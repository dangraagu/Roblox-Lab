# FACILITY: Endless Nightmare — design spec (v1)

**Status: built headless, reviewed and fixed (see REVIEW-1.md); not yet opened in Studio.** Nothing is
published and no universe exists. Written 2026-09-16.

**Built from:** `docs/game-radar/2026-09-14-roblox-game-radar.md` §1 (the concept brief), plus that
file's *What players want* and *Avoid solo* sections, plus the round-2 radar's rule that the threat
must be **environmental and scripted, with no chasing AI**
(`docs/game-radar/2026-09-06-roblox-game-radar-round2.md`, line 58).

**Repo lessons this spec is written against:** `docs/new-game-checklist.md`,
`robloxemu/SPAWN-ORDER.md`, `fork-tower/STUDIO.md`, `fork-tower/REVIEW-3.md` (the replication leak
and how it was closed), `anomaly-observatory/CLAUDE.md` ("ServerStorage, not the zone"),
`deep-vein/` (layout template), `nightwatch-manor/CLAUDE.md` (why a pursuer's speed is data) and
`vault-runners/` (a countdown derived from the level, and `Trace.luau`).

---

## 0. How to read the numbers in this file

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M1]..[M11]** | Measured by this spec's rig, `design-measure/` (Appendix A). Re-runnable. |
| **[REPO]** | Measured earlier in this repo, with the file named. |
| **[ARITH]** | Arithmetic from a measured or chosen number, shown inline. |
| **[DOC]** | Roblox documentation. **Not measured here.** |
| **[STUDIO]** | A starting value only Studio can confirm. It is on the §15 list. |

**What the rig models, and how it is biased.** The numbers come from a **model explorer**. It
generates a floor with the real `MazeGen` and walks it blind. It remembers every room perfectly and
explores the nearest unexplored doorway first. It picks up whatever it walks into, then walks to the
elevator. It turns the flashlight on in dark rooms and off in lit ones.

- **Optimistic:** perfect memory, no hesitation, perfect flashlight discipline.
- **Pessimistic:** it never sprints, and it never changes route to avoid the dark.

Human inefficiency is stood in for by walking the same explorer slower:

| speed (studs/s) | name used here |
|---|---|
| 16 | "perfect" |
| 12.8 | "medium" |
| 10.4 | "slow" |
| 8 / 6.4 | "very slow" |

These speeds are **proxies, not measured humans**. Every survival percentage below is a model
number, and §15 item 1 is the playtest that replaces them.

---

## 1. The core loop, in one paragraph

You spawn in a lit break room and walk into the service elevator, which drops you into
**Sublevel 1**. That floor was generated from scratch a moment ago: a grid of lab rooms that are
built one at a time, as you open their doors. The facility's power is failing. Starting at the
elevator you arrived in, the lights die **one ring of rooms at a time**, spreading outward through
the doorways like a tide. Each room flickers for two seconds before it goes dark.

- **Standing in a dark room with your flashlight off fills your exposure.** When it fills, the dark
  takes you.
- **The flashlight holds the dark off, but it drains a battery** that has to last the whole run.

Find the fuses, carry them to the freight elevator (always the room farthest from where you came
in), and it powers up. Then you choose:

- **EXTRACT:** bank every point of **Essence** this run has earned.
- **DESCEND:** go one sublevel deeper. The next floor pays more, and the dark comes faster.

If the dark takes you, the run is over (**permadeath**) and you keep a quarter of what you had
earned. Back in the break room, banked Essence buys **permanent perks**: a bigger battery, a longer
grace in the dark, more sprint, a once-per-run second wind, and a bigger share kept on death. Then
you go again, into a facility nobody has seen before.

### What changed from the brief, and why

- **The stalking monster is gone.** The brief asks for a PathfindingService stalker with a
  patrol/investigate/chase state machine. The round-2 radar says to cut the pursuer, and so do the
  *Avoid solo* list ("AI-heavy systems") and this repo's own history: nightwatch-manor's hunter was
  faster than the player through every green test. The threat is now **the blackout front**, the
  dark itself spreading room by room. It is scripted, deterministic, readable, testable from the CLI
  and needs no rig, animation or pathfinding.
- **It does not duplicate the sibling games.** Vault Runners' collapse kills on contact. Here the
  dark is survivable for exactly as long as your battery lasts, so the loop is resource management
  rather than a race. Nightwatch Manor has a pursuer, and Anomaly is spot-the-difference; this game
  has neither.

---

## 2. The rules of a sublevel

### 2.1 Rooms and doors

- **The floor is a square grid of rooms.** Each cell is a room with a floor, ceiling, four walls
  and a light, and neighbouring rooms connect through doorways (§4).
- **Only the rooms you have opened exist.** On arrival, only the entry room is built. A room is
  built the moment a door into it opens, and a door opens by itself when the server's **trusted
  position** (§9) comes within `DoorOpenRadius` of the doorway while standing in the adjacent room.
  There is no prompt to press. The Reddit horror asks in the round-2 radar explicitly reject
  "Hold E simulator" horror.
- **Doors stay open once opened.** Nothing closes behind you in v1 (door slams are cut, §16).
- **A door leaf is built with whichever of its two rooms is built first.** A door into an unbuilt
  room is therefore always present and closed, and never a hole into the void.

### 2.2 The blackout front

- **Every room except the exit has a death time.** Let `d(r)` be the doorway (BFS) distance from the
  entry room. Room `r` goes dark at `hold + (LeadSteps + d(r)) * step`, and starts flickering
  `FlickerSeconds` earlier. The exit room's emergency light never fails.
- **`step` is derived from the floor itself, never typed in** (the vault-runners 8b lesson). The
  server runs the model explorer (§0) on the generated plan and takes its completion time `Tmodel`.
  Then `step = max(CellSize / WalkSpeed, slack(k) * Tmodel / (maxD + LeadSteps))`, where `maxD` is
  the exit's BFS distance. With the guard rail not binding, the last non-exit room goes dark at
  exactly `hold + slack(k) * Tmodel`. **The whole floor is dark, bar the elevator, at `slack` times
  a perfect blind explorer's time.**
- **`slack(k) = 1 + (1 + (k - 1) / 4) ^ -1`.** That is 2.000 at sublevel 1, 1.571 at 4, 1.364 at 8,
  1.121 at 30 and 1.039 at 100 [M6]. It decays toward 1 and never arrives, so no sublevel is the
  last one that gets harder (the vault-runners 8d lesson).
- **`hold` is zero, except on a player's first-ever run** (`profile.runs == 0`). There, on
  sublevel 1 only, the front starts when the first fuse is picked up. See §13.
- **Run time is accumulated from `task.wait`'s return value**, never read off a wall clock. The
  emulator drives a virtual clock (the nightwatch-manor lesson), so a wall clock would freeze the
  front in every headless check.
- **The rule is public, and nothing about it is secret.** What must never reach a client is the
  plan it is applied to: `d(r)` for rooms not yet built, the exit's cell, and `step` and `hold` as
  numbers (§7).
- **The HUD shows no power timer.** Rooms dying behind you *are* the timer. A "power %" bar would
  also hand over `maxD * step`, which a player could otherwise only estimate.

### 2.3 Flashlight, battery, exposure, sprint

The server ticks every `ServerTickSeconds` and owns all of this. The client only asks.

- **Lit or dark** is decided from the trusted cell and the front, never from anything a client
  renders.
- **The flashlight** is on only while the player has asked for it and `battery > 0`. While on, it
  drains 1 battery-second per second, **in any room**. Leaving it on in a lit room is the player's
  own waste. When the battery empties, the flashlight turns itself off and the player is told.
- **Exposure:**
  - In a lit room it recovers at `Exposure.RecoverPerSecond` down to 0.
  - In a dark room with the flashlight **off** (or empty) it rises at 1 per second.
  - In a dark room with the flashlight **on** it holds, neither rising nor falling.
  - At `GraceSeconds` the dark takes you: if Second Wind is unspent, it fires (§5.4); otherwise you
    die (§2.5).
- **Why there is nothing to gain by spamming the flashlight toggle:** battery drains only while the
  light is on, and exposure rises only while it is off in the dark. A toggle therefore splits one
  second between two costs, with no third state that costs neither. Each tick the server applies
  only the **latest** requested state, so a burst of toggles inside one tick is one change.
- **Sprint.** While sprint is requested and stamina is above 0, the server sets
  `Humanoid.WalkSpeed = SprintSpeed` and drains stamina at 1 per second. Otherwise WalkSpeed is 16,
  and stamina refills over `StaminaRegenSeconds` while not sprinting.

### 2.4 Fuses, the elevator, the choice

- **Pickups are automatic.** A fuse or battery cell is taken when the trusted position is within
  `PickupRadius` of it **and** the trusted cell is the item's cell. There is no prompt.
- **A cell adds `Battery.CellSeconds`, up to the cap.** At a full battery the cell is **not**
  consumed: it stays where it is, and the player is told "Battery full". Below the cap it is
  consumed whole. (The rig consumed cells even at a full battery, so it is pessimistic here;
  Appendix A.)
