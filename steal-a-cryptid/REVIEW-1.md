# REVIEW-1 - Steal a Cryptid: two adversarial reviews of the 2026-09-17 build, and what was done

**Nothing here was opened in Roblox Studio. Nothing was committed, pushed or published.** Every
number below was measured by a script run in this pass; where a number moves from run to run (camps
are random per server) the file says so.

A naming note. Source comments and CLAUDE.md written before this file say "REVIEW-1" for the FIRST
probe round (2026-09-16, reviewer scripts in a session scratchpad, no report in the repo). This file
is the record of the SECOND round: two reviewers, an exploit lens (findings A1-A6) and a reachability
lens (B1-B4), both run against the build of 2026-09-17. New comments cite it as `REVIEW-1.md A1` etc.

## How each finding was handled

1. **Reproduce first**, with the reviewer's own probe script, on a copy of the repo whose `src/` was
   verified byte-identical (sha256) to the reviewed build. A finding that did not reproduce would
   have been rejected with that measurement. All ten reproduced.
2. **A failing test** in the repo's gates, run against that untouched copy and watched fail.
3. **Fix the game**, never weaken a test: the test then passes in the repo. Two fixes change a
   contract an older assertion encoded, and those assertions were replaced, not loosened, each with a
   comment saying why: the 4.25-stud grab reach in `Layout.spec` (B2), and `check_stealacryptid.luau`
   section 8 joining a locked profile inline, which cannot work once the join waits for the lock (A1).
   One older guards block, G5 (e), was re-aimed after the sweep showed B2 had blunted it.
4. **Re-run the reviewer's probe** against a copy of the fixed build (numbers under "after").
5. **Mutation sweep**: every guard added or changed is broken on purpose, one at a time; the bundle
   is proven to carry the edit; every gate runs; sources are restored byte-identical.

## Summary

| ID | Sev. | Finding | Verdict | Before (reviewer's probe, re-run) | After (same probe on the fixed build) |
|---|---|---|---|---|---|
| B1 | high | A ~0.5 s freeze while turning into a fence gap locks the trusted position behind the fence | CLOSED | trusted stuck at (62.88, 49.00), 20 grab holds refused, raid ended at dawn; pure probe e.g. c = 1.0: 7 of 25 freeze phases at 0.5 s | 0 stuck phases in every row of the pure probe; the e2e probe found no camp with a locking phase in 400 |
| A1 | med | Save lock read only at join; a lock that clears 1 s later costs the session | CLOSED | 603 s later canSave = false, 17 805 Essence collected, store still 250 000 | canSave = true, store 268 336 after leaving |
| A2 | med | The next camp (layout, prize, laser phases) is computable from one camp's seed | CLOSED | brute force recovered both camps' seeds; `PREDICTION MATCH: true` for the next tier-2 camp, phases exact (107.9 s CPU) | both camps' own seeds still recovered (inherent), `salt solutions: 0`: nothing predicts the next camp (142.2 s CPU) |
| A3 | low | A grant queued behind a write can land after the leave's release and re-lock for 120 s | CLOSED | 6 of 10 leave offsets left `jobId` set, `lockUntil` = now + 120 | 0 of 10 |
| A4 | low | A change made during an in-flight write waits for the 60 s autosave | CLOSED | reached the store 52.4 s later (control 5.0 s) | 8.5 s later (control 6.9 s) |
| A5 | low | Snare dropped on the walking poacher, cleared after: free catches | CLOSED | 5 visits, 5 caught, +180 each, net trap cost 0 | 4 visits in 1 300 s, 0 caught, 312 placements refused |
| A6 | low | Trusted position squeezes between corner-touching rocks | CLOSED | trusted in cell (5,7) through rocks (5,6)+(4,7); 200 of 200 squeezes passed per tier 1-3 | trusted stayed in (5,1) at (32.00, 32.00); 0 of 200 per tier |
| B2 | low | Grab prompt missing on 12-14 % of the grab cell; a rim that refuses | CLOSED | prompt at 87.5 / 87.4 / 87.4 / 87.8 % of reachable grab-cell points, worst cage 85.8 %; 335-345 refusing rim points per tier | 98.9 / 99.0 / 98.8 / 99.0 %, worst cage 98.3 %; the server grabs wherever the prompt shows |
| B3 | low | No glow on cage prompts; a stolen cryptid does not walk into its cage | CLOSED | 3 of 3 lair Release prompts and every Grab anchor unlit; stolen model 0.0 studs from its cage at the escape | every prompt host lit; the model is on its way (> 20 studs off) at the escape and in the cage 2.3 s later |
| B4 | low | A slow load teleports an already-walking player back to the marker | CLOSED | moved back 9.6 studs (0.6 s load) and 35.2 studs (failed attempt + retry) | never moved back |

No finding was rejected.

---

## B1 (high) - a freeze at a corner locked the trusted position for the rest of the raid - CLOSED

**Reproduced.** The reviewer's pure probe (`probe_corner.luau`: real Trace2D, Layout, Config), on the
untouched copy. Freeze phases that left the trusted position more than 1 stud from a walker standing 5 s
at its goal: walking at clearance 1.0: 0.4 s 3/26, 0.5 s 7/25, 0.7 s 15/23, 1.0 s 15/20; clearance 1.5:
0.5 s 3/26, 0.7 s 11/24, 1.0 s 15/21; clearance 2.0: 0.7 s 7/25; cell centres (4): 1.0 s 3/24; carrying
at 1.0: 0.7 s 10/33, 1.0 s 19/30. No freeze: 0.000 studs. The end-to-end probe (`probe_corner_e2e.luau`)
on the real server: trusted position (62.88, 49.00) while the root stood at the cage, 20 holds over 40 s
all refused with "Stand right in front of the cage to grab it", then "Dawn broke".

A wider measurement of my own (`stall_sweep.luau`, scratch, not a gate): 600 corner-cutting honest
routes (clearance 1.5, gate to prize, 150 camps per tier), one freeze at every phase of every route.
Phases that locked: 0.3 s 0 of 33 482; 0.5 s 0; 0.7 s 186; 1.0 s 8 817; 1.5 s 16 114.

**Cause.** `Trace2D.step` moved straight toward the claim and stopped where the segment left the map. A
catch-up chord across a fence corner stops ON the fence's 1-stud margin, and from there every straight
line toward a raider past the corner leaves the map at once, so the position never moves again.

**Fix** (`Trace2D.luau`, `Heist.luau`, `Main.server.luau`, `Config.luau`).
- **Slide.** After a clamped straight leg, what is left of the tick's allowance slides along the boundary,
  one axis at a time (farther to go first), toward the claim's coordinate on that axis, clamped at the
  map's edge again. No route is planned: a slide follows only the wall the position is pressed against.
  A noclip claim straight through a fence has no sideways component and still stops 1 stud in (the
  existing spec and check assertions for that are unchanged and green).
- **The catch runs along every leg.** `t.path` records the tick's legs; `Heist.caughtPath` times each leg
  by its share of the path's length; the raid loop calls it instead of the one-chord test.
- **Backstop: pull back.** `t.stuck` counts seconds with no progress toward a claim more than
  `Raid.StuckStuds` (4) away. After `Raid.StuckSeconds` (1.0) the server moves the character to
  `Trace2D.settle` (the trusted position moved 2 studs inside its floor cell: out of the wall margin and
  clear by the root's half-width) and toasts "You were pulled back to where the server last saw you -
  walk on from there". Honest catch-up always makes progress, so it never counts.

**Red, then green.**
- `tests/Trace2D.spec.luau`, freeze sweeps over the reviewer's geometry (clearance 1..4, walk and carry,
  freezes 0.2..1.0 s, every phase): on the old module 167 of 1 922 phases stuck turning into a gap and
  184 of 2 276 rounding a rock, and the spec crashed further on (`Trace2D.settle` did not exist); now 0
  and 0. Also asserted: every tick records its path (on the old module 4 000 of 4 000 random claims had
  none), no tick's path is longer than its budget and every point of it is on the map (4 000 random
  claims), a claim held through a fence counts as stuck and one tick of progress resets it, an honest
  walker 24 studs ahead after a freeze never counts, and where settle puts a position.
