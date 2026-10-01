# Meteor Drop Tycoon: design spec (v1)

**Status (2026-10-01): built from this spec; see `CLAUDE.md` for the state and the gates.** The paragraph below is the design-stage status.

**Status at design time: design only.** No game code exists. Nothing is committed, pushed or published, no universe exists,
and Studio has not been opened. Written 2026-09-30 from `docs/game-radar/2026-09-28-roblox-game-radar.md` §3
"Mineshaft Drop Tycoon" (line 208), rethemed as the orchestrator asked: meteors fall from the sky onto the
player's own plot; you collect them and upgrade the Collector and the Smelter. It keeps that file's signal #4,
a pure drop-and-collect chill loop with no stealing, raiding or PvP. It is held to
`docs/complete-game-standard.md` from the first build and follows `docs/new-game-checklist.md`. The theme
stays away from mines and digging, because `deep-vein/` already covers that.

## How to read the numbers

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.luau`. Run it with `luau design/model.luau 2>&1` (27 s, deterministic: two runs gave the same md5, `6860497a...`). The output is saved as `design/model.out.txt`. The model is a design-time tool, not game code. |
| **[T]** | Taken from a template this game copies (`plus1-jump`, `deep-vein`, `vault-runners`, `steal-a-cryptid`), where it was measured or reviewed. The source file is named. |
| **[R]** | A design rule or arithmetic, worked inline. |
| **[A]** | An assumption. The model's player profiles are assumptions, and every number derived from them inherits that. The first real play session replaces them. |

The model's player profiles, all **[A]**:

| profile | react s | retarget s | walk efficiency | opens the shop every | s per purchase | hazards that hit |
|---|---|---|---|---|---|---|
| fast | 0.4 | 0.2 | 0.95 | 10 s | 0.8 | 10 % |
| **normal** | 0.8 | 0.4 | 0.85 | 20 s | 1.2 | 25 % |
| slow | 1.5 | 0.8 | 0.70 | 45 s | 2.0 | 40 % |
| bot (the script bound) | 0 | 0 | 1.35 (the trusted-speed cap, section 12) | every 0.1 s | 0 | 0 % |
| cheapest (sensitivity) | as normal, but ignores the HUD's star and buys the cheapest lit upgrade | | | | | |

Every profile except `cheapest` buys what the HUD's star recommends (section 4.4). This follows +1 Jump's
lesson: model the player who does what the HUD tells them. The model walks in straight lines at
16 studs/s × efficiency. It is not a physics model.

---

## 1. Core loop

Meteors fall out of the sky onto your own round plot. A soft glow in the meteor's rarity colour marks each
landing spot 1.5 seconds before impact. Walk over a landed meteor and it zips into your **Smelter**,
which melts its ore into **Stardust** at a steady rate. Stardust buys three machines. The **Beacon** reaches
further into space: more meteors, richer meteors, rarer kinds, and a new sky over your plot as night falls,
the aurora rises, stars rain, a nebula opens and finally the galactic core hangs overhead. The **Collector**
is a dish around the Smelter that catches whatever lands inside it with no walking. The **Smelter** melts
ore faster. The HUD stars whichever machine is holding you back. Now and then a piece of space junk falls
at you. A red ring shows exactly where it can hit, and stepping out of the ring always dodges it. Press
**Stargaze** to sit back and watch the sky; nothing falls on you while you rest. At about 36 minutes your
Beacon reaches the Starfall band and a guaranteed **Falling Star** comes down beside your arrival pad for
you to catch: the brag moment. After that the goal is the Galactic Core, about 2 hours in, and a place on
the **Star Chart** highscore board, ranked by Beacon level, for everyone or just for your friends.

---

## 2. Where v1 departs from the brief, and why

| the radar brief said | v1 does | why |
|---|---|---|
| Free-fall down a procedural mineshaft and steer between chutes | Meteors fall onto a flat plot; you walk to them | The orchestrator's retheme. It also removes falling physics, which `robloxemu` cannot model, from the core loop. |
| Procedural chute layout | No seeded generation at all; every meteor is a fresh server draw | Nothing to memorise and nothing to precompute. fork-tower REVIEW-4 showed that a generator a client can re-run leaks everything it decides. |
| Idle income that keeps accruing offline, capped | No offline accrual. In a session, the Collector keeps catching for 10 minutes after your last hand pickup | Offline accrual is a trust surface (clock deltas between servers). It would also let the highscore grow with nobody playing (section 9). |
| Prestige / re-mine for a permanent multiplier | Cut | The unbounded Beacon and the board are v1's long tail. Prestige needs its own pacing model (section 17). |
| Fall-speed control, collection-radius upgrade, deeper layers, idle multiplier | Three machines: Beacon, Collector, Smelter | Each one has one job the player can see. A fourth and fifth track would add purchases, not decisions. |
| A single-server leaderboard for total value collected | A cross-server Star Chart (public and friends) ranked on Beacon level | The standard asks for public + friends on a metric a script cannot inflate. Total value would overflow the tie-break encoding (section 9). |
| "LIKE + FAVORITE for a free starter boost" | Nothing is rewarded for likes, favourites or follows | Fair monetization (section 13). |

---

## 3. The world

One server holds **8 plots** around a central observatory landmark, on one continuous ground plate.

| thing | value | reason |
|---|---|---|
| Plots per server | 8, and `Players.MaxPlayers` = 8 | One plot per player, always. `MaxPlayers` is a Studio/Creator setting (section 18). If a ninth player ever arrives (a Studio test with more clients), they are kicked with the message "This server's 8 plots are taken. Rejoin to get a server with room." and the server logs it. |
| Plot shape | a disc of radius 36 studs | A plot is crossed in 72 / 16 = 4.5 s at WalkSpeed [R]. The mean walk between two landing points is 29.90 studs = 1.87 s [M1]: short enough to feel chill, long enough that walking is the decision the Collector competes with. |
| Plot centres | on a ring of radius 110 around the world origin, 45° apart | Neighbouring centres are 2 × 110 × sin 22.5° = 84.2 studs apart, so the rims are 12.2 studs apart [R]: no meteor, dish or glow of one plot can reach the next. |
| Ground | one `Baseplate`, 600 × 600 studs, top at y = 0 | Covers every plot rim (outer edge at 146 from the origin) with room to spare [R]. The ground is continuous, so nothing in the game can fall off anything: a knock (section 6) only costs time. |
| Observatory landmark | a dome on a round base at the origin, radius 16 | A shared landmark for thumbnails and orientation. Decorative, nothing interactive. It is 110 − 36 − 16 = 58 studs from the nearest rim [R]. |

**Plot-local layout** (origin at the plot centre, −Z pointing at the observatory):

| part of the plot | where | reason |
|---|---|---|
| Smelter (furnace, hopper gauge, chimney) | centre, footprint radius 6 | The Collector dish is centred on it, so dish catches drop straight in. |
| Landing area | the ring 8 ≤ r ≤ 32 | Nothing lands on the Smelter or its 2-stud apron, or within 4 studs of the rim [R]. |
| Collector dish | a flat glowing ring centred on the Smelter, radius 0 (not built) or 10..24 (section 4.3) | It covers the inner part of the landing ring, so the outer part is always walking territory. |
| Arrival pad (`Plot_k.Arrival`, a SpawnLocation 6 × 1 × 6) | (0, −30), facing +Z | On the observatory side, so a player arriving sees their Smelter ahead and the other plots around them. Section 11. |
| First meteor of a session | lands at (0, −20) | 10 studs in front of the arrival: the first pickup needs a 5-stud walk = 0.31 s [R], measured at 2.0 s after the character is placed [M8]. A returning player whose Collector reaches radius 22 or more sees the dish take it instead. |
| Falling Star showcase | (0, −26), r = 26 | 4 studs in front of the arrival centre [M1], outside the biggest dish (24), on the observatory side of the plot. |
| Star Chart (the highscore board) | (−14, −31), r = 34.0, facing the arrival | Beside the spawn, as the standard asks, and outside the landing ring so nothing lands in it [R]. |
| Beacon tower | (0, +33), r = 33 | Outside the landing ring, opposite the arrival, so its beam stands behind the Smelter in every arrival view. |
| Owner sign | above the rim at (0, −36) | A BillboardGui with the owner's display name: which plot is whose. |

The server builds all of this at start-up for all 8 plots, before any player joins, so a plot exists before
any character can spawn on it (section 11).

---

## 4. Meteors and the three machines

### 4.1 How a meteor falls

1. **Schedule.** Each owned plot has its own clock. The gap to the next meteor is
   `SpawnInterval(L) × U(0.75, 1.25)` seconds, where L is the owner's Beacon level. `SpawnJitter = 0.25`
   makes the rhythm feel random while keeping the rate exact. All draws come from one server-lifetime
   `Random.new()`, never from a seed derived from anything public (section 12).
2. **Announce.** The server picks a landing point uniformly by area in the ring 8 ≤ r ≤ 32 and a rarity
   from the owner's band (4.2), and decides the meteor's fate at once (3 below). It creates **one** meteor
   Part at the landing point: while incoming it is a flat Neon disc in the rarity colour (the landing glow),
   and on landing the server reshapes it into the rock. **Each client draws the fall**: a local streak from
   180 studs up, entering at 25° from vertical so it crosses a third-person view instead of dropping in from
   behind the top edge of the screen, and reaching the glow in `FallSeconds = 1.5` (so 120 studs/s). The
   server never tweens a falling part. 1.5 s is enough for a normal player to see the glow and start walking
   (react 0.8 s [A]), and short enough that the sky stays busy.
3. **Fate, decided at the announcement:**
   * **Inside the Collector's radius and not a legendary, while the Collector is awake** (4.3): a dish
     catch. It never lies on the ground. On landing it drops into the hopper if the hopper has room, and
     bounces off in a puff if it does not ("Hopper full!" is shown on the Smelter's gauge).
   * **Anything else** lies where it lands, **unless 20 meteors already lie on the plot** (`MaxLying = 20`),
     in which case it burns up high in the sky: a visible fizzle, no glow, no landing.
4. **Pickup.** Ten times a second the server checks each owner's *trusted* position (section 12). A landed
   meteor within `PickupRadius = 5` studs (horizontal) of it is collected: it flies into the Smelter. If the
   hopper is full the pickup is refused, the meteor stays, and a toast says why (at most one every 5 s).
   **A legendary is never refused and never enters the hopper**: it pays its Stardust the moment it is caught.
5. **Only the owner** can collect on a plot. A player standing on someone else's plot near a meteor gets
   "Only <name> can collect here. Your plot has the ⭐ over it." at most once every 15 s.

| number | value | reason |
|---|---|---|
| `SpawnInterval(L)` | `max(1.2, 3.0 × 0.97^L)` s | 3.0 s at the start is about one meteor per mean walk plus a reaction, so a new player always has one to walk to and never a pile [M1, M8]. The floor, reached at L31 [M2], is where an active player with the biggest Collector still has to walk to 0.39 meteors/s (0.467 of 1/1.2), just under the 0.4/s the HUD assumes (4.4) [R]. Server-wide at the floor: 8 / 1.2 = 6.7 meteors/s [R]. |
| `MaxLying` | 20 | Bounds the parts on a plot: 20 lying + at most 2 falling (1.5 s fall ÷ 0.9 s shortest gap) + the Falling Star = 23 [R]. A 20-meteor pile also keeps walks short, because the nearest of many meteors is close: the normal player loses 0.000 of its ore to burning or bouncing over 240 minutes (median, printed to 3 decimals) [M3]. |
| `PickupRadius` | 5 studs | Generous on a phone: you walk *toward* a meteor, not onto its centre. A plot is 72 studs across, so 5 studs never reaches a meteor you did not walk to [R]. |
| Pickup poll | 10 Hz | At 16 studs/s a player moves 1.6 studs between polls, well inside the 5-stud radius, so no meteor is walked past unseen [R]. |
| Pile persistence | lying meteors are **not** saved | They are the sky's, not yours. Leaving loses at most 20 meteors, and it keeps the save small. The hopper **is** saved (section 10). The cap applies to legendaries too: a plot left with 20 meteors lying burns even a Star Core. Only the Falling Star ignores it (section 8). |

### 4.2 Rarities

| rarity | ore multiplier | colour (RGB) | look |
|---|---|---|---|
| Common "Pebble" | 1 | 200, 200, 210 | grey-white stone, small |
| Uncommon "Iron" | 3 | 90, 220, 120 | green-veined |
| Rare "Crystal" | 8 | 80, 160, 255 | blue crystal cluster |
| Epic "Plasma" | 25 | 180, 100, 255 | violet, pulsing |
| Legendary "Star Core" | 100 | 255, 210, 60 | gold, with a vertical light beam |

A meteor's ore is `1.14^L × multiplier` (`OreGrowth = 1.14`). **No meteor colour is red**: red belongs to
the hazard ring alone (section 6). `EnvConfig.spec` enforces it with an `isReddish` test (r ≥ 180,
g ≤ 110 and b ≤ 110; the hazard red is 255, 40, 40) over every rarity colour, glow, dish rim, beacon beam,
weather and critter colour [R].

The mix per band, per mille:

| band | common | uncommon | rare | epic | legendary | average multiplier [M2] | one legendary per |
|---|---|---|---|---|---|---|---|
| 1 Dusk Meadow | 880 | 110 | 10 | 0 | 0 | 1.290 | never |
| 2 Twilight | 800 | 160 | 36 | 4 | 0 | 1.668 | never |
| 3 Aurora | 720 | 200 | 65 | 14 | 1 | 2.290 | 1 000 meteors |
| 4 Starfall | 640 | 230 | 95 | 30 | 5 | 3.340 | 200 |
| 5 Nebula | 560 | 260 | 125 | 45 | 10 | 4.465 | 100 |
| 6 Galactic Core | 480 | 280 | 160 | 60 | 20 | 6.100 | 50 |

Reason: each band raises the average multiplier by 1.29-1.46×, so entering a band is a jump you feel in
income. Legendaries go from never, to rare, to about one per minute at the core (50 × 1.2 s) [M2].
Legendaries are never caught by the dish, so they reward walking: they are 31.9 % of a normal player's
income over 240 minutes [M3].

### 4.3 The three machines

| machine | level | effect | price of the next level | reason |
|---|---|---|---|---|
| **Beacon** | L = 0, 1, 2, … (unbounded) | the spawn interval and the ore per meteor above, and the band (section 5) | `round(12 × 1.26^L)` | The first level (12) is about 28 s of the starting inflow of 0.43 ore/s [M2, R], and the first purchase is a Beacon for every seed [M8]. Tuned with the Smelter's growth to put the Falling Star at 35.6 min (section 8). M11 shows the sensitivity: 1.25 gives 31.8 min, 1.27 gives 37.5 min. |
| **Collector** (the dish) | c = 0..8 | radius 0 at c = 0, then `10 + 2 × (c − 1)` studs; share of landings `(r² − 64) / 960` | `round(60 × 2.2^c)`: 60, 132, 290, 639, 1 406, 3 092, 6 803, 14 966 | The share goes 0.037 → 0.533 [M1]. It stops at radius 24, so the outer 46.7 % of landings is always walking territory: an AFK player with an awake Collector earns 0.293 of an active one at the 35-minute build and 0.423 at the 90-minute build [M5]. |
| **Smelter** | s = 0, 1, 2, … (unbounded) | melts `0.6 × 1.28^s` ore/s into Stardust 1:1; the hopper holds 20 s of melting | `round(20 × 1.38^s)` | At s = 0 it melts 0.6 ore/s against an inflow of 0.43 [M2], so a new player is never blocked. Price growth 1.38 came out of the sweep: 1.36 puts the star at 34.2 min, 1.40 at 37.9, and 1.45 (the first draft) at 43.9 min, with the Galactic Core out of reach in 240 min [M11]. |

**Hopper rules** [R]: the hopper accepts a meteor while its fill is *below* the cap, even if that meteor
overfills it. A cap check that required the meteor to *fit* would refuse every epic until the Smelter was
upgraded, and bounce every epic the dish caught: in band 2, where epics first appear, an epic is 1.91 hoppers
of the smallest Smelter that keeps up [M7]. A full hopper refuses pickups (with a toast) and bounces dish
catches until it melts below the cap. **Legendaries bypass the hopper**: a Falling Star at Beacon 22 is
1.14^22 x 100 = 1 786 ore, which is 2.24 hoppers of the smallest Smelter that keeps up in band 4 (s17, 797.5
ore). It would block that Smelter (39.9 ore/s) for 1 786 / 39.9 = 45 s at the brag moment [R].

**The Collector sleeps** [R]. It catches only while its owner has picked up a meteor **by hand in the last
10 minutes** (`DishIdleSeconds = 600`). A new player starts awake; a returning one starts with the awake time
their last save carried (REVIEW-1: a session used to start awake, so an auto-rejoin every 10 minutes re-armed it). The HUD shows the time left ("Collector
awake 8:12"), and asleep it shows "💤 Collector asleep: grab a meteor to wake it". Ten minutes is shorter
than Roblox's own 20-minute idle kick, so the common anti-AFK trick (which exists to beat that kick) buys at
most 10 minutes of catching. It is long enough that a real break (a Stargaze rest, a drink) never costs the
dish anything. **The timer does not freeze during rest.** Section 9.1 has what it buys against macros.

### 4.4 The HUD's star: the "best next" upgrade

The upgrade panel lights every affordable machine and puts a **★** on one of them: the one that adds the
most steady income per Stardust. It is a pure function, `Economy.bestNext(L, c, s)`, over
`Economy.steadyIncome`:

```
caught fraction = dishShare(c) + min((1 − dishShare(c)) / SpawnInterval(L), HudHandRate) × SpawnInterval(L)
steady income   = min(StarHeadroom × SmeltRate(s), inflow(L) × caught fraction)  -- legendaries ignored
                  (REVIEW-1: StarHeadroom = 0.85, and the star is on the Smelter whenever the hopper has
                   been full StarFullShare = 10% of the recent time, a 30 s moving share; see REVIEW-1.md)
