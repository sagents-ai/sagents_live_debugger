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

  describe "utterance marker on content parts" do
    defp render_parts(parts) do
      %Message{role: :assistant, content: parts, status: :complete}
      |> render_message()
    end

    test "a narration part is badged and set apart" do
      doc = render_parts([ContentPart.narration!("Checking the logs.")])

      assert has_node?(doc, "[data-utterance='narration']")
      assert text(doc, ".utterance-badge") == "narration"
      assert text(doc, ".content-part-text") == "Checking the logs."
    end

    test "an answer part is badged as the answer" do
      doc = render_parts([ContentPart.answer!("Out of memory.")])

      assert has_node?(doc, "[data-utterance='answer']")
      assert text(doc, ".utterance-badge") == "answer"
    end

    test "an unmarked part carries no badge" do
      doc = render_parts([ContentPart.text!("Plain reply.")])

      refute has_node?(doc, ".utterance-badge")
      refute has_node?(doc, "[data-utterance]")
      assert text(doc, ".content-part-text") == "Plain reply."
    end

    test "a message holding both is labelled part by part, in order" do
      doc =
        render_parts([
          ContentPart.narration!("Checking the logs."),
          ContentPart.answer!("Out of memory.")
        ])

      badges =
        doc
        |> LazyHTML.query(".utterance-badge")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert badges == ["narration", "answer"]
    end

    test "a thinking block marked narration reads as a progress update" do
      part =
        %{type: :thinking, content: "Reading the events next."}
        |> ContentPart.new!()
        |> ContentPart.put_utterance("narration")

      doc = render_parts([part])

      assert text(doc, ".thinking-label") =~ "Progress update"
      assert has_node?(doc, ".content-part-thinking[data-utterance='narration']")
    end

    test "an unmarked thinking block still reads as thinking" do
      doc = render_parts([ContentPart.thinking!("Working through it.")])

      assert text(doc, ".thinking-label") =~ "Thinking"
      refute has_node?(doc, ".content-part-thinking[data-utterance]")
    end
  end

  describe "part_utterance/1" do
    # The parts reaching these components are not always structs: state
    # restored from a store arrives as plain maps, and its options may be a
    # keyword list or a string-keyed map depending on where it came from.

    test "reads a ContentPart through its own accessor" do
      assert MessageComponents.part_utterance(ContentPart.narration!("x")) == "narration"
      assert MessageComponents.part_utterance(ContentPart.answer!("x")) == "answer"
      assert MessageComponents.part_utterance(ContentPart.text!("x")) == nil
    end

    test "reads a plain map with keyword options" do
      part = %{type: :text, content: "x", options: [utterance: "narration"]}
      assert MessageComponents.part_utterance(part) == "narration"
    end

    test "reads a plain map with string-keyed map options" do
      part = %{type: :text, content: "x", options: %{"utterance" => "answer"}}
      assert MessageComponents.part_utterance(part) == "answer"
    end

    test "returns nil for options it cannot read, rather than raising" do
      for options <- [nil, [], ["not", "a", "keyword", "list"], %{}, "nonsense"] do
        part = %{type: :text, content: "x", options: options}
        assert MessageComponents.part_utterance(part) == nil
      end
    end

    test "returns nil for an unrecognized marker value" do
      part = %{type: :text, content: "x", options: [utterance: "something_new"]}
      assert MessageComponents.part_utterance(part) == nil
    end

    test "returns nil for a non-map" do
      assert MessageComponents.part_utterance("just text") == nil
      assert MessageComponents.part_utterance(nil) == nil
    end
  end

  describe "text previews" do
    test "previews the answer, not the preamble in front of it" do
      parts = [
        ContentPart.narration!("Checking the deployment status and events now."),
        ContentPart.answer!("The image tag does not exist.")
      ]

      assert MessageComponents.extract_text_preview(parts) == "The image tag does not exist."
      assert MessageComponents.extract_content_preview(parts) == "The image tag does not exist."
    end

    test "a message that is only narration says so rather than looking empty" do
      parts = [ContentPart.narration!("Reading the events next.")]

      assert MessageComponents.extract_text_preview(parts) ==
               "(narration) Reading the events next."

      assert MessageComponents.extract_content_preview(parts) ==
               "(narration) Reading the events next."
    end

    test "unmarked parts preview as they always did" do
      assert MessageComponents.extract_text_preview([ContentPart.text!("Plain reply.")]) ==
               "Plain reply."

      assert MessageComponents.extract_content_preview([ContentPart.text!("Plain reply.")]) ==
               "Plain reply."
    end

    test "a string content previews directly" do
      assert MessageComponents.extract_content_preview("Just a string.") == "Just a string."
    end

    test "non-text parts are skipped" do
      parts = [ContentPart.thinking!("reasoning"), ContentPart.answer!("Done.")]

      assert MessageComponents.extract_text_preview(parts) == "Done."
      assert MessageComponents.extract_content_preview(parts) == "Done."
    end

    test "nothing previewable yields an empty string" do
      assert MessageComponents.extract_text_preview([]) == ""
      assert MessageComponents.extract_content_preview([]) == ""
      assert MessageComponents.extract_text_preview(nil) == ""
    end

    test "previews are truncated" do
      long = String.duplicate("a", 200)

      assert String.length(MessageComponents.extract_text_preview([ContentPart.text!(long)])) ==
               50

      assert String.length(MessageComponents.extract_content_preview([ContentPart.text!(long)])) ==
               100
    end
  end
end
