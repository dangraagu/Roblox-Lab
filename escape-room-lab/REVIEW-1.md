# Escape Room Lab — REVIEW-1: closing the second adversarial review (2026-10-01)

Two adversarial reviewers probed the build after the first review's fixes (reviewer A: `scratchpad/erlx3-ex-v8n4`,
reviewer B: `scratchpad/rev3`). Nine findings. For each one: its probe was re-run on the UNCHANGED build (the
repo's source was byte-identical to both reviewers' copies, `diff -r`), a gate was written and watched fail,
the GAME was fixed, the gate went green, the reviewer's probe was re-run on the fixed build, and the fix was
mutation-tested. No git command was run, Studio was not opened, nothing was published.

Files changed: `src/server/Main.server.luau`, `src/client/Lab.client.luau`, `src/shared/Config.luau`;
`tests/EnvConfig.spec.luau`, `tests/LabModel.luau`, `tests/walk.luau`; `robloxemu/check_escaperoomlab_lifts`,
`_pair`, `_release`, `_hazards`, `_leak`; `CLAUDE.md`, `DESIGN.md` ([review-1] notes), `EYECANDY.md`,
`MARKETING.md`, `README.md` (not the store text, still 933 characters). Templates (`EnvBands`, `Hazards`, `Rest`,
`Responsive`, `FxClient` and their specs) are still md5-identical to plus1-jump's.

## Verdicts

| # | sev. | finding | verdict |
|---|---|---|---|
| A1 | medium | one idle player on a Pair Lift pad blocks every pair | **closed** |
| A2 | medium | the Solo Lift's doors can be held shut by looping clients | **closed** |
| A3 | low | leaving during an in-flight load holds the lock 45 s | **closed** |
| A4 | low | carrying: one partner absorbs hints and wrong tries, the other gets 3 stars | **closed** |
| B1 | medium | stepping out of the ring does not dodge for the first 1.45 s | **closed** |
| B2 | low | the Pair Lift takes a partner who walked away during the ride | **closed** |
| B3 | low | the second NEXT press says "The door is still shut." | **closed** |
| B4 | low | about 4 in 10 hazards fire exactly as the arrival grace ends | **closed** |
| B5 | low | the public board freezes once ten players reach 45 | **reproduced, not changed: the owner's standard prescribes it; owner decision** |

## The findings, one by one

### A1 — an idle player on a pad blocks every pair: closed
- **Reproduced** (`probe_padblock`, unchanged build): control (Gus 10 studs away) rode after 3 GO pairs (6 s);
  Gus idle on pad B: 30 GO pairs over 60 s, both stayed in the Atrium, Ben told "The Pair Lift is full." on
  every press. The probe's own output also showed one of a DEPARTING pair told "The Pair Lift is full."
- **Red**: `check_escaperoomlab_lifts` §6, 4 failed (not in a room, not together, not a pair, told "full");
  `check_escaperoomlab_pair`, 2 failed (a same-pad GO). The departing-pair message: lifts, 2 failed.
- **Fix** (`Main.server.luau`, GO prompt): the partner is a player on the OTHER pad who pressed GO inside the
  10 s window, the earliest first; whoever merely stands on a pad is ignored. A GO from the same pad as another
  GO is told `One player per pad: step onto the other pad and press GO.`; "full" is only for a third player
  during a countdown; one of the departing pair is told `The Pair Lift leaves in a moment.`
- **After**: `probe_padblock` with Gus idle on pad B: both rode after 3 GO pairs (6 s), as the control. Lifts
  §6 green.

### A2 — the Solo Lift's doors held shut by looping clients: closed
- **Reproduced** (`probe_doorhold`): door shut 57% of 120 s with one teleporting looper, 99% with two (longest
  open gap 0.00 s), 99% with three walkers.
- **Red**: lifts §2: the doorway blocked on the server in 1067 of 1200 frames of three riders on a loop; lifts
  §7, 2 failed (a rider who left the cab mid-ride was taken, and not told); `tests/walk.luau`, 2 failed.
