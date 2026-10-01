# Vault Runners 💎 — marketing: clip list, thumbnails, rules

Not published. No Roblox experience exists for this game yet, so there is no live link, no media and no
`marketing/` folder. Everything below is what to film once the night shift has a place to film it in.

## The rules (docs/complete-game-standard.md §4-§5, read first)

- Marketing starts **only after the game is live**, spread over a day and the next, one game at a time, in
  communities whose rules allow self-promotion, and **labelled as AI-assisted** (r/RobloxDevelopers rule 6).
- Studio, thumbnails, clips and publishing belong to the night shift (00:00-06:00,
  `C:\Users\bahs_admin\.claude\scheduled-tasks\roblox-night-shift\SKILL.md`).
- Clips are filmed with `tools/film_game.py` (real Studio viewport, `--source capture`), vertical
  **1080x1920**, **7-15 s**. A clip may stage only where the character starts, the camera, and codes every
  player gets (this game has none). It **never edits the game's numbers** and never fakes progress. Each
  clip's staging goes into `marketing/clips/manifest.json`.
- **`tools/film_game.py` has no Vault Runners scenarios yet** (`GAMES` is plus1, crystal, laby). Every clip
  below is "add": `tools/` belongs to the tools owner, so the night shift adds a `VAULT` table there.
- Never film the Friends view of the board with a real account: it shows real friends' usernames.

## What a fresh Studio session can show, and what it cannot

EYECANDY.md §9 step 2 turns Studio's API access OFF, so every Play session is a **new player: Bronze floor 1,
nothing banked**, and Bronze floor 1 is the **Bank Vault** (depth 1). That covers the core loop: the portal,
the maze, the crumbling pads, the collapse, the drop, the escape, the rest. It does **not** reach the Pyramid
Tomb (depth 5), the Reactor Core (14), the Frozen Vault (18, the brag), the Volcano Temple (40) or the board's
rows: EYECANDY §9 reaches those by editing `Config` in a Studio-only copy, which is fine for a still and is
exactly what a clip may not do. So the deep strata and the board are filmed **after publishing**, on the live
server, with an account that really got there (marked HELD below).

Coordinates are for `WorldSeed 20260909`, the first vault slot (origin (0, 200, 0)), and come from EYECANDY.md
§9, recomputed from `VaultFloor.build`. Bronze floor 1 is a 4x4 maze over three storeys, countdown 79 s. Storey
s's floor top is y = 200 + 18 s. Storey 0's stairwell is the cell centred at (36, 200, 36); its six pads' tops
run (40, 203, 40) to (32, 218, 40).

## Clip list (vertical 1080x1920, 7-15 s)

| # | Clip | Length | What the viewer sees | Staging | Scenario |
|---|---|---|---|---|---|
| 1 | `portal_drop` | 8 s | the hub at night: three glowing portals and the round vault door behind them; one real click on the Bronze portal; the avatar drops into a fresh maze, the countdown appears and starts | fresh session; avatar on the spawn pad, (0, 3, 0), facing -Z; camera behind and above, (0, 9, 18) looking at (-22, 7, -22); record the real click on `workspace.Hub.Portal_1` (its ClickDetector, by `instance_path`) | add |
| 2 | `crumbling_leap` | 12 s | six 3x3 marble pads spiralling up a stairwell, five studs of air between them; the avatar hops pad to pad; each pad cracks red-orange behind it and falls away with debris; in the corridor behind, a rat runs its loop (the Bank Vault's critters, EYECANDY §2.5) | fresh session, Bronze run; teleport to (24, 204, 36), just west of the stairwell, as the run starts; camera in the corridor at about (20, 210, 36) looking at (36, 211, 36); the climb is real input (`hop()` pad to pad) | add |
| 3 | `missed_hop` | 9 s | a hop falls short: the avatar drops back to the storey floor, the pads it used are gone or going, the countdown keeps running, and it starts again at pad 1 | as 2; on pad 3 give a deliberately short hop (W held for about half of `hop()`'s time) so the miss is real; keep the HUD on so the timer shows | add |
| 4 | `collapse_rising` | 12 s | looking down the hole from storey 1: the red kill plane sweeps up through storey 0's shaft, sparks off it, ceiling dust pouring, the grade warming toward red | fresh session, Bronze run, shipped config (EYECANDY §9 shot 6 variant); teleport to storey 1 beside the hole, (24, 222, 36), and look down into (36, 218, 36); the plane reaches storey 1 at about 52 s and ends the run, so record from about 37 s to 49 s of the run | add |
| 5 | `ceiling_drop` | 10 s | a crack opens overhead, the yellow ring follows the runner, turns coral red and locks, the runner keeps moving, and the slab crashes down behind them | a long take, cut by hand: drops come about once every 2.3-2.6 minutes of RUN time and never in a run's first 12 s, so record several Bronze runs back to back (record up to 6 minutes) with the runner walking the maze; camera default third-person, pitched up so the ceiling is in frame. Do not shorten `Config.Hazards` for it | add |
| 6 | `escape_banked` | 9 s | the runner reaches the exit pad on the top storey with gems; the countdown stops; "Banked N gems - Bronze floor 1 cleared!"; back in the hub | fresh session, Bronze run; walk the real route (the server's `Trace` follows at runner speed, so a teleport to the exit does not bank: walk the last stretch); record the last 9 s | add |
| 7 | `hub_rest` | 8 s | back in the hub: a tap on Rest, the avatar sits, the view softens, the chip says "Resting" | after clip 6, in the hub; camera (0, 9, 18) looking at the avatar; record the real click on the Rest button | add |
| 8 | `frozen_vault` | 12 s | the brag: an ice-blue vault, snow falling, icicles, three aurora ribbons over the top storey, an amethyst gem glowing in an ice corridor | **HELD until published.** Needs a profile that really escaped Bronze floor 17 (the Frozen Vault starts at depth 18: about 40 minutes of play) on the live server; then the same framing as EYECANDY §9 shot 5 on the floor it is on. Never with Config edited | add, after publishing |
| 9 | `board_turnaround` | 8 s | from the spawn the runner turns west to the DEEPEST ESCAPES sign: rows of names with depths and their strata (❄️, 🌋); press E: FRIENDS | **HELD until published.** In Studio with API access off the sign says it is offline (correct, and not worth filming). On the live server, film the PUBLIC view only, or a test account with no friends (its friends view says what an empty one says). Camera (-4, 7, 10) looking at the sign at (-18, 5.5, 4) | add, after publishing |

Two more if there is time: the **Volcano Temple's halls** (Gold floors past depth 44, a hall card on each new
hall; only with a real long-played profile), and **a Silver unlock** (the Silver portal's sign turning from
locked to `Floor 1 · ...` after a real escape banks the last gems; Silver unlocks after about 90 minutes of play
for the normal player of `tests/Pacing.spec.luau`, so this one is also best filmed on the live server).

## Thumbnail and icon

The shot list is `EYECANDY.md` §9 (seven set-ups with camera, place and what is in frame, output 1920x1080; the
seventh, the board, is held until published), and
the brief's own thumbnail, "a player mid-air leaping between two crumbling stone platforms", is §9 shot 2. Its
recipe edits `ReplicatedStorage.Config` in a Studio-only copy (unlocks at 0, a long countdown, a moved
`TierDepth`) to reach the deep strata quickly: that is fine for a still, and it is why no clip above uses it.

## Store text

`README.md`, "The store description" (897 characters, gate `py -3 check_store_text.py`). It names the strata,
their critters, the drops and the board because the game has them, and drops every claim of the concept brief the build does
not keep (eggs, hatching, levelling pets, closing walls, weekly content).
