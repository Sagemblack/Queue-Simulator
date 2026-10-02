local M = {}

local OUTCOMES = {
  "declined",
  "cancelled",
  "declined_full",
  "declined_delisted",
  "timedout",
  "failed",
  "invited",
  "inviteaccepted",
  "invitedeclined",
}

local function ensureTotals(store)
  store.totalApplications = store.totalApplications or 0
  if store.totalSessions == nil then
    store.totalSessions = #(store.sessionHistory or {})
  end
  if store.totalSessionTime == nil then
    store.totalSessionTime = 0
    for _, session in ipairs(store.sessionHistory or {}) do
      store.totalSessionTime = store.totalSessionTime + (session.duration or 0)
    end
  end
  for _, outcome in ipairs(OUTCOMES) do
    store[outcome] = store[outcome] or 0
  end
end

local function copyActive(source)
  local active = {}
  for applicationID, value in pairs(source or {}) do active[applicationID] = value end
  return active
end

local function copyRoles(source)
  local roles = {}
  if type(source) ~= "table" then return roles end
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    if source[role] == true then roles[role] = true end
  end
  return roles
end

local function copyApplicationDetail(detail)
  if type(detail) ~= "table" then return nil end
  return {
    dungeon = detail.dungeon,
    instanceMapID = detail.instanceMapID,
    keyLevel = detail.keyLevel,
    appliedRoles = copyRoles(detail.appliedRoles),
    role = detail.role,
  }
end

local function copyApplicationDetails(source)
  local details = {}
  for applicationID, detail in pairs(source or {}) do
    details[applicationID] = copyApplicationDetail(detail)
  end
  return details
end

local function restoreSession(store)
  local startedAt = store and (store.mpatSessionStartedAt or store.startedAt)
  if not startedAt then
    return { applications = 0, active = {}, applicationDetails = {}, ended = false }
  end
  local ended = store.mpatSessionEnded
  if ended == nil then ended = store.ended == true end
  return {
    applications = store.mpatSessionApplications or store.applications or 0,
    active = copyActive(store.mpatSessionActive or store.active),
    applicationDetails = copyApplicationDetails(store.mpatSessionApplicationDetails or store.applicationDetails),
    startedAt = startedAt,
    endedAt = store.mpatSessionEndedAt or store.endedAt,
    ended = ended,
    recorded = store.mpatSessionRecorded or store.recorded == true,
    declined = store.mpatSessionDeclined or store.declined or 0,
    cancelled = store.mpatSessionCancelled or store.cancelled or 0,
    declined_full = store.mpatSessionDeclinedFull or store.declined_full or 0,
    declined_delisted = store.mpatSessionDeclinedDelisted or store.declined_delisted or 0,
    timedout = store.mpatSessionTimedout or store.timedout or 0,
    failed = store.mpatSessionFailed or store.failed or 0,
    invited = store.mpatSessionInvited or store.invited or 0,
    inviteaccepted = store.mpatSessionInviteAccepted or store.inviteaccepted or 0,
    accepted = store.mpatSessionAccepted or store.accepted or 0,
    invitedeclined = store.mpatSessionInviteDeclined or store.invitedeclined or 0,
    acceptedDungeon = store.mpatSessionAcceptedDungeon or store.acceptedDungeon,
    acceptedKeyLevel = store.mpatSessionAcceptedKeyLevel or store.acceptedKeyLevel,
    appliedRoles = copyRoles(store.mpatSessionAppliedRoles or store.appliedRoles),
    acceptedRole = store.mpatSessionAcceptedRole or store.acceptedRole,
  }
end

local function saveSession(store, session)
  if not store then return end
  store.mpatSessionApplications = session.applications
  store.mpatSessionActive = copyActive(session.active)
  store.mpatSessionApplicationDetails = copyApplicationDetails(session.applicationDetails)
  store.mpatSessionStartedAt = session.startedAt
  store.mpatSessionEndedAt = session.endedAt
  store.mpatSessionEnded = session.ended
  store.mpatSessionRecorded = session.recorded == true
  store.mpatSessionAccepted = session.accepted or 0
  store.mpatSessionAcceptedDungeon = session.acceptedDungeon
  store.mpatSessionAcceptedKeyLevel = session.acceptedKeyLevel
  store.mpatSessionAppliedRoles = copyRoles(session.appliedRoles)
  store.mpatSessionAcceptedRole = session.acceptedRole
  for _, outcome in ipairs(OUTCOMES) do
    store["mpatSession" .. outcome] = session[outcome] or 0
  end
  -- Keep the nested form for compatibility with the previous 0.1.x builds.
  store.applications = session.applications
  store.active = copyActive(session.active)
  store.applicationDetails = copyApplicationDetails(session.applicationDetails)
  store.startedAt = session.startedAt
  store.endedAt = session.endedAt
  store.ended = session.ended
  store.recorded = session.recorded == true
  for _, outcome in ipairs(OUTCOMES) do store[outcome] = session[outcome] or 0 end
  store.accepted = session.accepted or 0
  store.acceptedDungeon = session.acceptedDungeon
  store.acceptedKeyLevel = session.acceptedKeyLevel
  store.appliedRoles = copyRoles(session.appliedRoles)
  store.acceptedRole = session.acceptedRole
