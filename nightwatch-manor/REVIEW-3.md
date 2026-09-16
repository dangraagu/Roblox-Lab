# Nightwatch Manor — resolving REVIEW-2

**Verdict on the code: every finding in REVIEW-2's open list and every regression it blamed on the
previous round is closed, each with its own measurement and its own mutation. The game has NOT run
in Roblox, and that is the one thing on REVIEW-2's list I could not close.**

Third pass, 2026-09-10. Read alongside `REVIEW.md` (first pass) and `REVIEW-2.md` (second pass,
BLOCK). Numbers below are mine, from commands I ran; where a number of REVIEW-2's is quoted it is
because I reproduced it first and then moved it.

Reproduce anything here with:

```
luau tests/*.spec.luau
cd tests && py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
luau check_walk.luau ; luau check_world.luau
luau check_boot_guard.luau -a control|fraction|walkspeed|saturated
py -3 tests/_mutate.py                       # 23 mutations + 4 controls, from the repo root
```

`robloxemu/` is shared and was NOT modified — I only read it. The three new headless gates
therefore live in `nightwatch-manor/tests/` and boot the same server through the same harness.
`robloxemu/check_nightwatch.luau` still carries the weak assertions REVIEW-2 named; the mutations
it could not kill are now killed by `tests/check_world.luau` instead. Whoever owns `robloxemu/`
may want to fold the two together.

---

## Where the gates stand

| gate | before | after |
|---|---|---|
| `tests/*.spec.luau` | 479 assertions | **470 assertions, 0 failed** |
| `robloxemu/check_nightwatch.luau` | 113 / 0 | 113 / 0 (untouched) |
| `robloxemu/check_nightwatch_hud.luau` | PASS | PASS |
| `tests/check_walk.luau` | — | **62 / 0** — walks the built world |
| `tests/check_world.luau` | — | **38 / 0** — the four untested guards |
| `tests/check_boot_guard.luau` | — | **2 / 4 / 4 / 4** over four hostile boots |
| mutation sweep | 5 survivors named in REVIEW-2 | **23 killed, 0 survived; 4 controls survived** |

The spec total went DOWN, from 479 to 470, and that is deliberate. `Chase.spec` had sixty
assertions of the form "night N: the exit is reachable from the foyer" — one per night, nights
1-60. They are now one assertion counting failures over nights 1-**500**. Eight times the coverage,
fifty-nine fewer ticks. Reading the count as a measure of the suite is the habit that let a
Nightwatcher nobody could outrun ship green.

`luau-compile --binary` is clean on all 8 sources. `luau-analyze` is clean apart from Roblox
global/type noise — including in `tests/`, where the pre-existing `FunctionUnused 'approx'` that
REVIEW-2 recorded is also gone.

---

## Open list (6) — five closed, one not

### 1. CLOSED — "the headline is certified by a player that walks through walls"

REVIEW-2 was right and understated it. I rebuilt the wall model from `buildWall` (1-stud slabs on
every shared plane, `DoorWidth` gap in the middle of a linked edge) and re-ran REVIEW-2's own bot:

| bot | caught, ambushed, nights 1-20 x2 = 40 |
|---|---|
| the shipped bot (no collision) | **0 / 40** |
| same bot, a POINT that cannot cross a wall | **5 / 40** — n6@2.2s, n19@1.8s, n22@2.2s, n29@1.8s, n31@1.8s |
| same bot, a 2-stud-wide BODY | **19 / 40** |

The middle row reproduces REVIEW-2's finding exactly (they reported 5/40 at 1.6-2.0s in rooms of
degree 2 and 3). The bottom row is the one that matters: a Roblox character is about four studs
across, so modelling the player as a point understates the problem by a factor of four.

Two things were wrong, and both are fixed.

