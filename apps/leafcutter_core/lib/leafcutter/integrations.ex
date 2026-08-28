defmodule Leafcutter.Integrations do
  @moduledoc """
  Public facade for Organization-scoped Integration lifecycle.

  Integrations bind one Organization to a stable Catalog Package identity.
  Environment-specific executable state belongs to the Deployments capability.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Leafcutter.Catalog.Packages
  alias Leafcutter.Integrations.Integration
  alias Leafcutter.Organizations
  alias Leafcutter.Repo

  @typedoc "Authority or lifecycle error returned while validating an Integration Organization."
  @type organization_error :: Organizations.active_organization_state_error()

  @typedoc "Error returned while creating an Integration."
  @type create_error :: organization_error() | :package_not_found | Changeset.t()

  @typedoc "Error returned while disabling an Integration."
  @type disable_error :: :not_found | organization_error() | Changeset.t()

  @doc """
  Creates an Organization-scoped Integration.

  ## Parameters

  * `attrs` - The Organization, stable Package identity, and Integration name

  ## Returns

  * `{:ok, integration}` when the Integration is persisted
  * `{:error, reason}` when the Organization is absent or disabled
  * `{:error, :package_not_found}` when the stable Package does not exist
  * `{:error, changeset}` when attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Integrations.create(%{})
      ...> )
      true

  ## Notes

  * The Organization must exist and remain active throughout persistence.
  * The Package reference targets a stable Package identity, never a PackageVersion.
  * Package and Organization become immutable parts of the Integration identity.
  * EnvironmentDeployment state is created separately through the Deployments capability.
  """
  @spec create(Integration.create_attrs()) ::
          {:ok, Integration.t()} | {:error, create_error()}
  def create(attrs) do
    changeset = Integration.create_changeset(%Integration{}, attrs)

    if changeset.valid? do
      create_with_locked_authorities(changeset)
    else
      {:error, changeset}
    end
  end

  @doc """
  Fetches an Integration by its identifier.

  ## Parameters

  * `id` - The Integration identifier to fetch

  ## Returns

  * `{:ok, integration}` when the Integration exists
  * `{:error, :not_found}` when no Integration has the identifier

  ## Examples

      iex> Leafcutter.Integrations.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Disabled Integrations are returned normally.
  * EnvironmentDeployments are not preloaded.
  * Lookup does not validate parent lifecycle state.
  """
  @spec get(Integration.id()) ::
          {:ok, Integration.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Integration, id) do
      %Integration{} = integration -> {:ok, integration}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Disables an Integration idempotently.

  ## Parameters

  * `id` - The Integration identifier to disable

  ## Returns

  * `{:ok, integration}` when the Integration is disabled
  * `{:ok, integration}` when it was already disabled
  * `{:error, :not_found}` when the Integration does not exist
  * `{:error, reason}` when its Organization is absent or disabled
  * `{:error, changeset}` when the lifecycle transition cannot be persisted

  ## Examples

      iex> Leafcutter.Integrations.disable(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * The first successful call records one disable timestamp.
  * Repeated calls preserve the original timestamp.
  * A disabled Integration cannot receive or resolve EnvironmentDeployments.
  * The Organization is locked before the Integration to preserve lock ordering.
  """
  @spec disable(Integration.id()) ::
          {:ok, Integration.t()} | {:error, disable_error()}
  def disable(id) do
    Repo.transaction(fn ->
      with {:ok, unlocked_integration} <- fetch_integration(id),
           {:ok, _organization} <-
             Organizations.lock_active(unlocked_integration.organization_id),
           {:ok, integration} <- lock_integration(id) do
        integration
        |> Integration.disable_changeset()
        |> update_or_rollback()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec create_with_locked_authorities(Changeset.t()) ::
          {:ok, Integration.t()} | {:error, create_error()}
  defp create_with_locked_authorities(changeset) do
    organization_id = Changeset.fetch_field!(changeset, :organization_id)
    package_id = Changeset.fetch_field!(changeset, :package_id)

    Repo.transaction(fn ->
      with {:ok, _organization} <- Organizations.lock_active(organization_id),
           :ok <- validate_package(package_id) do
        insert_or_rollback(changeset)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec validate_package(Ecto.UUID.t()) ::
          :ok | {:error, :package_not_found}
  defp validate_package(package_id) do
    case Packages.get(package_id) do
      {:ok, _package} -> :ok
      {:error, :not_found} -> {:error, :package_not_found}
    end
  end

  @spec fetch_integration(Integration.id()) ::
          {:ok, Integration.t()} | {:error, :not_found}
  defp fetch_integration(id) do
    case Repo.get(Integration, id) do
      %Integration{} = integration -> {:ok, integration}
      nil -> {:error, :not_found}
    end
  end

  @spec lock_integration(Integration.id()) ::
          {:ok, Integration.t()} | {:error, :not_found}
  defp lock_integration(id) do
    integration =
      Integration
      |> where([integration], integration.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case integration do
      %Integration{} = integration -> {:ok, integration}
      nil -> {:error, :not_found}
    end
  end

  @spec insert_or_rollback(Changeset.t()) :: Integration.t() | no_return()
  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, integration} -> integration
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec update_or_rollback(Changeset.t()) :: Integration.t() | no_return()
  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, integration} -> integration
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
