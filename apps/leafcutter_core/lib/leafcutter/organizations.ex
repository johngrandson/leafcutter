defmodule Leafcutter.Organizations do
  @moduledoc """
  Public facade for the Organizations context.

  This module exposes operations related to the primary organization
  lifecycle while specialized capabilities live in dedicated modules.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  @typedoc "Authority or lifecycle error returned while validating an active Organization."
  @type active_organization_state_error ::
          :organization_not_found | :organization_disabled

  @typedoc "Error returned while locking an active Organization."
  @type active_organization_error ::
          :transaction_required | active_organization_state_error()

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

  @doc """
  Locks and validates an active Organization.

  ## Parameters

  * `id` - The Organization identifier to lock and validate

  ## Returns

  * `{:ok, organization}` when the Organization exists and is active
  * `{:error, :transaction_required}` when no caller-owned transaction is active
  * `{:error, :organization_not_found}` when the Organization does not exist
  * `{:error, :organization_disabled}` when the Organization is disabled

  ## Examples

      iex> Leafcutter.Organizations.lock_active(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :transaction_required}

  ## Notes

  * The caller must already own a Repo transaction.
  * A shared row lock blocks lifecycle updates until the caller commits.
  * The lock is intended for cross-context workflows that require Organization authority.
  """
  @spec lock_active(Organization.id()) ::
          {:ok, Organization.t()} | {:error, active_organization_error()}
  def lock_active(id) do
    if Repo.in_transaction?() do
      Organization
      |> where([organization], organization.id == ^id)
      |> lock("FOR SHARE")
      |> Repo.one()
      |> classify_active()
    else
      {:error, :transaction_required}
    end
  end

  @spec persist_disable(Organization.t() | nil) ::
          Organization.t() | no_return()
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

  @spec classify_active(Organization.t() | nil) ::
          {:ok, Organization.t()}
          | {:error, active_organization_state_error()}
  defp classify_active(nil), do: {:error, :organization_not_found}

  defp classify_active(%Organization{disabled_at: nil} = organization),
    do: {:ok, organization}

  defp classify_active(%Organization{}), do: {:error, :organization_disabled}
end
