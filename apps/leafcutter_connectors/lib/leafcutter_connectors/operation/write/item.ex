defmodule LeafcutterConnectors.Operation.Write.Item do
  @moduledoc """
  One transformed and validated destination payload.
  """

  alias LeafcutterConnectors.Operation

  @enforce_keys [:ref, :payload]
  defstruct [:ref, :payload]

  @type t :: %__MODULE__{
          ref: String.t(),
          payload: Operation.json_value()
        }

  @doc "Returns whether an item satisfies the write operation contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = item) do
    non_blank_string?(item.ref) and Operation.json_value?(item.payload)
  end

  def valid?(_item), do: false

  @spec non_blank_string?(term()) :: boolean()
  defp non_blank_string?(value) do
    is_binary(value) and String.valid?(value) and String.trim(value) != ""
  end
end