- **Fuses go in by themselves.** Entering the exit room inserts every fuse you carry, and the panel
  shows the slots. Short of the count, the player is told how many are still missing. Nothing fails
  silently.
- **All fuses in: the elevator powers.** The server does four things in one step:
  1. adds `FloorPay(k)` to the run's Essence;
  2. raises `bestSublevel`;
  3. writes a checkpoint (§7);
  4. opens the **choice** panel.

  The exit room is lit, so the choice has no timer.
- **EXTRACT:** the run settles at once (§2.5), then a 4-second ride up to the hub.
- **DESCEND:** the player is moved into the zone's ride car. Over the 4-second ride the server
  destroys the floor and builds sublevel `k+1`'s entry room, then moves the player into its car. The
  front starts when the car doors open.

### 2.5 Death, extraction, settlement

All of these call **one idempotent function**, `endRun(plr, reason)`:

| reason | what triggers it | pays |
|---|---|---|
| `extract` | the EXTRACT choice | `runEssence` |
| `dark` | exposure reaches grace | `floor(keep * runEssence)` |
| `reset` | `Humanoid.Died` during a run (the Roblox Reset button, or falling out of the world) | same as `dark` |
| `left` | `PlayerRemoving` during a run | same as `dark` |
| `shutdown` | `game:BindToClose` | same as `dark` |

- **`keep` is snapshotted when the run starts** (0.25 plus Soul Anchor).
- **Settlement happens the instant the cause is known**, before any presentation plays, so leaving
  during the death beat changes nothing.
- **Leaving, resetting and crashing pay exactly what dying pays.** None of them is a way out of a
  bad run (§9).
