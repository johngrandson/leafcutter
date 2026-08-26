defmodule Leafcutter.Organizations.AccessTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access
  alias Leafcutter.Organizations.Membership
  alias Leafcutter.Organizations.Users

  describe "add_member/1" do
    test "persists a membership for active participants" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:ok, %Membership{} = membership} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id
               })

      assert membership.organization_id == organization.id
      assert membership.user_id == user.id
      assert membership.disabled_at == nil
      assert {:ok, membership.id} == Ecto.UUID.cast(membership.id)
      assert %DateTime{} = membership.inserted_at
    end

    test "rejects missing required attributes" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      invalid_attributes = [
        %{},
        %{organization_id: organization.id},
        %{user_id: user.id}
      ]

      for attrs <- invalid_attributes do
        assert {:error, changeset} = Access.add_member(attrs)
        assert map_size(errors_on(changeset)) > 0
      end
    end

    test "does not allow callers to create a disabled membership" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:ok, membership} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id,
                 disabled_at: ~U[2026-01-01 00:00:00.000000Z]
               })

      assert membership.disabled_at == nil
    end

    test "requires an existing organization" do
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:error, :organization_not_found} =
               Access.add_member(%{
                 organization_id: "00000000-0000-0000-0000-000000000000",
                 user_id: user.id
               })
    end

    test "rejects memberships for a disabled organization" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})
      assert {:ok, _organization} = Organizations.disable(organization.id)

      assert {:error, :organization_disabled} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id
               })
    end

    test "requires an existing user" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      assert {:error, :user_not_found} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: "00000000-0000-0000-0000-000000000000"
               })
    end

    test "rejects memberships for a disabled user" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})
      assert {:ok, _user} = Users.disable(user.id)

      assert {:error, :user_disabled} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id
               })
    end

    test "returns a named error for an existing membership" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      attrs = %{organization_id: organization.id, user_id: user.id}

      assert {:ok, _membership} = Access.add_member(attrs)
      assert {:error, :membership_already_exists} = Access.add_member(attrs)
    end

    test "enforces membership uniqueness in the database" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      attrs = %{organization_id: organization.id, user_id: user.id}

      assert {:ok, _membership} = Access.add_member(attrs)

      duplicate_changeset = Membership.create_changeset(%Membership{}, attrs)

      assert {:error, changeset} = Repo.insert(duplicate_changeset)
      assert %{organization_id: [_ | _]} = errors_on(changeset)
    end

    test "scopes uniqueness to the organization and user pair" do
      assert {:ok, first_organization} = Organizations.create(%{name: "First"})
      assert {:ok, second_organization} = Organizations.create(%{name: "Second"})
      assert {:ok, first_user} = Users.create(%{email: "first@example.com"})
      assert {:ok, second_user} = Users.create(%{email: "second@example.com"})

      assert {:ok, _membership} =
               Access.add_member(%{
                 organization_id: first_organization.id,
                 user_id: first_user.id
               })

      assert {:ok, _membership} =
               Access.add_member(%{
                 organization_id: first_organization.id,
                 user_id: second_user.id
               })

      assert {:ok, _membership} =
               Access.add_member(%{
                 organization_id: second_organization.id,
                 user_id: first_user.id
               })
    end
  end

  describe "remove_member/2" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:ok, membership} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id
               })

      assert {:ok, first_removal} = Access.remove_member(organization.id, user.id)
      assert %DateTime{} = first_removal.disabled_at

      assert {:ok, second_removal} = Access.remove_member(organization.id, user.id)
      assert second_removal.disabled_at == first_removal.disabled_at

      assert Repo.get!(Membership, membership.id).disabled_at == first_removal.disabled_at
    end

    test "returns a named error when the membership does not exist" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:error, :membership_not_found} =
               Access.remove_member(organization.id, user.id)
    end

    test "allows removal when the organization and user are disabled" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      assert {:ok, _membership} =
               Access.add_member(%{
                 organization_id: organization.id,
                 user_id: user.id
               })

      assert {:ok, _organization} = Organizations.disable(organization.id)
      assert {:ok, _user} = Users.disable(user.id)

      assert {:ok, removed} = Access.remove_member(organization.id, user.id)
      assert %DateTime{} = removed.disabled_at
    end

    test "does not implicitly reactivate a removed membership" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      attrs = %{organization_id: organization.id, user_id: user.id}

      assert {:ok, _membership} = Access.add_member(attrs)
      assert {:ok, removed} = Access.remove_member(organization.id, user.id)
      assert %DateTime{} = removed.disabled_at

      assert {:error, :membership_already_exists} = Access.add_member(attrs)
    end
  end

  describe "membership constraints" do
    test "maps an organization foreign key violation to the changeset" do
      assert {:ok, user} = Users.create(%{email: "member@example.com"})

      changeset =
        Membership.create_changeset(%Membership{}, %{
          organization_id: "00000000-0000-0000-0000-000000000000",
          user_id: user.id
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{organization_id: [_ | _]} = errors_on(changeset)
    end

    test "maps a user foreign key violation to the changeset" do
      assert {:ok, organization} = Organizations.create(%{name: "Acme"})

      changeset =
        Membership.create_changeset(%Membership{}, %{
          organization_id: organization.id,
          user_id: "00000000-0000-0000-0000-000000000000"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{user_id: [_ | _]} = errors_on(changeset)
    end
  end
end
