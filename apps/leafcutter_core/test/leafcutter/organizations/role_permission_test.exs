defmodule Leafcutter.Organizations.RolePermissionTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.RolePermission

  describe "create_changeset/2" do
    test "requires a role identifier and permission identifier" do
      role_id = Ecto.UUID.generate()

      invalid_attributes = [
        %{},
        %{role_id: role_id},
        %{permission: "environment.read"}
      ]

      for attrs <- invalid_attributes do
        changeset = RolePermission.create_changeset(%RolePermission{}, attrs)

        refute changeset.valid?
        assert changeset.errors != []
      end
    end

    test "accepts permission identifiers at the 255-character limit" do
      changeset =
        RolePermission.create_changeset(%RolePermission{}, %{
          role_id: Ecto.UUID.generate(),
          permission: String.duplicate("a", 255)
        })

      assert changeset.valid?
    end

    test "rejects permission identifiers longer than 255 characters" do
      changeset =
        RolePermission.create_changeset(%RolePermission{}, %{
          role_id: Ecto.UUID.generate(),
          permission: String.duplicate("a", 256)
        })

      refute changeset.valid?
      assert {:permission, {_, options}} = List.keyfind(changeset.errors, :permission, 0)
      assert options[:count] == 255
    end
  end
end