- **A dark death does not kill the Humanoid.** It is a 2.5-second fade to black ("THE DARK TOOK
  YOU — kept 25 of 100 Essence"), then a server move to the hub. That keeps the dark death out of
  the engine's respawn cycle, which `robloxemu` does not model (SPAWN-ORDER §7). The reset path does
  go through a respawn, and §8 handles it.

### 2.6 Apparitions (presentation only)

- **What one is.** A tall black figure built from 6 Parts, with no mesh and no sound. It stands in a
  dark room you have already walked through, seen through the doorway you came in by.
- **When it appears.** At most once per sublevel: the first time a room connected to the player's
  **lit** room by an **open** door is dark, the server places the figure in that room, centred on
  the wall opposite the doorway, 2 studs off it, facing the doorway. It is 6 Parts because a head,
  a torso, two arms and two legs is the fewest that read as a person.
- **How often that happens:**

  | sublevel | floors that trigger it | after arrival (p50) |
  |---|---|---|
  | 1, first-ever run (front held) | 27% / 52% / 70% (perfect / slow / very slow) | 41 / 53 / 63 s |
  | 2 | 55% / 85% / 99% | 35 / 46 / 53 s |
  | 4 | 79% / 98% / 100% | 53 / 68 / 80 s |

  [M10]. It is mostly a sublevel-2 beat, not a first-minute one. The alternative trigger, "the first
  door opened into an already-dark room", fired on only 6% / 28% / 45% of first-run sublevel-1
  floors [M10], so it was rejected.
- **It changes no rule** (no damage, no exposure), so hiding it is a **client** decision. The client
  hides it once it has been on screen `ApparitionMinVisibleSeconds` and the camera has turned more
  than `ApparitionHideAngle` away, or as soon as the character is within `ApparitionHideRadius`. The
  server destroys it after `ApparitionLifetimeSeconds` either way.
- **It is deliberately not a jumpscare.** The round-2 radar puts jumpscare horror at about 2% day-7
  retention ("it acquires and does not hold"). The figure is silent and static, and it is gone when
  you look back.
- **It leaks nothing.** It only ever stands in a room that is already built, dark and visible.

---

## 3. Sublevel shape schedule

| sublevel `k` | grid | fuses | battery cells | why |
|---|---|---|---|---|
| 1–3 | 4×4 | 3 | 2 | Model floor time p10 32.3 s / p50 45.2 s / p90 62.2 s [M1]. Short floors while a new player learns. |
| 4–8 | 5×5 | 4 | 2 | p50 74.3 s [M1]. The grid stops growing here: 6×6 floors took p50 109.0 s, 47% longer [M1], on every sublevel from the growth on. Capped at 5×5, the slow explorer's run to death lasts p50 8.8 min [M8], inside the brief's 5–10. After the cap, difficulty comes from slack, fuses and cells. |
| 9+ | 5×5 | 5 | 1 | Cells are the sustain lever. A +2-cells-per-floor perk let the perfect explorer clear 30 sublevels 88% of the time [M4]. With that perk plus a 90 s cap and 8.5 s grace, even the medium explorer cleared 30 on 84% of runs [M4]. So depth thins cells, and no perk adds them. |

**The curve is never flat.** Perk-less, the perfect explorer clears sublevel 10 / 15 / 20 / 30 with
probability 0.94 / 0.56 / 0.22 / 0.01 [M5]. The slow explorer clears sublevel 4 / 5 / 6 / 8 with
0.89 / 0.63 / 0.38 / 0.09 [M5].

---

## 4. Procedural generation

All generation is pure and lives in `src/shared/Facility.luau`. It is a function of
`(cfg, k, layoutSeed, lootSeed, decorSeed, Rng, MazeGen)`. It requires nothing, because a bare
`require("./X")` is invalid in Roblox and every dependency is an argument.

1. **Seeds.** For each sublevel the server draws three independent values with
   `Random.new():NextInteger(0, 2147483646)` (engine entropy [DOC]): `layoutSeed`, `lootSeed` and
   `decorSeed`.
   - They are held in the run table and a ServerStorage debug mirror (§7), and are never
     replicated or persisted.
   - Every value stays below 2^53, so no low bits are lost (checklist: seed overflow).
   - **Why three streams:** `Rng` is a 32-bit LCG. Someone who brute-forced a layout seed from the
     walls they have seen would learn walls, not where the fuses are. Keeping props off the layout
     stream also gives that attack no extra observations.
   - **Why a fresh seed every sublevel, salted by nothing public:** nothing is memorisable (checklist:
     replayable RNG). The brief's promise is "the facility rebuilds itself from scratch every run".
2. **Walls.** `MazeGen.generate(n, n, layoutRng)`, copied **verbatim** from labyrint-spill (md5
   `c269d302…`, identical in vault-runners). It gives a perfect maze, so every room is reachable by
   construction. Then every closed wall between neighbours opens with probability
   `ExtraDoorChance = 0.2`, drawn from `layoutRng` in row-major order.
   - `Rng` needs `NextInteger`, routed through `Rng.below` (high bits). Copy vault-runners' `Rng`,
     md5 `217e5d06…`, not the older variant, because MazeGen asks for 1..4 (a power-of-two span).
   - Measured doors per room: 1.05 on 4×4, 1.09 on 5×5 [M1].
3. **Entry and exit.**
   - Entry: a perimeter cell, `layoutRng:below(#perimeter)`.
   - Exit: a room at maximum BFS distance from the entry, ties by `layoutRng`. Every floor is a
     full crossing (the nightwatch-manor invariant).
   - Measured `maxD`: p50 7, max 15 on 4×4; p50 10, max 22 on 5×5 [M1].
4. **Loot** (`lootRng`).
   - Fuses go in distinct rooms, never the entry or the exit.
   - **On every run's sublevel 1**, the first fuse is placed within `OnboardFuseMaxDistance = 2`
     doorways of the entry. That moved a perfect explorer's first fuse from p50 8.6 s / p90 22.4 s
     to p50 5.4 s / p90 17.9 s [M1].
   - Battery cells go in distinct remaining rooms. A room holds at most one item.
   - An item's position is a `lootRng` point in the room interior at least 6 studs from every wall.
   - **Draw order:** every room choice first (fuses, then cells), positions after. That keeps the
     room assignment identical to the rig's, so §14 can reproduce M1.
5. **Decor** (`decorRng`). Zero to 3 props per room (desk, crate, cabinet, pipe run), from one kit.
   With three, a fully opened 5×5 zone comes to 566 Parts, under the 600 cap (§4.7).
   - A prop is anchored.
   - It never overlaps an item's pickup circle, and never comes within 4 studs of a doorway line.
     Four studs is one character hull, so a prop can never narrow the approach to a doorway below
     a body's width.
   - The spec asserts both, because a prop across a doorway is a wall (nightwatch's M23: furniture
     that blocks the route).
6. **Model time and front.** `Facility.modelTime(plan, cfg)` runs the model explorer exactly as in
   Appendix A, then `Facility.front(plan, cfg, k, hold)` returns `step`, and each room's death and
   flicker times. Both are pure and deterministic.
7. **Room build, done by the server when a room is opened:**
   - floor, ceiling, and four walls inside the cell (each room owns its own, so neighbours meet
     back to back and no visible faces are coplanar);
   - doorway gaps split each wall into at most 3 Parts;
   - door leaves not yet built by the neighbour;
   - light fixture and PointLight, an `Fx.dustVolume`, props, the item if any.

   **Budget: at most 20 Parts per room, not counting door leaves:** floor 1, ceiling 1, walls 12,
   fixture 1, dust volume 1, props 3, item 1. Door leaves are counted per floor instead, at most one
   per doorway: a 5×5 grid has 40 internal walls, so at most 40.
   Per zone that is 25 × 20 + 40, plus 6 for the entry room's car, 8 for the exit elevator and
   panel, 6 for the ride car and 6 for an apparition: **566, under a 600 cap asserted by the
   headless check.**
   Evidence the scale is fine: fork-tower measured 4110 Parts, 1687 PointLights and 241
   ParticleEmitters across 24 lanes with draw batches unchanged [REPO `fork-tower/STUDIO.md` §6].
   8 zones × 600 = 4800 Parts is of that order, but not identical, which is why it is also §15
   item 13.

---

## 5. Every number

### 5.1 Movement and geometry (`Config.Movement`, `Config.Facility`)

| name | value | reason |
|---|---|---|
| `WalkSpeed` | 16 | Read off a live Humanoid in Studio [REPO `fork-tower/STUDIO.md` §5]. The server **assigns** it on every character. A speed nobody configured is a speed no test can see (the nightwatch-manor defect). Every model run used it. |
| `JumpHeight` | 7.2 (unchanged) | Same measurement. Nothing in v1 is a jump. |
| `SprintSpeed` | 24 | A full stamina bar covers 4 s × 24 = 96 studs = 3.4 rooms. Walking inside the exposure grace covers 4 s × 16 = 64 studs = 2.3 rooms [ARITH]. So sprint is the tool for a dark crossing. Feel: [STUDIO]. Not in the survival model (§0). |
| `StaminaSeconds` | 4 | Pairs with `SprintSpeed` above. |
| `StaminaRegenSeconds` | 8 (empty to full, while not sprinting) | About one median front step on sublevel 1, p50 10.0 s [M6]: roughly one full sprint per ring the dark advances. |
| `CellSize` | 28 studs | 1.75 s to cross at walk [ARITH]. At this size the slow explorer's run to death lasts p50 8.8 min [M8], inside the brief's 5–10. Every timing in Appendix A is in these units. |
| `WallThickness` | 1 | Inside the cell. See §4.7. |
| `CeilingHeight` | 14 | Above a jump apex: JumpHeight 7.2 [REPO] plus an avatar height of about 5 (not measured). [STUDIO] |
| `DoorWidth` × `DoorHeight` | 6 × 9 | A 4-stud hull (fork-tower's `CharacterHalfWidth = 2`, itself an unmeasured model) plus 1 stud each side. [STUDIO] |
| `DoorOpenSeconds` | 0.5 | The door tween, and the charge every model run added per first entry [M1–M10]. |
| `DoorOpenRadius` | 8 studs | At WalkSpeed 16, 8 studs = 0.5 s = the tween, so a walking player reaches the doorway as it finishes opening [ARITH]. |
| `PickupRadius` | 5 studs | Items sit at least 6 studs from walls, so a pickup never reaches through a wall [ARITH]. |
| `ExtraDoorChance` | 0.2 | Dead-end rooms 18% / 13% / 8% at 0 / 0.2 / 0.4 [M9]. Slow explorer's mean sublevels cleared 4.16 / 5.16 / 6.08 [M9]. 0.2 keeps dead ends as real exploration decisions. **The whole difficulty curve was measured at 0.2**: retune this and re-run M4/M5. |
| `OnboardFuseMaxDistance` | 2 doorways | §4.4 [M1]. |
| `RoomLightRange` | 26 studs | Ceiling centre to floor corner is √(14² + 14² + 14²) = 24.2 studs [ARITH]. Brightness: [STUDIO]. |
| `Flashlight.Range` | 40 studs | From a doorway, the next room's far wall is 28 studs away [ARITH]. Roblox caps light range at 60 [DOC]. |
| `Flashlight.Angle` | 45° | Cone width at 28 studs = 2 × 28 × tan 22.5° = 23.2 studs, about a room's 26-stud interior [ARITH]. |
| `MaxPartsPerRoom` | 20 (door leaves excluded; at most 40 per floor) | §4.7. |
| Hub | 60 × 40 × 14 studs, spawn at one end, car 16 studs ahead of it, terminal on a side wall | 16 studs = 1 s at walk, so the core action lands inside the checklist's 5 seconds [ARITH]. 60 × 40 holds 8 avatars, the car and the terminal. Its 30-stud half-width is the hub term in `ZoneSpacing` (§5.5). |

### 5.2 The front (`Config.Front`)

| name | value | reason |
|---|---|---|
| `LeadSteps` | 2 | The entry room goes dark at p10 11.5 s / p50 20.0 s after arrival on sublevel 1 [M6]. It is counted in steps, not seconds, so it scales with the floor (the vault-runners 8c lesson). |
| `slack(k)` | `1 + (1 + (k-1)/4)^-1` | §2.2. Parameters `S1 = 2`, `Smin = 1`, `K = 4`, `e = 1`. M3 tried `Smin 1.1, K 3` on the longer 6×6 schedule. This form was measured in M4 and M5: perk-less, the slow explorer clears sublevel 1 always and dies at median sublevel 5, and the perfect explorer's P(clear k) keeps falling out to sublevel 30 [M5]. |
| step guard rail | `>= CellSize / WalkSpeed = 1.75 s` | The dark never crosses a room faster than a walking player does. **Non-binding as measured:** the smallest step over 3000 floors was 4.05 s at sublevel 1 and 2.34 s at sublevel 100 [M6]. It exists for a retune. |
| `FlickerSeconds` | 2.0 | Below every measured step (minimum 2.34 s [M6]), so a ring finishes dying before the next ring starts to flicker, and the front reads as a sequence rather than a smear. |
| first-run hold | front starts at the first fuse pickup, sublevel 1, `runs == 0` only | P(clear sublevel 1): very slow 8 studs/s explorer 0.959 → 0.990; 6.4 studs/s 0.817 → 0.908 [M7]. |

### 5.3 Survival (`Config.Battery`, `Config.Exposure`)

| name | value | reason |
|---|---|---|
| `Battery.CapSeconds` | 45 | Seconds a slow explorer spends in the dark on sublevel 1 (slack 2.0): p50 5.4, p90 20.2 [M2]; 45 covers p90 more than twice. With the cell schedule the perk-less slow explorer dies at median sublevel 5 [M5], after p50 8.2–8.8 min (494 s in M4; 8.8 min in M8, which adds rides and overhead). That is the brief's 5–10-minute run. |
| `Battery.CellSeconds` | 15 | Measured with the cap and schedule above [M4, M5]. |
| battery drain | 1 per second while on | §2.3. |
| `Exposure.GraceSeconds` | 4 | The farthest point in a room from a doorway is √(28² + 14²) = 31.3 studs = 1.96 s at walk [ARITH]. Doubled for reaction. |
| `Exposure.RecoverPerSecond` | 1 | Symmetric: X seconds of exposure takes X seconds of light to clear, so exposure is a debt counted in the same seconds as the grace. It is also the rate M3–M8 modelled. |
| Second Wind battery | +10 s | 10 s × 16 studs/s = 160 studs = 5.7 rooms of lit walking to get out of the dark it saved you from [ARITH]. Modelled in M5. |

### 5.4 Economy and perks (`Config.Economy`, `Config.Perks`)

**Pay.** `FloorPay(k) = 10 + 5 * (k - 1)`, so clearing sublevels 1..K pays `10K + 2.5K(K-1)`:
10, 25, 45, 70, 100 for K = 1..5. The absolute scale is a unit choice: only the ratios matter to the
measurements, and the perk prices below are set in the same unit. At base 10 the smallest possible
death payout (dying on sublevel 2) is still `floor(0.25 × 10) = 2` Essence rather than 0.

Measured Essence per minute when extracting after sublevel K [M5] (`K*` = the best K):

| pay rule | slow explorer | medium explorer | perfect explorer |
|---|---|---|---|
| flat 20 per floor | K* = 3 | K* = 3 | K* = 3 |
| `10 + 5(k-1)`, keep 25% (chosen) | K* = 3, 12.2/min | K* = 8, 17.1/min | K* = 11, 27.0/min |
| `10 + 10(k-1)` | K* = 4, 16.7/min | K* = 8, 27.9/min | K* = 12, 46.6/min |

- **Flat pay was rejected.** It makes extracting at sublevel 3 optimal at every skill level, so the
  push-your-luck choice collapses into a rule and skill stops mattering.
- **`10 + 5(k-1)` was chosen.** The best extraction depth rises with skill (3 → 8 → 11), which is
  what makes DESCEND a real decision, and the perfect/slow ratio is 2.2×.
- **`10 + 10(k-1)` was rejected** for widening that ratio to 2.8×.

**Death keeps `DeathKeep = 0.25`.** At 25%, a slow explorer who greedily pushes to sublevel 8 earns
4.7/min against 12.2 playing optimally [M5]: death is a real cost. Soul Anchor at rank 3 (55%) lifts
that greedy rate to 7.7/min while barely moving the optimum (12.3) [M5]. It is a forgiveness perk,
not a strategy changer: with it maxed, the slow and medium explorers' best K stays at 3 and 8 [M5].
The perfect explorer's best K sits at the edge of the measured range (11 at 25%, 12 at 55%) [M5].
For a perfect player, going very deep simply is the right play.

**Perks.** Five perks, bought with Essence only, snapshotted at run start.

| id | name | ranks | effect per rank | price by rank |
|---|---|---|---|---|
| `deepCell` | Deep Cell | 3 | battery cap +10 s (45 → 75) | 25 / 60 / 120 |
| `nightEyes` | Night Eyes | 3 | exposure grace +1 s (4 → 7) | 25 / 60 / 120 |
| `marathon` | Marathon | 3 | stamina +1 s (4 → 7) | 25 / 60 / 120 |
| `soulAnchor` | Soul Anchor | 3 | death keep +10 points (25% → 55%) | 25 / 60 / 120 |
| `secondWind` | Second Wind | 1 | once per run, the dark's killing moment is cancelled in place: exposure to 0, battery +10 s | 150 |

- **Rank 1 = 25.** A perk-less slow explorer's first run, pushed until death, banks p50 25 (p10 11,
  p90 43) [M8], so at that proxy's median a perk is affordable after run 1. The very slow explorer
  banks p50 11, so 2–3 runs [M8]. A first extraction at sublevel 3 pays 45. The brief's hook is "every death
  makes you deadlier", so the first purchase must arrive at once.
- **Ranks 2 and 3 = 60 and 120.** Rank 3 costs about ten minutes of optimal slow-player play
  (120 / 12.2 per min = 9.8 min [M5]).
- **Second Wind = 150.** Measured effect on median sublevels cleared (slow / medium / perfect)
  [M5]:

  | perk state | slow | medium | perfect |
  |---|---|---|---|
  | none | 5 | 9 | 15 |
  | Deep Cell ×3 (205 Essence) | 7 | 11 | 20 |
  | Second Wind (150 Essence) | 6 | 10 | 18 |
  | Night Eyes ×3 | 5 (mean 5.16 → 5.41) | 9 | 16 |
  | all three survival perks | 8 | 12 | 25 |

  That is roughly 100–150 Essence per extra median sublevel for the slow explorer, so the prices
  are consistent.
- **Night Eyes looks nearly worthless in the model, and the model is the reason.** The explorer
  never changes route toward light when its battery dies, and a longer grace is exactly what buys a
  human that choice. It keeps the common ladder; §15 item 1 re-prices it.
- **Marathon and sprint are not modelled at all** (§0). Its +1 s per rank (4 → 7) is the same
  +75% at max rank as Night Eyes, so neither out-prices the other until a playtest separates them.
- **With every survival perk maxed, the endless curve still bites:** the perfect explorer clears
  sublevel 30 with probability 0.21 [M5].
- **Total for everything: 970 Essence.** At the model's optimal rates that is about 80 / 57 / 36
  minutes for the slow / medium / perfect explorer (970 / 12.2, 17.1, 27.0 [M5]). Real play is not
  optimal, so real time is longer. v1 has one room kit, and a grind longer than the content would be
  padding, so the tree is sized to the content, not to a retention target.
- **Removed from the brief's perk list, with reasons:**
  - "Scavenger" (+cells): measured to break the endless curve, §3.
  - "starting keycard": it deletes one of three objectives on sublevels 1–3.
  - "shorter cooldowns": there are no cooldowns.

### 5.5 Pacing, server and persistence (`Config.Run`, `Config.Server`, `Config.Data`)

| name | value | reason |
|---|---|---|
| `ServerTickSeconds` | 0.1 | Resolution of 2.5% of the 4 s grace and 5% of the 2 s flicker [ARITH]. dt comes from `task.wait`'s return value (§2.2). |
| `StatePushSeconds` | 0.2 (5 Hz, owner only) | A battery step of 0.2 s is 0.44% of a 45 s bar [ARITH]. The HUD tweens between pushes. |
| `BoardingSeconds` | 1.5 | The hub car's interior is 8 studs deep, 0.5 s at walk [ARITH]. Standing 3× that is deliberate, so walking past the car never starts a run. Stepping out cancels, with a toast. |
| `RideSeconds` | 4 | A breather between floors, during which the server clears the old floor (at most 600 Parts) and builds one room out of the player's sight. How long that work takes is not measured, and nothing waits on it finishing early. Included in M5/M8's run-time accounting. Feel: [STUDIO]. |
| `DeathBeatSeconds` | 2.5 | The fade and "THE DARK TOOK YOU" card. Feel: [STUDIO]. |
| per-run overhead (model only) | 15 s | An assumption in M5/M8's run lengths. The rows above give a floor of 1 + 1.5 + 4 + (2.5 death beat or 4 ride up) = 9–10.5 s [ARITH]; the remaining 4.5–6 s stands for walking around the hub between runs, which is not measured. |
| `TrustedSpeedFactor` | 1.35 over the server's own current speed (16 or 24) | Inherited from `vault-runners/src/shared/Config.luau` `Run.TrustedSpeedFactor`: "jitter, not speed". Never measured against real replication. [STUDIO] |
| `TrustedBurstSeconds` | 3 | Same file, same caveat. |
| `ApparitionHideRadius` | 12 studs | The figure stands about 24 studs from its doorway (28-stud room, 2 studs off the far wall, 2 studs of doorway depth). At 12 studs the player has spent 0.75 s walking toward it: seen, never reached [ARITH]. |
| `ApparitionHideAngle` | 60° off the camera's look direction | Roblox's default 70° vertical FieldOfView [DOC] gives a horizontal half-angle of about 51° on 16:9 [ARITH]. 60° is "just off screen". [STUDIO] |
| `ApparitionMinVisibleSeconds` | 0.5 | So a figure is not hidden on the very frame it would first be seen. [STUDIO] |
| `ApparitionLifetimeSeconds` | 10 | Server cleanup, longer than a glance. |
| `Players.MaxPlayers` / zone pool | 8; the server uses `max(8, Players.MaxPlayers)` zones | 8 × 600 Parts is the fork-tower-measured order of scale (§4.7). The pool is a floor, not a cap, so a Studio slider cannot seat more players than zones (fork-tower REVIEW-3, M5). |
| `ZoneSpacing` | 400 studs; zone `i` origin `(400·(i+1), 0, 0)`, hub at origin | A zone's reach = half its 5×28 footprint (70) + the ride car 20 studs off the grid + max light range 60 [DOC] = 150. Two zones need 300; 400 leaves 100 margin. The hub reaches 30 + 60 = 90, well inside 400 − 150 = 250 [ARITH]. Zone indices are recycled on leave (checklist: unbounded coordinates). |
| `Workspace.StreamingEnabled` | false | The server moves characters 400+ studs into zones. With streaming on, the destination floor may not have streamed to the client yet [DOC]. At most 8 × 600 Parts need no streaming. [STUDIO] |
| `Players.RespawnTime` | 3 | Only the reset path respawns (§8). Roughly matches the 2.5 s death beat; Roblox's default is 5 [DOC]. [STUDIO] |
| `StarterPlayer.EnableMouseLockOption` | false | Shift is sprint. [STUDIO] |
| `Data.AutosaveSeconds` | 20 | The sibling convention, live in anomaly-observatory (`src/shared/Config.luau` line 120). |
| `Data.SessionLockSeconds` | 45 | Same file, line 121. Longer than two autosaves, so one failed autosave does not drop the lock. |
| DataStore write rate | about 50 per minute at 8 players | Autosave only when dirty (at most 8 × 3 = 24/min), plus checkpoints (a p10 model floor takes 32.3 s [M1], so about 8 × 60/32 = 15/min), plus settles and purchases. Roblox allows 60 + 10 × players = 140/min [DOC]. |

---

## 6. Meta-progression

The hub terminal opens the perk panel. Buying a perk is `BuyPerk(perkId)`.

- **It is refused unless** the profile is loaded, the store is writable and the lock is ours, the
  player is in the hub, no run is open, the rank is below max, and `essence >= price`. Every
  refusal says why.
- **The atomic flush** (checklist: one-time rewards):
  1. snapshot the profile;
  2. apply the purchase;
  3. flush the **whole** profile with `UpdateAsync`, under the lock;
  4. if the write did not persist, roll back to the snapshot and tell the player "Couldn't reach the
     save server — nothing was spent."

  Nothing is granted that is not on disk.
- **When the DataStore is unavailable** (an unpublished place, where `GetDataStore` raises [REPO
  `fork-tower/STUDIO.md` §7]), purchases are refused and the HUD says progress will not be saved.
  Runs still play.

---

## 7. Data model

### 7.1 What persists

DataStore `FacilityNightmare_v1`, key `u_<userId>`, record `{ data = <profile>, lock = { owner, expires } }`.

| field | type | why |
|---|---|---|
| `v` | 1 | schema version |
| `essence` | integer ≥ 0 | wallet |
| `essenceEarned` | integer ≥ 0 | lifetime banked; stats only |
| `perks` | `{ deepCell, nightEyes, marathon, soulAnchor, secondWind }` | **String keys only.** JSON round-trips sparse integer keys into strings (checklist). Sanitised on load: unknown keys dropped, ranks clamped to `0..max`. |
| `bestSublevel` | integer | deepest sublevel whose elevator was powered; mirrored to `leaderstats.Deepest` |
| `runs` | integer | settled runs; `runs == 0` means the first-ever-run hold applies |
| `extractions` | integer | stats |
| `openRun` | `nil` or `{ id = GUID string, sublevel, runEssence, keep }` | See the settlement rules below. |

**How `openRun` works.**

- It is written at every elevator powering, as the checkpoint.
- It is **cleared in the same write that pays the run**, so a run can be paid only once.
- **If the server dies mid-run:** the store holds the last checkpoint. The next load settles it as
  `dark` (`floor(keep * runEssence)`) before any new run may start. The player loses the
  extraction bonus, never gains.
- **If a settle's write fails:** memory holds the paid profile with `openRun = nil`, and the store
  holds the unpaid checkpoint. Autosave retries every 20 s. Whichever lands is applied once, and
  the two can never be combined, because they are written as one record.

**What never persists:** battery, exposure, stamina, fuses held, seeds, the plan, positions,
apparition state, phase.

**Session lock.** The owner is a **stable per-session GUID**, never a timestamp that is also
rewritten (checklist). The profile is always loaded with `UpdateAsync`, and the lock is taken only
if it is free or expired. `GetDataStore` is `pcall`'d.

**A run may start only if** the store is unavailable (play unsaved, said on the HUD), **or** the lock
is ours and no `openRun` is still unsettled. If the lock is held elsewhere, the elevator says "Your
file is open on another server — retrying" and retries on each autosave tick. A run whose result
could not be saved while a save file exists would be a silent loss.

### 7.2 Server-only state

**In `Main.server.luau`, as a Lua table per player (never an Instance):** phase; zone index;
sublevel; the three seeds; the plan (adjacency, entry, exit, `d[]`, items, `Tmodel`, `step`, `hold`,
death times); run clock; trace and trusted cell; opened doors; built rooms; battery; exposure;
stamina; flashlight and sprint requested/actual; fuses held and inserted; `runEssence`; the perk
snapshot; Second Wind left; whether an apparition has been shown.

**In `ServerStorage.FacilityDebug.Run_<userId>` (a Folder with attributes):**
`Sublevel`, `LayoutSeed`, `LootSeed`, `DecorSeed`, `EntryCell`, `ExitCell`, `FuseCells`,
`BatteryCells`, `StepSeconds`, `HoldSeconds`, `ModelSeconds`. They are written only so the headless
check can compare the world against the plan (the anomaly-observatory `PassInfo` pattern).
**ServerStorage never replicates.** The check sweeps `Workspace` and `ReplicatedStorage` for every
one of these attribute names and fails if any appear. That is the "ServerStorage, not the zone"
lesson turned into an assertion.

### 7.3 What replicates, and why each is safe

| what | who receives it | why it is safe |
|---|---|---|
| Hub geometry, `HubSpawn`, the car, the perk terminal | everyone | static |
| **Built** rooms: walls, floor, ceiling, props, door leaves and their open state | everyone (streaming off) | A room exists only after a trusted door-open into it, so the workspace never holds a room its owner has not reached. Other zones hold other seeds, worth nothing. |
| Room `PointLight.Enabled`/`Brightness` and fixture colour, including the flicker | everyone | The flicker is the intended 2 s warning and carries exactly what the world shows. Death times, `step`, `hold` and `d[]` are never written to any Instance. Flicker is the server stepping `Brightness` on every other tick (10 changes per room over the 2 s), not an attribute like "dies at t". |
| Fuse and cell Parts, named `Fuse` / `Cell` | everyone | Built rooms only, where the owner can see them anyway. **No attributes.** |
| Exit elevator and fuse panel | everyone | Only once the exit room is built. The exit's location is otherwise unknown to the client. |
| Apparition model | everyone | Built, dark, already-visible rooms only. Presentation. |
| Flashlight `SpotLight.Enabled` on the character, `Humanoid.WalkSpeed` | everyone | They mirror server state, and no rule reads the client's copy. |
| `leaderstats.Deepest` | everyone | Public by design. |
| `State` / `Notice` / `Taken` remotes | the owning player only (`FireClient`) | battery, exposure fraction, stamina, fuses `x/N`, sublevel, `runEssence`, and the choice payload. `N` is in the public schedule. **No** cell, seed, item location, `d[]`, `step` or `hold`. |
| `ReplicatedStorage` module **source**: `Config`, `Facility`, `Survival`, `Trust`, `Economy`, `Rng`, `MazeGen`, `Fx`, `FxClient`, `Responsive` | everyone | `robloxemu`'s harness mounts only `src/shared` as requirable modules (`emu/harness.luau` lines 90–102), so every pure module ships its source to clients. **No secret may live in code.** The secrets are runtime values (seeds, plan) that exist only in server memory. |
| Attributes under any zone | nobody, because there are **none** | Asserted by enumerating every attribute on every Instance under every zone against an **exact expected list, which is empty**. Per fork-tower REVIEW-3, the enumeration is the test, not a list of forbidden names, so a leak that is renamed or moved onto a BillboardGui still fails. |

**What an exploiter can still learn, accepted:** the walls and contents of rooms they have opened,
seen at full brightness with a local fullbright; other players' floors; the generator's source.
Those give no fuse locations ahead of time and no route through unopened doors. **Residual risk:**
a 32-bit layout seed could in principle be brute-forced offline from the walls seen so far. That
yields walls only, because loot is an independent stream.

---

## 8. Spawn and respawn placement (per `robloxemu/SPAWN-ORDER.md`)

**The engine's order** (measured in Studio [REPO `fork-tower/STUDIO.md` §3]): `CharacterAdded` fires
while the character is **unparented at the origin**. One frame later the engine parents it and
places it on a spawn, discarding any CFrame written in between. With no enabled `SpawnLocation` it
drops the character on the highest ground over the origin, and the hub, a sealed room at the
origin, has a **roof**.

1. **Build the hub first**, synchronously, when `Main.server` starts: floor, walls, ceiling, lights,
   `HubArrival` (a plain Part) and `HubSpawn`, a real `SpawnLocation` with `Enabled = true`,
   `Duration = 0` (no ForceField [DOC]) and `Neutral = true`. All of this happens **before**
   `PlayerAdded` is connected, before existing players are looped over, and before any DataStore
   call (nightwatch-manor's fix: the world must exist before the blocking load).
2. **`HubSpawn` is the only enabled `SpawnLocation` anywhere.** Zones, cars and the ride car are
   plain Parts. The engine chooses arbitrarily among several enabled spawns (SPAWN-ORDER §7), and a
   stray one in a zone would receive every respawn. Asserted, as deep-vein's `walk.luau` does.
3. **In `PlayerAdded`, set `plr.RespawnLocation = HubSpawn` immediately**, before the character
   loads. This is SPAWN-ORDER's preferred pattern: the engine's own placement is already correct.
4. **The `CharacterAdded` handler writes no CFrame and does not yield.** It sets
   `Humanoid.WalkSpeed = 16` (a property of the Humanoid, not a position) and resets the camera to
   Classic. If a run is open, it calls `endRun(plr, "reset")`, which is idempotent.
5. **Every other move is a server write on a character that is already in the world**, never inside
   `CharacterAdded`:

   | move | from → to |
   |---|---|
   | run start | hub car → zone ride car → entry car |
   | descend | exit room → ride car → next entry car |
   | extract | exit room → ride car → `HubArrival` |
   | dark death | wherever you are → `HubArrival`, after the beat |

   Each move is guarded by `char.Parent ~= nil and humanoid.Health > 0`, and each one **resets the
   trace** to its destination (§9). If the guard fails, a run start is refused with a toast. Any
   other move is skipped, because a character that is not alive in the world is already on the
   reset path (item 6), and the run is already settled.
6. **The reset path.** `Humanoid.Died` during a run calls `endRun(plr, "reset")`. The engine
   respawns after `Players.RespawnTime` and places the character on `HubSpawn` through
   `RespawnLocation`, with nothing to race.
7. **Falling out of the world** (for example after locally deleting a door into an unbuilt room)
   reaches `FallenPartsDestroyHeight` [DOC], then `Died`, then path 6.

**Headless coverage.** `Players:simulateSpawn` now fires `CharacterAdded` before parenting and honours
`RespawnLocation` (SPAWN-ORDER §2), so items 1–4 are checkable. Item 6's automatic respawn is not
modelled by the emulator (SPAWN-ORDER §7). The check fires `Humanoid:TakeDamage` to raise `Died`,
calls `simulateSpawn` itself, and asserts one settlement and a landing on `HubSpawn`.

---

## 9. Anti-exploit model

The client owns its character's physics, can read everything that replicates, can edit its own
Lighting, and can fire any remote with any arguments. **Every rule therefore reads the server's own
state**, and nothing a client sends is trusted beyond "the player would like X".

**The trusted position** (`src/shared/Trust.luau`, pure). It follows vault-runners' `Trace.luau`:
the server moves its own copy of the player's position toward the client's claim, no faster than
`TrustedSpeedFactor` × the speed the **server** has set (16, or 24 while sprinting), banking up to
`TrustedBurstSeconds` of unused allowance for jitter. The room graph adds the part vault-runners
does not have:

- **The trusted cell changes only to an adjacent cell, and only through a doorway the server has
  opened.**
- A claim through a wall or a closed door leaves the trusted position clamped inside the current
  cell.
- Pickups, door opening, fuse insertion, lit/dark, exposure and the exit all read the trusted cell
  and position.

| threat | what it would buy | response | residual |
|---|---|---|---|
| Teleport, speed hack, noclip | instant fuses, instant exit | trusted position and trusted cell, as above | straight-line movement *inside* a room at up to 1.35× speed |
| Client `WalkSpeed` override | outrunning the dark | the trace is capped by the server's speed, not the Humanoid's | as above |
| Fullbright / local Lighting edits | seeing in the dark | no rule depends on what renders; unbuilt rooms do not exist; the dark kills by server arithmetic | sees opened rooms at full brightness |
| Reading replicated Instances or attributes | fuse rooms, the exit, the schedule | none of it replicates (§7.3); enumeration test | none known |
| Reading module source | the generator | seeds are runtime-only, per sublevel, from engine entropy, in three independent streams | offline 32-bit layout-seed brute force gives walls, not loot |
| Forged remote arguments | free Essence, perks or extraction | typed validation; phase checks; trusted-cell checks (`Choose` requires the trusted cell to be the exit and fuses inserted = required); every refusal answered with a toast | none known |
| Remote spam | averaging or flooding | the flashlight and sprint remotes set a *requested* state; each tick applies only the latest; there is nothing to average (§2.3) | none |
| Deleting a door or wall locally | walking into unbuilt space | the trusted cell does not move; falling out means `Died`, which means a death settlement | none |
| Reset, leave or crash to dodge a death | keeping more than death pays | all pay exactly what `dark` pays (§2.5); `openRun` settles on the next load; `BindToClose` | none |
| Two servers | a double settle, or a perk dupe | session lock; `openRun` cleared in the paying write; purchases are whole-profile atomic flushes | none known |
| `fireproximityprompt` on the terminal | nothing: it only opens the panel | purchases go through the validated `BuyPerk` | none |
| AFK in a lit room or at the exit | Essence over time | nothing accrues with time; only powering an elevator pays | none |
| Farming shallow extractions | it is not an exploit | measured: sublevel 3 is optimal only for the slowest model; deeper pays more for skilled play [M5] | none |

**No `Workspace:Raycast`, no `PathfindingService`, no `Touched`** in any rule. All spatial rules are
grid arithmetic. That is a security property (`Touched` is client-physics-driven) and a
testability one (the emulator's `Raycast` raises on purpose, `robloxemu/emu/services.luau` line 903).

---

## 10. Fair monetization

**v1 sells nothing.** No game passes, no developer products, no paid private servers. Every perk is
bought with Essence, and Essence is earned only by powering elevators.

**Never, in any version:**

- Essence, perks, revives, battery or fuses for Robux;
- paid skips of a sublevel or the dark;
- randomised paid rewards of any kind (spin wheels, crates, loot boxes). The 2026-09-14 radar
  records player backlash against slot-machine wheels;
- rewards for watching or scrolling anything. The same radar series records Roblox forcing a top
  game to strip its "Reels" (2026-09-05 radar).

**If a v2 adds a store**, the only candidate is a **cosmetic** flashlight tint, as a game pass. The
constraint is written down now, because a tint is where pay-to-win would hide: the beam's `Range`,
`Angle` and `Brightness` must be identical for every tint, and a spec must assert it. A brighter
"cosmetic" beam is a paid advantage in a game about darkness.

---

## 11. Visuals and traps from the first build

Everything below is code-only and belongs in the **first playable build** (checklist §2), not a
later pass.

1. **Lighting.**
   - Copy `Fx.luau` from **anomaly-observatory or nightwatch-manor** (md5 `142bf959…`). That
     variant knows an `Atmosphere` in Lighting replaces the legacy fog properties.
   - Add one preset, `Fx.Presets.Facility`: the `Horror` preset with `Ambient` and `OutdoorAmbient`
     lowered, because an unlit room must read as **dark** and not dim.
   - `Fx.applyLighting(Fx.Presets.Facility)` is the server's first statement.
   - The exact ambient and exposure values are §15 item 2. They cannot be chosen from the CLI.
2. **Signature light.**
   - Fuses: `Fx.attachGlow` amber (the thing you chase glows).
   - Cells: green glow.
   - Exit panel: red slots that turn green as fuses go in.
   - Flicker: the room's fixture Part goes Neon to dark SmoothPlastic when its light dies.
3. **Atmosphere.** One `Fx.dustVolume` per built room (at most 25 per zone, 200 at 8 players;
   fork-tower measured 241 emitters without draw-batch change [REPO]).
4. **Client juice.** `FxClient.theme` on every HUD frame. `FxClient.shake` when the player's own room
   dies around them and when the dark takes them. `FxClient.flash` for the death and the extraction.
   `FxClient.fovPunch` on a fuse pickup.
5. **The exposure vignette.** Four edge Frames with `UIGradient` transparency ramps (no image
   asset), whose thickness follows the exposure fraction. A small `FxClient.shake` above 0.5.
6. **Camera.** `Player.CameraMode = LockFirstPerson` inside the facility and `Classic` in the hub,
   set by the server. The flashlight is a `SpotLight` on the head, so it points where you look.
   [STUDIO]

---

## 12. HUD (phone first)

Copy `Responsive.luau` verbatim (md5 `8cf3ba92…`, identical in all eight games) and follow
`docs/mobile-ui-brief.md`: a root Frame owns the `UIScale`; its size is `1/scale`; the layout is
re-applied on `ViewportSize` changes.

| element | where | notes |
|---|---|---|
| sublevel + fuses `x/N` | top-left | |
| battery bar + run Essence | top-right | |
| toasts / hints | top-centre, scale width with a `UISizeConstraint` cap | |
| **LIGHT** and **SPRINT** buttons | right edge, vertically between 45% and 70% of screen height | **Never** the bottom-left or bottom-right: Roblox's thumbstick and jump button own those. Tap targets are at least 44 **screen** px after scaling (the vault-runners `ceil(46/scale)` rule). Keyboard **F** and **Shift**; gamepad **ButtonY** and **ButtonL3**. |
| choice panel | centre modal | EXTRACT: "bank N". DESCEND: "next sublevel pays +P; if the dark takes you, you keep K%". |
| perk panel | centre modal, `ScrollingFrame` | opened by the hub terminal or a top-edge **PERKS** button in the hub |

**Glyphs.** Only glyphs already photographed rendering in Studio may ship. The list is
`GLYPHS_SEEN_IN_STUDIO` in `robloxemu/check_forktower.luau` (for example 🚪 🔒 👁 ★ — …). The
emoji this game would want — 🔦 U+1F526, 🔋 U+1F50B, ⚡ U+26A1 — are **not** on it, so v1 labels are
plain text (`LIGHT`, `BATTERY`, `FUSES`) until §15 item 8 photographs them. fork-tower shipped an
Emoji-13 glyph that rendered as an empty box.

**HUD language:** English.

---

## 13. The first 60 seconds of a new player

Times are from joining. "After arrival" rows add the 7 s before the doors open.

| t (s) | what happens | evidence |
|---|---|---|
| 0 | The engine places the character on `HubSpawn` (§8). The break room is lit. A hint says **"Walk into the elevator"**, with a floor arrow to the car 16 studs ahead. | §8 |
| ≈1 | In the car: **the core action inside 5 seconds** (checklist §4), no prerequisite, nothing to buy. "Going down…" counts `BoardingSeconds`. | 16 studs at 16 studs/s [ARITH] |
| ≈2.5 → 6.5 | Doors close. Ride car: shake, flicker, **SUBLEVEL 1**. | `RideSeconds` |
| ≈7 | Entry car doors open into a lit room. HUD: `FUSES 0/3`, `BATTERY 45`. Hint: **"Find 3 fuses. Bring them to the elevator."** First-ever run, so the front is **held**. | §2.2 |
| ≈12–16 (p50) | **First fuse**, placed within 2 doorways of the entry. After arrival: p50 5.4 / 7.3 / 8.9 s, p90 18.8 / 26.3 / 32.8 s (perfect / slow / very slow). FOV punch. Banner: **"THE POWER IS FAILING — STAY IN THE LIGHT."** Hint: **"F / LIGHT button: flashlight."** The front starts. | [M6] |
| ≈24–26 (p10), ≈35–38 (p50) | **First darkness:** the entry ring flickers and dies behind the player. After arrival: p10 17.1–19.3 s, p50 28.2–31.1 s. | [M7] |
| on the player's own room flickering, or on entering a dark room with the light off | Hint: **"Your room is going dark — turn on your flashlight."** The vignette starts if they wait. | §2.3 |
| ≈52 / ≈71 / ≈86 (p50) | **Sublevel-1 elevator reached** and the first EXTRACT/DESCEND choice. After arrival: p50 45 / 64 / 79 s, p90 63 / 90 / 113 s. | [M8] |

**Honest reading of that table:**

- A new player **moves, opens doors, finds a fuse, and sees the dark start** inside the first
  minute.
- The **first choice screen** arrives at about one minute for a fast player, and **just after** the
  minute for most new players.
- **Usually no apparition** in the first minute. On a first-ever sublevel 1 it triggers on only
  27–70% of floors, at p50 41–63 s after arrival [M10]. It is a sublevel-2 beat.
- A first run pushed until death clears p50 5 sublevels and banks p50 25 Essence for the slow
  explorer [M8], which is **enough for the first perk** (§5.4).
- Holding the front makes a sublevel-1 death rare: the very slow 8 studs/s explorer survives
  sublevel 1 on 99.0% of floors [M7].

---

## 14. Invariants the build must test first (TDD order)

Each line below is a failing test to write before the code, and the name of the spec that owns it.

**`tests/Facility.spec.luau`**
1. Every room is reachable from the entry, over 10 000 seeds per shape.
2. The entry is on the perimeter. The exit is at maximum BFS distance, and exit ≠ entry.
3. Fuses and cells are in distinct rooms, never the entry or exit, with counts equal to the §3
   schedule.
4. Sublevel 1's first fuse is at `d ≤ 2` on **every** seed. A candidate always exists: sublevel 1
   is a connected 4×4 grid, so the entry has a neighbour at `d = 1`. That neighbour cannot be the
   exit, because the exit sits at `maxD`, and `maxD = 1` would need all 15 other rooms adjacent to
   one room of degree at most 4. Measured too: 0 of 20 000 plans lacked a candidate, and the
   smallest `maxD` seen was 5 [M11]. The test asserts "always", so a generator change that breaks
   the argument fails loudly.
5. Loot is independent of layout: same `layoutSeed` with a different `lootSeed` gives identical
   walls, and vice versa.
6. `modelTime` is deterministic.
7. `step >= CellSize / WalkSpeed`.
8. The last non-exit room dies at `hold + slack * Tmodel` (within 1e-9) whenever the guard rail does
   not bind.
9. The exit never dies.
10. `slack` is strictly decreasing and > 1 for k = 1..1000.
11. **Reproduce Appendix A M1's table** with the real module, using `m1_nofront.luau`'s seeds
    (`layoutSeed = 1000003·i + 17`, `lootSeed = 7919·i + 104729`, i = 1..3000). If it does not
    reproduce, re-measure M1–M11 against the real module and edit this spec's numbers; do not tune
    the module to the rig.
12. Only `Rng.below`, never `Rng.int`; seeds < 2^53; props clear doorways and pickup circles.

**`tests/Survival.spec.luau`**
1. Battery drains only while on, in any room. Exposure rises only in the dark with the light off or
   empty, holds with it on, and recovers in light.
2. Death at grace. Second Wind fires once and never twice.
3. `dt` that is NaN, negative or zero changes nothing.
4. A cell is not consumed at a full battery.

**`tests/Trust.spec.luau`**
1. The speed bound, including burst banking and its cap.
2. The cell changes only to an adjacent cell through an open door. A teleport claim is walked, not
   jumped. A wall claim is clamped.
3. The sprint cap follows the server's state, not the claim.

**`tests/Economy.spec.luau`**
1. `FloorPay` and its cumulative sum. `floor(keep * runEssence)`.
2. The price ladder and max ranks. Effects are clamped.
3. Profile sanitise: string keys, unknown keys dropped, and a JSON round-trip gives an identical
   profile.
4. Settlement is idempotent: a second `endRun` pays nothing.

**`tests/responsive.spec.luau`** — copied with `Responsive.luau`.

**`robloxemu/check_facilitynightmare.luau`**, against `build/facility-nightmare.luau` (rebuild the
bundle before every run):
1. The server boots with no errors. `HubSpawn` exists, is enabled, and is the **only** enabled
   SpawnLocation. `RespawnLocation` is set, and `simulateSpawn` lands the character on it.
2. Walking into the car starts a run. The entry room is built, and **no other room is**.
3. A door opens only on a trusted approach. A teleport onto a fuse does not collect it. A claim
   through a wall does not change the cell.
4. Ring 0 goes dark at the virtual time the plan says. The battery drains. A player with the light
   off in the dark dies at grace, settles at `keep`, and arrives at `HubArrival`.
5. An extraction pays in full.
6. `openRun` settles on rejoin, once.
7. **Enumerated attributes under every zone: exactly none.** The debug attribute names appear
   nowhere in `Workspace` or `ReplicatedStorage`.
8. Parts ≤ 20 per room (door leaves excluded), ≤ 40 door leaves per floor, and ≤ 600 per zone,
   counted by walking the built folders, not a loop counter
   (vault-runners invariant 6).
9. Every glyph in the built world and the HUD is on the Studio-seen list.
10. A purchase is refused and rolled back when the store write fails.
11. `TakeDamage` during a run settles once, then `simulateSpawn` lands on `HubSpawn`.

Then a mutation sweep with a **control** the suite must not notice (for example a room light's
colour), per the repo's mutation-control rule.

---

## 15. Needs Studio

Nothing on this list is verified. Each item says what to look at.

1. **Whether the dark is frightening and fair with real players.** The survival curve, `slack`,
   battery cap, cell size and every perk's value are model numbers (§0). Play sublevels 1–6 and time
   them against M8's p50 (45 / 64 / 79 s for sublevel 1), note where the players die, then re-run M4
   and M5 with a speed proxy fitted to what they actually did. **Night Eyes and Marathon especially:
   the model cannot value them.**
2. **`Fx.Presets.Facility` values.** Is an unlit room genuinely dark, is a flashlit room readable,
   and is the 26-stud room light enough?
3. **The flashlight.** SpotLight `Range 40`, `Angle 45`, brightness, shadows under `Future`
   lighting, and whether a head-mounted light in `LockFirstPerson` points where the player looks.
4. **Walk/sprint feel.** 16 and 24 studs/s, 1.75 s per room, and `CellSize 28` visually.
5. **Doors.** Whether a Humanoid fits a 6×9 doorway without snagging. Whether the 8-stud open radius
   and 0.5 s tween read as the door opening for you rather than at you. Ceiling 14 against a real
   jump.
6. **The 2 s flicker.** Is it noticed and understood without a tutorial?
7. **The apparition.** Does a 6-Part black figure read as a figure at about 24 studs in a dark room,
   or as a prop? Do the hide angle and radius make it vanish at the right moment? Is it frightening,
   or silly?
8. **Glyphs.** 🔦 🔋 ⚡ before any of them replaces the text labels.
9. **Phone.** LIGHT/SPRINT buttons on the right edge against the jump button. The first-person camera
   with a thumbstick. The perk terminal's prompt on a touch screen.
10. **Input.** Shift-to-sprint with `EnableMouseLockOption = false`, and F with no engine binding in
    the way.
11. **The trusted position.** With `TrustedSpeedFactor 1.35` and burst 3 s, is an honest walker or
    sprinter, on real replication, never throttled? (It has never been measured in this repo.)
12. **Teleports with `StreamingEnabled = false`.** The ride car and entry car land cleanly, with no
    clipping and no camera snap visible across the matching car interiors.
13. **Render cost.** 8 zones × at most 600 Parts, at most 25 PointLights each plus flashlights, 200
    dust emitters. Take `Stats` FPS, not a Lua frame counter (fork-tower §6: an MCP-driven Lua
    counter read 15 fps in an empty world).
14. **The reset path.** `Humanoid.Died`, then a respawn after `RespawnTime 3`, landing on `HubSpawn`
    with `Duration 0` (no ForceField).
15. **`BindToClose`.** Settlement and flushes for 8 players complete inside the shutdown window
    [DOC 30 s].
16. **Flicker replication.** Do 10 `Brightness` changes per room over 2 s look like a flicker and
    not a stutter on a real connection.
17. **Profile load time on join**, which gates the first run, against the "core action in 5 s" goal.
18. **The console.** Zero errors and warnings across a run, a death, an extraction, a purchase and a
    rejoin (the fork-tower §7 bar).

---

## 16. Cut from v1

Each item is cut rather than shipped thin.

1. **The stalking monster AI** (brief). Replaced by the blackout front (§1). A pursuer is the costliest
   solo system and the round-2 radar's explicit cut.
2. **Co-op / parties** (brief: "solo or with a small crew"). A shared run changes run ownership,
   death, payout splitting and the choice vote, and the change is a redesign rather than a flag, so
   nothing is scaffolded for it. v1 is one player per zone on a shared server with a shared hub.
3. **Audio.** There is not one `Sound`. It needs asset IDs this project does not have, and it is on
   the *Avoid solo* list. It is the first post-v1 item, and nightwatch-manor calls it that game's
   single biggest gap too.
4. **Leaderboards** (OrderedDataStore and an in-world board). Only `leaderstats.Deepest` ships.
5. **Perks from the brief:** starting keycard, shorter cooldowns, and Scavenger (measured to break
   the endless curve, §3). Five perks remain.
6. **Hazard variety:** door slams and lockdowns (they can seal a player in a dark dead end, which is
   unfair without a fairness proof), steam vents, flooding.
7. **Hiding spots and lockers.** There is nothing to hide from.
8. **Breakers / restoring power to rooms.**
9. **More than one room kit or biome.**
10. **Cosmetics, game passes, developer products, codes, badges** (§10).
11. **Daily or shared seeds.** Every sublevel is fresh (§4.1).
12. **Map, minimap, compass or exit indicator.** They would undo exploration and leak `maxD`.
13. **Jumpscares** (§2.6).
14. **A flashlight tool model and animations.** The flashlight is a `SpotLight` only.
15. **Killing the Humanoid on a dark death** (§2.5).

---

## 17. Store copy that must change before publishing

The brief's paste-ready description promises things v1 does not have. Before the experience is
created:

- Remove **"Dodge the stalker"** and the monster in the thumbnail brief; the figure in the
  thumbnail must read as the apparition.
- Remove **"🤝 SOLO OR CO-OP"**.
- Remove **"new perks & facilities added weekly!"**, which is a promise.
- Keep "procedurally generated", "permadeath roguelite", "permanent perks" and "5-10 min runs": all
  true of this design, and the last one measured (§5.3).

---

## Appendix A — The measurement rig

**Location:** `facility-nightmare/design-measure/`. A design tool, **not game code** (see the
`sim.luau` header).

- `sim.luau`: the prototype planner, model explorer and front.
- `Rng.luau` and `MazeGen.luau`: verbatim copies of `vault-runners/src/shared` (md5 `217e5d06…`,
  `c269d302…`).
- `m1`–`m11`: one file per measurement.

Run from that directory, with the scratchpad luau CLI:
`luau.exe m1_nofront.luau 2>&1`. M1, M7 and M9 were re-run from this directory after the copy and
printed byte-identical output to the first runs.

**Model parameters:** `CellSize 28`, `WalkSpeed 16`, door 0.5 s per first entry, 0.9 s per pickup
detour, `ExtraDoorChance 0.2`, onboarding fuse `d ≤ 2` on sublevel 1, `LeadSteps 2`.

| id | question | size | headline output (verbatim numbers) |
|---|---|---|---|
| M1 | Floor time with no threat | 3000 floors per shape | 4×4 F3: T p10 32.3 / p50 45.2 / p90 62.2 / max 87.2 s; maxD p50 7, max 15; first fuse p50 5.4 / p90 17.9 s with onboarding (8.6 / 22.4 without); doors/room 1.05. 5×5 F4: 54.5 / 74.3 / 96.6 / 133.8; first fuse 10.8 / 27.8; doors/room 1.09. 6×6 F5: 82.7 / 109.0 / 134.8 / 178.7. 7×7 F6: 117.2 / 148.8 / 181.3 / 235.0. |
| M2 | Seconds in the dark vs slack and speed | 2000 floors per cell | 4×4 slack 2.00: v16 p50 0.0 / p90 5.3; v12.8 2.0 / 10.9; v10.4 5.4 / 20.2; step p50 9.87. 4×4 slack 1.00, v10.4: 33.4 / 47.3. |
| M3 | Whole runs on 4/5/6-grid shapes | 1500 runs | Superseded by M4 (6×6 floors too long); kept for the record. Set A (cap 45, cell 15, slack 2.0→1.1): v10.4 mean cleared 4.76. Set B (cap 60, cell 20): v10.4 6.29. |
| M4 | 5×5 cap, slack → 1.0, thinning cells, perk magnitudes | 800 runs, to sublevel 30 | Base: v16 p50 15 cleared, P(10/15/20/30) = 0.94 / 0.56 / 0.22 / 0.01, run p50 1125 s; v12.8 p50 9, run p50 753 s; v10.4 p50 5, run p50 494 s, P(4/5/6/8) = 0.89 / 0.63 / 0.38 / 0.09. Scavenger +2 cells: v16 P(30) = 0.88. Cap 90 + grace 8.5 + 2 cells: v12.8 P(30) = 0.84. |
| M5 | v1 perk magnitudes and extraction economy | 800 runs | Median cleared (v16 / v12.8 / v10.4): none 15 / 9 / 5; Deep Cell ×3 20 / 11 / 7; Night Eyes ×3 16 / 9 / 5; Second Wind 18 / 10 / 6; all 25 / 12 / 8 (v16 P(30) = 0.21). Pay 10+5(k−1), keep 25%: best K 11 / 8 / 3 at 27.0 / 17.1 / 12.2 per min; v10.4 greedy K = 8 gives 4.7 per min. Keep 55%: v10.4 K = 8 gives 7.7, K = 3 gives 12.3. Flat 20: best K = 3 for all. 10+10(k−1): best K 12 / 8 / 4. |
| M6 | Step bounds and onboarding | 3000 floors / 2000 runs | Slack k = 1/3/4/8/9/30/100: 2.000 / 1.667 / 1.571 / 1.364 / 1.333 / 1.121 / 1.039. Step at k = 1 (4×4): min 4.05, p50 10.00. At k = 100 (5×5 F5): min 2.34, p1 2.80, p50 6.75. P(clear 1): v16 1.000, v10.4 1.000, v8 0.956. First fuse after arrival p50 / p90: 5.4 / 18.8, 7.3 / 26.3, 8.9 / 32.8. Entry room dark at p10 11.5, p50 20.0 s. |
| M7 | First-run hold | 3000 floors | P(clear sublevel 1), plain → held: v10.4 1.000 → 1.000; v8 0.959 → 0.990; v6.4 0.817 → 0.908. First darkness p10 / p50 with hold: 17.1 / 28.2, 18.1 / 29.7, 19.3 / 31.1 s. |
| M8 | First run pushed until death | 2000 runs | Sublevel-1 seconds to the elevator p10 / p50 / p90: v16 33 / 45 / 63; v10.4 45 / 64 / 90; v8 56 / 79 / 113. Cleared p50: 15 / 5 / 3. Banked p10 / p50 / p90: 96 / 168 / 343; 11 / 25 / 43; 6 / 11 / 17. Run minutes p50: 20.4 / 8.8 / 6.1. |
| M9 | `ExtraDoorChance` 0 / 0.2 / 0.4 | 2000 plans per size, 800 runs | Dead-end rooms 18% / 13% / 8%. Model p50 4×4 46.5 / 45.2 / 43.5 s; 5×5 76.4 / 73.4 / 68.2 s. Mean cleared v12.8: 6.78 / 8.77 / 10.07; v10.4: 4.16 / 5.16 / 6.08. |
| M10 | Apparition trigger (a walked-through room dark beside a lit player room) | 2000 floors | Sublevel 1 first run: 27% / 52% / 70% of floors (v16 / v10.4 / v8), p50 40.8 / 53.1 / 63.0 s. Sublevel 2: 55% / 85% / 99%, p50 34.6 / 46.4 / 53.1 s. Sublevel 4: 79% / 98% / 100%, p50 52.7 / 67.7 / 80.0 s. The rejected "door opened into a dark room" trigger (same file, reading `firstDarkEntry` instead of `firstDarkBehind`; `sim.luau` returns both): sublevel 1 6% / 28% / 45%, sublevel 2 25% / 61% / 86%, sublevel 4 60% / 90% / 100%. |
| M11 | Does sublevel 1 always have an onboarding-fuse candidate? | 20 000 plans | Plans with no candidate: 0. Smallest `maxD` seen: 5. |

**What the rig does not model**, so no number above covers it: sprint; a player changing route
toward light; flashlight waste in lit rooms; hesitation other than as a slower walk; humanoid
physics and collision; replication latency; the trusted-position throttle; props blocking movement.
It also consumes a battery cell even at a full battery, where the game leaves it in place (§2.4), so
it is pessimistic there.
