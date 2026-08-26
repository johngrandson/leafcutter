defmodule Leafcutter.Organizations.AccessAuthorizationTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access
  alias Leafcutter.Organizations.Access.ServiceAccounts, as: ServiceAccountAccess

  alias Leafcutter.Organizations.{
    Environments,
    Roles,
    ServiceAccounts,
    Users
  }

  describe "authorize/3 for users" do
    test "organization-wide roles authorize both organization and environment scopes" do
      scope = create_user_scope()

      assert {:ok, _permission} = Roles.grant_permission(scope.role.id, :organization_read)

      assert {:ok, _assignment} =
               Access.assign_role(%{
                 membership_id: scope.membership.id,
                 role_id: scope.role.id
               })

      assert :ok =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert :ok =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:environment, scope.environment.id}
               )
    end

    test "environment-scoped roles authorize only the matching environment" do
      scope = create_user_scope()

      assert {:ok, other_environment} =
               Environments.create(%{
                 organization_id: scope.organization.id,
                 name: "other"
               })

      assert {:ok, _permission} = Roles.grant_permission(scope.role.id, :environment_read)

      assert {:ok, _assignment} =
               Access.assign_role(%{
                 membership_id: scope.membership.id,
                 role_id: scope.role.id,
                 environment_id: scope.environment.id
               })

      assert :ok =
               Access.authorize(
                 {:user, scope.user.id},
                 :environment_read,
                 {:environment, scope.environment.id}
               )

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:user, scope.user.id},
                 :environment_read,
                 {:organization, scope.organization.id}
               )

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:user, scope.user.id},
                 :environment_read,
                 {:environment, other_environment.id}
               )
    end

    test "returns lifecycle and membership errors before permission denial" do
      scope = create_user_scope()

      assert {:error, :user_not_found} =
               Access.authorize(
                 {:user, "00000000-0000-0000-0000-000000000000"},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert {:ok, outsider} = Users.create(%{email: unique_email("outsider")})

      assert {:error, :membership_not_found} =
               Access.authorize(
                 {:user, outsider.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert {:ok, _membership} =
               Access.remove_member(scope.organization.id, scope.user.id)

      assert {:error, :membership_disabled} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )
    end

    test "returns user_disabled for a disabled user" do
      scope = create_user_scope()
      assert {:ok, _user} = Users.disable(scope.user.id)

      assert {:error, :user_disabled} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )
    end
  end

  describe "authorize/3 for service accounts" do
    test "supports organization-wide inheritance and environment-only assignments" do
      scope = create_service_account_scope()

      assert {:ok, _permission} = Roles.grant_permission(scope.organization_role.id, :organization_read)

      assert {:ok, _assignment} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: scope.service_account.id,
                 role_id: scope.organization_role.id
               })

      assert :ok =
               Access.authorize(
                 {:service_account, scope.service_account.id},
                 :organization_read,
                 {:environment, scope.environment.id}
               )

      assert {:ok, _permission} = Roles.grant_permission(scope.environment_role.id, :environment_read)

      assert {:ok, _assignment} =
               ServiceAccountAccess.assign_role(%{
                 service_account_id: scope.service_account.id,
                 role_id: scope.environment_role.id,
                 environment_id: scope.environment.id
               })

      assert :ok =
               Access.authorize(
                 {:service_account, scope.service_account.id},
                 :environment_read,
                 {:environment, scope.environment.id}
               )

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:service_account, scope.service_account.id},
                 :environment_read,
                 {:organization, scope.organization.id}
               )
    end

    test "rejects service accounts outside the requested organization" do
      scope = create_service_account_scope()
      assert {:ok, other_organization} = Organizations.create(%{name: unique_name("Other")})

      assert {:error, :service_account_organization_mismatch} =
               Access.authorize(
                 {:service_account, scope.service_account.id},
                 :organization_read,
                 {:organization, other_organization.id}
               )
    end

    test "returns service account lifecycle errors" do
      scope = create_service_account_scope()

      assert {:error, :service_account_not_found} =
               Access.authorize(
                 {:service_account, "00000000-0000-0000-0000-000000000000"},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert {:ok, _service_account} = ServiceAccounts.disable(scope.service_account.id)

      assert {:error, :service_account_disabled} =
               Access.authorize(
                 {:service_account, scope.service_account.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )
    end
  end

  describe "authorization lifecycle" do
    test "missing and disabled scopes deny before actor evaluation" do
      scope = create_user_scope()

      assert {:error, :environment_not_found} =
               Access.authorize(
                 {:user, scope.user.id},
                 :environment_read,
                 {:environment, "00000000-0000-0000-0000-000000000000"}
               )

      assert {:error, :organization_not_found} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, "00000000-0000-0000-0000-000000000000"}
               )

      assert {:ok, _environment} = Environments.disable(scope.environment.id)

      assert {:error, :environment_disabled} =
               Access.authorize(
                 {:user, scope.user.id},
                 :environment_read,
                 {:environment, scope.environment.id}
               )

      assert {:ok, _organization} = Organizations.disable(scope.organization.id)

      assert {:error, :organization_disabled} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )
    end

    test "disabled roles and revoked permissions or assignments no longer authorize" do
      scope = create_user_scope()

      assert {:ok, _permission} = Roles.grant_permission(scope.role.id, :organization_read)

      assignment_attrs = %{
        membership_id: scope.membership.id,
        role_id: scope.role.id
      }

      assert {:ok, _assignment} = Access.assign_role(assignment_attrs)

      assert :ok =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert :ok = Roles.revoke_permission(scope.role.id, :organization_read)

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert {:ok, _permission} = Roles.grant_permission(scope.role.id, :organization_read)
      assert :ok = Access.revoke_role(assignment_attrs)

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )

      assert {:ok, _assignment} = Access.assign_role(assignment_attrs)
      assert {:ok, _role} = Roles.disable(scope.role.id)

      assert {:error, :permission_denied} =
               Access.authorize(
                 {:user, scope.user.id},
                 :organization_read,
                 {:organization, scope.organization.id}
               )
    end
  end

  defp create_user_scope do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} = Organizations.create(%{name: "Auth User #{suffix}"})
    assert {:ok, user} = Users.create(%{email: "auth-user-#{suffix}@example.com"})

    assert {:ok, membership} =
             Access.add_member(%{
               organization_id: organization.id,
               user_id: user.id
             })

    assert {:ok, role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "role-#{suffix}"
             })

    assert {:ok, environment} =
             Environments.create(%{
               organization_id: organization.id,
               name: "env-#{suffix}"
             })

    %{
      organization: organization,
      user: user,
      membership: membership,
      role: role,
      environment: environment
    }
  end

  defp create_service_account_scope do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} = Organizations.create(%{name: "Auth Service #{suffix}"})

    assert {:ok, service_account} =
             ServiceAccounts.create(%{
               organization_id: organization.id,
               name: "agent-#{suffix}"
             })

    assert {:ok, organization_role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "org-role-#{suffix}"
             })

    assert {:ok, environment_role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "env-role-#{suffix}"
             })

    assert {:ok, environment} =
             Environments.create(%{
               organization_id: organization.id,
               name: "env-#{suffix}"
             })

    %{
      organization: organization,
      service_account: service_account,
      organization_role: organization_role,
      environment_role: environment_role,
      environment: environment
    }
  end

  defp unique_name(prefix) do
    "#{prefix} #{System.unique_integer([:positive])}"
  end

  defp unique_email(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end
