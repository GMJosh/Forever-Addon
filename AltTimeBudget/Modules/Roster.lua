-- AltTimeBudget: alt roster (account-wide) and per-week completion state
--
-- db.global.chars[guid] = {
--   guid, name, realm, class, level, lastSeen,   -- identity, refreshed on every login
--   role,                                        -- "main" / "alt" / "profession" / "bank" (see Config.lua)
--   priority,                                    -- reward multiplier (defaults per role, user-editable)
--   preBankRole,                                 -- role held before switching to bank (priority rule)
--   excluded,
--   activeSeconds,                               -- cumulative active (non-AFK) play the addon has observed
--   anchors = { [anchorKey] = { at = activeSeconds, source = "quest"/"instance"/"manual" } },
--   week = {                                     -- wiped at the weekly reset
--     key,                                       -- db.global.weekKey this state belongs to
--     detected = { [choreId] = serverTime },     -- auto-detected completions
--     manual   = { [choreId] = true/false },     -- manual checkoff / override of detection (nil = follow detection)
--     measured = { [choreId] = minutes },        -- measured completion time, when we had an anchor
--     vaultProgress = { [rowName] = progress },
--     progress = { [choreId] = { done = n, need = m } }, -- quest progress for "all" / "count" chores
--     baseline = { [choreId] = { [questID] = true } },   -- questOnce chores: IDs already done at the week's first scan
--   },
--   professions = {                              -- primary professions, refreshed on login / SKILL_LINES_CHANGED
--     scanned = serverTime,                      -- nil = never scanned (profession chores fall back to manual)
--     [1] = { skillLine, base, name }, [2] = ...  -- base = base skillLine (171 Alchemy ...) or nil if unknown
--   },
-- }
local addonName, ns = ...

local Debug = ns.Debug

local pairs = pairs
local ipairs = ipairs
local select = select
local pcall = pcall
local tostring = tostring
local sort = table.sort
local wipe = wipe
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitLevel = UnitLevel
local GetServerTime = GetServerTime
local abs = math.abs
local type = type

local Roster = {}
ns.Roster = Roster

local currentGUID

local function G()
	return ns.db.global
end

local function NewWeek(key)
	return { key = key, detected = {}, manual = {}, measured = {}, vaultProgress = {}, progress = {}, baseline = {} }
end

-- Week tables saved by older versions lack the newer sub-tables.
local function FillWeek(w)
	w.detected = w.detected or {}
	w.manual = w.manual or {}
	w.measured = w.measured or {}
	w.vaultProgress = w.vaultProgress or {}
	w.progress = w.progress or {}
	w.baseline = w.baseline or {}
	return w
end

function Roster:CurrentGUID()
	if not currentGUID then
		currentGUID = ns.SafeString(UnitGUID("player"))
	end
	return currentGUID
end

function Roster:Current()
	local guid = self:CurrentGUID()
	return guid and G().chars[guid]
end

function Roster:GetChar(guid)
	return guid and G().chars[guid]
end

local function CountChars()
	local n = 0
	for _ in pairs(G().chars) do n = n + 1 end
	return n
end

function Roster:RegisterCurrent()
	local guid = self:CurrentGUID()
	if not guid then
		Debug:Log("RegisterCurrent: no player GUID yet")
		return nil
	end
	local chars = G().chars
	local char = chars[guid]
	if not char then
		-- Convenience only: the very first character in a brand-new database starts as Main.
		-- Every later character starts as Alt. Roles are changed in the Alts tab.
		local role = CountChars() == 0 and "main" or "alt"
		char = {
			guid = guid,
			role = role,
			priority = ns.RoleDefaultPriority(role),
			excluded = false,
			activeSeconds = 0,
			anchors = {},
		}
		chars[guid] = char
		Debug:Log("Registered new character", guid, "role", role)
	end
	char.role = ns.ValidRole(char.role) or "alt"
	char.name = ns.SafeString(UnitName("player")) or char.name or "?"
	char.realm = ns.SafeString(GetNormalizedRealmName and GetNormalizedRealmName()) or char.realm or "?"
	char.class = ns.SafeString(select(2, UnitClass("player"))) or char.class
	char.level = ns.SafeNumber(UnitLevel("player")) or char.level or 1
	char.lastSeen = GetServerTime()
	char.anchors = char.anchors or {}
	char.activeSeconds = char.activeSeconds or 0
	self:GetWeek(char)
	return char
end

