defmodule Leafcutter.Catalog.ContractVersion do
  @moduledoc """
  Represents one immutable published version of a Contract.

  The persistence model stores object and boolean JSON Schema roots. New
  publications require executable schema content, while `nil` remains
  loadable for identity-only legacy rows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.Contract
  alias Leafcutter.Catalog.Types.SchemaDocument

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "The identifier of one immutable ContractVersion identity."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when publishing an executable ContractVersion."
  @type publish_attrs :: %{
          required(:contract_id) => Contract.id(),
          required(:version) => String.t(),
          required(:schema) => SchemaDocument.t()
        }

  @typedoc "An immutable published ContractVersion with optional persisted schema content."
  @type t :: %__MODULE__{
          id: id() | nil,
          contract_id: Contract.id() | nil,
          contract: Contract.t() | Ecto.Association.NotLoaded.t(),
          version: String.t() | nil,
          schema: SchemaDocument.t() | nil,
          published_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "contract_versions" do
    belongs_to(:contract, Contract)

    field(:version, :string)
    field(:schema, SchemaDocument)
    field(:published_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for publishing an executable ContractVersion.

  ## Parameters

  * `contract_version` - The ContractVersion schema receiving publication attributes
  * `attrs` - The Contract identity, opaque version string, and schema document

  ## Returns

  * A valid changeset with an internally assigned publication timestamp
  * An invalid changeset when required attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.ContractVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.ContractVersion{},
      ...>     %{
      ...>       contract_id: Ecto.UUID.generate(),
      ...>       version: "2026.08",
      ...>       schema: true
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> is_struct(
      ...>   Ecto.Changeset.get_change(changeset, :published_at),
      ...>   DateTime
      ...> )
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.ContractVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.ContractVersion{},
      ...>     %{contract_id: Ecto.UUID.generate()}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The version is opaque, required, valid UTF-8, and may contain at most 255 characters.
  * Schema content is required and cast through `SchemaDocument`.
  * Version values are unique within one Contract.
  * Semantic Versioning is not interpreted.
  * `published_at` is assigned internally and cannot be supplied by callers.
  * Executable schema policy and JSV build checks are enforced by the public context
    boundary.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(contract_version, attrs) do
    contract_version
    |> cast(attrs, [:contract_id, :version, :schema])
    |> validate_required([:contract_id, :version, :schema])
    |> validate_utf8(:version)
    |> validate_length(:version, max: 255)
    |> put_change(:published_at, DateTime.utc_now(:microsecond))
    |> foreign_key_constraint(:contract_id)
    |> unique_constraint(
      [:contract_id, :version],
      name: :contract_versions_contract_id_version_index
    )
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
