defmodule SagentsLiveDebugger.AbilitySets do
  @moduledoc """
  Reads what an agent sends on its next LLM call: the active ability set, the
  tools and the system prompt.

  An agent with ability sets (`Sagents.Middleware.AbilitySetSwitcher`) keeps
  every set's middleware. `agent.tools` is the union of every set's tools and
  `agent.assembled_system_prompt` is the default set's prompt. The set in use
  is named in the agent's state, so the tools and prompt a chain is built with
  depend on the agent and its current state together, and change when the
  model or the app switches sets.

  For an agent without a switcher, the agent's own tools and assembled prompt
  are what is sent.
  """

  alias Sagents.AbilitySets.Index

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
  @spec view(Sagents.Agent.t() | nil, Sagents.State.t() | nil) :: view() | nil
  def view(nil, _state), do: nil

  def view(agent, state) do
    active = Sagents.AbilitySets.active(agent, state || %Sagents.State{})
    effective = Sagents.AbilitySets.effective(agent, active)

    case agent.ability_index do
      %Index{} = index ->
        sent_names = MapSet.new(effective.tools, & &1.name)
        tool_sets = index.tool_sets || %{}

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

      nil ->
        %{
          enabled?: false,
          active: nil,
          sets: [],
          tools: effective.tools || [],
          inactive_tools: [],
          system_prompt: effective.system_prompt
        }
    end
  end
end
