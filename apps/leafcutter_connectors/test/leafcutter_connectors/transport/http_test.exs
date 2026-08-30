defmodule LeafcutterConnectors.Transport.HTTPTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Transport.HTTP
  alias LeafcutterConnectors.Transport.HTTP.{Error, Request, Response}

  defmodule ValidAdapter do
    @moduledoc false

    @behaviour LeafcutterConnectors.Transport.HTTP.Adapter

    alias LeafcutterConnectors.Transport.HTTP.Response

    @impl true
    def request(_request) do
      {:ok, %Response{status: 503, headers: [], body: "unavailable"}}
    end
  end

  defmodule ErrorAdapter do
    @moduledoc false

    @behaviour LeafcutterConnectors.Transport.HTTP.Adapter

    alias LeafcutterConnectors.Transport.HTTP.Error

    @impl true
    def request(_request), do: {:error, %Error{reason: :timeout}}
  end

  defmodule MalformedAdapter do
    @moduledoc false

    def request(_request), do: {:ok, :not_a_response}
  end

  defmodule InvalidResponseAdapter do
    @moduledoc false

    alias LeafcutterConnectors.Transport.HTTP.Response

    def request(_request), do: {:ok, %Response{status: 700, headers: [], body: ""}}
  end

  defmodule DefectAdapter do
    @moduledoc false

    def request(_request), do: raise("adapter defect")
  end

  test "accepts valid adapter responses and sanitized errors" do
    assert {:ok, %Response{status: 503}} = HTTP.request(request(), ValidAdapter)
    assert {:error, %Error{reason: :timeout}} = HTTP.request(request(), ErrorAdapter)
  end

  test "rejects invalid input before invoking an adapter" do
    invalid_request = request(pool_timeout_ms: 0)

    assert {:error, %Error{reason: :invalid_request}} =
             HTTP.request(invalid_request, DefectAdapter)
  end

  test "raises on malformed adapter output without exposing the raw value" do
    message = "HTTP adapter returned a value outside its contract"

    assert_raise ArgumentError, message, fn ->
      HTTP.request(request(), MalformedAdapter)
    end

    assert_raise ArgumentError, message, fn ->
      HTTP.request(request(), InvalidResponseAdapter)
    end
  end

  test "leaves unexpected adapter exceptions visible as defects" do
    assert_raise RuntimeError, "adapter defect", fn ->
      HTTP.request(request(), DefectAdapter)
    end
  end

  test "sanitized errors never inspect an invalid raw reason" do
    secret = "raw-error-secret"
    inspected = inspect(%Error{reason: secret})

    assert inspected =~ "reason: :invalid"
    refute inspected =~ secret
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
