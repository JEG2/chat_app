defmodule ChatApp.ConnectionManager do
  use GenServer
  alias ChatApp.{Connection, ConnectionSupervisor, Listener}

  @packet_size 2

  defstruct mode: :ready, name: nil, ui: nil, me: nil

  def start_link(options) do
    GenServer.start_link(
      __MODULE__,
      options,
      name: Keyword.get(options, :name, __MODULE__)
    )
  end

  def listen(manager \\ __MODULE__, port, name) do
    GenServer.call(manager, {:listen, port, name})
  end

  def connect(manager \\ __MODULE__, host, port, name) do
    GenServer.call(manager, {:connect, host, port, name})
  end

  def send_to_all(manager \\ __MODULE__, message) do
    GenServer.call(manager, {:send_to_all, message})
  end

  def receive_message(manager \\ __MODULE__, message, from) do
    GenServer.cast(manager, {:receive_message, message, from})
  end

  def receive_send_error(manager \\ __MODULE__, message_id, error) do
    GenServer.cast(manager, {:receive_send_error, message_id, error})
  end

  def reset(manager \\ __MODULE__), do: GenServer.call(manager, :reset)

  def init(options) do
    case Keyword.get(options, :ui) do
      ui when is_atom(ui) ->
        me = Keyword.get(options, :name, __MODULE__) || self()
        {:ok, %__MODULE__{ui: ui, me: me}}

      _no_ui ->
        {:stop, "ConnectionManager must be started with a UI module"}
    end
  end

  def handle_call({:listen, port, name}, _from, state) do
    case start_listening(port, state.me) do
      :ok ->
        {:reply, :ok, %__MODULE__{state | mode: :host, name: name}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, host, port, name}, _from, state) do
    case listen_to_connection(host, port, state.me) do
      :ok ->
        new_state = %__MODULE__{state | mode: :client, name: name}
        send_now(:connected, new_state)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:send_to_all, message}, _from, state) do
    result = send_now(message, state)
    {:reply, result, state}
  end

  def handle_call(:reset, _from, state) do
    send_now(:disconnected, state)

    for_active_connections(fn {:undefined, pid, :worker, [module]} ->
      apply(module, :close, [pid])
    end)

    {:reply, :ok, %__MODULE__{}}
  end

  def handle_cast({:receive_message, message, from}, state) do
    if state.mode == :host do
      for_active_connections(fn
        {:undefined, pid, :worker, [Connection]} when pid != from ->
          Connection.send(pid, message)

        _listener_or_from ->
          :ok
      end)
    end

    {name, content} = :erlang.binary_to_term(message)
    state.ui.show_chat_message(name, content)

    {:noreply, state}
  end

  def handle_cast({:receive_send_error, message_id, _error}, state) do
    state.ui.show_send_failure(message_id)
    {:noreply, state}
  end

  defp start_listening(port, me) do
    case :gen_tcp.listen(
           port,
           [:binary, packet: @packet_size, active: false, reuseaddr: true]
         ) do
      {:ok, listening_socket} ->
        Listener.listen(listening_socket, me)

      error ->
        error
    end
  end

  defp listen_to_connection(host, port, me) do
    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [:binary, packet: @packet_size, active: false]
         ) do
      {:ok, socket} ->
        Connection.listen(socket, me)

      error ->
        error
    end
  end

  defp send_now(message, %__MODULE__{mode: mode} = state)
       when mode in ~w[host client]a do
    ref = make_ref()
    prepared_message = :erlang.term_to_binary({state.name, message})

    for_active_connections(fn
      {:undefined, pid, :worker, [Connection]} ->
        Connection.send(pid, ref, prepared_message)

      _listener ->
        :ok
    end)

    {ref, state.name}
  end

  defp send_now(_message, _state), do: nil

  defp for_active_connections(func) do
    ConnectionSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.filter(fn {:undefined, pid_or_restarting, :worker, _modules} ->
      is_pid(pid_or_restarting)
    end)
    |> Enum.each(func)
  end
end
