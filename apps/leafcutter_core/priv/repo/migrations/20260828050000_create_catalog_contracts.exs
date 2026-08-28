defmodule Leafcutter.Repo.Migrations.CreateCatalogContracts do
  use Ecto.Migration

  def change do
    create table(:contracts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:contract_versions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :contract_id,
        references(:contracts, type: :binary_id),
        null: false
      )

      add(:version, :string, null: false)
      add(:published_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :contract_versions,
        [:contract_id, :version]
      )
    )

    execute(
      """
      CREATE FUNCTION reject_contract_version_content_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'contract_versions content is immutable';
      END;
      $$;
      """,
      "DROP FUNCTION reject_contract_version_content_mutation();"
    )

    execute(
      """
      CREATE TRIGGER contract_versions_reject_mutation
      BEFORE UPDATE OR DELETE ON contract_versions
      FOR EACH ROW
      EXECUTE FUNCTION reject_contract_version_content_mutation();
      """,
      "DROP TRIGGER contract_versions_reject_mutation ON contract_versions;"
    )
  end
end
