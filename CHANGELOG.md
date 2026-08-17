# Changelog

## v0.5.0

Renders the `:length`, `:content_filtered` and `:stream_error` message statuses
added in `sagents` v0.12.1 and `langchain` v0.10.0. The debugger interpolates the
status atom into a class name, so each new value produced a class that matched no
CSS rule and the badge rendered unstyled.

**Breaking:** the `sagents` requirement moves from `~> 0.8` to `~> 0.12`.

### Upgrading from v0.4.1 - v0.5.0

Upgrade `sagents` to `~> 0.12` in your host application. The router macro and its
options are unchanged.

### Added
- Badge coloring for the `:length`, `:content_filtered` and `:stream_error` message statuses, plus a tooltip naming what each status means [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)
- A stop note between a message's header and body carrying the provider's description of the cause, from `stop_details` or `streaming_error` [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)

### Changed
- **Breaking:** `sagents` requirement raised from `~> 0.8` to `~> 0.12` [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)
- Status badges resolve through `DisplayHelpers.stop_reason/1`, so a dead stream badges alike on either side of the `langchain` v0.10.0 status split [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)
- `:cancelled` badges neutral gray, reserving red for `:stream_error` [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)
- Added `lazy_html` as a test-only dependency [#39](https://github.com/sagents-ai/sagents_live_debugger/pull/39)

## v0.4.1

Widens the `sagents` dependency constraint from `~> 0.8.0` to `~> 0.8` so the
debugger resolves against both the `sagents` 0.8.x and 0.9.x lines. The 0.9.0
release reworks only the optional Horde distribution backend and changes no API
the debugger consumes (`Sagents.AgentServer`, `Sagents.Middleware`,
`Sagents.MiddlewareEntry`, `Sagents.Presence`, `Sagents.Subscriber`), so the two
are compatible. No functional changes.

### Changed
- Relax `sagents` requirement to `~> 0.8` (allows `>= 0.8.0` and `< 1.0.0`) [#34](https://github.com/sagents-ai/sagents_live_debugger/pull/34)

## v0.4.0

First stable release of the 0.4.0 line, promoting the `v0.4.0-rc.1`/`v0.4.0-rc.2` work out of the release-candidate phase. The library now tracks the stable `sagents` 0.8.0 line. There are no functional changes since `v0.4.0-rc.2` — see the RC entries below for the full feature set.

Because most users are upgrading directly from the 0.3.x line, note the breaking router change carried over from `v0.4.0-rc.1`.

### Upgrading from v0.3.x - v0.4.0

The `sagents_live_debugger` router macro now **requires** a `:pubsub` option pointing at the host application's `Phoenix.PubSub` instance. Previously the debugger derived the PubSub name from `coordinator.pubsub_name()`; that path has been removed.

Update your router:

```elixir
sagents_live_debugger "/debug/agents",
  coordinator: MyApp.Coordinator,
  pubsub: MyApp.PubSub,           # NEW — required
  presence_module: MyAppWeb.Presence
```

Mounting without `:pubsub` will raise `KeyError` at compile time.

### Changed
- **Breaking:** `:pubsub` is now a required option on the `sagents_live_debugger` router macro. See upgrade notes above.
- Promoted `sagents` dependency constraint from the pre-release `~> 0.8.0-rc` to the stable `~> 0.8.0` [#33](https://github.com/sagents-ai/sagents_live_debugger/pull/33)
- Updated README install instructions to the stable `~> 0.4.0` and removed the release-candidate note [#33](https://github.com/sagents-ai/sagents_live_debugger/pull/33)

## v0.4.0-rc.2

Maintenance release candidate. No breaking changes since v0.4.0-rc.1 — primarily a dependency refresh aligning with newer `sagents`/`langchain` releases, plus code-quality cleanups.

### Changed
- Dependency refresh, notably `sagents` `0.8.0-rc.1` → `0.8.0-rc.11` and `langchain` `0.8.4` → `0.8.12`, along with `phoenix`, `ecto` (3.13 → 3.14), `decimal` (2 → 3), `req`, `finch`, `mint`, `plug`, and other transitive bumps [#29](https://github.com/sagents-ai/sagents_live_debugger/pull/29)
- Removed dead `nil`-handling clauses in `AgentListLive` (`format_time_ago/1`, `format_duration_from_start/1`, `detail_format_time_ago/1`) that a newer compiler flagged as unreachable — every caller already guards against `nil` [#29](https://github.com/sagents-ai/sagents_live_debugger/pull/29)
- Credo-driven style cleanups across `agent_list_live.ex`, `core_components.ex`, `message_components.ex`, `session_config.ex`, and `subagents_tab.ex` (not part of a PR)
- Documentation fixes to silence `mix docs` warnings in `README.md` and `CHANGELOG.md` (not part of a PR)

## v0.4.0-rc.1

Release candidate aligned with `sagents` v0.8.0-rc.1. Contains a breaking router change and a new middleware debug-summary callback.

### Upgrading from v0.3.x - v0.4.0-rc.1

The `sagents_live_debugger` router macro now **requires** a `:pubsub` option pointing at the host application's `Phoenix.PubSub` instance. Previously the debugger derived the PubSub name from `coordinator.pubsub_name()`; that path has been removed.

Update your router:

```elixir
sagents_live_debugger "/debug/agents",
  coordinator: MyApp.Coordinator,
  pubsub: MyApp.PubSub,           # NEW — required
  presence_module: MyAppWeb.Presence
```

Mounting without `:pubsub` will raise `KeyError` at compile time.

### Added
- `c:Sagents.Middleware.debug_summary/1` callback support in the Middleware tab. When a middleware module exports `debug_summary/1`, its return value (a map or string) is rendered in place of the raw config — letting middleware that holds large structures (caches, big in-memory stores) surface a curated, compact view instead of dumping their entire configuration into the debug page.
- Bounded inspect output for middleware config via `inspect_for_display/1`. Defaults are now `limit: 200` and `printable_limit: 16_384`, preventing a single oversized value from dominating render time and DOM size. Middleware that needs a richer view should opt into `debug_summary/1`.
- Producer-crash recovery: `AgentListLive` now traps `:DOWN` from monitored AgentServers and flips the matching subscription entries to `:pending`, so the next presence-diff join for that `agent_id` resubscribes automatically.

### Changed
- **Breaking:** `:pubsub` is now a required option on the `sagents_live_debugger` router macro. See upgrade notes above.
- Updated dependency on `sagents` library to `>= 0.8.0-rc.1`.
- Subscription handling migrated to `Sagents.Subscriber` for both `:main` and `:debug` channels. Subscriptions for not-yet-running agents are recorded as `:pending` and upgraded automatically when the agent appears via `presence_diff`, replacing the previous `Sagents.AgentServer.subscribe/subscribe_debug` calls that returned `{:error, :process_not_found}` for offline agents.
- `subscribe_to_presence/2` and `subscribe_to_agent_presence/1` now use `Phoenix.PubSub.subscribe/2` directly (caller-level dedup via the `:subscribed_topics` MapSet) instead of `Sagents.PubSub.subscribe/3`.
- Middleware tab config rendering refactored into a multi-clause `middleware_config_display/1` function component, dispatching at compile time on `{:map, _}` vs `{:string, _}` payloads from `display_config/1`.

## v0.3.8

### Fixed
- `priv/` directory is now included in the published Hex package so the bundled CSS asset (`priv/static/debugger.css`) actually ships with the library [#24](https://github.com/sagents-ai/sagents_live_debugger/pull/24)

## v0.3.7

### Added
- `:csp_nonce_assign_key` router option for mounting the debugger under a strict Content Security Policy. Accepts either a single atom (used for both script and style nonces) or a `%{script: atom, style: atom}` map, matching the `Phoenix.LiveDashboard` convention. The emitted `<link>` and `<script>` tags in the root layout now include the corresponding `nonce` attribute [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)
- Self-contained CSS asset serving: the ~2060-line stylesheet was extracted from the inline `<style>` block into `priv/static/debugger.css` and is served from a cache-busted `/css-:md5` Plug route alongside the existing JS bundle, with `public, max-age=31536000, immutable` headers [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)
- New `SagentsLiveDebugger.Timezone` module with `validate/1` and `validate_or_utc/1`, backed by `Tzdata`, so browser-supplied zones can never crash `DateTime.shift_zone/3` when rendering event timestamps [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)

### Changed
- Browser timezone is now read from the LiveSocket `connect_params` at mount time (pushed by the bundled LiveSocket init script) and validated in `SessionConfig.on_mount/4`, replacing the previous hidden-button + `phx:page-loading-stop` JS round-trip [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)
- `live_session :sagents_debugger` now uses the MFA session form (`{SagentsLiveDebugger.Router, :__session__, [...]}`) instead of a static map, keeping session resolution lazy [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)
- Removed the inline `<style>` block, the hidden `#sagents-tz-btn` button, the `set_timezone` event handler, and the private `validate_timezone/1` helper from `AgentListLive`, all superseded by the new asset route and `Timezone` module [#23](https://github.com/sagents-ai/sagents_live_debugger/pull/23)

## v0.3.6

### Added
- Live message updates during multi-turn agent runs - the Messages tab now streams `:agent_state_messages_appended` events and patches messages turn-by-turn instead of waiting for the final `:agent_state_update` [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)
- Cancelled agent state handling with a red "Agent cancelled" banner at the end of the messages list, a `status-cancelled` badge in the SubAgents tab, and a dedicated `handle_subagent_event/3` clause that preserves streamed messages when a context-less cancellation broadcast arrives [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)
- Structured rendering of `%LangChain.LangChainError{}` sub-agent failures (context length exceeded, `:length` stops, etc.) with a clean type + message view instead of a raw `inspect` blob [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)
- `:subagent_failed_with_context` event handler that renders "Last N message(s) before failure" alongside the structured error [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)
- `.github/dependabot.yml` for weekly GitHub Actions updates with a 7-day cooldown [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)

### Changed
- CI workflow hardened per zizmor recommendations: `actions/checkout`, `erlef/setup-beam`, and `actions/cache` pinned to commit SHAs with version comments, and `persist-credentials: false` set on checkout [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)

### Fixed
- Lumis compiler warning resolved by moving the `:language` option into the `{:html_inline, ...}` formatter tuple in `core_components.ex` to match the current Lumis formatter signature [#19](https://github.com/sagents-ai/sagents_live_debugger/pull/19)

## v0.3.5

### Added
- Self-contained JavaScript asset serving following the `Phoenix.LiveDashboard` pattern -- the debugger now bundles `phoenix.js`, `phoenix_html.js`, and `phoenix_live_view.js` at compile time and serves them from a cache-busted Plug route, so host applications no longer need to provide LiveView JS assets [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)
- WebSocket-to-LongPoll automatic fallback in the bundled LiveSocket initialization [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)
- `live_socket_path` option in router macro for custom WebSocket paths [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)

### Changed
- Layout split into `root/1` (HTML shell with `<script>`, CSRF meta, `phx-socket`) and `app/1` (passthrough), matching Phoenix conventions for root vs app layouts [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)
- `.btn-primary` and `.btn-secondary` styles promoted to global scope (previously scoped under `.filter-actions`) [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)

### Fixed
- Debugger now works in host applications that don't load Phoenix LiveView JavaScript in their own layout [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)
- Button styles rendering inconsistently outside of filter actions context [#17](https://github.com/sagents-ai/sagents_live_debugger/pull/17)

## v0.3.4

### Added
- Error events are now displayed in the agent event stream, making it easier to spot and diagnose failures during agent runs [#14](https://github.com/sagents-ai/sagents_live_debugger/pull/14)

## v0.3.3

### Changed
- Loosened dependency constraints on `jason`, `mdex`, `lumis`, and `tzdata` (from `~>` to `>=`) so host applications can pin their own compatible versions without conflicts [#13](https://github.com/sagents-ai/sagents_live_debugger/pull/13)

## v0.3.2

### Added
- Middleware tab now displays the tools provided by each middleware item, with a collapsible tools list showing tool count [#11](https://github.com/sagents-ai/sagents_live_debugger/pull/11)

### Changed
- Relaxed `sagents` dependency constraint from `~> 0.4.0` to `>= 0.4.0` for greater compatibility with host applications

## v0.3.1

### Changed
- Updated dependency on `sagents` library to `~> 0.4.0`

### Fixed
- README setup example now includes the required `presence_module` option in the router configuration

## v0.3.0

### Added
- Enhanced display of interrupted tool calls — interrupted tool results now show a ✋ icon, amber "INTERRUPTED" badge, and a highlighted code block with interrupt data details [#7](https://github.com/sagents-ai/sagents_live_debugger/pull/7)
- Interrupt summary formatting in the event timeline, distinguishing direct HITL interrupts from sub-agent HITL interrupts [#7](https://github.com/sagents-ai/sagents_live_debugger/pull/7)
- Agent run mode display on the overview tab under "Agent Information" [#6](https://github.com/sagents-ai/sagents_live_debugger/pull/6)

### Changed
- Updated dependency on `sagents` library to `~> 0.3.0` (and `langchain` to `0.6.1` via transitive dep) [#7](https://github.com/sagents-ai/sagents_live_debugger/pull/7)

## v0.2.1

### Changed
- Updated dependency on `sagents` library to `~> 0.2.1`

## v0.2.0

### Added
- Horde distributed clustering support - the debug dashboard is now cluster-aware and handles agent migration across nodes [#2](https://github.com/sagents-ai/sagents_live_debugger/pull/2)
- "Node" column in the agent list table showing which node each agent runs on
- Node transfer events (`:node_transferring`, `:node_transferred`) for tracking agent migration
- `most_recent_meta/1` helper for resolving multiple presence metas during Horde handoffs

### Changed
- Updated dependency on `sagents` library to `~> 0.2.0`
- Dashboard title changed from "Agent Debug Dashboard" to "Sagents Debug Dashboard"
- Migrated syntax highlighting theme from Autumn to Lumis
- Added `lumis` dependency (`~> 0.1`)

## v0.1.0

Initial release published to [hex.pm](https://hex.pm).
