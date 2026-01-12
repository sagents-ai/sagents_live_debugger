defmodule SagentsLiveDebugger.Live.Components.FilterConfig do
  @moduledoc """
  Filter configuration component for auto-follow targeting.

  Filters control which agents are auto-followed when auto-follow is enabled.
  All agents are always visible in the list - filters only affect which agent
  gets automatically followed when it appears.

  ## Supported Filters

  - `conversation_id` - Auto-follow agents for a specific conversation
  - `agent_id` - Auto-follow a specific agent by ID
  - Custom scope fields - Auto-follow agents matching application-specific scope
    (e.g., user_id, project_id - these come from agent's filesystem_scope)

  ## Usage in Templates

      <.filter_config_form
        filters={@auto_follow_filters}
        presence_active={@followed_agent_id != nil}
      />
  """
  use Phoenix.Component

  @doc """
  Renders the filter configuration form for auto-follow targeting.

  ## Attributes

  - `filters` - Current filter configuration (`:all`, `:none`, or list of filter tuples)
  - `presence_active` - Whether the debugger is actively following an agent
  """
  attr :filters, :any, required: true
  attr :presence_active, :boolean, default: false

  def filter_config_form(assigns) do
    # Extract current filter values for form display
    filter_values = extract_filter_values(assigns.filters)
    assigns = assign(assigns, :filter_values, filter_values)

    ~H"""
    <div class="filter-config">
      <div class="filter-config-header">
        <h3>Auto-Follow Filters</h3>
      </div>

      <p class="filter-hint">
        Configure filters to target which agents to auto-follow.
        All agents are always visible - filters only affect auto-follow behavior.
      </p>

      <form phx-submit="apply_debug_filters" phx-change="preview_debug_filters">
        <div class="filter-fields">
          <div class="filter-field">
            <label for="filter_conversation_id">Conversation ID</label>
            <input
              type="text"
              id="filter_conversation_id"
              name="filters[conversation_id]"
              value={@filter_values[:conversation_id]}
              placeholder="e.g., conv-123"
              phx-debounce="300"
            />
            <span class="field-hint">Match agents for a specific conversation</span>
          </div>

          <div class="filter-field">
            <label for="filter_agent_id">Agent ID</label>
            <input
              type="text"
              id="filter_agent_id"
              name="filters[agent_id]"
              value={@filter_values[:agent_id]}
              placeholder="e.g., conversation-456"
              phx-debounce="300"
            />
            <span class="field-hint">Match a specific agent by ID</span>
          </div>

          <div class="filter-field">
            <label for="filter_custom_scope">Custom Scope</label>
            <div class="custom-scope-inputs">
              <input
                type="text"
                id="filter_custom_key"
                name="filters[custom_key]"
                value={@filter_values[:custom_key]}
                placeholder="key (e.g., project_id)"
                class="scope-key"
                phx-debounce="300"
              />
              <input
                type="text"
                id="filter_custom_value"
                name="filters[custom_value]"
                value={@filter_values[:custom_value]}
                placeholder="value"
                class="scope-value"
                phx-debounce="300"
              />
            </div>
            <span class="field-hint">Match agents by custom scope field from presence metadata</span>
          </div>
        </div>

        <div class="filter-actions">
          <button type="submit" class="btn btn-primary">
            Apply Filters
          </button>
          <button type="button" phx-click="clear_debug_filters" class="btn btn-secondary">
            Clear All
          </button>
        </div>
      </form>

      <div class={"presence-status #{if @presence_active, do: "active", else: "inactive"}"}>
        <%= if @presence_active do %>
          <span class="status-icon active"></span>
          <span>Following an agent.</span>
        <% else %>
          <%= if @filters == :none do %>
            <span class="status-icon inactive"></span>
            <span>No filters set. Will auto-follow first agent that appears.</span>
          <% else %>
            <span class="status-icon waiting"></span>
            <span>Waiting for matching agent to auto-follow...</span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact filter badge showing active filters.
  Use this in the header to show current filter state at a glance.
  """
  attr :filters, :any, required: true

  def filter_badge(assigns) do
    filter_count = count_active_filters(assigns.filters)
    assigns = assign(assigns, :filter_count, filter_count)

    ~H"""
    <div class="filter-badge-container">
      <%= cond do %>
        <% @filters == :all -> %>
          <span class="filter-badge all">All Agents</span>
        <% @filters == :none -> %>
          <span class="filter-badge none">No Filters</span>
        <% @filter_count > 0 -> %>
          <span class="filter-badge active">
            {@filter_count} Filter<%= if @filter_count > 1, do: "s" %>
          </span>
        <% true -> %>
          <span class="filter-badge none">No Filters</span>
      <% end %>
    </div>
    """
  end

  # Extract current filter values from the filters configuration
  defp extract_filter_values(:all), do: %{}
  defp extract_filter_values(:none), do: %{}

  defp extract_filter_values(filters) when is_list(filters) do
    Enum.reduce(filters, %{}, fn
      {:conversation_id, value}, acc -> Map.put(acc, :conversation_id, value)
      {:agent_id, value}, acc -> Map.put(acc, :agent_id, value)
      {key, value}, acc when is_atom(key) ->
        acc
        |> Map.put(:custom_key, to_string(key))
        |> Map.put(:custom_value, value)
    end)
  end

  defp extract_filter_values(_), do: %{}

  # Count active filters
  defp count_active_filters(:all), do: 0
  defp count_active_filters(:none), do: 0
  defp count_active_filters(filters) when is_list(filters), do: length(filters)
  defp count_active_filters(_), do: 0

  @doc """
  Parse filter form params into filter configuration.

  ## Examples

      iex> parse_filters(%{"conversation_id" => "conv-123"})
      [{:conversation_id, "conv-123"}]

      iex> parse_filters(%{"custom_key" => "project_id", "custom_value" => "proj-456"})
      [{:project_id, "proj-456"}]
  """
  def parse_filters(params) do
    filters = []

    filters =
      case params["conversation_id"] do
        nil -> filters
        "" -> filters
        value -> [{:conversation_id, value} | filters]
      end

    filters =
      case params["agent_id"] do
        nil -> filters
        "" -> filters
        value -> [{:agent_id, value} | filters]
      end

    filters =
      case {params["custom_key"], params["custom_value"]} do
        {nil, _} -> filters
        {_, nil} -> filters
        {"", _} -> filters
        {_, ""} -> filters
        {key, value} ->
          try do
            [{String.to_existing_atom(key), value} | filters]
          rescue
            ArgumentError -> filters
          end
      end

    case filters do
      [] -> :none
      list -> Enum.reverse(list)
    end
  end
end
