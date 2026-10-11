# CLAUDE.md — Nightwatch Manor: Haunted Escape Tycoon (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/`, `anomaly-observatory/`; same stack (one CONFIG table, deterministic `Rng`,
DataStore with `canSave`, a session lock and an owner token on every write, pure logic tested from the luau CLI).
Built from Game-Radar concept #2 (2026-09-09) — the seasonal one, aimed at the Sept–Oct horror window.
Measured against `docs/complete-game-standard.md` on 2026-10-01 (pass 2): what is still missing is the night shift's
(§5) and the genre gaps in "NOT built" below. The store text is `README.md`, the clip list `MARKETING.md`, the
needs-Studio and thumbnail lists `EYECANDY.md` §11-12.

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

## The nights escalate (eye candy, 2026-09-23/24) — read `EYECANDY.md`

Built to the owner's brief of 2026-09-17, client-side only (`src/client/Haunt.client.luau`,
`src/shared/HauntArt.luau`, `src/shared/Nightfall.luau`, plus the template modules EnvBands, Rest and Hazards from
`plus1-jump`). There are six bands by NIGHT, nudged by dread and never by time. They bring:
* windows on the outer walls (moon, stars, mist, rain, lightning, a blood moon, an eclipse);
* portraits whose eyes follow you;
* flicker that deepens with dread;
* a safehouse that grows cosier with the hub level;
* ghostly hazards, a near-miss every 2-3 minutes in the manor;
* the Blood Moon (night 26) as the brag moment and the Witching Hour (night 50) as the long-term goal (moved from 20
  and 40 on 2026-10-01: on the salted manors the game now plays, night 20 came at a median of 25.8 minutes);
* ☕ Rest and the ⚡ "fewer flashes" toggle in the safehouse only.

`Main.server.luau` and `Hud.client.luau` were untouched by the eye candy; the second review (2026-09-30, below and
`EYECANDY.md` §15) changed `saveProfile` (ownership) and made the HUD's own flashes obey "fewer flashes". Invariants a
future edit must keep:
- **Fair to the chase** (`Nightfall.fairness`, `validateHazards`, `hazardClock`):
  - the lighting stays inside a hard envelope around `Fx.Presets.Horror`;
  - no cosmetic glow within 60 of the Nightwatcher's light colours (`Config.Env.WatcherSignature`) **or of the
    Servants' Exit's green** (`Config.Env.ExitSignature`, review 4). Both are pinned to what the server builds by
    `check_nightwatchmanor_haunt`, and both are scanned on every frame of the worst case by `check_nightwatchmanor_budget`;
  - hazards: one every 90-130 s of NIGHT, aimed 0.5 s ahead of a walker: a near-miss (a pass within 8 studs of a
    player who reads the ring) every 2.7-2.9 minutes in the manor for every player profile, one hazard shown per
    1.9-2.1 (`Pacing.spec`, pooled over three seeds; second review; re-measured 2026-10-01 after the bands moved). The clock is frozen outside the night, and
    **held** (running, no launch) while the Nightwatcher sees you and for 10 s after. Review 4: a clock frozen for
    chases made hazards come more often the better a player hid (DECIDED 2026-09-30: stays held). A hazard is called
    off the moment it sees you. A knock is slower than walking and never lifts;
  - a hazard can knock you down only from `Nightfall.hitFrom` on (arrival minus reach over the KIND's speed: after the
    lane locks, at least 3 s into the warning). Without it, walking up to a slow ghost and stopping in its path was a
    knock 1.5-2 s early, with the warning still saying INCOMING. The ring and the warning stay up while
    `Hazards.threatLive` (a hit can still land), not just to the arrival time;
  - an invalid config switches off only its own part (`check_nightwatchmanor_fairgate`).
