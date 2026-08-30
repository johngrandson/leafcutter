defmodule LeafcutterConnectors.Application do
  @moduledoc false

  use Application

  alias LeafcutterConnectors.Transport.HTTP.Finch

  @impl true
  def start(_type, _args) do
    children = [Finch.child_spec()]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: LeafcutterConnectors.Supervisor
    )
  end
end
