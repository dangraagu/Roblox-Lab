# Outpost Zero: Sky City Tycoon: design spec (v1)

**Status: design only.** No game code exists. Nothing is committed, pushed or published, no universe exists, and
Studio has not been opened. Written 2026-10-07 from `docs/game-radar/2026-09-23-roblox-game-radar.md`, concept brief
"### 4. Outpost Zero: Sky City Tycoon" (line 267) and its ranked entry #4 (score 7.05; the radar calls it the slowest
build of its top four). It is held to `docs/complete-game-standard.md` from the first build and follows
`docs/new-game-checklist.md`, `robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md` and anomaly-observatory's
"ServerStorage, not the zone". The model document for layout and depth is `meteor-drop-tycoon/DESIGN.md`, the
nearest sibling in genre; section 2 says what this game does differently from it and from the other fifteen.

## How to read the numbers

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.py`. Run it from `outpost-zero/` with `py -3 design/model.py` (about 13 s, deterministic: two runs gave the same md5, `31733f82...`). The output is saved as `design/model.out.txt`. The model is a design-time tool, not game code. |
| **[T]** | Taken from a template this game copies (`plus1-jump`, `meteor-drop-tycoon`, `deep-vein`, `stormgrow`, `fork-tower`, `anomaly-observatory`), where it was measured or reviewed. The source is named. Spec counts marked "today" were run on 2026-10-07. |
| **[R]** | A design rule or arithmetic, worked inline. |
| **[A]** | An assumption. The player profiles are assumptions, and every number derived from them inherits that. The first real play session replaces them. |

**Why the model is Python.** The luau CLI under the session scratchpad was deleted at 17:43 on 2026-10-07, in the
middle of this task (every file in the scratchpad went; the directories stayed), and it did not come back in a
5-minute wait. Downloading a new one needs the owner's permission, so the model was written in Python 3.13, which is
installed. It is written to port line by line to `tests/CityModel.luau` (meteor-drop-tycoon's `tests/PlotModel.luau`
is the pattern), and that port is the builder's first job: `Pacing.spec` must run the game's own `Economy` and `City`
modules, not this copy of them.

The model's player profiles, all **[A]**:

| profile | decides in | walk efficiency | notices "affordable" within | s per purchase | hazards that hit |
|---|---|---|---|---|---|
| fast | 0.4 s | 0.95 | 1 s | 0.6 | 10 % |
| **normal** | 1.0 s | 0.85 | 3 s | 1.0 | 25 % |
| slow | 2.0 s | 0.70 | 8 s | 1.5 | 40 % |
| walker (a non-exploit macro) | 0 | 1.00 | 0 | 0.125 (the rate limit) | 0 % |
| teleport (an exploit: no walking at all) | 0 | no walking | 0 | 0.125 | 0 % |

Every profile buys what the HUD's star recommends (section 4.5), +1 Jump's lesson: model the player who does what
the HUD tells them. Walking is a straight line at 16 studs/s × efficiency to 6 studs from the lot's centre. That
is a conservative stand-in for the sign post at the lot's inner edge (section 3.3), which a player reaches sooner.
The seeds vary the city layout and the small delays. The economy itself is deterministic, so the p10-p90 spreads
below are narrow. They do not measure how much real players differ; the profiles stand in for that.

---

## 1. Core loop

You land on an empty rock shelf floating above a sea of fog. On it are your Town Hall, six empty lots and nothing
else. Walk to a glowing lot and tap **BUILD**. **Homes** bring settlers and **Workshops** bring jobs, and every
settler who has a job is a **citizen**. Your **population** is your citizens, and each one earns 0.25 credits a
second. Spend the credits on more lots and on more storeys: every storey makes a building taller and adds settlers
or jobs, so the skyline rises as you play. A ★ over one lot marks the build that pays for itself soonest, and the
HUD's balance bar says whether you need homes or jobs. As your population passes each milestone a new
**district** opens. Its storeys hold more people and its buildings look different: Market Row, Sky-Rail Yard, Skyport,
Reactor Quarter, Crown Heights. Each city draws its own layout. The sky grows with your population: the fog lifts,
balloons drift by, lanterns rise at dusk, a storm rolls through, and finally the aurora comes and the sky whales
with it. Every build gives your workers **Orders for 10 minutes**: they keep earning that long after your last
build, online or off, and then wait for you. Now and then something falls from the sky. A red ring shows exactly
where it can hit, and stepping out of the ring always dodges it. Press **☕ Break** to sit down; nothing falls on
you while you rest. At about 37 minutes the Skyport opens and the **Grand Airship** docks above your Town Hall, in
view of the whole server: that is the brag moment. After it come Crown Heights at about 2 h 14 min, then a complete
skyline at about 4 h 18 min, and a place on the **Census** board, ranked by population, for everyone or just for
your friends.

---

## 2. What is new here, and where v1 departs from the brief

### 2.1 Not a copy of a sibling

Sixteen games exist. The two this could most easily repeat are `meteor-drop-tycoon` (walk to random meteors, three
machines, a sleeping Collector) and `stormgrow` (a farm under a shared weather clock). Outpost Zero shares their
plumbing (spawn, save, board, Hazards/Rest/EnvBands) and none of their play:

| | Outpost Zero | the nearest sibling |
|---|---|---|
| what you do | choose **where** to build and keep homes and jobs in balance; the city's shape is yours | meteor: chase random drops; stormgrow: time harvests against the weather |
| the progress you see | your own buildings get taller; districts with their own layouts open on the shelf | meteor: a Beacon tower; stormgrow: crop marks |
| the idle rule | **Orders**: the city works 10 min after your last *build* | meteor: the Collector sleeps 10 min after the last hand *pickup* |
| what the world shows | the frontier around your shelf filling up: fog, trade balloons, lanterns, a storm, the aurora | meteor: dusk to the galactic core; stormgrow: seasons and storms |
| the brag | a 12-second airship arrival that stays moored for the server to see | meteor: catching a Falling Star |
| the board | population | meteor: Beacon level; stormgrow: Almanac entries |

### 2.2 Departures from the radar brief

| the radar brief said | v1 does | why |
|---|---|---|
| Place a starter Outpost Pad | The Town Hall stands at the shelf's centre from the start; the arrival pad is in front of it | The first action should be the core action (building), not a setup step (checklist §4). |
| Workers and droppers, conveyors, cash that accrues | No droppers. Homes and Workshops; income = citizens × wage, paid straight into your credits | One rule the player can see: settlers need jobs. A physical dropper loop is a second simulation to build and test, and walking to collect is meteor-drop-tycoon's play (2.1). |
| Upgrade buildings | Storeys: each one makes a building one floor taller (4 studs) | The upgrade is the visual. A sky city is a skyline. |
| Unlock the next procedurally generated block (new district shape and theme) | Six districts open at population milestones. Each one's slot on the shelf, lot arrangement and zoning come from a per-profile seed | The procedural hook at the cost of three templates (section 3.2). Every layout has the same lots and prices, so a layout predicts nothing (fork-tower REVIEW-4, section 12). |
| Rarer block types at milestones (sky-rail, market district, reactor core) | They are the districts: Market Row, Sky-Rail Yard, Skyport, Reactor Quarter, Crown Heights | One thing per milestone, not two. |
| Prestige ("Relaunch Outpost") for a permanent multiplier | Cut | It needs its own pacing model. v1 ends at a complete skyline at 4 h 18 min (section 8), and prestige is the first candidate for v2 (section 17). |
| OrderedDataStore Top Tycoons board | Census board, public + friends, ranked by population | The standard's board (section 9). |
| 2-3 gamepasses (2x Cash, Auto-Collect, VIP Outpost) | None. Nothing costs Robux | 2x Cash is pay-to-win on a ranked board, and Auto-Collect sells away the play. Section 13. |
| "earns even while you're away" | Yes, bounded: until your Orders run out (10 min at most after your last build) | An unbounded offline income would rank people for being away (section 9). |
| "Free codes, daily rewards & VIP perks", "LIKE + FAVORITE" | None | One-time grants are a trust surface (checklist), and nothing is rewarded for likes (section 13). The store text promises only what the game does (section 20). |

---

## 3. The world

### 3.1 The server and the shelves

| thing | value | reason |
|---|---|---|
| Shelves per server | 6, and `Players.MaxPlayers` = 6 | One shelf per player, always. `MaxPlayers` is a Studio/Creator setting (section 18). A seventh player (a Studio test with more clients) is kicked with "This server's 6 shelves are taken. Rejoin to get a server with room." and the server logs it. |
| Shelf | a rock disc of radius 80 studs, top at y = 0 | Holds all six districts' lots with every lot corner at most 72.01 studs from the centre [M1] (limit 73), leaving a walkway of at least 6 studs inside the parapet. |
| Shelf centres | on a ring of radius 220 around the world origin, 60° apart | Neighbouring centres are 2 × 220 × sin 30° = 220 studs apart, so the rims are 60 studs apart [R]. A jump carries at most 16 × 0.54 = 8.7 studs (default JumpHeight 7.2: airtime 2 × √(2 × 7.2 / 196.2) = 0.54 s) [R], so no shelf can be reached from another. |
| Parapet | a ring at r = 79: 16 segments, each a 3-stud stone wall plus invisible collidable glass up to 12 studs | Taller than any jump from the ground (7.2) [R]. The chords stay within 79 × (1 − cos 11.25°) = 1.5 studs of the circle [R]. |
| Fall rescue | a character below y = −30 is put back on its own arrival pad, with the toast "The updraft caught you." | A 7.2-stud jump clears a 1-storey roof (4 studs + a 2-stud roof), so stepped towers may be climbable roof to roof, and a player could then jump over the glass from a tall roof. The rescue makes that harmless (section 18 item 15). |
| Below the shelves | a client-drawn cloud sea at y = −80 (section 5) | The void is scenery. Nothing on the server is below y = 0. |

### 3.2 One shelf

Shelf-local coordinates, origin at the shelf centre, −Z facing district 1.

| part of the shelf | where | reason |
|---|---|---|
| Core plaza | paved disc, r ≤ 26 | No lot comes closer than 33.06 [M1], so the plaza is open ground on every side. |
| Town Hall | centre, footprint 14 × 14 | The city's heart. It grows one piece per district (section 4.4), which is the server's public sign of progress. |
| Arrival pad (`Shelf_k.Arrival`, a SpawnLocation 6 × 1 × 6) | (0, −16), facing −Z | Between the Town Hall and district 1, so a new player lands looking at their first lots. Section 11. |
| Census board | (−10, −16), facing +X (toward the pad) | 10 studs beside the spawn, inside the plaza, where no lot can be (section 9.4). |
| District slots | six sectors 60° wide around the plaza; slot 0 is −Z | District 1 always takes slot 0, in front of the pad. Districts 2-6 take slots 1-5 in an order drawn from the profile's seed. |
| Lots | 10 × 10 plates, 6 per district, arranged by one of three templates (below), turned to face the centre | 6 lots × 6 districts = 36. |
| Locked slots | bare rock with a fog wisp and a sign: "Market Row opens at population 80" | The next goal is visible on the shelf itself. |
| Grand Airship (from district 4) | moored to a mast on the Town Hall, hull bottom at y = 120 | The tallest tower is 22 × 4 + 2 (roof) = 90 studs [R], so the hull clears every roof by 30 studs. |

**Lot templates** (u = distance from the shelf centre along the slot's axis, v = sideways; H = Home, W = Workshop):

| template | lots (u, v, zone) |
|---|---|
| rows | (44, −14, H) (44, 0, W) (44, 14, H) (58, −14, W) (58, 0, H) (58, 14, W) |
| column | (38, −7, H) (38, 7, W) (52, −7, W) (52, 7, H) (66, −7, H) (66, 7, W) |
| arc | (45.7, −14, H) (48, 0, W) (45.7, 14, H) (62.3, −14, W) (64, 0, H) (62.3, 14, W) |

Each district draws a template and a mirror (which swaps H and W), so every district has 3 Homes and 3 Workshops
[R]. Over 200 seeds [M1]: lots of one district are at least 4.00 studs apart (the rule); lots of neighbouring
districts at least 6.09. The first draft's rows and arcs reached to u = 40 and 41.7 and came within 2.09 studs of the
next district; they were moved outwards. Layouts: 3⁶ templates × 2⁶ mirrors × 5! slot orders = 5 598 720 [R].

### 3.3 A lot and its building

| part | value | reason |
|---|---|---|
| Lot plate | 10 × 10 × 0.4, the district's paving colour; it glows faintly while the ★ is on it | Interactive things read as interactive (checklist §2). 0.4 studs is a kerb a character walks over without a jump. |
| Building | 8 × 8 footprint, centred; height = storeys × 4 studs; 3 Parts: body, roof (its shape is the district's style), window strip (Neon) | Three Parts at any height keep the server budget flat (section 15). The 1-stud rim of plate left around the body shows the lot's colour and the ★ glow. A 4-stud storey is just under the 5-stud avatar, so it reads as a floor, and 22 of them stay below the airship (3.2). |
| Sign post | half a stud outside the lot's inner edge, 5.5 studs from its centre toward the shelf centre; it holds the lot's ProximityPrompt | Outside the plate and the building, on the street side, so the building never blocks it. |
| Prompt | `MaxActivationDistance` 8, `HoldDuration` 0, `RequiresLineOfSight` false; ActionText "Build Home" / "Build Workshop" / "Add storey"; ObjectText "Home 6/22 · 1.2K" | Every sign post sits at the same offset from its lot, so inside a district the posts are as far apart as the lot centres: at least 14 studs (10 + the 4-stud gap) [R]. Over 1 000 seeds and all 36 posts, across districts too, the closest two are 14.00 studs apart [M1], and `City.spec` asserts it. Two reach circles of 8 overlap only in a lens 8 + 8 − 14 = 2 studs wide between neighbouring posts [R]; there Roblox shows the nearer prompt per key, and the ObjectText names the lot. Line of sight is off because a tower beside the sign can hide it from the camera. |
| Topped out | at 22 storeys the prompt is disabled and a small billboard reads "22/22 Topped out" | Nothing to press, nothing to refuse. |

---

## 4. The economy

### 4.1 Buildings, storeys, population

* A **Home** storey adds settlers and a **Workshop** storey adds jobs. In district d, each storey adds
  `Cap(d) = 4 × 5^(d−1)`: 4, 20, 100, 500, 2 500, 12 500.
* **Population = min(settlers, jobs)**. Settlers without jobs and jobs without settlers count for nothing; the HUD
  shows both ("Settlers 120 · Jobs 96: build a Workshop ★").
* **Income = 0.25 credits per second per citizen**, paid into your credits while your Orders run (4.3).
* Storey s (s = 1 is the build) of a lot in district d costs `Price(d, s) = 15 × 6^(d−1) × 1.35^(s−1)` credits.
* A building tops out at **22 storeys**.
* Population never falls: nothing is demolished and nothing is lost [R]. Every rule keyed on population
  (districts, bands, the board) is therefore monotonic. The one exception is a corrupt record's recovery (10.1).

| number | value | reason |
|---|---|---|
| `Wage` | 0.25 credits/s per citizen (15 a minute) | With `Cap(1)` 4 and storey 1 at 15, a Home + Workshop pair (30 credits) pays for itself in 30 / (0.25 × 4) = 30 s at the start [R]. That gives 7 purchases in the first minute [M5]. In the design sweep, wage 0.5 with storey 1 at 10 gave 21 (a press every 3 s), and wage 0.2 with storey 1 at 25 gave 5. |
| `StartCredits` | 30 | Exactly the first Home and the first Workshop [R], so the core action needs nothing first: first build at 3.3-3.9 s [M5]. |
| `Cap(d)` ×5 and price ×6 per district | 4 × 5^(d−1); 15 × 6^(d−1) | A new district's first storey is 1.2× worse per credit than the previous district's (0.2667 → 0.1072 capacity per credit across d1-d6 [M2]), so later bands last longer (3.4, 8.8, 24.9, 39.0, 57.7 min [M4]). Yet it is cheap against the income at its opening (d6 storey 1 costs 116.64K [M2] against 46.25K credits/s at population 185 000 [R]: 2.5 s), so no district opens on a long save. |
| `Growth` | 1.35 per storey | Sets the pace. Brag minutes [M8]: 1.30 → 25.6, 1.33 → 31.9, **1.35 → 37.1**, 1.37 → 43.4, 1.40 → 55.2. |
| `MaxStoreys` | 22 | The dead-end fix (4.3). 22 storeys reach 88 studs, a real skyline over a 5-stud avatar. |
| District thresholds | population 80 / 900 / 6 400 / 35 000 / 185 000 | Fitted by bisection to target entries of 3.5 / 12 / 36 / 75 / 135 min, then rounded. Measured: 3.4 / 12.2 / 37.1 / 76.1 / 133.9 min [M3]. |
| Full city | 36 lots × 22 storeys = population 1 031 184, income 257.80K credits/s [M2] | Below the board's exact-encoding limit with room to spare (section 9.2). |

### 4.2 Credits

Credits are minted only by the server, by its own clock × the population it computed × the wage, and only while the
Orders run. They are spent only through the lot prompts. The HUD shows them compact ("1.2K", "3.4M") with
"+X/min". There is no other currency, nothing to collect and nothing to sell.

### 4.3 Orders: the idle rule

Every build or storey sets the player's **Orders to 10 minutes**. The city earns while the Orders run and stops
when they run out. The HUD chip reads "📋 Orders 8:12"; when they have run out it reads "💤 Workers idle: build
anything to put them back to work".

**The safety net:** the city also keeps earning, with or without Orders, **while no storey you could build is
affordable**. It stops being needed once you can afford one, and it plays no part in a complete city.

**Offline:** the workers finish their Orders while you are away. On the next join, the server credits
`income × (seconds the city worked since savedAt)`, where the city works until `ordersUntil` and then, under the
safety net, only until the credits reach the cheapest storey. Both are pure functions of the saved profile and
`os.time()` (`Economy.offline`, unit-tested). The toast: "Your workers finished their orders while you were
away: +3.2K".

| number | value | reason |
|---|---|---|
| `OrdersSeconds` | 600 | The longest gap between two purchases of an honest normal player in 4 h is 262.5 s (slow: 265.3), with 0 lapses in 200 sessions [M3]: a 2.3× margin. Ten minutes is shorter than Roblox's 20-minute idle kick, so the common anti-AFK trick buys at most 10 minutes [M7]. meteor-drop-tycoon's Collector uses the same window for the same reason [T]. |
| `MaxStoreys` 22, the dead-end rule | the dearest storey costs at most half the Orders | **Found by the model, then fixed.** With 30 storeys, the cheapest storey left in an almost complete city cost 694 s of income: the Orders ran out before the player could afford it, and a perfect player's city stopped earning for good at population 1.22M after 9.2 h. Measured worst waits: 30 storeys 694 s, 26 → 716 s, 25 → 552 s, 24 → 427 s, **22 → 256 s** [M9 at 22; the others by setting `MaxStoreys` and re-running Part 9]. At 22, d6 storey 22 costs 63.66M, which is 256.3 s of income in the worst end state (all three d6 Homes or Workshops one storey short), under the rule's 300 s [M2]. `Economy.spec` asserts the rule from Config. |
| Safety net | engaged 0 times in 70 macro and AFK stalls [M7]; 0 Orders lapses for every profile [M3] | It is never reached in honest play or in the cheap macros. It exists for one case: a returning player whose Orders ran out offline after spending everything. Without it, that player would stand in a city with no income and nothing affordable, forever. |

### 4.4 The six districts

| # | district | opens at population | storey capacity | storey 1 price | style: walls / roof | Town Hall gains (server, public) |
|---|---|---|---|---|---|---|
| 1 | Landing Field | 0 | 4 | 15 | timber planks, canvas cream / pitched | timber hut with a windsock mast |
| 2 | Market Row | 80 | 20 | 90 | pastel plaster / flat, striped awning | a clock face |
| 3 | Sky-Rail Yard | 900 | 100 | 540 | brick (150, 80, 60) and iron / sawtooth with a chimney | a rail-station canopy |
| 4 | **Skyport** | **6 400** | 500 | 3.24K | white and navy / flat with a radio mast | the mooring mast and the **Grand Airship** (section 8) |
| 5 | Reactor Quarter | 35 000 | 2 500 | 19.44K | steel with a teal Neon band / dome | a teal reactor halo ring |
| 6 | Crown Heights | 185 000 | 12 500 | 116.64K | white stone, gold trim / spire | the gold Crown Spire |

Each building's facade colour is drawn from its district's three-colour palette with the layout seed, so two
Market Rows are not the same. The skyline at the brag: districts 1-3 average 18.3 / 18.0 / 17.0 storeys (73 / 72 /
68 studs) [M11].

### 4.5 The HUD's star: the next build

`Economy.bestNext(state)` is pure and server-side. The owner receives it in `State`, and the client puts a ★ over
that lot's sign and the line "★ Workshop · storey 7 · 1.2K · ready in 0:18" on the HUD.

```
side      = Homes if settlers < jobs, Workshops if jobs < settlers, both when equal
candidate = a lot on that side, in an open district, under 22 storeys,
            whose next storey costs at most credits + income × OrdersSeconds
