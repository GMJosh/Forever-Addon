-- ReturnFromBreak: "New Zones" section (data from Data\Zones.lua)
local addonName, ns = ...

local C_QuestLog = C_QuestLog
local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local format = string.format

local Clean = ns.Clean
local Color = ns.Color

local function MapName(mapID)
	if not mapID or mapID <= 0 or not C_Map.GetMapInfo then
		return nil
	end
	local info = C_Map.GetMapInfo(mapID)
	return info and Clean(info.name) or nil
end

local function IsUnlocked(entry)
	local q = tonumber(entry.unlockQuestID)
	if not q or q <= 0 then
		return false
	end
	return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) or false
end

local function HasWaypoint(entry)
	local mapID, x, y = tonumber(entry.startMapID), tonumber(entry.x), tonumber(entry.y)
	return mapID and mapID > 0 and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100
end

-- Sets a user waypoint at the entry's start location and super-tracks it.
-- Returns true on success.
function ns.SetZoneWaypoint(entry)
	if not HasWaypoint(entry) then
		ns.Print("No start location set for " .. tostring(entry.name) .. ".")
		return false
	end
	if not (C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		ns.Print("Map waypoints are not available.")
		return false
	end
	local mapID = tonumber(entry.startMapID)
	if not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print(format("Can't place a waypoint on %s (map %d).", MapName(mapID) or "that map", mapID))
		ns.Debug("CanSetUserWaypointOnMap false for", mapID)
		return false
	end
	local point = UiMapPoint.CreateFromCoordinates(mapID, entry.x / 100, entry.y / 100)
	local wasSet = C_Map.SetUserWaypoint(point)
	if wasSet and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	ns.Debug("SetUserWaypoint", entry.name, mapID, entry.x, entry.y, "->", wasSet)
	if wasSet then
		ns.Print(format("Waypoint set: %s (%.1f, %.1f) on %s.", entry.questGiver or entry.name, entry.x, entry.y, MapName(mapID) or ("map " .. mapID)))
	end
	return wasSet
end

local function Build()
	local rows = {}
	local list = ns.Zones or {}
	local real, pending = 0, 0

	for _, entry in ipairs(list) do
		if type(entry) == "table" and not entry.example and entry.name then
			real = real + 1
			if not IsUnlocked(entry) then
				pending = pending + 1

				local title = Color(ns.COLOR_WHITE, entry.name)
				local q = tonumber(entry.unlockQuestID)
				if q and q > 0 and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q) then
					title = title .. "  " .. Color(ns.COLOR_GOLD, "(quest in progress)")
				end

				local details = {}
				if entry.questGiver then
					local where = MapName(tonumber(entry.startMapID))
					local coords = HasWaypoint(entry) and format(" (%.1f, %.1f)", entry.x, entry.y) or ""
					details[#details + 1] = "Talk to " .. entry.questGiver .. (where and (" in " .. where) or "") .. coords
				end
				if q and q > 0 then
					local qTitle = C_QuestLog.GetTitleForQuestID and Clean(C_QuestLog.GetTitleForQuestID(q))
					details[#details + 1] = "Unlock quest: " .. (qTitle or ("#" .. q))
				end
				if entry.note and entry.note ~= "" then
					details[#details + 1] = Color(ns.COLOR_DIM, entry.note)
				end

				local text = title
				if #details > 0 then
					text = text .. "\n" .. table.concat(details, "\n")
				end

				rows[#rows + 1] = {
					kind = "action",
					text = text,
					indent = 1,
					buttonText = "Waypoint",
					buttonEnabled = HasWaypoint(entry) and true or false,
					tooltip = MapName(tonumber(entry.uiMapID)),
					onClick = function() ns.SetZoneWaypoint(entry) end,
				}
			end
		end
	end

	if real == 0 then
		rows[#rows + 1] = { kind = "empty", text = "No zone data yet. Add entries to Data\\Zones.lua and /reload." }
	elseif pending == 0 then
		rows[#rows + 1] = { kind = "good", text = "All listed zones are unlocked." }
	end
	ns.Debug("Zones: entries", real, "pending", pending)
	return rows
end

ns.Sections.zones = { Build = Build }
