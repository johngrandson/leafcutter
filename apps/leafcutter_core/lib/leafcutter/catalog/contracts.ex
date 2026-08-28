defmodule Leafcutter.Catalog.Contracts do
  @moduledoc """
  Public capability module for Contract identities and immutable versions.

  ContractVersion persists only the version identity required by Catalog
  resolution. Executable schemas remain outside the initial slice.
  """

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{Contract, ContractVersion}
  alias Leafcutter.Repo

  @typedoc "Attributes accepted when publishing an immutable ContractVersion identity."
  @type publish_version_attrs ::
          %{required(:version) => String.t()}
          | %{required(String.t()) => String.t()}

  @typedoc "Error returned when a ContractVersion identity cannot be published."
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
  * Executable schema content is outside the initial Catalog slice.
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
  Publishes an immutable ContractVersion identity.

  ## Parameters

  * `contract_id` - The stable Contract identity receiving the version
  * `attrs` - The opaque version string

  ## Returns

  * `{:ok, contract_version}` with its Contract loaded
  * `{:error, :contract_not_found}` when the parent Contract does not exist
  * `{:error, changeset}` when the version is invalid

  ## Examples

      iex> {:ok, contract} =
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Customer"
      ...>   })

      iex> {:ok, version} =
      ...>   Leafcutter.Catalog.Contracts.publish_version(
      ...>     contract.id,
      ...>     %{version: "2026.08"}
      ...>   )

      iex> version.version
      "2026.08"

  ## Notes

  * The version string is opaque and unique within one Contract.
  * Publication persists identity only; schema content is not accepted.
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
          version: attribute(attrs, :version)
        })
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
