# CLAUDE.md — StormGrow: Mutation Farm (Roblox)

Context so a fresh session can continue. Sibling of `plus1-jump/` (the eye-candy templates), `deep-vein/` (the
layout) and the other Roblox-Lab games; same stack: Config-driven, pure modules tested from the luau CLI,
authoritative server, display-only clients, phone-first HUD, `robloxemu` headless checks.

## What it is
A farming game where the weather runs on the real clock, the same in every server (storm :x0, frost :x5,
rainbow after the :00 and :30 storms). Only ripe crops catch it: marks multiply a crop's value (x5, x5, x8, up to
the Tempest x200). Six farms per server, 8 crops, 6 fields, 7 environment bands on the lifetime harvest, a
56-entry Almanac that the public + friends board ranks. Full spec: `DESIGN.md`. Eye candy: `EYECANDY.md`. Clips:
`MARKETING.md`. Store text: `README.md`.

## State (2026-10-01)
- **v1 built test-first; every gate green; not published; never opened in Studio; never played by a person.**
- **REVIEW-1 (2026-10-01, `REVIEW-1.md`)** closed 11 findings of two adversarial reviewers and 5 found on the way.
  The big one: taps are no longer ClickDetector hitboxes (6-stud invisible columns sent two taps in three to the tile
  in FRONT of the one tapped); the client picks the tile under the thumb against what is drawn (`Pick.luau`) and sends
  `Tap(slot, key)`. Also: idle rest after 90 s (it rested a normal farmer half the time), a readable porch board 15
  studs from the pad, load retries and recovery, a crashed server's expired lock taken over, newer-version records
  never written, the board writes only what a save landed, freed farms handed to whoever waits, a prompt cooldown,
  StreamingEnabled pinned, the hazard ring drawn ON the porch/pad/soil (it was buried under them), the owner sign
  lowered (it hid field 1 from the spawn camera). Gates now: 17 spec files 1,007/0, `tests/project_check.py` 5/0,
  the walk 26/0, 13 headless checks (below). Mutation sweep: 57 mutants, 56 killed, M14 equivalent, CONTROL and
  BASELINE green, sources byte-identical (62 files) before and after.
- Before REVIEW-1 (the build and the resume pass): specs 16 files, 967 passed, 0 failed. Headless: `tests/walk.luau` 21, `check_stormgrow` 164, `_compile` 72,
  `_env` 104, `_hazards` 103, `_rest` 32, `_hud` PASS (10 viewports x 4 modes, overlap = true), `_save` 38,
  `_wire` 18, `_board` 27, `_firstmin` 23, all 0 failed. The walk (real clock, real odds) was run at 60 boot
  phases over the hour (every 2 min, on the minute and at :01 past it): 59 green, 1 red in the walk's own rejoin
  assertion (trap 13), fixed; then 6 of 6 green at the phase that failed.
- **Resume pass (2026-10-01, after a usage cut-off during the mutation sweep):** the server, the three clients and
  the game-logic modules re-read, the templates hash-checked against plus1-jump, every gate re-run. Found and fixed: a locked seed row's client-side refusal ("Unlock 🌽 Corn first") vanished at the next
  0.2 s HUD refresh (now queued like a server toast: `pushToast`); two mutants SURVIVED all 27 gates (no light
  cap, no action rate limit), so `check_stormgrow_env` now exercises the cap at MaxLights = 5 and `check_stormgrow`
  fires two taps in one instant; a third (band cards before the profile loaded) survived a later run, so the env
  check now plays a slow, locked load; the CONTROL went red twice, on phase-dependent check set-ups (trap 17).
  The sweep driver now lives in `tests/_mutate.py`; final run: 25 mutants, 25 killed, CONTROL and BASELINE green.
- Measured: the brag (Eye of the Storm) at 36.6 min median for the normal player (p10 33.4, p90 39.2); fast 36.1,
  slow 39.5; ignoring the forecast 45.8; band 7 at 120.8 min; all 56 entries at 4.3 h for a player who follows
  the "N to find" hint. First plant 0.8 s after joining. After REVIEW-1, played through the real server and clients
  with every tap a click on the screen (8 long walks, 8 boot phases): the brag at 33.0-39.3 min (median 36.8), 1,651
  clicks all on the tile aimed at, one hazard per 159-213 s (median 173 s), 3.8-14.6% of frames in rest.

