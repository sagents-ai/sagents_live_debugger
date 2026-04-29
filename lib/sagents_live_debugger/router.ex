defmodule SagentsLiveDebugger.Router do
  @moduledoc """
  Router macro for mounting the debugger in a Phoenix application.

  ## Options

    * `:coordinator` (required) - The coordinator module for managing agent sessions.

    * `:pubsub` (required) - The `Phoenix.PubSub` instance the host application
      uses to broadcast agent and presence events. The debugger subscribes to
      `Sagents.Subscriber.presence_topic/0` and to per-conversation viewer
      presence topics on this PubSub.

    * `:presence_module` - Optional presence module for real-time viewer updates.

    * `:live_socket_path` - Configures the socket path. Must match the
      `socket "/live", Phoenix.LiveView.Socket` in your endpoint.
      Defaults to `"/live"`.

    * `:csp_nonce_assign_key` - An assign key to find the CSP nonce value
      used for assets. Supports either `atom()` (used for both script and
      style nonces) or a map of type
      `%{optional(:script) => atom(), optional(:style) => atom()}`.

  ## Examples

      import SagentsLiveDebugger.Router

      scope "/dev" do
        pipe_through :browser

        sagents_live_debugger "/debug/agents",
          coordinator: MyApp.Coordinator,
          pubsub: MyApp.PubSub,
          presence_module: MyAppWeb.Presence
      end

  With CSP nonces:

      sagents_live_debugger "/debug/agents",
        coordinator: MyApp.Coordinator,
        pubsub: MyApp.PubSub,
        csp_nonce_assign_key: :csp_nonce
  """

  defmacro sagents_live_debugger(path, opts \\ []) do
    scope =
      quote bind_quoted: [path: path, opts: opts] do
        scope path, alias: false, as: false do
          import Phoenix.Router, only: [get: 4]
          import Phoenix.LiveView.Router, only: [live: 3, live: 4, live_session: 3]

          # Extract and validate required configuration
          coordinator = Keyword.fetch!(opts, :coordinator)
          pubsub = Keyword.fetch!(opts, :pubsub)

          # Optional: Presence tracking for real-time viewer updates
          presence_module = Keyword.get(opts, :presence_module)

          # Optional: custom live socket path (defaults to "/live")
          live_socket_path = Keyword.get(opts, :live_socket_path, "/live")

          # Optional: CSP nonce assign key for strict CSP environments
          csp_nonce_assign_key =
            case Keyword.get(opts, :csp_nonce_assign_key) do
              nil -> nil
              key when is_atom(key) -> %{style: key, script: key}
              %{} = keys -> Map.take(keys, [:style, :script])
            end

          live_session :sagents_debugger,
            session:
              {SagentsLiveDebugger.Router, :__session__, [coordinator, pubsub, presence_module]},
            on_mount: [SagentsLiveDebugger.SessionConfig],
            root_layout: {SagentsLiveDebugger.Layouts, :root},
            layout: {SagentsLiveDebugger.Layouts, :app} do
            # Self-contained asset routes (cache-busted via MD5 hash)
            get "/css-:md5", SagentsLiveDebugger.Assets, :css, as: :sagents_debugger_asset
            get "/js-:md5", SagentsLiveDebugger.Assets, :js, as: :sagents_debugger_asset

            live "/", SagentsLiveDebugger.AgentListLive, :home,
              private: %{
                live_socket_path: live_socket_path,
                csp_nonce_assign_key: csp_nonce_assign_key
              }
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

  @doc false
  def __session__(conn, coordinator, pubsub, presence_module) do
    _ = conn

    %{
      "coordinator" => coordinator,
      "pubsub" => pubsub,
      "presence_module" => presence_module
    }
  end
end
