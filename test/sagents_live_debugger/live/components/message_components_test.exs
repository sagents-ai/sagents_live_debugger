defmodule SagentsLiveDebugger.Live.Components.MessageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LangChain.LangChainError
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolResult
  alias SagentsLiveDebugger.Live.Components.MessageComponents
  alias Sagents.MiddlewareEntry

  describe "message_item/1 stop status" do
    test "a finished message keeps its complete badge and shows no note" do
      doc = render_message(assistant("All done.", status: :complete))

      assert has_node?(doc, ".message-status.status-complete")
      refute has_node?(doc, ".message-stop-note")
    end

    test "hitting the output cap badges the status verbatim" do
      doc = render_message(assistant("Half a th", status: :length))

      assert has_node?(doc, ".message-status.status-length")
      # The badge names the atom a developer matches on in their own code.
      assert text(doc, ".message-status") == "length"
    end

    test "the badge text is the status value for every stop reason" do
      for status <- [:complete, :cancelled, :length, :content_filtered, :stream_error] do
        doc = render_message(assistant("Text", status: status))
        assert text(doc, ".message-status") == to_string(status)
      end
    end

    test "a caller-initiated stop badges as cancelled with no note" do
      doc = render_message(assistant("Partial.", status: :cancelled))

      assert has_node?(doc, ".message-status.status-cancelled")
      refute has_node?(doc, ".message-stop-note")
    end

    test "a filtered response names the provider's category and explanation" do
      doc =
        render_message(
          assistant("",
            status: :content_filtered,
            metadata: %{
              stop_details: %{
                "type" => "refusal",
                "category" => "cyber",
                "explanation" => "Declined to produce exploit code."
              }
            }
          )
        )

      assert has_node?(doc, ".message-status.status-content_filtered")
      assert text(doc, ".message-stop-note") =~ "refusal / cyber"
      assert text(doc, ".message-stop-note") =~ "Declined to produce exploit code."
    end

    test "a dead stream badges as stream error and shows the error message" do
      error = LangChainError.exception(type: "overloaded", message: "Overloaded")

      doc =
        render_message(
          assistant("Cut off", status: :stream_error, metadata: %{streaming_error: error})
        )

      assert has_node?(doc, ".message-status.status-stream_error")
      assert text(doc, ".message-stop-note") == "Overloaded"
    end

    test "the pre-0.10.0 dead-stream shape badges as stream error, not cancelled" do
      # LangChain below 0.10.0 records a dead stream as :cancelled carrying the
      # error in metadata. Both shapes are one condition and must badge alike.
      error = LangChainError.exception(type: "overloaded", message: "Overloaded")

      doc =
        render_message(
          assistant("Cut off", status: :cancelled, metadata: %{streaming_error: error})
        )

      assert has_node?(doc, ".message-status.status-stream_error")
      refute has_node?(doc, ".message-status.status-cancelled")
    end

    test "the note sits outside the message body and the collapsed metadata block" do
      doc =
        render_message(
          assistant("",
            status: :content_filtered,
            metadata: %{stop_details: %{"type" => "refusal", "explanation" => "Declined."}}
          )
        )

      # Guard assertions: the containers the note must stay out of are present,
      # so the negative assertions below can fail for the right reason.
      assert has_node?(doc, ".message-content")
      assert has_node?(doc, "details.message-metadata")

      assert has_node?(doc, ".message-stop-note")
      refute has_node?(doc, ".message-content .message-stop-note")
      refute has_node?(doc, "details.message-metadata .message-stop-note")
    end
  end

  defp assistant(text, fields) do
    %Message{
      role: :assistant,
      content: [ContentPart.text!(text)],
      status: Keyword.fetch!(fields, :status),
      metadata: Keyword.get(fields, :metadata, %{})
    }
  end

  defp render_message(message) do
    render_component(&MessageComponents.message_item/1, message: message, index: 0)
    |> LazyHTML.from_fragment()
  end

  defp render_tool_result(tool_result) do
    render_component(&MessageComponents.tool_result_item/1, tool_result: tool_result)
    |> LazyHTML.from_fragment()
  end

  defp has_node?(doc, selector) do
    doc |> LazyHTML.query(selector) |> Enum.any?()
  end

  defp text(doc, selector) do
    doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
  end

  describe "tool_result_item/1 content" do
    test "shows the text the LLM received, not the ContentPart structs" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          name: "list_accounts",
          content: "Accounts:\n- #9 Anytime Checking: $714.71 balance"
        })

      html = render_component(&MessageComponents.tool_result_item/1, tool_result: result)
      doc = LazyHTML.from_fragment(html)

      assert text(doc, "pre.tool-result-text") =~ "Anytime Checking: $714.71 balance"
      refute html =~ "ContentPart"
      refute html =~ "%LangChain"
    end

    test "indents a JSON object and highlights it" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          content: ~s({"accounts":[{"id":9,"balance":714.71}]})
        })

      doc = render_tool_result(result)

      assert has_node?(doc, ".tool-result-content .highlighted-code")
      refute has_node?(doc, "pre.tool-result-text")

      shown = text(doc, ".tool-result-content")
      assert shown =~ ~r/\n\s+"accounts"/
      assert shown =~ "714.71"
    end

    test "keeps the key order the tool wrote" do
      result =
        ToolResult.new!(%{tool_call_id: "call-1", content: ~s({"zebra":1,"apple":2})})

      doc = render_tool_result(result)
      shown = text(doc, ".tool-result-content")

      assert shown =~ ~r/"zebra".*"apple"/s
    end

    test "a JSON-shaped string that does not parse stays plain text" do
      result = ToolResult.new!(%{tool_call_id: "call-1", content: "[broken, not json"})

      doc = render_tool_result(result)

      assert text(doc, "pre.tool-result-text") == "[broken, not json"
      refute has_node?(doc, ".tool-result-content .highlighted-code")
    end

    test "joins multiple text parts" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          content: [ContentPart.text!("first half"), ContentPart.text!("second half")]
        })

      assert text(render_tool_result(result), "pre.tool-result-text") ==
               "first half\n\nsecond half"
    end

    test "renders a non-text part through content_part/1" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          content: [ContentPart.image!("base64data", media: :png)]
        })

      doc = render_tool_result(result)

      assert has_node?(doc, ".tool-result-content .content-part-image")
      refute has_node?(doc, "pre.tool-result-text")
    end

    test "marks an empty result instead of rendering a blank block" do
      doc = render_tool_result(%ToolResult{tool_call_id: "call-1", content: nil})

      assert text(doc, ".tool-result-empty") == "(no content)"
      refute has_node?(doc, "pre.tool-result-text")
    end
  end

  describe "format_tool_result/1" do
    test "returns the joined text of a ContentPart list" do
      parts = [ContentPart.text!("one"), ContentPart.text!("two")]
      assert MessageComponents.format_tool_result(parts) == "one\n\ntwo"
    end

    test "indents JSON and leaves prose alone" do
      assert MessageComponents.format_tool_result(~s({"a":1})) == "{\n  \"a\": 1\n}"
      assert MessageComponents.format_tool_result("just prose") == "just prose"
    end
  end

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
