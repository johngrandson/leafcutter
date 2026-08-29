defmodule Leafcutter.Catalog.ContractVersionPersistenceTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Contract,
    Contracts,
    ContractVersion
  }

  alias Leafcutter.Catalog.Types.SchemaDocument

  @dialect "https://json-schema.org/draft/2020-12/schema"

  test "round-trips object and boolean schema roots" do
    contract = contract_fixture()

    documents = [
      {"object", %{"$schema" => @dialect, "type" => "object"}},
      {"true", true},
      {"false", false}
    ]

    for {version, document} <- documents do
      contract_version = persist_version!(contract, version, document)

      assert Repo.get!(ContractVersion, contract_version.id).schema === document
    end
  end

  test "rejects a new row without schema content" do
    contract = contract_fixture()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(
          fn ->
            insert_raw_schema!(contract.id, "missing-schema", nil)
          end,
          mode: :savepoint
        )
      end

    assert error.postgres.message ==
             "contract_versions schema is required"
  end

  test "rejects JSONB roots other than object or boolean" do
    contract = contract_fixture()

    invalid_documents = [
      {"array", "[]"},
      {"string", ~s("schema")},
      {"number", "1"},
      {"json-null", "null"}
    ]

    for {version, encoded_document} <- invalid_documents do
      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              insert_raw_schema!(
                contract.id,
                version,
                encoded_document
              )
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.constraint ==
               "contract_versions_schema_root_check"
    end
  end

  test "keeps the persisted schema protected by the existing mutation trigger" do
    contract = contract_fixture()

    contract_version =
      persist_version!(
        contract,
        "immutable",
        %{"$schema" => @dialect, "type" => "object"}
      )

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(
          fn ->
            contract_version
            |> Changeset.change(schema: false)
            |> Repo.update!()
          end,
          mode: :savepoint
        )
      end

    assert error.postgres.message ==
             "contract_versions content is immutable"

    assert Repo.get!(ContractVersion, contract_version.id).schema ==
             contract_version.schema
  end

  @spec persist_version!(
          Contract.t(),
          String.t(),
          SchemaDocument.t()
        ) :: ContractVersion.t()
  defp persist_version!(contract, version, schema) do
    Repo.insert!(%ContractVersion{
      contract_id: contract.id,
      version: version,
      schema: schema,
      published_at: DateTime.utc_now(:microsecond)
    })
  end

  @spec insert_raw_schema!(Contract.id(), String.t(), String.t() | nil) ::
          Postgrex.Result.t()
  defp insert_raw_schema!(contract_id, version, encoded_schema) do
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract_id)
    {:ok, dumped_version_id} = Ecto.UUID.dump(Ecto.UUID.generate())

    SQL.query!(
      Repo,
      """
      INSERT INTO contract_versions (
        id,
        contract_id,
        version,
        schema,
        published_at,
        inserted_at
      )
      VALUES ($1, $2, $3, $4::text::jsonb, clock_timestamp(), clock_timestamp())
      """,
      [dumped_version_id, dumped_contract_id, version, encoded_schema]
    )
  end

  @spec contract_fixture() :: Contract.t()
  defp contract_fixture do
    {:ok, contract} = Contracts.create(%{name: "Contract"})
    contract
  end
end
