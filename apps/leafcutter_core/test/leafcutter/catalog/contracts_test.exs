defmodule Leafcutter.Catalog.ContractsTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    Contract,
    Contracts,
    ContractVersion
  }

  describe "create/1" do
    test "persists a global Contract identity" do
      assert {:ok, %Contract{} = contract} =
               Contracts.create(%{
                 name: "Customer",
                 id: Ecto.UUID.generate()
               })

      assert contract.name == "Customer"
      assert {:ok, contract.id} == Ecto.UUID.cast(contract.id)
      assert %DateTime{} = contract.inserted_at
      assert %DateTime{} = contract.updated_at
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 names" do
      invalid_attrs = [
        %{},
        %{name: ""},
        %{name: "   "},
        %{name: String.duplicate("a", 256)},
        %{name: <<255>>}
      ]

      for attrs <- invalid_attrs do
        assert {:error, changeset} = Contracts.create(attrs)
        assert %{name: [_ | _]} = errors_on(changeset)
      end
    end
  end

  describe "get/1" do
    test "returns a persisted Contract identity without preloading versions" do
      contract = contract_fixture()

      assert {:ok, fetched} = Contracts.get(contract.id)
      assert fetched.id == contract.id
      assert fetched.name == contract.name
      assert %Ecto.Association.NotLoaded{} = fetched.versions
    end

    test "returns a named error when the Contract does not exist" do
      assert {:error, :not_found} =
               Contracts.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "publish_version/2" do
    test "publishes an opaque identity-only ContractVersion" do
      contract = contract_fixture()

      assert {:ok, %ContractVersion{} = contract_version} =
               Contracts.publish_version(
                 contract.id,
                 %{
                   version: "release-2026.08",
                   published_at: ~U[2025-01-01 00:00:00.000000Z],
                   schema: %{"type" => "object"}
                 }
               )

      assert contract_version.contract == contract
      assert contract_version.version == "release-2026.08"
      assert %DateTime{} = contract_version.published_at

      assert contract_version.published_at !=
               ~U[2025-01-01 00:00:00.000000Z]
    end

    test "accepts string-keyed attributes" do
      contract = contract_fixture()

      assert {:ok, contract_version} =
               Contracts.publish_version(
                 contract.id,
                 %{"version" => "opaque"}
               )

      assert contract_version.version == "opaque"
    end

    test "returns contract_not_found without persisting a version" do
      assert {:error, :contract_not_found} =
               Contracts.publish_version(
                 "00000000-0000-0000-0000-000000000000",
                 %{version: "1"}
               )

      assert Repo.aggregate(ContractVersion, :count) == 0
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 versions" do
      contract = contract_fixture()

      invalid_attrs = [
        %{},
        %{version: ""},
        %{version: "   "},
        %{version: String.duplicate("a", 256)},
        %{version: <<255>>}
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} =
                 Contracts.publish_version(contract.id, attrs)

        refute changeset.valid?
      end

      assert Repo.aggregate(ContractVersion, :count) == 0
    end

    test "enforces version uniqueness within one Contract" do
      first_contract = contract_fixture("First")
      second_contract = contract_fixture("Second")

      assert {:ok, _version} =
               Contracts.publish_version(first_contract.id, %{version: "1"})

      assert {:error, %Changeset{} = changeset} =
               Contracts.publish_version(first_contract.id, %{version: "1"})

      assert %{contract_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _version} =
               Contracts.publish_version(second_contract.id, %{version: "1"})
    end
  end

  describe "database immutability" do
    test "rejects ContractVersion updates and deletes" do
      contract = contract_fixture()

      assert {:ok, contract_version} =
               Contracts.publish_version(contract.id, %{version: "1"})

      update_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              contract_version
              |> Changeset.change(version: "changed")
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert update_error.postgres.message ==
               "contract_versions content is immutable"

      delete_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn -> Repo.delete!(contract_version) end,
            mode: :savepoint
          )
        end

      assert delete_error.postgres.message ==
               "contract_versions content is immutable"

      assert Repo.get!(ContractVersion, contract_version.id).version == "1"
    end
  end

  @spec contract_fixture(String.t()) :: Contract.t()
  defp contract_fixture(name \\ "Contract") do
    {:ok, contract} = Contracts.create(%{name: name})
    contract
  end
end
