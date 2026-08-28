defmodule LeafcutterRuntime.RunsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Executions.{Nodes, Run, RuntimeNode}
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias Leafcutter.Repo

  alias LeafcutterRuntime.{
    NodeHeartbeat,
    RunDynamicSupervisor,
    RunRegistry,
    Runs
  }

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    runtime_node_id = NodeHeartbeat.runtime_node_id()

    assert {:ok, _runtime_node} =
             Nodes.heartbeat(
               runtime_node_id,
               unique_node_name("local-runtime")
             )

    {:ok, runtime_node_id: runtime_node_id}
  end

  describe "start/1" do
    test "claims a Run and starts one idempotent local tree", %{
      runtime_node_id: runtime_node_id
    } do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, first_supervisor_pid} = Runs.start(run.id)
      assert {:ok, second_supervisor_pid} = Runs.start(run.id)
      assert second_supervisor_pid == first_supervisor_pid

      run_id = run.id

      assert {:ok,
              %{
                run_supervisor_pid: ^first_supervisor_pid,
                ownership_token:
                  %{
                    run_id: ^run_id,
                    runtime_node_id: ^runtime_node_id,
                    generation: 1
                  } = ownership_token
              }} = Runs.lookup(run.id)

      assert [{^first_supervisor_pid, ^ownership_token}] =
               Registry.lookup(RunRegistry, run.id)

      assert [{coordinator_pid, ^ownership_token}] =
               Registry.lookup(
                 RunRegistry,
                 {:coordinator, run.id}
               )

      assert Process.alive?(first_supervisor_pid)
      assert Process.alive?(coordinator_pid)
    end

    test "replaces an older local generation after a fresh claim" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, first_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: first_token}} = Runs.lookup(run.id)
      assert :ok = DurableRuns.release(first_token)

      assert {:ok, second_supervisor_pid} = Runs.start(run.id)
      assert second_supervisor_pid != first_supervisor_pid

      assert {:ok, %{ownership_token: second_token}} = Runs.lookup(run.id)
      assert second_token.generation == first_token.generation + 1
      assert second_token.runtime_node_id == first_token.runtime_node_id

      refute Process.alive?(first_supervisor_pid)
      assert Process.alive?(second_supervisor_pid)
    end

    test "removes a local stale tree when another active node owns the Run" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, _run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: local_token}} = Runs.lookup(run.id)
      assert :ok = DurableRuns.release(local_token)

      other_runtime_node = create_runtime_node("other-owner")

      assert {:ok, other_token} =
               DurableRuns.claim(run.id, other_runtime_node.id)

      assert {:error, :owned_by_active_node} = Runs.start(run.id)
      assert :ok = wait_until_not_running(run.id, 50)

      persisted_run = Repo.get!(Run, run.id)
      assert persisted_run.owner_node_id == other_token.runtime_node_id
      assert persisted_run.generation == other_token.generation
    end

    test "serializes local lifecycle operations for the same Run" do
      run = insert_run()
      register_cleanup(run.id)
      operation_lock_key = {:run_operation, run.id}

      assert {:ok, _owner} =
               Registry.register(
                 RunRegistry,
                 operation_lock_key,
                 :test_lock
               )

      start_task = Task.async(fn -> Runs.start(run.id) end)
      yielded_result = Task.yield(start_task, 200)

      Registry.unregister(RunRegistry, operation_lock_key)

      start_result =
        case yielded_result do
          nil -> Task.await(start_task, 500)
          {:ok, result} -> result
        end

      assert yielded_result == nil
      assert {:ok, run_supervisor_pid} = start_result
      assert Process.alive?(run_supervisor_pid)
    end

    test "releases durable ownership when the dynamic supervisor is unavailable" do
      run = insert_run()
      register_cleanup(run.id)

      assert :ok =
               Supervisor.terminate_child(
                 LeafcutterRuntime.Supervisor,
                 RunDynamicSupervisor
               )

      on_exit(&restart_run_dynamic_supervisor/0)

      assert {:error, {:run_supervisor_start_failed, _reason}} =
               Runs.start(run.id)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :running
      assert persisted_run.owner_node_id == nil
      assert persisted_run.ownership_acquired_at == nil
      assert persisted_run.generation == 1
    end
  end

  describe "stop/1" do
    test "releases ownership and terminates the complete local tree" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: ownership_token}} = Runs.lookup(run.id)

      assert :ok = Runs.stop(run.id)
      assert :ok = wait_until_not_running(run.id, 50)
      refute Process.alive?(run_supervisor_pid)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :running
      assert persisted_run.owner_node_id == nil
      assert persisted_run.ownership_acquired_at == nil
      assert persisted_run.generation == ownership_token.generation

      assert :ok = Runs.stop(run.id)
    end

    test "terminates the local tree when durable release reports stale ownership" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: local_token}} = Runs.lookup(run.id)
      assert :ok = DurableRuns.release(local_token)

      other_runtime_node = create_runtime_node("stop-stale-owner")

      assert {:ok, current_token} =
               DurableRuns.claim(run.id, other_runtime_node.id)

      assert {:error, :stale_ownership} = Runs.stop(run.id)
      assert :ok = wait_until_not_running(run.id, 50)
      refute Process.alive?(run_supervisor_pid)

      persisted_run = Repo.get!(Run, run.id)
      assert persisted_run.owner_node_id == current_token.runtime_node_id
      assert persisted_run.generation == current_token.generation
    end
  end

  describe "RunCoordinator supervision" do
    test "restarts the coordinator after an abnormal crash while preserving the token" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: ownership_token}} = Runs.lookup(run.id)

      first_coordinator_pid = coordinator_pid(run.id, ownership_token)
      monitor_ref = Process.monitor(first_coordinator_pid)

      Process.exit(first_coordinator_pid, :kill)

      assert_receive {
                       :DOWN,
                       ^monitor_ref,
                       :process,
                       ^first_coordinator_pid,
                       :killed
                     },
                     500

      second_coordinator_pid =
        wait_for_restarted_coordinator(
          run.id,
          ownership_token,
          first_coordinator_pid,
          50
        )

      assert second_coordinator_pid != first_coordinator_pid
      assert Process.alive?(second_coordinator_pid)
      assert Process.alive?(run_supervisor_pid)

      assert {:ok,
              %{
                run_supervisor_pid: ^run_supervisor_pid,
                ownership_token: ^ownership_token
              }} = Runs.lookup(run.id)
    end

    test "stale ownership shuts down the matching local tree without releasing a newer owner" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, _run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: first_token}} = Runs.lookup(run.id)
      assert :ok = DurableRuns.release(first_token)

      recovery_runtime_node = create_runtime_node("recovery-owner")

      assert {:ok, second_token} =
               DurableRuns.claim(run.id, recovery_runtime_node.id)

      assert second_token.generation == first_token.generation + 1

      assert :ok = Runs.stale_ownership(first_token)
      assert :ok = wait_until_not_running(run.id, 50)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.owner_node_id == second_token.runtime_node_id
      assert persisted_run.generation == second_token.generation
      assert %DateTime{} = persisted_run.ownership_acquired_at
    end

    test "a stale report from another generation does not stop the current tree" do
      run = insert_run()
      register_cleanup(run.id)

      assert {:ok, run_supervisor_pid} = Runs.start(run.id)
      assert {:ok, %{ownership_token: ownership_token}} = Runs.lookup(run.id)

      other_generation_token = %{
        ownership_token
        | generation: ownership_token.generation + 1
      }

      assert :ok = Runs.stale_ownership(other_generation_token)
      Process.sleep(25)

      assert {:ok,
              %{
                run_supervisor_pid: ^run_supervisor_pid,
                ownership_token: ^ownership_token
              }} = Runs.lookup(run.id)
    end
  end

  @spec insert_run() :: Run.t()
  defp insert_run do
    {:ok, run} = DurableRuns.create(definition_fixture())
    run
  end

  @spec definition_fixture() :: map()
  defp definition_fixture do
    %{
      "package_version_id" => Ecto.UUID.generate(),
      "source" => %{
        "ref" => "source",
        "contract_version_id" => Ecto.UUID.generate(),
        "connection" => %{
          "id" => Ecto.UUID.generate(),
          "config" => %{},
          "secret_version_id" => nil
        }
      },
      "destinations" => [
        %{
          "ref" => "destination",
          "contract_version_id" => Ecto.UUID.generate(),
          "connection" => %{
            "id" => Ecto.UUID.generate(),
            "config" => %{},
            "secret_version_id" => nil
          }
        }
      ],
      "effective_config" => %{}
    }
  end

  @spec create_runtime_node(String.t()) :: RuntimeNode.t()
  defp create_runtime_node(prefix) do
    runtime_node_id = Ecto.UUID.generate()

    {:ok, runtime_node} =
      Nodes.heartbeat(
        runtime_node_id,
        unique_node_name(prefix)
      )

    runtime_node
  end

  @spec coordinator_pid(
          Run.id(),
          DurableRuns.ownership_token()
        ) :: pid()
  defp coordinator_pid(run_id, ownership_token) do
    case Registry.lookup(RunRegistry, {:coordinator, run_id}) do
      [{coordinator_pid, ^ownership_token}] ->
        coordinator_pid

      _other ->
        flunk("matching Run coordinator was not registered")
    end
  end

  @spec wait_for_restarted_coordinator(
          Run.id(),
          DurableRuns.ownership_token(),
          pid(),
          non_neg_integer()
        ) :: pid()
  defp wait_for_restarted_coordinator(
         _run_id,
         _ownership_token,
         _original_pid,
         0
       ) do
    flunk("Run coordinator did not restart")
  end

  defp wait_for_restarted_coordinator(
         run_id,
         ownership_token,
         original_pid,
         attempts_remaining
       ) do
    case Registry.lookup(RunRegistry, {:coordinator, run_id}) do
      [{coordinator_pid, ^ownership_token}]
      when coordinator_pid != original_pid ->
        coordinator_pid

      _other ->
        Process.sleep(10)

        wait_for_restarted_coordinator(
          run_id,
          ownership_token,
          original_pid,
          attempts_remaining - 1
        )
    end
  end

  @spec wait_until_not_running(Run.id(), non_neg_integer()) :: :ok
  defp wait_until_not_running(_run_id, 0) do
    flunk("local Run tree did not terminate")
  end

  defp wait_until_not_running(run_id, attempts_remaining) do
    case Runs.lookup(run_id) do
      :error ->
        :ok

      {:ok, _local_run} ->
        Process.sleep(10)
        wait_until_not_running(run_id, attempts_remaining - 1)
    end
  end

  @spec register_cleanup(Run.id()) :: :ok
  defp register_cleanup(run_id) do
    on_exit(fn -> Runs.stop(run_id) end)
  end

  @spec restart_run_dynamic_supervisor() :: :ok
  defp restart_run_dynamic_supervisor do
    case Supervisor.restart_child(
           LeafcutterRuntime.Supervisor,
           RunDynamicSupervisor
         ) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
      {:error, :running} -> :ok
    end
  end

  @spec unique_node_name(String.t()) :: String.t()
  defp unique_node_name(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}@example"
  end
end