- `tests/Heist.spec.luau`: `caughtPath` catches a bent path through a snare its chord misses, and times
  legs by length (the old module has no `caughtPath`: crash).
- Guards G15, real server: a tier-1 camp whose route turns into a gap, hugging the fence at 1.5 studs,
  with a 0.5 s freeze at a phase that locked the OLD step (a copy of the old step lives in the check only
  to find that phase). Old build: trusted (54.88, 49.00) in one run, (62.88, 49.00) in another, grab
  refused, steals 0. Now: grabbed, carried
  out with a freeze at the same corner, steals + 1, and no pull-back toast (the slide alone did it).
- Guards G15b: a noclip claim left through a fence for 1.6 s. Old build: root still at (12.00, 60.00), no
  toast. Now: root at the settled point 1 stud off the fence face, (12.00, 47.00), toast, raid still on.
- `tests/walk.luau`: an honest walk through two raids is never pulled back.

**After.** Pure probe: 0 stuck phases in every row. The e2e probe's own predictor (now the fixed Trace2D)
finds no camp with a locking phase in 400 camps. `stall_sweep.luau` on the fixed modules: 0.3 s 0;
0.5 s 0; 0.7 s 0 (was 186); 1.0 s 329 (was 8 817), and the pull-back fires in all 329; 1.5 s 4 708 (was
16 114), pull-back in 4 713 (5 phases were stuck for over a second and would have come free later).

**Residual.** A freeze of a second or more round a rock can still leave the slide stuck (the raider ends
straight behind the rock); the pull-back ends it within 1 s, at the cost of walking round again. How often
Roblox replication freezes like this, and how a server-set CFrame on a client-owned character feels, are
Studio questions (Needs Studio 2, 3).

## A6 (low) - squeezing between corner-touching rocks - CLOSED

