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

## State — two adversarial reviews closed. NOT published, NOT committed, NEVER run in Roblox.

`REVIEW.md` (first pass) returned BLOCK with six findings; `REVIEW-2.md` (second pass) verified the
fixes independently, closed 8, and returned BLOCK again with six still-open and six broken BY the
fixes. `REVIEW-3.md` is the resolution of REVIEW-2 and is the file to read next.

- **7 spec files, all green**: Chase 32, Manor 86, Night 64, Rng 32, Upgrades 99, Watcher 87,
  responsive 70 = **470 assertions, 0 failed**. Chase.spec dropped from 91 to 32 because sixty
  one-per-night assertions became one assertion over five hundred nights — more coverage, fewer
  ticks. Do not read the count as a size.
- **Four headless gates, all green.** Three of them are new and live in `tests/`, because
  `robloxemu/` is not this game's to edit:
  - `tests/check_walk.luau` — **62 passed**. WALKS the game: spawns, walks the safehouse, presses
    prompts only from inside their real `MaxActivationDistance`, and threads the manor against the
    walls and the FURNITURE that were actually built. Three nights, 1050 studs on foot.
  - `tests/check_world.luau` — **38 passed**. The four guards nothing was testing (both
    `prof.loaded` gates, the origin plate/spawn pair, `spawnPad.Enabled`) plus the exit door.
  - `tests/check_boot_guard.luau` — **2/4/4/4 passed** over four cases. Boots the server against a
    hostile Config and asserts it REFUSES, which is the only thing that can catch a boot guard
    quietly turned into decoration.
  - `robloxemu/check_nightwatch.luau` — 113 passed, unmodified. `check_nightwatch_hud.luau` — PASS.
- **23 mutations, 23 killed; 4 controls, 4 survived.** Driver: `tests/_mutate.py` (delete it or
  keep it, but it is a test tool, not game code). Every tracked source sha256-matches afterwards.
- `luau-compile --binary` clean; `luau-analyze` clean apart from Roblox global/type noise — no
  LocalShadow, LocalUnused or FunctionUnused findings left anywhere, including the specs.

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
- **The hunter uses the same doors you do.** `Manor.chaseStep` steers a pursuer at the DOORWAY
  until it is standing in the gap and only then at the room beyond. Aiming straight at the next
  room's centre — which is what shipped — is wall-safe only FROM a centre, and one hunt tick in,
  the watcher is never at one; it cut the corner through 1 stud of Brick while the player had to
  use a 10-stud hole. The clamp that decides "close enough to the doorway" is a quarter of
  `DoorWidth`, not a bare constant, and without it the walk DEADLOCKS: `roomAtWorld` resolves a
  point exactly on a shared plane to the HIGHER cell, so a hunter arriving at a doorway heading
  toward the LOWER cell is still "in" the room it came from, still aiming at the doorway it is
  standing on, zero studs away, forever.
- **The way out is built on an outer wall.** `Manor.exitFace` prefers a face with nothing behind
  it, then a shared wall with no doorway in it. The ExitDoor slab is exactly `DoorWidth` wide, so
  a hard-coded face plants it in the doorway on half of all nights — measured: 249 of nights
  1-500 — and on some of those it is the only way into the room you have to reach.
- **`MaxRooms` is the cap on the TOTAL**, repair rooms included, and `Manor.roomCount` stops the
  growth target `MaxRepairRooms` short of it so the arithmetic closes. That leaves a config
  invariant, `MaxRooms >= MaxRepairRooms + 2`, which Manor.spec asserts: below it `roomCount`'s
  floor at 2 out-votes the cap. A second `math.min(..., MaxRooms)` inside `plan` was deleted
  rather than kept — with the target already clamped it was unreachable for every legal config,
  and an unreachable guard is decoration.
- **Effect ceilings**: `MaxDreadSlow` / `MaxWatcherSlow` / `MaxKeepOnCaught` are NOT binding with
  today's catalog (the natural maxima sit at or below them). They exist for the retune that will
  happen, and `Upgrades.spec` exercises them by temporarily raising every `max` — without that, a
  mutation deleting the `keepOnCaught` clamp passed the entire suite.

## Files

- `src/shared/Config.luau` — every tunable, plus the three catalogs.
- `src/shared/Manor.luau` — layout generation, room-graph queries, `pathBetween`, plus
  `doorwayBetween` / `chaseStep` (where a pursuer walks NEXT, through the doorway) and `exitFace`
  (which wall the way out is built on).
- `src/shared/Watcher.luau` — route maths, `dread`, `speed`, `sees`, `spots`, `hears`, `caught`,
  the PATROL/HUNT state machine, and the two boot audits `speedAudit` (fatal) / `ceilingBinds`
  (warning).
- `src/shared/Upgrades.luau` — `cost`, `canBuy`, `buy` (never mutates its input), `effects`,
  `sanitize`, `EFFECT_KEYS`.
- `src/shared/Night.luau` — `dreadSeconds`, `payout`, `startState`, `resolve` (raises on an
  outcome nobody defined).
