defmodule Leafcutter.Connections.Secrets do
  @moduledoc """
  Public capability module for Secret identities and immutable versions.

  This capability stores only scoped identities. It deliberately excludes raw
  secret material, encryption, provider locators, credentials, and rotation.
  """

  import Ecto.Query

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

  @typedoc "Error returned while fetching exact SecretVersion identities for a scope."
  @type fetch_versions_error ::
          {:secret_version_not_found, SecretVersion.id()}
          | {:secret_version_scope_mismatch, SecretVersion.id()}

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

  @doc """
  Fetches and validates exact immutable SecretVersion identities for one scope.

  ## Parameters

  * `ids` - The exact SecretVersion identifiers required by the caller
  * `organization_id` - The Organization every SecretVersion must belong to
  * `environment_id` - The Environment every SecretVersion must belong to

  ## Returns

  * `{:ok, secret_versions}` with unique versions ordered by identifier
  * `{:error, {:secret_version_not_found, id}}` when a requested version is absent
  * `{:error, {:secret_version_scope_mismatch, id}}` when a version belongs to another scope

  ## Examples

  Given an immutable SecretVersion in the expected scope:

      iex> {:ok, secret_versions} =
      ...>   Leafcutter.Connections.Secrets.fetch_versions(
      ...>     [secret_version.id],
      ...>     organization.id,
      ...>     environment.id
      ...>   )

      iex> Enum.map(secret_versions, & &1.id)
      [secret_version.id]

      iex> Leafcutter.Connections.Secrets.fetch_versions(
      ...>   ["00000000-0000-0000-0000-000000000000"],
      ...>   Ecto.UUID.generate(),
      ...>   Ecto.UUID.generate()
      ...> )
      {:error,
       {:secret_version_not_found,
        "00000000-0000-0000-0000-000000000000"}}

  ## Notes

  * Duplicate identifiers are fetched once and do not duplicate the result.
  * The returned Secret association is loaded as scope evidence.
  * SecretVersions are immutable and therefore do not require row locks.
  * No latest-version selection or secret material access occurs.
  """
  @spec fetch_versions(
          [SecretVersion.id()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) ::
          {:ok, [SecretVersion.t()]}
          | {:error, fetch_versions_error()}
  def fetch_versions(ids, organization_id, environment_id) when is_list(ids) do
    requested_ids = ids |> Enum.uniq() |> Enum.sort()

    secret_versions =
      SecretVersion
      |> join(:inner, [secret_version], secret in assoc(secret_version, :secret))
      |> where([secret_version], secret_version.id in ^requested_ids)
      |> order_by([secret_version], asc: secret_version.id)
      |> preload([_secret_version, secret], secret: secret)
      |> Repo.all()

    with :ok <- validate_versions_present(requested_ids, secret_versions),
         :ok <-
           validate_versions_scope(
             secret_versions,
             organization_id,
             environment_id
           ) do
      {:ok, secret_versions}
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

  @spec validate_versions_present(
          [SecretVersion.id()],
          [SecretVersion.t()]
        ) :: :ok | {:error, {:secret_version_not_found, SecretVersion.id()}}
  defp validate_versions_present(requested_ids, secret_versions) do
    persisted_ids = MapSet.new(secret_versions, & &1.id)

    case Enum.find(requested_ids, &(not MapSet.member?(persisted_ids, &1))) do
      nil -> :ok
      missing_id -> {:error, {:secret_version_not_found, missing_id}}
    end
  end

  @spec validate_versions_scope(
          [SecretVersion.t()],
          Ecto.UUID.t(),
          Ecto.UUID.t()
        ) :: :ok | {:error, {:secret_version_scope_mismatch, SecretVersion.id()}}
  defp validate_versions_scope(
         secret_versions,
         organization_id,
         environment_id
       ) do
    case Enum.find(secret_versions, fn secret_version ->
           secret_version.secret.organization_id != organization_id or
             secret_version.secret.environment_id != environment_id
         end) do
      nil -> :ok

      secret_version ->
        {:error, {:secret_version_scope_mismatch, secret_version.id}}
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
