-- CraftPath: constants and defaults
local addonName, ns = ...

ns.ADDON = addonName
ns.DEBUG_MAX = 1000        -- max lines in the debug log
ns.AH_CUT = 0.95           -- you keep about 95% of an auction house sale (5% cut)
ns.TOP_COUNT = 10          -- recipes shown in the ranking

-- Chance of a skill-up by recipe color. These are the usual Classic estimates, not exact values.
-- Enum.TradeskillRelativeDifficulty: 0 optimal (orange), 1 medium (yellow), 2 easy (green), 3 trivial (grey).
ns.SKILLUP_CHANCE = { [0] = 1.0, [1] = 0.75, [2] = 0.25, [3] = 0 }
ns.DIFF_NAMES = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
ns.DIFF_COLORS = {
	[0] = { 1.00, 0.50, 0.25 },
	[1] = { 1.00, 1.00, 0.00 },
	[2] = { 0.25, 0.75, 0.25 },
	[3] = { 0.60, 0.60, 0.60 },
}

ns.DEFAULTS = {
	countBagsFree = true,   -- items already in your bags cost nothing
	crafts = 10,            -- crafts used for the shopping list
	prices = {},            -- [itemID] = copper, set with /cpath price (for vendor items)
	chars = {},
	window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
	debugLog = {},
}
