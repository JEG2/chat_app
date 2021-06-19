defmodule ChatApp.Listener do
  use GenServer, restart: :transient
  alias ChatApp.{Connection, ConnectionSupervisor}

  defstruct ~w[listening_socket manager]a

  def listen(listening_socket, manager) do
    case DynamicSupervisor.start_child(
           ConnectionSupervisor,
           {__MODULE__, [listening_socket, manager]}
         ) do
      {:ok, listener} ->
        transfer_control(listening_socket, listener)

      error ->
        error
    end
  end

  def start_link([listening_socket, manager]) do
    GenServer.start_link(__MODULE__, [listening_socket, manager])
  end

  def close(listener), do: GenServer.cast(listener, :close)

  def init([listening_socket, manager]) do
    {:ok, %__MODULE__{listening_socket: listening_socket, manager: manager}}
  end

  def handle_cast(:accept, state) do
    case :gen_tcp.accept(state.listening_socket, 1_000) do
      {:ok, socket} ->
        Connection.listen(socket, state.manager)
        accept(self())
        {:noreply, state}

      {:error, :closed} ->
        {:stop, :normal, %__MODULE__{state | listening_socket: nil}}

      _error ->
        accept(self())
        {:noreply, state}
    end
  end

  def handle_cast(:close, state) do
    :gen_tcp.close(state.listening_socket)
    {:stop, :normal, %__MODULE__{state | listening_socket: nil}}
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
