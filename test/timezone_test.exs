defmodule SagentsLiveDebugger.TimezoneTest do
  use ExUnit.Case, async: true

  alias SagentsLiveDebugger.Timezone

  describe "validate/1" do
    test "accepts a valid IANA timezone" do
      assert {:ok, "America/New_York"} = Timezone.validate("America/New_York")
      assert {:ok, "Asia/Tokyo"} = Timezone.validate("Asia/Tokyo")
      assert {:ok, "UTC"} = Timezone.validate("UTC")
    end

    test "rejects an unknown timezone" do
      assert {:error, :invalid_timezone} = Timezone.validate("Invalid/Timezone")
      assert {:error, :invalid_timezone} = Timezone.validate("Not/A/Zone")
    end

    test "rejects non-binary input" do
      assert {:error, :invalid_timezone} = Timezone.validate(nil)
      assert {:error, :invalid_timezone} = Timezone.validate(123)
      assert {:error, :invalid_timezone} = Timezone.validate(:atom)
    end
  end

  describe "validate_or_utc/1" do
    test "returns the zone for valid input" do
      assert "Europe/London" = Timezone.validate_or_utc("Europe/London")
    end

    test "falls back to UTC for invalid, nil, or unknown input" do
      assert "UTC" = Timezone.validate_or_utc(nil)
      assert "UTC" = Timezone.validate_or_utc("Not/A/Zone")
      assert "UTC" = Timezone.validate_or_utc(42)
    end
  end

  describe "DateTime.shift_zone/3 sanity checks" do
    test "works with valid timezones" do
      dt = ~U[2025-01-03 14:32:15Z]

      assert {:ok, shifted} = DateTime.shift_zone(dt, "America/New_York", Tzdata.TimeZoneDatabase)
      assert shifted.hour == 9
      assert shifted.minute == 32

      assert {:ok, shifted} = DateTime.shift_zone(dt, "Asia/Tokyo", Tzdata.TimeZoneDatabase)
      assert shifted.hour == 23
      assert shifted.minute == 32
    end

    test "returns :error for invalid timezones" do
      dt = ~U[2025-01-03 14:32:15Z]
      assert {:error, _} = DateTime.shift_zone(dt, "Invalid/Timezone", Tzdata.TimeZoneDatabase)
    end

    test "works with UTC" do
      dt = ~U[2025-01-03 14:32:15Z]
      assert {:ok, shifted} = DateTime.shift_zone(dt, "UTC", Tzdata.TimeZoneDatabase)
      assert shifted.hour == 14
      assert shifted.minute == 32
    end
  end
end
