defmodule Leafcutter.Executions.RunSnapshot.DefinitionV1.Connection do
  @moduledoc """
  Represents one resolved connection binding inside a RunSnapshot v1 definition.

  The binding contains a stable Connection identifier, non-sensitive
  configuration, and an optional reference to the exact SecretVersion selected
  for the Run. It never contains raw secret material.
  """

  use Ecto.Schema

  @primary_key false

  @typedoc "A resolved connection binding before it is serialized to JSONB."
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          config: map() | nil,
          secret_version_id: Ecto.UUID.t() | nil
        }

  embedded_schema do
    field(:id, :binary_id)
    field(:config, :map)
    field(:secret_version_id, :binary_id)
  end
end
