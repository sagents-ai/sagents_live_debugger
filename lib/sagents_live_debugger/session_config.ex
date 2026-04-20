defmodule SagentsLiveDebugger.SessionConfig do
  @moduledoc """
  Provides on_mount callback to inject debugger configuration into LiveView socket.
  """
  import Phoenix.Component, only: [assign: 3]

  alias SagentsLiveDebugger.Timezone

  def on_mount(:default, _params, session, socket) do
    coordinator = session["coordinator"]
    presence_module = session["presence_module"]

    # Browser timezone arrives via LiveSocket connect_params (see Assets.@init_js).
    # Validate against Tzdata so a bogus/unknown zone can't break downstream
    # DateTime.shift_zone/3 calls when formatting event timestamps.
    user_timezone =
      socket
      |> Phoenix.LiveView.get_connect_params()
      |> case do
        %{"time_zone" => tz} -> tz
        _ -> nil
      end
      |> Timezone.validate_or_utc()

    socket =
      socket
      |> assign(:coordinator, coordinator)
      |> assign(:presence_module, presence_module)
      |> assign(:user_timezone, user_timezone)

    {:cont, socket}
  end
end
