# Queue Simulator

![Queue Simulator](assets/queue-simulator-thumbnail.png)

Queue Simulator is a World of Warcraft Retail addon that tracks Mythic+ Premade Group Finder applications and the painful wait behind them.

## Features

- Counts Mythic+ applications per tracking session.
- Session timer begins with the first application.
- Session ends when an invitation is accepted.
- Shows a persistent acceptance popup with the accepted dungeon, key level when available, roles selected when applying, accepted role, session duration, and session outcomes.
- Stores accepted dungeon, key level, applied roles, and accepted role in session history.
- Names accepted dashboard sessions after the dungeon and key level, with a native role icon for the accepted role.
- Tracks declined, player-cancelled, group-full, delisted, timed-out, failed, invited, invite-declined, and accepted outcomes separately.
- Stores character and account lifetime totals in SavedVariables.
- Provides a compact, movable live tracker designed to sit beside Group Finder.
- Displays live outcomes in aligned, color-assisted rows rather than a text block.
- Includes a larger dashboard with lifetime totals, acceptance rate, average session duration, and expandable recent sessions.
- Adds a clickable teleport spell icon to the accepted popup, with Ready, Locked, Cooldown and Unavailable/Unmapped labels. Only a learned, ready spell can be cast, and only through your click.
- Teleports resolve from a curated numeric instance-map catalog, never dungeon-name matching or UI-map lookups. Unsupported destinations fail closed. Catalog provenance is in `docs/teleport-sources.md`.
- The accepted popup temporarily hides and disarms in combat; pending acceptance is displayed after combat. Close/Escape cancels it, and Open Dashboard does not dismiss it.
- Protected key-title history is UI-only when a normal numeric level is unavailable; that fallback does not survive reload.
- Slash commands:
  - `/qsim` opens the dashboard
  - `/qsim status`
  - `/qsim show`
  - `/qsim hide`
  - `/qsim end`
  - `/qsim reset`
  - `/qsim history`

## Outcome clarification

Queue Simulator records the underlying application statuses reported by WoW and keeps **Declined** and **Delisted** as separate, non-overlapping outcomes. Blizzard's Premade Group Finder displays the word **Declined** for both an application actually declined by the group leader and a listing that was delisted. As a result, an entry shown as **Declined** in Blizzard's queue may correctly increase Queue Simulator's **Delisted** counter instead of its **Declined** counter.

## Testing

```bash
lua tests/run.lua
lua tests/addon_mock.lua
lua tests/teleport.lua
lua tests/teleport_mock.lua
luac -p QueueSimulator/Core.lua
luac -p QueueSimulator/Addon.lua
luac -p QueueSimulator/Teleport.lua
```

The final compatibility check is live testing in the current WoW Retail client, especially application status events and Mythic+ activity filtering.
