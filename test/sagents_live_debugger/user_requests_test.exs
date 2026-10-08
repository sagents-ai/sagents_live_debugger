defmodule SagentsLiveDebugger.UserRequestsTest do
  use ExUnit.Case, async: true

  alias LangChain.Message
  alias LangChain.TokenUsage
  alias SagentsLiveDebugger.UserRequests

  defp message(metadata), do: %Message{role: :assistant, content: "Hi", metadata: metadata}

  describe "reading a message" do
    test "returns the request number, summary flag and usage it carries" do
      message =
        message(%{
          user_request_seq: 3,
          summary: true,
          usage: %TokenUsage{input: 120, output: 40},
          subagent_usage: %TokenUsage{input: 900, output: 75}
        })

      assert UserRequests.seq(message) == 3
      assert UserRequests.summary?(message)
      assert UserRequests.usage(message) == %{input: 120, output: 40}
      assert UserRequests.usage(message, :subagent_usage) == %{input: 900, output: 75}
    end

    test "returns nothing for a message from a sagents version that records none of it" do
      for message <- [message(%{}), message(nil), %{role: :user}] do
        assert UserRequests.seq(message) == nil
        refute UserRequests.summary?(message)
        assert UserRequests.usage(message) == nil
        assert UserRequests.usage(message, :subagent_usage) == nil
      end
    end

    test "treats request number 0 as no request" do
      assert UserRequests.seq(message(%{user_request_seq: 0})) == nil
    end
  end

  describe "current_seq/1" do
    test "reads the state's current number" do
      assert UserRequests.current_seq(%{messages: [], user_request_seq: 2}) == 2
    end

    test "returns nil for a state without the field, before a request, or with no state" do
      assert UserRequests.current_seq(%{messages: []}) == nil
      assert UserRequests.current_seq(%{user_request_seq: 0}) == nil
      assert UserRequests.current_seq(nil) == nil
    end
  end

  describe "with_dividers/1" do
    test "opens a divider where the request number changes, and nowhere else" do
      messages = [
        %Message{role: :system, content: "sys", metadata: %{}},
        message(%{user_request_seq: 1}),
        message(%{user_request_seq: 1}),
        message(%{user_request_seq: 2})
      ]

      assert Enum.map(UserRequests.with_dividers(messages), fn {_m, i, d} -> {i, d} end) ==
               [{0, nil}, {1, 1}, {2, nil}, {3, 2}]
    end

    test "opens none for messages that carry no number" do
      messages = [message(%{}), message(%{})]

      assert Enum.map(UserRequests.with_dividers(messages), &elem(&1, 2)) == [nil, nil]
    end
  end

  describe "format_event/1" do
    test "summarizes a started request" do
      assert %{type: "user_request_started", seq: 4, summary: "User request #4 started"} =
               UserRequests.format_event({:user_request_started, %{seq: 4}})
    end

    test "summarizes a completed request with its status, counts and usage" do
      report = %{
        seq: 4,
        status: :completed,
        assistant_message_count: 3,
        tool_calls: %{"search" => 2, "read_file" => 1},
        token_usage: %TokenUsage{input: 500, output: 60}
      }

      assert %{
               type: "user_request_completed",
               summary: "User request #4 completed",
               status: :completed,
               assistant_message_count: 3,
               tool_calls_label: "read_file ×1, search ×2",
               input: 500,
               output: 60
             } = UserRequests.format_event({:user_request_completed, report})
    end

    test "omits token counts when the report has no usage" do
      event =
        UserRequests.format_event(
          {:user_request_completed, %{seq: 1, status: :cancelled, tool_calls: %{}}}
        )

      assert event.tool_calls_label == "none"
      refute Map.has_key?(event, :input)
    end

    test "tolerates a report missing fields" do
      assert %{summary: "User request #? finished"} =
               UserRequests.format_event({:user_request_completed, %{}})
    end

    test "returns nil for any other event" do
      assert UserRequests.format_event({:todos_updated, []}) == nil
    end
  end
end
