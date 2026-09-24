# Fork Tower — the tower that changes as you climb

Owner's brief (Gustav, 2026-09-17): every game must feel visually richer and never monotonous, with eye
candy and environment changes as the player progresses, following the logic of the game; rare,
telegraphed hazards (about one near-hit per 2-3 minutes, easy to see coming and avoid); a way to rest that
can never become an exploit; a thumbnail shot list for the night Studio session.

Fork Tower's own constraint, on top of the brief: **each floor is a fork of two doors, and the inscription
the player pays 1.1 s to read is the only information about which door is the trap** (REVIEW-2/3). Since
REVIEW-4 the trap side comes from a server-only per-floor secret. So everything in this file is built to
be identical for both doors of a fork, to reveal nothing, and to leave the read's price where
`tests/readcost.measure.luau` put it.

**State (2026-09-24, after the adversarial review): built, unit-tested, headless-tested, mutation-tested
(50 + 17 mutations, 4 + 4 controls; §9, §14), independently reviewed once, all three review findings
closed (§14). NOT seen in Studio, and the fixes themselves have not been re-reviewed.** Nothing was
committed, pushed or published.

The review found three things, all reproduced first and each now held by a test that went red first
(§14):
* **medium: on a landscape phone the band chip and the ☕ button sat over the player's own character**,
  head to waist, and over the spot a hazard strikes. The row now goes up into the header wherever the
  centred stack would reach the character (every landscape phone); a new check projects the character
  through Roblox's default camera and holds every always-on panel off it;
* **low: a read begun on the exit platform's edge could be knocked mid-hold.** The next fork's prompt
  reaches the exit, off the pad. Clearing the floor now ends any hazard in flight, in the first frame the
  next fork exists;
* **low: the band title card covered the character's legs on a landscape phone, ran off a 640x300 screen,
  and sat on an open drawer in portrait** (and, found by the new check, covered the character's head on a
  1366x768 laptop). It now gets the strip between the HUD and the character where that strip can hold it,
  or sits on the chip for its few seconds, and a hazard warning ends it.

`Fork.luau`, `Main.server.luau`, `floorSecrets`/`mintSecret`, `loadProfile`'s trust rules, the session
token and `saveProfile` are byte-identical to before this work (both files last written 2026-09-17, by
the plan-secret pass; md5 checked at the start and the end of the resume session and of the review-fix
session), and `robloxemu/check_forktower_plansecret.luau` is green (96 / 0) and byte-identical.

The first build session was cut off by a usage limit in the middle of its mutation sweep, with this file
still holding two placeholders. The resume session (§13) re-read everything and re-ran every gate. It
found:
* two of the new checks were flaky, three flakes in all (on the unchanged tree `env_secret` failed 1 run
  in 12 and `env` 1 in 16);
* four promises no test held: a Config name typo silently deleting scenery, the join card's wait for the
  profile, TowerArt's hide-then-show rule, and its weather cap;
* **one real regression on the phone most players hold**: in landscape, the HUD's ambience row left the
  menu drawer (with the Rebirth button), the leaderboard drawer and the summit's Build Reveal card 1 px
  tall. They had been cramped there before the row too (35 px);
* four errors in the shot list.

All of it is fixed and held by a test that went red first, and the whole sweep was run again on the final
tree.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from `plus1-jump` (md5 identical): progress → band + eased blend, glide, tiling, ambient spawn ring, `capRates`. Pure. |
| `src/shared/Hazards.luau` | **template, verbatim**: rare, telegraphed, one-at-a-time scheduler; lanes start on screen; the red ring is the hit rule; capped knock. Pure. |
| `src/shared/Rest.luau` | **template, verbatim**: manual + idle rest, queued under a threat, wake on move, freezes (never resets) the hazard clock. Pure. |
| `src/shared/Climb.luau` | **new, Fork Tower's own**: the progress value (floors climbed), the named floor, the fork-pad sanctuary, the hazard gate, and the clock's short arc. Pure. Since the review: the gate also dismisses a hazard in flight once the floor is cleared, and hits only while climbing (§14 finding 2). |
| `src/shared/TowerArt.luau` | new: the scenery walls, far set pieces, critters, hazard models, weather, lightning. Code-only, pooled, client-only. |
| `src/client/Ambience.client.luau` | new: the glue. Lane → progress → bands → Lighting/scenery/life/weather; hazards behind the sanctuary; rest; the band chip, ☕ button and title cards. Since the review: anything new in the player's lane is scanned the next frame (not at the 4 Hz tick), the title card fills the HUD's card slot on a plate, and a hazard warning ends it (§14). |
| `src/client/Hud.client.luau` | reserves the **ambience row** under the toast (a chip slot and a thumb-sized rest slot) and moves the side panels down by it. Since the resume session also: on a phone a drawer only clears the centred stack where it shares columns with it, ends above the touch controls, and on a landscape phone the Build Reveal card takes the free column right of the stack (§13 item 7: all three were 1 px tall there). Since the review: nothing that stays up may reach the player's character (`PLAY_TOP`), so on a landscape phone the row goes up into the header (the counter beside the menu toggle where the chip needs the width), and it places the title card's slot (§14). |
| `src/shared/Config.luau` | + `Env` (6 bands, critters, sanctuary, walls), `Hazards` (8 kinds), `Rest`, `Budget`, `Pacing` (the human profiles). Nothing existing changed. |
| `tests/` | new specs `Climb`, `EnvConfig`, `Pacing` (+ `PlayModel.luau`, the test-side model); the template's `EnvBands`, `Hazards`, `Rest` specs copied verbatim. |
| `robloxemu/check_forktower_env.luau` | new: the glue through the real server + HUD + Ambience client (bands, glides, budgets, hazards, knock + server rescue, rest, what the client touches), and every name Config.Env gives TowerArt is one it can build. Since the review: the exit-edge read, a pad dismissal while still climbing, the floor clear seen within a frame at all ten floors, and a warning ending a title card (§14). |
| `robloxemu/check_forktower_env_secret.luau` | new: the environment reveals nothing (static audit, door clearance and mirror symmetry at every unread fork, a read changes nothing it draws, no secret in anything it made). |
| `robloxemu/check_forktower_env_join.luau` | new (resume session): the first title card at a join waits for the profile, including 16 s and 40 s loads of a returning floor-7 climber. |
| `robloxemu/check_forktower_hud.luau` | new: `hudcheck` over ten viewports with the HUD **and** the ambience row, overlap on. |
| `robloxemu/check_forktower_hud_open.luau` | new (resume session): the panels hudcheck never measures, OPEN, at the same ten viewports: both phone drawers and the Build Reveal card (tall enough to use, above the touch controls, covering nothing else; the card never over the inscription, the counter, a toggle or a visible ambience row). |
| `robloxemu/check_forktower_hud_play.luau` | new (review fix): the HUD against the player's own character, projected through Roblox's default camera at 13 viewports and three pitches: the always-on HUD and the band title card keep off the character and the hazard ring at its feet; the card stays on screen, off the inscription, the counter, the toast's slot, the toggles, the ☕ button and every open drawer; the chip stays readable (§14). |
| `robloxemu/build/fork-tower.luau` | rebuilt. |

`src/server/Main.server.luau` did not change. The server builds none of this, knows none of it exists, and
the client never tells it anything.

---

## 2. The bands and what triggers them

**Trigger: the player's floor, never time.** Every frame the client reads its OWN lane (the lane folder
whose `Owner` is the local player) and computes two numbers (`Climb.luau`):

* the **named floor**: the highest fork the server has built for this player (= the server's floor, the
  number the HUD shows as `ETASJE n/10`), or one past the top at the summit. It names the band: the chip,
  the title card, which hazards fly;
* the **progress**: `(floor - 1) + the fraction of the chosen section's height the player has climbed`,
  clamped to `[0, 1]`. It drives every blend.

At a fork the section does not exist yet (the door is not chosen), so **the progress is exactly
`floor - 1`, whatever else is true**: the world in front of two unread doors is a function of the floor
number and nothing else. A trapped section is longer and so moves the blend more slowly, but only after the
choice. A fall never takes the world back (the fraction clamps at 0), and nothing runs ahead of the next
fork (it clamps at 1). At every fork the named floor and the progress agree (`Climb.spec`).

Minutes = minutes into a run at which the band is first stood in, measured by `tests/Pacing.spec.luau`
(`PlayModel`, 80 runs per profile; profiles in `Config.Pacing`, §3). A run is ten floors plus the summit.

| # | band | floors | from / fade (floors) | fast | normal | slow | sky & light | scenery walls (both sides, mirrored) | far set pieces | life | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 🕯️ **Fangehullet** (the dungeon) | 1-2 | 0 / — | 0.00 | 0.00 | 0.00 | night 0.5, dense dark atmosphere (0.56), warm tint, strong bloom | stone pillars, torch flames (60 % of cells) | — | bats | embers 6/s | **none** (a new player's first floors) |
| 2 | 🌿 **Den gjengrodde hagen** (the overgrown garden) | 3-4 | 2 / 0.8 | 0.39 | 0.64 | 1.17 | morning 8.6, green-gold haze, sun rays | giant leaves, hanging vines, mossy ruin blocks, glowing blooms | three giant flowers on the horizon | butterflies, fireflies | pollen 8/s | bumblebee, seed pod |
| 3 | ⚙️ **Urverket** (the clockwork) | 5-6 | 4 / 0.8 | 0.84 | 1.41 | 2.61 | afternoon 16.4, brass-amber, glare | turning brass gears (disc + teeth bar), copper pipes | a great clock face ahead of the climb, hands turning | clockwork moths | sparks 10/s | flung cog, clockwork bird |
| 4 | ⛈️ **Stormen** (the storm) | 7-8 | 6 / 0.8 | 1.36 | 2.30 | 4.19 | dusk 18.7, blue-grey, high contrast, **lightning** (every 6-12 s, flash) | dark storm-cloud masses | a storm deck of cloud below | blown leaves | rain 40/s | ball lightning, roof tile |
| 5 | 🔭 **Observatoriet** (the observatory) | 9-10 | 8 / 0.8 | 1.93 | 3.27 | 6.04 | night 23.6, 4 000 stars, **big moon** (angular size 26), clear air | floating star lanterns, brass orrery balls | a ringed planet, a blue planet, a constellation | shooting stars | stardust 8/s | meteor, comet |
| 6 | 👑 **Stjernekronen** (the star crown) | summit | 10 / 0.6 | 2.58 | 4.37 | 8.12 | 23.95, 5 000 stars, the strongest bloom, golden tint | — | a spiral galaxy far below; **a crown of ten gold stars circling the climber** | shooting stars | stardust 10/s | **none** (the summit is a sanctuary) |

A normal ten-floor run takes 4.54 min, fast 2.66, slow 8.37. The environment changes every 38-66 s for a
normal climber, never less than 20 s for a fast one and never more than 150 s for a slow one (asserted), so
a run is never one place. Every run walks through all six; a rebirth starts the dungeon again and the
title cards with it.

