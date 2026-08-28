defmodule Leafcutter.Repo.Migrations.CreateConnections do
  use Ecto.Migration

  def up do
    create_environment_scope_index()
    create_tables()
    create_indexes_and_constraints()
    create_integrity_functions()
    create_integrity_triggers()
  end

  def down do
    drop_integrity_triggers()
    drop_integrity_functions()

    drop(table(:connections))
    drop(table(:secret_versions))
    drop(table(:secrets))

    drop(
      unique_index(
        :environments,
        [:organization_id, :id],
        name: :environments_organization_id_id_index
      )
    )
  end

  defp create_environment_scope_index do
    create(
      unique_index(
        :environments,
        [:organization_id, :id],
        name: :environments_organization_id_id_index
      )
    )
  end

  defp create_tables do
    create table(:secrets, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :organization_id,
        references(:organizations, type: :binary_id),
        null: false
      )

      add(
        :environment_id,
        references(:environments, type: :binary_id),
        null: false
      )

      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:secret_versions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :secret_id,
        references(:secrets, type: :binary_id),
        null: false
      )

      add(:version, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:connections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :organization_id,
        references(:organizations, type: :binary_id),
        null: false
      )

      add(
        :environment_id,
        references(:environments, type: :binary_id),
        null: false
      )

      add(
        :connector_id,
        references(:connectors, type: :binary_id),
        null: false
      )

      add(:name, :string, null: false)
      add(:config, :map, null: false, default: %{})

      add(
        :secret_version_id,
        references(:secret_versions, type: :binary_id)
      )

      add(:disabled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end
  end

  defp create_indexes_and_constraints do
    create(
      unique_index(
        :secret_versions,
        [:secret_id, :version]
      )
    )

    create(
      constraint(
        :connections,
        :connections_config_object,
        check: "jsonb_typeof(config) = 'object'"
      )
    )

    execute("""
    ALTER TABLE secrets
    ADD CONSTRAINT secrets_organization_environment_fkey
    FOREIGN KEY (organization_id, environment_id)
    REFERENCES environments(organization_id, id)
    """)

    execute("""
    ALTER TABLE connections
    ADD CONSTRAINT connections_organization_environment_fkey
    FOREIGN KEY (organization_id, environment_id)
    REFERENCES environments(organization_id, id)
    """)
  end

  defp create_integrity_functions do
    execute("""
    CREATE FUNCTION reject_secret_version_content_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'secret_versions content is immutable';
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION reject_secret_scope_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
         OR OLD.environment_id IS DISTINCT FROM NEW.environment_id THEN
        RAISE EXCEPTION 'secret scope is immutable';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION reject_connection_identity_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.id IS DISTINCT FROM NEW.id
         OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
         OR OLD.environment_id IS DISTINCT FROM NEW.environment_id
         OR OLD.connector_id IS DISTINCT FROM NEW.connector_id
         OR OLD.name IS DISTINCT FROM NEW.name
         OR OLD.inserted_at IS DISTINCT FROM NEW.inserted_at THEN
        RAISE EXCEPTION 'connection identity is immutable';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION validate_connection_secret_version_scope()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      bound_organization_id uuid;
      bound_environment_id uuid;
    BEGIN
      IF NEW.secret_version_id IS NULL THEN
        RETURN NEW;
      END IF;

      SELECT secret.organization_id, secret.environment_id
      INTO bound_organization_id, bound_environment_id
      FROM secret_versions AS secret_version
      JOIN secrets AS secret ON secret.id = secret_version.secret_id
      WHERE secret_version.id = NEW.secret_version_id;

      IF NOT FOUND THEN
        RETURN NEW;
      END IF;

      IF bound_organization_id IS DISTINCT FROM NEW.organization_id
         OR bound_environment_id IS DISTINCT FROM NEW.environment_id THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'connections_secret_version_scope',
          MESSAGE = 'SecretVersion must belong to the Connection organization and environment';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION require_connection_secret_version_scope()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.secret_version_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1
           FROM secret_versions AS secret_version
           JOIN secrets AS secret ON secret.id = secret_version.secret_id
           WHERE secret_version.id = NEW.secret_version_id
             AND secret.organization_id = NEW.organization_id
             AND secret.environment_id = NEW.environment_id
         ) THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'connections_secret_version_scope',
          MESSAGE = 'SecretVersion must belong to the Connection organization and environment';
      END IF;

      RETURN NULL;
    END;
    $$;
    """)
  end

  defp create_integrity_triggers do
    execute("""
    CREATE TRIGGER secret_versions_reject_mutation
    BEFORE UPDATE OR DELETE ON secret_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_secret_version_content_mutation();
    """)

    execute("""
    CREATE TRIGGER secrets_reject_scope_mutation
    BEFORE UPDATE OF organization_id, environment_id ON secrets
    FOR EACH ROW
    EXECUTE FUNCTION reject_secret_scope_mutation();
    """)

    execute("""
    CREATE TRIGGER connections_reject_identity_mutation
    BEFORE UPDATE ON connections
    FOR EACH ROW
    EXECUTE FUNCTION reject_connection_identity_mutation();
    """)

    execute("""
    CREATE TRIGGER connections_validate_secret_version_scope
    BEFORE INSERT OR UPDATE OF organization_id, environment_id, secret_version_id
    ON connections
    FOR EACH ROW
    EXECUTE FUNCTION validate_connection_secret_version_scope();
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER connections_require_secret_version_scope
    AFTER INSERT OR UPDATE ON connections
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION require_connection_secret_version_scope();
    """)
  end

  defp drop_integrity_triggers do
    execute(
      "DROP TRIGGER connections_require_secret_version_scope ON connections"
    )

    execute(
      "DROP TRIGGER connections_validate_secret_version_scope ON connections"
    )

    execute("DROP TRIGGER connections_reject_identity_mutation ON connections")

    execute("DROP TRIGGER secrets_reject_scope_mutation ON secrets")
    execute("DROP TRIGGER secret_versions_reject_mutation ON secret_versions")
  end

  defp drop_integrity_functions do
    execute("DROP FUNCTION require_connection_secret_version_scope()")
    execute("DROP FUNCTION validate_connection_secret_version_scope()")
    execute("DROP FUNCTION reject_connection_identity_mutation()")
    execute("DROP FUNCTION reject_secret_scope_mutation()")
    execute("DROP FUNCTION reject_secret_version_content_mutation()")
  end
end
