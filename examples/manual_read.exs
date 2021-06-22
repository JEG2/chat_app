{:ok, socket} =
  :gen_tcp.connect(
    'localhost',
    4444,
    [:list, packet: :raw, active: false]
  )

{:ok, [length]} = :gen_tcp.recv(socket, 1)
{:ok, message} = :gen_tcp.recv(socket, length)
message |> to_string() |> IO.inspect()

:gen_tcp.close(socket)
