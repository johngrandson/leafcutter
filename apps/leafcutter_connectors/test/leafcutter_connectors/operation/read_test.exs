defmodule LeafcutterConnectors.Operation.ReadTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Operation.Error
  alias LeafcutterConnectors.Operation.Read
  alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

  defmodule FakeRead do
    @moduledoc false

    @behaviour LeafcutterConnectors.Operation.Read

    alias LeafcutterConnectors.Operation.Read.{Invocation, Result}

    @impl true
    def read(%Invocation{cursor: nil}) do
      {:ok,
       %Result{
         records: [%{"id" => "first"}],
         next_cursor: %{"page" => 2},
         metadata: %{"request_id" => "request-1"}
       }}
    end

    def read(%Invocation{cursor: %{"page" => 2}}) do
      {:ok, %Result{records: [], next_cursor: %{"page" => 3}}}
    end

    def read(%Invocation{}) do
      {:ok, %Result{records: [%{"id" => "last"}], next_cursor: nil}}
    end
  end

  test "validates first page, empty progress, and terminal page" do
    first_invocation = invocation(nil)
    assert Invocation.valid?(first_invocation)

    assert {:ok, first_result} = first_return = FakeRead.read(first_invocation)
    assert Read.valid_return?(first_return, first_invocation)
    assert first_result.next_cursor == %{"page" => 2}

    second_invocation = invocation(first_result.next_cursor)
    assert {:ok, second_result} = second_return = FakeRead.read(second_invocation)
    assert Read.valid_return?(second_return, second_invocation)
    assert second_result.records == []
    assert second_result.next_cursor == %{"page" => 3}

    last_invocation = invocation(second_result.next_cursor)
    assert {:ok, last_result} = last_return = FakeRead.read(last_invocation)
    assert Read.valid_return?(last_return, last_invocation)
    assert last_result.next_cursor == nil
  end

  test "rejects invalid cursors and a continuation without progress" do
    refute Invocation.valid?(invocation({:page, 1}))

    invocation = invocation(%{"page" => 2})
    result = %Result{records: [], next_cursor: %{"page" => 2}}

    refute Result.valid_for?(result, invocation)
    refute Read.valid_return?({:ok, result}, invocation)
  end

  test "treats metadata as safe non-authoritative data" do
    invocation = invocation(%{"page" => 2})

    assert Result.valid_for?(
             %Result{
               records: [],
               next_cursor: %{"page" => 3},
               metadata: %{"page" => 999}
             },
             invocation
           )

    refute Result.valid?(%Result{
             records: [],
             next_cursor: %{"page" => 3},
             metadata: %{page: 3}
           })
  end

  test "accepts a normalized top-level error only with a valid invocation" do
    error = %Error{category: :timeout, code: "source_timeout"}

    assert Read.valid_return?({:error, error}, invocation(nil))
    refute Read.valid_return?({:error, error}, invocation({:invalid, :cursor}))
    refute Read.valid_return?(:timeout, invocation(nil))
  end

  test "redacts credentials during inspection" do
    secret = "read-secret-that-must-not-leak"
    inspected = inspect(%Invocation{config: %{}, credentials: %{"token" => secret}, cursor: nil})

    assert inspected =~ "credentials: :redacted"
    refute inspected =~ secret
  end

  defp invocation(cursor) do
    %Invocation{config: %{"page_size" => 100}, credentials: %{}, cursor: cursor}
  end
end
