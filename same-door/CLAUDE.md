# CLAUDE.md — The Same Door (Roblox)

A daily dungeon speedrun: one layout per UTC day, the same for every player; 3 Seals, then the Door; the
server times you; public + friends board. `DESIGN.md` is the spec (read §3, §5, §11 before touching the
server), `README.md` the store text, `EYECANDY.md` bands/hazards/rest/budgets/needs-Studio/thumbnails,
`MARKETING.md` the clips.

## State — v1 built and tested headless (2026-10-01). NEVER RUN BY A PERSON. NOT in Studio, NOT published, NOT committed.

Everything below is green on the emulator. Nothing has been rendered or played on a device. The
needs-Studio list (EYECANDY §7) is open in full.

Second pass (2026-10-01, later the same day): the walk was rewritten as an HONEST player (it reads only
what the player's client shows) and immediately found that the day's "perfect line" P was not the
shortest line (trap 14). Fixed test-first, with three smaller fixes: the Dawn Sanctum had no parapet over
the void, the finish card printed "1:17.86 s", and the pacing model's players could not find the
shortest line either.

Third pass (2026-10-01, `REVIEW-1.md`): two adversarial reviewers, 10 findings, all reproduced and
closed test-first. The big ones: a script could step out of the lane before the line and re-appear inside
seal 1's circle with the clock starting on that sample (trap 17); P was looser than the server's own
whole-run check, so a script walking the published line passed at up to 1.11x (trap 19); one failed save
lost a run for good, and a stale session lock unranked a whole session (trap 21). Two more were found on
the way: a 0.4 s replication stall voided honest walks on straight halls (trap 23), and the new P's
descent could stall on a corridor (trap 20, found by the honest walk).

## Gates — run all of them, in this order, after every change

luau = `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe`
(any luau CLI works; append `2>&1`). There is no luau-analyze/luau-compile here; `check_samedoor.luau` part
A compiles every source through `loadstring`.

```
cd robloxemu && py -3 wrap.py --game ../same-door --out build/same-door.luau    # ALWAYS first: checks read the bundle
cd ../same-door && for f in tests/*.spec.luau; do luau $f; done                 # 15 specs
luau tests/walk.luau                                                            # the honest walk: join, explore, Run again, board, rest, pause, rejoin
for k in $(seq 1 30); do luau tests/walk.luau -a $k | tail -1; done              # the same walk on 30 other pinned days (optional, ~30 s)
cd ../robloxemu
luau check_samedoor.luau            # compile, world built+parented, spawn, prompts reachable, 3 loops, board renders, rejoin, friends, owner token
luau check_samedoor_secret.luau     # pre-seeded day used verbatim, reveal <= 2 steps, no stray parts, no leak (+ planted-leak control)
luau check_samedoor_cheat.luau      # teleport, speed, burst, noclip, fly, lag switch, forged remotes; an honest walker still ranked
luau check_samedoor_days.luau       # failing Days store, midnight mid-run, invalid record fails closed, unknown version
luau check_samedoor_eyecandy.luau   # bands + glide, Lighting <= 10 Hz, budgets, reserved colours, hazards via remotes, rest
luau check_samedoor_hud.luau        # emu/hudcheck, overlap = true, 10 viewports x 6 HUD modes
luau check_samedoor_save.luau       # a failed save at the finish, a stale lock, leaving mid-load, the live streak (os.time shifted)
luau check_samedoor_lanes.luau      # lanes go back to the pool at the hub; a 13th player waits with a true toast
```

Measurement scripts (not gates; `design/measure/`, run from that folder): `residual.luau` (the speed-hack
residual against the published line, 200 days), `tightcheck.luau` (P against an independent sampled
search, `-a <days>`), `timing.luau` (what P costs a server), `studiodoor.luau` (MARKETING/EYECANDY numbers),
`boardtext.py` (board text sizes with PIL; Montserrat stands in for GothamBold).

Counts on 2026-10-01, REVIEW-1 pass (all green): Bands 44, Board 48, Day 18, DoorHazards 46, Dungeon 69,
EnvBands 124, Grid 49, Ledger 62, Medals 42, Pacing 8, Pause 16, Rest 55, Rng 32, RunCheck 47, responsive
70 (= 730 spec assertions); walk 0 problems on the default day and on 30 other pinned days; check_samedoor
105, secret 12, cheat 49, days 24, eyecandy 76, save 25, lanes 23 (= 314); hudcheck PASS over 60 viewport x
mode combinations. `Pacing.spec` takes about 3-4 min (every one of its 1680 days mints the tight P),
`Dungeon.spec` about 30 s; everything else a few minutes together.

**REVIEW-1 mutation sweep** (2026-10-01): 19 mutations of the REVIEW-1 code (the ready phase, the corridor fill, the tight P and its solver, the medals, the window slack, the save queue and lock retry, the knock release, the board fit, the critters, the live streak, the lane pool), same rules; **19 of 19 killed, the baseline and the control survived, 48 files byte-identical after.** The table is in `REVIEW-1.md` §4.

**Mutation sweep** (2026-10-01): 21 mutations of the game's own code, each applied to a byte-restored
file (md5 before/after), the bundle rebuilt, every gate run; a run whose gate lines were missing counts as a
harness error, never a kill. **21 of 21 killed; the baseline and the control survived.** Second pass: 4
more on the shortest line (MP1-MP4), **4 of 4 killed**, its own baseline and control survived. Tables at
the end.

## Traps this game has (read before editing)

1. **The layout is secret data, not a seed.** Never derive anything a client can see from a seed, a date or
   a public number. The day is `Dungeon.mint(Config, draw, ...)` with `draw` from two Roblox Randoms XORed
   (server) and stored in `SameDoor_Days_v2` (v1 until REVIEW-1). The only copy outside server memory is
   `ServerStorage.SameDoor.Day`. Never an attribute, a workspace value, a remote payload.
2. **Reveal follows validated movement only.** `RunState` sends a cell when the server has seen the root
   within `RevealSteps` (2) open steps of it, once, and nothing after a void. Do not "pre-send" cells to
   fight pop-in: that is the leak (mutations M2/M3 are killed by `check_samedoor_secret`).
3. **Never teleport a character inside a run.** The monitor voids it by design. Move into a run only with a
   server `PivotTo` into the antechamber (before the line nothing is timed). Film by walking.
4. **The run clock is the sum of the server's Heartbeat dt**, never `os.clock` (CPU time, barely moves
   headless) or `tick`. Caches and rate limits use `tick()`.
