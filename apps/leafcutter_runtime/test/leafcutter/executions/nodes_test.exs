defmodule Leafcutter.Executions.NodesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Executions.{Nodes, RuntimeNode}
  alias Leafcutter.Repo

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  describe "heartbeat/2" do
    test "inserts the first heartbeat and updates the same runtime incarnation" do
      runtime_node_id = Ecto.UUID.generate()

      assert {:ok, first_heartbeat} =
               Nodes.heartbeat(runtime_node_id, "leafcutter@host-1")

      assert first_heartbeat.id == runtime_node_id
      assert first_heartbeat.node_name == "leafcutter@host-1"
      assert %DateTime{} = first_heartbeat.last_heartbeat_at
      assert %DateTime{} = first_heartbeat.inserted_at
      assert %DateTime{} = first_heartbeat.updated_at

      Process.sleep(2)

      assert {:ok, second_heartbeat} =
               Nodes.heartbeat(runtime_node_id, "leafcutter@host-1-renamed")

      assert second_heartbeat.id == runtime_node_id
      assert second_heartbeat.node_name == "leafcutter@host-1-renamed"
      assert second_heartbeat.inserted_at == first_heartbeat.inserted_at

      assert DateTime.compare(
               second_heartbeat.last_heartbeat_at,
               first_heartbeat.last_heartbeat_at
             ) == :gt

      count =
        RuntimeNode
        |> where([runtime_node], runtime_node.id == ^runtime_node_id)
        |> Repo.aggregate(:count, :id)

      assert count == 1
    end

    test "keeps separate incarnations that reuse the same Erlang node name" do
      first_runtime_node_id = Ecto.UUID.generate()
      second_runtime_node_id = Ecto.UUID.generate()
      node_name = "leafcutter@host-1"

      assert {:ok, first_runtime_node} =
               Nodes.heartbeat(first_runtime_node_id, node_name)

      assert {:ok, second_runtime_node} =
               Nodes.heartbeat(second_runtime_node_id, node_name)

      assert first_runtime_node.id != second_runtime_node.id
      assert first_runtime_node.node_name == second_runtime_node.node_name

      count =
        RuntimeNode
        |> where([runtime_node], runtime_node.node_name == ^node_name)
        |> Repo.aggregate(:count, :id)

      assert count == 2
    end

    test "returns a changeset error for invalid heartbeat metadata" do
      assert {:error, changeset} =
               Nodes.heartbeat(
                 Ecto.UUID.generate(),
                 String.duplicate("a", 256)
               )

      refute changeset.valid?
      assert {:node_name, {_message, options}} = List.keyfind(changeset.errors, :node_name, 0)
      assert options[:count] == 255
    end
  end
end
