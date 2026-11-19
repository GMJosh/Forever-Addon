-- SessionJournal: addon object, DB init, shared helpers, slash commands
local addonName, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local SJ = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.SJ = SJ

local Debug = ns.Debug

local floor = math.floor
local abs = math.abs
local format = string.format
local tostring = tostring
local type = type
local pairs = pairs
local InCombatLockdown = InCombatLockdown

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

-- True if v is a 12.0 secret value. Safe on clients without issecretvalue.
function ns.IsSecret(v)
	if issecretvalue then
		return issecretvalue(v) and true or false
	end
	return false
end

-- Returns v if it's a usable (non-secret) string, else nil.
function ns.SafeString(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "string" or v == "" then
		return nil
	end
	return v
end

-- Returns v if it's a usable (non-secret) number, else nil.
function ns.SafeNumber(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- Registers an event only if the client knows it.
function ns.RegisterEventSafe(obj, event, handler)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		Debug:Log("Event not valid on this client, skipped:", event)
		return false
	end
	obj:RegisterEvent(event, handler)
	return true
end

-- "1h 23m", "12m 05s", "45s"
function ns.FormatDuration(seconds)
	seconds = floor(seconds or 0)
	if seconds < 0 then seconds = 0 end
	local h = floor(seconds / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return format("%dh %02dm", h, m)
	elseif m > 0 then
		return format("%dm %02ds", m, s)
	end
	return format("%ds", s)
end

-- "h:mm:ss" clock-style for the live tracker
function ns.FormatClock(seconds)
	seconds = floor(seconds or 0)
	if seconds < 0 then seconds = 0 end
	return format("%d:%02d:%02d", floor(seconds / 3600), floor((seconds % 3600) / 60), seconds % 60)
end

local function GroupThousands(n)
	local s = tostring(n)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

-- Plain-text money for exports: "+1,234g 56s 7c". Zero parts are omitted.
function ns.FormatMoneyPlain(copper, withSign)
	copper = floor(copper or 0)
	local sign = ""
	if copper < 0 then
		sign = "-"
	elseif withSign and copper > 0 then
		sign = "+"
	end
	copper = abs(copper)
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	local gSym = GOLD_AMOUNT_SYMBOL or "g"
	local sSym = SILVER_AMOUNT_SYMBOL or "s"
	local cSym = COPPER_AMOUNT_SYMBOL or "c"
	local parts = {}
	if g > 0 then parts[#parts + 1] = GroupThousands(g) .. gSym end
	if s > 0 then parts[#parts + 1] = s .. sSym end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. cSym end
	return sign .. table.concat(parts, " ")
end

-- Money with coin icons for the UI.
function ns.FormatMoneyUI(copper, withSign)
	copper = floor(copper or 0)
	local sign = ""
	if copper < 0 then
		sign = "|cffff4040-|r"
	elseif withSign and copper > 0 then
		sign = "|cff40ff40+|r"
	end
	local amount = abs(copper)
	local text
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		text = C_CurrencyInfo.GetCoinTextureString(amount)
	elseif GetMoneyString then
		text = GetMoneyString(amount, true)
	else
		text = ns.FormatMoneyPlain(amount)
	end
	return sign .. text
end

-- "|cff...|Hitem:...|h[Name]|h|r" -> "[Name]" for plain-text exports.
function ns.StripLink(link)
	if not link then return "" end
	local name = link:match("|h%[(.-)%]|h")
	if name then
		return "[" .. name .. "]"
	end
	-- Fallback: remove any escape sequences
	local plain = link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn.-:", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
	return plain
end

function ns.CharKey(char)
	if not char then return "?" end
	return (char.name or "?") .. "-" .. (char.realm or "?")
end

function ns.ClassColoredName(char)
	if not char then return "?" end
	local name = char.name or "?"
	if char.class and C_ClassColor and C_ClassColor.GetClassColor then
		local color = C_ClassColor.GetClassColor(char.class)
		if color and color.WrapTextInColorCode then
			return color:WrapTextInColorCode(name)
		end
	end
	return name
end

---------------------------------------------------------------------------
-- Lightweight internal update notifications (Tracker -> UI)
---------------------------------------------------------------------------
local listeners = {}

function ns.RegisterUpdateListener(key, fn)
	listeners[key] = fn
end

function ns.NotifyUpdate(reason)
	for _, fn in pairs(listeners) do
		fn(reason)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function SJ:OnInitialize()
	-- true = all characters share the "Default" profile (account-wide settings)
	self.db = LibStub("AceDB-3.0"):New("SessionJournalDB", ns.defaults, true)
	ns.db = self.db
	Debug:Attach(self.db.global.debugLog)
	Debug:Log("OnInitialize: DB ready. Archived sessions:", #self.db.global.sessions)

	if ns.Options and ns.Options.Register then
		ns.Options:Register()
	end

	self:RegisterChatCommand("sj", "HandleSlash")
	self:RegisterChatCommand("sessionjournal", "HandleSlash")
end

function SJ:OnEnable()
	Debug:Log("OnEnable")
	if ns.Tracker and ns.Tracker.Enable then
		ns.Tracker:Enable()
	end
	if ns.LiveTracker and ns.LiveTracker.Init then
		ns.LiveTracker:Init()
	end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
function SJ:OpenConfig()
	if InCombatLockdown() then
		self:Print("Settings can't be opened in combat. Try again after combat.")
		return
	end
	if ns.Options and ns.Options.categoryID and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.Options.categoryID)
	else
		LibStub("AceConfigDialog-3.0"):Open(addonName)
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP_LINES = {
	"|cff33ff99SessionJournal|r commands:",
	"  /sj - toggle the logbook",
	"  /sj tracker - toggle the live session tracker",
	"  /sj lock - lock or unlock the live tracker",
	"  /sj recap - open the current session recap (copyable)",
	"  /sj config - open settings",
	"  /sj debug - open the debug log window",
	"  /sj help - show this help",
}

function SJ:HandleSlash(input)
	local cmd = self:GetArgs(input or "", 1)
	cmd = cmd and cmd:lower() or ""
	Debug:Log("Slash:", cmd)

	if cmd == "" then
		ns.Logbook:Toggle()
	elseif cmd == "tracker" then
		ns.LiveTracker:Toggle()
	elseif cmd == "lock" or cmd == "unlock" then
		local locked = ns.LiveTracker:ToggleLock()
		self:Print(locked and "Live tracker locked." or "Live tracker unlocked. Drag it to move.")
	elseif cmd == "recap" then
		local session = ns.Tracker:GetCurrent()
		if session then
			ns.Logbook:OpenCopyWindow(session)
		else
			self:Print("No session is being recorded yet.")
		end
	elseif cmd == "config" or cmd == "options" then
		self:OpenConfig()
	elseif cmd == "debug" then
		Debug:ToggleWindow()
	else
		for i = 1, #HELP_LINES do
			print(HELP_LINES[i])
		end
	end
end