- `src/server/Main.server.luau` — world building, the night loop, persistence.
- `src/client/Hud.client.luau` — display only.
- `tests/*.spec.luau` — the pure specs, run straight from the luau CLI.
- `tests/check_walk.luau` — WALKS the built world. The most important gate in the repo.
- `tests/check_world.luau` — the join-time guards and the exit door, in the built world.
- `tests/check_boot_guard.luau` — four hostile-Config boots; takes a case argument.
- `tests/_mutate.py` — the mutation driver that produced the table below.
- `../robloxemu/check_nightwatch.luau`, `../robloxemu/check_nightwatch_hud.luau` — NOT ours to
  edit; the three files above exist in `tests/` for exactly that reason. Whoever owns `robloxemu/`
  may want to fold them in.

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

**2026-09-10, closing REVIEW-2.** Full sweep, `py -3 tests/_mutate.py`: **23 mutations, 23 KILLED**;
4 controls, 4 SURVIVED; all four tracked sources sha256-match the baseline afterwards. The five
that survived the entire previous suite are now each killed by name — the two `prof.loaded` gates
(M16, M17) and `spawnPad.Enabled` (M20) by `check_world`, the origin plate and the origin spawn
sunk to y=-4000 (M18, M19) by `check_world`'s "the spawn point rests on the plate" pair, and the
boot guard turned into decoration (M14) by `check_boot_guard`. New this round and killed: the
hunter's diagonal restored in `Manor.chaseStep` (M10, by Manor.spec: 182 room-to-room walks, 182
wall crossings) and in the SERVER (M11, by `check_walk`), the exit door back on +Z (M12, M13), the
room cap invariant broken (M8), and three world-level ones — no doorway ever cut (M21), the
character never placed on the spawn frame (M22), and the dining table grown to fill its room (M23,
which is the "furniture the player gets stuck on" class, caught for the first time).

One mutation was DELETED rather than killed: `math.min(target + MaxRepairRooms, MaxRooms)` inside
`Manor.plan`. It survived every gate because the clamp in `roomCount` already implies it for any
config with `MaxRooms >= MaxRepairRooms + 2`; the line was unreachable, so it went, and the
invariant it stood for is asserted instead. Also worth recording, because it is the trap the
memory note warns about: an earlier run of this sweep reported that mutation KILLED, and the kill
was spurious — Manor.spec was ALREADY red at baseline from a control assertion of mine that was
simply wrong. A mutation sweep with no green baseline reports everything as killed.

Controls (changes the suites must NOT notice), re-verified 2026-09-10 by running each one through
every gate: renaming a room kind, renaming a relic tier, rewriting an upgrade blurb, renaming an
upgrade, recolouring the Nightwatcher. "Renaming a room kind" was listed here and was NOT true —
`Manor.spec` asserted `kindById("library").name == "Library"`, so the doc promised silence the
suite did not give. The assertion now checks the `id`, which is the load-bearing half, and the
control passes. **`HuntSpeedMul` is NO LONGER a control** — it is load-bearing, and both
Watcher.spec and the boot audit assert against it.

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
6. **No unlock gate, and the safehouse no longer touches the manor at all.** The brief has the
   safehouse "gating access to harder/larger manor seeds". It gates nothing: since the
   determinism fix, `Manor.plan` does not take a hub level and `Manor.roomCount` does not read
   one, so the manor grows with the NIGHT and with nothing else. The night simply advances when
   you extract. (This paragraph used to say "hub level grows the manor", which stopped being
   true the moment that fix landed and was the doc half of REVIEW-2's finding.)
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
    emulator. `tests/check_walk.luau` now closes part of that gap by hand: it models wall and
    furniture collision from the parts the server actually built, walks the whole loop through it,
    and only presses a prompt from inside its real reach — so "furniture the player can get stuck
    on" and "a pedestal clipping a bookshelf" ARE now caught (a dining table grown to fill its
    room fails the gate). What is still unmodelled and can only be seen in Studio: gravity,
    stairs and step height, character physics against sloped or rotated parts (the nursery's
    rocking horse is rotated and is modelled here as its unrotated box), lighting — whether the
    manor is dark enough to be frightening and light enough to navigate — camera, and every
    question of feel.

## Next

1. Open it in Studio and walk a night. Navigability and prompt reach are no longer the open
   questions — `tests/check_walk.luau` walks three nights against the real geometry and reaches
   every relic and the exit — so the things to look at are the ones no gate here can see: whether
   the manor is lit enough to read and dark enough to be frightening, whether the character gets
   caught on a rotated part or a step, and — the real one — whether a Nightwatcher that can no
   longer run a fleeing player down still FEELS like a threat. The maths says it costs you route
   and dread rather than the run, and that ignoring it costs the haul on roughly two nights in
   three; only a real session says whether that is frightening. Retune `BaseSpeed` /
   `SpeedPerDread` / `HuntSpeedMul` freely if it is not — the ceiling makes that safe, and the
   boot audit will warn in F9 the moment a retune pins the watcher AT the ceiling.
2. Audio pass (item 3) — the largest genre gap, and it needs marketplace assets.
4. Decide the currency question (item 2) and fix the description to match the code before the
   experience is created.
5. Then the usual ship path: create the experience, git-ignored `publish_nightwatch.bat` with the
   Open Cloud key inline, maturity questionnaire (the Preview page is ground truth — a green check
   means "answered", not "No"), then Public. `git push` does NOT update the live game.
