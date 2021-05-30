defmodule ChatApp.Connection do
  use GenServer, restart: :transient
  alias ChatApp.{ConnectionManager, ConnectionSupervisor}

  def listen(socket) do
    case DynamicSupervisor.start_child(
           ConnectionSupervisor,
           {__MODULE__, socket}
         ) do
      {:ok, connection} ->
        transfer_control(socket, connection)

      error ->
        error
    end
  end

  def start_link(socket), do: GenServer.start_link(__MODULE__, socket)

  def send(connection, ref, message) do
    GenServer.cast(connection, {:send, ref, message})
  end

  def close(connection), do: GenServer.cast(connection, :close)

  def init(socket), do: {:ok, socket}

  def handle_cast(:activate, nil), do: {:noreply, nil}

  def handle_cast(:activate, socket) do
    :inet.setopts(socket, active: :once)
    {:noreply, socket}
  end

  def handle_cast({:send, ref, message}, socket) do
    case :gen_tcp.send(socket, message) do
      :ok ->
        :ok

      _error ->
        # FIXME
        # GUI.mark_send_failure(ref)
        IO.puts("Message #{inspect(ref)} failed to reach a participant.")
    end

    {:noreply, socket}
  end

  def handle_cast(:close, nil), do: {:stop, :normal, nil}

  def handle_cast(:close, socket) do
    :gen_tcp.close(socket)
    {:stop, :normal, nil}
  end

  def handle_info({:tcp_closed, socket}, socket), do: {:stop, :normal, nil}

  def handle_info({:tcp, socket, message}, socket) do
    {name, content} = :erlang.binary_to_term(message)
    ConnectionManager.forward(message, self())
    # FIXME
    # GUI.receive(name, content)
    IO.puts("#{name}:  #{content}")
    activate(self())
    {:noreply, socket}
  end

  def handle_info(_unexpected_message, socket), do: {:noreply, socket}

  defp transfer_control(socket, connection) do
    case :gen_tcp.controlling_process(socket, connection) do
      :ok ->
        activate(connection)
        :ok

      error ->
        close(connection)
        error
    end
  end

  defp activate(connection), do: GenServer.cast(connection, :activate)
end
