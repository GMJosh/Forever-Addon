-- StreamMoments: detects the moments (level-ups, drops, boss kills, deaths, profession ranks, rare kills, new zones)
local addonName, ns = ...

local GetTime = GetTime
local format = string.format
local floor = math.floor

local recent = {}       -- dedupe: key -> time seen
local lastLevelUp       -- GetTime() of the previous level-up this session
local encounterStart = {} -- encounter name -> GetTime() when it started
local sessionDeaths = 0

local function Recent(key, within)
	local now = GetTime()
	local last = recent[key]
	if last and now - last < within then
		return true
	end
	recent[key] = now
	return false
end

---------------------------------------------------------------------------
-- Level-ups
---------------------------------------------------------------------------

ns.On("PLAYER_LEVEL_UP", function(_, level)
	level = ns.Num(level)
	if not level then
		return
	end
	local char = ns.Char()
	local now = time()
	local took
	if char.lastLevelAt then
		took = now - char.lastLevelAt
	end
	char.lastLevelAt = now
	local sub = took and took > 0 and took < 86400 * 30 and ("Took " .. ns.Clock(took)) or "Keep going!"
	ns.Moment("level", "LEVEL " .. level .. "!", sub)
end)

---------------------------------------------------------------------------
-- Drops: your own loot of the chosen quality or better
---------------------------------------------------------------------------

local function Announce(link, quality)
	local name, icon
	if C_Item and C_Item.GetItemInfo then
		name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
	elseif GetItemInfo then
		name, _, _, _, _, _, _, _, _, icon = GetItemInfo(link)
	end
	local r, g, b = 1, 1, 1
	if C_Item and C_Item.GetItemQualityColor then
		r, g, b = C_Item.GetItemQualityColor(quality)
	end
	local color = { r or 1, g or 1, b or 1 }
	local label = ns.QUALITY_NAMES[quality] or "Great"
	ns.Moment("loot", name or "New item", label .. " drop", { icon = icon, link = link, color = color })
end

local function CheckLoot(link, attempt)
	local quality
	if C_Item and C_Item.GetItemQualityByID then
		quality = ns.Num(C_Item.GetItemQualityByID(link))
	end
	if not quality then
		if attempt < 4 then
			C_Timer.After(1, function()
				CheckLoot(link, attempt + 1)
			end)
		else
			ns.Debug("Loot quality unavailable:", link)
		end
		return
	end
	if quality >= ns.db.minQuality and quality <= 6 then
		Announce(link, quality)
	end
end

ns.On("CHAT_MSG_LOOT", function(_, text, playerName, _, _, _, _, _, _, _, _, _, guid)
	text = ns.Str(text)
	if not text then
		return
	end
	-- only your own loot: by GUID, or by name as a fallback
	local mine = false
	local g, myGUID = ns.Str(guid), ns.Str(UnitGUID("player"))
	if g and myGUID and g == myGUID then
		mine = true
	else
		local who, me = ns.Str(playerName), ns.Str(UnitName("player"))
		if who and me and Ambiguate(who, "short") == me then
			mine = true
		end
	end
	if not mine then
		return
	end
	local itemString = text:match("|H(item:[^|]+)|h")
	if not itemString or Recent("loot:" .. itemString, 4) then
		return
	end
	CheckLoot(text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or itemString, 1)
end)

---------------------------------------------------------------------------
-- Boss kills. ENCOUNTER_END is the main signal; BOSS_KILL is a backup. Both are noted in the debug log so we can
-- see which one this client actually fires.
---------------------------------------------------------------------------

local function BossDown(name, source)
	name = ns.Str(name)
	if not name or Recent("boss:" .. name, 15) then
		return
	end
	local started = encounterStart[name]
	local sub = started and ("Down in " .. ns.Clock(GetTime() - started)) or name
	ns.Debug("Boss kill via", source, name)
	ns.Moment("boss", started and name or "Boss defeated", started and sub or name)
end

