-- AltTimeBudget: auto-detection of weekly chore completion on the logged-in character
--
-- Detection methods (all confirmed in Blizzard_APIDocumentationGenerated):
--   vault : C_WeeklyRewards.GetActivities() -> { type, index, threshold, progress, ... }
--           Row types come from Enum.WeeklyRewardChestThresholdType (Activities / Raid / World /
--           RankedPvP, as used by Blizzard_WeeklyRewards.lua). Done when progress >= threshold.
--   quest : C_QuestLog.IsQuestFlaggedCompleted(questID) ("char" flag),
--           C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) ("account" flag), or either one
--           ("either" flag, housing). Quest IDs come from Data\QuestIDs.lua via the presets, or
--           from the options. Modes (Chores:QuestSpec):
--             any   - any one completed ID = done
--             all   - every ID completed; progress x/y is stored for the UI
--             count - at least `required` IDs completed; progress x/required is stored
--           questOnce chores (Arcantina patron quests: once per character ever, weekly rotation)
--           ignore IDs that were already completed at the week's first scan (week.baseline).
--   profession chores resolve their quest IDs from the alt's scanned professions; an alt that
--           hasn't been scanned yet is manual checkoff.
-- A detector returns true (done), false (not done) or nil (can't tell - manual checkoff applies).
--
-- Triggers: delayed scans after login (data isn't always ready), QUEST_TURNED_IN,
-- WEEKLY_REWARDS_UPDATE, ENCOUNTER_END / CHALLENGE_MODE_COMPLETED (+3s), PLAYER_LEVEL_UP,
-- SKILL_LINES_CHANGED (profession rescan), and the weekly reset.
local addonName, ns = ...

local Debug = ns.Debug

local pairs = pairs
local ipairs = ipairs
local max = math.max
local type = type
local tostring = tostring
local pcall = pcall
local tconcat = table.concat
local format = string.format
local wipe = wipe

local Detection = {}
ns.Detection = Detection

local scanTimer
local pendingLive = false
local loginScansDone = false
-- Quest IDs turned in this session (IsQuestFlaggedCompleted can lag behind QUEST_TURNED_IN).
-- Tied to the week key so it is dropped at the weekly reset.
local recent = { key = nil, ids = {} }

local function G()
	return ns.db.global
end

-- Enum value -> row name, for the rows we care about.
local function RowNameByType()
	local map = {}
	local E = Enum and Enum.WeeklyRewardChestThresholdType
	if not E then return map end
	for _, name in ipairs({ "Activities", "Raid", "World", "RankedPvP" }) do
		if E[name] ~= nil then
			map[E[name]] = name
		end
	end
	return map
end

-- Returns rows[rowName] = { progress = n, slots = { [index] = { threshold, progress } } }, or nil.
local function ReadVault()
	if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return nil end
	local ok, activities = pcall(C_WeeklyRewards.GetActivities)
	if not ok or type(activities) ~= "table" or #activities == 0 then
		return nil
	end
	local names = RowNameByType()
	local rows = {}
	for _, a in ipairs(activities) do
		local name = names[a.type]
		local idx = ns.SafeNumber(a.index)
		local threshold = ns.SafeNumber(a.threshold)
		local progress = ns.SafeNumber(a.progress)
		if name and idx and threshold and progress then
			local row = rows[name]
			if not row then
				row = { progress = 0, slots = {} }
				rows[name] = row
			end
			row.slots[idx] = { threshold = threshold, progress = progress }
			row.progress = max(row.progress, progress)
		end
	end
	return rows
end

local function Recent()
	local key = G().weekKey
	if recent.key ~= key then
		recent.key = key
		wipe(recent.ids)
	end
	return recent.ids
end

-- Flag reader for a spec. Returns a function(questID) -> true / false / nil (unknown), or nil.
local function FlagReader(flag)
	local QL = C_QuestLog
	if not QL then return nil end
	local charFn = QL.IsQuestFlaggedCompleted
	local acctFn = QL.IsQuestFlaggedCompletedOnAccount
	if flag == "account" then
		local fn = acctFn or charFn
		if not fn then return nil end
		return function(id) return ns.SafeBool(fn(id)) end
	elseif flag == "either" then
		if not (charFn or acctFn) then return nil end
		return function(id)
			local a = charFn and ns.SafeBool(charFn(id))
			if a then return true end
			local b = acctFn and ns.SafeBool(acctFn(id))
			if b then return true end
			if a == false or b == false then return false end
			return nil
		end
	end
	if not charFn then return nil end
	return function(id) return ns.SafeBool(charFn(id)) end
end

-- Evaluates a quest / profession chore for the current character.
-- Returns result (true / false / nil = unknown), done count, needed count.
local function EvaluateQuest(char, chore)
	local spec = ns.Chores:QuestSpec(chore, char)
	if not spec then return nil end
	local read = FlagReader(spec.flag)
	if not read then return nil end
	local turnedIn = Recent()
	local need = ns.Chores:Needed(spec)
	local state = ns.Roster:StateFor(char, chore)

	local base
	if spec.once then
		base = state.baseline[chore.id]
		if not base then
			-- First look this week: IDs already completed are from earlier weeks.
			base = {}
			local n = 0
			for _, id in ipairs(spec.ids) do
				if not turnedIn[id] and read(id) then
					base[id] = true
					n = n + 1
				end
			end
			state.baseline[chore.id] = base
			Debug:Log("Baseline", chore.id, n, "of", #spec.ids, "already completed before this week")
		end
	end

	local done, known = 0, false
	for _, id in ipairs(spec.ids) do
		local v = turnedIn[id] or read(id)
		if v ~= nil then known = true end
		if v and not (base and base[id]) then
			done = done + 1
		end
	end
	if not known then return nil, 0, need end
	return done >= need, done, need
end

local function DetectVault(chore, vault)
	if not vault then return nil end
	local row = vault[chore.detect.row]
	if not row then return nil end
	local slot = row.slots[chore.detect.index]
	if not slot then return nil end
	return slot.progress >= slot.threshold
end

local MODE_SHORT = { any = "any of", all = "all of" }
local FLAG_SHORT = { char = "", account = ", account flag", either = ", char or account flag" }

local function DescribeSpec(spec)
	local ids = spec.ids
	local list
	if #ids > 6 then
		list = format("%d IDs (%s ... %d)", #ids, tconcat(ids, ",", 1, 3), ids[#ids])
	else
		list = tconcat(ids, ",")
	end
	local mode
	if #ids == 1 then
		mode = "quest"
	elseif spec.mode == "count" then
		mode = format("%d of", ns.Chores:Needed(spec))
	else
		mode = MODE_SHORT[spec.mode] or "any of"
	end
	return format("auto: %s %s%s%s", mode, list, FLAG_SHORT[spec.flag] or "", spec.once and ", this week's only" or "")
end

-- Public: how this chore is detected, for UI labels. char (optional) resolves profession chores.
function Detection:Describe(chore, char)
	local d = chore.detect
	if not d then return "manual" end
	if d.type == "vault" then
		return "auto: Great Vault " .. d.row .. " #" .. d.index
	elseif d.type == "quest" then
		return DescribeSpec(chore.quest)
	elseif d.type == "profession" then
		if not char then
			return format("auto: profession %d %s (resolved per alt)", d.slot, d.kind)
		end
		local spec, reason = ns.Chores:QuestSpec(chore, char)
		if spec then return DescribeSpec(spec) end
		if reason == "unscanned" then return "manual: log in to scan professions" end
		if reason == "none" then return format("no profession in slot %d", d.slot) end
		return "manual: no quest data for this profession"
	end
	return "manual"
end

-- "2/3" progress text for all / count chores (nil when there's nothing to show).
function Detection:ProgressText(char, chore)
	local spec = ns.Chores:QuestSpec(chore, char)
	if not spec or ns.Chores:Needed(spec) <= 1 then return nil end
	local done, need = ns.Roster:GetProgress(char, chore)
	if not need then return nil end
	if ns.Roster:IsDetected(char, chore) then done = need end
	if done > need then done = need end
	return format("%d/%d", done, need)
end

function Detection:ScanNow(live)
	scanTimer = nil
	pendingLive = false
	ns.ATB:CheckWeeklyReset()
	local char = ns.Roster:RegisterCurrent()
	if not char then return end
	local week = ns.Roster:GetWeek(char)
	local changed = false

	-- Great Vault
	local vault = ReadVault()
	if vault then
		local cache = G().vaultThresholds
		for rowName, row in pairs(vault) do
			cache[rowName] = cache[rowName] or {}
			for idx, slot in pairs(row.slots) do
				if cache[rowName][idx] ~= slot.threshold then
					cache[rowName][idx] = slot.threshold
					changed = true
					ns.Chores:Invalidate()
				end
			end
			local old = week.vaultProgress[rowName]
			if old ~= row.progress then
				if old ~= nil and row.progress > old and live then
					ns.TimeLearner:OnVaultProgress(char, rowName, row.progress - old)
				end
				Debug:Log("Vault", rowName, "progress", tostring(old), "->", row.progress)
				week.vaultProgress[rowName] = row.progress
				changed = true
			end
		end
	end

	-- Chores
	for _, chore in ipairs(ns.Chores:GetAll()) do
		if chore.detect and not ns.Roster:IsDetected(char, chore) then
			local result
			if chore.detect.type == "vault" then
				result = DetectVault(chore, vault)
			elseif chore.detect.type == "quest" or chore.detect.type == "profession" then
				local done, need
				result, done, need = EvaluateQuest(char, chore)
				if result ~= nil and need and need > 1 and ns.Roster:SetProgress(char, chore, done, need) then
					changed = true
				end
			end
			if result and ns.Roster:MarkDetected(char, chore) then
				changed = true
				Debug:Log("Detected done:", chore.id, live and "(live)" or "(scan)")
				if live then
					ns.TimeLearner:OnChoreCompleted(char, chore, "auto")
				end
			end
		end
	end

	if changed then
		ns.NotifyUpdate("scan")
	end
end

-- Coalesces bursts of triggers into one scan. live = the change happened during this session,
-- so it may produce a learned-time sample.
function Detection:RequestScan(reason, live)
	if live then pendingLive = true end
	if scanTimer then return end
	scanTimer = ns.ATB:ScheduleTimer(function()
		Detection:ScanNow(pendingLive)
	end, ns.SCAN_THROTTLE_SECONDS)
end

function Detection:OnQuestTurnedIn(_, questID)
	questID = ns.SafeNumber(questID)
	if not questID then return end
	Recent()[questID] = true
	local char = ns.Roster:Current()
	if char then
		local changed = false
		for _, chore in ipairs(ns.Chores:GetAll()) do
			local d = chore.detect
			if d and (d.type == "quest" or d.type == "profession") and not ns.Roster:IsDetected(char, chore) then
				local spec = ns.Chores:QuestSpec(chore, char)
				local listed = false
				if spec then
					for _, id in ipairs(spec.ids) do
						if id == questID then listed = true break end
					end
				end
				if listed then
					local result, done, need = EvaluateQuest(char, chore)
					if result ~= nil and need and need > 1 and ns.Roster:SetProgress(char, chore, done, need) then
						changed = true
					end
					if result and ns.Roster:MarkDetected(char, chore) then
						Debug:Log("Quest turned in -> done:", chore.id, questID)
						ns.TimeLearner:OnChoreCompleted(char, chore, "auto")
						changed = true
					elseif need and need > 1 then
						Debug:Log("Quest turned in -> progress:", chore.id, questID, tostring(done) .. "/" .. need)
					end
				end
			end
		end
		if changed then
			ns.NotifyUpdate("scan")
		end
	end
	self:RequestScan("QUEST_TURNED_IN", true)
end

-- Profession learned / unlearned: rescan professions, then quests.
function Detection:OnSkillLinesChanged()
	if ns.Roster:ScanProfessions() then
		ns.NotifyUpdate("roster")
	end
	self:RequestScan("SKILL_LINES_CHANGED", false)
end

function Detection:OnWeeklyRewardsUpdate()
	-- The first scans after login set the progress baseline - later updates are live progress.
	self:RequestScan("WEEKLY_REWARDS_UPDATE", loginScansDone)
end

-- Backup triggers: vault progress can lag the kill / key completion by a few seconds.
function Detection:OnContentCompleted(event)
	ns.ATB:ScheduleTimer(function()
		Detection:RequestScan(event, true)
	end, 3)
end

function Detection:OnLevelUp(_, level)
	ns.Roster:SetLevel(level)
	self:RequestScan("PLAYER_LEVEL_UP", false)
end

-- True once the delayed login scans have run (quest / vault data should be loaded by then).
function Detection:IsReady()
	return loginScansDone
end

function Detection:Enable()
	LibStub("AceEvent-3.0"):Embed(self)
	ns.RegisterEventSafe(self, "QUEST_TURNED_IN", "OnQuestTurnedIn")
	ns.RegisterEventSafe(self, "WEEKLY_REWARDS_UPDATE", "OnWeeklyRewardsUpdate")
	ns.RegisterEventSafe(self, "PLAYER_LEVEL_UP", "OnLevelUp")
	ns.RegisterEventSafe(self, "ENCOUNTER_END", "OnContentCompleted")
	ns.RegisterEventSafe(self, "CHALLENGE_MODE_COMPLETED", "OnContentCompleted")
	ns.RegisterEventSafe(self, "SKILL_LINES_CHANGED", "OnSkillLinesChanged")

	local delays = ns.LOGIN_RESCAN_DELAYS
	for i, delay in ipairs(delays) do
		ns.ATB:ScheduleTimer(function()
			-- Profession data may not be ready at the very first pass; each login pass refreshes it.
			if ns.Roster:ScanProfessions() then
				ns.NotifyUpdate("roster")
			end
			Detection:ScanNow(false)
			if i == #delays then
				loginScansDone = true
			end
		end, delay)
	end
end
