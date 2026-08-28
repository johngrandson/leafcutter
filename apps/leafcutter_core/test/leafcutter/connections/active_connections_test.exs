defmodule Leafcutter.Connections.ActiveConnectionsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Catalog.Connectors, as: CatalogConnectors
  alias Leafcutter.Connections
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments

  test "locks unique active Connections in deterministic identifier order" do
    scope = scope_fixture("Scope")
    first = connection_fixture(scope, "First")
    second = connection_fixture(scope, "Second")

    ids = [second.id, first.id, second.id]

    assert {:ok, {:ok, connections}} =
             Repo.transaction(fn ->
               Connections.lock_active(
                 ids,
                 scope.organization.id,
                 scope.environment.id
               )
             end)

    assert Enum.map(connections, & &1.id) ==
             [first.id, second.id] |> Enum.sort()
  end

  test "requires a caller-owned transaction" do
    assert {:error, :transaction_required} =
             Connections.lock_active(
               [],
               Ecto.UUID.generate(),
               Ecto.UUID.generate()
             )
  end

  test "classifies missing, scope-incompatible, and disabled Connections" do
    first_scope = scope_fixture("First")
    second_scope = scope_fixture("Second")
    first_connection = connection_fixture(first_scope, "First")
    second_connection = connection_fixture(second_scope, "Second")
    missing_id = Ecto.UUID.generate()

    assert {:ok, {:error, {:connection_not_found, ^missing_id}}} =
             Repo.transaction(fn ->
               Connections.lock_active(
                 [missing_id],
                 first_scope.organization.id,
                 first_scope.environment.id
               )
             end)

    assert {:ok,
            {:error,
             {:connection_scope_mismatch, second_connection_id}}} =
             Repo.transaction(fn ->
               Connections.lock_active(
                 [second_connection.id],
                 first_scope.organization.id,
                 first_scope.environment.id
               )
             end)

    assert second_connection_id == second_connection.id

    assert {:ok, _disabled_connection} =
             Connections.disable(first_connection.id)

    assert {:ok, {:error, {:connection_disabled, first_connection_id}}} =
             Repo.transaction(fn ->
               Connections.lock_active(
                 [first_connection.id],
                 first_scope.organization.id,
                 first_scope.environment.id
               )
             end)

    assert first_connection_id == first_connection.id
  end

  defp scope_fixture(prefix) do
    {:ok, organization} =
      Organizations.create(%{name: "#{prefix} Organization"})

    {:ok, environment} =
      Environments.create(%{
        organization_id: organization.id,
        name: "Production"
      })

    {:ok, connector} =
      CatalogConnectors.create(%{name: "#{prefix} Connector"})

    %{
      organization: organization,
      environment: environment,
      connector: connector
    }
  end

  defp connection_fixture(scope, name) do
    {:ok, connection} =
      Connections.create(%{
        organization_id: scope.organization.id,
        environment_id: scope.environment.id,
        connector_id: scope.connector.id,
        name: name,
        config: %{}
      })

    connection
  end
end