**Reproduced.** `probe_squeeze.luau`: walls at (5,6) and (4,7), a claim from (4,6) straight to (5,7) put
the trusted position at (36.00, 76.00), cell (5,7), raid running; the two rock Parts leave 0.57 studs.
`squeeze_stats.luau` (2 000 camps per tier): squeezes in 931 / 638 / 681 / 0 camps, and the trusted
position passed 200 of 200 tried in each of tiers 1-3.

**Cause.** `Layout.freeRects` grows every floor cell by 1 stud; two floor cells on a diagonal whose other
two cells are walls overlap in the 2 x 2-stud square round the shared corner, and `reach` treats that
overlap as continuous.

**Fix** (`Layout.freeRects`, `Trace2D`). `freeRects` also returns BARRIERS: at every grid vertex with the
checkerboard pattern (wall, floor / floor, wall) a segment across that square, perpendicular to the
diagonal, reaching 0.1 studs past it into the walls. Every leg, straight or slide, stops 0.001 studs short
of a barrier. The raid loop passes the barriers.

A first version computed a claim landing exactly ON the corner as `s = 1 + 2e-16`, missed the hit, and let
the trusted position stand on the barrier where `cellAt` put it in the far cell. Guards G16 caught it
(walls (3,1) and (2,2): trusted (16.00, 32.00), cell (3,2)). The hit test is inclusive with a 1e-9
tolerance now, and the spec replays that exact claim.

**Red, then green.** `Trace2D.spec`: four rock pairs in both diagonal orientations, nine chords each; on
the old modules 9 of 9 passed through in every case; now 0, plus the exact-corner walk, an honest detour
round the pair arriving with 0 clamps, and a walk 1 stud off a rock face never clamped. `Layout.spec`, over
2 000 camps per tier: squeezes in 947 / 680 / 682 / 0 camps (1 252 / 809 / 804 / 0 barriers), every
barrier sits between exactly two rocks, and no barrier point is standable by a 2 x 2 body. Guards G16,
real server: old build (60.00, 68.00) in cell (8,6); now the trusted position stays on its side.

**After.** `probe_squeeze`: the trusted position stays at (32.00, 32.00), cell (5,1). `squeeze_stats`,
patched only to pass the barriers as the game now does: 0 of 200 in every tier.

## B2 (low) - the grab prompt missed part of the grab cell, and showed where the server refused - CLOSED

**Reproduced.** `probe_reach.luau`, 25 camps per tier, a 2 x 2 body flood-filled over the built Parts: the
prompt showed at 87.5 / 87.4 / 87.4 / 87.8 % of reachable grab-cell points (worst cage 85.8 %), and 340 /
340 / 345 / 335 points off the cell showed a prompt that refused. The check's assertion tested 4 points
inset 1 stud on both axes; row 8 is open along x.

**Fix** (a contract change, recorded as a deviation in CLAUDE.md). The server's grab spot is no longer the
grab cell. It is the trusted position within `Raid.GrabReach` (5 studs) of the anchor on the flat
(`Layout.inGrabReach`), and the prompt's `MaxActivationDistance` is the same 5 (`GrabPromptDistance`), with
the anchor at root height. The prompt shows where a grab works and nowhere else. 5 covers the whole cage
front (hypot(4, 3)) and 97.9 % of the cell's standing points; what it leaves out is the two corners
farthest from the cage.

**Red, then green.** `Layout.spec`: the rule and the prompt agree at every point of a 0.25-stud grid round
the cage, the whole cage front is in reach, at least 97 % of the cell (old module: `GrabReach` nil, no
`inGrabReach`, crash). `check_stealacryptid.luau` section 5, asked of the built pocket on a 0.25-stud grid:
old build e.g. cage 4 front 77 of 96 points, 88.1 % of 928 cell points; now the whole front and at least
97 %. Guards G17: (a) against the bars 3.5 studs off centre: old build 4.61 of 4.25 studs, no prompt; now
shown, and the hold grabs. (b) 4.9 studs in front of the anchor, in row 7: old build prompt shown, hold
refused; now it grabs. (c) 5.3 studs: no prompt, and a fired one is refused with the reason (both builds).

**After.** `probe_reach`: 98.9 / 99.0 / 98.8 / 99.0 %, worst cage 98.3 %. Its "points off the cell that
show a prompt" (2 788-2 881 per tier) are no longer refusals: the server grabs there.

**What the change broke in a test, found by the sweep.** With the larger spot, guards G5 (e) pressed a
stud AFTER the server already had the raider in reach, so it no longer tested a press that arrives early,
and mutation M08 (a press on arrival never starts the hold) survived the first sweep. G5 (e) now presses
on entering the prompt's reach and asserts the server's trusted position was not there yet.

## B3 (low) - no glow on cage prompts; a stolen cryptid appeared in its cage - CLOSED

**Reproduced.** In the source, `Fx.attachGlow` was called for pedestals, pad, board, snares and the
poacher hat, never in `buildCage` or the pocket cage block; the Grab anchor is fully transparent and
tier-1 cryptids carry no aura; `grant` only called `buildCage`. In the built world (the new check run on
the old build): Cage_4, Cage_5 and Cage_6 Release prompts unlit, every Grab anchor unlit, the stolen
cryptid 0.0 studs from its cage at the moment of the escape.

