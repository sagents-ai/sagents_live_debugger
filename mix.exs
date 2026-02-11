defmodule SagentsLiveDebugger.MixProject do
  use Mix.Project

  @source_url "https://github.com/sagents-ai/sagents_live_debugger"
  @version "0.1.0"

  def project do
    [
      app: :sagents_live_debugger,
      version: @version,
      elixir: "~> 1.17",
      test_options: [docs: true],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      # docs: docs(),
      name: "Sagents LiveDebugger",
      homepage_url: @source_url,
      description: "A Phoenix LiveView dashboard for debugging and monitoring Sagents agents in real-time."
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:sagents, "~> 0.1.0"},
      # markdown and code highlighting (autumn)
      {:mdex, "~> 0.11.0"},
      {:autumn, "~> 0.6"},
      {:tzdata, "~> 1.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, before performing a commit, run the following checks:
  #
  #     $ mix precommit
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        ".formatter.exs",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ],
      maintainers: ["Mark Ericksen"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
