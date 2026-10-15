# REVIEW-1 — Scrapline Tycoon

Two adversarial reviewers read v1 on 2026-10-07: one hunted for ways a player can **reach** a broken state or
fail to reach the core loop (findings B1-B6), the other for **exploits** of the server, the save and the board
(findings A1-A4). Their raw reports went to the orchestrating session and were not saved in this repo. This file
was written on the build stage's second run (2026-10-07, evening) from what the fix round left on disk: the
fixes in the code, the failing-first checks named below, the mutation driver (`scratchpad/slt_r1/mutate_r1.py`,
whose mutant notes name each finding) and the documentation the fix round updated (`CLAUDE.md`, `DESIGN.md`
§20, `EYECANDY.md` §3, §4, §8). The fix round stopped before it wrote this file and before its mutation sweep
finished (it reached M37); the build stage's second run finished the sweep (M38-M45, C3, C4) on the same pristine
copy.

**10 findings: 9 fixed in the game behind a failing check, 1 accepted as a design property (A4) and documented.**

**Round 2** (two more reviewers, 2026-10-07/08, at the end of this file): 12 findings (X1-X4, R1-R8), all reproduced,
none rejected: 9 fixed in the game behind a failing check, 2 flaky checks fixed in the checks (the game was right), 1
a document; 27 mutants (26 KILLED, 1 equivalent alone), 4 controls and 2 no-edit runs survive; **28 of 28 gates
green, 4 799 assertions**. The final gates, the standard's status and what is still open are in round 2.

# Round 1

## Findings

| # | finding | what a player met | fix | check that failed first |
|---|---|---|---|---|
| A1 | The plot was freed only after the leave's writes returned | Roblox frees the player slot at once and runs PlayerRemoving on its own thread: on a full server a joiner arriving while the leave was still saving was kicked ("all 6 factories are taken"), and a late Buy from the leaver could act on the plot | `onPlayerRemoving` frees the plot (and resets it) before any yield; every remote handler and loop skips a `leaving` session | `check_scraplinetycoon_save` K (latencies 0.3, 1 and 3 s) |
| A2 | `BoardView` spam multiplied the server's web calls | 60 s of public-view spam with name lookups failing cost 4 806 lookups; 60 s of Friends toggling cost 48 friend-list fetches + 144 pages, enough to keep a 429 going for everyone | a failed name lookup is not retried for 60 s and only one lookup per id is in flight (`Config.Board.NameRetrySeconds`); each viewer's friend list is cached 5 min, a failed fetch 1 min (`FriendListSeconds`, `FriendListRetrySeconds`). Now: 10 lookups and 1 fetch | `check_scraplinetycoon_board` §6, §7 |
| A3 | A same-server rejoin cancelled its own leave's write | the lock lets the same JobId through, so the rejoin's load took the owner token while the release write was in flight; that write was then refused and the progress since the last flush was lost | `leavingByUser`: the rejoin's load waits (bounded, `Config.Save.LeaveWaitSeconds`) for the leave's writes, with a toast (`Tutorial.LeaveWaiting`) | `check_scraplinetycoon_save` L (the slow-first-write order) |
| A4 | A bot that walks to every sputter, 24/7, tops the public board | — | **Accepted, not fixed.** The metric cannot be inflated, only accumulated at human speed: the model's bot reaches 1 / 14 / 21 / 27 bolts after 1 / 8 / 24 / 72 h against the normal player's 1 / 13 / 21 / 27 (`tests/LineModel.luau`, seeds 1-3). Macros that never walk to a sputter gain nothing. Documented in `DESIGN.md` §20; whether a per-period or best-run metric should replace it is the owner's call | — |
| B1 | Pressing E beside a broken machine opened the line panel instead of fixing | ProximityPrompt `Exclusivity` defaults to OnePerButton and Roblox shows only the nearest prompt per key; the station console sat 4.51 studs from where a player fixes, the machine 4.53-4.74, so E went to the console at 85 of 156 spots | Fix is on **F / ButtonY** with `Exclusivity = AlwaysShow`; a station's console prompt is disabled while one of its machines sputters or is jammed | new `check_scraplinetycoon_prompts` (applies Roblox's keyboard and gamepad rule, and the worst case for touch, to the prompts the real HUD creates) |
| B2 | ☕ Break never let go of the camera | the drift was an endlessly repeating tween that was never cancelled: after the break it kept writing `Camera.CFrame` for the rest of the session | the yard script's `frame()` moves the camera only while gazing; no tween | `check_scraplinetycoon_yard` "☕ Break lets go of the camera completely" |
| B3 | A player standing still at the HUD never met a hazard | the template's 20 s idle rest froze the crane for exactly how a tycoon is played (the walk: one drop per 31.6 min, the chip read "💤 Resting" most of the game); the walk had hidden it by holding the stick all game | `Config.Rest.IdleSeconds = 0` (the template's own switch); only ☕ Break rests. The walk now stands still between taps | `check_scraplinetycoon_hazards` 7c, the walk (a drop every 1.5-3.5 min, 0 rest frames) |
| B4 | The SCRAPLINE sign's text faced the wall | the SurfaceGui was on the Back face, pressed flat against the factory wall (gap 0.000 studs) | `NormalId.Front`, whose normal points into the yard on every plot (dot 1.000) | `check_scraplinetycoon` §1 (a SurfaceGui's face measured headless) |
| B5 | The crane dropped on a player standing on a machine | machine bodies are collidable and 6-9 studs tall; FloorMaterial Metal counted as grounded, and the ring was drawn on the floor below, hidden inside the machine | no aim at a root more than `Config.Hazards.StandAboveFloorMax` (5) studs above the highest low surface under it | `check_scraplinetycoon_hazards` 7b |
| B6 | The break chip implied the factory pauses | the chip did not say that the line keeps running and machines can still jam during a break | chip, store text and docs say so ("Your line keeps running, and machines can still jam.") | `check_scraplinetycoon_yard` (the break's own words) |

## Mutation sweep of the review's assertions

`scratchpad/slt_r1/mutate_r1.py`: an isolated copy (`slt_r1/mut/pristine`, byte-identical to the game's code at
the time of writing; only the docs differ), the pristine source restored before every mutant, sha256 before and
after, the mutation confirmed in the rebuilt bundle, all 24 gates per mutant, a gate that dies without a summary
counts as KILLED. M29-M37 ran in the fix round; M38-M45, C3 and C4 in the build stage's second run (same driver,
same pristine copy). **17 of 17 mutants KILLED; both controls SURVIVED.**

