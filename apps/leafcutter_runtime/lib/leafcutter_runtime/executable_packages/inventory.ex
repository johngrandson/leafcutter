defmodule LeafcutterRuntime.ExecutablePackages.Inventory do
  @moduledoc """
  Exposes the checked-in package build inventory embedded in the runtime.

  The inventory is parsed and validated while the runtime application is
  compiled. Runtime callers receive only the literal, validated entries and
  never read package files or evaluate build code.
  """

  @typedoc "One installed package selected by trusted build code."
  @type entry :: %{
          app: atom(),
          path: String.t(),
          binding: module(),
          manifest_sha256: String.t()
        }

  @repository_root Path.expand("../../../../..", __DIR__)
  @inventory_file Path.join(@repository_root, "packages/build.exs")
  @package_build_file Path.join(
                        @repository_root,
                        "apps/leafcutter_runtime/mix/package_build.exs"
                      )
  @external_resource @inventory_file
  @external_resource @package_build_file

  @raw_entries LeafcutterRuntime.PackageBuild.load!(@inventory_file, @repository_root)

  Enum.each(@raw_entries, fn entry ->
    manifest_path = Path.join([@repository_root, entry.path, "manifest.json"])
    Module.put_attribute(__MODULE__, :external_resource, manifest_path)
  end)

  @entries LeafcutterRuntime.PackageBuild.validate_compiled!(
             @raw_entries,
             @repository_root
           )

  if Mix.env() == :test do
    @test_repository_root Path.join(
                            @repository_root,
                            "apps/leafcutter_runtime/test/fixtures/package_inventory"
                          )
    @test_inventory_file Path.join(@test_repository_root, "build.exs")
    @external_resource @test_inventory_file

    @test_raw_entries LeafcutterRuntime.PackageBuild.load!(
                        @test_inventory_file,
                        @test_repository_root
                      )

    Enum.each(@test_raw_entries, fn entry ->
      manifest_path = Path.join([@test_repository_root, entry.path, "manifest.json"])
      Module.put_attribute(__MODULE__, :external_resource, manifest_path)
    end)

    @test_entries LeafcutterRuntime.PackageBuild.validate_compiled!(
                    @test_raw_entries,
                    @test_repository_root
                  )
  else
    @test_entries []
  end

  @doc "Returns installed packages in deterministic application order."
  @spec entries() :: [entry()]
  def entries, do: @entries

  @doc false
  @spec runtime_entries() :: [entry()]
  def runtime_entries do
    Enum.sort_by(@entries ++ @test_entries, &Atom.to_string(&1.app))
  end
end
