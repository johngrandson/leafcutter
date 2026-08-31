defmodule LeafcutterHTTPPassthroughFixture do
  @moduledoc false

  alias LeafcutterConnectors.Operation.Error

  @dialect "https://json-schema.org/draft/2020-12/schema"

  @spec source_schema() :: map()
  def source_schema do
    %{
      "$schema" => @dialect,
      "title" => "HTTP passthrough source customer",
      "type" => "object",
      "required" => ["id", "full_name", "email", "active", "updated_at"],
      "additionalProperties" => false,
      "properties" => %{
        "id" => %{"type" => "string", "minLength" => 1},
        "full_name" => %{"type" => "string", "minLength" => 1},
        "email" => %{"type" => "string", "format" => "email"},
        "active" => %{"type" => "boolean"},
        "updated_at" => %{"type" => "string", "format" => "date-time"}
      }
    }
  end

  @spec destination_schema() :: map()
  def destination_schema do
    %{
      "$schema" => @dialect,
      "title" => "HTTP passthrough destination contact",
      "type" => "object",
      "required" => ["external_id", "name", "email", "enabled", "source_updated_at"],
      "additionalProperties" => false,
      "properties" => %{
        "external_id" => %{"type" => "string", "minLength" => 1},
        "name" => %{"type" => "string", "minLength" => 1},
        "email" => %{"type" => "string", "format" => "email"},
        "enabled" => %{"type" => "boolean"},
        "source_updated_at" => %{"type" => "string", "format" => "date-time"}
      }
    }
  end

  @spec transform(map()) :: {:ok, map()} | {:error, Error.t()}
  def transform(%{
        "id" => id,
        "full_name" => full_name,
        "email" => email,
        "active" => active,
        "updated_at" => updated_at
      }) do
    {:ok,
     %{
       "external_id" => id,
       "name" => full_name,
       "email" => email,
       "enabled" => active,
       "source_updated_at" => updated_at
     }}
  end

  def transform(_record) do
    {:error, %Error{category: :validation, code: "unsupported_source_record"}}
  end
end

defmodule LeafcutterHTTPPassthroughFixture.Source do
  @moduledoc false

  @behaviour LeafcutterConnectors.Operation.Read

  alias LeafcutterConnectors.Operation.Error, as: OperationError
  alias LeafcutterConnectors.Operation.Read.Invocation
  alias LeafcutterConnectors.Operation.Read.Result
  alias LeafcutterConnectors.Transport.HTTP
  alias LeafcutterConnectors.Transport.HTTP.Error, as: HTTPError
  alias LeafcutterConnectors.Transport.HTTP.Request
  alias LeafcutterConnectors.Transport.HTTP.Response

  @request_timeout_ms 2_000
  @response_body_limit 1_048_576

  @impl true
  def read(%Invocation{} = invocation) do
    with true <- Invocation.valid?(invocation),
         {:ok, url} <- source_url(invocation.config, invocation.cursor) do
      case HTTP.request(request(url, invocation.credentials)) do
        {:ok, %Response{} = response} -> decode_response(response, invocation)
        {:error, %HTTPError{} = error} -> {:error, transport_error(error)}
      end
    else
      _invalid ->
        {:error, %OperationError{category: :validation, code: "invalid_read_invocation"}}
    end
  end

  defp source_url(%{"url" => url}, nil) when is_binary(url), do: {:ok, url}
  defp source_url(_config, _cursor), do: :error

  defp request(url, credentials) do
    %Request{
      method: :get,
      url: url,
      headers: [{"accept", "application/json"} | authorization_headers(credentials)],
      body: nil,
      pool_timeout_ms: @request_timeout_ms,
      receive_timeout_ms: @request_timeout_ms,
      request_timeout_ms: @request_timeout_ms,
      max_response_body_bytes: @response_body_limit
    }
  end

  defp authorization_headers(%{"token" => token})
       when is_binary(token) and token != "" do
    [{"authorization", "Bearer " <> token}]
  end

  defp authorization_headers(_credentials), do: []

  defp decode_response(%Response{status: status, body: body}, invocation)
       when status in 200..299 do
    with {:ok, %{"data" => records, "next_cursor" => next_cursor}} <- JSON.decode(body),
         result = %Result{records: records, next_cursor: next_cursor},
         true <- Result.valid_for?(result, invocation) do
      {:ok, result}
    else
      _invalid ->
        {:error, %OperationError{category: :permanent, code: "source_invalid_response"}}
    end
  end

  defp decode_response(%Response{status: 429, headers: headers}, _invocation) do
    {:error,
     %OperationError{
       category: :rate_limited,
       code: "source_rate_limited",
       retry_after_ms: retry_after_ms(headers)
     }}
  end

  defp decode_response(%Response{}, _invocation) do
    {:error, %OperationError{category: :permanent, code: "source_unexpected_status"}}
  end

  defp retry_after_ms(headers) do
    with {"retry-after", value} <- List.keyfind(headers, "retry-after", 0),
         {seconds, ""} when seconds >= 0 <- Integer.parse(value) do
      seconds * 1_000
    else
      _missing_or_invalid -> nil
    end
  end

  defp transport_error(%HTTPError{reason: :timeout}) do
    %OperationError{category: :timeout, code: "source_http_timeout"}
  end

  defp transport_error(%HTTPError{reason: :invalid_request}) do
    %OperationError{category: :validation, code: "source_invalid_http_request"}
  end

  defp transport_error(%HTTPError{}) do
    %OperationError{category: :temporary, code: "source_http_unavailable"}
  end
