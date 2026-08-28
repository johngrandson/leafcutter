defmodule Leafcutter.Integrations.Integration do
  @moduledoc """
  Represents an Organization-scoped integration identity.

  An Integration selects one stable Catalog Package identity. Environment-
  specific executable state is owned separately by EnvironmentDeployment.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @create_fields [:organization_id, :package_id, :name]

  @typedoc "The identifier of one Organization-scoped Integration."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating an Integration identity."
  @type create_attrs ::
          %{
            required(:organization_id) => Ecto.UUID.t(),
            required(:package_id) => Ecto.UUID.t(),
            required(:name) => String.t()
          }
          | %{required(String.t()) => String.t()}

  @typedoc "An Organization-scoped Integration bound to one stable Package."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Ecto.UUID.t() | nil,
          package_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "integrations" do
    field(:organization_id, :binary_id)
    field(:package_id, :binary_id)
    field(:name, :string)
    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating an Integration identity.

  ## Parameters

  * `integration` - The Integration schema receiving creation attributes
  * `attrs` - The Organization, stable Package, and Integration name

  ## Returns

  * A valid changeset when every required identity attribute is present
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Integrations.Integration.create_changeset(
      ...>     %Leafcutter.Integrations.Integration{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       package_id: Ecto.UUID.generate(),
      ...>       name: "CRM synchronization"
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Integrations.Integration.create_changeset(
      ...>     %Leafcutter.Integrations.Integration{},
      ...>     %{name: ""}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * Organization, stable Package, and name are required.
  * The name must be valid UTF-8 and may contain at most 255 characters.
  * Package, Organization, lifecycle state, and identity cannot be changed after creation.
  * EnvironmentDeployment state is deliberately excluded from this changeset.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(integration, attrs) do
    integration
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields)
    |> validate_utf8(:name)
    |> validate_length(:name, max: 255)
    |> apply_constraints()
  end

  @doc """
  Builds a changeset for disabling an Integration.

  ## Parameters

  * `integration` - The Integration whose lifecycle state will change

  ## Returns

  * A changeset with a new disable timestamp when the Integration is active
  * An unchanged changeset when the Integration is already disabled

  ## Examples

      iex> integration = %Leafcutter.Integrations.Integration{}
      iex> changeset =
      ...>   Leafcutter.Integrations.Integration.disable_changeset(integration)

      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * Disable is idempotent and preserves an existing timestamp.
  * Callers cannot set `disabled_at` through the creation changeset.
  * Persistence and row locking are handled by the Integrations context.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = integration) do
    change(integration, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = integration) do
    change(integration)
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

  @spec apply_constraints(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp apply_constraints(changeset) do
    changeset
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:package_id)
  end
end
