defmodule Leafcutter.Organizations.Access do
  @moduledoc """
  Public capability module for managing organization access.

  Access coordinates memberships and, as the authorization model evolves,
  role and permission assignments within organization scopes.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.{
    Environment,
    Membership,
    Organization,
    Role,
    RoleAssignment,
    User
  }

  alias Leafcutter.Repo

  @typedoc """
  Error returned when a membership cannot be created.

  The organization or user may be missing or disabled, the membership may
  already exist, or persistence may fail validation or a database constraint.
  """
  @type add_member_error ::
          :organization_not_found
          | :organization_disabled
          | :user_not_found
          | :user_disabled
          | :membership_already_exists
          | Ecto.Changeset.t()

  @typedoc """
  Error returned when a membership cannot be removed.

  The membership may not exist, or the lifecycle change may fail validation
  or a database constraint.
  """
  @type remove_member_error :: :membership_not_found | Ecto.Changeset.t()

  @typedoc """
  Error returned when a role cannot be assigned.

  Assignment requires an active organization, membership, role, and optional
  environment that all belong to the same organization scope.
  """
  @type assign_role_error ::
          :membership_not_found
          | :membership_disabled
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
  Adds a user as a member of an active organization.

  ## Parameters

  * `attrs` - The organization and user identifiers used to create the membership

  ## Returns

  * `{:ok, membership}` when the membership is persisted
  * `{:error, :organization_not_found}` when the organization does not exist
  * `{:error, :organization_disabled}` when the organization is disabled
  * `{:error, :user_not_found}` when the user does not exist
  * `{:error, :user_disabled}` when the user is disabled
  * `{:error, :membership_already_exists}` when the user already has a membership
    in the organization
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Access Example Organization"})

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{
      ...>     email: "access-example@example.com"
      ...>   })

      iex> match?(
      ...>   {:ok, %{organization_id: organization_id, user_id: user_id}}
      ...>   when organization_id == organization.id and user_id == user.id,
      ...>   Leafcutter.Organizations.Access.add_member(%{
      ...>     organization_id: organization.id,
      ...>     user_id: user.id
      ...>   })
      ...> )
      true

  ## Notes

  * Both the organization and user must exist and be active.
  * A user may have at most one membership within the same organization.
  * A disabled membership is not implicitly reactivated by this operation.
  * Organization and user rows are locked in that order while lifecycle
    invariants are evaluated.
  """
  @spec add_member(Membership.create_attrs()) ::
          {:ok, Membership.t()} | {:error, add_member_error()}
  def add_member(attrs) do
    changeset = Membership.create_changeset(%Membership{}, attrs)

    if changeset.valid? do
      add_member_with_active_participants(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid membership creation changeset containing both
  # organization_id and user_id.
  @spec add_member_with_active_participants(Ecto.Changeset.t()) ::
          {:ok, Membership.t()} | {:error, add_member_error()}
  defp add_member_with_active_participants(changeset) do
    organization_id =
      Ecto.Changeset.fetch_field!(changeset, :organization_id)

    user_id =
      Ecto.Changeset.fetch_field!(changeset, :user_id)

    Repo.transaction(fn ->
      lock_active_organization(organization_id)
      lock_active_user(user_id)
      ensure_membership_absent(organization_id, user_id)
      persist_membership(changeset)
    end)
  end

  @spec lock_active_organization(Organization.id()) :: :ok
  defp lock_active_organization(organization_id) do
    organization =
      Organization
      |> where([organization], organization.id == ^organization_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case organization do
      nil ->
        Repo.rollback(:organization_not_found)

      %Organization{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:organization_disabled)

      %Organization{} ->
        :ok
    end
  end

  @spec lock_active_user(User.id()) :: :ok
  defp lock_active_user(user_id) do
    user =
      User
      |> where([user], user.id == ^user_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case user do
      nil ->
        Repo.rollback(:user_not_found)

      %User{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:user_disabled)

      %User{} ->
        :ok
    end
  end

  @spec ensure_membership_absent(Organization.id(), User.id()) :: :ok
  defp ensure_membership_absent(organization_id, user_id) do
    Membership
    |> where(
      [membership],
      membership.organization_id == ^organization_id and
        membership.user_id == ^user_id
    )
    |> Repo.one()
    |> case do
      nil -> :ok
      %Membership{} -> Repo.rollback(:membership_already_exists)
    end
  end

  @spec persist_membership(Ecto.Changeset.t()) :: Membership.t()
  defp persist_membership(changeset) do
    case Repo.insert(changeset) do
      {:ok, membership} ->
        membership

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Removes a user from an organization by disabling the membership.

  ## Parameters

  * `organization_id` - The identifier of the organization
  * `user_id` - The identifier of the user whose membership will be disabled

  ## Returns

  * `{:ok, membership}` when the membership is disabled
  * `{:ok, membership}` when the membership was already disabled
  * `{:error, :membership_not_found}` when no membership exists for the
    organization and user
  * `{:error, changeset}` when the lifecycle change cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Remove Member Example"
      ...>   })

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{
      ...>     email: "remove-member@example.com"
      ...>   })

      iex> {:ok, _membership} =
      ...>   Leafcutter.Organizations.Access.add_member(%{
      ...>     organization_id: organization.id,
      ...>     user_id: user.id
      ...>   })

      iex> {:ok, removed} =
      ...>   Leafcutter.Organizations.Access.remove_member(
      ...>     organization.id,
      ...>     user.id
      ...>   )

      iex> is_struct(removed.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent for an existing membership.
  * An existing `disabled_at` timestamp is preserved.
  * The membership is retained as durable history rather than deleted.
  * Organization and user lifecycle state do not prevent membership removal.
  * The membership row is locked while the lifecycle transition is evaluated
    and persisted.
  """
  @spec remove_member(Organization.id(), User.id()) ::
          {:ok, Membership.t()} | {:error, remove_member_error()}
  def remove_member(organization_id, user_id) do
    Repo.transaction(fn ->
      Membership
      |> where(
        [membership],
        membership.organization_id == ^organization_id and
          membership.user_id == ^user_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_membership_removal()
    end)
  end

  @spec persist_membership_removal(Membership.t() | nil) :: Membership.t()
  defp persist_membership_removal(nil) do
    Repo.rollback(:membership_not_found)
  end

  defp persist_membership_removal(%Membership{} = membership) do
    membership
    |> Membership.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, membership} ->
        membership

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Assigns a role to an active membership within an active scope.

  ## Parameters

  * `attrs` - The membership and role identifiers plus an optional environment identifier

  ## Returns

  * `{:ok, role_assignment}` when the role is assigned
  * `{:error, :membership_not_found}` when the membership does not exist
  * `{:error, :membership_disabled}` when the membership is disabled
  * `{:error, :organization_not_found}` when the membership organization does not exist
  * `{:error, :organization_disabled}` when the membership organization is disabled
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
      ...>   Leafcutter.Organizations.create(%{name: "Role Assignment Organization"})

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{email: "role-assignment@example.com"})

      iex> {:ok, membership} =
      ...>   Leafcutter.Organizations.Access.add_member(%{
      ...>     organization_id: organization.id,
      ...>     user_id: user.id
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> match?(
      ...>   {:ok, %{membership_id: membership_id, role_id: role_id, environment_id: nil}}
      ...>   when membership_id == membership.id and role_id == role.id,
      ...>   Leafcutter.Organizations.Access.assign_role(%{
      ...>     membership_id: membership.id,
      ...>     role_id: role.id
      ...>   })
      ...> )
      true

  ## Notes

  * Omitting `environment_id` assigns the role organization-wide.
  * Providing `environment_id` scopes the role to one environment.
  * Organization-wide and environment-scoped assignments may coexist.
  * The organization, membership, role, and optional environment must be active.
  * Role and environment scope must match the membership organization.
  * Locks are acquired in the order Organization, Membership, Role, Environment.
  """
  @spec assign_role(RoleAssignment.create_attrs()) ::
          {:ok, RoleAssignment.t()} | {:error, assign_role_error()}
  def assign_role(attrs) do
    changeset = RoleAssignment.create_changeset(%RoleAssignment{}, attrs)

    if changeset.valid? do
      assign_role_with_active_scope(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid role assignment changeset containing membership_id and
  # role_id, with an optional environment_id.
  @spec assign_role_with_active_scope(Ecto.Changeset.t()) ::
          {:ok, RoleAssignment.t()} | {:error, assign_role_error()}
  defp assign_role_with_active_scope(changeset) do
    membership_id = Ecto.Changeset.fetch_field!(changeset, :membership_id)
    role_id = Ecto.Changeset.fetch_field!(changeset, :role_id)
    environment_id = Ecto.Changeset.get_field(changeset, :environment_id)

    Repo.transaction(fn ->
      organization_id = membership_organization_id(membership_id)

      lock_active_organization(organization_id)
      lock_active_membership(membership_id)

      role = lock_active_role(role_id)
      ensure_role_organization(role, organization_id)

      lock_assignment_environment(environment_id, organization_id)
      ensure_role_assignment_absent(membership_id, role_id, environment_id)
      persist_role_assignment(changeset)
    end)
  end

  @spec membership_organization_id(Membership.id()) :: Organization.id()
  defp membership_organization_id(membership_id) do
    case Repo.get(Membership, membership_id) do
      nil -> Repo.rollback(:membership_not_found)
      %Membership{organization_id: organization_id} -> organization_id
    end
  end

  @spec lock_active_membership(Membership.id()) :: Membership.t()
  defp lock_active_membership(membership_id) do
    Membership
    |> where([membership], membership.id == ^membership_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil ->
        Repo.rollback(:membership_not_found)

      %Membership{disabled_at: disabled_at} when not is_nil(disabled_at) ->
        Repo.rollback(:membership_disabled)

      %Membership{} = membership ->
        membership
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

  @spec ensure_role_assignment_absent(Membership.id(), Role.id(), Environment.id() | nil) :: :ok
  defp ensure_role_assignment_absent(membership_id, role_id, environment_id) do
    membership_id
    |> role_assignment_query(role_id, environment_id)
    |> Repo.one()
    |> case do
      nil -> :ok
      %RoleAssignment{} -> Repo.rollback(:role_already_assigned)
    end
  end

  @spec persist_role_assignment(Ecto.Changeset.t()) :: RoleAssignment.t()
  defp persist_role_assignment(changeset) do
    case Repo.insert(changeset) do
      {:ok, role_assignment} ->
        role_assignment

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Revokes a role assignment from a membership.

  ## Parameters

  * `attrs` - The membership and role identifiers plus the optional environment scope

  ## Returns

  * `:ok` when the role assignment is revoked
  * `:ok` when the role assignment did not exist
  * `{:error, changeset}` when the assignment identity attributes are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Role Revoke Organization"})

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{email: "role-revoke@example.com"})

      iex> {:ok, membership} =
      ...>   Leafcutter.Organizations.Access.add_member(%{
      ...>     organization_id: organization.id,
      ...>     user_id: user.id
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> {:ok, _assignment} =
      ...>   Leafcutter.Organizations.Access.assign_role(%{
      ...>     membership_id: membership.id,
      ...>     role_id: role.id
      ...>   })

      iex> Leafcutter.Organizations.Access.revoke_role(%{
      ...>   membership_id: membership.id,
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
  @spec revoke_role(RoleAssignment.create_attrs()) :: :ok | {:error, Ecto.Changeset.t()}
  def revoke_role(attrs) do
    changeset = RoleAssignment.create_changeset(%RoleAssignment{}, attrs)

    if changeset.valid? do
      revoke_role_assignment(changeset)
    else
      {:error, changeset}
    end
  end

  @spec revoke_role_assignment(Ecto.Changeset.t()) :: :ok
  defp revoke_role_assignment(changeset) do
    membership_id = Ecto.Changeset.fetch_field!(changeset, :membership_id)
    role_id = Ecto.Changeset.fetch_field!(changeset, :role_id)
    environment_id = Ecto.Changeset.get_field(changeset, :environment_id)

    Repo.transaction(fn ->
      lock_membership_if_present(membership_id)

      membership_id
      |> role_assignment_query(role_id, environment_id)
      |> Repo.delete_all()

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
    end
  end

  @spec lock_membership_if_present(Membership.id()) :: :ok
  defp lock_membership_if_present(membership_id) do
    Membership
    |> where([membership], membership.id == ^membership_id)
    |> lock("FOR UPDATE")
    |> Repo.one()

    :ok
  end

  @spec role_assignment_query(Membership.id(), Role.id(), Environment.id() | nil) :: Ecto.Query.t()
  defp role_assignment_query(membership_id, role_id, nil) do
    RoleAssignment
    |> where(
      [role_assignment],
      role_assignment.membership_id == ^membership_id and
        role_assignment.role_id == ^role_id and
        is_nil(role_assignment.environment_id)
    )
  end

  defp role_assignment_query(membership_id, role_id, environment_id) do
    RoleAssignment
    |> where(
      [role_assignment],
      role_assignment.membership_id == ^membership_id and
        role_assignment.role_id == ^role_id and
        role_assignment.environment_id == ^environment_id
    )
  end
end
