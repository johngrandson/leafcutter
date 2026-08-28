defmodule Leafcutter.Executions.RunSnapshot.DefinitionV1 do
  @moduledoc """
  Validates and normalizes the structural RunSnapshot definition format v1.

  This module validates shape, UUID syntax, endpoint cardinality, local
  reference uniqueness, and JSON-compatible configuration. It does not verify
  that referenced Catalog or Connections entities exist.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Leafcutter.Executions.RunSnapshot.DefinitionV1.{Connection, Endpoint}

  @primary_key false
  @root_fields [:package_version_id, :source, :destinations, :effective_config]
  @root_cast_fields [:package_version_id, :effective_config]
  @endpoint_fields [:ref, :contract_version_id, :connection]
  @endpoint_cast_fields [:ref, :contract_version_id]
  @connection_fields [:id, :config, :secret_version_id]

  @typedoc "A structurally valid v1 definition using canonical JSON string keys."
  @type normalized_definition :: %{required(String.t()) => term()}

  @typep normalization_accumulator :: {map(), [String.t()], [atom()]}

  @typedoc "The embedded representation used while validating definition v1."
  @type t :: %__MODULE__{
          package_version_id: Ecto.UUID.t() | nil,
          source: Endpoint.t() | nil,
          destinations: [Endpoint.t()],
          effective_config: map() | nil
        }

  embedded_schema do
    field(:package_version_id, :binary_id)
    embeds_one(:source, Endpoint, on_replace: :raise)
    embeds_many(:destinations, Endpoint, on_replace: :raise)
    field(:effective_config, :map)
  end

  @doc """
  Validates and normalizes a RunSnapshot definition using format v1.

  ## Parameters

  * attrs - The complete v1 definition using either atom or string keys at each object level

  ## Returns

  * {:ok, definition} with canonical JSON string keys when the structure is valid
  * {:error, changeset} with root and nested validation errors when the structure is invalid

  ## Examples

      iex> connection = %{
      ...>   id: Ecto.UUID.generate(),
      ...>   config: %{},
      ...>   secret_version_id: nil
      ...> }

      iex> attrs = %{
      ...>   package_version_id: Ecto.UUID.generate(),
      ...>   source: %{
      ...>     ref: "source",
      ...>     contract_version_id: Ecto.UUID.generate(),
      ...>     connection: connection
      ...>   },
      ...>   destinations: [
      ...>     %{
      ...>       ref: "crm",
      ...>       contract_version_id: Ecto.UUID.generate(),
      ...>       connection: connection
      ...>     }
      ...>   ],
      ...>   effective_config: %{}
      ...> }

      iex> {:ok, definition} =
      ...>   Leafcutter.Executions.RunSnapshot.DefinitionV1.validate(attrs)

      iex> is_binary(definition["package_version_id"])
      true

      iex> {:error, changeset} =
      ...>   Leafcutter.Executions.RunSnapshot.DefinitionV1.validate(%{})

      iex> changeset.valid?
      false

  ## Notes

  * Exactly one source and at least one destination are required.
  * Source and destination references must be non-empty and mutually unique.
  * Unknown fields and duplicate atom/string forms of the same field are rejected.
  * Configuration objects may contain only JSON-compatible values.
  * Atom keys inside configuration objects are normalized to JSON string keys.
  * Destination order is preserved but does not define execution priority.
  * Raw-secret detection and referenced-entity existence are outside structural validation.
  """
  @spec validate(term()) ::
          {:ok, normalized_definition()} | {:error, Changeset.t()}
  def validate(attrs) when is_map(attrs) do
    changeset = definition_changeset(%__MODULE__{}, attrs)

    if changeset.valid? do
      {:ok, changeset |> apply_changes() |> to_definition_map()}
    else
      {:error, changeset}
    end
  end

  def validate(_attrs) do
    changeset =
      %__MODULE__{}
      |> change()
      |> add_error(:base, "must be a map", validation: :map)

    {:error, changeset}
  end

  @spec definition_changeset(t(), map()) :: Changeset.t()
  defp definition_changeset(definition, attrs) do
    definition
    |> normalized_cast(attrs, @root_cast_fields, @root_fields)
    |> validate_required(@root_cast_fields)
    |> validate_uuid(:package_version_id)
    |> cast_embed(:source, required: true, with: &endpoint_changeset/2)
    |> cast_embed(:destinations, required: true, with: &endpoint_changeset/2)
    |> validate_length(:destinations, min: 1)
    |> validate_json_object(:effective_config)
    |> validate_unique_refs()
  end

  @spec endpoint_changeset(Endpoint.t(), map()) :: Changeset.t()
  defp endpoint_changeset(endpoint, attrs) do
    endpoint
    |> normalized_cast(attrs, @endpoint_cast_fields, @endpoint_fields)
    |> validate_required(@endpoint_cast_fields)
    |> validate_uuid(:contract_version_id)
    |> validate_ref()
    |> cast_embed(:connection, required: true, with: &connection_changeset/2)
  end

  @spec connection_changeset(Connection.t(), map()) :: Changeset.t()
  defp connection_changeset(connection, attrs) do
    connection
    |> normalized_cast(attrs, @connection_fields, @connection_fields)
    |> validate_required([:id, :config])
    |> validate_uuid(:id)
    |> validate_uuid(:secret_version_id)
    |> validate_json_object(:config)
  end

  @spec normalized_cast(struct(), map(), [atom()], [atom()]) :: Changeset.t()
  defp normalized_cast(data, attrs, cast_fields, allowed_fields) do
    {params, unknown_fields, duplicate_fields} =
      normalize_params(attrs, allowed_fields)

    data
    |> cast(params, cast_fields)
    |> add_normalization_errors(unknown_fields, duplicate_fields)
  end

  @spec normalize_params(map(), [atom()]) ::
          {map(), [String.t()], [atom()]}
  defp normalize_params(attrs, allowed_fields) do
    fields_by_string =
      Map.new(allowed_fields, fn field ->
        {Atom.to_string(field), field}
      end)

    Enum.reduce(attrs, {%{}, [], []}, fn entry, accumulator ->
      normalize_param(
        entry,
        accumulator,
        allowed_fields,
        fields_by_string
      )
    end)
  end

  @spec normalize_param(
          {term(), term()},
          normalization_accumulator(),
          [atom()],
          %{String.t() => atom()}
        ) :: normalization_accumulator()
  defp normalize_param(
         {key, value},
         {params, unknown_fields, duplicate_fields},
         allowed_fields,
         fields_by_string
       ) do
    case normalize_field(key, allowed_fields, fields_by_string) do
      {:ok, field} when is_map_key(params, field) ->
        {params, unknown_fields, [field | duplicate_fields]}

      {:ok, field} ->
        {Map.put(params, field, value), unknown_fields, duplicate_fields}

      :error ->
        {params, [inspect(key) | unknown_fields], duplicate_fields}
    end
  end

  @spec normalize_field(term(), [atom()], %{String.t() => atom()}) ::
          {:ok, atom()} | :error
  defp normalize_field(key, allowed_fields, _fields_by_string)
       when is_atom(key) do
    if key in allowed_fields, do: {:ok, key}, else: :error
  end

  defp normalize_field(key, _allowed_fields, fields_by_string)
       when is_binary(key) do
    Map.fetch(fields_by_string, key)
  end

  defp normalize_field(_key, _allowed_fields, _fields_by_string), do: :error

  @spec add_normalization_errors(
          Changeset.t(),
          [String.t()],
          [atom()]
        ) :: Changeset.t()
  defp add_normalization_errors(changeset, unknown_fields, duplicate_fields) do
    changeset
    |> maybe_add_unknown_fields_error(unknown_fields)
    |> maybe_add_duplicate_fields_error(duplicate_fields)
  end

  @spec maybe_add_unknown_fields_error(Changeset.t(), [String.t()]) ::
          Changeset.t()
  defp maybe_add_unknown_fields_error(changeset, []), do: changeset

  defp maybe_add_unknown_fields_error(changeset, unknown_fields) do
    add_error(changeset, :base, "contains unknown fields",
      validation: :unknown_fields,
      fields: Enum.sort(unknown_fields)
    )
  end

  @spec maybe_add_duplicate_fields_error(Changeset.t(), [atom()]) ::
          Changeset.t()
  defp maybe_add_duplicate_fields_error(changeset, []), do: changeset

  defp maybe_add_duplicate_fields_error(changeset, duplicate_fields) do
    fields =
      duplicate_fields
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&Atom.to_string/1)

    add_error(changeset, :base, "contains duplicate fields",
      validation: :duplicate_fields,
      fields: fields
    )
  end

  @spec validate_uuid(Changeset.t(), atom()) :: Changeset.t()
  defp validate_uuid(changeset, field) do
    case fetch_change(changeset, field) do
      {:ok, value} ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} ->
            put_change(changeset, field, uuid)

          :error ->
            add_error(
              changeset,
              field,
              "is not a valid UUID",
              validation: :uuid
            )
        end

      :error ->
        changeset
    end
  end

  @spec validate_ref(Changeset.t()) :: Changeset.t()
  defp validate_ref(changeset) do
    validate_change(changeset, :ref, fn :ref, ref ->
      cond do
        not String.valid?(ref) ->
          [ref: {"must be valid UTF-8", validation: :utf8}]

        String.trim(ref) == "" ->
          [
            ref: {"must contain a non-whitespace character", validation: :format}
          ]

        true ->
          []
      end
    end)
  end

  @spec validate_json_object(Changeset.t(), atom()) :: Changeset.t()
  defp validate_json_object(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value ->
        if json_object?(value) do
          changeset
        else
          add_error(
            changeset,
            field,
            "must contain only JSON-compatible values",
            validation: :json_object
          )
        end
    end
  end

  @spec validate_unique_refs(Changeset.t()) :: Changeset.t()
  defp validate_unique_refs(changeset) do
    definition = apply_changes(changeset)

    refs =
      [definition.source | definition.destinations]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.ref)
      |> Enum.filter(fn ref ->
        is_binary(ref) and String.valid?(ref) and String.trim(ref) != ""
      end)

    if length(refs) == MapSet.size(MapSet.new(refs)) do
      changeset
    else
      add_error(
        changeset,
        :destinations,
        "source and destination references must be unique",
        validation: :unique_refs
      )
    end
  end

  @spec json_object?(term()) :: boolean()
  defp json_object?(%_{}), do: false

  defp json_object?(value) when is_map(value) do
    normalized_keys =
      Enum.map(Map.keys(value), fn
        key when is_binary(key) -> valid_json_string(key)
        key when is_atom(key) -> key |> Atom.to_string() |> valid_json_string()
        _key -> nil
      end)

    Enum.all?(normalized_keys, &is_binary/1) and
      length(normalized_keys) == MapSet.size(MapSet.new(normalized_keys)) and
      Enum.all?(Map.values(value), &json_value?/1)
  end

  defp json_object?(_value), do: false

  @spec json_value?(term()) :: boolean()
  defp json_value?(value)
       when is_nil(value) or is_boolean(value) or is_number(value),
       do: true

  defp json_value?(value) when is_binary(value), do: String.valid?(value)

  defp json_value?(value) when is_list(value) do
    Enum.all?(value, &json_value?/1)
  end

  defp json_value?(value) when is_map(value), do: json_object?(value)
  defp json_value?(_value), do: false

  @spec valid_json_string(binary()) :: binary() | nil
  defp valid_json_string(value) do
    if String.valid?(value), do: value
  end

  @spec to_definition_map(t()) :: normalized_definition()
  defp to_definition_map(definition) do
    %{
      "package_version_id" => definition.package_version_id,
      "source" => endpoint_to_map(definition.source),
      "destinations" => Enum.map(definition.destinations, &endpoint_to_map/1),
      "effective_config" => normalize_json_object(definition.effective_config)
    }
  end

  @spec endpoint_to_map(Endpoint.t()) :: map()
  defp endpoint_to_map(endpoint) do
    %{
      "ref" => endpoint.ref,
      "contract_version_id" => endpoint.contract_version_id,
      "connection" => connection_to_map(endpoint.connection)
    }
  end

  @spec connection_to_map(Connection.t()) :: map()
  defp connection_to_map(connection) do
    %{
      "id" => connection.id,
      "config" => normalize_json_object(connection.config),
      "secret_version_id" => connection.secret_version_id
    }
  end

  @spec normalize_json_object(map()) :: map()
  defp normalize_json_object(value) do
    Map.new(value, fn {key, nested_value} ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: key
      {normalized_key, normalize_json_value(nested_value)}
    end)
  end

  @spec normalize_json_value(term()) :: term()
  defp normalize_json_value(value) when is_list(value) do
    Enum.map(value, &normalize_json_value/1)
  end

  defp normalize_json_value(value) when is_map(value) do
    normalize_json_object(value)
  end

  defp normalize_json_value(value), do: value
end