end

defmodule LeafcutterHTTPPassthroughFixture.Destination do
  @moduledoc false

  @behaviour LeafcutterConnectors.Operation.Write

  alias LeafcutterConnectors.Operation.Error, as: OperationError
  alias LeafcutterConnectors.Operation.Write.Invocation
  alias LeafcutterConnectors.Operation.Write.Item
  alias LeafcutterConnectors.Operation.Write.ItemResult
  alias LeafcutterConnectors.Operation.Write.Result
  alias LeafcutterConnectors.Transport.HTTP
  alias LeafcutterConnectors.Transport.HTTP.Error, as: HTTPError
  alias LeafcutterConnectors.Transport.HTTP.Request
  alias LeafcutterConnectors.Transport.HTTP.Response

  @request_timeout_ms 2_000
  @response_body_limit 1_048_576

  @impl true
  def write(%Invocation{} = invocation) do
    with true <- Invocation.valid?(invocation),
         {:ok, url} <- destination_url(invocation.config) do
      case HTTP.request(request(url, invocation.credentials, invocation.items)) do
        {:ok, %Response{} = response} -> decode_response(response, invocation)
        {:error, %HTTPError{} = error} -> {:error, transport_error(error)}
      end
    else
      _invalid ->
        {:error, %OperationError{category: :validation, code: "invalid_write_invocation"}}
    end
  end

  defp destination_url(%{"url" => url}) when is_binary(url), do: {:ok, url}
  defp destination_url(_config), do: :error

  defp request(url, credentials, items) do
    body =
      JSON.encode!(%{
        "items" =>
          Enum.map(items, fn %Item{} = item ->
            %{"ref" => item.ref, "payload" => item.payload}
          end)
      })

    %Request{
      method: :post,
      url: url,
      headers: [
        {"accept", "application/json"},
        {"content-type", "application/json"}
        | authorization_headers(credentials)
      ],
      body: body,
      pool_timeout_ms: @request_timeout_ms,
      receive_timeout_ms: @request_timeout_ms,
      request_timeout_ms: @request_timeout_ms,
      max_response_body_bytes: @response_body_limit
    }
  end

  defp authorization_headers(%{"token" => token})
       when is_binary(token) and token != "" do
    [{"authorization", "Bearer " <> token}]
  end

  defp authorization_headers(_credentials), do: []

  defp decode_response(%Response{status: status, body: body}, invocation)
       when status in 200..299 do
    with {:ok, %{"results" => raw_results}} <- JSON.decode(body),
         {:ok, item_results} <- decode_item_results(raw_results),
         result = %Result{results: item_results},
         true <- Result.valid_for?(result, invocation) do
      {:ok, result}
    else
      _invalid ->
        {:error, %OperationError{category: :permanent, code: "destination_invalid_response"}}
    end
  end

  defp decode_response(%Response{}, _invocation) do
    {:error, %OperationError{category: :permanent, code: "destination_unexpected_status"}}
  end

  defp decode_item_results(results) when is_list(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, decoded} ->
      case decode_item_result(result) do
        {:ok, item_result} -> {:cont, {:ok, [item_result | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end

  defp decode_item_results(_results), do: :error

  defp decode_item_result(%{
         "ref" => ref,
         "status" => "success",
         "destination_id" => destination_id
       }) do
    {:ok, %ItemResult{ref: ref, outcome: {:ok, destination_id}}}
  end

  defp decode_item_result(%{"ref" => ref, "status" => "rejected"}) do
    {:ok,
     %ItemResult{
       ref: ref,
       outcome: {:error, %OperationError{category: :validation, code: "destination_rejected"}}
     }}
  end

  defp decode_item_result(_result), do: :error

  defp transport_error(%HTTPError{reason: :timeout}) do
    %OperationError{category: :timeout, code: "destination_http_timeout"}
  end

  defp transport_error(%HTTPError{reason: :invalid_request}) do
    %OperationError{category: :validation, code: "destination_invalid_http_request"}
  end

  defp transport_error(%HTTPError{}) do
    %OperationError{category: :temporary, code: "destination_http_unavailable"}
  end
end

defmodule LeafcutterHTTPPassthroughFixture.Package do
  @moduledoc false

  use LeafcutterConnectors.Package,
    manifest: Path.expand("../manifest.json", __DIR__),
    source: {"customers", LeafcutterHTTPPassthroughFixture.Source},
    destinations: [{"contacts", LeafcutterHTTPPassthroughFixture.Destination}]
end
