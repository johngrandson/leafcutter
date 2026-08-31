defmodule LeafcutterConnectors.OperationTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Error

  describe "JSON-compatible values" do
    test "accepts JSON scalars, arrays, and objects" do
      values = [
        nil,
        true,
        false,
        42,
        -1.5,
        "value",
        [],
        [1, nil, %{"nested" => [true]}],
        %{"object" => %{"value" => 1}}
      ]

      assert Enum.all?(values, &Operation.json_value?/1)
      assert Operation.json_object?(%{"items" => values})
    end

    test "rejects non-JSON terms and invalid UTF-8" do
      invalid_utf8 = <<255>>

      values = [
        :atom,
        %{atom_key: "value"},
        %URI{scheme: "https"},
        {:tuple, "value"},
        self(),
        make_ref(),
        fn -> :ok end,
        [1 | 2],
        invalid_utf8,
        %{invalid_utf8 => "value"}
      ]

      refute Enum.any?(values, &Operation.json_value?/1)
    end

    test "reserves nil for cursor start and completion" do
      refute Operation.cursor?(nil)
      assert Operation.cursor?(0)
      assert Operation.cursor?(%{"page" => 2})
    end
  end

  describe "normalized errors" do
    test "accepts every ratified category" do
      categories = [
        :validation,
        :authentication,
        :rate_limited,
        :timeout,
        :temporary,
        :permanent
      ]

      assert Enum.all?(categories, fn category ->
               Error.valid?(error(category: category))
             end)
    end

    test "requires a stable non-blank UTF-8 code and safe metadata" do
      refute Error.valid?(error(code: ""))
      refute Error.valid?(error(code: "  \n"))
      refute Error.valid?(error(code: <<255>>))
      refute Error.valid?(error(message: <<255>>))
      refute Error.valid?(error(metadata: %{unsafe: "value"}))
      refute Error.valid?(error(category: :unknown))
    end

    test "limits retry hints to rate-limited and temporary failures" do
      assert Error.valid?(error(category: :rate_limited, retry_after_ms: 0))
      assert Error.valid?(error(category: :temporary, retry_after_ms: 500))

      refute Error.valid?(error(category: :timeout, retry_after_ms: 500))
      refute Error.valid?(error(category: :validation, retry_after_ms: 500))
      refute Error.valid?(error(category: :temporary, retry_after_ms: -1))
      refute Error.valid?(error(category: :temporary, retry_after_ms: 1.0))
    end
  end

  defp error(overrides) do
    struct!(Error, Keyword.merge([category: :temporary, code: "temporary"], overrides))
  end
end
