-- ReturnFromBreak: main window
--
-- One movable window with a scroll area that stacks every enabled section.
-- Footer: "Open Talents" (toggles the talent window), Refresh, Options.
local addonName, ns = ...

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_SuperTrack = C_SuperTrack
local GameTooltip = GameTooltip
local max = math.max
local pcall = pcall
local tinsert = table.insert

local UI = {}
ns.UI = UI

local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 560
local INDENT = 14
local ACTION_WIDTH = 86
local FOOTER_HEIGHT = 34

local frame, scrollFrame, content
local talentButton, talentPlaceholder
local rows = {}
local pendingHide = false

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local pos = ns.db.profile.window
	pos.point, pos.relativePoint, pos.x, pos.y = point, relativePoint, x, y
end

local function ApplyPosition()
	local pos = ns.db.profile.window
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
end

function UI:ResetPosition()
	local pos = ns.db.profile.window
	pos.point, pos.relativePoint, pos.x, pos.y = "CENTER", "CENTER", 0, 0
	if frame then
		ApplyPosition()
	end
end

function UI:ApplySettings()
	if not frame then
		return
	end
	frame:SetScale(ns.db.profile.scale or 1)
	ApplyPosition()
end

---------------------------------------------------------------------------
-- Quest click actions
---------------------------------------------------------------------------

local function FocusQuest(questID)
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		C_SuperTrack.SetSuperTrackedQuestID(questID)
		ns.Debug("SetSuperTrackedQuestID", questID)
	end
end

local function OpenMapForQuest(questID, mapID)
	if InCombatLockdown() then
		ns.Print("The map can't be opened from here during combat.")
		return
	end
	-- OpenWorldMap goes through WorldMapFrame:HandleUserActionOpenSelf, avoiding
	-- the ShowUIPanel + SetMapID taint path.
	if OpenWorldMap then
		OpenWorldMap(mapID)
		ns.Debug("OpenWorldMap", mapID, "for quest", questID)
	end
end

---------------------------------------------------------------------------
-- Row pool
---------------------------------------------------------------------------

local function Row_OnClick(self, button)
	local data = self.data
	if not data or data.kind ~= "quest" then
		return
	end
	if button == "RightButton" then
		FocusQuest(data.questID)
		OpenMapForQuest(data.questID, data.mapID)
	else
		FocusQuest(data.questID)
	end
end

