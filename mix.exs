defmodule Leafcutter.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      # Keep Tidewave at the umbrella root so `mix tidewave` can inspect every
      # child application running in the shared development runtime.
      {:bandit, "~> 1.0", only: :dev},
      {:tidewave, "~> 0.9", only: :dev}
    ]
  end

  defp aliases do
    [
      tidewave:
        "run --no-halt -e '{:ok, _} = Application.ensure_all_started(:tidewave); {:ok, _} = Application.ensure_all_started(:bandit); Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: String.to_integer(System.get_env(\"TIDEWAVE_PORT\", \"4001\"))) end)'"
    ]
  end
end
