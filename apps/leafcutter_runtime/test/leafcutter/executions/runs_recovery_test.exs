defmodule Leafcutter.Executions.RunsRecoveryTest do
  use ExUnit.Case, async: true

  import Leafcutter.Executions.RunFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Nodes, Run, Runs, RunSnapshot, RuntimeNode}
  alias Leafcutter.Repo

  @typep run_attrs :: %{
           optional(:status) => Run.status(),
           optional(:inserted_at) => DateTime.t(),
           optional(:updated_at) => DateTime.t()
         }

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "list_owned_tokens/1" do
    test "lists only running Runs currently owned by the runtime incarnation" do
      runtime_node = create_active_runtime_node("owned-list")
      other_runtime_node = create_active_runtime_node("owned-list-other")

      owned_run = pending_run_fixture()
      released_run = pending_run_fixture()
      other_run = pending_run_fixture()

      assert {:ok, owned_token} = Runs.claim(owned_run.id, runtime_node.id)

      assert {:ok, released_token} =
               Runs.claim(released_run.id, runtime_node.id)

      assert :ok = Runs.release(released_token)
      assert {:ok, _other_token} = Runs.claim(other_run.id, other_runtime_node.id)

      assert [^owned_token] = Runs.list_owned_tokens(runtime_node.id)
    end
  end

  describe "claim_recoverable/3" do
    test "claims recoverable running and eligible pending Runs" do
      claimant = create_active_runtime_node("recovery-claimant")
      stale_owner = create_active_runtime_node("recovery-stale-owner")
      active_owner = create_active_runtime_node("recovery-active-owner")

      unowned_run = insert_run(%{status: :running})
      stale_run = pending_run_fixture()
      active_run = pending_run_fixture()
      eligible_pending_run = pending_run_fixture()
      missing_snapshot_pending_run = insert_run()
      unsupported_snapshot_pending_run = insert_run()
      _snapshot = insert_snapshot(unsupported_snapshot_pending_run, 999)
      completed_run = insert_run(%{status: :completed})

      assert {:ok, stale_token} = Runs.claim(stale_run.id, stale_owner.id)
      assert {:ok, active_token} = Runs.claim(active_run.id, active_owner.id)
      expire_runtime_node(stale_owner)

      assert {:ok, ownership_tokens} =
               Runs.claim_recoverable(claimant.id, 10, [])

      tokens_by_run =
        Map.new(ownership_tokens, fn ownership_token ->
          {ownership_token.run_id, ownership_token}
        end)

      claimed_run_ids =
        tokens_by_run
        |> Map.keys()
        |> MapSet.new()

      assert claimed_run_ids ==
               MapSet.new([
                 unowned_run.id,
                 stale_run.id,
                 eligible_pending_run.id
               ])

      assert tokens_by_run[unowned_run.id].runtime_node_id == claimant.id
      assert tokens_by_run[unowned_run.id].generation == 1
      assert tokens_by_run[stale_run.id].runtime_node_id == claimant.id
      assert tokens_by_run[stale_run.id].generation == stale_token.generation + 1

      assert tokens_by_run[eligible_pending_run.id].runtime_node_id ==
               claimant.id

      assert tokens_by_run[eligible_pending_run.id].generation == 1

      persisted_active_run = Repo.get!(Run, active_run.id)
      assert persisted_active_run.owner_node_id == active_token.runtime_node_id
      assert persisted_active_run.generation == active_token.generation

      persisted_eligible_pending_run = Repo.get!(Run, eligible_pending_run.id)

      assert persisted_eligible_pending_run.status == :running
      assert persisted_eligible_pending_run.owner_node_id == claimant.id

      persisted_missing_snapshot_run = Repo.get!(Run, missing_snapshot_pending_run.id)

      assert persisted_missing_snapshot_run.status == :pending
      assert persisted_missing_snapshot_run.owner_node_id == nil

      persisted_unsupported_snapshot_run = Repo.get!(Run, unsupported_snapshot_pending_run.id)

      assert persisted_unsupported_snapshot_run.status == :pending
      assert persisted_unsupported_snapshot_run.owner_node_id == nil

      persisted_completed_run = Repo.get!(Run, completed_run.id)
      assert persisted_completed_run.status == :completed
      assert persisted_completed_run.owner_node_id == nil
    end

    test "obeys exclusions, batch size, and oldest-updated ordering" do
      claimant = create_active_runtime_node("recovery-order")
      now = DateTime.utc_now(:microsecond)

      oldest_run =
        insert_run(%{
          status: :running,
          inserted_at: DateTime.add(now, -40, :second),
          updated_at: DateTime.add(now, -40, :second)
        })

      excluded_run =
        insert_run(%{
          status: :running,
          inserted_at: DateTime.add(now, -30, :second),
          updated_at: DateTime.add(now, -30, :second)
        })

      middle_run =
        insert_run(%{
          status: :running,
          inserted_at: DateTime.add(now, -20, :second),
          updated_at: DateTime.add(now, -20, :second)
        })

      newest_run =
        insert_run(%{
          status: :running,
          inserted_at: DateTime.add(now, -10, :second),
          updated_at: DateTime.add(now, -10, :second)
        })

      assert {:ok, ownership_tokens} =
               Runs.claim_recoverable(
                 claimant.id,
                 2,
                 [excluded_run.id]
               )

      assert Enum.map(ownership_tokens, & &1.run_id) ==
               [oldest_run.id, middle_run.id]

      assert Repo.get!(Run, excluded_run.id).owner_node_id == nil
      assert Repo.get!(Run, newest_run.id).owner_node_id == nil
    end

    test "requires an existing active claimant runtime node" do
      insert_run(%{status: :running})

      assert {:error, :runtime_node_not_found} =
               Runs.claim_recoverable(
                 "00000000-0000-0000-0000-000000000000",
                 25,
                 []
               )

      expired_runtime_node =
        create_active_runtime_node("recovery-expired-claimant")

      expire_runtime_node(expired_runtime_node)

      assert {:error, :runtime_node_expired} =
               Runs.claim_recoverable(
                 expired_runtime_node.id,
                 25,
                 []
               )
    end
  end

  @spec insert_snapshot(Run.t(), pos_integer()) :: RunSnapshot.t()
  defp insert_snapshot(run, format_version) do
    %RunSnapshot{
      run_id: run.id,
      format_version: format_version,
      definition: definition_fixture()
    }
    |> Repo.insert!()
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

  @spec expire_runtime_node(RuntimeNode.t()) :: RuntimeNode.t()
  defp expire_runtime_node(runtime_node) do
    expired_at =
      DateTime.add(
        runtime_node.last_heartbeat_at,
        -60,
        :second
      )

    runtime_node
    |> Changeset.change(last_heartbeat_at: expired_at)
    |> Repo.update!()
  end
end
