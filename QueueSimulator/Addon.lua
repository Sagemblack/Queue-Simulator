local addonName = ...
local Core = QueueSimulatorCore

QueueSimulatorAccountDB = QueueSimulatorAccountDB or MPlusApplicationTrackerAccountDB or {}
QueueSimulatorCharacterDB = QueueSimulatorCharacterDB or MPlusApplicationTrackerCharacterDB or {}
MPlusApplicationTrackerAccountDB = nil
MPlusApplicationTrackerCharacterDB = nil

local tracker = Core.new(QueueSimulatorCharacterDB, QueueSimulatorAccountDB, QueueSimulatorCharacterDB.sessionState, QueueSimulatorAccountDB.sessionState)
local active = tracker.session.active
local pendingApplicationDetails = {}
local lastInspection
local recentKeyTitles = {}
local recentKeyTitleAvailable = {}

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLASES = {
  TANK = "groupfinder-icon-role-micro-tank",
  HEALER = "groupfinder-icon-role-micro-heal",
  DAMAGER = "groupfinder-icon-role-micro-dps",
}
local function roleName(role)
  return role and (_G[role] or role) or "Unknown"
end

local function roleIcon(role)
  local atlas = ROLE_ATLASES[role]
  if not atlas or not CreateAtlasMarkup then return "" end
  return CreateAtlasMarkup(atlas, 14, 14, 0, 0) .. " "
end

local function formatRoles(roles)
  local labels = {}
  for _, role in ipairs(ROLE_ORDER) do
    if roles and roles[role] then table.insert(labels, roleName(role)) end
  end
  return #labels > 0 and table.concat(labels, " + ") or "Unknown"
end

local function formatRolesWithIcons(roles)
  local labels = {}
  for _, role in ipairs(ROLE_ORDER) do
    if roles and roles[role] then table.insert(labels, roleIcon(role) .. roleName(role)) end
  end
  return #labels > 0 and table.concat(labels, " + ") or "Unknown"
end

local function fmtTime(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function makeBackdrop(target, opacity)
  target:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  target:SetBackdropColor(0.035, 0.045, 0.065, opacity or 0.94)
  target:SetBackdropBorderColor(0.35, 0.55, 0.85, 0.8)
end

local function makeButton(parent, label, width)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(label)
  return button
end

local TONE_COLORS = {
  primary = { 0.92, 0.82, 0.42 },
  active = { 0.35, 0.7, 1 },
  invited = { 1, 0.78, 0.25 },
  accepted = { 0.35, 0.9, 0.45 },
  declined = { 1, 0.38, 0.38 },
  full = { 1, 0.58, 0.22 },
  muted = { 0.72, 0.75, 0.82 },
}

local function setTone(fontString, tone)
  local color = TONE_COLORS[tone] or TONE_COLORS.muted
  fontString:SetTextColor(color[1], color[2], color[3])
end

local frame = CreateFrame("Frame", "QueueSimulatorFrame", UIParent, "BackdropTemplate")
frame:SetSize(330, 260)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
makeBackdrop(frame, 0.94)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -12)
title:SetText("QUEUE SIMULATOR")
local elapsedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
elapsedText:SetPoint("TOPRIGHT", -14, -15)
elapsedText:SetTextColor(0.72, 0.75, 0.82)

local applicationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
applicationLabel:SetPoint("TOPLEFT", 16, -43)
applicationLabel:SetText("Applications")
local applicationValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
applicationValue:SetPoint("TOPRIGHT", -16, -38)
setTone(applicationValue, "primary")

local divider = frame:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.3, 0.5, 0.8, 0.45)
divider:SetPoint("TOPLEFT", 14, -72)
divider:SetPoint("TOPRIGHT", -14, -72)
divider:SetHeight(1)

local floatingRows = {}
for index = 1, 8 do
  local column = (index - 1) % 2
  local row = math.floor((index - 1) / 2)
  local x = 16 + column * 158
  local y = -88 - row * 28
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", x, y)
  local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  value:SetPoint("TOPRIGHT", frame, "TOPLEFT", x + 140, y + 1)
  floatingRows[index] = { label = label, value = value }
end

local endButton = makeButton(frame, "End Session", 125)
endButton:SetPoint("BOTTOMLEFT", 14, 14)
local dashboardButton = makeButton(frame, "Dashboard", 125)
dashboardButton:SetPoint("BOTTOMRIGHT", -14, 14)