| mutant | finding | killed by |
|---|---|---|
| M29 the plot freed only after the leave's writes return | A1 | `_save` (10) |
| M30 a same-server rejoin does not wait for its own leave | A3 | `_save` (5), walk (1) |
| M31 the leaving session not registered | A3 | `_save` (5) |
| M32 a failed name lookup retried at once | A2 | `_board` (1), `_hazards` (1) |
| M33 the friend list fetched on every toggle | A2 | `_board` (3), `_hazards` (1) |
| M34 a failed friend list re-fetched on every toggle | A2 | `_board` (1) |
| M35 Fix back on the default E / ButtonX | B1 | `_hazards` (1), `_prompts` (7) |
| M36 Fix not AlwaysShow | B1 | `check_scraplinetycoon` (1), `_prompts` (2) |
| M37 the console of a station in trouble stays enabled | B1 | `check_scraplinetycoon` (1), `_prompts` (1) |
| M38 the original endless camera tween | B2 | `_yard` (7), `_hazards` (1) |
| M39 the drift keeps writing the camera after the break | B2 | `_yard` (2) |
| M40 the template's 20 s idle rest | B3 | `_hazards` (2), walk (3) |
| M41 the sign's text on the Back face | B4 | `check_scraplinetycoon` (6) |
| M42 hazards aim at a player standing on a machine | B5 | `_hazards` (2) |
| M43 a machine top counts as a low surface (StandAboveFloorMax 10) | B5 | `_hazards` (2) |
| M44 the break chip does not say machines can jam | B6 | `_yard` (1) |
| M45 a leaving player's Buy acts on the plot | A1 | `_save` (3) |
| CONTROL C3 the LeaveWaiting toast's wording | — | survived all 24 gates, as it must |
| CONTROL C4 the break drift 16 s each way instead of 14 | — | survived all 24 gates, as it must |

## Added on the build stage's second run (not a reviewer's finding)

