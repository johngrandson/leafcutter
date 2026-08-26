defmodule LeafcutterRuntime.Application do
  @moduledoc false

  use Application

  alias LeafcutterRuntime.{NodeHeartbeat, RunDynamicSupervisor}

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    runtime_node_id = Ecto.UUID.generate()

    children = [
      {Registry, keys: :unique, name: LeafcutterRuntime.RunRegistry},
      RunDynamicSupervisor,
      {NodeHeartbeat, %{runtime_node_id: runtime_node_id}}
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: LeafcutterRuntime.Supervisor
    )
  end
end
