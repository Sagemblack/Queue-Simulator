local frames = {}
local now = 0
local applicationRole = "NONE"
local reusedResultIsMythicPlus = false
local primaryResultInfoReads = 0
local protectedKeyTitle = setmetatable({}, { __tostring = function() return "+12" end })

local function widget(parent)
  local value = { children = {}, scripts = {}, shown = true }
  local methods = {}

  function methods:CreateFontString()
    local child = widget(self)
    table.insert(self.children, child)
    return child
  end

  function methods:CreateTexture()
    local child = widget(self)
    table.insert(self.children, child)
    return child
  end

  function methods:SetScript(name, callback) self.scripts[name] = callback end
  function methods:SetText(text) self.text = tostring(text) end
  function methods:GetText() return self.text end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:SetShown(shown) self.shown = shown == true end
  function methods:IsShown() return self.shown == true end
  function methods:GetHeight() return 260 end
  function methods:GetStringHeight() return 20 end

  setmetatable(methods, { __index = function() return function() end end })
  return setmetatable(value, { __index = methods })
end

local function allTexts(root, result)
  result = result or {}
  if root.text then result[root.text] = root end
  for _, child in ipairs(root.children or {}) do allTexts(child, result) end
  return result
end

QueueSimulatorCore = dofile("QueueSimulator/Core.lua")
dofile("QueueSimulator/Teleport.lua")
QueueSimulatorAccountDB = {}
QueueSimulatorCharacterDB = {}
MPlusApplicationTrackerAccountDB = nil
MPlusApplicationTrackerCharacterDB = nil
UIParent = widget()
StaticPopupDialogs = {}
SlashCmdList = {}
UISpecialFrames = {}
TANK = "Tank"
HEALER = "Healer"
DAMAGER = "Damage"
C_Timer = { After = function() end }
GetTime = function() return now end
InCombatLockdown = function() return false end
RegisterStateDriver = function() end
CreateAtlasMarkup = function(atlas) return "<" .. atlas .. ">" end
CreateFrame = function(_, name, parent)
  local frame = widget(parent)
  if parent and parent.children then table.insert(parent.children, frame) end
  if name then frames[name] = frame end
  return frame
end
hooksecurefunc = function(owner, method, callback)
  local original = owner[method]
  owner[method] = function(...)
    local results = { original(...) }
    callback(...)
    return (unpack or table.unpack)(results)
  end
end

C_LFGList = {
  ApplyToGroup = function() return true end,
  GetSearchResultInfo = function(searchResultID)
    if searchResultID == 42 then
      primaryResultInfoReads = primaryResultInfoReads + 1
      if primaryResultInfoReads == 1 then return { activityIDs = { 99 }, name = {} } end
      return nil
    end
    if searchResultID == 77 then return { activityIDs = { 98 }, name = "Reused +8" } end
    return nil
  end,
  GetActivityInfoTable = function(activityID)
    if activityID == 99 then
      return {
        fullName = "Kings' Rest (Mythic Keystone)",
        shortName = "Kings' Rest",
        groupFinderActivityGroupID = 501,
        mapID = 601,
        isMythicPlusActivity = true,
      }
    end
    if activityID == 98 then return { shortName = "Reused", isMythicPlusActivity = reusedResultIsMythicPlus } end
    return nil
  end,
  GetActivityGroupInfo = function(groupID)
    if groupID == 501 then return "Mythic+" end
    return nil
  end,
  GetApplicationInfo = function(searchResultID)
    return searchResultID, "applied", nil, 0, applicationRole
  end,
  GetApplications = function() return {} end,
}
C_Map = {
  GetMapInfo = function(mapID)
    if mapID == 601 then return { name = "Torghast, Tower of the Damned" } end
    return nil
  end,
}

local realPrint = print
print = function() end
local ok, err = pcall(dofile, "QueueSimulator/Addon.lua")
print = realPrint
assert(ok, err)

