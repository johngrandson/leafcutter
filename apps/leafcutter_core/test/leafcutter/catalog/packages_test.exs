defmodule Leafcutter.Catalog.PackagesTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    ConnectorVersion,
    Connectors,
    ContractVersion,
    Contracts,
    Operation,
    Package,
    Packages,
    PackageVersion,
    PackageVersionEndpoint
  }

  @typep topology_fixture :: %{
           source_operation: Operation.t(),
           first_destination_operation: Operation.t(),
           second_destination_operation: Operation.t(),
           contract_version: ContractVersion.t()
         }

  describe "create/1" do
    test "persists a global Package identity" do
      assert {:ok, %Package{} = package} =
               Packages.create(%{
                 name: "CRM synchronization",
                 id: Ecto.UUID.generate()
               })

      assert package.name == "CRM synchronization"
      assert {:ok, package.id} == Ecto.UUID.cast(package.id)
      assert %DateTime{} = package.inserted_at
      assert %DateTime{} = package.updated_at
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 names" do
      invalid_attrs = [
        %{},
        %{name: ""},
        %{name: "   "},
        %{name: String.duplicate("a", 256)},
        %{name: <<255>>}
      ]

      for attrs <- invalid_attrs do
        assert {:error, changeset} = Packages.create(attrs)
        assert %{name: [_ | _]} = errors_on(changeset)
      end
    end
  end

  describe "get/1" do
    test "returns a persisted Package identity without preloading versions" do
      package = package_fixture()

      assert {:ok, fetched} = Packages.get(package.id)
      assert fetched.id == package.id
      assert fetched.name == package.name
      assert %Ecto.Association.NotLoaded{} = fetched.versions
    end

    test "returns a named error when the Package does not exist" do
      assert {:error, :not_found} =
               Packages.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "publish_version/2" do
    test "publishes one source and ordered destinations atomically" do
      package = package_fixture()
      topology = topology_fixture()

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish_version(
                 package.id,
                 publication_attrs(topology,
                   version: "release-2026.08",
                   published_at: ~U[2025-01-01 00:00:00.000000Z],
                   manifest: %{"not" => "persisted"}
                 )
               )

      assert package_version.package == package
      assert package_version.version == "release-2026.08"
      assert %DateTime{} = package_version.published_at

      assert package_version.published_at !=
               ~U[2025-01-01 00:00:00.000000Z]

      assert [source, first_destination, second_destination] =
               package_version.endpoints

      assert %PackageVersionEndpoint{
               ref: "source",
               role: :source,
               position: nil
             } = source

      assert %PackageVersionEndpoint{
               ref: "crm",
               role: :destination,
               position: 0
             } = first_destination

      assert %PackageVersionEndpoint{
               ref: "warehouse",
               role: :destination,
               position: 1
             } = second_destination

      assert %ConnectorVersion{} = source.operation.connector_version
      assert source.contract_version == topology.contract_version
      assert Repo.aggregate(PackageVersion, :count) == 1
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 3
    end

    test "accepts string-keyed publication attributes" do
      package = package_fixture()
      topology = topology_fixture()

      attrs = %{
        "version" => "opaque",
        "source" => %{
          "ref" => "source",
          "operation_id" => topology.source_operation.id,
          "contract_version_id" => topology.contract_version.id
        },
        "destinations" => [
          %{
            "ref" => "crm",
            "operation_id" => topology.first_destination_operation.id,
            "contract_version_id" => topology.contract_version.id
          }
        ]
      }

      assert {:ok, package_version} =
               Packages.publish_version(package.id, attrs)

      assert package_version.version == "opaque"
      assert Enum.map(package_version.endpoints, & &1.ref) == ["source", "crm"]
    end

    test "returns package_not_found without persisting a version" do
      topology = topology_fixture()

      assert {:error, :package_not_found} =
               Packages.publish_version(
                 "00000000-0000-0000-0000-000000000000",
                 publication_attrs(topology)
               )

      assert Repo.aggregate(PackageVersion, :count) == 0
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 0
    end

    test "rejects incomplete publication shapes" do
      package = package_fixture()
      topology = topology_fixture()
      valid_source = source_attrs(topology)
      valid_destination = destination_attrs(topology)

      invalid_attrs = [
        %{},
        %{version: "1", source: nil, destinations: [valid_destination]},
        %{version: "1", source: valid_source, destinations: nil},
        %{version: "1", source: valid_source, destinations: []},
        %{version: "1", source: valid_source, destinations: [:invalid]}
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} =
                 Packages.publish_version(package.id, attrs)

        refute changeset.valid?
      end

      assert Repo.aggregate(PackageVersion, :count) == 0
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 0
    end

    test "rolls back invalid UTF-8 and duplicate endpoint refs" do
      package = package_fixture()
      topology = topology_fixture()

      invalid_utf8_attrs =
        publication_attrs(topology,
          source: Map.put(source_attrs(topology), :ref, <<255>>)
        )

      assert {:error, invalid_utf8_changeset} =
               Packages.publish_version(package.id, invalid_utf8_attrs)

      assert %{ref: [_ | _]} = errors_on(invalid_utf8_changeset)

      duplicate_ref_attrs =
        publication_attrs(topology,
          destinations: [
            Map.put(destination_attrs(topology), :ref, "source")
          ]
        )

      assert {:error, duplicate_changeset} =
               Packages.publish_version(package.id, duplicate_ref_attrs)

      assert %{ref: [_ | _]} = errors_on(duplicate_changeset)
      assert Repo.aggregate(PackageVersion, :count) == 0
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 0
    end

    test "rejects an Operation whose role does not match the endpoint" do
      package = package_fixture()
      topology = topology_fixture()

      attrs =
        publication_attrs(topology,
          source: %{
            ref: "source",
            operation_id: topology.first_destination_operation.id,
            contract_version_id: topology.contract_version.id
          }
        )

      assert {:error, changeset} =
               Packages.publish_version(package.id, attrs)

      assert %{operation_id: [_ | _]} = errors_on(changeset)
      assert Repo.aggregate(PackageVersion, :count) == 0
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 0
    end

    test "rejects missing Operation and ContractVersion references" do
      package = package_fixture()
      topology = topology_fixture()

      missing_operation_attrs =
        publication_attrs(topology,
          source:
            topology
            |> source_attrs()
            |> Map.put(:operation_id, Ecto.UUID.generate())
        )

      assert {:error, operation_changeset} =
               Packages.publish_version(package.id, missing_operation_attrs)

      assert %{operation_id: [_ | _]} = errors_on(operation_changeset)

      missing_contract_attrs =
        publication_attrs(topology,
          source:
            topology
            |> source_attrs()
            |> Map.put(:contract_version_id, Ecto.UUID.generate())
        )

      assert {:error, contract_changeset} =
               Packages.publish_version(package.id, missing_contract_attrs)

      assert %{contract_version_id: [_ | _]} = errors_on(contract_changeset)
      assert Repo.aggregate(PackageVersion, :count) == 0
      assert Repo.aggregate(PackageVersionEndpoint, :count) == 0
    end

    test "enforces version uniqueness within one Package" do
      first_package = package_fixture("First")
      second_package = package_fixture("Second")
      topology = topology_fixture()

      assert {:ok, _version} =
               Packages.publish_version(
                 first_package.id,
                 publication_attrs(topology)
               )

      assert {:error, %Changeset{} = changeset} =
               Packages.publish_version(
                 first_package.id,
                 publication_attrs(topology)
               )

      assert %{package_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _version} =
               Packages.publish_version(
                 second_package.id,
                 publication_attrs(topology)
               )
    end
  end

  describe "get_version/1" do
    test "returns the immutable projection in deterministic endpoint order" do
      package = package_fixture()
      topology = topology_fixture()

      assert {:ok, published} =
               Packages.publish_version(
                 package.id,
                 publication_attrs(topology)
               )

      assert {:ok, fetched} = Packages.get_version(published.id)
      assert fetched.package == package

      assert Enum.map(fetched.endpoints, fn endpoint ->
               {endpoint.ref, endpoint.role, endpoint.position}
             end) == [
               {"source", :source, nil},
               {"crm", :destination, 0},
               {"warehouse", :destination, 1}
             ]

      for endpoint <- fetched.endpoints do
        assert %Operation{} = endpoint.operation
        assert %ConnectorVersion{} = endpoint.operation.connector_version
        assert %ContractVersion{} = endpoint.contract_version
      end
    end

    test "returns a named error when the PackageVersion does not exist" do
      assert {:error, :not_found} =
               Packages.get_version(
                 "00000000-0000-0000-0000-000000000000"
               )
    end
  end

  describe "database invariants" do
    test "rejects PackageVersion updates and endpoint deletes" do
      package = package_fixture()
      topology = topology_fixture()

      assert {:ok, package_version} =
               Packages.publish_version(
                 package.id,
                 publication_attrs(topology)
               )

      [source | _destinations] = package_version.endpoints

      version_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              package_version
              |> Changeset.change(version: "changed")
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert version_error.postgres.message ==
               "package_versions content is immutable"

      endpoint_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn -> Repo.delete!(source) end,
            mode: :savepoint
          )
        end

      assert endpoint_error.postgres.message ==
               "package_version_endpoints content is immutable"
    end

    test "rejects adding an endpoint after publication" do
      package = package_fixture()
      topology = topology_fixture()

      assert {:ok, package_version} =
               Packages.publish_version(
                 package.id,
                 publication_attrs(topology)
               )

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              %PackageVersionEndpoint{}
              |> PackageVersionEndpoint.publish_changeset(%{
                package_version_id: package_version.id,
                ref: "late_destination",
                role: :destination,
                position: 2,
                operation_id: topology.first_destination_operation.id,
                contract_version_id: topology.contract_version.id
              })
              |> Repo.insert!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message ==
               "endpoints cannot be added after PackageVersion publication"
    end

    test "rejects an unsealed PackageVersion at the transaction boundary" do
      package = package_fixture()

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              %PackageVersion{}
              |> PackageVersion.publish_changeset(%{
                package_id: package.id,
                version: "unsealed"
              })
              |> Repo.insert!()

              Ecto.Adapters.SQL.query!(
                Repo,
                "SET CONSTRAINTS package_versions_require_complete_publication IMMEDIATE",
                []
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message ==
               "package_versions must be published before commit"
    end

    test "rejects publication without at least one destination" do
      package = package_fixture()
      topology = topology_fixture()

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              package_version =
                %PackageVersion{}
                |> PackageVersion.publish_changeset(%{
                  package_id: package.id,
                  version: "incomplete"
                })
                |> Repo.insert!()

              %PackageVersionEndpoint{}
              |> PackageVersionEndpoint.publish_changeset(%{
                package_version_id: package_version.id,
                ref: "source",
                role: :source,
                position: nil,
                operation_id: topology.source_operation.id,
                contract_version_id: topology.contract_version.id
              })
              |> Repo.insert!()

              package_version
              |> Changeset.change(
                published_at: DateTime.utc_now(:microsecond)
              )
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message ==
               "package_versions require at least one destination endpoint"
    end
  end

  @spec package_fixture(String.t()) :: Package.t()
  defp package_fixture(name \\ "Package") do
    {:ok, package} = Packages.create(%{name: name})
    package
  end

  @spec topology_fixture() :: topology_fixture()
  defp topology_fixture do
    {:ok, connector} = Connectors.create(%{name: "Connector"})

    {:ok, connector_version} =
      Connectors.publish_version(connector.id, %{
        version: "1",
        operations: [
          %{ref: "read", role: :source},
          %{ref: "write_crm", role: :destination},
          %{ref: "write_warehouse", role: :destination}
        ]
      })

    operations_by_ref = Map.new(connector_version.operations, &{&1.ref, &1})

    {:ok, contract} = Contracts.create(%{name: "Customer"})
    {:ok, contract_version} = Contracts.publish_version(contract.id, %{version: "1"})

    %{
      source_operation: Map.fetch!(operations_by_ref, "read"),
      first_destination_operation: Map.fetch!(operations_by_ref, "write_crm"),
      second_destination_operation:
        Map.fetch!(operations_by_ref, "write_warehouse"),
      contract_version: contract_version
    }
  end

  @spec publication_attrs(topology_fixture(), keyword()) :: map()
  defp publication_attrs(topology, overrides \\ []) do
    topology
    |> default_publication_attrs()
    |> Map.merge(Map.new(overrides))
  end

  @spec default_publication_attrs(topology_fixture()) :: map()
  defp default_publication_attrs(topology) do
    %{
      version: "1",
      source: source_attrs(topology),
      destinations: [
        destination_attrs(topology),
        %{
          ref: "warehouse",
          operation_id: topology.second_destination_operation.id,
          contract_version_id: topology.contract_version.id
        }
      ]
    }
  end

  @spec source_attrs(topology_fixture()) :: map()
  defp source_attrs(topology) do
    %{
      ref: "source",
      operation_id: topology.source_operation.id,
      contract_version_id: topology.contract_version.id
    }
  end

  @spec destination_attrs(topology_fixture()) :: map()
  defp destination_attrs(topology) do
    %{
      ref: "crm",
      operation_id: topology.first_destination_operation.id,
      contract_version_id: topology.contract_version.id
    }
  end
end
