defmodule SagentsLiveDebugger.Live.Components.MessageComponents do
  @moduledoc """
  Shared components for rendering messages and tools.

  These components are used by both the main AgentListLive and SubagentsTab
  to provide consistent message and tool rendering with expandable/collapsible UI.
  """

  use Phoenix.Component

  import SagentsLiveDebugger.CoreComponents, only: [highlight_code: 1]

  alias LangChain.Message
  alias Sagents.Message.DisplayHelpers

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
        <.message_status message={@message} />
      </div>

      <.message_stop_note message={@message} />

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
          <.highlight_code code={inspect_for_display(@message.metadata)} />
        </details>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the message's status badge.

  The status value is shown verbatim, since it is the name a developer reads in
  their own code. What it means goes in the tooltip instead. Nothing is rendered
  for a message carrying no status.
  """
  attr :message, :map, required: true

  def message_status(assigns) do
    status = stop_status(assigns.message)

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:explanation, status_explanation(status))

    ~H"""
    <span :if={@status} class={"message-status status-#{@status}"} title={@explanation}>
      {@status}
    </span>
    """
  end

  @doc """
  Renders the provider's own account of why a message stopped.

  Nothing is rendered when the provider named no cause. Placed as a sibling of
  the message body rather than inside it: a filtered response arrives with empty
  or near-empty content, so a note nested in the body has nothing to sit beside.
  """
  attr :message, :map, required: true

  def message_stop_note(assigns) do
    assigns =
      assigns
      |> assign(:status, stop_status(assigns.message))
      |> assign(:detail, stop_detail_text(assigns.message))

    ~H"""
    <div :if={@detail} class={"message-stop-note status-#{@status}"}>
      {@detail}
    </div>
    """
  end

  # `DisplayHelpers.stop_reason/1` normalizes a dead stream across the supported
  # LangChain range: releases below 0.10.0 record it as `:cancelled` carrying
  # `metadata[:streaming_error]`, later ones as `:stream_error`. Reading
  # `Message.status` here would badge one condition two different ways depending
  # on which LangChain the host installed. A finished message reports no reason,
  # so its own `:complete` stands in and keeps the badge.
  defp stop_status(%Message{} = message) do
    DisplayHelpers.stop_reason(message) || message.status
  end

  defp stop_status(message), do: Map.get(message, :status)

  defp status_explanation(:length),
    do: "Stopped at the output token cap. The turn ended early and the conversation stays usable."

  defp status_explanation(:cancelled), do: "The caller stopped the response before it finished."

  defp status_explanation(:content_filtered),
    do: "The provider's filter stopped the response."

  defp status_explanation(:stream_error), do: "The stream died mid-response."
  defp status_explanation(_status), do: nil

  # The provider's own description of the cause, when it named one. A filtered
  # response says almost nothing on its own, so the category and explanation are
  # the whole content of the row.
  defp stop_detail_text(%Message{} = message) do
    case DisplayHelpers.stop_details(message) do
      details when is_map(details) -> format_stop_details(details)
      nil -> streaming_error_text(message)
    end
  end

  defp stop_detail_text(_message), do: nil

  defp format_stop_details(details) do
    label =
      [Map.get(details, "type"), Map.get(details, "category")]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" / ")

    case {label, Map.get(details, "explanation")} do
      {"", explanation} when is_binary(explanation) -> explanation
      {"", _no_explanation} -> inspect_for_display(details)
      {label, explanation} when is_binary(explanation) -> "#{label}: #{explanation}"
      {label, _no_explanation} -> label
    end
  end

  # `streaming_error/1` reads `Message.metadata`, which is not serialized, so a
  # message restored from persisted agent state reports its status without the
  # error that produced it.
  defp streaming_error_text(message) do
    case DisplayHelpers.streaming_error(message) do
      %{message: text} when is_binary(text) -> text
      nil -> nil
      error -> inspect_for_display(error)
    end
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

      is_nil(message.content) ->
        assigns = %{}
        ~H""

      true ->
        assigns = %{content: inspect_for_display(message.content)}

        ~H"""
        <div class="formatted-content" phx-no-format><%= @content %></div>
        """
    end
  end

  @doc """
  Renders a single content part (text, thinking, image, etc.).
  """
  attr :part, :map, required: true
  attr :prefix, :string, default: ""

  def content_part(assigns) do
    part = assigns.part
    prefix = assigns[:prefix] || ""

    cond do
      is_map(part) && Map.get(part, :type) == :text ->
        assigns = %{text: Map.get(part, :content, "")}

        ~H"""
        <div class="formatted-content content-part-text" phx-no-format><%= @text %></div>
        """

      is_map(part) && Map.get(part, :type) == :thinking ->
        # Generate unique ID for this thinking block
        thinking_id = "#{prefix}thinking-#{:erlang.phash2(part)}"

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
        assigns = %{part: part, inspected: inspect_for_display(part)}

        ~H"""
        <div class="content-part-image">
          [Image: <.highlight_code code={@inspected} />]
        </div>
        """

      true ->
        assigns = %{inspected: inspect_for_display(part)}

        ~H"""
        <div class="content-part-unknown">
          <.highlight_code code={@inspected} />
        </div>
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
          <.highlight_code code={format_tool_arguments(@tool_call.arguments)} language="json" />
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
    is_interrupt = Map.get(assigns.tool_result, :is_interrupt, false)
    interrupt_data = Map.get(assigns.tool_result, :interrupt_data)

    assigns =
      assigns
      |> assign(:is_interrupt, is_interrupt)
      |> assign(:interrupt_data, interrupt_data)
      |> assign(:formatted_interrupt_data, format_interrupt_data(interrupt_data))

    ~H"""
    <div class="tool-result">
      <div class="tool-result-header">
        <%= if @is_interrupt do %>
          <span class="tool-name">✋ {@tool_result.name || "Result"}</span>
          <span class="result-status status-interrupted">INTERRUPTED</span>
        <% else %>
          <span class="tool-name">✅ {@tool_result.name || "Result"}</span>
        <% end %>
        <%= if @tool_result.tool_call_id do %>
          <span class="tool-call-id">{@tool_result.tool_call_id}</span>
        <% end %>
        <%= if Map.get(@tool_result, :status) do %>
          <span class={"result-status status-#{Map.get(@tool_result, :status)}"}>
            {Map.get(@tool_result, :status)}
          </span>
        <% end %>
      </div>
      <%= if @is_interrupt && @interrupt_data do %>
        <div class="tool-result-interrupt-data">
          <.highlight_code code={@formatted_interrupt_data} language="elixir" />
        </div>
      <% end %>
      <div class="tool-result-content">
        <.highlight_code
          code={format_tool_result(@tool_result.content)}
          language={detect_result_language(@tool_result.content)}
        />
      </div>
    </div>
    """
  end

  defp format_interrupt_data(nil), do: ""

  defp format_interrupt_data(data) do
    inspect(data, pretty: true, limit: :infinity)
  end

  defp detect_result_language(content) when is_binary(content) do
    if String.match?(content, ~r/^\s*[\{\[]/) do
      "json"
    else
      "elixir"
    end
  end

  defp detect_result_language(_), do: "elixir"

  @doc """
  Renders a tool item with expandable description and parameters.
  Expects a tool struct or map with name, description, parameters, and async fields.

  The prefix attribute is used to create unique DOM IDs when the same tool
  is displayed in multiple contexts (e.g., main agent vs sub-agent views).
  """
  attr :tool, :map, required: true
  attr :prefix, :string, default: ""

  def tool_item(assigns) do
    # Extract tool fields safely (works for both structs and maps)
    tool = assigns.tool
    prefix = assigns[:prefix] || ""

    tool_name = get_tool_field(tool, :name)
    tool_async = get_tool_field(tool, :async)
    tool_description = get_tool_field(tool, :description)
    tool_parameters = get_tool_field(tool, :parameters) || []

    # Generate unique IDs for this tool item
    tool_id = "#{prefix}tool-#{:erlang.phash2(tool_name)}"
    toggle_id = "toggle-#{tool_id}"

    assigns =
      assigns
      |> assign(:tool_id, tool_id)
      |> assign(:toggle_id, toggle_id)
      |> assign(:tool_name, tool_name)
      |> assign(:tool_async, tool_async)
      |> assign(:tool_description, tool_description)
      |> assign(:tool_parameters, tool_parameters)

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
          {@tool_name}
          <%= if @tool_async do %>
            <span class="badge badge-async">Async</span>
          <% end %>
        </span>
        <span class="toggle-icon collapsed" id={@toggle_id}></span>
      </div>

      <div class="middleware-content" id={@tool_id} style="display: none;">
        <div class="list-item-description" style="white-space: pre-wrap;" phx-no-format><%= @tool_description || "No description available" %></div>
        <%= if @tool_parameters != [] do %>
          <div class="list-item-details">
            <strong>Parameters:</strong>
            <ul phx-no-format><%= for param <- @tool_parameters do %><li style="white-space: pre-wrap;"><code><%= get_tool_field(param, :name) %></code><%= if get_tool_field(param, :required) do %> <span class="badge badge-required">Required</span><% end %> - <%= get_tool_field(param, :description) %></li><% end %></ul>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper to safely access tool fields from either structs or maps
  defp get_tool_field(tool, field) when is_struct(tool) do
    Map.get(tool, field)
  end

  defp get_tool_field(tool, field) when is_map(tool) do
    Map.get(tool, field) || Map.get(tool, to_string(field))
  end

  defp get_tool_field(_, _), do: nil

  ## Middleware Components
  #
  # These components are used for displaying middleware configuration
  # in both the main agent view and sub-agent views.

  @doc """
  Renders a middleware section with a list of middleware entries.
  Expects an agent struct with a middleware field containing MiddlewareEntry structs.

  The prefix attribute is used to create unique DOM IDs when middleware
  is displayed in multiple contexts (e.g., main agent vs sub-agent views).
  """
  attr :agent, :map, required: true
  attr :prefix, :string, default: ""

  def middleware_section(assigns) do
    assigns = assign_new(assigns, :prefix, fn -> "" end)

    ~H"""
    <div class="info-section">
      <h3>🔧 Middleware ({length(@agent.middleware)})</h3>
      <%= if Enum.empty?(@agent.middleware) do %>
        <p class="empty-state">No middleware configured</p>
      <% else %>
        <div class="list-card">
          <%= for entry <- @agent.middleware do %>
            <.middleware_item entry={entry} prefix={@prefix} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single middleware item with expandable configuration.
  Expects a MiddlewareEntry struct with id and config fields.

  The prefix attribute is used to create unique DOM IDs when the same middleware
  is displayed in multiple contexts (e.g., main agent vs sub-agent views).
  """
  attr :entry, :map, required: true
  attr :prefix, :string, default: ""

  def middleware_item(assigns) do
    prefix = assigns[:prefix] || ""

    # Model is rendered separately by middleware_model_config/1 — it's small and
    # already handled regardless of whether the middleware exposes a debug_summary.
    model = Map.get(assigns.entry.config, :model)

    # The main config display: prefer the middleware's own debug_summary/1 when
    # exported, otherwise fall back to the raw config (with agent_id/model
    # stripped, since they're either internal or rendered separately above).
    display = display_config(assigns.entry)

    # Generate unique IDs for this middleware item
    middleware_id = "#{prefix}middleware-#{:erlang.phash2(assigns.entry.id)}"
    toggle_id = "toggle-#{middleware_id}"

    assigns =
      assigns
      |> assign(:display, display)
      |> assign(:model, model)
      |> assign(:middleware_id, middleware_id)
      |> assign(:toggle_id, toggle_id)
      |> assign(:prefix, prefix)
      |> assign(:tools, Sagents.Middleware.get_tools(assigns.entry))

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
          <.middleware_model_config model={@model} entry_id={@entry.id} prefix={@prefix} />
        <% end %>

        <.middleware_config_display display={@display} />

        <%= if @tools != [] do %>
          <div class="middleware-tools">
            <div class="middleware-tools-header">
              <span class="config-label">Tools ({length(@tools)})</span>
            </div>
            <div class="list-card">
              <%= for tool <- @tools do %>
                <.tool_item tool={tool} prefix={"#{@prefix}mw-#{:erlang.phash2(@entry.id)}-"} />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders the middleware config display, dispatching on the shape of the
  payload returned by `display_config/1`.

  Multi-clause function components let us pick the template at compile time
  via pattern matching, instead of a runtime `case` inside HEEx.
  """
  attr :display, :any, required: true

  def middleware_config_display(%{display: {:map, config_map}} = assigns)
      when map_size(config_map) > 0 do
    assigns = assign(assigns, :config_map, config_map)

    ~H"""
    <div class="middleware-config">
      <%= for {key, value} <- @config_map do %>
        <.middleware_config_entry key={key} value={value} />
      <% end %>
    </div>
    """
  end

  def middleware_config_display(%{display: {:string, text}} = assigns)
      when is_binary(text) and text != "" do
    assigns = assign(assigns, :text, text)

    ~H"""
    <div class="middleware-config">
      <.highlight_code code={@text} />
    </div>
    """
  end

  def middleware_config_display(assigns), do: ~H""

  @doc """
  Build the display payload for a middleware's config section.

  Returns:

    * `{:map, map}` — render as a key/value config table
    * `{:string, text}` — render as a single highlighted code block

  Prefers the middleware module's own `c:Sagents.Middleware.debug_summary/1`
  callback when exported. The callback owns the decision of what's useful to
  surface; falling back to the raw config is the safe default for middleware
  that hasn't opted in.
  """
  def display_config(%Sagents.MiddlewareEntry{module: module, config: config}) do
    if Code.ensure_loaded?(module) and function_exported?(module, :debug_summary, 1) do
      case module.debug_summary(config) do
        result when is_map(result) ->
          {:map, Map.drop(result, [:agent_id, :model])}

        result when is_binary(result) ->
          {:string, result}
      end
    else
      {:map, Map.drop(config, [:agent_id, :model])}
    end
  end

  @doc """
  Renders a model configuration within middleware.
  """
  attr :model, :map, required: true
  attr :entry_id, :any, required: true
  attr :prefix, :string, default: ""

  def middleware_model_config(assigns) do
    prefix = assigns[:prefix] || ""

    # Generate unique ID for this model config
    model_id = "#{prefix}model-#{:erlang.phash2(assigns.entry_id)}"
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
        <.highlight_code code={inspect_for_display(@model)} />
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
    # Pre-compute the formatted value to ensure limit: :infinity is respected
    formatted_value =
      if is_binary(assigns.value) do
        assigns.value
      else
        inspect_for_display(assigns.value)
      end

    # Detect if key contains "prompt" for markdown highlighting
    language = detect_config_language(assigns.key)

    assigns =
      assigns
      |> assign(:formatted_value, formatted_value)
      |> assign(:language, language)

    ~H"""
    <div class="config-entry">
      <div class="config-label">{format_config_key(@key)}</div>
      <.highlight_code code={@formatted_value} language={@language} />
    </div>
    """
  end

  defp detect_config_language(key) do
    key_string =
      case key do
        k when is_atom(k) -> Atom.to_string(k)
        k when is_binary(k) -> k
        k -> inspect(k)
      end

    if String.contains?(key_string, "prompt") do
      "markdown"
    else
      "elixir"
    end
  end

  # Helper functions - public so they can be used by importers

  @inspect_limit 200
  @inspect_printable_limit 16_384

  @doc """
  Inspect values for debug display.

  Uses bounded `:limit` and `:printable_limit` so that an unexpectedly large
  middleware config (or any other value) cannot dominate render time and DOM
  size. Middleware modules that hold large structures should implement
  `c:Sagents.Middleware.debug_summary/1` to provide a curated view; this
  function is the safety net for everything else.
  """
  def inspect_for_display(value) do
    inspect(value,
      pretty: true,
      limit: @inspect_limit,
      printable_limit: @inspect_printable_limit
    )
  end

  def message_role_emoji(:system), do: "⚙️"
  def message_role_emoji(:user), do: "👤"
  def message_role_emoji(:assistant), do: "🤖"
  def message_role_emoji(:tool), do: "🔧"
  def message_role_emoji(_), do: "❓"

  def format_tool_arguments(arguments) when is_map(arguments) do
    Jason.encode!(arguments, pretty: true)
  rescue
    _other -> inspect_for_display(arguments)
  end

  def format_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> arguments
    end
  rescue
    _other -> arguments
  end

  def format_tool_arguments(arguments),
    do: inspect_for_display(arguments)

  def format_tool_result(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> content
    end
  rescue
    _other -> content
  end

  def format_tool_result(content),
    do: inspect_for_display(content)

  # Middleware helper functions

  def format_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> List.last()
  end

  def format_module_name(module),
    do: inspect(module)

  def get_model_name(model) when is_map(model) do
    Map.get(model, :model) || Map.get(model, :__struct__) |> format_module_name()
  end

  def get_model_name(_), do: "Unknown"

  def format_config_key(key) when is_atom(key), do: Atom.to_string(key)
  def format_config_key(key), do: inspect(key)

  def format_config_value(value) when is_binary(value), do: value

  def format_config_value(value),
    do: inspect_for_display(value)
end