local dashboardFrame = CreateFrame("Frame", "QueueSimulatorDashboardFrame", UIParent, "BackdropTemplate")
dashboardFrame:SetSize(700, 520)
dashboardFrame:SetPoint("CENTER")
dashboardFrame:SetMovable(true)
dashboardFrame:EnableMouse(true)
dashboardFrame:RegisterForDrag("LeftButton")
dashboardFrame:SetScript("OnDragStart", dashboardFrame.StartMoving)
dashboardFrame:SetScript("OnDragStop", dashboardFrame.StopMovingOrSizing)
makeBackdrop(dashboardFrame, 0.98)
dashboardFrame:Hide()

local acceptedFrame = CreateFrame("Frame", "QueueSimulatorAcceptedFrame", UIParent, "BackdropTemplate,SecureHandlerStateTemplate")
acceptedFrame:SetSize(430, 436)
acceptedFrame:SetPoint("CENTER")
acceptedFrame:SetMovable(true)
acceptedFrame:EnableMouse(true)
acceptedFrame:RegisterForDrag("LeftButton")
acceptedFrame:SetScript("OnDragStart", function(self)
  if not InCombatLockdown() then self:StartMoving() end
end)
acceptedFrame:SetScript("OnDragStop", function(self)
  if not InCombatLockdown() then self:StopMovingOrSizing() end
end)
makeBackdrop(acceptedFrame, 0.98)
acceptedFrame:SetBackdropBorderColor(0.35, 0.9, 0.45, 0.9)
acceptedFrame:Hide()
-- Escape is handled by an unprotected proxy in Teleport.lua, never this protected parent.

local acceptedTitle = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
acceptedTitle:SetPoint("TOP", 0, -18)
acceptedTitle:SetText("ACCEPTED!")
setTone(acceptedTitle, "accepted")
local acceptedDungeon = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
acceptedDungeon:SetPoint("TOP", 0, -50)
acceptedDungeon:SetWidth(390)
local acceptedDestination = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
acceptedDestination:SetPoint("TOP", 0, -76)
acceptedDestination:SetWidth(390)
setTone(acceptedDestination, "primary")
local acceptedAppliedRoles = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
acceptedAppliedRoles:SetPoint("TOP", 0, -101)
acceptedAppliedRoles:SetTextColor(0.68, 0.72, 0.8)
local acceptedRole = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
acceptedRole:SetPoint("TOP", 0, -119)
acceptedRole:SetTextColor(0.68, 0.72, 0.8)
local acceptedDurationLabel = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
acceptedDurationLabel:SetPoint("TOPLEFT", 22, -149)
acceptedDurationLabel:SetText("Session time")
local acceptedDurationValue = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
acceptedDurationValue:SetPoint("TOPRIGHT", -22, -149)
setTone(acceptedDurationValue, "primary")
local acceptedDivider = acceptedFrame:CreateTexture(nil, "ARTWORK")
acceptedDivider:SetColorTexture(0.3, 0.7, 0.4, 0.45)
acceptedDivider:SetPoint("TOPLEFT", 18, -173)
acceptedDivider:SetPoint("TOPRIGHT", -18, -173)
acceptedDivider:SetHeight(1)

local acceptedStatRows = {}
for index = 1, 8 do
  local column = (index - 1) % 2
  local row = math.floor((index - 1) / 2)
  local x = 22 + column * 196
  local y = -194 - row * 29
  local label = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", x, y)
  local value = acceptedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  value:SetPoint("TOPRIGHT", acceptedFrame, "TOPLEFT", x + 172, y + 1)
  acceptedStatRows[index] = { label = label, value = value }
end

local acceptedTeleport = QueueSimulatorTeleport.attach(acceptedFrame)

local closeAcceptedButton = makeButton(acceptedFrame, "Close", 120)
closeAcceptedButton:SetPoint("BOTTOMLEFT", 34, 18)
closeAcceptedButton:SetScript("OnClick", function() acceptedTeleport:Close() end)
local acceptedDashboardButton = makeButton(acceptedFrame, "Open Dashboard", 150)
acceptedDashboardButton:SetPoint("BOTTOMRIGHT", -34, 18)

