defmodule Leafcutter.Executions.RunsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Leafcutter.Executions.RunFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Executions.{Nodes, Run, Runs, RuntimeNode}
  alias Leafcutter.Repo

  test "concurrent claimants produce one owner and one fencing generation" do
    {run, first_runtime_node, second_runtime_node} = create_claim_scope()

    on_exit(fn ->
      delete_claim_scope(
        run.id,
        [first_runtime_node.id, second_runtime_node.id]
      )
    end)

    pause_next_run_lock()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Runs.claim(run.id, first_runtime_node.id)
        end)
      end)

    assert_receive {:run_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Runs.claim(run.id, second_runtime_node.id)
        end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, first_token} = Task.await(first_task)
    assert first_token.generation == 1
    assert first_token.runtime_node_id == first_runtime_node.id

    assert {:error, :owned_by_active_node} = Task.await(second_task)

    persisted_run =
      with_unboxed_connection(fn -> Repo.get!(Run, run.id) end)

    assert persisted_run.owner_node_id == first_runtime_node.id
    assert persisted_run.generation == 1
  end

  @spec create_claim_scope() :: {Run.t(), RuntimeNode.t(), RuntimeNode.t()}
  defp create_claim_scope do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, first_runtime_node} =
        Nodes.heartbeat(
          Ecto.UUID.generate(),
          "claim-first-#{suffix}@example"
        )

      {:ok, second_runtime_node} =
        Nodes.heartbeat(
          Ecto.UUID.generate(),
          "claim-second-#{suffix}@example"
        )

      run = pending_run_fixture()

      {run, first_runtime_node, second_runtime_node}
    end)
  end

  @spec pause_next_run_lock() :: :ok
  defp pause_next_run_lock do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, {test_process, handler_id} ->
          if String.contains?(metadata.query, "FOR UPDATE") and
               String.contains?(metadata.query, ~s(FROM "runs")) do
            :telemetry.detach(handler_id)
            send(test_process, {:run_locked, self()})

            receive do
              :continue_transaction -> :ok
            after
              1_000 -> raise "timed out while holding the Run row lock"
            end
          end
        end,
        {test_process, handler_id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
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

  @spec delete_claim_scope(Run.id(), [RuntimeNode.id()]) :: :ok
  defp delete_claim_scope(run_id, runtime_node_ids) do
    with_unboxed_connection(fn ->
      Run
      |> where([run], run.id == ^run_id)
      |> Repo.delete_all()

      RuntimeNode
      |> where([runtime_node], runtime_node.id in ^runtime_node_ids)
      |> Repo.delete_all()

      :ok
    end)
  end
end
