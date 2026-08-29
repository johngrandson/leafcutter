defmodule LeafcutterConnectors.Operation.WriteTest do
  use ExUnit.Case, async: true

  alias LeafcutterConnectors.Operation.Error
  alias LeafcutterConnectors.Operation.Write
  alias LeafcutterConnectors.Operation.Write.{Invocation, Item, ItemResult, Result}

  defmodule FakeWrite do
    @moduledoc false

    @behaviour LeafcutterConnectors.Operation.Write

    alias LeafcutterConnectors.Operation.Error
    alias LeafcutterConnectors.Operation.Write.{Invocation, Item, ItemResult, Result}

    @impl true
    def write(%Invocation{items: items}) do
      results =
        Enum.map(items, fn
          %Item{ref: "rejected"} ->
            %ItemResult{
              ref: "rejected",
              outcome: {:error, %Error{category: :validation, code: "rejected"}}
            }

          %Item{ref: "no-identity"} ->
            %ItemResult{ref: "no-identity", outcome: {:ok, nil}}

          %Item{ref: ref} ->
            %ItemResult{ref: ref, outcome: {:ok, %{"id" => ref}}}
        end)

      {:ok, %Result{results: results}}
    end
  end

  test "validates a complete ordered result with partial success" do
    invocation = invocation([item("accepted"), item("rejected"), item("no-identity")])

    assert Invocation.valid?(invocation)
    assert {:ok, result} = return = FakeWrite.write(invocation)
    assert Write.valid_return?(return, invocation)

    assert [
             %ItemResult{ref: "accepted", outcome: {:ok, %{"id" => "accepted"}}},
             %ItemResult{ref: "rejected", outcome: {:error, %Error{}}},
             %ItemResult{ref: "no-identity", outcome: {:ok, nil}}
           ] = result.results
  end

  test "accepts ok when every item has a normalized error" do
    invocation = invocation([item("first"), item("second")])
    error = %Error{category: :validation, code: "rejected"}

    result = %Result{
      results: [
        %ItemResult{ref: "first", outcome: {:error, error}},
        %ItemResult{ref: "second", outcome: {:error, error}}
      ]
    }

    assert Write.valid_return?({:ok, result}, invocation)
  end

  test "reserves top-level errors for missing complete classification" do
    invocation = invocation([item("first")])
    error = %Error{category: :timeout, code: "batch_timeout"}

    assert Write.valid_return?({:error, error}, invocation)
    refute Write.valid_return?({:error, :timeout}, invocation)
    refute Write.valid_return?(:timeout, invocation)
  end

  test "requires a non-empty batch with valid payloads and unique refs" do
    refute Invocation.valid?(invocation([]))
    refute Invocation.valid?(invocation([item("duplicate"), item("duplicate")]))
    refute Invocation.valid?(invocation([item("invalid", {:tuple, :payload})]))
    refute Invocation.valid?(invocation([item("  ")]))
  end

  test "rejects missing, extra, duplicated, reordered, and divergent results" do
    invocation = invocation([item("first"), item("second")])
    first = %ItemResult{ref: "first", outcome: {:ok, "external-1"}}
    second = %ItemResult{ref: "second", outcome: {:ok, "external-2"}}
    extra = %ItemResult{ref: "extra", outcome: {:ok, "external-3"}}
    divergent = %ItemResult{ref: "different", outcome: {:ok, "external-2"}}

    invalid_results = [
      %Result{results: [first]},
      %Result{results: [first, second, extra]},
      %Result{results: [first, first]},
      %Result{results: [second, first]},
      %Result{results: [first, divergent]}
    ]

    refute Enum.any?(invalid_results, &Result.valid_for?(&1, invocation))
  end

  test "redacts credentials during inspection" do
    secret = "write-secret-that-must-not-leak"

    inspected =
      inspect(%Invocation{
        config: %{},
        credentials: %{"token" => secret},
        items: [item("first")]
      })

    assert inspected =~ "credentials: :redacted"
    refute inspected =~ secret
  end

  defp invocation(items) do
    %Invocation{config: %{"mode" => "upsert"}, credentials: %{}, items: items}
  end

  defp item(ref), do: item(ref, %{"value" => ref})

  defp item(ref, payload) do
    %Item{ref: ref, payload: payload}
  end
end
