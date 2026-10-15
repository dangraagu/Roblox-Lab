# CLAUDE.md — Scrapline Tycoon (Roblox)

Read `DESIGN.md` for the why of every number, `EYECANDY.md` for the bands, hazards, ☕ Break, budgets, the
needs-Studio list and the thumbnail shots, `MARKETING.md` for the clips, `README.md` for the store text.

## What it is

A production-line tycoon for 6 players on 6 plots around the Scrap Market. Junk rides a U-shaped belt past six
stations (Shredder, Furnace, Press, Cutter, Assembler, Rocket Bay) to a dock that sells whatever arrives; each station
handles only so many items a second and the overflow rides past and sells for less. Players upgrade or twin the
bottleneck or save for the next station (the HUD's ★), and walk to a sputtering machine to hold Fix before it jams.
Six bands follow the highest product shipped; the first Rocket of a run lifts off for the server (the brag moment);
Recycle trades a fast enough line for a Gold Bolt (+50 % value forever); the Top Recyclers board ranks Gold Bolts,
public and friends. No PvP, nothing for Robux, no offline income.

## State (2026-10-08)

v1 built test-first from `DESIGN.md`, then two rounds of adversarial review, both in **REVIEW-1.md**: round 1's 10
findings (9 fixed in the game behind a failing test, 1 accepted as a design property: A4) and round 2's 12 (X1-X4,
R1-R8: 9 fixed in the game, 2 flaky checks fixed in the checks, 1 document; all behind a check that failed first and
mutation-tested). **Green in every gate below (28): 4 799 assertions, 0 failed, HUD PASS.** **Never played by a person, never opened in Studio, not published, no universe, nothing committed.** Nothing
only Studio can settle has been settled: that list is `EYECANDY.md` §8.

The build stage ran a second time the same evening (the workflow restarted it). That run changed no game code: it
re-ran every gate, finished the REVIEW-1 mutation sweep the fix round had left at M37 (M38-M45 and controls C3, C4:
all 17 review mutants KILLED, both controls SURVIVED), wrote the missing `REVIEW-1.md` from what the fix round left on
disk, and pinned `Workspace.StreamingEnabled = false` in `default.project.json` behind a new failing-first
`tests/project_spec.py` (gate 25).

**Round 2 (2026-10-07/08)** changed the game: a leave-rejoin-leave no longer cancels the first leave's save (X1); a
root claim that is not a finite number is ignored and Fix's range check is fail-closed (X2); a failed recycle write
holds the next try 10 s (X3); hazards hold only during a live SPUTTER, never for a standing jam (R5); the board is 10 ×
10 on the dock side with 11 rows, readable by geometry on a phone, and always shows your own row (R1, R2); the panel
paints green only what is worth buying (`Economy.worth`), so a player who taps whatever is green lands the first
Rocket in 30-45 min (R3); the step-2 hint follows the ★ (R4); invisible walls close the world's edge (R7). New gates:
`check_scraplinetycoon_guard`, `check_scraplinetycoon_boardview`, the walk's `green` mode. Flaky checks fixed: the red
scan, the sputter gap, the walk's wiped sputter, the yard's far-rocket critter, the hazards set-up.

