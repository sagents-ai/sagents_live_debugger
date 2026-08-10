import Config

if Mix.env() == :test do
  config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
end
