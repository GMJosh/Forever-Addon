-- StreamBingo: in-game event detectors
-- Every detector ends in ns.FireSquare(key, extra). No combat log (CLEU is unavailable
-- in 12.0). Every value that could be secret goes through ns.SafeNumber/SafeString/SafeBool
-- before it is compared or used in math.
local addonName, ns = ...

local Debug = ns.Debug
local Detectors = ns.SB:NewModule("Detectors", "AceEvent-3.0")
ns.Detectors = Detectors

local SafeNumber = ns.SafeNumber
local SafeString = ns.SafeString
local SafeBool = ns.SafeBool

local GetTime = GetTime
local GetMoney = GetMoney
local IsInInstance = IsInInstance
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local UnitGUID = UnitGUID
local UnitName = UnitName
local C_Timer = C_Timer
local floor = math.floor
local pcall = pcall
local ipairs = ipairs
local type = type
local tostring = tostring
local select = select

local COPPER_PER_GOLD = 10000
local LOOT_DEDUPE_SECONDS = 5
local VAULT_DEBOUNCE_SECONDS = 60
local REPAIR_PENDING_TIMEOUT = 5
local MOUNT_SOURCE_DROP = 1 -- BATTLE_PET_SOURCE_1 ("Drop"), used by the Mount Journal source filter

