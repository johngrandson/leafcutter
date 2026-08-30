defmodule LeafcutterPackageInventoryFixture.MixProject do
  use Mix.Project

  def project do
    [
      app: :leafcutter_package_inventory_fixture,
      version: "0.1.0",
      build_path: "../../../../../../../_build",
      deps_path: "../../../../../../../deps",
      lockfile: "../../../../../../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:leafcutter_connectors,
       path: "../../../../../../leafcutter_connectors",
       env: :test}
    ]
  end
end
