# StreamBingo Pixel Bridge Protocol (v1)

WoW addons have no network access. StreamBingo draws a small strip of solid-color blocks on screen, and an external **companion app** screen-captures that strip, decodes it, and forwards events to the Twitch Extension Backend Service (EBS).

- Encoder source: [Modules/Bridge.lua](Modules/Bridge.lua)
- Square registry and constants: [Config.lua](Config.lua)
- Detectors that fire squares: [Modules/Detectors.lua](Modules/Detectors.lua)

## Contents

- [Strip geometry](#strip-geometry)
- [Block layout](#block-layout)
- [Checksum (CRC-8)](#checksum-crc-8)
- [Sequence handling and hold time](#sequence-handling-and-hold-time)
- [Flags byte](#flags-byte)
- [Square ID table](#square-id-table)
- [Color accuracy warnings](#color-accuracy-warnings)
- [Decoder algorithm](#decoder-algorithm)
- [Companion app recommendations](#companion-app-recommendations)
- [Twitch extension recommendations](#twitch-extension-recommendations)

## Strip geometry

| Property | Value |
|---|---|
| Block count | 6, laid out left to right (block 0 is always the leftmost) |
| Block size | `blockSize` **physical pixels** square (default 4, configurable 1-32) |
| Strip size | `6 * blockSize` x `blockSize` physical pixels (default 24 x 4) |
| Anchor | One screen corner (default `TOPLEFT`) plus X/Y offset in physical pixels measured inward from that corner |
| Scale | The strip ignores the parent scale and sets its own scale to `768 / physicalScreenHeight`, so one strip unit equals one physical pixel. The UI Scale slider does not change its size. |
| Strata | `FULLSCREEN_DIALOG`, frame level 9000, mouse disabled |
| Parent | `UIParent` (default; hidden by Alt-Z) or `WorldFrame` (option; survives Alt-Z) |

Blocks are drawn with `Texture:SetColorTexture(r/255, g/255, b/255, 1)`, so every channel is an exact 8-bit value.

## Block layout

Each block carries 3 bytes: R, G, B.

| Block | R | G | B | Notes |
|---|---|---|---|---|
| 0 | 255 | 0 | 255 | **Sync** (magenta). Used to locate the strip. |
| 1 | protocol version (`1`) | sequence number `seq` (0-255) | CRC-8 of the 9 payload bytes | **Header** |
| 2 | `squareID` (0 = none) | `sessionCount` for that square (capped 255) | `extra` (square-specific, 0-255) | **Event** (payload bytes 0-2) |
| 3 | bitfield IDs 1-8 | bitfield IDs 9-16 | bitfield IDs 17-24 | **Fired bitfield** (payload bytes 3-5) |
| 4 | total session events, high byte | total session events, low byte | flags | **Totals** (payload bytes 6-8) |
| 5 | 0 | 255 | 255 | **End sentinel** (cyan). Confirms orientation and block pitch. |

**Bitfield.** Square `id` is fired this session if bit `(id - 1)` is set. Byte 1 (block 3 R) holds bits 0-7 (IDs 1-8), with bit 0 as the least significant bit. Byte 2 (block 3 G) holds IDs 9-16 and byte 3 (block 3 B) holds IDs 17-24.

**Total events** is a 16-bit big-endian integer, `(R << 8) | G`, clamped at 65535.

## Checksum (CRC-8)

CRC-8 with polynomial `0x07`, init `0x00`, no reflection and no final XOR (the "CRC-8/SMBUS" parameters). It is computed over the 9 payload bytes in this order:

```
block2.R, block2.G, block2.B, block3.R, block3.G, block3.B, block4.R, block4.G, block4.B
```

Reference implementation (Python):

```python
def crc8(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc
```

Test vectors:

| Input | CRC |
|---|---|
| ASCII `"123456789"` | `0xF4` (244) |
| `[4, 2, 16, 9, 0, 0, 0, 3, 0]` (square 4 fired a 2nd time, extra 16; IDs 1 and 4 fired; 3 events total) | `0x4F` (79) |
| `[0, 0, 0, 0, 0, 0, 0, 0, 2]` (session reset frame) | `0x0E` (14) |
| all zeros | `0x00` |

The header bytes (version, seq) are **not** included in the CRC. Validate them separately: version must equal 1.

## Sequence handling and hold time

- `seq` increments by 1 (mod 256) **every time a new frame is put on screen**: real events, manual fires, test events and session resets. It is saved in `StreamBingoDB`, so it survives `/reload` and relogs.
- **New event rule.** A decoded frame is a new event when the CRC is valid, `seq != lastSeq`, and `squareID != 0`. A valid frame with `squareID == 0` is a state snapshot: either the boot frame after login or reload, or a reset frame if the `RESET` flag is set.
- **Boot frame.** After login or `/reload`, the strip shows `squareID = 0` with the **current** `seq` (unchanged) and the current session bitfield. Use it to resync the bitfield, not as an event.
- **Hold time.** Every frame stays on screen for at least `holdTime` seconds (default 1.5, configurable 0.25-10). Events that fire during a hold are queued in FIFO order and shown one by one. While more frames are waiting, the `QUEUED` flag is set on the frame being displayed.
- **Missed frames.** If the companion sees `seq` jump by more than 1 (for example, the capture stalled), the events in between are lost as individual events. The bitfield and per-square counts are cumulative, so the companion can still rebuild the session state from the next good frame. Sample at **at least 4x per hold time** (for the default 1.5 s, 3+ samples per second; 10 fps is comfortable).
- **seq wraparound.** 255 to 0 is a normal increment. Treat `(seq - lastSeq) mod 256` as the number of frames advanced.
- **Loading screens.** The strip disappears during loading screens and when the UI is hidden (unless parented to WorldFrame). When it reappears, the first valid frame is either the boot frame or the frame that was showing before.

## Flags byte

Block 4, B channel.

| Bit | Value | Name | Meaning |
|---|---|---|---|
| 0 | 1 | `TEST` | Frame came from bridge test mode. The companion should **not** forward it to viewers, apart from an optional "test" indicator. |
| 1 | 2 | `RESET` | Session reset. `squareID = 0`, empty bitfield, total 0. The companion should start a new round. |
| 2 | 4 | `QUEUED` | More frames are waiting behind this one. |
| 3 | 8 | `MANUAL` | Fired by the streamer with `/bingo test <key>`. Treat it as a real event, because it's a streamer override. |
| 4-7 | | reserved | Always 0 in v1 |

## Square ID table

IDs are stable. New squares will only be appended (up to ID 24 in v1).

**Forever (Classic/Vanilla) build:** squares 2, 3, 6, 7, 8, 9, 11 and 13 (Mythic+, mounts, Great Vault, achievements) are not shown or fired, because the content does not exist there. Their IDs stay reserved.

| ID | Key | Board label | Category | Trigger | `extra` byte |
|---|---|---|---|---|---|
| 1 | `trash_death` | Died to Trash | Core | `PLAYER_DEAD` inside a party/raid/scenario instance while no encounter is active (`ENCOUNTER_START`/`END` window and `C_InstanceEncounter.IsEncounterInProgress`) | instance difficultyID |
| 2 | `key_timed` | Key Timed | Core | `CHALLENGE_MODE_COMPLETED`, `C_ChallengeMode.GetChallengeCompletionInfo().onTime == true` (practice runs ignored) | keystone level |
| 3 | `mount_drop` | Mount Drop | Core | `NEW_MOUNT_ADDED`; by default only mounts whose `C_MountJournal.GetMountInfoByID` sourceType is 1 (Drop) | mount sourceType |
| 4 | `boss_wipe` | Boss Wipe | Core | `ENCOUNTER_END` with `success == 0` inside a PvE instance | difficultyID |
| 5 | `big_repair` | Huge Repair Bill | Core | Repair All cost >= threshold (default 5000g) | cost in units of 100g, capped 255 |
| 6 | `key_depleted` | Key Depleted | M+ | `CHALLENGE_MODE_COMPLETED` with `onTime == false` | keystone level |
| 7 | `key_upgrade` | Key +2 / +3 | M+ | `keystoneUpgradeLevels >= 2` | upgrade levels |
| 8 | `party_left` | Someone Left Key | M+ | `GROUP_ROSTER_UPDATE` with fewer members during an active key (not when the player leaves) | group size after the leave |
| 9 | `key_deaths` | Death Fest | M+ | `C_ChallengeMode.GetDeathCount()` reaches the threshold (default 10), once per key | death count |
| 10 | `epic_loot` | Epic Loot | Loot | Player receives an item of Epic quality or higher (Heirloom and WoW Token excluded) via `SHOW_LOOT_TOAST`, `LOOT_ITEM_ROLL_WON` or `CHAT_MSG_LOOT` | item quality (4 Epic, 5 Legendary, 6 Artifact) |
| 11 | `great_vault` | Great Vault | Loot | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Enum.PlayerInteractionType.WeeklyRewards`, debounced to 60 s | 0 |
| 12 | `level_up` | Level Up | Loot | `PLAYER_LEVEL_UP` | new level |
| 13 | `achievement` | Achievement | Loot | `ACHIEVEMENT_EARNED` where `alreadyEarned` is not true | 0 |
| 14 | `fall_death` | Fall Damage Death | Loot | `PLAYER_DEAD`, then the newest `C_DeathRecap.GetRecapEvents()` entry is `ENVIRONMENTAL_DAMAGE` / `FALLING` | 0 |
| 15 | `boss_kill` | Boss Killed | Raid | `ENCOUNTER_END` with `success == 1` (raid instances only by default) | difficultyID |
| 16 | `first_pull_kill` | One-Shot Boss | Raid | Kill with no earlier wipe on the same encounterID + difficulty this session | difficultyID |
| 17 | `wipe_low` | Wipe Under 10% | Raid | `ENCOUNTER_END` wipe where the highest `encounterUnitStatus[].remainingHealthPercent` is below the threshold (default 10) | highest remaining HP %, floored |

A single in-game moment can fire more than one square. For example, a first-pull raid kill fires 15 and then 16, and a timed +3 fires 2 and then 7. Each square is queued as its own frame.

## Color accuracy warnings

The protocol depends on **exact** 8-bit colors. All of these can break it:

- **HDR** output (Windows HDR or in-game HDR) and **Auto HDR**.
- **Color-blind filters** (in-game Accessibility settings or the OS), **gamma/brightness/contrast** sliders other than the defaults, NVIDIA/AMD color filters, ReShade, and Night Light / f.lux.
- **Video encoding.** Never decode from the Twitch stream itself. Chroma subsampling (4:2:0) and compression destroy small colored blocks. Capture the game window or monitor locally.
- **Scaling.** Capture at native resolution. Windowed-mode DPI scaling or capture-card scaling resamples pixels and blends block edges.
- **Overlays.** Discord, Steam, NVIDIA, and OBS-in-game overlays drawn over the corner.

Mitigations:

- Sample **block centers only**: pixel `(x0 + i*S + S/2, y0 + S/2)`, where S is the block size. Edges may be anti-aliased or blended.
- Use a block size of at least 4 px. Use 6-8 px if capture is unreliable.
- Allow a small tolerance (for example +/-2 per channel) when **locating** the sync and end blocks. **Payload bytes must still match exactly**, and the CRC will reject bad reads.
- Use test mode (`/bingo testmode`) to check a setup: the companion should decode every square in turn with the `TEST` flag set.

## Decoder algorithm

1. Capture the configured corner region at native resolution (a 64x64 region is plenty for defaults).
2. Find a pixel near (255, 0, 255). Measure its run length horizontally to get `S` (block size), or use the configured size.
3. Check that block 5 (`x0 + 5*S + S/2`) is near (0, 255, 255). If it isn't, the strip wasn't found.
4. Read blocks 1-4 at their centers. Require `version == 1` and `crc8(payload) == header.B`.
5. If valid and `seq != lastSeq`:
   - `RESET` flag set: start a new round and clear the companion state.
   - `TEST` flag set: optionally show a test indicator and stop.
   - `squareID != 0`: emit event `{squareID, count, extra, manual: flags & 8}`.
   - Always replace the companion's fired-set with the bitfield (it is authoritative).
6. Set `lastSeq = seq`.

## Companion app recommendations

- **Screen capture.**
  - Windows: use the **Windows.Graphics.Capture** API (works with borderless windowed and has low overhead) or **DXGI Desktop Duplication** for full-screen exclusive. Capture only the corner rectangle.
  - Cross-platform prototypes can use Python with `mss` (region grab) and `numpy`. For production, use .NET or Rust with WGC.
  - An OBS plugin or OBS script that reads the game-capture source texture also works and avoids a second capture pipeline. Crop the strip out of the broadcast output with a crop filter.
- Poll at 10 Hz. Debounce on `seq`, not on color changes.
- Keep a local log of every decoded event (timestamp, seq, squareID, count, extra, flags) for disputes.
- **Forward to the backend.** The companion authenticates to your **EBS** (Extension Backend Service) with a streamer-specific secret issued during an OAuth pairing flow, and POSTs events over HTTPS. Never ship the extension secret inside the companion.
- **EBS to viewers.** The EBS signs a JWT with the extension secret and calls the Twitch **Extensions "Send Extension PubSub Message"** endpoint (`POST https://api.twitch.tv/helix/extensions/pubsub`) with `target: ["broadcast"]` for the channel. Twitch rate-limits this per channel (about 1 message per second), so batch bursts into one message (`{events:[...], bitfield, seq}`). Payloads are limited to 5 KB.
- Include the full fired bitfield in every broadcast, so viewers who join mid-stream (or miss a message) can rebuild state. Also expose a `GET /state/:channelId` endpoint on the EBS for the initial load.

## Twitch extension recommendations

- **Card generation per viewer.**
  - The EBS generates each card deterministically from `HMAC(roundId, opaqueUserId or userId)`. That gives a stable card per viewer per round, and it can be verified server-side.
  - Pick 24 squares (5x5 with a FREE center) from the enabled square IDs, plus streamer-defined custom squares if wanted. With only 17 detector squares, either allow duplicates weighted by expected frequency, or use a 4x4 card.
  - Weight rare squares (One-Shot Boss, Mount Drop) into fewer cards.
- **Win detection.**
  - Server-authoritative. On every event, the EBS recomputes each active card against the fired set: rows, columns, and both diagonals, with the FREE center counting as marked.
  - The **first** card to complete a full line wins. Order ties by the EBS receive time of the event that completed them, and mark simultaneous completers as co-winners.
  - Never trust a client-side "BINGO" claim. The client may *display* local marks, but the EBS decides.
- **Shoutout hook.**
  - On a win, the EBS broadcasts a `winner` PubSub message (display name, if the viewer shared identity) for an in-panel celebration.
  - Optionally post to chat with **Send Extension Chat Message** (`POST /helix/extensions/chat`), and/or trigger a Helix **Send a Shoutout** or channel-point / EventSub flow that the streamer has authorized.
  - Rate-limit winner announcements and require identity-linked viewers (`opaque_user_id` starting with `U`) for prizes.
- **Round lifecycle.** A `RESET` frame (from `/bingo reset` or the board's Reset Session button) starts a new round. The EBS archives the old round and issues new cards.
