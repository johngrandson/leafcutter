defmodule Leafcutter.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :organization_id,
        references(:organizations, type: :binary_id),
        null: false
      )

      add(:name, :string, null: false)
      add(:disabled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :roles,
        [:organization_id, :name]
      )
    )

    create table(:role_permissions, primary_key: false) do
      add(
        :role_id,
        references(:roles, type: :binary_id),
        null: false
      )

      add(:permission, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :role_permissions,
        [:role_id, :permission]
      )
    )
  end
end
