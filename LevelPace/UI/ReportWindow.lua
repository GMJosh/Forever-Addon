-- LevelPace: report window (/lp): time buckets, top time sinks, tips, best zones, level history
local addonName, ns = ...

local format = string.format
local sort = table.sort
local tinsert = table.insert
local tconcat = table.concat

local M = {}
ns.AddModule(M)

local frame
local mode = "level" -- "level" | "session" | "history"
local ROW_H = 20
local BAR_W = 170

local function Header(text)
	return "|cffffd100" .. text .. "|r"
end

local function BuildRows(parent)
	local rows = {}
	for i, bucket in ipairs(ns.BUCKETS) do
		local row = {}
		local y = -62 - (i - 1) * ROW_H
		row.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("TOPLEFT", 14, y)
		row.label:SetWidth(120)
		row.label:SetJustifyH("LEFT")
		row.label:SetText(bucket.label)
		row.back = parent:CreateTexture(nil, "BORDER")
		row.back:SetPoint("TOPLEFT", 138, y - 2)
		row.back:SetSize(BAR_W, 12)
		row.back:SetColorTexture(0.15, 0.15, 0.15, 0.8)
		row.bar = parent:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("TOPLEFT", row.back, "TOPLEFT")
		row.bar:SetHeight(12)
		row.bar:SetColorTexture(bucket.color[1], bucket.color[2], bucket.color[3], 1)
		row.value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.value:SetPoint("LEFT", row.back, "RIGHT", 8, 0)
		row.value:SetJustifyH("LEFT")
		rows[i] = row
	end
	return rows
end

local function SetMode(newMode)
	mode = newMode
	for key, btn in pairs(frame.tabs) do
		btn:SetEnabled(key ~= mode)
	end
	ns.UpdateReport()
end

