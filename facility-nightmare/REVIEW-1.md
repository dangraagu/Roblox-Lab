# FACILITY: Endless Nightmare — REVIEW-1: two adversarial reviews, closed

2026-09-17, third pass. Two reviewers, one looking for exploits (A) and one for things a player cannot reach
(B), filed seven findings against the second-pass build. **I reproduced all seven, rejected none, and
closed all seven headless.** For each one: the reviewer's own probe was re-run on the untouched code; a
failing test was written and shown red on the untouched source; the game was fixed, not the test; the
probe was re-run on the fixed code. Every assertion added was mutation-tested (table below).

Nothing here has been opened in Roblox Studio or played by a person. Four of the fixes rest on engine
behaviour the emulator does not model (the cursor, the camera, rendering), and those parts are listed
under "Still open".

Not done: nothing was committed, pushed, published or created on Roblox. `robloxemu/emu/`, `docs/`,
`DESIGN.md`, `tests/Bot.luau` and `tests/curve.luau` are byte-identical to before this pass. The
`lost-found-depot` and `steal-a-cryptid` directories were never opened.

## The seven findings

| id | severity | finding | reproduced (untouched code) | after the fix | verdict |
|---|---|---|---|---|---|
| A1 | medium | one replicated Fuse/Cell position gives away the loot stream | reviewer's pure probe: loot state recovered on 200 of 200 floors, true fuse set among the hypotheses on 200 of 200; end to end: true fuse rooms inside the candidate set on 18 of 18 floors | pure probe: true set among hypotheses on 2 of 400 floors, never uniquely determined; end to end: 2 of 27 floors (chance) | CLOSED |
| A2 | low | leaving during the join's lock claim leaves the file locked | the stored lock names the departed session; the rejoin cannot save for 59.1 s and is told "open on another server" | stored lock nil; the rejoin can save after 0.0 s, no toast | CLOSED |
| A3 | low | Sprint(true) on every tick averages 20.03 studs/s | walk 16.00, hold Shift 16.05, best honest 18.67, spam 20.03 (Trust envelope 27.03) | spam 18.70 (envelope 25.25), which is the paid-for ceiling for 600 s | CLOSED |
| B1 | critical | mouse and keyboard players cannot EXTRACT or DESCEND | at the choice: LockFirstPerson, 0 Modal buttons, screen centre in the 12 px gap, 21 keys fired produced 0 choices | 1 Modal button while the choice shows, 0 while exploring; E extracts, Q descends; labels name the keys; `CameraMinZoomDistance` 6 | CLOSED headless; cursor needs Studio |
| B2 | medium | a phone player who leaves the powered lift has no LIGHT/SPRINT | 3 of 3 floors: modal shown, LIGHT and SPRINT hidden, dead 2.9-3.1 s into the dark room | 3 of 3 floors: modal gone, LIGHT and SPRINT shown; the gate taps LIGHT and is alive 6 s later | CLOSED |
| B3 | low | a run can stall for ever in the lit exit | 600 s standing in the unpowered lift with no battery: still `floor`, exposure 0.00 | the dark ends the run; 6 desktop-check runs: 57.1 to 134.7 s after reaching the lift | CLOSED |
| B4 | low | about 1 apparition in 14 stands inside a prop | this pass's re-run of the reviewer's probe: 73 of 707 apparitions inside a prop (reviewer: 53 of 727) | 0 of 720 (804 floors, 15 060 rooms) | CLOSED |

---

## A1 — one Fuse position gave away every fuse room

**Cause, confirmed in the code.** `Facility.plan` drew the room choices from the loot stream and then
each item's x and z from the SAME stream (`src/shared/Facility.luau`, old lines 264-307). `Rng.next`
returns the LCG's whole state / 2^32, so a client that reads one item Part's Position has the stream's
state, can step it back to the seed and replay the room choices. The decor stream leaked the same way,
more weakly: props were drawn room after room from one stream, so where a room's props started depended
on how many draws every earlier room had used, which depended on those rooms' doors and items.

**Reproduced** with the reviewer's probes on a copy of the untouched code:
`rev_loot.luau`: 200 floors, loot state recovered on 200, the true fuse-room set among the hypotheses on
200, at most 61 359 candidate states scanned per item. `rev_e2e.luau` in the headless engine, reading
only replicated things: the true fuse rooms inside the candidate set on 18 of 18 floors, 21 of 54 fuse
rooms known for certain, mean 5.39 candidate rooms, 73 of 288 rooms built at the moment of the leak.

