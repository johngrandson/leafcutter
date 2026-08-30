defmodule LeafcutterRuntime.ExecutablePackages.ExplodingPackageFixture do
  @moduledoc false

  @behaviour LeafcutterConnectors.Package

  alias LeafcutterPackageInventoryFixture.Package

  @impl true
  def manifest, do: raise("fixture package callback failed")

  @impl true
  def manifest_sha256, do: Package.manifest_sha256()

  @impl true
  def source, do: Package.source()

  @impl true
  def destinations, do: Package.destinations()

  @impl true
  def resolve(ref, role), do: Package.resolve(ref, role)
end

defmodule LeafcutterRuntime.ExecutablePackagesTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset

  alias Leafcutter.Repo

  alias LeafcutterRuntime.ExecutablePackages
  alias LeafcutterRuntime.ExecutablePackages.{Binding, Inventory}
  alias LeafcutterRuntime.ResolutionFixtures

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "returns a named error for an unknown PackageVersion" do
    assert {:error, :package_version_not_found} =
             ExecutablePackages.resolve(Ecto.UUID.generate())
  end

  test "resolves compiled modules with authoritative Catalog identifiers and order" do
    fixture = ResolutionFixtures.deployment_fixture()

    assert {:ok, %Binding{} = binding} =
             ExecutablePackages.resolve(fixture.package_version.id)

    assert binding.package_version_id == fixture.package_version.id

    assert binding.manifest_sha256 ==
             "cce7d8f992ab739429f9dccb46985e9c2ee73338eac96dbdd6a108717f75a3a1"

    assert binding.source == %{
             ref: "source",
             operation_id: fixture.source_operation.id,
             contract_version_id: fixture.source_contract_version.id,
             module: LeafcutterPackageInventoryFixture.Source
           }

    assert binding.destinations == [
             %{
               ref: "warehouse",
               operation_id: fixture.destination_operation.id,
               contract_version_id: fixture.warehouse_contract_version.id,
               module: LeafcutterPackageInventoryFixture.FirstDestination
             },
             %{
               ref: "crm",
               operation_id: fixture.destination_operation.id,
               contract_version_id: fixture.crm_contract_version.id,
               module: LeafcutterPackageInventoryFixture.SecondDestination
             }
           ]
  end

  test "rejects a historical PackageVersion without a valid manifest digest" do
    fixture = ResolutionFixtures.deployment_fixture()
    replace_manifest_sha256!(fixture.package_version.id, nil)

    assert {:error, :package_not_bound} =
             ExecutablePackages.resolve(fixture.package_version.id)
  end

  test "rejects a valid digest that is absent from the runtime inventory" do
    fixture = ResolutionFixtures.deployment_fixture()
    replace_manifest_sha256!(fixture.package_version.id, String.duplicate("f", 64))

    assert {:error, :package_not_installed} =
             ExecutablePackages.resolve(fixture.package_version.id)
  end

  test "rejects a Catalog package name that differs from the compiled manifest" do
    fixture = ResolutionFixtures.deployment_fixture()

    fixture.package
    |> Changeset.change(name: "Different package name")
    |> Repo.update!()

    assert {:error, :manifest_mismatch} =
             ExecutablePackages.resolve(fixture.package_version.id)
  end

  test "rejects a Catalog package version that differs from the compiled manifest" do
    fixture = ResolutionFixtures.deployment_fixture()
    replace_package_version!(fixture.package_version.id, "different-version")

    assert {:error, :manifest_mismatch} =
             ExecutablePackages.resolve(fixture.package_version.id)
  end

  test "rejects endpoint topology that differs from the compiled manifest" do
    fixture = ResolutionFixtures.deployment_fixture()
    warehouse = Enum.find(fixture.package_version.endpoints, &(&1.ref == "warehouse"))
    replace_endpoint_ref!(warehouse.id, "different-destination")

    assert {:error, :manifest_mismatch} =
             ExecutablePackages.resolve(fixture.package_version.id)
  end

  test "rejects a module that violates the compiled package contract" do
    fixture = ResolutionFixtures.deployment_fixture()
    [entry] = Inventory.runtime_entries()

    invalid_entry = %{
      entry
      | binding: LeafcutterPackageInventoryFixture.InvalidOperationPackage
    }

    assert {:error, :invalid_binding} =
             ExecutablePackages.resolve_projection(
               fixture.package_version,
               [invalid_entry]
             )
  end

  test "keeps unexpected package callback exceptions visible" do
    fixture = ResolutionFixtures.deployment_fixture()
    [entry] = Inventory.runtime_entries()

    exploding_entry = %{
      entry
      | binding: LeafcutterRuntime.ExecutablePackages.ExplodingPackageFixture
    }

    assert_raise RuntimeError, "fixture package callback failed", fn ->
      ExecutablePackages.resolve_projection(
        fixture.package_version,
        [exploding_entry]
      )
    end
  end

  defp replace_manifest_sha256!(package_version_id, manifest_sha256) do
    with_replication_triggers_disabled(fn ->
      SQL.query!(
        Repo,
        "UPDATE package_versions SET manifest_sha256 = $2 WHERE id = $1",
        [dump_uuid!(package_version_id), manifest_sha256]
      )
    end)
  end

  defp replace_package_version!(package_version_id, version) do
    with_replication_triggers_disabled(fn ->
      SQL.query!(
        Repo,
        "UPDATE package_versions SET version = $2 WHERE id = $1",
        [dump_uuid!(package_version_id), version]
      )
    end)
  end

  defp replace_endpoint_ref!(endpoint_id, ref) do
    with_replication_triggers_disabled(fn ->
      SQL.query!(
        Repo,
        "UPDATE package_version_endpoints SET ref = $2 WHERE id = $1",
        [dump_uuid!(endpoint_id), ref]
      )
    end)
  end

  defp with_replication_triggers_disabled(function) do
    SQL.query!(Repo, "SET LOCAL session_replication_role = replica", [])

    try do
      function.()
    after
      SQL.query!(Repo, "SET LOCAL session_replication_role = origin", [])
    end
  end

  defp dump_uuid!(id) do
    {:ok, dumped_id} = Ecto.UUID.dump(id)
    dumped_id
  end
end