**Fix.** A faint `FxGlow` PointLight on every unlocked lair cage base (the Release prompt's host) and, in
the tier's colour, on every pocket Grab anchor. `walkInto` (the purchase's walk, factored out) also runs
after a grant, from the arrival marker the raider lands on to the cage.

**Red, then green.** `check_stealacryptid.luau`: every Part carrying a prompt in the lair glows; every Grab
anchor glows; the stolen cryptid is more than 20 studs from its cage at the escape and within 1 stud
BuyTweenSeconds + 0.3 s later. A first version of that last assertion looked in the wrong cage when the
prize was the species the player had already bought (1 failing run); it now picks the cage the steal
filled.

**Residual.** Whether the glows read at night, and what up to 9 more PointLights per lair cost on a phone,
are Needs Studio 1 and 11.

## B4 (low) - a slow load yanked a walking player back to the marker - CLOSED

**Reproduced.** `probe_joinload.luau`: with a 0.6 s load the root was moved from plot-local x 45.6 back to
(36.00, 8.00) at 0.6 s (9.6 studs); with a failed first attempt and a retry, 35.2 studs at 2.2 s.

**Cause.** `onPlayerAdded` connects CharacterAdded before the load, so a character that spawns during the
load is placed; after the load it then placed `plr.Character` a second time.

**Fix.** That second placement exists for a character that spawned before the handler connected (Studio
play-solo). It now runs BEFORE the load instead of after it.

**Red, then green.** Guards G23, both reviewer cases: old build "at 0.6 s moved from x 45.6 to (36.00,
8.00)" and "at 1.6 s moved from x 61.6"; now never moved. And a control: a character that spawned before
PlayerAdded still lands on its marker (green on both builds).

**After.** `probe_joinload`: "never moved back" in both cases.

## A1 (medium) - the save lock was read once, at join - CLOSED

**Reproduced.** `probe_save.luau` D2: a 250 000-Essence record locked by `old-server-job` until now + 120,
the lock cleared 1 s after the join. 603 s later canSave was false, 17 805 Essence had been collected in
the session, and the store still held 250 000 after the player left.

**Fix** (`loadProfile`, `recheckLock`, `Config.Save`). DESIGN.md section 8 chose "locked at load means
unsaved for the session"; this is now a recorded deviation.
- **Wait at join.** A locked record is re-read every `LockRetrySeconds` (5) for up to `LockWaitSeconds`
  (15) before the session plays unsaved, and the player is told once: "Your save is still open on another
  server - waiting for it to close". The old server's leave-write normally lands within seconds, so a
  quick rejoin loads the real, released save.
- **Re-check after the wait.** A session that still started unsaved re-reads the record every
  `LockRecheckSeconds` (15). If the lock is gone AND the saved data is exactly what this session loaded
  (a crashed server, a lapsed lock), it takes the lock in the same transform and saves from then on:
  "Your save is free again - this session is saving now". If the data changed (the other server wrote
  after this session read it), writing would erase that write, so the session stays unsaved and the banner
  says "Not saving: your save changed on another server. Rejoin to load it".
- A take-over write that lands after the player left hands the lock straight back.

**Red, then green.** Guards G20. (a) The reviewer's case: old build canSave false, banner "Rejoin in 2
minutes", store 250 000 after 120 s of collecting (4 140 Essence); now canSave true, no banner, every
collected Essence in the store, lock released. (b) A lock held past the wait, then lapsing with the save
untouched: the old build stays unsaved; now the session takes the lock, the banner goes, the player is
told, the progress is stored. (c) The other server wrote 71 234 and released: never written over, the
banner says to rejoin (green on both builds: the safety half). (d) Leaving while the take-over write is in
flight leaves no lock and writes no data. `check_stealacryptid.luau` section 8 now joins the locked profile
on its own thread, since the join yields as in Roblox: no lair state while waiting, the waiting toast, then
the original assertions (unsaved, banner, 777 Essence, nothing written).

**After.** `probe_save` D2, with its first state read moved past the 15 s wait: canSave true, store 268 336
after leaving.

**Residual.** 15 s is a guess about real DataStore latency (Needs Studio 15). A player whose old server
notices the disconnect only after the wait AND writes a final save plays unsaved and is told to rejoin. A
LOAD_FAILED session (the store could not be read at all) still never retries in the background.

## A2 (medium) - the next camp was predictable - CLOSED

**Reproduced.** `probe_salt.luau`, from sign text, part names and sizes only: both observed tier-1 camps'
seeds recovered exactly, the session salt and raid serial solved, the next tier-2 camp predicted before its
360 permit was paid, layout and laser phases identical to the server's (`PREDICTION MATCH: true`), in
107.9 s of interpreted Luau.

**Cause.** `campSeed = (WorldSeed x 31 + salt x 7 + raidSerial x 2654435761 + tier x 104729) mod p`, so one
recovered seed gives every later one.

**Fix.** Every camp's seed is its own draw from a server-only `Random` stream (`campRandom`, created once,
unseeded, at server start). `Layout.campSeed` remains only as the specs' enumerator of reproducible camp
sets, which the spec numbers in CLAUDE.md are measured over.

