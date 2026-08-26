defmodule Leafcutter.Organizations.Users do
  @moduledoc """
  Public capability module for managing users within the Organizations context.

  Users represent platform-wide human identities. Their association with
  organizations is established separately through memberships.
  """

  alias Leafcutter.Organizations.User
  alias Leafcutter.Repo

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
end
