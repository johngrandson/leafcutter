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

  @typedoc "Error returned while locking active Connections for a caller-owned workflow."
  @type lock_active_error ::
          :transaction_required
          | {:connection_not_found, Connection.id()}
          | {:connection_scope_mismatch, Connection.id()}
          | {:connection_disabled, Connection.id()}

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
  Locks and validates active Connections in deterministic identifier order.

  ## Parameters

  * `ids` - The Connection identifiers required by the caller-owned workflow
  * `organization_id` - The Organization every Connection must belong to
  * `environment_id` - The Environment every Connection must belong to

  ## Returns

  * `{:ok, connections}` with unique Connections ordered by identifier
  * `{:error, :transaction_required}` when no caller-owned transaction is active
  * `{:error, {:connection_not_found, id}}` when a requested Connection is absent
  * `{:error, {:connection_scope_mismatch, id}}` when a Connection has another scope
  * `{:error, {:connection_disabled, id}}` when a Connection is disabled

  ## Examples

      iex> Leafcutter.Connections.lock_active(
      ...>   [],
      ...>   "00000000-0000-0000-0000-000000000000",
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :transaction_required}

  ## Notes

  * The caller must already own a Repo transaction.
  * The caller is responsible for locking Organization and Environment first.
  * Duplicate identifiers are locked once and do not duplicate the result.
  * Shared row locks block Connection update and disable until commit.
  * Ordering by identifier prevents workflows from acquiring the same set in different orders.
  """
  @spec lock_active(
          [Connection.id()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) ::
          {:ok, [Connection.t()]} | {:error, lock_active_error()}
  def lock_active(ids, organization_id, environment_id) when is_list(ids) do
    if Repo.in_transaction?() do
      ids
      |> Enum.uniq()
      |> Enum.sort()
      |> lock_and_validate_connections(organization_id, environment_id)
    else
      {:error, :transaction_required}
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

  @spec lock_and_validate_connections(
          [Connection.id()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) :: {:ok, [Connection.t()]} | {:error, lock_active_error()}
  defp lock_and_validate_connections(ids, organization_id, environment_id) do
    connections =
      Connection
      |> where([connection], connection.id in ^ids)
      |> order_by([connection], asc: connection.id)
      |> lock("FOR SHARE")
      |> Repo.all()

    with :ok <- validate_connections_present(ids, connections),
         :ok <-
           validate_connections_active_scope(
             connections,
             organization_id,
             environment_id
           ) do
      {:ok, connections}
    end
  end

  @spec validate_connections_present(
          [Connection.id()],
          [Connection.t()]
        ) :: :ok | {:error, {:connection_not_found, Connection.id()}}
  defp validate_connections_present(ids, connections) do
    persisted_ids = MapSet.new(connections, & &1.id)

    case Enum.find(ids, &(not MapSet.member?(persisted_ids, &1))) do
      nil -> :ok
      id -> {:error, {:connection_not_found, id}}
    end
  end

  @spec validate_connections_active_scope(
          [Connection.t()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) ::
          :ok
          | {:error, {:connection_scope_mismatch, Connection.id()}}
          | {:error, {:connection_disabled, Connection.id()}}
  defp validate_connections_active_scope(
         connections,
         organization_id,
         environment_id
       ) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      cond do
        connection.organization_id != organization_id or
            connection.environment_id != environment_id ->
          {:halt, {:error, {:connection_scope_mismatch, connection.id}}}

        connection.disabled_at != nil ->
          {:halt, {:error, {:connection_disabled, connection.id}}}

        true ->
          {:cont, :ok}
      end
    end)
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
