defmodule LeafcutterConnectors.Transport.HTTP.Error do
  @moduledoc """
  Sanitized failure at the HTTP transport boundary.
  """

  @reasons [
    :invalid_request,
    :pool_timeout,
    :timeout,
    :dns,
    :connection,
    :tls,
    :protocol,
    :response_too_large,
    :transport_failure
  ]

  @typedoc "A stable HTTP transport failure category."
  @type reason ::
          :invalid_request
          | :pool_timeout
          | :timeout
          | :dns
          | :connection
          | :tls
          | :protocol
          | :response_too_large
          | :transport_failure

  @enforce_keys [:reason]
  defstruct [:reason]

  @type t :: %__MODULE__{reason: reason()}

  @doc "Returns whether an error has a ratified sanitized reason."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{reason: reason}), do: reason in @reasons
  def valid?(_error), do: false

  @doc false
  @spec reason?(term()) :: boolean()
  def reason?(reason), do: reason in @reasons
end

defimpl Inspect, for: LeafcutterConnectors.Transport.HTTP.Error do
  import Inspect.Algebra

  alias LeafcutterConnectors.Transport.HTTP.Error

  @impl true
  def inspect(error, opts) do
    reason = if Error.reason?(error.reason), do: error.reason, else: :invalid

    concat([
      "%LeafcutterConnectors.Transport.HTTP.Error{reason: ",
      to_doc(reason, opts),
      "}"
    ])
  end
end