**Workspace.StreamingEnabled was not pinned.** `Hud.client` binds the console and board prompts and the board's
SurfaceGui to parts of the player's own plot and caches them once found; with streaming a part arrives late, and a
part streamed out and back in is a new instance, so a cached prompt would sit on a destroyed part
(gnome-garden-defense REVIEW-1 R4 reproduced exactly that). Rojo writes no Workspace unless the project names one,
so a place started from a Studio template (streaming on) would keep it on. `tests/project_spec.py` was written
first and failed (7 passed, 2 failed); `default.project.json` now pins `Workspace.StreamingEnabled = false`
(9 passed, 0 failed; `rojo build` writes `<bool name="StreamingEnabled">false</bool>`). Mutants: P1 the property
true (1 failed), P2 no Workspace node (2 failed); control C5 the project's name (survived).

---

# Round 2 (2026-10-07/08): two more adversarial reviewers, 12 findings

An **exploit** reviewer (X1-X4) and a **reach** reviewer (R1-R8) read the game after round 1. Their reports reached
this run as text from the orchestrating session; their probes are in `scratchpad/sltx2-exploit-r2q7/robloxemu` and
`scratchpad/sltrev3_reach_m4q8`. Every finding was reproduced first (the reviewer's probe re-run on this code, or a
forced reproduction), then closed behind a check that failed first. **12 findings: 9 fixed in the game, 2 were flaky
checks (the game was right; fixed in the checks), 1 a document (R8). None rejected: all 12 reproduced.**

