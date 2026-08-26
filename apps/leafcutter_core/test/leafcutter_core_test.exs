defmodule LeafcutterCoreTest do
  use ExUnit.Case
  doctest LeafcutterCore

  test "greets the world" do
    assert LeafcutterCore.hello() == :world
  end
end
