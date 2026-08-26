defmodule Leafcutter.Organizations.Access.Authorization do
  @moduledoc false

  import Ecto.Query

  alias Leafcutter.Organizations.{
    Environment,
    Membership,
    Organization,
    Permission,
    Role,
    RoleAssignment,
    RolePermission,
    ServiceAccount,
    ServiceAccountRoleAssignment,
    User
  }

  alias Leafcutter.Repo

  @type actor :: {:user, User.id()} | {:service_account, ServiceAccount.id()}
  @type scope :: {:organization, Organization.id()} | {:environment, Environment.id()}

  @type error ::
          :organization_not_found
          | :organization_disabled
          | :environment_not_found
          | :environment_disabled
          | :user_not_found
          | :user_disabled
          | :membership_not_found
          | :membership_disabled
          | :service_account_not_found
          | :service_account_disabled
          | :service_account_organization_mismatch
          | :permission_denied

  @spec authorize(actor(), Permission.t(), scope()) :: :ok | {:error, error()}
  def authorize(actor, permission, scope) do
    permission_identifier = Permission.identifier(permission)

    with {:ok, resolved_scope} <- resolve_scope(scope),
         {:ok, authorization_subject} <- resolve_actor(actor, resolved_scope.organization_id),
         true <- permission_granted?(authorization_subject, permission_identifier, resolved_scope) do
      :ok
    else
      false -> {:error, :permission_denied}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec resolve_scope(scope()) ::
          {:ok, %{organization_id: Organization.id(), environment_id: Environment.id() | nil}}
          | {:error, error()}
  defp resolve_scope({:organization, organization_id}) do
    case Repo.get(Organization, organization_id) do
      nil ->
        {:error, :organization_not_found}

      %Organization{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        {:error, :organization_disabled}

      %Organization{} ->
        {:ok, %{organization_id: organization_id, environment_id: nil}}
    end
  end

  defp resolve_scope({:environment, environment_id}) do
    case Repo.get(Environment, environment_id) do
      nil ->
        {:error, :environment_not_found}

      %Environment{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        {:error, :environment_disabled}

      %Environment{organization_id: organization_id} ->
        case resolve_scope({:organization, organization_id}) do
          {:ok, _organization_scope} ->
            {:ok, %{organization_id: organization_id, environment_id: environment_id}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec resolve_actor(actor(), Organization.id()) ::
          {:ok, {:membership, Membership.id()} | {:service_account, ServiceAccount.id()}}
          | {:error, error()}
  defp resolve_actor({:user, user_id}, organization_id) do
    with :ok <- ensure_active_user(user_id),
         {:ok, membership} <- active_membership(user_id, organization_id) do
      {:ok, {:membership, membership.id}}
    end
  end

  defp resolve_actor({:service_account, service_account_id}, organization_id) do
    case Repo.get(ServiceAccount, service_account_id) do
      nil ->
        {:error, :service_account_not_found}

      %ServiceAccount{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        {:error, :service_account_disabled}

      %ServiceAccount{organization_id: ^organization_id} ->
        {:ok, {:service_account, service_account_id}}

      %ServiceAccount{} ->
        {:error, :service_account_organization_mismatch}
    end
  end

  @spec ensure_active_user(User.id()) :: :ok | {:error, error()}
  defp ensure_active_user(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      %User{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        {:error, :user_disabled}

      %User{} ->
        :ok
    end
  end

  @spec active_membership(User.id(), Organization.id()) ::
          {:ok, Membership.t()} | {:error, error()}
  defp active_membership(user_id, organization_id) do
    Membership
    |> where(
      [membership],
      membership.user_id == ^user_id and membership.organization_id == ^organization_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :membership_not_found}

      %Membership{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        {:error, :membership_disabled}

      %Membership{} = membership ->
        {:ok, membership}
    end
  end

  @spec permission_granted?(
          {:membership, Membership.id()} | {:service_account, ServiceAccount.id()},
          String.t(),
          %{organization_id: Organization.id(), environment_id: Environment.id() | nil}
        ) :: boolean()
  defp permission_granted?({:membership, membership_id}, permission_identifier, scope) do
    membership_id
    |> membership_permission_query(permission_identifier, scope)
    |> Repo.exists?()
  end

  defp permission_granted?({:service_account, service_account_id}, permission_identifier, scope) do
    service_account_id
    |> service_account_permission_query(permission_identifier, scope)
    |> Repo.exists?()
  end

  @spec membership_permission_query(
          Membership.id(),
          String.t(),
          %{organization_id: Organization.id(), environment_id: Environment.id() | nil}
        ) :: Ecto.Query.t()
  defp membership_permission_query(membership_id, permission_identifier, scope) do
    organization_id = scope.organization_id
    environment_id = scope.environment_id

    RoleAssignment
    |> join(:inner, [assignment], role in Role, on: role.id == assignment.role_id)
    |> join(:inner, [_assignment, role], permission in RolePermission,
      on: permission.role_id == role.id
    )
    |> where(
      [assignment, role, permission],
      assignment.membership_id == ^membership_id and
        role.organization_id == ^organization_id and
        is_nil(role.disabled_at) and
        permission.permission == ^permission_identifier
    )
    |> apply_assignment_scope(environment_id)
  end

  @spec service_account_permission_query(
          ServiceAccount.id(),
          String.t(),
          %{organization_id: Organization.id(), environment_id: Environment.id() | nil}
        ) :: Ecto.Query.t()
  defp service_account_permission_query(service_account_id, permission_identifier, scope) do
    organization_id = scope.organization_id
    environment_id = scope.environment_id

    ServiceAccountRoleAssignment
    |> join(:inner, [assignment], role in Role, on: role.id == assignment.role_id)
    |> join(:inner, [_assignment, role], permission in RolePermission,
      on: permission.role_id == role.id
    )
    |> where(
      [assignment, role, permission],
      assignment.service_account_id == ^service_account_id and
        role.organization_id == ^organization_id and
        is_nil(role.disabled_at) and
        permission.permission == ^permission_identifier
    )
    |> apply_assignment_scope(environment_id)
  end

  @spec apply_assignment_scope(Ecto.Query.t(), Environment.id() | nil) :: Ecto.Query.t()
  defp apply_assignment_scope(query, nil) do
    where(query, [assignment, _role, _permission], is_nil(assignment.environment_id))
  end

  defp apply_assignment_scope(query, environment_id) do
    where(
      query,
      [assignment, _role, _permission],
      is_nil(assignment.environment_id) or assignment.environment_id == ^environment_id
    )
  end
end
