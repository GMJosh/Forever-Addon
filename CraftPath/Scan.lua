-- CraftPath: reads your learned recipes from the open profession window
local addonName, ns = ...

local GetTime = GetTime
local sort = table.sort

local loggedFields = false
local lastScan = 0
local scanPending = false

local function KeysOf(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = tostring(k)
	end
	sort(keys)
	return table.concat(keys, ",")
end

-- Reagents that count toward the cost: the first reagent of each basic slot.
local function ReadReagents(schematic)
	local reagents = {}
	local slots = schematic and schematic.reagentSlotSchematics
	if not slots then
		return reagents
	end
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	for _, slot in ipairs(slots) do
		local first = slot.reagents and slot.reagents[1]
		local isBasic = basic == nil or slot.reagentType == nil or slot.reagentType == basic
		if isBasic and first and first.itemID and slot.quantityRequired and slot.quantityRequired > 0 then
			reagents[#reagents + 1] = { item = first.itemID, qty = slot.quantityRequired }
		end
	end
	return reagents
end

-- force = scan even if the profession window is not open (still needs it to have data)
function ns.ScanProfession(force)
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then
		ns.Print("This client has no recipe API I can use. Run /cpath debug and send me the log.")
		ns.Debug("Missing C_TradeSkillUI recipe functions")
		return
	end
	if InCombatLockdown() then
		return
	end
	if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then
		return
	end
	if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then
		return
	end
	local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
	local profName = info and ns.Num(info.professionID) and info.professionName
	if not profName or profName == "" then
		if force then
			ns.Print("Open a profession window first, then scan.")
		end
		return
	end

	local ids = T.GetAllRecipeIDs()
	if not ids or #ids == 0 then
		ns.Debug("Scan: no recipe IDs yet for", profName)
		return
	end

	local recipes = {}
	for _, id in ipairs(ids) do
		local r = T.GetRecipeInfo(id)
		if r and r.learned then
			local schematic = T.GetRecipeSchematic(id, false)
			if not loggedFields then
				loggedFields = true
				ns.Debug("recipeInfo fields:", KeysOf(r))
				if schematic then
					ns.Debug("schematic fields:", KeysOf(schematic))
				end
			end
			local reagents = ReadReagents(schematic)
			if #reagents > 0 then
				recipes[#recipes + 1] = {
					id = id,
					name = r.name or ("Recipe " .. id),
					diff = r.relativeDifficulty,
					canSkillUp = r.canSkillUp,
					out = schematic and schematic.outputItemID,
					outQty = schematic and schematic.quantityMin or 1,
					reagents = reagents,
				}
			end
		end
	end

	local skill = info.skillLevel and ns.Num(info.skillLevel) or 0
	local max = info.maxSkillLevel and ns.Num(info.maxSkillLevel) or 0
	ns.Char().profs[profName] = { skill = skill, max = max, recipes = recipes, scanned = time() }
	ns.currentProf = profName
	ns.Debug(string.format("Scanned %s: skill %d/%d, %d recipes", profName, skill, max, #recipes))
	if ns.UpdateWindow then
		ns.UpdateWindow()
	end
end

local function ScheduleScan()
	if scanPending then
		return
	end
	scanPending = true
	-- recipe data arrives a moment after the window opens, and the list event can fire many times
	C_Timer.After(0.7, function()
		scanPending = false
		lastScan = GetTime()
		ns.ScanProfession(false)
	end)
end

ns.On("TRADE_SKILL_SHOW", ScheduleScan)
ns.On("TRADE_SKILL_LIST_UPDATE", function()
	if GetTime() - lastScan > 3 then
		ScheduleScan()
	end
end)
