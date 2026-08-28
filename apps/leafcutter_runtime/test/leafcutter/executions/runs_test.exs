defmodule Leafcutter.Executions.RunsTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Nodes, Run, Runs, RunSnapshot, RuntimeNode}
  alias Leafcutter.Repo

  @type run_fixture_attrs :: %{
          optional(:status) => Run.status(),
          optional(:owner_node_id) => RuntimeNode.id(),
          optional(:generation) => integer(),
          optional(:ownership_acquired_at) => DateTime.t()
        }

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "create/1" do
    test "creates a pending Run and immutable snapshot in one transaction" do
      definition = definition_fixture()

      assert {:ok, run} = Runs.create(definition)

      assert run.status == :pending
      assert run.owner_node_id == nil
      assert run.generation == 0
      assert run.ownership_acquired_at == nil

      snapshot = Repo.get!(RunSnapshot, run.id)

      assert snapshot.run_id == run.id
      assert snapshot.format_version == RunSnapshot.current_format_version()
      assert snapshot.definition == definition
    end

    test "does not persist either record when the definition is invalid" do
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      invalid_definition =
        definition_fixture()
        |> Map.put("package_version_id", "not-a-uuid")

      assert {:error, %Changeset{} = changeset} =
               Runs.create(invalid_definition)

      refute changeset.valid?
      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "rejects attempts to set internal Run or snapshot fields" do
      definition_with_internal_fields =
        definition_fixture()
        |> Map.put("status", "running")
        |> Map.put("format_version", 999)

      assert {:error, %Changeset{} = changeset} =
               Runs.create(definition_with_internal_fields)

      assert {:base, {"contains unknown fields", options}} =
               List.keyfind(changeset.errors, :base, 0)

      assert options[:validation] == :unknown_fields
      assert Repo.aggregate(Run, :count) == 0
      assert Repo.aggregate(RunSnapshot, :count) == 0
    end

    test "creates distinct Runs for two valid calls" do
      definition = definition_fixture()

      assert {:ok, first_run} = Runs.create(definition)
      assert {:ok, second_run} = Runs.create(definition)

      refute first_run.id == second_run.id
      assert Repo.get!(RunSnapshot, first_run.id)
      assert Repo.get!(RunSnapshot, second_run.id)
    end
  end

  describe "fetch_snapshot/1" do
    test "returns the immutable snapshot for a Run created publicly" do
      assert {:ok, run} = Runs.create(definition_fixture())

      assert {:ok, %RunSnapshot{} = snapshot} =
               Runs.fetch_snapshot(run.id)

      assert snapshot.run_id == run.id
      assert snapshot.format_version == RunSnapshot.current_format_version()
    end

    test "distinguishes an existing legacy Run without a snapshot" do
      run = insert_run()

      assert {:error, :run_snapshot_not_found} =
               Runs.fetch_snapshot(run.id)
    end

    test "returns run_not_found when the Run does not exist" do
      assert {:error, :run_not_found} =
               Runs.fetch_snapshot("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "claim/2" do
    test "claims a pending Run and returns generation one" do
      run = create_pending_run()
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

    test "rejects a pending legacy Run without a snapshot" do
      run = insert_run()
      runtime_node = create_active_runtime_node("missing-snapshot")

      assert {:error, :run_snapshot_not_found} =
               Runs.claim(run.id, runtime_node.id)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :pending
      assert persisted_run.owner_node_id == nil
      assert persisted_run.generation == 0
    end

    test "rejects a pending Run with an unsupported snapshot format" do
      run = insert_run()
      _snapshot = insert_snapshot(run, 999)
      runtime_node = create_active_runtime_node("unsupported-snapshot")

      assert {:error, :unsupported_run_snapshot_format} =
               Runs.claim(run.id, runtime_node.id)

      persisted_run = Repo.get!(Run, run.id)

      assert persisted_run.status == :pending
      assert persisted_run.owner_node_id == nil
      assert persisted_run.generation == 0
    end

    test "preserves claims for running Runs regardless of snapshot state" do
      missing_snapshot_run = insert_run(%{status: :running})
      unsupported_snapshot_run = insert_run(%{status: :running})
      _snapshot = insert_snapshot(unsupported_snapshot_run, 999)
      runtime_node = create_active_runtime_node("running-compatibility")

      for run <- [missing_snapshot_run, unsupported_snapshot_run] do
        assert {:ok, ownership_token} =
                 Runs.claim(run.id, runtime_node.id)

        assert ownership_token.run_id == run.id
        assert ownership_token.generation == 1
      end
    end

    test "is idempotent for the current active owner" do
      run = create_pending_run()
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
      run = create_pending_run()
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
      run = create_pending_run()
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
      run = create_pending_run()
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
      run = create_pending_run()
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
      run = create_pending_run()
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
      changeset = constrained_changeset(%Run{}, %{generation: -1})

      assert {:error, changeset} = Repo.insert(changeset)

      assert {:generation, {_message, _options}} =
               List.keyfind(changeset.errors, :generation, 0)
    end

    test "requires ownership identifier and acquisition timestamp to change together" do
      runtime_node = create_active_runtime_node("ownership-constraint")

      changeset =
        constrained_changeset(%Run{}, %{
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
        constrained_changeset(%Run{}, %{
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

  @spec create_pending_run() :: Run.t()
  defp create_pending_run do
    {:ok, run} = Runs.create(definition_fixture())
    run
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

  @spec insert_run(run_fixture_attrs()) :: Run.t()
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
  defp expire_runtime_node(
         %RuntimeNode{last_heartbeat_at: %DateTime{} = last_heartbeat_at} = runtime_node
       ) do
    expired_at = DateTime.add(last_heartbeat_at, -60, :second)

    runtime_node
    |> Changeset.change(last_heartbeat_at: expired_at)
    |> Repo.update!()
  end

  @spec constrained_changeset(Run.t(), run_fixture_attrs()) :: Changeset.t()
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
