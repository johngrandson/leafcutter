defmodule Leafcutter.Catalog.Contracts.Validator do
  @moduledoc false

  alias Leafcutter.Catalog.ContractVersion

  @derive {Inspect, only: [:contract_version_id]}
  @enforce_keys [:contract_version_id, :root]
  defstruct [:contract_version_id, :root]

  @typedoc "An internal validator retaining one ContractVersion identity and JSV root."
  @opaque t :: %__MODULE__{
            contract_version_id: ContractVersion.id(),
            root: JSV.Root.t()
          }

  @doc false
  @spec new(ContractVersion.id(), JSV.Root.t()) :: t()
  def new(contract_version_id, root) do
    %__MODULE__{
      contract_version_id: contract_version_id,
      root: root
    }
  end
end
