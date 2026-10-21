defmodule SagentsLiveDebugger.AbilitySets do
  @moduledoc """
  Reads what an agent sends on its next LLM call: the active ability set, the
  tools and the system prompt.

  Sagents versions with ability sets (`Sagents.Middleware.AbilitySetSwitcher`)
  keep every set's middleware in the agent. `agent.tools` is the union of every
  set's tools and `agent.assembled_system_prompt` is the default set's prompt.
  The set in use is named in the agent's state, so the tools and prompt a chain
  is built with depend on the agent and its current state together, and change
  when the model or the app switches sets.

  Older Sagents versions have no ability sets. For them, and for any agent
  without a switcher, the agent's own tools and assembled prompt are what is
  sent. `Sagents.AbilitySets` is called through `apply/3` so this module
  compiles against versions that lack it.
  """

  @sagents_ability_sets Sagents.AbilitySets

  @typedoc """
  - `:enabled?` - the agent declares ability sets
  - `:active` - the active set name, or `nil` for rails only
  - `:sets` - every declared set name, sorted
  - `:tools` - the tools sent for the active set
  - `:inactive_tools` - `{tool, set_names}` for each tool that belongs only to
    sets other than the active one
  - `:system_prompt` - the system prompt sent for the active set
  """
  @type view :: %{
          enabled?: boolean(),
          active: String.t() | nil,
          sets: [String.t()],
          tools: [map()],
          inactive_tools: [{map(), [String.t()]}],
          system_prompt: String.t() | nil
        }

  @doc """
  Returns the view of `agent` for `state`, or `nil` when there is no agent.

  A `nil` state reads as a state that names no set, so it shows the default
  set.
  """
  @spec view(map() | nil, map() | nil) :: view() | nil
  def view(nil, _state), do: nil

  def view(agent, state) do
    case Map.get(agent, :ability_index) do
      %{effective: effective} = index when is_map(effective) ->
        if supported?(), do: switcher_view(agent, state, index), else: plain_view(agent)

      _none ->
        plain_view(agent)
    end
  end

  defp switcher_view(agent, state, index) do
    active = apply(@sagents_ability_sets, :active, [agent, state || %Sagents.State{}])
    effective = apply(@sagents_ability_sets, :effective, [agent, active])

    sent_names = MapSet.new(effective.tools, & &1.name)
    tool_sets = Map.get(index, :tool_sets) || %{}

    inactive_tools =
      agent.tools
      |> Enum.reject(&MapSet.member?(sent_names, &1.name))
      |> Enum.map(&{&1, tool_sets |> Map.get(&1.name, []) |> Enum.sort()})

    %{
      enabled?: true,
      active: active,
      sets: index.effective |> Map.keys() |> Enum.reject(&is_nil/1) |> Enum.sort(),
      tools: effective.tools,
      inactive_tools: inactive_tools,
      system_prompt: effective.system_prompt
    }
  end

  defp plain_view(agent) do
    %{
      enabled?: false,
      active: nil,
      sets: [],
      tools: agent.tools || [],
      inactive_tools: [],
      system_prompt: agent.assembled_system_prompt
    }
  end

  defp supported? do
    Code.ensure_loaded?(@sagents_ability_sets) and
      function_exported?(@sagents_ability_sets, :active, 2) and
      function_exported?(@sagents_ability_sets, :effective, 2)
  end
end
