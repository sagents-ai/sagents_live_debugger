defmodule SagentsLiveDebugger.SessionConfig do
  @moduledoc """
  Provides on_mount callback to inject debugger configuration into LiveView socket.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    coordinator = session["coordinator"]
    presence_module = session["presence_module"]

    socket =
      socket
      |> assign(:coordinator, coordinator)
      |> assign(:presence_module, presence_module)

    {:cont, socket}
  end
end
