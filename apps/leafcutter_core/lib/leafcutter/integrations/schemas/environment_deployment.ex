defmodule Leafcutter.Integrations.EnvironmentDeployment do
  @moduledoc """
  Represents the current executable state of one Integration in an Environment.

  A deployment selects one immutable PackageVersion, preserves promotable and
  local non-sensitive configuration, and owns a complete set of endpoint bindings.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Integrations.{EnvironmentDeploymentBinding, Integration}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @create_fields [
    :organization_id,
    :environment_id,
    :integration_id,
    :package_version_id,
    :promotable_config,
    :local_config
  ]
  @replace_fields [:package_version_id, :promotable_config, :local_config]

  @typedoc "The identifier of one EnvironmentDeployment."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a complete EnvironmentDeployment."
  @type create_attrs ::
          %{
            required(:organization_id) => Ecto.UUID.t(),
            required(:environment_id) => Ecto.UUID.t(),
            required(:integration_id) => Integration.id(),
            required(:package_version_id) => Ecto.UUID.t(),
            optional(:promotable_config) => map(),
            optional(:local_config) => map()
          }
          | %{
              required(String.t()) => String.t() | map()
            }

  @typedoc "Attributes accepted when replacing mutable deployment state."
  @type replace_attrs ::
          %{
            required(:package_version_id) => Ecto.UUID.t(),
            optional(:promotable_config) => map(),
            optional(:local_config) => map()
          }
          | %{
              required(String.t()) => String.t() | map()
            }

  @typedoc "Current executable deployment state and its complete endpoint bindings."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Ecto.UUID.t() | nil,
          environment_id: Ecto.UUID.t() | nil,
          integration_id: Integration.id() | nil,
          integration: Integration.t() | Ecto.Association.NotLoaded.t(),
          package_version_id: Ecto.UUID.t() | nil,
          promotable_config: map(),
          local_config: map(),
          bindings:
            [EnvironmentDeploymentBinding.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "environment_deployments" do
    field(:organization_id, :binary_id)
    field(:environment_id, :binary_id)

    belongs_to(:integration, Integration)

    field(:package_version_id, :binary_id)
    field(:promotable_config, :map, default: %{})
    field(:local_config, :map, default: %{})

    has_many(:bindings, EnvironmentDeploymentBinding)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a complete EnvironmentDeployment.

  ## Parameters

  * `deployment` - The EnvironmentDeployment schema receiving creation attributes
  * `attrs` - Scope, Integration, PackageVersion, and separated configuration

  ## Returns

  * A valid changeset when required identity and configuration attributes are valid
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Integrations.EnvironmentDeployment.create_changeset(
      ...>     %Leafcutter.Integrations.EnvironmentDeployment{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       environment_id: Ecto.UUID.generate(),
      ...>       integration_id: Ecto.UUID.generate(),
      ...>       package_version_id: Ecto.UUID.generate(),
      ...>       promotable_config: %{},
      ...>       local_config: %{}
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Integrations.EnvironmentDeployment.create_changeset(
      ...>     %Leafcutter.Integrations.EnvironmentDeployment{},
      ...>     %{promotable_config: []}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * Organization, Environment, Integration, and PackageVersion are required.
  * Config fields accept only JSON objects and normalize atom keys to strings.
  * Bindings are validated and persisted by the Deployments capability.
  * Identity, lifecycle extensions, effective config, and provenance history are excluded.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @create_fields)
    |> validate_required(@create_fields)
    |> validate_json_object(:promotable_config)
    |> validate_json_object(:local_config)
    |> apply_constraints()
  end

  @doc """
  Builds a changeset for replacing mutable EnvironmentDeployment state.

  ## Parameters

  * `deployment` - The persisted EnvironmentDeployment receiving replacement state
  * `attrs` - A complete PackageVersion and separated configuration replacement

  ## Returns

  * A valid changeset when the replacement state is structurally valid
  * An invalid changeset when configuration or a database constraint is invalid

  ## Examples

      iex> deployment =
      ...>   %Leafcutter.Integrations.EnvironmentDeployment{
      ...>     promotable_config: %{},
      ...>     local_config: %{}
      ...>   }

      iex> changeset =
      ...>   Leafcutter.Integrations.EnvironmentDeployment.replace_changeset(
      ...>     deployment,
      ...>     %{
      ...>       package_version_id: Ecto.UUID.generate(),
      ...>       promotable_config: %{batch_size: 100},
      ...>       local_config: %{}
      ...>     }
      ...>   )

      iex> Ecto.Changeset.get_change(changeset, :promotable_config)
      %{"batch_size" => 100}

  ## Notes

  * Only PackageVersion, promotable config, and local config are mutable.
  * Missing config is supplied as an empty object by the Deployments capability.
  * Scope and Integration identity are excluded from replacement.
  * The complete binding set is replaced separately in the same transaction.
  """
  @spec replace_changeset(t(), replace_attrs()) :: Ecto.Changeset.t()
  def replace_changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @replace_fields)
    |> validate_required(@replace_fields)
    |> validate_json_object(:promotable_config)
    |> validate_json_object(:local_config)
    |> apply_constraints()
  end

  @spec validate_json_object(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_json_object(changeset, field) do
    case fetch_change(changeset, field) do
      {:ok, value} ->
        case normalize_json_object(value) do
          {:ok, normalized_value} ->
            put_change(changeset, field, normalized_value)

          :error ->
            add_error(
              changeset,
              field,
              "must contain only JSON-compatible values",
              validation: :json_object
            )
        end

      :error ->
        changeset
    end
  end

  @spec normalize_json_object(term()) :: {:ok, map()} | :error
  defp normalize_json_object(%_{}), do: :error

  defp normalize_json_object(value) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, nested_value}, {:ok, acc} ->
      with {:ok, normalized_key} <- normalize_json_key(key),
           false <- Map.has_key?(acc, normalized_key),
           {:ok, normalized_value} <- normalize_json_value(nested_value) do
        {:cont, {:ok, Map.put(acc, normalized_key, normalized_value)}}
      else
        _invalid -> {:halt, :error}
      end
    end)
  end

  defp normalize_json_object(_value), do: :error

  @spec normalize_json_key(term()) :: {:ok, String.t()} | :error
  defp normalize_json_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> normalize_json_key()
  end

  defp normalize_json_key(key) when is_binary(key) do
    if String.valid?(key), do: {:ok, key}, else: :error
  end

  defp normalize_json_key(_key), do: :error

  @spec normalize_json_value(term()) :: {:ok, term()} | :error
  defp normalize_json_value(value)
       when is_nil(value) or is_boolean(value) or is_number(value),
       do: {:ok, value}

  defp normalize_json_value(value) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: :error
  end

  defp normalize_json_value(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn nested_value, {:ok, acc} ->
      case normalize_json_value(nested_value) do
        {:ok, normalized_value} ->
          {:cont, {:ok, [normalized_value | acc]}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized_values} -> {:ok, Enum.reverse(normalized_values)}
      :error -> :error
    end
  end

  defp normalize_json_value(value) when is_map(value) do
    normalize_json_object(value)
  end

  defp normalize_json_value(_value), do: :error

  @spec apply_constraints(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp apply_constraints(changeset) do
    changeset
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:environment_id)
    |> foreign_key_constraint(:integration_id)
    |> foreign_key_constraint(:package_version_id)
    |> foreign_key_constraint(:environment_id,
      name: :environment_deployments_organization_environment_fkey
    )
    |> foreign_key_constraint(:integration_id,
      name: :environment_deployments_integration_organization_fkey
    )
    |> unique_constraint(
      [:integration_id, :environment_id],
      name: :environment_deployments_integration_id_environment_id_index
    )
    |> check_constraint(:promotable_config,
      name: :environment_deployments_promotable_config_object
    )
    |> check_constraint(:local_config,
      name: :environment_deployments_local_config_object
    )
  end
end
