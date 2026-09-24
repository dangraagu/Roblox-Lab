# FACILITY: Endless Nightmare — deeper is stranger

Owner's brief (Gustav, 2026-09-17): every game visually richer and never monotonous, with the world changing
as the player progresses in a way that fits the game; rare hazards that are easy to see coming and avoid
(about one near-hit per 2-3 minutes); a way to rest that can never become an exploit; a thumbnail shot list.
For FACILITY specifically: the dark and the flashlight are the gameplay and there is no chasing AI, so the
visuals must never make a room brighter or easier to see than designed, must never hide a fuse, and rest
belongs in the break room, not mid-run.

**State: built, unit-tested, headless-tested, mutation-tested, and reviewed by an independent adversarial reviewer
whose five findings are closed (§11). NOT seen in Studio, NOT played by a person.** Nothing was committed, pushed
or published.

**Review round (2026-09-24, after the resume session).** An independent reviewer found five things; §11 has each
one reproduced, fixed test-first and mutation-tested:
1. **The deep bands' palettes dimmed the rooms and hid the doors** (medium). In the server vault, the reactor and
   the void a closed door was as bright as its wall, and void walls returned 7 % of the light the server's did.
   Palettes are now held in linear light: every repainted surface returns 60-100 % of the server's light, the room
   light keeps 90-100 % of its output, and a closed door stands out from its wall as the server built it (±10 %).
   Five palettes were retuned.
2. **A new room showed the server's colours for up to 14 frames, then snapped** (low). A room is now dressed and
   repainted on the first frame it exists or comes into view, and the entry room during the ride. A new gate,
   `check_facilitynightmare_firstframe`, audits every frame at 60 Hz.
3. **Hazards are rarer than the brief, and a walking player almost never gets the near-hit** (low). Framed with the
   measured near-hit share for Gustav's call (§3, §10). No number changed.
4. **The DEPTH RECORD board never highlighted THE VOID** (low). Fixed.
5. **Particles that are not self-lit were probably drawn full-bright in dark rooms** (low, plausible). Every emitter
   now sets `LightInfluence`, and every particle, self-lit or not, stops when its room goes dark.

**Resume session (2026-09-24).** An earlier build was cut off by a usage limit while it wrote this file. The
code it left was complete and every gate was green. This session re-read every new and changed file, re-ran
every gate, and found and fixed the following. Each fix was test-first: the new assertion was watched failing
on the unfixed build.