function Roster:TouchCurrent()
	local char = self:Current()
	if not char then return end
	char.level = ns.SafeNumber(UnitLevel("player")) or char.level
	char.lastSeen = GetServerTime()
end

function Roster:SetLevel(level)
	local char = self:Current()
	level = ns.SafeNumber(level)
	if char and level then
		char.level = level
		ns.NotifyUpdate("level")
	end
end

function Roster:Role(char)
	return char and ns.ValidRole(char.role) or "alt"
end

-- Role order (mains first, bank last), then priority (desc), then name.
function Roster:GetAll()
	local list = {}
	for _, char in pairs(G().chars) do
		list[#list + 1] = char
	end
	local rank = ns.ROLE_RANK
	sort(list, function(a, b)
		local ra, rb = rank[Roster:Role(a)], rank[Roster:Role(b)]
		if ra ~= rb then
			return ra < rb
		end
		if (a.priority or 0) ~= (b.priority or 0) then
			return (a.priority or 0) > (b.priority or 0)
		end
		return ns.CharLabel(a) < ns.CharLabel(b)
	end)
	return list
end

---------------------------------------------------------------------------
-- Week state
---------------------------------------------------------------------------
function Roster:GetWeek(char)
	local key = G().weekKey
	local w = char.week
	if not w or w.key ~= key then
		w = NewWeek(key)
		char.week = w
	end
	return FillWeek(w)
end

function Roster:AccountWeek()
	local g = G()
	local w = g.accountWeek
	if not w or w.key ~= g.weekKey then
		w = NewWeek(g.weekKey)
		g.accountWeek = w
	end
	return FillWeek(w)
end

-- The state table a chore's completion lives in for a given char.
function Roster:StateFor(char, chore)
	if chore.scope == "account" then
		return self:AccountWeek()
	end
	return self:GetWeek(char)
end

function Roster:ResetAllWeeks()
	local key = G().weekKey
	for _, char in pairs(G().chars) do
		char.week = NewWeek(key)
	end
	G().accountWeek = NewWeek(key)
	Debug:Log("Week state cleared for all characters")
end

-- Returns done (bool), how ("manual" / "auto" / nil)
function Roster:IsDone(char, chore)
	local state = self:StateFor(char, chore)
	local m = state.manual[chore.id]
	if m ~= nil then
		return m and true or false, "manual"
	end
	if state.detected[chore.id] then
		return true, "auto"
	end
	return false, nil
end

function Roster:IsDetected(char, chore)
	return self:StateFor(char, chore).detected[chore.id] ~= nil
end

-- value: true (done), false (force not done), nil (follow detection)
function Roster:SetManual(char, chore, value)
	local wasDone = self:IsDone(char, chore)
	local state = self:StateFor(char, chore)
	state.manual[chore.id] = value
	Debug:Log("Manual checkoff:", ns.CharLabel(char), chore.id, tostring(value))
	local nowDone = self:IsDone(char, chore)
	if nowDone and not wasDone and char.guid == self:CurrentGUID() then
		-- If the player started a timer (or accepted a linked quest), this yields a learned sample.
		ns.TimeLearner:OnChoreCompleted(char, chore, "manual")
	end
	ns.NotifyUpdate("checkoff")
end

function Roster:MarkDetected(char, chore)
	local state = self:StateFor(char, chore)
	if state.detected[chore.id] then return false end
	state.detected[chore.id] = GetServerTime()
	return true
end

-- Role + applicability check (no level / enabled check). A profession-slot chore does not apply
-- to an alt that was scanned without a profession in that slot.
function Roster:RoleAllows(char, chore)
	return ns.Chores:RoleAllows(chore, self:Role(char)) and ns.Chores:AppliesTo(chore, char)
end

-- Partial quest progress: done, need (nil when there is nothing to show).
function Roster:GetProgress(char, chore)
	local p = self:StateFor(char, chore).progress[chore.id]
	if type(p) ~= "table" or not p.need then return nil end
	return p.done or 0, p.need
end

-- Returns true if the stored progress changed.
function Roster:SetProgress(char, chore, done, need)
	local state = self:StateFor(char, chore)
	local p = state.progress[chore.id]
	if p and p.done == done and p.need == need then return false end
	state.progress[chore.id] = { done = done, need = need }
	return true
end

---------------------------------------------------------------------------
-- Professions (current character)
---------------------------------------------------------------------------
-- GetProfessions / GetProfessionInfo are legacy globals that are not in
-- Blizzard_APIDocumentationGenerated; their signatures are taken from Blizzard's own callers
-- (Blizzard_ProfessionsBook.lua: "local prof1, prof2, arch, fish, cook = GetProfessions()" and
-- "local name, texture, rank, maxRank, numSpells, spellOffset, skillLine, ... = GetProfessionInfo(index)").
local function ReadProfession(index)
	if not index or ns.IsSecret(index) then return nil end
	local ok, name, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, index)
	if not ok then return nil end
	skillLine = ns.SafeNumber(skillLine)
	if not skillLine then return nil end
	local Q = ns.QuestIDs
	local base = Q and Q.ProfessionBaseBySkillLine and Q.ProfessionBaseBySkillLine[skillLine]
	local data = base and Q.Professions[base]
	return {
		skillLine = skillLine,
		base = base,
		name = ns.SafeString(name) or (data and data.name) or ("Profession " .. skillLine),
	}
