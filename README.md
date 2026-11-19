# Forever-Addon

Addons for the World of Warcraft **Forever** (Classic) client, Interface `16001`.

| Addon | What it does | Commands |
|---|---|---|
| **AltTimeBudget** | Weekly chore planner: set your hours, get a plan across your characters. | `/atb` |
| **ReturnFromBreak** | One window answering "what was I doing?": unspent talents, current quests, what changed. | `/rfb` |
| **SessionJournal** | Session logbook: runtime, zones, loot, deaths, gold, with recaps. | `/sj` |
| **StreamBingo** | Detects in-game moments for a Twitch bingo companion app. See `docs/BRIDGE_PROTOCOL.md`. | `/bingo` |

## Install

1. Copy the addon folders you want into `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game or type `/reload`.

Each addon also has a `debug` command that opens a copyable debug window.

## Status

Early versions, tested in-game by one person. Please open an issue with the full Lua error if something breaks
(`/console scriptErrors 1` shows them).

## License

MIT. Bundled libraries keep their own licenses.
