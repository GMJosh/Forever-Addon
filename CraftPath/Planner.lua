-- CraftPath: prices, ranking by cost per skill-up, and the shopping list
local addonName, ns = ...

local sort = table.sort
local max = math.max

-- Copper for one item: your own price first (vendor items), then Auctionator. nil when unknown.
function ns.Price(itemID)
	if not itemID then
		return nil
	end
	local own = ns.db.prices[itemID]
	if own then
		return own
	end
	local A = Auctionator and Auctionator.API and Auctionator.API.v1
	if A and A.GetAuctionPriceByItemID then
		local ok, price = pcall(A.GetAuctionPriceByItemID, "CraftPath", itemID)
		if ok and price and price > 0 then
			return price
		end
	end
	return nil
end

local function Have(itemID)
	-- include the bank, so crafting from the bank counts
	if C_Item and C_Item.GetItemCount then
		return C_Item.GetItemCount(itemID, true) or 0
	end
	if GetItemCount then
		return GetItemCount(itemID, true) or 0
	end
	return 0
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID) -- the name arrives later; ITEM_DATA_LOAD_RESULT refreshes the window
	end
	return name or ("item:" .. itemID)
end
ns.ItemName = ItemName

-- Ranks one scanned profession. Returns a list sorted by net cost per expected skill-up (cheapest first).
function ns.Rank(prof)
	local list = {}
	if not prof then
		return list
	end
	local bagsFree = ns.db.countBagsFree
	for _, r in ipairs(prof.recipes) do
		local chance = r.diff ~= nil and ns.SKILLUP_CHANCE[r.diff]
		if chance == nil and r.canSkillUp then
			chance = 0.5 -- the client says it can skill up but gave no color
		end
		if chance and chance > 0 then
			local cost, missingCost, unpriced = 0, 0, 0
			local craftableNow = true
			for _, g in ipairs(r.reagents) do
				local price = ns.Price(g.item)
				if price then
					cost = cost + price * g.qty
					missingCost = missingCost + price * max(0, g.qty - Have(g.item))
				else
					unpriced = unpriced + 1
				end
				if Have(g.item) < g.qty then
					craftableNow = false
				end
			end
			local outValue = 0
			local outPrice = r.out and ns.Price(r.out)
			if outPrice then
				outValue = outPrice * (r.outQty or 1) * ns.AH_CUT
			end
			local spend = bagsFree and missingCost or cost
			local net = spend - outValue
			list[#list + 1] = {
				recipe = r, chance = chance, cost = cost, missing = missingCost, outValue = outValue,
				net = net, perSkill = net / chance, unpriced = unpriced, craftableNow = craftableNow,
			}
		end
	end
	sort(list, function(a, b)
		if a.perSkill ~= b.perSkill then
			return a.perSkill < b.perSkill
		end
		return a.recipe.name < b.recipe.name
	end)
	return list
end

-- What to buy for `crafts` crafts of a ranked entry. Returns { { name, need, have, buy, cost } ... }, totalCost.
function ns.ShoppingList(entry, crafts)
	local rows, total = {}, 0
	if not entry then
		return rows, total
	end
	for _, g in ipairs(entry.recipe.reagents) do
		local need = g.qty * crafts
		local have = Have(g.item)
		local buy = max(0, need - have)
		local price = ns.Price(g.item)
		local cost = price and price * buy or nil
		if cost then
			total = total + cost
		end
		rows[#rows + 1] = { name = ItemName(g.item), need = need, have = have, buy = buy, cost = cost, item = g.item }
	end
	return rows, total
end
