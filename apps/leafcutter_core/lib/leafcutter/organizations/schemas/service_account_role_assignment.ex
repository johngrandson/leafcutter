defmodule Leafcutter.Organizations.ServiceAccountRoleAssignment do
  @moduledoc """
  Represents a role assignment for a service account.

  Assignments may apply to the entire organization or to one specific
  environment. They represent current authorization state and do not have an
  independent domain identifier.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.{Environment, Role, ServiceAccount}

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [:service_account_id, :role_id]
  @optional_fields [:environment_id]

  @typedoc "Attributes accepted when creating a service account role assignment."
  @type create_attrs :: %{
          required(:service_account_id) => ServiceAccount.id(),
          required(:role_id) => Role.id(),
          optional(:environment_id) => Environment.id()
        }

  @typedoc "A role assignment for a service account within an organization or environment scope."
  @type t :: %__MODULE__{
          service_account_id: ServiceAccount.id() | nil,
          service_account: ServiceAccount.t() | Ecto.Association.NotLoaded.t(),
          role_id: Role.id() | nil,
          role: Role.t() | Ecto.Association.NotLoaded.t(),
          environment_id: Environment.id() | nil,
          environment: Environment.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "service_account_role_assignments" do
    belongs_to(:service_account, ServiceAccount)
    belongs_to(:role, Role)
    belongs_to(:environment, Environment)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a service account role assignment.

  ## Parameters

  * `role_assignment` - The service account role assignment schema receiving the creation attributes
  * `attrs` - The service account, role, and optional environment identifiers

  ## Returns

  * A valid changeset when the required identifiers are present
  * An invalid changeset when required attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.ServiceAccountRoleAssignment.create_changeset(
      ...>     %Leafcutter.Organizations.ServiceAccountRoleAssignment{},
      ...>     %{
      ...>       service_account_id: Ecto.UUID.generate(),
      ...>       role_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> Leafcutter.Organizations.ServiceAccountRoleAssignment.create_changeset(
      ...>   %Leafcutter.Organizations.ServiceAccountRoleAssignment{},
      ...>   %{service_account_id: Ecto.UUID.generate()}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * Omitting `environment_id` creates an organization-wide assignment.
  * Providing `environment_id` scopes the assignment to that environment.
  * A service account may receive the same role once organization-wide and once per environment.
  * Lifecycle and organization-boundary invariants are enforced by the public access capability.
  * Service account role assignments do not have independent domain identifiers.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(role_assignment, attrs) do
    role_assignment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:service_account_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:environment_id)
    |> unique_constraint(
      [:service_account_id, :role_id],
      name: :sa_role_assignments_account_role_org_scope_index
    )
    |> unique_constraint(
      [:service_account_id, :role_id, :environment_id],
      name: :sa_role_assignments_account_role_env_scope_index
    )
  end
end
