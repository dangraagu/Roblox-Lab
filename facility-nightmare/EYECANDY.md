# FACILITY: Endless Nightmare — deeper is stranger

Owner's brief (Gustav, 2026-09-17): every game visually richer and never monotonous, with the world changing
as the player progresses in a way that fits the game; rare hazards that are easy to see coming and avoid
(about one near-hit per 2-3 minutes); a way to rest that can never become an exploit; a thumbnail shot list.
For FACILITY specifically: the dark and the flashlight are the gameplay and there is no chasing AI, so the
visuals must never make a room brighter or easier to see than designed, must never hide a fuse, and rest
belongs in the break room, not mid-run.

**State: built, unit-tested, headless-tested, mutation-tested, and reviewed twice by independent adversarial reviewers;
all ten findings are closed (§11, §12). The owner's two open decisions are taken (§10). NOT seen in Studio, NOT played by
a person.** Nothing was committed, pushed or published.

**Pass 2 resumed (2026-10-01), §15.** Every item of the standard checked again. Built test-first: a critter in every band
(a cockroach, a lab mouse, a moth, a rat, a bat, a beetle, a pale drifter), held to every dressing rule over its whole path
and moving only in near lit rooms; dust motes, the offices' weather; the walk's rejoin; and the desktop check's rare flake,
which was a real defect (the wrong hint at the powered lift).

**Pass 1 again (2026-10-01), §14.** Review 2's five findings were re-checked on the current tree with the reviewer's own
probes: none reproduces, except the slow half of the brag finding, which was an open owner decision and is now **DECIDED
2026-09-30 (owner: take recommended): left as designed**, one brag timed for normal play (§10, with the per-band minutes).
Pass 2's cut-off mutation sweep is completed (§13: 27 of 28 KILLED, B11 equivalent, 3 controls SURVIVED) and review 2's
re-run on this tree (§7: 27 of 27, 3 controls SURVIVED). Documentation only; no source changed.

