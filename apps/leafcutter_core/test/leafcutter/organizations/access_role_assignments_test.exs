defmodule Leafcutter.Organizations.AccessRoleAssignmentsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Organizations.RoleAssignment
  alias Leafcutter.Organizations.Roles
  alias Leafcutter.Organizations.Users

  describe "assign_role/1" do
    test "persists an organization-wide role assignment" do
      fixture = create_access_fixture()

      assert {:ok, %RoleAssignment{} = assignment} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id
               })

      assert assignment.membership_id == fixture.membership.id
      assert assignment.role_id == fixture.role.id
      assert assignment.environment_id == nil
      assert %DateTime{} = assignment.inserted_at
    end

    test "persists an environment-scoped role assignment" do
      fixture = create_access_fixture()
      environment = create_environment(fixture.organization.id, "production")

      assert {:ok, %RoleAssignment{} = assignment} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id,
                 environment_id: environment.id
               })

      assert assignment.environment_id == environment.id
    end

    test "allows organization-wide and environment-scoped assignments to coexist" do
      fixture = create_access_fixture()
      first_environment = create_environment(fixture.organization.id, "production")
      second_environment = create_environment(fixture.organization.id, "homologation")

      assert {:ok, _assignment} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id
               })

      for environment <- [first_environment, second_environment] do
        assert {:ok, %RoleAssignment{environment_id: environment_id}} =
                 Access.assign_role(%{
                   membership_id: fixture.membership.id,
                   role_id: fixture.role.id,
                   environment_id: environment.id
                 })

        assert environment_id == environment.id
      end
    end

    test "returns a named error when the same role is already assigned in the scope" do
      fixture = create_access_fixture()
      environment = create_environment(fixture.organization.id, "production")

      organization_attrs = %{
        membership_id: fixture.membership.id,
        role_id: fixture.role.id
      }

      environment_attrs = Map.put(organization_attrs, :environment_id, environment.id)

      assert {:ok, _assignment} = Access.assign_role(organization_attrs)
      assert {:error, :role_already_assigned} = Access.assign_role(organization_attrs)

      assert {:ok, _assignment} = Access.assign_role(environment_attrs)
      assert {:error, :role_already_assigned} = Access.assign_role(environment_attrs)
    end

    test "requires an existing active membership" do
      fixture = create_access_fixture()

      assert {:error, :membership_not_found} =
               Access.assign_role(%{
                 membership_id: missing_id(),
                 role_id: fixture.role.id
               })

      assert {:ok, _membership} =
               Access.remove_member(fixture.organization.id, fixture.user.id)

      assert {:error, :membership_disabled} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id
               })
    end

    test "requires an active membership organization" do
      fixture = create_access_fixture()
      assert {:ok, _organization} = Organizations.disable(fixture.organization.id)

      assert {:error, :organization_disabled} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id
               })
    end

    test "requires an existing active role in the membership organization" do
      fixture = create_access_fixture()

      assert {:error, :role_not_found} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: missing_id()
               })

      assert {:ok, _role} = Roles.disable(fixture.role.id)

      assert {:error, :role_disabled} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id
               })

      second_fixture = create_access_fixture()

      assert {:error, :role_organization_mismatch} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: second_fixture.role.id
               })
    end

    test "requires an existing active environment in the membership organization" do
      fixture = create_access_fixture()

      assert {:error, :environment_not_found} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id,
                 environment_id: missing_id()
               })

      disabled_environment = create_environment(fixture.organization.id, "disabled")
      assert {:ok, _environment} = Environments.disable(disabled_environment.id)

      assert {:error, :environment_disabled} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id,
                 environment_id: disabled_environment.id
               })

      second_fixture = create_access_fixture()
      foreign_environment = create_environment(second_fixture.organization.id, "foreign")

      assert {:error, :environment_organization_mismatch} =
               Access.assign_role(%{
                 membership_id: fixture.membership.id,
                 role_id: fixture.role.id,
                 environment_id: foreign_environment.id
               })
    end
  end

  describe "revoke_role/1" do
    test "is idempotent and physically removes the requested assignment" do
      fixture = create_access_fixture()

      attrs = %{
        membership_id: fixture.membership.id,
        role_id: fixture.role.id
      }

      assert {:ok, _assignment} = Access.assign_role(attrs)
      assert :ok = Access.revoke_role(attrs)
      assert Repo.all(RoleAssignment) == []
      assert :ok = Access.revoke_role(attrs)
    end

    test "revokes only the requested scope" do
      fixture = create_access_fixture()
      environment = create_environment(fixture.organization.id, "production")

      organization_attrs = %{
        membership_id: fixture.membership.id,
        role_id: fixture.role.id
      }

      environment_attrs = Map.put(organization_attrs, :environment_id, environment.id)

      assert {:ok, _assignment} = Access.assign_role(organization_attrs)
      assert {:ok, _assignment} = Access.assign_role(environment_attrs)

      assert :ok = Access.revoke_role(environment_attrs)

      assert [%RoleAssignment{environment_id: nil}] = Repo.all(RoleAssignment)
    end

    test "allows revocation after related lifecycle resources are disabled" do
      fixture = create_access_fixture()
      environment = create_environment(fixture.organization.id, "production")

      attrs = %{
        membership_id: fixture.membership.id,
        role_id: fixture.role.id,
        environment_id: environment.id
      }

      assert {:ok, _assignment} = Access.assign_role(attrs)
      assert {:ok, _environment} = Environments.disable(environment.id)
      assert {:ok, _role} = Roles.disable(fixture.role.id)
      assert {:ok, _membership} =
               Access.remove_member(fixture.organization.id, fixture.user.id)

      assert {:ok, _organization} = Organizations.disable(fixture.organization.id)

      assert :ok = Access.revoke_role(attrs)
      assert Repo.all(RoleAssignment) == []
    end

    test "returns a changeset for invalid assignment identity attributes" do
      assert {:error, changeset} = Access.revoke_role(%{})
      assert %{membership_id: [_ | _], role_id: [_ | _]} = errors_on(changeset)
    end
  end

  defp create_access_fixture do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} =
             Organizations.create(%{name: "Role Assignment #{suffix}"})

    assert {:ok, user} =
             Users.create(%{email: "role-assignment-#{suffix}@example.com"})

    assert {:ok, membership} =
             Access.add_member(%{
               organization_id: organization.id,
               user_id: user.id
             })

    assert {:ok, role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "operator"
             })

    %{
      organization: organization,
      user: user,
      membership: membership,
      role: role
    }
  end

  defp create_environment(organization_id, name) do
    assert {:ok, environment} =
             Environments.create(%{
               organization_id: organization_id,
               name: name
             })

    environment
  end

  defp missing_id, do: "00000000-0000-0000-0000-000000000000"
end
