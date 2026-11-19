# User Guide

How to use each addon in this repo. All of them are for the Forever client (Interface 16001).

**Install:** copy the addon folders into `World of Warcraft\_forever_\Interface\AddOns\`, then restart or `/reload`.
**Something broke?** Run `/console scriptErrors 1`, reproduce it, and open an issue with the full error. Every addon also has a debug window (listed below) you can copy from.

| Addon | Open with | One line |
|---|---|---|
| [LevelPace](#levelpace) | `/lp` | Where your leveling time goes, and how to speed up |
| [CraftPath](#craftpath) | `/cpath` | Cheapest next craft for a profession skill-up |
| [AltTimeBudget](#alttimebudget) | `/atb` | Weekly chore plan across your alts |
| [ReturnFromBreak](#returnfrombreak) | `/rfb` | "What was I doing?" after time away |
| [SessionJournal](#sessionjournal) | `/sj` | Diary of every play session |
| [StreamBingo](#streambingo) | `/bingo` | Streamer tool: detects moments for a Twitch bingo app |

---

## LevelPace

Tracks how long you spend on each part of leveling, so you can see where time is wasted.

**Commands**

| Command | What it does |
|---|---|
| `/lp` | Open or close the report window |
| `/lp hud` | Show or hide the small on-screen tracker |
| `/lp lock` | Lock or unlock the HUD (unlocked = drag to move) |
| `/lp reset` | Start a fresh session |
| `/lpdebug` | Debug window |

**What it tracks:** time spent fighting, looting, on foot, mounted, on flight paths, in town, standing idle, dead, and on loading screens. Idle starts after 5 seconds of standing still.

**The report has three tabs**
- **This level:** time buckets, XP per hour (last 10 minutes), estimated time to level, kills to level (from your last 20 kills), XP split between kills, quests and other, XP per hour by zone, and plain-language tips such as "Travel is 40% of your time."
- **Session:** the same for this login.
- **History:** your past levels, to compare pace over time.
- **Advisor:** where to level at your level. It lists the five zones with the most quests left for you (and your own XP per hour there if you've played it), up to eight quests to pick up in the zone you're standing in with who gives them and a clickable **[waypoint]**, and the dungeons and raids that fit your level. Quests you've already done or have in your log are skipped. The data comes from [ForeverDB.net](https://foreverdb.net), and the credit link sits at the bottom of the tab.

**Tips:** let it run for a few minutes before trusting the tips. Time to level and kills to level need some kills to get accurate.

---

## CraftPath

Ranks the recipes you know by cost per skill-up, or plans a whole path from your skill to the cap, with a shopping list.

**Commands**

| Command | What it does |
|---|---|
| `/cpath` | Open or close the planner |
| `/cpath scan` | Re-read recipes from an open profession window |
| `/cpath price [item] 2g 50s` | Set your own price for an item (use for vendor items, shift-click the item into the command). Add `clear` instead of a price to remove it |
| `/cpdebug` | Debug window |

**How to use**
1. Open each profession window once (for example Engineering). CraftPath scans it automatically.
2. Type `/cpath` and click a profession button.
3. The top 10 recipes are ranked by net cost per expected skill-up. Click one to see its shopping list.
4. Change **Crafts to buy for** to size the list (press Enter), and tick or untick **Items in my bags and bank cost nothing**.

**Prices** come from Auctionator if you have it. Reagents with no price (a `*` shows next to the cost) are counted as free, so the cost is too low. Set them with `/cpath price`. Auction sales assume a 5% cut.

**Full path to the cap:** click **Show full path** (bottom left). CraftPath plans every skill point from where you are up to the cap (or the skill you type into **Plan up to skill**, then press Enter). You get a list like "75-95 Linen Bandage x40", plus one shopping list for the whole path. Tick **Include recipes I have not learned yet** to plan with recipes you still need to learn; those are marked with where to learn them. The recipe colors come from ForeverDB.net data bundled with the addon, so the plan works even for recipes you can't see yet.

**Where to buy or gather:** under each item on a shopping list, CraftPath shows where to get it: the cheapest vendor on your side (name, zone and coordinates), or the best zones to gather it (herbs and ore). Click the blue **[waypoint]** link to put a pin on your map. Vendor prices are used automatically, so most vendor reagents no longer need a price set by hand. If both a vendor and Auctionator know an item, the cheaper one is used. For recipes you haven't learned, the plan also says which trainer or vendor teaches it.

**Good to know:** the "next craft" view uses the colors from your last scan, so reopen the profession window after you skill up. Skill-up chances by color are estimates (orange 100%, yellow 75%, green 25%, grey 0%). Items with no vendor, no auction price and no price of your own count as free, so set those with `/cpath price` or the totals will be too low (reagents that drop or come from other crafts are the usual ones). Recipe data is from [ForeverDB.net](https://foreverdb.net).

---

## AltTimeBudget

Plans your weekly chores around the hours you actually have, spread across your characters.

**Commands**

| Command | What it does |
|---|---|
| `/atb` | Open or close the planner |
| `/atb hours 6.5` | Set this week's hour budget |
| `/atb plan` | Print a short plan summary in chat |
| `/atb config` | Open settings (not in combat) |
| `/atb debug` | Debug window |

**How to use**
1. Log in on each alt once so it registers.
2. Give each alt a role in the planner or settings: **Main**, **Alt**, **Profession** (only gets profession chores) or **Bank** (never planned).
3. Set your weekly hours (`/atb hours 6`), then open `/atb` to see the plan: which alts to play and which chores to do on each.
4. Tick chores off as you finish them. Time already spent can be subtracted from the budget.

**Chores:** raids (The Barrow Deeps, Hyjal Summit, Onyxia's Lair) and profession cooldowns come built in, and are checked off by hand. In settings you can edit a chore's minutes and value points, change who may do it, or add your own. The addon learns how long chores take from how long you actually spend.

**Settings worth knowing:** per-alt overhead minutes (a higher number concentrates the plan on fewer alts), alt priority, and a login message that says whether this alt is in the plan.

---

## ReturnFromBreak

One window that answers "what was I doing?" when you log in after time away.

**Commands**

| Command | What it does |
|---|---|
| `/rfb` | Open or close the window |
| `/rfb show` / `/rfb hide` | Open or close explicitly |
| `/rfb config` | Open settings |
| `/rfb resetpos` | Put the window back in the center |
| `/rfbdebug` | Debug window (`/rfbdebug clear` empties it) |

**Sections**
- **Unspent Talents:** points you haven't spent, with an **Open Talents** button.
- **Current Quests:** your quest log at a glance.
- **Since Last Time:** what changed since you last logged out.
- **New Zones:** zones you can now unlock.

**Settings:** show on login (with a delay), lock position, window scale, and how many currency lines to show. **Clear snapshot** resets the "since last time" baseline.

---

## SessionJournal

Writes a diary entry for every play session, from login to logout.

**Commands**

| Command | What it does |
|---|---|
| `/sj` | Open or close the logbook |
| `/sj tracker` | Show or hide the live session tracker |
| `/sj lock` | Lock (click-through) or unlock the tracker |
| `/sj recap` | Open a copyable recap of the current session |
| `/sj config` | Open settings |
| `/sj debug` | Debug window |

**What it records:** time played, zones visited, loot, deaths, gold change, and quests turned in. The live tracker shows elapsed time, current zone, zones visited, loot, deaths and gold as you play.

**Using the logbook:** pick a session to read it, and copy a recap to share or keep. Choose a default recap format in settings.

**Settings:** how many sessions to keep, minimum session length (short ones are skipped), loot quality shown in recaps, loot cap, quest tracking, and whether to request `/played` at session start. **Delete all sessions** wipes the journal.

---

## StreamBingo

For streamers. Detects in-game moments and sends them to a Twitch Stream Bingo companion app through a small pixel strip drawn in a screen corner. Most players don't need this one.

**Commands**

| Command | What it does |
|---|---|
| `/bingo` | Show the help list |
| `/bingo config` | Open settings |
| `/bingo reset` | Reset the session (clears all fired squares) |
| `/bingo test` | List the square keys |
| `/bingo test <key>` | Fire one square by hand, to test |
| `/bingo bridge` | Show or hide the pixel strip |
| `/bingo testmode` | Cycle fake events through the strip |
| `/bingodebug` | Debug window (`/bingodebug clear` empties it) |

**Squares in Forever:** Died to Trash, Boss Wipe, Huge Repair Bill, Epic Loot, Level Up, Fall Damage Death, Boss Killed, One-Shot Boss, Wipe Under 10%. Turn any on or off in settings, and adjust the repair and low-wipe thresholds.

**The pixel strip:** the companion app reads exact colors, so turn off HDR, color-blind filters, gamma tweaks, ReShade and overlays over the strip. Setup details are in [BRIDGE_PROTOCOL.md](BRIDGE_PROTOCOL.md).
