defmodule Leafcutter.Executions.RunsTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Nodes, Run, Runs, RuntimeNode}
  alias Leafcutter.Repo

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "claim/2" do
    test "claims a pending Run and returns generation one" do
      run = insert_run()
      runtime_node = create_active_runtime_node("first-claim")
      run_id = run.id
      runtime_node_id = runtime_node.id

      assert {:ok,
              %{
                run_id: ^run_id,
                runtime_node_id: ^runtime_node_id,
                generation: 1
              }} = Runs.claim(run.id, runtime_node.id)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :running
      assert persisted_run.owner_node_id == runtime_node.id
      assert persisted_run.generation == 1
      assert %DateTime{} = persisted_run.ownership_acquired_at
    end

    test "is idempotent for the current active owner" do
      run = insert_run()
      runtime_node = create_active_runtime_node("idempotent-claim")

      assert {:ok, first_token} = Runs.claim(run.id, runtime_node.id)
      first_persisted_run = Repo.get!(Run, run.id)

      assert {:ok, second_token} = Runs.claim(run.id, runtime_node.id)
      second_persisted_run = Repo.get!(Run, run.id)

      assert second_token == first_token
      assert second_persisted_run.generation == 1

      assert second_persisted_run.ownership_acquired_at ==
               first_persisted_run.ownership_acquired_at
    end

    test "rejects another active owner" do
      run = insert_run()
      first_runtime_node = create_active_runtime_node("active-owner")
      second_runtime_node = create_active_runtime_node("active-contender")

      assert {:ok, first_token} = Runs.claim(run.id, first_runtime_node.id)

      assert {:error, :owned_by_active_node} =
               Runs.claim(run.id, second_runtime_node.id)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.owner_node_id == first_runtime_node.id
      assert persisted_run.generation == first_token.generation
    end

    test "reclaims a Run from an expired owner and increments generation" do
      run = insert_run()
      first_runtime_node = create_active_runtime_node("expired-owner")
      second_runtime_node = create_active_runtime_node("recovery-node")

      assert {:ok, first_token} = Runs.claim(run.id, first_runtime_node.id)
      expire_runtime_node(first_runtime_node)

      assert {:ok, second_token} = Runs.claim(run.id, second_runtime_node.id)

      assert first_token.generation == 1
      assert second_token.generation == 2
      assert second_token.runtime_node_id == second_runtime_node.id

      persisted_run = Repo.get!(Run, run.id)
      assert persisted_run.owner_node_id == second_runtime_node.id
      assert persisted_run.generation == 2
    end

    test "requires an existing active claimant runtime node" do
      run = insert_run()
      missing_runtime_node_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, :runtime_node_not_found} =
               Runs.claim(run.id, missing_runtime_node_id)

      expired_runtime_node = create_active_runtime_node("expired-claimant")
      expire_runtime_node(expired_runtime_node)

      assert {:error, :runtime_node_expired} =
               Runs.claim(run.id, expired_runtime_node.id)
    end

    test "rejects terminal Runs" do
      runtime_node = create_active_runtime_node("terminal-claim")

      for status <- [:completed, :failed, :cancelled] do
        run = insert_run(%{status: status})

        assert {:error, :run_not_claimable} =
                 Runs.claim(run.id, runtime_node.id)
      end
    end

    test "returns a named error when the Run does not exist" do
      runtime_node = create_active_runtime_node("missing-run")

      assert {:error, :run_not_found} =
               Runs.claim(
                 "00000000-0000-0000-0000-000000000000",
                 runtime_node.id
               )
    end
  end

  describe "release/1" do
    test "clears ownership idempotently while preserving lifecycle and generation" do
      run = insert_run()
      runtime_node = create_active_runtime_node("release")

      assert {:ok, ownership_token} = Runs.claim(run.id, runtime_node.id)
      assert :ok = Runs.release(ownership_token)
      assert :ok = Runs.release(ownership_token)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :running
      assert persisted_run.owner_node_id == nil
      assert persisted_run.ownership_acquired_at == nil
      assert persisted_run.generation == ownership_token.generation
    end

    test "rejects an old token after another runtime node acquires a later generation" do
      run = insert_run()
      first_runtime_node = create_active_runtime_node("release-first")
      second_runtime_node = create_active_runtime_node("release-second")

      assert {:ok, first_token} = Runs.claim(run.id, first_runtime_node.id)
      assert :ok = Runs.release(first_token)

      assert {:ok, second_token} = Runs.claim(run.id, second_runtime_node.id)
      assert second_token.generation == first_token.generation + 1

      assert {:error, :stale_ownership} = Runs.release(first_token)
      assert :ok = Runs.release(second_token)
    end

    test "returns a named error when the Run does not exist" do
      ownership_token = %{
        run_id: "00000000-0000-0000-0000-000000000000",
        runtime_node_id: Ecto.UUID.generate(),
        generation: 1
      }

      assert {:error, :run_not_found} = Runs.release(ownership_token)
    end
  end

  describe "database constraints" do
    test "rejects a negative generation" do
      changeset =
        %Run{}
        |> constrained_changeset(%{generation: -1})

      assert {:error, changeset} = Repo.insert(changeset)
      assert {:generation, {_message, _options}} = List.keyfind(changeset.errors, :generation, 0)
    end

    test "requires ownership identifier and acquisition timestamp to change together" do
      runtime_node = create_active_runtime_node("ownership-constraint")

      changeset =
        %Run{}
        |> constrained_changeset(%{
          status: :running,
          owner_node_id: runtime_node.id,
          generation: 1
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert {:owner_node_id, {_message, _options}} =
               List.keyfind(changeset.errors, :owner_node_id, 0)
    end

    test "maps an owner node foreign key violation to the changeset" do
      changeset =
        %Run{}
        |> constrained_changeset(%{
          status: :running,
          owner_node_id: "00000000-0000-0000-0000-000000000000",
          generation: 1,
          ownership_acquired_at: DateTime.utc_now(:microsecond)
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert {:owner_node_id, {_message, _options}} =
               List.keyfind(changeset.errors, :owner_node_id, 0)
    end
  end

  @spec insert_run(map()) :: Run.t()
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
    expired_at = DateTime.add(runtime_node.last_heartbeat_at, -60, :second)

    runtime_node
    |> Changeset.change(last_heartbeat_at: expired_at)
    |> Repo.update!()
  end

  @spec constrained_changeset(Run.t(), map()) :: Changeset.t()
  defp constrained_changeset(run, attrs) do
    run
    |> Changeset.change(attrs)
    |> Changeset.foreign_key_constraint(:owner_node_id)
    |> Changeset.check_constraint(:status, name: :runs_status_valid)
    |> Changeset.check_constraint(:generation, name: :runs_generation_non_negative)
    |> Changeset.check_constraint(
      :owner_node_id,
      name: :runs_ownership_fields_consistent
    )
  end
end
