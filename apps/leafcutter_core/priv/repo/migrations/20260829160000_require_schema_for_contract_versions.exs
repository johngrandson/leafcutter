defmodule Leafcutter.Repo.Migrations.RequireSchemaForContractVersions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION reject_contract_version_without_schema()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.schema IS NULL THEN
        RAISE EXCEPTION 'contract_versions schema is required';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE TRIGGER contract_versions_require_schema
    BEFORE INSERT ON contract_versions
    FOR EACH ROW
    EXECUTE FUNCTION reject_contract_version_without_schema();
    """)
  end

  def down do
    execute("""
    DROP TRIGGER contract_versions_require_schema ON contract_versions;
    """)

    execute("""
    DROP FUNCTION reject_contract_version_without_schema();
    """)
  end
end
