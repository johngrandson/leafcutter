defmodule Leafcutter.Organizations.ServiceAccountRoleAssignmentsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.Access.ServiceAccounts, as: ServiceAccountAccess

  alias Leafcutter.Organizations.{
    Organization,
    Role,
    Roles,
    ServiceAccount,
    ServiceAccountRoleAssignment,
    ServiceAccounts
  }

  alias Leafcutter.Repo

  test "role assignment observes a concurrent service account disable" do
    {organization, service_account, role} = create_scope()
    on_exit(fn -> delete_scope(organization.id) end)

    pause_next_for_update()

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> ServiceAccounts.disable(service_account.id) end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    assignment_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          ServiceAccountAccess.assign_role(%{
            service_account_id: service_account.id,
            role_id: role.id
          })
        end)
      end)

    assert Task.yield(assignment_task, 100) == nil

    send(disable_process, :continue_transaction)

    assert {:ok, %ServiceAccount{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :service_account_disabled} = Task.await(assignment_task)
  end

  test "concurrent role assignment persists only one association" do
    {organization, service_account, role} = create_scope()
    on_exit(fn -> delete_scope(organization.id) end)

    attrs = %{service_account_id: service_account.id, role_id: role.id}

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> ServiceAccountAccess.assign_role(attrs) end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> ServiceAccountAccess.assign_role(attrs) end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, %ServiceAccountRoleAssignment{}} = Task.await(first_task)
    assert {:error, :role_already_assigned} = Task.await(second_task)
  end

  defp create_scope do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} = Organizations.create(%{name: "Concurrent #{suffix}"})

      {:ok, service_account} =
        ServiceAccounts.create(%{
          organization_id: organization.id,
          name: "agent-#{suffix}"
        })

      {:ok, role} =
        Roles.create(%{
          organization_id: organization.id,
          name: "operator-#{suffix}"
        })

      {organization, service_account, role}
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

  defp delete_scope(organization_id) do
    with_unboxed_connection(fn ->
      service_account_ids =
        ServiceAccount
        |> where([service_account], service_account.organization_id == ^organization_id)
        |> select([service_account], service_account.id)
        |> Repo.all()

      role_ids =
        Role
        |> where([role], role.organization_id == ^organization_id)
        |> select([role], role.id)
        |> Repo.all()

      ServiceAccountRoleAssignment
      |> where(
        [assignment],
        assignment.service_account_id in ^service_account_ids or assignment.role_id in ^role_ids
      )
      |> Repo.delete_all()

      ServiceAccount
      |> where([service_account], service_account.organization_id == ^organization_id)
      |> Repo.delete_all()

      Role
      |> where([role], role.organization_id == ^organization_id)
      |> Repo.delete_all()

      Organization
      |> where([organization], organization.id == ^organization_id)
      |> Repo.delete_all()
    end)
  end
end
