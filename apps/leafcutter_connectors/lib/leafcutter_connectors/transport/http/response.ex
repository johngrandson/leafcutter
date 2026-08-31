defmodule LeafcutterConnectors.Transport.HTTP.Response do
  @moduledoc """
  Complete raw response returned by one HTTP transport attempt.

  Inspection exposes only status and bounded size information. Header, trailer,
  and body contents are always redacted.
  """

  @header_name ~r/\A[!#$%&'*+\-.^_`|~0-9a-z]+\z/

  @typedoc "One ordered normalized HTTP header."
  @type header :: {binary(), binary()}

  @enforce_keys [:status, :headers, :body]
  defstruct [:status, :headers, :body, trailers: []]

  @type t :: %__MODULE__{
          status: 100..599,
          headers: [header()],
          body: binary(),
          trailers: [header()]
        }

  @doc "Returns whether a response is complete and satisfies the HTTP contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = response) do
    is_integer(response.status) and response.status in 100..599 and
      valid_headers?(response.headers) and
      is_binary(response.body) and
      valid_headers?(response.trailers)
  end

  def valid?(_response), do: false

  @spec valid_headers?(term()) :: boolean()
  defp valid_headers?([]), do: true

  defp valid_headers?([{name, value} | headers]) do
    valid_header?(name, value) and valid_headers?(headers)
  end

  defp valid_headers?(_headers), do: false

  @spec valid_header?(term(), term()) :: boolean()
  defp valid_header?(name, value) when is_binary(name) and is_binary(value) do
    Regex.match?(@header_name, name) and
      not String.contains?(value, ["\r", "\n", "\0"])
  end

  defp valid_header?(_name, _value), do: false
end

defimpl Inspect, for: LeafcutterConnectors.Transport.HTTP.Response do
  import Inspect.Algebra

  @impl true
  def inspect(response, opts) do
    concat([
      "%LeafcutterConnectors.Transport.HTTP.Response{status: ",
      to_doc(safe_status(response.status), opts),
      ", headers: :redacted, header_count: ",
      to_doc(safe_length(response.headers), opts),
      ", body: :redacted, body_bytes: ",
      to_doc(safe_byte_size(response.body), opts),
      ", trailers: :redacted, trailer_count: ",
      to_doc(safe_length(response.trailers), opts),
      "}"
    ])
  end

  @spec safe_status(term()) :: 100..599 | :invalid
  defp safe_status(status) when is_integer(status) and status in 100..599, do: status
  defp safe_status(_status), do: :invalid

  @spec safe_length(term()) :: non_neg_integer() | :invalid
  defp safe_length(list), do: safe_length(list, 0)

  @spec safe_length(term(), non_neg_integer()) :: non_neg_integer() | :invalid
  defp safe_length([], length), do: length
  defp safe_length([_item | items], length), do: safe_length(items, length + 1)
  defp safe_length(_list, _length), do: :invalid

  @spec safe_byte_size(term()) :: non_neg_integer() | :invalid
  defp safe_byte_size(body) when is_binary(body), do: byte_size(body)
  defp safe_byte_size(_body), do: :invalid
end
