defmodule LeafcutterRuntime.NodeHeartbeatTest do
  use ExUnit.Case, async: false

  @heartbeat_event [:leafcutter, :runtime, :node, :heartbeat]

  test "emits periodic heartbeat telemetry for the local node" do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @heartbeat_event,
        fn event, measurements, metadata, test_process ->
          send(test_process, {:node_heartbeat, event, measurements, metadata})
        end,
        test_process
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert_receive {
                     :node_heartbeat,
                     @heartbeat_event,
                     %{system_time: first_system_time},
                     %{node: heartbeat_node}
                   },
                   500

    assert is_integer(first_system_time)
    assert heartbeat_node == node()

    assert_receive {
                     :node_heartbeat,
                     @heartbeat_event,
                     %{system_time: second_system_time},
                     %{node: ^heartbeat_node}
                   },
                   500

    assert is_integer(second_system_time)
    assert second_system_time >= first_system_time
  end
end
