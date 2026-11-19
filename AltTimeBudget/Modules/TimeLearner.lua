-- AltTimeBudget: learns how long chores really take you
--
-- HEURISTIC (documented here because it is a judgment call)
--
-- 1. Active play clock. Each character has char.activeSeconds, advanced every
--    ns.ACTIVE_TICK_SECONDS from GetTime() deltas while the player is not flagged AFK
--    (UnitIsAFK). Gaps longer than 4 ticks are capped, so a stalled timer cannot inflate it.
--    It only advances while that character is logged in, so every measurement counts only active
--    play on THAT character, even across sessions (accepted on Monday, finished on Thursday).
--
-- 2. Anchors mark when a chore "window" began, in active-clock seconds:
--      quest    QUEST_ACCEPTED for a quest ID linked to a chore (for "all" / "count" chores only
--               the first accept anchors, so the sample covers the whole chore)
--      instance entering a dungeon / raid / scenario (delve) anchors the matching Great Vault row
--               ("party" -> Activities, "raid" -> Raid, "scenario" -> World). A /reload or
--               relog inside an instance keeps the existing anchor.
--      manual   the "Start" button in the Current character section (any chore)
--    A newer anchor of the same key replaces the old one.
--
-- 3. Samples.
--      Normal chores: when the chore completes (detected, or manually checked off on this
--        character) and an anchor exists: minutes = (activeSeconds now - anchor) / 60.
--      Great Vault rows: learned per progress unit (one dungeon, one boss, one delve). When the
--        row's progress rises by k: perUnit = elapsed / k, then the anchor moves to "now" so the
--        next boss / run in the same instance chains from there.
--      No anchor -> no sample - the estimate stays on the preset (or override).
--
-- 4. Outliers. Let cap = default minutes x profile.outlierCap (default 3).
--      sample < ns.MIN_SAMPLE_MINUTES -> discarded (already done / instant turn-in)
--      sample > 2 x cap               -> discarded as stale (quest sat in the log for days)
--      sample > cap                   -> clamped to cap
--
-- 5. Smoothing. Exponential moving average: ema = alpha x sample + (1 - alpha) x ema, with
--    alpha = profile.emaAlpha (default 0.3). The first sample seeds the average. The estimate is
--    shown as "learned" once there is at least one sample. Overrides always win - reset clears it.
local addonName, ns = ...

local Debug = ns.Debug

local GetTime = GetTime
local UnitIsAFK = UnitIsAFK
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local GetServerTime = GetServerTime
local pairs = pairs
local ipairs = ipairs
local format = string.format
local min = math.min
local tostring = tostring
local select = select
local type = type
local wipe = wipe

local TimeLearner = {}
ns.TimeLearner = TimeLearner

local lastTick
local isAFK = false

local INSTANCE_TYPE_TO_ROW = {
	party = "Activities",
	raid = "Raid",
	scenario = "World",
}

local function G()
	return ns.db.global
end

local function ReadAFK()
	if not UnitIsAFK then return false end
	local v = UnitIsAFK("player")
	if ns.IsSecret(v) then
		return isAFK -- keep the last known state
	end
	return v and true or false
end

---------------------------------------------------------------------------
-- Active play clock
---------------------------------------------------------------------------
function TimeLearner:Flush()
	local char = ns.Roster:Current()
	local now = GetTime()
	if not lastTick then
		lastTick = now
		return
	end
	local delta = now - lastTick
	lastTick = now
	if not char or delta <= 0 then return end
	delta = min(delta, ns.ACTIVE_TICK_SECONDS * 4)
	if not isAFK then
		char.activeSeconds = (char.activeSeconds or 0) + delta
	end
end

function TimeLearner:Now()
	self:Flush()
	local char = ns.Roster:Current()
	return char and char.activeSeconds or 0
end

