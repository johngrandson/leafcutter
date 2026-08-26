defmodule Leafcutter.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:status, :string, null: false, default: "pending")

      add(
        :owner_node_id,
        references(:runtime_nodes, type: :binary_id)
      )

      add(:generation, :bigint, null: false, default: 0)
      add(:ownership_acquired_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      constraint(:runs, :runs_status_valid,
        check: "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')"
      )
    )

    create(
      constraint(:runs, :runs_generation_non_negative,
        check: "generation >= 0"
      )
    )

    create(
      constraint(:runs, :runs_ownership_fields_consistent,
        check:
          "(owner_node_id IS NULL AND ownership_acquired_at IS NULL) OR " <>
            "(owner_node_id IS NOT NULL AND ownership_acquired_at IS NOT NULL)"
      )
    )

    create(index(:runs, [:owner_node_id]))
    create(index(:runs, [:status]))
  end
end
