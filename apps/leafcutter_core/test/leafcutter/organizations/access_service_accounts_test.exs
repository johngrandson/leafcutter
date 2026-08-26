defmodule Leafcutter.Organizations.Access.ServiceAccountsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access.ServiceAccounts, as: ServiceAccountAccess
  alias Leafcutter.Organizations.{
    Environments,
    Roles,
    ServiceAccountRoleAssignment,
    ServiceAccounts
  }

  describe "assign_role/1" do
    test "assigns an organization-wide role" do
      %{service_account: service_account, role: role} = create_scope()

      assert {:ok, %ServiceAccountRoleAssignment{} = assignment} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id
               })

      assert assignment.service_account_id == service_account.id
      assert assignment.role_id == role.id
      assert assignment.environment_id == nil
    end

    test "assigns an environment-scoped role and allows organization-wide coexistence" do
      %{service_account: service_account, role: role, environment: environment} = create_scope()

      assert {:ok, organization_assignment} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id
               })

      assert {:ok, environment_assignment} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id,
                 environment_id: environment.id
               })

      assert organization_assignment.environment_id == nil
      assert environment_assignment.environment_id == environment.id
    end

    test "returns a named error for duplicate assignments in the same scope" do
      %{service_account: service_account, role: role, environment: environment} = create_scope()

      attrs = %{
        service_account_id: service_account.id,
        role_id: role.id,
        environment_id: environment.id
      }

      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(attrs)
      assert {:error, :role_already_assigned} = ServiceAccountAccess.assign_role(attrs)
    end

    test "requires an existing active service account" do
      %{organization: organization, role: role} = create_scope()

      assert {:error, :service_account_not_found} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: "00000000-0000-0000-0000-000000000000",
                 role_id: role.id
               })

      assert {:ok, service_account} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "disabled-agent"
               })

      assert {:ok, _service_account} = ServiceAccounts.disable(service_account.id)

      assert {:error, :service_account_disabled} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id
               })
    end

    test "requires an active organization" do
      %{organization: organization, service_account: service_account, role: role} = create_scope()
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id
               })
    end

    test "requires an active role in the same organization" do
      %{organization: organization, service_account: service_account, role: role} = create_scope()

      assert {:error, :role_not_found} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: "00000000-0000-0000-0000-000000000000"
               })

      assert {:ok, _role} = Roles.disable(role.id)

      assert {:error, :role_disabled} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id
               })

      assert {:ok, other_organization} = Organizations.create(%{name: "Other"})

      assert {:ok, other_role} =
               Roles.create(%{
                 organization_id: other_organization.id,
                 name: "other-role"
               })

      assert {:error, :role_organization_mismatch} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: other_role.id
               })

      assert organization.id == service_account.organization_id
    end

    test "requires an active environment in the same organization" do
      %{service_account: service_account, role: role, environment: environment} = create_scope()

      assert {:error, :environment_not_found} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id,
                 environment_id: "00000000-0000-0000-0000-000000000000"
               })

      assert {:ok, _environment} = Environments.disable(environment.id)

      assert {:error, :environment_disabled} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id,
                 environment_id: environment.id
               })

      assert {:ok, other_organization} = Organizations.create(%{name: "Other"})

      assert {:ok, other_environment} =
               Environments.create(%{
                 organization_id: other_organization.id,
                 name: "production"
               })

      assert {:error, :environment_organization_mismatch} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: service_account.id,
                 role_id: role.id,
                 environment_id: other_environment.id
               })
    end
  end

  describe "revoke_role/1" do
    test "is idempotent and revokes only the requested scope" do
      %{service_account: service_account, role: role, environment: environment} = create_scope()

      organization_attrs = %{
        service_account_id: service_account.id,
        role_id: role.id
      }

      environment_attrs = %{
        service_account_id: service_account.id,
        role_id: role.id,
        environment_id: environment.id
      }

      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(organization_attrs)
      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(environment_attrs)

      assert :ok = ServiceAccountAccess.revoke_role(environment_attrs)
      assert :ok = ServiceAccountAccess.revoke_role(environment_attrs)

      assert %ServiceAccountRoleAssignment{} =
               Repo.get_by(ServiceAccountRoleAssignment,
                 service_account_id: service_account.id,
                 role_id: role.id,
                 environment_id: nil
               )

      assert Repo.get_by(ServiceAccountRoleAssignment,
               service_account_id: service_account.id,
               role_id: role.id,
               environment_id: environment.id
             ) == nil
    end

    test "allows revocation after related resources are disabled" do
      %{organization: organization, service_account: service_account, role: role} = create_scope()

      attrs = %{service_account_id: service_account.id, role_id: role.id}

      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(attrs)
      assert {:ok, _service_account} = ServiceAccounts.disable(service_account.id)
      assert {:ok, _role} = Roles.disable(role.id)
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert :ok = ServiceAccountAccess.revoke_role(attrs)
      assert :ok = ServiceAccountAccess.revoke_role(attrs)
    end
  end

  describe "database constraints" do
    test "enforces organization-wide uniqueness" do
      %{service_account: service_account, role: role} = create_scope()

      attrs = %{service_account_id: service_account.id, role_id: role.id}

      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(attrs)

      changeset =
        ServiceAccountRoleAssignment.create_changeset(
          %ServiceAccountRoleAssignment{},
          attrs
        )

      assert {:error, changeset} = Repo.insert(changeset)
      assert map_size(errors_on(changeset)) > 0
    end

    test "enforces environment-scoped uniqueness" do
      %{service_account: service_account, role: role, environment: environment} = create_scope()

      attrs = %{
        service_account_id: service_account.id,
        role_id: role.id,
        environment_id: environment.id
      }

      assert {:ok, _assignment} = ServiceAccountAccess.assign_role(attrs)

      changeset =
        ServiceAccountRoleAssignment.create_changeset(
          %ServiceAccountRoleAssignment{},
          attrs
        )

      assert {:error, changeset} = Repo.insert(changeset)
      assert map_size(errors_on(changeset)) > 0
    end
  end

  defp create_scope do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} = Organizations.create(%{name: "Scope #{suffix}"})

    assert {:ok, service_account} =
             ServiceAccounts.create(%{
               organization_id: organization.id,
               name: "agent-#{suffix}"
             })

    assert {:ok, role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "operator-#{suffix}"
             })

    assert {:ok, environment} =
             Environments.create(%{
               organization_id: organization.id,
               name: "production-#{suffix}"
             })

    %{
      organization: organization,
      service_account: service_account,
      role: role,
      environment: environment
    }
  end
end