| # | sev | finding | reproduced (before) | fix | check that failed first | after |
|---|---|---|---|---|---|---|
| X1 | low | Leave, rejoin the same server, leave again: the first leave's save is cancelled | reviewer's `check_x2_hop` (every UpdateAsync 10 s): record Furnace **L1** (bought L2) and "a newer session owns this profile"; control L2 | `load()` returns right after its wait for an earlier leave if its own player left meanwhile (no token taken); only a **loaded** session registers in `leavingByUser` (an unloaded one replaced, then cleared, the earlier leave's entry) | `check_scraplinetycoon_save` M (3 failed): a second session comes and goes and a **third** joins while leave #1 still writes | the probe: Furnace L2, 3 writes on the key, no warning; M 0 failed |
| X2 | low | One tick at an infinite root position makes Fix work from anywhere | reviewer's `check_x2_trace`: x = +inf or z = −inf on Plot_2 → trusted (nan, nan), Fix from the pad "Saved it!", sputter cleared; NaN alone did nothing | the trace loop skips a claim whose X, Y or Z is not finite before `Trace.step`; the range check is fail-closed: `not (dist <= FixRange)` | new `check_scraplinetycoon_guard` 1 (6 failed): control, x +inf, z −inf, NaN, y +inf | trusted stays (0, −30) in all five; Fix from the pad refused ("Get closer to fix it") |
| X3 | low | A failed recycle write can be retried at the remote's rate | reviewer's `check_x2_fuzz` §2: 73 profile-store calls in 10 s of spam (0 without); `_guard` 2: 80 | after a failed write the next try waits `Config.Recycle.RetrySeconds` = 10 s, with a toast that counts it down ("The save is having trouble. Nothing changed: try again in 8 s.") | `Recycle.spec` (3 failed: the text and the config); `_guard` 2 (2 failed) | 1 store call in 10 s of spam (100 calls, 8 a second let through by the remote, 82 toasts); after the hold the recycle lands its bolt. `_save` C now expects the hold (a try 1 s after the failure is held, no store call, a toast) |
| X4 | low | `check_scraplinetycoon` failed 7 runs in 28 | forced: scanning while the client's crane ring is drawn fails "and still nothing red" (got 1); it also happened unforced in this run. A second red part: the telegraph's pillar turns ring-red at the lock (DESIGN 7), 1 run in 6 after the first exclusion. The gap: from the first sputter's START it held the 5.0-6.2 s it was live (12 runs: 159.9-211.5 s against a 212 bound) | **in the check**: `redParts()` skips only `Workspace.ScraplineLocalYard.HazardZone` and `.HazardPillar` (the local telegraph); the gap is measured from the FIX (153.7-205.7 s in the same 12 runs) | forced reproduction (old check 386/1, new 392/0) | 12 of 12 runs green |
| R1 | med | The Top Recyclers rows are unreadable on a phone | `probe_board`: face 7.00 × 3.70, a row 0.229 studs; new `_boardview` (pinhole camera, FOV 70, 800 × 360): **3.3 px** read from 5 studs at the default camera (12.5 studs behind the head), 6.6 px first person from the pad, 2.9 px default camera from the pad | the board is 10 × 10 (face 10 × 9.2) at (7, −21) on the DOCK side of the arrival (hides neither the chute nor the Shredder), 11.4 studs from it, prompt 13 studs; the rows take 82 % of the face: a row is 0.686 studs | `_boardview` 2 (2 failed); the bar is the HUD's own hint text on that phone, read live: 16 × UIScale 0.6 = **9.6 px** | **10.1 px** reading it, 15.4 px first person from the pad, 7.8 px default camera from the pad. `PlotGeom.spec` (new): the frame clears every footprint on the floor by 0.66 studs or more (the Rocket Bay twin's corner) |
| R2 | med | The public board drops the viewer's own row once 10 others are on it | `probe_board`: 11 rows sent, 10 drawn, own row drawn = false; friends: 13 sent, 10 drawn | 11 slots: the top 10 and, under them, the viewer's own row when it is not among them (`Config.Board.ShownRows`) | `_boardview` 1 (4 failed) | public: 11 drawn, the last "— Nova 🎨 1"; friends: "13. Nova 🎨 1"; every row inside the frame |
| R3 | med | The brag moment is in 30-45 min only for players who follow the ★ | `Pacing.spec`: cheapest 53.4, random 53.0 min; the reviewer's "any affordable button" 53.0; **through the real HUD** (the walk's new `green` mode on the original game): **50.7 min** | `Economy.worth`: the panel paints an affordable purchase GREEN only when it is the next station or pays for itself within `Star.GreenPayback` = 2 × the best payback on the list, and nothing green while the ★ saves for the next station; affordable-but-not-now is a muted blue-grey (the server sends `worth` per row) | `Economy.spec` (red: no `worth`), `Pacing.spec` `green`/`green60` (red), the walk's colour audit (151 of 1 256 buttons wrong, 23 green while saving) | a player who taps ANY gold or green button: **36.8 min** median (p10 35.0, p90 39.8; shopping every 60 s 36.3 / 38.0 / 40.1); the green walk through the HUD **34.2-34.6 min** (4 walks), 0 of 1 576-1 593 buttons wrong. CONTROL: tapping any affordable button whatever its colour still takes 53.0 |
| R4 | low | The step-2 hint names the Furnace as the ★ while the ★ points elsewhere | the walk's new audit: 527 frames (52.7 s) from 22.3 s ("Save for a Furnace ★" while the ★ was ⬆ Shredder) | step 2 says "Save for a Furnace ★…" only while the ★ IS the Furnace build; before that "Buy the ★ row in 🏭 Line: it is the best buy for your line right now" | the walk (1 failed) | 0 frames in every walk |
| R5 | low | One jammed machine stops all crane drops until fixed | `probe_rest`: 10 min standing still with jams: 1 drop, the hold on in 3 626 of 6 000 frames; `_hazards` 7: 0 drops in 60 s with a jam standing (a hazard due every 8-9 s) | hazards hold only while a machine SPUTTERS (15 s clock), never for a standing jam; the dead `trouble` field left the State; the pacing model follows | `_hazards` 7 (2 failed) | 7 drops in 60 s with the jam standing; none during the 15 s sputter; `probe_rest`: 3 drops in 10 min. The walk: one drop every 2.43-2.64 min (star), 2.45-2.90 (green) |
| R6 | low | Two gates fail at random (walk 2 in 91, check 6 in 42) | forced: the walker recycles while a sputter is live → old walk "13 of 14" FAIL; the check: X4 | **in the walk**: a sputter still live at the recycle is counted as wiped by it (new machines), at most 1 | forced reproduction (old 18/1, new 19/0) | see "Flakes" below |
| R7 | low | Players can walk off the world behind plots 1 and 4 | `check_scraplinetycoon` §1 (new, 4 failed): no wall on any edge; the closest plot corner 12.0 studs from the plate's edge | four invisible, collidable walls on the plate's edges, 60 tall, 4 thick (`World.EdgeWallHeight/Thickness`) | `check_scraplinetycoon` §1 | every edge closed; server parts 266 idle, 422 busy (budget 640) |
| R8 | low | Thumbnail shot 5 cannot be staged as written | by reading: `Yard.client` lights the world by the LOCAL player's own tier (EYECANDY §2), so six plots in different bands cannot be filmed | `EYECANDY.md` §9 shot 5 and `DESIGN.md` §20 restaged: six plots at different stages (lines, sign accents, paint) under the camera player's own night sky | (a document) | — |

