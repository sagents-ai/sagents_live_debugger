defmodule SagentsLiveDebugger.SessionConfig do
  @moduledoc """
  Provides on_mount callback to inject debugger configuration into LiveView socket.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    coordinator = session["coordinator"]
    presence_module = session["presence_module"]

    # Try to get timezone from connect_params as fallback
    user_timezone = get_timezone_from_params(socket) || "UTC"

    socket =
      socket
      |> assign(:coordinator, coordinator)
      |> assign(:presence_module, presence_module)
      |> assign(:user_timezone, user_timezone)

    {:cont, socket}
  end

  defp get_timezone_from_params(socket) do
    case Phoenix.LiveView.get_connect_params(socket) do
      %{"time_zone" => tz} when is_binary(tz) -> tz
      _ -> nil
    end
  end
end
