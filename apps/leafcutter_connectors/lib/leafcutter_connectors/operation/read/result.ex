defmodule LeafcutterConnectors.Operation.Read.Result do
  @moduledoc """
  One ordered source page and its opaque continuation cursor.
  """

  alias LeafcutterConnectors.Operation
  alias LeafcutterConnectors.Operation.Read.Invocation

  @enforce_keys [:records, :next_cursor]
  defstruct [:records, :next_cursor, metadata: %{}]

  @type t :: %__MODULE__{
          records: [Operation.json_value()],
          next_cursor: Operation.cursor() | nil,
          metadata: Operation.json_object()
        }

  @doc "Returns whether a result has valid field values."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = result) do
    valid_records?(result.records) and
      (is_nil(result.next_cursor) or Operation.cursor?(result.next_cursor)) and
      Operation.json_object?(result.metadata)
  end

  def valid?(_result), do: false

  @spec valid_records?(term()) :: boolean()
  defp valid_records?([]), do: true

  defp valid_records?([record | records]) do
    Operation.json_value?(record) and valid_records?(records)
  end

  defp valid_records?(_records), do: false

  @doc "Returns whether a result is valid and advances its invocation cursor."
  @spec valid_for?(term(), term()) :: boolean()
  def valid_for?(%__MODULE__{} = result, %Invocation{} = invocation) do
    Invocation.valid?(invocation) and
      valid?(result) and
      (is_nil(result.next_cursor) or result.next_cursor !== invocation.cursor)
  end

  def valid_for?(_result, _invocation), do: false
end
