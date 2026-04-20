# Changelog

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
