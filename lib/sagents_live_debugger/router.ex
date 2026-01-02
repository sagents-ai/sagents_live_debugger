defmodule SagentsLiveDebugger.Router do
  @moduledoc """
  Router macro for mounting the debugger in a Phoenix application.
  """

  defmacro sagents_live_debugger(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]

        # Extract and validate required configuration
        coordinator = Keyword.fetch!(opts, :coordinator)

        # Optional: Presence tracking for real-time viewer updates
        # If not provided, viewer counts will only update on polling
        presence_module = Keyword.get(opts, :presence_module)

        # Use live_session to pass configuration via session
        live_session :sagents_debugger,
          session: %{
            "coordinator" => coordinator,
            "presence_module" => presence_module
          },
          on_mount: [SagentsLiveDebugger.SessionConfig],
          layout: {SagentsLiveDebugger.Layouts, :app} do
          live "/", SagentsLiveDebugger.AgentListLive, :home
        end
      end
    end
  end
end
