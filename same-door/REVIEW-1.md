# REVIEW-1: The Same Door, the first adversarial review, closed

Date: 2026-10-01. Two independent reviewers attacked the second-pass build (they wrote nothing in the
repo; their probes ran on scratch copies). Reviewer 1 tried to cheat and to lose data; reviewer 2 walked
the player path. This pass reproduced every finding on the unchanged build first, then fixed the GAME
test-first: each new assertion was watched failing on the old code, and each was mutation-tested
(section 4). Nothing was committed, published or opened in Studio.

Reproduction tools: the reviewers' own probes (`check_sdx_seal1/ready/save/speed`, `check_rv_reach`,
`tautvsP.luau`, `textw.py`) rerun against a bundle built from the unchanged sources; "the first build"
below means the second-pass sources exactly as reviewed (sha256 recorded before any edit).

## 1. The findings

| # | sev. | finding | reproduced | status |
|---|---|---|---|---|
| R1-1 | critical | ready-phase teleport: start the clock inside seal 1's circle, or behind a closed wall | yes | **closed** |
| R1-2 | high | a speed script on the published line passes at 5-11 % over it, not 2 % | yes | **closed** |
| R1-3 | medium | one failed save at the finish loses that run forever | yes | **closed** |
| R1-4 | medium | a session lock is never re-acquired: one failed release unranks the next session | yes | **closed** |
| R1-5 | low | P is not the shortest line: every honest walk of P beats "perfect" | yes | **closed** |
| R2-1 | medium | a knock followed by Leave leaves the character stuck (PlatformStand) | yes | **closed** |
| R2-2 | medium | the hub board cuts off its own text, including the empty-friends message | yes | **closed** (look: needs-Studio) |
| R2-3 | low | the Dawn Sanctum's critters spawn ~155 studs from the player | yes | **closed** |
| R2-4 | low | leaderstats Streak shows a streak that has already ended | yes | **closed** |
| R2-5 | low | lanes are held for a whole session, so player 13 can never run | yes | **closed** |
| A-1 | (this pass) | a 0.4 s replication stall voids an honest walk on a straight hall | found | **closed** |
| A-2 | (this pass) | the new P's descent can stall on one corridor | found by the walk | **closed** |

No finding was rejected: every one reproduced with the reviewer's own numbers or close to them.

### R1-1 (critical): a script re-enters the lane anywhere before the line

**Reproduced.** `check_sdx_seal1 -a 1` on the first build: "clock started on the teleport sample true,
seal 1 taken on it true", the script finished Sealer in 21,478 ms against an honest walk of P in 22,875.
`check_sdx_ready -a 111`: a map dump in 22 hops over 2 ready-phase runs (81 of 81 cells, no clock ever
started), then a wall skip across the closed west entrance wall: Sealer in 21,689 ms against an honest
32,948. Cause as the reviewer described: ignored out-of-lane samples froze the guard's clock, the gap
widened the continuity allowance, and the re-entry sample both started the clock and took the seal.

