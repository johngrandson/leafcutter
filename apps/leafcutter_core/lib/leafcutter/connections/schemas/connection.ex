defmodule Leafcutter.Connections.Connection do
  @moduledoc """
  Represents an environment-scoped connection to a stable Catalog Connector.

  A Connection stores only non-sensitive configuration and may bind one exact
  immutable SecretVersion. Mutable fields affect future resolutions only.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Leafcutter.Connections.SecretVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @create_fields [
    :organization_id,
    :environment_id,
    :connector_id,
    :name,
    :config,
    :secret_version_id
  ]
  @required_create_fields [
    :organization_id,
    :environment_id,
    :connector_id,
    :name,
    :config
  ]
  @update_fields [:config, :secret_version_id]

  @typedoc "The identifier of one environment-scoped Connection."
  @type id :: Ecto.UUID.t()

  @typedoc "Attributes accepted when creating a Connection."
  @type create_attrs ::
          %{
            required(:organization_id) => Ecto.UUID.t(),
            required(:environment_id) => Ecto.UUID.t(),
            required(:connector_id) => Ecto.UUID.t(),
            required(:name) => String.t(),
            optional(:config) => map(),
            optional(:secret_version_id) => SecretVersion.id() | nil
          }
          | %{
              required(String.t()) => String.t() | map() | SecretVersion.id() | nil
            }

  @typedoc "Mutable attributes accepted when updating a Connection."
  @type update_attrs ::
          %{
            optional(:config) => map(),
            optional(:secret_version_id) => SecretVersion.id() | nil
          }
          | %{
              optional(String.t()) => map() | SecretVersion.id() | nil
            }

  @typedoc "An environment-scoped Connection and its current mutable state."
  @type t :: %__MODULE__{
          id: id() | nil,
          organization_id: Ecto.UUID.t() | nil,
          environment_id: Ecto.UUID.t() | nil,
          connector_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          config: map(),
          secret_version_id: SecretVersion.id() | nil,
          secret_version: SecretVersion.t() | Ecto.Association.NotLoaded.t(),
          disabled_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "connections" do
    field(:organization_id, :binary_id)
    field(:environment_id, :binary_id)
    field(:connector_id, :binary_id)
    field(:name, :string)
    field(:config, :map, default: %{})

    belongs_to(:secret_version, SecretVersion)

    field(:disabled_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a Connection.

  ## Parameters

  * `connection` - The Connection schema receiving creation attributes
  * `attrs` - The external scope, Connector, name, config, and optional SecretVersion binding

  ## Returns

  * A valid changeset when the required attributes and config satisfy the contract
  * An invalid changeset when an attribute or database constraint is invalid

  ## Examples

      iex> changeset =
      ...>   Leafcutter.Connections.Connection.create_changeset(
      ...>     %Leafcutter.Connections.Connection{},
      ...>     %{
      ...>       organization_id: Ecto.UUID.generate(),
      ...>       environment_id: Ecto.UUID.generate(),
      ...>       connector_id: Ecto.UUID.generate(),
      ...>       name: "CRM",
      ...>       config: %{"base_url" => "https://example.test"}
      ...>     }
      ...>   )

      iex> changeset.valid?
      true

      iex> changeset =
      ...>   Leafcutter.Connections.Connection.create_changeset(
      ...>     %Leafcutter.Connections.Connection{},
      ...>     %{name: "CRM", config: []}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * Organization, Environment, Connector, and name are required.
  * Config defaults to an empty object and accepts only JSON-compatible values.
  * Atom keys inside config are normalized to JSON string keys.
  * The optional SecretVersion must belong to the same Organization and Environment.
  * Raw secret material, lifecycle state, and identity fields are excluded from the cast.
  """
  @spec create_changeset(t(), create_attrs()) :: Ecto.Changeset.t()
  def create_changeset(connection, attrs) do
    connection
    |> cast(attrs, @create_fields)
    |> validate_required(@required_create_fields)
    |> validate_name()
    |> validate_json_object(:config)
    |> apply_constraints()
  end

  @doc """
  Builds a changeset for updating mutable Connection state.

  ## Parameters

  * `connection` - The persisted Connection receiving mutable attributes
  * `attrs` - A replacement config, an exact SecretVersion binding, or both

  ## Returns

  * A valid changeset when the mutable attributes satisfy the contract
  * An invalid changeset when config or a database constraint is invalid

  ## Examples

      iex> connection = %Leafcutter.Connections.Connection{config: %{}}
      iex> changeset =
      ...>   Leafcutter.Connections.Connection.update_changeset(
      ...>     connection,
      ...>     %{config: %{"timeout" => 30}}
      ...>   )

      iex> Ecto.Changeset.get_change(changeset, :config)
      %{"timeout" => 30}

      iex> connection = %Leafcutter.Connections.Connection{config: %{}}
      iex> changeset =
      ...>   Leafcutter.Connections.Connection.update_changeset(
      ...>     connection,
      ...>     %{config: :invalid}
      ...>   )

      iex> changeset.valid?
      false

  ## Notes

  * Only config and `secret_version_id` are mutable.
  * Organization, Environment, Connector, name, and lifecycle state are excluded.
  * Setting `secret_version_id` to `nil` removes the binding explicitly.
  * Persistence and concurrency control are handled by the Connections context.
  """
  @spec update_changeset(t(), update_attrs()) :: Ecto.Changeset.t()
  def update_changeset(connection, attrs) do
    connection
    |> cast(attrs, @update_fields)
    |> validate_json_object(:config)
    |> apply_constraints()
  end

  @doc """
  Builds a changeset for disabling a Connection.

  ## Parameters

  * `connection` - The Connection whose lifecycle state will change

  ## Returns

  * A changeset with a new disable timestamp when the Connection is active
  * An unchanged changeset when the Connection is already disabled

  ## Examples

      iex> connection = %Leafcutter.Connections.Connection{}
      iex> changeset =
      ...>   Leafcutter.Connections.Connection.disable_changeset(connection)

      iex> is_struct(Ecto.Changeset.get_change(changeset, :disabled_at), DateTime)
      true

  ## Notes

  * Disable is idempotent and preserves an existing timestamp.
  * Callers cannot set `disabled_at` through create or update changesets.
  * Persistence and row locking are handled by the Connections context.
  """
  @spec disable_changeset(t()) :: Ecto.Changeset.t()
  def disable_changeset(%__MODULE__{disabled_at: nil} = connection) do
    change(connection, disabled_at: DateTime.utc_now(:microsecond))
  end

  def disable_changeset(%__MODULE__{} = connection) do
    change(connection)
  end

  @spec validate_name(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_name(changeset) do
    changeset
    |> validate_utf8(:name)
    |> validate_length(:name, max: 255)
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
    |> foreign_key_constraint(:connector_id)
    |> foreign_key_constraint(:secret_version_id)
    |> foreign_key_constraint(:environment_id,
      name: :connections_organization_environment_fkey
    )
    |> check_constraint(:config, name: :connections_config_object)
    |> check_constraint(:secret_version_id,
      name: :connections_secret_version_scope
    )
  end
end
