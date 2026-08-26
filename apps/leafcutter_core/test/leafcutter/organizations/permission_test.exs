defmodule Leafcutter.Organizations.PermissionTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.Permission

  describe "identifier/1 and parse/1" do
    test "convert every supported permission across the persistence boundary" do
      permissions = [
        {:organization_read, "organization.read"},
        {:organization_manage, "organization.manage"},
        {:environment_read, "environment.read"},
        {:environment_manage, "environment.manage"},
        {:access_manage, "access.manage"}
      ]

      for {permission, identifier} <- permissions do
        assert Permission.identifier(permission) == identifier
        assert Permission.parse(identifier) == {:ok, permission}
      end
    end

    test "rejects unknown permission identifiers" do
      assert Permission.parse("unknown.permission") == {:error, :unknown_permission}
    end
  end
end
