defmodule LeafcutterPackageInventoryFixture.MixProject do
  use Mix.Project

  @spec project() :: keyword()
  def project do
    [
      app: :leafcutter_package_inventory_fixture,
      version: "0.1.0",
      build_path: "../../../../../../../_build",
      deps_path: "../../../../../../../deps",
      lockfile: "../../../../../../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: false,
      dialyzer: [
        no_umbrella: true,
        plt_local_path: "../../../../../../../_build/package_inventory_fixture_plts"
      ],
      deps: deps()
    ]
  end

  @spec application() :: keyword()
  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:leafcutter_connectors, path: "../../../../../../leafcutter_connectors", env: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
