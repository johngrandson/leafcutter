Code.require_file(Path.expand("mix/package_build.exs", __DIR__))

defmodule LeafcutterRuntime.MixProject do
  use Mix.Project

  @repository_root Path.expand("../..", __DIR__)
  @inventory_file Path.join(@repository_root, "packages/build.exs")
  @inventory_entries LeafcutterRuntime.PackageBuild.load!(@inventory_file, @repository_root)
  @package_dependencies LeafcutterRuntime.PackageBuild.dependency_specs(
                          @inventory_entries,
                          @repository_root
                        )

  def project do
    [
      app: :leafcutter_runtime,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r{^test/fixtures/package_inventory/}],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LeafcutterRuntime.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:leafcutter_core, in_umbrella: true},
      {:leafcutter_connectors, in_umbrella: true}
    ] ++
      @package_dependencies ++
      [
        {:leafcutter_package_inventory_fixture,
         path: "test/fixtures/package_inventory/packages/conformance",
         only: :test,
         env: :test,
         runtime: false}
      ]
  end
end
