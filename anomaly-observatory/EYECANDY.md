# Anomaly: Night Shift — the sky outside the observatory

Owner's brief (Gustav, 2026-09-17): every game richer and never monotonous, with the environment
changing as the player progresses in a way that fits the game; rare, telegraphed hazards; a way to
rest that can never be exploited; a thumbnail shot list for the night Studio session.

What that means in THIS game: it is spot-the-difference horror. The hall is rebuilt every pass and
is either clean or wrong in exactly ONE way, so any other change inside the hall would read as an
anomaly and break the game. The environment therefore changes **outside** the hall only: the night
sky beyond the concourse's open end progresses with your **Day** streak. There are **no hazards**:
nothing chases you is the premise, so nothing here ever touches the player.

**State: built, unit-tested, headless-tested through the real server and client, mutation-tested,
independently reviewed (2026-09-24: five findings, all reproduced and closed, §0b). NOT seen in
Studio.** Nothing was committed, pushed or published. `Main.server.luau` and `Hud.client.luau` are
byte-identical to `HEAD`.

---

## 0b. Review round (2026-09-24): five findings, all reproduced, all closed

An independent reviewer found five defects. Each was reproduced first (measurement below), then got a
test that failed on the unfixed code for the reviewer's reason, then a fix in the game (never in the
test), then a mutation sweep with controls (§7). No game rule, number or gate outside the sky changed.

| # | finding (severity) | reproduced | failing test first | fix |
|---|---|---|---|---|
| 1 | The break caption said `Day N is safe`, but the streak lives only for the session and Roblox disconnects a player idle for ~20 min (medium) | `Sky.client` lines 350-352 printed it; `ps.day` is never saved; nothing handled `Idled` | `NightSky.spec` (+26: `breakCaption`, `bandNews`, `introNews`, the validate rule); `check_anomalyobservatory_rest` failed 5 on the old build (`☕ On a break. Day 3 is safe ...`) | pure `NightSky.breakCaption`: never "safe"; once `Player.Idled` fires, the caption states the 20-minute disconnect, that a new session starts at Day 1 and which Day would be lost; any input clears it. `Config.Sky.IdleKickMinutes = 20`, required by `validate` |
| 2 | Every left/right in the thumbnail shot list was mirrored and the hero shot's avatar was out of its own frame (medium) | the reviewer's probe, re-run: comet sx -0.28 (listed "right"), avatar sx -0.97 sy -1.44 | new `check_anomalyobservatory_shots` played the list as written: 13 of 42 failed (every side, the avatar, the rim, the pan note) | §9 rewritten from the measurements; a new hero composition (camera inside the doorway, avatar wholly in the lower-right third, the whole doorway framing the sky). Cause: looking out of the entrance, Roblox's camera has +X on its LEFT |
| 3 | On small phones the band-up caption lay across the Mirror and ChartWall for the next pass, and the break button blinked at 2 Hz (low) | new check: Mirror under the caption at 13/19 walk points (640x300), and a finding the reviewer did not have: the Window at **17/19** on a portrait phone; the button changed colour 12-14 times on every viewport | new `check_anomalyobservatory_occlusion` (walks the hall on 13 viewports): 35 failures on the old build | on a phone (any compact layout) the sky writes nothing over the hall that the player did not ask for: band news and the join tip wait for the next break's caption; the button carries a **steady** highlight meanwhile, never a blink |
| 4 | Nine storm clouds were non-uniform `Ball`s and the Milky Way a 2200-stud Block: sizes Roblox does not draw (low) | layout dump: StormCloud1 (177, 115, 177) Ball; MilkyWay x 2200 | `NightSky.engineSizeOk` spec, `SkyConfig.spec` (+4), and a per-Part engine-size assertion in `check_anomalyobservatory_sky` (failed on the old build: 9 clouds + MilkyWay) | new shape `Ellipsoid` (a Block whose Sphere `SpecialMesh` fills the box, so the flattened cloud bank draws as designed and the clearance proof still measures the box); Milky Way 2000 long; `validate` refuses a non-uniform Ball, an oval Cylinder or any axis over 2048 |
| 5 | No `Sky` object, so Roblox's default (phaseless) moon could hang behind the phased one (low) | no `Sky` in the project, the place file or any source | `check_anomalyobservatory_sky` (+4) failed on the old build (`0|none`) | `Sky.client` sets one `Sky` with `CelestialBodiesShown = false` at start and never touches it again (the owner's rule: cosmetics on the client). It is the one Lighting write outside a break, the same on every pass and Day; asserted on every frame |

Two things a reader should know about how the rules were set:
* the occlusion rule was first written as "no hall object under the sky's GUI at more than 1 of 19 walk
  points" (the reviewer's desktop number). Its first run found the **permanent** break button over the
  ceiling's Fixture1 at 2/19 on a 1366x768 touch laptop (a taller tap target). A fixture crossing the top
  row for half a second of a walk is not what the finding is about, so the rule is the round 10% (at most
  2 of 19), and phones get the strict rule: no unrequested caption over the hall at all (0 points);
* one assertion was CHANGED rather than added: `check_anomalyobservatory_rest` used to require `Day 3` in
  the break caption, which was the check requiring the false promise. It now requires the opposite.

Still an owner decision (§10): making "nothing is lost" true across a disconnect means saving the streak
across sessions, a gameplay change with its own exploit (leave mid-pass, rejoin, get a fresh hall).

---

## 0. Resume session (2026-09-24)

The first build was cut off by a usage limit after the code, the specs, three headless checks and the
README / CLAUDE.md notes were written, and while its mutation sweep was being set up (its sweep
script existed; only the precheck had run). This file did not exist. The resume session:

* re-read every new and changed file (`git status` / `git diff` inside the game, the three
  `check_anomalyobservatory_*` files, the prepared sweep script);
* rebuilt the bundle to a scratch path: **byte-identical** to `robloxemu/build/anomaly-observatory.luau`
  on disk, so the checks had been testing the current code;
* ran every gate: **all green on arrival** (§7);
* ran the prepared sweep, extended with 9 mutations aimed at promises nothing had mutated yet:
  **49 mutations, 42 killed, the 3 controls survived, 4 real survivors** (§7);
