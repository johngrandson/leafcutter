defmodule LeafcutterRuntime.HTTPPassthroughConformanceTest do
  use Leafcutter.DataCase, async: false

  alias Leafcutter.Catalog.Contracts
  alias Leafcutter.Catalog.Contracts.ValidationError

  alias LeafcutterConnectors.Operation.Error, as: OperationError
  alias LeafcutterConnectors.Operation.Read
  alias LeafcutterConnectors.Operation.Read.Invocation, as: ReadInvocation
  alias LeafcutterConnectors.Operation.Read.Result, as: ReadResult
  alias LeafcutterConnectors.Operation.Write
  alias LeafcutterConnectors.Operation.Write.Invocation, as: WriteInvocation
  alias LeafcutterConnectors.Operation.Write.Item
  alias LeafcutterConnectors.Operation.Write.ItemResult
  alias LeafcutterConnectors.Operation.Write.Result, as: WriteResult
  alias LeafcutterConnectors.TestHTTPServer
  alias LeafcutterConnectors.Transport.HTTP

  alias LeafcutterHTTPPassthroughFixture, as: Fixture
  alias LeafcutterHTTPPassthroughFixture.Package

  @response_body_limit 1_048_576

  setup do
    previous_config = Application.fetch_env(:leafcutter_connectors, HTTP)
    configured = Application.get_env(:leafcutter_connectors, HTTP, [])

    Application.put_env(
      :leafcutter_connectors,
      HTTP,
      Keyword.put(configured, :max_response_body_bytes, @response_body_limit)
    )

    on_exit(fn -> restore_http_config(previous_config) end)
  end

  test "crosses validated and transformed records from one HTTP source to one destination" do
    test_process = self()
    records = source_records()

    source_server =
      start_server(fn request, _attempt ->
        send(test_process, {:source_request, request})
        json_response(200, %{"data" => records, "next_cursor" => nil})
      end)

    destination_server =
      start_server(fn request, _attempt ->
        send(test_process, {:destination_request, request})

        json_response(200, %{
          "results" => [
            %{
              "ref" => "customer:customer-001",
              "status" => "success",
              "destination_id" => "contact-9001"
            },
            %{
              "ref" => "customer:customer-002",
              "status" => "success",
              "destination_id" => "contact-9002"
            }
          ]
        })
      end)

    validators = publish_validators!()

    assert {:ok, trace} =
             execute_once(
               TestHTTPServer.url(source_server, "/records"),
               TestHTTPServer.url(destination_server, "/contacts"),
               validators
             )

    assert Read.valid_return?({:ok, trace.read_result}, trace.read_invocation)
    assert trace.read_result == %ReadResult{records: records, next_cursor: nil}

    [first_payload, second_payload] = Enum.map(records, &destination_payload/1)

    assert trace.write_invocation.items == [
             %Item{
               ref: "customer:customer-001",
               payload: first_payload
             },
             %Item{
               ref: "customer:customer-002",
               payload: second_payload
             }
           ]

    assert Write.valid_return?({:ok, trace.write_result}, trace.write_invocation)

    assert trace.write_result.results == [
             %ItemResult{ref: "customer:customer-001", outcome: {:ok, "contact-9001"}},
             %ItemResult{ref: "customer:customer-002", outcome: {:ok, "contact-9002"}}
           ]

    assert_receive {:source_request, source_request}
    assert String.starts_with?(source_request, "GET /records HTTP/1.1\r\n")
    assert source_request =~ ~r/\r\nauthorization: Bearer source-token\r\n/i

    assert_receive {:destination_request, destination_request}
    assert String.starts_with?(destination_request, "POST /contacts HTTP/1.1\r\n")
    assert destination_request =~ ~r/\r\nauthorization: Bearer destination-token\r\n/i

    assert request_body(destination_request) == %{
             "items" => [
               %{
                 "ref" => "customer:customer-001",
                 "payload" => first_payload
               },
               %{
                 "ref" => "customer:customer-002",
                 "payload" => second_payload
               }
             ]
           }

    assert TestHTTPServer.attempts(source_server) == 1
    assert TestHTTPServer.attempts(destination_server) == 1
  end

  test "stops before destination HTTP when a source record violates its contract" do
    invalid_record =
      source_records()
      |> hd()
      |> Map.put("email", "invalid-email")

    source_server =
      start_server(fn _request, _attempt ->
        json_response(200, %{"data" => [invalid_record], "next_cursor" => nil})
      end)

    destination_server =
      start_server(fn _request, _attempt ->
        json_response(200, %{"results" => []})
      end)

    assert {:error, %ValidationError{reason: :schema_violation}} =
             execute_once(
               TestHTTPServer.url(source_server, "/records"),
               TestHTTPServer.url(destination_server, "/contacts"),
               publish_validators!()
             )

    assert TestHTTPServer.attempts(source_server) == 1
    assert TestHTTPServer.attempts(destination_server) == 0
  end

  test "preserves a complete ordered destination result with mixed outcomes" do
    records = source_records()

    source_server =
      start_server(fn _request, _attempt ->
        json_response(200, %{"data" => records, "next_cursor" => nil})
      end)

    destination_server =
      start_server(fn _request, _attempt ->
        json_response(200, %{
          "results" => [
            %{
              "ref" => "customer:customer-001",
              "status" => "success",
              "destination_id" => "contact-9001"
            },
            %{
              "ref" => "customer:customer-002",
              "status" => "rejected",
              "vendor_code" => "duplicate_email"
            }
          ]
        })
      end)

    assert {:ok, trace} =
             execute_once(
               TestHTTPServer.url(source_server, "/records"),
               TestHTTPServer.url(destination_server, "/contacts"),
               publish_validators!()
             )

    assert Write.valid_return?({:ok, trace.write_result}, trace.write_invocation)

    assert [
             %ItemResult{ref: "customer:customer-001", outcome: {:ok, "contact-9001"}},
             %ItemResult{
               ref: "customer:customer-002",
               outcome:
                 {:error,
                  %OperationError{
                    category: :validation,
                    code: "destination_rejected"
                  } = item_error}
             }
           ] = trace.write_result.results

    refute inspect(item_error) =~ "duplicate_email"
    assert TestHTTPServer.attempts(destination_server) == 1
  end

  test "normalizes source rate limiting without retrying or calling the destination" do
    source_server =
      start_server(fn _request, _attempt ->
        json_response(
          429,
          %{"error" => "raw-rate-limit-body"},
          [{"retry-after", "2"}]
        )
      end)

    destination_server =
      start_server(fn _request, _attempt ->
        json_response(200, %{"results" => []})
      end)

    assert {:error,
            %OperationError{
              category: :rate_limited,
              code: "source_rate_limited",
              retry_after_ms: 2_000
            } = error} =
             execute_once(
               TestHTTPServer.url(source_server, "/records"),
               TestHTTPServer.url(destination_server, "/contacts"),
               publish_validators!()
             )

    refute inspect(error) =~ "raw-rate-limit-body"
    assert TestHTTPServer.attempts(source_server) == 1
    assert TestHTTPServer.attempts(destination_server) == 0
  end

  defp execute_once(source_url, destination_url, validators) do
    {"customers", source_module} = Package.source()
    [{"contacts", destination_module}] = Package.destinations()

    read_invocation = %ReadInvocation{
      config: %{"url" => source_url},
      credentials: %{"token" => "source-token"},
      cursor: nil
    }

    with {:ok, %ReadResult{} = read_result} <- source_module.read(read_invocation),
         true <- Read.valid_return?({:ok, read_result}, read_invocation),
         {:ok, items} <- build_items(read_result.records, validators),
         write_invocation = %WriteInvocation{
           config: %{"url" => destination_url},
           credentials: %{"token" => "destination-token"},
           items: items
         },
         {:ok, %WriteResult{} = write_result} <- destination_module.write(write_invocation),
         true <- Write.valid_return?({:ok, write_result}, write_invocation) do
      {:ok,
       %{
         read_invocation: read_invocation,
         read_result: read_result,
         write_invocation: write_invocation,
         write_result: write_result
       }}
    else
      {:error, error} -> {:error, error}
      false -> {:error, :operation_contract_violation}
    end
  end

  defp build_items([_record | _records] = records, validators) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, items} ->
      with {:ok, %{"id" => id} = validated_record} <-
             Contracts.validate(validators.source, record),
           {:ok, destination_payload} <- Fixture.transform(validated_record),
           {:ok, validated_payload} <-
             Contracts.validate(validators.destination, destination_payload) do
        item = %Item{
          ref: "customer:" <> id,
          payload: validated_payload
        }

        {:cont, {:ok, [item | items]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, error} -> {:error, error}
    end
  end

  defp build_items([], _validators), do: {:error, :empty_source_page}

  defp publish_validators! do
    suffix = System.unique_integer([:positive])

    {:ok, source_contract} =
      Contracts.create(%{name: "HTTP passthrough source contract #{suffix}"})

    {:ok, destination_contract} =
      Contracts.create(%{name: "HTTP passthrough destination contract #{suffix}"})

    {:ok, source_version} =
      Contracts.publish_version(source_contract.id, %{
        version: "1",
        schema: Fixture.source_schema()
      })

    {:ok, destination_version} =
      Contracts.publish_version(destination_contract.id, %{
        version: "1",
        schema: Fixture.destination_schema()
      })

    {:ok, source_validator} = Contracts.compile(source_version.id)
    {:ok, destination_validator} = Contracts.compile(destination_version.id)

    %{source: source_validator, destination: destination_validator}
  end

  defp source_records do
    [
      %{
        "id" => "customer-001",
        "full_name" => "Ana Silva",
        "email" => "ana@example.test",
        "active" => true,
        "updated_at" => "2026-08-31T10:30:00Z"
      },
      %{
        "id" => "customer-002",
        "full_name" => "Bruno Costa",
        "email" => "bruno@example.test",
        "active" => false,
        "updated_at" => "2026-08-31T10:35:00Z"
      }
    ]
  end

  defp destination_payload(record) do
    {:ok, payload} = Fixture.transform(record)
    payload
  end

  defp start_server(handler) do
    server = TestHTTPServer.start(handler)
    on_exit(fn -> TestHTTPServer.stop(server) end)
    server
  end

  defp json_response(status, payload, headers \\ []) do
    body = JSON.encode!(payload)

    encoded_headers =
      Enum.map(headers, fn {name, value} ->
        [name, ": ", value, "\r\n"]
      end)

    [
      "HTTP/1.1 ",
      Integer.to_string(status),
      " Status\r\n",
      "content-type: application/json\r\n",
      "content-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      encoded_headers,
      "connection: close\r\n\r\n",
      body
    ]
  end

  defp request_body(request) do
    [_headers, body] = String.split(request, "\r\n\r\n", parts: 2)
    JSON.decode!(body)
  end

  defp restore_http_config({:ok, config}) do
    Application.put_env(:leafcutter_connectors, HTTP, config)
  end

  defp restore_http_config(:error) do
    Application.delete_env(:leafcutter_connectors, HTTP)
  end
end
