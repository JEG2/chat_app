{:ok, socket} =
  :gen_tcp.connect(
    'localhost',
    4444,
    [:binary, packet: 1, active: false]
  )

:gen_tcp.recv(socket, 0)
|> IO.inspect()

:gen_tcp.close(socket)
