# Sagents Live Debugger

A Phoenix LiveView dashboard for debugging and monitoring LangChain agents in real-time. Provides visibility into agent execution, message history, tool calls, middleware actions, todos, and event streams.

## Features

- **Real-time Agent Monitoring**: View all running agents with status, uptime, and viewer counts
- **Message Inspection**: Browse complete message history with tool calls, results, and thinking blocks
- **Event Stream**: Live feed of agent events (LLM calls, middleware actions, tool executions)
- **Todo Tracking**: Monitor agent task lists and progress in real-time
- **Timezone Localization**: Automatically displays timestamps in your browser's timezone

## Installation

Add `sagents_live_debugger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sagents_live_debugger, "~> 0.1.0"}
  ]
end
```

## Setup

Add the debugger to your Phoenix router:

```elixir
# lib/my_app_web/router.ex
import SagentsLiveDebugger.Router

scope "/dev" do
  pipe_through :browser

  sagents_live_debugger "/debug/agents",
    coordinator: MyApp.Agents.Coordinator
end
```

**Important:** Ensure your application has configured the timezone database in `config/config.exs`:

```elixir
# config/config.exs
import Config

# Required for timezone support
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
```

That's it! Visit `http://localhost:4000/dev/debug/agents` to access the debugger.

## Configuration Options

The `sagents_live_debugger` macro accepts the following options:

### Required

- `:coordinator` - Your application's agent coordinator module (implements coordinator behavior)

### Optional

- `:presence_module` - Phoenix Presence module for real-time viewer tracking (defaults to polling if not provided)

### Example with All Options

```elixir
sagents_live_debugger "/debug/agents",
  coordinator: MyApp.Agents.Coordinator,
  presence_module: MyApp.Presence
```

## Timezone Display

The debugger automatically detects your browser's timezone and displays all timestamps in your local time. If timezone detection fails, UTC is used as a fallback.

Timestamps are displayed in the format: `HH:MM:SS TZ` (e.g., `14:32:15 EST`)

**No configuration required** - timezone detection works automatically via JavaScript.

## Architecture Notes

### Plugin Design

The debugger is designed as a self-contained plugin library:
- No JavaScript files to compile or bundle
- All CSS is inlined in the layout
- All JavaScript is inlined for timezone detection
- Zero configuration beyond adding to router

### Event-Driven Updates

- **List View**: Polls every 2 seconds + subscribes to presence changes
- **Detail View**: Fully event-driven via PubSub (no polling)
  - `status_changed` events update agent status
  - `todos_updated` events refresh the TODOs tab
  - `llm_message` events update the Messages tab
  - All events are added to the Events stream

## Browser Compatibility

The timezone detection feature uses `Intl.DateTimeFormat().resolvedOptions().timeZone`, which is supported in:
- Chrome/Edge 24+
- Firefox 52+
- Safari 10+

Older browsers will gracefully fall back to displaying timestamps in UTC.

## License

Copyright (c) 2025

