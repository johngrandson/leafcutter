defmodule Leafcutter.Integrations.DeploymentsTest do
  use Leafcutter.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Connectors,
    Contracts,
    ContractVersion,
    Packages,
    PackageVersion,
    PackageVersionEndpoint
  }

  alias Leafcutter.Connections

  alias Leafcutter.Integrations

  alias Leafcutter.Integrations.{
    Deployments,
    EnvironmentDeployment,
    EnvironmentDeploymentBinding
  }

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments

  describe "create/1" do
    test "persists complete state with normalized config and ordered bindings" do
      scope = deployment_scope()

      assert {:ok, %EnvironmentDeployment{} = deployment} =
               Deployments.create(
                 deployment_attrs(scope,
                   promotable_config: %{
                     batch: %{size: 100},
                     fields: ["id", "name"]
                   },
                   local_config: %{region: "eu-west-1"},
                   id: Ecto.UUID.generate(),
                   effective_config: %{"not" => "persisted"}
                 )
               )

      force_integrity_constraints()

      assert deployment.organization_id == scope.organization.id
      assert deployment.environment_id == scope.environment.id
      assert deployment.integration_id == scope.integration.id
      assert deployment.package_version_id == scope.package_version.id

      assert deployment.promotable_config == %{
               "batch" => %{"size" => 100},
               "fields" => ["id", "name"]
             }

      assert deployment.local_config == %{"region" => "eu-west-1"}

      assert Enum.map(deployment.bindings, &{&1.ref, &1.connection_id}) == [
               {"crm", scope.destination_connection.id},
               {"source", scope.source_connection.id}
             ]

      assert {:ok, deployment.id} == Ecto.UUID.cast(deployment.id)
      refute Map.has_key?(Map.from_struct(deployment), :effective_config)
    end

    test "accepts string-keyed state and defaults both config objects" do
      scope = deployment_scope()

      assert {:ok, deployment} =
               Deployments.create(%{
                 "organization_id" => scope.organization.id,
                 "environment_id" => scope.environment.id,
                 "integration_id" => scope.integration.id,
                 "package_version_id" => scope.package_version.id,
                 "bindings" => [
                   %{
                     "ref" => "source",
                     "connection_id" => scope.source_connection.id
                   },
                   %{
                     "ref" => "crm",
                     "connection_id" => scope.destination_connection.id
                   }
                 ]
               })

      assert deployment.promotable_config == %{}
      assert deployment.local_config == %{}
    end

    test "rejects invalid config and malformed binding inputs" do
      scope = deployment_scope()

      invalid_attrs = [
        deployment_attrs(scope, promotable_config: []),
        deployment_attrs(scope, local_config: %URI{scheme: "https"}),
        deployment_attrs(scope, local_config: %{"pid" => self()}),
        deployment_attrs(scope, bindings: :invalid),
        deployment_attrs(scope, bindings: [:invalid]),
        deployment_attrs(scope,
          bindings: [
            %{ref: "", connection_id: scope.source_connection.id}
          ]
        )
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} = Deployments.create(attrs)
        refute changeset.valid?
      end

      assert Repo.aggregate(EnvironmentDeployment, :count) == 0
      assert Repo.aggregate(EnvironmentDeploymentBinding, :count) == 0
    end

    test "returns deterministic errors for invalid mutable authorities" do
      first_scope = deployment_scope("First")
      second_scope = deployment_scope("Second")

      assert {:error, :organization_not_found} =
               Deployments.create(
                 deployment_attrs(first_scope,
                   organization_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_not_found} =
               Deployments.create(
                 deployment_attrs(first_scope,
                   environment_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_scope_mismatch} =
               Deployments.create(
                 deployment_attrs(first_scope,
                   environment_id: second_scope.environment.id
                 )
               )

      assert {:error, :integration_not_found} =
               Deployments.create(
                 deployment_attrs(first_scope,
                   integration_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :integration_scope_mismatch} =
               Deployments.create(
                 deployment_attrs(first_scope,
                   integration_id: second_scope.integration.id
                 )
               )

      assert {:ok, _disabled_integration} =
               Integrations.disable(first_scope.integration.id)

      assert {:error, :integration_disabled} =
               Deployments.create(deployment_attrs(first_scope))
    end

    test "validates PackageVersion identity and complete endpoint coverage" do
      scope = deployment_scope()
      other_scope = deployment_scope("Other")

      assert {:error, :package_version_not_found} =
               Deployments.create(
                 deployment_attrs(scope,
                   package_version_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :package_version_mismatch} =
               Deployments.create(
                 deployment_attrs(scope,
                   package_version_id: other_scope.package_version.id
                 )
               )

      assert {:error,
              {:binding_mismatch,
               %{
                 missing_refs: ["crm", "source"],
                 unexpected_refs: ["unknown"]
               }}} =
               Deployments.create(
                 deployment_attrs(scope,
                   bindings: [
                     %{
                       ref: "unknown",
                       connection_id: scope.destination_connection.id
                     }
                   ]
                 )
               )
    end

    test "rejects legacy ContractVersions with unique sorted identifiers" do
      scope = deployment_scope()
      first_legacy = legacy_contract_version_fixture("create-first")
      second_legacy = legacy_contract_version_fixture("create-second")

      historical_package_version =
        historical_package_version_fixture(
          scope,
          "legacy-create",
          second_legacy,
          [
            {"crm", first_legacy},
            {"warehouse", second_legacy}
          ]
        )

      expected_ids = Enum.sort([first_legacy.id, second_legacy.id])

      assert {:error, {:contract_versions_not_executable, ^expected_ids}} =
               Deployments.create(
                 deployment_attrs(scope,
                   package_version_id: historical_package_version.id,
                   bindings: three_endpoint_binding_attrs(scope)
                 )
               )

      assert Repo.aggregate(EnvironmentDeployment, :count) == 0
      assert Repo.aggregate(EnvironmentDeploymentBinding, :count) == 0
    end

    test "validates Connection existence, scope, lifecycle, and Connector" do
      scope = deployment_scope()
      other_scope = deployment_scope("Other")
      missing_connection_id = Ecto.UUID.generate()

      assert {:error, {:connection_not_found, ^missing_connection_id}} =
               Deployments.create(
                 deployment_attrs(scope,
                   bindings: [
                     %{
                       ref: "source",
                       connection_id: missing_connection_id
                     },
                     %{
                       ref: "crm",
                       connection_id: scope.destination_connection.id
                     }
                   ]
                 )
               )

      assert {:error, {:connection_scope_mismatch, other_connection_id}} =
               Deployments.create(
                 deployment_attrs(scope,
                   bindings: [
                     %{
                       ref: "source",
                       connection_id: other_scope.source_connection.id
                     },
                     %{
                       ref: "crm",
                       connection_id: scope.destination_connection.id
                     }
                   ]
                 )
               )

      assert other_connection_id == other_scope.source_connection.id

      assert {:ok, _disabled_connection} =
               Connections.disable(scope.destination_connection.id)

      assert {:error, {:connection_disabled, disabled_connection_id}} =
               Deployments.create(deployment_attrs(scope))

      assert disabled_connection_id == scope.destination_connection.id

      connector_scope = deployment_scope("Connector mismatch")

      assert {:error, {:connector_mismatch, "source"}} =
               Deployments.create(
                 deployment_attrs(connector_scope,
                   bindings: [
                     %{
                       ref: "source",
                       connection_id: connector_scope.destination_connection.id
                     },
                     %{
                       ref: "crm",
                       connection_id: connector_scope.destination_connection.id
                     }
                   ]
                 )
               )
    end

    test "rejects duplicate refs and a second deployment for the same scope" do
      scope = deployment_scope()

      duplicate_bindings = [
        %{ref: "source", connection_id: scope.source_connection.id},
        %{ref: "crm", connection_id: scope.destination_connection.id},
        %{ref: "crm", connection_id: scope.destination_connection.id}
      ]

      assert {:error, %Changeset{} = binding_changeset} =
               Deployments.create(deployment_attrs(scope, bindings: duplicate_bindings))

      assert %{ref: [_ | _]} = errors_on(binding_changeset)

      assert {:ok, _deployment} =
               Deployments.create(deployment_attrs(scope))

      assert {:error, %Changeset{} = deployment_changeset} =
               Deployments.create(deployment_attrs(scope))

      refute deployment_changeset.valid?
      assert Repo.aggregate(EnvironmentDeployment, :count) == 1
      assert Repo.aggregate(EnvironmentDeploymentBinding, :count) == 2
    end
  end

  describe "get/1" do
    test "returns the deployment with bindings ordered by ref" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))

      assert {:ok, fetched} = Deployments.get(deployment.id)
      assert fetched.id == deployment.id
      assert Enum.map(fetched.bindings, & &1.ref) == ["crm", "source"]
    end

    test "keeps a historical deployment with legacy ContractVersions readable" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      legacy_contract_version = legacy_contract_version_fixture("deployment-history")

      historical_package_version =
        historical_package_version_fixture(
          scope,
          "deployment-history",
          legacy_contract_version,
          [{"crm", scope.contract_version}]
        )

      deployment
      |> EnvironmentDeployment.replace_changeset(%{
        package_version_id: historical_package_version.id,
        promotable_config: deployment.promotable_config,
        local_config: deployment.local_config
      })
      |> Repo.update!()

      force_integrity_constraints()

      assert {:ok, fetched} = Deployments.get(deployment.id)
      assert fetched.package_version_id == historical_package_version.id

      assert Enum.map(fetched.bindings, & &1.id) ==
               Enum.map(deployment.bindings, & &1.id)
    end

    test "returns a named error when the deployment does not exist" do
      assert {:error, :not_found} =
               Deployments.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "fetch_resolution_scope/1" do
    test "returns only immutable parent identifiers without reading bindings" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      handler_id = {__MODULE__, make_ref()}
      test_process = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:leafcutter, :repo, :query],
          fn _event, _measurements, metadata, test_process ->
            if self() == test_process do
              send(test_process, {:resolution_scope_query, metadata.query})
            end
          end,
          test_process
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, resolution_scope} =
               Deployments.fetch_resolution_scope(deployment.id)

      assert resolution_scope == %{
               organization_id: scope.organization.id,
               environment_id: scope.environment.id,
               integration_id: scope.integration.id
             }

      assert_receive {:resolution_scope_query, query}
      assert String.contains?(query, ~s(FROM "environment_deployments"))
      refute String.contains?(query, "environment_deployment_bindings")
      refute_receive {:resolution_scope_query, _query}
    end

    test "returns a named error when the deployment does not exist" do
      assert {:error, :not_found} =
               Deployments.fetch_resolution_scope(Ecto.UUID.generate())
    end
  end

  describe "lock_for_resolution/1" do
    test "requires a caller-owned transaction" do
      assert {:error, :transaction_required} =
               Deployments.lock_for_resolution(Ecto.UUID.generate())
    end

    test "locks and returns the deployment with bindings ordered by ref" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      handler_id = {__MODULE__, make_ref()}
      test_process = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:leafcutter, :repo, :query],
          fn _event, _measurements, metadata, test_process ->
            if self() == test_process and
                 String.contains?(metadata.query, "FOR SHARE") do
              send(test_process, {:shared_lock_query, metadata.query})
            end
          end,
          test_process
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, {:ok, locked_deployment}} =
               Repo.transaction(fn ->
                 Deployments.lock_for_resolution(deployment.id)
               end)

      assert_receive {:shared_lock_query, deployment_query}
      assert_receive {:shared_lock_query, bindings_query}
      assert String.contains?(deployment_query, ~s(FROM "environment_deployments"))

      assert String.contains?(
               bindings_query,
               ~s(FROM "environment_deployment_bindings")
             )

      assert locked_deployment.id == deployment.id

      assert Enum.map(
               locked_deployment.bindings,
               &{&1.ref, &1.connection_id}
             ) == [
               {"crm", scope.destination_connection.id},
               {"source", scope.source_connection.id}
             ]
    end

    test "returns a named error when the deployment does not exist" do
      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn ->
                 Deployments.lock_for_resolution(Ecto.UUID.generate())
               end)
    end
  end

  describe "replace/2" do
    test "replaces PackageVersion, configs, and the complete binding set" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      old_binding_ids = Enum.map(deployment.bindings, & &1.id)

      replacement_version =
        package_version_fixture(scope,
          version: "2",
          destination_ref: "warehouse"
        )

      {:ok, replacement_connection} =
        connection_fixture(
          scope,
          scope.destination_connector.id,
          "Warehouse"
        )

      assert {:ok, replaced} =
               Deployments.replace(deployment.id, %{
                 package_version_id: replacement_version.id,
                 promotable_config: %{batch: %{size: 500}},
                 local_config: %{region: "us-east-1"},
                 bindings: [
                   %{
                     ref: "warehouse",
                     connection_id: replacement_connection.id
                   },
                   %{
                     ref: "source",
                     connection_id: scope.source_connection.id
                   }
                 ],
                 organization_id: Ecto.UUID.generate(),
                 environment_id: Ecto.UUID.generate(),
                 integration_id: Ecto.UUID.generate()
               })

      force_integrity_constraints()

      assert replaced.id == deployment.id
      assert replaced.organization_id == deployment.organization_id
      assert replaced.environment_id == deployment.environment_id
      assert replaced.integration_id == deployment.integration_id
      assert replaced.package_version_id == replacement_version.id
      assert replaced.promotable_config == %{"batch" => %{"size" => 500}}
      assert replaced.local_config == %{"region" => "us-east-1"}

      assert Enum.map(replaced.bindings, &{&1.ref, &1.connection_id}) == [
               {"source", scope.source_connection.id},
               {"warehouse", replacement_connection.id}
             ]

      for binding_id <- old_binding_ids do
        assert Repo.get(EnvironmentDeploymentBinding, binding_id) == nil
      end
    end

    test "resets omitted config to empty objects" do
      scope = deployment_scope()

      {:ok, deployment} =
        Deployments.create(
          deployment_attrs(scope,
            promotable_config: %{"old" => true},
            local_config: %{"old" => true}
          )
        )

      assert {:ok, replaced} =
               Deployments.replace(deployment.id, %{
                 package_version_id: scope.package_version.id,
                 bindings: binding_attrs(scope)
               })

      assert replaced.promotable_config == %{}
      assert replaced.local_config == %{}
    end

    test "rolls back every field and binding when replacement is invalid" do
      scope = deployment_scope()

      {:ok, deployment} =
        Deployments.create(
          deployment_attrs(scope,
            promotable_config: %{"stable" => true}
          )
        )

      original_binding_ids = Enum.map(deployment.bindings, & &1.id)

      assert {:error, {:connector_mismatch, "source"}} =
               Deployments.replace(deployment.id, %{
                 package_version_id: scope.package_version.id,
                 promotable_config: %{"changed" => true},
                 local_config: %{},
                 bindings: [
                   %{
                     ref: "source",
                     connection_id: scope.destination_connection.id
                   },
                   %{
                     ref: "crm",
                     connection_id: scope.destination_connection.id
                   }
                 ]
               })

      assert {:ok, persisted} = Deployments.get(deployment.id)
      assert persisted.package_version_id == deployment.package_version_id
      assert persisted.promotable_config == %{"stable" => true}
      assert Enum.map(persisted.bindings, & &1.id) == original_binding_ids
    end

    test "rejects legacy ContractVersions and preserves the complete deployment" do
      scope = deployment_scope()

      {:ok, deployment} =
        Deployments.create(
          deployment_attrs(scope,
            promotable_config: %{"stable" => true},
            local_config: %{"region" => "eu-west-1"}
          )
        )

      original_binding_ids = Enum.map(deployment.bindings, & &1.id)
      first_legacy = legacy_contract_version_fixture("replace-first")
      second_legacy = legacy_contract_version_fixture("replace-second")

      historical_package_version =
        historical_package_version_fixture(
          scope,
          "legacy-replace",
          second_legacy,
          [
            {"crm", first_legacy},
            {"warehouse", second_legacy}
          ]
        )

      expected_ids = Enum.sort([first_legacy.id, second_legacy.id])

      assert {:error, {:contract_versions_not_executable, ^expected_ids}} =
               Deployments.replace(deployment.id, %{
                 package_version_id: historical_package_version.id,
                 promotable_config: %{"changed" => true},
                 local_config: %{"region" => "us-east-1"},
                 bindings: three_endpoint_binding_attrs(scope)
               })

      assert {:ok, persisted} = Deployments.get(deployment.id)
      assert persisted.package_version_id == deployment.package_version_id
      assert persisted.promotable_config == %{"stable" => true}
      assert persisted.local_config == %{"region" => "eu-west-1"}
      assert Enum.map(persisted.bindings, & &1.id) == original_binding_ids
    end

    test "requires an explicit PackageVersion and active parent authorities" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))

      assert {:error, %Changeset{} = changeset} =
               Deployments.replace(deployment.id, %{
                 bindings: binding_attrs(scope)
               })

      assert %{package_version_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _disabled_integration} =
               Integrations.disable(scope.integration.id)

      assert {:error, :integration_disabled} =
               Deployments.replace(deployment.id, %{
                 package_version_id: scope.package_version.id,
                 bindings: binding_attrs(scope)
               })
    end
  end

  describe "database invariants" do
    test "rejects identity mutation and non-object config directly" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))

      identity_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              deployment
              |> Changeset.change(environment_id: Ecto.UUID.generate())
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert identity_error.postgres.message ==
               "environment deployment identity is immutable"

      {:ok, dumped_id} = Ecto.UUID.dump(deployment.id)

      config_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              SQL.query!(
                Repo,
                """
                UPDATE environment_deployments
                SET promotable_config = '[]'::jsonb
                WHERE id = $1
                """,
                [dumped_id]
              )
            end,
            mode: :savepoint
          )
        end

      assert config_error.postgres.constraint ==
               "environment_deployments_promotable_config_object"
    end

    test "rejects incomplete bindings at the transaction boundary" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      [binding | _remaining] = deployment.bindings

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              Repo.delete!(binding)

              SQL.query!(
                Repo,
                "SET CONSTRAINTS environment_deployment_bindings_require_integrity IMMEDIATE",
                []
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint ==
               "environment_deployments_complete_bindings"
    end

    test "rejects a PackageVersion from another Package directly" do
      scope = deployment_scope()
      other_scope = deployment_scope("Other")
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              deployment
              |> Changeset.change(package_version_id: other_scope.package_version.id)
              |> Repo.update!()

              SQL.query!(
                Repo,
                "SET CONSTRAINTS environment_deployments_require_integrity IMMEDIATE",
                []
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint ==
               "environment_deployments_package_version_match"
    end

    test "rejects a Connector-incompatible binding directly" do
      scope = deployment_scope()
      {:ok, deployment} = Deployments.create(deployment_attrs(scope))
      source_binding = Enum.find(deployment.bindings, &(&1.ref == "source"))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              source_binding
              |> Changeset.change(connection_id: scope.destination_connection.id)
              |> Repo.update!()

              SQL.query!(
                Repo,
                "SET CONSTRAINTS environment_deployment_bindings_require_integrity IMMEDIATE",
                []
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint ==
               "environment_deployments_connector_compatibility"
    end
  end

  defp deployment_scope(prefix \\ "Scope") do
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

    {:ok, contract_version} =
      Contracts.publish_version(contract.id, %{version: "1", schema: true})

    {:ok, package} = Packages.create(%{name: "#{prefix} Package #{suffix}"})

    {:ok, package_version} =
      Packages.publish_version(package.id, %{
        manifest_sha256: manifest_sha256_fixture(),
        version: "1",
        source: %{
          ref: "source",
          operation_id: source_operation.id,
          contract_version_id: contract_version.id
        },
        destinations: [
          %{
            ref: "crm",
            operation_id: destination_operation.id,
            contract_version_id: contract_version.id
          }
        ]
      })

    scope = %{
      organization: organization,
      environment: environment,
      source_connector: source_connector,
      destination_connector: destination_connector,
      source_operation: source_operation,
      destination_operation: destination_operation,
      contract_version: contract_version,
      package: package,
      package_version: package_version
    }

    {:ok, source_connection} =
      connection_fixture(scope, source_connector.id, "Source")

    {:ok, destination_connection} =
      connection_fixture(scope, destination_connector.id, "Destination")

    {:ok, integration} =
      Integrations.create(%{
        organization_id: organization.id,
        package_id: package.id,
        name: "#{prefix} Integration #{suffix}"
      })

    Map.merge(scope, %{
      source_connection: source_connection,
      destination_connection: destination_connection,
      integration: integration
    })
  end

  defp connection_fixture(scope, connector_id, name) do
    Connections.create(%{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      connector_id: connector_id,
      name: name,
      config: %{}
    })
  end

  defp legacy_contract_version_fixture(version) do
    {:ok, contract} =
      Contracts.create(%{
        name: "Legacy Contract #{System.unique_integer([:positive])}"
      })

    contract_version_id = Ecto.UUID.generate()
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract.id)
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
         scope,
         version,
         source_contract_version,
         destinations
       ) do
    package_version =
      %PackageVersion{}
      |> PackageVersion.publish_changeset(%{
        package_id: scope.package.id,
        manifest_sha256: manifest_sha256_fixture(),
        version: version
      })
      |> Repo.insert!()

    source = %{
      ref: "source",
      role: :source,
      position: nil,
      operation_id: scope.source_operation.id,
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
          operation_id: scope.destination_operation.id,
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

  defp package_version_fixture(scope, overrides) do
    attrs = Map.new(overrides)

    {:ok, package_version} =
      Packages.publish_version(scope.package.id, %{
        manifest_sha256: manifest_sha256_fixture(),
        version: Map.fetch!(attrs, :version),
        source: %{
          ref: "source",
          operation_id: scope.source_operation.id,
          contract_version_id: scope.contract_version.id
        },
        destinations: [
          %{
            ref: Map.fetch!(attrs, :destination_ref),
            operation_id: scope.destination_operation.id,
            contract_version_id: scope.contract_version.id
          }
        ]
      })

    package_version
  end

  defp deployment_attrs(scope, overrides \\ []) do
    %{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      integration_id: scope.integration.id,
      package_version_id: scope.package_version.id,
      promotable_config: %{},
      local_config: %{},
      bindings: binding_attrs(scope)
    }
    |> Map.merge(Map.new(overrides))
  end

  defp binding_attrs(scope) do
    [
      %{ref: "crm", connection_id: scope.destination_connection.id},
      %{ref: "source", connection_id: scope.source_connection.id}
    ]
  end

  defp three_endpoint_binding_attrs(scope) do
    [
      %{ref: "crm", connection_id: scope.destination_connection.id},
      %{ref: "source", connection_id: scope.source_connection.id},
      %{ref: "warehouse", connection_id: scope.destination_connection.id}
    ]
  end

  defp manifest_sha256_fixture do
    hex = Ecto.UUID.generate() |> String.replace("-", "")
    hex <> hex
  end

  defp force_integrity_constraints do
    SQL.query!(
      Repo,
      "SET CONSTRAINTS environment_deployments_require_integrity IMMEDIATE",
      []
    )

    SQL.query!(
      Repo,
      "SET CONSTRAINTS environment_deployment_bindings_require_integrity IMMEDIATE",
      []
    )
  end
end
