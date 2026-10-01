# Steal a Cryptid — the night over Pine Hollow

Owner's brief (Gustav, 2026-09-17): every game richer and never monotonous — eye candy, and an environment
that changes as the player progresses, following the logic of the game; hazards that knock you down, but
RARE (about one near-hit per 2-3 minutes) and easy to see coming; a way to rest that can never become an
exploit; environments worth photographing, and a thumbnail shot list for the night Studio session.
+1 Jump was built first; its `EnvBands`, `Hazards` and `Rest` modules are the template, copied here verbatim.

**State (2026-09-30): built, unit-tested, headless-tested through the real server and the real client
scripts, reviewed twice, mutation-tested after each review. The second review's five findings are closed
test-first and the four open owner decisions are DECIDED (§14; §11 has the decisions). NEVER OPENED IN ROBLOX
STUDIO. Not published. The 2026-09-30 pass did not commit or push (the orchestrating session owns git).**
(2026-10-01: the pass was re-run and every claim re-measured; one test gap closed in `check_stealacryptid_nighthud`,
no game change; 38 of 38 mutations killed, 4 of 4 controls survived. §14, last subsection.)
**(2026-10-01, pass 2 toward the complete-game standard, §15: a fifth home band, the Gathering, past Mythic Night; every
camp with its own weather and its own critters; the band times measured in Luau. Nobody has reviewed it yet.)**

(State 2026-09-24: reviewed once, mutation-tested: the resume session's 49 edits re-run plus 28 new ones, 70 of 70
mutations killed, 6 of 6 controls survived, one equivalent mutant set aside, every edit proven to reach the bundle.)

