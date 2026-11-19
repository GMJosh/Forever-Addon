-- StreamBingo: pixel bridge encoder
-- Renders a horizontal strip of solid-color blocks that an external companion app
-- screen-captures. Full spec: BRIDGE_PROTOCOL.md
--
--   block 0  sync      (255, 0, 255)
--   block 1  header    (protocolVersion, seq, crc8(payload))
--   block 2  event     (squareID, sessionCount, extra)
--   block 3  bitfield  (IDs 1-8, IDs 9-16, IDs 17-24)
--   block 4  totals    (totalHi, totalLo, flags)
--   block 5  end       (0, 255, 255)
--
-- The strip is a plain (non-secure) frame, so Show/Hide/SetPoint are safe in combat.
local addonName, ns = ...

local Debug = ns.Debug
local Bridge = ns.SB:NewModule("Bridge", "AceEvent-3.0")
ns.Bridge = Bridge

local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift
local floor = math.floor
local max = math.max
local min = math.min
local tinsert = table.insert
local tremove = table.remove
local GetPhysicalScreenSize = GetPhysicalScreenSize
local C_Timer = C_Timer
local ipairs = ipairs
local wipe = wipe

local strip            -- the strip frame
local blocks = {}      -- textures, index 0..BLOCK_COUNT-1
local queue = {}       -- pending frames
local holding = false  -- true while the current frame is inside its hold window
local current          -- frame currently displayed
local testTicker
local testCounts = {}
local testTotal = 0
local testIndex = 0

---------------------------------------------------------------------------
-- Checksum: CRC-8, polynomial 0x07, init 0x00, no reflection, no final XOR
---------------------------------------------------------------------------
local function CRC8(bytes)
	local crc = 0
	for _, b in ipairs(bytes) do
		crc = bxor(crc, b)
		for _ = 1, 8 do
			if band(crc, 0x80) ~= 0 then
				crc = band(bxor(lshift(crc, 1), 0x07), 0xFF)
			else
				crc = band(lshift(crc, 1), 0xFF)
			end
		end
	end
	return crc
end
ns.CRC8 = CRC8

---------------------------------------------------------------------------
-- Frame building
---------------------------------------------------------------------------

local function GetParentFrame()
	if ns.db.bridge.parentToWorldFrame then
		return WorldFrame
	end
	return UIParent
end

-- Scale the strip so 1 strip unit == 1 physical pixel, independent of UI scale.
local function ApplyPixelScale()
	if not strip then return end
	local _, physH = GetPhysicalScreenSize()
	if not physH or physH <= 0 then return end
	strip:SetIgnoreParentScale(true)
	strip:SetScale(768 / physH)
end

local CORNER_SIGNS = {
	TOPLEFT = { 1, -1 },
	TOPRIGHT = { -1, -1 },
	BOTTOMLEFT = { 1, 1 },
	BOTTOMRIGHT = { -1, 1 },
}

function Bridge:ApplyLayout()
	if not strip then return end
	local cfg = ns.db.bridge
	local size = max(1, floor(cfg.blockSize or 4))
	local parent = GetParentFrame()
	if strip:GetParent() ~= parent then
		strip:SetParent(parent)
	end
	strip:SetFrameStrata("FULLSCREEN_DIALOG")
	strip:SetFrameLevel(9000)
	ApplyPixelScale()

	local corner = CORNER_SIGNS[cfg.corner] and cfg.corner or "TOPLEFT"
	local signs = CORNER_SIGNS[corner]
	strip:ClearAllPoints()
	strip:SetPoint(corner, parent, corner, signs[1] * floor(cfg.offsetX or 0), signs[2] * floor(cfg.offsetY or 0))
	strip:SetSize(size * ns.BRIDGE_BLOCK_COUNT, size)

	for i = 0, ns.BRIDGE_BLOCK_COUNT - 1 do
		local tex = blocks[i]
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", strip, "TOPLEFT", i * size, 0)
		tex:SetSize(size, size)
	end
end

local function CreateStrip()
	strip = CreateFrame("Frame", "StreamBingoBridgeFrame", GetParentFrame())
	strip:EnableMouse(false)
	strip:SetAlpha(1)
	strip:SetIgnoreParentAlpha(true)
	for i = 0, ns.BRIDGE_BLOCK_COUNT - 1 do
		local tex = strip:CreateTexture(nil, "OVERLAY")
		tex:SetSnapToPixelGrid(true)
		tex:SetTexelSnappingBias(0)
		tex:SetColorTexture(0, 0, 0, 1)
		blocks[i] = tex
	end
	Bridge:ApplyLayout()
end

local function SetBlock(i, r, g, b)
	blocks[i]:SetColorTexture(r / 255, g / 255, b / 255, 1)
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

