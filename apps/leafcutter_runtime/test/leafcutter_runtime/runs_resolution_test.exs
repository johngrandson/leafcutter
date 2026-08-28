defmodule LeafcutterRuntime.RunsResolutionTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset

  alias Leafcutter.Catalog.{Connectors, Contracts, Packages}
  alias Leafcutter.Connections
  alias Leafcutter.Connections.Secrets
  alias Leafcutter.Executions.{Run, RunSnapshot}
  alias Leafcutter.Executions.Runs, as: DurableRuns
  alias Leafcutter.Integrations

  alias Leafcutter.Integrations.Deployments

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo
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
      fixture = deployment_fixture()
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
      fixture = deployment_fixture()

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
      organization_fixture = deployment_fixture("Disabled Organization")
      environment_fixture = deployment_fixture("Disabled Environment")
      integration_fixture = deployment_fixture("Disabled Integration")

      assert {:ok, _organization} =
               Organizations.disable(organization_fixture.organization.id)

      assert {:ok, _environment} =
               Environments.disable(environment_fixture.environment.id)

      assert {:ok, _integration} =
               Integrations.disable(integration_fixture.integration.id)

      assert {:error,
              {:environment_deployment_not_executable,
               :organization_disabled}} =
               Runs.create_from_deployment(
                 organization_fixture.deployment.id
               )

      assert {:error,
              {:environment_deployment_not_executable,
               :environment_disabled}} =
               Runs.create_from_deployment(
                 environment_fixture.deployment.id
               )

      assert {:error,
              {:environment_deployment_not_executable,
               :integration_disabled}} =
               Runs.create_from_deployment(
                 integration_fixture.deployment.id
               )
    end

    test "rolls back Run creation when a Connection is disabled" do
      fixture = deployment_fixture()
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      assert {:ok, _connection} =
               Connections.disable(fixture.crm_connection.id)

      assert {:error,
              {:environment_deployment_not_executable,
               {:connection_disabled, connection_id}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert connection_id == fixture.crm_connection.id
      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "revalidates PackageVersion ownership without persisting a Run" do
      fixture = deployment_fixture()
      run_count = Repo.aggregate(Run, :count)
      snapshot_count = Repo.aggregate(RunSnapshot, :count)

      {:ok, other_package} =
        Packages.create(%{name: unique_name("Other Package")})

      {:ok, other_package_version} =
        Packages.publish_version(other_package.id, %{
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

      assert {:error,
              {:environment_deployment_not_executable,
               :package_version_mismatch}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == run_count
      assert Repo.aggregate(RunSnapshot, :count) == snapshot_count
    end

    test "returns deterministic binding mismatch refs" do
      fixture = deployment_fixture()

      fixture.deployment.bindings
      |> Enum.find(&(&1.ref == "crm"))
      |> Repo.delete!()

      assert {:error,
              {:environment_deployment_not_executable,
               {:binding_mismatch,
                %{missing_refs: ["crm"], unexpected_refs: []}}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == 0
      assert Repo.aggregate(RunSnapshot, :count) == 0
    end

    test "returns the first Connector mismatch by ordered ref" do
      fixture = deployment_fixture()

      fixture.deployment.bindings
      |> Enum.find(&(&1.ref == "source"))
      |> Changeset.change(connection_id: fixture.crm_connection.id)
      |> Repo.update!()

      assert {:error,
              {:environment_deployment_not_executable,
               {:connector_mismatch, "source"}}} =
               Runs.create_from_deployment(fixture.deployment.id)

      assert Repo.aggregate(Run, :count) == 0
      assert Repo.aggregate(RunSnapshot, :count) == 0
    end
  end

  defp deployment_fixture(prefix \\ "Resolution") do
    suffix = System.unique_integer([:positive])

    {:ok, organization} =
      Organizations.create(%{name: "#{prefix} Organization #{suffix}"})

    {:ok, environment} =
      Environments.create(%{
        organization_id: organization.id,
        name: "Production"
      })

    {:ok, source_connector} =
      Connectors.create(%{name: "#{prefix} Source #{suffix}"})

    {:ok, source_connector_version} =
      Connectors.publish_version(source_connector.id, %{
        version: "1",
        operations: [%{ref: "read", role: :source}]
      })

    [source_operation] = source_connector_version.operations

    {:ok, destination_connector} =
      Connectors.create(%{name: "#{prefix} Destination #{suffix}"})

    {:ok, destination_connector_version} =
      Connectors.publish_version(destination_connector.id, %{
        version: "1",
        operations: [%{ref: "write", role: :destination}]
      })

    [destination_operation] = destination_connector_version.operations

    {:ok, contract} =
      Contracts.create(%{name: "#{prefix} Contract #{suffix}"})

    {:ok, source_contract_version} =
      Contracts.publish_version(contract.id, %{version: "source"})

    {:ok, warehouse_contract_version} =
      Contracts.publish_version(contract.id, %{version: "warehouse"})

    {:ok, crm_contract_version} =
      Contracts.publish_version(contract.id, %{version: "crm"})

    {:ok, package} =
      Packages.create(%{name: "#{prefix} Package #{suffix}"})

    {:ok, package_version} =
      Packages.publish_version(package.id, %{
        version: "1",
        source: %{
          ref: "source",
          operation_id: source_operation.id,
          contract_version_id: source_contract_version.id
        },
        destinations: [
          %{
            ref: "warehouse",
            operation_id: destination_operation.id,
            contract_version_id: warehouse_contract_version.id
          },
          %{
            ref: "crm",
            operation_id: destination_operation.id,
            contract_version_id: crm_contract_version.id
          }
        ]
      })

    {:ok, source_secret} =
      Secrets.create(%{
        organization_id: organization.id,
        environment_id: environment.id,
        name: "Source credentials"
      })

    {:ok, source_secret_version} =
      Secrets.create_version(%{
        secret_id: source_secret.id,
        version: "1"
      })

    scope = %{
      organization: organization,
      environment: environment
    }

    {:ok, source_connection} =
      connection_fixture(
        scope,
        source_connector.id,
        "Source",
        %{"endpoint" => "source-v1"},
        source_secret_version.id
      )

    {:ok, warehouse_connection} =
      connection_fixture(
        scope,
        destination_connector.id,
        "Warehouse",
        %{"endpoint" => "warehouse"},
        nil
      )

    {:ok, crm_connection} =
      connection_fixture(
        scope,
        destination_connector.id,
        "CRM",
        %{"endpoint" => "crm"},
        nil
      )

    {:ok, integration} =
      Integrations.create(%{
        organization_id: organization.id,
        package_id: package.id,
        name: "#{prefix} Integration #{suffix}"
      })

    {:ok, deployment} =
      Deployments.create(%{
        organization_id: organization.id,
        environment_id: environment.id,
        integration_id: integration.id,
        package_version_id: package_version.id,
        promotable_config: %{
          batch: %{size: 100, mode: "bulk"},
          regions: ["global"],
          nullable: "promotable",
          promotable_only: true
        },
        local_config: %{
          batch: %{size: 25},
          regions: ["eu-west-1"],
          nullable: nil,
          local_only: true
        },
        bindings: [
          %{ref: "crm", connection_id: crm_connection.id},
          %{ref: "source", connection_id: source_connection.id},
          %{ref: "warehouse", connection_id: warehouse_connection.id}
        ]
      })

    %{
      organization: organization,
      environment: environment,
      integration: integration,
      deployment: deployment,
      source_operation: source_operation,
      destination_operation: destination_operation,
      source_contract_version: source_contract_version,
      warehouse_contract_version: warehouse_contract_version,
      crm_contract_version: crm_contract_version,
      source_secret: source_secret,
      source_secret_version: source_secret_version,
      source_connection: source_connection,
      warehouse_connection: warehouse_connection,
      crm_connection: crm_connection
    }
  end

  defp connection_fixture(
         scope,
         connector_id,
         name,
         config,
         secret_version_id
       ) do
    Connections.create(%{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      connector_id: connector_id,
      name: name,
      config: config,
      secret_version_id: secret_version_id
    })
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

  defp unique_name(prefix) do
    "#{prefix} #{System.unique_integer([:positive])}"
  end
end
