defmodule SagentsLiveDebugger.Live.Components.MessageComponents do
  @moduledoc """
  Shared components for rendering messages and tools.

  These components are used by both the main AgentListLive and SubagentsTab
  to provide consistent message and tool rendering with expandable/collapsible UI.
  """

  use Phoenix.Component

  @doc """
  Renders a single message item with role emoji, content, tool calls/results, and metadata.
  """
  attr :message, :map, required: true
  attr :index, :integer, default: nil

  def message_item(assigns) do
    ~H"""
    <div class={"message-item message-#{@message.role}"}>
      <div class="message-header">
        <span class="message-role">
          {message_role_emoji(@message.role)}
          {String.capitalize(to_string(@message.role))}
        </span>
        <%= if Map.get(@message, :status) do %>
          <span class={"message-status status-#{Map.get(@message, :status)}"}>
            {Map.get(@message, :status)}
          </span>
        <% end %>
      </div>

      <div class="message-content">
        {render_message_content(@message)}
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

  @doc """
  Renders message content, handling both binary and multimodal content.
  """
  def render_message_content(message) do
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

  @doc """
  Renders a single content part (text, thinking, image, etc.).
  """
  attr :part, :map, required: true

  def content_part(assigns) do
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

  @doc """
  Renders a tool call item.
  """
  attr :tool_call, :map, required: true

  def tool_call_item(assigns) do
    ~H"""
    <div class="tool-call">
      <div class="tool-call-header">
        <span class="tool-name">🔧 {@tool_call.name}</span>
        <%= if @tool_call.call_id do %>
          <span class="tool-call-id">{@tool_call.call_id}</span>
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

  @doc """
  Renders a tool result item.
  """
  attr :tool_result, :map, required: true

  def tool_result_item(assigns) do
    ~H"""
    <div class="tool-result">
      <div class="tool-result-header">
        <span class="tool-name">✅ {@tool_result.name || "Result"}</span>
        <%= if @tool_result.tool_call_id do %>
          <span class="tool-call-id">{@tool_result.tool_call_id}</span>
        <% end %>
        <%= if Map.get(@tool_result, :status) do %>
          <span class={"result-status status-#{Map.get(@tool_result, :status)}"}>
            {Map.get(@tool_result, :status)}
          </span>
        <% end %>
      </div>
      <div class="tool-result-content">
        <pre phx-no-format><%= format_tool_result(@tool_result.content) %></pre>
      </div>
    </div>
    """
  end

  @doc """
  Renders a tool item with expandable description and parameters.
  Expects a tool struct with name, description, parameters, and async fields.
  """
  attr :tool, :map, required: true

  def tool_item(assigns) do
    # Generate unique IDs for this tool item
    tool_id = "tool-#{:erlang.phash2(assigns.tool.name)}"
    toggle_id = "toggle-#{tool_id}"

    assigns =
      assigns
      |> assign(:tool_id, tool_id)
      |> assign(:toggle_id, toggle_id)

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
          {@tool.name}
          <%= if @tool[:async] do %>
            <span class="badge badge-async">Async</span>
          <% end %>
        </span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>

      <div class="middleware-content" id={@tool_id} style="display: none;">
        <div class="list-item-description" style="white-space: pre-wrap;" phx-no-format><%= @tool[:description] || "No description available" %></div>
        <%= if length(@tool[:parameters] || []) > 0 do %>
          <div class="list-item-details">
            <strong>Parameters:</strong>
            <ul phx-no-format><%= for param <- @tool.parameters do %><li style="white-space: pre-wrap;"><code><%= param.name %></code><%= if param.required do %> <span class="badge badge-required">Required</span><% end %> - <%= param.description %></li><% end %></ul>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  ## Middleware Components
  #
  # These components are used for displaying middleware configuration
  # in both the main agent view and sub-agent views.

  @doc """
  Renders a middleware section with a list of middleware entries.
  Expects an agent struct with a middleware field containing MiddlewareEntry structs.
  """
  attr :agent, :map, required: true

  def middleware_section(assigns) do
    ~H"""
    <div class="info-section">
      <h3>🔧 Middleware ({length(@agent.middleware)})</h3>
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

  @doc """
  Renders a single middleware item with expandable configuration.
  Expects a MiddlewareEntry struct with id and config fields.
  """
  attr :entry, :map, required: true

  def middleware_item(assigns) do
    # Filter out agent_id and model from config
    config_without_special = Map.drop(assigns.entry.config, [:agent_id, :model])
    model = Map.get(assigns.entry.config, :model)

    # Generate unique IDs for this middleware item
    middleware_id = "middleware-#{:erlang.phash2(assigns.entry.id)}"
    toggle_id = "toggle-#{middleware_id}"

    assigns =
      assigns
      |> assign(:config_without_special, config_without_special)
      |> assign(:model, model)
      |> assign(:middleware_id, middleware_id)
      |> assign(:toggle_id, toggle_id)

    ~H"""
    <div class="list-item">
      <div
        class="list-item-header middleware-header-clickable"
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@middleware_id}")
          |> Phoenix.LiveView.JS.toggle_class("collapsed", to: "##{@toggle_id}")
        }
      >
        <span class="list-item-name">{format_module_name(@entry.id)}</span>
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

  @doc """
  Renders a model configuration within middleware.
  """
  attr :model, :map, required: true
  attr :entry_id, :any, required: true

  def middleware_model_config(assigns) do
    # Generate unique ID for this model config
    model_id = "model-#{:erlang.phash2(assigns.entry_id)}"
    toggle_id = "toggle-#{model_id}"

    assigns =
      assigns
      |> assign(:model_id, model_id)
      |> assign(:toggle_id, toggle_id)

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
        <span class="model-brief">{get_model_name(@model)}</span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>
      <div class="middleware-model-content" id={@model_id} style="display: none;">
        <pre class="config-value" phx-no-format><%= inspect(@model, pretty: true, limit: :infinity) %></pre>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single config entry within middleware.
  """
  attr :key, :any, required: true
  attr :value, :any, required: true

  def middleware_config_entry(assigns) do
    ~H"""
    <div class="config-entry">
      <div class="config-label">{format_config_key(@key)}</div>
      <pre
        class={"config-value #{if is_binary(@value), do: "config-value-text", else: ""}"}
        phx-no-format
      ><%= format_config_value(@value) %></pre>
    </div>
    """
  end

  # Helper functions - public so they can be used by importers

  def message_role_emoji(:system), do: "⚙️"
  def message_role_emoji(:user), do: "👤"
  def message_role_emoji(:assistant), do: "🤖"
  def message_role_emoji(:tool), do: "🔧"
  def message_role_emoji(_), do: "❓"

  def format_tool_arguments(arguments) when is_map(arguments) do
    Jason.encode!(arguments, pretty: true)
  rescue
    _ -> inspect(arguments, limit: :infinity)
  end

  def format_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> arguments
    end
  rescue
    _ -> arguments
  end

  def format_tool_arguments(arguments), do: inspect(arguments, limit: :infinity)

  def format_tool_result(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> content
    end
  rescue
    _ -> content
  end

  def format_tool_result(content), do: inspect(content, pretty: true, limit: :infinity)

  # Middleware helper functions

  def format_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> List.last()
  end

  def format_module_name(module), do: inspect(module, limit: :infinity)

  def get_model_name(model) when is_map(model) do
    Map.get(model, :model) || Map.get(model, :__struct__) |> format_module_name()
  end

  def get_model_name(_), do: "Unknown"

  def format_config_key(key) when is_atom(key), do: Atom.to_string(key)
  def format_config_key(key), do: inspect(key)

  def format_config_value(value) when is_binary(value), do: value
  def format_config_value(value), do: inspect(value, pretty: true, limit: :infinity)
end
