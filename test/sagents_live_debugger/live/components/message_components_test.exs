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

  describe "message_item/1 user request" do
    test "badges the request number, summary flag and token usage" do
      doc =
        render_message(
          assistant("Answer.",
            status: :complete,
            metadata: %{
              user_request_seq: 2,
              summary: true,
              usage: %LangChain.TokenUsage{input: 120, output: 40},
              subagent_usage: %LangChain.TokenUsage{input: 900, output: 75}
            }
          )
        )

      assert text(doc, ".message-badge-request") == "req #2"
      assert has_node?(doc, ".message-badge-summary")

      assert text(doc, ".message-usage-tokens:not(.message-usage-subagent) .token-input") ==
               "↑120"

      assert text(doc, ".message-usage-subagent .token-output") == "↓75"
    end

    test "renders none of it for a message that records none of it" do
      doc = render_message(assistant("Answer.", status: :complete))

      refute has_node?(doc, ".message-badge")
      refute has_node?(doc, ".message-usage")
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

  describe "tool_item/1 ability sets" do
    test "badges each set the tool belongs to" do
      tool = %{name: "list_devices", description: "Lists devices."}

      doc =
        render_component(&MessageComponents.tool_item/1,
          tool: tool,
          ability_sets: ["devices", "ops"]
        )
        |> LazyHTML.from_fragment()

      assert doc |> LazyHTML.query(".badge-ability-set") |> Enum.map(&LazyHTML.text/1) ==
               ["devices", "ops"]
    end

    test "shows no set badge by default" do
      doc =
        render_component(&MessageComponents.tool_item/1, tool: %{name: "lookup"})
        |> LazyHTML.from_fragment()

      refute has_node?(doc, ".badge-ability-set")
    end
  end

  describe "tool_item/1 tool search" do
    defp render_tool(tool, opts \\ []) do
      render_component(&MessageComponents.tool_item/1, Keyword.merge([tool: tool], opts))
      |> LazyHTML.from_fragment()
    end

    defp deferred_function(name, options \\ []) do
      LangChain.Function.new!(%{
        name: name,
        description: "Tool #{name}",
        parameters_schema: %{
          "type" => "object",
          "properties" => %{"site" => %{"type" => "string", "description" => "hq or warehouse"}},
          "required" => ["site"]
        },
        options:
          Keyword.merge(
            [defer_loading: true, namespace: "devices", namespace_description: "Devices."],
            options
          ),
        function: fn _args, _context -> {:ok, "ok"} end
      })
    end

    test "the search tool is badged as a provider tool and described, with its variant" do
      doc = render_tool(LangChain.NativeTool.tool_search(variant: :regex))

      assert text(doc, ".badge-provider-tool") == "Provider tool"
      assert text(doc, ".list-item-description") =~ "search for deferred tools"
      refute text(doc, ".list-item-description") =~ "No description available"
      assert text(doc, ".list-item-details") =~ "regex"
    end

    test "any other provider tool is badged and shows its configuration" do
      tool =
        LangChain.NativeTool.new!(%{name: "google_search", configuration: %{"mode" => "dynamic"}})

      doc = render_tool(tool)

      assert text(doc, ".badge-provider-tool") == "Provider tool"
      assert text(doc, ".list-item-details") =~ "dynamic"
    end

    test "a deferred function is badged with its namespace" do
      doc = render_tool(deferred_function("devices_list"))

      assert text(doc, ".badge-deferred") == "Deferred"
      assert text(doc, ".badge-namespace") == "devices"
      refute has_node?(doc, ".badge-loaded")
      refute has_node?(doc, ".badge-not-loaded")
    end

    test "a deferred function is marked loaded or not loaded against the conversation" do
      loaded = MapSet.new(["devices_list"])

      assert has_node?(
               render_tool(deferred_function("devices_list"), loaded: loaded),
               ".badge-loaded"
             )

      assert has_node?(
               render_tool(deferred_function("devices_get"), loaded: loaded),
               ".badge-not-loaded"
             )
    end

    test "a visible function has no deferral badges, even when the set is given" do
      tool = deferred_function("whoami", defer_loading: false, namespace: nil)
      doc = render_tool(tool, loaded: MapSet.new())

      refute has_node?(doc, ".badge-deferred")
      refute has_node?(doc, ".badge-not-loaded")
    end

    test "a function defined by a JSON schema lists its parameters" do
      doc = render_tool(deferred_function("devices_list"))

      assert text(doc, ".list-item-details") =~ "site"
      assert text(doc, ".list-item-details") =~ "hq or warehouse"
      assert has_node?(doc, ".badge-required")
    end
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

  describe "tool_result_item/1 outcome" do
    test "badges a failed result as an error" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          name: "get_weather",
          content: "Missing required argument: city",
          is_error: true
        })

      doc = render_tool_result(result)

      assert has_node?(doc, ".tool-result.tool-result-error")
      assert text(doc, ".result-status.status-error") == "ERROR"
      assert text(doc, ".tool-name") =~ "❌"
      refute text(doc, ".tool-name") =~ "✅"
    end

    test "a successful result carries no error badge" do
      result = ToolResult.new!(%{tool_call_id: "call-1", name: "get_weather", content: "Sunny"})

      doc = render_tool_result(result)

      refute has_node?(doc, ".tool-result-error")
      refute has_node?(doc, ".status-error")
      assert text(doc, ".tool-name") =~ "✅"
    end

    test "an interrupt is badged as interrupted rather than as an error" do
      result =
        ToolResult.new!(%{
          tool_call_id: "call-1",
          name: "delete_file",
          content: "Awaiting approval",
          is_interrupt: true
        })

      doc = render_tool_result(result)

      assert text(doc, ".result-status.status-interrupted") == "INTERRUPTED"
      refute has_node?(doc, ".status-error")
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

  describe "provider items on content parts" do
    # A literal rather than `ContentPart.provider_item!/2`, which has no way to
    # set `content`: a streamed Anthropic search call carries its input there.
    defp provider_item(provider, item, content \\ nil),
      do: %ContentPart{
        type: :provider_item,
        content: content,
        options: [provider: provider, item: item]
      }

    # As a streamed Anthropic search arrives: the query is JSON text in
    # `content`, and the item's `"input"` is still empty.
    @streamed_search_call %{
      "id" => "srvtoolu_01XSZbUuFkZmaRdAMeY41XBS",
      "input" => %{},
      "name" => "tool_search_tool_bm25",
      "type" => "server_tool_use"
    }

    @search_result %{
      "content" => %{
        "tool_references" => [
          %{"tool_name" => "devices_list", "type" => "tool_reference"},
          %{"tool_name" => "devices_restart", "type" => "tool_reference"}
        ],
        "type" => "tool_search_tool_search_result"
      },
      "tool_use_id" => "srvtoolu_01XSZbUuFkZmaRdAMeY41XBS",
      "type" => "tool_search_tool_result"
    }

    defp chips(doc),
      do:
        doc
        |> LazyHTML.query(".provider-item-chip")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    test "a streamed Anthropic search call shows its query, decoded from the part's content" do
      doc =
        render_parts([
          provider_item(
            "anthropic",
            @streamed_search_call,
            ~s({"query": "list devices at a site"})
          )
        ])

      assert has_node?(doc, ".content-part-provider-item[data-search='call']")
      assert text(doc, ".provider-item-label") =~ "Tool search"
      assert text(doc, ".provider-item-query") =~ "list devices at a site"
      assert text(doc, ".badge-provider") == "anthropic"
      assert text(doc, ".provider-item-type") == "server_tool_use"
      refute has_node?(doc, ".content-part-unknown")

      # The raw item, as it goes back to the provider, carries the decoded input.
      assert text(doc, ".provider-item-raw") =~ "list devices at a site"
    end

    test "an Anthropic search result lists the tools it loaded" do
      doc = render_parts([provider_item("anthropic", @search_result)])

      assert has_node?(doc, ".content-part-provider-item[data-search='result']")
      assert text(doc, ".provider-item-label") =~ "Tools loaded"
      assert chips(doc) == ["devices_list", "devices_restart"]
    end

    test "a search that found nothing says so" do
      empty = put_in(@search_result, ["content", "tool_references"], [])
      doc = render_parts([provider_item("anthropic", empty)])

      assert text(doc, ".provider-item-label") =~ "found nothing"
      refute has_node?(doc, ".provider-item-chips")
    end

    test "a failed search is marked as an error with its code" do
      error = %{
        "type" => "tool_search_tool_result",
        "tool_use_id" => "srvtoolu_1",
        "content" => %{"type" => "tool_search_tool_result_error", "error_code" => "unavailable"}
      }

      doc = render_parts([provider_item("anthropic", error)])

      assert has_node?(doc, ".content-part-provider-item[data-search='error']")
      assert text(doc, ".provider-item-label") =~ "Tool search failed: unavailable"
    end

    test "an OpenAI search shows the paths it looked up, then its namespaces and tools" do
      call = %{
        "type" => "tool_search_call",
        "id" => "tsc_1",
        "execution" => "server",
        "call_id" => nil,
        "status" => "completed",
        "arguments" => %{"paths" => ["devices"]}
      }

      output = %{
        "type" => "tool_search_output",
        "id" => "tso_1",
        "tools" => [
          %{
            "type" => "namespace",
            "name" => "devices",
            "tools" => [%{"type" => "function", "name" => "devices_list"}]
          },
          %{"type" => "function", "name" => "billing_invoices"}
        ]
      }

      doc = render_parts([provider_item("openai", call), provider_item("openai", output)])

      assert text(doc, ".provider-item-query") =~ "devices"
      assert chips(doc) == ["devices", "devices_list", "billing_invoices"]
      assert has_node?(doc, ".provider-item-namespace")
    end

    test "any other provider item is labelled and keeps its raw view" do
      web_search = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "srvtoolu_2",
        "content" => []
      }

      doc = render_parts([provider_item("anthropic", web_search)])

      assert text(doc, ".provider-item-label") =~ "Provider item"
      assert text(doc, ".provider-item-type") == "web_search_tool_result"
      assert has_node?(doc, ".provider-item-raw")
    end

    test "a tool result holding tool references names each tool" do
      result = %ToolResult{
        type: :function,
        tool_call_id: "call_load",
        name: "load_tools",
        content: [ContentPart.tool_reference!("billing_invoices")]
      }

      doc = render_tool_result(result)

      assert has_node?(doc, ".content-part-tool-reference")
      assert text(doc, ".content-part-tool-reference .provider-item-chip") == "billing_invoices"
      refute has_node?(doc, ".content-part-unknown")
    end
  end

  describe "part_utterance/1" do
    test "reads a ContentPart struct" do
      assert MessageComponents.part_utterance(ContentPart.narration!("x")) == "narration"
      assert MessageComponents.part_utterance(ContentPart.answer!("x")) == "answer"
      assert MessageComponents.part_utterance(ContentPart.text!("x")) == nil
    end

    test "returns nil for an unrecognized marker value" do
      part = %ContentPart{type: :text, content: "x", options: [utterance: "something_new"]}
      assert MessageComponents.part_utterance(part) == nil
    end

    test "returns nil for anything that is not a ContentPart" do
      assert MessageComponents.part_utterance(%{type: :text, options: [utterance: "narration"]}) ==
               nil

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
