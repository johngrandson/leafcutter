defmodule Leafcutter.Catalog.PackageVersion do
  @moduledoc """
  Represents one immutable published topology for a Package version.

  The topology is projected relationally through PackageVersionEndpoint rows.
  Its manifest digest binds that authority to compiled package code without
  persisting module names in the Catalog.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.{Package, PackageVersionEndpoint}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @manifest_sha256_bytes 64

  @typedoc "The identifier of one immutable PackageVersion topology."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes used to create the internal unpublished version row."
  @type publish_attrs :: %{
          required(:package_id) => Package.id(),
          required(:version) => String.t(),
          required(:manifest_sha256) => String.t()
        }

  @typedoc "An immutable published PackageVersion and its endpoint projection."
  @type t :: %__MODULE__{
          id: id() | nil,
          package_id: Package.id() | nil,
          package: Package.t() | Ecto.Association.NotLoaded.t(),
          version: String.t() | nil,
          manifest_sha256: String.t() | nil,
          published_at: DateTime.t() | nil,
          endpoints: [PackageVersionEndpoint.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "package_versions" do
    belongs_to(:package, Package)

    field(:version, :string)
    field(:manifest_sha256, :string)
    field(:published_at, :utc_datetime_usec)

    has_many(:endpoints, PackageVersionEndpoint)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for the internal PackageVersion publication row.

  ## Parameters

  * `package_version` - The PackageVersion schema receiving publication attributes
  * `attrs` - The Package identity, opaque version, and exact manifest digest

  ## Returns

  * A valid changeset containing the Package identity, version, and manifest digest
  * An invalid changeset when required attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.PackageVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.PackageVersion{},
      ...>     %{
      ...>       package_id: Ecto.UUID.generate(),
      ...>       manifest_sha256:
      ...>         "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      ...>       version: "2026.08"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.PackageVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.PackageVersion{},
      ...>     %{package_id: Ecto.UUID.generate()}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The version is opaque, required, valid UTF-8, and may contain at most 255 characters.
  * Version values are unique within one Package.
  * The manifest digest is required for new rows, lowercase hexadecimal, and globally unique.
  * The physical column remains nullable so historical rows stay readable.
  * Semantic Versioning is not interpreted.
  * `published_at` is deliberately excluded from the cast.
  * The capability API sets `published_at` only after every endpoint is persisted.
  * A deferred database constraint prevents incomplete publication from committing.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(package_version, attrs) do
    package_version
    |> cast(attrs, [:package_id, :version, :manifest_sha256])
    |> validate_required([:package_id, :version, :manifest_sha256])
    |> validate_utf8(:version)
    |> validate_length(:version, max: 255)
    |> validate_manifest_sha256()
    |> foreign_key_constraint(:package_id)
    |> check_constraint(
      :manifest_sha256,
      name: :package_versions_manifest_sha256_format
    )
    |> unique_constraint(
      [:package_id, :version],
      name: :package_versions_package_id_version_index
    )
    |> unique_constraint(
      :manifest_sha256,
      name: :package_versions_manifest_sha256_index
    )
  end

  @spec validate_manifest_sha256(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_manifest_sha256(changeset) do
    validate_change(changeset, :manifest_sha256, fn field, value ->
      if valid_manifest_sha256?(value) do
        []
      else
        [
          {field,
           {"must be exactly 64 lowercase hexadecimal characters",
            validation: :format}}
        ]
      end
    end)
  end

  @spec valid_manifest_sha256?(term()) :: boolean()
  defp valid_manifest_sha256?(value)
       when is_binary(value) and byte_size(value) == @manifest_sha256_bytes do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end

  defp valid_manifest_sha256?(_value), do: false

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