**Transitions never cut** (all measured through the real client, `check_forktower_env`):

* a band fades in over the last 0.8 floor (0.6 for the summit) of the section below its first fork, eased;
* every written value glides with a 0.6 s half-life, so a jump in progress (a rebirth from the summit to
  the dungeon, a join) glides too;
* **the sun only moves forward up the tower**: each band's `ClockTime` is later than the one below
  (`EnvConfig.spec`). The first headless run found the storm (18.7) blending to an observatory set at 0.2
  through 13.87, midday, half-way up floor 8; the observatory is now 23.6 and the crown 23.95;
* **across a jump the clock takes the short way round** (`Climb.nearestClock`): a rebirth from the
  summit's night to the dungeon's night passes through midnight, a join from the server's dusk preset
  (17.6) goes forward through the evening. Measured: **0 daytime frames** in both glides, no frame moves
  the clock more than 0.12 h, and the first client frame moves it at most 0.6 h from the server's value;
* **no scenery part changes transparency by more than 0.1 in a 1/30 s frame, and every part enters the
  scene invisible** (every frame of a whole run, the summit and a rebirth; and again over the second and
  third runs, where every band and piece is shown a second time, with hazards, a knock and its fall, and
  rest, except that there a frame in which the camera teleports is exempt from the 0.1 rule: §13 item 6). This found two real pops, both
  fixed: the wall grid re-placed every slot at each cell crossing (188 parts popped in); and the template's
  `setWeight` (in +1 Jump's `SkyArt`) forgets a hidden part's transparency, so a part shown again at a small
  weight came back at its old opacity (26 pops). The walls now keep each cell's slot while the cell is in
  view, fade each slot by its distance to the grid's edge, and glide; `TowerArt`'s hide writes
  `Transparency = 1`.

The band chip under the HUD's toast (up in the header on a landscape phone, §14) says where you are and
what is next (`🌿 Den gjengrodde hagen · ⚙️ om 2 etasjer`, counted in floors). A title card
(`⚙️ URVERKET` / `etasje 5`, gold on a dark plate) plays for ~3.8 s when a new band is first stood in; it
waits behind the Build Reveal card rather than covering it. It sits where the HUD has room for it without
covering the player's character: the strip under the ambience row on a desktop monitor, a portrait phone
and a small window, or ON the chip on a landscape phone, a 1366x768 laptop, a tablet and a 1280x720
window (§14). A hazard warning ends it, since on the chip it would hide the warning. A soft lantern (range 36, shadowless) lights the climber in the dark bands
(dungeon, storm, night) and is off in daylight.

**At a join** the client cannot know the floor until the server has loaded the profile and built the lane,
so the first card waits for both (leaderstats and the player's own lane), then 1.5 s, and says quietly
where the player is (`⛈️ STORMEN` / `etasje 7`). There is no timeout: a card shown before the load would
name the dungeon to a player saved on floor 7 and then the storm when the load lands (+1 Jump shipped that
shape past a 15 s timeout). Measured with real saves (`check_forktower_env_join`): a returning floor-7
climber gets exactly one card, `STORMEN`, 1.5 s after a 0.1 s, 16 s or 40 s load; a new player gets one
`FANGEHULLET` card after a 16 s load. Until the load lands the sky shows the dungeon, and it glides to the
player's band once the lane appears (Studio list).

---

## 3. Hazards and their measured rarity

| kind | band | speed | warning | lane locks | ring (danger zone) | knock |
|---|---|---|---|---|---|---|
| 🐝 bee (`HUMLE`) | garden | 20 | 3.4 s | 1.8 s before | 6.2 studs across | 30 |
| seed pod (`FRØKAPSEL`, falls from above) | garden | 24 | 3.2 s | 1.7 s | 6.6 | 34 |
| flung cog (`TANNHJUL`, rolling) | clockwork | 42 | 3.0 s | 1.5 s | 6.8 | 44 |
| clockwork bird (`URVERKSFUGL`) | clockwork | 30 | 3.2 s | 1.6 s | 6.4 | 36 |
| ball lightning (`KULELYN`) | storm | 24 | 3.4 s | 1.8 s | 6.6 | 40 |
| roof tile (`TAKSTEIN`, tumbling) | storm | 48 | 3.0 s | 1.5 s | 6.8 | 46 |
| meteor (from above) | observatory | 46 | 3.0 s | 1.5 s | 6.8 | 44 |
| comet | observatory | 60 | 3.0 s | 1.5 s | 6.8 | 48 |

**Rules** (the template's `Hazards.luau` plus Fork Tower's `Climb.gate`):

* **one hazard every 70-110 s of CLIMBING**, never two at once. The clock runs **only while the player is
  climbing a section** (their floor's door is chosen) **and stands off every pad**, and not while resting.
  Time spent at a fork (walking on, reading, deciding) and at the summit never brings a hazard closer;
* **the fork pads, the lobby and the summit are a sanctuary**: nothing launches there, nothing hits there,
  and a hazard still in flight when the player reaches the next fork pad is dismissed at once;
* **clearing a floor ends the climb and what it launched** (review, §14): the moment the player lands on
  the exit, the server builds the next fork, and that fork's LES prompt reaches 16 studs, over the front
  3.5 studs of the exit platform, off the pad. So a hazard still in flight is dismissed in the first frame
  the next fork exists, wherever the player stands, and nothing hits a player who is not climbing;
* none in the dungeon (floors 1-2) or the summit; a due hazard in a quiet band is re-rolled, never saved up;
* it launches only while the player stands on something, and **starts on screen** (the template's view
  window: ±35° of the camera's heading, ±20° of its pitch; `EnvConfig.spec` launches every band's kinds at
  camera pitches -60..60 on 16:9 and 4:3: 3 360 launches, 3 360 on screen from launch until the lane locks);
* **telegraph**: an always-on-top ⚠️ over the hazard, a blinking red light, a lane line through the player
  (yellow while it tracks them, red once it locks), the red ring at their feet, and the band chip turning
  red: `⚠️ TANNHJUL KOMMER ◀`, then `⚠️ FLYTT DEG! TANNHJUL ◀`. The arrival time never moves;
* **the red ring is the rule**: a hit needs the player inside it (the template's round-2 fix). The ring is
  at most 6.8 studs across on a 9-stud tile, so from a tile's centre a step of at most 3.4 studs in any
  direction dodges and still leaves more than a stud of tile (`EnvConfig.spec`). Jumping on to the next
  platform (11-15.5 studs away) also dodges;
* a hit: a horizontal push away from the lane (30-48 studs/s), a 10 studs/s lift (0.25 studs of rise, below
  the smallest step of 3.4, asserted), `PlatformStand` for 0.9 s, camera shake and a white flash. The player
  falls; **the server's existing fall rescue puts them back on their checkpoint**. Nothing is lost: no
  floor, no pick, no read.

**Measured** (`tests/Pacing.spec.luau`: whole runs on real `Section.build` towers, the real scheduler behind
the real `Climb.gate`, 80 runs per row = 3.5-13.5 h of play each, camera pitch -15°). "dodge" = walks out of the
ring when the lane locks; "ignore" = never reacts, keeps climbing on rhythm. "read" takes the safe door,
"guess" flips a coin.

| profile | strategy | behaviour | min / run | hazards / min | near-hits / min | hits / min | hit share | share of play climbing |
|---|---|---|---|---|---|---|---|---|
| fast | read | dodge | 2.66 | 0.366 | 0.366 | 0 | 0 | 0.68 |
| fast | read | ignore | 2.58 | 0.388 | 0.160 | 0.000 | 0.00 | 0.67 |
| fast | guess | dodge | 3.08 | 0.466 | 0.458 | 0 | 0 | 0.78 |
| fast | guess | ignore | 2.97 | 0.434 | 0.173 | 0.004 | 0.01 | 0.78 |
| **normal** | **read** | **dodge** | **4.54** | **0.416** | **0.413 (one per 2.4 min)** | **0** | 0 | 0.70 |
| normal | read | ignore | 4.39 | 0.393 | 0.290 | 0.063 (one per 16 min) | 0.16 | 0.69 |
| normal | guess | dodge | 5.44 | 0.450 | 0.450 | 0 | 0 | 0.79 |
| normal | guess | ignore | 5.22 | 0.441 | 0.352 | 0.089 | 0.20 | 0.78 |
| slow | read | dodge | 8.37 | 0.430 | 0.429 | 0 | 0 | 0.75 |
| slow | read | ignore | 8.05 | 0.432 | 0.368 | 0.174 (one per 5.7 min) | 0.40 | 0.74 |
| slow | guess | dodge | 10.11 | 0.440 | 0.440 | 0 | 0 | 0.81 |
| slow | guess | ignore | 9.81 | 0.441 | 0.375 | 0.176 | 0.40 | 0.80 |

* **"About one near-hit per 2-3 minutes" holds** for the player the warning is for: 0.413 near-hits per
  minute of play for a normal reader who reacts (asserted within 1/3-1/2), 0.37-0.43 for fast and slow; a
  near-hit is a pass within 8 studs (the template's definition). A player who reacts is **never hit**.
* Over every row: **0 hazards launched on a pad, 0 hits on a pad, never 2 at once, never two launches less
  than 70 climbing seconds apart**, and the scheduler's clock equals the climbing seconds (asserted).
* Hazards per climbing second are the same for readers and guessers (0.00987 vs 0.00955 /s, normal profile,
  asserted within 10 %): a guesser meets more per run only because a trapped section is longer.
* The model's assumptions are written in `Config.Pacing` and at the top of `tests/PlayModel.luau`: seconds
  lining up a hop (0.8 / 1.4 / 2.4), missed hops (8 / 18 / 32 %), recovery after a rescue (1.0 / 1.5 /
  2.0 s), seconds at a fork besides the read (3.5 / 6 / 10), 1.1 s to read; a miss or a knock falls the whole
  way to the rescue line (worst case). **When telemetry exists, retune `Profiles.normal` and re-run the spec.**
* The model moves a player from the exit straight onto the next pad, so it never had the exit-edge window
  the review found (§14 finding 2), and the gate's floor-clear dismissal changes none of its numbers:
  `Pacing.spec`'s output is byte-identical before and after the fix.

Through the real client (`check_forktower_env`, hazards due every 8-9 s in memory for that run): the dungeon
(floors 1-2, 140 s of climbing) launched nothing; 40 s on an unread fork pad launched nothing and the chip
never warned; climbing the garden, a garden kind launched within 10 s (IntervalMax + 1); the chip warned `KOMMER`, then `FLYTT DEG!`; standing still in
the ring knocked the player (PlatformStand, ≥ 20 studs/s sideways, lift ≤ 15); the server's rescue put them back
on their section with the floor unchanged; walking out of the ring at the lock dodged; a hazard in flight when
the player stepped onto a fork pad while still climbing was gone within two frames; a hazard in flight when the
floor was cleared was gone in the first frame after the next fork existed, and a read begun from the exit's
front edge (in the prompt's reach, off the pad) completed in exactly `ReadSeconds` of server time with nothing
flying and no knock (§14); at all ten floor clears of a run the ambience saw the new floor within a frame of the
next fork existing; floors 4-10 flew only their own bands' kinds; after clearing a floor, 12 s on the exit
platform (next fork unanswered, off the pad) launched nothing new; 30 s on the summit launched nothing.

---

## 4. Rest — what "pause" means in Fork Tower

A Roblox server cannot stop the world for one player, so rest is a place and a state:

* **Every fork pad is a bench.** The pads (and the lobby and the summit) are a sanctuary: no hazard runs,
  launches or hits there, and one in flight is dismissed on arrival. A player can stop at any fork for as
  long as they like, read or not, and nothing comes for them. That is also where the design needs them
  undisturbed (the read).
* **☕ Hvil** (in the ambience row under the toast, or up in the header on a landscape phone; thumb-sized on
  phones): on a section platform, sits the
  player down, softens the view (depth of field), and the chip says `☕ Hviler — farene lar deg være`.
  Press again (`▶ Klatre`) or just move to carry on.
* **Idle rest**: standing still for 20 s pauses hazards (`💤 Pause`), AFK-safe. The player is not sat down.
* While resting the hazard clock **freezes**; the sky, the life and the weather go on. Nothing is lost,
  nothing is earned. Roblox's own ~20-minute idle disconnect still applies; the profile is saved (every
  reveal and pick is saved as it happens), and a rejoin puts the player back on their fork or section.

**Why it cannot be exploited**

1. **There is no clock to dodge.** Fork Tower has no round timer, no raid, no timed leaderboard (the board
   ranks the best build SCORE), no penalty that runs on time. The only thing rest pauses is the client's
   hazards, and a hazard takes nothing.
2. **The read is timed by the server.** `onReadInscription` charges `Config.Fork.ReadSeconds` on the
   server's own clock; nothing on the client, rest included, can shorten it. The read is untouched by this
   work (`Main.server.luau` is byte-identical).
3. **No climbing while resting.** Progress is the server's `Touched` on its own platforms and needs
   movement; any movement input, a jump or leaving the ground wakes the player (`Rest.validate` refuses
   `WakeOnMove = false`).
4. **Not a panic button.** Rest cannot start in the air or with a hazard inbound (`Rest.validate` refuses
   `BlockWhileThreat = false`). Pressing it then queues the request (`☕ …`): the hazard still comes, rest
   never removes one in flight, and rest begins only once the sky is clear and the player stands still. The
   queue expires after 8 s, longer than the longest flight (5.9 s) plus a second (asserted). Measured through
   the client: a request under a threat did not sit the player, the hazard kept coming, and the rest began
   once it had passed.
5. **Toggling does not thin hazards.** Rest freezes the climbing clock, never resets it. Measured
   (`Pacing.spec`): 34.5 hazards per climbing hour without rest, 34.1 for a player resting 30 s of every 75
   (214 minutes rested). Through the client: after a 40 s rest the next hazard came within one interval of
   climbing, exactly where the frozen clock left it.
6. **The sanctuary is not a shortcut.** It is where a player must stand to read and to choose anyway, and
   it does not move the player, save anything, or touch the server. A hazard dismissed on reaching the next
   fork, or on clearing the floor (landing on the exit, §14), was a hazard the player outran by climbing,
   which is progress, not a dodge of anything the design depends on. Rest never dismisses one: resting is
   not "not climbing" (the gate still lets a hazard in flight land on a resting climber).

---

## 5. Hazards against the read's price

`Config.Fork.ReadSeconds = 1.1` is the break-even against never reading, measured as climbing time
(`readcost.measure.luau`, still 1.110 s at hit rate 0, unchanged by this work). Hazards could touch it in
two ways, and both are closed or measured:

* **the read itself**: hazards never run, launch or hit on a fork pad, so standing still for 1.1 s to read
  costs exactly 1.1 s. **The review found this held only on the pad** (§14 finding 2): the prompt also
  reaches the front of the exit platform, off the pad, and a hazard launched in the last seconds of the
  climb knocked a reader there 0.97 s into the hold. It holds wherever the prompt reaches now: clearing the
  floor dismisses whatever is in flight, in the first frame the next fork exists. Asserted through the
  client (a read begun from the exit's edge, with a hazard in flight at the floor clear, completed in
  `ReadSeconds` of server time, nothing flying, no knock) and in the model (0 launches and 0 hits on pads);
* **the trap's cost**: a trapped section is longer, so a guesser spends longer in hazard bands and, if they
  ignore warnings, gets knocked more. That can only make guessing costlier, never cheaper, i.e. it moves the
  break-even UP (reading worth a little more). Measured (`Pacing.spec`: the guesser's extra climbing per run
  × the knocks per climbing second × one knock's cost ÷ ten floors):

| profile | reacts to warnings | ignores warnings |
|---|---|---|
| fast | +0.000 s per read | +0.000 s |
| normal | +0.000 s | +0.027 s (2.5 % of the read) |
| slow | +0.000 s | +0.134 s (12 %) |

For everyone who reacts to the warning the read's price is untouched; the worst case (a slow climber who
ignores every warning) moves it from 1.110 to about 1.24 s, inside the 1.110-1.599 s range the read's own
measurement already spans across hit rates on the server's cubes. Asserted: ≥ 0 always, 0 for reacting
climbers, ≤ 0.05 s for normal, ≤ 20 % of the read for anyone.

---

## 6. Client vs server, and why nothing leaks

| what | where | why |
|---|---|---|
| bands, lighting, sky, walls, far pieces, life, weather, lightning, title cards, chip, lantern | **client** (`Ambience.client` + `TowerArt`) | cosmetic and per-player (the world follows *your* floor); costs the server nothing, replicates nothing |
| hazards: schedule, telegraph, hit test, knock | **client** | they harm only the local player, whose character physics the client already owns. The server trusts nothing from here: progress is still only its own platform `Touched`; the knock's lift is capped below the smallest step; an exploiter who deletes hazards gains nothing a flying exploit would not already give |
| rest | **client** | it only pauses client hazards |
| floors, reads, doors, sections, picks, rebirth, saves, leaderboard, **fall rescue** | **server** (unchanged) | authoritative, as before |
| the ambience row's place and size, and the title card's slot | `Hud.client` | one script owns the layout, so the chip, the button and the card can never overlap the HUD, and all three keep off the player's character (`PLAY_TOP`, §14) |

**What the ambience reads**, and the four things that hold it there (`check_forktower_env_secret`, 92 / 0):

* **A. statically**, from the sources the bundle ships (`Ambience.client`, `TowerArt`, `Climb`, comments
  stripped): the only attributes read are `Owner` (my lane) and `Exit` (a chosen section's top); no
  attribute is written or enumerated; nothing names a door, a sign, `Marked`, `TellKind`, `RuleInverted`,
  the inscription, a penalty, a theme, `floorSecrets`, `legacySecrets`, `isTrap`, `trapDoor`, a
  ProximityPrompt, the `Read` attribute or the Fork module, and nothing touches a remote; the only children
  looked up by name are the pads, a section, the Reveal card and leaderstats;
* **B. at every unread fork of a real run**: nothing the ambience places by rule comes within 20 studs of
  either door or onto the pad, and every wall part has its mirror twin across the lane's centre line;
* **C. a read changes nothing it draws**: at every one of ten forks, everything that does not move by itself
  (Lighting, atmosphere, sky, bloom, colour correction, sun rays, every wall part, the chip) is recorded
  from a frozen camera under a quiet sky (no lightning bolt for 1.5 s), the inscription is read, and it is
  recorded again the same way: identical, ten of ten;
* **D. no secret in it**: after the run the player's ten saved floor secrets are read from their record and
  every name, text, attribute and number of everything the ambience made during the run, parented at the
  end or pooled out of the scene (355 instances, every band's walls, far pieces, critters, weather and
  lightning, asserted by name), is swept for them, in decimal and hex: none.

Critters, weather and lightning are ambient (spawned at random around the camera, or random in time) and
are left out of B and C; A and D cover them. Hazards never exist at a fork.

The client fires no remote and adds none (counted: every server call in the check was the check's own),
sets no attribute on anything the server built, and every part it makes is anchored, non-collidable,
non-queryable, non-touchable and casts no shadow; nothing new appears in the workspace outside its own
`ForkLocalEnv` folder except the lantern on its own root part (`check_forktower_env` §7).

**What other players see**: nothing of it. Each client draws its own floor's world; a knock looks, to
others, like a player falling with nothing hitting them (hazards are local). On the Studio list.

---

## 7. Budgets (measured, `check_forktower_env`)

Client-built only; the server builds none of this. Measured every frame of the whole check: 6 s at each of
ten forks, every climbing frame of ten floors (so every seam, both bands live), the summit, the rebirth
glide, every hazard flight at an 8-9 s interval, the knock and the rest sections. The numbers move by a few
parts from run to run with the random critters, so they are given as the range over the **40 final runs**
of the check on the final tree (2026-09-24), the most common value in brackets.

| where | parts | emitters (rate) | beams | trails | lights |
|---|---|---|---|---|---|
| floor 1 (dungeon), mid-climb | 59-61 (61) | 1 (6/s) | 0 | 0 | 1 |
| floor 2 (dungeon › garden seam) | 112-114 (114) | 2 (6/s) | 0 | 0 | 1 |
| floor 3 (garden) | 72-73 (73) | 1 (7/s) | 0 | 0 | 1 |
| floor 4 (garden › clockwork seam) | 130-134 (134) | 2 (8/s) | 0 | 0 | 1 |
| floor 5 (clockwork) | 72-74 (74) | 1 (9/s) | 0 | 0 | 1 |
| floor 6 (clockwork › storm seam) | 111-115 (115) | 2 (14/s) | 0 | 0 | 1 |
| floor 7 (storm) | 48-49 (49) | 1 (39/s) | 0 | 0 | 1 |
| floor 8 (storm › observatory seam) | 81-83 (82) | 2 (32/s) | 0 | 1 | 1 |
| floor 9 (observatory) | 39-40 (40) | 1 (7/s) | 0 | 1-3 | 1 |
| floor 10 (observatory › crown seam) | 53 | 1 (7/s) | 0 | 1-3 | 1 |
| summit (crown) | 18-19 (19) | 1 (9/s) | 4 | 2-5 | 1 |

| metric | measured peak (40 runs) | where | budget (`Config.Budget`) |
|---|---|---|---|
| local parts | **143-146** (143-149 over 30 runs of the check as extended by the review fix, §14) | a hazard in flight in the garden (the 8-9 s section) | 200 |
| particle emitters | 2 (every run) | dungeon › garden seam | 3 |
| particles per second | **40** (every run) | storm rain | 50 |
| beams | 4 (every run) | the galaxy's arms, fading in on floor 10 | 8 |
| trails | 5 (36 runs), **6** (4 runs); after the review fix 5 (28 of 30), 6 (2 of 30) | floor 10: shooting stars of both night bands, plus a meteor's or comet's trail when a hazard happens to fly there | 6 |
| point lights | 2 | the lantern + a hazard's blink | 3 |
| hazards at once | 1 | | 1 |

Trails reach their budget exactly, and cannot pass it: the shooting-star pool never holds more than the
five the crown asks for (a critter leaving still counts until it is gone, so none is spawned over it), and
only one hazard flies at a time. The weather cap is enforced in TowerArt, not left to the config (a probe
asks for all five weathers at full rate and gets at most 2 emitters under 50/s; §13 item 5).

**How it stays cheap:** a band's pieces are built the first time it needs them and **unparented** at zero
weight (asserted: back in the dungeon, no other band's scenery is parented). The walls are world-fixed grids of
cells (5 along the climb × 3 up, each side), each cell's content a hash of its coordinates; a cell keeps its
parts while it is in view, so the camera moving re-places only the row that leaves, as the row that enters, and
both are invisible at that moment (not after a teleport: §13 item 6). Wall transparency is updated every frame
but written only on a change of more than 0.01; gears turn at 20 Hz. Critters are pooled per kind, spawned at
most one group per frame and recycled when out of range (asserted: 40 s standing in the garden, never fewer than
3 in range). One model per hazard kind, one lane, one ring; one weather host with at most 2 emitters
(`EnvBands.capRates`, 50/s summed); a 5-part lightning pool. Lighting is written at most 10 times a second and
only when a value changed.

These are part and emitter counts, not frame time. Frame time on a real phone is on the Studio list, and the
tower itself (every player's lane) is server-built on top of this.

---

## 8. Gates

Every gate for this game: before the environment work (2026-09-17 tree), as the resume session found the
tree (2026-09-24, before any change), at the end of the resume session, and after the review fix (§14).

| gate | before the work | as found | resume session | **after the review fix** |
|---|---|---|---|---|
| `tests/Build.spec` | 31 / 0 | 31 / 0 | **31 / 0** | **31 / 0** |
| `tests/Codes.spec` | 19 / 0 | 19 / 0 | **19 / 0** | **19 / 0** |
| `tests/Fork.spec` | 71 / 0 | 71 / 0 | **71 / 0** | **71 / 0** |
| `tests/Rng.spec` | 32 / 0 | 32 / 0 | **32 / 0** | **32 / 0** |
| `tests/Section.spec` | 50 / 0 | 50 / 0 | **50 / 0** | **50 / 0** |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | **70 / 0** | **70 / 0** |
| `tests/Climb.spec` | — | 66 / 0 | **66 / 0** | **67 / 0** (was 64 / 3 before the fix) |
| `tests/EnvConfig.spec` | — | 361 / 0 | **361 / 0** | **361 / 0** |
| `tests/Pacing.spec` | — | 87 / 0 | **87 / 0** | **87 / 0** (output byte-identical) |
| `tests/EnvBands.spec` (template, verbatim) | — | 124 / 0 | **124 / 0** | **124 / 0** |
| `tests/Hazards.spec` (template, verbatim) | — | 102 / 0 | **102 / 0** | **102 / 0** |
| `tests/Rest.spec` (template, verbatim) | — | 55 / 0 | **55 / 0** | **55 / 0** |
| **spec total** | **273 / 0** | **1 068 / 0** | **1 068 / 0** | **1 069 / 0** |
| `tests/readcost.measure.luau` (a measurement) | break-even 1.110 s | 1.110 s | **1.110 s** (unchanged) | **1.110 s** (output byte-identical) |
| `tests/world.check` | 71 / 0 | 71 / 0 | **71 / 0** | **71 / 0** |
| `robloxemu/check_forktower` | 129 / 0 | 129 / 0 | **129 / 0** | **129 / 0** |
| `robloxemu/check_forktower_plansecret` | 96 / 0 | 96 / 0 | **96 / 0** | **96 / 0** (file byte-identical) |
| `robloxemu/check_forktower_env` | — | 196 / 0 (flaky: 1 run in 16) | **204 / 0** | **215 / 0** (the final check run on the resume session's tree: 210 / 5) |
| `robloxemu/check_forktower_env_secret` | — | 90 / 0 (flaky: 1 run in 12) | **92 / 0** | **92 / 0** |
| `robloxemu/check_forktower_env_join` | — | — | **37 / 0** (new) | **37 / 0** |
| `robloxemu/check_forktower_hud` (hudcheck, drawers closed, 10 viewports, overlap on) | PASS (HUD alone) | PASS | **PASS** | **PASS** |
| `robloxemu/check_forktower_hud_open` (drawers and card open, 10 viewports) | 144 / 13 (the final check run on the HEAD HUD: 10 real failures, 3 about the row it lacks) | 145 / 12 (the final check run on the HUD as found: both drawers and the card 1 px tall on landscape phones) | **157 / 0** (new) | **157 / 0** |
| `robloxemu/check_forktower_hud_play` (the HUD against the player's character, 13 viewports, 3 pitches) | — | — | — (the check run on the resume session's tree: 242 / 72) | **324 / 0** (new) |
| **headless total** | **296 / 0 + PASS** | **582 / 0 + PASS** | **786 / 0 + PASS** | **1 121 / 0 + PASS** |
| compile (`luau` `loadstring`; `luau-compile` and `luau-analyze` are not on this machine) | — | — | 39 of 39 | **40 of 40** files (17 sources, 15 test files, 8 checks) |

**Stability on the final tree** (the checks whose runs use the client's unseeded `Random` or the server's
random secrets, run again and again after the last change):

| check | runs | result |
|---|---|---|
| `check_forktower_env` | 40 | 40 × 204 / 0 |
| `check_forktower_env_secret` | 10 (+20 earlier the same day, after the C/D fix) | 10 × 92 / 0 (and 20 × 92 / 0) |
| `check_forktower_env_join` | 5 (+10 earlier) | 5 × 37 / 0 |
| `check_forktower_hud_open` | 3 | 3 × 157 / 0 |
| `check_forktower_hud` | 3 | 3 × PASS |
| `check_forktower_plansecret` | 3 | 3 × 96 / 0 |
| `check_forktower` | 3 | 3 × 129 / 0 |
| `tests/world.check` | 3 | 3 × 71 / 0 |

**Stability after the review fix** (the final tree, bundle md5 `dd38fa7eeb2f8a1e6a3b045974627b28`; 61 runs,
4 at a time):

| check | runs | result |
|---|---|---|
| `check_forktower_env` | 30 | 30 × 215 / 0 (peak parts 143-149, trails 5 or 6, camera-teleport frames 65 of ~22 800 every run) |
| `check_forktower_env_secret` | 8 | 8 × 92 / 0 |
| `check_forktower_env_join` | 8 | 8 × 37 / 0 |
| `check_forktower_hud_play` | 3 | 3 × 324 / 0 |
| `check_forktower_hud_open` | 3 | 3 × 157 / 0 |
| `check_forktower_hud` | 3 | 3 × PASS |
| `check_forktower_plansecret` | 3 | 3 × 96 / 0 |
| `check_forktower` | 3 | 3 × 129 / 0 |

The two flakes fixed in the resume session, each shown first on the unchanged tree and then forced:

| flake | unchanged tree | forced | old check under force | fixed check under force |
|---|---|---|---|---|
| `env_secret` C: a lightning flash inside one of the two snapshots | 1 run in 12 failed | storm lightning every 2-2.5 s | 8 of 8 failed | 8 of 8 passed |
| `env_secret` D: the coverage count came out ≤ 100 | failed in 2 sweep runs and 1 stress run | — | — | 355 instances every run, asserted by name |
| `env`: a hazard due inside the first run, so the garden's came 70-110 s late | 1 run in 16 failed | first interval rolled at 60 s | 3 of 3 failed | 3 of 3 passed |

---

## 9. Mutation sweep

**Final: 50 mutations on the final tree, 46 of 46 killed, 4 of 4 controls survived** (2026-09-24, run 3;
bundle md5 `e3e48a53905b2bd512c6160fa378a756`). The review-fix session swept its own changes separately:
17 of 17 killed, 4 of 4 controls survived (§14).

**How each mutation was run** (the driver is `ft_resume/sweep/sweep.py` in the scratchpad):
* on a scratch copy verified file-for-file against the real tree (40 files), so the real tree was only read;
* exactly one occurrence of the text is replaced;
* for a source file, the bundle is rebuilt and must equal the baseline bundle with that same single
  replacement (path lines aside), which proves the mutation reached `build/fork-tower.luau`;
* every suite runs: 12 specs, `world.check` and the 7 `check_forktower*`;
* a suite that fails, errors or prints no summary kills it;
* the original bytes are restored and md5-checked, and the bundle is rebuilt and compared again.

After the last mutation every suite was green on the restored copy. A control is a real edit that no
promise depends on, and it must survive, or the harness is broken.

| id | mutation | killed by |
|---|---|---|
| M1 | Climb.gate: the hazard clock runs on a pad | Climb.spec |
| M2 | Climb.gate: a hazard may hit on a pad | Climb.spec |
| M3 | Climb.gate: a hazard in flight is never dismissed on a pad | Climb.spec, env |
| M4 | progress at an unanswered fork follows altitude | Climb.spec |
| M5 | progress not clamped (a fall takes the world back) | Climb.spec |
| M6 | nearestClock: no short arc | Climb.spec, env, env_secret |
| M7 | namedFloor: the summit named as floor 10 | Climb.spec, EnvConfig, Pacing, env |
| M8 | onPad ignores the player radius | Climb.spec |
| G1 | Ambience: "climbing" at an unanswered fork | env |
| G2 | Ambience: fork pads are not sanctuaries | env |
| G3 | Ambience: the hazard clock not gated | env |
| G5 | Ambience: no short arc for the clock | env, env_secret |
| G7 | Ambience: band weights snap (no glide) | env |
| G8 | Ambience: the lantern never lights | env |
| G9 | Ambience: knock without PlatformStand | env |
| G10 | Ambience: no hazard warning on the chip | env |
| G11 | Ambience: the Rest button does not sit the player | env |
| G12 | Ambience: rest does not freeze hazards | env |
| G14 | Ambience: a band card behind the Reveal card is dropped, not queued | env |
| G15 | Ambience: the join jumps to the band instead of gliding from the server's preset | env |
| G16 | Ambience: the first title card does not wait for the profile and the lane | env_join |
| L1 | **LEAK**: lighting reacts to a door's `Marked` attribute, obfuscated past the static audit | env, env_secret |
| L2 | TowerArt: walls not mirrored | env_secret |
| L3 | Config: walls moved into the tower's corridor | EnvConfig, env_secret |
| T1 | TowerArt: hide does not reset transparency (the template's pop-in) | env (the new probe) |
| T2 | TowerArt: no edge fade on the wall grid | env |
| T3 | TowerArt: every wall slot re-placed on every cell crossing | env |
| T4 | TowerArt: wall slots do not glide | env |
| T5 | TowerArt: the weather emitter cap ignored | env (the new probe) |
| T6 | TowerArt: critters never recycled | env |
| T7 | TowerArt: the summit crown circles the camera, not the climber | env |
| K1 | Config: hazards twice as often | EnvConfig, Pacing |
| K2 | Config: the dungeon (onboarding) gets hazards | EnvConfig, env |
| K3 | Config: the observatory at 0.2 (the sun runs backwards) | EnvConfig, env_secret |
| K4 | Config: sanctuary radius 0 | EnvConfig |
| K5 | Config: a queued rest outlived by a hazard flight | EnvConfig, env |
| K6 | Config: part budget below the measured peak | env |
| K7 | Config: a piece id typo (the planets vanish silently) | env (the new name check), env_secret (D's coverage by name) |
| K8 | Config: a weather kind typo (the storm's rain stops silently) | env (the new name check) |
| H1 | Hud: the ambience row not touch-sized | hud |
| H2 | Hud: the side panels start on top of the ambience row | hud_open |
| H3 | Hud: a phone drawer ignores the centred stack | hud_open |
| H4 | Hud: the menu drawer hangs from `bandTop` again (1 px on a landscape phone) | hud_open |
| H5 | Hud: a drawer's bottom is the clamped `bandBottom` (into the thumbstick) | hud_open |
| H6 | Hud: the Build Reveal card never takes the side column | hud_open |
| H7 | Hud: the card's side column centred instead (over the inscription) | hud_open |
| C1 | CONTROL: the clock rim two shades lighter | survived |
| C2 | CONTROL: every torch flame a touch yellower (both walls alike) | survived |
| C3 | CONTROL: lightning a second more often (6-12 s → 5-11 s) | survived |
| C4 | CONTROL: the card's side-column threshold 40 → 60 (no viewport sits near it) | survived |

**The new assertions against the checks as they stood.** The same current sources were run against the
session's STARTING checks: the old `env` and `env_secret`, no `env_join`, no `hud_open`
(`ft_resume/sweep_old`). The new mutations are not all caught there, and the ones that look caught mostly
got that verdict from the flakes this session fixed:

| id | at the session's start | now |
|---|---|---|
| G16, K8, T5, H5, H7 | **survived** | killed |
| T1, H2, H3, H4, K7 | "killed" **only by `env_secret`'s flakes** (a lightning flash at floor 7 or 8, or the coverage count at 92-100) | killed by the assertion written for them |
| H6 | "killed" **only by `env`'s own flake** (a hazard due inside the first run) | killed by `hud_open` |
| L1 | killed for real (`env` lighting settle, `env_secret` C at floor 1) | killed |
| C3, C4 | survived | survived |

**History.** The first session's sweep ran 20 of its 40 mutations before it was cut off, all killed, some
by those same flakes. Run 1 of the resume session (44 mutations) killed 38 and left three survivors, T1, T5
and H2, each a hole (§13 items 4, 5, 7). Run 2 (50 mutations, after those were fixed) killed 46 of 46, but
its closing run on the restored copy failed `env` once. Together with H6's verdict on the before-side run,
that is how `env`'s second flake was found (§8's flake table: then measured at 1 run in 16, forced, and
fixed). Run 3, after that fix, is the one above. Logs:
`ft_resume/sweep/sweep_run1_before_hudfix.log`, `sweep_run2.log`, `sweep.log`,
`ft_resume/sweep_old/sweep.log`.

---

## 10. Needs Studio (only real rendering and a real device can judge)

1. **Every band's look.** Is the tower readable in the dungeon (night 0.5, atmosphere 0.56, exposure 0.35)
   with only the pads' own glow, the neon exits and the climber's lantern? Is the storm dark enough, the
   observatory's night bright enough? Bloom per band (the torches and blooms are Neon).
2. **The walls at 90-120 studs from the lane's centre.** Do they read as a hall, a garden, a machine, a
   storm, or as far-off clutter? Too sparse, too dense? The grid fades at its edge (±150 studs along the
   climb, ±90 up); is the fade visible? Do the mirrored walls look designed or repetitive?
3. **Gears**: a disc and a bar across it, turning. Do they read as gears? (More teeth cost parts.)
4. **The far set pieces follow the camera** (the clock face 560 studs ahead, the far blooms, the planets,
   the galaxy, the storm deck): do they read as distant landmarks or as glued to the camera?
5. **The moon**: `MoonAngularSize` 26 at `ClockTime` 23.6 with 4 000 stars and atmosphere 0.08. Does
   Roblox draw it large and where is it in the sky? (The shot list asks the session to find it.)
6. **Lightning**: flash strength (+0.3 colour-correction brightness for 0.14 s), bolt size and distance
   (260-560 studs), rain density (40/s over a 120 × 120 box).
7. **The crown of stars** circling the climber at the summit: lovely or in the way of the Build Reveal card
   and the plinth?
8. **The telegraph on a phone**: the red chip under the toast, the ⚠️ billboard, the lane line, the ring.
   Is a 6.2-6.8-stud ring on a 9-stud tile comfortable to leave with a thumbstick? Is 1.5-1.8 s after the
   lock enough?
9. **The knock**: does `PlatformStand` + `AssemblyLinearVelocity` push the character off the platform
   (humanoid damping), does it release cleanly, and how long is the fall to the server's rescue (70 studs
   below the checkpoint; a real fall often lands on a lower platform of the same section first)?
10. **Other players see a knock with nothing hitting** (hazards are local). Glitch or fine?
11. **Rest's sit**: `Humanoid.Sit = true` from the client without a seat: does it sit and replicate, does walk
    input wake it, does jump unsit?
12. **The ambience row on a real phone**: notch/safe area, emoji in `TextScaled` labels, chip text length
    (`🌿 Den gjengrodde hagen · ⚙️ om 2 etasjer` is the longest). `hudcheck` passes at ten viewports, but
    it cannot see a notch. On a landscape phone the row is now in the header, between the counter and the
    🏆 Topp toggle, 4.8 px from it (§14): mis-taps between ☕ Hvil and 🏆 Topp?
13. **Frame time** on a mid/low phone at the densest seam (145 local parts at a seam with a hazard) on top of
    the tower and the neighbouring lanes.
14. **The join glide**: the server's preset (`Fx.Presets.Fork`, violet dusk) glides to the dungeon's night
    over ~3 s at join. Fine, or should the server preset become the dungeon look (a server change, not done)?
15. **The server's red hazard cubes** look out of place in the garden and the observatory (server change,
    not done; README already lists "hazards all look the same").
16. **Neighbouring lanes**: my walls stand between my tower and my neighbour's (their tower's corridor starts
    145 studs from my centre line, 220 − 60 − 15; my walls end at 120). Clutter, or a nice sense of other
    towers beyond the hall?
17. **A slow join**: until the server has loaded the profile the player waits on the pad under the dungeon's
    night; when the lane appears the sky glides (0.6 s half-life) to their band, e.g. dusk storm for a
    floor-7 climber, and one quiet card says where they are. Does the glide read as arriving, or as a flicker?
18. **The observatory's planets turn slowly around the whole sky** (the `planets` piece spins about the
    camera, one turn in about 26 minutes; the storm deck turns too, once in ~10 min). Does that read as a
    living sky, or as the planets sliding?
19. **A teleport and the far wall parts** (§13 item 6): when the server's fall rescue (or a door choice, a
    rebirth, a join) moves the camera further than the wall grid's fade can follow, a row of wall parts at
    the edge of the grid (100-140 studs out) that is still partly visible vanishes in that frame. Visible,
    or lost in the cut? If visible, the fix is double-buffered wall slots (doubles the wall part count).
20. **The HUD on a landscape phone** (§13 item 7), a layout no human has seen: the ☰ Meny and 🏆 Topp
    drawers now hang from under their toggles beside the inscription (135 px tall on 800x360, 95 on
    640x300), and the Build Reveal card sits in the column right of the inscription instead of under it.
    Readable? Does the card's narrower column (as little as 279 design px on 640x300) still show the build
    title, the rarity, at least one trait row and LUKK? Portrait phones and larger screens are unchanged.
    Since the review (§14) the header of a landscape phone is a toolbar: ☰ Meny, the floor counter (moved
    beside the menu toggle on 640-844 px wide phones; still centred on 926x428), the band chip, ☕ Hvil,
    🏆 Topp. Does it read as one bar, and is the counter still the first thing the eye finds?
21. **The band title card** (§14): a gold-on-dark plate in the strip above the character on a 1920x1080
    monitor (470x84 px), a portrait phone and a small window; on the chip itself (the chip's size, 3.8 s)
    on a landscape phone, a 1366x768 laptop, a tablet and a 1280x720 window. Does the small one on the
    chip still feel like arriving somewhere new, or should it be bigger there (nothing on those screens
    has room for it without covering the character or the inscription)?
22. **Hazards coming from behind the inscription on a landscape phone** (measured, not fixed; §14 finding
    1). The strike point and the red ring are never covered now (0 of 400 launches, was 400 of 400), but
    the inscription panel, pre-existing and centred just above the character, still hides 64-74 % of a
    hazard's flight frames at camera pitch -15 to -30 on 800x360 (31 % level), and most of the last second
    of 36-39 % of flights. The chip's warning (with its direction arrow), the lane line and the ring stay
    visible. If players are surprised, the options are Gustav's: fade the inscription while climbing on a
    phone (it only matters at a fork), or keep hazards' launch angles out from behind it.
23. **The server's toast covers the character's head on a landscape phone** for 3.5 s after each notice
    (pre-existing; `check_forktower_hud_play` reports it at 800x360, 844x390, 926x428 and 640x300 and does
    not assert it). Worth moving?
24. **On a 640x300 phone the inscription's bottom edge crosses the top 7-11 px of a tall avatar's head box**
    (HEAD layout, from before the environment work; 0-8 px for a bare R15 head). Held where it is by
    `check_forktower_hud_play` (it may not sit lower) and not moved: it is the game's one indispensable
    panel.

---

## 11. Thumbnail shot list (for the night Studio session)

**Getting there.** *Not yet tried in Studio.* Step 1 was run headless on 2026-09-24: `rojo build` succeeds
and the place holds `Ambience` (LocalScript, StarterPlayerScripts), `Hud`, `Main` and the new modules.

1. **Build a place that has the environment.** In `fork-tower/`, run `rojo build -o ForkTower-shots.rbxlx`
   and open that file (`*.rbxlx` is git-ignored). **Do not use `ForkTower.rbxlx` on disk: it predates this
   work.** Keep Rojo disconnected while editing the place.
2. **No saves.** *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server then
   plays with a fresh profile every Play (floor 1, no rebirths) and writes nothing anywhere.
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`:
   * **Session A (shots 1, 2, 4, 5, 6):** `Hazards.IntervalMin = 100000`, `Hazards.IntervalMax = 100001`
     (nothing knocks the avatar out of a frame) and `Rest.IdleSeconds = 0` (idle rest off, so the chip keeps
     showing the band while you frame; `Rest.validate` accepts 0).
   * **Session B (shot 3):** `Hazards.IntervalMin = 20`, `Hazards.IntervalMax = 25`, `Rest.IdleSeconds = 0`.
     Hazards then come every 20-25 s of climbing from floor 3 on; on the way up to floor 6, walk out of each
     red ring when the chip says `FLYTT DEG!` (a hit only knocks you down; the rescue puts you back).
     `Hazards.validate` and `Rest.validate` accept both sessions' values (read 2026-09-24).
4. **Climb honestly, and shoot on the way up.** The environment follows the floor the SERVER has you on (the
   highest fork built), not where you stand, and the server's fall rescue sends you back to your checkpoint if
   you drop more than 70 studs below it, so shots are taken in order, going up. At each fork hold **R** (LES)
   for 1.1 s and take the door the inscription says is safe. **Always take the safe door**: with a fresh
   profile, an all-safe run builds exactly the tower below (lane 0, the first player in the server; measured
   for two players with different secrets: identical). A trapped door builds a longer section and moves
   everything above it.
5. **Clean frames**: command bar, Client context:
   `game.Players.LocalPlayer.PlayerGui.ForkHud.Enabled = false` (hides the HUD and the band chip with it).
   For an exact camera:
   `local c = workspace.CurrentCamera; c.CameraType = Enum.CameraType.Scriptable; c.CFrame = CFrame.lookAt(Vector3.new(X, Y, Z), Vector3.new(TX, TY, TZ))`,
   and `c.CameraType = Enum.CameraType.Custom` to give it back. Freecam (Shift+P) also works; it hides
   ScreenGuis, not the doors' billboards.
6. Let each band settle ~4 s after arriving (0.6 s half-life) before shooting.

Positions (all-safe run, lane 0, `WorldSeed 20260909`, fresh profile), measured headless and re-measured on
the final bundle 2026-09-24 (identical). A section's geometry is seeded by the world seed, the run seed, the
floor and whether it is the trap, never by the door's theme or the floor's secret, which is why the safe
path is the same tower in every Studio session: fork pad tops
`ForkPad_1` (0, 0, 14) · `ForkPad_3` (0, 35, 147.8) · `ForkPad_4` (−34.5, 57.8, 215.8) · `ForkPad_5`
(−46.2, 81.8, 284.5) · `ForkPad_6` (−34.2, 111.2, 342) · `ForkPad_7` (2.5, 142, 424.5) · `ForkPad_8` (−10,
178.8, 520.5) · `ForkPad_9` (−48.2, 217.2, 617.8) · `ForkPad_10` (−9.2, 262.2, 729.2) · summit pad top (−9.2,
309, 882). Mid-section platforms: `Plat_3_4` top (−23, 50.2, 187.8), `Plat_7_5` top (−10, 165, 466.5). The
doors of fork *n* stand 8 studs past the pad's centre (+Z), 6.5 studs either side. The scenery walls stand at
x = −105 and +105 (±15).

1. **"Which door?" — the dungeon, floor 1 (the core mechanic).** Session A, right after spawning. Avatar on
   `ForkPad_1`, centred, facing the doors (+Z), the fork unread. Camera `(0, 8, 0)` looking at `(0, 6, 26)`,
   low behind the avatar. In frame: the avatar's back, **both doors identical** (`🚪 DØR` billboards, the
   same colour), the inscription billboard `🔒 INNSKRIPSJONEN ER ULEST`, the warm night, embers, and beyond
   the doors the torch-lit pillars receding into the dark on both sides. Take a second one with the HUD on
   (the chip reads `🕯️ Fangehullet · 🌿 om 2 etasjer`). Do not read the inscription before this shot.
2. **"The overgrown garden" — floor 3.** Session A. Choose floor 3's door and stand on `Plat_3_4` (−23,
   50.2, 187.8), then jump toward the next platform. Camera `(35, 60, 176)` looking at `(−23, 54, 190)`,
   side-on, standing between the tower and the wall at x ≈ +105 and looking toward −x, so **the wall at
   x ≈ −105 fills the background**: giant leaves, hanging vines, glowing pink, yellow and violet blooms. In frame: the avatar
   mid-jump with its trail, butterflies and fireflies, pollen, morning sun rays. A giant horizon flower if one
   is in the view (they sit 380 studs out at three fixed bearings; turn the camera to find one).
3. **"Inside the clockwork" — floor 6, with a flung cog.** **Session B**; climb to floor 6. Avatar on a
   platform of section 6 above `ForkPad_6` (−34.2, 111.2, 342), e.g. `Plat_6_4` top (−9.8, 128.8, 383.5), stood
   still (the door chosen, off the pad: hazards only run while climbing a section), **normal camera** (a hazard
   starts inside the player's own view; Freecam would take the movement keys): turn it to look along the climb
   (+Z), level or a little down (see the clock face below). When `⚠️ TANNHJUL KOMMER` shows and the lane turns red (`FLYTT DEG!`), walk out of the
   red ring **sideways** and screenshot as the cog rolls through. The clockwork flies two kinds; if
   `⚠️ URVERKSFUGL KOMMER` (the brass clockwork bird) comes instead, take that one too, it is just as good a
   frame, or let it pass and wait 20-25 s of climbing for the next. In frame: the cog with its ⚠️, the red lane
   and ring, the avatar clear of it, **brass gears turning on both walls**, and **the great clock face** above
   the climb. It rides 560 studs along +Z and 110 up from the camera (about 11° above the camera's horizon,
   about 28° across), so with the default follow camera looking along +Z and a little down (~10°) it fills
   the upper half of the frame; tilting the camera UP moves it toward the middle. A hit only knocks the avatar down; the rescue puts it back for another try. Without a
   hazard, the same framing on `ForkPad_6` makes a calmer variant.
4. **"Into the storm" — floor 7.** Session A. Avatar mid-jump near `Plat_7_5` (−10, 165, 466.5). Camera
   `(−70, 176, 444)` looking at `(−10, 166, 470)`, across the tower toward the wall at x ≈ +105. In frame: the
   dark storm-cloud masses, the storm deck below, rain streaks, and **a lightning bolt** (every 6-12 s: hold
   the shot and take a burst). The tower's neon exit platform glows against the dark.
5. **"Doors under the stars" — the observatory, floor 9.** Session A. Avatar on `ForkPad_9` (−48.2, 217.2,
   617.8), fork unread. Camera low behind the avatar, `(−48, 219, 598)` looking at `(−40, 250, 660)`. In frame:
   both unread doors against a sky of 4 000 stars, the floating star lanterns on the walls, **the ringed planet**
   and **the constellation** (five joined stars); a shooting star if one crosses (take a burst). **The planets
   turn slowly around the whole sky** (one turn in about 26 minutes of play, counted from when the client
   started), so where they are depends on how long the session has run: at start the ringed planet is at
   (+520, +170, +700) from the camera, which for a camera looking along +Z (up the climb) is ahead and to the
   LEFT (in Roblox, looking along +Z, screen-right is −X), and the constellation (x −340 to −90) is ahead-right;
   by floor 9 they have usually moved 40-70° round. Before framing, pan with the normal camera to find the ringed planet, the
   constellation and the moon (angular size 26), then set the Scriptable camera so the doors are low in frame
   and the planet is in the upper third; the camera position above is the starting point, change only the
   look-at target.
6. **"Stjernekronen" — the summit.** Session A. Reach the summit; the Build Reveal card pops up. Close it for
   the clean frame (or keep it for a HUD variant). Avatar on the summit pad (−9.2, 309, 882) beside the golden
   plinth. Camera `(8, 318, 866)` looking at `(−9.2, 311, 882)`, slightly above. In frame: **the crown of ten
   gold stars circling the avatar**, the plinth's glow and `👑 TOPPEN` billboard, stardust, the deepest bloom.
   For the wide variant, camera `(−9, 360, 840)` looking at `(−9, 300, 900)`: the avatar small on the pad and
   **the spiral galaxy far below** (it rides 520 studs below and 260 ahead of the camera).

---

## 12. Not done / open

* **Reviewed once; the fixes are not re-reviewed.** An independent adversarial review (2026-09-24) found
  three things, all closed (§14). The fixes had their own failing tests first, a mutation sweep and every
  gate, not a second reviewer; the captain-mode default is a review before anything ships.
* **Found by this session's new check, not fixed** (Studio list items 22-24): hazards approaching from behind
  the inscription on a landscape phone; the server's toast over the character's head there for 3.5 s after
  each notice; the inscription's edge over the crown of a tall avatar's head on a 640x300 phone. All three
  are the pre-existing HUD, measured and reported, not changed.
* **Not seen in Studio**: all of §10, and the shot list itself (§11) has only been checked headless: the
  positions were re-measured, the place builds with `rojo build` (Ambience lands as a LocalScript in
  StarterPlayerScripts), and both sessions' Config edits pass validation.
* **`luau-analyze` and `luau-compile` were not run.** They are not on this machine (searched 2026-09-24:
  the scratchpad's `luau/` holds only `luau.exe`, nothing on PATH). Every file was compile-checked through
  `luau`'s own `loadstring` instead: 39 of 39 (17 sources, 15 test files, 7 checks). Type analysis is owed.
* **Hazards per minute rest on the human model** (`Config.Pacing`), not telemetry.
* **No progress across runs.** Every run walks the same six bands and a rebirth starts the dungeon again;
  there is no long-term environment goal like +1 Jump's galaxy. A cosmetic one would be easy and safe
  (driven by the public `Rebirths` leaderstat, e.g. one more star in the summit's crown per rebirth, or a
  rarer crown at 5 / 10 / 25 rebirths), but it is a design decision for Gustav, so it is not built.
* **The template's `setWeight` pop-in** (a hidden part coming back at its old transparency) is fixed in
  `TowerArt` only. +1 Jump's `SkyArt` still has it (read 2026-09-24: its hide resets `lastT` and not
  `Transparency`, and a re-show at a small weight moves `t` by 0.02, under its write threshold). Not
  touched here: another game's directory.
* The server's red hazard cubes and preset are unchanged (§10 items 14-15).
* Not committed, not pushed, not published.

---

## 13. The resume session (2026-09-24)

The first session stopped mid-sweep (20 of its 40 mutations run, both placeholders in this file). Nothing
was taken on trust: every new and changed file was re-read (Climb, Config, TowerArt, Ambience.client,
the Hud diff, the three new specs, PlayModel, the three checks), the template copies were md5-compared
with +1 Jump's (EnvBands, Hazards, Rest and their specs: identical), the bundle was rebuilt (byte-identical
to the one on disk), every gate was run, and the two environment checks were run 12 more times each.

**What it found, and what was done:**

1. **`check_forktower_env_secret` was flaky, twice over.**
   * **C** compared two snapshots ~9 s apart, and the storm's lightning lifts the colour correction's
     Brightness for ~0.7 s after each bolt: 1 run in 12 failed at floor 8 on the unchanged tree
     (`C -0.015` against the storm's `-0.020`). Proof, by a stress probe with the storm's lightning set
     to every 2-2.5 s in memory: the old check failed 8 runs of 8, the fixed one passed 8 of 8. Fix: each
     snapshot is taken under a quiet sky (no bolt for 1.5 s; bounded, and asserted so C cannot pass by not
     looking). In 20 stability runs right after the fix, 7 had to wait for one (up to 1.6 s over the run).
   * **D**'s coverage assertion (`swept > 100`) counted what happened to be parented at the end, which
     depends on random critters: 70 and 100 in the first sweep, 100 in the stress probe. Fix: D sweeps
     everything the ambience made during the run, parented or pooled (355 instances in every run), and
     asserts by name that it reached every band's walls, far pieces, critters, weather and lightning. That
     also closes a real gap: pooled, unparented parts were never swept at all.
   * So the first sweep's kills credited to this check were partly the flake (G8 "the lantern never
     lights" and G10 at floors 7-8, G7 and G11 by the count). The whole sweep was re-run on the final tree
     (§9); every one of those is killed there by the check that is meant to kill it.
2. **A typo in a Config.Env name deleted scenery silently.** Ambience guards every lookup (a broken config
   costs the polish, never the game), so `"planet"` for `"planets"` removes the observatory's planets and
   `"rains"` for `"rain"` stops the storm's rain, and no suite noticed (K7 and K8 survived every suite as
   they stood; §9). EnvConfig.spec cannot see it because TowerArt needs Roblox's `Enum` to load. New
   assertion in `check_forktower_env`: every piece, critter, weather and hazard name Config.Env gives
   TowerArt is one it can build.
3. **The join card's wait for the profile was untested.** `check_forktower_env` joins a fresh player whose
   load is instant, so a card that did not wait (G16) survived. New `check_forktower_env_join` (37
   assertions): real saves made by climbing to floor 7 and leaving, then rejoins whose `UpdateAsync` yields
   16 s, 40 s and 0.1 s, and a new player with a 16 s load. Each gets exactly one card, after the load,
   naming their band.
4. **TowerArt's hide-then-show rule was untested** (T1 survived the first full re-run). §2 cites it as the
   fix for a measured pop-in: TowerArt hides a part by unparenting it and writes `Transparency = 1`, so a
   part shown again at a small weight comes back invisible and fades in. Deleting that write changed
   nothing any suite saw, because Ambience smooths every band weight, so in the integrated run a piece is
   always nearly transparent by the time it is hidden, and because `check_forktower_env` switched its
   no-cut watch off after the first rebirth, before any piece is shown a second time. Now held twice:
   * a direct TowerArt probe in `check_forktower_env` (show the far blooms at weight 1, hide at once,
     show at 0.015: every part must come back at most 5 % opaque);
   * the no-cut/pop-in watch now stays on through the second and third runs: every band shown again,
     hazards, a knock and its fall, rest.

   Keeping the watch on found something (item 6).
5. **TowerArt's weather cap was untested** (T5 survived). In this game at most two bands overlap, so the
   run never asks for more than two kinds or 40 particles/s and a TowerArt that ignored the cap passed.
   Now a probe asks it for all five kinds at full rate at once: at most `MaxWeatherEmitters` switch on and
   the summed rate stays within `MaxEmitterRate`.
6. **A camera teleport makes far wall parts vanish in one frame.** With the watch on after the rebirth,
   124-134 wall parts jumped from partly visible to invisible in one frame on the check's simulated knock
   (the root moved 90 studs down, then the server's rescue moved it back), plus up to 60 more on the
   check's own backward teleports (back to platform 2 after a knock). The wall grid keeps a fixed window of
   cells around the camera. When the camera jumps further than its fade can follow, a row that is still
   partly visible leaves the window and is re-placed, invisible, in the same frame. Only a teleport does
   this: the door choice onto a section, the fall rescue, a rebirth, a join. It happens at the edge of the
   grid (100-140 studs out) in the frame where the whole view cuts anyway. The first run, whose teleports
   only go forward as climbing does, has none.

   Doing better needs double-buffered wall slots, which doubles the part budget, so it was **not
   changed**. It is written down instead:
   * teleport frames (the camera moving more than 8 studs in 1/30 s; a full-speed fall is ~5.5) are left
     out of the second watch's no-cut rule, never out of its pop-in rule;
   * they are counted (56 of about 18 600 frames in each of 40 final runs), and required to stay under 2 %;
   * the effect is on the Studio list (§10 item 19).
7. **The HUD's open panels were never measured, and on a landscape phone they were 1 px tall.** H2 (the
   side panels start ON the ambience row) survived. `check_forktower_hud` runs hudcheck with the drawers
   closed and the Build Reveal card hidden, and in that state no side panel can meet the centred row. So
   the new `check_forktower_hud_open` opens each drawer through its real toggle, and shows the card, at
   all ten hudcheck viewports. It went red at once. On 800x360 and 640x300 (landscape, how most phone
   players hold a phone), the ambience row had taken the only vertical room there was:
   * the menu drawer (Skip, **Rebirth**, the code box) and the leaderboard drawer were 1 px tall;
   * the summit's Build Reveal card was 1 px tall, with its close button drawn above it.

   Before the row, the same HUD gave 35 px (800x360) and 1 px (640x300): too small already. Measured by
   running the new check on the HUD as committed at HEAD: 10 real failures, plus 3 that only apply once
   the row exists.

   The fix is in `Hud.client` and is compact-only, so portrait phones and larger screens are unchanged:
   * a phone drawer clears only the parts of the centred stack (inscription, toast, ambience row) whose
     columns it shares, so on a landscape phone it hangs from under its toggle;
   * a drawer ends above the touch controls whatever the clamped `bandBottom` says (on 640x300 that clamp
     carried it into the thumbstick);
   * when there is no usable room under the stack, the card takes the free column right of the stack. It
     is still never over the inscription (a rebirth taken with the card open lands on a live fork), the
     counter, a toggle or the row.

   Result:

   | panel, open | 800x360 before the row | with the row | fixed | 640x300 before / with / fixed |
   |---|---|---|---|---|
   | menu drawer | 35 px | 1 px | 135 px | 1 / 1 / 95 px |
   | leaderboard drawer | 35 px | 1 px | 135 px | 1 / 1 / 95 px |
   | Build Reveal card | 35 px | 1 px | 135 px | 1 / 1 / 95 px |

   `check_forktower_hud_open`: 157 / 0 on the final tree. The new layout rules are mutation-tested in §9
   (H3-H7 and control C4).
8. **Dead code**: Ambience's 15 s settle timeout could never fire (it counted under the same condition as
   the 1.5 s settle). Removed rather than made live, with the reason in the source (§2, "At a join").
9. **The shot list had four errors**, all fixed in §11: the planets were placed "upper right", but that
   piece turns about the camera (one turn in ~26 min), so by floor 9 they have moved 40-70°, and at the
   start they are on the LEFT anyway (looking along +Z, screen-right is −X, which also made "right-hand
   wall" the wrong wall in shots 2 and 4); shot 3's "tilt the camera up ~15°" would put the clock face in the
   middle of the frame, not the upper third; shot 3 named no platform and did not say the clockwork can send
   a bird instead of a cog. The positions were re-measured on the final bundle (identical) and the place
   was built with `rojo build` to prove step 1.
10. **Small doc fixes**: the neighbour's corridor starts 145 studs from the lane's centre line, not 147; the
    budgets in §7 are now ranges over many runs (they vary by a few parts with the random critters), and
    the trails reach their budget of 6 in 4 runs of 40 (it said 5).
11. **`check_forktower_env` had a rarer flake of its own**, found by the sweep's closing run and by one
    before-side verdict (§9). The hazard clock is never reset, and the check's first run climbs ~72.5 s of
    sections against a first interval rolled at 70-110 s. About one run in sixteen (1 of 16 measured), a
    hazard came due inside the first run, so the next was 70-110 s away when part 5 started expecting one
    "within IntervalMax + 1 s" of climbing the garden. Six assertions then failed together.

    Forced (the first interval rolled at 60 s), it failed 3 runs of 3. The fix is part 5's dungeon climb:
    140 s instead of 40. A hazard that comes due in a quiet band is re-rolled on the current (8-9 s)
    interval, so any interval left pending from the first run expires in the dungeon. Forced, it now passes
    3 of 3, and 40 of 40 ordinary runs pass.

**Files written in the resume session:**
* in `fork-tower/`: `src/client/Ambience.client.luau` (the dead timeout), `src/client/Hud.client.luau` (the
  phone drawers and the card, item 7), `EYECANDY.md`, `CLAUDE.md`, `README.md`;
* in `robloxemu/`: `check_forktower_env.luau` (the Config-name assertion, the TowerArt probes, the second
  watch), `check_forktower_env_secret.luau` (C and D), `check_forktower_hud.luau` (comment only), the new
  `check_forktower_env_join.luau` and `check_forktower_hud_open.luau`, and the rebuilt `build/fork-tower.luau`.

Nothing else: `robloxemu/emu`, `tools`, `docs`, every `marketing` folder and the other games were not
touched, and nothing was committed. Probes, sweeps and logs are in the scratchpad under `ft_resume/`.

---

## 14. The adversarial review and its fixes (2026-09-24)

An independent reviewer rebuilt the bundle from source, reproduced every count in §8, and found three
things. Each was **reproduced first** on the tree as the resume session left it (bundle md5
`e3e48a53905b2bd512c6160fa378a756`), then held by a test that **went red on that tree**, then fixed in the
game, never in the test. Every gate is green on the final tree (§8; bundle md5
`dd38fa7eeb2f8a1e6a3b045974627b28`), and `Fork.luau`, `Main.server.luau`, `Fork.spec`,
`check_forktower.luau` and `check_forktower_plansecret.luau` are byte-identical to the session's start.

### Finding 1 (medium): the band chip and ☕ Hvil sat over the player's own character on a landscape phone

**Reproduced.** The reviewer's own probe on the session-start bundle: at 800x360, 640x300, 844x390 and
926x428 the chip and the button stood at y 178..222 in the middle 35 % of the width. The harness draws the
HUD 36 × (1 − scale) px too high under a UIScale (it scales the topbar inset too; Roblox pins the scaled
root at the inset), so on a real phone they sit at y 192..236. Roblox's default camera draws the
character's focus (root + 1.5 studs) at the centre, y 180 on 800x360: the row covered the character from
head to waist, and the reviewer's projection put the hazard strike point behind it in 400 of 400 launches.

**The test** (`robloxemu/check_forktower_hud_play.luau`, new, 324 assertions). It projects the character
through the default camera (focus root + 1.5, 12.5-stud zoom, 70° FOV over the full viewport height; a
generous R15 box from the feet, 3 studs below the root, to 2.5 above it, 4 across, 2 deep) and the widest
hazard ring at its feet (2 × (hitRadius + PlayerRadius) = 6.8 studs), at pitches −30, −15 and 0, at the ten
hudcheck viewports plus 844x390, 926x428 and 1280x720, with every rect corrected for the inset.
* **A**: nothing that stays up in ordinary play (every shown panel with the drawers closed, the chip and the
  button; not the toast or the Build Reveal card) overlaps the character or the ring.
* **C**: the chip keeps at least 130 px of width (the longest warning in two lines) and a thumb's height.

On the session-start tree it failed 242 / 72.

One pre-existing overlap is **named, bounded and reported, not exempted**: on 640x300 the inscription
panel (HEAD's layout, the one the reviewer took as the baseline) ends at y 138 and crosses the top 7-11 px
of the generous box (the crown of a tall avatar's head; 0-8 px for a bare R15 head). It may not sit lower
than HEAD; nothing the environment work draws has any exception (Studio list item 24).

**The fix** (`Hud.client.luau`). `PLAY_TOP = 0.42`: nothing that stays up may end below 42 % of the
viewport in the middle of the screen (head top at the default zoom: ~44 %). Where the centred stack
(inscription, toast, ambience row) would, the row goes up into the header, the one band that is sky at
any pitch. It goes to the right of the counter if the counter can stay centred and the chip still gets
130 px; otherwise the counter moves beside the ☰ Meny toggle, and the row takes the rest of the header up
to 🏆 Topp. In the header the row is the header's height, so on a mouse-driven phone window the chip is
32 px tall, not 20. That is every landscape phone and nothing else hudcheck measures. Portrait phones,
tablets, laptops and monitors are unchanged. The drawers and the Build Reveal card no longer count the
row as part of the centred stack when it is in the header.

| viewport | before (real px) | after |
|---|---|---|
| 800x360 | chip + button y 192..236, x 259..541 | header y 43..88, x 265..696; counter x 104..260 |
| 640x300 | the same | header y 43..88, x 265..536 (chip 154 px); counter x 104..260 |
| 844x390 | the same | header y 43..88, x 265..740; counter x 104..260 |
| 926x428 | the same | header y 43..88, x 546..822; counter centred |
| 800x360 (mouse) | y 156..176 | header y 43..76, x 483..733; counter centred |

**The reviewer's metric, before and after** (their projection model, 400 launches, corrected rects):

| 800x360 | hazard strike point hidden | flight frames behind the HUD | last second mostly hidden |
|---|---|---|---|
| pitch −30 | 400 → **0** | 79 % → 74 % | 188 → 157 |
| pitch −15 | 400 → **0** | 68 % → 64 % | 155 → 146 |
| pitch 0 | 400 → **0** | 49 % → 31 % | 145 → 60 |

After the fix, what still hides the flight is the inscription panel alone. It is pre-existing and
centred just above the character. The strike point, the ring, the chip's warning and the lane stay
visible. This is not changed: it is the game's central panel and a design call (Studio list item 22).
The same numbers on 844x390: strike point 400 → 0 at every pitch; flight hidden 65/58/51 % → 62/51/23 %.

### Finding 2 (low): a read begun on the exit platform's edge could be knocked mid-hold

**Reproduced.** The reviewer's probe on the session-start bundle: a seed pod launched on the platform
before the exit; the player landed on the exit (the server built fork 4); stood on its front edge, 13.2
studs from the LES prompt's part (its `MaxActivationDistance` is 16, the gap to the pad 2 studs) and
outside the sanctuary; and held LES 0.6 s after the lane locked. They were knocked **1.03 s into the 1.10 s
hold** (the reviewer saw 0.97 s). `Climb.gate` dismissed a hazard in flight only on a pad, and clearing a
floor stopped new launches but not the one flying. `check_forktower_env` always walked the reader onto the
pad first, so it could not see this.

**The tests.**
* `Climb.spec`: the floor cleared (not climbing), off any pad: dismiss, and no hit; the truth table now
  requires `dismiss = sanctuary or not climbing` and `hit = climbing and not sanctuary`. 64 / 3 on the old
  gate.
* `check_forktower_env`, three blocks:
  * the reviewer's scenario through the real client: the hazard must be gone within a frame of fork 4
    existing, and a read begun on the exit's edge (asserted in the prompt's reach and off the pad) must see
    nothing fly, no knock, and complete in `ReadSeconds` of server time;
  * a pad dismissal while still climbing, so the old pad rule stays covered on its own;
  * at all ten floor clears of a run, the ambience must see the new floor within one frame of the next fork
    existing. The 4 Hz lane scan lagged 0-4 frames (0,0,2,4,0,4,2,0,0,0).

  All three failed on the session-start tree.

**The fix.**
* `Climb.gate`: `dismiss = sanctuary or not climbing`, `hit = climbing and not sanctuary`. Clearing the floor
  ends the climb and what it launched. Rest is not "not climbing", so rest still never dismisses a hazard
  (§4).
* `Ambience.client`: anything added to the player's own lane (`DescendantAdded`: the next fork, the summit, a
  section) flags a scan on the very next frame; only the fact of the arrival is used. The reviewer's probe
  now gives, 5 runs of 5: nothing in flight on the exit, no knock.
* `tests/Pacing.spec` is byte-identical in output: its model already moved the player from the exit
  straight onto the pad, which is why it never saw the window.

### Finding 3 (low): the band title card covered the lower middle of a landscape phone

**Reproduced.** The reviewer's probe: the card hung under the row at y 228..322 on 800x360 (90 % of the
height), off the bottom of 640x300 (107 %), and over both open drawers on 414x800. The new check found one
more that no one had reported: on a 1366x768 laptop, a 1024x768 tablet and a 1280x720 window the card
(y 286-422) covered the character's head too.

**The tests.**
* `check_forktower_hud_play` part **B** shows the card (as Ambience does) at all 13 viewports. It must be on
  screen below the topbar and clear of the character and the ring. It must never cover the inscription,
  the counter, the toast's slot (the floor-clear notice comes with it), a toggle, the ☕ button, or either
  drawer opened through its toggle; where it covers the chip at all, it must lie inside the chip. Its title
  must be at least 18 px tall.
* `check_forktower_env` stages a hazard warning that starts while a card is up. The clock is made due while
  floor 4 is climbed in the air; floor 4's exit brings the clockwork's card; a guessed door on floor 5
  launches the waiting hazard. The card must be gone in the frame the chip warns. It stayed for 88 frames on
  the old code.

**The fix.**
* `Hud.client` places a `CardSlot` under the row. The slot goes in the strip between the centred stack and
  `PLAY_TOP`, kept out of the side panels' and drawers' columns, when that strip is at least 48 px tall
  and 160 px wide. That is 470x84 on a 1920x1080 monitor, 184x51 px on a portrait phone and 294x53 px on a
  small window. Otherwise the slot covers exactly the chip for the card's 3.8 s: on landscape phones, the
  laptop, the tablet and a 1280x720 window.
* `Ambience.client` puts the title and its line on a dark plate in that slot, and **a hazard warning ends the
  card**, because on the chip it would hide the warning.
* `check_forktower_env` and `check_forktower_env_join` look the card up recursively now that it sits in the
  slot. That is a path change, not a weaker assertion.

### Mutation sweep of the fixes: 17 of 17 killed, 4 of 4 controls survived

Same driver as §9 (`ft_rev1/sweep/sweep.py`): a scratch copy verified file for file against the real tree
(41 files), exactly one replacement per mutation, and the rebuilt bundle proven to equal the baseline plus
that replacement. Every suite runs (12 specs, `world.check` and the 8 `check_forktower*`), then the file is
restored and md5-checked; after the last one every suite was green on the restored copy.

| id | mutation | killed by |
|---|---|---|
| R1 | Climb.gate: dismissed only on a pad | Climb.spec, env |
| R2 | Climb.gate: may hit once the floor is cleared | Climb.spec |
| R3 | Ambience: a lane arrival never flags a rescan | env (floor-clear lag, dismissal) |
| R4 | Ambience: the frame ignores the rescan flag | env |
| R5 | Ambience: dismisses on a pad only | env |
| P1 | Hud: `PLAY_TOP` ignored | hud_play |
| P2 | Hud: the counter never moves aside | hud_play |
| P3 | Hud: the header row placed under the header | hud, hud_open, hud_play |
| P4 | Hud: the header row keeps the small height | hud_play (12 px title) |
| P5 | Hud: the chip may shrink to 20 px | hud_play (96 px chip) |
| P6 | Hud: in the header, the band forgets the toast | hud_open, hud_play |
| T1 | Hud: the card never gets the strip | hud_play (12 px title) |
| T2 | Hud: the strip not kept out of the drawers' columns | hud_play |
| T3 | Hud: the strip ignores the play area | hud_play |
| T4 | Hud: the card on the chip covers the ☕ button too | hud_play |
| T5 | Ambience: a warning does not end the card | env |
| T6 | Ambience: the card ignores the HUD's slot | hud_play |
| K1 | CONTROL: the strip card 4 design px taller | survived |
| K2 | CONTROL: the card's plate a shade lighter | survived |
| K3 | CONTROL: the lane scan at 5 Hz instead of 4 | survived |
| K4 | CONTROL: the chip's minimum 130 → 140 px | survived |

**Files written in the review-fix session:**
* in `fork-tower/`: `src/shared/Climb.luau` (the gate), `src/client/Ambience.client.luau` (the rescan,
  the card's slot and plate, a warning ends the card), `src/client/Hud.client.luau` (`PLAY_TOP`, the
  header row, the card slot), `tests/Climb.spec.luau`, `EYECANDY.md`, `CLAUDE.md`, `README.md`;
* in `robloxemu/`: the new `check_forktower_hud_play.luau`, `check_forktower_env.luau` (three new blocks,
  the recursive card lookup), `check_forktower_env_join.luau` (the recursive card lookup), and the
  rebuilt `build/fork-tower.luau`.

Nothing else: `robloxemu/emu`, `tools`, `docs`, every `marketing` folder and the other games were not
touched, nothing was committed, pushed or published, and Studio was not opened. Probes, logs and the
sweep are in the scratchpad under `ft_rev1/`.
