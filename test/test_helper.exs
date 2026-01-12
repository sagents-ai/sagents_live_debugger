# Configure timezone database for tests
Application.put_env(:elixir, :time_zone_database, Tzdata.TimeZoneDatabase)

ExUnit.start()
