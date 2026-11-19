-- CraftPath: the planner window (/cpath)
local addonName, ns = ...

local format = string.format
local tinsert = table.insert
local tconcat = table.concat
local sort = table.sort

local frame
local selected -- index into the current ranking
local ranking = {}
local profName
local refreshQueued = false

local ROW_H = 22
local MAX_PROF_BUTTONS = 6

local function Color(rgb, text)
	return format("|cff%02x%02x%02x%s|r", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255, text)
end

local function ProfNames()
	local names = {}
	for name in pairs(ns.Char().profs) do
		names[#names + 1] = name
	end
	sort(names)
	return names
end

local function Build()
	frame = CreateFrame("Frame", "CraftPathWindow", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(480, 540)
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
	frame.TitleText:SetText("CraftPath")
	tinsert(UISpecialFrames, "CraftPathWindow")

	-- profession buttons
	frame.profButtons = {}
	for i = 1, MAX_PROF_BUTTONS do
		local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		btn:SetSize(100, 22)
		btn:SetPoint("TOPLEFT", 12 + ((i - 1) % 4) * 104, -30 - math.floor((i - 1) / 4) * 24)
		btn:SetScript("OnClick", function(self)
			profName = self.prof
			selected = nil
			ns.UpdateWindow()
		end)
		btn:Hide()
		frame.profButtons[i] = btn
	end

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", 14, -84)
	frame.status:SetWidth(450)
	frame.status:SetJustifyH("LEFT")

	-- options: bags free, number of crafts
	local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", 10, -100)
	check:SetSize(24, 24)
	check.text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	check.text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	check.text:SetText("Items in my bags and bank cost nothing")
	check:SetScript("OnClick", function(self)
		ns.db.countBagsFree = self:GetChecked() and true or false
		ns.UpdateWindow()
	end)
	frame.check = check

	frame.craftsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.craftsLabel:SetPoint("TOPLEFT", 300, -106)
	frame.craftsLabel:SetText("Crafts to buy for:")
	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(40, 20)
	box:SetPoint("LEFT", frame.craftsLabel, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	box:SetScript("OnEnterPressed", function(self)
		local n = tonumber(self:GetText())
		if n and n > 0 then
			ns.db.crafts = n
		end
		self:ClearFocus()
		ns.UpdateWindow()
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	frame.craftsBox = box

	-- ranking rows
	frame.rows = {}
	for i = 1, ns.TOP_COUNT do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(452, ROW_H)
		row:SetPoint("TOPLEFT", 12, -132 - (i - 1) * ROW_H)
		row.hl = row:CreateTexture(nil, "BACKGROUND")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(1, 1, 1, 0.12)
		row.hl:Hide()
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 4, 0)
		row.name:SetWidth(250)
		row.name:SetJustifyH("LEFT")
		row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.cost:SetPoint("RIGHT", -4, 0)
		row.cost:SetWidth(190)
		row.cost:SetJustifyH("RIGHT")
		row:SetScript("OnClick", function()
			selected = i
			ns.UpdateWindow()
		end)
		row:Hide()
		frame.rows[i] = row
	end

	frame.list = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.list:SetPoint("TOPLEFT", 14, -132 - ns.TOP_COUNT * ROW_H - 12)
	frame.list:SetWidth(450)
	frame.list:SetJustifyH("LEFT")
	frame.list:SetJustifyV("TOP")
	frame.list:SetSpacing(2)

	frame:Hide()
end

local function ShoppingText(entry)
	if not entry then
		return "Pick a recipe above to see what to buy."
	end
	local crafts = ns.db.crafts
	local rows, total = ns.ShoppingList(entry, crafts)
	local lines = { format("|cffffd100Shopping list: %s x%d|r", entry.recipe.name, crafts) }
	for _, r in ipairs(rows) do
		if r.buy > 0 then
			lines[#lines + 1] = format("Buy %d  %s  (need %d, have %d)  %s", r.buy, r.name, r.need, r.have,
				r.cost and ns.Money(r.cost) or "|cffff8080no price|r")
		else
			lines[#lines + 1] = format("|cff80ff80Have enough:|r %s (%d)", r.name, r.need)
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Total to buy: " .. ns.Money(total)
	if entry.unpriced > 0 then
		lines[#lines + 1] = "|cffff8080Some reagents have no price, so costs are too low. Set one with /cpath price [item] 2g.|r"
	end
	return tconcat(lines, "\n")
end

function ns.UpdateWindow()
	if not frame or not frame:IsShown() then
		return
	end
	local names = ProfNames()
	for i, btn in ipairs(frame.profButtons) do
		local name = names[i]
		btn.prof = name
		btn:SetShown(name ~= nil)
		if name then
			btn:SetText(name)
			btn:SetEnabled(name ~= profName)
		end
	end
	frame.check:SetChecked(ns.db.countBagsFree)
	frame.craftsBox:SetText(tostring(ns.db.crafts))

	local prof = profName and ns.Char().profs[profName]
	if not prof then
		profName = ns.currentProf or names[1]
		prof = profName and ns.Char().profs[profName]
	end
	if not prof then
		ranking = {}
		frame.status:SetText("No profession scanned yet. Open a profession window (like Engineering), then come back.")
		for _, row in ipairs(frame.rows) do
			row:Hide()
		end
		frame.list:SetText("")
		return
	end

	local ago = time() - (prof.scanned or 0)
	frame.status:SetText(format("%s: skill %d/%d. Scanned %s ago. Colors are as of that scan; reopen the profession window to refresh.",
		profName, prof.skill or 0, prof.max or 0, ns.AgoText(ago)))
	ranking = ns.Rank(prof)
	if selected and not ranking[selected] then
		selected = nil
	end
	for i, row in ipairs(frame.rows) do
		local e = ranking[i]
		if e then
			local d = e.recipe.diff
			local rgb = ns.DIFF_COLORS[d] or { 1, 1, 1 }
			row.name:SetText(Color(rgb, e.recipe.name) .. (e.craftableNow and " |cff80ff80[have mats]|r" or ""))
			row.cost:SetText(format("%s per skill-up%s", ns.Money(e.perSkill), e.unpriced > 0 and " *" or ""))
			row.hl:SetShown(selected == i)
			row:Show()
		else
			row:Hide()
		end
	end
	if #ranking == 0 then
		frame.list:SetText("No recipes that can still give a skill-up (all grey, or none learned).")
	else
		frame.list:SetText(ShoppingText(ranking[selected or 1]))
		if not selected then
			-- the first row is the default pick
			frame.rows[1].hl:Show()
		end
	end
end

function ns.AgoText(sec)
	if sec < 90 then
		return sec .. "s"
	elseif sec < 5400 then
		return math.floor(sec / 60) .. "m"
	end
	return math.floor(sec / 3600) .. "h"
end

function ns.ToggleWindow()
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		ns.UpdateWindow()
	end
end

-- Bag changes change what you still need to buy; refresh once things settle.
ns.On("BAG_UPDATE_DELAYED", function()
	if refreshQueued or not frame or not frame:IsShown() then
		return
	end
	refreshQueued = true
	C_Timer.After(0.3, function()
		refreshQueued = false
		ns.UpdateWindow()
	end)
end)
