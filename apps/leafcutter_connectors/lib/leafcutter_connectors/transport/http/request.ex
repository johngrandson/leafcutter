defmodule LeafcutterConnectors.Transport.HTTP.Request do
  @moduledoc """
  Raw bounded input for one synchronous HTTP transport attempt.

  Inspection exposes only the method, origin, and finite limits. Request path,
  query, headers, and body are always redacted.
  """

  @methods [:get, :head, :post, :put, :patch, :delete, :options]
  @header_name ~r/\A[!#$%&'*+\-.^_`|~0-9a-z]+\z/
  @invalid_url_byte ~r/[\x00-\x20\x7F]/

  @typedoc "An HTTP method accepted by the transport."
  @type method :: :get | :head | :post | :put | :patch | :delete | :options

  @typedoc "One ordered raw HTTP header."
  @type header :: {binary(), binary()}

  @enforce_keys [
    :method,
    :url,
    :headers,
    :body,
    :pool_timeout_ms,
    :receive_timeout_ms,
    :request_timeout_ms,
    :max_response_body_bytes
  ]
  defstruct [
    :method,
    :url,
    :headers,
    :body,
    :pool_timeout_ms,
    :receive_timeout_ms,
    :request_timeout_ms,
    :max_response_body_bytes
  ]

  @type t :: %__MODULE__{
          method: method(),
          url: String.t(),
          headers: [header()],
          body: binary() | nil,
          pool_timeout_ms: pos_integer(),
          receive_timeout_ms: pos_integer(),
          request_timeout_ms: pos_integer(),
          max_response_body_bytes: pos_integer()
        }

  @doc "Returns whether a request satisfies the bounded HTTP contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    method?(request.method) and
      valid_url?(request.url) and
      valid_headers?(request.headers) and
      (is_nil(request.body) or is_binary(request.body)) and
      positive_integer?(request.pool_timeout_ms) and
      positive_integer?(request.receive_timeout_ms) and
      positive_integer?(request.request_timeout_ms) and
      positive_integer?(request.max_response_body_bytes)
  end

  def valid?(_request), do: false

  @doc false
  @spec method?(term()) :: boolean()
  def method?(method), do: method in @methods

  @doc false
  @spec safe_origin(term()) :: String.t() | :invalid
  def safe_origin(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        sanitized_uri = %URI{uri | userinfo: nil, path: nil, query: nil, fragment: nil}
        URI.to_string(sanitized_uri)

      _other ->
        :invalid
    end
  end

  def safe_origin(_url), do: :invalid

  @spec valid_url?(term()) :: boolean()
  defp valid_url?(url) when is_binary(url) do
    String.valid?(url) and
      not Regex.match?(@invalid_url_byte, url) and
      valid_parsed_url?(URI.new(url))
  end

  defp valid_url?(_url), do: false

  @spec valid_parsed_url?({:ok, URI.t()} | {:error, term()}) :: boolean()
  defp valid_parsed_url?(
         {:ok,
          %URI{
            scheme: scheme,
            host: host,
            userinfo: nil,
            fragment: nil
          }}
       ) do
    scheme in ["http", "https"] and is_binary(host) and host != ""
  end

  defp valid_parsed_url?(_result), do: false

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

  @spec positive_integer?(term()) :: boolean()
  defp positive_integer?(value), do: is_integer(value) and value > 0
end

defimpl Inspect, for: LeafcutterConnectors.Transport.HTTP.Request do
  import Inspect.Algebra

  alias LeafcutterConnectors.Transport.HTTP.Request

  @impl true
  def inspect(request, opts) do
    concat([
      "%LeafcutterConnectors.Transport.HTTP.Request{method: ",
      to_doc(safe_method(request.method), opts),
      ", origin: ",
      to_doc(Request.safe_origin(request.url), opts),
      ", headers: :redacted, body: :redacted, pool_timeout_ms: ",
      to_doc(safe_limit(request.pool_timeout_ms), opts),
      ", receive_timeout_ms: ",
      to_doc(safe_limit(request.receive_timeout_ms), opts),
      ", request_timeout_ms: ",
      to_doc(safe_limit(request.request_timeout_ms), opts),
      ", max_response_body_bytes: ",
      to_doc(safe_limit(request.max_response_body_bytes), opts),
      "}"
    ])
  end

  @spec safe_method(term()) :: Request.method() | :invalid
  defp safe_method(method) do
    if Request.method?(method), do: method, else: :invalid
  end

  @spec safe_limit(term()) :: pos_integer() | :invalid
  defp safe_limit(value) when is_integer(value) and value > 0, do: value
  defp safe_limit(_value), do: :invalid
end