This work was resumed from an interrupted build (§12 says what that build left, what was wrong with it, and
what that session changed). In short: the art, rules and most checks were there and green, one check had
never passed, and six defects no check saw were found and closed test-first. An adversarial review then
found three more (§13): the night's far floor hid the world's edge (a player could walk off it and fall
through), a knock near the edge could carry a player past it, and camp scenery could stand between a
zoomed-out camera and the raider. All three were reproduced with the reviewer's own probes, closed
test-first, and the camera one was closed at home too. Verification also caught two rare flakes, both closed:
a wisp's halo reaching 0.2 studs into a camp keep-out corner (a game gap, fixed test-first), and a float-noise
edge in the hazards check's telegraph timing (a test-arithmetic bug).

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau`, `Hazards.luau`, `Rest.luau` | **the template, verbatim** from `plus1-jump/src/shared` (byte-identical, with their specs): progress → band + eased blend, glides, announcer, ambient ring, `capRates`; the rare telegraphed hazard scheduler with the ring rule; rest rules. Pure. |
| `src/shared/Night.luau` | **this game's rules**, pure: the readability floor (no band darker or foggier than the game as it shipped), night hours (a glide never passes through daylight), rank → home sky, "am I in a camp pocket", the camp keep-out (scenery never inside a camp or the camera's corridor behind its gate), the hazard gate (home only, after the tutorial, no poacher, no panel/build mode, away from the ground's edge, a settle time), `hazardPitch` (lanes never start under the ground), `drawPosition` (where a hazard is DRAWN: swoop away after arrival, meteorite ends at the ring, rise over a dodger), habitats, HUD strings. |
| `src/shared/NightArt.luau` | the art, code-only, client-only: horizon (the far floor beyond a ravine, ridges, far pines, owls on the server's pines, auroras, UFOs, a 98-stud Bigfoot), four camp places, six critters, four hazard models + telegraph, weather, habitats, the rest campfire. Pooled; unparented at weight 0; every part anchored and non-collidable/queryable/touchable. Every frame `occlude` hides a part that stands between the camera and the camp (in a camp) or the player (at home) (§13). |
| `src/client/Night.client.luau` | the glue, one RenderStepped: where am I → band weights → lighting (10 Hz, only on change) → scenery → critters → weather → habitats → rest → hazards → HUD chip → title cards. |
| `src/client/Hud.client.luau` | a **Rest** toggle first in the top-right row (hidden while raiding); a client-local `NightBus` (press count in, button label and one chip line out); the chip shows the night's line after raid and poacher lines. |
| `src/server/Main.server.luau` | **two fields** in the owner's own `State`: `rank` (highest tier ever owned, what the pedestals and camps already follow) and `plot` (the lair whose sign carries their name). Nothing else on the server. |
| `src/shared/Config.luau` | `Config.Night`: 4 home bands, 4 camp bands, critters, hazards (4 kinds), rest, budget, habitats, campfire, text. |
| `tests/` | `Night.spec` (427; 347 before the review fixes), `NightConfig.spec` (222; 214), and the template's `EnvBands.spec` (124), `Hazards.spec` (102), `Rest.spec` (55), verbatim. |
| `robloxemu/check_stealacryptid_{night,hazards,rest,nighthud,budget,compile}.luau` | the glue, headless (the interrupted build's, extended here). |
| `robloxemu/check_stealacryptid_{lateroad,keepout,life,longroad}.luau` | new in the resume session (§12). |
| review fixes (§13) | `Night.luau` gains `farGroundRects` (the ravine), `limitKnock` (a knock near the edge), `viewHull` / `boxOverlapsHull` / `campViewHull` / `hidesCamp` (the camera's view) and `critterClear`; `NightArt` builds the ravine and hides what stands in the view; `Night.client` cuts the knock, keeps camp critters out of the view and tells the art where the player is; `Config.Night.Ravine` and `HomeViewRadius`. New checks `check_stealacryptid_edge` and `_view`; `_lateroad` and `_longroad` extended. |
| pass 2 (2026-10-01, §15) | a fifth home band, **the Gathering** (`Night.level`: one step past the Mythic once `State.best`, the best lair income ever and the Top Lairs board's metric, reaches `Config.Night.GatheringRate` 1 350/s): a crimson moon (`bloodMoon`, rides with the camera), the legends of Pine Hollow on the far floor (`gathering`: a Mothman and a Dogman on one side, a Jersey Devil and a Mothman on the other), moths, embers, Mythic Night's pieces kept; each camp its own weather and critters (Badlands `sand`, Barrens the Jersey Devil `devil`, Loch Shore `moth`, Redwoods `spores`; the camp keep-out tests a critter by its own `reach`); the server's `State.best`. Checks: `_night` (the fifth band through real purchases; every band's weather and critters drawn; the art builds every kind Config names), `_budget` (the mythic -> gathering seam; nothing refused by the cap), `_view` and `_longroad` now run at the Gathering. |
| second review fixes and owner decisions (2026-09-30, §14, §11) | `Hazards.threatLive` (template update) and the lingering ring/chip/drawing (`Night.drawPosition` `liveUntil`); a Rest press mid-stumble queued; `Night.campfireSpot`; the title card placed from the HUD's NightBus room and deferred while a panel is open; the budget capped in code (`Night.budgetGate`/`admit`/`capEmitters`, `Budget.Reserve`); the server's fall rescue (`World.FallRescueStuds`). New checks `_latehit`, `_card`, `_budgetcap`, `_fall`. |

`check_stealacryptid.luau`, `check_stealacryptid_guards.luau`, `check_stealacryptid_hud.luau` and `tests/walk.luau`
are **unchanged** and green: the game they guard is the same game. (2026-09-30: they are still unchanged and
green after the server's fall rescue.)

---

## 2. The bands and what triggers them

**Trigger: the Journal's rank, never time.** `rank` = the highest tier the player has ever owned (0-4), the
value the pedestals and the camp unlocks already follow; the server reports it in the player's own State. Past the
Mythic the home sky takes one more step, **the Gathering**, once the best lair income the player has ever had
(`State.best`, the Top Lairs board's metric, which never goes down) reaches `Config.Night.GatheringRate` (1 350/s,
three Bigfoots' worth; above the 900/s of the best lair without a Mythic, so it always follows Mythic Night). The
blend's progress is `Night.level` (0-5).
The rarer your collection, the deeper the night over Pine Hollow. Inside a raid the night is the **camp's**
place, named by the camp's tier. Where you are comes from your own root's position (a pocket is at
x ≥ 3 936), so a State that arrives before the teleport cannot show the wrong place.

**Why "the night deepens" instead of a day/night clock:** the brief says environment changes are driven by
progress, not time, and the game is a night game by design (DESIGN.md §13: moonlit, readable nets). The
five home bands step the sky from sundown to 4:36 am as the Journal and the lair fill. `ClockTime` is written in *night
hours* (18 = 6 pm … 27 = 3 am; the client writes h mod 24) inside 17.5-30, so a glide between any two bands
never passes through daylight (asserted over every blend of every pair, and on every frame of the headless
runs).

**The readability floor.** No band, and no frame the client writes, may be darker, foggier, less saturated
or harder to bloom than the game as it shipped (`Config.Lighting`), and no band may carry depth of field: a
raider must read a whole camp from its gate, tier colours must survive, neon nets must bloom. `Night.readable`
checks every band, every 5-step blend of every pair (9 bands + the v1 take-over, 500 blends; 405 before the
fifth band), and every frame of `check_stealacryptid_night` (join, 5 bands, 4 camps, every seam).

**Transitions never cut.** Every written value glides with a 0.6 s half-life; lighting is written at most
10×/s and only when it changed. Measured through the real client: 0.3 s after a purchase raises the rank the
`ClockTime` is between the two bands; 0.4 s after leaving a camp the night is still gliding home. At join the
client starts from exactly the server's lighting and glides to the player's band (it reuses the server's
`FxAtmosphere`/`FxBloom`/`FxColorCorrection` by name — exactly one Atmosphere).

### Home: the sky over your lair

| # | band | Journal rank | clock | the sky | scenery | life | weather | hazards |
|---|---|---|---|---|---|---|---|---|
| 1 | **Dusk** — "Pine Hollow at sundown" | 0-1 (no cryptid / Common) | 18:09 | warm rose fog, low sun rays, 300 stars | the road's Ground is a bluff: a rock face drops 80 studs into a 24-stud ravine, and the forest floor runs from its far rim to the fog; 14 dark ridges on the horizon, 24 pine silhouettes | 3 crows | fireflies 5/s | crow |
| 2 | **Moonrise** — "A Rare cryptid stirs the woods" | 2 (a Rare) | 20:24 | blue moonlight, a big moon, 1 500 stars | + owls on the road's own pine crowns, turning to watch you, blinking | 6 bats | mist 3/s | bat, crow |
| 3 | **Strange Lights** — "Legendary lights over the ridge" | 3 (a Legendary) | 23:42 | teal grade, stronger bloom, 3 000 stars | + a green-violet **aurora** (3 ribbons) | will-o'-wisps, **red eyes blinking in the treeline**, bats | wisp-lights 6/s | wisp, bat |
| 4 | **Mythic Night** — "Bigfoot walks Pine Hollow" | 4 (the Mythic) | 02:48 | warm grade, strongest bloom, 4 500 stars, the biggest moon | + a gold aurora, **three UFOs** with tractor beams over the ridge, **Bigfoot, 98 studs tall, walking the horizon** | **meteors** streaking overhead, wisps, red eyes | stardust 6/s | meteorite, wisp |
| 5 | **The Gathering** — "Every legend comes to look" | level 5: the Mythic, and a best lair income of 1 350/s | 04:36 | crimson grade, the strongest bloom (threshold 0.78), 5 000 stars; the sky's moon shrinks to 6 | Mythic Night's pieces + a **crimson moon** low over the ridge + **the legends of Pine Hollow** (a Mothman and a Dogman, a Jersey Devil and a Mothman, 30 studs tall, glowing eyes) standing on the far floor past the ravine, looking at the lairs | **moths**, red eyes, meteors | embers 6/s | meteorite, bat |

A title card names the band quietly when the player's State first arrives, and again each time a new band is
reached (`MOONRISE / A Rare cryptid stirs the woods`) — never over a camp, where it would cover the nets, never over
the HUD's top stack or into the thumb band, and never over an open Hunt panel or build sheet: a band reached with
one open is named when it closes (2026-09-30, §14 finding 4).

### Camps: each tier its own place

| camp tier | place | clock | scenery (all outside the fences) | life | weather |
|---|---|---|---|---|---|
| 1 Common | **Badlands Camp** | 21:36 | red sand, 9 mesas on the horizon, cacti | tumbleweeds rolling past, bats | sand blowing sideways behind the back fence (4/s; 2026-10-01) |
| 2 Rare | **Pine Barrens Camp** | 23:00 | pine-needle floor, a ring of 14 pines | **the Jersey Devil circling high over the pines** (2026-10-01), bats | fireflies behind the back fence |
| 3 Legendary | **Loch Shore Camp** | 00:48 | pebble shore; a loch 1 400 × 800 behind the cages with a moon glint; a castle tower with one lit window; **Nessie gliding across the water** | **moths** (drawn to the lit window; 2026-10-01: they replaced bats, the Barrens' life) | mist behind the back fence |
| 4 Mythic | **Redwood Camp** | 03:12 | fern floor, 12 redwoods 190 studs tall, **a Bigfoot glimpsed between them** | wisps | spores drifting down behind the back fence (2026-10-01: they replaced mist, the Loch's) |

Every band, home and camp, has its own weather and its own life: among the five home bands and among the four camps
no two share a weather kind or the same set of critters (`NightConfig.spec`), and `check_stealacryptid_night` sees
each band's weather falling and its critters out after 8 s there. A critter that draws wider than the camp keep-out's
3-stud box names its own `reach` (the Jersey Devil's wings: 7).

**Camp visuals reveal nothing.** The place depends on the camp's TIER only (which the raider chose). No hazard
ever flies in a camp. Every camp part and critter is kept out of `Night.keepOut`: the camp (fences, sign, cage
row) grown by 8 studs, and a 60 × 70-stud corridor behind the gate where the raider's camera sits — checked
when placed and on every animated frame (critters by the box their wings, bob and halo draw, `Night.critterClear`),
and camp weather hangs 58+ studs behind the back fence. `check_stealacryptid_night` asserts it on every camp
frame; `check_stealacryptid_keepout` widens the keep-out in memory so the guard actually has to work (§12).
**And from anywhere else:** a raider who zooms out and orbits looks at the camp across the scenery, so every
frame any camp part or critter whose footprint enters the hull of the camera and the camp is hidden (a critter
is recycled) on the frame the camera moves, and fades back in over 0.4 s once clear (§13). So nothing local
can stand between the camera and a net, a snare or the raider, from any camera position:
`check_stealacryptid_view` puts the real camera at 11 520 spots (zoom 20-400, every side, three pitches) and
finds none.

### Habitats: your own cages

Each of **your own** occupied cages gets a small habitat patch per species on the server's cage base:
Jackalope prairie (tuft, burrow), Hodag north woods (stump, mossy rock), Chupacabra desert (saguaro, skull),
Dogman moon-field (wheat, post), Jersey Devil pine barrens (sapling, ember), Mothman bridge (lamp post and
lamp), Nessie loch (pool, reeds), Bigfoot rainforest (fern, boulder). A neon rim per tier, brighter the rarer.
Only the rarest one also has particles (dust, smoke, fireflies, embers, moths or mist), for the budget. Only
your own lair is dressed (the neighbour's Bigfoot cage stays plain, asserted), and it is local: other players
see the cages as before.

### How long to each band (measured in Luau, 2026-10-01)

`tests/Pacing.spec.luau` plays 24 sessions per player model on the game's own modules (real camps solved by the
raid solver, raid success judged by the server's catch rule against a timing error, real prices, pedestals,
permits, alerts and poachers; README.md has the table). Median minutes of play for the **normal** raider (timing
error 0.25 s, raids at 2x the solver's time), fastest-slowest in brackets:

| band | reached at | normal | casual (0.35 s, 3x) | never raids |
|---|---|---|---|---|
| Moonrise | first Rare | 3.9 (3.7-5.0) | 4.9 | 10.8 |
| Strange Lights | first Legendary | 14.5 (13.8-18.0) | 17.4 | 61.2 |
| **Mythic Night** (the brag moment) | first Mythic | **35.6** (31.8-76.3) | 59.5 | 180.5 |
| **The Gathering** | best lair 1 350/s | **97.3** (92.7-137.7) | 122.5 | 222.0 |
| (the end goal) | nine Mythics | 190.9 (184.5-228.2) | 213.8 | 325.0 |

Mythic Night used to come at 81.6 minutes in this model (107-183 in DESIGN.md's Python one): the Mythic's payback is
now 3 600 s instead of 14 400 (CLAUDE.md Deviations), so the brag moment lands inside the standard's 30-45 minutes,
and the Gathering is the step between it and the full lair. **These are a model's minutes, not playtests.**

---

## 3. Hazards and their measured rarity

| kind | bands | speed | warning | lane locks | hitbox (ring Ø) | knock | after arrival |
|---|---|---|---|---|---|---|---|
| crow | dusk, moonrise | 26 | 3.2 s | 1.5 s before | 1.8 (6.6) | 30 | swoops up and away |
| bat | moonrise, strange | 22 | 3.2 s | 1.6 s | 2.0 (7.0) | 28 | swoops up and away |
| will-o'-wisp | strange, mythic | 12 | 3.6 s | 2.0 s | 1.8 (6.6) | 24 | swoops up and away |
| meteorite (glowing, trailed) | mythic | 40 | 3.2 s | 1.7 s | 2.2 (7.4) | 34 | strikes the ring and is gone |

**Rules** (template `Hazards` + `Night`; an invalid config switches hazards off with a warning):

* **One hazard every 120-180 s of hazard time**, never two at once. Hazard time runs only while the gate is
  open: **at home**, after the tutorial's first raid, with **no poacher warning or poacher** in the yard (a
  warning also removes a hazard already flying — the owner must be free to defend), not in build mode, not with
  the Hunt panel open, not within 33 studs of the ground's edge, not before the road's Ground is known, and 8 s
  after the gate reopens (coming home from a raid, closing a panel). A closed gate freezes the clock; it never
  resets it.
* **It starts on screen**: within ±35° of where the camera looks and ±20° of its pitch — but never below the
  horizon: here the camera looks DOWN at a player on the ground, and the template's window would start lanes
  inside the ground (the spec's control: with the camera 30° down the template starts a crow 14 studs below the player's root). `Night.hazardPitch` keeps the window's top at the
  horizon and holds a launch while the camera looks down more than 40°. With the usual follow camera (~22° down)
  lanes come in level; looking level or up, they come down out of the sky.
* **Telegraph**: an always-on-top `!` marker on the hazard, a blinking red light, a lane line through you and
  a ring at your feet (yellow while it tracks you, red once it locks), and the HUD chip: `Bat incoming from the
  left`, then `Move! Leave the red ring - bat`. The arrival time never moves. The lane line goes at arrival; the
  ring, the chip, the marker and the light stay up while the rest of the flight can still hit someone in the ring
  (`Hazards.threatLive`, the +1 Jump template's rule) and go then, or at the hit: nothing blinks `!` once the danger
  has passed, and nothing hits after its warning has gone (2026-09-30, §14 finding 1).
* **The red ring is the danger zone** (template round-2 rule): a hit needs you inside it. Stepping out in any
  direction dodges. `NightConfig.spec`: leaving the ring from where you stand at walk speed after 0.5 s to react
  fits inside every kind's lock (tightest: a crow, 0.71 s of its 1.5 s).
* **Drawn, not just computed** (new here): until arrival the hazard is exactly on its lane; while the ring
  lingers after arrival it keeps the lane's line, level at the height it arrived (never into the ground); then a
  flier swoops up at 35° instead of flying on into the ground, and the meteorite ends at the ring; for a player
  who has left the ring the drawn path rises over a smooth bump so its centre stays 4.5 studs from their root —
  it passes over a dodger instead of through them. The hit rule is untouched.
* **A hit is a stumble**: `PlatformStand` 0.9 s, a horizontal push away from the lane (24-34 studs/s), 8 studs/s
  lift, a small camera shake and flash. **Nothing is lost** — no Essence, no cryptid, no progress. A raid's
  teleport clears a stumble on its first frame. The edge margin (33) is at least the hardest knock's
  frictionless slide (34 × 0.9 + 1.5 = 32.1), so no hazard launches where a full knock could reach the edge.
  But the margin gates LAUNCHES: a player can walk toward the edge while a hazard flies. So the push itself is
  cut (`Night.limitKnock`, §13): its outward part, axis by axis, so that its frictionless slide ends at least
  PlayerRadius (1.5) inside the Ground; along the edge and inward it is untouched, and far from the edge the
  knock is the template's. Measured through the real client (`check_stealacryptid_edge`): 48 walks toward all
  four edges, stopping in the ring, 47 hits, every slide ending 1.5 studs inside or more (before the fix, the
  reviewer's probe: 19-20 of 24 slides ended past the edge; this check: 10-14 of 24 at rank 2 and 8 of 23 at rank 4
  ended within 1.5 studs of the edge or past it).

**Measured** (every number below is from a run on the final tree; the emulator's `Random` is unseeded, so the
headless figures are ranges over 16 runs of `check_stealacryptid_hazards`):

| measurement | where | result |
|---|---|---|
| raw scheduler, 20 h of hazard time | `NightConfig.spec` | 478 hazards = **one per 150.4 s** (0.398/min); gaps 120.1-180.0 s; never two at once |
| **lair life, reacting to every warning** — stand 12 s at an apron spot, walk 6 s to the next, and when the chip says `Move!` step out of the ring 0.5 s later — 20 min at the shipped interval | `check_stealacryptid_hazards` R2 | **7-9 hazards (one per 2.2-2.9 min), 5-9 near-hits within 8 studs (one per 2.2-4.0 min, typically 2.5), 0 knocks, none flew through the avatar** |
| the same lair life **ignoring every warning** | R3 | 7-9 hazards, **3-7 knocks (one per 2.9-6.7 min)** |
| a player walking a circle at 8 studs/s, never reacting | R | 8-9 hazards, 0 knocks (they keep out-walking the ring), near-hits one per 2.9-6.7 min |
| stays put / steps out of the ring, every kind × 8 directions × 12 lanes | `NightConfig.spec` | stays put: 48 of 48 hit; steps out: **0 of 384 hit**, 384 of 384 still near-hits |
| through the real client: stays put / steps out at 0, 90, 180, 270° from the lane | H1-H3 | 3 of 3 knocked (push ≥ 20 studs/s, lift ≤ 8, hit ≥ 3.0 s after launch); **0 of 4 knocked**; the ring drawn exactly where they stood, red, exactly as wide as the hit rule |
| a dodged hazard's closest part to the root | H7 | **3.3-5.5 studs** (before this session: 0.2-0.7 — it flew through the avatar) |
| after arrival, with the camera level and looking up (lanes come down) | H8-H10 | **0 hazard parts under the floor, 0 frames with the `!` marker on** (before: 1 083-1 333 part-frames under the floor, 694-1 144 marker frames) |
| lanes start on screen: every kind, camera pitch −40…+60° | `NightConfig.spec` | 3 360 launches: 0 below the player, 0 off screen (worst 31.4° / 34.0°) |
| rest toggling, 6 h of hazard time | `NightConfig.spec` | never rests 143 · toggles every 7 s **143** · rests 40 s of every 150 s **143** |

So the owner's "about one near-hit per 2-3 minutes" holds for the player the warning is for; one who ignores
every warning is knocked (harmlessly) every 3-7 minutes of home time; time in a raid, in a panel, in build
mode, with a poacher about or resting does not count at all.

---

## 4. Rest — what "pause" means in Steal a Cryptid

A Roblox server cannot stop the world for one player, so **rest is a state the player is in**:

* **Rest button**, first in the top-right row beside Hunt and Build (thumb-sized on touch; hidden during a raid):
  you sit down, a small **campfire** crackles in front of you, the view softens (depth of field, at home only),
  and the chip says `Resting - poachers still come`. Press again (`Resting` → `Rest`) or move to carry on.
* **Idle rest**: stand still 20 s and the chip says `Idle - critters leave you alone` (AFK-safe; not seated, no fire).
* While resting: no hazard launches and the hazard clock is **frozen, never reset**. The sky, critters, weather
  and habitats carry on. **Nothing else changes, because nothing else is the client's**: jars fill at the same
  rate, poachers come on the server's schedule, raids, heat and permits are untouched.
* Roblox's own idle disconnect (about 20 minutes with no input) still applies; nothing is lost by it either
  (DataStore saves, jars fill offline up to 8 h).

**Why it cannot be exploited**

1. **It touches nothing the server owns.** The server does not know rest exists; the client fires no remote
   and sets no attribute (asserted in four checks). Measured through the real server: a minute of rest grew
   the Dogman's jar by its rate × 60, Essence unchanged (`check_stealacryptid_rest` §1).
2. **It does not dodge the "raid" on your lair — the poacher.** The first poacher's warning came on the
   server's schedule while resting, walked into the yard while resting, and took half the jar it walked to
   (§5 of the same check). The chip shows the poacher, not the rest line. Rest protects no income.
3. **It never pauses a raid.** Rest is refused in a camp (the button is gone; a press that reaches the night
   anyway does nothing), and starting a raid while resting ends the rest on the teleport's first frame. The
   raid's clock kept running (at least 4 s off its timer in 5 s). Rest therefore cannot dodge a raid clock, a trap or Heat.
4. **Not a panic button.** Rest cannot start in the air or with a hazard inbound (`BlockWhileThreat` is
   mandatory in `Rest.validate`): pressing it then only *queues*; the hazard still arrives and a hit voids the
   request; stepping out of the ring keeps the request, and rest begins once the sky is clear and you stand
   still. A request expires after 10 s (the longest flight is 7.6 s). Rest never removes a hazard in flight.
   A press **during a stumble** is queued the same way (the button reads `Rest...`, the chip says rest starts when
   the sky is clear) and rest begins once the player is back on their feet under a clear sky; it used to be
   dropped with no word (second review, 2026-09-30, finding 2; `check_stealacryptid_rest` 2c).
5. **Toggling does not thin hazards** (143 / 143 / 143 above), and hazards take nothing anyway.
6. **There is no leaderboard or timed rule in v1** for rest to touch (README: no leaderboards).

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| bands, lighting, sky, scenery, critters, weather, habitats, title cards, campfire | **client** (`Night.client` + `NightArt`) | cosmetic and per-player (your sky follows *your* Journal); costs the server nothing, replicates nothing |
| hazards: schedule, telegraph, hit test, stumble | **client** | harms only the local player, whose character physics the client already owns; takes nothing. An exploiter who deletes hazards gains nothing |
| rest | **client** | it only pauses the client's hazards |
| rank and plot in State | **server** (2 fields) | the client must not guess progress; both are the owner's own facts (the pedestals already follow rank, the sign already shows the plot) |
| the fall rescue (owner decision (d), 2026-09-30) | **server** (the 10 Hz lair loop) | a character at home 12 studs under the Ground's top goes back to its own arrival marker; the server already owns where a player is sent home |
| economy, raids, poachers, traps, trusted position, saves | **server, unchanged** | authoritative as before |

**Leak review.** The client reads its own character, its own camera, `Config`, its own State (rank, plot,
cages, raid tier, tutorial, build mode, poacher) and public geometry (the road's Ground and pine crowns, its
own plot's cage bases). Nothing about any other player, and nothing about a camp's traps, prize or layout:
camp visuals depend on the tier only and keep out of the camp and the camera corridor. State is sent with
`FireClient` to its owner only (`check_stealacryptid_night` makes the emulator deliver per player, as Roblox
does, and asserts the neighbour's Bigfoot cage stays plain). The review fixes (§13) read nothing new: the ravine
is built from the road's Ground, the knock cut from the Ground and the player's own root, and the view guard
from the local camera, the root and `Config`. Every local part is anchored, non-collidable,
non-queryable, non-touchable and casts no shadow; zero attributes under workspace/ReplicatedStorage
(`check_stealacryptid` and the night check). **Spawn order** (`robloxemu/SPAWN-ORDER.md`): the night never
writes the character's CFrame; the server's wait-for-parent spawn is untouched and `check_stealacryptid`'s
spawn blocks are unchanged and green. **What other players see:** a stumble with nothing hitting, and a
player sitting down — the fire and the hazard are local (Studio item 16).

---

## 6. Budgets (measured)

Everything is built on the client; the server builds none of it. `Config.Night.Budget` is asserted on every
frame of `check_stealacryptid_night` (join, four home bands, four camps, every seam) and of
`check_stealacryptid_budget` (the worst reachable case: nine habitats, a hazard flying most of the time, the
strange → mythic seam, the campfire, all four camps, three cycles).

**Capped in code since 2026-09-30** (second review, finding 5, §14): every piece of scenery, critter and habitat
is admitted against the budget minus `Budget.Reserve` before it is drawn (`Night.admit` inside NightArt's
`setWeight`; a refused item stays hidden and asks again next time), the emitters are capped every frame in
priority order (campfire, weather, the lit habitat: `Night.capEmitters`), and only the hazard in flight is ever
drawn (`MaxHazards`). The Reserve (10 parts, 1 trail, 2 lights) is what the always-drawn pieces may use: a hazard,
its lane and ring, the campfire and the weather host, measured at 3 + 2 + 4 + 1 parts. With the shipped numbers
the cap trims nothing (the table below is unchanged); `check_stealacryptid_budgetcap` lowers the budget in memory
and holds every frame to it.

| where (8 s there) | parts | emitters (rate) | beams | trails |
|---|---|---|---|---|
| dusk | 61 (53 before the ravine) | 2 (9.0/s) | 0 | 0 |
| moonrise | 89 (81) | 2 (6.8/s) | 0 | 0 |
| strange lights | 103 (95) | 2 (9.9/s) | 3 | 0 |
| mythic night | 110 (102) | 2 (9.9/s) | 5 | 3 |
| **the gathering** (2026-10-01; five habitats) | 154 | 2 (9.9/s) | 5 | 2 |
| Badlands camp | 53 (52 before its sand) | 1 (3.9/s) | 0 | 0 |
| Pine Barrens camp | 44 (42 with bats only) | 1 (2.8/s) | 0 | 0 |
| Loch Shore camp | 31 (22 with bats) | 1 (2.8/s) | 0 | 0 |
| Redwood camp | 32 | 1 (3.9/s) | 0 | 0 |

| metric | measured peak | where | budget |
|---|---|---|---|
| local parts | **176-180** (2026-10-01; 150 before the fifth band) | mythic → gathering seam, hazard flying, nine habitats | 200, and **190 for scenery** (the budget minus its Reserve): `check_stealacryptid_budget` asserts the worst case stays at or under 190, so the cap never refuses a piece. Three legends a side measured 195 there; two a side, 179 |
| particle emitters | 3 | seams (two weathers + the lit habitat) | 4 |
| particles per second | 17.9 | resting by the campfire | 40 |
| beams | **8** | strange → mythic seam (5 aurora + 3 UFO) | 8 — **at the limit, no headroom** |
| trails | 4 | mythic, hazard flying | 6 |
| point lights | 1 | a hazard's blink, or the campfire (never both: no hazard launches while resting) | 3 |
| hazards at once | 1 | | 1 |

(2026-10-01) Unique instances ever built over three cycles of the budget check, with the fifth band: 400, 400, 400
(415, 415, 415 in a run whose crow hazard flew).

**Pooled and cheap:** scenery is built the first time a band needs it and unparented at weight 0 (asserted per
band); critters are pooled per kind, one group spawned per kind per frame, recycled at 1.35 × their ring
(`check_stealacryptid_life`: 5-6 of 6 bats stay in range for 90 s, tumbleweeds 3 of 3 for a whole camp visit,
a meteor up in 52 of 52 seconds); one model per hazard kind, one lane, one ring; one weather host with at most
2 emitters and 24 particles/s (`EnvBands.capRates`, probed directly: 4 kinds asked at 30/s → 2 on, 24/s); one
campfire. Unique instances ever built over three full cycles: the same after every cycle of every run (the
pools do not grow): 340, 340, 340, or 333, 333, 333 in a run where no crow hazard happened to launch (a crow's
model is 7 instances, built the first time one flies; 332 before the ravine). The view guard (§13) builds
nothing: it unparents what is in the way and reparents it when clear; static footprints are cached per
placement, so a frame costs one hull and one separating-axis test per shown home or camp part. These are part
and emitter counts, not frame time: a phone's frame time is on the Studio list.

---

## 7. Gates (final tree after the review fixes; bundle md5 `cd6ada4476987315013b120e13a0d5aa`)

| gate | before the night (CLAUDE.md) | as the interrupted build left it | after the resume session | **after the review fixes (§13)** |
|---|---|---|---|---|
| 9 original specs (Rng, Responsive, Economy, Offers, Layout, Heist, Trace2D, Poacher, CryptidModel) | 1 267 / 0 | 1 267 / 0 | 1 267 / 0 | **1 267 / 0** (files unchanged) |
| `tests/EnvBands.spec` (template) | — | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/Hazards.spec` (template) | — | 102 / 0 | 102 / 0 | 102 / 0 |
| `tests/Rest.spec` (template) | — | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Night.spec` | — | 333 / 0 | 347 / 0 | **427 / 0** |
| `tests/NightConfig.spec` | — | 213 / 0 | 214 / 0 | **222 / 0** |
| **spec total (14 files)** | 1 267 / 0 | 2 094 / 0 | 2 109 / 0 | **2 197 / 0** |
| `check_stealacryptid` | 332 / 0 | 332 / 0 | 332 / 0 | 332 / 0 (file unchanged) |
| `check_stealacryptid_guards` | 184 / 0 | 184 / 0 | 184 / 0 | 184 / 0 (file unchanged) |
| `check_stealacryptid_hud` | 2 × PASS | 2 × PASS | 2 × PASS | 2 × PASS (file unchanged) |
| `tests/walk.luau` | 46 / 0 | 46 / 0 | 46 / 0 | 46 / 0 (file unchanged) |
| `check_stealacryptid_compile` | — | 40 / 0 | 40 / 0 | 40 / 0 (20 sources) |
| `check_stealacryptid_night` | — | 386 / 0 | 386 / 0 | 386 / 0 |
| `check_stealacryptid_hazards` | — | 54 / 0 | 69 / 0 | 69 / 0 (two telegraph comparisons: + 1e-6 for float noise, §13) |
| `check_stealacryptid_rest` | — | 63 / 0 | 63 / 0 | 63 / 0 |
| `check_stealacryptid_nighthud` | — | 3 × PASS | 3 × PASS | 3 × PASS |
| `check_stealacryptid_budget` | — | **11 / 12 — never passed** | 28 / 0 | 28 / 0 |
| `check_stealacryptid_lateroad` | — | — | 10 / 0 | **12 / 0** (the far floor is a frame now: its hole, not a slab, is centred on the road) |
| `check_stealacryptid_keepout` | — | — | 24 / 0 | 24 / 0 |
| `check_stealacryptid_life` | — | — | 4 / 0 | 4 / 0 |
| `check_stealacryptid_longroad` | — | — | 2 / 0 | **4 / 0** (+ the ravine round a 2 520-stud road) |
| `check_stealacryptid_edge` | — | — | — | **25 / 0** (new: findings 1 and 2) |
| `check_stealacryptid_view` | — | — | — | **44 / 0** (new: finding 3, camps and home) |
| **headless total** (counted) | 562 / 0 + 2 PASS | 1 116 / 12 + 5 PASS | 1 188 / 0 + 5 PASS | **1 261 / 0 + 5 PASS** |

**Stability** (unseeded `Random`). Resume session, on its final tree: `check_stealacryptid_hazards` 16 of 16 runs
green; night, rest, budget, lateroad, keepout, life, longroad and nighthud 5 of 5 each; the four unchanged gates
(`check_stealacryptid`, `_guards`, `_hud`, `tests/walk`) green in all five full gate runs of that session. An
earlier R2 assertion ("every hazard is a near-hit") failed 2 runs in 10 — a hazard that locks while the player is
mid-walk passes 8-9 studs off — and was relaxed to "at least 60 %" with the measured range printed, before its
final sweep. **Review-fix session:** on the final sources, 8 full runs of all 30 suites (the last two on the final
bytes of every file) plus 4 sweep baselines: all green but one, below. Extra runs: `_night` 8 + 16, `_hazards` 8 +
10, `_keepout` and `_life` 8 each, `_view` 6 and `_edge` 6 on their final versions (8 each before V4, H4 and the
stricter E2): all green. Two red runs on the way, both closed in §13 and neither caused by the fixes:
`_night` once caught a wisp's halo 0.2 studs inside the camera corridor's corner (a latent gap in the first night's
critter keep-out; 0 of 12 runs of the unfixed tree, 0 of 16 of the next), and `_hazards` once measured a bat's
warning as exactly 89 frames, which float noise put 1e-15 under its own bound ("shortest 2.97"; a test-arithmetic
bug in that unchanged check: 86 % of 89-frame spans do this once the clock is large).

**Static checks.** `luau-compile.exe` and `luau-analyze.exe` no longer exist on this machine (the shared
scratchpad that held them was wiped on 2026-09-23; only `luau.exe` survived, and downloading a new release
needs the owner's go). `check_stealacryptid_compile` compiles every bundled source with `loadstring` and fails
any string `require`: 20 sources clean. Tests and checks compile when they run. **luau-analyze was not run.**

---

## 8. Mutation sweep

Driver: the resume session's `scratchpad/sac_eye3/sweep.py`, re-used unchanged in `scratchpad/sacfix_nk5`
(`sweep.py`, `mutations.json`, logs `sweep_round*.log`, results `sweep_results_*.json`, table `mktable2.py`; scratch,
not in the repo). On a fresh scratch copy verified identical to the real tree (sources, tests, every
`check_stealacryptid*`, the emulator): for each mutation exactly one occurrence replaced and the sha256 checked
changed; the bundle rebuilt and **proved to carry the edit** (the mutated bundle equals the baseline bundle with the
same single replacement); all 30 suites run (14 specs, 15 checks, the walk); the bytes restored and the sha256
re-checked. Every round started from an all-green baseline and ended with the copy's sources byte-identical to the
real tree and the rebuilt bundle identical to the baseline. "Night 425/2" is Night.spec 425 passed, 2 failed;
lower-case names are the `check_stealacryptid_*` files; "rc 1" is a suite that stopped with an error.

The resume session's sweep (46 mutations + 3 controls, all killed / all survived; §12) is superseded by the table
below, which re-runs every one of its edits on the final tree.
**The review-fix sweep re-ran all 49 of those edits on the new tree** (L02's target line changed, so it runs as
L02b, the same edit re-aimed) **plus 27 new ones** covering every new rule and guard, and 3 new controls.

* **Round 1** (76 edits): 67 of 70 mutations killed, 6 of 6 controls survived. Three survivors, each a gap in the
  new TESTS, closed there (never by weakening a mutation):
  E03 (a 1-stud bluff 40 studs down passed E2, which asked only for "a part whose bottom is 40 studs down": E2 now
  asks for ONE face hanging from just under the Ground's top to 40+ studs down, and the same for the far rim);
  V09 (the view kept clear along a LINE to the root instead of round the character: no sampled spot had a pine the
  root's line just misses; H4 now builds that case on purpose); V11 (see V11b).
* **Round 2** (the 3 survivors, every other edge/view edit, the new controls: 18 edits, with the strengthened
  checks): all 15 mutations killed except V11, 3 of 3 controls survived.
* **V11 is an equivalent mutant**, my error in writing it: it cached an animated piece's footprint on WRITE, but the
  read, `if fp == nil or item.animate`, already re-judges animated pieces every frame, so nothing could change.
  **Round 3**: V11b makes the real defect (read and write: Nessie, Bigfoot and the UFOs judged where they first
  stood) and is killed by the new V4 (a camera held behind the loch for Nessie's lap: 537 frames with her neck in the
  way); control CTRL5 survived again.
* **Round 4**: the resume session's controls CTRL1-3 re-run against the final checks: all survived.

**Final: 70 of 70 mutations KILLED (V11 excluded as equivalent, V11b in its place), 6 of 6 controls SURVIVED, 77 of
77 edits proven to reach the bundle.** After round 4, `check_stealacryptid_hazards`' two telegraph-time comparisons
gained a 1e-6 tolerance for float noise (§13); it changes no verdict above, since every mutation moves a warning by
at least a whole frame (0.033 s) or not at all.

| # | mutation | round 1 | final | bundle | red suites in the final round (passed/failed) |
|---|---|---|---|---|---|
| N01 | readability floor forgets FogEnd | KILLED | KILLED | ad4ef132af80 | Night 425/2 |
| N02 | a poacher does not close the hazard gate | KILLED | KILLED | 7c7606dacd6d | Night 421/6, hazards 66/3 |
| N03 | a poacher does not remove a hazard in flight | KILLED | KILLED | 21806e4b76aa | Night 426/1, hazards 66/3 |
| N04 | no settle time after the gate reopens | KILLED | KILLED | 39e680b071e2 | Night 410/17, hazards 67/2, rest 50/13 |
| N05 | lane window not raised: lanes start underground | KILLED | KILLED | 2df6839bf39f | Night 426/1, NightConfig 221/1 |
| N06 | camera corridor behind the gate not kept clear | KILLED | KILLED | e12df678bff7 | Night 424/3 |
| N07 | the COMMONEST habitat is lit | KILLED | KILLED | 52d128013fc9 | Night 425/2, night 385/1 |
| N08 | rank may go backwards | KILLED | KILLED | 62edc735399d | Night 426/1 |
| N09 | a camp is never recognised (always home) | KILLED | KILLED | ef8394bd488f | Night 420/7, hazards 52/8, keepout 21/3, life 3/1, night 325/61, rest 59/4, view 32/5 |
| N10 | no swoop: fliers dive into the ground after arrival | KILLED | KILLED | 8a444e218612 | Night 425/2, hazards 67/2 |
| N11 | a meteorite flies on after arrival | KILLED | KILLED | 4784e8587cef | Night 424/3 |
| N12 | no bump: a hazard flies through a dodger | KILLED | KILLED | 4b3894f5cd3a | Night 425/2, hazards 68/1 |
| N13 | no edge margin | KILLED | KILLED | 32fc75025ade | Night 423/4, hazards 68/1 |
| C01 | rest does not freeze the hazard clock | KILLED | KILLED | e572955058cf | budget 27/1, rest 57/6 |
| C02 | a raid's teleport does not clear a stumble | KILLED | KILLED | 30cfa7119193 | hazards 67/2 |
| C03 | the Hunt panel does not close the gate | KILLED | KILLED | e505b49f31b2 | hazards 67/2 |
| C04 | the client ignores the poacher | KILLED | KILLED | 0d8fdeb5550c | hazards 66/3 |
| C05 | lighting snaps instead of gliding | KILLED | KILLED | cad56f7e4ca0 | night 379/7 |
| C06 | a hit does not void rest | KILLED | KILLED | 8ab98b0b01d3 | rest 55/8 |
| C07 | the client never passes the dodger (fly-through) | KILLED | KILLED | 593521bc739f | hazards 68/1 |
| C08 | habitats dress the wrong plot | KILLED | KILLED | d7e94b8724a2 | night 365/9 |
| A01 | the warning marker blinks after arrival | KILLED | KILLED | dafb7c3860c2 | hazards 67/2 |
| A02 | the ring is drawn under the hazard, not the zone | KILLED | KILLED | afe036395b21 | hazards 68/1 |
| A03 | camp scenery keep-out guard off | KILLED | KILLED | 9c82fcda5348 | keepout 23/1 |
| A04 | local parts collidable | KILLED | KILLED | 6a47cfb8b399 | night 385/1 |
| A05 | a band at weight 0 keeps its parts parented | KILLED | KILLED | dc609bf01619 | budget 27/3, edge 23/2, hazards 52/17, keepout 19/5, night 306/80, rest 51/12, view 34/3 |
| A06 | weather cap bypassed | KILLED | KILLED | 3b724631a21f | budget 26/2 |
| A07 | camp weather hangs over the back fence | KILLED | KILLED | bd89ceebc243 | budget 26/2, keepout 22/2, night 385/1 |
| A08 | critters may wander into a camp | KILLED | KILLED | 0528e5f1563a | keepout 22/2, night 385/1, view 34/3 |
| A09 | critters never expire (never recycled) | KILLED | KILLED | c65512d184c2 | life 2/2 |
| H01 | Rest button shown while raiding | KILLED | KILLED | e718652acc64 | nighthud rc 1, rest 62/1 |
| H02 | the chip never shows the night's line | KILLED | KILLED | 8cef5c0b8f29 | nighthud rc 1, rest 61/2 |
| H03 | the toggle row is not sized for Rest | KILLED | KILLED | 04c4b867dcd3 | hud rc 1, nighthud rc 1 |
| S01 | server does not report the rank | KILLED | KILLED | 9b3822b04cd3 | budget 27/1, edge 22/3, lateroad 11/1, life 1/3, longroad 3/1, night 325/61 |
| S02 | server does not report the plot | KILLED | KILLED | 61cb7d8d4285 | budget rc 1, edge rc 1, hazards rc 1, keepout rc 1, life rc 1, night rc 1, rest rc 1, view rc 1 |
| K01 | hazards 4x more often | KILLED | KILLED | a7fa15d4ab82 | NightConfig 220/2, hazards 68/1 |
| K02 | a camp band lists a hazard | KILLED | KILLED | 492f0159645d | NightConfig 221/1 |
| K03 | edge margin back to 30 | KILLED | KILLED | 43cf397cd26a | NightConfig 221/1 |
| K04 | dusk fog below the readability floor | KILLED | KILLED | 6ff3690f6e72 | NightConfig 220/2, budget rc 1, edge rc 1, hazards rc 1, keepout rc 1, lateroad rc 1, life rc 1, longroad rc 1, night rc 1, nighthud rc 1, rest rc 1, view rc 1 |
| K05 | clearance over a dodger 1.5 | KILLED | KILLED | 60b82b2e580e | Night 426/1, hazards 68/1 |
| K06 | no climb after arrival | KILLED | KILLED | 513bead32959 | Night 426/1 |
| R01 | the road is never looked for again after start | KILLED | KILLED | 11e5cb57c3e7 | lateroad 5/3 |
| R02 | hazards run before the road (edge rule) is known | KILLED | KILLED | 9eb61c1f9e2a | lateroad 11/1 |
| R03 | scenery built before the road is known is kept | KILLED | KILLED | cc927d2ba709 | lateroad 6/2 |
| L01 | the horizon ring never moves off a long road | KILLED | KILLED | e9a2e19969d8 | longroad 2/2 |
| CTRL1 | CONTROL marker text a shade redder | SURVIVED | SURVIVED | 81c086720573 | - |
| CTRL2 | CONTROL aurora beams 20 segments | SURVIVED | SURVIVED | a5b4c7dfd803 | - |
| CTRL3 | CONTROL campfire light 1.6 -> 1.5 | SURVIVED | SURVIVED | 24999ca6652a | - |
| E01 | no ravine: the far floor starts at the Ground's edge (new) | KILLED | KILLED | 2c381acb5dfb | Night 413/14, edge 19/6, lateroad 10/2, longroad 3/1 |
| E02 | one far floor under everything again (the reviewer's tree) (new) | KILLED | KILLED | 74ae82316e0d | edge 19/6, lateroad 7/1, longroad 2/2 |
| E03 | the bluff is a 1-stud slab: no cliff face (new) | SURVIVED | KILLED | 70ad0b9b8c59 | edge 23/2 |
| E04 | the bluff pokes above the Ground's top (new) | KILLED | KILLED | 387c8b531bbc | edge 23/2 |
| E05 | the far rim wall stands up above the far floor (new) | KILLED | KILLED | 8b2de2be8111 | edge 23/2 |
| E06 | ravine 8 studs wide (jumpable) (new) | KILLED | KILLED | d3ff6e2b4731 | Night 423/4, NightConfig 221/1, edge 21/4, longroad 3/1 |
| E07 | far pines may stand in the ravine (new) | KILLED | KILLED | c155136c8d17 | edge 21/4, longroad 2/2 |
| L02b | far pines may stand at the road's edge (the builder's L02, re-aimed at the new line) (new) | KILLED | KILLED | 1dc4f75607a8 | edge 21/4, hazards 68/1, longroad 2/2 |
| K11 | the client does not cut the knock (the reviewer's tree) (new) | KILLED | KILLED | cd3c3ae1f14f | edge 23/2 |
| K12 | the cut ignores PlayerRadius on the + side (new) | KILLED | KILLED | 9407eb811084 | Night 423/4, edge 23/2 |
| K13 | the cut may turn a push around (- side) (new) | KILLED | KILLED | 4a598c4763d1 | Night 425/2 |
| K14 | the z axis is never cut (back and front edges) (new) | KILLED | KILLED | 71f024d39815 | Night 424/3, edge 23/2 |
| V01 | camp scenery is never hidden from the camera (the reviewer's tree) (new) | KILLED | KILLED | 68fb5740254d | view 38/6 |
| V02 | home scenery is never hidden from the camera (new) | KILLED | KILLED | 3f55d02363b4 | view 41/3 |
| V03 | camp critters may fly between the camera and the camp (new) | KILLED | KILLED | 249a40ab5807 | view 42/2 |
| V04 | an occluder fades out instead of going at once (new) | KILLED | KILLED | fbbb6835a5b6 | hazards 68/1, view 38/6 |
| V05 | the view hull forgets the camera (new) | KILLED | KILLED | 3840be533c95 | Night 422/5, view 35/9 |
| V06 | the hull test is only a bounding box (hides too much) (new) | KILLED | KILLED | 05ba9e42505a | Night 426/1 |
| V07 | floor pieces (camp ground, far floor) are hidden too (new) | KILLED | KILLED | 7fc8172879ab | edge 23/2, lateroad 11/1, night 382/4 |
| V08 | the view hull is never recomputed (new) | KILLED | KILLED | a3dd7ce2e628 | view 35/9 |
| V09 | home view box ignores HomeViewRadius (a line to the root) (new) | SURVIVED | KILLED | 27b6aa05ba45 | view 43/1 |
| V10 | Config: HomeViewRadius 0 (new) | KILLED | KILLED | 9d9084a37a07 | NightConfig 221/1, view 43/1 |
| V11 | an animated piece's footprint is cached (Nessie, Bigfoot, UFOs never re-judged) (new) | SURVIVED | EQUIVALENT (see V11b) | ec43e4b5427b | - |
| V12 | the client never tells the art where the player is (new) | KILLED | KILLED | 6d5a6ae6f0b8 | view 41/3 |
| W01 | critters kept out by a circle again (a wisp halo reaches a corner) (new) | KILLED | KILLED | 1b108fed32bf | Night 426/1 |
| CTRL4 | CONTROL bluff and ravine rock a shade redder (new) | SURVIVED | SURVIVED | 6b3ae51e41a1 | - |
| CTRL5 | CONTROL occluders fade back in over 0.45 s (new) | SURVIVED | SURVIVED | c806fed36cb5 | - |
| CTRL6 | CONTROL ravine walls 2.5 studs thick (new) | SURVIVED | SURVIVED | 7273a302313b | - |
| V11b | an animated piece's footprint is cached for real (read and write): Nessie, Bigfoot, UFOs judged where they first stood (new) | (new in round 3) | KILLED | f0c044cb4534 | view 42/2 |

---

## 9. Needs Studio (only real rendering and a real device can judge)

1. **Every band's look**: the four home grades and four camp grades; whether the dusk rose and the mythic gold
   read as "deeper night" while the lair, tier colours and neon nets still read. The readability floor is a
   set of numbers against v1, not a picture.
2. **Atmosphere vs fog**: fog values are blended, but Roblox ignores legacy fog while an Atmosphere exists
   (CLAUDE.md Studio item 1). Which one is actually doing the work at each band.
3. **Stars and moon**: `StarCount` 300-4 500 and `MoonAngularSize` 14-30 through an Atmosphere of density 0.24-0.40;
   the client-created `CryptidSky` popping in at join.
4. **Distant set pieces**: ridges 820-1 000 studs out, UFOs 680-760, Bigfoot 700 (98 studs tall), redwoods
   190 tall, the loch castle 430 out — visible through the haze, and at lower graphics quality?
5. **Beams**: both auroras (camera-anchored, 620 studs toward +Z, `FaceCamera` off, curve sizes) and the UFO
   tractor beams — almost certainly need hand tuning. Beams are at the budget's limit (8 of 8).
6. **Critter and hazard models**: crow/bat wing axes, bat wobble, wisp bob, tumbleweed roll, meteor trail;
   **are dark crows and bats visible against a dark sky** (the `!` marker and red blink are meant to carry it).
7. **The hazard drawing**: does the swoop after arrival read as "it flew off", the meteorite vanishing at the
   ring as an impact (there is no dust puff), and the rise over a dodger as "it missed me"?
8. **The stumble on a real humanoid**: `PlatformStand` + a 24-34 studs/s push on grass — does it look like a
   stumble, how far does it slide (the 33-stud edge margin assumes no friction), does it release cleanly.
9. **Telegraph readability on a phone**: marker, lane and ring at night; the 1.5-2 s after the lock with a
   thumbstick; the chip line under the HUD's top row.
10. **Rest**: `Humanoid.Sit = true` without a seat from the client (does it sit and replicate; does walk input
    wake it); the campfire's size and light; the depth of field's strength.
11. **The Rest toggle in the top-right row on a real phone** (four buttons in a camp-free row, notch/safe area).
12. **Habitats**: the patch and rim on the cage base (z-fighting at 0.04 studs), props clipping cryptid models,
    whether the tier rim reads, the lit habitat's particles.
13. **Owls** on the road's pine crowns: size, blink, facing the camera; with StreamingEnabled far crowns may not
    have streamed in when the road is first seen (fewer owls).
14. **Camp views from the gate**: that the loch/castle/Nessie and redwoods read at night. (Nothing local can sit
    between the camera and the camp from any camera spot: the view guard, §13, checked at 11 520 real camera
    spots. What only Studio shows is how it looks.)
15. **Frame time** on a mid/low phone at the strange → mythic seam (150 parts, 8 beams) with a full lair and
    neighbours' lairs around, and with the view guard's per-frame test (one hull, one separating-axis test per
    shown home or camp part; static footprints cached).
16. **Other players** see a player stumble with nothing hitting, or sit down with no fire: glitch or charm?
17. **Late replication**: a client that starts before the road arrives shows the sky and waits for the road for
    the horizon, owls and hazards (checked headless); how long that takes on a real join.
18. **Title cards** over the HUD on a phone.
19. **The ravine** (§13): does the Ground read as a bluff at night — the Ground's 1-stud grass edge over the slate
    face (0.1 studs inside it: any z-fighting?), the 24-stud gully and the far rim's face — and what shows at the
    bottom (the void: sky or haze colour, a dark gully or a glowing band?). Does anyone still try to jump it?
20. **The view guard's pop** (§13): a pine, redwood or ridge that swings in front of a zoomed-out camera vanishes
    at once and fades back in over 0.4 s. Does that read as natural at far zoom, or does a fade-out margin look
    better (at the cost of the "never in the way" guarantee)?
21. **A server boundary** (owner decision, §13 finding 1): if invisible walls round the Ground are wanted, check
    first whether a collidable, fully transparent wall between a zoomed-out camera and a cage hides the cage's
    ProximityPrompt (`RequiresLineOfSight`), and whether it blocks ClickDetector clicks on the build tiles.
22. **Ball parts with a non-uniform Size.** The night declares many (far pines 12 × 34 × 12, ridges, redwood
    crowns, UFO domes, owls, habitat props). The reviewer's geometry assumed a Ball draws as a sphere of its
    SMALLEST axis; if Roblox does that, a far pine is a 12-stud ball floating 9 studs over the forest floor.
    Check one in Studio; if so, give those parts a SpecialMesh (MeshType Sphere scales per axis). The view
    checks already test every part as the box of its declared Size, so they hold either way.
23. **The fall rescue** (owner decision (d), §11): a server CFrame on a falling, client-owned character 12+ studs
    below the Ground's top. Does it land cleanly on the arrival marker (no fling, no camera snap from the ravine),
    is the toast noticed, and does the engine's own FallenPartsDestroyHeight never get there first on a slow server?
24. **The band title card's new place** (§14 finding 4): under the HUD's top stack (the chip's slot kept) and
    above the touch-control band, shrunk (title first) or title-only on a short phone. Does it still read as a
    moment, and does it feel right that a band reached with the Hunt panel open is named when the panel closes?
25. **The lingering ring** (§14 finding 1): after arrival the hazard keeps its lane's line, level at the height it
    arrived, for as long as the ring stays up (0.63 s at most in `Night.spec`'s replay of players inside the ring), then swoops away. Does a
    crow skimming through the ring at root height read as "still coming", and the meteorite resting a moment?
26. **The campfire at the cliff** (§14 finding 3): it moves behind or beside a player who sits facing the ravine.
    Does a fire behind the avatar read, or should the seated player be turned to face it?
27. **The Gathering's sky** (§15): the crimson moon is a 120-stud Neon ball with a 200-stud halo, 730 studs from the
    camera and riding with it, while the sky's own moon shrinks to 6. Does it read as a blood moon or as a red blob;
    does the halo band against the atmosphere; is the crimson grade too much over a lair full of tier colours?
28. **The legends on the far floor**: dark 30-stud silhouettes 54 studs past the Ground's edge, eyes glowing. Do they
    read at 4:36 am against the far pines and the fog (FogEnd 600), from the apron and from behind the cage row; are
    they too scary for the audience; do players walk to the edge to look (the fall rescue catches them)?
29. **Moths and the Jersey Devil**: pale Neon moth wings at 40-120 studs (visible flutter, or specks?); the Jersey
    Devil circling 110-220 studs out and 40-90 up over the Pine Barrens (a silhouette against the sky?).
30. **The new weather**: sand blowing sideways behind the Badlands camp (does it read as wind?), spores in the
    redwoods, embers at home.
31. **Frame time at the mythic → gathering seam**: 176-180 local parts with nine habitats and a hazard, on a phone.

---

## 10. Thumbnail shot list (for the night Studio session)

**This recipe has not been tried in Studio. Check step 1 before relying on the rest.** Every shot is **1920x1080**
(16:9, the size Roblox shows an experience's thumbnails at): set the Studio viewport or the capture to 1920x1080
before framing, and keep the subject inside the middle 1440x1080 (a list tile crops the sides). The vertical gameplay
clips are a separate list: MARKETING.md.

**Getting there without touching real saves**

1. **Build a fresh place with the night.** In `steal-a-cryptid/`, `rojo build -o StealACryptid-shots.rbxlx`,
   open that file. `*.rbxlx` is git-ignored. Keep Rojo disconnected while editing the place.
2. **No saves.** *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server then plays
   a fresh profile that is never written (a "not saving" banner shows; hide the HUD for clean frames).
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/` (nothing is published from Studio):
   * **Session A (shots 1, 2, 4, 5, 6):** `Config.Economy.StartEssence = 50000000`, `Config.Economy.StartCages = 9`,
     `Config.Night.Hazards.IntervalMin = 100000`, `Config.Night.Hazards.IntervalMax = 100001` (no hazard can
     knock the avatar out of a frame), `Config.Poacher.FirstAfterSeconds = 100000` (no poacher walks into shot).
   * **Session B (shot 3):** the same Essence, cages and poacher line, plus `Config.Night.Hazards.IntervalMin = 8`,
     `IntervalMax = 10` and **`Config.Night.Rest.IdleSeconds = 0`** (`Rest.validate` accepts 0: it turns idle
     rest off; without it the night rests after 20 s of standing still and the hazard never comes).
