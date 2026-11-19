-- SessionJournal: movable live session tracker (stream-capture friendly)
local addonName, ns = ...

local Debug = ns.Debug

local CreateFrame = CreateFrame
local format = string.format

local LiveTracker = {}
ns.LiveTracker = LiveTracker

local frame
local ticker

local ROWS = {
	{ key = "elapsed", label = "Elapsed" },
	{ key = "zone", label = "Zone" },
	{ key = "zones", label = "Zones visited" },
	{ key = "loot", label = "Loot" },
	{ key = "deaths", label = "Deaths" },
	{ key = "gold", label = "Gold" },
}

local ROW_HEIGHT = 16
local WIDTH = 230

local function TrackerSettings()
	return ns.db.profile.tracker
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local t = TrackerSettings()
	t.point, t.relativePoint, t.x, t.y = point or "CENTER", relativePoint or "CENTER", x or 0, y or 0
end

local function ApplyPosition()
	local t = TrackerSettings()
	frame:ClearAllPoints()
	frame:SetPoint(t.point or "CENTER", UIParent, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
end

local function Refresh()
	if not frame or not frame:IsShown() then return end
	local s = ns.Tracker:GetCurrent()
	local v = frame.values
	if not s or not ns.Tracker:IsLive(s) then
		v.elapsed:SetText("--")
		v.zone:SetText("--")
		v.zones:SetText("0")
		v.loot:SetText("0")
		v.deaths:SetText("0")
		v.gold:SetText("--")
		return
	end
	v.elapsed:SetText(ns.FormatClock(ns.SessionDuration(s)))
	local lastZone = s.zones[#s.zones]
	v.zone:SetText(lastZone and lastZone.name or "--")
	v.zones:SetText(tostring(ns.UniqueZoneCount(s)))
	v.loot:SetText(tostring(s.lootItems or 0))
	v.deaths:SetText(tostring(s.deathCount or 0))
	local m = s.money or {}
	v.gold:SetText(ns.FormatMoneyUI((m.last or 0) - (m.start or 0), true))
end

local function ApplyLockState()
	local locked = TrackerSettings().locked
	-- Locked = fully click-through so it never gets in the way during play/streaming
	frame:EnableMouse(not locked)
	frame.unlockHint:SetShown(not locked)
	if locked then
		frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	else
		frame:SetBackdropBorderColor(1, 0.82, 0, 1)
	end
end

local function ApplyAppearance()
	local t = TrackerSettings()
	frame:SetScale(t.scale or 1)
	frame:SetBackdropColor(0, 0, 0, t.bgAlpha or 0.65)
	ApplyLockState()
end

local function StartTicker()
	if ticker then return end
	ticker = C_Timer.NewTicker(1, Refresh)
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function CreateTrackerFrame()
	local f = CreateFrame("Frame", "SessionJournalLiveTracker", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, 30 + #ROWS * ROW_HEIGHT)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})

	f:SetScript("OnDragStart", function(self)
		if not TrackerSettings().locked then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -7)
	title:SetText("Session Journal")
	f.title = title

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPRIGHT", -8, -8)
	hint:SetText("drag / unlocked")
	f.unlockHint = hint

	f.values = {}
	for i, row in ipairs(ROWS) do
		local y = -24 - (i - 1) * ROW_HEIGHT
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 10, y)
		label:SetText(row.label)
		label:SetTextColor(0.75, 0.75, 0.75)

		local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		value:SetPoint("TOPRIGHT", -10, y)
		value:SetPoint("TOPLEFT", label, "TOPRIGHT", 8, 0)
		value:SetJustifyH("RIGHT")
		value:SetWordWrap(false)
		f.values[row.key] = value
	end

	f:SetScript("OnShow", function()
		StartTicker()
		Refresh()
	end)
	f:SetScript("OnHide", StopTicker)

	f:Hide()
	return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function LiveTracker:Init()
	if not frame then
		frame = CreateTrackerFrame()
		ApplyPosition()
		ApplyAppearance()
		ns.RegisterUpdateListener("LiveTracker", Refresh)
	end
	frame:SetShown(TrackerSettings().shown)
end

function LiveTracker:SetShown(shown)
	TrackerSettings().shown = shown and true or false
	if frame then
		frame:SetShown(TrackerSettings().shown)
	end
end

function LiveTracker:Toggle()
	self:SetShown(not TrackerSettings().shown)
	Debug:Log("Live tracker shown:", TrackerSettings().shown)
end

function LiveTracker:SetLocked(locked)
	TrackerSettings().locked = locked and true or false
	if frame then ApplyLockState() end
end

function LiveTracker:ToggleLock()
	self:SetLocked(not TrackerSettings().locked)
	return TrackerSettings().locked
end

function LiveTracker:ApplySettings()
	if frame then ApplyAppearance() end
end

function LiveTracker:ResetPosition()
	local t = TrackerSettings()
	t.point, t.relativePoint, t.x, t.y = "CENTER", "CENTER", 0, 200
	if frame then ApplyPosition() end
end