score     = wait + payback, lower is better
            wait    = max(0, price - credits) / income
            payback = 2 × price / (Wage × Cap(d))      -- a pair of storeys, one each side
bestNext  = the lowest score; ties go to the nearer lot; with no candidate, the cheapest storey on that side
```

"★ marks the build that pays for itself soonest, counting the wait" is what the HUD's help line says. **The first
draft was wrong, and the model caught it:** it starred the best capacity per credit, which put the ★ on each new
district's first storey the moment the district opened, and the player stood waiting for it for minutes (the
longest gap between purchases reached 570 s in the design sweep). The payback rule ends that: no gap over 265.3 s in 4 h of any profile [M3].

---

## 5. The environment bands

### 5.1 What triggers them

**The trigger is the player's population: the game's own logic, never time.** The story is the frontier coming
alive around a growing city. Each band opens with the district that opens at the same population, so the
district sign, the band chip and the sky always agree (+1 Jump review finding 7 [T]):

* **Named by the integer population** through `EnvBands.indexAt`, the same number as `leaderstats.Population` and
  the board.
* **Blended by the same number.** Each band fades in over `fade` population before its `from`, eased by EnvBands'
  smoothstep, so the last purchases before a milestone move the sky in visible steps. Every written value then
  glides with a **1.5 s half-life** (meteor-drop-tycoon's value for a deliberate purchase [T]). Lighting is
  written at most 10×/s and only on change [T].
* **Title card** ("☀️ CLEAR MORNING · Market Row is open") when a purchase takes you into a band you have not seen
  this session. A player who joins already in a band gets a quiet chip instead, and the first card waits for the
  saved state to load (+1 Jump's slow-load lesson [T]).
* `EnvBands.luau` is plus1-jump's, verbatim, with its spec (124 passed today [T]).

### 5.2 The six bands

Minutes are a normal player's median time to enter the band [M3]; durations are medians [M4].

| # | band | from (fade) | normal min | lasts | light and colour | scenery (client) | critters (client) | weather (client) | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌫️ Fogbound Dawn | 0 | 0.0 | 3.4 min | dawn, `ClockTime` 6.4, pale rose-grey, thick haze | fog banks rolling over the parapet, the cloud sea hidden, 5 bare rock spires (empty shelves) in silhouette | 3 gulls circling | fog wisps, 4/s | none |
| 2 | ☀️ Clear Morning | 80 (30) | 3.4 | 8.8 min | morning, `ClockTime` 9.0, fresh blue | the fog lifts: the cloud sea 80 studs below, 5 far shelves with tents | 5 swifts | dandelion seeds, 5/s | loose crate |
| 3 | 🎈 Trade Winds | 900 (300) | 12.2 | 24.9 min | midday, `ClockTime` 13.0, bright and saturated | pennant strings over the plaza, a far sky-rail line linking the far shelves | 3 hot-air balloons drifting past | blowing leaves, 8/s | loose crate, sandbag |
| 4 | 🏮 **Lantern Dusk** | **6 400** (2 000) | **37.1** | 39.0 min | sunset, `ClockTime` 17.9, gold-pink, strong bloom | the far shelves' windows light up | sky lanterns rising out of the cloud sea (12 at a time) | warm sparks, 10/s | loose crate, spent lantern |
| 5 | ⛈️ Storm Front | 35 000 (10 000) | 76.1 | 57.7 min | night, `ClockTime` 20.5, violet-blue | silent lightning inside the cloud sea (at most one flash per 3 s), a storm wall on the horizon | 3 storm petrels | rain, 40/s | lightning strike, hailstone |
| 6 | 🌌 **Aurora Crown** | 185 000 (50 000) | 133.9 | open-ended | clear night, `ClockTime` 23.0, teal-violet | aurora curtains (4 Beams), 3 000 stars | 2 sky whales drifting slowly past the shelves | snow glitter, 15/s | ice shard, lightning strike |

Reasons for the band numbers:
* **`from` values** are the district thresholds (4.1), fitted to put the brag at 37.1 min and the last band at
  133.9 min [M3]. The shortest band lasts 3.38 min at the minimum across seeds [M4], above the 2 minutes +1 Jump
  holds itself to [T].
* **`fade` values** are 27-38 % of their band's `from` (30/80, 300/900, 2 000/6 400, 10 000/35 000, 50 000/185 000),
  and each satisfies `EnvBands.validate`'s rule `fade ≤ from − previous from` (30 ≤ 80, 300 ≤ 820, 2 000 ≤ 5 500,
  10 000 ≤ 28 600, 50 000 ≤ 150 000) [R].
* **`ClockTime` only rises** (6.4 → 23.0) and stays below 24, because a linear blend from 23.5 into 0.0 would sweep
  the sky backwards through the day (meteor-drop-tycoon's rule [T]). `EnvConfig.spec` asserts it.
* **Weather rates** peak at 40/s alone and 55/s for the heaviest blend (rain + glitter), under the 60/s budget;
  `EnvBands.capRates` keeps at most 2 kinds on [R, T].
* **Lightning flashes** are distant, never full-screen, and at most one per 3 s [R: under the common
  photosensitivity limit of three flashes a second].

Starting lighting values (every band defines the same fields, as `EnvConfig.spec` requires [T]):

| band | Brightness | Ambient / OutdoorAmbient | Atmosphere Density, Color | ColorCorrection TintColor | Bloom Intensity |
|---|---|---|---|---|---|
| Fogbound Dawn | 1.6 | 110,105,115 / 150,140,155 | 0.45, 215,200,210 | 240,232,240 | 0.8 |
| Clear Morning | 2.6 | 120,125,135 / 160,170,185 | 0.30, 200,220,245 | 250,250,255 | 0.9 |
| Trade Winds | 3.0 | 125,125,130 / 170,175,185 | 0.25, 205,225,250 | 255,250,240 | 1.0 |
| Lantern Dusk | 2.2 | 120,100,95 / 170,135,120 | 0.30, 255,190,150 | 255,232,210 | 1.5 |
| Storm Front | 1.1 | 85,85,110 / 105,105,140 | 0.40, 110,105,150 | 215,215,245 | 1.2 |
| Aurora Crown | 1.0 | 90,105,120 / 110,135,160 | 0.10, 60,90,120 | 220,245,240 | 1.6 |

The OutdoorAmbient floor keeps the shelf readable at night. The window strips, the ★ lot and the Town Hall's
pieces are Neon, so they glow whatever the light does. These are starting points that only real rendering can
judge (section 18). **No colour anywhere is red except the hazard ring:** `EnvConfig.spec` runs meteor-drop-tycoon's
`isReddish` test (r ≥ 180, g ≤ 110, b ≤ 110; the ring is 255, 40, 40) over every band, district, critter, weather,
lantern and window colour [T]. The Sky-Rail brick (150, 80, 60) passes because r < 180.

**The server's starting light** is `Fx.applyLighting(Fx.Presets.Dawn)`, a new preset equal to band 1, so the
client's first blend takes over with no jump. Adding one preset is the only edit to the copied `Fx.luau`, as
meteor-drop-tycoon added `Dusk` [T].

**Everything in 5.2 is client-only**: built locally, non-collidable, non-queryable, non-touchable, and it
replicates nothing (+1 Jump's leak review [T]). Your sky follows your population, so you see your neighbours'
cities under your own sky. The one server-side change per band is the Town Hall's new piece (4.4), which
everyone sees. That is a public brag, and population is public anyway (leaderstats).

---

## 6. Hazards: things fall off the frontier

**Template.** Copy `meteor-drop-tycoon/src/shared/Hazards.luau` and its `tests/Hazards.spec.luau` (153 passed,
0 failed today; the spec requires nothing but the module). That file is plus1-jump's `Hazards.luau` with the
2026-09-27 `threatLive` rule, plus deep-vein's marked **vertical kinds** section, unchanged. Diffed today
against plus1-jump: meteor's header comment and the marked section are the only differences [T]. Why this game needs the adaptation is
meteor's argument and it holds unchanged: a shelf is flat ground, and a third-person camera on flat ground looks
down, so a sideways lane that starts inside the camera's pitch window starts underground. The only honest lane
is from above. A vertical kind's telegraph is the ring at the player's feet, on screen wherever the camera looks.

**The rule the standard asks for, exactly:** the red ring is the hazard's zone, radius `hitRadius + PlayerRadius`,
centred where the player stood when the lane last aimed. A hit needs the player inside the ring *and* the object
passing within reach, so **stepping out of the ring in any direction always dodges** (+1 Jump review round 2 [T]).

| kind | bands | height studs | fall s | warning s | locks s before impact | pass s | hitRadius (ring radius) | knock studs/s |
|---|---|---|---|---|---|---|---|---|
| loose crate (off a passing freighter) | Clear Morning, Trade Winds, Lantern Dusk | 60 | 0.8 | 3.2 | 1.6 | 1.0 | 2.4 (3.9) | 36 |
| sandbag (off a balloon) | Trade Winds | 55 | 0.7 | 3.2 | 1.6 | 1.0 | 2.0 (3.5) | 32 |
| spent lantern | Lantern Dusk | 45 | 1.4 | 3.4 | 1.7 | 1.0 | 2.0 (3.5) | 28 |
| lightning strike | Storm Front, Aurora Crown | 90 | 0.3 | 3.6 | 1.8 | 1.0 | 2.6 (4.1) | 40 |
| hailstone | Storm Front | 70 | 0.7 | 3.2 | 1.6 | 1.0 | 2.2 (3.7) | 34 |
| ice shard | Aurora Crown | 70 | 0.6 | 3.2 | 1.6 | 1.0 | 2.2 (3.7) | 36 |

| number | value | reason |
|---|---|---|
| `IntervalMin` / `IntervalMax` | 120 / 180 s of non-rest time on your own shelf | The template's rarity [T]: +1 Jump measured one hazard per 150.9 s over 20 h of scheduler, never two at once. Here: 13 hazards before the brag for a normal player (13-14 across seeds) [M6], about one per 2.6 min after the hazard-free start. |
| First hazard band | 2 (Clear Morning) | A new player's first 3.42 min are hazard-free [M4, M6]. A due hazard in a quiet band is re-rolled, not held (the template's rule [T]). |
| `MinTelegraphSeconds` / `MinCommitSeconds` | 3 / 1.5 | The template's minimums [T]. Every kind meets them, and `fall ≤ commit` holds for each (0.8 ≤ 1.6, 0.7 ≤ 1.6, 1.4 ≤ 1.7, 0.3 ≤ 1.8, 0.7 ≤ 1.6, 0.6 ≤ 1.6), so nothing falls before its lane locks (deep-vein's validation [T]). |
| Ring radius | 3.5-4.1 studs | Leaving it from its centre takes at most 4.1 / 16 = 0.26 s, against at least 1.6 s between lock and impact [R]. |
| `PlayerRadius`, `AimJitter`, `MaxRetargetSpeed` | 1.5, 0.8, 1.5 | The template's values [T]. With the jitter the object lands up to 0.8 studs off centre, so a hit near the ring's edge is a near miss, never an unfair hit. |
| `KnockLift` / `KnockSeconds` | 8 studs/s (cap 15) / 0.9 s | A shove and a stumble. The lift peaks at 8² / (2 × 196.2) = 0.16 studs [R], far under the 12-stud parapet. |
| Hit cost | about 1.9 s, nothing else | **[A]**, as in meteor-drop-tycoon's model. No credits, storeys or Orders are ever touched. |
| `SpreadDegrees` / `ViewPitchDegrees` / `KindFitDegrees` | 0 / 20 / 25 | Kept only because `Hazards.validate` requires them; vertical kinds ignore the view cone [T]. |

**Where and when** [R]. A hazard launches only while the player is grounded, on their own shelf, not resting and
not in the Grand Airship's arrival. The arrival passes `ctx.canDodge = false`, the template's existing hold, from
the title card until 3 s after mooring, so the brag can never be knocked. A roof is ground: a player on a roof can
be hit and pushed off it, and Roblox has no fall damage, so that costs a short drop.

**Telegraph** (client): the object hanging high above (a crate, a sandbag, a dim lantern, a crackling bolt), a
light pillar from it down to the ring, the red ring at the player's feet, and a HUD banner "⚠️ CRATE INCOMING:
step out of the red ring". At the lock the pillar and the ring turn solid red and the banner says "MOVE!".

**Client-only, and why** (+1 Jump's split [T]): the schedule, the telegraph, the hit test and the knock run on the
owner's client. A hazard only harms the local player, whose character physics that client already owns, and it
grants and removes nothing. An exploiter who deletes hazards avoids a 1.9-second stumble and gains nothing else.
The price: other players can see you stumble with nothing hitting you (section 18).

---

## 7. Rest: ☕ Break

Copy `plus1-jump/src/shared/Rest.luau` and its spec (55 passed today [T]) **verbatim**.

* **☕ Break button** (right edge, section 15). Your avatar sits down where it stands, the camera tilts slowly up
  to your band's sky piece (the fog banks, the balloons, the lanterns, the storm wall, the aurora), and the chip
  says "☕ On a break: nothing falls on you. Orders 8:12". Press the button again, move, or press a lot's BUILD
  (which ends the break on the client) to carry on.
* **Idle rest**: standing still for 60 s also rests you (hazards off, no camera change), which keeps AFK players
  safe [T].

| number | value | reason |
|---|---|---|
| `IdleSeconds` | 60 | stormgrow's REVIEW-1 B2 found its 20 s put a farmer at rest for about half of play, freezing the hazard clock [T]. Here a normal player stands still while waiting for credits: at 20 s the idle rest takes 16.6 % of the first hour, at 45 s 1.7 %, at **60 s 0.5 %** (max 1.2 %), at 90 s 0.0 % [M10]. Of the values measured, 60 is the shortest whose worst seed stays under 1.5 %. |
| `WakeGraceSeconds` | 0.4 | +1 Jump's [T]. |
| `PendingSeconds` | 7 | A break requested with a hazard inbound is queued. The queue must outlive the longest flight (lightning: 3.6 s warning + 1.0 s pass = 4.6 s) by more than 2 s, as +1 Jump sized its own [R, T]. |
| `RequireGrounded`, `BlockWhileThreat`, `WakeOnMove` | true | `WakeOnMove` and `BlockWhileThreat` are mandatory in `Rest.validate` [T]. |

**Why the break can never be an exploit:**
1. **It pauses only hazards.** The hazard clock freezes during a break and is never reset, so toggling the break
   cannot thin hazards out (measured 142 / 142 / 142 in +1 Jump [T]).
2. **It earns nothing that standing still does not.** Income depends only on population and Orders, and the
   Orders keep counting down during a break: a break never renews them.
3. **It is not a panic button**: it cannot start with a hazard inbound (the template's queue [T]).
4. **Nothing races a clock.** There is no round and no timer to beat, and no penalty for pausing beyond the Orders'
   10 minutes, which apply to everyone the same way.

Roblox's own 20-minute idle kick still applies, and nothing is lost when it fires: the profile is saved within
7 s of every change and on leaving (section 10), and the workers finish their Orders offline.

---

## 8. The brag moment and the long-term goal

**The Grand Airship.** The purchase that takes population to 6 400 opens the Skyport. The server adds the mooring
mast to the Town Hall and tells every client (`Announce`). Each client flies its own copy of the Grand Airship in
from 1 500 studs out to the mast over **12 s**. The owner gets a title card, "⚓ SKYPORT OPEN! The Grand Airship is
coming", and at the mooring a white flash, an FOV punch and a camera shake (FxClient [T]). The whole server gets
the toast "<name>'s city welcomed the Grand Airship!". When the 12 s are up the server places the moored airship
(about 12 Parts, a gold lamp on the gondola), the client copies are removed, and it stays moored from then on, in
view of everyone in the server.

* **Measured: 37.1 min** median for the normal follower (p10 37.0, p90 37.2). Fast 36.8, slow 38.8, the
  walker macro 36.6, the teleport exploit 36.5 [M3]. The standard's window is 30-45 min. Skill barely moves it:
  income, not walking, sets this game's pace (section 9.1).
* **Not luck.** The Skyport opens at a population, never a roll.
* **No grant, so nothing to dupe.** The airship and the Skyport follow from population, which follows from the
  saved lots. The only flag is cosmetic: `airshipSeen`, set when the flight finishes. A player who leaves
  mid-flight sees the flight once more on the next join. A repeat costs nothing and grants nothing.
* The skyline at that moment: districts 1-3 average 17-18 storeys (68-73 studs) [M11]. That is the thumbnail.

**The long-term goal: Crown Heights** (band 6, population 185 000) at a measured 133.9 min for the normal follower
(p10 133.8, p90 133.9; slow 136.3) [M3]. That is 3.6× the brag time and under 3 hours. The Crown Spire rises on the
Town Hall and the sky whales come.

**Beyond it: a complete skyline.** Every one of the 36 lots at 22 storeys, at a measured 4.30 h for the normal
follower (4.28 h for the walker macro) [M9, M11]. The Crown Spire's gold beam lights, the server toasts "<name>
completed their skyline!", and the board ranks everyone who got there by who got there first (section 9). That is
v1's end, stated plainly: prestige, which would continue it, is cut (section 17).

---

## 9. The Census: public and friends highscores

### 9.1 The metric: population

Ranked on **population**, with ties going to whoever reached that population first. The board shows the band
emoji beside each number, so "🏮 6 400" reads as a player with a Skyport.

**Why a script cannot inflate it.** Follow one citizen back to its source:
1. Population is computed by the server from the saved storeys: `min(settlers, jobs)`.
2. A storey is added only by the server, in the lot prompt's server-side `Triggered`, after checking that the
   shelf is the player's, the district is open, the lot is under 22 storeys, the rate limit, and that the
   server's own credit count covers the server's own price.
3. Credits are minted only by the server's clock × that population × the wage, and only while the server-side
   Orders run (or under the safety net). Orders are renewed only by step 2.

So no client input makes credits arrive faster, makes storeys cheaper, or adds population without paying.
**Measured:** an exploit that teleports and fires prompts from anywhere reaches the brag 0.6 min sooner than the
normal player (36.5 vs 37.1) and a perfect walking macro 0.5 min sooner [M3]: automation buys about 1.6 %.

**What a macro can and cannot do**, from the normal player's state when the Skyport opens (population 6 400) [M7]:

| over the next 8 hours | population |
|---|---|
| AFK, or the common anti-AFK jiggle | **×1.000**: the city earns 10 more minutes of income, then stops |
| a macro pressing one lot's prompt at the rate limit (the best lot for it) | **×1.000**: it tops that lot out at 22 storeys, and one side alone adds no citizens |
| a route macro walking between one Home lot and one Workshop lot (the best pair) | ×2.719 |
| the normal human | ×161.123 (the city completes) |

**Residual risk, stated:** a bot that plays the whole city for you climbs at a human's pace. No cumulative metric
can stop that; this one makes sure it is never faster than a human, and that the cheap macros get nothing.

Why not credits or lifetime credits: they grow by orders of magnitude (the full city earns 257.80K a second
[M2]) and would break the tie-break encoding's exact range. Population is bounded at 1 031 184 [M2].

### 9.2 Storage

| thing | value | reason |
|---|---|---|
| Store | OrderedDataStore `OutpostZero_Census_v1`, key `u_<userId>` | The standard [T: complete-game-standard.md §3]. |
| Value | `population × 2e9 + (2e9 − popAt)` | The standard's encoding. `popAt` is the profile's `os.time()` when that population was first reached, not the write time. The largest value is 1 031 184 × 2e9 + 2e9 = 2.06 × 10¹⁵, under 2^53 = 9.0 × 10¹⁵ [M2]. `popAt` stays under 2e9 until May 2033 [R]. |
| Write | only when the population beats the last value this server wrote or read for the player; coalesced to at most one write per player per 60 s, plus one on leaving | "Write only when the metric improves" [T]. Early on the population rises every few seconds (7 purchases in the first minute [M5]), so writing each one would waste budget. 6 players × 1/min = 6 writes a minute per server [R]. |
| Written from | the saved profile only, after a save has landed | stormgrow's REVIEW-1 rule: the board never shows what a save did not keep [T]. |
| Seed of "last value" | one pcall'd `GetAsync` of the player's own key at join | So a rejoin never writes a lower or equal value. |

### 9.3 The two views

* **Public**: `GetSortedAsync(false, 10)`, cached server-side for 60 s and shared by every player in the server, so
  a server makes at most one sorted read a minute [T].
* **Friends**, fetched only when the player switches to it: `Players:GetFriendsAsync(userId)`, pcall'd, capped at
  the first **200** friend ids [T: the standard's example]. Each friend's score is one `GetAsync` on the board
  store, at most **1 per second per server**, and only while `GetRequestBudgetForRequestType(GetAsync)` stays above
  a reserve of 10. Results are cached for 300 s server-wide, and friends in the same server are read from memory.
  The view fills in as scores arrive ("Loading friends… 34 / 120"), and 200 friends take at most 200 s [R]. The
  viewer's own row is always present. (meteor-drop-tycoon's numbers [T].)
* **Empty friends view**: "None of your friends is on the Census yet. Your population: 🏮 6 400. Invite someone:
  the sky has room for six cities." If `GetFriendsAsync` fails or is missing: "Friends list unavailable right now.
  Showing your own row." That covers `robloxemu`, which has no `GetFriendsAsync`.
* **Names** come from `Players:GetNameFromUserIdAsync`, pcall'd and cached for the server's lifetime. **A name is
  never stored**, only user ids.

### 9.4 The physical board

Each shelf has a **Census** board beside its arrival pad (3.2): a framed board Part with a `ProximityPrompt`
("Census: switch Public / Friends", `MaxActivationDistance` 14: the board stands 10 studs from the pad's centre and
13.3 from its far corners, so it is in reach from anywhere on the pad [R]). The
rows render in a **SurfaceGui that lives in the owner's PlayerGui with `Adornee` set to their own board**, so each
player's friends and rows reach only that player, sent by the server over the `Board` remote (meteor-drop-tycoon's
design [T]). A visitor would see only the title plate, and shelves cannot be visited anyway (3.1). A prompt
triggered by someone who is not the owner answers "This is <name>'s Census board. Yours is beside your own
arrival pad."

---

## 10. Data model

### 10.1 What persists: DataStore `OutpostZero_v1`, key `u_<userId>`

```
{
  session   = string | nil,   -- owner token: one HttpService:GenerateGUID per server session (fork-tower `old.session`)
  jobId     = string,         -- diagnostics only
  lockUntil = integer,        -- os.time(); renewed by every write
  data = {
    v           = 1,
    seed        = integer 1..2147483646,  -- the layout seed: drawn once, by the server's Random.new(), at profile creation
    credits     = number >= 0,
    lifetime    = number >= 0,            -- all credits ever earned (the footer of your own Census row)
    lots        = { ["1_1"] = 0..22, ... },  -- storeys per lot, string keys "<district>_<index>"; absent = 0
    savedAt     = integer,                -- os.time() of this write; ALWAYS written together with credits
    ordersUntil = integer,                -- os.time() when the workers' Orders run out
    popAt       = integer,                -- os.time() when the current population was first reached
    airshipSeen = boolean,
    tutorial    = integer 0..3,           -- section 14's hint step, so a rejoin resumes and never repeats
  },
}
```

* **Everything else is derived**, never stored, so it can never disagree: each lot's zone and position come from
  `City.layout(seed)`; settlers, jobs and population from the lots; open districts and the band from population.
* **No integer keys anywhere** (checklist: JSON turns sparse integer keys into strings). Lot keys are strings.
* **`savedAt` and `credits` travel together.** The offline earnings (4.3) are computed at load from `savedAt`. A
  write that updated one without the other would pay the same absence twice. Every write is one `UpdateAsync` of
  the whole document [R].
* `Save.normalise` (pure, spec'd) makes a loaded record safe: a non-number gives the default, a negative gives 0,
  storeys are floored and clamped to 0..22, and NaN or infinity gives the default. A seed outside its range can only
  come from a corrupt record. It is redrawn, because a new layout is better than a city that cannot load, and the
  population is recomputed from the new zones, which can lower it. The board keeps its best value, because it only
  ever writes an improvement (9.2). A record with `v` greater than 1 is never written (stormgrow's
  REVIEW-1 [T]).
* **Clocks**: `os.time()` for everything persisted; `tick()` for in-session timers, because `tick()` is the clock
  `robloxemu` advances (deep-vein measured that `os.clock()` barely moves headless [T]).
* **Session lock with an owner token** (fork-tower REVIEW-4 §10 [T]): the load is one `UpdateAsync` that takes the
  lock (writes `session = token`) unless another live session holds it; `canSave` is true only if this session
  wrote its token; **every** later write first checks `old.session == token` and cancels (returns nil, marks the
  session lost, stops saving) when it does not match.
* **Non-saving session** (store unavailable, locked elsewhere, or token lost): everything works in memory, and a HUD
  banner says "Progress is not being saved this session". A load is tried 3 times (1 s, 2 s apart); a lock is
  re-read every 5 s for up to 15 s at the join; a session that still starts read-only re-checks every 15 s and
  takes over once the lock is gone and the record is exactly what it read (steal-a-cryptid's and meteor's REVIEW-1
  fixes [T]). Its offline earnings are shown but never saved, so the next saving session computes them once.
* `GetDataStore` is itself pcall'd: unwrapped, it raises in an unpublished place and kills the server script [T].
* **No one-time grants exist in v1**: no codes, no rewards, no airship payout. The checklist's atomic-grant trap has
  nothing to bite [R].

| number | value | reason |
|---|---|---|
| `Save.FlushTickSeconds` | 7 | Coalesced writes, at most one per player per tick [T]. 6 players × 60 / 7 = 51.4 `UpdateAsync` a minute against a budget of 60 + 10 × 6 = 120 [R]. |
| `Save.AutosaveSeconds` | 60 | Renews the lock. Every real change marks the profile pending, so it reaches the store within one 7 s tick [T]. |
| `Save.LockSeconds` | 120 | Twice the autosave, so a live session always renews in time [T]. |

### 10.2 What is server-only (Lua tables in `Main.server.luau`)

The layout seed; each profile's credits and Orders; the server's `Random.new()`; pending-save flags and session
tokens; prompt rate-limit buckets; board caches (public rows, friend scores, names).

### 10.3 What lives in `ServerStorage` (anomaly-observatory's "ServerStorage, not the zone" [T])

* `ServerStorage.CityKit`: the building pieces per district style, the Town Hall's six pieces, the Grand Airship.
  The server clones them. Nothing in them is secret, but clients have no reason to hold them.
* `ServerStorage.CityInfo.<userId>`: attributes `Shelf`, `Seed`, `Credits`, `OrdersUntil`, `Population`. They exist
  **only** for the headless checks and tools, as anomaly's `PassInfo` does [T].

**Is the seed a secret?** No, and the design does not need it to be, but it stays server-only anyway. It decides
which slot each district takes, its template, its mirror and its facade colours. Every layout has the same
lots, prices and capacities, so knowing a future district's shape buys nothing. The most it changes is walking
time, at most 5.61 s across the shelf [M1], and walking barely moves the pace (the teleport exploit gains 0.6 min
at the brag [M3]). That is different from fork-tower, where the generator decided the traps (REVIEW-4 §1 [T]).

### 10.4 What replicates, and why it is safe

| replicates | why that is fine |
|---|---|
| Every shelf Part: rock, plaza, parapet, Town Hall and its pieces, arrival pad, board frame, locked-district signs, lot plates, sign posts, buildings, the moored airship | Nothing about a city is secret. Building heights are the point. |
| Lot prompts with their texts ("Build Home", "Home 6/22 · 1.2K") | Present prices from public Config. |
| `leaderstats.Population` | Public by design: the board shows the same number. |
| `State` (server → owner only, `FireClient`): credits, lifetime, income, settlers, jobs, population, Orders seconds left, the safety-net flag, the ★ (lot key, action, price, seconds to afford), tutorial step, `saving` | All of it is the owner's own *present* state. |
| `Board` rows (server → the viewer only) | That player's own view of public data and their own friends. |
| `Announce` (server → all) | The airship and skyline toasts, which are public. |
| Shared modules in `ReplicatedStorage` (Config, Economy, City, Board, EnvBands, Hazards, Rest, …) | Public code. The only seeded thing is the layout, and its seed never leaves the server (10.3). |

**The attribute rule: no attribute on any Instance under `workspace` or `ReplicatedStorage`.** Instance names carry
only visible facts (`Shelf_3`, `Lot_2_4`). The headless check enumerates every attribute under both and requires
the list to be **empty**: fork-tower's wire inventory in its strictest form [T].

### 10.5 Remotes (`ReplicatedStorage.CityRemotes`)

| remote | direction | content |
|---|---|---|
| `State`, `Toast`, `Fx`, `Board` | server → one player | as above |
| `Announce` | server → all | the airship and skyline toasts |

**There is no client → server remote at all.** Every player action is a server-side `ProximityPrompt.Triggered`:
the 36 lot prompts and the board's toggle. The break and the hazards are client-only and grant nothing. The ★ "Show
me" beam is client-only. With no remote, there is no remote payload to validate or abuse [R].

| number | value | reason |
|---|---|---|
| Prompt rate limit | 8 triggers per second per player | Above deliberate tapping on a phone. Excess triggers are dropped with at most one "Slow down" toast per 5 s [T: steal-a-cryptid]. |

---

## 11. Spawn and respawn (`robloxemu/SPAWN-ORDER.md`)

The engine's order, measured in Studio: `CharacterAdded` fires while the character is unparented at the origin; one
frame later the engine parents it **and places it on a SpawnLocation**, throwing away any CFrame written in between
[T]. deep-vein's `place()` lost exactly that race [T].

The design uses SPAWN-ORDER's **preferred pattern: let the engine place you** (grow-a-crystal, nightwatch-manor,
meteor-drop-tycoon [T]):

1. **Each shelf's arrival pad is a real, enabled `SpawnLocation`** (`Shelf_k.Arrival`, 6 × 1 × 6, top at y = 1,
   `Duration = 0` so no force-field bubble, `Neutral = true`). All 6 exist from server start, built before any player
   can join. Nothing else in the world is a SpawnLocation.
2. **`PlayerAdded` claims a free shelf and sets `plr.RespawnLocation = Shelf_k.Arrival` synchronously, before any
   yield** (before the DataStore load). The engine's placement is then already right, with no race to lose. The
   city appears as the profile loads; until then the shelf shows the Town Hall alone and every lot prompt answers
   "Loading your city…".
3. **Belt and braces in `CharacterAdded`**: wait for `char.Parent ~= nil`, bounded at 300 frames of
   `task.wait(1/60)` [T]; then **re-read** the player's shelf (it can change across the yield); if the root is more
   than 8 studs (horizontal) from the shelf's arrival pad, CFrame it 3 studs above the pad. `WaitForChild` is not
   the wait: on the server both children already exist when the event fires [T].
4. **The fall rescue** (3.1) uses the same placement: back to the player's own pad.
5. **Leaving** frees the shelf for the next joiner and resets it to the Town Hall alone. Its locked-slot signs
   return, and the next owner's seed lays out the districts again.

Headless (section 16): every shelf has exactly one enabled SpawnLocation and there are no others; after
`simulateSpawn`, each of two players stands on their **own** pad (XZ within 4 studs); the same after a respawn; with
`RespawnLocation` deliberately cleared, step 3 still puts the player on their own pad. The assertions are on XZ,
not Y, as SPAWN-ORDER §7 advises [T].

---

## 12. Anti-exploit model

vault-runners' rule [T]: do not try to detect cheating; remove what cheating is worth, and bound what cannot be
removed.

| a client can… | what it would buy | denied or bounded by |
|---|---|---|
| Teleport, speed-hack, or fire a prompt from far away | Build without walking | The server checks ownership, district, storey cap, rate and price on every trigger. Walking is not what limits the pace: the teleport exploit reaches the brag 0.6 min sooner than a normal player [M3]. |
| Trigger another player's lot prompts | Grief or build on their city | The shelf-ownership check, with a toast. Shelves are 60 studs apart over open sky (3.1). |
| Flood the prompts | Server work | 8/s limit and one toast per 5 s; writes coalesced to one per 7 s. |
| Read replicated state or traffic | Know something early | Nothing in the future replicates. The layout seed stays on the server, and every layout is worth the same (10.3). There are no attributes under workspace or ReplicatedStorage (the check enforces an empty list). |
| Send a forged remote | Anything | There are no client → server remotes (10.5). |
| Go AFK, or run an anti-AFK jiggle | Income forever | Orders: 10 minutes of income after the last build, then nothing. Population +0 [M7]. |
| Run a prompt macro at one lot | Income and rank while away | Population ×1.000 in 8 h [M7]: one side tops out and adds no citizens. |
| Run a two-lot route macro | Climb while away | ×2.719 in 8 h, against a human's ×161.123 [M7]. The residual for a full bot is stated in 9.1. |
| Server-hop or crash to duplicate | Two sessions on one profile | The session lock with an owner token on every write; credits and `savedAt` in one write; no one-time grants exist (10.1). |
| Manipulate time | Mint credits while away | Only server `os.time()` and `tick()` are read. Offline earnings stop where the Orders stop, plus at most the time to afford the cheapest storey (4.3). A negative clock difference between servers counts as 0. |
| Write the board | A fake rank | Only the server writes, from the saved profile's population and `popAt` (9.2). |
| Delete hazards or fake a break | Avoid knocks | Client-only, grants nothing; a hit costs about 1.9 s (section 6). |
| Jump off the shelf | Get stuck or leave the map | The 12-stud parapet glass, and the rescue below y = −30 (3.1). |

---

## 13. Fair monetization

**v1 sells nothing.** No Game Passes, no Developer Products, no premium currency, no codes. Rules for any later
version, written down now so they are not negotiated feature by feature:
1. **No paid randomness, ever**: no crates, eggs, wheels or paid rerolls.
2. **No credits, wage, Orders or storeys for Robux**: no 2× income, no longer Orders, no auto-build. Each of these
   would change the bounds in section 12 and the Census.
3. **Cosmetics only**: facade palettes, roof ornaments, an airship livery, plaza decorations.
4. **Nothing rewarded for likes, favourites or follows**, and no store text that implies it.

---

## 14. The first 60 seconds

Measured with the normal profile [M5] and the section-3 geometry. The headless first-minute walk (section 16) has to
reproduce the checkable rows through the real server.

| t (s) | what happens | source |
|---|---|---|
| 0 | The character lands on its own arrival pad, facing the Landing Field's six glowing lot outlines; the Town Hall (a timber hut) behind. Fog banks, 3 gulls. Hint: "Walk to the ★ lot and tap BUILD". 30 credits. | sections 3, 11 |
| 2.3 | The nearest district-1 lot is reached: 1.0 s to decide, then 17.1 studs in 1.26 s at the normal walk [M1]. | [M1] |
| 3.3-3.9 | **The core action: the first building, a Home or a Workshop** (whichever the ★ named), rises with a construction puff. Hint 1: "Settlers need jobs: build the Workshop ★" (or "Jobs need settlers: build the Home ★"). | [M5] |
| 5.8-6.5 | The second build. Population 4, "+60/min" appears, and the Orders chip starts at 10:00. Hint 2: "Every build keeps your workers busy for 10 minutes." | [M5] |
| about 22-25 | The third purchase, a new lot (15 credits after about 15 s of income). | [M5] |
| 60 | 7 purchases (every seed); population 12. The ★ keeps moving between the six lots. Hint 3, after the third purchase: "★ marks the build that pays for itself soonest. Lost it? Tap ★ Show me." | [M5] |

Market Row opens at 3.4 min with the fog lifting: the first title card, the first band change and the first new
district [M3, M4]. The hints are the persisted `tutorial` step (0 → 3), so a rejoin resumes rather than repeats. No
step needs a purchase the player cannot afford, and every refusal on the way says why (section 15).

---

## 15. Look and HUD from the first build

**Fx from day 1** (checklist §2). Server: `Fx.applyLighting(Fx.Presets.Dawn)` as the first line. Signature
particles: `Fx.sparkle` as a construction puff on every storey added; `Fx.attachGlow` on the ★ lot's sign post (the
interactive thing reads as interactive); a gold glow on the Grand Airship's gondola lamp. A new storey grows with a
0.35 s server tween of the building's size and position. Client: `FxClient.flash` + `fovPunch` + `shake` at the
airship's mooring and at a complete skyline, and a small shake on a hazard hit.

**Phone first** (checklist §2b; `Responsive.luau` copied verbatim, spec 70 passed today [T]):
* The root Frame owns the `UIScale` and is sized `1/scale`.
* **Top centre**, stacked: credits ("1.2K credits · +3.4K/min"); the population chip ("🏮 Lantern Dusk · population
  6 400 · Reactor Quarter at 35 000"); the balance bar (settlers against jobs, with "build Homes" / "build
  Workshops" / "balanced"); the Orders chip; the ★ line. Toasts and the one-line hint sit below. Title cards are
  centred and transient.
* **Right edge, between 45 % and 70 % of the height**: two buttons, "☕ Break" and "★ Show me" (a beam from the
  avatar to the ★ lot for 4 s). **Nothing tappable in the bottom-left or bottom-right** (the thumbstick and the jump
  button). Tap targets are at least 44 screen px: `ceil(46 / scale)` design px on touch [T: vault-runners].
* Building is done at the lot, through the prompt Roblox draws itself, so the HUD has no panel to cover the world.
* The headless HUD check runs `hudcheck` at six viewports with **`overlap = true`** (rule 4b asserted), and the HUD
  re-lays out on `ViewportSize` changes.
* **Colour carries meaning**: red means a hazard ring and nothing else (section 5); gold means the ★, the airship
  and the Crown.

**No silent no-ops.** Every refusal a player can cause answers with a toast:

| refusal | toast |
|---|---|
| not enough credits | "Need 1.2K credits, you have 900 (ready in 0:20)" |
| profile still loading | "Loading your city…" |
| someone else's lot (only reachable by an exploit) | "This is <name>'s city. Yours is the shelf with your name on it." (at most once per 5 s) |
| rate limit | "Slow down" (at most once per 5 s) |
| someone else's board | "This is <name>'s Census board. Yours is beside your own arrival pad." |
| a break requested with a hazard inbound | "Break queued: step out of the red ring first" (the template's queue) |
| Orders run out | the chip "💤 Workers idle: build anything to put them back to work" |

A topped-out lot has no prompt to press (3.3), and a locked district has no lots, only its sign.

**Budgets, capped in code** (`Config.Budget`, meteor-drop-tycoon's client values [T]): `MaxLocalParts` 200,
`MaxEmitters` 4, `MaxEmitterRate` 60/s, `MaxWeatherEmitters` 2 (via `EnvBands.capRates`), `MaxBeams` 8, `MaxTrails`
8, `MaxLights` 3, `MaxHazards` 1.

**Server parts** [R], per shelf at most: rock 1 + plaza 1 + parapet 32 + Town Hall 10 + arrival pad 1 + board 2 +
locked-slot signs 5 + 36 lots × 5 (plate, sign post, body, roof, window strip) 180 + airship 12 = **244**. A sign
exists only while its district is locked, so the real peak is lower. 6 shelves: **≤ 1 464**, asserted ≤ 1 500
headless. Server lights: one in each Town Hall and one on each airship = 12. Prompts: at most 36 lot prompts + 1
board prompt per shelf.

---

## 16. Build plan: tests first

**Files** (checklist §1 scaffold; deep-vein's layout: `default.project.json` maps `src/server` →
ServerScriptService, `src/client` → StarterPlayerScripts, `src/shared` → ReplicatedStorage):

```
outpost-zero/
  default.project.json
  src/shared/Config.luau     every tunable in this spec, one block each (World, Shelf, Lots, Templates, Economy,
                             Districts, Orders, Env, Hazards, Rest, Save, Board, Prompts, Budget, Tutorial, Pacing)
  src/shared/Economy.luau    Cap, Price, population, income, Orders + safety net, offline, bestNext, canBuy/apply (pure)
  src/shared/City.luau       layout(seed): slots, templates, mirrors, lot keys and positions, facade picks; validate (pure)
  src/shared/Board.luau      encode/decode, shouldWrite, friend-row merge and sort, empty-view texts (pure)
  src/shared/Save.luau       defaults, normalise, version guard (pure)
  src/shared/Rng.luau        anomaly-observatory's, verbatim: it has Rng.below (high bits, 1-based) for every small
                             range (checklist "LCG low bits"); plus1-jump's copy has no `below`
  src/shared/EnvBands.luau   plus1-jump, verbatim
  src/shared/Hazards.luau    meteor-drop-tycoon's copy (plus1-jump + deep-vein's marked vertical section), verbatim
  src/shared/Rest.luau       plus1-jump, verbatim
  src/shared/Fx.luau         + Presets.Dawn (the only change); FxClient.luau, Responsive.luau verbatim
  src/shared/SkyArt.luau     client art: bands, critters, weather, hazard models, the airship's flight
  src/server/Main.server.luau
  src/client/Hud.client.luau (HUD, ★ marker, board SurfaceGui)   src/client/Sky.client.luau (bands, hazards, break)
  tests/*.spec.luau          tests/CityModel.luau (design/model.py, ported, reading Config and calling Economy/City)
  README.md (store text, section 20) CLAUDE.md EYECANDY.md MARKETING.md .gitignore (publish_*.bat, publish_*.sh, *.rbxl*)
```

The layout seed is below 2^31, so `seed × 7919 + 17` stays under 1.7 × 10¹³, far below 2^53 (checklist: seed
overflow) [R]. The model's `below` is 0-based and `Rng.below` is 1-based, so the port shifts by one; `City.spec`
asserts layout properties, not the model's exact layouts.

**Unit specs, each written and watched failing before its module:**
* `Economy.spec`: every price, capacity and threshold above; population = min; income only while Orders run; Orders
  renewed by a purchase and never by a break; the safety net on and off; `offline` (negative clock difference → 0,
  the stop at `ordersUntil`, the safety-net extension); `bestNext` for each case in 4.5; the dead-end rule from
  Config (dearest storey ≤ half the Orders of income at the worst end state).
* `City.spec`: every seed's lots inside r ≤ 73 and outside the plaza; gaps ≥ 4 in a district and ≥ 6 across
  districts (M1 over 1 000 seeds); every two sign posts ≥ 14 studs apart (3.3); 3 Homes and 3 Workshops in every
  district; district 1 always in slot 0; lot keys are strings; the same seed always gives the same layout.
* `Board.spec`: encode/decode round trip, tie-break order, write only on improvement, the 200-friend cap, the empty
  and failure texts. `Save.spec`: normalise, clamps, string keys, `v` guard.
* `EnvConfig.spec`: bands validate; every band defines every lighting field; `ClockTime` rising and under 24; band 1
  has no hazards; every hazard kind is used; `fall ≤ commit`; every ring leavable in under 0.3 s; `PendingSeconds`
  ≥ longest flight + 2; `isReddish` over every non-hazard colour; `Fx.Presets.Dawn` equal to band 1; band `from`
  equal to the district thresholds.
* The copied `EnvBands`, `Hazards`, `Rest`, `Responsive` and `Rng` specs, each from the game its module comes from,
  self-contained and verbatim.
* `Pacing.spec` runs `CityModel` from Config and asserts: normal and slow open the Skyport in 30-45 min; Crown
  Heights at least 2× later and under 3 h; every band at least 2 min; 0 Orders lapses; teleport/normal brag
  ratio ≥ 0.95; AFK and the one-lot macro add 0 population in 8 h.

**Headless gates** (`robloxemu`; rebuild with `py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau`
before every run), each in `robloxemu/check_outpostzero*.luau`:
* `check_outpostzero.luau`, **the real player path**: 6 shelves exist and are parented; each has exactly one enabled
  SpawnLocation; spawn on your own pad (section 11); trigger the ★ lot's prompt and see a building, then the second,
  and see population 4 and credits rise; wait and buy a storey; reach population 80 and see Market Row's lots
  appear in the slot the seed names; a refused purchase **with a toast**; Orders running out stop income and a
  purchase restarts it; the empty attribute inventory; server parts ≤ 1 500; rejoin restores every saved field and
  pays the offline earnings once.
* `_save`: two sessions on one profile (the second is non-saving and pays nothing it can keep); a late releasing
  write cancelled by the owner token; a `v = 2` record left untouched.
* `_sky`: every band and every seam, budgets asserted each frame; weather capped; a purchase glides; the client
  fires nothing (there is no remote to fire) and writes nothing the server built.
* `_hazards`: only on your own shelf, grounded, not resting, not during the airship; the drawn ring equals the zone;
  walking out of it in 8 directions always dodges; a break freezes the clock.
* `_airship`: the Skyport purchase announces once, the moored airship appears after 12 s, `airshipSeen` saves, and a
  rejoin mid-flight replays it once.
* `_hud`: hudcheck at six viewports with `overlap = true`, touch and desktop.
* `_board`: writes only on improvement and only after a save landed, the encoding, public rows, the friends view
  falling back cleanly where `GetFriendsAsync` is missing.

Every new assertion is mutation-tested with a control (the standard §4).

---

## 17. Cut from v1

| cut | why |
|---|---|
| Prestige ("Relaunch Outpost") | Needs its own pacing model and its own board rules. The complete skyline at 4.30 h is v1's end (section 8); prestige is v2's first candidate. |
| Droppers, conveyors, a collect pad | A second physical loop, and walk-to-collect is meteor-drop-tycoon's play (2.1). |
| More building types (parks, markets, power), adjacency bonuses, zoning choices | Each one adds a rule to the star and the model. Two types and one balance rule already give the decision. |
| Demolish and rebuild | Population would fall, and every monotonic rule (districts, bands, board) would need a second case. |
| Bridges between shelves, visiting, trading, co-op, any PvP | The 60-stud sky gap is what keeps cities apart without code (3.1). Visiting is v2 material. |
| Walking citizens, moving trams and trains | NPC pathing and moving server parts cost frame time and tests. The far sky-rail line is static scenery. |
| Codes, daily rewards, streaks, badges | One-time grants are a trust surface (checklist); badges need the Creator Dashboard. |
| Server-wide events (festivals, storms for everyone) | They would need fairness rules against the per-player bands. |
| Sound and music | Audio needs asset ids (section 18, optional). |
| Custom meshes, textures, skyboxes | v1 is code-only Parts, as the checklist expects. |
| Any Robux item | Section 13. |

---

## 18. Needs Studio (and needs a live server)

Only real rendering, real input or a published server can settle these. This list moves into `EYECANDY.md` when the
game is built.

1. **Every band's look**: exposure, ambient and bloom per band; whether the shelf reads in the dawn haze
   (Atmosphere density 0.45) and at night; Neon window strips under bloom; the gold-pink Lantern Dusk grade.
2. **Atmosphere vs fog**: Roblox ignores the Fog properties while an Atmosphere exists, so the fog banks are
   Atmosphere and client parts. Do they read as fog, or as a grey screen?
3. **The cloud sea at y = −80** and the far shelves at 400-2 000 studs: culled at low graphics quality on a phone?
   If so, closer and smaller.
4. **The aurora's 4 Beams, the lanterns rising, the sky whales**: almost certainly need hand tuning.
5. **The Grand Airship**: a 12 s client flight then a server-placed mooring. Does the hand-over jump? Does a
   12-Part model at y = 120 read from the plaza on a phone?
6. **Frame time** on a mid or low phone with 6 cities of up to 36 towers (1 464 server parts) and the full weather.
7. **The lot prompt** at `MaxActivationDistance` 8 on a sign post: easy to hit with a thumbstick? Does Roblox's
   nearest-prompt choice ever pick the neighbouring lot while you stand between two signs?
8. **The new storey's 0.35 s server tween**: smooth under real replication, or stepped?
9. **The knock**: does `PlatformStand` plus `AssemblyLinearVelocity` push a humanoid on flat ground and release
   cleanly? The same open item as deep-vein, meteor-drop-tycoon and +1 Jump.
10. **The hazard telegraph among towers**: is the ring visible when a tower stands between the camera and the
    player? Is the light pillar readable at midday in Trade Winds?
11. **The break's sit and camera tilt**: `Humanoid.Sit` with no seat, from the client (+1 Jump's open item 11);
    does the tilt feel good and release on the first move?
12. **Top-centre HUD on a notched phone**: safe area, emoji in `TextScaled` labels, the population chip's length at
    "Aurora Crown · population 1 031 184".
13. **The Census SurfaceGui** in PlayerGui with `Adornee`: legible from the pad (10 studs); only the owner sees
    the rows.
14. **`Players.MaxPlayers = 6`** in Game Settings, and `SpawnLocation.Duration = 0` really removing the force field.
15. **Climbing**: can players climb stepped towers and jump over the glass from a roof? The rescue makes it harmless.
    Is it fun enough to keep, or should the glass go higher?
16. **Other players see a knock with nothing hitting** (client-only hazards). Does it look like a glitch?
17. **Live server only**: the friends board against real `GetFriendsAsync` pages and DataStore throttling;
    `GetSortedAsync` caching across servers; offline earnings across two servers' `os.time()` (skew of a few
    seconds is expected and harmless).
18. **Photosensitivity**: Storm Front's distant lightning at one flash per 3 s, never full-screen. Confirm it
    on a real screen.
19. **Optional, if assets are chosen**: a construction thump, wind at dawn, an airship horn. Library audio ids only.

---

## 19. Planned thumbnail shots and clips

These seed `EYECANDY.md` (thumbnails, 1920 × 1080) and `MARKETING.md` (clips, 7-15 s, vertical 1080 × 1920, for
`tools/film_game.py`). A Studio session sets up each shot through a copy of Config in the place only, never `src/`,
the way +1 Jump's shot list does [T].

**Thumbnails**
1. **"Lantern Dusk skyline"**: camera low on the plaza looking up past the Town Hall; 17-18-storey towers with lit
   windows on both sides, sky lanterns rising, the Grand Airship moored overhead. The brag in one frame.
2. **"Build it"**: over the shoulder of an avatar at a glowing ★ lot, a tower mid-grow with the construction puff,
   the fog lifting off the cloud sea behind.
3. **"Six cities under the aurora"**: a wide shot from above the ring of shelves, every city at a different
   height, the aurora curtains and a sky whale crossing.
4. **"Close call"**: a loose crate one frame before impact, the red ring on the paving, the avatar a step outside it.

**Clips** (how to stage each)
1. *First build* (8 s): a fresh profile; walk to the ★ lot; BUILD; the first house rises; the second; "+60/min".
2. *The Grand Airship* (15 s): a profile at population 6 380 with credits for one more pair of district-3 storeys;
   buy the pair; the title card, the 12 s flight, the mooring and the toast.
3. *The fog lifts* (12 s): a profile at population 48 with credits for several cheap storeys; buy pairs across 50 →
   80 and watch Fogbound Dawn glide into Clear Morning (the fade is 30 population wide).
4. *Dodge* (10 s): hazards every 8-10 s in the place's Config copy; step out of the red ring as the crate lands.
5. *Tower climb* (10 s): a profile with credits for 6 storeys on one lot; tap Add storey six times; the tower climbs.
6. *Coffee break* (10 s): press ☕ Break in Storm Front; the camera tilts up to the lightning in the cloud sea.
7. *Census* (8 s): walk to the board, toggle Public → Friends.

---

## 20. Store text (for `README.md`; 974 characters by `len()` in Python, limit 1000, plain ASCII)

```
Build a city on an empty sky-shelf above the clouds.

Walk to a glowing lot and tap BUILD. Homes bring settlers, Workshops bring jobs, and every settler with a job is a citizen who earns you credits. Keep them in balance and stack storeys until your towers stand 22 floors tall. A star marks the build that pays for itself soonest.

Your city grows into six districts, from the Landing Field to Crown Heights, and each city draws its own layout. The sky grows with your population: the fog lifts, balloons drift past, lanterns rise at dusk, a storm rolls through, and at last the aurora and the sky whales come.

Open the Skyport and the Grand Airship docks above your Town Hall for the whole server to see.

Now and then something falls from the sky. A red ring shows exactly where: step out of it and it misses. Press Break to sit down; nothing falls while you rest.

The Census board by your spawn ranks everyone, or just your friends, by population. Nothing costs Robux.
```

Every claim in it is a rule in this spec: 22 storeys (4.1), the star (4.5), six districts and a per-city layout
(3.2, 4.4), the six bands (5.2), the airship (8), the red ring (6), the break (7), the board (9), no Robux (13).

---

## 21. Self-review

Checked against the task and `docs/complete-game-standard.md`, one line each:

* **Core loop in one paragraph**: section 1. **Every number with a reason**: each carries a tag or a worked reason.
  The profiles, the 1.9 s hit cost and the starting light values are the assumptions, and they are labelled.
* **Reachable from join**: section 14's first minute (first build at 3.3-3.9 s), and the headless real-player-path
  gate in section 16.
* **Spawn per SPAWN-ORDER**: section 11 (RespawnLocation before any yield, plus a bounded wait-and-correct).
* **Server-authoritative, nothing secret replicates**: 10.2-10.5, no client → server remotes, the empty attribute
  inventory, a server-only seed that decides nothing of value.
* **DataStore**: pcall everywhere, `canSave` only while holding the lock, an owner token on every write, string
  keys, credits and `savedAt` in one write, no one-time grants (10.1).
* **No silent no-ops**: the refusal table in section 15.
* **Bands**: six, each with its own light, colour, scenery, critters and weather, triggered by population, gliding
  (section 5). **Hazards**: rare (one per 120-180 s of play), telegraphed, the red ring is exactly the zone, one at a
  time, a hit costs about 1.9 s (section 6). **Rest**: never an exploit (section 7).
* **Brag at 37.1 min** in the 30-45 window; **long-term goal at 133.9 min**; a complete skyline at 4.30 h
  (section 8).
* **Board**: public + friends, a metric a script cannot inflate with its residual stated, the standard's encoding,
  physical, with a ProximityPrompt, cached names and a useful empty view (section 9).
* **Phone first**: section 15, hudcheck with `overlap = true`.
* **Needs-Studio list**: section 18. **Thumbnail shots and clips**: section 19. **Store text**: section 20.
* **Fair monetization**: section 13. **Scope**: the cut list in section 17; v1 has two building types, one balance
  rule, one idle rule and no remotes.

Consistency checks made while writing:
* The model's constants (`design/model.py`, `E` and `Shelf`) equal every value stated here.
* Band `from` values 0 / 80 / 900 / 6 400 / 35 000 / 185 000 equal the district thresholds, and the fades satisfy
  `EnvBands.validate` (5.2).
* The arrival pad (0, −16) and the board (−10, −16) are inside the plaza (r ≤ 26); no lot comes closer than 33.06
  [M1].
* `PendingSeconds` 7 ≥ 4.6 + 2; every kind's `fall ≤ commit`.
* The airship's hull bottom (120) is above the tallest roof (90).
* Server parts ≤ 1 464 against the asserted 1 500.

Defects the model found while it was being built, and how each was fixed, so a reader sees why the rules are as
they are. Items 1-4 were measured by earlier revisions of the model and cannot be re-run from the current file. Item 5
can: set `E["MaxStoreys"]` in `design/model.py` to 30, 26, 25 or 24 and run Part 9 (`py -3 design/model.py 9`).
1. The first threshold draft (×10 per district) put Crown Heights at population 400 000, above what districts 1-5
   can hold at 30 storeys (281 160): band 6 was unreachable. The thresholds are now fitted to times and checked
   against capacity. Crown Heights needs 185 000 of the 206 184 that districts 1-5 hold at 22 storeys (90 %), which
   is why those towers stand at 19.7-22 storeys when it opens [M11].
2. The first star (best capacity per credit) made players stand and wait at each district's opening; the longest
   gap between purchases in that design sweep was 570 s. Replaced by the payback rule (4.5).
3. The first economy scale ran the first minute at 21 purchases (one press every 3 s). Rescaled to 7 (4.1).
4. Neighbouring districts' lots came within 2.09 studs; the rows and arc templates moved outwards (3.2).
5. With 30 storeys, Orders ran out before the last storeys were affordable and a perfect city stalled at population
   1.22M. Fixed by 22 storeys and the safety net (4.3).

What this spec does **not** know: whether any of it looks or feels good (section 18), and whether the normal profile
is anything like a real player. Replace `Config.Pacing.Profiles.normal` with telemetry first, then re-run
`Pacing.spec`.
