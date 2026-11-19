-- SessionJournal: session lifecycle + event tracking
--
-- Lifecycle overview
--   * PLAYER_LOGOUT fires on BOTH logout/exit AND /reload, and can't tell them apart.
--     So the logout handler finalizes the session IN PLACE (end time, duration, zone time)
--     and marks it STATE_CLOSED, leaving it in db.global.current. That is the only work
--     done there (SavedVariable writes only).
--   * At the next PLAYER_ENTERING_WORLD:
--       - isReloadingUi + same character -> reopen the session (a /reload continues it)
--       - fresh login -> commit the closed session to the archive, then start a new one
--       - a session still STATE_OPEN at fresh login means the client crashed or disconnected
--         without PLAYER_LOGOUT. It is finalized using its last heartbeat (lastSeen).
--   * A heartbeat (every ns.HEARTBEAT_INTERVAL seconds) keeps lastSeen / duration current.
local addonName, ns = ...

local SJ = ns.SJ
local Debug = ns.Debug

local time = time
local type = type
local tonumber = tonumber
local select = select
local max = math.max
local tinsert = table.insert
local tremove = table.remove
local GetMoney = GetMoney
local UnitGUID = UnitGUID

local IsSecret = ns.IsSecret
local SafeString = ns.SafeString
local SafeNumber = ns.SafeNumber

local Tracker = {}
ns.Tracker = Tracker

local lootPatterns = {}
local started = false
local heartbeatTimer

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function DB()
	return ns.db
end

local function Current()
	local g = DB().global
	return g.current
end

local function IsLive(s)
	return s and s.state == ns.STATE_OPEN
end

local function CappedInsert(list, entry)
	if #list < ns.MAX_LIST_ENTRIES then
		tinsert(list, entry)
	end
end

local function CurrentZoneInfo()
	local name = SafeString(GetRealZoneText()) or SafeString(GetZoneText())
	local mapID
	if C_Map and C_Map.GetBestMapForUnit then
		mapID = SafeNumber(C_Map.GetBestMapForUnit("player"))
	end
	if not name and mapID and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		name = info and SafeString(info.name)
	end
	return name, mapID
end

