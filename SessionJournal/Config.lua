-- SessionJournal: defaults and constants
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.ADDON_TITLE = "SessionJournal"

-- Constants
ns.HEARTBEAT_INTERVAL = 60      -- seconds between heartbeat writes
ns.DEBUG_LOG_MAX = 1000         -- max lines kept in the debug log
ns.DEATH_DEDUPE_SECONDS = 3     -- ignore duplicate PLAYER_DEAD fired within this window
ns.MAX_LIST_ENTRIES = 300       -- cap for deaths / achievements / quests / level lists per session

-- Session states stored in db.global.current
ns.STATE_OPEN = "open"          -- session is live (or the client crashed while it was live)
ns.STATE_CLOSED = "closed"      -- PLAYER_LOGOUT finalized it; committed at next fresh login unless it was a /reload

-- AceDB defaults. All characters share the "Default" profile (settings are account-wide),
-- and session data lives in .global so the logbook spans every character.
ns.defaults = {
	profile = {
		retention = 200,            -- keep the last N sessions
		minDurationMinutes = 2,     -- discard sessions shorter than this
		recapQuality = 3,           -- Enum.ItemQuality.Rare: minimum quality listed in recaps
		lootCap = 500,              -- max loot entries stored per session (beyond this only counts are kept)
		trackQuests = true,
		requestPlayed = false,      -- call RequestTimePlayed() at session start (prints a /played line in chat)
		recapFormat = "prose",      -- "prose" or "markdown"
		tracker = {
			shown = false,
			locked = false,
			scale = 1,
			bgAlpha = 0.65,
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 200,
		},
		logbook = {
			filter = "ALL",
			status = {},            -- AceGUI Frame status table (position / size)
			treeStatus = { treewidth = 240 },
		},
		copyStatus = {},
	},
	global = {
		nextId = 1,
		sessions = {},              -- archived sessions, oldest first
		current = nil,              -- the open (or logout-closed) session
		debugLog = {},
	},
}
