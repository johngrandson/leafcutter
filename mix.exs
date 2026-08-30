defmodule Leafcutter.MixProject do
  use Mix.Project

  @repository_root __DIR__

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Dialyzer analyzes test support modules under MIX_ENV=test.
      dialyzer: [plt_add_apps: [:ex_unit]],
      releases: releases(),
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
        &validate_package_build/1,
        "format --check-formatted",
        "credo --strict",
        "test",
        &run_dialyzer/1,
        &run_package_project_quality/1
      ]
    ]
  end

  defp releases do
    [
      leafcutter: [
        applications: [leafcutter_api: :permanent]
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
    python3 =
      System.find_executable("python3") ||
        Mix.raise("#{label} failed: python3 executable not found")

    {output, status} =
      System.cmd(python3, args,
        stderr_to_stdout: true,
        env: [{"PYTHONDONTWRITEBYTECODE", "1"}]
      )

    IO.write(output)

    if status != 0 do
      Mix.raise("#{label} failed with exit status #{status}")
    end
  end

  defp run_dialyzer(_) do
    args = if Mix.Project.apps_paths() == %{}, do: ["--plt"], else: []
    Mix.Task.run("dialyzer", args)
  end

  defp validate_package_build(_) do
    entries = package_entries!()

    release =
      Mix.Release.from_config!(
        :leafcutter,
        Mix.Project.config(),
        include_erts: false
      )

    release_applications = Map.keys(release.applications)

    required_applications = [
      :leafcutter_api,
      :leafcutter_connectors,
      :leafcutter_core,
      :leafcutter_runtime
    ] ++ Enum.map(entries, & &1.app)

    missing_applications = required_applications -- release_applications

    if missing_applications != [] do
      Mix.raise("required platform or inventory apps are absent from the release closure")
    end

    if :leafcutter_package_inventory_fixture in release_applications do
      Mix.raise("test-only package fixture entered the release closure")
    end
  end

  defp run_package_project_quality(_) do
    mix =
      System.find_executable("mix") ||
        Mix.raise("package quality failed: mix executable not found")

    commands = [
      ["compile", "--warnings-as-errors"],
      ["format", "--check-formatted"],
      ["test"],
      ["dialyzer"]
    ]

    Enum.each(package_entries!(), &run_package_quality!(mix, commands, &1))
  end

  defp run_package_quality!(mix, commands, entry) do
    package_path = Path.expand(entry.path, @repository_root)

    Enum.each(commands, &run_package_command!(mix, package_path, entry.app, &1))
  end

  defp run_package_command!(mix, package_path, app, arguments) do
    {output, status} =
      System.cmd(mix, arguments,
        cd: package_path,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    IO.write(output)

    if status != 0 do
      command = Enum.join(["mix" | arguments], " ")
      Mix.raise("#{app} package quality failed: #{command}")
    end
  end

  defp package_entries! do
    inventory = LeafcutterRuntime.ExecutablePackages.Inventory

    case Code.ensure_loaded(inventory) do
      {:module, ^inventory} -> apply(inventory, :entries, [])
      {:error, _reason} -> Mix.raise("compiled package inventory is unavailable")
    end
  end
end
