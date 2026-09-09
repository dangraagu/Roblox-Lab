# CLAUDE.md — Nightwatch Manor: Haunted Escape Tycoon (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/`, `anomaly-observatory/`; same stack (one CONFIG table, deterministic `Rng`,
DataStore with `canSave` + a soft session lock, pure logic tested from the luau CLI). Built from
Game-Radar concept #2 (2026-09-09) — the seasonal one, aimed at the Sept–Oct horror window.

## What it is

A two-phase horror tycoon.

**NIGHT** — the server builds a manor from `Manor.plan` (a seeded grid of modular rooms), fills it
with relics on pedestals, and starts one Nightwatcher on a patrol route through the doorways. The
player takes relics and has to reach the Servants' Exit before DREAD reaches 1.

**DAY** — a persistent per-player safehouse. Each upgrade is an in-world pad with a
ProximityPrompt; buying a level spends relics, stacks a visible prop on the pad, and moves a number
the next night reads.

Failure (caught, or evicted at full dread) costs the haul you were carrying. It does **not** roll
back the night and does **not** touch the safehouse.

## State — built, adversarially reviewed, blocking findings closed. NOT published, NOT committed.

An adversarial review (`REVIEW.md`) returned BLOCK with six findings. All six are addressed; the
resolution log is at the bottom of REVIEW.md. The two that mattered were a Nightwatcher the player
could not outrun (so being seen was being caught, always, with no counterplay) and a joining
player free-falling in an empty world while a blocking DataStore call finished.

- **7 spec files, all green**: Manor 64, Watcher 71, Upgrades 99, Night 64, Rng 32, responsive 70,
  **Chase 79**. Chase.spec is new and is the one that asserts the game is PLAYABLE rather than
  merely well-formed — see "Core model" below.
- **`robloxemu/check_nightwatch.luau`: 113 passed, 0 failed** — boots the real server and plays the
  loop against the workspace, including the join sequence against a deliberately SLOW DataStore.
- **`robloxemu/check_nightwatch_hud.luau`: PASS** across ten viewports, with both phone drawers
  opened by the warmup so the compact layout is actually measured rather than skipped.
- `luau-compile` clean; `luau-analyze` clean after filtering Roblox global/type noise.
- Never run in Studio or a real client. No experience created, nothing published, nothing pushed.

## Core model / invariants

- **THE NIGHTWATCHER CAN NEVER BE FASTER THAN THE PLAYER.** `Config.Player.WalkSpeed` (20) is real
  data the server assigns onto every Humanoid, and `Watcher.speed` clamps itself to
  `MaxSpeedFraction * WalkSpeed` (0.65 -> 13.0) as its LAST step. The curve underneath never
  reaches it (12.48 at dread 1 while hunting), so the ceiling is a guard rail rather than the
  operating point and `BaseSpeed` / `SpeedPerDread` / `HuntSpeedMul` can be retuned freely.
  Main.server refuses to boot if the curve ever does reach the player. This exists because the
  shipped build had the hunter at 15.95 studs/s against Roblox's never-assigned default of 16:
  faster from 0.8 seconds into night one, so being seen was being caught, every night, forever —
  and the whole suite was green through it, because the player's speed was in no config and no
  test. A pursuer's speed only means anything relative to what it is pursuing.
- **Determinism**: `Manor.seedFor(cfg, night) = WorldSeed * SeedPrimeA + night * SeedPrimeB`, and
  `Manor.plan(rng, cfg, night)` takes NOTHING else — no userId, and (since the review) no hub
  level. Night N is the same manor for everyone, which is the only thing that makes a best-night
  number comparable. Both products stay far under 2^53, so no low bits are lost to float rounding
  (the trap that pinned a sibling game to one outcome forever). The trade-off is real and
  accepted: layouts are memorisable across sessions.
- **Growth, then circuits, then repair**: `Manor.plan` attaches each new room to a random room that
  still has a free orthogonal neighbour, weighting the choice toward cells that already touch built
  rooms so it fills out instead of growing tendrils. It then opens a doorway through every OTHER
  shared wall with probability `ExtraDoorChance`, and finally runs a dead-end repair pass (up to
  `MaxRepairRooms` extra rooms, consuming no rng draws) until no room has a single door.
  Attachment alone gives a TREE, and a tree is a manor a chased player cannot survive at any speed:
  55% of rooms were dead ends, and a fleeing player was still cornered on 8 of nights 1-12 after
  the speeds were fixed. Now 1.36 doorways per room and 0.4% dead ends. Doorways are only ever
  ADDED and rooms only ever attached, so connectivity is still guaranteed by construction.
