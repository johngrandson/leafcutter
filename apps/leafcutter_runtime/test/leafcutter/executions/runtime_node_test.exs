defmodule Leafcutter.Executions.RuntimeNodeTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Executions.RuntimeNode

  describe "heartbeat_changeset/2" do
    test "requires the incarnation identifier, node name, and heartbeat timestamp" do
      runtime_node_id = Ecto.UUID.generate()
      heartbeat_at = DateTime.utc_now(:microsecond)

      invalid_attributes = [
        %{},
        %{id: runtime_node_id},
        %{id: runtime_node_id, node_name: "leafcutter@host-1"},
        %{id: runtime_node_id, last_heartbeat_at: heartbeat_at},
        %{node_name: "leafcutter@host-1", last_heartbeat_at: heartbeat_at}
      ]

      for attrs <- invalid_attributes do
        changeset = RuntimeNode.heartbeat_changeset(%RuntimeNode{}, attrs)

        refute changeset.valid?
        assert changeset.errors != []
      end
    end

    test "accepts a valid runtime incarnation heartbeat" do
      runtime_node_id = Ecto.UUID.generate()
      heartbeat_at = DateTime.utc_now(:microsecond)

      changeset =
        RuntimeNode.heartbeat_changeset(
          %RuntimeNode{},
          %{
            id: runtime_node_id,
            node_name: "leafcutter@host-1",
            last_heartbeat_at: heartbeat_at
          }
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :id) == runtime_node_id
      assert Ecto.Changeset.get_change(changeset, :node_name) == "leafcutter@host-1"
      assert Ecto.Changeset.get_change(changeset, :last_heartbeat_at) == heartbeat_at
    end

    test "accepts names at the 255-character limit and rejects longer names" do
      attrs = %{
        id: Ecto.UUID.generate(),
        last_heartbeat_at: DateTime.utc_now(:microsecond)
      }

      valid_changeset =
        RuntimeNode.heartbeat_changeset(
          %RuntimeNode{},
          Map.put(attrs, :node_name, String.duplicate("a", 255))
        )

      invalid_changeset =
        RuntimeNode.heartbeat_changeset(
          %RuntimeNode{},
          Map.put(attrs, :node_name, String.duplicate("a", 256))
        )

      assert valid_changeset.valid?
      refute invalid_changeset.valid?

      assert {:node_name, {_, options}} =
               List.keyfind(invalid_changeset.errors, :node_name, 0)

      assert options[:count] == 255
    end
  end
end
