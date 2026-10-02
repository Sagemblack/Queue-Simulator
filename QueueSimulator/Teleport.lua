local M = {}

-- Keys are instance Map.db2 IDs, NOT UiMapIDs or MapChallengeMode IDs.
-- Numeric catalog provenance and supported destinations: docs/teleport-sources.md.
local spells = {
  [658] = 1254555, -- Pit of Saron
  [657] = 410080, -- The Vortex Pinnacle
  [643] = 424142, -- Throne of the Tides
  [670] = 445424, -- Grim Batol
  [960] = 131204, -- Temple of the Jade Serpent
  [1011] = 131228, -- Siege of Niuzao Temple
  [1007] = 131232, -- Scholomance
  [1004] = 131229, -- Scarlet Monastery
  [1001] = 131231, -- Scarlet Halls
  [962] = 131225, -- Gate of the Setting Sun
  [994] = 131222, -- Mogu'shan Palace
  [959] = 131206, -- Shado-Pan Monastery
  [961] = 131205, -- Stormstout Brewery
  [1176] = 159899, -- Shadowmoon Burial Grounds
  [1279] = 159901, -- The Everbloom
  [1175] = 159895, -- Bloodmaul Slag Mines
  [1182] = 159897, -- Auchindoun
  [1209] = 159898, -- Skyreach
  [1358] = 159902, -- Upper Blackrock Spire
  [1208] = 159900, -- Grimrail Depot
  [1195] = 159896, -- Iron Docks
  [1466] = 424163, -- Darkheart Thicket
  [1501] = 424153, -- Black Rook Hold
  [1477] = 393764, -- Halls of Valor
  [1458] = 410078, -- Neltharion's Lair
  [1571] = 393766, -- Court of Stars
  [1651] = 373262, -- Return to Karazhan
  [1753] = 1254551, -- Seat of the Triumvirate
  [1763] = 424187, -- Atal'Dazar
  [1754] = 410071, -- Freehold
  [1862] = 424167, -- Waycrest Manor
  [1841] = 410074, -- The Underrot
  [2097] = 373274, -- Operation: Mechagon
  [1822] = { Alliance = 445418, Horde = 464256 }, -- Siege of Boralus
  [1594] = { Alliance = 467553, Horde = 467555 }, -- The MOTHERLODE!!
  [1877] = 1286828, -- Temple of Sethraliss
  [1762] = 1286831, -- Kings' Rest
  [2286] = 354462, -- The Necrotic Wake
  [2289] = 354463, -- Plaguefall
  [2290] = 354464, -- Mists of Tirna Scithe
  [2287] = 354465, -- Halls of Atonement
  [2285] = 354466, -- Spires of Ascension
  [2293] = 354467, -- Theater of Pain
  [2291] = 354468, -- De Other Side
  [2284] = 354469, -- Sanguine Depths
  [2441] = 367416, -- Tazavesh, the Veiled Market
  [2521] = 393256, -- Ruby Life Pools
  [2516] = 393262, -- The Nokhud Offensive
  [2515] = 393279, -- The Azure Vault
  [2526] = 393273, -- Algeth'ar Academy
  [2451] = 393222, -- Uldaman: Legacy of Tyr
  [2519] = 393276, -- Neltharus
  [2520] = 393267, -- Brackenhide Hollow
  [2527] = 393283, -- Halls of Infusion
  [2579] = 424197, -- Dawn of the Infinite
  [2669] = 445416, -- City of Threads
  [2660] = 445417, -- Ara-Kara, City of Echoes
  [2652] = 445269, -- The Stonevault
  [2662] = 445414, -- The Dawnbreaker
  [2648] = 445443, -- The Rookery
  [2651] = 445441, -- Darkflame Cleft
  [2661] = 445440, -- Cinderbrew Meadery
  [2649] = 445444, -- Priory of the Sacred Flame
  [2773] = 1216786, -- Operation: Floodgate
  [2830] = 1237215, -- Eco-Dome Al'dani
  [2811] = 1254572, -- Magisters' Terrace
  [2874] = 1254559, -- Maisara Caverns
  [2915] = 1254563, -- Nexus-Point Xenas
  [2805] = 1254400, -- Windrunner Spire
  [2993] = 1286812, -- Altar of Fangs
  [2825] = 1286807, -- Den of Nalorakk
  [2859] = 1286801, -- The Blinding Vale
  [2923] = 1286804, -- Voidscar Arena
  [2813] = 1286809, -- Murder Row
}

