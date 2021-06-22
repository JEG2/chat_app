{:ok, listening_socket} =
  :gen_tcp.listen(
    4444,
    [:binary, packet: 1]
  )

{:ok, socket} = :gen_tcp.accept(listening_socket)

:ok = :gen_tcp.send(socket, "Length encoded!")

:gen_tcp.close(socket)
:gen_tcp.close(listening_socket)
