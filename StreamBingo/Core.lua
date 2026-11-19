-- StreamBingo: addon object, AceDB init, session state, FireSquare, slash commands
local addonName, ns = ...

local SB = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.SB = SB

local Debug = ns.Debug

local type = type
local time = time
local floor = math.floor
local min = math.min
local max = math.max
local tinsert = table.insert
local tremove = table.remove
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local bor = bit.bor
local lshift = bit.lshift
local InCombatLockdown = InCombatLockdown

local RECENT_MAX = 12

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

function ns.IsSecret(v)
	if issecretvalue then
		return issecretvalue(v) and true or false
	end
	return false
end

-- Returns v if it is a usable (non-secret) number, else nil.
function ns.SafeNumber(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- Returns v if it is a usable (non-secret, non-empty) string, else nil.
function ns.SafeString(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "string" or v == "" then
		return nil
	end
	return v
end

-- Returns v if it is a usable (non-secret) boolean, else nil.
function ns.SafeBool(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "boolean" then
		return nil
	end
	return v
end

-- Clamp to a byte 0..255 (non-secret numbers only).
function ns.ToByte(v)
	v = ns.SafeNumber(v)
	if not v then return 0 end
	return max(0, min(255, floor(v)))
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

---------------------------------------------------------------------------
-- Session state
---------------------------------------------------------------------------

function ns.GetSession()
	return ns.db.session
end

function ns.GetCount(id)
	return ns.db.session.counts[id] or 0
end

-- 24-bit bitfield of every square fired this session, split into 3 bytes.
-- Bit (id - 1): byte1 = IDs 1-8, byte2 = IDs 9-16, byte3 = IDs 17-24.
function ns.GetBitfieldBytes(overrideCounts)
	local counts = overrideCounts or ns.db.session.counts
	local b1, b2, b3 = 0, 0, 0
	for id, n in pairs(counts) do
		if n and n > 0 and id >= 1 and id <= ns.MAX_SQUARE_ID then
			local bitIndex = id - 1
			if bitIndex < 8 then
				b1 = bor(b1, lshift(1, bitIndex))
			elseif bitIndex < 16 then
				b2 = bor(b2, lshift(1, bitIndex - 8))
			else
				b3 = bor(b3, lshift(1, bitIndex - 16))
			end
		end
	end
	return b1, b2, b3
end

function ns.IsDetectorEnabled(key)
	return ns.db.detectors[key] and true or false
end

-- Central entry point: every detector calls this.
-- opts.manual: fired via /bingo test (bypasses the detector toggle)
function ns.FireSquare(key, extra, opts)
	local sq = ns.SQUARES_BY_KEY[key]
	if not sq then
		Debug:Log("FireSquare: unknown key", key)
		return false
	end
	local manual = opts and opts.manual
	if not manual and not ns.IsDetectorEnabled(key) then
		Debug:Log("FireSquare: detector disabled, ignored", key)
		return false
	end

	local session = ns.db.session
	local count = (session.counts[sq.id] or 0) + 1
	session.counts[sq.id] = count
	session.total = (session.total or 0) + 1

	local extraByte = ns.ToByte(extra)
	tinsert(session.recent, 1, { id = sq.id, t = time(), extra = extraByte, manual = manual or nil })
	while #session.recent > RECENT_MAX do
		tremove(session.recent)
	end

	Debug:Log("FIRE", sq.id, key, "count=" .. count, "extra=" .. extraByte, manual and "(manual)" or "")

	if ns.Bridge then
		local flags = manual and ns.FLAG_MANUAL or 0
		ns.Bridge:PushEvent(sq.id, count, extraByte, flags)
	end
	if ns.Board then
		ns.Board:Refresh(sq.id)
	end
	return true
end

function ns.ResetSession()
	local session = ns.db.session
	wipe(session.counts)
	wipe(session.wipedEncounters)
	wipe(session.recent)
	session.total = 0
	session.startedAt = time()
	Debug:Log("Session reset")
	if ns.Detectors and ns.Detectors.OnSessionReset then
		ns.Detectors:OnSessionReset()
	end
	if ns.Bridge then
		ns.Bridge:PushReset()
	end
	if ns.Board then
		ns.Board:Refresh()
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function SB:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("StreamBingoDB", ns.DB_DEFAULTS, true)
	ns.db = self.db.global
	Debug:Attach(ns.db.debugLog)

	if (ns.db.session.startedAt or 0) == 0 then
		ns.db.session.startedAt = time()
	end

	if ns.Options then
		ns.Options:Register()
	end

	self:RegisterChatCommand("bingo", "SlashBingo")
	self:RegisterChatCommand("bingodebug", "SlashDebug")
	Debug:Log("OnInitialize complete, version", C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?")
end

function SB:OnEnable()
	Debug:Log("OnEnable")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintHelp()
	print("|cff9966ffStreamBingo|r commands:")
	print("  /bingo - toggle the streamer board")
	print("  /bingo reset - reset the session (clears all fired squares)")
	print("  /bingo test <squareKey> - fire a square manually")
	print("  /bingo test - list square keys")
	print("  /bingo bridge - toggle the pixel bridge strip")
	print("  /bingo testmode - toggle bridge test mode (cycles fake events)")
	print("  /bingo config - open settings")
	print("  /bingodebug - open the debug log (/bingodebug clear to wipe it)")
end

function ns.OpenConfig()
	if not InCombatLockdown() and ns.Options and ns.Options.categoryID and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.Options.categoryID)
	else
		-- Combat-safe fallback: standalone AceConfigDialog window
		LibStub("AceConfigDialog-3.0"):Open(addonName)
	end
end

function SB:SlashBingo(input)
	input = (input or ""):match("^%s*(.-)%s*$")
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		if ns.Board then ns.Board:Toggle() end
	elseif cmd == "reset" then
		ns.ResetSession()
		print("|cff9966ffStreamBingo|r: session reset.")
	elseif cmd == "test" then
		local key = rest and rest:lower() or ""
		if key == "" then
			local keys = {}
			for _, sq in ipairs(ns.SQUARES) do
				keys[#keys + 1] = sq.id .. "=" .. sq.key
			end
			print("|cff9966ffStreamBingo|r square keys: " .. table.concat(keys, ", "))
		elseif ns.SQUARES_BY_KEY[key] then
			ns.FireSquare(key, 0, { manual = true })
			print("|cff9966ffStreamBingo|r: fired " .. key)
		else
			print("|cff9966ffStreamBingo|r: unknown square key '" .. key .. "'. Type /bingo test for the list.")
		end
	elseif cmd == "bridge" then
		if ns.Bridge then
			local on = ns.Bridge:Toggle()
			print("|cff9966ffStreamBingo|r: pixel bridge " .. (on and "ON" or "OFF"))
		end
	elseif cmd == "testmode" then
		if ns.Bridge then
			local on = ns.Bridge:SetTestMode(not ns.db.bridge.testMode)
			print("|cff9966ffStreamBingo|r: bridge test mode " .. (on and "ON" or "OFF"))
		end
	elseif cmd == "config" or cmd == "options" then
		ns.OpenConfig()
	else
		PrintHelp()
	end
end

function SB:SlashDebug(input)
	input = (input or ""):match("^%s*(.-)%s*$"):lower()
	if input == "clear" then
		Debug:Clear()
		print("|cff9966ffStreamBingo|r: debug log cleared.")
		return
	end
	Debug:ToggleWindow()
end
