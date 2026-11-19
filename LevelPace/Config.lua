-- LevelPace: constants and defaults
local addonName, ns = ...

ns.ADDON = addonName
ns.TICK = 1                 -- seconds between tracker ticks
ns.IDLE_AFTER = 5           -- seconds standing still before the time counts as idle
ns.RATE_WINDOW = 600        -- seconds of history used for XP per hour
ns.RATE_MIN_SPAN = 30       -- need at least this many seconds of history for a rate
ns.KILL_SAMPLE = 20         -- kills averaged for "kills to level"
ns.DEBUG_MAX = 1000         -- max lines in the debug log
ns.ZONE_MIN_SECONDS = 120   -- zone needs this much time before it is ranked

-- Time buckets, in display order. waste = counts toward the "where did my time go" tips.
ns.BUCKETS = {
	{ key = "fight", label = "Fighting",          color = { 0.80, 0.25, 0.25 } },
	{ key = "loot",  label = "Looting",           color = { 0.85, 0.65, 0.20 } },
	{ key = "foot",  label = "Traveling on foot", color = { 0.35, 0.65, 0.90 }, waste = true },
	{ key = "mount", label = "Traveling mounted", color = { 0.30, 0.80, 0.80 }, waste = true },
	{ key = "flight", label = "On a flight path", color = { 0.55, 0.55, 0.95 }, waste = true },
	{ key = "town",  label = "Town and NPCs",     color = { 0.70, 0.55, 0.35 }, waste = true },
	{ key = "idle",  label = "Standing / AFK",    color = { 0.55, 0.55, 0.55 }, waste = true },
	{ key = "dead",  label = "Dead / corpse run", color = { 0.60, 0.20, 0.60 }, waste = true },
	{ key = "loading", label = "Loading screens", color = { 0.40, 0.40, 0.40 }, waste = true },
}
ns.BUCKET_BY_KEY = {}
for _, b in ipairs(ns.BUCKETS) do
	ns.BUCKET_BY_KEY[b.key] = b
end

ns.DEFAULTS = {
	hud = { shown = true, locked = false, scale = 1, point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -200 },
	report = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
	chars = {},
	debugLog = {},
}
