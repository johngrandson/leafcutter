defmodule Leafcutter.Catalog.Packages do
  @moduledoc """
  Public capability module for Package identities and immutable topologies.

  PackageVersion and PackageVersionEndpoint rows are published atomically as
  a relational projection bound to a Package Manifest digest. Every new
  endpoint must pin an executable ContractVersion.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{
    ContractVersion,
    Operation,
    Package,
    PackageVersion,
    PackageVersionEndpoint
  }

  alias Leafcutter.Repo

  @typedoc "Attributes that identify one source or destination endpoint."
  @type endpoint_attrs ::
          %{
            required(:ref) => String.t(),
            required(:operation_id) => Operation.id(),
            required(:contract_version_id) => ContractVersion.id()
          }
          | %{required(String.t()) => String.t()}

  @typedoc "Attributes accepted when publishing an immutable PackageVersion."
  @type publish_version_attrs ::
          %{
            required(:version) => String.t(),
            required(:manifest_sha256) => String.t(),
            required(:source) => endpoint_attrs(),
            required(:destinations) => nonempty_list(endpoint_attrs())
          }
          | %{
              required(String.t()) =>
                String.t() | endpoint_attrs() | nonempty_list(endpoint_attrs())
            }

  @typedoc "Error returned when a PackageVersion cannot be published."
  @type publish_error :: :package_not_found | Changeset.t()

  @doc """
  Creates a stable Package identity.

  ## Parameters

  * `attrs` - The external attributes containing the Package name

  ## Returns

  * `{:ok, package}` when the identity is persisted
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:ok, %{name: "CRM synchronization"}},
      ...>   Leafcutter.Catalog.Packages.create(%{
      ...>     name: "CRM synchronization"
      ...>   })
      ...> )
      true

  ## Notes

  * Package identities are global and not scoped to an Organization.
  * Creating an identity does not publish a PackageVersion.
  * Manifest compilation and build inventory are owned outside this identity API.
  """
  @spec create(Package.create_attrs()) ::
          {:ok, Package.t()} | {:error, Changeset.t()}
  def create(attrs) do
    %Package{}
    |> Package.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches a Package identity by its identifier.

  ## Parameters

  * `id` - The Package identifier to fetch

  ## Returns

  * `{:ok, package}` when the Package exists
  * `{:error, :not_found}` when no Package has the identifier

  ## Examples

      iex> {:ok, package} =
      ...>   Leafcutter.Catalog.Packages.create(%{
      ...>     name: "Package Lookup Example"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Catalog.Packages.get(package.id)

      iex> fetched.id == package.id
      true

      iex> Leafcutter.Catalog.Packages.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Versions are not preloaded.
  * Lookup has no availability filtering in the initial Catalog slice.
  """
  @spec get(Package.id()) ::
          {:ok, Package.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Package, id) do
      %Package{} = package ->
        {:ok, package}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Fetches one immutable PackageVersion projection by its identifier.

  ## Parameters

  * `id` - The PackageVersion identifier to fetch

  ## Returns

  * `{:ok, package_version}` with Package, endpoints, Operations, and ContractVersions loaded
  * `{:error, :not_found}` when no PackageVersion has the identifier

  ## Examples

  Given a published PackageVersion with `source` and `destination` endpoint refs:

      iex> {:ok, fetched} =
      ...>   Leafcutter.Catalog.Packages.get_version(
      ...>     published_package_version.id
      ...>   )

      iex> Enum.map(fetched.endpoints, & &1.ref)
      ["source", "destination"]

      iex> Leafcutter.Catalog.Packages.get_version(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * The source endpoint is first and has no position.
  * Destination endpoints follow in their persisted position order.
  * Each Operation includes its immutable ConnectorVersion association.
  * Historical endpoints that pin identity-only ContractVersions remain readable.
  * Historical PackageVersions without a manifest digest remain readable.
  * The projection has no availability filtering in this slice.
  """
  @spec get_version(PackageVersion.id()) ::
          {:ok, PackageVersion.t()} | {:error, :not_found}
  def get_version(id) do
    case Repo.get(PackageVersion, id) do
      %PackageVersion{} = package_version ->
        package_version = Repo.preload(package_version, :package)

        {:ok,
         load_projection(
           package_version,
           package_version.package
         )}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Publishes an immutable PackageVersion and its endpoint projection atomically.

  ## Parameters

  * `package_id` - The stable Package identity receiving the version
  * `attrs` - The version, manifest digest, one source, and ordered non-empty destinations

  ## Returns

  * `{:ok, package_version}` with its complete projection loaded
  * `{:error, :package_not_found}` when the parent Package does not exist
  * `{:error, changeset}` when the topology or one of its references is invalid

  ## Examples

      iex> {:ok, package} =
      ...>   Leafcutter.Catalog.Packages.create(%{
      ...>     name: "CRM synchronization"
      ...>   })

      iex> is_binary(package.id)
      true

  Given compatible persisted source and destination Operations and a ContractVersion:

      iex> {:ok, package_version} =
      ...>   Leafcutter.Catalog.Packages.publish_version(
      ...>     package.id,
      ...>     %{
      ...>       manifest_sha256:
      ...>         "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      ...>       version: "2026.08",
      ...>       source: %{
      ...>         ref: "source",
      ...>         operation_id: source_operation.id,
      ...>         contract_version_id: contract_version.id
      ...>       },
      ...>       destinations: [
      ...>         %{
      ...>           ref: "destination",
      ...>           operation_id: destination_operation.id,
      ...>           contract_version_id: contract_version.id
      ...>         }
      ...>       ]
      ...>     }
      ...>   )

      iex> Enum.map(package_version.endpoints, &{&1.ref, &1.role})
      [{"source", :source}, {"destination", :destination}]

  ## Notes

  * Exactly one source and one or more destinations are required.
  * Every new PackageVersion requires a globally unique lowercase SHA-256 manifest digest.
  * Historical PackageVersions without a digest remain readable through `get_version/1`.
  * Destination position is derived from list order and is not caller supplied.
  * Endpoint refs are unique across the complete PackageVersion.
  * Every endpoint role must match its referenced Operation role.
  * Every referenced ContractVersion must contain persisted executable schema content.
  * Publication seals the version after inserting every endpoint.
  * An incomplete or unsealed PackageVersion cannot cross the transaction boundary.
  * Published version and endpoint rows cannot be appended, updated, or deleted.
  * This API does not define Package Manifest field names.
  """
  @spec publish_version(
          Package.id(),
          publish_version_attrs()
        ) ::
          {:ok, PackageVersion.t()}
          | {:error, publish_error()}
  def publish_version(package_id, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      package = fetch_package_or_rollback(package_id)

      version_changeset =
        PackageVersion.publish_changeset(
          %PackageVersion{},
          %{
            package_id: package.id,
            manifest_sha256: attribute(attrs, :manifest_sha256),
            version: attribute(attrs, :version)
          }
        )

      source_attrs =
        attrs
        |> attribute(:source)
        |> validate_source_or_rollback(version_changeset)

      destination_attrs =
        attrs
        |> attribute(:destinations)
        |> validate_destinations_or_rollback(version_changeset)

      package_version =
        insert_unpublished_version_or_rollback(version_changeset)

      source =
        insert_endpoint_or_rollback(
          package_version,
          source_attrs,
          :source,
          nil
        )

      destinations =
        destination_attrs
        |> Enum.with_index()
        |> Enum.map(fn {endpoint_attrs, position} ->
          insert_endpoint_or_rollback(
            package_version,
            endpoint_attrs,
            :destination,
            position
          )
        end)

      published_version =
        publish_version_or_rollback(package_version)

      endpoints =
        [source | destinations]
        |> Repo.preload(
          operation: :connector_version,
          contract_version: :contract
        )

      %{
        published_version
        | package: package,
          endpoints: endpoints
      }
    end)
  end

  @spec fetch_package_or_rollback(Package.id()) :: Package.t() | no_return()
  defp fetch_package_or_rollback(package_id) do
    case Repo.get(Package, package_id) do
      %Package{} = package ->
        package

      nil ->
        Repo.rollback(:package_not_found)
    end
  end

  @spec validate_source_or_rollback(term(), Changeset.t()) ::
          endpoint_attrs() | no_return()
  defp validate_source_or_rollback(source, _changeset) when is_map(source),
    do: source

  defp validate_source_or_rollback(_source, changeset) do
    Repo.rollback(
      Changeset.add_error(
        changeset,
        :source,
        "must be a map",
        validation: :map
      )
    )
  end

  @spec validate_destinations_or_rollback(term(), Changeset.t()) ::
          [endpoint_attrs()] | no_return()
  defp validate_destinations_or_rollback(destinations, changeset)
       when is_list(destinations) do
    cond do
      destinations == [] ->
        Repo.rollback(
          Changeset.add_error(
            changeset,
            :destinations,
            "must contain at least one endpoint",
            validation: :length
          )
        )

      Enum.any?(destinations, &(not is_map(&1))) ->
        Repo.rollback(
          Changeset.add_error(
            changeset,
            :destinations,
            "must contain only maps",
            validation: :map
          )
        )

      true ->
        destinations
    end
  end

  defp validate_destinations_or_rollback(_destinations, changeset) do
    Repo.rollback(
      Changeset.add_error(
        changeset,
        :destinations,
        "must be a list",
        validation: :list
      )
    )
  end

  @spec insert_unpublished_version_or_rollback(Changeset.t()) ::
          PackageVersion.t() | no_return()
  defp insert_unpublished_version_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, %PackageVersion{} = package_version} ->
        package_version

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec insert_endpoint_or_rollback(
          PackageVersion.t(),
          endpoint_attrs(),
          PackageVersionEndpoint.role(),
          integer() | nil
        ) :: PackageVersionEndpoint.t() | no_return()
  defp insert_endpoint_or_rollback(
         package_version,
         attrs,
         role,
         position
       ) do
    %PackageVersionEndpoint{}
    |> PackageVersionEndpoint.publish_changeset(%{
      package_version_id: package_version.id,
      ref: attribute(attrs, :ref),
      role: role,
      position: position,
      operation_id: attribute(attrs, :operation_id),
      contract_version_id: attribute(attrs, :contract_version_id)
    })
    |> validate_contract_version_executable()
    |> Repo.insert()
    |> case do
      {:ok, %PackageVersionEndpoint{} = endpoint} ->
        endpoint

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec validate_contract_version_executable(Changeset.t()) :: Changeset.t()
  defp validate_contract_version_executable(changeset) do
    case Changeset.fetch_field(changeset, :contract_version_id) do
      {_source, contract_version_id} when is_binary(contract_version_id) ->
        legacy_contract_version? =
          ContractVersion
          |> where(
            [contract_version],
            contract_version.id == ^contract_version_id and
              is_nil(contract_version.schema)
          )
          |> Repo.exists?()

        if legacy_contract_version? do
          Changeset.add_error(
            changeset,
            :contract_version_id,
            "does not reference an executable ContractVersion",
            validation: :contract_version_executable
          )
        else
          changeset
        end

      _missing_or_invalid ->
        changeset
    end
  end

  @spec publish_version_or_rollback(PackageVersion.t()) ::
          PackageVersion.t() | no_return()
  defp publish_version_or_rollback(package_version) do
    package_version
    |> Changeset.change()
    |> Changeset.put_change(
      :published_at,
      DateTime.utc_now(:microsecond)
    )
    |> Repo.update()
    |> case do
      {:ok, %PackageVersion{} = published_version} ->
        published_version

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec load_projection(PackageVersion.t(), Package.t()) :: PackageVersion.t()
  defp load_projection(package_version, package) do
    endpoints =
      PackageVersionEndpoint
      |> where([endpoint], endpoint.package_version_id == ^package_version.id)
      |> order_by(
        [endpoint],
        asc_nulls_first: endpoint.position,
        asc: endpoint.ref
      )
      |> Repo.all()
      |> Repo.preload(
        operation: :connector_version,
        contract_version: :contract
      )

    %{
      package_version
      | package: package,
        endpoints: endpoints
    }
  end

  @spec attribute(map(), atom(), term()) :: term()
  defp attribute(attrs, key, default \\ nil) do
    case Map.fetch(attrs, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(attrs, Atom.to_string(key), default)
    end
  end
end
