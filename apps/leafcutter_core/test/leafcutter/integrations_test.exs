defmodule Leafcutter.IntegrationsTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Changeset

  alias Leafcutter.Catalog.Packages
  alias Leafcutter.Integrations
  alias Leafcutter.Integrations.Integration
  alias Leafcutter.Organizations

  describe "create/1" do
    test "persists an Organization-scoped identity bound to a stable Package" do
      scope = scope_fixture()

      assert {:ok, %Integration{} = integration} =
               Integrations.create(%{
                 organization_id: scope.organization.id,
                 package_id: scope.package.id,
                 name: "CRM synchronization",
                 id: Ecto.UUID.generate(),
                 disabled_at: ~U[2025-01-01 00:00:00.000000Z]
               })

      assert integration.organization_id == scope.organization.id
      assert integration.package_id == scope.package.id
      assert integration.name == "CRM synchronization"
      assert integration.disabled_at == nil
      assert {:ok, integration.id} == Ecto.UUID.cast(integration.id)
    end

    test "accepts string-keyed attributes" do
      scope = scope_fixture()

      assert {:ok, integration} =
               Integrations.create(%{
                 "organization_id" => scope.organization.id,
                 "package_id" => scope.package.id,
                 "name" => "Warehouse synchronization"
               })

      assert integration.organization_id == scope.organization.id
      assert integration.package_id == scope.package.id
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 names" do
      scope = scope_fixture()

      invalid_attrs = [
        %{},
        integration_attrs(scope, name: ""),
        integration_attrs(scope, name: "   "),
        integration_attrs(scope, name: String.duplicate("a", 256)),
        integration_attrs(scope, name: <<255>>)
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} =
                 Integrations.create(attrs)

        refute changeset.valid?
      end

      assert Repo.aggregate(Integration, :count) == 0
    end

    test "returns named errors for missing or disabled authorities" do
      scope = scope_fixture()

      assert {:error, :organization_not_found} =
               Integrations.create(
                 integration_attrs(scope,
                   organization_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :package_not_found} =
               Integrations.create(integration_attrs(scope, package_id: Ecto.UUID.generate()))

      assert {:ok, _disabled_organization} =
               Organizations.disable(scope.organization.id)

      assert {:error, :organization_disabled} =
               Integrations.create(integration_attrs(scope))

      assert Repo.aggregate(Integration, :count) == 0
    end
  end

  describe "get/1" do
    test "returns active and disabled Integrations" do
      scope = scope_fixture()
      {:ok, integration} = Integrations.create(integration_attrs(scope))

      assert {:ok, fetched} = Integrations.get(integration.id)
      assert fetched.id == integration.id

      assert {:ok, disabled} = Integrations.disable(integration.id)
      assert {:ok, fetched_disabled} = Integrations.get(disabled.id)
      assert fetched_disabled.disabled_at == disabled.disabled_at
    end

    test "returns a named error when the Integration does not exist" do
      assert {:error, :not_found} =
               Integrations.get("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "disable/1" do
    test "persists one lifecycle timestamp and preserves it on repeated calls" do
      scope = scope_fixture()
      {:ok, integration} = Integrations.create(integration_attrs(scope))

      assert {:ok, first_disable} = Integrations.disable(integration.id)
      assert %DateTime{} = first_disable.disabled_at

      assert {:ok, second_disable} = Integrations.disable(integration.id)
      assert second_disable.disabled_at == first_disable.disabled_at
    end

    test "returns a named error for a missing Integration or disabled parent" do
      assert {:error, :not_found} =
               Integrations.disable("00000000-0000-0000-0000-000000000000")

      scope = scope_fixture()
      {:ok, integration} = Integrations.create(integration_attrs(scope))

      assert {:ok, _disabled_organization} =
               Organizations.disable(scope.organization.id)

      assert {:error, :organization_disabled} =
               Integrations.disable(integration.id)
    end
  end

  describe "database invariants" do
    test "rejects changing Integration identity fields directly" do
      scope = scope_fixture()
      {:ok, second_package} = Packages.create(%{name: "Second Package"})
      {:ok, integration} = Integrations.create(integration_attrs(scope))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              integration
              |> Changeset.change(
                name: "Changed",
                package_id: second_package.id
              )
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message == "integration identity is immutable"
    end
  end

  defp scope_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, organization} =
      Organizations.create(%{name: "Organization #{suffix}"})

    {:ok, package} = Packages.create(%{name: "Package #{suffix}"})

    %{organization: organization, package: package}
  end

  defp integration_attrs(scope, overrides \\ []) do
    %{
      organization_id: scope.organization.id,
      package_id: scope.package.id,
      name: "Integration"
    }
    |> Map.merge(Map.new(overrides))
  end
end
