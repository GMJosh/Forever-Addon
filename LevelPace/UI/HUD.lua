-- LevelPace: small always-on HUD (level, ETA, XP per hour, kills to level, what you are doing now)
local addonName, ns = ...

local format = string.format

local M = {}
ns.AddModule(M)

local frame

local function Apply()
	local h = ns.db.hud
	frame:ClearAllPoints()
	frame:SetPoint(h.point, UIParent, h.relPoint, h.x, h.y)
	frame:SetScale(h.scale or 1)
	frame:SetShown(h.shown)
end

local function Build()
	frame = CreateFrame("Frame", "LevelPaceHUD", UIParent)
	frame:SetSize(210, 78)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)

	-- XP bar along the top
	local barBg = frame:CreateTexture(nil, "BORDER")
	barBg:SetPoint("TOPLEFT", 4, -4)
	barBg:SetPoint("TOPRIGHT", -4, -4)
	barBg:SetHeight(8)
	barBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
	frame.bar = frame:CreateTexture(nil, "ARTWORK")
	frame.bar:SetPoint("TOPLEFT", barBg, "TOPLEFT")
	frame.bar:SetHeight(8)
	frame.bar:SetColorTexture(0.58, 0.2, 0.9, 1)

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.text:SetPoint("TOPLEFT", 6, -18)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetSpacing(2)

	frame:SetScript("OnDragStart", function(self)
		if not ns.db.hud.locked then
			frame.moved = true
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local h = ns.db.hud
		h.point, h.relPoint, h.x, h.y = point, relPoint, x, y
	end)
	frame:SetScript("OnMouseDown", function()
		frame.moved = false
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and not frame.moved then
			ns.ToggleReport()
		end
	end)
	Apply()
end

function ns.UpdateHUD()
	if ns.UpdateReport then
		ns.UpdateReport()
	end
	if not frame or not frame:IsShown() then
		return
	end
	local st = ns.XPStats()
	if not st.pct then
		frame.text:SetText(format("Level %d", st.level or 0))
		frame.bar:SetWidth(1)
		return
	end
	frame.bar:SetWidth(math.max(1, (frame:GetWidth() - 8) * st.pct / 100))
	local eta = st.eta and ns.Clock(st.eta) or "--"
	local rate = st.rate and ns.Comma(st.rate) or "--"
	local kills = st.killsLeft and ("~" .. ns.Comma(st.killsLeft)) or "--"
	local b = ns.BUCKET_BY_KEY[ns.currentBucket]
	frame.text:SetText(format("Lv %d   %.1f%%   %s to level\n%s XP/hr   %s kills left\nNow: %s",
		st.level, st.pct, eta, rate, kills, b and b.label or "?"))
	frame:SetHeight(frame.text:GetStringHeight() + 24)
	frame:SetWidth(math.max(210, frame.text:GetStringWidth() + 14))
end

function ns.ToggleHUD()
	ns.db.hud.shown = not ns.db.hud.shown
	if frame then
		frame:SetShown(ns.db.hud.shown)
	end
	ns.Print(ns.db.hud.shown and "HUD shown." or "HUD hidden.")
end

function M.Start()
	Build()
end
