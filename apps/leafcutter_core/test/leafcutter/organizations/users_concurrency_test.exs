defmodule Leafcutter.Organizations.UsersConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations.User
  alias Leafcutter.Organizations.Users
  alias Leafcutter.Repo

  test "concurrent user disables preserve one lifecycle timestamp" do
    email = "concurrent-#{System.unique_integer([:positive])}@example.com"

    user =
      with_unboxed_connection(fn ->
        {:ok, user} = Users.create(%{email: email})
        user
      end)

    on_exit(fn -> delete_user(user.id) end)

    pause_next_for_update()

    first_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Users.disable(user.id) end)
      end)

    assert_receive {:row_locked, first_disable_process}, 1_000

    second_disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Users.disable(user.id) end)
      end)

    assert Task.yield(second_disable_task, 100) == nil

    send(first_disable_process, :continue_disable)

    assert {:ok, first_disable} = Task.await(first_disable_task)
    assert {:ok, second_disable} = Task.await(second_disable_task)
    assert second_disable.disabled_at == first_disable.disabled_at
  end

  defp pause_next_for_update do
    handler_id = {__MODULE__, make_ref()}
    test_process = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:leafcutter, :repo, :query],
        fn _event, _measurements, metadata, {test_process, handler_id} ->
          if String.contains?(metadata.query, "FOR UPDATE") do
            :telemetry.detach(handler_id)
            send(test_process, {:row_locked, self()})

            receive do
              :continue_disable -> :ok
            after
              1_000 -> raise "timed out while holding a row lock"
            end
          end
        end,
        {test_process, handler_id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp with_unboxed_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      :ok = Sandbox.checkin(Repo)
    end
  end

  defp delete_user(user_id) do
    with_unboxed_connection(fn ->
      User
      |> where([user], user.id == ^user_id)
      |> Repo.delete_all()
    end)
  end
end
