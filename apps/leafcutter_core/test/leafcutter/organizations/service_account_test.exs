defmodule Leafcutter.Organizations.ServiceAccountTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.ServiceAccount

  describe "create_changeset/2" do
    test "requires an organization identifier and name" do
      organization_id = Ecto.UUID.generate()

      invalid_attributes = [
        %{},
        %{organization_id: organization_id},
        %{name: "production-sync"}
      ]

      for attrs <- invalid_attributes do
        changeset = ServiceAccount.create_changeset(%ServiceAccount{}, attrs)

        refute changeset.valid?
        assert changeset.errors != []
      end
    end

    test "accepts names at the 255-character limit and rejects longer names" do
      organization_id = Ecto.UUID.generate()

      valid_changeset =
        ServiceAccount.create_changeset(%ServiceAccount{}, %{
          organization_id: organization_id,
          name: String.duplicate("a", 255)
        })

      invalid_changeset =
        ServiceAccount.create_changeset(%ServiceAccount{}, %{
          organization_id: organization_id,
          name: String.duplicate("a", 256)
        })

      assert valid_changeset.valid?
      refute invalid_changeset.valid?
      assert {:name, {_, options}} = List.keyfind(invalid_changeset.errors, :name, 0)
      assert options[:count] == 255
    end

    test "excludes lifecycle state from creation attributes" do
      changeset =
        ServiceAccount.create_changeset(%ServiceAccount{}, %{
          organization_id: Ecto.UUID.generate(),
          name: "production-sync",
          disabled_at: ~U[2026-01-01 00:00:00.000000Z]
        })

      assert changeset.valid?
      refute Ecto.Changeset.changed?(changeset, :disabled_at)
    end
  end

  describe "disable_changeset/1" do
    test "sets a lifecycle timestamp for an active service account" do
      changeset = ServiceAccount.disable_changeset(%ServiceAccount{})

      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :disabled_at)
    end

    test "preserves an existing lifecycle timestamp" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]
      changeset = ServiceAccount.disable_changeset(%ServiceAccount{disabled_at: disabled_at})

      refute Ecto.Changeset.changed?(changeset, :disabled_at)
      assert changeset.data.disabled_at == disabled_at
    end
  end
end
