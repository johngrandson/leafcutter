defmodule LeafcutterRuntime.RunRecoveryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Nodes, Run, RuntimeNode}
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias Leafcutter.Repo

  alias LeafcutterRuntime.{
    RunRecovery,
    RunRegistry,
    Runs
  }

  @typep run_attrs :: %{
           optional(:status) => Run.status()
         }

  @typep recovery_overrides :: %{
           optional(:initial_backoff) => pos_integer(),
           optional(:max_backoff) => pos_integer()
         }

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    runtime_node = create_active_runtime_node("recovery-runtime")

    {:ok, runtime_node: runtime_node}
  end

  test "recovers unowned running Runs without starting pending Runs", %{
    runtime_node: runtime_node
  } do
    running_run = insert_run(%{status: :running})
    pending_run = insert_run()

    register_cleanup(running_run.id)
    register_cleanup(pending_run.id)

    recovery_pid = start_recovery(runtime_node.id)
    send(recovery_pid, :scan)

    local_run = wait_for_local_run(running_run.id, 100)

    assert local_run.ownership_token.runtime_node_id == runtime_node.id
    assert local_run.ownership_token.generation == 1
    assert Runs.lookup(pending_run.id) == :error

    persisted_pending_run = Repo.get!(Run, pending_run.id)
    assert persisted_pending_run.status == :pending
    assert persisted_pending_run.owner_node_id == nil
  end

  test "reconstructs an already-owned Run without incrementing generation", %{
    runtime_node: runtime_node
  } do
    run = insert_run()
    register_cleanup(run.id)

    assert {:ok, ownership_token} =
             DurableRuns.claim(run.id, runtime_node.id)

    recovery_pid = start_recovery(runtime_node.id)
    send(recovery_pid, :scan)

    local_run = wait_for_local_run(run.id, 100)
    assert local_run.ownership_token == ownership_token

    persisted_run = Repo.get!(Run, run.id)
    assert persisted_run.generation == ownership_token.generation
    assert persisted_run.owner_node_id == runtime_node.id
  end

  test "replaces a stale local generation with the current durable token", %{
    runtime_node: runtime_node
  } do
    previous_runtime_node =
      create_active_runtime_node("recovery-previous-runtime")

    run = insert_run()
    register_cleanup(run.id)

    assert {:ok, previous_token} =
             DurableRuns.claim(run.id, previous_runtime_node.id)

    assert {:ok, previous_supervisor_pid} =
             Runs.start_claimed(previous_token)

    assert :ok = DurableRuns.release(previous_token)

    assert {:ok, current_token} =
             DurableRuns.claim(run.id, runtime_node.id)

    recovery_pid = start_recovery(runtime_node.id)
    send(recovery_pid, :scan)

    current_local_run =
      wait_for_local_token(run.id, current_token, 100)

    assert current_local_run.run_supervisor_pid != previous_supervisor_pid
    refute Process.alive?(previous_supervisor_pid)
    assert current_token.generation == previous_token.generation + 1
  end

  test "backs off one failed local startup while continuing other Runs", %{
    runtime_node: runtime_node
  } do
    blocked_run = insert_run(%{status: :running})
    healthy_run = insert_run(%{status: :running})

    register_cleanup(blocked_run.id)
    register_cleanup(healthy_run.id)

    startup_blocker = register_startup_blocker(blocked_run.id)
    on_exit(fn -> send(startup_blocker, :stop) end)

    recovery_pid =
      start_recovery(
        runtime_node.id,
        %{
          initial_backoff: 1_000,
          max_backoff: 4_000
        }
      )

    send(recovery_pid, :scan)

    _healthy_local_run = wait_for_local_run(healthy_run.id, 100)
    wait_for_released_run(blocked_run.id, 100)

    first_failed_attempt = Repo.get!(Run, blocked_run.id)
    assert first_failed_attempt.owner_node_id == nil
    assert first_failed_attempt.generation == 1

    send(recovery_pid, :scan)
    Process.sleep(100)

    second_observation = Repo.get!(Run, blocked_run.id)
    assert second_observation.owner_node_id == nil
    assert second_observation.generation == 1
  end

  test "graceful recovery shutdown releases local ownership", %{
    runtime_node: runtime_node
  } do
    run = insert_run(%{status: :running})
    register_cleanup(run.id)

    recovery_pid = start_recovery(runtime_node.id)
    send(recovery_pid, :scan)

    _local_run = wait_for_local_run(run.id, 100)

    assert :ok =
             stop_supervised({RunRecovery, runtime_node.id})

    assert :ok = wait_until_not_local(run.id, 100)

    persisted_run = Repo.get!(Run, run.id)
    assert persisted_run.status == :running
    assert persisted_run.owner_node_id == nil
    assert persisted_run.ownership_acquired_at == nil
    assert persisted_run.generation == 1
  end

  test "a failed scan is retried without crashing the recovery process" do
    missing_runtime_node_id = Ecto.UUID.generate()

    recovery_pid =
      start_recovery(
        missing_runtime_node_id,
        %{
          initial_backoff: 25,
          max_backoff: 100
        }
      )

    send(recovery_pid, :scan)
    Process.sleep(75)

    assert Process.alive?(recovery_pid)
  end

  @spec start_recovery(RuntimeNode.id(), recovery_overrides()) :: pid()
  defp start_recovery(runtime_node_id, overrides \\ %{}) do
    options =
      Map.merge(
        %{
          runtime_node_id: runtime_node_id,
          enabled: true,
          name: nil,
          initial_delay: 60_000,
          scan_interval: 60_000,
          batch_size: 25,
          drain_delay: 60_000,
          initial_backoff: 1_000,
          max_backoff: 8_000
        },
        overrides
      )

    start_supervised!({RunRecovery, options})
  end

  @spec insert_run(run_attrs()) :: Run.t()
  defp insert_run(attrs \\ %{}) do
    %Run{}
    |> Changeset.change(attrs)
    |> Repo.insert!()
  end

  @spec create_active_runtime_node(String.t()) :: RuntimeNode.t()
  defp create_active_runtime_node(prefix) do
    runtime_node_id = Ecto.UUID.generate()

    {:ok, runtime_node} =
      Nodes.heartbeat(
        runtime_node_id,
        "#{prefix}-#{System.unique_integer([:positive])}@example"
      )

    runtime_node
  end

  @spec register_startup_blocker(Run.id()) :: pid()
  defp register_startup_blocker(run_id) do
    test_process = self()

    {:ok, blocker_pid} =
      Task.start_link(fn ->
        {:ok, _owner} =
          Registry.register(
            RunRegistry,
            run_id,
            :startup_blocker
          )

        send(test_process, {:startup_blocker_ready, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:startup_blocker_ready, ^blocker_pid}, 500
    blocker_pid
  end

  @spec wait_for_local_run(Run.id(), non_neg_integer()) :: Runs.local_run()
  defp wait_for_local_run(_run_id, 0) do
    flunk("Run recovery did not start the local tree")
  end

  defp wait_for_local_run(run_id, attempts_remaining) do
    case Runs.lookup(run_id) do
      {:ok, local_run} ->
        local_run

      :error ->
        Process.sleep(10)
        wait_for_local_run(run_id, attempts_remaining - 1)
    end
  end

  @spec wait_for_local_token(
          Run.id(),
          DurableRuns.ownership_token(),
          non_neg_integer()
        ) :: Runs.local_run()
  defp wait_for_local_token(_run_id, _ownership_token, 0) do
    flunk("Run recovery did not converge to the durable ownership token")
  end

  defp wait_for_local_token(run_id, ownership_token, attempts_remaining) do
    case Runs.lookup(run_id) do
      {:ok, %{ownership_token: ^ownership_token} = local_run} ->
        local_run

      _not_current ->
        Process.sleep(10)

        wait_for_local_token(
          run_id,
          ownership_token,
          attempts_remaining - 1
        )
    end
  end

  @spec wait_for_released_run(Run.id(), non_neg_integer()) :: :ok
  defp wait_for_released_run(_run_id, 0) do
    flunk("failed Run startup did not release durable ownership")
  end

  defp wait_for_released_run(run_id, attempts_remaining) do
    case Repo.get!(Run, run_id) do
      %Run{owner_node_id: nil, generation: generation}
      when generation > 0 ->
        :ok

      %Run{} ->
        Process.sleep(10)
        wait_for_released_run(run_id, attempts_remaining - 1)
    end
  end

  @spec wait_until_not_local(Run.id(), non_neg_integer()) :: :ok
  defp wait_until_not_local(_run_id, 0) do
    flunk("local Run tree did not terminate")
  end

  defp wait_until_not_local(run_id, attempts_remaining) do
    case Runs.lookup(run_id) do
      :error ->
        :ok

      {:ok, _local_run} ->
        Process.sleep(10)
        wait_until_not_local(run_id, attempts_remaining - 1)
    end
  end

  @spec register_cleanup(Run.id()) :: :ok
  defp register_cleanup(run_id) do
    on_exit(fn -> Runs.stop(run_id) end)
  end
end
