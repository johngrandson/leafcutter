defmodule Leafcutter.Catalog.Operation do
  @moduledoc """
  Represents one immutable operation exposed by a ConnectorVersion.

  The role identifies whether the operation can serve a package source or
  destination endpoint.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.ConnectorVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: Ecto.UUID.t()
  @type role :: :source | :destination

  @type publish_attrs :: %{
          required(:connector_version_id) => ConnectorVersion.id(),
          required(:ref) => String.t(),
          required(:role) => role() | String.t()
        }

  @type t :: %__MODULE__{
          id: id() | nil,
          connector_version_id: ConnectorVersion.id() | nil,
          connector_version:
            ConnectorVersion.t() | Ecto.Association.NotLoaded.t(),
          ref: String.t() | nil,
          role: role() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "operations" do
    belongs_to(:connector_version, ConnectorVersion)

    field(:ref, :string)
    field(:role, Ecto.Enum, values: [:source, :destination])

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for publishing an Operation with a ConnectorVersion.

  ## Parameters

  * `operation` - The Operation schema receiving publication attributes
  * `attrs` - The ConnectorVersion, local reference, and source/destination role

  ## Returns

  * A valid changeset when all operation attributes satisfy the contract
  * An invalid changeset when attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.Operation.publish_changeset(
      ...>     %Leafcutter.Catalog.Operation{},
      ...>     %{
      ...>       connector_version_id: Ecto.UUID.generate(),
      ...>       ref: "list_accounts",
      ...>       role: :source
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.Operation.publish_changeset(
      ...>     %Leafcutter.Catalog.Operation{},
      ...>     %{
      ...>       connector_version_id: Ecto.UUID.generate(),
      ...>       ref: "list_accounts",
      ...>       role: :invalid
      ...>     }
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The reference is required, local to one ConnectorVersion, and at most 255 characters.
  * References are unique inside one ConnectorVersion.
  * The role is persisted as either `source` or `destination`.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(operation, attrs) do
    operation
    |> cast(attrs, [:connector_version_id, :ref, :role])
    |> validate_required([:connector_version_id, :ref, :role])
    |> validate_length(:ref, max: 255)
    |> foreign_key_constraint(:connector_version_id)
    |> unique_constraint(
      [:connector_version_id, :ref],
      name: :operations_connector_version_id_ref_index
    )
    |> check_constraint(:role, name: :operations_role_valid)
  end
end
