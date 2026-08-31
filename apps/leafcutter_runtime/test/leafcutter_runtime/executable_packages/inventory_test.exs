defmodule LeafcutterRuntime.ExecutablePackages.InventoryTest do
  use ExUnit.Case, async: false

  alias LeafcutterRuntime.ExecutablePackages.Inventory
  alias LeafcutterRuntime.PackageBuild

  @fixture_root Path.expand("../../fixtures/package_inventory", __DIR__)
  @fixture_build_file Path.join(@fixture_root, "build.exs")
  @fixture_digest "cce7d8f992ab739429f9dccb46985e9c2ee73338eac96dbdd6a108717f75a3a1"

  @fixture_entry %{
    app: :leafcutter_package_inventory_fixture,
    path: "packages/conformance",
    binding: LeafcutterPackageInventoryFixture.Package,
    manifest_sha256: @fixture_digest
  }

  test "keeps the production inventory empty before the first product package" do
    assert Inventory.entries() == []
  end

  test "uses the conformance package only for test runtime resolution" do
    assert Inventory.entries() == []
    assert Inventory.runtime_entries() == [@fixture_entry]
  end

  test "does not expose the conformance package dependency outside the test environment" do
    original_environment = Mix.env()

    try do
      Mix.env(:dev)

      refute Enum.any?(LeafcutterRuntime.MixProject.project()[:deps], fn
               {:leafcutter_package_inventory_fixture, _options} -> true
               _dependency -> false
             end)
    after
      Mix.env(original_environment)
    end
  end

  test "loads literal entries in deterministic application order" do
    source = """
    [
      %{
        app: :z_package,
        path: "packages/z_package",
        binding: Example.ZPackage,
        manifest_sha256: "#{String.duplicate("a", 64)}"
      },
      %{
        app: :a_package,
        path: "packages/a_package",
        binding: Example.APackage,
        manifest_sha256: "#{String.duplicate("b", 64)}"
      }
    ]
    """

    assert [first, second] = PackageBuild.parse!(source, "packages/build.exs")
    assert first.app == :z_package
    assert first.binding == Example.ZPackage
    assert second.app == :a_package

    with_temporary_repository(fn repository_root ->
      create_package_files!(repository_root, "z_package")
      create_package_files!(repository_root, "a_package")

      assert [first, second] =
               source
               |> PackageBuild.parse!("packages/build.exs")
               |> PackageBuild.validate_entries!(repository_root)

      assert first.app == :a_package
      assert second.app == :z_package
    end)
  end

  test "rejects non-literal build code and entries without exact keys" do
    invalid_sources = [
      "System.get_env(\"PACKAGES\") || []",
      "[%{app: :package}]",
      """
      [%{
        app: :package,
        path: "packages/package",
        binding: Example.Package,
        manifest_sha256: "#{String.duplicate("a", 64)}",
        extra: true
      }]
      """,
      """
      [%{
        app: :package,
        app: :other_package,
        path: "packages/package",
        binding: Example.Package,
        manifest_sha256: "#{String.duplicate("a", 64)}"
      }]
      """
    ]

    Enum.each(invalid_sources, fn source ->
      assert_raise ArgumentError, ~r/invalid package inventory/, fn ->
        PackageBuild.parse!(source, "packages/build.exs")
      end
    end)
  end

  test "rejects duplicate app, path, binding, and digest" do
    other_digest = String.duplicate("c", 64)

    duplicate_cases = [
      {:app,
       %{
         @fixture_entry
         | path: "packages/other",
           binding: Example.Other,
           manifest_sha256: other_digest
       }},
      {:path,
       %{
         @fixture_entry
         | app: :other_package,
           binding: Example.Other,
           manifest_sha256: other_digest
       }},
      {:binding,
       %{
         @fixture_entry
         | app: :other_package,
           path: "packages/other",
           manifest_sha256: other_digest
       }},
      {:manifest_sha256,
       %{
         @fixture_entry
         | app: :other_package,
           path: "packages/other",
           binding: Example.Other
       }}
    ]

    Enum.each(duplicate_cases, fn {field, duplicate} ->
      assert_raise ArgumentError, ~r/duplicate #{field}/, fn ->
        PackageBuild.validate_entries!([@fixture_entry, duplicate], @fixture_root)
      end
    end)
  end

  test "rejects invalid app, path, binding, and digest literals" do
    invalid_entries = [
      %{@fixture_entry | app: true},
      %{@fixture_entry | path: "/tmp/package"},
      %{@fixture_entry | path: "packages/../outside"},
      %{@fixture_entry | path: <<"packages/", 0xFF>>},
      %{@fixture_entry | path: "packages/invalid\0path"},
      %{@fixture_entry | binding: :not_a_module},
      %{@fixture_entry | manifest_sha256: String.duplicate("A", 64)},
      %{@fixture_entry | manifest_sha256: String.duplicate("a", 63)}
    ]

    Enum.each(invalid_entries, fn entry ->
      assert_raise ArgumentError, ~r/invalid package inventory/, fn ->
        PackageBuild.validate_entries!([entry], @fixture_root)
      end
    end)
  end

  test "requires an existing Mix project and root manifest" do
    with_temporary_repository(fn repository_root ->
      missing_project = Path.join(repository_root, "packages/missing_project")
      File.mkdir_p!(missing_project)
      File.write!(Path.join(missing_project, "manifest.json"), "{}")

      assert_raise ArgumentError, ~r/Mix project is missing/, fn ->
        PackageBuild.validate_entries!(
          [entry("packages/missing_project")],
          repository_root
        )
      end

      missing_manifest = Path.join(repository_root, "packages/missing_manifest")
      File.mkdir_p!(missing_manifest)
      File.write!(Path.join(missing_manifest, "mix.exs"), "# fixture\n")

      assert_raise ArgumentError, ~r/root manifest is missing/, fn ->
        PackageBuild.validate_entries!(
          [entry("packages/missing_manifest")],
          repository_root
        )
      end

      assert_raise ArgumentError, ~r/package path does not exist/, fn ->
        PackageBuild.validate_entries!([entry("packages/absent")], repository_root)
      end
    end)
  end

  test "rejects symlink escapes and duplicate package realpaths" do
    with_temporary_repository(fn repository_root ->
      outside_package = Path.join(repository_root, "outside")
      create_package_files_at!(outside_package)

      escape_path = Path.join(repository_root, "packages/escape")
      File.ln_s!(outside_package, escape_path)

      assert_raise ArgumentError, ~r/realpath must remain inside packages/, fn ->
        PackageBuild.validate_entries!([entry("packages/escape")], repository_root)
      end

      create_package_files!(repository_root, "canonical")

      alias_path = Path.join(repository_root, "packages/alias")
      File.ln_s!(Path.join(repository_root, "packages/canonical"), alias_path)

      alias_entry = %{
        entry("packages/alias")
        | app: :alias_package,
          binding: Example.AliasPackage,
          manifest_sha256: String.duplicate("b", 64)
      }

      assert_raise ArgumentError, ~r/duplicate path/, fn ->
        PackageBuild.validate_entries!(
          [entry("packages/canonical"), alias_entry],
          repository_root
        )
      end
    end)
  end

  test "does not turn unlisted directories into path dependencies" do
    with_temporary_repository(fn repository_root ->
      create_package_files!(repository_root, "unlisted")

      assert PackageBuild.dependency_specs([], repository_root) == []
    end)

    entries = PackageBuild.load!(@fixture_build_file, @fixture_root)

    assert PackageBuild.dependency_specs(entries, @fixture_root) == [
             {:leafcutter_package_inventory_fixture,
              path: Path.join(@fixture_root, "packages/conformance")}
           ]
  end

  test "accepts a valid source ref that matches the resolver probe prefix" do
    entries = PackageBuild.load!(@fixture_build_file, @fixture_root)

    assert PackageBuild.validate_compiled!(entries, @fixture_root) == [@fixture_entry]
  end

  test "rejects a compiled resolver that accepts refs under the wrong role" do
    [entry] = PackageBuild.load!(@fixture_build_file, @fixture_root)

    invalid_entry = %{
      entry
      | binding: LeafcutterPackageInventoryFixture.InvalidRoleResolverPackage
    }

    assert_raise ArgumentError, ~r/resolves an endpoint under the wrong role/, fn ->
      PackageBuild.validate_compiled!([invalid_entry], @fixture_root)
    end
  end

  test "rejects packages that depend on platform applications" do
    [entry] = PackageBuild.load!(@fixture_build_file, @fixture_root)
    invalid_entry = %{entry | app: :leafcutter_runtime}

    assert_raise ArgumentError, ~r/depends on forbidden platform applications/, fn ->
      PackageBuild.validate_compiled!([invalid_entry], @fixture_root)
    end
  end

  test "requires packages to depend directly on Connectors" do
    [entry] = PackageBuild.load!(@fixture_build_file, @fixture_root)
    invalid_entry = %{entry | app: :jason}

    assert_raise ArgumentError, ~r/must depend directly on leafcutter_connectors/, fn ->
      PackageBuild.validate_compiled!([invalid_entry], @fixture_root)
    end
  end

  test "rejects an inventory app absent from the resolved dependency graph" do
    [entry] = PackageBuild.load!(@fixture_build_file, @fixture_root)
    invalid_entry = %{entry | app: :missing_inventory_app}

    assert_raise ArgumentError, ~r/is not a resolved Mix dependency/, fn ->
      PackageBuild.validate_compiled!([invalid_entry], @fixture_root)
    end
  end

  test "rejects digest, app ownership, binding resource, and binding contract mismatches" do
    [entry] = PackageBuild.load!(@fixture_build_file, @fixture_root)

    invalid_entries = [
      %{entry | manifest_sha256: String.duplicate("0", 64)},
      %{entry | binding: LeafcutterPackageInventoryFixture.OtherManifestPackage},
      %{entry | binding: LeafcutterPackageInventoryFixture.MissingPackage},
      %{entry | binding: LeafcutterPackageInventoryFixture.InvalidOperationPackage},
      %{entry | binding: LeafcutterPackageInventoryFixture.InvalidTopologyPackage}
    ]

    Enum.each(invalid_entries, fn invalid_entry ->
      assert_raise ArgumentError, ~r/invalid package inventory/, fn ->
        PackageBuild.validate_compiled!([invalid_entry], @fixture_root)
      end
    end)
  end

  defp entry(path) do
    %{
      app: :temporary_package,
      path: path,
      binding: Example.TemporaryPackage,
      manifest_sha256: String.duplicate("a", 64)
    }
  end

  defp with_temporary_repository(function) do
    unique = System.unique_integer([:positive, :monotonic])
    repository_root = Path.join(System.tmp_dir!(), "leafcutter_inventory_#{unique}")
    File.mkdir_p!(Path.join(repository_root, "packages"))

    try do
      function.(repository_root)
    after
      File.rm_rf!(repository_root)
    end
  end

  defp create_package_files!(repository_root, name) do
    repository_root
    |> Path.join("packages")
    |> Path.join(name)
    |> create_package_files_at!()
  end

  defp create_package_files_at!(package_path) do
    File.mkdir_p!(package_path)
    File.write!(Path.join(package_path, "mix.exs"), "# fixture\n")
    File.write!(Path.join(package_path, "manifest.json"), "{}")
  end
end
