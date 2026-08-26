defmodule LeafcutterRuntimeTest do
  use ExUnit.Case
  doctest LeafcutterRuntime

  test "greets the world" do
    assert LeafcutterRuntime.hello() == :world
  end
end
