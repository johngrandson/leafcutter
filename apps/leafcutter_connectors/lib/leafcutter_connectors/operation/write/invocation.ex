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
  defp valid_items?([_item | _items] = items) do
    valid_items?(items, MapSet.new())
  end

  defp valid_items?(_items), do: false

  @spec valid_items?(term(), MapSet.t(String.t())) :: boolean()
  defp valid_items?([], _refs), do: true

  defp valid_items?([%Item{ref: ref} = item | items], refs) do
    Item.valid?(item) and
      not MapSet.member?(refs, ref) and
      valid_items?(items, MapSet.put(refs, ref))
  end

  defp valid_items?(_items, _refs), do: false
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
