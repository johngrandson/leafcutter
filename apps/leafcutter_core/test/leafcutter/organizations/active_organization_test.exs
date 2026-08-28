defmodule Leafcutter.Organizations.ActiveOrganizationTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations

  test "locks and returns an active Organization inside a transaction" do
    {:ok, organization} = Organizations.create(%{name: "Organization"})

    assert {:ok, {:ok, locked_organization}} =
             Repo.transaction(fn ->
               Organizations.lock_active(organization.id)
             end)

    assert locked_organization.id == organization.id
  end

  test "requires a caller-owned transaction" do
    assert {:error, :transaction_required} =
             Organizations.lock_active(
               "00000000-0000-0000-0000-000000000000"
             )
  end

  test "classifies a missing or disabled Organization" do
    {:ok, organization} = Organizations.create(%{name: "Organization"})

    assert {:ok, {:error, :organization_not_found}} =
             Repo.transaction(fn ->
               Organizations.lock_active(Ecto.UUID.generate())
             end)

    assert {:ok, _disabled_organization} =
             Organizations.disable(organization.id)

    assert {:ok, {:error, :organization_disabled}} =
             Repo.transaction(fn ->
               Organizations.lock_active(organization.id)
             end)
  end
end
