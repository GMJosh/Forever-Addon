-- AltTimeBudget: addon object, DB init, shared helpers, weekly reset, slash commands
local addonName, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local ATB = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.ATB = ATB

local Debug = ns.Debug

local floor = math.floor
local max = math.max
local format = string.format
local tonumber = tonumber
local type = type
local pairs = pairs
local ipairs = ipairs
local print = print
local InCombatLockdown = InCombatLockdown
local GetServerTime = GetServerTime

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

-- True if v is a 12.0 secret value. Safe on clients without issecretvalue.
function ns.IsSecret(v)
	if issecretvalue then
		return issecretvalue(v) and true or false
	end
	return false
end

-- Returns v if it's a usable (non-secret) number, else nil.
function ns.SafeNumber(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- Returns v if it's a usable (non-secret, non-empty) string, else nil.
function ns.SafeString(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "string" or v == "" then
		return nil
	end
	return v
end

-- Returns true/false for a usable boolean, nil if secret or missing.
function ns.SafeBool(v)
	if v == nil or ns.IsSecret(v) then
		return nil
	end
	return v and true or false
end

-- Registers an event only if the client knows it.
function ns.RegisterEventSafe(obj, event, handler)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		Debug:Log("Event not valid on this client, skipped:", event)
		return false
	end
	obj:RegisterEvent(event, handler)
	return true
end

-- 125 -> "2h 05m", 45 -> "45m", 0 -> "0m"
function ns.FormatMinutes(minutes)
	minutes = floor((minutes or 0) + 0.5)
	if minutes < 0 then minutes = 0 end
	local h = floor(minutes / 60)
	local m = minutes % 60
	if h > 0 then
		return format("%dh %02dm", h, m)
	end
	return format("%dm", m)
end

-- 1.234 -> "1.23"
function ns.FormatRate(rate)
	return format("%.2f", rate or 0)
end

function ns.MaxLevel()
	if GetMaxLevelForPlayerExpansion then
		local lvl = ns.SafeNumber(GetMaxLevelForPlayerExpansion())
		if lvl and lvl > 0 then
			return lvl
		end
	end
	return ns.FALLBACK_MAX_LEVEL
end

-- minLevel may be a number or "max"
function ns.ResolveMinLevel(v)
	if v == "max" then
		return ns.MaxLevel()
	end
	return tonumber(v) or 1
end

function ns.ClassColoredName(char)
	if not char then return "?" end
	local name = char.name or "?"
	if char.class and C_ClassColor and C_ClassColor.GetClassColor then
		local color = C_ClassColor.GetClassColor(char.class)
		if color and color.WrapTextInColorCode then
			return color:WrapTextInColorCode(name)
		end
	end
	return name
end

function ns.CharLabel(char)
	if not char then return "?" end
	return format("%s-%s", char.name or "?", char.realm or "?")
end

-- User-facing chat line (not debug output).
function ns.Say(msg)
	print("|cff33ff99AltTimeBudget|r: " .. msg)
end

---------------------------------------------------------------------------
-- Lightweight internal update notifications (data -> UI)
---------------------------------------------------------------------------
local listeners = {}

function ns.RegisterUpdateListener(key, fn)
	listeners[key] = fn
end

function ns.NotifyUpdate(reason)
	for _, fn in pairs(listeners) do
		fn(reason)
	end
end

---------------------------------------------------------------------------
-- Weekly reset
---------------------------------------------------------------------------

-- The week key is the epoch time of the NEXT weekly reset, rounded to the hour so that small
-- skew between GetServerTime() and GetSecondsUntilWeeklyReset() can't flip it.
function ATB:ComputeWeekKey()
	local now = ns.SafeNumber(GetServerTime and GetServerTime())
	if not now then return nil end
	local nextReset
	if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
		local secs = ns.SafeNumber(C_DateAndTime.GetSecondsUntilWeeklyReset())
		if secs and secs > 0 then
			nextReset = now + secs
		end
	end
	if not nextReset and C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime then
		local start = ns.SafeNumber(C_DateAndTime.GetWeeklyResetStartTime())
		if start and start > 0 then
			nextReset = start + ns.SECONDS_PER_WEEK
		end
	end
	if not nextReset then return nil end
	return floor((nextReset + 1800) / 3600) * 3600
end

function ATB:CheckWeeklyReset()
	local key = self:ComputeWeekKey()
	if not key then
		Debug:Log("Week key unavailable - reset check skipped")
		return false
	end
	local g = ns.db.global
	if g.weekKey == key then
		return false
	end
	if g.weekKey and key < g.weekKey then
		-- Clock went backwards (shouldn't happen) - never roll back a week.
		Debug:Log("Week key went backwards, ignoring:", g.weekKey, "->", key)
		return false
	end

	if g.weekKey then
		Debug:Log("Weekly reset detected:", g.weekKey, "->", key)
		-- Summarize the old week BEFORE the key changes (week state is keyed on g.weekKey).
		local ok, summary = pcall(ns.Planner.SummarizeWeek, ns.Planner)
		if ok then
			g.lastWeek = summary
		else
			Debug:Log("SummarizeWeek failed:", summary)
		end
		g.weekKey = key
		ns.Roster:ResetAllWeeks()
	else
		Debug:Log("First week key set:", key)
		g.weekKey = key
	end
	g.weekPlanSnapshot = nil
	ns.NotifyUpdate("reset")
	return true
end

function ATB:ScheduleResetTimer()
	if self.resetTimer then
		self:CancelTimer(self.resetTimer)
		self.resetTimer = nil
	end
	if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then return end
	local secs = ns.SafeNumber(C_DateAndTime.GetSecondsUntilWeeklyReset())
	if not secs then return end
	-- Fire a little after the reset - re-check at least every 6 hours as a safety net.
	local delay = math.min(secs + 30, 6 * 3600)
	self.resetTimer = self:ScheduleTimer(function()
		self.resetTimer = nil
		if self:CheckWeeklyReset() and ns.Detection then
			ns.Detection:RequestScan("reset", false)
		end
		self:ScheduleResetTimer()
	end, max(delay, 10))
end

---------------------------------------------------------------------------
-- Saved data migration
---------------------------------------------------------------------------
-- A database without schemaVersion is schema 1 (the original release).
local MIGRATIONS = {
	-- 1 -> 2: "first character = main" (isMain flag) replaced by a role per alt.
	-- The old main becomes "main", every other alt becomes "alt". Priorities are kept as they are.
	[2] = function(g)
		local mains, alts = 0, 0
		for _, char in pairs(g.chars) do
			if type(char) == "table" and not ns.ValidRole(char.role) then
				if char.isMain then
					char.role = "main"
					mains = mains + 1
				else
					char.role = "alt"
					alts = alts + 1
				end
			end
			if type(char) == "table" then
				char.isMain = nil
			end
		end
		Debug:Log(format("Migration 2: roles assigned (%d main, %d alt)", mains, alts))
	end,

	-- 2 -> 3: real Midnight quest IDs (Data\QuestIDs.lua) replace the manual chores.
	--   * One-to-one replacements are renamed: their minutes / value / enabled / level / roles
	--     overrides, learned time, this week's manual checkoff + measured time and timer anchors move
	--     to the new id. Name / category / quest ID overrides are dropped (the new chore's name and
	--     shipped quest IDs apply). world_boss keeps its id; only its quest ID override is dropped.
	--   * Chores that were split or removed lose their overrides and learned time.
	--   * Any other override for an id that is neither a preset nor a custom chore is dropped.
	--   * Stale per-week entries for removed ids are left alone - nothing reads them, and they are
	--     wiped at the next weekly reset.
	[3] = function(g)
		local RENAMED = {
			prof_weekly_1 = "prof1_weekly",
			prof_weekly_2 = "prof2_weekly",
			pvp_weekly = "pvp_sparks",
		}
		local REMOVED = {
			prof_knowledge_drops = "split into per-profession treatise + knowledge drops chores",
			housing_endeavors = "split into Housing: Vaeli endeavor + Housing: neighborhood weekly",
			zone_weekly = "split into one chore per zone weekly",
		}
		local KEEP = { "minutes", "value", "enabled", "minLevel", "roles" }

		local function MoveKey(t, from, to)
			if type(t) == "table" and t[from] ~= nil then
				if t[to] == nil then t[to] = t[from] end
				t[from] = nil
				return true
			end
			return false
		end

		local overrides = g.choreOverrides or {}
		g.choreOverrides = overrides
		for old, new in pairs(RENAMED) do
			local ov = overrides[old]
			if type(ov) == "table" then
				local kept, n = {}, 0
				for _, field in ipairs(KEEP) do
					if ov[field] ~= nil then
						kept[field] = ov[field]
						n = n + 1
					end
				end
				overrides[old] = nil
				if n > 0 and overrides[new] == nil then
					overrides[new] = kept
				end
				Debug:Log(format("Migration 3: override %s -> %s (%d field(s) kept)", old, new, n))
			end
			if type(g.learned) == "table" and MoveKey(g.learned, old, new) then
				Debug:Log(format("Migration 3: learned time %s -> %s", old, new))
			end
			local moved = 0
			local weeks = {}
			for _, char in pairs(g.chars or {}) do
				if type(char) == "table" then
					weeks[#weeks + 1] = char.week
					if MoveKey(char.anchors, old, new) then moved = moved + 1 end
				end
			end
			weeks[#weeks + 1] = g.accountWeek
			for _, w in ipairs(weeks) do
				if type(w) == "table" then
					if MoveKey(w.manual, old, new) then moved = moved + 1 end
					if MoveKey(w.measured, old, new) then moved = moved + 1 end
					MoveKey(w.detected, old, new)
				end
			end
			if moved > 0 then
				Debug:Log(format("Migration 3: %d checkoff / timer entr(ies) %s -> %s", moved, old, new))
			end
		end

		local wb = overrides.world_boss
		if type(wb) == "table" and wb.questIDs ~= nil then
			wb.questIDs = nil
			if next(wb) == nil then overrides.world_boss = nil end
			Debug:Log("Migration 3: world_boss quest ID override dropped (shipped world boss pool applies)")
		end

		for old, why in pairs(REMOVED) do
			if overrides[old] ~= nil then
				overrides[old] = nil
				Debug:Log(format("Migration 3: override for removed chore %s dropped (%s)", old, why))
			end
			if type(g.learned) == "table" and g.learned[old] ~= nil then
				g.learned[old] = nil
				Debug:Log(format("Migration 3: learned time for removed chore %s dropped", old))
			end
		end

		local presetIds = {}
		for _, p in ipairs(ns.PRESETS) do presetIds[p.id] = true end
		local customs = g.customChores or {}
		for id in pairs(overrides) do
			if not presetIds[id] and customs[id] == nil then
				overrides[id] = nil
				Debug:Log(format("Migration 3: orphaned override %s dropped", tostring(id)))
			end
		end
		Debug:Log("Migration 3: done (stale week entries for removed chores are ignored)")
	end,
}

function ATB:MigrateDB()
	local g = self.db.global
	local from = tonumber(g.schemaVersion) or 1
	for v = from + 1, ns.DB_SCHEMA_VERSION do
		local step = MIGRATIONS[v]
		if step then
			local ok, err = pcall(step, g)
			if not ok then
				Debug:Log("Migration", v, "failed:", err)
				return
			end
		end
		g.schemaVersion = v
	end
	if from < ns.DB_SCHEMA_VERSION then
		Debug:Log("DB schema", from, "->", ns.DB_SCHEMA_VERSION)
	end
	g.schemaVersion = ns.DB_SCHEMA_VERSION
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function ATB:OnInitialize()
	-- true = all characters share the "Default" profile (account-wide settings)
	self.db = LibStub("AceDB-3.0"):New("AltTimeBudgetDB", ns.defaults, true)
	ns.db = self.db
	Debug:Attach(self.db.global.debugLog)
	Debug:Log("OnInitialize: DB ready")
	self:MigrateDB()

	if ns.Options and ns.Options.Register then
		ns.Options:Register()
	end

	self:RegisterChatCommand("atb", "HandleSlash")
	self:RegisterChatCommand("alttimebudget", "HandleSlash")
end

function ATB:OnEnable()
	Debug:Log("OnEnable")
	self:CheckWeeklyReset()
	ns.Roster:RegisterCurrent()
	ns.TimeLearner:Enable()
	ns.Detection:Enable()
	self:ScheduleResetTimer()

	ns.RegisterEventSafe(self, "PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
	ns.RegisterEventSafe(self, "PLAYER_LOGOUT", "OnPlayerLogout")

	if ns.db.profile.loginMessage then
		self:ScheduleTimer("LoginMessage", ns.LOGIN_MESSAGE_DELAY)
	end
end

function ATB:OnPlayerEnteringWorld(_, isInitialLogin, isReloadingUi)
	if self:CheckWeeklyReset() then
		ns.Detection:RequestScan("reset", false)
	end
	ns.Roster:RegisterCurrent()
end

function ATB:OnPlayerLogout()
	ns.TimeLearner:Flush()
	ns.Roster:TouchCurrent()
end

function ATB:LoginMessage()
	if not ns.db.profile.loginMessage then return end
	local plan = ns.Planner:Compute()
	local guid = ns.Roster:CurrentGUID()
	local group = guid and plan.groupsByGuid[guid]
	local char = ns.Roster:Current()
	if char and ns.Roster:Role(char) == "bank" then
		ns.Say("bank character - no chores planned. Type /atb for details.")
	elseif group then
		ns.Say(format("this alt is in this week's plan: %d chore(s), about %s. Type /atb for details.",
			#group.items, ns.FormatMinutes(group.minutes + group.overhead)))
	else
		local reason = guid and plan.skipReasons[guid]
		ns.Say("this alt is not in this week's plan" .. (reason and (" (" .. reason .. ")") or "") .. ". Type /atb for details.")
	end
end

---------------------------------------------------------------------------
-- Budget
---------------------------------------------------------------------------
function ATB:SetHours(hours)
	hours = tonumber(hours)
	if not hours or hours < 0 or hours > 168 then
		return false
	end
	ns.db.profile.hoursBudget = hours
	Debug:Log("Hours budget set:", hours)
	ns.NotifyUpdate("budget")
	return true
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
function ATB:OpenConfig()
	if InCombatLockdown() then
		ns.Say("settings can't be opened in combat. Try again after combat.")
		return
	end
	if ns.Options and ns.Options.categoryID and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.Options.categoryID)
	else
		LibStub("AceConfigDialog-3.0"):Open(addonName)
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP_LINES = {
	"|cff33ff99AltTimeBudget|r commands:",
	"  /atb - toggle the planner window",
	"  /atb hours <n> - set this week's hours budget (e.g. /atb hours 6.5)",
	"  /atb plan - print a short plan summary in chat",
	"  /atb config - open settings (not in combat)",
	"  /atb debug - open the debug log window",
	"  /atb help - show this help",
}

function ATB:PrintPlanSummary()
	local plan = ns.Planner:Compute()
	ns.Say(format("plan %s of %s available (budget %s, already spent %s).",
		ns.FormatMinutes(plan.plannedMinutes), ns.FormatMinutes(plan.availableMinutes),
		ns.FormatMinutes(plan.budgetMinutes), ns.FormatMinutes(plan.spentMinutes)))
	if #plan.groups == 0 then
		print("  Nothing planned.")
	end
	for i, group in ipairs(plan.groups) do
		print(format("  %d. %s: %d chore(s), %s", i, ns.ClassColoredName(group.char), #group.items,
			ns.FormatMinutes(group.minutes + group.overhead)))
	end
	local skipNames = {}
	for _, s in ipairs(plan.skipped) do
		if s.kind == "skip" then
			skipNames[#skipNames + 1] = ns.ClassColoredName(s.char) .. " (" .. s.reason .. ")"
		end
	end
	if #skipNames > 0 then
		print("  Skip: " .. table.concat(skipNames, ", "))
	end
end

function ATB:HandleSlash(input)
	local cmd, arg = self:GetArgs(input or "", 2)
	cmd = cmd and cmd:lower() or ""
	Debug:Log("Slash:", cmd, arg)

	if cmd == "" then
		ns.MainWindow:Toggle()
	elseif cmd == "hours" then
		if arg and self:SetHours(arg) then
			ns.Say(format("weekly budget set to %s.", ns.FormatMinutes(ns.db.profile.hoursBudget * 60)))
		else
			ns.Say("usage: /atb hours <number between 0 and 168>")
		end
	elseif cmd == "plan" then
		self:PrintPlanSummary()
	elseif cmd == "config" or cmd == "options" then
		self:OpenConfig()
	elseif cmd == "debug" then
		Debug:ToggleWindow()
	else
		for i = 1, #HELP_LINES do
			print(HELP_LINES[i])
		end
	end
end
