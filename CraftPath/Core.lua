-- CraftPath: namespace, events, saved data, helpers and slash commands
local addonName, ns = ...

local format = string.format
local floor = math.floor
local abs = math.abs

local frame = CreateFrame("Frame")
local handlers = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Num(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return tonumber(v)
end

function ns.Print(msg)
	print("|cff66ccffCraftPath:|r " .. msg)
end

-- Copper to text, with a minus sign when negative (a negative net cost is a profit).
function ns.Money(copper)
	copper = floor((copper or 0) + 0.5)
	local text
	if GetCoinTextureString then
		text = GetCoinTextureString(abs(copper))
	else
		text = format("%dg %ds %dc", floor(abs(copper) / 10000), floor(abs(copper) % 10000 / 100), abs(copper) % 100)
	end
	return copper < 0 and ("-" .. text) or text
end

-- "2g 50s 3c", "50s", "12" (copper) -> copper
function ns.ParseMoney(text)
	if not text or text == "" then
		return nil
	end
	local total, found = 0, false
	for amount, unit in text:gmatch("(%d+%.?%d*)%s*([gsc]?)") do
		local n = tonumber(amount)
		if n then
			found = true
			if unit == "g" then
				total = total + n * 10000
			elseif unit == "s" then
				total = total + n * 100
			else
				total = total + n
			end
		end
	end
	return found and floor(total + 0.5) or nil
end

local function MergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then
				db[k] = {}
				MergeDefaults(db[k], v)
			else
				db[k] = v
			end
		elseif type(v) == "table" and type(db[k]) == "table" then
			MergeDefaults(db[k], v)
		end
	end
end

function ns.Char()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or ""
	local key = name .. "-" .. realm
	local char = ns.db.chars[key]
	if not char then
		char = { name = name, profs = {} }
		ns.db.chars[key] = char
	end
	return char
end

-- Puts a map pin on a spot (coords are percent, like 41.6, 65.8). Falls back to printing the spot.
function ns.Waypoint(mapID, x, y)
	if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
		and C_Map.CanSetUserWaypointOnMap(mapID) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		ns.Print(format("Waypoint set at %.1f, %.1f.", x, y))
	else
		ns.Print(format("Could not set a waypoint here. The spot is %.1f, %.1f on map %d.", x, y, mapID))
	end
end

-- Clicks on |Hcraftpath:way:map:x:y|h links in the window.
function ns.HandleLink(link)
	local mapID, x, y = tostring(link):match("^craftpath:way:(%d+):([%d.]+):([%d.]+)$")
	if mapID then
		ns.Waypoint(tonumber(mapID), tonumber(x), tonumber(y))
	end
end

---------------------------------------------------------------------------
-- Events: ns.On("EVENT", fn). Events that do not exist in this client are skipped.
---------------------------------------------------------------------------

function ns.On(event, fn)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		ns.Debug("Event not valid in this client:", event)
		return
	end
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		frame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			list[i](event, ...)
		end
	end
end)

-- Registered first, so the database exists before any other handler runs.
ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then
		return
	end
	CraftPathDB = CraftPathDB or {}
	MergeDefaults(CraftPathDB, ns.DEFAULTS)
	ns.db = CraftPathDB
	ns.Debug("Loaded")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_CRAFTPATH1 = "/cpath"
SLASH_CRAFTPATH2 = "/craftpath"
SlashCmdList.CRAFTPATH = function(input)
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "show" then
		ns.ToggleWindow()
	elseif cmd == "scan" then
		ns.ScanProfession(true)
	elseif cmd == "price" then
		-- /cpath price [item link] 2g 50s
		local itemID = tonumber(arg:match("item:(%d+)"))
		local money = ns.ParseMoney((arg:gsub("|c%x+|Hitem:.-|h%[.-%]|h|r", "")))
		if itemID and money then
			ns.db.prices[itemID] = money
			ns.Print(format("Price for item %d set to %s.", itemID, ns.Money(money)))
		elseif itemID and arg:lower():find("clear") then
			ns.db.prices[itemID] = nil
			ns.Print(format("Price for item %d cleared.", itemID))
		else
			ns.Print("Usage: /cpath price [shift-click an item] 2g 50s   (use for vendor items with no auction price)")
		end
	elseif cmd == "debug" then
		ns.ToggleDebugWindow(arg)
	else
		ns.Print("/cpath (open), /cpath scan, /cpath price [item] 2g, /cpath debug")
	end
end

SLASH_CRAFTPATHDEBUG1 = "/cpdebug"
SlashCmdList.CRAFTPATHDEBUG = function(input)
	ns.ToggleDebugWindow((input or ""):lower())
end
