defmodule LeafcutterConnectors.PackageTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Operation.Read
  alias LeafcutterConnectors.Operation.Write
  alias LeafcutterConnectors.Package, as: PackageContract
  alias LeafcutterConnectors.Package.Manifest

  @manifest_path Path.expand("../fixtures/package/manifest.json", __DIR__)

  defmodule SourceOperation do
    @moduledoc false

    @behaviour LeafcutterConnectors.Operation.Read

    alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

    @impl true
    def read(%Invocation{}) do
      {:ok, %Result{records: [], next_cursor: nil}}
    end
  end

  defmodule FirstDestinationOperation do
    @moduledoc false

    @behaviour LeafcutterConnectors.Operation.Write

    alias LeafcutterConnectors.Operation.Error
    alias LeafcutterConnectors.Operation.Write.Invocation

    @impl true
    def write(%Invocation{}) do
      {:error, %Error{category: :permanent, code: "test_failure"}}
    end
  end

  defmodule SecondDestinationOperation do
    @moduledoc false

    @behaviour LeafcutterConnectors.Operation.Write

    alias LeafcutterConnectors.Operation.Error
    alias LeafcutterConnectors.Operation.Write.Invocation

    @impl true
    def write(%Invocation{}) do
      {:error, %Error{category: :permanent, code: "test_failure"}}
    end
  end

  defmodule UndeclaredOperation do
    @moduledoc false

    def read(_invocation), do: :unsupported
  end

  defmodule CompiledPackage do
    @moduledoc false

    use LeafcutterConnectors.Package,
      manifest: Path.expand("../fixtures/package/manifest.json", __DIR__),
      source: {"source", LeafcutterConnectors.PackageTest.SourceOperation},
      destinations: [
        {"first-destination", LeafcutterConnectors.PackageTest.FirstDestinationOperation},
        {"second-destination", LeafcutterConnectors.PackageTest.SecondDestinationOperation}
      ]
  end

  test "exposes the ratified behaviour callbacks" do
    assert Enum.sort(PackageContract.behaviour_info(:callbacks)) ==
             [
               destinations: 0,
               manifest: 0,
               manifest_sha256: 0,
               resolve: 2,
               source: 0
             ]
  end

  test "embeds the validated manifest, digest, and ordered bindings" do
    assert %Manifest{
             package_name: "Conformance package",
             package_version: "2026.08",
             source_ref: "source",
             destination_refs: [
               "first-destination",
               "second-destination"
             ]
           } = CompiledPackage.manifest()

    assert CompiledPackage.manifest_sha256() ==
             @manifest_path |> File.read!() |> Manifest.sha256()

    assert CompiledPackage.source() == {"source", SourceOperation}

    assert CompiledPackage.destinations() == [
             {"first-destination", FirstDestinationOperation},
             {"second-destination", SecondDestinationOperation}
           ]
  end

  test "resolves only declared refs in their declared roles" do
    assert CompiledPackage.resolve("source", :source) ==
             {:ok, SourceOperation}

    assert CompiledPackage.resolve("first-destination", :destination) ==
             {:ok, FirstDestinationOperation}

    assert CompiledPackage.resolve("second-destination", :destination) ==
             {:ok, SecondDestinationOperation}

    assert CompiledPackage.resolve("source", :destination) ==
             {:error, :not_found}

    assert CompiledPackage.resolve("first-destination", :source) ==
             {:error, :not_found}

    assert CompiledPackage.resolve("missing", :destination) ==
             {:error, :not_found}

    assert CompiledPackage.resolve("source", :unknown) ==
             {:error, :not_found}
  end

  test "registers the exact manifest as an external compile resource" do
    external_resources =
      CompiledPackage.module_info(:attributes)
      |> Keyword.get_values(:external_resource)
      |> List.flatten()

    assert @manifest_path in external_resources
  end

  test "rejects missing, extra, and reordered destination bindings" do
    manifest = CompiledPackage.manifest()

    invalid_destinations = [
      [{"first-destination", FirstDestinationOperation}],
      [
        {"first-destination", FirstDestinationOperation},
        {"second-destination", SecondDestinationOperation},
        {"extra", SecondDestinationOperation}
      ],
      [
        {"second-destination", SecondDestinationOperation},
        {"first-destination", FirstDestinationOperation}
      ]
    ]

    for destinations <- invalid_destinations do
      assert_raise CompileError, ~r/destination bindings/, fn ->
        PackageContract.__validate_bindings__!(
          manifest,
          {"source", SourceOperation},
          destinations,
          __ENV__
        )
      end
    end
  end

  test "rejects divergent source refs and duplicate modules" do
    manifest = CompiledPackage.manifest()

    assert_raise CompileError, ~r/source binding/, fn ->
      PackageContract.__validate_bindings__!(
        manifest,
        {"other-source", SourceOperation},
        CompiledPackage.destinations(),
        __ENV__
      )
    end

    assert_raise CompileError, ~r/modules must be unique/, fn ->
      PackageContract.__validate_bindings__!(
        manifest,
        {"source", SourceOperation},
        [
          {"first-destination", FirstDestinationOperation},
          {"second-destination", FirstDestinationOperation}
        ],
        __ENV__
      )
    end
  end

  test "requires Read and Write behaviour conformance" do
    manifest = CompiledPackage.manifest()

    assert_raise CompileError, ~r/must implement #{inspect(Read)}/, fn ->
      PackageContract.__validate_bindings__!(
        manifest,
        {"source", UndeclaredOperation},
        CompiledPackage.destinations(),
        __ENV__
      )
    end

    assert_raise CompileError, ~r/must implement #{inspect(Write)}/, fn ->
      PackageContract.__validate_bindings__!(
        manifest,
        {"source", SourceOperation},
        [
          {"first-destination", UndeclaredOperation},
          {"second-destination", SecondDestinationOperation}
        ],
        __ENV__
      )
    end
  end

  test "rejects malformed binding shapes deterministically" do
    manifest = CompiledPackage.manifest()

    for {source, destinations} <- [
          {:not_a_binding, CompiledPackage.destinations()},
          {{"source", nil}, CompiledPackage.destinations()},
          {{"source", SourceOperation}, [:not_a_binding]}
        ] do
      assert_raise CompileError, ~r/invalid shape/, fn ->
        PackageContract.__validate_bindings__!(
          manifest,
          source,
          destinations,
          __ENV__
        )
      end
    end
  end

  test "requires exact macro options and literal endpoint bindings" do
    assert_raise CompileError, ~r/expected exactly/, fn ->
      compile_package("MissingDestinations", """
      use LeafcutterConnectors.Package,
        manifest: #{inspect(@manifest_path)},
        source: {"source", #{inspect(SourceOperation)}}
      """)
    end

    assert_raise CompileError, ~r/literal \{ref, Module\} tuples/, fn ->
      compile_package("DynamicSource", """
      source_binding = {"source", #{inspect(SourceOperation)}}

      use LeafcutterConnectors.Package,
        manifest: #{inspect(@manifest_path)},
        source: source_binding,
        destinations: [
          {"first-destination", #{inspect(FirstDestinationOperation)}},
          {"second-destination", #{inspect(SecondDestinationOperation)}}
        ]
      """)
    end
  end

  test "requires an absolute manifest path at compilation" do
    assert_raise CompileError, ~r/absolute UTF-8 path/, fn ->
      compile_package("RelativeManifest", """
      use LeafcutterConnectors.Package,
        manifest: "manifest.json",
        source: {"source", #{inspect(SourceOperation)}},
        destinations: [
          {"first-destination", #{inspect(FirstDestinationOperation)}},
          {"second-destination", #{inspect(SecondDestinationOperation)}}
        ]
      """)
    end
  end

  test "compile failures never include raw manifest values" do
    secret = "manifest-secret-that-must-not-leak"

    path =
      Path.join(
        System.tmp_dir!(),
        "leafcutter-invalid-manifest-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(%{"secret" => secret}))
    on_exit(fn -> File.rm(path) end)

    error =
      assert_raise CompileError, fn ->
        PackageContract.__compile_binding__!(
          path,
          {"source", SourceOperation},
          CompiledPackage.destinations(),
          __ENV__
        )
      end

    refute Exception.message(error) =~ secret
  end

  test "normalizes manifest read failures as compile errors" do
    missing_path =
      Path.join(
        System.tmp_dir!(),
        "leafcutter-missing-manifest-#{System.unique_integer([:positive])}.json"
      )

    assert_raise CompileError, ~r/could not read package manifest/, fn ->
      PackageContract.__compile_binding__!(
        missing_path,
        {"source", SourceOperation},
        CompiledPackage.destinations(),
        __ENV__
      )
    end
  end

  test "bindings remain independent from Core and runtime modules" do
    assert function_exported?(SourceOperation, :read, 1)
    assert function_exported?(FirstDestinationOperation, :write, 1)
    assert Read in declared_behaviours(SourceOperation)
    assert Write in declared_behaviours(FirstDestinationOperation)
  end

  defp declared_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp compile_package(suffix, body) do
    Code.compile_string("""
    defmodule LeafcutterConnectors.PackageTest.#{suffix} do
      #{body}
    end
    """)
  end
end
