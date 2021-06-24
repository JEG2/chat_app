defmodule ChatApp.GUI do
  use GenServer
  use Bitwise
  require Record
  alias ChatApp.ConnectionManager

  Record.extract_all(from_lib: "wx/include/wx.hrl")
  |> Enum.map(fn {name, fields} -> Record.defrecordp(name, fields) end)

  # constants from wx/include/wx.hrl
  @default 70
  @multiline 32
  @rich 32768
  @horizontal 4
  @vertical 8
  @left 16
  @right 32
  @up 64
  @down 128
  @all @left ||| @right ||| @up ||| @down
  @expand 8192
  @return_key 13

  defstruct window: nil,
            chat: nil,
            bold: nil,
            italic: nil,
            input: nil,
            button: nil,
            active_sends: Map.new()

  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def show_chat_message(name, content) do
    GenServer.cast(__MODULE__, {:show_chat_message, name, content})
  end

  def show_send_failure(ref) do
    GenServer.cast(__MODULE__, {:show_send_failure, ref})
  end

  def init([]) do
    :timer.send_interval(5 * 60 * 1_000, :prune_active_sends)
    {:ok, %__MODULE__{}, {:continue, :show_gui}}
  end

  def handle_cast({:show_chat_message, name, action}, state)
      when is_atom(action) do
    append_text_with_font(state.chat, "#{name} #{action}\n", state.italic)
    {:noreply, state}
  end

  def handle_cast({:show_chat_message, name, content}, state) do
    append_message(name, content, state)
    {:noreply, state}
  end

  def handle_cast({:show_send_failure, ref}, state) do
    case Map.pop(state.active_sends, ref) do
      {{message, _timestamp}, new_active_sends} ->
        append_text_with_font(
          state.chat,
          "The following message was not received by all participants:  " <>
            "#{message}\n",
          state.italic
        )

        {:noreply, %__MODULE__{state | active_sends: new_active_sends}}

      {nil, _active_sends} ->
        {:noreply, state}
    end
  end

  def handle_continue(:show_gui, state) do
    wx = :wx.new()
    gui = :wx.batch(fn -> prepare_gui(wx) end)
    :wxWindow.show(gui.window)

    {
      :noreply,
      %__MODULE__{
        state
        | window: gui.window,
          chat: gui.chat,
          bold: gui.bold,
          italic: gui.italic,
          input: gui.input,
          button: gui.button
      }
    }
  end

  def handle_info(
        wx(
          id: _id,
          obj: window,
          userData: _userData,
          event: wxClose(type: :close_window)
        ),
        %__MODULE__{window: window} = state
      ) do
    quit(state)
    {:noreply, state}
  end

  def handle_info(
        wx(
          id: _id,
          obj: input,
          userData: _userData,
          event:
            wxKey(
              type: :key_down,
              x: _x,
              y: _y,
              keyCode: @return_key,
              controlDown: false,
              shiftDown: false,
              altDown: false,
              metaDown: false,
              uniChar: _uniChar,
              rawCode: _rawCode,
              rawFlags: _rawFlags
            )
        ),
        %__MODULE__{input: input} = state
      ) do
    new_active_sends = process_input(state)
    {:noreply, %__MODULE__{state | active_sends: new_active_sends}}
  end

  def handle_info(
        wx(
          id: _id,
          obj: button,
          userData: _userData,
          event:
            wxCommand(
              type: :command_button_clicked,
              cmdString: _cmdString,
              commandInt: _commandInt,
              extraLong: _extraLong
            )
        ),
        %__MODULE__{button: button} = state
      ) do
    new_active_sends = process_input(state)
    {:noreply, %__MODULE__{state | active_sends: new_active_sends}}
  end

  def handle_info(:prune_active_sends, state) do
    expired = System.monotonic_time(:second) - 5 * 60

    new_active_sends =
      state.active_sends
      |> Enum.reject(fn {_ref, {_message, timestamp}} ->
        timestamp < expired
      end)
      |> Map.new()

    {:noreply, %__MODULE__{state | active_sends: new_active_sends}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp prepare_gui(wx) do
    wx
    |> build_gui()
    |> layout_gui()
    |> setup_events()
  end

  defp build_gui(wx) do
    window = :wxFrame.new(wx, -1, "Chat", size: {800, 600})
    controls = :wxPanel.new(window)
    chat = :wxTextCtrl.new(controls, 1, style: @multiline ||| @rich)
    :wxTextCtrl.setEditable(chat, false)
    bold = :wxNORMAL_FONT |> :wxe_util.get_const() |> :wxFont.new()
    :wxFont.setWeight(bold, :wxe_util.get_const(:wxFONTWEIGHT_BOLD))
    italic = :wxe_util.get_const(:wxITALIC_FONT)

    c = "Commands:\n  /listen PORT NAME\n  /connect HOST PORT NAME\n  /quit\n"
    append_text_with_font(chat, c, italic)

    form = :wxPanel.new(controls)
    input = :wxTextCtrl.new(form, 2, style: @default)
    button = :wxButton.new(form, 3, label: "Send")

    %{
      window: window,
      controls: controls,
      chat: chat,
      bold: bold,
      italic: italic,
      form: form,
      input: input,
      button: button
    }
  end

  defp layout_gui(gui) do
    window_sizer = :wxBoxSizer.new(@vertical)

    :wxSizer.add(
      window_sizer,
      gui.controls,
      border: 4,
      proportion: 1,
      flag: @expand ||| @all
    )

    controls_sizer = :wxBoxSizer.new(@vertical)
    :wxSizer.add(controls_sizer, gui.chat, proportion: 1, flag: @expand)
    :wxSizer.addSpacer(controls_sizer, 4)
    :wxSizer.add(controls_sizer, gui.form, proportion: 0, flag: @expand)
    form_sizer = :wxBoxSizer.new(@horizontal)
    :wxSizer.add(form_sizer, gui.input, proportion: 1, flag: @expand)
    :wxSizer.addSpacer(controls_sizer, 4)
    :wxSizer.add(form_sizer, gui.button)
    :wxWindow.setSizer(gui.form, form_sizer)
    :wxWindow.setSizer(gui.controls, controls_sizer)
    :wxWindow.setSizer(gui.window, window_sizer)

    gui
  end

  defp setup_events(gui) do
    :wxWindow.setFocus(gui.input)

    :wxEvtHandler.connect(gui.window, :close_window)
    :wxEvtHandler.connect(gui.input, :key_down, skip: true)
    :wxEvtHandler.connect(gui.button, :command_button_clicked)

    gui
  end

  defp process_input(state) do
    new_active_sends =
      case state.input |> :wxTextCtrl.getValue() |> to_string() do
        "/" <> command ->
          process_command(command, state)
          state.active_sends

        message when byte_size(message) > 0 ->
          case ConnectionManager.send_to_all(message) do
            {ref, name} ->
              append_message(name, message, state)

              now = System.monotonic_time(:second)
              Map.put(state.active_sends, ref, {message, now})

            nil ->
              state.active_sends
          end

        "" ->
          state.active_sends
      end

    :wxTextCtrl.clear(state.input)
    new_active_sends
  end

  defp process_command("connect" <> args, state) do
    case Regex.named_captures(
           ~r{\A\s+(?<host>\S+)\s+(?<port>\d+)\s+(?<name>\S.*)\z},
           args
         ) do
      %{"host" => host, "port" => port, "name" => name} ->
        case ConnectionManager.connect(host, String.to_integer(port), name) do
          :ok ->
            append_text_with_font(state.chat, "Connected\n", state.italic)

          _error ->
            append_text_with_font(
              state.chat,
              "Error:  connecting failed\n",
              state.italic
            )
        end

      nil ->
        append_text_with_font(
          state.chat,
          "Usage:  /connect HOST PORT NAME\n",
          state.italic
        )
    end
  end

  defp process_command("listen" <> args, state) do
    case Regex.named_captures(~r{\A\s+(?<port>\d+)\s+(?<name>\S.*)\z}, args) do
      %{"port" => port, "name" => name} ->
        case ConnectionManager.listen(String.to_integer(port), name) do
          :ok ->
            append_text_with_font(state.chat, "Listening\n", state.italic)

          _error ->
            append_text_with_font(
              state.chat,
              "Error:  listening failed\n",
              state.italic
            )
        end

      nil ->
        append_text_with_font(
          state.chat,
          "Usage:  /listen PORT NAME\n",
          state.italic
        )
    end
  end

  defp process_command("quit", state), do: quit(state)

  defp process_command(_unknown_command, state) do
    append_text_with_font(
      state.chat,
      "Error:  unknown command\n",
      state.italic
    )
  end

  defp append_text(ctrl, text) do
    :wxTextCtrl.appendText(ctrl, text)
  end

  defp append_text_with_font(ctrl, text, font) do
    style = :wxTextCtrl.getDefaultStyle(ctrl)
    :wxTextAttr.setFont(style, font)
    :wxTextCtrl.setDefaultStyle(ctrl, style)
    append_text(ctrl, text)
    :wxTextAttr.setFont(style, :wxe_util.get_const(:wxNORMAL_FONT))
    :wxTextCtrl.setDefaultStyle(ctrl, style)
  end

  defp append_message(name, message, state) do
    append_text_with_font(state.chat, name, state.bold)
    append_text(state.chat, ":  #{message}\n")
  end

  defp quit(state) do
    ConnectionManager.reset()
    :wxWindow.destroy(state.window)
    :wx.destroy()
    System.stop(0)
  end
end
