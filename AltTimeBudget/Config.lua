-- AltTimeBudget: defaults and constants
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.ADDON_TITLE = "AltTimeBudget"

-- Constants
ns.DEBUG_LOG_MAX = 1000          -- max lines kept in the debug log
ns.ACTIVE_TICK_SECONDS = 15      -- how often the active-play counter is advanced
ns.SCAN_THROTTLE_SECONDS = 1     -- coalesce bursts of detection triggers
ns.LOGIN_RESCAN_DELAYS = { 3, 12, 30 } -- quest / vault data is not always ready at login
ns.LOGIN_MESSAGE_DELAY = 14      -- seconds after login before the "are you in the plan" chat line
ns.MIN_SAMPLE_MINUTES = 1        -- learned-time samples shorter than this are discarded
ns.FALLBACK_MAX_LEVEL = 60       -- used only if GetMaxLevelForPlayerExpansion is unavailable
ns.SECONDS_PER_WEEK = 604800
ns.DB_SCHEMA_VERSION = 3         -- bump + add a step in Core:MigrateDB when saved data changes shape

-- Alt roles. Order here is the display / sort order (mains first).
--   main        all chores, default priority 1.0 (any number of mains allowed)
--   alt         all chores, default priority = profile.defaultAltPriority
--   profession  only chores whose allowed roles include "profession" (profession weeklies, treatises,
--               knowledge drops, patron orders), default priority = profile.defaultProfessionPriority
--   bank        no chores at all: never planned, never in the skip list, never gets account chores
ns.ROLE_ORDER = { "main", "alt", "profession", "bank" }
ns.ROLE_RANK = { main = 1, alt = 2, profession = 3, bank = 4 }
ns.ROLE_LABELS = { main = "Main", alt = "Alt", profession = "Profession", bank = "Bank" }
ns.ROLE_COLORS = { main = "|cffffd100", alt = "|cff9d9d9d", profession = "|cff66bbff", bank = "|cffc08040" }
-- Roles a chore can be allowed for (bank never takes chores).
ns.CHORE_ROLE_ORDER = { "main", "alt", "profession" }
ns.MAIN_PRIORITY = 1.0

-- Fallback Great Vault thresholds, used only until C_WeeklyRewards.GetActivities has reported
-- the real thresholds once (they are cached account-wide in db.global.vaultThresholds).
ns.FALLBACK_VAULT_THRESHOLDS = {
	Activities = { 1, 4, 8 },
	Raid = { 2, 4, 6 },
	World = { 2, 4, 8 },
	RankedPvP = { 1, 2, 3 },
}

-- AceDB defaults. Every character shares the "Default" profile (settings are account-wide) and
-- all roster / chore / learned data lives in .global so the planner can see every alt.
ns.defaults = {
	profile = {
		hoursBudget = 10,           -- persists week to week as the default budget
		overheadMinutes = 5,        -- per-alt cost (log in, fly to the hub) charged once per alt used
		defaultAltPriority = 0.5,   -- default priority for the "alt" role (new alts start as "alt")
		defaultProfessionPriority = 0.5, -- default priority for the "profession" role
		subtractSpent = true,       -- plan only the time left after chores already done this week
		loginMessage = true,        -- short chat line at login: is this alt in the plan?
		emaAlpha = 0.3,             -- weight of the newest sample in the learned-time average
		outlierCap = 3,             -- samples are clamped to this multiple of the default minutes
		window = {
			status = {},            -- AceGUI Frame status (position / size)
			tab = "plan",
			checkoffChar = nil,     -- GUID selected in the Checkoff tab
		},
	},
	global = {
		-- schemaVersion is deliberately NOT given a default here: AceDB would report the default
		-- for old databases too, hiding the fact that they still need migrating.
		weekKey = nil,              -- identifies the current reset week (see Core:ComputeWeekKey)
		chars = {},                 -- [guid] = roster entry (see Roster.lua)
		choreOverrides = {},        -- [presetId] = { enabled, minutes, value, minLevel, name, category, questIDs, roles }
		customChores = {},          -- [customId] = full chore definition
		nextCustomId = 1,
		learned = {},               -- [learnKey] = { ema, n, last, at }
		accountWeek = nil,          -- per-week state for account-wide chores
		vaultThresholds = {},       -- [rowName] = { [index] = threshold } last reported by the client
		weekPlanSnapshot = nil,     -- first plan computed this week (for the "last week" summary)
		lastWeek = nil,             -- plan vs actual for the previous week
		debugLog = {},
	},
}

-- Default priority for a role (nil for bank, which has no priority).
function ns.RoleDefaultPriority(role)
	if role == "main" then return ns.MAIN_PRIORITY end
	if role == "alt" then return ns.db and ns.db.profile.defaultAltPriority or 0.5 end
	if role == "profession" then return ns.db and ns.db.profile.defaultProfessionPriority or 0.5 end
	return nil
end

-- Returns role if it is a known role, else nil.
function ns.ValidRole(role)
	if role and ns.ROLE_RANK[role] then return role end
	return nil
end

-- "[Main]" style coloured tag for UI text.
function ns.RoleTag(role)
	role = ns.ValidRole(role) or "alt"
	return ns.ROLE_COLORS[role] .. "[" .. ns.ROLE_LABELS[role] .. "]|r"
end
