defmodule LeafcutterConnectors.Transport.HTTP.ResponseTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Transport.HTTP.Response

  test "accepts complete responses across every status class" do
    for status <- [100, 204, 302, 401, 429, 503, 599] do
      assert Response.valid?(response(status: status))
    end
  end

  test "preserves ordered duplicate headers and trailers" do
    response =
      response(
        headers: [{"x-value", "first"}, {"x-value", "second"}],
        trailers: [{"x-trailer", "first"}, {"x-trailer", "second"}]
      )

    assert Response.valid?(response)
    assert Enum.map(response.headers, &elem(&1, 1)) == ["first", "second"]
    assert Enum.map(response.trailers, &elem(&1, 1)) == ["first", "second"]
  end

  test "rejects invalid status, headers, trailers, and bodies" do
    refute Response.valid?(response(status: 99))
    refute Response.valid?(response(status: 600))
    refute Response.valid?(response(headers: [{"X-Value", "value"}]))
    refute Response.valid?(response(headers: [{"bad header", "value"}]))
    refute Response.valid?(response(headers: [{"x-value", "bad\nvalue"}]))
    refute Response.valid?(response(headers: [{"x-value", "value"} | :invalid_tail]))
    refute Response.valid?(response(trailers: [{"x-trailer", "bad\0value"}]))
    refute Response.valid?(response(body: nil))
  end

  test "inspection exposes only counts and byte size" do
    inspected =
      inspect(
        response(
          headers: [{"authorization", "header-secret"}],
          body: "body-secret",
          trailers: [{"x-secret", "trailer-secret"}]
        )
      )

    assert inspected =~ "status: 200"
    assert inspected =~ "header_count: 1"
    assert inspected =~ "body_bytes: 11"
    assert inspected =~ "trailer_count: 1"
    refute inspected =~ "header-secret"
    refute inspected =~ "body-secret"
    refute inspected =~ "trailer-secret"
  end

  defp response(overrides) do
    struct!(
      Response,
      Keyword.merge(
        [status: 200, headers: [], body: "", trailers: []],
        overrides
      )
    )
  end
end
