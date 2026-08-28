defmodule Leafcutter.ConnectionsTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset

  alias Leafcutter.Catalog.Connectors, as: CatalogConnectors
  alias Leafcutter.Connections

  alias Leafcutter.Connections.{
    Connection,
    SecretVersion,
    Secrets
  }

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments

  @typep scope_fixture :: %{
           organization: Leafcutter.Organizations.Organization.t(),
           environment: Leafcutter.Organizations.Environment.t(),
           connector: Leafcutter.Catalog.Connector.t()
         }

  describe "create/1" do
    test "persists scoped non-sensitive config with an optional exact binding" do
      scope = scope_fixture()
      secret_version = secret_version_fixture(scope)

      assert {:ok, %Connection{} = connection} =
               Connections.create(%{
                 organization_id: scope.organization.id,
                 environment_id: scope.environment.id,
                 connector_id: scope.connector.id,
                 name: "CRM",
                 config: %{
                   :base_url => "https://example.test",
                   "options" => [%{timeout: 30}]
                 },
                 secret_version_id: secret_version.id,
                 id: Ecto.UUID.generate(),
                 disabled_at: ~U[2025-01-01 00:00:00.000000Z],
                 raw_secret: "not persisted"
               })

      assert connection.organization_id == scope.organization.id
      assert connection.environment_id == scope.environment.id
      assert connection.connector_id == scope.connector.id
      assert connection.name == "CRM"

      assert connection.config == %{
               "base_url" => "https://example.test",
               "options" => [%{"timeout" => 30}]
             }

      assert connection.secret_version_id == secret_version.id
      assert connection.disabled_at == nil
      assert %Ecto.Association.NotLoaded{} = connection.secret_version
      assert {:ok, connection.id} == Ecto.UUID.cast(connection.id)
      refute Map.has_key?(Map.from_struct(connection), :raw_secret)
    end

    test "accepts string-keyed attributes and defaults config to an empty object" do
      scope = scope_fixture()

      assert {:ok, connection} =
               Connections.create(%{
                 "organization_id" => scope.organization.id,
                 "environment_id" => scope.environment.id,
                 "connector_id" => scope.connector.id,
                 "name" => "Warehouse"
               })

      assert connection.config == %{}
      assert connection.secret_version_id == nil
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 names" do
      scope = scope_fixture()

      invalid_attrs = [
        %{},
        connection_attrs(scope, name: ""),
        connection_attrs(scope, name: "   "),
        connection_attrs(scope, name: String.duplicate("a", 256)),
        connection_attrs(scope, name: <<255>>)
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} = Connections.create(attrs)
        refute changeset.valid?
      end

      assert Repo.aggregate(Connection, :count) == 0
    end

    test "rejects values that are not JSON objects with compatible nested values" do
      scope = scope_fixture()

      invalid_configs = [
        [],
        %URI{scheme: "https"},
        %{1 => "invalid key"},
        %{:key => 1, "key" => 2},
        %{"pid" => self()},
        %{"invalid_utf8" => <<255>>}
      ]

      for config <- invalid_configs do
        assert {:error, %Changeset{} = changeset} =
                 Connections.create(connection_attrs(scope, config: config))

        assert %{config: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(Connection, :count) == 0
    end

    test "returns named errors for invalid or inactive upstream authorities" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")

      assert {:error, :organization_not_found} =
               Connections.create(
                 connection_attrs(first_scope,
                   organization_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_not_found} =
               Connections.create(
                 connection_attrs(first_scope,
                   environment_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_scope_mismatch} =
               Connections.create(
                 connection_attrs(first_scope,
                   environment_id: second_scope.environment.id
                 )
               )

      assert {:error, :connector_not_found} =
               Connections.create(
                 connection_attrs(first_scope,
                   connector_id: Ecto.UUID.generate()
                 )
               )

      assert {:ok, _disabled_environment} =
               Environments.disable(first_scope.environment.id)

      assert {:error, :environment_disabled} =
               Connections.create(connection_attrs(first_scope))

      assert {:ok, _disabled_organization} =
               Organizations.disable(second_scope.organization.id)

      assert {:error, :organization_disabled} =
               Connections.create(connection_attrs(second_scope))
    end

    test "rejects an absent or cross-scope SecretVersion binding" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")
      second_secret_version = secret_version_fixture(second_scope)

      assert {:error, :secret_version_not_found} =
               Connections.create(
                 connection_attrs(first_scope,
                   secret_version_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :secret_version_scope_mismatch} =
               Connections.create(
                 connection_attrs(first_scope,
                   secret_version_id: second_secret_version.id
                 )
               )

      assert Repo.aggregate(Connection, :count) == 0
    end
  end

  describe "get/1" do
    test "returns active and disabled Connections without preloading bindings" do
      scope = scope_fixture()
      {:ok, connection} = Connections.create(connection_attrs(scope))

      assert {:ok, fetched} = Connections.get(connection.id)
      assert fetched.id == connection.id
      assert %Ecto.Association.NotLoaded{} = fetched.secret_version

      assert {:ok, disabled} = Connections.disable(connection.id)
      assert {:ok, fetched_disabled} = Connections.get(disabled.id)
      assert fetched_disabled.disabled_at == disabled.disabled_at
    end

    test "returns a named error when the Connection does not exist" do
      assert {:error, :not_found} =
               Connections.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "update/2" do
    test "replaces config and exact binding while preserving immutable identity" do
      scope = scope_fixture()
      first_secret_version = secret_version_fixture(scope, "1")
      second_secret_version = secret_version_fixture(scope, "2", first_secret_version)

      {:ok, connection} =
        Connections.create(
          connection_attrs(scope,
            config: %{"old" => true},
            secret_version_id: first_secret_version.id
          )
        )

      assert {:ok, updated} =
               Connections.update(connection.id, %{
                 config: %{nested: %{value: 2}},
                 secret_version_id: second_secret_version.id,
                 organization_id: Ecto.UUID.generate(),
                 environment_id: Ecto.UUID.generate(),
                 connector_id: Ecto.UUID.generate(),
                 name: "Changed",
                 disabled_at: ~U[2025-01-01 00:00:00.000000Z]
               })

      assert updated.config == %{"nested" => %{"value" => 2}}
      assert updated.secret_version_id == second_secret_version.id
      assert updated.organization_id == connection.organization_id
      assert updated.environment_id == connection.environment_id
      assert updated.connector_id == connection.connector_id
      assert updated.name == connection.name
      assert updated.disabled_at == nil

      assert {:ok, unbound} =
               Connections.update(connection.id, %{secret_version_id: nil})

      assert unbound.secret_version_id == nil
    end

    test "does not persist an invalid config or incompatible binding" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")
      second_secret_version = secret_version_fixture(second_scope)

      {:ok, connection} =
        Connections.create(
          connection_attrs(first_scope, config: %{"stable" => true})
        )

      assert {:error, %Changeset{} = changeset} =
               Connections.update(connection.id, %{config: []})

      assert %{config: [_ | _]} = errors_on(changeset)

      assert {:error, :secret_version_scope_mismatch} =
               Connections.update(connection.id, %{
                 secret_version_id: second_secret_version.id
               })

      assert {:ok, persisted} = Connections.get(connection.id)
      assert persisted.config == %{"stable" => true}
      assert persisted.secret_version_id == nil
    end

    test "returns named errors for a missing Connection or disabled parent" do
      scope = scope_fixture()

      assert {:error, :not_found} =
               Connections.update(
                 "00000000-0000-0000-0000-000000000000",
                 %{config: %{}}
               )

      {:ok, connection} = Connections.create(connection_attrs(scope))
      assert {:ok, _environment} = Environments.disable(scope.environment.id)

      assert {:error, :environment_disabled} =
               Connections.update(connection.id, %{config: %{}})
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      scope = scope_fixture()
      {:ok, connection} = Connections.create(connection_attrs(scope))

      assert {:ok, first_disable} = Connections.disable(connection.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = Connections.disable(connection.id)
      assert second_disable.disabled_at == first_disable.disabled_at
    end

    test "returns a named error for a missing Connection or disabled parent" do
      assert {:error, :not_found} =
               Connections.disable("00000000-0000-0000-0000-000000000000")

      scope = scope_fixture()
      {:ok, connection} = Connections.create(connection_attrs(scope))
      assert {:ok, _organization} = Organizations.disable(scope.organization.id)

      assert {:error, :organization_disabled} =
               Connections.disable(connection.id)
    end
  end

  describe "database invariants" do
    test "rejects changing Connection identity fields directly" do
      scope = scope_fixture()
      {:ok, connection} = Connections.create(connection_attrs(scope))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              connection
              |> Changeset.change(name: "Changed")
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message == "connection identity is immutable"
    end

    test "rejects an incompatible Organization and Environment directly" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")

      changeset =
        Connection.create_changeset(
          %Connection{},
          connection_attrs(first_scope,
            environment_id: second_scope.environment.id
          )
        )

      assert {:error, persisted_changeset} = Repo.insert(changeset)
      assert %{environment_id: [_ | _]} = errors_on(persisted_changeset)
    end

    test "rejects a cross-scope SecretVersion directly" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")
      second_secret_version = secret_version_fixture(second_scope)

      changeset =
        Connection.create_changeset(
          %Connection{},
          connection_attrs(first_scope,
            secret_version_id: second_secret_version.id
          )
        )

      assert {:error, persisted_changeset} = Repo.insert(changeset)
      assert %{secret_version_id: [_ | _]} = errors_on(persisted_changeset)
    end

    test "rejects a non-object config directly" do
      scope = scope_fixture()

      dumped_ids =
        Enum.map(
          [
            Ecto.UUID.generate(),
            scope.organization.id,
            scope.environment.id,
            scope.connector.id
          ],
          fn id ->
            {:ok, dumped_id} = Ecto.UUID.dump(id)
            dumped_id
          end
        )

      [connection_id, organization_id, environment_id, connector_id] =
        dumped_ids

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              SQL.query!(
                Repo,
                """
                INSERT INTO connections (
                  id,
                  organization_id,
                  environment_id,
                  connector_id,
                  name,
                  config,
                  inserted_at,
                  updated_at
                )
                VALUES ($1, $2, $3, $4, 'Invalid', '[]'::jsonb, clock_timestamp(), clock_timestamp())
                """,
                [
                  connection_id,
                  organization_id,
                  environment_id,
                  connector_id
                ]
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint == "connections_config_object"
    end
  end

  @spec scope_fixture(String.t()) :: scope_fixture()
  defp scope_fixture(prefix \\ "Scope") do
    {:ok, organization} = Organizations.create(%{name: "#{prefix} Organization"})

    {:ok, environment} =
      Environments.create(%{
        organization_id: organization.id,
        name: "Production"
      })

    {:ok, connector} = CatalogConnectors.create(%{name: "#{prefix} Connector"})

    %{
      organization: organization,
      environment: environment,
      connector: connector
    }
  end

  @spec connection_attrs(scope_fixture(), keyword()) :: map()
  defp connection_attrs(scope, overrides \\ []) do
    %{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      connector_id: scope.connector.id,
      name: "Connection",
      config: %{}
    }
    |> Map.merge(Map.new(overrides))
  end

  @spec secret_version_fixture(scope_fixture(), String.t(), SecretVersion.t() | nil) ::
          SecretVersion.t()
  defp secret_version_fixture(scope, version \\ "1", existing_version \\ nil)

  defp secret_version_fixture(scope, version, nil) do
    {:ok, secret} =
      Secrets.create(%{
        organization_id: scope.organization.id,
        environment_id: scope.environment.id,
        name: "Credentials"
      })

    {:ok, secret_version} =
      Secrets.create_version(%{
        secret_id: secret.id,
        version: version
      })

    secret_version
  end

  defp secret_version_fixture(_scope, version, existing_version) do
    {:ok, secret_version} =
      Secrets.create_version(%{
        secret_id: existing_version.secret_id,
        version: version
      })

    secret_version
  end
end
