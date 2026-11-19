-- ReturnFromBreak: defaults and constants
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.TITLE = "Return From Break"

-- AceDB defaults. Settings live in profile, snapshots in char.
ns.DEFAULTS = {
	profile = {
		showOnLogin = true,
		loginDelay = 3,
		scale = 1,
		locked = false,
		sections = {
			talents = true,
			quests = true,
			snapshot = true,
			zones = true,
		},
		window = {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 0,
		},
		maxCurrencyLines = 25,
	},
	char = {
		-- Written on PLAYER_LOGOUT (also fires on /reload)
		snapshot = nil,
		-- Copy of 'snapshot' taken at initial login. This is what we diff against,
		-- and it survives /reload because it is only replaced on a real login.
		baseline = nil,
		-- GetServerTime() at the most recent initial login
		sessionStart = nil,
	},
}

-- Order in which sections are stacked in the window
ns.SECTION_ORDER = { "talents", "quests", "snapshot", "zones" }

ns.SECTION_TITLES = {
	talents = "Unspent Talents",
	quests = "Current Quests",
	snapshot = "Since Last Time",
	zones = "New Zones",
}

ns.DEBUG_LOG_MAX = 1000

-- Colors
ns.COLOR_GOOD = "ff33ff33"
ns.COLOR_BAD = "ffff4040"
ns.COLOR_DIM = "ff9d9d9d"
ns.COLOR_GOLD = "ffffd100"
ns.COLOR_WHITE = "ffffffff"
