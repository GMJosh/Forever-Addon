# Forever-Addon

Addons for the World of Warcraft **Forever** (Classic) client, Interface `16001`.

| Addon | What it does | Commands |
|---|---|---|
| **AltTimeBudget** | Weekly chore planner: set your hours, get a plan across your characters. | `/atb` |
| **ReturnFromBreak** | One window answering "what was I doing?": unspent talents, current quests, what changed. | `/rfb` |
| **LevelPace** | Leveling tracker: where your time goes (travel, idle, town, fighting), time to level, XP per hour, kills to level, best zones. | `/lp` |
| **CraftPath** | Profession leveling planner: cheapest next craft, or a full path to the cap, with a shopping list that says where to buy or gather each item. Uses Auctionator prices and ForeverDB data. | `/cpath` |
| **SessionJournal** | Session logbook: runtime, zones, loot, deaths, gold, with recaps. | `/sj` |
| **StreamBingo** | Detects in-game moments for a Twitch bingo companion app. See `docs/BRIDGE_PROTOCOL.md`. | `/bingo` |

## Install

1. Copy the addon folders you want into `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game or type `/reload`.

Each addon also has a `debug` command that opens a copyable debug window.

**New here?** Read the [User Guide](docs/USER_GUIDE.md) for commands and how to use each addon.

## Status

Early versions, tested in-game by one person. Please open an issue with the full Lua error if something breaks
(`/console scriptErrors 1` shows them).

## Data

CraftPath's data (`CraftPath/Data/`: recipes, vendors, gathering) comes from [ForeverDB.net](https://foreverdb.net). Regenerate it with
`python tools/fetch_recipes.py` (recipes and trainers) and `python tools/fetch_world.py` (vendors and gathering, about 40 minutes) (needs a ForeverDB API key in the `FOREVERDB_KEY` environment variable; the key is never stored in the repo).

## License

MIT. Bundled libraries keep their own licenses.
