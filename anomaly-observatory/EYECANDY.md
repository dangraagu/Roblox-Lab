# Anomaly: Night Shift — the sky outside the observatory

Owner's brief (Gustav, 2026-09-17): every game richer and never monotonous, with the environment
changing as the player progresses in a way that fits the game; rare, telegraphed hazards; a way to
rest that can never be exploited; a thumbnail shot list for the night Studio session.

What that means in THIS game: it is spot-the-difference horror. The hall is rebuilt every pass and
is either clean or wrong in exactly ONE way, so any other change inside the hall would read as an
anomaly and break the game. The environment therefore changes **outside** the hall only: the night
sky beyond the concourse's open end progresses with your **Day** streak. There are **no hazards**:
nothing chases you is the premise, so nothing here ever touches the player.

**State (2026-10-01): built, unit-tested, headless-tested through the real server and both clients,
mutation-tested, independently reviewed twice.** The second review (2026-09-30) reported seven findings: all
seven reproduced and closed (§0c), and re-measured closed on 2026-10-01 (§0g). The three owner decisions are
DECIDED (§0d), and queued job A, the Field Guide highscore board, is built (§0e). The 2026-10-01 night added the
critters (the harmless rare events) and closed the last silent no-ops (§0f); both were mutation-tested on
2026-10-01 (§0g). Pass 2 of 2026-10-01 gave every band its own weather and its own light, the last two band items
of the standard (§0h). **Nothing seen in Studio yet** (§8). Nothing was committed, pushed or published.

---

## 0i. Night shift 2026-10-09: Studio check and the second review of db6d889 + 3c67595

**Studio** (job H step 1): see `STUDIO.md`. The doorway sky, the single moon, the break (B) and the Field Guide
sign all work. Three things are weak and **none is fixed yet**:
- the aurora reads as flat planks;
- the storm is near-black;
- The Other Sky's ring runs behind the unbacked caption text.

**Second review** (job H step 2). One independent read-only reviewer was asked to refute both commits. It
found no HIGH. Its verdicts:
- **db6d889: SHIP.** One doc nit: the client writes `CelestialBodiesShown` at startup, outside a break.
- **3c67595: SHIP-WITH-DEFERRED.**

It confirmed these hold:
- the 0..24 clamp in encode and decode;
- only the server writes;
- a catch is only the server's own roll answered correctly;
- `UpdateAsync` only raises the value;
- writes only on an increase, at most once per 6 s;
- the friends fetch is capped at 200, cached, in a pcall, and stops at budget 10;
- names are never stored;
- read-only sessions merge as a union;
- the break is free (client camera and Lighting only, restored);
- the checks drive the real bundled Main.server.

