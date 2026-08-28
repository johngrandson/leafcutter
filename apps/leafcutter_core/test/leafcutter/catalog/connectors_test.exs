defmodule Leafcutter.Catalog.ConnectorsTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Connector,
    Connectors,
    ConnectorVersion,
    Operation
  }

  describe "create/1" do
    test "persists a global Connector identity" do
      assert {:ok, %Connector{} = connector} =
               Connectors.create(%{
                 name: "Salesforce",
                 id: Ecto.UUID.generate()
               })

      assert connector.name == "Salesforce"
      assert {:ok, connector.id} == Ecto.UUID.cast(connector.id)
      assert %DateTime{} = connector.inserted_at
      assert %DateTime{} = connector.updated_at
    end

    test "rejects missing, blank, and oversized names" do
      invalid_attrs = [
        %{},
        %{name: ""},
        %{name: "   "},
        %{name: String.duplicate("a", 256)}
      ]

      for attrs <- invalid_attrs do
        assert {:error, changeset} = Connectors.create(attrs)
        assert %{name: [_ | _]} = errors_on(changeset)
      end
    end
  end

  describe "get/1" do
    test "returns a persisted Connector identity without preloading versions" do
      connector = connector_fixture()

      assert {:ok, fetched} = Connectors.get(connector.id)
      assert fetched.id == connector.id
      assert fetched.name == connector.name
      assert %Ecto.Association.NotLoaded{} = fetched.versions
    end

    test "returns a named error when the Connector does not exist" do
      assert {:error, :not_found} =
               Connectors.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "publish_version/2" do
    test "publishes an opaque version and its Operations atomically" do
      connector = connector_fixture()

      assert {:ok, %ConnectorVersion{} = connector_version} =
               Connectors.publish_version(
                 connector.id,
                 %{
                   version: "release-2026.08",
                   published_at: ~U[2025-01-01 00:00:00.000000Z],
                   operations: [
                     %{ref: "list_accounts", role: :source},
                     %{"ref" => "create_contact", "role" => "destination"}
                   ]
                 }
               )

      assert connector_version.connector == connector
      assert connector_version.version == "release-2026.08"
      assert connector_version.published_at != ~U[2025-01-01 00:00:00.000000Z]
      assert length(connector_version.operations) == 2

      assert [
               %Operation{ref: "list_accounts", role: :source},
               %Operation{ref: "create_contact", role: :destination}
             ] = connector_version.operations

      assert Repo.aggregate(ConnectorVersion, :count) == 1
      assert Repo.aggregate(Operation, :count) == 2
    end

    test "allows a ConnectorVersion with no Operations" do
      connector = connector_fixture()

      assert {:ok, connector_version} =
               Connectors.publish_version(connector.id, %{
                 version: "metadata-only"
               })

      assert connector_version.operations == []
    end

    test "returns connector_not_found without persisting a version" do
      assert {:error, :connector_not_found} =
               Connectors.publish_version(
                 "00000000-0000-0000-0000-000000000000",
                 %{version: "1", operations: []}
               )

      assert Repo.aggregate(ConnectorVersion, :count) == 0
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "rejects invalid version and Operation shapes" do
      connector = connector_fixture()

      invalid_attrs = [
        %{},
        %{version: ""},
        %{version: "1", operations: :invalid},
        %{version: "1", operations: [:invalid]}
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} =
                 Connectors.publish_version(connector.id, attrs)

        refute changeset.valid?
      end

      assert Repo.aggregate(ConnectorVersion, :count) == 0
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "rolls back the version when one Operation is invalid" do
      connector = connector_fixture()

      assert {:error, %Changeset{} = changeset} =
               Connectors.publish_version(
                 connector.id,
                 %{
                   version: "1",
                   operations: [
                     %{ref: "valid", role: :source},
                     %{ref: "invalid", role: :unknown}
                   ]
                 }
               )

      refute changeset.valid?
      assert Repo.aggregate(ConnectorVersion, :count) == 0
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "rolls back duplicate Operation refs" do
      connector = connector_fixture()

      assert {:error, %Changeset{} = changeset} =
               Connectors.publish_version(
                 connector.id,
                 %{
                   version: "1",
                   operations: [
                     %{ref: "same", role: :source},
                     %{ref: "same", role: :destination}
                   ]
                 }
               )

      assert %{connector_version_id: [_ | _]} = errors_on(changeset)
      assert Repo.aggregate(ConnectorVersion, :count) == 0
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "enforces version uniqueness within one Connector" do
      first_connector = connector_fixture("First")
      second_connector = connector_fixture("Second")

      assert {:ok, _version} =
               Connectors.publish_version(first_connector.id, %{version: "1"})

      assert {:error, %Changeset{} = changeset} =
               Connectors.publish_version(first_connector.id, %{version: "1"})

      assert %{connector_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _version} =
               Connectors.publish_version(second_connector.id, %{version: "1"})
    end
  end

  describe "database immutability" do
    test "rejects ConnectorVersion updates and Operation deletes" do
      connector = connector_fixture()

      assert {:ok, connector_version} =
               Connectors.publish_version(
                 connector.id,
                 %{
                   version: "1",
                   operations: [
                     %{ref: "read", role: :source}
                   ]
                 }
               )

      [operation] = connector_version.operations

      version_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              connector_version
              |> Changeset.change(version: "changed")
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert version_error.postgres.message ==
               "connector_versions content is immutable"

      operation_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn -> Repo.delete!(operation) end,
            mode: :savepoint
          )
        end

      assert operation_error.postgres.message ==
               "operations content is immutable"

      assert Repo.get!(ConnectorVersion, connector_version.id).version == "1"
      assert Repo.get!(Operation, operation.id).ref == "read"
    end
  end

  @spec connector_fixture(String.t()) :: Connector.t()
  defp connector_fixture(name \\ "Connector") do
    {:ok, connector} = Connectors.create(%{name: name})
    connector
  end
end
