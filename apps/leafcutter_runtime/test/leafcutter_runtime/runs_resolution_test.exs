defmodule LeafcutterRuntime.RunsResolutionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    ContractVersion,
    Packages,
    PackageVersion,
    PackageVersionEndpoint
  }

  alias Leafcutter.Connections
  alias Leafcutter.Connections.Secrets
  alias Leafcutter.Executions.{Run, RunSnapshot}
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias Leafcutter.Integrations

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo
  alias LeafcutterRuntime.ResolutionFixtures
  alias LeafcutterRuntime.Runs

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "create_from_deployment/1" do
    test "returns a named error when the deployment does not exist" do
      assert {:error, :environment_deployment_not_found} =
               Runs.create_from_deployment(Ecto.UUID.generate())
    end

    test "freezes a complete definition v1 in the ratified authority order" do
      fixture = ResolutionFixtures.deployment_fixture()
      handler_id = attach_query_handler()

      assert {:ok, run} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert run.status == :pending
      assert run.owner_node_id == nil
      assert run.generation == 0
      assert run.ownership_acquired_at == nil
      assert Runs.lookup(run.id) == :error

      assert {:ok, %RunSnapshot{} = snapshot} =
               DurableRuns.fetch_snapshot(run.id)

      assert snapshot.definition == expected_definition(fixture)
      assert snapshot.format_version == RunSnapshot.current_format_version()

      refute Map.has_key?(snapshot.definition, "organization_id")
      refute Map.has_key?(snapshot.definition, "environment_id")
      refute Map.has_key?(snapshot.definition, "integration_id")
      refute Map.has_key?(snapshot.definition, "environment_deployment_id")

      queries = drain_queries(handler_id)
      assert_resolution_query_order(queries)
    end

    test "creates distinct Runs and preserves earlier Connection state" do
      fixture = ResolutionFixtures.deployment_fixture()

      assert {:ok, first_run} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert {:ok, next_secret_version} =
               Secrets.create_version(%{
                 secret_id: fixture.source_secret.id,
                 version: "2"
               })

      assert {:ok, updated_source_connection} =
               Connections.update(fixture.source_connection.id, %{
                 config: %{"endpoint" => "source-v2"},
                 secret_version_id: next_secret_version.id
               })

      assert {:ok, second_run} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert first_run.id != second_run.id

      assert {:ok, first_snapshot} = DurableRuns.fetch_snapshot(first_run.id)
      assert {:ok, second_snapshot} = DurableRuns.fetch_snapshot(second_run.id)

      assert get_in(first_snapshot.definition, ["source", "connection"]) == %{
               "id" => fixture.source_connection.id,
               "config" => %{"endpoint" => "source-v1"},
               "secret_version_id" => fixture.source_secret_version.id
             }

      assert get_in(second_snapshot.definition, ["source", "connection"]) == %{
               "id" => updated_source_connection.id,
               "config" => %{"endpoint" => "source-v2"},
               "secret_version_id" => next_secret_version.id
             }
    end

    test "classifies disabled parent authorities" do
      organization_fixture =
        ResolutionFixtures.deployment_fixture("Disabled Organization")

      environment_fixture =
        ResolutionFixtures.deployment_fixture("Disabled Environment")

      integration_fixture =
        ResolutionFixtures.deployment_fixture("Disabled Integration")

      assert {:ok, _organization} =
               Organizations.disable(organization_fixture.organization.id)

      assert {:ok, _environment} =
               Environments.disable(environment_fixture.environment.id)

      assert {:ok, _integration} =
               Integrations.disable(integration_fixture.integration.id)

      assert {:error, {:environment_deployment_not_executable, :organization_disabled}} =
               Runs.create_from_deployment(organization_fixture.deployment.id)

      assert {:error, {:environment_deployment_not_executable, :environment_disabled}} =
               Runs.create_from_deployment(environment_fixture.deployment.id)

      assert {:error, {:environment_deployment_not_executable, :integration_disabled}} =
               Runs.create_from_deployment(integration_fixture.deployment.id)
    end

    test "rolls back Run creation when a Connection is disabled" do
      fixture = ResolutionFixtures.deployment_fixture()
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      assert {:ok, _connection} =
               Connections.disable(fixture.crm_connection.id)

      assert {:error,
              {:environment_deployment_not_executable, {:connection_disabled, connection_id}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert connection_id == fixture.crm_connection.id
      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "revalidates PackageVersion ownership without persisting a Run" do
      fixture = ResolutionFixtures.deployment_fixture()
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      {:ok, other_package} =
        Packages.create(%{name: unique_name("Other Package")})

      {:ok, other_package_version} =
        Packages.publish_version(other_package.id, %{
          manifest_sha256: manifest_sha256_fixture(),
          version: "1",
          source: %{
            ref: "source",
            operation_id: fixture.source_operation.id,
            contract_version_id: fixture.source_contract_version.id
          },
          destinations: [
            %{
              ref: "warehouse",
              operation_id: fixture.destination_operation.id,
              contract_version_id: fixture.warehouse_contract_version.id
            },
            %{
              ref: "crm",
              operation_id: fixture.destination_operation.id,
              contract_version_id: fixture.crm_contract_version.id
            }
          ]
        })

      fixture.deployment
      |> Changeset.change(package_version_id: other_package_version.id)
      |> Repo.update!()

      assert {:error, {:environment_deployment_not_executable, :package_version_mismatch}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "rejects legacy ContractVersions without persisting a Run" do
      fixture = ResolutionFixtures.deployment_fixture()
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      first_legacy =
        legacy_contract_version_fixture(
          fixture.contract.id,
          "resolver-first"
        )

      second_legacy =
        legacy_contract_version_fixture(
          fixture.contract.id,
          "resolver-second"
        )

      historical_package_version =
        historical_package_version_fixture(
          fixture,
          second_legacy,
          [
            {"warehouse", first_legacy},
            {"crm", second_legacy}
          ]
        )

      fixture.deployment
      |> Changeset.change(package_version_id: historical_package_version.id)
      |> Repo.update!()

      expected_ids = Enum.sort([first_legacy.id, second_legacy.id])

      assert {:error,
              {:environment_deployment_not_executable,
               {:contract_versions_not_executable, ^expected_ids}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "returns deterministic binding mismatch refs" do
      fixture = ResolutionFixtures.deployment_fixture()

      fixture.deployment.bindings
      |> Enum.find(&(&1.ref == "crm"))
      |> Repo.delete!()

      assert {:error,
              {:environment_deployment_not_executable,
               {:binding_mismatch, %{missing_refs: ["crm"], unexpected_refs: []}}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == 0
      assert Repo.aggregate(RunSnapshot, :count) == 0
    end

    test "returns the first Connector mismatch by ordered ref" do
      fixture = ResolutionFixtures.deployment_fixture()

      fixture.deployment.bindings
      |> Enum.find(&(&1.ref == "source"))
      |> Changeset.change(connection_id: fixture.crm_connection.id)
      |> Repo.update!()

      assert {:error, {:environment_deployment_not_executable, {:connector_mismatch, "source"}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == 0
      assert Repo.aggregate(RunSnapshot, :count) == 0
    end
  end

  defp legacy_contract_version_fixture(contract_id, version) do
    contract_version_id = Ecto.UUID.generate()
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract_id)
    {:ok, dumped_contract_version_id} = Ecto.UUID.dump(contract_version_id)

    SQL.query!(
      Repo,
      "ALTER TABLE contract_versions DISABLE TRIGGER contract_versions_require_schema",
      []
    )

    try do
      SQL.query!(
        Repo,
        """
        INSERT INTO contract_versions (
          id,
          contract_id,
          version,
          schema,
          published_at,
          inserted_at
        )
        VALUES ($1, $2, $3, NULL, clock_timestamp(), clock_timestamp())
        """,
        [dumped_contract_version_id, dumped_contract_id, version]
      )
    after
      SQL.query!(
        Repo,
        "ALTER TABLE contract_versions ENABLE TRIGGER contract_versions_require_schema",
        []
      )
    end

    Repo.get!(ContractVersion, contract_version_id)
  end

  defp historical_package_version_fixture(
         fixture,
         source_contract_version,
         destinations
       ) do
    package_version =
      %PackageVersion{}
      |> PackageVersion.publish_changeset(%{
        package_id: fixture.package.id,
        manifest_sha256: manifest_sha256_fixture(),
        version: "legacy"
      })
      |> Repo.insert!()

    source = %{
      ref: "source",
      role: :source,
      position: nil,
      operation_id: fixture.source_operation.id,
      contract_version_id: source_contract_version.id
    }

    destination_endpoints =
      destinations
      |> Enum.with_index()
      |> Enum.map(fn {{ref, contract_version}, position} ->
        %{
          ref: ref,
          role: :destination,
          position: position,
          operation_id: fixture.destination_operation.id,
          contract_version_id: contract_version.id
        }
      end)

    for attrs <- [source | destination_endpoints] do
      %PackageVersionEndpoint{}
      |> PackageVersionEndpoint.publish_changeset(
        Map.put(attrs, :package_version_id, package_version.id)
      )
      |> Repo.insert!()
    end

    package_version
    |> Changeset.change(published_at: DateTime.utc_now(:microsecond))
    |> Repo.update!()
  end

  defp expected_definition(fixture) do
    %{
      "package_version_id" => fixture.deployment.package_version_id,
      "source" => %{
        "ref" => "source",
        "contract_version_id" => fixture.source_contract_version.id,
        "connection" => %{
          "id" => fixture.source_connection.id,
          "config" => %{"endpoint" => "source-v1"},
          "secret_version_id" => fixture.source_secret_version.id
        }
      },
      "destinations" => [
        %{
          "ref" => "warehouse",
          "contract_version_id" => fixture.warehouse_contract_version.id,
          "connection" => %{
            "id" => fixture.warehouse_connection.id,
            "config" => %{"endpoint" => "warehouse"},
            "secret_version_id" => nil
          }
        },
        %{
          "ref" => "crm",
          "contract_version_id" => fixture.crm_contract_version.id,
          "connection" => %{
            "id" => fixture.crm_connection.id,
            "config" => %{"endpoint" => "crm"},
            "secret_version_id" => nil
          }
        }
      ],
      "effective_config" => %{
        "batch" => %{"size" => 25, "mode" => "bulk"},
        "regions" => ["eu-west-1"],
        "nullable" => nil,
        "promotable_only" => true,
        "local_only" => true
      }
    }
  end

  defp attach_query_handler do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, test_process ->
          if self() == test_process do
            send(test_process, {handler_id, metadata.query})
          end
        end,
        test_process
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    handler_id
  end

  defp drain_queries(handler_id, queries \\ []) do
    receive do
      {^handler_id, query} -> drain_queries(handler_id, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp assert_resolution_query_order(queries) do
    resolution_scope_index =
      query_index!(queries, ~s(FROM "environment_deployments"), fn query ->
        not String.contains?(query, "FOR SHARE")
      end)

    organization_index =
      query_index!(queries, ~s(FROM "organizations"), &shared_lock?/1)

    environment_index =
      query_index!(queries, ~s(FROM "environments"), &shared_lock?/1)

    integration_index =
      query_index!(queries, ~s(FROM "integrations"), &shared_lock?/1)

    deployment_index =
      query_index!(
        queries,
        ~s(FROM "environment_deployments"),
        &shared_lock?/1
      )

    bindings_index =
      query_index!(
        queries,
        ~s(FROM "environment_deployment_bindings"),
        &shared_lock?/1
      )

    connections_index =
      query_index!(queries, ~s(FROM "connections"), &shared_lock?/1)

    package_version_index =
      query_index!(queries, ~s(FROM "package_versions"))

    secret_versions_index =
      query_index!(queries, ~s(FROM "secret_versions"))

    assert [
             resolution_scope_index,
             organization_index,
             environment_index,
             integration_index,
             deployment_index,
             bindings_index,
             connections_index,
             package_version_index,
             secret_versions_index
           ] ==
             Enum.sort([
               resolution_scope_index,
               organization_index,
               environment_index,
               integration_index,
               deployment_index,
               bindings_index,
               connections_index,
               package_version_index,
               secret_versions_index
             ])
  end

  defp query_index!(queries, fragment, predicate \\ fn _query -> true end) do
    case Enum.find_index(queries, fn query ->
           String.contains?(query, fragment) and predicate.(query)
         end) do
      nil -> flunk("expected query containing #{inspect(fragment)}")
      index -> index
    end
  end

  defp shared_lock?(query), do: String.contains?(query, "FOR SHARE")

  defp manifest_sha256_fixture do
    hex = Ecto.UUID.generate() |> String.replace("-", "")
    hex <> hex
  end

  defp unique_name(prefix) do
    "#{prefix} #{System.unique_integer([:positive])}"
  end
end
