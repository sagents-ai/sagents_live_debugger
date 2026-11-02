defmodule SagentsLiveDebugger.Live.Components.SubagentsTabTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SagentsLiveDebugger.Live.Components.SubagentsTab

  # A sub-agent entry as the debugger builds it from `{:subagent_started, data}`.
  defp subagent(fields) do
    Map.merge(
      %{
        id: "parent-1-sub-1",
        parent_id: "parent-1",
        name: "general-purpose",
        instructions: "Deploy acme to staging.",
        system_prompt: nil,
        tools: [],
        middleware: [],
        model: "glm",
        ability_set: nil,
        ability_set_source: nil,
        status: :running,
        started_at: DateTime.utc_now(),
        messages: [],
        streaming_content: "",
        result: nil,
        duration_ms: nil,
        error: nil,
        expanded: true,
        token_usage: nil
      },
      fields
    )
  end

  defp render_entry(subagent) do
    render_component(&SubagentsTab.subagent_entry/1,
      subagent: subagent,
      expanded: true,
      selected_tab: "config"
    )
    |> LazyHTML.from_fragment()
  end

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))

  test "a requested set is badged in the header and explained in the config" do
    doc = render_entry(subagent(%{ability_set: "devices", ability_set_source: :requested}))

    assert texts(doc, ".subagent-name .badge-ability-set") == ["devices"]

    assert [row] = texts(doc, "#subagent-ability-set-parent-1-sub-1")
    assert row =~ "devices"
    assert row =~ "named by the task call's mode"
  end

  test "an inherited set says it is the parent's current set" do
    doc = render_entry(subagent(%{ability_set: "billing", ability_set_source: :inherited}))

    assert [row] = texts(doc, "#subagent-ability-set-parent-1-sub-1")
    assert row =~ "billing"
    assert row =~ "the parent's current set"
  end

  test "a rails-only sub-agent of a parent with sets says so" do
    doc = render_entry(subagent(%{ability_set_source: :inherited}))

    assert texts(doc, ".subagent-name .badge-ability-set-none") == ["none (rails only)"]
  end

  test "a sub-agent without a set, or from a sagents that sends none, shows nothing" do
    for entry <- [subagent(%{}), Map.drop(subagent(%{}), [:ability_set, :ability_set_source])] do
      doc = render_entry(entry)

      assert texts(doc, ".subagent-name .badge") == []
      assert texts(doc, "#subagent-ability-set-parent-1-sub-1") == []
    end
  end
end
