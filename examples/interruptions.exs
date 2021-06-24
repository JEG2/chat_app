task =
  Task.async(fn ->
    Process.sleep(60 * 1_000)
    IO.puts("Brett:  is your talk done yet?")
  end)

_message = IO.gets(":  ")

Task.await(task)