1. **The ring is out of view in first person (§3).** Floors are LockFirstPerson. A ring 3.5 studs out at your
   feet sits about 50-55° below eye level, the source is straight overhead, and the view spans about ±35°
   vertically (Roblox's default 70° field of view). The HUD banner is the telegraph a player can actually
   see, so it now says whether the step worked: `CHEMICAL LEAK — STEP OUT OF THE RING` while you are inside, `CHEMICAL LEAK — YOU ARE CLEAR`
   once you are out. It lasts exactly the telegraph.
2. **A hazard called off by a flicker kept its banner** for up to 3 s. It went on saying "step out of the
   ring" for a ring that was gone, while the player's room went dark.
3. **A hazard that fell due at the lift landed on the next arrival.** The hazard clock carries over between
   sublevels (it freezes, it never resets), and no hazard may start on the car or lift pad. So a player
   waiting at EXTRACT / DESCEND let one fall due, and it fired 0.6 s after the next arrival, on top of
   `THE POWER IS FAILING — STAY IN THE LIGHT`. Now no hazard starts in the first 6 s on a sublevel.
4. **Text.**
   - The bands' flavour lines were dead config; they now show on the ride down.
   - Band 7 read "Going down to the THE VOID…".
   - The rest hint was 101 characters, longer than any hint the HUD had before (81).
   - New banners and hints are held to the longest ones the HUD already showed.
5. **The env check was flaky (1 of 8 runs).** Its densest-floor walk could route the bot through a fuse room.
   The bot picked up the fuse, the first run's hold on the dark ended, and the floor ended under the check.
   It now routes only through fuse-free rooms, with a control per band. 24 of 24 runs green after.
6. **No mutation sweep had been run.** The first sweep found 6 promises no gate held, and the final sweep 2
   more. All 8 are held now (§7).
7. **Two robustness fixes.**
   - The burst visual assumed the floor top is at y = 0; it now reads the floor height.
   - A rolled overhead run (the flooded kit's dripping pipe, chance 1) gave up if its one random wall was
     blocked: 134 of 6 825 real rooms had no drip. It now tries the other walls: 0 of 6 825.
8. **A measurement of hazard rarity in real play**, not only per lit minute (`tests/hazards.measure.luau`, §3).

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from plus1-jump (md5 `c6fc63a1…`): progress → band + eased blend, frame-rate-independent glide. Its spec is copied verbatim too. |
| `src/shared/Hazards.luau` | **adapted** from plus1-jump. Kept: a clock that freezes and never resets, 120-180 s between hazards, one at a time, and "the ring is what hits". FACILITY-specific: hazards come down from the ceiling (nothing flies), start only on a legal spot in a lit room, and are called off by a flicker. `arrivalOk` (this session): none in the first 6 s on a sublevel. |
| `src/shared/Rest.luau` | **adapted** from plus1-jump: rest is a state, allowed only in the break room. `validate` refuses any run phase. |
| `src/shared/Dressing.luau` | pure: each band's kit of room dressing, and the rules that keep it fair. It never sees an item. Review round: `linear`, `returned` and a `paletteOk` that works in linear light (§11, finding 1). |
| `src/shared/EnvBus.luau` | a client-local message bus, Env.client → HUD. No Instance, nothing replicates. |
| `src/shared/EnvArt.luau` | client art. It builds room dressing, screens, particles, the break room's dressing, the DEPTH RECORD board and the hazard visuals, and recolours rooms on this client only. Review round: every emitter sets `LightInfluence`; the board highlights THE VOID. |
| `src/client/Env.client.luau` | the glue: grade by sublevel, dressing, glow follows power, hazards, rest. Review round: a room is dressed on the first frame it can be seen; a dark room's particles are off and take none of the emitter budget. |
| `src/client/Hud.client.luau` | band name on the SUBLEVEL banner. The ride hint gives the band and its line. Hazard banner: STEP OUT / YOU ARE CLEAR, hidden when the hazard is called off. The rest line. |
| `src/server/Main.server.luau` | **one change**: two benches (real `Seat`s) on the break room's south wall. |
| `src/shared/Config.luau` | + `Env` (base values, break-room grade, 7 bands), `Hazards` (6 kinds, `ArrivalGraceSeconds`), `Rest`, `Budget`. No survival number changed. Review round: `Env.ReflectanceMin`, `LightOutputMin`, `DoorContrastMin` / `Max`, and five retuned palettes. |
| `tests/` | specs `EnvBands` `EnvBus` `EnvConfig` `Hazards` `Rest` `Dressing`; the measurement `hazards.measure.luau`. |
| `robloxemu/check_facilitynightmare_env.luau`, `_hazards.luau`, `_firstframe.luau` | headless glue checks through the real server, HUD and Env.client. `_firstframe` (review round) audits every frame at 60 Hz. |

---

## 2. The bands and what triggers them

**Trigger: the sublevel number, never time.** The band is read off the server's `run.k`, the same number the
HUD shows (`SUBLEVEL 5`) and that `leaderstats.Deepest` records. You cannot be on sublevel 9 without having
powered the eight above it, so the band is real progress.

**Transitions never cut.**
- **Foreshadowing.** A band blends in over 1.5 sublevels before it starts (a smoothstep). On the last
  sublevel of the band before, about 26 % of the rooms already wear the next band's kit and palette, and the
  colour grade is 26 % of the way there. Which rooms is a hash of (sublevel, room id), so the labs creep into
  the offices before you reach them.
- **The ride is the transition.** The grade glides with a 0.8 s half-life, so the 4 s ride down is five
  half-lives. Measured in `check_facilitynightmare_env` C: the break room → offices ride makes 16 tint
  writes, the largest step is 2.0 of a 24.0 change, and 2.0 is left on arrival. Lighting is written at most
  10 times a second, and only on change.
- **The ride names it.** As the ride starts, the banner names the band (`SUBLEVEL 5 — SERVER VAULT`, 3 s),
  and the hint gives its line (`Going down to the SERVER VAULT… The machines are still thinking.`).

**Never brighter, never easier to see.**
- A band's grade may only darken and tint the server's `Fx.Presets.Facility`:
  - tint luma 80-100 % of the preset's;
  - brightness never above it;
  - contrast preset..+0.2;
  - saturation -0.5..0;
  - atmosphere colour and decay never brighter.
  It may not touch density, haze, glare, exposure, ambient, bloom or depth of field.
- A palette recolours the server's own walls, floor, ceiling and doors **on this client only**, in matte
  materials only. It may change their hue, not how much light they give back. In **linear light**, under the
  flashlight's white light and under the room's own light (review round, §11):
  - every surface returns **60-100 %** of the light the server's surface did: never brighter, and never
    darker than about 80 % as bright on screen (0.6^(1/2.2) ≈ 0.79), the same allowance the grade's tint has;
  - the room light's colour carries **90-100 %** of the server's light. Brightness, range and on/off stay the
    server's;
  - a closed door stands out from its wall **90-110 %** as much as in the server's room (wall light / door
    light, 2.6 there), so doors are no harder, and no easier, to find than designed;
  - before the review these rules were in gamma luma (25-100 %) with no door rule. 26 % of the gamma luma is
    7 % of the light, and in three bands the closed door was as bright as its wall.
- `EnvConfig.spec` checks every band, the break room, and every blend at every 0.05 of a sublevel. The env
  check compares the base values against the real Lighting and a real built room.

**Glow follows power.** Every self-lit piece (Neon, glowing screens) and, since the review round, **every particle
emitter, self-lit or not** (steam, drips, fumes and motes too) is on only while its own room's light is on at full
brightness. It flickers with the room and goes dark with it, and a dark room's emitters take none of the emitter
budget. Particles that are not self-lit are drawn lit by the scene (`LightInfluence` 1; Roblox's default is 0,
unaffected by light); self-lit ones say so (0). The environment creates no light source at all. Measured in the env check's section F, over three real sublevels: 407 - 5 149
observations of dark or flickering dressed rooms per run (24 runs), 0 self-lit things in them.

**Nothing hides a fuse.** Measured on real rooms by `Dressing.spec`, and on the built instances by the env check.
- Wall pieces lie within 2.5 studs of a wall. Items stand at least 6 studs off every wall.
- Everything else hangs above 6.5 studs (above a standing eye) and out of the centre column.
- Floor films (water, moss, papers, ink) are at most 0.2 thick. Items float at 0.7 and higher.
- No particle reaches the item volume.
- Below the door height, nothing stands in front of the middle of any wall, door or not, so the dressing
  does not even say where the doors are.
- Nothing glowing is within 30° of hue of a fuse's amber or a cell's green, and nothing painted is a bright
  amber or green.
- The env check re-derives these rules on the built instances. It also casts sight lines from every standing
  spot to the room's real item: no dressing ever came between an eye and an item.

### The seven bands

Reach and arrival come from `tests/hazards.measure.luau`: perk-less runs through the real server, played by
`tests/Bot.luau` at DESIGN.md's speed proxies (medium = 12.8 studs/s, slow = 10.4, perfect = 16), 120 / 80 /
40 runs. "Arrival" is minutes into the run, among the runs that got there. The numbers are the review round's
run on the final tree. The resume session's run gave medium 98 / 85 / 63 / 48 / 34 / 17 % for labs to void; the
palettes cannot move them (the bot reads the workspace, not colours), so the spread between the runs is sampling.

| # | band (banner) | sublevels | look (grade, room palette) | dressing (per room: 3-5 wall pieces, overhead runs, hanging pieces, desk items) | particles | hazard | reached (medium / slow / perfect) | arrival p50 (medium) |
|---|---|---|---|---|---|---|---|---|
| 1 | ADMIN OFFICES | 1-2 | pale fluorescent green-grey; beige-grey walls, blue-grey carpet | filing cabinets, cubicle dividers with an office chair, water cooler, notice board (SAFETY FIRST), potted plant, wall clock stopped at 3:17, monitors and keyboards on desks, scattered papers | none | none: a first run meets the dark before anything else | 100 % / 100 % / 100 % | 0 min |
| 2 | LABORATORIES | 3-4 (26 % of sublevel 2's rooms) | cold cyan; pale teal walls | lab benches with glowing violet and cyan flasks, a fume hood with slow fumes, shelves of glowing jars, whiteboard (DO NOT OPEN TANK 3), biohazard bins, microscopes with a glowing slide, ceiling ducts | fumes | CHEMICAL LEAK | 98 % / 95 % / 100 % | 1.9 min |
| 3 | SERVER VAULT | 5-6 | cold blue, higher contrast; steel-blue metal walls, diamond-plate floor | rack pairs with blinking blue/red/white LED faces, a rack with a cable bundle, a cooling unit, a breaker box with a loose sparking cable, laptops, cable trays, drooping cables | sparks | ARCING CABLE | 91 % / 70 % / 100 % | 4.3 min |
| 4 | FLOODED MAINTENANCE | 7-8 | teal-green murk; stained green-grey concrete, brown doors | water over the whole floor, rusted pipe runs with red valve wheels, valve banks, pumps, rust streaks, an overhead pipe dripping into the water | drips | BURST PIPE | 72 % / 28 % / 98 % | 7.6 min |
| 5 | REACTOR CORE | 9-10 | warm orange, high contrast; warm grey metal, hazard-brown doors | coolant risers with hazard-yellow bands, yellow/black HIGH TEMPERATURE panels, pulsing red beacons, consoles reading CORE 712 C / PRESSURE HIGH, steam vents, coolant ducts | steam | STEAM VALVE | 55 % / 8 % / 95 % | 10.5 min |
| 6 | OVERGROWN BIO-LAB | 11-12 | green; moss-green concrete, earth floor | vines up the walls, specimen tanks of glowing teal liquid, glowing blue fungi, cracked panels with roots, ceiling vines, hanging vines with seed pods, moss | drifting glowing spores | SPORE POD | 30 % / 1 % / 90 % | 13.3 min |
| 7 | THE VOID | 13+ | desaturated violet, darkest grade; dusky violet slate | glitching wall panels, violet tears that flicker, black monoliths, ink pools, cracks with rising motes, stone debris floating and bobbing overhead | motes | RIFT | 12 % / 0 % / 80 % | 16.2 min |

Perks push these up: every row above is perk-less. The void is the long-term goal, the brag for players who
have bought perks and learned the dark. At the medium proxy nearly every run sees the labs and about half
reach the reactor; at the slow proxy most runs end in the labs or the server vault. The last band starts by sublevel 13
(`EnvConfig.spec`), and every band lasts at least two sublevels.

**The break room** has its own warm grade, never brighter than the facility's.
- Along the walls: a lit vending machine, a coffee corner with a steaming cup, a water cooler, three potted
  plants, a rug under two benches, and posters (`IF THE LIGHTS FLICKER — RUN`, `DAYS WITHOUT AN INCIDENT: 0`).
- The **DEPTH RECORD** board faces a player who has just spawned. It shows `DEEPEST: SUBLEVEL n` and every band
  you have reached by name. The ones below stay `???` (no spoilers), and your current band is highlighted.
- It is built once on the client and parented only while you are in the break room. All of it keeps off the
  spawn → car → arrival path, the benches, the perk terminal and the car (asserted).

---

## 3. Hazards and their measured rarity

| kind | band | telegraph | burst | ring (hit radius + 1.5 player) | knock (studs/s) | lift | the look |
|---|---|---|---|---|---|---|---|
| CHEMICAL LEAK | labs | 3.0 s | 0.5 s | 7.0 wide | 18 | 0 | violet drips from a ceiling fitting, then a violet splash |
| ARCING CABLE | servers | 2.8 s | 0.4 s | 6.6 | 22 | 2 | blue-white sparks, then an arc floor to ceiling |
| BURST PIPE | flooded | 3.0 s | 0.6 s | 7.0 | 20 | 0 | drips, then a water column |
| STEAM VALVE | reactor | 3.0 s | 0.6 s | 7.0 | 22 | 1 | wisps, then a steam column |
| SPORE POD | bio-lab | 3.2 s | 0.6 s | 7.4 | 16 | 0 | teal spores, then a teal splash |
| RIFT | void | 3.0 s | 0.5 s | 7.0 | 24 | 3 | violet sparks, then a violet arc |

**Rules** (`Hazards.luau`, validated at load; an invalid config switches hazards OFF with a warning and costs
nothing else):

- **Rarity.** One every 120-180 s of *exposed* time. Exposed means on a sublevel, in a lit room, in a band that
  has hazards. The clock **freezes** everywhere else (dark rooms, the quiet offices, the ride, the break room)
  and never resets, so walking in and out of a dark room cannot thin hazards out. Never two at once, never a
  backlog: a hazard that falls due waits for a legal spot, and exactly one comes.
- **Where.** It comes down from the ceiling onto the spot you stand on, which must be a legal spot:
  - at least 6 studs off every wall (the room's interior, never in a doorway; whether a real humanoid's
    shove can still carry anyone through one is on the Studio list);
  - off the car's or lift's 10 × 10 pad;
  - not under the light fixture.
- **Never in the dark.** Only in a lit room. If its room starts to flicker it is called off at once: ring,
  source and banner all go. The dark's 2-second warning outranks everything, and a hazard never adds to the
  dark.
- **Never on arrival** (this session). None in the first 6 s on a sublevel. That time belongs to the
  arrival's `THE POWER IS FAILING — STAY IN THE LIGHT` banner and the "Find N fuses" hint. A hazard that
  fell due while you waited at the choice waits too.
- **The ring is what hits.** A hit needs you inside the ring (hit radius + your 1.5-stud radius) when it
  bursts. Stepping out in any direction dodges. The widest ring is 7.4 studs, so the longest walk out from
  its centre is 3.7 studs: 0.36 s at the slow proxy's 10.4 studs/s, inside even the shortest telegraph (2.8 s)
  with a full second to react. `Hazards.validate` enforces this for every kind.
- **What a hit does.** A shove (16-24 studs/s horizontally, at most 3 up) and a camera shake. Nothing is lost:
  no battery, no exposure, no Essence. The server never hears of it.

**First person: the banner is the telegraph.** On a floor the camera is LockFirstPerson. The ring on the
floor and the source on the ceiling are out of view unless you look down or up, so the red HUD banner does
the telling:

- the moment it starts: `SPORE POD — STEP OUT OF THE RING`, in red;
- once you are out: `SPORE POD — YOU ARE CLEAR`, in green. It turns red again if you walk back in;
- it lasts exactly the telegraph, and disappears if the hazard is called off.

The banner is never longer than the longest banner the HUD already showed (40 characters, "THE POWER IS
FAILING — STAY IN THE LIGHT"). The ring pulses faster as the burst nears, and the warning particles thicken.

**Measured.**

| measurement | where | result |
|---|---|---|
| the scheduler on its own, 20 h exposed | `Hazards.spec` | 480 hazards = **one per 150 s exposed**, every gap 120.1-180.0 s |
| exposure toggled every 6 s, or 40 s of every 150 s, for 6 h | `Hazards.spec` | 144 / 144 / 144, identical to continuous: freezing never thins hazards |
| a stand-and-walk model in lit rooms, 10 h | `Hazards.spec` | a player who **reacts**: 0.393 hazards/min = **one near-hit per 2.5 exposed min, 0 hits**. One who **ignores** the warnings: hit once per 12.5 exposed min (hit share 0.20) |
| walk out at 10.4 or 16 studs/s after 1 s, in 36 directions, both of the spec's own kinds | `Hazards.spec` | 0 of 144 hit; a player who stays put is hit |
| through the real client on a held, lit floor, 18 hazards | `check_facilitynightmare_hazards` C | one per 146-157 s of lit time, gaps 120.5-178.9 s. Stand still: 9 of 9 hit. Step out a second after the warning: 9 of 9 dodged, and the banner said YOU ARE CLEAR before the burst every time. The ring was drawn where the player stood, as wide as the zone |
| 10 min in a dark room, then lit again | same, D | no hazard in the dark; the next came 124-177 s of *lit* time after the last (frozen, not reset) |
| 200 s on the entry car's pad, then 200 s in the powered lift at the choice, each with a hazard long due | same, E | none on either pad. A step off the car's pad and the waiting hazard came at once. After DESCEND it came 5.9 s after arrival, not 0.6, and THE POWER IS FAILING kept its 3 s |
| **real runs**, perk-less, the bot ignoring every warning and never stopping, medium proxy (12.8), 120 runs, 1 329 floor-minutes (review round, final tree) | `tests/hazards.measure.luau` | **one hazard per 4.3 minutes on a floor**, one per 2.8 exposed minutes; one per 3.3-4.0 floor-minutes in the bands that have hazards (labs 3.3, servers 3.9, flooded 4.0, reactor 3.8, bio-lab 3.5, void 3.3); one per 28 in the offices (only sublevel 2's foreshadowed lab rooms). 26 of 307 called off by a flicker. **Near-hit share: 2 of 281 bursts (0.7 %) landed within 8 studs of the bot.** 1 hit in 1 329 minutes. Hazards per run: 0: 4, 1: 22, 2: 33, 3: 31, 4: 25, 5: 4, 6: 1 |
| same, slow proxy (10.4), 80 runs, 642 floor-min | same | one per 5.4 floor-min; near-hits 1 of 108 bursts (0.9 %); 1 hit |
| same, perfect (16), 40 runs, 574 floor-min | same | one per 3.7 floor-min; near-hits 3 of 145 bursts (2.1 %); 3 hits |
| the resume session's run of the same file (before the review round) | same | medium one per 4.4 floor-min (3 near-hits in 266 bursts), slow 5.4, perfect 3.7: the same rates within sampling |

**What that means against the brief** (reframed in the review round, finding 3). A hazard comes about once every
3.3-4 minutes of play in a band that has hazards, and once per 2.5-2.8 minutes of *lit* time, the brief's number.
It is rarer per minute of play because dark rooms freeze the clock. That is deliberate: the dark is FACILITY's
threat, and a hazard must never add to it.

Whether each hazard is a **near-hit** depends on the player, and the brief asked for near-hits:
- The ring is drawn where you stood **when the warning started**. A player who **stops** when the banner goes up
  and steps out has a near-miss every time: one per 3.3-4 minutes of play.
- A player who **keeps walking** is out of the ring (3.3-3.7 studs in radius) within 0.2-0.4 s at 10.4-16 studs/s.
  The banner turns from STEP OUT OF THE RING to YOU ARE CLEAR almost at once, and the burst happens behind them,
  out of view in first person. The bot never stops walking, and **6 of 534 bursts (1.1 %) landed within 8 studs of
  it** over all three speeds (0.7 % at the medium proxy). For a player who plays like the bot, a hazard is a red
  banner and a burst they do not see, not a near-hit.
- Real players are somewhere between: they stop to look around and to pick up items. How often is a Studio and
  real-player question (§8 item 16).

A human who looks around in a lit room and ignores the banner is hit about once per 12.5 lit minutes (the spec's
model). The bot's 5 hits in 2 545 minutes are not a human's number.

This is **Gustav's call** (§10); nothing was changed.

`IntervalMin` / `IntervalMax` in `Config.Hazards` is the knob. `EnvConfig.spec` pins 120 / 180 so a retune is
deliberate.

---

## 4. Rest: what "pause" means in FACILITY

A Roblox server cannot stop the world for one player. In FACILITY the world *is* the clock: a run is the
blackout front spreading ring by ring through the floor. Every survival number in DESIGN.md was measured
against it. So **rest is between runs, in the break room**, where there is no front, no hazard, no clock and
nothing to lose:

- **Sit on a bench.** Two real `Seat`s on the break room's south wall. Walk into one to sit, and jump to stand,
  the Roblox way. Everyone in the break room sees you sitting. Resting starts at once.
- **Or stand still for 20 s** in the break room (AFK-safe).
- While resting, the view softens (a mild far depth of field) and the hint reads `Resting — nothing reaches
  the break room, and nothing is lost. Get up when ready.` Standing up, moving, stepping into the elevator car
  or a run starting ends it.
- Roblox's own idle disconnect (about 20 minutes without input) still applies. Nothing is lost by it in the
  break room: no run is open there, and the profile is saved.

**Why it cannot be exploited**

1. **Rest can never happen in a run.** `Config.Rest.Phases = { hub = true }`. `Rest.validate` refuses a
   config that names `ride`, `floor` or `dying`, and refuses any phase it does not know, so a typo cannot open
   a hole. `EnvConfig.spec` pins "hub" as the only phase. Mutation R1 (rest allowed on a floor) is killed by
   EnvConfig.spec, the env check and the hazards check. A player seated for 2 s on sublevel 2 is not resting
   (env check F).
2. **Rest has no hook into anything that matters.** It is client presentation only. `Rest.PAUSES_RUN_CLOCK`
   is false, the server never hears of it (Env.client fires no remote), and the run clock is the server's
   (`run.clock`, accumulated in its tick loop). A modified client that "rested" mid-run would pause nothing:
   the only thing rest could ever pause is the client's own hazards, and on a floor it is refused.
3. **Nothing in the break room can be dodged.** No front, no hazard (6 minutes there with a hazard kind forced
   on: none, hazards check A), and no timed leaderboard: the board is `Deepest`.
4. **The one place a run can stop was already there, and it pauses nothing.** A powered freight elevator never
   goes dark (DESIGN.md §2.2), so the EXTRACT / DESCEND choice has no timer. That is not a rest feature and
   this work did not change it.
   - Standing there, the rest of the floor still dies around you. The sublevel's pay was already credited when
     the lift powered, and the next sublevel starts only when you choose.
   - No hazard ever targets the lift's pad (hazards check E: 200 s with one long due). A hazard that falls due
     there waits out the 6 s arrival grace on the next sublevel.
   - Idling there is not free. Roblox's idle disconnect would end the run as `left`, which pays the keep
     percentage (25 % base), not the full run. EXTRACT banks it all. The break room is the place to rest.

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| colour grade and atmosphere by band | **client** (`Env.client`) | cosmetic and per player; the server keeps `Fx.Presets.Facility`, and a band may only darken it |
| room dressing, palettes, screens, particles, glow following power | **client** (`EnvArt`, `Dressing`) | cosmetic. The server builds every room exactly as before. The client adds local parts and recolours the server's parts on this client only (client changes to replicated parts do not replicate) |
| floor-standing wall furniture colliding | **client**, for this player only | you cannot walk through a filing cabinet. It stands only in the wall band, off every doorway, so it cannot block a route. The server's trusted position knows nothing of it and needs nothing |
| hazards: schedule, telegraph, hit, shove | **client** | it only ever harms the local player, whose character physics the client already owns. Nothing is lost by a hit, so a client that deletes its hazards gains nothing |
| rest | **client**, plus two server `Seat`s | the benches are real props everyone sees; resting itself is presentation |
| band names on the banner, the ride's line, the hazard banner, the rest line | **client** (`Hud.client`, over `EnvBus`) | EnvBus is a plain Lua table both LocalScripts require: no Instance, nothing replicates. The HUD draws these where its own layout, already checked on 10 viewports, fits them |
| runs, the front, trust, pay, saves, perks | **server, unchanged** | authoritative, as before. The server's only change is the two benches |

**Leak review.** This repo has closed replication leaks before: fork-tower REVIEW-3, and REVIEW-1 A1 here,
where one Fuse position gave away every fuse room.

- **What Env.client reads.** Its own State (`phase`, `run.k`, `run.flicker`, `run.dark`, `bestSublevel`,
  `boarding`). Rooms that already exist (a room exists only after a trusted door-open), their `Floor`,
  `Prop*`, walls and `Fixture.RoomLight`. Door-leaf names, and the car's and lift's plates.
- **What it never reads.** It never names a Fuse or a Cell, never reads ServerStorage or FacilityDebug, never
  requires Facility, Trust, Survival, Economy, MazeGen or Rng, and sees no plan or seed. `check_facilitynightmare_env`
  A asserts this on the shipped source. It also asserts that Env.client, EnvArt, Dressing, Hazards, Rest and
  EnvBus never call `FireServer`, `InvokeServer`, `SetAttribute` or `PivotTo` and create no light source.
- **What a room's look depends on.** Its dressing is a function of (kit, room id, sublevel, the room's props)
  and never of its item. `Dressing.build` has no item input. A room's band is a hash of (sublevel, room id), all
  public. No hazard's position is a draw of anything but the local player's own position.
- **What the server's world looks like after.** The env check snapshots every server part and light on the
  floor, re-dresses it through all seven bands, and compares: only colours and materials changed on this
  client. The zones still carry zero attributes.
- **Spawn order** (`robloxemu/SPAWN-ORDER.md`) is untouched. The client never writes the character's CFrame,
  and the benches are Seats, not spawns. HubSpawn is still the only enabled SpawnLocation (asserted in the
  env check with the benches present).

**What other players see.** Floors are one player per zone, so nobody sees your dressing or your hazards. In
the break room everyone sees the benches and who sits on them; the rest of the break-room dressing is local
and identical for all.

---

## 6. Budgets (measured)

Everything visual is built on the client; the server builds none of it (apart from the benches: 2 Seats, 2
backs, 2 bases, 6 parts). `Config.Budget`, enforced in code where it matters:

| metric | measured peak | where | budget |
|---|---|---|---|
| local parts | **207** | the densest floor, bio-lab kit | 240 (arithmetic worst case: 16 rooms within 60 studs × 14 parts + 8 hazard parts = 232) |
| particle emitters on | **4** (the cap) | densest floors, most kits | 4, nearest lit rooms first, and a live hazard takes one |
| particles per second | **27** | densest floors | 40 |
| screens (SurfaceGuis) on | **16** (the cap) | densest server vault | 16, nearest rooms first |
| light sources | **0** | anywhere | 0 |
| hazard parts | **3** (ring, source, burst) | per hazard | 8 |
| hazards at once | **1** | | 1 |
| break-room dressing | **18** parts, 1 emitter | only while you are in the break room | 40 |

Peaks come from 24 runs of `check_facilitynightmare_env` on the review round's final build, one floor each,
since floors are random; each column is its own peak over the 24 runs. In each run it walks every room reachable
without a fuse, to every room's centre and four corners, in each of the seven kits. That reaches 1 to 13 rooms
depending on where the fuses lie. The resume session's 24 runs peaked at 203 parts (206 before its pipe fix):
the spread is the random floors, since the review round changed no part.

| kit | densest floor: parts / emitters on (rate) / screens on | held floor, 4 rooms built |
|---|---|---|
| offices | 146 / 0 / 9 | 44 / 0 / 6 |
| labs | 189 / 4 (14/s) / 9 | 55 / 3 (9/s) / 7 |
| servers | 147 / 4 (24/s) / 15 | 41 / 4 (20/s) / 12 |
| flooded | 173 / 4 (26/s) / 0 | 47 / 4 (24/s) / 0 |
| reactor | 122 / 4 (20/s) / 9 | 34 / 4 (20/s) / 8 |
| bio-lab | **207** / 4 (16/s) / 0 | 56 / 3 (12/s) / 0 |
| void | 139 / 4 (24/s) / 11 | 43 / 3 (15/s) / 7 |

**How it stays cheap.**
- **Rooms.** A room is dressed the first time it is built within 60 studs. It is **unparented** when you walk
  out of range and destroyed with its floor. At most 14 parts, 1 emitter (at most 10/s) and 3 screens per
  room (`Dressing.check`, asserted on every real room).
- **Emitters and screens.** They run only in rooms within 32 studs (yours and the ones you see into), nearest
  first, up to the caps. Since the review round an emitter runs only in a lit room, so a dark room near you
  takes none of the emitter budget.
- **Animation.** Bobbing debris, pulsing beacons and flickering tears move only in near rooms. Screen blinks
  step 4 times a second.
- **Hazards.** One pooled model per hazard kind (3 parts), parented only while live.
- **Lighting.** Written at most 10 times a second, only on change. Dressing passes run 4 times a second, and at
  once on a frame where a room that should be dressed is not (review round): a check of at most 25 rooms per
  frame, one table lookup for a room already dressed.
- **Checked** (env check D1 and hazards check C, caps lowered in memory; since the review round also env check
  E, a dark room's emitters stopping):
  - a room out of range is put away and comes back in range;
  - with the emitter cap at 1, exactly one room's emitter runs;
  - with the screen cap at 1, at most one room's screens run;
  - with the emitter cap at 1, a live hazard's warning takes the room's emitter, never both.

These are part and emitter counts, not frame times. Frame time on a real phone, and what 16 SurfaceGuis cost
there, are on the Studio list.

---

## 7. Gates

Git Bash from `D:\Claude\Roblox`; commands in CLAUDE.md. Bundle rebuilt before every headless run.

| gate | before the environment (HEAD) | as the cut-off attempt left it | final (resume session) | after the review round (§11) |
|---|---|---|---|---|
| `tests/Config.spec` | 106 / 0 | 106 / 0 | 106 / 0 | 106 / 0 |
| `tests/Economy.spec` | 93 / 0 | 93 / 0 | 93 / 0 | 93 / 0 |
| `tests/Facility.spec` | 84 / 0 | 84 / 0 | 84 / 0 | 84 / 0 |
| `tests/Survival.spec` | 74 / 0 | 74 / 0 | 74 / 0 | 74 / 0 |
| `tests/Trust.spec` | 53 / 0 | 53 / 0 | 53 / 0 | 53 / 0 |
| `tests/Responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/Rng.spec` | 37 / 0 | 37 / 0 | 37 / 0 | 37 / 0 |
| `tests/MazeGen.spec` | 3 / 0 | 3 / 0 | 3 / 0 | 3 / 0 |
| `tests/Fx.spec` | 26 / 0 | 26 / 0 | 26 / 0 | 26 / 0 |
| `tests/EnvBands.spec` (verbatim template) | — | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/EnvBus.spec` | — | 11 / 0 | 11 / 0 | 11 / 0 |
| `tests/EnvConfig.spec` | — | 382 / 0 | **417 / 0** | **475 / 0** |
| `tests/Hazards.spec` | — | 82 / 0 | **92 / 0** | 92 / 0 |
| `tests/Rest.spec` | — | 43 / 0 | 43 / 0 | 43 / 0 |
| `tests/Dressing.spec` | — | 75 / 0 | **79 / 0** | **87 / 0** |
| **spec total** | **546 / 0** | **1 263 / 0** | **1 312 / 0** | **1 378 / 0** |
| `check_facilitynightmare` | 203 / 0 | 203 / 0 | 203 / 0 | 203 / 0 |
| `check_facilitynightmare_input` | 116 / 0 | 116 / 0 | 116 / 0 | 116 / 0 |
| `check_facilitynightmare_desktop` | 47 / 0 | 47 / 0 | 47 / 0 | 47 / 0 |
| `check_facilitynightmare_hud` (10 viewports × 3 modes) | PASS | PASS | PASS | PASS |
| `check_facilitynightmare_env` | — | 191 / 0 (1 run in 8 crashed: the introduction's item 5) | **221 / 0** | **251 / 0** |
| `check_facilitynightmare_hazards` | — | 28 / 0 | **42 / 0** | **44 / 0** |
| `check_facilitynightmare_firstframe` (review round) | — | — | — | **18 / 0** |
| `tests/walk.luau` (count varies with depth) | 70 / 0 | 55 / 0 | 55-63 / 0 (3 runs) | 55-71 / 0 (4 runs) |
| **headless total**, the counted checks (the walk's count varies with depth) | 366 / 0 + PASS | 585 / 0 + PASS | **629 / 0 + PASS** | **679 / 0 + PASS** |
| compile every file (see below) | 12 sources | — | **44 of 44 files clean**: 19 sources, 19 test files, 6 checks | **45 of 45**: 19 sources, 19 test files, 7 checks |
| `rojo build` (Rojo 7.7.0) | builds | builds | builds; the place holds `Env` and `Hud` LocalScripts and every new module | builds; the place holds the review round's code |

**Stability after the review round** (bundle md5 `1bbf3b9a…`; the final bundle, `735c51b3…`, differs from it by one
comment line in Env.client, diffed, and ran every gate once more, all green): `check_facilitynightmare_env` **24 of 24** at
251 / 0; `_hazards` **10 of 10** at 44 / 0; `_firstframe` **20 of 20** at 18 / 0 (72 840 frames at 60 Hz, 306 rooms
appearing, 345 108 room-frames and 791 808 door-leaf-frames audited, 0 frames of a room in view and not ready);
`_desktop` **20 of 20**, `check_facilitynightmare` and `_input` **10 of 10** each; the walk 4 of 4.

**Stability (resume session).** Floors are random every run and the emulator's `Random` is unseeded, so the two new
checks were run many times on the final build.
- `check_facilitynightmare_env`: 24 runs after the D2 fix, then 6-8 runs after each later change, all green.
  The final build ran **24 of 24 at 221 / 0**.
- `check_facilitynightmare_hazards`: 4-6 runs after each change. One of 4 runs failed its new emitter
  control, because the entry room had no dripping pipe; that is the pipe fix in the introduction's item 7.
  The final build ran **10 of 10 at 42 / 0**.

**Compile, and what could not run.** `luau-compile.exe` and `luau-analyze.exe` were no longer in the shared
scratchpad (another session removed them). Every file was compiled with `luau.exe` + `loadstring` instead.
That checks syntax only and runs nothing; a deliberately broken file fails it, as the control. **`luau-analyze`
was not run at all this session.**

### Mutation sweep (review round, the final tree)

Driver: `scratchpad/fn_fix/sweep/sweep.py` (the resume session's driver, unchanged) with a new `mutations.py`: the
resume session's 45 mutations and 3 controls re-run on the final tree (B2's text follows the new budget line), plus
19 mutations and 3 controls for the review's fixes. Five workers on fresh copies, **all 23 suites** per mutation
(15 specs, the walk, 7 checks), every mutation **proved to be in the rebuilt bundle**, the original bytes restored
and md5-checked, and the bundle proved back to the baseline after each. The baseline bundle equalled the real
tree's.

**Result: 64 of 64 KILLED, all 6 controls SURVIVED.** After the sweep, all 23 suites were green on the baseline.

| id | mutation (review round) | killed by |
|---|---|---|
| R2-P1 | `paletteOk`: the light-output rule removed | EnvConfig.spec |
| R2-P2 | `paletteOk`: surfaces checked under the flashlight only | EnvConfig.spec |
| R2-P3 | `paletteOk`: no reflectance floor (never brighter only) | EnvConfig.spec |
| R2-P4 | `paletteOk`: the door/wall contrast rule removed | EnvConfig.spec |
| R2-P5 | `paletteOk`: no upper bound on door/wall contrast (doors easier to find) | EnvConfig.spec |
| R2-P6 | `Dressing.linear` is gamma (the old luma arithmetic) | Dressing.spec, EnvConfig.spec |
| R2-P7 | `Dressing.returned` ignores the light colour | Dressing.spec, EnvConfig.spec |
| R2-P8 | `ReflectanceMin` 0.6 → 0.25 | EnvConfig.spec |
| R2-P9 | the void's old near-black palette | EnvConfig.spec, env, firstframe, hazards (Env.client refuses the environment) |
| R2-P10 | the server vault's door the colour of its wall | EnvConfig.spec, env, firstframe, hazards |
| R2-P11 | door leaves never repainted | env, firstframe |
| R2-F1 | no per-frame check: dressed only in the 4 Hz pass (the review's defect) | firstframe |
| R2-F2 | the ride does not dress the entry room wherever it is | firstframe |
| R2-F3 | no pass forced when the run or the sublevel changes | firstframe |
| R2-F4 | the per-frame check ignores a room put away and back in range | firstframe |
| R2-B1 | the DEPTH RECORD board never highlights its last row | env |
| R2-E1 | `LightInfluence` never written (Roblox's default 0) | env, hazards |
| R2-E2 | `LightInfluence` 1 on self-lit particles too | env, hazards |
| R2-E3 | a dark room's emitters keep running (the budget ignores power) | env |
| R2-CONTROL-1 | the void's ceiling a shade redder, still inside every rule | SURVIVED, as it must |
| R2-CONTROL-2 | `paletteOk` checks the room's light before the flashlight | SURVIVED, as it must |
| R2-CONTROL-3 | the periodic dressing pass a hair sooner (0.24 s) | SURVIVED, as it must |

The resume session's 45 were all killed again. Against the table below, the killing suites differ in six places:
G3 only by the env check (the desktop check's kill below was its one-off flake); B4 only by the hazards check and
D2 only by Dressing.spec (the env check's random floor did not catch them this time, the deterministic suites did);
B7, H11 and R1 by the new firstframe check as well.

Two notes on how the tests were made to hold:
- **R2-F2 is killed only when the entry room is more than 60 studs from the ride car.** Entries are on the
  perimeter, and for the 4 × 4 floors of sublevels 1-3 that is 10 of 12 cells. The check rides twice, so it
  misses the mutation only when both entries fall in the two near cells.
- **The power check for emitters had been in two places** (Env.client's budget and EnvArt), so mutating either
  alone would have changed nothing a test could see. It lives in the budget now and EnvArt applies it
  (CLAUDE.md trap 37). A negative-case assertion in EnvConfig.spec named the light a rule was broken under; it
  now names only the rule, so control 2 (which reorders the lights) is not killed for the wrong reason.

### Mutation sweep (resume session)

Driver: `scratchpad/fn_resume/sweep/sweep.py` with `mutations.py`.
- **Fresh copies.** Five workers, each with its own fresh copy of `facility-nightmare` and `robloxemu`
  (`emu`, `wrap.py`, every `check_facilitynightmare*`). The real tree is only read.
- **Per mutation:**
  - exactly one occurrence replaced, with the file's md5 recorded;
  - bundle rebuilt and **proved to contain the mutation** (the mutated bundle equals the baseline bundle with
    the same single replacement, path lines normalised);
  - **all 22 suites run**: 15 specs, the walk, 6 checks;
  - original bytes restored, md5 re-checked;
  - bundle rebuilt and proved identical to the baseline.
- **Baseline.** The baseline bundle was proved equal to the real tree's bundle.

**Three sweeps counted** (a fourth was stopped when the tree changed under it, and is not counted):

| sweep | tree | mutations | result | survivors, and what now holds each |
|---|---|---|---|---|
| 1 | this session's first fixes | 39 + 3 controls | 33 KILLED, 6 SURVIVED, controls survived | **B1** rooms out of range never put away: env check D1 shrinks `DressRadius` in memory. **B2** emitter cap ignored: D1 sets the cap to 1 with the flooded kit. **B4** a live hazard takes no emitter: hazards check C, flooded kit and cap 1 in memory. **D5** particles may reach the item volume: Dressing.spec now has an emitter legal in every other way and asserts the reason (the old case was too wide, 60°, and failed the spread rule first). **H2** two hazards at once: equivalent under any real config (120 s between hazards, 3.8 s per hazard), so Hazards.spec now pins it with a 0.5 s interval. **H4** hazards on the pads: hazards check E |
| 3 | + the arrival grace, banners and hints | 44 + 3 | 42 KILLED, 2 SURVIVED, controls survived | **B3** screen cap ignored: killed in sweep 1 only because that run's random floor put enough screens near the player. D1 now sets the cap to 1 over the first kit with two or more near screens. **H4** again: the pad test stood 1 stud off centre, which is also under the light fixture's keep-out, so the fixture rule decided. It now stands 4 studs out, on the pad and clear of the fixture |
| **4 (final)** | **the final tree** | **45 + 3** | **45 of 45 KILLED, controls survived** | none |

Every mutation in the final sweep was proven to be in the bundle. After the sweep every worker's bundle was
back to the baseline, and all 22 suites were green on it.

| id | mutation | killed by |
|---|---|---|
| G1 | grade never follows the band (the break room's grade everywhere) | env |
| G2 | grade snaps (half-life 0): a hard cut on the ride | env |
| G3 | grade driven by time (t/60), not by the sublevel | env (and desktop\*) |
| P1 | `roomPowered` always true: glow in dark rooms | env, hazards |
| P2 | the flicker's low step counts as powered | env, hazards |
| B1 | rooms out of DressRadius are never unparented | env |
| B2 | emitter cap ignored | env, hazards |
| B3 | screen cap ignored | env |
| B4 | a live hazard takes no emitter from the rooms | env, hazards |
| B5 | `Budget.MaxEmitters` 4 → 6 | EnvConfig.spec |
| B6 | dressing parts queryable | env, hazards |
| B7 | a palette paints walls white (brighter than the server built them) | env |
| D1 | `roomBand` never blends the next band in | Dressing.spec |
| D2 | doorway keep-out removed | Dressing.spec, env |
| D3 | a glowing piece may glow like a fuse or a cell | Dressing.spec |
| D4 | overhead pieces may hang below 6.5 studs | Dressing.spec |
| D5 | particles may reach the item volume | Dressing.spec |
| D6 | a rolled overhead run tries one wall only | Dressing.spec |
| H1 | the clock runs everywhere (dark rooms, quiet bands, rest) | Hazards.spec, hazards |
| H2 | a new hazard may start while one is live | Hazards.spec |
| H3 | `spotOk` ignores the car/lift pad | Hazards.spec, hazards |
| H4 | the client never detects the car/lift pad | hazards |
| H5 | hazards in dark or flickering rooms | hazards |
| H6 | a flicker never calls its hazard off | hazards |
| H7 | the ring drawn at half the zone | hazards |
| H8 | the shove never applied | hazards |
| H9 | the hit ignores where the player is (a step out does not dodge) | hazards |
| H10 | `IntervalMin` 120 → 60 | EnvConfig.spec, hazards |
| H11 | a 2.0 s telegraph (below the minimum) | EnvConfig.spec, env, hazards |
| U1 | the HUD ignores a hazard called off (banner stays up) | hazards |
| U2 | the client never tells the HUD the player left the ring | hazards |
| U3 | the HUD ignores the inside flag (always STEP OUT) | hazards |
| U4 | the hazard banner lasts 2 s, not the telegraph | hazards |
| U5 | the SUBLEVEL banner drops the band name | env |
| U6 | the DEPTH RECORD board names bands never reached | env |
| U7 | the ride hint drops the band's line | env |
| U8 | "the THE VOID" (article rule removed) | env |
| R1 | rest allowed on a floor (mid-run) | EnvConfig.spec, env, hazards |
| R2 | stepping into the car does not end rest | Rest.spec |
| R3 | idle rest off | env |
| R4 | the HUD never shows the rest line | env |
| R5 | the benches are plain Parts, not Seats | env |
| R6 | the 101-character rest hint is back | env |
| A1 | the client skips the arrival grace | hazards |
| A2 | `ArrivalGraceSeconds` 6 → 0 | EnvConfig.spec, hazards |
| CONTROL-1 | the vending machine a shade redder | SURVIVED, as it must |
| CONTROL-2 | the whiteboard says TANK 4 | SURVIVED, as it must |
| CONTROL-3 | the bench cushion a shade lighter | SURVIVED, as it must |

\* **A flake in a pre-existing gate, seen once.** The desktop check does not load Env.client, so it cannot see
G3. Its failure was `…and so does the hint`: the lift's hint read "Your room is going dark" where the EXTRACT
hint was expected, 0.3 s after the bot powered the lift. That hint logic is unchanged HEAD code. Across about
190 runs of the desktop check today it failed that once. In 40 more runs on the final build and 40 on the
untouched HEAD tree (extracted with `git archive`) it failed 0 times each. Unverified guess: the front's flicker
reaches the exit room in the same tick the bot powers it. Not investigated further; see §10.

---

## 8. Needs Studio (only real rendering, a real device and real players can judge)

1. **Every band's look under the real preset.**
   - Are the seven bands distinct, and is each still dark enough?
   - Does a palette recolour read under the room light, and does the grade glide on the ride read as "going
     somewhere"?
   - The void's -0.05 brightness and -0.5 saturation are the darkest: still playable?
   - **The palettes (review round).** Take an A/B screenshot of the same room in the server's colours and in each
     band's palette, lit and under the flashlight. The arithmetic holds every repainted surface at 60-100 % of the
     server's light (linear) and each closed door as much darker than its wall as the server built it. It cannot
     see what Metal, Slate and DiamondPlate textures do to that. Is a closed door found as easily as in a
     server-coloured room?
2. **Glow and bloom.** Neon flasks, jars, fungi, tank liquid, beacons, tears, LED faces and glitch screens: eye
   candy, or blown out? In a dark room they are off by design, so check the lit ones.
3. **Could anything read as an item at a glance?** Self-lit dressing is off in the dark, so this is a lit-room
   question. The teal specimen liquid (hue about 176°) is 43° from a battery cell's green, and the violet
   flasks are far from a fuse's amber. The spec's 30° hue rule is a number, not an eye.
4. **Screens** (SurfaceGuis with `LightInfluence` 0). Rack LEDs, monitors, consoles (CORE 712 C), glitch
   panels, notice boards, whiteboards, the stopped clock: readable, the right way round, not too bright? And
   16 of them at once on a phone: frame time.
5. **Particles at real scale.** Drips into the water, steam, fumes, sparks, spores (light emission 0.6),
   motes: sizes and rates are guesses. Since the review round steam, drips, fumes and motes are lit by the scene
   (`LightInfluence` 1): do they still read in a lit room, and does the room light's tint colour them well?
   Every emitter stops when its room goes dark (asserted headless).
6. **The flooded water film** (26 × 26 studs, 0.12 thick, 35 % transparent) over the floor: water, or a
   plastic sheet? Any z-fighting with the floor it lies on?
7. **The first-person telegraph.**
   - Is the banner (STEP OUT / YOU ARE CLEAR) enough on a phone?
   - Is the pulsing ring visible when a player looks down, and does the burst (splash ball, arc, column)
     read?
   - Does the source fitting on the ceiling look like part of the ceiling?
8. **The shove.** `AssemblyLinearVelocity` on a walking humanoid, with no PlatformStand. Roblox's humanoid
   controller may cancel most of it within a few frames. Is a hit felt at all? It must never carry a player
   through a doorway into a dark room: the spot is at least 6 studs off every wall, but that is geometry, not
   physics.
9. **Client-only collision.** Floor furniture collides for its own player only. Can a player snag on a filing
   cabinet or pump in the dark? (It never stands in front of a doorway or where an item can.)
10. **The first frame of a new room.** Headless, a room is dressed and repainted on the first frame after it
    appears, at 60 Hz (0 frames of the server's colours in `check_facilitynightmare_firstframe`). Roblox may
    deliver a replicated room after RenderStepped and before the frame is drawn, which would show one frame of the
    server's grey-green. Open a few doors in the void and watch for it.
11. **Recolouring server parts on the client.** Does the server's later door-leaf tween or light flicker ever
    reset the client's colour or material? Headless says no: the server writes position, CanCollide,
    Enabled and Brightness, never colour.
12. **The benches.**
    - Seat orientation (the sitter faces into the room).
    - Jump to stand.
    - The far depth-of-field softening: pleasant, or looks broken?
    - Idle rest after 20 s of standing still.
13. **The DEPTH RECORD board**: legible from the spawn, and the amber highlight (THE VOID's row too, since the
    review round).
14. **Text on a phone**: the 40-character banners at 30 px and the 81-character hints at 16 px in their boxes
    (held to the longest the HUD already had, which is itself unverified on a phone).
15. **Frame time on a mid/low phone** at the densest floor (about 200 local parts, 16 screens, 4 emitters) on
    top of the server's up to 394 zone parts.
16. **The whole brief, with people**:
    - Does the world change often enough to never feel monotonous at the depths players actually reach?
    - About half of perk-less medium runs reach the reactor, and 17 % reach the void.
    - Are hazards rare and fair?
    - Does anyone miss a mid-run rest?

---

## 9. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *None of this has been tried in Studio. Do steps 1 and 2
first and check them before relying on the rest.*

1. **Build a place that has the environment.** In `facility-nightmare/`, run
   `rojo build default.project.json -o Facility-shots.rbxlx` and open that file from disk. `*.rbxlx` is
   git-ignored. There is no universe and no published place for this game; never publish this file.
2. **Check that it runs storeless.** Press Play. A place that was never published should make the server's
   `GetDataStore` fail at start. The break room's hint should then read
   `Saving is off on this server — progress will not be kept. Walk into the elevator.`, and every Play
   starts from a fresh profile (runs 0). That is what the shots need: on a first-ever run, **sublevel 1
   stays lit until you pick up your first fuse.**
   - If the hint is different, or the elevator refuses with "Couldn't reach the save server — retrying",
     the DataStore did not fail at start. In **this place only**, add `profileStore = nil` on the line after
     the `pcall` near the top of `ServerScriptService.Main` (look for `local okStore, profileStore`).
3. **Put the band you want on sublevel 1.** Edit `ReplicatedStorage.Config` **in this place only**, never in
   `src/`. Add this just before `return Config`:
   ```lua
   -- SHOTS ONLY (Facility-shots.rbxlx): put one band on sublevel 1. Only the look changes; the server never reads Config.Env.
   local SHOT_BAND = 3 -- 1 offices, 2 labs, 3 server vault, 4 flooded, 5 reactor, 6 bio-lab, 7 the void
   for j, b in Config.Env.Bands do
   	b.fade = 0
   	b.from = if j <= SHOT_BAND then (j - 1) * 0.1 else 100 + j
   end
   ```
   This was checked headless for all seven values. It passes the client's own validation, and the chosen
   band then covers sublevels 1 and 2 with no blend. Stop, change `SHOT_BAND`, Play again for the next band.
   For the break-room shot (shot 1), remove the snippet.
4. **Walk to build rooms.** Only the room you arrive in exists. A door opens as you walk up to it, and the room
   behind is built. **Do not pick up a fuse (amber) until shot 6.** Green battery cells are fine.
5. **Camera.** Floors are first person. For a composed frame, use Studio's Freecam (Shift+P; it hides the HUD),
   or place the camera from the command bar (Client context), then give it back afterwards:
   ```lua
   -- print the room you stand in; the first player's zone is Zone_1 (x = 400)
   local p = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
   for _, r in workspace.Facility.Zone_1.Floor.Rooms:GetChildren() do
   	local f = r.Floor.Position
   	if math.abs(p.X - f.X) <= 14 and math.abs(p.Z - f.Z) <= 14 then print(r.Name, f) end
   end
   -- camera just inside the middle of one wall, looking at the far corner (offsets from the Floor part's centre,
   -- which is half a stud below the floor top)
   local f = workspace.Facility.Zone_1.Floor.Rooms.Room_12.Floor.Position -- the name you printed
   local cam = workspace.CurrentCamera
   cam.CameraType = Enum.CameraType.Scriptable
   cam.CFrame = CFrame.lookAt(f + Vector3.new(-12, 6.5, 0), f + Vector3.new(9, 3, 9))
   -- afterwards: cam.CameraType = Enum.CameraType.Custom
   ```
   **Where things are in every room** (room-local, from the floor's centre, floor top y = 0):
   - walls' inner faces at ±13, ceiling at 14;
   - wall furniture stands in the 2.5-stud band along a wall, about 9.5 either side of the wall's middle,
     so near the corners; the middle of every wall is kept clear;
   - overhead runs (ducts, cable trays, pipes, vines) along one wall at y ≈ 11.5-13.5;
   - hanging pieces (cables, vines with pods, floating debris) at y ≈ 8-12, 3.5-6 studs off a wall;
   - the light fixture is in the middle of the ceiling; in the entry room the car stands in the middle.
6. **Clean frames**: `game.Players.LocalPlayer.PlayerGui.FacilityHud.Enabled = false` (Client), or Freecam.

**The shots** (in this order; shot 6 ends the held floor):

1. **"The break room: DEPTH RECORD"** (no `SHOT_BAND` snippet).
   - Play one real run to sublevel 2 or 3 and EXTRACT. Sublevel 1 is held until your first fuse; after that
     the dark runs, so move.
   - Back in the break room the board reads `DEEPEST: SUBLEVEL n` with the bands you reached by name, your
     current one highlighted, and `???` below.
   - Sit on the left bench (x = 6; jump to stand). Stand up before the shot, or the rest's soft focus blurs
     the board.
   - Camera ≈ (8, 5.5, -4), looking at ≈ (-6, 4, -19).
   - In frame: the board (south wall, x ≈ -19), the benches and rug, the plant by the wall. Stretch it to
     catch the amber SERVICE ELEVATOR sign glowing in the car if you can.
   - The break room is lit, so this is the one bright, warm frame: the "before".
2. **"Server vault"** (`SHOT_BAND = 3`).
   - Open doors until a room shows a **rack pair** in a corner (two tall black racks with blinking LED faces).
   - Camera from the middle of the opposite wall, 6.5 up, looking at that corner (the snippet's framing).
   - In frame: racks with blue/red/white LEDs, a cable tray overhead, a drooping cable, the cold blue grade,
     and the avatar small in the middle with its flashlight on. A breaker box sparking is a bonus.
3. **"Flooded maintenance"** (`SHOT_BAND = 4`).
   - Low camera (y ≈ 2) near one wall, looking across the room so the water film catches the room light.
   - In frame: water across the floor, a rusted pipe run with red valve wheels or a valve bank, the overhead
     pipe **dripping** into the water, the teal murk. Take a burst for the drips.
4. **"Reactor core: STEAM VALVE"** (`SHOT_BAND = 5`, and in the same place's Config
   `Config.Hazards.IntervalMin = 8` and `Config.Hazards.IntervalMax = 10`).
   - Stand about 6.5 studs from the centre of a lit room. Not the room's middle (the light fixture), and not
     the entry room's car pad. Wait: the first hazard comes 6 s after arrival at the earliest, then every
     8-10 s of standing there.
   - When the red ring appears (banner `STEAM VALVE — STEP OUT OF THE RING`), step 4 studs sideways
     (`YOU ARE CLEAR`), switch to Freecam side-on about 20 studs away, and screenshot the **steam column
     bursting over the red ring** with the avatar just outside it.
   - Also in frame: red CORE 712 C consoles, a pulsing red beacon, yellow/black HIGH TEMPERATURE panels,
     coolant risers with yellow bands, the orange grade.
   - A hit only shoves the avatar; nothing is lost. Try again.
   - Variant with the HUD on, in first person: the red banner over the scene.
5. **"Overgrown bio-lab"** (`SHOT_BAND = 6`).
   - Camera low, near a **specimen tank** (glowing teal liquid behind glass), looking up past it to the
     hanging vines and seed pods.
   - In frame: vines up the walls, glowing blue fungi clusters, drifting glowing spores, moss on the floor,
     the green grade.
6. **"The void, and the dark coming"** (`SHOT_BAND = 7`).
   - First the lit void: glitching wall panels, violet tears flickering, a black monolith, stone debris
     floating and bobbing overhead, motes rising from a crack, the violet grade.
   - Then **pick up a fuse**: the first run's front starts at the entry, and the rooms die ring by ring.
   - Stand in a lit room next to one that is about to die, and frame its doorway from the lit side. The dying
     room flickers for 2 s, its tears and screens flicker with it (glow follows power), then it goes black.
   - Take a burst through the flicker, with the avatar's flashlight pointing into the doorway. A fuse's amber
     glow in frame tells a viewer what the game is about.

A HUD variant for any band: capture the ride down. `SUBLEVEL 1 — SERVER VAULT` is on the banner for the ride's
first 3 s, and the hint gives the band's line.

---

## 10. Not done / open

- **The independent adversarial review is done** and its five findings are closed (§11). Nothing after it has
  been reviewed by anyone else.
- **`luau-analyze` was not run** (the binary is gone from the shared scratchpad; still gone in the review round).
  The strict-mode type noise of the new modules is unknown.
- **Gustav's call: hazards and near-hits** (review finding 3, §3). In real play a hazard comes once per 3.3-4
  floor-minutes in the bands that have them (one per 4.3 overall at the medium proxy), because the dark freezes
  the clock by design. And it is a near-hit only for a player who stops: 6 of 534 bursts (1.1 %) landed within 8
  studs of a bot that never stops walking. Options, none taken:
  1. **Keep it.** Hazards stay a rare telegraphed scare that never adds to the dark.
  2. **More often:** `Config.Hazards.IntervalMin` / `IntervalMax` 90 / 140 (and update `EnvConfig.spec`). More
     banners, still few near-hits for a walker.
  3. **Aim ahead of a moving player:** draw the ring where they will be in about 1.5 s. A walker then meets it and
     steps round it. This changes "the ring is where you stood", so the escape-time rule (every ring escapable at
     10.4 studs/s after a 1 s reaction) must be re-derived and re-tested first.
  4. **Start only when the player has stood still for a moment:** every hazard becomes a near-miss, but rarer still.
- **The void is reached by 17 % of perk-less medium runs.** It is the long-term goal by design; perks raise it.
  Real player depths (CLAUDE.md "Needs Studio" item 1) will show whether the band starts are right.
- **The proposed store text in README.md** does not mention the bands. It is left to the publishing session.
- **A rare flake in `check_facilitynightmare_desktop`**, which predates this work (§7). It was seen once in
  about 190 runs: the lift's hint read "Your room is going dark" 0.3 s after powering. 0 of 40 on the final
  build and 0 of 40 on HEAD; 0 of 20 more in the review round. Worth a look in the game's next review: if a powered lift can report a
  flicker for a moment, the player sees a wrong hint at the choice.
- **Everything in §8.**

---

## 11. The adversarial review (2026-09-24) and how each finding was closed

An independent reviewer read the resume session's final tree (bundle md5 `56c294c4…`), re-ran every gate on copies
and probed it. Five findings. Each was **reproduced first** on an untouched copy of that tree, each fix went
**test-first** (every new assertion below was watched failing on the untouched copy), and the sweep in §7 mutates
every new rule. Final bundle md5 `735c51b3…` (the sweep and the repeated runs used `1bbf3b9a…`, which differs from it
by one comment line).

### Finding 1 (medium): the deep bands' palettes dimmed the rooms and hid the doors. CLOSED

**Reproduced** with the reviewer's probe on the untouched copy. Linear light; "door:wall" is the WCAG-style
contrast ratio the reviewer used, server-built room 2.17:

| band | door:wall | wall under the flashlight | wall under its room light | room light's output |
|---|---|---|---|---|
| server vault | 1.06 | 19 % | 15 % | 75 % |
| flooded | 1.44 | 46 % | 41 % | 87 % |
| reactor | 1.04 | 30 % | 23 % | 74 % |
| bio-lab | 1.39 | 48 % | 44 % | 90 % |
| void | 1.06 | 7 % | 5 % | 69 % |

In the server vault, the reactor and the void a closed door was *brighter* than its wall. **Cause:** `paletteOk` held
surfaces at 25-100 % of the server's gamma luma, the light at 80-100 % of its gamma luma, and had no door rule. The
difficulty numbers could not see it: the bot finds doors in the workspace, not by colour.

**Fix.** `Dressing.paletteOk` works in linear light (`Dressing.linear`, `Dressing.returned`), under the flashlight's
white light and under the room's own light:
- every repainted surface returns **60-100 %** of the server's light (`Config.Env.ReflectanceMin`): about 80 % as
  bright on screen, the allowance the grade's tint already had;
- the room light's colour carries **90-100 %** of the server's light (`LightOutputMin`);
- a closed door stands out from its wall **90-110 %** as much as in the server's room (`DoorContrastMin` / `Max`):
  no harder to find, and no easier.

Five palettes were retuned, keeping each band's hue and raising its light to about 70 % (offices and labs already
passed and are unchanged):

| band | wall | floor | ceiling | door | light |
|---|---|---|---|---|---|
| server vault | 66,72,84 → **123,133,153** | 70,74,82 → **73,77,85** | 34,36,42 → **37,39,46** | 70,76,86 → **78,84,95** | 190,215,255 → **223,235,255** |
| flooded | 104,112,94 → **126,136,114** | 54,62,58 → **69,79,74** | 38,42,40 | 92,84,72 → **91,83,71** | 200,235,220 → **215,240,229** |
| reactor | 96,88,84 → **142,130,125** | 66,62,60 → **80,76,73** | 40,34,32 → **44,38,36** | 110,90,40 → **100,82,36** | 255,200,170 → **255,229,217** |
| bio-lab | 96,116,92 → **115,139,111** | 58,70,52 → **67,80,60** | 36,44,36 | 80,92,78 → **76,87,74** | 205,240,210 → **212,242,216** |
| void | 44,38,56 → **141,125,173** | 30,28,38 → **78,74,95** | 20,18,26 → **41,37,50** | 48,42,60 → **89,79,109** | 215,195,255 → **238,231,255** |

**After** (the same probe on the final tree): door:wall **2.03-2.05** in every deep band (offices 2.05, labs 2.12);
walls **70 %** under the flashlight and **66-67 %** under the room light; room light **93 %**.

**What it does to the look.** The deep bands are tinted now, not dimmed: steel-blue vault, warm grey reactor metal,
dusky violet void slate. Their darkness comes from the grade (never brighter than the preset), the glow and the
dressing. What Metal, Slate and DiamondPlate textures do on top is a Studio question (§8 item 1).

**Tests** (all failing on the untouched copy): `EnvConfig.spec` re-derives every rule for every band in its own
linear arithmetic and pins the four numbers (55 failures on the untouched tree), plus six cases that each break
exactly one rule and the three palettes the review measured; `Dressing.spec` hand-checks the sRGB curve and the
per-channel product; `check_facilitynightmare_env` D measures, on the real instances of every band, that each door
leaf wears its band's door colour, stands out from its wall 90-110 % as much as the server built it, and that wall,
floor and door return 60-100 % of the server's light (5 bands failed on the untouched copy). Mutations R2-P1..P11.

### Finding 2 (low): a new room showed the server's colours, then snapped. CLOSED

**Reproduced.** The reviewer's 60 Hz probe on the untouched copy, in the void: the 11 rooms that appeared behind
opened doors kept the server's wall colour for 2-14 rendered frames each (the entry room for its whole ride). The new gate on the untouched copy (3 runs): 30-60
violating frames at opened doors, and the entry room undressed through a whole ride from a far car (240 frames,
unseen inside the closed car) and the first frames after arrival.

**Cause.** Env.client dressed and recoloured rooms only in its 0.25 s pass.

**Fix.** Every frame, Env.client looks for a room of the player's floor that should be dressed and is not (within
`DressRadius`, or any room during the ride) and runs the pass at once. The pass is also forced when the run or the
sublevel changes, and during the ride it dresses the entry room wherever it is, so the room is ready before
arrival whatever order Roblox delivers the teleport and the State in. Cost: at most 25 rooms per frame, one table
lookup for a room already dressed.

**After.** The reviewer's probe: 0 frames for all 10 rooms. `check_facilitynightmare_firstframe`, 20 of 20 runs:
72 840 frames at 60 Hz, 306 rooms appearing, 345 108 room-frames and 791 808 door-leaf-frames audited, **0 frames**
of a room in view in the server's colours or undressed. Mutations R2-F1..F4. Real replication order is on the
Studio list (§8 item 10).

### Finding 3 (low): hazards are rarer than the brief, and a walker almost never gets the near-hit. FRAMED for Gustav

**Reproduced** with `tests/hazards.measure.luau` on the final tree: one hazard per 4.3 floor-minutes at the medium
proxy (3.3-4.0 in the bands that have them), one per 2.8 exposed minutes, and **6 of 534 bursts (1.1 %) within 8
studs** of a bot that never stops walking. The reviewer's run: one per 4.4, 3 of 266 bursts.

**Not a defect to fix without the owner.** The rarity is deliberate (the dark freezes the clock; a hazard never adds
to the dark), and "a near-hit per 2-3 minutes" holds only for a player who stops when the banner goes up. §3 now
says so with the numbers, `tests/hazards.measure.luau` prints the near-hit share, and §10 lists four options for
Gustav. No number changed.

### Finding 4 (low): the DEPTH RECORD board never highlighted THE VOID. CLOSED

**Reproduced** with the reviewer's probe: at DEEPEST 13 and 20 no row was highlighted. **Cause:** row i was
highlighted only when `i < #rows`. **Fix:** the last row has no next band to stop it. **Test:** env check B builds a
second board in memory and checks nine depths (0, 1, 2, 3, 4, 11, 12, 13, 20): exactly the right row, and none at
0. It failed at 13 and 20 on the untouched copy. Mutation R2-B1.

### Finding 5 (low, plausible): particles that are not self-lit drawn full-bright in dark rooms. CLOSED headless

**Reproduced as far as headless can go.** No ParticleEmitter wrote `LightInfluence` (Roblox's documented default is
0, unaffected by light; it reads nil here), and the flooded kit's drips (light emission 0) kept running in a dark
room. How Roblox draws them cannot be seen headless.

**Fix, both halves.** Every emitter writes `LightInfluence`: 1 (lit by the scene) unless it is self-lit, then 0.
And every particle follows its room's power, self-lit or not: a dark room's emitters are off and take none of the
emitter budget, which goes to lit rooms. The power decision for emitters lives in one place, the budget in
Env.client (CLAUDE.md trap 37).

**Tests** (failing on the untouched copy): the env check's census asserts every emitter's `LightInfluence` at every
frame (14 wrong on the untouched copy), the hazards check does the same for hazard and room emitters (27 772 wrong
emitter-frames), env E stops the flooded kit's drips in a dark room and on the flicker's low step, and env F's
power audit counts any running emitter in a dark room (20 on the untouched copy). Mutations R2-E1..E3. How lit
steam and drips look is §8 item 5.

### What the reviewer found clean, re-checked here

Gates and counts, the server diff (the benches only), dressing never seeing an item, hazards (one at a time, never
in the dark or on a pad or in the arrival grace, nothing lost by a hit), rest (break room only, no server hook), the
replication and authority rules, and the part budgets. Nothing in this round touched the server, the HUD, Hazards,
Rest or the survival numbers.
