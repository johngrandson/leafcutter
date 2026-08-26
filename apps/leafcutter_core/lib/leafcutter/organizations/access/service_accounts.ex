defmodule Leafcutter.Organizations.Access.ServiceAccounts do
  @moduledoc """
  Public access capability for service account role assignments.

  Service accounts receive roles independently from user memberships while
  preserving the same organization-wide and environment-scoped authorization
  semantics.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.{
    Environment,
    Organization,
    Role,
    ServiceAccount,
    ServiceAccountRoleAssignment
  }

  alias Leafcutter.Repo

  @typedoc """
  Error returned when a role cannot be assigned to a service account.

  Assignment requires an active organization, service account, role, and
  optional environment that all belong to the same organization scope.
  """
  @type assign_role_error ::
          :service_account_not_found
          | :service_account_disabled
          | :organization_not_found
          | :organization_disabled
          | :role_not_found
          | :role_disabled
          | :role_organization_mismatch
          | :environment_not_found
          | :environment_disabled
          | :environment_organization_mismatch
          | :role_already_assigned
          | Ecto.Changeset.t()

  @doc """
  Assigns a role to an active service account within an active scope.

  ## Parameters

  * `attrs` - The service account and role identifiers plus an optional environment identifier

  ## Returns

  * `{:ok, role_assignment}` when the role is assigned
  * `{:error, :service_account_not_found}` when the service account does not exist
  * `{:error, :service_account_disabled}` when the service account is disabled
  * `{:error, :organization_not_found}` when the service account organization does not exist
  * `{:error, :organization_disabled}` when the service account organization is disabled
  * `{:error, :role_not_found}` when the role does not exist
  * `{:error, :role_disabled}` when the role is disabled
  * `{:error, :role_organization_mismatch}` when the role belongs to another organization
  * `{:error, :environment_not_found}` when the requested environment does not exist
  * `{:error, :environment_disabled}` when the requested environment is disabled
  * `{:error, :environment_organization_mismatch}` when the environment belongs to another organization
  * `{:error, :role_already_assigned}` when the same role already exists in the requested scope
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Service Account Access Organization"})

      iex> {:ok, service_account} =
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production-sync"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> match?(
      ...>   {:ok, %{service_account_id: service_account_id, role_id: role_id, environment_id: nil}}
      ...>   when service_account_id == service_account.id and role_id == role.id,
      ...>   Leafcutter.Organizations.Access.ServiceAccounts.assign_role(%{
      ...>     service_account_id: service_account.id,
      ...>     role_id: role.id
      ...>   })
      ...> )
      true

  ## Notes

  * Omitting `environment_id` assigns the role organization-wide.
  * Providing `environment_id` scopes the role to one environment.
  * Organization-wide and environment-scoped assignments may coexist.
  * The organization, service account, role, and optional environment must be active.
  * Role and environment scope must match the service account organization.
  * Locks are acquired in the order Organization, ServiceAccount, Role, Environment.
  """
  @spec assign_role(ServiceAccountRoleAssignment.create_attrs()) ::
          {:ok, ServiceAccountRoleAssignment.t()} | {:error, assign_role_error()}
  def assign_role(attrs) do
    changeset =
      ServiceAccountRoleAssignment.create_changeset(
        %ServiceAccountRoleAssignment{},
        attrs
      )

    if changeset.valid? do
      assign_role_with_active_scope(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid assignment changeset containing service_account_id and
  # role_id, with an optional environment_id.
  @spec assign_role_with_active_scope(Ecto.Changeset.t()) ::
          {:ok, ServiceAccountRoleAssignment.t()} | {:error, assign_role_error()}
  defp assign_role_with_active_scope(changeset) do
    service_account_id = Ecto.Changeset.fetch_field!(changeset, :service_account_id)
    role_id = Ecto.Changeset.fetch_field!(changeset, :role_id)
    environment_id = Ecto.Changeset.get_field(changeset, :environment_id)

    Repo.transaction(fn ->
      organization_id = service_account_organization_id(service_account_id)

      lock_active_organization(organization_id)
      lock_active_service_account(service_account_id)

      role = lock_active_role(role_id)
      ensure_role_organization(role, organization_id)

      lock_assignment_environment(environment_id, organization_id)
      ensure_role_assignment_absent(service_account_id, role_id, environment_id)
      persist_role_assignment(changeset)
    end)
  end

  @spec service_account_organization_id(ServiceAccount.id()) :: Organization.id()
  defp service_account_organization_id(service_account_id) do
    case Repo.get(ServiceAccount, service_account_id) do
      nil -> Repo.rollback(:service_account_not_found)
      %ServiceAccount{organization_id: organization_id} -> organization_id
    end
  end

  @spec lock_active_organization(Organization.id()) :: :ok
  defp lock_active_organization(organization_id) do
    Organization
    |> where([organization], organization.id == ^organization_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:organization_not_found)

      %Organization{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:organization_disabled)

      %Organization{} ->
        :ok
    end
  end

  @spec lock_active_service_account(ServiceAccount.id()) :: ServiceAccount.t()
  defp lock_active_service_account(service_account_id) do
    ServiceAccount
    |> where([service_account], service_account.id == ^service_account_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:service_account_not_found)

      %ServiceAccount{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:service_account_disabled)

      %ServiceAccount{} = service_account ->
        service_account
    end
  end

  @spec lock_active_role(Role.id()) :: Role.t()
  defp lock_active_role(role_id) do
    Role
    |> where([role], role.id == ^role_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:role_not_found)

      %Role{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:role_disabled)

      %Role{} = role ->
        role
    end
  end

  @spec ensure_role_organization(Role.t(), Organization.id()) :: :ok
  defp ensure_role_organization(%Role{organization_id: organization_id}, organization_id), do: :ok

  defp ensure_role_organization(%Role{}, _organization_id) do
    Repo.rollback(:role_organization_mismatch)
  end

  @spec lock_assignment_environment(Environment.id() | nil, Organization.id()) :: :ok
  defp lock_assignment_environment(nil, _organization_id), do: :ok

  defp lock_assignment_environment(environment_id, organization_id) do
    Environment
    |> where([environment], environment.id == ^environment_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:environment_not_found)

      %Environment{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:environment_disabled)

      %Environment{organization_id: ^organization_id} ->
        :ok

      %Environment{} ->
        Repo.rollback(:environment_organization_mismatch)
    end
  end

  @spec ensure_role_assignment_absent(
          ServiceAccount.id(),
          Role.id(),
          Environment.id() | nil
        ) :: :ok
  defp ensure_role_assignment_absent(service_account_id, role_id, environment_id) do
    service_account_id
    |> role_assignment_query(role_id, environment_id)
    |> Repo.one()
    |> case do
      nil -> :ok
      %ServiceAccountRoleAssignment{} -> Repo.rollback(:role_already_assigned)
    end
  end

  @spec persist_role_assignment(Ecto.Changeset.t()) :: ServiceAccountRoleAssignment.t()
  defp persist_role_assignment(changeset) do
    case Repo.insert(changeset) do
      {:ok, role_assignment} ->
        role_assignment

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Revokes a role assignment from a service account.

  ## Parameters

  * `attrs` - The service account and role identifiers plus the optional environment scope

  ## Returns

  * `:ok` when the role assignment is revoked
  * `:ok` when the role assignment did not exist
  * `{:error, changeset}` when the assignment identity attributes are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Service Account Revoke Organization"})

      iex> {:ok, service_account} =
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production-sync"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> {:ok, _assignment} =
      ...>   Leafcutter.Organizations.Access.ServiceAccounts.assign_role(%{
      ...>     service_account_id: service_account.id,
      ...>     role_id: role.id
      ...>   })

      iex> Leafcutter.Organizations.Access.ServiceAccounts.revoke_role(%{
      ...>   service_account_id: service_account.id,
      ...>   role_id: role.id
      ...> })
      :ok

  ## Notes

  * The operation is idempotent.
  * Revocation is allowed when related resources are disabled.
  * Omitting `environment_id` revokes only the organization-wide assignment.
  * Providing `environment_id` revokes only that environment-scoped assignment.
  * Assignments represent current authorization state and are physically deleted.
  * Historical tracking belongs to the audit capability.
  """
  @spec revoke_role(ServiceAccountRoleAssignment.create_attrs()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def revoke_role(attrs) do
    changeset =
      ServiceAccountRoleAssignment.create_changeset(
        %ServiceAccountRoleAssignment{},
        attrs
      )

    if changeset.valid? do
      revoke_role_assignment(changeset)
    else
      {:error, changeset}
    end
  end

  @spec revoke_role_assignment(Ecto.Changeset.t()) :: :ok
  defp revoke_role_assignment(changeset) do
    service_account_id = Ecto.Changeset.fetch_field!(changeset, :service_account_id)
    role_id = Ecto.Changeset.fetch_field!(changeset, :role_id)
    environment_id = Ecto.Changeset.get_field(changeset, :environment_id)

    Repo.transaction(fn ->
      lock_service_account_if_present(service_account_id)

      service_account_id
      |> role_assignment_query(role_id, environment_id)
      |> Repo.delete_all()

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
    end
  end

  @spec lock_service_account_if_present(ServiceAccount.id()) :: :ok
  defp lock_service_account_if_present(service_account_id) do
    ServiceAccount
    |> where([service_account], service_account.id == ^service_account_id)
    |> lock("FOR UPDATE")
    |> Repo.one()

    :ok
  end

  @spec role_assignment_query(ServiceAccount.id(), Role.id(), Environment.id() | nil) ::
          Ecto.Query.t()
  defp role_assignment_query(service_account_id, role_id, nil) do
    ServiceAccountRoleAssignment
    |> where(
      [role_assignment],
      role_assignment.service_account_id == ^service_account_id and
        role_assignment.role_id == ^role_id and
        is_nil(role_assignment.environment_id)
    )
  end

  defp role_assignment_query(service_account_id, role_id, environment_id) do
    ServiceAccountRoleAssignment
    |> where(
      [role_assignment],
      role_assignment.service_account_id == ^service_account_id and
        role_assignment.role_id == ^role_id and
        role_assignment.environment_id == ^environment_id
    )
  end
end
