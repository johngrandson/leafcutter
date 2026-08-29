defmodule LeafcutterConnectors.Operation.Read.Invocation do
  @moduledoc """
  Ephemeral input for one source page read.

  Inspection always redacts credentials.
  """

  alias LeafcutterConnectors.Operation

  @enforce_keys [:config, :credentials, :cursor]
  defstruct [:config, :credentials, :cursor]

  @type t :: %__MODULE__{
          config: Operation.json_object(),
          credentials: map(),
          cursor: Operation.cursor() | nil
        }

  @doc "Returns whether an invocation satisfies the read operation contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = invocation) do
    Operation.json_object?(invocation.config) and
      is_map(invocation.credentials) and
      (is_nil(invocation.cursor) or Operation.cursor?(invocation.cursor))
  end

  def valid?(_invocation), do: false
end

defimpl Inspect, for: LeafcutterConnectors.Operation.Read.Invocation do
  import Inspect.Algebra

  @impl true
  def inspect(invocation, opts) do
    concat([
      "%LeafcutterConnectors.Operation.Read.Invocation{config: ",
      to_doc(invocation.config, opts),
      ", credentials: :redacted, cursor: ",
      to_doc(invocation.cursor, opts),
      "}"
    ])
  end
end
