-- StreamMoments: the window (/sm): which moments are on, banner settings, and the log of what happened
local addonName, ns = ...

local format = string.format
local date = date
local tconcat = table.concat
local tinsert = table.insert

local frame

local function StripCodes(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

local function Summary()
	local s = ns.session
	return format("This session: %d level-ups, %d drops, %d boss kills, %d deaths, %d rares, %d zones.",
		s.level, s.loot, s.boss, s.death, s.rare, s.zone)
end

local function LogText()
	local lines = {}
	local log = ns.db.log
	for i = #log, 1, -1 do
		local m = log[i]
		local t = ns.TYPE_BY_KEY[m.kind]
		lines[#lines + 1] = format("%s  [%s]  %s  -  %s", date("%H:%M", m.t), t and t.label or m.kind, StripCodes(m.title), StripCodes(m.text))
	end
	if #lines == 0 then
		return "Nothing yet. Play, or type /sm test to see a banner."
	end
	return tconcat(lines, "\n")
end

local function Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	for _, t in ipairs(ns.TYPES) do
		frame.checks[t.key]:SetChecked(ns.db.enabled[t.key])
	end
	frame.sound:SetChecked(ns.db.sound)
	frame.quality:SetText("Drops: " .. (ns.QUALITY_NAMES[ns.db.minQuality] or "Rare") .. " and up")
	frame.lock:SetText(ns.db.locked and "Unlock banner" or "Lock banner")
	frame.bg:SetText("Background: " .. ns.db.background)
	frame.summary:SetText(Summary())
	frame.edit:SetText(LogText())
end

function ns.UpdateLog()
	Refresh()
end

local function Check(parent, x, y, text, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.text:SetText(text)
	cb:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false)
	end)
	return cb
end

local function Button(parent, x, y, w, text, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "StreamMomentsWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(540, 520)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local w = ns.db.window
		w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
	end)
	local w = ns.db.window
	frame:SetPoint(w.point, UIParent, w.relPoint, w.x, w.y)
	frame.TitleText:SetText("StreamMoments")
	tinsert(UISpecialFrames, "StreamMomentsWindow")

	-- which moments are on (two columns)
	frame.checks = {}
	for i, t in ipairs(ns.TYPES) do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		frame.checks[t.key] = Check(frame, 12 + col * 260, -32 - row * 24, t.label, function(on)
			ns.db.enabled[t.key] = on
		end)
	end
	frame.sound = Check(frame, 272, -32 - 3 * 24, "Play sounds", function(on)
		ns.db.sound = on
	end)

	-- banner controls
	frame.quality = Button(frame, 12, -136, 170, "", function()
		local q = ns.db.minQuality + 1
		if q > 5 then
			q = 3
		end
		ns.db.minQuality = q
		Refresh()
	end)
	frame.lock = Button(frame, 188, -136, 110, "", function()
		ns.SetLocked(not ns.db.locked)
		Refresh()
	end)
	frame.bg = Button(frame, 304, -136, 150, "", function()
		local order = { "dark", "clear", "green", "magenta" }
		local idx = 1
		for i, k in ipairs(order) do
			if k == ns.db.background then
				idx = i
			end
		end
		ns.db.background = order[idx % #order + 1]
		ns.ApplyBanner()
		Refresh()
	end)
	Button(frame, 12, -164, 110, "Test banners", function()
		ns.TestMoment()
	end)
	Button(frame, 128, -164, 110, "Clear log", function()
		wipe(ns.db.log)
		Refresh()
	end)

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.summary:SetPoint("TOPLEFT", 14, -196)
	frame.summary:SetWidth(510)
	frame.summary:SetJustifyH("LEFT")

	-- the log (copyable text, newest first)
	local scroll = CreateFrame("ScrollFrame", "StreamMomentsLogScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -216)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(480)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	scroll:SetScrollChild(edit)
	frame.edit = edit

	frame:SetScript("OnShow", Refresh)
	frame:Hide()
end

function ns.ToggleWindow()
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end
