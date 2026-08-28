defmodule Leafcutter.Catalog.PackageVersion do
  @moduledoc """
  Represents one immutable published topology for a Package version.

  The topology is projected relationally through PackageVersionEndpoint rows
  and remains independent from the still-draft Package Manifest contract.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.{Package, PackageVersionEndpoint}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "The identifier of one immutable PackageVersion topology."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes used to create the internal unpublished version row."
  @type publish_attrs :: %{
          required(:package_id) => Package.id(),
          required(:version) => String.t()
        }

  @typedoc "An immutable published PackageVersion and its endpoint projection."
  @type t :: %__MODULE__{
          id: id() | nil,
          package_id: Package.id() | nil,
          package: Package.t() | Ecto.Association.NotLoaded.t(),
          version: String.t() | nil,
          published_at: DateTime.t() | nil,
          endpoints:
            [PackageVersionEndpoint.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "package_versions" do
    belongs_to(:package, Package)

    field(:version, :string)
    field(:published_at, :utc_datetime_usec)

    has_many(:endpoints, PackageVersionEndpoint)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for the internal PackageVersion publication row.

  ## Parameters

  * `package_version` - The PackageVersion schema receiving publication attributes
  * `attrs` - The Package identity and opaque version string

  ## Returns

  * A valid changeset containing the Package identity and opaque version
  * An invalid changeset when required attributes or database constraints fail

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.PackageVersion.publish_changeset(
      ...>     %Leafcutter.Catalog.PackageVersion{},
      ...>     %{
      ...>       package_id: Ecto.UUID.generate(),
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
  * Semantic Versioning is not interpreted.
  * `published_at` is deliberately excluded from the cast.
  * The capability API sets `published_at` only after every endpoint is persisted.
  * A deferred database constraint prevents incomplete publication from committing.
  * Published rows are protected against update and delete by PostgreSQL.
  """
  @spec publish_changeset(t(), publish_attrs()) :: Ecto.Changeset.t()
  def publish_changeset(package_version, attrs) do
    package_version
    |> cast(attrs, [:package_id, :version])
    |> validate_required([:package_id, :version])
    |> validate_utf8(:version)
    |> validate_length(:version, max: 255)
    |> foreign_key_constraint(:package_id)
    |> unique_constraint(
      [:package_id, :version],
      name: :package_versions_package_id_version_index
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
