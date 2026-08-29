defmodule Leafcutter.Catalog.Contracts.PayloadPolicy do
  @moduledoc false

  alias Leafcutter.Catalog.Contracts.ValidationError

  @typedoc "A segment in a deterministic path through a JSON payload."
  @type path_segment :: String.t() | non_neg_integer()

  @typedoc "A deterministic root-relative path through a JSON payload."
  @type path :: [path_segment()]

  @typedoc "The concrete reason a payload value is not JSON-compatible."
  @type json_error_detail ::
          :non_string_key
          | :invalid_utf8_key
          | :invalid_utf8_string
          | :unencodable_number
          | :unsupported_value

  @typedoc "An internal JSON payload policy error."
  @type error :: {path(), json_error_detail()}

  @doc false
  @spec validate(term()) :: {:ok, term()} | {:error, error()}
  def validate(payload) do
    case validate_json(payload, []) do
      :ok -> {:ok, payload}
      {:error, _error} = failure -> failure
    end
  end

  @doc false
  @spec error_details(error()) :: ValidationError.details()
  def error_details({path, detail}) do
    %{
      "instanceLocation" => json_pointer(path),
      "kind" => Atom.to_string(detail)
    }
  end

  @spec validate_json(term(), path()) :: :ok | {:error, error()}
  defp validate_json(%_{} = _value, path) do
    {:error, {path, :unsupported_value}}
  end

  defp validate_json(value, path) when is_map(value) do
    with :ok <- validate_object_keys(value, path) do
      value
      |> Enum.sort_by(fn {key, _nested_value} -> key end)
      |> Enum.reduce_while(:ok, fn {key, nested_value}, :ok ->
        continue_validation(nested_value, path ++ [key])
      end)
    end
  end

  defp validate_json([], _path), do: :ok

  defp validate_json([head | tail], path) do
    validate_list(head, tail, path, 0)
  end

  defp validate_json(value, _path) when is_nil(value) or is_boolean(value), do: :ok

  defp validate_json(value, path) when is_integer(value) or is_float(value) do
    case Jason.encode(value) do
      {:ok, _encoded} -> :ok
      {:error, _exception} -> {:error, {path, :unencodable_number}}
    end
  end

  defp validate_json(value, path) when is_binary(value) do
    if String.valid?(value) do
      :ok
    else
      {:error, {path, :invalid_utf8_string}}
    end
  end

  defp validate_json(_value, path) do
    {:error, {path, :unsupported_value}}
  end

  @spec validate_list(term(), term(), path(), non_neg_integer()) ::
          :ok | {:error, error()}
  defp validate_list(head, tail, path, index) do
    case validate_json(head, path ++ [index]) do
      :ok -> validate_list_tail(tail, path, index + 1)
      {:error, _error} = failure -> failure
    end
  end

  @spec validate_list_tail(term(), path(), non_neg_integer()) ::
          :ok | {:error, error()}
  defp validate_list_tail([], _path, _index), do: :ok

  defp validate_list_tail([head | tail], path, index) do
    validate_list(head, tail, path, index)
  end

  defp validate_list_tail(_improper_tail, path, index) do
    {:error, {path ++ [index], :unsupported_value}}
  end

  @spec continue_validation(term(), path()) ::
          {:cont, :ok} | {:halt, {:error, error()}}
  defp continue_validation(value, path) do
    case validate_json(value, path) do
      :ok -> {:cont, :ok}
      {:error, _error} = failure -> {:halt, failure}
    end
  end

  @spec validate_object_keys(map(), path()) :: :ok | {:error, error()}
  defp validate_object_keys(value, path) do
    keys = Map.keys(value)

    cond do
      Enum.any?(keys, fn key -> not is_binary(key) end) ->
        {:error, {path, :non_string_key}}

      Enum.any?(keys, fn key -> not String.valid?(key) end) ->
        {:error, {path, :invalid_utf8_key}}

      true ->
        :ok
    end
  end

  @spec json_pointer(path()) :: String.t()
  defp json_pointer([]), do: "#"

  defp json_pointer(path) do
    "#" <>
      Enum.map_join(path, "", fn segment ->
        "/" <> escape_pointer_segment(segment)
      end)
  end

  @spec escape_pointer_segment(path_segment()) :: String.t()
  defp escape_pointer_segment(segment) when is_integer(segment), do: Integer.to_string(segment)

  defp escape_pointer_segment(segment) do
    segment
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end
end
