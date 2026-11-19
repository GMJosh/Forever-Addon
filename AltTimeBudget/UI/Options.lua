-- AltTimeBudget: AceConfig options, registered in the Blizzard Settings panel
local addonName, ns = ...

local format = string.format
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs

local Options = {}
ns.Options = Options

local GREY = "|cff9d9d9d"
local GREEN = "|cff40ff40"

local function P()
	return ns.db.profile
end

local function Notify()
	LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

local function NumberValidator(minV, maxV, allowBlank)
	return function(_, v)
		if allowBlank and (v == nil or v == "") then return true end
		local n = tonumber(v)
		if not n or n < minV or n > maxV then
			return format("Enter a number between %s and %s%s.", minV, maxV, allowBlank and " (or leave blank)" or "")
		end
		return true
	end
end

local function ChoreInfoText(chore)
	local lines = {}
	lines[#lines + 1] = "Detection: " .. ns.Detection:Describe(chore)
	if chore.prof then
		lines[#lines + 1] = GREY .. format("Resolved per alt from the profession in slot %d (scanned at login and when professions change). Names show as e.g. \"Alchemy %s\". Alts not scanned yet are manual checkoff.|r",
			chore.prof.slot, chore.prof.kind == "drops" and "knowledge drops" or chore.prof.kind)
	end
	if chore.quest and chore.quest.once then
		lines[#lines + 1] = GREY .. "These quests can be completed once per character ever and rotate weekly: only completions since the week's first scan count.|r"
	end
	if chore.note then
		lines[#lines + 1] = "Note: " .. chore.note
	end
	lines[#lines + 1] = "Scope: " .. (chore.scope == "account" and "account-wide (once per week, given to the highest-priority alt whose role allows it)" or "per character")
	lines[#lines + 1] = "Allowed roles: " .. ns.Chores:RolesText(chore) .. (chore.rolesCustomized and "" or (GREY .. " (default)|r"))
	local minutes, source = ns.Chores:EstimateMinutes(chore)
	lines[#lines + 1] = format("Estimate used by the planner: %s (%s)", ns.FormatMinutes(minutes), source)
	lines[#lines + 1] = "Default: " .. ns.FormatMinutes(ns.Chores:DefaultMinutes(chore))
	local learned, rec = ns.Chores:LearnedMinutes(chore)
	if learned then
		lines[#lines + 1] = format("%sLearned: %s from %d sample(s), last %s|r", GREEN, ns.FormatMinutes(learned), rec.n or 0, ns.FormatMinutes(rec.last))
	else
		lines[#lines + 1] = GREY .. "Not learned yet.|r"
	end
	if chore.isVault then
		lines[#lines + 1] = GREY .. format("Great Vault slots learn minutes per progress unit, shared by every slot of the %s row. This slot needs %d unit(s).|r",
			chore.detect.row, ns.Chores:VaultUnits(chore))
	end
	return table.concat(lines, "\n") .. "\n"
end

local function BuildChoreGroup(chore)
	local id = chore.id
	local args = {
		info = {
			order = 1, type = "description", fontSize = "medium",
			name = function() return ChoreInfoText(ns.Chores:Get(id) or chore) end,
		},
		enabled = {
			order = 2, type = "toggle", name = "Enabled",
			get = function() local c = ns.Chores:Get(id) return c and c.enabled end,
			set = function(_, v) ns.Chores:SetOverride(id, "enabled", v and true or false) end,
		},
		name = {
			order = 3, type = "input", name = "Name", width = "double",
			get = function() local c = ns.Chores:Get(id) return c and c.name end,
			set = function(_, v) ns.Chores:SetOverride(id, "name", ns.SafeString(v)) end,
		},
		category = {
			order = 4, type = "input", name = "Category",
			get = function() local c = ns.Chores:Get(id) return c and c.category end,
			set = function(_, v) ns.Chores:SetOverride(id, "category", ns.SafeString(v)) end,
		},
		value = {
			order = 5, type = "input", name = "Value points",
			desc = "Points per completion. Score = value x alt priority - rate = score / minutes.",
			validate = NumberValidator(0, 100000),
			get = function() local c = ns.Chores:Get(id) return c and tostring(c.value) end,
			set = function(_, v) ns.Chores:SetOverride(id, "value", tonumber(v)) end,
		},
		minutes = {
			order = 6, type = "input", name = "Minutes override",
			desc = "Leave blank to use the learned average (or the default until something is learned).",
			validate = NumberValidator(1, 1440, true),
			get = function() local c = ns.Chores:Get(id) return c and c.minutesOverride and tostring(c.minutesOverride) or "" end,
			set = function(_, v) ns.Chores:SetOverride(id, "minutes", tonumber(v)) end,
		},
		minLevel = {
			order = 7, type = "input", name = "Minimum level",
			desc = "A number, or \"max\" for the current expansion's max level.",
			validate = function(_, v)
				if v == "max" or (tonumber(v) and tonumber(v) >= 1 and tonumber(v) <= 200) then return true end
				return "Enter a level (1-200) or \"max\"."
			end,
			get = function() local c = ns.Chores:Get(id) return c and tostring(c.minLevel) end,
			set = function(_, v) ns.Chores:SetOverride(id, "minLevel", v == "max" and "max" or tonumber(v)) end,
		},
		roles = {
			order = 8.5, type = "multiselect", name = "Allowed roles",
			desc = "Which alt roles may do this chore. Bank alts never get chores. Default: Main + Alt, plus Profession for chores in the Professions category.",
			values = { main = "Main", alt = "Alt", profession = "Profession" },
			get = function(_, key) local c = ns.Chores:Get(id) return c and c.roles[key] and true or false end,
			set = function(_, key, state) ns.Chores:SetRoleAllowed(id, key, state) end,
		},
		resetLearned = {
			order = 20, type = "execute", name = "Reset learned time",
			desc = "Forget the learned average and go back to the default.",
			func = function() ns.TimeLearner:Reset((ns.Chores:Get(id) or chore).learnKey) end,
		},
	}

	if not chore.isVault and not chore.prof then
		args.questIDs = {
			order = 8, type = "input", name = "Quest IDs (auto-detect)", width = "double",
			desc = "Optional. Comma-separated quest IDs. The detection mode below decides how many must be flagged completed this week. Accepting one starts a timer for learning. Only enter IDs you have verified.",
			get = function() local c = ns.Chores:Get(id) return c and c.questIDsText or "" end,
			set = function(_, v) ns.Chores:SetOverride(id, "questIDs", ns.SafeString(v)) end,
		}
		args.questMode = {
			order = 8.1, type = "select", name = "Detection mode",
			desc = "Any one: a pool, one completed ID = done. All listed: every ID must be completed (shows x/y). At least N: done when N IDs are completed (shows x/N).",
			values = ns.Chores.QUEST_MODE_LABELS, sorting = { "any", "all", "count" },
			get = function() local c = ns.Chores:Get(id) return c and c.questMode or "any" end,
			set = function(_, v) ns.Chores:SetOverride(id, "questMode", v) end,
		}
		args.required = {
			order = 8.2, type = "input", name = "N (for \"At least N\")",
			desc = "How many of the listed quests must be completed. Capped at the number of IDs.",
			validate = NumberValidator(1, 100),
			hidden = function() local c = ns.Chores:Get(id) return not c or c.questMode ~= "count" end,
			get = function() local c = ns.Chores:Get(id) return c and tostring(c.questRequired or 1) or "1" end,
			set = function(_, v) ns.Chores:SetOverride(id, "required", tonumber(v)) end,
		}
	end

	if chore.isCustom then
		args.baseMinutes = {
			order = 9, type = "input", name = "Default minutes",
			desc = "Starting estimate before anything is learned.",
			validate = NumberValidator(1, 1440),
			get = function() local c = ns.Chores:Get(id) return c and tostring(c.baseMinutes) end,
			set = function(_, v) ns.Chores:SetCustomField(id, "minutes", tonumber(v)) end,
		}
		args.scope = {
			order = 10, type = "select", name = "Scope",
			values = { char = "Per character", account = "Account-wide" },
			get = function() local c = ns.Chores:Get(id) return c and c.scope end,
			set = function(_, v) ns.Chores:SetCustomField(id, "scope", v) end,
		}
		args.delete = {
			order = 30, type = "execute", name = "Delete chore",
			confirm = true, confirmText = "Delete this custom chore and its learned time?",
			func = function() ns.Chores:DeleteCustom(id) end,
		}
	else
		args.restore = {
			order = 30, type = "execute", name = "Restore preset values",
			confirm = true, confirmText = "Undo every edit to this chore (name, value, minutes, level, quest IDs, detection mode, roles, enabled)?",
			func = function() ns.Chores:ResetOverrides(id) end,
		}
	end

	return {
		type = "group",
		order = chore.order,
		name = function()
			local c = ns.Chores:Get(id) or chore
			return c.enabled and c.name or (GREY .. c.name .. "|r")
		end,
		args = args,
	}
end

local newChoreName = ""

local function BuildChoresArgs()
	local args = {
		add = {
			order = 0, type = "group", name = "|cffffd100+ Add custom chore|r",
			args = {
				desc = {
					order = 1, type = "description",
					name = "Custom chores are manual checkoff unless you give them quest IDs (with a detection mode: any one, all, or at least N). Set their minutes and value after adding.\n",
				},
				name = {
					order = 2, type = "input", name = "Name", width = "double",
					get = function() return newChoreName end,
					set = function(_, v) newChoreName = v or "" end,
				},
				create = {
					order = 3, type = "execute", name = "Add",
					func = function()
						local id = ns.Chores:AddCustom(newChoreName)
						if id then
							newChoreName = ""
							Notify()
							LibStub("AceConfigDialog-3.0"):SelectGroup(addonName, "chores", id)
						end
					end,
				},
			},
		},
	}
	for _, chore in ipairs(ns.Chores:GetAll()) do
		args[chore.id] = BuildChoreGroup(chore)
	end
	return args
end

local ROLE_VALUES = {}
for _, role in ipairs(ns.ROLE_ORDER) do ROLE_VALUES[role] = ns.ROLE_LABELS[role] end

local function BuildAltsArgs()
	local args = {
		desc = {
			order = 0, type = "description",
			name = GREY .. "Main / Alt: every chore. Profession: only chores that allow the Profession role. Bank: no chores, never planned or listed as skipped. Changing a role resets the priority to the new role's default only if it still equals the old role's default.|r\n",
		},
	}
	local currentGUID = ns.Roster:CurrentGUID()
	for i, char in ipairs(ns.Roster:GetAll()) do
		local guid = char.guid
		local function C() return ns.Roster:GetChar(guid) end
		args["c" .. i] = {
			order = i, type = "group", inline = true,
			name = function()
				local c = C()
				if not c then return "?" end
				return format("%s %s (lvl %d)%s", ns.ClassColoredName(c), ns.RoleTag(ns.Roster:Role(c)), c.level or 0,
					guid == currentGUID and (GREEN .. " - this character|r") or "")
			end,
			args = {
				role = {
					order = 1, type = "select", name = "Role",
					values = ROLE_VALUES, sorting = ns.ROLE_ORDER,
					get = function() return ns.Roster:Role(C()) end,
					set = function(_, v) ns.Roster:SetRole(guid, v) end,
				},
				priority = {
					order = 2, type = "range", name = "Priority",
					min = 0, max = 2, step = 0.05,
					disabled = function() return ns.Roster:Role(C()) == "bank" end,
					get = function() local c = C() return c and c.priority or 0 end,
					set = function(_, v) ns.Roster:SetPriority(guid, v) end,
				},
				excluded = {
					order = 3, type = "toggle", name = "Exclude",
					get = function() local c = C() return c and c.excluded or false end,
					set = function(_, v) ns.Roster:SetExcluded(guid, v) end,
				},
			},
		}
	end
	return args
end

local function BuildOptions()
	return {
		type = "group",
		name = "AltTimeBudget",
		childGroups = "tab",
		args = {
			general = {
				order = 1,
				type = "group",
				name = "General",
				args = {
					intro = {
						order = 1,
						type = "description",
						name = "Plans your week of alt chores around the hours you actually have. /atb opens the planner.\n",
					},
					openWindow = {
						order = 2, type = "execute", name = "Open planner",
						func = function() ns.MainWindow:Open() end,
					},
					openDebug = {
						order = 3, type = "execute", name = "Debug log",
						func = function() ns.Debug:ToggleWindow() end,
					},
					budget = {
						order = 10, type = "group", inline = true, name = "Budget",
						args = {
							hours = {
								order = 1, type = "range", name = "Hours per week",
								desc = "Default weekly budget. It carries over each week - change it any time with /atb hours <n>.",
								min = 0, max = 168, softMax = 60, step = 0.5,
								get = function() return P().hoursBudget end,
								set = function(_, v) ns.ATB:SetHours(v) end,
							},
							overhead = {
								order = 2, type = "range", name = "Per-alt overhead (minutes)",
								desc = "Charged once for each alt the plan uses (log in, fly to the hub). Higher values concentrate the plan on fewer alts.",
								min = 0, max = 60, step = 1,
								get = function() return P().overheadMinutes end,
								set = function(_, v) P().overheadMinutes = v ns.NotifyUpdate("settings") end,
							},
							subtractSpent = {
								order = 3, type = "toggle", name = "Subtract time already spent",
								desc = "Plan only the hours left after chores already completed this week (using their measured or estimated minutes).",
								width = "full",
								get = function() return P().subtractSpent end,
								set = function(_, v) P().subtractSpent = v ns.NotifyUpdate("settings") end,
							},
						},
					},
					alts = {
						order = 20, type = "group", inline = true, name = "Alts",
						args = {
							rolesDesc = {
								order = 0, type = "description",
								name = GREY .. "Each alt has a role (set it in the Alts tab here or in the planner). Main always defaults to priority 1.0. New alts register as Alt - only the very first character in a brand-new database starts as Main, as a convenience.|r\n",
							},
							defaultPriority = {
								order = 1, type = "range", name = "Default priority: Alt role",
								desc = "Priority given to new alts and to alts switched to the Alt role (unless you customized their priority). Existing priorities are never rewritten when you change this.",
								min = 0, max = 2, step = 0.05,
								get = function() return P().defaultAltPriority end,
								set = function(_, v) P().defaultAltPriority = v end,
							},
							defaultProfessionPriority = {
								order = 1.5, type = "range", name = "Default priority: Profession role",
								desc = "Priority given to alts switched to the Profession role (unless you customized their priority). Existing priorities are never rewritten when you change this.",
								min = 0, max = 2, step = 0.05,
								get = function() return P().defaultProfessionPriority end,
								set = function(_, v) P().defaultProfessionPriority = v end,
							},
							loginMessage = {
								order = 2, type = "toggle", name = "Login message",
								desc = "Shortly after login, print one chat line saying whether this alt is in this week's plan.",
								get = function() return P().loginMessage end,
								set = function(_, v) P().loginMessage = v end,
							},
						},
					},
					learning = {
						order = 30, type = "group", inline = true, name = "Time learning",
						args = {
							desc = {
								order = 0, type = "description",
								name = GREY .. "Chores are timed on the active (non-AFK) play clock of the character doing them: from quest accept, dungeon / raid / delve entry, or the Start button, until completion. Samples feed a moving average.|r\n",
							},
							alpha = {
								order = 1, type = "range", name = "Weight of newest sample",
								desc = "Moving-average weight. Higher adapts faster, lower is steadier.",
								min = 0.05, max = 0.9, step = 0.05, isPercent = true,
								get = function() return P().emaAlpha end,
								set = function(_, v) P().emaAlpha = v end,
							},
							cap = {
								order = 2, type = "range", name = "Outlier cap (x default)",
								desc = "Samples longer than this multiple of the default are clamped - more than twice the cap is discarded as stale.",
								min = 1.5, max = 10, step = 0.5,
								get = function() return P().outlierCap end,
								set = function(_, v) P().outlierCap = v end,
							},
							resetAll = {
								order = 3, type = "execute", name = "Reset all learned times",
								confirm = true, confirmText = "Forget every learned chore time?",
								func = function() ns.TimeLearner:ResetAll() end,
							},
						},
					},
				},
			},
			chores = {
				order = 2,
				type = "group",
				name = "Chores",
				childGroups = "tree",
				args = BuildChoresArgs(),
			},
			alts = {
				order = 3,
				type = "group",
				name = "Alts",
				args = BuildAltsArgs(),
			},
		},
	}
end

function Options:Register()
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "AltTimeBudget")
	self.categoryID = categoryID
end

-- Keep an open options panel in sync with edits made in the main window.
ns.RegisterUpdateListener("Options", function(reason)
	if reason == "chores" or reason == "learned" or reason == "reset" or reason == "budget" or reason == "roster" then
		Notify()
	end
end)
