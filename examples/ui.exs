defmodule UI do
  use Agent

  def start_link(iex) do
    Agent.start_link(fn -> iex end, name: __MODULE__)
  end

  def show_chat_message(name, content) do
    Agent.get(__MODULE__, &send(&1, {name, content}))
  end
end
