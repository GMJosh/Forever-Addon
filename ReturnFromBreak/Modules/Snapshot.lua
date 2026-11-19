-- ReturnFromBreak: "Since Last Time" section and snapshot capture
--
-- Flow:
--   PLAYER_LOGOUT (also on /reload)  -> db.char.snapshot = TakeSnapshot()
--   PLAYER_ENTERING_WORLD initial    -> db.char.baseline = db.char.snapshot
--   Window                           -> diff baseline against live values
local addonName, ns = ...

local C_CurrencyInfo = C_CurrencyInfo
local GetServerTime = GetServerTime
local GetMoney = GetMoney
local UnitLevel = UnitLevel
local GetAverageItemLevel = GetAverageItemLevel -- global, used by Blizzard (LFGList); not in generated docs
local GetMoneyString = GetMoneyString
local BreakUpLargeNumbers = BreakUpLargeNumbers
local floor = math.floor
local abs = math.abs
local format = string.format
local date = date
local tsort = table.sort

local Clean = ns.Clean
local Color = ns.Color

local function Number(n)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n)
	end
	return tostring(n)
end

local function Money(copper)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return format("%dg", floor(copper / 10000))
end

local function EquippedItemLevel()
	if not GetAverageItemLevel then
		return nil
	end
	local _, equipped = GetAverageItemLevel()
	equipped = Clean(equipped)
	if equipped then
		return floor(equipped * 10 + 0.5) / 10
	end
	return nil
end

