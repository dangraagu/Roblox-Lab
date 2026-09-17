# CLAUDE.md — FACILITY: Endless Nightmare (Roblox)

Context so a fresh session can continue. Sibling of `deep-vein/`, `vault-runners/`,
`nightwatch-manor/` and the rest; same stack (Config-driven pure modules tested from the luau CLI,
DataStore with a pcall'd `GetDataStore` and a GUID session lock, phone-first HUD, headless gates in
`robloxemu`). The design, with the measurement behind every number, is `DESIGN.md`; read §0 first.

## State — v1 BUILT and headless-tested; NEVER opened in Studio, NEVER played by a person; NOT published

- No universe, no place ID, nothing committed, nothing pushed. Nothing here has ever rendered.
- Built 2026-09-16; verified and fixed 2026-09-17 (second pass); the seven findings of two
  adversarial reviewers closed the same day (third pass, `REVIEW-1.md`). All gates green on the final
  code; exact counts at the bottom of this file and in REVIEW-1.md.
- Mutation sweeps: second pass 35 KILLED, 3 controls SURVIVED (table below); the REVIEW-1 pass is in
  REVIEW-1.md.
- Deliberate deviations from DESIGN.md, each with its measured reason:
  - §9/§14: the trusted position routes claims through open doorways instead of clamping every
    claim that meets a wall (trap 15). It still never crosses a wall or a closed door.
  - §4.4/§4.5: an item's offset in its room and the room's props come from THAT ROOM's own stream,
    keyed off the decor seed and the room id; not from the loot stream after the room choices, and
    not from one decor stream run room after room (trap 19). Which rooms hold items is still the
    loot stream's, draw for draw, so Appendix A's M1 still reproduces.
  - §2.2: the exit's emergency light fails one ring after the farthest ring UNLESS the elevator is
    powered (trap 22). A powered elevator never goes dark, so the choice still has no timer.
  - §2.6: where a prop on the far wall crosses the figure's line, the figure stands in front of it
    instead of 2 studs off the wall (trap 23).
  - §12: E and Q choose EXTRACT and DESCEND on a keyboard, and the choice panel shows only while the
    player stands in the powered lift (traps 20, 21).
- Studio is the next step, and everything in "Needs Studio" is unverified.

## How to run every gate

Git Bash, from `D:\Claude\Roblox`. `L` is the luau CLI directory (`luau.exe`, `luau-compile.exe`,
`luau-analyze.exe`). The luau CLI prints to stderr: always `2>&1`. Use `py -3`, never `python3`
(in Git Bash `python3` is the Windows Store stub and hangs).

```
# 1. pure specs (one per shared module)
cd facility-nightmare
for s in tests/Config tests/Economy tests/Facility tests/Survival tests/Trust tests/Responsive tests/Rng tests/MazeGen; do $L/luau.exe $s.spec.luau 2>&1 | tail -1; done

# 2. ALWAYS rebuild the bundle before anything headless (the gates read build/, not src/)
cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau

# 3. headless gates
$L/luau.exe check_facilitynightmare.luau 2>&1 | tail -1        # world, spawn, run, trust, leaks, saves, label faces
$L/luau.exe check_facilitynightmare_input.luau 2>&1 | tail -1  # every HUD button and key, pressed through the real HUD (a phone)
$L/luau.exe check_facilitynightmare_desktop.luau 2>&1 | tail -1 # mouse and keyboard: Modal, E/Q, camera zoom, the stalled lift
$L/luau.exe check_facilitynightmare_hud.luau 2>&1 | tail -1    # HUD x 10 viewports x 3 modes
cd ../facility-nightmare
$L/luau.exe tests/Fx.spec.luau 2>&1 | tail -1                  # Fx/FxClient, through the harness
$L/luau.exe tests/walk.luau 2>&1                                # the player's path, in numbers

# 4. syntax and lint
for f in src/shared/*.luau src/server/*.luau src/client/*.luau; do $L/luau-compile.exe --binary "$f" >/dev/null || echo "FAIL $f"; done
for f in src/shared/*.luau src/server/*.luau src/client/*.luau; do $L/luau-analyze.exe "$f" 2>&1 | grep -v "Unknown global\|Unknown type\|Unknown require"; done

# 5. the place builds
rojo build default.project.json -o <somewhere outside the repo>.rbxlx

# a MEASUREMENT, not a gate (about 7 minutes per 200 runs per speed)
$L/luau.exe tests/curve.luau 2>&1
```

