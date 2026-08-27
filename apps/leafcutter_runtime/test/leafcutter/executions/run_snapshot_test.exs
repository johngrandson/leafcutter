defmodule Leafcutter.Executions.RunSnapshotTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Leafcutter.Executions.{Run, RunSnapshot}
  alias Leafcutter.Repo

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "schema" do
    test "uses the Run identifier as its only primary key" do
      assert RunSnapshot.__schema__(:primary_key) == [:run_id]
      assert RunSnapshot.__schema__(:fields) == [:run_id, :format_version, :definition]

      association = RunSnapshot.__schema__(:association, :run)

      assert association.related == Run
      assert association.owner_key == :run_id
      assert association.related_key == :id
    end

    test "does not define an independent identifier or timestamps" do
      fields = RunSnapshot.__schema__(:fields)

      refute :id in fields
      refute :inserted_at in fields
      refute :updated_at in fields
    end

    test "publishes the ratified format version contract" do
      assert RunSnapshot.current_format_version() == 1
      assert RunSnapshot.supported_format_versions() == [1]
    end
  end

  describe "create_changeset/2" do
    test "normalizes definition v1 and assigns the current format internally" do
      run = insert_run()

      definition =
        definition_fixture()
        |> Map.delete("effective_config")
        |> Map.put(:effective_config, %{retry: %{enabled: true}})

      changeset =
        RunSnapshot.create_changeset(
          %RunSnapshot{},
          %{
            run_id: run.id,
            definition: definition,
            format_version: 999
          }
        )

      assert changeset.valid?
      assert Changeset.get_change(changeset, :format_version) == 1

      assert Changeset.get_change(changeset, :definition)["effective_config"] == %{
               "retry" => %{"enabled" => true}
             }
    end

    test "rejects an invalid definition and preserves its structural errors" do
      run = insert_run()

      invalid_definition =
        definition_fixture()
        |> Map.put("package_version_id", "not-a-uuid")

      changeset =
        RunSnapshot.create_changeset(
          %RunSnapshot{},
          %{run_id: run.id, definition: invalid_definition}
        )

      refute changeset.valid?

      assert {"is invalid", options} =
               Keyword.fetch!(changeset.errors, :definition)

      assert options[:validation] == :run_snapshot_definition_v1

      assert [{"is not a valid UUID", uuid_options}] =
               options[:definition_errors].package_version_id

      assert uuid_options[:validation] == :uuid
    end
  end

  describe "database invariants" do
    test "persists one snapshot for an existing Run" do
      run = insert_run()
      definition = definition_fixture()

      assert {:ok, snapshot} = insert_snapshot(run, %{definition: definition})

      assert snapshot.run_id == run.id
      assert snapshot.format_version == 1
      assert snapshot.definition == definition
      assert Repo.get!(RunSnapshot, run.id) == snapshot
    end

    test "allows a legacy Run to exist without a snapshot" do
      run = insert_run()

      assert Repo.get(RunSnapshot, run.id) == nil
    end

    test "rejects a second snapshot for the same Run" do
      run = insert_run()

      assert {:ok, _snapshot} = insert_snapshot(run)
      assert {:error, changeset} = insert_snapshot(run)

      assert {:run_id, {_message, _options}} =
               List.keyfind(changeset.errors, :run_id, 0)
    end

    test "rejects a snapshot for a missing Run" do
      missing_run = %Run{id: Ecto.UUID.generate()}

      assert {:error, changeset} = insert_snapshot(missing_run)

      assert {:run_id, {_message, _options}} =
               List.keyfind(changeset.errors, :run_id, 0)
    end

    test "enforces a positive format version at the database boundary" do
      run = insert_run()

      for invalid_format_version <- [0, -1] do
        attrs = %{
          run_id: run.id,
          format_version: invalid_format_version,
          definition: definition_fixture()
        }

        assert {:error, changeset} =
                 %RunSnapshot{}
                 |> Changeset.change(attrs)
                 |> Changeset.check_constraint(
                   :format_version,
                   name: :run_snapshots_format_version_positive
                 )
                 |> Repo.insert()

        assert {:format_version, {_message, _options}} =
                 List.keyfind(changeset.errors, :format_version, 0)
      end
    end

    test "requires the persisted definition root to be a JSON object" do
      run = insert_run()
      {:ok, dumped_run_id} = Ecto.UUID.dump(run.id)

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              SQL.query!(
                Repo,
                """
                INSERT INTO run_snapshots (run_id, format_version, definition)
                VALUES ($1, 1, '[]'::jsonb)
                """,
                [dumped_run_id]
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint == "run_snapshots_definition_is_object"
    end

    test "rejects every update and preserves the original snapshot" do
      run = insert_run()
      assert {:ok, snapshot} = insert_snapshot(run)

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              snapshot
              |> Changeset.change(definition: %{"changed" => true})
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message ==
               "run_snapshots are immutable and cannot be updated"

      assert Repo.get!(RunSnapshot, run.id).definition == snapshot.definition
    end

    test "deletes the snapshot when its Run is deleted" do
      run = insert_run()
      assert {:ok, _snapshot} = insert_snapshot(run)

      Repo.delete!(run)

      assert Repo.get(RunSnapshot, run.id) == nil
    end
  end

  @spec insert_run() :: Run.t()
  defp insert_run do
    %Run{}
    |> Changeset.change()
    |> Repo.insert!()
  end

  @spec insert_snapshot(Run.t(), map()) ::
          {:ok, RunSnapshot.t()} | {:error, Changeset.t()}
  defp insert_snapshot(run, attrs \\ %{}) do
    %{
      run_id: run.id,
      format_version: 1,
      definition: definition_fixture()
    }
    |> Map.merge(attrs)
    |> then(&RunSnapshot.create_changeset(%RunSnapshot{}, &1))
    |> Repo.insert()
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
end
