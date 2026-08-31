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
    valid_items?(items, %{})
  end

  defp valid_items?(_items), do: false

  @spec valid_items?(term(), %{optional(String.t()) => true}) :: boolean()
  defp valid_items?([], _seen_refs), do: true

  defp valid_items?([%Item{ref: ref} = item | items], seen_refs)
       when is_binary(ref) do
    Item.valid?(item) and
      not Map.has_key?(seen_refs, ref) and
      valid_items?(items, Map.put(seen_refs, ref, true))
  end

  defp valid_items?(_items, _seen_refs), do: false
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
