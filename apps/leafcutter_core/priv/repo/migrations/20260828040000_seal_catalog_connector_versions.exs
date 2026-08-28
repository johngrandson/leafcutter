defmodule Leafcutter.Repo.Migrations.SealCatalogConnectorVersions do
  use Ecto.Migration

  def up do
    execute("DROP TRIGGER connector_versions_reject_mutation ON connector_versions")

    execute("DROP TRIGGER operations_reject_mutation ON operations")
    execute("DROP FUNCTION reject_catalog_version_content_mutation()")

    execute("ALTER TABLE connector_versions ALTER COLUMN published_at DROP NOT NULL")

    create_sealing_functions()
    create_sealing_triggers()
  end

  def down do
    execute("DROP TRIGGER connector_versions_require_publication ON connector_versions")

    execute("DROP TRIGGER operations_reject_after_publication ON operations")

    execute("DROP TRIGGER connector_versions_reject_mutation ON connector_versions")

    execute("DROP TRIGGER operations_reject_mutation ON operations")
    execute("DROP FUNCTION require_connector_version_publication()")
    execute("DROP FUNCTION allow_operation_only_before_publication()")
    execute("DROP FUNCTION reject_operation_content_mutation()")
    execute("DROP FUNCTION reject_connector_version_content_mutation()")

    execute("ALTER TABLE connector_versions ALTER COLUMN published_at SET NOT NULL")

    create_original_mutation_function()
    create_original_mutation_triggers()
  end

  defp create_sealing_functions do
    execute("""
    CREATE FUNCTION reject_connector_version_content_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF TG_OP = 'UPDATE' THEN
        IF OLD.published_at IS NULL
           AND NEW.published_at IS NOT NULL
           AND OLD.id IS NOT DISTINCT FROM NEW.id
           AND OLD.connector_id IS NOT DISTINCT FROM NEW.connector_id
           AND OLD.version IS NOT DISTINCT FROM NEW.version
           AND OLD.inserted_at IS NOT DISTINCT FROM NEW.inserted_at THEN
          RETURN NEW;
        END IF;
      END IF;

      RAISE EXCEPTION 'connector_versions content is immutable';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION reject_operation_content_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'operations content is immutable';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION allow_operation_only_before_publication()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      parent_published_at timestamptz;
    BEGIN
      SELECT published_at
      INTO parent_published_at
      FROM connector_versions
      WHERE id = NEW.connector_version_id;

      IF NOT FOUND OR parent_published_at IS NULL THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'operations cannot be added after ConnectorVersion publication';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION require_connector_version_publication()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM connector_versions
        WHERE id = NEW.id
          AND published_at IS NULL
      ) THEN
        RAISE EXCEPTION 'connector_versions must be published before commit';
      END IF;

      RETURN NULL;
    END;
    $$;
    """)
  end

  defp create_sealing_triggers do
    execute("""
    CREATE TRIGGER connector_versions_reject_mutation
    BEFORE UPDATE OR DELETE ON connector_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_connector_version_content_mutation();
    """)

    execute("""
    CREATE TRIGGER operations_reject_mutation
    BEFORE UPDATE OR DELETE ON operations
    FOR EACH ROW
    EXECUTE FUNCTION reject_operation_content_mutation();
    """)

    execute("""
    CREATE TRIGGER operations_reject_after_publication
    BEFORE INSERT ON operations
    FOR EACH ROW
    EXECUTE FUNCTION allow_operation_only_before_publication();
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER connector_versions_require_publication
    AFTER INSERT ON connector_versions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION require_connector_version_publication();
    """)
  end

  defp create_original_mutation_function do
    execute("""
    CREATE FUNCTION reject_catalog_version_content_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION '% content is immutable', TG_TABLE_NAME;
      RETURN NEW;
    END;
    $$;
    """)
  end

  defp create_original_mutation_triggers do
    execute("""
    CREATE TRIGGER connector_versions_reject_mutation
    BEFORE UPDATE OR DELETE ON connector_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_catalog_version_content_mutation();
    """)

    execute("""
    CREATE TRIGGER operations_reject_mutation
    BEFORE UPDATE OR DELETE ON operations
    FOR EACH ROW
    EXECUTE FUNCTION reject_catalog_version_content_mutation();
    """)
  end
end
