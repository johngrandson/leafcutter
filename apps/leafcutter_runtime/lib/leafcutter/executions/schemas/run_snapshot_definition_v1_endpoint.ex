defmodule Leafcutter.Executions.RunSnapshot.DefinitionV1.Endpoint do
  @moduledoc """
  Represents one source or destination binding in a RunSnapshot v1 definition.

  Endpoint references are local to the snapshot format. They identify resolved
  bindings and do not define Package Manifest field names or execution
  priority.
  """

  use Ecto.Schema

  alias Leafcutter.Executions.RunSnapshot.DefinitionV1.Connection

  @primary_key false

  @typedoc "A resolved source or destination binding before JSONB serialization."
  @type t :: %__MODULE__{
          ref: String.t() | nil,
          contract_version_id: Ecto.UUID.t() | nil,
          connection: Connection.t() | nil
        }

  embedded_schema do
    field(:ref, :string)
    field(:contract_version_id, :binary_id)

    embeds_one(:connection, Connection, on_replace: :raise)
  end
end
