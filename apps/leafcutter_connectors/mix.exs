defmodule LeafcutterConnectors.MixProject do
  use Mix.Project

  def project do
    [
      app: :leafcutter_connectors,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {LeafcutterConnectors.Application, []},
      extra_applications: [:crypto, :logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.23.0"},
      {:jason, "~> 1.4"},
      {:jsv, "~> 0.22.0"}
    ]
  end
end
