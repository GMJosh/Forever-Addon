-- AltTimeBudget: built-in weekly chore presets (Forever / Classic Vanilla)
--
-- Vanilla chores are manual checkoff (no quest flags). Quest IDs, if added later, come from Data\QuestIDs.lua.
-- Never type quest IDs here directly - add them to QuestIDs.lua and reference them.
--
-- Field reference
--   id        unique string key (never change once shipped: saved overrides and learned times use it)
--   name      display name
--   category  grouping label
--   minutes   default estimated minutes for the whole chore
--   value     default value points (editable). Score = value x alt priority, rate = score / minutes
--   minLevel  number, or "max" for the current expansion's max level (GetMaxLevelForPlayerExpansion)
--   scope     "char" (each alt does it) or "account" (done once per account per week, attached to
--             the highest-priority alt whose role allows it)
--   roles     which alt roles may do the chore: { main = true, alt = true, profession = true }
--             Optional. If omitted: main + alt, plus profession when category is "Professions".
--   requires  optional id of a chore that must be done first (Great Vault slot chains)
--   enabled   optional, false = shipped disabled
--   note      optional short remark shown in the Checkoff tab and the options
--
-- Quest-flag detection
--   questIDs  list of quest IDs
--   questMode "any"   (default) a pool: any one completed ID = done
--             "all"   every listed ID must be completed (progress x/y)
--             "count" done when at least `required` IDs are completed (progress x/required)
--   required  for "count" mode
--   questFlag "char" (IsQuestFlaggedCompleted), "account" (IsQuestFlaggedCompletedOnAccount) or
--             "either" (done if either flag is set). Default: "account" for scope = "account",
--             else "char".
--   questOnce true for quests that are completable once per character EVER (not weekly flags).
--             The IDs already completed at the first scan of the week are ignored, so only this
--             week's completions count.
--   prof      { slot = 1 or 2, kind = "weekly" / "treatise" / "drops" }: the quest IDs are resolved
--             per alt from that alt's scanned professions (ns.QuestIDs.Professions).
--   detect    { type = "vault", row = <Enum.WeeklyRewardChestThresholdType key>, index = <slot> }
--             Uses C_WeeklyRewards.GetActivities(): done when progress >= threshold.
--             For vault chores, "unitMinutes" is the default minutes per vault progress unit.
--
-- Chores with no quest IDs (and no prof / detect) are manual checkoff.
-- Quest IDs / mode typed in /atb config -> Chores -> <chore> override the values here.
local addonName, ns = ...

local Q = ns.QuestIDs
local sort = table.sort
local pairs = pairs
local ipairs = ipairs

-- Sorted list of the keys of an { [questID] = label } table, minus any IDs in `exclude`.
local function Keys(t, exclude)
	local list = {}
	for id in pairs(t) do
		if not (exclude and exclude[id]) then
			list[#list + 1] = id
		end
	end
	sort(list)
	return list
end

-- Sorted list of IDs from an { [questID] = label } table, taking only the given IDs (each is
-- checked against the table so a typo can't slip in an ID that isn't in the data).
local function Pick(t, ids)
	local list = {}
	for _, id in ipairs(ids) do
		if t[id] then
			list[#list + 1] = id
		end
	end
	sort(list)
	return list
end

local PROF_ROLES = { main = true, alt = true, profession = true }

-- Forever raids (Blizzard's raid overview, 20 Oct 2026; open 9 Dec 2026). All three are level 60 and
-- currently planned to reset weekly, so one run per week fits the planner. Source: ForeverDB.net.
ns.PRESETS = {
	-------------------------------------------------------------------------
	-- Raids (manual checkoff)
	-------------------------------------------------------------------------
	{
		id = "raid_barrow_deeps", name = "The Barrow Deeps (10-player, 8 bosses)", category = "Raids",
		minutes = 120, value = 100, minLevel = 60, scope = "char",
		note = "Mount Hyjal. Opens December 9.",
	},
	{
		id = "raid_hyjal_summit", name = "Hyjal Summit (20-player, 13 bosses)", category = "Raids",
		minutes = 180, value = 110, minLevel = 60, scope = "char",
		note = "Mount Hyjal. Opens December 9.",
	},
	{
		id = "raid_onyxia", name = "Onyxia's Lair (40-player)", category = "Raids",
		minutes = 45, value = 70, minLevel = 60, scope = "char",
		note = "Needs the Drakefire Amulet attunement. Opens December 9.",
	},

	-------------------------------------------------------------------------
	-- Professions (manual checkoff)
	-------------------------------------------------------------------------
	{
		id = "prof_cooldowns", name = "Profession cooldowns (Mooncloth, Transmute, Salt Shaker)", category = "Professions",
		minutes = 10, value = 25, minLevel = 40, scope = "char", roles = PROF_ROLES,
	},
}
