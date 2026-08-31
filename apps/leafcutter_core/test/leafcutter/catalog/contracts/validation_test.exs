defmodule Leafcutter.Catalog.Contracts.ValidationTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Catalog.Contracts
  alias Leafcutter.Catalog.Contracts.SchemaBuilder
  alias Leafcutter.Catalog.Contracts.ValidationError
  alias Leafcutter.Catalog.Contracts.Validator

  @contract_version_id "00000000-0000-0000-0000-000000000001"
  @dialect "https://json-schema.org/draft/2020-12/schema"

  describe "validate/2" do
    test "accepts scalar and composite JSON payloads with one reusable true validator" do
      validator = validator!(true)

      payloads = [
        nil,
        true,
        false,
        "payload",
        42,
        1.0,
        [],
        [1, "two", nil],
        %{},
        %{"nested" => [%{"number" => 1.0}]}
      ]

      for payload <- payloads do
        assert {:ok, validated_payload} = Contracts.validate(validator, payload)
        assert validated_payload === payload
      end
    end

    test "discards JSV numeric normalization and returns the exact original payload" do
      validator = validator!(schema(%{"type" => "integer"}))
      payload = 123.0

      assert {:ok, validated_payload} = Contracts.validate(validator, payload)
      assert validated_payload === payload
      assert is_float(validated_payload)
    end

    test "returns a schema violation for a false schema" do
      validator = validator!(false)

      assert {:error,
              %ValidationError{
                contract_version_id: @contract_version_id,
                reason: :schema_violation,
                details: details
              }} = Contracts.validate(validator, %{"payload" => "private-value"})

      assert public_json?(details)
      assert "boolean_schema" in collect_kinds(details)
      refute contains_key?(details, "message")
      refute contains_value?(details, "private-value")
    end

    test "rejects non-JSON Elixir terms before JSV with deterministic paths" do
      validator = validator!(true)

      invalid_payloads = [
        {
          %{
            "z" => self(),
            "a/b~c" => [nil, {:do_not_leak, "private-value"}]
          },
          %{
            "instanceLocation" => "#/a~1b~0c/1",
            "kind" => "unsupported_value"
          }
        },
        {
          %{"nested" => %{1 => "value"}},
          %{
            "instanceLocation" => "#/nested",
            "kind" => "non_string_key"
          }
        },
        {
          %{"nested" => <<255>>},
          %{
            "instanceLocation" => "#/nested",
            "kind" => "invalid_utf8_string"
          }
        },
        {
          %{<<255>> => "value"},
          %{
            "instanceLocation" => "#",
            "kind" => "invalid_utf8_key"
          }
        },
        {
          %{"items" => [1 | :improper_tail]},
          %{
            "instanceLocation" => "#/items/1",
            "kind" => "unsupported_value"
          }
        }
      ]

      for {payload, expected_details} <- invalid_payloads do
        assert {:error,
                %ValidationError{
                  contract_version_id: @contract_version_id,
                  reason: :invalid_json,
                  details: ^expected_details
                }} = Contracts.validate(validator, payload)
      end
    end

    test "normalizes schema violations into ordered payload-safe JSON details" do
      validator =
        validator!(
          schema(%{
            "anyOf" => [
              %{
                "type" => "object",
                "properties" => %{"z" => %{"type" => "integer"}}
              },
              %{
                "type" => "object",
                "properties" => %{"a" => %{"type" => "integer"}}
              }
            ]
          })
        )

      payload = %{
        "z" => "private-z",
        "a" => "private-a"
      }

      assert {:error,
              %ValidationError{
                contract_version_id: @contract_version_id,
                reason: :schema_violation,
                details: first_details
              }} = Contracts.validate(validator, payload)

      assert {:error, %ValidationError{details: second_details}} =
               Contracts.validate(validator, payload)

      assert first_details == second_details
      assert public_json?(first_details)
      refute contains_key?(first_details, "message")
      refute contains_value?(first_details, "private-z")
      refute contains_value?(first_details, "private-a")

      assert "anyOf" in collect_kinds(first_details)
      assert "type" in collect_kinds(first_details)

      units = collect_units(first_details)

      assert units != []

      assert Enum.all?(units, fn unit ->
               is_binary(unit["instanceLocation"]) and
                 is_binary(unit["schemaLocation"]) and
                 is_binary(unit["evaluationPath"])
             end)

      assert_units_ordered(first_details)
    end
  end

  @spec validator!(map() | boolean()) :: Validator.t()
  defp validator!(document) do
    {:ok, root} = SchemaBuilder.build(document)
    Validator.new(@contract_version_id, root)
  end

  @spec schema(map()) :: map()
  defp schema(fields), do: Map.put(fields, "$schema", @dialect)

  @spec public_json?(term()) :: boolean()
  defp public_json?(value) when is_nil(value) or is_boolean(value), do: true
  defp public_json?(value) when is_binary(value), do: String.valid?(value)
  defp public_json?(value) when is_integer(value) or is_float(value), do: true
  defp public_json?(value) when is_list(value), do: Enum.all?(value, &public_json?/1)

  defp public_json?(value) when is_map(value) do
    not is_struct(value) and
      Enum.all?(value, fn {key, nested_value} ->
        is_binary(key) and public_json?(nested_value)
      end)
  end

  defp public_json?(_value), do: false

  @spec contains_key?(term(), String.t()) :: boolean()
  defp contains_key?(value, key) when is_map(value) do
    Map.has_key?(value, key) or
      Enum.any?(Map.values(value), &contains_key?(&1, key))
  end

  defp contains_key?(value, key) when is_list(value) do
    Enum.any?(value, &contains_key?(&1, key))
  end

  defp contains_key?(_value, _key), do: false

  @spec contains_value?(term(), term()) :: boolean()
  defp contains_value?(value, expected) when is_map(value) do
    Enum.any?(Map.values(value), &contains_value?(&1, expected))
  end

  defp contains_value?(value, expected) when is_list(value) do
    Enum.any?(value, &contains_value?(&1, expected))
  end

  defp contains_value?(value, expected), do: value === expected

  @spec collect_kinds(term()) :: [String.t()]
  defp collect_kinds(value) when is_map(value) do
    own_kinds =
      case Map.fetch(value, "kind") do
        {:ok, kind} -> [kind]
        :error -> []
      end

    own_kinds ++ Enum.flat_map(Map.values(value), &collect_kinds/1)
  end

  defp collect_kinds(value) when is_list(value), do: Enum.flat_map(value, &collect_kinds/1)
  defp collect_kinds(_value), do: []

  @spec collect_units(term()) :: [map()]
  defp collect_units(
         %{
           "valid" => valid,
           "instanceLocation" => instance_location,
           "schemaLocation" => schema_location,
           "evaluationPath" => evaluation_path
         } = value
       )
       when is_boolean(valid) and is_binary(instance_location) and
              is_binary(schema_location) and is_binary(evaluation_path) do
    [value | Enum.flat_map(Map.values(value), &collect_units/1)]
  end

  defp collect_units(value) when is_map(value) do
    Enum.flat_map(Map.values(value), &collect_units/1)
  end

  defp collect_units(value) when is_list(value), do: Enum.flat_map(value, &collect_units/1)
  defp collect_units(_value), do: []

  @spec assert_units_ordered(term()) :: :ok
  defp assert_units_ordered(%{"details" => units} = value) when is_list(units) do
    sort_keys = Enum.map(units, &unit_sort_key/1)

    assert sort_keys == Enum.sort(sort_keys)

    Enum.each(Map.values(value), &assert_units_ordered/1)
  end

  defp assert_units_ordered(value) when is_map(value) do
    case Map.fetch(value, "errors") do
      {:ok, errors} ->
        error_sort_keys =
          Enum.map(errors, fn error ->
            {Map.fetch!(error, "kind"), Map.get(error, "details", [])}
          end)

        assert error_sort_keys == Enum.sort(error_sort_keys)

      :error ->
        :ok
    end

    Enum.each(Map.values(value), &assert_units_ordered/1)
  end

  defp assert_units_ordered(value) when is_list(value) do
    Enum.each(value, &assert_units_ordered/1)
  end

  defp assert_units_ordered(_value), do: :ok

  @spec unit_sort_key(map()) :: tuple()
  defp unit_sort_key(unit) do
    {
      Map.fetch!(unit, "instanceLocation"),
      Map.fetch!(unit, "schemaLocation"),
      Map.fetch!(unit, "evaluationPath")
    }
  end
end
