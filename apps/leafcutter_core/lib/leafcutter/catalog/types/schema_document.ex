defmodule Leafcutter.Catalog.Types.SchemaDocument do
  @moduledoc """
  Ecto type for JSON Schema documents persisted by ContractVersion.

  The type preserves object and boolean roots without wrapping or normalizing
  them. Recursive JSON validity and executable schema policy are validated by
  the Catalog publication boundary.
  """

  use Ecto.Type

  @typedoc "A JSON Schema document root accepted by the persistence type."
  @type t :: map() | boolean()

  @impl true
  def type, do: :map

  @impl true
  def cast(value), do: validate_root(value)

  @impl true
  def dump(value), do: validate_root(value)

  @impl true
  def load(nil), do: {:ok, nil}
  def load(value), do: validate_root(value)

  @spec validate_root(term()) :: {:ok, t()} | :error
  defp validate_root(value) when is_boolean(value), do: {:ok, value}

  defp validate_root(value) when is_map(value) do
    if is_struct(value), do: :error, else: {:ok, value}
  end

  defp validate_root(_value), do: :error
end
