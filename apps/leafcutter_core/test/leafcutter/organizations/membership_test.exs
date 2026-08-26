defmodule Leafcutter.Organizations.MembershipTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.Membership

  describe "create_changeset/2" do
    test "requires organization and user identifiers" do
      organization_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      invalid_attributes = [
        %{},
        %{organization_id: organization_id},
        %{user_id: user_id}
      ]

      for attrs <- invalid_attributes do
        changeset = Membership.create_changeset(%Membership{}, attrs)

        refute changeset.valid?
        assert changeset.errors != []
      end
    end

    test "excludes lifecycle state from creation attributes" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]

      changeset =
        Membership.create_changeset(%Membership{}, %{
          organization_id: Ecto.UUID.generate(),
          user_id: Ecto.UUID.generate(),
          disabled_at: disabled_at
        })

      assert changeset.valid?
      refute Ecto.Changeset.changed?(changeset, :disabled_at)
    end
  end

  describe "disable_changeset/1" do
    test "sets a lifecycle timestamp for an active membership" do
      changeset = Membership.disable_changeset(%Membership{})

      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :disabled_at)
    end

    test "preserves an existing lifecycle timestamp" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]
      changeset = Membership.disable_changeset(%Membership{disabled_at: disabled_at})

      refute Ecto.Changeset.changed?(changeset, :disabled_at)
      assert changeset.data.disabled_at == disabled_at
    end
  end
end
