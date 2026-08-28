defmodule Leafcutter.Repo.Migrations.CreateEnvironmentDeployments do
  use Ecto.Migration

  def up do
    create_tables()
    create_indexes_and_constraints()
    create_integrity_functions()
    create_integrity_triggers()
  end

  def down do
    drop_integrity_triggers()
    drop_integrity_functions()

    drop(table(:environment_deployment_bindings))
    drop(table(:environment_deployments))
  end

  defp create_tables do
    create table(:environment_deployments, primary_key: false) do
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
        :integration_id,
        references(:integrations, type: :binary_id),
        null: false
      )

      add(
        :package_version_id,
        references(:package_versions, type: :binary_id),
        null: false
      )

      add(:promotable_config, :map, null: false, default: %{})
      add(:local_config, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create table(:environment_deployment_bindings, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :environment_deployment_id,
        references(:environment_deployments, type: :binary_id),
        null: false
      )

      add(:ref, :string, null: false)

      add(
        :connection_id,
        references(:connections, type: :binary_id),
        null: false
      )

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end

  defp create_indexes_and_constraints do
    create(
      unique_index(
        :environment_deployments,
        [:integration_id, :environment_id]
      )
    )

    create(
      unique_index(
        :environment_deployment_bindings,
        [:environment_deployment_id, :ref],
        name: :environment_deployment_bindings_deployment_id_ref_index
      )
    )

    create(
      constraint(
        :environment_deployments,
        :environment_deployments_promotable_config_object,
        check: "jsonb_typeof(promotable_config) = 'object'"
      )
    )

    create(
      constraint(
        :environment_deployments,
        :environment_deployments_local_config_object,
        check: "jsonb_typeof(local_config) = 'object'"
      )
    )

    execute("""
    ALTER TABLE environment_deployments
    ADD CONSTRAINT environment_deployments_organization_environment_fkey
    FOREIGN KEY (organization_id, environment_id)
    REFERENCES environments(organization_id, id)
    """)

    execute("""
    ALTER TABLE environment_deployments
    ADD CONSTRAINT environment_deployments_integration_organization_fkey
    FOREIGN KEY (integration_id, organization_id)
    REFERENCES integrations(id, organization_id)
    """)
  end

  defp create_integrity_functions do
    execute("""
    CREATE FUNCTION reject_environment_deployment_identity_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.id IS DISTINCT FROM NEW.id
         OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
         OR OLD.environment_id IS DISTINCT FROM NEW.environment_id
         OR OLD.integration_id IS DISTINCT FROM NEW.integration_id
         OR OLD.inserted_at IS DISTINCT FROM NEW.inserted_at THEN
        RAISE EXCEPTION 'environment deployment identity is immutable';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION assert_environment_deployment_integrity(target_deployment_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      deployment_organization_id uuid;
      deployment_environment_id uuid;
      integration_package_id uuid;
      version_package_id uuid;
    BEGIN
      SELECT
        deployment.organization_id,
        deployment.environment_id,
        integration.package_id,
        package_version.package_id
      INTO
        deployment_organization_id,
        deployment_environment_id,
        integration_package_id,
        version_package_id
      FROM environment_deployments AS deployment
      JOIN integrations AS integration
        ON integration.id = deployment.integration_id
      JOIN package_versions AS package_version
        ON package_version.id = deployment.package_version_id
      WHERE deployment.id = target_deployment_id;

      IF NOT FOUND THEN
        RETURN;
      END IF;

      IF integration_package_id IS DISTINCT FROM version_package_id THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'environment_deployments_package_version_match',
          MESSAGE = 'PackageVersion must belong to the Integration Package';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM (
          (
            SELECT endpoint.ref
            FROM package_version_endpoints AS endpoint
            JOIN environment_deployments AS deployment
              ON deployment.package_version_id = endpoint.package_version_id
            WHERE deployment.id = target_deployment_id
            EXCEPT
            SELECT binding.ref
            FROM environment_deployment_bindings AS binding
            WHERE binding.environment_deployment_id = target_deployment_id
          )
          UNION ALL
          (
            SELECT binding.ref
            FROM environment_deployment_bindings AS binding
            WHERE binding.environment_deployment_id = target_deployment_id
            EXCEPT
            SELECT endpoint.ref
            FROM package_version_endpoints AS endpoint
            JOIN environment_deployments AS deployment
              ON deployment.package_version_id = endpoint.package_version_id
            WHERE deployment.id = target_deployment_id
          )
        ) AS binding_mismatch
      ) THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'environment_deployments_complete_bindings',
          MESSAGE = 'bindings must match every PackageVersion endpoint exactly';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM environment_deployment_bindings AS binding
        JOIN connections AS connection
          ON connection.id = binding.connection_id
        WHERE binding.environment_deployment_id = target_deployment_id
          AND (
            connection.organization_id IS DISTINCT FROM deployment_organization_id
            OR connection.environment_id IS DISTINCT FROM deployment_environment_id
          )
      ) THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'environment_deployments_connection_scope',
          MESSAGE = 'Connection must belong to the deployment organization and environment';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM environment_deployment_bindings AS binding
        JOIN environment_deployments AS deployment
          ON deployment.id = binding.environment_deployment_id
        JOIN package_version_endpoints AS endpoint
          ON endpoint.package_version_id = deployment.package_version_id
         AND endpoint.ref = binding.ref
        JOIN operations AS operation
          ON operation.id = endpoint.operation_id
        JOIN connector_versions AS connector_version
          ON connector_version.id = operation.connector_version_id
        JOIN connections AS connection
          ON connection.id = binding.connection_id
        WHERE binding.environment_deployment_id = target_deployment_id
          AND connection.connector_id IS DISTINCT FROM connector_version.connector_id
      ) THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          CONSTRAINT = 'environment_deployments_connector_compatibility',
          MESSAGE = 'Connection Connector must match the endpoint ConnectorVersion';
      END IF;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION require_environment_deployment_integrity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      PERFORM assert_environment_deployment_integrity(NEW.id);
      RETURN NULL;
    END;
    $$;
    """)

    execute("""
    CREATE FUNCTION require_environment_deployment_binding_integrity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      target_deployment_id uuid;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        target_deployment_id := OLD.environment_deployment_id;
      ELSE
        target_deployment_id := NEW.environment_deployment_id;
      END IF;

      IF TG_OP = 'UPDATE'
         AND OLD.environment_deployment_id IS DISTINCT FROM NEW.environment_deployment_id THEN
        PERFORM assert_environment_deployment_integrity(
          OLD.environment_deployment_id
        );
      END IF;

      PERFORM assert_environment_deployment_integrity(target_deployment_id);
      RETURN NULL;
    END;
    $$;
    """)
  end

  defp create_integrity_triggers do
    execute("""
    CREATE TRIGGER environment_deployments_reject_identity_mutation
    BEFORE UPDATE ON environment_deployments
    FOR EACH ROW
    EXECUTE FUNCTION reject_environment_deployment_identity_mutation();
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER environment_deployments_require_integrity
    AFTER INSERT OR UPDATE ON environment_deployments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION require_environment_deployment_integrity();
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER environment_deployment_bindings_require_integrity
    AFTER INSERT OR UPDATE OR DELETE ON environment_deployment_bindings
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION require_environment_deployment_binding_integrity();
    """)
  end

  defp drop_integrity_triggers do
    execute(
      "DROP TRIGGER environment_deployment_bindings_require_integrity " <>
        "ON environment_deployment_bindings"
    )

    execute(
      "DROP TRIGGER environment_deployments_require_integrity " <>
        "ON environment_deployments"
    )

    execute(
      "DROP TRIGGER environment_deployments_reject_identity_mutation " <>
        "ON environment_deployments"
    )
  end

  defp drop_integrity_functions do
    execute("DROP FUNCTION require_environment_deployment_binding_integrity()")
    execute("DROP FUNCTION require_environment_deployment_integrity()")
    execute("DROP FUNCTION assert_environment_deployment_integrity(uuid)")
    execute("DROP FUNCTION reject_environment_deployment_identity_mutation()")
  end
end
