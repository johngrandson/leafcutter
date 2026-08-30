defmodule Leafcutter.Repo.Migrations.RequireManifestSha256ForPackageVersions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION reject_package_version_without_manifest_sha256()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.manifest_sha256 IS NULL THEN
        RAISE EXCEPTION 'package_versions manifest_sha256 is required';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE TRIGGER package_versions_require_manifest_sha256
    BEFORE INSERT ON package_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_package_version_without_manifest_sha256();
    """)
  end

  def down do
    execute("""
    DROP TRIGGER package_versions_require_manifest_sha256 ON package_versions;
    """)

    execute("""
    DROP FUNCTION reject_package_version_without_manifest_sha256();
    """)
  end
end
