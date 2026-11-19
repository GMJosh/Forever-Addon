-- LevelPace: debug log and window (/lpdebug)
local addonName, ns = ...

local date = date
local format = string.format
local tconcat = table.concat
local tinsert = table.insert
local tremove = table.remove

local buffer = {}
local window

function ns.Debug(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	local line = format("%s %s", date("%H:%M:%S"), tconcat(parts, " "))
	local log = ns.db and ns.db.debugLog or buffer
	tinsert(log, line)
	while #log > ns.DEBUG_MAX do
		tremove(log, 1)
	end
end

local function BuildWindow()
	local f = CreateFrame("Frame", "CraftPathDebugFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(560, 360)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.TitleText:SetText("CraftPath debug log")
	local scroll = CreateFrame("ScrollFrame", "CraftPathDebugScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(500)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	scroll:SetScrollChild(edit)
	f.edit = edit
	f:Hide()
	tinsert(UISpecialFrames, "CraftPathDebugFrame")
	return f
end

function ns.ToggleDebugWindow(arg)
	if arg == "clear" then
		wipe(ns.db.debugLog)
		ns.Print("Debug log cleared.")
		return
	end
	window = window or BuildWindow()
	if window:IsShown() then
		window:Hide()
		return
	end
	window.edit:SetText(tconcat(ns.db.debugLog, "\n"))
	window:Show()
end
