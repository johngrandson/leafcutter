defmodule Leafcutter.Organizations.ServiceAccount do
  @moduledoc """
  Represents a non-human actor scoped to one organization.

  Service accounts participate in authorization independently from users and
  memberships. Concrete authentication mechanisms such as API keys or tokens
  are intentionally outside this schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [:organization_id, :name]

  @typedoc "The service account identifier."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a service account."
  @type create_attrs :: %{
          required(:organization_id) => Organization.id(),
          required(:name) => String.t()
        }

  @typedoc "A non-human authorization subject scoped to an organization."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Organization.id() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t(),
          name: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "service_accounts" do
    belongs_to(:organization, Organization)

    field(:name, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a service account.

  ## Parameters

  * `service_account` - The service account schema receiving the creation attributes
  * `attrs` - The organization identifier and name used to create the service account

  ## Returns

  * A valid changeset when the required attributes satisfy the service account constraints
  * An invalid changeset when attributes or database constraints are invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Organizations.ServiceAccount.create_changeset(
      ...>     %Leafcutter.Organizations.ServiceAccount{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       name: "production-sync"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> Leafcutter.Organizations.ServiceAccount.create_changeset(
      ...>   %Leafcutter.Organizations.ServiceAccount{},
      ...>   %{organization_id: Ecto.UUID.generate()}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * A service account belongs to exactly one organization.
  * Names are unique within the organization and may contain at most 255 characters.
  * Authentication credentials are deliberately excluded from this schema.
  * `disabled_at` is excluded from the cast so callers cannot set lifecycle state manually.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(service_account, attrs) do
    service_account
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(
      [:organization_id, :name],
      name: :service_accounts_organization_id_name_index
    )
  end

  @doc """
  Builds a changeset for disabling a service account.

  ## Parameters

  * `service_account` - The service account whose lifecycle state will be changed

  ## Returns

  * A changeset containing a new `disabled_at` timestamp when the service account is active
  * An unchanged changeset when the service account is already disabled

  ## Examples

      iex> service_account = %Leafcutter.Organizations.ServiceAccount{}
      iex> changeset =
      ...>   Leafcutter.Organizations.ServiceAccount.disable_changeset(service_account)

      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Persistence and concurrency control are handled by the ServiceAccounts capability.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = service_account) do
    change(service_account, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = service_account) do
    change(service_account)
  end
end
