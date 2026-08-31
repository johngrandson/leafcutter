defmodule Leafcutter.Repo.Migrations.AddSchemaToContractVersions do
  use Ecto.Migration

  def up do
    alter table(:contract_versions) do
      add(:schema, :jsonb, null: true)
    end

    create(
      constraint(
        :contract_versions,
        :contract_versions_schema_root_check,
        check:
          "schema IS NULL OR jsonb_typeof(schema) IN ('object', 'boolean')"
      )
    )
  end

  def down do
    drop(
      constraint(
        :contract_versions,
        :contract_versions_schema_root_check
      )
    )

    alter table(:contract_versions) do
      remove(:schema)
    end
  end
end
