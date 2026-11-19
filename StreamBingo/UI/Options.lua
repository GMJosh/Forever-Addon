-- StreamBingo: AceConfig options, registered into Blizzard Settings
local addonName, ns = ...

local Options = {}
ns.Options = Options

local ipairs = ipairs
local tostring = tostring

local CORNERS = {
	TOPLEFT = "Top Left",
	TOPRIGHT = "Top Right",
	BOTTOMLEFT = "Bottom Left",
	BOTTOMRIGHT = "Bottom Right",
}

local function RefreshBoard()
	if ns.Board then ns.Board:Refresh() end
end

local function RefreshBridgeLayout()
	if ns.Bridge then ns.Bridge:ApplyLayout() end
end

local function BuildDetectorArgs()
	local args = {}
	local order = 1
	for _, cat in ipairs(ns.CATEGORY_ORDER) do
		args["hdr_" .. cat] = {
			type = "header",
			name = ns.CATEGORY_LABELS[cat],
			order = order,
		}
		order = order + 1
		for _, sq in ipairs(ns.SQUARES) do
			if sq.category == cat then
				args[sq.key] = {
					type = "toggle",
					name = sq.id .. ". " .. sq.label,
					desc = sq.desc .. "\n\nKey: " .. sq.key .. "\nExtra byte: " .. sq.extra,
					width = "full",
					order = order,
					get = function() return ns.db.detectors[sq.key] end,
					set = function(_, v)
						ns.db.detectors[sq.key] = v
						RefreshBoard()
					end,
				}
				order = order + 1
			end
		end
	end
	return args
end