- **`roomCount` is a TARGET, not an exact count** — the repair pass may exceed it by up to
  `MaxRepairRooms`. Manor.spec asserts the band rather than equality.
- **The exit is always the deepest room**, so every night is a full crossing.
- **Walls block sight with no raycast**: `Watcher.spots` is the cone AND a `roomOk` flag the server
  computes from `Manor.roomAtWorld` + `Manor.linked`. Roblox's `Raycast` is not modelled by the
  headless emulator, and this design does not need it.
- **The chase is our own BFS**, `Manor.pathBetween`, over at most 18 nodes — not
  PathfindingService. The watcher beelines at the centre of the next room on the path, which is
  what keeps it going through doorways instead of through walls.
- **Dread is accumulated from `task.wait`'s return value**, never from a wall clock. The emulator
  drives a virtual clock, so `os.clock()` would sit at zero for an entire simulated night and the
  loop would be untestable.
- **Three dispatch tables, three startup guards.** `ROOM_BUILDERS`, `RELIC_BUILDERS` and
  `UPGRADE_PROPS` are keyed by the ids in `Config`, and the server `error()`s at boot if any
  catalog entry has no handler. Adding an entry to a `Config` list does NOT make it happen. This is
  the pattern taken from `anomaly-observatory`, and each of the three failures it catches is
  silent and green to every unit test.
- **Nothing the client sends is trusted, because the client sends nothing.** Every action is an
  in-world ProximityPrompt whose handler checks `who == plr`. The only remotes are `State` and
  `Notice`, both server -> client.
- **Zone indices are recycled** through a free list on `PlayerRemoving`, so a long-lived server
  never marches out to where float precision degrades.
- **DataStore**: `GetDataStore` is pcall'd (it RAISES in an unpublished place and would otherwise
  kill the whole script at load). Soft session lock — always load the real data, save only while we
  hold the lock, and never clobber a lock somebody else took. Ownership is a stable per-session
  GUID, never a timestamp we also rewrite.
- **Effect ceilings**: `MaxDreadSlow` / `MaxWatcherSlow` / `MaxKeepOnCaught` are NOT binding with
  today's catalog (the natural maxima sit at or below them). They exist for the retune that will
  happen, and `Upgrades.spec` exercises them by temporarily raising every `max` — without that, a
  mutation deleting the `keepOnCaught` clamp passed the entire suite.

## Files

- `src/shared/Config.luau` — every tunable, plus the three catalogs.
- `src/shared/Manor.luau` — layout generation, room-graph queries, `pathBetween`.
- `src/shared/Watcher.luau` — route maths, `dread`, `speed`, `sees`, `spots`, `hears`, `caught`,
  and the PATROL/HUNT state machine.
- `src/shared/Upgrades.luau` — `cost`, `canBuy`, `buy` (never mutates its input), `effects`,
  `sanitize`, `EFFECT_KEYS`.
- `src/shared/Night.luau` — `dreadSeconds`, `payout`, `startState`, `resolve` (raises on an
  outcome nobody defined).
- `src/server/Main.server.luau` — world building, the night loop, persistence.
- `src/client/Hud.client.luau` — display only.
- `../robloxemu/check_nightwatch.luau`, `../robloxemu/check_nightwatch_hud.luau`.

## Mutation results (all restored afterwards)

**2026-09-09.** Killed: remove the carried lantern; remove the pedestal `Taken` attribute; unparent every wall;
remove the `who ~= plr` guard on an upgrade pad; delete a `ROOM_BUILDERS` entry (refuses to boot);
break `exit is deepest`; make CAUGHT advance the night; make the sight cone always true; drop the
`keepOnCaught` clamp (after the spec was strengthened).

Survived once, then fixed: passing `Upgrades.effects(Config, {})` into `Night.resolve` instead of
the player's real effects — invisible until the headless check bought a Relic Vault first.