function M.resolve(instanceMapID, faction)
  if issecretvalue and issecretvalue(instanceMapID) then return nil end
  if type(instanceMapID) ~= "number" then return nil end
  local spell = spells[instanceMapID]
  if type(spell) == "table" then
    if issecretvalue and issecretvalue(faction) then return nil end
    return spell[faction or ""]
  end
  return spell
end

local function public(value)
  return not issecretvalue or not issecretvalue(value)
end

local function read(api, ...)
  if not api then return nil end
  local ok, value = pcall(api, ...)
  if ok and public(value) then return value end
end

local function spellState(spell)
  if not spell then return "unmapped", "Teleport: Unmapped dungeon" end
  local known = read(C_SpellBook and C_SpellBook.IsSpellKnown, spell)
  if known == false then return "locked", "Teleport: Locked (not learned)" end
  if known ~= true then return "unavailable", "Teleport: Unavailable" end
  local cd = read(C_Spell and C_Spell.GetSpellCooldown, spell)
  if type(cd) ~= "table" or not public(cd.startTime) or not public(cd.duration)
    or not public(cd.isEnabled) or not public(cd.modRate)
    or type(cd.startTime) ~= "number" or type(cd.duration) ~= "number"
    or cd.isEnabled ~= true then return "unavailable", "Teleport: Unavailable" end
  local remaining = math.max(0, cd.startTime + cd.duration - GetTime())
  if remaining > 0 then
    return "cooldown", string.format("Teleport: Cooldown (%ds)", math.ceil(remaining))
  end
  return "ready", "Teleport: Ready"
end

function M.attach(parent)
  local controller = {}
  local button = CreateFrame("Button", "QueueSimulatorTeleportButton", parent, "SecureActionButtonTemplate")
  controller.button = button
  button:SetSize(36, 36)
  button:SetPoint("BOTTOMLEFT", 28, 57)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetAllPoints(button)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", button, "RIGHT", 12, 0)
  function controller:Refresh()
    if InCombatLockdown() then return end
    local spell = M.resolve(self.instanceMapID, UnitFactionGroup and UnitFactionGroup("player"))
    local state, text = spellState(spell)
    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    if state == "ready" then
      button:SetAttribute("spell", spell)
      button:SetAttribute("type", "spell")
    end
    local texture = spell and read(C_Spell and C_Spell.GetSpellTexture, spell)
    button.Icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.Icon:SetDesaturated(state ~= "ready")
    label:SetText(text)
  end
  -- Secure state transition is the ONLY code that touches the protected popup in combat.
  -- It never re-shows on leaving combat: insecure regen must refresh the latest snapshot first.
  parent:SetFrameRef("teleport", button)
  parent:SetAttribute("_onstate-combat", [[
    if newstate == "combat" then
      self:Hide()
      local action = self:GetFrameRef("teleport")
      action:SetAttribute("type", nil)
      action:SetAttribute("spell", nil)
    end
  ]])
  RegisterStateDriver(parent, "combat", "[combat] combat; peace")

  -- Not parented/anchored to the protected popup. Blizzard's Escape handler can safely
  -- hide this proxy even while the popup is combat-hidden or waiting to be shown.
  local escape = CreateFrame("Frame", "QueueSimulatorAcceptedEscape", UIParent)
  escape:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "QueueSimulatorAcceptedEscape") end
  function controller:Close()
    self.wanted, self.render, self.instanceMapID = false, nil, nil
    if escape:IsShown() then escape:Hide() end
    if InCombatLockdown() then return end
    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    parent:Hide()
  end
  escape:SetScript("OnHide", function() controller:Close() end)
  function controller:Resume()
    if InCombatLockdown() then return end
    parent:StopMovingOrSizing()
    if not self.wanted then self:Close(); return end
    if self.render then self.render() end
    self:Refresh()
    parent:Show()
    parent:Raise()
  end
  function controller:Show(instanceMapID, render)
    self.instanceMapID, self.render, self.wanted = instanceMapID, render, true
    escape:Show()
    self:Resume()
  end
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("SPELLS_CHANGED")
  events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then controller:Resume()
    elseif parent:IsShown() then controller:Refresh() end
  end)
  local elapsedTotal = 0
  parent:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal >= 1 then elapsedTotal = 0; controller:Refresh() end
  end)
  return controller
end

QueueSimulatorTeleport = M
return M
