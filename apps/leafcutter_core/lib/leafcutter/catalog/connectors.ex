defmodule Leafcutter.Catalog.Connectors do
  @moduledoc """
  Public capability module for Connector identities and immutable versions.

  ConnectorVersion and Operation rows are published atomically. Published
  version content has no update or delete lifecycle.
  """

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Connector,
    ConnectorVersion,
    Operation
  }

  alias Leafcutter.Repo

  @type operation_attrs ::
          %{
            required(:ref) => String.t(),
            required(:role) => Operation.role()
          }
          | %{
              required(String.t()) => String.t()
            }

  @type publish_version_attrs ::
          %{
            required(:version) => String.t(),
            optional(:operations) => [operation_attrs()]
          }
          | %{
              required(String.t()) =>
                String.t() | [operation_attrs()]
            }

  @type publish_error :: :connector_not_found | Changeset.t()

  @doc """
  Creates a stable Connector identity.

  ## Parameters

  * `attrs` - The external attributes containing the Connector name

  ## Returns

  * `{:ok, connector}` when the identity is persisted
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:ok, %{name: "Salesforce"}},
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "Salesforce"
      ...>   })
      ...> )
      true

  ## Notes

  * Connector identities are global and not scoped to an Organization.
  * Creating an identity does not publish a ConnectorVersion.
  * Version and availability lifecycles are handled separately.
  """
  @spec create(Connector.create_attrs()) ::
          {:ok, Connector.t()} | {:error, Changeset.t()}
  def create(attrs) do
    %Connector{}
    |> Connector.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches a Connector identity by its identifier.

  ## Parameters

  * `id` - The Connector identifier to fetch

  ## Returns

  * `{:ok, connector}` when the Connector exists
  * `{:error, :not_found}` when no Connector has the identifier

  ## Examples

      iex> Leafcutter.Catalog.Connectors.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Versions and Operations are not preloaded.
  * Lookup has no availability filtering in the initial Catalog slice.
  """
  @spec get(Connector.id()) ::
          {:ok, Connector.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Connector, id) do
      %Connector{} = connector ->
        {:ok, connector}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Publishes an immutable ConnectorVersion and its Operations atomically.

  ## Parameters

  * `connector_id` - The stable Connector identity receiving the version
  * `attrs` - The opaque version string and optional Operation definitions

  ## Returns

  * `{:ok, connector_version}` with its Connector and Operations loaded
  * `{:error, :connector_not_found}` when the parent Connector does not exist
  * `{:error, changeset}` when the version or an Operation is invalid

  ## Examples

      iex> {:ok, connector} =
      ...>   Leafcutter.Catalog.Connectors.create(%{
      ...>     name: "CRM"
      ...>   })

      iex> {:ok, version} =
      ...>   Leafcutter.Catalog.Connectors.publish_version(
      ...>     connector.id,
      ...>     %{
      ...>       version: "2026.08",
      ...>       operations: [
      ...>         %{ref: "list_accounts", role: :source},
      ...>         %{ref: "create_contact", role: :destination}
      ...>       ]
      ...>     }
      ...>   )

      iex> Enum.map(version.operations, & &1.ref)
      ["list_accounts", "create_contact"]

  ## Notes

  * The version string is opaque and unique within one Connector.
  * Operations may be empty because endpoint cardinality belongs to PackageVersion.
  * Operation refs are unique within the published ConnectorVersion.
  * Publication uses one database transaction and rolls back every row on failure.
  * Published version and Operation rows cannot be updated or deleted.
  """
  @spec publish_version(
          Connector.id(),
          publish_version_attrs()
        ) ::
          {:ok, ConnectorVersion.t()}
          | {:error, publish_error()}
  def publish_version(connector_id, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      connector =
        case Repo.get(Connector, connector_id) do
          %Connector{} = connector ->
            connector

          nil ->
            Repo.rollback(:connector_not_found)
        end

      version_changeset =
        ConnectorVersion.publish_changeset(
          %ConnectorVersion{},
          %{
            connector_id: connector.id,
            version: attribute(attrs, :version)
          }
        )

      operation_attrs =
        case attribute(attrs, :operations, []) do
          operations when is_list(operations) ->
            operations

          _other ->
            Repo.rollback(
              Changeset.add_error(
                version_changeset,
                :operations,
                "must be a list",
                validation: :list
              )
            )
        end

      if Enum.any?(operation_attrs, &(not is_map(&1))) do
        Repo.rollback(
          Changeset.add_error(
            version_changeset,
            :operations,
            "must contain only maps",
            validation: :map
          )
        )
      end

      connector_version = insert_or_rollback(version_changeset)

      operations =
        Enum.map(operation_attrs, fn attrs ->
          %Operation{}
          |> Operation.publish_changeset(%{
            connector_version_id: connector_version.id,
            ref: attribute(attrs, :ref),
            role: attribute(attrs, :role)
          })
          |> insert_or_rollback()
        end)

      %{
        connector_version
        | connector: connector,
          operations: operations
      }
    end)
  end

  @spec insert_or_rollback(Changeset.t()) ::
          ConnectorVersion.t() | Operation.t() | no_return()
  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec attribute(map(), atom(), term()) :: term()
  defp attribute(attrs, key, default \\ nil) do
    case Map.fetch(attrs, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(attrs, Atom.to_string(key), default)
    end
  end
end
