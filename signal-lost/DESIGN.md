# SIGNAL LOST: Derelict Station — design spec (v1)

**Status: built (v1, 2026-10-01) and headless-tested; see `CLAUDE.md` for the gates and `EYECANDY.md` for what
changed against this spec (§2.3: the exterior's placement). `REVIEW-1.md` (2026-10-01) changed §5.1 adaptation 4,
§5.3's interval (now 55–85 s), §6's rest-while-threat note, §8.2 (`CreditSeconds`), §8.5 and §14 (AIR also charges
the trusted vacuum distance; a closing session never ticks; `BuyUpgrade` replies; prompt buttons); each says so.**
Never opened in Studio, not published, no universe. Written 2026-09-30 as a spec; the rest is the spec as written.

**Built from:** `docs/game-radar/2026-09-23-roblox-game-radar.md`, concept brief §1 (line 71) and ranked
entry #1, with three changes the task set: the threat is environmental and scripted (no chasing AI),
oxygen is the clock, and the station has zero-g sections and signal-repair objectives.
**Measured against:** `docs/complete-game-standard.md` (the finish line), `docs/new-game-checklist.md`
(the traps), `robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md` (the seed leak),
`anomaly-observatory/CLAUDE.md` ("ServerStorage, not the zone"), `plus1-jump/EYECANDY.md` and its
`EnvBands` / `Hazards` / `Rest` templates, `facility-nightmare/DESIGN.md` and `EYECANDY.md` (the
closest sibling, and how a room game adapted the templates), and `deep-vein/` (the layout).

---

## 0. How to read the numbers in this file

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M1]..[M9], [M3b], [M7b]** | Measured by this spec's rig, `signal-lost/design-measure/` (Appendix A). Re-runnable, deterministic seeds. |
| **[REPO]** | Measured earlier in this repo, with the file named. |
| **[ARITH]** | Arithmetic from a measured, documented or chosen number, shown inline. |
| **[DOC]** | Roblox documentation. **Not measured here.** |
| **[STUDIO]** | A starting value only Studio or real players can confirm. It is on the §20 list. |

**What the rig models.** A prototype sector planner (the real `MazeGen`, the planned stream order) and a
**model explorer** that walks each sector blind, remembers every module it has seen, knows the air or
vacuum behind every hatch it has seen (the hatch light, §2.2), keeps exact track of its oxygen, retreats
to air when a step would leave it unable to get back, and uses the signal meter when it is in range.
A **campaign model** plays sectors 1, 2, 3, … with that explorer, banks salvage, buys upgrades
greedily and counts minutes.

Human play is stood in for by three **profiles** (proxies, not measured people):

| profile | speed factor (air / vacuum studs/s) | ignores the signal meter | unsafe decisions (skips its own O2 check) | safety margin |
|---|---|---|---|---|
| fast | 1.0 (16 / 12) | 0 % of decisions | 2 % | 2 s |
| medium | 0.8 (12.8 / 9.6) | 30 % | 5 % | 3 s |
| slow | 0.65 (10.4 / 7.8) | 60 % | 10 % | 4 s |

- **Optimistic:** perfect memory; exact O2 arithmetic, including the cost of getting back; reads the
  relay's exact straight-line distance inside the meter's range (the HUD shows 5 coarse bars); never panics.
  **So the model's death rates are a floor, not an estimate.**
- **Pessimistic:** never routes to an O2 canister on purpose, never uses the hypoxia grace on purpose,
  ignores the meter on a share of decisions by construction.
- **Not modelled:** hazards' time cost, the low-gravity hop (a flat 1.2 s per salvage), physics and
  collision, replication and the trusted-position throttle, hub time between sessions.

§20 item 1 is the playtest that replaces the proxies. When real session data exists, refit the
profiles first, then re-run M3 and move the numbers in §3 and §7.

---

## 1. The core loop, in one paragraph

You are the engineer on a lifeboat docked to a dead space station whose signal has gone silent. A lift
drops you into **Sector 1**, a small grid of station modules generated a moment ago. Some modules still
hold **air**: gravity, light, a full tank. Others are **breached**: open to space, gravity almost gone
(you drift), and your suit's **AIR** ticks down one second per second. The light over every hatch tells
you what is behind it, **green for air, red for vacuum**, so you plan a route from air pocket to air
pocket. Your suit's **SIGNAL** meter (five bars) gets stronger as you get closer to the sector's
**relay**. Grab the **salvage** floating in the breached modules, reach the relay, and it splices itself:
the sector's lights come back, your salvage is banked, and a hatch in the floor opens into the next,
larger, emptier sector. Run out of air and after five seconds of hypoxia you **black out**: you wake at
the sector's entrance with half of what you carried banked, and the sector has rebuilt itself into a new layout.
Salvage buys a bigger **Air Tank** and **Mag-Boots** at a fabricator. Relay 30 is the **Main Array**: splice
it and the signal goes home (about 37 minutes at the medium proxy). Then something answers, from deeper in
the station, and the sectors go on without end. A public and friends board ranks **relays restored**.

### How this differs from the brief, and from FACILITY: Endless Nightmare

**Changes to the brief:**
- **No Entity.** The brief's stalker (pathfinding, patrol/investigate/hunt) is cut. The threat is the
  vacuum, the tank and a handful of rare scripted drifting hazards (§5). A pursuer is the costliest solo
  system, and nightwatch-manor's was faster than the player through every green test.
- **No stamina, noise or hiding spots.** There is nothing to hide from.
- **No keycards or signal fragments.** One objective per sector, the relay, found by following the signal.
- **Persistent progress instead of a permadeath run.** Your relay chain is a checkpoint that never resets.

**Against facility-nightmare**, the procedural horror facility already in this repo:

| | FACILITY: Endless Nightmare | SIGNAL LOST |
|---|---|---|
| the clock | a world clock: the blackout front spreads room by room and dooms the whole floor | a personal clock: your tank drains only in vacuum and refills in any air module, so nothing in the world runs out |
| where the danger is | everywhere, eventually | fixed per module and shown on every hatch before you open it |
| movement | first person, walk and sprint | third person, walk in air, low-gravity drift and hops in vacuum |
| objective | collect N fuses, carry them to the farthest room | follow a signal meter to one relay |
| structure | permadeath runs, EXTRACT or DESCEND, perks between runs | a persistent relay chain; blackout costs one sector attempt and half your carried salvage |
| setting | a lab facility underground | a space station in orbit, a planet outside every cracked viewport |
| progress board | `leaderstats.Deepest` only | public and friends OrderedDataStore board |

---

## 2. The rules of a sector

### 2.1 Modules and hatches

- **A sector is a square grid of modules** (3×3 up to 6×6, §3). Each module is a 32-stud cube room with a
  floor, a ceiling, four walls and a light. Neighbouring modules connect through **hatches**.
- **Only opened modules exist.** On arrival only the entry module, the **dock**, is built. A module is built
  the moment a hatch into it opens, and a hatch opens by itself when the server's trusted position (§14)
  comes within `HatchOpenRadius` of it from the adjacent module. There is no prompt (the round-2 radar:
  players reject "Hold E simulator" horror). Hatches stay open.
- **A hatch leaf into an unbuilt module is always present and closed**, never a hole into the void.
- **The dock** is the sector's entrance. You arrive through a hatch in its ceiling. It holds the
  **RETURN** console (back to the lifeboat, §2.7).

### 2.2 Air and vacuum

- **Every module is air or vacuum**, decided when the sector is generated (§12).
  - **Air module:** normal gravity, `WalkSpeed` 16, a warm white light, and your tank refills.
  - **Vacuum module (breached):** 20 % gravity, `WalkSpeed` 12 plus Mag-Boots, a dim red emergency light, a
    cracked glass viewport in the ceiling showing space, and your tank drains.
- **The hatch light** on the built side of a hatch into an unbuilt module is **green for air, red for
  vacuum**. It is public by design: the danger is shown before you step into it. It says nothing about
  which module holds the relay, except that the relay is always in an air module (§2.4), which the game
  tells you in its first hint.
- **The dock and the relay are always air.** On sector 1 every module next to the dock is vacuum, so
  the first hatch teaches the gauge (§16).
- **Reach rule:** in every sector, every vacuum module is at most `reach(k)` hatches from an air module
  (§3). It depends on the walls and the air map only, never on the relay (§12).

### 2.3 AIR, hypoxia, canisters

The server ticks every `ServerTickSeconds` and owns all of this. The client only displays it.

- **AIR** is a number of seconds, capped at the tank (20 s, up to 40 s with the Air Tank).
- In a **vacuum** module it drains 1 per second. In an **air** module it refills to full in
  `RefillSeconds`, whatever the tank size.
- **At 0 AIR you are hypoxic:** the screen tunnels, and after `GraceSeconds` without reaching air you
  **black out** (§2.6). Reaching any air module, or taking a canister, ends hypoxia at once.
- **O2 canisters** float in vacuum modules. Taking one adds `CanisterSeconds`, up to the tank. At a full
  tank a canister is **not** taken: it stays where it is and the HUD says `AIR FULL — canister left here`.
- Pickups are automatic: within `PickupRadius` of the item horizontally, in the item's module by trusted
  position, and inside the item's height window (§8.1).

### 2.4 The signal and the relay

- **Each sector has exactly one relay, in an air module far from the dock** (§12). Its location is
  server-only until its module is built.
- **The SIGNAL meter** shows `bars = clamp(5 − floor(d), 1, 5)`, where `d` is the straight-line distance in
  modules between the centre of the module you are in (by trusted position) and the relay's module centre.
  Five bars: you are in the relay module. Four: next to it (d = 1 or 1.41). One bar: four modules or more away.
  The server computes it and pushes it on every module change.
- **The splice is automatic.** When your trusted position comes within `SpliceRadius` of the relay mast, a
  `SpliceSeconds` splice plays and completes (you are in air, nothing can interrupt it). Then, in one step:
  1. carried salvage is banked, plus `bonus(k)` (§9);
  2. `best` becomes `k` and `bestAt` the server's time;
  3. the profile is written (§11) and the board entry queued (§10);
  4. every built module's light in this sector turns on at full (the payoff);
  5. a hatch opens in the relay module's floor, and its fabricator console and RETURN console wake up.
- **Transit:** walk onto the open floor hatch and a `TransitSeconds` ride carries you into sector `k+1`'s dock.
  During the ride the server destroys the old sector and builds the new dock out of sight.

### 2.5 Salvage

- Salvage pieces float in vacuum modules, glowing amber. Some float low (take them walking), some higher (a
  low-gravity hop). Each piece is worth `value(k)` (§9).
- **Carried salvage is banked only at a splice.** It is shown as `CARRIED n` beside `SALVAGE total`.

### 2.6 Blackout

- After `GraceSeconds` at 0 AIR: a `BlackoutBeatSeconds` fade and the card **SIGNAL LOST — you blacked out.
  Kept 17 of 35 carried salvage.** Then you wake in the same sector's dock, and the sector has been
  **generated again from fresh entropy** (§12): new walls, new air map, new relay.
- **A blackout does not kill the Humanoid.** It is a fade and a server move, which keeps it out of the
  engine's respawn cycle (SPAWN-ORDER §7 says `robloxemu` does not model that cycle).
- `floor(carried × keep)` is banked, `keep = 0.5`. `blackouts` and `attempts` count up.

### 2.7 Leaving a sector before its relay

**One rule for every way out: a sector left unspliced banks `floor(carried × 0.5)`.**

| way out | what triggers it |
|---|---|
| blackout | §2.6 |
| return | the RETURN console in the dock (after a splice, the relay room has one too) |
| reset | `Humanoid.Died` during a sector: the Roblox Reset button, or falling out of the world |
| left | `PlayerRemoving` |
| shutdown | `game:BindToClose` |
| crashed | the next load finds `open` in the profile (§11.1) and settles it the same way |

