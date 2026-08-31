defmodule Leafcutter.Catalog.Contracts.CompilationTest do
  use Leafcutter.DataCase, async: false

  alias Ecto.Adapters.SQL

  alias Leafcutter.Catalog.{
    Contract,
    Contracts,
    ContractVersion
  }

  alias Leafcutter.Catalog.Contracts.Validator

  @dialect "https://json-schema.org/draft/2020-12/schema"

  describe "compile/1" do
    test "compiles object and boolean schemas into opaque validators" do
      contract = contract_fixture()

      documents = [
        {"object", schema(%{"type" => "object"})},
        {"true", true},
        {"false", false}
      ]

      for {version, document} <- documents do
        contract_version = publish_version!(contract, version, document)

        assert {:ok, %Validator{} = validator} =
                 Contracts.compile(contract_version.id)

        refute is_struct(validator, JSV.Root)
        refute inspect(validator) =~ "root:"
      end
    end

    test "returns not_found when the ContractVersion does not exist" do
      assert {:error, :not_found} =
               Contracts.compile("00000000-0000-0000-0000-000000000000")
    end

    test "returns schema_unavailable for an identity-only legacy row" do
      contract = contract_fixture()
      contract_version_id = insert_legacy_version!(contract.id)

      assert {:error, :schema_unavailable} =
               Contracts.compile(contract_version_id)
    end

    test "fails closed for persisted schemas outside the publication boundary" do
      contract = contract_fixture()

      invalid_documents = [
        {"invalid-policy", %{"type" => "object"}},
        {"invalid-build", schema(%{"type" => "bad type"})}
      ]

      for {version, document} <- invalid_documents do
        contract_version = persist_version!(contract, version, document)

        assert {:error, :schema_compilation_failed} =
                 Contracts.compile(contract_version.id)
      end
    end
  end

  @spec publish_version!(Contract.t(), String.t(), map() | boolean()) ::
          ContractVersion.t()
  defp publish_version!(contract, version, schema) do
    {:ok, contract_version} =
      Contracts.publish_version(contract.id, %{
        version: version,
        schema: schema
      })

    contract_version
  end

  @spec persist_version!(Contract.t(), String.t(), map()) :: ContractVersion.t()
  defp persist_version!(contract, version, schema) do
    Repo.insert!(%ContractVersion{
      contract_id: contract.id,
      version: version,
      schema: schema,
      published_at: DateTime.utc_now(:microsecond)
    })
  end

  @spec insert_legacy_version!(Contract.id()) :: ContractVersion.id()
  defp insert_legacy_version!(contract_id) do
    version_id = Ecto.UUID.generate()
    {:ok, dumped_contract_id} = Ecto.UUID.dump(contract_id)
    {:ok, dumped_version_id} = Ecto.UUID.dump(version_id)

    SQL.query!(
      Repo,
      "ALTER TABLE contract_versions DISABLE TRIGGER contract_versions_require_schema",
      []
    )

    try do
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
        VALUES ($1, $2, 'legacy', NULL, clock_timestamp(), clock_timestamp())
        """,
        [dumped_version_id, dumped_contract_id]
      )
    after
      SQL.query!(
        Repo,
        "ALTER TABLE contract_versions ENABLE TRIGGER contract_versions_require_schema",
        []
      )
    end

    version_id
  end

  @spec schema(map()) :: map()
  defp schema(fields), do: Map.put(fields, "$schema", @dialect)

  @spec contract_fixture() :: Contract.t()
  defp contract_fixture do
    {:ok, contract} = Contracts.create(%{name: "Contract #{System.unique_integer()}"})
    contract
  end
end
