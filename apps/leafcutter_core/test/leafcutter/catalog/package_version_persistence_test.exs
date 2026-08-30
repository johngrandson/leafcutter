defmodule Leafcutter.Catalog.PackageVersionPersistenceTest do
  use Leafcutter.DataCase, async: true

  @migrations_path Path.expand("../../../priv/repo/migrations", __DIR__)

  Code.require_file(
    Path.join(
      @migrations_path,
      "20260830070000_add_manifest_sha256_to_package_versions.exs"
    )
  )

  Code.require_file(
    Path.join(
      @migrations_path,
      "20260830071000_require_manifest_sha256_for_package_versions.exs"
    )
  )

  alias Ecto.Adapters.SQL

  alias Leafcutter.Repo.Migrations.{
    AddManifestSha256ToPackageVersions,
    RequireManifestSha256ForPackageVersions
  }

  @manifest_sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  @alternate_manifest_sha256 "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  @add_manifest_sha256_migration 20_260_830_070_000
  @require_manifest_sha256_migration 20_260_830_071_000
  @migration_options [
    log: false,
    log_migrations_sql: false,
    log_migrator_sql: false
  ]

  test "preserves legacy rows and sealing across the digest migration lifecycle" do
    with_migration_repo(fn schema_prefix ->
      create_legacy_package_version_tables!()
      create_legacy_sealing_function_and_trigger!()

      legacy_version_id = insert_legacy_version!(published?: true)
      migration_options = [{:prefix, schema_prefix} | @migration_options]

      assert :ok =
               Ecto.Migrator.up(
                 Repo,
                 @add_manifest_sha256_migration,
                 AddManifestSha256ToPackageVersions,
                 migration_options
               )

      assert fetch_manifest_sha256!(legacy_version_id) === nil

      assert :ok =
               Ecto.Migrator.up(
                 Repo,
                 @require_manifest_sha256_migration,
                 RequireManifestSha256ForPackageVersions,
                 migration_options
               )

      assert fetch_manifest_sha256!(legacy_version_id) === nil
      assert_new_null_digest_rejected!()

      version_id = insert_version_with_digest!(@manifest_sha256)
      insert_complete_endpoints!(version_id)
      publish_version!(version_id)

      assert fetch_manifest_sha256!(version_id) == @manifest_sha256
      assert_digest_mutation_rejected!(version_id)

      assert :ok =
               Ecto.Migrator.down(
                 Repo,
                 @require_manifest_sha256_migration,
                 RequireManifestSha256ForPackageVersions,
                 migration_options
               )

      assert :ok =
               Ecto.Migrator.down(
                 Repo,
                 @add_manifest_sha256_migration,
                 AddManifestSha256ToPackageVersions,
                 migration_options
               )

      refute manifest_sha256_column_exists?()

      downgraded_version_id = insert_legacy_version!(published?: false)
      insert_complete_endpoints!(downgraded_version_id)
      publish_version!(downgraded_version_id)

      assert published?(downgraded_version_id)
    end)
  end

  @spec assert_new_null_digest_rejected!() :: :ok
  defp assert_new_null_digest_rejected! do
    error =
      assert_raise Postgrex.Error, fn ->
        insert_version_with_digest!(nil)
      end

    assert error.postgres.message ==
             "package_versions manifest_sha256 is required"
  end

  @spec assert_digest_mutation_rejected!(Ecto.UUID.t()) :: :ok
  defp assert_digest_mutation_rejected!(version_id) do
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    error =
      assert_raise Postgrex.Error, fn ->
        SQL.query!(
          Repo.get_dynamic_repo(),
          "UPDATE package_versions SET manifest_sha256 = $2 WHERE id = $1",
          [dumped_version_id, @alternate_manifest_sha256]
        )
      end

    assert error.postgres.message == "package_versions content is immutable"
  end

  @spec insert_legacy_version!(published?: boolean()) :: Ecto.UUID.t()
  defp insert_legacy_version!(published?: published?) do
    version_id = Ecto.UUID.generate()
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)
    {:ok, dumped_package_id} = Ecto.UUID.dump(Ecto.UUID.generate())

    published_at = if published?, do: DateTime.utc_now(:microsecond), else: nil

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      INSERT INTO package_versions (
        id,
        package_id,
        version,
        published_at,
        inserted_at
      )
      VALUES ($1, $2, $3, $4, clock_timestamp())
      """,
      [dumped_version_id, dumped_package_id, "legacy-#{version_id}", published_at]
    )

    version_id
  end

  @spec insert_version_with_digest!(String.t() | nil) :: Ecto.UUID.t()
  defp insert_version_with_digest!(manifest_sha256) do
    version_id = Ecto.UUID.generate()
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)
    {:ok, dumped_package_id} = Ecto.UUID.dump(Ecto.UUID.generate())

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      INSERT INTO package_versions (
        id,
        package_id,
        version,
        manifest_sha256,
        published_at,
        inserted_at
      )
      VALUES ($1, $2, $3, $4, NULL, clock_timestamp())
      """,
      [dumped_version_id, dumped_package_id, "current-#{version_id}", manifest_sha256]
    )

    version_id
  end

  @spec insert_complete_endpoints!(Ecto.UUID.t()) :: :ok
  defp insert_complete_endpoints!(version_id) do
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)
    {:ok, dumped_source_id} = Ecto.UUID.dump(Ecto.UUID.generate())
    {:ok, dumped_destination_id} = Ecto.UUID.dump(Ecto.UUID.generate())

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      INSERT INTO package_version_endpoints (id, package_version_id, role)
      VALUES
        ($1, $3, 'source'),
        ($2, $3, 'destination')
      """,
      [dumped_source_id, dumped_destination_id, dumped_version_id]
    )

    :ok
  end

  @spec publish_version!(Ecto.UUID.t()) :: :ok
  defp publish_version!(version_id) do
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      UPDATE package_versions
      SET published_at = clock_timestamp()
      WHERE id = $1
      """,
      [dumped_version_id]
    )

    :ok
  end

  @spec fetch_manifest_sha256!(Ecto.UUID.t()) :: String.t() | nil
  defp fetch_manifest_sha256!(version_id) do
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    %{rows: [[manifest_sha256]]} =
      SQL.query!(
        Repo.get_dynamic_repo(),
        "SELECT manifest_sha256 FROM package_versions WHERE id = $1",
        [dumped_version_id]
      )

    manifest_sha256
  end

  @spec manifest_sha256_column_exists?() :: boolean()
  defp manifest_sha256_column_exists? do
    %{rows: [[exists?]]} =
      SQL.query!(
        Repo.get_dynamic_repo(),
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = 'package_versions'
            AND column_name = 'manifest_sha256'
        )
        """,
        []
      )

    exists?
  end

  @spec published?(Ecto.UUID.t()) :: boolean()
  defp published?(version_id) do
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    %{rows: [[published?]]} =
      SQL.query!(
        Repo.get_dynamic_repo(),
        "SELECT published_at IS NOT NULL FROM package_versions WHERE id = $1",
        [dumped_version_id]
      )

    published?
  end

  @spec with_migration_repo((String.t() -> result)) :: result when result: var
  defp with_migration_repo(test) do
    schema_prefix = "package_version_migration_#{System.unique_integer([:positive])}"
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

  @spec create_legacy_package_version_tables!() :: :ok
  defp create_legacy_package_version_tables! do
    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      CREATE TABLE package_versions (
        id uuid PRIMARY KEY,
        package_id uuid NOT NULL,
        version varchar(255) NOT NULL,
        published_at timestamp(6) without time zone,
        inserted_at timestamp(6) without time zone NOT NULL
      )
      """,
      []
    )

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      CREATE TABLE package_version_endpoints (
        id uuid PRIMARY KEY,
        package_version_id uuid NOT NULL,
        role varchar(255) NOT NULL
      )
      """,
      []
    )

    :ok
  end

  @spec create_legacy_sealing_function_and_trigger!() :: :ok
  defp create_legacy_sealing_function_and_trigger! do
    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      CREATE FUNCTION reject_package_version_content_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        source_count bigint;
        destination_count bigint;
      BEGIN
        IF TG_OP = 'UPDATE'
           AND OLD.published_at IS NULL
           AND NEW.published_at IS NOT NULL
           AND OLD.id IS NOT DISTINCT FROM NEW.id
           AND OLD.package_id IS NOT DISTINCT FROM NEW.package_id
           AND OLD.version IS NOT DISTINCT FROM NEW.version
           AND OLD.inserted_at IS NOT DISTINCT FROM NEW.inserted_at THEN
          SELECT
            count(*) FILTER (WHERE role = 'source'),
            count(*) FILTER (WHERE role = 'destination')
          INTO source_count, destination_count
          FROM package_version_endpoints
          WHERE package_version_id = NEW.id;

          IF source_count <> 1 THEN
            RAISE EXCEPTION 'package_versions require exactly one source endpoint';
          END IF;

          IF destination_count < 1 THEN
            RAISE EXCEPTION 'package_versions require at least one destination endpoint';
          END IF;

          RETURN NEW;
        END IF;

        RAISE EXCEPTION 'package_versions content is immutable';
      END;
      $$;
      """,
      []
    )

    SQL.query!(
      Repo.get_dynamic_repo(),
      """
      CREATE TRIGGER package_versions_reject_mutation
      BEFORE UPDATE OR DELETE ON package_versions
      FOR EACH ROW
      EXECUTE FUNCTION reject_package_version_content_mutation();
      """,
      []
    )

    :ok
  end
end
