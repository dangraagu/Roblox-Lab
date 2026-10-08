# Nightwatch Manor — the nights escalate

Owner's brief (Gustav, 2026-09-17): every game visibly richer and never monotonous, with the environment changing as
the player progresses, in that game's own logic; rare knock-down hazards (about one near-hit per 2-3 minutes, easy to
see coming and avoid); a way to rest that can never become an exploit; a thumbnail shot list for the night Studio
session. For this game specifically: the visuals must not hide the Nightwatcher unfairly, reveal it unfairly, or
change the chase balance that was tuned by hand (an ambushed runner is never caught; a player who ignores it is caught
on 19 of 30 nights).

**State: built, unit-tested, headless-tested through the real server + HUD + client, mutation-tested, and through two
independent adversarial reviews: review 4 (2026-09-24, four findings, §14) and the second review (2026-09-30, eight
findings, §15). Every finding is closed test-first. The owner's open decisions were taken on 2026-09-30 ("take the
recommended option for all", §13). Re-run on 2026-10-01 after the run was cut off: every finding reproduced again on
the committed code and checked on this tree, every gate twice (§8, §15). Pass 2 the same day (§16): the NIGHTS
SURVIVED board, secret manors, the exit's guard, the bands moved to keep the brag moment in 30-45 minutes; 40 of 40
gates twice. NOT seen in Studio.**
Nothing was committed, pushed or published. Two earlier attempts were cut off by a usage limit. The resume session
re-read every file, re-ran every gate, and found a red gate, four defects in the game code and several holes in the
tests (§10). Review 4 then found four more (§14): hazards far more often than the brief once counted honestly,
lightning faster than its own anti-strobe rule, ghosts in the exit's green, and a wrong statement of what the client
writes.

**In one paragraph.** The progress value is **the night you are on**: the night the server credits you with, the
same number the HUD shows. It moves one whole step each time you get out alive. Being caught or evicted never moves
it. Inside a night it is nudged forward by the night's **dread**, so the manor visibly wakes up as the clock runs
down. It drives six looks: 🌙 Quiet Night → 🌫️ The Mist Rises → 🌧️ Rain on the Glass → ⛈️ Thunderstorm → 🩸 Blood Moon
→ 🕯️ The Witching Hour. What changes:
* **Windows** on the manor's outer walls. Each is a closed picture box on the inside of a solid wall, with a sky, a
  moon, stars, a treeline, mist, rain on the glass, lightning and swaying curtains. The moon turns blood-red at night
  26 and goes into eclipse with a pale corona at night 50 (20 and 40 until 2026-10-01: §16).
* **Portraits** whose eyes follow you and glow more every band.
* **Candles and fixtures** that flicker harder as the night wears on, and **dust** in the air.
* **The safehouse** grows cosier as you buy upgrades. The hearth is kindled, then an armchair, bookshelf and candles
  appear, then a sleeping cat, a garland and a painting, and last a second armchair and a plant. Its two windows look
  across the grounds at the manor, where a figure passes behind a lit window.