**Fix** (`src/server/RunState.luau`, `src/server/RunCheck.luau`). Before the line, the only way back
into the lane is the antechamber: a re-entry anywhere else voids ("you re-appeared inside the halls
without walking in from the antechamber") before it can start a clock, take a seal or reveal a cell, and
a re-entry into the antechamber is a fresh arrival (`RunCheck.arrive`: the windows start over). Defence in
depth: `RunCheck.passCell` now fills any gap in the run's corridor with a shortest open path, so the taut
line can never cut a wall (`Dungeon.funnel`'s portals assume adjacent cells).

**Tests, failing first.** `tests/RunCheck.spec.luau`, "the ready phase": 9 assertions failed on the first
build (no clock, no seal, no reveal beyond the arrival batch, void, for a seal-1 hop after 55 s, a hop 15
studs past the line after 1 s, a hop across the closed west wall after 55 s; and "every consecutive pair
in the run's corridor shares an open passage" after a 2.5 s server hitch). `robloxemu/
check_samedoor_cheat.luau`, "the ready phase", through the real server Heartbeat: 5 failures and then a
crash on the first build; all pass now.

**After.** The reviewer's probes on the fixed build: the map dump stops at its first hop with 2-3 of 81
cells known (the arrival batch) and the run void; with no map the wall skip and the seal-1 leg cannot be
planned. `check_samedoor_cheat`: "ready hop -> void", "ready wall skip -> void", nothing on the board or
in the profile.

### R1-2 (high) and R1-5 (low): P was looser than the server's own check

**Reproduced.** `tautvsP.luau` (200 days, the real RunState/RunCheck): the server's taut line of a walk
of P was 0.9153-0.9732 of P (p50 0.9470), so a script on the published line passed the whole-run check
up to 1.048x-1.114x (p50 1.077x); a P walker's official time was 0.9886-0.9926 of P. The new
`Dungeon.spec` assertions on the first build: 40 of 40 days finished under P (worst 250 ms), 0 of 40
voided at 1.03x, and an independent sampled search found a shorter line on 8 of 8 days (worst 32.15
studs shorter).

**Fix** (`src/server/Dungeon.luau`, `src/shared/Config.luau`). P is now `Dungeon.tightLine`: the
shortest line in exactly the geometry `RunCheck.finishCheck` measures, `Check.TautMargin` (2) off every
jamb (there is no separate P margin any more), the start anywhere on the line, each seal touched within
`Pickup.Radius - Perfect.PickupInset` (3.75; the inset makes a 60 Hz walk of the published line surely
take it), the end ON the Door's 4-stud circle where the clock stops. Corridors: every simple cell path
within PathSlack 4 of the BFS distance whose centre line is within 2 x the ends' reach of the best (a
line moves at most as far as its ends do). Free points: coordinate descent (projection on the line, the
closest point of a segment or the reflection point on a circle, the nearest point of the Door's circle),
plus a corridor-switch search (A-2). The record is version 2 in `SameDoor_Days_v2`: a v1 perfectMs can
never validate.

Because P moved (0.912-0.969 of the old one on 200 days, median 0.937), the medals moved with it:
**Silver 1.71, Gold 1.33, Sealer 1.18 x P** (were 1.60 / 1.25 / 1.10 on the old P): about the same
seconds on a median day, the same slack over the best possible line on every day (which closes R1-5's
"looser on some days than others"). `Perfect.MinSeconds/MaxSeconds` went from 22/34 to 21/32 (300 mints:
P p10 22.2, p50 25.7, p90 29.9 s; acceptance 73.5 %).

**Tests, failing first.** `tests/Dungeon.spec.luau`, "P is the server's own lower bound": on the first
build 3 failed (40 of 40 days under P; 0 of 40 caught at 1.03x; 8 of 8 days beaten by the independent
search). `tests/RunCheck.spec.luau` and `check_samedoor.luau` now expect a walk of P to take P (the first
build's "a perfect bot finishes a little under P" was the defect). `check_samedoor_cheat.luau`: "a script
walking the published perfect line at 1.03x is voided" FAILED on the first build ("got finished").

**After.** `design/measure/residual.luau` (200 days): a 1.00x walk of P takes exactly P (official/P
1.0000 min, p50 and max); the server's taut line of it is 0.9957-0.9998 of P; the fastest factor at which a
script on the published line still passes is **1.020 on every one of the 200 days**. `tightcheck.luau`:
the independent search finds no line shorter than P on 150 further days (P is at most 0.002 studs above
its sampled line). The spec's 40 days: never under P, P reachable within 2 ms, 1.03x voided on 40 of 40.

The 2 % that remains is the stated tolerance against the best possible line, and it is now the same
line players are shown. It assumes a character can come 2 studs off a jamb and graze a pickup circle
(needs-Studio 23): if real characters cannot, honest bests sit a little above P and a script gains that
much on top.

### R1-3 (medium): one failed save at the finish lost the run

**Reproduced.** `check_sdx_save` part 1: finished Sealer 24,659 ms, `unranked true, posted false`;
90 s of good autosaves later the profile's best was nil, the board nil, Best "--", and after a rejoin too.

**Fix** (`src/server/Main.server.luau`). A verified finish waits in `p.pendingFinishes` until a commit
that carries it LANDS: every commit applies the pending finishes inside its UpdateAsync transform with
`Ledger.applyFinish` (still the only place a medal, a Door day or a streak moves) and drops exactly the
ones it carried once the write is in. `settle` then posts what changed and tells the player ("Your Sealer
run of 24.66 s is saved and on today's board."). The finish card says "Saving failed just now. This run is
kept and saved at the next try (within 20 s)."

**Test, failing first.** `robloxemu/check_samedoor_save.luau` part 1 (new): 6 failures on the first
build, all pass: the run lands in the profile one autosave later, on the board, in the player list, with
a toast, and survives a rejoin.

### R1-4 (medium): a session lock was never re-acquired

**Reproduced.** `check_sdx_save` part 2: Bo's release write fails, he rejoins 10 s later ("open in another
server"), and 130 s into the new session a Sealer finish is still unranked, the board and profile empty.

**Fix** (`src/server/Main.server.luau`, `Config.Save.LockRetrySeconds`). A session that found its
profile locked retries just after that lock runs out; one whose load failed retries every 10 s. On taking
the lock it says so ("Your profile is loaded now: this session saves and ranks, the runs you finished
while waiting too.") and the runs it kept land. A load the player left during gives its lock straight
back (it would otherwise block the next join for 45 s). Only a session that can never save (no store, or
a newer session took over) shows a run as not saved.

**Test, failing first.** `check_samedoor_save.luau` part 2 (6 failures on the first build) and part 3,
leaving during the load (1 failure: the lock stayed until 45 s later). All pass.

### R2-1 (medium): a knock followed by Leave left the character stuck

**Reproduced.** `check_rv_reach`: knocked in hazard slot 1's ring, Leave 0.3 s later: at the fire
PlatformStand true and Sit true 5 s later, and still PlatformStand 2 s into the next run.

**Fix** (`src/client/Dungeon.client.luau`). `releaseKnock()`: a run that ends, voids or finishes, or a
return to the hub, stands the player back up at once.

**Test, failing first.** `check_samedoor_eyecandy.luau` 3b (new): a knock, then the run becomes "ended",
"void", "finished" or "hub" 0.3 s into it: 4 failures on the unfixed client (plus 3 knock-on failures in
later sections, from the character left lying), all pass.

### R2-2 (medium): the board cut off its own text

**Reproduced.** The new audit in `check_samedoor.luau` on the first build: the footer at y 450-510 on a
480 px canvas ("BoardView.Foot at (20, 450) size (440, 60) leaves the 480 x 480 canvas"), and none of the
13 board labels and 4 plaque labels shrank or truncated. The reviewer's `textw.py` widths (Montserrat as
the GothamBold stand-in): the public sub-line 625 px and a row with "[SEALED]" 494-753 px in 440 px.

**Fix** (`src/client/Board.client.luau`, the plaque in `Main.server.luau`). Rows are columns: rank,
name (truncates with "..."), time, medal or a SEALED plate. Every other label shrinks to fit under a
`UITextSizeConstraint` cap; the footer has 80 px for 3 wrapped lines; the plaque is 8 x 5 studs (was 6).

**Test, failing first.** `check_samedoor.luau`: every board and plaque label lies on its Part, and every
one shrinks or truncates; the footer wraps and shrinks. 4 failures on the unfixed client, all pass.
`design/measure/boardtext.py` (worst-case reading, TextSize as em): the empty-friends message renders on 3
lines at 22 px, the sub-lines at 20 px, the SEALED plate at 18 px, a 13-character name whole on the board
and on the plaque, a 20-character name as its first 12-14 letters and "...". How it really looks is
needs-Studio 12.

### R2-3 (low): the Dawn Sanctum's birds flew 155 studs away

**Reproduced.** `check_rv_reach`: band 5, 5 birds, nearest 153.6 studs from the player. The new check on
the first build: closest band-5 critter 114.6 studs, farthest 174.3.

**Fix** (`src/client/Dungeon.client.luau`). Outside the grid (the antechamber, the Sanctum) critters
circle the player.

**Test, failing first.** `check_samedoor_eyecandy.luau`: every band's critters come within 16 studs of
the player, and in the Sanctum all 5 birds are within 12. 2 failures on the unfixed client; now 5 birds,
the farthest 9.4 studs away.

### R2-4 (low): a broken streak still showed in the player list

**Reproduced.** `check_rv_reach`: last finish 3 days ago, stored streak 5, leaderstats Streak 5.

**Fix** (`src/shared/Ledger.luau`, `Main.server.luau`). `Ledger.liveStreak(life, today)`: the streak while
the last Door day is today or yesterday, else 0; the player list and the finish card use it. Ranks keep
using bestStreak.

**Tests, failing first.** `tests/Ledger.spec.luau` (6 new; the spec errored on the first build: no such
function) and `check_samedoor_save.luau` part 4 (1 failure on the first build: Streak 5).

### R2-5 (low): lanes were held for the whole session

**Reproduced.** `check_rv_reach`: after 12 players had entered once, the 13th got "Every lane is busy right
now. Try again in a moment." and stayed locked out however long the 12 sat in the hub.

**Fix** (`Main.server.luau`). `freeLane`: a lane goes back to the pool when its player is back in the hub
(Leave run, the Hub button, death, a reset, leaving the game); the finish and void cards keep it. With
every lane in a live run the toast now says "All 12 lanes are in runs right now. One frees as soon as a
player is back in the hub." MaxPlayers 12 stays a place setting (needs-Studio 15).

**Test, failing first.** `robloxemu/check_samedoor_lanes.luau` (new): 5 failures on the unfixed server,
all pass (Leave, death and the Hub button on a void card each free a lane; a live run's lane is never taken).

### A-1 (found this pass): a 0.4 s stall voided honest walks

When P changed, the existing assertion "a 0.4 s replication stall, then the real position, is ranked"
failed: it had been tested at ONE spot, where the line turned. On a straight hall the 0.5 s window then
spans 16 x 0.9 = 14.4 studs against a 14.0 limit. Swept along the whole line (every 40th frame) on the
first build: **25 of 44 spots voided**. Fix: `Config.Check.BurstSlack` 2 -> 3 and `SustainSlack` 2 -> 4.5
(each carries a 0.43 s stall). Now 0 of 42 spots void; 3 of them straddle a pickup and the server's chord
misses that seal, which stays lit for the player to step back into (needs-Studio 24). The cheats still
void: a 1.6x speed hack, a 2x burst, teleports, the lag switch (`check_samedoor_cheat`).

### A-2 (found this pass): the tight line's descent could stall on a corridor

The honest walk on pinned day 8 reported "the player's own line (367.5 studs) beat the day's perfect line
P (369.4)": over the passages it had seen, the walker found the corridor between seals (6, 4) and (2, 4)
that P's descent had passed over; that corridor only pays once both touch points move to suit it. Fix:
after the descent settles, `tightLine` pins each leg to each of its other corridors, descends, unpins and
keeps any shorter result. `Dungeon.spec` keeps the recorded day (maze, placement and the walker's
passages, copied from the run, not invented). Cost (`timing.luau`, this PC): mint 42 ms mean, validate
30 ms mean, 177 ms worst (the first build: 6.5 / 5.7 / 44.7), once a day per server.

## 2. Gates (final run, bundle rebuilt first)

Final run on the final sources (2026-10-01), every gate green:
- Specs: Bands 44, Board 48, Day 18, DoorHazards 46, Dungeon 69 (was 62), EnvBands 124, Grid 49, Ledger 62
  (was 56), Medals 42, Pacing 8, Pause 16, Rest 55, Rng 32, RunCheck 47 (was 32), responsive 70. **730
  passed, 0 failed** (second pass: 702).
- Headless checks: check_samedoor 105 (was 96), check_samedoor_secret 12, check_samedoor_cheat 49 (was 33),
  check_samedoor_days 24, check_samedoor_eyecandy 76 (was 61), check_samedoor_save 25 (new),
  check_samedoor_lanes 23 (new). **314 passed, 0 failed** (second pass: 226).
- check_samedoor_hud: PASS over 60 viewport x mode combinations, overlap = true, with the longest new
  reason texts in its fixtures.
- tests/walk.luau: 0 problems on the default day; 30 other pinned days in section 3.
- Pacing (normal profile, 20-minute sessions): first Silver p50 4.6 min, first Gold 8.0, **first Sealer
  36.6** (day 2 typically; earned on 37 % of days); fast Sealer 8.6; slow never (112 of 120); 0.350
  near-misses per running minute.
- Eye-candy budgets over the walk: parts 104 of 220, decor 7 of 30, critters 6 of 8, weather 1 emitter at
  26/s, client lights 1, emitters 2; Lighting written 10.01 times a second; bands 0 -> 1 -> 2 -> 3 -> 4 -> 5.
- Measurements: `residual.luau` and `tightcheck.luau` as in R1-2; `timing.luau` mint 42.4 ms, validate
  29.7 ms mean, 176.9 ms worst; store text 980 characters, ASCII.

## 3. Walk

`tests/walk.luau` (the honest player: it reads only what its own client shows), default day (Door #2),
phone landscape 800x360, touch, on the final build:
- Join: lands on HubSpawn (0, 6); the arch prompt is up after 0.28 s of walking. Antechamber card:
  "Sealer 34.99   Gold 39.44   Silver 50.71" (P 29.66 s); 2 cells sent.
- Loop 1, exploring at 13.6 studs/s: Bronze 1:17.86, rank Wanderer.
- Loop 2, the tight line over the passages it saw (44 cell steps, 474.5 studs = P) at 16: **29.81 s,
  Sealer, "THE DOOR IS SEALED"** (the brag moment; 0.15 s over P from the walker's own steering).
- Hub: the board's row 1 reads "1. FirstTimer 29.81 SEALED", the sub-line "Public (the board's prompt
  shows friends)"; it flips to Friends and back. Rest by the fire: sitting, view softened.
- Pause in a run: the clock went 0.50 -> 2.50 under the open sheet; Leave run ends the run, the player
  lands sitting at the fire, nothing posted. Rejoin: Best 29.81, Streak 1.
- 30 other pinned days (`-a 1..30`): **0 problems on every day** (before the corridor-switch fix, day 8
  reported its own line beating P: A-2). Loop 1 took 1:02.37 to 2:56.74; loop 2 earned Sealer on 28 days
  and Gold on 2 (days 3 and 4, where the explorer's map had missed the best route).
- Reviewer 2's probe on the final build: Streak 0 for a streak broken 3 days ago; after a knock and Leave,
  PlatformStand false at the fire and in the next run; in the Sanctum 5 birds, the nearest 7.6 studs away.

## 4. Mutation sweep

Driver: a scratchpad script (not committed). Per mutant: one string replacement, asserted to apply
exactly once; the bundle rebuilt and the mutated text found in `build/same-door.luau`; the named gates
run; a gate whose "N passed, M failed" line is missing counts as a harness error, never a kill; the file
restored and its sha256 checked against the original. A no-change baseline and a control (a change
nothing reads) must survive.

| # | mutation (file) | in bundle | gates: passed/failed | result | restored (sha256) |
|---|---|---|---|---|---|
| BASELINE | no change (`-`) | - | RunCheck.spec 47/0; Dungeon.spec 69/0; Ledger.spec 62/0; Medals.spec 42/0; check_samedoor 105/0; check_samedoor_cheat 49/0; check_samedoor_save 25/0; check_samedoor_lanes 23/0; check_samedoor_eyecandy 76/0 | SURVIVED | - |
| MR1 | ready phase: a re-entry anywhere in the lane is accepted again (no antechamber-only rule) (`RunState.luau`) | yes | RunCheck.spec 43/4; check_samedoor_cheat 45/4 | KILLED | yes |
| MR2 | the ignored ready-phase samples still widen the gap allowance (no fresh arrival on re-entry) (`RunState.luau`) | yes | RunCheck.spec 46/1; check_samedoor_cheat 49/0 | KILLED | yes |
| MR3 | the corridor is not filled across a gap (a non-adjacent cell is appended) (`RunCheck.luau`) | yes | RunCheck.spec 46/1 | KILLED | yes |
| MR4 | P is measured 0.5 stud looser than the check (margin TautMargin + 0.5) (`Dungeon.luau`) | yes | Dungeon.spec 67/2 | KILLED | yes |
| MR5 | P keeps every seal touch at the seal centre (no disc optimisation) (`Dungeon.luau`) | yes | Dungeon.spec 67/2 | KILLED | yes |
| MR6 | P keeps the start in the middle of the line (no free start point) (`Dungeon.luau`) | yes | Dungeon.spec 68/1 | KILLED | yes |
| MR19 | no corridor-switch search after the descent settles (`Dungeon.luau`) | yes | Dungeon.spec 68/1 | KILLED | yes |
| MR7 | Sealer at 1.16 P instead of 1.18 P (`Config.luau`) | yes | Medals.spec 40/2; Pacing.spec 7/1 | KILLED | yes |
| MR8 | the burst slack back at 2 (a 0.4 s stall voids honest walks again) (`Config.luau`) | yes | RunCheck.spec 45/2 | KILLED | yes |
| MR9 | a commit no longer applies the pending finishes (`Main.server.luau`) | yes | check_samedoor 87/18; check_samedoor_save 18/7 | KILLED | yes |
| MR10 | a finish whose save failed is dropped (not kept pending) (`Main.server.luau`) | yes | check_samedoor_save 18/7 | KILLED | yes |
| MR11 | a locked profile is never retried (`Main.server.luau`) | yes | check_samedoor_save 19/6 | KILLED | yes |
| MR12 | a player who left during the load keeps the lock (`Main.server.luau`) | yes | check_samedoor_save 24/1 | KILLED | yes |
| MR13 | a run that ends mid-knock leaves PlatformStand on (`Dungeon.client.luau`) | yes | check_samedoor_eyecandy 67/7 | KILLED | yes |
| MR14 | the board footer back at y 450 (straddles the bottom edge) (`Board.client.luau`) | yes | check_samedoor 104/1 | KILLED | yes |
| MR15 | board names neither shrink nor truncate (`Board.client.luau`) | yes | check_samedoor 103/2 | KILLED | yes |
| MR16 | critters outside the grid home on the entrance cell again (`Dungeon.client.luau`) | yes | check_samedoor_eyecandy 74/2 | KILLED | yes |
| MR17 | the player list shows the stored streak (broken or not) (`Ledger.luau`) | yes | Ledger.spec 60/2; check_samedoor_save 24/1 | KILLED | yes |
| MR18 | Leave run keeps the lane (`Main.server.luau`) | yes | check_samedoor_lanes 21/2 | KILLED | yes |
| CONTROL | the campfire emitter rate 10 -> 12 (nothing reads it) (`Main.server.luau`) | yes | RunCheck.spec 47/0; Dungeon.spec 69/0; Ledger.spec 62/0; Medals.spec 42/0; check_samedoor 105/0; check_samedoor_cheat 49/0; check_samedoor_save 25/0; check_samedoor_lanes 23/0; check_samedoor_eyecandy 76/0 | SURVIVED | yes |

**Result on the final sources: 19 of 19 mutants killed, 0 survived, 0 harness errors; the baseline and
the control survived; every mutated file was restored byte-identical (sha256), and all 48 source, test
and check files hash the same before and after the sweep.**

A first sweep on the sources one step earlier is why three of these rows look as they do: MR2 SURVIVED
there (the fresh-arrival test re-entered too close to where the character had left, so its burst window
saw nothing; the test now waits a second by the line first), and MR1 and MR9 were harness errors because
`check_samedoor_cheat` and `check_samedoor` crashed on the mutant after printing their failures (both now
report instead of crashing). Everything else, the baseline and the control matched.

## 5. The complete-game standard

§1 It works and is honest
- Core loop reachable from join: **MET.** The honest walk (default day and 30 pinned days, 0 problems)
  and `check_samedoor` join, explore, finish, Run again, use the board, rest, pause/leave and rejoin.
- Spawn per SPAWN-ORDER: **MET** (one enabled HubSpawn, RespawnLocation in PlayerAdded, no CFrame in
  CharacterAdded; the character lands at (0, 6)).
- Server-authoritative, nothing secret replicates: **MET**, and stronger: before the line a client can
  no longer re-enter the lane anywhere but the antechamber, so it cannot pull cells it has not walked to
  (`check_samedoor_secret` 12/0, the ready-phase cases in `check_samedoor_cheat`).
- DataStore safety: **MET**, and stronger: a verified finish waits until a commit that carries it lands
  (applied inside the one UpdateAsync, token-checked), a locked or unloaded session retries, a load left
  mid-way releases its lock (`check_samedoor_save`).
- No silent no-ops: **MET** (every refusal toasts; the lane-pool and lock messages now say what happens next).

§2 It looks good from the first build
- Fx preset and signature particles: **MET.**
- Bands: **MET**, and every band now has its critters around the player, the Dawn Sanctum's too.
- Hazards: **MET** (ring = hit zone; one at a time; 0.350 near-misses per running minute for the normal
  profile; a knock never outlives its run).
- Rest/pause: **MET** (rest only in the hub, earns nothing; the run clock never stops under the sheet).
- Budgets: **MET** (eye-candy walk: parts 104 of 220, decor 7 of 30, critters 6 of 8, weather 1 emitter
  at 26/s, lights 1, emitters 2).
- Brag moment: **MET** with the open owner question unchanged: the normal profile's first Sealer at a
  median of 36.6 cumulative minutes (Sealer on 37 % of days), usually on day 2; slow players top out at
  Gold. Long-term goals: Warden (7-day streak) and Keeper (30 Sealer days).
- Phone first: **MET** (UIScale root, 44 px targets, hudcheck PASS with overlap = true over 60 viewport x
  mode combinations, with the longest new reason texts in the fixtures).

§3 Players can compare themselves
- Public + friends board on a metric a script cannot inflate: **MET.** The metric is the server-measured
  time, and the published perfect line is now the server's own lower bound, so a script gains at most the
  stated 2 % over the best possible line (it passes at 1.020x and no faster on 200 of 200 days). The
  physical board's text fits it (`check_samedoor` audit) and the empty-friends message is whole
  (estimated 3 lines at 22 px); how it looks is needs-Studio 12.
- Nothing costs Robux, no gambling, no pay-to-win: **MET.**

§4 Ready to ship
- README store text: **MET** (980 characters, ASCII; "within 18%" for the Sealer).
- EYECANDY.md: **MET** (needs-Studio list now 27 items, 5 thumbnails; shot staging re-measured).
- MARKETING.md: **MET** (8 clips; the Studio door's numbers re-measured: P 25.65 s, seal 3 at 21.34 s).
- CLAUDE.md: **MET** (every gate incl. the two new checks, traps 1-25, the build's differences).
- TDD and mutation testing: **MET** for this pass (section 4).
- Adversarial review: **PARTLY MET.** The first review ran (two reviewers) and all 10 findings are closed
  here. The changes this pass made (the new P and its solver, the save queue and lock retry, the board
  layout, the lane pool) have not been reviewed by anyone but their author.

§5 Night shift: not started, by design (nothing published, no Studio).

## 6. Still open

- **Needs Studio** (EYECANDY.md §7, now 27 items): above all 23 (can a real character walk 2 studs off a
  jamb and graze a pickup circle, the clearance P and the check both assume), 1 (honest movement
  statistics for `Config.Check`), 24 (a stall over a pickup), 12 (the board's look), 19 (the pivot race:
  the stale position must be the hub's), 15 (MaxPlayers 12).
- **A review of this pass.** The new P and its solver, the save queue and lock retry, the board layout and
  the lane pool were written and tested by one agent. A second adversarial review should run before
  publishing.
- **Not testable headless:** the emulator's DataStore never yields, so the race this pass guards in
  `finishRun` (an autosave carrying a finish while the finish's own write waits) cannot be produced here;
  the guard (`f.res` set by whichever commit carried the finish) is reasoning, not a measurement. If a
  write lands but its pcall still fails, the next commit applies the same finish again: that only adds 1
  to that day's finish count (`Ledger.applyFinish` grants nothing twice).
- **Cost:** P now costs a server about 42 ms to mint and 30 ms to validate on this PC (177 ms worst), once
  a day; the first build's were 6.5 / 5.7 / 44.7 ms.
- **Unchanged from the second pass:** other players' characters replicate (a script watching another
  lane can learn passages early; v1 does nothing about it); `GetFriendsAsync` is stubbed and the
  DataStore budgets are the emulator's; the honest walk's explorer is one greedy player.
- **Owner decisions** (DESIGN §21): the brag moment lands on day 2 for most normal players (36.6 cumulative
  minutes median); slow players top out at Gold; MaxPlayers 12. New with this pass: the medal percentages
  171 / 133 / 118 (the brag minutes are steep in SealerPct: 117 / 118 / 119 / 120 give 50.9 / 36.6 / 30.6 /
  18.9 minutes).
- Nothing is committed (the ownership rules forbid it).
