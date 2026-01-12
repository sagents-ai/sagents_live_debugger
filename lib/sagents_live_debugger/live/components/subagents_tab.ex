defmodule SagentsLiveDebugger.Live.Components.SubagentsTab do
  @moduledoc """
  Component for displaying sub-agents in the debugger.

  Provides a collapsible list of sub-agents with:
  - Status badges
  - Duration display
  - Token usage display
  - Expandable detail views (Config, Messages, Middleware, Tools)
  - Streaming content indicator

  Messages and middleware are rendered using the shared MessageComponents for consistent
  display with expandable tool calls, content parts, and metadata.
  """

  use Phoenix.Component
  import SagentsLiveDebugger.Live.Components.MessageComponents

  @doc """
  Renders the sub-agents view container.

  ## Assigns

  - `subagents` - Map of sub-agent ID to sub-agent data
  - `expanded_subagent` - ID of currently expanded sub-agent (or nil)
  - `subagent_tab` - Currently selected tab within expanded sub-agent ("config", "messages", "middleware", "tools")
  """
  attr :subagents, :map, required: true
  attr :expanded_subagent, :string, default: nil
  attr :subagent_tab, :string, default: "config"

  def subagents_view(assigns) do
    ~H"""
    <div class="subagents-container">
      <%= if map_size(@subagents) == 0 do %>
        <div class="empty-state">
          <p>No sub-agents have been spawned yet.</p>
          <p class="text-muted">Sub-agents appear when the agent uses the "task" tool.</p>
        </div>
      <% else %>
        <div class="subagents-list">
          <%= for {id, subagent} <- Enum.sort_by(@subagents, fn {_, s} -> s.started_at end) do %>
            <.subagent_entry
              subagent={subagent}
              expanded={@expanded_subagent == id}
              selected_tab={@subagent_tab}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single sub-agent entry with header and optional detail view.
  """
  attr :subagent, :map, required: true
  attr :expanded, :boolean, default: false
  attr :selected_tab, :string, default: "config"

  def subagent_entry(assigns) do
    ~H"""
    <div class={["subagent-entry", status_entry_class(@subagent.status)]}>
      <div
        class="subagent-header"
        phx-click="toggle_subagent"
        phx-value-id={@subagent.id}
      >
        <span class="subagent-expand-icon">
          <%= if @expanded, do: "▼", else: "▶" %>
        </span>
        <span class="subagent-name"><%= @subagent.name %></span>
        <.status_badge status={@subagent.status} />
        <%= if @subagent.token_usage do %>
          <.token_usage_badge token_usage={@subagent.token_usage} />
        <% end %>
        <span class="subagent-duration">
          <%= format_duration(@subagent.duration_ms) %>
        </span>
        <span class="subagent-message-count">
          <%= length(@subagent.messages) %> messages
        </span>
      </div>

      <%= if @expanded do %>
        <div class="subagent-detail">
          <div class="subagent-tabs">
            <button
              class={["subagent-tab", @selected_tab == "config" && "active"]}
              phx-click="select_subagent_tab"
              phx-value-tab="config"
            >
              Config
            </button>
            <button
              class={["subagent-tab", @selected_tab == "messages" && "active"]}
              phx-click="select_subagent_tab"
              phx-value-tab="messages"
            >
              Messages
            </button>
            <button
              class={["subagent-tab", @selected_tab == "middleware" && "active"]}
              phx-click="select_subagent_tab"
              phx-value-tab="middleware"
            >
              Middleware
            </button>
            <button
              class={["subagent-tab", @selected_tab == "tools" && "active"]}
              phx-click="select_subagent_tab"
              phx-value-tab="tools"
            >
              Tools
            </button>
          </div>

          <div class="subagent-tab-content">
            <%= case @selected_tab do %>
              <% "config" -> %>
                <.config_view subagent={@subagent} />
              <% "messages" -> %>
                <.messages_view subagent={@subagent} />
              <% "middleware" -> %>
                <.subagent_middleware_view subagent={@subagent} />
              <% "tools" -> %>
                <.tools_view subagent={@subagent} />
              <% _ -> %>
                <.config_view subagent={@subagent} />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the status badge for a sub-agent.
  """
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["subagent-status-badge", status_badge_class(@status)]}>
      <%= format_status(@status) %>
    </span>
    """
  end

  @doc """
  Renders a token usage badge showing input/output tokens.
  """
  attr :token_usage, :map, required: true

  def token_usage_badge(assigns) do
    ~H"""
    <span class="subagent-token-badge" title="Input / Output tokens">
      <%= format_tokens(@token_usage.input) %> / <%= format_tokens(@token_usage.output) %>
    </span>
    """
  end

  @doc """
  Renders the config view for a sub-agent.
  """
  attr :subagent, :map, required: true

  def config_view(assigns) do
    ~H"""
    <div class="subagent-config-view">
      <div class="subagent-config-item">
        <label>ID:</label>
        <code><%= @subagent.id %></code>
      </div>

      <div class="subagent-config-item">
        <label>Parent:</label>
        <code><%= @subagent.parent_id %></code>
      </div>

      <div class="subagent-config-item">
        <label>Model:</label>
        <span><%= @subagent.model || "Unknown" %></span>
      </div>

      <%= if @subagent.instructions do %>
        <div class="subagent-config-item">
          <label>Instructions:</label>
          <pre><%= @subagent.instructions %></pre>
        </div>
      <% end %>

      <%= if @subagent.result do %>
        <div class="subagent-config-item">
          <label>Result:</label>
          <pre><%= format_result(@subagent.result) %></pre>
        </div>
      <% end %>

      <%= if @subagent.error do %>
        <div class="subagent-config-item">
          <label class="subagent-error-label">Error:</label>
          <pre class="subagent-error-content"><%= inspect(@subagent.error, pretty: true, limit: 500) %></pre>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the messages view for a sub-agent.

  Uses the shared message_item component for consistent message rendering
  with expandable tool calls, content parts, and metadata.
  """
  attr :subagent, :map, required: true

  def messages_view(assigns) do
    ~H"""
    <div class="subagent-messages-view">
      <%= if @subagent.streaming_content != "" do %>
        <div class="subagent-streaming">
          <span class="subagent-streaming-dots">
            <span></span>
            <span></span>
            <span></span>
          </span>
          Streaming...
        </div>
        <pre class="subagent-streaming-content"><%= @subagent.streaming_content %></pre>
      <% end %>

      <%= if @subagent.messages == [] and @subagent.streaming_content == "" do %>
        <div class="subagent-messages-empty">
          No messages yet.
        </div>
      <% else %>
        <%= for message <- @subagent.messages do %>
          <.message_item message={message} />
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the tools view for a sub-agent.

  Uses the shared tool_item component for consistent tool rendering
  with expandable descriptions and parameters.
  """
  attr :subagent, :map, required: true

  def tools_view(assigns) do
    ~H"""
    <div class="subagent-tools-view">
      <%= if @subagent.tools == [] do %>
        <div class="subagent-tools-empty">
          No tools available.
        </div>
      <% else %>
        <div class="list-card">
          <%= for tool <- @subagent.tools do %>
            <.tool_item tool={tool} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the middleware view for a sub-agent.

  Uses the shared middleware_item component for consistent middleware rendering
  with expandable configurations.
  """
  attr :subagent, :map, required: true

  def subagent_middleware_view(assigns) do
    ~H"""
    <div class="subagent-middleware-view">
      <%= if @subagent.middleware == [] do %>
        <div class="subagent-middleware-empty">
          No middleware configured.
        </div>
      <% else %>
        <div class="list-card">
          <%= for entry <- @subagent.middleware do %>
            <.middleware_item entry={entry} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp status_entry_class(:starting), do: "status-starting"
  defp status_entry_class(:running), do: "status-running"
  defp status_entry_class(:completed), do: "status-completed"
  defp status_entry_class(:interrupted), do: "status-interrupted"
  defp status_entry_class(:error), do: "status-error"
  defp status_entry_class(_), do: ""

  defp status_badge_class(:starting), do: "status-starting"
  defp status_badge_class(:running), do: "status-running"
  defp status_badge_class(:completed), do: "status-completed"
  defp status_badge_class(:interrupted), do: "status-interrupted"
  defp status_badge_class(:error), do: "status-error"
  defp status_badge_class(_), do: ""

  defp format_status(:starting), do: "Starting"
  defp format_status(:running), do: "Running"
  defp format_status(:completed), do: "Completed"
  defp format_status(:interrupted), do: "Interrupted"
  defp format_status(:error), do: "Error"
  defp format_status(other), do: to_string(other)

  defp format_duration(nil), do: "..."
  defp format_duration(ms) when is_integer(ms) and ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when is_integer(ms), do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(_), do: "-"

  defp format_result(result) when is_binary(result), do: result
  defp format_result(result), do: inspect(result, pretty: true, limit: 500)

  # Format token counts with K suffix for thousands
  defp format_tokens(nil), do: "-"
  defp format_tokens(count) when is_integer(count) and count >= 1000 do
    "#{Float.round(count / 1000, 1)}K"
  end
  defp format_tokens(count) when is_integer(count), do: to_string(count)
  defp format_tokens(_), do: "-"
end
