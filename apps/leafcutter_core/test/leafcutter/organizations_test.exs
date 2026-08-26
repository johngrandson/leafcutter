defmodule Leafcutter.OrganizationsTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Organization

  describe "create/1" do
    test "persists a new active organization" do
      assert {:ok, %Organization{} = organization} =
               Organizations.create(%{name: "Acme"})

      assert organization.name == "Acme"
      assert organization.disabled_at == nil
      assert {:ok, organization.id} == Ecto.UUID.cast(organization.id)
      assert %DateTime{} = organization.inserted_at
    end

    test "rejects missing, blank, and oversized names" do
      invalid_attributes = [
        %{},
        %{name: ""},
        %{name: String.duplicate("a", 256)}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = Organizations.create(attrs)
        assert %{name: [_ | _]} = errors_on(changeset)
      end
    end

    test "does not allow callers to create a disabled organization" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]

      assert {:ok, organization} =
               Organizations.create(%{name: "Acme", disabled_at: disabled_at})

      assert organization.disabled_at == nil
    end
  end

  describe "get/1" do
    test "returns a persisted organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, fetched} = Organizations.get(organization.id)
      assert fetched.id == organization.id
      assert fetched.name == "Acme"
    end

    test "returns a named error when the organization does not exist" do
      assert {:error, :not_found} =
               Organizations.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:ok, first_disable} = Organizations.disable(organization.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = Organizations.disable(organization.id)
      assert second_disable.disabled_at == first_disable.disabled_at

      assert {:ok, fetched} = Organizations.get(organization.id)
      assert fetched.disabled_at == first_disable.disabled_at
    end

    test "returns a named error when the organization does not exist" do
      assert {:error, :not_found} =
               Organizations.disable("00000000-0000-0000-0000-000000000000")
    end
  end
end