## Gates (run all of them; rebuild the bundle first, every time)
```
cd D:\Claude\Roblox\robloxemu
py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau        # ALWAYS first: checks read the bundle

cd D:\Claude\Roblox\stormgrow
luau tests/<each>.spec.luau          # 17 files (Pick.spec since REVIEW-1); Pacing.spec takes ~20 s
luau tests/walk.luau                 # the player's path, every tap a click ON THE SCREEN (reads the bundle)
py -3 tests/project_check.py         # default.project.json: StreamingEnabled pinned false, the Rojo tree

cd D:\Claude\Roblox\robloxemu
luau check_stormgrow.luau            # world built+parented, spawn, prompts, board renders, the core loop
luau check_stormgrow_compile.luau    # every source compiles; no string require; no os.clock
luau check_stormgrow_env.luau        # bands follow Harvested, glide, budgets at every band/seam/event, brag
luau check_stormgrow_hazards.luau    # ring = zone, dodge in 8 directions, pitches, rarity (~26 s)
luau check_stormgrow_rest.luau       # rest is never an exploit
luau check_stormgrow_hud.luau        # hudcheck, overlap = true, 4 modes per viewport
luau check_stormgrow_save.luau       # lock, owner token, read-only, failed load, BindToClose
luau check_stormgrow_wire.luau       # nothing secret replicates; the remote surface
luau check_stormgrow_board.luau      # public + friends, cached reads, upward writes, failure path
luau check_stormgrow_firstmin.luau   # the first minutes, as a new player sees them (taps on the screen)
luau check_stormgrow_aim.luau        # REVIEW-1: a tap lands on the tile you see; no silent tap; the spawn view
luau check_stormgrow_slots.luau      # REVIEW-1: a freed farm goes to whoever waits, at once, even mid-save
luau check_stormgrow_stream.luau     # REVIEW-1: tiles that stream in late / out; one crop folder per tile
```
`luau` is the luau CLI (append `2>&1`). `luau-compile` and `luau-analyze` are not on this machine; the compile
check covers the compile half with loadstring. A full run takes about 3 minutes (about 1 minute 8 at a time).
Counts after REVIEW-1: specs 1,007 (Board 53, ClientClock 4, Economy 78, EnvBands 124, EnvConfig 129, Farm 54,
Growth 13, Hazards 111, Hints 14, Mutation 116, Pacing 10, Pick 29, Profile 53, Rest 55, Text 20, Weather 74,
responsive 70), project 5, walk 26, `check_stormgrow` 164, `_compile` 75 (25 sources), `_env` 104, `_hazards` 114,
`_rest` 32, `_hud` PASS, `_save` 75, `_wire` 20, `_board` 47, `_firstmin` 24, `_aim` 22, `_slots` 12, `_stream` 11,
all 0 failed. `tests/Aim.luau` is the shared aiming helper (not a gate).

## This game's traps (each one bit during the build or is a standing rule)
1. **Ripeness is strict on the server** (`now >= at + grow`); the client shows ripe 0.25 s LATER
   (`Growth.shownRipe`), so every tap it offers is accepted.
2. **The server clock is `os.time()` at boot + the `tick()` difference.** Headless, `tick()` is the virtual clock
   and `os.time()` is real, so checks fast-forward weather and growth. Never time anything with `os.clock()`
   (CPU time, frozen headless): the compile check fails any source that does.
3. **Planting times are stored to the millisecond** (`Economy.tap`). The server clock is fractional; a DataStore
   stores JSON and the emulator keeps 14 significant digits, so a raw time came back changed and a rejoin saw every
   crop replanted (the walk found it: 0 of 18 tiles identical). 10 + 3 digits survive.
4. **The session lock owns the record**: a GUID token per session, checked by EVERY write, the release on leave
   included (fork-tower REVIEW-4 §10). The stored field is `session = { token, lockUntil }` (DESIGN.md said
   `until`, a Luau keyword). A failed load plays read-only and never writes a default over real data; a locked
   record waits 6 x 5 s, then plays read-only; a session whose token is gone stops writing and says so.
5. **Only the strike loop grants marks and Almanac entries** (`Mutation.strikeTick`, unseeded `Random.new()` in
   the server script). No remote accepts a mark, an entry or a count (`check_stormgrow_wire` fires junk at all
   three). There is no seeded RNG module at all (the template `Rng.luau` was dropped as unused).
