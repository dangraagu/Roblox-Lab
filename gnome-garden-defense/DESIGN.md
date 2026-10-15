# Gnome Garden Defense: design spec (v1)

**Build note, 2026-10-07 (later the same day): v1 is BUILT from this spec; see `CLAUDE.md` for the gates and
`EYECANDY.md` §10 for every place the build differs from it.** The Luau model ran (on a Luau-to-LuaJIT shim:
the luau CLI was still missing, CLAUDE.md "State") and printed the mirror's lines exactly once the sim moved to
`src/shared/Garden.luau` (brag median 33.6, p10 30.3, p90 53.3, worst 61.8; every win rate; `WaveTable` line for
line). `tests/mirror/` was moved to the session scratchpad, not deleted. The text below is the design as written.

Status at design time: **design only, no game code.** Every outcome number below was measured with the
balance model in `tests/`. Decisions (prices, timers, colours) carry a reason; outcomes (win rates,
minutes, rates) carry the command that printed them. Nothing here was opened in Studio, published or
committed.

**How the numbers were made, and one caveat.** The model is `tests/GardenModel.luau` and the gate is
`tests/Pacing.spec.luau` (written first, before the model existed). The luau CLI disappeared from the
scratchpad minutes into this session (`scratchpad/luau/` became empty and nothing restored it), so
**the Luau files have never been executed.** Every number was measured with a line-for-line JavaScript
mirror of the same model and spec, kept in `tests/mirror/` until the Luau run confirms it:

```
node tests/mirror/spec.js        # the spec's 26 assertions on the same seeds: 26 passed, 0 failed
node tests/mirror/waves.js normal  # the per-wave table (§5)
node tests/mirror/bands.js       # minutes at every band threshold, the Aurora goal, the hazard rate
node tests/mirror/bosssweep.js tests/mirror/none.json <chapter> <boss> <hp,hp,...>   # §5.3
node tests/mirror/ceiling.js tests/mirror/none.json   # the endless ceiling with unlimited seeds
node tests/mirror/report.js      # attempts per chapter, wave 1, economy per chapter, most bugs alive
node tests/mirror/tune.js tests/mirror/none.json   # compact metrics for a candidate override file (re-tuning)
```

Figures quoted as **tuning history** (rounds 1-10: earlier configurations, the seed-spill and daze
sweeps, the 120-180 s hazard interval) were measured with throwaway variants of these scripts and are
quoted only as the reason a number changed. Reproduce one by editing `tests/mirror/cfg.js`.

First job of the build: run `luau tests/Pacing.spec.luau` and `luau tests/WaveTable.luau normal`,
confirm they print the same lines as the mirror, then delete `tests/mirror/`.

