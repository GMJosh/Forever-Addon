-- ReturnFromBreak: New Zones data (YOU fill this in)
--
-- Each entry describes one zone and how to unlock / reach it. The "New Zones"
-- section lists every entry whose unlock quest is NOT yet completed on this
-- character, with a "Waypoint" button that drops a map pin on the quest giver.
--
-- SCHEMA (one table per zone)
-- ---------------------------------------------------------------------------
--   name          string   REQUIRED  Display name of the zone, e.g. "Some Zone".
--   uiMapID       number   optional  The zone's own uiMapID. Used to show the real
--                                    map name in the tooltip. Find it in-game with
--                                    /dump C_Map.GetBestMapForUnit("player") while
--                                    standing in the zone.
--   unlockQuestID number   optional  The breadcrumb / unlock quest. When
--                                    C_QuestLog.IsQuestFlaggedCompleted(id) is true
--                                    the entry is hidden. Without it, the entry is
--                                    always shown.
--   questGiver    string   optional  NPC name that offers the unlock quest.
--   startMapID    number   optional  uiMapID of the map the quest giver stands on
--                                    (often a city map, not the continent).
--   x, y          number   optional  Quest giver coordinates on startMapID, using the
--                                    0-100 scale shown by coordinate addons / TomTom
--                                    (e.g. x = 45.2, y = 61.8). The Waypoint button
--                                    needs startMapID, x and y.
--   note          string   optional  Short hint, e.g. "Requires level 83" or
--                                    "Talk to the flight master first".
--   example       boolean  optional  true = placeholder, never shown. Delete this
--                                    field (or set it to false) on real entries.
-- ---------------------------------------------------------------------------
--
-- Tips:
--   * Get coordinates: stand on the NPC and run
--       /dump C_Map.GetBestMapForUnit("player"), C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
--     The x/y it prints are 0-1. Multiply by 100 for this file.
--   * Get a quest ID: Wowhead URL (wowhead.com/quest=XXXXX) or
--       /dump C_SuperTrack.GetSuperTrackedQuestID()  while the quest is focused.
--   * Edit this file, then /reload in game.
--
-- The schema works for any zone. Add your own Classic zones below.

local addonName, ns = ...

ns.Zones = {
	-- EXAMPLE ENTRY. It is ignored because example = true. Copy it, fill in real
	-- values, and remove the example line.
	{
		example = true,
		name = "EXAMPLE - Zone Name",
		uiMapID = 0,
		unlockQuestID = 0,
		questGiver = "EXAMPLE - Quest Giver Name",
		startMapID = 0,
		x = 50.0,
		y = 50.0,
		note = "EXAMPLE - Replace with a short hint (level requirement, prerequisites, etc.)",
	},

	-- Second EXAMPLE showing the minimum useful entry (name + waypoint only).
	{
		example = true,
		name = "EXAMPLE - Minimal Entry",
		startMapID = 0,
		x = 0,
		y = 0,
	},

	-- Add real zones below this line:

}
