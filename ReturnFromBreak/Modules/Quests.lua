-- ReturnFromBreak: "Current Quests" section
-- Lists the super-tracked quest, campaign quests and watched (tracked) quests.
-- Click handling (super-track / open map) lives in UI\MainWindow.lua.
local addonName, ns = ...

local C_QuestLog = C_QuestLog
local C_SuperTrack = C_SuperTrack
local C_TaskQuest = C_TaskQuest
local C_CampaignInfo = C_CampaignInfo
local C_Map = C_Map
local GetQuestUiMapID = GetQuestUiMapID -- global, used by Blizzard's QuestMapFrame (not in generated docs)
local tsort = table.sort

local Clean = ns.Clean
local Color = ns.Color

local function MapName(mapID)
	mapID = Clean(mapID)
	if not mapID or mapID <= 0 or not C_Map.GetMapInfo then
		return nil
	end
	local info = C_Map.GetMapInfo(mapID)
	return info and Clean(info.name) or nil
end

-- Best uiMapID for a quest (used for zone label and "open map")
local function GetQuestMapID(questID)
	local mapID
	if GetQuestUiMapID then
		mapID = Clean(GetQuestUiMapID(questID))
	end
	if (not mapID or mapID <= 0) and C_TaskQuest and C_TaskQuest.GetQuestZoneID then
		mapID = Clean(C_TaskQuest.GetQuestZoneID(questID))
	end
	if (not mapID or mapID <= 0) and C_QuestLog.GetNextWaypoint then
		mapID = Clean((C_QuestLog.GetNextWaypoint(questID)))
	end
	if mapID and mapID > 0 then
		return mapID
	end
	return nil
end
ns.GetQuestMapID = GetQuestMapID

-- Walk the quest log once: questID -> { title, header, campaignID, hidden, task }
local function ScanQuestLog()
	local quests = {}
	if not C_QuestLog.GetNumQuestLogEntries then
		return quests
	end
	local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
	local header
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				header = Clean(info.title)
			elseif info.questID and info.questID > 0 then
				quests[info.questID] = {
					title = Clean(info.title),
					header = header,
					campaignID = info.campaignID,
					hidden = info.isHidden,
					task = info.isTask,
				}
			end
		end
	end
	return quests
end

local function StatusTag(questID)
	local ready = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
	if ready or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)) then
		return " " .. Color(ns.COLOR_GOOD, "(ready to turn in)")
	end
	return ""
end

local function MakeQuestRow(questID, logData, indent)
	local title = (logData and logData.title) or Clean(C_QuestLog.GetTitleForQuestID(questID)) or ("Quest #" .. questID)
	local mapID = GetQuestMapID(questID)
	local zone = MapName(mapID) or (logData and logData.header)
	local text = Color(ns.COLOR_WHITE, title)
	if zone and zone ~= "" then
		text = text .. "  " .. Color(ns.COLOR_DIM, "- " .. zone)
	end
	text = text .. StatusTag(questID)
	return {
		kind = "quest",
		text = text,
		questID = questID,
		mapID = mapID,
		title = title,
		zone = zone,
		indent = indent or 1,
	}
end

local function Build()
	local rows = {}
	if not (C_QuestLog and C_QuestLog.GetInfo) then
		rows[#rows + 1] = { kind = "empty", text = "Quest information is not available." }
		return rows
	end

	local log = ScanQuestLog()
	local shown = {}

	-- 1. Super-tracked (focused) quest
	local superID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Clean(C_SuperTrack.GetSuperTrackedQuestID())
	if superID and superID > 0 then
		rows[#rows + 1] = { kind = "subheader", text = "Focused quest" }
		rows[#rows + 1] = MakeQuestRow(superID, log[superID])
		shown[superID] = true
	end

	-- 2. Campaign quests, grouped by campaign
	local campaigns, campaignOrder = {}, {}
	for questID, data in pairs(log) do
		if data.campaignID and data.campaignID > 0 and not data.hidden and not shown[questID] then
			local list = campaigns[data.campaignID]
			if not list then
				list = {}
				campaigns[data.campaignID] = list
				campaignOrder[#campaignOrder + 1] = data.campaignID
			end
			list[#list + 1] = questID
		end
	end
	tsort(campaignOrder)
	for _, campaignID in ipairs(campaignOrder) do
		local name
		if C_CampaignInfo and C_CampaignInfo.GetCampaignInfo then
			local info = C_CampaignInfo.GetCampaignInfo(campaignID)
			name = info and Clean(info.name)
		end
		rows[#rows + 1] = { kind = "subheader", text = "Campaign: " .. (name or ("#" .. campaignID)) }
		local list = campaigns[campaignID]
		tsort(list)
		for _, questID in ipairs(list) do
			rows[#rows + 1] = MakeQuestRow(questID, log[questID])
			shown[questID] = true
		end
	end

	-- 3. Watched (tracked) quests not already listed
	local tracked = {}
	if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
		local numWatches = C_QuestLog.GetNumQuestWatches() or 0
		for i = 1, numWatches do
			local questID = Clean(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
			if questID and not shown[questID] then
				tracked[#tracked + 1] = questID
			end
		end
	end
	if #tracked > 0 then
		rows[#rows + 1] = { kind = "subheader", text = "Tracked quests" }
		for _, questID in ipairs(tracked) do
			rows[#rows + 1] = MakeQuestRow(questID, log[questID])
			shown[questID] = true
		end
	end

	if not next(shown) then
		rows[#rows + 1] = { kind = "empty", text = "No focused, campaign or tracked quests." }
	else
		rows[#rows + 1] = { kind = "empty", text = "Left-click a quest to focus it. Right-click to open the map." }
	end
	ns.Debug("Quests: super", superID, "campaigns", #campaignOrder, "tracked", #tracked)
	return rows
end

ns.Sections.quests = { Build = Build }
