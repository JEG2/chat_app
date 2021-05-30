defmodule ChatApp.ConnectionManager do
  use GenServer
  alias ChatApp.{Connection, ConnectionSupervisor, Listener}

  @packet_size 2

  defstruct mode: :ready, name: nil

  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def listen(port, name), do: GenServer.call(__MODULE__, {:listen, port, name})

  def connect(host, port, name) do
    GenServer.call(__MODULE__, {:connect, host, port, name})
  end

  def send_to_all(message) do
    ref = make_ref()
    GenServer.cast(__MODULE__, {:send_to_all, ref, message})
    ref
  end

  def forward(message, from) do
    GenServer.cast(__MODULE__, {:forward, message, from})
  end

  def reset, do: GenServer.call(__MODULE__, :reset)

  def init([]), do: {:ok, %__MODULE__{}}

  def handle_call({:listen, port, name}, _from, state) do
    case start_listening(port) do
      :ok ->
        {:reply, :ok, %__MODULE__{state | mode: :host, name: name}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, host, port, name}, _from, state) do
    case listen_to_connection(host, port) do
      :ok ->
        {:reply, :ok, %__MODULE__{state | mode: :client, name: name}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:reset, _from, _state) do
    for_active_connections(fn {:undefined, pid, :worker, [module]} ->
      apply(module, :close, [pid])
    end)

    {:reply, :ok, %__MODULE__{}}
  end

  def handle_cast(
        {:send_to_all, _ref, _message},
        %__MODULE__{mode: :ready} = state
      ) do
    {:noreply, state}
  end

  def handle_cast({:send_to_all, ref, message}, state) do
    prepared_message = :erlang.term_to_binary({state.name, message})

    for_active_connections(fn
      {:undefined, pid, :worker, [Connection]} ->
        Connection.send(pid, ref, prepared_message)

      _listener ->
        :ok
    end)

    {:noreply, state}
  end

  def handle_cast(
        {:forward, message, from},
        %__MODULE__{mode: :host} = state
      ) do
    for_active_connections(fn
      {:undefined, pid, :worker, [Connection]} when pid != from ->
        Connection.send(pid, make_ref(), message)

      _listener_or_from ->
        :ok
    end)

    {:noreply, state}
  end

  def handle_cast({:forward, _message, _from}, state), do: {:noreply, state}

  defp start_listening(port) do
    case :gen_tcp.listen(
           port,
           [:binary, packet: @packet_size, active: false, reuseaddr: true]
         ) do
      {:ok, listening_socket} ->
        Listener.listen(listening_socket)

      error ->
        error
    end
  end

  defp listen_to_connection(host, port) do
    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [:binary, packet: @packet_size, active: false]
         ) do
      {:ok, socket} ->
        Connection.listen(socket)

      error ->
        error
    end
  end

  defp for_active_connections(func) do
    ConnectionSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.filter(fn {:undefined, pid_or_restarting, :worker, _modules} ->
      is_pid(pid_or_restarting)
    end)
    |> Enum.each(func)
  end
end
