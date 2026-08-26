defmodule Leafcutter.Organizations.Roles do
  @moduledoc """
  Public capability module for managing authorization roles.

  Roles are scoped to organizations and group permissions that may be
  assigned to authorization subjects through the access capability.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.{Organization, Role}

  alias Leafcutter.Organizations.{
    Organization,
    Permission,
    Role,
    RolePermission
  }

  alias Leafcutter.Repo

  @doc """
  Creates a role within an active organization.

  ## Parameters

  * `attrs` - The attributes used to create the role, including the
    organization identifier and role name

  ## Returns

  * `{:ok, role}` when the role is persisted
  * `{:error, :organization_not_found}` when the referenced organization does not exist
  * `{:error, :organization_disabled}` when the referenced organization is disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Role Example Organization"
      ...>   })

      iex> match?(
      ...>   {:ok, %{name: "operator"}},
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })
      ...> )
      true

  ## Notes

  * The referenced organization must exist and be active.
  * Role names are unique within their organization.
  * Creating a role does not grant any permissions.
  * Permissions are granted through a separate authorization operation.
  * The organization row is locked while its lifecycle state is checked and
    the role is persisted.
  """
  @spec create(Role.create_attrs()) ::
          {:ok, Role.t()}
          | {:error, :organization_not_found}
          | {:error, :organization_disabled}
          | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    changeset = Role.create_changeset(%Role{}, attrs)

    if changeset.valid? do
      create_with_active_organization(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid role creation changeset containing organization_id.
  # The organization row remains locked until the role insertion completes.
  @spec create_with_active_organization(Ecto.Changeset.t()) ::
          {:ok, Role.t()}
          | {:error, :organization_not_found}
          | {:error, :organization_disabled}
          | {:error, Ecto.Changeset.t()}
  defp create_with_active_organization(changeset) do
    organization_id =
      Ecto.Changeset.fetch_field!(changeset, :organization_id)

    Repo.transaction(fn ->
      Organization
      |> where([organization], organization.id == ^organization_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_role_creation(changeset)
    end)
  end

  @spec persist_role_creation(Organization.t() | nil, Ecto.Changeset.t()) :: Role.t()
  defp persist_role_creation(nil, _changeset) do
    Repo.rollback(:organization_not_found)
  end

  defp persist_role_creation(%Organization{disabled_at: disabled_at}, _changeset)
       when not is_nil(disabled_at) do
    Repo.rollback(:organization_disabled)
  end

  defp persist_role_creation(%Organization{}, changeset) do
    case Repo.insert(changeset) do
      {:ok, role} ->
        role

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Fetches a role by its identifier.

  ## Parameters

  * `id` - The identifier of the role to fetch

  ## Returns

  * `{:ok, role}` when the role exists
  * `{:error, :not_found}` when no role exists with the given identifier

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Role Lookup Organization"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Organizations.Roles.get(role.id)

      iex> fetched.id == role.id
      true

  ## Notes

  * Disabled roles are returned normally.
  * Lifecycle state does not affect lookup semantics.
  * Permissions are not preloaded by this operation.
  """
  @spec get(Role.id()) ::
          {:ok, Role.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Role, id) do
      %Role{} = role ->
        {:ok, role}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Disables a role.

  ## Parameters

  * `id` - The identifier of the role to disable

  ## Returns

  * `{:ok, role}` when the role is disabled
  * `{:ok, role}` when the role was already disabled
  * `{:error, :not_found}` when the role does not exist
  * `{:error, changeset}` when the lifecycle change cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Role Disable Organization"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> {:ok, disabled} =
      ...>   Leafcutter.Organizations.Roles.disable(role.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Persisted permissions and historical assignments are not deleted.
  * A disabled role must not participate in future authorization decisions.
  * The role row is locked while the lifecycle transition is evaluated and persisted.
  """
  @spec disable(Role.id()) ::
          {:ok, Role.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def disable(id) do
    Repo.transaction(fn ->
      Role
      |> where([role], role.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_role_disable()
    end)
  end

  @spec persist_role_disable(Role.t() | nil) :: Role.t()
  defp persist_role_disable(nil) do
    Repo.rollback(:not_found)
  end

  defp persist_role_disable(%Role{} = role) do
    role
    |> Role.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, role} ->
        role

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Grants a permission to an active role within an active organization.

  ## Parameters

  * `role_id` - The identifier of the role receiving the permission
  * `permission` - The typed domain permission to grant

  ## Returns

  * `{:ok, role_permission}` when the permission is granted
  * `{:error, :role_not_found}` when the role does not exist
  * `{:error, :role_disabled}` when the role is disabled
  * `{:error, :organization_disabled}` when the role's organization is disabled
  * `{:error, :permission_already_granted}` when the role already has the permission
  * `{:error, changeset}` when the association cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Permission Grant Organization"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> match?(
      ...>   {:ok, %{permission: "environment.read"}},
      ...>   Leafcutter.Organizations.Roles.grant_permission(
      ...>     role.id,
      ...>     :environment_read
      ...>   )
      ...> )
      true

  ## Notes

  * Permissions are accepted as typed domain atoms, not arbitrary strings.
  * The canonical string identifier is used only at the persistence boundary.
  * Granting the same permission twice does not create duplicate associations.
  * A disabled role or organization cannot receive new permissions.
  """
  @spec grant_permission(Role.id(), Permission.t()) ::
          {:ok, RolePermission.t()}
          | {:error, :role_not_found}
          | {:error, :role_disabled}
          | {:error, :organization_disabled}
          | {:error, :permission_already_granted}
          | {:error, Ecto.Changeset.t()}
  def grant_permission(role_id, permission) do
    permission_identifier = Permission.identifier(permission)

    grant_permission_to_active_role(role_id, permission_identifier)
  end

  # Locks the organization before the role so authorization mutations follow a
  # consistent lock order.
  @spec grant_permission_to_active_role(Role.id(), String.t()) ::
          {:ok, RolePermission.t()}
          | {:error, :role_not_found}
          | {:error, :role_disabled}
          | {:error, :organization_disabled}
          | {:error, :permission_already_granted}
          | {:error, Ecto.Changeset.t()}
  defp grant_permission_to_active_role(role_id, permission_identifier) do
    Repo.transaction(fn ->
      role = Repo.get(Role, role_id)

      if is_nil(role) do
        Repo.rollback(:role_not_found)
      end

      organization =
        Organization
        |> where([organization], organization.id == ^role.organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if organization.disabled_at do
        Repo.rollback(:organization_disabled)
      end

      role =
        Role
        |> where([role], role.id == ^role_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case role do
        nil ->
          Repo.rollback(:role_not_found)

        %Role{disabled_at: disabled_at} when not is_nil(disabled_at) ->
          Repo.rollback(:role_disabled)

        %Role{} ->
          persist_role_permission(role.id, permission_identifier)
      end
    end)
  end

  @spec persist_role_permission(Role.id(), String.t()) ::
          RolePermission.t() | no_return()
  defp persist_role_permission(role_id, permission_identifier) do
    existing =
      RolePermission
      |> where(
        [role_permission],
        role_permission.role_id == ^role_id and
          role_permission.permission == ^permission_identifier
      )
      |> Repo.one()

    if existing do
      Repo.rollback(:permission_already_granted)
    end

    changeset =
      RolePermission.create_changeset(
        %RolePermission{},
        %{
          role_id: role_id,
          permission: permission_identifier
        }
      )

    case Repo.insert(changeset) do
      {:ok, role_permission} ->
        role_permission

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Revokes a permission from a role.

  ## Parameters

  * `role_id` - The identifier of the role whose permission will be revoked
  * `permission` - The typed domain permission to revoke

  ## Returns

  * `:ok` when the permission is revoked
  * `:ok` when the permission was not granted
  * `{:error, :role_not_found}` when the role does not exist

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Permission Revoke Organization"
      ...>   })

      iex> {:ok, role} =
      ...>   Leafcutter.Organizations.Roles.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "operator"
      ...>   })

      iex> {:ok, _role_permission} =
      ...>   Leafcutter.Organizations.Roles.grant_permission(
      ...>     role.id,
      ...>     :environment_read
      ...>   )

      iex> Leafcutter.Organizations.Roles.revoke_permission(
      ...>   role.id,
      ...>   :environment_read
      ...> )
      :ok

  ## Notes

  * The operation is idempotent.
  * Revocation is allowed even when the role or organization is disabled.
  * Role permissions represent current authorization state and are physically
    deleted when revoked.
  * Historical tracking of permission changes belongs to the audit capability,
    not to `role_permissions`.
  * The role row is locked while the permission association is removed to
    serialize permission mutations for that role.
  """
  @spec revoke_permission(Role.id(), Permission.t()) ::
          :ok | {:error, :role_not_found}
  def revoke_permission(role_id, permission) do
    permission_identifier = Permission.identifier(permission)

    Repo.transaction(fn ->
      role =
        Role
        |> where([role], role.id == ^role_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case role do
        nil ->
          Repo.rollback(:role_not_found)

        %Role{} ->
          RolePermission
          |> where(
            [role_permission],
            role_permission.role_id == ^role_id and
              role_permission.permission == ^permission_identifier
          )
          |> Repo.delete_all()

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, :role_not_found} -> {:error, :role_not_found}
    end
  end
end
