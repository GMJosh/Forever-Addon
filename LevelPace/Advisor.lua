-- LevelPace: "where should I level" advice from ForeverDB quest and dungeon data (Data\Quests.lua, Data\Dungeons.lua).
-- Data from ForeverDB.net (https://foreverdb.net).
local addonName, ns = ...

local format = string.format
local sort = table.sort

local BELOW = 5 -- quests up to this many levels under you still give decent XP
local ABOVE = 2 -- and this many over

local function PlayerSide()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or "B"
end

local function Done(id)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(id)
	end
	return false
end

local function InLog(id)
	return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and (C_QuestLog.GetLogIndexForQuestID(id) or 0) > 0
end

-- Quests you could still do at this level: right side, level in range, not done.
local function Eligible(q, level, side)
	if q.k ~= 1 then
		return false
	end
	if q.s ~= "B" and side ~= "B" and q.s ~= side then
		return false
	end
	if q.l < level - BELOW or q.l > level + ABOVE or q.r > level then
		return false
	end
	return not Done(q.id)
end

-- Zones ranked by how many quests are left for you. Returns { { map, name, count, lo, hi }, ... }.
function ns.AdvisorZones(level)
	local data = ns.QuestData
	if not data then
		return {}
	end
	local side = PlayerSide()
	local by = {}
	for _, q in ipairs(data.list) do
		if Eligible(q, level, side) then
			local z = by[q.m]
			if not z then
				z = { map = q.m, name = data.zones[q.m] or ("Zone " .. q.m), count = 0, lo = q.l, hi = q.l }
				by[q.m] = z
			end
			z.count = z.count + 1
			if q.l < z.lo then z.lo = q.l end
			if q.l > z.hi then z.hi = q.l end
		end
	end
	local list = {}
	for _, z in pairs(by) do
		list[#list + 1] = z
	end
	sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)
	return list
end

-- The zone map you are standing in, as a map id that exists in the quest data (walks up from sub-zones).
function ns.AdvisorCurrentZone()
	local data = ns.QuestData
	if not (data and C_Map and C_Map.GetBestMapForUnit) then
		return nil
	end
	local map = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while map and map > 0 and guard < 6 do
		if data.zones[map] then
			return map
		end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		map = info and info.parentMapID
		guard = guard + 1
	end
	return nil
end

-- Quests to pick up in one zone, the ones closest to your level first. Skips quests already in your log.
function ns.AdvisorQuests(map, level, limit)
	local data = ns.QuestData
	local out = {}
	if not data then
		return out
	end
	local side = PlayerSide()
	for _, q in ipairs(data.list) do
		if q.m == map and Eligible(q, level, side) and not InLog(q.id) then
			out[#out + 1] = q
		end
	end
	sort(out, function(a, b)
		local da, db = math.abs(a.l - level), math.abs(b.l - level)
		if da ~= db then
			return da < db
		end
		return a.n < b.n
	end)
	for i = #out, limit + 1, -1 do
		out[i] = nil
	end
	return out
end

-- Dungeons and raids whose level range fits you. Only ones that exist in Classic or are announced for Forever.
function ns.AdvisorDungeons(level)
	local out = {}
	for _, d in ipairs(ns.DungeonData or {}) do
		if (d.st == "classic" or d.st == "forever") and level >= d.lo - 2 and level <= d.hi + 2 then
			out[#out + 1] = d
		end
	end
	sort(out, function(a, b)
		return a.lo < b.lo
	end)
	return out
end
