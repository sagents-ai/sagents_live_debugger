defmodule SagentsLiveDebugger.AbilitySetsTest do
  use ExUnit.Case, async: true

  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Function
  alias Sagents.Agent
  alias Sagents.State
  alias SagentsLiveDebugger.AbilitySets

  # `Sagents.AbilitySets` exists only in Sagents versions with ability sets.
  @ability_sets_available Code.ensure_loaded?(Sagents.AbilitySets)

  defp model, do: ChatAnthropic.new!(%{model: "claude-sonnet-4-5"})

  defp tool(name) do
    Function.new!(%{name: name, function: fn _args, _context -> {:ok, "ok"} end})
  end

  describe "an agent without ability sets" do
    test "shows the agent's own tools and assembled prompt" do
      {:ok, agent} =
        Agent.new(
          %{model: model(), base_system_prompt: "Base prompt.", tools: [tool("lookup")]},
          replace_default_middleware: true
        )

      view = AbilitySets.view(agent, State.new!())

      refute view.enabled?
      assert view.active == nil
      assert view.sets == []
      assert view.tools == agent.tools
      assert view.inactive_tools == []
      assert view.system_prompt == agent.assembled_system_prompt
    end

    test "reads an agent from a Sagents version with no ability index" do
      agent = %{tools: [tool("lookup")], assembled_system_prompt: "Prompt."}

      view = AbilitySets.view(agent, nil)

      refute view.enabled?
      assert Enum.map(view.tools, & &1.name) == ["lookup"]
      assert view.system_prompt == "Prompt."
    end

    test "returns nil when there is no agent" do
      assert AbilitySets.view(nil, State.new!()) == nil
    end
  end

  describe "an agent with ability sets" do
    if not @ability_sets_available do
      @describetag skip: "this Sagents version has no ability sets"
    end

    setup do
      {:ok, agent} =
        Agent.new(
          %{
            model: model(),
            base_system_prompt: "Base prompt.",
            tools: [tool("rail_tool")],
            middleware: [
              {Sagents.Middleware.AbilitySetSwitcher,
               sets: %{
                 "planning" => %{
                   when_to_use: "Planning multi-step work.",
                   middleware: [Sagents.Middleware.TodoList]
                 },
                 "asking" => %{
                   when_to_use: "Asking the user a question.",
                   middleware: [Sagents.Middleware.AskUserQuestion]
                 }
               },
               default: "planning"}
            ]
          },
          replace_default_middleware: true
        )

      %{agent: agent}
    end

    defp tool_names(tools), do: tools |> Enum.map(& &1.name) |> Enum.sort()

    defp in_set(name),
      do: State.new!(%{metadata: %{"active_ability_set" => name}})

    test "follows the set named in the state", %{agent: agent} do
      planning = AbilitySets.view(agent, in_set("planning"))
      asking = AbilitySets.view(agent, in_set("asking"))

      assert planning.enabled?
      assert planning.sets == ["asking", "planning"]

      assert planning.active == "planning"
      assert "write_todos" in tool_names(planning.tools)
      refute "ask_user" in tool_names(planning.tools)

      assert asking.active == "asking"
      assert "ask_user" in tool_names(asking.tools)
      refute "write_todos" in tool_names(asking.tools)

      assert planning.system_prompt != asking.system_prompt
      assert asking.system_prompt =~ "Current mode: asking"
    end

    test "lists the tools of other sets with the sets that provide them", %{agent: agent} do
      view = AbilitySets.view(agent, in_set("asking"))

      assert [{%{name: "write_todos"}, ["planning"]}] = view.inactive_tools
      assert "rail_tool" in tool_names(view.tools)
    end

    test "shows the default set when there is no state yet", %{agent: agent} do
      view = AbilitySets.view(agent, nil)

      assert view.active == "planning"
      assert "write_todos" in tool_names(view.tools)
    end
  end
end