**What the reviewers' clean areas raised, not as findings:** whether Roblox replicates a non-finite root CFrame at all
(X2's severity), and fling-griefing between players (collisions are on): both are now needs-Studio items
(`EYECANDY.md` §8, 29).

## Flakes found and closed in this round

The exploit reviewer measured `check_scraplinetycoon` failing 7 runs in 28, the reach reviewer the walk 2 in 91 and
the check 6 in 42; in every captured case the game was right. This round's own sweep found two more (a BASE run with
no mutation failed one assertion in `check_scraplinetycoon` and one in the walk) and the first sweep's controls failed
in `_yard`:
- `check_scraplinetycoon` "still nothing red": the client's ring and, at the lock, its pillar (above). 12 of 12 runs
  green since.
- `check_scraplinetycoon` "inside the 150-210 s gap": measured from the fix (above).
- the walk: a sputter wiped by the recycle (above). One more walk failure in the first sweep's BASE was not captured
  (that driver kept only summaries); the driver now keeps every FAIL line, and since then 30 star walks and 22 green
  walks have all passed.
- `check_scraplinetycoon_yard` "launchsite: its critter farRocket is out" failed 3 runs in 8 (baseline included): a
  critter that leaves the sky is respawned on the same frame but drawn only from the next (at weight 0, invisible),
  and the check looked at one frame. It now looks over 10 frames (10 of 10 green; mutant Y1 below proves it still
  catches a missing critter).
