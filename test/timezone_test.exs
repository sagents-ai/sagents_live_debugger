defmodule SagentsLiveDebugger.TimezoneTest do
  use ExUnit.Case

  # We need to test private functions via a public wrapper
  # For now, we'll do a basic integration test

  describe "timezone functionality" do
    test "DateTime.shift_zone/2 works with valid timezones" do
      dt = ~U[2025-01-03 14:32:15Z]

      # Test shifting to New York (UTC-5 in winter)
      assert {:ok, shifted} = DateTime.shift_zone(dt, "America/New_York")
      assert shifted.hour == 9
      assert shifted.minute == 32

      # Test shifting to Tokyo (UTC+9)
      assert {:ok, shifted} = DateTime.shift_zone(dt, "Asia/Tokyo")
      assert shifted.hour == 23
      assert shifted.minute == 32
    end

    test "DateTime.shift_zone/2 handles invalid timezones" do
      dt = ~U[2025-01-03 14:32:15Z]

      assert {:error, _} = DateTime.shift_zone(dt, "Invalid/Timezone")
    end

    test "DateTime.shift_zone/2 works with UTC" do
      dt = ~U[2025-01-03 14:32:15Z]

      assert {:ok, shifted} = DateTime.shift_zone(dt, "UTC")
      assert shifted.hour == 14
      assert shifted.minute == 32
    end
  end
end
