defmodule SagentsLiveDebugger do
  @moduledoc """
  Real-time debugging and observability for agent systems.

  Similar to Phoenix LiveDashboard, this tool provides visibility into
  agent state, configuration, and execution flow.

  ## Installation

  Add to your router:

      import SagentsLiveDebugger.Router

      scope "/dev" do
        pipe_through :browser

        sagents_live_debugger "/debug/agents",
          coordinator: MyApp.Agents.Coordinator,
          conversation_provider: &MyApp.list_conversations/0
      end

  ## Required Configuration

  - `coordinator`: Module that implements the Coordinator pattern
  - `conversation_provider`: Function that returns list of conversation IDs

  ## Optional Configuration

  - `additional_pages`: List of additional page modules to include
  - `metrics_callback`: Function to provide custom metrics
  """
end
