defmodule SagentsLiveDebugger.AgentListLive do
  use Phoenix.LiveView
  require Logger

  import SagentsLiveDebugger.CoreComponents
  import SagentsLiveDebugger.Live.Components.SubagentsTab
  import SagentsLiveDebugger.Live.Components.MessageComponents
  import SagentsLiveDebugger.Live.Components.FilterConfig
  alias SagentsLiveDebugger.{Metrics, FilterForm}

  # Presence topics for debugger discovery
  @debug_viewers_topic "debug_viewers"
  @agent_presence_topic "agent_server:presence"

  # Event-Driven Architecture Notes:
  #
  # This LiveView is entirely event-driven (NO POLLING):
  #
  # 1. Agent List View:
  #    - Built from presence metadata (agent_server:presence topic)
  #    - Real-time updates via presence_diff events when agents join/leave
  #    - Status and activity updates come through presence metadata changes
  #    - Viewer counts via conversation presence topics
  #
  # 2. Agent Detail View:
  #    - Subscribes to both regular and debug PubSub topics
  #    - Real-time updates via handle_info event handlers:
  #      - :todos_updated -> Updates TODOs tab
  #      - :llm_message -> Updates Messages tab
  #      - :status_changed -> Updates status in metadata
  #      - :middleware_action -> Adds to Events stream
  #      - All events -> Added to Events tab stream
  #
  # 3. Auto-Follow First:
  #    - Automatically follows the first matching agent that appears
  #    - Configurable via auto_follow_first assign
  #    - Filter matching for production use (conversation_id, custom scope fields, etc.)
  #
  # Subscription Management:
  #    - Subscribe when entering detail view
  #    - Unsubscribe when leaving detail view or switching agents
  #    - Tracked via :subscribed_agent_id assign

  def mount(_params, _session, socket) do
    # Configuration comes from on_mount callback via socket assigns
    coordinator = socket.assigns.coordinator
    presence_module = socket.assigns.presence_module
    # Ensure user_timezone is set (comes from SessionConfig, default to UTC if missing)
    user_timezone = Map.get(socket.assigns, :user_timezone, "UTC")

    # NO polling - agent list is entirely presence-driven

    # Track debugger presence and subscribe to agent presence topic (for discovery)
    if connected?(socket) && presence_module do
      pubsub_name = coordinator.pubsub_name()
      track_debugger_presence(presence_module, socket.id)
      subscribe_to_agent_presence(pubsub_name)
    end

    # Build initial agent list from presence (not Discovery polling)
    agents = build_agents_from_presence(presence_module, coordinator)
    metrics = Metrics.calculate_metrics(agents)

    # Subscribe to presence changes for conversation agents (for viewer counts)
    subscribed_topics =
      if presence_module do
        pubsub_name = coordinator.pubsub_name()
        subscribe_to_conversation_agents(pubsub_name, agents)
      else
        MapSet.new()
      end

    # Initialize filter form with default values
    filter_changeset =
      FilterForm.new()
      |> FilterForm.changeset(%{})

    # Auto-follow configuration - can be customized in consuming app's config
    # Defaults are dev-friendly: auto-follow enabled
    auto_follow_default = Application.get_env(:sagents_live_debugger, :auto_follow_default, true)

    socket =
      socket
      |> assign(:user_timezone, user_timezone)
      |> assign(:agents, agents)
      |> assign(:metrics, metrics)
      |> assign(:filter_changeset, filter_changeset)
      |> assign(:form, to_form(filter_changeset))
      |> assign(:subscribed_topics, subscribed_topics)
      |> assign(:view_mode, :list)
      |> assign(:selected_agent_id, nil)
      |> assign(:agent_detail, nil)
      |> assign(:agent_metadata, nil)
      |> assign(:agent_state, nil)
      |> assign(:current_tab, :overview)
      |> assign(:event_stream, [])
      |> assign(:subscribed_agent_id, nil)
      # Auto-follow state
      |> assign(:auto_follow_first, auto_follow_default)
      |> assign(:auto_follow_filters, :none)
      |> assign(:followed_agent_id, nil)
      # Sub-agents state (for Phase 4)
      |> assign(:subagents, %{})
      |> assign(:expanded_subagent, nil)
      |> assign(:subagent_tab, "config")

    # Auto-follow first existing agent if auto-follow is enabled
    socket = maybe_auto_follow_existing_agent(socket, agents, auto_follow_default)

    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    # Extract base path (without query string) for navigation
    base_path = URI.parse(uri).path || ""

    socket = assign(socket, :base_path, base_path)

    case Map.get(params, "agent_id") do
      nil ->
        # List view - unsubscribe from any previous agent
        socket = maybe_unsubscribe_from_previous_agent(socket)

        # Clear detail-related assigns
        socket =
          socket
          |> assign(:view_mode, :list)
          |> assign(:selected_agent_id, nil)
          |> assign(:agent_detail, nil)
          |> assign(:agent_metadata, nil)
          |> assign(:agent_state, nil)
          |> assign(:event_stream, [])

        {:noreply, socket}

      agent_id ->
        # Detail view

        # Capture the previous selected agent BEFORE any updates to determine if we should clear events
        # Use selected_agent_id (not subscribed_agent_id) because it's always set when viewing an agent,
        # even if subscription fails
        previous_selected_agent_id = socket.assigns[:selected_agent_id]

        # Unsubscribe from previous agent if different
        socket =
          if socket.assigns[:subscribed_agent_id] != agent_id do
            maybe_unsubscribe_from_previous_agent(socket)
          else
            socket
          end

        # Subscribe to new agent events
        socket =
          if connected?(socket) && socket.assigns[:subscribed_agent_id] != agent_id do
            subscribe_to_agent_events(socket, agent_id)
          else
            socket
          end

        # Get tab from params
        tab = Map.get(params, "tab", "overview")

        current_tab =
          case tab do
            "messages" -> :messages
            "middleware" -> :middleware
            "tools" -> :tools
            "todos" -> :todos
            "events" -> :events
            "subagents" -> :subagents
            _ -> :overview
          end

        # Touch the agent to reset inactivity timer
        if connected?(socket) do
          LangChain.Agents.AgentServer.touch(agent_id)
        end

        # Load agent detail
        # Only clear event_stream when switching to a different agent
        socket =
          socket
          |> assign(:view_mode, :detail)
          |> assign(:selected_agent_id, agent_id)
          |> assign(:current_tab, current_tab)
          |> maybe_clear_event_stream(previous_selected_agent_id, agent_id)
          |> load_agent_detail(agent_id)

        {:noreply, socket}
    end
  end

  defp maybe_unsubscribe_from_previous_agent(socket) do
    if prev_agent_id = socket.assigns[:subscribed_agent_id] do
      unsubscribe_from_agent_events(prev_agent_id, socket.assigns.coordinator)
      assign(socket, :subscribed_agent_id, nil)
    else
      socket
    end
  end

  defp maybe_clear_event_stream(socket, previous_agent_id, current_agent_id) do
    # Only clear event_stream when switching to a different agent
    # Keep events when:
    # - Switching tabs or reloading the same agent detail view
    # - Entering detail view for an agent we've been following (preserve buffered events)
    followed_id = socket.assigns[:followed_agent_id]

    cond do
      # Same agent - keep events (tab switch)
      previous_agent_id == current_agent_id ->
        socket

      # Entering detail view for followed agent - keep buffered events
      current_agent_id == followed_id ->
        socket

      # Switching to a different agent - clear events
      true ->
        assign(socket, :event_stream, [])
    end
  end

  defp subscribe_to_agent_events(socket, agent_id) do
    # Use AgentServer subscription functions
    # Handle case where agent doesn't exist (has shut down)
    with :ok <- LangChain.Agents.AgentServer.subscribe(agent_id),
         :ok <- LangChain.Agents.AgentServer.subscribe_debug(agent_id) do
      assign(socket, :subscribed_agent_id, agent_id)
    else
      {:error, :process_not_found} ->
        # Agent doesn't exist, don't subscribe
        socket

      {:error, _reason} ->
        # Other error (e.g., no pubsub configured), don't subscribe
        socket
    end
  end

  defp unsubscribe_from_agent_events(agent_id, _coordinator) do
    # Unsubscribe returns :ok even if the agent process doesn't exist
    :ok = LangChain.Agents.AgentServer.unsubscribe(agent_id)
    :ok = LangChain.Agents.AgentServer.unsubscribe_debug(agent_id)
  end

  # Handle agent status change events (for detail view)
  def handle_info({:agent, {:status_changed, new_status, _data}}, socket) do
    if socket.assigns.view_mode == :detail && socket.assigns.agent_metadata do
      updated_metadata = Map.put(socket.assigns.agent_metadata, :status, new_status)
      {:noreply, assign(socket, :agent_metadata, updated_metadata)}
    else
      {:noreply, socket}
    end
  end

  # Handle presence_diff events for agent presence topic (agent discovery)
  # This is the primary mechanism for updating the agent list - no polling needed
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          topic: @agent_presence_topic,
          payload: payload
        },
        socket
      ) do
    joins = Map.get(payload, :joins, %{})
    leaves = Map.get(payload, :leaves, %{})

    if map_size(joins) > 0 || map_size(leaves) > 0 do
      # Categorize presence changes into joined/left/updated
      # Updates (metadata changes) don't affect follow state - only true joins/leaves do
      %{joined: joined, left: left, updated: _updated} =
        categorize_presence_changes(joins, leaves)

      # Rebuild agent list from current presence state (includes all changes)
      agents =
        build_agents_from_presence(socket.assigns.presence_module, socket.assigns.coordinator)

      metrics = Metrics.calculate_metrics(agents)

      # Subscribe to any new conversation agents (for viewer counts)
      subscribed_topics =
        if socket.assigns.presence_module do
          pubsub_name = socket.assigns.coordinator.pubsub_name()

          subscribe_to_new_conversation_agents(
            pubsub_name,
            agents,
            socket.assigns.subscribed_topics
          )
        else
          socket.assigns.subscribed_topics
        end

      socket =
        socket
        |> assign(:agents, agents)
        |> assign(:metrics, metrics)
        |> assign(:subscribed_topics, subscribed_topics)
        |> handle_agents_joined(joined)
        |> handle_agents_left(left)

      # Note: updates don't need handling - agent list is rebuilt, follow state unchanged

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Handle presence_diff events for real-time viewer count updates (conversation topics)
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic, payload: _payload},
        socket
      ) do
    # Extract conversation_id from topic "conversation:#{conversation_id}"
    conversation_id = String.replace_prefix(topic, "conversation:", "")

    # Get updated viewer count for this conversation
    viewer_count = get_viewer_count(socket.assigns.coordinator, conversation_id)

    # Update the agent in our list
    agents =
      Enum.map(socket.assigns.agents, fn agent ->
        if agent.conversation_id == conversation_id do
          %{agent | viewer_count: viewer_count}
        else
          agent
        end
      end)

    # Recalculate metrics with updated viewer counts
    metrics = Metrics.calculate_metrics(agents)

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:metrics, metrics)

    {:noreply, socket}
  end

  # Handle agent shutdown events
  def handle_info({:agent, {:agent_shutdown, _shutdown_data}}, socket) do
    # The periodic refresh will remove the agent from the list
    # No need to manually update the agent list here
    {:noreply, socket}
  end

  # Handle todos_updated events
  def handle_info({:agent, {:todos_updated, todos}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        # Update agent state if in detail view with state loaded
        socket =
          if socket.assigns.view_mode == :detail && socket.assigns.agent_state do
            updated_state = %{socket.assigns.agent_state | todos: todos}
            assign(socket, :agent_state, updated_state)
          else
            socket
          end

        add_event_to_stream(socket, {:todos_updated, todos}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_message events
  def handle_info({:agent, {:llm_message, message}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        # Update agent state if in detail view with state loaded
        socket =
          if socket.assigns.view_mode == :detail && socket.assigns.agent_state do
            updated_messages = socket.assigns.agent_state.messages ++ [message]
            updated_state = %{socket.assigns.agent_state | messages: updated_messages}
            assign(socket, :agent_state, updated_state)
          else
            socket
          end

        add_event_to_stream(socket, {:llm_message, message}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_deltas events (streaming tokens)
  def handle_info({:agent, {:llm_deltas, deltas}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        add_event_to_stream(socket, {:llm_deltas, deltas}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_token_usage events
  def handle_info({:agent, {:llm_token_usage, usage}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        add_event_to_stream(socket, {:llm_token_usage, usage}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle conversation_title_generated events
  def handle_info({:agent, {:conversation_title_generated, title, agent_id}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        add_event_to_stream(socket, {:conversation_title_generated, title, agent_id}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handler for sub-agent debug events
  # Sub-agent events are wrapped as {:agent, {:debug, {:subagent, sub_agent_id, event}}}
  def handle_info({:agent, {:debug, {:subagent, sub_agent_id, event}}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        socket
        |> handle_subagent_event(sub_agent_id, event)
        |> add_event_to_stream({:subagent, sub_agent_id, event}, :debug)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handler for wrapped debug events
  # Debug events are wrapped with {:agent, {:debug, event}} tuple in AgentServer
  def handle_info({:agent, {:debug, event}}, socket) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        add_event_to_stream(socket, event, :debug)
      else
        socket
      end

    {:noreply, socket}
  end

  # Catch-all handler for any other agent events not specifically handled above
  # This should be the LAST handle_info clause for agent events
  def handle_info({:agent, event}, socket) when is_tuple(event) do
    socket =
      if socket.assigns.followed_agent_id != nil do
        # Assume standard event unless it matches debug patterns
        category =
          if tuple_size(event) >= 1 && elem(event, 0) == :agent_state_update do
            :debug
          else
            :std
          end

        add_event_to_stream(socket, event, category)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("update_filters", %{"filter_form" => filter_params}, socket) do
    # Create changeset from new form with incoming params
    changeset =
      FilterForm.new()
      |> FilterForm.changeset(filter_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:filter_changeset, changeset)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    # Navigate to different tab in detail view
    agent_id = socket.assigns.selected_agent_id
    base_path = socket.assigns[:base_path] || ""

    # Touch the agent to reset inactivity timer
    LangChain.Agents.AgentServer.touch(agent_id)

    {:noreply, push_patch(socket, to: "#{base_path}?agent_id=#{agent_id}&tab=#{tab}")}
  end

  def handle_event("back_to_list", _params, socket) do
    # Navigate back to list view (remove query params)
    base_path = socket.assigns[:base_path] || ""
    {:noreply, push_patch(socket, to: base_path)}
  end

  # Handle timezone from phx-click with phx-value-timezone
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    case validate_timezone(timezone) do
      {:ok, validated_tz} ->
        {:noreply, assign(socket, :user_timezone, validated_tz)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("set_timezone", _params, socket) do
    {:noreply, socket}
  end

  # Toggle auto-follow first agent
  def handle_event("toggle_auto_follow", _params, socket) do
    {:noreply, assign(socket, :auto_follow_first, !socket.assigns.auto_follow_first)}
  end

  # Toggle subagent expansion in the Sub-Agents tab
  def handle_event("toggle_subagent", %{"id" => id}, socket) do
    new_expanded = if socket.assigns.expanded_subagent == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_subagent, new_expanded)}
  end

  # Select tab within expanded subagent (config, messages, tools)
  def handle_event("select_subagent_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :subagent_tab, tab)}
  end

  # Manually follow an agent from the list
  def handle_event("follow_agent", %{"id" => agent_id}, socket) do
    {:noreply, follow_agent(socket, agent_id)}
  end

  # Unfollow the currently followed agent
  def handle_event("unfollow_agent", _params, socket) do
    {:noreply, maybe_unfollow_agent(socket)}
  end

  # Apply auto-follow filters from the filter form
  def handle_event("apply_debug_filters", %{"filters" => filter_params}, socket) do
    filters = SagentsLiveDebugger.Live.Components.FilterConfig.parse_filters(filter_params)
    {:noreply, assign(socket, :auto_follow_filters, filters)}
  end

  # Preview filters as user types (same as apply for now)
  def handle_event("preview_debug_filters", %{"filters" => filter_params}, socket) do
    filters = SagentsLiveDebugger.Live.Components.FilterConfig.parse_filters(filter_params)
    {:noreply, assign(socket, :auto_follow_filters, filters)}
  end

  # Clear all auto-follow filters
  def handle_event("clear_debug_filters", _params, socket) do
    {:noreply, assign(socket, :auto_follow_filters, :none)}
  end

  ## Presence-Based Agent List Functions
  #
  # These functions build the agent list entirely from presence metadata,
  # eliminating the need for polling. The agent list updates in real-time
  # via presence_diff events.

  # Build agent list directly from presence metadata
  defp build_agents_from_presence(nil, _coordinator), do: []

  defp build_agents_from_presence(presence_module, coordinator) do
    presence_module
    |> LangChain.Presence.list(@agent_presence_topic)
    |> Enum.map(fn {agent_id, %{metas: [meta | _]}} ->
      %{
        agent_id: agent_id,
        status: Map.get(meta, :status, :unknown),
        conversation_id: Map.get(meta, :conversation_id),
        last_activity: Map.get(meta, :last_activity_at),
        started_at: Map.get(meta, :started_at),
        viewer_count:
          get_viewer_count_from_presence(coordinator, Map.get(meta, :conversation_id)),
        node: Map.get(meta, :node)
      }
    end)
    |> Enum.sort_by(& &1.last_activity, {:desc, DateTime})
  end

  defp get_viewer_count_from_presence(_coordinator, nil), do: 0

  defp get_viewer_count_from_presence(coordinator, conversation_id) do
    try do
      viewers = coordinator.list_conversation_viewers(conversation_id)
      map_size(viewers)
    rescue
      _ -> 0
    end
  end

  ## Auto-Follow Functions
  #
  # Auto-follow automatically subscribes to the first matching agent that appears.
  # This eliminates the need for event buffering - the debugger captures all events
  # from the moment of auto-follow.
  #
  # Filters only affect which agent gets auto-followed - all agents remain visible
  # in the list regardless of filter settings.

  # Auto-follow first matching agent on mount (if any exist and auto-follow is enabled)
  defp maybe_auto_follow_existing_agent(socket, agents, auto_follow_enabled) do
    if auto_follow_enabled && connected?(socket) && length(agents) > 0 do
      filters = socket.assigns[:auto_follow_filters] || :none

      case find_first_matching_agent(agents, filters) do
        nil -> socket
        agent -> follow_agent(socket, agent.agent_id)
      end
    else
      socket
    end
  end

  # Find first agent that matches the auto-follow filters
  defp find_first_matching_agent(agents, :none), do: List.first(agents)
  defp find_first_matching_agent(agents, :all), do: List.first(agents)

  defp find_first_matching_agent(agents, filters) when is_list(filters) do
    Enum.find(agents, fn agent -> agent_matches_filters?(agent, filters) end)
  end

  # Check if an agent matches all the specified filters
  defp agent_matches_filters?(agent, filters) do
    Enum.all?(filters, fn filter -> agent_matches_filter?(agent, filter) end)
  end

  defp agent_matches_filter?(agent, {:conversation_id, value}) do
    to_string(agent.conversation_id) == to_string(value)
  end

  defp agent_matches_filter?(agent, {:agent_id, value}) do
    to_string(agent.agent_id) == to_string(value)
  end

  defp agent_matches_filter?(_agent, {_key, _value}) do
    # For custom scope fields, we'd need to check presence metadata
    # For now, only conversation_id and agent_id are directly available
    # Custom fields would require fetching full presence metadata
    false
  end

  ## Presence Change Categorization
  #
  # Phoenix.Presence diffs contain `joins` and `leaves` maps, but not all changes
  # are true joins/leaves. We need to distinguish:
  #
  # 1. JOINED: Agent is new (appears in joins, no phx_ref_prev, not in leaves)
  # 2. LEFT: Agent departed (appears in leaves, not in joins)
  # 3. UPDATED: Agent's metadata changed (presence update, not a true join/leave)
  #
  # Updates are detected by:
  # - phx_ref_prev in join metadata (Phoenix.Presence.update/3 links to old entry)
  # - Agent appears in both joins AND leaves (LangChain.Presence.update untrack+track)

  # Categorizes a presence_diff payload into joined, left, and updated agents.
  # Returns `%{joined: %{}, left: %{}, updated: %{}}` where each map contains
  # agent_id => presence_data for agents in that category.
  defp categorize_presence_changes(joins, leaves) do
    # Get all agent IDs mentioned in the diff
    all_agent_ids =
      MapSet.new(Map.keys(joins))
      |> MapSet.union(MapSet.new(Map.keys(leaves)))

    Enum.reduce(all_agent_ids, %{joined: %{}, left: %{}, updated: %{}}, fn agent_id, acc ->
      in_joins = Map.get(joins, agent_id)
      in_leaves = Map.get(leaves, agent_id)

      cond do
        # Agent in joins with phx_ref_prev -> UPDATE (Phoenix.Presence.update pattern)
        # The phx_ref_prev links this entry to the previous one it's replacing
        in_joins && has_phx_ref_prev?(in_joins) ->
          %{acc | updated: Map.put(acc.updated, agent_id, in_joins)}

        # Agent in both joins AND leaves (without phx_ref_prev) -> UPDATE
        # This is the LangChain.Presence.update pattern (untrack + track)
        in_joins && in_leaves ->
          %{acc | updated: Map.put(acc.updated, agent_id, in_joins)}

        # Agent only in joins (no phx_ref_prev, not in leaves) -> TRUE JOIN
        in_joins ->
          %{acc | joined: Map.put(acc.joined, agent_id, in_joins)}

        # Agent only in leaves (not in joins) -> TRUE LEAVE
        in_leaves ->
          %{acc | left: Map.put(acc.left, agent_id, in_leaves)}
      end
    end)
  end

  # Check if a presence entry has phx_ref_prev in any of its metas
  # phx_ref_prev is added by Phoenix.Presence when an entry is updated (not new)
  defp has_phx_ref_prev?(%{metas: metas}) do
    Enum.any?(metas, fn meta -> Map.has_key?(meta, :phx_ref_prev) end)
  end

  defp has_phx_ref_prev?(_), do: false

  # Handle agents that truly joined (not updates)
  # This is where auto-follow logic lives - filters control which agent gets followed
  defp handle_agents_joined(socket, joined) when map_size(joined) == 0, do: socket

  defp handle_agents_joined(socket, joined) do
    if socket.assigns.auto_follow_first and is_nil(socket.assigns.followed_agent_id) do
      filters = socket.assigns[:auto_follow_filters] || :none

      # Convert joined map to list of agent-like maps for filter matching
      joined_agents =
        Enum.map(joined, fn {agent_id, %{metas: [meta | _]}} ->
          %{
            agent_id: agent_id,
            conversation_id: Map.get(meta, :conversation_id)
          }
        end)

      case find_first_matching_agent(joined_agents, filters) do
        nil -> socket
        agent -> follow_agent(socket, agent.agent_id)
      end
    else
      socket
    end
  end

  # Handle agents that truly left (not updates)
  # Clear follow state if the followed agent departed
  defp handle_agents_left(socket, left) do
    followed = socket.assigns.followed_agent_id

    if followed && Map.has_key?(left, followed) do
      socket
      |> assign(:followed_agent_id, nil)
      |> assign(:event_stream, [])
      |> assign(:subagents, %{})
    else
      socket
    end
  end

  ## Follow/Unfollow Agent Functions

  defp follow_agent(socket, agent_id) do
    # Don't re-follow if already following the same agent (preserves event_stream)
    if socket.assigns.followed_agent_id == agent_id do
      socket
    else
      do_follow_agent(socket, agent_id)
    end
  end

  defp do_follow_agent(socket, agent_id) do
    # Unfollow previous if any
    socket = maybe_unfollow_agent(socket)

    # Subscribe to agent events
    socket =
      if connected?(socket) do
        with :ok <- LangChain.Agents.AgentServer.subscribe(agent_id),
             :ok <- LangChain.Agents.AgentServer.subscribe_debug(agent_id) do
          socket
        else
          _error -> socket
        end
      else
        socket
      end

    # Fetch current agent state for initial display
    initial_state =
      try do
        LangChain.Agents.AgentServer.get_state(agent_id)
      catch
        :exit, _ -> nil
      end

    socket
    |> assign(:followed_agent_id, agent_id)
    |> assign(:event_stream, [])
    |> assign(:subagents, %{})
    |> maybe_set_initial_state(initial_state)
  end

  defp maybe_unfollow_agent(socket) do
    case socket.assigns.followed_agent_id do
      nil ->
        socket

      agent_id ->
        # Unsubscribe from agent events
        LangChain.Agents.AgentServer.unsubscribe(agent_id)
        LangChain.Agents.AgentServer.unsubscribe_debug(agent_id)

        socket
        |> assign(:followed_agent_id, nil)
        |> assign(:event_stream, [])
        |> assign(:subagents, %{})
    end
  end

  defp maybe_set_initial_state(socket, nil), do: socket

  defp maybe_set_initial_state(socket, _state) do
    # Optionally populate initial state from followed agent
    # This allows showing current todos and messages immediately
    # For now, just return socket - events will populate state in real-time
    socket
  end

  # Subscribe to presence topics for all conversation agents
  defp subscribe_to_conversation_agents(pubsub_name, agents) do
    conversation_agents = Enum.filter(agents, & &1.conversation_id)

    Enum.reduce(conversation_agents, MapSet.new(), fn agent, acc ->
      topic = presence_topic(agent.conversation_id)
      subscribe_to_presence(pubsub_name, topic)
      MapSet.put(acc, topic)
    end)
  end

  # Subscribe to presence topics for new conversation agents only
  defp subscribe_to_new_conversation_agents(pubsub_name, agents, subscribed_topics) do
    conversation_agents = Enum.filter(agents, & &1.conversation_id)

    Enum.reduce(conversation_agents, subscribed_topics, fn agent, acc ->
      topic = presence_topic(agent.conversation_id)

      if MapSet.member?(acc, topic) do
        acc
      else
        subscribe_to_presence(pubsub_name, topic)
        MapSet.put(acc, topic)
      end
    end)
  end

  # Subscribe to a presence topic
  defp subscribe_to_presence(pubsub_name, topic) do
    # Use LangChain.PubSub for automatic deduplication
    LangChain.PubSub.subscribe(Phoenix.PubSub, pubsub_name, topic)
  end

  # Load agent detail data
  defp load_agent_detail(socket, agent_id) do
    metadata =
      case LangChain.Agents.AgentServer.get_metadata(agent_id) do
        {:ok, meta} -> meta
        {:error, _} -> nil
      end

    # get_state returns State.t() directly, not a tuple
    state =
      try do
        LangChain.Agents.AgentServer.get_state(agent_id)
      catch
        :exit, _ -> nil
      end

    agent =
      case LangChain.Agents.AgentServer.get_agent(agent_id) do
        {:ok, agent} -> agent
        {:error, _} -> nil
      end

    socket
    |> assign(:agent_detail, agent)
    |> assign(:agent_metadata, metadata)
    |> assign(:agent_state, state)
  end

  # Get current viewer count for a conversation
  defp get_viewer_count(coordinator, conversation_id) do
    viewers = coordinator.list_conversation_viewers(conversation_id)
    map_size(viewers)
  end

  # Build presence topic name for a conversation
  defp presence_topic(conversation_id) do
    "conversation:#{conversation_id}"
  end

  # Track debugger presence for agent discovery
  # Agents can discover debuggers via this topic
  defp track_debugger_presence(presence_module, debugger_id) do
    metadata = %{
      interested_in: :all,
      connected_at: DateTime.utc_now(),
      node: node()
    }

    case LangChain.Presence.track(
           presence_module,
           @debug_viewers_topic,
           debugger_id,
           self(),
           metadata
         ) do
      {:ok, _ref} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to track debugger presence: #{inspect(reason)}")
        :error
    end
  end

  # Subscribe to agent presence topic for real-time agent discovery
  defp subscribe_to_agent_presence(pubsub_name) do
    LangChain.PubSub.subscribe(Phoenix.PubSub, pubsub_name, @agent_presence_topic)
  end

  def render(assigns) do
    ~H"""
    <!-- Hidden button for timezone submission -->
    <button id="sagents-tz-btn" phx-click="set_timezone" style="display: none;"></button>

    <!-- Timezone detection script - phx-update="ignore" prevents re-execution -->
    <div phx-update="ignore" id="sagents-tz-script-container">
      <script>
        (function() {
          // Listen for every phx:page-loading-stop (initial load AND reconnects)
          window.addEventListener('phx:page-loading-stop', function() {
            // Use requestAnimationFrame + setTimeout for reliable timing
            // RAF ensures we're past the current render, setTimeout adds buffer for LiveView bindings
            requestAnimationFrame(function() {
              setTimeout(function() {
                const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
                const btn = document.getElementById('sagents-tz-btn');
                if (btn) {
                  btn.setAttribute('phx-value-timezone', tz);
                  btn.click();
                }
              }, 100);
            });
          });
        })();
      </script>
    </div>

    <!-- Self-contained TimeAgo script - updates relative times client-side -->
    <div phx-update="ignore" id="sagents-time-ago-script-container">
      <script>
        (function() {
          // Prevent multiple initializations
          if (window.__sagentsTimeAgoInitialized) return;
          window.__sagentsTimeAgoInitialized = true;

          var UPDATE_INTERVAL_MS = 2000; // Update every 2 seconds
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
            // Update "time ago" elements (Last Activity)
            document.querySelectorAll('[data-time-ago]').forEach(function(el) {
              var timestamp = el.getAttribute('data-time-ago');
              if (timestamp) {
                el.textContent = formatTimeAgo(timestamp);
              }
            });

            // Update duration elements (Uptime)
            document.querySelectorAll('[data-duration-since]').forEach(function(el) {
              var timestamp = el.getAttribute('data-duration-since');
              if (timestamp) {
                el.textContent = formatDuration(timestamp);
              }
            });
          }

          function startUpdates() {
            // Run initial update
            updateTimeElements();
            // Start interval if not already running
            if (!intervalId) {
              intervalId = setInterval(updateTimeElements, UPDATE_INTERVAL_MS);
            }
          }

          // Wait for DOM to be ready before first update
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', startUpdates);
          } else {
            // DOM already loaded, use requestAnimationFrame to ensure render is complete
            requestAnimationFrame(function() {
              setTimeout(startUpdates, 50);
            });
          }

          // Re-update after LiveView patches the DOM
          window.addEventListener('phx:update', function() {
            setTimeout(updateTimeElements, 50);
          });

          // Also listen for page load events (navigation, reconnects)
          window.addEventListener('phx:page-loading-stop', function() {
            setTimeout(startUpdates, 100);
          });
        })();
      </script>
    </div>

    <%= case @view_mode do %>
      <% :list -> %>
        {render_list_view(assigns)}
      <% :detail -> %>
        {render_detail_view(assigns)}
    <% end %>
    """
  end

  defp render_list_view(assigns) do
    # Extract filter data from changeset and apply to agents
    filter_form =
      case Ecto.Changeset.apply_action(assigns.filter_changeset, :update) do
        {:ok, data} -> data
        {:error, _} -> FilterForm.new()
      end

    assigns =
      assign(
        assigns,
        :filtered_agents,
        FilterForm.apply_filters(assigns.agents, filter_form)
      )

    ~H"""
    <div class="container">
      <header class="header">
        <div class="header-row">
          <h1>Agent Debug Dashboard</h1>
          <label class="auto-follow-toggle">
            <input
              type="checkbox"
              checked={@auto_follow_first}
              phx-click="toggle_auto_follow"
            />
            <span>Auto-Follow First</span>
          </label>
        </div>
        <%= if @followed_agent_id do %>
          <div class="followed-indicator">
            <button phx-click="unfollow_agent" class="btn btn-following-toggle" title="Click to unfollow">
              🕵️ Following
            </button>
            <.link patch={"?agent_id=#{@followed_agent_id}"} class="followed-agent-link">
              {@followed_agent_id}
            </.link>
          </div>
        <% end %>
      </header>

    <!-- System Overview Panel -->
      <.system_overview metrics={@metrics} />

    <!-- Auto-Follow Filter Configuration -->
      <.filter_config_form
        filters={@auto_follow_filters}
        presence_active={@followed_agent_id != nil}
      />

    <!-- Agent List Filters (for visibility/sorting) -->
      <.filter_controls form={@form} />

    <!-- Active Agent List -->
      <.agent_table agents={@filtered_agents} followed_agent_id={@followed_agent_id} />
    </div>
    """
  end

  defp render_detail_view(assigns) do
    ~H"""
    <div class="agent-detail-container">
      <%= if is_nil(@agent_detail) do %>
        <div class="agent-not-found">
          <h2>Agent Not Found</h2>
          <p>Agent {@selected_agent_id} doesn't appear to be active.</p>
          <p class="text-muted">It may have stopped or completed its work.</p>
          <button phx-click="back_to_list" class="btn-back">← Back to Agent List</button>
        </div>
      <% else %>
        <div class="agent-detail-header">
          <button phx-click="back_to_list" class="btn-back">← Back to List</button>
          <h2>Agent: {@selected_agent_id}</h2>
        </div>

        <div class="agent-detail-tabs">
          <button
            phx-click="change_tab"
            phx-value-tab="overview"
            class={"tab-button #{if @current_tab == :overview, do: "active", else: ""}"}
          >
            Overview
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="messages"
            class={"tab-button #{if @current_tab == :messages, do: "active", else: ""}"}
          >
            Messages
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="middleware"
            class={"tab-button #{if @current_tab == :middleware, do: "active", else: ""}"}
          >
            Middleware
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="tools"
            class={"tab-button #{if @current_tab == :tools, do: "active", else: ""}"}
          >
            Tools
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="todos"
            class={"tab-button #{if @current_tab == :todos, do: "active", else: ""}"}
          >
            TODOs
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="events"
            class={"tab-button #{if @current_tab == :events, do: "active", else: ""}"}
          >
            Events
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="subagents"
            class={"tab-button #{if @current_tab == :subagents, do: "active", else: ""}"}
          >
            Sub-Agents (<%= map_size(@subagents) %>)
          </button>
        </div>

        <div class="agent-detail-content">
          <%= case @current_tab do %>
            <% :overview -> %>
              <.overview_tab
                agent={@agent_detail}
                metadata={@agent_metadata}
                state={@agent_state}
                presence_module={@presence_module}
                agent_id={@selected_agent_id}
              />
            <% :messages -> %>
              <.messages_tab state={@agent_state} agent={@agent_detail} />
            <% :middleware -> %>
              <.middleware_tab agent={@agent_detail} />
            <% :tools -> %>
              <.tools_tab agent={@agent_detail} />
            <% :events -> %>
              <.events_tab event_stream={@event_stream} user_timezone={@user_timezone} />
            <% :todos -> %>
              <.todos_tab state={@agent_state} />
            <% :subagents -> %>
              <.subagents_view
                subagents={@subagents}
                expanded_subagent={@expanded_subagent}
                subagent_tab={@subagent_tab}
              />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Component: System Overview
  defp system_overview(assigns) do
    ~H"""
    <div class="overview">
      <h2>📊 Active Agents</h2>
      <div class="metrics-grid">
        <div class="metric-card">
          <div class="metric-value">🔵 {@metrics.total_agents}</div>
          <div class="metric-label">Total Agents</div>
        </div>
        <div class="metric-card">
          <div class="metric-value">🟢 {@metrics.running}</div>
          <div class="metric-label">Running</div>
        </div>
        <div class="metric-card">
          <div class="metric-value">🟡 {@metrics.idle}</div>
          <div class="metric-label">Idle</div>
        </div>
        <div class="metric-card">
          <div class="metric-value">👁️ {@metrics.total_viewers}</div>
          <div class="metric-label">Total Viewers</div>
        </div>
      </div>
    </div>
    """
  end

  # Component: Filter Controls
  defp filter_controls(assigns) do
    ~H"""
    <.form for={@form} phx-change="update_filters">
      <div class="filters">
        <div class="filter-group">
          <.input
            field={@form[:status_filter]}
            type="select"
            label="Status"
            options={[
              {"All Agents", :all},
              {"Running", :running},
              {"Idle", :idle},
              {"Interrupted", :interrupted},
              {"Error", :error},
              {"Cancelled", :cancelled}
            ]}
            class="filter-select"
          />
        </div>

        <div class="filter-group">
          <.input
            field={@form[:presence_filter]}
            type="select"
            label="Presence"
            options={[
              {"All", :all},
              {"Has viewers", :has_viewers},
              {"No viewers", :no_viewers}
            ]}
            class="filter-select"
          />
        </div>

        <div class="filter-group search">
          <.input
            field={@form[:search_query]}
            type="text"
            label="Search"
            placeholder="Search agents..."
            class="filter-input"
            phx-debounce="300"
          />
        </div>

        <div class="filter-group">
          <.input
            field={@form[:sort_by]}
            type="select"
            label="Sort"
            options={[
              {"Activity", :last_activity},
              {"Viewers", :viewers},
              {"Uptime", :uptime}
            ]}
            class="filter-select"
          />
        </div>
      </div>
    </.form>
    """
  end

  # Component: Agent Table
  defp agent_table(assigns) do
    ~H"""
    <div class="table-container">
      <table>
        <thead>
          <tr>
            <th>Agent ID</th>
            <th>Status</th>
            <th>Viewers</th>
            <th>Last Activity</th>
            <th>Uptime</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for agent <- @agents do %>
            <.agent_row agent={agent} followed_agent_id={@followed_agent_id} />
          <% end %>
        </tbody>
      </table>

      <%= if @agents == [] do %>
        <div class="empty-state">
          <p>No active agents. Agents appear here when they're running.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Component: Single Agent Row
  defp agent_row(assigns) do
    is_followed = assigns.followed_agent_id == assigns.agent.agent_id
    assigns = assign(assigns, :is_followed, is_followed)

    ~H"""
    <tr class={if @is_followed, do: "followed-row", else: ""}>
      <td>
        <div class="conv-id">
          <span class="conv-id-icon">
            {status_emoji(@agent.status)}
          </span>
          <span>{@agent.agent_id}</span>
          <%= if @is_followed do %>
            <span class="followed-badge" title="Following">🕵️</span>
          <% end %>
        </div>
        <%= if @agent.conversation_id do %>
          <div class="agent-id">
            Conversation: {@agent.conversation_id}
          </div>
        <% end %>
      </td>
      <td>
        <span class="status-badge">
          {status_text(@agent.status)}
        </span>
        <div class="status-desc">
          {status_description(@agent.status)}
        </div>
      </td>
      <td>
        <span class="viewer-count">
          {@agent.viewer_count}
        </span>
      </td>
      <td class="text-gray">
        <%= if @agent.last_activity do %>
          <span data-time-ago={DateTime.to_iso8601(@agent.last_activity)}>
            {format_time_ago(@agent.last_activity)}
          </span>
        <% else %>
          <span class="text-muted">—</span>
        <% end %>
      </td>
      <td class="text-gray">
        <%= if @agent.started_at do %>
          <span data-duration-since={DateTime.to_iso8601(@agent.started_at)}>
            {format_duration_from_start(@agent.started_at)}
          </span>
        <% else %>
          <span class="text-muted">—</span>
        <% end %>
      </td>
      <td class="actions-cell">
        <.link
          patch={"?agent_id=#{@agent.agent_id}"}
          class="btn btn-view"
        >
          View
        </.link>
        <%= if @is_followed do %>
          <button phx-click="unfollow_agent" class="btn btn-unfollow">
            Unfollow
          </button>
        <% else %>
          <button phx-click="follow_agent" phx-value-id={@agent.agent_id} class="btn btn-follow">
            Follow
          </button>
        <% end %>
      </td>
    </tr>
    """
  end

  # Helper functions
  defp status_emoji(:running), do: "🟢"
  defp status_emoji(:idle), do: "🟡"
  defp status_emoji(:stopped), do: "⚫"
  defp status_emoji(:interrupted), do: "✋"
  defp status_emoji(:error), do: "❌"
  defp status_emoji(:cancelled), do: "🚫"
  defp status_emoji(:shutdown), do: "🔴"
  defp status_emoji(_), do: "❓"

  defp status_text(:running), do: "RUNNING"
  defp status_text(:idle), do: "IDLE"
  defp status_text(:stopped), do: "STOPPED"
  defp status_text(:interrupted), do: "INTERRUPTED"
  defp status_text(:error), do: "ERROR"
  defp status_text(:cancelled), do: "CANCELLED"
  defp status_text(:shutdown), do: "SHUTDOWN"
  defp status_text(_), do: "UNKNOWN"

  defp status_description(:running), do: "⚡ Processing message"
  defp status_description(:idle), do: "💤 Waiting for input"
  defp status_description(:stopped), do: "🔵 Not started yet"
  defp status_description(:interrupted), do: "✋ Awaiting human decision"
  defp status_description(:error), do: "❌ Execution failed"
  defp status_description(:cancelled), do: "🚫 Cancelled by user"
  defp status_description(:shutdown), do: "💨 Shut down"
  defp status_description(_), do: "❓ Unknown"

  defp format_time_ago(nil), do: "Never"

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 5 -> "Just now"
      diff_seconds < 60 -> "#{diff_seconds} seconds ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
      true -> "#{div(diff_seconds, 86400)} days ago"
    end
  end

  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)

    cond do
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end

  defp format_duration(_), do: "—"

  # Format duration from a start DateTime to now
  defp format_duration_from_start(nil), do: "—"

  defp format_duration_from_start(started_at) do
    ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    format_duration(ms)
  end

  # Get presence metadata for a specific agent
  # This is the source of truth for agent timing data (started_at, last_activity_at)
  defp get_agent_presence_metadata(nil, _agent_id), do: nil

  defp get_agent_presence_metadata(presence_module, agent_id) do
    presences = LangChain.Presence.list(presence_module, @agent_presence_topic)

    case Map.get(presences, agent_id) do
      %{metas: [meta | _]} -> meta
      _ -> nil
    end
  end

  # Detail View Components (from AgentDetailLive)

  # Overview Tab
  defp overview_tab(assigns) do
    # Get started_at from presence metadata (source of truth for timing data)
    presence_meta = get_agent_presence_metadata(assigns.presence_module, assigns.agent_id)
    started_at = if presence_meta, do: Map.get(presence_meta, :started_at), else: nil
    assigns = assign(assigns, :started_at, started_at)

    ~H"""
    <div class="overview-tab">
      <%= if @metadata do %>
        <.agent_info_section agent={@agent} metadata={@metadata} />
        <.detail_status_section metadata={@metadata} started_at={@started_at} />
        <%= if @agent do %>
          <.model_section agent={@agent} />
        <% end %>
      <% else %>
        <p class="loading">Loading agent data...</p>
      <% end %>
    </div>
    """
  end

  defp agent_info_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🔍 Agent Information</h3>
      <div class="info-card">
        <div class="info-row">
          <span class="info-label">Agent ID:</span>
          <span class="info-value">{@agent.agent_id}</span>
        </div>
        <%= if @metadata.conversation_id do %>
          <div class="info-row">
            <span class="info-label">Conversation ID:</span>
            <span class="info-value">{@metadata.conversation_id}</span>
          </div>
        <% end %>
        <%= if @agent.name do %>
          <div class="info-row">
            <span class="info-label">Agent Name:</span>
            <span class="info-value">{@agent.name}</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp detail_status_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>⚡ Current Status</h3>
      <div class="info-card">
        <div class="info-row">
          <span class="info-label">Status:</span>
          <span class="info-value">
            {status_emoji(@metadata.status)}
            {detail_status_description(@metadata.status)}
          </span>
        </div>
        <%= if @metadata.last_activity_at do %>
          <div class="info-row">
            <span class="info-label">Last Activity:</span>
            <span class="info-value">
              <span data-time-ago={DateTime.to_iso8601(@metadata.last_activity_at)}>
                {detail_format_time_ago(@metadata.last_activity_at)}
              </span>
            </span>
          </div>
        <% end %>
        <%= if @started_at do %>
          <div class="info-row">
            <span class="info-label">Uptime:</span>
            <span class="info-value">
              <span data-duration-since={DateTime.to_iso8601(@started_at)}>
                {format_duration_from_start(@started_at)}
              </span>
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Note: middleware_section, middleware_item, middleware_model_config, middleware_config_entry,
  # get_model_name, format_config_key, format_config_value, and format_module_name
  # are now imported from SagentsLiveDebugger.Live.Components.MessageComponents

  defp tools_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🛠️ Tools ({length(@agent.tools)})</h3>
      <%= if Enum.empty?(@agent.tools) do %>
        <p class="empty-state">No tools available</p>
      <% else %>
        <div class="list-card">
          <%= for tool <- @agent.tools do %>
            <.tool_item tool={tool} prefix="main-" />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp model_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🤖 Model Configuration</h3>
      <div class="info-card">
        <%= if @agent.model do %>
          <div class="info-row">
            <span class="info-label">Model:</span>
            <span class="info-value">{@agent.model.model}</span>
          </div>
          <%= if @agent.model.temperature do %>
            <div class="info-row">
              <span class="info-label">Temperature:</span>
              <span class="info-value">{@agent.model.temperature}</span>
            </div>
          <% end %>
        <% else %>
          <p class="empty-state">No model information available</p>
        <% end %>
      </div>
    </div>
    """
  end

  # System Message Sections Component
  defp system_message_sections(assigns) do
    ~H"""
    <div class="system-messages-container">
      <!-- Assembled System Prompt -->
      <%= if @agent.assembled_system_prompt && @agent.assembled_system_prompt != "" do %>
        <div class="system-message-section">
          <div class="system-message-card">
            <div
              class="system-message-header"
              phx-click={
                Phoenix.LiveView.JS.toggle(to: "#content-assembled")
                |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "#toggle-assembled")
              }
            >
              <div class="system-message-title">
                <span class="system-message-icon">⚙️</span>
                <span>Assembled System Prompt</span>
                <span class="system-message-badge">Active Configuration</span>
              </div>
              <span class="toggle-icon collapsed" id="toggle-assembled"></span>
            </div>

            <div class="system-message-content-wrapper" id="content-assembled" style="display: none;">
              <div class="formatted-content system-message-content" phx-no-format><%= @agent.assembled_system_prompt %></div>
              <div class="system-message-info">
                <small>
                  ℹ️ This is the complete system message sent to the LLM, including contributions from all middleware.
                  It is prepended to conversation messages and protected from summarization.
                </small>
              </div>
            </div>
          </div>
        </div>
      <% end %>

    <!-- Base System Prompt -->
      <%= if @agent.base_system_prompt && @agent.base_system_prompt != "" do %>
        <div class="system-message-section">
          <div class="system-message-card base-prompt">
            <div
              class="system-message-header"
              phx-click={
                Phoenix.LiveView.JS.toggle(to: "#content-base")
                |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "#toggle-base")
              }
            >
              <div class="system-message-title">
                <span class="system-message-icon">📝</span>
                <span>Base System Prompt</span>
                <span class="system-message-badge">Developer Provided</span>
              </div>
              <span class="toggle-icon collapsed" id="toggle-base"></span>
            </div>

            <div class="system-message-content-wrapper" id="content-base" style="display: none;">
              <div class="formatted-content system-message-content" phx-no-format><%= @agent.base_system_prompt %></div>
              <div class="system-message-info">
                <small>
                  ℹ️ This is the base prompt provided by the developer. Middleware may add additional instructions
                  to create the final assembled prompt.
                </small>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Messages Tab
  defp messages_tab(assigns) do
    ~H"""
    <div class="messages-tab">
      <%= if @state && @state.messages do %>
        <!-- System Message Sections -->
        <%= if @agent do %>
          <.system_message_sections agent={@agent} />
        <% end %>

        <div class="messages-header">
          <h3>💬 Conversation Messages ({length(@state.messages)})</h3>
        </div>

        <%= if Enum.empty?(@state.messages) do %>
          <p class="empty-state">No messages yet</p>
        <% else %>
          <div class="messages-list">
            <%= for {message, index} <- Enum.with_index(@state.messages) do %>
              <.message_item message={message} index={index} />
            <% end %>
          </div>
        <% end %>
      <% else %>
        <p class="loading">Loading messages...</p>
      <% end %>
    </div>
    """
  end

  # Middleware Tab
  defp middleware_tab(assigns) do
    ~H"""
    <div class="middleware-tab">
      <%= if @agent do %>
        <.middleware_section agent={@agent} prefix="main-" />
      <% else %>
        <p class="loading">Loading middleware data...</p>
      <% end %>
    </div>
    """
  end

  # Tools Tab
  defp tools_tab(assigns) do
    ~H"""
    <div class="tools-tab">
      <%= if @agent do %>
        <.tools_section agent={@agent} />
      <% else %>
        <p class="loading">Loading tools data...</p>
      <% end %>
    </div>
    """
  end

  # Events Tab
  defp events_tab(assigns) do
    event_count = if assigns[:event_stream], do: length(assigns.event_stream), else: 0
    assigns = assign(assigns, :event_count, event_count)

    ~H"""
    <div class="events-tab">
      <div class="events-header">
        <h3>📡 Event Stream ({@event_count})</h3>
        <p class="events-subtitle">Real-time agent events (last 100)</p>
      </div>

      <%= if @event_stream && @event_stream != [] do %>
        <div class="events-list">
          <%= for event_data <- @event_stream do %>
            <.event_item event_data={event_data} user_timezone={@user_timezone} />
          <% end %>
        </div>
      <% else %>
        <div class="empty-state">
          <p>No events yet. Events will appear here as the agent executes.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp event_item(assigns) do
    event_id = "event-#{assigns.event_data.id}"
    toggle_id = "toggle-#{assigns.event_data.id}"

    assigns = assign(assigns, :event_id, event_id)
    assigns = assign(assigns, :toggle_id, toggle_id)

    ~H"""
    <div class="event-item">
      <div
        class="event-item-header"
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@event_id}")
          |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
        }
      >
        <div class="event-item-main">
          <span class={"event-badge event-badge-#{@event_data.category}"}>
            {if @event_data.category == :debug, do: "Dbg", else: "Std"}
          </span>
          <span class="event-summary">{@event_data.event.summary}</span>
          <%= if Map.has_key?(@event_data.event, :input) do %>
            <span class="event-field-inline">
              <span class="token-input">↑{@event_data.event.input}</span>
              <span class="token-output">↓{@event_data.event.output}</span>
            </span>
          <% end %>
        </div>
        <div class="event-item-meta">
          <span class="event-timestamp">
            {format_timestamp(@event_data.timestamp, @user_timezone)}
          </span>
          <span class="toggle-icon collapsed" id={@toggle_id}></span>
        </div>
      </div>

      <div class="event-details" id={@event_id} style="display: none;">
        <div class="event-details-content">
          <%= if @event_data.event.type == "middleware_action" do %>
            <div class="event-field">
              <span class="event-label">Middleware:</span>
              <span class="event-value">{@event_data.event.middleware}</span>
            </div>
            <div class="event-field">
              <span class="event-label">Action:</span>
              <span class="event-value">{@event_data.event.action}</span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :status) do %>
            <div class="event-field">
              <span class="event-label">Status:</span>
              <span class="event-value">{@event_data.event.status}</span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :content_preview) do %>
            <div class="event-field">
              <span class="event-label">Content Preview:</span>
              <span class="event-value">{@event_data.event.content_preview}</span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :count) do %>
            <div class="event-field">
              <span class="event-label">Count:</span>
              <span class="event-value">{@event_data.event.count}</span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :merged_delta) && @event_data.event.merged_delta do %>
            <div class="event-field">
              <span class="event-label">Merged Delta:</span>
              <pre class="event-raw"><%= inspect(@event_data.event.merged_delta, pretty: true, limit: :infinity) %></pre>
            </div>
          <% end %>

          <div class="event-field">
            <span class="event-label">Raw Event:</span>
            <pre class="event-raw"><%= @event_data.raw_event %></pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_timestamp(datetime, timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} ->
        shifted
        |> DateTime.truncate(:second)
        |> Calendar.strftime("%H:%M:%S %Z")

      {:error, _} ->
        # Fallback to UTC if timezone shift fails
        datetime
        |> DateTime.truncate(:second)
        |> Calendar.strftime("%H:%M:%S UTC")
    end
  end

  # TODOs Tab
  defp todos_tab(assigns) do
    ~H"""
    <div class="todos-tab">
      <%= if @state && @state.todos do %>
        <div class="todos-header">
          <h3>📋 Current TODOs ({length(@state.todos)})</h3>
        </div>

        <%= if Enum.empty?(@state.todos) do %>
          <div class="empty-state">
            <p>No TODOs - Agent is not tracking any tasks</p>
          </div>
        <% else %>
          <div class="todos-list">
            <%= for {todo, index} <- Enum.with_index(@state.todos, 1) do %>
              <.todo_item todo={todo} index={index} />
            <% end %>
          </div>
        <% end %>
      <% else %>
        <div class="empty-state">
          <p>Loading TODO data...</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp todo_item(assigns) do
    ~H"""
    <div class={"todo-item todo-status-#{@todo.status}"}>
      <div class="todo-header">
        <div class="todo-header-left">
          <span class="todo-number">#{@index}</span>
          <span class="todo-icon">{todo_status_icon(@todo.status)}</span>
        </div>
        <span class={"todo-badge status-#{@todo.status}"}>
          {format_status(@todo.status)}
        </span>
      </div>

      <div class="todo-content">
        {@todo.content}
      </div>

      <%= if Map.get(@todo, :active_form) && @todo.active_form do %>
        <div class="todo-active-form">
          <span class="active-form-label">Currently:</span>
          <em>{@todo.active_form}</em>
        </div>
      <% end %>
    </div>
    """
  end

  defp todo_status_icon(status) do
    case status do
      :pending -> "⏸️"
      :in_progress -> "▶️"
      :completed -> "✅"
      _ -> "❓"
    end
  end

  defp format_status(status) do
    status
    |> to_string()
    |> String.upcase()
    |> String.replace("_", " ")
  end

  defp detail_status_description(:running), do: "Processing message"
  defp detail_status_description(:idle), do: "Waiting for input"
  defp detail_status_description(:interrupted), do: "Awaiting human decision"
  defp detail_status_description(:error), do: "Execution failed"
  defp detail_status_description(:cancelled), do: "Cancelled by user"
  defp detail_status_description(_), do: "Unknown"

  defp detail_format_time_ago(nil), do: "Never"

  defp detail_format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 5 -> "Just now"
      diff_seconds < 60 -> "#{diff_seconds} seconds ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
      true -> "#{div(diff_seconds, 86400)} days ago"
    end
  end

  # Note: format_module_name is imported from MessageComponents

  # Event Filtering and Formatting

  defp should_display_event?(event) do
    case event do
      # Filter out events with large payloads
      {:agent_state_update, _state} -> false
      {:agent_state_update, _middleware_id, _state} -> false
      {:state_restored, _state} -> false
      # Display all other events
      _ -> true
    end
  end

  # Helper to extract text preview from message content (handles both string and ContentPart list)
  defp extract_content_preview(content) when is_binary(content) do
    String.slice(content, 0, 100)
  end

  defp extract_content_preview(content) when is_list(content) do
    # Extract text from ContentPart structs
    content
    |> Enum.filter(fn part -> is_map(part) && Map.get(part, :type) == :text end)
    |> Enum.map(fn part -> Map.get(part, :content, "") end)
    |> Enum.join(" ")
    |> String.slice(0, 100)
  end

  defp extract_content_preview(content) do
    inspect(content, limit: 100)
  end

  # Helper to extract text preview from content parts (for Issue #3)
  defp extract_text_preview(content_parts) do
    content_parts
    |> Enum.find_value("", fn
      %{type: :text, content: text} when is_binary(text) -> String.slice(text, 0, 50)
      text when is_binary(text) -> String.slice(text, 0, 50)
      _ -> nil
    end)
  end

  defp format_event_data(event) do
    case event do
      {:status_changed, status, _data} ->
        %{
          type: "status_changed",
          status: to_string(status),
          summary: "Status: #{status}"
        }

      # Issue #2: Tool Result Messages - handle :tool role with tool_results
      {:llm_message, %LangChain.Message{role: :tool, tool_results: tool_results} = message}
      when is_list(tool_results) and length(tool_results) > 0 ->
        # Extract tool names and error status
        result_summaries =
          Enum.map(tool_results, fn result ->
            name = Map.get(result, :name, "unknown")
            is_error = Map.get(result, :is_error, false)
            status = if is_error, do: "✗", else: "✓"
            "#{name} #{status}"
          end)

        summary = "Tool Results: #{Enum.join(result_summaries, ", ")}"

        %{
          type: "llm_message",
          role: "tool",
          tool_results: tool_results,
          summary: summary,
          raw: message
        }

      # Issue #3: Assistant Tool Calls - handle :assistant role with enhanced display
      {:llm_message, %LangChain.Message{role: :assistant} = message} ->
        tool_calls = message.tool_calls || []
        content_parts = List.wrap(message.content || [])

        # Check for thinking content
        has_thinking =
          Enum.any?(content_parts, fn
            %{type: :thinking} -> true
            _ -> false
          end)

        # Check for text content and get preview
        text_preview = extract_text_preview(content_parts)
        has_text = text_preview != ""

        # Build summary parts list
        parts = []
        parts = if has_thinking, do: parts ++ ["[thinking]"], else: parts
        parts = if has_text, do: parts ++ ["[text]"], else: parts

        # Add tool names if present
        tool_names =
          if tool_calls != [] do
            Enum.map(tool_calls, & &1.name) |> Enum.join(", ")
          else
            nil
          end

        parts = if tool_names, do: parts ++ [tool_names], else: parts

        summary = "Assistant: " <> Enum.join(parts, " ")

        %{
          type: "llm_message",
          role: "assistant",
          tool_calls: tool_calls,
          content: content_parts,
          has_thinking: has_thinking,
          has_text: has_text,
          text_preview: text_preview,
          summary: summary,
          raw: message
        }

      # Generic handler for other message roles (user, system, etc.)
      {:llm_message, message} ->
        content_preview = extract_content_preview(message.content)
        # Limit to 60 chars for summary display
        short_preview = String.slice(content_preview, 0, 60)

        role_label =
          case message.role do
            :user -> "User"
            :assistant -> "Assistant"
            _ -> String.capitalize(to_string(message.role))
          end

        %{
          type: "llm_message",
          role: to_string(message.role),
          content_preview: short_preview,
          summary: "#{role_label}: #{short_preview}"
        }

      {:todos_updated, todos} ->
        %{
          type: "todos_updated",
          count: length(todos),
          summary: "TODOs: #{length(todos)}"
        }

      {:llm_deltas, deltas} ->
        # Normalize to list and merge with nil (first batch)
        deltas = List.flatten([deltas])
        delta_count = length(deltas)
        merged_delta = LangChain.MessageDelta.merge_deltas(nil, deltas)

        %{
          type: "llm_deltas",
          merged_delta: merged_delta,
          delta_count: delta_count,
          summary: "Streaming: #{delta_count} deltas"
        }

      {:llm_token_usage, usage} ->
        %{
          type: "llm_token_usage",
          input: usage.input,
          output: usage.output,
          summary: "Tokens:"
        }

      {:conversation_title_generated, title, _agent_id} ->
        %{
          type: "conversation_title_generated",
          title: title,
          summary: "Title generated: #{title}"
        }

      {:middleware_action, middleware_module, action_data} ->
        middleware_name = format_module_name(middleware_module)
        action_summary = format_action_data(action_data)

        %{
          type: "middleware_action",
          middleware: middleware_name,
          action: action_summary,
          summary: "#{middleware_name}: #{action_summary}"
        }

      {:agent_shutdown, data} ->
        %{
          type: "agent_shutdown",
          reason: Map.get(data, :reason, "unknown"),
          summary: "Agent shutting down: #{Map.get(data, :reason, "unknown")}"
        }

      # Issue #5: display_message_saved - enhanced formatting
      {:display_message_saved, display_message} ->
        # Safely extract fields - schema may vary by application
        message_type = Map.get(display_message, :message_type, "unknown")
        content_type = Map.get(display_message, :content_type, "unknown")
        content = Map.get(display_message, :content, %{})

        # Build summary based on content_type
        suffix =
          case content_type do
            "tool_call" ->
              tool_name = get_in(content, ["name"]) || "unknown"
              ": #{tool_name}"

            "tool_result" ->
              tool_name = get_in(content, ["name"]) || "unknown"
              is_error = get_in(content, ["is_error"]) || false
              status = if is_error, do: "✗", else: "✓"
              ": #{tool_name} #{status}"

            "thinking" ->
              # Optional: add short preview
              text = get_in(content, ["text"]) || ""

              preview =
                if String.length(text) > 30 do
                  String.slice(text, 0, 30) <> "..."
                else
                  text
                end

              if preview != "", do: " - #{preview}", else: ""

            _ ->
              ""
          end

        summary = "Saved #{message_type} #{content_type}#{suffix}"

        %{
          type: "display_message_saved",
          message_type: message_type,
          content_type: content_type,
          summary: summary,
          raw: display_message
        }

      # Sub-agent events - wrapped as {:subagent, sub_agent_id, inner_event}
      {:subagent, sub_agent_id, inner_event} ->
        format_subagent_event(sub_agent_id, inner_event)

      other ->
        # Generic fallback for unknown events
        event_type = extract_event_type(other)

        %{
          type: event_type,
          raw: inspect(other, limit: 100),
          summary: "#{event_type} event"
        }
    end
  end

  defp format_action_data(action_data) when is_tuple(action_data) do
    case action_data do
      {action_name, data} when is_atom(action_name) ->
        data_preview =
          data
          |> inspect(limit: 50)
          |> String.slice(0, 100)

        "#{action_name}: #{data_preview}"

      _ ->
        inspect(action_data, limit: 100)
    end
  end

  defp format_action_data(action_data) do
    inspect(action_data, limit: 100)
  end

  # Format sub-agent events for display in the event stream
  defp format_subagent_event(sub_agent_id, {:subagent_started, data}) do
    name = data[:name] || "general-purpose"

    %{
      type: "subagent_started",
      sub_agent_id: sub_agent_id,
      name: name,
      model: data[:model],
      tools: data[:tools] || [],
      summary: "SubAgent started: #{name}"
    }
  end

  defp format_subagent_event(sub_agent_id, {:subagent_status_changed, status}) do
    %{
      type: "subagent_status_changed",
      sub_agent_id: sub_agent_id,
      status: to_string(status),
      summary: "SubAgent #{short_id(sub_agent_id)}: #{status}"
    }
  end

  defp format_subagent_event(sub_agent_id, {:subagent_completed, data}) do
    duration = format_duration(data[:duration_ms])

    %{
      type: "subagent_completed",
      sub_agent_id: sub_agent_id,
      duration_ms: data[:duration_ms],
      result_preview: String.slice(data[:result] || "", 0, 100),
      summary: "SubAgent #{short_id(sub_agent_id)} completed (#{duration})"
    }
  end

  defp format_subagent_event(sub_agent_id, {:subagent_error, reason}) do
    %{
      type: "subagent_error",
      sub_agent_id: sub_agent_id,
      error: inspect(reason, limit: 100),
      summary: "SubAgent #{short_id(sub_agent_id)} error"
    }
  end

  defp format_subagent_event(sub_agent_id, {:subagent_llm_message, message}) do
    role = message.role || :unknown

    %{
      type: "subagent_llm_message",
      sub_agent_id: sub_agent_id,
      role: to_string(role),
      summary: "SubAgent #{short_id(sub_agent_id)}: #{role} message"
    }
  end

  defp format_subagent_event(sub_agent_id, {:subagent_llm_deltas, deltas}) do
    count = length(List.flatten([deltas]))

    %{
      type: "subagent_llm_deltas",
      sub_agent_id: sub_agent_id,
      delta_count: count,
      summary: "SubAgent #{short_id(sub_agent_id)}: streaming"
    }
  end

  defp format_subagent_event(sub_agent_id, event) do
    # Catch-all for unknown subagent events
    event_type =
      case event do
        {type, _} when is_atom(type) -> to_string(type)
        {type, _, _} when is_atom(type) -> to_string(type)
        _ -> "unknown"
      end

    %{
      type: "subagent_#{event_type}",
      sub_agent_id: sub_agent_id,
      raw: inspect(event, limit: 100),
      summary: "SubAgent #{short_id(sub_agent_id)}: #{event_type}"
    }
  end

  # Helper to shorten subagent IDs for display
  defp short_id(sub_agent_id) when is_binary(sub_agent_id) do
    case String.split(sub_agent_id, "-sub-") do
      [_parent, suffix] -> "sub-#{suffix}"
      _ -> String.slice(sub_agent_id, -10, 10)
    end
  end

  defp short_id(sub_agent_id), do: inspect(sub_agent_id)

  defp extract_event_type(event) when is_tuple(event) do
    case event do
      {type, _} when is_atom(type) -> to_string(type)
      {type, _, _} when is_atom(type) -> to_string(type)
      _ -> "unknown"
    end
  end

  defp extract_event_type(_event), do: "unknown"

  defp add_event_to_stream(socket, event, event_category) do
    if should_display_event?(event) do
      existing_events = socket.assigns[:event_stream] || []

      # Special handling for delta events to prevent flooding
      case event do
        {:llm_deltas, deltas} ->
          # Normalize deltas to a list
          deltas = List.flatten([deltas])

          # Check if the latest event is also a delta event with an accumulated delta
          case existing_events do
            # When the latest event is a streaming delta, update and merge new events in
            [
              %{event: %{type: "llm_deltas", merged_delta: prev_merged, delta_count: prev_count}} =
                last_event
              | rest
            ]
            when not is_nil(prev_merged) ->
              # Use merge_deltas/2: pass accumulated delta + new batch
              merged_delta = LangChain.MessageDelta.merge_deltas(prev_merged, deltas)
              new_count = prev_count + length(deltas)

              # Update the existing delta event
              updated_event = %{
                last_event
                | event: %{
                    last_event.event
                    | merged_delta: merged_delta,
                      delta_count: new_count,
                      summary: "Streaming: #{new_count} deltas"
                  },
                  timestamp: DateTime.utc_now()
              }

              assign(socket, :event_stream, [updated_event | rest])

            _ ->
              # No previous delta event, create new one using format_event_data
              event_data = %{
                id: System.unique_integer([:positive, :monotonic]),
                category: event_category,
                event: format_event_data(event),
                raw_event: inspect(event, limit: 200),
                timestamp: DateTime.utc_now()
              }

              new_events = [event_data | Enum.take(existing_events, 99)]
              assign(socket, :event_stream, new_events)
          end

        _ ->
          # Normal event, add to stream
          event_data = %{
            id: System.unique_integer([:positive, :monotonic]),
            category: event_category,
            event: format_event_data(event),
            raw_event: inspect(event, limit: 200),
            timestamp: DateTime.utc_now()
          }

          new_events = [event_data | Enum.take(existing_events, 99)]
          assign(socket, :event_stream, new_events)
      end
    else
      socket
    end
  end

  defp validate_timezone(timezone) when is_binary(timezone) do
    case DateTime.shift_zone(DateTime.utc_now(), timezone) do
      {:ok, _} -> {:ok, timezone}
      {:error, _} -> {:error, :invalid_timezone}
    end
  end

  defp validate_timezone(_), do: {:error, :invalid_timezone}

  ## Sub-Agent Event Handling and State Management

  # Handle sub-agent events and update the subagents state
  defp handle_subagent_event(socket, sub_agent_id, {:subagent_started, data}) do
    subagent_entry = %{
      id: sub_agent_id,
      parent_id: data.parent_id,
      name: data.name || "general-purpose",
      instructions: data.instructions,
      tools: data.tools || [],
      middleware: data[:middleware] || [],
      model: data.model,
      status: :starting,
      started_at: DateTime.utc_now(),
      messages: [],
      streaming_content: "",
      result: nil,
      duration_ms: nil,
      error: nil,
      expanded: false,
      token_usage: nil
    }

    update(socket, :subagents, &Map.put(&1, sub_agent_id, subagent_entry))
  end

  defp handle_subagent_event(socket, sub_agent_id, {:subagent_status_changed, status}) do
    update_subagent(socket, sub_agent_id, %{status: status})
  end

  defp handle_subagent_event(socket, sub_agent_id, {:subagent_llm_message, message}) do
    update(socket, :subagents, fn subagents ->
      case Map.get(subagents, sub_agent_id) do
        nil ->
          subagents

        existing ->
          updated = %{
            existing
            | messages: existing.messages ++ [message],
              streaming_content: ""
          }

          Map.put(subagents, sub_agent_id, updated)
      end
    end)
  end

  defp handle_subagent_event(socket, sub_agent_id, {:subagent_llm_deltas, deltas}) do
    update(socket, :subagents, fn subagents ->
      case Map.get(subagents, sub_agent_id) do
        nil ->
          subagents

        existing ->
          new_content =
            Enum.reduce(List.flatten([deltas]), existing.streaming_content, fn delta, acc ->
              acc <> (delta.content || "")
            end)

          updated = %{existing | streaming_content: new_content}
          Map.put(subagents, sub_agent_id, updated)
      end
    end)
  end

  defp handle_subagent_event(socket, sub_agent_id, {:subagent_completed, data}) do
    update(socket, :subagents, fn subagents ->
      case Map.get(subagents, sub_agent_id) do
        nil ->
          subagents

        existing ->
          updated = %{
            existing
            | status: :completed,
              result: data.result,
              messages: data.messages || existing.messages,
              duration_ms: data.duration_ms,
              streaming_content: "",
              token_usage: data[:token_usage]
          }

          Map.put(subagents, sub_agent_id, updated)
      end
    end)
  end

  defp handle_subagent_event(socket, sub_agent_id, {:subagent_error, reason}) do
    update_subagent(socket, sub_agent_id, %{status: :error, error: reason})
  end

  # Catch-all for unhandled subagent events
  defp handle_subagent_event(socket, _sub_agent_id, _event), do: socket

  # Helper to update a single field in a subagent
  defp update_subagent(socket, sub_agent_id, updates) do
    update(socket, :subagents, fn subagents ->
      case Map.get(subagents, sub_agent_id) do
        nil -> subagents
        existing -> Map.put(subagents, sub_agent_id, Map.merge(existing, updates))
      end
    end)
  end
end
