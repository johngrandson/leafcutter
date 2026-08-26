defmodule LeafcutterCore.ApplicationTest do
  use ExUnit.Case, async: true

  test "supervises the shared repository, PubSub, and Oban infrastructure" do
    children = Supervisor.which_children(LeafcutterCore.Supervisor)

    assert {Leafcutter.Repo, repo_pid, :supervisor, [Leafcutter.Repo]} =
             List.keyfind(children, Leafcutter.Repo, 0)

    assert {Oban, oban_pid, :supervisor, [Oban]} =
             List.keyfind(children, Oban, 0)

    assert Process.alive?(repo_pid)
    assert Process.alive?(oban_pid)

    assert pubsub_pid = Process.whereis(Leafcutter.PubSub)
    assert Process.alive?(pubsub_pid)
  end

  test "the shared PubSub delivers messages through its registered name" do
    topic = "application-test:#{System.unique_integer([:positive])}"

    assert :ok = Phoenix.PubSub.subscribe(Leafcutter.PubSub, topic)
    assert :ok = Phoenix.PubSub.broadcast(Leafcutter.PubSub, topic, {:published, topic})
    assert_receive {:published, ^topic}, 1_000
  end
end
