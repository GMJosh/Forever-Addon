-- AltTimeBudget: quest ID data (Forever / Classic Vanilla build)
--
-- Vanilla has no weekly quest-flag content, so the Midnight tables (weekly metas, world bosses,
-- Housing, Prey, profession knowledge quests and so on) were removed. The chores in
-- Data\Presets.lua are manual checkoff. Add IDs here only after verifying them in game with
-- /dump C_QuestLog.IsQuestFlaggedCompleted(<id>), then reference them from Presets.lua.
--
-- Exposed as ns.QuestIDs (no globals). Loaded before Data\Presets.lua.
local addonName, ns = ...

local Vanilla = {}

-- Profession lookups used by Roster / Chores. Empty on Vanilla: professions are listed by name
-- only and have no weekly quests.
Vanilla.Professions = {}
Vanilla.ProfessionBaseBySkillLine = {}

ns.QuestIDs = Vanilla