**The test was measuring a bot, so the bot was replaced.** `tests/Chase.spec.luau`'s player now has
a capsule body of radius 2, cannot enter a wall, slides on one axis when the other is blocked, and
threads a doorway by aiming at the DOORWAY rather than at the room behind it. It is committed:
it picks a destination room and does not change its mind halfway through the door, because a bot
that re-decides every tick parks in the doorway it is standing in and waits to be collected (it
did — 40/40 caught, and that number is a bot artefact too, in the other direction). It keeps the
old bot's one piece of sense: it will not cross a line that passes within arm's length of the
Nightwatcher.

There is now a **CONTROL on the collision model itself** — the middle of a room is walkable, the
middle of a doorway is walkable, the jamb one `DoorWidth` to the side is NOT, and the outside wall
of the manor is NOT. Without it a `blocked()` that always answered "walkable" restores the old
wall-walking bot and every assertion in the file goes green again on a game nobody can play.
Verified: stubbing `blocked` to `return false` fails 2 of those 4 controls.

**The game was wrong too, and this is the real finding underneath REVIEW-2's.** `Manor.luau`'s own
comment claimed the chase "keeps it going through doorways instead of through walls". It did not.
The server aimed the hunting Nightwatcher at the CENTRE of the next room on the path, and that line
is wall-safe only when it starts from a room centre — which, one hunt tick in, it never does,
because the watcher has been walking at a player. So the hunter cut corners through 1 stud of Brick
while the player had to find a 10-stud hole. **The two of them were racing on different maps, and
the shorter map was the monster's.**

`Manor.chaseStep(cfg, plan, fromId, x, z, toId)` is new, pure, and steers at the doorway until the
pursuer is standing in the gap, then at the room beyond. Measured in `Manor.spec`: 182 room-to-room
walks on night 9, starting from a room CORNER, **0 wall crossings, 0 that never arrived**. Restore
the old behaviour and it is 182 crossings out of 182.

With both fixed, the wall-respecting, door-aware, committed player ambushed in the Nightwatcher's
face is caught **0 of 40** nights (1/40 with the fix to the test but not to the game — night 20 at
65.5s, in a degree-1 room).

The clamp deciding "close enough to the doorway" is `DoorWidth * 0.25`, not a bare constant, and
it is load-bearing rather than tidy: `Manor.roomAtWorld` resolves a point exactly on a shared plane
to the HIGHER cell, so a pursuer that arrives at a doorway heading toward the LOWER cell is still
"in" the room it came from, still aiming at the doorway it is standing on, zero studs away, and
never moves again. That deadlock is real; I hit it while building this.

**And the retune did not make the game safe.** A player who walks the greedy full-clear route
legally, through doorways, and pays the Nightwatcher no attention at all is caught on **19 of 30**
nights (11 clears). That is a new assertion in `Chase.spec` — `caught >= 10` of 30 — and it is the
one that fails if the hunter is ever nerfed into furniture. A player who beelines for the exit and
ignores it gets out on 25 of 30 and is caught on 5.

### 2. CLOSED — the `prof.loaded` gate on ENTERING A NIGHT was untested (M11 SURVIVED)

`tests/check_world.luau` joins a player whose stored profile is **night 9, 900 relics**, wraps
`UpdateAsync` so the join blocks for a second, and presses the manor door inside that window.

Asserted: no `Manor` is built, no misleading State is pushed, the DENIED notice says the safehouse
is still opening, and after the profile lands the run is still in DAY and the *same press* now
builds a manor **on night 9**.

Mutation `if not prof.loaded then` -> `if false then`: **KILLED**, 3 assertions —
`pressing the manor door before the profile lands builds NO manor -> got Manor, want nil`.

### 3. CLOSED — the `prof.loaded` gate on BUYING passed for an unrelated reason (M13 SURVIVED)

REVIEW-2 diagnosed this precisely: the default profile's stash is 0, so `Upgrades.canBuy` refuses
anyway, and both paths emit a DENIED and build nothing. The two outcomes are identical in
everything the old test looked at.

