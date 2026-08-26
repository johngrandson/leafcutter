defmodule Leafcutter.Organizations.Environment do
  @moduledoc """
  Represents an operational environment within an organization.

  Environment names are organization-scoped and are intentionally not
  restricted to predefined values such as development or production.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]
  @required_fields [:organization_id, :name]

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

  schema "environments" do
    belongs_to(:organization, Organization)

    field(:name, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating an environment.

  ## Parameters

  * environment - The environment struct
  * attrs - The external attributes to validate and cast

  ## Returns

  * A changeset containing the validated creation attributes

  ## Examples

      iex> alias Leafcutter.Organizations.Environment
      Leafcutter.Organizations.Environment
      iex> Environment.create_changeset(
      ...>   %Environment{},
      ...>   %{organization_id: "550e8400-e29b-41d4-a716-446655440000", name: "Production"}
      ...> )
      ...> |> Map.fetch!(:valid?)
      true

      iex> alias Leafcutter.Organizations.Environment
      Leafcutter.Organizations.Environment
      iex> Environment.create_changeset(
      ...>   %Environment{},
      ...>   %{organization_id: "550e8400-e29b-41d4-a716-446655440000"}
      ...> )
      ...> |> Map.fetch!(:valid?)
      false

      iex> alias Leafcutter.Organizations.Environment
      Leafcutter.Organizations.Environment
      iex> Environment.create_changeset(%Environment{}, %{name: "Production"})
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * The organization and name are required.
  * The name may contain at most 255 characters and must be unique within the organization.
  * The organization reference is protected by a database foreign key constraint.
  * `disabled_at` is excluded from the cast so callers cannot set lifecycle state manually.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(environment, attrs) do
    environment
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:name,
      name: :environments_organization_id_name_index
    )
  end

  @doc """
  Builds a changeset for disabling an environment.

  ## Parameters

  * `environment` - The environment whose lifecycle state will be changed

  ## Returns

  * A changeset containing a new `disabled_at` timestamp when the environment is active
  * An unchanged changeset when the environment is already disabled

  ## Examples

      iex> environment = %Leafcutter.Organizations.Environment{}
      iex> changeset = Leafcutter.Organizations.Environment.disable_changeset(environment)
      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * The operation is idempotent.
  * An existing `disabled_at` timestamp is preserved.
  * Persistence and concurrency control are handled by the Organizations context,
    not by this changeset.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = environment) do
    change(environment, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = environment) do
    change(environment)
  end
end