4. **Ranking up** (the sky follows the Journal; it never goes back within a session, so shoot in band order):
   press E at the **first pedestal (P1, a Jackalope for 30)**, then at **P3** (it always shows the next tier up)
   three times — Rare, Legendary, Mythic — waiting ~3 s between for it to refill. A card names each new band.
   Then fill the other cages from P1/P2 so all nine have habitats.
5. **Positions** assume the first player gets `Plot_0`: its plot-local (x, z) is world (x − 36, y, z + 16),
   facing +Z from the road. Arrival marker (0, 3, 24); the cage row is world z 104-112 (cage 5 at x 0); P3 at
   (−30, 24), the Hunt Board at (26, 24). The home horizon is centred on `workspace.Road.Ground.Position`,
   whose length depends on the place's `Players.MaxPlayers` (set it to 8, CLAUDE.md known gap). The first raid
   of the server uses pocket 0: camp-local (x, z) is world (4000 + x, y, z), the gate at (4036, 0, 20).
6. **Framing tools** (command bar, Client context):
   `local c = workspace.CurrentCamera; c.CameraType = Enum.CameraType.Scriptable; c.CFrame = CFrame.lookAt(Vector3.new(X, Y, Z), Vector3.new(TX, TY, TZ))`
   (back: `c.CameraType = Enum.CameraType.Custom`). Clean frames:
   `local g = game.Players.LocalPlayer.PlayerGui; g.CryptidHud.Enabled = false; g.CryptidNight.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   Find a moving piece: `for _, n in {"Ufo", "Bigfoot_Torso", "NessieHead", "GlimpseTorso"} do local p = workspace.CryptidNight:FindFirstChild(n); print(n, p and p.Position) end`.
   The auroras are anchored to the camera, 620 studs toward world **+Z** and 300 up: to have one in frame the
   camera must face +Z and look up ~25°.
   **The view guard** (§13) hides any scenery that stands between the camera and your avatar at home (or the
   camp, in a camp): a pine framed in FRONT of the avatar disappears. For such a frame, park the avatar out of
   that line (a pine behind or beside the subject is untouched).

**The shots** (session A unless stated; in band order)

1. **"Resting under the Strange Lights"** (rank 3, before buying the Mythic). Stand on the apron at world
   (0, 3, 20) facing the road (−Z), press **Rest**: the avatar sits, the campfire appears 4 studs toward the road.
   Camera ≈ (−9, 5, 4) looking at (0, 14, 60): the fire and the seated avatar in the lower third, the lair
   behind, the **green aurora** across the upper sky; wisps and a pair of **red eyes** in the treeline if they
   pass. For a crisp background set `game.Lighting.CryptidRestFocus.Enabled = false` (Client) — the rest blur is
   part of the feature, so take one of each.
2. **"Mythic Night over the lair" — the hero** (rank 4, nine habitats). Camera on the road in front of Plot_0 ≈
   (−30, 18, −30) looking at (0, 40, 140). In frame: the cage row's **nine glowing habitats** (the Bigfoot's
   rainforest with its mist), the **gold aurora**, 4 500 stars and the big moon; with MaxPlayers 8 the first UFO
   (≈ Ground centre + (390, 190, 557)) sits upper left (+X is screen-left when facing +Z); behind the cage row the
   Ground ends in the ravine's rock face at z 130, with the far forest floor and pines beyond it. Take a burst:
   the meteors streak across every few seconds.
3. **"Close call"** (**session B**, rank 4). Buy, step on the Collect Pad, start a hunt at the board and leave the
   camp (the tutorial must be done). At home, stand still with the **normal** camera tilted to look level or a
   little up (lanes come down out of the sky only then; looking down they come in level). A **meteorite** — glowing
   rock, orange trail, `!` marker — comes every 8-10 s. When the ring turns red (`Move! Leave the red ring`),
   walk out of it **sideways** and shoot as it strikes the ring. In frame: the meteorite and its trail, the red
   lane and ring, the avatar clear of it, the gold aurora above. A hit only stumbles the avatar; nothing is lost.
4. **"Bigfoot on the ridge"** (rank 4). From the back of Plot_0's cage row, camera ≈ (0, 30, 120), look toward
   `Bigfoot_Torso` (he walks a 57° arc around the Ground centre at ~700 studs, on the −Z side, 98 studs tall):
   `c.FieldOfView = 25` for a telephoto. In frame: Bigfoot's silhouette on the horizon over the road and the
   opposite lairs, a UFO's tractor beam near him if one is close (the second UFO is ≈ centre + (327, 210, −642)).
   `c.FieldOfView = 70` after.
5. **"Loch Shore Camp"** (rank 4; release one cryptid at its cage first: a hunt needs a free cage). Hunt Board →
   Camp 3. You have 150 s. Camera behind the gate ≈ (4036, 22, −25) looking at (4080, 8, 320). In frame: the camp
   in the foreground (fences, nets, the glowing cage row), beyond the back fence the loch with its moon glint, the
   **castle tower with its lit window** (≈ (4210, 0, 430)), mist, and **Nessie** crossing (x 3830 → 4350 at z 250,
   4 studs/s; wait until `NessieHead` is between x 4000 and 4120). Leave the camp after.
6. **"Redwood Camp"** (rank 4). Hunt Board → Camp 4 (3 s after the last hunt). Camera low behind the gate ≈
   (4036, 4, −20) looking up at (4036, 120, 220). In frame: 190-stud **redwoods** towering over the camp's back
   fence, mist, wisps, and the **Bigfoot glimpse** between the trunks (`GlimpseTorso`, 150 studs from the camp
   centre, swinging ±55° over ~2 minutes).
7. **"The Gathering"** (session A; added 2026-10-01). From Mythic Night (shot 2), buy two more Bigfoots at P3, 2.5 s
   apart: the second takes the best lair income past 1 350/s and the sky glides to the Gathering (the card names it).
   Camera behind the cage row ≈ (0, 30, 118), `c.FieldOfView = 80`, looking at ≈ (40, 60, 400): this side's legends on
   the far floor at the left (with MaxPlayers 8 near (96, −1, 184) and (256, −1, 184): `for _, d in
   workspace.CryptidNight:GetChildren() do if d.Name == "Legend_Body" then print(d.Position) end end`), the crimson
   moon high on the right (it rides with the camera, ≈ camera + (−280, 190, 660)), embers in the air, the nine
   habitats' glow below. `c.FieldOfView = 70` after.

---

## 11. Not done / open

* **Two adversarial reviews** (§13: three findings; §14: five findings), all closed test-first. Nobody has reviewed
  the second round's fixes: a next reviewer should look at `Hazards.threatLive` in the client (the lingering ring
  and chip, `Night.drawPosition`'s `liveUntil`), the queued rest mid-stumble, `Night.campfireSpot`, the card's
  place (`NightBus` CardTop/CardBottom) and its deferral, the budget gate (`Night.admit` in `setWeight`,
  `capEmitters`, `Budget.Reserve`) and the server's fall rescue.
* **Owner decisions.** The owner decided on 2026-09-30: "take the recommended option for all". None of the four
  below had an option marked as recommended, so each takes the option that best serves the brief (fair, fun,
  never punishing, never exploitable), with the reason:
  (a) **Knock rate for a player who ignores warnings**: one per 2.9-6.7 min of home time (§3, R3). The brief
  says hazards are rare; a knock costs nothing. The knob is `Config.Night.Hazards.IntervalMin/Max` (120/180).
  **DECIDED 2026-09-30 (owner: take recommended): keep 120/180.** The warned player gets the brief's "one
  near-hit per 2-3 minutes"; the one who ignores every warning is knocked every 3-7 minutes and loses nothing. A
  shorter interval would make the reacting player's near-hits more frequent than the brief asks; a longer one
  makes hazards forgettable. Pinned: `NightConfig.spec` asserts 120 and 180 exactly (mutant M34 killed, §14).
  (b) **The theme direction's yeti (snowy peaks) and aliens (UFO field)**: this game has eight species and no
  yeti or aliens, so there is no snowy habitat or camp; the UFOs appear in the Mythic Night sky instead. A snowy
  camp tier or a Yeti species is a design change (DESIGN.md §16).
  **DECIDED 2026-09-30 (owner: take recommended): keep the eight species and four camp tiers; the aliens stay in
  the Mythic Night sky (three UFOs with tractor beams) and Bigfoot, the yeti's cousin, walks the horizon.** A new
  species or tier changes prices, the saved profile, the camp solver and the pacing, all measured and tested for
  eight species; nothing in the brief asks for it, and it would reopen every economy number. No code change.
  (c) **A clock-driven day/night cycle** was not built: the brief says progress drives the environment, and the
  game is a night game. A slow cosmetic drift inside each band is possible later.
  **DECIDED 2026-09-30 (owner: take recommended): no clock cycle; the Journal's rank drives the sky.** The brief
  says progress drives the environment; a clock would change the lair's light while the player does nothing and
  would have to be held to the readability floor on every frame for no gameplay gain. No code change: the
  existing `Night.spec` progress rules (rank, never a timer, never backwards) already pin it.
  (d) **A server-side world boundary.** As in v1, a player who walks off the Ground falls into the void and
  respawns (nothing is lost); the night now shows the edge as a ravine instead of hiding it (§13). Invisible
  walls would stop the fall but change v1's geometry and may hide cage prompts from a camera behind them
  (Studio item 21). Not built.
  **DECIDED 2026-09-30 (owner: take recommended): no invisible walls; the server catches the fall instead.** A
  character at home whose root falls `Config.World.FallRescueStuds` (12) below the Ground's top is put back on its
  own arrival marker at once, at rest, with the toast "That is a long way down - back to your lair". Walls were
  rejected for the prompt risk above; doing nothing kept a death and a respawn for a walk off a cosmetic cliff,
  which is punishing for no reason. Not exploitable: it only returns a player to their own lair, which Reset
  already does (slower), and never in a raid (a camp pocket still belongs to the raid). Test first:
  `check_stealacryptid_fall` (13 assertions; 9 failed before the rescue existed). Studio item 23.
* **luau-analyze was not run** (§7); only compile-by-loadstring. (2026-10-01: the binary is still missing.)
* ~~No Luau pacing model for time-to-band~~ (2026-10-01: `tests/Pacing.spec.luau`, §2).
* **Nobody has reviewed pass 2** (§15): the fifth band, `Night.level`, the camps' weather and critters, the
  critter `reach`, the budget-under-the-Reserve rule.
* Not committed, not pushed, not published. Studio not opened.

---

## 12. Resume session (2026-09-24): what the interrupted build left, and what changed

The interrupted build (stopped by a usage limit on 2026-09-23 ~18:23) had written every source, both specs,
the template copies and six checks. Nothing had been committed; there was no EYECANDY.md. This session
re-read every new and changed file (`git status`/`git diff` in the game), rebuilt the bundle (byte-identical
to the one on disk), ran every gate, and then looked for what the gates did not see.

1. **`check_stealacryptid_budget` had never passed** (11 / 12 on the tree as found; its last run log predates
   it). It filled all nine cages, so every hunt was refused with `Free a cage first`. Fixed in the check: one
   cryptid is released through the real prompt before the camps. Added a direct weather-cap probe (4 kinds at
   30/s → 2 emitters, 24/s) and the camp weather's placement behind the back fence.
2. **Edge margin below the knock's slide**: 30 studs against a frictionless 32.1. Spec first (watched fail),
   then `EdgeMarginStuds` 33.
3. **Hazards after arrival** (a template assumption that only holds in open sky): with the camera level or
   looking up, crows and bats flew on into the ground (1 083-1 333 part-frames under the floor per run) with the
   `!` marker still blinking (694-1 144 frames), and a player who dodged along the lane saw the hazard fly
   through them (closest 0.2-0.7 studs; +1 Jump's open Studio question 22). Specs and checks first (watched
   fail: H7, H8, H9, Night.spec), then `Night.drawPosition` + the marker off at arrival or hit. After: 0, 0,
   3.3-5.5 studs. The hit rule did not change.
4. **A client that starts before the road replicates** (normal for a LocalScript, more so with streaming) read
   the road once: the whole horizon centred on the world origin, no owls ever, and hazards with no edge rule.
   `check_stealacryptid_lateroad` written first (watched fail: 3 failures), then the client looks for the road
   once a second until found, hazards wait for it, and home scenery built before it is rebuilt around it.
5. **A long road**: at `MaxPlayers` 50 the road is 2 520 studs and the fixed horizon ring stood ridges and
   Bigfoot on the lairs. `check_stealacryptid_longroad` first (watched fail: a ridge 0.0 studs off the road),
   then `offRoad` pushes each horizon piece out until its footprint clears the road by 40 studs (bisection, so
   the walking Bigfoot moves smoothly). The look at 8-12 players is unchanged.
6. **Two mutation survivors in the first sweep** (41 mutations and 3 controls: 39 killed, 2 survived, the 3 controls survived):
   the camp keep-out guard switched off (no shipped piece reaches the keep-out, so no check reached the guard)
   and critters that never recycle (the sky empties at the same part count). Closed test-first in the only
   honest order a test gap allows: `check_stealacryptid_keepout` (widens the keep-out in memory; 30 320
   violations and "0 fewer parts shown" with the guard off) and `check_stealacryptid_life` (bats in range 0,
   meteors up 0 of 52 s with recycling off) pass on the real build and fail on the mutants.
7. **Rarity measured the owner's way**: R2 (lair life, reacting) and R3 (ignoring), with near-hits counted by
   the closest part of the model to the root, and the dodged hazards' closest approach (H7).

Files written this session: in `steal-a-cryptid/` — `src/shared/Night.luau`, `NightArt.luau`, `Config.luau`,
`src/client/Night.client.luau`, `tests/Night.spec.luau`, `tests/NightConfig.spec.luau`, this file, README.md
and CLAUDE.md; in `robloxemu/` — `check_stealacryptid_{budget,hazards}.luau` (extended),
`check_stealacryptid_{lateroad,keepout,life,longroad}.luau` (new) and `build/steal-a-cryptid.luau` (rebuilt).
Nothing else: no other game, `robloxemu/emu`, `tools`, `docs` or any marketing folder.

---

## 13. Review 2026-09-24: three findings, reproduced, fixed test-first

An adversarial reviewer re-ran every gate from a clean bundle (byte-identical to the builder's, counts matching)
and probed the night through the real server and client. Three findings; each was reproduced first with the
reviewer's own probe (`scratchpad/sacrev_night_k4/robloxemu/probe_*.luau`, run unchanged on a copy of this tree),
then a failing test was written and watched fail, then the game was fixed (never the test), then the probe was
re-run. Scratch: `scratchpad/sacfix_nk5` (copies, logs, the sweep).

### Finding 1 (medium): the far floor hid the world's edge, and walking onto it dropped the player into the void

**Reproduced.** The server's Ground (696 × 260 at 12 players, top y −0.2) is the only floor at home. The night's
local `FarGround` was one 2 048 × 2 048 slab, top y −1.3 (1.1 studs lower), opaque grass, non-collidable, in all
four home bands. At (48, 135), 5 studs behind the back edge between Plot_0 and Plot_2, and at (−106, 0), 10 studs
past the road's −x end, the only part under the point was `FarGround` (no collide). Nearest local far pine: 37.8
studs past the real edge. Same numbers as the review.

**Test first.** `check_stealacryptid_edge` E1-E3 (real server and client, at moonrise and at mythic night):
nothing local at walking height (y −20.2 … 2.8) at 2 608 points 0.25-23.5 studs past every side and corner; a
cliff face at least 40 studs deep under every edge, never above the Ground's top; a cliff face under the far rim,
never above the far floor; the forest floor still there beyond, at y −1.3; no far pine over the ravine. On the
unfixed tree: 2 608 of 2 608 points had the false floor, and 162 edge points and 166 rim points had no cliff face.
`Night.spec` (the frame's geometry at 8, 12 and 50 players and an odd road) and `NightConfig.spec` (the ravine is
over twice a running jump: 8.5 studs at WalkSpeed 16 with Roblox's default JumpPower 50 and gravity 196.2; the
game sets neither) failed on the missing rule.

**Fixed (client, cosmetic).** `Night.farGroundRects`: the far floor is a FRAME of four slabs around a hole, the
Ground grown by `Config.Night.Ravine.Width` (24 studs), reaching 1 024 studs from the road's centre (as before),
or 200 past the ravine on a longer road. `NightArt` hangs a rock BLUFF under the Ground (80 studs deep, its top
inside the Ground's slab, its faces 0.1 inside the Ground's edges, so it adds nothing to stand on) and four rock
walls under the far rim. Far pines keep 36 studs off the edge (`PineMargin`), wholly beyond the ravine. Before
the road is known the far floor is one slab round the origin, rebuilt round the road when it arrives (as before).
**After:** the reviewer's probe finds nothing under (48, 135) or (−106, 0); E1-E3 green at 12 players; at 50
players `_longroad` finds nothing at walking height in the ravine and the far floor beyond it on all four sides.
(The mutation sweep then showed E2 too lenient: a 1-stud bluff 40 studs down passed it. E2 now asks for ONE face
hanging from just under the Ground's top to 40+ studs down, and likewise under the far rim; §8, E03.) The edge now reads as an edge: a grassy bluff falling into a dark ravine, the forest
beyond. It is visible behind the lairs in shot 2 of the shot list.

**What is left (owner decision, not built).** As in v1, past the Ground's edge is still the void: a player who
walks off it on purpose falls and respawns (nothing is lost). The difference is that it now looks like a drop. A
server-side boundary (invisible walls round the Ground) would stop it, but it is a gameplay change the night was
not asked for, and a collidable invisible wall between a zoomed-out camera and a cage can hide that cage's
ProximityPrompt (`RequiresLineOfSight`), which only Studio can settle (§9 item 21).

### Finding 2 (low): the edge margin only stops launches; a hazard in flight knocked a player on toward the edge

**Reproduced** with the reviewer's probe: a player 45 studs from the −x end, rapid hazards, strafing toward the
edge until the chip says `Move!`, then stopping in the ring: 24 of 24 hit 17.8-19.4 studs from the edge; 20 of 24
frictionless slides (push × KnockSeconds) ended 0.2-9.1 studs past it (the review: 19 of 24).

**Test first.** `Night.spec`: `Night.limitKnock` over 90 000 knocks (positions hugging all four edges and
corners, 48 headings, three strengths): no slide ends outside the Ground's inner keep band (or farther out than it
started), no push is strengthened or turned around, the lift never changes, and a knock that cannot reach the band
is exactly the template's; the reviewer's own hit stops PlayerRadius inside the end. `check_stealacryptid_edge` K1:
the reviewer's set-up toward all FOUR edges, 6 walks each, at rank 2 (bat, crow) and rank 4 (meteorite, the
hardest knock, and wisp); K2 control: a hit in the middle of the road keeps the template's full push. Unfixed:
14 and 10 of 24 (rank 2, two runs) and 8 of 23 (rank 4) slides ended within 1.5 studs of the edge or past it.

**Fixed (client).** On a hit, `Night.client` passes the template's push through `Night.limitKnock(groundRect,
pos, kv, KnockSeconds, PlayerRadius)`: the outward part of each axis is cut so the frictionless slide ends at
least 1.5 studs inside the Ground, never below zero. The stumble (PlatformStand) is unchanged, so a hit near the
edge is still a stumble. **After:** the reviewer's probe: 24 hit, 0 slides past the edge. K1: 48 walks, 47 hits,
closest slide end 1.50 studs inside; K2: every hit in the middle of the road kept the template's full push. With
finding 1's ravine, no hazard can knock a
player into it, even under the frictionless bound; how far a real stumble slides on grass is still Studio item 8.

### Finding 3 (low): camp scenery could hide the raider from a far-zoomed camera outside the gate corridor

**Reproduced** with the reviewer's probe: Rare camp 15 of 900 camera spots (RingPine), Mythic camp 15 of 900
(Redwood), the others 0. That probe collects the shown parts once and then only computes geometry for camera
spots the client never sees, so it measures the layout, not a fix that reacts to the camera. A copy that puts the
real camera at each spot and fires one client frame (`probe_campview_live.luau`; that is its only change) gives
the same 15 and 15 on the unfixed tree.

**Test first.** `check_stealacryptid_view` V1-V3: every camp tier, 5 raider spots × zoom 20-400 (Roblox's default
`CameraMaxZoomDistance` is 400 and the game sets none) × 24 yaws × 3 pitches (10, 25 and 50° down) = 2 880 real
camera spots per tier, one client frame each: no shown local part (scenery or critter, each tested as the oriented
box of its declared Size, a superset of any Ball or Cylinder drawn inside it) on the line from the camera to the
raider or to 10 points of the camp (four corners low and high, the gate, the cage row). V2: the guard really
hides something from the side, and never more than two thirds of a camp's scenery; V3: the follow camera behind
the gate and a camera over the camp hide nothing, and everything comes back. Unfixed: 114 / 625 / 1 / 745 of
2 880 spots per tier (mesas, cacti, pines, redwoods, a bat, wisps: wider than the reviewer's probe because zoom
reaches 400 and the nets are targets too). `Night.spec`: the hull is convex and holds the camera and the camp for
400 cameras; the separating-axis test agrees with sampling for 400 random boxes; named cases; over 6 000 random
cameras (70-460 studs out) and parts, every part on a line of sight to the camp is flagged (213 of 213), and the
test is tight (213 flagged in all).

**Fixed (client).** Every line of sight from the camera to any point of the camp, at any height, projects into the
2-D convex hull of the camera's position and the camp's rect (`Night.campViewHull`: the keep-out's camp rect, that
is the fences, sign and cage row grown 8 studs). Each frame `NightArt:occlude`, run last for every shown camp
piece, hides a part whose footprint enters that hull AT ONCE (on the frame the camera moved) and fades it back in
over 0.4 s once it is clear; `Night.client` keeps camp critters out of the same hull (a critter inside is
recycled, and none spawns there). Floor pieces (a camp's ground, the loch) lie under the floor and are never
hidden. With the usual follow camera the hull is the camp plus the corridor the keep-out already keeps clear, so
the raid view loses nothing. **After:** V1 0 of 11 520 camera spots in all four camps; the guard hid scenery at
913 / 1 014 / 35 / 1 054 spots, at most 12 of 42 / 8 of 28 / 6 of 12 / 12 of 24 parts at once; the live copy of
the reviewer's probe: 0 of 900 in every tier.

**The same class at home** (found by extending the probe; not in the review): a far pine stood between a
zoomed-out camera and the player at 1-4 of 72 spots per zoom (60-400) behind the lairs and on the strips
(`check_stealacryptid_view` H1, watched fail: 32 of 3 456 with the root as the only target; the final H1 also
aims at the head and 1.5 studs to each side). The same guard now runs for home pieces, with the hull
of the camera and a box of `Config.Night.HomeViewRadius` (4 studs) round the player's root. **After:** 0 of 3 456
camera spots (root, head and sides tested), at most 3 horizon parts hidden at once, none with the follow camera.
Critters at home are small moving life and are not hidden (a bat can cross the line of sight); in a camp they are,
because there the view is gameplay.

**Two cases the sweep showed the sampled spots could miss, now built on purpose** (§8, V09 and V11/V11b): H4, a far
pine that the line to the player's root misses by 1 stud but the line to their side crosses, is hidden (the view kept
clear is the character's, `HomeViewRadius`, not a line); V4, a camera held low behind the loch for Nessie's whole
130-s lap: an ANIMATED piece is judged where it is every frame (0 frames with anything in the way; she is hidden on
the 234 frames she crosses the view).

### Found during verification: a critter's drawn halo could reach 0.2 studs into a keep-out corner

One full gate run in about 30 (on the tree before this fix) failed `check_stealacryptid_night`: a `WispHalo` 0.2
studs inside the corner of the camera corridor. The cause is in the first night's code: critters were kept out by
a 3-stud CIRCLE round their centre, but a wisp is drawn with a 1.2-stud bob and a 2.4-stud halo whose
world-aligned box, turned 45°, spans 1.7 studs each way: 2.9 studs per axis, which a circle lets into a rect's
corner diagonally. Test first (`Night.spec`: round every keep-out corner, the old circle lets a drawn wisp in at
747 of 12 800 sampled spots, the new rule at 0), then `Night.critterClear`: the same 3 studs, as a box. The flake did not show in
12 runs of the unfixed tree or 16 of the next one, so its rate is below what those runs can show; the geometry
proves the gap.

### Found during verification (2): a telegraph measured on a running sum of frame times

One full run (the 14th of 16) failed the unchanged `check_stealacryptid_hazards`: "H4: every warning ran at least 3.0 s
(shortest 2.97)". Its bound is 3.0 s less one frame (sampling), and 2.97 is exactly 89 frames of 1/30 s: ON the
bound. The check measures a span as the difference of two running sums of 1/30-s steps, and once that clock is large
86 % of 89-frame spans come out 1e-15 short of `3.0 - 1/30` (measured with a scratch Luau script). The game is
fine: the shortest warning before a hit is 3.04 s (a bat: 3.2 s less (2.0 + 1.5) / 22), and `NightConfig.spec` holds
every kind to 3.0. The two comparisons (H1, H4) now allow 1e-6: the bound stays exactly "3.0 s less one frame".
Then `_hazards` 10 of 10 runs and two full runs green.

### New Traps (CLAUDE.md 24-28)

24. **A local floor that continues the real one at walking height is a trap door.** A cosmetic floor must never be
    mistakable for the server's ground: leave a visible drop or a gap nobody can jump.
25. **A launch margin is not a knock margin.** A rule on where a hazard starts says nothing about where the player
    stands when it lands: cut the push itself.
26. **Poppercam ignores non-collidable parts.** Local scenery (CanCollide off, as it must be) can sit between the
    camera and the player for as long as the camera stays there; a keep-out that covers only the default camera is
    not enough. Hide what is in the view hull, every frame, on the frame the camera moves.
27. **Keep a drawn thing out by what it draws, measured the way the check measures it.** A circle round a centre
    does not bound a box turned 45° plus a bob; a flake in 1 run of 30 was a real 0.2-stud intrusion.
28. **A span taken from a running sum of dt is not exact.** Compare it with a bound that sits exactly on a frame
    count only with a tolerance (1e-6), or it fails on float noise.

### Files written in the review-fix session

In `steal-a-cryptid/`: `src/shared/Night.luau`, `src/shared/NightArt.luau`, `src/shared/Config.luau`,
`src/client/Night.client.luau`, `tests/Night.spec.luau`, `tests/NightConfig.spec.luau`, this file, `CLAUDE.md` and
`README.md`. In `robloxemu/`: `check_stealacryptid_edge.luau` and `check_stealacryptid_view.luau` (new),
`check_stealacryptid_lateroad.luau` (its far-floor assertion now checks the frame's hole is centred on the road,
the same intent for the new shape), `check_stealacryptid_longroad.luau` (+ the ravine at 50 players) and
`check_stealacryptid_hazards.luau` (two telegraph comparisons: + 1e-6, above), and
`build/steal-a-cryptid.luau` (rebuilt). `src/server/Main.server.luau`, the HUD, the three original checks
(`check_stealacryptid`, `_guards`, `_hud`) and `tests/walk.luau` are untouched. Nothing in another game, `robloxemu/emu`, `tools`, `docs` or any marketing
folder. Not committed, not pushed, not published; Studio not opened.

---

## 14. Second review 2026-09-30: five findings, reproduced, fixed test-first; the owner's decisions

A second reviewer probed the night (and its review fixes) through the real server and client and reported five
low findings. Each was reproduced first with the reviewer's own probes (`scratchpad/sacrev2_eye_z4q7`, run
unchanged on a copy of this tree in `scratchpad/sacfix30p1`), then a failing test was written and watched fail,
then the game was fixed (never the test), then the probes were re-run. None was rejected: all five reproduced
with the reviewer's numbers.

### Finding 1: a hazard could land after its ring and warning were gone

**Reproduced.** `probe_latehit` (rank 2, a player who stops at 0.99 R on the ring's far side): 24 of 120 knocks
landed after the ring, the chip and the marker had gone (worst 0.033 s); `probe_latehit4` (rank 4): 25 of 114, all
wisps (worst 0.083 s). The pure `probe_late`: 3.3-3.5 % of hits after `arriveAt`; latest meteorite 0.067 s (model
already hidden at all 2 189 of its late hits), crow 0.100, bat 0.117, wisp 0.200 s: the review's numbers exactly.

**Test first.** `tests/Hazards.spec.luau` gets the +1 Jump template's `threatLive` block verbatim (1 failure: the
function did not exist). `Night.spec`: the client's per-frame rule replayed purely (300 plans per kind, 48 players
standing still inside each ring): 3 failures on the old drawing (541 hits with the meteorite hidden, 7 drawn more
than the ring's radius plus a frame away, 4 834 lingering frames off the lane's line). New
`check_stealacryptid_latehit` (the reviewer's set-up as a gate, 60 hazards at rank 2 and 60 at rank 4): 4 failures
(20 of 116 knocks after the ring went, 20 after the chip went, 11 with nothing drawn, 6 rings kept after a knock).

**Fixed.** `src/shared/Hazards.luau` now carries `Hazards.threatLive` exactly as +1 Jump's working tree has it
(the file and its spec are byte-identical to `plus1-jump/src/shared/Hazards.luau` and
`plus1-jump/tests/Hazards.spec.luau` as of 2026-09-30: sha256 `bd470578ce83...` and `cafb80675fa6...`). The client
keeps the ring and the chip (and the marker and blink) up while `threatLive(plan, PlayerRadius, before)` holds and
records `plan.liveUntil`; `Night.drawPosition`'s new `liveUntil` keeps the hazard on its lane's line, level at the
height it arrived, until then, and only then swoops away (or, a meteorite, is gone). The lane line still goes at
arrival. **After:** `probe_latehit` 0 of 120, `probe_latehit4` 0 of 120; `check_stealacryptid_latehit` 12 / 0 (120
of 120 knocked, 20 of them after the arrival, 0 after the ring or the chip, 0 with nothing drawn, the drawn hazard
at most 0.76 studs past the ring's radius); the ring lingers at most 0.63 s past arrival in `Night.spec`'s replay.
(`probe_late` itself replays the OLD rule by hand, so its numbers do not change; `Night.spec` is its fixed twin.)

### Finding 2: Rest pressed during a stumble was silently dropped

**Reproduced.** `probe_restknock`: 5 of 5 presses 0.1 s into a stumble; the button read `Rest` and the chip was
empty for the next 3 s. **Test first:** `check_stealacryptid_rest` 2c (three stumbles): 3 failures (never
`Rest...`, never the queued line, rest never began). **Fixed:** the press is queued like any press with a hazard
about (a stumbling player is not on their feet). **After:** 2c green; the probe: 0 presses unanswered. The sweep's
mutant M11 (a stumbling player counts as on their feet) survived round 1: in 2c the hazard is always still flying
during the stumble, so the queue came from the threat, not from the stumble. 2d closes that gap (a poacher's warning
removes the hazard mid-stumble, so the sky is clear while the player is still down: the press must still queue and
nobody may sit while stumbling); `_rest` 75 / 0.

### Finding 3: the rest campfire hung over the ravine

**Reproduced.** `probe_campfire`: sitting 0.5 and 2.0 studs from the back edge facing out, 4 of 4 campfire parts
stood past the edge at y -0.10 (stones 3.5 and 2.0 studs out); at 4.0 the stones' centre was on the edge.
**Test first:** `Night.spec` for `Night.campfireSpot` (failed: missing), `check_stealacryptid_edge` E4 (14 spots:
0.5 / 2 / 4 studs from all four edges facing out, two corners; it errored: no `Campfire.Distance`; mutant M12,
which restores the old placement, fails it). **Fixed:** `Night.campfireSpot` puts the fire at the first of ahead /
behind / right / left whose whole stone ring (`Config.Night.Campfire.Radius`, which NightArt now builds the ring
from) is on the Ground; in a corner nook, the farthest of those pulled onto the Ground. **After:** the probe 0 of 4
at all three distances; E4 0 parts past the Ground at 14 spots; a 20 000-spot sweep in `Night.spec` 0.

### Finding 4: the band title card overlapped the HUD on phones

**Reproduced.** `probe_cardtext`: Card x RaidChip 252 x 14 px on 800x360; Card x Toast 360 x 21 and x RaidChip
252 x 13 on 640x300. `probe_cardflow` (800x360): MOONRISE over the open Hunt panel on 129 of 150 frames, up to
10 598 px^2. **Test first:** `check_stealacryptid_nighthud` gets a card overlap rule (the card and its subtitle
overlap nothing the HUD draws, with the not-saving banner, the first hint, a 100-character toast and the longest
warning up): 9 overlaps. New `check_stealacryptid_card` (the reviewer's flow): C1 129 of 150, C2 never shown.
**Fixed:** the HUD publishes the card's room on its NightBus (`CardTop`: under the chip's slot, kept even while
the chip is hidden; `CardBottom`: above the touch-control band); the card sits at 46 % where there is room, else
right under the stack, shrinking the title first (never below 22 design px, the subtitle never below 20) or
showing the title alone; a band reached with a panel open waits until it closes, and a panel opened over a card
hides it. **After:** 0 overlaps in 10 viewports, legibility still green (4 PASS lines); the flow 0 of 150 frames,
the card named once the panel closed; `probe_cardtext` "none" in every viewport.

### Finding 5: the budget was only asserted; beams sat at 8 of 8

**Reproduced.** Nothing in `src/` read `MaxLocalParts`, `MaxEmitters`, `MaxEmitterRate`, `MaxBeams`, `MaxTrails`,
`MaxLights` or `MaxHazards` (grep); `check_stealacryptid_budget`: parts 146 of 200, beams 8.0 of 8 at the
strange -> mythic seam. **Test first:** new `check_stealacryptid_budgetcap` lowers the budget in memory (90 parts,
5 beams, 2 trails, 2 lights, 2 emitters, 12 particles/s) and drives the heaviest scene: parts 150, beams 8, trails
4 before (6 failures, with the missing `Budget.Reserve`); `Night.spec` and `NightConfig.spec` for the gate and the
reserve (failed: missing). **Fixed:** section 6 (admission in `setWeight` against Budget - Reserve, the per-frame
emitter cap in priority order, one hazard drawn). **After:** under the lowered budget parts 86 of 90, beams 5 of 5,
trails 2 of 2, emitters 2 of 2, 9.9 of 12 particles/s; the telegraph drawn on all 1 026 warning frames and the
campfire on all 301 resting frames; the seam still 86 parts and 5 beams. The shipped scene is untouched: `_budget`
still peaks at 150 parts and 8 beams and builds 340 unique instances per cycle. The sweep's mutant M27 (a home piece
destroyed when the road arrives late keeps its budget) survived round 1; B6 now checks the gate's books on the
game's own NightArt after a late road (used = the cost of what is shown: 63 parts and 5 beams both ways).
`_budgetcap` itself raced once in 7 runs on the unchanged tree (its rest procedure's dodge steps woke a rest that
had just begun); the check now presses again until rest holds (12 of 12 runs green after), and every round-1
verdict that leaned on it alone was re-run in round 2.

### The owner's decisions (section 11)

(a) keep the 120-180 s interval (pinned in `NightConfig.spec`); (b) keep the eight species and four camp tiers,
the UFOs stay in the Mythic sky; (c) no clock cycle, the Journal's rank drives the sky; (d) no invisible walls, a
server fall rescue instead (`check_stealacryptid_fall`, 13 / 0; 9 failed before it existed). Each is recorded as
DECIDED 2026-09-30 (owner: take recommended) in section 11 with its reason.

### Gates (final tree of this pass)

Every gate, run on the real tree after the last edit (bundle sha256 `9fe7e3553f6a...`): **34 suites, 3 594
assertions passed, 0 failed, plus 6 PASS lines.**

| gate | before this pass | after |
|---|---|---|
| 9 original specs (Rng, Responsive, Economy, Offers, Layout, Heist, Trace2D, Poacher, CryptidModel) | 1 267 / 0 | 1 267 / 0 (unchanged) |
| `tests/EnvBands.spec` / `Rest.spec` (template) | 124 / 0, 55 / 0 | 124 / 0, 55 / 0 |
| `tests/Hazards.spec` (template) | 102 / 0 | **111 / 0** (+ `threatLive`) |
| `tests/Night.spec` | 427 / 0 | **465 / 0** |
| `tests/NightConfig.spec` | 222 / 0 | **232 / 0** |
| **spec total (14 files)** | 2 197 / 0 | **2 254 / 0** |
| `check_stealacryptid` / `_guards` / `tests/walk` | 332 / 184 / 46 | 332 / 184 / 46 (the fall rescue changed nothing they see) |
| `check_stealacryptid_hud` | 2 PASS | 2 PASS |
| `check_stealacryptid_nighthud` | 3 PASS | **4 PASS** (the card overlaps nothing) |
| `_compile`, `_night`, `_hazards`, `_budget`, `_lateroad`, `_keepout`, `_life`, `_longroad`, `_view` | 40, 386, 69, 28, 12, 24, 4, 4, 44 | the same |
| `check_stealacryptid_rest` | 63 / 0 | **75 / 0** (2c, 2d) |
| `check_stealacryptid_edge` | 25 / 0 | **42 / 0** (E4) |
| `check_stealacryptid_latehit` (new) | - | **12 / 0** |
| `check_stealacryptid_card` (new) | - | **13 / 0** |
| `check_stealacryptid_budgetcap` (new) | - | **12 / 0** |
| `check_stealacryptid_fall` (new, owner decision (d)) | - | **13 / 0** |
| **headless total** (counted) | 1 261 / 0 + 5 PASS | **1 340 / 0 + 6 PASS** |

**Stability** (unseeded `Random`): on the final checks `_latehit`, `_card`, `_fall` and `_edge` 5 of 5 runs green
(4 stability runs plus the final gate run), `_rest` 7 of 7 with 2d, `_budgetcap` 13 of 13 after its procedure fix.

### Mutation sweep

Driver `scratchpad/sacfix30p1/sweep/sweep.py` (mutation list `mk.py`, results `results_*.json`, logs
`sweep_round*.log`; scratch, not in the repo), on a scratch copy verified identical to the real tree: for each
mutation every edit is applied exactly once, the bundle is rebuilt and **proved to carry it** (the mutated bundle
equals the baseline bundle with the same replacements, and differs from it), all 34 suites run, the bytes are
restored; after each round the tracked files' sha256 manifest and the bundle (`9830815adf9a`) matched the start.
Each round began from an all-green baseline.

* **Round 1** (31 mutations, 3 controls): 29 killed; **2 survivors, both gaps in the new TESTS**, closed there (never
  by weakening a mutation): M11 (2c could not tell "not on your feet" from "a hazard is about": 2d added) and M27
  (nothing checked the gate's books after a late road: B6 added). One control, CTRL2, went red on `_budgetcap`
  alone: its rest procedure raced (a rest that began during the dodge steps was woken by them), the same
  `budgetcap 9/2` seen beside other kills below. Fixed in the check (press again until rest holds); 12 of 12 runs
  green after.
* **Round 2** (the two survivors, every mutation that `_budgetcap` alone had killed, and all three controls, on the
  final checks): all 6 mutations killed, 3 of 3 controls survived.

**Final: 31 of 31 mutations KILLED, 3 of 3 controls SURVIVED, 34 of 34 edit sets proven to reach the bundle.** Three edits were considered and left out, each equivalent or unreachable
under the shipped config, so a survivor would say nothing: the ring judged from `plan.t` instead of `before`, a
larger stone ring (the fire keeps 4 studs from the player), and a second hazard model left drawn (the scheduler
flies one at a time). The
`budgetcap 9/2` entries of round 1 are that race, and every such mutant is killed by another suite as well.

| # | mutation | round 1 | final | bundle | red suites in the final round (passed/failed) |
|---|---|---|---|---|---|
| M01 | F1 the ring goes at arrival again (client) | KILLED | KILLED | 1d704df5f3f7 | budgetcap 10/1, latehit 11/1 |
| M02 | F1 the chip warning goes at arrival again (client) | KILLED | KILLED | faa4c0a7ff9e | latehit 10/2 |
| M03 | F1 the drawing ignores liveUntil (swoop / meteorite end at arrival) | KILLED | KILLED | 57793f70ef73 | budgetcap 10/1, latehit 11/1 |
| M04 | F1 while the ring lingers the drawing follows the lane down (dives) | KILLED | KILLED | cb134354fb12 | Night 463/2 |
| M05 | F1 a meteorite still vanishes at arrival (drawPosition) | KILLED | KILLED | 7bedbc68efca | budgetcap 10/1, latehit 11/1, Night 463/2 |
| M06 | F1 template threatLive: live only until arrival | KILLED | KILLED | cc4e352057ee | latehit 9/3, Hazards 109/2, Night 462/3 |
| M08 | F1 the lane line stays after arrival | KILLED | KILLED | 5d97871ec413 | latehit 11/1 |
| M09 | F1 after a knock the ring stays until arrival | KILLED | KILLED | 4024bcb09a15 | latehit 11/1 |
| M10 | F2 a rest press mid-stumble dropped again | KILLED | KILLED | c5e17b3b281b | edge 40/1, rest 66/3 |
| M11 | F2 a stumbling player counts as on their feet | SURVIVED | KILLED | 0e2e7840610b | rest 73/2 |
| M12 | F3 the campfire straight ahead again (no Ground) | KILLED | KILLED | 2de1d8342512 | edge 41/1 |
| M13 | F3 campfireSpot ignores the ring radius | KILLED | KILLED | ae59ea0413d7 | budgetcap 9/2, edge 41/1, Night 464/1 |
| M14 | F3 campfireSpot never tries behind or aside | KILLED | KILLED | 518da4064a20 | budgetcap 9/2, edge 41/1, Night 463/2 |
| M16 | F4 the card at a fixed 46 % again (ignores the HUD room) | KILLED | KILLED | 17fee2d0347b | nighthud 3 PASS |
| M17 | F4 the HUD's card room forgets the chip's slot | KILLED | KILLED | f5ba6bbc3b55 | nighthud 2 PASS |
| M18 | F4 the card is not deferred while a panel is open | KILLED | KILLED | 0578badb4d5e | budgetcap 9/2, card 10/3 |
| M19 | F4 opening a panel does not hide the card | KILLED | KILLED | 63a4b87b5dc0 | card 11/2 |
| M20 | F4 a band reached with a panel open is never named | KILLED | KILLED | 3ba654d571da | card 10/3 |
| M21 | F4 the subtitle may shrink below legible | KILLED | KILLED | f9f8b5abad8e | nighthud 3 PASS |
| M22 | F5 no admission (every item drawn) | KILLED | KILLED | 6b2bf0c049f3 | budgetcap 10/5 |
| M23 | F5 the hazard model is gated too (the telegraph can be refused) | KILLED | KILLED | cd4c150af048 | budgetcap 11/1 |
| M24 | F5 the emitter cap never runs | KILLED | KILLED | 79bf85ddbd0a | budgetcap 11/3 |
| M25 | F5 the campfire last in the emitter priority | KILLED | KILLED | b954c74a31a6 | budgetcap 11/1 |
| M26 | F5 the reserve ignored for parts | KILLED | KILLED | ec95c934b538 | budgetcap 8/4, Night 464/1 |
| M27 | F5 setHome does not give destroyed pieces' budget back | SURVIVED | KILLED | edcf9e532cab | budgetcap 11/1 |
| M29 | D the fall rescue never runs | KILLED | KILLED | 1fe0698059d5 | fall 6/7 |
| M30 | D the fall rescue also in a raid | KILLED | KILLED | ff95a511b72a | budgetcap 9/2, fall 12/1 |
| M31 | D the rescue fires at the Ground's top (no depth) | KILLED | KILLED | 766c86c166ae | fall 11/2 |
| M32 | D the rescued player keeps the fall speed | KILLED | KILLED | 53ab57b70fd8 | fall 8/5 |
| M33 | D the rescue is silent | KILLED | KILLED | a4c8754c11b4 | budgetcap 9/2, fall 8/5 |
| M34 | A hazard interval 120-240 s | KILLED | KILLED | 4b25742f382a | budgetcap 9/2, NightConfig 229/3 |
| CTRL1 | CONTROL card text a shade cooler | SURVIVED | SURVIVED | 618df65f607b | - |
| CTRL2 | CONTROL campfire flicker 0.08 -> 0.07 | KILLED (control!) | SURVIVED | f9ca5e75c60b | - |
| CTRL3 | CONTROL tracking ring a shade less green | SURVIVED | SURVIVED | 7284df0a4f0b | - |

### New traps (CLAUDE.md 29-33)

29. **A hit rule that runs past the warning is a hit with no warning.** The hit test ran to the flight's end, the
    ring and the chip stopped at arrival. Keep the warning up exactly as long as the hit can still land
    (`Hazards.threatLive`), and draw the thing where it hits.
30. **A refusal inside a condition is still a silent no-op.** `if ... or knockUntil ~= nil then return end` looked
    like a guard; it swallowed a player's press. Queue it or say why.
31. **A local prop placed "ahead of the player" needs the same ground rule as the player.** The campfire floated
    over the ravine the knock cut (Trap 25) keeps players out of.
32. **An overlap rule that looks at one ScreenGui misses the other.** The night's card lives in its own gui;
    measure it against every drawn HUD element, with the busiest HUD, in every viewport.
33. **A budget asserted only by a check is a promise, not a cap.** Admit costs where things are shown, keep a
    reserve for what must always show (the telegraph), and prove it with a check that lowers the budget.

### Files written in this pass

In `steal-a-cryptid/`: `src/shared/Hazards.luau` (template update), `src/shared/Night.luau`, `NightArt.luau`,
`Config.luau`, `src/client/Night.client.luau`, `src/client/Hud.client.luau`, `src/server/Main.server.luau` (the
fall rescue), `tests/Hazards.spec.luau` (template update), `tests/Night.spec.luau`, `tests/NightConfig.spec.luau`,
this file and `CLAUDE.md`. In `robloxemu/`: `check_stealacryptid_{latehit,card,budgetcap,fall}.luau` (new),
`check_stealacryptid_{rest,edge,nighthud}.luau` (new blocks) and `build/steal-a-cryptid.luau` (rebuilt). Nothing
in another game, `robloxemu/emu`, `tools` or `docs`. Not committed, not pushed, not published; Studio not opened.

### Re-run of this pass (2026-10-01): re-verified from scratch; one test gap closed

The workflow ran pass 1 again ("try again"). The tree was as the 2026-09-30 pass left it: every source, spec and
check byte-identical to that pass's sweep copy, and `Hazards`, `EnvBands`, `Rest` and their specs still
byte-identical to +1 Jump's. Nothing in `src/` changed in this re-run. Every number below was measured again.

* **Reproduced again on the reviewed tree** (git HEAD, byte-identical to the reviewer's copy), with the reviewer's
  probes: F1 `probe_latehit` 24 of 120 knocks after the ring, chip and marker had gone (worst 0.017 s),
  `probe_latehit4` 25 of 114 (all wisps, worst 0.067 s), `probe_late` 3.3-3.5 % of hits after `arriveAt` (latest
  meteorite 0.067 s with the model hidden at all 2 189 such hits, crow 0.100, bat 0.117, wisp 0.200); F2
  `probe_restknock` 5 of 5 presses unanswered; F3 `probe_campfire` 4 of 4 parts past the edge at 0.5 and 2.0
  studs; F4 `probe_cardtext` Card x RaidChip 252 x 14 px (800x360), Card x Toast 360 x 21 and Card x RaidChip
  252 x 13 (640x300), `probe_cardflow` MOONRISE over the open Hunt panel on 129 of 150 frames (up to 10 598
  px^2); F5 nothing in `src/` reads a Budget field, `_budget` parts 148 of 200 and beams 8.0 of 8 at the seam.
* **The tests fail on that tree:** `Hazards.spec` 102 / 1, `Night.spec` stops at its first new block (a missing
  function), `NightConfig.spec` 224 / 1, `_latehit` 8 / 4 (26 knocks after the ring, 26 after the chip, 14 with
  nothing drawn, 12 rings kept after a knock), `_card` 10 / 3, `_budgetcap` 8 / 9, `_fall` 4 / 9, `_rest` 70 / 5,
  `_edge` stops at E4 (no `Campfire.Distance`), `_nighthud` 9 card overlaps.
* **On the fixed tree** the same probes give 0 of 120, 0 of 120, 0 presses unanswered, 0 of 4 parts at 0.5, 2.0
  and 4.0 studs, no overlap in 10 viewports, and 0 of 150 frames. Stability: `_latehit`, `_card`, `_budgetcap`,
  `_fall`, `_edge`, `_rest` and `_nighthud` 35 of 35 runs green (5 each).
* **Sweep, round 1** (driver `scratchpad/sac_try2/sw/sweep`, the same rules as above; 40 entries: the 31 mutations
  and 3 controls in the table above plus five new mutations X1-X5 and a fourth control): 35 of 36 mutations
  killed, 4 of 4 controls survived, 40 of 40 edit sets proven in the bundle, sources restored byte-identical.
  Every mutation in the table was killed by the suites it names, less the `budgetcap 9/2` race, which did not
  recur (M13, M14, M18, M30, M33, M34 were killed by their other suites alone). New: X2 (`threatLive` stays live after a hit: Hazards 110 / 1, latehit
  11 / 1), X3 (no particles/s cap: Night 464 / 1, budgetcap 11 / 2), X4 (`admit` never counts: budgetcap 10 / 5,
  Night timed out), X5 (`threatLive` forgets the ring radius: Hazards 110 / 1), CTRL4 (the fall toast's wording)
  survived.
* **The survivor, X1, was a gap in the TESTS:** with the HUD never publishing `CardBottom` the card ignores the
  touch-control band, and on 640x300 its title went 10 and its subtitle 28 screen px into the band; no gate looked.
  `check_stealacryptid_nighthud` gets a fifth PASS line: the card and its subtitle stay above the touch-control
  band (Responsive's `controlPad`, as the HUD measures it) in every touch viewport, and the subtitle shows on
  every screen 600 px or taller. Writing it exposed a staging error in the check's own card mode: it set the
  subtitle Visible by hand and measured at once, so it measured a subtitle the game never draws (7 px "into the
  band" on 640x300 on the unchanged game). The card mode now re-lays-out the screen with the card up (a
  rotation) so the game decides what of the card it shows, and measures that: the title alone on the three
  phone-landscape touch viewports with the whole top stack up, title and subtitle on the other seven. The
  game was not changed.
* **Sweep, round 2** (the new rule, from an all-green baseline): X1 killed (nighthud 4 PASS), two new mutations X6
  (no room for the subtitle anywhere) and X7 (a re-layout always hides it) killed, the three mutants the card
  mode's change could affect (M16, M17, M21) still killed, 4 of 4 controls survived, sources restored
  byte-identical. **Final: 38 of 38 mutations KILLED, 4 of 4 controls SURVIVED, every edit set proven in the
  bundle.**
* Owner decisions: the four in section 11 were already recorded as DECIDED 2026-09-30 (owner: take recommended);
  a search of this file, CLAUDE.md, REVIEW-1.md, README.md and DESIGN.md found no other open owner decision.
* **Gates on the real tree after the last edit** (bundle sha256 `9fe7e3553f6a...`, unchanged: no source changed):
  34 suites, 3 594 assertions passed (specs 2 254, headless 1 340), 0 failed, plus 7 PASS lines (`_hud` 2,
  `_nighthud` 5). The changed `_nighthud` was green in 7 of 7 runs of its final version.
* Files written in this re-run: `robloxemu/check_stealacryptid_nighthud.luau` (the touch-band rule and the card
  mode's re-layout), this file and `CLAUDE.md`; `robloxemu/build/steal-a-cryptid.luau` rebuilt (byte-identical).
  Not committed, not pushed, not published; Studio not opened.

---

## 15. Pass 2 (2026-10-01): the complete-game standard

`docs/complete-game-standard.md` is the owner's finish line. This pass checked every item of it against the game, took
the reviewer's list of gaps and added one of its own, and built what was missing test-first: each new test was run
and watched fail before the code it guards existed, and every new assertion was mutation-tested with controls
(below). Where a number is quoted it was measured in this pass.

| standard | what was missing | built | test written first, and how it failed before |
|---|---|---|---|
| §3 highscore board | everything (DESIGN.md had cut leaderboards) | the Top Lairs board: `Board.luau` (+1 Jump's template, verbatim, md5 848ed9ca...), the metric `bestRate` / `bestRateAt` (`Economy.noteBest`), a board on every plot's front fence behind the Collect Pad, `Board.client` drawing each player's view on every board | `Board.spec` (66; no module), `Economy.spec` +26 (`noteBest` a nil call), `check_stealacryptid_board` (31 failures: no Config.Board, no boards, no remote, nothing written, no views), guards G10 +2 (a failed grant's best) |
| §2 brag moment in 30-45 min, measured in `tests/` | no Luau model; DESIGN.md's Python put the first Mythic at 107-183 min | `tests/Pacing.spec.luau`; the Mythic payback 14 400 s -> 3 600 s | the brag assertion failed at 81.6 min; `Economy.spec`'s hand-written Mythic price, permit and alert failed (5) on the old Config |
| §2 at least 5 bands, each its own weather and critters | 4 home bands; the Badlands had no weather; the Barrens and the Loch shared bats as their only life | the Gathering (`Night.level`, `State.best`, `GatheringRate` 1 350/s): crimson moon, the legends, moths, embers; camp sand, the Jersey Devil, moths, spores | `Night.spec` +12 (`Night.level` a nil call), `NightConfig.spec` (6 failures: 4 bands, no gathering, no GatheringRate, Badlands no weather, Loch = Barrens' critters, Redwoods = Loch's weather), `_night` (2: pieces it did not know), `_budget` (195 parts > 190, below) |
| §1 RespawnLocation | never set | `plr.RespawnLocation = trailhead` at PlayerAdded | `check_stealacryptid` +2. Written after the one-line fix; its failure without it is mutant M20 |
| §1 an owner token on every write | the token was `game.JobId`, one per server (CLAUDE.md known gap) | a per-session `session` GUID beside `jobId`, checked on every write and release; a same-server rejoin waits for that player's leave-write | guards G25 + G25b: 5 failures before the fix (the rejoin played 3 cages, not the 4 the leave carried; the lock went nil under it; its own change wrote 4 over the old 4; the late write unlocked and overwrote) |
| §4 clip list | no MARKETING.md | 10 vertical clips with staging | - |
| §4 store text, shot list | the copy did not mention the board; the shot list stated no size | 989 characters, ASCII; shots at 1920x1080, a seventh (the Gathering) | measured from the file |

### Found while building it

* **A capped budget hides an overrun** (CLAUDE.md Traps 35). The fifth band's first build peaked at 194-195 parts at the
  mythic -> gathering seam with nine habitats and a hazard flying, and every "within budget" assertion passed, because
  the cap admits scenery only up to the budget minus its Reserve (190) and refuses the rest: a piece would have popped
  in late. `_budget` now asserts the worst case stays at or under 190, which failed at 195; the legends went from three
  a side to two and the moths from 6 to 5: 176-180. The gathering keeps Mythic Night's UFOs, so its set contains
  every rank-4 piece and the seam's union did not grow; `_view` and `_longroad` now run there.
* **The camp keep-out box was 3 studs for every critter.** The Jersey Devil's wings reach 6.1 studs: the box is now each
  kind's `reach` (default 3; the devil 7).
* **Two of the checks' own set-ups were wrong at first** (Traps 37 and 38): G25 asked for a cage the seed could not pay
  for, and the board check cached the emulator's `User_709` for a user it looked up before he joined.

### Gates (final tree)

Run on the live tree after the last edit (bundle sha256 `29235c64b499...`): **37 suites, 4 100 assertions passed, 0
failed, plus 7 PASS lines** (`_hud` 2, `_nighthud` 5). Specs, 16 files, 2 441: Board 66, CryptidModel 552, Economy 219,
EnvBands 124, Hazards 111, Heist 79, Layout 202, Night 477, NightConfig 298, Offers 36, Pacing 17, Poacher 51,
Responsive 70, Rest 55, Rng 32, Trace2D 52. Headless, 1 659: check 334, board 78, budget 46, budgetcap 12, card 13,
compile 44 (22 sources), edge 42, fall 13, guards 200, hazards 69, keepout 28, latehit 12, lateroad 12, life 4,
longroad 4, night 583, rest 75, view 44, walk 46. Stability on the final checks: guards 6 of 6 runs at 200 (after its last change), budget 4 of 4 at 46, keepout 7 of 7 at 28; and on this pass's night and board code, night 8 of 8 at 583, board 6 of 6 at 78, view 3 of 3, longroad 3 of 3.

### Mutation sweep

Driver `scratchpad/sac_p2/sweep.py` (not kept in the repo). Each mutation is an exact-string edit set applied ALONE to a
scratch copy of the game and its checks (never the live tree); the file's sha256 is verified changed; all 37 gates run
(`gates.sh` rebuilds the bundle first); the mutant is PROVEN in the bundle (its sha256 differs from that root's
baseline and it contains the mutation's `--[[Mxx]]` marker); the source is restored and its sha256 verified identical;
and at the end every live source is verified unchanged. A mutation is KILLED when any gate is not fully green (a
count of failures, a missing PASS line or a crash); a CONTROL must survive. Both roots' baselines were green (37 of 37
gates).

Three rounds. **Round 1** (38 mutations, 5 controls): 34 killed, 4 survived (M23, M30, M31, M32), 5 of 5 controls
survived. Each survivor was a gap in the TESTS, closed there (no mutation was weakened): M23, the load not putting its
token on the record, survived the sweep's run and failed a separate run of the same mutant (195/2): G25b looked at the
record only after the late write, a window in which a write of the new session's own can put its token there (G25b
now also reads the record the moment the rejoin's load lands); M30 and M31, CLAUDE.md Traps 39 and 40 (each camp a critter
of its own; `capEmitters` driven with an emitter budget of 0 over every weather kind); M32, Traps 40 (15 devils, the
camera orbiting the camp). **Round 2** (the four, the mutants those tests also kill, the controls): M23, M30, M31 killed;
M22 SURVIVED (killed in round 1): an autosave of the new session rewrote the record 1 s after the late write landed,
1 run in 3 (Traps 41); G25b now judges every commit since the rejoin's load. M32 survived again (15 devils with the
camera at the gate never fly with their wings toward the keep-out: Traps 40), closed with the orbiting camera.
**Round 3**: M21, M22, M23, M32 killed; 5 of 5 controls survived. Repeats outside the sweep with the final tests: M22
killed in 6 of 6 runs (it had survived 2 of 6 before the commit-history assertion), M32 in 3 of 3.
**One unexplained red:** in round 1, M21's run also failed `check_stealacryptid_hazards` (68 / 1). M21 (the rejoin wait)
cannot reach that check, its log was overwritten by the next rounds, and 60 reruns on the final tree were green
(`_hazards` passed 134 of the 135 runs of this pass). It is recorded as a possible rare flake, not explained.

**Final: 38 of 38 mutations KILLED, 5 of 5 controls SURVIVED in every round, every edit set proven in the bundle,
every live source unchanged by the sweep (sha256).**

| # | mutation | final result | bundle | red gates (the killing run) | rounds |
|---|---|---|---|---|---|
| M01 | the Mythic payback back to DESIGN.md's 14 400 s | KILLED | f5e11de1b1cf | Economy 214/5, Pacing 16/1, chk_night 591/39, chk_budget 39/5 | |
| M02 | noteBest re-stamps an equal income (>= for >) | KILLED | 34a423352e6e | Economy 216/3, chk_board 74/4 | |
| M03 | normalize: a best with no stamp is not stamped at the load | KILLED | ee8b12401fb1 | Economy 218/1 | |
| M04 | normalize: a saved best is not capped at nine Bigfoots | KILLED | 4478383aef2c | Economy 218/1 | |
| M05 | normalize: the loaded lair's income is not noted (legacy profiles best 0) | KILLED | bf745dea0174 | Economy 215/4, chk_board 74/4, chk_guards 195/2 | |
| M06 | a purchase does not note the best | KILLED | 24510e2589fb | chk_board 70/8, chk_night 591/39, chk_budget 41/3 | |
| M07 | a failed grant keeps the best it raised | KILLED | f6c19a632d2a | chk_guards 195/2 | |
| M08 | a committed profile write never writes the board | KILLED | 248e6b2a01a8 | chk_board 64/14, chk_guards 196/1 | |
| M09 | writeBoard writes even when the best has not risen | KILLED | 5b6db1146eb7 | chk_board 74/4 | |
| M10 | writeBoard overwrites instead of keeping the higher value | KILLED | e2c89fef6896 | chk_board 76/2 | |
| M11 | a session without its save's lock writes the board | KILLED | a1d1a03a571f | chk_board 77/1 | |
| M12 | the public top 10 is read every second | KILLED | 923f40c665b5 | chk_board 75/3 | |
| M13 | friends capped at 1 000 instead of 200 | KILLED | 8f12af6dd907 | chk_board 74/4 | |
| M14 | the friends list is never taken from the cache | KILLED | 7fe9155675af | chk_board 77/1 | |
| M15 | a friend in this server is read from the store, not memory | KILLED | 439a04b936da | chk_board 77/1 | |
| M16 | a failed friends call reads as no friends | KILLED | ac74cf56e50b | chk_board 77/1 | |
| M17 | the prompt never toggles back to public | KILLED | 583b7c7ea936 | chk_board 76/2 | |
| M18 | the board prompt reaches 10 studs further | KILLED | 316193eac22b | chk_board 75/1 | |
| M19 | the board stands out on the apron (z 12, not flush on the fence) | KILLED | f05dc1b95c31 | chk_board 76/2 | |
| M20 | no RespawnLocation | KILLED | d13bdd541c86 | chk 332/2 | |
| M21 | a rejoin does not wait for its own leave-write on this server | KILLED | 35d747c01837 | chk_guards 198/2 | round 1: KILLED (chk_guards 195/2, chk_hazards 68/1); round 2: KILLED (chk_guards 196/2); round 3: KILLED (chk_guards 198/2) |
| M22 | a write ignores another session's token on this server | KILLED | efbe5fccf356 | chk_guards 197/3 | round 1: KILLED (chk_guards 195/2); round 2: SURVIVED; round 3: KILLED (chk_guards 197/3) |
| M23 | the load does not put its token on the record | KILLED | 300ffd64dd97 | chk_guards 196/4 | round 1: SURVIVED; round 2: KILLED (chk_guards 197/1); round 3: KILLED (chk_guards 196/4) |
| M24 | GatheringRate 900 (a lair without a Mythic could reach it) | KILLED | 54f5cfef0ff2 | NightConfig 293/1, chk_night 566/1, chk_budget 43/1 | |
| M25 | Night.level ignores the rank (a big best alone is the gathering) | KILLED | c6c160186ee3 | Night 476/1 | |
| M26 | Night.level needs a best ABOVE GatheringRate (> for >=) | KILLED | dabf81412786 | Night 475/2, chk_longroad 3/1 | |
| M27 | the client blends the home sky on the rank, not the level | KILLED | bfe6cdbb6f40 | chk_longroad 3/1, chk_night 546/37, chk_budget 42/2 | |
| M28 | the server's State carries no best | KILLED | 00e234539ef6 | chk_longroad 3/1, chk_night 591/39, chk_budget 41/3 | |
| M29 | the Badlands camp has no weather | KILLED | 1a384a812e8f | NightConfig 293/1 | round 1: KILLED (NightConfig 289/1); round 2: KILLED (NightConfig 293/1) |
| M30 | the Loch Shore's critters are bats again (the Barrens' set) | KILLED | 36f3cb9263a5 | NightConfig 297/1 | round 1: SURVIVED; round 2: KILLED (NightConfig 297/1) |
| M31 | capEmitters leaves the Badlands sand out of its list | KILLED | ff0f9fb39570 | chk_budget 45/1 | round 1: SURVIVED; round 2: KILLED (chk_budget 45/1) |
| M32 | the camp keep-out tests the Jersey Devil by the 3-stud box | KILLED | fdf69fc6aee7 | chk_keepout 27/1 | round 1: SURVIVED; round 2: SURVIVED; round 3: KILLED (chk_keepout 27/1) |
| M33 | the legends stand in the ravine (14 studs short of its far rim) | KILLED | 463cedc1e5e2 | chk_longroad 2/2 | |
| M34 | the gathering drops the UFOs | KILLED | 7c4fd2936ff5 | chk_longroad 3/1 | |
| M35 | Board.client draws on the first board only | KILLED | 76368a77ad70 | chk_board 69/9 | |
| M36 | Board.client draws views sent to other players | KILLED | 927c9fb2fa3e | chk_board 77/1 | |
| M37 | Board.keepHigher replaces an equal metric (a later reach wins the tie) | KILLED | bb1ef950a0e7 | Board 64/2 | |
| M38 | three legends a side (195 parts at the seam) | KILLED | eeb17fe24c94 | chk_budget 43/1 | |
| C1 | CONTROL board hint text 14 -> 15 px | SURVIVED, correctly | bb03bf90445e | - | round 1: SURVIVED; round 2: SURVIVED; round 3: SURVIVED |
| C2 | CONTROL board hint wording | SURVIVED, correctly | 4760e12baef2 | - | round 1: SURVIVED; round 2: SURVIVED; round 3: SURVIVED |
| C3 | CONTROL legend silhouette colour 18,14,18 -> 20,16,20 | SURVIVED, correctly | 58ee653f9d80 | - | round 1: SURVIVED; round 2: SURVIVED; round 3: SURVIVED |
| C4 | CONTROL board trim colour | SURVIVED, correctly | acebb114d604 | - | round 1: SURVIVED; round 2: SURVIVED; round 3: SURVIVED |
| C5 | CONTROL the gathering's fog colour 92,38,54 -> 90,40,56 | SURVIVED, correctly | f0d4e84d3d1f | - | round 1: SURVIVED; round 2: SURVIVED; round 3: SURVIVED |

### Files written in this pass

`src/shared/Board.luau` (new, verbatim), `src/client/Board.client.luau` (new), `src/server/Main.server.luau` (the board,
`State.best`, `RespawnLocation`, the session token and the rejoin wait), `src/shared/Economy.luau` (`bestRate`,
`noteBest`, `maxLairRate`), `src/shared/Config.luau` (the Mythic payback, `Config.Board`, `Save.Board`, the fifth band,
`GatheringRate`, the camps' weather and critters, `moth`, `devil`), `src/shared/Night.luau` (`Night.level`),
`src/shared/NightArt.luau` (`bloodMoon`, `gathering`, `moth`, `devil`, `embers`, `sand`, `spores`, the per-kind reach,
`WEATHER_KINDS`), `src/client/Night.client.luau` (the level, the reach, the moon fades like a sky piece);
`tests/Board.spec.luau` and `tests/Pacing.spec.luau` (new), `tests/Economy.spec.luau`, `tests/Night.spec.luau`,
`tests/NightConfig.spec.luau`; `robloxemu/check_stealacryptid_board.luau` (new), `check_stealacryptid.luau`,
`_guards.luau`, `_night.luau`, `_budget.luau`, `_view.luau`, `_longroad.luau`; `robloxemu/build/steal-a-cryptid.luau`
rebuilt; `MARKETING.md` (new), `README.md`, `CLAUDE.md` and this file. Not committed, not pushed, not published; Studio
not opened. **Nobody has reviewed this pass.**
