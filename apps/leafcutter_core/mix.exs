defmodule LeafcutterCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :leafcutter_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LeafcutterCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:jason, "~> 1.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:oban, "~> 2.23"}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]]
  end
end
