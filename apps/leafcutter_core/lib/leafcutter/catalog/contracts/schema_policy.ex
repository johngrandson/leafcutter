defmodule Leafcutter.Catalog.Contracts.SchemaPolicy do
  @moduledoc """
  Validates the executable document policy for ContractVersion schemas.

  This module validates only deterministic, side-effect-free document rules.
  It does not access persistence, build a JSV root, or validate payloads.
  """

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @max_serialized_bytes 1_048_576
  @max_depth 64
  @max_nodes 10_000

  @typedoc "A segment in a deterministic path through a JSON document."
  @type path_segment :: String.t() | non_neg_integer()

  @typedoc "A deterministic root-relative path through a JSON document."
  @type path :: [path_segment()]

  @typedoc "The concrete reason a value is not JSON-compatible."
  @type json_error_detail ::
          :non_string_key
          | :invalid_utf8_key
          | :invalid_utf8_string
          | :unencodable_number
          | :unsupported_value

  @typedoc "An internal deterministic ContractVersion schema policy error."
  @type error ::
          {:invalid_root, path()}
          | {:invalid_json, path(), json_error_detail()}
          | {:invalid_dialect, path()}
          | {:invalid_reference, path()}
          | {:forbidden_keyword, path()}
          | {:depth_limit_exceeded, path()}
          | {:node_limit_exceeded, path()}
          | {:size_limit_exceeded, path()}

  @typedoc "A policy-approved object or boolean JSON Schema document."
  @type document :: map() | boolean()

  @doc """
  Validates one ContractVersion schema document without normalizing it.

  ## Parameters

  * `document` - The object or boolean JSON Schema document to validate

  ## Returns

  * `{:ok, document}` when every pure document rule is satisfied
  * `{:error, error}` with a deterministic root-relative path otherwise

  ## Examples

      iex> Leafcutter.Catalog.Contracts.SchemaPolicy.validate(true)
      {:ok, true}

      iex> Leafcutter.Catalog.Contracts.SchemaPolicy.validate(%{
      ...>   "$schema" => "https://json-schema.org/draft/2020-12/schema",
      ...>   "$ref" => "https://example.test/schema"
      ...> })
      {:error, {:invalid_reference, ["$ref"]}}

  ## Notes

  * Object roots must declare the canonical Draft 2020-12 dialect.
  * References are restricted to fragments in the same document.
  * JSV casting extensions are rejected at every depth.
  * The root counts as one node and as structural depth one.
  * The input document is returned unchanged after successful validation.
  """
  @spec validate(term()) :: {:ok, document()} | {:error, error()}
  def validate(document) do
    with :ok <- validate_root(document),
         {:ok, _node_count} <- validate_json(document, [], 1, 0),
         :ok <- validate_dialect(document),
         :ok <- validate_keywords(document, []),
         :ok <- validate_serialized_size(document) do
      {:ok, document}
    end
  end

  @spec validate_root(term()) :: :ok | {:error, error()}
  defp validate_root(value) when is_boolean(value), do: :ok

  defp validate_root(value) when is_map(value) do
    if is_struct(value), do: {:error, {:invalid_root, []}}, else: :ok
  end

  defp validate_root(_value), do: {:error, {:invalid_root, []}}

  @spec validate_json(term(), path(), pos_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, error()}
  defp validate_json(value, path, depth, node_count) do
    node_count = node_count + 1

    if node_count > @max_nodes do
      {:error, {:node_limit_exceeded, path}}
    else
      validate_json_value(value, path, depth, node_count)
    end
  end

  @spec validate_json_value(term(), path(), pos_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, error()}
  defp validate_json_value(%_{} = _value, path, _depth, _node_count) do
    {:error, {:invalid_json, path, :unsupported_value}}
  end

  defp validate_json_value(value, path, depth, node_count) when is_map(value) do
    with :ok <- validate_container_depth(depth, path),
         :ok <- validate_object_keys(value, path) do
      value
      |> Enum.sort_by(fn {key, _nested_value} -> key end)
      |> Enum.reduce_while({:ok, node_count}, fn {key, nested_value},
                                                {:ok, current_count} ->
        nested_path = path ++ [key]
        nested_depth = nested_depth(nested_value, depth)

        case validate_json(nested_value, nested_path, nested_depth, current_count) do
          {:ok, next_count} -> {:cont, {:ok, next_count}}
          {:error, _error} = failure -> {:halt, failure}
        end
      end)
    end
  end

  defp validate_json_value(value, path, depth, node_count) when is_list(value) do
    with :ok <- validate_container_depth(depth, path) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, node_count}, fn {nested_value, index},
                                                {:ok, current_count} ->
        nested_path = path ++ [index]
        nested_depth = nested_depth(nested_value, depth)

        case validate_json(nested_value, nested_path, nested_depth, current_count) do
          {:ok, next_count} -> {:cont, {:ok, next_count}}
          {:error, _error} = failure -> {:halt, failure}
        end
      end)
    end
  end

  defp validate_json_value(value, _path, _depth, node_count)
       when is_nil(value) or is_boolean(value),
       do: {:ok, node_count}

  defp validate_json_value(value, path, _depth, node_count)
       when is_integer(value) or is_float(value) do
    case Jason.encode(value) do
      {:ok, _encoded} -> {:ok, node_count}
      {:error, _exception} -> {:error, {:invalid_json, path, :unencodable_number}}
    end
  end

  defp validate_json_value(value, path, _depth, node_count) when is_binary(value) do
    if String.valid?(value) do
      {:ok, node_count}
    else
      {:error, {:invalid_json, path, :invalid_utf8_string}}
    end
  end

  defp validate_json_value(_value, path, _depth, _node_count) do
    {:error, {:invalid_json, path, :unsupported_value}}
  end

  @spec validate_container_depth(pos_integer(), path()) :: :ok | {:error, error()}
  defp validate_container_depth(depth, path) do
    if depth <= @max_depth do
      :ok
    else
      {:error, {:depth_limit_exceeded, path}}
    end
  end

  @spec validate_object_keys(map(), path()) :: :ok | {:error, error()}
  defp validate_object_keys(value, path) do
    keys = Map.keys(value)

    cond do
      Enum.any?(keys, fn key -> not is_binary(key) end) ->
        {:error, {:invalid_json, path, :non_string_key}}

      Enum.any?(keys, fn key -> not String.valid?(key) end) ->
        {:error, {:invalid_json, path, :invalid_utf8_key}}

      true ->
        :ok
    end
  end

  @spec nested_depth(term(), pos_integer()) :: pos_integer()
  defp nested_depth(value, current_depth) when is_map(value) or is_list(value),
    do: current_depth + 1

  defp nested_depth(_value, current_depth), do: current_depth

  @spec validate_dialect(document()) :: :ok | {:error, error()}
  defp validate_dialect(value) when is_boolean(value), do: :ok

  defp validate_dialect(value) do
    if Map.get(value, "$schema") == @dialect do
      :ok
    else
      {:error, {:invalid_dialect, ["$schema"]}}
    end
  end

  @spec validate_keywords(term(), path()) :: :ok | {:error, error()}
  defp validate_keywords(value, path) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _nested_value} -> key end)
    |> Enum.reduce_while(:ok, fn {key, nested_value}, :ok ->
      nested_path = path ++ [key]

      with :ok <- validate_keyword(key, nested_value, nested_path),
           :ok <- validate_keywords(nested_value, nested_path) do
        {:cont, :ok}
      else
        {:error, _error} = failure -> {:halt, failure}
      end
    end)
  end

  defp validate_keywords(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {nested_value, index}, :ok ->
      nested_path = path ++ [index]

      case validate_keywords(nested_value, nested_path) do
        :ok -> {:cont, :ok}
        {:error, _error} = failure -> {:halt, failure}
      end
    end)
  end

  defp validate_keywords(_value, _path), do: :ok

  @spec validate_keyword(String.t(), term(), path()) :: :ok | {:error, error()}
  defp validate_keyword("jsv-cast", _value, path) do
    {:error, {:forbidden_keyword, path}}
  end

  defp validate_keyword("x-jsv-cast", _value, path) do
    {:error, {:forbidden_keyword, path}}
  end

  defp validate_keyword("$ref", value, path), do: validate_reference(value, path)
  defp validate_keyword("$dynamicRef", value, path), do: validate_reference(value, path)
  defp validate_keyword(_key, _value, _path), do: :ok

  @spec validate_reference(term(), path()) :: :ok | {:error, error()}
  defp validate_reference(value, path) when is_binary(value) do
    if String.starts_with?(value, "#") do
      :ok
    else
      {:error, {:invalid_reference, path}}
    end
  end

  defp validate_reference(_value, path), do: {:error, {:invalid_reference, path}}

  @spec validate_serialized_size(document()) :: :ok | {:error, error()}
  defp validate_serialized_size(document) do
    case Jason.encode_to_iodata(document) do
      {:ok, encoded} ->
        if IO.iodata_length(encoded) <= @max_serialized_bytes do
          :ok
        else
          {:error, {:size_limit_exceeded, []}}
        end

      {:error, _exception} ->
        {:error, {:invalid_json, [], :unsupported_value}}
    end
  end
end