6. **Hazards on flat ground** (`HazardGlue.luau`): the camera pitch floor (-25) keeps lane STARTS above the root;
   the ground skim keeps the DRAWN hazard above ground + 1, because a descending lane's true flight dips 3.21 studs
   under the ground after it passes the player (a finding of `tests/EnvConfig.spec`). Hits use the true flight.
7. **A farm action is activity for rest**: it wakes a rest AND resets the idle timer (`Sky.client`), or a farmer
   tapping from the porch drifts into idle rest every 20 s with the hazard clock frozen (the walk found it).
8. **Spawn**: a real `FarmPad_<k>` SpawnLocation per farm, enabled only while claimed; `plr.RespawnLocation` set
   in `PlayerAdded` before any yield; the facing write waits for `char.Parent` (robloxemu/SPAWN-ORDER.md §3).
   `MarketPad` is the first enabled spawn in the tree, for a seventh player.
9. **Attributes only hold primitives**: Roblox rejects a table attribute, the emulator does not
   (`check_stormgrow_wire` sweeps for it).
10. **One client connection per server->client remote** (Toast, Board), in `Hud.client`.
11. **The board view is a SurfaceGui each client creates and parents to the board part**, so two players at the
    board see their own view, and the hudcheck (which measures PlayerGui) never mistakes it for a screen panel.
12. **Emulator limits met here** (not game defects): `Player.DisplayName` is nil (the server falls back to Name);
    `FireClient` reaches the one client whatever the target (read `Board:sentTo(plr)` for content);
    `GetNameFromUserIdAsync` answers `User_<id>` for anyone not in the server; `GetFriendsAsync` does not exist
    (checks inject one); a rejoin needs the client scripts re-run by hand (`tests/walk.luau` does it).
13. **The real clock's phase is an input to every headless run.** The server clock starts at the real `os.time()`,
    so the weather a check sees depends on when it runs. A sweep over ten boot phases (2026-10-01) failed
    `check_stormgrow` at 4, the board check at 1 and the walk at 2, all in set-up assumptions (joining during an
    event marks the first crops; "the next storm" can be seconds away; a strike during the first second after a
    rejoin adds a mark). `check_stormgrow` and `check_stormgrow_board` now boot at a stated phase via
    `ClockOffsetSeconds`; the walk keeps the real clock and asserts only what holds at every phase. Re-run a
    phase sweep after changing a check that waits for weather. The same strike can grant a NEW Almanac entry in
    that first second (60-phase sweep, 2026-10-01: boot at :13:01 rejoins in the :30 storm, count 2 -> 3), so the
    walk checks that every saved entry and mark came back and that the count did not fall, never that it is equal.
    To pin a phase for a sweep, copy the walk and set the BUNDLE's Config before the server boots:
    `h:_require(h.ReplicatedStorage.Config).Weather.ClockOffsetSeconds = (P - os.time() % 3600) % 3600`.
14. **Two boards, one view each**: the market board and a small board on every porch (the standard wants the
    board near spawn; a farmer spawns on the porch, ~105 studs from the market). Each client draws its view on the
    market board and on its OWN porch board only; both prompts toggle the same per-player view.
15. **The scratchpad is shared with other agents.** A `gates.sh` there was overwritten by another game's script
    mid-session; the mutation driver then ran the wrong gates and reported a false survivor. Keep tooling in a
    uniquely named folder (this build used `scratchpad/stormgrow_work/`) and make the driver refuse a run that
    does not print exactly the expected number of gate lines.
16. **A refusal the client says itself goes through the toast queue** (`pushToast` in `Hud.client`), never straight
    onto the label: the HUD refresh hides an expired line every 0.2 s, so a line written without a deadline flashed
    for one refresh (`check_stormgrow_firstmin`, mutant M25).
17. **A check that waits for weather must pick weather that suits its set-up.** Phase sweeps on 2026-10-01 (the walk
    at 60 boot phases; the wire check at 65 before its fix; then rest, hazards, wire and firstmin at 20 phases
    around event edges, 80 of 80 green) found two set-ups that broke near an event edge: the walk's rejoin count (trap 13) and the wire check, which ran to
    "the next storm" even when it began before its Radishes were ripe (boot at :29:45). The wire check now runs to
    the first storm at least 35 s away and asserts what its scan needs (a board payload per player, a strike
    toast), not a payload count. To sweep a check, copy it and prepend the bundle-Config offset of trap 13.

