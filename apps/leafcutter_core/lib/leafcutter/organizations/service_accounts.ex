defmodule Leafcutter.Organizations.ServiceAccounts do
  @moduledoc """
  Public capability module for managing service accounts.

  Service accounts are non-human authorization subjects scoped directly to an
  organization. Concrete authentication credentials are managed separately.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.{Organization, ServiceAccount}
  alias Leafcutter.Repo

  @typedoc """
  Error returned when a service account cannot be created.

  The organization may be missing or disabled, or persistence may fail
  validation or a database constraint.
  """
  @type create_error ::
          :organization_not_found
          | :organization_disabled
          | Ecto.Changeset.t()

  @typedoc """
  Error returned when a service account cannot be disabled.

  The service account may not exist, or the lifecycle change may fail
  validation or a database constraint.
  """
  @type disable_error :: :not_found | Ecto.Changeset.t()

  @doc """
  Creates a service account within an active organization.

  ## Parameters

  * `attrs` - The organization identifier and name used to create the service account

  ## Returns

  * `{:ok, service_account}` when the service account is persisted
  * `{:error, :organization_not_found}` when the referenced organization does not exist
  * `{:error, :organization_disabled}` when the referenced organization is disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Service Account Organization"})

      iex> match?(
      ...>   {:ok, %{name: "production-sync"}},
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production-sync"
      ...>   })
      ...> )
      true

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{})
      ...> )
      true

  ## Notes

  * The referenced organization must exist and be active.
  * Service account names are unique within their organization.
  * Creating a service account does not create credentials or grant roles.
  * The organization row is locked while lifecycle state is checked and the
    service account is persisted.
  """
  @spec create(ServiceAccount.create_attrs()) ::
          {:ok, ServiceAccount.t()} | {:error, create_error()}
  def create(attrs) do
    changeset = ServiceAccount.create_changeset(%ServiceAccount{}, attrs)

    if changeset.valid? do
      create_with_active_organization(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid service account creation changeset containing organization_id.
  @spec create_with_active_organization(Ecto.Changeset.t()) ::
          {:ok, ServiceAccount.t()} | {:error, create_error()}
  defp create_with_active_organization(changeset) do
    organization_id = Ecto.Changeset.fetch_field!(changeset, :organization_id)

    Repo.transaction(fn ->
      Organization
      |> where([organization], organization.id == ^organization_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_creation(changeset)
    end)
  end

  @spec persist_creation(Organization.t() | nil, Ecto.Changeset.t()) :: ServiceAccount.t()
  defp persist_creation(nil, _changeset) do
    Repo.rollback(:organization_not_found)
  end

  defp persist_creation(%Organization{disabled_at: disabled_at}, _changeset)
       when not is_nil(disabled_at) do
    Repo.rollback(:organization_disabled)
  end

  defp persist_creation(%Organization{}, changeset) do
    case Repo.insert(changeset) do
      {:ok, service_account} ->
        service_account

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Fetches a service account by its identifier.

  ## Parameters

  * `id` - The identifier of the service account to fetch

  ## Returns

  * `{:ok, service_account}` when the service account exists
  * `{:error, :not_found}` when no service account exists with the given identifier

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Service Account Lookup"})

      iex> {:ok, service_account} =
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "lookup-agent"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Organizations.ServiceAccounts.get(service_account.id)

      iex> fetched.id == service_account.id
      true

  ## Notes

  * Disabled service accounts are returned normally.
  * Lifecycle state does not affect lookup semantics.
  """
  @spec get(ServiceAccount.id()) ::
          {:ok, ServiceAccount.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(ServiceAccount, id) do
      %ServiceAccount{} = service_account ->
        {:ok, service_account}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Disables a service account.

  ## Parameters

  * `id` - The identifier of the service account to disable

  ## Returns

  * `{:ok, service_account}` when the service account is disabled
  * `{:ok, service_account}` when the service account was already disabled
  * `{:error, :not_found}` when the service account does not exist
  * `{:error, changeset}` when the lifecycle change cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{name: "Service Account Disable"})

      iex> {:ok, service_account} =
      ...>   Leafcutter.Organizations.ServiceAccounts.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "disable-agent"
      ...>   })

      iex> {:ok, disabled} =
      ...>   Leafcutter.Organizations.ServiceAccounts.disable(service_account.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Disabling a service account does not delete historical authorization data.
  * The service account row is locked while the lifecycle transition is
    evaluated and persisted.
  """
  @spec disable(ServiceAccount.id()) ::
          {:ok, ServiceAccount.t()} | {:error, disable_error()}
  def disable(id) do
    Repo.transaction(fn ->
      ServiceAccount
      |> where([service_account], service_account.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_disable()
    end)
  end

  @spec persist_disable(ServiceAccount.t() | nil) :: ServiceAccount.t()
  defp persist_disable(nil) do
    Repo.rollback(:not_found)
  end

  defp persist_disable(%ServiceAccount{} = service_account) do
    service_account
    |> ServiceAccount.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, service_account} ->
        service_account

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end
end
