defmodule LeafcutterConnectors.Transport.HTTP.Adapter do
  @moduledoc """
  Contract implemented by synchronous HTTP transport adapters.

  Each callback invocation represents exactly one network attempt.
  """

  alias LeafcutterConnectors.Transport.HTTP.{Error, Request, Response}

  @callback request(Request.t()) ::
              {:ok, Response.t()}
              | {:error, Error.t()}
end
