defmodule Leafcutter.Connections.SecretsTest do
  use Leafcutter.DataCase, async: true

  alias Ecto.Changeset

  alias Leafcutter.Connections.{Secret, Secrets, SecretVersion}
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Environments

  @typep scope_fixture :: %{
           organization: Leafcutter.Organizations.Organization.t(),
           environment: Leafcutter.Organizations.Environment.t()
         }

  describe "create/1" do
    test "persists an environment-scoped Secret identity without material" do
      scope = scope_fixture()

      assert {:ok, %Secret{} = secret} =
               Secrets.create(%{
                 organization_id: scope.organization.id,
                 environment_id: scope.environment.id,
                 name: "CRM credentials",
                 id: Ecto.UUID.generate(),
                 raw_secret: "not persisted",
                 ciphertext: "not persisted",
                 provider_locator: "not persisted"
               })

      assert secret.organization_id == scope.organization.id
      assert secret.environment_id == scope.environment.id
      assert secret.name == "CRM credentials"
      assert %Ecto.Association.NotLoaded{} = secret.versions
      assert {:ok, secret.id} == Ecto.UUID.cast(secret.id)
      refute Map.has_key?(Map.from_struct(secret), :raw_secret)
      refute Map.has_key?(Map.from_struct(secret), :ciphertext)
      refute Map.has_key?(Map.from_struct(secret), :provider_locator)
    end

    test "accepts string-keyed scope and name attributes" do
      scope = scope_fixture()

      assert {:ok, secret} =
               Secrets.create(%{
                 "organization_id" => scope.organization.id,
                 "environment_id" => scope.environment.id,
                 "name" => "Credentials"
               })

      assert secret.name == "Credentials"
    end

    test "rejects missing, blank, oversized, and invalid UTF-8 names" do
      scope = scope_fixture()

      invalid_attrs = [
        %{},
        secret_attrs(scope, name: ""),
        secret_attrs(scope, name: "   "),
        secret_attrs(scope, name: String.duplicate("a", 256)),
        secret_attrs(scope, name: <<255>>)
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} = Secrets.create(attrs)
        refute changeset.valid?
      end

      assert Repo.aggregate(Secret, :count) == 0
    end

    test "returns named errors for absent, incompatible, or disabled scope" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")

      assert {:error, :organization_not_found} =
               Secrets.create(
                 secret_attrs(first_scope,
                   organization_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_not_found} =
               Secrets.create(
                 secret_attrs(first_scope,
                   environment_id: Ecto.UUID.generate()
                 )
               )

      assert {:error, :environment_scope_mismatch} =
               Secrets.create(
                 secret_attrs(first_scope,
                   environment_id: second_scope.environment.id
                 )
               )

      assert {:ok, _environment} =
               Environments.disable(first_scope.environment.id)

      assert {:error, :environment_disabled} =
               Secrets.create(secret_attrs(first_scope))

      assert {:ok, _organization} =
               Organizations.disable(second_scope.organization.id)

      assert {:error, :organization_disabled} =
               Secrets.create(secret_attrs(second_scope))
    end
  end

  describe "create_version/1" do
    test "persists only an immutable opaque version identity" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))

      assert {:ok, %SecretVersion{} = secret_version} =
               Secrets.create_version(%{
                 secret_id: secret.id,
                 version: "rotation-2026-08",
                 id: Ecto.UUID.generate(),
                 raw_secret: "not persisted",
                 ciphertext: "not persisted",
                 provider_locator: "not persisted",
                 credential: "not persisted"
               })

      assert secret_version.secret_id == secret.id
      assert secret_version.secret == secret
      assert secret_version.version == "rotation-2026-08"
      assert %DateTime{} = secret_version.inserted_at
      assert {:ok, secret_version.id} == Ecto.UUID.cast(secret_version.id)
      refute Map.has_key?(Map.from_struct(secret_version), :raw_secret)
      refute Map.has_key?(Map.from_struct(secret_version), :ciphertext)
      refute Map.has_key?(Map.from_struct(secret_version), :provider_locator)
      refute Map.has_key?(Map.from_struct(secret_version), :credential)
    end

    test "accepts string-keyed attributes" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))

      assert {:ok, secret_version} =
               Secrets.create_version(%{
                 "secret_id" => secret.id,
                 "version" => "1"
               })

      assert secret_version.version == "1"
    end

    test "requires a valid parent and opaque version" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))

      invalid_attrs = [
        %{},
        %{secret_id: secret.id},
        %{version: "1"},
        %{secret_id: secret.id, version: ""},
        %{secret_id: secret.id, version: "   "},
        %{secret_id: secret.id, version: String.duplicate("a", 256)},
        %{secret_id: secret.id, version: <<255>>}
      ]

      for attrs <- invalid_attrs do
        assert {:error, %Changeset{} = changeset} =
                 Secrets.create_version(attrs)

        refute changeset.valid?
      end

      assert {:error, :secret_not_found} =
               Secrets.create_version(%{
                 secret_id: Ecto.UUID.generate(),
                 version: "1"
               })

      assert Repo.aggregate(SecretVersion, :count) == 0
    end

    test "enforces version uniqueness within one Secret only" do
      scope = scope_fixture()
      {:ok, first_secret} = Secrets.create(secret_attrs(scope, name: "First"))
      {:ok, second_secret} = Secrets.create(secret_attrs(scope, name: "Second"))

      assert {:ok, _version} =
               Secrets.create_version(%{
                 secret_id: first_secret.id,
                 version: "1"
               })

      assert {:error, %Changeset{} = changeset} =
               Secrets.create_version(%{
                 secret_id: first_secret.id,
                 version: "1"
               })

      assert %{secret_id: [_ | _]} = errors_on(changeset)

      assert {:ok, _version} =
               Secrets.create_version(%{
                 secret_id: second_secret.id,
                 version: "1"
               })
    end

    test "does not select a latest version implicitly" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))

      assert {:ok, first_version} =
               Secrets.create_version(%{
                 secret_id: secret.id,
                 version: "1"
               })

      assert {:ok, second_version} =
               Secrets.create_version(%{
                 secret_id: secret.id,
                 version: "2"
               })

      assert first_version.id != second_version.id
      assert first_version.version == "1"
      assert second_version.version == "2"
    end

    test "rejects version creation after the parent scope is disabled" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))
      assert {:ok, _environment} = Environments.disable(scope.environment.id)

      assert {:error, :environment_disabled} =
               Secrets.create_version(%{
                 secret_id: secret.id,
                 version: "1"
               })
    end
  end

  describe "fetch_versions/3" do
    test "returns unique exact identities ordered by identifier with scope loaded" do
      scope = scope_fixture()
      {:ok, first_secret} = Secrets.create(secret_attrs(scope, name: "First"))
      {:ok, second_secret} = Secrets.create(secret_attrs(scope, name: "Second"))

      {:ok, first_version} =
        Secrets.create_version(%{secret_id: first_secret.id, version: "1"})

      {:ok, second_version} =
        Secrets.create_version(%{secret_id: second_secret.id, version: "1"})

      assert {:ok, secret_versions} =
               Secrets.fetch_versions(
                 [second_version.id, first_version.id, second_version.id],
                 scope.organization.id,
                 scope.environment.id
               )

      assert Enum.map(secret_versions, & &1.id) ==
               [first_version.id, second_version.id] |> Enum.sort()

      assert Enum.all?(secret_versions, fn secret_version ->
               secret_version.secret.organization_id == scope.organization.id and
                 secret_version.secret.environment_id == scope.environment.id
             end)

      assert {:ok, []} =
               Secrets.fetch_versions(
                 [],
                 scope.organization.id,
                 scope.environment.id
               )
    end

    test "classifies missing and scope-incompatible versions deterministically" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")

      {:ok, second_secret} = Secrets.create(secret_attrs(second_scope))

      {:ok, second_version} =
        Secrets.create_version(%{secret_id: second_secret.id, version: "1"})

      missing_id = Ecto.UUID.generate()

      assert {:error, {:secret_version_not_found, ^missing_id}} =
               Secrets.fetch_versions(
                 [missing_id],
                 first_scope.organization.id,
                 first_scope.environment.id
               )

      assert {:error, {:secret_version_scope_mismatch, second_version_id}} =
               Secrets.fetch_versions(
                 [second_version.id],
                 first_scope.organization.id,
                 first_scope.environment.id
               )

      assert second_version_id == second_version.id
    end
  end

  describe "database invariants" do
    test "rejects SecretVersion update and delete operations" do
      scope = scope_fixture()
      {:ok, secret} = Secrets.create(secret_attrs(scope))

      {:ok, secret_version} =
        Secrets.create_version(%{
          secret_id: secret.id,
          version: "1"
        })

      update_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              secret_version
              |> Changeset.change(version: "changed")
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert update_error.postgres.message ==
               "secret_versions content is immutable"

      delete_error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn -> Repo.delete!(secret_version) end,
            mode: :savepoint
          )
        end

      assert delete_error.postgres.message ==
               "secret_versions content is immutable"
    end

    test "rejects changing the persisted scope of a Secret" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")
      {:ok, secret} = Secrets.create(secret_attrs(first_scope))

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.transaction(
            fn ->
              secret
              |> Changeset.change(
                organization_id: second_scope.organization.id,
                environment_id: second_scope.environment.id
              )
              |> Repo.update!()
            end,
            mode: :savepoint
          )
        end

      assert error.postgres.message == "secret scope is immutable"
    end

    test "rejects incompatible Organization and Environment scope directly" do
      first_scope = scope_fixture("First")
      second_scope = scope_fixture("Second")

      changeset =
        Secret.create_changeset(
          %Secret{},
          secret_attrs(first_scope,
            environment_id: second_scope.environment.id
          )
        )

      assert {:error, persisted_changeset} = Repo.insert(changeset)
      assert %{environment_id: [_ | _]} = errors_on(persisted_changeset)
    end
  end

  @spec scope_fixture(String.t()) :: scope_fixture()
  defp scope_fixture(prefix \\ "Scope") do
    {:ok, organization} = Organizations.create(%{name: "#{prefix} Organization"})

    {:ok, environment} =
      Environments.create(%{
        organization_id: organization.id,
        name: "Production"
      })

    %{organization: organization, environment: environment}
  end

  @spec secret_attrs(scope_fixture(), keyword()) :: map()
  defp secret_attrs(scope, overrides \\ []) do
    %{
      organization_id: scope.organization.id,
      environment_id: scope.environment.id,
      name: "Credentials"
    }
    |> Map.merge(Map.new(overrides))
  end
end
