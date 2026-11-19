-- LevelPace: XP gained, XP per hour, time to level, kills to level
local addonName, ns = ...

local GetTime = GetTime
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local GetXPExhaustion = GetXPExhaustion
local ceil = math.ceil
local tremove = table.remove

local M = {}
ns.AddModule(M)

local lastXP, lastMax = 0, 1
local lastKillT, lastQuestT = -10, -10

local function Read()
	local xp = ns.Num(UnitXP("player"))
	local max = ns.Num(UnitXPMax("player"))
	return xp, max
end

-- Called by the tracker every 10 seconds: one point of "total XP gained this session".
function ns.XPSample(now)
	local s = ns.samples
	s[#s + 1] = { t = now, g = ns.session.gained }
	-- keep one point older than the window so the span can reach back far enough
	while #s > 2 and s[2].t < now - ns.RATE_WINDOW do
		tremove(s, 1)
	end
end

local function Credit(rec, zoneName, source, amount)
	rec.xp[source] = (rec.xp[source] or 0) + amount
	ns.session.xp[source] = (ns.session.xp[source] or 0) + amount
	ns.session.gained = ns.session.gained + amount
	ns.ZoneEntry(ns.char.zones, zoneName).xp = ns.ZoneEntry(ns.char.zones, zoneName).xp + amount
	ns.ZoneEntry(ns.sessionZones, zoneName).xp = ns.ZoneEntry(ns.sessionZones, zoneName).xp + amount
	if source == "kill" then
		rec.kills = rec.kills + 1
		ns.session.kills = ns.session.kills + 1
		local list = ns.killXP
		list[#list + 1] = amount
		while #list > ns.KILL_SAMPLE do
			tremove(list, 1)
		end
	end
end

local function OnXPUpdate()
	local xp, max = Read()
	if not xp or not max or not ns.rec then
		return
	end
	local delta = xp - lastXP
	if delta < 0 then
		delta = (lastMax - lastXP) + xp -- level up: the bar wrapped around
	end
	lastXP, lastMax = xp, max
	if delta <= 0 then
		return
	end
	-- Which record and zone earned it, captured now: a level-up can swap the record before we classify.
	local rec, zoneName, t = ns.rec, ns.Zone(), GetTime()
	C_Timer.After(0.25, function()
		local now = GetTime()
		local source = "other"
		if lastKillT >= t - 1 and lastKillT <= now then
			source = "kill"
		elseif lastQuestT >= t - 1 and lastQuestT <= now then
			source = "quest"
		end
		Credit(rec, zoneName, source, delta)
		ns.Debug("XP +" .. delta, source)
	end)
end

function M.Register()
	ns.On("PLAYER_XP_UPDATE", OnXPUpdate)
	ns.On("CHAT_MSG_COMBAT_XP_GAIN", function()
		lastKillT = GetTime()
	end)
	ns.On("QUEST_TURNED_IN", function()
		lastQuestT = GetTime()
	end)
end

function M.Start()
	lastXP, lastMax = Read()
	lastXP, lastMax = lastXP or 0, lastMax or 1
	ns.XPSample(GetTime())
end

function M.OnLevelUp()
	local _, max = Read()
	lastMax = max or lastMax
end

-- Everything the HUD and report need about progress to the next level.
function ns.XPStats()
	local xp, max = Read()
	local st = { level = ns.level, xp = xp or 0, max = max or 0 }
	if not xp or not max or max <= 0 then
		return st
	end
	st.pct = xp / max * 100
	st.remaining = max - xp
	st.rested = ns.Num(GetXPExhaustion()) or 0
	local s = ns.samples
	if s and s[1] then
		local now = GetTime()
		local span = now - s[1].t
		if span >= ns.RATE_MIN_SPAN then
			st.rate = (ns.session.gained - s[1].g) / span * 3600
			if st.rate > 0 then
				st.eta = st.remaining / (st.rate / 3600)
			end
		end
	end
	local list = ns.killXP
	if list and #list > 0 then
		local sum = 0
		for i = 1, #list do
			sum = sum + list[i]
		end
		st.avgKill = sum / #list
		st.killsLeft = ceil(st.remaining / st.avgKill)
	end
	return st
end
