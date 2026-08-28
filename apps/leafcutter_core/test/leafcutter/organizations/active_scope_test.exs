defmodule Leafcutter.Organizations.ActiveScopeTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments

  test "locks and returns an active matching scope inside a transaction" do
    {:ok, organization} = Organizations.create(%{name: "Organization"})

    {:ok, environment} =
      Environments.create(%{
        organization_id: organization.id,
        name: "Production"
      })

    assert {:ok, {:ok, scope}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 organization.id,
                 environment.id
               )
             end)

    assert scope.organization.id == organization.id
    assert scope.environment.id == environment.id
  end

  test "requires a caller-owned transaction" do
    assert {:error, :transaction_required} =
             Environments.lock_active_scope(
               "00000000-0000-0000-0000-000000000000",
               "00000000-0000-0000-0000-000000000000"
             )
  end

  test "classifies missing, incompatible, and disabled scope" do
    {:ok, first_organization} = Organizations.create(%{name: "First"})
    {:ok, second_organization} = Organizations.create(%{name: "Second"})

    {:ok, first_environment} =
      Environments.create(%{
        organization_id: first_organization.id,
        name: "Production"
      })

    {:ok, second_environment} =
      Environments.create(%{
        organization_id: second_organization.id,
        name: "Production"
      })

    assert {:ok, {:error, :organization_not_found}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 Ecto.UUID.generate(),
                 first_environment.id
               )
             end)

    assert {:ok, {:error, :environment_not_found}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 first_organization.id,
                 Ecto.UUID.generate()
               )
             end)

    assert {:ok, {:error, :environment_scope_mismatch}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 first_organization.id,
                 second_environment.id
               )
             end)

    assert {:ok, _environment} = Environments.disable(first_environment.id)

    assert {:ok, {:error, :environment_disabled}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 first_organization.id,
                 first_environment.id
               )
             end)

    assert {:ok, _organization} = Organizations.disable(second_organization.id)

    assert {:ok, {:error, :organization_disabled}} =
             Repo.transaction(fn ->
               Environments.lock_active_scope(
                 second_organization.id,
                 second_environment.id
               )
             end)
  end
end
