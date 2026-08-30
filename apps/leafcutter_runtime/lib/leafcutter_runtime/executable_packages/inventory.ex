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

  @doc "Returns installed packages in deterministic application order."
  @spec entries() :: [entry()]
  def entries, do: @entries
end