They are not identical in **what the player is told**, and that difference is reachable on the
shipped config with nothing retuned. With the gate: *"Still opening your safehouse — one moment."*
Without it, a player with 900 relics banked is told *"You need 40 relics for Safehouse Lanterns."*
— which is a lie, in the one moment the game most needs to be trusted.

`check_world.luau` asserts the text: it must contain "Still opening" and must NOT contain
"You need".

Mutation `if not p.loaded then` -> `if false then`: **KILLED**, 2 assertions —
`...what it says is that the safehouse is still opening, not that you are poor (said: "You need 40 relics for Safehouse Lanterns.")`.

I deliberately did NOT reach for the obvious alternative — raising `Config.Night.StartStash` in the
fixture so the default profile can afford something. It would have worked, and it would have been a
test that only fails under a config nobody ships.

### 4. CLOSED — the origin plate and the origin SpawnLocation each covered the other's absence

The old assertions were "ANY BasePart within 500 studs of the origin" and "ANY SpawnLocation
anywhere in the workspace". `check_world.luau` now pins them **to each other**: both within 30
studs of the origin, the spawn horizontally inside the plate's footprint, and the spawn's bottom
face resting on the plate's top face (within -1 / +2 studs).

- Plate to y=-4000: **KILLED**, 2 assertions (`the plate is AT the world origin ... (0.0, -4000.0, 0.0)`; `spawn bottom 1.00 vs plate top -3999.00`).
- Spawn to y=-4000: **KILLED**, 2 assertions (`spawn bottom -4000.50 vs plate top 1.00`).

### 5. CLOSED — `spawnPad.Enabled` was untested

`check_world.luau` asserts `spawnPad.Enabled == true` (and the same for `OriginSpawn`), and
separately that the pad IS the player's `RespawnLocation`. Asserting `== true` also catches the
line being deleted, which returns nil.

Mutation `spawnPad.Enabled = true` -> `false`: **KILLED** —
`...and is ENABLED ... -> got false, want true`.

### 6. NOT CLOSED — nothing has run in Roblox

I have no Studio session and did not open one. What I did instead is make the headless walk model
the parts, which moves the line but does not erase it.

`tests/check_walk.luau` does not read `Manor.plan` — the plan is what the server *intended*. It
reads the workspace: rooms from `Floor` parts, connectivity from which shared edges have no `Wall*`
part across them at chest height, and obstacles from **every solid part in the torso band**, which
is the bookshelves, the dining table, the chairs, the pews, the barrels, the pedestals and the exit
slab as well as the walls. It routes over a two-stud four-connected lattice, walks the character by
hand at `WalkSpeed`, and fires a ProximityPrompt only from inside its real `MaxActivationDistance`.

So the class REVIEW-2 called unmodelled — "furniture the player can get stuck on, a pedestal
clipping a bookshelf" — **is now modelled and is caught**: growing the dining table from 8x22 to
34x34 fails the gate with `NO WALKABLE ROUTE exists in the built world`.

What is still only visible in Studio, stated plainly: gravity and falling, step height and stairs,
character physics against rotated parts (the nursery's rocking horse is rotated and is modelled
here as its unrotated box), Raycast, lighting — whether the manor is dark enough to frighten and
light enough to navigate — camera, and every question of feel, including the one this whole retune
raises: whether a Nightwatcher you can outrun is still frightening.

**Two things I got wrong while building that walk, recorded because both are the exact failure
this repo keeps repeating.** First: I hard-coded the torso band as an absolute height, `Y` 1.6 to
4.4, while every zone in this game sits about a hundred studs up. The band matched nothing, the
"collision" model collected zero obstacles, and the walk passed — *and so did three control
mutations, including one that sealed every room in the manor*. A green walk with no collision looks
exactly like a green walk. Second: the route was planned with the same radius the walk used, so a
path could be laid tangent to an obstacle; the half-stud of drift that following a polyline costs
then put the character INSIDE the box, where every direction is blocked, and it stood on the corner
of a dining chair until the night ran out. Planning now keeps 0.6 studs more clearance than walking
does.

