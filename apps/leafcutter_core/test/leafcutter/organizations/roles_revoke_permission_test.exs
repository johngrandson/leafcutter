defmodule Leafcutter.Organizations.RolesRevokePermissionTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.RolePermission
  alias Leafcutter.Organizations.Roles

  describe "revoke_permission/2" do
    test "physically removes the permission and remains idempotent" do
      role = create_role()

      assert {:ok, _role_permission} =
               Roles.grant_permission(role.id, :environment_read)

      assert :ok = Roles.revoke_permission(role.id, :environment_read)

      refute Repo.get_by(RolePermission,
               role_id: role.id,
               permission: "environment.read"
             )

      assert :ok = Roles.revoke_permission(role.id, :environment_read)
    end

    test "returns a named error when the role does not exist" do
      assert {:error, :role_not_found} =
               Roles.revoke_permission(
                 "00000000-0000-0000-0000-000000000000",
                 :environment_read
               )
    end

    test "allows revocation when the role and organization are disabled" do
      role = create_role()

      assert {:ok, _role_permission} =
               Roles.grant_permission(role.id, :environment_read)

      assert {:ok, _role} = Roles.disable(role.id)
      assert {:ok, _organization} = Organizations.disable(role.organization_id)

      assert :ok = Roles.revoke_permission(role.id, :environment_read)

      refute Repo.get_by(RolePermission,
               role_id: role.id,
               permission: "environment.read"
             )
    end
  end

  defp create_role do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} =
             Organizations.create(%{name: "Revoke Permission #{suffix}"})

    assert {:ok, role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "operator"
             })

    role
  end
end
