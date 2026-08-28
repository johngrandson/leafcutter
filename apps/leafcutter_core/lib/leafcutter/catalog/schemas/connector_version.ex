defmodule Leafcutter.Catalog.ConnectorVersion do
  @moduledoc """
  Represents immutable published metadata for one Connector version.

  Operations are published atomically with the version through the Catalog
  capability API.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.{Connector, Operation}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: Ecto.UUID.t()

  @type publish_attrs :: %{
          required(:connector_id) => Connector.id(),
          required(:version) => String.t()
        }

  @type t :: %__MODULE__{
          id: id() | nil,
          connector_id: Connector.id() | nil,
          connector: Connector.t() | Ecto.Association.NotLoaded.t(),
          version: String.t() | nil,
          published_at: DateTime.t() | nil,
          operations: [Operation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "connector_versions" do
    belongs_to(:connector, Connector)

    field(:version, :string)
    field(:published_at, :utc_datetime_usec)

    has_many(:operations, Operation)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for publishing a ConnectorVersion.

  ## Parameters

  * `connector_version` - The ConnectorVersion schema receiving publication attributes
  * `attrs` - The Connector identity and opaque version string

  ## Returns

  * A valid changeset with an internally assigned publication timestamp
  * An invalid changeset when required attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.ConnectorVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.ConnectorVersion{},
      ...>     %{
      ...>       connector_id: Ecto.UUID.generate(),
      ...>       version: "2026.08"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> is_struct(
      ...>   Ecto.Changeset.get_change(changeset, :published_at),
      ...>   DateTime
      ...> )
      true

  ## Notes

  * The version is opaque, required, and may contain at most 255 characters.
  * Version values are unique within one Connector.
  * Semantic Versioning is not interpreted.
  * `published_at` is selected internally and cannot be supplied by callers.
  * Operations are persisted separately in the same transaction.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(connector_version, attrs) do
    connector_version
    |> cast(attrs, [:connector_id, :version])
    |> validate_required([:connector_id, :version])
    |> validate_length(:version, max: 255)
    |> put_change(:published_at, DateTime.utc_now(:microsecond))
    |> foreign_key_constraint(:connector_id)
    |> unique_constraint(
      [:connector_id, :version],
      name: :connector_versions_connector_id_version_index
    )
  end
end
