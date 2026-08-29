defmodule Leafcutter.Catalog.Contracts.SchemaBuilderTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Catalog.Contracts.SchemaBuilder

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @validation_options [cast: false, cast_formats: false]

  describe "build/1" do
    test "builds object and boolean documents" do
      assert {:ok, object_root} = SchemaBuilder.build(schema(%{"type" => "object"}))
      assert {:ok, true_root} = SchemaBuilder.build(true)
      assert {:ok, false_root} = SchemaBuilder.build(false)

      assert {:ok, %{}} = JSV.validate(%{}, object_root, @validation_options)
      assert {:ok, "payload"} = JSV.validate("payload", true_root, @validation_options)
      assert {:error, _error} = JSV.validate("payload", false_root, @validation_options)
    end

    test "builds and resolves fragment-only references inside the document" do
      document =
        schema(%{
          "$defs" => %{"name" => %{"type" => "string"}},
          "$ref" => "#/$defs/name"
        })

      assert {:ok, root} = SchemaBuilder.build(document)
      assert {:ok, "Leafcutter"} = JSV.validate("Leafcutter", root, @validation_options)
      assert {:error, _error} = JSV.validate(42, root, @validation_options)
    end

    test "enables the default format validators" do
      document = schema(%{"type" => "string", "format" => "email"})

      assert {:ok, root} = SchemaBuilder.build(document)
      assert {:ok, "joe.bloggs@example.com"} =
               JSV.validate("joe.bloggs@example.com", root, @validation_options)

      assert {:error, _error} =
               JSV.validate("2962", root, @validation_options)
    end

    test "returns the deterministic policy failure before JSV resolution" do
      document = schema(%{"$ref" => "https://example.test/schema"})

      assert {:error, {:policy_failed, {:invalid_reference, ["$ref"]}}} =
               SchemaBuilder.build(document)
    end

    test "hides JSV build errors behind a deterministic failure" do
      document = schema(%{"type" => "bad type"})

      assert {:error, :schema_build_failed} = SchemaBuilder.build(document)
    end
  end

  defp schema(fields) do
    Map.put(fields, "$schema", @dialect)
  end
end
