defmodule SagentsLiveDebugger.UserRequests do
  @moduledoc """
  Reads user request data for display: the request number a message was
  produced under, the tokens it used, and the `:user_request_started` and
  `:user_request_completed` events.

  A user request is one human message and all the work done for it. Sagents
  versions that track them stamp each message's `metadata[:user_request_seq]`,
  keep the current number in `Sagents.State.user_request_seq`, and broadcast
  the two events. Older versions do none of this, so every read here tolerates
  the key, field or event being absent and returns `nil` in that case. Callers
  render nothing for `nil`.
  """

  @doc """
  Returns the user request number a message was produced under, or `nil`.
  """
  @spec seq(map()) :: pos_integer() | nil
  def seq(message), do: positive_integer(metadata_value(message, :user_request_seq))

  @doc """
  Returns the current user request number held by an agent state, or `nil`
  when no request has started or the state has no such field.
  """
  @spec current_seq(map() | nil) :: pos_integer() | nil
  def current_seq(%{} = state), do: positive_integer(Map.get(state, :user_request_seq))
  def current_seq(_state), do: nil

  @doc """
  Returns true when a message is a summary that replaced older history.
  """
  @spec summary?(map()) :: boolean()
  def summary?(message), do: metadata_value(message, :summary) == true

  @doc """
  Returns `%{input: integer, output: integer}` for the tokens a message used,
  or `nil`. `:subagent_usage` reads the usage a sub-agent spent on a `task`
  tool message instead.
  """
  @spec usage(map(), :usage | :subagent_usage) ::
          %{input: non_neg_integer(), output: non_neg_integer()} | nil
  def usage(message, key \\ :usage) when key in [:usage, :subagent_usage],
    do: usage_counts(metadata_value(message, key))

  @doc """
  Pairs each message with its index and the user request number to show a
  divider for: the number when it differs from the last one seen, else `nil`.
  Messages with no number never open a divider.
  """
  @spec with_dividers([map()]) :: [{map(), non_neg_integer(), pos_integer() | nil}]
  def with_dividers(messages) do
    {items, _last_seq} =
      messages
      |> Enum.with_index()
      |> Enum.map_reduce(nil, fn {message, index}, last_seq ->
        case seq(message) do
          nil -> {{message, index, nil}, last_seq}
          ^last_seq -> {{message, index, nil}, last_seq}
          seq -> {{message, index, seq}, seq}
        end
      end)

    items
  end

  @doc """
  Formats a user request event for the event stream, or returns `nil` for any
  other event.

  The map carries the `:type` and `:summary` every event has. A completed
  request adds `:status`, `:assistant_message_count` and `:tool_calls_label`,
  and `:input`/`:output` when its token usage is known.
  """
  @spec format_event(term()) :: map() | nil
  def format_event({:user_request_started, info}) do
    seq = map_value(info, :seq)

    %{type: "user_request_started", seq: seq, summary: "User request ##{seq || "?"} started"}
  end

  def format_event({:user_request_completed, report}) do
    seq = map_value(report, :seq)
    status = map_value(report, :status)

    base = %{
      type: "user_request_completed",
      seq: seq,
      status: status,
      assistant_message_count: map_value(report, :assistant_message_count),
      tool_calls_label: tool_calls_label(map_value(report, :tool_calls)),
      summary: "User request ##{seq || "?"} #{status || "finished"}"
    }

    case usage_counts(map_value(report, :token_usage)) do
      nil -> base
      counts -> Map.merge(base, counts)
    end
  end

  def format_event(_event), do: nil

  defp tool_calls_label(tool_calls) when is_map(tool_calls) and map_size(tool_calls) > 0 do
    tool_calls
    |> Enum.sort()
    |> Enum.map_join(", ", fn {name, count} -> "#{name} ×#{count}" end)
  end

  defp tool_calls_label(_tool_calls), do: "none"

  # Matches `LangChain.TokenUsage` and any map with the same keys.
  defp usage_counts(%{input: input, output: output})
       when is_integer(input) or is_integer(output),
       do: %{input: input || 0, output: output || 0}

  defp usage_counts(_usage), do: nil

  defp metadata_value(%{metadata: %{} = metadata}, key), do: Map.get(metadata, key)
  defp metadata_value(_message, _key), do: nil

  defp map_value(%{} = map, key), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil
end
