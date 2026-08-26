defmodule LeafcutterApi.Router do
  use LeafcutterApi, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", LeafcutterApi do
    pipe_through :api
  end
end
