defmodule ChatApp.Connection do
  use GenServer, restart: :transient
  alias ChatApp.{ConnectionManager, ConnectionSupervisor}

  defstruct ~w[socket manager]a

  def listen(socket, manager) do
    case DynamicSupervisor.start_child(
           ConnectionSupervisor,
           {__MODULE__, [socket, manager]}
         ) do
      {:ok, connection} ->
        transfer_control(socket, connection)

      error ->
        error
    end
  end

  def start_link([socket, manager]) do
    GenServer.start_link(__MODULE__, [socket, manager])
  end

  def send(connection, message) do
    send(connection, nil, message)
  end

  def send(connection, message_id, message) do
    GenServer.cast(connection, {:send, message_id, message})
  end

  def close(connection), do: GenServer.cast(connection, :close)

  def init([socket, manager]) do
    {:ok, %__MODULE__{socket: socket, manager: manager}}
  end

  def handle_cast(:activate, state) do
    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end

  def handle_cast({:send, message_id, message}, state) do
    case :gen_tcp.send(state.socket, message) do
      :ok ->
        :ok

      error ->
        if is_reference(message_id) do
          ConnectionManager.receive_send_error(state.manager, message_id, error)
        end
    end

    {:noreply, state}
  end

  def handle_cast(:close, state) do
    :gen_tcp.close(state.socket)
    {:stop, :normal, %__MODULE__{state | socket: nil}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, %__MODULE__{state | socket: nil}}
  end

  def handle_info({:tcp, _socket, message}, state) do
    ConnectionManager.receive_message(state.manager, message, self())
    activate(self())
    {:noreply, state}
  end

  def handle_info(_unexpected_message, state), do: {:noreply, state}

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
