defmodule LeafcutterRuntime.ResolutionFixtures do
  @moduledoc false

  @installed_manifest_sha256 "cce7d8f992ab739429f9dccb46985e9c2ee73338eac96dbdd6a108717f75a3a1"
  @installed_package_name "Inventory conformance package"
  @installed_package_version "2026.08"

  alias Ecto.Adapters.SQL

  alias Leafcutter.Catalog.{Connectors, Contracts, Packages}
  alias Leafcutter.Connections
  alias Leafcutter.Connections.Secrets
  alias Leafcutter.Integrations
  alias Leafcutter.Integrations.Deployments
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo

  def deployment_fixture(prefix \\ "Resolution", options \\ []) do
    suffix = System.unique_integer([:positive])
    installed? = Keyword.get(options, :installed, true)

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
      Contracts.publish_version(contract.id, %{version: "source", schema: true})

    {:ok, warehouse_contract_version} =
      Contracts.publish_version(contract.id, %{version: "warehouse", schema: true})

    {:ok, crm_contract_version} =
      Contracts.publish_version(contract.id, %{version: "crm", schema: true})

    package_name =
      if installed?, do: @installed_package_name, else: "#{prefix} Package #{suffix}"

    package_version =
      if installed?, do: @installed_package_version, else: "uninstalled-#{suffix}"

    manifest_sha256 =
      if installed?, do: @installed_manifest_sha256, else: manifest_sha256_fixture()

    {:ok, package} = Packages.create(%{name: package_name})

    {:ok, package_version} =
      Packages.publish_version(package.id, %{
        manifest_sha256: manifest_sha256,
        version: package_version,
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
      source_connector: source_connector,
      destination_connector: destination_connector,
      contract: contract,
      package: package,
      package_version: package_version,
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

  def delete_persisted_fixture(fixture) do
    Repo.transaction(fn ->
      SQL.query!(Repo, "SET LOCAL session_replication_role = replica", [])

      delete_runs(fixture.package_version.id)

      delete_by(
        "environment_deployment_bindings",
        "environment_deployment_id",
        fixture.deployment.id
      )

      delete_by("environment_deployments", "id", fixture.deployment.id)
      delete_by("integrations", "id", fixture.integration.id)
      delete_by("connections", "organization_id", fixture.organization.id)
      delete_by("secret_versions", "secret_id", fixture.source_secret.id)
      delete_by("secrets", "id", fixture.source_secret.id)
      delete_by("package_version_endpoints", "package_version_id", fixture.package_version.id)
      delete_by("package_versions", "id", fixture.package_version.id)
      delete_by("packages", "id", fixture.package.id)
      delete_by("operations", "connector_version_id", source_connector_version_id(fixture))
      delete_by("operations", "connector_version_id", destination_connector_version_id(fixture))
      delete_by("connector_versions", "connector_id", fixture.source_connector.id)
      delete_by("connector_versions", "connector_id", fixture.destination_connector.id)
      delete_by("connectors", "id", fixture.source_connector.id)
      delete_by("connectors", "id", fixture.destination_connector.id)
      delete_by("contract_versions", "contract_id", fixture.contract.id)
      delete_by("contracts", "id", fixture.contract.id)
      delete_by("environments", "id", fixture.environment.id)
      delete_by("organizations", "id", fixture.organization.id)
    end)

    :ok
  end

  defp connection_fixture(scope, connector_id, name, config, secret_version_id) do
    Connections.create(%{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      connector_id: connector_id,
      name: name,
      config: config,
      secret_version_id: secret_version_id
    })
  end

  defp delete_runs(package_version_id) do
    SQL.query!(
      Repo,
      """
      WITH matching_runs AS MATERIALIZED (
        SELECT run_id
        FROM run_snapshots
        WHERE definition->>'package_version_id' = $1
      ), deleted_snapshots AS (
        DELETE FROM run_snapshots
        WHERE run_id IN (SELECT run_id FROM matching_runs)
      )
      DELETE FROM runs
      WHERE id IN (SELECT run_id FROM matching_runs)
      """,
      [package_version_id]
    )
  end

  defp delete_by(table, column, id) do
    SQL.query!(Repo, "DELETE FROM #{table} WHERE #{column}::text = $1", [id])
  end

  defp source_connector_version_id(fixture) do
    fixture.source_operation.connector_version_id
  end

  defp destination_connector_version_id(fixture) do
    fixture.destination_operation.connector_version_id
  end

  defp manifest_sha256_fixture do
    hex = Ecto.UUID.generate() |> String.replace("-", "")
    hex <> hex
  end
end