local dashboardTitle = dashboardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dashboardTitle:SetPoint("TOPLEFT", 18, -14)
dashboardTitle:SetText("QUEUE SIMULATOR DASHBOARD")

local summaryDefinitions = {
  { key = "sessions", label = "Sessions" },
  { key = "applications", label = "Applications" },
  { key = "accepted", label = "Accepted" },
  { key = "acceptanceRate", label = "Acceptance" },
  { key = "averageDuration", label = "Avg. session" },
}
local summaryCards = {}
for index, definition in ipairs(summaryDefinitions) do
  local card = CreateFrame("Frame", nil, dashboardFrame, "BackdropTemplate")
  card:SetSize(124, 58)
  card:SetPoint("TOPLEFT", 18 + (index - 1) * 133, -46)
  makeBackdrop(card, 0.55)
  card:SetBackdropBorderColor(0.2, 0.35, 0.58, 0.65)
  local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOP", 0, -8)
  label:SetText(definition.label)
  label:SetTextColor(0.68, 0.72, 0.8)
  local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  value:SetPoint("BOTTOM", 0, 8)
  setTone(value, definition.key == "accepted" and "accepted" or "primary")
  summaryCards[definition.key] = value
end

local outcomeDefinitions = {
  { key = "declined", label = "Declined", tone = "declined" },
  { key = "cancelled", label = "Withdrawn", tone = "muted" },
  { key = "declined_full", label = "Group full", tone = "full" },
  { key = "declined_delisted", label = "Delisted", tone = "muted" },
  { key = "timedout", label = "Expired", tone = "muted" },
  { key = "invited", label = "Invited", tone = "invited" },
  { key = "inviteaccepted", label = "Accepted", tone = "accepted" },
  { key = "failed", label = "Failed", tone = "muted" },
}
local lifetimeOutcomeValues = {}
for index, definition in ipairs(outcomeDefinitions) do
  local column = (index - 1) % 4
  local row = math.floor((index - 1) / 4)
  local x = 20 + column * 168
  local y = -122 - row * 25
  local label = dashboardFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(definition.label)
  local value = dashboardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  value:SetPoint("TOPLEFT", x + 105, y + 1)
  setTone(value, definition.tone)
  lifetimeOutcomeValues[definition.key] = value
end

local historyTitle = dashboardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
historyTitle:SetPoint("TOPLEFT", 20, -182)
historyTitle:SetText("RECENT SESSIONS")
local historyHint = dashboardFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
historyHint:SetPoint("TOPRIGHT", -34, -183)
historyHint:SetText("Click a session to show its outcome details")
historyHint:SetTextColor(0.58, 0.62, 0.7)

local statsScrollFrame = CreateFrame("ScrollFrame", nil, dashboardFrame, "UIPanelScrollFrameTemplate")
statsScrollFrame:SetPoint("TOPLEFT", 18, -205)
statsScrollFrame:SetPoint("BOTTOMRIGHT", -34, 52)
local statsScrollChild = CreateFrame("Frame", nil, statsScrollFrame)
statsScrollChild:SetSize(638, 1)
statsScrollFrame:SetScrollChild(statsScrollChild)
local expandedSessions = {}
local sessionRowFrames = {}

local refreshDashboard
local function clearSessionRows()
  for _, rowFrame in ipairs(sessionRowFrames) do rowFrame:Hide() end
end

local function acquireSessionRow(poolIndex)
  local rowFrame = sessionRowFrames[poolIndex]
  if rowFrame then return rowFrame end

  rowFrame = CreateFrame("Frame", nil, statsScrollChild, "BackdropTemplate")
  makeBackdrop(rowFrame, 0.45)
  rowFrame:SetBackdropBorderColor(0.18, 0.28, 0.45, 0.55)
  rowFrame.toggle = CreateFrame("Button", nil, rowFrame)
  rowFrame.toggle:SetPoint("TOPLEFT", 5, -4)
  rowFrame.toggle:SetPoint("TOPRIGHT", -5, -4)
  rowFrame.toggle:SetHeight(28)
  rowFrame.heading = rowFrame.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rowFrame.heading:SetPoint("LEFT", 7, 0)
  rowFrame.keyTitle = rowFrame.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rowFrame.keyTitle:SetPoint("LEFT", rowFrame.heading, "RIGHT", 6, 0)
  setTone(rowFrame.keyTitle, "primary")
  rowFrame.summary = rowFrame.toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rowFrame.summary:SetPoint("RIGHT", -7, 0)
  rowFrame.roles = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rowFrame.roles:SetPoint("TOPLEFT", 14, -42)
  rowFrame.roles:SetTextColor(0.68, 0.72, 0.8)
  rowFrame.details = {}
  for detailIndex = 0, 9 do
    local column = detailIndex % 4
    local detailRow = math.floor(detailIndex / 4)
    local x = 14 + column * 152
    local detailY = -67 - detailRow * 26
    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, detailY)
    local value = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPLEFT", x + 96, detailY + 1)
    rowFrame.details[detailIndex + 1] = { label = label, value = value }
  end
  sessionRowFrames[poolIndex] = rowFrame
  return rowFrame
