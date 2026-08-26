defmodule LeafcutterCore.Application do
  @moduledoc "Application module for LeafcutterCore"

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Leafcutter.Repo,
      {Phoenix.PubSub, name: Leafcutter.PubSub},
      {Oban, Application.fetch_env!(:leafcutter_core, Oban)}
    ]

    opts = [strategy: :one_for_one, name: LeafcutterCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
