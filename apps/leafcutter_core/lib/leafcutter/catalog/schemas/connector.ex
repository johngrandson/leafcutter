defmodule Leafcutter.Catalog.Connector do
  @moduledoc """
  Represents the stable Catalog identity of an external-system connector.

  Connector implementations and versioned operation metadata are published
  separately through ConnectorVersion.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.ConnectorVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: Ecto.UUID.t()

  @type create_attrs ::
          %{required(:name) => String.t()}
          | %{required(String.t()) => String.t()}

  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t() | nil,
          versions: [ConnectorVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "connectors" do
    field(:name, :string)

    has_many(:versions, ConnectorVersion)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a Connector identity.

  ## Parameters

  * `connector` - The Connector schema receiving creation attributes
  * `attrs` - The external attributes containing the Connector name

  ## Returns

  * A valid changeset when the required name satisfies the constraints
  * An invalid changeset when the name is missing or invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.Connector.create_changeset(
      ...>     %Leafcutter.Catalog.Connector{},
      ...>     %{name: "Salesforce"}
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.Connector.create_changeset(
      ...>     %Leafcutter.Catalog.Connector{},
      ...>     %{}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The name is required, must be valid UTF-8, and may contain at most 255 characters.
  * Connector identities are global and do not belong to an Organization.
  * Versions and Operations are excluded from this changeset.
  * Lifecycle and availability metadata are outside the initial Catalog slice.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(connector, attrs) do
    connector
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
