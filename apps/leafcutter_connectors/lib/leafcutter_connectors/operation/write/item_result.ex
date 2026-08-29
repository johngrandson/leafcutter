defmodule LeafcutterConnectors.Operation.Write.ItemResult do
  @moduledoc """
  Complete success or normalized failure classification for one write item.
  """

  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Error

  @typedoc "The normalized outcome for one destination item."
  @type outcome ::
          {:ok, Operation.destination_identity()}
          | {:error, Error.t()}

  @enforce_keys [:ref, :outcome]
  defstruct [:ref, :outcome]

  @type t :: %__MODULE__{
          ref: String.t(),
          outcome: outcome()
        }

  @doc "Returns whether an item result satisfies the write operation contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = result) do
    non_blank_string?(result.ref) and valid_outcome?(result.outcome)
  end

  def valid?(_result), do: false

  @spec valid_outcome?(term()) :: boolean()
  defp valid_outcome?({:ok, destination_identity}) do
    Operation.json_value?(destination_identity)
  end

  defp valid_outcome?({:error, %Error{} = error}), do: Error.valid?(error)
  defp valid_outcome?(_outcome), do: false

  @spec non_blank_string?(term()) :: boolean()
  defp non_blank_string?(value) do
    is_binary(value) and String.valid?(value) and String.trim(value) != ""
  end
end
