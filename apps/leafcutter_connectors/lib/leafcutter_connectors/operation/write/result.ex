defmodule LeafcutterConnectors.Operation.Write.Result do
  @moduledoc """
  Complete ordered classification for one destination batch.
  """

  alias LeafcutterConnectors.Operation.Write.{Invocation, ItemResult}

  @enforce_keys [:results]
  defstruct [:results]

  @type t :: %__MODULE__{results: nonempty_list(ItemResult.t())}

  @doc "Returns whether a result contains a non-empty list of valid item results."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = result) do
    valid_results?(result.results)
  end

  def valid?(_result), do: false

  @spec valid_results?(term()) :: boolean()
  defp valid_results?([result | results]) do
    ItemResult.valid?(result) and valid_result_tail?(results)
  end

  defp valid_results?(_results), do: false

  @spec valid_result_tail?(term()) :: boolean()
  defp valid_result_tail?([]), do: true

  defp valid_result_tail?([result | results]) do
    ItemResult.valid?(result) and valid_result_tail?(results)
  end

  defp valid_result_tail?(_results), do: false

  @doc "Returns whether a result completely and orderly classifies an invocation."
  @spec valid_for?(term(), term()) :: boolean()
  def valid_for?(%__MODULE__{} = result, %Invocation{} = invocation) do
    Invocation.valid?(invocation) and
      valid?(result) and
      Enum.map(result.results, & &1.ref) == Enum.map(invocation.items, & &1.ref)
  end

  def valid_for?(_result, _invocation), do: false
end
