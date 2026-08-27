defmodule Leafcutter.Executions.RunSnapshot.DefinitionV1Test do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Leafcutter.Executions.RunSnapshot.DefinitionV1

  describe "validate/1" do
    test "normalizes a valid atom-keyed definition to canonical JSON keys" do
      attrs =
        valid_attrs()
        |> put_in(
          [:source, :connection, :config],
          %{
            region: "eu-west",
            nested: %{enabled: true},
            tags: ["primary", 1]
          }
        )
        |> Map.put(:effective_config, %{batch: %{size: 100}})

      assert {:ok, definition} = DefinitionV1.validate(attrs)

      assert Map.keys(definition) |> Enum.sort() ==
               [
                 "destinations",
                 "effective_config",
                 "package_version_id",
                 "source"
               ]

      assert definition["package_version_id"] == attrs.package_version_id
      assert definition["source"]["ref"] == "source"

      assert definition["source"]["connection"]["config"] == %{
               "region" => "eu-west",
               "nested" => %{"enabled" => true},
               "tags" => ["primary", 1]
             }

      assert definition["effective_config"] == %{
               "batch" => %{"size" => 100}
             }

      refute Map.has_key?(definition, "id")
      refute Map.has_key?(definition, "format_version")
    end

    test "accepts string keys at every structural level" do
      attrs = stringify_object_keys(valid_attrs())

      assert {:ok, definition} = DefinitionV1.validate(attrs)

      assert definition["source"]["connection"]["secret_version_id"] == nil
      assert length(definition["destinations"]) == 1
    end

    test "preserves destination order without assigning priority semantics" do
      attrs = valid_attrs()
      first_destination = hd(attrs.destinations)

      second_destination =
        first_destination
        |> Map.put(:ref, "warehouse")
        |> Map.put(:contract_version_id, Ecto.UUID.generate())

      attrs =
        Map.put(
          attrs,
          :destinations,
          [first_destination, second_destination]
        )

      assert {:ok, definition} = DefinitionV1.validate(attrs)

      assert Enum.map(definition["destinations"], & &1["ref"]) == [
               "crm",
               "warehouse"
             ]
    end

    test "rejects a non-map root and missing root fields" do
      assert {:error, non_map_changeset} = DefinitionV1.validate([])
      assert validation_present?(non_map_changeset, :map)

      assert {:error, missing_fields_changeset} = DefinitionV1.validate(%{})

      refute missing_fields_changeset.valid?
      assert Keyword.has_key?(missing_fields_changeset.errors, :package_version_id)
      assert Keyword.has_key?(missing_fields_changeset.errors, :effective_config)
      assert Keyword.has_key?(missing_fields_changeset.errors, :source)
      assert Keyword.has_key?(missing_fields_changeset.errors, :destinations)
    end

    test "rejects malformed UUIDs throughout the definition" do
      attrs = valid_attrs()

      invalid_definitions = [
        Map.put(attrs, :package_version_id, "not-a-uuid"),
        put_in(attrs, [:source, :contract_version_id], "not-a-uuid"),
        put_in(attrs, [:source, :connection, :id], "not-a-uuid"),
        put_in(
          attrs,
          [:source, :connection, :secret_version_id],
          "not-a-uuid"
        )
      ]

      for invalid_definition <- invalid_definitions do
        assert {:error, changeset} = DefinitionV1.validate(invalid_definition)
        refute changeset.valid?
      end
    end

    test "requires exactly one source and at least one destination" do
      attrs = valid_attrs()

      invalid_definitions = [
        Map.delete(attrs, :source),
        Map.put(attrs, :source, [attrs.source]),
        Map.put(attrs, :destinations, [])
      ]

      for invalid_definition <- invalid_definitions do
        assert {:error, changeset} = DefinitionV1.validate(invalid_definition)
        refute changeset.valid?
      end
    end

    test "requires non-empty and mutually unique endpoint references" do
      attrs = valid_attrs()
      destination = hd(attrs.destinations)

      duplicate_destination =
        destination
        |> Map.put(:contract_version_id, Ecto.UUID.generate())

      invalid_definitions = [
        put_in(attrs, [:source, :ref], "   "),
        put_in(attrs, [:destinations, Access.at(0), :ref], "source"),
        Map.put(
          attrs,
          :destinations,
          [destination, duplicate_destination]
        )
      ]

      for invalid_definition <- invalid_definitions do
        assert {:error, changeset} = DefinitionV1.validate(invalid_definition)
        refute changeset.valid?
      end
    end

    test "requires connection and effective configuration to be JSON objects" do
      attrs = valid_attrs()

      config_with_colliding_keys = %{
        :region => "eu-west",
        "region" => "us-east"
      }

      invalid_definitions = [
        Map.put(attrs, :effective_config, []),
        Map.put(attrs, :effective_config, %{invalid: {:tuple, :value}}),
        put_in(attrs, [:source, :connection, :config], []),
        put_in(
          attrs,
          [:source, :connection, :config],
          config_with_colliding_keys
        )
      ]

      for invalid_definition <- invalid_definitions do
        assert {:error, changeset} = DefinitionV1.validate(invalid_definition)
        refute changeset.valid?
      end
    end

    test "rejects unknown fields at every structural level" do
      attrs = valid_attrs()

      invalid_definitions = [
        Map.put(attrs, :unexpected, true),
        put_in(attrs, [:source, :unexpected], true),
        put_in(attrs, [:source, :connection, :unexpected], true)
      ]

      for invalid_definition <- invalid_definitions do
        assert {:error, changeset} = DefinitionV1.validate(invalid_definition)
        assert validation_present?(changeset, :unknown_fields)
      end
    end

    test "rejects duplicate atom and string forms of one structural field" do
      attrs =
        valid_attrs()
        |> Map.put("source", valid_attrs().source)

      assert {:error, changeset} = DefinitionV1.validate(attrs)
      assert validation_present?(changeset, :duplicate_fields)
    end
  end

  @spec validation_present?(Changeset.t(), atom()) :: boolean()
  defp validation_present?(changeset, validation) do
    Enum.any?(changeset.errors, fn {_field, {_message, options}} ->
      options[:validation] == validation
    end) or
      Enum.any?(changeset.changes, fn {_field, value} ->
        nested_validation_present?(value, validation)
      end)
  end

  @spec nested_validation_present?(term(), atom()) :: boolean()
  defp nested_validation_present?(%Changeset{} = changeset, validation) do
    validation_present?(changeset, validation)
  end

  defp nested_validation_present?(changesets, validation)
       when is_list(changesets) do
    Enum.any?(changesets, &nested_validation_present?(&1, validation))
  end

  defp nested_validation_present?(_value, _validation), do: false

  @spec valid_attrs() :: map()
  defp valid_attrs do
    %{
      package_version_id: Ecto.UUID.generate(),
      source: %{
        ref: "source",
        contract_version_id: Ecto.UUID.generate(),
        connection: %{
          id: Ecto.UUID.generate(),
          config: %{},
          secret_version_id: nil
        }
      },
      destinations: [
        %{
          ref: "crm",
          contract_version_id: Ecto.UUID.generate(),
          connection: %{
            id: Ecto.UUID.generate(),
            config: %{},
            secret_version_id: nil
          }
        }
      ],
      effective_config: %{}
    }
  end

  @spec stringify_object_keys(term()) :: term()
  defp stringify_object_keys(value) when is_list(value) do
    Enum.map(value, &stringify_object_keys/1)
  end

  defp stringify_object_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {Atom.to_string(key), stringify_object_keys(nested_value)}
    end)
  end

  defp stringify_object_keys(value), do: value
end
