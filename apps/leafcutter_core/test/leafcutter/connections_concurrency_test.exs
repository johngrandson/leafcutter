defmodule Leafcutter.ConnectionsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Catalog.Connector
  alias Leafcutter.Catalog.Connectors, as: CatalogConnectors
  alias Leafcutter.Connections
  alias Leafcutter.Connections.Connection
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environment
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  test "Connection creation observes a concurrent Organization disable" do
    scope = persist_scope("Organization disable")
    on_exit(fn -> delete_scope(scope) end)

    pause_next_query("FOR UPDATE")

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Organizations.disable(scope.organization.id)
        end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    create_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Connections.create(connection_attrs(scope)) end)
      end)

    assert Task.yield(create_task, 100) == nil
    send(disable_process, :continue_query)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} =
             Task.await(disable_task)

    assert {:error, :organization_disabled} = Task.await(create_task)
  end

  test "Connection creation observes a concurrent Environment disable" do
    scope = persist_scope("Environment disable")
    on_exit(fn -> delete_scope(scope) end)

    pause_next_query("FOR UPDATE")

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Environments.disable(scope.environment.id)
        end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    create_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Connections.create(connection_attrs(scope)) end)
      end)

    assert Task.yield(create_task, 100) == nil
    send(disable_process, :continue_query)

    assert {:ok, %Environment{disabled_at: %DateTime{}}} =
             Task.await(disable_task)

    assert {:error, :environment_disabled} = Task.await(create_task)
  end

  test "concurrent Connection disables preserve one lifecycle timestamp" do
    scope = persist_scope("Connection disable")

    connection =
      with_unboxed_connection(fn ->
        {:ok, connection} = Connections.create(connection_attrs(scope))
        connection
      end)

    on_exit(fn -> delete_scope(scope) end)

    pause_next_query("FOR UPDATE")

    first_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Connections.disable(connection.id) end)
      end)

    assert_receive {:row_locked, first_disable_process}, 1_000

    second_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Connections.disable(connection.id) end)
      end)

    assert Task.yield(second_disable_task, 100) == nil
    send(first_disable_process, :continue_query)

    assert {:ok, first_disable} = Task.await(first_disable_task)
    assert {:ok, second_disable} = Task.await(second_disable_task)
    assert second_disable.disabled_at == first_disable.disabled_at
  end

  defp persist_scope(prefix) do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} =
        Organizations.create(%{name: "#{prefix} #{suffix}"})

      {:ok, environment} =
        Environments.create(%{
          organization_id: organization.id,
          name: "Production"
        })

      {:ok, connector} =
        CatalogConnectors.create(%{name: "Connector #{suffix}"})

      %{
        organization: organization,
        environment: environment,
        connector: connector
      }
    end)
  end

  defp connection_attrs(scope) do
    %{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      connector_id: scope.connector.id,
      name: "Connection",
      config: %{}
    }
  end

  defp pause_next_query(pattern) do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata,
           {test_process, handler_id, pattern} ->
          if String.contains?(metadata.query, pattern) do
            :telemetry.detach(handler_id)
            send(test_process, {:row_locked, self()})

            receive do
              :continue_query -> :ok
            after
              1_000 -> raise "timed out while holding a row lock"
            end
          end
        end,
        {test_process, handler_id, pattern}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp with_unboxed_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      :ok = Sandbox.checkin(Repo)
    end
  end

  defp delete_scope(scope) do
    with_unboxed_connection(fn ->
      Connection
      |> where([connection], connection.organization_id == ^scope.organization.id)
      |> Repo.delete_all()

      Environment
      |> where([environment], environment.id == ^scope.environment.id)
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^scope.organization.id)
      |> Repo.delete_all()

      Connector
      |> where([connector], connector.id == ^scope.connector.id)
      |> Repo.delete_all()
    end)
  end
end
