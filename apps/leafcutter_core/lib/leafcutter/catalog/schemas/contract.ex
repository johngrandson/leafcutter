defmodule Leafcutter.Catalog.Contract do
  @moduledoc """
  Represents the stable Catalog identity of a data contract.

  Versioned contract identities are published separately through
  ContractVersion. Executable schemas are outside the initial Catalog slice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Catalog.ContractVersion

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
          versions: [ContractVersion.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "contracts" do
    field(:name, :string)

    has_many(:versions, ContractVersion)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a Contract identity.

  ## Parameters

  * `contract` - The Contract schema receiving creation attributes
  * `attrs` - The external attributes containing the Contract name

  ## Returns

  * A valid changeset when the required name satisfies the constraints
  * An invalid changeset when the name is missing or invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Catalog.Contract.create_changeset(
      ...>     %Leafcutter.Catalog.Contract{},
      ...>     %{name: "Customer"}
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Catalog.Contract.create_changeset(
      ...>     %Leafcutter.Catalog.Contract{},
      ...>     %{}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The name is required, must be valid UTF-8, and may contain at most 255 characters.
  * Contract identities are global and do not belong to an Organization.
  * Versions and executable schemas are excluded from this changeset.
  * JSON Schema and JSV validation are outside the initial Catalog slice.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(contract, attrs) do
    contract
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
