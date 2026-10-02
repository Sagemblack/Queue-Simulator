local Core = dofile("QueueSimulator/Core.lua")

local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error((label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, label)
  if not value then error(label or "expected true") end
end

local function newTracker()
  local character = {}
  local account = {}
  return Core.new(character, account), character, account
end

local tracker, character, account = newTracker()
assertEqual(tracker:sessionTotal(), 0, "empty session total")
assertEqual(tracker:elapsed(100), 0, "empty elapsed")

tracker:applicationApplied(100, "key-1")
assertEqual(tracker:sessionTotal(), 1, "first application")
assertEqual(tracker:elapsed(160), 60, "session timer")
assertEqual(character.totalApplications, 1, "character lifetime applications")
assertEqual(account.totalApplications, 1, "account lifetime applications")

tracker:applicationApplied(200, "key-2")
assertEqual(tracker:sessionTotal(), 2, "second application")
tracker:applicationOutcome("key-1", "declined")
tracker:applicationOutcome("key-2", "declined_full")
assertEqual(tracker.session.declined, 1, "declined count")
assertEqual(tracker.session.declined_full, 1, "full count")
assertEqual(tracker:sessionTotal(), 2, "terminal outcomes remain in total")

tracker:applicationApplied(300, "key-3")
tracker:applicationOutcome("key-3", "cancelled")
assertEqual(tracker.session.cancelled, 1, "cancelled count")
assertEqual(tracker:sessionTotal(), 3, "cancelled included")

tracker:applicationApplied(350, "pending-key")
local restored = Core.new(character, account)
assertEqual(restored:sessionTotal(), 4, "session survives reload")
assertEqual(restored.session.active["pending-key"], true, "active application survives reload")
assertEqual(restored:elapsed(400), 300, "restored timer")
tracker = restored

tracker:applicationOutcome("pending-key", "declined", 450)
tracker:applicationApplied(500, "key-4")
tracker:applicationOutcome("key-4", "inviteaccepted", 700)
assertTrue(tracker.session.ended, "accepted invite ends session")
assertEqual(tracker.session.accepted, 1, "accepted count")
assertEqual(tracker:elapsed(999), 600, "timer stops at acceptance")
assertEqual(#character.sessionHistory, 1, "accepted session history")
assertEqual(character.sessionHistory[1].accepted, 1, "accepted session history outcome")
assertEqual(character.totalSessionTime, 600, "accepted duration added to character lifetime time")
assertEqual(account.totalSessionTime, 600, "accepted duration added to account lifetime time")

local invitedTracker = newTracker()
invitedTracker:applicationApplied(100, "invited-key")
invitedTracker:applicationOutcome("invited-key", "invited", 150)
assertTrue(invitedTracker.session.active["invited-key"], "invited application remains active")
assertTrue(not invitedTracker.session.ended, "invited status does not end session")
invitedTracker:applicationOutcome("invited-key", "inviteaccepted", 200)
assertTrue(invitedTracker.session.ended, "accepted invitation after invited ends session")

local metadataTracker, metadataCharacter, metadataAccount = newTracker()
metadataTracker:applicationApplied(100, "metadata-key", {
  dungeon = "Priory of the Sacred Flame",
  keyLevel = 12,
  appliedRoles = { TANK = true, DAMAGER = true },
  role = "DAMAGER",
})
local metadataRestored = Core.new(metadataCharacter, metadataAccount)
assertEqual(metadataRestored.session.applicationDetails["metadata-key"].dungeon, "Priory of the Sacred Flame", "application dungeon survives reload")
assertEqual(metadataRestored.session.applicationDetails["metadata-key"].keyLevel, 12, "application key level survives reload")
assertTrue(metadataRestored.session.applicationDetails["metadata-key"].appliedRoles.TANK, "applied tank role survives reload")
assertTrue(metadataRestored.session.applicationDetails["metadata-key"].appliedRoles.DAMAGER, "applied damage role survives reload")
assertEqual(metadataRestored.session.applicationDetails["metadata-key"].role, "DAMAGER", "application role survives reload")
metadataRestored:applicationOutcome("metadata-key", "invited", 150)
metadataRestored:applicationOutcome("metadata-key", "inviteaccepted", 200)
assertEqual(metadataRestored.session.acceptedDungeon, "Priory of the Sacred Flame", "accepted session keeps dungeon")
assertEqual(metadataRestored.session.acceptedKeyLevel, 12, "accepted session keeps key level")
assertTrue(metadataRestored.session.appliedRoles.TANK, "accepted session keeps applied tank role")
assertTrue(metadataRestored.session.appliedRoles.DAMAGER, "accepted session keeps applied damage role")
assertEqual(metadataRestored.session.acceptedRole, "DAMAGER", "accepted session keeps role")
assertEqual(metadataCharacter.sessionHistory[1].acceptedDungeon, "Priory of the Sacred Flame", "accepted history keeps dungeon")
assertEqual(metadataCharacter.sessionHistory[1].acceptedKeyLevel, 12, "accepted history keeps key level")
assertTrue(metadataCharacter.sessionHistory[1].appliedRoles.TANK, "accepted history keeps applied tank role")
assertTrue(metadataCharacter.sessionHistory[1].appliedRoles.DAMAGER, "accepted history keeps applied damage role")
assertEqual(metadataCharacter.sessionHistory[1].acceptedRole, "DAMAGER", "accepted history keeps role")
local metadataHistoryRows = Core.historyRows(metadataCharacter.sessionHistory, 1)
assertEqual(metadataHistoryRows[1].destination, "Priory of the Sacred Flame +12", "accepted history row exposes destination")
assertTrue(metadataHistoryRows[1].appliedRoles.TANK, "accepted history row exposes applied tank role")
assertTrue(metadataHistoryRows[1].appliedRoles.DAMAGER, "accepted history row exposes applied damage role")
assertEqual(metadataHistoryRows[1].acceptedRole, "DAMAGER", "accepted history row exposes role")

assertEqual(Core.parseKeyLevel("+12"), 12, "plain generated key level")
assertEqual(Core.parseKeyLevel("Priory + 10"), 10, "key level with whitespace")
assertEqual(Core.parseKeyLevel("Mythic +7 chill"), 7, "key level inside listing title")
assertEqual(Core.parseKeyLevel("Weekly no leavers"), nil, "listing without key level")
assertEqual(Core.parseKeyLevel("2+2"), nil, "arithmetic-like listing is not a key level")
assertEqual(Core.parseKeyLevel("+0"), nil, "zero key level rejected")
assertEqual(Core.parseKeyLevel("+100"), nil, "out-of-range key level rejected")
assertEqual(Core.parseKeyLevel(12), nil, "non-string key level source rejected")
assertEqual(Core.acceptedDestination({ acceptedDungeon = "Priory", acceptedKeyLevel = 12 }), "Priory +12", "accepted destination with key")
assertEqual(Core.acceptedDestination({ acceptedDungeon = "Priory" }), "Priory", "accepted destination without key")
assertEqual(Core.acceptedDestination({}), "Mythic+ group", "accepted destination fallback")

tracker:resetSession()
assertEqual(tracker:sessionTotal(), 0, "reset session")
assertEqual(character.totalApplications, 5, "reset does not erase lifetime")
assertEqual(account.totalApplications, 5, "reset does not erase account lifetime")

tracker:applicationApplied(1000, "key-5")
assertEqual(tracker:sessionTotal(), 1, "new session starts after accepted invite")
assertEqual(tracker:elapsed(1010), 10, "new session timer")
tracker:endSession(1100, "manual")
assertTrue(tracker.session.ended, "manual end")
assertEqual(#character.sessionHistory, 2, "manual session history")
assertEqual(character.sessionHistory[2].reason, "manual", "manual history reason")
assertEqual(tracker:elapsed(9999), 100, "manual timer stops")
assertEqual(character.totalSessionTime, 700, "completed session durations add together")
assertEqual(account.totalSessionTime, 700, "account completed session durations add together")
tracker:clearHistory()
assertEqual(#character.sessionHistory, 0, "character history clears")
assertEqual(#account.sessionHistory, 0, "account history clears")
assertEqual(character.totalSessions, 2, "clearing history keeps character completed session count")
assertEqual(account.totalSessions, 2, "clearing history keeps account completed session count")
assertEqual(Core.lifetimeSummary(account).averageDuration, 350, "clearing history keeps lifetime average duration")
assertEqual(character.totalApplications, 6, "clearing history keeps lifetime")
assertEqual(account.totalSessionTime, 700, "clearing history keeps lifetime session time")
tracker:resetLifetime()
assertEqual(character.totalApplications, 0, "lifetime reset character")
assertEqual(account.totalApplications, 0, "lifetime reset account")
assertEqual(tracker:sessionTotal(), 0, "lifetime reset session")
assertEqual(account.totalSessionTime, 0, "lifetime reset clears session time")

local floatingStats = Core.sessionStats({
  applications = 14,
  active = { one = true, two = true, three = true },
  declined = 3,
  cancelled = 1,
  declined_full = 2,
  declined_delisted = 1,
  timedout = 1,
  invited = 2,
  accepted = 1,
})
assertEqual(#floatingStats, 9, "floating tracker has applications plus eight non-overlapping statistics")
assertEqual(floatingStats[1].key, "applications", "applications lead floating tracker")
assertEqual(floatingStats[1].value, 14, "application value")
assertEqual(floatingStats[2].key, "active", "active applications are prominent")
assertEqual(floatingStats[2].value, 3, "active count derives from active IDs")
assertEqual(floatingStats[3].key, "invited", "invites precede terminal outcomes")
assertEqual(floatingStats[4].key, "accepted", "acceptances are prominent")
assertEqual(floatingStats[5].key, "declined", "declined remains raw declined only")
assertEqual(floatingStats[7].key, "declined_delisted", "delisted stays separate")
assertEqual(floatingStats[8].key, "timedout", "expired remains visible at zero or above")
assertEqual(floatingStats[9].key, "cancelled", "withdrawn remains visible at zero or above")

local dashboardSummary = Core.lifetimeSummary({
  totalApplications = 40,
  totalSessionTime = 900,
  inviteaccepted = 4,
  invited = 7,
  sessionHistory = { {}, {}, {} },
})
assertEqual(dashboardSummary.sessions, 3, "dashboard completed session count")
assertEqual(dashboardSummary.applications, 40, "dashboard lifetime applications")
assertEqual(dashboardSummary.accepted, 4, "dashboard accepted applications")
assertEqual(dashboardSummary.invited, 7, "dashboard invitations")
assertEqual(dashboardSummary.acceptanceRate, 10, "dashboard acceptance percentage")
assertEqual(dashboardSummary.averageDuration, 300, "dashboard average session duration")

local dashboardEmpty = Core.lifetimeSummary({})
assertEqual(dashboardEmpty.acceptanceRate, 0, "empty dashboard acceptance percentage")
assertEqual(dashboardEmpty.averageDuration, 0, "empty dashboard average duration")

local historyRows = Core.historyRows({
  { applications = 5, duration = 60, accepted = 0, reason = "manual" },
  { applications = 8, duration = 120, accepted = 1, reason = "accepted" },
  { applications = 12, duration = 180, accepted = 0, reason = "manual" },
}, 2)
assertEqual(#historyRows, 2, "dashboard history limit")
assertEqual(historyRows[1].index, 3, "newest session appears first")
assertEqual(historyRows[1].applications, 12, "newest session application count")
assertEqual(historyRows[2].index, 2, "second newest session follows")
assertEqual(historyRows[2].accepted, 1, "history accepted result")
assertEqual(#historyRows[1].stats, 11, "history details include all tracked non-overlapping outcomes")
assertEqual(historyRows[1].stats[10].key, "failed", "history details include failed outcomes")
assertEqual(historyRows[1].stats[11].key, "invitedeclined", "history details include declined invitations")

local addonFile = assert(io.open("QueueSimulator/Addon.lua", "r"))
local addonSource = addonFile:read("*a")
addonFile:close()
assertTrue(addonSource:find('SLASH_QUEUESIMULATOR1 = "/qsim"', 1, true), "qsim slash command registered")
assertTrue(not addonSource:find('SLASH_QUEUESIMULATOR2', 1, true), "no second slash alias registered")
assertTrue(not addonSource:find('"/mtracker', 1, true), "mtracker slash command removed")
assertTrue(not addonSource:find('"/mplus', 1, true), "mplus slash command removed")
assertTrue(addonSource:find('"UIPanelScrollFrameTemplate"', 1, true), "statistics scroll frame created")
assertTrue(addonSource:find("statsScrollChild = CreateFrame(\"Frame\", nil, statsScrollFrame)", 1, true), "statistics scroll child frame created")
assertTrue(addonSource:find("statsScrollFrame:SetScrollChild(statsScrollChild)", 1, true), "statistics child frame is scroll child")
assertTrue(addonSource:find("CreateFrame(\"Frame\", nil, statsScrollChild", 1, true), "expandable session rows are inside scroll child")
assertTrue(addonSource:find("frame:Hide()", 1, true), "tracker hidden during initialization")
assertTrue(addonSource:find("dashboardFrame:Hide()", 1, true), "dashboard hidden during initialization")
assertTrue(addonSource:find("summaryCards.averageDuration:SetText", 1, true), "dashboard shows average session duration")
assertTrue(not addonSource:find("Leader declined", 1, true), "outcome display has no overlapping leader-declined breakdown")
assertTrue(not addonSource:find("Core.declineTotal", 1, true), "declined display uses only the raw declined outcome")
assertTrue(addonSource:find("Core.sessionStats", 1, true), "floating tracker uses shared session statistics")
assertTrue(addonSource:find("Core.lifetimeSummary", 1, true), "dashboard uses shared lifetime summary")
assertTrue(addonSource:find("Core.historyRows", 1, true), "dashboard uses newest-first history rows")
assertTrue(addonSource:find("dashboardFrame:SetSize(700, 520)", 1, true), "manual dashboard is larger than floating tracker")
assertTrue(addonSource:find("local expandedSessions = {}", 1, true), "dashboard supports expandable history rows")
assertTrue(addonSource:find('if message == "" then', 1, true), "bare qsim command has a dedicated dashboard action")
assertTrue(addonSource:find("showDashboard()", 1, true), "bare qsim command can open dashboard")
assertTrue(addonSource:find("if changed and dashboardFrame:IsShown() then refreshDashboard() end", 1, true), "open dashboard refreshes after live data changes")
assertTrue(not addonSource:find('"Applications: %d\\nTime:', 1, true), "floating statistics are not rendered as one text block")
assertTrue(addonSource:find("Type /qsim to open the dashboard.", 1, true), "load message describes bare qsim behavior")
assertTrue(addonSource:find("/qsim end", 1, true), "fallback help includes end command")
assertTrue(addonSource:find("/qsim history, /qsim stats", 1, true), "fallback help includes both dashboard aliases")
assertTrue(not addonSource:find("Type /qsim for help.", 1, true), "obsolete qsim help message removed")
assertTrue(addonSource:find('"QueueSimulatorAcceptedFrame"', 1, true), "accepted popup frame created")
assertTrue(addonSource:find("local function inspectApplication", 1, true), "application metadata inspected before result disappears")
assertTrue(addonSource:find("details.dungeon = activity.fullName or activity.shortName or activityGroupName", 1, true), "accepted dungeon uses Blizzard's activity name")
assertTrue(not addonSource:find("C_Map.GetMapInfo(activity.mapID)", 1, true), "activity map ID is not treated as a UI map ID")
assertTrue(addonSource:find("pendingApplicationDetails[searchResultID] = details", 1, true), "signup metadata cached for the application event")
assertTrue(addonSource:find("Core.parseKeyLevel", 1, true), "listing key level parsed through tested helper")
assertTrue(addonSource:find("acceptedDestination:SetText(groupName)", 1, true), "accepted popup renders the acceptance event title")
assertTrue(addonSource:find('acceptedDungeon:SetText(session.acceptedDungeon or "Mythic+ dungeon")', 1, true), "accepted popup renders cached dungeon separately")
assertTrue(addonSource:find("local function showAcceptedPopup", 1, true), "accepted popup renderer created")
assertTrue(addonSource:find("recentKeyTitles[historyIndex] = groupName", 1, true), "accepted event title is retained for recent-session display")
assertTrue(addonSource:find("showAcceptedPopup(groupName, instanceMapID)", 1, true), "accepted popup opens with event title and cached numeric identity after accepted outcome is recorded")
assertTrue(addonSource:find("row.destination", 1, true), "accepted destination appears in dashboard history")

print("all core tests passed")