local trackerFrame = assert(frames.QueueSimulatorFrame, "tracker frame was not created")
local acceptedFrame = assert(frames.QueueSimulatorAcceptedFrame, "accepted frame was not created")
local dashboardFrame = assert(frames.QueueSimulatorDashboardFrame, "dashboard frame was not created")
local onEvent = assert(trackerFrame.scripts.OnEvent, "tracker event handler was not registered")

now = 100
C_LFGList.ApplyToGroup(42, true, false, true)
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "applied", "none", "Kings' Rest +12")
assert(not acceptedFrame:IsShown(), "accepted popup must stay hidden after applying")

now = 150
applicationRole = "DAMAGER"
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "invited", "applied", protectedKeyTitle)
assert(not acceptedFrame:IsShown(), "accepted popup must stay hidden on invitation")

now = 300
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "inviteaccepted", "invited", protectedKeyTitle)
assert(acceptedFrame:IsShown(), "accepted popup must open after accepting")

local texts = allTexts(acceptedFrame)
assert(texts["ACCEPTED!"], "accepted popup title")
assert(texts["Kings' Rest (Mythic Keystone)"], "accepted popup uses Blizzard's activity name rather than an unrelated map name")
assert(not texts["Torghast, Tower of the Damned"], "accepted popup must not use activity mapID as dungeon identity")
assert(texts["+12"], "accepted popup uses the key title from the acceptance event")
assert(texts["Applied as: <groupfinder-icon-role-micro-tank> Tank + <groupfinder-icon-role-micro-dps> Damage"], "accepted popup applied roles use icons")
assert(texts["Accepted as: <groupfinder-icon-role-micro-dps> Damage"], "accepted popup accepted role uses icon")
assert(texts["00:03:20"], "accepted popup session duration")
assert(texts["Applications"], "accepted popup application statistic")
assert(texts["Accepted"], "accepted popup accepted statistic")

local history = QueueSimulatorAccountDB.sessionHistory
assert(#history == 1, "accepted session must be recorded")
assert(history[1].acceptedDungeon == "Kings' Rest (Mythic Keystone)", "accepted dungeon must be persisted")
assert(history[1].acceptedKeyLevel == nil, "protected key title is not persisted as a guessed number")
assert(history[1].appliedRoles.TANK, "applied tank role must be persisted")
assert(history[1].appliedRoles.DAMAGER, "applied damage role must be persisted")
assert(history[1].acceptedRole == "DAMAGER", "accepted role must be persisted")

local openDashboard = assert(texts["Open Dashboard"], "accepted popup dashboard button")
assert(openDashboard.scripts.OnClick, "accepted popup dashboard action")
openDashboard.scripts.OnClick(openDashboard)
assert(acceptedFrame:IsShown(), "opening dashboard keeps accepted popup open")
assert(dashboardFrame:IsShown(), "opening dashboard shows dashboard")
local dashboardTexts = allTexts(dashboardFrame)
assert(dashboardTexts["+  <groupfinder-icon-role-micro-dps> Kings' Rest (Mythic Keystone)"], "accepted session title uses role icon and dungeon")
assert(dashboardTexts["+12"], "recent session renders the protected key title separately")

C_LFGList.ApplyToGroup(77, true, false, false)
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 77, "applied", "none", "Non-Mythic listing")
reusedResultIsMythicPlus = true
applicationRole = "NONE"
now = 400
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 77, "applied", "none", "Reused +8")
applicationRole = "DAMAGER"
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 77, "invited", "applied", "Reused +8")
now = 500
onEvent(trackerFrame, "LFG_LIST_APPLICATION_STATUS_UPDATED", 77, "inviteaccepted", "invited", "Reused +8")
assert(#history == 2, "reused result creates a second accepted session")
assert(not history[2].appliedRoles.TANK, "untracked application roles must not leak when a result ID is reused")

realPrint("addon mock accepted-popup test passed")
