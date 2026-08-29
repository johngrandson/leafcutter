defmodule LeafcutterConnectors.Operation.Read do
  @moduledoc """
  Synchronous behaviour for reading one ordered source page.
  """

  alias LeafcutterConnectors.Operation.Error
  alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

  @callback read(Invocation.t()) :: {:ok, Result.t()} | {:error, Error.t()}

  @doc "Returns whether a callback return is valid for its invocation."
  @spec valid_return?(term(), term()) :: boolean()
  def valid_return?({:ok, %Result{} = result}, %Invocation{} = invocation) do
    Result.valid_for?(result, invocation)
  end

  def valid_return?({:error, %Error{} = error}, %Invocation{} = invocation) do
    Invocation.valid?(invocation) and Error.valid?(error)
  end

  def valid_return?(_return, _invocation), do: false
end
