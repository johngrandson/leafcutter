defmodule Leafcutter.Connections do
  @moduledoc """
  Public facade for environment-scoped Connection lifecycle.

  Connections point to stable Catalog Connector identities, store only
  non-sensitive JSON configuration, and may select one exact SecretVersion.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Leafcutter.Catalog.Connectors

  alias Leafcutter.Connections.{
    Connection,
    Secret,
    SecretVersion
  }

  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo

  @typedoc "Authority or lifecycle error returned while validating a Connection scope."
  @type scope_error :: Environments.active_scope_state_error()

  @typedoc "Error returned when an exact SecretVersion binding is absent or incompatible."
  @type binding_error ::
          :secret_version_not_found | :secret_version_scope_mismatch

  @typedoc "Error returned while creating a Connection."
  @type create_error ::
          scope_error()
          | binding_error()
          | :connector_not_found
          | Changeset.t()

  @typedoc "Error returned while updating mutable Connection state."
  @type update_error ::
          :not_found | scope_error() | binding_error() | Changeset.t()

  @typedoc "Error returned while disabling a Connection."
  @type disable_error :: :not_found | scope_error() | Changeset.t()

  @doc """
  Creates an environment-scoped Connection.

  ## Parameters

  * `attrs` - The scope, stable Connector, name, config, and optional exact SecretVersion binding

  ## Returns

  * `{:ok, connection}` when the Connection is persisted
  * `{:error, reason}` when a referenced authority is absent, incompatible, or disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Connection Create Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, connector} =
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "Connection Create Connector"
      ...>   })

      iex> {:ok, connection} =
      ...>   Leafcutter.Connections.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     connector_id: connector.id,
      ...>     name: "CRM",
      ...>     config: %{"base_url" => "https://example.test"}
      ...>   })

      iex> connection.config
      %{"base_url" => "https://example.test"}

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Connections.create(%{})
      ...> )
      true

  ## Notes

  * The Organization and Environment must exist, correspond, and be active.
  * The Connector reference targets a stable Connector identity, never a ConnectorVersion.
  * Config defaults to an empty JSON object and must remain non-sensitive.
  * SecretVersion selection is optional, exact, and scope-compatible.
  * Scope locks prevent concurrent parent disable from crossing the write.
  """
  @spec create(Connection.create_attrs()) ::
          {:ok, Connection.t()} | {:error, create_error()}
  def create(attrs) do
    changeset = Connection.create_changeset(%Connection{}, attrs)

    if changeset.valid? do
      create_with_locked_authorities(changeset)
    else
      {:error, changeset}
    end
  end

  @doc """
  Fetches a Connection by its identifier.

  ## Parameters

  * `id` - The Connection identifier to fetch

  ## Returns

  * `{:ok, connection}` when the Connection exists
  * `{:error, :not_found}` when no Connection has the identifier

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Connection Lookup Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, connector} =
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "Connection Lookup Connector"
      ...>   })

      iex> {:ok, connection} =
      ...>   Leafcutter.Connections.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     connector_id: connector.id,
      ...>     name: "CRM"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Connections.get(connection.id)

      iex> fetched.id == connection.id
      true

      iex> Leafcutter.Connections.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Disabled Connections are returned normally.
  * SecretVersion is not preloaded.
  * Lookup does not validate parent lifecycle state.
  """
  @spec get(Connection.id()) ::
          {:ok, Connection.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Connection, id) do
      %Connection{} = connection -> {:ok, connection}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Replaces mutable Connection state for future resolutions.

  ## Parameters

  * `id` - The Connection identifier to update
  * `attrs` - A replacement config, an exact SecretVersion binding, or both

  ## Returns

  * `{:ok, connection}` when the mutable state is persisted
  * `{:error, :not_found}` when the Connection does not exist
  * `{:error, reason}` when its scope is absent, incompatible, or disabled
  * `{:error, reason}` when the selected SecretVersion is absent or scope-incompatible
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Connection Update Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, connector} =
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "Connection Update Connector"
      ...>   })

      iex> {:ok, connection} =
      ...>   Leafcutter.Connections.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     connector_id: connector.id,
      ...>     name: "CRM"
      ...>   })

      iex> {:ok, updated} =
      ...>   Leafcutter.Connections.update(
      ...>     connection.id,
      ...>     %{config: %{"timeout" => 30}}
      ...>   )

      iex> updated.config
      %{"timeout" => 30}

      iex> Leafcutter.Connections.update(
      ...>   "00000000-0000-0000-0000-000000000000",
      ...>   %{config: %{}}
      ...> )
      {:error, :not_found}

  ## Notes

  * Only config and `secret_version_id` are mutable.
  * Organization, Environment, Connector, name, and lifecycle state are ignored.
  * Changes affect future resolutions only; existing snapshots remain frozen.
  * Parent scope is locked before the Connection row to preserve lock ordering.
  """
  @spec update(Connection.id(), Connection.update_attrs()) ::
          {:ok, Connection.t()} | {:error, update_error()}
  def update(id, attrs) do
    Repo.transaction(fn ->
      with {:ok, unlocked_connection} <- fetch_connection(id),
           {:ok, _scope} <- lock_connection_scope(unlocked_connection),
           {:ok, connection} <- lock_connection(id),
           {:ok, changeset} <- validate_update(connection, attrs),
           :ok <- validate_secret_version_binding(changeset) do
        update_or_rollback(changeset)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Disables a Connection idempotently.

  ## Parameters

  * `id` - The Connection identifier to disable

  ## Returns

  * `{:ok, connection}` when the Connection is disabled
  * `{:ok, connection}` when it was already disabled
  * `{:error, :not_found}` when the Connection does not exist
  * `{:error, reason}` when its parent scope is absent, incompatible, or disabled
  * `{:error, changeset}` when the lifecycle transition cannot be persisted

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Connection Disable Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, connector} =
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "Connection Disable Connector"
      ...>   })

      iex> {:ok, connection} =
      ...>   Leafcutter.Connections.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     connector_id: connector.id,
      ...>     name: "CRM"
      ...>   })

      iex> {:ok, disabled} =
      ...>   Leafcutter.Connections.disable(connection.id)

      iex> is_struct(disabled.disabled_at, DateTime)
      true

      iex> Leafcutter.Connections.disable(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * The first successful call records one disable timestamp.
  * Repeated calls preserve the original timestamp.
  * A disabled Connection cannot participate in future deployment resolution.
  * Parent scope is locked before the Connection row to preserve lock ordering.
  """
  @spec disable(Connection.id()) ::
          {:ok, Connection.t()} | {:error, disable_error()}
  def disable(id) do
    Repo.transaction(fn ->
      with {:ok, unlocked_connection} <- fetch_connection(id),
           {:ok, _scope} <- lock_connection_scope(unlocked_connection),
           {:ok, connection} <- lock_connection(id) do
        connection
        |> Connection.disable_changeset()
        |> update_or_rollback()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec create_with_locked_authorities(Changeset.t()) ::
          {:ok, Connection.t()} | {:error, create_error()}
  defp create_with_locked_authorities(changeset) do
    organization_id = Changeset.fetch_field!(changeset, :organization_id)
    environment_id = Changeset.fetch_field!(changeset, :environment_id)
    connector_id = Changeset.fetch_field!(changeset, :connector_id)

    Repo.transaction(fn ->
      with {:ok, _scope} <-
             Environments.lock_active_scope(
               organization_id,
               environment_id
             ),
           :ok <- validate_connector(connector_id),
           :ok <- validate_secret_version_binding(changeset) do
        insert_or_rollback(changeset)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec validate_connector(Ecto.UUID.t()) ::
          :ok | {:error, :connector_not_found}
  defp validate_connector(connector_id) do
    case Connectors.get(connector_id) do
      {:ok, _connector} -> :ok
      {:error, :not_found} -> {:error, :connector_not_found}
    end
  end

  @spec fetch_connection(Connection.id()) ::
          {:ok, Connection.t()} | {:error, :not_found}
  defp fetch_connection(id) do
    case Repo.get(Connection, id) do
      %Connection{} = connection -> {:ok, connection}
      nil -> {:error, :not_found}
    end
  end

  @spec lock_connection(Connection.id()) ::
          {:ok, Connection.t()} | {:error, :not_found}
  defp lock_connection(id) do
    connection =
      Connection
      |> where([connection], connection.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case connection do
      %Connection{} = connection -> {:ok, connection}
      nil -> {:error, :not_found}
    end
  end

  @spec lock_connection_scope(Connection.t()) ::
          {:ok, Environments.active_scope()}
          | {:error, scope_error()}
  defp lock_connection_scope(connection) do
    Environments.lock_active_scope(
      connection.organization_id,
      connection.environment_id
    )
  end

  @spec validate_update(Connection.t(), Connection.update_attrs()) ::
          {:ok, Changeset.t()} | {:error, Changeset.t()}
  defp validate_update(connection, attrs) do
    changeset = Connection.update_changeset(connection, attrs)

    if changeset.valid? do
      {:ok, changeset}
    else
      {:error, changeset}
    end
  end

  @spec validate_secret_version_binding(Changeset.t()) ::
          :ok | {:error, binding_error()}
  defp validate_secret_version_binding(changeset) do
    secret_version_id = Changeset.get_field(changeset, :secret_version_id)

    case secret_version_id do
      nil ->
        :ok

      secret_version_id ->
        validate_persisted_secret_version_scope(
          secret_version_id,
          Changeset.fetch_field!(changeset, :organization_id),
          Changeset.fetch_field!(changeset, :environment_id)
        )
    end
  end

  @spec validate_persisted_secret_version_scope(
          SecretVersion.id(),
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) :: :ok | {:error, binding_error()}
  defp validate_persisted_secret_version_scope(
         secret_version_id,
         organization_id,
         environment_id
       ) do
    scope =
      from(secret_version in SecretVersion,
        join: secret in Secret,
        on: secret.id == secret_version.secret_id,
        where: secret_version.id == ^secret_version_id,
        select: {secret.organization_id, secret.environment_id}
      )
      |> Repo.one()

    case scope do
      nil ->
        {:error, :secret_version_not_found}

      {^organization_id, ^environment_id} ->
        :ok

      {_organization_id, _environment_id} ->
        {:error, :secret_version_scope_mismatch}
    end
  end

  @spec insert_or_rollback(Changeset.t()) :: Connection.t() | no_return()
  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, connection} -> connection
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec update_or_rollback(Changeset.t()) :: Connection.t() | no_return()
  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, connection} -> connection
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
