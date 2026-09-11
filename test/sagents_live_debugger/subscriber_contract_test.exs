defmodule SagentsLiveDebugger.SubscriberContractTest do
  @moduledoc """
  The return shapes `AgentListLive` matches on when it routes inbound
  `presence_diff` and `:DOWN` messages through `Sagents.Subscriber`.

  Both functions can also name the subscription that changed, but only under
  `report: true`, which changes the shape. The debugger rebuilds its whole
  agent list from presence on every diff, so it never asks, and its
  `handle_info` clauses match the bare shapes. A mismatch here is invisible at
  compile time and surfaces as a `MatchError` inside a live LiveView.
  """
  use ExUnit.Case, async: true

  alias Sagents.Subscriber

  describe "handle_presence_diff/3 without report:" do
    test "returns the subs map itself, not a {subs, revived} tuple" do
      subs = %{}
      payload = %{joins: %{}, leaves: %{}}

      assert ^subs = Subscriber.handle_presence_diff(subs, "some:other:topic", payload)
    end
  end

  describe "handle_publisher_down/3 without report:" do
    test "returns :no_match for a ref we are not holding" do
      assert :no_match = Subscriber.handle_publisher_down(%{}, make_ref(), :normal)
    end
  end
end
