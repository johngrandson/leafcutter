defmodule Leafcutter.Organizations.AccessConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access
  alias Leafcutter.Organizations.Membership
  alias Leafcutter.Organizations.Organization
  alias Leafcutter.Organizations.User
  alias Leafcutter.Organizations.Users
  alias Leafcutter.Repo

  test "membership creation observes a concurrent organization disable" do
    {organization, user} = create_participants()
    on_exit(fn -> delete_participants(organization.id, user.id) end)

    pause_next_for_update()

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Organizations.disable(organization.id) end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    membership_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.add_member(%{
            organization_id: organization.id,
            user_id: user.id
          })
        end)
      end)

    assert Task.yield(membership_task, 100) == nil

    send(disable_process, :continue_transaction)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :organization_disabled} = Task.await(membership_task)
  end

  test "membership creation observes a concurrent user disable" do
    {organization, user} = create_participants()
    on_exit(fn -> delete_participants(organization.id, user.id) end)

    pause_next_for_update()

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Users.disable(user.id) end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    membership_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.add_member(%{
            organization_id: organization.id,
            user_id: user.id
          })
        end)
      end)

    assert Task.yield(membership_task, 100) == nil

    send(disable_process, :continue_transaction)

    assert {:ok, %User{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :user_disabled} = Task.await(membership_task)
  end

  test "concurrent membership creation persists only one membership" do
    {organization, user} = create_participants()
    on_exit(fn -> delete_participants(organization.id, user.id) end)

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.add_member(%{
            organization_id: organization.id,
            user_id: user.id
          })
        end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.add_member(%{
            organization_id: organization.id,
            user_id: user.id
          })
        end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, %Membership{}} = Task.await(first_task)
    assert {:error, :membership_already_exists} = Task.await(second_task)
  end

  test "concurrent membership removals preserve one lifecycle timestamp" do
    {organization, user} = create_participants()
    on_exit(fn -> delete_participants(organization.id, user.id) end)

    with_unboxed_connection(fn ->
      {:ok, _membership} =
        Access.add_member(%{
          organization_id: organization.id,
          user_id: user.id
        })
    end)

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.remove_member(organization.id, user.id)
        end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Access.remove_member(organization.id, user.id)
        end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, first_removal} = Task.await(first_task)
    assert {:ok, second_removal} = Task.await(second_task)
    assert second_removal.disabled_at == first_removal.disabled_at
  end

  defp create_participants do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} =
        Organizations.create(%{name: "Concurrent #{suffix}"})

      {:ok, user} =
        Users.create(%{email: "concurrent-#{suffix}@example.com"})

      {organization, user}
    end)
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
              :continue_transaction -> :ok
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

  defp delete_participants(organization_id, user_id) do
    with_unboxed_connection(fn ->
      Membership
      |> where(
        [membership],
        membership.organization_id == ^organization_id and
          membership.user_id == ^user_id
      )
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^organization_id)
      |> Repo.delete_all()

      User
      |> where([user], user.id == ^user_id)
      |> Repo.delete_all()
    end)
  end
end