**Pass 2 of the complete-game standard (2026-10-01), §13.** Every item of docs/complete-game-standard.md checked; built
test-first where missing: the TOP DIVERS board (public + friends, on the break room's north wall), a REST button to press
pause in the break room, the local-parts budget capped in code, a `[hub]` mode in the HUD check, MARKETING.md's eight
clips, the store text, and §8 item 18 / §9's 1920x1080.

**Review round 2 and the owner's decisions (2026-09-30 / 10-01).** A second reviewer found five things; §12 has each
one reproduced, fixed test-first and mutation-tested. The owner decided "take the recommended option for all" (§10).
1. **Text lay on the EXTRACT / DESCEND modal on a phone, and on the perk panel everywhere** (medium). The reviewer found
   the hazard banner on the choice modal; the same gate gap hid the toast and the hint on both modals (31 text-row
   overlaps across 20 viewport-modes before the fix, 0 after). No hazard starts at the powered lift now, a live one is
   called off there, and while a modal is up the HUD's text rows sit below it.
2. **The brag came too late** (medium). THE VOID was both the brag and the long-term goal: a medium player first powered
   it after a median of 52.9 minutes in this round's reproduction (the reviewer measured 71.0). The brag is now the OVERGROWN BIO-LAB, with a fanfare the first time the saved record
   reaches it: a medium player gets there after a median of 29.6 minutes (§2). The void stays the long-term goal.
3. **Doors between two bands broke the door-contrast promise** (low). A leaf now wears the band of the room on the
   player's side of it.
4. **Five environment promises no gate held** (low). Each is asserted now, and each of the reviewer's five mutants is
   killed.
5. **A stale 17 %** (low). The void is reached on 10 of 120 perk-less medium runs (8 %), measured again below.
- **Owner's decisions:** hazards come every 90-140 s of exposed time (option 2), about one per 2.6-3.1 minutes of play in
  the bands that have them (§3); and the slow player's brag is left as designed (§10, taken in §14's pass).

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
| `src/shared/Hazards.luau` | **adapted** from plus1-jump. Kept: a clock that freezes and never resets, 120-180 s between hazards (90-140 since the owner's decision, §10), one at a time, and "the ring is what hits". FACILITY-specific: hazards come down from the ceiling (nothing flies), start only on a legal spot in a lit room, and are called off by a flicker. `arrivalOk` (this session): none in the first 6 s on a sublevel. |
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

**Review 2 (§12) and the owner's decision (§10) changed:**
- `Hazards.luau`: `validate` holds every kind to the config's promised shove (`KnockMin` / `KnockMax` / `LiftMax`).
  `step` takes `ctx.callOff`: at the powered lift a live hazard is called off and none starts.
- `Dressing.luau`: `leafSide`, which of a door leaf's rooms is on the viewer's side.
- `Env.client.luau`: the lift's call-off, and every door leaf painted in the band on the player's side, every frame.
- `Hud.client.luau`: while a modal is up the text rows sit below it, and a modal keeps room for them. The brag's and
  the goal's fanfare.
- `Main.server.luau`: the `choice` notice's `record` flag.
- `Config.luau`: hazards every 90-140 s (the owner's decision), `KnockMin` 16 / `KnockMax` 24 / `LiftMax` 3, and the
  bio-lab's `brag = true`.
- `tests/`: `pacing.measure.luau` (the brag's and the goal's minutes), new cases in `Hazards`, `EnvConfig` and
  `Dressing`.
- The checks: the HUD's text-on-a-modal audit, hazards D and E at the lift, env B (board, benches, fanfare), env D3
  (doors between two bands), env F (the fanfare in play), the firstframe door rule, and the main check's `record`.

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
40 runs. "Arrival" is minutes into the run, among the runs that got there. The numbers are review 2's run on the
final tree (2026-10-01). Earlier runs gave medium 98 / 91 / 72 / 55 / 30 / 12 % (review 1) and 98 / 85 / 63 / 48 / 34
/ 17 % (the resume session) for labs to void; hazards cost nothing and the palettes cannot move reach (the bot reads
the workspace, not colours), so the spread between the runs is sampling.

| # | band (banner) | sublevels | look (grade, room palette) | dressing (per room: 3-5 wall pieces, overhead runs, hanging pieces, desk items) | weather (particles); critter (pass 2) | hazard | reached (medium / slow / perfect) | arrival p50 (medium) |
|---|---|---|---|---|---|---|---|---|
| 1 | ADMIN OFFICES | 1-2 | pale fluorescent green-grey; beige-grey walls, blue-grey carpet | filing cabinets, cubicle dividers with an office chair, water cooler, notice board (SAFETY FIRST), potted plant, wall clock stopped at 3:17, monitors and keyboards on desks, scattered papers | dust motes drifting high in the light (pass 2); a cockroach along the foot of a wall | none: a first run meets the dark before anything else | 100 % / 100 % / 100 % | 0 min |
| 2 | LABORATORIES | 3-4 (26 % of sublevel 2's rooms) | cold cyan; pale teal walls | lab benches with glowing violet and cyan flasks, a fume hood with slow fumes, shelves of glowing jars, whiteboard (DO NOT OPEN TANK 3), biohazard bins, microscopes with a glowing slide, ceiling ducts | fumes; an escaped white lab mouse | CHEMICAL LEAK | 100 % / 93 % / 100 % | 1.9 min |
| 3 | SERVER VAULT | 5-6 | cold blue, higher contrast; steel-blue metal walls, diamond-plate floor | rack pairs with blinking blue/red/white LED faces, a rack with a cable bundle, a cooling unit, a breaker box with a loose sparking cable, laptops, cable trays, drooping cables | sparks; a moth fluttering under the trays | ARCING CABLE | 93 % / 68 % / 100 % | 4.3 min |
| 4 | FLOODED MAINTENANCE | 7-8 | teal-green murk; stained green-grey concrete, brown doors | water over the whole floor, rusted pipe runs with red valve wheels, valve banks, pumps, rust streaks, an overhead pipe dripping into the water | drips; a rat along the water's edge | BURST PIPE | 70 % / 28 % / 100 % | 7.3 min |
| 5 | REACTOR CORE | 9-10 | warm orange, high contrast; warm grey metal, hazard-brown doors | coolant risers with hazard-yellow bands, yellow/black HIGH TEMPERATURE panels, pulsing red beacons, consoles reading CORE 712 C / PRESSURE HIGH, steam vents, coolant ducts | steam; a bat flitting under the ducts | STEAM VALVE | 48 % / 10 % / 98 % | 10.0 min |
| 6 | OVERGROWN BIO-LAB, **the brag** | 11-12 | green; moss-green concrete, earth floor | vines up the walls, specimen tanks of glowing teal liquid, glowing blue fungi, cracked panels with roots, ceiling vines, hanging vines with seed pods, moss | drifting glowing spores; a beetle crawling high on the wall | SPORE POD | 28 % / 1 % / 90 % | 12.9 min |
| 7 | THE VOID, **the long-term goal** | 13+ | desaturated violet, darkest grade; dusky violet slate | glitching wall panels, violet tears that flicker, black monoliths, ink pools, cracks with rising motes, stone debris floating and bobbing overhead | motes; a pale half-there drifter overhead | RIFT | 8 % / 0 % / 80 % | 16.3 min |

Perks push these up: every row above is perk-less. At the medium proxy nearly every run sees the labs and about half
reach the reactor; at the slow proxy most runs end in the labs or the server vault. The last band starts by sublevel 13
(`EnvConfig.spec`), and every band lasts at least two sublevels.

**The brag and the long-term goal** (review 2, finding 2; `docs/complete-game-standard.md` asks for a brag within about
30-45 minutes of normal play and a goal beyond it). THE VOID used to be both, and a medium player first powered it after a
median of 52.9 minutes in this round's reproduction (30 players; the reviewer measured 71.0). Now:
- **The brag is the OVERGROWN BIO-LAB** (`brag = true` in `Config.Env.Bands`), the deepest band of the facility itself.
- **The long-term goal is THE VOID**, the last band.
- Each is reached when the SAVED record first reaches its first sublevel: its lift powers, the server's `choice` notice
  says `record = true` (only the server knows the best before), and the HUD plays the fanfare, a
  `NEW RECORD — OVERGROWN BIO-LAB` / `NEW RECORD — THE VOID` banner with an FOV punch. It shows below the
  EXTRACT / DESCEND modal. It fires once: a powering that does not raise the record, or a sublevel that starts no
  band, gets none. The DEPTH RECORD board names the band from then on, and `leaderstats.Deepest` shows the number to
  everyone.
- **Measured** by `tests/pacing.measure.luau` (review 2's pacing model): fresh players on the real server buy every
  perk they can afford between runs and always DESCEND. The clock covers everything since join.

| proxy | players | the brag (bio-lab): p10 / p50 / p90 min | within 30 / 45 min | the goal (void): p10 / p50 / p90 min | within 45 / 150 min |
|---|---|---|---|---|---|
| medium (normal play, 12.8) | 30 | 14.7 / **29.6** / 41.8 (the 3rd run, median) | 16 / 27 of 30 | 26.3 / 57.7 / 96.9 | 14 / 30 of 30 |
| slow (10.4) | 20 | 146.5 / later than 150 / later | 0 / 0 of 20 | later than 150 | 0 / 0 of 20 |
| perfect (16) | 10 | 10.5 / 13.5 / 23.2 | 10 / 10 of 10 | 13.1 / 15.5 / 28.8 | 10 / 10 of 10 |

A second, separate sample of the same model (the review-2 reproduction probe, 30 medium players) gave the bio-lab a
median of 34.6 minutes (17 of 30 within 45 min, 12 within 30) and the void 52.9. A third, pass 2's run on its final
gameplay code (bundle md5 `33ee9007…`, 8 min 44 s): medium brag p10 13.9 / **p50 26.9** / p90 51.9 min, 16 of 30 within 30
and 23 of 30 within 45; void p10 29.3 / p50 70.2 / p90 113.7 (10 of 30 within 45, 30 of 30 within 150); slow: brag p10
126.3, the rest later than 150; perfect: brag 11.1 / 12.2 / 21.9, void 13.1 / 14.9 / 26.8. Two more on the current tree
(2026-10-01, pass 1 again, §14; nothing retuned since pass 2): `tests/pacing.measure.luau` itself gave medium brag p10
15.5 / **p50 31.8** / p90 62.7 (14 of 30 within 30, 21 of 30 within 45), void p50 49.2; slow brag p10 144.5, the rest later
than 150; perfect brag 12.2 / 13.2 / 24.5. A per-band variant (30 medium players) gave the brag **p50 37.0** (24 of 30 within
45) and the void 46.6. Over the five samples the brag's medium median is 26.9-37.0 minutes, and 17-27 of 30 players get
there within 45: the brag sits in the standard's 30-45 minutes by its median, with a long tail from runs the dark ends
early. **A slow player mostly does not reach the brag**: within 45 minutes 0, 0, 0 and 3 of 20 in four slow samples, and
the median is later than 150 minutes in all four; they
first power the flooded maintenance (sublevel 7) after a median of 27.6-32.7 minutes and the reactor (9) after 61.8-90.7.
That is **left as designed: DECIDED 2026-09-30 (owner: take recommended)**, §10.

**The break room** has its own warm grade, never brighter than the facility's.
- Along the walls: a lit vending machine, a coffee corner with a steaming cup, a water cooler, three potted
  plants, a rug under two benches, and posters (`IF THE LIGHTS FLICKER — RUN`, `DAYS WITHOUT AN INCIDENT: 0`).
- The **DEPTH RECORD** board faces a player who has just spawned (asserted since review 2: its SurfaceGui's face points
  at HubSpawn). It shows `DEEPEST: SUBLEVEL n` and every band you have reached by name. The ones below stay `???`
  (no spoilers), and your current band is highlighted.
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

Every kind is held to the promise below (a shove of 16-24 studs/s, at most 3 up): `Config.Hazards.KnockMin` /
`KnockMax` / `LiftMax`, enforced by `Hazards.validate` since review 2 (it used to accept anything up to the module's own
30 / 4), and pinned in `EnvConfig.spec`.

**Rules** (`Hazards.luau`, validated at load; an invalid config switches hazards OFF with a warning and costs
nothing else):

- **Rarity.** One every **90-140 s** of *exposed* time (DECIDED 2026-09-30 (owner: take recommended), §10; it was
  120-180). Exposed means on a sublevel, in a lit room, in a band that has hazards. The clock **freezes** everywhere else (dark rooms, the quiet offices, the ride, the break room)
  and never resets, so walking in and out of a dark room cannot thin hazards out. Never two at once, never a
  backlog: a hazard that falls due waits for a legal spot, and exactly one comes.
- **Where.** It comes down from the ceiling onto the spot you stand on, which must be a legal spot:
  - at least 6 studs off every wall (the room's interior, never in a doorway; whether a real humanoid's
    shove can still carry anyone through one is on the Studio list);
  - off the car's or lift's 10 × 10 pad;
  - not under the light fixture;
  - **not at the powered lift at all** (review 2, finding 1). The server says `atLift` for the whole powered exit room,
    and the EXTRACT / DESCEND modal shows there. No hazard starts there, and a live one is called off the moment the
    player reaches it (ring, source and banner). The clock runs on there, as on the car's pad, so a hazard that
    falls due waits, and after DESCEND it waits out the arrival grace.
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
| the scheduler on its own, 20 h exposed (the spec's own config, 120-180 s) | `Hazards.spec` | 480 hazards = **one per 150 s exposed**, every gap 120.1-180.0 s |
| exposure toggled every 6 s, or 40 s of every 150 s, for 6 h | `Hazards.spec` | 144 / 144 / 144, identical to continuous: freezing never thins hazards |
| a stand-and-walk model in lit rooms, 10 h | `Hazards.spec` | a player who **reacts**: 0.393 hazards/min = **one near-hit per 2.5 exposed min, 0 hits**. One who **ignores** the warnings: hit once per 12.5 exposed min (hit share 0.20) |
| walk out at 10.4 or 16 studs/s after 1 s, in 36 directions, both of the spec's own kinds | `Hazards.spec` | 0 of 144 hit; a player who stays put is hit |
| through the real client on a held, lit floor, 18 hazards (at 120-180 s, before the decision) | `check_facilitynightmare_hazards` C | one per 146-157 s of lit time, gaps 120.5-178.9 s. Stand still: 9 of 9 hit. Step out a second after the warning: 9 of 9 dodged, and the banner said YOU ARE CLEAR before the burst every time. The ring was drawn where the player stood, as wide as the zone |
| 10 min in a dark room, then lit again | same, D | no hazard in the dark; the next came 124-177 s of *lit* time after the last (frozen, not reset; at 120-180 s; review 2's final run at 90-140 s: 139.3 s) |
| 200 s on the entry car's pad, then 200 s in the powered lift at the choice, each with a hazard long due | same, E | none on either pad. A step off the car's pad and the waiting hazard came at once. After DESCEND it came 5.9 s after arrival, not 0.6, and THE POWER IS FAILING kept its 3 s |
| **real runs, after the owner's decision (90-140 s)**, perk-less, the bot ignoring every warning and never stopping, medium proxy (12.8), 120 runs, 1 273 floor-minutes (review 2, final tree) | `tests/hazards.measure.luau` | **one hazard per 3.3 minutes on a floor**, one per 2.1 exposed minutes; **one per 2.6-3.1 floor-minutes in the bands that have hazards** (labs 2.6, servers 2.9, flooded 3.1, reactor 2.8, bio-lab 2.9; the void 4.0 on only 24 floor-minutes); one per 13.9 in the offices (only sublevel 2's foreshadowed lab rooms). 37 of 386 called off by a flicker. Near-hit share: 5 of 349 bursts (1.4 %) landed within 8 studs of the bot. 1 hit in 1 273 minutes. Hazards per run: 0: 3, 1: 10, 2: 31, 3: 20, 4: 34, 5: 15, 6: 6, 7: 1 |
| same, slow proxy (10.4), 80 runs, 632 floor-min | same | one per 4.1 floor-min, 2.1 exposed min; 2.9-3.6 in the bands with hazards; near-hits 3 of 142 bursts (2.1 %); 3 hits |
| same, perfect (16), 40 runs, 567 floor-min | same | one per 2.9 floor-min, 2.2 exposed min; 2.5-2.8 in the bands with hazards; near-hits 2 of 183 bursts (1.1 %); 3 hits |
| review 1's run of the same file, at 120-180 s (before the decision) | same | medium one per 4.3 floor-min (3.3-4.0 in the bands with hazards), one per 2.8 exposed min, 2 near-hits in 281 bursts; slow 5.4; perfect 3.7 |
| through the real client, 18 hazards on a held lit floor (review 2) | `check_facilitynightmare_hazards` C | at 90-140 s: one per 116.3 s of lit time, gaps 91.0-138.1 s; 9 of 9 standing still hit, 9 of 9 stepping out dodged |
| 200 s at the powered lift 6.5 studs from its centre (off the pad, a legal spot anywhere else), with a hazard long due (review 2) | same, E | none, on every run; and a State saying `atLift` during a live hazard calls it off at once (D). The old code, reproduced this round with the reviewer's probe: a warning 119.7 and 108.7 s in, on 2 of 2 runs |

**What that means against the brief.** With the owner's decision (90-140 s) a hazard comes about once every 2.6-3.1
minutes of play in a band that has hazards (it was 3.3-4 at 120-180), and once per 2.1-2.2 minutes of *lit* time.
Dark rooms still freeze the clock, deliberately: the dark is FACILITY's threat, and a hazard must never add to it.

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

**DECIDED 2026-09-30 (owner: take recommended)**: option 2 of §10, 90-140 s. Why that one is in §10.

`IntervalMin` / `IntervalMax` in `Config.Hazards` is the knob. `EnvConfig.spec` pins 90 / 140 and
`check_facilitynightmare_hazards` writes out the same bounds, so a retune is deliberate.

---

## 4. Rest: what "pause" means in FACILITY

A Roblox server cannot stop the world for one player. In FACILITY the world *is* the clock: a run is the
blackout front spreading ring by ring through the floor. Every survival number in DESIGN.md was measured
against it. So **rest is between runs, in the break room**, where there is no front, no hazard, no clock and
nothing to lose:

- **Sit on a bench.** Two real `Seat`s on the break room's south wall. Walk into one to sit, and jump to stand,
  the Roblox way. Everyone in the break room sees you sitting. Resting starts at once.
- **Or stand still for 20 s** in the break room (AFK-safe).
- **Or press REST** (pass 2, 2026-10-01: "man skal kunne trykke på pause"). A HUD button beside PERKS, only in the
  break room. It rests at once (`Rest.press`, source `button`); moving or pressing it again (it reads GET UP) ends it.
  Pressed anywhere else (a tap that lands as the ride starts) it is refused with a toast that says why. Like every
  rest it is client presentation only: it fires no remote and pauses nothing, because nothing runs in the break room.
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
   - No hazard ever starts at the powered lift, pad or not, and a live one is called off there (hazards check D and E,
     since review 2: 200 s on the pad and 200 s 6.5 studs out, with one long due). A hazard that falls due there waits
     out the 6 s arrival grace on the next sublevel.
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
| local parts | **229** (pass 2 resumed, with critters; 207 before) | the densest floor, bio-lab kit, 16 rooms built | 264 since pass 2 resumed (240 before), **capped in code** since pass 2 (Env.client parents rooms' dressing nearest first while it fits in the budget less the 8 kept for a hazard); the arithmetic worst case (16 rooms within 60 studs × (14 parts + 2 critter parts) + 8 hazard parts = 264) shows it never binds on a real floor |
| critters moving | at most 4 (the cap) | near lit rooms | `Budget.MaxCritters` = 4, nearest first; every other critter keeps still (pass 2 resumed) |
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
  step 4 times a second. A critter (pass 2 resumed) moves only in a near, lit room, at most 4 at once: two parts moved
  per critter per frame.
- **Hazards.** One pooled model per hazard kind (3 parts), parented only while live.
- **Lighting.** Written at most 10 times a second, only on change. Dressing passes run 4 times a second, and at
  once on a frame where a room that should be dressed is not (review round): a check of at most 25 rooms per
  frame, one table lookup for a room already dressed.
- **Checked** (env check D1 and hazards check C, caps lowered in memory; since the review round also env check
  E, a dark room's emitters stopping; since pass 2 the local-parts cap):
  - a room out of range is put away and comes back in range;
  - with the emitter cap at 1, exactly one room's emitter runs;
  - with the screen cap at 1, at most one room's screens run;
  - with the emitter cap at 1, a live hazard's warning takes the room's emitter, never both;
  - with the parts cap lowered to the hazard reserve + the player's own room, only that room keeps its dressing, and
    with the real cap every room in range is dressed again (pass 2).

These are part and emitter counts, not frame times. Frame time on a real phone, and what 16 SurfaceGuis cost
there, are on the Studio list.

---

## 7. Gates

Git Bash from `D:\Claude\Roblox`; commands in CLAUDE.md. Bundle rebuilt before every headless run.

| gate | before the environment (HEAD) | as the cut-off attempt left it | final (resume session) | after the review round (§11) | after review 2 (§12, 2026-10-01) |
|---|---|---|---|---|---|
| `tests/Config.spec` | 106 / 0 | 106 / 0 | 106 / 0 | 106 / 0 | 106 / 0 |
| `tests/Economy.spec` | 93 / 0 | 93 / 0 | 93 / 0 | 93 / 0 | 93 / 0 |
| `tests/Facility.spec` | 84 / 0 | 84 / 0 | 84 / 0 | 84 / 0 | 84 / 0 |
| `tests/Survival.spec` | 74 / 0 | 74 / 0 | 74 / 0 | 74 / 0 | 74 / 0 |
| `tests/Trust.spec` | 53 / 0 | 53 / 0 | 53 / 0 | 53 / 0 | 53 / 0 |
| `tests/Responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/Rng.spec` | 37 / 0 | 37 / 0 | 37 / 0 | 37 / 0 | 37 / 0 |
| `tests/MazeGen.spec` | 3 / 0 | 3 / 0 | 3 / 0 | 3 / 0 | 3 / 0 |
| `tests/Fx.spec` | 26 / 0 | 26 / 0 | 26 / 0 | 26 / 0 | 26 / 0 |
| `tests/EnvBands.spec` (verbatim template) | — | 124 / 0 | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/EnvBus.spec` | — | 11 / 0 | 11 / 0 | 11 / 0 | 11 / 0 |
| `tests/EnvConfig.spec` | — | 382 / 0 | **417 / 0** | **475 / 0** | **511 / 0** |
| `tests/Hazards.spec` | — | 82 / 0 | **92 / 0** | 92 / 0 | **108 / 0** |
| `tests/Rest.spec` | — | 43 / 0 | 43 / 0 | 43 / 0 | 43 / 0 |
| `tests/Dressing.spec` | — | 75 / 0 | **79 / 0** | **87 / 0** | **99 / 0** |
| **spec total** | **546 / 0** | **1 263 / 0** | **1 312 / 0** | **1 378 / 0** | **1 442 / 0** |
| `check_facilitynightmare` | 203 / 0 | 203 / 0 | 203 / 0 | 203 / 0 | **205 / 0** |
| `check_facilitynightmare_input` | 116 / 0 | 116 / 0 | 116 / 0 | 116 / 0 | 116 / 0 |
| `check_facilitynightmare_desktop` | 47 / 0 | 47 / 0 | 47 / 0 | 47 / 0 | 47 / 0 |
| `check_facilitynightmare_hud` (10 viewports × 3 modes) | PASS | PASS | PASS | PASS | **PASS**, + no text row on a modal (20 viewport-modes) |
| `check_facilitynightmare_env` | — | 191 / 0 (1 run in 8 crashed: the introduction's item 5) | **221 / 0** | **251 / 0** | **264 / 0** |
| `check_facilitynightmare_hazards` | — | 28 / 0 | **42 / 0** | **44 / 0** | **53 / 0** |
| `check_facilitynightmare_firstframe` (review round) | — | — | — | **18 / 0** | 18 / 0 (the door rule is the viewer's side now) |
| `tests/walk.luau` (count varies with depth) | 70 / 0 | 55 / 0 | 55-63 / 0 (3 runs) | 55-71 / 0 (4 runs) | 55-71 / 0 (10 runs) |
| **headless total**, the counted checks (the walk's count varies with depth) | 366 / 0 + PASS | 585 / 0 + PASS | **629 / 0 + PASS** | **679 / 0 + PASS** | **703 / 0 + PASS** |
| compile every file (see below) | 12 sources | — | **44 of 44 files clean**: 19 sources, 19 test files, 6 checks | **45 of 45**: 19 sources, 19 test files, 7 checks | **46 of 46**: 19 sources, 20 test files (+ `pacing.measure`), 7 checks |
| `rojo build` (Rojo 7.7.0) | builds | builds | builds; the place holds `Env` and `Hud` LocalScripts and every new module | builds; the place holds the review round's code | builds; the place holds review 2's code |

**Stability after review 2** (bundle md5 `19c1e8d7…`). Floors are random every run. On the final tree:
`check_facilitynightmare_env` 6 of 6 at 264 / 0, `_hazards` 12 of 12 at 53 / 0, `_firstframe` 6 of 6 at 18 / 0,
`check_facilitynightmare`, `_input` and `_desktop` 3 of 3 each, `_hud` 4 of 4, the walk 4 of 4 (55-71), plus the final
gate run. On the tree just before its last two edits (a redundant guard taken out of Env.client, and the hazards check's
harness fix below): `_env` 10 of 10, `_firstframe` 10 of 10, `check_facilitynightmare`, `_input` and `_desktop` 6 of 6
each, the walk 4 of 4, and `_hazards` 33 of 34. The one failure was a bot death in section E, and the assert's own
message then crashed on a nil State. The check's player now has every perk, and the message is nil-safe; nothing the
check asserts depends on the perks. The D3 control measured leaves joining two bands from both sides in all 16 env runs,
and the firstframe audit saw door-frames of such a leaf in 13 of its 16 runs.

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

### Mutation sweep (review 2, the final tree)

Driver: review 2's own driver (`scratchpad/fnrev2/mut/driver.py`, pointed at a frozen copy of the final tree) with a
parallel runner and this round's `mutations.py` (`scratchpad/fnp1_0930/sweep/`). Three workers on fresh copies, **all 23
suites** per mutation, every mutation applied exactly once and **proved to be in the rebuilt bundle** (the mutated bundle
equals the baseline bundle with the same replacement, path lines normalised), the frozen baseline proved unchanged
after the sweep, and the real tree sha256-identical to its pre-sweep record. The baseline ran all 23 suites green first.

**Result: 27 of 27 KILLED, all 3 controls SURVIVED.** One trap in the driver, found while reading this sweep: it counted a
gate as passed when its last line contained "0 failed", so "10 failed" read as a pass. Every log was re-read with a
digit-boundary match; the only change was one more killing suite for F3-c (Dressing.spec, 10 failures). No control
depended on it.

| id | mutation (review 2) | killed by |
|---|---|---|
| F1-a | Env.client never calls off at the lift | hazards |
| F1-b | `Hazards.step`: callOff cancels nothing | Hazards.spec, hazards |
| F1-c | `Hazards.step`: a hazard may start at the lift | Hazards.spec, hazards |
| F1-d | HUD: the text rows stay above a modal | hud |
| F1-e | HUD: the rows are not kept to the touch band's middle | hud |
| F1-f | HUD: no room kept below a modal | hud |
| F1-g | HUD: the hint shown below a modal where it does not fit | hud |
| F2-a | the bio-lab is no brag | EnvConfig.spec |
| F2-b | server: every powering is a record | check |
| F2-c | HUD: the fanfare ignores the record flag | env |
| F2-d | HUD: every band gets a fanfare | env |
| F2-e | HUD: the long-term goal gets none | env |
| F2-f | HUD: any sublevel of the band, not its first | env |
| F2-g | HUD: no FOV punch on the fanfare | env |
| F3-a | Env.client paints a leaf in its lower room's band again (the defect) | env, firstframe |
| F3-b | `leafSide`: an unbuilt lower room on the wrong side | Dressing.spec |
| F3-c | `leafSide`: the normal is the wide axis | Dressing.spec, env, firstframe |
| F3-d | the doors are never painted | env, firstframe |
| U1 | rift knock 30, lift 4 (the reviewer's) | EnvConfig.spec, env, firstframe, hazards (validate switches hazards off) |
| U1-b | `KnockMax` 24 → 30 | EnvConfig.spec |
| U1-c | validate ignores the config's knock bounds | Hazards.spec |
| U2 | the warning rate uncapped (the reviewer's) | hazards |
| U4 | the DEPTH RECORD board faces the wall (the reviewer's) | env |
| U5 | a bench sitter faces the wall (the reviewer's) | env |
| U6 | `FixtureKeepOut` 2.5 → 0 (the reviewer's) | EnvConfig.spec |
| D-1 | `IntervalMin` back to 120 | EnvConfig.spec |
| D-2 | `IntervalMax` back to 180 | EnvConfig.spec, hazards |
| CONTROL-1 | the fanfare's FOV punch eases back in 0.45 s, not 0.4 | SURVIVED, as it must |
| CONTROL-2 | the fanfare's banner stays 6 s, not 5 | SURVIVED, as it must |
| CONTROL-3 | a leaf keeps its colour within 0.04 of its plane, not 0.05 | SURVIVED, as it must |

D-1 is killed by the spec's pin alone: the hazards check's gaps (90-140) still hold at 120-140, and asserting the
shortest of 18 gaps below 100 s would fail about 2 % of honest runs.

**Re-run on the current tree (2026-10-01, pass 1 again, §14).** The same 27 mutations and 3 controls, on fresh copies of
the tree pass 2 left (bundle md5 `61caa0b0…`), with `scratchpad/fnp1_1001/sweep/driver.py` and **all 26 suites** (the
board's two checks are new since): **27 of 27 KILLED, 3 of 3 controls SURVIVED**, every mutation proved in the bundle.
Two killer lists changed: F3-a fell to the env check alone this time (the firstframe audit only sees door frames the
floor happens to give it), and U1 also to the board and input checks, which count the warning `Hazards.validate` prints
when it switches hazards off.

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
    - About half of perk-less medium runs reach the reactor (57 of 120), and 8 % reach the void (10 of 120).
    - Are hazards rare and fair at one per 90-140 s of lit time (the owner's decision)?
    - Does anyone miss a mid-run rest?
17. **Review 2's changes** (headless proves the layout and the colours, never how they look):
    - While the EXTRACT / DESCEND modal or the perk panel is up, the toast, hint and banner sit below it; on a phone
      they are narrowed to the middle of the band the thumbstick and jump button own. Readable there, over the
      touch controls' own graphics?
    - The fanfare (`NEW RECORD — OVERGROWN BIO-LAB`, amber, with an FOV punch) under the choice modal: does it feel
      like a brag? Do a medium player's first 30-45 minutes really get there (the pacing is a bot's)?
    - A door leaf between rooms of two bands changes colour when the player crosses its plane (in a doorway, where
      the leaf is edge-on or, when open, its lip is overhead). Watch the lip under a lintel for a visible snap.
    - Hazards never start in the powered lift's room: is the room still interesting, and does a live hazard vanishing
      as the player steps into the lift read as fair?
18. **Pass 2's additions** (headless proves the numbers, the layout and the calls, never how they look or what Roblox's
    services return):
    - **The TOP DIVERS board** (north wall, 13 x 7 studs, 1300 x 700 canvas, rows at 34 px): legible from the spawn,
      20.4 studs away? Its amber glow and the DEPTH RECORD board opposite: two boards, or one too many?
    - Its ProximityPrompt (E, 10 studs, no hold) at the board's foot: does it show where a player stands to read it,
      and does it never compete with the perk terminal's (31 studs apart)?
    - The real services: `GetOrderedDataStore`, `GetSortedAsync`, `Players:GetFriendsAsync` pages and
      `GetNameFromUserIdAsync` on a published place. The emulator has no friends service (the check supplies one) and
      its store never throttles; watch the output for "request was added to queue" when a friends view is opened.
    - A band a viewer has not reached shows as ??? on their board (no spoilers): does ??? next to a deep number tempt,
      or confuse?
    - **The REST button** beside PERKS on a phone: tappable, and does resting read (the soft focus, the hint)?
    - The local-parts cap is headless-proven never to bind on a real floor; nothing to see unless a kit grows.
19. **Pass 2 resumed (2026-10-01): critters, the offices' dust, the lift's hint** (headless proves where a critter can be,
    that it moves only in a near, lit room and within the cap; never how it looks):
    - The seven critters (a 0.55-stud cockroach, a white lab mouse, a moth, a rat, a bat, a beetle, a pale drifter): do
      they read as what they are at that size, in first person and in the flashlight? Too small to notice, or a
      distraction from finding fuses?
    - A scurrier turns round by mirroring (its parts swap ends): does the turn read as an animal turning?
    - A critter keeps still in a dark room and in the flicker's low step: in the flashlight, is a frozen roach creepy or
      a visible bug?
    - The offices' dust motes (3 a second, 0.14 studs, lit by the room, high in the room): visible at all, or noise?
    - Back through a flickering room into the powered lift: the hint reads `EXTRACT (E) to bank it, or DESCEND (Q) for
      more.` at once (it read "Your room is going dark" for up to 3 s before; desktop check F).

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

**Format: 1920x1080** (16:9 landscape, the Roblox thumbnail size). Set the Studio window or the capture region to
1920x1080 before each shot, or capture larger and crop to exactly that, never stretch. The vertical 1080x1920 clips are
MARKETING.md's, not these.

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
   - Variant (pass 2): turn round to the north wall for the TOP DIVERS board, camera ≈ (-19, 5, 4) looking at
     (-19, 5.5, 19.8), the board filling the middle third. In a place with no API access it says it cannot be reached:
     take this variant only where the real public board shows, or leave it out.
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

**Critters in frame (pass 2 resumed).** Every band has one (the cockroach, the lab mouse, the moth, the rat, the bat, the
beetle, the drifter; §2's table), in about 70 % of rooms, at a wall slot near a corner. A critter moves only while its room
is lit and within 32 studs of the player (at most 4 at once), so stand in or next to its room. Good extras: the moth under
the server vault's cable tray (shot 2), the rat at the flooded room's waterline (shot 3), the beetle high on a bio-lab wall
(shot 5), the drifter over the void's debris (shot 6). In the offices (shot 1's variant on a floor) the dust motes show
best against the dark ceiling.

---

## 10. Not done / open

- **Two independent adversarial reviews are done** and their ten findings are closed (§11, §12). Review 2's own changes
  have been mutation-tested (§7) but not reviewed by a third pass.
- **`luau-analyze` was not run** (the binary is gone from the shared scratchpad; still gone in the review round).
  The strict-mode type noise of the new modules is unknown.
- **Gustav's call: hazards and near-hits** (review finding 3, §3). **DECIDED 2026-09-30 (owner: take recommended):
  option 2, `IntervalMin` / `IntervalMax` 90 / 140.** None of the four was marked as recommended, so the one that best
  serves the brief (fair, fun, never punishing, never exploitable) was taken:
  1. **Keep it.** Not taken: at one hazard per 3.3-4 minutes of play in the bands that have them, it misses the brief's
     "about one per 2-3 minutes".
  2. **More often: 90 / 140. TAKEN.** It is the only option that moves the measured rate into the brief's number (now one
     per 2.6-3.1 floor-minutes in those bands, §3). It is a config change: every fairness rule stays as it was (the
     telegraph, the ring that is exactly what hits, one at a time, never in the dark, never on arrival, never at the
     choice). The escape arithmetic is unchanged, a hit still costs nothing, and hazards are client-only, so there is
     nothing to exploit. A player who stops at the banner gets a near-miss every time. A walker still mostly sees a
     banner (5 of 349 bursts within 8 studs of the bot, 1.4 %).
  3. **Aim ahead of a moving player.** Not taken: it cannot make a walker's near-miss inside one room. The burst comes
     2.8-3.2 s after the warning, and a walker covers 29-51 studs in that time, while a legal spot lies within a
     14 × 14 stud square of a 26-stud room. So the ring lands on their path and they walk through it before it bursts.
     It would also break the rule "the ring is where you stood".
  4. **Start only when the player has stood still.** Not taken: it makes hazards rarer still, away from the brief's
     number, and never happens at all to a player who keeps moving.
- **The void is reached by 8 % of perk-less medium runs** (10 of 120, review 2; the 17 % that stood here was an older
  run, and this file's own table said 12 %). It is the long-term goal; the brag is now the bio-lab (§2). Real player
  depths (CLAUDE.md "Needs Studio" item 1) will show whether the band starts are right.
- **The slow player's brag** (review 2, finding 2's slow half; it stood here as open, and in CLAUDE.md "Next" 5).
  **DECIDED 2026-09-30 (owner: take recommended): left as designed.** One brag, the OVERGROWN BIO-LAB, timed for normal
  play (the medium proxy). No option was marked; the file's own position was this one ("a per-speed brag was not built:
  the standard asks for normal play"), and it was checked against the brief (fair, fun, never punishing, never
  exploitable) with a per-band run of the pacing model on the current tree (2026-10-01; `tests/pacing.measure.luau`'s
  model with the first powering of every band's first sublevel recorded; minutes since join, p50):

  | band (first sublevel) | slow (10.4), 20 players | medium (12.8, normal play), 30 players |
  |---|---|---|
  | LABORATORIES (3) | 4.0 | 3.1 |
  | SERVER VAULT (5) | 15.0 | 6.2 |
  | FLOODED MAINTENANCE (7) | 32.7 (15 of 20 within 45) | 9.6 |
  | REACTOR CORE (9) | 90.7 (8 of 20 within 45) | 18.5 |
  | OVERGROWN BIO-LAB (11), the brag | later than 150 (3 of 20 within 45, 6 of 20 within 150) | **37.0** (24 of 30 within 45) |
  | THE VOID (13), the goal | later than 150 (1 of 20) | 46.6 |

  1. **Keep it. TAKEN.** Fair: the brag means one thing for everyone, on TOP DIVERS and in `leaderstats`. Never
     exploitable: it is the server's powered record. Never punishing: a slow player loses nothing by it and still meets a
     new band at about 4, 15 and 33 minutes; their fanfare comes when their record gets there.
  2. **An earlier brag band.** Not taken: no band fits both. The one a slow player reaches inside 45 minutes (the
     flooded maintenance, 15 of 20) comes after 9.6 minutes for a medium player, too cheap for a brag, and the reactor
     (8 of 20 slow players within 45) after 18.5.
  3. **A fanfare on every new band.** Not taken: the ride already names each band (`SUBLEVEL 7 — FLOODED MAINTENANCE`),
     and a brag that every band gives is not a brag (review 2's mutation F2-d, "every band gets a fanfare", is held
     killed by the env check).
  4. **A catch-up for slow players.** Not taken: the server cannot tell a slow player from a careful one, and it would
     move the difficulty curve DESIGN.md measured.

  The sibling games made the same call (anomaly-observatory D2, "left as designed"; same-door DESIGN §21.2). What can
  reopen it is real players' depths (CLAUDE.md "Needs Studio" item 1). No code changed: `EnvConfig.spec` already pins
  exactly one brag (the bio-lab, from 11) and the goal (the void, from 13), and the pacing model shows any retune.
- **docs/complete-game-standard.md, pass 2 (2026-10-01):** the public and friends board, `MARKETING.md` (eight clips),
  the REST button, the local-parts cap in code and the store text are built (§13). `luau-analyze` is still not in the
  shared scratchpad, so it has not been run on any of this.
- **The proposed store text in README.md** (pass 2) names the first five bands, the hazards, the rest and the board.
- **A rare flake in `check_facilitynightmare_desktop`: CLOSED (pass 2 resumed, §15).** It was seen once in about 190
  runs: the lift's hint read "Your room is going dark" 0.3 s after powering. It was a real defect, not the bot: the HUD
  holds a `roomDying` hint for 3 s, so a player who came through a flickering room into the lift (or stepped out of the
  powered lift into one and back) read it at the choice, over a lift that never goes dark. Made certain in desktop check F
  (2 of 2 assertions failed before the fix), fixed in `Hud.client` (at the powered lift its own hint wins).
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

### Finding 3 (low): hazards are rarer than the brief, and a walker almost never gets the near-hit. FRAMED for Gustav; DECIDED 2026-09-30 (owner: take recommended), option 2 (§10)

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

---

## 12. Review 2 (2026-09-30) and how each finding was closed

A second independent reviewer read the tree the §11 round left (unchanged since, git HEAD `b347f56`), ran all 23 gates
and probed it. Five findings. Each was **reproduced first** on an untouched copy of that tree with the reviewer's own
probes, each fix went **test-first** (every new assertion below was watched failing on the untouched tree, or, where the
code already kept the promise, on the reviewer's mutant), and the sweep in §7 mutates every new rule.

### Finding 1 (medium): text lay on the EXTRACT / DESCEND modal on a phone. CLOSED, wider than reported

**Reproduced.** The reviewer's probe (the real server, HUD and Env.client; the offices given the labs' hazard in memory;
the bot 6.5 studs from the powered exit room's centre): a hazard warning came 119.7 and 108.7 s later, on 2 of 2
runs, and the banner lay on the choice modal on 5 of 10 viewports each time (phone landscape 264 × 46 px, small phone
264 × 34, laptop-touch 440 × 13, phone-landscape-mouse 264 × 18, and the touch-again repeat). Control with no hazard
kind: 0 of 10.

**Wider.** The same gate gap (hudcheck's rule 4b counts Frames, and the toast, hint and banner are TextLabels) hid two more
overlaps, found by a probe of every text row against both modals:
- at every powering, the toast (`Fuses in: 3/3`) and the hint lay on the choice modal on 3 of 10 viewports;
- with the perk panel open, a purchase's toast and the hub hint lay on its title and first row on **10 of 10**
  viewports, the desktop too.

The new audit counted **31 overlaps in 20 viewport-modes** on the untouched tree.

**Fix, two halves.**
- **The game:** no hazard starts at the powered lift, and a live one is called off when the player reaches it. The
  server's `atLift` covers the whole powered exit room, and that is where the modal shows. `Hazards.step` takes
  `ctx.callOff` and decides both (one place, trap 37). The clock runs on there, as on the car's pad, so a hazard that
  falls due waits and, after DESCEND, waits out the arrival grace.
- **The HUD:** while a modal is up, the banner, toast and hint sit BELOW it. A modal keeps room for the banner and the
  toast under it. The hint is left out where it does not fit, because the modal says what to do. On a touch screen,
  rows that reach the band Roblox's controls own keep to the middle, clear of the thumbstick's corner (0.35 of the
  width) and the jump button's (0.25).

**Tests** (all failing on the untouched tree):
- `check_facilitynightmare_hud`: the text audit. On all 20 choice and perk viewport-modes it re-fires a real refused
  request (a toast) and, at the choice, a hazard warning on the bus exactly as Env.client sends one. It asserts no
  visible text row on a visible modal, every row fully on screen, and the touch band's middle. Before the fix: 31
  failures. After: 0, with the banner audited 10 times, the toast 20 and the hint 16.
- `check_facilitynightmare_hazards` E: 200 s at the powered lift, 6.5 studs out (off the pad, a legal spot anywhere
  else), with a hazard long due: none.
- `check_facilitynightmare_hazards` D: a State saying `atLift` during a live hazard calls it off at once, with its ring
  and banner, and it never bursts.
- `Hazards.spec`: callOff cancels a live hazard; 300 s at the lift with one due and a legal spot starts none while the
  clock runs; the first legal moment after it brings exactly one.

**After:** the reviewer's probe gave no warning in 200 s, and 0 of 10 overlaps, on 2 of 2 runs. Mutations F1-a..g.

### Finding 2 (medium): the brag was not reachable in 30-45 minutes. CLOSED for the medium proxy

**Reproduced** with a per-sublevel version of the reviewer's pacing probe: fresh players, perks bought between runs,
always DESCEND, 30 players per proxy, run in parallel. At the medium proxy the first powering of sublevel 13 had a
median of 52.9 min (p10 30.8, p90 110.8); 11 of 30 players got there within 45 min and 3 of 30 within 30. The slow
proxy: 0 of 30 within 150 min. The perfect proxy: a median of 16.0.

**Fix.** The brag is the OVERGROWN BIO-LAB (`brag = true`), the deepest band of the facility itself, and the void is the
long-term goal beyond it.
- **The server:** the `choice` notice says `record = true` when this powering raised the saved best. Only the server
  knows the best before it.
- **The HUD:** on a record that powers the first sublevel of the brag band or of the last band, it shows
  `NEW RECORD — <BAND>` with an FOV punch, below the modal (finding 1's layout).

**Tests** (failing on the untouched tree):
- `EnvConfig.spec`: exactly one brag, the bio-lab, from 11; the goal is the void, from 13; every fanfare banner is at
  most 40 characters.
- `check_facilitynightmare` D and E: `record` is true on VET's first powering and false on the next.
- `check_facilitynightmare_env` B: the notice as the server sends it, with the bands moved in memory. The brag's first
  sublevel gets the fanfare; the same powering with no record gets none; a sublevel that starts no band gets none; the
  offices as shipped get none; THE VOID gets its own.
- `check_facilitynightmare_env` F, through the server: three new records on sublevels 1-3, with the offices marked as the
  brag, give exactly one fanfare.

**Measured** with `tests/pacing.measure.luau`: the medium brag's median is 29.6 min; 16 of 30 players got there
within 30 min and 27 of 30 within 45 (§2). **Not closed for the slow proxy**: 0 of 20 in 45 min. That half is not a
defect against the standard (it asks for normal play, and DESIGN.md §0 makes the medium proxy normal play); it was an
open owner decision, **DECIDED 2026-09-30 (owner: take recommended): left as designed** (§10, with the per-band minutes).
Mutations F2-a..g.

### Finding 3 (low): a door between two bands broke the 90-110 % contrast promise. CLOSED

**Reproduced.**
- The reviewer's arithmetic: a servers room with a labs door gives 71 % (white light) and 72 % (room light); a labs
  room with a servers door 138 %; every other adjacent pair 94-104 %.
- The reviewer's end-to-end probe: 1 of 3 closed-door sides outside 90-110 % (138 %), on 3 of 3 runs. Control
  (flooded to reactor): 0 of 3.
- How common, on the shipped config: of 10 957 doors on 400 real sublevel-4 plans, 2 272 (21 %) join the labs and the
  server vault, on 400 of 400 floors (the reviewer's `crossdoor_k4` probe, re-run).

**Cause.** Env.client painted every leaf in the band of its lower room id.

**Fix.** A leaf is a thin slab seen from one side at a time, set in that side's wall. `Dressing.leafSide` answers which
of its rooms is on the viewer's side: its thin axis is the doorway's normal, and an unbuilt room is the built one's
mirror image through the leaf. Env.client paints every leaf in that room's band, every frame after the dressing pass,
and writes a colour only when it changes. On the plane itself, in a doorway's middle, where the leaf is edge-on or its
lip is overhead, it keeps what it wore. No palette changed.

**Tests** (failing on the untouched tree):
- `Dressing.spec`: 12 cases, both orientations, both sides, unbuilt rooms, on the plane.
- `check_facilitynightmare_env` D3: the labs on a floor with the server vault blended in, the blend chosen so that most
  of the entry room's leaves join two bands. From inside the entry and from a stud past each leaf's plane, each leaf
  must wear the door of the band on the player's side and stand out 90-110 % in white and in room light. 6 failures
  before the fix; after, 16 of 16 runs measured such leaves from both sides.
- `check_facilitynightmare_firstframe`: the audit's door rule is now the player's side, re-derived from the leaf's own
  geometry. Before the fix it found 132 wrong frames on the real sublevel 2, where the labs creep into the offices.

Mutations F3-a..d.

### Finding 4 (low): five environment promises no gate held. CLOSED

Each of the reviewer's five surviving mutants is killed now (§7: U1, U2, U4, U5, U6).
- **U1:** `Hazards.validate` holds every kind to the config's promised shove (`KnockMin` 16, `KnockMax` 24, `LiftMax` 3)
  instead of the module's 30 / 4. `EnvConfig.spec` pins the bounds and every kind's numbers, and `Hazards.spec` has
  nine new cases.
- **U2:** `check_facilitynightmare_hazards` C reads every warning emitter's rate on every frame: at most 10/s. It
  reached 9.80/s, a control that the warning does thicken.
- **U4:** env check B: the DEPTH RECORD board's SurfaceGui face points at HubSpawn, from the south wall.
- **U5:** env check B: both benches seat a player facing into the room.
- **U6:** `EnvConfig.spec` pins `FixtureKeepOut` 2.5, `PadKeepOut` 5.5 and `SpotMinWallDistance` 6. `spotOk` with the
  shipped config refuses a spot 1 stud off a room's centre.

The four promises other than U1 were already kept by the code; their tests were watched failing on the reviewer's
mutants.

### Finding 5 (low): a stale 17 %. CLOSED

`tests/hazards.measure.luau` on the final tree: the void is reached on **10 of 120** perk-less medium runs (8 %), the
reactor on 57 of 120 (48 %). §2's table, §8 item 16 and §10 now carry these numbers.

### Also found and fixed this round
- **The mutation driver's pass test** read "10 failed" as a pass (§7). Its logs were re-read; nothing it reported changed.
- **`check_facilitynightmare_hazards` could crash in section E** on a bot death (1 of 34 runs): its assert message
  indexed a nil State. The message is nil-safe now, and the check's player has every perk, as the env check's already
  did.

---

## 13. Pass 2: the complete-game standard (2026-10-01)

Every item of `docs/complete-game-standard.md` was checked against the code, not the earlier reports. What was missing
was built test-first (each new assertion watched failing first), then mutation-tested with controls (below).

| standard | before pass 2 | now |
|---|---|---|
| §3 highscore board, public + friends | only `leaderstats.Deepest` and the personal DEPTH RECORD | **TOP DIVERS** on the break room's north wall (13 x 7 studs, 20.4 studs from the spawn, facing it), ProximityPrompt E toggles Public / Friends. OrderedDataStore `FacilityNightmare_TopDivers_v1`, key `u_<userId>`, value `bestSublevel * 2e9 + (2e9 - bestAt)`; `shared/Board.luau` is plus1-jump's, verbatim |
| §2 rest: "trykke på pause" | a bench or 20 s standing still | also a **REST** button beside PERKS (`Rest.press`); GET UP or moving ends it; refused with a toast outside the break room |
| §2 budgets capped in code | local parts held by arithmetic only | Env.client parents dressing nearest-first within `MaxLocalParts` less the hazard's 8 (never binds on a real floor, §6) |
| §2 phone first, rule 4b | `overlap = true`; the hub's own HUD never measured | a `[hub]` mode: PERKS and REST measured on 10 viewports |
| §2 brag in 30-45 min | medium median 29.6 min (pass 1) | re-measured on this code: medium median 26.9 min, 23 of 30 within 45 (§2); not retuned |
| §4 store text | did not mention bands, hazards or rest | 957 characters: bands to the reactor, hazards, rest, the board |
| §4 thumbnail list | no resolution | 1920x1080, and a TOP DIVERS variant of shot 1 (§9) |
| §4 clip list | none | MARKETING.md: eight vertical clips with staging and honesty rules |
| §4 needs-Studio | items 1-17 | item 18 (the board, its prompt, the real services, REST on a phone) |

**How the board keeps its promises** (check_facilitynightmare_board, 104 assertions, through the real server, Board.client,
Env.client and a bot that powers real lifts):
- The metric is the server's: only `power` raises `bestSublevel`, behind the trusted position. Forged CHOOSE / BUY from
  the break room write nothing to the board.
- Ties go to the first: Bo and Ava both at sublevel 4, Bo reached it earlier and ranks above her. A record saved before
  the board existed is stamped once, with the session it came back in, and that stamp is saved.
- Written only when it improves: two autosaves with no new record, 0 writes; NEW powers sublevel 1 (1 write, stamped
  within 5 s of the powering), then 2 (1 more), then sublevel 1 again (0). A board value higher than the profile
  (Ned: 8 on the board, 5 in his profile) is never lowered.
- Public top 10: 3 GetSortedAsync calls in 180 s; a failing read keeps the last list.
- Friends on demand: none fetched before the prompt; one fetch, then cached (no new reads on the next toggle); scores
  read only for friends not on this server; 450 friends: 41 reads in the first second, 100 in the first minute, exactly
  200 in all, 3 pages turned. Empty boards say something: no friends, friends who never powered a lift, the friends
  call failing.
- The drawn board: a SurfaceGui on the front face (canvas in the face's proportions), not in PlayerGui; a band the
  viewer has not reached shows as ??? (no spoilers); names are never stored; no attribute on the board; no break-room
  dressing within the board's 3 studs.
- check_facilitynightmare_boardoff (16): with every call to the board's store raising, the server boots, the board says
  "The board can't be reached on this server right now." (not "nobody has played"), the prompt still answers, the
  player's file still loads; when the store comes back the record that failed to write is written at the next save.

**Gates on the final tree** (bundle md5 `61caa0b0e1849935d9c352c330fb842a`): 16 specs 1 558 passed, 0 failed (Board 66
new, Economy 93 -> 109, Rest 43 -> 77); check_facilitynightmare 205/0, _board 104/0 (new), _boardoff 16/0 (new),
_input 116 -> 132/0, _desktop 47/0, _env 264 -> 269/0, _hazards 53/0, _firstframe 18/0, _hud PASS in 40 viewport-modes
(30 before; the text audit still 20); walk 67/0. Repeat runs on the same bundle: _board 6 of 6, _boardoff 4 of 4, _input
4 of 4, _env 3 of 3, _hud, _firstframe, _hazards, main and _desktop 2 of 2 each. luau.exe + loadstring: 51 of 51 files
compile, a broken control does not. Rojo 7.7.0 builds. `luau-analyze` NOT run (still not in the shared scratchpad).

**Pass 2's mutation sweep.** Pass 2's own sweep was cut off after B1-B12 of its 27 mutations and 3 controls (B11 survived,
B13 was half-run), and this table was left as a placeholder. It was completed on the same tree by pass 1's re-run (2026-10-01,
§14): pass 2's 27 mutations and 3 controls plus **B11b**, each applied exactly once to a fresh copy, **proved to be in the
rebuilt bundle** (the mutated bundle equals the baseline bundle with the same replacement, path lines normalised), and run
against **all 26 suites** (16 specs, the walk, 9 checks); every log read with a digit-boundary match (trap 43a). The
baseline ran all 26 green in both workers first; afterwards both workers' `src` were byte-identical to the frozen copy,
and the real tree's `src` to its sha256 at the start of the pass. Driver: `scratchpad/fnp1_1001/sweep/driver.py` +
`muts.py` (which loads `fnp2/mutations.py`).

**Result: 27 of 28 KILLED, B11 SURVIVED as an equivalent mutant, all 3 controls SURVIVED.**

| id | mutation (pass 2) | killed by |
|---|---|---|
| B1 | `power` never stamps a new record's reach time | Economy.spec, board |
| B2 | powering the same depth again restamps it (ties to the LAST) | Economy.spec |
| B3 | sanitize drops `bestAt` and `boardBest` | Economy.spec, board, boardoff |
| B4 | a legacy record is never stamped at load | board |
| B5 | the board is written on every save, not only when the record rose | board |
| B6 | the board write ignores what is stored (no `keepHigher`) | board |
| B7 | `boardBest` is set even when the board write failed | boardoff |
| B8 | `Board.encode`: ties go to the LAST (2e9 + t) | Board.spec, board |
| B9 | the public top 10 is read every 5 s, not once a minute | board |
| B10 | a player's friends list is never cached | board |
| B11 | the friends loop's `while` condition drops the cap of 200 | **SURVIVED: equivalent.** The cap is held three times in that loop (the `while`, the insert, the `break`); any one of them alone keeps it |
| B11b | all three cap checks gone | board |
| B12 | friends' scores are read without the limiter | board |
| B13 | the client draws views sent to other players | board |
| B14 | the board names bands the viewer has not reached (spoilers) | board |
| B15 | a board that was never read says "nobody has played" | boardoff |
| B16 | the board faces the wall (turned 180°) | board |
| B17 | the board's canvas is a fixed 400 x 200 | board |
| B18 | the prompt toggles nothing (stays public) | board, boardoff |
| B19 | a new record is not written at the powering's save (only on leave) | board, boardoff, walk |
| R1 | `Rest.press` ignores the phase (rests on a floor) | Rest.spec, input |
| R2 | pressing while resting does not get up | Rest.spec, input |
| R3 | REST shows on a floor too | input |
| R4 | a refused REST press is silent (no toast) | input |
| R5 | REST drawn in the thumbstick's corner on a phone | hud |
| R6 | REST under the minimum tap size on a phone | hud |
| P1 | no local-parts cap: every room in range is parented | env |
| P2 | the cap keeps the FARTHEST rooms first | env |
| CONTROL-1 | the board's title a little smaller (60 -> 58 px) | SURVIVED, as it must |
| CONTROL-2 | the board part a shade lighter | SURVIVED, as it must |
| CONTROL-3 | the boarding refusal worded differently | SURVIVED, as it must |

---

## 14. Pass 1 again (2026-10-01): review 2 and the owner's decisions, re-checked on the current tree

The workflow ran pass 1 a second time. The tree already held pass 1's fixes (§12) and pass 2's work (§13); pass 2 had
been cut off during its mutation sweep, so §13's sweep table and CLAUDE.md's gate line were placeholders. At the start
every one of the 26 suites was green (bundle md5 `61caa0b0e1849935d9c352c330fb842a`). Each of review 2's findings was
re-checked on a copy of this tree with the reviewer's own probe (`scratchpad/fnrev2/robloxemu/`):

| finding | the reviewer, on the old tree | this tree |
|---|---|---|
| 1. the hazard banner on the EXTRACT / DESCEND modal (medium) | a warning 76.8-135.3 s after standing 6.5 studs off the lift's centre, 4 of 4 runs; banner on the modal on 5 of 10 viewports | `probe_choicebanner`, 4 runs: no warning in 200 s, 0 of 10 viewports overlapped, each run; its control 0 of 10. Does not reproduce |
| 2. the brag not reachable in 30-45 min (medium) | medium median 71.0 min (to the void); slow 0 of 30 within 45 | the brag is the bio-lab now: medium p50 31.8 (21 of 30 within 45) and 37.0 (24 of 30) in two samples. The slow half reproduces (0 and 3 of 20 within 45): an owner decision, **DECIDED 2026-09-30 (owner: take recommended): left as designed** (§10) |
| 3. doors between two bands (low) | 24 of 85 closed-door sides outside 90-110 % over 30 runs | the reviewer's `probe_crossdoor`, 30 runs: 0 of 69. Adapted to stand in the room each side is seen from: 0 of 69, 31 of them on leaves joining the labs and the server vault; its control (flooded to reactor) 0 of 25 over 10 runs. Does not reproduce |
| 4. five promises no gate held (low) | U1, U2, U4, U5, U6 survived all 23 gates | each killed (§7's re-run: 27 of 27 KILLED, 3 controls SURVIVED) |
| 5. a stale 17 % (low) | EYECANDY said 17 %, its table 12 % | no 17 % is left for the void's reach; §2, §8 item 16 and §10 carry 8 % (10 of 120) |

**Owner's decisions** ("take the recommended option for all", 2026-09-30). Two open decisions were found in this file,
CLAUDE.md and the REVIEW files: the hazard interval (already DECIDED 2026-09-30 (owner: take recommended), option 2,
90-140 s, §10) and the slow player's brag, which stood in §10 and CLAUDE.md "Next" 5 as open. The second is DECIDED
2026-09-30 (owner: take recommended): left as designed, with the per-band minutes and the four options in §10. It
changes no code, so it needed no new test: `EnvConfig.spec` already pins the one brag and the goal.

**What changed in this pass:** documentation only. No game source, test or check changed; the real tree's `src` is
sha256-identical to its state at the start of the pass, and the bundle is still `61caa0b0…`. §13's sweep (pass 2's,
completed here: 27 of 28 KILLED, B11 equivalent, 3 controls SURVIVED) and §7's re-run replace the placeholders.

**Gates on the final tree** (bundle md5 `61caa0b0e1849935d9c352c330fb842a`), five full runs (one at the start, four at the
end), every count the same each time but the walk's: 16 specs **1 558 passed, 0 failed** (Board 66, Config 106, Dressing 99, Economy 109, EnvBands
124, EnvBus 11, EnvConfig 511, Facility 84, Fx 26, Hazards 108, MazeGen 3, Responsive 70, Rest 77, Rng 37, Survival 74,
Trust 53); check_facilitynightmare 205 / 0, _board 104 / 0, _boardoff 16 / 0, _desktop 47 / 0, _env 269 / 0, _firstframe
18 / 0, _hazards 53 / 0, _input 132 / 0, _hud PASS; walk 55-71 / 0 (its count varies with depth). Every file compiles
(`luau.exe` + `loadstring`, 51 of 51; a broken control fails); Rojo 7.7.0 builds the place. `luau-analyze` NOT run (still
not in the shared scratchpad).

---

## 15. Pass 2 resumed (2026-10-01): critters and weather in every band, the rejoin, the lift's hint

An earlier attempt at this pass was cut off by a usage limit. On resuming, the tree held passes 1 and 2's work (§13, §14)
and all 26 suites were green on it (bundle md5 `61caa0b0…`). Every item of docs/complete-game-standard.md was checked again
against the code, not the reports. Three gaps were left, none of them in the reviewer's list:

| standard | found | now |
|---|---|---|
| §2 bands: each with "its own light, colour, scenery, critters and weather" | no band had a critter, and the offices had no weather (particles: none) | a critter per band, in 67-75 % of rooms (600 real rooms per kit, a probe beside the spec), and dust motes in the offices (50 % of rooms) |
| §1 walk the player's path: "... spend, rejoin" | the walk ended after the second run; rejoins were checked only as stored values (check K) | the walk's REJOIN: leave, join again, land on HubSpawn (the RespawnLocation), the State shows the Essence, runs, deepest sublevel and the perk, `leaderstats.Deepest` is back, a third run has the perk's 55 s battery and is settled on leaving |
| the desktop check's rare flake (§10) | "worth a look" | a real defect (CLAUDE.md trap 48): desktop check F, fixed in `Hud.client` |
| §2 phone first, rule 4b | asserted; the reviewer's note that the HUD check never loads Env.client | the reason is written next to `clients` in the check: Env.client draws nothing in PlayerGui, and its screen text goes over EnvBus into the HUD, which section 4 fires exactly as Env.client does |
| §2 brag in about 30-45 minutes | five samples, medians 26.9-37.0 | a sixth (`tests/pacing.measure.luau`, 11 min, on the starting bundle: this pass changed only client code and `Config.Env` / `Budget`, which the server never reads): medium brag p10 15.0 / **p50 30.5** / p90 54.1 min, 15 of 30 within 30 and 24 of 30 within 45; void p50 71.7; slow 0 of 20 within 45 (the owner's decision stands, §10); perfect 13.5. No retune |

**The critters.** Each is two parts, never self-lit, matte, coloured clear of a fuse's amber and a cell's green by the
same rule as all dressing, and placed at a wall slot near a corner, LAST in the room (every earlier draw is unchanged, so
the rest of the room is dressed exactly as without it).

| band | critter | how it moves (`Dressing.critterPose`) | where |
|---|---|---|---|
| offices | a cockroach | scurry: 3.4 studs along the foot of a wall, a stop, turns round, runs back, a stop | the floor, in the wall band |
| labs | an escaped white lab mouse (pink tail) | scurry, 3.4 studs | the floor, in the wall band |
| servers | a moth | flutter: loops over 2.6 along, 2.2 up, 2.2 out, from 8.2 studs up | overhead |
| flooded | a rat at the water's edge | scurry, 3.3 studs | the floor, in the wall band |
| reactor | a bat | flutter over 3.0 / 1.8 / 1.6, from 8.6 up | overhead |
| bio-lab | a beetle | crawl: 3.0 along and 1.6 up the wall face, from 9.7 up | the wall band, above the doorways |
| void | a pale drifter, 45-50 % see-through | drift over 2.4 / 1.6 / 1.6, from 7.8 up | overhead |

The rules, and where each is held:
- **Every dressing rule over the whole path.** A critter part's checked box is the envelope of everywhere it can be: the
  part and, for a scurrier, its mirror image (it turns round by mirroring), swept over its travel along, up and out.
  `Dressing.critterBox` is where the client draws it at a moment. Dressing.spec, on 60 real rooms per kit: every pose
  (401 moments x 2 phases per part) inside its box, the size unchanged (it moves, it does not stretch), every critter
  moving more than half a stud, and spanning at least 90 % of each travel; the pose functions stay within 0..1 and use the
  whole travel, and a scurrier faces the way it runs and stops now and then. The envelope rule caught the bat and the
  drifter, whose paths reached into the next wall's door column (CLAUDE.md trap 49).
- **Never glows, never collides, one per room.** `Dressing.partOk` and `check` refuse a glowing or colliding critter and a
  second one; the spec's checker cases prove it.
- **Its own parts.** Two per room on top of the furniture's 14 (`Env.MaxCritterParts`, `MaxCrittersPerRoom`), so a full
  bio-lab room still gets one (trap 50); `Budget.MaxLocalParts` 240 -> 264 = 16 rooms x (14 + 2) + 8 hazard parts.
- **Moves like a particle.** Only in a room within `EmitterRadius` (32 studs) whose light is on at full brightness, nearest
  first, at most `Budget.MaxCritters` = 4 at once; anywhere else it keeps still where it is (a dark room holds nothing that
  moves). env check E2, on the densest floor D2 reached (2 to 12 rooms in this pass's runs), every band in turn: most
  bands drew their critter and no two the same kind (the spec holds every band to its own on 60 real rooms; on a 2-room
  floor the 70 % roll per room misses a band 9 % of the time, by arithmetic, and two early runs of this check missed one
  and two bands); a critter moves exactly when its room is near and lit and within the
  cap, all of its parts or none; every drawn part is critter-sized (not its path's size). Then, made certain in memory:
  with `EmitterRadius` at 1 stud nothing outside the player's room moves; in the nearest lit critter room the light off
  and the flicker's low step stop it and the light back on starts it; `MaxCritters` at 0 stops every critter, at 1 one
  room's, a nearest one's. env D and D2 audit every critter where it stands, with every other piece.

**Desktop check F (the lift's hint).** The server's own `roomDying` notice is sent while the bot carries every fuse to the
lift (stopping once the server has sent the choice), then once more at the powered lift. Before the fix both assertions
failed (53 passed, 2 failed): the hint read "Your room is going dark — turn on your flashlight." At the powered lift its
own hint now wins over any event hint (`Hud.client`, `atChoice`). Controls: the notice reached the HUD away from the lift,
the last one was inside its 3 s, and the State said `atLift`.

**Mutation sweep (pass 2 resumed).** 18 mutations and 3 controls, each applied exactly once to a fresh copy of the final
tree, proved to be in the rebuilt bundle, and run against all 26 suites (16 specs, the walk, 9 checks), every log read with
a digit-boundary match and a count of the suites that ran. The baseline ran all 26 green first; afterwards both workers'
`src` were byte-identical to the frozen copy. Driver: `scratchpad/fnp2b/sweep/driver.py` + `muts.py`. Two earlier runs of
the same sweep are not counted: they used E2's first far-critter control, which failed on a floor that lay wholly within
32 studs (seen killing RJ1 alongside the walk), and F's first control, which failed on 1 of 20 desktop runs when the lift
powered while the bot only passed through. Both controls were rewritten to be certain (EmitterRadius at 1 stud in memory;
such a floor is extracted and another played), and this sweep ran on the rewritten checks.

**Result: 18 of 18 KILLED, all 3 controls SURVIVED.**

| id | mutation | killed by |
|---|---|---|
| H1 | the lift's hint no longer outranks an event hint at the choice | desktop (2 failed) |
| RJ1 | a returning player's `leaderstats.Deepest` is not set when the file loads | walk (REJOIN) |
| C1 | critters are never moved by the client | env (6 failed) |
| C2 | critters move in a dark room too | env |
| C3 | no cap on the critters that move at once | env |
| C4 | critters far from the player move too | env |
| C5 | a scurrier never turns round | Dressing.spec (3 failed) |
| C6 | the envelope leaves out a scurrier's mirror image | Dressing.spec |
| C7 | the envelope leaves out the travel along the wall | Dressing.spec |
| C8 | critters are solid like floor furniture | Dressing.spec (3 failed) |
| C9 | `check()` lets a room hold two critters | Dressing.spec |
| C10 | the void has no critter | Dressing.spec |
| C11 | the offices have no weather | Dressing.spec |
| C12 | a critter is drawn at its whole path's size | env (12 failed) |
| C13 | `critterBox` ignores the travel up | Dressing.spec |
| C14 | `critterBox` ignores the travel out | Dressing.spec |
| C15 | the local-parts budget left at 240 | EnvConfig.spec |
| C17 | critters placed before the hangers (the rest of the room moves) | Dressing.spec |
| CONTROL-1 | a purchase's toast 3.5 s, not 3 | SURVIVED, as it must |
| CONTROL-2 | the cockroach a shade lighter | SURVIVED, as it must |
| CONTROL-3 | the moth a little faster | SURVIVED, as it must |

**Gates on the final tree** (bundle md5 `242e1a9873ebea19ea5c833bfda3b065`), three full runs, every count the same each time
but the walk's: 16 specs **1 649 passed, 0 failed** (Dressing 99 -> 187, EnvConfig 511 -> 514, the rest unchanged);
check_facilitynightmare 205 / 0, _board 104 / 0, _boardoff 16 / 0, _desktop 47 -> 55 / 0, _env 269 -> 283 / 0, _firstframe
18 / 0, _hazards 53 / 0, _input 132 / 0, _hud PASS; walk 86, 78, 85 / 0 (the REJOIN adds 15). The desktop check 30 of 30
more. Five earlier full runs, before F's retry, were green in all 26 suites too. Every file compiles (`luau.exe` +
`loadstring`, 51 of 51; a broken control fails); Rojo 7.7.0 builds the place. `luau-analyze` NOT run (still not in the
shared scratchpad). Densest local parts this pass: 229 of 264 (bio-lab, 16 rooms built).

---

## Night shift 2026-10-09: second review of b347f56 + 607b079 (job H step 2)

One independent read-only reviewer. Verdicts: **b347f56 SHIP-WITH-DEFERRED; 607b079 SHIP-WITH-DEFERRED.**
- **MEDIUM, fixed tonight: no Studio gate.** `Config.Data.AllowStudio`; MARKETING.md:91-92 says to film the
  board with API access on.
- **LOW, suspected, not fixed. Saves can overlap on one key** (no per-session write serialisation in
  `saveProfile`). An autosave can overwrite the leave payload and re-lock the key for 45 s.
- **LOW, not fixed.** `boardBest` is persisted, so a board reset or rename is never re-written.
- **LOW, not fixed.** The board prompt has no rate limit (self-DoS only).
- **LOW, not fixed, predates these commits.** Progress made while read-only is discarded when the lock clears.

Checked and clean:
- the remotes are type- or whitelist-checked, and Choose needs the trusted exit cell;
- the metric and tie time are server-side;
- nothing is pay-to-win;
- rest pays nothing;
- hazards are telegraphed and called off at the lift;
- no board is empty;
- no banned glyphs.
