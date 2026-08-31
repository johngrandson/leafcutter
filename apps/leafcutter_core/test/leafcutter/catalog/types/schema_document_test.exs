defmodule Leafcutter.Catalog.Types.SchemaDocumentTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Catalog.Types.SchemaDocument

  @object_schema %{
    "$schema" => "https://json-schema.org/draft/2020-12/schema",
    "type" => "object"
  }
  @valid_roots [@object_schema, true, false]
  @invalid_roots [nil, [], "object", 1, 1.0, %URI{}]

  describe "type/0" do
    test "uses the map primitive for JSONB persistence" do
      assert SchemaDocument.type() == :map
    end
  end

  describe "cast/1" do
    test "preserves object and boolean roots" do
      for value <- @valid_roots do
        assert {:ok, ^value} = SchemaDocument.cast(value)
      end
    end

    test "rejects unsupported roots and structs" do
      for value <- @invalid_roots do
        assert :error == SchemaDocument.cast(value)
      end
    end
  end

  describe "dump/1" do
    test "preserves object and boolean roots" do
      for value <- @valid_roots do
        assert {:ok, ^value} = SchemaDocument.dump(value)
      end
    end

    test "rejects unsupported roots and structs" do
      for value <- @invalid_roots do
        assert :error == SchemaDocument.dump(value)
      end
    end
  end

  describe "load/1" do
    test "preserves object, boolean, and legacy nil roots" do
      for value <- [nil | @valid_roots] do
        assert {:ok, ^value} = SchemaDocument.load(value)
      end
    end

    test "rejects unsupported persisted roots and structs" do
      for value <- List.delete(@invalid_roots, nil) do
        assert :error == SchemaDocument.load(value)
      end
    end
  end
end
