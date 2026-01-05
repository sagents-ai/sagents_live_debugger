defmodule SagentsLiveDebugger.AgentListLive do
  use Phoenix.LiveView
  require Logger

  import SagentsLiveDebugger.CoreComponents
  alias SagentsLiveDebugger.{Discovery, Metrics, FilterForm}

  # Event-Driven Architecture Notes:
  #
  # This LiveView uses a hybrid approach for updates:
  #
  # 1. Agent List View:
  #    - Refreshes every 2 seconds via :refresh timer
  #    - Shows agent discovery, status badges, metrics
  #    - Subscribes to all agent regular topics for status updates
  #
  # 2. Agent Detail View:
  #    - NO polling - entirely event-driven
  #    - Subscribes to both regular and debug PubSub topics
  #    - Real-time updates via handle_info event handlers:
  #      - :todos_updated -> Updates TODOs tab
  #      - :llm_message -> Updates Messages tab
  #      - :status_changed -> Updates status in metadata
  #      - :middleware_action -> Adds to Events stream
  #      - All events -> Added to Events tab stream
  #
  # Subscription Management:
  #    - Subscribe when entering detail view
  #    - Unsubscribe when leaving detail view or switching agents
  #    - Tracked via :subscribed_agent_id assign

  # 2 seconds
  @refresh_interval 2_000

  def mount(_params, _session, socket) do
    # Configuration comes from on_mount callback via socket assigns
    coordinator = socket.assigns.coordinator
    presence_module = socket.assigns.presence_module
    # Ensure user_timezone is set (comes from SessionConfig, default to UTC if missing)
    user_timezone = Map.get(socket.assigns, :user_timezone, "UTC")

    # Schedule periodic refresh
    if connected?(socket) do
      schedule_refresh()
    end

    # Initial data load
    agents = Discovery.list_agents(coordinator)
    metrics = Metrics.calculate_metrics(agents)

    # Subscribe to presence changes for conversation agents (if configured)
    # Get pubsub_name from coordinator if presence tracking is enabled
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
        current_tab = case tab do
          "messages" -> :messages
          "middleware" -> :middleware
          "tools" -> :tools
          "todos" -> :todos
          "events" -> :events
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
    # Keep events when switching tabs or reloading the same agent detail view
    if previous_agent_id != current_agent_id do
      assign(socket, :event_stream, [])
    else
      socket
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

  def handle_info(:refresh, socket) do
    # Only refresh agent list and metrics
    agents = Discovery.list_agents(socket.assigns.coordinator)
    metrics = Metrics.calculate_metrics(agents)

    # Subscribe to any new conversation agents
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

    # NOTE: The detail view updates via PubSub events:
    # - :todos_updated events update TODOs
    # - :llm_message events update messages
    # - :status_changed events update status
    # - All events are captured in the Events tab
    # This eliminates polling and provides real-time updates (<200ms latency)

    schedule_refresh()

    {:noreply, socket}
  end

  # Handle agent status change events (for detail view)
  def handle_info({:status_changed, new_status, _data}, socket) do
    if socket.assigns.view_mode == :detail && socket.assigns.agent_metadata do
      updated_metadata = Map.put(socket.assigns.agent_metadata, :status, new_status)
      {:noreply, assign(socket, :agent_metadata, updated_metadata)}
    else
      {:noreply, socket}
    end
  end

  # Handle presence_diff events for real-time viewer count updates
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
  def handle_info({:agent_shutdown, shutdown_data}, socket) do
    # Log the shutdown for debugging
    Logger.debug("Agent #{shutdown_data.agent_id} shutting down: #{shutdown_data.reason}")

    # The periodic refresh will remove the agent from the list
    # No need to manually update the agent list here
    {:noreply, socket}
  end

  # Handle todos_updated events
  def handle_info({:todos_updated, todos}, socket) do
    socket =
      if socket.assigns.view_mode == :detail && socket.assigns.agent_state do
        # Update the agent state with new todos
        updated_state = %{socket.assigns.agent_state | todos: todos}

        socket
        |> assign(:agent_state, updated_state)
        |> add_event_to_stream({:todos_updated, todos}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_message events
  def handle_info({:llm_message, message}, socket) do
    socket =
      if socket.assigns.view_mode == :detail && socket.assigns.agent_state do
        # Append message to state
        updated_messages = socket.assigns.agent_state.messages ++ [message]
        updated_state = %{socket.assigns.agent_state | messages: updated_messages}

        socket
        |> assign(:agent_state, updated_state)
        |> add_event_to_stream({:llm_message, message}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_deltas events (streaming tokens)
  def handle_info({:llm_deltas, deltas}, socket) do
    socket =
      if socket.assigns.view_mode == :detail do
        add_event_to_stream(socket, {:llm_deltas, deltas}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle llm_token_usage events
  def handle_info({:llm_token_usage, usage}, socket) do
    socket =
      if socket.assigns.view_mode == :detail do
        add_event_to_stream(socket, {:llm_token_usage, usage}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle conversation_title_generated events
  def handle_info({:conversation_title_generated, title, agent_id}, socket) do
    socket =
      if socket.assigns.view_mode == :detail do
        add_event_to_stream(socket, {:conversation_title_generated, title, agent_id}, :std)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handler for wrapped debug events
  # Debug events are wrapped with {:debug, event} tuple in AgentServer
  def handle_info({:debug, event}, socket) do
    socket =
      if socket.assigns.view_mode == :detail do
        add_event_to_stream(socket, event, :debug)
      else
        socket
      end

    {:noreply, socket}
  end

  # Catch-all handler for debug events and other regular events
  # This needs to come AFTER specific handlers
  def handle_info({:middleware_action, _module, _action} = event, socket) do
    socket =
      if socket.assigns.view_mode == :detail do
        # Middleware actions are debug events
        add_event_to_stream(socket, event, :debug)
      else
        socket
      end

    {:noreply, socket}
  end

  # Generic catch-all for any other tuple events
  # This should be the LAST handle_info clause for events
  def handle_info(event, socket) when is_tuple(event) do
    socket =
      if socket.assigns.view_mode == :detail do
        # Assume standard event unless it matches debug patterns
        category = if tuple_size(event) >= 1 && elem(event, 0) == :agent_state_update do
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
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
    metadata = case LangChain.Agents.AgentServer.get_metadata(agent_id) do
      {:ok, meta} -> meta
      {:error, _} -> nil
    end

    # get_state returns State.t() directly, not a tuple
    state = try do
      LangChain.Agents.AgentServer.get_state(agent_id)
    catch
      :exit, _ -> nil
    end

    agent = case LangChain.Agents.AgentServer.get_agent(agent_id) do
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

  def render(assigns) do
    ~H"""
    <!-- Hidden form for timezone submission - NOT in phx-update ignore so events work -->
    <form id="sagents-tz-form" phx-change="set_timezone" style="display: none;">
      <input type="hidden" id="sagents-tz-input" name="timezone" value="UTC" />
    </form>

    <!-- Timezone detection script - phx-update="ignore" prevents re-execution -->
    <div phx-update="ignore" id="sagents-tz-script-container">
      <script>
        (function() {
          // Wait for LiveView to finish loading
          window.addEventListener('phx:page-loading-stop', function() {
            const input = document.getElementById('sagents-tz-input');
            if (input) {
              const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
              input.value = tz;
              input.dispatchEvent(new Event('input', { bubbles: true }));
            }
          }, { once: true });
        })();
      </script>
    </div>

    <%= case @view_mode do %>
      <% :list -> %>
        <%= render_list_view(assigns) %>
      <% :detail -> %>
        <%= render_detail_view(assigns) %>
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
        <h1>Agent Debug Dashboard</h1>
      </header>

      <!-- System Overview Panel -->
      <.system_overview metrics={@metrics} />

      <!-- Filters -->
      <.filter_controls form={@form} />

      <!-- Active Agent List -->
      <.agent_table agents={@filtered_agents} />
    </div>
    """
  end

  defp render_detail_view(assigns) do
    ~H"""
    <div class="agent-detail-container">
      <%= if is_nil(@agent_detail) do %>
        <div class="agent-not-found">
          <h2>Agent Not Found</h2>
          <p>Agent <%= @selected_agent_id %> doesn't appear to be active.</p>
          <p class="text-muted">It may have stopped or completed its work.</p>
          <button phx-click="back_to_list" class="btn-back">← Back to Agent List</button>
        </div>
      <% else %>
        <div class="agent-detail-header">
          <button phx-click="back_to_list" class="btn-back">← Back to List</button>
          <h2>Agent: <%= @selected_agent_id %></h2>
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
        </div>

        <div class="agent-detail-content">
          <%= case @current_tab do %>
            <% :overview -> %>
              <.overview_tab agent={@agent_detail} metadata={@agent_metadata} state={@agent_state} />
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
            <.agent_row agent={agent} />
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
    ~H"""
    <tr>
      <td>
        <div class="conv-id">
          <span class="conv-id-icon">
            <%= status_emoji(@agent.status) %>
          </span>
          <span>{@agent.agent_id}</span>
        </div>
        <%= if @agent.conversation_id do %>
          <div class="agent-id">
            Conversation: {@agent.conversation_id}
          </div>
        <% end %>
      </td>
      <td>
        <span class="status-badge">
          <%= status_text(@agent.status) %>
        </span>
        <div class="status-desc">
          <%= status_description(@agent.status) %>
        </div>
      </td>
      <td>
        <span class="viewer-count">
          👁️ {@agent.viewer_count}
        </span>
      </td>
      <td class="text-gray">
        <%= if @agent.last_activity do %>
          <%= format_time_ago(@agent.last_activity) %>
        <% else %>
          <span class="text-muted">—</span>
        <% end %>
      </td>
      <td class="text-gray">
        <%= if @agent.uptime_ms do %>
          <%= format_duration(@agent.uptime_ms) %>
        <% else %>
          <span class="text-muted">—</span>
        <% end %>
      </td>
      <td>
        <.link
          patch={"?agent_id=#{@agent.agent_id}"}
          class="btn btn-view"
        >
          View
        </.link>
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

  # Detail View Components (from AgentDetailLive)

  # Overview Tab
  defp overview_tab(assigns) do
    ~H"""
    <div class="overview-tab">
      <%= if @metadata do %>
        <.agent_info_section agent={@agent} metadata={@metadata} />
        <.detail_status_section metadata={@metadata} />
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
          <span class="info-value"><%= @agent.agent_id %></span>
        </div>
        <%= if @metadata.conversation_id do %>
          <div class="info-row">
            <span class="info-label">Conversation ID:</span>
            <span class="info-value"><%= @metadata.conversation_id %></span>
          </div>
        <% end %>
        <%= if @agent.name do %>
          <div class="info-row">
            <span class="info-label">Agent Name:</span>
            <span class="info-value"><%= @agent.name %></span>
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
            <%= status_emoji(@metadata.status) %>
            <%= detail_status_description(@metadata.status) %>
          </span>
        </div>
        <%= if @metadata.last_activity_at do %>
          <div class="info-row">
            <span class="info-label">Last Activity:</span>
            <span class="info-value"><%= detail_format_time_ago(@metadata.last_activity_at) %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp middleware_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🔧 Middleware (<%= length(@agent.middleware) %>)</h3>
      <%= if Enum.empty?(@agent.middleware) do %>
        <p class="empty-state">No middleware configured</p>
      <% else %>
        <div class="list-card">
          <%= for entry <- @agent.middleware do %>
            <.middleware_item entry={entry} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp middleware_item(assigns) do
    # Filter out agent_id and model from config
    config_without_special = Map.drop(assigns.entry.config, [:agent_id, :model])
    model = Map.get(assigns.entry.config, :model)

    # Generate unique IDs for this middleware item
    middleware_id = "middleware-#{:erlang.phash2(assigns.entry.id)}"
    toggle_id = "toggle-#{middleware_id}"

    assigns = assign(assigns, :config_without_special, config_without_special)
    assigns = assign(assigns, :model, model)
    assigns = assign(assigns, :middleware_id, middleware_id)
    assigns = assign(assigns, :toggle_id, toggle_id)

    ~H"""
    <div class="list-item">
      <div
        class="list-item-header middleware-header-clickable"
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@middleware_id}")
          |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
        }
      >
        <span class="list-item-name"><%= format_module_name(@entry.id) %></span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>

      <div class="middleware-content" id={@middleware_id} style="display: none;">
        <%= if @model do %>
          <.middleware_model_config model={@model} entry_id={@entry.id} />
        <% end %>

        <%= if map_size(@config_without_special) > 0 do %>
          <div class="middleware-config">
            <%= for {key, value} <- @config_without_special do %>
              <.middleware_config_entry key={key} value={value} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp middleware_model_config(assigns) do
    # Generate unique ID for this model config
    model_id = "model-#{:erlang.phash2(assigns.entry_id)}"
    toggle_id = "toggle-#{model_id}"

    assigns = assign(assigns, :model_id, model_id)
    assigns = assign(assigns, :toggle_id, toggle_id)

    ~H"""
    <div class="middleware-model">
      <div
        class="middleware-model-header"
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@model_id}")
          |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
        }
      >
        <span class="config-label">🤖 Model</span>
        <span class="model-brief"><%= get_model_name(@model) %></span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>
      <div class="middleware-model-content" id={@model_id} style="display: none;">
        <pre class="config-value" phx-no-format><%= inspect(@model, pretty: true, limit: :infinity) %></pre>
      </div>
    </div>
    """
  end

  defp middleware_config_entry(assigns) do
    ~H"""
    <div class="config-entry">
      <div class="config-label"><%= format_config_key(@key) %></div>
      <pre class={"config-value #{if is_binary(@value), do: "config-value-text", else: ""}"} phx-no-format><%= format_config_value(@value) %></pre>
    </div>
    """
  end

  defp get_model_name(model) when is_map(model) do
    Map.get(model, :model) || Map.get(model, :__struct__) |> format_module_name()
  end
  defp get_model_name(_), do: "Unknown"

  defp format_config_key(key) when is_atom(key), do: Atom.to_string(key)
  defp format_config_key(key), do: inspect(key)

  defp format_config_value(value) when is_binary(value), do: value
  defp format_config_value(value), do: inspect(value, pretty: true, limit: :infinity)

  defp tools_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🛠️ Tools (<%= length(@agent.tools) %>)</h3>
      <%= if Enum.empty?(@agent.tools) do %>
        <p class="empty-state">No tools available</p>
      <% else %>
        <div class="list-card">
          <%= for tool <- @agent.tools do %>
            <.tool_item tool={tool} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp tool_item(assigns) do
    # Generate unique IDs for this tool item
    tool_id = "tool-#{:erlang.phash2(assigns.tool.name)}"
    toggle_id = "toggle-#{tool_id}"

    assigns = assign(assigns, :tool_id, tool_id)
    assigns = assign(assigns, :toggle_id, toggle_id)

    ~H"""
    <div class="list-item">
      <div
        class="list-item-header middleware-header-clickable"
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@tool_id}")
          |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
        }
      >
        <span class="list-item-name">
          <%= @tool.name %>
          <%= if @tool.async do %>
            <span class="badge badge-async">Async</span>
          <% end %>
        </span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>

      <div class="middleware-content" id={@tool_id} style="display: none;">
        <div class="list-item-description" style="white-space: pre-wrap;" phx-no-format><%= @tool.description %></div>
        <%= if length(@tool.parameters || []) > 0 do %>
          <div class="list-item-details">
            <strong>Parameters:</strong>
            <ul phx-no-format><%= for param <- @tool.parameters do %><li style="white-space: pre-wrap;"><code><%= param.name %></code><%= if param.required do %> <span class="badge badge-required">Required</span><% end %> - <%= param.description %></li><% end %></ul>
          </div>
        <% end %>
      </div>
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
            <span class="info-value"><%= @agent.model.model %></span>
          </div>
          <%= if @agent.model.temperature do %>
            <div class="info-row">
              <span class="info-label">Temperature:</span>
              <span class="info-value"><%= @agent.model.temperature %></span>
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
          <h3>💬 Conversation Messages (<%= length(@state.messages) %>)</h3>
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
        <.middleware_section agent={@agent} />
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
        <h3>📡 Event Stream (<%= @event_count %>)</h3>
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
            <%= if @event_data.category == :debug, do: "Dbg", else: "Std" %>
          </span>
          <span class="event-summary"><%= @event_data.event.summary %></span>
          <%= if Map.has_key?(@event_data.event, :input) do %>
            <span class="event-field-inline">
              <span class="token-input">↑<%= @event_data.event.input %></span>
              <span class="token-output">↓<%= @event_data.event.output %></span>
            </span>
          <% end %>
        </div>
        <div class="event-item-meta">
          <span class="event-timestamp">
            <%= format_timestamp(@event_data.timestamp, @user_timezone) %>
          </span>
          <span class="toggle-icon collapsed" id={@toggle_id}></span>
        </div>
      </div>

      <div class="event-details" id={@event_id} style="display: none;">
        <div class="event-details-content">
          <%= if @event_data.event.type == "middleware_action" do %>
            <div class="event-field">
              <span class="event-label">Middleware:</span>
              <span class="event-value"><%= @event_data.event.middleware %></span>
            </div>
            <div class="event-field">
              <span class="event-label">Action:</span>
              <span class="event-value"><%= @event_data.event.action %></span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :status) do %>
            <div class="event-field">
              <span class="event-label">Status:</span>
              <span class="event-value"><%= @event_data.event.status %></span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :content_preview) do %>
            <div class="event-field">
              <span class="event-label">Content Preview:</span>
              <span class="event-value"><%= @event_data.event.content_preview %></span>
            </div>
          <% end %>

          <%= if Map.has_key?(@event_data.event, :count) do %>
            <div class="event-field">
              <span class="event-label">Count:</span>
              <span class="event-value"><%= @event_data.event.count %></span>
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
          <h3>📋 Current TODOs (<%= length(@state.todos) %>)</h3>
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
          <span class="todo-number">#<%= @index %></span>
          <span class="todo-icon"><%= todo_status_icon(@todo.status) %></span>
        </div>
        <span class={"todo-badge status-#{@todo.status}"}>
          <%= format_status(@todo.status) %>
        </span>
      </div>

      <div class="todo-content">
        <%= @todo.content %>
      </div>

      <%= if Map.get(@todo, :active_form) && @todo.active_form do %>
        <div class="todo-active-form">
          <span class="active-form-label">Currently:</span>
          <em><%= @todo.active_form %></em>
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

  defp message_item(assigns) do
    ~H"""
    <div class={"message-item message-#{@message.role}"}>
      <div class="message-header">
        <span class="message-role">
          <%= message_role_emoji(@message.role) %>
          <%= String.capitalize(to_string(@message.role)) %>
        </span>
        <%= if Map.get(@message, :status) do %>
          <span class={"message-status status-#{Map.get(@message, :status)}"}>
            <%= Map.get(@message, :status) %>
          </span>
        <% end %>
      </div>

      <div class="message-content">
        <%= render_message_content(@message) %>
      </div>

      <%= if @message.tool_calls && @message.tool_calls != [] do %>
        <div class="message-tool-calls">
          <strong>Tool Calls:</strong>
          <%= for tool_call <- @message.tool_calls do %>
            <.tool_call_item tool_call={tool_call} />
          <% end %>
        </div>
      <% end %>

      <%= if @message.tool_results && @message.tool_results != [] do %>
        <div class="message-tool-results">
          <strong>Tool Results:</strong>
          <%= for tool_result <- @message.tool_results do %>
            <.tool_result_item tool_result={tool_result} />
          <% end %>
        </div>
      <% end %>

      <%= if @message.metadata && map_size(@message.metadata) > 0 do %>
        <details class="message-metadata">
          <summary>Metadata</summary>
          <pre phx-no-format><%= inspect(@message.metadata, pretty: true, limit: :infinity) %></pre>
        </details>
      <% end %>
    </div>
    """
  end

  defp render_message_content(message) do
    cond do
      is_binary(message.content) ->
        assigns = %{content: message.content}
        ~H"""
        <div class="formatted-content" phx-no-format><%= @content %></div>
        """

      is_list(message.content) ->
        assigns = %{content: message.content}
        ~H"""
        <div class="multimodal-content">
          <.content_part :for={part <- @content} part={part} />
        </div>
        """

      true ->
        assigns = %{content: inspect(message.content, limit: :infinity)}
        ~H"""
        <div class="formatted-content" phx-no-format><%= @content %></div>
        """
    end
  end

  defp content_part(assigns) do
    part = assigns.part

    cond do
      is_map(part) && Map.get(part, :type) == :text ->
        assigns = %{text: Map.get(part, :content, "")}
        ~H"""
        <div class="formatted-content content-part-text" phx-no-format><%= @text %></div>
        """

      is_map(part) && Map.get(part, :type) == :thinking ->
        # Generate unique ID for this thinking block
        thinking_id = "thinking-#{:erlang.phash2(part)}"
        assigns = %{
          content: Map.get(part, :content, ""),
          thinking_id: thinking_id,
          toggle_id: "toggle-#{thinking_id}"
        }
        ~H"""
        <div class="content-part-thinking">
          <div
            class="thinking-header"
            phx-click={
              Phoenix.LiveView.JS.toggle(to: "##{@thinking_id}")
              |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
            }
          >
            <span class="thinking-label">💭 Thinking</span>
            <span class="toggle-icon collapsed" id={@toggle_id}></span>
          </div>
          <div class="thinking-content-wrapper" id={@thinking_id} style="display: none;">
            <div class="formatted-content thinking-content" phx-no-format><%= @content %></div>
          </div>
        </div>
        """

      is_map(part) && Map.get(part, :type) == :image ->
        assigns = %{part: part}
        ~H"""
        <div class="content-part-image" phx-no-format>
          [Image: <%= inspect(@part, limit: :infinity) %>]
        </div>
        """

      true ->
        assigns = %{part: part}
        ~H"""
        <div class="content-part-unknown" phx-no-format><%= inspect(@part, limit: :infinity) %></div>
        """
    end
  end

  defp tool_call_item(assigns) do
    ~H"""
    <div class="tool-call">
      <div class="tool-call-header">
        <span class="tool-name">🔧 <%= @tool_call.name %></span>
        <%= if @tool_call.call_id do %>
          <span class="tool-call-id"><%= @tool_call.call_id %></span>
        <% end %>
      </div>
      <%= if @tool_call.arguments do %>
        <div class="tool-arguments">
          <strong>Arguments:</strong>
          <pre phx-no-format><%= format_tool_arguments(@tool_call.arguments) %></pre>
        </div>
      <% end %>
    </div>
    """
  end

  defp tool_result_item(assigns) do
    ~H"""
    <div class="tool-result">
      <div class="tool-result-header">
        <span class="tool-name">✅ <%= @tool_result.name || "Result" %></span>
        <%= if @tool_result.tool_call_id do %>
          <span class="tool-call-id"><%= @tool_result.tool_call_id %></span>
        <% end %>
        <%= if Map.get(@tool_result, :status) do %>
          <span class={"result-status status-#{Map.get(@tool_result, :status)}"}>
            <%= Map.get(@tool_result, :status) %>
          </span>
        <% end %>
      </div>
      <div class="tool-result-content">
        <pre phx-no-format><%= format_tool_result(@tool_result.content) %></pre>
      </div>
    </div>
    """
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

  defp message_role_emoji(:system), do: "⚙️"
  defp message_role_emoji(:user), do: "👤"
  defp message_role_emoji(:assistant), do: "🤖"
  defp message_role_emoji(:tool), do: "🔧"
  defp message_role_emoji(_), do: "❓"

  defp format_tool_arguments(arguments) when is_map(arguments) do
    Jason.encode!(arguments, pretty: true)
  rescue
    _ -> inspect(arguments, limit: :infinity)
  end

  defp format_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> arguments
    end
  rescue
    _ -> arguments
  end

  defp format_tool_arguments(arguments), do: inspect(arguments, limit: :infinity)

  defp format_tool_result(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> content
    end
  rescue
    _ -> content
  end

  defp format_tool_result(content), do: inspect(content, pretty: true, limit: :infinity)

  # Helper to format module names by removing "Elixir." prefix
  defp format_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> List.last()
  end

  defp format_module_name(module), do: inspect(module, limit: :infinity)

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
            [%{event: %{type: "llm_deltas", merged_delta: prev_merged, delta_count: prev_count}} = last_event | rest]
            when not is_nil(prev_merged) ->
              # Use merge_deltas/2: pass accumulated delta + new batch
              merged_delta = LangChain.MessageDelta.merge_deltas(prev_merged, deltas)
              new_count = prev_count + length(deltas)

              # Update the existing delta event
              updated_event = %{
                last_event
                | event: %{last_event.event | merged_delta: merged_delta, delta_count: new_count, summary: "Streaming: #{new_count} deltas"},
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
end