**2026-09-10, closing the review.** The two mutations that survived the ENTIRE suite before are now
handled. `SightRange 55 -> 2000` is KILLED by Chase.spec (there has to be a corner of the next room
it cannot see). `HuntSpeedMul 1.45 -> 5.0` no longer breaks the game at all — the speed ceiling
absorbs it — while unbolting the ceiling itself (`MaxSpeedFraction 0.65 -> 3.0`) and deleting it
from `Watcher.speed` are both KILLED. Also killed: `ExtraDoorChance -> 0`, `MaxRepairRooms -> 0`,
folding hubLevel back into `roomCount`, and — in the headless check — removing the origin floor,
never assigning `RespawnLocation`, making the spawn pad a plain Part, delaying the placement by
0.2s, putting the blocking DataStore call back in front of the world build, never assigning
`WalkSpeed`, and removing either of the two `who ~= plr` guards inside the manor.

Controls (changes the suites must NOT notice, all verified silent): renaming a room kind, renaming
a relic tier, rewriting an upgrade blurb, renaming an upgrade. **`HuntSpeedMul` is NO LONGER a
control** — it is load-bearing, and Watcher.spec asserts it.

## NOT built — be honest about these before writing any store copy

1. **No environmental puzzles.** The brief says "solve light environmental puzzles". There are
   none. A night is walk, take, avoid, leave.
2. **One currency, not two.** The brief and the paste-ready description say "relics **& cash**".
   Cash is folded into relic worth. Either add the second currency or edit the description.
3. **No audio at all.** No ambience, no footsteps, no stinger. In a horror game that is the single
   biggest gap, and it needs assets we do not have.
4. **No real jumpscare.** Being caught is a red screen flash, a camera shake and a toast. There is
   no jumpscare model, animation or sound.
5. **Traps do not fire.** Bear Traps slow the Nightwatcher globally and stack a prop on their pad;
   they are not placeable traps that trigger in the manor. Same for the Alarm Bell (it grants a
   proximity warning, it does not ring) and the turrets in the description, which do not exist.
6. **No unlock gate.** The brief has the safehouse "gating access to harder/larger manor seeds".
   Hub level grows the manor, but nothing is locked behind it — the night simply advances when you
   extract.
7. **No character death.** Being caught teleports you home and takes the haul. The Humanoid is
   never damaged and there is no ragdoll or respawn beat.
8. ~~**No spawn point.**~~ CLOSED 2026-09-10. A plate and a `SpawnLocation` at the world origin,
   built before anybody can join; each safehouse's spawn pad IS a `SpawnLocation` and is assigned
   as that player's `RespawnLocation`; the character is placed on the frame it appears and the
   CFrame is re-asserted next frame; and the zone is now built BEFORE the blocking `claimProfile`
   call rather than after it, with buying and entering a night gated on `prof.loaded`.
9. **No leaderboard surface.** Best night is written to an OrderedDataStore but nothing reads it
   back — there is no in-world board and no HUD ranking.
10. **No codes, no gamepasses, no badges, no cosmetics.**
11. **Never run in Roblox.** Everything above was verified by the luau CLI and the headless
    emulator. The emulator is not Roblox: it models no physics, no rendering and no Raycast, so
    first real play will surface things neither gate can see — furniture the player can get stuck
    on, a pedestal clipping a bookshelf, a manor too dark to navigate.

## Next

1. Open it in Studio and walk a night. Check the manor is navigable and lit enough to read, the
   prompts are reachable, and — the new question — whether a Nightwatcher that can no longer run a
   fleeing player down still FEELS like a threat. The maths says it now costs you route and dread
   rather than the run; only a real session says whether that is frightening. Retune `BaseSpeed` /
   `SpeedPerDread` / `HuntSpeedMul` freely if it is not: the ceiling makes that safe.
2. Audio pass (item 3) — the largest genre gap, and it needs marketplace assets.
4. Decide the currency question (item 2) and fix the description to match the code before the
   experience is created.
5. Then the usual ship path: create the experience, git-ignored `publish_nightwatch.bat` with the
   Open Cloud key inline, maturity questionnaire (the Preview page is ground truth — a green check
   means "answered", not "No"), then Public. `git push` does NOT update the live game.
