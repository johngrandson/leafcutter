defmodule Leafcutter.Connections.Secrets do
  @moduledoc """
  Public capability module for Secret identities and immutable versions.

  This capability stores only scoped identities. It deliberately excludes raw
  secret material, encryption, provider locators, credentials, and rotation.
  """

  alias Ecto.Changeset

  alias Leafcutter.Connections.{Secret, SecretVersion}
  alias Leafcutter.Organizations.Environments
  alias Leafcutter.Repo

  @typedoc "Authority or lifecycle error returned while validating a Secret scope."
  @type scope_error :: Environments.active_scope_state_error()

  @typedoc "Error returned while creating a Secret identity."
  @type create_error :: scope_error() | Changeset.t()

  @typedoc "Error returned while creating an immutable SecretVersion identity."
  @type create_version_error :: :secret_not_found | scope_error() | Changeset.t()

  @doc """
  Creates an environment-scoped Secret identity.

  ## Parameters

  * `attrs` - The Organization, Environment, and Secret name

  ## Returns

  * `{:ok, secret}` when the identity is persisted
  * `{:error, reason}` when the scope is absent, incompatible, or disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Secret Create Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, secret} =
      ...>   Leafcutter.Connections.Secrets.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     name: "CRM credentials"
      ...>   })

      iex> secret.name
      "CRM credentials"

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Connections.Secrets.create(%{})
      ...> )
      true

  ## Notes

  * Organization and Environment are locked and validated before insertion.
  * The scope locks prevent a concurrent disable from crossing the write.
  * Creating a Secret does not create a SecretVersion.
  * Raw secret material and provider-specific metadata are excluded from the schema.
  """
  @spec create(Secret.create_attrs()) ::
          {:ok, Secret.t()} | {:error, create_error()}
  def create(attrs) do
    changeset = Secret.create_changeset(%Secret{}, attrs)

    if changeset.valid? do
      create_with_active_scope(changeset)
    else
      {:error, changeset}
    end
  end

  @doc """
  Creates one immutable version identity for an existing Secret.

  ## Parameters

  * `attrs` - The parent Secret identifier and opaque version string

  ## Returns

  * `{:ok, secret_version}` with its parent Secret loaded
  * `{:error, :secret_not_found}` when the parent Secret does not exist
  * `{:error, reason}` when the parent scope is absent, incompatible, or disabled
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> {:ok, organization} =
      ...>   Leafcutter.Organizations.create(%{
      ...>     name: "Secret Version Organization"
      ...>   })

      iex> {:ok, environment} =
      ...>   Leafcutter.Organizations.Environments.create(%{
      ...>     organization_id: organization.id,
      ...>     name: "production"
      ...>   })

      iex> {:ok, secret} =
      ...>   Leafcutter.Connections.Secrets.create(%{
      ...>     organization_id: organization.id,
      ...>     environment_id: environment.id,
      ...>     name: "CRM credentials"
      ...>   })

      iex> {:ok, secret_version} =
      ...>   Leafcutter.Connections.Secrets.create_version(%{
      ...>     secret_id: secret.id,
      ...>     version: "rotation-2026-08"
      ...>   })

      iex> secret_version.version
      "rotation-2026-08"

      iex> match?(
      ...>   {:error, %{valid?: false}},
      ...>   Leafcutter.Connections.Secrets.create_version(%{})
      ...> )
      true

  ## Notes

  * Version labels are opaque and unique within one Secret.
  * No latest-version selection is performed.
  * The parent scope must remain active while the version is inserted.
  * PostgreSQL rejects update and delete operations on persisted versions.
  * Raw secret material is never accepted by the changeset or persisted.
  """
  @spec create_version(SecretVersion.create_attrs()) ::
          {:ok, SecretVersion.t()} | {:error, create_version_error()}
  def create_version(attrs) do
    changeset = SecretVersion.create_changeset(%SecretVersion{}, attrs)

    if changeset.valid? do
      create_version_with_active_scope(changeset)
    else
      {:error, changeset}
    end
  end

  @spec create_with_active_scope(Changeset.t()) ::
          {:ok, Secret.t()} | {:error, create_error()}
  defp create_with_active_scope(changeset) do
    organization_id = Changeset.fetch_field!(changeset, :organization_id)
    environment_id = Changeset.fetch_field!(changeset, :environment_id)

    Repo.transaction(fn ->
      case Environments.lock_active_scope(organization_id, environment_id) do
        {:ok, _scope} -> insert_secret_or_rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec create_version_with_active_scope(Changeset.t()) ::
          {:ok, SecretVersion.t()} | {:error, create_version_error()}
  defp create_version_with_active_scope(changeset) do
    secret_id = Changeset.fetch_field!(changeset, :secret_id)

    Repo.transaction(fn ->
      with {:ok, secret} <- fetch_secret(secret_id),
           {:ok, _scope} <-
             Environments.lock_active_scope(
               secret.organization_id,
               secret.environment_id
             ) do
        secret_version = insert_secret_version_or_rollback(changeset)
        %{secret_version | secret: secret}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec fetch_secret(Secret.id()) ::
          {:ok, Secret.t()} | {:error, :secret_not_found}
  defp fetch_secret(secret_id) do
    case Repo.get(Secret, secret_id) do
      %Secret{} = secret -> {:ok, secret}
      nil -> {:error, :secret_not_found}
    end
  end

  @spec insert_secret_or_rollback(Changeset.t()) ::
          Secret.t() | no_return()
  defp insert_secret_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, secret} -> secret
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec insert_secret_version_or_rollback(Changeset.t()) ::
          SecretVersion.t() | no_return()
  defp insert_secret_version_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, secret_version} -> secret_version
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