- **Nothing strobes** (review 4): lightning never closer than 4 s of real time (`Nightfall.boltGap`), warnings blink at
  most twice a second, no lightning while resting. **"Fewer flashes"** (`src/shared/Calm.luau`, one switch shared by
  both client scripts): Roblox's Reduced Motion setting (`GuiService.ReducedMotionEnabled`, read every frame through
  pcall; the name is unverified in Studio) OR the in-game ⚡ toggle in the safehouse (owner decision 2026-09-30) turns
  every flash of ours off, and the HUD's own CAUGHT / EVICTED flashes, shakes and the EXTRACTED FOV punch too
  (`check_nightwatchmanor_flash`). Turning flashes ON under Reduced Motion is refused with a card saying why.
- **Rest never inside the night.** `Nightfall.validateRest` rejects `Rest.Phases.NIGHT`. The night is a timed round.
- **The server never hears of any of it**: no remote, no attribute. What the client DOES write outside its own folder
  (review 4 corrected an earlier "only room lights" claim):
  - room-light `Brightness` (flicker), inside a hard floor;
  - the bands' own keys on the Lighting service and on the server's `FxAtmosphere` / `FxBloom` / `FxColorCorrection`,
    never `FxDoF` or any other key, plus one effect of its own (`NightwatchRestFocus`). Asserted by
    `check_nightwatchmanor_haunt`. **A server-side Lighting change would be overwritten by the client**: put it in the
    bands, or extend that check on purpose;
  - its own character's `Humanoid.Sit`, `PlatformStand` and `AssemblyLinearVelocity` (rest, a knock). These are normal
    character state and may replicate. The server reads none of them.
  `check_nightwatchmanor_haunt` checks EVERY assignment to Lighting and the server's effects during a session (a write
  hook on the emulator's Instance metatable), not only the end state (second review: a flash-time FxDoF write put back
  afterwards passed before).
- **A seated Humanoid drops.** Sat down without a seat, it falls for about 0.3 s (vy -3 .. -26, FloorMaterial Air;
  measured in real Studio in +1 Jump). The first `SIT_SETTLE_SECONDS` (1.0) after a sit count as supported, or the
  drop's first frame ends the rest (`check_nightwatchmanor_sitdrop` replays the Studio trace).
- **Budgets** (`Config.Budget`) are asserted every frame of a built worst case by `check_nightwatchmanor_budget`, and
  CAPPED in code (second review): `HauntArt` reserves the largest hazard + lane + ring + six hosts, gives scenery what
  is left of `MaxParts` (nearest / lowest tier first), `HauntArt:capLights` holds `MaxLights` (hazard, fire, lightning
  in that order), and `Nightfall.validateHazards` switches hazards off below `MaxHazards` 1.
  `check_nightwatchmanor_caps` cuts the budget to 50 parts and 1 light in memory and holds it every frame.