- **Fix**: no door on the server at all. Each rider's client shuts its OWN door: Lab.client makes a collidable
  local part `SoloDoorLocal` in the doorway when its ride notice (now carrying `lift = "solo"`) arrives, and
  removes it at the next RoomState. A client simulates its own character, so only the rider bumps into it. The
  server checks at departure that each rider is still aboard (`aboard()`, the Solo Lift plus 0.5 studs); one
  who left stays in the Atrium, told `You stepped out of the lift before it left. Step back in to ride.`
- **After**: three riders on a loop for 60 s, 38 rides: **0 of 1200** frames with anything collidable in the
  doorway on the server. The walk: the rider's door is collidable, visible, 8 x 10 in the doorway; no server
  door shuts; gone 0.1 s after arrival. Whether a client-side `CanCollide` part really stops the local
  character is a Studio question (`EYECANDY.md` §8 item 22).

### A3 — a leave during an in-flight load keeps the lock: closed
- **Reproduced** (`probe_loadleave`, UpdateAsync 1.0 s): leaving 0.5 s after joining, the rejoin showed 0 stars
  and `canSave` false at +1.5, +3.5, +10.5 and +30.5 s, and recovered after 63.5 s (control: 1.0 s).
- **Red**: `check_escaperoomlab_release`, 8 failed (two orders: the transform runs at landing; the transform ran
  before the leave and the write landed after).
