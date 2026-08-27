defmodule Leafcutter.Repo.Migrations.CreateRunSnapshots do
  use Ecto.Migration

  def up do
    create table(:run_snapshots, primary_key: false) do
      add(
        :run_id,
        references(:runs, type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false
      )

      add(:format_version, :integer, null: false)
      add(:definition, :map, null: false)
    end

    create(
      constraint(:run_snapshots, :run_snapshots_format_version_positive,
        check: "format_version > 0"
      )
    )

    create(
      constraint(:run_snapshots, :run_snapshots_definition_is_object,
        check: "jsonb_typeof(definition) = 'object'"
      )
    )

    execute("""
    CREATE FUNCTION reject_run_snapshot_updates()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'run_snapshots are immutable and cannot be updated'
        USING ERRCODE = '23514';
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER run_snapshots_reject_update
    BEFORE UPDATE ON run_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION reject_run_snapshot_updates()
    """)
  end

  def down do
    execute("DROP TRIGGER run_snapshots_reject_update ON run_snapshots")
    execute("DROP FUNCTION reject_run_snapshot_updates()")

    drop(table(:run_snapshots))
  end
end