local function Build()
	frame = CreateFrame("Frame", "LevelPaceReport", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(430, 580)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local r = ns.db.report
		r.point, r.relPoint, r.x, r.y = point, relPoint, x, y
	end)
	local r = ns.db.report
	frame:SetPoint(r.point, UIParent, r.relPoint, r.x, r.y)
	frame.TitleText:SetText("LevelPace")

	frame.tabs = {}
	local labels = { { "level", "This level" }, { "session", "Session" }, { "history", "History" }, { "advisor", "Advisor" } }
	for i, t in ipairs(labels) do
		local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		btn:SetSize(100, 22)
		btn:SetPoint("TOPLEFT", 12 + (i - 1) * 104, -30)
		btn:SetText(t[2])
		btn:SetScript("OnClick", function()
			SetMode(t[1])
		end)
		frame.tabs[t[1]] = btn
	end

	frame.rows = BuildRows(frame)
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.text:SetPoint("TOPLEFT", 14, -62 - #ns.BUCKETS * ROW_H - 10)
	frame.text:SetWidth(400)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetJustifyV("TOP")
	frame.text:SetSpacing(3)

	-- credit for the quest and dungeon data (ForeverDB asks for a visible link)
	frame.credit = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.credit:SetPoint("BOTTOMRIGHT", -14, 14)
	frame.credit:SetText("Advisor data: ForeverDB.net")
	local link = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	link:SetSize(150, 18)
	link:SetPoint("RIGHT", frame.credit, "LEFT", -6, 0)
	link:SetAutoFocus(false)
	link:SetText("https://foreverdb.net")
	link:SetCursorPosition(0)
	link:SetScript("OnTextChanged", function(self, user)
		if user then
			self:SetText("https://foreverdb.net")
		end
	end)
	link:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	link:SetScript("OnEscapePressed", link.ClearFocus)
	frame.creditLink = link

	-- clicks on waypoint links in the Advisor tab (guarded: not every client lets a plain frame take links)
	if frame.SetHyperlinksEnabled then
		frame:SetHyperlinksEnabled(true)
		frame:SetScript("OnHyperlinkClick", function(_, linkText)
			ns.HandleLink(linkText)
		end)
	end

	frame:Hide()
	tinsert(UISpecialFrames, "LevelPaceReport")
end

local function WaypointLink(map, x, y)
	if map and x and y then
		return format(" |cff71d5ff|Hlevelpace:way:%d:%.1f:%.1f|h[waypoint]|h|r", map, x, y)
	end
	return ""
end

local function AdvisorText()
	local level = ns.level or UnitLevel("player")
	local cap = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
	if not ns.QuestData then
		return "No quest data found. Reinstall the addon."
	end
	local lines = { Header(format("Where to level at level %d", level)) }
	if level >= cap then
		lines[#lines + 1] = "You are at the level cap. Dungeons and raids are the next step."
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = Header("Best zones for quests (most left to do)")
	local zones = ns.AdvisorZones(level)
	if #zones == 0 then
		lines[#lines + 1] = "No quests left in range. Try a dungeon."
	end
	for i = 1, math.min(5, #zones) do
		local z = zones[i]
		local mine = ns.char.zones and ns.char.zones[z.name]
		local rate = mine and mine.secs and mine.secs >= ns.ZONE_MIN_SECONDS and mine.xp > 0 and (mine.xp / mine.secs * 3600) or nil
		lines[#lines + 1] = format("%d. %s: %d quests (levels %d-%d)%s", i, z.name, z.count, z.lo, z.hi,
			rate and format("  - your pace here: %s XP/hr", ns.Comma(math.floor(rate))) or "")
	end

	local here = ns.AdvisorCurrentZone()
	lines[#lines + 1] = ""
	if here then
		lines[#lines + 1] = Header("Quests to pick up in " .. ns.QuestData.zones[here])
		local quests = ns.AdvisorQuests(here, level, 8)
		if #quests == 0 then
			lines[#lines + 1] = "None left at your level here. Check the zones above."
		end
		for _, q in ipairs(quests) do
			local from = q.sn and format("  from %s%s", q.sn, WaypointLink(q.sm, q.sx, q.sy)) or ""
			lines[#lines + 1] = format("[%d] %s%s", q.l, q.n, from)
		end
	else
		lines[#lines + 1] = Header("Quests to pick up here")
		lines[#lines + 1] = "Walk into a zone and I will list its quests."
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = Header("Dungeons and raids for your level")
	local dungeons = ns.AdvisorDungeons(level)
	if #dungeons == 0 then
		lines[#lines + 1] = "None in range."
	end
	for _, d in ipairs(dungeons) do
		local tag = d.new and "new in Forever" or (d.st == "forever" and "Forever" or "Classic")
		local bosses = #d.bosses > 0 and format(", %d bosses", #d.bosses) or ""
		lines[#lines + 1] = format("%s (%d-%d, %d-player %s, %s%s)", d.n, d.lo, d.hi, d.p, d.kind, tag, bosses)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cff9d9d9dQuest levels shown in [brackets]. Quests count when their level is within a few levels of yours.|r"
	return tconcat(lines, "\n")
end

local function SourceRecord()
	if mode == "session" then
		return ns.session, ns.sessionZones
	end
	return ns.rec, ns.char.zones
end

local function HistoryText()
	local levels = {}
	for level in pairs(ns.char.levels) do
		levels[#levels + 1] = level
	end
	sort(levels)
	local lines = { Header("Time per level (" .. (ns.char.name or "?") .. ")") }
	local sum = 0
	for _, level in ipairs(levels) do
		local rec = ns.char.levels[level]
		local total = ns.Total(rec.b)
		sum = sum + total
		local tag = (level == ns.level and not rec.done) and "  (current)" or ""
		lines[#lines + 1] = format("Level %d: %s   %d kills, %d deaths%s", level, ns.Clock(total), rec.kills or 0, rec.deaths or 0, tag)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Total tracked: " .. ns.Clock(sum)
	return tconcat(lines, "\n")
end

local function DetailText(rec, zones)
	local lines = {}
	local st = ns.XPStats()
	if mode == "level" and st.pct then
		lines[#lines + 1] = Header(format("Level %d: %.1f%% (%s / %s XP)", st.level, st.pct, ns.Comma(st.xp), ns.Comma(st.max)))
		lines[#lines + 1] = format("To level: %s    XP/hr: %s    Kills left: %s    Rested: %s",
			st.eta and ns.Clock(st.eta) or "--", st.rate and ns.Comma(st.rate) or "--",
			st.killsLeft and ("~" .. ns.Comma(st.killsLeft)) or "--", ns.Comma(st.rested or 0))
		lines[#lines + 1] = ""
	end
	local xp = rec.xp
	lines[#lines + 1] = Header("XP sources")
	lines[#lines + 1] = format("Kills %s   Quests %s   Other %s   (%d kills, %d deaths)",
		ns.Comma(xp.kill or 0), ns.Comma(xp.quest or 0), ns.Comma(xp.other or 0), rec.kills or 0, rec.deaths or 0)
	lines[#lines + 1] = ""
	lines[#lines + 1] = Header("Biggest time sinks")
	local sinks = ns.TopSinks(rec, 3)
	if #sinks == 0 then
		lines[#lines + 1] = "Nothing yet."
	end
	for i, s in ipairs(sinks) do
		lines[#lines + 1] = format("%d. %s: %s", i, s.label, ns.Clock(s.secs))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = Header("Tips")
	for _, tip in ipairs(ns.Tips(rec)) do
		lines[#lines + 1] = "- " .. tip
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = Header("Best zones (XP per hour)")
	local ranking = ns.ZoneRanking(zones)
	if #ranking == 0 then
		lines[#lines + 1] = format("Stay in a zone for %d minutes to rank it.", ns.ZONE_MIN_SECONDS / 60)
	end
	for i = 1, math.min(4, #ranking) do
		local z = ranking[i]
		lines[#lines + 1] = format("%d. %s: %s XP/hr (%s)", i, z.name, ns.Comma(z.rate), ns.Clock(z.secs))
	end
	return tconcat(lines, "\n")
end

function ns.UpdateReport()
	if not frame or not frame:IsShown() or not ns.rec then
		return
	end
	local textOnly = mode == "history" or mode == "advisor"
	for _, row in ipairs(frame.rows) do
		row.label:SetShown(not textOnly)
		row.back:SetShown(not textOnly)
		row.bar:SetShown(not textOnly)
		row.value:SetShown(not textOnly)
	end
	frame.credit:SetShown(mode == "advisor")
	frame.creditLink:SetShown(mode == "advisor")
	if textOnly then
		frame.text:ClearAllPoints()
		frame.text:SetPoint("TOPLEFT", 14, -62)
		frame.text:SetText(mode == "advisor" and AdvisorText() or HistoryText())
		return
	end
	frame.text:ClearAllPoints()
	frame.text:SetPoint("TOPLEFT", 14, -62 - #ns.BUCKETS * ROW_H - 10)
	local rec, zones = SourceRecord()
	local total = ns.Total(rec.b)
	for i, bucket in ipairs(ns.BUCKETS) do
		local secs = rec.b[bucket.key] or 0
		local pct = total > 0 and secs / total or 0
		local row = frame.rows[i]
		row.bar:SetWidth(math.max(1, BAR_W * pct))
		row.value:SetText(format("%s  %d%%", ns.Clock(secs), pct * 100 + 0.5))
	end
	frame.text:SetText(DetailText(rec, zones))
end

function ns.ToggleReport()
	if not frame then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		SetMode(mode)
	end
end

function M.Start()
	Build()
	frame.tabs[mode]:SetEnabled(false)
end