18. **A tap is picked on the client, against what is DRAWN** (REVIEW-1 B1). Never make an invisible part a click
    target: Roblox delivers a click to the first queryable part on the ray, and the 7.6 x 6 x 7.6 ClickDetector columns
    stood in front of the tiles behind them (1,575 aimed taps: 625 on the tile seen, 944 on another). `Pick.luau` slab-
    tests the soil plate (the Tile_ part is its 0.6-stud twin) and the crop parts; the server checks Tap(slot, key) as
    before. Headless there is no `Camera:ScreenPointToRay`, so Farm.client falls back to `Pick.viewportRay`.
19. **Every gate that taps must tap the SCREEN where it can** (`tests/Aim.luau`): the walk, firstmin, aim and stream
    checks stand where a farmer stands, pose the camera, find a point of the tile the player can see (its own oracle,
    never the game's Pick) and tap there. Firing the tile you meant hides every geometry bug. Its oracle looks past
    translucent glows (Transparency >= 0.6) and transient effects (hazard art, critters, bolts, pops), as a player does.
    A back-row tile can be hidden behind tall crops from the field's working spot: the walker then steps into the field
    (`walkTo`); 1 walk-in and 4 steeper cameras in 7,503 clicks over 60 phases.
20. **A walk that rejoins must disconnect the old client's input handlers** (`UserInputService` TouchTap/InputBegan/
    InputEnded) as well as RenderStepped: a stale Farm.client picked against destroyed crop parts and sent a second Tap.
21. **Idle rest is AFK safety, not a waiting farmer** (REVIEW-1 B2): at 20 s it rested a normal player 44-55% of a
    session with the hazard clock frozen; `IdleSeconds` = 90. The walk asserts the rest share (0-13% over 60 phases).
22. **The board writes only what a save has landed** (`savedValue`, REVIEW-1 A5); a new entry asks for a save within
    `SoonSeconds`, retried if it fails. A save still queued when the farmer leaves is DROPPED (it would re-lock the
    record after the release, check_stormgrow_save part 12).
23. **Draw things ON the floor the player stands on.** The porch (top 0.4), the pads (1.0) and the soil plates (0.6)
    are above the ground: the hazard ring at ground + 0.15 was buried under them (`HazardGlue.ringY` now, checked
    against the real parts at 3,577 points). The owner sign 4.5-7.5 studs up behind the pad hid field 1 from a 15-20
    degree spawn camera; it is a low plate now (check_stormgrow_aim part 4).
24. **The hazards check's `force` hook only QUEUES a launch while a hazard is in the air**: a hazard the clock launched
    on its own in a trial's band change made the trial adopt it, aimed where the farmer stood a trial before; ~2% of
    runs (before REVIEW-1 too: 2 of 96) had no stayer hit. `nextHazard` now lets it land first (96 of 96 green).

## Files
Server `src/server/Main.server.luau` (world, sessions, saving, the strike loop, the board). Clients:
`Hud.client` (every screen label, the board view, the only Toast/Board listeners), `Farm.client` (crops, marks,
strikes, onboarding), `Sky.client` (bands, events, scenery, critters, hazards, rest). Shared pure modules:
`Config`, `Weather`, `Growth`, `Mutation`, `Economy`, `Farm`, `Board`, `Profile`, `Hints`, `Text`, `ClientClock`,
`HazardGlue` (pitch floor, ground skim, and since REVIEW-1 the floor map the ring lies on), `Pick` (REVIEW-1: which
tile a tap lands on); client art: `ValleyArt`, `CropArt`. Test helpers: `tests/Aim.luau` (aiming like a player),
`tests/project_check.py` (the project file), `tests/_mutate.py` (the sweep). Templates, verbatim from plus1-jump (sha256):
`EnvBands` 42d148b6, `Hazards` bd470578 (the working copy with `threatLive`), `Rest` 45044098, `Responsive`
e9445b3d, `FxClient` b5f910b3; `Fx` 4109bcb7 = plus1-jump's 4b996c24 + the `Farm` preset. Their specs are copied
unchanged. `design/pacing-model.luau` (sha256 1f0ff4b6) is RETIRED: `tests/Pacing.spec.luau` + `tests/FarmModel.luau`
re-measure everything on the real modules and reproduce its numbers.

