defmodule ChatApp.Listener do
  use GenServer, restart: :transient
  alias ChatApp.{Connection, ConnectionSupervisor}

  def listen(listening_socket) do
    case DynamicSupervisor.start_child(
           ConnectionSupervisor,
           {__MODULE__, listening_socket}
         ) do
      {:ok, listener} ->
        transfer_control(listening_socket, listener)

      error ->
        error
    end
  end

  def start_link(listening_socket) do
    GenServer.start_link(__MODULE__, listening_socket)
  end

  def close(listener), do: GenServer.cast(listener, :close)

  def init(listening_socket), do: {:ok, listening_socket}

  def handle_cast(:accept, nil), do: {:noreply, nil}

  def handle_cast(:accept, listening_socket) do
    case :gen_tcp.accept(listening_socket, 1_000) do
      {:ok, socket} ->
        Connection.listen(socket)
        accept(self())
        {:noreply, listening_socket}

      {:error, :closed} ->
        {:stop, :normal, nil}

      _error ->
        accept(self())
        {:noreply, listening_socket}
    end
  end

  def handle_cast(:close, nil), do: {:stop, :normal, nil}

  def handle_cast(:close, listening_socket) do
    :gen_tcp.close(listening_socket)
    {:stop, :normal, nil}
  end

  defp transfer_control(listening_socket, listener) do
    case :gen_tcp.controlling_process(listening_socket, listener) do
      :ok ->
        accept(listener)
        :ok

      error ->
        close(listener)
        error
    end
  end

  defp accept(listener), do: GenServer.cast(listener, :accept)
end
