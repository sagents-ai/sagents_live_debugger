defmodule SagentsLiveDebugger.Live.Components.MessageComponentsTest do
  use ExUnit.Case, async: true

  alias SagentsLiveDebugger.Live.Components.MessageComponents
  alias Sagents.MiddlewareEntry

  describe "inspect_for_display/1" do
    test "produces small output for small values" do
      result = MessageComponents.inspect_for_display(%{a: 1, b: 2})
      assert is_binary(result)
      assert byte_size(result) < 100
    end

    test "bounds output for large structures (the safety net)" do
      # A 10,000-element map would inspect to many KB with limit: :infinity.
      # The bounded defaults must keep the output to a few KB.
      huge_map = for i <- 1..10_000, into: %{}, do: {"key_#{i}", "value_#{i}"}

      result = MessageComponents.inspect_for_display(huge_map)

      # Bounded output should be well under 25KB even for a 10k-entry map.
      assert byte_size(result) < 25_000,
             "expected bounded output, got #{byte_size(result)} bytes"
    end

    test "bounds output for huge strings" do
      huge_string = String.duplicate("x", 100_000)
      result = MessageComponents.inspect_for_display(huge_string)
      # printable_limit is 16_384, plus quoting/ellipsis overhead. Allow some slack.
      assert byte_size(result) < 20_000
    end
  end

  describe "display_config/1" do
    defmodule FakeSummaryMiddleware do
      @moduledoc false
      # Pretends to be a Sagents.Middleware that exposes a slim debug_summary.
      def debug_summary(config) do
        %{
          summary_line: "compact representation of middleware",
          item_count: map_size(config[:big_map] || %{})
        }
      end
    end

    defmodule FakeStringSummaryMiddleware do
      @moduledoc false
      def debug_summary(_config), do: "single string summary"
    end

    defmodule FakePlainMiddleware do
      @moduledoc false
      # No debug_summary/1 — exercises the fallback path.
    end

    test "uses module.debug_summary/1 when exported and returns a map" do
      entry = %MiddlewareEntry{
        id: :fake,
        module: FakeSummaryMiddleware,
        config: %{big_map: %{a: 1, b: 2, c: 3}}
      }

      assert {:map, summary} = MessageComponents.display_config(entry)
      assert summary.summary_line == "compact representation of middleware"
      assert summary.item_count == 3
      # The raw config (with :big_map) is NOT surfaced
      refute Map.has_key?(summary, :big_map)
    end

    test "uses module.debug_summary/1 when it returns a string" do
      entry = %MiddlewareEntry{
        id: :fake_string,
        module: FakeStringSummaryMiddleware,
        config: %{}
      }

      assert {:string, "single string summary"} = MessageComponents.display_config(entry)
    end

    test "falls back to raw config when debug_summary/1 is not exported" do
      entry = %MiddlewareEntry{
        id: :plain,
        module: FakePlainMiddleware,
        config: %{key: "value", agent_id: "internal", model: %{should: "be dropped"}}
      }

      assert {:map, displayed} = MessageComponents.display_config(entry)
      # agent_id and model are dropped (handled separately in the UI)
      refute Map.has_key?(displayed, :agent_id)
      refute Map.has_key?(displayed, :model)
      # Other keys survive
      assert displayed.key == "value"
    end

    test "drops agent_id/model from debug_summary results too" do
      defmodule FakeOverreachMiddleware do
        @moduledoc false
        def debug_summary(_config) do
          %{agent_id: "leaked", model: "leaked", real_data: "kept"}
        end
      end

      entry = %MiddlewareEntry{
        id: :overreach,
        module: FakeOverreachMiddleware,
        config: %{}
      }

      assert {:map, summary} = MessageComponents.display_config(entry)
      refute Map.has_key?(summary, :agent_id)
      refute Map.has_key?(summary, :model)
      assert summary.real_data == "kept"
    end
  end
end
