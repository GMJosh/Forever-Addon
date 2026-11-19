-- CraftPath: plans a whole leveling path from one skill level to another, using ForeverDB's recipe colors
-- (Data\Recipes.lua). Recipe data from ForeverDB.net (https://foreverdb.net).
local addonName, ns = ...

local max = math.max
local min = math.min
local insert = table.insert

local function Have(itemID)
	if C_Item and C_Item.GetItemCount then
		return C_Item.GetItemCount(itemID, true) or 0
	end
	return 0
end

-- Skill-up chance for a recipe at a skill level, from ForeverDB's thresholds.
-- o = orange starts, y = yellow, g = green, x = grey. Below o you cannot craft it.
local function ChanceAt(r, skill)
	if skill < r.o then
		return 0, nil
	elseif skill < r.y then
		return ns.SKILLUP_CHANCE[0], 0
	elseif skill < r.g then
		return ns.SKILLUP_CHANCE[1], 1
	elseif skill < r.x then
		return ns.SKILLUP_CHANCE[2], 2
	end
	return 0, 3
end

-- Copper cost of one craft, and how many reagents have no price.
local function CraftCost(r)
	local cost, unpriced = 0, 0
	for _, g in ipairs(r.r) do
		local price = ns.Price(g[1])
		if price then
			cost = cost + price * g[2]
		else
			unpriced = unpriced + 1
		end
	end
	local outValue = 0
	local outPrice = r.out and ns.Price(r.out)
	if outPrice then
		outValue = outPrice * (r.q or 1) * ns.AH_CUT
	end
	return cost - outValue, unpriced
end

-- Builds the plan. prof = the scanned profession (to know which recipes you have learned).
-- Returns { steps = {...}, shopping = {...}, total = copper, unpriced = n, from, to } or nil, reason.
function ns.BuildPath(profName, prof, fromSkill, toSkill, includeUnlearned)
	local data = ns.RecipeData and ns.RecipeData[profName]
	if not data then
		return nil, "No recipe data for " .. tostring(profName) .. "."
	end
	local learned = {}
	if prof then
		for _, r in ipairs(prof.recipes) do
			learned[r.id] = true
		end
	end
	local hasScan = prof and #prof.recipes > 0
	fromSkill = max(1, fromSkill or 1)
	toSkill = min(toSkill or data.max, data.max)
	if fromSkill >= toSkill then
		return nil, "Already at or above the target skill."
	end

	-- price each recipe once
	local pool = {}
	for _, r in ipairs(data.recipes) do
		local known = learned[r.id] or false
		if known or includeUnlearned or not hasScan then
			local net, unpriced = CraftCost(r)
			pool[#pool + 1] = { r = r, net = net, unpriced = unpriced, known = known }
		end
	end

	-- best recipe at every skill point
	local best = {}
	for s = fromSkill, toSkill - 1 do
		local pick, pickScore, pickChance
		for _, c in ipairs(pool) do
			local chance = ChanceAt(c.r, s)
			if chance > 0 then
				-- recipes with an unpriced reagent look free, so they only win when nothing priced can skill up here
				local score = c.net / chance + (c.unpriced > 0 and 1e12 or 0)
				if not pick or score < pickScore then
					pick, pickScore, pickChance = c, score, chance
				end
			end
		end
		best[s] = pick and { c = pick, chance = pickChance } or false
	end

	-- merge runs of the same recipe into steps
	local steps, gaps = {}, {}
	local s = fromSkill
	while s < toSkill do
		local b = best[s]
		if not b then
			gaps[#gaps + 1] = s
			s = s + 1
		else
			local step = { c = b.c, from = s, crafts = 0 }
			while s < toSkill and best[s] and best[s].c == b.c do
				step.crafts = step.crafts + 1 / best[s].chance
				s = s + 1
			end
			step.to = s
			step.crafts = math.ceil(step.crafts)
			steps[#steps + 1] = step
		end
	end
	if #steps == 0 then
		return nil, "No recipe in the data can skill you up from " .. fromSkill .. "."
	end

	-- shopping list across the whole path
	local need, total, unpricedItems = {}, 0, 0
	for _, st in ipairs(steps) do
		for _, g in ipairs(st.c.r.r) do
			need[g[1]] = (need[g[1]] or 0) + g[2] * st.crafts
		end
	end
	local shopping = {}
	for item, n in pairs(need) do
		local have = Have(item)
		local buy = max(0, n - have)
		local price = ns.Price(item)
		local cost = price and price * buy or nil
		if cost then
			total = total + cost
		else
			unpricedItems = unpricedItems + 1
		end
		shopping[#shopping + 1] = { item = item, need = n, have = have, buy = buy, cost = cost }
	end
	table.sort(shopping, function(a, b)
		return (a.cost or 0) > (b.cost or 0)
	end)
	return { steps = steps, shopping = shopping, total = total, unpriced = unpricedItems, from = fromSkill, to = toSkill, gaps = gaps }
end

local function WaypointLink(m, x, y)
	if m and m > 0 then
		return string.format(" |cff71d5ff|Hcraftpath:way:%d:%.1f:%.1f|h[waypoint]|h|r", m, x, y)
	end
	return ""
end

-- Where to learn a recipe you do not know yet: a nearby trainer or the vendor that sells it (ForeverDB data).
function ns.LearnSource(profName, r)
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local side = faction == "Alliance" and "A" or faction == "Horde" and "H" or "N"
	local ways = r.w or ""
	if ways:find("auto", 1, true) then
		return "learned automatically"
	end
	local v = (side == "H" and r.rvh) or (side == "A" and r.rva) or r.rva or r.rvh
	if ways:find("vendor", 1, true) and v then
		return string.format("buy the recipe from %s, %s (%.0f, %.0f)%s", v.n, v.z, v.x, v.y, WaypointLink(v.m, v.x, v.y))
	end
	local data = ns.RecipeData and ns.RecipeData[profName]
	if ways:find("trainer", 1, true) and data and data.trainers then
		local need, best = r.ls or r.o or 1, nil
		for _, t in ipairs(data.trainers) do
			if (t.s == side or t.s == "N") and t.u >= need and (not best or t.u < best.u) then
				best = t
			end
		end
		if best then
			return string.format("trainer %s, %s (%.0f, %.0f)%s", best.n, best.z, best.x, best.y, WaypointLink(best.m, best.x, best.y))
		end
		return "trainer"
	end
	return ways ~= "" and ways or "see ForeverDB"
end
