-- SessionJournal: AceConfig options, registered in the Blizzard Settings panel
local addonName, ns = ...

local format = string.format

local Options = {}
ns.Options = Options

local function P()
	return ns.db.profile
end

local function QualityValues()
	local values = {}
	for q = 0, 5 do
		local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q)
		local hex
		if C_Item and C_Item.GetItemQualityColor then
			local r, g, b = C_Item.GetItemQualityColor(q)
			if r then
				hex = format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
			end
		end
		values[q] = hex and (hex .. name .. "|r") or name
	end
	return values
end

local function BuildOptions()
	return {
		type = "group",
		name = "SessionJournal",
		args = {
			intro = {
				order = 1,
				type = "description",
				name = "Writes a diary of every play session (login to logout). /sj opens the logbook.\n",
			},
			openLogbook = {
				order = 2,
				type = "execute",
				name = "Open logbook",
				func = function() ns.Logbook:Open() end,
			},
			openDebug = {
				order = 3,
				type = "execute",
				name = "Debug log",
				func = function() ns.Debug:ToggleWindow() end,
			},
			journal = {
				order = 10,
				type = "group",
				inline = true,
				name = "Journal",
				args = {
					retention = {
						order = 1,
						type = "range",
						name = "Sessions to keep",
						desc = "Oldest sessions beyond this number are removed.",
						min = 10, max = 1000, step = 10,
						get = function() return P().retention end,
						set = function(_, v)
							P().retention = v
							ns.Tracker:ApplyRetention()
						end,
					},
					minDuration = {
						order = 2,
						type = "range",
						name = "Minimum session length (minutes)",
						desc = "Sessions shorter than this are discarded when they close.",
						min = 0, max = 30, step = 1,
						get = function() return P().minDurationMinutes end,
						set = function(_, v) P().minDurationMinutes = v end,
					},
					recapFormat = {
						order = 3,
						type = "select",
						name = "Default recap format",
						values = { prose = "Prose", markdown = "Discord / Markdown" },
						get = function() return P().recapFormat end,
						set = function(_, v) P().recapFormat = v end,
					},
				},
			},
			tracking = {
				order = 20,
				type = "group",
				inline = true,
				name = "Tracking",
				args = {
					recapQuality = {
						order = 1,
						type = "select",
						name = "Recap loot quality",
						desc = "Loot at or above this quality is listed in recaps. Everything is still recorded (up to the loot cap).",
						values = QualityValues,
						get = function() return P().recapQuality end,
						set = function(_, v) P().recapQuality = v end,
					},
					lootCap = {
						order = 2,
						type = "range",
						name = "Loot cap (unique items per session)",
						min = 50, max = 2000, step = 50,
						get = function() return P().lootCap end,
						set = function(_, v) P().lootCap = v end,
					},
					trackQuests = {
						order = 3,
						type = "toggle",
						name = "Track quests turned in",
						get = function() return P().trackQuests end,
						set = function(_, v) P().trackQuests = v end,
					},
					requestPlayed = {
						order = 4,
						type = "toggle",
						name = "Request /played at session start",
						desc = "Asks the server for /played when a new session starts so the recap can show a /played delta. This prints the normal /played lines in chat (they can't be cleanly suppressed). /played you type yourself is always captured.",
						width = "full",
						get = function() return P().requestPlayed end,
						set = function(_, v) P().requestPlayed = v end,
					},
				},
			},
			tracker = {
				order = 30,
				type = "group",
				inline = true,
				name = "Live tracker",
				args = {
					shown = {
						order = 1,
						type = "toggle",
						name = "Show live tracker",
						get = function() return P().tracker.shown end,
						set = function(_, v) ns.LiveTracker:SetShown(v) end,
					},
					locked = {
						order = 2,
						type = "toggle",
						name = "Lock (click-through)",
						get = function() return P().tracker.locked end,
						set = function(_, v) ns.LiveTracker:SetLocked(v) end,
					},
					scale = {
						order = 3,
						type = "range",
						name = "Scale",
						min = 0.5, max = 2, step = 0.05,
						isPercent = true,
						get = function() return P().tracker.scale end,
						set = function(_, v)
							P().tracker.scale = v
							ns.LiveTracker:ApplySettings()
						end,
					},
					bgAlpha = {
						order = 4,
						type = "range",
						name = "Background opacity",
						min = 0, max = 1, step = 0.05,
						isPercent = true,
						get = function() return P().tracker.bgAlpha end,
						set = function(_, v)
							P().tracker.bgAlpha = v
							ns.LiveTracker:ApplySettings()
						end,
					},
					reset = {
						order = 5,
						type = "execute",
						name = "Reset position",
						func = function() ns.LiveTracker:ResetPosition() end,
					},
				},
			},
			data = {
				order = 40,
				type = "group",
				inline = true,
				name = "Data",
				args = {
					deleteAll = {
						order = 1,
						type = "execute",
						name = "Delete all sessions",
						desc = "Removes every archived session. The current session is kept.",
						confirm = true,
						confirmText = "Delete ALL archived SessionJournal sessions? This can't be undone.",
						func = function() ns.Tracker:DeleteAll() end,
					},
				},
			},
		},
	}
end

function Options:Register()
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "SessionJournal")
	self.categoryID = categoryID
end
