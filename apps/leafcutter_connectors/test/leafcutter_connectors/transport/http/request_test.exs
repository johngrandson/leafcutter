defmodule LeafcutterConnectors.Transport.HTTP.RequestTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Transport.HTTP.Request

  test "accepts every ratified method and absolute HTTP URLs" do
    for method <- [:get, :head, :post, :put, :patch, :delete, :options] do
      assert Request.valid?(request(method: method))
    end

    assert Request.valid?(request(url: "http://api.example.test/items"))
    assert Request.valid?(request(url: "https://api.example.test/items?cursor=next"))
  end

  test "rejects invalid methods and URLs" do
    invalid_urls = [
      "/relative",
      "ftp://api.example.test/items",
      "http://",
      "https://user:secret@api.example.test/items",
      "https://api.example.test/items#fragment",
      "https://api.example.test/bad path",
      <<"https://api.example.test/", 255>>
    ]

    refute Request.valid?(request(method: :trace))

    refute Enum.any?(invalid_urls, fn url ->
             Request.valid?(request(url: url))
           end)
  end

  test "preserves ordered duplicate headers and validates raw bodies" do
    headers = [{"x-value", "first"}, {"x-value", "second"}]

    assert Request.valid?(request(headers: headers, body: nil))
    assert Request.valid?(request(headers: headers, body: <<0, 1, 2>>))

    refute Request.valid?(request(headers: [{"X-Value", "value"}]))
    refute Request.valid?(request(headers: [{"bad header", "value"}]))
    refute Request.valid?(request(headers: [{"x-value", "bad\r\nvalue"}]))
    refute Request.valid?(request(headers: [{"x-value", "bad\0value"}]))
    refute Request.valid?(request(headers: [{{:not, :binary}, "value"}]))
    refute Request.valid?(request(headers: [{"x-value", "value"} | :invalid_tail]))
    refute Request.valid?(request(body: {:not, :binary}))
  end

  test "requires positive finite timeouts and body limits" do
    for field <- [
          :pool_timeout_ms,
          :receive_timeout_ms,
          :request_timeout_ms,
          :max_response_body_bytes
        ],
        invalid <- [0, -1, 1.0, :infinity, nil] do
      refute Request.valid?(request([{field, invalid}]))
    end
  end

  test "redacts path, query, headers, body, and invalid userinfo" do
    inspected =
      inspect(
        request(
          url: "https://api.example.test/private?cursor=query-secret",
          headers: [{"authorization", "header-secret"}],
          body: "body-secret"
        )
      )

    assert inspected =~ "method: :get"
    assert inspected =~ ~s(origin: "https://api.example.test")
    assert inspected =~ "headers: :redacted"
    assert inspected =~ "body: :redacted"
    refute inspected =~ "/private"
    refute inspected =~ "query-secret"
    refute inspected =~ "header-secret"
    refute inspected =~ "body-secret"

    invalid = inspect(request(url: "https://userinfo-secret@api.example.test/private"))
    refute invalid =~ "userinfo-secret"
    refute invalid =~ "/private"
  end

  defp request(overrides \\ []) do
    struct!(
      Request,
      Keyword.merge(
        [
          method: :get,
          url: "https://api.example.test/items",
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
end