end

local function SameProf(a, b)
	if a == nil or b == nil then return a == b end
	return a.skillLine == b.skillLine and a.name == b.name
end

-- Refreshes the current character's primary professions. Returns true if they changed.
function Roster:ScanProfessions()
	local char = self:Current()
	if not char then return false end
	if not (GetProfessions and GetProfessionInfo) then
		Debug:Log("ScanProfessions: GetProfessions/GetProfessionInfo unavailable")
		return false
	end
	local ok, i1, i2 = pcall(GetProfessions)
	if not ok then
		Debug:Log("ScanProfessions: GetProfessions failed", tostring(i1))
		return false
	end
	local p1, p2 = ReadProfession(i1), ReadProfession(i2)
	local old = char.professions
	local changed = type(old) ~= "table" or not old.scanned or not SameProf(old[1], p1) or not SameProf(old[2], p2)
	char.professions = { scanned = GetServerTime(), [1] = p1, [2] = p2 }
	if changed then
		Debug:Log("Professions:", ns.CharLabel(char),
			p1 and (p1.name .. " (" .. p1.skillLine .. (p1.base and "" or ", no quest data") .. ")") or "-",
			p2 and (p2.name .. " (" .. p2.skillLine .. (p2.base and "" or ", no quest data") .. ")") or "-")
	end
	return changed
end

function Roster:IsEligible(char, chore)
	if not chore.enabled then return false end
	if not self:RoleAllows(char, chore) then return false end
	return (char.level or 1) >= ns.Chores:MinLevel(chore)
end

---------------------------------------------------------------------------
-- Roster editing
---------------------------------------------------------------------------
function Roster:SetPriority(guid, value)
	local char = self:GetChar(guid)
	if not char then return end
	char.priority = value
	ns.NotifyUpdate("roster")
end

function Roster:SetExcluded(guid, value)
	local char = self:GetChar(guid)
	if not char then return end
	char.excluded = value and true or false
	Debug:Log("Exclude:", ns.CharLabel(char), tostring(char.excluded))
	ns.NotifyUpdate("roster")
end

local function SamePriority(a, b)
	return a ~= nil and b ~= nil and abs(a - b) < 0.001
end

-- Changes an alt's role. The priority follows the new role's default ONLY if it still equals the
-- old role's default - a priority the user customized is never overwritten. Bank has no default:
-- going to bank leaves the priority alone, and leaving bank compares against the role held before.
function Roster:SetRole(guid, role)
	local char = self:GetChar(guid)
	role = ns.ValidRole(role)
	if not char or not role then return end
	local old = self:Role(char)
	if old == role then return end
	local compareRole = old
	if old == "bank" then
		compareRole = ns.ValidRole(char.preBankRole) or "alt"
	end
	if role == "bank" then
		char.preBankRole = old
	else
		char.preBankRole = nil
		if SamePriority(char.priority, ns.RoleDefaultPriority(compareRole)) then
			char.priority = ns.RoleDefaultPriority(role)
		end
	end
	char.role = role
	Debug:Log("Role:", ns.CharLabel(char), old, "->", role, "priority", tostring(char.priority))
	ns.NotifyUpdate("roster")
end

function Roster:Delete(guid)
	if guid == self:CurrentGUID() then
		return false
	end
	local char = self:GetChar(guid)
	if not char then return false end
	G().chars[guid] = nil
	Debug:Log("Deleted character:", ns.CharLabel(char))
	ns.NotifyUpdate("roster")
	return true
end

-- Note: changing profile.defaultAltPriority only affects alts registered afterwards - existing
-- priorities are user data and are never rewritten.
function Roster:ClearAnchors(char)
	if char and char.anchors then
		wipe(char.anchors)
	end
end
