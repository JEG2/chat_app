{:ok, listening_socket} =
  :gen_tcp.listen(
    4444,
    [:binary, packet: 1]
  )

{:ok, socket} = :gen_tcp.accept(listening_socket)

# No error!
:ok = :gen_tcp.send(socket, String.duplicate("X", 300))

:gen_tcp.close(socket)
:gen_tcp.close(listening_socket)
