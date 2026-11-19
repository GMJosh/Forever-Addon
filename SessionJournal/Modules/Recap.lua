-- SessionJournal: recap formatters
--   Recap:Build(session, "prose")     -> short plain-text prose (copyable)
--   Recap:Build(session, "markdown")  -> Discord / Markdown summary (copyable)
--   Recap:BuildDetail(session)        -> colored, full diary for the logbook detail pane
local addonName, ns = ...

local date = date
local format = string.format
local tinsert = table.insert
local tconcat = table.concat
local sort = table.sort
local max = math.max

local Recap = {}
ns.Recap = Recap

local GOLD = "|cffffd100"
local GREY = "|cff9d9d9d"
local WHITE = "|cffffffff"
local GREEN = "|cff40ff40"
local RED = "|cffff4040"

local MARKDOWN_MAX_ZONES = 8
local PROSE_MAX_LOOT = 6
local MARKDOWN_MAX_LOOT = 12

---------------------------------------------------------------------------
-- Data preparation
---------------------------------------------------------------------------
local function JoinNatural(list)
	local n = #list
	if n == 0 then return "" end
	if n == 1 then return list[1] end
	return tconcat(list, ", ", 1, n - 1) .. " and " .. list[n]
end

local function Plural(n, one, many)
	return n == 1 and one or many
end

