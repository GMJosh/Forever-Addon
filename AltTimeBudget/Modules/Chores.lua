-- AltTimeBudget: chore definitions (presets + user overrides + custom chores) and time estimates
local addonName, ns = ...

local Debug = ns.Debug

local max = math.max
local floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs
local sort = table.sort
local gmatch = string.gmatch
local next = next
local tconcat = table.concat
local lower = string.lower

local Chores = {}
ns.Chores = Chores

local cacheList, cacheById

local function G()
	return ns.db.global
end

-- "12345, 67890" -> { 12345, 67890 } (nil if empty)
function Chores:ParseQuestIDs(text)
	if type(text) ~= "string" then return nil end
	local ids = {}
	for token in gmatch(text, "%d+") do
		local id = tonumber(token)
		if id and id > 0 then
			ids[#ids + 1] = id
		end
	end
	if #ids == 0 then return nil end
	return ids
end

-- Preset questIDs may be a list of numbers ({ 123, 456 }) or a string ("123, 456").
-- Returns the comma-separated text form (nil when empty).
local function QuestIDsToText(v)
	if type(v) == "table" then
		local parts = {}
		for _, id in ipairs(v) do
			if tonumber(id) then parts[#parts + 1] = tostring(id) end
		end
		if #parts == 0 then return nil end
		return tconcat(parts, ", ")
	end
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- Default allowed roles when a chore doesn't list any: main + alt, plus profession for
-- chores in the "Professions" category (any category containing "profession").
function Chores:DefaultRoles(category)
	local roles = { main = true, alt = true }
	if type(category) == "string" and lower(category):find("profession", 1, true) then
		roles.profession = true
	end
	return roles
end

-- Copies a roles table keeping only roles a chore may have (bank never takes chores).
local function CleanRoles(t)
	if type(t) ~= "table" then return nil end
	local roles = {}
	for _, role in ipairs(ns.CHORE_ROLE_ORDER) do
		if t[role] then roles[role] = true end
	end
	return roles
end

local QUEST_MODES = { any = true, all = true, count = true }
Chores.QUEST_MODE_LABELS = {
	any = "Any one (pool)",
	all = "All listed",
	count = "At least N",
}

local function ValidMode(m)
	if m and QUEST_MODES[m] then return m end
	return nil
end

function Chores:ClampRequired(n, total)
	n = floor(tonumber(n) or 1)
	if n < 1 then n = 1 end
	if total and total > 0 and n > total then n = total end
	return n
end

local function Resolve(base, ov, isCustom, order)
	ov = ov or {}
	local c = {
		id = base.id,
		isCustom = isCustom,
		order = order,
		name = ov.name or base.name or base.id,
		category = ov.category or base.category or "Custom",
		value = tonumber(ov.value) or tonumber(base.value) or 10,
		minLevel = ov.minLevel or base.minLevel or 1,
		scope = base.scope == "account" and "account" or "char",
		requires = base.requires,
		minutesOverride = tonumber(ov.minutes),
		baseMinutes = tonumber(base.minutes) or 20,
		unitMinutes = tonumber(base.unitMinutes),
		questIDsText = QuestIDsToText(ov.questIDs) or QuestIDsToText(base.questIDs),
	}
	c.roles = CleanRoles(ov.roles) or CleanRoles(base.roles) or Chores:DefaultRoles(c.category)
	c.rolesCustomized = ov.roles ~= nil
	if ov.enabled ~= nil then
		c.enabled = ov.enabled and true or false
	else
		c.enabled = base.enabled ~= false
	end
	c.note = base.note
	c.nameCustomized = ov.name ~= nil
	if base.detect then
		c.detect = base.detect
	elseif type(base.prof) == "table" then
		-- Quest IDs resolve per alt from the alt's scanned professions (see Chores:QuestSpec).
		c.prof = { slot = base.prof.slot, kind = base.prof.kind }
		c.detect = { type = "profession", slot = c.prof.slot, kind = c.prof.kind }
		c.questIDsText = nil
	else
		local ids = Chores:ParseQuestIDs(c.questIDsText)
		if ids then
			local mode = ValidMode(ov.questMode) or ValidMode(base.questMode) or "any"
			local flag = base.questFlag
			if flag ~= "char" and flag ~= "account" and flag ~= "either" then
				flag = c.scope == "account" and "account" or "char"
			end
			c.detect = { type = "quest", questIDs = ids }
			c.quest = {
				ids = ids,
				mode = mode,
				required = Chores:ClampRequired(tonumber(ov.required) or tonumber(base.required) or 1, #ids),
				flag = flag,
				once = base.questOnce and true or false,
			}
		end
	end
	c.questMode = (c.quest and c.quest.mode) or ValidMode(ov.questMode) or ValidMode(base.questMode) or "any"
	c.questRequired = (c.quest and c.quest.required) or tonumber(ov.required) or tonumber(base.required) or 1
	c.isVault = c.detect ~= nil and c.detect.type == "vault"
	-- Vault chores learn "minutes per vault progress unit" shared by every slot of the same row.
	c.learnKey = c.isVault and ("vault:" .. c.detect.row) or c.id
	return c
end

local function Build()
	local g = G()
	cacheList, cacheById = {}, {}
	local order = 0
	for _, base in ipairs(ns.PRESETS) do
		order = order + 1
		local c = Resolve(base, g.choreOverrides[base.id], false, order)
		cacheList[#cacheList + 1] = c
		cacheById[c.id] = c
	end
	local customs = {}
	for id, def in pairs(g.customChores) do
		if type(def) == "table" then
			def.id = id
			customs[#customs + 1] = def
		end
	end
	sort(customs, function(a, b) return (a.created or 0) < (b.created or 0) end)
	for _, def in ipairs(customs) do
		order = order + 1
		local c = Resolve(def, g.choreOverrides[def.id], true, order)
		cacheList[#cacheList + 1] = c
		cacheById[c.id] = c
	end
end

function Chores:Invalidate()
	cacheList, cacheById = nil, nil
end

function Chores:GetAll()
	if not cacheList then Build() end
	return cacheList
end

function Chores:Get(id)
	if not cacheById then Build() end
	return cacheById[id]
end

-- Can an alt with this role do this chore? (bank: never)
function Chores:RoleAllows(chore, role)
	if role == "bank" then return false end
	return chore.roles[ns.ValidRole(role) or "alt"] and true or false
end

-- Sets one role on/off for a chore (stored as an override; "Restore preset values" undoes it).
function Chores:SetRoleAllowed(id, role, allowed)
	local chore = self:Get(id)
	if not chore or role == "bank" or not ns.ValidRole(role) then return end
	local roles = {}
	for r in pairs(chore.roles) do roles[r] = true end
	roles[role] = allowed and true or nil
	self:SetOverride(id, "roles", roles)
end

-- "Main, Alt, Profession" (or "none")
function Chores:RolesText(chore)
	local parts = {}
	for _, role in ipairs(ns.CHORE_ROLE_ORDER) do
		if chore.roles[role] then parts[#parts + 1] = ns.ROLE_LABELS[role] end
	end
	if #parts == 0 then return "none" end
	return tconcat(parts, ", ")
end

function Chores:MinLevel(chore)
	return ns.ResolveMinLevel(chore.minLevel)
end

---------------------------------------------------------------------------
-- Per-alt resolution (profession chores) and quest detection specs
---------------------------------------------------------------------------
local PROF_KIND_LABEL = { weekly = "weekly", treatise = "treatise", drops = "knowledge drops" }
local PROF_KIND_MODE = { weekly = "any", treatise = "any", drops = "all" }
local profSpecCache = {}

-- The alt's profession in a slot.
-- Returns entry ({ skillLine, base, name }) or nil, plus status "ok" / "unscanned" / "none".
function Chores:ProfessionInSlot(char, slot)
	local profs = char and char.professions
	if type(profs) ~= "table" or not profs.scanned then
		return nil, "unscanned"
	end
	local entry = profs[slot]
	if type(entry) ~= "table" then
		return nil, "none"
	end
	return entry, "ok"
end

local function ProfSpec(base, kind)
	local key = tostring(base) .. ":" .. tostring(kind)
	local spec = profSpecCache[key]
	if spec ~= nil then return spec or nil end
	local data = ns.QuestIDs and ns.QuestIDs.Professions and ns.QuestIDs.Professions[base]
	local ids
	if data then
		if kind == "treatise" then
			ids = data.treatise and { data.treatise } or nil
		elseif type(data[kind]) == "table" then
			ids = data[kind]
		end
	end
	if not ids or #ids == 0 then
		profSpecCache[key] = false
		return nil
	end
	local mode = PROF_KIND_MODE[kind] or "any"
	spec = { ids = ids, mode = mode, required = mode == "all" and #ids or 1, flag = "char", once = false }
	profSpecCache[key] = spec
	return spec
end

-- Quest detection spec for a chore on a given alt:
--   { ids, mode = "any"/"all"/"count", required, flag = "char"/"account"/"either", once }
-- Returns spec, or nil plus a reason ("manual" / "unscanned" / "none" / "nodata").
function Chores:QuestSpec(chore, char)
	if chore.quest then
		return chore.quest
	end
	if chore.prof then
		local entry, status = self:ProfessionInSlot(char, chore.prof.slot)
		if not entry then
			return nil, status
		end
		local spec = entry.base and ProfSpec(entry.base, chore.prof.kind)
		if not spec then
			return nil, "nodata"
		end
		return spec
	end
	return nil, "manual"
end

-- How many completed IDs make the spec done.
function Chores:Needed(spec)
	if spec.mode == "all" then return #spec.ids end
	if spec.mode == "count" then return self:ClampRequired(spec.required, #spec.ids) end
	return 1
end

-- Does the chore apply to this alt at all? False only for a profession slot the alt has been
-- scanned NOT to have (unscanned alts keep the chore, as manual checkoff).
function Chores:AppliesTo(chore, char)
	if chore.prof then
		local _, status = self:ProfessionInSlot(char, chore.prof.slot)
		return status ~= "none"
	end
	return true
end

-- Display name for a chore on an alt ("Alchemy weekly" for profession chores).
function Chores:DisplayName(chore, char)
	if chore.prof and not chore.nameCustomized and char then
		local entry = self:ProfessionInSlot(char, chore.prof.slot)
		if entry and entry.name then
			return entry.name .. " " .. (PROF_KIND_LABEL[chore.prof.kind] or chore.prof.kind)
		end
	end
	return chore.name
end

---------------------------------------------------------------------------
-- Great Vault slot sizing
---------------------------------------------------------------------------
local function Threshold(row, index)
	local cached = G().vaultThresholds[row]
	if cached and cached[index] then
		return cached[index]
	end
	local fb = ns.FALLBACK_VAULT_THRESHOLDS[row]
	if fb and fb[index] then
		return fb[index]
	end
	return index
end

-- Vault progress units needed for this slot beyond the previous slot.
function Chores:VaultUnits(chore)
	if not chore.isVault then return 1 end
	local idx = chore.detect.index
	local cur = Threshold(chore.detect.row, idx)
	local prev = idx > 1 and Threshold(chore.detect.row, idx - 1) or 0
	return max(1, cur - prev)
end

-- Default minutes for one learn unit (whole chore for normal chores, one progress unit for vault).
function Chores:DefaultUnitMinutes(chore)
	if chore.isVault then
		return chore.unitMinutes or 20
	end
	return chore.baseMinutes
end

function Chores:DefaultMinutes(chore)
	if chore.isVault then
		return self:VaultUnits(chore) * (chore.unitMinutes or 20)
	end
	return chore.baseMinutes
end

function Chores:LearnedMinutes(chore)
	local rec = ns.TimeLearner:Get(chore.learnKey)
	if not rec or (rec.n or 0) < 1 or not rec.ema then
		return nil, rec
	end
	if chore.isVault then
		return self:VaultUnits(chore) * rec.ema, rec
	end
	return rec.ema, rec
end

-- Returns minutes, source ("override" / "learned" / "default")
-- Partial progress on "all" / "count" chores (e.g. 1/2 knowledge drops) deliberately does NOT
-- scale the estimate: the planner keeps the full chore minutes until the chore is done. This is
-- the simpler option - it keeps learned samples (which time the whole chore) comparable with the
-- estimate, at the cost of slightly over-budgeting a half-finished chore.
function Chores:EstimateMinutes(chore)
	if chore.minutesOverride and chore.minutesOverride > 0 then
		return chore.minutesOverride, "override"
	end
	local learned = self:LearnedMinutes(chore)
	if learned then
		return max(1, learned), "learned"
	end
	return max(1, self:DefaultMinutes(chore)), "default"
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------
local function Changed(reason)
	Chores:Invalidate()
	ns.NotifyUpdate(reason or "chores")
end

-- field: enabled / minutes / value / minLevel / name / category / questIDs / questMode / required / roles
function Chores:SetOverride(id, field, value)
	local g = G()
	local ov = g.choreOverrides[id]
	if not ov then
		ov = {}
		g.choreOverrides[id] = ov
	end
	if value == "" then value = nil end
	ov[field] = value
	if next(ov) == nil then
		g.choreOverrides[id] = nil
	end
	Debug:Log("Chore override:", id, field, tostring(value))
	Changed("chores")
end

function Chores:ResetOverrides(id)
	G().choreOverrides[id] = nil
	Debug:Log("Chore overrides reset:", id)
	Changed("chores")
end

-- Edit the base definition of a custom chore (minutes / scope / minLevel ...)
function Chores:SetCustomField(id, field, value)
	local def = G().customChores[id]
	if not def then return end
	def[field] = value
	Debug:Log("Custom chore field:", id, field, tostring(value))
	Changed("chores")
end

function Chores:AddCustom(name)
	name = ns.SafeString(name)
	if not name then return nil end
	local g = G()
	local id = "custom_" .. g.nextCustomId
	g.nextCustomId = g.nextCustomId + 1
	g.customChores[id] = {
		id = id,
		name = name,
		category = "Custom",
		minutes = 20,
		value = 20,
		minLevel = 1,
		scope = "char",
		created = (GetServerTime and GetServerTime()) or 0,
	}
	Debug:Log("Custom chore added:", id, name)
	Changed("chores")
	return id
end

function Chores:DeleteCustom(id)
	local g = G()
	if not g.customChores[id] then return end
	g.customChores[id] = nil
	g.choreOverrides[id] = nil
	g.learned[id] = nil
	Debug:Log("Custom chore deleted:", id)
	Changed("chores")
end

-- Display helper: "35m (learned, 6 samples)" etc.
function Chores:EstimateText(chore)
	local minutes, source = self:EstimateMinutes(chore)
	local text = ns.FormatMinutes(minutes)
	if source == "learned" then
		local _, rec = self:LearnedMinutes(chore)
		return text .. " |cff40ff40learned|r" .. (rec and rec.n and (" (" .. rec.n .. ")") or "")
	elseif source == "override" then
		return text .. " |cffffd100override|r"
	end
	return text .. " |cff9d9d9ddefault|r"
end

-- Used by the UI for a stable floor of numbers typed in edit boxes.
function Chores:CleanNumber(v, minV, maxV)
	v = tonumber(v)
	if not v then return nil end
	if minV and v < minV then v = minV end
	if maxV and v > maxV then v = maxV end
	return floor(v * 100 + 0.5) / 100
end