end

local function recordSession(self, reason)
  if self.session.recorded or not self.session.startedAt then return end
  local summary = {
    startedAt = self.session.startedAt,
    endedAt = self.session.endedAt,
    duration = self:elapsed(self.session.endedAt or self.session.startedAt),
    applications = self.session.applications,
    reason = reason or "ended",
  }
  for _, outcome in ipairs(OUTCOMES) do summary[outcome] = self.session[outcome] or 0 end
  summary.accepted = self.session.accepted or 0
  summary.acceptedDungeon = self.session.acceptedDungeon
  summary.acceptedKeyLevel = self.session.acceptedKeyLevel
  summary.appliedRoles = copyRoles(self.session.appliedRoles)
  summary.acceptedRole = self.session.acceptedRole
  self.session.recorded = true
  self.character.sessionHistory = self.character.sessionHistory or {}
  self.account.sessionHistory = self.account.sessionHistory or {}
  self.character.totalSessionTime = self.character.totalSessionTime + summary.duration
  self.account.totalSessionTime = self.account.totalSessionTime + summary.duration
  self.character.totalSessions = self.character.totalSessions + 1
  self.account.totalSessions = self.account.totalSessions + 1
  table.insert(self.character.sessionHistory, summary)
  table.insert(self.account.sessionHistory, summary)
end

function M.new(characterTotals, accountTotals, sessionStore, fallbackSessionStore)
  ensureTotals(characterTotals)
  ensureTotals(accountTotals)
  sessionStore = sessionStore or characterTotals.sessionState
  fallbackSessionStore = fallbackSessionStore or accountTotals.sessionState
  if (not sessionStore or not sessionStore.startedAt) and fallbackSessionStore and fallbackSessionStore.startedAt then
    sessionStore = fallbackSessionStore
    characterTotals.sessionState = sessionStore
  end
  sessionStore = sessionStore or {}
  characterTotals.sessionState = sessionStore
  accountTotals.sessionState = fallbackSessionStore or accountTotals.sessionState or {}
  local self = {
    character = characterTotals,
    account = accountTotals,
    sessionStore = sessionStore,
    mirrorSessionStore = accountTotals.sessionState,
    session = restoreSession(sessionStore),
  }
  return setmetatable(self, { __index = M })
end

function M:applicationApplied(now, applicationID, details)
  if self.session.ended then self:resetSession() end
  if not self.session.startedAt then self.session.startedAt = now end
  if self.session.active[applicationID] then return false end
  self.session.active[applicationID] = true
  self.session.applicationDetails = self.session.applicationDetails or {}
  self.session.applicationDetails[applicationID] = copyApplicationDetail(details)
  self.session.applications = self.session.applications + 1
  self.character.totalApplications = self.character.totalApplications + 1
  self.account.totalApplications = self.account.totalApplications + 1
  saveSession(self.sessionStore, self.session)
  if self.mirrorSessionStore ~= self.sessionStore then saveSession(self.mirrorSessionStore, self.session) end
  return true
end

function M:endSession(now, reason)
  if not self.session.startedAt or self.session.ended then return false end
  self.session.ended = true
  self.session.endedAt = now or self.session.startedAt
  recordSession(self, reason or "manual")
  for applicationID in pairs(self.session.active) do
    self.session.active[applicationID] = nil
    self.session.applicationDetails[applicationID] = nil
  end
  saveSession(self.sessionStore, self.session)
  if self.mirrorSessionStore ~= self.sessionStore then saveSession(self.mirrorSessionStore, self.session) end
  return true
end

function M:applicationOutcome(applicationID, outcome, now)
  if not self.session.active[applicationID] then return false end
  local details = self.session.applicationDetails and self.session.applicationDetails[applicationID]
  if outcome ~= "invited" then self.session.active[applicationID] = nil end
  self.session[outcome] = (self.session[outcome] or 0) + 1
  self.character[outcome] = self.character[outcome] + 1
  self.account[outcome] = self.account[outcome] + 1
  if outcome == "inviteaccepted" then
    self.session.accepted = (self.session.accepted or 0) + 1
    if details then
      self.session.acceptedDungeon = details.dungeon
      self.session.acceptedKeyLevel = details.keyLevel
      self.session.appliedRoles = copyRoles(details.appliedRoles)
      self.session.acceptedRole = details.role
    end
    self:endSession(now, "accepted")
  elseif outcome ~= "invited" and self.session.applicationDetails then
    self.session.applicationDetails[applicationID] = nil
  end
  saveSession(self.sessionStore, self.session)
  if self.mirrorSessionStore ~= self.sessionStore then saveSession(self.mirrorSessionStore, self.session) end
  return true
