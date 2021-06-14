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
    GenServer.call(__MODULE__, {:send_to_all, message})
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

  def handle_call({:connect, host, port, name}, from, state) do
    case listen_to_connection(host, port) do
      :ok ->
        new_state = %__MODULE__{state | mode: :client, name: name}
        handle_call({:send_to_all, :connected}, from, new_state)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:send_to_all, _message},
        _from,
        %__MODULE__{mode: :ready} = state
      ) do
    {:reply, nil, state}
  end

  def handle_call({:send_to_all, message}, _from, state) do
    ref = make_ref()
    prepared_message = :erlang.term_to_binary({state.name, message})

    for_active_connections(fn
      {:undefined, pid, :worker, [Connection]} ->
        Connection.send(pid, ref, prepared_message)

      _listener ->
        :ok
    end)

    {:reply, {ref, state.name}, state}
  end

  def handle_call(:reset, from, state) do
    handle_call({:send_to_all, :disconnected}, from, state)

    for_active_connections(fn {:undefined, pid, :worker, [module]} ->
      apply(module, :close, [pid])
    end)

    {:reply, :ok, %__MODULE__{}}
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
