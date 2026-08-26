defmodule Leafcutter.Executions.RunTest do
  use ExUnit.Case, async: true

  alias Leafcutter.Executions.Run

  test "defines the initial lifecycle and ownership defaults" do
    run = %Run{}

    assert run.status == :pending
    assert run.generation == 0
    assert run.owner_node_id == nil
    assert run.ownership_acquired_at == nil
  end

  test "maps the ratified lifecycle states to stable database identifiers" do
    assert Ecto.Enum.mappings(Run, :status) == [
             pending: "pending",
             running: "running",
             completed: "completed",
             failed: "failed",
             cancelled: "cancelled"
           ]
  end
end
