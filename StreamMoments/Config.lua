-- StreamMoments: constants and defaults
local addonName, ns = ...

ns.ADDON = addonName
ns.DEBUG_MAX = 1000       -- max lines in the debug log
ns.LOG_MAX = 500          -- max moments kept in the log
ns.QUEUE_MAX = 8          -- banners waiting at once; extra moments go to the log only

-- The kinds of moments, in display order. color = accent color of the banner.
ns.TYPES = {
	{ key = "level", label = "Level-ups",           color = { 1.00, 0.82, 0.00 } },
	{ key = "loot",  label = "Rare drops",          color = { 0.64, 0.21, 0.93 } },
	{ key = "boss",  label = "Boss kills",          color = { 0.90, 0.30, 0.20 } },
	{ key = "death", label = "Deaths",              color = { 0.70, 0.10, 0.10 } },
	{ key = "skill", label = "Profession ranks",    color = { 0.20, 0.75, 0.75 } },
	{ key = "rare",  label = "Rare mob kills",      color = { 0.75, 0.75, 0.95 } },
	{ key = "zone",  label = "New zones discovered", color = { 0.30, 0.60, 1.00 } },
}
ns.TYPE_BY_KEY = {}
for _, t in ipairs(ns.TYPES) do
	ns.TYPE_BY_KEY[t.key] = t
end

ns.QUALITY_NAMES = { [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

-- Banner backgrounds. "green" and "magenta" are solid colors for chroma-keying in OBS.
ns.BACKGROUNDS = {
	dark    = { 0.05, 0.05, 0.08, 0.88 },
	clear   = { 0.00, 0.00, 0.00, 0.35 },
	green   = { 0.00, 1.00, 0.00, 1.00 },
	magenta = { 1.00, 0.00, 1.00, 1.00 },
}

ns.DEFAULTS = {
	enabled = { level = true, loot = true, boss = true, death = true, skill = true, rare = true, zone = true },
	minQuality = 3,        -- 3 rare, 4 epic, 5 legendary
	sound = true,
	duration = 5,          -- seconds each banner stays
	scale = 1,
	locked = true,         -- locked = click-through
	background = "dark",
	banner = { point = "TOP", relPoint = "TOP", x = 0, y = -160 },
	window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
	chars = {},
	log = {},
	debugLog = {},
}