-- Returns the 6 RGB triplets for a frame (also used by tests / docs).
function Bridge:Encode(f, seq)
	local total = max(0, min(65535, f.total or 0))
	local payload = {
		f.id, f.count, f.extra,
		f.b1, f.b2, f.b3,
		rshift(total, 8), band(total, 0xFF), f.flags,
	}
	local crc = CRC8(payload)
	return {
		ns.SYNC_COLOR,
		{ ns.PROTOCOL_VERSION, seq, crc },
		{ payload[1], payload[2], payload[3] },
		{ payload[4], payload[5], payload[6] },
		{ payload[7], payload[8], payload[9] },
		ns.END_COLOR,
	}
end

local function Render(f)
	current = f
	if not strip then return end
	local triplets = Bridge:Encode(f, ns.db.bridgeSeq or 0)
	for i = 0, ns.BRIDGE_BLOCK_COUNT - 1 do
		local c = triplets[i + 1]
		SetBlock(i, c[1], c[2], c[3])
	end
end

local function MakeFrame(id, count, extra, flags, counts, total)
	local b1, b2, b3 = ns.GetBitfieldBytes(counts)
	return {
		id = id or 0,
		count = max(0, min(255, count or 0)),
		extra = max(0, min(255, extra or 0)),
		flags = flags or 0,
		b1 = b1, b2 = b2, b3 = b3,
		total = total or (ns.db.session.total or 0),
	}
end

local Pump

local function OnHoldExpired()
	holding = false
	Pump()
end

Pump = function()
	if holding or #queue == 0 then
		return
	end
	local f = tremove(queue, 1)
	if #queue > 0 then
		f.flags = f.flags + ns.FLAG_QUEUED
	end
	ns.db.bridgeSeq = ((ns.db.bridgeSeq or 0) + 1) % 256
	Render(f)
	Debug:Log("Bridge frame seq=" .. ns.db.bridgeSeq, "id=" .. f.id, "count=" .. f.count,
		"extra=" .. f.extra, "flags=" .. f.flags, "queued=" .. #queue)
	holding = true
	C_Timer.After(max(0.2, ns.db.bridge.holdTime or 1.5), OnHoldExpired)
end

function Bridge:PushEvent(id, count, extra, flags)
	tinsert(queue, MakeFrame(id, count, extra, flags))
	Pump()
end

function Bridge:PushReset()
	tinsert(queue, MakeFrame(0, 0, 0, ns.FLAG_RESET))
	Pump()
end

---------------------------------------------------------------------------
-- Visibility / settings
---------------------------------------------------------------------------

function Bridge:UpdateVisibility()
	local cfg = ns.db.bridge
	local want = cfg.enabled or cfg.testMode
	if want and not strip then
		CreateStrip()
		Render(current or MakeFrame(0, 0, 0, 0))
	end
	if strip then
		strip:SetShown(want and true or false)
	end
end

function Bridge:Toggle()
	ns.db.bridge.enabled = not ns.db.bridge.enabled
	self:UpdateVisibility()
	return ns.db.bridge.enabled
end

function Bridge:SetEnabled(on)
	ns.db.bridge.enabled = on and true or false
	self:UpdateVisibility()
end

local function TestTick()
	testIndex = testIndex % #ns.SQUARES + 1
	local sq = ns.SQUARES[testIndex]
	testCounts[sq.id] = (testCounts[sq.id] or 0) + 1
	testTotal = testTotal + 1
	tinsert(queue, MakeFrame(sq.id, testCounts[sq.id], testIndex, ns.FLAG_TEST, testCounts, testTotal))
	Pump()
end

function Bridge:SetTestMode(on)
	ns.db.bridge.testMode = on and true or false
	if testTicker then
		testTicker:Cancel()
		testTicker = nil
	end
	if ns.db.bridge.testMode then
		wipe(testCounts)
		testTotal = 0
		testIndex = 0
		local interval = max(1, (ns.db.bridge.holdTime or 1.5) * 2)
		testTicker = C_Timer.NewTicker(interval, TestTick)
		Debug:Log("Bridge test mode ON, interval", interval)
	else
		Debug:Log("Bridge test mode OFF")
	end
	self:UpdateVisibility()
	return ns.db.bridge.testMode
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Bridge:OnEnable()
	ns.RegisterEventSafe(self, "UI_SCALE_CHANGED", "OnDisplayChanged")
	ns.RegisterEventSafe(self, "DISPLAY_SIZE_CHANGED", "OnDisplayChanged")

	-- Boot frame: squareID 0, current session bitfield, so the companion can resync.
	current = MakeFrame(0, 0, 0, 0)
	self:UpdateVisibility()
	if ns.db.bridge.testMode then
		self:SetTestMode(true)
	end
	Debug:Log("Bridge enabled, seq=" .. (ns.db.bridgeSeq or 0))
end

function Bridge:OnDisplayChanged()
	self:ApplyLayout()
end