**Hazards** (bats, a will-o'-wisp, flying crockery, a wraith) are ghosts: they come through the walls. A close call
(a pass within 8 studs of a player who reads the ring) comes about every 2.6-2.9 minutes in the manor, for every kind
of player; a hazard is shown every 90-130 s of night. Each comes with 3 s of warning and a ring on the floor, it can
only knock you down after its lane has locked, and none flies while the Nightwatcher is hunting you. **Rest** is the
safehouse between nights: sit by the fire as long as you like, and no lightning flashes while you do. The night never
pauses, so rest is never offered inside it. **Fewer flashes:** Roblox's own Reduced Motion setting, or the ⚡ toggle
next to ☕ Rest, turns every flash off: lightning, a knock's screen flash, the blinking warning, and the HUD's own
flashes when you are caught or evicted.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from `plus1-jump` (identical bytes). Progress → band + eased blend, `approach`, `capRates`. Pure. |
| `src/shared/Rest.luau` | **template, verbatim** (identical bytes). The rest state machine. Pure. |
| `src/shared/Hazards.luau` | **template + five additions**, each pinned in `tests/Hazards.spec.luau`: `ElevationMin/Max` (a lane starts inside the room's height band, never out of the floor); `ctx.paused` (freeze the clock: it is day, or the night has just ended); `ctx.held` (review 4: the clock runs but a due hazard waits, for the Nightwatcher's hunt); `Hazards.cancel` (call off the hazard in flight with no hit, schedule untouched); `Hazards.threatLive` (second review: can the rest of the flight still hit anyone in the ring? the ring and the warning stay up that long; the same function +1 Jump's copy gained). |
| `src/shared/Calm.luau` | **new (2026-09-30), client only.** "Fewer flashes": Roblox's Reduced Motion setting OR the in-game ⚡ toggle, one switch read by both client scripts. |
| `src/shared/Nightfall.luau` | **new, pure,** this game's own rules: `progress` (night + dread × lookahead, never time), `bandIndex`, `chipText`, `outerFaces` / `windowPlacement` (windows on outer walls only), `flicker` (bounded, with a hard floor), `boltGap` (real seconds between lightning flashes, never under 4) and `blink` (at most 2 a second), `fairness` (the visibility envelope + the no-decoy rule for the Nightwatcher's colours AND the exit's, §5), `hazardClock` / `hazardGate` / `validateHazards` (the chase rules for hazards), `leadAim`, `validateRest` / `restAllowed` (rest is DAY only), `cosyTier`, `pupil`. |
| `src/shared/HauntArt.luau` | **new, client only.** Builds and pools every local part: windows, portraits, dust and rain hosts, the lightning light and bolt, the safehouse props and windows, the hazard models, lane and ring. |
| `src/client/Haunt.client.luau` | **new, the glue.** State → progress → bands → lighting (10 Hz, glided, inside the fairness gate) → windows, portraits, flicker, weather, lightning → the safehouse → rest → hazards → chip, Rest button, warning banner, title cards. Reads Roblox's Reduced Motion setting live. |
| `src/shared/Config.luau` | + `Env` (6 bands, windows, cosiness tiers, the watcher's and the exit's light colours for the fairness rule, the ghosts' colour, the blink rate), `Hazards`, `Rest`, `Budget`, `Pacing` (the model's human assumptions). All cosmetic, and the server reads none of it. |
| `src/server/Main.server.luau`, `src/client/Hud.client.luau` | untouched by the eye candy: everything the client needs was already in the State push (`phase`, `night`, `dread`, `spotted`, `hubLevel`). The second review changed two things (§15): `saveProfile` writes only while the record carries this session's token, and the HUD's CAUGHT / EVICTED / EXTRACTED / SPOTTED effects obey `Calm`. |
| `tests/` | `EnvBands.spec`, `Rest.spec` (verbatim from the template), `Hazards.spec` (template + the four additions), `Nightfall.spec`, `EnvConfig.spec` (the shipped numbers checked against every rule), `Pacing.spec` + `NightModel.luau` (minutes of play, measured rarity, the chase with and without hazards). |
| `robloxemu/check_nightwatchmanor_*.luau` | `kit` (shared boot, not a check), `haunt` (the whole glue), `hazards`, `join` (a slow profile load), `layout` (the new UI around the HUD, 19 viewports, and whether its text can be read), `rest`, `budget` (the worst case), `fairgate` (hostile configs), `flash` (review 4: lightning gaps, blink rates, Reduced Motion; since 2026-09-30 the ⚡ toggle and the HUD's flashes); new with the second review: `sitdrop` (the Studio trace of a sit's drop), `save` (the session lock's owner token), `caps` (the budgets held in code at 50 parts / 1 light). |

---

## 2. The bands and what triggers them

**Trigger: the night number, never time.** `Nightfall.progress = night + dread × 0.9` while a night runs, and `night`
in the safehouse. The night is `State.night`, which only the server's `Night.resolve` moves, and only on an
EXTRACTED outcome. So:

* **Surviving a night** is the only thing that moves you a whole step.
* **A catch or an eviction** puts the look back where the night started, gliding back within about 2 s.
* **Dread foreshadows the next band.** Each band fades in over the 0.9 of the night before it (`fade = 0.9`,
  smoothstep), so on the last night of a band the manor turns into the next one as the dread rises. The name on the
  chip and the title card still go by the whole night number.

**Transitions never cut.** Every blended value glides on a 0.7 s half-life, and Lighting is written at most 10×/s
and only when a value moved. Measured through the real client over 39 real extractions: the largest single-frame
change was **3/255** on a tint channel and **0.0018** in fog density (gates: ≤ 4/255, ≤ 0.004). Every band defines
every key (`EnvConfig.spec`). A key only one side of a blend has would snap at the halfway point, not glide.

**Band 1 IS the server's `Fx.Presets.Horror`**, number for number (`check_nightwatchmanor_haunt` §1), so the client
takes over without a step. A returning player's first frames are the server's preset, and then the look glides to
their night once their profile has loaded (`check_nightwatchmanor_join`: a 20 s load shows no chip, no card and no
band change until it lands, then one quiet card).

Minutes = minutes of PLAY (day and night) to the band's first night, from `tests/Pacing.spec.luau`. It plays the
game's real rules forward (`NightModel.luau`, §3) with the human costs written down in `Config.Pacing`: *normal* takes
every relic it can and leaves at dread 0.6; *fast* is quicker at everything; *slow* takes at most 3 relics and leaves
at dread 0.45.

| # | band | nights | windows show | in the room | lightning (real seconds between flashes: dread 0 / full dread) | hazards | normal | fast | slow |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌙 Quiet Night | 1-2 | a pale full moon, **stars**, a thin mist | dust 3/s, candles barely flicker, curtains stir (2°), the portraits' eyes faint | none | none (a new player learns the manor first) | 0 | 0 | 0 |
| 2 | 🌫️ The Mist Rises | 3-5 | the mist climbs the glass (0.75), clouds veil the moon, a few stars | dust 5/s, flicker 0.4, sway 4° | none | bats | 1.4 | 1.1 | 2.0 |
| 3 | 🌧️ Rain on the Glass | 6-9 | rain runs down the nearest window (28 drops/s), no stars | flicker 0.5, sway 6° | **sheet lightning**, 18-34 s / 9-17 s: the glass blinks and the room is lit from the window | bats, will-o'-wisp | 7.1 | 3.3 | 16.9 |
| 4 | ⛈️ Thunderstorm | 10-25 | heavy rain (44/s), full cloud, a smaller moon | flicker 0.7, curtains billow (10°) | **forked lightning**, 6-14 s / 4-7 s, a bolt drawn in the glass | flying crockery, bats | 17.2 | 13.7 | 20.6 |
| 5 | 🩸 Blood Moon | 26-49 | a huge **blood-red moon** on a crimson sky, stars back | dust 6/s, flicker 0.8, the portraits' eyes burn amber (0.85) | bolts, 14-26 s / 7-13 s | wraith, flying crockery | **43.9** | 32.5 | 35.0 |
| 6 | 🕯️ The Witching Hour | 50+ | **total eclipse**: a black moon with a pale corona on a green-black sky, rain, mist | dust 7/s, the deepest flicker, sway 12°, eyes at full glow | bolts, 5-11 s / 4-5.5 s | all four | 94.6 | 78.9 | 66.5 |

(One session per profile, the model's seed, on the PUBLIC manors (the model's old game). Re-measured 2026-10-01 after
the Blood Moon moved from night 20 to 26 and the Witching Hour from 40 to 50 (§16). On the salted manors the game now
plays, 31 first-time normal players reach the Blood Moon after a median of **33.5** minutes and the Witching Hour after
**66.8**: the numbers asserted, below.)

* **Lightning comes more often as dread rises, and never faster than one flash per 4 s.** Each gap is rolled in REAL
  seconds by `Nightfall.boltGap`: the band's own range, divided by (1 + dread), and never under
  `Nightfall.HARD.FlashGapMin` = 4 s whatever the band or dread asks. (Before review 4 the client ran its countdown at
  (1 + dread) × real time, so the Witching Hour's "every 5-11 s" came to every 2.7 s at high dread; §14.) Measured
  through the real client on a whole night-53 Witching Hour night (night 43 before the bands moved) up to dread 0.97:
  19 flashes in 109 s, the closest two 4.03 s apart.
* **No lightning while you rest** by the fire (seated or dozing), and none at all with Roblox's Reduced Motion setting
  on. A strike that falls due then is silent: the gap is kept, nothing flashes.
* Candle flicker deepens with dread on top of the band's own amount (`FlickerDreadGain 0.6`). The headless check
  measured a flicker range of 0.13-0.17 early in a night (dread about 0.2) and 0.30 at dread 0.88.
* Curtain sway grows 60 % at full dread.
* Dust rises 50 % at full dread.
* The portraits' eyes glow +0.4 at full dread.

**The flagship milestone is the Blood Moon (night 26).** The brief's target is 30-45 minutes. `Pacing.spec` measures
it on POPULATIONS, not one trajectory: 31 normal players, each 0-30 s slower to get their bearings every night. **The
game as it ships (2026-10-01): first-time players on SALTED manors** (each player's own salt per night; a retry is the
same manor, remembered, until the third failure shifts it; Main.server, §16): the Blood Moon at 26.4-49.2 min, median
**33.5**, quartiles 30.4 / 39.1, **23 of 31 inside 30-45**; nobody needed more than 9 attempts at one night. Median in
30-45, at least half inside, at most 12 attempts at any night and every player at the last band inside 200 minutes are
asserted. The two older populations, on the public manors nobody plays any more, are still asserted too: the model's
player who knows each layout (median 44.4, 16 of 31 inside) and the first-time player (median 40.5, 23 of 31). Before
the bands moved, salted first-timers saw the Blood Moon (then night 20) at a median of 25.8 min, 10 of 31 inside: the
public manors of nights 1-20 had been harder than the average manor. It is also the one band that is celebrated: a
fanfare card "🩸 THE BLOOD MOON RISES" with a flash and an FOV punch, shown back in the safehouse after the server's own
"YOU GOT OUT" toast. **The Witching Hour (night 50) is the long-term goal**: on the salted population a median of
**66.8 min** (54.3-92.5), asserted at least 1.6× the flagship's median and inside 3 hours, and on the single public
session at least 1.6× too. Beyond it, the NIGHTS SURVIVED board has no last night. Every band lasts long enough to be a
place, not a flicker (asserted: ≥ 1 min for the first, ≥ 3 min for the rest).

**Why "slow" gets to the Blood Moon sooner than "normal".** The night advances when you get out, whatever you are
carrying. The cautious profile takes three relics and leaves at dread 0.45, so it gets caught less and its nights are
shorter. The greedy one ends richer and a band later. That is the existing game's rule, not something the visuals
added. **DECIDED 2026-09-30 (owner: take recommended): it stays** (§13). Leaving early is a strategy with a price, not
an exploit: every night is still a full crossing to the deepest room, and the cautious player reaches the Blood Moon
with hub level 18 against the greedy one's 29 (medians of 11 players each, night 26; asserted: at least 5 lower; 14 and
24 when the Blood Moon was night 20).

**Chip** (a row under the HUD's help line; on phones it stacks up from the bottom centre, between Roblox's thumbstick
and jump button): `🌫️ The Mist Rises · Night 4 · 🌧️ in 2`. The last band has no "next". While resting:
`☕ Resting by the fire · the manor waits`. Since the second review it wraps onto two lines and is never narrower
than 170 screen px on a phone: by day, when the ⚡ and ☕ Rest buttons would squeeze it, they move to their own line
above it (the line the hazard warning uses at night), and on a phone held upright the whole stack sits above the
touch controls at the width of the screen. Estimated headless (no text renders): the smallest chip or warning text on
any of 19 viewports is 12.0 px (the tablet's day chip, 157 x 44 px, beside both buttons; on phones 14.5 px); every one
is at least 11 px (measured 2026-10-01, three runs identical; this said 13.8 before the ⚡ toggle took its width).

**The safehouse grows cosier by hub level**, which is the sum of upgrade levels, max 30, and is already in the State
push:

| tier | hub level | adds |
|---|---|---|
| Bare Shelter | 0 | a cold stone hearth and mantel |
| Hearth Kindled | 2 | the fire (with its own light and embers), a rug |
| Homely | 6 | a velvet armchair by the fire, a bookshelf, two candles on the mantel |
| Cosy | 12 | a sleeping cat on the hearth, a garland of warm lights over the mantel, a painting |
| Haven | 20 | a second armchair, a potted plant, and a bigger fire |

Every prop stands clear of the upgrade pads, the spawn pad and the way to the manor door (asserted on the rotated
extents of every prop at the cosiest tier). At night the props are unparented: no draw calls 400 studs away.

---

## 3. Hazards and their measured rarity

**What they are.** Four ghostly things, taken from the manor itself. Walls do not stop them, which is why they can
come at you in a sealed room:

| kind | bands | model | speed | warning | locked for | ring | knock | starts |
|---|---|---|---|---|---|---|---|---|
| 🦇 bats | mist, rain, storm, witching | 5 flapping bats | 18 studs/s | 3.3 s | 1.5 s | 7.6 studs across | 14 studs/s | 59 studs out |
| ✨ will-o'-wisp | rain, witching | a violet ghost-light with a halo | 12 | 3.6 | 1.7 | 7.2 | 10 | 43 |
| 🍽️ flying crockery | storm, blood, witching | three spinning plates and a cup | 22 | 3.2 | 1.4 | 7.4 | 15 | 70 |
| 👻 wraith | blood, witching | a pale shroud with violet eyes | 26 | 3.2 | 1.4 | 8.0 | 16 | 83 |

The ghosts' glow (`Config.Env.Glow.ghost` / `ghostHalo`, a violet ghost-light) used to be a hard-coded green
(120, 255, 140), 35 from the Servants' Exit's light. It now lives in Config, where the fairness rule checks it against
the exit's colour as well as the Nightwatcher's (§5).

**How a hazard plays** (the template's rules, kept):
* It launches on screen, at most 35° either side of where your camera looks, and inside the room's height band.
* It re-aims at you while the warning runs: an ⚠️ marker over it that shows through walls, an amber light blinking
  twice a second, a lane line, a banner (`⚠️ WRAITH INCOMING ▲`, with an arrow toward it) and a **ring on the floor**
  where it will land.
* For its last 1.4-1.7 s the lane **locks**, the marker blinks (twice a second; it was three times before review 4),
  and the banner says `⚠️ DODGE THE RING! WRAITH ◀`. With Reduced Motion on, the light and marker hold steady.
* The ring IS the hit rule. Step out of it in any direction and it misses. Stay in it and you are knocked down
  (`PlatformStand` for 0.8 s) and pushed sideways, never up, always slower than walking.
* **The ring and the banner stay up while a hit can still land** (`Hazards.threatLive`, second review). They used to go
  at the arrival time, but the lane is aimed up to `AimJitter` from the ring's centre, so a player on the far side of
  the ring was knocked down a frame or two after both had gone (through the client: 6 of 8 such players).
* **A knock only from the earliest-hit time on** (`Nightfall.hitFrom`: arrival minus reach over the kind's speed, which
  is after the lock and at least 3 s into the warning). Before it, the ring still follows you and cannot be stepped out
  of: walking up to a slow will-o'-wisp and stopping in its path knocked 8 of 8 players down 1.5-2 s early, with the
  banner still saying INCOMING. Now the ghost passes through, and only a player still standing in the LOCKED ring
  when that time comes is knocked down (8 of 8, all after the DODGE banner, the soonest 3.33 s into the warning).
* It takes nothing: relics, dread and the night are the server's, and the server never hears of a hazard.
* The warning covers the **earliest** hit, not the arrival. `Nightfall.validateHazards` requires
  telegraph − (hitRadius + PlayerRadius) / speed ≥ 3 s for every kind: bats 3.09, wisp 3.30, crockery 3.03,
  wraith 3.05.

**The chase rules** (`Nightfall.hazardClock`, `validateHazards`, and the client):
1. **One hazard every 90-130 s of night** (`IntervalMin/Max`; 120-180 until the second review), the ring half a second
   ahead of a walker (`LeadSeconds` 0.5; it was 1.0). The clock is **frozen** outside the night: in the
   safehouse, in the 2.5 s beat after a night ends, and before the profile loads.
2. While the Nightwatcher sees you, and for `QuietAfterSpottedSeconds` = 10 s after it last saw you, the clock keeps
   running but the launch is **held**: nothing launches into a chase (10 s is longer than its 7 s hunt, validated as
   "hunt + 1 s at least"). A hazard that falls due meanwhile launches the moment the quiet window closes: one hazard,
   never a backlog, and never two closer than 90 s. Review 4 found that the old rule, a clock FROZEN while hunted,
   made hazards come more often per minute in the manor the better a player hid (§14). **DECIDED 2026-09-30 (owner:
   take recommended): the clock stays held** (§13).
3. The moment it sees you, a hazard in flight is **called off** (no hit), and a knock **ends** that frame.
4. A knock is capped at 0.8 × WalkSpeed, and `KnockLift` is 0. There is nothing to fall off in a manor, and a knock
   is never a speed boost.
5. The clock is never reset. Neither a night ending, nor a chase, nor resting can thin hazards out or bunch them up.

**Measured rarity** (`Pacing.spec`, 200 minutes of play per profile and seed, three hazard seeds pooled, hazards on).
The owner's standard (`docs/complete-game-standard.md` §2) asks for **about one near-miss per 2-3 minutes**. Since the
second review that is the asserted number: a **near-miss** is a pass within 8 studs of a player who reads the ring,
counted **per minute IN THE MANOR** (hazards never run in the safehouse, which is 10-36 % of play), for **every
profile**, and for a player who is rarely seen (the Nightwatcher's sight cut to 30 studs in memory). Every hazard
SHOWN (near-misses, wide passes, and those called off by a sighting) must stay rare: one per 1.5-3 manor-minutes. Also
asserted: the shown rate does not depend on how often it sees you (within 15 %).

| player | minutes in the manor (of ~600 played) | hunted | hazards shown | one per | near-misses within 8 studs | one per (per seed) | called off |
|---|---|---|---|---|---|---|---|
| normal | 489 | 55 % | 251 | 1.95 manor-min | 179 | **2.73** (2.78 / 2.70 / 2.71) | 77 |
| fast | 520 | 53 % | 259 | 2.01 | 183 | **2.84** (2.68 / 2.88 / 2.99) | 63 |
| slow | 377 | 48 % | 195 | 1.93 | 133 | **2.83** (3.07 / 2.53 / 2.95) | 40 |
| stealthy (sight 30) | 467 | 22 % | 237 | 1.97 | 172 | **2.72** (2.74 / 2.68 / 2.73) | 26 |

(Re-measured 2026-10-01 after the Blood Moon moved to night 26: nights 20-25 now fly the Thunderstorm's crockery and
bats instead of the wraith. Before: 2.63 / 2.86 / 2.72 / 2.68, shown 1.92-2.00. Measured on the public manors the
model's single sessions play; not re-measured on salted manors.)

| also measured | result |
|---|---|
| hits on a player who steps out of the ring | **0** in all twelve sessions (asserted) |
| hits on a player who ignores every warning | 5 in 162 manor-min, **one per 32.5 manor-min**, 4.5 s knocked down in all (asserted: at most one per 5, and more than 0, else the ring is decoration). Before the earliest-hit rule it was one per 16.2: a walker who keeps going is now past before the hit window opens |
| the second review's count, reproduced (120-180 s, the ring 1 s ahead) | near-misses one per **4.67** (normal), 4.54 (fast), 5.59 (slow), 4.51 (stealthy) manor-minutes, pooled; the single session the reviewer measured: 5.07 / 4.72 / 6.52 / 4.74. That was the finding. |
| the same count under review 4's old rule (frozen clock) | normal profile: 137 hazards, one per **1.18 manor-min**; stealthy stand-in: one per **0.74**. |

**Through the real client** (`check_nightwatchmanor_hazards`, interval cut to 6-8 s in memory on a night-12 player):
* A minute in the safehouse launches nothing.
* A hazard launches on the band's kinds only, one at a time, with its warning showing from the first frame.
* The ring is centred where you stand and exactly as wide as the hit rule.
* Standing still: knocked down after ≥ 3 s of warning, pushed sideways slower than walking, never lifted, back up
  after 0.8 s.
* **Walking out of the ring in each of 8 compass directions: 8 of 8 dodged.**
* Standing still at the spot inside the ring the hazard reaches LAST (found from the drawn lane and ring): 12 of 12
  hit, 7-9 of them after their arrival time, and **the ring and the banner still up on every hit frame** (before the
  fix: the ring already gone on 6 of 8, the banner on 2).
* Walking straight at a will-o'-wisp while its ring follows you and stopping in its path: **no knock before the DODGE
  banner or before 3 s of warning** (before the fix: 8 of 8, at 1.83-1.90 s).
* The Nightwatcher seeing you removes the hazard at once. It never hits, and the next one waits ≥ 10 s after the
  sighting. Then it comes **at once**, 10.03 s after it lost you, because the clock ran through the chase and the
  hazard was already due. A frozen clock would still have owed at least 3 s; the old rule measured 16.5 s.
* A knocked-down player is back on their feet the first frame after it sees them.
* A night ended 4 s after a launch resumed, next night, after **2.8-3.2 s** of night (two runs). That is the
  remainder, not 0 (a clock that ran in the day) and not 6-8 (a reset).

### The chase is untouched (measured)

`NightModel.simulate` is Chase.spec's night simulation, and `Pacing.spec` first proves the copy reproduces Chase.spec's
own numbers (0 of 20, 19 of 30, 5 of 30). It then plays the same nights with the shipped hazards, and with a
**stress** config that launches one every 3-5 s of night, for a player who **ignores every warning** (the worst case).
With the held clock the stress case is also the "a hazard the moment every chase ends" case. The model calls
`Nightfall.hazardClock` exactly as the client does. **A knock is modelled as a push**: the full knock speed for the
whole 0.8 s, through Chase.spec's walls. That is the worst case, because friction in Roblox can only shorten it. It
averaged 9.5 studs per hit, at most 12.8.

| player | nights | caught, no hazards | caught, shipped hazards | caught, stress (3-5 s) |
|---|---|---|---|---|
| ambushed runner | 1-20 | 0 | **0** (2 hazards, 1 hit) | **0** (12 hazards, 8 hits) |
| ambushed runner, full Bear Traps | 1-20 | 0 | **0** (1 hazard, 1 hit) | **0** (8 hazards, 7 hits) |
| wandering runner | 1-20 | 0 | **0** (19 hazards, 16 hits) | **0** (355 hazards, 324 hits) |
| greedy looter ignoring the watcher | 1-30 | 19 | **19** (3 hazards, 0 hits) | **19** (58 hazards, 0 hits) |
| exit walker ignoring the watcher | 1-30 | 5 | **5** (1 hazard, 0 hits) | **5** (29 hazards, 0 hits) |

(Re-measured 2026-09-30 with 90-130 s, the 0.5 s lead and the earliest-hit rule. A knock averages 9.4 studs of push.)

Asserted:
* The shipped hazards change no catch count: runners stay at 0, and the others are within 1.
* The stress moves them by at most 2.
* **No hit ever lands while it is hunting you** (seen, or within the quiet window after): 0.
* **No player is still knocked down on a tick it sees them**: 0.

---

## 4. Rest — what "pause" means in Nightwatch Manor

A Roblox server cannot pause the world for one player, and **this game's loop is a timed round**. A night is a race
against DREAD with a hunter in it, and the whole design, from the upgrade economy to the chase tuning and the best
night on the leaderboard, depends on that clock. Freezing it for one player would be exactly the exploit the brief
rules out. So rest lives where the brief says it may: **between rounds**.

* **The safehouse is the break room.** Nothing runs there. The day has no timer, and the next night only starts when
  you walk through the manor door. The game already paused between rounds; rest makes that visible and comfortable.
* **☕ Rest** (next to the band chip, a 44-px tap target on phones) sits your character down by the fire, softens the
  view (its own depth-of-field effect, never the server's), and the chip says
  `☕ Resting by the fire · the manor waits`. The button reads **▶ Up**. Press it, or move or jump, to get up.
* **The sit survives its own drop** (second review, 2026-09-30, HIGH). A Humanoid sat down without a seat falls onto
  the floor for about 0.3 s (vy -3 .. -26 studs/s, a bounce, FloorMaterial Air throughout; measured in real Studio in
  +1 Jump on 2026-09-27). The client counted "seated and |vy| ≥ 2" as falling, so in Roblox the ☕ Rest button stood
  you straight back up. The first `SIT_SETTLE_SECONDS` (1.0) after a sit now count as supported; a sustained fall while
  seated still ends the rest. `check_nightwatchmanor_sitdrop` replays the Studio trace frame by frame: seated on 1 of
  120 frames before the fix, 120 of 120 after, for a pressed rest and for a queued one.
* **Idle**: stand still in the safehouse for 45 s and you doze (`💤 Dozing by the fire`), for AFK comfort. It does
  not sit you down, and any movement or ▶ Up wakes you.
* **Rest is quiet.** While you sit or doze, no lightning flashes the windows or the room; the rain goes on. Review 4
  measured 21 flashes in 180 s of rest by the fire on night 43; `check_nightwatchmanor_rest` now counts 4 flashes while
  up and about on night 7 (Rain on the Glass) and **0 in 302 s of rest**.
* **Inside the manor there is no rest at all**: no button, no idle doze, and pressing a stale button does nothing.
  Walking into the manor ends rest and its soft focus: the chase is played in the server's own view.
* Roblox's own idle disconnect (about 20 minutes) still applies. Nothing is lost: progress autosaves every 20 s and
  on leaving.

**Why it cannot be exploited:**
1. **Nothing to dodge.** Rest exists only where no clock, hunter or penalty runs. It pauses nothing the server runs,
   and the server never hears of it (the client fires no remote; asserted across every check).
2. **It cannot reach into the round.** `Nightfall.validateRest` rejects a config with `Phases.NIGHT`, and the client
   refuses to offer rest at all under such a config. `check_nightwatchmanor_fairgate -a rest` boots the real client
   with `NIGHT = true` in memory: a warning, no button in the safehouse either, no doze, and none at night.
3. **Nothing carries across.** A phase change ends any rest, so you never start a night seated or blurred, and the
   night starts with its full dread clock as always.
4. **Nothing earned, nothing lost.** Five simulated minutes of rest:
   * the night, relics, best night and upgrades the server **saved** during them (it autosaves every 20 s) are exactly
     what it loaded;
   * and the day is still the day (`check_nightwatchmanor_rest`).
5. **The template's guard rails stay on.** `Rest.validate` refuses `WakeOnMove = false` (you could move while resting)
   and `BlockWhileThreat = false` (a panic button). There are no threats in the day, but a future change cannot quietly
   drop the rule.
6. **Hazards are not thinned by it either.** The hazard clock is frozen in the day whether you rest or not, and never
   reset. The template's rest-toggle probe shows 142 hazards per 6 h of play whether you never rest, toggle every 7 s,
   or rest 40 s of every 150 s (`Hazards.spec`).

---

## 5. Fair to the chase: never hide it, never reveal it, never change it

The Nightwatcher is the whole game, and the chase was tuned under the server's `Fx.Presets.Horror`. Five rules,
enforced in code:

1. **A visibility envelope.** Every band's fog, haze, exposure, ambient, grade brightness and contrast stay within a
   hard envelope around the preset (`Nightfall.HARD`):
   * atmosphere density ≤ 0.45 (preset 0.42);
   * haze ≤ 2.0 (1.6);
   * exposure ≥ −0.25 (−0.15);
   * ambient luma ≥ 18 (21.8);
   * grade brightness ≥ −0.05 (−0.02);
   * contrast ≤ 0.30 (0.18).

   No band tints the whole screen red (red/green ≤ 1.12): the Nightwatcher's eyes are red. No band crushes a colour
   channel. A config may tighten the envelope, never loosen it.
2. **No decoys, for the hunter or for the way out.** No cosmetic glow may be within 60 (RGB distance) of the
   Nightwatcher's own two light colours, its red head light (255,70,70) and its pale lamp (150,200,210), **nor of the
   Servants' Exit's green light (120,220,140)**, the one cue a player hunts for under dread (review 4).
   `Config.Env.WatcherSignature` and `Config.Env.ExitSignature` hold them, and the haunt check asserts they ARE the
   colours the server builds (the Nightwatcher's two lights; the ExitLamp, its light and the ExitDoor's light). Checked
   two ways:
   * **statically**, on every glow colour in the config (`Nightfall.fairness`), which now includes the ghosts' colour;
   * **on every frame of the worst case**, on every Neon part, point light and particle the client actually
     parents (`check_nightwatchmanor_budget`). That includes the hard-coded colours no config rule sees: the hazard
     models, the stars, the distant manor's lit windows and the bolt. The closest any of them came is **66.1** to the
     Nightwatcher's lamp and **81.4** to the exit's green (both the Witching Hour's dust).

   This measurement found three violations, all fixed: the rain on the glass at **43** from the lamp and the window
   glass during a lightning fade at **32** (§10), and the will-o'-wisp and the wraith's eyes at **35** from the exit's
   green (review 4, §14). Before review 4 the scan checked only the Nightwatcher's colours, so the ghosts passed it.

   **One exemption, reported rather than asserted:** the three pieces of window glass whose colour glides with the
   band (sky, moon, corona). They are a picture on the wall behind a frame, not a light in the room, and their steady
   colours are the band colours the static rule already checks. But while a look glides between bands, a pale moon
   fading to a dark one passes near the grey axis, and the lamp's (150,200,210) sits 45 from that axis. Measured:
   **60.3** at the closest to the lamp, **102.4** to the exit's green.
3. **Flicker is never a blackout.** Room lights flicker between 0.78 and 1.22 of what the server built (a hard floor of
   0.75 inside `Nightfall.flicker`, whatever the caller asks for), and average out at the server's brightness. The
   lightning boost to the grade is +0.12 for 0.12 s, with a hard cap of 0.15.
4. **Nothing strobes, and every flash can be turned off** (review 4):
   * two lightning flashes are never closer than **4 s** of real time (`Nightfall.HARD.FlashGapMin`, applied by
     `Nightfall.boltGap` whatever the band or the dread asks; the worst case asks for 0.3 s and gets 4.00);
   * a hazard's amber light and its locked marker blink at most **twice a second** (`HARD.BlinkHzMax`; the marker
     blinked 3 times a second, which sampled at 30 fps came to 4 flashes in one second, past WCAG's three);
   * no lightning while resting;
   * **Roblox's own Reduced Motion setting** (`GuiService.ReducedMotionEnabled`, read every frame) turns off every
     flash of ours: no lightning at all, no screen flash or shake on a knock or the Blood Moon card, and the hazard's
     warning light and marker hold steady. The rain, the windows and the rest of the band stay.
     `check_nightwatchmanor_flash -a calm` plays a whole night-43 night with it on (0 flashes) and then switches it
     off in the safehouse (the lightning is back within 30 s). **The property's name is from the Roblox API as I know
     it and was not checked in Studio**: read through `pcall`, so an engine without it simply reads "off" (Studio
     list).
   * **The ⚡ toggle** (DECIDED 2026-09-30, §13), next to ☕ Rest in the safehouse: `⚡ On` / `⚡ Off`, for this session.
     `src/shared/Calm.luau` is the one switch (Reduced Motion OR the toggle) that both client scripts read, so the
     HUD's own effects obey it too: no red flash and shake when CAUGHT, no purple flash when EVICTED, no FOV punch on
     EXTRACTED, no shake when SPOTTED (the toasts still say what happened). Pressing it to turn flashes ON while
     Reduced Motion is on is refused with a card, `⚡ FLASHES STAY OFF`, that says why. `check_nightwatchmanor_flash`
     storm: ⚡ Off gives 30 s of the storm band without a strike (CONTROL: strikes before), no HUD flash on CAUGHT or
     EVICTED, no FOV punch; ⚡ On brings the lightning back. calm: the HUD flashes nothing and punches nothing.
5. **A broken rule costs the polish, never the game.** An unfair config switches the client's lighting OFF, and the
   lighting stays exactly the server's tuned preset; the windows, chip and hazards still run. An invalid hazard config
   switches hazards off. An invalid rest config switches rest off. Each warns once in F9, and
   `check_nightwatchmanor_fairgate` boots each case for real.

**Reveal.**
* Nothing the client draws depends on where the Nightwatcher is. The client never reads its position. The flicker
  and the portraits' eyes follow the camera and the player (asserted: the eyes do not move while the Nightwatcher
  walks and you stand still).
* The only watcher-related input is `spotted`, which the HUD already shows as "IT SEES YOU".
* Windows are closed boxes: nothing is ever seen through them (asserted: a solid, opaque, colliding server wall
  stands behind every window).
* A lightning flash lights the room from the window for 0.12 s. The Nightwatcher carries its own lights, so a flash
  shows nothing that was not already lit; whether it reads that way is on the Studio list.

**Balance.** §3's table: the shipped hazards move no catch count.

---

## 6. Client vs server, and why nothing leaks

| what | where | why |
|---|---|---|
| bands, lighting, windows, portraits, flicker, dust, rain, lightning, the safehouse props, chip, cards | **client** (`Haunt.client` + `HauntArt`) | cosmetic and per player: your manor follows *your* night. It costs the server nothing, and none of it is seen by other players. |
| hazards and the knock | **client** | a hazard only ever touches the local player, whose character physics the client owns. It awards, removes and records nothing. |
| rest | **client** | it pauses nothing the server runs |
| night, dread, relics, the Nightwatcher, the chase, upgrades, saves, leaderboard, spawn | **server** | authoritative, as before. The eye candy left `Main.server.luau` alone; the second review changed only `saveProfile` (a write lands only while the record carries this session's token, §15) |
| "fewer flashes" (Reduced Motion or the ⚡ toggle) | **client** (`Calm.luau`) | an accessibility choice for this screen only; nothing is saved or sent |

**Leak review.**
* **What the client reads:** the State push the HUD already shows (`phase`, `night`, `dread`, `spotted`, `hubLevel`);
  the Notice kinds EXTRACTED / CAUGHT / EVICTED (so no hazard starts in the 2.5 s beat after a night ends); its own
  character and camera; Config; and the parts of its **own** zone: room floors, portraits, room lights, the exit door
  and the safehouse floor. It never reads the Nightwatcher, the relics or another player's zone.
* **What the client writes.** (Review 4 found this list stated wrongly as "only the room lights' Brightness". It is
  corrected here and in `CLAUDE.md`, and asserted.)
  * **Its own parts**, only in its own `workspace.NightwatchLocal` folder. All of them are anchored, non-colliding,
    non-queryable and non-touchable (asserted on every frame of the worst case), and cast no shadow (asserted by the
    haunt check). Its own GUIs, and one effect of its own in Lighting, `NightwatchRestFocus`.
  * **In the server's manor**, only the `Brightness` of the room lights (flicker). The haunt check snapshots all 211
    server-built instances of the zone before the first client frame and finds **0 changed** apart from that.
  * **In Lighting** (this IS what the bands are): the bands' own keys on the Lighting service (Ambient,
    OutdoorAmbient, Brightness, ExposureCompensation) and on the three effects the server made for the Horror preset,
    `FxAtmosphere`, `FxBloom` and `FxColorCorrection`. Never `FxDoF` or any other key. Since the second review the
    haunt check hooks every ASSIGNMENT to Lighting and to each child the server made (the emulator's shared Instance
    metatable), so a write that is put back later is caught too: **1845 assignments to 17 keys over a session, 0 of them
    outside the bands** (a flash-time `FxDoF.FarIntensity = 0` put back after the flash is caught, §9 W1; the old
    end-state check let it pass). It also snapshots
    Lighting and its children before any client script runs, and after a whole session of every band finds **16
    keys changed, 0 of them outside the bands**, and exactly one child added (the rest focus). A future SERVER change
    to Lighting (a catch effect, say) would be overwritten by the client: put it in the bands, or extend that check
    on purpose.
  * **Its own character**: `Humanoid.Sit` (rest), `Humanoid.PlatformStand` and the root's `AssemblyLinearVelocity` (a
    knock). These are normal character state and may replicate like any movement (other players see you sit, or get
    shoved). The server reads none of them (`Main.server.luau` never mentions them).
* **What it sends:** nothing. No remote, no attribute (asserted: 0 server calls in every check).
* **Windows** go on outer walls only, so they tell you which walls have nothing behind them. You learn that from the
  manor's shape anyway, and it is how a real house works. The exit's wall never gets one.

**What other players see:** none of this. Everything is local to its owner. A knocked player's character does move,
because the client owns it, so others see that player shoved by nothing they can see (Studio list).

**Spawn order** (`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame, and
`check_nightwatch` (the spawn and join assertions) is green.

---

## 7. Budgets (measured, `check_nightwatchmanor_budget`)

Client-built only. The server's own manor is on top of this: 134 BaseParts for a 10-room manor, plus one PointLight
per room and the Nightwatcher's two lights.

**The worst case, built on purpose:**
* every upgrade maxed, so the cosiest safehouse (fire, embers, fire light, every prop);
* in memory only, every band flies **all four hazard kinds back to back** (interval 1 s, so one is always in flight)
  and asks for **lightning every 0.3-0.5 s** with a bolt. Since review 4 the client holds that to one flash per 4 s
  (asserted here: 51 strikes, the closest two 4.00 s apart), so the worst case has fewer bolt frames than before;
* the Thunderstorm asks for **90 drops/s of rain and 30 dust motes/s**, past the rate budget, so the client's own cap
  has to hold it;
* for each band, the night inside it whose manor has the **most Portrait Halls**, reached by real extractions; the
  safehouse by day, then every room the Nightwatcher is not near;
* every budget asserted on every frame: 3315 frames, a bolt on 128 of them, and a hazard in flight on 753 of the
  1114 manor-tour frames.

One run's peaks are below. They move by up to 4 parts between runs, depending on which hazard kind is in flight (the
bats are 5 parts, the wisp 2) and whether a bolt is drawn. Across five runs on the final tree the highest was **118
parts** (before review 4, when a bolt was in the glass on a third of all frames, it was 121). After the second review
(caps in code, below) one run peaked at 119 (blood, night 33); the table is that run.

| where | parts | emitters | particles/s | lights | windows | portraits | hazards |
|---|---|---|---|---|---|---|---|
| Quiet Night, day (n1) | 73 | 1 | 8 | 1 | 2 | 0 | 0 |
| Quiet Night, manor (n1) | 107 | 1 | 3 | 2 | 6 | 2 | 1 |
| Mist, day (n5) | 77 | 1 | 8 | 2 | 2 | 0 | 0 |
| Mist, manor (n5) | 110 | 1 | 5 | 2 | 6 | 2 | 1 |
| Rain, day (n8) | 78 | 2 | 36 | 2 | 2 | 0 | 0 |
| Rain, manor (n8) | 104 | 2 | 32 | 1 | 6 | 2 | 1 |
| Thunderstorm, day (n18, flooded) | 78 | 2 | **60** (capped) | 2 | 2 | 0 | 0 |
| Thunderstorm, manor (n18, flooded) | 117 | 2 | **60** (capped) | 2 | 6 | 3 | 1 |
| Blood Moon, day (n33) | 77 | 1 | 8 | 2 | 2 | 0 | 0 |
| Blood Moon, manor (n33) | **118** | 1 | 6 | 2 | 6 | 3 | 1 |
| Witching Hour, day (n43) | 78 | 2 | 42 | 2 | 2 | 0 | 0 |
| Witching Hour, manor (n43) | 108 | 2 | 41 | 2 | 6 | 3 | 1 |
| **budget** (`Config.Budget`) | **160** | **3** | **60** | **3** | **6** | **4** | **1** |

**The normal session** (`check_nightwatchmanor_haunt`: 39 real extractions, the manor toured, dread run up): peak
**109 parts, 2 emitters, 49 particles/s, 2 lights**. With the shipped bands the heaviest weather is the Thunderstorm's
44 drops/s of rain plus up to 10.5 dust motes/s, so the rate cap is never reached. `EnvConfig.spec` asserts that
rain + dust ≤ 60 in every band.

**By construction**, at night, per shown element:
* a window is 15 parts: frame, sky, 5 stars, corona, moon, treeline, mist, 2 mullions, 2 curtains;
* a portrait is 6: canvas, face, 2 eyes, 2 pupils;
* a hazard is at most 5 (the bats) + lane + ring;
* plus 6 hosts: dust, rain, flash, 3 bolt segments.

So at most 6 × 15 + 4 × 6 + 7 + 6 = **127 ≤ 160**. By day: 2 safehouse windows of 21 parts, 31 props and 5 hosts
= 78.

**How it stays cheap:**
* Windows and portraits are built the first time they come within 70 / 60 studs, and are **unparented** when out of
  range or past the cap (6 / 4); the nearest win. The pick is re-sorted 4×/s, not every frame.
* One model per hazard kind, and one lane and one ring shared by all of them.
* One dust host (the room you are in), one rain host (the nearest window), one lightning light and one 3-segment
  bolt.
* The weather goes through `EnvBands.capRates`: at most 2 weather emitters, and their sum is scaled to what the fire's
  embers leave of the 60/s budget.
* Rates are written down at once and up with 0.25 hysteresis, so an emitter never lags above its cap.
* Flicker writes a light only when it moves more than 0.01.
* Lighting is written ≤ 10×/s, only on change.
* The safehouse's props are unparented at night; the manor's windows and portraits are destroyed when the night ends.

These are part and emitter counts, not frame time; phone frame time is on the Studio list.

**Capped in code, not only measured** (second review, 2026-09-30: `MaxParts`, `MaxLights` and `MaxHazards` were read
by nothing in `src/`; the 118-part peak stayed under 160 only because of how the scene happened to be built):
* **parts**: `HauntArt` reserves the largest hazard model (the bats, 5) + lane + ring + the six hosts = 13, so a warning
  is never dropped for scenery, and gives windows, portraits and the safehouse's props and windows what is left of
  `MaxParts`, nearest (or lowest tier) first. What does not fit is not parented;
* **lights**: `HauntArt:capLights`, after every frame, keeps at most `MaxLights` on, in the order hazard warning,
  fire, lightning;
* **hazards**: one model at a time (`showHazard` hides any other), the scheduler flies one, and
  `Nightfall.validateHazards` switches hazards off below `MaxHazards` = 1.

`check_nightwatchmanor_caps` cuts the budget in memory to **50 parts and 1 light** on a maxed night-33 profile with
every hazard kind back to back and lightning every 0.3-0.5 s: over 490 frames the peak is 48 parts (31 by day: every
prop, no windows), 1 light, 1 hazard, and **the hazard and its ring are drawn on every one of the ~250 frames its
warning is up**. Before the caps the same run parented 115 parts (73 by day) and 2 lights, over the cut budget on all
490 frames. At the shipped 160 / 3 the worst case above is unchanged (peak 119 parts in one run).

---

## 8. Gates

Every gate for this game, on the final tree of pass 2 (2026-10-01), run **twice** with identical counts (the client
checks use unseeded randomness, and every manor is a new salt): **40 of 40 green**. The bundle
`robloxemu/build/nightwatch-manor.luau` was rebuilt from it before each run (md5 `d3f90f04…` both times; `6d9ac50c…`
after the second review), and so was `tests/build/`. The runner (`scratchpad/nwm_p2_1001/gates.sh`; the commands are in
CLAUDE.md under State) runs every `tests/*.spec.luau`, the three `tests/` checks, and every
`robloxemu/check_nightwatch*.luau` (the kit excluded) with `fairgate -a light|hazards|rest` and `flash -a storm|calm`,
and judges each process by its **exit code**, not its last line.

| suite | result | new or changed this work |
|---|---|---|
| `tests/Chase.spec` | 32 passed, 0 failed | |
| `tests/Manor.spec` | 86 / 0 | |
| `tests/Night.spec` | 64 / 0 | |
| `tests/Rng.spec` | 32 / 0 | |
| `tests/Upgrades.spec` | 99 / 0 | |
| `tests/Watcher.spec` | 87 / 0 | |
| `tests/responsive.spec` | 70 / 0 | |
| `tests/EnvBands.spec` | 124 / 0 | new (template) |
| `tests/Rest.spec` | 55 / 0 | new (template) |
| `tests/Hazards.spec` | **147** / 0 | new (template + additions); +12 in review 4 (`ctx.held`, held vs frozen); +9 in the second review (`threatLive`) |
| `tests/Nightfall.spec` | **185** / 0 | new; +42 in review 4 (`hazardClock`, `boltGap`, `blink`, the exit's colour); +15 in the second review (`MaxHazards`, `hitFrom`) |
| `tests/EnvConfig.spec` | **244** / 0 | new; +9 in review 4 (real lightning gaps, the exit's signature, the ghosts' colour) |
| `tests/Pacing.spec` | **62** / 0 | new; +10 in review 4; second review: near-misses 2-3 per manor-minute both ways pooled over 3 seeds, the Blood Moon on two populations of 31, the first-time player's CONTROL, the leave-early price (net +6); pass 2: the salted population (+7: its CONTROL, the brag window, the long-term goal, nobody stuck) |
| `tests/Salt.spec` | **31** / 0 | new in pass 2 (the server-only generator; salted manors keep every manor invariant; the public plan predicts nothing) |
| `tests/Crossing.spec` | **40** / 0 | new in pass 2 (the exit's guard: a lower bound on every legal walk, public and salted; the exit room; the verdict) |
| `tests/Board.spec` | **70** / 0 | new in pass 2 (the encoding and its tie-break, keep-higher, the public and friends views, the cache, the token bucket) |
| `tests/check_walk` | 62 / 0 | |
| `tests/check_world` | 38 / 0 | |
| `tests/check_boot_guard` control / fraction / walkspeed / saturated | 2 / 4 / 4 / 4, 0 failed | |
| `robloxemu/check_nightwatch` | **129** / 0 | pass 2: public layouts, the board's two parts, ESCAPE through the guard (+2) |
| `robloxemu/check_nightwatch_hud` | PASS (10 viewports) | |
| `robloxemu/check_nightwatchmanor_haunt` | **127** / 0 | new; +9 in review 4; +2 in the second review (every assignment to Lighting, not only the end state); pass 2: the tour to night 50 and a CONTROL that a Portrait Hall was visited (+1) |
| `robloxemu/check_nightwatchmanor_hazards` | **54** / 0 | new; +2 in review 4; +9 in the second review (4b the ring and banner until the hit window closes, 4c no knock before the lock) |
| `robloxemu/check_nightwatchmanor_join` | 25 / 0 | new |
| `robloxemu/check_nightwatchmanor_layout` | 7 / 0 | new; second review: 19 viewports and every chip / warning text readable (still one verdict assertion) |
| `robloxemu/check_nightwatchmanor_rest` | **41** / 0 | new; +3 in review 4 (no lightning while resting) |
| `robloxemu/check_nightwatchmanor_budget` | **32** / 0 | new; +4 in review 4 (the exit's colour on every frame; lightning never under 4 s) |
| `robloxemu/check_nightwatchmanor_caps` | **12** / 0 | new in the second review (50 parts / 1 light held in code) |
| `robloxemu/check_nightwatchmanor_fairgate` light / hazards / rest | **12** / 6 / 8, 0 failed | new; pass 2: the Blood Moon's first night pinned (+1) |
| `robloxemu/check_nightwatchmanor_flash` storm / calm | **31 / 27**, 0 failed | new in review 4; second review: the ⚡ toggle and the HUD's own flashes (+13 / +7) |
| `robloxemu/check_nightwatchmanor_save` | **67** / 0 | new in the second review (a save lands only while this session owns the record) |
| `robloxemu/check_nightwatchmanor_sitdrop` | **24** / 0 | new in the second review (the Studio trace of a sit's drop) |
| `robloxemu/check_nightwatchmanor_board` | **89** / 0 | new in pass 2 (the board in the world, the stored value and ties, writes only on a better night, the public list's cache and `GetSortedAsync(false, 10)`, friends on demand, empty boards, the 200 cap and the throttle, no stored names) |
| `robloxemu/check_nightwatchmanor_guard` | **64** / 0 | new in pass 2 (the halves only in ServerStorage, the manor is the salted plan, same manor on a retry until it shifts, new on a new night / session / player, `PublicLayouts`, the exit's guard) |

Totals:
* **specs: 1428 passed** (1280 before pass 2; 1250 before the second review; 470 before the eye candy);
* **headless: 114 in `tests/` + 755 in `robloxemu/`** (598 before pass 2), plus the HUD PASS;
* **40 suite runs, 0 failed anywhere**, twice.

Also:
* **Compile:** `luau-compile` and `luau-analyze` are not in this session's scratchpad (only `luau.exe`). All 57 Luau
  files were compiled with `loadstring` instead: 21 sources, 20 test files, 16 `check_nightwatch*`. **0 errors.**
  luau-analyze was not run.
* **Spawn order:** `check_nightwatch` (the join and spawn assertions from `robloxemu/SPAWN-ORDER.md`) is green, and
  `tests/check_walk` walks from the spawn pad past the new board to the manor door.
* **Untouched:** the other games, `robloxemu/emu`, `tools/`, `docs/` and every `marketing/` folder. The only files
  outside `nightwatch-manor/` written by this work are `robloxemu/check_nightwatch*.luau` and
  `robloxemu/build/nightwatch-manor.luau`.

---

## 9. Mutation sweep

(Pass 2's sweep, 29 mutants over the board, the salt, the guard and the salted pacing, is in §16.)

Driver: `sweep.py` in this session's scratchpad (`nwm_resume/`), logs `sweep.log` and `sweep_r2.log`, results in
`mut/results.json` and `mut/results_r2.json`. It never touches `D:\Claude\Roblox`:
* **Four worker copies.** Each copy of `nightwatch-manor/` and `robloxemu/` (emu, `wrap.py`, every
  `check_nightwatch*`) was verified **byte-identical** to the real tree first.
* **A green baseline on every worker** before any mutant. A red baseline reports every mutant as killed.
* **Per mutant:**
  - exactly one replacement (refused on 0 or more than 1 matches);
  - **all 30 gate runs**, judged by exit code;
  - then the **proof that it reached the bundle**: the rebuilt `robloxemu/build/nightwatch-manor.luau` must equal the
    worker's baseline bundle with that one file's text swapped for its mutated text, and nothing else;
  - then the original bytes restored and their md5 re-checked.
* **Afterwards:** the real tree's md5 is unchanged.

**Round 1** (38 mutants): 34 KILLED as expected; 3 controls SURVIVED as they must; **1 unexpected survivor, A1**,
closed below.

| id | mutant | killed by |
|---|---|---|
| C1 | CONTROL: the wraith's shroud a shade warmer | survived, as it must |
| C2 | CONTROL: the stars twinkle a touch slower | survived, as it must |
| C3 | CONTROL: the garland bulbs a shade deeper | survived, as it must |
| N1 | progress ignores dread | Nightfall.spec |
| N2 | the fog-density fairness rule off | Nightfall.spec |
| N3 | the no-decoy (watcher colour) rule off | Nightfall.spec |
| N4 | no quiet window after a sighting | Nightfall.spec, Pacing.spec, `hazards` |
| N5 | `validateRest` lets rest into the night | Nightfall.spec, `fairgate -a rest` |
| N6 | windows allowed on the exit's wall (pure rule) | Nightfall.spec |
| N7 | the flicker's hard floor removed | Nightfall.spec (the new "caller asks for 0.2" assertion) |
| H1 | `cancel` leaves the hazard flying | Hazards.spec, Pacing.spec, `hazards` |
| H2 | `paused` no longer freezes the clock | Hazards.spec, Pacing.spec, `hazards` |
| H3 | the room height clamp dropped | Hazards.spec |
| K1 | quiet window 10 → 5 s (shorter than the hunt) | EnvConfig.spec, Pacing.spec, and every client check (the client switches hazards off and warns) |
| K2 | Blood Moon at night 12 | Pacing.spec (30-45 min) |
| K3 | Blood Moon tints the screen red | EnvConfig.spec, and every client check (lighting off, warning) |
| K4 | hazards every 5-40 s instead of 25-40 | Pacing.spec (near-hits per 2-3 min) |
| K5 | rest allowed in the night | EnvConfig.spec, and every client check |
| K6 | flicker amplitude 0.22 → 0.4 | EnvConfig.spec, and every client check |
| K7 | the rain back to (190,200,225) | EnvConfig.spec, and every client check |
| G1 | a sighting does not call the hazard off | `hazards` |
| G2 | a sighting does not end the knock | `hazards` |
| G3 | the bands driven by time | `haunt`, `join`, `budget`, `fairgate -a light` |
| G4 | the hazard clock runs in the day and while hunted | `hazards` |
| G5 | entering the manor keeps you seated | `rest`, `hazards` |
| G6 | cards before the profile loads | `join` |
| G7 | the fairness gate ignored at load | `fairgate -a light` |
| A1 | a window on the exit's wall (the client passes no exit face) | **survived round 1**, see below |
| A2 | the dark-lightning bug put back | `budget` |
| A3 | no corona at the eclipse | `haunt` |
| A4 | the stars ignore the band | `haunt` |
| A5 | the eclipsed moon veiled by cloud | `haunt` |
| A6 | the portraits' eyes stare at a fixed point | `haunt` |
| A7 | client parts can be raycast | `haunt`, `budget` |
| A8 | the window cap ignored | `budget` |
| A9 | the weather cap bypassed | `budget` (only since the flood; before it this was invisible) |
| A10 | the embers not counted against the rate cap | `budget` |
| A11 | an emitter rate may lag above the cap | `budget` |

**A1, the survivor.** The haunt check read windows only from rooms the PLAYER toured, and the tour skips rooms near
the Nightwatcher. On night 1 it starts in the Servants' Exit, so the exit's own walls were never in view. Windows are
chosen by distance to the camera and the Nightwatcher only reacts to the character, so the check now moves the
**camera** through every room (12 distinct windows seen, all of night 1's outer faces). Proven in a scratch copy with
the mutant in the bundle: `no window is on the Servants' Exit's wall -> got 12, want 13`.

**Round 2** (7 mutants, the same driver on fresh verified copies with green baselines): A1 again, plus the
assertions added after round 1 started. **7 of 7 as expected**, the real tree untouched.

| id | mutant | killed by |
|---|---|---|
| A1 | a window on the exit's wall | `haunt` (the camera now visits every room) |
| C4 | CONTROL: the rest chip reworded ("the manor is waiting") | survived, as it must |
| P1 | a plant pot moved onto an upgrade pad | `haunt` (the pad clearance) |
| R1 | the ▶ Up button cannot wake a doze | `rest` |
| S1 | the will-o'-wisp in the lamp's colour (a hard-coded colour no config rule sees) | `budget` (the per-frame decoy scan) |
| S2 | the distant manor's lit window in the lamp's colour | `budget` |
| T1 | the model's knock stops instead of pushing (test side; nothing of it is in the bundle) | Pacing.spec |

**Totals: 45 mutants. 41 killed, 4 controls survived, 0 unexplained.** Every in-source mutant was proven to be in
the bundle the checks ran.

**Known equivalent under the shipped numbers, and why it is not in the table:** the lightning glass as a linear fade
instead of a blink. It is a visual choice, window glass is the documented exemption from the per-frame decoy scan
(§5), and no gate can tell the two apart.

**Round 3: review 4's fixes** (27 mutants; driver `scratchpad/nwm_r4/sweep4.py`, the same method as above: four
worker copies verified byte-identical to the real tree, a green baseline on each, all 32 gate runs per mutant judged
by exit code, the bundle proof, the original bytes restored and md5-checked, the real tree unchanged afterwards).
**23 killed as expected, 4 controls survived as they must, 0 unexpected.** Every in-source mutant was proven to be
in the bundle the checks ran.

| id | mutant | killed by |
|---|---|---|
| C5 | CONTROL: the wisp's halo a shade greener | survived, as it must |
| C6 | CONTROL: hazards up to 2 s sooner (IntervalMax 178) | survived, as it must |
| C7 | CONTROL: the exit rule's message reworded | survived, as it must |
| C8 | CONTROL: a knock's shake a touch softer | survived, as it must |
| F1a | `held` ignored: a due hazard launches into a chase | Hazards.spec, Pacing.spec, `hazards` |
| F1b | `held` freezes the clock (the old rule) | Hazards.spec, Pacing.spec, `hazards` |
| F1c | `hazardClock` freezes while it sees you | Nightfall.spec (the glue cannot tell: the 10 s quiet window that follows still runs the clock) |
| F1d | hazards back to every 25-180 s | Pacing.spec |
| F1e | the client freezes the clock while hunted | `hazards` |
| F1f | the client runs the clock in the day | `hazards` |
| F1g | the model freezes while hunted (test side; nothing of it is in the bundle) | Pacing.spec |
| F2a | no floor under the lightning gap | Nightfall.spec, EnvConfig.spec, `budget`, `flash -a storm` |
| F2b | the countdown runs at (1 + dread) again | `budget`, `flash -a storm` |
| F2c | lightning flashes while resting | `rest` |
| F2d | Reduced Motion ignored by the lightning | `flash -a calm` |
| F2e | Reduced Motion never read | `flash -a calm` |
| F2f | Reduced Motion read only at load | `flash -a calm` |
| F2g | the locked marker blinks 3 times a second again | `flash -a storm`, `flash -a calm` |
| F2h | the blink cap removed (pure rule; the shipped 2 Hz hides it at runtime) | Nightfall.spec |
| F2i | Reduced Motion: the warning still blinks | `flash -a calm` |
| F2j | Reduced Motion: a knock still flashes the screen | `flash -a calm` |
| F3a | the exit decoy rule off (pure rule) | Nightfall.spec |
| F3b | the wisp hard-coded in the exit's green again | `budget` (the per-frame scan; no config rule sees a hard-coded colour) |
| F3c | the ghost colour in the exit's green (config) | EnvConfig.spec, and every client check (the client switches its lighting off and warns) |
| F3d | the exit signature drifts from the built exit | `haunt` |
| F4a | the client stacks its own Lighting effects instead of taking over the server's | `haunt`, `join` |
| F4b | a lightning strike writes a Lighting key outside the bands | `haunt` |

**All three rounds: 72 mutants, 64 killed, 8 controls survived, 0 unexplained.**

**Round 4: the second review's fixes and the owner's decisions** (30 mutants, 2026-09-30; driver
`scratchpad/nwm_p1_0930/sweep.py`, the same method: three worker copies verified byte-identical to the real tree, a
green baseline of all 35 gate runs on each, exactly one replacement per mutant, both bundles rebuilt and **proven**: the
rebuilt bundle equals the baseline bundle with that one text swapped (a test-side mutant must leave it unchanged), the
gates judged by exit code, the original bytes restored and sha256-checked). **28 killed as expected, both controls
survived all 35 gate runs, 0 unexpected.** Every worker file sha256-identical to the real tree afterwards; the real
tree's sources, tests and checks were never touched (56 of 56 sha256-identical before and after; only CLAUDE.md and
this file were edited meanwhile). The driver crashed printing a ⚡ on a cp1252 console after 26 results; the last four
(D4, D5, C1, C2) were run again with UTF-8 output, same method. **Re-run 2026-10-01** on the same bytes
(`scratchpad/nwm_p1_1001/sweep.py`, UTF-8 output, all 30 in one run): 28 killed, both controls survived all 35 gate
runs, every mutant proven in the bundle (P4 proven absent from it), every worker file sha256-restored, the real tree
58 of 58 sha256-identical afterwards. The kill counts below moved with the unseeded `Random` (R1 6, R2 1, W1 x24).

| id | mutant | killed by |
|---|---|---|
| C1 | CONTROL: the ⚡ button a shade lighter | survived all 35, as it must |
| C2 | CONTROL: the lost-lock message reworded | survived all 35, as it must |
| S1 | no settle window after the sit (the shipped bug) | `sitdrop` (seated 1 of 120) |
| S2 | a queued rest never stamps its sit time | `sitdrop` (seated 1 of 120 after landing) |
| S3 | settle window 5 s: a real fall while seated no longer wakes you | `sitdrop` |
| L1 | the old save rule (write when the lock is nil or expired, whoever owns it) | `save` (night 5 written over night 9) |
| L2 | a lost lock never turns `canSave` off | `save` (told twice) |
| L3 | a lost lock is not told to the player | `save` |
| R1 | the ring and lane go at the arrival time again | `hazards` 4b (9 hits with the ring gone) |
| R2 | the banner goes at the arrival time again | `hazards` 4b (6) |
| R3 | `threatLive` ends at the arrival time (pure rule) | Hazards.spec, `hazards` |
| W1 | the reviewer's R4a: FxDoF.FarIntensity = 0 at each flash, put back after | `haunt` (24 assignments to FxDoF.FarIntensity) |
| B1 | no parts cap on scenery | `caps` (490 of 490 frames over) |
| B2 | no lights cap | `caps` (2 lights) |
| B3 | MaxHazards 0 accepted | Nightfall.spec |
| T1 | the chip does not wrap | `layout` (12 unreadable) |
| T2 | the chip is never stacked | `layout` (8) |
| T3 | the text cap not scaled by the UIScale | `layout` (30) |
| T4 | the warning one line tall again | `layout` (1) |
| P1 | the ring a whole second ahead again | Pacing.spec (a near-miss one per 3.39) |
| P2 | hazards every 120-180 s again | Pacing.spec (one per 3.12) |
| P3 | the Blood Moon at night 12 | Pacing.spec (both population medians) |
| P4 | the first-time player knows every room (test side; bundle unchanged, proven) | Pacing.spec (its CONTROL) |
| K1 | the hit test not clipped to the earliest-hit time | `hazards` 4c |
| K2 | `hitFrom` from the lane's slowed speed | Nightfall.spec, `hazards` 4c |
| D1 | the HUD's CAUGHT flash ignores "fewer flashes" | `flash -a storm`, `flash -a calm` |
| D2 | the ⚡ toggle does not toggle | `flash -a storm` |
| D3 | `Calm` ignores the toggle | `flash -a storm` |
| D4 | refusing to turn flashes on under Reduced Motion is silent | `flash -a calm` |
| D5 | everyone starts with 100000 relics | Pacing.spec: the leave-early price (hub 30 vs 30; checked by hand, the driver keeps the first three failures), and the Blood Moon medians |

**Known equivalent, not in the table:** releasing the lock as `nil` instead of `{ token, at = 0 }`. With the new save
rule the only difference is a SECOND releasing write of the same session (BindToClose, then PlayerRemoving), which is
then refused; the data it would have written is the data the first one wrote.

---

## 10. Found and fixed in this resume session

The two earlier attempts left the work uncommitted and, as it turned out, not finished. Everything below was found by
re-reading the files and running the gates, not by assuming the leftovers were right.

1. **A red gate: `check_nightwatchmanor_rest` (28 passed, 1 failed).** The check pressed Rest while the player was
   already dozing; the button then reads "▶ Up" and correctly woke them, so "still resting at the door" failed. It was
   the check's mistake, not the game's. The check now asserts the doze → ▶ Up → awake step and then sits down for the
   long rest. It also now reads what the server **saved** during the five minutes (via the DataStore), not only the
   last push: 38 passed.
2. **Lightning never lit the room after the first night.** `HauntArt:clearManor` did `self.flashLight.Parent = nil`,
   which detached the PointLight from its host instead of unparenting the host. The first `syncManor` (entering night
   1) orphaned it, so every later bolt was drawn dark. Found by the new budget check. It is now asserted: every frame
   with a bolt in the glass has the flash light on, night after night (every one of about 1,170-1,190 bolt frames per
   run). Watched failing first on 1163 frames.
3. **Rain in the Nightwatcher's lamp colour.** The rain particles were hard-coded (190,200,225), 43 from the lamp's
   (150,200,210). They are now `Config.Env.Glow.rain = (210,214,236)`: 66 away, and covered by the static rule too.
   The lightning's glass fade passed within 32 of it as well. Lightning is now a blink: the glass is the flash colour
   for the first 0.06 s and the sky after, and both ends are fair.
4. **The safehouse broke the particle budget in a heavy rain.** The weather cap held the rain at 60/s and the fire's
   embers added 8.1 on top: **68/s against 60**. The weather now gets what the embers leave, and emitter rates are
   written down at once (the 0.25 hysteresis had let a falling cap lag to 60.03). This was invisible with the shipped
   numbers, which is why the budget check now floods one band in memory: without that, deleting the cap passed every
   gate.
5. **Half-written looks.** `outside.stars`, `outside.eclipse` and `glow.corona` were in the config and drawn by
   nothing, so the Witching Hour's "eclipse" was a black disc on a black sky. The windows now draw 5 twinkling stars
   and a pale corona behind the moon, and an eclipsed moon stays a solid disc through the cloud veil. Every band now
   sets every key as a number, so the eclipse fades in instead of snapping.
   * While in there: the curtains covered 30 % of the window's width on each side and **hid half the moon** (and the
     distant manor's lit window and figure in the safehouse view). They are now 20 %, and the moon sits in the gap.
6. **The chase model treated a knock as a pause.** `NightModel` stood the player still for 0.8 s. The real client
   pushes them sideways at up to 16 studs/s. The model now pushes them (the upper bound), and the chase table in §3 is
   measured with it: the shipped numbers did not move, and the stress moved by 1.
7. **Flaky or missing assertions:**
   * The haunt check read a pupil from whichever Portrait Hall happened to be first in the folder (a neighbouring hall
     40 studs away is in range too), and it sampled the window sky during random lightning flashes. It now reads this
     hall's pupils and waits for a frame between flashes.
   * The flicker's hard floor was never exercised below the caller's own floor; now it is.
   * `Config.Budget` and `HauntArt` pointed at a budget check that did not exist; it exists now.
   * Nothing checked that the client's fairness, hazard and rest gates actually switch their part off: that is
     `check_nightwatchmanor_fairgate`.
   * Nothing checked that the cosy props stay off the pads; now something does.
8. **Dead config:** `Env.Window.Depth` was read by nothing; removed.

---

## 11. Needs Studio (only real rendering and a real device can judge)

1. **The bands' looks.** The grade stays inside a tight envelope on purpose (§5), so the bands differ mainly in the
   windows, the particles, the flicker and the tint. Is night 50 visibly a different place from night 1, or only a
   greener one? Does the Blood Moon's crimson read through a 7×6-stud window?
2. **Fairness at sight range.** In every band, can you see the Nightwatcher's red eyes and pale lamp across a
   40-stud room and at its 55-stud sight range as well as on night 1? The envelope allows +0.03 fog density and
   +0.3 haze over the preset.
3. **Windows.** Picture boxes on the wall, layered 0.008-0.02 studs apart: any z-fighting at 30+ studs on a phone?
   * Do the curtains' billow (a rotation about the top edge, up to 19° at full dread) look like cloth or a hinged
     board?
   * Stars are 0.18-stud squares: visible on a phone, or lost?
   * The eclipse corona (1.32× the moon) behind a black disc: an eclipse, or a donut?
4. **Lightning** (photosensitivity).
   * The glass blinks for 0.06 s, the room is lit from the window for 0.12 s (PointLight range 34, brightness 3, no
     shadows, so it also lights through walls into the next room), and the grade gets +0.12.
   * In the Witching Hour it comes every 5-11 s at dread 0 and every 4-5.5 s at full dread, never closer than 4 s
     (measured headless: 19 flashes in a 109 s night). Comfortable, or still too much?
   * **Reduced Motion.** Switch Roblox's *Settings → Reduced Motion* on in a storm band: every lightning flash, the
     knock's screen flash and shake, the Blood Moon card's flash and FOV punch should stop, and the hazard's amber
     light and marker should hold steady. The client reads `GuiService.ReducedMotionEnabled` through `pcall`; **if
     that property is not what Roblox calls it, nothing turns off** and no error shows. Check it first, and check it
     switches live, without rejoining.
   * An in-game "reduce flashing" toggle as well: DECIDED 2026-09-30 (owner: take recommended): built, the ⚡ toggle
     (§13).
5. **Flicker** (0.78-1.22 of the server's light): candlelight, or a broken bulb?
6. **Portraits' eyes**: a 0.14-stud pupil shift toward your head. Noticeable? Creepy enough? Too much?
7. **Hazards.**
   * Ghost models through walls: do they read as ghosts, or as clipping?
   * The ⚠️ marker is always on top: visible through walls from the far side of the room?
   * The ring is drawn 3 studs below the root part, on the floor: flush on a real character, or floating or buried?
   * The knock (`PlatformStand` 0.8 s at 10-16 studs/s): does the character stay upright or tumble? Does it stop at
     walls cleanly?
   * Other players see a knocked player shoved by nothing: glitch, or haunting?
   * **A hazard right after a chase** (review 4): the clock runs through a chase, so a hazard that fell due during
     it comes 10 s after the Nightwatcher loses you. Does that read as fair (you are out of danger, with 3 s of
     warning), or as piling on?
   * The warning blinks twice a second now (the locked marker was three times). Still urgent enough?
8. **The wraith** (pale shroud, violet eyes) next to the Nightwatcher (black body, red eyes, pale lamp): ever confused
   in a dark room? And the will-o'-wisp's violet orb (170,140,255) is 78 from the lamp's pale (150,200,210) in RGB:
   distinct on a real screen in a dark room, or not?
9. **The Witching Hour's green** grade, dust and eyes near the exit's green lamp: does the way out still read? (The
   ghosts are no longer green; the dust is 81 from the exit's colour, the eyes 93.)
10. **Rest**: `Humanoid.Sit = true` with no seat. Does it sit, and replicate? Does WASD produce `MoveDirection` while
    seated (that is what wakes)? The soft focus strength.
11. **The safehouse props**: a cat made of three balls and a tail, a Ball "plant", Neon garland bulbs. Cosy, or
    placeholder-looking?
12. **UI on a real phone**: the chip and ☕ Rest row stacked above the bottom centre, the warning banner above it,
    the title card. The notch and safe area; the emoji in `TextScaled` labels.
13. **Frame time** on a mid/low phone at the worst case: about 120 client parts, 2 emitters, 2 lights, plus the
    server's manor.
14. **Dust**: 3-10 motes/s in a 36×10×36 box. Visible, or lost?
15. **Added by the second review (2026-09-30):**
    * **☕ Rest**: the sit's drop was measured in +1 Jump's Studio, not here. Press ☕ Rest by the fire: does the avatar
      stay seated (it must, for 1 s of settle and after), and does holding W still get you up?
    * **The ⚡ toggle** next to ☕ Rest: findable? Does "⚡ Off" read as "fewer flashes"? With it off, a storm band's
      lightning, the red CAUGHT flash and shake, and the EXTRACTED FOV punch must all stop.
    * **The chip on a real phone**: it now wraps onto two lines and, when the day's buttons would squeeze it, sits on
      its own line under them. The font sizes (12.0-18.8 px on the 19 viewports, phones 14.5) are ESTIMATED; check a
      568x320 and a 667x375 phone, landscape and portrait (upright, the stack sits above the thumbstick).
    * **Hazards every 90-130 s, the ring 0.5 s ahead of a walker**: a close call every 2-3 minutes by the model. Does it
      feel like that, or like too many? And a ghost that meets you before its lane locks now passes through you: does
      that read as a ghost, or as a bug?
    * **The ring after the arrival**: it now stays until the hazard is out of reach (up to about 0.3 s past the
      arrival for the wraith). Does that look like a lingering ring?
16. **Added by pass 2 (2026-10-01): the board, the secret manors and the exit's guard.**
    * **The NIGHTS SURVIVED board** on the safehouse's east wall: a server-drawn SurfaceGui at 40 px per stud
      (12 x 8 studs). Readable from the spawn pad 29 studs away, or only up close? Do the emoji (🏆 🌍 👥) render on a
      SurfaceGui? Is the gold Neon trim too bright in the dark room? The prompt is on F (gamepad Y), so it never fights a
      pad's E: does a phone player find and tap it?
    * **Friends**: `Players:GetFriendsAsync` paging and `GetNameFromUserIdAsync` were only stubbed headless. On a real
      account with friends: the list fills in, "Checking your friends: n of m" counts up, nothing errors in F9.
    * **`workspace:GetServerTimeNow()`** is the board's clock (`tick()` when it is missing): confirm it exists and the
      public list refreshes about once a minute (F9: no DataStore throttling warnings).
    * **`PublicLayouts`** from the command bar (Server context) really switches the next manor to the public layout
      (the thumbnail recipe and the clip list depend on it).
    * **The manor shifts** after three failures in a row on one night: does the NIGHT toast's "The manor has shifted:
      these are new halls." read as a mercy or as a bug? Is three right?
    * **The exit's guard**: an honest player must never see "The Servants' Exit is still barred: it opens in n s". Walk
      the shortest crossing you can on a small manor and press ESCAPE the moment you reach the door. Also press it from
      the room next to the exit, through the wall: it must say "Stand at the Servants' Exit to use it."
    * **The Blood Moon at night 26** (was 20): the model's first-time players get there after a median of 33.5 minutes.
      Does a real first session agree, or is it a slog or a sprint?

---

## 12. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *This recipe has not been tried in Studio. Check step 2 before
relying on the rest.*

1. **Build a fresh place with the new client.** In `nightwatch-manor/`, run
   `rojo build -o NightwatchManor-shots.rbxlx` and open that file (`*.rbxlx` is git-ignored).
2. **No saves.** Turn *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server then
   warns "DataStore unavailable — running without saves" and runs anyway. A fresh profile starts at
   `Config.Night.StartNight` with `StartStash` relics, and nothing reaches the live DataStore or the NIGHTS SURVIVED
   board (which then says nobody has got out yet).
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`. Nothing is published from Studio. For all
   shots:
   * `Watcher.SightRange = 0`: the Nightwatcher never sees you, so it patrols and never hunts. Stay more than 7 studs
     from it, because its catch radius still applies.
   * `Night.DreadSeconds = 900`, `Night.DreadMin = 900`, `Night.DreadPerNight = 0`: a long, calm night. Dread nudges
     the look toward the NEXT band only on a band's last night, so the nights below are pure.
   * Per shot, `Night.StartNight` as given.
   * **Public layouts** (since 2026-10-01 every manor is planned from a server-only salt, so its rooms differ every
     session): after pressing Play and before entering the manor, in the command bar with the **Server** context,
     `game.ServerStorage.NightwatchSecrets:SetAttribute("PublicLayouts", true)`. Every night is then planned from the
     public seed the coordinates below were probed from. Without it no coordinate below means anything.
4. **Play solo.** The first player's zone is index 1: the safehouse floor is centred at **(3000, 100, 0)** and the
   manor's foyer at **(3000, 100, -400)**. Every coordinate below is a world coordinate, from the real generator
   (`Manor.plan` for `WorldSeed 20260909`, probed; re-probed 2026-10-01 for the new band nights). The manor door is on
   the safehouse's south wall.
5. **Getting to a room** without walking through the patrol. Enter the manor through the safehouse door, then move
   the avatar from the command bar (Client context; the client owns its own character):
   `game.Players.LocalPlayer.Character:PivotTo(CFrame.new(X, 104, Z))`.
6. **Clean frames** (command bar, Client context):
   `local g = game.Players.LocalPlayer.PlayerGui; g.NightwatchHud.Enabled = false; g.NightwatchHaunt.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   * Exact camera (Client context):
     `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable; workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(FROM), Vector3.new(AT))`.
   * **The portraits' eyes look at your avatar's head, not the camera**, so park the avatar at the "avatar" spot
     given, just beside and behind the camera and out of frame. The eyes then look straight out of the picture.
7. The look glides on a 0.7 s half-life, so give it a few seconds after a teleport or a new night. Take bursts for
   the lightning shots, and keep Roblox's *Reduced Motion* setting OFF for them (it turns lightning off). Do not
   press ☕ Rest before a lightning shot either: nothing flashes while you rest.

**The seven shots:**

1. **"The Blood Moon in the Portrait Hall"** (store-page hero; `StartNight = 43`, a Blood Moon night).
   * The Portrait Hall at (2960, 100, -400) is the room west of the foyer, through a doorway, and not on night 43's
     patrol. You can walk there.
   * Its west wall carries a portrait at (2941.5, 108, -406) and a window at (2940.6, 107.5, -394), side by side.
   * Avatar at (2976, 104, -401). Camera from (2974, 106.5, -397) looking at (2941, 107.5, -400).
   * **In frame:** the huge blood-red moon behind swaying velvet curtains; the portrait's amber eyes looking back
     at you; dust in the air; the ceiling fixture's flicker on the walls.
   * Wait for a bolt (every 14-26 s): the glass blinks white and the room is lit from the window. Take a burst.
2. **"THE BLOOD MOON RISES"** (the fanfare; `StartNight = 25`, `Night.StartStash = 100000`).
   * Before the night, buy upgrades on the pads until the hub level is 20 or more (the Haven tier: every prop and
     the bigger fire). Enter the manor, take the Servants' Exit, and wait in the safehouse.
   * About 1.2 s into the day, after the server's own "YOU GOT OUT" toast, the card "🩸 THE BLOOD MOON RISES"
     appears, with a flash and an FOV punch. Hide only the HUD for this one (`g.NightwatchHud.Enabled = false`): the
     card belongs to the Haunt UI.
   * Camera from (3013, 109, 20) looking at (2988, 105, -28).
   * **In frame:** the two south windows either side of the manor door, now showing the blood moon over the distant
     manor with its lit windows; the armchairs and rug in the foreground; the card mid-screen.
   * The card lasts 4.5 s. Take a burst.
3. **"Rest by the fire"** (`StartNight = 26` or later, hub level ≥ 20 as in shot 2).
   * Stand at (3000, 104, 19), on the spawn pad between the two armchairs and 8 studs from the fire, facing north
     (+Z). Press **☕ Rest**.
   * Camera from (3000, 106.5, 7) looking at (3000, 104, 28).
   * **In frame:** the seated avatar in silhouette against the hearth; the fire and its embers; the sleeping cat;
     the candles and garland over the mantel; the painting; an armchair either side; the soft focus.
   * One variant with the Haunt UI on, so the chip `☕ Resting by the fire · the manor waits` is in the picture.
4. **"Thunderstorm"** (`StartNight = 12`).
   * Walk to the Portrait Hall at (3000, 100, -360), one room north of the foyer through a doorway, and off night
     12's patrol.
   * Its east wall has a window at (3019.4, 107.5, -354) and a portrait at (3018.5, 108, -366).
   * Avatar at (2992, 104, -361). Camera from (2994, 106.5, -357) looking at (3019, 107.5, -360).
   * **In frame:** rain streaming down the glass; a forked bolt in the window (every 6-14 s); the room lit
     blue-white from the window for an instant; the curtains billowing; the portrait's eyes.
   * Take bursts; the bolt lasts 0.12 s.
5. **"The Witching Hour"** (`StartNight = 64`).
   * Night 64's manor (the first Witching Hour night with this room, probed 2026-10-01) also has a Portrait Hall at
     (2960, 100, -400), west of the foyer through a doorway and off night 64's patrol: you can walk there.
   * Its west wall has the window at (2940.6, 107.5, -394) and the portrait at (2941.5, 108, -406).
   * Avatar at (2976, 104, -401). Camera from (2974, 106.5, -397) looking at (2941, 107.5, -400): the same framing
     as shot 1, on purpose. Shots 1 and 5 side by side show the progression.
   * **In frame:** the eclipse (a black moon with a pale corona) on a green-black sky; rain; the eyes at full glow;
     the deepest flicker. Lightning every 5-11 s.
6. **"Something comes through the wall"** (a hazard; `StartNight = 43`; also `Hazards.IntervalMin = 6`,
   `Hazards.IntervalMax = 8`).
   * Stand in the dining room at (3000, 100, -360), north of the foyer through a doorway and off night 43's patrol.
     Keep the normal camera, pitched a little down. (With `SightRange = 0` the Nightwatcher never sees you, so a
     launch is never held back by a chase.)
   * Within about 8 s the banner says `⚠️ WRAITH INCOMING` or `FLYING CROCKERY`. Frame the hazard coming through
     the wall on its lane line, the ⚠️ marker over it, and the ring on the floor at your feet. The wraith's eyes are
     violet now, not green.
   * Keep the Haunt UI on for one variant, so the banner shows. Step out of the ring after the capture: getting
     knocked down ends the shot.
7. **"The NIGHTS SURVIVED board"** (new 2026-10-01; any night, hub level ≥ 20 as in shot 2 for the cosy room behind).
   * The board stands on the safehouse's east wall at about (3029, 106.5, 23.4), facing west into the room, 29 studs
     from the spawn pad. In a place without API access it shows the empty public board ("Nobody has got out of the
     manor yet. Survive a night and be the first name here!"); for rows, shoot it in a published place's Studio
     session with API access on, never with a real account's friends list in the Friends view.
   * Avatar at (3018, 104, 20), facing the board. Camera from (3014, 107, 15) looking at (3029, 106.5, 23.4).
   * **In frame:** the dark board with its gold trim, 🏆 NIGHTS SURVIVED and 🌍 PUBLIC, the rows; the fire's warm light
     on the left; the avatar's shoulder. Hide both UIs.

---

## 13. Not done / open

* **Two independent adversarial reviews (review 4, §14; the second review, §15), every finding closed test-first.**
  Pass 2 (2026-10-01, §16) built what `docs/complete-game-standard.md` still asked for (the board, the server-only
  salt, the clip list, the store text) and has had no independent review of its own yet. What no headless gate can
  settle is on the Studio list (§11, item 16 for pass 2).

**Owner decisions.** The owner decided on 2026-09-30: "take the recommended option for all". None of the decisions below had
a recommendation marked, so each was taken by what best serves the brief (fair, fun, never punishing, never
exploitable), test first:
* **An in-game "reduce flashing" toggle. DECIDED 2026-09-30 (owner: take recommended): built.** Roblox's Reduced Motion
  setting is the platform's switch, but many players never open it, and its property name is unverified here: if it is
  wrong, nothing turns off. A photosensitivity opt-out that always works serves "never punishing" better than a clean
  row. It is the ⚡ toggle next to ☕ Rest in the safehouse (the break room is where settings belong, and it keeps the
  night's phone layout as it was); by day on a phone the two buttons share the line the hazard warning uses at night,
  so the layout did not grow (§5 rule 4, the layout check). Tests: `check_nightwatchmanor_flash` storm (the toggle) and
  calm (the refusal says why), watched failing first (no button; the HUD flashing under Reduced Motion).
* **The HUD's own effects under "fewer flashes". DECIDED 2026-09-30 (owner: take recommended): they obey it.** They were
  listed as not covered: the red flash and shake when CAUGHT, the purple flash when EVICTED, the shake on SPOTTED, the
  FOV punch on EXTRACTED. A player who asked for fewer flashes gets fewer flashes everywhere; the toasts still say what
  happened. The one change to `Hud.client.luau` is that gate. Tests: flash storm and calm (CAUGHT 6 flash frames before,
  0 after).
* **The bands, like the night counter, reward leaving early. DECIDED 2026-09-30 (owner: take recommended): kept.** It
  is the core game's own rule, every night is still a full crossing to the deepest room (so it is not an exploit), and
  it has a price the pacing model now pins: at the Blood Moon the cautious player has hub level 14 and the greedy one
  24 (medians of 11 players each; asserted at least 5 lower in `Pacing.spec`). Changing it would mean reworking the
  core loop, the chase tuning and the leaderboard for a trade-off that already exists.
* **Hazards held (not frozen) through a chase. DECIDED 2026-09-30 (owner: take recommended): kept held.** The frozen
  clock is exactly the unfairness review 4 found (a player who hides well gets more hazards). A hazard can come right
  after a chase, but only after the 10 s quiet window, with its full warning, and it can knock you down only after its
  lane locks. Already pinned: `Pacing.spec` (the shown rate is the same for a player seen 22 % or 55 % of the time,
  within 15 %) and `check_nightwatchmanor_hazards` (the held hazard comes 10.03 s after the Nightwatcher lost you).
* **One currency (CLAUDE.md "NOT built" item 2). DECIDED 2026-09-30 (owner: take recommended): one currency, relics;
  the description no longer says "& cash".** Adding cash would be a new economy; the honest fix is the copy (README).
* **Which number the brief's "one near-miss per 2-3 minutes" means** (the second review's finding 3 left it to the
  owner). **DECIDED 2026-09-30 (owner: take recommended): the near-miss itself**, a pass within 8 studs of a player who
  reads the ring, counted per minute in the manor (hazards never fly in the safehouse, so counting the break would
  dilute it), asserted 2-3 both ways for four players over three pooled seeds; every hazard shown is asserted rare as
  well (one per 1.5-3 manor-minutes). The standard names the near-miss, and a floor stops the rate from sliding. Tests:
  `Pacing.spec` (P1 and P2 in §9 are killed by it). Recorded as its own line on 2026-10-01; the numbers are §3's.

* **luau-compile and luau-analyze were not available** in this session's scratchpad (only `luau.exe`). Every source,
  spec and check (49 files on 2026-09-30) was compiled with `loadstring` instead: 0 errors. luau-analyze was not run.
* Not built: audio (still the biggest gap in a horror game, and it needs assets); silhouettes in the manor's own
  windows (the safehouse's view of the manor has its passing figure; a figure outside a manor window was left out,
  because a dark shape at head height in a window is exactly the kind of thing a player could take for the hunter).
* Not published. Studio not opened. The eye candy is committed (0ed378f); the second review's work (§15) and pass 2
  (§16) are not.
* §11 in full.

---

## 14. Review 4 (2026-09-24): four findings, reproduced, fixed and gated

An independent adversarial reviewer re-ran all 30 gates on a clean copy (all green, same counts), confirmed that
`Main.server.luau`, `Hud.client.luau` and every pre-existing module and check were unchanged, reproduced the chase
table and the hazard safety rules, and checked every coordinate in the shot list. It filed four findings. Each was
**reproduced here before anything was changed**. For each one a **failing test was written and run against the
pre-fix bundle** (in a scratch copy, so the real tree was never broken), and then the game was fixed, not the test.
Scratch work: `scratchpad/nwm_r4/` (`repro1.luau`, `repro2.luau`, `oldbundle_fail_storm_budget.txt`, the sweep).

**1. (medium) Hazards came far more often than the brief, and more often the better you hid.**
* *Reproduced exactly:* the normal profile got 137 hazards in 200 min of play, which is one per 1.18 minutes in the
  manor, or one per 32.7 s of unhunted time. The 2.5-minute figure came from dividing by all of play, counting only
  passes within 8 studs, and measuring one profile. The reviewer's stealthy stand-in (sight cut to 30 studs) got one
  per 0.74 manor-min.
* *Cause:* the clock froze for every chase, so a player who was rarely seen ran it for longer.
* *Fix:*
  - `ctx.held` in `Hazards` (the clock runs, a due hazard waits);
  - `Nightfall.hazardClock` ("freeze" outside the night, "hold" while hunted and for 10 s after, "run" otherwise);
  - the interval set to 120-180 s of night.
  Nothing launches into a chase, and nothing lands during one: both still asserted, 0.
* *Result:* one hazard shown per **2.57-2.65 minutes in the manor** for the normal, fast, slow and stealthy players
  (§3). The chase table did not move, and neither did the Blood Moon's time (37.2 min).
* *Tests:*
  - `Hazards.spec`: +12, the held section and a probe that tells a held clock from a frozen one;
  - `Nightfall.spec`: +18, `hazardClock` and `hazardGate` agreeing;
  - `Pacing.spec`: the honest metric for four players and the "rate does not depend on being seen" rule. It failed 5
    times on a frozen clock even with the new interval;
  - `check_nightwatchmanor_hazards`: after a chase the held hazard comes at once. It measured 16.5 s on the old
    client and 10.03 s now.

**2. (medium) The anti-strobe rule was checked on the config, not on the game, and rest kept flashing.**
* *Reproduced:*
  - night 43: 20 strikes in 112 s, the closest two 2.73 s apart;
  - night 18: 3.33 s;
  - resting by the fire on night 43: 21 strikes in 180 s;
  - night 18 at rest: 19.
  The locked marker blinked 3 times a second, which at 30 fps came to 4 flashes in one second.
* *Fix:*
  - `Nightfall.boltGap`: real seconds, never under `HARD.FlashGapMin` = 4;
  - no strike while resting;
  - `Nightfall.blink`: at most 2 a second;
  - **Roblox's Reduced Motion setting** turns every flash of ours off, read live.
  The rate the owner was told is corrected in §2's table: at full dread the Witching Hour flashes every 4-5.5 s,
  not "5-11 s".
* *Tests:*
  - `Nightfall.spec`: +18 for `boltGap` and `blink`;
  - `EnvConfig.spec`: the real gaps per band;
  - `check_nightwatchmanor_rest`: 13 flashes in 302 s of rest on the old client, **0** now;
  - the new `check_nightwatchmanor_flash`: storm (old client 2.77 s and a 4-per-second marker; now 4.03 s and at
    most 2 a second) and calm (old client 21 strikes, 14 screen flashes and a blinking warning; now 0, 0 and steady;
    switched off live, the lightning comes back);
  - `check_nightwatchmanor_budget`: asks for lightning every 0.3 s and gets 4.00.

**3. (low) The will-o'-wisp and the wraith's eyes were 35 from the Servants' Exit's green.**
* *Reproduced:* the budget check's new scan measured `Hazard_wisp_Wisp` at 35.0 on the old client.
* *Fix:*
  - `Config.Env.ExitSignature` (120,220,140), checked by `Nightfall.fairness` against every glow, pinned by the haunt
    check to the built ExitLamp, its light and the ExitDoor's light, and scanned on every frame of the worst case;
  - the ghosts' colour moved into `Config.Env.Glow.ghost` / `ghostHalo`, a violet ghost-light, 149 / 148 from the
    exit and 78 / 74 from the lamp.
* *Tests:* `Nightfall.spec` +6, `EnvConfig.spec` +5, haunt +4, budget +2.

**4. (low) The docs said the client's only write to anything server-built is room-light Brightness.**
* *Reproduced by reading `Haunt.client`.* It writes the Lighting service and the server's FxAtmosphere, FxBloom and
  FxColorCorrection every lighting tick, and its own character's Sit, PlatformStand and velocity. The old haunt check
  snapshotted only the zone.
* *Fix:* the statement is corrected in `CLAUDE.md`, §6 and the `Haunt.client` header. The Lighting write-set is now
  asserted: after a whole session, 16 keys changed, all of them band keys; FxDoF untouched; one child added, the rest
  focus.
* *Not a test-first case:* the true rule held on the old client too (the finding was the wrong words, not wrong
  behaviour). The assertion is proven by mutation instead (§9, F4a/F4b).

Also from the review: shot 5's "through two rooms on the patrol" corrected to one (§12).

---

## 15. The second review (2026-09-30): eight findings, reproduced, fixed test-first

Each finding was reproduced on the committed tree before anything changed, a test was written and watched failing
against the old bundle, and then the GAME was fixed. Scratch work: `scratchpad/nwm_p1_0930/` (probes, the gate runner,
the sweep). The mutation proof of every new assertion is §9, round 4.

1. **(HIGH) ☕ Rest stood you back up on the first frame in real Roblox.** Reproduced by replaying the Studio trace of a
   seatless sit's drop through the real Hud + Haunt clients: seated on **1 of 120** frames after pressing Rest, the chip
   back to the band text, the button `☕ Rest`. New `check_nightwatchmanor_sitdrop` (14 passed / 10 failed on the old
   bundle, 24 / 0 now). Fix: `SIT_SETTLE_SECONDS = 1.0` after the sit counts as supported, stamped on both paths (the
   button, and a queued rest that starts on landing); a sustained fall while seated still wakes you (§4).
2. **(MEDIUM) Saves went through without holding the session lock.** Reproduced with the reviewer's sequence on the real
   server: another session writes night 9 / 999 relics and releases the lock; A's 20 s autosave put night 5 / 10 relics
   back. New `check_nightwatchmanor_save` (25 / 42 on the old server; 67 / 0 now): released lock (both formats),
   expired foreign lock, and as CONTROLS a fresh foreign lock (refused before too) and A still owning its stale lock
   (A's night 6 IS saved). Fix: `saveProfile` writes only while the stored lock carries this session's token; the first
   refusal turns `canSave` off and tells the player once (READONLY); a release keeps the token with `at = 0`.
3. **(LOW) Near-misses came half as often as the owner asked.** Reproduced exactly: one per 5.07 (normal), 4.72, 6.52,
   4.74 manor-minutes, and nothing asserted a floor. The owner's standard names the near-miss, so the near-miss is now
   asserted both ways (one per 2-3 manor-minutes, four players, pooled over three seeds): 4 failures on the old config.
   Fix: hazards every 90-130 s instead of 120-180, the ring 0.5 s ahead of a walker instead of 1 s (a ring 20 studs
   ahead of a player who then turned was a far pass, not a close call). Now one per 2.63 / 2.86 / 2.72 / 2.68; shown
   hazards one per 1.92-2.00 manor-minutes (asserted 1.5-3). The chase table did not move (§3).
4. **(LOW) The 30-45 min Blood Moon was asserted on one chaotic trajectory, by a player who never searched.**
   Reproduced exactly (26.7-47.5 min, median 39.0, 12 of 31 outside 30-45). Fixed in the GATE, which was the defect:
   `Pacing.spec` now asserts the median of 31 perturbed normal players, and at least half of them, inside 30-45, both
   for the model that knows each layout (median 37.3) and for a new FIRST-TIME player who knows only what it has
   entered or seen through a doorway (median 32.1; a CONTROL proves it searches: 315 s vs 291 s out of nights 1-12, and
   it walks only part of the manor on 11 of 12). The game's pacing needed no change.
5. **(LOW) The ring and the banner went before the hit window closed.** Reproduced through the real client by standing
   at the spot inside the ring the hazard reaches last: hit with the ring already gone on 6 of 8, the banner on 2. Fix:
   `Hazards.threatLive` (the same function +1 Jump gained) keeps both up while a hit can land. `Hazards.spec` +9
   (600 lanes: 17 hits after the arrival time, 0 on a frame threatLive called over), hazards check 4b.
6. **(LOW) The Lighting write-set check only compared the final state.** Confirmed by reading the check; the reviewer's
   mutant R4a (FxDoF.FarIntensity = 0 at each flash, put back after) is killed now (§9 W1: 24 assignments caught). Fix
   (in the check, which was the defect): a hook on every assignment to Lighting and the server's effects.
7. **(LOW) MaxParts, MaxLights and MaxHazards were capped nowhere in code.** Reproduced with the budget cut to 50 parts
   and 1 light in memory: the client parented 115 parts and 2 lights, over budget on 490 of 490 frames. New
   `check_nightwatchmanor_caps` (11 / 1 before, 12 / 0 now), `Nightfall.spec` +3 (MaxHazards 0 switches hazards off).
   Fix: §7 (a reserve for the hazard, scenery from what is left, `capLights`, one hazard model at a time).
8. **(LOW) The band chip was too narrow to read on small phones.** Reproduced with the layout check's own harness: on a
   568x320 phone the chip was 95x44 screen px beside the Rest button, for chip texts of up to 40 characters; with the
   16 design-px text cap under a 0.6 UIScale no chip text on any phone could exceed 9.6 px. The layout check now
   estimates every chip and warning text's font on 19 viewports (the HUD's 10 + 9 phones), at least 11 px: 35 failures
   before. Fix: the chip wraps, keeps 170 x 40 screen px (stacked under the day's buttons when narrower; above the
   touch controls on an upright phone), the warning gets two lines, the text caps are meant in screen px, and the
   highest label (the card) is inset from the HUD's drawers. Now 12.0-18.8 px everywhere (phones 14.5-18.8; measured
   2026-10-01).

**Found while fixing 3: a knock before the lock.** With the ring following a player until the lane locks, walking up to
a slow ghost and stopping in its path knocked 8 of 8 players down at 1.83-1.90 s, with the banner still saying INCOMING
(the Pacing model found the same case at other intervals: 2 reacting players hit). Fix: `Nightfall.hitFrom` (arrival
minus reach over the KIND's speed: after the lock, at least 3 s into the warning; `Nightfall.spec` +12); the client and
the model clip the hit test to it. Hazards check 4c: no knock before the DODGE banner or before 3 s of warning.

**Re-verified 2026-10-01** (pass 1 run again; scratch `scratchpad/nwm_p1_1001/`). Each finding reproduced on the committed
code (a HEAD export, bundle rebuilt from it) with today's checks, and checked on this tree:

| # | on the committed code (HEAD) | on this tree |
|---|---|---|
| 1 | `sitdrop` 14 / 10: seated 1 of 120 frames after ☕ Rest, the button back to `☕ Rest` | 24 / 0 |
| 2 | `save` 25 / 42: night 5 written over the other session's night 9 | 67 / 0 |
| 3 | HEAD's own Pacing output: near-hits one per 5.1 (normal, 32 in 200 min), 4.7, 6.5, 4.7 manor-min; shown one per 2.57-2.65; 19 of the normal 63 called off | one near-miss per 2.63 / 2.86 / 2.72 / 2.68, pooled over 3 seeds; Pacing 55 / 0 |
| 4 | the reviewer's sweep (normal `startSeconds` +0..+30 s, HEAD model): 26.7-47.5 min, median 39.0, 12 of 31 outside 30-45; +5 s 31.2, +20 s 46.1, +30 s 39.4 | asserted on populations of 31: knows the layout 25.0-47.7, median 37.3, 17 inside; first-time 24.3-37.8, median 32.1, 19 inside |
| 5 | `hazards` 51 / 3: hit with the ring gone 7 times, the banner 3 | 54 / 0 |
| 6 | the reviewer's R4a (§9 W1) on the current bundle: HEAD's `haunt` 124 / 0, survives | today's `haunt` 125 / 1 (FxDoF.FarIntensity x26) |
| 7 | `caps` 11 / 1: over the cut budget on 490 of 490 frames (DAY 73 parts) | 12 / 0 |
| 8 | `layout` 6 / 1: 35 of 57 chip and warning labels under 11 px; the 568x320 day chip 95 x 44 px | 7 / 0: 0 under 11; 12.0-18.8 px (phones 14.5-18.8), three runs identical |

No finding needed new code this time: every source, test and check is byte-identical to the 2026-09-30 fixes (only
`CLAUDE.md` and this file changed; the unfinished board pass that had been laid over them is archived, `CLAUDE.md` State). Compile: 49 files through `loadstring`, 0 errors.


---

## 16. Pass 2 (2026-10-01): the board, the secret manors and the exit's guard

Pass 2 of 2 measured the game against `docs/complete-game-standard.md` and built what it still lacked (scratch
`scratchpad/nwm_p2_1001/`: gate logs, mutant lists, sweep logs, the probes). Nothing is committed or published; Studio
was not opened.

**Resumed, not restarted.** A cut-off run had started a highscore board, a server-only salt and a guard on the exit;
pass 1 archived it byte-for-byte with five red suites. It was put back from the archive (sha256 per its manifest) and
finished. The five reds were: the layout-bound checks (`check_walk`, `check_nightwatch`, `budget`, `caps`) meeting
salted manors, so they now flip the server's `PublicLayouts` switch; exit presses meeting the guard, so the kit's
`Kit.extract` / `ctx.pressExit` now stand at the door after the shortest walk; the board's two new safehouse parts; and a
kit bug: it blinded the Nightwatcher with `CatchRadius = -1`, which `Watcher.caught` squares into a 1-stud catch, while
the player waited on the foyer's start point, which lies on the patrol line (night 7: caught every time at 5.9 s).

**Built test-first** (each new check or assertion run red first, on the code before the change):

| what | red first | now |
|---|---|---|
| a salt per player, night and session (the WIP drew one per attempt) | `guard`: "the retry is planned from the SAME halves" failed | a retry is the same manor; a new night, a rejoin or another player is not |
| the manor shifts after `ShiftAfterFails` (3) failures in a row | `guard` 55 / 6; `Pacing`: one model player 418 attempts at night 36, 2 of 31 never at the last band | new halves, the NIGHT toast says "The manor has shifted"; nobody needs more than 9 attempts at a night |
| ESCAPE only from inside the exit room | `Crossing.spec` 36 / 4: public night 9's bound 77 studs short of the best legal walk (through the wall); a salted night-45 manor 0.13 s from the start | the bound ends in the exit room: 2.9-8.9 s public, 1.85-10.44 s on 3000 salted manors; `guard` presses from behind the wall and is refused |
| the refusal's reason in the toast text | `guard`: the seconds were only in the notice's detail, which the HUD drops | "The Servants' Exit is still barred: it opens in n s" |
| the public board on a fresh server | `board`: "Loading..." 1.5 s after the first join (the first read waited a minute) | read within a second of the first join, then once a minute |
| names: a player on the server first | `board`: Ned shown as `User_8109`, a lookup cached before he joined | the player's own name |
| the Blood Moon in 30-45 minutes on the manors the game plays | `Pacing`: salted first-timers at night 20 after a median of 25.8 min, 10 of 31 inside | night 26: median 33.5, 23 of 31 inside; the Witching Hour moved to 50 (median 66.8) |
| the hall tour of `haunt` | it visited 0 Portrait Halls on night 50 and passed ("halls == 0 or ...") | blinded tour, CONTROL halls >= 1: 3 halls, 14 pupils |

The board check and the guard check were also run on pass 1's tree (no board, no salt): the board check failed from
its first assertion on, the guard check stopped at `require(Salt)`.

**Mutation sweep, pass 2** (`sweep.py`, the pass-1 driver: worker copies, one replacement each, the mutant proven in
the rebuilt bundle, all 40 gate runs per mutant, sha256 restore), three rounds: 29 mutants. **24 of 25 killed**; the survivor (B5:
the friends loop's own cap check deleted) changed nothing because two checks inside the loop already held the cap, so
that copy was deleted from the code and the cap check left (B5b) is killed by `board` (8 page turns). **4 controls (a
reworded board hint, two shades of the board's colours, a reworded board prompt) survived all 40 gate runs each.** Every
worker file sha256-identical afterwards.

| id | mutant | killed by |
|---|---|---|
| G1 | a retry gets new halves | guard |
| G2 | failures never count (no shift) | guard |
| G3 | the secrets folder in ReplicatedStorage | guard ("the server keeps its manor records in ServerStorage"), and 11 more suites whose exit presses read the record from ServerStorage |
| G4 | the server forgets the exit-room test | guard |
| G5 | `verdictFor` ignores the room | Crossing.spec, guard |
| G6 | no room ends a walk (the bound collapses to 0) | Crossing.spec, guard |
| G7 | the refusal does not say when | guard |
| B1 | every best stamped at 0 (no tie-break) | board |
| B2 | the same best written at every autosave | board |
| B3 | a read-only session writes the board | board |
| B4 | the first public read waits a minute | board |
| B5 / B5b | the loop's cap copy / the last cap check | survived (equivalent; deleted) / board |
| B6 | the friends cache never hits | board |
| B7 | names: the cache before the player on the server | board |
| B8 | no board in the safehouse | check_nightwatch, board |
| B9 | anyone can switch my board | board |
| B10 | the score-read limiter bypassed | board |
| B11 | the public read asks for 50 rows | board (`GetSortedAsync(false, 10)`, added after round 2) |
| P1 | the model never shifts | Pacing.spec |
| P2 | the model draws salts but plays the public manor | Pacing.spec (its CONTROL) |
| P3 | the Blood Moon back on night 20 | Pacing.spec, fairgate light |
| X1 | the crossing clock slack 1.5 s | Crossing.spec |
| X2 | the shift after 10 failures | guard |
| K2 | the hall tour finds no hall | haunt (its CONTROL) |
| C1-C4 | controls | survived 40 of 40 each |

**Store text, clips, thumbnails.** README's description was rewritten against the code (909 code points, no
coloured-square emoji). `MARKETING.md` is the clip list (8 clips, vertical 7-15 s, with staging and honest captions).
The thumbnail shots moved with the bands and were re-probed on the public manors (§12: the Blood Moon shots on night
43, the Witching Hour on night 64, the same framing as before; a seventh shot of the board), and the recipe now
switches the server to `PublicLayouts`, without which none of its coordinates mean anything.

**Open.** Everything on §11 (item 16 is this pass's). No independent review of pass 2 yet. luau-analyze was not run (57
files compiled through `loadstring`, 0 errors). The near-miss rates were re-measured only on the public manors. The
genre gaps stay (CLAUDE.md "NOT built": no audio, no jumpscare, no puzzles, traps that do not fire).

---

## Night shift 2026-10-09: second review of 0ed378f + 95ca6c5 (job H step 2)

One independent read-only reviewer. Verdicts: **0ed378f SHIP-WITH-DEFERRED; 95ca6c5 BLOCK.** Nothing fixed yet.
1. **HIGH. A script can still climb the board.** The exit guard (`Main.server.luau:1263-1292`) checks only that
   `minSeconds` has passed on the night clock and that the character is in the exit room when E is pressed.
   Detection (`:1472-1506`) works on x/z, so a character standing outside every room is never spotted.
   - The exploit: teleport out of the manor, wait about 9 s, teleport into the exit room, press E. That is one
     safe night per ~12 s, and MaxNight 500 in under 2 hours.
   - The claim in CLAUDE.md and Crossing.luau ("gains nothing a person could not") is false.
   - Fix: check the position every tick. Treat outside the footprint, or a jump larger than WalkSpeed·dt plus
     slack, as a forfeit.
2. **MEDIUM. No Studio gate on the live stores** (`:64-76`).
3. **MEDIUM. A session can go unsaved for its whole length.** A leave during `claimProfile` never releases the
   lock (`:1895-1897`), and a pcall failure counts as "lock held" (`:519-521`). A read-only session never
   retries. The notice at `:1934` promises that saving resumes, which it does not.
4. **LOW.** The board is written before `saveProfile` (`:1655`).
5. **LOW.** `nameCache` and `scoreCache` never evict.

Checked and clean: there are no client→server remotes; rest earns nothing; the save token and `keepHigher` are
correct; the precision holds; the empty public board has text.
