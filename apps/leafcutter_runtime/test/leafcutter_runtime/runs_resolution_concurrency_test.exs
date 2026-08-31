defmodule LeafcutterRuntime.RunsResolutionConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias Leafcutter.Connections
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias Leafcutter.Integrations.Deployments
  alias Leafcutter.Repo
  alias LeafcutterRuntime.ResolutionFixtures
  alias LeafcutterRuntime.Runs

  test "resolution freezes one coherent state while mutable authorities wait" do
    fixture =
      with_unboxed_connection(fn ->
        ResolutionFixtures.deployment_fixture("Concurrent Resolution")
      end)

    on_exit(fn ->
      with_unboxed_connection(fn ->
        ResolutionFixtures.delete_persisted_fixture(fixture)
      end)
    end)

    pause_next_snapshot_insert()

    resolution_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Runs.create_from_deployment(fixture.deployment.id)
        end)
      end)

    assert_receive {:resolution_paused, resolution_process}, 2_000
    on_exit(fn -> send(resolution_process, :continue_resolution) end)

    connection_update_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Connections.update(fixture.source_connection.id, %{
            config: %{"endpoint" => "source-v2"}
          })
        end)
      end)

    deployment_replace_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Deployments.replace(fixture.deployment.id, %{
            package_version_id: fixture.package_version.id,
            promotable_config: %{revision: "replacement-promotable"},
            local_config: %{revision: "replacement-local"},
            bindings: [
              %{ref: "crm", connection_id: fixture.crm_connection.id},
              %{ref: "source", connection_id: fixture.source_connection.id},
              %{
                ref: "warehouse",
                connection_id: fixture.warehouse_connection.id
              }
            ]
          })
        end)
      end)

    assert Task.yield(connection_update_task, 100) == nil
    assert Task.yield(deployment_replace_task, 100) == nil

    send(resolution_process, :continue_resolution)

    assert {:ok, run} = Task.await(resolution_task)
    assert {:ok, updated_connection} = Task.await(connection_update_task)
    assert {:ok, replaced_deployment} = Task.await(deployment_replace_task)

    assert {:ok, snapshot} =
             with_unboxed_connection(fn -> DurableRuns.fetch_snapshot(run.id) end)

    assert get_in(snapshot.definition, ["source", "connection", "config"]) == %{
             "endpoint" => "source-v1"
           }

    assert snapshot.definition["effective_config"] == %{
             "batch" => %{"mode" => "bulk", "size" => 25},
             "local_only" => true,
             "nullable" => nil,
             "promotable_only" => true,
             "regions" => ["eu-west-1"]
           }

    assert updated_connection.config == %{"endpoint" => "source-v2"}

    assert replaced_deployment.promotable_config == %{
             "revision" => "replacement-promotable"
           }

    assert replaced_deployment.local_config == %{
             "revision" => "replacement-local"
           }
  end

  defp pause_next_snapshot_insert do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, {test_process, handler_id} ->
          if String.contains?(metadata.query, ~s(INSERT INTO "run_snapshots")) do
            :telemetry.detach(handler_id)
            send(test_process, {:resolution_paused, self()})

            receive do
              :continue_resolution -> :ok
            after
              2_000 -> raise "timed out while holding resolution authority locks"
            end
          end
        end,
        {test_process, handler_id}
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
end
