defmodule SagentsLiveDebugger.Layouts do
  use Phoenix.Component

  @compile {:no_warn_undefined, Phoenix.VerifiedRoutes}

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" phx-socket={live_socket_path(@conn)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Agent Debugger</title>

        <link rel="stylesheet" nonce={csp_nonce(@conn, :style)} href={asset_path(@conn, :css)} />
        <script nonce={csp_nonce(@conn, :script)} src={asset_path(@conn, :js)} defer>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    {@inner_content}
    """
  end

  defp live_socket_path(conn) do
    [Enum.map(conn.script_name, &["/" | &1]) | conn.private.live_socket_path]
  end

  defp asset_path(conn, asset) when asset in [:js, :css] do
    hash = SagentsLiveDebugger.Assets.current_hash(asset)
    prefix = conn.private.phoenix_router.__sagents_debugger_prefix__()

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      "#{prefix}/#{asset}-#{hash}"
    )
  end

  defp csp_nonce(conn, type) do
    case conn.private[:csp_nonce_assign_key] do
      nil -> nil
      key when is_atom(key) -> conn.assigns[key]
      %{} = map -> conn.assigns[map[type]]
    end
  end
end
