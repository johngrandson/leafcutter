defmodule Leafcutter.Organizations.Access do
  @moduledoc """
  Public capability module for managing organization access.

  Access coordinates memberships and, as the authorization model evolves,
  role and permission assignments within organization scopes.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.{Membership, Organization, User}
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
end
