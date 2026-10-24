defmodule SagentsLiveDebugger.ToolSearchTest do
  use ExUnit.Case, async: true

  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Function
  alias LangChain.Message
  alias LangChain.Message.{ContentPart, ToolCall}
  alias Sagents.{Agent, State}
  alias SagentsLiveDebugger.AbilitySets
  alias SagentsLiveDebugger.ToolSearch

  defp model, do: ChatAnthropic.new!(%{model: "claude-sonnet-4-5"})

  defp function(name, options \\ []),
    do:
      Function.new!(%{
        name: name,
        options: options,
        function: fn _args, _context -> {:ok, "ok"} end
      })

  defp deferred(name, namespace, description),
    do:
      function(name,
        defer_loading: true,
        namespace: namespace,
        namespace_description: description
      )

  defp agent(switch_opts \\ []) do
    Agent.new!(
      %{
        model: model(),
        tools: [
          function("whoami"),
          deferred("billing_invoices", "billing", "Invoices."),
          deferred("devices_list", "devices", "Devices."),
          deferred("devices_get", "devices", "Devices.")
        ],
        middleware: [{Sagents.Middleware.ToolSearch, switch_opts}]
      },
      replace_default_middleware: true
    )
  end

  defp view(agent, state) do
    ToolSearch.view(agent, state, AbilitySets.view(agent, state).tools)
  end

  test "is nil for an agent without tool search" do
    agent =
      Agent.new!(%{model: model(), tools: [function("whoami")]}, replace_default_middleware: true)

    assert view(agent, State.new!()) == nil
  end

  test "lists namespaces in the order their tools appear, with the catalog" do
    view = view(agent(), State.new!())

    assert [
             %{
               name: "billing",
               description: "Invoices.",
               tools: ["billing_invoices"],
               loaded?: false
             },
             %{name: "devices", tools: ["devices_list", "devices_get"], loaded?: false}
           ] = view.namespaces

    assert view.variant == :bm25
    assert view.catalog =~ "- billing: Invoices."
    assert view.catalog =~ "- devices: Devices."
    assert view.loaded == MapSet.new()
  end

  test "marks what the conversation has loaded" do
    search =
      ContentPart.provider_item!("anthropic", %{
        "type" => "tool_search_tool_result",
        "tool_use_id" => "srvtoolu_1",
        "content" => %{
          "type" => "tool_search_tool_search_result",
          "tool_references" => [%{"type" => "tool_reference", "tool_name" => "devices_list"}]
        }
      })

    state =
      State.new!(%{
        messages: [
          Message.new_user!("Devices?"),
          Message.new_assistant!(%{
            content: [search],
            tool_calls: [ToolCall.new!(%{call_id: "c1", name: "devices_list", arguments: %{}})]
          })
        ]
      })

    view = view(agent(), state)

    assert [%{name: "billing", loaded?: false}, %{name: "devices", loaded?: true}] =
             view.namespaces

    assert view.loaded == MapSet.new(["devices_list"])
  end

  test "reports a catalog turned off as nil" do
    assert view(agent(catalog: false), State.new!()).catalog == nil
  end
end
