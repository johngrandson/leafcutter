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

  @typedoc "The identifier of one immutable Operation."
  @type id :: Ecto.UUID.t()

  @typedoc "The endpoint role supported by an Operation."
  @type role :: :source | :destination

  @typedoc "Attributes accepted when publishing an Operation with its ConnectorVersion."
  @type publish_attrs :: %{
          required(:connector_version_id) => ConnectorVersion.id(),
          required(:ref) => String.t(),
          required(:role) => role() | String.t()
        }

  @typedoc "An immutable Operation published as part of one ConnectorVersion."
  @type t :: %__MODULE__{
          id: id() | nil,
          connector_version_id: ConnectorVersion.id() | nil,
          connector_version: ConnectorVersion.t() | Ecto.Association.NotLoaded.t(),
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

  * The reference is required, valid UTF-8, local to one ConnectorVersion, and at most 255 characters.
  * References are unique inside one ConnectorVersion.
  * The role is persisted as either `source` or `destination`.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(operation, attrs) do
    operation
    |> cast(attrs, [:connector_version_id, :ref, :role])
    |> validate_required([:connector_version_id, :ref, :role])
    |> validate_utf8(:ref)
    |> validate_length(:ref, max: 255)
    |> foreign_key_constraint(:connector_version_id)
    |> unique_constraint(
      [:connector_version_id, :ref],
      name: :operations_connector_version_id_ref_index
    )
    |> check_constraint(:role, name: :operations_role_valid)
  end

  @spec validate_utf8(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_utf8(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.valid?(value) do
        []
      else
        [{field, {"must be valid UTF-8", validation: :utf8}}]
      end
    end)
  end
end