**Failing tests first** (`tests/Facility.spec.luau`, section 5b), red on the untouched source:
- the attack itself, in exact doubles (stronger than the float32 a client reads): is any item
  coordinate an output of the first 64 loot draws? **1800 of 1800 plans** leaked.
- change only the loot seed: an item moved within its room in **2030** rooms; a prop moved in **3028**
  rooms whose own item was unchanged.
- section 5 was restated. Its old form ("same loot seed, different layout -> identical offsets in draw
  order") asserted the leak's own mechanism; it now asserts that a room holding an item under two
  layouts holds it at the same offset (it failed on the untouched source: 934 rooms compared).

**Fix.** `Facility.roomSeed(seed, room)` (murmur3's 32-bit finaliser over the decor seed and the room
id). Each room gets its own stream: its item's offset first, then its props. The loot stream now
decides WHICH rooms hold items and nothing else. Nothing replicated is ever drawn from it. Two further
tests pin the per-room streams: 20 000 pairs of (room r, room r + 1) first draws fill all 100 bins of a
10 x 10 grid with at least 120 each (without the finaliser 80 bins fall short; with the room ignored,
90), and no two items on one floor share an offset.

**After.** Facility.spec 5b: 0 of 1800 plans, 0 items moved, 0 props moved. `rev_loot.luau`: 400
floors, the true set among the hypotheses on 2, uniquely determined on 0. `rev_e2e.luau`: 27 floors,
true fuse rooms inside the candidate set on 2. The probe still "recovers" a state, as it would from
any LCG output; that state is the room's own dressing stream, and replaying the room choices from it
produces noise. M1 still reproduces exactly (Facility.spec 11), because the room choices are draw for
draw what they were.

**Deviation from DESIGN.md §4.4/§4.5**, recorded in CLAUDE.md: item offsets and props are per room,
from the decor seed, not "a lootRng point" and not one decor stream.

**What an exploiter still learns:** from one prop or item position, the decor seed, and so where an
item WOULD stand and which props WOULD stand in any room given its doors. Which rooms hold items is
not in it. See also "Still open" on the engine seeds.

## A2 — a lock left behind by a player who left during the claim

**Cause.** `attempt()` returned early when the session was gone after `claimProfile` had already
written `lock = {owner = token, expires = now + 45}`. `onPlayerRemoving` could not release it because
`canSave` was still false.

**Reproduced** with `rev_lock.luau` (store yields 1.5 s on the join's claim, then commits; player
leaves 0.5 s in; os.time on the virtual clock): control lock nil and save after 0.0 s; slow claim:
the lock still named the departed session, the rejoin could not save for **59.1 s** and was told
"Your file is open on another server — retrying."

**Failing test first:** `check_facilitynightmare.luau` section K3 (real os.time, so a lock left behind
outlives the file): 4 failures on the untouched source (lock left, rejoin cannot save, false toast,
elevator refuses).

**Fix** (`src/server/Main.server.luau`): `releaseLock(sess)`, called by `attempt()` when a claim that
GOT the lock comes back to a session that no longer exists. It writes `lock = nil` with the stored data
untouched, and only if the lock still names this session. A second test (K3, LEAVER2) writes another
server's lock into the store just before the release runs and asserts it survives.

**After:** check K3 green; `rev_lock.luau`: stored lock nil, save possible after 0.0 s, no toast.

## A3 — sprint spam beat every honest pattern

**Cause.** A press on every tick cleared `exhausted`, and a tick sprinted on any stamina above 1e-9: a
single regen tick's 0.05 s bought a whole 0.1 s at 24 studs/s.

**Reproduced** with `rev_sprint.luau` (the server's tick order, 600 s): walk 16.00, hold Shift 16.05,
best honest hold-release-refill 18.67, Sprint(true) every tick **20.03** (Trust envelope 27.03).

**Failing tests first** (`tests/Survival.spec.luau`, "NO OVERDRAFT"), red on the untouched source:
- spam over 600 s must stay under the paid-for ceiling. Every sprint second must come from the bar or
  from refill earned while walking, S <= 4 + (600 - S) x 4/8, so S <= 202.67 s and the mean is <=
  18.702 studs/s. Got 20.03.
- conservation, fuzzed: 200 trials x 3000 ticks of random press/hold/release with dt jittering 0.08 to
  0.12 s: sprint time never exceeds bar + earned refill. Worst excess was **28.54 s**.
- a key HELD through the end of the bar with a jittering tick never sprints again without a press
  (a guard for the fix's own new branch).

**Fix** (`src/shared/Survival.luau`): a sprint tick must be paid in full (`stamina >= dt`); a request
the bar cannot fund is exhausted exactly as an empty bar is, so a held key cannot flip-flop on crumbs.

**After:** spam 18.70 over 600 s (the 0.03 above hold-release-refill is that pattern ending on a full,
unspent bar), Trust envelope 25.25; worst conservation excess <= 1e-6 s. DESIGN.md §9's "remote spam:
none" is true again.

## B1 — a PC player could not choose (critical)

**Cause.** The server holds the player in `Enum.CameraMode.LockFirstPerson` on the floor. Roblox's
PlayerModule then locks the cursor to the screen centre unless a visible GuiButton has `Modal = true`.
No button did, and no key chose. Back in the break room, the Classic camera re-clamps the old 0.5-stud
distance to `CameraMinZoomDistance`, whose default of 0.5 keeps the player in first person.

**Reproduced** with `rv_desktop_choice.luau` (1280x720, touch off, real server and HUD): CameraMode
LockFirstPerson at the choice; 0 Modal buttons; the screen centre (640, 360) inside the Choice panel but
outside EXTRACT (x 442..634) and DESCEND (x 646..838); 21 keys produced 0 Choose requests. The cursor
behaviour itself is the reviewer's reading of the PlayerModule source and cannot run headless; I accept
it on that source and list its confirmation under Studio.

**Failing test first:** new gate `robloxemu/check_facilitynightmare_desktop.luau`, **15 failures on the
pre-review source** (the verifier re-measured this; an earlier figure of 21 did not reproduce and had no log). It asserts what the fix is made of, on the real HUD:
- a shown Modal button while the choice is up, and while the perk panel is up;
- NO Modal button while exploring or idle (a Modal left on would break mouse-look);
- E extracts and Q descends only while the choice is on screen, and do nothing while exploring;
- the desktop labels and hint name the keys (the phone check asserts they do not);
- `Player.CameraMinZoomDistance` >= 1, the PlayerModule's first-person threshold, in the break room
  before and after a run.

**Fix.** `src/client/Hud.client.luau`: `extractButton.Modal = choiceShown`, `perksClose.Modal =
perks.Visible`, E/Q bound while `choice.Visible`, labels "EXTRACT (E)" / "DESCEND (Q)" where there is no
touch. `src/server/Main.server.luau`: `plr.CameraMinZoomDistance = Config.Hub.CameraMinZoomDistance`
(6) on join. `rv_desktop_choice.luau` after: 1 Modal button at the choice, and the first key tried (E)
extracted.

## B2 — the modal followed a phone player into the dark

**Cause.** `choiceOpen` was set by the "choice" notice and cleared only by leaving the floor, and it
hid LIGHT and SPRINT. The hint put the lift ahead of "your room is dark".

**Reproduced** with `rv_phone_after_power.luau` (800x360, touch): on 3 of 3 powered floors, in the dark
neighbour room: choice shown, LIGHT and SPRINT hidden, dead 2.9 / 3.0 / 3.1 s later.

**Failing test first:** `check_facilitynightmare_input.luau` section C, walked by hand with no bot
ticks, so nothing but a HUD press can light the flashlight. 5 failures on the untouched source (modal
still up, LIGHT hidden, SPRINT hidden, LIGHT not pressable, hint).

**Fix.** The State's run payload gains `atLift` (the floor phase, powered, and the trusted cell is the
exit). It is false until powered, and powering happens only in the lift, so it never reveals where an
unpowered exit is. Section H's exact key set was updated. The HUD shows the choice only while `atLift`,
shows LIGHT/SPRINT otherwise, ranks the dark hint above the lift hint, and away from the lift says "Back
to the freight elevator to EXTRACT or DESCEND."

**After:** input check green (the player taps LIGHT in the dark neighbour room and is alive 6 s later;
walking back brings the choice back). `rv_phone_after_power.luau`: LIGHT and SPRINT shown on 3 of 3
floors. That probe never taps, so its bot still dies, as it should.

## B3 — the run that never ended

**Cause.** `Facility.deathTime` returned `math.huge` for the exit, powered or not, and nothing else
ends a run.

**Reproduced** with `rv_stalemate2.luau`: in the exit with 0 held and 2 of 3 fuses inserted, battery
drained to 0, the nearest missing fuse room 2 rooms away. After 600 s: phase `floor`, exposure max 0.00,
7 other built rooms dark, the hint still "Find 3 fuses".

**Failing tests first**, red on the untouched source:
- `tests/Facility.spec.luau` invariant 9, restated: a POWERED exit never dies; an unpowered exit dies
  at `hold + (2 + maxD + 1) x step` (wrong on **15 000 of 15 000** floors); every other room is dark
  before it. `tests/Config.spec.luau` pins `Front.ExitExtraRings = 1`.
- `check_facilitynightmare_desktop.luau` section E: steered by the debug oracle to the nearest fuse and
  then to the lift, battery spent with F, then wait. The run must end by itself, as a dark death, after
  every other built room is dark and the lift's own light has failed. Settled once. While the lift is
  lit, the hint must read "Find N more fuse(s)". Correction from the independent verifier: against the pre-review source this section cannot measure
  anything - it aborts at its own control, because E could not extract before the B1 fix. What does
  reproduce is B3 re-applied alone on the fixed code: Facility.spec invariant 9 and this section both fail.
  An earlier claim of "never ended, Find 3 fuses on 6530 samples" did not reproduce and is withdrawn.
- section C of the same file: standing in a POWERED lift to run clock 18 x step + 3 s (past any
  unpowered exit's death on a 4x4 floor), the light stays on and the choice stays up.

**Fix.** `Facility.deathTime(..., powered)` and `Config.Front.ExitExtraRings = 1`; the server passes
`run.powered`. A player who walks in with every fuse powers the lift in the same tick, before the
light is read, so honest play never meets a dark lift. The HUD hint counts the fuses still missing.

**After:** `rv_stalemate2.luau` ended by itself 9 s into the wait (the lift had already failed while
the battery drained). Desktop check section E, 6 consecutive runs: the dark took the player 57.1 /
109.9 / 75.9 / 83.9 / 89.5 / 134.7 s after they reached the lift.

**Deviation from DESIGN.md §2.2** ("the exit room's emergency light never fails"), recorded in CLAUDE.md.
Difficulty is unchanged (see the curve below).

## B4 — the figure inside the furniture

**Cause.** `spawnApparition` put the figure `inner - WallOffset` = 11 studs off centre on the far
wall with no look at `plan.props`. A far-wall prop reaches 9..13 studs off centre.

**Reproduced** with `rv_geometry.luau` (120 runs at 10.4 studs/s): 804 floors, 14 986 rooms, 707
apparitions, **73 inside a prop** (PropDesk 29, PropCrate 27, PropCabinet 14, two props 3), 0 inside
any other solid part. The reviewer measured 53 of 727.

**Failing test first:** `tests/Facility.spec.luau`, "the apparition stands in the room". The placement
now lives in one pure function, `Facility.apparition`, which the server builds from. The test was first
run against that function carrying the OLD rule, transcribed: **1910 of 20 717** spots (9.2%) put a limb
inside a prop. It checks every (room, neighbour) spot on 450 plans: no limb inside a prop, wall,
lintel, light or item; every limb inside the room; on the doorway's axis, facing it; exactly on
DESIGN.md's spot whenever nothing on the far wall crosses the line. In the walk, every figure the bot
meets is checked against the parts of its room in the workspace.

**Fix.** Where a prop on the far wall crosses the figure's 1.8-stud half-width, it stands 0.25 studs in
front of that prop, still on the axis. The server builds the six limbs from `spec.limbs`.

**After:** Facility.spec 0 of 20 717 spots (1918 of them with a prop across the line); the walk, 20 of
20 runs clean; `rv_geometry.luau` **0 of 720** apparitions inside a prop, 0 inside another solid part
(800 floors, 15 060 rooms, 0 items inside a solid part, 0 arrival hulls blocked).

---

## Mutation sweep

Driver: `fnm-rv1/mutate_rv1.py` in this session's scratchpad. For each mutation it restores the file from a
backup, requires the old text exactly once, applies it, and requires the file's sha256 to change. It then
rebuilds the bundle and **proves the mutation reached it**: the mutated file's whole text is in
`build/facility-nightmare.luau` and the clean file's text is not. It runs all 14 gates (9 specs, 4 emulator
checks, the walk), restores, and requires the file's sha256 to equal the backup's. A gate with no summary line
counts as KILLED. At the end all 12 `src/` files were compared with the backup and matched, and `sha256sum -c`
against the pre-sweep manifest reported OK for all 12.

| # | mutation | result, and the gate(s) that killed it |
|---|---|---|
| R1 | A3: sprint starts on a crumb again (the unfundable check deleted) | KILLED — Survival.spec (spam 24.00 vs ceiling 18.70; conservation excess 43.24 s; press on an empty bar sprints) |
| R2 | A3: an unfundable request walks but is not exhausted | KILLED — Survival.spec (held key sprinted 10 more ticks under jitter) |
| M21' | old M21 on its new anchor: exhaustion removed | KILLED — Survival.spec, input |
| N5 | old N5: Survival ignores a fresh press | KILLED — Survival.spec, input |
| R3 | A2: a claim that returns after leaving is not released | KILLED — check (K3, 6 failures) |
| R4 | A2: the release clears a lock it does not own | KILLED — check (K3: another server's lock cleared) |
| R5 | A1: item offsets drawn from the loot stream again | KILLED — Facility.spec (5, 5b) |
| R6 | A1: props drawn from one stream shared across rooms | KILLED — Facility.spec (5b: 15 667 props moved) |
| R7 | A1: the room seed ignores the room | KILLED — Facility.spec (5b: 90 thin bins; shared offsets) |
| R8 | A1: no finaliser, room seeds a constant apart | KILLED — Facility.spec (5b: 80 thin bins) |
| R9 | B4: the figure ignores props | KILLED — Facility.spec (1910 spots), walk |
| R10 | B4: the figure's width is not counted | KILLED — Facility.spec (858 spots) |
| R11 | B4: an overhead prop (the pipe run) also moves the figure | SURVIVED — **equivalent**: the pipe run is 1 stud deep, so "in front of it" is 11.25 studs, behind the 11-stud spot, and `min()` never moves the figure. The guard was deleted; R9, R10, R12 and the GAP control were re-run on the new code (below) |
| R12 | B4: the server stands the figure 3 studs further back | KILLED — walk (figure inside `Wall-x` / props). This kill needs at least one apparition in the walk; the final walk met 7, and the two sweep runs met 9 and 7 |
| R13 | B3: the server never tells the front the lift is powered | KILLED — desktop (the powered lift went dark and killed the player) |
| R14 | B3: the unpowered exit never dies | KILLED — Facility.spec, desktop (the run never ended) |
| R15 | B3: the exit dies with the farthest ring, not after it | KILLED — Facility.spec |
| R16 | B3: the hint counts every fuse again | KILLED — desktop (942 wrong hint samples) |
| R17 | B2: `atLift` true anywhere once powered | KILLED — input |
| R18 | B2: the HUD ignores `atLift` | KILLED — input |
| R19 | B2: the lift hint outranks the dark hint | KILLED — input |
| R20 | B1: EXTRACT never Modal | KILLED — desktop |
| R21 | B1: EXTRACT always Modal (breaks mouse-look) | KILLED — desktop |
| R22 | B1: CLOSE never Modal | KILLED — desktop |
| R23 | B1: E/Q choose while the choice is hidden | KILLED — desktop |
| R24 | B1: E and Q swapped | KILLED — desktop |
| R25 | B1: the desktop EXTRACT label names no key | KILLED — desktop |
| R26 | B1: a phone's EXTRACT label names a key | KILLED — input |
| R27 | B1: `CameraMinZoomDistance` never set | KILLED — desktop |
| CONTROL | room wall colour 150 -> 151 | SURVIVED (as it must) |
| CONTROL | break-room minimum zoom 6 -> 7 | SURVIVED (as it must) |
| CONTROL | figure stands 0.3 in front of a prop, not 0.25 | SURVIVED (as it must) |
| CONTROL | room-seed multiplier 2654435761 -> 2654435769 | SURVIVED (as it must: the tests pin independence, not a constant) |

Re-run after deleting R11's guard, same driver: R9 KILLED (Facility.spec 1910, walk), R10 KILLED
(Facility.spec 858), R12 KILLED (walk), CONTROL GAP 0.25 -> 0.3 SURVIVED; `src/` byte-identical afterwards.
Re-run after two spec assertions were made to FAIL cleanly instead of raising on the pre-review source
(below): R7 KILLED (90 thin bins), R8 KILLED (80), CONTROL room-seed multiplier SURVIVED; `src/`
byte-identical, 12 of 12 files OK against the manifest.

**Totals:** 33 mutations, 28 KILLED, 1 SURVIVED (equivalent, and its line deleted), 4 controls SURVIVED.
Every mutation was confirmed in the bundle, and every restore was confirmed by sha256.

## Gates on the final code

Bundle rebuilt first. Every count below is from `gates_final2.txt` in the scratchpad.

```
Config.spec      106 passed, 0 failed   (was 104)
Economy.spec      93 passed, 0 failed
Facility.spec     84 passed, 0 failed   (was 66; M1's three rows still reproduce exactly)
Survival.spec     74 passed, 0 failed   (was 70)
Trust.spec        53 passed, 0 failed
Responsive.spec   70 passed, 0 failed
Rng.spec          37 passed, 0 failed
MazeGen.spec       3 passed, 0 failed
Fx.spec           26 passed, 0 failed
check_facilitynightmare          203 passed, 0 failed   (was 194)
check_facilitynightmare_input    116 passed, 0 failed   (was 99)
check_facilitynightmare_desktop   47 passed, 0 failed   (new)
check_facilitynightmare_hud      PASS — 10 viewports x 3 modes, overlap check on
walk                              70 passed, 0 failed   (the count varies with depth)
luau-compile --binary            12 of 12 clean
luau-analyze                     11 of 12 clean; MazeGen.luau 10 (verbatim copy, unchanged)
rojo build                       builds
```

**Stability**, 20 consecutive runs each on different floors (before the two spec-only edits below, which
touch no emulator gate): check 20 of 20 green, input 20 of 20, desktop 20 of 20, walk 20 of 20.

**The final tests against the untouched source** (a scratch copy of the pre-review `src/`):
- Config.spec 2 failed, Survival.spec 2, Facility.spec 9, check 6, input 6, desktop 15;
- the HUD check PASS (it asserts nothing this pass changed);
- the walk 0 failed: that run met 3 apparitions and none happened to stand in a prop, which at 73 in 707
  is the likely outcome for 3.

Two spec assertions (Config.spec's minimum zoom, Facility.spec's `roomSeed`) first raised on the
pre-review source instead of failing. They were rewritten to fail cleanly, and that changed no pass count on
the final code except Facility.spec's new control (+1).

## The walk, final code

`tests/walk.luau`, played through the headless bot (a separate run from the gate run above, which counted 70
assertions):
- **Join:** landed on HubSpawn at (-24.00, 3.51, 0.00); 2.3 s from spawn to the ride.
- **Loop 1, 16 studs/s:** sublevels 1 / 2 / 3 powered after 44.0 / 35.5 / 47.4 s. EXTRACT banked exactly 45
  (10 + 15 + 20). Deep Cell rank 1 bought, 45 -> 20 Essence.
- **Loop 2, 10.4 studs/s:**
  - sublevels 1-5 powered after 62.0 / 40.7 / 60.7 / 104.2 / 119.0 s;
  - sublevel 4: 42.7 s in dark rooms, battery 55 -> 26.7; sublevel 5: 26.7 -> 6.6;
  - on sublevel 6 the dark took the player after 109.2 s, and they kept 25 of 100.
- **Profile:** essence 45, earned 70, runs 2, extractions 1, deepest 5.
- **Worst Part budget:** room 17 of 20, door leaves 28 of 40, zone 394 of 600 with 25 rooms built.
- **Apparitions:** 7, none inside a wall, prop or item. 671.8 s of virtual time.

## Difficulty, before and after (the fixes move props and item offsets and add a dark lift)

`tests/curve.luau`, perk-less, 400 runs at 10.4 studs/s, fixed code and untouched pre-review code run side by
side:

| | P(1) | P(2) | P(3) | P(4) | P(5) | P(6) | P(8) | P(10) | p50 powered | run p50 |
|---|---|---|---|---|---|---|---|---|---|---|
| fixed | 0.96 | 0.93 | 0.89 | 0.66 | 0.45 | 0.29 | 0.10 | 0.01 | 4 | 464 s |
| pre-review | 0.97 | 0.94 | 0.89 | 0.63 | 0.44 | 0.29 | 0.10 | 0.01 | 4 | 453 s |

At 16 studs/s (200 runs, fixed code): P(4 / 6 / 8 / 10 / 12) = 0.96 / 0.94 / 0.93 / 0.83 / 0.73, against the
second pass's 0.97 / 0.92 / 0.89 / 0.82 / 0.73. There is no difference beyond sampling noise. 0 scheduler
errors, 0 warnings.

## Still open

Needs Studio. Headless can only prove the flags are set, never what the engine does with them:
1. **B1:** does a visible Modal EXTRACT free a LockFirstPerson cursor on PC, and re-lock it when the panel
   closes? Do E and Q reach the HUD on the floor? Back in the break room, does `CameraMinZoomDistance = 6`
   put the camera behind the character with a free cursor, and is 6 comfortable in a 14-stud room?
2. **B3:** does a player understand why the unpowered lift went dark, and is one ring enough warning?
   `ExitExtraRings = 1` is arithmetic, not a measurement against people.
3. **B4:** does a figure standing in front of a desk or crate still read as a figure?
4. **B2:** does the choice panel vanishing and returning as a phone player crosses the lift's doorway feel
   right?

Not closed by this pass, and not among the seven findings:
5. **Gamepad players** still have no binding for EXTRACT, DESCEND, BUY or PERKS; they reach them only through
   Roblox's UI selection mode.
6. **Engine seeds.** The layout, loot and decor seeds are three consecutive draws from one `Random.new()`.
   A1's fix makes the decor seed recoverable from a prop, and DESIGN.md already accepts that the layout
   seed can be brute-forced offline. Whether two outputs of Roblox's `Random` could then predict the one
   between them depends on an engine algorithm this repo has not measured. Not attempted; noted so the next
   review can decide.
7. **`releaseLock` is best-effort.** If that one write itself errors, the lock stands until it expires (45 s)
   and the join retries on autosave. Not tested with a failing store.
8. **A phone player cannot switch off a flashlight left on in the powered lift:** LIGHT is hidden under the
   modal. The lift is lit, so this only costs battery until the choice; arrival on the next sublevel clears
   it. Unchanged by this pass.
9. **R12's kill depends on an apparition appearing in the walk.** It did in every walk run this pass (7 to
   9), but no gate forces one.
10. **Reviewer A's "not reproduced" items, still Studio-only:** an exploiter teleporting into another
    player's zone to body-block, and DataStore write queueing on one key.
11. **DESIGN.md itself was not edited.** Its §2.2, §2.6, §4.4, §4.5 and §12 now differ from the code as
    listed in CLAUDE.md's State section.

## Files changed

`facility-nightmare/`
- `src/shared/Survival.luau` (+10 -1): a sprint tick is paid in full.
- `src/shared/Facility.luau` (+105 -12): `roomSeed` and per-room dressing streams; `deathTime(..., powered)`;
  `apparition`.
- `src/shared/Config.luau` (+8): `Front.ExitExtraRings`, `Hub.CameraMinZoomDistance`.
- `src/server/Main.server.luau` (+45 -18): `releaseLock`, `atLift`, `run.powered` into the front,
  `CameraMinZoomDistance`, and the apparition built from `Facility.apparition`.
- `src/client/Hud.client.luau` (+34 -16): the choice driven by `atLift`, Modal, E/Q, key labels, hint order
  and count.
- `tests/Survival.spec.luau` (+74), `tests/Facility.spec.luau` (+229 -14), `tests/Config.spec.luau` (+2),
  `tests/walk.luau` (+32).
- `CLAUDE.md` (State, deviations, invariants, traps 19-25, curve, Needs Studio, gate counts), `README.md`
  (loop, controls, curve numbers), `REVIEW-1.md` (this file).

`robloxemu/`
- `check_facilitynightmare.luau` (+82 -1): section K3 and the `atLift` key.
- `check_facilitynightmare_input.luau` (+61): B2 and the phone labels and hint.
- `check_facilitynightmare_desktop.luau` (new, 349 lines).
- `build/facility-nightmare.luau` (rebuilt).
