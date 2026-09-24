# Lost & Found Depot — the wings

Owner's brief (Gustav, 2026-09-17), applied to this game: richer, never monotonous; the environment
changes as the player progresses, following what the game is about; rare, telegraphed hazards that
knock the player down; the "brag" destination (space) in about 30-45 minutes for a normal player, and
a longer-term goal beyond it; a way to rest that can never be exploited; a thumbnail shot list.

**What it became here.** The depot sends you to a new **wing** as your career grows: a city depot, an
airport lost-and-found, a train station's left luggage, a theme park's guest services, a lost property
office on a **space station**, and finally the last lost-and-found **beyond the galaxy**. Each wing has
its own light and sky, its own roof over your bay, landmarks over the walls, life in the air, weather,
and its own two runaway hazards on the sorting floor.

**State: built, unit-tested, headless-tested, mutation-tested, and adversarially reviewed once (REVIEW-2,
2026-09-24): its six findings were each reproduced, turned into a failing gate, fixed and mutation-tested
(§13). NOT seen in Studio.** Nothing committed, pushed or published. This work was started by earlier
sessions that were cut off by a usage limit; §12 says what the resume found and fixed, §13 what the review
found and what changed.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau`, `Hazards.luau`, `Rest.luau` | **copied verbatim** from `plus1-jump/src/shared` (the template), with their specs (`tests/EnvBands.spec`, `Hazards.spec`, `Rest.spec`, also verbatim). Byte-identical to +1 Jump's. |
| `src/shared/Wings.luau` | **new, pure.** This game's side of the template: `progress` / `completedShifts` (the career from the State payload), the walled floor (`bayRect`, `obstacles`, `room`, `clipLane`, `groundLane`, `endAtWall`, `withdraw`), `mayLaunch` (a due hazard waits for room, the player's own floor and an uncovered screen), `lockNear` (with a reaction time), `noteLock` and **`checkHit` (the knock: a full second inside the red ring and 2 s of warning, by construction)**, `zoneLive` (how long the ring can still hit), `endWithShift`, `keepStrongest`, `overheadFade`, and the BREAK (`pressBreak`, `updateBreak`, `hazardsMayRun`). |
| `src/shared/WingArt.luau` | **new, client only.** Every wing's pieces, critters, weather and hazard models, built in code (no assets), pooled. |
| `src/shared/StateCache.luau` | **new, pure.** The last State payload the HUD received, for the wings (§5 says why). |
| `src/client/Wings.client.luau` | **new.** The glue: career → wing weights → Lighting / pieces / critters / weather; hazards, knock, BREAK; the wing panel, warning and title cards. Every step of a frame runs on its own guard, the stumble's release first (§13, finding 4). |
| `src/client/Hud.client.luau` | **three lines:** a comment, `require` of `StateCache`, and `StateCache.set(st)` in its State handler. Nothing else. |
| `src/shared/Config.luau` | + `Env` (6 wings, `OverheadFade`, `Critters`), `Hazards` (10 kinds), `Rest`, `Budget`, `Pacing` (the design model's career, the sorter). Nothing above the new block changed. |
| `src/server/*` | **untouched.** The server does not know wings, hazards or breaks exist. |
| `tests/` | new `Wings.spec`, `EnvConfig.spec`, `Pacing.spec` (+ `SortModel.luau`, test-side: it calls the same Wings functions the client does, and its reacting sorter reacts to everything 0.4 s late), `StateCache.spec`; the three verbatim template specs. |
| `../robloxemu/check_lostfounddepot_wings.luau` | glue through the real server, HUD and client: career → wing, the glide, cards, the break, hazards (a still player, one who walks the bay, a reader up against the tray, broken cosmetic steps), budgets at every wing and seam, stress, leaks. |
| `../robloxemu/check_lostfounddepot_wingview.luau` | `_view`'s tap and sightline model on the same bay, bare and then with every wing built: identical numbers required. |
| `../robloxemu/check_lostfounddepot_hud_wings.luau` | hudcheck with BOTH ScreenGuis, 10 modes x 10 viewports (three of them: a hazard flying, then a drawer opened), plus the HUD's text rows; the title card against the HUD on all 10; no launch under a phone's drawer or a title card. |
| `../robloxemu/check_lostfounddepot_compile.luau` | every bundled source compiles; no `require` by string (luau-compile is gone from this machine). |

---

## 2. The wings and what triggers them

**Trigger: the career, never time.** The client reads the server's own State payload (the one the HUD
already gets): `shifts` (career shifts completed) plus, while a shift RUNS, `shift.cleared / shift.total`.

* the **continuous** value (`Wings.progress`, e.g. 12.83 = 12 shifts done and 25 of 30 sorted) drives every
  BLEND: lighting, atmosphere, sky, post-effects, pieces, critters, weather. A wing fades in while you sort
  the last third of the shift before it (`fade` 0.34 shifts, smoothstep);
* the **whole** number (`Wings.completedShifts`) NAMES the wing: the panel, the title card, which hazards
  fly. Sorting the last item of a shift does not rename the wing before the shift is over.

**Transitions never cut.** On top of the eased blend every written value glides with a 0.6 s half-life
(`Env.HalfLife`), so a jump in career (a join, a shift that times out with nothing sorted) also glides.
Measured through the real client: a jump from 0 to 36 shifts never moves ClockTime more than 12% of the way
in one write and never moves any scenery part's transparency more than 0.06 in a frame
(`check_lostfounddepot_wings` §6). Lighting is written at most 10 times a second, only when a value
changed. At a constant career nothing drifts: 20 s later the light is the same (§1). **At join** the lighting
glides from the server's preset (which is the first wing's) and the scenery waits for the loaded profile,
then fades in from nothing: a returning 12-shift player never sees the city's roof for a single frame and
their theme park fades in (§1).

Minutes to each wing come from the game's **own design model**, not a guess: `Config.Pacing.Career` is
`design/model.luau` PART 9's running total per career shift on the live 250/800/2000 price ladder
(reproduced by this session: the same 40 numbers, to 0.1 min), plus an ASSUMED 10 s of human overhead
per shift. `tests/Pacing.spec.luau` asserts the owner's window and prints:

| # | wing | from (shifts done) | career shifts | normal (regular) | slow (first-timer) | light and sky | over the bay | out past the walls | life | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | CITY DEPOT | 0 | 1-3 | 0 min | 0 min | afternoon = the server's Temple preset (no jump at join) | steel roof trusses, four hanging lamps | a city skyline all round, lit windows | pigeons | — | **none**: the tutorial, torn tags and the first memo each get a calm shift |
| 2 | AIRPORT LOST & FOUND | 3 | 4-6 | 8.5 | 13.2 | bright noon | glass terminal roof on white ribs; departures board over the arc: `ARRIVALS / LOST PROPERTY B3 ON TIME` | control tower with a blinking red beacon, hangar, terminal | airliners crossing | — | runaway trolley, tumbling suitcase |
| 3 | TRAIN STATION | 6 | 7-9 | 16.6 | 26.8 | late-afternoon gold, sun rays | iron-and-glass arched shed; a station clock over the arc whose minute hand really runs (a lap a minute) | a viaduct 70 studs up with a train crossing every 30 s (smoking loco), a brick clock tower | pigeons | steam | porter's cart, pigeon |
| 4 | THEME PARK | 9 | 10-13 | 24.6 | 39.9 | dusk, pink haze, first 400 stars | strings of coloured bulbs | a turning ferris wheel (a turn a minute), a loop coaster, a big top | balloons rising | confetti | giant beach ball (bouncing), bumper car |
| 5 | **SPACE STATION** | **13** | 14-36 | **35.1** | **57.4** | night, 3 500 stars, no haze | white dome ribs with blue running lights | **the Earth** with its cloud shell and airglow over the back wall, solar wings | satellites, a drifting astronaut | floating motes | floating crate, repair drone |
| 6 | BEYOND THE GALAXY | 36 | 37+ | 94.2 | 155.5 | deepest night, 5 000 stars, violet grade | the dome | a spiral galaxy (disc, core, curved arms), a ringed planet, a nebula | comets, satellites | stardust | runaway alien pet, space rock |

Asserted in `Pacing.spec`: the normal player reaches space in 30-45 min (35.1) and within 5 min of the
window's centre (a retune that drifts fails loudly); a slow reader inside an hour (57.4); every wing before
space lasts 5-15 min (8.5, 8.1, 8.0, 10.5): **never monotonous**; the first new wing inside 10 min of a first
session; the galaxy at least twice the time to space (94.2) and under 3 h even for a slow reader (155.5).
The Back Room ending (backlog 500, 18 shifts for a regular) lands at 47.9 min, **after** reaching space.
*When real session data exists, retune `Config.Pacing.BetweenShiftsSeconds` first, then the `from`
numbers; the spec says where space lands.*

Also on screen: the **wing panel** (bottom-left, level with the hotbar: `THEME PARK` /
`Next: SPACE STATION in 1 shift` / the BREAK button); the wing's name on two wall faces of the bay beside
(never over) the bay's own boards; a **title card** when a new wing is reached (`NOW POSTED: TRAIN STATION`;
`YOU MADE IT TO SPACE!` with a white flash and an FOV punch). The card waits while the HUD's summary card is
up and shows when it closes; a returning player gets a quiet card for the wing they are already in, never
a fanfare (`check_lostfounddepot_wings` §1, §3).

---

## 3. Hazards and their MEASURED rarity

Rare, telegraphed, one at a time, **client-only** (they only ever bump you), on **your own sorting floor**.

| kind | wing | speed | warning (to arrival) | ring across | knock | moves |
|---|---|---|---|---|---|---|
| runaway trolley | airport | 14 | 3.2 s | 6.6 | 24 | rolls |
| tumbling suitcase | airport | 12 | 3.0 s | 6.0 | 22 | rolls, tumbling |
| porter's cart | train | 13 | 3.2 s | 6.6 | 24 | rolls |
| pigeon | train | 16 | 3.0 s | 5.4 | 16 | flies low |
| giant beach ball | park | 12 | 3.2 s | 7.0 | 26 | bounces |
| bumper car | park | 13 | 3.2 s | 6.8 | 26 | rolls |
| floating crate | station | 8 | 3.6 s | 6.6 | 20 | drifts, turning |
| repair drone | station | 14 | 3.0 s | 5.8 | 20 | flies low |
| runaway alien pet | galaxy | 10 | 3.4 s | 6.6 | 22 | wobbles along the floor |
| space rock | galaxy | 14 | 3.0 s | 6.6 | 26 | flies low, glowing |

**Rules** (`Hazards` + `Wings`, all validated at load; an invalid config switches hazards off with a warning):

* one hazard every **120-180 s of RUNNING shift clock**, on a clock that stops between shifts, on a break,
  and while idle (frozen, never reset). None in the first wing. Never two at once;
* it starts **on screen** (within ±35° of where the camera looks and ±20° of its pitch) and **on your floor**:
  the template starts a hazard `speed x warning` studs out, which in a 72 x 56 bay is often behind a wall,
  so `Wings.clipLane` pulls the start in along the lane and SLOWS the hazard so the arrival time never
  shortens, clear of the tray, the six crates and the locker (`Wings.obstacles`). A hazard waits until the
  view has at least 10 studs of floor (`Wings.room`); a launch whose fitted lane is shorter is withdrawn the
  same frame and stays due (the rarity does not change). After it passes you it ends where it meets a wall
  or a fixture (`endAtWall`): a trolley never rolls through a crate. **A player up against the tray (reading
  its small tags) or a crate gets no lane from beyond it**: a ray that starts inside a fixture's 1.5-stud
  margin stops where it would enter the fixture (REVIEW-2 finding 3; until then those lanes rolled straight
  through the tray and its items);
* **a due hazard also waits while the screen is covered** (`Wings.mayLaunch`): on a phone while a HUD drawer
  or card is open (it sits exactly where the warning and the hazard's marker would be), and while the
  wing's title card is up. It stays due with its clock running, so this delays a hazard, it does not skip it
  (REVIEW-2 finding 2; measured below);
* **telegraph**: an always-on-top `!` marker and a blinking light on the hazard, a lane line from it through
  you, a ring at your feet and a banner `<< RUNAWAY TROLLEY INCOMING`, with an arrow when it is off to a side.
  While it tracks you (yellow) the lane re-aims at you; then it **locks**: ring and lane turn red, the banner
  says `MOVE! RUNAWAY TROLLEY`. If a phone drawer is opened while a hazard is flying, the banner steps aside
  (two lines, just below the drawer, between the thumbstick and the jump button; else beside the drawer)
  instead of disappearing;
* **the red ring is the danger zone, and THE KNOCK IS FAIR BY CONSTRUCTION** (`Wings.checkHit`, REVIEW-2
  finding 1). A hazard knocks you only when all three hold:
  1. you are inside its RED ring and it passes within reach (the template's ring rule, `Hazards.checkHit`);
  2. **you have been inside that red ring for at least 1 s without leaving it**, counted from the ring
     turning red or from when you stepped into it, whichever is later (walking into a ring that is already
     red also leaves you a full second to walk out again);
  3. **its warning has been up for at least 2 s.**
  Whatever you do: walking toward it, stepping back in, standing still. A hazard that reaches you sooner
  passes as a near-miss (the model counts these as "spared", below). Until REVIEW-2 only a player standing
  still had these guarantees: a sorter walking toward a lane (lanes start ahead of the camera, which for a
  walker is where they are going) was knocked 0.13 s after `MOVE!` and 0.40 s after the warning;
* the ring (and the banner) stay up exactly as long as a hit inside it is possible (`Wings.zoneLive`): on
  this small floor a fitted lane is slow and can still cross its ring after "arriving";
* **time to react for a player standing still**: `Wings.lockNear` locks the lane the moment the hazard is
  within reach + speed x `MinReactSeconds` (1.0 s), so the ring is red a full second before the hazard can
  first touch a player who never moves; the hit rule above then covers everyone else;
* **no hazard outlives the shift**: the moment the clock stops, one still in the air is taken away (it stays
  counted, the next keeps its due time);
* a knock: a sideways shove (16-26 studs/s) with 6 studs/s of lift (0.1 studs of height: never onto the tray
  step), 0.6 s of `PlatformStand`, a small camera shake and flash. **Nothing is dropped, lost or recorded;
  the server never hears of it.** What it costs is the stumble: a second or two of your own shift clock.
  The release is the first thing every frame does, so no other failing step can leave you on the floor
  (REVIEW-2 finding 4).

**Measured** (`tests/Pacing.spec.luau`: the game's own Hazards + Wings code, `Wings.checkHit` included, on a
sorter walking the real bay (`Layout`), 180 min of running shift clock per wing and sorter, the design model's
`regular` at stage 3). The **reacting** sorter reacts to EVERYTHING 0.4 s late, the reviewer's model: a red
ring ahead or the hazard's body in their way stops them only once it has been in their way 0.4 s, and they
step out of a red ring 0.4 s after finding themselves in it (until REVIEW-2 two of those rules had no delay,
which made that sorter unhittable). "Spared" counts the passes the plain ring rule would have knocked and
the promise turned into near-misses.

| wing | hazards / min (the reacting sorter's run) | the sorter who REACTS 0.4 s late: near-hits / min, knocks | the sorter who IGNORES every warning: knocks / min (each at least ... after the warning / after red) | spared: ignoring / reacting | the player who STANDS STILL: every knock at least ... after the warning / after the ring turned red |
|---|---|---|---|---|---|
| airport | 0.389 | 0.378, **0** | 0.056 (2.23 s / 1.00 s) | 24 / 22 | 2.47 s / 1.00 s |
| train | 0.389 | 0.361, **0** | 0.050 (2.53 s / 1.03 s) | 19 / 14 | 2.50 s / 1.03 s |
| theme park | 0.378 | 0.350, **0** | 0.056 (2.33 s / 1.00 s) | 33 / 18 | 2.40 s / 1.00 s |
| space station | 0.383 | 0.350, **0** | 0.033 (2.27 s / 1.00 s) | 25 / 15 | 2.43 s / 1.00 s |
| galaxy | 0.394 | 0.389, **0** | 0.044 (2.33 s / 1.00 s) | 30 / 31 | 2.40 s / 1.00 s |
| **all wings** | **~0.39 (one per 2.6 min)** | **0.366 near-hits / min = one per 2.7 min; 0 knocks in 348 hazards** | **0.048 / min = one per 20.9 min; 0.16% of shift time lost to stumbles** | 131 / 100 | |

Before REVIEW-2 (the reviewed build, same model): the reacting sorter was knocked by 100 of 352 hazards
(0.111 / min, red to knock as little as 0.13 s), the ignoring one 0.193 / min (one per 5.2 min, 0.43 s after
the warning at worst).

"About one near-hit per 2-3 minutes, easy to see coming and avoid" therefore holds: every hazard comes close
(they aim at you), a player who reacts to everything with a human's 0.4 s delay is never knocked, and one who
ignores every warning loses under 0.2% of their shift clock. A regular's shift is about 3 minutes of clock,
so that is **about one hazard per shift**.

Two designs were tried for finding 1 and REJECTED, measured (§13): launching only at a player standing still
(a still sorter faces the tray or a crate, so no lane ever had room: 0 hazards in 180 min per wing), and
locking the lane by the CLOSING speed so a walker saw red a second before contact (the lane stopped following
walkers so early that near-hits fell to one per 4.2 min, under the brief).

Through the **real client** (`check_lostfounddepot_wings`, hazards in memory every 6-7 s so a check sees
dozens):

* §4, a real running shift: 21 hazards, at the pick point and on a spot where the view has only 10-12 studs
  of floor (short, slow lanes). Three kinds of player take turns. 7 who stood in the ring were knocked;
  **7 who walked out of the red ring: 0 knocked**; 7 who stepped back onto the ring's far side just before the
  hazard arrived and stayed: 4 knocked, **all 4 after it had arrived, with the red ring still up**, which is
  what `zoneLive` is for. Every knock came at least 2.53 s after its warning and 1.03 s after `MOVE!`; nobody
  was knocked outside the drawn ring or after it was taken away; only the wing's own kinds; never two at
  once; every lane started on the floor; a knock lifts at most 6 studs/s, shoves at least 15 sideways and
  wears off; the server's clock (`endsAt`) was untouched by hazards and knocks; 0 calls to the server;
* §5: a player who never moves, on a spot with 12-13.5 studs of floor in view (the slowest lanes, where a
  drone touches you well before it "arrives"): 14 hazards, 14 knocks, each at least **1.00 s** after `MOVE!`.
  A hazard made to be in the air when the shift ends is gone, with its ring and warning, the same frame.
  Never in the city wing (60 s of running clock, hazards due every 6-7 s: none). None while the tray is
  armed, on the summary, or on a break;
* §5, **a sorter WALKING the bay** (REVIEW-2 finding 1): pick point → a bin stand → the pick point → the next
  stand at 18 studs/s, the camera behind them along the way they walk, stopping 1.2 s at each stand and 1.5 s
  at the pick point; THEME PARK and SPACE STATION, 150 s each: 43 hazards, 15 knocks, **every one at least
  2.13 s after its warning, 1.00 s after `MOVE!` and 1.00 s after the sorter stepped into the ring**, none
  outside the drawn ring (on the reviewed build the same walk: 22 knocks, 8 of them short, the worst 0.17 s
  after `MOVE!`, one before the ring was ever red);
* §5, **a broken cosmetic step** (REVIEW-2 finding 4): after a knock, `WingArt:updateWeather`, `updatePiece`,
  `updateCritters`, `showHazard` and then the frame's own read step (`EnvBands.weights`) are made to throw, one
  at a time: every stumble still wears off within KnockSeconds, the BREAK still books mid-shift, hazards keep
  coming and knocking with the scenery broken, and each broken step warns once (on the reviewed build the
  first fault left the player lying down for good and the BREAK dead);
* §5, **a reader up against the tray** (REVIEW-2 finding 3): 0.7 studs from its edge, the camera over the tray:
  0 hazards (no lane from beyond the tray; on the reviewed build 13 of 14 rolled through it); the same spot
  facing the floor: 14 hazards, none inside the tray's footprint on the way in.

The Wings spec samples 600 more fitted lanes against a still player (warning at least 2.13 s, red ring at
least 1.00 s) and 1 200 lanes against players who start walking during the flight, straight at the hazard,
away or across, half of them stopping again inside the ring: 92 knocks, each at least 2.00 s after the
warning, 1.00 s after red and 1.00 s after stepping into the ring; the plain ring rule on the same lanes
knocked 139 times, as little as 0.10 s after red.

---

## 4. Rest — what "pause" means in the depot

The shift clock is the game (330 s, starts at your first pickup, 8 s per misfile) and it lives on the
server, which cannot pause the world for one player and must not pause a clock a Perfect Shift and a
personal best are measured against. So **rest is between shifts, and the depot already has the pause:
the clock only starts at your first pickup.** The wings add a place to take it:

* **TAKE A BREAK** (wing panel, a thumb-sized button): between shifts you sit down, the far view softens
  (a depth-of-field blur beyond ~28 studs), the panel says `On break - the clock waits for your first
  pickup`. The sky, critters, train, ferris wheel and weather keep going. **BACK TO WORK**, or just move.
* **Mid-shift the button reads BREAK AFTER SHIFT**: pressing it BOOKS a break (`BREAK BOOKED`, press again to
  cancel). It never starts one against a running clock. When the shift ends, the booked break starts, under
  a clear sky (no hazard outlives the shift).
* **Your first pickup ends a break** in the same frame, standing still or not: the clock running again is
  the end of the break.
* **Idle** (AFK safety, from the template): stand still 20 s and hazards leave you alone
  (`Idle - hazards leave you alone`). Mid-shift that pauses **hazards only**; the server's clock runs on.
* Roblox's own idle disconnect still applies; nothing is lost then either (the server's autosave is
  unchanged).

**Why it cannot be exploited**

1. **It never touches the clock.** The break is client-side and the server never hears of it: no remote,
   no attribute. A break can only START while the clock is not running; pressed mid-shift it is booked; the
   first pickup (the server's clock RUNNING) ends it the same frame. Measured through the real server:
   30 s on a break, the tray still armed and the server's clock fields unchanged; a booked break and 30 s of
   hazards later, `endsAt` unchanged; idle for 46 s mid-shift, the server's clock ran the whole 46 s.
2. **It cannot dodge a penalty.** There are only two: the 8 s misfile penalty (server-side, per deposit;
   a break cannot happen mid-shift) and the clock itself (see 1). Nothing else in the game is timed, raided or
   ranked (no leaderboard; a personal best is your own fastest Perfect Shift, on the server's clock).
3. **It is not a panic button.** A break never starts with a hazard in the air or while you are airborne
   (`Rest.validate` refuses a config that allows it); pressed then, it is queued and taken the first safe
   moment you stand still, or dropped. Mid-shift it cannot start at all. A knock voids a pending one.
4. **It does not thin hazards out.** Every pause FREEZES the hazard clock, never resets it. Measured
   (`Wings.spec`, 6 h of working clock each): a player who never rests meets 142 hazards; one who presses
   BREAK every 7 s: 142; one who idles 25 s of every minute: 142. Through the real client (the interval
   stretched to 40-41 s for the test): the hazard that fell due during 25 s of idle did not launch, and came
   16.5 s after waking (the rest of its interval), not a fresh 40 s later.
5. **Idle is no shortcut either**: it takes 20 s of standing still (with the clock running) to pause a
   hazard that would cost a second or two.
6. **Nor is a drawer.** Since REVIEW-2 a due hazard waits while a phone's HUD drawer or card (or the wing's
   title card) covers the screen (§3). That is not a rest: the shift clock runs on, the hazard stays due and
   comes the moment the drawer closes (within 6 s in every one of 18 phone runs, `check_lostfounddepot_hud_wings`).
   It delays hazards, it does not skip them: a phone player who keeps the MANUAL open 25 s of every minute
   meets 137 hazards in 6 h of working clock against 142 (3.5% fewer, `Wings.spec`), while sorting a third
   of their shift with the middle of the screen covered. A knock costs 0.16% of the shift clock at most.

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| wings: lighting, sky, stars, post-effects, roofs, landmarks, critters, weather, wall signs, title cards, wing panel | **client** (`Wings.client` + `WingArt`) | cosmetic and per-player (your wing follows YOUR career); costs the server nothing, replicates nothing |
| hazards: schedule, telegraph, hit test, knock | **client** | they only ever move the local character, whose physics the client already owns. Nothing is awarded, removed or recorded: a knock costs the player's own time and nothing else. An exploiter who deletes hazards gains a second or two per shift, which a bot reading the public manual already beats (README "Fair play") |
| the BREAK and idle | **client** | they only pause client hazards; the clock is the server's and is never touched |
| sorting, pay, the clock, misfiles, the backlog, saves, spawn | **server, unchanged** | authoritative, as before |

**Leak review.** The client reads its own State payload (the server already sends it to this player alone),
its own character and camera, `Config` (already replicated) and the bay's public `BayPad` position. It fires
no remote and adds none, sets no attribute, writes nothing the server built, and everything it creates lives
in `workspace.DepotWings`, its own ScreenGui or two Lighting effects (`DepotSky`, `DepotBreakFocus`); it
takes over the server's `FxAtmosphere` / `FxBloom` / `FxColorCorrection` / `FxSunRays` by name instead of
stacking new ones. Every part is anchored, CanCollide/CanQuery/CanTouch off, no shadow: taps and the camera
pass through it and nothing can be stood on. All of that is asserted on a creation log of every Instance the
wings made (`check_lostfounddepot_wings` §9) and by a source scan (no `FireServer`, `InvokeServer`,
`SetAttribute`, `ServerScriptService`, `ServerStorage`, `OnClientEvent`). The main check's leak sweep
(Secret's note and codes never in client or shared source) covers the new files and stays green.

**Why the HUD passes State on (`StateCache`).** Roblox queues a RemoteEvent fired before any client listener
connects and hands the queue to the FIRST connection. The server pushes the loaded profile at join, usually
before a phone has started its LocalScripts. A second listener would race the HUD for that push, and
whichever lost would wait for the next one: a HUD with no cash, hotbar or tutorial hint, or a veteran shown
the first wing. So the HUD stays the only listener, exactly as before, and hands each payload to
`StateCache`; the wings poll it every frame (`check_lostfounddepot_wings` asserts Wings.client connects to
no remote).

**What other players see.** Each client decorates only its own bay. Hazards are local, so a knocked player
stumbles with nothing hitting them in other players' eyes (Studio list).

**Spawn order** (`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame at
spawn and the server did not change. `check_lostfounddepot_spawn` is green, unchanged.

---

## 6. Budgets (measured, `check_lostfounddepot_wings`)

Client-built only; the server builds none of this. Measured after 8 s at every wing and at the middle of
every seam (both wings live), over 8 more seconds of frames with hazards flying every 6-7 s:

| where | parts | emitters (particles/s) | beams | trails | lights |
|---|---|---|---|---|---|
| CITY DEPOT | 64 | 0 | 0 | 0 | 0 |
| city › airport | 85 | 0 | 0 | 0 | 0 |
| AIRPORT | 44 | 0 | 0 | 0 | 1 |
| airport › train | 93 | 2 (7.1) | 0 | 0 | 0 |
| TRAIN STATION | 80 | 2 (9.8) | 0 | 0 | 1 |
| **train › park** | **134** | **3 (10.9)** | 0 | 0 | 1 |
| THEME PARK | 77 | 1 (7.9) | 0 | 0 | 0 |
| park › station | 111 | 2 (6.5) | 0 | 0 | 1 |
| SPACE STATION | 44 | 1 (4.9) | 0 | 0 | 0 |
| station › galaxy | 48 | 2 (5.6) | 4 | 1 | 1 |
| BEYOND THE GALAXY | 35 | 1 (5.8) | 4 | 1 | 0 |

(A row is the scene at the end of its 16 s; when a hazard happens to be flying then, its model, lane and ring
add 4-7 parts and its blinking light 1. The peaks below are over every frame.)

| metric | measured peak | budget (`Config.Budget`) |
|---|---|---|
| local parts | **135** (train › park, also the worst frame with a hazard in flight) | 220 |
| particle emitters | 3 (steam + confetti + the loco's smoke) | 4 (weather capped at 2 by `EnvBands.capRates`) |
| particles per second | 10.9 | 60 |
| beams | 4 (galaxy arms) | 8 |
| trails | 1 (comet) | 8 |
| point lights | 1 (the hazard's blink) | 3 |
| hazards at once | 1 | 1 |

**Stress** (§8): first a flurry through all six wings 0.3 s apart, twenty times round (1 080 frames): never
more than two wings' scenery on screen, peak 137 parts. Then 160 random career jumps (0-40 shifts, running
or not, 0.2 s or 4 s apart) with hazards every 6-7 s, every budget asserted on every frame: peak **142
parts**, 370 unique instances ever under the folder (pooled, nothing piles up). The reviewer's own harder
stress (city, train and park in every order, held 0.4-2 s, the camera switching between low and zoomed out,
hazards every 3 s) peaks at 151 parts, 3 emitters, 1 light: inside the budget. Before `Wings.keepStrongest`
(the scenery of the two strongest wings only; normal play never blends more) random jumps reached 223 parts,
over budget (§12).

**What is pooled / how it stays cheap:** a wing's pieces are built the first time it is needed and
**unparented** at zero weight (a wing you are not in costs no draw calls); critters are pooled per kind,
faded in and out, recycled when out of range, at most one group spawned per kind per frame; one model per
hazard kind, one lane, one ring; one weather host with emitters created lazily (at most 2 on, summed rate
capped at 60/s); the ferris wheel moves at most 20 times a second; lighting at most 10 writes a second, only
on change. These are part and emitter counts, not frame rate: phone frame time is on the Studio list.

**The job stays readable** (`check_lostfounddepot_wingview`): `_view`'s tap and sightline model on the same
bay, bare and with every wing built (all parented wing parts as occluders; anything not fully invisible stops
the eye, so the 0.72 glass counts as a wall):

| | bare bay | every one of the 6 wings |
|---|---|---|
| sorting cameras (8-16 studs back, up to 16.3 up), every roof at full weight | taps 7657 / 7658 reach the item, 0 of 1953 sightlines blocked | **identical**: 7657 / 7658, 0 / 1953, 0 ending on a wing part |
| zoomed-out cameras (24-40 back, 30-60° down, 16.5-39.7 up) | taps 12863 / 12863, 0 of 837 blocked | **identical** (the roof has faded away) |

**The landmarks show over the walls** (same check): each wing's biggest landmark part, with the sorting
cameras at the pick point and every bin stand turned toward it, is seen over the 16-stud walls by the Earth
100%, the galaxy 100%, the viaduct deck 100%, the ferris wheel 99%, the skyline 98% and the airport terminal
95% of those cameras (the first measurement found the viaduct deck at 47%, hidden behind the back wall: it
was raised to 70 studs and brought in to 150, and the terminal made taller).

The roof fades with the CAMERA's height (`Config.Env.OverheadFade`: in full at or below 13 studs, gone at 16,
the wall tops), and every overhead part sits at or above 16 (lowest measured 16.2, the train shed's feet on
the walls): a camera that shows any roof is below all of it and cannot look down at a tag through it. The
landmarks and critters never enter the bay below the wall tops (asserted on every frame of §5); inside the
walls there are only the two wing signs (one-sided, flush on the wall beside the bay's own boards), the
hazard with its lane and ring, and the invisible weather host.

**The HUD stays usable** (`check_lostfounddepot_hud_wings`): both ScreenGuis on the 10 hudcheck viewports in
10 modes (the HUD's six, a hazard warning up, and a hazard flying when the MANUAL, UPGRADES or CODES drawer
opens), overlap rule on: PASS, and the wing panel and warning never sit on the HUD's memo, hint, toast, stamp,
cash, clock, toggles or hotbar. The wing panel sits LEFT of the hotbar, level with it (so above the
thumbstick); on a short landscape phone (640x300) it switches to a row (text, then BREAK to its right) and the
warning moves right of the hotbar. When a drawer opens on a phone during a hazard's flight the warning stays
up (30 of 30 runs), two lines just below the drawer where the hidden hotbar sits, clear of the thumbstick and
the jump button (18 of 18 touch runs); with a drawer open no new hazard launches (0 in 18 ten-second runs with
hazards due every 1-2 s). **The title card** (REVIEW-2 finding 5) goes in the free band between the HUD's text
rows and the hotbar with both lines when they fit (8 viewports), the title alone when only it fits (800x360
touch), or beside the hotbar on its right (640x300, where there is no band at all); measured with
"YOU MADE IT TO SPACE!" on all 10 viewports: shown on 10, 0 clashes with the rows, the hotbar or the wing
panel. No hazard launches while a card is up.

---

## 7. Gates

Every gate, run on the final source and a freshly rebuilt bundle. `luau` is the luau CLI, always `2>&1`.

| gate | before the wings (CLAUDE.md, 2026-09-17) | the wings as reviewed (REVIEW-2) | now, after REVIEW-2 |
|---|---|---|---|
| tests/Codes.spec | 16 / 0 | 16 / 0 | 16 / 0 |
| tests/Economy.spec | 157 / 0 | 157 / 0 | 157 / 0 |
| tests/Layout.spec | 32 / 0 | 32 / 0 | 32 / 0 |
| tests/Rng.spec | 32 / 0 | 32 / 0 | 32 / 0 |
| tests/Rules.spec | 95 / 0 | 95 / 0 | 95 / 0 |
| tests/Seed.spec | 24 / 0 | 24 / 0 | 24 / 0 |
| tests/Shift.spec | 79 / 0 | 79 / 0 | 79 / 0 |
| tests/responsive.spec | 70 / 0 | 70 / 0 | 70 / 0 |
| tests/walk.luau | 48 / 0 | 48 / 0 | 48 / 0 |
| tests/EnvBands.spec (template, verbatim) | — | 124 / 0 | 124 / 0 |
| tests/Hazards.spec (template, verbatim) | — | 102 / 0 | 102 / 0 |
| tests/Rest.spec (template, verbatim) | — | 55 / 0 | 55 / 0 |
| tests/Wings.spec | — | 213 / 0 | **256 / 0** |
| tests/EnvConfig.spec | — | 265 / 0 | **268 / 0** |
| tests/Pacing.spec | — | 100 / 0 | **115 / 0** |
| tests/StateCache.spec | — | 10 / 0 | 10 / 0 |
| **spec + walk total** | **553 / 0** | **1 422 / 0** | **1 483 / 0** |
| check_lostfounddepot | 238 / 0 | 238 / 0 | 238 / 0 |
| check_lostfounddepot_spawn | 29 / 0 | 29 / 0 | 29 / 0 |
| check_lostfounddepot_save | 111 / 0 | 111 / 0 | 111 / 0 |
| check_lostfounddepot_hudflow | 44 / 0 | 44 / 0 | 44 / 0 |
| check_lostfounddepot_view | 17 / 0 (front/pad taps 99.4%) | 17 / 0 (99.4%) | 17 / 0 (99.4%, 3169 of 3187, unchanged) |
| check_lostfounddepot_hud | PASS | PASS | PASS |
| check_lostfounddepot_rng | 24 / 0 | 24 / 0 | 24 / 0 |
| check_lostfounddepot_firstmin | 67 / 0 | 67 / 0 | 67 / 0 |
| check_lostfounddepot_wings | — | 183 / 0 | **217 / 0** |
| check_lostfounddepot_wingview | — | 66 / 0 | 66 / 0 |
| check_lostfounddepot_hud_wings | — | PASS + PASS (text rows) | **PASS + PASS** (10 modes; the title card on 10 viewports; the launch holds) |
| check_lostfounddepot_compile | — | 21 sources, 42 / 0 | 21 sources, 42 / 0 |
| **headless check total** | **530 / 0 + PASS** | **821 / 0 + PASS + PASS + PASS** | **855 / 0 + PASS + PASS + PASS** |
| `luau-compile` / `luau-analyze` | 14 / 14 clean | **not available**: both binaries were wiped from this machine on 2026-09-23 (only `luau.exe` survived). The compile half is `check_lostfounddepot_compile` (loadstring over all 21 sources); **luau-analyze was not run**. | still not available; not run |

The new glue checks pin the emulator's unseeded `Random` (as the older checks do), so they are deterministic: `_wings`, `_wingview` and `_hud_wings` were each run 3 more times on the final bundle with identical results (after REVIEW-2: `_wings` three runs and `_hud_wings` two, byte-identical output). `_view` still reports the front-row tap figure of 99.4% (3169 of 3187): the view check itself is untouched, and `_wingview` shows the wings change none of its numbers.

**REVIEW-2's fixes had their own sweep: 25 of 25 mutations killed, 3 controls survived (§13).** The sweep
below is the wings' first one, on the source as it was before REVIEW-2.

**Mutation sweep** (scratch tool `scratchpad/lfd_eye2/sweep.py`, final log `sweep_round3_final.log`; the real
tree was never written, and its sources' md5 were identical before and after). Six workers, each on its own
scratch copy of the game and of robloxemu's `emu/`, `wrap.py` and every `check_lostfounddepot*`. For each
mutation: exactly one occurrence replaced (line endings matched to the file), the bundle rebuilt and **proved
to carry it** (the bundle now embeds the mutated file and not the original), all 28 suites run (15 specs, the
walk, 12 checks), the file restored and its md5 re-checked. **30 mutations: 26 of the 27 real ones KILLED, the
harness control and both controls SURVIVED, as they must.**

| id | mutation | killed by |
|---|---|---|
| Z1 | `zoneLive`: the ring dies the moment the hazard arrives | Pacing.spec, Wings.spec, `_wings` |
| R1 | the client hides ring and warning at arrival (as before `zoneLive`) | `_wings` (a knock after the ring went) |
| L1 | `lockNear` ignores the reaction time | Pacing.spec, Wings.spec, `_wings` |
| L2 | the client does not pass `MinReactSeconds` | `_wings` (a still player got 0.83 s of red) |
| O1 | `overheadFade` cuts instead of easing | Wings.spec |
| O2 | the client never fades the roof | `_wings`, `_wingview` |
| O3 | the airport's glass roof not marked overhead | `_wingview` (zoomed-out sightlines blocked) |
| O4 | `OverheadFade.Gone` 16 -> 18 | EnvConfig.spec, `_wings` |
| K1 | no cap on wings shown at once | `_wings` (the flurry) |
| E1 | a hazard outlives the shift | `_wings` |
| B1 | BREAK mid-shift starts a rest | Wings.spec, `_wings` |
| B2 | the first pickup does not end a break | Wings.spec, `_wings` |
| B3 | `hazardsMayRun` ignores the clock | `_wings` |
| B4 | the client's hazards ignore the clock | `_wings` |
| P1 | progress ignores the running shift | Wings.spec, `_wings` |
| S1 | the HUD does not pass State on | `_wings`, `_wingview`, `_hud_wings` |
| S2 | the wings never poll the cache after load | `_wings`, `_wingview`, `_hud_wings` |
| SC1 | `StateCache` never bumps its version | StateCache.spec, `_wings`, `_wingview`, `_hud_wings` |
| U1 | no row layout on a short phone | `_hud_wings` |
| U2 | the warning always above the hotbar | `_hud_wings` |
| C1 | `clipLane` shortens the warning instead of slowing the hazard | Wings.spec |
| G1 | the first wing (tutorial shifts) gets hazards | EnvConfig.spec, `_wings` |
| N1 | a knock lifts 9 studs/s | EnvConfig.spec |
| V1 | the Earth sinks below the walls | `_wingview` (seen by 10% of the cameras) |
| T1 | the title card does not wait for the summary card | `_wings` |
| Q1 | a returning player's first card is a fanfare | `_wings` |
| **W1** | `WingArt` skips `EnvBands.capRates` (the weather cap) | **SURVIVED: equivalent with this config.** At most two wings blend and a wing has one weather kind, so at most two emitters at 8 + 6 particles/s are ever wanted; the cap cannot bind. `EnvConfig.spec` now asserts that premise (the two heaviest wings' weather fits the budget), so a config that would need the cap fails there first. |
| C0 | harness control: no change at all | survived |
| CONTROL-1 | the city lamps a shade warmer | survived |
| CONTROL-2 | the loco puffs 5 smoke particles a second, not 4 | survived |

Earlier rounds found gaps and closed them before this final one: round 1 (`sweep_round1.log`) had L2, K1 and R1
surviving and four mutations that did not apply (CRLF files); round 2 had L2, E1 and V1 surviving. Each got
an assertion that was watched fail on the mutant (`sweep_spot_L2_E1_V1.log`): a still player on a slow-lane
spot, a deliberate flurry through all six wings, a player who steps back into a live ring, a hazard forced to
be in the air when the shift ends, and each landmark's biggest part measured over the walls.

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Every wing's look**: the six light grades; that tags (BillboardGuis, not AlwaysOnTop) and the boards stay
   legible under each (the night wings keep Ambient >= 100, bloom threshold >= 0.75, tint near white, all
   asserted in `EnvConfig.spec`, none rendered); the glass roof's tint on the tray from inside.
2. **The roof fade**: the roof (in full below a 13-stud camera, gone at 16) while zooming. Smooth or
   distracting? The train shed and station dome rest their feet on the wall tops: does that read as a roof
   or as parts sitting on the walls?
3. **Distant giants on a phone**: the Earth (a 900-stud sphere 1 500 away), the galaxy disc (1 400 across, 1 600
   away), the ringed planet, nebula, skyline, viaduct. Low graphics quality may cull them; if so, closer and
   smaller.
4. **Neon and bloom**: lamps, bulbs, the blue running lights, the galaxy core, the airglow (0.9 transparency).
5. **Beams**: the galaxy arms (curve sizes, `FaceCamera = false`) almost certainly need hand tuning.
6. **Moving set pieces**: the ferris wheel rim and spokes (`CFrame.lookAt` with up = +Z), the gondolas, the
   train on the viaduct, the station clock's hands (face toward the tray, turning about the centre), the
   tower beacon blink.
7. **Critters and hazard models**: pigeon wing flap axis, airliner and satellite orientation, the astronaut's
   tumble; every hazard facing along its lane; the beach ball's bounce, the pet's wobble, the suitcase and
   crate spin.
8. **The knock on a real humanoid**: does `PlatformStand` + a 16-26 studs/s shove stumble the sorter
   acceptably, does it release cleanly, can it push a player onto the tray step or wedge them against a crate
   (6 studs/s of lift says no). A carried item stays carried: the server does not know.
9. **The ring and lane on the floor** (a 0.12-stud disc at y 0.07 over the floor top at 0): z-fighting? Is
   the red ring clearly readable on each wing's floor light? Can a phone player step out of a 6-7 stud ring
   in the 1 s of red, with a thumbstick?
10. **The warning banner** (centred above the hotbar; right of it on a 640x300 phone) and the `!` marker:
    noticed in time on a phone?
11. **The wing panel on a phone**: stacked above-left of the hotbar on most phones; on a short landscape
    phone the row layout gives the wing name about 96 screen px: legible?
12. **The BREAK**: `Humanoid.Sit = true` without a seat from the client: does it sit, replicate, wake on the
    thumbstick, unsit on jump? The depth-of-field blur beyond ~28 studs: pleasant or muddy?
13. **Title cards**: `YOU MADE IT TO SPACE!` with the flash and FOV punch: celebratory, not annoying; placed
    between the HUD's text rows and the hotbar where they fit.
14. **Other players**: a knocked player stumbling with nothing hitting them (hazards are local); a neighbour's
    bay has no roof in your view (every client decorates only its own bay).
15. **Frame time** on a mid/low phone at the densest seam (train › park, 134 parts) with the depot's 12 bays.
16. **Weather in the bay**: confetti (0.35 studs) and motes (0.18) drifting through the tray area: charming or
    in the way of the tags?
17. **The join**: `StateCache` rests on Roblox delivering the queued join payload to the HUD (the first and
    only State listener). On a real phone join, a returning veteran should see their own wing at once, with
    no city flash first. The client-created `DepotSky`: any visible pop at join?
18. **The skybox** is Roblox's default with StarCount, sun and moon sizes blended; no custom sky textures.
19. **The knock rule, felt** (REVIEW-2): a knock needs a full second inside the red ring. Does that read as
    fair and obvious, or does a hazard that rolls through a sorter who walked into it early ("spared": about
    one pass in three for a player who ignores the warnings, one in four for one who reacts) look like a bug?
    If it does, the cheapest cue is a small hop or swerve of the hazard on a spared pass; not built.
20. **The warning under a phone drawer** (REVIEW-2): two lines just below the drawer, between the thumbstick
    and the jump button. Readable there, at a glance, with a thumb on the stick?
21. **The title card on a phone** (REVIEW-2): the title alone in the free band on 800x360; both lines beside
    the hotbar, on its right, on 640x300. Celebratory enough there, and legible at those sizes?

---

## 9. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *Not tried in Studio yet: verify step 1-3 before relying on
the rest.*

1. **Build a place that has the wings.** In `lost-found-depot/`, run `rojo build -o LostFound-shots.rbxlx` and
   open that. `*.rbxlx` is git-ignored. `LostFoundDepot.rbxlx` on disk (2026-09-17) **predates the wings**.
2. **No saves.** *Game Settings -> Security -> Enable Studio Access to API Services* **OFF**. The profile
   load then fails and the session plays read-only with a fresh career (0 shifts): nothing reaches the live
   DataStore.
3. **Pick the wing by editing `ReplicatedStorage.Config` in the shots place only** (never `src/`): in
   `Config.Env.Bands`, delete every wing but the one you are shooting and set its `from = 0, fade = 0`
   (`EnvBands.validate` accepts a single wing starting at 0). For shots from ABOVE the roof also set
   `Config.Env.OverheadFade = { Full = 1000, Gone = 1001 }`, or the roof fades away as the camera rises. For
   the hazard shot set `Config.Hazards.IntervalMin = 8`, `IntervalMax = 10` and `Config.Rest.IdleSeconds = 0`.
   Stop and press Play again after each edit.
4. **Play solo**: you get `Bay_1`, centred at **x = 100** (floor top y = 0, back wall z = -36, front wall
   z = 20, the pick point at (100, 3, 0), the tray at z 3.5-9.5, the six bins on an arc of radius 28 toward
   -Z). Coordinates below are world coordinates for Bay_1. Let the wing glide in for 5 s.
5. **Clean frames** (command bar, Client): `local g = game.Players.LocalPlayer.PlayerGui; g.DepotHud.Enabled =
   false; g.DepotWings.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   Freecam (Shift+P) moves `workspace.CurrentCamera`, so the roof fade follows it (see step 3).

Shots, best first:

1. **"Lost property in orbit"** — SPACE STATION, the brag. Avatar at a bin stand mid-drop, an item in hand.
   Camera low near the pad, (100, 6, 16), looking at (160, 70, -400): the white dome ribs and blue running
   lights across the top of the frame, **the Earth with its airglow filling the sky over the back wall**,
   the tray's tags and the bin signs in the lower third, stars; a satellite or the drifting astronaut if one
   passes (wait for it). **Card variant, HUD on:** keep two wings, CITY at `from = 0` and SPACE STATION at
   `from = 1` (`fade = 0.34`), set `Config.Shift.Seconds = 20`, pick one item, let the 20 s run out, close the
   summary card: `YOU MADE IT TO SPACE!` with the flash, over the station. It plays once per session.
2. **"Last train"** — TRAIN STATION at golden hour. Camera at the pick point, low, (110, 5, 10), looking up at
   (95, 30, -60): the iron arches and glass, **the station clock hanging over the bins**, the viaduct beyond
   the back wall with **the train crossing** (every 30 s: take a burst as the loco's smoke passes), steam
   rising, pigeons. Sun rays on.
3. **"Dusk at the park"** — THEME PARK. Camera (120, 8, 14) looking at (40, 45, -200): the strings of coloured
   bulbs over the bay in the upper frame, **the ferris wheel turning** beyond the back-left wall and the loop
   coaster to the right, balloons rising, confetti in the air, the pink haze; the tray and bins below.
4. **"Close call"** — AIRPORT (trolley) or THEME PARK (beach ball / bumper car), hazard settings from step 3.
   Hazards only fly while the shift clock RUNS: pick up an item first. Camera side-on and low, about 15 studs
   to the avatar's side, normal camera (Freecam takes the movement keys). When the ring and lane turn red
   (`MOVE!`), step sideways out of the ring and take the burst as the hazard passes. In frame: the hazard
   with its `!` marker, the red lane and ring, the avatar just outside it, the wing's roof overhead. A knock
   only stumbles you; the next one comes 8-10 s of clock later.
5. **"Arrivals"** — AIRPORT, bright noon. Camera (106, 9, 18) looking at (90, 22, -60): the glass terminal
   roof on its white ribs, the departures board `ARRIVALS / LOST PROPERTY B3 ON TIME` over the arc, the
   control tower's red beacon over the back-left wall, an airliner crossing; a suitcase on the tray.
6. **"Beyond the galaxy"** — BEYOND THE GALAXY from above (OverheadFade raised, step 3). Freecam at
   (140, 60, 60) looking at (-50, 420, -1600): the bay small in the lower frame (the dome's ribs, the tray and
   the arc of bins), **the spiral galaxy** with its bright core and curved arms high in the sky, the nebula at
   the edge, a comet trail. A second angle toward (720, 260, 900) catches the ringed planet.

---

## 10. Using this game as a template (what differs from +1 Jump)

* **Progress is the career from the server's payload**, not the character's position: a sorting game has no
  altitude. Blend by the continuous value (shifts + cleared share), NAME by whole completed shifts.
* **A walled floor**: fit lanes to the floor (`clipLane` keeps the arrival time by slowing the hazard), check
  the room in view before launching, treat fixtures as obstacles, end a flight at a wall. A slow hazard
  touches a player long before it "arrives": lock by reaction time (`lockNear` with `MinReactSeconds`), keep
  the ring up while it can still hit (`zoneLive`).
* **A timed game**: rest is between rounds (the BREAK books itself for the end of the shift and the first
  pickup ends it); no hazard outlives the round; hazards run only on the round's clock.
* **A second client script next to a HUD**: never add a second listener on a remote the server pushes at
  join; take the payload from the HUD (`StateCache`).
* **Overhead scenery over a play area that must stay readable**: fade it by the camera's height, keep every
  overhead part above the fade's top, and measure with the game's own view model (`_wingview`).
* **Players who walk** (REVIEW-2): a lane that starts ahead of the camera starts where a walker is going, so
  guarantees measured on a player standing still do not hold for them. Make the promise part of the HIT
  (`Wings.checkHit`: a full second inside the red ring, counted from red or from stepping in, and 2 s of
  warning), measure with a model that reacts to EVERYTHING late (not only to the ring under its feet), and pin
  the promise as literals in the tests, never as the Config value under test.
* **A phone HUD with drawers**: hold new hazards while a drawer or card covers the screen, and move (never
  hide) the warning of one already flying. Measure the title card against the HUD itself: hudcheck's overlap
  rule sees Frames only.
* **Fixtures in the play area**: a player can stand inside an obstacle's margin; a ray from there must still
  respect the fixture itself.
* **One RenderStepped doing many things**: guard each step on its own, and release anything that holds the
  player (a stumble) first.

---

## 11. Not done / open

* **One adversarial review so far (REVIEW-2, §13)**; its fixes have been tested by their author and the
  mutation sweep, not yet re-reviewed by a fresh reviewer.
* **Owner decisions surfaced, not taken:** (a) hazards cost the player a stumble (about 1.6 s of their own
  shift clock per knock; since REVIEW-2 a knock needs a full second in the red ring, so a player who ignores
  every warning is knocked once per 21 minutes and loses 0.16% of the clock, one who reacts never). They never touch pay,
  items, misfiles or the backlog, but they can cost a personal best (fastest Perfect Shift). If the personal
  best must be hazard-free, the cheapest change is to switch hazards off for a shift that is on pace for one;
  not done. (b) The second wing (hazards on) starts at career shift 4, after the tutorial, torn tags and the
  first memo have each had a calm shift.
* **luau-analyze was not run** (the binary is gone from this machine); luau-compile is replaced by the
  loadstring compile check.
* Not committed, not pushed, not published. Studio not opened. §8 in full.

---

## 12. The resume (2026-09-24): what the interrupted build left, and what this session changed

The earlier sessions had written `Wings.luau`, `WingArt.luau`, `Wings.client.luau`, the Config block and the
specs; there was no EYECANDY.md, no headless check, and the bundle had not been rebuilt since 2026-09-17.
Re-reading every new and changed file and running every gate found:

| # | found | fix (test first: each failing assertion was watched fail on the unfixed code) |
|---|---|---|
| 1 | `Wings.spec` crashed: it called `Wings.zoneLive`, which did not exist. `Pacing.spec` 5 failures: a sorter who stepped out of the red ring was still knocked 24-36 times in 180 min per wing, by a slow fitted hazard crossing its ring AFTER "arriving", when the client had already hidden the ring | `Wings.zoneLive`; the ring and the warning stay up exactly as long as a hit inside the ring is possible; the sorter model respects the ring that long: 0 knocks |
| 2 | a player standing still in the ring got as little as **0.13 s** of red ring before a knock (0.73 s even for a player who never moves), and a knock could come 0.43 s after its warning, because a slow hazard touches a player long before its planned lock | `Wings.lockNear(..., MinReactSeconds)`: locks at reach + speed x 1.0 s. Now at least 1.00 s of red and 2.40 s of warning (Pacing), 2.13 s (Wings.spec property), 2.53 s (client). The reacting sorter now reacts 0.4 s late, like a human, and is still never knocked. *(REVIEW-2: that last claim was an artifact of the model, whose avoid rules had no delay; a walker could still be knocked 0.13 s after red. Fixed by the hit rule, §13)* |
| 3 | a second State listener (the wings) would race the HUD for the join payload Roblox queues for the first listener: whichever lost waits for the next push | `StateCache`; the HUD stays the only listener (three lines in Hud.client) |
| 4 | the wing panel sat on the HUD's memo, hint and toast rows on the common 800x360 phone and on the cash panel at 640x300; the warning on the toast at 640x300 (hudcheck compares Frames only, so a new assertion measures the text rows) | the panel moved left of the hotbar, level with it; a row layout for short phones; the warning moves right of the hotbar when there is no room above it; the title card goes between the text rows and the hotbar when it fits |
| 5 | roofs and lamps over the bay: a player zoomed out above the walls would look down at the tags THROUGH them (a CanCollide = false part never pulls the camera in), and the art's own claim "never below y = 18" was false (the shed's feet sit at 16.2) | `Wings.overheadFade` + `Config.Env.OverheadFade` (13 -> 16); every overhead part at or above 16, asserted; `_wingview` proves nothing is newly hidden, zoomed in or out |
| 6 | a hazard still flying when the shift ended could knock a player on the summary, and its knock cancelled a break booked for that moment | `Wings.endWithShift`: no hazard outlives the shift |
| 7 | random career jumps stacked three or more wings' scenery: 223 parts, over the 220 budget | `Wings.keepStrongest`: pieces, critters and weather from the two strongest wings (normal play never blends more): stress peak 140, a deliberate flurry through all six wings 137, never more than two wings on screen |
| 8 | the wing panel's text and button were written before the break updated, so they showed last frame's state | the panel is written at the end of the frame |
| 9 | `Config.Pacing.Career` said it came from the design model | reproduced: `design/model.luau` PART 9 on the live 250/800/2000 ladder gives the same 40 + 40 numbers |
| 10 | a returning veteran saw the CITY DEPOT's roof and skyline for 4 s at join before their own wing glided in (the scenery started at the first wing and faded from it) | the scenery waits for the loaded profile and fades in from nothing (`_wings` §1: 0 frames of city for a 12-shift player) |
| 11 | the train wing's viaduct, its moving centrepiece, was behind the back wall for half the sorting cameras (47%) | deck raised to 70 studs and brought in to 150; the terminal taller; `_wingview` now measures every wing's biggest landmark over the walls (95-100%) |

---

## 13. REVIEW-2 (2026-09-24): the adversarial review of the wings, and what changed

An independent reviewer worked on scratch copies only (probes in `scratchpad/lfdrev_adv9/`) and reported six
findings. Every one was **reproduced first** on the reviewed source, with the reviewer's own probes and with a
new gate; each gate was watched fail on the reviewed build (its bundle, `lfdrev_adv9/robloxemu/build`), then
the game was fixed (never the test), then the gates went green and the fixes were mutation-tested.

| # | finding (severity) | reproduced on the reviewed build | fix | proven by (red on the reviewed build, green now) |
|---|---|---|---|---|
| 1 | **a walking player is warned far too late** (high). Lanes start ahead of the camera, which for a walker is where they are going; the reach rule counted only the hazard's own speed; the model's "reacting" sorter had two avoid rules with no delay | reviewer's `probe_walk`: 48 hazards, **31 knocks**, warning → knock min **0.40 s**, `MOVE!` → knock min **0.13 s**; `Pacing.spec` with the sorter reacting to everything 0.4 s late: **100 knocks in 352 hazards**, and the ignoring sorter knocked 0.43 s after the warning (25 failures) | **`Wings.checkHit` is the knock**: the ring rule, and only after the player has been a full `MinReactSeconds` (1 s) inside the red ring (from red, or from stepping in) and `MinWarnSeconds` (2 s) of warning, by construction. `SortModel`'s reacting sorter now reacts to everything 0.4 s late (the reviewer's model) and calls the same Wings functions as the client | `Wings.spec`: hand-built lanes (locked late, walked in late, stepped out and back, long frames) and 1 200 game lanes against players who walk during the flight: 92 knocks, each >= 2.00 s / 1.00 s / 1.00 s (the plain rule: 139 knocks, red as little as 0.10 s). `Pacing.spec`: the reacting sorter **0 knocks in 348 hazards**, near-hits one per 2.7 min; the ignoring sorter one knock per 20.9 min, each >= 2.23 s after the warning and 1.00 s after red. `_wings`: a sorter walking the bay: 43 hazards, 15 knocks, each >= 2.13 s / 1.00 s / 1.00 s (reviewed build: 22 knocks, 8 short, worst 0.17 s after `MOVE!`). Reviewer's `probe_walk` re-run: 48 hazards, **0 knocks** |
| 2 | **on a phone an open drawer hides the warning** (medium) | reviewer's `probe_drawer` (800x360 touch, MANUAL open): 10 hazards, **10 knocks, the banner on 0 of 966 flying frames**, the `!` marker behind the drawer on 679 | a due hazard **waits while a phone's drawer or card, or the wing's title card, covers the screen** (`Wings.mayLaunch`; it stays due, the clock is untouched); a hazard already flying when a drawer opens **keeps its warning**, two lines just below the drawer (where the hidden hotbar sits, between the thumbstick and the jump button), else beside it | `_hud_wings`, three new modes on all 10 viewports, overlap rule on: the warning stayed up in 30 of 30 runs, clear of the touch controls in 18 of 18, never on a drawer or a HUD row; 18 phone runs with a drawer open 10 s and hazards due every 1-2 s: **0 launches**, and one within 6 s of closing every time (reviewed build: the warning hidden, first run). `Wings.spec`: a drawer open 25 s of every minute delays hazards, 137 against 142 in 6 h. Reviewer's `probe_drawer` re-run: no new launch in 60 s with the drawer open |
| 3 | **runaways roll through the tray at a reader up against it** (low). A ray that started inside a fixture's grown box ignored that fixture | `Wings.spec` sweep (the reviewer's): **1 297 of 1 302 launches through the tray** (reviewer: 1 384 of 1 395); `_wings` on the reviewed build: 13 of 14 hazards drawn inside the tray on the way in (reviewer: 18 of 18) | `rayToObstacle`: from inside a fixture's 1.5-stud margin a ray stops where it would enter the fixture itself, and is free only where it leads away (boxes carry their margin `m`) | `Wings.spec`: 0 launches over the tray; with the camera along or away from it 874 launches, **0 through it**; 0.7 studs from every crate and the locker no room; standing on the tray, no room. `_wings`: a reader 0.7 studs from the tray, camera over it: 0 hazards; facing the floor: 14 hazards, 0 through the tray on the way in, and one that has arrived ends at its edge (at most 0.00-0.04 studs in). Reviewer's `probe_tray_rt` re-run: 0 hazards, 0 inside |
| 4 | **a cosmetic error after a knock leaves the player lying down for good** (low). The stumble's release ran late in one pcall | reviewer's `probe_fault`: `PlatformStand` still true 30 s after `WingArt:updateWeather` started throwing; `_wings` on the reviewed build: every stumble stuck, the BREAK dead | **every step of a frame runs on its own guard, the stumble's release first**; `knockUntil` is set before anything that can fail after a knock; a hazard that cannot be drawn cannot knock (drawn before the hit test); each broken step warns once | `_wings`: after knocks, `updateWeather`, `updatePiece`, `updateCritters`, `showHazard` and the frame's own read step (`EnvBands.weights`) throw in turn: every stumble wears off within KnockSeconds, the BREAK still books, hazards keep coming with the scenery broken, one warning per step. Reviewer's `probe_fault` re-run: `PlatformStand` false |
| 5 | **the wing's title card sits on the hotbar on common phones** (low) | reviewer's `probe_card`: 800x360 (3 872 + 5 332 px²), 640x300, 844x390; `_hud_wings` card sweep on the reviewed build: **9 clashes** (hotbar; on 640x300 also the toast row and the wing panel) | the card goes in the free band between the HUD's text rows and the hotbar (both lines; the title alone when only it fits), else beside the hotbar on its right, else it is not shown; its lines are re-decided on every layout; no hazard launches while it is up | `_hud_wings`: "YOU MADE IT TO SPACE!" on all 10 viewports: shown on 10 (the sub line on 8), **0 clashes**; 0 launches while it was up. Reviewer's `probe_card` re-run on 800x360, 640x300, 844x390, 915x412: no overlaps |
| 6 | **the "1 s of red" promise was pinned by no gate** (low): `MinReactSeconds = 0` passed everything, because every gate compared the measured time against Config's own value | the reviewer's mutant | the promise as **literals** (2 s, 1 s) in `Pacing.spec`, `_wings` and `Wings.spec`; `EnvConfig.spec` pins `MinReactSeconds >= 1.0` and `MinWarnSeconds >= 2.0` | mutation sweep below: K1 (0), K2 (0.8) and K3 (`MinWarnSeconds` 1.5) all killed |

**Tried for finding 1 and rejected, measured** (so nobody re-tries them blind):

* **launch only at a player standing still** (a lane then always starts at a still player). `Pacing.spec`:
  **0 hazards in 180 min per wing** for the walking sorters. A still sorter faces the tray (reading) or a crate
  (dropping), so no lane in the camera's window ever has room; the rarity assertion failed (0.000 / min).
* **lock the lane by the CLOSING speed** (a walker heading at it sees red a second before contact, not only a
  still player). It cannot help a walker already within a second of the hazard at launch (on this floor most
  are: every short case locked on the first frame), and the lane stopped following walkers so early that
  near-hits fell from one per 2.7 min to **one per 4.2 min**, under the brief. `Pacing.spec` variants in
  `scratchpad/lfdfix10/lost-found-depot/tests/zz_variants.luau`.
* a first version of the hit rule counted the second from the ring turning red only. Under the reviewer's
  strict lag model the reacting sorter was still knocked (one per 36 min, 1.2 s after red) by walking into a
  ring that was already red; counting from stepping in gave 0 (mutation H3 below keeps it that way).

**What the fix costs.** A hazard that reaches a player before their second in the ring is up passes as a
near-miss: over 180 min per wing, 131 such passes for the ignoring sorter and 100 for the reacting one (one in
three and one in four hazards). How that looks is Studio item 19.

**Mutation sweep of the fixes** (scratch tool `scratchpad/lfdfix10/sweep/sweep.py`, log `sweep_r2.log`; seven
workers, each on its own scratch copy of the game and of robloxemu's `emu/`, `wrap.py` and every
`check_lostfounddepot*`; per mutation exactly one occurrence replaced (line endings matched), the bundle rebuilt
and proved to carry it, all 28 suites run, the file restored and its md5 re-checked; the real tree was never
written):

| id | mutation | result: killed by |
|---|---|---|
| C0 | HARNESS CONTROL: no change at all | **SURVIVED** (as it must) |
| CTL-A | CONTROL: the title card's text stroke a little lighter | **SURVIVED** (as it must) |
| CTL-B | CONTROL: the hazard ring a touch less see-through | **SURVIVED** (as it must) |
| H1 | F1: the knock no longer needs a second inside the red ring | KILLED: Pacing.spec, Wings.spec, `_wings` |
| H2 | F1: the knock no longer waits for 2 s of warning | KILLED: Pacing.spec, Wings.spec |
| H3 | F1: the second counts from the ring turning red, not from stepping into it | KILLED: Pacing.spec, Wings.spec, `_wings` |
| H4 | F1: a lane that still follows the player (no red ring) can knock | KILLED: Pacing.spec, Wings.spec, `_wings` |
| H5 | F1: a long frame counts from its start, not from the allowed moment | KILLED: Wings.spec |
| H6 | F1: the client knocks with the plain ring rule (as reviewed) | KILLED: `_wings` |
| H7 | F1: the client passes no time-in-the-ring | KILLED: `_wings` |
| K1 | F6: Config MinReactSeconds 1.0 -> 0 (the reviewer's mutant) | KILLED: EnvConfig.spec, Pacing.spec, `_wings` |
| K2 | F6: Config MinReactSeconds 1.0 -> 0.8 (a quiet retune) | KILLED: EnvConfig.spec, Pacing.spec, `_wings` |
| K3 | F6: Config MinWarnSeconds 2.0 -> 1.5 | KILLED: EnvConfig.spec, Pacing.spec |
| D1 | F2: mayLaunch ignores a covered screen | KILLED: Wings.spec, `_hud_wings` |
| D2 | F2: the client does not hold launches under a phone's drawer | KILLED: `_hud_wings` |
| D3 | F2: the warning hidden while a phone's drawer is open (as reviewed) | KILLED: `_hud_wings` |
| D4 | F2: the warning left where it was, on the drawer | KILLED: `_hud_wings` |
| D5 | F2: the aside warning ignores the thumbstick and jump button | KILLED: `_hud_wings` |
| T1 | F3: a ray starting in a fixture's margin ignores the fixture (as reviewed) | KILLED: Wings.spec, `_wings` |
| T2 | F3: the fixture's own box is taken as the grown one | KILLED: Wings.spec, `_wings` |
| G1 | F4: the weather step unguarded | KILLED: `_wings` |
| G2 | F4: the stumble released after the read step, not first | KILLED: `_wings` |
| G3 | F4: a broken step warns every frame | KILLED: `_wings` |
| G4 | F4: the release time set after a step that can fail | KILLED: `_wings` |
| C1 | F5: no place beside the hotbar (the card hidden on a 640x300 phone) | KILLED: `_hud_wings` |
| C2 | F5: a new layout does not re-decide the card's lines | KILLED: `_hud_wings` |
| C3 | F5: hazards launch while a title card is up | KILLED: `_hud_wings` |
| C4 | F5: never both lines in the band (title only or beside) | KILLED: `_hud_wings` |

**25 of 25 real mutations KILLED; the harness control and both controls SURVIVED, as they must.** Every
mutation was proved to reach the bundle and restored (md5); the real tree was unchanged across the sweep.

**The reviewer's probes, re-run on the fixed source** (scratch copies): `probe_walk` 48 hazards, 0 knocks (was
31); `probe_drawer` no new launch in 60 s with the MANUAL open (was 10 knocks with no banner); `probe_tray_rt`
0 hazards through the tray (was 18 of 18); `probe_fault` the stumble released (was stuck); `probe_card_*` no
overlap on any of the four phone sizes (was 3 of 4); `probe_stress` peak 151 parts, inside the budget.

**Not done / open after REVIEW-2:** no fresh reviewer has looked at these fixes yet; the look of a spared pass,
the warning under a phone drawer and the title card on a phone are Studio items 19-21; luau-analyze is still
not available on this machine.