bestNext        = argmax over {Beacon, Collector, Smelter} of (income after − income now) / price;
                  when nothing adds income, the cheaper of Beacon and Smelter (they move together)
```

`HudHandRate = 0.4` meteors/s is the pace the star assumes an active player walks: the mean walk is
29.90 studs = 1.87 s [M1], plus about 0.6 s to notice and turn [A], about 2.5 s per meteor [R]. The star
never goes dark. The normal follower buys its first Beacon at 0.67 min, first Smelter at 2.34 and first
Collector at 11.02 [M10]. A player who ignores the star and buys the cheapest lit thing still catches the
Falling Star at 37.2 min, but loses 1.2 % of ore to a full hopper [M3].

The first draft of the star was simply "the cheapest affordable upgrade", with a full hopper lighting the
Smelter first. The first revision of `design/model.luau` measured 56 % of all ore burning up behind a starved
Smelter, with every profile's income pinned to the Smelter cap, so skill stopped mattering. That draft is
gone, and the current file no longer contains it.

---

## 5. The environment bands

### 5.1 What triggers them

**The trigger is the owner's Beacon level: the game's own logic, never time.** The Beacon *is* how far into
space your plot listens, so the sky over your plot is the region you have tuned into. The level reaches the
client in its own `State` payload (section 10.4) and in `leaderstats.Beacon`, and only the server can raise
it (by a purchase).

* **Named by the integer level.** The band chip, the title card, which hazards fly and the meteor mix all
  use `EnvBands.indexAt(bands, L)`, the same number the Star Chart and leaderstats show, so they always
  agree (+1 Jump review finding 7 [T]).
* **Blended by the same level.** Each band fades in over `fade` levels before its `from`, eased with
  EnvBands' smoothstep, so every purchase near a seam moves the sky a visible step. On top of that, every
  written value glides with a **1.5 s half-life**. +1 Jump used 0.6 s for teleports [T]; a purchase is a
  deliberate step the player should see happen, so it gets a slower glide [R]. Lighting is written at most
  10×/s and only on change [T].
* **Title card** when a purchase takes you into a band you have not seen this session. A player who joins
  already in a band gets a quiet chip instead. The first card waits until the saved state has loaded
  (+1 Jump's slow-load lesson [T]).

### 5.2 The six bands

Minutes are a normal player's median time to *enter* the band [M3]; durations are medians [M4].

| # | band | from Beacon (fade) | normal min | lasts | light and colour | scenery (client) | critters (client) | weather | hazards | server-visible change |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌅 Dusk Meadow | 0 | 0.0 | 4.3 min | golden hour, `ClockTime` 17.8, warm orange-pink | rolling hills ring, birch trees at the world edge, low sun | swallows (1 flock of 5), 3 butterflies | dandelion fluff, 5/s | none | Beacon beam amber |
| 2 | 🌆 Twilight | 5 (2) | 4.3 | 9.3 min | blue hour, `ClockTime` 19.0, first 800 stars | hills, crescent moon, a far lighthouse beam sweeping | 4 bats, 8 fireflies | mist, 4/s | satellite | beam lavender |
| 3 | 🌌 Aurora | 12 (3) | 13.4 | 22.1 min | night, `ClockTime` 22.0, 2 500 stars, cold teal grade | aurora curtains (3 Beams), snowy peaks | 2 snowy owls, 6 wisps | snow glitter, 20/s | satellite, ice chunk | beam teal |
| 4 | 🌠 **Starfall** | **22** (4) | **35.5** | 29.2 min | deep night, `ClockTime` 23.0, 3 500 stars, gold-violet grade, strong bloom | a great comet with a long tail overhead | shooting stars (3 at a time) | gold embers, 12/s | bolide | beam gold; the **Falling Star** (section 8) |
| 5 | 🪐 Nebula | 32 (4) | 64.6 | 64.3 min | `ClockTime` 23.5, 4 500 stars, violet-teal | nebula clouds (6 translucent Neon spheres), a ringed planet | 3 star jellies (glowing bells) | stardust, 6/s | plasma blob, bolide | beam violet |
| 6 | ✨ Galactic Core | 44 (6) | 128.6 | open-ended | `ClockTime` 23.9, 5 000 stars, deepest grade, strongest bloom | the galaxy's core overhead: a bright disc with 4 spiral-arm Beams | 2 comets | gold dust, 8/s | neutron shard, bolide | beam white-gold |

Reasons for the band numbers:
* **`from` values** put the brag band at 35.5 min and the last band at 128.6 min for the normal
  follower [M3]. The shortest band, Dusk, lasts 4.3 min at the median and 4.0 at the minimum across seeds
  [M4], above the 2 minutes +1 Jump holds itself to [T].
* **`fade` values** each cover 40-50 % of the band before (2 of 5, 3 of 7, 4 of 10, 4 of 10, 6 of 12), so the
  next sky creeps in over the last few purchases. Every one satisfies `EnvBands.validate`'s rule `fade ≤ from
  − previous from` (2 ≤ 5, 3 ≤ 7, 4 ≤ 10, 4 ≤ 10, 6 ≤ 12) [R].
* **`ClockTime` only ever rises** (17.8 → 23.9) and never wraps past midnight: `EnvBands.lerp` is linear, so
  blending 23.5 into 0.0 would sweep the sky backwards through the whole day. `EnvConfig.spec` asserts the
  sequence is increasing and below 24 [R].
* **Weather rates** peak at 20/s alone and 32/s for two blended bands, under the 60/s budget [R, T].

Starting lighting values (every band defines the same fields, as +1 Jump's `EnvConfig.spec` requires [T]):

| band | Brightness | Ambient / OutdoorAmbient | Atmosphere Density, Color | ColorCorrection TintColor | Bloom Intensity | beam accent |
|---|---|---|---|---|---|---|
| Dusk | 2.4 | 120,100,90 / 170,140,120 | 0.30, 255,190,150 | 255,236,220 | 1.0 | 255,170,90 |
| Twilight | 1.6 | 90,90,120 / 110,110,160 | 0.25, 140,130,200 | 225,225,255 | 1.1 | 150,140,255 |
| Aurora | 1.2 | 80,100,110 / 100,130,150 | 0.15, 90,140,170 | 215,245,240 | 1.3 | 80,255,190 |
| Starfall | 1.1 | 100,90,110 / 120,110,150 | 0.10, 70,60,110 | 255,240,215 | 1.6 | 255,210,90 |
| Nebula | 1.0 | 100,85,120 / 125,105,160 | 0.05, 80,40,110 | 240,220,255 | 1.7 | 200,120,255 |
| Core | 0.9 | 110,100,120 / 135,120,165 | 0.00, 30,20,40 | 255,230,245 | 1.9 | 255,235,180 |

The OutdoorAmbient floor keeps the plot readable at night. Meteors, the dish rim and the Smelter are Neon, so
they glow whatever the light does. These values are starting points: only real rendering can judge them
(section 18).

**The server's starting light** is `Fx.applyLighting(Fx.Presets.Dusk)`, a new preset equal to band 1, so
the client's first blend takes over with no jump (+1 Jump did the same with `Temple` [T]). Adding one preset
is the only edit to the copied `Fx.luau`, which is how fork-tower added `Fork` [T].

**Everything in 5.2 except the Beacon beam is client-only**: built locally, non-collidable, non-queryable,
non-touchable, and it replicates nothing (+1 Jump's leak review [T]). Your sky follows *your* Beacon, so
another player's plot is seen under your sky. The one server-side change per band is the colour of your
Beacon's beam, which everyone sees. That is a public brag, and the band is public anyway (leaderstats).

---

## 6. Hazards: rare space junk

**Template.** Copy `deep-vein/src/shared/Hazards.luau` and its `tests/Hazards.spec.luau` (140 passed,
0 failed today; the spec requires nothing but the module). That file is +1 Jump's template (111 passed) with
one marked section, "DEEP VEIN ADAPTATION": **vertical kinds** (`drop = "above"`), the `ctx.canDodge` hold
and a fallback knock direction. The diff touches nothing else. Why this game needs it, worked out:
+1 Jump's lanes start inside the camera's pitch window, `ViewPitchDegrees = 20` around the camera's pitch.
A third-person camera on flat ground looks down, say −25°, so the window is −45° to −5°. A lane that starts
at −5° elevation, 102 studs out (34 studs/s × 3 s), starts 8.9 studs *below* the player's root, which is
underground [R]. On a flat plot the only honest lane is from above, and a vertical kind's telegraph is the
ring at the player's feet, on screen wherever the camera looks (deep-vein's own reasoning [T]). Nothing else
changes: the zone, the swept hit test, the one-at-a-time scheduler and the knock are the template's.

**The rule the standard asks for, exactly:** the red ring is the hazard's zone, radius `hitRadius +
PlayerRadius`, centred where the player stood when the lane last aimed. A hit needs the player inside the
ring *and* the falling object passing within reach. **Stepping out of the ring in any direction always
dodges** (+1 Jump review round 2 [T]).

| kind | bands | height studs | fall s | warning s | locks s before | hitRadius (ring radius) | knock studs/s |
|---|---|---|---|---|---|---|---|
| dead satellite | Twilight, Aurora | 60 | 0.8 | 3.2 | 1.6 | 2.4 (3.9) | 36 |
| ice chunk | Aurora | 60 | 0.7 | 3.2 | 1.6 | 2.2 (3.7) | 34 |
| bolide (a fireball too big to catch) | Starfall, Nebula, Core | 80 | 0.9 | 3.6 | 1.8 | 3.0 (4.5) | 42 |
| plasma blob | Nebula | 60 | 1.0 | 3.4 | 1.7 | 2.6 (4.1) | 34 |
| neutron shard | Core | 70 | 0.6 | 3.2 | 1.6 | 2.2 (3.7) | 44 |

| number | value | reason |
|---|---|---|
| `IntervalMin` / `IntervalMax` | 120 / 180 s of **non-rest time on your own plot** | The template's rarity [T]. +1 Jump measured one hazard per 150.9 s over 20 h of scheduler, never two at once [T], which is the standard's "about one near-miss per 2-3 minutes" for a player who reacts. Here: 13 hazards in a normal player's first 36 minutes (12-14 across seeds) [M9]. |
| First hazard band | 2 (Twilight, Beacon 5) | A new player's first 4.3 minutes are hazard-free [M3, M9]. |
| `MinTelegraphSeconds` / `MinCommitSeconds` | 3 / 1.5 | The template's minimums [T]. Every kind above meets them, and `fall ≤ commit` holds for each, so nothing starts to fall before its lane locks (deep-vein's validation [T]). |
| `PlayerRadius` | 1.5 | +1 Jump's value [T]. |
| Ring radius | 3.7-4.5 studs | Leaving it from its centre takes at most 4.5 / 16 = 0.28 s, against at least 1.6 s between lock and impact [R]. The plot is flat and open, so there is always room to step. |
| `AimJitter` | 0.8 | deep-vein's value [T]. The ring stays centred on the player; the object lands up to 0.8 studs off, so inside the ring near the edge is a near miss, never an unfair hit. |
| `KnockLift` / `KnockSeconds` | 8 studs/s (cap 15) / 0.9 s | A hit is a shove and a stumble. The lift can never carry anyone onto anything [T]. |
| Knock speeds | 34-44 studs/s horizontal | Inside +1 Jump's measured 26-58 range [T]. On continuous ground a hit costs about 1.9 s and nothing else [A: `HazardHitCost` in the model]. |
| `MaxRetargetSpeed` | 1.5 | The template's [T]. |
| `SpreadDegrees` / `ViewPitchDegrees` / `KindFitDegrees` | 0 / 20 / 25 | Kept only because `Hazards.validate` requires them; vertical kinds ignore the view cone. deep-vein sets the same [T]. |

**Where and when** [R]. A hazard launches only while the player is grounded, on their **own** plot, not
resting, and not in the Falling Star sequence. That sequence passes `ctx.canDodge = false`, deep-vein's
existing hold, from the moment the star is granted until it is caught, so the brag moment can never be
knocked. A due hazard in a quiet band is re-rolled rather than held (the template's rule [T]).

**Telegraph** (client): a ⚠️ billboard on the object hanging high above, a light pillar from it down to the
ring, the red ring at the player's feet, and a HUD banner "⚠️ BOLIDE INCOMING: step out of the red ring".
At the lock the pillar and ring turn solid red and the banner says "MOVE!".

**Client-only, and why** (+1 Jump's split [T]): the schedule, the telegraph, the hit test and the knock run on
the owner's client. A hazard only harms the local player, whose character physics that client already owns,
and it grants and removes nothing, so the server needs to know nothing. An exploiter who deletes hazards
avoids a 1.9-second stumble and gains nothing else. The price: other players see you stumble with nothing
hitting you (section 18).

---

## 7. Rest: Stargaze

Copy `plus1-jump/src/shared/Rest.luau` and its spec (55 passed, 0 failed today) **verbatim**. Deep Vein's
additions (`SettleSeconds`, `MinAwakeSeconds`) exist because a miner earns by clicking while standing still.
Here every hand pickup needs walking, and walking wakes you, so those rules have nothing to close [R].

* **☕ Stargaze button** (right edge, section 15). You sit down on your plot, the camera tilts slowly up to
  your band's sky piece (the comet, the nebula, the galaxy core), and the chip says "☕ Stargazing: the sky
  leaves you alone. Collector awake 8:12". Press again, or move, to carry on.
* **Idle rest**: standing still for 20 s also rests you (hazards off, no camera change). This keeps AFK
  players safe [T].

| number | value | reason |
|---|---|---|
| `IdleSeconds` | 20 | +1 Jump's [T]. |
| `WakeGraceSeconds` | 0.4 | +1 Jump's [T]. |
| `PendingSeconds` | 7 | A rest requested while a hazard is inbound is queued; it must outlive the longest hazard flight (bolide: 3.6 warning + 1.0 pass = 4.6 s) by more than 2 s, as +1 Jump sized its own [R, T]. |
| `RequireGrounded`, `BlockWhileThreat`, `WakeOnMove` | true | `WakeOnMove` and `BlockWhileThreat` are mandatory in `Rest.validate` [T]. |

**Why rest can never be an exploit:**
1. **Rest pauses only hazards.** The hazard clock *freezes* during rest and is never reset, so toggling rest
   cannot thin hazards (measured 142 / 142 / 142 in +1 Jump [T]).
2. **Rest earns nothing that standing still does not.** You cannot pick anything up while resting, because
   pickups need walking and walking wakes you. The Collector keeps working, but its 10-minute timer does **not**
   freeze during rest (4.3), so rest never extends idle income. Meteors keep falling and pile up as for any
   player standing still (at most 20, 4.1).
3. **It is not a panic button**: it cannot start with a hazard inbound (the template's queue [T]).
4. **Nothing races a clock.** The game has no round, no timer and no penalty for pausing.

Roblox's own 20-minute idle kick still applies. Nothing is lost when it fires: the profile is saved every
60 s and on leaving (section 10), and only the unsaved pile (at most 20 meteors) goes with the session.

---

## 8. The brag moment and the long-term goal

**The Falling Star.** The purchase that takes the Beacon to level 22 (Starfall) grants a one-time guaranteed
legendary. A card says "🌠 STARFALL! A Falling Star is coming to your plot". A gold beam stands at the showcase
spot, and the star descends slowly over `StarFallSeconds = 4` [R: slower than a meteor's 1.5 s so it can be
watched and filmed]. It lands 4 studs in front of the arrival pad's centre. **It ignores the 20-meteor cap**
and is never caught by the dish. Walk to it: "🌠 YOU CAUGHT A FALLING STAR!" with a white flash, an FOV punch
and a camera shake (FxClient [T]). It pays its legendary Stardust at once. The whole server gets a toast,
"<name> caught a Falling Star!", and your Beacon wears a gold crown ring from then on, which everyone can see.

* **Measured: 35.6 min** median for the normal follower (p10 34.2, p90 36.5). Fast 35.0, slow 36.9,
  cheapest-first 37.2, bot 34.5 [M3]. The standard's window is 30-45 min. Fast, normal and slow are only
  1.9 min apart, because Smelter throughput, not walking skill, sets the pace (9.1).
* **Not luck.** The star is guaranteed at a Beacon level, not rolled.
* **One-time grant, atomic** (checklist): profile field `star` = 0 (not granted), 1 (granted, not caught),
  2 (caught). In a saving session the grant is one owner-checked `UpdateAsync` that writes `star = 1` with
  the rest of the profile, and the star spawns **only after that write succeeds**. If the write fails, the
  toast says "Your Falling Star is waiting: it falls as soon as your progress saves", and the grant retries
  every flush tick. In a non-saving session (store unavailable, or locked by another server) it spawns at
  once, because a grant that is never written cannot be redeemed twice (steal-a-cryptid's rule [T]). The
  catch writes `star = 2` and the Stardust in the same pending save. A player who leaves with `star = 1`
  gets the star again on the next join. That is not a duplicate: its payout was never saved.

**The long-term goal: the Galactic Core** (band 6, Beacon 44) at a measured 128.6 min for the normal
follower (p10 124.0, p90 133.0) [M3]. That is 3.6× the brag time and under 3 hours. After it the Beacon
keeps going (unbounded levels, 1.26× per level), and that climb is the Star Chart (section 9).

---

## 9. The Star Chart: public and friends highscores

### 9.1 The metric: Beacon level

Ranked on the owner's **Beacon level**. Ties go to whoever reached that level first. The board shows the
band emoji next to each level, so "🌠 22" reads as a player who has reached Starfall.

**Why a script cannot inflate it.** Follow one Beacon level back to its source:
1. A Beacon level is raised only by the server, by a `Buy("beacon")` it has validated against the price.
2. Stardust is minted only by the server: by the Smelter, at `0.6 × 1.28^s` ore/s on the server's clock, or
   by a legendary the server spawned.
3. Ore enters the hopper only from meteors the server spawned on that player's own plot, through the
   Collector (server geometry) or through a hand pickup tested against the **trusted position**. That is
   the server's own copy of the character, which moves toward the claimed root at no more than
   16 × 1.35 = 21.6 studs/s (vault-runners' `Trace` [T]).

So no client input makes meteors fall faster, makes the Smelter melt faster, or collects faster than walking
pace. **Measured**: a bot with no reaction time, perfect lines and the full trusted speed collects 0.996×
and 1.001× what the normal human does at the same build [M5]. It reaches the Falling Star 1.1 min sooner,
by buying the instant it can [M3]. The model runs the bot at a steady 21.6 studs/s; `Trace`'s 3 s burst bank
lets a teleporter spend a saved burst, but never raises its average above that cap [T].

**What a macro can and cannot do** [M6], from the normal player's 35-minute state (Beacon 21):

| over the next… | anti-AFK jiggle + auto-buy macro | a pathing bot that grabs one meteor every 9 min | the active normal player |
|---|---|---|---|
| 1 h | Beacon 22 | 26 | 38 |
| 8 h | **22** | 52 | 66 |

The common anti-AFK jiggle is worth one level, then the Collector sleeps. A purpose-built pathing bot that
keeps the Collector awake climbs, but slower than an honest player. **Residual risk, stated:** a bot that
plays for you around the clock climbs the board at a human's pace. No cumulative metric can stop that;
this one ensures it is never faster than a human.

Why not lifetime Stardust: tycoon totals grow geometrically (the core band's inflow is 1 621.67 ore/s [M2])
and would overflow the tie-break encoding, which needs `metric < 4.5 × 10⁶` to stay exact under 2^53 [R].

### 9.2 Storage

| thing | value | reason |
|---|---|---|
| Store | OrderedDataStore `MeteorDropTycoon_Board_v1`, key `u_<userId>` | The standard [T: complete-game-standard.md §3]. |
| Value | `beacon × 2e9 + (2e9 − beaconAt)` | The standard's encoding. `beaconAt` is the profile's `os.time()` when that level was first reached, **not** the write time, so ties go to whoever *reached* it first. Beacon 100 encodes to about 2.0 × 10¹¹, far under 2^53 ≈ 9.0 × 10¹⁵ [R]. `beaconAt` stays under 2e9 until May 2033 [R]. |
| Write | only when the Beacon beats the last value this server wrote or read for that player; coalesced to at most one write per player per 60 s, plus one on leaving | "Write only when the metric improves" [T]. A normal player reaches Beacon 5 at 4.3 min [M3], about one level a minute early on, so writing every purchase would waste budget. 8 players × 1/min = 8 writes/min per server [R]. |
| Seed of "last value" | one `GetAsync` of the player's own key at join (pcall'd) | So a rejoin never writes a lower or equal value. |

### 9.3 The two views

* **Public**: `GetSortedAsync(false, 10)`, cached server-side for 60 s and shared by every player on the
  server, so a server makes at most one sorted read a minute [T].
* **Friends**, fetched only when the player switches to it: `Players:GetFriendsAsync(userId)`, pcall'd,
  capped at the first **200** friend ids [T: the standard's example]. Each friend's score is one
  `GetAsync` on the board store, made at most **1 per second per server** and only while
  `DataStoreService:GetRequestBudgetForRequestType(GetAsync)` stays above a reserve of 10 [R]. Results are
  cached for 300 s server-wide, so two friends on one server share reads. Friends on the same server are
  read from memory, with no request. The view fills in as scores arrive ("Loading friends… 34 / 120"), and
  200 friends take at most 200 s [R]. The viewer's own row is always present.
* **Empty friends view**: "None of your friends is on the Star Chart yet. Your best: 🌠 Beacon 22. Invite
  someone: the sky is big enough." If `GetFriendsAsync` fails or is missing: "Friends list unavailable right
  now. Showing your own row." This covers `robloxemu`, which has no `GetFriendsAsync`.
* **Names** come from `Players:GetNameFromUserIdAsync`, pcall'd and cached for the server's lifetime.
  **A name is never stored**, only user ids.

### 9.4 The physical board

Each plot has a **Star Chart** beside its arrival pad (section 3): a framed board Part with a
`ProximityPrompt` ("Star Chart: switch Public / Friends", `MaxActivationDistance = 10` [R: the board is
14 studs from the arrival, so a few steps reach it]). The rows render in a **SurfaceGui that lives in the
owner's PlayerGui with `Adornee` set to their own board**. Each player's friends list and rows therefore
reach only that player, sent by the server over the `Board` remote. A visitor sees only the board's title
plate. Pressing someone else's prompt gives "This is <name>'s Star Chart. Yours is by your own arrival pad."

---

## 10. Data model

### 10.1 What persists: DataStore `MeteorDropTycoon_v1`, key `u_<userId>`

```
{
  session   = string | nil,   -- owner token: one HttpService:GenerateGUID per server session (fork-tower `old.session`)
  jobId     = string,         -- diagnostics only
  lockUntil = integer,        -- os.time(); renewed by every write
  data = {
    v          = 1,
    stardust   = number >= 0,   -- spendable
    lifetime   = number >= 0,   -- all Stardust ever minted (the Star Chart footer: "Lifetime 1.2M")
    beacon     = integer >= 0,
    beaconAt   = integer,       -- os.time() when `beacon` was first reached (the board's tie-break)
    collector  = integer 0..8,
    smelter    = integer >= 0,
    hopper     = number >= 0,   -- ore waiting in the hopper; melts again next session, never offline
    star       = 0 | 1 | 2,     -- the Falling Star: not granted / granted, not caught / caught
    starCores  = integer >= 0,  -- legendaries caught by hand, the Falling Star included
    tutorial   = integer 0..3,  -- section 14's hint step, so a rejoin resumes and never repeats
  },
}
```

* **No integer keys anywhere** (checklist: JSON turns sparse integer keys into strings).
* `Save.normalise` (pure, spec'd) makes a loaded record safe: a non-number gives the default, a negative
  gives 0, `collector` is clamped to 0..8, integers are floored, and NaN or infinity gives the default.
* **Clocks**: `os.time()` for everything persisted. `tick()` for in-session timers (spawn clock, Collector
  timer, rate limits), because `tick()` is the clock `robloxemu` advances; deep-vein measured that
  `os.clock()` barely moves headless [T].
* **Session lock with an owner token** (fork-tower REVIEW-4 §10 [T]). The load is one `UpdateAsync` that
  takes the lock (writes `session = token`) unless another live session holds it. `canSave` is true only if
  this session wrote its token. **Every** later write is an `UpdateAsync` that first checks
  `old.session == token` and cancels (returns nil, marks the session lost, stops saving) when it does not
  match. A late releasing write can therefore never re-release a record a newer session has taken.
* **Non-saving session** (store unavailable, locked elsewhere, or token lost): everything works in memory.
  A HUD banner says "Progress is not being saved this session". REVIEW-1 (steal-a-cryptid's REVIEW-1 fix [T]):
  a load is tried 3 times (1 s, 2 s apart) before it gives up; a lock is re-read every 5 s for up to 15 s at the
  join; and a session that still starts read-only re-checks every 15 s and takes over once the lock is gone and
  the record's data is exactly what it read (otherwise it stays unsaved and says rejoin). A session that lost
  its token to a newer one never switches back.
* `GetDataStore` is itself pcall'd: unwrapped, it raises in an unpublished place and kills the server
  script [T].

| number | value | reason |
|---|---|---|
| `Save.FlushTickSeconds` | 7 | Coalesced writes, at most one per player per tick [T: steal-a-cryptid, vault-runners]. 8 players × 60/7 = 68.6 `UpdateAsync`/min against a budget of 60 + 10 × 8 = 140 [R]. |
| `Save.AutosaveSeconds` | 60 | Renews the lock. Every real change (a purchase, a catch, a hopper change) marks the profile pending, so it reaches the store within one 7 s tick [T]. |
| `Save.LockSeconds` | 120 | Twice the autosave, so a live session always renews in time [T]. |

### 10.2 What is server-only (Lua tables in `Main.server.luau`)

The server's `Random.new()`; each plot's next-spawn time; every meteor's fate and ore; each player's
`Trace` (trusted position, burst bank); the Collector's last-hand-pickup time; hopper fill; pending-save
flags and session tokens; remote rate-limit buckets; board caches (public rows, friend scores, names); and
the pending Falling Star grant.

### 10.3 What lives in `ServerStorage` (anomaly-observatory's "ServerStorage, not the zone")

* `ServerStorage.MeteorKit`: the meteor model per rarity, the Falling Star, a Beacon segment and the crown
  ring. The server clones these. Nothing in them is secret, but clients have no reason to hold them.
* `ServerStorage.PlotInfo.<userId>`: attributes `Plot`, `NextSpawnAt`, `TrustedX`, `TrustedZ`,
  `CollectorAwakeUntil`, `Hopper`. They exist **only** for the headless checks and tools, as anomaly's
  `PassInfo` does [T]. `NextSpawnAt` is future information, which is exactly why it is here and nowhere a
  client can read.

### 10.4 What replicates, and why it is safe

| replicates | why that is fine |
|---|---|
| Every plot Part: disc, rim, Smelter and its hopper gauge (a fill bar), Collector dish (its radius), Beacon tower (height, beam colour, crown), arrival pad, board frame, owner sign | Nothing about a plot is secret. The dish radius and Beacon beam are meant to be seen. |
| A meteor Part, from its **announcement** (hidden, with its landing glow) to its pickup | The landing point is shown 1.5 s early **by design**. Its rarity is visible by colour, and its ore follows from public Config. Its fate (dish, lie, burn) shows the moment it lands. **The next** meteor, its time, point and rarity, exist nowhere until the server draws them. |
| `leaderstats.Beacon`, `leaderstats.Stardust` | Public by design: the board shows the same numbers. |
| `State` (server → owner only, `FireClient`): stardust, lifetime, beacon, collector, smelter, hopper and cap, melt rate, inflow, Collector awake-seconds, `star`, `tutorial`, `saving` | All of it is the owner's own *present* state. None of it is future information. |
| `Board` rows (server → the viewer only) | That player's own view of public data and their own friends. |
| Shared modules in `ReplicatedStorage` (Config, Economy, Meteors, Board, EnvBands, Hazards, Rest, …) | Public code. Nothing is seeded from public values, so the code predicts nothing (fork-tower REVIEW-4 [T]). |

**The attribute rule: no attribute on any Instance under `workspace` or `ReplicatedStorage`.** Instance
names carry only visible facts (`Meteor_Rare`, `Plot_3`). The headless check enumerates every attribute
under both and requires the list to be **empty**. That is fork-tower's wire inventory in its strictest
form [T].

### 10.5 Remotes (`ReplicatedStorage.MeteorRemotes`)

| remote | direction | validation |
|---|---|---|
| `State`, `Toast`, `Fx`, `Board` | server → one player | none |
| `Announce` | server → all | the server-wide "caught a Falling Star" toast. Text only, and already public. |
| `Buy(kind)` | client → server | `kind` must be the string `"beacon"`, `"collector"` or `"smelter"`. Refused, **each with a toast**: unknown kind; not affordable ("Need 1.9K Stardust, you have 1.2K"); Collector at max ("Your Collector is at its biggest"); profile not loaded yet ("Loading your plot…"). |

Nothing else goes client → server. Pickups are server polls (4.1). The Star Chart toggle is a server-side
`ProximityPrompt.Triggered`. Rest and hazards are client-only.

| number | value | reason |
|---|---|---|
| `Remotes.MaxPerSecond` | 8 per remote per player | Above deliberate tapping on a phone. Excess calls are dropped with at most one "Slow down" toast per 5 s [T: steal-a-cryptid]. |

---

## 11. Spawn and respawn (`robloxemu/SPAWN-ORDER.md`)

The engine's order, measured in Studio: `CharacterAdded` fires while the character is unparented at the
origin; one frame later the engine parents it **and places it on a SpawnLocation**, discarding any CFrame
written in between [T].

The design uses SPAWN-ORDER's **preferred pattern: let the engine place you** (grow-a-crystal and
nightwatch-manor do this [T]):

1. **Each plot's arrival pad is a real, enabled `SpawnLocation`** (`Plot_k.Arrival`, 6 × 1 × 6, top at
   y = 1, `Duration = 0` so no force-field bubble, `Neutral = true`). All 8 exist from server start
   (section 3). The observatory has no SpawnLocation.
2. **`PlayerAdded` claims a free plot and sets `plr.RespawnLocation = Plot_k.Arrival` synchronously, before
   any yield** (before the DataStore load). The engine's placement is then already correct, with no race to
   lose. The plot's contents (machines at the saved levels) appear once the profile loads. Until then the
   plot shows level-0 machines and Buy answers "Loading your plot…".
3. **Belt and braces in `CharacterAdded`**: wait for `char.Parent ~= nil`, bounded at 300 frames of
   `task.wait(1/60)` [T]; then **re-read** the player's plot (it can change across the yield); if the root
   is more than 8 studs (horizontal) from the plot's arrival, CFrame it there, 3 studs above the pad top
   (vault-runners' root height [T]). This covers an engine that ever picks a different enabled spawn.
   `WaitForChild` is not the wait: on the server both children already exist when the event fires [T].
4. **The trusted position resets** to the arrival pad after placement. It is a point the server chose,
   never one the client supplied (vault-runners' rule [T]).
5. **Leaving** frees the plot for the next joiner, destroys its meteors, and resets its machines to
   level-0 visuals.

Headless (section 16): every plot has exactly one enabled SpawnLocation and there are no others; after
`simulateSpawn`, each of two players stands on their **own** arrival pad (XZ within 4 studs, not on each
other); the same after a respawn; and with `RespawnLocation` deliberately cleared, step 3 still puts the
player on their own pad. The assertion is on XZ, not Y, as SPAWN-ORDER §7 advises [T].

---

## 12. Anti-exploit model

vault-runners' rule [T]: do not try to detect cheating; remove what cheating is worth, and bound what cannot
be removed.

| a client can… | what it would buy | denied or bounded by |
|---|---|---|
| Teleport or speed-hack its character | Sweep the plot instantly | Pickups read the **trusted position**, capped at 21.6 studs/s with a 3 s burst bank [T]. Measured: a bot at that cap collects 0.996-1.001× a normal player at the same build [M5]. |
| Collect on someone else's plot | Steal their meteors | Only the owner's trusted position is tested against a plot's meteors. |
| Fire `Buy` with a bad kind, while broke, or in a flood | Free levels, server work | String whitelist, price check, 8/s rate limit, a toast for every refusal, and writes coalesced to one per 7 s. |
| Read replicated state or remote traffic | Know the next meteor | Nothing to read: the schedule and RNG never leave the server, a meteor exists only from its announcement, `State` carries only the present, and there are no attributes (the check enforces an empty list). |
| Predict the RNG | Stand where the legendary will land | Every draw is from a server-lifetime `Random.new()`. Nothing is seeded from a public value (fork-tower REVIEW-4 [T]). |
| Delete hazards, or fake rest | Avoid knocks | Hazards and rest are client-only and grant nothing; the only thing avoided is a 1.9 s stumble. The Collector's timer ignores rest. |
| Run an anti-AFK jiggle | Idle income forever | The Collector sleeps 10 min after the last hand pickup: +1 Beacon level in 8 h [M6]. |
| Run a pathing bot | Play while away | It plays at walking pace, at most the trusted speed: 0.996-1.001× a human [M5], Beacon 52 vs 66 in 8 h [M6]. The residual, stated in 9.1. |
| Server-hop or crash to duplicate | Two sessions writing one profile, or a Falling Star twice | The session lock with an owner token on every write; the Falling Star grant gated on its atomic write (section 8). |
| Manipulate time | Mint Stardust while away | There is no offline accrual. Only server `tick()` and `os.time()` are read. |
| Write the board | A fake rank | Only the server writes, from the saved profile's Beacon and `beaconAt`. |
| Abuse a hazard's knock | Fling onto something | The knock is client-only, on the player's own character; lift is capped at 15 and there is nothing to land on [T]. |

---

## 13. Fair monetization

**v1 sells nothing.** No Game Passes, no Developer Products, no premium currency, no promo codes. Rules for
any later version, written down now so they are not negotiated feature by feature:
1. **No paid randomness, ever**: no crates, eggs, wheels or paid rerolls.
2. **No Stardust or production for Robux**: no 2× income pass, no Smelter or Collector boosts, no paid
   Collector wake. Each of these would scale the anti-farm bounds in section 12 and the Star Chart.
3. **Cosmetics only**: Beacon beam colours, plot decorations, meteor trail skins, a Stargaze chair.
4. **Nothing rewarded for likes, favourites or follows**, and no store text that implies it.

---

## 14. The first 60 seconds

Measured with the normal profile [M8] and the section-3 geometry. The headless first-minute walk (section 16)
has to reproduce the checkable rows through the real server.

| t (s) | what happens | source |
|---|---|---|
| 0 | The character lands on its own arrival pad, facing the Smelter. Hint: "A meteor is coming: walk over it when it lands" (with a pointer to the glow). The Dusk sky, and swallows overhead. | sections 3, 11 |
| 0.5 | The session's first meteor is announced: a glow appears 10 studs ahead. | `FirstMeteorAt` [R] |
| 2.0 | It lands; the player is already there; it zips into the Smelter. **The core action at 2.0 s.** | [M8], median = p10 = p90 |
| 2-30 | A meteor about every 3 s; walks of about 1.9 s. The hopper gauge fills and the Smelter glows and sparks. Hint 1 after the first pickup: "Meteors melt into Stardust. Keep collecting!" | [M1, M2] |
| about 30 | 12 Stardust (28 s of 0.43 ore/s). The Upgrades button pulses with ★; hint: "Tap ⬆ Upgrades and buy the Beacon ★". | `BeaconPrice0`, [M2, R] |
| 40 | First purchase, the Beacon, for every seed. The tower grows a ring, the beam brightens, and meteors come a little faster. | [M8] (the model opens the shop every 20 s; a player following the hint buys at about 30 s) |
| 60 | 24.3 Stardust melted, one purchase made. | [M8] |

The first Smelter purchase comes at 2.34 min and the first Collector at 11.02 min [M10]. Hint 2 appears the
first time the ★ lands on the Collector: "The Collector catches meteors for you. It sleeps if you stop
collecting." The hints are the persisted `tutorial` step (0 → 3), so a rejoin resumes rather than repeats.
No step needs a purchase the player cannot afford, and every refusal on the way says why.

---

## 15. Look and HUD from the first build

**Fx from day 1** (checklist §2). Server: `Fx.applyLighting(Fx.Presets.Dusk)` as the first line.
Signature particles: `Fx.sparkle` on the Smelter's chimney, `Fx.attachGlow` on the dish rim (interactive
things read as interactive), and a gold glow and beam on every legendary. Client: trails on the falling
streaks over the player's own plot only (at most 2 at a time [R], which keeps the trail budget);
`FxClient.shake` + `flash` + `fovPunch` on the Falling Star catch, and a small shake on a hazard hit.

**Phone first** (checklist §2b; `Responsive.luau` copied verbatim, spec 70 passed today):
* The root Frame owns the `UIScale`, sized `1/scale`.
* **Top centre**: the wallet (Stardust, compact "1.2K / 3.4M", plus "+2.0K/min"); under it the band chip
  ("🌌 Aurora · 🌠 Starfall in 9 levels"); under it the hopper bar with "Hopper full!" when full. Toasts and
  the one-line tutorial hint sit below. The Falling Star and band title cards are centred and transient.
* **Right edge, between 45 % and 70 % of the height**: two buttons, "⬆ Upgrades" and "☕ Stargaze".
  **Nothing tappable in the bottom-left or bottom-right** (the thumbstick and jump button). Tap targets are
  at least 44 screen px: `ceil(46 / scale)` design px on touch [T: vault-runners].
* **The upgrade panel** slides in from the right edge (`Responsive.sideWidth` / `fitHeight`, a
  `ScrollingFrame`): three rows (Beacon, Collector, Smelter), each with its level, now → next effect, price,
  BUY, and the ★ on one of them. When it opens, the button column moves with its left edge, so no two panels
  ever overlap.
* The headless HUD check runs `hudcheck` at six viewports with **`overlap = true`** (rule 4b asserted), and
  re-lays out on `ViewportSize` changes.
* **Colour carries meaning**: red means a hazard ring and nothing else (4.2's `isReddish` test); gold means
  legendary and the Falling Star.

**Budgets, capped in code** (`Config.Budget`, +1 Jump's values [T]): `MaxLocalParts` 200, `MaxEmitters` 4,
`MaxEmitterRate` 60/s, `MaxWeatherEmitters` 2 (via `EnvBands.capRates`), `MaxBeams` 8, `MaxTrails` 8,
`MaxLights` 3, `MaxHazards` 1. **Server parts** [R]: per plot, disc 1 + rim 1 + arrival 1 + board 2 + sign
post 1 + Smelter 8 + dish 2 + Beacon base 2 + up to 10 segments (one per 5 levels) + crown 1 = 29 static, plus
at most 23 meteors (4.1; a meteor is one Part from announcement to pickup) = 52. That makes 416 for 8 plots,
plus the observatory (≤ 30) and the baseplate: **≤ 447**, asserted ≤ 450 headless. Server lights: one on each
Smelter and one on each Beacon = 16. Meteors use Neon, not lights.

---

## 16. Build plan: tests first

**Files** (checklist §1 scaffold; `deep-vein` layout):

```
meteor-drop-tycoon/
  default.project.json      src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  src/shared/Config.luau     every tunable in this spec, one block each (World, Plot, Meteors, Beacon, Collector,
                             Smelter, Rarities, Env, Hazards, Rest, Trace, Save, Board, Remotes, Budget, Tutorial, Pacing)
  src/shared/Economy.luau    prices, rates, dish radius/share, steadyIncome, bestNext, canBuy/apply (pure)
  src/shared/Meteors.luau    gap, landing point, rarity roll, fate at announcement, landing, pickup, Collector awake (pure; rand injected)
  src/shared/Board.luau      encode/decode, shouldWrite, friend-row merge and sort, empty-view text (pure)
  src/shared/Save.luau       defaults, normalise, star transitions (pure)
  src/shared/EnvBands.luau   plus1-jump, verbatim
  src/shared/Hazards.luau    deep-vein's copy (plus1-jump + the marked vertical-kind section), verbatim
  src/shared/Rest.luau       plus1-jump, verbatim
  src/shared/Trace.luau      vault-runners' + ONE marked section: speeds() reads Config.Trace (walk x 1.35) and
                             y follows the claim both ways. vault-runners derives a climb rate from staircase
                             geometry this flat plot does not have. Its spec (28 passed there) requires
                             vault-runners' Config, so tests/Trace.spec.luau keeps its horizontal cases and
                             rewrites only the config fixture.
  src/shared/Fx.luau         + Presets.Dusk (the only change); FxClient.luau, Responsive.luau verbatim
  src/shared/SkyArt.luau     client art for the bands, critters, weather, hazard models, streaks (game-specific)
  src/server/Main.server.luau
  src/client/Hud.client.luau (HUD, upgrade panel, Star Chart SurfaceGui)  src/client/Sky.client.luau (bands, hazards, rest, streaks)
  tests/*.spec.luau          tests/PlotModel.luau (design/model.luau's simulate, reading Config)
  README.md (store text, section 20) CLAUDE.md EYECANDY.md MARKETING.md .gitignore (publish_*.bat, publish_*.sh, *.rbxl*)
```

No `Rng.luau`. Nothing in the game is seeded: every draw is the server's `Random.new()`, and the pure modules
take `rand: () -> number` as an argument. Specs supply their own deterministic LCG [R].

**Unit specs, each written and watched failing before its module:** `Economy.spec` (every price and rate
above, `bestNext` for every case in 4.4, the hopper's accept-while-below-cap rule, the legendary bypass);
`Meteors.spec` (landing points only inside 8 ≤ r ≤ 32; fate at announcement; the 20-meteor cap refuses only
meteors that would lie; the Collector asleep after 600 s and awake at session start; the first meteor at (0,
−20)); `Board.spec` (encode/decode round trip, tie-break order, write only on improvement, 200-friend cap,
empty and failure texts); `Save.spec` (normalise, clamps, star 0 → 1 → 2 only); `EnvConfig.spec` (the bands
validate, every band defines every lighting field, `ClockTime` rising and under 24, band 1 has no hazards,
every hazard kind is used, `fall ≤ commit`, ring leavable in 0.3 s, `PendingSeconds` ≥ longest flight + 2,
`isReddish` over every non-hazard colour, `Fx.Presets.Dusk` equal to band 1); the copied `EnvBands`,
`Hazards`, `Rest` and `Responsive` specs (self-contained, verbatim) and the adapted `Trace` spec;
`Pacing.spec`, which runs `PlotModel` from Config and asserts: normal and slow followers catch the Falling
Star in 30-45 min; the core arrives at least 2× later and under 3 h; every band lasts at least 2 min;
bot/normal at most 1.05 at a frozen build; the anti-AFK jiggle gains at most 1 level in 8 h.

**Headless gates** (`robloxemu`; rebuild with `py -3 wrap.py --game ../meteor-drop-tycoon --out
build/meteor-drop-tycoon.luau` before every run):
* `check_meteordroptycoon.luau`, **the real player path**: 8 plots exist and are parented; each has exactly
  one enabled SpawnLocation; spawn on your own pad (section 11); the first meteor announced and landed at
  (0, −20) within 2.5 s; walk the character onto it and see the hopper, then Stardust, rise; `Buy("beacon")`
  moves the level, the tower and leaderstats; walk until the Collector is starred, buy it, see a dish catch;
  fill the hopper and see a refused pickup **with a toast**; the empty attribute inventory; server parts
  ≤ 450; rejoin restores every saved field.
* `_save`: two sessions on one profile (the second is non-saving); a late releasing write cancelled by the
  owner token; the Falling Star grant with the DataStore failing (no star, a toast, then a star after
  recovery); a star granted but not caught returns on rejoin.
* `_sky`: every band and every seam, budgets asserted each frame; weather capped; a purchase glides (no
  Lighting write above its share of the change); the client fires no remote and writes nothing the server
  built.
* `_hazards`: only on your own plot, grounded, not resting, not during the Falling Star; the drawn ring
  equals the zone; walking out of it in 8 directions always dodges; resting freezes the clock.
* `_hud`: hudcheck at six viewports with `overlap = true`, touch and desktop.
* `_board`: board writes only on improvement, the encoding, public rows, the friends view falling back
  cleanly where `GetFriendsAsync` is missing.

Every new assertion is mutation-tested with a control (the standard §4).

---

## 17. Cut from v1

| cut | why |
|---|---|
| Offline earnings | A clock-delta trust surface, and it would grow the board with nobody playing (section 2). |
| Rebirth / prestige | Needs its own pacing model; the unbounded Beacon and the board carry the long tail. |
| Steering drop runs (the brief's free-fall) | Replaced by the retheme; falling physics is not headless-testable. |
| A carried pack and a magnet (pickup radius) upgrade | A second walking loop adds walking, not decisions. Pickups go straight to the Smelter. |
| Smelter "grades" (value multipliers) | One number per machine keeps the star's arithmetic legible. |
| Promo codes, badges, daily rewards, streaks | Each is a one-time-grant or dashboard surface outside the core loop. Badges also need the Creator Dashboard. |
| Trading, gifting, visiting, co-op, any PvP | The radar's point: pure chill. |
| Server-wide meteor showers and events | They would need their own fairness rules against the per-plot clock. |
| Sound and music | Audio needs asset ids (section 18 lists it as optional night-shift work). |
| Custom meshes, textures, skyboxes | v1 is code-only Parts, as the checklist expects. |
| Any Robux item | Section 13. |

---

## 18. Needs Studio (and needs a live server)

Only real rendering, real input or a published server can settle these. This list moves into `EYECANDY.md`
when the game is built.

1. **Every band's look**: exposure, ambient and bloom per band; whether the plot and meteors read at night;
   Neon meteors under bloom; the gold Starfall grade; the teal aurora against snow glitter.
2. **Stars at `ClockTime` 19.0** (Twilight): do 800 stars show at blue hour, or only after about 20?
3. **Atmosphere vs fog**: Roblox ignores fog while an Atmosphere exists; density 0 at the Core.
4. **Distant pieces on a phone**: comet, nebula spheres, ringed planet and galaxy disc at 1 500-4 000 studs
   may be culled at low graphics quality. If so: closer and smaller.
5. **Beams**: the aurora curtains, the galaxy arms and the lighthouse sweep almost certainly need hand tuning.
6. **The falling streak**: does a client-drawn 1.5 s fall line up with the server's reveal of the landed
   meteor, with real replication delay (100-200 ms)? Does a meteor ever pop in before its streak arrives?
7. **The landing glow**: readable 1.5 s early on a phone at 30 studs; the five rarity colours
   distinguishable (colour-blind check on the green/blue/violet trio).
8. **Walk-over pickup at `PickupRadius` 5** with a thumbstick: does it feel generous or sloppy?
9. **The knock**: does `PlatformStand` plus `AssemblyLinearVelocity` push a humanoid on flat ground, and
   release cleanly? Deep-vein and +1 Jump have the same open item.
10. **The hazard telegraph from above**: is the ring enough when the object hangs out of view? Is the light
    pillar readable in daylight (band 1 has none; Twilight is the first)?
11. **Stargaze's sit and camera tilt**: `Humanoid.Sit` with no seat, from the client, as in +1 Jump's item 11;
    does the camera tilt feel good, and release on the first move?
12. **Top-centre HUD on a notched phone**: safe area, emoji in `TextScaled` labels, and the band chip's length.
13. **The Star Chart SurfaceGui** in PlayerGui with `Adornee`: text legible from the arrival pad (14 studs);
    only the owner sees their rows.
14. **Frame time** on a mid/low phone with 8 busy plots (up to 184 meteor parts server-side) at the floor
    spawn rate, 6.7 meteors/s.
15. **`Players.MaxPlayers = 8`** set in Game Settings. Also check that `SpawnLocation.Duration = 0` really
    removes the force field.
16. **Other players see a knock with nothing hitting** (client-only hazards). Does it look like a glitch in
    a full server?
17. **Live server only**: the friends board against real `GetFriendsAsync` pages and real DataStore
    throttling; `GetSortedAsync` caching across real servers; the Falling Star grant with a real
    `UpdateAsync` failure.
18. **Optional, if assets are chosen**: an impact thud, a Smelter hum, a Falling Star chime. Library audio
    ids only.
19. **The Falling Star fanfare** (flash, FOV punch, shake, server toast): celebratory, not annoying.

---

## 19. Planned thumbnail shots and clips

These seed `EYECANDY.md` (thumbnails, 1920 × 1080) and `MARKETING.md` (clips, 7-15 s, vertical
1080 × 1920, for `tools/film_game.py`). A Studio session sets up each shot through a copy of Config in
the place only, never `src/`, the way +1 Jump's shot list does [T].

**Thumbnails**
1. **"The sky is falling on your plot"** (Starfall): camera low behind the avatar on its plot, looking up at
   a sky full of shooting stars and the comet, with three meteors mid-streak toward glowing landing spots.
2. **"The Falling Star"**: the gold beam and the star 20 studs above the showcase spot, the avatar
   reaching toward it, and the Beacon's gold beam behind.
3. **"Nebula night"**: a wide shot of four plots under the nebula, every Beacon beam a different colour, the
   observatory in the middle.
4. **"Close call"** (Starfall): a bolide one frame before impact, the red ring on the ground, the avatar a
   step outside it.

**Clips** (how to stage each)
1. *First catch* (8 s): a fresh profile; the first meteor lands 10 studs ahead; walk; it zips into the
   Smelter.
2. *The Falling Star* (15 s): a profile at Beacon 21 with at least 1 538 Stardust (the price of level 22);
   buy the Beacon; the card, the descent, the catch and the fanfare.
3. *Sky change* (12 s): a profile at Beacon 9 with at least 369 Stardust (levels 10, 11 and 12 cost 96, 121
   and 152); buy three Beacon levels and watch Twilight glide into Aurora (the Aurora weight goes 0, 0.26,
   0.74, 1).
4. *Dodge* (10 s): hazards every 8-10 s in the place's Config copy; step out of the red ring as the bolide
   lands.
5. *Collector at work* (10 s): the maximum dish at the spawn floor; the dish swallows half the rain while
   the avatar sprints for a legendary outside it.
6. *Stargaze* (10 s): press Stargaze in the Galactic Core; the camera tilts up to the galaxy disc and arms.
7. *Star Chart* (8 s): walk to the board, toggle Public → Friends.

---

## 20. Store text (for `README.md`; 814 characters by count, limit 1000, no coloured-square emoji)

```
☄️ Meteors fall from the sky onto your own plot. Walk over them to collect them, feed your Smelter, and turn space rock into Stardust.

Upgrade three machines:
• Beacon: reach further into space for more and rarer meteors, and a new sky
• Collector: a dish that catches meteors for you
• Smelter: turns ore into Stardust faster

Your Beacon changes the sky over your plot: dusk, twilight, aurora, a starfall, a nebula and the galactic core. Now and then space junk falls too. A red ring shows exactly where it will land: step out of the ring and it misses.

Need a break? Press Stargaze to sit back and watch the sky. Nothing falls on you while you rest.

Catch your first Falling Star, then climb the Star Chart against everyone, or just against your friends.

No stealing, no raids, nothing to buy. Just meteors.
```

---

## 21. Self-review

Checked against the task and `docs/complete-game-standard.md`, one line each:

* **Core loop in one paragraph**: section 1. **Every number with a reason**: each carries a tag or a
  worked reason. The profiles and the 1.9 s hit cost are the only assumptions, and they are labelled.
* **Reachable from join**: section 14's first minute, and the headless real-player-path gate in section 16.
* **Spawn per SPAWN-ORDER**: section 11 (RespawnLocation before any yield, plus a bounded
  wait-and-correct).
* **Server-authoritative, nothing secret replicates**: 10.2-10.4, the empty attribute inventory, and no
  seeded generation (fork-tower REVIEW-4).
* **DataStore**: pcall everywhere, `canSave` only while holding the lock, an owner token on every write,
  string keys, and the one-time Falling Star inside one atomic `UpdateAsync` (sections 8, 10.1).
* **No silent no-ops**: every refusal in 4.1, 9.4 and 10.5 names its toast.
* **Bands**: six, each with its own light, colour, scenery, critters and weather, triggered by the Beacon,
  gliding (section 5).
* **Hazards**: rare (one per 120-180 s of play), telegraphed, the red ring is exactly the zone, one at a
  time, a hit costs about 1.9 s (section 6).
* **Rest**: never an exploit (section 7).
* **Brag at 35.6 min** in the 30-45 window; **long-term goal at 128.6 min** (section 8).
* **Board**: public + friends, a metric a script cannot inflate with its limits stated, the standard's
  encoding, physical, with a ProximityPrompt, cached names and a useful empty view (section 9).
* **Phone first**: section 15, with hudcheck `overlap = true`.
* **Needs-Studio list**: section 18. **Thumbnail shots and clip list**: section 19. **Store text**: section 20.
* **Fair monetization**: section 13.

Consistency checks, made while writing:
* The model's constants equal every value stated here.
* Band `from` values 0/5/12/22/32/44 and fades satisfy `EnvBands.validate`.
* The showcase (r = 26) lies outside the biggest dish (24) and inside the landing ring.
* The Star Chart (r = 34) lies outside the landing ring (32) and inside the plot (36).
* `PendingSeconds` 7 ≥ 4.6 + 2.
* Every hazard kind's `fall ≤ commit` (0.8 ≤ 1.6, 0.7 ≤ 1.6, 0.9 ≤ 1.8, 1.0 ≤ 1.7, 0.6 ≤ 1.6).
* Server parts ≤ 447.

Contradictions found and fixed while the model was being built, so a reader sees why the rules are as they
are. Items 1 and 2 were measured by earlier revisions of `design/model.luau` and cannot be re-run from the
current file; 3 is arithmetic (4.3); 4's 52 is what M6 still prints for the pathing bot, whose Collector
never sleeps.
1. The first pile-cap rule also refused Collector catches: AFK earned 0.6 % of active play.
2. A cheapest-first star starved the Smelter, burning 56 % of all ore.
3. A Falling Star clogged the hopper for about 45 s at the brag moment.
4. An anti-AFK macro would have climbed to Beacon 52 in 8 h. With the Collector's sleep rule it gains one
   level; only a pathing bot reaches 52.

What this spec does **not** know: whether any of it looks or feels good (section 18), and whether the
normal profile is anything like a real player. Replace `Config.Pacing.Profiles.normal` with telemetry first,
then re-run `Pacing.spec`.
