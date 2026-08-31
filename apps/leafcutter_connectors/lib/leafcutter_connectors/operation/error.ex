defmodule LeafcutterConnectors.Operation.Error do
  @moduledoc """
  Normalized, safe, in-memory failure returned by an operation.
  """

  alias LeafcutterConnectors.Operation

  @categories [
    :validation,
    :authentication,
    :rate_limited,
    :timeout,
    :temporary,
    :permanent
  ]
  @retry_hint_categories [:rate_limited, :temporary]

  @typedoc "The retry-policy category of an operation error."
  @type category ::
          :validation
          | :authentication
          | :rate_limited
          | :timeout
          | :temporary
          | :permanent

  @enforce_keys [:category, :code]
  defstruct [:category, :code, :message, :retry_after_ms, metadata: %{}]

  @type t :: %__MODULE__{
          category: category(),
          code: String.t(),
          message: String.t() | nil,
          retry_after_ms: non_neg_integer() | nil,
          metadata: Operation.json_object()
        }

  @doc "Returns whether an error satisfies the executable operation contract."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = error) do
    error.category in @categories and
      non_blank_string?(error.code) and
      optional_string?(error.message) and
      retry_hint_valid?(error.category, error.retry_after_ms) and
      Operation.json_object?(error.metadata)
  end

  def valid?(_error), do: false

  @spec non_blank_string?(term()) :: boolean()
  defp non_blank_string?(value) do
    is_binary(value) and String.valid?(value) and String.trim(value) != ""
  end

  @spec optional_string?(term()) :: boolean()
  defp optional_string?(nil), do: true
  defp optional_string?(value) when is_binary(value), do: String.valid?(value)
  defp optional_string?(_value), do: false

  @spec retry_hint_valid?(term(), term()) :: boolean()
  defp retry_hint_valid?(_category, nil), do: true

  defp retry_hint_valid?(category, retry_after_ms) do
    category in @retry_hint_categories and
      is_integer(retry_after_ms) and retry_after_ms >= 0
  end
end
