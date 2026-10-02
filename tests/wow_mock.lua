-- Deliberately strict protection model. Secure snippets run verbatim, not reimplemented.
local H = { frames = {}, all = {}, drivers = {}, now = 100, combat = false, secure = false,
  known = true, cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } }
local function protected(frame)
  if not frame or frame == UIParent then return false end
  return frame.protected or protected(frame.parent)
end
local function guard(frame, operation)
  assert(not (H.combat and not H.secure and protected(frame)), "protected operation in combat: " .. operation)
end
local methods = {}
local function widget(parent, name)
  return setmetatable({ parent = parent, name = name, children = {}, scripts = {}, attrs = {}, refs = {}, events = {}, shown = true }, { __index = methods })
end
function methods:SetScript(k, v) self.scripts[k] = v end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k, v)
  local old = self.scripts[k]
  self.scripts[k] = function(...) if old then old(...) end; v(...) end
end
function methods:Show() guard(self, "Show"); self.shown = true end
function methods:Hide()
  guard(self, "Hide")
  local wasShown = self.shown
  self.shown = false
  if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text end
function methods:SetTexture(v) self.texture = v end
function methods:SetDesaturated(v) self.desaturated = v end
function methods:SetAttribute(k, v)
  guard(self, "SetAttribute")
  self.attrs[k] = v
end
function methods:GetAttribute(k) return self.attrs[k] end
function methods:SetFrameRef(k, v) guard(self, "SetFrameRef"); self.refs[k] = v end
function methods:GetFrameRef(k) return self.refs[k] end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:GetHeight() return 260 end
function methods:SetEnabled(v) guard(self, "SetEnabled"); self.enabled = v end
function methods:CreateFontString() local w = widget(self); table.insert(self.children, w); return w end
methods.CreateTexture = methods.CreateFontString
for _, op in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetHeight", "SetWidth", "Raise", "StartMoving", "StopMovingOrSizing", "SetMovable", "EnableMouse", "RegisterForDrag", "RegisterForClicks" }) do
  methods[op] = function(self, ...) guard(self, op); self[op .. "Args"] = {...} end
end
for _, op in ipairs({ "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetTextColor", "SetColorTexture", "SetScrollChild", "SetHighlightTexture", "SetAlpha", "SetTexCoord", "SetAllPoints", "SetFrameStrata", "SetClampedToScreen", "SetJustifyH" }) do
  methods[op] = function() end
end
UIParent = widget(nil, "UIParent")
CreateFrame = function(_, name, parent, template)
  assert(not (H.combat and template and template:find("Secure")), "creating protected frame in combat")
  local f = widget(parent, name); f.template = template
  if template and template:find("Secure") then
    f.protected = true
    local p = parent
    while p and p ~= UIParent do p.protected = true; p = p.parent end
  end
  if parent then table.insert(parent.children, f) end
  if name then H.frames[name] = f; _G[name] = f end
  table.insert(H.all, f)
  return f
end
local function runDriver(f)
  local snippet = f.attrs["_onstate-combat"]
  if snippet then
    local fn = assert((loadstring or load)("return function(self, newstate) " .. snippet .. " end"))()
    H.secure = true
    fn(f, H.combat and "combat" or "peace")
    H.secure = false
  end
end
RegisterStateDriver = function(f, state, condition)
  guard(f, "RegisterStateDriver")
  assert(state == "combat" and condition == "[combat] combat; peace", "unexpected secure driver")
  H.drivers[f] = true
  runDriver(f)
end
function H.event(event, ...)
  for _, f in ipairs(H.all) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
function H.setCombat(value)
  H.combat = value
  for f in pairs(H.drivers) do runDriver(f) end
  H.event(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
function H.text(root, value)
  if root.text == value then return root end
  for _, child in ipairs(root.children) do local match = H.text(child, value); if match then return match end end
end
function H.escape()
  for _, name in ipairs(UISpecialFrames) do local f = _G[name]; if f and f:IsShown() then f:Hide() end end
end
function H.accept(id, map)
  H.result = { activityIDs = { id }, name = "Test +10" }
  H.activity = { fullName = "Dungeon " .. id, mapID = map, isMythicPlusActivity = true }
  C_LFGList.ApplyToGroup(id, false, false, true)
  H.event("LFG_LIST_APPLICATION_STATUS_UPDATED", id, "applied", "none", "Test +10")
  H.result = nil -- acceptance must use the cached numeric identity
  H.now = H.now + 10
  H.event("LFG_LIST_APPLICATION_STATUS_UPDATED", id, "inviteaccepted", "invited", "Test +10")
end
GetTime = function() return H.now end
InCombatLockdown = function() return H.combat end
UnitFactionGroup = function() return H.faction or "Alliance" end
C_SpellBook = { IsSpellKnown = function() return H.known end }
C_Spell = {
  GetSpellTexture = function(id) return id + 1 end,
  GetSpellCooldown = function() if H.cooldownError then error("restricted") end; return H.cooldown end,
}
issecretvalue = function(value) return value == H.secret and H.secret ~= nil end
C_Map = { GetMapInfo = function() error("must never confuse instance maps with UI maps") end }
C_Timer = { After = function() end }
C_LFGList = {
  ApplyToGroup = function() end,
  GetSearchResultInfo = function() return H.result end,
  GetActivityInfoTable = function() return H.activity end,
  GetApplicationInfo = function() return { role = "DAMAGER" } end,
  GetApplications = function() return {} end,
}
hooksecurefunc = function(owner, key, callback)
  local original = owner[key]
  owner[key] = function(...) original(...); callback(...) end
end
StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}
QueueSimulatorAccountDB, QueueSimulatorCharacterDB = {}, {}
dofile("QueueSimulator/Core.lua")
dofile("QueueSimulator/Teleport.lua")
local realPrint = print; print = function() end
dofile("QueueSimulator/Addon.lua")
print = realPrint
return H
