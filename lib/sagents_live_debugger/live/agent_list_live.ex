defmodule SagentsLiveDebugger.AgentListLive do
  use Phoenix.LiveView

  import SagentsLiveDebugger.CoreComponents
  alias SagentsLiveDebugger.{Discovery, Metrics, FilterForm}

  # 2 seconds
  @refresh_interval 2_000

  def mount(_params, _session, socket) do
    # Configuration comes from on_mount callback via socket assigns
    coordinator = socket.assigns.coordinator
    presence_module = socket.assigns.presence_module

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

    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    # Extract base path (without query string) for navigation
    base_path = URI.parse(uri).path || ""

    socket = assign(socket, :base_path, base_path)

    case Map.get(params, "agent_id") do
      nil ->
        # List view
        socket =
          socket
          |> assign(:view_mode, :list)
          |> assign(:selected_agent_id, nil)

        {:noreply, socket}

      agent_id ->
        # Detail view - load agent data
        tab = Map.get(params, "tab", "overview")
        current_tab = case tab do
          "messages" -> :messages
          "middleware" -> :middleware
          "tools" -> :tools
          _ -> :overview
        end

        # Subscribe to agent events if connected
        if connected?(socket) && socket.assigns.selected_agent_id != agent_id do
          subscribe_to_agent(agent_id, socket.assigns.coordinator)
        end

        # Touch the agent to reset inactivity timer
        if connected?(socket) do
          LangChain.Agents.AgentServer.touch(agent_id)
        end

        socket =
          socket
          |> assign(:view_mode, :detail)
          |> assign(:selected_agent_id, agent_id)
          |> assign(:current_tab, current_tab)
          |> load_agent_detail(agent_id)

        {:noreply, socket}
    end
  end

  def handle_info(:refresh, socket) do
    # Refresh agent list
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

    # Also refresh agent detail if in detail view
    socket =
      if socket.assigns.view_mode == :detail && socket.assigns.selected_agent_id do
        load_agent_detail(socket, socket.assigns.selected_agent_id)
      else
        socket
      end

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
    require Logger
    Logger.debug("Agent #{shutdown_data.agent_id} shutting down: #{shutdown_data.reason}")

    # The periodic refresh will remove the agent from the list
    # No need to manually update the agent list here
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
    Phoenix.PubSub.subscribe(pubsub_name, topic)
  end

  # Subscribe to agent status change events
  defp subscribe_to_agent(agent_id, coordinator) do
    # Get PubSub name from coordinator
    pubsub_name = coordinator.pubsub_name()

    topic = "agent_server:#{agent_id}"
    Phoenix.PubSub.subscribe(pubsub_name, topic)

    # Also subscribe to debug events
    debug_topic = "agent_server:debug:#{agent_id}"
    Phoenix.PubSub.subscribe(pubsub_name, debug_topic)
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
    case assigns.view_mode do
      :list ->
        render_list_view(assigns)
      :detail ->
        render_detail_view(assigns)
    end
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
      <h3>🔧 Middleware</h3>
      <%= if Enum.empty?(@agent.middleware) do %>
        <p class="empty-state">No middleware configured</p>
      <% else %>
        <div class="list-card">
          <%= for entry <- @agent.middleware do %>
            <div class="list-item">
              <div class="list-item-header">
                <span class="list-item-name"><%= format_module_name(entry.id) %></span>
              </div>
              <%= if map_size(entry.config) > 0 do %>
                <div class="list-item-details">
                  <strong>Config:</strong>
                  <pre phx-no-format><%= inspect(entry.config, pretty: true, limit: :infinity) %></pre>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp tools_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🛠️ Tools</h3>
      <%= if Enum.empty?(@agent.tools) do %>
        <p class="empty-state">No tools available</p>
      <% else %>
        <div class="list-card">
          <%= for tool <- @agent.tools do %>
            <div class="list-item">
              <div class="list-item-header">
                <span class="list-item-name"><%= tool.name %></span>
                <%= if tool.async do %>
                  <span class="badge badge-async">Async</span>
                <% end %>
              </div>
              <div class="list-item-description" style="white-space: pre-wrap;" phx-no-format><%= tool.description %></div>
              <%= if length(tool.parameters || []) > 0 do %>
                <div class="list-item-details">
                  <strong>Parameters:</strong>
                  <ul phx-no-format><%= for param <- tool.parameters do %><li style="white-space: pre-wrap;"><code><%= param.name %></code><%= if param.required do %> <span class="badge badge-required">Required</span><% end %> - <%= param.description %></li><% end %></ul>
                </div>
              <% end %>
            </div>
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

  defp message_item(assigns) do
    ~H"""
    <div class={"message-item message-#{@message.role}"}>
      <div class="message-header">
        <span class="message-role">
          <%= message_role_emoji(@message.role) %>
          <%= String.capitalize(to_string(@message.role)) %>
        </span>
        <%= if @message.status do %>
          <span class={"message-status status-#{@message.status}"}>
            <%= @message.status %>
          </span>
        <% end %>
      </div>

      <div class="message-content">
        <%= render_message_content(@message) %>
      </div>

      <%= if @message.tool_calls && length(@message.tool_calls) > 0 do %>
        <div class="message-tool-calls">
          <strong>Tool Calls:</strong>
          <%= for tool_call <- @message.tool_calls do %>
            <.tool_call_item tool_call={tool_call} />
          <% end %>
        </div>
      <% end %>

      <%= if @message.tool_results && length(@message.tool_results) > 0 do %>
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
        <%= if @tool_result.status do %>
          <span class={"result-status status-#{@tool_result.status}"}>
            <%= @tool_result.status %>
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
  end

  defp format_module_name(module), do: inspect(module, limit: :infinity)
end
