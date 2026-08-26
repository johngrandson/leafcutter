defmodule Leafcutter.Organizations.ServiceAccountsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.{ServiceAccount, ServiceAccounts}

  describe "create/1" do
    test "persists a new active service account in an active organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, %ServiceAccount{} = service_account} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "production-sync",
                 disabled_at: ~U[2026-01-01 00:00:00.000000Z]
               })

      assert service_account.organization_id == organization.id
      assert service_account.name == "production-sync"
      assert service_account.disabled_at == nil
      assert {:ok, service_account.id} == Ecto.UUID.cast(service_account.id)
      assert %DateTime{} = service_account.inserted_at
    end

    test "rejects missing required attributes" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      invalid_attributes = [
        %{},
        %{organization_id: organization.id},
        %{name: "production-sync"}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = ServiceAccounts.create(attrs)
        assert map_size(errors_on(changeset)) > 0
      end
    end

    test "requires an existing active organization" do
      missing_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, :organization_not_found} =
               ServiceAccounts.create(%{
                 organization_id: missing_id,
                 name: "production-sync"
               })

      assert {:ok, organization} = Organizations.create(%{name: "Disabled"})
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "production-sync"
               })
    end

    test "scopes service account name uniqueness to each organization" do
      assert {:ok, first_organization} = Organizations.create(%{name: "First"})
      assert {:ok, second_organization} = Organizations.create(%{name: "Second"})

      assert {:ok, _service_account} =
               ServiceAccounts.create(%{
                 organization_id: first_organization.id,
                 name: "production-sync"
               })

      assert {:error, changeset} =
               ServiceAccounts.create(%{
                 organization_id: first_organization.id,
                 name: "production-sync"
               })

      assert %{organization_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _service_account} =
               ServiceAccounts.create(%{
                 organization_id: second_organization.id,
                 name: "production-sync"
               })
    end
  end

  describe "get/1" do
    test "returns active and disabled service accounts" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, service_account} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "production-sync"
               })

      assert {:ok, fetched} = ServiceAccounts.get(service_account.id)
      assert fetched.id == service_account.id

      assert {:ok, disabled} = ServiceAccounts.disable(service_account.id)
      assert {:ok, fetched_disabled} = ServiceAccounts.get(service_account.id)
      assert fetched_disabled.disabled_at == disabled.disabled_at
    end

    test "returns a named error when the service account does not exist" do
      assert {:error, :not_found} =
               ServiceAccounts.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, service_account} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "production-sync"
               })

      assert {:ok, first_disable} = ServiceAccounts.disable(service_account.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = ServiceAccounts.disable(service_account.id)
      assert second_disable.disabled_at == first_disable.disabled_at

      assert Repo.get!(ServiceAccount, service_account.id).disabled_at ==
               first_disable.disabled_at
    end

    test "allows disabling a service account after its organization is disabled" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, service_account} =
               ServiceAccounts.create(%{
                 organization_id: organization.id,
                 name: "production-sync"
               })

      assert {:ok, _organization} = Organizations.disable(organization.id)
      assert {:ok, disabled} = ServiceAccounts.disable(service_account.id)
      assert %DateTime{} = disabled.disabled_at
    end

    test "returns a named error when the service account does not exist" do
      assert {:error, :not_found} =
               ServiceAccounts.disable("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "service account constraints" do
    test "maps an organization foreign key violation to the changeset" do
      changeset =
        ServiceAccount.create_changeset(%ServiceAccount{}, %{
          organization_id: "00000000-0000-0000-0000-000000000000",
          name: "production-sync"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{organization_id: [_ | _]} = errors_on(changeset)
    end
  end
end
