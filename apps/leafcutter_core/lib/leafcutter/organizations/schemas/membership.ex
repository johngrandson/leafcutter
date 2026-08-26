defmodule Leafcutter.Organizations.Membership do
  @moduledoc """
  Represents a user's membership within an organization.

  Memberships establish participation in an organization but do not
  directly grant permissions. Authorization is modeled separately
  through roles and access assignments.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.{Organization, User}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @typedoc "The membership identifier."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a membership."
  @type create_attrs :: %{
          required(:organization_id) => Organization.id(),
          required(:user_id) => User.id()
        }

  @typedoc "A membership between a user and an organization."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Organization.id() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t(),
          user_id: User.id() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t(),
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "memberships" do
    belongs_to(:organization, Organization)
    belongs_to(:user, User)

    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a membership.

  ## Parameters

  * `membership` - The membership schema receiving the creation attributes
  * `attrs` - The organization and user identifiers used to create the membership

  ## Returns

  * A valid changeset when the required identifiers are present
  * An invalid changeset when required attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.Membership.create_changeset(
      ...>     %Leafcutter.Organizations.Membership{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       user_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> Leafcutter.Organizations.Membership.create_changeset(
      ...>   %Leafcutter.Organizations.Membership{},
      ...>   %{organization_id: Ecto.UUID.generate()}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * A user may have at most one membership within the same organization.
  * Organization and user lifecycle rules are enforced by the public access workflow.
  * `disabled_at` is not accepted during creation and defaults to `nil`.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:organization_id, :user_id])
    |> validate_required([:organization_id, :user_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(
      [:organization_id, :user_id],
      name: :memberships_organization_id_user_id_index
    )
  end

  @doc """
  Builds a changeset for disabling a membership.

  ## Parameters

  * `membership` - The membership whose lifecycle state will be changed

  ## Returns

  * A changeset containing a new `disabled_at` timestamp when the membership is active
  * An unchanged changeset when the membership is already disabled

  ## Examples

      iex> membership = %Leafcutter.Organizations.Membership{}
      iex> changeset =
      ...>   Leafcutter.Organizations.Membership.disable_changeset(membership)

      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Disabling a membership removes active participation without deleting
    its durable history.
  * Persistence and concurrency control are handled by the Organizations
    access capability.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = membership) do
    change(membership, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = membership) do
    change(membership)
  end
end
