# Teleport catalog and secure button

## Catalog provenance

Numeric catalog checked on 2026-10-02 against the DungeonTeleports project's original source, pinned to commit `d577999d378cda287f3719f13d3e893d8f0ce3a9`:

- https://github.com/Earthenmist/DungeonTeleports/blob/d577999d378cda287f3719f13d3e893d8f0ce3a9/DungeonNames.lua
- https://github.com/Earthenmist/DungeonTeleports/blob/d577999d378cda287f3719f13d3e893d8f0ce3a9/TeleportData.lua

Joined the internal catalog IDs in TeleportData to the explicit instanceMapID values in DungeonNames. All 72 non-faction mappings in QueueSimulator/Teleport.lua match that join. Both faction-dependent mappings (Siege of Boralus and The MOTHERLODE!!) match DungeonNames. Raid destinations are excluded.

This is a maintained community catalog, not a live Blizzard teleport resolver or proof that every mapping works in the user's client. In-game verification remains required, particularly recent-season spells. An absent mapping offers no cast.

## Identity and runtime

Cache the accepted listing's numeric activity.mapID during signup. This is used as an **instance Map.db2 ID** in the curated table; it is never passed to C_Map.GetMapInfo, which expects a UiMapID. Dungeon display continues to use activity fullName, independent of teleport selection. There is no localized-name guessing.

Use C_SpellBook.IsSpellKnown and C_Spell.GetSpellCooldown to arm only known, ready spells. Missing, secret or failed reads leave the action unarmed. Spell texture lookup failures use the question-mark icon and are retried on later refreshes.

A SecureActionButtonTemplate performs the cast only on a hardware click. The parent is a SecureHandlerStateTemplate: its secure combat state hides the popup and clears spell attributes. Insecure handlers do not mutate protected frames during lockdown. On regeneration, only the latest pending accepted snapshot is refreshed before showing. An unprotected Escape proxy lets dismissal cancel pending state safely. Open Dashboard remains independent.

## Validation

- tests/teleport.lua: catalog fixtures, wrong-namespace rejection, faction variants and application metadata persistence.
- tests/teleport_mock.lua: ready/locked/cooldown states, unavailable/secret/error cases, missing texture fallback, stale spell clearing, combat/deferred acceptance, Escape/Close/reset and dashboard behavior.
- tests/wow_mock.lua: strict mocked protected-frame operations and execution of the actual combat-state snippet.

Mocks do not reproduce WoW's complete taint/security runtime or actually cast a spell. Test in game: accept a known destination, verify the spell icon/destination, click while ready, verify locked and cooldown states, then verify combat hiding, post-combat restoration and Close/Escape cancellation. Do not claim live validation before these checks.
