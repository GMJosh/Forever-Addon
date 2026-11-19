-- LevelPace: turns the recorded time into a "where am I wasting time" report
local addonName, ns = ...

local format = string.format
local sort = table.sort

-- source = a record table: { b = { bucket = seconds }, xp = {...}, kills, deaths, maxIdle }
function ns.Total(b)
	local total = 0
	for _, bucket in ipairs(ns.BUCKETS) do
		total = total + (b[bucket.key] or 0)
	end
	return total
end

-- Plain-language tips, ordered by how much time each costs.
function ns.Tips(rec)
	local b = rec.b
	local total = ns.Total(b)
	local tips = {}
	if total < 120 then
		tips[1] = "Play a few more minutes and tips will show up here."
		return tips
	end
	local function share(...)
		local s = 0
		for _, k in ipairs({ ... }) do
			s = s + (b[k] or 0)
		end
		return s / total * 100
	end
	local travel = share("foot", "mount", "flight")
	local idle = share("idle")
	local town = share("town")
	local dead = share("dead")
	local loading = share("loading")
	if travel >= 30 then
		tips[#tips + 1] = format("Travel is %d%% of your time. Group quests by area and turn in several at once.", travel)
	end
	if idle >= 10 then
		tips[#tips + 1] = format("You stood still %d%% of the time (longest stretch %s). Plan breaks, or queue for something while you wait.",
			idle, ns.Clock(rec.maxIdle or 0))
	end
	if town >= 12 then
		tips[#tips + 1] = format("Town and NPC time is %d%%. Sell and repair in one trip, and hand in quests in batches.", town)
	end
	if dead >= 5 then
		tips[#tips + 1] = format("Dying cost %d%% of your time (%d deaths). Pull fewer mobs at once or skip tough quests.", dead, rec.deaths or 0)
	end
	if loading >= 5 then
		tips[#tips + 1] = format("Loading screens took %d%%. Fewer zone and instance hops will help.", loading)
	end
	if #tips == 0 then
		tips[1] = format("Nice pace: %d%% of your time is fighting and looting.", share("fight", "loot"))
	end
	return tips
end

-- Buckets sorted by time, wasteful ones only.
function ns.TopSinks(rec, count)
	local list = {}
	for _, bucket in ipairs(ns.BUCKETS) do
		local secs = rec.b[bucket.key] or 0
		if bucket.waste and secs > 0 then
			list[#list + 1] = { label = bucket.label, secs = secs }
		end
	end
	sort(list, function(a, c) return a.secs > c.secs end)
	while #list > (count or 3) do
		list[#list] = nil
	end
	return list
end

-- Zones ranked by XP per hour (only zones with enough time spent).
function ns.ZoneRanking(zones)
	local list = {}
	for name, z in pairs(zones) do
		if z.secs >= ns.ZONE_MIN_SECONDS then
			list[#list + 1] = { name = name, secs = z.secs, xp = z.xp, rate = z.xp / z.secs * 3600 }
		end
	end
	sort(list, function(a, c) return a.rate > c.rate end)
	return list
end
