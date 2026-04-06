defmodule SagentsLiveDebugger.Router do
  @moduledoc """
  Router macro for mounting the debugger in a Phoenix application.
  """

  defmacro sagents_live_debugger(path, opts \\ []) do
    scope =
      quote bind_quoted: [path: path, opts: opts] do
        scope path, alias: false, as: false do
          import Phoenix.Router, only: [get: 4]
          import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]

          # Extract and validate required configuration
          coordinator = Keyword.fetch!(opts, :coordinator)

          # Optional: Presence tracking for real-time viewer updates
          presence_module = Keyword.get(opts, :presence_module)

          # Optional: custom live socket path (defaults to "/live")
          live_socket_path = Keyword.get(opts, :live_socket_path, "/live")

          live_session :sagents_debugger,
            session: %{
              "coordinator" => coordinator,
              "presence_module" => presence_module
            },
            on_mount: [SagentsLiveDebugger.SessionConfig],
            root_layout: {SagentsLiveDebugger.Layouts, :root},
            layout: {SagentsLiveDebugger.Layouts, :app} do
            # Self-contained JS asset route (cache-busted via MD5 hash)
            get "/js-:md5", SagentsLiveDebugger.Assets, :js, as: :sagents_debugger_asset

            live "/", SagentsLiveDebugger.AgentListLive, :home,
              private: %{live_socket_path: live_socket_path}
          end
        end
      end

    quote do
      unquote(scope)

      unless Module.get_attribute(__MODULE__, :sagents_debugger_prefix) do
        @sagents_debugger_prefix Phoenix.Router.scoped_path(__MODULE__, unquote(path))
                                 |> String.replace_suffix("/", "")
        def __sagents_debugger_prefix__, do: @sagents_debugger_prefix
      end
    end
  end
end