**The luau CLI was missing.** The task's `scratchpad/luau/` was empty (a search of C: and D: seven directory levels
deep found no luau.exe), and fetching a new one needs the owner's permission. Every gate ran through
`scratchpad/slt/luaushim` (copied from another agent's `scratchpad/ggd/luaushim` this session): `luau2lua.py`
translates Luau to Lua 5.1 + LuaJIT (types stripped, `+=`, `continue`, if-expressions, interpolation, generalized
iteration, `//`) and `luaurun.py` runs it on OBS's `lua51.dll` (LuaJIT 2.1). The `luau` in the commands below is the
wrapper `scratchpad/slt/luau`. What that means: "compiles" = "translates and LuaJIT-compiles", not Luau's own parser,
and there was no luau-analyze. **Re-run every gate with the real luau CLI once it is back, before shipping.**
Cross-check that the shim agrees with the real CLI where it matters: on meteor-drop-tycoon (built and gated with the
real CLI on 2026-10-01) the shim reproduced `Economy 119/0`, `Hazards 153/0` and `check_meteordroptycoon 195/0`.

## How to run every gate

```
# 0. the project file, from scrapline-tycoon/ (Workspace.StreamingEnabled pinned off, the script layout, .gitignore)
py -3 tests/project_spec.py
# 1. pure specs, from scrapline-tycoon/
luau tests/Line.spec.luau      luau tests/Economy.spec.luau   luau tests/Jams.spec.luau      luau tests/Recycle.spec.luau
luau tests/Save.spec.luau      luau tests/Board.spec.luau     luau tests/PlotGeom.spec.luau  luau tests/HudLayout.spec.luau
luau tests/EnvConfig.spec.luau luau tests/Pacing.spec.luau    (about 10 s; the pacing model, tests/LineModel.luau)
luau tests/EnvBands.spec.luau  luau tests/Hazards.spec.luau   luau tests/Rest.spec.luau      luau tests/Trace.spec.luau
luau tests/responsive.spec.luau
# 2. ALWAYS rebuild the bundle before anything headless (a stale bundle has cost this repo hours)
cd ../robloxemu && py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
# 3. headless gates, from robloxemu/
luau check_scraplinetycoon.luau          # the real player path (see below)
luau check_scraplinetycoon_save.luau     # lock, owner token, the recycle's one atomic write, failures, double taps
luau check_scraplinetycoon_board.luau    # Top Recyclers, public + friends, on the owner's own board
luau check_scraplinetycoon_yard.luau     # bands entered by shipping, seams, glide, lift-off, recycle snap, Break, budgets
luau check_scraplinetycoon_hazards.luau  # where/when, ring = zone, 8-direction dodge, rest, the holds
luau check_scraplinetycoon_hud.luau      # hudcheck, 30 viewports in 3 modes, overlap = true
luau check_scraplinetycoon_compile.luau  # compiles, no string require, every Enum item is real
luau check_scraplinetycoon_prompts.luau  # which prompt a player beside a broken machine GETS (keyboard, gamepad, touch)
luau check_scraplinetycoon_guard.luau    # REVIEW-2 X2, X3: non-finite root claims; Recycle spam against a failing store
luau check_scraplinetycoon_boardview.luau # REVIEW-2 R1, R2: a board row's px on a phone; the viewer's own row always drawn
# 4. the walk, from scrapline-tycoon/ (star: taps the gold ★; green: taps any gold or green button, REVIEW-2 R3)
luau tests/walk.luau
luau tests/walk.luau green
```

`scratchpad/slt_r2/gates.sh [gameDir] [emuDir]` runs all 28 in about 55-75 s and prints one line each;
`scratchpad/slt_r2/gates2.sh [gameDir] [emuDir] [outDir]` does the same and keeps every gate's FAIL lines in outDir.
(The older `scratchpad/slt/gates.sh` and `slt_b2/gates.sh` lack the three round-2 gates.)

Last full run (2026-10-08, round 2, bundle rebuilt first): **28 of 28 gates green, 4 799 assertions passed, 0
failed, HUD PASS.** Before it, 12 full runs in parallel copies (336 gate results) were all green.

| gate | result |
|---|---|
| project_spec (`py -3`) | 9 passed, 0 failed |
| Line.spec | 54 passed, 0 failed |
| Economy.spec | 140 / 0 |
| Jams.spec | 47 / 0 |
| Recycle.spec | 54 / 0 |
| Save.spec | 60 / 0 |
| Board.spec (meteor-drop-tycoon's, metric renamed) | 46 / 0 |
| PlotGeom.spec | 116 / 0 |
| HudLayout.spec | 2 554 / 0 |
| EnvConfig.spec | 164 / 0 |
| Pacing.spec | 33 / 0 |
| EnvBands.spec (verbatim) | 124 / 0 |
| Hazards.spec (meteor-drop-tycoon's merge, verbatim) | 153 / 0 |
| Rest.spec (verbatim) | 55 / 0 |
| Trace.spec (meteor-drop-tycoon's, four config names renamed) | 22 / 0 |
| responsive.spec (verbatim) | 70 / 0 |
| check_scraplinetycoon | 392 / 0 |
| check_scraplinetycoon_save | 104 / 0 |
| check_scraplinetycoon_board | 41 / 0 |
| check_scraplinetycoon_boardview | 26 / 0 (REVIEW-2 R1, R2) |
| check_scraplinetycoon_yard | 106 / 0 |
| check_scraplinetycoon_hazards | 101 / 0 |
| check_scraplinetycoon_guard | 34 / 0 (REVIEW-2 X2, X3) |
| check_scraplinetycoon_compile | 220 / 0 (20 sources, 175 Enum uses) |
| check_scraplinetycoon_prompts | 28 / 0 (REVIEW-1 B1) |
| check_scraplinetycoon_hud | PASS at 30 viewports (hudcheck's 10 × idle / panel+toast+alert+hint+warning / recycle confirm), overlap = true |
| walk | 23 / 0 |
| walk green | 23 / 0 (REVIEW-2 R3) |

**Mutation sweep** (2026-10-07, `scratchpad/slt/mutate.py`: an isolated copy under `scratchpad/slt/mut/`, the
pristine source restored before every mutant, md5 before/after recorded, the mutation confirmed in the rebuilt bundle,
all 23 gates per mutant, a gate that dies without a summary counts as KILLED, Git Bash called explicitly): **26 of 28
mutants KILLED; the 2 survivors are each other's backup and the pair is KILLED; both controls SURVIVED.**

| mutant | killed by |
|---|---|
| M1 RespawnLocation not set in PlayerAdded | check_scraplinetycoon (died) |
| M2 Fix reads the raw claim, not the trusted position | check_scraplinetycoon (3 assertions) |
| M3 no Buy rate limit | check_scraplinetycoon (3) |
| M4 no owner-token check on profile writes | _save (5) |
| M5 the recycle applied though its write failed | _save (9) |
| M6 a non-saving session passes the recycle check | _save (2) |
| M7 a recycle resets the jam clock | Recycle.spec (1), check_scraplinetycoon (1), _save (1) |
| M8 a live sputter not saved as a jam | Save.spec (3), check_scraplinetycoon (3) |
| M9 the jam clock runs during a sputter | Jams.spec (5), check_scraplinetycoon (5), _hazards (1) |
| M10 overflow lost instead of sold | Line.spec (20), Economy.spec (5), Pacing.spec (died), check_scraplinetycoon (died), _yard (34), _hazards (3), walk (8) |
| M11 the ★ without rule 0 | Economy.spec (7), Pacing.spec (died), check_scraplinetycoon (2), walk (8) |
| M12 hazards not held during trouble / lift-off / recycle | _hazards (3) |
| M13 hazards off your own plot | _hazards (3) |
| M14 the ring drawn smaller than the zone | _hazards (1) |
| M15 the recycle glides the sky backwards | _yard (3), _hazards (1) |
| M16 the column does not move with the panel | HudLayout.spec (29), _hud (FAIL) |
| M17 tap targets not grown on touch | HudLayout.spec (92), check_scraplinetycoon (1), _hud (FAIL) |
| M18 `savedBolts` set by a read-only session | **SURVIVED: equivalent alone** (boardWrite's canSave guard blocks it) |
| M19 no CharacterAdded correction | check_scraplinetycoon (2) |
| M20 recycle bar 500 rockets/s | Recycle.spec (10), Pacing.spec (2), _save (5) |
| M21 Fix is a tap, not a 0.5 s hold | check_scraplinetycoon (1) |
| M22 the Build button sends the wrong purchase | check_scraplinetycoon (7), walk (11) |
| M23 the tier not saved | _yard (1) |
| M24 the State leaks the jam clock | check_scraplinetycoon (1: the State scan) |
| M25 the Junkyard not hazard-free | EnvConfig.spec (1) |
| M26 two recycles may run at once | _save (1), _hazards (1) |
| M27 boardWrite without its canSave guard | **SURVIVED: equivalent alone** (`savedBolts` is 0 in a read-only session) |
| M28 M18 + M27 together | check_scraplinetycoon (1), _save (1) |
| CONTROL C1 the Scrap Market's colour | survived all 23 gates, as it must |
| CONTROL C2 the printed-only `random` profile's shop cadence | survived all 23 gates, as it must |

The sweep's first set-up exposed one blind spot, closed before the sweep ran: `_save` A's read-only profile had 0
bolts, so no board guard could be tested by it; it now loads 2.

**REVIEW-1's assertions** were swept the same way (`scratchpad/slt_r1/mutate_r1.py`, M29-M45 + 2 controls; table in
`REVIEW-1.md`): **17 of 17 KILLED, controls C3 and C4 SURVIVED.** **Round 2's** (`scratchpad/slt_r2/mutate_r2b.py`,
all 28 gates per mutant, every FAIL line kept, six workers in their own copies): M46-M72, **26 KILLED, M49 equivalent
alone (its pair M50 KILLED)**, controls C6-C9 and two no-edit BASE runs SURVIVED; Y1 (the yard check's critter
sampling) KILLED. Table in `REVIEW-1.md`. The driver died silently twice in long runs (after
M37 in the fix round, after M44 in the second build run: no traceback, no results JSON); every mutant was then run
in a shorter batch, so each one has a printed result. `tests/project_spec.py`: P1 (StreamingEnabled true) and P2 (no
Workspace node) KILLED, control C5 (the project's name) SURVIVED.

TDD record: Line, Economy, Recycle, Save, Board, PlotGeom and HudLayout specs were written and run red (module
missing) before their modules; the Jams spec was written first but its module was written before the spec's first
run (it was not watched red; M9 shows it can fail). EnvConfig.spec checks Config, which existed first. The server and
client glue were written before their headless checks (the checklist's "pure logic gets TDD; the glue gets the
review"); the checks found three real defects on their first runs: LineState never reaching a client that started
late (belt items missing at join), a recycle handler that yielded on the remote's thread, and a first State that reached a
fresh HUD only after 1 s, leaving the first hint blank (now 0.5 s, with "Loading your factory…" until then).

`check_scraplinetycoon.luau` is the real player path: 6 plots built AND parented, exactly one enabled SpawnLocation
each and none elsewhere, belt / stations / consoles / board where DESIGN §3 puts them (positions worked by hand, not
with PlotGeom); a joining character lands on its own pad under the engine's spawn order (also after a respawn and with
RespawnLocation cleared); the real HUD's prompts exist on the owner's plot only and every one is reachable from the
floor; the State never carries the jam clock; the trickle sells; one tap on 🔧 Build Shredder is the core action;
an unaffordable Furnace is refused with both numbers; following the ★ builds the Furnace and a twin; the first Ingot
moves the tier and the sign; the board renders on the owner's own board; the first sputter comes 240 s of line time
after the Shredder; a Fix from the pad and a teleported Fix are refused (trusted position); walking there and holding
the HUD's Fix prompt saves it; a second sputter left alone jams after 15 s and the line earns less; every refusal
speaks and a flood is cut at 8/s; a visitor's Fix acts only on their own plot; budgets and the empty attribute
inventory with six players and four complete lines; a seventh player is kicked with a reason; a rejoin restores every
field, and a sputter live at the leave comes back as a jam.

`tests/walk.luau` is somebody playing on a phone (800 × 360, touch), through the HUD only: it lands, taps 🔧 Build
Shredder, every 20 s taps 🏭 Line and the ★ row's GOLD button (paging with ▼ when the ★ is on another page), notices a
sputter after 4 s and walks at 85 % of WalkSpeed to hold the Fix prompt, and taps ♻ and ✓ Recycle! when ♻ shows ★.
Between those it STANDS STILL (no stick input; REVIEW-1 B3). It plays loop 1 to the first Rocket and the first recycle,
loop 2 through the Foundry and Press Works, then rejoins and buys once more. Seven walks before REVIEW-1 (each differs:
nothing is seeded): the free Shredder at 1.0 s, the first purchase at 21.9-22.3 s, **the first Rocket at 33.9-34.2
min** (model: 34.0), the recycle at 43.1-43.5 min (model: 43.6), 13 of 13 sputters saved in 5.8-6.6 s, 164-165
purchases all taps on the HUD's own buttons, run 2's Foundry 1.6-1.7 min after the recycle (run 1: 2.4). Three walks
after it: the first Rocket at 34.0-34.2 min, the recycle at 43.1-43.3 min, 13 of 13 sputters saved, and 11-13 crane
drops from the Foundry to the first Rocket, one every 2.45-2.88 min, with 0 rest frames. Three walks on the build
stage's second run: the Shredder at 1.0 s, the first purchase at 22.3 s, **the first Rocket at 33.9 min** in all
three, the recycle at 43.0-43.4 min, 13-14 of 13-14 sputters saved in 5.8-6.6 s, 164 purchases all HUD taps, 13-14
crane drops (one every 2.25-2.43 min), 0 rest frames, run 2's Foundry 1.7 min after the recycle, the rejoined
session's first purchase 22.6-26.0 s after the rejoin.

Since round 2 the walk also **audits** every 0.1 s that the hint never names a ★ the HUD does not star (REVIEW-2 R4),
and every time the panel is open that every buy button wears the colour the game's own `Economy.worth` gives it, with
nothing green while the ★ saves for the next station (R3); a curious peek at the panel every 60 s shows the colours
while saving too. A sputter still live at the recycle is counted as wiped by it (R6). `luau tests/walk.luau green`
plays a player who ignores the ★ and taps a random gold or green button on any page every 20 s. Four star walks: the
first Rocket at 33.9-34.1 min, the recycle at 43.1-43.3, a crane drop every 2.43-2.64 min, 1 247-1 256 buttons checked,
0 wrong, 0 hint clashes. Four green walks: the first Rocket at 34.2-34.6 min (50.7 on the game before round 2), the
recycle at 43.6-43.8, 1 576-1 593 buttons checked, 0 wrong.

## Invariants and this game's traps (each is asserted somewhere; the gate is named)

REVIEW-1 (`REVIEW-1.md`) added these; each was a real defect, found by an adversarial reviewer, reproduced, then fixed
behind a failing test:
- **Which prompt a player GETS** (`_prompts`): Roblox shows only the nearest OnePerButton prompt per key, and robloxemu
  does not choose, so a check that fires `prompt.Triggered` proves nothing about reach. Fix is on **F / ButtonY with
  `Exclusivity = AlwaysShow`**; a station's console prompt is disabled while one of its machines is in trouble.
- **The leave frees the plot BEFORE any yield** (`_save` K): Roblox frees the player slot at once and runs
  PlayerRemoving on its own thread; every remote handler and loop skips a `leaving` session (its plot may already be a
  joiner's). Tests leave with `task.spawn(function() h:leave(p) end)`: `h:leave` on the main thread finishes every
  yield first and hides this.
- **A same-server rejoin waits for its own leave's writes** (`leavingByUser`, `Save.LeaveWaitSeconds`, `_save` L): the
  lock lets this JobId through, so the rejoin's load used to take the token and cancel the leave's write.
- **BoardView spam is bounded** (`_board` §6, §7): failed name lookups are not retried for 60 s, one lookup per id in
  flight; each viewer's friend list is cached 5 min (a failure 1 min). `_board` §2 waits past those caches between its
  scenarios.
- **No idle rest** (`Rest.IdleSeconds = 0`, `_hazards` 7c, the walk): a tycoon is played standing still at the HUD.
  The walk stands still between taps (an earlier walk held the stick all game and hid this) and asserts a crane drop
  every 1.5-3.5 min and zero rest frames.
- **☕ Break's camera** is written by `frame()` only while gazing, never by a tween (`_yard` "lets go of the camera").
- **No hazard aim on a perch** (`Hazards.StandAboveFloorMax`, `_hazards` 7b): on a machine the ring would be drawn
  hidden inside it.
- **A SurfaceGui's face is decidable headless** (`check_scraplinetycoon` §1): NormalId.Front is the part's LookVector.
REVIEW-2 (round 2 in `REVIEW-1.md`) added these:
- **A leave registers only when its session LOADED, and a load that waited for an earlier leave takes nothing if its
  own player left meanwhile** (`_save` M): otherwise leave, rejoin, leave cancelled the first leave's save.
- **A root claim that is not a finite number is skipped before `Trace.step`, and Fix's range check is fail-closed**
  (`_guard` 1): inf/inf = NaN made the trusted position NaN for good, and NaN passes `dist > FixRange`.
- **A failed recycle write holds the next try `Recycle.RetrySeconds`** (`_guard` 2, `_save` C), with a toast.
- **Hazards hold only while a machine SPUTTERS** (`_hazards` 7): a standing jam has no clock and used to freeze the
  crane for good. `_hazards` counts a hold only while the State says the sputter is live; its set-up helper fixes a
  sputter that starts inside a wait and waits again.
- **Green means worth buying** (`Economy.worth`, `Star.GreenPayback`, the server's `worth` per row; `Economy.spec`,
  `Pacing.spec` green / green60 and the anyaffordable CONTROL, the walk's colour audit and green mode).
- **The step-2 hint names the Furnace only while the ★ is the Furnace** (the walk's hint audit).
- **The board: 10 × 10 on the dock side, 11 rows, the viewer's own row always drawn** (`_boardview`: a row's px on a
  phone from the built face and the HUD's own rows, against the HUD's own hint text; `PlotGeom.spec`: the frame clears
  every footprint on the floor).
- **The world's edge is four invisible collidable walls** (`check_scraplinetycoon` §1).
- **Flaky checks, fixed in the checks**: the red scan skips only the local telegraph (`HazardZone`, and `HazardPillar`
  which turns ring-red at the lock); the sputter gap is measured from the fix; the yard samples critters over 10
  frames (the far rocket respawns a frame late, invisibly).

- **Workspace.StreamingEnabled is pinned off** (`tests/project_spec.py`): Hud.client caches console and board prompts
  and the board's SurfaceGui on parts of the player's own plot, and robloxemu does not model streaming, so no headless
  check could see a prompt left on a streamed-out part (gnome-garden-defense REVIEW-1 R4). Rojo writes no Workspace
  unless the project names one.

- **Spawn** (`robloxemu/SPAWN-ORDER.md`): every plot's Arrival is a real, enabled SpawnLocation built before anyone
  joins; `PlayerAdded` sets `plr.RespawnLocation` synchronously, before any yield; `CharacterAdded` waits (bounded,
  300 frames) for `char.Parent`, re-reads the session, and corrects a root more than 8 studs from the pad; the trusted
  position restarts at the pad. Assert XZ, not Y (`check_scraplinetycoon` §3, §8).
- **Fix reads the TRUSTED position** (`Trace.luau`, meteor-drop-tycoon's copy, byte-identical): 21.6 studs/s with a 3 s
  banked burst; FixRange 12 from the machine, the prompt shows at 10 (`check_scraplinetycoon` §6: from the pad and
  after a teleport, refused).
- **Cash, tier and bolts come only from the server's flow** (`Line.income` every 0.5 s), which reads only purchases
  `Economy.buy` priced and jams `Jams.fix` cleared. The ★ is `Economy.star` (rules 0-2), computed by the server and
  pushed; rule 2 can never fire (rule 1's score already beats any filler: `Economy.spec` checks the outcome on 3 000
  random lines).
- **Jams**: `Jams.luau`, the server's `Random.new()`; one sputter at a time; the clock runs only while a machine is
  built and no sputter is live; a live sputter is SAVED as a jam (`Save.pack`), the clock is saved (`jamIn`), a
  recycle keeps it. The clock never reaches a client: the State carries only a live sputter
  (`check_scraplinetycoon` scans every State payload), JamIn lives in `ServerStorage.PlotInfo`.
- **No attributes under workspace or ReplicatedStorage** (the check enumerates them and requires 0). Names carry only
  visible facts (`Plot_3`, `Station_Press`, `Machine_Press_b`).
- **Nothing is seeded.** Every draw is a `Random.new()`; pure modules take `rand`. Consequence: every headless run
  differs; the checks hold for any draw and were run several times each.
- **The recycle is one atomic write**: every check first (`Recycle.check`: loaded, saving, not busy, the rate with
  jams counted), then `recycling` is set before any yield, one owner-checked `UpdateAsync` writes the whole new run
  with bolts + 1, and only when it lands is the new run swapped in (`check_scraplinetycoon_save` C, D, H, I, J). A
  non-saving session never recycles (A, E). The handler runs the recycle on its own thread (`task.spawn`): the write
  can yield, and robloxemu runs remote handlers inline (the first version raised "attempt to yield across C-call
  boundary" under injected latency, I).
- **Saving** is meteor-drop-tycoon's code after its REVIEW-1: lock + owner token, load retried 3 times, a lock waited
  for 15 s at the join, a read-only session re-checking every 15 s, writes serialised per session, `pending` cleared
  before the yield, no re-lock after the leave began (`_save` A, B, E, F, G).
- **The board writes only what was SAVED** (`savedBolts`, set by a successful write), only when it improves, never from
  a non-saving session; a count saved in an earlier session whose board write never landed is ranked at the next join
  with its own `boltsAt` (`_board` §3). The owner's rows render on a SurfaceGui in their PlayerGui; the toggle is a
  ProximityPrompt the owner's client creates on its own board, firing `BoardView(mode)`.
- **Every ProximityPrompt is created by the owner's client on its own plot** (consoles, Fix, board). The server
  creates none; `check_scraplinetycoon` counts zero on every other plot.
- **The HUD is one pure layout** (`HudLayout.luau`) for both client scripts: three column slots (Hud draws 1 and 3,
  Yard draws 2), a line panel that PAGES instead of scrolling (hudcheck measures a scrolled-away row where it would be
  with no scroll, under the jump button), the column moving with the panel. Slot 3 is ♻ Recycle, the panel's ▼ page
  turner, or the confirmation's ✕ Not yet; the confirm itself is slot 1, so a double tap on ♻ cancels instead of
  recycling.
- **Yard.client never fires a remote and never writes a server part**; your own belt is drawn from your own State
  (immediate), everyone else's from `LineState` (on change, at most 1/s, and every 5 s anyway: a client that started
  after the last send still draws every line).
- **The sky snaps only when the tier DROPS** (a recycle), whichever of `State` and `Fx` arrives first; every other
  change glides. `ClockTime` rises band to band (`EnvConfig.spec`), so a glide never sweeps the sun backwards.
- **Hazards are held** (`ctx.canDodge = false`) while a machine sputters (not for a standing jam: REVIEW-2 R5), during
  the lift-off and the recycle sequence; off your own plot the clock does not run (`_hazards` §3, §7-9).

## robloxemu and machine quirks met while building this

- `FireClient` fires `OnClientEvent` for every connection whoever the target, and a client's `FireServer` is
  attributed to `Players.LocalPlayer`, which `h:join` moves to the newest player. Checks that run the HUD assert on it
  only while one player is joined, or put LocalPlayer back (`check_scraplinetycoon_board` §2) and read payloads with
  `sentTo`.
- `simulateFireServer` runs the handler inline on the caller's thread: a handler that yields must spawn its work.
- `State:sentTo(plr)` includes payloads sent before a client script connected; a client's own view can lag that by up
  to one push (0.5 s). The State throttle has a millisecond of slack: without it the 0.5 s line tick missed the 0.5 s
  throttle by a rounding error and the first State reached a fresh HUD only after 1 s (found by the walk).
- One Harness per process: a check that needs several worlds rejoins one player with a new record (`_prompts`), and
  earlier HUD instances keep listening (every `OnClientEvent` connection fires).
- A Tween's `Cancel()` does not stop the goal robloxemu applies when its Time is up, and repeating tweens are not
  modelled: a tween left playing shows up as one late write (`_yard` writes a sentinel CFrame and watches it).
- Methods cannot be overridden on an Instance (`h.Players.GetNameFromUserIdAsync = …` raises); `_board` §6 wraps the
  shared Instance metatable's `__index` for that one key and restores it. Unset properties read as nil (a prompt's
  `Enabled`, `KeyboardKeyCode`), so game code compares with `~= not x`, and checks default nil to Roblox's defaults.
- The scratchpad is shared with other agents; this build used `scratchpad/slt/` only (REVIEW-1: `scratchpad/slt_r1/`). Python's `subprocess` `bash` is
  WSL on this machine: the mutation driver calls `C:\Program Files\Git\bin\bash.exe` explicitly.

## Files

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
src/server/Main.server.luau   world, line tick, jams, Buy/Fix/Recycle/BoardView, saving, the board
src/client/Hud.client.luau    wallet, alert, toasts, hint, column slots 1+3, paged line panel, recycle confirm, prompts, board rows
src/client/Yard.client.luau   bands, belt items, machine animation, lift-off, hazards, ☕ Break (slot 2), chip, warning, card
src/shared/  Config Line Economy Jams Recycle Save Board PlotGeom HudLayout YardArt  (game)
             EnvBands Rest Responsive FxClient (plus1-jump, verbatim)  Hazards Trace (meteor-drop-tycoon, verbatim)
             Fx (plus1-jump + Presets.Junkyard)
tests/       *.spec.luau (15), project_spec.py, LineModel.luau (the pacing model), walk.luau (the player's path)
design/      model.py + model.out.txt (the design-time model DESIGN.md quotes; LineModel supersedes it)
../robloxemu/check_scraplinetycoon*.luau (8)
REVIEW-1.md            the two adversarial reviews' 10 findings: what a player met, the fix, the check, the mutants
                       (written on the build stage's second run from what the fix round left on disk)
```

## Things the suite does not see

- Anything rendered: colours, readability, beams, bloom, SurfaceGuis, the camera drift, belt-item continuity
  (`EYECANDY.md` §8).
- Real physics: the knock, sitting without a seat, walking with a thumbstick, the belt running through machine bodies.
- Real prompt input: `_prompts` applies Roblox's measured keyboard rule and a worst case for touch; how a phone
  actually shows several client-created prompts is EYECANDY §8 item 9.
- Real networking: replication delay, remote ordering between `Fx` and `State`, DataStore throttling and per-key write
  limits (robloxemu returns a budget of 1000 always).
- Real players: the pacing profiles are assumptions. The walk agrees with the model (34.0 min) because it plays the
  model's normal player through the HUD; a person who ignores the ★ is at about 53 min (`Pacing.spec`, cheapest and
  random policies), outside the 30-45 window. Watch that first.
- Real Luau: every run went through the luau2lua shim (above).

## Next (night shift, 00:00-06:00, per `docs/complete-game-standard.md` §5)

Re-run every gate with the real luau CLI; the Studio check of EYECANDY §8; thumbnails (EYECANDY §9); clips
(MARKETING.md); then the universe, publishing (a git-ignored `publish_*.bat`), the maturity questionnaire, and only
after that marketing.