5. **Spawn:** exactly one enabled SpawnLocation (`HubSpawn`) and `plr.RespawnLocation = hubSpawn` in
   PlayerAdded. `CharacterAdded` never writes a CFrame (SPAWN-ORDER.md).
6. **Every profile write goes through `commit`** (one at a time per player): the stored copy is the truth,
   one-time grants happen only inside `Ledger.applyFinish` inside the UpdateAsync transform, and a write
   lands only while the record carries this session's token (fork-tower REVIEW-4 §10; mutation M9 is
   killed by check_samedoor part H). Do not write `p.data` wholesale from memory.
7. **The board encoding refuses reachedAt >= 2e9** (2033-05-18). Bump `SameDoor_Board_v1` before then.
8. **A stored day is never re-minted over**, even when invalid: that would change a day's layout mid-day.
   Invalid -> "failed its check", unknown `v` -> "out of date; rejoin" (check_samedoor_days).
9. **Reserved colours:** seal-gold (255, 200, 70) is for Seals only, hazard-red (230, 40, 40) for rings
   only; `Bands.validate` rejects anything within 75 RGB. A new decor colour must pass `Bands.spec`.
10. **Decor must not read cell content.** `Bands.decorFor` takes (wall key, face, band, cfg, hash01);
    `Bands.spec` pins its arity. A decor rule that looks at what is in a cell is a layout leak.
