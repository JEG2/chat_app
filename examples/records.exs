defmodule Chat do
  require Record
  Record.defrecordp(:member, name: nil, connected?: false)
  def connect(name), do: member(name: name, connected?: true)
  def connected?(m), do: member(m, :connected?)
  def greet(member(name: name, connected?: true)), do: "Welcome #{name}!"
end

james = Chat.connect("JEG2") |> IO.inspect()
Chat.connected?(james) |> IO.inspect()
Chat.greet(james) |> IO.inspect()
