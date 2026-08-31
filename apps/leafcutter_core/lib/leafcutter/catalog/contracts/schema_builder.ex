defmodule Leafcutter.Catalog.Contracts.SchemaBuilder do
  @moduledoc false

  alias Leafcutter.Catalog.Contracts.SchemaPolicy

  @dialect "https://json-schema.org/draft/2020-12/schema"
  @build_options [
    resolver: [],
    default_meta: @dialect,
    formats: true,
    atoms: false,
    vocabularies: %{}
  ]

  @typedoc "A deterministic error returned before a JSV root can be built."
  @type error :: {:policy_failed, SchemaPolicy.error()} | :schema_build_failed

  @doc false
  @spec build(term()) :: {:ok, JSV.Root.t()} | {:error, error()}
  def build(document) do
    case SchemaPolicy.validate(document) do
      {:ok, approved_document} ->
        build_approved(approved_document)

      {:error, policy_error} ->
        {:error, {:policy_failed, policy_error}}
    end
  end

  @spec build_approved(SchemaPolicy.document()) ::
          {:ok, JSV.Root.t()} | {:error, :schema_build_failed}
  defp build_approved(document) do
    case JSV.build(document, @build_options) do
      {:ok, root} -> {:ok, root}
      {:error, _build_error} -> {:error, :schema_build_failed}
    end
  end
end