ns.On("ENCOUNTER_START", function(_, id, name)
	name = ns.Str(name)
	if name then
		encounterStart[name] = GetTime()
	end
	ns.Debug("ENCOUNTER_START", tostring(ns.Num(id)), tostring(name))
end)

ns.On("ENCOUNTER_END", function(_, id, name, _, _, success)
	ns.Debug("ENCOUNTER_END", tostring(ns.Num(id)), tostring(ns.Str(name)), "success=" .. tostring(ns.Num(success)))
	if ns.Num(success) == 1 then
		BossDown(name, "ENCOUNTER_END")
	end
end)

ns.On("BOSS_KILL", function(_, id, name)
	ns.Debug("BOSS_KILL", tostring(ns.Num(id)), tostring(ns.Str(name)))
	BossDown(name, "BOSS_KILL")
end)

---------------------------------------------------------------------------
-- Deaths
---------------------------------------------------------------------------

ns.On("PLAYER_DEAD", function()
	if Recent("death", 5) then
		return
	end
	sessionDeaths = sessionDeaths + 1
	ns.Moment("death", "YOU DIED", "Death #" .. sessionDeaths .. " this session")
end)

---------------------------------------------------------------------------
-- Profession ranks (every 75 skill points). Uses the game's own "skill increased" message.
---------------------------------------------------------------------------

local RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

local function PatternFor(globalString)
	if type(globalString) ~= "string" then
		return nil
	end
	local p = globalString:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
	return "^" .. p .. "$"
end

local skillPattern = PatternFor(SKILL_RANK_UP)
local zonePattern = PatternFor(ERR_ZONE_EXPLORED)

if not skillPattern then
	ns.Debug("SKILL_RANK_UP missing: profession moments are off")
end
if not zonePattern then
	ns.Debug("ERR_ZONE_EXPLORED missing: zone discovery moments are off")
end

ns.On("CHAT_MSG_SKILL", function(_, text)
	text = ns.Str(text)
	if not (text and skillPattern) then
		return
	end
	local skill, rank = text:match(skillPattern)
	rank = tonumber(rank)
	if skill and rank and RANKS[rank] then
		ns.Moment("skill", skill .. " " .. rank, RANKS[rank] .. " reached")
	end
end)

---------------------------------------------------------------------------
-- New zones discovered (the "Discovered X: N experience gained" system message)
---------------------------------------------------------------------------

ns.On("CHAT_MSG_SYSTEM", function(_, text)
	text = ns.Str(text)
	if not (text and zonePattern) then
		return
	end
	local zone, xp = text:match(zonePattern)
	if zone then
		ns.Moment("zone", "DISCOVERED", zone .. (xp and (" (+" .. xp .. " XP)") or ""))
	end
end)

---------------------------------------------------------------------------
-- Rare mob kills: watch your target. When a rare, rare elite or world boss target dies, that is the moment.
---------------------------------------------------------------------------

local watch = { guid = nil, name = nil, class = nil }
local RARE = { rare = true, rareelite = true, worldboss = true }

local unitFrame = CreateFrame("Frame")
unitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid("UNIT_HEALTH") then
	ns.Debug("Event not valid in this client: UNIT_HEALTH (rare kills are off)")
else
	unitFrame:RegisterUnitEvent("UNIT_HEALTH", "target")
end
unitFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		watch.guid, watch.name, watch.class = nil, nil, nil
		if UnitExists("target") then
			local class = ns.Str(UnitClassification("target"))
			if class and RARE[class] then
				watch.guid = ns.Str(UnitGUID("target"))
				watch.name = ns.Str(UnitName("target"))
				watch.class = class
			end
		end
		return
	end
	-- UNIT_HEALTH on the target
	if not (watch.guid and watch.name) then
		return
	end
	local dead = UnitIsDead("target")
	if issecretvalue and issecretvalue(dead) then
		return
	end
	if dead and ns.Str(UnitGUID("target")) == watch.guid and not Recent("rare:" .. watch.guid, 60) then
		if watch.class == "worldboss" then
			ns.Moment("boss", "World boss down", watch.name)
		else
			ns.Moment("rare", "Rare slain", watch.name)
		end
	end
end)