-- Reads every currency in the token list. When expandCollapsed is true (logout
-- only), collapsed headers are temporarily expanded so their children are
-- listed, then collapsed again afterwards. It is NOT used during normal window
-- refreshes because expanding fires CURRENCY_DISPLAY_UPDATE.
local function ReadCurrencies(expandCollapsed)
	local result = {}
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo) then
		return result
	end

	local expanded = {}
	local i = 1
	-- List size grows as headers are expanded, so re-read it each iteration
	while i <= C_CurrencyInfo.GetCurrencyListSize() do
		local info = C_CurrencyInfo.GetCurrencyListInfo(i)
		if info then
			if info.isHeader then
				if expandCollapsed and not info.isHeaderExpanded and C_CurrencyInfo.ExpandCurrencyList then
					C_CurrencyInfo.ExpandCurrencyList(i, true)
					expanded[#expanded + 1] = i
				end
			else
				local id = Clean(info.currencyID)
				local qty = Clean(info.quantity)
				if id and qty then
					result[id] = {
						name = Clean(info.name) or ("Currency #" .. id),
						qty = qty,
						icon = Clean(info.iconFileID),
					}
				end
			end
		end
		i = i + 1
		if i > 2000 then
			break -- safety
		end
	end

	-- Restore collapse state in reverse order so earlier indices stay valid
	for j = #expanded, 1, -1 do
		C_CurrencyInfo.ExpandCurrencyList(expanded[j], false)
	end
	return result
end

function ns.TakeSnapshot()
	local snap = {
		time = GetServerTime(),
		level = Clean(UnitLevel("player")),
		ilvl = EquippedItemLevel(),
		money = Clean(GetMoney()),
		currencies = ReadCurrencies(true),
	}
	return snap
end

local function TimeAgo(seconds)
	if seconds < 60 then
		return "less than a minute"
	elseif seconds < 3600 then
		local m = floor(seconds / 60)
		return m == 1 and "1 minute" or (m .. " minutes")
	elseif seconds < 86400 then
		local h = floor(seconds / 3600)
		return h == 1 and "1 hour" or (h .. " hours")
	end
	local d = floor(seconds / 86400)
	return d == 1 and "1 day" or (d .. " days")
end

local function Signed(delta, formatter)
	if delta > 0 then
		return Color(ns.COLOR_GOOD, "+" .. formatter(delta))
	elseif delta < 0 then
		return Color(ns.COLOR_BAD, "-" .. formatter(abs(delta)))
	end
	return Color(ns.COLOR_DIM, "no change")
end

local function Build()
	local rows = {}
	local char = ns.db.char
	local base = char.baseline

	if not base or not base.time then
		rows[#rows + 1] = { kind = "empty", text = "Snapshot will be saved when you log out; changes appear next time." }
		return rows
	end

	-- Time away
	local now = char.sessionStart or GetServerTime()
	local away = now - base.time
	if away < 0 then
		away = 0
	end
	rows[#rows + 1] = {
		kind = "text",
		text = format("Last played %s ago  %s", Color(ns.COLOR_WHITE, TimeAgo(away)),
			Color(ns.COLOR_DIM, "(" .. date("%b %d, %Y %H:%M", base.time) .. ")")),
	}

	-- Level
	local level = Clean(UnitLevel("player"))
	if level and base.level then
		local delta = level - base.level
		if delta ~= 0 then
			rows[#rows + 1] = { kind = "text", indent = 1, text = format("Level: %d -> %d  (%s)", base.level, level, Signed(delta, tostring)) }
		else
			rows[#rows + 1] = { kind = "text", indent = 1, text = format("Level: %d  %s", level, Color(ns.COLOR_DIM, "(no change)")) }
		end
	end

	-- Item level
	local ilvl = EquippedItemLevel()
	if ilvl and base.ilvl then
		local delta = floor((ilvl - base.ilvl) * 10 + 0.5) / 10
		if delta ~= 0 then
			rows[#rows + 1] = { kind = "text", indent = 1, text = format("Item level: %.1f -> %.1f  (%s)", base.ilvl, ilvl,
				Signed(delta, function(v) return format("%.1f", v) end)) }
		else
			rows[#rows + 1] = { kind = "text", indent = 1, text = format("Item level: %.1f  %s", ilvl, Color(ns.COLOR_DIM, "(no change)")) }
		end
	end

	-- Gold
	local money = Clean(GetMoney())
	if money and base.money then
		local delta = money - base.money
		rows[#rows + 1] = { kind = "text", indent = 1, text = format("Gold: %s  (%s)", Money(money), Signed(delta, Money)) }
	end

	-- Currencies: new or changed only
	-- Live values: currencies visible in the token list, plus a direct lookup of
	-- every currency from the baseline (covers ones under collapsed headers)
	local old_c = base.currencies or {}
	local now_c = ReadCurrencies(false)
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		for id, old in pairs(old_c) do
			if not now_c[id] then
				local info = C_CurrencyInfo.GetCurrencyInfo(id)
				local qty = info and Clean(info.quantity)
				if qty then
					now_c[id] = { name = Clean(info.name) or old.name, qty = qty, icon = Clean(info.iconFileID) or old.icon }
				end
			end
		end
	end
	local changes = {}
	for id, cur in pairs(now_c) do
		local old = old_c[id]
		if not old then
			if cur.qty > 0 then
				changes[#changes + 1] = { name = cur.name, icon = cur.icon, new = true, qty = cur.qty, delta = cur.qty }
			end
		elseif old.qty ~= cur.qty then
			changes[#changes + 1] = { name = cur.name, icon = cur.icon, old = old.qty, qty = cur.qty, delta = cur.qty - old.qty }
		end
	end
	tsort(changes, function(a, b)
		local an, bn = a.new and 1 or 0, b.new and 1 or 0
		if an ~= bn then
			return an > bn
		end
		return a.name < b.name
	end)

	if #changes == 0 then
		rows[#rows + 1] = { kind = "text", indent = 1, text = "Currencies: " .. Color(ns.COLOR_DIM, "no changes") }
	else
		rows[#rows + 1] = { kind = "subheader", text = format("Currencies (%d new or changed)", #changes) }
		local maxLines = tonumber(ns.db.profile.maxCurrencyLines) or 25
		for idx, c in ipairs(changes) do
			if idx > maxLines then
				rows[#rows + 1] = { kind = "empty", text = format("...and %d more.", #changes - maxLines) }
				break
			end
			local iconStr = c.icon and format("|T%s:14:14:0:0|t ", c.icon) or ""
			local text
			if c.new then
				text = format("%s%s: %s  %s", iconStr, Color(ns.COLOR_WHITE, c.name), Number(c.qty), Color(ns.COLOR_GOOD, "(new)"))
			else
				text = format("%s%s: %s -> %s  (%s)", iconStr, Color(ns.COLOR_WHITE, c.name), Number(c.old), Number(c.qty), Signed(c.delta, Number))
			end
			rows[#rows + 1] = { kind = "text", indent = 1, text = text }
		end
	end

	ns.Debug("Snapshot diff: away", away, "currency changes", #changes)
	return rows
end

ns.Sections.snapshot = { Build = Build }