-- Converts a Blizzard format string ("You receive loot: %sx%d.") into a Lua pattern.
-- Handles positional specifiers ("%1$s") used by some locales and returns the
-- argument index each capture maps to.
local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
local function FormatToPattern(fmt)
	local out = { "^" }
	local order = {}
	local nextArg = 1
	local i = 1
	local len = #fmt
	while i <= len do
		local c = fmt:sub(i, i)
		if c == "%" then
			local s, e, num, spec = fmt:find("^%%(%d*)%$?([sd])", i)
			if s then
				local argIndex = (num ~= "" and tonumber(num)) or nextArg
				nextArg = argIndex + 1
				order[#order + 1] = argIndex
				out[#out + 1] = (spec == "s") and "(.+)" or "(%d+)"
				i = e + 1
			elseif fmt:sub(i + 1, i + 1) == "%" then
				out[#out + 1] = "%%"
				i = i + 2
			else
				out[#out + 1] = "%%"
				i = i + 1
			end
		else
			if c:find(MAGIC) then
				out[#out + 1] = "%" .. c
			else
				out[#out + 1] = c
			end
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	return table.concat(out), order
end

-- Self-loot global strings, most specific (multiple) first. No hardcoded English.
local LOOT_FORMAT_GLOBALS = {
	"LOOT_ITEM_SELF_MULTIPLE",
	"LOOT_ITEM_SELF",
	"LOOT_ITEM_PUSHED_SELF_MULTIPLE",
	"LOOT_ITEM_PUSHED_SELF",
	"LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
	"LOOT_ITEM_BONUS_ROLL_SELF",
}

local function BuildLootPatterns()
	wipe(lootPatterns)
	for _, globalName in ipairs(LOOT_FORMAT_GLOBALS) do
		local fmt = _G[globalName]
		if type(fmt) == "string" and fmt ~= "" then
			local pattern, order = FormatToPattern(fmt)
			tinsert(lootPatterns, { name = globalName, pattern = pattern, order = order })
		else
			Debug:Log("Loot format global missing:", globalName)
		end
	end
	Debug:Log("Built", #lootPatterns, "loot patterns")
end

local function ParseLoot(text)
	for _, p in ipairs(lootPatterns) do
		local caps = { text:match(p.pattern) }
		if #caps > 0 then
			local args = {}
			for k = 1, #caps do
				args[p.order[k] or k] = caps[k]
			end
			local link = args[1]
			local count = tonumber(args[2]) or 1
			if link and link:find("|Hitem:", 1, true) then
				return link, count
			end
		end
	end
	return nil
end

function ns.GetItemQuality(link, itemID)
	if not link then return nil end
	local q
	if C_Item and C_Item.GetItemQualityByID then
		q = SafeNumber(C_Item.GetItemQualityByID(link))
	end
	if not q then
		-- Modern links embed quality as |cnIQ<n>:
		q = tonumber(link:match("|cnIQ(%d+):"))
	end
	return q
end

---------------------------------------------------------------------------
-- Session operations
---------------------------------------------------------------------------
local function FlushZoneTime(s, now)
	local last = s.zones[#s.zones]
	if last and s.zoneEnteredAt then
		local d = now - s.zoneEnteredAt
		if d > 0 then
			last.seconds = (last.seconds or 0) + d
		end
	end
	s.zoneEnteredAt = now
end

local function UpdateZone(s, now)
	local name, mapID = CurrentZoneInfo()
	if not name then return end
	FlushZoneTime(s, now)
	local last = s.zones[#s.zones]
	if last and last.name == name then
		return -- dedupe consecutive repeats
	end
	if #s.zones >= ns.MAX_LIST_ENTRIES then
		return
	end
	tinsert(s.zones, { name = name, mapID = mapID, enter = now, seconds = 0 })
	s.zoneEnteredAt = now
	Debug:Log("Zone:", name, mapID or "?")
end

local function NewSession()
	local g = DB().global
	local now = time()
	local className, classToken = UnitClass("player")
	local money = SafeNumber(GetMoney()) or 0
	local level = SafeNumber(UnitLevel("player")) or 0
	local s = {
		id = g.nextId,
		state = ns.STATE_OPEN,
		char = {
			name = SafeString(UnitName("player")) or "?",
			realm = SafeString(GetRealmName()) or "?",
			class = SafeString(classToken),
			className = SafeString(className),
			level = level,
			startLevel = level,
			guid = SafeString(UnitGUID("player")),
		},
		startTime = now,
		lastSeen = now,
		duration = 0,
		reloads = 0,
		zones = {},
		zoneEnteredAt = now,
		loot = {},
		lootItems = 0,       -- total quantity of items looted
		lootOverflow = 0,    -- unique items not stored because of the cap
		lootSkippedSecret = 0,
		deaths = {},
		deathCount = 0,
		money = { start = money, last = money, earned = 0, spent = 0 },
		achievements = {},
		levels = {},
		quests = {},
		questCount = 0,
		played = {},
	}
	g.nextId = g.nextId + 1
	g.current = s
	Debug:Log("New session #" .. s.id, ns.CharKey(s.char), "level", level, "money", money)
	return s
end

local function Finalize(s, endTime, reason)
	endTime = max(endTime or s.lastSeen or s.startTime, s.startTime)
	FlushZoneTime(s, endTime)
	s.endTime = endTime
	s.lastSeen = endTime
	s.duration = endTime - s.startTime
	s.closedBy = reason
	s.state = ns.STATE_CLOSED
end

local function TrimArchive()
	local g = DB().global
	local keep = DB().profile.retention or 200
	while #g.sessions > keep do
		local removed = tremove(g.sessions, 1)
		Debug:Log("Retention trimmed session #" .. (removed and removed.id or "?"))
	end
end

local function Commit(s)
	local minSeconds = (DB().profile.minDurationMinutes or 0) * 60
	local duration = s.duration or 0
	if duration < minSeconds then
		Debug:Log("Discarded short session #" .. s.id, "(" .. duration .. "s)")
		return false
	end
	s.state = nil
	s.zoneEnteredAt = nil
	tinsert(DB().global.sessions, s)
	TrimArchive()
	Debug:Log("Committed session #" .. s.id, ns.CharKey(s.char), ns.FormatDuration(duration), "closedBy", s.closedBy or "?")
	return true
end

---------------------------------------------------------------------------
-- Heartbeat
---------------------------------------------------------------------------
local function Heartbeat()
	local s = Current()
	if not IsLive(s) then return end
	local now = time()
	FlushZoneTime(s, now)
	s.lastSeen = now
	s.duration = now - s.startTime
end

local function StartHeartbeat()
	if heartbeatTimer then
		SJ:CancelTimer(heartbeatTimer)
	end
	heartbeatTimer = SJ:ScheduleRepeatingTimer(Heartbeat, ns.HEARTBEAT_INTERVAL)
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
local function SyncMoney(s)
	local m = SafeNumber(GetMoney())
	if not m then return end
	local d = m - (s.money.last or m)
	if d > 0 then
		s.money.earned = s.money.earned + d
	elseif d < 0 then
		s.money.spent = s.money.spent - d
	end
	s.money.last = m
end

function Tracker:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
	local now = time()
	if started then
		-- Later loading screens: just a zone check
		local s = Current()
		if IsLive(s) then
			UpdateZone(s, now)
			ns.NotifyUpdate("zone")
		end
		return
	end
	started = true

	local g = DB().global
	local s = g.current
	local guid = SafeString(UnitGUID("player"))
	local isNew = false
	Debug:Log("PEW first: isInitialLogin", isInitialLogin, "isReloadingUi", isReloadingUi, "pending", s and s.id or "none", s and s.state or "")

	if s then
		if isReloadingUi and s.char and s.char.guid == guid then
			-- /reload: continue the same session
			s.state = ns.STATE_OPEN
			s.endTime = nil
			s.closedBy = nil
			s.reloads = (s.reloads or 0) + 1
			s.zoneEnteredAt = s.zoneEnteredAt or now
			Debug:Log("Resumed session #" .. s.id, "after /reload")
		else
			if s.state == ns.STATE_OPEN then
				-- Never saw PLAYER_LOGOUT: crash / disconnect. Use the last heartbeat.
				Finalize(s, s.lastSeen or s.startTime, "crash")
				Debug:Log("Stale open session #" .. s.id, "finalized from lastSeen")
			end
			Commit(s)
			g.current = nil
			s = nil
		end
	end

	if not s then
		s = NewSession()
		isNew = true
	end

	SyncMoney(s)
	UpdateZone(s, now)
	s.lastSeen = now
	s.duration = now - s.startTime
	StartHeartbeat()

	if isNew and DB().profile.requestPlayed and RequestTimePlayed then
		C_Timer.After(5, function()
			RequestTimePlayed()
		end)
	end

	ns.NotifyUpdate("session")
end

-- Minimal: only SavedVariable writes are possible here.
function Tracker:PLAYER_LOGOUT()
	local s = Current()
	if IsLive(s) then
		Finalize(s, time(), "logout")
	end
end

function Tracker:ZONE_CHANGED_NEW_AREA()
	local s = Current()
	if not IsLive(s) then return end
	UpdateZone(s, time())
	ns.NotifyUpdate("zone")
end

function Tracker:PLAYER_MONEY()
	local s = Current()
	if not IsLive(s) then return end
	SyncMoney(s)
	ns.NotifyUpdate("money")
end

function Tracker:CHAT_MSG_LOOT(event, text)
	local s = Current()
	if not IsLive(s) then return end
	if IsSecret(text) then
		-- 12.0: chat payload text can be secret (e.g. restricted instance contexts). Skip safely.
		s.lootSkippedSecret = (s.lootSkippedSecret or 0) + 1
		Debug:Log("CHAT_MSG_LOOT text is secret, skipped")
		return
	end
	if type(text) ~= "string" then return end

	local link, count = ParseLoot(text)
	if not link then return end

	s.lootItems = (s.lootItems or 0) + count

	-- Aggregate by link
	for i = 1, #s.loot do
		local e = s.loot[i]
		if e.link == link then
			e.count = e.count + count
			e.t = time()
			ns.NotifyUpdate("loot")
			return
		end
	end

	if #s.loot >= (DB().profile.lootCap or 500) then
		s.lootOverflow = (s.lootOverflow or 0) + 1
	else
		local itemID
		if C_Item and C_Item.GetItemInfoInstant then
			itemID = SafeNumber((C_Item.GetItemInfoInstant(link)))
		end
		tinsert(s.loot, {
			link = link,
			id = itemID,
			count = count,
			quality = ns.GetItemQuality(link, itemID),
			t = time(),
		})
	end
	ns.NotifyUpdate("loot")
end

function Tracker:PLAYER_DEAD()
	local s = Current()
	if not IsLive(s) then return end
	local now = time()
	local last = s.deaths[#s.deaths]
	if last and now - last.t < ns.DEATH_DEDUPE_SECONDS then return end
	s.deathCount = (s.deathCount or 0) + 1
	CappedInsert(s.deaths, { t = now, zone = (CurrentZoneInfo()) })
	Debug:Log("Death #" .. s.deathCount)
	ns.NotifyUpdate("death")
end

function Tracker:ACHIEVEMENT_EARNED(event, achievementID, alreadyEarned)
	local s = Current()
	if not IsLive(s) then return end
	achievementID = SafeNumber(achievementID)
	if not achievementID then return end
	local name, points, link
	if GetAchievementInfo then
		local _, n, p = GetAchievementInfo(achievementID)
		name, points = SafeString(n), SafeNumber(p)
	end
	if GetAchievementLink then
		link = SafeString(GetAchievementLink(achievementID))
	end
	CappedInsert(s.achievements, {
		id = achievementID,
		name = name or ("Achievement " .. achievementID),
		points = points,
		link = link,
		t = time(),
		alreadyEarned = alreadyEarned and true or nil,
	})
	Debug:Log("Achievement:", achievementID, name or "?")
	ns.NotifyUpdate("achievement")
end

function Tracker:PLAYER_LEVEL_UP(event, level)
	local s = Current()
	if not IsLive(s) then return end
	level = SafeNumber(level)
	if not level then return end
	s.char.level = level
	CappedInsert(s.levels, { level = level, t = time() })
	Debug:Log("Level up:", level)
	ns.NotifyUpdate("level")
end

function Tracker:QUEST_TURNED_IN(event, questID)
	local s = Current()
	if not IsLive(s) or not DB().profile.trackQuests then return end
	questID = SafeNumber(questID)
	if not questID then return end
	local title
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		title = SafeString(C_QuestLog.GetTitleForQuestID(questID))
	end
	s.questCount = (s.questCount or 0) + 1
	CappedInsert(s.quests, { id = questID, title = title, t = time() })
	ns.NotifyUpdate("quest")
end

-- Passive /played capture: records whatever TIME_PLAYED_MSG arrives (from the user's own
-- /played or the optional request at session start). The chat line is NOT suppressed
-- because TIME_PLAYED_MSG bypasses chat message filters in 12.0.
function Tracker:TIME_PLAYED_MSG(event, totalTimePlayed)
	local s = Current()
	if not IsLive(s) then return end
	totalTimePlayed = SafeNumber(totalTimePlayed)
	if not totalTimePlayed then return end
	local p = s.played
	if not p.first then
		p.first = totalTimePlayed
		p.firstAt = time()
	end
	p.last = totalTimePlayed
	p.lastAt = time()
	Debug:Log("TIME_PLAYED_MSG total", totalTimePlayed)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
local EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LOGOUT",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_MONEY",
	"CHAT_MSG_LOOT",
	"PLAYER_DEAD",
	"ACHIEVEMENT_EARNED",
	"PLAYER_LEVEL_UP",
	"QUEST_TURNED_IN",
	"TIME_PLAYED_MSG",
}

function Tracker:Enable()
	BuildLootPatterns()
	for _, event in ipairs(EVENTS) do
		ns.RegisterEventSafe(SJ, event, function(...)
			Tracker[event](Tracker, ...)
		end)
	end
end

-- The live (or pending) session, or nil.
function Tracker:GetCurrent()
	return Current()
end

function Tracker:IsLive(s)
	return IsLive(s)
end

-- Duration that's correct for live and finished sessions.
function ns.SessionDuration(s)
	if not s then return 0 end
	if IsLive(s) then
		return time() - s.startTime
	end
	return s.duration or ((s.endTime or s.lastSeen or s.startTime) - s.startTime)
end

-- Zone seconds including the in-progress stretch of a live session.
function ns.ZoneSeconds(s, index)
	local z = s.zones[index]
	if not z then return 0 end
	local secs = z.seconds or 0
	if IsLive(s) and index == #s.zones and s.zoneEnteredAt then
		secs = secs + max(0, time() - s.zoneEnteredAt)
	end
	return secs
end

function ns.UniqueZoneCount(s)
	local seen, n = {}, 0
	for i = 1, #s.zones do
		local name = s.zones[i].name
		if name and not seen[name] then
			seen[name] = true
			n = n + 1
		end
	end
	return n
end

function Tracker:GetSessionByID(id)
	local cur = Current()
	if cur and cur.id == id then return cur end
	local list = DB().global.sessions
	for i = #list, 1, -1 do
		if list[i].id == id then return list[i] end
	end
	return nil
end

function Tracker:DeleteSession(id)
	local list = DB().global.sessions
	for i = #list, 1, -1 do
		if list[i].id == id then
			tremove(list, i)
			Debug:Log("Deleted session #" .. id)
			ns.NotifyUpdate("archive")
			return true
		end
	end
	return false
end

function Tracker:DeleteAll()
	wipe(DB().global.sessions)
	Debug:Log("Deleted all archived sessions")
	ns.NotifyUpdate("archive")
end

function Tracker:ApplyRetention()
	TrimArchive()
	ns.NotifyUpdate("archive")
end
