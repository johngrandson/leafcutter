defmodule Leafcutter.Connections.Secret do
  @moduledoc """
  Represents an environment-scoped identity for immutable SecretVersions.

  This slice stores only identity and scope. It does not store secret material,
  ciphertext, provider locators, or credentials.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Connections.SecretVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @fields [:organization_id, :environment_id, :name]

  @typedoc "The identifier of one environment-scoped Secret identity."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a Secret identity."
  @type create_attrs ::
          %{
            required(:organization_id) => Ecto.UUID.t(),
            required(:environment_id) => Ecto.UUID.t(),
            required(:name) => String.t()
          }
          | %{required(String.t()) => String.t()}

  @typedoc "An environment-scoped Secret identity."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Ecto.UUID.t() | nil,
          environment_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          versions: [SecretVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "secrets" do
    field(:organization_id, :binary_id)
    field(:environment_id, :binary_id)
    field(:name, :string)

    has_many(:versions, SecretVersion)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a Secret identity.

  ## Parameters

  * `secret` - The Secret schema receiving creation attributes
  * `attrs` - The external Organization, Environment, and name attributes

  ## Returns

  * A valid changeset when scope and name satisfy the structural contract
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Connections.Secret.create_changeset(
      ...>     %Leafcutter.Connections.Secret{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       environment_id: Ecto.UUID.generate(),
      ...>       name: "CRM credentials"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Connections.Secret.create_changeset(
      ...>     %Leafcutter.Connections.Secret{},
      ...>     %{name: "CRM credentials"}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * Organization, Environment, and name are required.
  * The name must be valid UTF-8 and may contain at most 255 characters.
  * Organization and Environment compatibility is protected by a composite foreign key.
  * Version children and all forms of secret material are excluded from the cast.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(secret, attrs) do
    secret
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_utf8(:name)
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:environment_id)
    |> foreign_key_constraint(:environment_id,
      name: :secrets_organization_environment_fkey
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