end

local function createSessionRow(row, y, poolIndex)
  local expanded = expandedSessions[row.index] == true
  local height = expanded and 158 or 38
  local rowFrame = acquireSessionRow(poolIndex)
  rowFrame:ClearAllPoints()
  rowFrame:SetPoint("TOPLEFT", 0, -y)
  rowFrame:SetSize(630, height)
  rowFrame:Show()
  local rowTitle = roleIcon(row.acceptedRole) .. (row.destination or string.format("Session #%d", row.index))
  rowFrame.heading:SetText(string.format("%s  %s", expanded and "–" or "+", rowTitle))
  rowFrame.keyTitle:SetText(recentKeyTitles[row.index])
  rowFrame.keyTitle:SetShown(row.acceptedKeyLevel == nil and recentKeyTitleAvailable[row.index] == true)
  rowFrame.summary:SetText(string.format("%d applications   %s   %d accepted", row.applications, fmtTime(row.duration), row.accepted))
  rowFrame.roles:SetText(string.format("Applied as: %s    Accepted as: %s", formatRoles(row.appliedRoles), roleName(row.acceptedRole)))
  rowFrame.roles:SetShown(expanded and row.reason == "accepted")
  rowFrame.toggle:SetScript("OnClick", function()
    expandedSessions[row.index] = not expanded
    refreshDashboard()
  end)

  for index = 2, #row.stats do
    local stat = row.stats[index]
    local detail = rowFrame.details[index - 1]
    detail.label:SetText(stat.label)
    detail.value:SetText(stat.value)
    setTone(detail.value, stat.tone)
    detail.label:SetShown(expanded)
    detail.value:SetShown(expanded)
  end
  return height
end

local emptyHistory = statsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
emptyHistory:SetPoint("TOPLEFT", 8, -12)
emptyHistory:SetText("No completed sessions yet. Start applying to Mythic+ groups to begin tracking.")
emptyHistory:Hide()