All call one idempotent `endSector(plr, reason)`. It settles the instant the cause is known, before any
presentation. Leaving, resetting or crashing pays exactly what a blackout pays, so none of them is a way
out of a bad sector (§14). M8 measures leaving early paying 3.8–5.7 × less per minute than splicing.

### 2.8 The lifeboat (the hub)

A shared 60 × 40 × 16-stud bay at the world origin: the `HubSpawn`, the **LIFT** 12 studs ahead of it,
the **board** (§10) on the wall the spawn faces, a **fabricator** console, two benches (real `Seat`s, §6),
and a wide window onto the planet and your own station's relay beacons (client-side art, one lit beacon
per relay you have restored; the dish lights up once you have restored the Main Array).

- **The LIFT** takes you to sector `best + 1`'s dock (a fresh layout every time). Stand in it for
  `BoardingSeconds`, then a `TransitSeconds` ride.
- **The fabricator** (hub, and every relay module after its splice) opens the upgrade panel (§9).

---

## 3. The difficulty schedule

The schedule is aligned with the environment bands (§4), so a new band is also a new challenge.
`n` = grid size, `breach` = chance a module other than the dock is vacuum before the reach rule,
`reach` = the reach rule's limit (§2.2).

| sectors | band | n | breach | reach | salvage | canisters | why |
|---|---|---|---|---|---|---|---|
| 1 | Docking Ring | 3 | 0.35 | 1 | 2 | 1 | Onboarding: every dock neighbour is vacuum and the first salvage floats next door (§16). Splice p50 20.1 / 24.5 / 29.8 s (fast / medium / slow), P(splice) 1.000 for all three [M1]. |
| 2 | Docking Ring | 3 | 0.35 | 1 | 2 | 1 | Same shape without the onboarding rules. |
| 3–4 | Docking Ring | 4 | 0.45 | 2 | 3 | 1 | P(splice) 1.000 / 1.000 / 0.995 perk-less at k = 3 [M1]: the first real vacuum stretches, still almost no deaths. |
| 5–9 | Hydroponics | 4 | 0.55 | 2 | 3 | 1 | P(splice) 1.000 / 0.999 / 0.990 at k = 5 [M1]. Hazards start here (§5). |
| 10–15 | Cargo Spine | 5 | 0.60 | 3 | 4 | 2 | The first tank pressure: perk-less P(splice) 0.990 / 0.947 / 0.883 at k = 10, with O2 below a quarter of the tank on 27 / 30 / 41 % of attempts [M1]. By sector 10 the medium proxy owns 2 upgrade ranks [M3]. |
| 16–22 | Reactor Ring | 5 | 0.65 | 3 | 4 | 2 | Perk-less P(splice) 0.987 / 0.921 / 0.823 at k = 16 [M1]. |
| 23–30 | Array Spine | 6 | `0.95 − 0.30·0.97^(k−23)` (0.650 → 0.708) | 4 | 5 | 2 | The largest grid. Perk-less 0.942 / 0.844 / 0.718 at k = 23, 0.904 / 0.752 / 0.583 at k = 30 [M1]; with half the upgrades 0.978 at k = 30 for the medium proxy [M4]. |
| 31–59 | The Deep | 6 | same formula (0.715 → 0.850) | `min(10, 4 + (k−23) // 8)` (5 → 8) | 5 | 1 | Beyond the brag. Air pockets thin and vacuum stretches grow. |
| 60+ | The Echo | 6 | same formula (0.853 → 0.95) | same (8, then 10 from sector 71) | 5 | 1 | The endless end. |

**The curve keeps falling, even with every upgrade** [M4], medium proxy, all 8 ranks bought:

| sector | 30 | 40 | 60 | 80 | 100 | 150 | 250 |
|---|---|---|---|---|---|---|---|
| P(splice) per attempt | 1.000 | 0.989 | 0.930 | 0.871 | 0.791 | 0.728 | 0.700 |
| slow proxy | 0.993 | 0.944 | 0.833 | 0.725 | 0.645 | 0.551 | 0.505 |

Breach approaches 0.95, so some air always survives, and reach caps at 10: with both upgrades maxed a vacuum
module 10 hatches from air is 10 × 2.0 s + 10 × 0.5 s of hatches = 25 s away, inside the 40 s tank [ARITH], so
no module is ever out of reach one way. The curve therefore approaches a limit rather than zero: the deep end
is a skill ranking, not a wall.
Perk-less at sector 60 the medium proxy splices only 0.359 of attempts [M4].

**Why these knobs and not others** [M2, at k = 10 and 23, perk-less, medium]:
- The tank is the strongest lever: `TankBase` 15 / 20 / 25 / 30 gives P(splice) 0.656 / 0.832 / 0.904 / 0.957 at k = 23.
- Vacuum speed is the second: `VacSpeed` 10 / 12 / 14 / 16 gives 0.713 / 0.832 / 0.890 / 0.952.
- `ExtraDoorChance` 0 / 0.2 / 0.4 gives 0.586 / 0.832 / 0.958. Kept at 0.2, facility-nightmare's measured
  value [REPO `facility-nightmare/DESIGN.md` §5.1]: loops stay rare enough that dead ends are decisions.
- `RefillSeconds` 1 / 2 / 4 and `CanisterSeconds` 5 / 10 / 15 barely move anything (0.832 / 0.832 / 0.832 and
  0.829 / 0.832 / 0.833), so they are feel numbers, not balance numbers (§8).

**What is not in the schedule, deliberately:** no timer, no drain multiplier and no world clock. Nothing
gets harder while you stand still.

---

## 4. Environment bands (eye candy)

### 4.1 What triggers them

**The trigger is the sector number, the game's own progress.** You cannot stand in sector 23 without
having spliced 22 relays. The band **name** (banner, ride card, hazard kind) follows the integer sector `k`,
the number the HUD and the board show, so they always agree. The **blend** follows
`p = (k − 1) + visited / n²`, where `visited` is how many of this sector's modules you have opened: it
creeps forward as you explore. `visited` and `n` are public, so the blend leaks nothing.

**The game's logic:** sectors go deeper into the station and further round its ring. The station's
systems change on the way down (docking, farms, cargo, power, communications, the structure nobody
mapped), and the planet outside turns from day to night to eclipse. The Main Array is the comms dish at
the end of the Array Spine; the Deep and the Echo lie past it.

**Transitions never cut.**
- In `p` units a band's `from` is its first sector minus 1 (0 / 4 / 9 / 15 / 22 / 30 / 59, so the first is 0 as
  `EnvBands.validate` requires), and `fade = 1`: each band blends in, with EnvBands' smoothstep, over the whole
  previous sector as you explore it.
- Foreshadowing, facility-nightmare's rule [REPO `facility-nightmare/EYECANDY.md` §2]: in the sector before
  a band, a module wears the next band's dressing kit when `hash01(k, moduleId) <` that band's blend weight,
  so the farms creep into the docking ring before you arrive.
