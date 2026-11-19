-- ReturnFromBreak: AceConfig options (Blizzard Settings > AddOns > Return From Break)
local addonName, ns = ...

local function RefreshWindow()
	if ns.UI:IsShown() then
		ns.UI:Refresh()
	end
end

local function SectionToggle(key, order, desc)
	return {
		type = "toggle",
		order = order,
		name = ns.SECTION_TITLES[key],
		desc = desc,
		get = function() return ns.db.profile.sections[key] end,
		set = function(_, value)
			ns.db.profile.sections[key] = value
			RefreshWindow()
		end,
	}
end

local function BuildOptions()
	return {
		type = "group",
		name = ns.TITLE,
		args = {
			intro = {
				type = "description",
				order = 1,
				name = "Shows what you were doing when you come back: unspent talents, current quests, what changed since you last logged out, and new zones to unlock.\n\n/rfb toggles the window.\n",
			},
			general = {
				type = "group",
				order = 10,
				inline = true,
				name = "General",
				args = {
					showOnLogin = {
						type = "toggle",
						order = 1,
						width = "full",
						name = "Show on login",
						desc = "Open the window automatically when you log in (not on /reload or zoning).",
						get = function() return ns.db.profile.showOnLogin end,
						set = function(_, value) ns.db.profile.showOnLogin = value end,
					},
					loginDelay = {
						type = "range",
						order = 2,
						name = "Login delay (seconds)",
						desc = "Wait this long after login before opening, so quest and currency data can load.",
						min = 0, max = 15, step = 1,
						get = function() return ns.db.profile.loginDelay end,
						set = function(_, value) ns.db.profile.loginDelay = value end,
					},
					open = {
						type = "execute",
						order = 3,
						name = "Open window",
						func = function() ns.UI:Show() end,
					},
				},
			},
			window = {
				type = "group",
				order = 20,
				inline = true,
				name = "Window",
				args = {
					locked = {
						type = "toggle",
						order = 1,
						name = "Lock position",
						get = function() return ns.db.profile.locked end,
						set = function(_, value) ns.db.profile.locked = value end,
					},
					scale = {
						type = "range",
						order = 2,
						name = "Scale",
						min = 0.6, max = 1.6, step = 0.05, isPercent = true,
						get = function() return ns.db.profile.scale end,
						set = function(_, value)
							ns.db.profile.scale = value
							ns.UI:ApplySettings()
						end,
					},
					resetPos = {
						type = "execute",
						order = 3,
						name = "Reset position",
						func = function() ns.UI:ResetPosition() end,
					},
				},
			},
			sections = {
				type = "group",
				order = 30,
				inline = true,
				name = "Sections",
				args = {
					talents = SectionToggle("talents", 1, "Unspent talent points."),
					quests = SectionToggle("quests", 2, "Focused, campaign and tracked quests."),
					snapshot = SectionToggle("snapshot", 3, "Time away and changes to level, item level, gold and currencies."),
					zones = SectionToggle("zones", 4, "Zones from Data\\Zones.lua whose unlock quest you haven't finished."),
					maxCurrencyLines = {
						type = "range",
						order = 5,
						name = "Max currency lines",
						min = 5, max = 100, step = 1,
						get = function() return ns.db.profile.maxCurrencyLines end,
						set = function(_, value)
							ns.db.profile.maxCurrencyLines = value
							RefreshWindow()
						end,
					},
				},
			},
			data = {
				type = "group",
				order = 40,
				inline = true,
				name = "Data",
				args = {
					clearSnapshot = {
						type = "execute",
						order = 1,
						name = "Clear snapshot",
						desc = "Forget this character's saved snapshot and baseline.",
						confirm = true,
						func = function()
							ns.db.char.snapshot = nil
							ns.db.char.baseline = nil
							RefreshWindow()
						end,
					},
				},
			},
		},
	}
end

function ns.SetupOptions(addon)
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, ns.TITLE)
	addon.optionsCategoryID = categoryID
	ns.Debug("Options registered, categoryID =", categoryID)
end
