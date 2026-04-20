defmodule SagentsLiveDebugger.Timezone do
  @moduledoc """
  Helpers for validating IANA timezone strings received from the browser.

  The debugger passes the browser's detected timezone (from
  `Intl.DateTimeFormat().resolvedOptions().timeZone`) through the LiveSocket
  `connect_params` as `"time_zone"`. This module ensures that only valid zones
  known to `Tzdata` make it into socket state, so downstream
  `DateTime.shift_zone/3` calls cannot crash when rendering event timestamps.
  """

  @doc """
  Validates a timezone string against `Tzdata.TimeZoneDatabase`.

  Returns `{:ok, timezone}` for recognized zones, `{:error, :invalid_timezone}`
  otherwise (including for `nil` or non-binary input).
  """
  @spec validate(any()) :: {:ok, String.t()} | {:error, :invalid_timezone}
  def validate(timezone) when is_binary(timezone) do
    case DateTime.shift_zone(DateTime.utc_now(), timezone, Tzdata.TimeZoneDatabase) do
      {:ok, _} -> {:ok, timezone}
      {:error, _} -> {:error, :invalid_timezone}
    end
  end

  def validate(_), do: {:error, :invalid_timezone}

  @doc """
  Validates a timezone and falls back to `"UTC"` on any failure.
  """
  @spec validate_or_utc(any()) :: String.t()
  def validate_or_utc(timezone) do
    case validate(timezone) do
      {:ok, tz} -> tz
      {:error, _} -> "UTC"
    end
  end
end
