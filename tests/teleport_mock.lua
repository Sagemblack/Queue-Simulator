local H = dofile("tests/wow_mock.lua")
H.accept(1, 2660)
local popup = H.frames.QueueSimulatorAcceptedFrame
local button = assert(H.frames.QueueSimulatorTeleportButton, "acceptance provides a secure teleport button")
assert(button.template:find("SecureActionButtonTemplate"), "only player-click secure spell action")
assert(button:GetAttribute("type") == "spell" and button:GetAttribute("spell") == 445417, "cached activity configures correct spell")
assert(H.text(popup, "Teleport: Ready"), "ready label")
assert(button.Icon.texture == 445418, "spell icon")
assert(popup:IsShown(), "popup shown")
H.text(popup, "Open Dashboard").scripts.OnClick()
assert(popup:IsShown(), "dashboard must not dismiss teleport")
H.known = false
H.event("SPELLS_CHANGED")
assert(H.text(popup, "Teleport: Locked (not learned)"), "locked label")
assert(button:GetAttribute("type") == nil and button:GetAttribute("spell") == nil, "unlearned cannot cast")
H.known = true
H.cooldown = { startTime = H.now, duration = 60, isEnabled = true, modRate = 1 }
H.event("SPELL_UPDATE_COOLDOWN")
assert(H.text(popup, "Teleport: Cooldown (60s)"), "cooldown label")
assert(button:GetAttribute("type") == nil, "cooldown is not an armed action")
H.now = H.now + 61
popup.scripts.OnUpdate(popup, 1)
assert(H.text(popup, "Teleport: Ready") and button:GetAttribute("spell") == 445417, "cooldown expiry updates without events")
H.accept(2, 601)
assert(H.text(popup, "Teleport: Unmapped dungeon"), "unmapped label")
assert(button:GetAttribute("type") == nil and button:GetAttribute("spell") == nil, "unknown dungeon clears stale spell")
assert(button.Icon.texture == "Interface\\Icons\\INV_Misc_QuestionMark", "unmapped uses valid question-mark icon path")
H.accept(3, 2660)
H.setCombat(true)
assert(not popup:IsShown(), "secure combat state hides protected parent")
assert(button:GetAttribute("type") == nil and button:GetAttribute("spell") == nil, "secure combat state disarms stale action")
-- Guard against insecure movement, event updates and close calls during lockdown.
popup.scripts.OnDragStart(popup)
popup.scripts.OnDragStop(popup)
H.event("SPELL_UPDATE_COOLDOWN")
popup.scripts.OnUpdate(popup, 1)
H.accept(4, 2526)
assert(not popup:IsShown(), "acceptance in combat stays pending")
assert(button:GetAttribute("spell") == nil, "pending acceptance never arms old spell")
H.setCombat(false)
assert(popup:IsShown() and button:GetAttribute("spell") == 393273, "regen shows latest accepted destination")
assert(H.text(popup, "Dungeon 4"), "deferred popup snapshot matches teleport")
H.setCombat(true)
H.accept(5, 2660)
H.escape()
H.setCombat(false)
assert(not popup:IsShown(), "Escape cancels pending acceptance without touching protected parent")
assert(button:GetAttribute("spell") == nil, "cancelled pending popup stays disarmed")
H.accept(6, 2660)
H.text(popup, "Close").scripts.OnClick()
assert(not popup:IsShown(), "Close dismisses popup")
H.setCombat(true); H.setCombat(false)
assert(not popup:IsShown(), "dismissed popup never resurrects on regen")
H.accept(7, 2660)
H.cooldown = nil
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("type") == nil, "missing cooldown data must fail closed")
assert(H.text(popup, "Teleport: Unavailable"), "missing data visibly unavailable")
H.cooldown = { startTime = 0, duration = 0, isEnabled = false, modRate = 1 }
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("type") == nil, "disabled spell is unavailable")
H.secret = {}
H.cooldown = { startTime = H.secret, duration = H.secret, isEnabled = true }
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("type") == nil, "secret cooldown must not be used in arithmetic")
H.cooldownError = true
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("type") == nil, "API errors fail closed")
H.cooldownError, H.secret = false, nil
H.cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("spell") == 445417, "recovers after temporary API restriction")
H.setCombat(true)
H.accept(8, 2526)
SlashCmdList.QUEUESIMULATOR("reset")
H.setCombat(false)
assert(not popup:IsShown(), "reset cancels pending acceptance")
H.accept(9, 2660)
H.escape()
assert(not popup:IsShown() and button:GetAttribute("spell") == nil, "out-of-combat Escape also clears action")
assert(not button.scripts.OnClick and not button.scripts.PreClick, "no insecure casting scripts")
-- First acceptance while hidden/in combat; newer acceptance replaces pending snapshot.
H.setCombat(true)
H.accept(10, 2660)
H.accept(11, 2526)
H.text(popup, "Close").scripts.OnClick()
H.setCombat(false)
assert(not popup:IsShown(), "combat Close cancels the newest pending acceptance")
H.setCombat(true)
H.accept(12, 2660)
H.accept(13, 2526)
H.setCombat(false)
assert(H.text(popup, "Dungeon 13") and button:GetAttribute("spell") == 393273, "only newest pending acceptance is displayed")
H.setCombat(true)
H.text(popup, "Open Dashboard").scripts.OnClick()
assert(H.frames.QueueSimulatorDashboardFrame:IsShown(), "independent dashboard works in combat")
StaticPopupDialogs.QUEUESIMULATOR_RESET_LIFETIME.OnAccept()
H.setCombat(false)
assert(not popup:IsShown(), "lifetime reset cancels suspended popup")
H.accept(14, 1822)
assert(button:GetAttribute("spell") == 445418, "Alliance teleport variant")
H.faction = "Horde"
H.event("SPELLS_CHANGED")
assert(button:GetAttribute("spell") == 464256, "Horde teleport variant re-resolved")
H.faction = "Neutral"
H.event("SPELLS_CHANGED")
assert(button:GetAttribute("spell") == nil, "unknown faction cannot reuse old variant")
H.accept(15, 2660)
local spellAPI = C_Spell
C_Spell = nil
H.event("SPELL_UPDATE_COOLDOWN")
assert(button:GetAttribute("spell") == nil, "missing spell API disarms action")
C_Spell = spellAPI
local bookAPI = C_SpellBook
C_SpellBook = nil
H.event("SPELLS_CHANGED")
assert(H.text(popup, "Teleport: Unavailable"), "missing spellbook is unavailable, not guessed locked")
C_SpellBook = bookAPI
H.event("SPELLS_CHANGED")
H.setCombat(true)
-- Simulate regen event arriving before InCombatLockdown() clears.
H.event("PLAYER_REGEN_ENABLED")
assert(not popup:IsShown(), "regen handler checks actual lockdown")
H.setCombat(false)
assert(button:GetAttribute("spell") == 445417, "suspended acceptance returns safely")
local textureAPI = C_Spell.GetSpellTexture
C_Spell.GetSpellTexture = function() error("spell icon not cached") end
H.event("SPELLS_CHANGED")
assert(button.Icon.texture == "Interface\\Icons\\INV_Misc_QuestionMark", "missing icon uses safe fallback")
C_Spell.GetSpellTexture = textureAPI
H.event("SPELLS_CHANGED")
H.escape()
H.result = { activityIDs = { 16, 17 }, name = "Test +10" }
H.activity = { fullName = "Ambiguous listing", mapID = 2660, isMythicPlusActivity = true }
C_LFGList.ApplyToGroup(16, false, false, true)
H.event("LFG_LIST_APPLICATION_STATUS_UPDATED", 16, "applied", "none", "Test +10")
H.event("LFG_LIST_APPLICATION_STATUS_UPDATED", 16, "inviteaccepted", "invited", "Test +10")
assert(button:GetAttribute("spell") == nil, "multiple listed activities must not guess a teleport")
print("teleport popup integration tests passed")
