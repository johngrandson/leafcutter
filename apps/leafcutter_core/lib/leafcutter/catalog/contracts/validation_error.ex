defmodule Leafcutter.Catalog.Contracts.ValidationError do
  @moduledoc """
  Represents a safe public failure from ContractVersion payload validation.

  Details contain only JSON-compatible values with string map keys. Schema
  violations retain stable validation paths and keyword kinds without exposing
  payload-dependent messages or JSV implementation structs.
  """

  alias Leafcutter.Catalog.ContractVersion

  @typedoc "A JSON-compatible value used in public validation details."
  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{optional(String.t()) => json_value()}

  @typedoc "A JSON object containing safe normalized validation details."
  @type details :: %{optional(String.t()) => json_value()}

  @typedoc "The boundary that rejected a payload."
  @type reason :: :invalid_json | :schema_violation

  @enforce_keys [:contract_version_id, :reason, :details]
  defstruct [:contract_version_id, :reason, :details]

  @type t :: %__MODULE__{
          contract_version_id: ContractVersion.id(),
          reason: reason(),
          details: details()
        }
end
