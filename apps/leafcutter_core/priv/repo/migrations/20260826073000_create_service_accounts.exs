defmodule Leafcutter.Repo.Migrations.CreateServiceAccounts do
  use Ecto.Migration

  def change do
    create table(:service_accounts, primary_key: false) do
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
        :service_accounts,
        [:organization_id, :name]
      )
    )
  end
end
