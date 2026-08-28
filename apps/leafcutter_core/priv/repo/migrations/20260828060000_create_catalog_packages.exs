defmodule Leafcutter.Repo.Migrations.CreateCatalogPackages do
  use Ecto.Migration

  def up do
    create_tables()
    create_indexes_and_constraints()
    create_sealing_functions()
    create_sealing_triggers()
  end

  def down do
    drop_sealing_triggers()
    drop_sealing_functions()

    drop(table(:package_version_endpoints))
    drop(table(:package_versions))
    drop(table(:packages))

    drop(
      unique_index(
        :operations,
        [:id, :role],
        name: :operations_id_role_index
      )
    )
  end

  defp create_tables do
    create table(:packages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:package_versions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :package_id,
        references(:packages, type: :binary_id),
        null: false
      )

      add(:version, :string, null: false)
      add(:published_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:package_version_endpoints, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :package_version_id,
        references(:package_versions, type: :binary_id),
        null: false
      )

      add(:ref, :string, null: false)
      add(:role, :string, null: false)
      add(:position, :integer)
      add(:operation_id, :binary_id, null: false)

      add(
        :contract_version_id,
        references(:contract_versions, type: :binary_id),
        null: false
      )

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end

  defp create_indexes_and_constraints do
    create(
      unique_index(
        :package_versions,
        [:package_id, :version]
      )
    )

    create(
      unique_index(
        :operations,
        [:id, :role],
        name: :operations_id_role_index
      )
    )

    create(
      unique_index(
        :package_version_endpoints,
        [:package_version_id, :ref]
      )
    )

    create(
      unique_index(
        :package_version_endpoints,
        [:package_version_id],
        name: :package_version_endpoints_one_source_index,
        where: "role = 'source'"
      )
    )

    create(
      unique_index(
        :package_version_endpoints,
        [:package_version_id, :position],
        name: :package_version_endpoints_destination_position_index,
        where: "role = 'destination'"
      )
    )

    create(
      constraint(
        :package_version_endpoints,
        :package_version_endpoints_role_valid,
        check: "role IN ('source', 'destination')"
      )
    )

    create(
      constraint(
        :package_version_endpoints,
        :package_version_endpoints_position_valid,
        check: """
        (role = 'source' AND position IS NULL)
        OR (role = 'destination' AND position IS NOT NULL)
        """
      )
    )

    execute("""
    ALTER TABLE package_version_endpoints
    ADD CONSTRAINT package_version_endpoints_operation_role_fkey
    FOREIGN KEY (operation_id, role)
    REFERENCES operations(id, role)
    """)
  end

  defp create_sealing_functions do
    execute("""
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
    """)

    execute("""
    CREATE FUNCTION reject_package_version_endpoint_content_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'package_version_endpoints content is immutable';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION allow_package_version_endpoint_only_before_publication()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      parent_published_at timestamptz;
    BEGIN
      SELECT published_at
      INTO parent_published_at
      FROM package_versions
      WHERE id = NEW.package_version_id;

      IF NOT FOUND OR parent_published_at IS NULL THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'endpoints cannot be added after PackageVersion publication';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION require_complete_package_version_publication()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      current_published_at timestamptz;
      source_count bigint;
      destination_count bigint;
    BEGIN
      SELECT published_at
      INTO current_published_at
      FROM package_versions
      WHERE id = NEW.id;

      IF current_published_at IS NULL THEN
        RAISE EXCEPTION 'package_versions must be published before commit';
      END IF;

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

      RETURN NULL;
    END;
    $$;
    """)
  end

  defp create_sealing_triggers do
    execute("""
    CREATE TRIGGER package_versions_reject_mutation
    BEFORE UPDATE OR DELETE ON package_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_package_version_content_mutation();
    """)

    execute("""
    CREATE TRIGGER package_version_endpoints_reject_mutation
    BEFORE UPDATE OR DELETE ON package_version_endpoints
    FOR EACH ROW
    EXECUTE FUNCTION reject_package_version_endpoint_content_mutation();
    """)

    execute("""
    CREATE TRIGGER package_version_endpoints_reject_after_publication
    BEFORE INSERT ON package_version_endpoints
    FOR EACH ROW
    EXECUTE FUNCTION allow_package_version_endpoint_only_before_publication();
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER package_versions_require_complete_publication
    AFTER INSERT ON package_versions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION require_complete_package_version_publication();
    """)
  end

  defp drop_sealing_triggers do
    execute(
      "DROP TRIGGER package_versions_require_complete_publication ON package_versions"
    )

    execute(
      "DROP TRIGGER package_version_endpoints_reject_after_publication " <>
        "ON package_version_endpoints"
    )

    execute(
      "DROP TRIGGER package_version_endpoints_reject_mutation " <>
        "ON package_version_endpoints"
    )

    execute("DROP TRIGGER package_versions_reject_mutation ON package_versions")
  end

  defp drop_sealing_functions do
    execute("DROP FUNCTION require_complete_package_version_publication()")

    execute(
      "DROP FUNCTION allow_package_version_endpoint_only_before_publication()"
    )

    execute("DROP FUNCTION reject_package_version_endpoint_content_mutation()")
    execute("DROP FUNCTION reject_package_version_content_mutation()")
  end
end