- `check_scraplinetycoon_hazards` (this round's own section 7 and `nextLocked`): a sputter starting inside a set-up
  wait holds the crane, as it must. The helper fixes it and waits again; section 7 counts only while the State says
  the sputter is live. 16 of 16 green.

**Measured after all of it: 12 full gate runs in parallel copies, 336 gate results, all green, no FAIL line**; then the
sweep's BASE and BASE2 (all 28 gates each), green.

## Mutation sweep of this round's assertions

`scratchpad/slt_r2/mutate_r2b.py`: a pristine copy of the repo after the fixes (`mut/pristine`: the game, robloxemu's
`emu/`, `wrap.py` and every `check_scraplinetycoon*.luau`), for each mutant a fresh copy with ONE mutant's edit(s)
(each old text exactly once), sha256 of every edited file before and after, **all 28 gates** (`slt_r2/gates2.sh`,
bundle rebuilt first) with every FAIL line kept, and proof the edit reached the rebuilt bundle (every new text in it,
every replaced text gone). Six workers in parallel, each in its own copy. The pristine copy's 65 files hashed the same
before and after (and matched the repo's hashes at the freeze). **27 mutants: 26 KILLED, M49 SURVIVED as equivalent
alone (its pair M50 is KILLED); the 4 controls and both BASE runs SURVIVED.** Every kill below is the assertion the
mutant aims at (the FAIL lines are in `mutate_r2b_log_part1.txt` / `_part2.txt`).

| mutant | finding | killed by |
|---|---|---|
| BASE, BASE2 (no edit) | — | survived all 28 gates, as they must |
| M46 a session that left while its load waited still takes the owner token | X1 | `_save` M (3) |
| M47 a leave that never loaded registers (and clears) the leaving entry | X1 | `_save` M (3) |
| M48 a non-finite root claim reaches `Trace.step` | X2 | `_guard` 1 (2: the trusted position not finite) |
| M49 the range check fail-open again, the finite guard kept | X2 | **SURVIVED: equivalent alone** (the guard keeps the trusted position finite, so the fail-closed test is defence in depth) |
| M50 M48 + M49 (the original code) | X2 | `_guard` 1 (6: Fix from the pad saves it) |
| M51 a failed recycle write sets no hold | X3 | `_guard` 2 (2: 80 store calls), `_save` C (3) |
| M52 the hold is never checked | X3 | `_guard` 2 (2), `_save` C (3) |
| M53 hazards held while any machine is jammed (the original code) | R5 | `_hazards` 7 (2: 0 drops in 60 s) |
| M54 hazards not held during a live sputter | R5 | `_hazards` 7 (3: 2 launched during the sputter) |
| M55 the edge walls 30 tall | R7 | `check_scraplinetycoon` §1 (4) |
| M56 the +X edge has no wall | R7 | `check_scraplinetycoon` §1 (1: the +X edge) |
| M57 the edge walls do not collide | R7 | `check_scraplinetycoon` §1 (4) |
| M58 a red SERVER part named HazardZone (the dock strip) | X4 | `check_scraplinetycoon` (2: "no server part is red", "still nothing red": 6 parts) |
| M59 sputters 120-130 s apart | X4 | `check_scraplinetycoon` (1: 120.7 s after the fix) |
| M60 step 2 always says "Save for a Furnace" (the original code) | R4 | walk (1: 521 frames), walk green (1: 515) |
| M61 green = every purchase (no payback rule) | R3 | `Economy.spec` (6), `Pacing.spec` (2: green p90 53.3, green60 57.1) |
| M62 green while the ★ saves for the next station | R3 | `Economy.spec` (1), `Pacing.spec` (1), walk (1), walk green (1) |
| M63 the HUD paints every affordable button green (the original code) | R3 | walk (2: 169 wrong), walk green (3: the first Rocket at 51.1 min, 135 wrong) |
| M64 the server sends worth = true for everything | R3 | walk (2: 153 wrong), walk green (3: 51.2 min) |
| M65 green within 10 × the best payback | R3 | `Pacing.spec` (2: green p90 52.1, green60 54.1) |
| M66 the board back to 7 × 4.5 | R1 | `_boardview` 2 (2: 4.0 and 6.1 px) |
| M67 the rows back to 62 % of the face | R1 | `_boardview` 2 (2: 7.6 and 11.7 px) |
| M68 the board on the chute side | R1 | `_boardview` 2 (1) |
| M69 the board 11.4 studs out but over the dock | R1 | `PlotGeom.spec` (1: 0.00 studs from the dock) |
| M70 the board's prompt back to 10 studs | R1 | `PlotGeom.spec` (1), `check_scraplinetycoon` (1: 11.5 > 10 from the pad) |
| M71 the own row not drawn below the top 10 (the original code) | R2 | `_boardview` 1 (4) |
| M72 10 slots for 11 rows | R2 | `_boardview` 1 (1: a row outside the frame) |
| CONTROL C6 the step-2 hint's wording | — | survived all 28 gates |
| CONTROL C7 the muted button colour 2 points lighter | — | survived all 28 gates |
| CONTROL C8 the edge walls 6 studs thick | — | survived all 28 gates |
| CONTROL C9 the recycle hold 12 s | — | survived all 28 gates |
| Y1 (one gate only) the far rocket never flies | flake fix | `_yard` (1: "its critter farRocket is out") |

A first sweep (`mutate_r2.py`) was run before two of the flakes above were found: its BASE failed one assertion in
`check_scraplinetycoon` and one in the walk, and controls C7 and C8 were "killed" by `_yard` and `check_scraplinetycoon`.
Those were the flakes, not the controls (C7 and C8 survive above). It was discarded and re-run with FAIL lines kept.
The second driver crashed on a "★" printed to a cp1252 console after M60 (results lost, pristine checked intact by
hash); M60-C9 were re-run with UTF-8 output (`_part2`).

## Final gates (2026-10-08, bundle rebuilt first, on the repo)

**28 of 28 green: 4 799 assertions passed, 0 failed, and the HUD check PASS** (30 viewports, overlap = true).

| gate | result | gate | result |
|---|---|---|---|
| project_spec | 9 / 0 | check_scraplinetycoon | 392 / 0 |
| Line.spec | 54 / 0 | _save | 104 / 0 |
| Economy.spec | 140 / 0 | _board | 41 / 0 |
| Jams.spec | 47 / 0 | **_boardview (new)** | 26 / 0 |
| Recycle.spec | 54 / 0 | _yard | 106 / 0 |
| Save.spec | 60 / 0 | _hazards | 101 / 0 |
| Board.spec | 46 / 0 | **_guard (new)** | 34 / 0 |
| PlotGeom.spec | 116 / 0 | _compile | 220 / 0 (20 sources, 175 Enum uses) |
| HudLayout.spec | 2 554 / 0 | _prompts | 28 / 0 |
| EnvConfig.spec | 164 / 0 | _hud | PASS |
| Pacing.spec | 33 / 0 | walk | 23 / 0 |
| EnvBands.spec | 124 / 0 | **walk green (new)** | 23 / 0 |
| Hazards.spec | 153 / 0 | | |
| Rest.spec | 55 / 0 | | |
| Trace.spec | 22 / 0 | | |
| responsive.spec | 70 / 0 | | |

**The walk** (800 × 360 touch, HUD only; 4 star walks): lands 0.0 studs from its pad; the free Shredder at 1.0 s; the
first purchase at 22.3 s; **the first Rocket at 33.9-34.1 min**; the recycle at 43.1-43.3 min; 13-14 of 13-14
sputters saved in 5.8-6.6 s; 164 purchases, all HUD taps; 12-13 crane drops from the Foundry to the first Rocket, one
every 2.43-2.64 min, 0 rest frames; the hint never disagreed with the ★; 1 247-1 256 buttons checked, 0 wrongly
painted; run 2's Foundry 1.7 min after the recycle (run 1: 2.4); the rejoin restores bolts, tier and every station,
first purchase 21.1-22.6 s after it. **Green mode** (4 walks, random gold-or-green taps): the first Rocket at
34.2-34.6 min, the recycle at 43.6-43.8, 1 576-1 593 buttons checked, 0 wrong.

## The complete-game standard after round 2

- **§1 works and honest: met.** Core loop reachable from join (the walk, both modes), spawn order, nothing secret
  replicates (still 0 attributes; the State lost its `trouble` field, gained `worth`, neither secret), DataStore lock
  + owner token + one atomic recycle, now also through leave-rejoin-leave (X1) and against a failing store (X3); every
  refusal speaks (the held recycle too).
- **§2 looks good: met.** Bands, Fx, templates unchanged; hazards rare and telegraphed, the ring exactly the zone, and
  now about one every 2.4-2.9 min for everyone including a player with a jam standing (R5); ☕ Break unchanged; budgets
  measured (server parts 266 / 422 of 640); the brag moment at 34.0 min for the ★ follower and **36.8 for a player who
  taps whatever is green** (R3); phone-first HUD, overlap = true.
- **§3 compare: met.** Public + friends board, Gold Bolts, ties to who reached it first, cached; now readable by
  geometry on a phone (R1) and always showing your own row (R2).
- **§4 ready to ship: met.** Store text unchanged (986 characters); `EYECANDY.md` needs-Studio list (29 items) and
  shot list (shot 5 fixed, R8); `MARKETING.md` 8 clips; `CLAUDE.md` names every gate (28) and trap; every gate green;
  every new assertion mutation-tested with controls.
- **§5 night shift: not done, by rule** (Studio, thumbnails, clips, universe, publishing, marketing).

## Still open

- **No real luau CLI on this machine**: every Luau gate ran through the luau2lua/LuaJIT shim (`scratchpad/slt`). Re-run
  every gate with the real CLI (and luau-analyze) before shipping.
- **Never played by a person or opened in Studio.** Everything on `EYECANDY.md` §8 is open, now including the big
  board's look and real legibility (its numbers are geometry with an assumed 12.5-stud default camera), the edge walls
  and the camera, the green / muted / grey colours on a phone, crane drops while walking to a jam, and whether a client
  can replicate a non-finite root CFrame (X2) or fling another player.
- **A player who taps any affordable button whatever its colour** still reaches the first Rocket at about 53 min
  (`Pacing.spec`'s CONTROL); the colours now carry the guidance, and the model's `normal`, `mixed` and `green` players
  are all inside 30-45.
- **REVIEW-1 A4 stays accepted**: a 24/7 bot that walks to every sputter climbs the public board at human speed.
- `Players.MaxPlayers = 6` (Game Settings) and `StreamingEnabled` off in the published place: confirm in Studio.
- Not built: the recycle's crane sweep, "+$" pops, the per-product flow summary, audio (`EYECANDY.md` §10).
- One walk failure in the first sweep's BASE was never captured (see Flakes); the 52 walks since are green.
