# Steal a Cryptid — the night over Pine Hollow

Owner's brief (Gustav, 2026-09-17): every game richer and never monotonous — eye candy, and an environment
that changes as the player progresses, following the logic of the game; hazards that knock you down, but
RARE (about one near-hit per 2-3 minutes) and easy to see coming; a way to rest that can never become an
exploit; environments worth photographing, and a thumbnail shot list for the night Studio session.
+1 Jump was built first; its `EnvBands`, `Hazards` and `Rest` modules are the template, copied here verbatim.

**State (2026-09-24): built, unit-tested, headless-tested through the real server and the real client
scripts, reviewed once, mutation-tested (the resume session's 49 edits re-run plus 28 new ones: 70 of 70
mutations killed, 6 of 6 controls survived, one equivalent mutant set aside, every edit proven to reach the bundle). NEVER OPENED IN ROBLOX STUDIO. Not committed, not pushed,
not published.**

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

`check_stealacryptid.luau`, `check_stealacryptid_guards.luau`, `check_stealacryptid_hud.luau` and `tests/walk.luau`
are **unchanged** and green: the game they guard is the same game.

---

## 2. The bands and what triggers them

**Trigger: the Journal's rank, never time.** `rank` = the highest tier the player has ever owned (0-4), the
value the pedestals and the camp unlocks already follow; the server reports it in the player's own State.
The rarer your collection, the deeper the night over Pine Hollow. Inside a raid the night is the **camp's**
place, named by the camp's tier. Where you are comes from your own root's position (a pocket is at
x ≥ 3 936), so a State that arrives before the teleport cannot show the wrong place.

**Why "the night deepens" instead of a day/night clock:** the brief says environment changes are driven by
progress, not time, and the game is a night game by design (DESIGN.md §13: moonlit, readable nets). The
four home bands step the sky from sundown to 3 am as the Journal fills. `ClockTime` is written in *night
hours* (18 = 6 pm … 27 = 3 am; the client writes h mod 24) inside 17.5-30, so a glide between any two bands
never passes through daylight (asserted over every blend of every pair, and on every frame of the headless
runs).

**The readability floor.** No band, and no frame the client writes, may be darker, foggier, less saturated
or harder to bloom than the game as it shipped (`Config.Lighting`), and no band may carry depth of field: a
raider must read a whole camp from its gate, tier colours must survive, neon nets must bloom. `Night.readable`
checks every band, every 5-step blend of every pair (8 bands + the v1 take-over, 405 blends), and every frame
of `check_stealacryptid_night` (join, 4 bands, 4 camps, every seam).

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

A title card names the band quietly when the player's State first arrives, and again each time a new band is
reached (`MOONRISE / A Rare cryptid stirs the woods`) — never over a camp, where it would cover the nets.

### Camps: each tier its own place

| camp tier | place | clock | scenery (all outside the fences) | life | weather |
|---|---|---|---|---|---|
| 1 Common | **Badlands Camp** | 21:36 | red sand, 9 mesas on the horizon, cacti | tumbleweeds rolling past, bats | — |
| 2 Rare | **Pine Barrens Camp** | 23:00 | pine-needle floor, a ring of 14 pines | bats | fireflies behind the back fence |
| 3 Legendary | **Loch Shore Camp** | 00:48 | pebble shore; a loch 1 400 × 800 behind the cages with a moon glint; a castle tower with one lit window; **Nessie gliding across the water** | bats | mist behind the back fence |
| 4 Mythic | **Redwood Camp** | 03:12 | fern floor, 12 redwoods 190 studs tall, **a Bigfoot glimpsed between them** | wisps | mist behind the back fence |

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

### How long to each band (not measured in Luau)

