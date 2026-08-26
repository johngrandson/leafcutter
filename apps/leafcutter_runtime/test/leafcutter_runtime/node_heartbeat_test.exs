defmodule LeafcutterRuntime.NodeHeartbeatTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Executions.RuntimeNode
  alias Leafcutter.Repo
  alias LeafcutterRuntime.NodeHeartbeat

  @heartbeat_event [:leafcutter, :runtime, :node, :heartbeat]
  @repo_query_event [:leafcutter, :repo, :query]

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "persists the initial durable heartbeat before start_link returns" do
    runtime_node_id = Ecto.UUID.generate()
    node_name = "initial-heartbeat@example"
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @repo_query_event,
        fn _event, _measurements, metadata, {test_process, node_name} ->
          if String.contains?(metadata.query, ~s(INSERT INTO "runtime_nodes")) and
               node_name in metadata.params do
            send(test_process, {:initial_heartbeat_persisting, self()})

            receive do
              :continue_initial_heartbeat -> :ok
            after
              1_000 -> raise "timed out while persisting the initial heartbeat"
            end
          end
        end,
        {test_process, node_name}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    start_task =
      Task.async(fn ->
        NodeHeartbeat.start_link(%{
          runtime_node_id: runtime_node_id,
          node_name: node_name,
          interval: 60_000,
          mode: :durable,
          name: nil
        })
      end)

    assert_receive {:initial_heartbeat_persisting, heartbeat_pid}, 500

    start_result = Task.yield(start_task, 0)
    send(heartbeat_pid, :continue_initial_heartbeat)

    assert start_result == nil
    assert {:ok, heartbeat_process} = Task.await(start_task, 500)
    assert %RuntimeNode{id: ^runtime_node_id} = Repo.get(RuntimeNode, runtime_node_id)

    GenServer.stop(heartbeat_process)
  end

  test "persists and emits periodic heartbeats for one runtime incarnation" do
    runtime_node_id = Ecto.UUID.generate()
    node_name = "leafcutter-test@host-1"
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @heartbeat_event,
        fn event, measurements, metadata, {test_process, runtime_node_id} ->
          if metadata.runtime_node_id == runtime_node_id do
            send(test_process, {:node_heartbeat, event, measurements, metadata})
          end
        end,
        {test_process, runtime_node_id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    heartbeat_pid =
      start_supervised!(
        {NodeHeartbeat,
         %{
           runtime_node_id: runtime_node_id,
           node_name: node_name,
           interval: 25,
           mode: :durable,
           name: nil
         }}
      )

    assert Process.alive?(heartbeat_pid)

    assert_receive {
                     :node_heartbeat,
                     @heartbeat_event,
                     %{system_time: first_system_time},
                     %{
                       node: heartbeat_node,
                       runtime_node_id: ^runtime_node_id
                     }
                   },
                   500

    assert is_integer(first_system_time)
    assert heartbeat_node == node()

    first_heartbeat = Repo.get!(RuntimeNode, runtime_node_id)
    assert first_heartbeat.node_name == node_name
    assert %DateTime{} = first_heartbeat.last_heartbeat_at

    assert_receive {
                     :node_heartbeat,
                     @heartbeat_event,
                     %{system_time: second_system_time},
                     %{
                       node: ^heartbeat_node,
                       runtime_node_id: ^runtime_node_id
                     }
                   },
                   500

    assert is_integer(second_system_time)
    assert second_system_time >= first_system_time

    second_heartbeat = Repo.get!(RuntimeNode, runtime_node_id)

    assert DateTime.compare(
             second_heartbeat.last_heartbeat_at,
             first_heartbeat.last_heartbeat_at
           ) == :gt
  end

  test "preserves the runtime incarnation identifier when the heartbeat process restarts" do
    original_pid = Process.whereis(NodeHeartbeat)
    original_runtime_node_id = NodeHeartbeat.runtime_node_id()
    monitor_ref = Process.monitor(original_pid)

    Process.exit(original_pid, :kill)

    assert_receive {:DOWN, ^monitor_ref, :process, ^original_pid, :killed}, 500

    restarted_pid = wait_for_restarted_process(original_pid, 50)

    assert restarted_pid != original_pid
    assert Process.alive?(restarted_pid)
    assert NodeHeartbeat.runtime_node_id() == original_runtime_node_id
  end

  @spec wait_for_restarted_process(pid(), non_neg_integer()) :: pid()
  defp wait_for_restarted_process(_original_pid, 0) do
    flunk("node heartbeat process did not restart")
  end

  defp wait_for_restarted_process(original_pid, attempts_remaining) do
    case Process.whereis(NodeHeartbeat) do
      pid when is_pid(pid) and pid != original_pid ->
        pid

      _other ->
        Process.sleep(10)
        wait_for_restarted_process(original_pid, attempts_remaining - 1)
    end
  end
end