11. **Client-set player attributes** (`SameDoorClock`, `SameDoorWarn`, `SameDoorBand`, `SameDoorKnocks`,
    `SameDoorNear`, `SameDoorParts`, `SameDoorLightingWrites`) are the client scripts talking to each other
    and to the checks. They never reach the server and hold nothing secret. Keep it that way.
12. **Server ModuleScripts** (`src/server/Dungeon`, `RunCheck`, `RunState`) are not modelled by the harness;
    every check registers them into ServerScriptService before the server runs (as check_lostfounddepot
    does). `RunState` takes its dependencies as an argument: never `require("./X")` in game code.
13. **FireClient before the client connects**: the emulator drops it (Roblox queues it). The day's public
    facts are therefore also attributes on `ReplicatedStorage.SameDoorRemotes` (DayState, Door, PerfectMs,
    Silver/Gold/SealerMs, Studio, DayMessage).
14. **P is the SHORTEST line, not the line along one shortest cell path.** Per leg the corridors are every
    simple cell path up to `Config.Perfect.PathSlack` (4) steps over the BFS distance. The first build pulled
    ONE min-step BFS path: an equal-step staircase beats an L, so on 54 % of 200 days a shorter line existed
    (`design/measure/pgap.luau`). The search is capped (`MaxExpansions`, measured need 932) so every server
    recomputes the same number. See trap 19 for WHAT line P is since REVIEW-1.
15. **The Studio door's numbers in MARKETING.md and EYECANDY.md** (cells, P, when the line reaches each
    seal) come from `design/measure/studiodoor.luau`. Rerun it after any change to the generator or to P;
    REVIEW-1 moved P from 27.46 to 25.65 s and seal 3 from 22.46 to 21.34 s.
16. **Durations on cards use `Medals.formatDuration`** ("27.34 s", "2:31.05"), never `formatTime(..) .. " s"`.
17. **Before the line, the only way back into the lane is the antechamber** (REVIEW-1 finding 1). Samples
    from outside the lane are ignored (the pivot race); a re-entry anywhere else voids, and a re-entry into
    the antechamber is a fresh arrival (`RunCheck.arrive`). Ignored samples must never widen the gap
    allowance or empty the windows: the first build let a script step out for 55 s and re-appear inside
    seal 1's circle, the clock starting on that sample; it finished Sealer on 30 of 30 days, 3.9-19.2 %
    under an honest walk of P, and could dump the whole map first (`check_samedoor_cheat`, `RunCheck.spec`).
18. **Consecutive corridor cells always share an open passage.** `RunCheck.passCell` fills any gap the
    continuity check let through (a diagonal, a server hitch) with a shortest open path: `Dungeon.funnel`'s
    portals assume adjacency, and a skipped wall would shorten the taut line.
19. **P is the whole-run check's own lower bound** (REVIEW-1 findings 2 and 5). `Dungeon.tightLine`: margin
    `Check.TautMargin` (there is NO separate P margin), the start free on the line, each seal touched within
    `Pickup.Radius - Perfect.PickupInset`, the end ON the Door's pickup circle. Measured on the first build
    (P centre to centre, margin 2.5, a fixed start): the server's taut line of a walk of P was 0.915-0.973 of
    P, so a script on the published line passed at up to 1.114x (p50 1.077x) and every honest walk of P beat
    "perfect". Now (`residual.luau`, 200 days): a walk of P takes exactly P, the taut line is 0.9957-0.9998 of
    it, and the line passes at 1.020x and no faster on every day. Never give P its own geometry: change
    TautMargin and P follows. Records are v2 in `SameDoor_Days_v2` (a v1 perfectMs can never validate).
