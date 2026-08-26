defmodule Leafcutter.Organizations.ServiceAccountsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.{Organization, ServiceAccount, ServiceAccounts}
  alias Leafcutter.Repo

  test "service account creation observes a concurrent organization disable" do
    organization = create_organization()
    on_exit(fn -> delete_organization(organization.id) end)

    pause_next_for_update()

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Organizations.disable(organization.id) end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    service_account_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          ServiceAccounts.create(%{
            organization_id: organization.id,
            name: "production-sync"
          })
        end)
      end)

    assert Task.yield(service_account_task, 100) == nil

    send(disable_process, :continue_transaction)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :organization_disabled} = Task.await(service_account_task)
  end

  test "concurrent service account disables preserve one lifecycle timestamp" do
    {organization, service_account} = create_service_account()
    on_exit(fn -> delete_organization(organization.id) end)

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> ServiceAccounts.disable(service_account.id) end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> ServiceAccounts.disable(service_account.id) end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, first_disable} = Task.await(first_task)
    assert {:ok, second_disable} = Task.await(second_task)
    assert second_disable.disabled_at == first_disable.disabled_at
  end

  defp create_organization do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} = Organizations.create(%{name: "Concurrent #{suffix}"})
      organization
    end)
  end

  defp create_service_account do
    organization = create_organization()

    service_account =
      with_unboxed_connection(fn ->
        {:ok, service_account} =
          ServiceAccounts.create(%{
            organization_id: organization.id,
            name: "production-sync"
          })

        service_account
      end)

    {organization, service_account}
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

  defp delete_organization(organization_id) do
    with_unboxed_connection(fn ->
      ServiceAccount
      |> where([service_account], service_account.organization_id == ^organization_id)
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^organization_id)
      |> Repo.delete_all()
    end)
  end
end
