-- LevelPace: namespace, events, saved data and slash commands
local addonName, ns = ...

local GetTime = GetTime
local UnitLevel = UnitLevel
local UnitGUID = UnitGUID
local UnitName = UnitName
local format = string.format
local floor = math.floor

local frame = CreateFrame("Frame")
ns.frame = frame
ns.modules = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Returns nil for secret values, so math on them can never error.
function ns.Num(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return tonumber(v)
end

function ns.Print(msg)
	print("|cff66ccffLevelPace:|r " .. msg)
end

-- 3725 -> "1h 02m", 125 -> "2m 05s", 40 -> "40s"
function ns.Clock(sec)
	sec = floor((sec or 0) + 0.5)
	if sec >= 3600 then
		return format("%dh %02dm", floor(sec / 3600), floor(sec % 3600 / 60))
	elseif sec >= 60 then
		return format("%dm %02ds", floor(sec / 60), sec % 60)
	end
	return format("%ds", sec)
end

function ns.Comma(n)
	local s = format("%d", floor((n or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function NewLevelRecord()
	return { b = {}, xp = { kill = 0, quest = 0, other = 0 }, kills = 0, deaths = 0, maxIdle = 0, started = time() }
end

local function MergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then
				db[k] = {}
				MergeDefaults(db[k], v)
			else
				db[k] = v
			end
		elseif type(v) == "table" and type(db[k]) == "table" then
			MergeDefaults(db[k], v)
		end
	end
end

-- Points the addon at the current character's record for the current level.
function ns.SelectCharacter()
	local guid = UnitGUID("player")
	local name = UnitName("player")
	local key = (guid and not (issecretvalue and issecretvalue(guid))) and tostring(guid) or name or "unknown"
	local char = ns.db.chars[key]
	if not char then
		char = { name = name, levels = {}, zones = {} }
		ns.db.chars[key] = char
	end
	char.name = name or char.name
	char.class = select(2, UnitClass("player"))
	ns.char = char
	ns.SelectLevel(UnitLevel("player"))
end

function ns.SelectLevel(level)
	level = ns.Num(level) or 1
	ns.level = level
	local rec = ns.char.levels[level]
	if not rec then
		rec = NewLevelRecord()
		ns.char.levels[level] = rec
	end
	ns.rec = rec
end

function ns.NewSession()
	ns.session = {
		b = {}, xp = { kill = 0, quest = 0, other = 0 }, kills = 0, deaths = 0, maxIdle = 0,
		start = GetTime(), started = time(), gained = 0,
	}
	ns.sessionZones = {}
	ns.samples = {}
	ns.killXP = {}
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}

-- Modules call ns.On("EVENT", fn). Events that do not exist in this client are skipped.
function ns.On(event, fn)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		ns.Debug("Event not valid in this client:", event)
		return
	end
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		frame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			list[i](event, ...)
		end
	end
end)

function ns.AddModule(m)
	ns.modules[#ns.modules + 1] = m
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	LevelPaceDB = LevelPaceDB or {}
	MergeDefaults(LevelPaceDB, ns.DEFAULTS)
	ns.db = LevelPaceDB
	ns.NewSession()
	for _, m in ipairs(ns.modules) do
		if m.Register then
			m.Register()
		end
	end
	ns.On("PLAYER_LOGIN", function()
		ns.SelectCharacter()
		for _, m in ipairs(ns.modules) do
			if m.Start then
				m.Start()
			end
		end
		ns.Debug("Started: level", ns.level)
	end)
	ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
		if ns.rec then
			ns.rec.done = time()
		end
		ns.SelectLevel(newLevel)
		ns.killXP = {}
		for _, m in ipairs(ns.modules) do
			if m.OnLevelUp then
				m.OnLevelUp()
			end
		end
		ns.Debug("Level up:", ns.level)
	end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_LEVELPACE1 = "/lp"
SLASH_LEVELPACE2 = "/levelpace"
SlashCmdList.LEVELPACE = function(input)
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "report" then
		ns.ToggleReport()
	elseif cmd == "hud" then
		ns.ToggleHUD()
	elseif cmd == "lock" then
		ns.db.hud.locked = not ns.db.hud.locked
		ns.Print(ns.db.hud.locked and "HUD locked." or "HUD unlocked, drag to move.")
	elseif cmd == "reset" then
		ns.NewSession()
		ns.Print("Session reset.")
	elseif cmd == "debug" then
		ns.ToggleDebugWindow(arg)
	else
		ns.Print("/lp (report), /lp hud, /lp lock, /lp reset, /lp debug, /lpdebug")
	end
end

SLASH_LEVELPACEDEBUG1 = "/lpdebug"
SlashCmdList.LEVELPACEDEBUG = function(input)
	ns.ToggleDebugWindow((input or ""):lower())
end
