-- SessionJournal: logbook window (session list + diary detail) and recap copy window
local addonName, ns = ...

local AceGUI = LibStub("AceGUI-3.0")
local Debug = ns.Debug

local date = date
local format = string.format
local tostring = tostring
local tonumber = tonumber
local sort = table.sort

local Logbook = {}
ns.Logbook = Logbook

local window          -- AceGUI Frame
local tree            -- AceGUI TreeGroup
local filterDropdown
local detailLabel
local detailScroll
local detailSessionId
local deleteArmedId   -- two-click delete confirmation

local copyWindow
local copyEditBox
local copyFormatDropdown
local copySessionId

local ALL = "ALL"
local GREEN = "|cff40ff40"
local GREY = "|cff9d9d9d"

local function Profile()
	return ns.db.profile
end

---------------------------------------------------------------------------
-- Session list helpers
---------------------------------------------------------------------------
-- All sessions newest first, including the live one at the top.
local function AllSessionsNewestFirst()
	local list = {}
	local cur = ns.Tracker:GetCurrent()
	if cur then
		list[#list + 1] = cur
	end
	local archive = ns.db.global.sessions
	for i = #archive, 1, -1 do
		list[#list + 1] = archive[i]
	end
	return list
end

local function BuildFilterList()
	local values, order = { [ALL] = "All characters" }, { ALL }
	local keys = {}
	for _, s in ipairs(AllSessionsNewestFirst()) do
		local key = ns.CharKey(s.char)
		if not values[key] then
			values[key] = key
			keys[#keys + 1] = key
		end
	end
	sort(keys)
	for _, k in ipairs(keys) do
		order[#order + 1] = k
	end
	return values, order
end

local function SessionTreeText(s)
	local prefix = ""
	if ns.Tracker:IsLive(s) then
		prefix = GREEN .. "Live|r "
	end
	return format("%s%s %s %s%s|r", prefix, date("%m/%d %H:%M", s.startTime), ns.ClassColoredName(s.char), GREY, ns.FormatDuration(ns.SessionDuration(s)))
end

local function BuildTree()
	local filter = Profile().logbook.filter or ALL
	local items = {}
	for _, s in ipairs(AllSessionsNewestFirst()) do
		if filter == ALL or ns.CharKey(s.char) == filter then
			items[#items + 1] = { value = tostring(s.id), text = SessionTreeText(s) }
		end
	end
	return items
end

---------------------------------------------------------------------------
-- Detail pane
---------------------------------------------------------------------------
local function RenderDetail(container, session)
	container:ReleaseChildren()
	detailLabel, detailScroll, detailSessionId = nil, nil, nil
	deleteArmedId = nil

	if not session then
		local empty = AceGUI:Create("Label")
		empty:SetFullWidth(true)
		empty:SetText("No sessions yet. Play for a bit and your journal will fill in automatically.")
		container:AddChild(empty)
		return
	end

	local isLive = ns.Tracker:IsLive(session)

	local copyBtn = AceGUI:Create("Button")
	copyBtn:SetText("Copy recap")
	copyBtn:SetWidth(130)
	copyBtn:SetCallback("OnClick", function()
		Logbook:OpenCopyWindow(session)
	end)
	container:AddChild(copyBtn)

	local deleteBtn = AceGUI:Create("Button")
	deleteBtn:SetText(isLive and "Live (can't delete)" or "Delete session")
	deleteBtn:SetWidth(170)
	deleteBtn:SetDisabled(isLive)
	deleteBtn:SetCallback("OnClick", function(widget)
		if deleteArmedId ~= session.id then
			deleteArmedId = session.id
			widget:SetText("Click again to delete")
			return
		end
		deleteArmedId = nil
		ns.Tracker:DeleteSession(session.id) -- triggers an "archive" refresh
	end)
	container:AddChild(deleteBtn)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local label = AceGUI:Create("Label")
	label:SetFullWidth(true)
	label:SetFontObject(GameFontHighlight)
	label:SetText(ns.Recap:BuildDetail(session))
	scroll:AddChild(label)

	detailLabel, detailScroll, detailSessionId = label, scroll, session.id
end

local function OnGroupSelected(container, event, value)
	local id = tonumber(value)
	local session = id and ns.Tracker:GetSessionByID(id)
	RenderDetail(container, session)
end

local function RefreshTree(keepSelection)
	if not tree then return end
	local items = BuildTree()
	tree:SetTree(items)
	local status = Profile().logbook.treeStatus
	local selected = keepSelection and status.selected
	local found = false
	if selected then
		for _, item in ipairs(items) do
			if item.value == selected then
				found = true
				break
			end
		end
	end
	-- TreeGroup only fires OnGroupSelected when the value changes; clear it to force a re-render
	status.selected = nil
	if found then
		tree:SelectByValue(selected)
	elseif items[1] then
		tree:SelectByValue(items[1].value)
	else
		RenderDetail(tree, nil)
	end
end

local function RefreshFilter()
	if not filterDropdown then return end
	local values, order = BuildFilterList()
	local filter = Profile().logbook.filter or ALL
	if not values[filter] then
		filter = ALL
		Profile().logbook.filter = ALL
	end
	filterDropdown:SetList(values, order)
	filterDropdown:SetValue(filter)
end

-- Called by the tracker whenever something changes.
local function OnUpdate(reason)
	if window then
		if reason == "archive" or reason == "session" then
			RefreshFilter()
			RefreshTree(true)
		else
			-- Live data changed: refresh the detail text in place if the live session is shown
			local cur = ns.Tracker:GetCurrent()
			if cur and detailLabel and detailSessionId == cur.id then
				detailLabel:SetText(ns.Recap:BuildDetail(cur))
				detailScroll:DoLayout()
			end
		end
	end
	-- The copy window is a snapshot on purpose: refreshing it on live events would
	-- steal keyboard focus mid-play. Switching format regenerates it.
end

---------------------------------------------------------------------------
-- Logbook window
---------------------------------------------------------------------------
function Logbook:Open()
	if window then return end
	ns.RegisterUpdateListener("Logbook", OnUpdate)

	local lb = Profile().logbook
	window = AceGUI:Create("Frame")
	window:SetTitle("Session Journal")
	window:SetStatusTable(lb.status)
	if not lb.status.width then
		window:SetWidth(820)
		window:SetHeight(560)
	end
	window:SetLayout("Flow")
	window:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		window, tree, filterDropdown, detailLabel, detailScroll, detailSessionId = nil, nil, nil, nil, nil, nil
	end)

	filterDropdown = AceGUI:Create("Dropdown")
	filterDropdown:SetLabel("Character")
	filterDropdown:SetWidth(260)
	filterDropdown:SetCallback("OnValueChanged", function(widget, event, key)
		Profile().logbook.filter = key
		RefreshTree(true)
	end)
	window:AddChild(filterDropdown)

	local configBtn = AceGUI:Create("Button")
	configBtn:SetText("Settings")
	configBtn:SetWidth(110)
	configBtn:SetCallback("OnClick", function()
		ns.SJ:OpenConfig()
	end)
	window:AddChild(configBtn)

	local trackerBtn = AceGUI:Create("Button")
	trackerBtn:SetText("Toggle tracker")
	trackerBtn:SetWidth(130)
	trackerBtn:SetCallback("OnClick", function()
		ns.LiveTracker:Toggle()
	end)
	window:AddChild(trackerBtn)

	tree = AceGUI:Create("TreeGroup")
	tree:SetFullWidth(true)
	tree:SetFullHeight(true)
	tree:SetLayout("Flow")
	tree:SetStatusTable(lb.treeStatus)
	tree:EnableButtonTooltips(false)
	tree:SetCallback("OnGroupSelected", OnGroupSelected)
	window:AddChild(tree)

	local count = #ns.db.global.sessions
	window:SetStatusText(format("%d archived %s. Keeping the last %d.", count, count == 1 and "session" or "sessions", Profile().retention))

	RefreshFilter()
	RefreshTree(true)
	Debug:Log("Logbook opened")
end

function Logbook:Close()
	if window then
		window:Hide() -- fires OnClose -> Release
	end
end

function Logbook:Toggle()
	if window then
		self:Close()
	else
		self:Open()
	end
end

---------------------------------------------------------------------------
-- Copy recap window
---------------------------------------------------------------------------
function Logbook:UpdateCopyText()
	if not copyWindow or not copyEditBox then return end
	local session = copySessionId and ns.Tracker:GetSessionByID(copySessionId)
	local text = session and ns.Recap:Build(session, Profile().recapFormat) or ""
	copyEditBox:SetText(text)
	copyEditBox:SetFocus()
	copyEditBox:HighlightText()
end

function Logbook:OpenCopyWindow(session)
	if not session then return end
	copySessionId = session.id
	ns.RegisterUpdateListener("Logbook", OnUpdate)

	if not copyWindow then
		copyWindow = AceGUI:Create("Frame")
		copyWindow:SetTitle("Session Recap")
		copyWindow:SetStatusTable(Profile().copyStatus)
		if not Profile().copyStatus.width then
			copyWindow:SetWidth(560)
			copyWindow:SetHeight(380)
		end
		copyWindow:SetLayout("Flow")
		copyWindow:SetStatusText("Ctrl+A to select all, Ctrl+C to copy.")
		copyWindow:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			copyWindow, copyEditBox, copyFormatDropdown, copySessionId = nil, nil, nil, nil
		end)

		copyFormatDropdown = AceGUI:Create("Dropdown")
		copyFormatDropdown:SetLabel("Format")
		copyFormatDropdown:SetWidth(220)
		copyFormatDropdown:SetList({ prose = "Prose", markdown = "Discord / Markdown" }, { "prose", "markdown" })
		copyFormatDropdown:SetCallback("OnValueChanged", function(widget, event, key)
			Profile().recapFormat = key
			Logbook:UpdateCopyText()
		end)
		copyWindow:AddChild(copyFormatDropdown)

		local selectBtn = AceGUI:Create("Button")
		selectBtn:SetText("Select all")
		selectBtn:SetWidth(120)
		selectBtn:SetCallback("OnClick", function()
			if copyEditBox then
				copyEditBox:SetFocus()
				copyEditBox:HighlightText()
			end
		end)
		copyWindow:AddChild(selectBtn)

		copyEditBox = AceGUI:Create("MultiLineEditBox")
		copyEditBox:SetLabel("")
		copyEditBox:DisableButton(true)
		copyEditBox:SetFullWidth(true)
		copyEditBox:SetFullHeight(true)
		copyWindow:AddChild(copyEditBox)
	end

	copyFormatDropdown:SetValue(Profile().recapFormat or "prose")
	self:UpdateCopyText()
end
