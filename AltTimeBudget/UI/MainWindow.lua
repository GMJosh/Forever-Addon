-- AltTimeBudget: main window (AceGUI), toggled with /atb
local addonName, ns = ...

local AceGUI = LibStub("AceGUI-3.0")
local Debug = ns.Debug

local format = string.format
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tconcat = table.concat
local sort = table.sort
local tinsert = table.insert
local type = type
local GetServerTime = GetServerTime
local date = date
local pcall = pcall

local MainWindow = {}
ns.MainWindow = MainWindow

local GLOBAL_FRAME_NAME = "AltTimeBudgetMainFrame" -- only so Escape (UISpecialFrames) closes it

local window, tabGroup, hoursBox, summaryLabel
local refreshTimer
local scrollStatus = {}
local deleteArmedGuid

local GREEN = "|cff40ff40"
local GREY = "|cff9d9d9d"
local GOLD = "|cffffd100"
local RED = "|cffff6060"

local TABS = {
	{ value = "plan", text = "Plan" },
	{ value = "checkoff", text = "Checkoff" },
	{ value = "alts", text = "Alts" },
	{ value = "chores", text = "Chores" },
	{ value = "lastweek", text = "Last week" },
}

local function P()
	return ns.db.profile
end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function AddLabel(container, text, relWidth, font)
	local l = AceGUI:Create("Label")
	if relWidth then
		l:SetRelativeWidth(relWidth)
	else
		l:SetFullWidth(true)
	end
	if font then l:SetFontObject(font) end
	l:SetText(text or "")
	container:AddChild(l)
	return l
end

local function AddHeading(container, text)
	local h = AceGUI:Create("Heading")
	h:SetFullWidth(true)
	h:SetText(text)
	container:AddChild(h)
	return h
end

local function AddRow(container)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	container:AddChild(row)
	return row
end

local function AddButton(container, text, relWidth, onClick)
	local b = AceGUI:Create("Button")
	b:SetText(text)
	b:SetRelativeWidth(relWidth)
	b:SetCallback("OnClick", onClick)
	container:AddChild(b)
	return b
end

local function NewScroll(container, key)
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scrollStatus[key] = scrollStatus[key] or {}
	scroll:SetStatusTable(scrollStatus[key])
	container:AddChild(scroll)
	return scroll
end

local function SourceTag(source)
	if source == "learned" then return GREEN .. "learned|r" end
	if source == "override" then return GOLD .. "override|r" end
	return GREY .. "default|r"
end

-- "Alchemy knowledge drops (1/2)" - per-alt name plus partial progress for all / count chores.
local function ItemName(item)
	local name = item.name or item.chore.name
	if item.progress then
		name = name .. " " .. GOLD .. "(" .. item.progress .. ")|r"
	end
	return name
end

local function ItemLine(item)
	return format("%s  %s %s · %d pts · %s/min", ItemName(item), ns.FormatMinutes(item.minutes),
		SourceTag(item.source), floor(item.score + 0.5), ns.FormatRate(item.rate))
end

