defmodule Leafcutter.Repo.Migrations.CreateIntegrations do
  use Ecto.Migration

  def up do
    create_table()
    create_indexes()
    create_integrity_function()
    create_integrity_trigger()
  end

  def down do
    execute("DROP TRIGGER integrations_reject_identity_mutation ON integrations")
    execute("DROP FUNCTION reject_integration_identity_mutation()")

    drop(table(:integrations))
  end

  defp create_table do
    create table(:integrations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :organization_id,
        references(:organizations, type: :binary_id),
        null: false
      )

      add(
        :package_id,
        references(:packages, type: :binary_id),
        null: false
      )

      add(:name, :string, null: false)
      add(:disabled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end
  end

  defp create_indexes do
    create(
      unique_index(
        :integrations,
        [:id, :organization_id],
        name: :integrations_id_organization_id_index
      )
    )
  end

  defp create_integrity_function do
    execute("""
    CREATE FUNCTION reject_integration_identity_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.id IS DISTINCT FROM NEW.id
         OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
         OR OLD.package_id IS DISTINCT FROM NEW.package_id
         OR OLD.name IS DISTINCT FROM NEW.name
         OR OLD.inserted_at IS DISTINCT FROM NEW.inserted_at THEN
        RAISE EXCEPTION 'integration identity is immutable';
      END IF;

      RETURN NEW;
    END;
    $$;
    """)
  end

  defp create_integrity_trigger do
    execute("""
    CREATE TRIGGER integrations_reject_identity_mutation
    BEFORE UPDATE ON integrations
    FOR EACH ROW
    EXECUTE FUNCTION reject_integration_identity_mutation();
    """)
  end
end
