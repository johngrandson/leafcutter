defmodule Leafcutter.Repo.Migrations.AddManifestSha256ToPackageVersions do
  use Ecto.Migration

  def up do
    alter table(:package_versions) do
      add(:manifest_sha256, :string, null: true)
    end

    create(
      unique_index(
        :package_versions,
        [:manifest_sha256]
      )
    )

    create(
      constraint(
        :package_versions,
        :package_versions_manifest_sha256_format,
        check:
          "manifest_sha256 IS NULL OR " <>
            "(octet_length(manifest_sha256) = 64 " <>
            "AND manifest_sha256 !~ '[^0-9a-f]')"
      )
    )

    replace_sealing_function_with_manifest_digest()
  end

  def down do
    restore_sealing_function_without_manifest_digest()

    drop(
      constraint(
        :package_versions,
        :package_versions_manifest_sha256_format
      )
    )

    drop(
      unique_index(
        :package_versions,
        [:manifest_sha256]
      )
    )

    alter table(:package_versions) do
      remove(:manifest_sha256)
    end
  end

  defp replace_sealing_function_with_manifest_digest do
    execute("""
    CREATE OR REPLACE FUNCTION reject_package_version_content_mutation()
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
         AND OLD.manifest_sha256 IS NOT DISTINCT FROM NEW.manifest_sha256
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
  end

  defp restore_sealing_function_without_manifest_digest do
    execute("""
    CREATE OR REPLACE FUNCTION reject_package_version_content_mutation()
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
  end
end
