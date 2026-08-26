defmodule Leafcutter.Organizations do
  @moduledoc """
  Public facade for the Organizations context.

  This module exposes operations related to the primary organization
  lifecycle while specialized capabilities live in dedicated modules.
  """
  import Ecto.Query

  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  @doc """
  Creates an organization.

  ## Parameters

  * attrs - The attributes used to create the organization

  ## Returns

  * `{:ok, organization}` when the organization is persisted
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:ok, %{name: "Test Organization"}},
      ...>   Leafcutter.Organizations.create(%{name: "Test Organization"})
      ...> )
      true

      iex> match?({:error, %{valid?: false}}, Leafcutter.Organizations.create(%{}))
      true

      iex> match?({:error, %{valid?: false}}, Leafcutter.Organizations.create(%{name: ""}))
      true

  ## Notes

  * The name is required and may contain at most 255 characters.
  * `disabled_at` is not accepted during creation and defaults to `nil`.
  """
  @spec create(Organization.create_attrs()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Organization{}
    |> Organization.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches an organization by its identifier.

  ## Parameters

  * id - The organization UUID

  ## Returns

  * `{:ok, organization}` when the organization exists
  * `{:error, :not_found}` when the organization does not exist

  ## Examples

      iex> with {:ok, organization} <-
      ...>        Leafcutter.Organizations.create(%{name: "Lookup Example"}),
      ...>      do: Leafcutter.Organizations.get(organization.id) == {:ok, organization}
      true

      iex> Leafcutter.Organizations.get("00000000-0000-0000-0000-000000000000")
      {:error, :not_found}

  ## Notes

  * Organization identifiers use the canonical UUID string format.
  """
  @spec get(Organization.id()) ::
          {:ok, Organization.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Organization, id) do
      %Organization{} = organization ->
        {:ok, organization}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Disables an organization.

  ## Parameters

  * `id` - The identifier of the organization to disable

  ## Returns

  * `{:ok, organization}` when the organization is disabled
  * `{:ok, organization}` when the organization was already disabled
  * `{:error, :not_found}` when the organization does not exist
  * `{:error, changeset}` when the update cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Disable Test"})

      iex> {:ok, disabled} =
      ...>   Leafcutter.Organizations.disable(organization.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * The organization row is locked during the lifecycle transition to keep
    concurrent disable and environment creation operations consistent.
  """
  @spec disable(Organization.id()) ::
          {:ok, Organization.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def disable(id) do
    Repo.transaction(fn ->
      Organization
      |> where([organization], organization.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_disable()
    end)
  end

  defp persist_disable(nil) do
    Repo.rollback(:not_found)
  end

  defp persist_disable(%Organization{} = organization) do
    organization
    |> Organization.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, organization} ->
        organization

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end
end