local function BuildOptions()
	return {
		type = "group",
		name = "StreamBingo",
		childGroups = "tab",
		args = {
			general = {
				type = "group",
				name = "General",
				order = 1,
				args = {
					intro = {
						type = "description",
						order = 1,
						name = "Detects in-game moments for Twitch Stream Bingo and broadcasts them through an on-screen pixel strip read by the companion app.\n",
					},
					boardShown = {
						type = "toggle",
						name = "Show streamer board",
						order = 2,
						get = function() return ns.db.board.shown end,
						set = function(_, v) ns.Board:SetShown(v) end,
					},
					boardLocked = {
						type = "toggle",
						name = "Lock board position",
						order = 3,
						get = function() return ns.db.board.locked end,
						set = function(_, v) ns.db.board.locked = v end,
					},
					showDisabled = {
						type = "toggle",
						name = "Show disabled squares on board",
						order = 4,
						get = function() return ns.db.board.showDisabled end,
						set = function(_, v)
							ns.db.board.showDisabled = v
							RefreshBoard()
						end,
					},
					boardScale = {
						type = "range",
						name = "Board scale",
						order = 5,
						min = 0.5, max = 2, step = 0.05,
						get = function() return ns.db.board.scale end,
						set = function(_, v)
							ns.db.board.scale = v
							if ns.Board then ns.Board:ApplySettings() end
						end,
					},
					resetPos = {
						type = "execute",
						name = "Reset board position",
						order = 6,
						func = function() ns.Board:ResetPosition() end,
					},
					resetSession = {
						type = "execute",
						name = "Reset session",
						desc = "Clears every fired square and the wipe history used by One-Shot Boss.",
						order = 7,
						confirm = true,
						func = function() ns.ResetSession() end,
					},
					debugHdr = { type = "header", name = "Debug", order = 20 },
					openDebug = {
						type = "execute",
						name = "Open debug log",
						order = 21,
						func = function() ns.Debug:ToggleWindow() end,
					},
					clearDebug = {
						type = "execute",
						name = "Clear debug log",
						order = 22,
						func = function() ns.Debug:Clear() end,
					},
				},
			},
			detectors = {
				type = "group",
				name = "Squares",
				order = 2,
				args = BuildDetectorArgs(),
			},
			thresholds = {
				type = "group",
				name = "Thresholds",
				order = 3,
				args = {
					repairGold = {
						type = "range",
						name = "Huge repair bill (gold)",
						desc = "Repair All cost at or above this fires the Huge Repair Bill square.",
						order = 1,
						min = 100, max = 100000, softMax = 20000, step = 100,
						width = "double",
						get = function() return ns.db.thresholds.repairGold end,
						set = function(_, v) ns.db.thresholds.repairGold = v end,
					},
					wipePercent = {
						type = "range",
						name = "Low wipe: boss HP below %",
						order = 3,
						min = 1, max = 50, step = 1,
						width = "double",
						get = function() return ns.db.thresholds.wipePercent end,
						set = function(_, v) ns.db.thresholds.wipePercent = v end,
					},
					raidOnly = {
						type = "toggle",
						name = "Raid squares only fire inside raids",
						desc = "Boss Killed, One-Shot Boss and Wipe Under X% only count in raid instances. Off: dungeons count too.",
						order = 5,
						width = "full",
						get = function() return ns.db.thresholds.raidSquaresRaidOnly end,
						set = function(_, v) ns.db.thresholds.raidSquaresRaidOnly = v end,
					},
				},
			},
			bridge = {
				type = "group",
				name = "Pixel Bridge",
				order = 4,
				args = {
					warn = {
						type = "description",
						order = 0,
						name = "|cffff8800The companion app reads exact colors. Disable HDR, color-blind filters, gamma/contrast tweaks, ReShade and any overlay over the strip. See BRIDGE_PROTOCOL.md.|r\n",
					},
					enabled = {
						type = "toggle",
						name = "Show pixel strip",
						order = 1,
						get = function() return ns.db.bridge.enabled end,
						set = function(_, v) ns.Bridge:SetEnabled(v) end,
					},
					testMode = {
						type = "toggle",
						name = "Test mode (cycle fake events)",
						desc = "Pushes a fake event for each square in turn with the TEST flag set. Real session data is not touched.",
						order = 2,
						get = function() return ns.db.bridge.testMode end,
						set = function(_, v) ns.Bridge:SetTestMode(v) end,
					},
					worldFrame = {
						type = "toggle",
						name = "Parent to WorldFrame (survives Alt-Z)",
						order = 3,
						width = "full",
						get = function() return ns.db.bridge.parentToWorldFrame end,
						set = function(_, v)
							ns.db.bridge.parentToWorldFrame = v
							RefreshBridgeLayout()
						end,
					},
					corner = {
						type = "select",
						name = "Screen corner",
						order = 4,
						values = CORNERS,
						get = function() return ns.db.bridge.corner end,
						set = function(_, v)
							ns.db.bridge.corner = v
							RefreshBridgeLayout()
						end,
					},
					blockSize = {
						type = "range",
						name = "Block size (physical pixels)",
						order = 5,
						min = 1, max = 32, step = 1,
						get = function() return ns.db.bridge.blockSize end,
						set = function(_, v)
							ns.db.bridge.blockSize = v
							RefreshBridgeLayout()
						end,
					},
					offsetX = {
						type = "range",
						name = "Offset X (pixels inward)",
						order = 6,
						min = 0, max = 2000, softMax = 400, step = 1,
						get = function() return ns.db.bridge.offsetX end,
						set = function(_, v)
							ns.db.bridge.offsetX = v
							RefreshBridgeLayout()
						end,
					},
					offsetY = {
						type = "range",
						name = "Offset Y (pixels inward)",
						order = 7,
						min = 0, max = 2000, softMax = 400, step = 1,
						get = function() return ns.db.bridge.offsetY end,
						set = function(_, v)
							ns.db.bridge.offsetY = v
							RefreshBridgeLayout()
						end,
					},
					holdTime = {
						type = "range",
						name = "Minimum hold per event (seconds)",
						desc = "Each event frame stays on screen at least this long. Bursts are queued.",
						order = 8,
						min = 0.25, max = 10, step = 0.05,
						get = function() return ns.db.bridge.holdTime end,
						set = function(_, v) ns.db.bridge.holdTime = v end,
					},
				},
			},
		},
	}
end

function Options:Register()
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "StreamBingo")
	self.categoryID = categoryID
	ns.Debug:Log("Options registered, categoryID=" .. tostring(categoryID))
end
