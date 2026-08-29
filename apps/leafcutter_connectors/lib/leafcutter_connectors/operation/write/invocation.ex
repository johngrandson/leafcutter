defmodule LeafcutterConnectors.Operation.Write.Invocation do
  @moduledoc """
  Ephemeral input for one ordered destination batch.

  Inspection always redacts credentials.
  """

  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Write.Item

  @enforce_keys [:config, :credentials, :items]
  defstruct [:config, :credentials, :items]

  @type t :: %__MODULE__{
          config: Operation.json_object(),
          credentials: map(),
          items: nonempty_list(Item.t())
        }

  @doc "Returns whether an invocation satisfies the write operation contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = invocation) do
    Operation.json_object?(invocation.config) and
      is_map(invocation.credentials) and
      valid_items?(invocation.items)
  end

  def valid?(_invocation), do: false

  @spec valid_items?(term()) :: boolean()
  defp valid_items?(items) do
    is_list(items) and items != [] and
      Enum.all?(items, &Item.valid?/1) and unique_refs?(items)
  end

  @spec unique_refs?([Item.t()]) :: boolean()
  defp unique_refs?(items) do
    refs = Enum.map(items, & &1.ref)
    length(refs) == MapSet.size(MapSet.new(refs))
  end
end

defimpl Inspect, for: LeafcutterConnectors.Operation.Write.Invocation do
  import Inspect.Algebra

  @impl true
  def inspect(invocation, opts) do
    concat([
      "%LeafcutterConnectors.Operation.Write.Invocation{config: ",
      to_doc(invocation.config, opts),
      ", credentials: :redacted, items: ",
      to_doc(invocation.items, opts),
      "}"
    ])
  end
end
