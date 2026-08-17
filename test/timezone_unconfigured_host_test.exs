defmodule SagentsLiveDebugger.TimezoneUnconfiguredHostTest do
  # Swaps the global Calendar time zone database, so this module cannot share
  # the scheduler with the async tests that read the configured one.
  use ExUnit.Case, async: false

  alias SagentsLiveDebugger.Timezone

  setup do
    configured = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(configured) end)
    :ok
  end

  describe "host application with no time zone database configured" do
    test "validate/1 rejects real zones rather than raising" do
      assert {:error, :invalid_timezone} = Timezone.validate("America/New_York")
      assert {:error, :invalid_timezone} = Timezone.validate("Asia/Tokyo")
    end

    test "validate_or_utc/1 lands on UTC for every browser zone" do
      assert "UTC" = Timezone.validate_or_utc("America/New_York")
      assert "UTC" = Timezone.validate_or_utc("Europe/London")
      assert "UTC" = Timezone.validate_or_utc("Not/A/Zone")
    end

    test "the UTC zone the socket falls back to still renders" do
      # Only "Etc/UTC" resolves under Calendar.UTCOnlyTimeZoneDatabase, so the
      # "UTC" that lands in socket state takes the timestamp formatter's error
      # branch, which labels the value UTC without shifting it.
      dt = ~U[2025-01-03 14:32:15Z]

      assert {:error, :utc_only_time_zone_database} = DateTime.shift_zone(dt, "UTC")

      assert "14:32:15 UTC" =
               dt |> DateTime.truncate(:second) |> Calendar.strftime("%H:%M:%S UTC")
    end
  end
end
