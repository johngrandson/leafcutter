defmodule Leafcutter.Executions.RunsRecoveryConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Nodes, Run, Runs, RuntimeNode}
  alias Leafcutter.Repo

  test "concurrent recovery claimants receive disjoint batches" do
    {runs, first_runtime_node, second_runtime_node} =
      create_recovery_scope()

    run_ids = Enum.map(runs, & &1.id)
    runtime_node_ids = [first_runtime_node.id, second_runtime_node.id]

    on_exit(fn ->
      delete_recovery_scope(run_ids, runtime_node_ids)
    end)

    first_task =
      recovery_task(first_runtime_node.id, self())

    second_task =
      recovery_task(second_runtime_node.id, self())

    assert_receive {:recovery_ready, first_process}, 1_000
    assert_receive {:recovery_ready, second_process}, 1_000

    send(first_process, :claim_recovery_batch)
    send(second_process, :claim_recovery_batch)

    assert {:ok, first_tokens} = Task.await(first_task)
    assert {:ok, second_tokens} = Task.await(second_task)

    assert length(first_tokens) == 3
    assert length(second_tokens) == 3

    first_ids = MapSet.new(first_tokens, & &1.run_id)
    second_ids = MapSet.new(second_tokens, & &1.run_id)

    assert MapSet.disjoint?(first_ids, second_ids)
    assert MapSet.union(first_ids, second_ids) == MapSet.new(run_ids)

    assert Enum.all?(first_tokens ++ second_tokens, fn ownership_token ->
             ownership_token.generation == 1
           end)
  end

  @spec recovery_task(RuntimeNode.id(), pid()) :: Task.t()
  defp recovery_task(runtime_node_id, test_process) do
    Task.async(fn ->
      with_unboxed_connection(fn ->
        send(test_process, {:recovery_ready, self()})

        receive do
          :claim_recovery_batch ->
            Runs.claim_recoverable(runtime_node_id, 3, [])
        after
          1_000 ->
            raise "timed out waiting to claim the recovery batch"
        end
      end)
    end)
  end

  @spec create_recovery_scope() ::
          {[Run.t()], RuntimeNode.t(), RuntimeNode.t()}
  defp create_recovery_scope do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, first_runtime_node} =
        Nodes.heartbeat(
          Ecto.UUID.generate(),
          "recovery-first-#{suffix}@example"
        )

      {:ok, second_runtime_node} =
        Nodes.heartbeat(
          Ecto.UUID.generate(),
          "recovery-second-#{suffix}@example"
        )

      runs =
        Enum.map(1..6, fn _index ->
          %Run{}
          |> Changeset.change(status: :running)
          |> Repo.insert!()
        end)

      {runs, first_runtime_node, second_runtime_node}
    end)
  end

  @spec with_unboxed_connection((-> result)) :: result when result: term()
  defp with_unboxed_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      :ok = Sandbox.checkin(Repo)
    end
  end

  @spec delete_recovery_scope([Run.id()], [RuntimeNode.id()]) :: :ok
  defp delete_recovery_scope(run_ids, runtime_node_ids) do
    with_unboxed_connection(fn ->
      Run
      |> where([run], run.id in ^run_ids)
      |> Repo.delete_all()

      RuntimeNode
      |> where(
        [runtime_node],
        runtime_node.id in ^runtime_node_ids
      )
      |> Repo.delete_all()

      :ok
    end)
  end
end
