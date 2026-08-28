defmodule Leafcutter.Catalog.Package do
  @moduledoc """
  Represents the stable Catalog identity of a reusable integration package.

  Executable topology is published separately through immutable
  PackageVersion identities and their relational endpoint projections.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.PackageVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "The stable identifier of a Package identity."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a Package identity."
  @type create_attrs ::
          %{required(:name) => String.t()}
          | %{required(String.t()) => String.t()}

  @typedoc "A global Package identity with separately published versions."
  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t() | nil,
          versions: [PackageVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "packages" do
    field(:name, :string)

    has_many(:versions, PackageVersion)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a Package identity.

  ## Parameters

  * `package` - The Package schema receiving creation attributes
  * `attrs` - The external attributes containing the Package name

  ## Returns

  * A valid changeset when the required name satisfies the constraints
  * An invalid changeset when the name is missing or invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.Package.create_changeset(
      ...>     %Leafcutter.Catalog.Package{},
      ...>     %{name: "CRM synchronization"}
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.Package.create_changeset(
      ...>     %Leafcutter.Catalog.Package{},
      ...>     %{}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The name is required, must be valid UTF-8, and may contain at most 255 characters.
  * Package identities are global and do not belong to an Organization.
  * Versions and endpoints are excluded from this changeset.
  * Package manifests, build metadata, and executable code are outside this slice.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(package, attrs) do
    package
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_utf8(:name)
    |> validate_length(:name, max: 255)
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
