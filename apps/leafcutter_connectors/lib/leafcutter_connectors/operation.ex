defmodule LeafcutterConnectors.Operation do
  @moduledoc """
  Shared JSON-compatible values used by executable connector operations.

  Credentials are deliberately excluded from these types. They remain opaque,
  ephemeral maps on invocation structs.
  """

  @typedoc "A JSON-compatible object with valid UTF-8 string keys."
  @type json_object :: %{optional(String.t()) => json_value()}

  @typedoc "A JSON-compatible value."
  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | json_object()

  @typedoc "A non-nil, opaque, JSON-compatible pagination cursor."
  @type cursor ::
          boolean()
          | number()
          | String.t()
          | [json_value()]
          | json_object()

  @typedoc "An opaque, JSON-compatible identity returned by a destination."
  @type destination_identity :: json_value()

  @doc "Returns whether a term is a JSON-compatible value."
  @spec json_value?(term()) :: boolean()
  def json_value?(value)
      when is_nil(value) or is_boolean(value) or is_number(value),
      do: true

  def json_value?(value) when is_binary(value), do: String.valid?(value)
  def json_value?(value) when is_list(value), do: Enum.all?(value, &json_value?/1)
  def json_value?(value) when is_map(value), do: json_object?(value)
  def json_value?(_value), do: false

  @doc "Returns whether a term is a JSON-compatible object."
  @spec json_object?(term()) :: boolean()
  def json_object?(%_{}), do: false

  def json_object?(value) when is_map(value) do
    Enum.all?(value, fn
      {key, nested_value} when is_binary(key) ->
        String.valid?(key) and json_value?(nested_value)

      _entry ->
        false
    end)
  end

  def json_object?(_value), do: false

  @doc "Returns whether a term is a valid non-nil operation cursor."
  @spec cursor?(term()) :: boolean()
  def cursor?(value), do: not is_nil(value) and json_value?(value)
end
