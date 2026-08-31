defmodule LeafcutterRuntime.ExecutablePackages.Binding do
  @moduledoc """
  In-memory binding between one Catalog PackageVersion and compiled Operations.

  The value preserves authoritative Catalog identifiers while attaching only
  module atoms selected from the checked-in build inventory. It is never
  persisted or serialized into a RunSnapshot.
  """

  alias Leafcutter.Catalog.{ContractVersion, Operation, PackageVersion}

  @typedoc "One resolved source or destination Operation."
  @type endpoint :: %{
          required(:ref) => String.t(),
          required(:operation_id) => Operation.id(),
          required(:contract_version_id) => ContractVersion.id(),
          required(:module) => module()
        }

  @enforce_keys [
    :package_version_id,
    :manifest_sha256,
    :source,
    :destinations
  ]
  defstruct [:package_version_id, :manifest_sha256, :source, :destinations]

  @typedoc "A complete resolved PackageVersion topology."
  @type t :: %__MODULE__{
          package_version_id: PackageVersion.id(),
          manifest_sha256: String.t(),
          source: endpoint(),
          destinations: nonempty_list(endpoint())
        }
end