There is no Luau pacing model for this game yet (CLAUDE.md Next 3). DESIGN.md §4's Python model (greedy
buyer, raids at 2-3× optimal time) puts a first Rare (Moonrise) at 3.1-6.0 min for a raider (8-10 idle-only),
a first Legendary (Strange Lights) at 14.2-17.6 min (61-70 idle-only) and a first Mythic (Mythic Night) at
107-183 min (315-326 idle-only). So Strange Lights is the "I got the aurora" milestone of a first session and
Mythic Night the long-term goal. The one Luau measurement: the headless walk (a competent scripted player
that also builds traps and sits out a poacher) reaches rank 2 at 490.9 s. **Treat the Python figures as a
model, not the game** (CLAUDE.md says the same).

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
  left`, then `Move! Leave the red ring - bat`. The arrival time never moves. Marker and light go off at arrival
  (or the hit): nothing blinks `!` once the danger has passed.
* **The red ring is the danger zone** (template round-2 rule): a hit needs you inside it. Stepping out in any
  direction dodges. `NightConfig.spec`: leaving the ring from where you stand at walk speed after 0.5 s to react
  fits inside every kind's lock (tightest: a crow, 0.71 s of its 1.5 s).
* **Drawn, not just computed** (new here): until arrival the hazard is exactly on its lane; after arrival a
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

| where (8 s there) | parts | emitters (rate) | beams | trails |
|---|---|---|---|---|
| dusk | 61 (53 before the ravine) | 2 (9.0/s) | 0 | 0 |
| moonrise | 89 (81) | 2 (6.8/s) | 0 | 0 |
| strange lights | 103 (95) | 2 (9.9/s) | 3 | 0 |
| mythic night | 110 (102) | 2 (9.9/s) | 5 | 3 |
| Badlands camp | 52 | 0 | 0 | 0 |
| Pine Barrens camp | 42 | 1 (2.8/s) | 0 | 0 |
| Loch Shore camp | 22 | 1 (2.8/s) | 0 | 0 |
| Redwood camp | 32 | 1 (3.9/s) | 0 | 0 |

| metric | measured peak | where | budget |
|---|---|---|---|
| local parts | **150** (140 before the ravine: its 9 parts, four far-floor slabs, the bluff and four rim walls, replace the one old floor) | strange → mythic seam, hazard flying, eight habitats | 200 |
| particle emitters | 3 | seams (two weathers + the lit habitat) | 4 |
| particles per second | 17.9 | resting by the campfire | 40 |
| beams | **8** | strange → mythic seam (5 aurora + 3 UFO) | 8 — **at the limit, no headroom** |
| trails | 4 | mythic, hazard flying | 6 |
| point lights | 1 | a hazard's blink, or the campfire (never both: no hazard launches while resting) | 3 |
| hazards at once | 1 | | 1 |

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

---

## 10. Thumbnail shot list (for the night Studio session)

**This recipe has not been tried in Studio. Check step 1 before relying on the rest.**

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

---

## 11. Not done / open

* **One adversarial review** (§13), three findings, all closed. Nobody has reviewed the fixes: a next reviewer
  should look at the ravine (`farGroundRects`, the bluff, the walls), `limitKnock`, the view guard in camps and at
  home (`campViewHull`, `NightArt:occlude`, the camp critters' hull), and `critterClear`.
* **Owner decisions, surfaced, not taken:**
  (a) **Knock rate for a player who ignores warnings**: one per 2.9-6.7 min of home time (§3, R3). The brief
  says hazards are rare; a knock costs nothing. The knob is `Config.Night.Hazards.IntervalMin/Max` (120/180).
  (b) **The theme direction's yeti (snowy peaks) and aliens (UFO field)**: this game has eight species and no
  yeti or aliens, so there is no snowy habitat or camp; the UFOs appear in the Mythic Night sky instead. A snowy
  camp tier or a Yeti species is a design change (DESIGN.md §16).
  (c) **A clock-driven day/night cycle** was not built: the brief says progress drives the environment, and the
  game is a night game. A slow cosmetic drift inside each band is possible later.
  (d) **A server-side world boundary.** As in v1, a player who walks off the Ground falls into the void and
  respawns (nothing is lost); the night now shows the edge as a ravine instead of hiding it (§13). Invisible
  walls would stop the fall but change v1's geometry and may hide cage prompts from a camera behind them
  (Studio item 21). Not built.
* **luau-analyze was not run** (§7); only compile-by-loadstring.
* **No Luau pacing model** for time-to-band (§2); the Python model's figures are quoted as a model.
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