Sources: `docs/complete-game-standard.md` (the finish line), `docs/new-game-checklist.md` (traps),
`robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md`, `anomaly-observatory/CLAUDE.md` ("ServerStorage,
not the zone"), radar entries 2026-09-14 #6 and 2026-09-06 #6 (+ its note), and the radar of 2026-10-05
#4 ("persistent progression instead of gacha rerolls"), which this design follows with chapter unlocks.

---

## 1. The core loop

Each player owns a garden bed on a shared 8-player server. A procedurally drawn path winds from the
hedge gap to your carrot patch, and waves of insects walk it. You tap a glowing pad beside the path
and plant a gnome (Pebble, Sprinkler, Mushroom or Lantern), the gnomes fire on their own, every bug
they stop pays seeds, and seeds plant more gnomes or upgrade them. Ten waves make a chapter (a
season), and the tenth wave brings the season's boss: stop it before it reaches the carrots, or the
patch is eaten and you try the chapter again on a fresh bed. Each won chapter unlocks the next season
and its new gnome. Chapter 3 ends with the Slug Queen under the Harvest Moon (the brag, about 34
minutes in). Chapter 4 ends with the Frost Mantis. After that, the endless Moonlit Bed (the same bed
for everyone that UTC day) ranks you on a public and friends board by the highest wave you survive.

---

## 2. The world

| thing | where / what | reason |
|---|---|---|
| server | 8 players, 8 garden slots in a 4 x 2 grid, slot footprint 140 x 130 studs, slot origins fixed and recycled | a fixed slot per player avoids the "unbounded coordinates" trap; 8 sims at 10 Hz with at most 35 bugs and 14 gnomes each is estimated light (measured in Studio, §17) |
| bed | 12 x 9 cells of 8 studs = 96 x 72 studs of lawn | 12 columns fit 3-5 vertical path runs 2 columns apart (the generator rule); 9 rows give room to wind |
| path | exactly 30 cells (240 studs) of gravel from the hedge gap (west edge) to the carrot patch (east edge) | fixed length: a bed's difficulty must not depend on luck. Pacing.spec asserts it |
| pads | every lawn cell touching the path (8-neighbourhood): **37-57 per bed** (measured, 200 seeds) | always more pads than the 14-gnome cap, so the cap, not the bed, limits a player |
| pad | 7 x 7 stud raised plate on the 8-stud pitch, faint rim glow; ClickDetector, MaxActivationDistance 150 | big tap target; 150 studs reaches the far corner of the bed from the deck. Pixel size on a phone is a Studio item (§17) |
| deck | 96 x 16 stud wooden deck along the bed's south edge; the player's SpawnLocation sits on it; the garden's board stands at its west end | the camera behind a player on the deck looks north over the whole bed |
| carrot patch | east end of the path; 20 carrots that visibly disappear | lives you can see |
| hedge | collidable perimeter around each slot | nobody walks off the world; the slot stays readable |
| sign | at each deck: owner name, wave, season | other players see where you are without any replicated secret |

---

## 3. Every number, with its reason

All of these become `src/shared/Config.luau` verbatim from `GardenModel.Config`.

### 3.1 Bed, timing, simulation

| name | value | reason |
|---|---|---|
| `Tile` | 8 studs | 7-stud pad + 1-stud gutter; a Roblox character is 2 studs wide, so pads read as plates, not tiles underfoot |
| `GridW`, `GridH` | 12, 9 | §2 |
| `PathCells` | 30 | 240 studs: an aphid (6 studs/s) needs 40 s to cross, so a wave of 8 is still on the path when its last bug spawns (7 x 0.9 s) |
| `Dt` | 0.1 s | fixed simulation step on the server; the fastest bug (ant, 10 studs/s) moves 1 stud per step, inside every range window; the model runs the same step |
| `Carrots` | 20 | a regular bug bites 1-3; a boss bites 20 (the whole patch), so a chapter is won only by stopping its boss (tuning round 3: when bosses bit 10, every boss walked through and nobody had to beat one) |
| `BuildSeconds` | 20 s between waves, READY skips it | the normal profile takes 14 s; a passive player still moves on |
| first wave of an attempt | **never auto-starts**; waits for READY | measured cliff: with a fixed 25 s a normal player had planted 1000 of the endless chapter's 2600 seeds when wave 41 arrived and lost it on 21 of 40 beds |
| `AfkHoldSeconds` | 180 s | the build timer does not auto-start the next wave unless the server saw activity (a step, a garden action, READY or PAUSE) in the last 180 s. The longest median wave measured is 137 s (wave 50) + 20 s build = 157 s, so a player who acts once per cycle never meets it |
| `WavesPerChapter` | 10 | one season per ten waves; measured, the normal profile finishes chapters at 8.6 / 20.3 / 33.6 / 57.4 min, retries included (§6) |
| `SpawnGap` | 0.9 s | waves of 8-36 bugs spawn in 6-31 s, shorter than a 40 s crossing: bugs overlap on the path |

### 3.2 Economy

| name | value | reason |
|---|---|---|
| chapter start seeds | 120 / 420 / 800 / 1500 / 2600 (chapter 5 = endless) | every attempt starts here on a fresh bed, nothing carries over, so every chapter is one measurable scenario. 120 = two Pebbles, the core action in the first seconds. The rest were tuned against the win-rate targets (§5) |
| bounty | kind's base x hpMult^0.4, rounded | income grows inside a chapter but slower than hit points (x1.075 per wave), so a chapter gets harder towards its boss; measured earnings per chapter (normal): 794 / 1421 / 2440 / 3752 |
| wave clear bonus | 15 + 3 x (wave number inside the chapter) | 18 after wave 1, 45 after wave 10: a steady drip that rewards surviving rather than farming |
| `SellRefund` | 0.7 of everything paid | lets a player fix a misplaced gnome; any buy/sell loop loses seeds |
| `MaxGnomes` | 14 per bed | with HpGrowth this is the wall that bounds the endless board: with **unlimited seeds** the strong profile still stops at waves 53-56 (`ceiling.js`) |
| Robux | nothing costs Robux in v1 | owner's rule: no gamepasses, no developer products, no gambling, no pay-to-win |

### 3.3 Gnomes

Level 1 is the planting price; levels 2-3 are upgrade prices. Unlocks are permanent (saved as the
highest chapter reached).

| gnome | unlock | targets | L1 cost/dmg/cd/range | L2 | L3 |
|---|---|---|---|---|---|
| Pebble (slingshot) | chapter 1 | first bug in range | 50 / 6 / 0.8 s / 14 | +70 / 14 / 0.8 / 15 | +130 / 28 / 0.7 / 16 |
| Sprinkler | chapter 1 | pulses every bug in range: damage + slow (speed x0.55 / x0.45 / x0.40 for 1.5 s) | 60 / 2 / 1.0 / 12 | +60 / 5 / 1.0 / 13 | +110 / 10 / 1.0 / 14 |
| Mushroom (spores) | chapter 2 | first bug, splash 7 studs around it | 110 / 10 / 1.5 / 13 | +120 / 22 / 1.5 / 13 | +220 / 48 / 1.3 / 14 |
| Lantern (firefly) | chapter 3 | the toughest bug in range, ignores armour | 150 / 45 / 2.0 / 18 | +160 / 95 / 2.0 / 20 | +300 / 170 / 1.8 / 22 |

Reasons. Pebble is the cheap, plain answer; Sprinkler is the support whose value depends on the gnomes
around it; Mushroom answers swarms (chapter 2 adds wasps and snails); Lantern answers armour and bosses
(chapter 3 is the Queen). **Every upgrade keeps at least 95% of planting's damage per seed paid**
(asserted; the lowest is Pebble L2 at 97.2%): tuning round 4 found that when upgrades were worse value,
the best play was to spam level-1 gnomes that armour then made useless against the first boss. The
Lantern's range was 26 in round 5 and covered half the path; chapter 3 was won first try by 95-100% of
every profile, so it is 18-22. Armour: a hit loses the bug's armour value, but never below 25% of
the hit (`ArmorFloor` 0.25), so nothing is immune. Slows never stack; the strongest one applies.
Combat has **no randomness**: no crits, no misses, so the model is the game and there is no RNG to
farm.

### 3.4 Bugs

Hit points at wave 1; every wave multiplies them by `HpGrowth` = 1.075 (x2.06 per chapter).

| bug | hp | speed | armour | bounty | bite | joins at wave | mix weight | notes |
|---|---|---|---|---|---|---|---|---|
| Aphid | 24 | 6 | 0 | 3 | 1 | 1 | 1.0 | the baseline |
| Ant | 14 | 10 | 0 | 2 | 1 | 3 | 0.6 | fast: punishes a single choke point |
| Beetle | 60 | 4.5 | 2 | 6 | 2 | 6 | 0.35 | armour: teaches upgrades before the first boss |
| Wasp | 34 | 9 | 0 | 5 | 2 | 12 | 0.4 | fast and sturdier |
| Snail | 120 | 3 | 0 | 10 | 3 | 15 | 0.25 | ignores slows ("already slow") |
| **Stag Beetle** (boss, w10) | 420 | 3 | 2 | 120 | 20 | | | the first boss: armour |
| **Snail Baron** (w20) | 600 | 2.5 | 0 | 160 | 20 | | | slows work at half strength |
| **Slug Queen** (w30) | 1000 | 2.2 | 2 | 220 | 20 | | | the brag; half-strength slows |
| **Frost Mantis** (w40) | 680 | 2.6 | 3 | 260 | 20 | | | the long-term goal of the chapters; half-strength slows |

Boss hit points were not guessed: each was swept against the three profiles (§5.3) and set where the
normal player's first-try win rate lands on its target. With the Snail Baron fully slow-immune
the strong profile lost him on 8 of 40 beds (its sprinklers did nothing to him); at half strength it
loses none.
After wave 40 the boss cycle repeats with the same growth.

### 3.5 Waves

Wave n has `8 + floor((n - 1) x 0.5)` bugs (8 at wave 1, 27 at wave 39, 36 at wave 57), split among the
kinds that have joined by their mix weights (largest remainder) and interleaved deterministically. A
boss wave sends half the count, then the boss 2 s after the last of them. Waves are a public function
of n: the HUD previews the next wave ("Next: 12 aphids, 5 ants"), honestly. The path is the procedural
part; the waves are not random.

### 3.6 The bed generator

`genPath(cfg, rand)`: 3-5 vertical runs in columns at least 2 apart (so no two path cells that are not
neighbours on the path ever touch side by side), rows drawn at random, rejection-sampled until the
path is exactly 30 cells. Pads = all lawn cells touching the path. `rand` is the shared `Rng` copied
from `fork-tower/src/shared/Rng.luau` (it has `Rng.below`, which uses the high bits: the checklist's
"LCG low bits" trap). Asserted: exact length, edge to edge, never touching itself, at least 14 pads,
same seed same bed.

Which seed: chapters 1-4 draw a **fresh bed for every attempt** from a server `Random.new()` seed
(tuning round 6: retrying the same bed left a player stuck on a layout that suited them badly; with
the numbers of that round the normal profile's 90th percentile to the brag was 64.0 min on the same
bed and 44.9 min with fresh beds; with the final numbers it is 53.3). The endless
chapter uses **the day's bed**: a seed drawn once per UTC day and stored in DataStore
`GnomeGarden_Daily_v1`, key `d_<utcDay>` (UpdateAsync keeps the first writer's value). Why a stored
draw and not a salt in code: the repo is on GitHub, so a constant in source is not a secret.

### 3.7 Server and network

| name | value | reason |
|---|---|---|
| sim | one pure `Garden.step(cfg, garden, dt)` per garden at a fixed 0.1 s step from a Heartbeat accumulator, at most 5 steps per frame | the model's rules exactly; a lagging server slows both sides of a garden equally |
| bugs on the wire | `GardenTick` RemoteEvent to the garden's OWNER at 10 Hz: `{ t, bugs = { id, kind, s, hpFrac } }` | 32 bugs alive at most for the normal profile (measured peak per chapter 12 / 16 / 21 / 26 / 32; strong endless 35; `report.js`). Bandwidth is an ESTIMATE, not a measurement: 32 bugs x about 8 bytes x 10 Hz = about 2.6 KB/s per player (Studio item, §17) |
| other gardens | gnomes and the sign only; their bugs are not sent | §19 cut; keeps bandwidth flat with 8 players |
| bug rendering | client-built local Parts, at most 3 per bug, interpolated between ticks; cap 40 rendered bugs | the measured peak is 35 |

---

## 4. The player profiles the numbers assume

`GardenModel.Config.Pacing.Profiles`. The model does not know what a human is; these are written down
so a reader can disagree with them.

| profile | decisions every | build phase used | plants on | grows to (per chapter) before upgrading | mix |
|---|---|---|---|---|---|
| weak | 4.0 s | full 20 s | one of the 8 best pads for that gnome | 6 / 8 / 10 / 12 / 12 | 4 : 2 : 2 : 1 |
| normal | 2.5 s | 14 s | one of the 3 best pads | 5 / 7 / 9 / 11 / 12 | 4 : 1.5 : 2 : 1.5 |
| strong | 1.0 s | 6 s | the best pad by value | by value (damage per seed over covered path) | by value |

Plus time on screens: reveal at least 30 / 25 / 15 s (and until the start budget is spent), fanfare
20 / 15 / 8 s, lost screen to retry 15 / 10 / 5 s. "Best pad" = most path within range. The strong
profile's value rule counts a sprinkler as the extra time it gives the gnomes it overlaps, on path no
other sprinkler already slows (tuning rounds 2-3: without that rule it built sprinkler farms and lost
the first boss). Nobody sells in the model.

---

## 5. Balance, measured

### 5.1 First-attempt win rates (40 beds per cell, `spec.js`)

```
first-attempt win rate, weak  : ch1  90%  ch2  55%  ch3  48%  ch4   0%
first-attempt win rate, normal: ch1  98%  ch2  95%  ch3  78%  ch4  57%
first-attempt win rate, strong: ch1 100%  ch2 100%  ch3 100%  ch4 100%
```

Asserted: normal wins chapter 1 first try on >= 95% of beds (98%); weak >= 75% (90%); strong wins every
chapter on every bed (the content is beatable); chapter 3 is a real fight for normal (50-99%); chapter 4
is harder than chapter 3. Attempts per chapter until won (normal, 40 campaigns): 1.02 / 1.07 / 1.32 /
1.35. The weak profile clears chapter 4 in only 4 of 40 campaigns within 12 attempts: chapter 4 is the
long-term goal, not a promise.

### 5.2 Every wave (normal profile, 40 beds per chapter, `waves.js normal`)

`sec` = median wave length; `carrots` = median / worst left after the wave; `lost` = beds lost on it.

```
wave bugs totalHP sec carrots lost gnomes levels    wave bugs totalHP sec carrots lost gnomes levels
   1    8     192  38  20/18    0     2      2        21   18    2914  69  20/11    0     9     10
   2    8     206  33  20/18    0     3      3        22   18    3133  55  20/8     0     9     12
   3    9     215  29  20/18    0     4      4        23   19    3662  56  20/8     0     9     15
   4    9     231  27  20/18    0     5      5        24   19    3937  54  20/8     0     9     17
   5   10     267  30  20/18    0     5      5        25   20    4368  55  20/8     0     9     18
   6   10     405  41  20/18    0     5      6        26   20    4696  54  20/8     0     9     19
   7   11     472  37  20/18    0     5      7        27   21    5140  51  20/8     0     9     20
   8   11     508  35  20/18    0     5      9        28   21    5525  49  20/8     0     9     22
   9   12     571  31  20/18    0     5     10        29   22    6121  49  20/8     0     9     23
  10    7    1112  72  20/0     1     5     10        30   12   11288 119  20/-12   9     9     24
  11   13     709  57  20/16    0     6      6        31   23    7372  65  20/16    0    11     19
  12   13     829  46  20/14    0     7      7        32   23    7925  65  20/12    0    11     22
  13   14     924  42  20/14    0     7      8        33   24    8661  64  20/10    0    11     22
  14   14     993  41  20/14    0     7      9        34   24    9310  60  20/10    0    11     23
  15   15    1398  49  20/14    0     7     11        35   25   10289  58  20/10    0    11     25
  16   15    1503  46  20/14    0     7     12        36   25   11061  56  20/10    0    11     27
  17   16    1998  50  20/14    0     7     14        37   26   13512  60  20/10    0    11     30
  18   16    2147  49  20/14    0     7     15        38   26   14525  59  20/10    0    11     32
  19   17    2433  46  20/14    0     7     16        39   27   16551  61  20/10    0    12     35
  20   10    3706  90  20/-6    2     7     16        40   15   19706 117  17/-5   17    13     38
endless (chapter 5 from wave 41, 40 beds): 41 28 19560 85 13/-1 3 | 45 30 27278 71 14/3 0 | 49 32 37652 87 13/-1 2
                                           50 17 36256 137 4/-19 11 | 51 33 44405 95 8/-2 4 | 53 34 53894 93 -1/-2 7
```

What it says: a normal player rarely loses a carrot to a regular wave; the worst bed loses a handful.
Each chapter is decided by its boss. That is deliberate (a clear, clip-able climax each season), and
it is also the design's main risk: a real player who is worse than the normal profile meets the
wall at the boss, not earlier. The weak profile's boss losses: 4 of 40 at wave 10, 18 at wave 20, 21 at
wave 30, 37 at wave 40.

### 5.3 Boss calibration (first-try win rate vs base hit points, `bosssweep.js`)

```
ch1 stag   360: weak 100% normal 100%  | 420: weak 90% normal 98%  | 480: weak 83% normal 85%
ch2 baron  540: weak  85% normal 100%  | 600: weak 55% normal 95%  | 660: weak 45% normal 88%
ch3 queen  900: weak  68% normal  95%  |1000: weak 48% normal 78%  |1100: weak 15% normal 43%
ch4 mantis 620: weak   5% normal  95%  | 680: weak  0% normal 57%  | 740: weak  0% normal 25%
(strong: 100% at every value shown except baron 660: 98%)
```

**The most sensitive numbers in the game are the bosses' hit points:** +-10% on the Slug Queen moves
the normal first-try rate between 95% and 43%. They are config, and the first live data should
re-tune them before anything else.

### 5.4 Hazards never decide a chapter

A hit dazes the gardener (§8). With **every** hazard hitting, the normal profile wins and loses exactly
the same chapters: **0 of 160** outcomes change (chapters 1-4, 40 beds each, asserted). Seed costs were
measured first and rejected: spilling 10% of the pouch (max 25) per hit flipped 3 of 40 chapter-3
beds and 3 of 40 chapter-4 beds; 5% (max 15) still flipped 2 and 3. In a tower defence a few seeds
always decide some boss fight, so a hit costs time, not seeds.

---

## 6. Pacing: the brag and the long-term goal

Minutes of play (median over 40 campaigns; resting excluded), `bands.js`:

```
         w3   w10  w15  w20  w27  w30  w31  w35  w40  w41  w45  w50
weak    3.0  10.2 16.9 24.3 34.7 53.7 56.6 62.7  -    -    -    -    (chapter 4 cleared in 4 of 40 campaigns)
normal  2.6   8.6 14.1 20.3 28.9 33.6 35.8 40.5 57.4 60.8 69.5  -    (w50 on 17 of 40 endless runs)
strong  2.1   7.2 11.1 16.7 23.2 26.6 27.9 32.1 37.5 39.2 43.8 50.5 (w50 on 40 of 40)
```

- **The brag: the Slug Queen falls under the Harvest Moon (wave 30 survived).** Normal: median
  **33.6 min**, p10 30.3, p90 53.3, worst 61.8 (asserted: median within 30-45, p10 >= 25, worst < 75).
  Strong 26.6 (p10 23.0, p90 28.7); weak 53.7 (p10 37.8, p90 85.5). The moment: the Queen's death
  rattle, a golden burst over the bed, the moon reaching full exactly as she falls (§7, band 6), the
  title card `HARVEST MOON: The Slug Queen falls!`, and the board entry.
- **Long-term goal 1: the Frost Mantis (wave 40).** Normal median 57.4 min (p10 43.9, p90 75.5).
- **Long-term goal 2: the Aurora (wave 50, on the day's endless bed).** The strong profile always gets
  there (40/40, median 50.5 min of play); the normal profile on 17 of 40 endless runs. It is a goal,
  not a given (asserted both ways).
- **Long-term goal 3: the board.** Endless best wave over 12 beds: normal 40-53 (median 50), strong
  53-56 (median 55). With unlimited seeds: normal 48-53, strong 53-56. The board ranks skill (strong
  median 5 waves above normal, asserted > 3) and has a ceiling (asserted < 200); the bed moves the
  strong ceiling by 3 waves (asserted <= 6).

---

## 7. Environment bands

`EnvBands.luau` copied **verbatim** from `plus1-jump/src/shared` with `tests/EnvBands.spec.luau`. All
band visuals are client-only (`Garden.client.luau` + `GardenArt.luau`), drawn for the local player's
own garden, and replicate nothing.

**What drives them (the game's own logic):** `progress p` = waves survived + the share of the current
wave's bugs already gone (killed or through). The server computes it and replicates it as the garden
attribute `Progress` (public: it is the wave counter). A boss wave's band turns as the boss loses
ground; losing a chapter sends p back to the chapter's start and `EnvBands.approach` (half-life 0.6 s,
plus1's value) glides it back. "Welcome to <band>" shows once per new highest band.

`full at` = minutes of play when p reaches `from` (median of 40 normal campaigns, `bands.js`); the band
blends in over the `fade` waves before it.

| # | id | from | fade | season and light | scenery (client parts) | critters | weather | hazards | full at (normal) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | sprouts | 0 | 0 | spring dawn, ClockTime 6.6, pale pink fog | seedlings, dewy grass tufts | butterflies | none | **none** (onboarding) | 0 min |
| 2 | blossom | 3 | 1 | spring morning, 9.5, clear | blossom trees along the hedge | butterflies, bees | falling petals | acorn | 2.6 |
| 3 | summer | 10 | 2 | high summer noon, 13.0, saturated | sunflowers, bunting | bees, dragonflies | pollen motes | acorn, sprinkler jet | 8.6 (the Stag falls) |
| 4 | shower | 15 | 1 | summer shower, 15.0, grey-violet | puddles, a rainbow arc | dragonflies | rain | sprinkler jet, acorn | 14.1 |
| 5 | harvest | 20 | 2 | autumn golden hour, 16.8, amber | pumpkins, hay bales | robins | falling leaves | apple, molehill | 20.3 (the Baron falls) |
| 6 | **moon** | 30 | 3 | **Harvest Moon** night, 21.5, a giant low moon | paper lanterns on the hedge, the moon | fireflies, an owl | fireflies | apple, pinecone | blends from 28.9, **full the instant the Queen falls** (33.6) |
| 7 | frost | 31 | 1 | first frost, cold morning, 8.0 | frosted hedge, frozen birdbath | robins | frost sparkle | icicle, molehill | 35.8 |
| 8 | snowfall | 35 | 1 | first snow at dusk, 17.5 | snow on the hedge, a sledge | crows | light snow | icicle, snow clump | 40.5 |
| 9 | moonlit | 40 | 2 | moonlit snow, midnight 0.5 | snowdrifts, a snowman | an owl | snow | snow clump, icicle | 57.4 (the Mantis falls) |
| 10 | starfall | 45 | 2 | clear frozen night, 23.0 | frosted lamp posts | shooting stars | stardust | star shard, snow clump | 69.5 (strong 43.8) |
| 11 | **aurora** | 50 | 3 | aurora night, 1.5 | aurora ribbons (Beams) | snow hares | slow snow + stardust | star shard, snow clump | strong 50.5; normal on 17 of 40 endless runs |

Reasons for the thresholds: band 1 is quiet so the first two and a half minutes teach the game; band 2
starts the hazards at wave 4 (the model's `QuietBeforeWave` = 4 is the same rule: the band you are in,
`EnvBands.indexAt(p)`, picks the hazard kinds, and band 1 has none). Season bands blend during the
boss fight and are full the instant the boss falls (`from` = the boss wave, `fade` 2-3), so the season
changing IS the reward. Band 7 starts at 31 with fade 1 (EnvBands.validate needs fade <= 31 - 30), so
frost never creeps into the Queen fight. Bands 8 and 10 split the two longest stretches (chapter 4 and
the endless climb) so no band lasts longer than about 17 minutes of normal play. Gaps between band
starts for the normal profile: 2.6, 6.0, 5.5, 6.2, 13.3, 2.2, 4.7, 16.9, 12.1 minutes; the 16.9 includes
chapter-4 retries, and every retry replays frost and snowfall from wave 31. All eleven `fade` values
pass `EnvBands.validate`'s fade <= gap rule.

Each band also carries the full lighting / atmosphere / bloom / colour-correction table in plus1's
format. Starting values are plus1's band with the nearest time of day (sprouts = plus1 `temple`,
summer = `treetops`, harvest = `cloudsea`, moon/snow/aurora = `edge`), and are a Studio item (§17):
only rendering can judge them. Night bands keep the path readable with neon path-edge strips, not
lights (the light budget is 3).

**Budgets, capped in code** (`EnvBands.capRates` + counters in `GardenArt`, measured headless in
`check_gnomegardendefense_env`): local scenery parts <= 200, rendered bugs <= 40 (<= 120 parts),
particle emitters <= 4, weather emitters on at once <= 2, total emitter rate <= 60/s, lights <= 3,
beams <= 8, hazards in flight <= 1. The emitter, weather, light, beam and hazard caps are plus1's
`Config.Budget` values; plus1 allows 220 local parts for its sky, 200 here because bugs add up to 120;
the bug cap is the measured peak (35) plus margin. Whether a low phone holds them is a Studio item.

---

## 8. Hazards

**Template:** `deep-vein/src/shared/Hazards.luau` verbatim, with `deep-vein/tests/Hazards.spec.luau`.
That file is plus1-jump's template plus deep-vein's documented VERTICAL kinds (`drop = "above"` /
`"below"`), and that adaptation is exactly what a garden needs: the TD camera looks down at a flat bed,
so a plus1 sideways lane clamped into the camera's pitch window would start underground. A thing that
falls on you from above (or pops up under you) is telegraphed by the ring at your feet, on screen
wherever the camera looks. Nothing else is adapted.

| kind | drop | from the template's tuned kind | height / fall / telegraph / commit / pass | ring radius | bands |
|---|---|---|---|---|---|
| acorn (a crow lets it go) | above | rock | 22 / 0.6 / 3.2 / 1.6 / 0.6 | 1.6 + 1.4 = 3.0 | 2, 3, 4 |
| apple | above | crystal | 20 / 0.5 / 3.2 / 1.6 / 0.6 | 3.0 | 5, 6 |
| pinecone | above | stalactite | 20 / 0.5 / 3.2 / 1.6 / 0.5 | 3.0 | 6 |
| icicle | above | shard | 20 / 0.5 / 3.2 / 1.6 / 0.5 | 3.0 | 7, 8, 9 |
| snow clump | above | lava | 18 / 0.7 / 3.4 / 1.7 / 0.8 | 3.0 | 8, 9, 10, 11 |
| star shard (a shooting star's spark) | above | relic | 22 / 0.6 / 3.2 / 1.6 / 0.6 | 3.0 | 10, 11 |
| sprinkler jet | below | steam | 7 / 0.35 / 3.4 / 1.8 / 1.2 | 3.0 | 3, 4 |
| molehill | below | magma | 7 / 0.35 / 3.6 / 1.8 / 1.2 | 3.0 | 5, 7 |

Template constants unchanged from deep-vein: MinTelegraphSeconds 3, MinCommitSeconds 1.5,
MaxRetargetSpeed 1.5, PlayerRadius 1.4, AimJitter 0.8, KnockLift 8, KnockSeconds 0.9, SpreadDegrees 0.
The red ring IS the hit zone (the template's zone rule): stepping out in any direction dodges; at
walk speed 16 a player standing at the centre is out in 0.19 s, well inside the 1.6 s commit.

- **Clock and rate:** `IntervalMin..Max` = **100-150 s of garden time** (waves and build phases; frozen
  while paused, while AFK-held, never reset). Measured: **one hazard per 2.58 min of play** for the
  normal profile (2.55 weak, 2.58 strong), asserted within 2-3 min. 120-180 s gave one per 3.14 min
  (measured one tuning round earlier), because the clock is off in band 1 and on screens. Never two at once (the template).
- **Cost of a hit:** the template's knock-down (0.9 s), then **dazed for 3 s**: the gnome menu greys out
  and a tap answers "Seeing stars... 2". No seeds. Measured: 0 of 160 chapter outcomes change even if
  every hazard hits (§5.4); 2 s and 6 s dazes also changed 0.
- **Where it runs:** the client, like plus1 and deep-vein: schedule, ring, hit test, knock and daze. It
  touches only the local player. A client that deletes hazards saves itself 3 s per 2.6 min, which the
  measurement above shows cannot change an outcome, and it can never touch another player.
- Hazards never hit gnomes, bugs or the carrots.

---

## 9. Rest (pause)

`Rest.luau` copied **verbatim** from `plus1-jump/src/shared` with `tests/Rest.spec.luau`. One config
value differs and one behaviour is added around it; both are below with the reason.

**What pause is:** a PAUSE button (top centre, 48 px) freezes the player's **whole garden**: bugs,
gnomes, the build timer, the hazard clock. Nothing moves, nothing earns, nothing is lost. Any step or
any garden action resumes it (WakeOnMove), or the button again. Pressing it with a hazard in flight
queues it (BlockWhileThreat): it begins the first still moment after the hazard has passed, and expires
after `PendingSeconds`.

| Rest config | value | reason |
|---|---|---|
| WakeOnMove | true | required by `Rest.validate` |
| BlockWhileThreat | true | required; rest is never a panic button against a falling acorn |
| RequireGrounded | true | template |
| WakeGraceSeconds | 0.4 | plus1's value |
| PendingSeconds | 10 | outlives the longest hazard (molehill: 3.6 s telegraph + 1.2 s pass = 4.8 s) by more than 2 s, plus1's rule |
| **IdleSeconds** | **0 (idle rest off)** | plus1 rests a player who stands still 20 s. In a TD, watching a wave without touching anything is normal play, and an idle pause would freeze a player mid-wave while they watch. AFK safety is the **AFK hold** instead (§3.1): the next wave does not auto-start for a player the server has not seen act for 180 s |

**Why mid-wave pause is not an exploit.** `Rest.luau` warns that a game must not map rest onto a clock
the player races. In this garden there is no such clock: the board metric is a wave count, not a time,
and pause stops **both sides** together, because the bugs, the gnomes and the hazard clock all run on
the same garden time. A paused second is a second that never happened. You cannot plant while paused:
the server resumes the garden before it applies any garden action, so a client that ignores the rule
gains nothing either. All a pause buys is thinking time, which a script already has unlimited of, so
it cannot inflate the board.

Where it runs: `Rest.luau` on the client (it needs the local hazard state), sending `SetPaused(bool)`;
the server freezes or resumes that garden (rate-limited), and also resumes it on any garden action or a
4-stud step. No validation beyond that is needed, because a pause gives no advantage (above).

---

## 10. The board (public + friends)

`Board.luau` copied **verbatim** from `plus1-jump/src/shared` (deep-vein's copy is byte-identical) with
`tests/Board.spec.luau`, and `Config.Board` with plus1's values and reasons (top 10 public via
`GetSortedAsync(false, 10)` cached 60 s; friends via `GetFriendsAsync` capped at 200, fetched on
demand, cached 300 s, reads throttled to a burst of 40 then 1/s with 10 spare; `MaxMetric` 4 000 000
because 4e6 x 2e9 < 2^53).

- **Metric: the highest wave survived**, in any chapter, measured by the server sim. Stored in
  OrderedDataStore `GnomeGarden_LB_v1`, key `u_<userId>`, value `wave x 2e9 + (2e9 - reachedAtUnix)`,
  written with UpdateAsync keep-the-larger, only when the best wave improves. Ties go to whoever got
  there first.
- **The physical board:** `GardenBoard_<userId>` at the west end of each player's deck, angled toward
  their spawn, with a ProximityPrompt (distance 9) toggling Public / Friends for its owner. Names via
  `GetNameFromUserIdAsync`, cached on the server, never stored. Empty friends board: "None of your
  friends has defended a garden yet. Invite one and race them to the Harvest Moon!"
- **Why a script cannot inflate it:**
  1. A wave counts only when the server's own simulation has removed every bug of it with carrots left.
     The client never reports a kill, a wave or a score.
  2. The client can only ask for actions the rules allow (plant, upgrade, sell, ready, pause), each
     validated against the server's seeds, pads and phase (§12). There is no remote that grants seeds.
  3. Combat is deterministic. There is no roll to repeat, so there is nothing to farm.
  4. READY only shortens a build phase: every bug of every wave still spawns and must be stopped.
  5. Pause stops both sides (§9).
  6. Bed fishing (restarting until a good bed) is impossible where the board is decided: every wave
     above 40 is played on the day's bed, which a restart does not change. Below 41, chapters are fixed
     milestones.
  7. Even with unlimited seeds the best profile stops at 53-56 (`ceiling.js`): the 14-gnome cap and
     the HP growth are a wall, so a perfect script plays a better game, not an infinite one.

---

## 11. Data model

**Persisted** (DataStore `GnomeGarden_v1`, key `u_<userId>`, value `{ data, session, jobId }`):

| field | type | why |
|---|---|---|
| `version` | 1 | migrations |
| `chapter` | 1-5, the highest chapter unlocked | unlocks are derived from it (gnome kinds), never stored separately, so they cannot disagree |
| `bestWave`, `bestAt` | integer, unix seconds | the board metric and its tie-break |
| `published` | integer | the last best written to the board, so a failed board write is retried |
| `tutorialDone` | boolean | the first-minute hints show once |

That is all. A run in progress is not saved: a rejoin starts the highest unlocked chapter on a fresh bed
(the endless chapter on the day's bed). Cost: at most one attempt; a normal chapter-4 attempt is about
13 minutes (the sum of the §5.2 medians for waves 31-40, 9 build phases of 14 s and the reveal). Saved this small on purpose: no inventory, no integer keys (the JSON round-trip trap cannot
occur), nothing one-time to grant.

Saving copies deep-vein's pattern: everything pcall'd; the load that takes the session lock writes a
fresh `session` GUID; every save carries this session's token AND this server's jobId or it is
cancelled; `canSave` only while holding the lock; a refused save is told to the player.

**Server-only** (Lua tables in the server script, never an Instance, an attribute or a payload): each
garden's sim state (bugs, gnomes, seeds, carrots, timers, rest/AFK state), the attempt's bed seed, the
session token. If a headless check needs to read state, it goes under `ServerStorage.GardenInfo.<userId>`,
never under the garden model (anomaly-observatory: "ServerStorage, not the zone").

**Replicated, and why it is safe:** the bed (path, pads), gnome models (`Kind`, `Level`), the garden
folder's attributes `Owner`, `Chapter`, `Wave`, `Progress`, `Phase` (reveal / build / wave / won / lost /
held), `Paused`, `Carrots`, `Seeds`, `BuildLeft`, `leaderstats.Best`, the owner's `GardenTick` (bug
positions and health), and `Config` in ReplicatedStorage. **There is no hidden answer in this game.**
Everything a player could want to know (where the path goes, what comes next, how strong the bugs are)
is shown on purpose. fork-tower REVIEW-4's lesson, a seed that drives visible geometry can be
recovered from it, does not bite here: the bed seed drives only the visible bed, so recovering it
yields the bed you can already see. The one forward-looking value, tomorrow's endless bed, does not
exist until a server draws it.

---

## 12. Anti-exploit model

| remote (client to server) | validated | refusal says |
|---|---|---|
| `Plant(padId, kind)` | number; pad belongs to the caller's own garden (ids index only that garden); pad free; kind unlocked; phase reveal/build/wave; seeds >= price; gnomes < 14 | "Not enough seeds (need 60, have 41)", "Garden full: 14 gnomes", "That pad is taken", "Lantern unlocks in Autumn" |
| `Upgrade(padId)` | own gnome there; not max level; seeds | "Max level", "Not enough seeds (need 130, have 97)" |
| `Sell(padId)` | own gnome there | (none possible beyond "No gnome there") |
| `Ready()` | phase reveal (needs >= 1 gnome) or build | "Plant a gnome first" |
| `SetPaused(bool)` | phase not won/lost; 1 per 0.5 s | "Can't pause now" |
| `Restart()` / `NextSeason()` | phase lost / won | (buttons exist only in those phases) |

All remotes share a token bucket of 10 actions/s with a burst of 20 per player (a human taps a few per
second); over the limit the action is refused with a toast, never silently. Every garden action first
resumes a paused garden. Nothing from the client is trusted beyond "this player asks for this action".
Server-to-client remotes carry only public state (`GardenTick`, `Toast`, `Fanfare`).

---

## 13. Spawn (robloxemu/SPAWN-ORDER.md)

- Each slot has a real SpawnLocation `Spawn_<userId>` on its deck: Enabled, Neutral, Duration 0 (no
  forcefield bubble), invisible, facing north over the bed.
- In `PlayerAdded`, **before any yield**: take the first free slot, create the spawn, set
  `plr.RespawnLocation` to it. Then load the profile. `CharacterAutoLoads` stays true (robloxemu does
  not implement `LoadCharacter`, and the engine places the character on the RespawnLocation by itself).
- `CharacterAdded` does **not** write the character's CFrame: the engine's placement on the right spawn
  is the final answer, so there is no race to lose (the "preferred" pattern; grow-a-crystal and
  nightwatch-manor use it).
- Leaving: the slot's spawn is destroyed and the slot is freed, so the engine can never pick a stale
  spawn. Each joiner's own RespawnLocation is set before their character exists.
- The headless check asserts two players who join together each stand on their own deck (deep-vein's
  "0.0 studs apart" defect is the failure it guards).

---

## 14. The first 60 seconds of a new player

Model (normal profile, chapter 1, 40 beds, `report.js` and §5.2): the reveal and first two plants take 25 s; wave 1 lasts a
median **37.8 s** (20.6-50.4) and costs a median **0 carrots** (worst 2); a third gnome is planted
by the end of wave 2 (gnome count 3 after wave 2 in §5.2).

| t | what happens |
|---|---|
| 0 s | spawn on your own deck (the engine places you on `Spawn_<userId>`), the bed already drawn in front of you, dawn light (band 1, no hazards). The 3 best pads for a Pebble pulse. Hint: "Tap a glowing pad to plant a gnome" with an arrow |
| about 3-5 s | tap a pad: the bottom sheet opens with two big buttons, Pebble 50 and Sprinkler 60 (Mushroom and Lantern shown locked: "Summer", "Autumn"). Tap Pebble: the gnome pops up in a puff of soil. Seeds 120 to 70 |
| about 10 s | hint: "One more, then press READY". Second Pebble, seeds 20. READY pulses |
| about 25 s | READY: 8 aphids come through the hedge gap. "+3" pops on every kill |
| about 63 s | wave 1 survived: +18 clear bonus, the 20 s build timer starts, hint: "Tap a gnome to upgrade it" |

The core action is reachable within about 5 seconds with no prerequisite (the checklist's rule): the
start budget is free and the first pad is highlighted.

---

## 15. Phone-first HUD

`Responsive.luau` copied verbatim (identical in all sibling games) with its spec; `docs/mobile-ui-brief.md`.

- One root Frame owning a `UIScale`, sized `1/scale`. Re-layout on `ViewportSize` changes.
- Top bar, left to right: seeds, carrots, wave `7/10` + season name, PAUSE (centre), next-wave preview.
- READY: right edge, vertically centred (never bottom-right: Roblox's jump button lives there).
- Gnome sheet: bottom centre, between the thumbstick and jump zones, buttons >= 44 screen px, collapses
  to icons when `layout.compact`.
- Nothing tappable in the bottom-left or bottom-right corners. The HUD overlap rule 4b is asserted with
  `overlap = true` in the game's hudcheck across robloxemu's six viewports.
- Boss bar under the top bar during boss waves.

---

## 16. What to build, and the gates

Files (deep-vein's layout): `default.project.json` (src/server -> ServerScriptService, src/client ->
StarterPlayerScripts, src/shared -> ReplicatedStorage); `src/shared/Config.luau` (from
`GardenModel.Config`), `Garden.luau` (the sim, from the model), `PathGen.luau`, `Waves.luau`, plus the
verbatim copies `EnvBands`, `Hazards` (deep-vein's), `Rest`, `Board`, `Responsive`, `Rng` (fork-tower's),
`Fx`, `FxClient`; `src/server/Main.server.luau`; `src/client/Hud.client.luau`,
`Garden.client.luau` (+ `GardenArt.luau` in shared), `Board.client.luau`; `tests/*.spec.luau`;
`README.md`, `CLAUDE.md`, `EYECANDY.md`, `MARKETING.md`, `.gitignore` with `publish_*.bat` /
`publish_*.sh`. First visual call on the server: `Fx.applyLighting(Fx.Presets.Cozy)`; signature
particles: soil puff on plant, seed sparkle on kill, golden burst on a boss.

Gates, TDD throughout (each new assertion watched failing first, then a mutation sweep with a control):

- `tests/Pacing.spec.luau` against the real modules, and `tests/WaveTable.luau` matching §5.2.
- `Garden.spec` (targeting, armour floor, splash radius, slows not stacking, leaks and bites, bounty,
  deterministic replay), `PathGen.spec`, `Waves.spec`, `Economy.spec` (prices, refunds, caps, every
  refusal), `EnvConfig.spec` (`EnvBands.validate` on the bands, `Hazards.validate`, `Rest.validate`,
  PendingSeconds > longest hazard + 2 s), plus the copied specs.
- robloxemu (rebuild the bundle first: `py -3 wrap.py --game ../gnome-garden-defense --out
  build/gnome-garden-defense.luau`): `check_gnomegardendefense.luau` walks the player path: join, spawn
  on own deck, tap a pad, plant, READY, kills, seeds, upgrade, a refused plant says why, pause freezes
  and an action resumes, a chapter won by a scripted strong player, rejoin with chapter 2 unlocked.
  `_spawn` (two players on two decks), `_board`, `_lock` (session token + jobId), `_hud` (overlap = true),
  `_env` (budgets at every band and seam), `_wire` (no server-only field in any Instance, attribute or
  payload; no `Seed`/`Key` attribute anywhere under workspace or ReplicatedStorage).

---

## 17. Needs Studio (only real rendering, input and network can settle these)

1. Pad tap size on a phone at the default camera from the deck: is a 7-stud pad >= 44 px? Does the
   whole 96 x 72 bed fit the default zoom, and is `CameraMaxZoomDistance` enough?
2. ClickDetector taps on pads through the bottom sheet's gaps; a tap on a gnome vs the pad under it.
3. Client-rendered bugs from 10 Hz snapshots: smooth at 35 bugs; ants at 10 studs/s.
4. Every band's look (lighting tables start from plus1 bands); the moon reaching full at the Queen's
   death; night-band path readability with neon edge strips.
5. The red ring on grass, gravel and snow; an acorn from above with a top-down camera; the knock and the
   daze greying the sheet.
6. Pause: the freeze reads as a freeze; thumbstick wakes; the PAUSED overlay on a phone.
7. The deck board's readability and its ProximityPrompt on touch.
8. Gnome, bug and boss models built from Parts: silhouettes readable at 60 studs.
9. Bandwidth and frame time with 8 players on a low phone.
10. Frame time at the densest band seam (harvest to moon) with 35 bugs.

## 18. What EYECANDY.md, MARKETING.md and README.md will hold

**Thumbnail shots (1920 x 1080, subject in the middle 1280 px):** (1) Harvest Moon over a full bed,
the Slug Queen mid-path, lanterns blazing; (2) low angle behind a Pebble gnome, aphids filing past,
spring blossom; (3) the board at the deck at dusk; (4) the aurora over a snowed bed.

**Clips (7-15 s, 1080 x 1920, for `tools/film_game.py`):** the first plant pop; the Stag Beetle stopped
on the last tile; the Slug Queen falling as the moon fills (the brag); an acorn ring dodged in time; a
sprinkler slowing a wasp swarm into a mushroom's splash; READY pressed on wave 49 under the aurora;
the season turning during a boss fight. Each gets its staging recipe in MARKETING.md.

**Store text** (`README.md`; 783 characters, plain ASCII, measured):

```
Bugs are marching on your carrots. Plant gnomes beside the path and stop them!

- A fresh garden bed every attempt: the path is drawn new each time, so no two fights play the same.
- Four gnomes: Pebble (slingshot), Sprinkler (slows bugs), Mushroom (spore splash) and Lantern (pierces armour). Upgrade each one twice.
- Four seasons, four bosses: the Stag Beetle, the Snail Baron, the Slug Queen under the Harvest Moon, and the Frost Mantis.
- Then the endless Moonlit Bed, the same bed for everyone each day. How many waves can you hold?
- Public and friends leaderboard for your highest wave, counted by the server.
- Need a break? Pause, and your garden freezes until you are back.
- Made for phones: tap a glowing pad to plant.

Nothing costs Robux. No loot boxes, no pay-to-win.
```

---

## 19. Cut from v1 (and why)

| cut | why |
|---|---|
| player-built mazes (bugs re-pathing around gnomes) | path length would be the player's choice: the balance model explodes and a script could search for degenerate mazes; per-placement pathfinding on the server |
| co-op on one bed | win rates would depend on party size; v1 measures one player |
| seeing other players' bugs | bandwidth x8; their gnomes and sign stay visible |
| flying bugs, second lanes | more systems than v1 can build well |
| a 2x speed button | changes every measured minute and doubles server work per garden |
| boss abilities (minions, shields) | the bosses are already the most sensitive numbers (§5.3) |
| saving a run mid-chapter | a chapter is 8-15 minutes; resuming adds a save format and a seed-in-save secret problem for little |
| permanent stat upgrades / meta currency | every chapter must stay one measurable scenario; unlocks by chapter are the progression |
| seed spill on a hazard hit | measured to decide boss fights (§5.4) |
| promo codes, cosmetics, daily rewards, Robux of any kind | fair-monetization rule; nothing to grant means no one-time-grant trap |
| idle rest | freezes players who are watching (§9); the AFK hold replaces it |
| gamepad-specific UI | ClickDetectors work with mouse and touch; gamepad is a later pass |

---

## 20. Self-review

- **Placeholders:** none. Every balance number in §3.1-§3.5 is in `GardenModel.Config`, except
  `AfkHoldSeconds` (not modelled: it only acts on an absent player). §2, §3.6's store names and §3.7
  are layout and engineering decisions with their reasons. Every outcome in §5, §6, §8 and §14 is
  printed by a named script on stated seeds.
- **Contradictions checked:** the first wave of an attempt waits for READY while later waves auto-start
  after 20 s (§3.1, both modelled). Hazards run on the client and cost time only, so the server needs no
  hazard state, and `Rest.luau`'s threat check runs where the hazard is (client) (§8, §9). Idle rest is
  off and the AFK hold is the AFK safety (§3.1, §9). Band 2 at p = 3 and `QuietBeforeWave` = 4 are the
  same rule. Band 6 (from 30, fade 3) and band 7 (from 31, fade 1) pass `EnvBands.validate`'s
  fade <= gap rule. Bosses bite 20 = `Carrots`.
- **Known gaps, stated:** (1) the Luau model and spec have not run; the numbers come from the JS mirror.
  The two can differ in the last bit of `pow` (bounties round with `floor(x + 0.5)`), so a seed's
  outcome could flip; the Luau run is the first build task. (2) The profiles are models of people.
  Real players will place and upgrade worse or better; the boss hit points (§5.3) are where that shows,
  and they are the first numbers to retune. (3) Regular waves rarely cost a normal player a carrot, so
  the tension lives in the boss waves. (4) Everything visual, every pixel size and the network load are
  unmeasured until Studio (§17).