- **The HUD row is readable on phones**: the chip wraps on two lines, is never under 170 screen px wide or 40 tall
  (stacked under the day's buttons when narrower; on an upright phone the stack moves above the touch controls), and
  text caps are meant in SCREEN px (`TEXT_MAX_PX / layout.scale`). `check_nightwatchmanor_layout` estimates every
  label's font on 19 viewports (at least 11 px). On a tablet or desktop the chip sits between the HUD's panels and is
  narrower (the tablet's day chip is 157 x 44 px, its text estimated at 12.0 px, the smallest of all 57 labels).

Gates for it: 6 more specs (EnvBands, Rest, Hazards, Nightfall, EnvConfig, Pacing) and 11 more headless checks
(`robloxemu/check_nightwatchmanor_*.luau`; `flash` added by review 4; `sitdrop`, `save` and `caps` by the second review).
Counts, the mutation sweeps, review 4's findings and fixes (§14), the second review's (§15), the Studio list and the
thumbnail shot list are in `EYECANDY.md`.

## Secret manors, the exit's guard and the board (2026-10-01, pass 2) — invariants

- **Every manor is planned from a server-only salt** (`src/shared/Salt.luau`: two 32-bit LCG streams mixed, 2^64
  states; `Manor.plan` takes it like an `Rng`). `Main.server` draws the halves (`drawHalf`: its own `Random` XOR a fresh
  one) **once per player, per night, per session** (`manorSalt`), and keeps them only in
  `ServerStorage.NightwatchSecrets` as the attribute `u_<userId>` = `"night:a:b"` (removed when the player leaves). No
  attribute outside ServerStorage, no remote payload and no Instance name carries them (`check_nightwatchmanor_guard`
  scans every Instance and every payload). A retry after being caught is the same manor; after
  `Config.Manor.ShiftAfterFails` (3) failures in a row there the manor **shifts** (new halves, same night, and the
  NIGHT notice says "The manor has shifted"). Without the shift, 2 of 31 model players were stuck on one night for the
  rest of their 200 minutes (one of them 418 attempts at night 36; Pacing.spec). The night alone still sets the size, relics, patrol and dread, so the best night is comparable.
- **`PublicLayouts`** (an attribute on that folder, set only from Studio's command bar, Server context) plans every night
  from the old public seed. The thumbnail recipe (EYECANDY.md §12), `MARKETING.md` and every layout-bound check use it
  (`tests/check_walk`, `check_nightwatch`, `budget`, `caps`, `flash`, `haunt`, `hazards`). A client cannot set it.
- **The Servants' Exit's guard** (`src/shared/Crossing.luau`, `Config.Guard`): ESCAPE works only for a character whose
  root the server measures **in the exit room** and within the prompt's reach (12 + 4 slack) of the door, once the
  night has run the shortest possible walk there at WalkSpeed, less 0.5 s. Every prompt in this game has
  `RequiresLineOfSight = false`, so without the room test ESCAPE worked through a wall from the next room (public
  night 9 saved 77 studs; a salted night-45 manor was 0.13 s from the start). Shortest crossings: 2.9-8.9 s on public
  nights 1-150, 1.85-10.44 s on 3000 salted manors. `minDistance` is a LOWER bound on every legal walk (Crossing.spec).
  A refusal says why in the toast's TEXT (the HUD drops a DENIED notice's detail).
- **The position guard** (`src/shared/PosGuard.luau`, `Config.Guard`, `checkFooting` in `Main.server`; 2026-10-11,
  the HIGH finding of the 2026-10-09 review). The exit's guard alone was NOT enough, and the claim that stood here
  and in `Crossing.luau` ("a script that teleports gains nothing a person could not") was false: the Nightwatcher
  sees by room, so a character parked outside every room was never seen, and a script could wait out the clock
  there and teleport to the door (a night per ~12 s). Now the server samples the root every tick of a night and at
  the exit's press, and a night is **VOID** (ends at once as an eviction with an EMPTY bag; the night does not
  advance, so the best night and the board cannot move; the notice's text says why) on either:
  - **OUTSIDE**: in no room for more than 0.5 s of the night in total;
  - **JUMP**: more ground than a walk covers. A bank of studs: 8 to start, refilled at 22 studs/s (WalkSpeed + 10%),
    capped at 74 (waiting buys nothing more; a 3.7 s lag gap is made up in one sample), spent by the shortest LEGAL
    walk between two samples (`Crossing.walkBound`: through the doorways, so a hop through a wall costs the way round).
  After the server itself places the character (the night's start, a respawn: `PosGuard.reseed` in `placeCharacter`)
  nothing is judged for 2 s, then the walk is measured from where the server put it; the exit's press is judged
  even inside that window. **Keep these when editing:** every server-side teleport during a NIGHT must re-seed the
  guard (or it reads as a jump); any sprint or speed boost must raise the bank's rate with it; `PositionChecks` is
  switched off only in memory by the headless kit (`Kit.posGuard`), because its checks place the character by CFrame.
  What it does NOT close (be honest in any store copy): a script that WALKS the doorways at WalkSpeed is a person
  to the server and can still take a night per crossing; a hop inside the bank looks like a lag gap (foyer to door
  in one hop on 1.2% of salted manors); short hops to dodge the Nightwatcher. `EYECANDY.md`, "Night shift 2026-10-11".
- **The NIGHTS SURVIVED board** (`src/shared/Board.luau`, `Config.Board`, `buildBoard` in `Main.server`): an
  OrderedDataStore `NightwatchManorBoard_v1`, key `u_<userId>`, value `night * 2e9 + (2e9 - reachedAtUnix)`
  (`prof.bestAt`, stamped at the extraction that first set the best), written through `UpdateAsync` +
  `Board.keepHigher` only when the night improves (`prof.boardBest` is saved, so a rejoin writes nothing), only while
  `canSave`, at most once per 30 s (the autosave catches up). Public top 10: `GetSortedAsync(false, 10)` at most once a
  minute while anybody is on, checked every second so a fresh server shows it at once. Friends: `GetFriendsAsync` only
  when a player asks, capped at 200, cached 5 minutes (a failure 1 minute), scores read through a token bucket (40, then
  1/s) and Roblox's own budget, a friend on this server read from memory. Names: a player on the server first, then a
  cache, then one `GetNameFromUserIdAsync`; never stored. The board is a part on the east wall of every safehouse, 29
  studs from the spawn pad, drawn by the SERVER (a SurfaceGui; no remote), prompt on F so it never fights a pad's E.
- **Pacing** (`tests/NightModel.luau` `session{ salted = seed }`): the brag moment and the long-term goal are asserted
  on 31 first-time players on salted manors (a salt per night, the shift after 3 failures), as the game ships.

## State — NOT published, NEVER run in Roblox. Current counts: `EYECANDY.md` §8.

**2026-10-11 (night shift: the position guard).** The HIGH finding of the 2026-10-09 review (a script could wait
outside the manor, unseen, and teleport to the door: a night per ~12 s) was reproduced against the real server and
fixed test-first: `PosGuard.luau`, `Crossing.walkBound`, `checkFooting` in `Main.server` (above, "The position
guard"). Every gate, run twice on the final tree with identical counts: **42 of 42 green** (17 specs 1653 passed;
headless 116 in `tests/` + 826 in `robloxemu/` + the HUD PASS; 0 failed). New gates: `tests/PosGuard.spec` (224),
`robloxemu/check_nightwatchmanor_posguard` (71); `check_walk` 62 to 64. Mutation sweep: 18 of 18 killed, 2 controls
survived. One independent read-only review of the diff: no HIGH, four findings taken. Residual risk, the mutation
table and the Studio list: `EYECANDY.md`, "Night shift 2026-10-11". The review's findings 2-5 are still open. Not
published, not pushed.

**2026-10-01 (pass 2 of 2).** The unfinished board / salt / crossing-guard work that pass 1 had archived
(`scratchpad/nwm_p1_1001/wip_board_archive/`) was put back byte-for-byte and finished: its five red suites were the
layout-bound checks meeting salted manors (now on `PublicLayouts`), the exit presses meeting the guard (now
`Kit.extract`: stand at the door after the shortest walk), the board's two new safehouse parts, and a kit bug (a
`CatchRadius` of -1 is a 1-stud catch). Then, test-first: a salt per player, night and session instead of per attempt,
the manor shift after 3 failures, the exit-room test in the guard, the board read on a fresh server within a second,
names from players on the server first, the guard's refusal text, the Blood Moon at night 26 and the Witching Hour at
50 (salted pacing), and a hall tour that had passed with 0 halls visited. New gates: `Board.spec`, `Crossing.spec`,
`Salt.spec`, `robloxemu/check_nightwatchmanor_board.luau`, `robloxemu/check_nightwatchmanor_guard.luau`. New docs:
`MARKETING.md` (8 clips), the store text (README), EYECANDY.md §11-12 and §16. Every gate, run twice on the final tree
with identical counts: **40 of 40 green** (specs 1428 passed; headless 114 in `tests/` + 755 in `robloxemu/` + the HUD
PASS; 0 failed). Mutation sweep: 29 mutants, 24 of 25 killed (the survivor was an equivalent copy of a check,
deleted), 4 controls survived all 40 gate runs (EYECANDY.md §16). 57 Luau files compile through
`loadstring`, 0 errors; luau-analyze was not available.

How to run every gate (luau CLI on the PATH as `luau`; every suite is judged by its exit code; run the set twice, the
client checks use unseeded randomness):

```
cd nightwatch-manor
for f in tests/*.spec.luau; do luau "$f"; done                    # 17 specs, from the game directory
cd tests && py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
luau check_walk.luau
luau check_world.luau
for c in control fraction walkspeed saturated; do luau check_boot_guard.luau -a $c; done
cd ../../robloxemu && py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
for f in check_nightwatch*.luau; do                                # every one except the kit (a library)
  case $f in
    check_nightwatchmanor_kit.luau) ;;
    check_nightwatchmanor_fairgate.luau) for c in light hazards rest; do luau $f -a $c; done ;;
    check_nightwatchmanor_flash.luau) for c in storm calm; do luau $f -a $c; done ;;
    *) luau $f ;;
  esac
done
```

The same as a script: `scratchpad/nwm_p2_1001/gates.sh` (one line per suite, exit code first). Rebuild the bundle before
every headless run: a stale `build/nightwatch-manor.luau` tests yesterday's game.

Traps this game has shown (keep them in mind before trusting a green run):
- CRLF and LF files side by side (each file is consistent): edit byte-preserving.
- The emulator's `Random` is unseeded: per-run counts of the client checks move, and every manor is a new salt. Run twice.
- One Harness per CLI process: a check with many cases uses one server and many players (or `-a <case>`).
- The pacing model is chaotic: assert on populations or pooled seeds, never one trajectory. Draw a salted session's
  halves from a Salt stream: two consecutive outputs of one 32-bit LCG are one number, and that correlated subset
  stuck 4 of 31 sessions within their first three nights (independent halves: the first stuck session, before the
  shift existed, came at night 36).
- `Watcher.caught` squares the radius: `CatchRadius = -1` is a 1-stud catch. Blind it in memory with 0 and 0.
- The foyer's start point (centre + 12 Z) lies on the patrol line to the foyer's +Z doorway.
- A check that says "every X visited had Y" needs a CONTROL that X was visited (the night-50 hall tour visited 0).
- Prompts need no line of sight here: anything a prompt guards must check the room on the server.
- Layout-bound checks set `PublicLayouts`; a check that wants the game as it ships must not.
- The headless kit switches the position guard OFF (`Kit.posGuard`; `Kit.boot{ posGuard = true }` keeps it): its
  checks place the character by CFrame, which is what the guard voids a night for. A check that moves the character
  with the guard on has to WALK it (2 studs a tick), as `check_nightwatchmanor_posguard` and `tests/check_walk` do.


History, newest first.

**2026-10-01 (pass 1 of 2, run again: the 2026-09-30 run was cut off before it reported).** Its pass 1 had left the
fixes below in the tree. A later pass of that run had started a highscore board, a server-only salt for every manor and
a "crossing guard" on the exit (new `Board`, `Salt` and `Crossing` with specs; changes to `Main.server`, `Config` and five
checks) and stopped half-way: its own specs green (Board 70, Crossing 33, Salt 31), five suites red (`check_walk` 46 / 14,
`check_nightwatch` and `haunt` stopped on errors, `budget` 31 / 1, `save` 66 / 1). **That work is not in the tree.** It
is archived byte-for-byte in `scratchpad/nwm_p1_1001/wip_board_archive/` (the 14 files, `MANIFEST.sha256`,
`wip_vs_pass1.patch`, its red gate log), and the seven files it had changed were put back to the 2026-09-30 bytes (58 of
58 files sha256-identical to that state). Resume the board from there: it is `docs/complete-game-standard.md` §3 (NOT
built item 9) and §1 (the salt). Then the eight second-review findings were reproduced again on the committed code
(HEAD) and checked on this tree (`EYECANDY.md` §15, "Re-verified"), one more owner decision recorded (the near-miss is
the metric, §13), mutation round 4 re-run (30 mutants: 28 killed, 2 controls survived all 35 gate runs, every mutant
proven in the bundle, workers sha256-restored), and every gate run twice: **35 of 35 green**, the counts below.

**2026-09-30 (second review, pass 1 of 2).** All eight findings of the second reviewer reproduced and fixed
test-first (`EYECANDY.md` §15), plus one found while fixing (a knock before the lane locked); the owner's open
decisions taken ("take the recommended option for all", `EYECANDY.md` §13). Every gate, run twice: **35 of 35 green**
(specs 1280 passed; headless 114 in `tests/` + 598 in `robloxemu/` + the HUD PASS; 0 failed). Mutation round 4: 30
mutants, 28 killed as expected, 2 controls survived all 35 gate runs. How to run every gate:
`scratchpad/nwm_p1_0930/gates.sh` (every `tests/*.spec.luau` from the game dir; `tests/check_walk`, `check_world`,
`check_boot_guard -a control|fraction|walkspeed|saturated` from `tests/` after `wrap.py --game .. --out
build/nightwatch-manor.luau`; every `robloxemu/check_nightwatch*.luau` except the kit, `fairgate -a light|hazards|rest`,
`flash -a storm|calm`). Traps this game has shown: CRLF and LF files side by side (edit byte-preserving); the
emulator's `Random` is unseeded (per-run counts move, so run twice); one Harness per CLI process (a check with many
cases uses one server and many players); and the Pacing model is chaotic (assert on populations or pooled seeds,
never one trajectory). The history below is the first two reviews'.

`REVIEW.md` (first pass) returned BLOCK with six findings; `REVIEW-2.md` (second pass) verified the
fixes independently, closed 8, and returned BLOCK again with six still-open and six broken BY the
fixes. `REVIEW-3.md` is the resolution of REVIEW-2 and is the file to read next.

The state on 2026-09-10, after REVIEW-3 (history; today's counts are `EYECANDY.md` §8):

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
- **Determinism, and the secret**: `Manor.plan(rng, cfg, night)` takes NOTHING else — no userId, and (since the
  review) no hub level — so the night alone sets a manor's size, relics, patrol and dread clock, which is what makes a
  best-night number comparable. Since 2026-10-01 the `rng` the server passes is `Salt.new(a, b)`, two server-only
  halves per player, night and session (above, "Secret manors"); before that it was the public
  `Rng.new(Manor.seedFor(cfg, night))` (`WorldSeed * SeedPrimeA + night * SeedPrimeB`, both products far under 2^53),
  which any client could compute, so every night's layout was memorisable and computable ahead of time. The public
  seed still exists for `PublicLayouts`, the specs and the layout-bound checks.
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
- **The exit is always the deepest room**, so every night is a full crossing, and ESCAPE works only from inside the
  exit room after the shortest possible walk there (`Crossing.luau`), in a night the character walked (`PosGuard.luau`).
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
  `Notice`, both server -> client. The one thing a client DOES control is where its own character is (Roblox gives
  it the physics); the server measures that itself, every tick of a night (`PosGuard.luau`).
- **Zone indices are recycled** through a free list on `PlayerRemoving`, so a long-lived server
  never marches out to where float precision degrades.
- **DataStore**: `GetDataStore` is pcall'd (it RAISES in an unpublished place and would otherwise
  kill the whole script at load). Soft session lock — always load the real data, save only while we
  hold the lock, and never clobber a lock somebody else took. Ownership is a stable per-session
  GUID, never a timestamp we also rewrite. **A write lands only while the record still carries our
  token** (second review, 2026-09-30): it used to land whenever the stored lock was nil or older than
  45 s, whoever's it was, so a server whose saves stalled could roll back a player who had moved on to
  another server. A refused write turns `canSave` off for good and tells the player once (READONLY);
  a release keeps the token with `at = 0` (claimable at once, and still ours for a second release).
  `robloxemu/check_nightwatchmanor_save.luau`.
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
- `src/shared/Salt.luau` — the server-only 64-bit generator every manor is planned from (`new`, `next`, `below`, `step`).
- `src/shared/Crossing.luau` — the Servants' Exit's guard: `minDistance` (a lower bound on every legal walk),
  `minSeconds`, `verdictFor` (reach, room, time).
- `src/shared/PosGuard.luau` — the position guard: `seed` / `reseed`, `cost` (the shortest legal walk between two
  samples), `step` (outside, jump, the bank, the settle window). `Crossing.walkBound` is the walk bound it spends.
- `src/shared/Board.luau` — the NIGHTS SURVIVED board's pure rules: `encode` / `decode`, `keepHigher`, `rank`,
  `publicView`, `friendsView`, `rowText`, a TTL cache and a token bucket.
- `src/server/Main.server.luau` — world building, the night loop, persistence.
- `src/client/Hud.client.luau` — display only.
- `src/client/Haunt.client.luau`, `src/shared/HauntArt.luau`, `src/shared/Nightfall.luau` — the eye candy
  (`EYECANDY.md`). `src/shared/EnvBands.luau` / `Rest.luau` are the plus1-jump template verbatim;
  `src/shared/Hazards.luau` is the template plus five additions (elevation clamp, `ctx.paused`, `ctx.held`,
  `cancel`, `threatLive`). `src/shared/Calm.luau` is "fewer flashes" (Reduced Motion or the ⚡ toggle), read by
  both client scripts.
- `tests/NightModel.luau` — Chase.spec's simulation + a session model, used by `tests/Pacing.spec.luau`.
- `tests/*.spec.luau` — the pure specs, run straight from the luau CLI.
- `tests/check_walk.luau` — WALKS the built world. The most important gate in the repo.
- `tests/check_world.luau` — the join-time guards and the exit door, in the built world.
- `tests/check_boot_guard.luau` — four hostile-Config boots; takes a case argument.
- `tests/Board.spec`, `tests/Crossing.spec`, `tests/Salt.spec` — the board's, the guard's and the salt's pure rules.
- `tests/PosGuard.spec` — the position guard: honest walkers are never voided (with the margins), the cheats are.
- `MARKETING.md` — the clip list (8 clips for `tools/film_game.py`, with staging and honest captions).
- `tests/_mutate.py` — the mutation driver that produced the table below.
- `../robloxemu/check_nightwatch.luau`, `../robloxemu/check_nightwatch_hud.luau` — NOT ours to
  edit; the three files above exist in `tests/` for exactly that reason. Whoever owns `robloxemu/`
  may want to fold them in. `../robloxemu/check_nightwatchmanor_*.luau` ARE this game's (the eye-candy
  checks; `_kit` is their shared setup; `_fairgate` takes `-a light|hazards|rest`; `_flash` takes
  `-a storm|calm`; `_sitdrop`, `_save` and `_caps` came with the second review; `_board` (the NIGHTS SURVIVED board,
  public and friends, through the real server) and `_guard` (the salt never leaves ServerStorage, a retry is the same
  manor until it shifts, the exit's guard) with pass 2; `_posguard` (2026-10-11: the exploit, an honest walk, a lag
  gap and a respawn through the real server, the guard as it ships; every other check runs with it off, see the kit)).

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
2. ~~**One currency, not two.**~~ DECIDED 2026-09-30 (owner: take recommended): one currency, relics.
   The description no longer says "& cash", and was rewritten against the code (README.md).
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
9. ~~**No leaderboard surface.**~~ CLOSED 2026-10-01 (pass 2): the NIGHTS SURVIVED board stands in every safehouse,
   public and friends, ranked on the server's best night, earliest first on a tie (`docs/complete-game-standard.md`
   §3; "Secret manors, the exit's guard and the board", above). There is still no HUD ranking.
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

0. The night shift (standard §5): the Studio list (`EYECANDY.md` §11, item 16 for pass 2), the thumbnails (§12, seven
   shots), the clips (`MARKETING.md`; `tools/film_game.py` needs Nightwatch scenarios first), creating the experience,
   the maturity questionnaire, publishing, then marketing. An independent review of pass 2 has not happened.
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
4. ~~Decide the currency question~~ DECIDED 2026-09-30: one currency; the description matches the code.
5. Then the usual ship path: create the experience, git-ignored `publish_nightwatch.bat` with the
   Open Cloud key inline, maturity questionnaire (the Preview page is ground truth — a green check
   means "answered", not "No"), then Public. `git push` does NOT update the live game.
