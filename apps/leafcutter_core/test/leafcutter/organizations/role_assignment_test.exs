defmodule Leafcutter.Organizations.RoleAssignmentTest do
  use Leafcutter.DataCase, async: true

  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Organizations.RoleAssignment
  alias Leafcutter.Organizations.Roles
  alias Leafcutter.Organizations.Users

  test "builds organization-wide and environment-scoped changesets" do
    base_attrs = %{
      membership_id: Ecto.UUID.generate(),
      role_id: Ecto.UUID.generate()
    }

    organization_changeset =
      RoleAssignment.create_changeset(%RoleAssignment{}, base_attrs)

    environment_changeset =
      RoleAssignment.create_changeset(
        %RoleAssignment{},
        Map.put(base_attrs, :environment_id, Ecto.UUID.generate())
      )

    assert organization_changeset.valid?
    assert environment_changeset.valid?
  end

  test "requires membership and role identifiers" do
    assert %{membership_id: [_ | _], role_id: [_ | _]} =
             %RoleAssignment{}
             |> RoleAssignment.create_changeset(%{})
             |> errors_on()
  end

  test "database constraints enforce uniqueness independently for each scope" do
    fixture = create_fixture()
    environment = create_environment(fixture.organization.id)

    organization_attrs = %{
      membership_id: fixture.membership.id,
      role_id: fixture.role.id
    }

    environment_attrs = Map.put(organization_attrs, :environment_id, environment.id)

    assert {:ok, _assignment} = insert_assignment(organization_attrs)
    assert {:ok, _assignment} = insert_assignment(environment_attrs)

    assert {:error, organization_changeset} = insert_assignment(organization_attrs)
    assert %{membership_id: [_ | _]} = errors_on(organization_changeset)

    assert {:error, environment_changeset} = insert_assignment(environment_attrs)
    assert %{membership_id: [_ | _]} = errors_on(environment_changeset)
  end

  test "database constraints allow the same role in different environments" do
    fixture = create_fixture()

    assert {:ok, first_environment} =
             Environments.create(%{
               organization_id: fixture.organization.id,
               name: "production"
             })

    assert {:ok, second_environment} =
             Environments.create(%{
               organization_id: fixture.organization.id,
               name: "homologation"
             })

    base_attrs = %{
      membership_id: fixture.membership.id,
      role_id: fixture.role.id
    }

    assert {:ok, _assignment} =
             insert_assignment(Map.put(base_attrs, :environment_id, first_environment.id))

    assert {:ok, _assignment} =
             insert_assignment(Map.put(base_attrs, :environment_id, second_environment.id))
  end

  defp create_fixture do
    suffix = System.unique_integer([:positive])

    assert {:ok, organization} =
             Organizations.create(%{name: "Role Assignment Schema #{suffix}"})

    assert {:ok, user} =
             Users.create(%{email: "role-assignment-schema-#{suffix}@example.com"})

    assert {:ok, membership} =
             Access.add_member(%{
               organization_id: organization.id,
               user_id: user.id
             })

    assert {:ok, role} =
             Roles.create(%{
               organization_id: organization.id,
               name: "operator"
             })

    %{organization: organization, membership: membership, role: role}
  end

  defp create_environment(organization_id) do
    assert {:ok, environment} =
             Environments.create(%{
               organization_id: organization_id,
               name: "production"
             })

    environment
  end

  defp insert_assignment(attrs) do
    %RoleAssignment{}
    |> RoleAssignment.create_changeset(attrs)
    |> Repo.insert()
  end
end
