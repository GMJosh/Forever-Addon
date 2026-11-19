-- ReturnFromBreak: debug log (SavedVariable ReturnFromBreakDebugLog) and copyable debug window
-- Never print() debug output. Use ns.Debug(...) and view it with /rfbdebug.
local addonName, ns = ...

local date = date
local select = select
local tostring = tostring
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local issecretvalue = issecretvalue

-- Messages logged before ADDON_LOADED are buffered here and flushed into the SavedVariable
local pending = {}
local log = pending

local function SafeToString(v)
	if issecretvalue and issecretvalue(v) then
		return "<secret>"
	end
	return tostring(v)
end

function ns.Debug(...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = SafeToString((select(i, ...)))
	end
	tinsert(log, date("%H:%M:%S") .. " " .. tconcat(parts, " "))
	while #log > ns.DEBUG_LOG_MAX do
		tremove(log, 1)
	end
end

-- Called from OnInitialize once SavedVariables are available
function ns.InitDebugLog()
	if type(ReturnFromBreakDebugLog) ~= "table" then
		ReturnFromBreakDebugLog = {}
	end
	log = ReturnFromBreakDebugLog
	for i = 1, #pending do
		tinsert(log, pending[i])
	end
	pending = nil
	while #log > ns.DEBUG_LOG_MAX do
		tremove(log, 1)
	end
end

local debugFrame

local function CreateDebugWindow()
	local frame = CreateFrame("Frame", "ReturnFromBreakDebugFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(640, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText("ReturnFromBreak Debug Log  (Ctrl+A, Ctrl+C to copy)")

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 6, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -26, 6)

	local editBox = CreateFrame("EditBox", nil, scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetFontObject(GameFontHighlightSmall)
	editBox:SetWidth(590)
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scrollFrame:SetScrollChild(editBox)

	frame.editBox = editBox
	tinsert(UISpecialFrames, "ReturnFromBreakDebugFrame")
	frame:Hide()
	return frame
end

function ns.ToggleDebugWindow(msg)
	msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""
	if msg == "clear" then
		if type(ReturnFromBreakDebugLog) == "table" then
			wipe(ReturnFromBreakDebugLog)
		end
		print("|cff33ff99ReturnFromBreak|r: debug log cleared.")
		if debugFrame and debugFrame:IsShown() then
			debugFrame.editBox:SetText("")
		end
		return
	end

	if not debugFrame then
		debugFrame = CreateDebugWindow()
	end
	if debugFrame:IsShown() and msg ~= "show" then
		debugFrame:Hide()
		return
	end
	debugFrame.editBox:SetText(tconcat(log, "\n"))
	debugFrame:Show()
end
