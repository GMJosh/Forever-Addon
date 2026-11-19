-- StreamBingo: streamer overlay board
-- A movable 5-column grid of the active squares. Fired squares light up green with
-- their session count. Plain, non-secure frames only.
local addonName, ns = ...

local Debug = ns.Debug
local Board = ns.SB:NewModule("Board")
ns.Board = Board

local ceil = math.ceil
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local max = math.max
local date = date
local GameTooltip = GameTooltip

local COLUMNS = 5
local CELL_W, CELL_H = 108, 46
local GAP = 4
local PAD = 10
local HEADER_H = 26
local FOOTER_H = 34

local COLOR_IDLE = { 0.08, 0.08, 0.10, 0.92 }
local COLOR_FIRED = { 0.10, 0.55, 0.20, 0.95 }
local COLOR_DISABLED = { 0.20, 0.06, 0.06, 0.75 }

local frame
local cells = {}

local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	ns.db.board.point = { point, relPoint, floor(x + 0.5), floor(y + 0.5) }
end

local function RestorePosition()
	local p = ns.db.board.point or {}
	frame:ClearAllPoints()
	frame:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
end

local function Cell_OnEnter(self)
	local sq = self.square
	if not sq then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(sq.label, 1, 1, 1)
	GameTooltip:AddLine(sq.desc, nil, nil, nil, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Square", sq.id .. " (" .. sq.key .. ")", 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Fired this session", ns.GetCount(sq.id), 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Extra byte", sq.extra, 0.7, 0.7, 0.7, 1, 1, 1)
	if not ns.IsDetectorEnabled(sq.key) then
		GameTooltip:AddLine("Detector disabled in settings", 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end

local function Cell_OnLeave()
	GameTooltip:Hide()
end

local function CreateCell(parent)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetSize(CELL_W, CELL_H)
	cell:EnableMouse(true)
	cell:SetMouseClickEnabled(false)

	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()

	cell.border = cell:CreateTexture(nil, "BORDER")
	cell.border:SetPoint("TOPLEFT", -1, 1)
	cell.border:SetPoint("BOTTOMRIGHT", 1, -1)
	cell.border:SetColorTexture(0.35, 0.35, 0.40, 1)
	cell.bg:SetDrawLayer("ARTWORK")

	cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cell.label:SetPoint("TOPLEFT", 4, -4)
	cell.label:SetPoint("BOTTOMRIGHT", -4, 14)
	cell.label:SetJustifyH("CENTER")
	cell.label:SetJustifyV("MIDDLE")
	cell.label:SetWordWrap(true)

	cell.count = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cell.count:SetPoint("BOTTOM", 0, 3)

	cell.flash = cell:CreateTexture(nil, "ARTWORK", nil, 2)
	cell.flash:SetAllPoints()
	cell.flash:SetColorTexture(1, 1, 0.6, 1)
	cell.flash:SetAlpha(0)
	local ag = cell.flash:CreateAnimationGroup()
	local a1 = ag:CreateAnimation("Alpha")
	a1:SetFromAlpha(0)
	a1:SetToAlpha(0.7)
	a1:SetDuration(0.15)
	a1:SetOrder(1)
	local a2 = ag:CreateAnimation("Alpha")
	a2:SetFromAlpha(0.7)
	a2:SetToAlpha(0)
	a2:SetDuration(0.9)
	a2:SetOrder(2)
	cell.flashAnim = ag

	cell:SetScript("OnEnter", Cell_OnEnter)
	cell:SetScript("OnLeave", Cell_OnLeave)
	return cell
end

local function CreateBoard()
	frame = CreateFrame("Frame", "StreamBingoBoardFrame", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not ns.db.board.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.02, 0.02, 0.04, 0.85)
	frame:SetBackdropBorderColor(0.6, 0.4, 1, 1)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", PAD, -8)
	frame.title:SetText("|cff9966ffStream Bingo|r")

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("TOPRIGHT", -30, -10)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() Board:SetShown(false) end)

	frame.grid = CreateFrame("Frame", nil, frame)
	frame.grid:SetPoint("TOPLEFT", PAD, -HEADER_H)

	local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reset:SetSize(110, 22)
	reset:SetPoint("BOTTOMLEFT", PAD, 8)
	reset:SetText("Reset Session")
	reset:SetScript("OnClick", function()
		ns.ResetSession()
	end)

	local cfg = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	cfg:SetSize(80, 22)
	cfg:SetPoint("LEFT", reset, "RIGHT", 6, 0)
	cfg:SetText("Settings")
	cfg:SetScript("OnClick", function() ns.OpenConfig() end)

	frame.recent = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.recent:SetPoint("LEFT", cfg, "RIGHT", 10, 0)
	frame.recent:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.recent:SetJustifyH("RIGHT")
	frame.recent:SetWordWrap(false)

	RestorePosition()
	frame:SetScale(ns.db.board.scale or 1)
	frame:Hide()
end

local function VisibleSquares()
	local list = {}
	local showDisabled = ns.db.board.showDisabled
	for _, sq in ipairs(ns.SQUARES) do
		if showDisabled or ns.IsDetectorEnabled(sq.key) then
			list[#list + 1] = sq
		end
	end
	return list
end

-- Rebuilds the grid. If flashID is given, that square flashes.
function Board:Refresh(flashID)
	if not frame then return end
	local list = VisibleSquares()
	local rows = max(1, ceil(#list / COLUMNS))
	local gridW = COLUMNS * CELL_W + (COLUMNS - 1) * GAP
	local gridH = rows * CELL_H + (rows - 1) * GAP
	frame.grid:SetSize(gridW, gridH)
	frame:SetSize(gridW + PAD * 2, gridH + HEADER_H + FOOTER_H + 4)

	for i, sq in ipairs(list) do
		local cell = cells[i]
		if not cell then
			cell = CreateCell(frame.grid)
			cells[i] = cell
		end
		local col = (i - 1) % COLUMNS
		local row = floor((i - 1) / COLUMNS)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", col * (CELL_W + GAP), -row * (CELL_H + GAP))
		cell.square = sq

		local n = ns.GetCount(sq.id)
		local enabled = ns.IsDetectorEnabled(sq.key)
		local c = (not enabled and COLOR_DISABLED) or (n > 0 and COLOR_FIRED) or COLOR_IDLE
		cell.bg:SetColorTexture(c[1], c[2], c[3], c[4])
		cell.label:SetText(sq.label)
		if n > 0 then
			cell.count:SetText("|cffffff00x" .. n .. "|r")
		else
			cell.count:SetText("|cff777777#" .. sq.id .. "|r")
		end
		cell:Show()
		if flashID and flashID == sq.id and frame:IsShown() then
			cell.flashAnim:Stop()
			cell.flashAnim:Play()
		end
	end
	for i = #list + 1, #cells do
		cells[i]:Hide()
		cells[i].square = nil
	end

	local session = ns.db.session
	local fired = 0
	for _ in pairs(session.counts) do fired = fired + 1 end
	frame.status:SetText(fired .. "/" .. #ns.SQUARES .. " squares, " .. (session.total or 0) .. " events")

	local last = session.recent[1]
	if last and ns.SQUARES_BY_ID[last.id] then
		frame.recent:SetText("Last: " .. ns.SQUARES_BY_ID[last.id].label .. " @ " .. date("%H:%M:%S", last.t))
	else
		frame.recent:SetText("Session since " .. date("%H:%M", session.startedAt or 0))
	end
end

function Board:SetShown(show)
	ns.db.board.shown = show and true or false
	if show and not frame then
		CreateBoard()
	end
	if frame then
		if show then
			self:Refresh()
			frame:Show()
		else
			frame:Hide()
		end
	end
end

function Board:Toggle()
	self:SetShown(not ns.db.board.shown)
end

function Board:ApplySettings()
	if not frame then return end
	frame:SetScale(ns.db.board.scale or 1)
	self:Refresh()
end

function Board:ResetPosition()
	ns.db.board.point = { "CENTER", "CENTER", 0, 0 }
	if frame then RestorePosition() end
end

function Board:OnEnable()
	if ns.db.board.shown then
		self:SetShown(true)
	end
	Debug:Log("Board enabled, shown=" .. tostring(ns.db.board.shown))
end
