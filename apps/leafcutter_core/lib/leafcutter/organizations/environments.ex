defmodule Leafcutter.Organizations.Environments do
  @moduledoc """
  Public capability module for managing organization environments.
  """

  import Ecto.Query

  alias Leafcutter.Organizations.Environment
  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Repo

  @doc """
  Creates an environment within an active organization.

  ## Parameters

  * `attrs` - The attributes used to create the environment, including the
    organization identifier and environment name

  ## Returns

  * `{:ok, environment}` when the environment is persisted
  * `{:error, :organization_not_found}` when the referenced organization does not exist
  * `{:error, :organization_disabled}` when the referenced organization is disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Environment Example Organization"
      ...>   })

      iex> match?(
      ...>   {:ok, %{name: "production"}},
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })
      ...> )
      true

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: ""
      ...>   })
      ...> )
      true

  ## Notes

  * The referenced organization must exist and be active.
  * The environment name is required and may contain at most 255 characters.
  * Environment names must be unique within their organization.
  * Different organizations may use the same environment name.
  * `disabled_at` is not accepted during creation and defaults to `nil`.
  * The organization row is locked while its lifecycle state is checked and the
    environment is persisted, preventing concurrent disable operations from
    violating the active-organization invariant.
  """
  @spec create(Environment.create_attrs()) ::
          {:ok, Environment.t()}
          | {:error, :organization_not_found}
          | {:error, :organization_disabled}
          | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    changeset = Environment.create_changeset(%Environment{}, attrs)

    if changeset.valid? do
      create_with_active_organization(changeset)
    else
      {:error, changeset}
    end
  end

  # Expects a valid environment creation changeset with an organization_id.
  # The organization row is locked for the duration of the transaction so its
  # lifecycle state cannot change between validation and persistence.
  @spec create_with_active_organization(Ecto.Changeset.t()) ::
          {:ok, Environment.t()}
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
      |> persist_environment(changeset)
    end)
  end

  defp persist_environment(nil, _changeset) do
    Repo.rollback(:organization_not_found)
  end

  defp persist_environment(%Organization{disabled_at: nil}, changeset) do
    case Repo.insert(changeset) do
      {:ok, environment} ->
        environment

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp persist_environment(%Organization{}, _changeset) do
    Repo.rollback(:organization_disabled)
  end

  @doc """
  Fetches an environment by its identifier.

  ## Parameters

  * `id` - The identifier of the environment to fetch

  ## Returns

  * `{:ok, environment}` when the environment exists
  * `{:error, :not_found}` when no environment exists with the given identifier

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Environment Lookup Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Organizations.Environments.get(environment.id)

      iex> fetched.id == environment.id
      true

  ## Notes

  * Disabled environments are returned normally.
  * Lifecycle state does not affect lookup semantics.
  """
  @spec get(Environment.id()) ::
          {:ok, Environment.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Environment, id) do
      %Environment{} = environment ->
        {:ok, environment}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Disables an environment.

  ## Parameters

  * `id` - The identifier of the environment to disable

  ## Returns

  * `{:ok, environment}` when the environment is disabled
  * `{:ok, environment}` when the environment was already disabled
  * `{:error, :not_found}` when the environment does not exist
  * `{:error, changeset}` when the lifecycle change cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Environment Disable Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, disabled} =
      ...>   Leafcutter.Organizations.Environments.disable(environment.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * The environment row is locked while the lifecycle transition is evaluated
    and persisted, keeping concurrent disable operations consistent.
  * An environment may be disabled even when its organization is already disabled.
  """
  @spec disable(Environment.id()) ::
          {:ok, Environment.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def disable(id) do
    Repo.transaction(fn ->
      Environment
      |> where([environment], environment.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> persist_disable()
    end)
  end

  defp persist_disable(nil) do
    Repo.rollback(:not_found)
  end

  defp persist_disable(%Environment{} = environment) do
    environment
    |> Environment.disable_changeset()
    |> Repo.update()
    |> case do
      {:ok, environment} ->
        environment

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @typedoc "An active Organization and Environment pair locked for a caller-owned transaction."
  @type active_scope :: %{
          organization: Organization.t(),
          environment: Environment.t()
        }

  @typedoc "Authority or lifecycle error returned while validating an active scope."
  @type active_scope_state_error ::
          :organization_not_found
          | :organization_disabled
          | :environment_not_found
          | :environment_scope_mismatch
          | :environment_disabled

  @typedoc "Error returned while locking an active Organization and Environment scope."
  @type active_scope_error ::
          :transaction_required
          | active_scope_state_error()

  @doc """
  Locks and validates an active Organization and Environment scope.

  ## Parameters

  * `organization_id` - The expected Organization identifier
  * `environment_id` - The Environment identifier expected to belong to the Organization

  ## Returns

  * `{:ok, scope}` with the active Organization and Environment rows
  * `{:error, :transaction_required}` when no caller-owned transaction is active
  * `{:error, :organization_not_found}` when the Organization does not exist
  * `{:error, :organization_disabled}` when the Organization is disabled
  * `{:error, :environment_not_found}` when the Environment does not exist
  * `{:error, :environment_scope_mismatch}` when the Environment belongs to another Organization
  * `{:error, :environment_disabled}` when the Environment is disabled

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Active Scope Example"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, {:ok, scope}} =
      ...>   Leafcutter.Repo.transaction(fn ->
      ...>     Leafcutter.Organizations.Environments.lock_active_scope(
      ...>       organization.id,
      ...>       environment.id
      ...>     )
      ...>   end)

      iex> {scope.organization.id, scope.environment.id}
      {organization.id, environment.id}

      iex> Leafcutter.Organizations.Environments.lock_active_scope(
      ...>   "00000000-0000-0000-0000-000000000000",
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :transaction_required}

  ## Notes

  * The caller must already own a Repo transaction.
  * The Organization is locked before the Environment.
  * Shared row locks allow concurrent readers and block lifecycle updates until commit.
  * The locks are intended for cross-context workflows that must prevent concurrent disable.
  """
  @spec lock_active_scope(Organization.id(), Environment.id()) ::
          {:ok, active_scope()} | {:error, active_scope_error()}
  def lock_active_scope(organization_id, environment_id) do
    if Repo.in_transaction?() do
      with {:ok, organization} <- lock_active_organization(organization_id),
           {:ok, environment} <-
             lock_active_environment(environment_id, organization_id) do
        {:ok, %{organization: organization, environment: environment}}
      end
    else
      {:error, :transaction_required}
    end
  end

  @spec lock_active_organization(Organization.id()) ::
          {:ok, Organization.t()}
          | {:error, :organization_not_found | :organization_disabled}
  defp lock_active_organization(organization_id) do
    organization =
      Organization
      |> where([organization], organization.id == ^organization_id)
      |> lock("FOR SHARE")
      |> Repo.one()

    case organization do
      nil ->
        {:error, :organization_not_found}

      %Organization{disabled_at: nil} = organization ->
        {:ok, organization}

      %Organization{} ->
        {:error, :organization_disabled}
    end
  end

  @spec lock_active_environment(Environment.id(), Organization.id()) ::
          {:ok, Environment.t()}
          | {:error,
             :environment_not_found
             | :environment_scope_mismatch
             | :environment_disabled}
  defp lock_active_environment(environment_id, organization_id) do
    environment =
      Environment
      |> where([environment], environment.id == ^environment_id)
      |> lock("FOR SHARE")
      |> Repo.one()

    case environment do
      nil ->
        {:error, :environment_not_found}

      %Environment{organization_id: persisted_organization_id}
      when persisted_organization_id != organization_id ->
        {:error, :environment_scope_mismatch}

      %Environment{disabled_at: nil} = environment ->
        {:ok, environment}

      %Environment{} ->
        {:error, :environment_disabled}
    end
  end
end
