defmodule Leafcutter.Organizations.RolesConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Leafcutter.Organizations
  alias Leafcutter.Organizations.{Organization, Role, RolePermission, Roles}
  alias Leafcutter.Repo

  test "role creation observes a concurrent organization disable" do
    organization = create_organization()
    on_exit(fn -> delete_organization(organization.id) end)

    pause_next_for_update()

    disable_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Organizations.disable(organization.id) end)
      end)

    assert_receive {:row_locked, disable_process}, 1_000

    role_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Roles.create(%{organization_id: organization.id, name: "operator"})
        end)
      end)

    assert Task.yield(role_task, 100) == nil

    send(disable_process, :continue_transaction)

    assert {:ok, %Organization{disabled_at: %DateTime{}}} = Task.await(disable_task)
    assert {:error, :organization_disabled} = Task.await(role_task)
  end

  test "concurrent role disables preserve one lifecycle timestamp" do
    {organization, role} = create_role()
    on_exit(fn -> delete_organization(organization.id) end)

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Roles.disable(role.id) end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn -> Roles.disable(role.id) end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, first_disable} = Task.await(first_task)
    assert {:ok, second_disable} = Task.await(second_task)
    assert second_disable.disabled_at == first_disable.disabled_at
  end

  test "concurrent permission grants persist one association" do
    {organization, role} = create_role()
    on_exit(fn -> delete_organization(organization.id) end)

    pause_next_for_update()

    first_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Roles.grant_permission(role.id, :environment_manage)
        end)
      end)

    assert_receive {:row_locked, first_process}, 1_000

    second_task =
      Task.async(fn ->
        with_unboxed_connection(fn ->
          Roles.grant_permission(role.id, :environment_manage)
        end)
      end)

    assert Task.yield(second_task, 100) == nil

    send(first_process, :continue_transaction)

    assert {:ok, %RolePermission{}} = Task.await(first_task)
    assert {:error, :permission_already_granted} = Task.await(second_task)
  end

  defp create_organization do
    suffix = System.unique_integer([:positive])

    with_unboxed_connection(fn ->
      {:ok, organization} = Organizations.create(%{name: "Concurrent #{suffix}"})
      organization
    end)
  end

  defp create_role do
    organization = create_organization()

    role =
      with_unboxed_connection(fn ->
        {:ok, role} =
          Roles.create(%{organization_id: organization.id, name: "operator"})

        role
      end)

    {organization, role}
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
      role_ids =
        Role
        |> where([role], role.organization_id == ^organization_id)
        |> select([role], role.id)
        |> Repo.all()

      RolePermission
      |> where([role_permission], role_permission.role_id in ^role_ids)
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
