defmodule SagentsLiveDebugger.Assets do
  @moduledoc false

  # Plug that serves self-contained CSS and JavaScript for the debugger.
  #
  # At compile time, this module reads the debugger CSS file and concatenates
  # the pre-built JS files from phoenix, phoenix_html, and phoenix_live_view
  # dependencies, plus a small LiveSocket initialization script. Assets are
  # served via Plug routes with cache-busting MD5 hashes in the URL.
  #
  # This follows the same pattern as Phoenix.LiveDashboard.Assets.

  import Plug.Conn

  # Read CSS at compile time
  css_path = Path.join(:code.priv_dir(:sagents_live_debugger), "static/debugger.css")
  @external_resource css_path
  @css File.read!(css_path)
  @css_hash Base.encode16(:crypto.hash(:md5, @css), case: :lower)

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
      params: function() {
        var tz = "UTC";
        try {
          tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
        } catch (e) {}
        return {_csrf_token: csrfToken, time_zone: tz};
      }
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

  @time_ago_js """
  (function() {
    if (window.__sagentsTimeAgoInitialized) return;
    window.__sagentsTimeAgoInitialized = true;

    var UPDATE_INTERVAL_MS = 2000;
    var intervalId = null;

    function formatTimeAgo(isoTimestamp) {
      if (!isoTimestamp) return '—';
      var now = new Date();
      var then = new Date(isoTimestamp);
      var diffSeconds = Math.floor((now - then) / 1000);

      if (diffSeconds < 0) return 'Just now';
      if (diffSeconds < 5) return 'Just now';
      if (diffSeconds < 60) return diffSeconds + ' seconds ago';
      if (diffSeconds < 3600) {
        var mins = Math.floor(diffSeconds / 60);
        return mins + (mins === 1 ? ' minute ago' : ' minutes ago');
      }
      if (diffSeconds < 86400) {
        var hours = Math.floor(diffSeconds / 3600);
        return hours + (hours === 1 ? ' hour ago' : ' hours ago');
      }
      var days = Math.floor(diffSeconds / 86400);
      return days + (days === 1 ? ' day ago' : ' days ago');
    }

    function formatDuration(isoTimestamp) {
      if (!isoTimestamp) return '—';
      var now = new Date();
      var start = new Date(isoTimestamp);
      var ms = now - start;

      if (ms < 0) return '0s';

      var seconds = Math.floor(ms / 1000);
      var minutes = Math.floor(seconds / 60);
      var hours = Math.floor(minutes / 60);

      if (hours > 0) return hours + 'h ' + (minutes % 60) + 'm';
      if (minutes > 0) return minutes + 'm ' + (seconds % 60) + 's';
      return seconds + 's';
    }

    function updateTimeElements() {
      document.querySelectorAll('[data-time-ago]').forEach(function(el) {
        var timestamp = el.getAttribute('data-time-ago');
        if (timestamp) el.textContent = formatTimeAgo(timestamp);
      });

      document.querySelectorAll('[data-duration-since]').forEach(function(el) {
        var timestamp = el.getAttribute('data-duration-since');
        if (timestamp) el.textContent = formatDuration(timestamp);
      });
    }

    function startUpdates() {
      updateTimeElements();
      if (!intervalId) {
        intervalId = setInterval(updateTimeElements, UPDATE_INTERVAL_MS);
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', startUpdates);
    } else {
      requestAnimationFrame(function() { setTimeout(startUpdates, 50); });
    }

    window.addEventListener('phx:update', function() { setTimeout(updateTimeElements, 50); });
    window.addEventListener('phx:page-loading-stop', function() { setTimeout(startUpdates, 100); });
  })();
  """

  @js Enum.map_join(phoenix_js_paths, "\n", fn path ->
        path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")
      end) <> "\n" <> @init_js <> "\n" <> @time_ago_js

  @js_hash Base.encode16(:crypto.hash(:md5, @js), case: :lower)

  def init(asset) when asset in [:js, :css], do: asset

  def call(conn, :js) do
    conn
    |> put_resp_header("content-type", "text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @js)
    |> halt()
  end

  def call(conn, :css) do
    conn
    |> put_resp_header("content-type", "text/css")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @css)
    |> halt()
  end

  @doc """
  Returns the current MD5 hash for the given asset bundle.
  """
  def current_hash(:js), do: @js_hash
  def current_hash(:css), do: @css_hash
end
