# Nightwatch Manor — the nights escalate

Owner's brief (Gustav, 2026-09-17): every game visibly richer and never monotonous, with the environment changing as
the player progresses, in that game's own logic; rare knock-down hazards (about one near-hit per 2-3 minutes, easy to
see coming and avoid); a way to rest that can never become an exploit; a thumbnail shot list for the night Studio
session. For this game specifically: the visuals must not hide the Nightwatcher unfairly, reveal it unfairly, or
change the chase balance that was tuned by hand (an ambushed runner is never caught; a player who ignores it is caught
on 19 of 30 nights).

**State: built, unit-tested, headless-tested through the real server + HUD + client, mutation-tested, and through one
independent adversarial review (review 4, 2026-09-24), whose four findings are closed (§14). NOT seen in Studio.**
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
  20 and goes into eclipse with a pale corona at night 40.
* **Portraits** whose eyes follow you and glow more every band.
* **Candles and fixtures** that flicker harder as the night wears on, and **dust** in the air.
* **The safehouse** grows cosier as you buy upgrades. The hearth is kindled, then an armchair, bookshelf and candles
  appear, then a sleeping cat, a garland and a painting, and last a second armchair and a plant. Its two windows look
  across the grounds at the manor, where a figure passes behind a lit window.

**Hazards** (bats, a will-o'-wisp, flying crockery, a wraith) are ghosts: they come through the walls. There is one
every 2-3 minutes in the manor, for every kind of player. Each comes with 3 s of warning and a ring on the floor, and
none flies while the Nightwatcher is hunting you. **Rest** is the safehouse between nights: sit by the fire as long as
you like, and no lightning flashes while you do. The night never pauses, so rest is never offered inside it.
**Roblox's own Reduced Motion setting** turns every flash off: lightning, a knock's screen flash, the blinking warning.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from `plus1-jump` (identical bytes). Progress → band + eased blend, `approach`, `capRates`. Pure. |
| `src/shared/Rest.luau` | **template, verbatim** (identical bytes). The rest state machine. Pure. |
| `src/shared/Hazards.luau` | **template + four additions**, each pinned in `tests/Hazards.spec.luau`: `ElevationMin/Max` (a lane starts inside the room's height band, never out of the floor); `ctx.paused` (freeze the clock: it is day, or the night has just ended); `ctx.held` (review 4: the clock runs but a due hazard waits, for the Nightwatcher's hunt); `Hazards.cancel` (call off the hazard in flight with no hit, schedule untouched). |
| `src/shared/Nightfall.luau` | **new, pure,** this game's own rules: `progress` (night + dread × lookahead, never time), `bandIndex`, `chipText`, `outerFaces` / `windowPlacement` (windows on outer walls only), `flicker` (bounded, with a hard floor), `boltGap` (real seconds between lightning flashes, never under 4) and `blink` (at most 2 a second), `fairness` (the visibility envelope + the no-decoy rule for the Nightwatcher's colours AND the exit's, §5), `hazardClock` / `hazardGate` / `validateHazards` (the chase rules for hazards), `leadAim`, `validateRest` / `restAllowed` (rest is DAY only), `cosyTier`, `pupil`. |
| `src/shared/HauntArt.luau` | **new, client only.** Builds and pools every local part: windows, portraits, dust and rain hosts, the lightning light and bolt, the safehouse props and windows, the hazard models, lane and ring. |
| `src/client/Haunt.client.luau` | **new, the glue.** State → progress → bands → lighting (10 Hz, glided, inside the fairness gate) → windows, portraits, flicker, weather, lightning → the safehouse → rest → hazards → chip, Rest button, warning banner, title cards. Reads Roblox's Reduced Motion setting live. |
| `src/shared/Config.luau` | + `Env` (6 bands, windows, cosiness tiers, the watcher's and the exit's light colours for the fairness rule, the ghosts' colour, the blink rate), `Hazards`, `Rest`, `Budget`, `Pacing` (the model's human assumptions). All cosmetic, and the server reads none of it. |
| `src/server/Main.server.luau`, `src/client/Hud.client.luau` | **unchanged** (`git diff` is empty). Everything the client needs was already in the State push: `phase`, `night`, `dread`, `spotted`, `hubLevel`. |
| `tests/` | `EnvBands.spec`, `Rest.spec` (verbatim from the template), `Hazards.spec` (template + the four additions), `Nightfall.spec`, `EnvConfig.spec` (the shipped numbers checked against every rule), `Pacing.spec` + `NightModel.luau` (minutes of play, measured rarity, the chase with and without hazards). |
| `robloxemu/check_nightwatchmanor_*.luau` | `kit` (shared boot, not a check), `haunt` (the whole glue), `hazards`, `join` (a slow profile load), `layout` (the new UI around the HUD, 10 viewports), `rest`, `budget` (the worst case), `fairgate` (hostile configs), `flash` (review 4: lightning gaps, blink rates, Reduced Motion). |

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
| 4 | ⛈️ Thunderstorm | 10-19 | heavy rain (44/s), full cloud, a smaller moon | flicker 0.7, curtains billow (10°) | **forked lightning**, 6-14 s / 4-7 s, a bolt drawn in the glass | flying crockery, bats | 17.2 | 13.7 | 20.6 |
| 5 | 🩸 Blood Moon | 20-39 | a huge **blood-red moon** on a crimson sky, stars back | dust 6/s, flicker 0.8, the portraits' eyes burn amber (0.85) | bolts, 14-26 s / 7-13 s | wraith, flying crockery | **37.2** | 26.4 | 29.2 |
| 6 | 🕯️ The Witching Hour | 40+ | **total eclipse**: a black moon with a pale corona on a green-black sky, rain, mist | dust 7/s, the deepest flicker, sway 12°, eyes at full glow | bolts, 5-11 s / 4-5.5 s | all four | 69.0 | 61.3 | 50.3 |

* **Lightning comes more often as dread rises, and never faster than one flash per 4 s.** Each gap is rolled in REAL
  seconds by `Nightfall.boltGap`: the band's own range, divided by (1 + dread), and never under
  `Nightfall.HARD.FlashGapMin` = 4 s whatever the band or dread asks. (Before review 4 the client ran its countdown at
  (1 + dread) × real time, so the Witching Hour's "every 5-11 s" came to every 2.7 s at high dread; §14.) Measured
  through the real client on a whole night-43 night up to dread 0.97: 19 flashes in 109 s, the closest two 4.03 s apart.
* **No lightning while you rest** by the fire (seated or dozing), and none at all with Roblox's Reduced Motion setting
  on. A strike that falls due then is silent: the gap is kept, nothing flashes.
* Candle flicker deepens with dread on top of the band's own amount (`FlickerDreadGain 0.6`). The headless check
  measured a flicker range of 0.13-0.17 early in a night (dread about 0.2) and 0.30 at dread 0.88.
* Curtain sway grows 60 % at full dread.
* Dust rises 50 % at full dread.
* The portraits' eyes glow +0.4 at full dread.

**The flagship milestone is the Blood Moon**, at 37.2 minutes of play for the normal profile. The brief's target is
30-45 minutes, and `Pacing.spec` asserts that window. It is also the one band that is celebrated: a fanfare card
"🩸 THE BLOOD MOON RISES" with a flash and an FOV punch, shown back in the safehouse after the server's own "YOU GOT
OUT" toast. **The Witching Hour is the long-term goal**: at least 1.6× the flagship's time, and inside 3 hours
(both asserted). Every band lasts long enough to be a place, not a flicker (asserted: ≥ 1 min for the first, ≥ 3
min for the rest).

**Why "slow" gets to the Blood Moon sooner than "normal".** The night advances when you get out, whatever you are
carrying. The cautious profile takes three relics and leaves at dread 0.45, so it gets caught less and its nights are
shorter. The greedy one ends richer and a band later. That is the existing game's rule, not something the visuals
added. It is worth knowing when reading the table.

**Chip** (a row under the HUD's help line; on phones it stacks up from the bottom centre, between Roblox's thumbstick
and jump button): `🌫️ The Mist Rises · Night 4 · 🌧️ in 2`. The last band has no "next". While resting:
`☕ Resting by the fire · the manor waits`.

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
* It takes nothing: relics, dread and the night are the server's, and the server never hears of a hazard.
* The warning covers the **earliest** hit, not the arrival. `Nightfall.validateHazards` requires
  telegraph − (hitRadius + PlayerRadius) / speed ≥ 3 s for every kind: bats 3.09, wisp 3.30, crockery 3.03,
  wraith 3.05.

**The chase rules** (`Nightfall.hazardClock`, `validateHazards`, and the client):
1. **One hazard every 120-180 s of night** (`IntervalMin/Max`). The clock is **frozen** outside the night: in the
   safehouse, in the 2.5 s beat after a night ends, and before the profile loads.
2. While the Nightwatcher sees you, and for `QuietAfterSpottedSeconds` = 10 s after it last saw you, the clock keeps
   running but the launch is **held**: nothing launches into a chase (10 s is longer than its 7 s hunt, validated as
   "hunt + 1 s at least"). A hazard that falls due meanwhile launches the moment the quiet window closes: one hazard,
   never a backlog, and never two closer than 120 s. Review 4 found that the old rule, a clock FROZEN while hunted,
   made hazards come more often per minute in the manor the better a player hid (§14).
3. The moment it sees you, a hazard in flight is **called off** (no hit), and a knock **ends** that frame.
4. A knock is capped at 0.8 × WalkSpeed, and `KnockLift` is 0. There is nothing to fall off in a manor, and a knock
   is never a speed boost.
5. The clock is never reset. Neither a night ending, nor a chase, nor resting can thin hazards out or bunch them up.

**Measured rarity** (`Pacing.spec`, 200 minutes of play per profile, hazards on). Counted strictly since review 4:
**every hazard SHOWN** (each one homes on you with a banner and a ring at your feet, whether it then passes close, is
dodged wide, or is called off by a sighting), **per minute IN THE MANOR** (hazards never run in the safehouse, which is
10-34 % of play), for **every profile**, and for a player who is rarely seen (the reviewer's stand-in: the
Nightwatcher's sight cut to 30 studs in memory). The brief asked for about one per 2-3 minutes. That window is
asserted for all four, and so is "the rate does not depend on how often it sees you" (within 15 %).

| player | minutes in the manor (of 200 played) | hunted | hazards shown | one per | near-hits within 8 studs | called off |
|---|---|---|---|---|---|---|
| normal | 162 | 54 % | 63 | **2.57 manor-min** (3.2 play-min) | 32: one per 5.1 manor-min | 19 |
| fast | 175 | 54 % | 66 | **2.64** (3.0) | 37: one per 4.7 | 21 |
| slow | 124 | 47 % | 47 | **2.64** (4.3) | 19: one per 6.5 | 9 |
| stealthy (sight 30) | 156 | 23 % | 59 | **2.65** (3.4) | 33: one per 4.7 | 5 |

| also measured | result |
|---|---|
| hits on a player who steps out of the ring | **0** (asserted) |
| hits on a player who ignores every warning | 11 in 163 manor-min, **one per 14.8 manor-min**, 9.5 s knocked down in all (asserted: at most one per 5, and more than 0, else the ring is decoration) |
| the same count under the old rule (resume session, reproduced for review 4) | normal profile: 137 hazards, one per **1.18 manor-min**; stealthy stand-in: one per **0.74**. That was the finding. |

**Through the real client** (`check_nightwatchmanor_hazards`, interval cut to 6-8 s in memory on a night-12 player):
* A minute in the safehouse launches nothing.
* A hazard launches on the band's kinds only, one at a time, with its warning showing from the first frame.
* The ring is centred where you stand and exactly as wide as the hit rule.
* Standing still: knocked down after ≥ 3 s of warning, pushed sideways slower than walking, never lifted, back up
  after 0.8 s.
* **Walking out of the ring in each of 8 compass directions: 8 of 8 dodged.**
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
| ambushed runner | 1-20 | 0 | **0** (2 hazards, 1 hit) | **0** (12 hazards, 9 hits) |
| ambushed runner, full Bear Traps | 1-20 | 0 | **0** (1 hazard, 1 hit) | **0** (8 hazards, 6 hits) |
| wandering runner | 1-20 | 0 | **0** (15 hazards, 9 hits) | **0** (355 hazards, 322 hits) |
| greedy looter ignoring the watcher | 1-30 | 19 | **19** (2 hazards, 1 hit) | **19** (62 hazards, 6 hits) |
| exit walker ignoring the watcher | 1-30 | 5 | **5** (no hazard reached it) | **5** (29 hazards, 3 hits) |

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
   * **Roblox's own Reduced Motion setting** (`GuiService.ReducedMotionEnabled`, read live) turns off every flash of
     ours: no lightning at all, no screen flash or shake on a knock or the Blood Moon card, and the hazard's warning
     light and marker hold steady. The rain, the windows and the rest of the band stay.
     `check_nightwatchmanor_flash -a calm` plays a whole night-43 night with it on (0 flashes) and then switches it
     off in the safehouse (the lightning is back within 30 s). **The property's name is from the Roblox API as I know
     it and was not checked in Studio**: read through `pcall`, so an engine without it simply reads "off" (Studio
     list).
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
| night, dread, relics, the Nightwatcher, the chase, upgrades, saves, leaderboard, spawn | **server, unchanged** | authoritative, as before; `Main.server.luau` has an empty diff |

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
    `FxAtmosphere`, `FxBloom` and `FxColorCorrection`. Never `FxDoF` or any other key. The haunt check snapshots
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
parts** (before review 4, when a bolt was in the glass on a third of all frames, it was 121).

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

---

## 8. Gates

Every gate for this game, on the final tree after review 4. The bundle `robloxemu/build/nightwatch-manor.luau` was
rebuilt from it (md5 `3118db89…`; it was `529c17c1…` before review 4), and so was `tests/build/`. The runner
(`scratchpad/nwm_r4/gates.sh`) judges each process by its **exit code**, not its last line. The whole set was run
**three times**, because the client checks use unseeded randomness (hazard kinds, lightning, the portraits' pick).
The counts were identical each time: **32 of 32 green**.

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
| `tests/Hazards.spec` | **138** / 0 | new (template + additions); +12 in review 4 (`ctx.held`, held vs frozen) |
| `tests/Nightfall.spec` | **170** / 0 | new; +42 in review 4 (`hazardClock`, `boltGap`, `blink`, the exit's colour) |
| `tests/EnvConfig.spec` | **244** / 0 | new; +9 in review 4 (real lightning gaps, the exit's signature, the ghosts' colour) |
| `tests/Pacing.spec` | **49** / 0 | new; +10 in review 4 (hazards shown per manor-minute, four players, rate independent of being seen) |
| `tests/check_walk` | 62 / 0 | |
| `tests/check_world` | 38 / 0 | |
| `tests/check_boot_guard` control / fraction / walkspeed / saturated | 2 / 4 / 4 / 4, 0 failed | |
| `robloxemu/check_nightwatch` | 127 / 0 | |
| `robloxemu/check_nightwatch_hud` | PASS (10 viewports) | |
| `robloxemu/check_nightwatchmanor_haunt` | **124** / 0 | new; +9 in review 4 (the exit's colour pinned to the built exit; the Lighting write-set) |
| `robloxemu/check_nightwatchmanor_hazards` | **45** / 0 | new; +2 in review 4 (the held hazard comes at once after a chase) |
| `robloxemu/check_nightwatchmanor_join` | 25 / 0 | new |
| `robloxemu/check_nightwatchmanor_layout` | 7 / 0 | new |
| `robloxemu/check_nightwatchmanor_rest` | **41** / 0 | new; +3 in review 4 (no lightning while resting) |
| `robloxemu/check_nightwatchmanor_budget` | **32** / 0 | new; +4 in review 4 (the exit's colour on every frame; lightning never under 4 s) |
| `robloxemu/check_nightwatchmanor_fairgate` light / hazards / rest | 11 / 6 / 8, 0 failed | new |
| `robloxemu/check_nightwatchmanor_flash` storm / calm | **18 / 20**, 0 failed | new in review 4 (lightning gaps at high dread, blink rates, Reduced Motion) |

Totals:
* **specs: 1250 passed** (1177 before review 4; 470 before the eye candy);
* **headless: 114 in `tests/` + 464 in `robloxemu/`** (408 before review 4), plus the HUD PASS;
* **0 failed anywhere**.

Also:
* **Compile:** `luau-compile` and `luau-analyze` are not in this session's scratchpad (only `luau.exe`). All 45 Luau
  files were compiled with `loadstring` instead: 17 sources, 17 test files, 11 `check_nightwatch*`. **0 errors.**
  luau-analyze was not run.
* **Spawn order:** `check_nightwatch` (the join and spawn assertions from `robloxemu/SPAWN-ORDER.md`) is green.
  `Main.server.luau` is untouched.
* **Untouched:** the other games, `robloxemu/emu`, `tools/`, `docs/` and every `marketing/` folder. The only files
  outside `nightwatch-manor/` written by this work are `robloxemu/check_nightwatchmanor_*.luau` and
  `robloxemu/build/nightwatch-manor.luau`. `robloxemu/check_nightwatch_hud.luau` shows as modified in git: an
  `overlap = true` line from 2026-09-17, not this work.

---

## 9. Mutation sweep

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
   windows, the particles, the flicker and the tint. Is night 40 visibly a different place from night 1, or only a
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
   * Whether to add an in-game "reduce flashing" toggle as well is an owner decision (§13).
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

---

## 12. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *This recipe has not been tried in Studio. Check step 2 before
relying on the rest.*

1. **Build a fresh place with the new client.** In `nightwatch-manor/`, run
   `rojo build -o NightwatchManor-shots.rbxlx` and open that file (`*.rbxlx` is git-ignored).
2. **No saves.** Turn *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server then
   warns "DataStore unavailable — running without saves" and runs anyway. A fresh profile starts at
   `Config.Night.StartNight` with `StartStash` relics, and nothing reaches the live DataStore or the leaderboard.
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`. Nothing is published from Studio. For all
   shots:
   * `Watcher.SightRange = 0`: the Nightwatcher never sees you, so it patrols and never hunts. Stay more than 7 studs
     from it, because its catch radius still applies.
   * `Night.DreadSeconds = 900`, `Night.DreadMin = 900`, `Night.DreadPerNight = 0`: a long, calm night. Dread nudges
     the look toward the NEXT band only on a band's last night, so the nights below are pure.
   * Per shot, `Night.StartNight` as given.
4. **Play solo.** The first player's zone is index 1: the safehouse floor is centred at **(3000, 100, 0)** and the
   manor's foyer at **(3000, 100, -400)**. Every coordinate below is a world coordinate, from the real generator
   (`Manor.plan` for `WorldSeed 20260909`, probed). The manor door is on the safehouse's south wall.
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

**The six shots:**

1. **"The Blood Moon in the Portrait Hall"** (store-page hero; `StartNight = 20`).
   * The Portrait Hall at (2960, 100, -400) is the room west of the foyer, through a doorway, and not on night 20's
     patrol. You can walk there.
   * Its west wall carries a portrait at (2941.5, 108, -406) and a window at (2940.6, 107.5, -394), side by side.
   * Avatar at (2976, 104, -401). Camera from (2974, 106.5, -397) looking at (2941, 107.5, -400).
   * **In frame:** the huge blood-red moon behind swaying velvet curtains; the portrait's amber eyes looking back
     at you; dust in the air; the ceiling fixture's flicker on the walls.
   * Wait for a bolt (every 14-26 s): the glass blinks white and the room is lit from the window. Take a burst.
2. **"THE BLOOD MOON RISES"** (the fanfare; `StartNight = 19`, `Night.StartStash = 100000`).
   * Before the night, buy upgrades on the pads until the hub level is 20 or more (the Haven tier: every prop and
     the bigger fire). Enter the manor, take the Servants' Exit, and wait in the safehouse.
   * About 1.2 s into the day, after the server's own "YOU GOT OUT" toast, the card "🩸 THE BLOOD MOON RISES"
     appears, with a flash and an FOV punch. Hide only the HUD for this one (`g.NightwatchHud.Enabled = false`): the
     card belongs to the Haunt UI.
   * Camera from (3013, 109, 20) looking at (2988, 105, -28).
   * **In frame:** the two south windows either side of the manor door, now showing the blood moon over the distant
     manor with its lit windows; the armchairs and rug in the foreground; the card mid-screen.
   * The card lasts 4.5 s. Take a burst.
3. **"Rest by the fire"** (`StartNight = 20` or later, hub level ≥ 20 as in shot 2).
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
5. **"The Witching Hour"** (`StartNight = 40`).
   * Night 40's manor also has a Portrait Hall at (2960, 100, -400), but **no doorway from the foyer**: either way
     round passes through one room on the patrol (review 4 corrected "two"). Teleport:
     `PivotTo(CFrame.new(2976, 104, -401))`.
   * Its west wall has the window at (2940.6, 107.5, -394) and the portrait at (2941.5, 108, -406).
   * Avatar at (2976, 104, -401). Camera from (2974, 106.5, -397) looking at (2941, 107.5, -400): the same framing
     as shot 1, on purpose. Shots 1 and 5 side by side show the progression.
   * **In frame:** the eclipse (a black moon with a pale corona) on a green-black sky; rain; the eyes at full glow;
     the deepest flicker. Lightning every 5-11 s.
6. **"Something comes through the wall"** (a hazard; `StartNight = 20`; also `Hazards.IntervalMin = 6`,
   `Hazards.IntervalMax = 8`).
   * Stand in the dining room at (3000, 100, -360), north of the foyer through a doorway and off night 20's patrol.
     Keep the normal camera, pitched a little down. (With `SightRange = 0` the Nightwatcher never sees you, so a
     launch is never held back by a chase.)
   * Within about 8 s the banner says `⚠️ WRAITH INCOMING` or `FLYING CROCKERY`. Frame the hazard coming through
     the wall on its lane line, the ⚠️ marker over it, and the ring on the floor at your feet. The wraith's eyes are
     violet now, not green.
   * Keep the Haunt UI on for one variant, so the banner shows. Step out of the ring after the capture: getting
     knocked down ends the shot.

---

## 13. Not done / open

* **One independent adversarial review so far (review 4, §14), all four findings closed.** The fixes have not been
  reviewed by anyone else yet. What it could not check headless is on the Studio list: how long the knock's
  get-up really takes, whether the fog or haze hides the Nightwatcher at 55 studs, and whether the lightning light
  (range 34, no shadows) shining through walls reveals it in the next room.
* **Owner decision: an in-game "reduce flashing" toggle.** Flashing is now bounded (one lightning flash per 4 s at
  most, blinks at most twice a second, none while resting) and Roblox's own Reduced Motion setting turns every flash
  off (§5 rule 4, if the property name holds in Studio). An in-game toggle on the chip row would reach players who
  never open Roblox's settings. It costs a button in a crowded phone layout. Not built.
* **Owner decision (existing design, surfaced by the pacing model):** the bands, like the night counter, reward
  leaving early. A cautious player reaches the Blood Moon in 29 minutes, a greedy one in 37.
* **Not covered by Reduced Motion:** the unchanged core HUD's own one-off effects (`Hud.client.luau`): a red screen
  flash and shake when you are CAUGHT, a purple flash when EVICTED, a shake on SPOTTED, an FOV punch on EXTRACTED.
  They are single events, not repeated flashing, and `Hud.client.luau` is outside the eye-candy work (its diff is
  empty by design). Honouring the setting there too is a small, separate change to the core game.
* **Owner decision (review 4):** hazards now come once per 2-3 minutes in the manor for everyone. A player who is hunted
  a lot sees some of them straight after a chase (they were held back during it). If that feels like piling on in
  Studio, the alternative is to let a chase push the next hazard back (the old frozen clock). But then a player who
  hides well gets more hazards than one who is often seen. That is the unfairness review 4 found.
* **luau-compile and luau-analyze were not available** in this session's scratchpad (only `luau.exe`). Every source,
  spec and check (44 files) was compiled with `loadstring` instead: 0 errors. luau-analyze was not run.
* Not built: audio (still the biggest gap in a horror game, and it needs assets); silhouettes in the manor's own
  windows (the safehouse's view of the manor has its passing figure; a figure outside a manor window was left out,
  because a dark shape at head height in a window is exactly the kind of thing a player could take for the hunter).
* Not committed, not pushed, not published. Studio not opened.
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