---

## Broken by the previous round (6) — all six closed

### 1. CLOSED — the fourth boot guard could not fire for three of the four causes it named

REVIEW-2 was right about the mechanism: the guard swept `Watcher.speed`, which has already been
clamped to `MaxSpeedFraction * WalkSpeed` by the time it returns, so `worst >= walk` was
unreachable for any fraction below 1 — while the error text told the reader to lower `BaseSpeed` /
`SpeedPerDread` / `HuntSpeedMul`.

The fix is a split, because the two things really are different severities:

- `Watcher.speedAudit(cfg)` — **FATAL**. `WalkSpeed` must be a positive number; `MaxSpeedFraction`
  must be positive and below 1. The server `error()`s. Its message now names only what it can
  actually be complaining about.
- `Watcher.ceilingBinds(cfg)` — **WARNING**. The raw, unclamped curve `(BaseSpeed + SpeedPerDread)
  * HuntSpeedMul` must stay under the ceiling. When it does not, the clamp stops being a guard rail
  and becomes the operating point: the watcher sits at exactly 13.00 studs/s for most of the night
  and the three knobs underneath stop changing anything. That is REVIEW-2's M4 (`SpeedPerDread`
  2.4 -> 12) and it is now loud. The server `warn()`s, and every headless gate asserts the server
  boots with **zero** warnings, so it is still caught by something that fails a build.

Why a warning and not an error: `HuntSpeedMul` 1.45 and `BaseSpeed` 9 / `SpeedPerDread` 3 are legal
retunes that CLAUDE.md explicitly promises are safe, and both saturate the ceiling. Making
saturation fatal would have made the doc's promise false in the other direction. Both are asserted
as controls in `Watcher.spec`.

Shipped values, for the record: raw curve **12.48**, ceiling **13.00** (0.65 x 20). It does not
bind, and `ceilingBinds(Config)` is asserted false.

The guard being *reachable* is not the same as the server *acting on it*, and REVIEW-2's M17 —
`if worst >= walk then` -> `... and false then` — is exactly that difference. Nothing that runs
inside one process can catch it, so `tests/check_boot_guard.luau` patches Config's **source text**
and boots the server four times:

| case | expectation | result |
|---|---|---|
| `control` | boots, zero warnings | 2 passed |
| `fraction` (`MaxSpeedFraction` 0.65 -> 3.0) | REFUSES, names MaxSpeedFraction, leaves no half-built zone | 4 passed |
| `walkspeed` (`WalkSpeed` 20 -> 0) | REFUSES, names WalkSpeed | 4 passed |
| `saturated` (`SpeedPerDread` 2.4 -> 12) | BOOTS, and warns, naming SpeedPerDread and the ceiling | 4 passed |

Turning the guard back into decoration (`if not ok and false then`) fails `fraction` and
`walkspeed`, 3 assertions each. Turning the warning off fails `saturated`, 3 assertions.

### 2. CLOSED — `Config.Manor.MaxRooms = 18` was exceeded on 96 of 120 nights

Reproduced over the full range: **468 of nights 1-500 over the cap, largest manor 23**.

`MaxRooms` now means what its name says — the cap on the TOTAL, repair rooms included — and
`Manor.roomCount` stops the growth target `MaxRepairRooms` short of it so the arithmetic closes.
Over nights 1-500: **largest manor 18 rooms (night 18), 0 nights over MaxRooms**.

The cost is honest and worth stating: late-night manors shrink from 23 rooms to 18, which is also
about 47 fewer BaseParts per player per night. Night 1 is unchanged at 10 rooms against a
`BaseRooms` of 6 — that gap is the dead-end repair pass and is inherent, which is why `roomCount`
is documented as a target and `Manor.spec` asserts a band.

