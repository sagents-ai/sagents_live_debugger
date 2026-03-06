# Changelog

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
