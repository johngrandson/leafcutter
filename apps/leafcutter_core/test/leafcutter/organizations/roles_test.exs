defmodule Leafcutter.Organizations.RolesTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.{Role, RolePermission, Roles}

  describe "create/1" do
    test "persists a new active role in an active organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, %Role{} = role} =
               Roles.create(%{
                 organization_id: organization.id,
                 name: "operator",
                 disabled_at: ~U[2026-01-01 00:00:00.000000Z]
               })

      assert role.organization_id == organization.id
      assert role.name == "operator"
      assert role.disabled_at == nil
      assert {:ok, role.id} == Ecto.UUID.cast(role.id)
      assert %DateTime{} = role.inserted_at
    end

    test "rejects missing required attributes" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      invalid_attributes = [
        %{},
        %{organization_id: organization.id},
        %{name: "operator"}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = Roles.create(attrs)
        assert map_size(errors_on(changeset)) > 0
      end
    end

    test "requires an existing active organization" do
      missing_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, :organization_not_found} =
               Roles.create(%{organization_id: missing_id, name: "operator"})

      assert {:ok, organization} = Organizations.create(%{name: "Disabled"})
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               Roles.create(%{organization_id: organization.id, name: "operator"})
    end

    test "scopes role name uniqueness to each organization" do
      assert {:ok, first_organization} = Organizations.create(%{name: "First"})
      assert {:ok, second_organization} = Organizations.create(%{name: "Second"})

      assert {:ok, _role} =
               Roles.create(%{organization_id: first_organization.id, name: "operator"})

      assert {:error, changeset} =
               Roles.create(%{organization_id: first_organization.id, name: "operator"})

      assert %{organization_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _role} =
               Roles.create(%{organization_id: second_organization.id, name: "operator"})
    end
  end

  describe "get/1" do
    test "returns active and disabled roles" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, fetched} = Roles.get(role.id)
      assert fetched.id == role.id

      assert {:ok, disabled} = Roles.disable(role.id)
      assert {:ok, fetched_disabled} = Roles.get(role.id)
      assert fetched_disabled.disabled_at == disabled.disabled_at
    end

    test "returns a named error when the role does not exist" do
      assert {:error, :not_found} =
               Roles.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, first_disable} = Roles.disable(role.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = Roles.disable(role.id)
      assert second_disable.disabled_at == first_disable.disabled_at
      assert Repo.get!(Role, role.id).disabled_at == first_disable.disabled_at
    end

    test "returns a named error when the role does not exist" do
      assert {:error, :not_found} =
               Roles.disable("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "grant_permission/2" do
    test "persists the canonical permission identifier" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, %RolePermission{} = role_permission} =
               Roles.grant_permission(role.id, :environment_read)

      assert role_permission.role_id == role.id
      assert role_permission.permission == "environment.read"
      assert %DateTime{} = role_permission.inserted_at
    end

    test "returns named errors for missing and disabled roles" do
      missing_id = "00000000-0000-0000-0000-000000000000"
      assert {:error, :role_not_found} = Roles.grant_permission(missing_id, :access_manage)

      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, _role} = Roles.disable(role.id)
      assert {:error, :role_disabled} = Roles.grant_permission(role.id, :access_manage)
    end

    test "rejects grants in a disabled organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               Roles.grant_permission(role.id, :access_manage)
    end

    test "returns a named error when the permission was already granted" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, _role_permission} =
               Roles.grant_permission(role.id, :environment_manage)

      assert {:error, :permission_already_granted} =
               Roles.grant_permission(role.id, :environment_manage)
    end

    test "scopes each permission grant to its role" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, first_role} =
               Roles.create(%{organization_id: organization.id, name: "operator"})

      assert {:ok, second_role} =
               Roles.create(%{organization_id: organization.id, name: "auditor"})

      assert {:ok, _role_permission} =
               Roles.grant_permission(first_role.id, :organization_read)

      assert {:ok, _role_permission} =
               Roles.grant_permission(second_role.id, :organization_read)

      assert %RolePermission{} =
               Repo.get_by(RolePermission,
                 role_id: first_role.id,
                 permission: "organization.read"
               )

      assert %RolePermission{} =
               Repo.get_by(RolePermission,
                 role_id: second_role.id,
                 permission: "organization.read"
               )
    end
  end
end