end

function M:sessionTotal()
  return self.session.applications
end

function M:elapsed(now)
  if not self.session.startedAt then return 0 end
  local finish = self.session.endedAt or now
  return math.max(0, finish - self.session.startedAt)
end

function M:clearHistory()
  self.character.sessionHistory = {}
  self.account.sessionHistory = {}
end

function M:resetLifetime()
  local function clearTotals(store)
    store.totalApplications = 0
    store.totalSessions = 0
    store.totalSessionTime = 0
    for _, outcome in ipairs(OUTCOMES) do store[outcome] = 0 end
    store.sessionHistory = {}
  end
  clearTotals(self.character)
  clearTotals(self.account)
  self:resetSession()
end

function M:resetSession()
  self.session = { applications = 0, active = {}, applicationDetails = {}, ended = false }
  saveSession(self.sessionStore, self.session)
  if self.mirrorSessionStore ~= self.sessionStore then saveSession(self.mirrorSessionStore, self.session) end
end

function M.parseKeyLevel(text)
  if type(text) ~= "string" then return nil end
  local levelText = text:match("^%+%s*(%d+)%f[%D]")
    or text:match("%s%+%s*(%d+)%f[%D]")
  local level = tonumber(levelText)
  if not level or level < 1 or level > 99 then return nil end
  return level
end

function M.acceptedDestination(session)
  session = session or {}
  local dungeon = session.acceptedDungeon
  local keyLevel = session.acceptedKeyLevel
  if dungeon and dungeon ~= "" then
    if keyLevel then return string.format("%s +%d", dungeon, keyLevel) end
    return dungeon
  end
  return "Mythic+ group"
end

function M.activeCount(active)
  local count = 0
  for _ in pairs(active or {}) do count = count + 1 end
  return count
end

function M.sessionStats(session, includeSecondary)
  session = session or {}
  local stats = {
    { key = "applications", label = "Applications", value = session.applications or 0, tone = "primary" },
    { key = "active", label = "Active", value = M.activeCount(session.active), tone = "active" },
    { key = "invited", label = "Invited", value = session.invited or 0, tone = "invited" },
    { key = "accepted", label = "Accepted", value = session.accepted or 0, tone = "accepted" },
    { key = "declined", label = "Declined", value = session.declined or 0, tone = "declined" },
    { key = "declined_full", label = "Group full", value = session.declined_full or 0, tone = "full" },
    { key = "declined_delisted", label = "Delisted", value = session.declined_delisted or 0, tone = "muted" },
    { key = "timedout", label = "Expired", value = session.timedout or 0, tone = "muted" },
    { key = "cancelled", label = "Withdrawn", value = session.cancelled or 0, tone = "muted" },
  }
  if includeSecondary then
    table.insert(stats, { key = "failed", label = "Failed", value = session.failed or 0, tone = "muted" })
    table.insert(stats, { key = "invitedeclined", label = "Invite declined", value = session.invitedeclined or 0, tone = "muted" })
  end
  return stats
end

function M.lifetimeSummary(store)
  store = store or {}
  local history = store.sessionHistory or {}
  local applications = store.totalApplications or 0
  local accepted = store.inviteaccepted or 0
  local sessions = store.totalSessions
  if sessions == nil then sessions = #history end
  return {
    sessions = sessions,
    applications = applications,
    invited = store.invited or 0,
    accepted = accepted,
    acceptanceRate = applications > 0 and (accepted / applications * 100) or 0,
    totalDuration = store.totalSessionTime or 0,
    averageDuration = sessions > 0 and ((store.totalSessionTime or 0) / sessions) or 0,
  }
end

function M.historyRows(history, limit)
  history = history or {}
  limit = math.max(0, limit or #history)
  local rows = {}
  local first = math.max(1, #history - limit + 1)
  for index = #history, first, -1 do
    local session = history[index]
    table.insert(rows, {
      index = index,
      applications = session.applications or 0,
      accepted = session.accepted or 0,
      duration = session.duration or 0,
      reason = session.reason or "ended",
      destination = session.reason == "accepted" and M.acceptedDestination(session) or nil,
      acceptedKeyLevel = session.acceptedKeyLevel,
      appliedRoles = copyRoles(session.appliedRoles),
      acceptedRole = session.acceptedRole,
      stats = M.sessionStats(session, true),
    })
  end
  return rows
end

function M.outcomes()
  local copy = {}
  for i, outcome in ipairs(OUTCOMES) do copy[i] = outcome end
  return copy
end

_G.QueueSimulatorCore = M
return M
