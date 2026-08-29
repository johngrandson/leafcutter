defmodule Leafcutter.Catalog.Contracts do
  @moduledoc """
  Public capability module for Contract identities and immutable executable
  versions.

  New ContractVersions are published with an immutable JSON Schema document
  that satisfies the Leafcutter policy and completes a JSV build before the
  row is inserted.
  """

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{Contract, ContractVersion}
  alias Leafcutter.Catalog.Contracts.SchemaBuilder
  alias Leafcutter.Catalog.Types.SchemaDocument
  alias Leafcutter.Repo

  @typedoc "Attributes accepted when publishing an immutable executable ContractVersion."
  @type publish_version_attrs ::
          %{
            required(:version) => String.t(),
            required(:schema) => SchemaDocument.t()
          }
          | %{required(String.t()) => term()}

  @typedoc "Error returned when an executable ContractVersion cannot be published."
  @type publish_error :: :contract_not_found | Changeset.t()

  @doc """
  Creates a stable Contract identity.

  ## Parameters

  * `attrs` - The external attributes containing the Contract name

  ## Returns

  * `{:ok, contract}` when the identity is persisted
  * `{:error, changeset}` when the attributes or database constraints are invalid

  ## Examples

      iex> match?(
      ...>   {:ok, %{name: "Customer"}},
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Customer"
      ...>   })
      ...> )
      true

  ## Notes

  * Contract identities are global and not scoped to an Organization.
  * Creating an identity does not publish a ContractVersion.
  * Executable schema content belongs to each immutable ContractVersion.
  """
  @spec create(Contract.create_attrs()) ::
          {:ok, Contract.t()} | {:error, Changeset.t()}
  def create(attrs) do
    %Contract{}
    |> Contract.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches a Contract identity by its identifier.

  ## Parameters

  * `id` - The Contract identifier to fetch

  ## Returns

  * `{:ok, contract}` when the Contract exists
  * `{:error, :not_found}` when no Contract has the identifier

  ## Examples

      iex> {:ok, contract} =
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Contract Lookup Example"
      ...>   })

      iex> {:ok, fetched} =
      ...>   Leafcutter.Catalog.Contracts.get(contract.id)

      iex> fetched.id == contract.id
      true

      iex> Leafcutter.Catalog.Contracts.get(
      ...>   "00000000-0000-0000-0000-000000000000"
      ...> )
      {:error, :not_found}

  ## Notes

  * Versions are not preloaded.
  * Lookup has no availability filtering in the initial Catalog slice.
  """
  @spec get(Contract.id()) ::
          {:ok, Contract.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Contract, id) do
      %Contract{} = contract ->
        {:ok, contract}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Publishes an immutable executable ContractVersion.

  ## Parameters

  * `contract_id` - The stable Contract identity receiving the version
  * `attrs` - The opaque version string and JSON Schema document

  ## Returns

  * `{:ok, contract_version}` with its Contract loaded
  * `{:error, :contract_not_found}` when the parent Contract does not exist
  * `{:error, changeset}` when the version or schema is invalid

  ## Examples

      iex> {:ok, contract} =
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Customer"
      ...>   })

      iex> {:ok, version} =
      ...>   Leafcutter.Catalog.Contracts.publish_version(
      ...>     contract.id,
      ...>     %{version: "2026.08", schema: true}
      ...>   )

      iex> version.version
      "2026.08"

  ## Notes

  * The version string is opaque and unique within one Contract.
  * Schema object and boolean roots are accepted without normalization.
  * Publication validates the Leafcutter schema policy and completes a JSV build before
    insert.
  * `published_at` is selected internally.
  * Published rows cannot be updated or deleted.
  """
  @spec publish_version(
          Contract.id(),
          publish_version_attrs()
        ) ::
          {:ok, ContractVersion.t()}
          | {:error, publish_error()}
  def publish_version(contract_id, attrs) when is_map(attrs) do
    case Repo.get(Contract, contract_id) do
      %Contract{} = contract ->
        %ContractVersion{}
        |> ContractVersion.publish_changeset(%{
          contract_id: contract.id,
          version: attribute(attrs, :version),
          schema: attribute(attrs, :schema)
        })
        |> validate_publication_schema()
        |> Repo.insert()
        |> case do
          {:ok, contract_version} ->
            {:ok, %{contract_version | contract: contract}}

          {:error, changeset} ->
            {:error, changeset}
        end

      nil ->
        {:error, :contract_not_found}
    end
  end

  @spec validate_publication_schema(Changeset.t()) :: Changeset.t()
  defp validate_publication_schema(changeset) do
    case Changeset.fetch_change(changeset, :schema) do
      {:ok, schema} ->
        case SchemaBuilder.build(schema) do
          {:ok, _root} ->
            changeset

          {:error, {:policy_failed, _policy_error}} ->
            Changeset.add_error(
              changeset,
              :schema,
              "does not satisfy the executable schema policy",
              validation: :schema_policy
            )

          {:error, :schema_build_failed} ->
            Changeset.add_error(
              changeset,
              :schema,
              "cannot be compiled as Draft 2020-12 JSON Schema",
              validation: :schema_build
            )
        end

      :error ->
        changeset
    end
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
