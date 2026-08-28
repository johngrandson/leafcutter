defmodule Leafcutter.Connections.SecretVersion do
  @moduledoc """
  Represents one immutable version identity belonging to a Secret.

  A SecretVersion carries only an opaque version label. Concrete secret
  material and provider-specific references remain outside this slice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Connections.Secret

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @fields [:secret_id, :version]

  @typedoc "The identifier of one immutable SecretVersion identity."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a SecretVersion identity."
  @type create_attrs ::
          %{
            required(:secret_id) => Secret.id(),
            required(:version) => String.t()
          }
          | %{required(String.t()) => String.t()}

  @typedoc "An immutable version identity belonging to one Secret."
  @type t :: %__MODULE__{
          id: id() | nil,
          secret_id: Secret.id() | nil,
          secret: Secret.t() | Ecto.Association.NotLoaded.t(),
          version: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "secret_versions" do
    belongs_to(:secret, Secret)
    field(:version, :string)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for creating an immutable SecretVersion identity.

  ## Parameters

  * `secret_version` - The SecretVersion schema receiving publication attributes
  * `attrs` - The parent Secret identifier and opaque version string

  ## Returns

  * A valid changeset when the parent and version satisfy the structural contract
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Connections.SecretVersion.create_changeset(
      ...>     %Leafcutter.Connections.SecretVersion{},
      ...>     %{secret_id: Ecto.UUID.generate(), version: "rotation-1"}
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Connections.SecretVersion.create_changeset(
      ...>     %Leafcutter.Connections.SecretVersion{},
      ...>     %{version: ""}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The parent Secret and version are required.
  * The opaque version is unique within its Secret, valid UTF-8, and at most 255 characters.
  * Raw secret, ciphertext, provider locator, credential, and lifecycle fields are excluded.
  * PostgreSQL rejects update and delete operations after insertion.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(secret_version, attrs) do
    secret_version
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_utf8(:version)
    |> validate_length(:version, max: 255)
    |> foreign_key_constraint(:secret_id)
    |> unique_constraint(:secret_id,
      name: :secret_versions_secret_id_version_index
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
