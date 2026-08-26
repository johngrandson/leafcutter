defmodule LeafcutterApi.Router do
  # Phoenix generates an unreachable successful-match branch while the router has no routes.
  # Remove this suppression when the first route is added.
  @dialyzer {:nowarn_function, call: 2}

  use LeafcutterApi, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", LeafcutterApi do
    pipe_through :api
  end
end
