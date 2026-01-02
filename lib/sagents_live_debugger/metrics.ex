defmodule SagentsLiveDebugger.Metrics do
  @moduledoc """
  Calculates system-wide metrics for active agents in the debugger.
  """

  @doc """
  Calculate system metrics from active agent list.

  Returns:

      %{
        total_agents: 10,
        running: 3,
        idle: 7,
        total_viewers: 12
      }
  """
  def calculate_metrics(agents) do
    total = length(agents)
    running = Enum.count(agents, &(&1.status == :running))
    idle = Enum.count(agents, &(&1.status == :idle))
    total_viewers = Enum.sum(Enum.map(agents, & &1.viewer_count))

    %{
      total_agents: total,
      running: running,
      idle: idle,
      total_viewers: total_viewers
    }
  end
end
