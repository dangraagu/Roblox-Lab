# REVIEW-1 - Disaster Rounds: two adversarial reviews, closed

2026-10-07/08. Input: two independent adversarial reviews of the v1 build (an exploit reviewer and a reachability
reviewer; 13 findings, 11 after merging duplicates). Every finding was **reproduced first** with the reviewer's own
probe, then closed **test first** (the new assertion run red against the unfixed game), then fixed **in the game**, then
mutation-tested (every new assertion has a mutant it kills, plus one control no gate notices). **No finding was
rejected: all eleven reproduced.** One owner decision is open (F5's number).

Ground rules held: no git command, nothing published, Studio not opened. Written only in `disaster-rounds/` and
`robloxemu/check_disasterrounds*.luau` (+ its bundle). **There is still no luau CLI on this machine**: every number here
was measured with the build's Luau-to-LuaJIT shim (`<scratchpad>/dr/luaushim/luaurun.py`, see `CLAUDE.md`). Re-run all
gates with a real CLI when one exists. `<scratchpad>` is the session scratchpad named in `CLAUDE.md`; this pass's files
are under `<scratchpad>/r1/` (probes' outputs `out/`, gate script `gates_r1.sh`, mutation driver `mut/`).

## Findings

| # | reviewer finding | severity | before (reproduced) | after | gate |
|---|---|---|---|---|---|
| F1 | leaving, resetting, dying or falling in the 4 s outro wipes the streak just awarded (both reviewers) | high | leave 1 s into the outro: stored streak 6 -> 0, `lastEnd = left:6`, rejoin "You left during a round, so your streak ended at 6."; died / respawned / fell (-500): streak 1 -> 0, Played +2 for one round | streak kept, no `lastEnd`, lock released; no swept card, Played +1; a fallen body is put back on the Lookout | `_outro` A-D |
| F2 | fly to the off-island corner: no ring can be placed, the funnel cannot reach, no cell can crack | high | (55.8, 35, 55.8), Heat 5: 0 rings aimed in 6 of 6 meteor/tornado/quake rounds, all survived, streak 6 | swept "You fell into the sea" 0.6 s after leaving the island, in all four disasters; also (-55.6, 55.6) and (55.8, 0); over the island's last strip (51.9, 51.9) rings still come (2) and hit | `_exploit` 1 |
| F3 | a leave during an in-flight write loses the release and the leave's elimination | medium | leave in the outro behind the round-end write: lock not released (expires +300 s), rejoin waits then "won't save"; leave 7.6 s into a disaster while `Saving`: stored streak 9, no elimination, not released | release lands after the write in flight; mid-disaster leave stored as streak 0, `lastEnd = left`, released; `BindToClose` waits for it | `_outro` E-G |
| F4 | rest + the known last disaster lets a player skip one disaster kind | medium | play only after a flood (60 rounds, seed 626262): 15 played, **0 floods faced** | the next disaster is an even draw: after a flood, 2 of the 11 rounds played were floods; 11 back-to-back repeats in 40 natural rounds | `Round.spec`, `_exploit` 4 |
| F5 | best streak is unbounded for a script reading the replicated red (both reviewers) | medium | the build's own dodger: 40 of 40 rounds, swept 0, best 40 in 59 virtual min | the board counts a streak **up to 25**; the same bot: best 40, board 25 (first reached after 25 rounds), nothing written past it | `Progress.spec`, `_board`, main |
| F6 | JumpIn refusals: one toast per request | low | 500 requests in one tick -> 500 toasts | 2 (the first request's reason, one "One tap is enough.") | `_exploit` 2 |
| F7 | rings and the tornado's red drawn flat at one terrace; buried in a higher cell, while the hit is 2-D | high | ring 1 stud from a step up, player 1.5 studs onto the higher terrace: disc at y 8.15 under a top at 12, hit with no red visible; 216 of 412 rings in crowded rounds had red buried at a cell they reach | every red piece is a volume from 0.05 over the lowest top it reaches to 0.25 over the highest: 412 rings, 216 (52 %) over more than one level, **0 of 1 444 ring-cells without red at the ground** | `_terrace` 1-2, `_zones` 0-1 |
| F8 | the tornado catches players in its wake, where no red is drawn | medium | stop 4 studs behind the funnel: caught, never on a drawn ribbon (14 frames in reach off red, seed 901); red drawn up to 2.25 studs behind the funnel's centre; nothing drawn before touchdown | red = a 13-stud disc on the funnel and on every published point ahead + boxes between, nothing behind, from the name: 45 917 sampled points in reach all red, 28 746 points >= 0.05 outside none red (600 frames, 29 before touchdown); the wake case 20 of 20 frames on red | `_terrace` 3-4, `_zones` 3 |
| F9 | three quick taps on ☕ leave the client on a break while the server drops the player | high | after on/off/on: HUD "On a break", server `Resting = false`; dropped, swept, streak 6 -> 0, and dropped again | a SetRest over the rate is applied when the second is up (the last one wins), never dropped: at the drop `Resting = true`, not dropped, streak 6 | `_exploit` 3 (server and real HUD) |
| F10 | one stale position in the guard's quiet second sweeps a dropped player | medium | one deck sample 0.05, 0.15, 0.3, 0.5 or 0.8 s after the drop: 5 of 5 "Movement check failed" | 0 of 5; a 30-stud teleport 0.1 s after the quiet second is still caught | `Guard.spec`, `_guard` 4 |
| F11 | EYECANDY called three budgets "enforced in code" that were only measured | low | no code used `ServerParts` or `SceneryParts`; rings capped only by coverage (42 on a full island) | rings capped at `Budget.Rings` 16 in `Strikes.maxLive`; SkyArt trims a piece to 125 Parts and all scenery to 500; the server's variable sources at their caps: 50 fixed + 169 + 80 + 16 = 315 of 400 | `Strikes.spec`, `EnvConfig.spec`, `_env` |

### The fixes (all in the game)

* **F1** `endDisaster` moves the island's players from `cur.on` to `cur.returning`; `returnAll` takes both sets home.
  `sweepOut`, `onCharacter`, `Humanoid.Died` and `onPlayerRemoving` act only on `cur.on`, so the outro is no longer
  "during a round", and the fall rescue now covers it.
* **F2** `updateIsland`: a root over no cell for `GroundGrace` (0.6 s) in a row is swept out ("fell"), in every
  disaster and the drop (the flood always did this).
* **F3** `saveSession(plr, s, release)` works on the session object; the pending write re-uses it (`sessions[plr]` is
  cleared by the leave). `writesInFlight` counts down after the pending write; `BindToClose` waits up to 25 s for 0.
* **F4** `Round.pickKind(kinds, rand, force)`: an even draw, no history. `tests/RoundModel.luau` uses it, so the pacing
  numbers are re-measured (brag normal 35.1 min, p10 32.7, p90 38.3; fast 32.7, slow 41.9; Codex 1.9 h; New Dawn 168.1
  min).
* **F5** `Config.Board.StreakCap = 25`; `Progress.boardEntry(p, cfg)` -> (min(best, 25), the time it was first reached:
  new field `capAt`, saved). Used for the board write, the live value and the pinned row; `Board.luau` stays verbatim.
  The board's label says "best streak, up to 25". Why 25 (model, 1 500 sittings per profile, `<scratchpad>/r1/
  game_model/tests/capdist.luau`): a fast player's best reaches 25 in 43 % of one-hour and 82 % of two-hour sittings, a
  normal player's in 2 % / 5 %, a slow player's never. **Owner decision:** the number (`math.huge` = the old board).
* **F6** a `JumpIn` refusal over the rate is toasted at most every `Rates.JumpInToastSeconds` (2 s).
* **F7** `Zones.cellsUnderDisk`, `Zones.cellsUnderBox` and `Zones.redSpan` (pure, spec'd). The server's ring Part is
  that volume (attribute `GroundY` = where the projectile lands). A cell whose edge the red only touches is listed
  (the headless check found rings at x = 32.5 reaching x = 28.0 exactly; the hit test is edge-inclusive).
* **F8** `World.client` draws the tornado's track from the funnel (or, before touchdown, the touchdown point): discs
  and boxes, each a volume, pooled (no per-frame Instance churn), at most `Budget.PathRibbon` = 40 Parts (peak 34).
* **F9** `applyRest`: over the rate, the latest request is stored and applied by one `task.delay` when the oldest
  request leaves the 1 s window; a request that lands supersedes it.
* **F10** `Guard.sample`: inside the quiet second nothing is kept (`table.clear(g.samples)`); judging starts from the
  first sample after it.
* **F11** `Strikes.maxLive = min(coverageCap, Budget.Rings)`; `SkyArt.updatePiece` trims past `SceneryPartsPerPiece`
  and `SceneryParts`; `EnvConfig.spec` asserts the sums.

### Tests that changed meaning (each because the finding changed the rule, never to get green)

| test | was | now | why |
|---|---|---|---|
| `Round.spec` "never the same twice" | 0 repeats in 4 000 | 8 000 draws: each kind 25 +- 2 %, repeats 25 +- 2 %, every kind 25 % after every kind (+- 3 points) | F4: the old rule was the leak |
| `tests/walk.luau` round 2 | "a different disaster" | "a disaster is named" | F4 |
| `Strikes.spec` cap | `maxLive(island) == 42` | `coverageCap == 42`, `maxLive == 16`, a 17th ring waits ("cap") | F11 |
| `_zones` ring shape | flat at the centre cell's top + 0.15 | the volume over every cell the disc reaches, exactly | F7 |
| `_zones` path pieces | boxes `len + 0.5` between published points | discs on the track's points, boxes of exact length, track starting at the funnel | F8 |
| main check | waited 30 s for a drop from whatever phase | waits for the intermission (bot off) first | F4 made earlier rounds' lengths differ; the assertion is unchanged |

### Reproduction notes

* The reviewers' probes are re-run against the fixed build in `<scratchpad>/r1/repro/` (outputs `<scratchpad>/r1/out/`
  before, `out/after/` after). One stays "false" after the fix for a reason that is not the game: `probe_buried2`
  judges visibility by the ring Part's centre height; the ring is now a volume (8.05 to 12.25 for that case) and its
  centre is 10.15. `check_disasterrounds_terrace` 2 asserts the same case properly: red shows under the player.
* F4's and F10's headless assertions were written after the pure fixes were in the bundle, so their red evidence is
  the spec runs (`Round.spec` crashed on the new signature; `Guard.spec` 7 failed) plus the reviewers' probes, and the
  mutants F4 and F10 below, which restore the old code and are killed by spec and headless check alike.

## Mutation sweep

Driver `<scratchpad>/r1/mut/driver.py` (mutants `mutants.py`, the build's ported in `mutants_old.py`). Each mutant is
applied to a sandbox copy of the game, the sandbox bundle is rebuilt and checked (the `MUTANT:<id>` marker is in
`build/disaster-rounds.luau` and its sha256 differs from the clean bundle; multi-line mutants are checked by the sha256
only), its gates run, the file restored and its sha256 compared with the pre-mutation file. No run came back empty.

| mutant | what it breaks | killed by (passed/failed) |
|---|---|---|
| F1a | survivors stay in `cur.on` through the outro | `_outro` 37/14 |
| F1b | `returnAll` ignores the survivors | main 88/1 |
| F2 | off the island is never the sea | `_exploit` 16/12 |
| F3a | the waiting write looks the session up by player | `_outro` 41/10 |
| F3b | `BindToClose` does not wait | `_outro` 50/1 |
| F4 | the pick excludes the last kind again | `Round.spec` 69/2, `_exploit` 27/1 |
| F5a | the board metric is uncapped | `Progress.spec` 64/6, `_board` 30/4 |
| F5b | `capAt` never set | `Progress.spec` 67/3 (`_board` 34/0) |
| F5c | the board's label without the cap | main 88/1 |
| F5d | the live value uncapped | `_board` 33/1 |
| F6 | no JumpIn toast throttle | `_exploit` 27/1 |
| F7a | ring volume over its centre cell only | `_terrace` 21/2, `_zones` 68/2 |
| F7b | no 1e-6 in `cellRange` | `Zones.spec` 66/2, `_terrace` 22/1 |
| F8a | the track starts at the published point behind the funnel | `_terrace` 22/1, `_zones` 69/1 |
| F8b | no disc on the funnel | `_terrace` 21/2 |
| F8c | nothing drawn before touchdown | `_terrace` 21/2 |
| F8d | path boxes span only their centre cell | `_terrace` 22/1 |
| F9 | an over-rate SetRest is dropped | `_exploit` 25/3 |
| F10 | the guard keeps quiet-second samples | `Guard.spec` 14/7, `_guard` 19/10 |
| F11a | rings uncapped (coverage only) | `Strikes.spec` 44/3 (`_env` 85/0: the measured peak is 15) |
| F11b | SkyArt never trims | `_env` 83/2 |
| F11c | `SceneryPartsPerPiece` 126 (2 x 126 > 250) | `EnvConfig.spec` 150/1 |
| **CONTROL** | the ring's starting transparency 0.4 instead of 0.35 (the client re-pulses it every frame) | **survived all 31 gates**: 17 specs, 13 headless checks, the walk |

**22 of 22 killed; the control unnoticed.** The build's own 35 mutants (Z1-Z10, G1-G4, M1-M23 less M17, M19), ported
to the new code (Z1 now widens the ring volume, Z7 narrows the path boxes), were re-run against the changed checks:
**35 of 35 killed** (Z1-Z10 by `_zones`, G1-G4 by `_guard`, M15 by `_fair`, M11 by `_hud`, the rest by their spec,
`_wire`, `_save`, `_rest`, main or the walk). Every sandbox source was restored byte-identical (sha256).

## Gates (final run, `<scratchpad>/r1/gates_r1.sh`, bundle rebuilt first, 0 empty runs)

| gate | result |
|---|---|
| syntax (transpile + compile) | 57 files, 0 bad |
| 17 specs | **1 083 passed, 0 failed**: Board 77, EnvBands 124, EnvConfig 151, Flood 57, Guard 21, Hazards 111, MapGen 39, Pacing 27, Progress 70, Quake 17, Responsive 70, Rest 55, Rng 56, Round 71, Strikes 47, Tornado 22, Zones 68 |
| `check_disasterrounds` | 89 / 0 |
| `_hud` | PASS (overlap = true) |
| `_env` | 85 / 0 (peak 313 server Parts, 15 rings, 13 projectiles, 34 red path pieces) |
| `_rest` | 30 / 0 |
| `_save` | 41 / 0 |
| `_board` | 34 / 0 |
| `_wire` | 3 / 0 (10 566 ticks swept) |
| `_zones` | 70 / 0 |
| `_guard` | 29 / 0 |
| `_outro` (new) | 51 / 0 |
| `_exploit` (new) | 28 / 0 |
| `_terrace` (new) | 23 / 0 |
| `_fair` | 12 / 0 (0 of 1 600 bot-rounds lost at Heat 5) |
| `tests/walk.luau` | 24 / 0 |

Headless: **495 passed, 0 failed** in 12 counted checks, and the HUD check PASS.

## The standard (`docs/complete-game-standard.md`)

* **§1 works and is honest: met.** Core loop walked headless (walk 24/0, main 89/0). Spawn per SPAWN-ORDER (main).
  Nothing secret replicates (`_wire`; the kind is now an even draw, so the replicated `LastKind` says nothing). The
  DataStore rules hold, now also for a leave behind a write in flight and at shutdown (`_save`, `_outro`). No silent
  no-ops; the JumpIn refusal is still said, once.
* **§2 looks good: met**, with REVIEW-1's corrections: the red is exactly the hit zone on terraces and behind the
  tornado (`_terrace`, `_zones`); rest is never an exploit (F4, F9; `_rest`, `_exploit`); budgets are measured AND
  capped in code (F11). Brag 35.1 min (model). Phone first (`_hud` PASS, overlap = true).
* **§3 board: met with a cap.** "A server-measured metric that a script cannot inflate": a dodge script now reaches 25
  and nothing more, a run a fast human makes (F5, same principle as same-door REVIEW-1's lower bound). Ties to the
  first to reach it. The number is the owner's.
* **§4 ready to ship: met.** README store text 990 characters, ASCII; EYECANDY needs-Studio 26 items, 6 shots;
  MARKETING 8 clips; CLAUDE.md gates and 26 traps; every gate green; new assertions mutation-tested with a control.
* **§5 night shift: not done, by rule.**

## Still open

1. **No real luau CLI**: every count is from the shim. Re-run all gates with `luau` when one exists.
2. **Owner decisions**: the board cap's number (F5, 25); the even draw replaces "never twice in a row" (F4).
3. **Needs Studio** (`EYECANDY.md` §8, now 26): the red volume on a step (#2) and the tornado's pieces (#4) on a real
   screen; whether the engine ever shows the server a stale position after a drop, and for how long (#8: a stale
   sample AFTER the guard's quiet second still trips it); the default player list over ☕ / 📖 on PC (#23); honest
   roots never leaving the cells, so the sea rule never fires on a walker (#24); real `UpdateAsync` latency (#25); the
   board prompt's server-side reach (#26).
4. **Not re-measured**: a normal player's stray rate on the deck (the design model's 1 per 4.6 min), the first-minute
   medians (DESIGN §11); the planned `_spawn`, `_firstmin`, `_strays`, `_jumpin` checks are still covered only inside
   main, `_rest` and the walk.
5. A second review of REVIEW-1's own changes before any publish; `MaxPlayers = 8` at publish; v1 is silent. Nothing
   is committed (by rule).
