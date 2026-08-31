defmodule Leafcutter.Catalog.Contracts do
  @moduledoc """
  Public capability module for Contract identities and immutable executable
  versions.

  New ContractVersions are published with an immutable JSON Schema document
  that satisfies the Leafcutter policy and completes a JSV build before the
  row is inserted. Persisted versions can be compiled explicitly into opaque,
  reusable Leafcutter validators and used to validate JSON payloads without
  rebuilding the schema.
  """

  alias Ecto.Changeset

  alias Leafcutter.Catalog.{Contract, ContractVersion}
  alias Leafcutter.Catalog.Contracts.PayloadPolicy
  alias Leafcutter.Catalog.Contracts.SchemaBuilder
  alias Leafcutter.Catalog.Contracts.ValidationError
  alias Leafcutter.Catalog.Contracts.ValidationErrorNormalizer
  alias Leafcutter.Catalog.Contracts.Validator
  alias Leafcutter.Catalog.Types.SchemaDocument
  alias Leafcutter.Repo

  @typedoc "Attributes accepted when publishing an immutable executable ContractVersion."
  @type publish_version_attrs ::
          %{
            required(:version) => String.t(),
            required(:schema) => SchemaDocument.t()
          }
          | %{
              required(String.t()) => String.t() | SchemaDocument.t()
            }

  @typedoc "Error returned when an executable ContractVersion cannot be published."
  @type publish_error :: :contract_not_found | Changeset.t()

  @typedoc "An opaque validator compiled from one immutable ContractVersion."
  @opaque validator :: Validator.t()

  @typedoc "A named failure returned when a ContractVersion cannot be compiled."
  @type compile_error :: :not_found | :schema_unavailable | :schema_compilation_failed

  @typedoc "A safe public failure returned when a payload cannot be validated."
  @type validation_error :: ValidationError.t()

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

  @doc """
  Compiles one persisted ContractVersion into an opaque validator.

  ## Parameters

  * `contract_version_id` - The immutable ContractVersion identifier to compile

  ## Returns

  * `{:ok, validator}` when the persisted schema passes policy checks and builds
  * `{:error, :not_found}` when the ContractVersion does not exist
  * `{:error, :schema_unavailable}` for an identity-only legacy version
  * `{:error, :schema_compilation_failed}` when persisted schema content is invalid

  ## Examples

      iex> {:ok, contract} =
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Compilation Example"
      ...>   })

      iex> {:ok, version} =
      ...>   Leafcutter.Catalog.Contracts.publish_version(
      ...>     contract.id,
      ...>     %{version: "1", schema: true}
      ...>   )

      iex> match?(
      ...>   {:ok, _validator},
      ...>   Leafcutter.Catalog.Contracts.compile(version.id)
      ...> )
      true

  ## Notes

  * Policy checks are repeated before every build to protect against invalid persisted state.
  * Each call builds at most one JSV root and does not use a shared cache or process.
  * The JSV root remains an internal implementation detail of the opaque validator.
  """
  @spec compile(ContractVersion.id()) ::
          {:ok, validator()} | {:error, compile_error()}
  def compile(contract_version_id) do
    case Repo.get(ContractVersion, contract_version_id) do
      nil ->
        {:error, :not_found}

      %ContractVersion{schema: nil} ->
        {:error, :schema_unavailable}

      %ContractVersion{id: id, schema: schema} ->
        case SchemaBuilder.build(schema) do
          {:ok, root} -> {:ok, Validator.new(id, root)}
          {:error, _reason} -> {:error, :schema_compilation_failed}
        end
    end
  end

  @doc """
  Validates one JSON payload with a compiled ContractVersion validator.

  ## Parameters

  * `validator` - The opaque validator returned by `compile/1`
  * `payload` - The JSON-compatible Elixir term to validate

  ## Returns

  * `{:ok, payload}` with the exact original term when validation succeeds
  * `{:error, validation_error}` when the term is not JSON-compatible or violates
    the schema

  ## Examples

      iex> {:ok, contract} =
      ...>   Leafcutter.Catalog.Contracts.create(%{
      ...>     name: "Validation Example"
      ...>   })

      iex> {:ok, version} =
      ...>   Leafcutter.Catalog.Contracts.publish_version(
      ...>     contract.id,
      ...>     %{version: "1", schema: true}
      ...>   )

      iex> {:ok, validator} =
      ...>   Leafcutter.Catalog.Contracts.compile(version.id)

      iex> Leafcutter.Catalog.Contracts.validate(
      ...>   validator,
      ...>   %{"amount" => 1.0}
      ...> )
      {:ok, %{"amount" => 1.0}}

  ## Notes

  * Non-JSON Elixir terms are rejected before JSV receives the payload.
  * JSV casting and format casting are disabled.
  * Validation errors expose only JSON values, string keys, stable paths and
    keyword kinds; payload-dependent messages are omitted.
  * Validation does not access the Repo, resolve references or rebuild the root.
  """
  @spec validate(validator(), term()) ::
          {:ok, term()} | {:error, validation_error()}
  def validate(validator, payload) do
    contract_version_id = Validator.contract_version_id(validator)

    case PayloadPolicy.validate(payload) do
      {:ok, approved_payload} ->
        validate_approved_payload(validator, approved_payload, payload)

      {:error, payload_error} ->
        {:error,
         %ValidationError{
           contract_version_id: contract_version_id,
           reason: :invalid_json,
           details: PayloadPolicy.error_details(payload_error)
         }}
    end
  end

  @spec validate_approved_payload(validator(), term(), term()) ::
          {:ok, term()} | {:error, validation_error()}
  defp validate_approved_payload(validator, approved_payload, original_payload) do
    case Validator.validate(validator, approved_payload) do
      {:ok, _jsv_payload} ->
        {:ok, original_payload}

      {:error, %JSV.ValidationError{} = jsv_error} ->
        {:error,
         %ValidationError{
           contract_version_id: Validator.contract_version_id(validator),
           reason: :schema_violation,
           details: ValidationErrorNormalizer.normalize(jsv_error)
         }}
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
