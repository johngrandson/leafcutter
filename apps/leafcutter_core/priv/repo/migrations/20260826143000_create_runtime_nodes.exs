defmodule Leafcutter.Repo.Migrations.CreateRuntimeNodes do
  use Ecto.Migration

  def change do
    create table(:runtime_nodes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:node_name, :string, null: false)
      add(:last_heartbeat_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:runtime_nodes, [:last_heartbeat_at]))
  end
end
