defmodule Leafcutter.Organizations.RolePermission do
  @moduledoc """
  Represents a permission granted to an organization-scoped role.

  Permissions are identified by stable strings defined by the application
  rather than by independently persisted Permission entities.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.Role

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type create_attrs :: %{
          required(:role_id) => Role.id(),
          required(:permission) => String.t()
        }

  @type t :: %__MODULE__{
          role_id: Role.id() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t(),
          permission: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "role_permissions" do
    belongs_to(:role, Role)

    field(:permission, :string)

    timestamps()
  end

  @doc """
  Builds a changeset for associating a permission with a role.

  ## Parameters

  * `role_permission` - The role permission schema receiving the creation attributes
  * `attrs` - The role identifier and permission identifier to associate

  ## Returns

  * A valid changeset when the required attributes are present
  * An invalid changeset when attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.RolePermission.create_changeset(
      ...>     %Leafcutter.Organizations.RolePermission{},
      ...>     %{
      ...>       role_id: Ecto.UUID.generate(),
      ...>       permission: "integration.read"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

  ## Notes

  * A role may contain a permission at most once.
  * Permission identifiers may contain at most 255 characters.
  * Whether a permission identifier is known by Leafcutter is validated by the
    public authorization capability rather than by this persistence changeset.
  * Role permissions do not have independent domain identifiers.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(role_permission, attrs) do
    role_permission
    |> cast(attrs, [:role_id, :permission])
    |> validate_required([:role_id, :permission])
    |> validate_length(:permission, max: 255)
    |> foreign_key_constraint(:role_id)
    |> unique_constraint(
      [:role_id, :permission],
      name: :role_permissions_role_id_permission_index
    )
  end
end
