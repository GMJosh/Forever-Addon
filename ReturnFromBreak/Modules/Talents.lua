-- ReturnFromBreak: "Unspent Talents" section (Forever: one class trait tree, three talent trees, no hero talents)
local addonName, ns = ...

local C_ClassTalents = C_ClassTalents
local C_Traits = C_Traits
local format = string.format

local Clean = ns.Clean
local Color = ns.Color

local function ActiveConfig()
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
		return C_ClassTalents.GetActiveConfigID()
	end
end

-- Unspent talent points, or nil when the client won't say.
local function UnspentPoints()
	local configID = ActiveConfig()
	if configID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo then
		local info = C_Traits.GetConfigInfo(configID)
		local treeID = info and info.treeIDs and info.treeIDs[1]
		if treeID then
			local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
			if currencies and currencies[1] then
				return Clean(currencies[1].quantity) or 0
			end
		end
	end
	if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
		local _, class, spec = C_ClassTalents.HasUnspentTalentPoints()
		return (Clean(class) or 0) + (Clean(spec) or 0)
	end
	if UnitCharacterPoints then
		return Clean(UnitCharacterPoints("player")) or 0
	end
	return nil
end

local function Build()
	local rows = {}
	local n = UnspentPoints()
	if n == nil then
		rows[#rows + 1] = { kind = "empty", text = "Talent information is not available." }
		return rows
	end
	ns.Debug("Talents: unspent", n)
	if n == 0 then
		rows[#rows + 1] = { kind = "good", text = "All talent points spent." }
		return rows
	end
	rows[#rows + 1] = { kind = "text", text = format("Talents: %s", Color(ns.COLOR_BAD, n .. " unspent")), indent = 1 }
	rows[#rows + 1] = { kind = "empty", text = "Use the \"Open Talents\" button at the bottom of this window to spend them." }
	return rows
end

ns.Sections.talents = { Build = Build }