I also **deleted** a guard rather than testing it. `plan` had a second clamp,
`math.min(target + MaxRepairRooms, MaxRooms)`. With the target already clamped it is unreachable
for any config satisfying `MaxRooms >= MaxRepairRooms + 2` — I could not construct a legal config
that reached it, and a mutation removing it survived every gate. So it went, and the invariant it
was standing in for is asserted in `Manor.spec` instead. Breaking that invariant
(`MaxRepairRooms` 5 -> 17) is **KILLED** by four gates.

**A caveat on my own sweep, because it is the trap the repo has hit before.** An earlier run of
this mutation reported KILLED, and the kill was spurious: `Manor.spec` was ALREADY red at baseline
from a control assertion of mine that was simply wrong (`largest 4 of 6`, asserting the repair pass
pressed against a cap it never reaches from a 2-room manor). A sweep with a red baseline reports
every mutation as killed. The four `C*` controls are what caught it.

### 3. CLOSED — the ExitDoor stood in a live doorway on 51% of nights

Reproduced over the full range: with the hard-coded `+Z` face, the exit door stands in a live
doorway on **249 of nights 1-500** (49.8%).

`Manor.exitFace(cfg, plan)` is new and pure: prefer a face with nothing behind it (the outside of
the manor, which is where a servants' exit belongs), then a shared wall with no doorway in it, and
only as a last resort the final direction. Over nights 1-500: **0 nights in a doorway, 499 on the
manor's outer wall, 1 on an internal solid wall, 0 last-resort**. The server builds the slab on
that face, sized along it (`(1.2, 12, DoorWidth)` on an X face, `(DoorWidth, 12, 1.2)` on a Z one)
rather than always broadside to Z.

`check_world.luau` asserts it in the BUILT world too: there must be a `Wall*` part covering the
exact point where a doorway's gap would be, behind the door. Reverting the server to `+Z`:
**KILLED**.

Note that `check_walk.luau` does NOT catch this one — nights 1, 2 and 3 happen to have `+Z` as an
outer face — which is why the plan-level and world-level assertions both exist.

### 4. CLOSED — CLAUDE.md still asserted the pre-fix claim

`notDone` item 6 said "Hub level grows the manor, but nothing is locked behind it". The first
clause has been false since the determinism fix. Rewritten to say that the safehouse now reaches
the manor generator not at all, with a line recording that the sentence outlived the fix.

### 5. CLOSED — "renaming a room kind" was listed as a control and was not one

`Manor.spec` asserted `Manor.kindById(Config, "library").name == "Library"` — the display name,
which is copy. The assertion now checks the `id`, which is what every dispatch table is keyed on.
Re-verified by running the mutation through every gate: `name = "Library"` -> `"Reading Room"`
now **SURVIVES**, as the doc promises. So do the other four controls (relic tier name, upgrade
blurb, upgrade name, the Nightwatcher's torso colour).

### 6. RECORDED, not a defect — the early game is close to free, and layouts are global

Still true, and re-measured after the retune. Crossing the manor to the exit costs at worst
**12.7% of the night** (night 67) over nights 1-500. A player who walks straight out reaches the
exit on **30 of 30** nights when the catch test is off — that is the navigability assertion — and
on 25 of 30 with it on.

Against that: ignoring the Nightwatcher costs the haul on **19 of 30** nights, so the constraint is
real and it is the thing making the loop a game rather than a walk. And `Manor.seedFor` still folds
only `WorldSeed` and the night, so one published route for night 1 is correct for everybody. That
is the accepted trade for a comparable best-night number, and it is documented as such.

---

## What the headless walk actually showed

`tests/check_walk.luau`, three nights, 537 server ticks (53.7 s of simulated night), 1050 studs
walked. Verbatim:

```
  spawned 3.4 studs from the spawn pad, at (3000, 104, 20)
  the spawn pad -> the manor door: 1 waypoints
  pressed ENTER THE MANOR from 8.4 studs (reach 12)
  the manor that got built: 10 rooms
  ...with 13 doorways you can actually walk through (1.30 per room)
  the foyer -> the nearest relic: 3 waypoints
  pressed TAKE from 7.1 studs (reach 12)
  the relic -> the Servants' Exit: 8 waypoints
  at the exit after 12.9s of night, dread 0.05, 1 relic(s) carried
  pressed ESCAPE from 7.6 studs (reach 12)
  loop 1 took 129 ticks (12.9 s of night) and 252 studs of walking
  ...
  FULL CLEAR on night 2: took 4 of 4 relics in 14.5 s of night -> OUT with the haul (dread 0.00)
  ...
  night 3: hunting on 38 ticks, watcher crossed 4 room boundaries; 0 of 1989 sampled points were inside a wall
```

Read that as: the character lands on its own spawn pad and not on a roof or in the void; it walks
to the manor door and the prompt is in reach; the door builds a manor whose 13 doorways are holes
you can put a body through, not just links in a table; every one of the 4 relics and the exit are
reachable on foot from where the night drops you; taking one and leaving banks it and advances the
night; a full clear of all four and out works; and when the Nightwatcher is provoked into a hunt
and followed for four room boundaries, none of the 1989 sampled points along its path is inside a
wall.

The night-1 loop costs 12.9 s of a 210 s night. That is the number behind "the early game is close
to free", from the world rather than from the model.

---

## Mutation table

`py -3 tests/_mutate.py` — **23 mutations, 23 KILLED; 4 controls, 4 SURVIVED**; all four tracked
sources sha256-match their baseline afterwards (`Config b29d44786796, Manor baf89db39215, Watcher
f08df48e3a12, Main.server b95d3c60e784`). The patcher refuses on a pattern miss.

| id | mutation | result | killed by |
|---|---|---|---|
| C1 | room kind `name` "Library" -> "Reading Room" | SURVIVE | — |
| C2 | relic tier `name` renamed | SURVIVE | — |
| C3 | upgrade `blurb` rewritten | SURVIVE | — |
| C4 | the Nightwatcher's torso recoloured | SURVIVE | — |
| M1 | `SightRange` 55 -> 2000 | KILL | Chase.spec |
| M2 | `MaxSpeedFraction` 0.65 -> 3.0 | KILL | Chase, Watcher, world, walk, boot_guard x3, robloxemu |
| M3 | the ceiling deleted from `Watcher.speed` | KILL | Chase.spec |
| M4 | `HuntSpeedMul` 1.2 -> 5.0 | KILL | Watcher, world, walk, boot_guard[control], robloxemu |
| M5 | `WalkSpeed` 20 -> 16 | KILL | Chase, Watcher, world, walk, boot_guard x2, robloxemu |
| M6 | `ExtraDoorChance` 0.75 -> 0.05 | KILL | Chase, Manor, walk |
| M7 | `MaxRepairRooms` 5 -> 1 | KILL | Chase, walk |
| M8 | `MaxRepairRooms` 5 -> 17 (breaks the cap invariant) | KILL | Chase, Manor, walk, robloxemu |
| M9 | growth target clamps AT `MaxRooms` again | KILL | Manor.spec |
| M10 | `chaseStep` back to the diagonal | KILL | Manor.spec (182/182 crossings) |
| M11 | the SERVER ignores `chaseStep` | KILL | check_walk |
| M12 | ExitDoor back on the hard-coded +Z face | KILL | check_world |
| M13 | `exitFace` stops preferring an outer wall | KILL | Manor.spec |
| M14 | the fatal boot guard turned into decoration | KILL | boot_guard[fraction], [walkspeed] |
| M15 | the ceiling warning turned into decoration | KILL | boot_guard[saturated] |
| M16 | `prof.loaded` gate on entering a night off | KILL | check_world |
| M17 | `prof.loaded` gate on buying off | KILL | check_world |
| M18 | OriginPlate sunk to y=-4000 | KILL | check_world |
| M19 | OriginSpawn sunk to y=-4000 | KILL | check_world |
| M20 | `spawnPad.Enabled = false` | KILL | check_world |
| M21 | no doorway is ever cut (every room sealed) | KILL | check_walk |
| M22 | the character is never placed on the spawn frame | KILL | check_walk, robloxemu |
| M23 | the dining table grown to fill its room | KILL | check_walk |

---

## What I could NOT close, and what I would look at next

1. **Roblox.** Item 6 of the open list. The walk now models wall and furniture collision, so the
   remaining gap is physics, lighting, camera and feel. It cannot be closed from here.
2. **`robloxemu/check_nightwatch.luau` still carries the weak assertions.** Lines 60-73 still say
   only "ANY BasePart near the origin" and "ANY SpawnLocation anywhere". I did not edit it because
   `robloxemu/` is not this game's directory. The mutations it cannot kill are killed by
   `tests/check_world.luau`, which boots the same server through the same harness — so the hole is
   covered, but it is covered in two places rather than fixed in one.
3. **A joining player's HUD is blank until the DataStore returns.** `pushState` is only called
   after `claimProfile`, so on a cold server the world is standing, the player can walk, and the
   HUD says nothing for the length of the round-trip. I left it alone deliberately: the obvious
   fix — push the default profile immediately — shows a night-9 player "NIGHT 1, 0 relics", which
   is precisely the confusion the two `prof.loaded` gates exist to prevent. It wants a third state
   ("loading"), which is a HUD change, not a one-liner. `check_world.luau` now pins the current
   behaviour so the choice is at least deliberate.
4. **`Chase.spec`'s player is still a bot.** It is a much better bot — it has a body, it respects
   walls, it threads doorways, it commits — but "anything it survives, a person survives" is an
   argument, not a proof. The honest form of the claim is the one the file now prints: an ambushed
   player who understands they are faster and runs is caught 0 of 40; a player who ignores the
   Nightwatcher entirely is caught 19 of 30.
5. **Balance beyond night ~60 is asserted structurally, not played.** Dead ends, circuits, exit
   reachability and crossing cost are swept over nights 1-500. Nobody has simulated a chase past
   night 20.
6. **The description still says "relics & cash"** and there is still one currency; there is still
   no audio, no jumpscare, no environmental puzzle and no unlock gate. All of that is REVIEW.md's
   and CLAUDE.md's list, untouched by this pass, and none of it is a correctness defect — but the
   store copy must not go out before the first two are settled.

## Addendum, 2026-09-10 — the frozen check's weak pair is fixed at the source, not covered twice

Open item 2 said the hole was "covered in two places rather than fixed in one". It is now fixed in
one. `robloxemu/check_nightwatch.luau` no longer asks for "ANY BasePart within 500 studs of the
origin" and "ANY SpawnLocation anywhere" — the pair where each object covered for the other's
absence. It now asks the same thing `tests/check_world.luau` asks: that `OriginSpawn` is at the
origin, inside `OriginPlate`'s footprint, resting on its top surface, and `Enabled`.

**`check_nightwatch.luau` reports 118 passed, 0 failed**, unchanged from before the edit — the new
assertions are satisfied by the shipped build.

| what was done to the game | check |
|---|---|
| M12: `OriginPlate` dropped to y = -4000, spawn kept | **116 / 2 — KILLED** |
| M15: `OriginSpawn` dropped to y = -4000, plate kept | **116 / 2 — KILLED** |
| M16: `sp.Enabled = true` → `false` | **117 / 1 — KILLED** |
| CONTROL: plate colour changed to magenta | 118 / 0 — correctly unnoticed |

One note worth keeping, because it nearly produced a false all-clear. M16 was first applied by
inserting `sp.Enabled = false` after `sp.CanCollide = true` — and the check stayed green. That was
not a weak assertion: the source sets `sp.Enabled = true` four lines further down, so the mutation
was a dead store and the built game was never disabled. Mutating the real assignment kills it.
A mutation that changes nothing proves nothing, and it reads exactly like a surviving mutation.

`src/server/Main.server.luau` restored and sha256-verified byte-identical after the sweep.
