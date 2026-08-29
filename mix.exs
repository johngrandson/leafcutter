defmodule Leafcutter.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Dialyzer analyzes test support modules under MIX_ENV=test.
      dialyzer: [plt_add_apps: [:ex_unit]],
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
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
      {:bandit, "~> 1.5"},
      {:tidewave, "~> 0.9", only: :dev},
      # Keep quality tooling at the umbrella root so one command checks every
      # child application without making the tools runtime dependencies.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      tidewave:
        "run --no-halt -e '{:ok, _} = Application.ensure_all_started(:tidewave); {:ok, _} = Application.ensure_all_started(:bandit); Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: String.to_integer(System.get_env(\"TIDEWAVE_PORT\", \"4001\"))) end)'",
      quality: [
        &run_knowledge_quality/1,
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test",
        &run_dialyzer/1
      ]
    ]
  end

  defp run_knowledge_quality(_) do
    run_python!(
      "knowledge lint tests",
      ["-m", "unittest", "discover", "-s", "docs/scripts", "-p", "test_*.py"]
    )

    run_python!(
      "knowledge lint",
      ["docs/scripts/kb_lint.py", "--kb", "docs/knowledge", "--strict"]
    )
  end

  defp run_python!(label, args) do
    {output, status} =
      System.cmd("python3", args, stderr_to_stdout: true)

    IO.write(output)

    if status != 0 do
      Mix.raise("#{label} failed with exit status #{status}")
    end
  end

  defp run_dialyzer(_) do
    args = if Mix.Project.apps_paths() == %{}, do: ["--plt"], else: []
    Mix.Task.run("dialyzer", args)
  end
end
