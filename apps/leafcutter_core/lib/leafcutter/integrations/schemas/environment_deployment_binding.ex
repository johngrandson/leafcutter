defmodule Leafcutter.Integrations.EnvironmentDeploymentBinding do
  @moduledoc """
  Represents one endpoint-to-Connection binding in an EnvironmentDeployment.

  The binding stores only the PackageVersion endpoint ref and one environment-
  scoped Connection. Endpoint role and executable metadata remain in Catalog.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Integrations.EnvironmentDeployment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @create_fields [:environment_deployment_id, :ref, :connection_id]

  @typedoc "The identifier of one EnvironmentDeployment endpoint binding."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when persisting one endpoint binding."
  @type create_attrs :: %{
          required(:environment_deployment_id) => EnvironmentDeployment.id(),
          required(:ref) => String.t(),
          required(:connection_id) => Ecto.UUID.t()
        }

  @typedoc "One persisted endpoint ref bound to an environment-scoped Connection."
  @type t :: %__MODULE__{
          id: id() | nil,
          environment_deployment_id: EnvironmentDeployment.id() | nil,
          environment_deployment:
            EnvironmentDeployment.t() | Ecto.Association.NotLoaded.t(),
          ref: String.t() | nil,
          connection_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "environment_deployment_bindings" do
    belongs_to(:environment_deployment, EnvironmentDeployment)

    field(:ref, :string)
    field(:connection_id, :binary_id)

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for persisting one EnvironmentDeployment binding.

  ## Parameters

  * `binding` - The binding schema receiving persistence attributes
  * `attrs` - The parent deployment, endpoint ref, and Connection identifier

  ## Returns

  * A valid changeset when the ref and identifiers satisfy structural constraints
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Integrations.EnvironmentDeploymentBinding.create_changeset(
      ...>     %Leafcutter.Integrations.EnvironmentDeploymentBinding{},
      ...>     %{
      ...>       environment_deployment_id: Ecto.UUID.generate(),
      ...>       ref: "crm",
      ...>       connection_id: Ecto.UUID.generate()
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Integrations.EnvironmentDeploymentBinding.create_changeset(
      ...>     %Leafcutter.Integrations.EnvironmentDeploymentBinding{},
      ...>     %{ref: ""}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * The ref is required, valid UTF-8, non-empty, and at most 255 characters.
  * Refs are unique within one EnvironmentDeployment.
  * Scope, lifecycle, endpoint coverage, and Connector compatibility are
    validated by the capability.
  * Role, position, Operation, ContractVersion, config, and SecretVersion are excluded.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(binding, attrs) do
    binding
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields)
    |> validate_utf8(:ref)
    |> validate_length(:ref, max: 255)
    |> foreign_key_constraint(:environment_deployment_id)
    |> foreign_key_constraint(:connection_id)
    |> unique_constraint(
      [:environment_deployment_id, :ref],
      name: :environment_deployment_bindings_deployment_id_ref_index,
      error_key: :ref
    )
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