**Red, then green.** Guards G22: twelve tier-1 camps for one player, another player's raids interleaved.
Old build: 11 of 11 seeds were the previous seed plus one or two per-raid steps, and 6 evenly spaced
triples. Now 0 and 0, and no seed repeats.

**After.** `probe_salt`: both camps' own seeds are still recovered (a camp's layout determines its seed,
which tells a player nothing the camp does not already show), `salt solutions: 0`: nothing predicts the
next camp.

**Residual.** `Random` is not a cryptographic generator. Recovering its state from 31-bit seeds (each
recovered by brute force, with other players' raids drawing in between) was not attempted.

## A3 (low) - a queued grant re-locked the record after the leave's release - CLOSED

**Reproduced.** `probe_race.luau`: the autosave's write yields 2 s, the carrier escapes during it and
leaves 0.005-0.095 s later; 6 of 10 offsets ended with `jobId = robloxemu-headless` and `lockUntil` = now +
120 (commit order LOCK, release, LOCK).

**Fix.** `PlayerRemoving` and `BindToClose` set `S.closing` first. Every write's transform reads it at
commit time and releases instead of locking, so whichever queued write lands last, the record is left
unlocked.

**Red, then green.** Guards G18, ten offsets: old build 6 relocked (0.015, 0.035, 0.045, 0.075, 0.085,
0.095 s in that run: the camps differ from the probe's); now 0, and 10 of 10 steals stored.

**After.** `probe_race`: 10 of 10 end with `jobId = nil`, `steals = 1`.

## A4 (low) - a change during an in-flight write waited for the autosave - CLOSED

**Reproduced.** `probe_save.luau` D1: an Expand made 0.55 s into a 2 s flush reached the store 52.4 s later;
with no write in flight, 5.0 s.

**Fix.** `flush` clears `pending` when it copies the profile, BEFORE the write yields; a change made during
the yield marks it again. A failed write marks it again too: the old code never cleared it on a failure, so
moving the clear earlier needed that line.

**Red, then green.** Guards G19: old build 48.5 s, now 8.5 s (bound: flush tick + write + 1 = 10 s). G19
also asserts that a change whose write FAILED is retried at the next tick (14.4 s, bound 15). That half is
green on the old build too; it guards the moved clear (sweep M46).

**After.** `probe_save` D1: 8.5 s (control 6.9 s).

## A5 (low) - free poacher catches by snaring the cell it walks - CLOSED

**Reproduced.** `probe_poacher.luau`, 1 300 s: 5 visits, 5 caught, 0 thefts, 5 snares placed and 5 cleared;
"+180 Essence bounty" and "Cleared - 100 Essence refunded" five times each.

**Fix.** `TrapAction` refuses to PLACE a trap while a poacher is in the yard: "A poacher is in your yard -
set traps before it comes, not under its feet". Placing during the 10 s warning still works, and clearing
always works. The 100 % refund stays: moving traps set before a visit is free by design; what was farmed
was placement under a poacher already walking.

**Red, then green.** Guards G21: a snare placed during the warning works (both builds). Tries on the
poacher's cells while it walks: the old build placed one and caught the poacher on the first try; now 0
placed, the refusal is toasted, no bounty.

**After.** `probe_poacher`: 4 visits, 0 caught, 4 thefts, 312 placements refused.

---

## B1 again: the per-leg catch needed its own test

The first sweep left mutation M34 (the raid loop judges each tick's chord again) alive: no gate could
tell the per-leg catch from the chord. Before keeping or deleting it, it was measured
(`legs_vs_chord.luau`, scratch): 1 440 000 random ticks in 600 camps, claims within 4 or 16 studs,
tick lengths up to the 0.5 s hitch cap. 125 764 ticks had a bent path; the two judgements disagreed on
694 of them. The legs caught 685 ticks the chord missed; the chord caught 9 the legs did not (it cuts
across a net's corner the path goes round). The first case found: the path (22.50, 48.36) -> (22.77,
49.00) -> (24.06, 49.00) slides along the fence margin into the gap of net (4,4); the chord only
touches that net at its last point. Guards G24 plays that tick on the real server: with the net OFF
no catch (control), with it burning "Caught by a laser net" on that tick. With M34 applied: no catch,
raid still running (guards 182/2).

## Mutation sweep

Driver `scratchpad/sacfix-r2/sweep.py` (not in the repo). One exact-string edit set per mutation,
applied alone to `src/`, sha256 verified changed; the bundle rebuilt and PROVEN to carry the edit (its
text differs from the baseline bundle `6c52f37e5131...` and contains every inserted string); all 13
gates run (9 specs, check, guards, HUD, walk); the source restored and sha256 verified identical. The
`src/` manifest (14 files) and the bundle were byte-identical before and after the whole sweep.

**56 of 56 mutations KILLED, 6 of 6 controls SURVIVED, 62 of 62 edits reached the bundle.**

M01-M27 are the first pass's mutations re-run on this tree (M05, "grab prompt reach back to 10", is
superseded by M40-M43). M28-M57 cover every guard this pass added or changed. C1-C3 are the first
pass's controls; C4-C6 are new: an unasserted property of an asserted object (the cage glow's
brightness) and the wording of two toasts outside the words the tests look for.

A first sweep of the same list, on the tree before three test changes, found three survivors. Each was
closed by fixing a TEST, and the whole sweep was then run again from the start:
- **M08** (a press made a tick before the server sees the raider arrive never starts the hold). Guards
  G5 (e) pressed on entering the grab CELL; once B2 made the grab spot a 5-stud disc, the server
  already had the raider in reach a stud earlier, so the press was no longer early. G5 (e) now presses
  on entering the prompt's reach and asserts the server's trusted position was not yet there.
- **M34** (the raid loop judges the chord): G24, above.
- **M37** (barrier hit test without its tolerance): `Trace2D.spec` tried four squeezed corners and
  none hit the rounding case. It now walks all 192 exact-corner cases; without the tolerance 35 end on
  or past the corner.

"check 331/1" means 331 passed, 1 failed.

| # | mutation | result | bundle | red gates |
|---|---|---|---|---|
| M01 | isBuildCell drops its range check | KILLED | ca2b22c284d9 | Layout 198/4, guards 171/13 |
| M02 | reconcile refunds every removed string | KILLED | 39d182541828 | Layout 199/3, guards 183/1 |
| M03 | escape from any row-0 position again | KILLED | b3e016da9c5e | Layout 200/2, guards 180/2 |
| M04 | the 0.5 s trusted bank restored | KILLED | ca1707602c60 | Trace2D 46/6, guards 183/1 |
| M06 | grab fired away from the grab spot not refused | KILLED | 0cea68d575d8 | check 331/1, guards 182/2 |
| M07 | stepping away mid-hold does not cancel | KILLED | 17dbd787c36b | guards 183/1 |
| M08 | press-on-arrival never starts the hold | KILLED | 48f1fc3174a6 | guards 183/1 |
| M09 | Collect Pad pays mid-raid | KILLED | 02f31219bac8 | guards 182/2 |
| M10 | abort is silent again | KILLED | c94a1890ddae | guards 182/2 |
| M11 | restart cooldown 0 | KILLED | 7ef14880a1bb | guards 182/2 |
| M12 | BuildMode(true) while on rebuilds | KILLED | f89f55a4b51c | guards 183/1 |
| M13 | one load attempt | KILLED | dcc7f8a2fa32 | guards 182/2 |
| M14 | failed load shows the generic banner | KILLED | e06f33f77da3 | guards 183/1 |
| M15 | no lock release after leaving mid-load | KILLED | 756bd0fcb45c | guards 183/1 |
| M16 | home only AFTER the grant write | KILLED | 961ca4ed875b | guards 183/1 |
| M17 | no busy guard during the grant write | KILLED | 18ffcc0c85ee | guards 182/2 |
| M18 | rollback keeps the Journal entry | KILLED | 65e47bf01d0a | check 331/1, guards 183/1 |
| M19 | writes not serialised | KILLED | 1e1dce94d872 | guards 181/3 |
| M20 | lost lock does not stop saving | KILLED | 3696e3cfda03 | guards 182/2 |
| M21 | emitter plate never parented | KILLED | 5b015f88ffad | guards 182/2 |
| M22 | snare takes mouse rays | KILLED | 9a370d54d51b | guards 183/1 |
| M23 | no brush in empty cage-row cells | KILLED | 327bb22fb214 | guards 178/6 |
| M24 | toast does not wrap | KILLED | bbc7e7374c5d | hud FAIL (1 PASS lines, rc 1) |
| M25 | the 112-char raid toast is back | KILLED | ff18158aa3ef | check 331/1, guards 183/1 |
| M26 | failed grant keeps the permit | KILLED | 9848b3882c32 | check 331/1, guards 178/1 |
| M27 | CharacterAdded does not wait for the parent | KILLED | bd95248e92ac | check 321/11, guards 180/4, walk 44/2 |
| M28 | B1 no slide along walls | KILLED | 53316ec679fa | Trace2D 50/2, guards 179/5 |
| M29 | B1 no pull-back in the raid loop | KILLED | a4557e0944fc | guards 182/2 |
| M30 | B1 stuck time never counted | KILLED | c66b3d510c78 | Trace2D 51/1, guards 182/2 |
| M31 | B1 stuck counted even while making progress | KILLED | 1a119978636f | Trace2D 51/1 |
| M32 | B1 settle leaves the wall margin in | KILLED | 83bf03cc4394 | Trace2D 51/1, guards 183/1 |
| M33 | B1 caughtPath judges only the chord | KILLED | ab76b7401fcd | Heist 77/2, guards 182/2 |
| M34 | B1 raid loop judges the chord, not the legs | KILLED | 57d5f52456d7 | guards 182/2 |
| M35 | B1 slide legs not recorded in the path | KILLED | eec8cee2e338 | Trace2D 51/1, guards 182/2 |
| M36 | A6 no barriers | KILLED | f89ccf8ca669 | Trace2D 43/9, guards 183/1 |
| M37 | A6 barrier hit without tolerance | KILLED | 3b05b75f8b18 | Trace2D 51/1 |
| M38 | A6 raid loop does not pass the barriers | KILLED | ee96202a873a | guards 183/1 |
| M39 | A6 a leg stops ON the barrier | KILLED | 5a40eda8d914 | Trace2D 47/5 |
| M40 | B2 reach back to 4.25 (server and prompt) | KILLED | f95e3cd6d349 | Layout 200/2, check 326/6, guards 182/2 |
| M41 | B2 server grabs on the grab cell again | KILLED | 5a624c04f1f4 | guards 183/1 |
| M42 | B2 server reach 10, prompt 5 | KILLED | 3ee9b192ae0a | Layout 199/3, guards 179/5 |
| M43 | B2 prompt reach 10, server 5 | KILLED | 482d25380fb0 | Layout 200/2, guards 182/2 |
| M44 | A3 a closing session's late write locks again | KILLED | 44b6067aac51 | guards 183/1 |
| M45 | A4 pending cleared after the write again | KILLED | 3c5ce65764b6 | guards 183/1 |
| M46 | A4 a failed write is not retried at the next tick | KILLED | 3b549f9484cb | guards 183/1 |
| M47 | A1 no wait for a lock at join | KILLED | 6ecf15afa7e8 | check 330/2, guards 182/2 |
| M48 | A1 no re-check of a lock after the wait | KILLED | 55a7c4c9eedf | guards 179/5 |
| M49 | A1 re-check takes a lock over changed data | KILLED | 54874b3a82dc | guards 181/3 |
| M50 | A1 a take-over after leaving keeps the lock | KILLED | 1289c92c8268 | guards 183/1 |
| M51 | A5 traps allowed while a poacher is in the yard | KILLED | 129f37ef1c7e | guards 180/4 |
| M52 | A2 camp seed back to salt + serial step | KILLED | c135f69fdef2 | guards 182/2 |
| M53 | B4 the post-load re-placement is back | KILLED | f2d633817307 | guards 182/2 |
| M54 | B4 an early character is never placed | KILLED | 1955b39e8eb0 | guards 183/1 |
| M55 | B3 lair cages do not glow | KILLED | 00cfdea9ad2b | check 331/1 |
| M56 | B3 grab anchors do not glow | KILLED | 36d461c3b2ee | check 329/3 |
| M57 | B3 a stolen cryptid appears in its cage | KILLED | 88877551f77f | check 331/1 |
| C1 | CONTROL road pine crown 9x14x9 -> 10x15x10 | SURVIVED, correctly | d4bb9291f6b1 | - |
| C2 | CONTROL hunt panel background 0.08 -> 0.12 | SURVIVED, correctly | 4e86f2fd1c70 | - |
| C3 | CONTROL emitter plate transparency 0.35 -> 0.45 | SURVIVED, correctly | 370bd0a7d95b | - |
| C4 | CONTROL cage glow brightness 0.8 -> 0.9 | SURVIVED, correctly | 3a126a8e64ae | - |
| C5 | CONTROL pull-back toast wording after 'pulled back' | SURVIVED, correctly | 436e478d947d | - |
| C6 | CONTROL lock-wait toast wording | SURVIVED, correctly | 0648461cb4a3 | - |

## Final gates (the tree as left, bundle rebuilt first)

| Gate | Result |
|---|---|
| `tests/Rng.spec.luau` | 32 passed, 0 failed |
| `tests/Responsive.spec.luau` | 70 passed, 0 failed |
| `tests/Economy.spec.luau` | 193 passed, 0 failed |
| `tests/Offers.spec.luau` | 36 passed, 0 failed |
| `tests/Layout.spec.luau` | 202 passed, 0 failed (was 192) |
| `tests/Heist.spec.luau` | 79 passed, 0 failed (was 73) |
| `tests/Trace2D.spec.luau` | 52 passed, 0 failed (was 28) |
| `tests/Poacher.spec.luau` | 51 passed, 0 failed |
| `tests/CryptidModel.spec.luau` | 552 passed, 0 failed |
| specs total | 1 267 passed, 0 failed (was 1 227) |
| `luau-compile --binary` | 27 of 27 files clean (src, tests, the three check files) |
| `luau-analyze` src + specs, Roblox global/type noise filtered | 0 lines |
| `robloxemu/check_stealacryptid.luau` | 332 passed, 0 failed (was 320) |
| `robloxemu/check_stealacryptid_guards.luau` | 184 passed, 0 failed (was 113) |
| `robloxemu/check_stealacryptid_hud.luau` | PASS (box fit, 10 viewports x 3 modes) and PASS (text legibility) |
| `tests/walk.luau` | 46 passed, 0 failed (was 45) |
| Robux / MarketplaceService / purchase prompt references in `src/` | 0 |

**Stability** (each headless run draws a new session salt): check 0 failing runs of 100, guards 0 of
60, walk 0 of 60, HUD 0 of 10.

**The final tests against the reviewed build** (a copy whose `src/` was re-verified byte-identical to
it after the work): guards 157 passed, 27 failed (every new block G15-G24 red except the halves that
are green by design: G20 (c), G21's warning placement, G23's early-character control, G19's retry);
check 13 failed, then crashed at the lock wait (`Save.LockWaitSeconds` does not exist there);
Trace2D.spec 6 failed, then crashed (no `Trace2D.settle`); Layout.spec 1 failed, then crashed (no
`Layout.inGrabReach`); Heist.spec crashed at its first new assertion (no `Heist.caughtPath`); walk 46
passed (its one new assertion, "never pulled back", holds trivially on a build with no pull-back).

**The final walk** (camps vary per run): first purchase 2.1 s after landing; tier-1 raid 13.6 s against
a 13.83 s plan, stealing a Chupacabra; one minute after joining 4 Essence/s;
poacher warned at 300.3 s, appearing 10.0 s later, escaping with 286 Essence past one net; tier-2 raid
21.4 s against 21.56 s (income 4/s -> 22/s); rejoin keeps everything and lands on the marker; 162 studs
walked, 3 prompt presses all in reach, 0 blocked steps, 0 pull-backs.

## Still open

- **Nobody has opened any of it in Roblox Studio or played it.** Everything below "Needs Studio" in
  CLAUDE.md stands; this pass added to it: how often replication freezes long enough to slide or pull
  back, what a server-set CFrame on a client-owned character looks like, the 5-stud grab sphere with
  avatars whose root is not 3 studs up and between two adjacent cages, whether the cage glows read,
  PointLight cost on a phone, whether an old server's leave-write lands inside the 15 s join wait.
- **Streaming** (both reviewers, unverified): `default.project.json` does not set
  `Workspace.StreamingEnabled`, and pockets sit at x >= 4000. With streaming on, a server teleport into
  a pocket could land before its floor streams in. Added to Needs Studio (18).
- **Freezes of a second or more** can still stop the slide (a raider ending straight behind a rock):
  329 of 33 482 phases at 1.0 s, 4 708 at 1.5 s, every one ended by the pull-back, which costs the
  player the walk round again.
- **After a freeze the trusted position trails the player** (a 0.5 s freeze: up to 8 studs, caught up
  over 1.4 s at 21.6 studs/s), so it can cross a net up to that freeze's length after the player did.
  This predates this pass and is Needs Studio 2.
- **`Random` is not a cryptographic generator**; recovering the camp stream's state was not attempted.
  A camp's own seed remains recoverable from its layout, which reveals nothing the camp does not show.
- **A LOAD_FAILED session never retries in the background**, and a locked session whose old server
  writes a final save after the 15 s wait stays unsaved until the player rejoins (the banner says so).
- **No reviewer has seen this pass's changes.** Most in need of one: the slide, barriers and pull-back
  in `Trace2D`, the lock wait and take-over in `loadProfile` / `recheckLock`, and `S.closing`.
- The reviewers' "clean areas" were not re-audited beyond the gates and probes listed here.

## What changed

In `steal-a-cryptid/` (the only game directory written):
- `src/shared/Trace2D.luau`: the slide, `t.path`, `t.stuck`, `Trace2D.settle`, barriers in `reach`.
- `src/shared/Layout.luau`: barriers from `freeRects`, `Layout.inGrabReach`, comments on `campSeed` and
  `grabAnchor`.
- `src/shared/Heist.luau`: `Heist.caughtPath`.
- `src/shared/Config.luau`: `Raid.StuckStuds`, `Raid.StuckSeconds`, `Raid.GrabReach` 5,
  `Raid.GrabPromptDistance` 5, `Save.LockWaitSeconds`, `LockRetrySeconds`, `LockRecheckSeconds`.
- `src/server/Main.server.luau`: per-leg catch, barriers, pull-back; grab spot; lock wait, `recheckLock`,
  `S.closing`, `pending` cleared before the write; trap placement refused under a poacher; camp seeds
  from `campRandom`; early character placed before the load; cage and anchor glows; `walkInto` after a
  grant.
- `tests/Trace2D.spec.luau`, `tests/Heist.spec.luau`, `tests/Layout.spec.luau`, `tests/walk.luau`: the
  assertions described above (one old Layout.spec contract, the 4.25-stud reach, replaced by the B2
  contract).
- `CLAUDE.md`, `README.md`: gates, traps 14-20, deviations, numbers, the sweep, Needs Studio, gaps.
- `REVIEW-1.md`: this file.

In `robloxemu/`: `check_stealacryptid.luau` and `check_stealacryptid_guards.luau` (G5 (e) changed; G15-G24
added; section 8 joins on a thread), and `build/steal-a-cryptid.luau` rebuilt. Against a sha256 manifest
taken before any work, `robloxemu/emu/`, `robloxemu/wrap.py`, `check_stealacryptid_hud.luau`, DESIGN.md and
every file that was in `docs/` are byte-identical. Nothing else was written by this session: during it,
other sessions changed files in `anomaly-observatory/marketing/`, `tools/film_anomaly.py` and added
`docs/marketing/youtube-schedule.md` (09:12), none of them touched here. Nothing was committed, pushed or
published. The reviewer probes, the measurements (`stall_sweep.luau`, `legs_vs_chord.luau`), the edit
scripts and the sweep driver live in the session scratchpad (`sacfix-r2/`), not in the repo.
