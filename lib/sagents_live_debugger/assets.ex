defmodule SagentsLiveDebugger.Assets do
  @moduledoc false

  # Plug that serves self-contained LiveView JavaScript for the debugger.
  #
  # At compile time, this module reads and concatenates the pre-built JS files
  # from phoenix, phoenix_html, and phoenix_live_view dependencies, plus a
  # small LiveSocket initialization script. The result is served via a Plug
  # route with cache-busting MD5 hash in the URL.
  #
  # This follows the same pattern as Phoenix.LiveDashboard.Assets.

  import Plug.Conn

  # Read Phoenix dependency JS files at compile time
  phoenix_js_paths =
    for app <- [:phoenix, :phoenix_html, :phoenix_live_view] do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  # Minimal LiveSocket initialization script.
  # After the concatenated Phoenix JS files load, `Phoenix` and `LiveView`
  # are available as globals. This connects the LiveSocket so the page
  # becomes interactive.
  @init_js """
  (function() {
    var socketPath = document.querySelector("html").getAttribute("phx-socket") || "/live";
    var csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
    var liveSocket = new LiveView.LiveSocket(socketPath, Phoenix.Socket, {
      params: function() { return {_csrf_token: csrfToken}; }
    });

    // Attempt WebSocket first, fall back to long polling on connection error
    var rawSocket = liveSocket.socket;
    var originalOnConnError = rawSocket.onConnError;
    var firstConnect = true;

    rawSocket.onOpen(function() { firstConnect = false; });
    rawSocket.onConnError = function() {
      if (firstConnect) {
        firstConnect = false;
        rawSocket.disconnect(null, 3000);
        rawSocket.transport = Phoenix.LongPoll;
        rawSocket.connect();
      } else {
        originalOnConnError.apply(rawSocket, arguments);
      }
    };

    window.addEventListener("phx:page-loading-start", function() {});
    window.addEventListener("phx:page-loading-stop", function() {});

    liveSocket.connect();
    window.liveSocket = liveSocket;
  })();
  """

  @js Enum.map_join(phoenix_js_paths, "\n", fn path ->
        path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")
      end) <> "\n" <> @init_js

  @js_hash Base.encode16(:crypto.hash(:md5, @js), case: :lower)

  def init(asset) when asset in [:js], do: asset

  def call(conn, :js) do
    conn
    |> put_resp_header("content-type", "text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @js)
    |> halt()
  end

  @doc """
  Returns the current MD5 hash for the JS bundle.
  """
  def current_hash(:js), do: @js_hash
end
