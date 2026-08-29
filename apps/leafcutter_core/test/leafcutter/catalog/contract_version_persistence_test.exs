defmodule Leafcutter.Catalog.ContractVersionPersistenceTest do
  use Leafcutter.DataCase, async: true

  @migrations_path Path.expand("../../../priv/repo/migrations", __DIR__)

  Code.require_file(
    Path.join(
      @migrations_path,
      "20260829150109_add_schema_to_contract_versions.exs"
    )
  )

  Code.require_file(
    Path.join(
      @migrations_path,
      "20260829160000_require_schema_for_contract_versions.exs"
    )
  )

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Contract,
    Contracts,
    ContractVersion
  }

  alias Leafcutter.Catalog.Types.SchemaDocument

  alias Leafcutter.Repo.Migrations.{
    AddSchemaToContractVersions,
    RequireSchemaForContractVersions
  }

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @add_schema_migration 20_260_829_150_109
  @require_schema_migration 20_260_829_160_000
  @migration_options [
    log: false,
    log_migrations_sql: false,
    log_migrator_sql: false
  ]

  test "round-trips object and boolean schema roots" do
    contract = contract_fixture()

    documents = [
      {"object", %{"$schema" => @dialect, "type" => "object"}},
      {"true", true},
      {"false", false}
    ]

    for {version, document} <- documents do
      contract_version = persist_version!(contract, version, document)

      assert Repo.get!(ContractVersion, contract_version.id).schema === document
    end
  end

  test "preserves an identity-only row while adding schema requirements" do
    with_migration_repo(fn schema_prefix ->
      create_legacy_contract_versions_table!()

      legacy_version_id = insert_legacy_identity!(Ecto.UUID.generate())
      migration_options = [{:prefix, schema_prefix} | @migration_options]

      assert :ok =
               Ecto.Migrator.up(
                 Repo,
                 @add_schema_migration,
                 AddSchemaToContractVersions,
                 migration_options
               )

      assert Repo.get!(ContractVersion, legacy_version_id).schema === nil

      assert :ok =
               Ecto.Migrator.up(
                 Repo,
                 @require_schema_migration,
                 RequireSchemaForContractVersions,
                 migration_options
               )

      assert Repo.get!(ContractVersion, legacy_version_id).schema === nil
    end)
  end

  test "rejects a new row without schema content" do
    contract = contract_fixture()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(
          fn ->
            insert_raw_schema!(contract.id, "missing-schema", nil)
          end,
          mode: :savepoint
        )
      end

    assert error.postgres.message ==
             "contract_versions schema is required"
  end

  test "rejects JSONB roots other than object or boolean" do
    contract = contract_fixture()

    invalid_documents = [
      {"array", "[]"},
      {"string", ~s("schema")},
      {"number", "1"},
      {"json-null", "null"}
    ]

    for {version, encoded_document} <- invalid_documents do
      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              insert_raw_schema!(
                contract.id,
                version,
                encoded_document
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint ==
               "contract_versions_schema_root_check"
    end
  end

  test "keeps the persisted schema protected by the existing mutation trigger" do
    contract = contract_fixture()

    contract_version =
      persist_version!(
        contract,
        "immutable",
        %{"$schema" => @dialect, "type" => "object"}
      )

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(
          fn ->
            contract_version
            |> Changeset.change(schema: false)
            |> Repo.update!()
          end,
          mode: :savepoint
        )
      end

    assert error.postgres.message ==
             "contract_versions content is immutable"

    assert Repo.get!(ContractVersion, contract_version.id).schema ==
             contract_version.schema
  end

  @spec persist_version!(
          Contract.t(),
          String.t(),
          SchemaDocument.t()
        ) :: ContractVersion.t()
  defp persist_version!(contract, version, schema) do
    Repo.insert!(%ContractVersion{
      contract_id: contract.id,
      version: version,
      schema: schema,
      published_at: DateTime.utc_now(:microsecond)
    })
  end

  @spec insert_raw_schema!(Contract.id(), String.t(), String.t() | nil) ::
          Postgrex.Result.t()
  defp insert_raw_schema!(contract_id, version, encoded_schema) do
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract_id)
    {:ok, dumped_version_id} = Ecto.UUID.dump(Ecto.UUID.generate())

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
      VALUES ($1, $2, $3, $4::text::jsonb, clock_timestamp(), clock_timestamp())
      """,
      [dumped_version_id, dumped_contract_id, version, encoded_schema]
    )
  end

  @spec insert_legacy_identity!(Contract.id()) :: ContractVersion.id()
  defp insert_legacy_identity!(contract_id) do
    version_id = Ecto.UUID.generate()
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract_id)
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      INSERT INTO contract_versions (
        id,
        contract_id,
        version,
        published_at,
        inserted_at
      )
      VALUES ($1, $2, 'legacy', clock_timestamp(), clock_timestamp())
      """,
      [dumped_version_id, dumped_contract_id]
    )

    version_id
  end

  @spec with_migration_repo((String.t() -> result)) :: result when result: var
  defp with_migration_repo(test) do
    schema_prefix = "contract_version_migration_#{System.unique_integer([:positive])}"
    {:ok, admin_connection} = Postgrex.start_link(postgrex_connection_options())

    Postgrex.query!(admin_connection, "CREATE SCHEMA #{schema_prefix}", [])

    try do
      {:ok, migration_repo} =
        Repo.start_link(
          name: nil,
          pool: DBConnection.ConnectionPool,
          pool_size: 2,
          after_connect: {Postgrex, :query!, ["SET search_path TO #{schema_prefix}", []]}
        )

      previous_repo = Repo.put_dynamic_repo(migration_repo)

      try do
        test.(schema_prefix)
      after
        Repo.put_dynamic_repo(previous_repo)
        Supervisor.stop(migration_repo)
      end
    after
      Postgrex.query!(admin_connection, "DROP SCHEMA #{schema_prefix} CASCADE", [])
      GenServer.stop(admin_connection)
    end
  end

  @spec postgrex_connection_options() :: keyword()
  defp postgrex_connection_options do
    Keyword.take(Repo.config(), [
      :username,
      :password,
      :hostname,
      :port,
      :database,
      :socket_options,
      :ssl
    ])
  end

  @spec create_legacy_contract_versions_table!() :: Postgrex.Result.t()
  defp create_legacy_contract_versions_table! do
    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      CREATE TABLE contract_versions (
        id uuid PRIMARY KEY,
        contract_id uuid NOT NULL,
        version varchar(255) NOT NULL,
        published_at timestamp(6) without time zone NOT NULL,
        inserted_at timestamp(6) without time zone NOT NULL
      )
      """,
      []
    )
  end

  @spec contract_fixture() :: Contract.t()
  defp contract_fixture do
    {:ok, contract} = Contracts.create(%{name: "Contract"})
    contract
  end
end
