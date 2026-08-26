defmodule Leafcutter.Organizations.Users do
  @moduledoc """
  Public capability module for managing users within the Organizations context.

  Users represent platform-wide human identities. Their association with
  organizations is established separately through memberships.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.User
  alias Leafcutter.Repo

  @typedoc """
  Error returned when a user cannot be disabled.

  The user may not exist, or the lifecycle change may fail validation or a
  database constraint.
  """
  @type disable_error :: :not_found | Ecto.Changeset.t()

  @doc """
  Creates a user.

  ## Parameters

  * `attrs` - The attributes used to create the user

  ## Returns

  * `{:ok, user}` when the user is persisted
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:ok, %{email: "user@example.com"}},
      ...>   Leafcutter.Organizations.Users.create(%{
      ...>     email: " User@Example.COM "
      ...>   })
      ...> )
      true

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Organizations.Users.create(%{})
      ...> )
      true

  ## Notes

  * Email addresses are normalized before persistence.
  * Email addresses are globally unique within the platform.
  * Creating a user does not grant access to any organization.
  * Organization access will be established separately through memberships.
  """
  @spec create(User.create_attrs()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches a user by its identifier.

  ## Parameters

  * `id` - The identifier of the user to fetch

  ## Returns

  * `{:ok, user}` when the user exists
  * `{:error, :not_found}` when no user exists with the given identifier

  ## Examples

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{
      ...>     email: "lookup@example.com"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Organizations.Users.get(user.id)

      iex> fetched.id == user.id
      true

  ## Notes

  * Disabled users are returned normally.
  * Lifecycle state does not affect lookup semantics.
  """
  @spec get(User.id()) ::
          {:ok, User.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(User, id) do
      %User{} = user ->
        {:ok, user}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Disables a user.

  ## Parameters

  * `id` - The identifier of the user to disable

  ## Returns

  * `{:ok, user}` when the user is disabled
  * `{:ok, user}` when the user was already disabled
  * `{:error, :not_found}` when the user does not exist
  * `{:error, changeset}` when the lifecycle change cannot be persisted

  ## Examples

      iex> {:ok, user} =
      ...>   Leafcutter.Organizations.Users.create(%{
      ...>     email: "disable@example.com"
      ...>   })

      iex> {:ok, disabled} =
      ...>   Leafcutter.Organizations.Users.disable(user.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Disabling a user does not delete memberships or historical authorization data.
  * The user row is locked while the lifecycle transition is evaluated and
    persisted, keeping concurrent disable operations consistent.
  """
  @spec disable(User.id()) :: {:ok, User.t()} | {:error, disable_error()}
  def disable(id) do
    Repo.transaction(fn ->
      User
      |> where([user], user.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_disable()
    end)
  end

  defp persist_disable(nil) do
    Repo.rollback(:not_found)
  end

  defp persist_disable(%User{} = user) do
    user
    |> User.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, user} ->
        user

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end
end
