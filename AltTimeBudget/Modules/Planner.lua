-- AltTimeBudget: weekly planner
--
-- Inputs: weekly hours budget, non-excluded non-bank alts (priority > 0), eligible chores (enabled,
-- allowed for the alt's role, level met, not done this week) and their estimated minutes.
--
-- ROLES: main / alt get every chore, profession alts only chores whose allowed roles include
-- "profession", bank alts get nothing and are left out of the plan AND the skip list entirely.
--
--   score = value points x alt priority
--   rate  = score / estimated minutes
--
-- ALGORITHM (greedy with per-alt overhead)
-- Using an alt costs a one-time overhead (profile.overheadMinutes: log in, fly to the hub). A
-- plain greedy-by-rate would either ignore that cost or charge it to the first chore, so the
-- planner compares two kinds of moves each step and commits the one with the best rate:
--
--   a) Next chore on an alt ALREADY in the plan: rate = score / minutes (overhead already paid).
--   b) Bring in a NEW alt as a bundle: walk that alt's chores best-rate-first (respecting slot
--      prerequisites, skipping ones that don't fit), and keep the prefix with the best AVERAGE
--      rate including the overhead: sum(score) / (overhead + sum(minutes)). A chore is only part
--      of the entry bundle if it raises that average - the rest stay available as type (a) moves.
--
-- This repeats until nothing fits. An alt whose best bundle never beats the alternatives falls
-- out as "skip this alt", with a reason: its best bundle rate is below the plan's cutoff rate,
-- nothing it has fits the time left, or the budget filled up first.
--
-- Account-wide chores are attached to one alt: the highest-priority included alt whose role and
-- level allow the chore (ties go to the current character). Bank alts never receive them.
--
-- Partially completed "all" / "count" quest chores are planned at their FULL estimate (see
-- Chores:EstimateMinutes); the progress ("1/2") is only shown next to the item.
local addonName, ns = ...

local Debug = ns.Debug

local pairs = pairs
local ipairs = ipairs
local format = string.format
local sort = table.sort
local max = math.max
local min = math.min

local Planner = {}
ns.Planner = Planner

local function G()
	return ns.db.global
end

local function P()
	return ns.db.profile
end

local function Priority(char)
	local p = char.priority or 0
	if p < 0 then p = 0 end
	return p
end

local function IsBank(char)
	return ns.Roster:Role(char) == "bank"
end

---------------------------------------------------------------------------
-- Spent time / value (completed chores)
---------------------------------------------------------------------------
local function DoneMinutes(state, chore)
	local measured = state.measured[chore.id]
	if measured then return measured end
	return (ns.Chores:EstimateMinutes(chore))
end

-- Returns totalMinutes, perGuid[guid] = minutes, completedCount, valueEarned, perGuidCount
function Planner:Spent()
	local total, count, value = 0, 0, 0
	local perGuid, perGuidCount = {}, {}
	local chores = ns.Chores:GetAll()
	local chars = ns.Roster:GetAll()
	for _, char in ipairs(chars) do
		local m, n = 0, 0
		for _, chore in ipairs(chores) do
			-- Only chores the alt's role allows count (bank alts count nothing).
			if chore.scope == "char" and ns.Roster:RoleAllows(char, chore) then
				local done = ns.Roster:IsDone(char, chore)
				if done then
					local state = ns.Roster:StateFor(char, chore)
					m = m + DoneMinutes(state, chore)
					n = n + 1
					value = value + chore.value * Priority(char)
				end
			end
		end
		perGuid[char.guid] = m
		perGuidCount[char.guid] = n
		total = total + m
		count = count + n
	end
	local account = ns.Roster:AccountWeek()
	for _, chore in ipairs(chores) do
		if chore.scope == "account" then
			local m = account.manual[chore.id]
			local done = (m ~= nil and m) or (m == nil and account.detected[chore.id] ~= nil)
			if done then
				total = total + DoneMinutes(account, chore)
				count = count + 1
				value = value + chore.value
			end
		end
	end
	return total, perGuid, count, value, perGuidCount
end

---------------------------------------------------------------------------
-- Candidates
---------------------------------------------------------------------------
local function MakeItem(char, chore)
	local minutes, source = ns.Chores:EstimateMinutes(chore)
	local score = chore.value * Priority(char)
	return {
		chore = chore,
		char = char,
		guid = char.guid,
		name = ns.Chores:DisplayName(chore, char),      -- "Alchemy weekly" for profession chores
		progress = ns.Detection:ProgressText(char, chore), -- "1/2" for all / count chores, else nil
		minutes = minutes,
		source = source,
		score = score,
		rate = minutes > 0 and score / minutes or 0,
	}
end

