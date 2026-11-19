-- StreamMoments: namespace, events, saved data, helpers, the Moment() entry point and slash commands
local addonName, ns = ...

local format = string.format
local floor = math.floor
local time = time

local frame = CreateFrame("Frame")
local handlers = {}

ns.session = { level = 0, loot = 0, boss = 0, death = 0, skill = 0, rare = 0, zone = 0 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Values that may be secret (Midnight restrictions) come back as nil instead of erroring.
function ns.Str(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return type(v) == "string" and v or nil
end

function ns.Num(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return tonumber(v)
end

function ns.Print(msg)
	print("|cffff9933StreamMoments:|r " .. msg)
end

function ns.Clock(sec)
	sec = floor(sec or 0)
	local h, m, s = floor(sec / 3600), floor(sec % 3600 / 60), sec % 60
	if h > 0 then
		return format("%dh %02dm %02ds", h, m, s)
	elseif m > 0 then
		return format("%dm %02ds", m, s)
	end
	return format("%ds", s)
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

function ns.Char()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or ""
	local key = name .. "-" .. realm
	local char = ns.db.chars[key]
	if not char then
		char = { name = name }
		ns.db.chars[key] = char
	end
	return char
end

---------------------------------------------------------------------------
-- Events: ns.On("EVENT", fn). Events that do not exist in this client are skipped (and noted in the debug log).
---------------------------------------------------------------------------

function ns.On(event, fn)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		ns.Debug("Event not valid in this client:", event)
		return false
	end
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		frame:RegisterEvent(event)
	end
	list[#list + 1] = fn
	return true
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			list[i](event, ...)
		end
	end
end)

-- Registered first, so the database exists before any other handler runs.
ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then
		return
	end
	StreamMomentsDB = StreamMomentsDB or {}
	MergeDefaults(StreamMomentsDB, ns.DEFAULTS)
	ns.db = StreamMomentsDB
	ns.Debug("Loaded")
end)

---------------------------------------------------------------------------
-- A moment: log it, count it, and show a banner. opts: icon (texture), link (item link), color, sound (soundkit id)
---------------------------------------------------------------------------

function ns.Moment(kind, title, subtitle, opts)
	local t = ns.TYPE_BY_KEY[kind]
	if not t or not ns.db then
		return
	end
	opts = opts or {}
	if not (ns.db.enabled[kind] or opts.test) then
		ns.Debug("Moment skipped (turned off):", kind, title)
		return
	end
	ns.Debug("Moment:", kind, title, subtitle or "")
	if not opts.test then
		ns.session[kind] = (ns.session[kind] or 0) + 1
		local log = ns.db.log
		log[#log + 1] = { t = time(), kind = kind, title = title, text = subtitle or "", link = opts.link }
		while #log > ns.LOG_MAX do
			table.remove(log, 1)
		end
		if ns.UpdateLog then
			ns.UpdateLog()
		end
	end
	if ns.ShowBanner then
		ns.ShowBanner({ kind = kind, title = title, subtitle = subtitle or "", icon = opts.icon, color = opts.color or t.color, sound = opts.sound })
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
	ns.Print("/sm - open the window (log and settings)")
	ns.Print("/sm test [level|loot|boss|death|skill|rare|zone] - show a sample banner")
	ns.Print("/sm lock - lock or unlock the banner (unlocked = drag it to move)")
	ns.Print("/sm bg [dark|clear|green|magenta] - banner background (green and magenta are for OBS chroma key)")
	ns.Print("/sm scale 1.2, /sm time 5 - banner size and seconds on screen")
	ns.Print("/sm clear - empty the log   |   /smdebug - debug window")
end

SLASH_STREAMMOMENTS1 = "/sm"
SLASH_STREAMMOMENTS2 = "/streammoments"
SlashCmdList.STREAMMOMENTS = function(input)
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	arg = (arg or ""):lower()
	if cmd == "" or cmd == "show" then
		ns.ToggleWindow()
	elseif cmd == "test" then
		ns.TestMoment(arg ~= "" and arg or nil)
	elseif cmd == "lock" then
		ns.SetLocked(not ns.db.locked)
	elseif cmd == "bg" then
		if ns.BACKGROUNDS[arg] then
			ns.db.background = arg
			ns.ApplyBanner()
			ns.Print("Background: " .. arg)
		else
			ns.Print("Choose dark, clear, green or magenta.")
		end
	elseif cmd == "scale" then
		local n = tonumber(arg)
		if n and n >= 0.5 and n <= 3 then
			ns.db.scale = n
			ns.ApplyBanner()
		else
			ns.Print("Usage: /sm scale 1.2 (between 0.5 and 3)")
		end
	elseif cmd == "time" then
		local n = tonumber(arg)
		if n and n >= 2 and n <= 30 then
			ns.db.duration = n
		else
			ns.Print("Usage: /sm time 5 (seconds, 2 to 30)")
		end
	elseif cmd == "clear" then
		wipe(ns.db.log)
		if ns.UpdateLog then
			ns.UpdateLog()
		end
		ns.Print("Log cleared.")
	elseif cmd == "debug" then
		ns.ToggleDebugWindow(arg)
	else
		Help()
	end
end

SLASH_STREAMMOMENTSDEBUG1 = "/smdebug"
SlashCmdList.STREAMMOMENTSDEBUG = function(input)
	ns.ToggleDebugWindow((input or ""):lower())
end
