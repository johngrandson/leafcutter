defmodule LeafcutterConnectors.Package.ManifestTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Package.Manifest

  @max_raw_bytes 1_048_576

  describe "parse/1" do
    test "preserves a valid manifest projection and destination order" do
      assert {:ok, manifest} = valid_document() |> Jason.encode!() |> Manifest.parse()

      assert manifest.manifest_version == 1
      assert manifest.package_name == "Conformance package"
      assert manifest.package_version == "2026.08"
      assert manifest.source_ref == "source"

      assert manifest.destination_refs == [
               "first-destination",
               "second-destination"
             ]
    end

    test "rejects malformed JSON and invalid UTF-8 without exposing input" do
      invalid_utf8 =
        ~s({"manifest_version":1,"package":{"name":") <>
          <<255>> <>
          ~s(","version":"2026.08"},"source":{"ref":"source"},"destinations":[{"ref":"destination"}]})

      assert {:error, {:invalid_json, []}} = Manifest.parse("{")
      assert {:error, {:invalid_json, []}} = Manifest.parse(invalid_utf8)
      assert {:error, {:invalid_json, []}} = Manifest.parse(:not_bytes)
    end

    test "rejects duplicate object keys after JSON escape decoding" do
      bytes =
        ~S"""
        {
          "manifest_version": 1,
          "package": {"name": "Conformance package", "version": "2026.08"},
          "source": {"ref": "source", "\u0072ef": "other"},
          "destinations": [{"ref": "destination"}]
        }
        """

      assert {:error, {:duplicate_object_key, ["source", "ref"]}} =
               Manifest.parse(bytes)
    end

    test "never exposes arbitrary object keys in structural errors" do
      secret = "manifest-secret-that-must-not-leak"
      bytes = ~s({"#{secret}":1,"#{secret}":2})

      assert {:error, {:duplicate_object_key, path}} = Manifest.parse(bytes)
      refute inspect(path) =~ secret
    end

    test "rejects unknown fields and invalid schema shapes" do
      invalid_documents = [
        true,
        Map.delete(valid_document(), "source"),
        Map.put(valid_document(), "unknown", true),
        put_in(valid_document(), ["package", "unknown"], true),
        put_in(valid_document(), ["source", "unknown"], true),
        update_in(valid_document(), ["destinations"], fn [first | rest] ->
          [Map.put(first, "unknown", true) | rest]
        end),
        put_in(valid_document(), ["manifest_version"], 2),
        put_in(valid_document(), ["package", "name"], 42),
        put_in(valid_document(), ["source"], []),
        put_in(valid_document(), ["source", "ref"], nil),
        put_in(valid_document(), ["destinations"], [])
      ]

      for document <- invalid_documents do
        assert {:error, {:schema_violation, []}} =
                 document |> Jason.encode!() |> Manifest.parse()
      end
    end

    test "projects a schema-equivalent numeric manifest version safely" do
      document = put_in(valid_document(), ["manifest_version"], 1.0)

      assert {:ok, %Manifest{manifest_version: 1}} =
               document |> Jason.encode!() |> Manifest.parse()
    end

    test "rejects blank identity fields and refs at deterministic paths" do
      invalid_fields = [
        {put_in(valid_document(), ["package", "name"], "  \n"), ["package", "name"]},
        {put_in(valid_document(), ["package", "version"], "\t"), ["package", "version"]},
        {put_in(valid_document(), ["source", "ref"], " "), ["source", "ref"]},
        {put_in(valid_document(), ["destinations", Access.at(0), "ref"], "\r\n"),
         ["destinations", 0, "ref"]}
      ]

      for {document, expected_path} <- invalid_fields do
        assert {:error, {:blank_string, ^expected_path}} =
                 document |> Jason.encode!() |> Manifest.parse()
      end
    end

    test "enforces the 255-character string limit" do
      accepted = put_in(valid_document(), ["package", "name"], String.duplicate("a", 255))
      rejected = put_in(valid_document(), ["package", "name"], String.duplicate("a", 256))

      assert {:ok, %Manifest{}} = accepted |> Jason.encode!() |> Manifest.parse()

      assert {:error, {:schema_violation, []}} =
               rejected |> Jason.encode!() |> Manifest.parse()
    end

    test "rejects refs duplicated across source and destinations" do
      source_duplicate =
        put_in(valid_document(), ["destinations", Access.at(0), "ref"], "source")

      destination_duplicate =
        put_in(
          valid_document(),
          ["destinations", Access.at(1), "ref"],
          "first-destination"
        )

      assert {:error, {:duplicate_ref, ["destinations", 0, "ref"]}} =
               source_duplicate |> Jason.encode!() |> Manifest.parse()

      assert {:error, {:duplicate_ref, ["destinations", 1, "ref"]}} =
               destination_duplicate |> Jason.encode!() |> Manifest.parse()
    end

    test "enforces the exact raw byte limit before decoding" do
      encoded = Jason.encode!(valid_document())
      accepted = encoded <> String.duplicate(" ", @max_raw_bytes - byte_size(encoded))
      rejected = accepted <> " "

      assert byte_size(accepted) == @max_raw_bytes
      assert {:ok, %Manifest{}} = Manifest.parse(accepted)

      assert {:error, {:size_limit_exceeded, []}} =
               Manifest.parse(rejected)
    end

    test "enforces structural depth and node limits before schema validation" do
      nested = Enum.reduce(1..64, nil, fn _index, value -> [value] end)
      too_deep = Map.put(valid_document(), "unexpected", nested)
      too_many_nodes = Map.put(valid_document(), "unexpected", List.duplicate(nil, 10_000))

      assert {:error, {:depth_limit_exceeded, _path}} =
               too_deep |> Jason.encode!() |> Manifest.parse()

      assert {:error, {:node_limit_exceeded, _path}} =
               too_many_nodes |> Jason.encode!() |> Manifest.parse()
    end

    test "accepts at most one thousand ordered destinations" do
      accepted = manifest_with_destination_count(1_000)
      rejected = manifest_with_destination_count(1_001)

      assert {:ok, %Manifest{destination_refs: refs}} =
               accepted |> Jason.encode!() |> Manifest.parse()

      assert length(refs) == 1_000

      assert {:error, {:schema_violation, []}} =
               rejected |> Jason.encode!() |> Manifest.parse()
    end
  end

  describe "sha256/1" do
    test "hashes exact bytes as lowercase hexadecimal" do
      assert Manifest.sha256("{}") ==
               "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"

      refute Manifest.sha256("{}") == Manifest.sha256("{}\n")
      assert Manifest.sha256("{}") =~ ~r/\A[0-9a-f]{64}\z/
    end
  end

  defp valid_document do
    %{
      "manifest_version" => 1,
      "package" => %{
        "name" => "Conformance package",
        "version" => "2026.08"
      },
      "source" => %{"ref" => "source"},
      "destinations" => [
        %{"ref" => "first-destination"},
        %{"ref" => "second-destination"}
      ]
    }
  end

  defp manifest_with_destination_count(count) do
    destinations =
      Enum.map(1..count, fn index ->
        %{"ref" => "destination-#{index}"}
      end)

    put_in(valid_document(), ["destinations"], destinations)
  end
end