local QUALITY_EPIC = (Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4
local QUALITY_HEIRLOOM = (Enum and Enum.ItemQuality and Enum.ItemQuality.Heirloom) or 7
local QUALITY_TOKEN = (Enum and Enum.ItemQuality and Enum.ItemQuality.WoWToken) or 8

---------------------------------------------------------------------------
-- Runtime state (not saved; session-level data lives in ns.db.session)
---------------------------------------------------------------------------
local state = {
	inEncounter = false,
	encounterID = nil,
	keyActive = false,
	keyDeathsFired = false,
	lastGroupCount = 0,
	merchantOpen = false,
	repairCost = nil,      -- copper, cached while merchant is open
	moneyAtMerchant = nil, -- copper
	repairPending = nil,   -- { cost = copper, guild = bool, t = GetTime() }
	recentLoot = {},       -- itemString -> GetTime()
	lastVaultFire = 0,
}

-- No auraInstanceID caches exist in this addon. This hook is where they would be
-- invalidated (auraInstanceIDs re-randomize on ENCOUNTER_START / CHALLENGE_MODE_START
-- and at PvP boundaries in 12.0.5).
local function InvalidateAuraCaches(reason)
	Debug:Log("Aura caches invalidated (none held):", reason)
end

local function Opt(name)
	return ns.db.thresholds[name]
end

local function EncounterInProgressAPI()
	if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
		return SafeBool(C_InstanceEncounter.IsEncounterInProgress()) or false
	end
	return false
end

local function GetInstanceType()
	local inInstance, instanceType = IsInInstance()
	if not SafeBool(inInstance) then
		return nil
	end
	return SafeString(instanceType)
end

local function IsPvEInstance()
	local t = GetInstanceType()
	return t == "party" or t == "raid" or t == "scenario"
end

-- Raid-extra squares are optionally restricted to raid instances.
local function RaidSquaresAllowed()
	if not Opt("raidSquaresRaidOnly") then
		return IsPvEInstance()
	end
	return GetInstanceType() == "raid"
end

local function IsKeyActive()
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
		local active = SafeBool(C_ChallengeMode.IsChallengeModeActive())
		if active ~= nil then
			return active
		end
	end
	return state.keyActive
end

local function GetGroupCount()
	return SafeNumber(GetNumGroupMembers()) or 0
end

local function InstanceDifficultyByte()
	if GetInstanceInfo then
		local difficultyID = select(3, GetInstanceInfo())
		return SafeNumber(difficultyID) or 0
	end
	return 0
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Detectors:OnEnable()
	local R = ns.RegisterEventSafe
	R(self, "PLAYER_ENTERING_WORLD")
	R(self, "PLAYER_DEAD")
	R(self, "ENCOUNTER_START")
	R(self, "ENCOUNTER_END")
	R(self, "CHALLENGE_MODE_START")
	R(self, "CHALLENGE_MODE_COMPLETED")
	R(self, "CHALLENGE_MODE_RESET")
	R(self, "CHALLENGE_MODE_DEATH_COUNT_UPDATED")
	R(self, "GROUP_ROSTER_UPDATE")
	R(self, "NEW_MOUNT_ADDED")
	R(self, "MERCHANT_SHOW")
	R(self, "MERCHANT_CLOSED")
	R(self, "UPDATE_INVENTORY_DURABILITY")
	R(self, "PLAYER_MONEY")
	R(self, "SHOW_LOOT_TOAST")
	R(self, "LOOT_ITEM_ROLL_WON")
	R(self, "CHAT_MSG_LOOT")
	R(self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	R(self, "PLAYER_LEVEL_UP")
	R(self, "ACHIEVEMENT_EARNED")

	-- Post-hook on the global RepairAllItems. hooksecurefunc never taints the caller
	-- (Blizzard's MerchantFrame / StaticPopup call it), and it sees every caller that
	-- goes through the global, including auto-repair addons.
	if type(RepairAllItems) == "function" and not self.repairHooked then
		hooksecurefunc("RepairAllItems", function(guildBankRepair)
			Detectors:OnRepairAllItems(guildBankRepair)
		end)
		self.repairHooked = true
	else
		Debug:Log("RepairAllItems not found; repair detection uses PLAYER_MONEY delta only")
	end
	Debug:Log("Detectors enabled")
end

function Detectors:OnSessionReset()
	state.keyDeathsFired = false
	state.recentLoot = {}
	state.lastVaultFire = 0
end

function Detectors:PLAYER_ENTERING_WORLD(event, isInitialLogin, isReloadingUi)
	state.inEncounter = EncounterInProgressAPI()
	state.keyActive = IsKeyActive()
	state.lastGroupCount = GetGroupCount()
	-- After a /reload mid-key, don't re-fire Death Fest for deaths that already happened.
	state.keyDeathsFired = false
	if state.keyActive and C_ChallengeMode and C_ChallengeMode.GetDeathCount then
		local numDeaths = SafeNumber((C_ChallengeMode.GetDeathCount()))
		if numDeaths and numDeaths >= Opt("keyDeaths") then
			state.keyDeathsFired = true
		end
	end
	Debug:Log("PEW", "instance=" .. tostring(GetInstanceType()), "encounter=" .. tostring(state.inEncounter),
		"key=" .. tostring(state.keyActive), "group=" .. state.lastGroupCount)
end

---------------------------------------------------------------------------
-- Deaths: died to trash, fall damage death
---------------------------------------------------------------------------

local function EncounterActive()
	if state.inEncounter then
		return true
	end
	return EncounterInProgressAPI()
end

-- Reads the most recent death recap and returns true if the killing blow
-- was environmental falling damage. Field names come from Blizzard_DeathRecap.lua
-- (DeathRecapEventInfo is undocumented in the generated docs).
local function CheckFallDeath()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
		Debug:Log("FallDeath: C_DeathRecap unavailable")
		return
	end
	if C_DeathRecap.HasRecapEvents and not SafeBool(C_DeathRecap.HasRecapEvents()) then
		Debug:Log("FallDeath: no recap events")
		return
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok or type(events) ~= "table" or #events == 0 then
		Debug:Log("FallDeath: recap read failed or empty", ok)
		return
	end

	-- Killing blow = newest timestamp. If timestamps are secret, fall back to the
	-- last entry in the list.
	local killing, newest = nil, nil
	for _, e in ipairs(events) do
		local ts = SafeNumber(e.timestamp)
		if ts and (not newest or ts > newest) then
			newest = ts
			killing = e
		end
	end
	killing = killing or events[#events]

	local evName = SafeString(killing.event)
	local envType = SafeString(killing.environmentalType)
	Debug:Log("FallDeath: killing blow event=" .. tostring(evName), "env=" .. tostring(envType))
	if evName == "ENVIRONMENTAL_DAMAGE" and envType and envType:upper() == "FALLING" then
		ns.FireSquare("fall_death", 0)
	end
end

function Detectors:PLAYER_DEAD()
	local instanceType = GetInstanceType()
	local encounter = EncounterActive()
	Debug:Log("PLAYER_DEAD", "instance=" .. tostring(instanceType), "encounter=" .. tostring(encounter))

	if IsPvEInstance() and not encounter then
		ns.FireSquare("trash_death", InstanceDifficultyByte())
	end

	if ns.IsDetectorEnabled("fall_death") then
		-- Recap is populated by the time the death popup shows; give it a moment.
		C_Timer.After(0.5, CheckFallDeath)
	end
end

---------------------------------------------------------------------------
-- Encounters: wipe, kill, first-pull kill, wipe under X%
---------------------------------------------------------------------------

function Detectors:ENCOUNTER_START(event, encounterID, encounterName, difficultyID, groupSize)
	state.inEncounter = true
	state.encounterID = SafeNumber(encounterID)
	InvalidateAuraCaches("ENCOUNTER_START")
	Debug:Log("ENCOUNTER_START", encounterID, encounterName, "diff=" .. tostring(difficultyID))
end

-- Returns the highest remaining boss HP (0-100 scale) from ENCOUNTER_END's
-- encounterUnitStatus, or nil if unusable. The field scale is undocumented:
-- if every value is <= 1 we treat it as a 0-1 fraction.
local function GetWipeRemainingPercent(unitStatus)
	if type(unitStatus) ~= "table" or (issecrettable and issecrettable(unitStatus)) then
		return nil
	end
	local highest, count, allFractional = nil, 0, true
	for _, info in ipairs(unitStatus) do
		local pct = type(info) == "table" and SafeNumber(info.remainingHealthPercent)
		if pct then
			count = count + 1
			if pct > 1 then
				allFractional = false
			end
			if not highest or pct > highest then
				highest = pct
			end
			Debug:Log("  unit", SafeString(info.creatureName) or "?", "remainingHealthPercent=" .. pct)
		end
	end
	if count == 0 then
		return nil
	end
	if allFractional then
		highest = highest * 100
	end
	return highest
end

function Detectors:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success, encounterUnitStatus)
	state.inEncounter = false
	state.encounterID = nil

	local id = SafeNumber(encounterID)
	local diff = SafeNumber(difficultyID) or 0
	local ok = SafeNumber(success)
	Debug:Log("ENCOUNTER_END", tostring(id), encounterName, "diff=" .. diff, "success=" .. tostring(ok))
	if not id or ok == nil then
		return
	end

	local session = ns.db.session
	local encKey = id .. ":" .. diff

	if ok == 1 then
		if RaidSquaresAllowed() then
			ns.FireSquare("boss_kill", diff)
			if not session.wipedEncounters[encKey] then
				ns.FireSquare("first_pull_kill", diff)
			end
		end
	elseif ok == 0 then
		session.wipedEncounters[encKey] = true
		if IsPvEInstance() then
			ns.FireSquare("boss_wipe", diff)
		end
		if RaidSquaresAllowed() and ns.IsDetectorEnabled("wipe_low") then
			local pct = GetWipeRemainingPercent(encounterUnitStatus)
			Debug:Log("Wipe remaining HP% =", tostring(pct), "threshold=" .. Opt("wipePercent"))
			if pct and pct > 0 and pct < Opt("wipePercent") then
				ns.FireSquare("wipe_low", floor(pct))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Mythic+
---------------------------------------------------------------------------

function Detectors:CHALLENGE_MODE_START(event, mapID)
	state.keyActive = true
	state.keyDeathsFired = false
	state.lastGroupCount = GetGroupCount()
	InvalidateAuraCaches("CHALLENGE_MODE_START")
	Debug:Log("CHALLENGE_MODE_START map=" .. tostring(mapID), "group=" .. state.lastGroupCount)
end

function Detectors:CHALLENGE_MODE_RESET(event, mapID)
	state.keyActive = false
	Debug:Log("CHALLENGE_MODE_RESET map=" .. tostring(mapID))
end

function Detectors:CHALLENGE_MODE_COMPLETED()
	state.keyActive = false
	if not (C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo) then
		Debug:Log("CHALLENGE_MODE_COMPLETED: GetChallengeCompletionInfo unavailable")
		return
	end
	local info = C_ChallengeMode.GetChallengeCompletionInfo()
	if type(info) ~= "table" then
		Debug:Log("CHALLENGE_MODE_COMPLETED: no info")
		return
	end
	local level = SafeNumber(info.level) or 0
	local onTime = SafeBool(info.onTime)
	local upgrades = SafeNumber(info.keystoneUpgradeLevels) or 0
	local practice = SafeBool(info.practiceRun)
	Debug:Log("CHALLENGE_MODE_COMPLETED level=" .. level, "onTime=" .. tostring(onTime),
		"upgrades=" .. upgrades, "practice=" .. tostring(practice))

	if practice then
		return
	end
	if onTime == true then
		ns.FireSquare("key_timed", level)
	elseif onTime == false then
		ns.FireSquare("key_depleted", level)
	end
	if upgrades >= 2 then
		ns.FireSquare("key_upgrade", upgrades)
	end
end

function Detectors:CHALLENGE_MODE_DEATH_COUNT_UPDATED()
	if state.keyDeathsFired or not (C_ChallengeMode and C_ChallengeMode.GetDeathCount) then
		return
	end
	local numDeaths = SafeNumber((C_ChallengeMode.GetDeathCount()))
	Debug:Log("Key deaths =", tostring(numDeaths))
	if numDeaths and numDeaths >= Opt("keyDeaths") then
		state.keyDeathsFired = true
		ns.FireSquare("key_deaths", numDeaths)
	end
end

function Detectors:GROUP_ROSTER_UPDATE()
	local count = GetGroupCount()
	local previous = state.lastGroupCount
	state.lastGroupCount = count
	if not IsKeyActive() then
		return
	end
	-- count == 0 / not in group means the player left, not a party member.
	if count > 0 and IsInGroup() and count < previous then
		Debug:Log("Party member left during key", previous .. " -> " .. count)
		ns.FireSquare("party_left", count)
	end
end

---------------------------------------------------------------------------
-- Mounts
---------------------------------------------------------------------------

function Detectors:NEW_MOUNT_ADDED(event, mountID)
	local id = SafeNumber(mountID)
	local name, sourceType
	if id and C_MountJournal and C_MountJournal.GetMountInfoByID then
		local n, _, _, _, _, src = C_MountJournal.GetMountInfoByID(id)
		name = SafeString(n)
		sourceType = SafeNumber(src)
	end
	Debug:Log("NEW_MOUNT_ADDED id=" .. tostring(id), tostring(name), "sourceType=" .. tostring(sourceType))
	if Opt("mountDropOnly") and sourceType ~= MOUNT_SOURCE_DROP then
		return
	end
	ns.FireSquare("mount_drop", sourceType or 0)
end

---------------------------------------------------------------------------
-- Repair bill
-- Primary: hooksecurefunc("RepairAllItems") marks a pending repair with the cost
-- captured while the merchant was open; it is confirmed when the repair cost drops
-- (UPDATE_INVENTORY_DURABILITY / PLAYER_MONEY). Fallback: a PLAYER_MONEY drop at a
-- merchant that exactly equals the cached repair cost.
---------------------------------------------------------------------------

local function QueryRepairCost()
	if not GetRepairAllCost then return nil end
	local cost, canRepair = GetRepairAllCost()
	cost = SafeNumber(cost)
	return cost
end

local function FinishRepair(cost, guild, source)
	state.repairPending = nil
	local gold = (cost or 0) / COPPER_PER_GOLD
	Debug:Log("Repair confirmed via " .. source, "cost=" .. floor(gold) .. "g", "guild=" .. tostring(guild))
	if gold >= Opt("repairGold") then
		ns.FireSquare("big_repair", floor(gold / 100))
	end
	state.repairCost = QueryRepairCost()
	state.moneyAtMerchant = SafeNumber(GetMoney())
end

function Detectors:MERCHANT_SHOW()
	state.merchantOpen = true
	state.repairCost = QueryRepairCost()
	state.moneyAtMerchant = SafeNumber(GetMoney())
	Debug:Log("MERCHANT_SHOW repairCost=" .. tostring(state.repairCost))
end

function Detectors:MERCHANT_CLOSED()
	state.merchantOpen = false
end

function Detectors:OnRepairAllItems(guildBankRepair)
	local cost = state.repairCost
	if not cost or cost <= 0 then
		cost = QueryRepairCost()
	end
	Debug:Log("RepairAllItems hook cost=" .. tostring(cost), "guild=" .. tostring(guildBankRepair))
	if not cost or cost <= 0 then
		return
	end
	state.repairPending = { cost = cost, guild = guildBankRepair and true or false, t = GetTime() }
end

local function CheckRepairConfirmed(source)
	local pending = state.repairPending
	if not pending then return false end
	if GetTime() - pending.t > REPAIR_PENDING_TIMEOUT then
		Debug:Log("Repair pending timed out")
		state.repairPending = nil
		return false
	end
	local now = QueryRepairCost()
	if now and now < pending.cost then
		FinishRepair(pending.cost, pending.guild, source)
		return true
	end
	return false
end

function Detectors:UPDATE_INVENTORY_DURABILITY()
	if CheckRepairConfirmed("durability") then return end
	if state.merchantOpen and not state.repairPending then
		state.repairCost = QueryRepairCost()
	end
end

function Detectors:PLAYER_MONEY()
	if CheckRepairConfirmed("money") then return end
	if not state.merchantOpen then return end
	local money = SafeNumber(GetMoney())
	local before = state.moneyAtMerchant
	state.moneyAtMerchant = money
	if not (money and before and state.repairCost and state.repairCost > 0) then
		return
	end
	-- Fallback for callers that bypass the hooked global: exact match on the bill.
	if before - money == state.repairCost then
		FinishRepair(state.repairCost, false, "money-delta")
	end
end

---------------------------------------------------------------------------
-- Epic loot
-- SHOW_LOOT_TOAST and LOOT_ITEM_ROLL_WON give an item link for the player directly.
-- CHAT_MSG_LOOT is a fallback for plain mob/chest loot: we only use the looter GUID /
-- name and the embedded |Hitem: link, never the localized sentence.
---------------------------------------------------------------------------

local function ItemStringFromLink(link)
	link = SafeString(link)
	if not link then return nil end
	return link:match("|H(item:[^|]+)|h") or (link:match("^item:") and link) or nil
end

local function CheckLootQuality(itemString, source, attempt)
	if not (C_Item and C_Item.GetItemQualityByID) then return end
	local quality = SafeNumber(C_Item.GetItemQualityByID(itemString))
	if not quality then
		if attempt < 3 then
			C_Timer.After(1, function() CheckLootQuality(itemString, source, attempt + 1) end)
		else
			Debug:Log("Loot quality unavailable", itemString)
		end
		return
	end
	Debug:Log("Loot via " .. source, itemString, "quality=" .. quality)
	if quality >= QUALITY_EPIC and quality ~= QUALITY_HEIRLOOM and quality ~= QUALITY_TOKEN then
		ns.FireSquare("epic_loot", quality)
	end
end

local function HandleLoot(link, source)
	if not ns.IsDetectorEnabled("epic_loot") then return end
	local itemString = ItemStringFromLink(link)
	if not itemString then return end
	local now = GetTime()
	local last = state.recentLoot[itemString]
	if last and now - last < LOOT_DEDUPE_SECONDS then
		return
	end
	state.recentLoot[itemString] = now
	CheckLootQuality(itemString, source, 1)
end

function Detectors:SHOW_LOOT_TOAST(event, typeIdentifier, itemLink)
	if SafeString(typeIdentifier) == "item" then
		HandleLoot(itemLink, "toast")
	end
end

function Detectors:LOOT_ITEM_ROLL_WON(event, itemLink)
	HandleLoot(itemLink, "rollwon")
end

function Detectors:CHAT_MSG_LOOT(event, text, playerName, _, _, _, _, _, _, _, _, _, guid)
	text = SafeString(text)
	if not text then return end -- secret during chat messaging lockdown
	local mine = false
	local g = SafeString(guid)
	local myGUID = SafeString(UnitGUID("player"))
	if g and myGUID and g == myGUID then
		mine = true
	else
		local who = SafeString(playerName)
		local me = SafeString(UnitName("player"))
		if who and me and Ambiguate(who, "short") == me then
			mine = true
		end
	end
	if mine then
		HandleLoot(text, "chat")
	end
end

---------------------------------------------------------------------------
-- Great Vault, level up, achievement
---------------------------------------------------------------------------

function Detectors:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(event, interactionType)
	local t = SafeNumber(interactionType)
	local vault = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.WeeklyRewards
	if t and vault and t == vault then
		local now = GetTime()
		if now - state.lastVaultFire < VAULT_DEBOUNCE_SECONDS then
			return
		end
		state.lastVaultFire = now
		ns.FireSquare("great_vault", 0)
	end
end

function Detectors:PLAYER_LEVEL_UP(event, level)
	ns.FireSquare("level_up", SafeNumber(level) or 0)
end

function Detectors:ACHIEVEMENT_EARNED(event, achievementID, alreadyEarned)
	Debug:Log("ACHIEVEMENT_EARNED", tostring(achievementID), "alreadyEarned=" .. tostring(alreadyEarned))
	if SafeBool(alreadyEarned) then
		return
	end
	ns.FireSquare("achievement", 0)
end
