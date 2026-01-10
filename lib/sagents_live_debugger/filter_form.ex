defmodule SagentsLiveDebugger.FilterForm do
  @moduledoc """
  Form schema for filtering and sorting agents in the dashboard.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses [:all, :running, :idle, :interrupted, :error, :cancelled]
  @valid_presence [:all, :has_viewers, :no_viewers]
  @valid_sort_by [:last_activity, :viewers, :uptime]

  @primary_key false
  embedded_schema do
    field :status_filter, Ecto.Enum, values: @valid_statuses, default: :all
    field :presence_filter, Ecto.Enum, values: @valid_presence, default: :all
    field :search_query, :string, default: ""
    field :sort_by, Ecto.Enum, values: @valid_sort_by, default: :last_activity
  end

  @doc """
  Creates a changeset for filter form validation.

  ## Examples

      iex> changeset(%FilterForm{}, %{status_filter: "running"})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%FilterForm{}, %{status_filter: "invalid"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(filter_form, attrs) do
    filter_form
    |> cast(attrs, [:status_filter, :presence_filter, :search_query, :sort_by])
    |> validate_required([])
    |> validate_inclusion(:status_filter, @valid_statuses)
    |> validate_inclusion(:presence_filter, @valid_presence)
    |> validate_inclusion(:sort_by, @valid_sort_by)
  end

  @doc """
  Creates a new filter form with default values.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Applies filters to a list of agents.
  """
  def apply_filters(agents, %__MODULE__{} = filters) do
    agents
    |> filter_by_status(filters.status_filter)
    |> filter_by_presence(filters.presence_filter)
    |> filter_by_search(filters.search_query)
    |> sort_agents(filters.sort_by)
  end

  # Filter by agent status
  defp filter_by_status(agents, :all), do: agents

  defp filter_by_status(agents, status) do
    Enum.filter(agents, fn agent -> agent.status == status end)
  end

  # Filter by viewer presence
  defp filter_by_presence(agents, :all), do: agents

  defp filter_by_presence(agents, :has_viewers) do
    Enum.filter(agents, fn agent -> agent.viewer_count > 0 end)
  end

  defp filter_by_presence(agents, :no_viewers) do
    Enum.filter(agents, fn agent -> agent.viewer_count == 0 end)
  end

  # Filter by search query (searches in agent_id)
  defp filter_by_search(agents, ""), do: agents
  defp filter_by_search(agents, nil), do: agents

  defp filter_by_search(agents, query) do
    query_lower = String.downcase(query)

    Enum.filter(agents, fn agent ->
      String.contains?(String.downcase(agent.agent_id), query_lower)
    end)
  end

  # Sort agents
  defp sort_agents(agents, :last_activity) do
    Enum.sort_by(
      agents,
      fn agent ->
        case agent.last_activity do
          nil -> ~U[1970-01-01 00:00:00Z]
          datetime -> datetime
        end
      end,
      {:desc, DateTime}
    )
  end

  defp sort_agents(agents, :viewers) do
    Enum.sort_by(agents, & &1.viewer_count, :desc)
  end

  defp sort_agents(agents, :uptime) do
    Enum.sort_by(
      agents,
      fn agent ->
        agent.uptime_ms || 0
      end,
      :desc
    )
  end
end