local function Row_OnEnter(self)
	local data = self.data
	if not data then
		return
	end
	if data.kind == "quest" then
		self.highlight:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(data.title or "Quest", 1, 1, 1)
		if data.zone then
			GameTooltip:AddLine(data.zone, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: focus (super-track)", 0, 1, 0)
		GameTooltip:AddLine("Right-click: focus and open map", 0, 1, 0)
		GameTooltip:Show()
	elseif data.tooltip then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(data.tooltip, 1, 1, 1)
		GameTooltip:Show()
	end
end

local function Row_OnLeave(self)
	self.highlight:Hide()
	GameTooltip:Hide()
end

local function Action_OnClick(self)
	local data = self:GetParent().data
	if data and data.onClick then
		data.onClick()
	end
end

local function CreateRow()
	local row = CreateFrame("Button", nil, content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", Row_OnClick)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)

	local hl = row:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	hl:Hide()
	row.highlight = hl

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetWordWrap(true)
	row.text = text

	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetColorTexture(1, 0.82, 0, 0.35)
	line:SetPoint("BOTTOMLEFT", 0, 0)
	line:SetPoint("BOTTOMRIGHT", 0, 0)
	line:Hide()
	row.line = line

	local action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	action:SetSize(ACTION_WIDTH, 22)
	action:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
	action:SetScript("OnClick", Action_OnClick)
	action:Hide()
	row.action = action

	return row
end

local function ResetRows()
	for _, row in ipairs(rows) do
		row:Hide()
		row.data = nil
	end
end

local function GetRow(index)
	local row = rows[index]
	if not row then
		row = CreateRow()
		rows[index] = row
	end
	return row
end

-- Lays out one row at vertical offset y; returns its height
local function LayoutRow(row, data, y, width)
	row.data = data
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetWidth(width)
	row.highlight:Hide()
	row.line:Hide()
	row.action:Hide()

	local kind = data.kind
	local indent = (data.indent or 0) * INDENT
	local font = "GameFontHighlight"
	local topPad, bottomPad = 2, 2
	if kind == "header" then
		font = "GameFontNormalLarge"
		topPad, bottomPad = 10, 4
	elseif kind == "subheader" then
		font = "GameFontNormal"
		topPad = 6
	elseif kind == "empty" then
		font = "GameFontDisableSmall"
	elseif kind == "good" then
		font = "GameFontGreen"
	end
	row.text:SetFontObject(font)

	local textWidth = width - indent - 4
	if kind == "action" then
		textWidth = textWidth - ACTION_WIDTH - 8
		row.action:SetText(data.buttonText or "Go")
		row.action:SetEnabled(data.buttonEnabled ~= false)
		row.action:Show()
	end

	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", indent + 2, -topPad)
	row.text:SetWidth(textWidth)
	row.text:SetText(data.text or "")

	local height = row.text:GetStringHeight() + topPad + bottomPad
	if kind == "action" then
		height = max(height, 26)
	end
	if kind == "header" then
		row.line:Show()
	end
	row:SetHeight(height)

	-- Only quest rows (clicks) and rows with tooltips need the mouse
	row:EnableMouse(kind == "quest" or data.tooltip ~= nil)
	row:Show()
	return height
end

---------------------------------------------------------------------------
-- Talent button
---------------------------------------------------------------------------

local function ToggleTalents()
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
		PlayerSpellsUtil.ToggleClassTalentFrame()
	elseif TogglePlayerSpellsFrame then
		TogglePlayerSpellsFrame()
	elseif ToggleTalentFrame then
		ToggleTalentFrame()
	end
end

local function AttachTalentButton()
	if not frame then
		return
	end
	if not talentButton then
		talentButton = CreateFrame("Button", "ReturnFromBreakTalentButton", frame, "UIPanelButtonTemplate")
		talentButton:SetSize(130, 24)
		talentButton:SetText("Open Talents")
		talentButton:SetScript("OnClick", function()
			if InCombatLockdown() then
				return
			end
			ToggleTalents()
		end)
	end
	talentButton:SetParent(frame)
	talentButton:ClearAllPoints()
	talentButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 9)
	talentButton:Show()
	talentPlaceholder:Hide()
end

local function DetachTalentButton()
	if talentButton then
		talentButton:Hide()
	end
	if talentPlaceholder then
		talentPlaceholder:SetText("Talents (in combat)")
		talentPlaceholder:Disable()
		talentPlaceholder:Show()
	end
end

function UI:OnCombatStart()
	DetachTalentButton()
end

function UI:OnCombatEnd()
	if not frame then
		return
	end
	if pendingHide then
		pendingHide = false
		frame:SetAlpha(1)
		frame:Hide()
		return
	end
	if frame:IsShown() then
		AttachTalentButton()
		self:Refresh()
	end
end

---------------------------------------------------------------------------
-- Frame creation
---------------------------------------------------------------------------

local function CreateMainFrame()
	frame = CreateFrame("Frame", "ReturnFromBreakMainFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not ns.db.profile.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:SetScript("OnHide", function()
		GameTooltip:Hide()
	end)
	frame.TitleText:SetText(ns.TITLE)
	frame.CloseButton:SetScript("OnClick", function() UI:Hide() end)

	scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 6, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -26, FOOTER_HEIGHT)

	content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(WINDOW_WIDTH - 50, 10)
	scrollFrame:SetScrollChild(content)
	scrollFrame:SetScript("OnSizeChanged", function(self, w)
		if w and w > 0 then
			content:SetWidth(w)
		end
	end)

	-- Footer buttons
	talentPlaceholder = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	talentPlaceholder:SetSize(130, 24)
	talentPlaceholder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 9)
	talentPlaceholder:Hide()

	local options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	options:SetSize(90, 24)
	options:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
	options:SetText("Options")
	options:SetScript("OnClick", function() ns.addon:OpenOptions() end)

	local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	refresh:SetSize(90, 24)
	refresh:SetPoint("RIGHT", options, "LEFT", -6, 0)
	refresh:SetText("Refresh")
	refresh:SetScript("OnClick", function() UI:Refresh() end)

	tinsert(UISpecialFrames, "ReturnFromBreakMainFrame")
	frame:Hide()
	UI:ApplySettings()
	ns.Debug("Main frame created")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function UI:IsShown()
	return frame ~= nil and frame:IsShown() and not pendingHide
end

function UI:Show()
	if not frame then
		CreateMainFrame()
	end
	pendingHide = false
	frame:SetAlpha(1)
	if not frame:IsShown() then
		if frame:IsProtected() and InCombatLockdown() then
			ns.Print("Can't open the window right now (combat). Try again after combat.")
			return
		end
		frame:Show()
	end
	if InCombatLockdown() then
		DetachTalentButton()
	else
		AttachTalentButton()
	end
	self:Refresh()
end

function UI:Hide()
	if not frame or not frame:IsShown() then
		return
	end
	if frame:IsProtected() and InCombatLockdown() then
		-- Secure child still attached (combat began before we could detach it):
		-- fade out now, really hide when combat ends.
		frame:SetAlpha(0)
		pendingHide = true
		ns.Debug("Hide deferred until combat ends")
		return
	end
	frame:Hide()
end

function UI:Toggle()
	if self:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function UI:Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	ResetRows()

	local width = content:GetWidth()
	if not width or width < 50 then
		width = WINDOW_WIDTH - 50
	end

	local y, index = 0, 0
	local sections = ns.db.profile.sections
	local anyShown = false
	for _, key in ipairs(ns.SECTION_ORDER) do
		local section = ns.Sections[key]
		if section and sections[key] then
			anyShown = true
			index = index + 1
			y = y + LayoutRow(GetRow(index), { kind = "header", text = ns.SECTION_TITLES[key] }, y, width)

			local ok, result = pcall(section.Build)
			if not ok then
				ns.Debug("Section", key, "error:", result)
				result = { { kind = "empty", text = "Error building this section. See /rfbdebug." } }
			elseif type(result) ~= "table" or #result == 0 then
				result = { { kind = "empty", text = "Nothing to report." } }
			end
			for _, data in ipairs(result) do
				index = index + 1
				y = y + LayoutRow(GetRow(index), data, y, width)
			end
		end
	end
	if not anyShown then
		index = index + 1
		y = y + LayoutRow(GetRow(index), { kind = "empty", text = "All sections are disabled. Use /rfb config to enable them." }, y, width)
	end

	content:SetHeight(max(y + 8, 10))
end
