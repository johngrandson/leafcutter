defmodule Leafcutter.Catalog.Contracts.SchemaPolicyTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Catalog.Contracts.SchemaPolicy

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @max_serialized_bytes 1_048_576
  @max_nodes 10_000

  describe "validate/1 roots and JSON values" do
    test "preserves valid object and boolean documents" do
      object_document =
        schema(%{
          "properties" => %{
            "amount" => %{"type" => "number"},
            "metadata" => %{
              "examples" => [nil, true, false, 1, 1.5, "valid"]
            }
          }
        })

      for document <- [object_document, true, false] do
        assert {:ok, ^document} = SchemaPolicy.validate(document)
      end
    end

    test "rejects unsupported roots" do
      for document <- [nil, [], "object", 1, 1.0, %URI{}] do
        assert {:error, {:invalid_root, []}} = SchemaPolicy.validate(document)
      end
    end

    test "rejects non-string and invalid UTF-8 object keys at the object path" do
      assert {:error, {:invalid_json, ["properties"], :non_string_key}} =
               SchemaPolicy.validate(schema(%{"properties" => %{name: true}}))

      assert {:error, {:invalid_json, ["properties"], :invalid_utf8_key}} =
               SchemaPolicy.validate(schema(%{"properties" => %{<<255>> => true}}))
    end

    test "rejects invalid strings and unsupported values at deterministic paths" do
      assert {:error, {:invalid_json, ["properties", "name"], :invalid_utf8_string}} =
               SchemaPolicy.validate(schema(%{"properties" => %{"name" => <<255>>}}))

      assert {:error, {:invalid_json, ["a"], :unsupported_value}} =
               SchemaPolicy.validate(schema(%{"z" => self(), "a" => {:invalid}}))
    end
  end

  describe "validate/1 dialect" do
    test "requires the canonical Draft 2020-12 dialect for object roots" do
      assert {:error, {:invalid_dialect, ["$schema"]}} =
               SchemaPolicy.validate(%{"type" => "object"})

      assert {:error, {:invalid_dialect, ["$schema"]}} =
               SchemaPolicy.validate(%{
                 "$schema" => "http://json-schema.org/draft-07/schema#",
                 "type" => "object"
               })
    end

    test "uses the fixed dialect implicitly for boolean roots" do
      assert {:ok, true} = SchemaPolicy.validate(true)
      assert {:ok, false} = SchemaPolicy.validate(false)
    end
  end

  describe "validate/1 references and extensions" do
    test "accepts fragment-only refs and dynamic refs at any depth" do
      document =
        schema(%{
          "$defs" => %{
            "customer" => %{
              "$anchor" => "customer",
              "type" => "object"
            }
          },
          "$ref" => "#/$defs/customer",
          "allOf" => [%{"$dynamicRef" => "#customer"}]
        })

      assert {:ok, ^document} = SchemaPolicy.validate(document)
    end

    test "rejects relative, remote, module, and non-string references" do
      invalid_references = [
        "schema.json",
        "schema.json#/$defs/customer",
        "../schema.json",
        "https://example.test/schema",
        "jsv:module:Elixir.SomeSchema",
        true
      ]

      for reference <- invalid_references do
        assert {:error, {:invalid_reference, ["allOf", 0, "$ref"]}} =
                 SchemaPolicy.validate(schema(%{"allOf" => [%{"$ref" => reference}]}))
      end
    end

    test "rejects both JSV casting extensions at any depth" do
      for keyword <- ["jsv-cast", "x-jsv-cast"] do
        assert {:error, {:forbidden_keyword, ["allOf", 0, ^keyword]}} =
                 SchemaPolicy.validate(schema(%{"allOf" => [%{keyword => "string"}]}))
      end
    end
  end

  describe "validate/1 structural limits" do
    test "accepts depth 64 and rejects depth 65" do
      accepted = schema_with_nested_containers(63)
      rejected = schema_with_nested_containers(64)

      assert {:ok, ^accepted} = SchemaPolicy.validate(accepted)

      expected_path = ["nested" | List.duplicate(0, 63)]

      assert {:error, {:depth_limit_exceeded, ^expected_path}} =
               SchemaPolicy.validate(rejected)
    end

    test "accepts 10,000 nodes and rejects the 10,001st node" do
      accepted = schema_with_nodes(@max_nodes)
      rejected = schema_with_nodes(@max_nodes + 1)

      assert {:ok, ^accepted} = SchemaPolicy.validate(accepted)

      assert {:error, {:node_limit_exceeded, ["values", 9_997]}} =
               SchemaPolicy.validate(rejected)
    end

    test "accepts serialized sizes below and at 1 MiB" do
      for size <- [@max_serialized_bytes - 1, @max_serialized_bytes] do
        document = schema_with_serialized_size(size)

        assert byte_size(Jason.encode!(document)) == size
        assert {:ok, ^document} = SchemaPolicy.validate(document)
      end
    end

    test "rejects a serialized size above 1 MiB" do
      document = schema_with_serialized_size(@max_serialized_bytes + 1)

      assert byte_size(Jason.encode!(document)) == @max_serialized_bytes + 1

      assert {:error, {:size_limit_exceeded, []}} =
               SchemaPolicy.validate(document)
    end
  end

  defp schema(fields) do
    Map.put(fields, "$schema", @dialect)
  end

  defp schema_with_nested_containers(container_count) do
    nested =
      Enum.reduce(1..container_count, nil, fn _index, accumulator ->
        [accumulator]
      end)

    schema(%{"nested" => nested})
  end

  defp schema_with_nodes(node_count) do
    schema(%{"values" => List.duplicate(nil, node_count - 3)})
  end

  defp schema_with_serialized_size(serialized_size) do
    document = schema(%{"description" => ""})
    filler_size = serialized_size - byte_size(Jason.encode!(document))

    Map.put(document, "description", String.duplicate("a", filler_size))
  end
end
