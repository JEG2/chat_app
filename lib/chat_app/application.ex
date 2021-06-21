defmodule ChatApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {
        DynamicSupervisor,
        strategy: :one_for_one, name: ChatApp.ConnectionSupervisor
      },
      {ChatApp.ConnectionManager, ui: ChatApp.GUI},
      ChatApp.GUI
    ]

    opts = [strategy: :one_for_one, name: ChatApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
