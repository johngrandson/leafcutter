defmodule Leafcutter.Organizations.UserTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Organizations.User

  describe "disable_changeset/1" do
    test "sets a lifecycle timestamp for an active user" do
      changeset = User.disable_changeset(%User{})

      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :disabled_at)
    end

    test "preserves an existing lifecycle timestamp" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]
      changeset = User.disable_changeset(%User{disabled_at: disabled_at})

      refute Ecto.Changeset.changed?(changeset, :disabled_at)
      assert changeset.data.disabled_at == disabled_at
    end
  end
end