20. **The tight line's descent can stall on a corridor.** After the coordinate descent settles,
    `tightLine` pins each leg to each of its other corridors, descends, unpins, and keeps any shorter
    result. Found by the honest walk (`-a 8`: the player's own line beat P by 1.9 studs); `Dungeon.spec`
    keeps the recorded day. `tightcheck.luau`: 0 of 150 further days beaten by the independent search.
    Cost (`timing.luau`, this PC): mint 42 ms mean, validate 30 ms mean, 177 ms worst, once a day per server.
21. **A verified finish is never dropped** (REVIEW-1 findings 3 and 4). It waits in `p.pendingFinishes`
    until a commit that carries it LANDS (applied inside the transform with `Ledger.applyFinish`, then
    posted by `settle`). A session that found its profile locked retries just after that lock runs out (one
    whose load failed, every `LockRetrySeconds`), and its kept runs land then; a load the player left during
    gives its lock straight back. Only a session that can never save (no store, a newer session took over)
    shows a run "not saved" (`check_samedoor_save`).
22. **A lane is held from the arch until the player is back in the hub** (Leave run, Hub, death, reset,
    leaving): `freeLane`. The finish and void cards keep it (Run again reuses it). Not for the session.
23. **The movement windows carry a 0.4 s stall** (`BurstSlack` 3, `SustainSlack` 4.5): on a straight hall
    the 0.5 s window spans 16 x 0.9 studs. With slacks of 2, a 0.4 s stall voided an honest walk at 25 of
    44 spots on the spec's line. `RunCheck.spec` sweeps the stall along the whole line; a stall that
    straddles a pickup can still make the server miss that seal (it stays lit; needs-Studio 24).
24. **Board labels must fit their Part** (a SurfaceGui clips): every label TextScaled under a
    `UITextSizeConstraint`, or a name that truncates. `check_samedoor` audits every box on the board and the
    plaque; `boardtext.py` estimates the rendered sizes.
25. **The player list shows the streak as of today** (`Ledger.liveStreak`): the stored streak only moves at
    the next finish. Critters outside the grid circle the player (the Sanctum's birds were 150 studs away).

## Where the build differs from DESIGN.md, and why (measured)

* **The whole-run speed check** (DESIGN §11: "path length sampled every 0.25 s / time <= 16 x 1.02").
  Measured on a spec day: 0.25 s chords cut corners and read a real 477.9-stud walk as 468.0, so a whole
  run at **1.03x read 16.08 studs/s and passed**. Replaced by a lower bound noise cannot inflate: the
  run's time may not beat the **taut line through the cells it actually passed and the points where it
  took each seal** at 16 x 1.02 (`RunCheck.tautLine`, `TautMargin` 2). Measured: the published P at
  1.03x voids on 40 of 40 spec days and passes at 1.020x and no faster on 200 of 200 (`residual.luau`).
* **The movement windows** (DESIGN §11: slacks of 2): `BurstSlack` 3 and `SustainSlack` 4.5, so a 0.4 s
  replication stall on a straight hall is not a burst (trap 23).
* **Before the line, out-of-lane samples are ignored** (the pivot race, needs-Studio 19), and the only
  way back in is the antechamber, as a fresh arrival (trap 17).
* **P** (DESIGN §3.2: "string-pulled path along that route", centre to centre at margin 2.5): the
  shortest line in the whole-run check's own geometry, over every seal order and every corridor within 4
  extra steps (traps 14, 19, 20). On 200 days the new P is 0.912-0.969 of the old one (median 0.937).
  `Perfect.MinSeconds`/`MaxSeconds` moved from 22/34 to 21/32 with it (300 mints: P p10 22.2, p50 25.7,
  p90 29.9 s, acceptance 73.5 %).
* **Medals** (DESIGN §6.1: 1.60 / 1.25 / 1.10 P): **1.71 / 1.33 / 1.18 P** on the new P, about the same
  seconds on a median day and the same slack over the best line on every day. Sealer is steep: SealerPct
  117 / 118 / 119 / 120 put the normal profile's first Sealer at 50.9 / 36.6 / 30.6 / 18.9 minutes.
* **The brag moment** lands at a median of **36.6 cumulative minutes** for the normal profile (design:
  33.7; 39.7 in the second pass), inside [30, 45]: the model runs on the game's own generator, hazard
  schedule and P; its players plan the centre line (margin 2.5, `RunnerModel.PLAN_MARGIN`) with their slop
  on top. Normal Sealer on 37 % of days, Gold 83 %, Silver 96 %; fast Sealer at 8.6 min; slow players
  still top out at Gold (112 of 120 never Sealer in 14 days).
* **Decor on half the wall faces** (design did not fix a share; 1/3 measured bare: 4 pieces in view).
* **The lane shell is 25 server parts** (design: "about 25"): the 21 of the first build plus a glass
  parapet on the Dawn Sanctum's four edges, because the balcony stood over the void (`check_samedoor`
  casts 32 rays; 28 escaped before the fix).
* **The yesterday plaque is 8 x 5 studs** (6 x 5 in the first build: too narrow for "1. " and a
  13-character name next to a time; trap 24).
* **Lanes** (DESIGN §4: "recycled"): recycled when the player is back in the hub, not when they leave the
  game (trap 22).

## Files

Server: `src/server/Main.server.luau` (hub, lanes, the day, runs + Heartbeat monitor, profiles, board),
`Dungeon.luau` (generator, placement, perfect line, record, validation, reveal), `RunCheck.luau`
(movement guard), `RunState.luau` (one run). Client: `Hud.client.luau`, `Dungeon.client.luau`,
`Board.client.luau`. Shared: `Config` (every tunable), `Day`, `Medals`, `Board`, `Ledger`, `Grid`, `Bands`,
`DoorHazards`, `Pause`, `DungeonArt`; verbatim: `EnvBands`, `Rest` (+1 Jump), `Responsive`, `Fx`,
`FxClient`, `Rng`. Tests: `tests/*.spec.luau`, `tests/RunnerModel.luau`, `tests/walk.luau`.
`design/measure/` is the design stage's throwaway model (not mapped by Rojo), plus measurement scripts:
`pgap.luau` (the second pass: how far a centre line gets below the stored P; superseded by
`tightcheck.luau`), `studiodoor.luau` (the Studio door's layout and line timings for MARKETING/EYECANDY),
`timing.luau` (what P costs a server), and from REVIEW-1 `residual.luau`, `tightcheck.luau`, `boardtext.py`.
Reviews: `REVIEW-1.md` (the first adversarial review and how each finding was closed).

## Known gaps (the suite does not see these)

* Nothing renders headless: every look, the veils, the knock's feel, the SurfaceGui boards (EYECANDY §7).
* Physics: collisions with client-built walls, the camera under a 14-stud ceiling.
* `GetFriendsAsync` is stubbed; the DataStore budgets are the emulator's (1000).
* The tolerances in `Config.Check` are provisional until honest runs are recorded (needs-Studio 1).
* The first adversarial review (two reviewers) ran on the second pass; its 10 findings are closed in
  `REVIEW-1.md`. Nobody has reviewed the REVIEW-1 changes themselves yet (the new P, the save queue, the
  lock retry, the board layout): a second review should, before publishing.
* P and the whole-run check assume a root can come 2 studs off a jamb and graze a pickup circle; if real
  characters cannot (needs-Studio 23), honest best times sit a little above P and a script gains that much
  on top of the 2 %.
* Other players' characters replicate. Someone who watches another player walk their own lane sees
  passages they have not reached yet. The layout is the same for everyone by design, so this is the same
  as watching a stream of today's run, but a script could gather it automatically. Nothing in v1 hides it.
* The honest walk's explorer is greedy (nearest unseen cell, no wandering). Over the default day and 30
  pinned days (REVIEW-1 pass) its first run took 1:02 to 2:57, and its second run (the tight line over the
  passages it saw, at 16) earned Sealer on 29 days and Gold on 2, where its map had missed the best route.
  That is one scripted player. The pacing model's population is the measure.
* Owner decisions open (DESIGN §21): the brag timing reading (day 2), slow players' summit is Gold, MaxPlayers 12.

## Mutation sweep (2026-10-01)

Driver: a scratchpad script (not committed) that applies one string replacement, asserts it applied once,
rebuilds the bundle, runs every gate above (Pacing only for the medal mutation, to save 80 s a run),
restores the file and asserts its md5. **The first sweep was invalid and was thrown away:** Python called
WSL's `bash`, every gate failed to start, and all 22 entries read KILLED. The control caught it (a
mutation nothing reads cannot be killed). The rerun uses Git Bash, counts the gate lines, and starts with
a no-mutation baseline.

| # | mutation | killed by |
|---|---|---|
| — | BASELINE (no change) | survived, as it must |
| M1 | the 0.5 s / 3 s windows never fail | RunCheck.spec, check_samedoor_cheat |
| M2 | reveal 3 steps instead of 2 | RunCheck.spec, check_samedoor_secret |
| M3 | the arrival batch sends every cell | check_samedoor, _secret, _eyecandy |
| M4 | HubSpawn disabled | check_samedoor |
| M5 | Board.improve lets a worse time overwrite | Board.spec (the server never tries: `needsPost` gates it) |
| M6 | every finish counts a new Door day | Ledger.spec, check_samedoor |
| M7 | the ring drawn 20 % wider than the hit zone | check_samedoor_eyecandy |
| M8 | no height cap on a hit | DoorHazards.spec |
| M9 | no owner-token check in `commit` | check_samedoor (part H) |
| M10 | Lighting written every frame | check_samedoor_eyecandy |
| M11 | full-width card button row (Run again under the thumbstick) | check_samedoor_hud |
| M12 | Sealer at 1.11 P | Medals.spec |
| M13 | no whole-run (taut line) check | RunCheck.spec only (REVIEW-1 added the server-level 1.03x case to check_samedoor_cheat) |
| M14 | validate does not recompute perfectMs | Dungeon.spec, check_samedoor_days |
| M15 | loadDay re-mints over an invalid stored day | check_samedoor_days |
| M16 | rest allowed in a run | Pause.spec, check_samedoor_eyecandy |
| M17 | any z = 0 crossing starts the clock | Grid.spec |
| M18 | out-of-lane samples ignored while running | RunCheck.spec |
| M19 | tap targets not grown on touch | check_samedoor_hud |
| M20 | reserved colours not enforced | Bands.spec |
| M21 | RespawnLocation never set | check_samedoor |
| CONTROL | the campfire emitter's rate 10 -> 12 (nothing reads it) | survived, as it must |

## Second-pass mutation sweep (2026-10-01): the shortest line

Same rules (one string replacement, applied once, file restored and md5 checked). Each mutation was run
against `tests/Dungeon.spec.luau`. (Since REVIEW-1, `shortestLeg`/`bestLine` are the centre-line planner of
the pacing model; the day's P is `tightLine`, swept in the REVIEW-1 table below.) The new walk and check assertions were each watched failing on the
unfixed code before the fix: the walk's P guard (the player line was 501.6 studs against a P of 517.6),
`check_samedoor`'s parapet rays (28 of 32 escaped) and the card format (`Bronze  1:17.86 s`, shown failing
by restoring the old card line in a byte-restored copy).

| # | mutation | result |
|---|---|---|
| — | BASELINE | survived (62/0) |
| MP1 | `shortestLeg` keeps the FIRST path it finds, not the shortest | KILLED, 3 assertions (the staircase) |
| MP2 | `PathSlack` 4 -> 0 (min-step paths only) | KILLED: 5 of 120 days beaten, worst 0.964 P |
| MP3 | `bestLine` takes the first seal order, not the shortest | KILLED: 61 of 120 days beaten |
| MP4 | `perfectPath` reports 1 % longer than the line it returns | KILLED: 120 of 120 days off |
| CONTROL | `MaxExpansions` 200000 -> 150000 (no leg needs more than 932) | survived, as it must |