* closed all four survivors with tests, each passing on the real build first and then watched
  failing on its mutant:
  * **A4** (the emitter cap bypassed) and **A7** (a meteor's trail never switched on): new
    `check_anomalyobservatory_cap.luau` and `check_anomalyobservatory_events.luau`;
  * **S16** (the moon's phase pinned to Day 1): per-Day moon assertions in `check_anomalyobservatory_sky`;
  * **S18** (a respawn does not end a break): a respawn section in `check_anomalyobservatory_rest`;
* found and closed a coverage gap no mutation had probed: the moving things (meteors, the lightning
  bolt, the turning stars) were only checked for position once per settled Day, so a 0.14 s flash
  was only seen by luck. `check_anomalyobservatory_events` watches every frame. Its five new mutations
  (E1-E5) are all killed;
* caught one defect in its OWN new check: re-running the controls against the extended suite list,
  the control that renames the star emitter was killed by `check_anomalyobservatory_cap`, which looked
  emitters up by SkyArt's internal names. It now keys them by the sky piece that hosts them
  (`StarField`, `RainHost`, the layout's keys); the control survives and the cap mutant is still
  killed (sweep 4);
* re-ran every resume-session kill and every control once more on the final check files (sweep 5).

**No game source changed in the resume session.** The only files written were this one, two new and
two extended `robloxemu/check_anomalyobservatory_*` checks, the README / CLAUDE.md notes, and
scratch files under the session scratchpad (`aor/`).

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, copied byte-for-byte from +1 Jump**: progress value → band + eased blend, frame-rate-independent glide, `capRates` (the emitter budget). Pure. |
| `src/shared/Rest.luau` | **template, copied byte-for-byte from +1 Jump**: rest rules (queued when unsafe, wake on move). Pure. |
| `src/shared/NightSky.luau` | this game's sky as pure numbers: layout of every piece, the oriented-box proof that every piece and every moving thing stays beyond the entrance, moon phase and how to draw it, meteor / lightning schedules, the break camera pose and `minRayZ` (proof that it looks away from every hall), `isReddish`, `validate`. |
| `src/shared/SkyArt.luau` | client-only: turns `NightSky.layout` into local Parts, pools and animates them, measures itself (`stats`). |
| `src/client/Sky.client.luau` | the glue: reads `leaderstats.Day`, glides the bands and the moon, runs the telescope break, the button and the caption. |
| `src/shared/Config.luau` | + `Config.Sky` (appended; nothing above it changed): the hall's geometry as the server builds it, 8 bands, every piece, the palette, `Rest`, `RestView`, `Budget`, the pacing model's profiles. |
| `tests/` | `NightSky.spec` (168), `SkyConfig.spec` (85), `Pacing.spec` (36) + `NightModel.luau` (test-side model), and the template's `EnvBands.spec` (124) and `Rest.spec` (55), copied unchanged. |
| `robloxemu/check_anomalyobservatory_sky.luau` | the sky follows the real Day; the hall never changes; same Day → same sky, clean or anomalous; geometry, colour, hygiene, Lighting, budgets; (resume) the drawn moon is each Day's phase. |
| `robloxemu/check_anomalyobservatory_rest.luau` | the telescope break changes nothing and never looks at a hall; (resume) a respawn ends a break. |
| `robloxemu/check_anomalyobservatory_hud.luau` | the HUD gate with both client scripts, 10 viewports, again during a break; the break row never overlaps the HUD. |
| `robloxemu/check_anomalyobservatory_events.luau` | **new (resume)**: every frame, every visible moving thing beyond the entrance; event rates per band; one meteor / one bolt at a time; trails; the character is never moved. |
| `robloxemu/check_anomalyobservatory_cap.luau` | **new (resume)**: the emitter budget is enforced in code (made to bind in memory). |
| `robloxemu/check_anomalyobservatory_occlusion.luau` | **new (review)**: the sky's GUI never sits on the hall during a pass (13 viewports, join and band-up walks), no blinking, news reaches the break. |
| `robloxemu/check_anomalyobservatory_shots.luau` | **new (review)**: §9's shot list, played against the real sky at 1920x1080. |

Review round (2026-09-24), in the game: `NightSky` (+ `engineSizeOk`, `breakCaption`, `bandNews`,
`introNews`, two `validate` rules, storm clouds are `Ellipsoid`), `SkyArt` (Ellipsoid = Block + Sphere
mesh), `Sky.client` (the `Sky` object, the honest caption and the idle warning, no unrequested phone
caption over the hall, a steady highlight), `Config.Sky` (`IdleKickMinutes`, Milky Way 2000 long).

Not touched: `src/server/Main.server.luau`, `src/client/Hud.client.luau`, every other shared module,
`robloxemu/emu`, the existing `check_anomaly*.luau` gates.

---

## 2. The bands and what triggers them

**Trigger: the Day, never time.** The client reads its own `leaderstats.Day`, which only the server
writes (Day + 1 on a correct call, back to Day 1 on a wrong one). It is already public (the
leaderboard shows it), so the sky reveals nothing. A band is fully up at `from` and fades in over the
`fade` Days before it, eased (EnvBands smoothstep). The sky's own clock drives only motion (meteors,
lightning, the aurora's sway, the turning stars), never which band you are in.

**Never a hard cut.** Every weight glides toward the Day's target with a 1.2 s half-life
(`GlideHalfLife`), so a band change is a glide of several seconds, and a wrong call's reset glides
the whole sky back to the first night. Measured through the real client across a climb from Day 1 to
52 and the reset: the largest one-frame transparency change of any non-flashing part is **0.019**
(the moon, during the reset; the check allows 0.03), nothing pops in visible, nothing vanishes while
visible, and after the reset the sky settles to exactly the Day-1 sky. The moon turns at most 0.012
cycles a second, so a reset turns it over for up to ~40 s instead of racing through new moon.

**Where it is.** Everything is beyond the hall's open end (hall-local z = +10, behind the spawn pad
and behind the capture rig's camera): the ridge, the moon, the comet, the storm, the nebulae and the
planets are 400-1 040 studs out, the nearest corner of any visible piece is 108 studs beyond the hall
origin (the tilted Milky Way band, high up; 60 before the review cut it to 2000 studs), and only the
rain falls close, 27-93 studs out in front of the entrance. You see it by turning round at the start
pad and looking out of the entrance, or by taking a break (§4). When a new band arrives, on a desktop
the caption says so for 6 s at the top centre (`🌠 Meteor Shower tonight — press 🔭 Break (B) to watch
it.`) and otherwise shows what is next (`Next sky: ☄️ The Great Comet on Day 15`). On a phone (any
compact layout) nothing is written over the hall: a caption there lies on the right-hand wall, where the
Mirror and the ChartWall are. Instead the break button turns a steady blue until the next break, whose
caption names the band. It never blinks ("The Flicker" is an anomaly). Measured in §7
(`check_anomalyobservatory_occlusion`).

Minutes = expected minutes of play to FIRST reach the band's Day from a fresh night, from
`tests/Pacing.spec.luau`. A wrong call resets the streak, so time grows geometrically with the Day.

| # | band | full on Day | fades in from | normal | fast | slow | what is in the sky |
|---|---|---|---|---|---|---|---|
| 1 | 🌙 Clear Night | 1 | — | 0.0 min | 0.0 | 0.0 | the place: a ridge line on the horizon, mist in the valley and ten far valley lights; the moon, a thin waxing crescent on Day 1; stars at 55 % |
| 2 | 🌠 Meteor Shower | 4 | 2 | 0.9 | 0.6 | 1.5 | + meteors with trails, stars 70 % |
| 3 | 🌌 Aurora | 9 | 7 | 2.7 | 1.6 | 5.5 | + four swaying aurora curtains (green, teal, violet) over the ridge; meteors 30 % |
| 4 | ☄️ The Great Comet | 15 | 12 | 6.1 | 3.1 | 16.5 | + a comet: head, coma and a long two-beam tail; aurora 35 %, meteors 20 %; the moon is full around Day 14 |
| 5 | ⛈️ Storm Front | 22 | 19 | 13.3 | 5.3 | 55.5 | a dark cloud bank low on the horizon, silent lightning inside it, rain falling just outside the entrance; stars 25 %, moon 35 %, the comet fading at 30 % |
| 6 | 🔭 **Deep Sky** (headline) | **31** | 28 | **34.1** | 9.1 | 287.3 | nebula clouds, the Milky Way band, a distant galaxy with a bright core; every star; the moon near new (a thin crescent at 60 %), so the sky is dark |
| 7 | 🪐 The Alignment | 40 | 36 | 86.9 | 14.8 | 1 639 | the five naked-eye planets in one line across the sky (Saturn ringed), the moon full around Day 44; nebulae 40 %, aurora 20 % |
| 8 | 👁️ The Other Sky | 50 | 45 | 238.3 | 23.8 | 11 336 | a second, pale-green moon, a vast pale ring across the zenith, a spiral of stars that turns once every 3 minutes; echoes of the earlier skies |

**The moon** follows the Day on a 29.5-Day cycle: a crescent on Day 1 that waxes with the streak,
full around Day 14, new around Day 29 (dark for Deep Sky), full again around Day 44. The phase is drawn
by sliding a dark disc across a lit one, with the lit fraction exactly right (the offset is the
inverse of the lens-area formula, `NightSky.luneOffset`); near full the disc fades away, near new the
moon fades out, so a phase never pops.

**Pacing model** (`tests/NightModel.luau`, assumptions in `Config.Sky.Pacing.Profiles`). No telemetry
exists, so time-to-Day is a model built on the game's own roll (`Anomaly.chance`, `Anomaly.poolSize`,
the real catalog): a pass takes `passSeconds` (normal 16 s: walk the 80-stud hall, look, decide); a
clean hall is answered right with `1 - falseAlarm` (normal 3 % false alarms); an anomaly is spotted
with `spotObvious` (96 %) for the Day-1 pool and `spotSubtle` (82 %) for the rest; a wrong call costs
the 2.5 s death beat plus reading the toast and restarts at Day 1. The closed form agrees with a
4 000-run simulation within 6 %. Asserted: a normal player sees the second sky within 2 minutes and
the headline in 30-45 min (34.1) and within 5 min of the window's centre; each band takes 1.8-4× as
long to first reach as the one before; the last sky is at least twice the headline and a skilled
player can get there in about an evening (23.8 min fast). **When real session data exists, retune
`Profiles.normal` first, then the `from` Days.** A slow player (6 % false alarms, 68 % on subtle
anomalies) takes 55 min to the storm and hours beyond it; that is the nature of a streak that a
single miss resets (§10).

---

## 3. Hazards and their measured rarity

**There are none, by design.** Nothing chases you and nothing knocks you down; the tension is pure
observation. Nothing the sky builds is collidable, touchable or ray-queryable, and
`check_anomalyobservatory_events` asserts the character's CFrame never changes while only the sky
runs (20 simulated minutes, 36 000 frames, across four bands).

The only things that move are cosmetic sky events, far beyond the entrance. Their frequency is the
"rarity" that matters here: subtle, atmospheric, never busy. Measured through the real client, 5
simulated minutes at each Day, Days reached by answering real passes (`check_anomalyobservatory_events`):

| Day | band | meteors / min (Config) | lightning flashes / min (Config) | turning stars |
|---|---|---|---|---|
| 1 | Clear Night | **0.0** (0) | **0.0** (0) | none |
| 6 | Meteor Shower | **13.4** (13.5) | 0.0 (0) | none |
| 25 | Storm Front | 0.0 (0) | **11.4** (11.5) | none |
| 52 | The Other Sky | **4.2** (4.0) | 0.0 (0) | on every frame |

Other bands, from the same formula (`60 / SlotSeconds × Chance × weight`): Aurora 4.0, Comet 2.7,
Deep Sky 2.0, Alignment 2.0 meteors a minute. A meteor lasts 0.8 s (limit 25 frames at 30 fps,
measured longest 24), a flash 0.14 s (limit 6 frames, measured longest 5). Never more than one meteor and one bolt at a
time (each event starts and ends inside its own time slot). A meteor draws its trail on every frame
it flies and switches it off when it lands. On every one of those frames every visible moving part
was at least **392.8 studs** beyond the hall origin; the entrance plane is at 10 and the required
clearance ends at 16. Lightning is silent Neon: the sky owns no Light, so a flash can never flicker
the hall ("The Flicker" is an anomaly).

---

## 4. Rest — what "pause" means here: the telescope break

A Roblox server cannot pause the world, and **this game has nothing to pause**: there is no clock
inside a pass (the server's `MIN_PASS_SECONDS` = 0.75 s is a floor against bots, not a timer), no
chaser, no hazard, no raid. Standing still anywhere is already completely safe. What a tired player
needs is a moment away from the tension, so rest is **🔭 Break**:

* press **B** or the break button (top centre on a desktop, right edge ~42 % down on a phone, under the
  HUD's drawers). The screen fades to black for 0.3 s and the camera steps out to the telescope: 54
  studs beyond the entrance, above the roof line, looking up at this Day's sky, panning slowly
  (±6° of yaw over 80 s, ±3° of pitch over ~2 min). The haze thins and the view is graded a little brighter while you
  are out. The caption says `☕ On a break: your hall is waiting, exactly as you left it. Move or
  press ▶ to go back.` (phone: `☕ Break · your hall waits. Move to go back.`), led by any news since the
  last break: a new band (`🌠 Meteor Shower tonight.`), or on a phone's first break the join tip. It never
  says the Day is "safe" (review 2026-09-24): it is not, see below;
* once Roblox reports the player idle (`Player.Idled`, about 2 minutes without any input), the caption
  becomes `☕ Still there? Roblox disconnects players idle for 20 minutes, and a new session starts at
  Day 1 (you are on Day N). Move or press ▶ to go back.` (phone: `☕ Idle 20 min = disconnect, back to
  Day 1. Move!`). Any input clears it; a mouse move does not end the break, moving the character does;
* **move, jump, press B or the button again** and it fades back, with the camera, Lighting and field
  of view exactly as they were;
* a break asked for in mid-air, or during the 3 s death beat after a wrong call, is queued
  (`☕ Break queued: it starts when this moment is over. Keep still.`) and starts the first moment you
  stand still on the floor; walking on drops it; it expires after 4 s;
* a wrong call's death beat, or a respawn, ends a break in progress.

**Why it cannot be exploited**

1. **There is nothing to dodge.** No clock, raid, timer, penalty or leaderboard rule depends on time
   spent. The only thing that ends a streak is a wrong call, which the player makes; the board ranks
   best Day. A break does not pause, delay, re-roll or protect anything, and the server is never told:
   it fires no remote. Measured (`check_anomalyobservatory_rest`): after a **10-minute break** the
   pass is the same pass (same `Serial`, same roll, same anomaly id), every BasePart of the hall is
   exactly as it was, the Day and the character are untouched, and the pass is then answered and
   scored normally, followed by the next serial.
2. **It cannot be used to look at the hall.** The break camera is beyond the entrance plane and every
   ray of its view frustum heads away from the halls (+Z). `NightSky.validate` refuses a config whose
   worst ray is not at least 0.05 outward at FOV 70 on screens up to 3.6:1, and the check measures it
   on every frame out, on 16:9, a 32:9 ultrawide and a portrait phone: worst **0.249**. The hall is
   sealed everywhere except that entrance, so no hall is visible from out there, and the camera is
   scripted (the player cannot turn it).
3. **It cannot show the hall differently.** Lighting is written only while the camera is out, the
   camera leaves and returns only on a fully black frame, and Lighting is restored before it returns.
   Measured on every frame: Lighting differs from the server's Horror preset only while the camera is
   out, the break grade is never on in the hall, and the camera is never scripted anywhere but out.
4. **It is not a panic button**, though there is nothing to panic about: it cannot start during the
   death beat (it queues; measured: the camera never leaves during the beat), and the beat ends a
   break in progress.
5. **It does not fight another camera owner.** With the camera scripted by someone else (a cutscene,
   the capture rig) the break refuses (`Not right now: the camera is busy.`) and changes nothing. Its
   ScreenGui never re-enables itself, so the rig's "every gui off" holds through a band change.
6. **No idle rest.** `Rest.IdleSeconds` is 0 and `NightSky.validate` requires it: an idle timer would
   only take the camera away from a player who stopped to look at the hall.

What a break does NOT change: Roblox's own idle disconnect (about 20 minutes without input) still
applies. The Day streak is per-session by the game's existing design (Best Day is saved), so a
player who idles 20 minutes on a break loses the session and with it the streak. The break did not
cause that and cannot prevent it, so it says so instead of promising otherwise: the first version's
caption (`Day N is safe`) was the review's first finding. Making "nothing is lost" true across a
disconnect is an owner decision (§10).

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| bands, moon, every sky piece, meteors, lightning, rain, turning stars, the break, the button and caption | **client** (`Sky.client` + `SkyArt`, pure `NightSky` / `EnvBands` / `Rest`) | cosmetic and per-player (your sky follows *your* Day); costs the server nothing and replicates nothing |
| the Day, the pass, the roll, the hall, scoring, saves, the leaderboard | **server** (unchanged) | authoritative, as before |

**Leak review.** The client reads its own `leaderstats.Day`, its own zone's `Index` attribute (to
know where its hall is), its own camera and humanoid, its own player's `Idled` event and the input
events (for the idle warning), the HUD's own drawers (read-only, to step
aside on a phone), `Config` (already replicated), and the server's existing `Death` remote (to know a
death beat is running). It reads **nothing about the pass**: no `PassInfo` (which is in ServerStorage
and does not replicate anyway), no zone contents, no `Anomaly` module. The sky check asserts that the
client sources never mention `PassInfo`, `ServerStorage`, `AnomalyId`, `FireServer`, `InvokeServer` or
any Light class; that the client fires no remote; that no attribute carrying the roll is visible in
`workspace` or `ReplicatedStorage` with the sky running; and that **a clean and an anomalous pass of the
same Day get an identical settled sky** (two climbs compared Day by Day, 18 Days; the server's roll
is salted per session, so the number of clean-vs-anomalous pairs varies: 6-10 per run in this
session, and the check requires at least 2). A deliberate leak mutant (the sky reacting to the hall's
descendant count, S19) is killed by that comparison.

**Why nothing leaks into the hall, or into the capture rig.** The hall is a sealed box open only at
its +Z end. The sky lives beyond that plane with 6 studs to spare, proved for exact oriented corners
of every piece in `SkyConfig.spec`, and measured on the real Parts at every Day and on every frame for
the moving ones. `tools/film_anomaly.py` photographs from hall-local z = +4 looking down the hall
(-Z), so the whole sky is behind its lens, and it pairs clean and anomalous frames from DIFFERENT
Days, which is exactly why nothing in its crop may depend on the Day. The hall's Mirror reflects only
the skybox. Outside a break the sky writes Lighting exactly once, at start, and never again: it adds a
`Sky` object (`ObservatorySkybox`) with `CelestialBodiesShown = false`, because without one Roblox draws
its default night sky, whose own moon has no phases and would hang behind the phased moon (review
finding 5). It is the same on every pass and every Day, so the Mirror cannot tell a clean pass from an
anomalous one by it; `check_anomalyobservatory_sky` asserts on every frame that there is exactly one
`Sky`, with no celestial bodies, unchanged, and that the rest of Lighting is the server's preset. The
sky uses no reddish colour (`NightSky.isReddish`), because "Red Shift" and "Blood Moon" are anomalies
and the sky must not teach the player that red is normal.

Spawn order (`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame,
and `check_anomaly_spawn` is green.

---

## 6. Budgets (measured, `check_anomalyobservatory_sky`)

Client-built only; the server builds none of it. Measured after every Day from 1 to 52 settled, and on
every one of 28 146 frames including every band change and the reset.

| Days | band | parts | emitters (particles/s) | beams | trails (in flight) | lights |
|---|---|---|---|---|---|---|
| 1-2 | Clear Night | 26 | 1 (5.5) | 0 | 0 | 0 |
| 3 | › Meteor Shower | 28 | 1 (6.2) | 0 | 0 | 0 |
| 4-7 | Meteor Shower | 28 | 1 (7.0) | 0 | 0-1 | 0 |
| 8 | › Aurora | 29 | 1 (7.0) | 4 | 0-1 | 0 |
| 9-12 | Aurora | 29 | 1 (7.0) | 4 | 0-1 | 0 |
| 13-14 | › Comet | 31 | 1 (7.3-7.7) | 6 | 0-1 | 0 |
| 15-19 | The Great Comet | 31 | 1 (8.0) | 6 | 0-1 | 0 |
| 20-21 | › Storm Front | 44 | 2 (16.9-33.6) | 6 | 0 | 0 |
| 22-28 | Storm Front | 41 | 2 (**42.5**) | 2 | 0 | 0 |
| 29-30 | › Deep Sky | 52 | 2 (34.1 / 18.4) | 2 | 0 | 0 |
| 31-36 | Deep Sky | 37 | 1 (10.0) | 0 | 0-1 | 0 |
| 37-39 | › Alignment | 44 | 1 (10.0) | 4 | 0-1 | 0 |
| 40-45 | The Alignment | 44 | 1 (10.0) | 4 | 0-1 | 0 |
| 46-49 | › Other Sky | **87** | 1 (10.0) | 4 | 0-1 | 0 |
| 50+ | The Other Sky | **87** | 1 (10.0) | 4 | 0-1 | 0 |

| metric | measured peak | budget (`Config.Sky.Budget`) |
|---|---|---|
| local parts | **87** (The Other Sky: 18 ring segments, 24 turning stars, a second moon) | 140 |
| particle emitters on | 2 (stars + rain, storm) | 2 |
| particles per second | **42.5** (rain 40 + stars 2.5, storm) | 60 |
| beams | 6 (aurora 4 + comet tail 2) | 8 |
| trails | 1 (a meteor in flight) | 4 |
| lights | **0**, always | 0 (validate refuses anything else) |
| hazards at once | 0 (there are none) | — |

The whole layout is 102 parts if every feature were on at once, which no Day produces;
`SkyConfig.spec` asserts it still fits the budget. A break adds one `ColorCorrectionEffect` on the
camera and no parts. The nine storm clouds each carry one `SpecialMesh` (Sphere), which is not a Part;
the budget numbers above did not move with the review fix.

**Sizes the engine draws as written (review finding 4).** robloxemu keeps any size; Roblox forces a
`Ball` uniform, draws a `Cylinder` round (Y = Z) and clamps every Part axis to 2048 studs. `validate`
refuses a layout that breaks any of these (`NightSky.engineSizeOk`), and the sky check measures every
built Part against them. A flattened sphere is an `Ellipsoid`: a Block with a Sphere mesh that fills it.

**The emitter cap is enforced in code, not only by the numbers.** SkyArt switches emitters on through
the template's `EnvBands.capRates` (at most `MaxEmitters`, the strongest first, summed rate scaled
under `MaxEmitterRate`). With the shipped numbers (stars 10/s, rain 40/s) the cap cannot bind, so a
mutant that bypassed it survived the first sweep. `check_anomalyobservatory_cap` makes it bind (a
budget of one emitter at 30/s, in memory, this run only) and plays through the Storm Front: on every
one of 1 965 frames at most one emitter is on and the rate is at most 30/s; the one kept is the rain,
scaled to 30/s, the stars step aside, and come back after a reset.

**What is pooled / how it stays cheap:** each feature's parts are built the first time it shows and
**unparented, not destroyed,** when its weight reaches zero (a band you are not in costs no draw
calls; a mutant that kept them parented is killed); the meteors are a pool of 2 parts that alternate
by time slot; lightning is one three-segment bolt; the aurora is 4 Beams on one invisible host; the
comet's tail is 2 Beams on its head; the stars and the rain are one emitter each. Writes are skipped
when a value has not changed, so a settled sky costs a handful of writes a frame: the aurora's sway
(2 curve sizes per curtain) and The Other Sky's 24 turning stars at 10 Hz, plus whatever meteor or
bolt is in flight. The glide writes at most one transparency per part per frame, and only changes
over 0.004 until it settles. These are part and emitter counts, not frame rate; frame time on a
phone is on the Studio list.

---

## 7. Gates

Every gate for this game, run on the final tree (bundle rebuilt from it). "Before the sky" = `HEAD`'s
game sources in a scratch copy with the same checks and emulator.

| gate | before the sky | on arrival (resume) | end of resume | **after the review round (final)** |
|---|---|---|---|---|
| `tests/Anomaly.spec` | 36 / 0 | 36 / 0 | 36 / 0 | 36 / 0 |
| `tests/Codes.spec` | 10 / 0 | 10 / 0 | 10 / 0 | 10 / 0 |
| `tests/Codex.spec` | 26 / 0 | 26 / 0 | 26 / 0 | 26 / 0 |
| `tests/Progression.spec` | 22 / 0 | 22 / 0 | 22 / 0 | 22 / 0 |
| `tests/Rng.spec` | 32 / 0 | 32 / 0 | 32 / 0 | 32 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/EnvBands.spec` | — | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/NightSky.spec` | — | 168 / 0 | 168 / 0 | **194 / 0** (+ engine sizes, the break's words) |
| `tests/SkyConfig.spec` | — | 85 / 0 | 85 / 0 | **89 / 0** (+ engine sizes) |
| `tests/Rest.spec` | — | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Pacing.spec` | — | 36 / 0 | 36 / 0 | 36 / 0 |
| **spec total** | **196 / 0** | **664 / 0** | **664 / 0** | **694 / 0** |
| `robloxemu/check_anomaly` (HUD fit, overlap on) | PASS | PASS | PASS | PASS |
| `robloxemu/check_anomaly_attrs` | 323 / 0 | 322 / 0 | 324 / 0 | 326, 329, 318 / 0 (three runs; varies, see below) |
| `robloxemu/check_anomaly_spawn` | 11 / 0 | 11 / 0 | 11 / 0 | 11 / 0 |
| `robloxemu/check_anomalyobservatory_sky` | — | 72 / 0 | 74 / 0 | **78 / 0** (+ engine sizes, the Sky object) |
| `robloxemu/check_anomalyobservatory_rest` | — | 56 / 0 | 59 / 0 | **67 / 0** (+ the caption and the idle warning) |
| `robloxemu/check_anomalyobservatory_hud` | — | 26 / 0 + PASS | 26 / 0 + PASS | 26 / 0 + PASS |
| `robloxemu/check_anomalyobservatory_events` | — | — | 24 / 0 | 24 / 0 |
| `robloxemu/check_anomalyobservatory_cap` | — | — | 12 / 0 | 12 / 0 |
| `robloxemu/check_anomalyobservatory_occlusion` | — | — | — | **80 / 0** (new) |
| `robloxemu/check_anomalyobservatory_shots` | — | — | — | **48 / 0** (new) |
| syntax (every source, test and check, compiled with `loadstring`) | — | — | 36 files clean | **38 files clean** |

`check_anomaly_attrs` prints a slightly different count each run (319, 322, 323, 324 in this
session), always 0 failed: the server takes a per-session salt from a real random source, so the roll
sequence differs per run (`robloxemu/SPAWN-ORDER.md` §4 records the same). The sky, rest, events and
cap checks answer each pass by reading the server's roll, so they are robust to it; their counts do
not move. **Stability:** after the final build, `check_anomaly_attrs` and all five
`check_anomalyobservatory_*` checks were run 3 times each: green every time, identical counts (the
sky check's clean-pass and clean-vs-anomalous-pair tallies vary with the roll, 23-35 and 6-10).

**Review round, final.** Bundle md5 `17bd7dd3…`, byte-equal (paths aside) to a fresh build of the
final sources. Every gate above was run three times on it: green every time, identical counts except
`check_anomaly_attrs` (per-session salt). The occlusion check measured, on the pass after a band
change: every phone and compact layout (640x300, 800x360 touch and mouse, 844x390, 414x800 portrait,
800x600 mouse) **0 of 19** walk points covered and no caption at all; desktop-class layouts only
Fixture1 crossing the top-centre row, at 1/19 (2/19 on the 1366x768 touch laptop, whose tap target
is taller); the break button changed colour at most once. The shots check's measurements are the
numbers in §9.

**Static analysis.** Only `luau.exe` is available in this session: no `luau-compile` and no
`luau-analyze`. The syntax gate above stands in for `luau-compile` (a deliberately broken line was
used to confirm it reports errors). `luau-analyze` was not run on the new modules; that is open (§10).

**Mutation sweeps** (session scratchpad, `aor/sweep.py`, `sweep_events.py`, `sweep3.py`, `sweep4.py`,
`sweep5.py`; logs `aor/sweep*.log`, per-suite results in `aor/sweep_results.json` and
`aor/ev*/sweep_results.json`). For every mutation,
on a fresh scratch copy of the game and the emulator (the real tree is never mutated): md5 of the
target recorded; exactly one occurrence replaced; bundle rebuilt and **proved to contain the
mutation** (the mutated bundle equals the baseline bundle with the same single replacement); every
suite run; original bytes restored and md5 re-checked; the bundle checked back to baseline at the end.
A suite that exits non-zero, times out or prints no summary counts as a kill.

* **Sweep 1** (the first build's 40 mutations + 9 new, 11 specs + the 6 checks of the time):
  **49 mutations, 42 killed**; CONTROL-1 (valley lights a shade yellower), CONTROL-2 (the star emitter
  renamed) and CONTROL-3 (a caption's spelling) **survived, as they must**. Four real survivors:
  A4 emitter cap bypassed; A7 meteor trail never switched on; S16 moon phase pinned to Day 1; S18 a
  respawn does not end a break.
* **Sweep 2** (8 mutations, all 19 suites incl. the two new checks): **7 killed, the control
  survived.** E1 a meteor in flight drawn 20 studs from the eye, E2 a bolt reaching 15 studs from the
  eye, E3 a flash four times its Duration, E4 meteor rate ignoring the band weight, E5 the turning
  stars swinging out over time (unchanged at t = 0, so `validate` cannot see it), and the re-runs of
  **A4 (now killed by `_cap`)** and **A7 (now killed by `_events`)**. CONTROL-4 (meteors a tenth of a
  stud fatter) survived.
* **Sweep 3** (all 19 suites): **S16 KILLED** by the sky check's moon assertions, **S18 KILLED** by
  the rest check's respawn section. The four controls re-run against the extended suite list:
  CONTROL-1, 3 and 4 survived, but **CONTROL-2 (the star emitter renamed) was KILLED by the new cap
  check**, which looked emitters up by SkyArt's internal names. That was a defect in the check, not
  in the game: it now keys emitters by the sky piece that hosts them (`StarField`, `RainHost`).
* **Sweep 4** (all 19 suites): CONTROL-2 **survived**, A4 still **KILLED** by the cap check.
* **Sweep 5** (all 19 suites, on the final check files): S16, S18, A4, A7, E1, E5 **all KILLED**;
  CONTROL-1..4 **all survived**. After every sweep the bundle was back to its baseline, and the real
  bundle's md5 is the same as when the session began (`87101699…`): no source changed.

What kills what, in short: geometry and hygiene mutants die in `SkyConfig.spec` / `NightSky.spec` and
the sky check; the glide / pop / band / leak mutants in the sky check; break mutants (camera,
Lighting, grade, black-frame swap, death beat, grounded, gui) in the rest check; layout mutants on a
phone in the hud check; motion mutants in the events check; the cap mutant in the cap check.

**Review-round sweep** (session scratchpad `aoz/sweep.py`, log `aoz/sweep1.log`, per-suite results
`aoz/sweep_results.json`; same method as above, all 21 suites per mutation, three mutations at a time):
**23 mutations, 23 killed; 5 controls, 5 survived.** Every mutation proved present in its rebuilt
bundle, every source restored to its md5, every bundle back to baseline, the real tree untouched.

| id | mutation | killed by |
|---|---|---|
| M1a | the desktop break caption says "your Day is safe" again | `NightSky.spec`, rest |
| M1b | `Player.Idled` never sets idle | rest |
| M1c | a mouse move no longer clears the idle warning | rest |
| M1d | the phone's idle warning drops "back to Day 1" | `NightSky.spec` |
| M1e | `validate` no longer requires `IdleKickMinutes` | `NightSky.spec` |
| M1f | the client never passes `idle` to the caption | rest |
| M3a | the band-up caption shown over the hall on a phone again | occlusion |
| M3b | the join tip shown over the hall on a phone again | occlusion |
| M3c | the highlight blinks at 2 Hz again | occlusion |
| M3d | the break forgets the news | occlusion |
| M3e | a reset keeps announcing a band the sky no longer shows | occlusion |
| M4a | storm clouds back to non-uniform `Ball` | `SkyConfig.spec` (and every client check: `validate` turns the sky off) |
| M4b | Milky Way back to 2200 studs | `SkyConfig.spec` (same) |
| M4c | Ellipsoids built without their mesh | sky |
| M4d | `engineSizeOk` stops checking Balls | `NightSky.spec` |
| M4e | `engineSizeOk` allows 4096 studs | `NightSky.spec` |
| M4f | the ellipsoid mesh is a Brick, not a Sphere | sky |
| M5a | the client's Sky shows the celestial bodies | sky |
| M5b | the client's Sky is never parented | sky, rest |
| M2a | the comet moved to azimuth -20 | shots |
| M2b | the break pan turns the other way | shots |
| M2c | the moon's dark disc on the lit side | shots, sky |
| M2d | Mercury moved to azimuth +40 | shots |
| C1-C5 | caption wording "go back" → "return"; the highlight colour a shade lighter; the mesh renamed; the Sky object renamed; the desktop intro reworded | **survived, as they must** |

**TDD order, honestly.** The pure modules' specs were written by the first build and cannot be
re-watched failing now. In the resume session every new assertion was necessarily written against
code that was already right: it passed on the real build first, then was watched failing on its
mutant for the stated reason (not a crash), which is the only honest order a test gap allows.
In the review round the order was the real one: every new assertion was written before its fix and
watched failing on the unfixed build for the reviewer's reason (scratchpad logs `aoz/occl_before_fix.log`
35 failures, `aoz/shots_builder_list.log` 13, `aoz/sky_prefix.log` 2, `aoz/rest_prefix.log` 5; the two
specs failed on the missing functions and on `validate` accepting the bad configs), then the game was
fixed. The shot list is the exception by nature: its "fix" is the list itself, so the check was run on
the list as written (13 failures), and the rewritten list is the measurements.

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Can you see it at all from the doorway?** The server's Horror preset keeps an Atmosphere
   (density 0.42, haze 1.6). The sky is mostly Neon at 400-1 040 studs; outside a break it may be swallowed.
   The break thins it to 0.2 / 0.6. If the doorway view is empty, the knob is distance (closer and
   smaller), not Lighting: the sky must not write Lighting in the hall.
2. **Planets and ridges are SmoothPlastic** at ClockTime 0.2 with a dark ambient: the ridges should be
   dark silhouettes (is the sky behind them lighter?), but the planets may simply be black. If so,
   make the planets Neon (`material` in `NightSky.layout`; colours are already non-red).
3. **The moon's dark disc.** Near a crescent the shade overhangs the moon on one side; against a
   hazy sky it may read as a black disc beside the moon rather than as the moon's dark side.
4. **Stars**: a 10/s emitter on a 1 500 × 700 slab at 820 studs, particles 2.2 studs: enough, too few,
   do they twinkle.
5. **Aurora and comet Beams** (`FaceCamera`, curved, 90-150 studs wide): curtains or flat ribbons;
   the sway period 23 s.
6. **Storm**: do nine dark flattened ellipsoids (Blocks with a Sphere `SpecialMesh`, since the review)
   read as a low cloud bank; does the mesh take the part's SmoothPlastic colour and 0.12 transparency as
   expected; lightning Neon + Bloom (threshold 1.1): flash
   too strong or too weak; is 11 flashes a minute busy. Rain: `VelocityParallel` + Squash streaks at
   40/s, seen from the doorway and from the break camera (which is inside the rain column).
7. **Nebulae and the Milky Way**: Neon balls at 0.86-0.93 transparency with Bloom: glow or wash. The
   Milky Way is now 2000 studs long (Roblox's Part limit is 2048): does it still span the top of shot 4.
8. **The Other Sky**: do 18 block segments read as one ring; is the spiral's turn (3 min) noticeable.
9. **Mobile**: lower graphics levels may cull parts 600-950 studs out; frame time with the densest
   sky (87 parts, The Other Sky) on a mid/low phone.
10. **The break**: 0.3 s fades; the slow pan; the grade on the camera; whether Roblox's camera module
    takes the restored CameraType / CFrame without a jump; whether the Lighting DepthOfField
    (FarIntensity 0.08) blurs the sky.
11. **Nothing in the Mirror or the Window.** `Reflectance` shows the skybox only, so the sky's Parts
    should never appear in the Mirror; confirm by eye.
12. **The hall pixel test** (the strongest proof there is): with `tools/film_anomaly.py`, shoot two
    CLEAN passes at very different Days (e.g. Day 1 and Day 33) and diff them; the difference must
    be no larger than two clean passes of the same Day.
13. **The phone button** (right edge, ~42 % down) under a real thumb, next to the jump button and the
    HUD's drawers; emoji in the button (`🌙 🔭`) and caption on a phone.
14. **The band caption (desktop) and the steady highlight (every layout)**: inviting, or a distraction
    in a game about concentration. On a phone, is a steady blue button enough of an invitation for the
    first break (the join tip is on that break now, not over the hall).
15. **No second moon** (review finding 5): with the client's `ObservatorySkybox` (`CelestialBodiesShown
    = false`) Roblox's own moon and sun must be gone, and the skybox and its stars otherwise unchanged.
    Look at the doorway and the break view on Day 29 (new moon): the sky must have no moon at all.
16. **The idle warning** (review finding 1) on a real client: take a break and leave the mouse alone;
    after about 2 minutes `Player.Idled` should fire and the caption turn into the 20-minute warning; a
    mouse move should clear it without ending the break. (The emulator fires `Idled` by hand; how often
    Roblox repeats it does not matter, the warning stays until input.)
17. **The occlusion walk** (review finding 3), by eye on a small phone: after a band change nothing of
    the sky's GUI but the button is over the hall, and the Mirror and ChartWall are clear.

---

## 9. Thumbnail shot list (the night Studio session)

**Rewritten in the review round (2026-09-24), and now checked.** The first list had every left and
right mirrored and parked the hero shot's avatar off the bottom-left of its own frame. The cause: looking
out of the entrance (+Z), Roblox's camera has **+X on its LEFT**, so everything the config places at a
positive azimuth (the comet, the nebulae, Saturn, the second moon) lands on the left of the photograph,
and the moon (azimuth -24°) on the right. `robloxemu/check_anomalyobservatory_shots.luau` now plays this
list against the real sky at 1920x1080 (48 assertions): the Days in this order with this wait, each
camera as written, every callout in the frame, visible and on the side stated (sx -1 left edge .. +1
right edge, sy -1 bottom .. +1 top, the numbers in the table are its measurements), the moon's phase
words and lit side, the avatar and the doorway, and the pan note. A camera INSIDE the hall counts only
what it sees through the doorway. **Its `SHOTS` table is this table as data: edit both or neither.**

**Before the first shot**

1. **Build a fresh place file**: `rojo build -o Anomaly.rbxlx` from `anomaly-observatory/`. The
   `Anomaly.rbxlx` on disk (2026-09-17) predates the sky, and its `.lock` file says a Studio session
   had it open: close that session first.
2. Pin render quality to the maximum before pressing Play (as `tools/film_anomaly.py` does:
   Automatic drops Bloom whenever Studio is not the focused window, and every one of these shots is
   Neon + Bloom).
3. Play Solo. Your hall is index 1, origin **O = (1000, 100, 0)**; confirm with
   `workspace["Concourse_" .. game.Players.LocalPlayer.UserId]:GetAttribute("Index")`. All positions
   below are hall-local offsets from O (the hall runs toward -Z; the open entrance is at z = +10).
4. Hide every ScreenGui (the capture rig's `HUD_OFF` snippet) and Roblox's own UI (client command
   bar: `game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`, which also hides the player
   list showing the Day). The sky's own gui never switches itself back on. **B still works with the
   guis hidden.**
5. **Setting the Day for a shot**: in the command bar in *Server* mode,
   `game.Players:GetPlayers()[1].leaderstats.Day.Value = N`. Only the sky reads it (the HUD takes
   its Day from the server's own state push; the Roblox player list shows it, see step 4); the
   server's streak is unchanged, so **do not answer a pass** during the session (the next answer would
   set the Day back to the real streak). Shoot the Days in the order below and **wait 45 s after each
   change** (measured: in this order the sky has settled by then; nothing changes in 30 s more).
6. **Break-view shots**: stand still on the floor, press **B**, keep hands off WASD (moving ends the
   break), capture about 1 s after pressing: the pan is then centred (yaw ≈ 0°, pitch ≈ 17°). A capture
   **20 s in** shows the view turned about 6° to the **left** and 2.7° higher, so everything drifts right
   and down (Mercury from sx +0.74 to +0.90). B again to come back.
7. **Custom-camera shots**, client command bar (FROM and AT from the table):
   ```lua
   local O = Vector3.new(1000, 100, 0)
   local c = workspace.CurrentCamera
   c.CameraType = Enum.CameraType.Scriptable
   c.FieldOfView = 70
   c.CFrame = CFrame.lookAt(O + Vector3.new(FROM), O + Vector3.new(AT))
   ```
   Give the camera back afterwards with `workspace.CurrentCamera.CameraType = Enum.CameraType.Custom`:
   a break refuses to start while another script owns the camera.
8. **Shot 1's caretaker**, client command bar (stands the avatar in the doorway, 1.5 studs inside the
   entrance, facing out); afterwards `r.Anchored = false`:
   ```lua
   local O = Vector3.new(1000, 100, 0)
   local r = game.Players.LocalPlayer.Character.HumanoidRootPart
   r.Anchored = true
   r.CFrame = CFrame.lookAt(O + Vector3.new(-5.5, 3.5, 8.5), O + Vector3.new(-90, 3.5, 700))
   ```

| # | shot | Day | camera | must be in frame (measured headless) |
|---|---|---|---|---|
| 1 | **The caretaker at the door** (hero) | 10 | custom, FROM `2, 5.5, -2` AT `-12, 21, 96` (inside the hall, 12 studs back from the entrance); the caretaker parked (step 8) | the **whole doorway** (both walls, the floor edge and the ceiling edge) framing the night; the caretaker standing in it, whole, in the **lower-right third** (centre sx +0.44, sy -0.54; about 40% of the frame's height), looking out; the **waxing gibbous moon upper right** (sx +0.21, sy +0.49), lit on its right; two aurora curtains near the centre over the ridge line (six ridges in the lower third); the valley lights low in the frame. Only the hall's last 12 studs are in frame and no anomaly lives there (the nearest objects, Fixture1, the StartPad and the Plant, are behind the lens), so any pass will do. |
| 2 | **The Great Comet** | 17 | break view (B) | the comet's head and coma **upper left** (sx -0.28, sy +0.44), its tail sweeping further **left**; the **waning gibbous moon upper right** (sx +0.36, sy +0.35), lit on its left; ridge silhouettes along the bottom third |
| 3 | **Storm Front** | 25 | custom, FROM `6, 4, 16` AT `-20, 11, 112` (just outside the entrance) | the dark cloud bank **across the middle** of the frame (all nine clouds; centre sx +0.02, sy -0.05), rain streaks falling through the foreground (the rain falls 14-74 studs in front of this camera), and a lightning bolt inside the bank. A flash lasts 0.14 s, so **record a minute and take the frame from the clip**: the headless minute had 13 flashes, every one wholly in frame. (The old `require(Config)` trick is dropped: the command bar can get its own copy of the module, so it may do nothing.) |
| 4 | **Deep Sky** (the headline, ~34 min in) | 33 | break view (B) | the nebula clouds **upper left** (centre sx -0.37, sy +0.56); the Milky Way band tilted across the top (sx +0.13, sy +0.85); the distant galaxy **upper right** (sx +0.49, sy +0.87); the **waxing crescent moon upper right** (sx +0.36, sy +0.35); a full star field; the ridge line along the bottom third |
| 5 | **The Alignment** | 44 | break view (B) | the five planets on one diagonal, from **Mercury lower right** (sx +0.74, sy -0.07) through Venus (right of centre), Mars and Jupiter (centre) to **ringed Saturn upper left** (sx -0.45, sy +0.41); the **full moon directly above Venus**; faint nebulae |
| 6 | **The Other Sky** | 52 | custom, FROM `0, 10, 20` AT `0, 84, 87` (straight out, 48° up) | the vast pale ring across the upper half (all 18 segments in frame); the pale-green **second moon left of centre** (sx -0.29, sy -0.10); the **turning spiral of stars right of centre** (sx +0.19); the waning crescent moon lower right (sx +0.34, sy -0.47); no ridge, no hall. Eerie and empty on purpose |

If shot 1 or 6 comes out empty because of the haze (§8 item 1), shoot it again with the break's
values set by hand for the session (`Lighting.FxAtmosphere.Density = 0.2; Haze = 0.6`), and say so in
the shot's file name. Do not leave that change in the place file. If a second, phaseless moon shows up
anywhere, stop: §8 item 15 has failed.

For clips rather than stills: the aurora's sway (23 s), the turning spiral (3 min a turn), the
meteor shower (Day 6, a meteor every ~4.5 s) and a band change (set the Day from 21 to 22 while on a
break and watch the storm roll in over ~11 s).

---

## 10. Still open / owner decisions

* **Reviewed once; the review-round fixes have not had a second review.** One independent review
  (2026-09-24) found five defects, all closed (§0b). The fixes are covered by new failing-first tests
  and a mutation sweep with controls (§7), not by a second pair of eyes.
* **`luau-analyze` was not run** on `NightSky`, `SkyArt`, `Sky.client` (not available in this
  session). The syntax gate and the headless checks run every line that matters, but type noise was
  not reviewed.
* **Owner decision: the streak and the idle kick.** The Day streak lives only for the session (Best
  Day is saved), and Roblox disconnects a player idle for ~20 minutes, so a player who walks away from a
  break loses the streak. Fixed in the review round: the break no longer calls the Day "safe", and once
  Roblox reports the player idle it says exactly what the kick costs (§4). Making "nothing is lost" TRUE
  across a disconnect would mean saving the streak across sessions: a gameplay change for Gustav, and not
  a free one, since leaving mid-pass and rejoining would then hand the player a fresh hall for the same
  Day (a re-roll of a pass they could not read), unless the live pass were saved and restored with it.
* **Owner decision: the slow player.** The band Days are placed so a normal player reaches Deep Sky
  in ~34 min; a slow player (the model's `slow` profile) needs ~55 min for the storm and hours for
  Deep Sky, because one miss resets the streak. Lowering the late thresholds would make the headline
  cheap for good players. Left as designed; `Pacing.spec` shows what any retune does.
* **Optional brag**: +1 Jump shows the band emoji next to Best and on the top-10 board. Here the HUD
  was deliberately left untouched (its gate and the capture rig depend on it). Showing, say, `🔭`
  next to a Best Day of 31+ would be a small `Hud.client` change for a later round.
* Everything in §8.