-- Aggregates zone time by name, returns { {name, seconds}, ... } sorted by time desc
local function ZoneTotals(s)
	local totals, order = {}, {}
	for i = 1, #s.zones do
		local name = s.zones[i].name
		if name then
			if not totals[name] then
				totals[name] = 0
				order[#order + 1] = name
			end
			totals[name] = totals[name] + ns.ZoneSeconds(s, i)
		end
	end
	local list = {}
	for _, name in ipairs(order) do
		list[#list + 1] = { name = name, seconds = totals[name] }
	end
	sort(list, function(a, b) return a.seconds > b.seconds end)
	return list
end

-- Loot at or above the configured quality, highest quality first.
local function NotableLoot(s)
	local threshold = ns.db.profile.recapQuality or 3
	local list = {}
	for i = 1, #s.loot do
		local e = s.loot[i]
		if e.quality == nil then
			e.quality = ns.GetItemQuality(e.link, e.id) -- item cache may be warm now
		end
		if e.quality and e.quality >= threshold then
			list[#list + 1] = e
		end
	end
	sort(list, function(a, b)
		if a.quality ~= b.quality then return a.quality > b.quality end
		return (a.t or 0) < (b.t or 0)
	end)
	return list
end

local function LootLabel(e, plain)
	local name = plain and ns.StripLink(e.link) or e.link
	if (e.count or 1) > 1 then
		return name .. " x" .. e.count
	end
	return name
end

local function AchievementLabel(a, plain)
	if not plain and a.link then return a.link end
	return "[" .. (a.name or ("#" .. a.id)) .. "]"
end

local function DeathZoneMost(s)
	local counts, best, bestN = {}, nil, 0
	for i = 1, #s.deaths do
		local z = s.deaths[i].zone
		if z then
			counts[z] = (counts[z] or 0) + 1
			if counts[z] > bestN then
				best, bestN = z, counts[z]
			end
		end
	end
	return best, bestN
end

local function CharDescription(s)
	local c = s.char or {}
	local parts = {}
	if c.level and c.level > 0 then parts[#parts + 1] = "level " .. c.level end
	if c.className then parts[#parts + 1] = c.className end
	return tconcat(parts, " ")
end

local function PlayedDelta(s)
	local p = s.played
	if p and p.first and p.last and p.last > p.first then
		return p.last - p.first
	end
	return nil
end

local function MoneyNet(s)
	local m = s.money or {}
	return (m.last or 0) - (m.start or 0), m.earned or 0, m.spent or 0
end

local function TimeRange(s)
	local startStr = date("%H:%M", s.startTime)
	if ns.Tracker:IsLive(s) then
		return startStr, nil
	end
	return startStr, date("%H:%M", s.endTime or s.lastSeen or s.startTime)
end

---------------------------------------------------------------------------
-- Prose
---------------------------------------------------------------------------
local function BuildProse(s)
	local lines = {}
	local c = s.char or {}
	local dur = ns.FormatDuration(ns.SessionDuration(s))
	local startStr, endStr = TimeRange(s)
	local who = ns.CharKey(c)
	local desc = CharDescription(s)
	if desc ~= "" then who = who .. " (" .. desc .. ")" end
	local day = date("%A, %B %d, %Y", s.startTime)

	if endStr then
		tinsert(lines, format("%s played on %s from %s to %s, a session of %s.", who, day, startStr, endStr, dur))
	else
		tinsert(lines, format("%s has been playing since %s on %s, %s so far.", who, startStr, day, dur))
	end

	-- Zones
	local zoneCount = ns.UniqueZoneCount(s)
	if zoneCount > 0 then
		local first = s.zones[1].name
		local last = s.zones[#s.zones].name
		local totals = ZoneTotals(s)
		local top = totals[1]
		if zoneCount == 1 then
			tinsert(lines, format("The whole session was spent in %s.", first))
		else
			local sentence = format("The journey covered %d zones, starting in %s and ending in %s", zoneCount, first, last)
			if top and top.seconds >= 60 then
				sentence = sentence .. format(", with the most time spent in %s (%s)", top.name, ns.FormatDuration(top.seconds))
			end
			tinsert(lines, sentence .. ".")
		end
	end

	-- Loot
	local lootItems = s.lootItems or 0
	if lootItems > 0 then
		local notable = NotableLoot(s)
		local sentence = format("Looted %d %s", lootItems, Plural(lootItems, "item", "items"))
		if #notable > 0 then
			local labels = {}
			for i = 1, math.min(#notable, PROSE_MAX_LOOT) do
				labels[i] = LootLabel(notable[i], true)
			end
			if #notable > PROSE_MAX_LOOT then
				labels[#labels + 1] = format("%d more", #notable - PROSE_MAX_LOOT)
			end
			sentence = sentence .. ". Highlights: " .. JoinNatural(labels)
		end
		tinsert(lines, sentence .. ".")
	end

	-- Achievements
	if #s.achievements > 0 then
		local labels = {}
		for i = 1, #s.achievements do
			labels[i] = AchievementLabel(s.achievements[i], true)
		end
		tinsert(lines, format("Earned %d %s: %s.", #s.achievements, Plural(#s.achievements, "achievement", "achievements"), JoinNatural(labels)))
	end

	-- Levels
	if #s.levels > 0 then
		local from = c.startLevel or (s.levels[1].level - 1)
		tinsert(lines, format("Leveled up from %d to %d.", from, c.level or s.levels[#s.levels].level))
	end

	-- Quests
	if (s.questCount or 0) > 0 then
		tinsert(lines, format("Completed %d %s.", s.questCount, Plural(s.questCount, "quest", "quests")))
	end

	-- Deaths
	local deaths = s.deathCount or 0
	if deaths > 0 then
		local zone, n = DeathZoneMost(s)
		if zone and deaths > 1 and n > 1 then
			tinsert(lines, format("Died %d times, most often in %s.", deaths, zone))
		elseif zone then
			tinsert(lines, format("Died %d %s%s.", deaths, Plural(deaths, "time", "times"), deaths == 1 and (" in " .. zone) or ""))
		else
			tinsert(lines, format("Died %d %s.", deaths, Plural(deaths, "time", "times")))
		end
	else
		tinsert(lines, "Made it through without dying.")
	end

	-- Gold
	local net, earned, spent = MoneyNet(s)
	if net ~= 0 or earned > 0 or spent > 0 then
		local dir = net >= 0 and "Gold up" or "Gold down"
		tinsert(lines, format("%s %s (earned %s, spent %s).", dir, ns.FormatMoneyPlain(math.abs(net)), ns.FormatMoneyPlain(earned), ns.FormatMoneyPlain(spent)))
	end

	local played = PlayedDelta(s)
	if played then
		tinsert(lines, format("/played advanced by %s.", ns.FormatDuration(played)))
	end

	return tconcat(lines, " ")
end

---------------------------------------------------------------------------
-- Discord / Markdown
---------------------------------------------------------------------------
local function BuildMarkdown(s)
	local out = {}
	local c = s.char or {}
	local startStr, endStr = TimeRange(s)
	local dur = ns.FormatDuration(ns.SessionDuration(s))

	tinsert(out, "### Session Journal: " .. ns.CharKey(c))
	local meta = {}
	local desc = CharDescription(s)
	if desc ~= "" then meta[#meta + 1] = desc:gsub("^l", "L") end
	meta[#meta + 1] = date("%a %b %d, %Y", s.startTime)
	meta[#meta + 1] = startStr .. " - " .. (endStr or "now")
	meta[#meta + 1] = dur .. (endStr and "" or " (in progress)")
	tinsert(out, "*" .. tconcat(meta, " | ") .. "*")
	tinsert(out, "")

	-- Zones in visit order
	local zoneCount = ns.UniqueZoneCount(s)
	if #s.zones > 0 then
		local parts = {}
		for i = 1, math.min(#s.zones, MARKDOWN_MAX_ZONES) do
			parts[i] = format("%s (%s)", s.zones[i].name, ns.FormatDuration(ns.ZoneSeconds(s, i)))
		end
		if #s.zones > MARKDOWN_MAX_ZONES then
			parts[#parts + 1] = format("+%d more", #s.zones - MARKDOWN_MAX_ZONES)
		end
		tinsert(out, format("- **Zones (%d):** %s", zoneCount, tconcat(parts, " > ")))
	end

	-- Loot
	local lootItems = s.lootItems or 0
	local notable = NotableLoot(s)
	local lootLine = format("- **Loot:** %d %s", lootItems, Plural(lootItems, "item", "items"))
	if #notable > 0 then
		local labels = {}
		for i = 1, math.min(#notable, MARKDOWN_MAX_LOOT) do
			labels[i] = LootLabel(notable[i], true)
		end
		if #notable > MARKDOWN_MAX_LOOT then
			labels[#labels + 1] = format("+%d more", #notable - MARKDOWN_MAX_LOOT)
		end
		lootLine = lootLine .. " | Notable: " .. tconcat(labels, ", ")
	end
	tinsert(out, lootLine)

	-- Gold
	local net, earned, spent = MoneyNet(s)
	tinsert(out, format("- **Gold:** %s (earned %s / spent %s)", ns.FormatMoneyPlain(net, true), ns.FormatMoneyPlain(earned), ns.FormatMoneyPlain(spent)))

	-- Deaths
	tinsert(out, format("- **Deaths:** %d", s.deathCount or 0))

	-- Achievements
	if #s.achievements > 0 then
		local labels = {}
		for i = 1, #s.achievements do
			labels[i] = AchievementLabel(s.achievements[i], true)
		end
		tinsert(out, format("- **Achievements (%d):** %s", #s.achievements, tconcat(labels, ", ")))
	end

	-- Levels
	if #s.levels > 0 then
		local from = c.startLevel or (s.levels[1].level - 1)
		tinsert(out, format("- **Level:** %d > %d", from, c.level or s.levels[#s.levels].level))
	end

	-- Quests
	if (s.questCount or 0) > 0 then
		tinsert(out, format("- **Quests completed:** %d", s.questCount))
	end

	local played = PlayedDelta(s)
	if played then
		tinsert(out, format("- **/played this session:** %s", ns.FormatDuration(played)))
	end

	return tconcat(out, "\n")
end

function Recap:Build(s, fmt)
	if not s then return "" end
	if fmt == "markdown" then
		return BuildMarkdown(s)
	end
	return BuildProse(s)
end

---------------------------------------------------------------------------
-- Detail view (colored, full lists) for the logbook
---------------------------------------------------------------------------
local function Header(out, text)
	tinsert(out, "")
	tinsert(out, GOLD .. text .. "|r")
end

function Recap:BuildDetail(s)
	if not s then return "" end
	local out = {}
	local c = s.char or {}
	local live = ns.Tracker:IsLive(s)
	local startStr, endStr = TimeRange(s)

	tinsert(out, ns.ClassColoredName(c) .. GREY .. " - " .. (c.realm or "?") .. "|r")
	local desc = CharDescription(s)
	if desc ~= "" then tinsert(out, WHITE .. desc:gsub("^l", "L") .. "|r") end
	tinsert(out, date("%A, %B %d, %Y", s.startTime) .. "   " .. startStr .. " - " .. (endStr or (GREEN .. "in progress|r")))
	local durLine = "Duration: " .. WHITE .. ns.FormatDuration(ns.SessionDuration(s)) .. "|r"
	if (s.reloads or 0) > 0 then
		durLine = durLine .. GREY .. format("  (%d %s)", s.reloads, Plural(s.reloads, "reload", "reloads")) .. "|r"
	end
	if s.closedBy == "crash" then
		durLine = durLine .. GREY .. "  (closed from last heartbeat)|r"
	end
	tinsert(out, durLine)
	local played = PlayedDelta(s)
	if played then
		tinsert(out, "/played delta: " .. WHITE .. ns.FormatDuration(played) .. "|r")
	elseif s.played and s.played.last then
		tinsert(out, GREY .. "Total /played: " .. ns.FormatDuration(s.played.last) .. "|r")
	end

	-- Summary
	Header(out, "Prose recap")
	tinsert(out, WHITE .. BuildProse(s) .. "|r")

	-- Gold
	local net, earned, spent = MoneyNet(s)
	Header(out, "Gold")
	tinsert(out, "Net: " .. ns.FormatMoneyUI(net, true))
	tinsert(out, "Earned: " .. ns.FormatMoneyUI(earned) .. "    Spent: " .. ns.FormatMoneyUI(spent))

	-- Zones
	Header(out, format("Zones (%d visited)", ns.UniqueZoneCount(s)))
	if #s.zones == 0 then
		tinsert(out, GREY .. "None recorded|r")
	end
	for i = 1, #s.zones do
		local z = s.zones[i]
		tinsert(out, format("%s%s|r  %s  %s(%s)|r", GREY, date("%H:%M", z.enter or s.startTime), z.name or "?", GREY, ns.FormatDuration(ns.ZoneSeconds(s, i))))
	end

	-- Loot
	Header(out, format("Loot (%d items, %d unique)", s.lootItems or 0, #s.loot + (s.lootOverflow or 0)))
	if #s.loot == 0 then
		tinsert(out, GREY .. "None recorded|r")
	else
		local threshold = ns.db.profile.recapQuality or 3
		local notable = NotableLoot(s)
		for i = 1, #notable do
			tinsert(out, LootLabel(notable[i], false))
		end
		local lesser = #s.loot - #notable
		if lesser > 0 then
			local qName = _G["ITEM_QUALITY" .. threshold .. "_DESC"] or tostring(threshold)
			tinsert(out, GREY .. format("+ %d lower-quality %s (below %s)", lesser, Plural(lesser, "item", "items"), qName) .. "|r")
		end
	end
	if (s.lootOverflow or 0) > 0 then
		tinsert(out, GREY .. format("%d more unique items not stored (loot cap)", s.lootOverflow) .. "|r")
	end
	if (s.lootSkippedSecret or 0) > 0 then
		tinsert(out, GREY .. format("%d loot messages skipped (restricted/secret text)", s.lootSkippedSecret) .. "|r")
	end

	-- Achievements
	if #s.achievements > 0 then
		Header(out, format("Achievements (%d)", #s.achievements))
		for i = 1, #s.achievements do
			local a = s.achievements[i]
			tinsert(out, format("%s%s|r  %s", GREY, date("%H:%M", a.t), AchievementLabel(a, false)))
		end
	end

	-- Levels
	if #s.levels > 0 then
		Header(out, "Level ups")
		for i = 1, #s.levels do
			local l = s.levels[i]
			tinsert(out, format("%s%s|r  Reached level %d", GREY, date("%H:%M", l.t), l.level))
		end
	end

	-- Deaths
	Header(out, format("Deaths (%d)", s.deathCount or 0))
	if #s.deaths == 0 then
		tinsert(out, GREY .. "None|r")
	end
	for i = 1, #s.deaths do
		local d = s.deaths[i]
		tinsert(out, format("%s%s|r  %s%s|r", GREY, date("%H:%M", d.t), RED, d.zone or "Unknown zone"))
	end

	-- Quests
	if (s.questCount or 0) > 0 then
		Header(out, format("Quests completed (%d)", s.questCount))
		for i = 1, #s.quests do
			local q = s.quests[i]
			tinsert(out, format("%s%s|r  %s", GREY, date("%H:%M", q.t), q.title or ("Quest #" .. q.id)))
		end
	end

	if live then
		tinsert(out, "")
		tinsert(out, GREY .. "Live session: this view updates as you play.|r")
	end

	return tconcat(out, "\n")
end