function TimeLearner:Enable()
	lastTick = GetTime()
	isAFK = ReadAFK()
	self:ValidateAnchors()
	local ATB = ns.ATB
	ATB:ScheduleRepeatingTimer(function() TimeLearner:Flush() end, ns.ACTIVE_TICK_SECONDS)
	-- AceEvent allows one handler per event per object, so the learner uses its own embed target.
	LibStub("AceEvent-3.0"):Embed(self)
	ns.RegisterEventSafe(self, "PLAYER_FLAGS_CHANGED", "OnFlagsChanged")
	ns.RegisterEventSafe(self, "QUEST_ACCEPTED", "OnQuestAccepted")
	ns.RegisterEventSafe(self, "PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function TimeLearner:OnFlagsChanged(_, unit)
	if unit ~= "player" then return end
	self:Flush() -- bank the time under the previous AFK state
	local was = isAFK
	isAFK = ReadAFK()
	if was ~= isAFK then
		Debug:Log("AFK state:", tostring(isAFK))
	end
end

---------------------------------------------------------------------------
-- Anchors
---------------------------------------------------------------------------
local function AnchorKey(chore)
	return chore.isVault and chore.learnKey or chore.id
end

-- detail (optional): the quest ID (source "quest") or instance ID (source "instance") that
-- triggered the anchor. It is stored on the anchor so it can be validated / shown later.
function TimeLearner:SetAnchor(key, source, detail)
	local char = ns.Roster:Current()
	if not char then return end
	char.anchors = char.anchors or {}
	local a = { at = self:Now(), source = source, server = GetServerTime() }
	if source == "quest" then
		a.questID = detail
	elseif source == "instance" then
		a.instanceID = detail
	end
	char.anchors[key] = a
	-- The number after "clock" is this character's active-play clock in seconds (anchor time),
	-- NOT a quest / instance ID.
	Debug:Log(format("Anchor set: %s %s%s (clock %.0fs)", tostring(key), tostring(source),
		detail ~= nil and (" " .. tostring(detail)) or "", a.at))
	ns.NotifyUpdate("anchor")
end

function TimeLearner:GetAnchor(chore)
	local char = ns.Roster:Current()
	return char and char.anchors and char.anchors[AnchorKey(chore)]
end

function TimeLearner:ClearAnchor(key)
	local char = ns.Roster:Current()
	if char and char.anchors then
		char.anchors[key] = nil
	end
end

-- "Start" button in the UI.
function TimeLearner:StartTimer(chore)
	self:SetAnchor(AnchorKey(chore), "manual")
end

function TimeLearner:StopTimer(chore)
	self:ClearAnchor(AnchorKey(chore))
	ns.NotifyUpdate("anchor")
end

-- Minutes since the chore's anchor (for "timer running" display), or nil.
function TimeLearner:ElapsedMinutes(chore)
	local a = self:GetAnchor(chore)
	if not a then return nil end
	return (self:Now() - a.at) / 60
end

function TimeLearner:OnQuestAccepted(_, questID)
	questID = ns.SafeNumber(questID)
	if not questID then return end
	local char = ns.Roster:Current()
	for _, chore in ipairs(ns.Chores:GetAll()) do
		local spec = chore.detect and ns.Chores:QuestSpec(chore, char)
		if spec then
			for _, id in ipairs(spec.ids) do
				if id == questID then
					-- Multi-quest chores ("all" / "count") time the whole chore from the FIRST accept,
					-- so later accepts must not move the anchor forward.
					local multi = ns.Chores:Needed(spec) > 1
					if char and ns.Roster:IsDone(char, chore) then
						-- Already done this week: an anchor here would never be consumed this week and
						-- would turn into a bogus sample after the reset.
						Debug:Log("Quest", questID, "accepted for", chore.id, "- already done this week, no anchor")
					elseif not (multi and char and char.anchors and char.anchors[chore.id]) then
						self:SetAnchor(chore.id, "quest", questID)
					end
					break
				end
			end
		end
	end
end

function TimeLearner:OnEnteringWorld(_, isInitialLogin, isReloadingUi)
	local inInstance, instanceType = IsInInstance()
	if ns.IsSecret(inInstance) or ns.IsSecret(instanceType) or not inInstance then return end
	local row = INSTANCE_TYPE_TO_ROW[instanceType]
	if not row then return end
	local key = "vault:" .. row
	local char = ns.Roster:Current()
	if (isReloadingUi or isInitialLogin) and char and char.anchors and char.anchors[key] then
		return -- /reload or relog inside the instance: keep the original anchor
	end
	local instanceID
	if GetInstanceInfo then
		instanceID = ns.SafeNumber((select(8, GetInstanceInfo())))
	end
	self:SetAnchor(key, "instance", instanceID)
end

-- Load-time safety net: drops quest anchors whose stored quest ID is not in the owning chore's
-- resolved ID list (per alt for profession chores). Anchors from before questID was stored
-- carry no ID and are kept (QUEST_ACCEPTED matching was already exact).
function TimeLearner:ValidateAnchors()
	local dropped = 0
	for _, char in pairs(G().chars) do
		if type(char) == "table" and type(char.anchors) == "table" then
			for key, a in pairs(char.anchors) do
				if type(a) ~= "table" or type(a.at) ~= "number" then
					char.anchors[key] = nil
					dropped = dropped + 1
					Debug:Log("Anchor dropped (malformed):", ns.CharLabel(char), tostring(key))
				elseif a.source == "quest" and a.questID ~= nil then
					local chore = ns.Chores:Get(key)
					local spec = chore and ns.Chores:QuestSpec(chore, char)
					local ok = false
					if spec then
						for _, id in ipairs(spec.ids) do
							if id == a.questID then ok = true break end
						end
					end
					if not ok then
						char.anchors[key] = nil
						dropped = dropped + 1
						Debug:Log("Anchor dropped (quest", tostring(a.questID), "not in chore list):",
							ns.CharLabel(char), tostring(key))
					end
				end
			end
		end
	end
	if dropped > 0 then
		Debug:Log("ValidateAnchors:", dropped, "anchor(s) dropped")
	end
	return dropped
end

---------------------------------------------------------------------------
-- Learned averages
---------------------------------------------------------------------------
function TimeLearner:Get(key)
	return G().learned[key]
end

-- Returns the minutes actually recorded (after clamping), or nil if discarded.
function TimeLearner:AddSample(key, minutes, defaultMinutes, label)
	local p = ns.db.profile
	if minutes < ns.MIN_SAMPLE_MINUTES then
		Debug:Log(format("Sample discarded (too short): %s %.1fm", label or key, minutes))
		return nil
	end
	local cap = (defaultMinutes or 20) * (p.outlierCap or 3)
	if minutes > cap * 2 then
		Debug:Log(format("Sample discarded (stale, > %.0fm): %s %.1fm", cap * 2, label or key, minutes))
		return nil
	end
	if minutes > cap then
		Debug:Log(format("Sample clamped %.1fm -> %.1fm: %s", minutes, cap, label or key))
		minutes = cap
	end
	local rec = G().learned[key]
	if not rec or not rec.ema or (rec.n or 0) < 1 then
		rec = { ema = minutes, n = 1 }
		G().learned[key] = rec
	else
		local alpha = p.emaAlpha or 0.3
		rec.ema = alpha * minutes + (1 - alpha) * rec.ema
		rec.n = rec.n + 1
	end
	rec.last = minutes
	rec.at = GetServerTime()
	Debug:Log(format("Learned %s: sample %.1fm -> avg %.1fm (n=%d)", label or key, minutes, rec.ema, rec.n))
	ns.NotifyUpdate("learned")
	return minutes
end

-- Normal (non-vault) chore completed on the current character.
function TimeLearner:OnChoreCompleted(char, chore, how)
	if chore.isVault then return end
	if not char or char.guid ~= ns.Roster:CurrentGUID() then return end
	local anchor = char.anchors and char.anchors[chore.id]
	if not anchor then
		Debug:Log("No anchor for", chore.id, "(" .. tostring(how) .. ") - keeping estimate")
		return
	end
	local minutes = (self:Now() - anchor.at) / 60
	char.anchors[chore.id] = nil
	Debug:Log(format("Chore completed: %s (%s), anchor %s%s, %.1fm active", chore.id, tostring(how),
		tostring(anchor.source), anchor.questID and (" " .. anchor.questID) or "", minutes))
	local recorded = self:AddSample(chore.id, minutes, ns.Chores:DefaultUnitMinutes(chore), chore.name)
	if recorded then
		ns.Roster:StateFor(char, chore).measured[chore.id] = recorded
	end
end

-- Great Vault row progress rose by `delta` units on the current character.
function TimeLearner:OnVaultProgress(char, row, delta)
	local key = "vault:" .. row
	local anchor = char.anchors and char.anchors[key]
	if not anchor or delta <= 0 then
		Debug:Log("Vault progress", row, "+" .. delta, "with no anchor - no sample")
		return
	end
	local now = self:Now()
	local perUnit = (now - anchor.at) / 60 / delta
	-- Chain: the next unit in this instance is measured from now.
	anchor.at = now
	local default = 20
	for _, chore in ipairs(ns.Chores:GetAll()) do
		if chore.learnKey == key then
			default = ns.Chores:DefaultUnitMinutes(chore)
			break
		end
	end
	self:AddSample(key, perUnit, default, "Great Vault " .. row .. " (per unit)")
end

function TimeLearner:Reset(key)
	G().learned[key] = nil
	Debug:Log("Learned time reset:", key)
	ns.NotifyUpdate("learned")
end

function TimeLearner:ResetAll()
	wipe(G().learned)
	Debug:Log("All learned times reset")
	ns.NotifyUpdate("learned")
end
