-- SessionJournal: debug log + copyable debug window
-- Debug output NEVER goes to chat. It is stored in SessionJournalDB.global.debugLog
-- (capped at ns.DEBUG_LOG_MAX lines) and shown in a scrollable, copy-pasteable EditBox via /sj debug.
local addonName, ns = ...

local date = date
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local tostring = tostring
local select = select

local Debug = {}
ns.Debug = Debug

-- Lines logged before the DB exists are buffered here and flushed on Attach().
local pending = {}
local log = pending
local debugFrame

local function SafeToString(v)
	if issecretvalue and issecretvalue(v) then
		return "<secret>"
	end
	return tostring(v)
end

function Debug:Log(...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = SafeToString((select(i, ...)))
	end
	local entry = date("%H:%M:%S") .. " " .. tconcat(parts, " ")
	tinsert(log, entry)
	while #log > ns.DEBUG_LOG_MAX do
		tremove(log, 1)
	end
	if debugFrame and debugFrame:IsShown() then
		Debug:RefreshWindow()
	end
end

-- Called from OnInitialize once AceDB is ready.
function Debug:Attach(savedLog)
	for i = 1, #pending do
		tinsert(savedLog, pending[i])
	end
	pending = nil
	log = savedLog
	while #log > ns.DEBUG_LOG_MAX do
		tremove(log, 1)
	end
end

function Debug:Clear()
	wipe(log)
	if debugFrame and debugFrame:IsShown() then
		Debug:RefreshWindow()
	end
end

local function CreateDebugWindow()
	local frame = CreateFrame("Frame", "SessionJournalDebugFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(640, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.TitleText then
		frame.TitleText:SetText("SessionJournal Debug Log")
	end

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 6, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg or frame, "BOTTOMRIGHT", -26, 34)

	local editBox = CreateFrame("EditBox", nil, scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetFontObject(GameFontHighlightSmall)
	editBox:SetWidth(590)
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scrollFrame:SetScrollChild(editBox)
	scrollFrame:SetScript("OnSizeChanged", function(self, w)
		editBox:SetWidth(w)
	end)

	local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectBtn:SetSize(110, 22)
	selectBtn:SetPoint("BOTTOMLEFT", frame.InsetBg or frame, "BOTTOMLEFT", 6, 6)
	selectBtn:SetText("Select All")
	selectBtn:SetScript("OnClick", function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearBtn:SetSize(110, 22)
	clearBtn:SetPoint("LEFT", selectBtn, "RIGHT", 8, 0)
	clearBtn:SetText("Clear Log")
	clearBtn:SetScript("OnClick", function()
		Debug:Clear()
	end)

	frame.editBox = editBox
	frame.scrollFrame = scrollFrame
	frame:Hide()
	return frame
end

function Debug:RefreshWindow()
	if not debugFrame then return end
	debugFrame.editBox:SetText(tconcat(log, "\n"))
end

function Debug:ToggleWindow()
	if not debugFrame then
		debugFrame = CreateDebugWindow()
	end
	if debugFrame:IsShown() then
		debugFrame:Hide()
	else
		Debug:RefreshWindow()
		debugFrame:Show()
		-- Scroll to the newest entries
		C_Timer.After(0, function()
			if debugFrame.scrollFrame then
				debugFrame.scrollFrame:SetVerticalScroll(debugFrame.scrollFrame:GetVerticalScrollRange())
			end
		end)
	end
end
