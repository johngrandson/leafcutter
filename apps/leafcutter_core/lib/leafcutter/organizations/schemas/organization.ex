defmodule Leafcutter.Organizations.Organization do
  @moduledoc """
  Represents an organization within Leafcutter.

  Organizations are the primary tenancy boundary and own operational
  environments, memberships, and authorization scope.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: Ecto.UUID.t()

  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type create_attrs ::
          %{required(:name) => String.t()}
          | %{required(String.t()) => String.t()}

  schema "organizations" do
    field(:name, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Creates a changeset for creating a new organization.

  ## Parameters

  * organization - The organization struct
  * attrs - The external attributes to validate and cast

  ## Returns

  * A changeset containing the validated creation attributes

  ## Examples

      iex> alias Leafcutter.Organizations.Organization
      Leafcutter.Organizations.Organization
      iex> Organization.create_changeset(%Organization{}, %{name: "Test Organization"})
      ...> |> Map.fetch!(:valid?)
      true

      iex> alias Leafcutter.Organizations.Organization
      Leafcutter.Organizations.Organization
      iex> Organization.create_changeset(%Organization{}, %{})
      ...> |> Map.fetch!(:valid?)
      false

      iex> alias Leafcutter.Organizations.Organization
      Leafcutter.Organizations.Organization
      iex> Organization.create_changeset(%Organization{}, %{name: ""})
      ...> |> Map.fetch!(:valid?)
      false

  ## Notes

  * The name is required and may contain at most 255 characters.
  * `disabled_at` is excluded from the cast so callers cannot set lifecycle state manually.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  @doc """
  Builds a changeset for disabling an organization.

  ## Parameters

  * organization - The organization struct

  ## Returns

  * A changeset that records the lifecycle transition when needed

  ## Examples

      iex> alias Leafcutter.Organizations.Organization
      Leafcutter.Organizations.Organization
      iex> %Organization{}
      ...> |> Organization.disable_changeset()
      ...> |> Ecto.Changeset.get_change(:disabled_at)
      ...> |> is_struct(DateTime)
      true

      iex> alias Leafcutter.Organizations.Organization
      Leafcutter.Organizations.Organization
      iex> %Organization{disabled_at: ~U[2025-01-01 00:00:00.000000Z]}
      ...> |> Organization.disable_changeset()
      ...> |> then(fn changeset ->
      ...>   {Ecto.Changeset.changed?(changeset, :disabled_at), changeset.data.disabled_at}
      ...> end)
      {false, ~U[2025-01-01 00:00:00.000000Z]}

  ## Notes

  * Active organizations receive the current UTC timestamp with microsecond precision.
  * Already disabled organizations retain their original timestamp, making this operation
    idempotent.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = organization) do
    change(organization, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = organization) do
    change(organization)
  end
end
