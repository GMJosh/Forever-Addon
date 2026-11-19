-- ReturnFromBreak: addon object, lifecycle, events, slash commands
local addonName, ns = ...

local C_Timer = C_Timer
local GetServerTime = GetServerTime
local InCombatLockdown = InCombatLockdown

local RFB = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")
ns.addon = RFB

-- Section modules register themselves here: ns.Sections[key] = { Build = function() return rows end }
ns.Sections = ns.Sections or {}

-- User-facing chat message (not for debug output)
function ns.Print(msg)
	RFB:Print(msg)
end

-- Returns v if it is a usable (non-secret) value, else nil
local issecretvalue = issecretvalue
function ns.Clean(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

-- Wrap text in a |c color escape (hex is "aarrggbb")
function ns.Color(hex, text)
	return "|c" .. hex .. tostring(text) .. "|r"
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function RFB:OnInitialize()
	ns.InitDebugLog()
	self.db = LibStub("AceDB-3.0"):New("ReturnFromBreakDB", ns.DEFAULTS, true)
	ns.db = self.db

	-- Save the snapshot from AceDB's own PLAYER_LOGOUT handler. It fires before
	-- AceDB strips defaults / removes empty sections, so the write can't be lost
	-- to handler ordering.
	self.db.RegisterCallback(self, "OnDatabaseShutdown", "SaveLogoutSnapshot")

	if ns.SetupOptions then
		ns.SetupOptions(self)
	end

	self:RegisterChatCommand("rfb", "HandleSlash")
	self:RegisterChatCommand("rfbdebug", function(input) ns.ToggleDebugWindow(input) end)

	ns.Debug("OnInitialize: DB ready, profile =", self.db:GetCurrentProfile())
end

function RFB:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")

	-- Anything that can change what the window shows. Refresh is throttled and
	-- only happens while the window is visible.
	local refreshEvents = {
		"QUEST_LOG_UPDATE",
		"QUEST_WATCH_LIST_CHANGED",
		"QUEST_TURNED_IN",
		"SUPER_TRACKING_CHANGED",
		"TRAIT_CONFIG_UPDATED",
		"TRAIT_TREE_CURRENCY_INFO_UPDATED",
		"PLAYER_TALENT_UPDATE",
		"ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
		"PLAYER_LEVEL_UP",
		"PLAYER_MONEY",
		"CURRENCY_DISPLAY_UPDATE",
	}
	for _, event in ipairs(refreshEvents) do
		if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
			ns.Debug("OnEnable: skipping invalid event", event)
		else
			self:RegisterEvent(event, "RequestRefresh")
		end
	end
	ns.Debug("OnEnable: events registered")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function RFB:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
	ns.Debug("PLAYER_ENTERING_WORLD initial =", isInitialLogin, "reload =", isReloadingUi)
	if not isInitialLogin then
		-- Reloads and zoning: keep the existing baseline, do not auto-open
		return
	end

	-- Real login: the snapshot written at the previous logout becomes the baseline
	local char = self.db.char
	char.baseline = char.snapshot
	char.sessionStart = GetServerTime()
	ns.Debug("Baseline set from previous snapshot:", char.baseline and char.baseline.time or "none")

	if self.db.profile.showOnLogin then
		-- Small delay so quest log / currency data has populated
		local delay = tonumber(self.db.profile.loginDelay) or 3
		C_Timer.After(delay, function()
			ns.Debug("Auto-opening window after login")
			ns.UI:Show()
		end)
	end
end

function RFB:SaveLogoutSnapshot()
	-- Runs on PLAYER_LOGOUT, which also fires on /reload. That is fine: the
	-- baseline is only replaced on initial login.
	if ns.TakeSnapshot then
		local ok, snapOrErr = pcall(ns.TakeSnapshot)
		if ok and snapOrErr then
			self.db.char.snapshot = snapOrErr
			ns.Debug("Logout: snapshot saved")
		else
			ns.Debug("Logout: snapshot failed:", snapOrErr)
		end
	end
end

function RFB:PLAYER_REGEN_DISABLED()
	ns.UI:OnCombatStart()
end

function RFB:PLAYER_REGEN_ENABLED()
	ns.UI:OnCombatEnd()
end

local refreshPending = false

function RFB:RequestRefresh(event)
	if not ns.UI:IsShown() or refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = false
		if ns.UI:IsShown() then
			ns.Debug("Refresh (triggered by", event, ")")
			ns.UI:Refresh()
		end
	end)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

function RFB:OpenOptions()
	if InCombatLockdown() then
		ns.Print("Options can't be opened in combat.")
		return
	end
	if self.optionsCategoryID and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.optionsCategoryID)
	else
		LibStub("AceConfigDialog-3.0"):Open(addonName)
	end
end

function RFB:HandleSlash(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)") or ""
	if cmd == "" or cmd == "toggle" then
		ns.UI:Toggle()
	elseif cmd == "show" then
		ns.UI:Show()
	elseif cmd == "hide" then
		ns.UI:Hide()
	elseif cmd == "config" or cmd == "options" then
		self:OpenOptions()
	elseif cmd == "debug" then
		ns.ToggleDebugWindow("")
	elseif cmd == "resetpos" then
		ns.UI:ResetPosition()
		ns.Print("Window position reset.")
	else
		ns.Print("Commands:")
		ns.Print("  /rfb - toggle the window")
		ns.Print("  /rfb config - open options")
		ns.Print("  /rfb resetpos - reset window position")
		ns.Print("  /rfbdebug - debug log window (/rfbdebug clear)")
	end
end