- **Fix**: `onPlayerRemoving` marks the session `gone` first; the load transform returns nil for a gone
  session; a load that landed "ok" for a session that is gone gives the lock back (`releaseGone`, only if the
  record still carries that session's token).
- **After**: `probe_loadleave`: the rejoin shows 11 stars with saving on after 1.0 s, as the control. Release
  check: in both orders no lock is left, the rejoin shows 11 stars and can save. Each guard is tested alone:
  in the "late" order any later write takes 5 s, so the fallback cannot hide a broken transform check.

### A4 — carrying: closed
- **Reproduced** (`probe_launder`): Ann solved every station, took the door hint and entered a wrong code; Ben
  made 1 Act call per room (the code). Ben 3 stars in each of 3 rooms (9, leaderstats 9), Ann 1 each.
- **Red**: `check_escaperoomlab_pair`, 10 failed.
- **Fix**: in a pair, Clean and Unaided are the PAIR's. A wrong try or a hint marks every member (`markTeam`);
  the mark stays with whoever carries on when the other leaves (`party.shared`); after a hint the room state
  goes to the whole party (the hint's TEXT still only to its taker); the escape card says
  `Clean star missed: a wrong try in your pair.` / `Unaided star missed: a hint was taken in your pair.`
- **After**: `probe_launder`: Ben 1 star per room (3 in all), Ann 1. Pair check: Eli, who only entered the code
  Dee worked out, 1 star; after Dee's hint and wrong try and her leaving, Eli's solo finish 1 star.
- **Cost, stated**: a partner can now cost you those two stars in one room (never Escaped); a replay restores
  them, leaving is one prompt. A partner who plays perfectly can still hand you the code: you get what the pair
  earned. DESIGN.md §4.3, §4.4, §11.2 and §14.2 carry [review-1] notes.

### B1 — stepping out does not dodge for 1.45 s: closed
- **Reproduced** (`rev3_dodge`, verbatim Hazards.luau, shipped Config, its range 1.30-2.50 s): a 3.9-stud step
  was hit 108 of 108 at 1.30-1.40 s (the reviewer measured the same from 0.40 s), 90 at 1.45 s, 0 at 1.50-2.00 s,
  49 at 2.10 s, 108 from 2.20 s; standing still is hit at 2.133 s. Cause: the lane re-aimed at the player for 1.5 s (`commit` 1.5), so the ring followed whoever
  stepped out, and a 4 studs/s drop touches the 3.5-stud zone 0.875 s before its arrival time.
- **Red**: `EnvConfig.spec`, 2 failed (540 of 684 trials hit when stepping out 0.0-1.8 s after the ring
  showed; the ring moved 3.900 studs); `check_escaperoomlab_hazards`, 2 failed (0 of 3 dodged with a step
  0.3 s after the ring showed; the ring moved 4.000 studs).
- **Fix** (Config only, the template stays verbatim): `commit = telegraph` (3.0) for all four kinds, so the lane
  LOCKS on its first frame and the ring stands where the player stood when it appeared.
- **After**: `rev3_dodge` over its full range: **0 of 108** at every reaction from 0.00 to 2.00 s, 1 at 2.05,
  49 at 2.10, 104 at 2.15, 108 from 2.20 s; standing still is still hit at 2.133 s. Through the real client:
  3 of 3 dodged at 0.3 s, the ring moved 0.000 studs. Eight full headless paths: every one of 36 step-outs 1.0 s
  after the ring showed dodged. The hit still lands at 2.13 s, not at 3.0 s: that is when a 4 studs/s drop
  reaches head height; the dodge window is now the whole time before it.

### B2 — the Pair Lift takes a partner who walked away: closed
- **Reproduced** (`rev3_pair`): Ben walked 15.0 studs off his pad 0.1 s into the ride and was in the room 2.7 s
  later, `members = Ann,Ben`.
- **Red**: lifts §8, 5 failed.
- **Fix**: the departure check above (`aboard()`, inside the Pair Lift plus 0.5 studs). Whoever left stays,
  told why; the other rides on solo and is told so.
- **After**: `rev3_pair`: Ben left behind at (12.0, 3.5, 12.0), Ann in the room alone.

### B3 — the second NEXT press: closed
- **Reproduced** (`rev3_next`): `NextPrompt.Enabled` true during the ride; Ben's notices
  `Going up to Reception... | The door is still shut.`
- **Red**: on the unchanged build lifts §9 could not start (the pair was not in a room after §8's failures, then
  a crash); the two assertions were shown to fail by mutants R7 (NEXT stays lit: `Enabled` true) and R8 (the
  press falls through to "The door is still shut."), each the old code path on the otherwise fixed build.
- **Fix**: NEXT is disabled as the lift leaves (both the room-to-room ride and room 15's ride to the Roof); a
  press already on its way is told `The lift is already on its way.`
- **After**: `rev3_next`: Enabled during the ride false; Ben's notices
  `Going up to Reception... | The lift is already on its way.`; Ben arrives in slot 2.

### B4 — hazards at the end of the arrival grace: closed
- **Reproduced**: the door station is never a legal spot, and the clock ran there and in the grace with the
  hazard held (`grounded = false`). Hazards check, red: 30 s at the door then a legal spot, the next hazard came
  after 0.1 s (the held one); in room 5, straight after a hazard, the first came **8.00 s** after arrival.
  (Reviewer: 15 of 40 hazards came 8.0 s after arrival in four full runs.)
- **Fix** (Lab.client glue): the clock runs only where a hazard may be released, a legal spot past the grace;
  everywhere else the glue passes `resting = true` and the clock is frozen. Nothing can back up.
- **Interval recalibrated**: with the door no longer exposed time, the template's 120-180 s gave 6-7 hazards per
  run to the Roof (four full paths, median gaps 241-302 s of play). The pacing model's exposed time was corrected
  to feeder time past the grace (it counted the whole room), and `Pacing.spec`'s own "rare, not absent" bound
  went red: 6.8 hazards. At **80-120 s**: 10.2 (green), and eight full headless paths met 9-11 per run, median
  gaps 170-206 s, the standard's one per 2-3 minutes of play. `EnvConfig.spec`'s pins moved with it (below).
- **After**: hazards check green (the door: the rest of the interval; room 5: 12.20-13.25 s after arrival over six runs). Eight full
  paths, 77 hazards: none at the end of a grace (the earliest 9 s after arrival), never two at once.

### B5 — the public board freezes: reproduced, not changed
- **Reproduced** (`rev3_freeze`, the shipped `Board`): ten 45-star entries at launch fill the top 10; a player
  who reaches 45 an hour later or a year later is not on it.
- **Why not changed**: `docs/complete-game-standard.md` §3 prescribes the metric's shape (cannot be inflated)
  and the tie-break (who reached it FIRST). On a metric capped at 45, a frozen top 10 is what that implies; the
  build's earlier note covered only the bot case and now says this. Changing it (a seasonal store, a different
  metric, showing the viewer's own rank) changes the owner's board, so it is an **owner decision**. The friends
  view still lets later players compare. Documented in DESIGN.md §11.2, EYECANDY.md §0 and §11, CLAUDE.md.

## Also changed while closing
- **The leak gate had a rare false positive**, found in this sweep: `check_escaperoomlab_leak` searched for the
  door code's array form everywhere, and a shelf's public `flasks` order uses colours 1-5, so `[1,4,3]` matched
  room 2's code 1 4 3 once in about 140 runs (40 reruns of the same build: 40 passed). The array search now
  skips the `flasks` field only; the code's text form is still searched everywhere. The first sweep's leak
  mutants still die (L1, L2 below).
- **The leak gate's Notice allowlist** gained `lift` (`"solo"` or `"pair"`), the one new payload key.

## Test expectations that changed (none weakened)
- `check_escaperoomlab_pair`: a second player on the same pad is sent to the other pad (was: told "full"; A1).
  Ben's room-1 escape is 2 stars, not 3, and his leaderstats 2: Ann's wrong code costs the pair's Clean star
  (A4). Ben's Unaided star is gone after Ann's hint, not kept (A4). Each is the finding's fix, not a looser bound.
- `check_escaperoomlab_lifts` §2: the server door's "shut for the ride / open after" assertions are replaced by
  "nothing collidable in the doorway on the server, ever" plus the rider's own door in the walk (A2).
- `tests/EnvConfig.spec.luau`: the interval pins 120/180 -> 80/120 and the probe's rate 140-160 s -> 92-108 s per
  hazard of exposed time (B4: exposed time was redefined; the play-time rate is pinned by `Pacing.spec`).
- `tests/LabModel.luau`: exposed time = feeder time past the grace (was the whole room).
- `check_escaperoomlab_hazards`: "every hazard came in the Archive room" now allows room 5 (the B4 section rides
  on to the Archive's second room).

## Mutation sweep (scratch copies; the repo never edited)

`scratchpad/erlc1/mutate_r1.py`: each mutant is applied to a fresh scratch copy of `escape-room-lab` and the
`robloxemu` checks, the bundle is rebuilt THERE, the mutant's whole text (or a removal's absence) is checked in
that `build/escape-room-lab.luau`, and all 31 gates run. **24 of 24 killed, both controls survived all 31.**
Every mutant: in_bundle = true.

| # | finding | mutation | killed by (first failing assertion) |
|---|---|---|---|
| R1 | A1 | any player standing on my pad blocks GO (the old rule) | lifts (Bo told "full"), pair (same pad) |
| R2 | A1 | the partner may stand on the same pad | pair |
| R3 | A2 | a server door shut in the doorway for every ride | lifts (1054 of 1200 frames blocked), walk |
| R4 | A2 | the rider's client never shuts its own doors | walk |
| R5 | A2 | a Solo rider is aboard wherever they stand | lifts (taken to a room) |
| R6 | B2 | a pair member is aboard wherever they stand | lifts (Bo pulled into the room) |
| R7 | B3 | NEXT stays lit during the ride | lifts (`Enabled` true) |
| R8 | B3 | a NEXT press during the ride falls through | lifts ("The door is still shut.") |
| R9 | A3 | the load transform ignores `gone` | release ("late" order: lock held) |
| R10 | A3 | no release after a load that landed for a gone session | release ("early" order: lock held) |
| R11 | A3 | leaving does not mark the session gone | release |
| R12 | A4 | a wrong try marks only the one who made it | pair (Ben 3 stars) |
| R13 | A4 | a hint marks only its taker | pair (Ben's Unaided kept) |
| R14 | A4 | the pair's reason text is the solo one | pair |
| R15 | A4 | after a hint only the taker gets the new room state | pair |
| R16 | B1 | the lane follows the player for 1.5 s (spider commit 1.5) | EnvConfig (540 of 684 hit), hazards |
| R17 | B4 | the old clock: running at the door and in the grace, the hazard held | hazards (0.1 s; 8.00 s after arrival) |
| R18 | B4 | the interval back to 120-180 s | EnvConfig, Pacing (6.8 hazards) |
| R19 | A1 | a GO from the departing pair is told "full" | lifts |
| R20 | A2 | the rider's doors stay until the timeout | walk (door still there after arrival) |
| R21 | A2 | the rider's doors do not collide | walk |
| R22 | A2/B2 | a rider left behind is not told why | lifts |
| L1 | leak | the door code as an attribute (the first sweep's S5) | leak, compile |
| L2 | leak | dark door rows show their guess (the first sweep's S6) | leak |
| CTL1 | control | the Atrium directory's title text | **survived all 31** |
| CTL2 | control | the colour of the rider's door | **survived all 31** |

**Sources byte-identical**: sha256 of all 54 files in `escape-room-lab/src`, `escape-room-lab/tests` and
`robloxemu/check_escaperoomlab*.luau`, taken before the final sweep and after it, are identical
(`scratchpad/erlc1/sha_pre_final.txt` = `sha_post_final.txt`). The three game files the mutants touched:
| file | sha256 (before = after) |
|---|---|
| `src/server/Main.server.luau` | `92f94630eecd87218da3a14a9698cb15d9d0c163a87055b8fac4a3bb7507ecf2` |
| `src/client/Lab.client.luau` | `90b3c63c86dcd67d5e4e7a11d9327d139fc0931fb1a35a093ea5e5697efb56be` |
| `src/shared/Config.luau` | `8f08c2ae13a4ab9d6441f2007ee5e5e54d516dabaef99641740a310e97d02d08` |

## Final gates

All 31 gates, 6 runs in a row on the final source, the bundle rebuilt before each run: **186 of 186 exited 0**.

| gate | count (every run) |
|---|---|
| specs: Text, CodeLock, Shelf, Lamps, Lab, Profile, Board, RoomView, Decor | 1346, 90, 54, 66, 173, 49, 68, 52, 51 passed; 0 failed |
| EnvConfig (+3 assertions: the dodge window, the still ring, the hit time) | 203 / 0 |
| Pacing | 11 / 0 (normal: the Roof p50 39.1 min, p90 41.2; 45 stars p50 69.5; 10.2 hazards) |
| templates, verbatim: EnvBands, Hazards, Rest, responsive, Rng | 124, 111, 55, 70, 32 / 0 |
| the walk (+4: the rider's doors) | 37-38 / 0 (one assertion per door line read; rooms are random) |
| check_escaperoomlab | 116-117 / 0 (the count follows room 1's random puzzle; the unchanged build gives the same spread) |
| HUD fit, overlap = true | PASS, 60 viewport x mode measurements, 712 controls, 0 spill |
| env, budget, compile, act, friends, hint, save | 114, 5, 63 (21 sources), 25, 16, 14, 41 / 0 |
| hazards (+14) | 64 / 0 |
| leak | 45 / 0 |
| lifts (+21) | 55 / 0 |
| pair (+12) | 53 / 0 |
| release (+10) | 22 / 0 |

The walk, as a new player on an 800x360 touch phone: spawn 0.00 studs from AtriumSpawn; 18.4 studs to the Solo
Lift in 1.15 s, the rider's doors shut and the ride took 3.1 s; room 1 escaped with 3 stars (7 taps), room 2 with
3 (8 taps); 16.5 s and 124.9 studs from the first step to room 2's exit cab; 22 local parts. Eight full headless
paths (the reviewer's `rev3_path`, shipped settings): join to the Roof in 34.9-36.8 simulated minutes with 45
stars, rejoin keeps 45 stars with saving on, at most 53 local parts and 3 emitters, no scheduler error.

## The owner's standard (`docs/complete-game-standard.md`)

| item | status |
|---|---|
| §1 core loop reachable from join; walk the real path | met: the walk (join, the Solo Lift with the rider's own doors, rooms 1-2 through the real HUD); eight full headless paths join -> 15 rooms -> the Roof -> rejoin (45 stars kept, `canSave` on) |
| §1 spawn per SPAWN-ORDER.md | met: one enabled SpawnLocation, RespawnLocation first; `check_escaperoomlab` |
| §1 nothing secret replicates; no seed | met: leak gate 45/0 (re-scoped, its mutants still killed); no seed exists |
| §1 DataStore discipline | met: pcall, session token on every write, `canSave` only with the lock, string keys; a failed load retried; the release final; a session that is gone takes no lock (A3) |
| §1 no silent no-ops | met: every new refusal says why (`One player per pad...`, `You stepped out of the lift...`, `The lift is already on its way.`, `The Pair Lift leaves in a moment.`) |
| §2 Fx preset, signature particles, >= 5 bands glided | met (unchanged): env 114/0 |
| §2 hazards: rare, telegraphed, the ring IS the hit zone, stepping out always dodges, one at a time, cost little | met, now also in the first 1.45 s (B1) and with no backlog (B4): 9-11 per run, median gaps 170-206 s of play |
| §2 rest / pause, never an exploit | met (unchanged): the Break freezes the clock and earns nothing |
| §2 budgets capped in code | met: the rider's door draws on the reserved share for one ride in the Atrium, where no hazard can be live; budget 5/0, max 53 local parts over full paths |
| §2 brag moment in 30-45 min | met by model: the Roof at p50 39.1 min (p90 41.2); 45 stars at p50 69.5 min. Human times are assumptions |
| §2 phone first, overlap = true | met (unchanged): HUD fit PASS, 60 measurements, 712 controls, 0 spill |
| §3 public + friends board, un-inflatable metric, first-reach ties | met as prescribed; B5 (the public top 10 freezes) is its consequence: owner decision |
| §3 no Robux, no gambling, no pay-to-win | met: nothing is sold |
| §4 README store text <= 1000 chars | met: 933 characters, ASCII, unchanged |
| §4 EYECANDY.md needs-Studio list and thumbnail shot list | met: 29 Studio items (5 added: 25-29, item 22 rewritten), 6 shots |
| §4 MARKETING.md clip list | met: 8 clips (the spider clip's staging updated for the fixed ring) |
| §4 CLAUDE.md gates and traps | met: gate table updated, traps 13 and 19 extended, 20-23 added |
| §4 every gate green, TDD, mutation-tested with a control | met: red first for every finding (B3 via its mutants), 24 of 24 killed, controls survived |
| §5 night shift (Studio, thumbnails, clips, universe, publish) | not done, by rule |

## Still open
- **Studio** (00:00-06:00 only): `EYECANDY.md` §8, all 29 items; new or changed here: 22 (does a client-side
  `CanCollide` door stop the local character, with no rubber-banding), 25 (prompt Exclusivity may hide NEXT or
  ATRIUM, 4 studs apart), 26 (the Roof's 3.5-stud rails are under the 7.2-stud jump: a fall to the Atrium's roof
  or the void, then a respawn), 27 (BackDown 8.02 studs from the Roof arrival with an 8-stud reach), 28 (does a
  ring that stands still read as coming for you; is 2.1 s enough on a phone), 29 (does "a wrong try in your
  pair" read as fair).
- **B5**: the frozen public top 10, an owner decision.
- **Accepted residual, unchanged**: a solver script reaches 45 stars in about 62 s; with first-reach ties a bot
  that gets there before ten real players keeps a top-10 row.
- `luau-analyze` not run (not installed; only `luau.exe`).
- The friends board under load (one reader per server) is slow: 99 s headless for two 200-friend views.
- Nothing committed, published or made into a universe; `tools/film_game.py` has no scenarios for this game.
