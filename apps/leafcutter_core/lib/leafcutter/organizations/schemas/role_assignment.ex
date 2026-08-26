defmodule Leafcutter.Organizations.RoleAssignment do
  @moduledoc """
  Represents a role assignment for an organization membership.

  Assignments may apply to the entire organization or to one specific
  environment. They represent current authorization state and do not have an
  independent domain identifier.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.{Environment, Membership, Role}

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [:membership_id, :role_id]
  @optional_fields [:environment_id]

  @typedoc "Attributes accepted when creating a role assignment."
  @type create_attrs :: %{
          required(:membership_id) => Membership.id(),
          required(:role_id) => Role.id(),
          optional(:environment_id) => Environment.id()
        }

  @typedoc "A role assignment for an organization-wide or environment scope."
  @type t :: %__MODULE__{
          membership_id: Membership.id() | nil,
          membership: Membership.t() | Ecto.Association.NotLoaded.t(),
          role_id: Role.id() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t(),
          environment_id: Environment.id() | nil,
          environment: Environment.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "role_assignments" do
    belongs_to(:membership, Membership)
    belongs_to(:role, Role)
    belongs_to(:environment, Environment)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a role assignment.

  ## Parameters

  * `role_assignment` - The role assignment schema receiving the creation attributes
  * `attrs` - The membership, role, and optional environment identifiers

  ## Returns

  * A valid changeset when the required identifiers are present
  * An invalid changeset when required attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.RoleAssignment.create_changeset(
      ...>     %Leafcutter.Organizations.RoleAssignment{},
      ...>     %{
      ...>       membership_id: Ecto.UUID.generate(),
      ...>       role_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> Leafcutter.Organizations.RoleAssignment.create_changeset(
      ...>   %Leafcutter.Organizations.RoleAssignment{},
      ...>   %{}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * Omitting `environment_id` creates an organization-wide assignment.
  * Providing `environment_id` scopes the assignment to that environment.
  * A membership may receive the same role once organization-wide and once per environment.
  * Lifecycle and organization-boundary invariants are enforced by the public access capability.
  * Role assignments do not have independent domain identifiers.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(role_assignment, attrs) do
    role_assignment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:environment_id)
    |> unique_constraint(
      [:membership_id, :role_id],
      name: :role_assignments_membership_role_organization_scope_index
    )
    |> unique_constraint(
      [:membership_id, :role_id, :environment_id],
      name: :role_assignments_membership_role_environment_scope_index
    )
  end
end
