defmodule LeafcutterConnectors.TestHTTPServer do
  @moduledoc false

  @request_limit 1_048_576

  @type response :: iodata() | {:chunks, [iodata()]} | :close

  @type t :: %{
          counter: pid(),
          pid: pid(),
          port: :inet.port_number()
        }

  @spec start((binary(), pos_integer() -> response())) :: t()
  def start(handler) when is_function(handler, 2) do
    owner = self()
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    pid = spawn_link(fn -> init(owner, counter, handler) end)

    receive do
      {:http_server_started, ^pid, port} ->
        %{counter: counter, pid: pid, port: port}
    after
      1_000 ->
        raise "local HTTP server did not start"
    end
  end

  @spec stop(t()) :: :ok
  def stop(%{counter: counter, pid: pid}) do
    Process.unlink(pid)
    Process.unlink(counter)

    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end

    if Process.alive?(counter) do
      Agent.stop(counter)
    end

    :ok
  end

  @spec attempts(t()) :: non_neg_integer()
  def attempts(%{counter: counter}), do: Agent.get(counter, & &1)

  @spec url(t(), String.t()) :: String.t()
  def url(%{port: port}, path \\ "/") do
    "http://127.0.0.1:#{port}#{path}"
  end

  @spec init(pid(), pid(), (binary(), pos_integer() -> response())) :: no_return()
  defp init(owner, counter, handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_address, port}} = :inet.sockname(listener)
    send(owner, {:http_server_started, self(), port})
    accept_loop(listener, counter, handler)
  end

  @spec accept_loop(
          :gen_tcp.socket(),
          pid(),
          (binary(), pos_integer() -> response())
        ) ::
          no_return()
  defp accept_loop(listener, counter, handler) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        serve(socket, counter, handler)
        accept_loop(listener, counter, handler)

      {:error, :closed} ->
        exit(:normal)

      {:error, reason} ->
        exit(reason)
    end
  end

  @spec serve(
          :gen_tcp.socket(),
          pid(),
          (binary(), pos_integer() -> response())
        ) :: :ok
  defp serve(socket, counter, handler) do
    case receive_request(socket, "") do
      {:ok, request} ->
        attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)
        send_response(socket, handler.(request, attempt))

      {:error, _reason} ->
        :ok
    end

    :gen_tcp.close(socket)
  end

  @spec receive_request(:gen_tcp.socket(), binary()) :: {:ok, binary()} | {:error, term()}
  defp receive_request(socket, received) when byte_size(received) <= @request_limit do
    case :binary.match(received, "\r\n\r\n") do
      {header_end, 4} ->
        header_size = header_end + 4
        body_size = request_body_size(binary_part(received, 0, header_size))
        receive_body(socket, received, header_size + body_size)

      :nomatch ->
        receive_more(socket, received)
    end
  end

  defp receive_request(_socket, _received), do: {:error, :request_too_large}

  @spec receive_body(:gen_tcp.socket(), binary(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  defp receive_body(_socket, received, expected_size)
       when byte_size(received) >= expected_size do
    {:ok, binary_part(received, 0, expected_size)}
  end

  defp receive_body(socket, received, expected_size) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, data} -> receive_body(socket, received <> data, expected_size)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec receive_more(:gen_tcp.socket(), binary()) :: {:ok, binary()} | {:error, term()}
  defp receive_more(socket, received) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, data} -> receive_request(socket, received <> data)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec request_body_size(binary()) :: non_neg_integer()
  defp request_body_size(headers) do
    case Regex.run(~r/\r\ncontent-length:[ \t]*(\d+)\r\n/i, headers) do
      [_match, length] -> String.to_integer(length)
      nil -> 0
    end
  end

  @spec send_response(:gen_tcp.socket(), response()) :: :ok
  defp send_response(_socket, :close), do: :ok

  defp send_response(socket, {:chunks, chunks}) when is_list(chunks) do
    Enum.each(chunks, fn chunk ->
      _result = :gen_tcp.send(socket, chunk)
    end)
  end

  defp send_response(socket, response) do
    _result = :gen_tcp.send(socket, response)
    :ok
  end
end