-- Returns orderedGuids, candidates[guid] = { items }, info[guid] = { char, reason, eligible, done }
local function BuildCandidates()
	local chars = ns.Roster:GetAll()
	local chores = ns.Chores:GetAll()
	local currentGUID = ns.Roster:CurrentGUID()
	local order, cands, info = {}, {}, {}

	for _, char in ipairs(chars) do
		local inf = { char = char, eligible = 0, done = 0 }
		info[char.guid] = inf
		if IsBank(char) then
			inf.reason, inf.bank = "bank character", true
		elseif char.excluded then
			inf.reason = "excluded"
		elseif Priority(char) <= 0 then
			inf.reason = "priority is 0"
		else
			order[#order + 1] = char.guid
			local list = {}
			for _, chore in ipairs(chores) do
				if chore.scope == "char" and ns.Roster:IsEligible(char, chore) then
					inf.eligible = inf.eligible + 1
					if ns.Roster:IsDone(char, chore) then
						inf.done = inf.done + 1
					else
						list[#list + 1] = MakeItem(char, chore)
					end
				end
			end
			cands[char.guid] = list
		end
	end

	-- Account-wide chores: attach to the best included eligible alt.
	for _, chore in ipairs(chores) do
		if chore.scope == "account" and chore.enabled then
			local account = ns.Roster:AccountWeek()
			local m = account.manual[chore.id]
			local done = (m ~= nil and m) or (m == nil and account.detected[chore.id] ~= nil)
			local best
			for _, guid in ipairs(order) do
				local char = info[guid].char
				if ns.Roster:IsEligible(char, chore) then
					if not best
						or Priority(char) > Priority(best)
						or (Priority(char) == Priority(best) and guid == currentGUID) then
						best = char
					end
				end
			end
			if best then
				local inf = info[best.guid]
				inf.eligible = inf.eligible + 1
				if done then
					inf.done = inf.done + 1
				else
					local list = cands[best.guid]
					list[#list + 1] = MakeItem(best, chore)
				end
			end
		end
	end

	return order, cands, info
end

-- Is the prerequisite of `item` satisfied? `pending` = set of chore ids still to do for the alt,
-- `taken` = set of chore ids already scheduled in this plan for the alt.
local function Ready(item, pending, taken)
	local req = item.chore.requires
	if not req then return true end
	return not pending[req] or taken[req]
end

local function PendingSet(list)
	local set = {}
	for _, item in ipairs(list) do
		set[item.chore.id] = true
	end
	return set
end

-- Best entry bundle for an alt not yet in the plan.
-- Returns items, averageRate, totalMinutesInclOverhead (or nil if nothing fits).
local function BestBundle(list, takenIds, overhead, remaining)
	local pending = PendingSet(list)
	local taken = {}
	for id in pairs(takenIds) do taken[id] = true end
	local used = {}
	local seq = {}
	local sumM, sumS = overhead, 0
	local bestRate, bestCount, bestM = nil, 0, 0
	while true do
		local pick
		for _, item in ipairs(list) do
			if not used[item] and not taken[item.chore.id] and Ready(item, pending, taken)
				and sumM + item.minutes <= remaining
				and (not pick or item.rate > pick.rate) then
				pick = item
			end
		end
		if not pick then break end
		used[pick] = true
		taken[pick.chore.id] = true
		seq[#seq + 1] = pick
		sumM = sumM + pick.minutes
		sumS = sumS + pick.score
		local rate = sumS / sumM
		if not bestRate or rate > bestRate then
			bestRate, bestCount, bestM = rate, #seq, sumM
		end
	end
	if bestCount == 0 then return nil end
	local items = {}
	for i = 1, bestCount do items[i] = seq[i] end
	return items, bestRate, bestM
end

-- Best single next chore for an alt already in the plan.
local function BestSingle(list, takenIds, remaining)
	local pending = PendingSet(list)
	local pick
	for _, item in ipairs(list) do
		if not takenIds[item.chore.id] and Ready(item, pending, takenIds)
			and item.minutes <= remaining
			and (not pick or item.rate > pick.rate) then
			pick = item
		end
	end
	return pick
end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
function Planner:Compute()
	local p = P()
	local overhead = max(0, p.overheadMinutes or 0)
	local budget = max(0, (p.hoursBudget or 0) * 60)
	local spent, spentPerGuid = self:Spent()
	local available = budget
	if p.subtractSpent then
		available = max(0, budget - spent)
	end

	local order, cands, info = BuildCandidates()

	local plan = {
		budgetMinutes = budget,
		spentMinutes = spent,
		spentPerGuid = spentPerGuid,
		availableMinutes = available,
		overhead = overhead,
		plannedMinutes = 0,
		plannedScore = 0,
		groups = {},
		groupsByGuid = {},
		skipped = {},
		skipReasons = {},
		leftovers = {},
		cutoffRate = nil,
	}

	local remaining = available
	local takenByGuid = {}
	for _, guid in ipairs(order) do takenByGuid[guid] = {} end

	while true do
		local bestRate, bestGuid, bestItems, bestIsBundle
		for _, guid in ipairs(order) do
			local list = cands[guid]
			if #list > 0 then
				if plan.groupsByGuid[guid] then
					local item = BestSingle(list, takenByGuid[guid], remaining)
					if item and (not bestRate or item.rate > bestRate) then
						bestRate, bestGuid, bestItems, bestIsBundle = item.rate, guid, { item }, false
					end
				else
					local items, rate = BestBundle(list, takenByGuid[guid], overhead, remaining)
					if items and (not bestRate or rate > bestRate) then
						bestRate, bestGuid, bestItems, bestIsBundle = rate, guid, items, true
					end
				end
			end
		end
		if not bestRate then break end

		local group = plan.groupsByGuid[bestGuid]
		if bestIsBundle then
			group = { char = info[bestGuid].char, guid = bestGuid, overhead = overhead, items = {}, minutes = 0, score = 0 }
			plan.groups[#plan.groups + 1] = group
			plan.groupsByGuid[bestGuid] = group
			remaining = remaining - overhead
			plan.plannedMinutes = plan.plannedMinutes + overhead
		end
		for _, item in ipairs(bestItems) do
			group.items[#group.items + 1] = item
			group.minutes = group.minutes + item.minutes
			group.score = group.score + item.score
			takenByGuid[bestGuid][item.chore.id] = true
			remaining = remaining - item.minutes
			plan.plannedMinutes = plan.plannedMinutes + item.minutes
			plan.plannedScore = plan.plannedScore + item.score
		end
		plan.cutoffRate = plan.cutoffRate and min(plan.cutoffRate, bestRate) or bestRate
	end

	-- Leftovers (didn't fit or not worth it)
	for _, guid in ipairs(order) do
		for _, item in ipairs(cands[guid]) do
			if not takenByGuid[guid][item.chore.id] then
				plan.leftovers[#plan.leftovers + 1] = item
			end
		end
	end
	sort(plan.leftovers, function(a, b) return a.rate > b.rate end)

	-- Skip list (every alt that is not in the plan, with a reason)
	for _, char in ipairs(ns.Roster:GetAll()) do
		local guid = char.guid
		local inf = info[guid]
		if inf.bank then
			-- Bank alts aren't "skipped" - they never take chores. Keep a reason for the login line.
			plan.skipReasons[guid] = inf.reason
		elseif not plan.groupsByGuid[guid] then
			local reason, kind
			if inf.reason then
				reason, kind = inf.reason, "inactive"
			elseif inf.eligible == 0 then
				local what = ns.Roster:Role(char) == "profession" and "profession chores" or "chores"
				reason, kind = format("no eligible %s at level %d", what, char.level or 0), "inactive"
			elseif #cands[guid] == 0 then
				reason, kind = "all chores done this week", "done"
			elseif available <= 0 then
				reason, kind = "no time left in this week's budget", "skip"
			else
				kind = "skip"
				local _, rate = BestBundle(cands[guid], {}, overhead, available)
				if not rate then
					local smallest
					for _, item in ipairs(cands[guid]) do
						smallest = smallest and min(smallest, item.minutes) or item.minutes
					end
					reason = format("nothing left that fits (needs %s incl. overhead)", ns.FormatMinutes((smallest or 0) + overhead))
				elseif plan.cutoffRate and rate < plan.cutoffRate then
					reason = format("low rate: %s pts/min vs plan cutoff %s", ns.FormatRate(rate), ns.FormatRate(plan.cutoffRate))
				else
					reason = format("budget filled first (%s pts/min)", ns.FormatRate(rate))
				end
			end
			plan.skipped[#plan.skipped + 1] = { char = char, guid = guid, reason = reason, kind = kind }
			plan.skipReasons[guid] = reason
		end
	end

	self:MaybeSnapshot(plan)
	return plan
end

---------------------------------------------------------------------------
-- Week summaries ("last week")
---------------------------------------------------------------------------
-- The first plan computed after the login scans of the week's first session is kept so that next
-- week can show "planned vs actual".
function Planner:MaybeSnapshot(plan)
	local g = G()
	if not g.weekKey then return end
	if g.weekPlanSnapshot and g.weekPlanSnapshot.key == g.weekKey then return end
	if not (ns.Detection and ns.Detection:IsReady()) then return end
	local count = 0
	for _, group in ipairs(plan.groups) do count = count + #group.items end
	g.weekPlanSnapshot = {
		key = g.weekKey,
		budgetMinutes = plan.budgetMinutes,
		plannedMinutes = plan.plannedMinutes,
		plannedScore = plan.plannedScore,
		plannedCount = count,
		alts = #plan.groups,
	}
	Debug:Log("Week plan snapshot:", count, "chores,", ns.FormatMinutes(plan.plannedMinutes))
end

-- Called by Core just before the week key changes.
function Planner:SummarizeWeek()
	local g = G()
	local spent, perGuid, count, value, perGuidCount = self:Spent()
	local perAlt = {}
	for _, char in ipairs(ns.Roster:GetAll()) do
		local n = perGuidCount[char.guid] or 0
		if n > 0 then
			perAlt[#perAlt + 1] = { name = char.name, realm = char.realm, class = char.class, count = n, minutes = perGuid[char.guid] or 0 }
		end
	end
	local snap = g.weekPlanSnapshot
	return {
		key = g.weekKey,
		budgetMinutes = (P().hoursBudget or 0) * 60,
		planned = (snap and snap.key == g.weekKey) and snap or nil,
		spentMinutes = spent,
		completedCount = count,
		valueEarned = value,
		perAlt = perAlt,
	}
end
