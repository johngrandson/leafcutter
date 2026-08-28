defmodule Leafcutter.Catalog.PackageVersionEndpoint do
  @moduledoc """
  Represents one immutable endpoint in a PackageVersion topology.

  The endpoint pins one Operation and one ContractVersion. Its role must match
  the Operation role, while destination position preserves declared order.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.{
    ContractVersion,
    Operation,
    PackageVersion
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "The identifier of one immutable PackageVersion endpoint."
  @type id :: Ecto.UUID.t()

  @typedoc "The source or destination role of an endpoint."
  @type role :: :source | :destination

  @typedoc "Attributes used internally while publishing an endpoint."
  @type publish_attrs :: %{
          required(:package_version_id) => PackageVersion.id(),
          required(:ref) => String.t(),
          required(:role) => role() | String.t(),
          required(:position) => integer() | nil,
          required(:operation_id) => Operation.id(),
          required(:contract_version_id) => ContractVersion.id()
        }

  @typedoc "An immutable endpoint pinned to an Operation and ContractVersion."
  @type t :: %__MODULE__{
          id: id() | nil,
          package_version_id: PackageVersion.id() | nil,
          package_version: PackageVersion.t() | Ecto.Association.NotLoaded.t(),
          ref: String.t() | nil,
          role: role() | nil,
          position: integer() | nil,
          operation_id: Operation.id() | nil,
          operation: Operation.t() | Ecto.Association.NotLoaded.t(),
          contract_version_id: ContractVersion.id() | nil,
          contract_version: ContractVersion.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "package_version_endpoints" do
    belongs_to(:package_version, PackageVersion)

    field(:ref, :string)
    field(:role, Ecto.Enum, values: [:source, :destination])
    field(:position, :integer)

    belongs_to(:operation, Operation)
    belongs_to(:contract_version, ContractVersion)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for publishing a PackageVersion endpoint.

  ## Parameters

  * `endpoint` - The endpoint schema receiving publication attributes
  * `attrs` - The parent version, ref, role, position, Operation, and ContractVersion

  ## Returns

  * A valid changeset when the endpoint satisfies the relational projection
  * An invalid changeset when attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.PackageVersionEndpoint.publish_changeset(
      ...>     %Leafcutter.Catalog.PackageVersionEndpoint{},
      ...>     %{
      ...>       package_version_id: Ecto.UUID.generate(),
      ...>       ref: "crm",
      ...>       role: :destination,
      ...>       position: 0,
      ...>       operation_id: Ecto.UUID.generate(),
      ...>       contract_version_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.PackageVersionEndpoint.publish_changeset(
      ...>     %Leafcutter.Catalog.PackageVersionEndpoint{},
      ...>     %{
      ...>       package_version_id: Ecto.UUID.generate(),
      ...>       ref: "source",
      ...>       role: :source,
      ...>       position: 0,
      ...>       operation_id: Ecto.UUID.generate(),
      ...>       contract_version_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The ref is required, valid UTF-8, local to one PackageVersion, and at most 255 characters.
  * A source has no position; every destination has one internally assigned position.
  * Endpoint role must match the referenced Operation role.
  * The referenced ContractVersion must already exist.
  * Endpoint refs and destination positions are unique within one PackageVersion.
  * Published endpoints are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [
      :package_version_id,
      :ref,
      :role,
      :position,
      :operation_id,
      :contract_version_id
    ])
    |> validate_required([
      :package_version_id,
      :ref,
      :role,
      :operation_id,
      :contract_version_id
    ])
    |> validate_utf8(:ref)
    |> validate_length(:ref, max: 255)
    |> validate_role_position()
    |> foreign_key_constraint(:package_version_id)
    |> foreign_key_constraint(:operation_id,
      name: :package_version_endpoints_operation_role_fkey,
      message: "does not exist or does not match the endpoint role"
    )
    |> foreign_key_constraint(:contract_version_id)
    |> unique_constraint(
      [:package_version_id, :ref],
      name: :package_version_endpoints_package_version_id_ref_index,
      error_key: :ref
    )
    |> unique_constraint(:package_version_id,
      name: :package_version_endpoints_one_source_index,
      error_key: :role
    )
    |> unique_constraint(
      [:package_version_id, :position],
      name: :package_version_endpoints_destination_position_index,
      error_key: :position
    )
    |> check_constraint(:role,
      name: :package_version_endpoints_role_valid
    )
    |> check_constraint(:position,
      name: :package_version_endpoints_position_valid
    )
  end

  @spec validate_role_position(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_role_position(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :position)} do
      {:source, nil} ->
        changeset

      {:source, _position} ->
        add_error(changeset, :position, "must be empty for a source endpoint")

      {:destination, position} when is_integer(position) ->
        changeset

      {:destination, nil} ->
        add_error(changeset, :position, "is required for a destination endpoint")

      {_role, _position} ->
        changeset
    end
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
