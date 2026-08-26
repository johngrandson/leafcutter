defmodule Leafcutter.Executions.Nodes do
  @moduledoc """
  Public capability module for durable runtime node liveness.

  Each heartbeat upserts one runtime incarnation by its UUID. Erlang node names
  remain descriptive metadata and may be reused by later incarnations.
  """

  alias Leafcutter.Executions.RuntimeNode
  alias Leafcutter.Repo

  @typedoc "Error returned when a runtime node heartbeat cannot be persisted."
  @type heartbeat_error :: Ecto.Changeset.t()

  @doc """
  Records a durable heartbeat for one runtime node incarnation.

  ## Parameters

  * `runtime_node_id` - The identifier generated for the current application incarnation
  * `node_name` - The current Erlang node name used as runtime metadata

  ## Returns

  * `{:ok, runtime_node}` when the heartbeat is inserted or updates the existing incarnation
  * `{:error, changeset}` when the heartbeat attributes or database constraints are invalid

  ## Examples

      iex> runtime_node_id = Ecto.UUID.generate()

      iex> match?(
      ...>   {:ok, %{id: ^runtime_node_id, node_name: "leafcutter@host-1"}},
      ...>   Leafcutter.Executions.Nodes.heartbeat(
      ...>     runtime_node_id,
      ...>     "leafcutter@host-1"
      ...>   )
      ...> )
      true

  ## Notes

  * Repeated heartbeats for the same `runtime_node_id` update one durable row.
  * The same `node_name` may belong to multiple historical runtime incarnations.
  * Liveness is derived from `last_heartbeat_at`; there is no active flag.
  * This operation records liveness only and does not grant or renew Run ownership.
  """
  @spec heartbeat(RuntimeNode.id(), String.t()) ::
          {:ok, RuntimeNode.t()} | {:error, heartbeat_error()}
  def heartbeat(runtime_node_id, node_name) do
    heartbeat_at = DateTime.utc_now(:microsecond)

    changeset =
      RuntimeNode.heartbeat_changeset(
        %RuntimeNode{},
        %{
          id: runtime_node_id,
          node_name: node_name,
          last_heartbeat_at: heartbeat_at
        }
      )

    Repo.insert(
      changeset,
      on_conflict: [
        set: [
          node_name: node_name,
          last_heartbeat_at: heartbeat_at,
          updated_at: heartbeat_at
        ]
      ],
      conflict_target: [:id],
      returning: true
    )
  end
end
