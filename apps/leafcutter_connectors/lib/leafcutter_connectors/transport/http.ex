defmodule LeafcutterConnectors.Transport.HTTP do
  @moduledoc """
  Bounded synchronous HTTP transport for executable connector operations.

  The default request path delegates to the supervised Finch adapter. The
  two-argument variant accepts only a code-level adapter module and validates
  both sides of the adapter contract.
  """

  alias LeafcutterConnectors.Transport.HTTP.{Error, Finch, Request, Response}

  @default_config [
    pool_size: 10,
    connect_timeout_ms: 5_000,
    pool_max_idle_time_ms: 300_000,
    max_response_body_bytes: 8_388_608
  ]

  @typedoc "A successful response or sanitized transport failure."
  @type result :: {:ok, Response.t()} | {:error, Error.t()}

  @doc "Performs exactly one HTTP network attempt with the Finch adapter."
  @spec request(Request.t()) :: result()
  def request(request), do: request(request, Finch)

  @doc "Performs exactly one attempt with a code-level HTTP adapter module."
  @spec request(Request.t(), module()) :: result()
  def request(%Request{} = request, adapter) when is_atom(adapter) do
    if Request.valid?(request) do
      request_with_adapter(request, adapter)
    else
      invalid_request()
    end
  end

  def request(_request, adapter) when is_atom(adapter), do: invalid_request()

  @doc false
  @spec config!() :: %{
          pool_size: pos_integer(),
          connect_timeout_ms: pos_integer(),
          pool_max_idle_time_ms: pos_integer(),
          max_response_body_bytes: pos_integer()
        }
  def config! do
    configured = Application.get_env(:leafcutter_connectors, __MODULE__, [])

    unless Keyword.keyword?(configured) do
      raise ArgumentError, "HTTP transport configuration must be a keyword list"
    end

    unknown_keys = Keyword.keys(configured) -- Keyword.keys(@default_config)

    if unknown_keys != [] do
      raise ArgumentError,
            "unknown HTTP transport configuration keys: #{inspect(unknown_keys)}"
    end

    config = Keyword.merge(@default_config, configured)

    %{
      pool_size: positive_integer!(config, :pool_size),
      connect_timeout_ms: positive_integer!(config, :connect_timeout_ms),
      pool_max_idle_time_ms: positive_integer!(config, :pool_max_idle_time_ms),
      max_response_body_bytes: positive_integer!(config, :max_response_body_bytes)
    }
  end

  @spec request_with_adapter(Request.t(), module()) :: result()
  defp request_with_adapter(request, adapter) do
    case adapter.request(request) do
      {:ok, %Response{} = response} = result ->
        if Response.valid?(response), do: result, else: contract_violation!()

      {:error, %Error{} = error} = result ->
        if Error.valid?(error), do: result, else: contract_violation!()

      _other ->
        contract_violation!()
    end
  end

  @spec positive_integer!(keyword(), atom()) :: pos_integer()
  defp positive_integer!(config, key) do
    value = Keyword.fetch!(config, key)

    if is_integer(value) and value > 0 do
      value
    else
      raise ArgumentError, "HTTP transport #{key} must be a positive integer"
    end
  end

  @spec invalid_request() :: {:error, Error.t()}
  defp invalid_request, do: {:error, %Error{reason: :invalid_request}}

  @spec contract_violation!() :: no_return()
  defp contract_violation! do
    raise ArgumentError, "HTTP adapter returned a value outside its contract"
  end
end
