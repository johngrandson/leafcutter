defmodule Leafcutter.Repo.Migrations.CreateRoleAssignments do
  use Ecto.Migration

  def change do
    create table(:role_assignments, primary_key: false) do
      add(
        :membership_id,
        references(:memberships, type: :binary_id),
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

    create unique_index(
             :role_assignments,
             [:membership_id, :role_id],
             name: :role_assignments_membership_role_organization_scope_index,
             where: "environment_id IS NULL"
           )

    create unique_index(
             :role_assignments,
             [:membership_id, :role_id, :environment_id],
             name: :role_assignments_membership_role_environment_scope_index,
             where: "environment_id IS NOT NULL"
           )
  end
end
