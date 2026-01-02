defmodule SagentsLiveDebugger.Discovery do
  @moduledoc """
  Discovers active agents and their status across the application.

  Works with arbitrary agent IDs and queries the Registry for agent information.
  """

  alias LangChain.Agents.AgentServer

  @doc """
  List all agents with their status.

  Returns a list of agent descriptors:

      [
        %{
          agent_id: "f4eb0573-892a-4592-8f9f-82ec2c517ea1",
          status: :running | :idle | :stopped,
          pid: #PID<...> | nil,
          conversation_id: 123 | nil,  # Only for conversation-based agents
          viewer_count: 0,  # Only available for conversation-based agents
          uptime_ms: 123456 | nil,
          last_activity: ~U[2025-01-15 14:35:10Z] | nil
        },
        ...
      ]
  """
  def list_agents(coordinator) do
    # Get all agent IDs from the framework
    agent_ids = AgentServer.list_running_agents()

    # For each agent, gather status information
    Enum.map(agent_ids, fn agent_id ->
      gather_agent_info(coordinator, agent_id)
    end)
  end

  @doc """
  Gather information about a single agent.
  """
  def gather_agent_info(coordinator, agent_id) do
    # agent_id is a string (UUID or other format)
    # Query AgentServer for status
    pid = AgentServer.get_pid(agent_id)

    # Get metadata from AgentServer if available
    metadata = case AgentServer.get_metadata(agent_id) do
      {:ok, meta} -> meta
      {:error, _} -> %{}
    end

    # Get uptime if running
    uptime_ms = if pid, do: get_uptime(pid), else: nil

    # Try to determine if this is a conversation agent
    # If agent_id looks like a UUID, try to get conversation viewers
    {conversation_id, viewer_count} = get_conversation_info(coordinator, agent_id)

    %{
      agent_id: agent_id,
      conversation_id: conversation_id || Map.get(metadata, :conversation_id),
      status: Map.get(metadata, :status, determine_status(pid)),
      pid: pid,
      viewer_count: viewer_count,
      uptime_ms: uptime_ms,
      last_activity: Map.get(metadata, :last_activity_at)
    }
  end

  # Try to get conversation info - if it succeeds, this is a conversation agent
  defp get_conversation_info(coordinator, agent_id) when is_binary(agent_id) do
    # Check if this looks like a UUID (contains hyphens, right length)
    if String.contains?(agent_id, "-") and String.length(agent_id) == 36 do
      # Try to query as a conversation_id
      try do
        viewers = coordinator.list_conversation_viewers(agent_id)
        {agent_id, map_size(viewers)}
      rescue
        _ -> {nil, 0}
      end
    else
      {nil, 0}
    end
  end

  defp get_conversation_info(_coordinator, _agent_id), do: {nil, 0}

  # Determine agent status as fallback when metadata isn't available
  defp determine_status(nil), do: :stopped

  defp determine_status(pid) when is_pid(pid) do
    # Default to :idle if process is alive
    # (The actual status will come from metadata if available)
    if Process.alive?(pid), do: :idle, else: :stopped
  end

  # Get process uptime in milliseconds
  defp get_uptime(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, _name} ->
        # Get process start time from process info
        # This is a simplified version - production code would track start time
        nil

      _ ->
        nil
    end
  end
end
