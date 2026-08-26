defmodule Leafcutter.Repo.Migrations.CreateServiceAccountRoleAssignments do
  use Ecto.Migration

  def change do
    create table(:service_account_role_assignments, primary_key: false) do
      add(
        :service_account_id,
        references(:service_accounts, type: :binary_id),
        null: false
      )

      add(
        :role_id,
        references(:roles, type: :binary_id),
        null: false
      )

      add(
        :environment_id,
        references(:environments, type: :binary_id)
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :service_account_role_assignments,
        [:service_account_id, :role_id],
        name: :sa_role_assignments_account_role_org_scope_index,
        where: "environment_id IS NULL"
      )
    )

    create(
      unique_index(
        :service_account_role_assignments,
        [:service_account_id, :role_id, :environment_id],
        name: :sa_role_assignments_account_role_env_scope_index,
        where: "environment_id IS NOT NULL"
      )
    )
  end
end
