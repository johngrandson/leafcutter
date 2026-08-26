defmodule LeafcutterRuntime.ApplicationTest do
  use ExUnit.Case, async: false

  test "starts the runtime infrastructure processes" do
    assert LeafcutterRuntime.Supervisor |> Process.whereis() |> is_pid()
    assert LeafcutterRuntime.RunRegistry |> Process.whereis() |> is_pid()
    assert LeafcutterRuntime.RunDynamicSupervisor |> Process.whereis() |> is_pid()
    assert LeafcutterRuntime.NodeHeartbeat |> Process.whereis() |> is_pid()

    refute LeafcutterRuntime.RunRecovery |> Process.whereis() |> is_pid()

    assert {:ok, _runtime_node_id} =
             LeafcutterRuntime.NodeHeartbeat.runtime_node_id()
             |> Ecto.UUID.cast()
  end

  test "RunRegistry provides unique local registration" do
    run_id = {:test_run, System.unique_integer([:positive])}

    assert {:ok, _owner} =
             Registry.register(
               LeafcutterRuntime.RunRegistry,
               run_id,
               :test_run
             )

    assert [{owner, :test_run}] =
             Registry.lookup(LeafcutterRuntime.RunRegistry, run_id)

    assert owner == self()

    assert {:error, {:already_registered, ^owner}} =
             Registry.register(
               LeafcutterRuntime.RunRegistry,
               run_id,
               :duplicate
             )
  end

  test "RunDynamicSupervisor starts and terminates dynamic children" do
    child_spec =
      {Task,
       fn ->
         receive do
           :stop -> :ok
         end
       end}

    assert {:ok, child_pid} =
             DynamicSupervisor.start_child(
               LeafcutterRuntime.RunDynamicSupervisor,
               child_spec
             )

    assert Process.alive?(child_pid)

    assert :ok =
             DynamicSupervisor.terminate_child(
               LeafcutterRuntime.RunDynamicSupervisor,
               child_pid
             )

    refute Process.alive?(child_pid)
  end
end