refreshDashboard = function()
  local db = QueueSimulatorAccountDB
  local summary = Core.lifetimeSummary(db)
  summaryCards.sessions:SetText(summary.sessions)
  summaryCards.applications:SetText(summary.applications)
  summaryCards.accepted:SetText(summary.accepted)
  summaryCards.acceptanceRate:SetText(string.format("%.1f%%", summary.acceptanceRate))
  summaryCards.averageDuration:SetText(fmtTime(summary.averageDuration))
  for _, definition in ipairs(outcomeDefinitions) do
    lifetimeOutcomeValues[definition.key]:SetText(db[definition.key] or 0)
  end

  clearSessionRows()
  local rows = Core.historyRows(db.sessionHistory, 50)
  emptyHistory:SetShown(#rows == 0)
  local y = 0
  for index, row in ipairs(rows) do y = y + createSessionRow(row, y, index) + 6 end
  statsScrollChild:SetHeight(math.max(statsScrollFrame:GetHeight(), y))
end

local function showDashboard()
  refreshDashboard()
  dashboardFrame:Show()
  dashboardFrame:Raise()
end

local ACCEPTED_STAT_INDICES = { 1, 3, 4, 5, 6, 7, 8, 9 }
local function showAcceptedPopup(groupName, instanceMapID)
  local session = tracker.session
  local duration = tracker:elapsed(GetTime())
  local stats = Core.sessionStats(session)
  acceptedTeleport:Show(instanceMapID, function()
  acceptedDungeon:SetText(session.acceptedDungeon or "Mythic+ dungeon")
  acceptedDestination:SetText(groupName)
  acceptedAppliedRoles:SetText(string.format("Applied as: %s", formatRolesWithIcons(session.appliedRoles)))
  acceptedRole:SetText(string.format("Accepted as: %s%s", roleIcon(session.acceptedRole), roleName(session.acceptedRole)))
  acceptedDurationValue:SetText(fmtTime(duration))
  for rowIndex, statIndex in ipairs(ACCEPTED_STAT_INDICES) do
    local stat = stats[statIndex]
    local row = acceptedStatRows[rowIndex]
    row.label:SetText(stat.label)
    row.value:SetText(stat.value)
    setTone(row.value, stat.tone)
  end
  end)
end

acceptedDashboardButton:SetScript("OnClick", function()
  showDashboard()
end)

local function refresh()
  local stats = Core.sessionStats(tracker.session)
  applicationValue:SetText(stats[1].value)
  elapsedText:SetText(fmtTime(tracker:elapsed(GetTime())))
  for index = 2, #stats do
    local row = floatingRows[index - 1]
    row.label:SetText(stats[index].label)
    row.value:SetText(stats[index].value)
    setTone(row.value, stats[index].tone)
  end
  endButton:SetEnabled(tracker.session.startedAt ~= nil and not tracker.session.ended)
end

local closeDashboard = makeButton(dashboardFrame, "Close", 90)
closeDashboard:SetPoint("BOTTOMRIGHT", -14, 14)
closeDashboard:SetScript("OnClick", function() dashboardFrame:Hide() end)
local clearHistoryButton = makeButton(dashboardFrame, "Clear History", 110)
clearHistoryButton:SetPoint("BOTTOMLEFT", 14, 14)
StaticPopupDialogs.QUEUESIMULATOR_CLEAR_HISTORY = {
  text = "Clear all completed M+ session history?\nLifetime totals will not be changed.",
  button1 = "Clear History",
  button2 = "Cancel",
  OnAccept = function()
    tracker:clearHistory()
    recentKeyTitles = {}
    recentKeyTitleAvailable = {}
    refreshDashboard()
    print("Queue Simulator: session history cleared. Lifetime totals were kept.")
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
clearHistoryButton:SetScript("OnClick", function()
  StaticPopup_Show("QUEUESIMULATOR_CLEAR_HISTORY")
end)
local resetLifetimeButton = makeButton(dashboardFrame, "Reset Lifetime", 115)
resetLifetimeButton:SetPoint("BOTTOM", 0, 14)
StaticPopupDialogs.QUEUESIMULATOR_RESET_LIFETIME = {
  text = "Reset all lifetime M+ tracker data?\nThis clears lifetime totals, history, and the current session.",
  button1 = "Reset Lifetime",
  button2 = "Cancel",
  OnAccept = function()
    tracker:resetLifetime()
    pendingApplicationDetails = {}
    acceptedTeleport:Close()
    recentKeyTitles = {}
    recentKeyTitleAvailable = {}
    active = tracker.session.active
    frame:Hide()
    refresh()
    refreshDashboard()
    print("Queue Simulator: lifetime totals, history, and current session reset.")
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
resetLifetimeButton:SetScript("OnClick", function()
  StaticPopup_Show("QUEUESIMULATOR_RESET_LIFETIME")
end)

endButton:SetScript("OnClick", function()
  if tracker:endSession(GetTime(), "manual") then
    frame:Hide()
    refresh()
    refreshDashboard()
    print("Queue Simulator: session ended and saved to history.")
  end
end)
dashboardButton:SetScript("OnClick", showDashboard)

local TERMINAL = {
  declined = true, cancelled = true, declined_full = true,
  declined_delisted = true, timedout = true, failed = true,
  inviteaccepted = true, invitedeclined = true,
}

local function selectedRoles(tank, healer, damage)
  return {
    TANK = tank == true,
    HEALER = healer == true,
    DAMAGER = damage == true,
  }
end

local function getApplicationRole(searchResultID)
  if not C_LFGList or not C_LFGList.GetApplicationInfo then return nil end
  local applicationInfo, _, _, _, role = C_LFGList.GetApplicationInfo(searchResultID)
  if type(applicationInfo) == "table" then role = applicationInfo.role end
  if role == "NONE" then return nil end
  return role
end

local function inspectApplication(searchResultID, appliedRoles)
  local details = {
    appliedRoles = appliedRoles,
    role = getApplicationRole(searchResultID),
  }
  if not C_LFGList or not C_LFGList.GetSearchResultInfo then return false, details end
  local info = C_LFGList.GetSearchResultInfo(searchResultID)
  if not info then return false, details end
  local activityID = info.activityID
  if not activityID and info.activityIDs then activityID = info.activityIDs[1] end
  if not activityID or not C_LFGList.GetActivityInfoTable then return false, details end
  local activity = C_LFGList.GetActivityInfoTable(activityID)
  if not activity then return false, details end
  local activityGroupID = activity.groupFinderActivityGroupID
  local activityGroupName
  if activityGroupID and C_LFGList.GetActivityGroupInfo then
    activityGroupName = C_LFGList.GetActivityGroupInfo(activityGroupID)
  end
  lastInspection = {
    activityID = activityID,
    shortName = activity.shortName,
    fullName = activity.fullName,
    activityGroupID = activityGroupID,
    activityGroupName = activityGroupName,
    mapID = activity.mapID,
  }
  local unambiguous = not info.activityIDs or #info.activityIDs == 1
  if unambiguous and not (issecretvalue and issecretvalue(activity.mapID)) and type(activity.mapID) == "number" then
    details.instanceMapID = activity.mapID
  end
  details.dungeon = activity.fullName or activity.shortName or activityGroupName
  local parsed, keyLevel = pcall(Core.parseKeyLevel, info.name)
  if parsed then details.keyLevel = keyLevel end
  return activity.isMythicPlusActivity == true, details
end

if hooksecurefunc and C_LFGList and C_LFGList.ApplyToGroup then
  hooksecurefunc(C_LFGList, "ApplyToGroup", function(searchResultID, tank, healer, damage)
    local isMythicPlus, details = inspectApplication(searchResultID, selectedRoles(tank, healer, damage))
    if not isMythicPlus then
      pendingApplicationDetails[searchResultID] = nil
      return
    end
    pendingApplicationDetails[searchResultID] = details
    if C_Timer and C_Timer.After then
      C_Timer.After(60, function()
        if pendingApplicationDetails[searchResultID] == details then pendingApplicationDetails[searchResultID] = nil end
      end)
    end
  end)
end

local function markApplication(searchResultID, details)
  pendingApplicationDetails[searchResultID] = nil
  if tracker:applicationApplied(GetTime(), searchResultID, details) then
    active = tracker.session.active
    active[searchResultID] = true
    frame:Show()
    return true
  end
  return false
end

local function syncPendingApplications()
  if not C_LFGList or not C_LFGList.GetApplications then return end
  local raw = { C_LFGList.GetApplications() }
  local applications = raw
  local changed = false
  if type(raw[1]) == "table" then applications = raw[1] end
  for _, searchResultID in ipairs(applications) do
    if not active[searchResultID] then
      local isMythicPlus, details = inspectApplication(searchResultID)
      if isMythicPlus then
        local info = C_LFGList.GetApplicationInfo and C_LFGList.GetApplicationInfo(searchResultID)
        local status = info
        if type(info) == "table" then status = info.applicationStatus or info.pendingApplicationStatus end
        if status == "applied" or status == "pending" then
          changed = markApplication(searchResultID, details) or changed
        end
      end
    end
  end
  refresh()
  if changed and dashboardFrame:IsShown() then refreshDashboard() end
end

local function onApplicationStatus(_, searchResultID, newStatus, _, groupName)
  local changed = false
  if newStatus == "applied" then
    local details = pendingApplicationDetails[searchResultID]
    if details then
      changed = markApplication(searchResultID, details)
    else
      local isMythicPlus, inspectedDetails = inspectApplication(searchResultID)
      if isMythicPlus then changed = markApplication(searchResultID, inspectedDetails) end
    end
    pendingApplicationDetails[searchResultID] = nil
  elseif newStatus == "invited" and active[searchResultID] then
    pendingApplicationDetails[searchResultID] = nil
    local details = tracker.session.applicationDetails and tracker.session.applicationDetails[searchResultID]
    if details then details.role = getApplicationRole(searchResultID) or details.role end
    changed = tracker:applicationOutcome(searchResultID, newStatus, GetTime())
  elseif TERMINAL[newStatus] and active[searchResultID] then
    pendingApplicationDetails[searchResultID] = nil
    if newStatus == "inviteaccepted" then
      local details = tracker.session.applicationDetails and tracker.session.applicationDetails[searchResultID]
      if details then
        details.role = getApplicationRole(searchResultID) or details.role
        if not details.keyLevel then
          local parsed, keyLevel = pcall(Core.parseKeyLevel, groupName)
          if parsed then details.keyLevel = keyLevel end
        end
      end
    end
    local acceptedDetails = tracker.session.applicationDetails and tracker.session.applicationDetails[searchResultID]
    local instanceMapID = acceptedDetails and acceptedDetails.instanceMapID
    if tracker:applicationOutcome(searchResultID, newStatus, GetTime()) then
      changed = true
      active[searchResultID] = nil
      if tracker.session.ended then frame:Hide() end
      if newStatus == "inviteaccepted" then
        local historyIndex = #(QueueSimulatorAccountDB.sessionHistory or {})
        recentKeyTitles[historyIndex] = groupName
        recentKeyTitleAvailable[historyIndex] = true
        showAcceptedPopup(groupName, instanceMapID)
      end
    end
  elseif TERMINAL[newStatus] or newStatus == "invited" then
    pendingApplicationDetails[searchResultID] = nil
  end
  refresh()
  if changed and dashboardFrame:IsShown() then refreshDashboard() end
end

frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(1, syncPendingApplications)
  else
    onApplicationStatus(event, ...)
  end
end)
frame:SetScript("OnUpdate", function(_, elapsed)
  frame._refreshTimer = (frame._refreshTimer or 0) + elapsed
  if frame._refreshTimer >= 1 then
    frame._refreshTimer = 0
    syncPendingApplications()
  end
end)

SLASH_QUEUESIMULATOR1 = "/qsim"
SlashCmdList.QUEUESIMULATOR = function(message)
  message = string.lower(message or "")
  if message == "reset" then
    tracker:resetSession()
    active = tracker.session.active
    pendingApplicationDetails = {}
    acceptedTeleport:Close()
    refresh()
    print("Queue Simulator: session reset.")
  elseif message == "end" then
    if tracker:endSession(GetTime(), "manual") then
      frame:Hide()
      refresh()
      refreshDashboard()
      print("Queue Simulator: session ended and saved to history.")
    else
      print("Queue Simulator: no active session to end.")
    end
  elseif message == "history" or message == "stats" then
    showDashboard()
  elseif message == "hide" then
    frame:Hide()
  elseif message == "show" then
    frame:Show(); refresh()
  elseif message == "" then
    showDashboard()
  elseif message == "status" then
    local stats = Core.sessionStats(tracker.session)
    print(string.format(
      "Queue Simulator: %d applications, %d active, %d invited, %d accepted, %s elapsed.",
      stats[1].value, stats[2].value, stats[3].value, stats[4].value,
      fmtTime(tracker:elapsed(GetTime()))))
  elseif message == "debug" then
    local activeCount = Core.activeCount(tracker.session.active)
    print(string.format("Queue Simulator debug: session=%d startedAt=%s ended=%s active=%d charSaved=%s accountSaved=%s visible=%s", tracker.session.applications, tostring(tracker.session.startedAt), tostring(tracker.session.ended), activeCount, tostring(QueueSimulatorCharacterDB.mpatSessionStartedAt), tostring(QueueSimulatorAccountDB.mpatSessionStartedAt), tostring(frame:IsShown())))
    if lastInspection then
      print(string.format(
        "Queue Simulator activity: id=%s short=%s full=%s groupID=%s group=%s mapID=%s",
        tostring(lastInspection.activityID), tostring(lastInspection.shortName), tostring(lastInspection.fullName),
        tostring(lastInspection.activityGroupID), tostring(lastInspection.activityGroupName),
        tostring(lastInspection.mapID)))
    end
  else
    print("Queue Simulator: /qsim, /qsim status, /qsim show, /qsim hide, /qsim end, /qsim reset, /qsim history, /qsim stats, /qsim debug")
  end
end

if tracker.session.startedAt and not tracker.session.ended then
  frame:Show()
else
  frame:Hide()
end
refresh()
print("Queue Simulator loaded. Type /qsim to open the dashboard.")
