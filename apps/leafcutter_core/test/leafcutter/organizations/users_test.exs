defmodule Leafcutter.Organizations.UsersTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations.User
  alias Leafcutter.Organizations.Users

  describe "create/1" do
    test "normalizes and persists a new active user" do
      disabled_at = ~U[2026-01-01 00:00:00.000000Z]

      assert {:ok, %User{} = user} =
               Users.create(%{
                 email: " User@Example.COM ",
                 disabled_at: disabled_at
               })

      assert user.email == "user@example.com"
      assert user.disabled_at == nil
      assert {:ok, user.id} == Ecto.UUID.cast(user.id)
      assert %DateTime{} = user.inserted_at
    end

    test "accepts an email at the 320-character limit" do
      email = String.duplicate("a", 314) <> "@x.com"

      assert String.length(email) == 320
      assert {:ok, user} = Users.create(%{email: email})
      assert user.email == email
    end

    test "rejects missing, malformed, and oversized emails" do
      invalid_attributes = [
        %{},
        %{email: ""},
        %{email: "a@@b"},
        %{email: "user @example.com"},
        %{email: String.duplicate("a", 315) <> "@x.com"}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = Users.create(attrs)
        assert %{email: [_ | _]} = errors_on(changeset)
      end
    end

    test "enforces uniqueness after email normalization" do
      assert {:ok, _user} = Users.create(%{email: " User@Example.COM "})
      assert {:error, changeset} = Users.create(%{email: "user@example.com"})
      assert %{email: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get/1" do
    test "returns a persisted user" do
      assert {:ok, user} = Users.create(%{email: "user@example.com"})

      assert {:ok, fetched} = Users.get(user.id)
      assert fetched.id == user.id
      assert fetched.email == "user@example.com"
    end

    test "returns a named error when the user does not exist" do
      assert {:error, :not_found} =
               Users.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      assert {:ok, user} = Users.create(%{email: "user@example.com"})

      assert {:ok, first_disable} = Users.disable(user.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = Users.disable(user.id)
      assert second_disable.disabled_at == first_disable.disabled_at

      assert {:ok, fetched} = Users.get(user.id)
      assert fetched.disabled_at == first_disable.disabled_at
    end

    test "returns a named error when the user does not exist" do
      assert {:error, :not_found} =
               Users.disable("00000000-0000-0000-0000-000000000000")
    end
  end
end
