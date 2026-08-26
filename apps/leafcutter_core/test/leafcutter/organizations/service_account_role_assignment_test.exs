defmodule Leafcutter.Organizations.ServiceAccountRoleAssignmentTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.ServiceAccountRoleAssignment

  describe "create_changeset/2" do
    test "requires a service account and role identifier" do
      service_account_id = Ecto.UUID.generate()
      role_id = Ecto.UUID.generate()

      invalid_attributes = [
        %{},
        %{service_account_id: service_account_id},
        %{role_id: role_id}
      ]

      for attrs <- invalid_attributes do
        changeset =
          ServiceAccountRoleAssignment.create_changeset(
            %ServiceAccountRoleAssignment{},
            attrs
          )

        refute changeset.valid?
        assert changeset.errors != []
      end
    end

    test "accepts organization-wide and environment-scoped assignments" do
      service_account_id = Ecto.UUID.generate()
      role_id = Ecto.UUID.generate()
      environment_id = Ecto.UUID.generate()

      organization_changeset =
        ServiceAccountRoleAssignment.create_changeset(
          %ServiceAccountRoleAssignment{},
          %{service_account_id: service_account_id, role_id: role_id}
        )

      environment_changeset =
        ServiceAccountRoleAssignment.create_changeset(
          %ServiceAccountRoleAssignment{},
          %{
            service_account_id: service_account_id,
            role_id: role_id,
            environment_id: environment_id
          }
        )

      assert organization_changeset.valid?
      assert environment_changeset.valid?
      assert Ecto.Changeset.get_field(organization_changeset, :environment_id) == nil
      assert Ecto.Changeset.get_field(environment_changeset, :environment_id) == environment_id
    end
  end
end
