defmodule LeafcutterConnectors.Transport.HTTP.FinchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias LeafcutterConnectors.TestHTTPServer
  alias LeafcutterConnectors.Transport.HTTP
  alias LeafcutterConnectors.Transport.HTTP.{Error, Request, Response}
  alias LeafcutterConnectors.Transport.HTTP.Finch, as: FinchAdapter

  test "returns every well-formed HTTP status without retrying" do
    for status <- [204, 302, 401, 429, 503] do
      body = if status == 204, do: "", else: "status-body"

      server =
        start_server(fn _request, _attempt ->
          fixed_response(status, [{"location", "/next"}], body)
        end)

      assert {:ok, %Response{status: ^status, body: ^body}} =
               HTTP.request(request(TestHTTPServer.url(server)))

      assert TestHTTPServer.attempts(server) == 1
      TestHTTPServer.stop(server)
    end
  end

  test "preserves duplicate headers, raw body chunks, and trailers" do
    server =
      start_server(fn _request, _attempt ->
        {:chunks,
         [
           "HTTP/1.1 200 OK\r\n",
           "transfer-encoding: chunked\r\n",
           "x-repeat: first\r\n",
           "x-repeat: second\r\n",
           "trailer: x-trailer\r\n",
           "connection: close\r\n\r\n",
           "3\r\nabc\r\n",
           "3\r\ndef\r\n",
           "0\r\nx-trailer: first\r\nx-trailer: second\r\n\r\n"
         ]}
      end)

    assert {:ok, response} = HTTP.request(request(TestHTTPServer.url(server)))
    assert response.body == "abcdef"

    assert Enum.filter(response.headers, &match?({"x-repeat", _value}, &1)) == [
             {"x-repeat", "first"},
             {"x-repeat", "second"}
           ]

    assert response.trailers == [
             {"x-trailer", "first"},
             {"x-trailer", "second"}
           ]
  end

  test "halts when content-length exceeds the request limit" do
    server =
      start_server(fn _request, _attempt ->
        fixed_response(200, [{"content-length", "4"}], "data", add_length?: false)
      end)

    assert {:error, %Error{reason: :response_too_large}} =
             HTTP.request(
               request(TestHTTPServer.url(server), max_response_body_bytes: 3)
             )
  end

  test "halts when streamed chunks cross the request limit" do
    server =
      start_server(fn _request, _attempt ->
        {:chunks,
         [
           "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n",
           "3\r\nabc\r\n",
           "3\r\ndef\r\n",
           "0\r\n\r\n"
         ]}
      end)

    assert {:error, %Error{reason: :response_too_large}} =
             HTTP.request(
               request(TestHTTPServer.url(server), max_response_body_bytes: 5)
             )
  end

  test "applies the central hard maximum in addition to the request limit" do
    body = String.duplicate("x", 65)
    server = start_server(fn _request, _attempt -> fixed_response(200, [], body) end)

    assert {:error, %Error{reason: :response_too_large}} =
             HTTP.request(
               request(TestHTTPServer.url(server), max_response_body_bytes: 1_000)
             )
  end

  test "normalizes receive timeouts" do
    server =
      start_server(fn _request, _attempt ->
        receive do
          :release_timeout_request -> fixed_response(200, [], "late")
        end
      end)

    assert {:error, %Error{reason: :timeout}} =
             HTTP.request(
               request(TestHTTPServer.url(server),
                 receive_timeout_ms: 10,
                 request_timeout_ms: 500
               )
             )
  end

  test "normalizes the expected pool checkout exception" do
    test_process = self()

    server =
      start_server(fn _request, attempt ->
        send(test_process, {:request_held, attempt})

        receive do
          :release_pool_request -> fixed_response(200, [], "released")
        end
      end)

    first_request =
      Task.async(fn ->
        HTTP.request(
          request(TestHTTPServer.url(server),
            pool_timeout_ms: 500,
            receive_timeout_ms: 500,
            request_timeout_ms: 500
          )
        )
      end)

    assert_receive {:request_held, 1}, 500

    assert {:error, %Error{reason: :pool_timeout}} =
             HTTP.request(
               request(TestHTTPServer.url(server), pool_timeout_ms: 10)
             )

    send(server.pid, :release_pool_request)
    assert {:ok, %Response{body: "released"}} = Task.await(first_request, 1_000)
  end

  test "normalizes only recognized Finch errors to safe reasons" do
    secret = "raw-client-secret"

    cases = [
      {%Finch.TransportError{reason: :timeout}, :timeout},
      {%Finch.TransportError{reason: :nxdomain}, :dns},
      {%Finch.TransportError{reason: :econnrefused}, :connection},
      {%Finch.TransportError{reason: {:tls_alert, {:unknown_ca, secret}}}, :tls},
      {%Finch.HTTPError{reason: :invalid_status_line}, :protocol},
      {%Finch.Error{reason: :request_timeout}, :timeout},
      {%Finch.Error{reason: {:unclassified, secret}}, :transport_failure}
    ]

    for {client_error, expected_reason} <- cases do
      error = FinchAdapter.normalize_error(client_error)

      assert error == %Error{reason: expected_reason}
      refute inspect(error) =~ secret
    end
  end

  test "configures one finite shared HTTP/1 pool per origin" do
    assert {Finch, options} = FinchAdapter.child_spec()
    assert options[:name] == FinchAdapter.client_name()

    pool_options = options[:pools][:default]
    config = HTTP.config!()

    assert pool_options[:protocols] == [:http1]
    assert pool_options[:count] == 1
    assert pool_options[:size] == config.pool_size
    assert pool_options[:pool_max_idle_time] == config.pool_max_idle_time_ms

    assert pool_options[:conn_opts] == [
             transport_opts: [timeout: config.connect_timeout_ms]
           ]

    assert config.max_response_body_bytes == 64
  end

  test "reuses the same origin pool across paths and credentials" do
    server = start_server(fn _request, _attempt -> fixed_response(200, [], "ok") end)
    first_url = TestHTTPServer.url(server, "/first")
    second_url = TestHTTPServer.url(server, "/second")

    assert {:ok, %Response{}} =
             HTTP.request(request(first_url, headers: [{"authorization", "first-token"}]))

    pool = Finch.Pool.new(first_url)
    assert {:ok, first_pool_pid} = Finch.find_pool(FinchAdapter.client_name(), pool)

    assert {:ok, %Response{}} =
             HTTP.request(request(second_url, headers: [{"authorization", "second-token"}]))

    assert {:ok, second_pool_pid} =
             Finch.find_pool(FinchAdapter.client_name(), Finch.Pool.new(second_url))

    assert first_pool_pid == second_pool_pid
  end

  test "does not log request or response secrets" do
    server =
      start_server(fn _request, _attempt ->
        fixed_response(200, [], "response-secret")
      end)

    url = TestHTTPServer.url(server, "/private?cursor=query-secret")

    logs =
      capture_log(fn ->
        assert {:ok, %Response{body: "response-secret"}} =
                 HTTP.request(
                   request(url,
                     method: :post,
                     headers: [{"authorization", "header-secret"}],
                     body: "request-secret"
                   )
                 )
      end)

    refute logs =~ "/private"
    refute logs =~ "query-secret"
    refute logs =~ "header-secret"
    refute logs =~ "request-secret"
    refute logs =~ "response-secret"
  end

  defp start_server(handler) do
    server = TestHTTPServer.start(handler)
    on_exit(fn -> TestHTTPServer.stop(server) end)
    server
  end

  defp request(url, overrides \\ []) do
    struct!(
      Request,
      Keyword.merge(
        [
          method: :get,
          url: url,
          headers: [],
          body: nil,
          pool_timeout_ms: 500,
          receive_timeout_ms: 500,
          request_timeout_ms: 500,
          max_response_body_bytes: 64
        ],
        overrides
      )
    )
  end

  defp fixed_response(status, headers, body, options \\ []) do
    add_length? = Keyword.get(options, :add_length?, true)

    headers =
      if add_length? do
        [{"content-length", Integer.to_string(byte_size(body))} | headers]
      else
        headers
      end

    encoded_headers = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)

    [
      "HTTP/1.1 #{status} Status\r\n",
      encoded_headers,
      "connection: close\r\n\r\n",
      body
    ]
  end
end
