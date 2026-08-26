defmodule Leafcutter.Organizations.EnvironmentsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environment
  alias Leafcutter.Organizations.Environments

  describe "create/1" do
    test "persists an active organization's environment" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, %Environment{} = environment} =
               Environments.create(%{
                 organization_id: organization.id,
                 name: "Production"
               })

      assert environment.organization_id == organization.id
      assert environment.name == "Production"
      assert environment.disabled_at == nil
      assert {:ok, environment.id} == Ecto.UUID.cast(environment.id)
    end

    test "rejects missing and oversized required attributes" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      invalid_attributes = [
        %{},
        %{organization_id: organization.id},
        %{name: "Production"},
        %{organization_id: organization.id, name: String.duplicate("a", 256)}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = Environments.create(attrs)
        assert map_size(errors_on(changeset)) > 0
      end
    end

    test "does not allow callers to create a disabled environment" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]

      assert {:ok, environment} =
               Environments.create(%{
                 organization_id: organization.id,
                 name: "Production",
                 disabled_at: disabled_at
               })

      assert environment.disabled_at == nil
    end

    test "requires an existing organization" do
      assert {:error, :organization_not_found} =
               Environments.create(%{
                 organization_id: "00000000-0000-0000-0000-000000000000",
                 name: "Production"
               })
    end

    test "rejects environments for a disabled organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               Environments.create(%{
                 organization_id: organization.id,
                 name: "Production"
               })
    end

    test "enforces name uniqueness within each organization" do
      assert {:ok, first_organization} = Organizations.create(%{name: "First"})
      assert {:ok, second_organization} = Organizations.create(%{name: "Second"})

      attrs = %{organization_id: first_organization.id, name: "Production"}

      assert {:ok, _environment} = Environments.create(attrs)
      assert {:error, changeset} = Environments.create(attrs)
      assert %{name: [_ | _]} = errors_on(changeset)

      assert {:ok, _environment} =
               Environments.create(%{
                 organization_id: second_organization.id,
                 name: "Production"
               })
    end
  end

  describe "get/1" do
    test "returns a persisted environment" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, environment} =
               Environments.create(%{
                 organization_id: organization.id,
                 name: "Production"
               })

      assert {:ok, fetched} = Environments.get(environment.id)
      assert fetched.id == environment.id
      assert fetched.organization_id == organization.id
      assert fetched.name == "Production"
    end

    test "returns a named error when the environment does not exist" do
      assert {:error, :not_found} =
               Environments.get("00000000-0000-0000-0000-000000000000")
    end
  end
end
