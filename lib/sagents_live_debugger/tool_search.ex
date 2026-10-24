defmodule SagentsLiveDebugger.ToolSearch do
  @moduledoc """
  Reads an agent's provider tool search for display: the namespaces it
  declares, the catalog its system prompt carries, and what the conversation
  has loaded so far.

  An agent has tool search when its stack holds
  `Sagents.Middleware.ToolSearch`, which gives it a `tool_search_index`.
  """

  alias Sagents.ToolSearch

  @typedoc """
  - `:namespaces` - one map per namespace, in the order its tools appear:
    `:name`, `:description`, `:tools`, `:entry_ids`, and `:loaded?`
  - `:loaded` - the names of the tools the conversation has loaded, as a set
  - `:catalog` - the catalog fragment sent with the given tools, or `nil` when
    the switch is configured with `catalog: false`
  - `:variant` - the search variant, `:bm25` or `:regex`
  """
  @type view :: %{
          namespaces: [map()],
          loaded: MapSet.t(String.t()),
          catalog: String.t() | nil,
          variant: atom()
        }

  @doc """
  Returns the view of `agent` for `state` and the `tools` sent on the next LLM
  call, or `nil` when the agent has no tool search.
  """
  @spec view(Sagents.Agent.t() | nil, Sagents.State.t() | nil, [map()]) :: view() | nil
  def view(%{tool_search_index: index} = agent, state, tools) when is_map(index) do
    switch = Enum.find(agent.middleware, &ToolSearch.switch?/1)
    loaded = ToolSearch.loaded(state || %Sagents.State{}, agent.tools)
    loaded_tools = MapSet.new(loaded.tools)

    namespaces =
      agent.tools
      |> Enum.map(&namespace_of/1)
      |> Enum.filter(&Map.has_key?(index, &1))
      |> Enum.uniq()
      |> Enum.map(fn name ->
        info = Map.fetch!(index, name)

        %{
          name: name,
          description: info.description,
          tools: info.tools,
          entry_ids: info.entry_ids,
          loaded?: name in loaded.namespaces
        }
      end)

    %{
      namespaces: namespaces,
      loaded: loaded_tools,
      catalog: catalog(switch, tools),
      variant: switch && switch.config.variant
    }
  end

  def view(_agent, _state, _tools), do: nil

  defp namespace_of(%LangChain.Function{} = function), do: LangChain.Function.namespace(function)
  defp namespace_of(_tool), do: nil

  defp catalog(%{config: %{catalog: false}}, _tools), do: nil
  defp catalog(nil, _tools), do: nil
  defp catalog(switch, tools), do: ToolSearch.switch_prompt(switch, tools)
end
