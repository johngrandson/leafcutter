defmodule LeafcutterConnectors.Transport.HTTP.Finch do
  @moduledoc """
  Finch-backed HTTP/1 adapter with finite timeouts and bounded response buffering.
  """

  @behaviour LeafcutterConnectors.Transport.HTTP.Adapter

  alias Finch, as: Client
  alias LeafcutterConnectors.Transport.HTTP
  alias LeafcutterConnectors.Transport.HTTP.{Error, Request, Response}

  @client_name __MODULE__.Client
  @response_header_name ~r/\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
  @pool_timeout_message "Finch was unable to provide a connection within the timeout"
  @dns_reasons [:nxdomain, :nodata, :eai_again, :eai_fail, :eai_noname]
  @connection_reasons [
    :closed,
    :econnaborted,
    :econnrefused,
    :econnreset,
    :ehostdown,
    :ehostunreach,
    :enetdown,
    :enetunreach,
    :enotconn,
    :epipe,
    :eshutdown
  ]
  @finch_connection_reasons [
    :connection_closed,
    :connection_dead,
    :connection_not_ready,
    :connection_process_went_down,
    :could_not_connect,
    :disconnected,
    :read_only
  ]

  @type accumulator :: %{
          body_bytes: non_neg_integer(),
          body_chunks: [binary()],
          failure: Error.reason() | nil,
          headers: [Response.header()],
          headers_seen?: boolean(),
          limit: pos_integer(),
          method: Request.method(),
          status: integer() | nil,
          trailers: [Response.header()]
        }

  @doc false
  @spec child_spec() :: {module(), keyword()}
  def child_spec do
    config = HTTP.config!()

    {Client,
     name: @client_name,
     pools: %{
       default: [
         protocols: [:http1],
         count: 1,
         size: config.pool_size,
         conn_opts: [transport_opts: [timeout: config.connect_timeout_ms]],
         pool_max_idle_time: config.pool_max_idle_time_ms
       ]
     }}
  end

  @doc false
  @spec client_name() :: atom()
  def client_name, do: @client_name

  @impl true
  def request(%Request{} = request) do
    if Request.valid?(request) do
      perform_request(request)
    else
      {:error, %Error{reason: :invalid_request}}
    end
  rescue
    exception in RuntimeError ->
      if pool_timeout_exception?(exception, __STACKTRACE__) do
        {:error, %Error{reason: :pool_timeout}}
      else
        reraise exception, __STACKTRACE__
      end
  end

  @doc false
  @spec normalize_error(Client.error()) :: Error.t()
  def normalize_error(%Client.TransportError{reason: reason}) do
    %Error{reason: normalize_transport_reason(reason)}
  end

  def normalize_error(%Client.HTTPError{}), do: %Error{reason: :protocol}

  def normalize_error(%Client.Error{reason: :request_timeout}) do
    %Error{reason: :timeout}
  end

  def normalize_error(%Client.Error{reason: reason}) when reason in @finch_connection_reasons do
    %Error{reason: :connection}
  end

  def normalize_error(%Client.Error{}), do: %Error{reason: :transport_failure}

  @spec perform_request(Request.t()) :: HTTP.result()
  defp perform_request(request) do
    config = HTTP.config!()
    limit = min(request.max_response_body_bytes, config.max_response_body_bytes)

    finch_request =
      Client.build(request.method, request.url, request.headers, request.body)

    options = [
      pool_timeout: request.pool_timeout_ms,
      receive_timeout: request.receive_timeout_ms,
      request_timeout: request.request_timeout_ms
    ]

    accumulator = %{
      body_bytes: 0,
      body_chunks: [],
      failure: nil,
      headers: [],
      headers_seen?: false,
      limit: limit,
      method: request.method,
      status: nil,
      trailers: []
    }

    finch_request
    |> Client.stream_while(@client_name, accumulator, &handle_entry/2, options)
    |> normalize_stream_result()
  end

  @spec handle_entry(
          {:status, integer()}
          | {:headers, [{binary(), binary()}]}
          | {:data, binary()}
          | {:trailers, [{binary(), binary()}]},
          accumulator()
        ) :: {:cont, accumulator()} | {:halt, accumulator()}
  defp handle_entry({:status, status}, accumulator) when is_integer(status) do
    {:cont,
     %{
       accumulator
       | status: status,
         headers: [],
         headers_seen?: false,
         body_chunks: [],
         body_bytes: 0,
         trailers: [],
         failure: nil
     }}
  end

  defp handle_entry({:status, _status}, accumulator), do: protocol_failure(accumulator)

  defp handle_entry({:headers, headers}, %{headers_seen?: false} = accumulator) do
    with {:ok, normalized_headers} <- normalize_headers(headers) do
      accumulator = %{
        accumulator
        | headers: normalized_headers,
          headers_seen?: true
      }

      if content_length_over_limit?(normalized_headers, accumulator) do
        response_too_large(accumulator)
      else
        {:cont, accumulator}
      end
    else
      :error -> protocol_failure(accumulator)
    end
  end

  defp handle_entry({:headers, headers}, accumulator) do
    store_trailers(headers, accumulator)
  end

  defp handle_entry({:data, data}, %{headers_seen?: true} = accumulator)
       when is_binary(data) do
    body_bytes = accumulator.body_bytes + byte_size(data)

    if body_bytes > accumulator.limit do
      response_too_large(%{accumulator | body_bytes: body_bytes})
    else
      {:cont,
       %{
         accumulator
         | body_bytes: body_bytes,
           body_chunks: [data | accumulator.body_chunks]
       }}
    end
  end

  defp handle_entry({:data, _data}, accumulator), do: protocol_failure(accumulator)

  defp handle_entry({:trailers, headers}, %{headers_seen?: true} = accumulator) do
    store_trailers(headers, accumulator)
  end

  defp handle_entry({:trailers, _headers}, accumulator), do: protocol_failure(accumulator)

  @spec store_trailers(term(), accumulator()) ::
          {:cont, accumulator()} | {:halt, accumulator()}
  defp store_trailers(headers, accumulator) do
    case normalize_headers(headers) do
      {:ok, normalized_headers} ->
        {:cont,
         %{accumulator | trailers: accumulator.trailers ++ normalized_headers}}

      :error ->
        protocol_failure(accumulator)
    end
  end

  @spec normalize_stream_result(
          {:ok, accumulator()} | {:error, Client.error(), accumulator()}
        ) :: HTTP.result()
  defp normalize_stream_result({:ok, %{failure: reason}}) when not is_nil(reason) do
    {:error, %Error{reason: reason}}
  end

  defp normalize_stream_result({:ok, accumulator}) do
    build_response(accumulator)
  end

  defp normalize_stream_result({:error, _client_error, %{failure: reason}})
       when not is_nil(reason) do
    {:error, %Error{reason: reason}}
  end

  defp normalize_stream_result({:error, client_error, _accumulator}) do
    {:error, normalize_error(client_error)}
  end

  @spec build_response(accumulator()) :: HTTP.result()
  defp build_response(%{status: status, headers_seen?: true} = accumulator)
       when is_integer(status) do
    response = %Response{
      status: status,
      headers: accumulator.headers,
      body: accumulator.body_chunks |> Enum.reverse() |> IO.iodata_to_binary(),
      trailers: accumulator.trailers
    }

    if Response.valid?(response) do
      {:ok, response}
    else
      {:error, %Error{reason: :protocol}}
    end
  end

  defp build_response(_accumulator), do: {:error, %Error{reason: :protocol}}

  @spec normalize_headers(term()) :: {:ok, [Response.header()]} | :error
  defp normalize_headers(headers), do: normalize_headers(headers, [])

  @spec normalize_headers(term(), [Response.header()]) ::
          {:ok, [Response.header()]} | :error
  defp normalize_headers([], normalized), do: {:ok, Enum.reverse(normalized)}

  defp normalize_headers([{name, value} | headers], normalized)
       when is_binary(name) and is_binary(value) do
    if Regex.match?(@response_header_name, name) and
         not String.contains?(value, ["\r", "\n", "\0"]) do
      header = {String.downcase(name, :ascii), value}
      normalize_headers(headers, [header | normalized])
    else
      :error
    end
  end

  defp normalize_headers(_headers, _normalized), do: :error

  @spec content_length_over_limit?([Response.header()], accumulator()) :: boolean()
  defp content_length_over_limit?(headers, accumulator) do
    body_expected?(accumulator.method, accumulator.status) and
      Enum.any?(headers, fn
        {"content-length", value} -> content_length_over?(value, accumulator.limit)
        _header -> false
      end)
  end

  @spec body_expected?(Request.method(), integer() | nil) :: boolean()
  defp body_expected?(:head, _status), do: false
  defp body_expected?(_method, status) when status in 100..199, do: false
  defp body_expected?(_method, status) when status in [204, 304], do: false
  defp body_expected?(_method, _status), do: true

  @spec content_length_over?(binary(), pos_integer()) :: boolean()
  defp content_length_over?(value, limit) do
    case Integer.parse(value) do
      {length, ""} when length >= 0 -> length > limit
      _other -> false
    end
  end

  @spec response_too_large(accumulator()) :: {:halt, accumulator()}
  defp response_too_large(accumulator) do
    {:halt, %{accumulator | failure: :response_too_large, body_chunks: []}}
  end

  @spec protocol_failure(accumulator()) :: {:halt, accumulator()}
  defp protocol_failure(accumulator) do
    {:halt, %{accumulator | failure: :protocol, body_chunks: []}}
  end

  @spec normalize_transport_reason(term()) :: Error.reason()
  defp normalize_transport_reason(:timeout), do: :timeout
  defp normalize_transport_reason(reason) when reason in @dns_reasons, do: :dns

  defp normalize_transport_reason(reason) when reason in @connection_reasons,
    do: :connection

  defp normalize_transport_reason(:protocol_not_negotiated), do: :tls
  defp normalize_transport_reason({:bad_alpn_protocol, _protocol}), do: :tls
  defp normalize_transport_reason({:tls_alert, _alert}), do: :tls
  defp normalize_transport_reason({:bad_cert, _reason}), do: :tls
  defp normalize_transport_reason({:certificate, _reason}), do: :tls
  defp normalize_transport_reason(_reason), do: :transport_failure

  @spec pool_timeout_exception?(RuntimeError.t(), list()) :: boolean()
  defp pool_timeout_exception?(exception, stacktrace) do
    String.starts_with?(exception.message, @pool_timeout_message) and
      Enum.any?(stacktrace, fn
        {Client.HTTP1.Pool, :request, _arity_or_args, _location} -> true
        _entry -> false
      end)
  end
end