Findings, none fixed tonight:
1. **MEDIUM. The 11 spare-based anomalies can be read from the client.** `hide()` and `show()` toggle
   `Transparency`, `CanCollide`, `CanTouch` and `CanQuery` (and the figure's PointLight), and those values
   replicate (`Main.server.luau:586-601, 737-751`). A script can read the answer without a clean reference.
   The board cap of 24 still holds; the cost is the tie-break. A bot at `MIN_PASS_SECONDS = 0.75` could take
   the earliest 24/24 slots. The R12 note (`Main.server.luau:997-1000`) and the commit message overstate the
   protection.
2. **MEDIUM. No `RunService:IsStudio()` gate on any DataStore**, including `AnomalyObsGuide_v1`.
   - A Studio playtest with API access on (as §8 items 20-21 ask) writes the developer's catches to the live
     public board.
   - Suspected: a Local Server test with negative UserIds writes `u_-1` keys. Those take top-10 slots that
     `userIdFromKey` then drops.
3. **LOW.** If both saves of a wrong call's reset fail, the next join restores the already-answered run.
4. **LOW.** A friends fetch keeps running after its player leaves.
5. **LOW.** The player's own row is trimmed off a friends board when they rank 11th or lower
   (`Main.server.luau:1386-1389, 1419-1421`).
6. **LOW, suspected.** `publishGuide` can yield ahead of `saveProfile` on leave and in BindToClose.

**Publish** is held until findings 1-2 are fixed or decided and the robloxemu gates run (no luau CLI tonight).

## 0h. 2026-10-01, pass 2: every band's own weather and its own light (standard §2)

`docs/complete-game-standard.md` §2 asks every band for its own light, colour, scenery, critters **and weather**.
Checked item by item on arrival, two were short: weather fell in 1 of 8 bands (the storm's rain), and no band had
a light of its own (the reason, "the hall must never change", was written only as "the sky casts no light"). Both
are built now, failing-test-first. Nothing else in the game changed: no server code, no HUD, no hall.

**Weather.** Every band has its own, or says why its sky is clear (`clearSky` on the band; `validate` refuses a
band with neither, as it does for critters). Each kind is a FEATURE, so it glides in and out with its band, and one
ParticleEmitter on its own invisible host out in front of the entrance (hall-local z 39-89), where the storm's rain
always fell: the player sees it from the start pad looking out, and stands in it on a break (asserted: the break
camera is inside every kind's fall).

| band | weather | particles/s | alive at most | nearest reach (studs beyond the hall origin) |
|---|---|---|---|---|
| 🌙 Clear Night | thistledown drifting on the breeze (with the fireflies: a still late-summer night) | 5 | 70 | 24.3 |
| 🌠 Meteor Shower | **clear**: "a meteor shower is watched under a clear, dry sky: only the meteors fall tonight" | — | — | — |
| 🌌 Aurora | light snow under the curtains | 20 | 200 | 28.2 |
| ☄️ The Great Comet | frost: diamond dust glittering in still, frozen air | 12 | 108 | 29.3 |
| ⛈️ Storm Front | the rain (unchanged since 2026-09-23) | 40 | 48 | 27.1 |
| 🔭 Deep Sky | **clear**: "the clearest, driest night of all: any weather would veil the faint nebulae and the galaxy" | — | — | — |
| 🪐 The Alignment | dry leaves blowing past (an autumn dusk) | 4 | 40 | 28.0 |
| 👁️ The Other Sky | pale motes rising, slowly, the wrong way | 8 | 112 | 26.9 |

The nearest reach is `NightSky.envelopes`: the host grown by the fall or rise (Speed max x Lifetime max), the drift
(x sin(spread)), the breeze (0.5 x Wind x Lifetime², along X only, never toward the hall) and a particle; `validate`
refuses any kind that reaches the entrance plane + Clearance (16), falls any way but down or up, emits nothing,
exceeds the particle budget on its own, or names a colour outside the palette (so never red). The emitter budget
went from 2 to 3 (the stars and two weathers while one band glides into the next; still the template's
`EnvBands.capRates`, in code); the hardest reset, from the Comet's glide into the storm back to Day 1, wants 4 at
once, so the cap binds there and holds 3.

**Light.** The hall must never change, so the sky casts no light and writes no Lighting while a pass can be seen.
A band's own light is therefore the telescope break's colour grade: the one time the sky writes Lighting, with the
camera out and the hall out of view. Every band has `light = { tint, brightness, contrast, saturation }`, blended by
Day like any band value (`NightSky.breakLight`), worn by the break's `ColorCorrectionEffect` when the camera goes
out and followed if the Day changes during the break:

| band | tint | brightness | contrast | saturation | the mood |
|---|---|---|---|---|---|
| Clear Night | 228, 236, 255 | 0.03 | 0.05 | 0.30 | cool moonlight (the old single grade, tinted) |
| Meteor Shower | 215, 228, 255 | 0.02 | 0.08 | 0.25 | a deeper blue |
| Aurora | 215, 255, 232 | 0.04 | 0.06 | 0.40 | a green cast |
| The Great Comet | 225, 245, 255 | 0.06 | 0.05 | 0.30 | cold and bright |
| Storm Front | 210, 216, 228 | **-0.04** | 0.12 | **-0.15** | dim and grey (the dimmest and greyest, asserted) |
| Deep Sky | 226, 222, 255 | -0.02 | **0.15** | 0.35 | dark and sharp (the most contrast, asserted) |
| The Alignment | 255, 242, 220 | 0.03 | 0.06 | 0.30 | warm, amber |
| The Other Sky | 220, 255, 238 | 0.00 | 0.10 | -0.10 | pale green, drained |

No tint is red (`validate`, `isReddish`), every band has one or none does, and the grades stay gentle (asserted
|brightness| <= 0.1, |contrast| <= 0.2, |saturation| <= 0.5; `validate` caps 0.2 / 0.5 / 1). The rest check
still proves the grade is on only while the camera is out.

**Failing first** (scratch `ao4/`): weather: `NightSky.spec` 275 passed / 3 failed (the detailed tests wait for
`bandWeather` / `emitterRates`), `SkyConfig.spec` 120 / 12, `check_anomalyobservatory_weather` stopped at its first
band (`weather_before.log`: no `emitterRates`). Light: `NightSky.spec` 326 / 1, `SkyConfig.spec` 152 / 12,
the weather check 61 / 1 (`weather_light_before.log`; the per-band line `breakLight names the band's light` was
added right after, so a missing `breakLight` now fails at every band). Three assertions were written after the
build and are proved by their mutants instead: the emitters are built as Config says (WX3, WX12), and the light
follows a Day that changes during a break (LX7). **One real defect was caught by the check and by no spec**:
`wearLight()` followed by a line that starts with `(` is ambiguous Luau, so `Sky.client` did not compile (only
robloxemu loads the client; fixed with `;`). Final: `NightSky.spec` 341 / 0, `SkyConfig.spec` 181 / 0,
`check_anomalyobservatory_weather` 96 / 0.

**Measured through the real server and client** (`check_anomalyobservatory_weather`, Days reached by answering
passes, the glide settled; 4 239 frames):

| Day | band | emitters on (particles/s) | the light on the break (tint; brightness, contrast, saturation) |
|---|---|---|---|
| 1 | Clear Night | stars 5.5, thistledown 5.0 | 228,236,255; 0.030, 0.050, 0.300 |
| 6 | Meteor Shower | stars 7.0 | 215,228,255; 0.020, 0.080, 0.250 |
| 12 | Aurora | snow 20.0, stars 7.0 | 215,255,232; 0.040, 0.060, 0.400 |
| 18 | The Great Comet | frost 12.0, stars 8.0 | 225,245,255; 0.060, 0.050, 0.300 |
| 25 | Storm Front | rain 40.0, stars 2.5 | 210,216,228; -0.040, 0.120, -0.150 |
| 34 | Deep Sky | stars 10.0 | 226,222,255; -0.020, 0.150, 0.350 |
| 44 | The Alignment | leaves 4.0, stars 10.0 | 255,242,220; 0.030, 0.060, 0.300 |
| 55 | The Other Sky | motes 8.0, stars 10.0 | 220,255,238; 0.000, 0.100, -0.100 |

On every frame every falling weather was measured off the real emitter (host corners, speed, lifetime, spread,
acceleration, size): nearest reach 24.3 studs beyond the hall origin (entrance 10 + clearance 6); nothing fell
toward the hall, nothing was red, no Light, the character never moved; at most 3 emitters on and at most 60
particles a second on every frame; a wrong call glided the weather back to the first night's; the reset from Day 21
wanted 4 emitters and had at most 3 on.

**The shot list says the weather.** Five of the six thumbnails now have weather falling in the frame, so every
shot in `marketing/ShotList.luau` names it (`weather`: snow, frost, rain, clear, leaves, motes) and its note tells the
night shift; `check_anomalyobservatory_shots` measures the emitters on at each shot against it (failing first: 68 / 11;
final 79 / 0). No side word was added to the prose.

**Mutation sweeps** (scratch `ao4/sweep.py`, the driver of §0g unchanged; `ao4/sweep.log`, `sweep2.log`,
`sweep_results.json`, `sweep2_results.json`). Each mutant in its own copy of the game and the emulator: exactly ONE
occurrence replaced, sha256 of the target before and after, the bundle rebuilt and proved to carry the mutation
(21 of 21 runs that edit a game source; the shot list is `require`d by its check directly). The real tree's sha256s
were unchanged by both sweeps.

| id | mutation | result |
|---|---|---|
| WX1 | `bandWeather` forgets the storm's rain | killed by `NightSky.spec`, `SkyConfig.spec`, `_weather` |
| WX2 | `emitterRates` stops clamping a weight to [0, 1] | killed by `NightSky.spec` |
| WX3 | every weather falls: the motes no longer rise | killed by `_weather` (built as Config says) |
| WX4 | the breeze blows toward the hall (-Z) | killed by `_weather` |
| WX5 | `validate` no longer asks for weather or a `clearSky` reason | killed by `NightSky.spec` |
| WX6 | the weather envelope ignores the drift | killed by `NightSky.spec` |
| WX7 | SkyArt asks only for the stars and the rain (the old code) | killed by `_weather` |
| WX8 | no cap on how many emitters are on | killed by `_weather` (the Day-21 reset: 107 frames over 3), `_cap` |
| WX9 | the emitter budget back at 2 | killed by `SkyConfig.spec` |
| WX10 | the Meteor Shower loses its `clearSky` reason | killed by `SkyConfig.spec`, `_weather` (validate turns the sky off) |
| WX11 | the snow's host 30 studs out (its drift reaches the entrance) | killed by `SkyConfig.spec`, `_weather` |
| WX12 | every weather emitter built from the snow's numbers | killed by `_weather` |
| LX1 | `breakLight` ignores the band's tint | killed by `NightSky.spec`, `SkyConfig.spec` |
| LX3 | the break wears its first light forever | killed by `_weather` |
| LX4 | `validate` lets a band's light be red | killed by `NightSky.spec` |
| LX5 | the storm's light brightened to +0.04 | killed by `SkyConfig.spec` |
| LX6 | the grade's contrast takes the brightness | killed by `_weather` |
| LX7 | the light no longer follows a Day that changes during a break | killed by `_weather` |
| LX8 | the break goes out without wearing the light | **survived: equivalent**. `goOut` runs on the fully black frame and the next frame wears the light before the fade lets anything through |
| SX1 | shot 1 says frost where the snow falls | killed by `_shots` |
| SX2 | shot 4's note no longer says its sky is clear | killed by `_shots` |
| CTL1-CTL3 | thistledown spins at 45 deg/s, not 40; the leaves glow a touch (LightEmission 0.05); shot 5's note reworded (each against all 29 suites) | **survived, as they must** |

21 mutations, 20 killed, 1 equivalent survivor (LX8); 3 controls, 3 survived.

---

## 0g. 2026-10-01 morning: the review findings, the owner decisions and job A, re-measured

The previous run of this pass stopped after the work in §0f, before its write-up and before any mutation test.
On arrival every gate was green (§7). This session changed no game source: it re-measured the three items
against today's tree, mutation-tested the night's work, added one assertion, and wrote these notes.

| # | review finding (2026-09-30) | measured today on the current tree | mutant today |
|---|---|---|---|
| 1 | the anomaly named by the Instance tree | the reviewer's own probe (110 passes, to Day 111): anomalous passes told apart by child names alone **0 of 62** (he measured 25 of 64); `check_anomaly_names` 77 / 0 | F1 (`DoorExtra` built again): killed by `check_anomaly_names` |
| 2 | the honest caption guarded only by "safe" | his mutant D1v run against all 28 suites | F2: killed by `NightSky.spec` |
| 3 | a dropped break kept saying "Keep still." | his probe: from 0.8 s (walked) to 3.3 s the caption reads `☕ Break cancelled: you moved. ...`, then `Next sky: ...`; never "queued" after the walk | F3: killed by `_rest` |
| 4 | the phone's join tip lost to a band and a wrong call | his probe (640x300 touch): after the wrong call the button is still highlighted, and the first break's caption carries the join tip | F4: killed by `_news` |
| 5 | budgets held only by tests | his mutant B1 (the ring at 80 segments): `validate` refuses it, the sky stays off | F5: killed by `SkyConfig.spec` and `_sky` |
| 6 | the shot list in two copies | §9 holds no table and **0** side words; the check `require`s `marketing/ShotList.luau`, the one copy | F6 (shot 1's moon mirrored in that list): killed by `_shots` |
| 7 | the entrance an unguarded drop | his probe: nothing collidable beyond z = 10; `check_anomaly_spawn`: **195 of 195** lines out of the hall blocked before the floor ends | F7 (the pane not collidable): killed by `_spawn` |

All seven stay closed; none is reopened. **Owner decisions:** none open (§0d, last paragraph). **Job A** (§0e):
`Highscore.spec` 36 / 0 and `check_anomaly_board` 51 / 0. One gap found and closed: the board check never fed a
fabricated value to the FRIENDS board, which reads each friend with `GetAsync`, outside the public query's
window, so a `decode` that stopped clamping survived it (only `Highscore.spec` caught it). New assertion: a
friend whose stored value claims 99 types shows `24/24`. Real build: `1. User_7004  24/24`, 51 passed; on mutant
A1 (decode unclamped, proved in the bundle): `1. User_7004  99/24`, 50 passed, 1 failed.

**Mutation sweeps** (scratch `ao3/sweep.py`, the 2026-09-30 driver unchanged; `ao3/sweep1.log`, `sweep2.log`,
`sweep_results.json`, `sweep2_results.json`). Each mutant in its own copy of the game and the emulator: exactly
ONE occurrence replaced, sha256 of the target before and after, the bundle rebuilt and **proved to carry the
mutation** (the mutated bundle equals the baseline bundle with that single replacement: 33 of 33 runs that
edit a game source, mutants and controls; F6 changes `marketing/ShotList.luau`, which the check requires
directly). The real tree's sha256s were
unchanged by both sweeps (sweep 1's report names `check_anomaly_board.luau`, which this session edited on
purpose while it ran).

| id | mutation | result |
|---|---|---|
| F1-F7 | the seven findings, above | all killed |
| A1 | `decode` stops clamping a fabricated count | killed by `Highscore.spec`; re-run with the new assertion: also `_board` |
| A2 | the public query loses its cap window | killed by `_board` |
| W1 | H twice on one hall charges twice again | killed by `_walk` |
| W2 | the hint flag not reset per pass (a new hall's answer free) | killed by `_walk` |
| W3 | an over-long code dropped without a reply | killed by `_walk` |
| W4 | a code inside the Redeem cooldown dropped without a reply | killed by `_walk` |
| W5 | a tint picked inside the cooldown vanishes | killed by `_walk` |
| W6 | an older waiting tint wins over a newer pick | killed by `_walk` |
| W7 | the HUD stops saying the second hint is free | killed by `_walk` |
| K1 | `critterPick` ignores `Chance` | killed by `NightSky.spec` |
| K2 | the kind follows the raw roll (no `jitter`) | killed by `NightSky.spec` |
| K3 | `critterAlpha` ignores the band's weight | killed by `NightSky.spec`, `_critters` |
| K4 | no fade in or out | killed by `NightSky.spec`, `_critters` |
| K5 | `validate` accepts a band with no critters and no reason | killed by `NightSky.spec` |
| K6 | `validate` lets a kind outlast the slot | killed by `NightSky.spec` |
| K7 | a flight is never landed at its end | **survived**: equivalent (alpha is exactly 0 from the end of the fade-out) |
| K8 | a new slot does not land the previous flight | **survived**: near-equivalent (§10: at most 8.3 % opaque, one frame's window) |
| K7b | a landed flight parked visible | killed by `_critters`, `_sky` |
| K8b | the client flies every kind in every band | killed by `_critters` |
| K9 | the bats 12 studs out | killed by `SkyConfig.spec`, `_critters` |
| K10 | the owl red | killed by `SkyConfig.spec`, `_critters` |
| K11 | the Storm Front loses its reason | killed by `SkyConfig.spec`, `_critters` |
| CTL1-CTL4 | fireflies blink at 1.4 s, not 1.3; the name cache bound 2500, not 2000; the storm's reason reworded; the friends cache 121 s, not 120 (each against all 28 suites) | **survived, as they must** |

29 mutations, 27 killed, 2 (near-)equivalent survivors; 4 controls, 4 survived. Of the night's own work (W, K):
20 mutations, 18 killed.

---

## 0f. The 2026-10-01 night: critters, no silent no-ops, the whole player path

Three items of `docs/complete-game-standard.md` that the 2026-09-30 round left open, built failing-test-first.
That run stopped before this write-up and before any mutation test; both were done on 2026-10-01 (§0g). Its
failing-first logs are in the scratchpad (`ao2/*_before.log`), and every final assertion was run again on
2026-10-01 against the tree as it was before that night (a scratch copy whose 51 game files match that night's
arrival sha256s): `NightSky.spec` 224 passed / 11 failed, `SkyConfig.spec` 93 / 10, `check_anomaly_walk`
55 / 12, `check_anomalyobservatory_critters` stops at its first line (there is no `Config.Sky.Critters`). On
the final tree: 274 / 0, 118 / 0, 67 / 0, 46 / 0.

* **Critters (standard §2: every band has its own; the harmless rare events this genre gets instead of
  hazards).** `fireflies` (Clear Night, and Deep Sky at half weight), `bats` across the moon (Meteor Shower,
  the Alignment), `geese` under the aurora (Aurora, the Alignment), an `owl` along the ridge (the Comet, Deep
  Sky), `wisps` near the second moon (The Other Sky). The Storm Front has none and says why in Config
  (`critterless`: animals shelter from a storm); `validate` refuses a band with neither. Each kind is a sky
  FEATURE, so it glides in and out with its band; a flight fades with its band (`NightSky.critterAlpha`) so a
  band leaving mid-flight never cuts it off (before `critterAlpha` existed, the critters check caught six
  fireflies vanishing at transparency 0.02-0.65 when their band left mid-flight: `ao2/critters_pop_before.log`,
  44 passed, 2 failed). One flight per 45 s slot at most, `Chance` 0.3 x the kinds' weight:
  measured 6000 of 20000 slots at full weight (0.40 a minute, one about every 2.5 minutes). Through the real
  client, at Days reached by answering passes: 3 flights in 6.0-7.5 simulated minutes in every band but the
  storm (0.40-0.50 a minute), 0 in 10.5 minutes of storm, each band only its own kinds, exactly the flights
  the pure schedule names, slot by slot; on every one of 62 721 frames every visible critter was at least
  104.0 studs beyond the hall origin (entrance 10 + clearance 6), none reddish, collidable, touchable or
  ray-queryable, never two kinds at once, and the character never moved. Peak sky parts 99 (§6).
* **No silent no-ops (standard §1).** H pressed twice on one hall used to charge two hints (the prompt has
  no cooldown): the second press now shows the same answer free and the HUD says `(this hall's hint, no extra
  cost)`; the flag resets every pass. A second code inside Redeem's 2 s cooldown now answers `One code at a
  time: nothing was used, send it again in a moment.`, and a pasted code over 64 characters answers `Unknown
  code` (both used to vanish after the HUD cleared its box). A second tint tapped inside SetTint's 0.5 s
  cooldown is applied when the cooldown ends (the last pick wins) instead of vanishing.
* **The whole player path, headless (standard §1).** `robloxemu/check_anomaly_walk.luau` (67 assertions):
  spawn, walk the hall over the floor, answer right and wrong, catch a type into the Field Guide, redeem codes,
  spend a hint and a tint, leave and rejoin on the saved run, every reading taken off the HUD.
* **The long-term goal, measured (standard §2).** `Pacing.spec` (+9) simulates the Field Guide with the same
  player model: expected minutes to first reach 1 / 8 / 16 / 24 of 24 types: fast 0.4 / 4.2 / 12.5 / 61.1,
  normal 0.6 / 6.9 / 34.7 / 391.8, slow 1.2 / 13.7 / 160.1 / 6 354.9. The full guide is a long-term goal
  (over twice the headline sky for a normal player) that a skilled player can finish in an evening. These
  nine assertions measure the test-side model, so they pass on the old game too (45 / 0): they guard no
  game code.

---

## 0c. Review round 2 (2026-09-30): seven findings, all reproduced, all closed

Each finding was reproduced first (measurement below), then got a test that failed on the unfixed build for
the reviewer's reason, then a fix in the game (never in the test). Every new or changed assertion was also
run, in its final form, against the untouched pre-round build (`git archive HEAD`, scratch `ao1/base`) and
failed there: `check_anomaly_names` 66 passed / 11 failed, `check_anomaly_spawn` 12 / 5 (the entrance and the
spawn), `check_anomalyobservatory_news` 10 / 5, `check_anomalyobservatory_rest` 67 / 6,
`check_anomaly_rejoin` 12 / 21, `NightSky.spec` 199 / 9, `SkyConfig.spec` 90 / 2; `check_anomaly_board` and
`Highscore.spec` cannot load (there was no Highscore module). The mutation sweep is in §7.

| # | finding (severity) | reproduced | failing test first | fix |
|---|---|---|---|---|
| 1 | The anomaly's identity replicated as Instance NAMES (`DoorExtra`, `TelescopeTwin`, `Fog`, a `Figure` Model; `Telescope`, `Plant`, `Chair4` destroyed): a labelled answer, the class the `PassInfo` move closed (medium) | new `robloxemu/check_anomaly_names.luau` forces every catalog id through the game's own Config and compares the zone's replicated tree (every path, name and class, in order) with the clean hall's: **11 of 24 ids** differ by the tree alone (the reviewer saw 10 in play; `door_extra` is the 11th, as predicted) | the same check: 66 passed, 11 failed on the old build | everything an anomaly can add is built into EVERY hall, hidden (`hide`: Transparency 1, no collide / touch / query / shadow, the figure's red eye off); everything it can remove is hidden in place; appliers only `show`/`hide` and move. The tree is now identical on every pass: **0 of 24**. Proof that no anomaly changed its look: the visible parts and lit lights of the clean hall and of all 24 anomalies, before vs after, are **byte-identical (25 halls, 907 rows)**. What a script can still do is diff PROPERTIES against a clean hall it recorded: R12, the cost the game accepts (`Main.server.luau`) |
| 2 | The honest break caption was guarded only by the word "safe": "your streak is kept while you rest, nothing is lost" passed every gate (low) | by construction: the guards were `find("safe")` (spec and rest check) | `NightSky.spec` now pins all 8 caption templates word for word and applies a promise deny-list (safe, saved, kept, nothing is lost, not lost, won't/will not lose, protect, surviv, guarantee, secure) to every non-idle caption and every caption of a session that does not save; a CONTROL proves the deny-list catches the reviewer's sentence | the captions changed for owner decision D1 (§0d): the idle warning says "saved" only when the server says this session saves the run (`SavesRun`), otherwise "saving is off" |
| 3 | A dropped break request kept saying "Break queued ... Keep still." for up to 4 s while nothing could start (low) | `check_anomalyobservatory_rest`: press Break mid-air, land walking, walk 0.6 s, keep still: the caption still said "queued ... Keep still." | the same section: 2 failures on the old build | `Sky.client` handles Rest's `dropped`: "☕ Break cancelled: you moved. Press 🔭 Break (B) again when you are standing still." (phone: "☕ Break cancelled: you moved.") |
| 4 | On a phone the first band overwrote the join tip, and a wrong call before the first break cleared the only invitation (low) | new `check_anomalyobservatory_news.luau` (640x300 touch, one fresh join): after the band-up and a wrong call the button was plain, the first break said "🌠 Meteor Shower", the second said nothing new | 9 passed, 4 failed on the old build | pending news is a small set (`intro`, `band`); a wrong call removes only the band; a break shows ONE item, the join tip first, and the button stays highlighted until the rest is seen |
| 5 | Part, beam and trail budgets were enforced only by tests (low) | the reviewer's mutant (the ring at 80 segments) passed `validate`: 164 layout pieces | `NightSky.spec` (`budgetOf` and three refusals) and `SkyConfig.spec` (the reviewer's ring, and 12 aurora curtains = 14 beams) failed | `NightSky.budgetOf` counts what the layout builds with every feature on (parts; beams: aurora curtains + the comet's 2; trails: one per pooled meteor) and `validate` refuses anything over `Config.Sky.Budget`, which turns the sky off with a warning. Shipped: 102 parts / 140, 6 beams / 8, 2 trails / 4 |
| 6 | The shot list lived in two copies, and the check read only its own (low) | the check has no way to read markdown (the luau CLI has no file IO): whatever §9's prose said, it passed | the list moved; the check now asserts the new rules below | **one copy**: `marketing/ShotList.luau` (data AND prose). The check `require`s it; the night shift prints it (`luau marketing/print_shotlist.luau`, §9). A side of the frame may enter the prose only through a measured `where` (the check fails on any side word in free text, with a CONTROL), and every printed number (positions, the avatar's centre, 13 flashes, the pan) is re-measured within 0.05 |
| 7 | The open entrance was an unguarded drop into the void (low) | `check_anomaly_spawn`: from just behind the start pad, **195 of 195** lines out through the doorway (floor to ceiling) met nothing collidable before the floor ended | the same section: 1 failure on the old build | an invisible pane (`EntranceGlass`, 20 x 16 x 0.5 at z 9.5..10, Transparency 1, collidable) keeps the feet in and leaves the view, the photos and the camera alone (the default camera's occlusion ignores parts over 0.25 transparency): **0 of 195** open. The fall itself needs Studio (§8) |

---

## 0d. Owner decisions (the owner, 2026-09-30: "take the recommended option for all")

Every open owner decision in this file, `CLAUDE.md` and the review notes. Where no option was marked
recommended, the choice is the one that best serves the owner's brief: fair, fun, never punishing, never
exploitable.

* **D1. The streak and the idle kick (§10 before this round). DECIDED 2026-09-30 (owner: take recommended).**
  No option was marked. Taken: **save the run, with its live pass.** Why: the brief says "never punishing" and,
  for rest, "you must be able to press pause"; a 20-minute idle kick, a phone switching apps or a dropped
  connection cost a whole streak (the headline is ~34 minutes in). The exploit the old note named (leave
  mid-pass, rejoin, get a fresh hall) is closed by saving the pass itself. What is built (`Main.server.luau`,
  `robloxemu/check_anomaly_rejoin.luau`, 33 assertions):
  * the profile carries `run = { id, day, pass }`, written by every save while the session holds the lock;
  * a rejoin restores the Day AND the same hall (same roll, same anomaly, part for part), which then scores;
  * a wrong call starts a new run (new id, Day 1, **no pass**: the death toast just told the player its
    answer) and is **flushed at once**, so leaving during the death beat does not undo it;
  * a session locked out of the save starts read-only from the stored run; when it wins the lock it keeps its
    own progress only if the stored run is still the one it loaded, or it made its own wrong call; if the
    stored run changed meanwhile (the other session's reset), the stored run wins: **a run ended by a wrong
    call can never be resumed from a stale copy**;
  * a malformed stored run is ignored; one whose anomaly this catalog no longer has keeps its Day and rolls;
  * the player's `SavesRun` attribute says whether this session saves (the break's idle caption promises
    "saved" only then). Residual: a server that crashes between a wrong call and its flush (one DataStore
    write) leaves the pre-reset run stored; players cannot crash servers at will.
* **D2. The slow player (§10 before this round). DECIDED 2026-09-30 (owner: take recommended).** The file's
  own recommendation was "left as designed" (lowering the late thresholds would make the headline cheap for
  good players), and it is taken: no band Day moved. `Pacing.spec` still shows what any retune does. D1 helps
  the slow player where it can without cheapening anything: a disconnect no longer costs them the climb.
* **D3. The optional brag (§10 before this round). DECIDED 2026-09-30 (owner: take recommended).** No option
  was marked. Taken: **show it**: the HUD's Best line carries the emoji of the highest sky band that Best Day
  has fully reached (`Best: Day 34 🔭`; nothing on the first night). Why: the standard asks for a brag moment
  (§2), it is fun, and it cannot be exploited (it reads the Best Day the server already publishes). Pure
  `NightSky.bragEmoji` (spec: 7 assertions), the HUD line asserted in `check_anomalyobservatory_news`.

Searched again on 2026-10-01 (this file, `CLAUDE.md`, `README.md`, `MARKETING.md`, every source and test; the
game has no `REVIEW*.md`): D1-D3 are the only owner decisions there have been, all three DECIDED 2026-09-30
(owner: take recommended). The 2026-10-01 night opened none.

---

## 0e. Queued job A: the Field Guide highscore board (design approved 2026-09-16)

Built as designed. A sign on the right-hand wall just behind the start pad (hall-local x 9.3, z 0..4, within
the prompt's 12 studs of the spawn point) ranks players on Field Guide completion: anomaly types caught,
`Codex.countKnown(prof.caught, ...)`, 0-24, ties broken by who reached that count FIRST.
* **Store:** a NEW OrderedDataStore `Config.Save.GuideStore` ("AnomalyObsGuide_v1"), key `u_<userId>`, value
  `caught * 2e9 + (2e9 - reachedAtUnix)` (`src/shared/Highscore.luau`, spec 36 assertions). Written only when
  the count goes UP (UpdateAsync keeps the larger value, so a write can never lower the board), throttled per
  player to one write per 6 s with the autosave flushing what waits, behind the same save-lock gate as the
  Best-Day board. `reachedAt` is recorded in the profile (`guide = { count, at, published }`). Only ids this
  catalog knows count, so a profile carrying retired ids publishes at most 24. `leaderstats.Best` and the
  Best-Day store are unchanged.
* **Public:** `GetSortedAsync(false, 10)` inside `Highscore.range` (one type caught .. 24 with any tie-break),
  so a fabricated value above the cap is never even fetched; one fetch per server per 60 s, shared by every
  sign; names via `GetNameFromUserIdAsync` (or the Player in the server), cached in memory, never stored.
* **Friends:** only when the player switches the sign (**L**, gamepad Y, or a tap on the prompt):
  `Players:GetFriendsAsync`, the first 200, one `GetAsync` per friend on the new store, stopping early if the
  server's GetAsync budget falls to 10, all pcall'd, cached per player 120 s (a failure 15 s). The player's
  own row joins from memory. An empty board says why: "None of your friends has caught an anomaly yet. The
  Field Guide has 24 to find: bring one along!", "Add friends on Roblox to compare Field Guides here.", or
  "Couldn't reach Roblox for your friends list. Try again in a minute."
* **Where, and why there:** outside the capture rig's frame and outside the hero thumbnail's frame (the check
  projects the sign's corners into both cameras): the pairs must not differ by a scoreboard, and no thumbnail
  may carry a player's name. It is not part of the zone model (the hall is rebuilt each pass and its tree must
  not change), and its SurfaceGui is on the part (robloxemu's HUD gate walks everything in PlayerGui as a
  screen panel).
* **Headless:** `robloxemu/check_anomaly_board.luau` (50 assertions; 51 since 2026-10-01, when a friend's
  fabricated value joined the cap test, §0g): placement, both boards and their order,
  the fabricated and foreign entries left out, the toggle and its prompt text, the three empty-board texts,
  exactly 200 of 300 friends looked up, one public fetch per window, writes only on a new type (and no request
  at all otherwise), the 24 cap against a 30-id profile, no names stored.
* **What it cannot stop (R12):** a scripted client can still diff the hall's properties against a clean hall it
  recorded and answer every pass. The board is capped at 24, so that buys a cheater at most the tie-break
  (reaching 24 sooner), never a higher score.

Also from `docs/complete-game-standard.md` §1, done in this round: every player gets a real, enabled
**SpawnLocation** on their own start pad (invisible, intangible, no force-field bubble) and
`plr.RespawnLocation` points at it, set BEFORE the profile load yields, so the engine itself places them in
their hall (`check_anomaly_spawn`: 9 new assertions, including the ordering, measured with a yielding load).

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

That owner decision (making "nothing is lost" true across a disconnect) is DECIDED 2026-09-30 (§0d, D1): the
run is saved with its live pass, which closes the exploit this note named (leave mid-pass, rejoin, get a fresh
hall).

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

Not touched in that round: `src/server/Main.server.luau`, `src/client/Hud.client.luau`, every other shared
module, `robloxemu/emu`, the existing `check_anomaly*.luau` gates.

The 2026-10-01 night (§0f), in the game: `Config.Sky.Critters` + one critter kind per band (`critterless` for the
storm), `NightSky` (the critter schedule, paths, fades and `validate` rules), `SkyArt` (the pooled flock),
`Main.server.luau` (H twice is free, Redeem and SetTint answer every refusal), `Hud.client` (the free re-shown
hint). New: `check_anomaly_walk`, `check_anomalyobservatory_critters`; extended: `NightSky.spec`, `SkyConfig.spec`,
`Pacing.spec` (+ `NightModel.simulateGuide`), `check_anomalyobservatory_sky` (critters are live). On the
morning of 2026-10-01 (§0g) only `check_anomaly_board` changed (one assertion), besides these notes.

Pass 2 of 2026-10-01 (§0h), in the game: `Config.Sky` (`Weather` with five kinds; on every band its weather
feature or a `clearSky` reason, and its `light`; five palette colours; `Budget.MaxEmitters` 3), `NightSky`
(`WEATHER`, `bandWeather`, `emitterRates`, `breakLight`, the weather hosts in `layout`, their `envelopes`, the weather
and light rules in `validate`), `SkyArt` (`_weatherEmitter`; the emitters ask `emitterRates`), `Sky.client`
(`wearLight`), `marketing/ShotList.luau` (each shot's weather). New: `check_anomalyobservatory_weather`; extended:
`NightSky.spec`, `SkyConfig.spec`, `check_anomalyobservatory_shots`.

Review round 2 and the owner decisions (2026-09-30), in the game: `Main.server.luau` (the constant hall tree:
`hide`/`show` and the spares; `EntranceGlass`; the saved run; the Field Guide board; the per-player
SpawnLocation), `Highscore.luau` (new), `NightSky` (`budgetOf` + three `validate` refusals, the saved/unsaved
idle captions, `bragEmoji`), `Sky.client` (a dropped request says so, pending news as a set, `SavesRun`),
`Hud.client` (the brag on the Best line), `Config` (`Save.GuideStore`, `Config.Guide`),
`marketing/ShotList.luau` + `print_shotlist.luau` (new: the one shot list). New checks:
`check_anomaly_names`, `check_anomaly_rejoin`, `check_anomaly_board`, `check_anomalyobservatory_news`, and
`tests/Highscore.spec`; extended: `check_anomaly_spawn` (entrance, SpawnLocation), `check_anomalyobservatory_rest`
(dropped request, the idle variants), `check_anomalyobservatory_shots` (reads the one list),
`NightSky.spec`, `SkyConfig.spec`. `robloxemu/emu` and every other game untouched.

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

**Critters** (2026-10-01, §0f): every band also has its own wildlife, now and then crossing the night beyond
the entrance: fireflies over the valley (Clear Night), bats across the moon (Meteor Shower), geese under the
aurora (Aurora), an owl along the ridge (the Comet), fireflies and the owl at half weight (Deep Sky), geese and
bats at half weight (the Alignment), pale wisps near the second moon (The Other Sky); none in the Storm Front
(animals shelter, and the band says so in `Config.Sky`).

**Weather and light** (2026-10-01 pass 2, §0h): every band also has its own weather, falling (or rising) out in
front of the entrance: thistledown (Clear Night), snow (Aurora), frost glitter (the Comet), the rain (Storm Front),
dry leaves (the Alignment), pale motes rising (The Other Sky); the Meteor Shower and Deep Sky are clear skies and
their bands say why. And its own light, which can only be the telescope break's colour grade, because the hall is
never lit differently: cool moonlight, a deeper blue, a green cast, cold and bright, dim and grey (the storm), dark
and sharp (Deep Sky), warm amber, pale green. Both glide with the band like everything else.

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

**The harmless rare events are the critters** (2026-10-01, §0f; the standard's alternative to hazards for a
genre where a knock-down is wrong). One flight per 45 s slot at most, `Chance` 0.3 x the band's critter weight:
0.40 a minute at full weight (pure: 6000 of 20000 slots), about one every 2.5 minutes, never two at once.
Measured through the real client (`check_anomalyobservatory_critters`), at Days reached by answering passes:

| Day | band | flights | in | per minute | kinds flown |
|---|---|---|---|---|---|
| 1 | Clear Night | 3 | 6.0 min | 0.50 | fireflies x3 |
| 6 | Meteor Shower | 3 | 6.8 min | 0.44 | bats x3 |
| 12 | Aurora | 3 | 7.5 min | 0.40 | geese x3 |
| 18 | The Great Comet | 3 | 6.7 min | 0.44 | owl x3 |
| 25 | Storm Front | **0** | 10.5 min | 0.00 | (none, by design) |
| 34 | Deep Sky | 3 | 6.7 min | 0.44 | fireflies x1, owl x2 |
| 44 | The Alignment | 3 | 7.5 min | 0.40 | bats x2, geese x1 |
| 55 | The Other Sky | 3 | 6.7 min | 0.44 | wisps x3 |

A flight lasts 5-12 s and fades in and out over its first and last tenth; it never touches, lights or moves
anything (62 721 frames watched, nearest visible critter 104.0 studs beyond the hall origin).

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
  last break: a new band (`🌠 Meteor Shower tonight.`), or on a phone the join tip (one piece of news per
  break, the join tip first; the button stays highlighted until the rest is seen). It never says the Day is
  "safe" (review 2026-09-24), and outside the idle warning it promises nothing about keeping progress
  (every template is pinned in `NightSky.spec`, review 2026-09-30);
* once Roblox reports the player idle (`Player.Idled`, about 2 minutes without any input), the caption
  becomes, in a session that saves the run (owner decision D1, the player's `SavesRun`): `☕ Still there?
  Roblox disconnects players idle for 20 minutes. Day N and this hall are saved: rejoin to carry on. Move or
  press ▶ to go back.` (phone: `☕ Idle 20 min = disconnect. Day N is saved. Move!`); in a session that does
  not: `☕ Still there? Roblox disconnects players idle for 20 minutes, and saving is off right now: Day N
  would be lost. Move or press ▶ to go back.` (phone: `☕ Idle 20 min = disconnect; saving is off. Move!`).
  Any input clears it; a mouse move does not end the break, moving the character does;
* **move, jump, press B or the button again** and it fades back, with the camera, Lighting and field
  of view exactly as they were;
* a break asked for in mid-air, or during the 3 s death beat after a wrong call, is queued
  (`☕ Break queued: it starts when this moment is over. Keep still.`) and starts the first moment you
  stand still on the floor; walking on drops it, and says so at once (`☕ Break cancelled: you moved. Press
  🔭 Break (B) again when you are standing still.`, review 2026-09-30); it expires after 4 s;
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
applies. What changed on 2026-09-30 (owner decision D1, §0d) is what the kick costs: the run, the Day
AND the live hall, is saved while the session holds the save lock, so a player who idles out on a break
rejoins on the same Day in the same hall (`check_anomaly_rejoin`). A session that could not take the lock
does not save, and its idle warning says so. The break itself still pauses, protects and saves nothing;
the first version's caption (`Day N is safe`) was the first review's first finding, and the second review
found the guard against it too narrow (§0c, finding 2).

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| bands, moon, every sky piece, meteors, lightning, rain, turning stars, the break, the button and caption | **client** (`Sky.client` + `SkyArt`, pure `NightSky` / `EnvBands` / `Rest`) | cosmetic and per-player (your sky follows *your* Day); costs the server nothing and replicates nothing |
| the Day, the pass, the roll, the hall, scoring, saves, the leaderboard | **server** (unchanged) | authoritative, as before |

**Leak review.** (2026-09-30: plus the player's own `SavesRun` attribute, whether this session saves the
run, which the HUD already shows as its read-only notice; it says nothing about the pass.) The client reads
its own `leaderstats.Day`, its own zone's `Index` attribute (to
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
every one of 28 146 frames including every band change and the reset. Re-measured 2026-10-01 pass 2 with the
weather (one invisible host per kind while its band shows; scratch `ao4/logs/w2`), and before that with the
critters (each kind's pool of parts exists while its band shows, whether or not a flight is in the air).

| Days | band | parts | emitters (particles/s) | beams | trails (in flight) | lights |
|---|---|---|---|---|---|---|
| 1-2 | Clear Night | 33 | 2 (10.5) | 0 | 0 | 0 |
| 3 | › Meteor Shower | 38 | 2 (8.8) | 0 | 0 | 0 |
| 4-7 | Meteor Shower | 31 | 1 (7.0) | 0 | 0-1 | 0 |
| 8 | › Aurora | 38 | 2 (17.0) | 4 | 0-1 | 0 |
| 9-12 | Aurora | 35 | 2 (27.0) | 4 | 0-1 | 0 |
| 13-14 | › Comet | 39 | 3 (25.2 / 21.8) | 6 | 0-1 | 0 |
| 15-19 | The Great Comet | 33 | 2 (20.0) | 6 | 0-1 | 0 |
| 20-21 | › Storm Front | 46 | 3 (25.8 / 36.7) | 6 | 0 | 0 |
| 22-28 | Storm Front | 41 | 2 (**42.5**) | 2 | 0 | 0 |
| 29-30 | › Deep Sky | 59 | 2 (34.1 / 18.4) | 2 | 0 | 0 |
| 31-36 | Deep Sky | 44 | 1 (10.0) | 0 | 0-1 | 0 |
| 37-39 | › Alignment | 60 | 2 (10.6-13.4) | 4 | 0-1 | 0 |
| 40-45 | The Alignment | 53 | 2 (14.0) | 4 | 0-1 | 0 |
| 46-49 | › Other Sky | **101** | 3 (14.4-17.6) | 4 | 0-1 | 0 |
| 50+ | The Other Sky | 92 | 2 (18.0) | 4 | 0-1 | 0 |

| metric | measured peak | budget (`Config.Sky.Budget`) |
|---|---|---|
| local parts | **101** (the glide into The Other Sky, Day 46: both bands' pieces, critter pools and weather hosts) | 140 |
| particle emitters on | 3 (stars + two weathers in a glide; the reset from Day 21 wants 4 and the cap holds 3) | 3 |
| particles per second | **42.5** (rain 40 + stars 2.5, storm) | 60 |
| beams | 6 (aurora 4 + comet tail 2) | 8 |
| trails | 1 (a meteor in flight) | 4 |
| lights | **0**, always | 0 (validate refuses anything else) |
| hazards at once | 0 (there are none; the critters fly one flight at a time) | — |

**Held in code since 2026-09-30 (review finding 5):** `NightSky.budgetOf` counts what the layout builds with
every feature on and `validate` refuses a config over `Budget`, which turns the sky off with a warning instead
of building it on a phone. Measured 2026-10-01 pass 2: **126 parts** (102 + the critters' pool of 19 + the five
weather hosts), 6 beams, 2 trails, against 140 / 8 / 4; no Day has every feature on at once. `SkyConfig.spec` asserts it still fits the
budget. A break adds one `ColorCorrectionEffect` on the camera and no parts. The nine storm clouds each carry
one `SpecialMesh` (Sphere), which is not a Part.

**Sizes the engine draws as written (review finding 4).** robloxemu keeps any size; Roblox forces a
`Ball` uniform, draws a `Cylinder` round (Y = Z) and clamps every Part axis to 2048 studs. `validate`
refuses a layout that breaks any of these (`NightSky.engineSizeOk`), and the sky check measures every
built Part against them. A flattened sphere is an `Ellipsoid`: a Block with a Sphere mesh that fills it.

**The emitter cap is enforced in code, not only by the numbers.** SkyArt switches emitters on through
the template's `EnvBands.capRates` (at most `MaxEmitters`, the strongest first, summed rate scaled
under `MaxEmitterRate`). With the numbers of 2026-09-24 (stars 10/s, rain 40/s) the cap could not bind, so a
mutant that bypassed it survived the first sweep. Since pass 2 it binds on its own on the hardest reset (Day 21
back to Day 1 wants stars, frost, rain and thistledown at once): `check_anomalyobservatory_weather` measures at most
3 on, every frame. `check_anomalyobservatory_cap` makes it bind (a
budget of one emitter at 30/s, in memory, this run only) and plays through the Storm Front: on every
one of 1 965 frames at most one emitter is on and the rate is at most 30/s; the one kept is the rain,
scaled to 30/s, the stars step aside, and come back after a reset.

**What is pooled / how it stays cheap:** each feature's parts are built the first time it shows and
**unparented, not destroyed,** when its weight reaches zero (a band you are not in costs no draw
calls; a mutant that kept them parented is killed); the meteors are a pool of 2 parts that alternate
by time slot; lightning is one three-segment bolt; the aurora is 4 Beams on one invisible host; the
comet's tail is 2 Beams on its head; the stars, the rain and each weather kind are one emitter each. Writes are skipped
when a value has not changed, so a settled sky costs a handful of writes a frame: the aurora's sway
(2 curve sizes per curtain) and The Other Sky's 24 turning stars at 10 Hz, plus whatever meteor or
bolt is in flight. The glide writes at most one transparency per part per frame, and only changes
over 0.004 until it settles. These are part and emitter counts, not frame rate; frame time on a
phone is on the Studio list.

---

## 7. Gates

### 2026-10-01, pass 2: the weather and the light (§0h)

Every gate run on arrival and twice on the final tree, bundle rebuilt from it each time (scratch logs
`ao4/logs/arrival`, `final1`, `final2`; all exit 0; the two final bundles are byte-identical). Arrival is the tree
the morning (§0g) left.

| gate | arrival | **final (run 1 / run 2)** |
|---|---|---|
| `tests/Anomaly.spec` | 36 / 0 | 36 / 0 |
| `tests/Codes.spec` | 10 / 0 | 10 / 0 |
| `tests/Codex.spec` | 26 / 0 | 26 / 0 |
| `tests/EnvBands.spec` | 124 / 0 | 124 / 0 |
| `tests/Highscore.spec` | 36 / 0 | 36 / 0 |
| `tests/NightSky.spec` | 274 / 0 | **341 / 0** |
| `tests/Pacing.spec` | 45 / 0 | 45 / 0 |
| `tests/Progression.spec` | 22 / 0 | 22 / 0 |
| `tests/Rest.spec` | 55 / 0 | 55 / 0 |
| `tests/Rng.spec` | 32 / 0 | 32 / 0 |
| `tests/SkyConfig.spec` | 118 / 0 | **181 / 0** |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 |
| **spec total** | **848 / 0** | **978 / 0** |
| `robloxemu/check_anomaly` (HUD fit, overlap on) | PASS | PASS |
| `robloxemu/check_anomaly_attrs` | 323 / 0 | 322 / 0, 322 / 0 (per-session salt) |
| `robloxemu/check_anomaly_board` | 51 / 0 | 51 / 0 |
| `robloxemu/check_anomaly_names` | 77 / 0 | 77 / 0 |
| `robloxemu/check_anomaly_rejoin` | 33 / 0 | 33 / 0 |
| `robloxemu/check_anomaly_spawn` | 21 / 0 | 21 / 0 |
| `robloxemu/check_anomaly_walk` | 67 / 0 | 67 / 0 |
| `robloxemu/check_anomalyobservatory_cap` | 12 / 0 | 12 / 0 |
| `robloxemu/check_anomalyobservatory_critters` | 46 / 0 | 46 / 0 |
| `robloxemu/check_anomalyobservatory_events` | 24 / 0 | 24 / 0 |
| `robloxemu/check_anomalyobservatory_hud` | 26 / 0 + PASS | 26 / 0 + PASS |
| `robloxemu/check_anomalyobservatory_news` | 15 / 0 | 15 / 0 |
| `robloxemu/check_anomalyobservatory_occlusion` | 80 / 0 | 80 / 0 |
| `robloxemu/check_anomalyobservatory_rest` | 73 / 0 | 73 / 0 |
| `robloxemu/check_anomalyobservatory_shots` | 67 / 0 | **79 / 0** (each shot's weather) |
| `robloxemu/check_anomalyobservatory_sky` | 78 / 0 | 78 / 0 |
| `robloxemu/check_anomalyobservatory_weather` | — | **96 / 0** (new) |

The mutation sweeps of this pass are in §0h. Summed, the gates take 370 s (run 1) and 350 s (run 2) on 8 parallel
workers; the slowest are the sky (64-68 s), critters (57-58 s), events (51-54 s), weather (45-47 s) and occlusion
(46-47 s) checks.


### 2026-10-01: the night (§0f) and the morning (§0g)

Every gate run on arrival and twice on the final tree, bundle rebuilt from it each time (scratch logs
`ao3/logs/arrival`, `final1`, `final2`; all exit 0). The final bundle is byte-identical to the arrival bundle: no
game source changed this morning. "Before the night" is the 2026-09-30 final (§7 below).

| gate | before the night | arrival | **final (run 1 / run 2)** |
|---|---|---|---|
| `tests/Anomaly.spec` | 36 / 0 | 36 / 0 | 36 / 0 |
| `tests/Codes.spec` | 10 / 0 | 10 / 0 | 10 / 0 |
| `tests/Codex.spec` | 26 / 0 | 26 / 0 | 26 / 0 |
| `tests/EnvBands.spec` | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/Highscore.spec` | 36 / 0 | 36 / 0 | 36 / 0 |
| `tests/NightSky.spec` | 221 / 0 | 274 / 0 | 274 / 0 |
| `tests/Pacing.spec` | 36 / 0 | 45 / 0 | 45 / 0 |
| `tests/Progression.spec` | 22 / 0 | 22 / 0 | 22 / 0 |
| `tests/Rest.spec` | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Rng.spec` | 32 / 0 | 32 / 0 | 32 / 0 |
| `tests/SkyConfig.spec` | 92 / 0 | 118 / 0 | 118 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 |
| **spec total** | **760 / 0** | **848 / 0** | **848 / 0** |
| `robloxemu/check_anomaly` (HUD fit, overlap on) | PASS | PASS | PASS |
| `robloxemu/check_anomaly_attrs` | 322 / 0, 327 / 0 | 321 / 0 | 327 / 0, 328 / 0 (per-session salt) |
| `robloxemu/check_anomaly_board` | 50 / 0 | 50 / 0 | **51 / 0** (the friends cap) |
| `robloxemu/check_anomaly_names` | 77 / 0 | 77 / 0 | 77 / 0 |
| `robloxemu/check_anomaly_rejoin` | 33 / 0 | 33 / 0 | 33 / 0 |
| `robloxemu/check_anomaly_spawn` | 21 / 0 | 21 / 0 | 21 / 0 |
| `robloxemu/check_anomaly_walk` | — | 67 / 0 | 67 / 0 |
| `robloxemu/check_anomalyobservatory_cap` | 12 / 0 | 12 / 0 | 12 / 0 |
| `robloxemu/check_anomalyobservatory_critters` | — | 46 / 0 | 46 / 0 |
| `robloxemu/check_anomalyobservatory_events` | 24 / 0 | 24 / 0 | 24 / 0 |
| `robloxemu/check_anomalyobservatory_hud` | 26 / 0 + PASS | 26 / 0 + PASS | 26 / 0 + PASS |
| `robloxemu/check_anomalyobservatory_news` | 15 / 0 | 15 / 0 | 15 / 0 |
| `robloxemu/check_anomalyobservatory_occlusion` | 80 / 0 | 80 / 0 | 80 / 0 |
| `robloxemu/check_anomalyobservatory_rest` | 73 / 0 | 73 / 0 | 73 / 0 |
| `robloxemu/check_anomalyobservatory_shots` | 67 / 0 | 67 / 0 | 67 / 0 |
| `robloxemu/check_anomalyobservatory_sky` | 78 / 0 | 78 / 0 | 78 / 0 |

The mutation sweeps of the morning are in §0g. Run one after another the gates take about 6.5 minutes (388 s
summed in `final1`); the slowest are the sky (74 s), critters (63 s), events (55 s) and occlusion (49 s) checks.

### Review round 2 (2026-09-30): the final gates

Every gate, run twice on the final tree (bundle rebuilt from it each time; scratch logs `ao1/logs/final1`,
`ao1/logs/final2`). Before this round every gate was green too (scratch `ao1/baseline_summary.txt`).

| gate | before round 2 | **final (run 1 / run 2)** |
|---|---|---|
| `tests/Anomaly.spec` | 36 / 0 | 36 / 0 |
| `tests/Codes.spec` | 10 / 0 | 10 / 0 |
| `tests/Codex.spec` | 26 / 0 | 26 / 0 |
| `tests/EnvBands.spec` | 124 / 0 | 124 / 0 |
| `tests/Highscore.spec` | — | **36 / 0** (new) |
| `tests/NightSky.spec` | 194 / 0 | **221 / 0** |
| `tests/Pacing.spec` | 36 / 0 | 36 / 0 |
| `tests/Progression.spec` | 22 / 0 | 22 / 0 |
| `tests/Rest.spec` | 55 / 0 | 55 / 0 |
| `tests/Rng.spec` | 32 / 0 | 32 / 0 |
| `tests/SkyConfig.spec` | 89 / 0 | **92 / 0** |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 |
| **spec total** | **694 / 0** | **760 / 0** |
| `robloxemu/check_anomaly` (HUD fit, overlap on) | PASS | PASS |
| `robloxemu/check_anomaly_attrs` | 321 / 0 | 322 / 0, 327 / 0 |
| `robloxemu/check_anomaly_names` | — | **77 / 0** (new) |
| `robloxemu/check_anomaly_rejoin` | — | **33 / 0** (new) |
| `robloxemu/check_anomaly_board` | — | **50 / 0** (new) |
| `robloxemu/check_anomaly_spawn` | 11 / 0 | **21 / 0** |
| `robloxemu/check_anomalyobservatory_sky` | 78 / 0 | 78 / 0 |
| `robloxemu/check_anomalyobservatory_rest` | 67 / 0 | **73 / 0** |
| `robloxemu/check_anomalyobservatory_hud` | 26 / 0 + PASS | 26 / 0 + PASS |
| `robloxemu/check_anomalyobservatory_events` | 24 / 0 | 24 / 0 |
| `robloxemu/check_anomalyobservatory_cap` | 12 / 0 | 12 / 0 |
| `robloxemu/check_anomalyobservatory_occlusion` | 80 / 0 | 80 / 0 |
| `robloxemu/check_anomalyobservatory_shots` | 48 / 0 | **67 / 0** |
| `robloxemu/check_anomalyobservatory_news` | — | **15 / 0** (new) |

`check_anomaly_attrs` moves with the server's per-session salt, as before; every other count is identical
across the two runs.

**Mutation sweep, round 2** (scratch `ao1/sweep.py`, list `ao1/make_muts.py`, log `ao1/sweep1.log`, results
`ao1/sweep_results.json`). For every mutation, in its own fresh copy of the game and the emulator: the target's
sha256 recorded, exactly ONE occurrence replaced, the bundle rebuilt and **proved to carry the mutation** (the
mutated bundle equals the baseline bundle with that single replacement: 37 of 37 source mutants; the four
shot-list mutants change `marketing/ShotList.luau`, which the check requires directly), the listed suites run;
a suite that exits non-zero, times out or prints no summary counts as a kill. Controls run all 26 suites. The
real tree's sha256s (every source, test, check and the bundle) were identical before and after the sweep.
**38 mutations, 38 killed; 3 controls, 3 survived.**

| id | mutation | killed by |
|---|---|---|
| N1 | `door_extra` builds a new part named `DoorExtra` again | names |
| N2 | `hide` leaves a hidden part collidable | names |
| N3 | the hidden figure's red eye left on | names |
| N4 | `scope_gone` destroys the Telescope again | names |
| E1 | the entrance pane not collidable | spawn |
| E2 | the entrance pane covers only the top half | spawn |
| B1 | `validate` no longer checks the part budget | `NightSky.spec`, `SkyConfig.spec` |
| B2 | `budgetOf` forgets the comet's beams | `NightSky.spec` |
| B3 | the reviewer's mutant: the ring at 80 segments | `SkyConfig.spec`, sky (the sky turns off) |
| D1 | the `dropped` branch gone | rest |
| P1 | a wrong call clears the join tip with the band | news |
| P2 | a break consumes every pending item | news |
| C1 | the reviewer's D1v: "your streak is kept while you rest, nothing is lost" (run against all 26 suites) | `NightSky.spec` (two pinned templates and the deny-list) |
| C2 | the client says "saved" whatever the server says | rest |
| C3 | an unsaved phone's idle warning claims the Day is saved | `NightSky.spec` |
| R1 | a wrong call not flushed | rejoin |
| R2 | a wrong call keeps the failed pass in the run | rejoin |
| R3 | a session that wins the lock never adopts a changed stored run | rejoin |
| R4 | a session adopts the stored run over its own wrong call | rejoin |
| R5 | a rejoin re-rolls instead of restoring the pass | rejoin |
| R6 | `SavesRun` true for a session locked out of the save | rejoin |
| G1 | `bragEmoji` counts the first night | `NightSky.spec` |
| G2 | the HUD drops the brag | news |
| H1 | the tie-break not clamped | `Highscore.spec` |
| H2 | `decode` does not clamp a fabricated count | `Highscore.spec` |
| H3 | the public query without the cap window | board |
| H4 | the friends cap ignored | board |
| H5 | `publishGuide` writes without a new count | board (the request counter) |
| H6 | the sign built inside the hall that is rebuilt every pass | board |
| H7 | the sign moved into the capture rig's frame | board |
| H8 | an empty friends board says nothing | board |
| H9 | the public list re-read on every use | board |
| W1 | `RespawnLocation` set after the profile load | spawn |
| W2 | the spawn gives a force-field bubble | spawn |
| S1 | shot 1's moon mirrored in the list | shots |
| S3 | a side word slipped into free prose | shots |
| S4 | the pan note turned the other way | shots |
| S5 | a printed position that is not the measured one | shots |
| K1-K3 | the board's title punctuation; a failed friends fetch retried after 16 s, not 15; the dropped caption's last words reworded | **survived all 26 suites, as they must** |

**TDD order, honestly.** Every new assertion was written before its fix and watched failing for the stated
reason, and the final versions were run once more against the untouched pre-round build (§0c, top). The
exceptions: fixes to the CHECKS themselves while they were new (the board check expected ten rows where the
seeded foreign key legitimately takes a fetched slot; it forced an anomaly by shrinking the catalog, which
also shrank the board's cap; the names check first read an unset light as off), each described where it
happened (§0e, `CLAUDE.md` traps).

### Review round 1 (2026-09-24) and before


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

Added 2026-09-30 (review round 2, the owner decisions, job A):

18. **The entrance glass** (finding 7): walk, run and jump at the doorway from inside: you stop at it and
    never fall out; nothing is drawn there; the default camera does not bump into it (it is Transparency 1,
    and Poppercam only stops at parts under 0.25); the view out to the sky is unchanged.
19. **The hidden spares** (finding 1): on a CLEAN pass nothing shows or can be felt where the spare door,
    the spare telescope, the extra mirror, the mist and the figure hide (walk through each spot; the figure's
    red eye must be dark), and on each of those eleven anomalies the hall looks exactly as it did before
    (headless: the visible parts and lights of all 25 halls are byte-identical; Roblox's own rendering of a
    shown-again part is the open question).
20. **The Field Guide sign** (job A): readable from the start pad (text 10-15 px on a 50 px-per-stud board in a
    dark hall, `LightInfluence` 0); its prompt and the hint prompt both show at the spawn without fighting
    (keys L and H; gamepad Y and X; a tap on a phone); a real friends list (`GetFriendsAsync` pages, names)
    and a real account with 200+ friends (the GetAsync budget stop, "Checked N of M friends").
21. **The saved run** (owner decision D1), with API access on: leave mid-pass and rejoin: the same Day and the
    same hall; make a wrong call and leave during the death beat: Day 1 on rejoin; the idle warning after
    about 2 minutes without input says "saved".
22. **The spawn**: the engine puts a fresh character on the start pad itself (no frame in the void), with no
    force-field bubble and no spawn decal visible (the SpawnLocation is created by script, Transparency 1).
23. **The brag** (owner decision D3): `Best: Day 34 🔭` fits the Best line on a small phone and the emoji
    renders.
24. **The dropped break** (finding 3): press B in mid-air, land walking: the caption says the break was
    cancelled because you moved.

Added 2026-10-01 (the critters and the silent no-ops, §0f):

25. **Can you see a critter at all?** They are small and far on purpose (a bat is 2.6 studs at 240, about
    10 px wide at 1080p; the geese 3 studs at 320; the owl 4 studs at 150), and the Horror preset's haze sits
    between. From the doorway and from the break camera: is a flight noticed, and does it read as an animal
    (bats flapping, a V of geese, a gliding owl) rather than as specks?
26. **Fireflies and wisps** blink and drift (Ball, the palette's green); with Bloom on, a glow or a smear? The
    wisps must not read as a second set of fireflies (they turn round their centre).
27. **Nothing living in the storm**: on Days 22-28 nothing flies, by design. Does the storm feel empty or
    right?
28. **A flight never in a thumbnail by accident**: a flight is 5-12 s once every ~2.5 minutes, so a still can
    catch one. Look at each shot; a bat across the moon is welcome in shot 1, a smear is not.
29. **H twice on one hall** (silent no-op fix): the second press shows the same answer and `(this hall's hint,
    no extra cost)`, and the Hints count does not move.
30. **The refusals that used to vanish**: two codes typed fast (the second says `One code at a time: ...`), a
    pasted paragraph in the code box (`Unknown code`), two tint swatches tapped fast (the second is put on
    half a second later).

Added 2026-10-01, pass 2 (every band's weather and light, §0h):

31. **Does each weather read as what it is?** From the start pad looking out, and from the break (the camera is
    inside every kind's fall): thistledown (0.35 studs, drifting), snow (0.45), frost (0.18, LightEmission 1: a
    glitter or invisible), dry leaves (0.6, ochre, tumbling), motes (0.3, rising). 39-89 studs out, through the
    Horror preset's haze; the knob is size and rate, never Lighting.
32. **What robloxemu cannot set**: `LightInfluence` 0 (so the night does not turn the flakes black), `Rotation`
    and `RotSpeed` (the leaves tumble) are written inside a `pcall`; confirm they took.
33. **Each band's light on the break**: does the grade read as a mood (the green cast under the aurora, the grey
    storm, the warm Alignment) or as a tinted filter; does it fight the Bloom; is the Clear Night still the
    cool moonlight it was.
34. **Frame time on a phone** with the snow (200 particles alive at most) under the aurora's beams, and on the
    glide into The Other Sky (101 parts, 3 emitters).
35. **Weather in the thumbnails**: shots 1 (snow), 2 (frost), 3 (rain), 5 (leaves) and 6 (motes) have weather in
    the frame (the shot list says which, and its gate measures it): take frames where nothing crosses a callout.

---

## 9. Thumbnail shot list (the night Studio session)

**One copy, and it is checked (review 2026-09-30, finding 6).** The shots live in `marketing/ShotList.luau`,
data and prose in one file. `robloxemu/check_anomalyobservatory_shots.luau` requires that file and plays it
against the real sky at 1920x1080 (67 assertions): every callout in the frame and on the side stated, every
printed position re-measured within 0.05, the moon's phase words and its lit side, the avatar and the doorway,
13 lightning flashes in the recorded minute, and the break-view pan. A side of the frame can enter the prose
only through a measured `where` field; the check fails on any side word anywhere else in the list. Print the
table from `anomaly-observatory/` (`luau.exe` is under `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/`):

    luau marketing/print_shotlist.luau

**Do not copy the table into this file.** A second copy here is exactly what drifted before: the first list had
every side of the frame mirrored, and the gate could not see the prose. (Why it happened is written at the top
of `ShotList.luau`: looking out of the entrance, Roblox's camera frame is not the world's.)

**Before the first shot**

1. **Build a fresh place file**: `rojo build -o Anomaly.rbxlx` from `anomaly-observatory/`. The
   `Anomaly.rbxlx` on disk (2026-09-17) predates the sky, and its `.lock` file says a Studio session
   had it open: close that session first.
2. Pin render quality to the maximum before pressing Play (as `tools/film_anomaly.py` does:
   Automatic drops Bloom whenever Studio is not the focused window, and every one of these shots is
   Neon + Bloom).
3. Play Solo. Your hall is index 1, origin **O = (1000, 100, 0)**; confirm with
   `workspace["Concourse_" .. game.Players.LocalPlayer.UserId]:GetAttribute("Index")`. All positions
   in the list are hall-local offsets from O (the hall runs toward -Z; the open entrance is at z = +10,
   closed to the feet by the invisible `EntranceGlass` since 2026-09-30, open to the eye and the lens).
4. Hide every ScreenGui (the capture rig's `HUD_OFF` snippet) and Roblox's own UI (client command
   bar: `game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`, which also hides the player
   list showing the Day). The sky's own gui never switches itself back on. **B still works with the
   guis hidden.** The Field Guide sign (a SurfaceGui on a part, not a ScreenGui) stays up, and it is
   outside every shot's frame (`check_anomaly_board` projects it into shot 1's camera).
5. **Setting the Day for a shot**: in the command bar in *Server* mode,
   `game.Players:GetPlayers()[1].leaderstats.Day.Value = N`. Only the sky reads it (the HUD takes
   its Day from the server's own state push; the Roblox player list shows it, see step 4); the
   server's streak is unchanged (and so is the saved run), so **do not answer a pass** during the session
   (the next answer would set the Day back to the real streak). Shoot the Days in the printed order and
   **wait 45 s after each change** (measured: in that order the sky has settled by then; nothing changes in
   30 s more).
6. **Break-view shots**: stand still on the floor, press **B**, keep hands off WASD (moving ends the
   break), capture about 1 s after pressing: the pan is then centred (yaw ≈ 0°, pitch ≈ 17°). The printed
   list's last line says how a capture 20 s in differs. B again to come back.
7. **Custom-camera shots**, client command bar (FROM and AT from the printed table):
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

If shot 1 or 6 comes out empty because of the haze (§8 item 1), shoot it again with the break's
values set by hand for the session (`Lighting.FxAtmosphere.Density = 0.2; Haze = 0.6`), and say so in
the shot's file name. Do not leave that change in the place file. If a second, phaseless moon shows up
anywhere, stop: §8 item 15 has failed.

Clips (vertical gameplay moments, not stills) are listed in `MARKETING.md`.

---

## 10. Still open

* **Pass 2 (§0h, the weather and the light) has had no review**: failing-first tests, a mutation sweep with
  controls, and one near-equivalent survivor on record (LX8: the break goes out without wearing its light; the next
  frame wears it, and the frame it skips is the fully black one).
* **Reviewed twice; the second round's fixes and the 2026-10-01 night (§0f) have not had a third review.**
  The review of 2026-09-30 found seven defects, all reproduced and closed (§0c, re-measured §0g); that round
  also carried the three owner decisions and job A. All of it is covered by failing-first tests and mutation
  sweeps with controls (§7, §0g), not by another pair of eyes.
* **Two survivors are on record as (near-)equivalent** (§0g): a flight never "landed" at its end (K7) is
  drawn at alpha exactly 0 from then on, so nothing changes on screen; a flight not landed when the next slot
  starts (K8) can differ only when a 12 s flight ends within one frame (the client clamps a frame to 0.1 s) of
  its slot's end, and then by members at most 8.3 % opaque. The suite kills the visible versions of both
  (K7b, K8b).
* **`luau-analyze` and `luau-compile` are not available** in this session: every source, test and check is
  executed by the gates (a syntax error fails them), but type noise was not reviewed.
* **Residual risks, stated:** (a) R12: a scripted client can still diff the hall's properties against a clean
  hall it recorded; on the Field Guide board that buys at most the tie-break (reaching 24 sooner), never a
  higher score. (b) The saved run: a server that crashes between a wrong call and its one-write flush leaves
  the pre-reset run stored. (c) The board's tie-break runs out on 2033-05-18 (unix 2e9): after that, equal
  counts are no longer ordered by time; counts stay correct (clamped). (d) Milestone badges are still a stub
  (`awardMilestone`) until real Badge asset ids exist.
* **The owner decisions** that were open here (the streak and the idle kick, the slow player, the optional
  brag) are DECIDED 2026-09-30 (owner: take recommended), §0d.
* Everything in §8.