- The transit ride (3 s) is the cut point for the grade, which glides with EnvBands' `approach` on a 0.6 s
  half-life (plus1-jump's `Env.HalfLife` [REPO]): five half-lives inside the ride [ARITH].
- The ride names it: `SECTOR 10 — CARGO SPINE`, with the band's flavour line.

### 4.2 The seven bands

Reached = minute of play the band's first sector is entered, p50 [M3] (fast / medium / slow).

| # | band | sectors | reached | outside the viewport | grade and palette | dressing (client) | critters (harmless, never collide) | weather | hazard |
|---|---|---|---|---|---|---|---|---|---|
| 1 | DOCKING RING | 1–4 | 0 | the planet's day side, huge and blue-white | cold white-blue; white panels, blue trim | suit lockers, cargo netting, handrails, tool racks, placards | tools and bolts tumbling slowly in vacuum modules | frost motes | none |
| 2 | HYDROPONICS | 5–9 | 2.0 / 2.5 / 3.0 min | the sunlit limb | soft green; pale green panels, dark wet floor | plant racks under magenta grow lamps, vines, seed trays, strapped water bladders | glow moths (escaped test insects) in air modules | mist and floating droplets | WATER GLOBE |
| 3 | CARGO SPINE | 10–15 | 5.1 / 6.5 / 8.4 | the station's own trusses and a drifting cargo pod | dusty amber; grey steel, hazard stripes | crates, container stacks, cargo nets, ceiling rails | maintenance drones gliding on ceiling rails, scripted loops that never turn toward the player | dust | LOOSE CRATE |
| 4 | REACTOR RING | 16–22 | 10.9 / 14.3 / 18.8 | the terminator: a red line of sunset on the planet | warm orange, high contrast; dark bronze metal | coolant pipes with glowing bands, heat vents, gauges (`CORE 88%`) | ember wisps | embers and heat shimmer | SLAG BLOB |
| 5 | ARRAY SPINE | 23–30 | 17.6 / 22.8 / 30.2 | the night side with aurora; **the Main Array dish grows in the viewport as you approach sector 30** | cool blue-violet; navy panels, cyan trim | antenna parts, cable bundles, screens showing the signal's waveform | small satellites drifting outside | blue static sparks | PANEL SHARD |
| 6 | THE DEEP | 31–59 | 28.5 / 36.9 / 49.3 | eclipse: the planet a black disc ringed with light | near-black, cold, desaturated; frosted dark steel | ice on walls, frozen fluid, dead screens | meteors crossing outside | ice glints | ICE CHUNK |
| 7 | THE ECHO | 60+ | 69.6 / 95.3 / 131.8 | a violet nebula; the planet gone behind you | violet; screens pulse with the answering signal | panels that flicker in time with the echo | dark shapes crossing **outside the viewport only**, never inside a module (dread through wrongness, never a chaser) | violet static | STATIC ORB |

Every band after the first lasts at least 3.1 minutes at every proxy (the shortest is Hydroponics for the fast
proxy, 2.0 → 5.1 min) [M3, from the reached column]. Band 1 lasts 2.0–3.0 min because it is the tutorial.

### 4.3 Fairness rules for the art

The art is client-side (as in facility-nightmare: the server builds the structure, the client dresses
and recolours it on this client only). It must never change what the player needs to read:

- **Nothing covers an item or a hatch.** Wall pieces stay within 2.5 studs of a wall and 4 studs off every
  doorway line (one character hull, the facility-nightmare rule [REPO]). Nothing stands in the item volume.
- **The four signal colours stay unique:** the amber salvage glow, the cyan canister glow, and the red and
  green hatch lights. No glowing dressing within 30° of hue of any of them within 8 studs of a hatch or
  item (facility-nightmare's hue rule [REPO]). `EnvConfig.spec` checks every palette.
- **A palette may change hue, not how much light a surface returns**: 60–100 % in linear light
  (facility-nightmare's review finding 1 [REPO]), so a band never hides a hatch.
- **Critters and weather never enter the play path:** exterior life stays outside the viewport glass; interior
  critters are non-collidable, cross above head height or along walls, and never move toward the player.
- **Nothing but a hazard looks like a hazard.** No dressing drifts toward the player, none carries a red ring, and no
  band's dressing copies its own hazard kind loose (Cargo's crates are strapped down; Hydroponics has no free water
  globes). A thing coming at you is always a hazard, and a hazard always has its ring.
- **Budgets are caps in code** and measured headless at every band and every seam (plus1-jump's rule):
  - at most 10 local dressing parts per built module and 300 in all, farthest modules culled first. A 6×6
    sector's players open 61–67 % of its 36 modules at the median [M1], about 24, so 300 leaves a fifth spare
    [ARITH];
  - 4 active emitters, at most 2 of them weather through `EnvBands.capRates`, 3 client lights and 1 hazard:
    plus1-jump's `Config.Budget` [REPO];
  - at most 45 exterior parts: one client-side model far from every zone, seen through every viewport and the
    lifeboat window (planet and atmosphere 2, dish 8, 30 relay beacons, 5 spare) [ARITH].

  These are starting caps; §20 item 6 measures the frame cost.

---

## 5. Hazards

Rare, themed, telegraphed, one at a time, and the red ring is exactly the hit zone.

### 5.1 The rule set (from `plus1-jump/src/shared/Hazards.luau`, kept verbatim where possible)

Copy the file and its spec at build time and record the md5 in `EYECANDY.md`: the template changed while this spec
was written (md5 `f36a9ac2…`, modified 2026-09-30 22:48). `Rest.luau` (`19226cb6…`) and `EnvBands.luau` (`c6fc63a1…`)
did not.

**Kept verbatim:** a clock that freezes and never resets; one hazard at a time; a straight lane that starts on
screen within the camera's view window, re-aims at the player while the warning runs and **locks** `commit`
seconds before arrival; the **zone rule** (a hit needs the player inside the ring when the lane passes, so
stepping out of the ring in any direction dodges); a swept hit test; a capped horizontal knock.

**Adapted, each because the genre needs it:**

1. **Where the clock runs.** Only in a vacuum module, in a band that has hazards (Hydroponics on), after the
   sector's first `ArrivalGraceSeconds`, while AIR ≥ `LowO2Seconds`. Air modules are the safe places and the
   rest places (§6); a hazard must never add to a player about to black out ("a hit costs a little, never a
   run"); and the dock arrival belongs to the hint.
2. **The lane starts inside the module.** plus1-jump's lanes fly in from open sky; a module is a 32-stud box.
   The start is clamped to the module's interior; when clamped, the lane is shorter and the drift slower,
   and the arrival time is unchanged, so the warning never shortens. Kinds are slow by design (6 studs/s ×
   3 s = an 18-stud lane [ARITH], inside the 30-stud interior): zero-g debris drifts, it does not fly.
3. **A due hazard waits for the player to stand still** (horizontal speed ≤ 4 studs/s: a pickup, a hatch
   cycling, a look around, landing from a hop), for at most `WaitForStillSeconds` of eligible time.
   facility-nightmare measured why: a hazard aimed at a player who keeps walking lands behind them unseen
   (6 of 534 bursts within 8 studs of its walking bot [REPO `facility-nightmare/EYECANDY.md` §3]). Aimed at a
   player who has stopped, the debris comes at them from ahead, the ring is at their feet, and one step is a
   visible near-miss.
4. **Leaving its module locks the lane; leaving the sector calls it off** (REVIEW-1). A lane may not follow a player
   into another module (an air module never has hazards), so the moment the player is in another module of the same
   sector the lane locks and the debris finishes its flight through the ring they left: a near-miss behind them, with
   the banner turned to `YOU ARE CLEAR`. The spec first called it off there, and on the real client path that made 111
   of 112 warnings vanish mid-telegraph (a player in vacuum keeps walking, and the next hatch is 2–3 s away). A
   transit, a blackout or RETURN calls it off, as does a new sector (`ctx.sector`).
5. **The first hazard of a session is due after 30 s of eligible time**, then every 55–85 s (§5.3): without it the
   first hazard lands at minute 6.0–6.8 p50, half a band late; with it, at minute 3.3 / 3.7 / 4.2, in sector
   7 / 6 / 6, early in Hydroponics [M7b].

A hazard is **client-side**, as in plus1-jump and facility-nightmare: it only ever touches the local player,
whose physics the client owns, and a hit costs no AIR, salvage or progress. The server never hears of it. A
client that deletes its hazards gains the second a dodge costs.

### 5.2 Kinds

| kind | band | the look | telegraph | commit | speed | ring radius (hitRadius + 1.5) | knock (studs/s) | lift |
|---|---|---|---|---|---|---|---|---|
| WATER GLOBE | Hydroponics | a wobbling sphere of water drifting at you | 3.2 s | 1.5 s | 5 | 3.5 | 14 | 0 |
| LOOSE CRATE | Cargo Spine | a crate tumbling end over end | 3.0 | 1.5 | 6 | 3.7 | 18 | 1 |
| SLAG BLOB | Reactor Ring | a glowing orange molten blob | 3.0 | 1.5 | 6 | 3.5 | 18 | 0 |
| PANEL SHARD | Array Spine | a spinning blue solar-panel shard | 3.0 | 1.5 | 6 | 3.7 | 20 | 1 |
| ICE CHUNK | The Deep | a frozen chunk trailing ice | 3.0 | 1.5 | 6 | 3.7 | 20 | 1 |
| STATIC ORB | The Echo | a crackling violet orb | 3.4 | 1.5 | 5 | 3.5 | 16 | 0 |

- **Pass** (flight after arrival) is 1.6 s for every kind, so the longest flight is 3.4 + 1.6 = 5.0 s (§6).
- **Telegraph ≥ 3 s and commit 1.5 s** are the template's minimums (`MinTelegraphSeconds`, `MinCommitSeconds`
  [REPO `plus1-jump/src/shared/Config.luau`]).
- **Escape:** the widest ring's radius is 3.7 studs; at the slowest walk the model uses in vacuum (the slow
  proxy's 7.8 studs/s) that is 0.47 s, at 12 studs/s 0.31 s [ARITH], inside the 1.5 s after the lock.
  `Hazards.validate` enforces `ring / 7.8 + 0.5 s reaction ≤ commit` for every kind.
- **Knock ≤ 20 and lift ≤ 1**: under 20 % gravity a lift of 1 stud/s is a 0.01-stud rise (1² / (2 × 39.24))
  [ARITH]; the shove is horizontal and the walls and ceiling glass are solid, so a hit can never carry anyone
  out of the station. Feel is §20 item 7.
- In third person (the default camera; §15) the ring at your feet and the debris ahead are both in view.
  facility-nightmare, in first person, needed a HUD banner because its rings were out of view; the banner stays
  here anyway: `LOOSE CRATE — STEP OUT OF THE RING`, then `LOOSE CRATE — YOU ARE CLEAR`.

### 5.3 Measured rate

| interval (eligible s) | one hazard per … min of play in hazard bands (fast / medium / slow) | share of that play that is eligible |
|---|---|---|
| 60–90 | 2.05 / 1.98 / 1.93 | 0.62 / 0.64 / 0.65 |
| 80–120 (chosen for v1; REVIEW-1 replaced it, below) | 2.75 / 2.64 / 2.58 | same |
| 100–150 | 3.45 / 3.31 / 3.22 | same |

[M7]. In the rig, 80–120 s lands inside the standard's "about one near-miss per 2–3 minutes". Per band (medium): one per
3.2 min in Cargo, 3.0 Reactor, 2.8 Array, 2.4 Deep, 2.3 Echo; Hydroponics only gets its first one or two
(7.3 min per hazard over its short stretch) [M7]. M7 does not model adaptation 3's wait: if every hazard
waited its full 15 s, the effective interval would be 95–135 s, between the measured 80–120 and 100–150 rows,
so one per 2.6–3.3 min of play [ARITH]. Whether each is a **near-miss** depends on the player standing still when
it comes; adaptation 3 makes that the usual case, and §20 item 7 counts it for real.

**Measured on the real client path (REVIEW-1 finding 5), and the interval changed to 55–85 s.** The rig's eligible
share (0.62–0.65) was too high: through the real `Env.client` it is 0.50–0.57 (the second reviewer, 12 campaigns), so 80–120 s gave one warning per
2.98–4.32 min of play at k ≥ 5 (9 campaigns from join to relay 30; hub, rides and relay rooms included), outside the
standard's 2–3. At **55–85 s** it is one per **2.32–3.08 min, median 2.54** (47 campaigns, bot speed 1.0 / 0.8 /
0.65), 8–12 warnings per campaign, the first in sector 5–11. `robloxemu/check_signallost_campaign.luau` measures it
on every run (one campaign; 1.8–3.3 passes, the standard's "about").

---

## 6. Rest (pause)

A Roblox server cannot stop the world for one player. In SIGNAL LOST nothing in the world runs out: the
tank drains only in vacuum. So **rest is allowed wherever there is air**, in the lifeboat and in any air module
mid-sector, and it pauses exactly what the template pauses: the hazard clock.

- **REST button** (top edge, §15) or keyboard **R** / gamepad **ButtonX**: you sit down where you stand, the view
  softens, the HUD reads `RESTING — the air here holds. Nothing is lost, nothing is earned. Move to go on.`
- **Idle rest:** stand still in air for `Rest.IdleSeconds` = 20 s (the template's value [REPO]).
- **In the lifeboat** the two benches are real `Seat`s, as in facility-nightmare.
- **In vacuum it is refused, with the reason:** `No air here — rest where the hatch light is green.` It is not
  queued, because you cannot rest without moving to air, and moving drops a queued request.
- Any movement wakes you (`WakeOnMove`, `WakeGraceSeconds` 0.4, the template's values [REPO]).
- The template's `BlockWhileThreat` stays (`Rest.validate` requires it) with `PendingSeconds` = 7: the longest
  flight is 3.4 s telegraph plus 1.6 s passing, plus 2 s to stand still [ARITH, the template's sizing rule]. Here
  it fires for up to about 5 s after a player walks out of a hazard's module into air, while the debris finishes its
  flight (§5.1 adaptation 4, REVIEW-1): REST asked for then is queued and **said** (`Resting as soon as the debris
  has passed.`), and starts once the flight is over.

**Why it can never be an exploit**
1. **There is nothing to pause.** No world clock, no round, no front. The tank refills in air whether you rest or
   not, so resting in air changes no number the server keeps.
2. **Rest cannot happen where anything drains.** `Rest.validate` refuses a config that allows vacuum
   (adapted template: `AllowedIn = { hub = true, air = true }` is required), and the client asks the pushed
   state which module type you are in.
3. **Hazards never happen where rest is allowed**, so rest cannot dodge one, and the clock freezes, never resets
   (plus1-jump measured identical counts with and without toggling [REPO `plus1-jump/EYECANDY.md` §4]).
4. **Nothing is earned by time.** Salvage comes from pickups and splices only.
5. **The idle disconnect.** Roblox disconnects a player idle for about 20 minutes [DOC]. Leaving mid-sector banks
   half of what you carry (§2.7). After `Player.Idled` fires (about 2 minutes idle [DOC]) the rest line adds
   `Idle for 20 minutes and Roblox disconnects you: you would keep half of your 35 carried salvage. Splice the relay to keep it all.`
6. **Rest is client presentation.** The server never hears of it (except the benches, which are Seats). A modified
   client that "rests" in vacuum pauses its own hazards and nothing else, and its AIR still drains on the server.

---

## 7. The brag moment and the long-term goal

### 7.1 Relay 30: the Main Array

Relay 30 is the station's **Main Array**. Its relay module is a special kit: a control room with a glass
ceiling under the giant dish (the dish is client-side art outside the zone), which has been growing in
the viewports all through the Array Spine.

**Splicing it:**
- the splice runs as always and banks as always;
- on the splicing player's screen (6 s): the dish swings toward the planet, a beam fires into space, all 30
  relay beacons along the station's hull light in sequence, white flash and FOV punch, title card
  **SIGNAL SENT** — `Relay 30. The Main Array is transmitting.`; three seconds later static, and
  `…something answered.`;
- **every player in the server** gets a toast: `★ <DisplayName> restored the MAIN ARRAY`;
- the board shows ★ beside every name with `best ≥ 30`; the lifeboat window shows your dish lit;
- `arrayAt` is written once, in the splice's write (§11).

**When it lands** [M3, 400 campaigns per proxy, minutes of play until relay 30 is spliced]:

| proxy | p10 | p50 | p90 |
|---|---|---|---|
| fast | 25.6 | 28.4 | 31.3 |
| **medium** | **33.0** | **36.9** | **41.3** |
| slow | 43.5 | 49.2 | 55.7 |

The medium proxy's whole 10–90 % range sits inside the standard's 30–45 minutes. Fast players get there
slightly early and slow ones slightly late; §20 item 1 decides whether real players are nearer fast or slow.
`tests/Pacing.spec.luau` re-runs this on the real module and asserts medium p50 in 30–45 min, so a retune that
moves it fails loudly.

### 7.2 Beyond it

- **THE DEEP (31–59)** and **THE ECHO (60+)**: the answering signal comes from deeper in the station, and the
  sectors never end. Sector 60 is entered at p50 69.6 / 95.3 / 131.8 min [M3], announced with
  `THE ECHO — the answer is coming from here.`
- **The endless curve** (§3) keeps falling with every upgrade, so the board keeps separating players.
- **The upgrades outlast the brag:** the medium proxy's 7th and 8th ranks come at 42.2 and 51.4 min [M3].
- **The board** ranks relays restored for as long as anyone plays.

---

## 8. Every number

### 8.1 Geometry and movement (`Config.Station`, `Config.Move`)

| name | value | reason |
|---|---|---|
| `CellSize` | 32 studs | A module's 30-stud interior holds an 18-stud hazard lane (§5.2) and a 16.3-stud low-gravity hop (below). 28 studs (facility-nightmare's) makes sectors 18 % faster at k = 23 (T p50 112.7 vs 137.5 s) and easier (0.892 vs 0.832) [M2]; the schedule was tuned at 32. |
| `WallThickness` | 1 | Inside the cell, facility-nightmare's rule: neighbours meet back to back, no coplanar faces [REPO]. |
| `CeilingHeight` | 18 studs | Above the vacuum hop's apex (9) plus an avatar (about 5, not measured) plus 4 studs [ARITH]. The ceiling glass is out of reach, so nothing can drift out. [STUDIO] |
| `HatchWidth` × `HatchHeight` | 8 × 10 | facility-nightmare's 6 × 9 door for a 4-stud hull [REPO], widened for hopping through in low gravity. [STUDIO] |
| `HatchOpenRadius` | 8 studs | At 16 studs/s, 0.5 s, the hatch cycle: a walker arrives as it finishes opening (facility-nightmare's arithmetic [REPO]). |
| `HatchSeconds` | 0.5 | The hatch cycle, charged per first entry in every M run. At 1.0 s sectors take 10 % longer at k = 23 (151.0 vs 137.5 s) [M2]. |
| `AirWalkSpeed` | 16 | Read off a live Humanoid in Studio [REPO `fork-tower/STUDIO.md` §5]. **The server assigns it** on every module change. |
| `VacWalkSpeed` | 12 (+1 per Mag-Boots rank, to 16) | §3's second lever: 10 / 12 / 14 / 16 gives 0.713 / 0.832 / 0.890 / 0.952 at k = 23 [M2]. Boots stop at air speed: vacuum is never faster than air. |
| `VacGravityFactor` | 0.2 | Near-zero-g, not zero-g: a Roblox Humanoid has no controller for true zero-g, and building one is cut (§21). The client applies a `VectorForce` of `mass × 196.2 × 0.8` upward in vacuum modules. [STUDIO] |
| `VacJumpHeight` | 1.8 | Roblox launches at `sqrt(2 × Gravity × JumpHeight)` [DOC] = 26.58 studs/s; under 0.2 × 196.2 = 39.24 studs/s² that is a 9.0-stud apex, 1.355 s airborne and a 16.3-stud drift at 12 studs/s [ARITH]. The air-module `JumpHeight` stays 7.2 [REPO]. [STUDIO] |
| `PickupRadius` | 5 studs, horizontal | Items stand at least 6 studs off every wall, so no pickup reaches through one (facility-nightmare's rule [REPO]). |
| salvage height | 3–8 studs above the floor (loot stream) | Pickup needs the root part within 4 studs of the item's height. A standing root part sits 2.51 studs above the surface it stands on (SPAWN-ORDER's recorded placement [REPO]), so a 3-stud piece is walked into and an 8-stud piece needs a hop (root up to 11.5 at the 9-stud apex) [ARITH]. [STUDIO] |
| `SpliceRadius` | 6 studs from the mast | The mast stands in the module centre; 6 studs is inside the 15-stud half-interior, so it fires only in the relay module [ARITH]. |
| hub | 60 × 40 × 16, LIFT 12 studs ahead of `HubSpawn` | 12 studs = 0.75 s at 16 [ARITH]: the core action inside the checklist's 5 s. 60 × 40 holds 8 avatars, the board, the lift and the benches (facility-nightmare's hub size [REPO]). |

### 8.2 Air (`Config.Air`)

| name | value | reason |
|---|---|---|
| `TankBase` | 20 s | M2's strongest lever: 15 / 20 / 25 / 30 gives 0.656 / 0.832 / 0.904 / 0.957 at k = 23, perk-less, medium. 20 keeps sectors 1–9 near-certain (≥ 0.990 even for the slow proxy at k ≤ 5 [M1]) and leaves the Air Tank something to fix. |
| `TankStep` | +5 s per Air Tank rank, 4 ranks (20 → 40) | Rank 1 alone lifts the medium proxy from 0.853 to 0.922 at k = 23 [M5]. |
| drain | 1 per second in vacuum | The HUD shows seconds, so the number means what it says. |
| `RefillSeconds` | 2 (empty to full, any tank) | No measurable effect on pacing or survival (1 / 2 / 4 s: P within 0.003 and T within 0.8 s [M2]). It is a feel number: one visible breath. [STUDIO] |
| `GraceSeconds` | 5 | 0 / 3 / 5 / 8 s gives 0.717 / 0.743 / 0.832 / 0.872 at k = 23 [M2]. Five seconds covers crossing one vacuum module back to air at 12 studs/s (2.67 s) with 2.3 s to react [ARITH]. |
| `CanisterSeconds` | 10 | Half the base tank. In the model it barely matters (5 / 10 / 15: 0.829 / 0.832 / 0.833 [M2]) because the model never routes to a canister; humans will. A visible lifeline, not a balance lever. |
| `LowO2Seconds` | 10 | No hazard starts below this (§5.1): half the base tank. |
| `CreditSeconds` | 1 | REVIEW-1 finding 1: a tick costs its time in vacuum or the trusted vacuum distance / the vacuum walk speed, whichever is more (`Air.vacuumCharge`). Vacuum time paid while covering less ground (standing, or a replication stall) covers a later burst, at most 1 s, so an honest stall is never paid twice; a script gains at most that, and only after standing still as long. |

### 8.3 Signal, splice, transit, blackout (`Config.Signal`, `Config.Run`)

| name | value | reason |
|---|---|---|
| meter | `clamp(5 − floor(d), 1, 5)` bars | Informative within 4 modules straight-line, one bar beyond. At the dock the meter reads 1 bar on 57–79 % of sectors from k = 10 on, and 3–4 bars in sector 1 [M9]: "far" early, a gradient near the end. The meter saves time, not lives: range 4 vs none, 137.5 vs 145.3 s at k = 23 with the same P(splice) [M2]. |
| `RelayDepthFrac` | 0.75 | Relay candidates are air modules with doorway distance ≥ ceil(0.75 × maxD). 0.5 / 0.75 / 1.0 gives T p50 97.4 / 137.5 / 151.2 s at k = 23 [M2]: 0.75 makes every sector most of a crossing, which is what the pacing was measured on. What it gives away is §12. |
| `SpliceSeconds` | 2 | The splice animation. Counted in every M run. |
| `TransitSeconds` | 3 | The floor-hatch ride (and the lift ride). The server destroys at most 900 Parts and builds one dock during it; how long that takes is not measured, and nothing waits on it (facility-nightmare's rule [REPO]). [STUDIO] |
| `BoardingSeconds` | 1.0 | The lift car is 8 studs deep: 0.5 s to walk through at 16 [ARITH]. Standing twice that long means walking past never boards. |
| `BlackoutBeatSeconds` | 2.5 | The fade and card, facility-nightmare's death beat [REPO]. The model charges 4.5 s per blackout (beat + waking at the dock). |
| campaign overheads (model only) | start 5 s, transit 3 s, blackout 4.5 s, purchase 4 s | Start = 0.75 walk + 1.0 boarding + 3.0 ride, rounded up [ARITH]. The purchase's 4 s of panel time is an assumption. |

### 8.4 Server, persistence, world (`Config.Server`, `Config.Data`)

| name | value | reason |
|---|---|---|
| `ServerTickSeconds` | 0.1 | 2 % of the 5 s grace, 0.5 % of the base tank [ARITH]. dt from `task.wait`'s return value, never a wall clock (the emulator's clock is virtual; facility-nightmare's rule [REPO]). |
| `StatePushSeconds` | 0.2 (5 Hz, owner only) | A 0.2 s step is 1 % of the base tank [ARITH]; the HUD tweens between pushes. |
| `TrustedSpeedFactor` | 1.35 × the server's current speed | Inherited from vault-runners and facility-nightmare, never measured against real replication [REPO]. Also covers the hatch crossing: the server lowers 16 → 12 when the trusted module turns vacuum, and 12 × 1.35 = 16.2 ≥ 16, so an honest walker still at 16 for a ping is not throttled [ARITH]. [STUDIO] |
| `TrustedBurstSeconds` | 3 | Same source, same caveat. |
| `Players.MaxPlayers` / zones | 8; zones = `max(8, Players.MaxPlayers)` | facility-nightmare's pattern: a Studio slider can never seat more players than zones (fork-tower REVIEW-3) [REPO]. |
| `ZoneSpacing` | 400 studs; zone `i` at `(400 · i, 0, 0)`, hub at the origin | A zone reaches 96 (half of 6 × 32) + 60 (max light range [DOC]) = 156 studs; two zones need 312 [ARITH]. The lifeboat reaches 30 + 60 = 90, inside the 400 − 156 = 244 left before zone 1 [ARITH]. Indices are recycled on leave (the checklist's unbounded-coordinates trap). |
| Parts per zone | ≤ 20 per module (hatch leaves counted apart), ≤ 2 per hatch, ≤ 900 per zone | Module: floor 1 + ceiling ≤ 5 (4-part frame and a glass pane in vacuum) + walls ≤ 12 (three pieces around each doorway) + fixture 1 + item 1 = 20. A 6×6 grid has 60 internal hatches × (leaf + lamp) = 120. 36 × 20 + 120 + dock 3 + relay 6 = 849 [ARITH]; the 900 cap is asserted by counting built folders, not a loop counter (vault-runners invariant 6 [REPO]). Eight full zones would be 7 200 Parts, more than fork-tower's measured 4 110 [REPO `fork-tower/STUDIO.md` §6]: §20 item 6. |
| `Workspace.StreamingEnabled` | false | The server moves characters 400+ studs; with streaming the destination may not have arrived [DOC]. facility-nightmare's choice [REPO]. [STUDIO] |
| `Players.RespawnTime` | 3 | Only the reset path respawns (§13). [STUDIO] |
| `Data.AutosaveSeconds` | 20 | The sibling convention (anomaly-observatory, facility-nightmare) [REPO]. |
| `Data.SessionLockSeconds` | 45 | Longer than two autosaves [REPO, same files]. |
| DataStore writes | ≤ 42 + 16 + 8 ≈ 66 per minute at 8 players, worst case | Splices: the fastest sector (k = 1, fast p10 11.4 s [M1]) at 8 players is 8 × 60 / 11.4 = 42 profile writes per minute [ARITH]; dirty-only autosave ≤ 8 × 2; the ordered store at most once per 60 s per player (§10). Roblox allows 60 + 10 × players = 140 per minute [DOC]. |

### 8.5 Hazards and rest (`Config.Hazards`, `Config.Rest`)

`IntervalMin/Max` 55 / 85 s eligible (REVIEW-1, measured on the real client path, §5.3; the spec's 80 / 120 [M7]
measured 2.98–4.32 min per warning there); `FirstIntervalSeconds` 30 [M7b]; `ArrivalGraceSeconds` 6
(facility-nightmare's arrival rule [REPO]; the first vacuum module is entered 1.0–1.5 s after the dock
opens [M6], so this protects it); `WaitForStillSeconds` 15 and `StillSpeed` 4 studs/s (§5.1; starting values,
[STUDIO]); `PlayerRadius` 1.5, `MaxRetargetSpeed` 1.5, `ViewPitchDegrees` 20, `SpreadDegrees` 35,
`KnockSeconds` 0.6 (plus1-jump's values [REPO], knock time shortened from 0.9 because a low-gravity shove
carries further; [STUDIO]). Kinds: §5.2. Rest: §6.

---

## 9. Economy and upgrades

**Salvage per piece** `value(k) = 5 + (k − 1)`; **splice bonus** `bonus(k) = 10 + 2(k − 1)`; **keep on leaving**
0.5. Growing with depth keeps a deep sector worth its longer, riskier attempt. The absolute scale is a unit
choice; only the ratios to the prices matter.

**Upgrades**, bought with salvage only, at a fabricator:

| id | name | ranks | per rank | price by rank |
|---|---|---|---|---|
| `tank` | AIR TANK | 4 | +5 s of air (20 → 40) | 120 / 300 / 600 / 1000 |
| `boots` | MAG-BOOTS | 4 | +1 stud/s in vacuum (12 → 16) | 120 / 300 / 600 / 1000 |

- **One ladder for both.** The Air Tank buys more survival per rank (k = 40: tank 4 → 0.935, boots 4 → 0.774,
  both → 0.990 [M5]); boots buy speed. The HUD tags the Air Tank RECOMMENDED when both next ranks cost the
  same, and the campaign model buys that way.
- **Why these prices** [M3, M3b]: with 120 / 300 / 600 / 1000 the
  first purchase lands at 2.9 / 3.7 / 4.5 min, the medium proxy buys a rank at 3.7, 6.2, 12.3, 16.8, 24.3, 31.5,
  42.2 and 51.4 min, and the last two land after the brag, so the post-brag stretch still has something to buy.
  The ladder barely moves the brag: the medium proxy splices relay 30 at p50 35.9 / 36.9 / 37.7 min with
  100 / 250 / 500 / 900, 120 / 300 / 600 / 1000 and 150 / 350 / 700 / 1200 [M3b]. The cheap ladder finishes every rank
  at 45.7 min, early in the Deep, and the dear one delays the first purchase to 4.4 min [M3b].
- **Total for everything: 4 040 salvage** (2 × 2 020) [ARITH]. The medium proxy earns p50 105.2 per minute [M3].
- **Leaving early never pays better** [M8]: splicing earns 3.8–5.7 × what a player earns by grabbing the first
  salvage and leaving (return pod, reset, blackout or rejoin) at k = 5, 10, 23 and 40, fast and medium proxies.
- **Removed:** a RECEIVER upgrade (a longer meter range). Range buys time, not survival: meter everywhere vs
  range 4 vs no meter gives P(splice) 0.833 / 0.832 / 0.836 and T p50 115.7 / 137.5 / 145.3 s at k = 23 [M2].
  An upgrade that only saves time, beside two that keep you alive, would ship thin, so it is cut (§21).

**Buying** (`BuyUpgrade(id)`, facility-nightmare's atomic flush [REPO]):
- refused, with the reason, unless: the profile is loaded, the store is writable and the lock is ours, the
  trusted position is within 10 studs of a fabricator console, the rank is below max, and `salvage ≥ price`;
- snapshot → apply → flush the whole profile with `UpdateAsync` under the lock → if it did not persist, roll back
  and say `Couldn't reach the save server — nothing was spent.`;
- with no DataStore (an unpublished place raises on `GetDataStore` [REPO `fork-tower/STUDIO.md` §7]) purchases
  are refused and the HUD says progress will not be saved. Sectors still play.

---

## 10. The highscore board

### 10.1 The metric: relays restored

`best` = the highest sector whose relay this player has spliced. It is the number on the HUD
(`RELAYS 29`), in `leaderstats.Relays`, and on the board.

**Why a script cannot inflate it:**
- **Only the server increments it**, inside the splice, which fires only when the server's **trusted position**
  (§14) is within `SpliceRadius` of the relay mast. The trusted position moves at most 1.35 × the server's own
  speed and only through hatches the server has opened. There is no remote that splices, banks or advances.
- **The relay's location is server memory until its module is built.** Nothing replicated names it (§11.3), and
  the only thing any client learns about it is the meter's bars, the same for every player.
- **AIR is server arithmetic.** A client cannot hold its breath longer; its claimed position decides which module
  it is in, bounded by the trust rules.
- **There is no time in the metric**, so speed is worth nothing beyond the trusted cap, and the tie-breaker is
  the server's clock at the splice.
- **Every attempt is a fresh plan from engine entropy** (§12), so there is nothing to memorise or replay.
- **What remains:** a script that plays perfectly at walking speed. It still needs the air, the route and the
  relay. That is playing the game.

### 10.2 Storage

- OrderedDataStore `SignalLost_Relays_v1`, key `u_<userId>`, value `best × 2e9 + (2e9 − bestAt)`, an integer.
  Ties go to whoever reached it first. `2e9 − now` stays positive until 2033-05-18 (unix 2 000 000 000; now is
  1 790 803 103, 6.6 years of margin) [ARITH], and `best × 2e9` stays under 2^53 while `best < 4 503 599` [ARITH].
- **Write only when `best` improved** since the last ordered write, **at most once per 60 s per player**, plus on
  leaving and in `BindToClose`. The profile keeps `bestAt`, so the value is exact whenever it is written.
  `UpdateAsync` keeps the larger value, so a stale server can never lower a score.

### 10.3 The board in the world

- **A physical board in the lifeboat, on the wall `HubSpawn` faces.** A `SurfaceGui` shows `RELAYS RESTORED`,
  the top 10, ★ beside `best ≥ 30`, and the viewer's own row. A `ProximityPrompt` toggles **PUBLIC / FRIENDS**
  for that viewer (the board is rendered per viewer from a remote payload).
- **Public:** `GetSortedAsync(false, 10)`, cached server-side 60 s, `pcall`'d.
- **Friends:** `Players:GetFriendsAsync(userId)` walked page by page to at most 200 ids, **only when that viewer
  asks**. Scores come from the ordered store's `GetAsync` per friend, issued only while
  `DataStoreService:GetRequestBudgetForRequestType(GetAsync)` is above a reserve of 20 [DOC], so the board can
  never starve profile loads. Each friend's score is cached 5 min server-wide; the viewer's list 10 min. The board
  fills progressively (`checking friends 40 of 120…`). Everything is `pcall`'d.
- **Names** via `GetNameFromUserIdAsync`, cached; names are never stored.
- **An empty friends board says something useful:** `None of your friends has restored a relay yet. Relay 1 takes
  about half a minute — invite one.` ("half a minute": sector 1's splice lands at p50 19.9–29.8 s after the dock
  opens [M6]).

---

## 11. Data model

### 11.1 What persists

DataStore `SignalLost_v1`, key `u_<userId>`, record `{ data = <profile>, lock = { owner, expires } }`.

| field | type | why |
|---|---|---|
| `v` | 1 | schema version |
| `salvage` | integer ≥ 0 | wallet |
| `salvageEarned` | integer ≥ 0 | lifetime, stats only |
| `best` | integer ≥ 0 | relays restored, the metric |
| `bestAt` | integer (unix) | when `best` was reached, the tie-breaker |
| `arrayAt` | integer or nil | when relay 30 was first spliced (the ★) |
| `up` | `{ tank = 0..4, boots = 0..4 }` | **String keys only** (the checklist's JSON trap). Sanitised on load: unknown keys dropped, ranks clamped. |
| `blackouts`, `attempts` | integers | stats |
| `open` | nil or `{ id = GUID string, k, carried }` | An unspliced sector's carried salvage, written by autosave when dirty. **Cleared in the same write that pays it** (splice or leave), so it pays once. A load that finds it banks `floor(carried × 0.5)` before anything else, the §2.7 rule. |

**Session lock:** owner = a stable per-session GUID, never a timestamp that is also rewritten (the checklist's
trap); load with `UpdateAsync`; take the lock only if free or expired; `canSave` only while holding it.
**A sector may start only if** the store is unavailable (play unsaved, said on the HUD) or the lock is ours and
`open` is settled. Lock held elsewhere: the LIFT says `Your file is open on another server — retrying.`

**Never persisted:** AIR, hypoxia, the plan, streams, positions, the built modules, hazard or rest state.

### 11.2 Server-only state

**In `Main.server.luau`, a Lua table per player, never an Instance:** phase (hub / lift / sector / transit /
blackout), zone index, `k`, the four stream objects, the plan (adjacency, dock, relay, air map, `d[]`, items,
salvage heights), built modules, opened hatches, the trusted position and module, AIR, hypoxia timer, carried,
the attempt GUID, the last ordered write.

**In `ServerStorage.SignalDebug.Run_<userId>`** (a Folder with attributes), for the headless checks only:
`Sector`, `DockCell`, `RelayCell`, `AirMap` (a 0/1 string), `SalvageCells`, `CanisterCells`. **ServerStorage never
replicates.** The checks sweep `Workspace` and `ReplicatedStorage` for these names and fail on any hit
(anomaly-observatory's lesson, turned into an assertion).

### 11.3 What replicates, and why each is safe

| what | who | why it is safe |
|---|---|---|
| the lifeboat, `HubSpawn`, lift, fabricator, board frame, benches | everyone | static |
| built modules: walls, floor, ceiling and glass, light, hatch leaves and their open state | everyone (streaming off) | A module exists only after a trusted hatch-open into it. Other zones hold other plans, worth nothing. |
| hatch lamps (red / green) on hatches into unbuilt modules | everyone | Public by design (§2.2): the danger behind a hatch. The relay is not marked. |
| `Salvage` / `Canister` Parts | everyone | Built modules only. **No attributes.** |
| the relay mast | everyone | Only once its module is built. |
| character `WalkSpeed`, `JumpHeight` | everyone | They mirror server state; no rule reads the client's copy. |
| `leaderstats.Relays` | everyone | Public by design. |
| `State` / `Notice` / `Board` remotes | the owner only (`FireClient`) | AIR, hypoxia, carried, salvage, `k`, band, module type, bars, phase; board rows. **No** cell, relay, air map, stream or distance. |
| `Announce` remote | every player | `★ <DisplayName> restored the MAIN ARRAY`. Public by design. |
| module **source** in ReplicatedStorage (`Config`, `Station`, `Air`, `Meter`, `Trust`, `Economy`, `Board`, `Rng`, `MazeGen`, `EnvBands`, `Hazards`, `Rest`, `Fx`, `FxClient`, `Responsive`) | everyone | `robloxemu` mounts only `src/shared` as requirable modules, so shared source ships to clients [REPO `facility-nightmare/DESIGN.md` §7.3]. **No secret lives in code**: the secrets are runtime objects in server memory. |
| attributes under any zone | nobody: there are **none** | Asserted by enumerating every attribute on every Instance under every zone against an **exact expected list, which is empty** (fork-tower REVIEW-3: the enumeration is the test). |

---

## 12. Generation and secrecy

`src/shared/Station.luau` is pure: `Station.plan(cfg, k, streams)`, where `streams = { layout, air, loot, relay }`
and each stream answers `:NextInteger(lo, hi)` and `:NextNumber()` (Roblox `Random`'s API). It requires
nothing; `MazeGen` and the config come in as arguments.

1. **Walls** (layout): `MazeGen.generate(n, n, layout)` (verbatim, md5 `c269d302…`), then every closed wall between
   neighbours opens with `ExtraDoorChance` 0.2 (layout `NextNumber`, row-major). **Dock:** a perimeter cell.
2. **Air map** (air): each module other than the dock is vacuum with probability `breach(k)`; on sector 1 every dock
   neighbour is vacuum; then the reach rule flips the vacuum module farthest from air, lowest id first, until every
   vacuum module is within `reach(k)` hatches of air (0.24 flips per plan at k = 10, 0.19 at k = 23 [M2]).
3. **Relay** (relay): uniform among air modules other than the dock with doorway distance ≥ ceil(0.75 × maxD),
   lowering the threshold until the set is non-empty. **The relay stream draws exactly once and drives nothing
   visible.**
4. **Loot** (loot): on sector 1 the first salvage goes in a dock neighbour; then salvage and canisters in distinct
   vacuum modules (air modules only when vacuum runs out); then positions and salvage heights, last, so the room
   assignment is draw-for-draw the rig's and M1 reproduces.

**Why nothing about the relay leaks, stream by stream** (the fork-tower REVIEW-4 lessons):
- **Trap 1, a seed brute-forced against visible geometry.** In production every stream is a `Random.new()` with
  **no seed argument** (engine entropy [DOC]), one object per stream, per attempt. The game never handles or
  exposes a seed, so there is no 31-bit integer to enumerate against the walls. What Roblox documents about that
  entropy is only "internal entropy" (fork-tower REVIEW-4, open item 2), so no claim is made about the engine
  generator's state size. Tests pass an adapter over `Rng.new(seed)` with the same two methods, so M1 reproduces
  exactly.
- **Trap 2, one stream pinned by many observations.** The relay stream is separate and makes one draw that is
  never shown. Walls, air and loot each reveal only themselves.
- **The air map never depends on the relay** (the reach rule reads walls and air only), so no trail of forced air
  modules points at it. The relay is chosen **after** the air map, among modules that are already air, so an air
  module is no likelier to be the relay than the public rule says.
- **What the public rule gives a map reader** [M9]: someone who somehow knew a sector's whole map (walls and air)
  would find 2–3 candidates at the median (p90 3–5) and guess the relay first time with probability 0.44–0.62.
  That is why the map must not be derivable, and why every stream is engine entropy. A human sees only opened
  modules and hatch lights.
- **Nothing is memorisable:** every attempt, every blackout and every lift ride is a fresh plan.

---

## 13. Spawn placement (per `robloxemu/SPAWN-ORDER.md`)

The engine fires `CharacterAdded` while the character is unparented at the origin, then one frame later places it
on a spawn and discards any CFrame written in between [REPO SPAWN-ORDER §1].

1. **Build the lifeboat first**, synchronously, before `PlayerAdded` is connected, before existing players are looped
   over and before any DataStore call: floor, walls, ceiling, window, lights, `HubArrival` (a plain Part) and
   `HubSpawn`, a real `SpawnLocation` with `Enabled = true`, `Duration = 0` (no ForceField [DOC]), `Neutral = true`.
2. **`HubSpawn` is the only enabled `SpawnLocation` anywhere.** Docks, relay rooms, the lift and the pods are plain
   Parts. Asserted headless, as deep-vein's `walk.luau` does.
3. **In `PlayerAdded`, `plr.RespawnLocation = HubSpawn` at once**, before the character loads: SPAWN-ORDER's
   preferred pattern, nothing to race.
4. **`CharacterAdded` writes no CFrame and does not yield.** It sets `WalkSpeed` 16 and `JumpHeight` 7.2 and resets the
   camera to Classic third person. If a sector is open, it calls `endSector(plr, "reset")` (idempotent).
5. **Every other move is a server write on a character already in the world**, guarded by
   `char.Parent ~= nil and Humanoid.Health > 0`, and each resets the trusted position to its destination:

   | move | from → to |
   |---|---|
   | lift | lifeboat → sector `best + 1`'s dock |
   | transit | relay module → next dock |
   | blackout | wherever you are → the same sector's new dock, after the beat |
   | return | dock or relay module → `HubArrival` |

6. **Reset path:** `Humanoid.Died` in a sector → `endSector("reset")`; the engine respawns after `RespawnTime` and
   places the character on `HubSpawn` through `RespawnLocation`.
7. **Falling out** (a client that deletes its own floor) reaches `FallenPartsDestroyHeight` [DOC], then `Died`, then 6.

**Headless coverage:** `simulateSpawn` honours `RespawnLocation` and the engine order [REPO SPAWN-ORDER §2], so 1–4
are checkable. The automatic respawn in 6 is not modelled (SPAWN-ORDER §7): the check fires `TakeDamage`, calls
`simulateSpawn` itself, and asserts one settlement and a landing on `HubSpawn`.

---

## 14. Anti-exploit model

The client owns its character's physics, reads everything that replicates, edits its own Lighting and fires any
remote with any arguments. **Every rule reads the server's own state.**

**The trusted position** (`src/shared/Trust.luau`, copied from facility-nightmare with its spec and adapted only in
speed: the cap follows the server-set speed of the module type): the server walks its own copy toward each claim at
most 1.35 × the server's speed, banking up to 3 s of allowance for jitter; the trusted module changes only to an
adjacent module through a hatch the server has opened; a claim through a wall or a closed hatch is clamped.
Height is ignored except for the salvage window (§8.1).

| threat | what it would buy | response | residual |
|---|---|---|---|
| teleport, speed hack, noclip | the relay at once; skipping vacuum | trusted position and module; AIR charges the trusted vacuum distance as well as the time (REVIEW-1 finding 1: a client writing its position crossed a vacuum module between two ticks for 0–0.2 s of AIR instead of 2.7 s; now 2.67 s, and its vacuum reach is the honest walker's +0.3 %) | moving at up to 1.35 × speed (reaching the board's metric sooner, not higher); at most `CreditSeconds` (1 s) of AIR per vacuum stretch, after standing still that long |
| client `WalkSpeed` or gravity edits | crossing vacuum faster | the cap follows the server's speed; AIR is server time or trusted distance, whichever is more | a client that switches its low-gravity force off only jumps lower |
| a claimed height | floating salvage without a hop | the height window, and the claim must stay under the hop's reach | about 1 s saved per high piece |
| reading replicated Instances | the relay, the air map | neither replicates (§11.3); enumeration test | none known |
| reading module source | the generator | streams are engine entropy per attempt; the relay stream shows nothing (§12) | none known |
| forged remotes | salvage, upgrades, progress | there is no splice or bank remote; `BuyUpgrade` is typed, ranged and checked against the trusted position; every refusal says why | none known |
| remote spam | throttling the server or the DataStore | `BuyUpgrade` checks its 0.5 s cooldown FIRST and answers inside it at most once (REVIEW-1 finding 3: 1000 calls drew 1000 replies; now 2), and a refused request writes nothing: a player can make only 8 successful purchases ever, so purchases never exceed 8 writes per player. The board toggle at most once per 2 s; its reads are budget-gated (§10.3) | none |
| reset, leave or crash to dodge a blackout | keeping all carried salvage | all pay what a blackout pays (§2.7); `open` settles on the next load; `BindToClose` | none |
| a slow release write (leave, shutdown) | a locked-out rejoin; a splice paid after the leave | a closing session never ticks again, and only its releasing write may save (REVIEW-1 finding 2: at 0.5 s latency a leave in the ride, out of air or mid-splice re-took the lock for 45 s, and a splice finished after the leave); `BindToClose` marks every session first and writes them all at once | real `UpdateAsync` latency is a live-server number |
| farming by leaving early | salvage without progress | measured: splicing pays 3.8–5.7 × more [M8] | none |
| resting to dodge | anything | rest only exists where nothing drains and hazards never come (§6) | none |
| two servers | a double settle or a dupe | session lock; `open` cleared in the paying write; whole-profile atomic purchases | none known |
| AFK | salvage over time | nothing accrues with time | none |
| a stale server lowering a board score | griefing the board | `UpdateAsync` keeps the larger value | none |

**No `Workspace:Raycast`, no `PathfindingService`, no `Touched` in any rule.** All spatial rules are grid arithmetic:
a security property (`Touched` is client-physics-driven) and a testability one (the emulator's `Raycast` raises on
purpose [REPO `robloxemu/emu/services.luau`]).

---

## 15. HUD (phone first)

Copy `Responsive.luau` verbatim (md5 `8cf3ba92…`, identical in every game [REPO]) and follow `docs/mobile-ui-brief.md`:
a root Frame owns the `UIScale`, sized `1 / scale`, re-laid-out on `ViewportSize` and `TouchEnabled` changes.

| element | where | notes |
|---|---|---|
| `SECTOR 12 · CARGO SPINE` / `RELAYS 11 · SALVAGE 340 (CARRIED 35)` | top-left | |
| **AIR** gauge: bar + `AIR 14s` | top-right | amber below 50 %, red below 25 %, pulsing in hypoxia with a countdown; the edge vignette tightens |
| **SIGNAL** meter: five vertical bars | right edge, 25–55 % of screen height | display only; above the jump button's pad on every viewport in `HudCheck.VIEWPORTS` (asserted) |
| hint / toast line | top-centre, scale width with a `UISizeConstraint` cap | |
| **REST** button; **SHOP** button (only at a fabricator) | top edge, right of centre | tap targets ≥ 44 screen px after scaling (the vault-runners `ceil(46 / scale)` rule [REPO]) |
| fabricator panel, blackout card, splice card, brag card | centre modal, `ScrollingFrame` where a list can grow | side panels hide while a modal is open |

- **Nothing tappable in the bottom-left or bottom-right** (the thumbstick and jump button own them). Jumping is Roblox's own
  button: the low-gravity hop needs nothing new.
- **Camera:** Classic third person everywhere (hazard rings and floating salvage need to be seen around you).
- **The overlap rule 4b is on:** `overlap = true` in `check_signallost_hud`, measured in the play state and the
  fabricator state separately.
- **Glyphs:** only glyphs already photographed rendering in Studio (`GLYPHS_SEEN_IN_STUDIO` in
  `robloxemu/check_forktower.luau` [REPO]): v1 uses ★ — … and plain text. No emoji until §20 item 13 photographs them.
- **Language:** English.

---

## 16. The first 60 seconds of a new player

Times from joining. The sector-1 rows add 4.75 s (0.75 walk + 1.0 boarding + 3.0 ride [ARITH]) to M6's times,
which count from the dock opening.

| t (s) | what happens | evidence |
|---|---|---|
| 0 | The engine places the character on `HubSpawn` (§13). The board is on the wall ahead. Hint: `Walk into the LIFT`, floor arrow. | §13 |
| ≈0.75 | In the lift: **the core action inside 5 seconds**, nothing to buy, no prerequisite. | 12 studs at 16 [ARITH] |
| ≈1.75 → 4.75 | Ride: `SECTOR 1 — DOCKING RING`. | `BoardingSeconds`, `TransitSeconds` |
| ≈4.75 | The dock opens. AIR 20s full. SIGNAL 3 bars (78 % of sector 1s) or 4 (22 %). Hint: `Follow the SIGNAL to the relay. Green light: air. Red light: vacuum.` | [M9] |
| ≈5.8–6.3 | **First vacuum**, on every sector 1: gravity drops, the gauge drains. Hint: `No air here — your AIR is draining. Jump to drift.` | 1.0 / 1.2 / 1.5 s after the dock opens, 100 % of runs [M6] |
| ≈8.8–10.1 (p50) | **First salvage**, floating next to the dock: `+5 salvage — banked when you splice the relay.` | 4.0 / 4.6 / 5.3 s p50, 91–93 % of runs [M6] |
| ≈24.7–34.6 (p50) | **RELAY 1 ONLINE.** The sector's lights come on, `+10` bonus, salvage banked; the floor hatch opens. Hint: `Drop through the hatch to go deeper.` | splice p50 19.9 / 24.4 / 29.8 s, p90 30.6 / 37.1 / 44.5 [M6] |
| ≈28–38 | Transit into sector 2. | `TransitSeconds` |

**Honest reading:** inside the first minute every proxy has moved, crossed vacuum, watched the gauge fall and refill,
taken salvage and spliced a relay: the whole loop once. Deaths in sector 1 are absent in the model (P(splice) 1.000
for all three [M1]); O2 falls below half on 1 / 6 / 17 % of first sectors [M6], so the gauge is felt without being a
threat. The first purchase comes at minute 2.9 / 3.7 / 4.5 [M3] and the first hazard at 3.3 / 3.7 / 4.2 [M7b].

---

## 17. Visuals from the first build

Code-only, in the **first playable build** (checklist §2):

1. **Lighting.** Copy `Fx.luau` from anomaly-observatory or nightwatch-manor (md5 `142bf959…`, the variant that knows an
   `Atmosphere` replaces legacy fog [REPO]) and add one preset, `Fx.Presets.Station`: space-dark ambient so the
   modules' own lights carry the scene. `Fx.applyLighting(Fx.Presets.Station)` is the server's first statement. Values: §20 item 3.
2. **Signature glow:** salvage amber (`Fx.attachGlow`: the thing you chase glows), canisters cyan, hatch lamps red / green,
   the relay mast red until spliced and green after; the splice ripples each built module's light on in doorway order.
3. **Atmosphere:** one `Fx.dustVolume` per built module (frost, spores, dust, embers… per band, §4.2).
4. **Client juice:** `FxClient.theme` on every HUD frame; `FxClient.fovPunch` on salvage; `FxClient.shake` on a hazard hit and
   the blackout; `FxClient.flash` on the splice and the brag.
5. **Hypoxia:** four edge Frames with `UIGradient` ramps (no image asset) that close in over the grace, facility-nightmare's
   exposure vignette [REPO].
6. **Exterior:** a client-side planet sphere, its atmosphere ring, the array dish and the relay beacons, placed far outside
   the zone, phased by band (§4.2); a `Sky` with stars.

---

## 18. Fair monetization

**v1 sells nothing.** No game passes, developer products, paid private servers or codes. Salvage comes only from
playing.

**Never, in any version:** air, canisters, salvage, upgrades, revives or skips for Robux; randomised paid rewards of any
kind; rewards for watching anything. **If a v2 adds a store**, the only candidate is a cosmetic suit colour, and a spec must
assert it changes no light, no tank and no speed.

---

## 19. Tests first (TDD order) and headless checks

**Scaffold** (deep-vein's layout): `default.project.json` maps `src/server` → ServerScriptService, `src/client` →
StarterPlayerScripts, `src/shared` → ReplicatedStorage. `src/shared`: `Config`, `Station`, `Air`, `Meter`, `Trust`,
`Economy`, `Board`, `Rng` (vault-runners, `217e5d06…`), `MazeGen` (`c269d302…`), `EnvBands`, `Hazards`, `Rest`,
`Fx`, `FxClient`, `Responsive`, `EnvArt`, `Dressing`. `src/server/Main.server.luau`; `src/client/Hud.client.luau`,
`Env.client.luau`. `tests/*.spec.luau`. `README.md`, `CLAUDE.md`, `EYECANDY.md`, `MARKETING.md`, and a `.gitignore`
with `publish_*.bat` / `publish_*.sh`. No bare `require("./X")` outside `tests/`: shared modules take their
dependencies as arguments.

**The traps `CLAUDE.md` must name:** the relay stream draws once and drives nothing visible (§12); production
streams are `Random.new()` with no seed, tests use the `Rng` adapter; the air map never reads the relay; the server
assigns `WalkSpeed` and `JumpHeight` on every module change; no CFrame write in `CharacterAdded`; hazards only in
vacuum and rest only in air; `open` is cleared in the write that pays it; the ordered value is an integer under
2^53; the Hazards template's md5 at copy time.

Each line below is a failing test to write before the code.

**`tests/Station.spec.luau`**
1. Every module is reachable from the dock, 10 000 plans per shape. The dock is on the perimeter.
2. The relay is air, not the dock, at doorway distance ≥ ceil(0.75 × maxD) (or the lowered threshold), and uniform among
   the candidates (chi-square over 20 000 draws with the other streams fixed).
3. **Relay independence:** with layout, air and loot streams fixed, changing the relay stream changes the relay and nothing
   else (walls, air map, items identical); changing the layout, air or loot stream never changes how the relay stream is read.
4. The reach rule holds on every plan; the air map is identical for any two relay streams.
5. Sector 1: every dock neighbour is vacuum and one salvage floats in one of them, on every plan.
6. Item counts equal the §3 schedule; items in vacuum first; one item per module; positions ≥ 6 studs off every wall;
   salvage heights 3–8.
7. Only `NextInteger` / `NextNumber` are called; no `Rng.int`; every intermediate < 2^53.
8. **Reproduce Appendix A's M1 table** with the real module and the rig's seeds. If it does not reproduce, re-measure M1–M9
   against the real module and edit this spec; do not tune the module to the rig.

**`tests/Air.spec.luau`**: drain only in vacuum, refill to full in `RefillSeconds` in air, hypoxia and grace, recovery in air or
by a canister, a canister untaken at a full tank, NaN / negative / zero dt changes nothing, and the hazard-eligibility helper
(vacuum, band, grace, AIR ≥ 10).

**`tests/Meter.spec.luau`**: `bars` mapping at d = 0, 1, 1.41, 2, 3, 3.99, 4, 7.07; clamps; symmetric.

**`tests/Trust.spec.luau`**: facility-nightmare's spec, with the speed cap following the module type (16 / 12 + boots).

**`tests/Economy.spec.luau`**: `value`, `bonus`, `keep`; the ladder and max ranks; sanitise (string keys, unknown keys dropped,
JSON round-trip identical); `endSector` idempotent; blackout, return, reset, left, shutdown and crashed pay the same; `open` pays once.

**`tests/Board.spec.luau`**: encode / decode; earlier `bestAt` wins a tie; the value is an integer; the write rule (improved and
≥ 60 s, or leaving); `UpdateAsync` keeps the larger value.

**`tests/Pacing.spec.luau`**: M3 on the real `Station` (200 campaigns): the medium proxy splices relay 30 at p50 within 30–45 min;
every band after the first lasts ≥ 3 min at every proxy; the curve (M4) is strictly falling from k = 30 to 150 with every upgrade.

**`tests/EnvBands.spec`, `Hazards.spec`, `Rest.spec`** copied with their modules (§10 of plus1-jump's EYECANDY names the
template API), extended for each adaptation in §5.1 and §6. **`EnvConfig.spec`**: every band defines the same fields, the
palette and hue rules of §4.3, `fade` = 1, band starts at sectors 1 / 5 / 10 / 16 / 23 / 31 / 60. **`Responsive.spec`,
`Rng.spec`, `MazeGen.spec`** copied.

**Headless, against `robloxemu/build/signal-lost.luau`** (rebuild the bundle before every run):
- `check_signallost.luau`: boot with no errors; `HubSpawn` the only enabled SpawnLocation; `RespawnLocation` set and honoured;
  the lift builds only the dock; a hatch opens only on a trusted approach; a teleport claim neither opens hatches nor picks up;
  AIR drains in vacuum on the virtual clock; blackout at grace → new dock, half banked; the splice banks, advances `best`, lights
  the sector; transit; a purchase refused and rolled back when the write fails; `TakeDamage` → one settlement → `HubSpawn`;
  `open` settles once on rejoin; **zero attributes under every zone**; the debug names nowhere in Workspace or
  ReplicatedStorage; ≤ 20 Parts per module, ≤ 900 per zone, counted from the built folders; every glyph on the Studio list.
- `check_signallost_walk.luau`: **the real player path**, the standard's §1: spawn, lift, sector 1 splice, sector 2, earn, buy
  at the relay's fabricator, leave, rejoin, lift to sector `best + 1`.
- `check_signallost_hud.luau`: the hudcheck on every viewport with `overlap = true`, in play and with the fabricator open.
- `check_signallost_env.luau`: band by sector, blends and glides, budgets at every band and seam, nothing covers an item or a
  lamp, hue rules on the built instances; Env never fires a remote, sets an attribute or creates a light source.
- `check_signallost_hazards.luau`: the rate through the real client, ring = zone, called off on leaving the module, none in air,
  none below 10 s AIR, none in the arrival grace, the first after 30 s, the wait for a still player. *(Built in REVIEW-1 as
  `check_signallost_campaign.luau`: one real campaign to relay 30 with the rate, the near-misses, no hazard called off
  in-sector, the relay room after every splice, REST there, and the prompt buttons; the rest of this list lives in
  `check_signallost_env.luau`. `check_signallost_review.luau` holds REVIEW-1's server regressions.)*
- `check_signallost_rest.luau`: refused in vacuum with the reason, allowed in air and on the benches, wakes on movement, freezes
  the hazard clock without resetting it.
- `check_signallost_board.luau`: public top 10 with ★; friends with `GetFriendsAsync` stubbed in the check file (the emulator
  does not have it); the empty-friends message; the budget gate.
- `check_signallost_brag.luau`: splicing relay 30 announces to other players, writes `arrayAt` once, and marks the board.

Then a **mutation sweep with a control** the suite must not notice (for example a band's dust colour), per the repo's
mutation-control rule.

---

## 20. Needs Studio

Nothing on this list is verified. Each item says what to look at.

1. **Real players against the proxies.** Time sectors 1–10 and the brag against M1 / M3, count blackouts per band (the
   model's are a floor, §0), then refit the profiles and re-run M3 before touching §3.
2. **Low gravity.** A client `VectorForce` at 80 % of weight and `JumpHeight` 1.8 in vacuum: a 9-stud apex, 1.36 s airborne,
   16 studs of drift [ARITH]. Does the Humanoid walk, land and turn sanely, does it snag on hatch frames, does it read as
   drifting, can every salvage height be reached with one hop, and is switching gravity at a hatch smooth?
3. **`Fx.Presets.Station`.** Space-dark ambient; air modules readable, vacuum modules dim but readable; the red and green
   hatch lamps unmistakable on a phone, including for red-green colour-blind players (§21 lists a symbol as a fallback).
4. **Geometry:** 8 × 10 hatches with a low-gravity hop through them; ceiling 18 against a real jump; the glass viewport.
5. **The trusted position** (1.35 ×, 3 s burst) on real replication, including the 16 → 12 speed change at a hatch.
6. **Render cost:** up to 8 zones × 900 Parts plus client dressing; take `Stats` FPS, not a Lua counter (fork-tower §6
   [REPO]). If it is too heavy, cap `MaxPlayers` at 6 before cutting art.
7. **Hazards:** a 6 studs/s drifting lane reads as a threat, the ring is visible in third person, the wait-for-still rule
   produces near-misses, knock 14–20 with `KnockSeconds` 0.6 under low gravity feels like a stagger.
8. **Phone and input:** AIR gauge and SIGNAL bars readable at 800 × 360, REST on the top edge, fabricator and board prompts
   on touch; keyboard R and gamepad ButtonX free of engine bindings; on a gamepad the prompts show Y (fabricators, the
   board) and B (RETURN), never X (REST), and both relay-console prompts are offered at once (REVIEW-1).
9. **The brag sequence:** dish swing, beam, beacons, the server-wide toast; the dish growing through sectors 23–30.
10. **Friends board:** real `FriendPages`, `GetRequestBudgetForRequestType` behaviour, OrderedDataStore reads under load.
11. **DataStore on a published place** (an unpublished one raises [REPO]).
12. **Spawn and reset:** `HubSpawn`, `RespawnLocation`, `RespawnTime` 3, no ForceField; `BindToClose` settles 8 players within
    the shutdown window [DOC 30 s].
13. **Glyphs** beyond ★ — … before any is used.
14. **The exterior:** planet phases per band through the ceiling glass and the lifeboat window, no z-fighting, nothing occluding
    a module.
15. **Transit and lift rides** land cleanly with streaming off; no camera snap.
16. **Console:** zero errors and warnings across a sector, a blackout, a splice, a purchase, a return and a rejoin.
17. **Maturity questionnaire:** mild fear, no blood, no jumpscares; the Preview page is the ground truth.
18. **`Random.new()` as a stream:** confirm `NextInteger` bounds are inclusive and `NextNumber` is in [0, 1) as the adapter
    assumes (the CLI has no `Random`).

---

## 21. Cut from v1

Each is cut rather than shipped thin.

1. **The Entity** (brief): no pursuer, no pathfinding, no rig. The vacuum and scripted hazards are the threat.
2. **Co-op / shared sectors / parties** (brief: "solo or with friends"): one player per zone, a shared lifeboat. Shared sectors
   change ownership, payout and the splice, which is a redesign, not a flag.
3. **Audio.** No asset IDs; the first post-v1 item and the biggest gap for a horror game (nightwatch-manor says the same).
4. **The RECEIVER upgrade** (measured useless for survival, §9).
5. **Sprint, stamina, noise, hiding spots, keycards, signal fragments.**
6. **True zero-g movement** (a six-axis drift controller): 20 % gravity instead.
7. **Hazard hits that cost AIR:** a hit is a shove only (client-side, §5.1).
8. **Repairing breaches** or re-pressurising modules; banking salvage anywhere but a splice.
9. **Map, minimap, compass or relay arrow:** the meter is the only guidance.
10. **Story content for THE ECHO** beyond its band, card and exterior.
11. **Cosmetics, game passes, developer products, codes, badges** (badges need asset IDs; the Main Array is the obvious first one).
12. **Daily or shared seeds.**
13. **Jumpscares** (about 2 % day-7 retention [REPO `docs/game-radar/2026-09-06-roblox-game-radar-round2.md`]).
14. **A colour-blind symbol on hatch lamps** until §20 item 3 says red / green alone is not enough (then it is the first fix).

---

## 22. Store text, clip list and thumbnail shots (drafts)

The radar's paste-ready description promises an Entity, co-op and weekly content, none of which v1 has. It must not be used.
The draft below is **945 characters, ASCII only, no coloured-square emoji** (counted), for `README.md`:

```
A dead space station has gone silent. You are the engineer sent to bring its signal back, one relay at a time.

Follow the signal through dark modules. Some still hold air. Some are open to space: gravity is almost gone, you drift, and your suit's air ticks down. The light over every hatch tells you what is behind it: green for air, red for vacuum. Plan a route between air pockets, grab the salvage floating in the wreckage, and splice each sector's relay to bring its lights back.

Run out of air and you black out. You wake at the sector's entrance, and the sector rebuilds itself into a new layout. Spend salvage on a bigger air tank and mag-boots.

Restore 30 relays to reach the Main Array and send the signal home. Then find out what answered.

- A new station layout on every attempt
- No monster chases you: the danger is the vacuum
- Leaderboard of relays restored, public and friends
- Nothing costs Robux

Mild fear. No jumpscares.
```

**Clip list** for `MARKETING.md` (vertical 1080 × 1920, 7–15 s, `tools/film_game.py` staging only: a start position, a camera
path, never faked progress):
1. **Red light** (10 s): at a red-lit hatch with a full gauge; step through, gravity drops, hop to a floating crate, the gauge
   ticking; back through a green hatch with 3 s left and the refill. Any sector 3–9.
2. **Near miss** (8 s): standing to take salvage, a LOOSE CRATE drifts in, red ring; one step out; it tumbles through. Cargo Spine.
3. **Splice** (9 s): the meter at 4 bars, a green hatch, the relay room, the splice, the sector's lights coming on. Any sector.
4. **Blackout** (10 s): the gauge at 0, the tunnel closing, a green hatch two modules away, SIGNAL LOST. Stage in the Deep.
5. **The Main Array** (15 s): relay 30's splice, dish, beam, beacons, SIGNAL SENT, "…something answered." Needs a filming
   account that has really reached sector 30 (about 37 minutes at the medium proxy).
6. **Band reveal** (8 s): the transit ride into a new band (Reactor → Array Spine), the grade shifting.
7. **The board** (7 s): the lifeboat board with ★ names, toggled to FRIENDS.

**Thumbnail shots** for `EYECANDY.md` (1920 × 1080):
1. A vacuum module from behind the character, mid-hop toward a glowing amber crate, the planet's day side through the cracked
   ceiling glass, a red hatch light in frame.
2. A doorway pair: a red lamp on the left, a green lamp on the right, the AIR gauge low.
3. The Main Array control room from below, the dish and the beam above the glass.
4. The lifeboat board with the planet window behind it.

---

## Appendix A — The measurement rig

**Location:** `signal-lost/design-measure/`. A design tool, **not game code** (see `station.luau`'s header).

- `station.luau`: the prototype planner (streams in the §12 order), the model explorer, the campaign model, the schedule,
  bands and economy as measured.
- `Rng.luau`, `MazeGen.luau`: verbatim copies of `vault-runners/src/shared` (md5 `217e5d06…`, `c269d302…`).
- `m1_sector.luau` … `m9_secrecy.luau`, plus `m3_campaign.luau` (the campaign driver that `m3_run.luau` and
  `m3b_ladders.luau` use) and `m7b_firsthazard.luau`. Their outputs are saved next to them as `out_m*.txt`.

Run from that directory with the scratchpad luau CLI: `luau.exe m1_sector.luau 2>&1`. Every file uses fixed seeds and
prints the same output on every run.

| id | question | size | headline output (verbatim numbers) |
|---|---|---|---|
| M1 | One sector attempt, no upgrades | 2 000 plans per row | P(splice) fast / medium / slow: k1 1.000 / 1.000 / 1.000, k3 1.000 / 1.000 / 0.995, k5 1.000 / 0.999 / 0.990, k10 0.990 / 0.947 / 0.883, k16 0.987 / 0.921 / 0.823, k23 0.942 / 0.844 / 0.718, k30 0.904 / 0.752 / 0.583. T p50 (s): k1 20.1 / 24.5 / 29.8, k10 57.6 / 82.4 / 95.2, k23 94.9 / 133.1 / 145.8, k30 106.7 / 151.0 / 153.7. Vacuum share of time 43–70 %, rising with k. maxD p50 5 / 7 / 10 / 12 for n = 3 / 4 / 5 / 6. Fastest sector: k1 fast p10 11.4 s. |
| M2 | One knob at a time, k = 10 and 23, no upgrades | 1 000 plans per row | k23 medium P(splice): base 0.832; TankBase 15 / 25 / 30 → 0.656 / 0.904 / 0.957; VacSpeed 10 / 14 / 16 → 0.713 / 0.890 / 0.952; Grace 0 / 3 / 8 → 0.717 / 0.743 / 0.872; Canister 5 / 15 → 0.829 / 0.833; Refill 1 / 4 → 0.832 / 0.832; ExtraDoor 0 / 0.4 → 0.586 / 0.958; RelayDepthFrac 0.5 / 1.0 → 0.869 / 0.822 (T 97.4 / 151.2 s vs 137.5); meter everywhere / none → 0.833 / 0.836 (T 115.7 / 145.3); Hatch 1.0 s → T 151.0; CellSize 28 → 0.892, T 112.7. Reach flips per plan 0.24 (k10), 0.19 (k23). |
| M3 | Whole campaigns, greedy buyer | 400 per proxy, cap 61 sectors / 240 min | Relay 30 spliced at p10 / p50 / p90: fast 25.6 / 28.4 / 31.3, medium 33.0 / 36.9 / 41.3, slow 43.5 / 49.2 / 55.7 min. Sector entered (p50, fast / medium / slow): 5 at 2.0 / 2.5 / 3.0, 10 at 5.1 / 6.5 / 8.4, 16 at 10.9 / 14.3 / 18.8, 23 at 17.6 / 22.8 / 30.2, 31 at 28.5 / 36.9 / 49.3, 40 at 40.7 / 53.2 / 71.7, 60 at 69.6 / 95.3 / 131.8. Income 139.2 / 105.2 / 78.6 per min. First purchase 2.9 / 3.7 / 4.5 min; all 8 ranks 39.9 / 51.4 / 68.3. Medium purchases at 3.7, 6.2, 12.3, 16.8, 24.3, 31.5, 42.2, 51.4. Blackouts p50 0 / 1 / 3. Medium O2 < 25 % of attempts by band: .02 / .06 / .15 / .14 / .26 / .43 / .60; blackouts per attempt .000 / .000 / .002 / .001 / .003 / .027 / .049. |
| M3b | Does the price ladder move the brag? | 300 per proxy per ladder | Medium relay 30 spliced p50: 35.9 / 36.9 / 37.7 min for 100 / 250 / 500 / 900, 120 / 300 / 600 / 1000, 150 / 350 / 700 / 1200 (both upgrades on one ladder); first purchase 3.3 / 3.7 / 4.4 min; all 8 ranks 45.7 / 51.5 / 59.7 min. |
| M4 | The endless curve | 800 plans per cell | Medium P(splice) with all 8 ranks: k30 1.000, k40 0.989, k60 0.930, k80 0.871, k100 0.791, k150 0.728, k250 0.700; slow 0.993 / 0.944 / 0.833 / 0.725 / 0.645 / 0.551 / 0.505; medium perk-less k60 0.359. |
| M5 | One upgrade at a time | 1 000 plans per row | k23 medium: none 0.853, tank 1–4 0.922 / 0.965 / 0.988 / 0.996, boots 1–4 0.898 / 0.917 / 0.946 / 0.960, both 4 1.000. k40 medium: none 0.571, tank 4 0.935, boots 4 0.774, both 4 0.990. |
| M6 | A new player's sector 1 | 3 000 plans | First vacuum 1.0 / 1.2 / 1.5 s after the dock opens (100 %); first salvage p50 4.0 / 4.6 / 5.3 s (91 / 92 / 93 %); splice p10 / p50 / p90 fast 11.4 / 19.9 / 30.6, medium 13.0 / 24.4 / 37.1, slow 15.7 / 29.8 / 44.5 s; O2 below half 1 / 6 / 17 %. |
| M7 | Hazard rate | 200 campaigns per proxy per interval | 80–120 s: one per 2.75 / 2.64 / 2.58 min of play in hazard bands; eligible share 0.62 / 0.64 / 0.65. 60–90 s: 2.05 / 1.98 / 1.93. (Superseded on the real client path, §5.3: the share there is 0.50–0.57.) 100–150 s: 3.45 / 3.31 / 3.22. Medium per band (80–120): hydro 7.3, cargo 3.2, reactor 3.0, array 2.8, deep 2.4, echo 2.3 min per hazard. |
| M7b | When the first hazard comes | 300 campaigns per row | First interval 80–120 s: minute 6.0 / 6.4 / 6.8 p50 (sector 10 / 10 / 8). First interval 30 s: minute 3.3 / 3.7 / 4.2 (sector 7 / 6 / 6). |
| M8 | Leaving early vs splicing | 1 500 plans per row | Salvage per minute, splicing vs grabbing the first piece and leaving: k5 60.5 vs 10.7 (fast), 50.1 vs 9.5 (medium); k10 67.2 vs 12.5, 55.3 vs 10.8; k23 99.3 vs 20.6, 78.1 vs 17.7; k40 141.5 vs 33.1, 108.8 vs 28.4. Ratio 3.83–5.66. |
| M9 | What the public relay rule gives a map reader | 3 000 plans per row | RelayDepthFrac 0.75: candidates p50 2 / 2 / 3 / 3 / 2 at k 1 / 5 / 10 / 23 / 40; first-guess hit chance 0.61 / 0.60 / 0.49 / 0.44 / 0.62. At 0.5: 0.31 / 0.27 / 0.21 / 0.17 / 0.28. Dock meter at 0.75: sector 1 3 bars 78 %, 4 bars 22 %; k ≥ 10 one bar 57–79 %. |

**What the rig does not model**, so no number above covers it: hazards' time cost; hesitation beyond a slower speed; the
low-gravity hop as physics; collision and props; replication and the trust throttle; canister routing; the fabricator panel
beyond 4 s; time spent in the lifeboat; the meter's coarseness (the model reads exact distances in range).