## Mutation sweep (2026-10-01)
Final run 2026-10-01, after REVIEW-1: `py -3 tests/_mutate.py`, 57 mutants + CONTROL + BASELINE over 32 gates; 56
killed, M14 equivalent (below), CONTROL and BASELINE green; the 62 source, test and check files byte-identical
(sha256) before and after. Earlier run (the resume pass): 25 mutants + CONTROL + BASELINE. Driver: `tests/_mutate.py [ids]` (header says how). Each mutant runs in its own copy of the game, the
emulator and these checks under `%TEMP%/stormgrow_mut/`, so the real bundle and `src/` are never touched; the
patched file's sha256 is recorded before and after; a killed mutant stops at its first failing gate; the CONTROL
(a patch nothing reads) and the BASELINE (no patch) run all 27 gates and must be green, or the run is void.

| id | mutant | killed by (first failing gate) |
|---|---|---|
| M1 | planting time not rounded to the ms | `Economy.spec` 76/2 |
| M2 | a farm action no longer counts as activity | `_rest` 31/1 |
| M3 | strikes ignore ripeness | `Mutation.spec` 112/4 |
| M4 | `onCharacter` does not wait for the engine's placement | `check_stormgrow` 158/6 (nobody faces field 1) |
| M5 | `RespawnLocation` never set | `check_stormgrow` 158/6 |
| M6 | saves ignore the owner token | `_save` 33/5 |
| M7 | the release on leave keeps the lock | `_save` 33/5 |
| M8 | drawn hazards may dive underground | `_hazards` 102/1 |
| M9 | no camera pitch floor | `_hazards` 102/1 in the final run; `EnvConfig.spec` 118/2 always (the hazards check notices only in some runs: its hazards are random) |
| M10 | the Almanac no longer hides the timeline | `_hud` (the almanac mode's own assertion) |
| M11 | no 44 px tap targets on touch | `_hud` (160 problems) |
| M12 | board writes may lower a score | `Board.spec` 51/2 |
| M13 | board writes not coalesced | `Board.spec` 52/1 |
| M14 | a read-only session writes the board | EQUIVALENT since REVIEW-1 A5: the board writes only `savedValue`, which a read-only session never raises (it has landed no save), so the `canSave` guard it removes is a second lock on the same door; all 32 gates green (kept in the sweep to show it) |
| M15 | a rainbow after every storm | `Weather.spec` 66/8 |
| M16 | no server distance check on taps | `check_stormgrow` 163/1 |
| M17 | rest does not freeze the hazard clock | `_rest` 30/2 |
| M18 | no cap on bolts | `_env` 103/1 |
| M19 | no cap on lights | `_env` 92/2: SURVIVED all 27 gates first (every band's lights fit under the cap, so the cap never acted); the env check now lowers the cap to 5 in memory |
| M20 | tiles on unbought fields plant | `Economy.spec` 71/7 |
| M21 | no action rate limit | `check_stormgrow` 163/1: SURVIVED all 27 first; `check_stormgrow` now fires two taps in one instant |
| M22 | band cards announce before the profile loaded | `_env` 101/3: SURVIVED all 27 first (the emulator's DataStore answers at once, so no client ever drew a frame before `Loaded`); the env check now joins a farmer past the brag whose farm another server holds for 12 s |
| M23 | the porch board's prompt does nothing | `check_stormgrow` 163/1 |
| M24 | harvests do not count toward the bands | `Economy.spec` 76/2 |
| M25 | a locked seed row's client-side refusal flashes for one refresh | `_firstmin` 22/1 (the resume fix, test first) |
| M26 | B1: the tap pick ignores the drawn crops | `_aim` 21/1 |
| M27 | B1: the tile part is a 6-stud invisible column again | `_aim` 18/4 |
| M28 | B3: a tap from too far is refused silently | `_aim` 20/2 |
| M29 | B3: the client drops taps beyond 32 studs | `_aim` 18/4 |
| M30 | B1: a tap the HUD took is also a farm tap | `_aim` 20/2 |
| M31 | B2: idle rest after 20 s again | walk 25/1 (the rest share) |
| M32 | B4: tiles that arrive later are never drawn | `_stream` 6/5 |
| M33 | B4: a tile that streamed out keeps its crop | `_stream` 8/3 |
| M34 | B4: the place streams | `project_check.py` 4/1 |
| M35 | an empty crop folder per replant (found in REVIEW-1) | `_stream` 7/4 |
| M36 | A1: a dead server's lock is never taken | `_save` 70/5 |
| M37 | A1: a lock that moved on is taken anyway | `_save` 70/5 |
| M38 | A2: one failed load call makes the session read-only | `_save` 72/3 (SURVIVED once: the background recovery could land inside the old 8 s window; the check now asserts the FIRST farm shown is the real one) |
| M39 | A2: an outage's read-only farm never reloads | `_save` 72/3 |
| M40 | A4: a newer version's record is rewritten | `Profile.spec` 51/2 |
| M41 | A3: the farm is freed only after the leave's writes | `_slots` 11/1 |
| M42 | A3: a freed farm is never handed to a waiting player | `_slots` 4/8 |
| M43 | A5: the board writes the live count | `_board` 46/1 |
| M44 | A5: a new entry waits for the autosave | `_board` (no summary: the entry never reached the profile) |
| M45 | A5: a failed entry save is not tried again | `_board` 45/2 |
| M46 | A6: no prompt cooldown | `_board` 44/3 |
| M47 | A6: a failed name is looked up on every view | `_board` 46/1 (SURVIVED once: the cooldown alone kept the flood's lookups at 1; the check now presses at a human pace) |
| M48 | B5: the porch board 36 studs from the pad again | `_board` 46/1 |
| M49 | B5: both prompts pressed from 16 studs | `_board` 45/2 |
| M50 | B5: the porch board lists ten small rows | `_board` 46/1 |
| M51 | B5: the porch board stands in front of field 1 | `_board` 46/1 |
| M52 | B5: the porch board turns its back on the spawn camera | `_board` 46/1 |
| M53 | B1: the server acts on another tile than the one tapped | `check_stormgrow` 151/13 |
| M54 | a save in flight at the leave re-locks the record (found in REVIEW-1) | `_save` 72/3 |
| M55 | the hazard ring drawn at ground height again (found in REVIEW-1) | `_hazards` 111/3 |
| M56 | the glue forgets the farm pads | `EnvConfig.spec` 127/2 |
| M57 | the owner sign back up behind the spawn pad (found in REVIEW-1) | `_aim` 20/2 |
| CONTROL | the market square's Material (nothing reads it) | GREEN, 32 of 32 gates |
| BASELINE | no patch | GREEN, 32 of 32 gates |

**25 mutants, 25 killed; the CONTROL and the BASELINE green.** Three needed a new assertion first (M19, M21, M22).
Two CONTROL runs went RED before that, and both were phase-dependent CHECKS, not the patch: the walk's rejoin
assertion (trap 13) and the wire check's "more than 10 payloads" set-up (booting at :29:26 sends 8). Both were
traced with phase sweeps and fixed (trap 17). That is why a RED control voids a run.

## Needs Studio
`EYECANDY.md` §8 (19 items since REVIEW-1; item 6 is now the tap path: TouchTap, ScreenPointToRay, gameProcessed).
Nothing here has been rendered.

## Deviations from DESIGN.md (all small; the owner may veto)
- The session field is `lockUntil`, not `until` (a Luau keyword).
- Hazards: the drawn position is clamped to ground + 1 (the design's "no lane point below ground + 1" does not hold
  for the true flight); see trap 6.
- Rest: a farm action also resets the idle timer (trap 7).
- The template `Rng.luau` is not shipped (unused; the only RNG is the server's unseeded `Random`).
- REVIEW-1: tiles are not ClickDetectors; taps are picked on the client and sent as `Tap(slot, key)` (DESIGN §8,
  §10, §12.2). `Config.Rest.IdleSeconds` 90, not 20 (DESIGN §5). The porch board is 10 x 6.6 studs at farm-local
  (15, 4), turned to the spawn camera, top 5 rows; both prompts reach 12 studs (DESIGN §7). The owner sign is a
  12 x 1.2 plate on the porch's front edge, no post. Loads retry 3 times, then play a fresh farm that never saves and
  keep retrying; a crashed server's expired, untouched lock is taken over; a record with a newer `v` is shown
  read-only; the board writes only saved values (DESIGN §8.4). A 7th+ player gets the next farm that frees up.
- The pacing spec runs fewer sessions than the design model (normal 200 x 150 min; fast, slow, nohold, combo
  100 x 60 min; planner 20 x 8 h) to keep it near 20 s; the medians match the design model's.
