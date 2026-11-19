-- StreamBingo: constants, square registry, AceDB defaults
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.DEBUG_LOG_MAX = 1000

---------------------------------------------------------------------------
-- Pixel bridge protocol constants (see BRIDGE_PROTOCOL.md)
---------------------------------------------------------------------------
ns.PROTOCOL_VERSION = 1
ns.BRIDGE_BLOCK_COUNT = 6
ns.SYNC_COLOR = { 255, 0, 255 }   -- block 0: magenta
ns.END_COLOR = { 0, 255, 255 }    -- block 5: cyan end sentinel

-- Flags byte (block 4, B channel)
ns.FLAG_TEST = 1        -- bit 0: frame came from test mode or /bingo test
ns.FLAG_RESET = 2       -- bit 1: session reset frame (squareID 0)
ns.FLAG_QUEUED = 4      -- bit 2: more frames are waiting in the queue
ns.FLAG_MANUAL = 8      -- bit 3: square fired manually via /bingo test <key>

---------------------------------------------------------------------------
-- Square registry
-- id:       stable numeric ID (1..24). Bit (id - 1) in the bitfield block.
--           NEVER renumber a shipped ID. Append new squares at the end.
-- key:      stable string key used in slash commands and settings.
-- label:    short text for the board.
-- category: "core" | "mplus" | "loot" | "raid"
-- extra:    meaning of the "extra" byte for this square
---------------------------------------------------------------------------
ns.SQUARES = {
	{ id = 1,  key = "trash_death",     category = "core",  label = "Died to Trash",       extra = "instance difficultyID",
		desc = "Player died inside a dungeon/raid/scenario while no boss encounter was active." },
	{ id = 2,  key = "key_timed",       category = "core",  label = "Key Timed",           extra = "keystone level",
		desc = "Mythic+ key completed in time (ChallengeCompletionInfo.onTime)." },
	{ id = 3,  key = "mount_drop",      category = "core",  label = "Mount Drop",          extra = "mount sourceType",
		desc = "A new mount was learned (NEW_MOUNT_ADDED). Optionally only drop-sourced mounts." },
	{ id = 4,  key = "boss_wipe",       category = "core",  label = "Boss Wipe",           extra = "difficultyID",
		desc = "A boss encounter ended without a kill (ENCOUNTER_END success == 0)." },
	{ id = 5,  key = "big_repair",      category = "core",  label = "Huge Repair Bill",    extra = "repair cost in 100g units (capped 255)",
		desc = "Repair All cost was at or above the configured gold threshold." },
	{ id = 6,  key = "key_depleted",    category = "mplus", label = "Key Depleted",        extra = "keystone level",
		desc = "Mythic+ key completed but over time." },
	{ id = 7,  key = "key_upgrade",     category = "mplus", label = "Key +2 / +3",         extra = "upgrade levels",
		desc = "Mythic+ key upgraded by 2 or more levels." },
	{ id = 8,  key = "party_left",      category = "mplus", label = "Someone Left Key",    extra = "group size after leave",
		desc = "A party member left the group during an active Mythic+ key." },
	{ id = 9,  key = "key_deaths",      category = "mplus", label = "Death Fest",          extra = "death count (capped 255)",
		desc = "Party deaths in one key reached the configured threshold." },
	{ id = 10, key = "epic_loot",       category = "loot",  label = "Epic Loot",           extra = "item quality",
		desc = "Player looted an item of Epic quality or better." },
	{ id = 11, key = "great_vault",     category = "loot",  label = "Great Vault",         extra = "0",
		desc = "Player opened the Great Vault." },
	{ id = 12, key = "level_up",        category = "loot",  label = "Level Up",            extra = "new level",
		desc = "Player gained a level." },
	{ id = 13, key = "achievement",     category = "loot",  label = "Achievement",         extra = "0",
		desc = "Player earned an achievement." },
	{ id = 14, key = "fall_death",      category = "loot",  label = "Fall Damage Death",   extra = "0",
		desc = "Player died and the killing blow in the death recap was falling damage." },
	{ id = 15, key = "boss_kill",       category = "raid",  label = "Boss Killed",         extra = "difficultyID",
		desc = "A boss encounter ended in a kill (ENCOUNTER_END success == 1)." },
	{ id = 16, key = "first_pull_kill", category = "raid",  label = "One-Shot Boss",       extra = "difficultyID",
		desc = "Boss killed with no prior wipe on that encounter+difficulty this session." },
	{ id = 17, key = "wipe_low",        category = "raid",  label = "Wipe Under 10%",      extra = "highest boss HP % remaining",
		desc = "Boss wipe where every boss unit had less than the threshold % health left." },
}

ns.MAX_SQUARE_ID = 24 -- bitfield is 3 bytes (24 bits)

-- Forever is Classic (Vanilla) content: no Mythic+, Great Vault, achievements or mount journal.
-- Those squares keep their IDs (the bridge protocol never renumbers) but are removed from the
-- active list, so the board, options and test cycle never show or fire them.
local RETAIL_ONLY = {
	key_timed = true, mount_drop = true, key_depleted = true, key_upgrade = true,
	party_left = true, key_deaths = true, great_vault = true, achievement = true,
}

ns.SQUARES_BY_KEY = {}
ns.SQUARES_BY_ID = {}
local active = {}
for _, sq in ipairs(ns.SQUARES) do
	ns.SQUARES_BY_KEY[sq.key] = sq
	ns.SQUARES_BY_ID[sq.id] = sq
	if not RETAIL_ONLY[sq.key] then
		active[#active + 1] = sq
	end
end
ns.ALL_SQUARES = ns.SQUARES
ns.SQUARES = active

ns.CATEGORY_ORDER = { "core", "loot", "raid" }
ns.CATEGORY_LABELS = {
	core = "Core",
	mplus = "Mythic+ Extras",
	loot = "Loot / Misc Extras",
	raid = "Raid Extras",
}

---------------------------------------------------------------------------
-- AceDB defaults (everything is account-wide under .global)
---------------------------------------------------------------------------
local detectorDefaults = {}
for _, sq in ipairs(ns.ALL_SQUARES) do
	detectorDefaults[sq.key] = true
end

ns.DB_DEFAULTS = {
	global = {
		debugLog = {},
		detectors = detectorDefaults,
		thresholds = {
			repairGold = 5000,
			keyDeaths = 10,
			wipePercent = 10,
			mountDropOnly = true,
			raidSquaresRaidOnly = true,
		},
		bridge = {
			enabled = true,
			parentToWorldFrame = false,
			corner = "TOPLEFT",
			offsetX = 0,
			offsetY = 0,
			blockSize = 4,
			holdTime = 1.5,
			testMode = false,
		},
		board = {
			shown = false,
			locked = false,
			showDisabled = false,
			scale = 1,
			point = { "CENTER", "CENTER", 0, 0 },
		},
		session = {
			startedAt = 0,
			total = 0,
			counts = {},
			wipedEncounters = {},
			recent = {},
		},
	},
}
