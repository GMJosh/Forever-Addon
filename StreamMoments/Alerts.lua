-- StreamMoments: the on-screen banner. One banner at a time, with a short queue.
local addonName, ns = ...

local tremove = table.remove

local banner
local queue = {}
local showing = false
local token = 0 -- guards against an old hide timer closing a newer banner

local function Sound(kind, override)
	if not ns.db.sound or not SOUNDKIT then
		return
	end
	local id = override
	if not id then
		if kind == "loot" then
			id = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST
		elseif kind == "boss" then
			id = SOUNDKIT.UI_RAID_BOSS_DEFEATED
		elseif kind == "death" then
			id = SOUNDKIT.UI_BNET_TOAST
		else
			id = SOUNDKIT.IG_QUEST_LIST_COMPLETE
		end
	end
	if id and PlaySound then
		PlaySound(id)
	end
end

function ns.ApplyBanner()
	if not banner then
		return
	end
	local bg = ns.BACKGROUNDS[ns.db.background] or ns.BACKGROUNDS.dark
	banner.back:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
	banner:SetScale(ns.db.scale)
	-- text is readable on every background; on solid chroma colors it gets a dark outline
	local solid = ns.db.background == "green" or ns.db.background == "magenta"
	banner.title:SetShadowColor(0, 0, 0, solid and 1 or 0.8)
	banner.subtitle:SetShadowColor(0, 0, 0, solid and 1 or 0.8)
end

local function Build()
	banner = CreateFrame("Frame", "StreamMomentsBanner", UIParent)
	banner:SetSize(460, 84)
	banner:SetFrameStrata("TOOLTIP")
	banner:SetMovable(true)
	banner:SetClampedToScreen(true)
	banner:RegisterForDrag("LeftButton")
	banner:SetScript("OnDragStart", banner.StartMoving)
	banner:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local b = ns.db.banner
		b.point, b.relPoint, b.x, b.y = point, relPoint, x, y
	end)
	local pos = ns.db.banner
	banner:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

	banner.back = banner:CreateTexture(nil, "BACKGROUND")
	banner.back:SetAllPoints()
	banner.accent = banner:CreateTexture(nil, "BORDER")
	banner.accent:SetPoint("TOPLEFT")
	banner.accent:SetPoint("BOTTOMLEFT")
	banner.accent:SetWidth(8)
	banner.icon = banner:CreateTexture(nil, "ARTWORK")
	banner.icon:SetSize(56, 56)
	banner.icon:SetPoint("LEFT", 20, 0)
	banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	banner.title:SetJustifyH("LEFT")
	banner.title:SetShadowOffset(1, -1)
	banner.subtitle = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	banner.subtitle:SetJustifyH("LEFT")
	banner.subtitle:SetShadowOffset(1, -1)

	banner.fadeIn = banner:CreateAnimationGroup()
	local a = banner.fadeIn:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(0.25)
	banner.fadeIn:SetScript("OnFinished", function()
		banner:SetAlpha(1)
	end)
	banner.fadeOut = banner:CreateAnimationGroup()
	local b = banner.fadeOut:CreateAnimation("Alpha")
	b:SetFromAlpha(1)
	b:SetToAlpha(0)
	b:SetDuration(0.5)
	banner.fadeOut:SetScript("OnFinished", function()
		banner:SetAlpha(0)
		banner:Hide()
		showing = false
		ns.NextBanner()
	end)

	banner:SetAlpha(0)
	banner:Hide()
	ns.ApplyBanner()
	ns.SetLocked(ns.db.locked, true)
end

local function Fill(m)
	local c = m.color
	banner.accent:SetColorTexture(c[1], c[2], c[3], 1)
	banner.title:SetTextColor(c[1], c[2], c[3])
	banner.subtitle:SetTextColor(1, 1, 1)
	banner.title:SetText(m.title)
	banner.subtitle:SetText(m.subtitle)
	banner.title:ClearAllPoints()
	banner.subtitle:ClearAllPoints()
	local left = 20
	if m.icon then
		banner.icon:SetTexture(m.icon)
		banner.icon:Show()
		left = 86
	else
		banner.icon:Hide()
	end
	banner.title:SetPoint("TOPLEFT", left, -14)
	banner.title:SetPoint("RIGHT", -14, 0)
	banner.subtitle:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -6)
	banner.subtitle:SetPoint("RIGHT", -14, 0)
end

local function Play(m)
	showing = true
	token = token + 1
	local mine = token
	Fill(m)
	banner:SetAlpha(0)
	banner:Show()
	banner.fadeOut:Stop()
	banner.fadeIn:Play()
	Sound(m.kind, m.sound)
	C_Timer.After(ns.db.duration, function()
		if token == mine and banner:IsShown() then
			banner.fadeOut:Play()
		end
	end)
end

function ns.NextBanner()
	if showing or not banner or not ns.db.locked then
		return
	end
	local m = tremove(queue, 1)
	if m then
		Play(m)
	end
end

function ns.ShowBanner(m)
	if not banner then
		return
	end
	if #queue >= ns.QUEUE_MAX then
		ns.Debug("Banner queue full, kept in the log only:", m.title)
		return
	end
	queue[#queue + 1] = m
	ns.NextBanner()
end

-- Unlocked: a sample banner stays up so you can drag it. Locked: click-through, normal behavior.
function ns.SetLocked(locked, silent)
	ns.db.locked = locked and true or false
	if not banner then
		return
	end
	banner:EnableMouse(not locked)
	if not locked then
		token = token + 1
		banner.fadeIn:Stop()
		banner.fadeOut:Stop()
		showing = true
		Fill({ title = "Drag me", subtitle = "Type /sm lock when it is where you want it", color = { 1, 0.6, 0.2 } })
		banner:SetAlpha(1)
		banner:Show()
		if not silent then
			ns.Print("Banner unlocked. Drag it, then type /sm lock.")
		end
	else
		banner:Hide()
		banner:SetAlpha(0)
		showing = false
		if not silent then
			ns.Print("Banner locked.")
		end
		ns.NextBanner()
	end
end

local SAMPLES = {
	level = { "LEVEL 20!", "Took 1h 12m 05s" },
	loot = { "|cffa335eeSample Epic Sword|r", "Epic drop" },
	boss = { "Boss defeated", "Sample Boss, down in 4m 12s" },
	death = { "YOU DIED", "Death #3 this session" },
	skill = { "Engineering 150", "Journeyman reached" },
	rare = { "Rare slain", "Sample Rare Beast" },
	zone = { "DISCOVERED", "Sample Zone (+150 XP)" },
}

function ns.TestMoment(kind)
	local list = {}
	if kind and SAMPLES[kind] then
		list[1] = kind
	elseif kind then
		ns.Print("Unknown type. Try level, loot, boss, death, skill, rare or zone.")
		return
	else
		for _, t in ipairs(ns.TYPES) do
			list[#list + 1] = t.key
		end
	end
	if not ns.db.locked then
		ns.Print("Lock the banner first (/sm lock), then test.")
		return
	end
	for _, k in ipairs(list) do
		ns.Moment(k, SAMPLES[k][1], SAMPLES[k][2], { test = true, icon = k == "loot" and "Interface\\Icons\\INV_Sword_04" or nil })
	end
end

ns.On("PLAYER_LOGIN", Build)
