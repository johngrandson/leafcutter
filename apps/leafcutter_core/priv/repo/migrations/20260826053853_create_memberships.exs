defmodule Leafcutter.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :organization_id,
        references(:organizations, type: :binary_id),
        null: false
      )

      add(
        :user_id,
        references(:users, type: :binary_id),
        null: false
      )

      add(:disabled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :memberships,
        [:organization_id, :user_id]
      )
    )
  end
end
