defmodule Leafcutter.Organizations.Role do
  @moduledoc """
  Represents an organization-scoped authorization role.

  Roles group permissions that may later be assigned to authorization
  subjects within an organization or environment scope.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: Ecto.UUID.t()

  @type create_attrs :: %{
          required(:organization_id) => Organization.id(),
          required(:name) => String.t()
        }

  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Organization.id() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t(),
          name: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "roles" do
    belongs_to(:organization, Organization)

    field(:name, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a role.

  ## Parameters

  * `role` - The role schema receiving the creation attributes
  * `attrs` - The organization identifier and name used to create the role

  ## Returns

  * A valid changeset when the required attributes satisfy the role constraints
  * An invalid changeset when attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.Role.create_changeset(
      ...>     %Leafcutter.Organizations.Role{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       name: "operator"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

  ## Notes

  * A role belongs to exactly one organization.
  * Role names are unique within their organization.
  * Role names may contain at most 255 characters.
  * Permissions are persisted separately from the role itself.
  * `disabled_at` is not accepted during creation and defaults to `nil`.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(role, attrs) do
    role
    |> cast(attrs, [:organization_id, :name])
    |> validate_required([:organization_id, :name])
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(
      [:organization_id, :name],
      name: :roles_organization_id_name_index
    )
  end

  @doc """
  Builds a changeset for disabling a role.

  ## Parameters

  * `role` - The role whose lifecycle state will be changed

  ## Returns

  * A changeset containing a new `disabled_at` timestamp when the role is active
  * An unchanged changeset when the role is already disabled

  ## Examples

      iex> role = %Leafcutter.Organizations.Role{}
      iex> changeset = Leafcutter.Organizations.Role.disable_changeset(role)
      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Disabling a role does not remove its persisted permissions or historical assignments.
  * Persistence and concurrency control are handled by the Roles capability.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = role) do
    change(role, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = role) do
    change(role)
  end
end
