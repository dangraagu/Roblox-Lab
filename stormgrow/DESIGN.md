# StormGrow: Mutation Farm — design spec (v1)

> **REVIEW-1 (2026-10-01) changed parts of this spec; `REVIEW-1.md` has the evidence and `CLAUDE.md` lists the
> deviations.** In short: tiles are no longer ClickDetector hitboxes (§8, §10, §12.2): a tap is picked on the client
> against the drawn crops and soil (`Pick.luau`) and sent as `Tap(slot, key)`, which the server checks as before;
> idle rest starts after 90 s, not 20 (§5); the porch board is 10 x 6.6 studs, 15 studs from the pad (§7); a load
> retries, a crashed server's expired lock is taken over, a newer version's record is never written, and the board
> writes only what a save has landed (§8.4); a freed farm goes to whoever waits for one.

Written 2026-09-30 from `docs/game-radar/2026-09-28-roblox-game-radar.md` §4 (ranked #4, score 7.5), measured
against `docs/complete-game-standard.md` (the finish line) and `docs/new-game-checklist.md` (the traps).
**No game code exists yet.** Nothing was committed, pushed or published, and Studio was not opened.

"Measured" in this file means one of two things, and each number says which:
* **modelled**: printed by `design/pacing-model.luau` (sha256 `1f0ff4b6…0190`). It is a design-time model with its own copy
  of the numbers in §2. Run it with `luau design/pacing-model.luau` from this folder (~20 s). When the game exists,
  `tests/Pacing.spec.luau` must re-measure the same quantities against the real `Config.luau`, and the model is retired;
* **computed**: arithmetic on the design numbers, shown where it is used.

Caps (parts, emitters, lights) are **limits the build enforces in code and measures headless**. They are not
measurements yet.

### Where each item of the standard lives

| standard (complete-game-standard.md) | here |
|---|---|
| §1 core loop reachable from join, walked headless | §1, §11, §13 (`check_stormgrow.luau` walks it) |
| §1 spawn per SPAWN-ORDER | §9 |
| §1 server-authoritative, nothing secret replicates | §8, §10 |
| §1 DataStore lock, owner token, string keys, one-time grants | §8.1, §8.4 |
| §1 no silent no-ops | §12.3 |
| §2 Fx preset + signature particles | §3.4 |
| §2 bands (≥ 5), hazards (ring = hit zone), rest, budgets | §3, §4, §5, §3.5 |
| §2 brag at 30-45 min + long-term goal, pacing model in tests/ | §6, §2.6 |
| §2 phone first, UIScale root, hudcheck overlap = true | §12 |
| §3 public + friends board, unscriptable metric, tie by first | §7 |
| §3 no Robux, no gambling, no pay-to-win | §2.2 (odds are public), §16 |
| §4 README store text, EYECANDY needs-Studio + shot list, MARKETING clips, CLAUDE.md | §14 (drafts), §15 |

---

## 1. The core loop

You own one of six farms around a market square. Tap an empty tile to plant the selected seed: the tap buys it,
and Radish seeds are free, so you can never get stuck. Crops grow on real-time timers, also while you are offline.
Tap a ripe crop to harvest it: it sells on the spot and the same tap replants. Over everything runs a **weather
clock that is the same in every server and follows the real clock**: a storm at the top of every ten minutes,
frost five minutes after it, and after the :00 and :30 storms a rainbow. **Only ripe crops catch the weather.**
Every 5 seconds of an event, each ripe crop has a small chance to take that event's mark: Charged (storm),
Frosted (frost) or Prismatic (rainbow). Marks stack into rarer variants and their values multiply (Stormglass,
Radiant, Aurora and the Tempest, worth x200). So the choice every minute is: harvest now, or leave ripe crops in the
ground for the event the forecast says is coming. Coins unlock the next crop and the next field. The lifetime total you have harvested
moves your farm's sky through seven bands, from Sunny Meadow to the Eye of the Storm (the brag, about 37 minutes)
and Starfall Summit (about 2 hours). Every mark a crop type takes for the first time is an entry in the 56-entry
**Almanac**, and the Almanac is what the leaderboard ranks.

---

## 2. Every number, with its reason

### 2.1 The weather clock (`Config.Weather`, pure `Weather.luau`)

| number | value | reason |
|---|---|---|
| cycle | 600 s: a storm starts at :00, :10, :20, :30, :40, :50 | 3-4 storms in a 30-45 min session. "On the tens" is learnable without a manual |
| storm | 90 s (:x0:00-:x1:30) | 18 strike waves, and a 15 s clip fits anywhere in it. Length is chosen for the show, not the balance: modelled, 60 s moves the normal player's brag from 36.6 to 37.5 min |
| frost | 90 s (:x5:00-:x6:30) | halfway between storms, so something happens every 5 minutes. Same length as the storm, so the two marks are symmetric |
| rainbow | 60 s right after the :00 and :30 storms (:01:30-:02:30, :31:30-:32:30) | rainbows follow rain, a rule players already know. Twice an hour keeps Prismatic (x8) and the Tempest (x200) rare |
| longest wait for any event | 210 s (computed: storm end :x1:30 to frost :x5:00, and frost end to the next storm) | a new player sees weather inside 3.5 min wherever they join |
| alignment | UTC Unix seconds, `t % 600` | every server shows the same weather, so server hopping gains nothing and players can tell each other "rainbow at :30" |
| strike tick | every 5 s during an event (18 per storm or frost, 12 per rainbow) | one wave every 5 s reads as rhythm: bolt, glow, a breath |
| per-crop chance over a full event | storm 0.50, frost 0.50, rainbow 0.35 | tuned with the model (§2.6): at 0.35/0.35/0.30 with x3 marks, **following the forecast was slower than ignoring it** (band 6 at 37.6 vs 31.4 min). Today's values plus the x5 marks make it faster (36.6 vs 45.8 min) |
| per-tick chance q | storm and frost 0.03778, rainbow 0.03526 (computed: `1 - (1 - P)^(1/ticks)`) | a crop ripe for the whole event gets exactly P. A crop that ripens halfway through gets a fair share, so being ripe at the start is the skill |
| worst case per farm per tick | 2.04 bolts (computed: 54 ripe crops × 0.03778) | bounds the bolt effects (§3.5) |
| `ClockOffsetSeconds` | 0 | a knob for the night shift's shots place (§14.2). A spec asserts it is 0 in `src/` |

**Server clock.** `now = unixAtBoot + (tick() - tickAtBoot) + Config.Weather.ClockOffsetSeconds`, with
`unixAtBoot = os.time()` read once at load. Only differences of `tick()` are used, so its time zone never matters. In
Roblox this is the Unix clock. In `robloxemu`, `tick()` is the virtual clock the harness advances and `os.time()` is
real (`check_stealacryptid.luau:59` records the same). So a headless check can fast-forward weather and growth. The
server writes `workspace:SetAttribute("ServerNow", now)` at 1 Hz. Clients extrapolate from it by at most 1.5 s, and
compute weather, growth and the forecast from the same pure modules. Because the offset is inside `now`, server and
clients always agree on the weather, in a shots place too.

### 2.2 Marks, variants and the Almanac (`Mutation.luau`)

A crop carries a set of marks, stored as bits: 1 = Charged, 2 = Frosted, 4 = Prismatic. An event only rolls ripe
crops that lack its own mark. Marks never go away and never hurt a crop: there is no bad weather in StormGrow.

| marks | variant | value | how to get it |
|---|---|---|---|
| none | plain | x1 | |
| ⚡ | Charged | **x5** | a storm |
| ❄️ | Frosted | **x5** | a frost |
| 🌈 | Prismatic | **x8** | a rainbow |
| ⚡❄️ | Stormglass | **x25** (5 × 5) | a storm and a frost, in either order: keep a Charged crop 3.5 min until the frost |
| ⚡🌈 | Radiant | **x40** (5 × 8) | the :00 or :30 storm, then its rainbow 0 s later |
| ❄️🌈 | Aurora | **x40** (5 × 8) | a rainbow, then the frost 2.5 min later (or a Frosted crop kept until the next rainbow) |
| ⚡❄️🌈 | **Tempest** | **x200** (5 × 5 × 8) | the golden sequence: ripe at :00 or :30, kept until :06:30 or :36:30 |

Why these values:
* **Marks multiply.** A player who knows x5 and x8 can work out every variant without a table. A first draft gave
  the combos their own smaller values (x20/x30/x30/x100). Self-review caught that "Charged x5, then Frosted x5 = x20" reads
  as a cheat. The model was re-run with products: the normal player's brag moved from 36.7 to 36.6 min, and the combo
  player now reaches it inside the window too (38.0, was 41.5).
* **x5 singles.** Measured with the model (§2.6): x3 made the headline mechanic a loss, x4 made the forecast
  8 % faster to band 6, and x5 made it 13 % faster at the old band thresholds. x5 is the smallest round multiplier at
  which following the forecast clearly beats ignoring it (20 % with today's thresholds: 36.6 vs 45.8 min).
* **Keeping a marked crop for the next event is a real choice, not a trap and not a must.** Computed for a Charged
  Sunflower (grow 240 s, sell 750, seed 150). Cash it now: 3 750, plus about one more Sunflower's profit on the freed
  tile in the 255 s the hold would take (255/240 × 600 = 638), so 4 388. Keep it through the frost: 0.5 × 18 750 +
  0.5 × 3 750 = 11 250 expected. Over a whole session (modelled), the combo holder reaches band 7 at 75.5 min against
  120.8, and band 6 at 38.0 against 36.6, because early crops are short.
* **The Tempest (x200) needs the clock, not luck alone.** Modelled: a player who keeps marked crops for the next event
  finds the first Tempest at 21.4 min median (p10 8.0, p90 37.3). A player who harvests marked crops at once finds
  none in 4 hours. The Tempest rewards learning the golden sequence.
* **The odds are public** (Config replicates, and the Almanac panel prints "each ripe crop: 1 in 2 per storm"). This
  is honest odds on free weather, not gambling: nothing costs Robux, nothing is bought and rolled.

**Almanac:** 8 crops × 7 marked variants = **56 entries**. "Plain" is not an entry. An entry is granted by the
server's strike loop **when the mark lands** (the bolt is the discovery moment), never by a remote and never at
harvest. It is keyed by the string `"<cropId>:<marks>"` (§8.1).

### 2.3 Crops (`Config.Crops`, in unlock order)

| # | crop | unlock (coins) | seed | sells for | grows | profit / tile / s | notes |
|---|---|---|---|---|---|---|---|
| 1 | Radish | owned | **free** | 5 | 30 s | 0.167 | free forever: a player with 0 coins can always plant |
| 2 | Carrot | 50 | 5 | 20 | 60 s | 0.25 | |
| 3 | Corn | 250 | 20 | 80 | 2 min | 0.50 | |
| 4 | Tomato | 1 000 | 60 | 280 | 3 min | 1.22 | |
| 5 | Sunflower | 3 500 | 150 | 750 | 4 min | 2.50 | |
| 6 | Pumpkin | 10 000 | 400 | 2 400 | 6 min | 5.56 | the thumbnail crop |
| 7 | Watermelon | 35 000 | 1 000 | 6 500 | 8 min | 11.5 | |
| 8 | **Stormfruit** | 120 000 **and** band 6 | 2 500 | 20 000 | 12 min | 24.3 | only sold once your farm is in the Eye of the Storm (§6) |

Reasons: grow times go from 30 s to 12 min, so the first minutes are tap-heavy and the late game is idle. Each crop
earns 1.5-2.4 times the one before it (profit per tile per second, computed), so every unlock is felt. Unlock prices
are placed so a normal player buys something every 1.6-4.8 minutes from the Carrot (0.9 min) to the Watermelon
(27.7 min). The one longer gap (8.9 min) ends in the brag, which puts the Stormfruit on sale (modelled purchase
minutes, §2.6). Crops
unlock **strictly in order**, so the owned set is a count (`unlocked`, 1-8). Ownership is never inferred from the
selected seed (checklist trap). One tap harvests **and** replants the selected seed. If you cannot afford it, the tap
plants the best crop you can afford and says so (§12.3).

### 2.4 Farm, fields, server

| number | value | reason |
|---|---|---|
| farms per server | 6 (`Players.MaxPlayers = 6`, set at publish) | six rectangles fit a ring around the market with 27 studs between inner corners (computed below). The part budget (§3.5) is sized for six |
| tile | 8 studs (soil plate 7.6 + 0.4 gap) | at 30 studs a tile is about 78 px tall on a 360 px phone viewport with a 70° field of view (computed), well over 44 px |
| field | 3 × 3 = 9 tiles (24 studs square) | the whole field is within the 32-stud tap reach from its edge |
| fields per farm | 1 free, then 2-6 at **400 / 3 000 / 20 000 / 1 500 000 / 6 000 000** | fields 2-4 come at 7.2, 14.0 and 22.9 min (modelled), and 5-6 are long-term sinks at 57.6 and 104.3 min, so coins keep a use after the brag |
| farm footprint | 84 × 64 studs: a 10-stud porch strip, then two rows of three fields, 6-stud paths | farm *k*'s inner edge is 100 studs from the origin at yaw (k-1)·60°. Computed clearances: inner corners of neighbours 27.3 studs apart, outer corners 91.3 |
| market square | radius 36 around the origin | a 69-stud walk from market edge to porch (4.3 s at WalkSpeed 16, computed) |
| valley wall | invisible ring at radius 230 | a hazard's knock can never push anyone out of the world. The hills beyond are client scenery |
| start coins | 20 | Radish is free, so this only brings the Carrot unlock under a minute (modelled 0.9 min) |

### 2.5 Timers, limits, caches

| number | value | reason |
|---|---|---|
| tap reach | ClickDetector `MaxActivationDistance` 32, server re-check ≤ 40 studs from the root | the server check is the real one, because exploit tools fire ClickDetectors from anywhere. The 8 extra studs absorb latency |
| action rate | ≥ 0.12 s between a player's farm actions (server `tick()`) | about 8 taps/s, above any human. `tick()` and not `os.clock()`: deep-vein `Main.server.luau:1108` records that os.clock would freeze every cooldown headless |
| ripeness | strict `now >= plantedAt + grow` on the server | the client shows "ripe" 0.25 s after that, so a tap it offers is one the server accepts |
| autosave | every 60 s, plus on leave and in `BindToClose` | 6 writes/min for a full server, well inside the UpdateAsync budget |
| session lock TTL | 180 s, renewed by every autosave | three missed autosaves before another server may take the farm |
| lock wait | retry every 5 s, 6 times (30 s), then read-only | a fast server hop usually clears within that |
| `ServerNow` broadcast | 1 Hz | the client's clock for growth bars and the forecast. One attribute write per second |
| board write coalescing | at most one OrderedDataStore write per player per 30 s, and only when the count went up | a storm can grant several entries within seconds |
| public board cache | 60 s (`GetSortedAsync(false, 100)`, top 10 shown) | the standard's number. One read per minute per server |
| friends board | on demand. `GetFriendsAsync` capped at 200 friends. Scores come from the players in the server plus a top-500 page cache (5 pages of 100), refreshed at most every 120 s | at most 5 sorted reads per 2 minutes, only while someone looks at the friends view (§7) |
| name cache | per server, `GetNameFromUserIdAsync`, no expiry | names are never stored in DataStores |

### 2.6 Measured pacing (modelled; 200 sessions of 4 h per profile, random join phase)

**Profiles** (the human part, written down instead of hidden). Each profile sweeps the farm every *check* seconds,
and one tap (harvest + replant) costs *tap* seconds. It follows the HUD: while an event runs, or one starts within
*cue* seconds, ripe crops stay in the ground, except a crop that already has the running event's mark (the HUD shows
it as "tap to harvest xN"). It buys the cheapest affordable upgrade, and a new crop becomes the selected seed. From
band 2 on, it pays *dodge* seconds per hazard (one per 150 s). No offline growth, rest excluded.

| profile | check | tap | cue | dodge | extra |
|---|---|---|---|---|---|
| normal | 15 s | 1.0 s | 60 s | 1.5 s | |
| fast | 5 s | 0.7 s | 90 s | 1.0 s | |
| slow | 40 s | 1.5 s | 30 s | 2.5 s | |
| nohold | 15 s | 1.0 s | never holds | 1.5 s | ignores the forecast |
| combo | 15 s | 1.0 s | 60 s | 1.5 s | also keeps a marked crop when the next event (≤ 420 s away) could add a mark it lacks |
| planner | 10 s | 1.0 s | 90 s | 1.5 s | combo + plants the unlocked crop with the fewest Almanac entries |

**Minutes to reach each band (p10 / median / p90):**

| band | normal | fast | slow | nohold | combo | planner |
|---|---|---|---|---|---|---|
| 2 Golden Fields | 2.2 / 2.9 / 3.7 | 2.0 / 2.9 / 3.9 | 2.3 / 3.4 / 4.7 | 2.5 / 2.5 / 2.5 | 2.5 / 4.7 / 6.9 | 3.2 / 5.5 / 7.7 |
| 3 Windy Orchard | 6.5 / 7.9 / 9.2 | 6.6 / 8.3 / 10.4 | 7.6 / 9.0 / 10.6 | 6.9 / 6.9 / 6.9 | 8.2 / 10.1 / 13.3 | 8.2 / 11.0 / 14.5 |
| 4 Thunder Plains | 13.2 / 14.9 / 17.0 | 13.4 / 15.0 / 17.5 | 14.6 / 16.3 / 19.0 | 14.2 / 14.6 / 14.6 | 15.9 / 19.1 / 21.8 | 16.3 / 19.7 / 23.0 |
| 5 Frost Highlands | 20.8 / 23.2 / 26.6 | 20.5 / 23.1 / 27.2 | 22.2 / 26.6 / 28.9 | 26.1 / 30.5 / 31.4 | 21.9 / 25.8 / 29.6 | 22.2 / 27.0 / 31.2 |
| **6 Eye of the Storm (brag)** | **33.4 / 36.6 / 39.2** | 32.8 / 36.1 / 38.5 | 35.6 / 39.7 / 43.2 | 43.6 / 45.8 / 45.8 | 31.2 / 38.0 / 43.5 | 33.4 / 38.9 / 43.9 |
| 7 Starfall Summit | 113.8 / 120.8 / 129.5 | 104.3 / 108.6 / 114.9 | 110.5 / 124.0 / 135.8 | 188.0 / 192.8 / 199.5 | 62.4 / 75.5 / 95.8 | 57.5 / 67.9 / 83.8 |

| milestone | normal | nohold | combo | planner |
|---|---|---|---|---|
| first mark (min) | 0.7 / 1.9 / 4.1 | 1.2 / 6.9 / 38.0 | 0.7 / 1.9 / 4.1 | 0.7 / 1.9 / 4.1 |
| first Tempest (min) | none in 4 h | none in 4 h | 8.0 / 21.4 / 37.3 | 8.0 / 19.7 / 31.1 |
| Almanac entries at 30 / 60 / 180 min (median) | 8 / 13 / 15 | 2 / 3 / 5 | 13 / 21 / 26 | 14 / 25 / 48 |

Normal player, median minute of each purchase: Carrot 0.9 · Corn 4.4 · field 2 7.2 · Tomato 9.8 · field 3 14.0 ·
Sunflower 15.6 · Pumpkin 19.0 · field 4 22.9 · Watermelon 27.7 · Stormfruit 36.6 · field 5 57.6 · field 6 104.3.
Median lifetime harvest by minute: 3 → 175, 10 → 2 535, 20 → 28 005, 30 → 145 805, 37 → 317 800, 45 → 726 030,
60 → 2 176 425, 120 → 10 902 180. **The band thresholds in §3 were read off this curve and then re-measured.**

**The long-term goal** (40 sessions of 30 h): the planner completes all 56 entries at **3.7 / 4.3 / 4.9 h**
(entries at 1/3/10/20 h: 24/48/56/56). The combo player **stalls at 27** (none of 40 sessions finished in 30 h),
because it always plants the newest crop and never goes back to the old ones. So **the seed panel marks every crop
that still has entries to find** ("📖 3 to find", §12). Without that hint the Almanac is not completable in practice.

**How the numbers were tuned** (kept, because each step was a finding):

| step | normal → band 6 | nohold → band 6 | verdict |
|---|---|---|---|
| x3 marks, odds 0.35/0.35/0.30, cue holds every ripe crop | 37.6 | 31.4 | the headline mechanic lost money |
| odds 0.50/0.50/0.35 + harvest crops that already have the running event's mark | 31.8 | 31.4 | break-even |
| x4 marks | 28.8 | 31.4 | 8 % |
| x5 marks | 27.2 | 31.4 | 13 %, chosen (x6: 24.8, 21 %) |
| event 60 s instead of 90 s (at x4) | 28.3 | 31.4 | length barely matters |
| Stormfruit gated on band 6, fields 5-6 added, thresholds re-read from the curve | 36.7 | 45.8 | |
| combo values made products (x25 / x40 / x40 / x200), self-review | **36.6** | **45.8** | final |

Final sensitivity (normal, band 6 / band 7 median; baseline 36.6 / 120.8): cue 30 s → 38.0 / 130.8 ·
cue 90 s → 37.0 / 109.5 · events 60 s → 37.5 / 125.6. The brag stays inside 30-45 min for every setting tried.

---

## 3. Environment bands

### 3.1 Trigger: the game's own progress, never time

The progress value is **`harvested`**: lifetime coins earned from harvests. It only goes up, spending never lowers
it, and it is server-written to the player's `Harvested` attribute. It is the real measure of how much your farm has
grown. The client blends by it with `EnvBands.luau` (plus1-jump, verbatim). Every value glides with a 0.6 s half-life
(`EnvBands.approach`), so a big harvest (+2 400 in one tap) or a rejoin deep in the ladder never cuts. Lighting is
written at most 10 times/s, and only when a value changed. The band **name** is the band whose threshold you have
passed. The HUD shows it with the harvested total, so the chip and the sky always agree.

Fades are a third of each threshold (the blend starts at two thirds of it). `EnvBands.validate` accepts them:
every fade is ≤ its gap to the previous threshold (computed: 50 ≤ 150, 400 ≤ 1 050, 3 000 ≤ 7 800,
18 000 ≤ 46 000, 100 000 ≤ 245 000, 3.6 M ≤ 10.7 M).

### 3.2 The seven bands

| # | band | from (harvested) | fade | normal reaches it (median) | light | scenery ring (client) | critters | ambient weather | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌱 Sunny Meadow | 0 | – | 0 min | clear morning, ClockTime 9.5, fresh green grade | rolling green hills, oaks, a pond, a distant farmhouse | white and yellow butterflies | dandelion fluff | **none** (the first ~3 min are for learning) |
| 2 | 🌾 Golden Fields | 150 | 50 | 2.9 | late morning, ClockTime 11.5, warm yellow | wheat-gold hills, hay rolls, a turning windmill | bees, sparrow flocks | pollen motes | hay bale |
| 3 | 🍂 Windy Orchard | 1 200 | 400 | 7.9 | afternoon, ClockTime 15.5, amber | orange and red orchard hills, a red barn, a leaning scarecrow | crows circling | falling leaves | hay bale, crow |
| 4 | ⛈️ Thunder Plains | 9 000 | 3 000 | 14.9 | overcast late afternoon, ClockTime 16.8, violet-grey | a dark cloud bank on the horizon with silent distant lightning, a lone lightning rod on a hill | geese in V formations | drizzle | crow, ball lightning |
| 5 | ❄️ Frost Highlands | 55 000 | 18 000 | 23.2 | cold dusk, ClockTime 17.6, blue-white | snow-capped peaks, pines, a frozen waterfall | snow owls | light snow | snowball, ball lightning |
| 6 | 🌀 **Eye of the Storm** | 300 000 | 100 000 | **36.6** | golden hour inside a calm eye, ClockTime 17.2, warm with a strong bloom | **a slow-turning storm wall ringing the whole valley**, lightning veins inside it, a sunbeam on your farm, floating storm isles | storm sprites (glowing motes) | sparks drifting up | ball lightning, dust devil |
| 7 | ✨ Starfall Summit | 11 000 000 | 3 600 000 | 120.8 | night, ClockTime 22.5, deep blue | aurora ribbons, 3 000 stars, falling stars, lanterns on your fences | fireflies over the fields | star glints | ball lightning, snowball, dust devil |

Each band ≥ 2 minutes (modelled medians: band 1 lasts 2.9, the shortest after it is 5.0). Every band defines the
**same** lighting fields (ClockTime, Brightness, Ambient, OutdoorAmbient, ExposureCompensation, FogColor, Atmosphere
Density/Color/Decay/Haze, ColorCorrection Tint/Saturation/Contrast, Bloom Intensity). `tests/EnvConfig.spec.luau`
(copied from plus1-jump) enforces that. The exact colour values are set in `Config.Env.Bands` at build time and judged
in Studio (§15 #1). They are art, not balance.

### 3.3 Weather events on top of the band

The global event is an **overlay** (`EnvBands.overlay`), weighted 0 → 1 over 4 s at the start and 1 → 0 over 4 s at
the end, so the band stays underneath:

| event | overlay | effects (client) |
|---|---|---|
| ⛈️ storm | Brightness × 0.5, violet fog, higher Atmosphere density | heavy rain. A bolt from the sky onto every tile that takes a mark (the `LastStrike` attribute, §8.3). Distant ambient bolts every 3-6 s. A small flash per bolt within 60 studs, and a camera shake only for a strike within 20 studs of you |
| ❄️ frost | blue-white tint, saturation down | snowfall, white ground tint on your tiles, frost sparkle on crops that take the mark |
| 🌈 rainbow | brightness and saturation up | **a rainbow arc across the whole valley**, sparkles on crops that turn Prismatic |

### 3.4 Fx and signature particles (checklist §2, from the first build)

* Server, first thing: `Fx.applyLighting(Fx.Presets.Farm)`. `Farm` is a **new preset** added to the game's copy of
  `Fx.luau`, equal to band 1's lighting, so the first frame before the client's bands take over is already band 1.
* Signature particles: **ripe crops glow and bob** (anything the player chases glows). **Charged crops crackle**
  (blue sparks), **Frosted crops wear an ice shell**, **Prismatic crops cycle rainbow colours**. Combos layer their
  parts, and a Tempest gets all three plus a slow spin. The marks differ in **shape and motion, not only colour**
  (colour-blind check, §15 #5). Empty tiles you own have a faint rim glow: that is the onboarding.
* Client juice: `FxClient.flash` + `fovPunch` on the brag card and on a Tempest, `FxClient.shake` on a near strike.
  `FxClient.theme()` on every HUD frame.

### 3.5 Budgets (caps enforced in code, measured headless at every band, every seam and during every event)

| what | cap | how it is kept |
|---|---|---|
| server Parts | 1 400 | 6 farms × (54 soil plates + 54 tile hitboxes + fences, porch, sign ≈ 50) + market ≈ 150 + wall |
| client crop Parts | 1 620 | 6 farms × 54 tiles × ≤ 5 Parts per crop model, built by the client from tile attributes |
| client scenery Parts | 700 | per band, cross-faded two bands at a time |
| client PointLights | 12 | lanterns (band 7), the sunbeam (band 6), nearest first |
| weather emitters | 4 | `EnvBands.capRates` over the band's ambient weather plus the event's |
| mark emitters | 24 | nearest marked crops first. Farther ones keep their static look (ice shell, colour) without particles |
| concurrent bolts | 6 | nearest strikes first. A skipped bolt still leaves the mark's look on the crop |
| hazard Parts | 30 | one hazard at a time (§4) |

---

## 4. Hazards

**StormGrow keeps real hazards although it is an idle grower**, and differs from Grow a Crystal (which chose harmless
visitors, `grow-a-crystal/EYECANDY.md` §3) for three reasons. (1) The farm is outdoors and the loop is on foot: you walk
between six fields and the market, so a step out of a ring is a natural action, not a break in watching. (2) The
theme is weather: the storm that blesses your crops also sends ball lightning after you. (3) A hit costs only time
and never crops or coins. Hazards are client-only, so they must never touch server state, and they don't.

`Hazards.luau` is copied **verbatim** from plus1-jump with its spec. **Take the working copy at build time and
record its sha256:** on 2026-09-30 plus1-jump has an uncommitted `Hazards.threatLive` (review of 2026-09-27) that keeps
the ring and banner up for as long as a hit is still possible. StormGrow uses it for the ring, the banner and Rest's
`threat` input.

| rule | value | reason |
|---|---|---|
| interval | 120-180 s of play (`IntervalMin/Max`), clock frozen while resting | the standard: about one near-miss per 2-3 min (plus1-jump's spec measured one per 150.9 s for this interval, and the build re-measures it) |
| never two at once, none in band 1 | module rule / band 1 has no kinds | a due hazard in a quiet band is re-rolled, so band 2 never opens with a backlog |
| telegraph | ≥ 3.0 s (`MinTelegraphSeconds`), lane locks ≥ 1.5 s before arrival (`MinCommitSeconds`) | template values |
| where it can hit | **the red ring is the zone**: radius hitRadius + `PlayerRadius` 1.5, drawn exactly as `Hazards.zone` says. A hit needs you inside it (`checkHit`) | step out in any direction and you are safe. The ring is drawn from the same numbers the hit uses |
| a hit | horizontal knock + lift 8 studs/s (`KnockLift` ≤ 15), `PlatformStand` 0.9 s, shake + flash | costs about 2 s on flat ground, never crops, coins or marks |
| launch | only while grounded and not resting | template |

| kind | bands | speed | telegraph | commit | pass | hitRadius (model) | ring radius | lane length | knock | pitch |
|---|---|---|---|---|---|---|---|---|---|---|
| hay bale (rolls, wobbling) | 2, 3 | 16 | 3.5 s | 1.8 s | 2.0 s | 2.5 (5) | 4.0 | 56 | 34 | 0 |
| crow (swoops in low) | 3, 4 | 24 | 3.0 s | 1.5 s | 1.5 s | 1.8 (3) | 3.3 | 72 | 30 | 6 ± 4 |
| ball lightning (drifts, crackles) | 4, 5, 6, 7 | 18 | 3.5 s | 1.8 s | 2.0 s | 2.0 (3) | 3.5 | 63 | 38 | 4 ± 3 |
| snowball (rolls, grows) | 5, 7 | 20 | 3.2 s | 1.6 s | 2.0 s | 2.5 (4) | 4.0 | 64 | 34 | 0 |
| dust devil (spinning) | 6, 7 | 12 | 4.0 s | 2.0 s | 2.0 s | 3.0 (5 wide, 8 tall) | 4.5 | 48 | 30 | 0 |

Ring radius = hitRadius + 1.5 and lane length = speed × telegraph (computed). Lanes are **short (48-72 studs)** on
purpose: on flat ground a long lane starts above the top of a downward-looking camera. The longest flight is the dust
devil, 4.0 + 2.0 = 6.0 s, which sizes Rest's `PendingSeconds` (§5).

**The one genre adaptation, made in the glue and not in `Hazards.luau`:** plus1-jump's climber stands over open air,
so a lane may start below them. A farm has ground. The client passes `ctx.pitch = max(cameraPitch, -rad(ViewPitchDegrees))`
with `ViewPitchDegrees = 25`, so the view window's upper edge is never below 0°. `Hazards.plan` then clamps every kind
here (natural pitch 0-10°) to a start at or above the player's root height: **no lane ever starts underground**.
`SpreadDegrees = 35`, `KindFitDegrees = 25`, `MaxRetargetSpeed = 1.5`, `AimJitter = 1.0` are the template's values.
What the build must measure (`check_stormgrow_hazards.luau`, §13): every warning frame has the ring and the banner on
screen at camera pitches -60°..+20° (16:9 and 4:3); the hazard *model* is on screen from launch at the default zoom for
the pitches where that is possible, and the boundary is reported as measured; no lane point is ever below ground + 1
stud; walkers out of the drawn ring in 8 directions are never hit and players who stay are always hit.

Hazards never collide with, damage or even look at crops: the model passes through them (a hay bale rolling through
your pumpkins is a clip, not a loss).

---

## 5. Rest

`Rest.luau` is copied verbatim from plus1-jump with its spec. Config: `WakeOnMove = true`, `BlockWhileThreat = true`
(both mandatory in `Rest.validate`), `RequireGrounded = true`, `IdleSeconds = 20`, `WakeGraceSeconds = 0.4`,
**`PendingSeconds = 8`** (the longest hazard flight, 6.0 s, + 2 s, the template's own rule).

* **☕ Rest** (top bar): you sit down where you stand, the view softens, and the chip says "☕ Resting — the wind
  leaves you alone". Press again or move to carry on. Stand still for 20 s and you rest automatically (💤).
* **What rest pauses: only the hazard clock**, frozen and never reset, so toggling cannot thin hazards.
* **What rest does not pause:** growth and the weather. The weather is one global clock that cannot stop for one
  player. And a player standing still gets exactly the same growth and marks without resting, so **rest earns nothing
  that standing still does not**.
* **Why it cannot be exploited:**
  1. it cannot start in the air or with a hazard inbound (`BlockWhileThreat`, fed by `Hazards.threatLive`). Pressing it
     then queues the request, and the hazard still arrives;
  2. **any farm action wakes you**, as moving does. That is StormGrow's addition, and it lives in the glue: every
     server-accepted plant, harvest, unlock or purchase bumps the player's `ActionSeq` attribute, and the client calls
     `Rest.stop` when its own `ActionSeq` changes. Taps do not move the character, so without this rest would be a
     hazard-free farming mode;
  3. nothing is raced: StormGrow has no round, no raid and no timed score. The board counts discoveries (§7).
* Roblox's own idle kick (about 20 min without input) still applies. Nothing is lost, because the farm is saved
  every 60 s and on leave.

---

## 6. The brag moment and the long-term goal

**The brag: "🌀 YOUR FARM IS IN THE EYE OF THE STORM"**, when `harvested` passes 300 000.
Modelled: **normal 36.6 min** (p10 33.4, p90 39.2), fast 36.1, slow 39.7, combo 38.0. Inside 30-45 min for all four. What happens:
a title card with a white flash and FOV punch, and over 4 s the storm wall rises around the valley and a sunbeam falls
on your fields. The Stormfruit seed goes on sale. A server-wide toast says "🌀 *Name*'s farm entered the Eye of the
Storm". It plays only when you cross the threshold during play, after your profile has `Loaded`. A player who joins
already past it gets a quiet "🌀 Eye of the Storm" chip instead (plus1-jump's first-card rule).

**The skill brag:** the first **Tempest** crop (x200), with a server-wide toast "⚡❄️🌈 *Name* grew a TEMPEST
Pumpkin!". Modelled: 21.4 min median for a player who keeps marked crops for the next event, never in 4 h for one who
does not. Learning the golden sequence is what unlocks it.

**The long-term goals, beyond the brag:**

| goal | modelled |
|---|---|
| field 5 / field 6 | 57.6 / 104.3 min (normal) |
| band 7 ✨ Starfall Summit | 120.8 min normal (3.3 × the brag, under 3 h); 75.5 combo; 67.9 planner |
| **complete the Almanac, 56/56** (the leaderboard metric) | planner 3.7 / 4.3 / 4.9 h. Needs the "📖 N to find" hint (§2.6) |

---

## 7. The highscore board

**Metric: Almanac entries discovered (0-56), ties broken by who reached the count first.**

Why a script cannot inflate it:
* only the server's strike loop grants an entry, at a strike tick, on a crop that the server clock says is ripe. No
  RemoteEvent, ClickDetector or attribute can grant one (§10);
* the rate is capped by a **global** clock: every server has the same six storms, six frosts and two rainbows an hour.
  A perfect script plays no better than a perfect human, hopping servers gains nothing, and the count stops at 56;
* the tie-break time is the server's own time of the grant, never a client time.

A script can play all night, as a person can. It still gets no more weather than the clock gives, and at 56 the one
who got there first stays ahead.

**Storage** (the standard's format): OrderedDataStore `StormGrowAlmanac_v1`, key `u_<userId>`, value
`count * 2e9 + (2e9 - reachedAtUnix)`, an integer. The largest value is 56 × 2e9 + 2e9 = 1.14e11 (computed), far
under 2^53. Written through `UpdateAsync(max(old, new))`, so a stale server can never lower a score. Written only when
`count` went up, coalesced to one write per player per 30 s, flushed on leave, pcall'd, and **only from a session that
holds the save lock**, so a read-only session cannot publish a count it will not keep. **Horizon:** `2e9 - reachedAt`
stays positive until Unix time 2e9 = 2033-05-18 03:33:20 UTC (computed). A v2 moves the epoch before then.

**Public view:** `GetSortedAsync(false, 100)`, the top 10 shown, cached 60 s per server.
**Friends view** (on demand, only while someone looks at it): `Players:GetFriendsAsync(userId)`, paged, capped at 200.
Scores come from (a) players in this server, from memory, and (b) the top-500 cache (5 pages of 100, refreshed at most
every 120 s), all pcall'd. You are always in your own friends view. **Empty state:** "None of your friends has an
Almanac entry in the top 500 yet. Invite one: there are six farms in this valley." **Failure state:** "Couldn't load
your friends right now. Showing everyone." Friends outside the top 500 are not shown in v1 (§16), and the view says
"top 500" so that is not hidden.

**In the world:** a physical board on the market square, facing the spawn side, with a ProximityPrompt "🏆 Friends /
Everyone" (per player). Each player sees their own view through a SurfaceGui in their PlayerGui (`Adornee` = the board),
so two players at the same board can see different views. Rows are rank, name and 📖 count, and your own row is pinned at the
bottom ("You: 📖 12"). Names come from `GetNameFromUserIdAsync`, cached, never stored. The rows are public data sent over
the `Board` RemoteEvent. The `leaderstats` show `Coins` and `Almanac` in the player list.

---

## 8. Data model

### 8.1 What persists: DataStore `StormGrow_v1`, key `u_<userId>`, one document per player

```
{
  v          = 1,
  coins      = <integer >= 0>,
  harvested  = <integer >= 0, only ever increases>,        -- the band progress value
  fields     = <1..6>,
  unlocked   = <1..8>,                                      -- crops unlock strictly in order: the owned set IS a count
  selected   = "<cropId>",                                  -- validated <= unlocked on load and on every Select
  tiles      = { ["<field>_<tile>"] = { c = "<cropId>", at = <plantedAt, Unix s>, m = <marks 0..7> } },
  almanac    = { ["<cropId>:<marks>"] = <first-seen Unix s> },
  almanacCount = <0..56>, almanacAt = <Unix s the count last went up>,
  harvests   = <integer>,                                   -- drives the first-minute hints only
  session    = { token = "<GUID of this server-session>", until = <Unix s> },
}
```

* **String keys everywhere** (checklist trap: sparse integer keys come back as strings). There is no integer-keyed
  table in the profile.
* **Load normalises:** a tile with an unknown crop id is cleared (its price is unknown, so there is nothing to refund).
  Marks outside 0-7 are cleared. Tiles beyond the owned fields are dropped. `at` in the future is clamped to now.
  `selected` above `unlocked` falls back to the newest owned crop. Almanac keys that name no known crop and mark are
  dropped, and `almanacCount` is recounted from what remains. The board is never lowered by this, because its writes
  are max-merged (§7). Each fix logs a warning.
* **Size:** 54 tiles × ~40 bytes + 56 entries × ~25 bytes ≈ 3.6 KB (computed), far under the 4 MB limit.
* **Growth is stateless**: ripeness is always `now >= at + grow`, so offline growth needs no code. **Marks never
  happen offline**: they need a strike tick in a server your farm is in. This is deliberate (the storm is a live show),
  and the store text says "crops keep growing while you are away", not that they mutate.

### 8.2 What is server-only

| state | where | why |
|---|---|---|
| every profile, authoritative | the server script's tables (ServerScriptService code is never replicated) | the server is the only writer |
| **the strike RNG** | one `Random.new()` per server, unseeded (Roblox seeds it from entropy), in the server script | this is the only unpredictable thing in the game. Nothing public seeds it, so there is no seed to memorise or brute-force (fork-tower `REVIEW-4.md`), and nothing visible is derived from it until a strike has happened |
| session tokens, rate-limit clocks, pending board writes, board and name caches | server script tables | not secret except the token, and none of it needs to replicate |
| any server-only Instance | `ServerStorage` (none planned) | anomaly-observatory `CLAUDE.md`: "ServerStorage, not the zone". Never an attribute or an Instance under workspace, ReplicatedStorage or the player |

### 8.3 What replicates, and why it is safe

**StormGrow has no hidden answer to leak.** The forecast is public on purpose. The only unpredictable thing, which
ripe crop the next bolt picks, is drawn by the server at the moment it strikes.

| replicated | contents | why it is safe |
|---|---|---|
| tile hitboxes in `workspace.Farms.Farm_<k>` | attributes `Owner` (userId), `Crop`, `PlantedAt`, `Grow`, `Marks`, `LastStrike` | all facts anyone standing at your field can already see. Nothing about the future |
| `workspace` attribute `ServerNow` | the server clock, 1 Hz | public by design |
| `ReplicatedStorage` | `Config` and the pure modules (`Weather`, `Growth`, `Mutation`, `Economy`, `Farm`, `EnvBands`, `Hazards`, `Rest`, …) | the schedule and the odds are public by design. No seed exists |
| Player attributes | `Coins`, `Harvested`, `Fields`, `Unlocked`, `Selected`, `AlmanacCount`, `AlmanacBits` (56 × "0/1", crop-major), `Loaded`, `ActionSeq`, `Slot` | the player's own progress, harmless to anyone else. Attributes replicate with the Instance, so there is no RemoteEvent join race (grow-a-crystal review finding 1: a queued RemoteEvent reaches only the first connection) |
| `leaderstats` | `Coins`, `Almanac` | the player list |
| RemoteEvents, server → client | `Toast(text)`, `Board(mode, rows)` | text and public board rows. **Each has exactly one client connection** (in `Hud.client`) |
| RemoteEvents, client → server | `Select(cropId)`, `Unlock()`, `BuyField()` | requests, validated server-side (§10). Planting and harvesting go through tile ClickDetectors, which pass the player |

### 8.4 Saving rules (the standard, applied)

* Every DataStore call is pcall'd. The load uses `UpdateAsync` and takes the lock (`session.token`, `until = now + 180`).
  If another live token holds the lock, it retries every 5 s up to 6 times. Until the lock is taken the session is
  **read-only** (`canSave = false`), with the toast "Your farm is open in another server — progress here won't save".
  **A failed load never writes a default profile over real data.** The session plays read-only with the same toast.
* **Every write carries the owner token**. The transform returns nil (abort) unless `old.session.token == myToken`.
  This includes the release on leave (`until = 0`), because a late release must never unlock a record the next session
  already holds (fork-tower `REVIEW-4.md` §10).
* **One-time grants: none in v1.** There are no codes and no daily rewards. The 20 start coins exist only in the
  default profile, which is written once, by the first successful locked save.
* The profile is one document, so a harvest's coins and its cleared tile are saved together or not at all. A crash
  rolls both back and nothing is duplicated.

---

## 9. Spawn placement (`robloxemu/SPAWN-ORDER.md`)

* Each farm has a real `SpawnLocation` **`FarmPad_<k>`** on its porch (6 × 1 × 6, `Neutral = true`), rotated to face
  field 1. **It is `Enabled` only while the farm is claimed.** The market has **`MarketPad`**, always enabled, first in
  a depth-first walk of Workspace, for the one case with no free farm.
* `PlayerAdded` claims the first free slot and sets `plr.RespawnLocation = FarmPad_<k>` **synchronously, before any
  yield** (before the profile load, which yields). The engine then places the character on the right pad on the
  first spawn and on every respawn.
* Facing: the engine's placement may not keep the pad's yaw, and a CFrame written inside `CharacterAdded` is thrown away
  one frame later. So the handler **waits for the character to be parented** (`while char.Parent == nil and frames < 300
  do task.wait(1/60)`), re-reads the slot, and only then writes `CFrame.lookAt(padTop + 3, field1Centre)`. This is
  SPAWN-ORDER §3's second pattern, the one grow-a-crystal ships. If the engine does keep the yaw, the write is a no-op.
* Leaving releases the slot after the final save: the pad is disabled, the tile attributes are cleared, and the index
  is recycled (the unbounded-coordinates trap). The farm geometry stays built for all six slots from server start.
* **Check** (`check_stormgrow_spawn.luau`): six players join and six land on their own porch (XZ within 3 studs, above
  the pad, not the Y to the centimetre, per SPAWN-ORDER §7), each facing field 1 (dot > 0.9). A respawn lands in the
  same place. A leave then a join reuses the slot. The only enabled pads are `MarketPad` and the claimed ones.

---

## 10. Anti-exploit model

| attempt | what stops it |
|---|---|
| fire a tile's ClickDetector from far away or for someone else's farm | the server checks `Owner == player`, the root within 40 studs, and ≥ 0.12 s since the last action. Each refusal says why (§12.3) |
| harvest early | strict server ripeness on the server clock, no grace |
| claim a mark or an Almanac entry | impossible: only the server's strike loop sets marks. No remote accepts marks, entries or counts |
| predict the next strike to harvest the "wrong" crops early | the strike RNG is server-only, entropy-seeded and drawn at the tick. Nothing replicated says what comes next |
| write coins, harvested or marks from the client | attributes are server-written. Client writes do not replicate, and the server never reads its own values back from Instances |
| buy out of order or below price, or Stormfruit early | `Unlock()` takes the next crop only, checks price and the band gate (`harvested >= 300 000`) server-side, and says why when it refuses |
| select a locked seed | `Select` is validated against `unlocked`. A plant uses the server's selection |
| hop servers for more weather | the clock is global UTC: every server has the same events |
| rejoin to re-roll | nothing is rolled at join. Marks and tiles persist and strikes happen only at ticks |
| play two servers at once | session lock with an owner token on every write (§8.4) |
| inflate the board | the metric comes from the strike loop, is capped by the clock and by 56, is written by the server with a server time, and only upward (§7) |
| rest as a shield | rest only freezes the hazard clock, cannot start with a threat inbound, and any move or farm action ends it (§5) |
| delete hazards on the client | hazards are client-only by design. Deleting them saves about 2 s per 10 min, and nothing server-side depends on them |
| ride a knock somewhere | knock lift ≤ 8 studs/s, flat valley, walls at radius 230. There is nothing to reach |
| autofarm script | cannot beat the grow timers or the weather clock. It equals a perfect human, the board stops at 56, and ties go to whoever got there first |

---

## 11. The first 60 seconds of a new player

Targets. `check_stormgrow_firstmin.luau` walks them through the real server and HUD. Minutes marked (m) are modelled.

| time | what happens | on screen |
|---|---|---|
| 0 s | `PlayerAdded`: slot claimed, `RespawnLocation` set before any yield | "🌱 Loading your farm…" until `Loaded` |
| ≈ 0 s | the character lands on your porch, facing field 1: nine empty tiles with a soft rim glow, 8-40 studs away | your name on the farm sign |
| profile loaded | 20 coins, Radish selected (free) | hint **"Tap a glowing tile to plant a Radish (free)"** with an arrow to the nearest tile |
| **≤ 5 s** | first tap plants the first Radish (the checklist's 5-second rule) | sprout pops, "+1 🌱" |
| ≈ 5-15 s | the other eight tiles get planted, about a tap per second | hint "Plant the rest: tap each glowing tile" |
| from 0 s | the forecast chip at the top: "Next ⛈️ Storm in 3:12" | tap it for the next 30 minutes |
| ≈ 35 s | the first Radishes ripen: glow and bob | hint **"Ripe! Tap to harvest — it sells and replants (+5)"** |
| ≈ 45-55 s | nine harvests put 65 coins in hand (computed: 20 + 9 × 5) | Carrot pulses in the seed panel: "Unlock Carrot — 50". Modelled median unlock: 0.9 min |
| 60 s before any event | banner "⛈️ Storm in 1:00 — ripe crops left in the ground can turn ⚡ Charged (x5)" | the HUD's hold cue (the model's *cue*) |
| first event | inside 3.5 min wherever you joined (computed, §2.1). **First mark: 1.9 min median (m), p90 4.1** | bolt, crackle, "⚡ NEW in the Almanac: Charged Radish" |

Hints come from state (`harvests`, empty and ripe tile counts, coins) and need no tutorial flag: a returning player
with a planted farm never sees them.

---

## 12. HUD (phone first)

### 12.1 Layout
* **A root Frame owns the `UIScale`**, sized `1/scale`. `Responsive.luau` is copied verbatim. The layout re-runs on
  `ViewportSize` and `TouchEnabled` changes.
* **Top left** (not tappable): 🪙 coins, 🌾 harvested, 📖 n/56.
* **Top centre:** the forecast chip ("⛈️ STORM — 0:42 left" / "Next ⛈️ Storm 3:12 · ❄️ Frost 8:12"); tap it for a
  30-minute timeline. Under it, the band chip ("🌾 Golden Fields · 🍂 Windy Orchard at 1 200"). Toasts and the hazard
  banner ("⚠️ BALL LIGHTNING ◀ — step out of the ring") go below that and are not tappable.
* **Top right:** ☕ Rest, 📖 Almanac, and 🌱 Seeds when the layout is compact.
* **Right side panel: Seeds.** A `ScrollingFrame` through `Responsive.sideWidth`/`fitHeight`, collapsed behind 🌱 when
  compact. Each row shows the crop, seed price, grow time, a **"⚡ ripe for the :20 storm" tag** when a seed planted now
  would be ripe inside the next event's window (pure `Weather.catchesEvent(now, grow)`), **"📖 N to find"** for crops
  with missing Almanac entries, and the unlock price or the band gate on locked rows. Below the list: "🧱 Next field —
  3 000".
* **Almanac:** a centred modal (8 × 7 grid; found entries lit; the combo recipes printed; the odds printed). **Opening it
  hides the Seeds panel**, so no two visible panels overlap and rule 4b holds without an exception.
* **Nothing tappable in the bottom-left or bottom-right bands**, and nothing tappable at the bottom at all. Every tap
  target is ≥ 44 screen px on touch.
* **Gate:** `robloxemu/check_stormgrow_hud.luau` runs `hudcheck` with **`overlap = true`** across its viewports, plus a
  warmup that opens the Seeds panel, the timeline and the Almanac in turn.

### 12.2 In the world
Tiles are ClickDetector hitboxes (7.6 × 6 × 7.6, invisible) over the soil plates. Client crop Parts are
`CanQuery = false` so a tap on a tall sunflower lands on its own tile, never the one behind it. Hovering with a mouse
shows the tile's state ("Pumpkin · ripe in 1:12", "⚡ Charged Pumpkin · tap for 12 000").

### 12.3 No silent no-ops (every refusal says why)
"This is *Name*'s farm" · "Walk closer to tap this crop" · "Ripe in 0:12" · "Corn costs 20, you have 12 — planted a
Carrot (5) instead" · "Unlock Corn for 250 — you have 180" · "Stormfruit only grows in the Eye of the Storm: harvest
300 000 to get there" · "Next field: 3 000 — you have 2 140" · "Easy — one tap at a time" (the rate limit, at most one
toast per 2 s) · "Your farm is open in another server — progress here won't save" · "Couldn't load your farm — nothing
will be saved this session. Rejoin to try again".

---

## 13. Build plan and gates (for the builder)

**Layout** (deep-vein's): `default.project.json` maps `src/server` → ServerScriptService, `src/client` →
StarterPlayerScripts and `src/shared` → ReplicatedStorage. Plus `tests/*.spec.luau`, `README.md`, `CLAUDE.md`,
`EYECANDY.md`, `MARKETING.md`, and a `.gitignore` with `publish_*.bat` / `publish_*.sh`. Shared modules take their
dependencies as arguments. `require("./X")` works only in the CLI.

| file | kind | spec (TDD, failing test first) |
|---|---|---|
| `Config.luau` | every tunable in §2-§5 | `EnvConfig.spec` (bands share fields, fades validate, hazard config validates, ring < 5 studs, `PendingSeconds` ≥ longest flight + 2, `ClockOffsetSeconds == 0`) |
| `Weather.luau` | schedule, `at(t)`, `nextEvent(t)`, `perTick`, `catchesEvent(now, grow)` | `Weather.spec`: every second of 24 h classified, rainbow only after the :00/:30 storms, the 210 s longest gap, the per-tick odds give P over a full event |
| `Growth.luau` | stage 0-1, `isRipe` | `Growth.spec` |
| `Mutation.luau` | mark bits, variant names, multipliers, almanac keys and bits, `strikeTick(tiles, kind, now, rand)` | `Mutation.spec`: only ripe crops, only missing marks, rand injected, 56 keys, measured P over 100 000 simulated events |
| `Economy.luau` | plant, harvest, unlock, buy field, fallback crop | `Economy.spec`: never negative coins, Radish always plantable, strict order, band gate |
| `Farm.luau` | slot frames, field and tile positions, pad CFrames | `Farm.spec`: no overlap between slots, every tile inside its field, the 27-stud clearance |
| `Board.luau` | encode/decode, max-merge, friends assembly, empty and failure texts | `Board.spec` (the emulator has no `GetFriendsAsync`, so the assembly is pure) |
| `Profile.luau` | default, normalise-on-load | `Profile.spec`: string keys only, every normalisation in §8.1 |
| `EnvBands` / `Hazards` / `Rest` / `Fx` / `FxClient` / `Responsive` / `Rng` | **verbatim** copies, sha256 recorded (Fx gains the `Farm` preset) | their own specs, copied |
| `tests/Pacing.spec.luau` + `tests/FarmModel.luau` | this file's model rebuilt on the real modules | asserts: normal brag in 30-45 and within 5 min of 37.5; fast and slow inside 30-45; nohold slower than normal; every band ≥ 2 min; band 7 < 3 h; planner completes 56 < 8 h |
| `src/server/Main.server.luau` | authoritative glue | the headless checks below |
| `src/client/Hud.client.luau`, `Farm.client.luau` (crop models, marks, bolts), `Sky.client.luau` (bands, events, scenery, critters, hazards, rest) | display | the headless checks below |

**Headless checks** (`robloxemu/check_stormgrow*.luau`; rebuild the bundle before every run with
`py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau`):
`check_stormgrow` (**the walk**: join → plant 9 → harvest → unlock Carrot → advance to a storm → marks land only on
ripe crops → an Almanac entry → harvest a Charged crop pays x5 → buy field 2 → leave → rejoin keeps coins, tiles,
marks and the Almanac), `_spawn` (§9), `_firstmin` (§11), `_hud` (§12), `_env` (bands follow `Harvested`, glides,
budgets at every band, seam and event), `_hazards` (§4), `_rest` (§5: no start with a threat, an action wakes, the
toggle probe does not thin hazards), `_board` (write only on improvement, max-merge, cache counts, the failure path),
`_save` (lock, owner token on release, read-only when locked, a failed load writes nothing), `_wire` (sweep every
replicated property, attribute and remote payload: no session token, and nothing that names a future strike).
Every new assertion is mutation-tested with a control, as in SPAWN-ORDER §6.

---

## 14. Ship documents (drafts; the builder re-checks every claim against the code)

### 14.1 Store text (for `README.md`; 997 characters, ASCII only, measured on this draft)
```
The weather here runs on the real clock, and it is the same in every server. A storm breaks every ten minutes, starting on the hour. Frost comes five minutes after each storm breaks, and at :00 and :30 a rainbow follows the storm.

Only ripe crops catch it. Lightning makes a crop Charged, worth x5. Frost makes it Frosted, also x5, and the rainbow makes it Prismatic, x8. Leave a Charged pumpkin in the ground until the frost and it can become Stormglass, x25. A crop that catches all three is a Tempest, x200, and the whole server hears about it.

So you plan: plant so your crops are ripe when the storm hits, watch the bolts land, then harvest. The forecast is always at the top of the screen.

Eight crops, six fields and an Almanac of 56 mutations to find. The sky over your farm changes as the farm grows, from a sunny meadow to the eye of the storm. Crops keep growing while you are away. The leaderboard counts Almanac discoveries, for everyone and for your friends.

Nothing costs Robux.
```

### 14.2 Thumbnail shots (1920 × 1080, for `EYECANDY.md`)
Staging for all of them: build a shots place with `rojo build`. Turn Studio API access off, so nothing reaches real
saves. In the place's own `ReplicatedStorage.Config` only, set `Weather.ClockOffsetSeconds` to land on the event. Set
the band from the command bar (Server): `plr:SetAttribute("Harvested", n)`. That drives the client's sky, and the
server rewrites the attribute only on a harvest.
1. **"The storm changes everything"**: storm, band 4. Low camera (3 studs up, 20 studs from a ripe Pumpkin) as a bolt
   hits it, violet sky, the avatar looking up. Take a burst: one wave every 5 s.
2. **"Eye of the Storm"**: band 6. Aerial from 120 studs over the market, looking at your farm: the storm wall around
   the valley, the sunbeam on your fields, Stormfruit glowing.
3. **"Rainbow harvest"**: rainbow at :01:30, band 3. Camera behind the avatar tapping a Prismatic Pumpkin, the arc
   across the valley.
4. **"Tempest"**: a Tempest Pumpkin close up, all three marks, the server toast visible. At the real odds, nine ripe
   Pumpkins give a Tempest in one golden sequence only 56 % of the time (computed: 1 - (1 - 0.5 × 0.35 × 0.5)^9). So in
   the shots place's own Config, also set `Weather.Chance` to 1 for all three events, with `ClockOffsetSeconds` landing
   just before :00.

### 14.3 Clips (7-15 s, 1080 × 1920, for `MARKETING.md` / `tools/film_game.py`)
1. **The storm breaks** (12 s): clear sky, then the first bolts light nine ripe Pumpkins blue. Stage it with
   `ClockOffsetSeconds` putting the storm 5 s into the clip.
2. **Cashing a Charged field** (10 s): tap nine Charged crops, x5 numbers popping.
3. **Dodging ball lightning** (8 s): the ring, a step out, the ball passes through the crops.
4. **Rainbow after the storm** (12 s): the storm fades, the arc rises, crops turn Prismatic.
5. **TEMPEST** (10 s): the :05 frost hits a Radiant crop, it turns Tempest, then the toast and the flash.
6. **Into the Eye** (12 s): cross 300 000 with one harvest, the card, the storm wall rising.
7. **Frost on the fields** (8 s): band 5 frost, snow, crops icing over.

---

## 15. Needs Studio (only real rendering, input and live services can settle these)

1. **Every band's look and every event overlay**: exposure, fog against Atmosphere, bloom in band 6, crop readability
   at night in band 7 and the lantern strength.
2. **The lightning bolt** (segmented neon or Beam): does it read as lightning; flash strength; thunder timing.
3. **The rainbow arc** across the valley: neon parts or a Beam; visible on a phone at distance; at night in band 7.
4. **The storm wall** (band 6), giant client parts 250-400 studs out: culled at low graphics quality? If so, closer and
   smaller.
5. **Crop models**: 8 silhouettes at growth stages; the marks readable at 30 studs on a phone, and Charged, Frosted
   and Prismatic told apart by shape and motion for a colour-blind player.
6. **Tapping tiles on a phone**: hitbox size at the usual zoom, taps on tall crops, ClickDetector on touch.
7. **The spawn**: does the engine keep `FarmPad` yaw; does the post-parent write look like a snap.
8. **Hazards on flat ground**: do lanes start on screen at a phone's usual camera; a hay bale through crops and fences;
   the knock with `PlatformStand` on flat ground; how a knock with nothing visible looks to other players.
9. **Rest's sit** (`Humanoid.Sit` without a seat): does it replicate; does a tap wake it as designed.
10. **The top bar on a real phone**: notch and safe area, forecast text length, emoji in `TextScaled` labels.
11. **Frame time** on a mid/low phone during a storm with six full farms (1 620 crop parts, 24 mark emitters, rain).
12. **Live services**: `GetFriendsAsync` and OrderedDataStore with real friends and real throttles; the session lock
    across a real fast server hop.
13. **Two servers side by side** show the same weather to the second.
14. **Server-wide toasts** (Tempest, Eye) in a full server: exciting or spammy.
15. **Sound**: rain, thunder, frost chime, rainbow chime, harvest pop. This needs chosen audio assets. v1 is silent
    until they are picked.
16. **Publish settings**: `MaxPlayers = 6`.

---

## 16. Cut from v1, and why

| cut | why |
|---|---|
| per-save procedural farm layout (the radar's differentiator) | without obstacles to clear it is randomised decor, which is thin. The global weather clock is the differentiator built well instead |
| Tremor and Eclipse events (radar) | replaced by Frost and Rainbow (this workflow's brief: lightning, frost, rainbow). A tremor rewrites terrain (build cost), and an eclipse fights the band lighting |
| Rebirth / prestige | plus1-jump's rebirth became an owner question (its `EYECANDY.md` §11). The Almanac and fields 5-6 carry the long term |
| storm shelters, bad weather | there is no bad weather to shelter from. StormGrow is cozy |
| forecaster as an upgrade | the forecast is the point and belongs to everyone, free |
| mutations while offline | the storm is a live show, and offline rolls would make logging off the best strategy |
| basket and sell stall, seed inventory | one tap harvests, sells and replants. Fewer systems, better on a phone |
| auto-harvest | the tap is the decision (harvest now or hold) |
| promo codes | one-time grants need an atomic flush, and v1 needs none |
| gamepasses, anything that costs Robux | the owner's rule for v1 |
| trading, visiting, PvP | the radar's own exclusions |
| friends outside the top 500 on the friends board | per-friend reads do not fit the DataStore budget. The view says "top 500" |
| band emoji on the board | the board's value holds only the count |
| 10-15 crops (radar) | 8, each with its own model, done well |
| music and sound | needs assets (§15 #15) |

## 17. Deviations from the radar brief (the owner may veto any of these)

1. Events are **Storm / Frost / Rainbow**, not Storm / Eclipse / Tremor.
2. **No per-save procedural layout** in v1.
3. **No rebirth** in v1.
4. **Six players per server**, each with a fixed farm slot.
5. The board ranks **Almanac discoveries**, not coins: coins can be ground out by anything that clicks, and
   discoveries are capped by the weather clock.

## 18. Self-review (done before handing over)

* **Placeholders:** none. Band colour values are delegated on purpose to build time plus Studio (§3.2, §15 #1),
  because they are art, not balance.
* **Contradictions checked:** events 90/90/60 s everywhere (§2.1, the model, §3.3). x5/x5/x8/x25/x40/x40/x200 in §2.2,
  the model and the store text. Thresholds 150 / 1 200 / 9 000 / 55 000 / 300 000 / 11 000 000 in §3.2, §6 and the model.
  Fields 400 / 3 000 / 20 000 / 1.5 M / 6 M in §2.4 and the model. `PendingSeconds` 8 = 6.0 + 2 (§4, §5). Start coins
  20 (§2.4, §8.4, §11). Six slots (§2.4, §9, §17). The rest wake-on-action rule in §5 and §10.
* **What the model does not cover**, so the build must measure it: offline growth (it only makes things faster),
  hazard hits for a player who ignores warnings, walking time between fields (inside *tap*), and a real player's
  reading of the seed-panel tags.
* **Known limits kept on purpose:** the tie-break horizon of 2033-05-18 (§7); marks never happen offline (§8.1); a
  resting player's crops still take marks, exactly as a player standing still (§5).
