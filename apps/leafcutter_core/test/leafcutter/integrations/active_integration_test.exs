defmodule Leafcutter.Integrations.ActiveIntegrationTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Catalog.Packages
  alias Leafcutter.Integrations
  alias Leafcutter.Organizations

  test "locks and returns an active Integration in its Organization" do
    scope = scope_fixture("Scope")

    assert {:ok, {:ok, integration}} =
             Repo.transaction(fn ->
               Integrations.lock_active(
                 scope.integration.id,
                 scope.organization.id
               )
             end)

    assert integration.id == scope.integration.id
  end

  test "requires a caller-owned transaction" do
    assert {:error, :transaction_required} =
             Integrations.lock_active(
               Ecto.UUID.generate(),
               Ecto.UUID.generate()
             )
  end

  test "classifies missing, scope-incompatible, and disabled Integrations" do
    first_scope = scope_fixture("First")
    second_scope = scope_fixture("Second")

    assert {:ok, {:error, :integration_not_found}} =
             Repo.transaction(fn ->
               Integrations.lock_active(
                 Ecto.UUID.generate(),
                 first_scope.organization.id
               )
             end)

    assert {:ok, {:error, :integration_scope_mismatch}} =
             Repo.transaction(fn ->
               Integrations.lock_active(
                 second_scope.integration.id,
                 first_scope.organization.id
               )
             end)

    assert {:ok, _disabled_integration} =
             Integrations.disable(first_scope.integration.id)

    assert {:ok, {:error, :integration_disabled}} =
             Repo.transaction(fn ->
               Integrations.lock_active(
                 first_scope.integration.id,
                 first_scope.organization.id
               )
             end)
  end

  defp scope_fixture(prefix) do
    {:ok, organization} =
      Organizations.create(%{name: "#{prefix} Organization"})

    {:ok, package} = Packages.create(%{name: "#{prefix} Package"})

    {:ok, integration} =
      Integrations.create(%{
        organization_id: organization.id,
        package_id: package.id,
        name: "#{prefix} Integration"
      })

    %{
      organization: organization,
      package: package,
      integration: integration
    }
  end
end