`luau-analyze` is clean on 11 of 12 sources after filtering Roblox globals. The 12th, `MazeGen.luau`,
reports 10 strict-mode type errors — it is a VERBATIM copy (md5 `c269d302…`) and the original in
`vault-runners/` reports the same; do not edit it to silence them (DESIGN.md §4.2).

Seeds are engine entropy, so **every headless run plays different floors**. The check's and the
input check's assertion counts are stable; the walk's count varies with how deep its second run gets.
Only a failure count above 0 matters.

## Files

- `src/shared/Config.luau` — every tunable. `tests/Config.spec.luau` pins DESIGN.md §5's values and
  the relations between them (flicker < smallest measured step, pickup < wall clearance, zone reach).
- `src/shared/Facility.luau` — pure generator: plan (walls, loot rooms and per-room dressing from three
  independent seeds; `roomSeed` keys each room's own stream), the model explorer, the front, the Part
  specs the server builds, and `apparition` (where the figure stands, and its six limbs).
- `src/shared/Survival.luau` — battery, exposure, stamina, Second Wind, one tick at a time.
- `src/shared/Trust.luau` — the trusted position and cell: speed-bounded, routed through open
  doorways, clamped where no open doorway leads.
- `src/shared/Economy.luau` — pay, perks, profile sanitise, settle-exactly-once, purchases.
- `src/shared/Rng.luau`, `MazeGen.luau`, `Responsive.luau`, `FxClient.luau` — verbatim copies.
  `Fx.luau` is anomaly-observatory's variant plus `Fx.Presets.Facility`.
- `src/server/Main.server.luau` — authoritative. `src/client/Hud.client.luau` — display only.
- `tests/Bot.luau` — a headless PLAYER used by the walk, the curve and the robloxemu checks. It knows
  only what a client could know (the workspace, its own State/Notice) and moves at the server's
  WalkSpeed.
- `tests/walk.luau` — join -> 3 sublevels -> EXTRACT -> perk -> a second run at the slow proxy.
- `tests/curve.luau` — the built game's difficulty curve, played by the bot (a measurement).
- `../robloxemu/check_facilitynightmare.luau`, `check_facilitynightmare_input.luau`,
  `check_facilitynightmare_desktop.luau`, `check_facilitynightmare_hud.luau` — the emulator gates.
- `REVIEW-1.md` — the two adversarial reviews: every finding, how it was reproduced and closed.
- `design-measure/` — the rig DESIGN.md's numbers came from. NOT game code; never copy it into src/.

## The model, and the invariants that hold it together

- **The world is built and parented before anything else.** Hub, HubSpawn (the ONLY enabled
  SpawnLocation anywhere), remotes — all synchronous at server start, before PlayerAdded is
  connected. `plr.RespawnLocation = HubSpawn` in PlayerAdded; the CharacterAdded handler writes no
  CFrame and never yields (robloxemu/SPAWN-ORDER.md). The check re-counts enabled spawns MID-RUN,
  with zones built, because counting at boot missed a stray spawn in a zone (mutation M22).
- **One zone per player**, `workspace.Facility.Zone_<i>` at `(400 i, 0, 0)`, index recycled on leave.
  A zone holds `RideCar` and, during a run, `Floor` (`Rooms/Room_<id>`, `Doors/Door_<lo>_<hi>`,
  `EntryCar`, `ExitLift`, `Apparition`). A room exists only after a trusted door-open into it.
- **Nothing that gives the floor away is on an Instance.** Zones carry zero attributes (the check
  enumerates every attribute under every zone against an empty list). The plan, seeds, step and
  hold live in server memory; `ServerStorage.FacilityDebug.Run_<uid>` mirrors them for the checks
  only, and the check sweeps Workspace and ReplicatedStorage for those attribute names. The State
  payload is enumerated against an exact key set.
- **What a built room shows is a function of that room alone** (trap 19): its doors, its own item's
  offset and its props, drawn from a stream keyed off (decor seed, room id). No replicated position
  is a draw of the loot stream, and no room's dressing shifts with another room's contents.
- **Every rule reads the trusted position** (`Trust.step`, fed the root part's claim once per
  0.1 s tick at the speed the SERVER set). Doors, pickups, fuse insertion, lit/dark, exposure and
  CHOOSE all use the trusted cell. CHOOSE is refused unless the trusted cell is the exit (M18).
  Trust's rules: (1) no faster than 1.35 x the server's speed, with up to 3 s banked; (2) a room
  edge is crossed only inside an OPEN doorway's 6-stud band, and a claim that no open doorway leads
  to is clamped; (3) a claim in a room that open doorways do lead to is walked there through them.
  `Trust.spec` checks rule 3 against honest walkers with random claim freezes AND against random
  adversarial claims (never faster than the bound, never through a wall or a shut door).
- **The front is derived from the floor.** `step = max(28/16, slack(k) x Tmodel / (maxD + 2))`;
  room r dies at `hold + (2 + d(r)) x step`, flickers 2 s before; an UNPOWERED exit dies at
  `hold + (2 + maxD + 1) x step`, after every other room; a powered exit never dies. `hold` is 0,
  or nil (held) on a first-ever run's sublevel 1 until the first fuse. The run clock is accumulated
  from `task.wait`'s return value inside ONE server tick loop, which also runs boarding, the ride
  and the death beat — so arrivals and deaths land on tick boundaries and the check can time them.
- **A run is paid exactly once.** `Economy.settle` clears `openRun` in the same step that pays it;
  EXTRACT pays all, `dark` / `reset` (Humanoid.Died) / `left` / `shutdown` / `load` (a checkpoint
  found on the next join) pay `floor(keep% x run / 100)` in integer arithmetic.
- **Purchases are atomic**: snapshot -> apply -> flush the whole profile under the lock -> roll back
  and say "nothing was spent" if the write did not persist. Refused while a purchase is in flight,
  and NO RUN STARTS while one is in flight (trap 11).
- **Sprint**: held while requested and stamina lasts; emptying the bar exhausts it until the request
  is released OR pressed afresh (`sprintPressed`). A sprint tick costs its WHOLE dt, and a request the
  bar cannot fund is exhausted exactly as an empty bar is (trap 24). Arriving on a sublevel clears
  both the light and the sprint request.
- **The choice** shows only while the State says `atLift` (powered AND the trusted cell is the exit).
  While it shows, EXTRACT is `Modal` (a PC cursor is freed) and E / Q choose; at no other time.
- **A dark death does not kill the Humanoid** (it would enter the respawn cycle the emulator does not
  model). Beat, then a server move to HubArrival.

## Traps this build hit (1-8 and 11-25 each have an assertion now; 9-10 are notes)

1. **Sprint flip-flop at empty stamina.** DESIGN.md §2.3 read literally ("sprint while requested and
   stamina > 0; refill while not sprinting") makes a held Shift alternate 24/16 every tick at empty,
   an average of 20 studs/s for ever. Found by the headless check, not the spec. Fix: emptying the
   bar EXHAUSTS sprint until the request is released (`Survival.luau`, spec "EXHAUSTION").
2. **`PointLight.Enabled` never written reads nil headless** (Roblox defaults it true). Every `RoomLight`
   sets `Enabled = true` explicitly; section I of the check ("60 s standing in the entry: still
   lit") is what caught it.
3. **The elevator can power while the player is only passing through its room.** CHOOSE is then
   refused from the next room (correctly). The bot walks back; the walk counts pay from the server's
   `choice` notices, not from how the bot's floor ended.
4. **A light left on at an exit came straight back on after the ride** and drained the battery in a
   lit entry room: `Survival.arrive` cleared the state but the server kept the request. Arrival
   clears `sess.wantLight` too (and, from trap 12, `sess.wantSprint`).
5. **A DataStore error on join told the player their file was open on another server.** The claim
   now reports `failed` separately; both the join toast and the elevator's refusal say "Couldn't reach
   the save server — retrying", and the autosave loop retries the claim (check section K2).
6. **Sprint pressed in the break room was silently ignored.** Pressing is answered; releasing Shift
   there is not (it would toast on every key-up after a run).
7. **DESIGN.md §14 invariant 8 is false as literally written** when the exit is the unique farthest
   room: then no non-exit room dies at `hold + slack x Tmodel`. The spec asserts what is true — a room
   at the exit's distance would die at exactly that time, and every non-exit room is dark by then.
8. **LIGHT/SPRINT placement.** §12 says 45-70% of screen height on the right edge; on a 640x300 phone
   70% is inside the jump button's band. The band wins; the stack's bottom is `min(70%, band top)`.
9. **Harness traps in the gates themselves**, all found by a gate asserting something vacuous:
   a bot's toasts only drain on bot ticks; a bot manages its own flashlight and will switch a light
   off in a lit room; once a neighbour room is built the `Doors` folder also holds ITS leaves; a toast
   from join matched a later assertion about the elevator's refusal. In a spec, `require` is a
   builtin the compiler resolves, so the harness's Instance `require` is reached as `h:_require(...)`.
10. **Client timers use `tick()`, not `os.clock()`**: os.clock is CPU time and barely moves under the
    virtual clock.
11. **A failed purchase wiped out a run started while it was saving.** `BuyPerk` yields in
    `UpdateAsync`; the player walked into the car meanwhile; the flush failed and restored the
    pre-purchase snapshot, which had no `openRun`. At the exit `power()` then raised
    `Main.server.luau:928: attempt to index nil with 'runEssence'`: no choice panel, and the run paid
    0. The emulator's store never yields, so no gate could see it until check section J2 gave the
    store a 6 s yield and a failure. Fix: no run starts while `sess.buying` ("Still saving your
    purchase — one moment.").
12. **On a phone every sprint after the first cost two taps.** SPRINT is a tap, not a held key: after
    the bar ran out the request was still "on", so the next tap sent a release. Found only by
    pressing the real button (`check_facilitynightmare_input.luau`). Fix: Survival re-arms on a fresh
    press (`sprintPressed`), the tap asks for the opposite of what the server says it is doing, and
    arrival clears the sprint request so a toggle left on does not burn stamina in the next entry.
13. **The fuse panel's slots faced away from the lift.** A SurfaceGui draws on one face; `Front` is
    -Z, and the panel stands on the lift's -Z edge, so a player standing in the lift to choose saw a
    blank slab. Now one SurfaceGui per face (Front and Back), both refreshed.
14. **Every hub label was stretched.** A fixed 400x200 canvas on a 7 x 1.6 stud sign drew SERVICE
    ELEVATOR 2.19 times too wide; on the 4 x 5 terminal, PERKS 2.50 times too tall. The canvas now
    takes the face's proportions; the check compares every SurfaceGui in the world with its face.
15. **An honest player under lag was pinned in the room behind them (DESIGN.md §9 deviation).** The
    trusted walk was one straight line toward the claim, clamped where it met a wall. Stepping
    through a doorway and turning along the wall while the server's copy of the claim froze for
    0.8 s or more turned into a claim "through the wall", and the trusted cell stayed in the room
    behind for as long as the player kept away from the doorway's line: its dark, its doors, its
    pickups. Measured in `Trust.spec` before the fix: a 0.5 s freeze was fine, 0.8 / 1.2 / 1.5 s
    pinned; under a random lag model 236 of 1000+ honest stops were wrong. Fix: rule 3, route
    through open doorways. The honest-walker property now has 0 wrong; the adversarial property
    (random claims anywhere, 60 000 ticks) finds nothing faster than the bound and no crossing
    through a wall or a shut door, before and after. To the server, "a claim through the wall
    beside an open doorway" and "an honest player whose claims froze" are the same input, which is
    why the old clamp could not be kept for one without breaking the other.
16. **DESIGN.md §11.4's camera shake when the player's own room dies was missing.** The server now
    sends `roomDied` when the trusted room dies around the player (not when they walk into a dark
    one); the input check spies on `FxClient.shake`.
17. **The bot read a stale State.** A picked-up fuse's Part is destroyed at once, the State push
    lands up to 0.2 s later, and the bot concluded "nothing left and a fuse missing": 3 bot errors in
    595 probe floors before a short wait, 0 in 600 after (`tests/curve.luau` found it).
18. **Two check flakes, both the bot and not the game.** (a) A 16 studs/s bot died on sublevel 1 on 3
    of 11 000 probe floors (long, unlucky layouts), which failed the check twice in about 1 370 runs;
    VET now carries Deep Cell 3, which nothing VET checks depends on. (b) The input check waited a
    fixed 30 s for the entry room to die; the entry dies at 2 x step, which ran longer on 4 of 39
    floors in the first sweep; it now waits for the flicker. After both: 40 of 40 runs green of
    each file.

19. **One replicated Fuse position gave away every fuse room (REVIEW-1 A1).** An item's (x, z) were
    the loot stream's next two draws after the room choices, and `Rng.next` is the LCG's whole state
    / 2^32: a client read the Part's Position, stepped the LCG back to the loot seed and replayed the
    room choices. The reviewer's end-to-end probe had the true fuse rooms inside its candidate set on
    18 of 18 headless floors, 0.4-0.5 s into a run. Props leaked the same way, more weakly (one decor
    stream, room after room). Fix: per-room streams (`Facility.roomSeed`). Facility.spec 5b runs the
    attack (1800 of 1800 plans leaked before, 0 after) and checks that another loot seed moves no
    item within its room and no prop of a room whose own item is unchanged.
20. **A PC player could not EXTRACT or DESCEND (REVIEW-1 B1, critical).** LockFirstPerson pins the
    cursor to the screen centre, which on 1280x720 is in the 12 px gap between the two buttons; no
    button was Modal and no key chose. Fix: EXTRACT is Modal exactly while the choice shows, CLOSE
    while the perk panel shows; E / Q choose; the labels say so on a keyboard;
    `Player.CameraMinZoomDistance = 6` puts the break-room camera back behind the character. The
    cursor itself is Studio-only.
21. **A phone player who stepped out of the powered lift lost LIGHT and SPRINT (REVIEW-1 B2).** The
    modal could not be closed and followed them: in the next dark room the dark took them in about
    3 s, on 3 of 3 floors. Fix: the State's `atLift`; the HUD shows the choice only there, and the
    dark hint outranks the lift hint.
22. **A run could stall for ever in the unpowered lift (REVIEW-1 B3).** No battery, the missing fuses
    beyond the grace, and the one room that never went dark: 600 s measured, nothing happened. Fix:
    `Config.Front.ExitExtraRings = 1`. The hint also counts the fuses still MISSING ("Find 1 more
    fuse"), not the total.
23. **The apparition stood inside a desk, crate or cabinet (REVIEW-1 B4)**: 73 of 707 in this pass's
    re-run of the reviewer's probe. Fix: `Facility.apparition` stands it in front of a far-wall prop;
    the server builds from it; Facility.spec checks every spot, and the walk checks every figure it
    meets against the room's parts in the workspace.
24. **Sprint(true) on every tick averaged 20.03 studs/s (REVIEW-1 A3)**, against 18.67 for the best
    honest pattern: a press cleared exhaustion, and a 0.05 s crumb bought a whole 0.1 s tick. Fix: a
    tick is paid in full. The spam now sits on the paid-for ceiling (18.70 over 600 s).
25. **Leaving while the join's lock claim was in flight left the file locked (REVIEW-1 A2)**: the next
    join was told "open on another server" and could not save for 59.1 s. Fix: a claim that comes
    back after the player left releases its own lock (`releaseLock`), and never another server's
    (check K3).

## Mutation sweeps

The REVIEW-1 sweep (33 mutations on the code the seven fixes touched, 28 KILLED, 1 equivalent
SURVIVED and its line deleted, 4 controls SURVIVED; every mutation proven to be in the bundle) is the
table in `REVIEW-1.md`. Its driver is `fnm-rv1/mutate_rv1.py` in that session's scratchpad.

### Second pass, 2026-09-17

Driver in the session scratchpad (`fnm/mutate2.py`): take a backup of `src/`, then per mutation
restore, require the old text exactly once and the file's sha256 to change, rebuild the bundle, run
all 13 gates, restore; a gate with no summary line counts as KILLED; `src/` verified byte-identical
to the backup afterwards (true, 12 files).

| # | mutation | result (gates that killed it) |
|---|---|---|
| M1 | trust crosses a closed door | KILLED (Trust.spec) |
| M2 | trust ignores the speed bound | KILLED (Trust.spec) |
| M3 | exposure rises with the light on | KILLED (Survival.spec, check, input) |
| M4 | a cell is consumed at a full battery | KILLED (Survival.spec) |
| M5 | settle leaves the run open (double pay) | KILLED (Economy.spec, check, input, walk) |
| M6 | death keeps 100% | KILLED (Economy.spec, check, walk) |
| M7 | the exit room dies too | KILLED (Facility.spec) |
| M8 | no onboarding fuse | KILLED (Facility.spec) |
| M9 | RespawnLocation never set | KILLED (check) |
| M10 | an attribute leaks onto a room | KILLED (check) |
| M11 | the whole floor is built on arrival | KILLED (check, input, hud, walk) |
| M13 | a failed purchase is not rolled back | KILLED (check) |
| M14 | a dark death pays nothing | KILLED (check, walk) |
| M15 | LIGHT/SPRINT drawn into the jump band | KILLED (hud) |
| M17 | rooms go dark 5 s late | KILLED (check, input) |
| M18 | CHOOSE accepted away from the elevator | KILLED (check) |
| M19 | flashlight argument not type-checked | KILLED (check) |
| M20 | stepping out of the car cancels silently | KILLED (check) |
| M21 | sprint exhaustion removed | KILLED (Survival.spec, input) |
| M22 | a second enabled SpawnLocation in a zone | KILLED (check) |
| M23 | the session lock is never released on leave | KILLED (check) |
| N1 | a run may start while a purchase is saving | KILLED (check) |
| N2 | fuse panel drawn on the Front face only | KILLED (check) |
| N3 | only the first panel face is refreshed | KILLED (check) |
| N4 | label canvas back to a fixed 400x200 | KILLED (check) |
| N5 | Survival ignores a fresh press | KILLED (Survival.spec, input) |
| N6 | the server never records a press | KILLED (input) |
| N7 | arrival keeps the sprint request | KILLED (input) |
| N8 | SPRINT tap back to `not wantSprint` | KILLED (input) |
| N9 | no `roomDied` notice | KILLED (input) |
| N10 | client ignores `roomDied` | KILLED (input) |
| N11 | trust routing off (straight line only) | KILLED (Trust.spec) |
| N12 | route aims at the claim's lateral, unclamped | KILLED (Trust.spec) |
| N13 | route never squares up before a doorway | KILLED (Trust.spec) — SURVIVED the first run of this sweep; the one-tick burst assertion was added |
| N14 | route ignores whether a door is open | KILLED (Trust.spec) |
| CONTROL | room wall colour 150 -> 151 | SURVIVED (as it must) |
| CONTROL | dust emitter rate 4 -> 5 | SURVIVED (as it must) |
| CONTROL | route squares up 0.6 studs either side of an edge, not 0.5 | SURVIVED (as it must) |

(M12 was dropped in the first sweep: a naive CFrame write in CharacterAdded is overwritten by the
engine step and is not a defect under the modelled spawn order. M16, "HUD root not grown by
1/scale", survived the first sweep as an equivalent mutation — every root child is positioned by
offsets computed from `viewport / scale` — and was not re-run.)

## The built game's difficulty, measured headless (`tests/curve.luau`, 2026-09-17)

200 fresh runs per row, perk-less unless the row says otherwise (runs = 1, so no first-run hold, as in DESIGN.md's M4), played by
`tests/Bot.luau` on the real server until the dark took the player or sublevel 12 was powered.
P = the share of runs that powered sublevel k.

| | p10 / p50 / p90 powered | P(1) | P(2) | P(3) | P(4) | P(5) | P(6) | P(8) | P(10) | P(12) | run seconds p50 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| bot, 16 studs/s | 7 / 12 (cap) / 12 | 1.00 | 0.99 | 0.99 | 0.97 | 0.95 | 0.92 | 0.89 | 0.82 | 0.73 | 795 |
| bot, 10.4 studs/s | 2 / 4 / 7 | 0.98 | 0.93 | 0.87 | 0.65 | 0.41 | 0.28 | 0.09 | 0.01 | 0.00 | 449 |
| bot, 10.4 studs/s, Deep Cell rank 1 (the walk's loop 2) | 3 / 5 / 8 | 0.97 | 0.96 | 0.95 | 0.76 | 0.57 | 0.43 | 0.20 | 0.01 | 0.01 | 548 |
| DESIGN.md M4 model, 10.4 | p50 5 | 1.00 | | | 0.89 | 0.63 | 0.38 | 0.09 | | | 494 |
| DESIGN.md M4 model, 16 | p50 15 | | | | | | | | 0.94 | | |

After the REVIEW-1 fixes (which move item offsets and props within rooms and let an unpowered lift
go dark), a paired re-measurement at 10.4 studs/s, 400 runs each, the fixed code and the untouched
pre-review code side by side: P(1 / 2 / 3 / 4 / 5 / 6 / 8 / 10) fixed 0.96 / 0.93 / 0.89 / 0.66 / 0.45 /
0.29 / 0.10 / 0.01, run p50 464 s; pre-review 0.97 / 0.94 / 0.89 / 0.63 / 0.44 / 0.29 / 0.10 / 0.01,
run p50 453 s. Both medians 4. At 16 studs/s (200 runs, fixed code): P(4 / 6 / 8 / 10 / 12) 0.96 / 0.94
/ 0.93 / 0.83 / 0.73. No change beyond sampling noise.

The bot plays the built game somewhat harder than the design's model explorer. It is not that
explorer — it walks to every item it can see before opening another door, and backtracks for cells
— so the table checks the order of the model's numbers, not the numbers. It found no divergence
between the server's trusted room and the room the bot stood in, in 2 500 probe floors on the old
Trust and 8 500 on the new one (the bot's claims never freeze). The walk's loop 2 (10.4 studs/s, Deep Cell rank 1), 40 walks: died
on sublevel 4 / 5 / 6 / 7 / 8 in 15 / 6 / 7 / 4 / 2, extracted after sublevel 8 in 6.

## What is NOT covered headless

- Anything rendered: lighting, darkness, the flashlight cone, the flicker, SurfaceGui labels, the
  apparition's look and its client-side hiding (the hide loop runs, but nothing checks it).
- Physics: collisions with walls, props and door leaves; humanoids fitting 6x9 doorways; falling
  out of the world. The bot walks doorway centres; the trust stands in for walls in the rules.
- The respawn CYCLE after Humanoid.Died (the emulator does not model it; the check calls
  `simulateSpawn` itself).
- Real input devices and real replication latency. The input check fires `Activated` and
  `UserInputService.InputBegan`; the lag model in `Trust.spec` is invented, not measured.
- DataStore timing (the emulator's store never yields, except where check J2 makes it), write
  queueing on one key, BindToClose's 30 s budget.

## Needs Studio (nothing below is verified)

DESIGN.md §15's eighteen items all still apply; in priority order the first five are:
1. Whether the dark is frightening and fair with real players; time sublevel-1 clears against M8,
   and put real players' depths beside the table above.
2. `Fx.Presets.Facility`: is an unlit room dark, a flashlit room readable, the room light enough?
3. The flashlight SpotLight on the head in LockFirstPerson (the server creates it on `Head`, falling
   back to the root part only because the emulator's character has no Head).
4. Doors: humanoid through a 6x9 doorway, the 8-stud open radius, the leaf tweening up into the
   ceiling (it pokes above the ceiling slab and leaves a 0.5-stud lip under the lintel — unverified).
5. Phone: LIGHT/SPRINT against the jump button, the perk panel, first-person with a thumbstick.

Added by the builds: `char:PivotTo` for every server move (ride car, entry car, HubArrival) on a real
character; `Player.CameraMode` written by the server, and whether the camera is still zoomed into
first person back in the break room; both faces of the exit panel and the proportioned hub labels
readable; `LocalTransparencyModifier` hiding the apparition per client; Rojo's
`StreamingEnabled = false`, `RespawnTime = 3` and `EnableMouseLockOption = false` in the built place
(they are in the built .rbxlx; not seen applied in a running server); Server Size set to 8 in Game
Settings (not settable from the project file); the trusted position under REAL replication — how
long claims actually freeze, and whether routing keeps an honest walker's room right (log
`Trust.throttled` and the trusted-vs-claimed room over a play session); a SPRINT tap within one
State push (0.2 s) of the last reads the old state; gamepad players reach EXTRACT / DESCEND / BUY /
PERKS only through Roblox's UI selection mode (no gamepad bindings exist for them); the console for
DataStore "request was added to queue" warnings when EXTRACT follows the powering checkpoint within
seconds on the same key.

Added by REVIEW-1 (headless proves the flags are set, never what the engine does with them): in
LockFirstPerson at the powered lift, does the visible Modal EXTRACT actually free the cursor, and
does it lock again the moment the panel closes; do E and Q reach the HUD there (nothing else on the
floor binds them); back in the break room after a run, is the camera behind the character with a
free cursor at `CameraMinZoomDistance = 6`, and is 6 a comfortable distance in a 14-stud room; the
unpowered lift going dark after the rest of the floor — does a player understand what happened, and
is one ring enough warning; the figure standing in front of a desk or crate instead of against the
wall — does it still read as a figure; the choice panel vanishing as a phone player steps out of
the lift and coming back as they step in.

## Next

1. Open in Studio (night window) and walk DESIGN.md §15 and the list above top to bottom; replace
   model numbers with measured ones and re-run M4/M5 with a refit speed proxy.
2. The Trust routing change (trap 15) is still the least-measured rule: REVIEW-1's reviewer fuzzed it
   (900 000 ticks, 0 wall or closed-door crossings) but its lag model is invented. Log it in Studio.
3. Only then: create the experience, the maturity questionnaire, the store text in README.md.

## Last run of every gate (2026-09-17, final code after REVIEW-1)

```
Config.spec      106 passed, 0 failed
Economy.spec      93 passed, 0 failed
Facility.spec     84 passed, 0 failed     (still reproduces DESIGN.md Appendix A M1's three rows exactly)
Survival.spec     74 passed, 0 failed
Trust.spec        53 passed, 0 failed
Responsive.spec   70 passed, 0 failed
Rng.spec          37 passed, 0 failed
MazeGen.spec       3 passed, 0 failed
Fx.spec           26 passed, 0 failed
check_facilitynightmare         203 passed, 0 failed   (20 of 20 consecutive runs, different floors each)
check_facilitynightmare_input   116 passed, 0 failed   (20 of 20)
check_facilitynightmare_desktop  47 passed, 0 failed   (20 of 20)
check_facilitynightmare_hud     PASS — 10 viewports x 3 modes (floor, choice, perks), overlap check on
walk                             70 passed, 0 failed   (count varies with depth; 20 of 20 runs 0 failed)
luau-compile --binary          12 of 12 clean
luau-analyze                   11 of 12 clean; MazeGen.luau 10 (verbatim copy)
rojo build                     builds (Rojo 7.7.0)
```

A walk (another run, 63 assertions): spawn on HubSpawn at (-24.00, 3.51, 0.00); spawn -> ride 2.3 s. Loop 1 at 16 studs/s
powered sublevels 1/2/3 after 44.0 / 35.5 / 47.4 s and EXTRACT banked exactly 45 (10 + 15 + 20).
Deep Cell bought (45 -> 20). Loop 2 at 10.4 studs/s powered sublevels 1-5 after 62.0 / 40.7 / 60.7 /
104.2 / 119.0 s (sublevel 4: 42.7 s in dark rooms, battery 55 -> 26.7; sublevel 5: 26.7 -> 6.6) and
the dark took the player on sublevel 6 after 109.2 s, keeping 25 of 100. Profile after: essence 45,
earned 70, runs 2, extractions 1, deepest 5. Worst Part budget: room 17/20, door leaves 28/40, zone
394/600 with all 25 rooms built. 7 apparitions, none inside a wall, prop or item. 671.8 s of virtual
time.