-- "Alchemy / Mining", "professions not scanned" etc.
local function ProfessionsText(char)
	local profs = char and char.professions
	if type(profs) ~= "table" or not profs.scanned then
		return "professions not scanned"
	end
	local names = {}
	for slot = 1, 2 do
		local p = profs[slot]
		if type(p) == "table" and p.name then names[#names + 1] = p.name end
	end
	if #names == 0 then return "no professions" end
	return tconcat(names, " / ")
end

-- "Name [Role]" for plan / checkoff lists.
local function NameWithRole(char)
	return ns.ClassColoredName(char) .. " " .. ns.RoleTag(ns.Roster:Role(char))
end

local function AgoText(ts)
	if not ts then return "never" end
	local secs = GetServerTime() - ts
	if secs < 3600 then return "just now" end
	if secs < 86400 then return format("%dh ago", floor(secs / 3600)) end
	return format("%dd ago", floor(secs / 86400))
end

---------------------------------------------------------------------------
-- Summary bar
---------------------------------------------------------------------------
local function UpdateSummary(plan)
	if not summaryLabel then return end
	plan = plan or ns.Planner:Compute()
	summaryLabel:SetText(format("Planned %s%s|r of %s available  (budget %s, spent %s, %s overhead per alt)",
		GOLD, ns.FormatMinutes(plan.plannedMinutes), ns.FormatMinutes(plan.availableMinutes),
		ns.FormatMinutes(plan.budgetMinutes), ns.FormatMinutes(plan.spentMinutes), ns.FormatMinutes(plan.overhead)))
	if hoursBox and not hoursBox.editbox:HasFocus() then
		hoursBox:SetText(tostring(P().hoursBudget))
	end
end

---------------------------------------------------------------------------
-- Plan tab
---------------------------------------------------------------------------
local function RenderCurrentCharacter(scroll, plan)
	local char = ns.Roster:Current()
	AddHeading(scroll, "Current character" .. (char and (": " .. NameWithRole(char)) or ""))
	if not char then
		AddLabel(scroll, "Character not registered yet.")
		return
	end
	if ns.Roster:Role(char) == "bank" then
		AddLabel(scroll, "Bank character - no chores planned. Change its role in the Alts tab if that's wrong.")
		return
	end
	local group = plan.groupsByGuid[char.guid]
	if not group then
		local reason = plan.skipReasons[char.guid]
		AddLabel(scroll, "Not in this week's plan" .. (reason and (": " .. reason) or "") .. ".")
		return
	end
	AddLabel(scroll, format("In the plan: %d chore(s), about %s (incl. %s overhead). Check off as you go - press Start to time a chore so its estimate learns your pace.",
		#group.items, ns.FormatMinutes(group.minutes + group.overhead), ns.FormatMinutes(group.overhead)))
	for _, item in ipairs(group.items) do
		local chore = item.chore
		local row = AddRow(scroll)
		local cb = AceGUI:Create("CheckBox")
		cb:SetLabel(ItemName(item))
		cb:SetRelativeWidth(0.45)
		cb:SetValue(false)
		cb:SetCallback("OnValueChanged", function(_, _, value)
			if value then
				ns.Roster:SetManual(char, chore, true)
			end
		end)
		row:AddChild(cb)
		AddLabel(row, format("%s %s · %s/min", ns.FormatMinutes(item.minutes), SourceTag(item.source), ns.FormatRate(item.rate)), 0.33)
		local elapsed = ns.TimeLearner:ElapsedMinutes(chore)
		if elapsed then
			AddButton(row, format("Stop timer (%s)", ns.FormatMinutes(elapsed)), 0.22, function()
				ns.TimeLearner:StopTimer(chore)
			end)
		else
			AddButton(row, "Start", 0.22, function()
				ns.TimeLearner:StartTimer(chore)
			end)
		end
	end
end

local function RenderPlan(container)
	local plan = ns.Planner:Compute()
	UpdateSummary(plan)
	local scroll = NewScroll(container, "plan")

	RenderCurrentCharacter(scroll, plan)

	AddHeading(scroll, "This week's plan")
	if #plan.groups == 0 then
		AddLabel(scroll, plan.availableMinutes <= 0 and "No time left in the budget. Raise the hours above." or
			"Nothing to plan. Log in on your alts once so they register, and check the Chores tab.")
	end
	for i, group in ipairs(plan.groups) do
		local lines = {}
		lines[1] = format("%s%d.|r %s  %s(lvl %d)|r  %s%s|r incl. %s overhead · %d pts", GOLD, i,
			NameWithRole(group.char), GREY, group.char.level or 0, GOLD,
			ns.FormatMinutes(group.minutes + group.overhead), ns.FormatMinutes(group.overhead), floor(group.score + 0.5))
		for _, item in ipairs(group.items) do
			lines[#lines + 1] = "      - " .. ItemLine(item)
		end
		AddLabel(scroll, tconcat(lines, "\n") .. "\n", nil, GameFontHighlight)
	end
	AddLabel(scroll, format("Total planned: %s%s|r of %s available. Already spent this week: %s.",
		GOLD, ns.FormatMinutes(plan.plannedMinutes), ns.FormatMinutes(plan.availableMinutes), ns.FormatMinutes(plan.spentMinutes)))

	AddHeading(scroll, "Skip these alts")
	local skipLines, otherLines = {}, {}
	for _, s in ipairs(plan.skipped) do
		local line = format("%s: %s", NameWithRole(s.char), s.reason)
		if s.kind == "skip" then
			skipLines[#skipLines + 1] = RED .. "x|r " .. line
		else
			otherLines[#otherLines + 1] = GREY .. "- " .. "|r" .. line
		end
	end
	if #skipLines == 0 then
		skipLines[1] = GREY .. "None. Every alt with chores left made it into the plan.|r"
	end
	AddLabel(scroll, tconcat(skipLines, "\n"), nil, GameFontHighlight)
	if #otherLines > 0 then
		AddLabel(scroll, "\n" .. GREY .. "Not in the plan for other reasons:|r\n" .. tconcat(otherLines, "\n"))
	end

	AddHeading(scroll, "Didn't fit / not worth it")
	if #plan.leftovers == 0 then
		AddLabel(scroll, GREY .. "Nothing left over.|r")
	else
		local lines = {}
		for i, item in ipairs(plan.leftovers) do
			if i > 40 then
				lines[#lines + 1] = format("... and %d more", #plan.leftovers - 40)
				break
			end
			lines[#lines + 1] = format("%s: %s", ns.ClassColoredName(item.char), ItemLine(item))
		end
		AddLabel(scroll, tconcat(lines, "\n"))
	end
end

---------------------------------------------------------------------------
-- Checkoff tab
---------------------------------------------------------------------------
local function RenderCheckoff(container)
	UpdateSummary()
	local scroll = NewScroll(container, "checkoff")
	local chars = ns.Roster:GetAll()
	if #chars == 0 then
		AddLabel(scroll, "No characters registered yet.")
		return
	end

	local list, order = {}, {}
	for _, char in ipairs(chars) do
		list[char.guid] = format("%s (%d) [%s]", ns.CharLabel(char), char.level or 0, ns.ROLE_LABELS[ns.Roster:Role(char)])
		order[#order + 1] = char.guid
	end
	local selected = P().window.checkoffChar
	if not selected or not list[selected] then
		selected = ns.Roster:CurrentGUID()
		if not list[selected] then selected = order[1] end
	end

	local dd = AceGUI:Create("Dropdown")
	dd:SetLabel("Character")
	dd:SetList(list, order)
	dd:SetValue(selected)
	dd:SetRelativeWidth(0.5)
	dd:SetCallback("OnValueChanged", function(_, _, value)
		P().window.checkoffChar = value
		MainWindow:RenderTab()
	end)
	scroll:AddChild(dd)

	AddLabel(scroll, GREY .. "Tick a chore when it's done. For auto-detected chores, clicking stores a manual override only when it disagrees with detection - click again to go back to detection. Account-wide chores are shared by every alt. Only chores allowed for the selected alt's role are listed.|r")

	local char = ns.Roster:GetChar(selected)
	if not char then return end
	local role = ns.Roster:Role(char)
	AddLabel(scroll, "Role: " .. ns.RoleTag(role) .. GREY .. "   Professions: " .. ProfessionsText(char)
		.. ((char.professions and char.professions.scanned) and "" or " (log in on this alt to scan them)") .. "|r")
	if role == "bank" then
		AddLabel(scroll, "Bank character - no chores. Change its role in the Alts tab to give it chores.")
		return
	end
	local lastCategory
	for _, chore in ipairs(ns.Chores:GetAll()) do
		if chore.enabled and ns.Roster:RoleAllows(char, chore) then
			if chore.category ~= lastCategory then
				AddHeading(scroll, chore.category)
				lastCategory = chore.category
			end
			local done, how = ns.Roster:IsDone(char, chore)
			local detected = ns.Roster:IsDetected(char, chore)
			local row = AddRow(scroll)
			local cb = AceGUI:Create("CheckBox")
			local progress = ns.Detection:ProgressText(char, chore)
			cb:SetLabel(ns.Chores:DisplayName(chore, char)
				.. (progress and (" " .. GOLD .. "(" .. progress .. ")|r") or "")
				.. (chore.scope == "account" and (GREY .. " (account)|r") or ""))
			cb:SetRelativeWidth(0.55)
			cb:SetValue(done)
			cb:SetCallback("OnValueChanged", function(_, _, value)
				value = value and true or false
				local newManual = value
				if value == ns.Roster:IsDetected(char, chore) or (not value and not chore.detect) then
					newManual = nil -- agrees with detection (or plain "not done"): follow detection
				end
				ns.Roster:SetManual(char, chore, newManual)
			end)
			row:AddChild(cb)
			local status = ns.Detection:Describe(chore, char)
			if chore.note then
				status = status .. " - " .. chore.note
			end
			if how == "manual" and chore.detect then
				status = status .. GOLD .. " (manual override: " .. (done and "done" or "not done") .. ")|r"
			elseif detected then
				status = status .. GREEN .. " (detected)|r"
			end
			if not ns.Roster:IsEligible(char, chore) then
				status = status .. RED .. format(" needs level %d|r", ns.Chores:MinLevel(chore))
			end
			AddLabel(row, GREY .. status .. "|r", 0.45)
		end
	end
end

---------------------------------------------------------------------------
-- Alts tab
---------------------------------------------------------------------------
local ROLE_LIST = {}
for _, role in ipairs(ns.ROLE_ORDER) do ROLE_LIST[role] = ns.ROLE_LABELS[role] end

local function RenderAlts(container)
	UpdateSummary()
	local scroll = NewScroll(container, "alts")
	AddLabel(scroll, GREY .. "Role decides which chores an alt gets: Main and Alt get everything, Profession only profession chores (weeklies, treatises, knowledge drops, patron orders), Bank gets nothing and is never planned. Any number of alts can be Main. Priority multiplies every chore's value for that alt (role defaults: Main 1.0, Alt and Profession per /atb config). Changing the role resets the priority to the new role's default only if you hadn't changed it. 0 or Exclude keeps the alt out of the plan. Alts register themselves when they log in with the addon enabled - new alts start as Alt (the very first character in a new database starts as Main, as a convenience).|r")
	local currentGUID = ns.Roster:CurrentGUID()
	for _, char in ipairs(ns.Roster:GetAll()) do
		local role = ns.Roster:Role(char)
		local isBank = role == "bank"
		local row = AddRow(scroll)
		local tags = { ns.RoleTag(role) }
		if char.guid == currentGUID then tags[#tags + 1] = GREEN .. "this character|r" end
		AddLabel(row, format("%s %s\n%slvl %d · seen %s\n%s|r", ns.ClassColoredName(char), tconcat(tags, " "),
			GREY, char.level or 0, AgoText(char.lastSeen), ProfessionsText(char)), 0.26)

		local dd = AceGUI:Create("Dropdown")
		dd:SetLabel("Role")
		dd:SetList(ROLE_LIST, ns.ROLE_ORDER)
		dd:SetValue(role)
		dd:SetRelativeWidth(0.17)
		dd:SetCallback("OnValueChanged", function(_, _, value)
			ns.Roster:SetRole(char.guid, value)
		end)
		row:AddChild(dd)

		local slider = AceGUI:Create("Slider")
		slider:SetLabel(isBank and "Priority (unused for bank)" or "Priority")
		slider:SetSliderValues(0, 2, 0.05)
		slider:SetValue(char.priority or 0)
		slider:SetRelativeWidth(0.24)
		slider:SetDisabled(isBank)
		slider:SetCallback("OnMouseUp", function(_, _, value)
			ns.Roster:SetPriority(char.guid, value)
		end)
		row:AddChild(slider)

		local ex = AceGUI:Create("CheckBox")
		ex:SetLabel("Exclude")
		ex:SetValue(char.excluded and true or false)
		ex:SetRelativeWidth(0.13)
		ex:SetCallback("OnValueChanged", function(_, _, value)
			ns.Roster:SetExcluded(char.guid, value)
		end)
		row:AddChild(ex)

		local delBtn = AddButton(row, deleteArmedGuid == char.guid and "Confirm" or "Delete", 0.15, function(widget)
			if deleteArmedGuid ~= char.guid then
				deleteArmedGuid = char.guid
				widget:SetText("Confirm")
				return
			end
			deleteArmedGuid = nil
			ns.Roster:Delete(char.guid)
		end)
		delBtn:SetDisabled(char.guid == currentGUID)
	end
end

---------------------------------------------------------------------------
-- Chores tab
---------------------------------------------------------------------------
local function RenderChores(container)
	UpdateSummary()
	local scroll = NewScroll(container, "chores")

	local addRow = AddRow(scroll)
	local nameBox = AceGUI:Create("EditBox")
	nameBox:SetLabel("New custom chore")
	nameBox:SetRelativeWidth(0.5)
	nameBox:DisableButton(true)
	addRow:AddChild(nameBox)
	local function AddFromBox()
		local id = ns.Chores:AddCustom(nameBox:GetText())
		if id then
			ns.Say("added custom chore. Set its minutes, value and quest IDs in /atb config.")
		end
	end
	nameBox:SetCallback("OnEnterPressed", AddFromBox)
	AddButton(addRow, "Add", 0.15, AddFromBox)
	AddButton(addRow, "Full editor", 0.3, function()
		ns.ATB:OpenConfig()
	end)

	AddLabel(scroll, GREY .. "Minutes: type a number to override the estimate, or clear it to go back to learned/default. Value: points per completion (blank = preset). Great Vault slots learn minutes per run/boss/delve, shared by all slots of a row. Edit which roles may do a chore in /atb config -> Chores.|r")

	local lastCategory
	for _, chore in ipairs(ns.Chores:GetAll()) do
		if chore.category ~= lastCategory then
			AddHeading(scroll, chore.category)
			lastCategory = chore.category
		end
		local row = AddRow(scroll)

		local cb = AceGUI:Create("CheckBox")
		cb:SetLabel(chore.name)
		cb:SetDescription(format("%s · %s · lvl %s · roles: %s", ns.Detection:Describe(chore),
			chore.scope == "account" and "account-wide" or "per character",
			chore.minLevel == "max" and ("max (" .. ns.MaxLevel() .. ")") or tostring(chore.minLevel),
			ns.Chores:RolesText(chore)))
		cb:SetValue(chore.enabled)
		cb:SetRelativeWidth(0.38)
		cb:SetCallback("OnValueChanged", function(_, _, value)
			ns.Chores:SetOverride(chore.id, "enabled", value and true or false)
		end)
		row:AddChild(cb)

		local minBox = AceGUI:Create("EditBox")
		minBox:SetLabel("Minutes")
		minBox:SetText(chore.minutesOverride and tostring(chore.minutesOverride) or "")
		minBox:SetRelativeWidth(0.11)
		minBox:SetCallback("OnEnterPressed", function(_, _, text)
			ns.Chores:SetOverride(chore.id, "minutes", ns.Chores:CleanNumber(text, 1, 1440))
		end)
		row:AddChild(minBox)

		local learned, rec = ns.Chores:LearnedMinutes(chore)
		local est = format("default %s", ns.FormatMinutes(ns.Chores:DefaultMinutes(chore)))
		if learned then
			est = est .. format("\n%slearned %s (%d)|r", GREEN, ns.FormatMinutes(learned), rec.n or 0)
		else
			est = est .. "\n" .. GREY .. "not learned yet|r"
		end
		AddLabel(row, est, 0.22)

		local valBox = AceGUI:Create("EditBox")
		valBox:SetLabel("Value")
		valBox:SetText(tostring(chore.value))
		valBox:SetRelativeWidth(0.11)
		valBox:SetCallback("OnEnterPressed", function(_, _, text)
			ns.Chores:SetOverride(chore.id, "value", ns.Chores:CleanNumber(text, 0, 100000))
		end)
		row:AddChild(valBox)

		local resetBtn = AddButton(row, "Reset time", 0.16, function()
			ns.TimeLearner:Reset(chore.learnKey)
		end)
		resetBtn:SetDisabled(learned == nil)
	end
end

---------------------------------------------------------------------------
-- Last week tab
---------------------------------------------------------------------------
local function RenderLastWeek(container)
	UpdateSummary()
	local scroll = NewScroll(container, "lastweek")
	local lw = ns.db.global.lastWeek
	if not lw then
		AddLabel(scroll, "No previous week recorded yet. After the next weekly reset, this shows last week's plan versus what you actually did.")
		return
	end
	local lines = {}
	if lw.key then
		lines[#lines + 1] = format("Week ending %s", date("%a %b %d", lw.key))
	end
	lines[#lines + 1] = format("Budget: %s", ns.FormatMinutes(lw.budgetMinutes))
	if lw.planned then
		lines[#lines + 1] = format("Planned: %d chore(s) on %d alt(s), %s, %d pts",
			lw.planned.plannedCount or 0, lw.planned.alts or 0, ns.FormatMinutes(lw.planned.plannedMinutes), floor((lw.planned.plannedScore or 0) + 0.5))
	else
		lines[#lines + 1] = GREY .. "Planned: no snapshot was taken that week.|r"
	end
	lines[#lines + 1] = format("Actual: %d chore(s), about %s, %d pts", lw.completedCount or 0,
		ns.FormatMinutes(lw.spentMinutes), floor((lw.valueEarned or 0) + 0.5))
	if lw.perAlt and #lw.perAlt > 0 then
		lines[#lines + 1] = ""
		for _, a in ipairs(lw.perAlt) do
			lines[#lines + 1] = format("  %s: %d chore(s), %s", ns.ClassColoredName(a), a.count, ns.FormatMinutes(a.minutes))
		end
	end
	AddLabel(scroll, tconcat(lines, "\n"), nil, GameFontHighlight)
end

local RENDERERS = {
	plan = RenderPlan,
	checkoff = RenderCheckoff,
	alts = RenderAlts,
	chores = RenderChores,
	lastweek = RenderLastWeek,
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function MainWindow:RenderTab()
	if not tabGroup then return end
	local tab = P().window.tab or "plan"
	if not RENDERERS[tab] then tab = "plan" end
	tabGroup:ReleaseChildren()
	local ok, err = pcall(RENDERERS[tab], tabGroup)
	if not ok then
		Debug:Log("Render error in tab", tab, err)
	end
end

function MainWindow:Open()
	if window then
		window:Show()
		self:RenderTab()
		return
	end
	window = AceGUI:Create("Frame")
	window:SetTitle("AltTimeBudget")
	window:SetStatusText("/atb help for commands")
	local status = P().window.status
	window:SetStatusTable(status)
	if not status.width then
		window:SetWidth(780)
		window:SetHeight(640)
	end
	window:SetLayout("Flow")
	window:SetCallback("OnClose", function(widget)
		_G[GLOBAL_FRAME_NAME] = nil
		AceGUI:Release(widget)
		window, tabGroup, hoursBox, summaryLabel = nil, nil, nil, nil
		deleteArmedGuid = nil
	end)

	hoursBox = AceGUI:Create("EditBox")
	hoursBox:SetLabel("Hours to play this week")
	hoursBox:SetText(tostring(P().hoursBudget))
	hoursBox:SetWidth(170)
	hoursBox:SetCallback("OnEnterPressed", function(widget, _, text)
		if not ns.ATB:SetHours(text) then
			widget:SetText(tostring(P().hoursBudget))
			ns.Say("hours must be a number between 0 and 168.")
		end
	end)
	window:AddChild(hoursBox)

	summaryLabel = AceGUI:Create("Label")
	summaryLabel:SetWidth(440)
	window:AddChild(summaryLabel)

	local refreshBtn = AceGUI:Create("Button")
	refreshBtn:SetText("Rescan")
	refreshBtn:SetWidth(100)
	refreshBtn:SetCallback("OnClick", function()
		ns.Detection:ScanNow(false)
		MainWindow:RenderTab()
	end)
	window:AddChild(refreshBtn)

	tabGroup = AceGUI:Create("TabGroup")
	tabGroup:SetFullWidth(true)
	tabGroup:SetFullHeight(true)
	tabGroup:SetLayout("Fill")
	tabGroup:SetTabs(TABS)
	tabGroup:SetCallback("OnGroupSelected", function(_, _, value)
		P().window.tab = value
		deleteArmedGuid = nil
		MainWindow:RenderTab()
	end)
	window:AddChild(tabGroup)
	tabGroup:SelectTab(P().window.tab or "plan")

	-- Escape closes the window. The global only exists while the window is open (cleared in
	-- OnClose) so a recycled AceGUI frame is never hidden by Escape later.
	_G[GLOBAL_FRAME_NAME] = window.frame
	local found = false
	for _, name in ipairs(UISpecialFrames) do
		if name == GLOBAL_FRAME_NAME then found = true break end
	end
	if not found then
		tinsert(UISpecialFrames, GLOBAL_FRAME_NAME)
	end
end

function MainWindow:Close()
	if window then
		window:Hide() -- fires OnClose -> release
	end
end

function MainWindow:Toggle()
	if window then
		self:Close()
	else
		self:Open()
	end
end

function MainWindow:IsOpen()
	return window ~= nil
end

-- Coalesce data-change notifications into one re-render.
ns.RegisterUpdateListener("MainWindow", function(reason)
	if not window then return end
	if refreshTimer then return end
	refreshTimer = ns.ATB:ScheduleTimer(function()
		refreshTimer = nil
		if window then
			MainWindow:RenderTab()
		end
	end, 0.15)
end)
