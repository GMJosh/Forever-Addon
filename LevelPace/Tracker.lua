-- LevelPace: time buckets (where every second of play goes)
local addonName, ns = ...

local GetTime = GetTime
local GetUnitSpeed = GetUnitSpeed
local IsMounted = IsMounted
local IsFalling = IsFalling
local IsResting = IsResting
local UnitOnTaxi = UnitOnTaxi
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsAFK = UnitIsAFK

local M = {}
ns.AddModule(M)

local last           -- GetTime() of the previous tick
local loadingSince   -- GetTime() when the current loading screen began
local lastMove = "foot"
local stillFor = 0
local idleRun = 0
local lootOpen = false
local open = {}      -- NPC windows currently open (merchant, bank, mail, quest dialogs...)
local tickCount = 0

ns.currentBucket = "idle"

local function Zone()
	local z = GetRealZoneText and GetRealZoneText()
	if z and z ~= "" and not (issecretvalue and issecretvalue(z)) then
		return z
	end
	return "Unknown"
end
ns.Zone = Zone

local function AddTo(t, key, secs)
	t[key] = (t[key] or 0) + secs
end

local function ZoneEntry(zones, name)
	local z = zones[name]
	if not z then
		z = { secs = 0, xp = 0 }
		zones[name] = z
	end
	return z
end
ns.ZoneEntry = ZoneEntry

local function Add(bucket, secs)
	if secs <= 0 or not ns.rec then
		return
	end
	AddTo(ns.rec.b, bucket, secs)
	AddTo(ns.session.b, bucket, secs)
	local zone = Zone()
	ZoneEntry(ns.char.zones, zone).secs = ZoneEntry(ns.char.zones, zone).secs + secs
	ZoneEntry(ns.sessionZones, zone).secs = ZoneEntry(ns.sessionZones, zone).secs + secs
end

local function Classify(dt)
	if loadingSince then
		return "loading"
	end
	if UnitIsDeadOrGhost("player") then
		return "dead"
	end
	if UnitOnTaxi("player") then
		return "flight"
	end
	if UnitAffectingCombat("player") then
		stillFor = 0
		return "fight"
	end
	local speed = ns.Num(GetUnitSpeed("player")) or 0
	if speed > 0 or IsFalling() then
		stillFor = 0
		-- A window cannot stay open while you move; clear any that missed their close event.
		if next(open) then
			wipe(open)
		end
		lastMove = IsMounted() and "mount" or "foot"
		return lastMove
	end
	if lootOpen then
		return "loot"
	end
	if next(open) then
		return "town"
	end
	stillFor = stillFor + dt
	if stillFor >= ns.IDLE_AFTER then
		if IsResting() and not UnitIsAFK("player") then
			return "town"
		end
		return "idle"
	end
	return lastMove
end

local function Tick()
	if not ns.rec then
		return
	end
	local now = GetTime()
	local dt = now - (last or now)
	last = now
	if dt <= 0 then
		return
	end
	if dt > 5 then
		dt = ns.TICK -- the game stalled; do not credit the gap
	end
	local bucket = Classify(dt)
	ns.currentBucket = bucket
	Add(bucket, dt)
	if bucket == "idle" then
		idleRun = idleRun + dt
		if idleRun > ns.rec.maxIdle then
			ns.rec.maxIdle = idleRun
		end
		if idleRun > ns.session.maxIdle then
			ns.session.maxIdle = idleRun
		end
	else
		idleRun = 0
	end
	tickCount = tickCount + 1
	if ns.XPSample and tickCount % 10 == 0 then
		ns.XPSample(now)
	end
	if ns.UpdateHUD then
		ns.UpdateHUD()
	end
end

local function Open(name)
	return function()
		open[name] = true
	end
end

local function Close(name)
	return function()
		open[name] = nil
	end
end

function M.Register()
	ns.On("LOADING_SCREEN_ENABLED", function()
		loadingSince = GetTime()
	end)
	ns.On("LOADING_SCREEN_DISABLED", function()
		if loadingSince and ns.rec then
			Add("loading", GetTime() - loadingSince)
		end
		loadingSince = nil
		last = GetTime() -- do not count the same seconds again on the next tick
	end)
	ns.On("LOOT_OPENED", function() lootOpen = true end)
	ns.On("LOOT_CLOSED", function() lootOpen = false end)
	local pairsToWatch = {
		{ "MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant" },
		{ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "bank" },
		{ "MAIL_SHOW", "MAIL_CLOSED", "mail" },
		{ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "auction" },
		{ "TRAINER_SHOW", "TRAINER_CLOSED", "trainer" },
		{ "GOSSIP_SHOW", "GOSSIP_CLOSED", "gossip" },
		{ "QUEST_DETAIL", "QUEST_FINISHED", "quest" },
		{ "QUEST_PROGRESS", "QUEST_FINISHED", "quest" },
		{ "QUEST_COMPLETE", "QUEST_FINISHED", "quest" },
	}
	for _, p in ipairs(pairsToWatch) do
		ns.On(p[1], Open(p[3]))
		ns.On(p[2], Close(p[3]))
	end
	ns.On("QUEST_FINISHED", function()
		open.quest = nil
	end)
	ns.On("PLAYER_DEAD", function()
		if ns.rec then
			ns.rec.deaths = ns.rec.deaths + 1
			ns.session.deaths = ns.session.deaths + 1
		end
	end)
end

function M.Start()
	last = GetTime()
	C_Timer.NewTicker(ns.TICK, Tick)
end
