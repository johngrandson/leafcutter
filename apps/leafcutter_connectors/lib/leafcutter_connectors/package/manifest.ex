defmodule LeafcutterConnectors.Package.Manifest do
  @moduledoc """
  Validated identity and endpoint topology from a Package Manifest v1 document.

  Parsing preserves the exact input bytes for digest calculation while exposing
  only the validated, decoded fields needed by compiled package bindings.
  """

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @max_raw_bytes 1_048_576
  @max_depth 64
  @max_nodes 10_000
  @safe_path_keys ~w(manifest_version package name version source destinations ref)

  @manifest_schema %{
    "$schema" => @dialect,
    "$id" => "urn:leafcutter:package-manifest:v1",
    "type" => "object",
    "required" => [
      "manifest_version",
      "package",
      "source",
      "destinations"
    ],
    "additionalProperties" => false,
    "properties" => %{
      "manifest_version" => %{"const" => 1},
      "package" => %{
        "type" => "object",
        "required" => ["name", "version"],
        "additionalProperties" => false,
        "properties" => %{
          "name" => %{
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 255
          },
          "version" => %{
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 255
          }
        }
      },
      "source" => %{"$ref" => "#/$defs/endpoint"},
      "destinations" => %{
        "type" => "array",
        "minItems" => 1,
        "maxItems" => 1_000,
        "uniqueItems" => true,
        "items" => %{"$ref" => "#/$defs/endpoint"}
      }
    },
    "$defs" => %{
      "endpoint" => %{
        "type" => "object",
        "required" => ["ref"],
        "additionalProperties" => false,
        "properties" => %{
          "ref" => %{
            "type" => "string",
            "minLength" => 1,
            "maxLength" => 255
          }
        }
      }
    }
  }

  @build_options [
    resolver: [],
    default_meta: @dialect,
    formats: true,
    atoms: false,
    vocabularies: %{}
  ]
  @validation_options [cast: false, cast_formats: false]

  @enforce_keys [
    :package_name,
    :package_version,
    :source_ref,
    :destination_refs
  ]
  defstruct manifest_version: 1,
            package_name: nil,
            package_version: nil,
            source_ref: nil,
            destination_refs: []

  @typedoc "A segment in a deterministic path through a manifest document."
  @type path_segment :: String.t() | non_neg_integer()

  @typedoc "A deterministic root-relative path through a manifest document."
  @type path :: [path_segment()]

  @typedoc "An allowlisted reason for rejecting manifest bytes."
  @type error_reason ::
          :invalid_json
          | :duplicate_object_key
          | :size_limit_exceeded
          | :depth_limit_exceeded
          | :node_limit_exceeded
          | :schema_violation
          | :blank_string
          | :duplicate_ref

  @typedoc "A safe manifest error that never contains raw document values."
  @type error :: {error_reason(), path()}

  @typedoc "A validated Package Manifest v1 projection."
  @type t :: %__MODULE__{
          manifest_version: 1,
          package_name: String.t(),
          package_version: String.t(),
          source_ref: String.t(),
          destination_refs: nonempty_list(String.t())
        }

  @doc """
  Parses and validates exact Package Manifest v1 bytes.

  The raw byte limit is applied before decoding. Duplicate object keys,
  structural limits, the ratified JSON Schema, blank strings, and duplicate
  endpoint refs are then validated without normalizing accepted values.

  Returns `{:ok, manifest}` on success or a safe, deterministic
  `{:error, {reason, path}}` tuple on failure.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, error()}
  def parse(bytes) when is_binary(bytes) do
    with :ok <- validate_raw_size(bytes),
         {:ok, ordered_document} <- decode(bytes),
         {:ok, document, _node_count} <-
           normalize_node(ordered_document, [], 1, 0),
         :ok <- validate_semantics(document),
         :ok <- validate_schema(document) do
      {:ok, from_document(document)}
    end
  end

  def parse(_bytes), do: {:error, {:invalid_json, []}}

  @doc """
  Calculates the lowercase SHA-256 digest of exact manifest bytes.

  No JSON decoding, newline normalization, or canonicalization is performed.
  """
  @spec sha256(binary()) :: String.t()
  def sha256(bytes) when is_binary(bytes) do
    bytes
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec validate_raw_size(binary()) :: :ok | {:error, error()}
  defp validate_raw_size(bytes) do
    if byte_size(bytes) <= @max_raw_bytes do
      :ok
    else
      {:error, {:size_limit_exceeded, []}}
    end
  end

  @spec decode(binary()) :: {:ok, term()} | {:error, error()}
  defp decode(bytes) do
    case Jason.decode(bytes, objects: :ordered_objects, strings: :copy) do
      {:ok, document} -> {:ok, document}
      {:error, _decode_error} -> {:error, {:invalid_json, []}}
    end
  end

  @spec normalize_node(term(), path(), pos_integer(), non_neg_integer()) ::
          {:ok, term(), non_neg_integer()} | {:error, error()}
  defp normalize_node(value, path, depth, node_count) do
    node_count = node_count + 1

    if node_count > @max_nodes do
      {:error, {:node_limit_exceeded, safe_path(path)}}
    else
      normalize_value(value, path, depth, node_count)
    end
  end

  @spec normalize_value(term(), path(), pos_integer(), non_neg_integer()) ::
          {:ok, term(), non_neg_integer()} | {:error, error()}
  defp normalize_value(
         %Jason.OrderedObject{values: entries},
         path,
         depth,
         node_count
       ) do
    with :ok <- validate_depth(depth, path),
         :ok <- validate_unique_keys(entries, path) do
      normalize_object(entries, path, depth, node_count)
    end
  end

  defp normalize_value(values, path, depth, node_count)
       when is_list(values) do
    case validate_depth(depth, path) do
      :ok -> normalize_list(values, path, depth, node_count)
      {:error, _error} = failure -> failure
    end
  end

  defp normalize_value(value, _path, _depth, node_count)
       when is_nil(value) or is_boolean(value) or is_number(value) or
              is_binary(value) do
    {:ok, value, node_count}
  end

  defp normalize_value(_value, path, _depth, _node_count) do
    {:error, {:invalid_json, safe_path(path)}}
  end

  @spec normalize_object(
          [{String.t(), term()}],
          path(),
          pos_integer(),
          non_neg_integer()
        ) :: {:ok, map(), non_neg_integer()} | {:error, error()}
  defp normalize_object(entries, path, depth, node_count) do
    Enum.reduce_while(
      entries,
      {:ok, %{}, node_count},
      fn entry, accumulator ->
        normalize_object_entry(entry, accumulator, path, depth)
      end
    )
  end

  @spec normalize_object_entry(
          {String.t(), term()},
          {:ok, map(), non_neg_integer()},
          path(),
          pos_integer()
        ) ::
          {:cont, {:ok, map(), non_neg_integer()}} | {:halt, {:error, error()}}
  defp normalize_object_entry(
         {key, nested_value},
         {:ok, object, node_count},
         path,
         depth
       ) do
    nested_path = path ++ [key]

    case normalize_node(
           nested_value,
           nested_path,
           nested_depth(nested_value, depth),
           node_count
         ) do
      {:ok, normalized_value, next_count} ->
        {:cont, {:ok, Map.put(object, key, normalized_value), next_count}}

      {:error, _error} = failure ->
        {:halt, failure}
    end
  end

  @spec normalize_list([term()], path(), pos_integer(), non_neg_integer()) ::
          {:ok, [term()], non_neg_integer()} | {:error, error()}
  defp normalize_list(values, path, depth, node_count) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], node_count}, fn entry, accumulator ->
      normalize_list_entry(entry, accumulator, path, depth)
    end)
    |> reverse_normalized_list()
  end

  @spec normalize_list_entry(
          {term(), non_neg_integer()},
          {:ok, [term()], non_neg_integer()},
          path(),
          pos_integer()
        ) ::
          {:cont, {:ok, [term()], non_neg_integer()}}
          | {:halt, {:error, error()}}
  defp normalize_list_entry(
         {nested_value, index},
         {:ok, normalized_values, node_count},
         path,
         depth
       ) do
    case normalize_node(
           nested_value,
           path ++ [index],
           nested_depth(nested_value, depth),
           node_count
         ) do
      {:ok, normalized_value, next_count} ->
        {:cont, {:ok, [normalized_value | normalized_values], next_count}}

      {:error, _error} = failure ->
        {:halt, failure}
    end
  end

  @spec reverse_normalized_list(
          {:ok, [term()], non_neg_integer()} | {:error, error()}
        ) :: {:ok, [term()], non_neg_integer()} | {:error, error()}
  defp reverse_normalized_list({:ok, values, node_count}) do
    {:ok, Enum.reverse(values), node_count}
  end

  defp reverse_normalized_list({:error, _error} = failure), do: failure

  @spec validate_unique_keys([{String.t(), term()}], path()) ::
          :ok | {:error, error()}
  defp validate_unique_keys(entries, path) do
    entries
    |> Enum.reduce_while(%{}, fn {key, _value}, seen ->
      if Map.has_key?(seen, key) do
        {:halt,
         {:error, {:duplicate_object_key, safe_path(path ++ [key])}}}
      else
        {:cont, Map.put(seen, key, true)}
      end
    end)
    |> case do
      {:error, _error} = failure -> failure
      _seen -> :ok
    end
  end

  @spec validate_depth(pos_integer(), path()) :: :ok | {:error, error()}
  defp validate_depth(depth, path) do
    if depth <= @max_depth do
      :ok
    else
      {:error, {:depth_limit_exceeded, safe_path(path)}}
    end
  end

  @spec safe_path(path()) :: path()
  defp safe_path(path), do: safe_path(path, [])

  @spec safe_path(path(), path()) :: path()
  defp safe_path([], reversed_path), do: Enum.reverse(reversed_path)

  defp safe_path([segment | rest], reversed_path)
       when segment in @safe_path_keys do
    safe_path(rest, [segment | reversed_path])
  end

  defp safe_path([segment | rest], reversed_path)
       when is_integer(segment) and segment >= 0 do
    safe_path(rest, [segment | reversed_path])
  end

  defp safe_path([_unsafe_segment | _rest], reversed_path) do
    Enum.reverse(reversed_path)
  end

  @spec nested_depth(term(), pos_integer()) :: pos_integer()
  defp nested_depth(%Jason.OrderedObject{}, current_depth),
    do: current_depth + 1

  defp nested_depth(value, current_depth) when is_list(value),
    do: current_depth + 1

  defp nested_depth(_value, current_depth), do: current_depth

  @spec validate_schema(term()) :: :ok | {:error, error()}
  defp validate_schema(document) do
    case JSV.build(@manifest_schema, @build_options) do
      {:ok, root} ->
        case JSV.validate(document, root, @validation_options) do
          {:ok, _validated_document} -> :ok
          {:error, _validation_error} -> {:error, {:schema_violation, []}}
        end

      {:error, build_error} ->
        raise "embedded Package Manifest v1 schema failed to build: #{inspect(build_error)}"
    end
  end

  @spec validate_semantics(term()) :: :ok | {:error, error()}
  defp validate_semantics(%{
         "package" => %{"name" => name, "version" => version},
         "source" => %{"ref" => source_ref},
         "destinations" => destinations
       })
       when is_binary(name) and is_binary(version) and is_binary(source_ref) and
              is_list(destinations) do
    case destination_refs(destinations) do
      {:ok, refs} ->
        with :ok <- validate_non_blank(name, ["package", "name"]),
             :ok <- validate_non_blank(version, ["package", "version"]),
             :ok <- validate_non_blank(source_ref, ["source", "ref"]),
             :ok <- validate_destination_refs(refs) do
          validate_unique_refs(source_ref, refs)
        end

      :invalid_shape ->
        :ok
    end
  end

  defp validate_semantics(_document), do: :ok

  @spec destination_refs(term()) :: {:ok, [String.t()]} | :invalid_shape
  defp destination_refs(destinations) do
    Enum.reduce_while(destinations, {:ok, []}, fn
      %{"ref" => ref}, {:ok, refs} when is_binary(ref) ->
        {:cont, {:ok, [ref | refs]}}

      _destination, _accumulator ->
        {:halt, :invalid_shape}
    end)
    |> case do
      {:ok, refs} -> {:ok, Enum.reverse(refs)}
      :invalid_shape -> :invalid_shape
    end
  end

  @spec validate_non_blank(String.t(), path()) :: :ok | {:error, error()}
  defp validate_non_blank(value, path) do
    if String.trim(value) == "" do
      {:error, {:blank_string, path}}
    else
      :ok
    end
  end

  @spec validate_destination_refs([String.t()]) :: :ok | {:error, error()}
  defp validate_destination_refs(refs) do
    refs
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {ref, index}, :ok ->
      case validate_non_blank(ref, ["destinations", index, "ref"]) do
        :ok -> {:cont, :ok}
        {:error, _error} = failure -> {:halt, failure}
      end
    end)
  end

  @spec validate_unique_refs(String.t(), [String.t()]) ::
          :ok | {:error, error()}
  defp validate_unique_refs(source_ref, destination_refs) do
    destination_refs
    |> Enum.with_index()
    |> Enum.reduce_while(%{source_ref => true}, fn {ref, index}, seen ->
      if Map.has_key?(seen, ref) do
        {:halt, {:error, {:duplicate_ref, ["destinations", index, "ref"]}}}
      else
        {:cont, Map.put(seen, ref, true)}
      end
    end)
    |> case do
      {:error, _error} = failure -> failure
      _seen -> :ok
    end
  end

  @spec from_document(map()) :: t()
  defp from_document(%{
         "manifest_version" => _validated_version,
         "package" => %{"name" => name, "version" => version},
         "source" => %{"ref" => source_ref},
         "destinations" => destinations
       }) do
    %__MODULE__{
      package_name: name,
      package_version: version,
      source_ref: source_ref,
      destination_refs: Enum.map(destinations, &Map.fetch!(&1, "ref"))
    }
  end
end
