defmodule Leafcutter.Repo.Migrations.CreateCatalogConnectors do
  use Ecto.Migration

  def change do
    create table(:connectors, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:connector_versions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :connector_id,
        references(:connectors, type: :binary_id),
        null: false
      )

      add(:version, :string, null: false)
      add(:published_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :connector_versions,
        [:connector_id, :version]
      )
    )

    create table(:operations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :connector_version_id,
        references(:connector_versions, type: :binary_id),
        null: false
      )

      add(:ref, :string, null: false)
      add(:role, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :operations,
        [:connector_version_id, :ref]
      )
    )

    create(
      constraint(:operations, :operations_role_valid, check: "role IN ('source', 'destination')")
    )

    execute(
      """
      CREATE FUNCTION reject_catalog_version_content_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION '% content is immutable', TG_TABLE_NAME;
        RETURN NEW;
      END;
      $$;
      """,
      "DROP FUNCTION reject_catalog_version_content_mutation();"
    )

    execute(
      """
      CREATE TRIGGER connector_versions_reject_mutation
      BEFORE UPDATE OR DELETE ON connector_versions
      FOR EACH ROW
      EXECUTE FUNCTION reject_catalog_version_content_mutation();
      """,
      "DROP TRIGGER connector_versions_reject_mutation ON connector_versions;"
    )

    execute(
      """
      CREATE TRIGGER operations_reject_mutation
      BEFORE UPDATE OR DELETE ON operations
      FOR EACH ROW
      EXECUTE FUNCTION reject_catalog_version_content_mutation();
      """,
      "DROP TRIGGER operations_reject_mutation ON operations;"
    )
  end
end
