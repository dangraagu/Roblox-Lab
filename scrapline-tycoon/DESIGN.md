# Scrapline Tycoon: design spec (v1)

**Status: design only.** No game code exists. Nothing is committed, pushed or published, no universe exists, and
Studio has not been opened. Written 2026-10-07 from `docs/game-radar/2026-09-09-roblox-game-radar.md`, ranked entry #5
"Prestige automation tycoon (Scrapline Tycoon)" (line 63) and its runner-up note (line 298): junk goes in, conveyors
and machines turn it into products, prestige for a permanent boost. Held to `docs/complete-game-standard.md` from the
first build; follows `docs/new-game-checklist.md`, `robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md` and
anomaly-observatory's "ServerStorage, not the zone".

**What makes it different from `meteor-drop-tycoon/`:** nothing drops and nothing is collected. The player builds a
production line and optimises it: which station is the bottleneck, whether to upgrade it or build its twin, when to
save for the next station, and keeping the line running. Income comes only out of the line.

## How to read the numbers

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.py`. Run it with `py -3 design/model.py > design/model.out.txt` (about 6 minutes; deterministic, see section 22). The output is saved as `design/model.out.txt`. The model is a design-time tool, not game code. It is Python because the luau CLI directory named in the task (`scratchpad/luau/`) was empty on 2026-10-07; the build ports it to `tests/LineModel.luau`, reading Config. |
| **[T]** | Taken from a template this game copies (`plus1-jump`, `meteor-drop-tycoon`, `deep-vein`, `vault-runners`, `steal-a-cryptid`), where it was measured or reviewed. The source is named. |
| **[R]** | A design rule or arithmetic, worked inline. |
| **[A]** | An assumption. The model's player profiles are assumptions, and every number derived from them inherits that. The first real play session replaces them. |

Numbers inside quoted HUD, toast or card text (for example "Need 1.2M, you have 800K") show the format only; they
are not measurements.

The model's player profiles, all **[A]**:

| profile | opens the shop every | s per purchase | notices a sputter after | walk efficiency | buys |
|---|---|---|---|---|---|
| fast | 10 s | 0.8 | 2 s | 0.95 | the ★ |
| **normal** | 20 s | 1.2 | 4 s | 0.85 | the ★ |
| slow | 45 s | 2.0 | 10 s | 0.70 | the ★ |
| mixed | 20 s | 1.2 | 4 s | 0.85 | the ★ three times in four, otherwise a random affordable purchase that adds income |
| cheapest | 20 s | 1.2 | 4 s | 0.85 | the cheapest purchase that adds income |
| random | 20 s | 1.2 | 4 s | 0.85 | a random affordable purchase that adds income |
| saver | 20 s | 1.2 | 4 s | 0.85 | the ★ without its rule 0 (section 4.5) |
| bot (the script bound) | 0.5 s | 0 | 0 s | walks at the trusted-speed cap, 21.6 studs/s | the ★ |
| afkmacro | 0.5 s | 0 | never fixes | - | the ★, and recycles the moment it can |
| jiggle | never | - | never fixes | - | nothing (an anti-AFK jiggle) |

Following +1 Jump's and Meteor Drop's lesson [T], the reference player is the one who does what the HUD's ★ says.

---

## 1. Core loop

Junk pours out of a chute onto a U-shaped conveyor belt on your own plot and rides past six stations to a shipping
dock, which sells whatever arrives. Each station turns what reaches it into something worth more: the **Shredder**
turns junk into scrap, then a **Furnace** makes ingots, a **Press** plates, a **Cutter** gears, an **Assembler**
robots and a **Rocket Bay** rockets. A station handles only so many items a second, and anything it cannot handle
rides past it unchanged and sells for less, so the line is only as good as its slowest station. You spend your cash
on that bottleneck: upgrade it, build its **twin** (a second machine doubles the station), or save for the next
station, which the HUD's ★ points at. Every three minutes or so a machine starts to **sputter**: walk over and hold
Fix before it jams. Your yard changes as your line climbs, from a dusty junkyard to a foundry, a press works, a
machine shop, a neon robot works and a launch site. Now and then the crane overhead drops something on you; a red
ring shows exactly where, and stepping out of it always dodges. Press **☕ Break** to sit and watch the line run. At
about 34 minutes your first **Rocket** ships and lifts off from your launch pad in front of the whole server: the
brag moment. Then you **Recycle** the factory for a **Gold Bolt**, which makes everything you ship worth 50 % more
forever, and build it again, faster. Four bolts turn your factory gold, about 2 h 10 min in, and the **Top
Recyclers** board ranks Gold Bolts, for everyone or just your friends.

---

## 2. Where v1 departs from the brief, and why

| the radar brief said | v1 does | why |
|---|---|---|
| Conveyors and machines, placed by the player | Six fixed stations in recipe order on one U belt; you choose what to build, upgrade and twin, not where it goes | Free placement in a strict recipe chain has one right answer (the recipe order); it is a chore, not a decision, and it is the hardest thing to make work on a phone. The decision that remains is the real production-line one: where the bottleneck is and how to relieve it (section 4). |
| A junk input you upgrade (droppers) | The chute feeds the Shredder exactly as fast as it can shred; there is no separate chute track | Measured in the model's first two revisions: with a separately priced chute, a balanced line made every single upgrade almost worthless, and the normal player once waited 14.7 minutes between two purchases (section 22, item 1). |
| Prestige for a permanent boost | **Recycle**: one Gold Bolt per recycle, +50 % value each, unlocked by a rocket rate that rises ×1.35 per recycle | A payout that grew with rockets shipped ran away in the model (17 recycles and a ×1 071 multiplier inside a 6-hour run, section 22 item 4). A fixed bolt behind a rising rate keeps every run after the first 26-39 minutes long [M4]. |
| Idle income | The line runs while you are in the server; no offline income | Offline accrual is a clock-delta trust surface and would grow the board with nobody playing (meteor-drop-tycoon's reasoning [T]). |
| (nothing) | **Jams**: the one active job | Without it, an anti-AFK jiggle plus an auto-buy macro would climb the board overnight. With it, they gain 0 Gold Bolts in 8 hours [M5] (section 5). |
| Leaderboards | Top Recyclers: public and friends, on Gold Bolts | The standard's board, on a metric a script cannot inflate (section 10). |

---

## 3. The world

One server holds **6 plots** on a ring around a central **Scrap Market** landmark, on one continuous ground plate.

| thing | value | reason |
|---|---|---|
| Plots per server | 6, and `Players.MaxPlayers` = 6 | One plot per player, always. `MaxPlayers` is a Studio/Creator setting (section 19). A seventh player is kicked with "This server's 6 factories are taken. Rejoin to get a server with room." and the server logs it (meteor-drop-tycoon's rule [T]). |
| Plot size | 64 × 76 studs (x ∈ ±32, z ∈ ±38, plot-local) | The machines' outer edges are at x = ±18, which leaves 14 studs on each side for the launch pad and for walking round; the U-turn's outer edge (z = 35) stops a stud short of the back wall [R]. |
| Plot centres | on a ring of radius 150 around the world origin, 60° apart; each plot's −Z faces the origin | Neighbouring plots are 56.6 studs apart at their closest corners, computed over the rotated rectangles [R]. Nothing of one plot reaches another. |
| Ground | one Baseplate, 400 × 400, top at y = 0 | The farthest plot corner is 190.7 studs from the origin, inside the plate's 200 [R]. The ground is continuous, so a knock (section 7) can never drop anyone off anything. |
| Scrap Market | a junk mountain with a dead crane at the origin, radius 30, at most 20 Parts | A landmark for thumbnails and orientation; decorative, nothing interactive. The nearest plot edge is 112 studs from the origin [R]. |

**Plot-local layout** (origin at the plot centre, −Z towards the Scrap Market):

| part of the plot | where | reason |
|---|---|---|
| Arrival pad (`Plot_k.Arrival`, SpawnLocation 6 × 1 × 6) | (0, −30), facing +Z | You arrive in the mouth of the U, looking along your whole line. Section 12. |
| Chute (junk hopper with the crane magnet over it) | (−14, −29), 8 × 8, 10 tall | Front-left, so the belt starts beside the arrival and the first thing you see is junk pouring in. |
| Belt | left leg x = −14 from z = −25 to 19; a U-turn of radius 14 centred on (0, 19); right leg x = +14 from z = 19 back to −25; 4 wide, top at y = 1 | 132 studs long: 44 per leg plus a 44-stud U-turn [R]. Its outer edge reaches z = 35, a stud short of the back wall. A visual item rides it in 13.2 s at 10 studs/s (section 16). One stud high, so it can be stepped over. |
| Stations 1-3 (Shredder, Furnace, Press) | left leg, centres z = −16, −2, 12 | Each station is 14 studs of belt; its machine sits 3.5 studs upstream of the centre and its twin 3.5 downstream. Machines are 6 along the belt × 8 across, 6-9 tall. |
| Stations 4-6 (Cutter, Assembler, Rocket Bay) | right leg, centres z = 12, −2, −16 | Recipe order along the flow, so the Rocket Bay ends beside the dock. |
| Shipping dock | (14, −29), 8 × 8 | Front-right, mirror of the chute: the line visibly goes round and comes home. |
| Launch pad | (26, −28), radius 4 | Beside the dock, 26.1 studs from the arrival [R], in view of the arrival camera. The first rocket of every run lifts off here (section 9). |
| Top Recyclers board | (7, −21), 10 wide × 10 tall on two legs, its face turned towards the arrival | **REVIEW-2 R1** (it was (−5, −23), 7 × 4.5, and a row was 3.3 px tall on a phone at the default camera): 11.4 studs from the arrival centre [R], inside its prompt's 13-stud reach, on the DOCK side so it hides neither the chute nor the Shredder (the first job). Its face is 10 × 9.2 with 11 rows of 0.686 studs: read from 5 studs at Roblox's default camera, a row is 10.1 px on an 800 × 360 phone, the HUD's own hint text being 9.6 (`check_scraplinetycoon_boardview`). It clears the right belt leg, the dock and the Rocket Bay's twin by 0.66 studs or more (`PlotGeom.spec`). Tall now: it hides part of the U's right half from the spawn camera (section 19). |
| Factory wall | z = 36..38, x = ±30, 14 tall, two chimneys 24 tall, the SCRAPLINE sign | The back of the yard. Its paint is the factory grade (section 9.3); the sign's neon is your band's accent (section 6). |
| Gantry crane | rails along x = ±30 at height 28, a bridge across the plot | Where hazards come from (section 7). Static on the server; the client moves the trolley. |
| Owner sign | BillboardGui over the chute with the owner's display name | Which plot is whose. |

The U's inside (x ∈ ±10, from z = −25 to the U-turn) is open floor where you walk; the board stands in its mouth on
the dock side (x 2.8-11.2), so the way in from the arrival is the chute side of the mouth. From its middle, (0, −2), every
station is 14.0 or 19.8 studs away; from the arrival, 19.8 to 44.3 studs [R]. The server builds all six plots at
start-up, before any player joins, so a plot exists before any character can spawn on it (section 12).

**The edge of the world is a wall (REVIEW-2 R7).** The 400-stud plate ends 12.0 studs behind plots 1 and 4 (21.2
behind the others). Four invisible, collidable walls, 60 tall and 4 thick, stand on its edges
(`Config.World.EdgeWallHeight`, `EdgeWallThickness`), so nothing can walk or be knocked off the world. They are fully
transparent, which Roblox's camera ignores (it should never push the camera in; section 19 confirms it).

---

## 4. The line

### 4.1 Products and stations

| state | product | sells for (× your multiplier) | made by | first copy | twin | speed at level 1 | level 1→2 | 10→11 | 20→21 | 30→31 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Junk | 1 | the chute | - | - | - | - | - | - | - |
| 1 | Scrap | 2 | **Shredder** | free (one tap) | 240 | 1.0 /s | 8 | 308 | 17 735 | 1 022 672 |
| 2 | Ingot | 5 | **Furnace** | 650 | 1 140 | 1.6 /s | 38 | 1 461 | 84 240 | 4 857 694 |
| 3 | Plate | 12 | **Press** | 13 000 | 4 380 | 2.6 /s | 146 | 5 613 | 323 658 | 18 663 770 |
| 4 | Gear | 30 | **Cutter** | 130 000 | 17 700 | 4.1 /s | 590 | 22 682 | 1 307 934 | 75 422 083 |
| 5 | Robot | 75 | **Assembler** | 1 100 000 | 71 400 | 6.6 /s | 2 380 | 91 495 | 5 276 074 | 304 245 014 |
| 6 | Rocket | 200 | **Rocket Bay** | 9 500 000 | 315 000 | 10.5 /s | 10 500 | 403 655 | 23 276 797 | 1 342 257 415 |

All prices and speeds are [M1]. The rules behind them:

| number | value | reason |
|---|---|---|
| Product values | 1, 2, 5, 12, 30, 75, 200 | About ×2.5 per step, so each new station is a jump you feel in income [R]. Red is never a product colour (section 16). |
| `BaseSpeed` | ×1.6 per station: 1.0, 1.6, 2.6, 4.1, 6.6, 10.5 items/s | A new station arrives when the line is bigger, so it starts faster. With slower new stations the run stalled before the Rocket in the model's first revision (section 22, item 2). |
| `SpeedGrowth` | ×1.25 per level, shared by a station's machine and twin | A level is a visible step. M8: 1.22 puts the first Rocket at 56.6 min, 1.28 at 23.2 min. |
| `UpgradeBase` | 8 × BaseSpeed × (value the station adds per item), rounded | Every station's first upgrade pays for itself in the same 32 s [M1]. Pricing upgrades by the value they add is what keeps a single upgrade worth buying; the first draft's flat prices made every upgrade worthless in a balanced line (section 22, item 1). |
| `UpgradeGrowth` | ×1.5 per level | Payback grows ×1.2 per level [M1], so a station saturates at a modest level and the next station takes over. With ×1.25 the levels ran into the cap of 60 by minute 30 (section 22, item 3). M8: 1.45 gives 25.6 min to the Rocket, 1.55 gives 43.9. |
| `TwinPrice` | 30 × the station's first upgrade | A twin doubles a station, which equals 3.11 levels [M1]. Three levels from level L cost (1 + 1.5 + 2.25) × 1.5^(L−1) = 4.75 × 1.5^(L−1) first-upgrades, which passes 30 from level 6 on, so that is where the twin starts to win [R]: a natural mid-game purchase. Without twins the first Rocket takes 68.3 min [M8]. |
| `BuildPrice` | 0, 650, 13 000, 130 000, 1 100 000, 9 500 000 | Bisected in the model, station by station, against band targets of 2.5, 6.5, 12.5, 21 and 34.5 min (three seeds), then rounded; the Rocket Bay went down from the bisected 10.4M to 9.5M, because at 10.4M the ten-seed median Rocket came at 37.0 min. M8: ×0.8 gives 30.9 min to the Rocket, ×1.25 gives 37.9. |
| `MaxLevel` | 100 | A safety cap only: after 8 hours the normal player's highest station is level 46 and the bot's 42 [M5]. Prices stay finite: level 99→100 of the Rocket Bay costs 10 500 × 1.5^98 ≈ 1.8 × 10^21 [R]. |
| Unlock rule | a station can be built once the one before it exists | One obvious next step. The Shredder is free and is the tutorial's first tap. |

### 4.2 The flow: how a line earns

The server computes the line's steady flow, a pure function of the six stations (`Line.flow`, spec'd):

```
intake = 0.5 junk/s before the Shredder exists, else max(0.5, Shredder capacity)     -- the chute feeds the Shredder
r[0] = intake; r[1..6] = 0
for station t = 1..6:  moved = min(r[t-1], capacity(t)); r[t-1] -= moved; r[t] += moved
capacity(t) = (working machines at t: 0, 1 or 2) × BaseSpeed[t] × 1.25^(level - 1)       -- a jammed machine is not working
income per second = Σ r[s] × value[s] × (1 + 0.5 × Gold Bolts)
```

What reaches the dock is sold on the server's own clock (a 0.5 s tick, `tick()`-based as `robloxemu` advances it
[T: meteor-drop-tycoon]). Overflow is never lost: an item a station cannot take rides past it and sells as what it
already is. That is why every upgrade on a cascading line adds income, and why the HUD can say exactly how much.

### 4.3 The bottleneck

`Line.bottleneck` names the built station whose capacity is smallest against what reaches it (ties: the earlier
station). The owner's client floats a 🐢 over it, and the line panel marks its row "slowest: 8.1 of 12.0/s". Each
station row also shows a load bar (what reaches it ÷ what it can take; above 100 % means items ride past unchanged).

### 4.4 Twins

A station holds at most two machines. The twin costs `TwinPrice`, sits on the second half of the station's belt,
shares the station's level (one upgrade raises both) and doubles its capacity. It is also insurance: when one of
the two jams, the station keeps half its capacity (section 5).

### 4.5 The HUD's ★: what to buy next

A pure function, `Economy.star`, recomputed by the server on every change and pushed to the owner:

0. **The next station**, the moment it is affordable, and from `SaveWindow = 60` seconds of income before that. The
   HUD then says "Saving for the Cutter: 0:42" and stars nothing else.
1. Otherwise the **target** is the purchase that pays for itself soonest, counting the wait to afford it:
   `max(0, price − cash) / income + price / gain`, ties to the cheaper.
2. While the target is unaffordable, the ★ goes to the affordable purchase with the shortest payback, if that
   payback is shorter than the wait for the target (buying it brings the target closer, never further). Otherwise
   the ★ stays on the target: save up.

Why rule 0 exists, measured: a new station opens a fresh set of 32-second upgrades, which a payback score that sees
only the new machine's first level undervalues. The `saver` profile (rules 1-2 only) shipped its first Gear at 43.9
min and never reached a Robot in 90 minutes [M2]. Why the 60-second window: without it (window 0) a player who
shops often spends on small upgrades just before the station becomes affordable, and the first Rocket comes at 40.6
min instead of 33.9; a 120-second window gives 33.3 min [M8], no real gain, for a save twice as long before every
station [R].

What following the ★ gives, to the first Rocket [M2]:

| profile | first Rocket (min, p10 / median / p90) | purchases | longest wait between purchases |
|---|---|---|---|
| fast | 33.0 / 33.1 / 33.3 | 134 | 120 s |
| **normal** | **33.8 / 33.9 / 34.1** | **137** | **120 s** |
| slow | 35.6 / 35.8 / 36.1 | 142 | 135 s |
| mixed | 35.1 / 36.1 / 39.9 | 140 | 100 s |
| bot | 32.2 / 32.2 / 32.2 | 133 | 126 s |
| cheapest | 53.2 / 53.3 / 53.5 | 160 | 80 s |
| random | 49.4 / 52.9 / 56.2 | 156 | 80 s |
| saver | never in 90 min | - | - |

Purchases and waits are medians over 20 seeds. The longest waits are the 60-second saves for a station plus the
time to the next shop visit. Players who ignore the ★ entirely reach the Rocket at about 53 minutes, outside the
30-45 window; one who follows it three times in four is inside it.

**Green: worth buying (REVIEW-2 R3).** The panel used to paint every affordable button green, so a player who tapped
whatever was green, not the gold ★, reached the first Rocket at 53 min (the reviewer's model) and at 50.7 min through
the real HUD. Now `Economy.worth` decides green: the next station, or a purchase that adds income and pays for itself
within `Star.GreenPayback` = 2 × the best payback on the list; and **nothing** is green while the ★ saves for the
next station (rule 0). An affordable purchase that is not worth it now is a muted blue-grey; one you cannot afford is
grey; the ★ is gold. Measured (`Pacing.spec`, 20 seeds): a player who taps any gold or green button at random lands
the first Rocket at 35.0 / 36.8 / 39.8 min (p10 / median / p90; shopping every 60 s: 36.3 / 38.0 / 40.1), and the
walk's green mode, through the real HUD, at 34.3 min. A player who taps any affordable button whatever its colour still
takes 53.0 (the CONTROL that shows the colours carry the guidance). So the HUD makes the next station impossible to miss (section 16), and the tutorial teaches "save for the
next station" (section 15).

---

## 5. Jams: the one active job

Every three minutes or so one machine on your line starts to **sputter**: it shakes, throws amber sparks, and the HUD
says "⚠ Your Press is sputtering: walk over and hold Fix (0:12)". Hold Fix within reach of it before the 15 seconds
run out and it is saved ("Saved it!"). Otherwise it **jams**: it stops, smokes, wears a "⚠ JAMMED" sign, and items
ride past it unchanged until you fix it.

| number | value | reason |
|---|---|---|
| `JamMin` / `JamMax` | 150 / 210 s of line time between sputters | About one every 3 minutes: 10 sputters before a normal player's first Rocket [M2]. |
| `FirstJamIn` | 240 s for a brand-new profile | The first four minutes have no sputter; the first one is the tutorial's fourth step (section 15). |
| `SputterSeconds` | 15 | The normal player needs 4 s to notice [A] + at most 19.8 studs from the middle of the U at 13.6 studs/s (1.5 s) + the 0.5 s hold = 6.0 s; the slow player 10 + 1.8 + 0.5 = 12.3 s [R]. Every active profile saved every sputter: 0 machine-seconds jammed, 0.0000 of income lost [M2]. Even from the arrival pad, the farthest station (44.3 studs) is 4 + 3.3 + 0.5 = 7.8 s away for the normal player [R]. |
| `FixHold` | 0.5 s, `FixRange` 12 studs | A deliberate press, not a brush-past. The prompt shows at 10 studs; the server accepts 12 against the trusted position (section 13), so lag never refuses an honest fix. |
| Target | one random working machine (`Random.new()` on the server) | Any machine, so a twin is insurance: a jam halves that station instead of stopping it. |
| One at a time | the clock runs only while no sputter is live | Never two warnings at once. Jams that are not fixed stay jammed and the clock moves on, so an untended line degrades. |

**What a jam costs**, measured on the normal player's 35-minute line left completely alone [M7] (three seeds):

| left alone for | income now, × a tended line | earned so far, × a tended line |
|---|---|---|
| 5 min | 0.78-0.81 | 0.90-0.93 |
| 10 min | 0.06-0.54 | 0.57-0.78 |
| 30 min | 0.00-0.01 | 0.22-0.47 |
| 60 min | 0.00 | 0.11-0.24 |

The fallback is the chute's 0.5 junk/s trickle (section 4.2), never zero. For an active player jams cost attention,
not income. For an idle line they are the bound: an unattended factory winds down within half an hour.

**Persisted, so a rejoin never clears a jam** (meteor-drop-tycoon REVIEW-1 A6 [T]: a rejoin used to re-arm its
Collector). The profile saves each station's jammed-machine count and `jamIn`, the line-seconds left to the next
sputter. A sputter still running when you leave is saved as a jam. Offline time never moves the clock.

**Jams and rest.** Rest does not touch jams: the jam clock keeps running, exactly as for anyone standing still
(section 8). Hazards are held while a sputter is live on your line (it has a 15 s clock and sends you walking).
**A standing jam does not hold them (REVIEW-2 R5):** it has no clock, and holding for it froze the crane for good for
anyone who left one jammed twin or rejoined with a saved jam (the reviewer: 1 drop in 10 minutes).

---

## 6. The environment bands

### 6.1 What triggers them

**The trigger is the highest product your line has shipped this run, 1-6: the game's own logic, never time.**
`tier` is server-measured (a product counts once one whole item of it has been sold) and only ever rises within a
run. It reaches the owner in `State`. Your yard looks like the factory you have built: a junkyard while you shred
scrap, a foundry from your first ingot, and so on up to a launch site from your first rocket.

* **Named by the integer** `tier`: the band chip, the title card, which hazards fly, all use
  `EnvBands.indexAt(bands, tier)`, so they always agree (+1 Jump review finding 7 [T]).
* **Glided, not blended.** `fade = 0` on every band, the exception `EnvBands.validate` allows [T]: a band arrives
  because you shipped a new product, a discrete achievement, so the sky should change then and not creep in early.
  Every written value glides to the new band with `EnvBands.approach` at a **1.5 s half-life** (meteor-drop-tycoon's
  purchase glide [T]), so nothing cuts. Lighting is written at most 10×/s and only on change [T].
* **A title card** on the first entry into a band in a run ("🔥 THE FOUNDRY: you shipped your first Ingot"). A player
  who joins mid-run already in a band gets a quiet chip instead; the first card waits until the saved state has
  loaded (+1 Jump's slow-load lesson [T]).
* **After a Recycle** the band returns to the Junkyard under the recycle's white flash, with the glide off for that
  one write (section 9.2). `ClockTime` only ever rises within a run, so no blend ever sweeps the sun backwards
  through the day; the one backwards jump happens behind the flash.

### 6.2 The six bands

Minutes are the normal player's median time to enter the band in the first run [M2]; durations are min / median /
max over 20 seeds [M3].

| # | band | from tier (product) | enter at min | lasts min | light | scenery (client) | critters (client) | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏚️ Junkyard | 0-1 (Scrap) | 0.1 | 2.3 / 2.5 / 2.6 | dusty midday, `ClockTime` 13.0 | junk mountains, tyre stacks and rusted car hulks round the horizon | a flock of 5 crows | dust motes 6/s | none |
| 2 | 🔥 Foundry | 2 (Ingot) | 2.6 | 3.7 / 4.0 / 4.0 | warm afternoon, 15.5 | brick chimneys with smoke plumes | 4 pigeons | embers 10/s | scrap bale |
| 3 | 🏗️ Press Works | 3 (Plate) | 6.6 | 5.7 / 5.7 / 6.3 | late afternoon, 17.0 | steel girder frames, a water tower | a flock of 5 swallows | steam puffs 5/s | scrap bale, pipe |
| 4 | ⚙️ Machine Shop | 4 (Gear) | 12.2 | 8.0 / 8.7 / 9.3 | sunset, 18.3 | giant gears turning on far towers | 3 maintenance drones | gold sparks 8/s | pipe, big gear |
| 5 | 🤖 Robot Works | 5 (Robot) | 20.9 | 12.7 / 13.0 / 13.7 | night, 20.5, 1 500 stars | neon signs, holo billboards, searchlights | 4 delivery drones, blinking | light rain 25/s | bolt bucket, dropped parcel |
| 6 | 🚀 Launch Site | 6 (Rocket) | 33.9 | until the recycle (9.7 min in run 1 [M4]) | deep night, 22.5, 4 000 stars | a launch gantry, a big moon, sweeping searchlights | 2 satellites crossing, a far rocket trail every 20 s | stardust 6/s | booster cap, big gear |

Every band lasts at least 2.3 minutes in the first run, above the 2 minutes +1 Jump holds itself to [T]. Later runs
are the reward for recycling and go faster: in run 2 the Junkyard lasts 1.7 min and the Launch Site 10.0; in run 5,
1.3 and 13.3 [M4].

Starting lighting values (every band defines the same fields, as +1 Jump's `EnvConfig.spec` requires [T]). These are
starting points; only real rendering can judge them (section 19):

| band | Brightness | Ambient / OutdoorAmbient | Atmosphere Density, Color | ColorCorrection TintColor | Bloom | accent (sign neon) |
|---|---|---|---|---|---|---|
| Junkyard | 2.6 | 130,120,105 / 160,150,130 | 0.35, 210,190,150 | 255,245,225 | 0.8 | 230,190,90 |
| Foundry | 2.3 | 135,110,90 / 170,135,110 | 0.30, 230,160,110 | 255,232,205 | 1.0 | 255,150,50 |
| Press Works | 2.0 | 115,105,110 / 150,135,150 | 0.25, 200,150,150 | 245,230,235 | 1.1 | 120,170,230 |
| Machine Shop | 1.5 | 95,100,115 / 120,125,160 | 0.20, 150,140,190 | 230,235,255 | 1.3 | 90,220,200 |
| Robot Works | 1.1 | 80,80,110 / 100,95,150 | 0.18, 70,60,120 | 235,220,255 | 1.6 | 0,230,255 |
| Launch Site | 0.9 | 95,95,120 / 120,120,160 | 0.08, 30,30,60 | 245,240,255 | 1.8 | 255,230,150 |

* `ClockTime` rises 13.0 → 15.5 → 17.0 → 18.3 → 20.5 → 22.5 and stays below 24 [R]; `EnvConfig.spec` asserts it.
* Weather peaks at 25/s alone; with `EnvBands.capRates` (at most 2 emitters, 60/s together) a glide between two bands
  stays under budget [T].
* The OutdoorAmbient floor keeps the line readable at night; machines, items and the dock use Neon accents.
* **The server's starting light** is `Fx.applyLighting(Fx.Presets.Junkyard)`, a new preset equal to band 1, so the
  client's first write is not a jump. Adding one preset is the only edit to the copied `Fx.luau`, as fork-tower
  added `Fork` and meteor-drop-tycoon added `Dusk` [T].
* **Everything in this section is client-only** except the SCRAPLINE sign's neon colour, which the server sets to your
  band's accent so everyone can see how far your line has come. Your sky follows your own tier, so other plots are
  seen under your sky (meteor-drop-tycoon's split [T]).

---

## 7. Hazards: the crane drops something

**Template.** Copy `meteor-drop-tycoon/src/shared/Hazards.luau` and its spec. That file is `plus1-jump`'s
`Hazards.luau` with deep-vein's marked **DEEP VEIN ADAPTATION** (vertical kinds, `drop = "above"`, and the
`ctx.canDodge` hold) and nothing else: `diff` against plus1-jump's copy shows 93 differing lines, the header and the
adaptation's code in `validate`, `pickKind`, `plan`, `positionAt`, `retarget`, the hold and the knock fallback [R,
measured with `diff`]. **Why this game needs the adaptation:** the yard is flat and open, so a
sideways lane that starts inside the camera's pitch window starts underground (meteor-drop-tycoon section 6 works
the numbers [T]); and the theme gives the hazard a natural source straight overhead, the gantry crane. The crane's
trolley rolls over you while the warning tracks you, its magnet light turns red when the lane locks, and the load
drops.

**The rule the standard asks for, exactly:** the red ring is the hazard's zone, radius `hitRadius + PlayerRadius`,
centred where you stood when the lane last aimed. A hit needs you inside the ring *and* the falling object passing
within reach. **Stepping out of the ring in any direction always dodges** (+1 Jump review round 2 [T]).

| kind | bands | hangs at (studs above you) | fall s | warning s | locks s before | hitRadius (ring radius) | knock studs/s | template row [T] |
|---|---|---|---|---|---|---|---|---|
| scrap bale | Foundry, Press Works | 25 | 0.8 | 3.2 | 1.6 | 2.4 (3.9) | 36 | satellite |
| pipe | Press Works, Machine Shop | 25 | 0.7 | 3.2 | 1.6 | 2.2 (3.7) | 34 | ice |
| big gear | Machine Shop, Launch Site | 25 | 0.9 | 3.6 | 1.8 | 3.0 (4.5) | 42 | bolide |
| bolt bucket | Robot Works | 25 | 1.0 | 3.4 | 1.7 | 2.6 (4.1) | 34 | plasma |
| dropped parcel | Robot Works | 25 | 0.6 | 3.2 | 1.6 | 2.2 (3.7) | 44 | neutron |
| booster cap | Launch Site | 80 | 0.9 | 3.6 | 1.8 | 3.0 (4.5) | 42 | bolide |

Every row's timing and size is the named row of meteor-drop-tycoon's `Config.Hazards.Kinds`, which follows the
template's limits [T], and every kind keeps that file's `pass` of 1.0 s (how long it keeps falling past the impact). Only the height changes: 25 studs is the crane (rails at 28, minus the player's root at about
3) [R]; the booster cap falls from the sky, at the template's 80.

| number | value | reason |
|---|---|---|
| `IntervalMin` / `IntervalMax` | 120 / 180 s of **non-rest time on your own plot** | The template's rarity [T]: about one near-miss per 2-3 minutes. Measured: 12 hazards before the normal player's first Rocket (p10 12, p90 13) [M2], in the 31.3 minutes after the Junkyard: one per 2.6 min. |
| First hazard band | 2 (Foundry) | The first 2.6 minutes are hazard-free [M2]. |
| `MinTelegraphSeconds` / `MinCommitSeconds` | 3 / 1.5 | The template's [T]; every kind meets them, and `fall ≤ commit` holds for each (0.8 ≤ 1.6, 0.7 ≤ 1.6, 0.9 ≤ 1.8, 1.0 ≤ 1.7, 0.6 ≤ 1.6, 0.9 ≤ 1.8), so nothing moves before its lane locks [R]. |
| `PlayerRadius` / `AimJitter` | 1.5 / 0.8 | [T: +1 Jump, deep-vein] |
| Ring radius | 3.7-4.5 studs | Leaving it from its centre takes at most 4.5 / 16 = 0.28 s, against at least 1.6 s between lock and impact [R]. |
| `KnockLift` / `KnockSeconds` | 8 studs/s (the module caps 15) / 0.9 s | A shove and a stumble [T]. The ground is continuous; nothing can be knocked off anything. |
| `MaxRetargetSpeed`, `SpreadDegrees` / `ViewPitchDegrees` / `KindFitDegrees` | 1.5, 0 / 20 / 25 | [T]; the last three only because `Hazards.validate` requires them. |

**Where and when.** A hazard launches only while you are grounded, on your **own** plot, not resting, and none of
these is true (each passes `ctx.canDodge = false`, deep-vein's hold [T]): a machine on your line is sputtering (not
merely jammed: REVIEW-2 R5, section 5); the first-Rocket lift-off is playing; the recycle sequence is playing. A due hazard in a quiet band is re-rolled, not
held (the template's rule [T]).

**Telegraph** (client): the crane's trolley rolls to above you, a ⚠ light on the magnet, a light pillar down to the
ring, the ring at your feet (yellow while it tracks you, red when it locks), and a banner "⚠ CRANE DROP: step out of
the red ring". At the lock the pillar and ring turn solid red and the banner says "MOVE!".

**Client-only, and why** (+1 Jump's split [T]): the schedule, the telegraph, the hit test and the knock run on the
owner's client. A hazard only touches the local character, whose physics that client already owns, and it grants
and removes nothing. An exploiter who deletes hazards avoids a stumble and gains nothing else. The price: other
players see you stumble with nothing hitting you (section 19).

---

## 8. Rest: ☕ Break

Copy `plus1-jump/src/shared/Rest.luau` and its spec **verbatim** (meteor-drop-tycoon's copy is byte-identical,
checked with `cmp` [R]). Deep Vein's additions (`SettleSeconds`, `MinAwakeSeconds`) exist because a miner earns by
clicking while standing still [T]; here nothing a player does earns while standing still except the line itself,
which earns the same whether you rest or not, so those rules have nothing to close [R].

* **☕ Break button** (right edge, section 16): your avatar sits down on a crate by the arrival, and the camera drifts
  slowly along your line. The chip says "☕ On break: the crane leaves you alone. Your line keeps running, and machines
  can still jam." Press again or move to carry on.
* **No idle rest** (REVIEW-1 B3, an adaptation of the template's number, not its code). The template rests a player
  who stands still for 20 s, which suits +1 Jump, where standing still means away. Here the game is played standing
  still and tapping the HUD, and the idle rest froze the crane for those players: the walk, standing between taps, got
  one drop per 31.6 min instead of one per 2-3, and the chip read "💤 Resting" most of the game. `IdleSeconds = 0` is
  the template's own off switch (`Rest.validate`: "0 disables idle rest"). An AFK player gets the crane like anyone
  else: a stumble on continuous ground, nothing lost.

| number | value | reason |
|---|---|---|
| `IdleSeconds` | 0 | No idle rest; only ☕ Break rests (REVIEW-1 B3) [R]. |
| `WakeGraceSeconds` | 0.4 | [T] |
| `PendingSeconds` | 7 | A rest asked for while a hazard is inbound is queued; it must outlive the longest flight (big gear and booster cap: 3.6 warning + 1.0 pass = 4.6 s) by more than 2 s [R, T]. |
| `RequireGrounded`, `BlockWhileThreat`, `WakeOnMove` | true | `Rest.validate` requires the last two [T]. |

**Why rest can never be an exploit:**
1. **Rest pauses only hazards.** Their clock freezes during rest and is never reset, so toggling rest cannot thin
   them out (+1 Jump measured 142 / 142 / 142 [T]).
2. **Rest earns nothing that standing still does not.** Income is the line's flow, the same resting or not. The jam
   clock does not freeze, so a rest is no shield for income: a line left on break winds down exactly like one left
   alone (section 5). Purchases need the HUD; fixes need walking, and walking wakes you.
3. **It is not a panic button**: it cannot start with a hazard inbound (the template's queue [T]).
4. **Nothing races a clock**: there is no round, no timer and no penalty for pausing.

Roblox's own 20-minute idle kick still applies. Nothing is lost when it fires: purchases are saved within 7 s and
cash every 60 s (section 11).

---

## 9. The brag moment and the long-term goal

### 9.1 The brag moment: lift-off

When your line ships its **first Rocket of a run**, the dock lifts it onto the launch pad and it launches: a
smoke column, a flame, a long trail up into the sky, a camera shake, an FOV punch and a flash for you (FxClient
[T]), the card "🚀 LIFT-OFF! Your factory builds rockets!", and a toast to the whole server: "<name> launched their
first rocket!". Everyone on the server sees it go up from your plot (every client animates the same launch from the
server's `Announce`).

* **Measured: 33.9 min** median for the normal player (p10 33.8, p90 34.1); fast 33.1, slow 35.8, mixed 36.1, bot
  32.2 [M2]. The standard's window is 30-45 min. Fast, normal and slow are 2.7 min apart, because purchasing, not
  walking skill, sets the pace.
* **Not luck.** It is guaranteed by building the Rocket Bay; nothing is rolled.
* **No grant, so nothing to duplicate.** The lift-off pays nothing beyond the rocket's sale. Only the run's `tier`
  (now 6) is saved, so a rejoin never replays it; the next run's first rocket launches again, with the card
  "Run 3: lift-off!".

### 9.2 Recycle and the Gold Bolt

Once your line ships rockets fast enough, **♻ Recycle** lights up with the ★: "Recycle your factory? You keep your
Gold Bolts. You lose your cash and machines. You get +1 Gold Bolt: everything you ship is worth 50 % more, forever."
**[Recycle] [Not yet]** (a confirmation, because on a phone a stray tap must not end a run). Then the crane sweeps
the line, the machines crumble into the chute, a white flash, and the yard comes back as a junkyard with a free
Shredder already in place and your factory one grade shinier.

| number | value | reason |
|---|---|---|
| Requirement for recycle *k* (k = bolts + 1) | your line ships `1500 × 1.35^(k−1)` rockets per second, jams counted | A rate, so it measures how good your line is, not how long you waited. 1 500/s comes about 10 minutes after the first rocket: the first recycle is at 43.6 min for the normal player [M4], so the Launch Site band in run 1 lasts 9.7 min. The ×1.35 keeps every later run 26-39 minutes long [M4]; in an earlier revision (500/s, ×1.5 per recycle) the twelfth run took 48.7 min. |
| Reward | exactly **+1 Gold Bolt**; value multiplier = 1 + 0.5 × bolts | One bolt per recycle is legible ("you have 3 bolts") and cannot run away. With the first bolt (×1.5), run 2's five bands before the Launch Site last 1.7 + 2.7 + 3.7 + 5.3 + 8.3 = 21.7 minutes (medians), against 33.9 to the first rocket in run 1, and the whole run 31.7 minutes against 43.6 [M4]. |
| Recycle star | on from the moment the requirement is met | There is nothing to gain by waiting: the bolt is fixed [R]. |
| What it wipes | cash (to 0), every station (the Shredder comes back free at level 1, the rest unbuilt), all jams (the machines are new), `tier` (to 0) | A new run starts where the first one did, with the multiplier. |
| What it keeps | `bolts`, `boltsAt`, `jamIn`, `tutorial` | The jam clock keeps counting, so a recycle is never a way to dodge it (section 13). |

**Atomic, and refused rather than lost.** A recycle is the game's only irreversible action, so it follows deep-vein's
`Prestige.apply` shape (every check before the first assignment [T]) and the checklist's one-time-grant rule:
1. The server checks, in order: the profile has loaded; the session is saving (it holds the lock with its owner
   token); no recycle or write of this session is in flight; the line's flow, jams counted, ships at least the
   requirement. Each failure is a toast: "Ship 1.5K rockets a second to recycle (now 920/s)", "Recycling needs your
   save, and it is not being saved this session. Rejoin to recycle.", "Recycling… one moment".
2. It sets `recycling` (Buy and Fix answer "Recycling… one moment") and makes **one** owner-checked `UpdateAsync`
   that writes the whole new run state and `bolts + 1` together.
3. Only when that write succeeds does it apply the result in memory, rebuild the plot and play the sequence. If it
   fails: "The recycle didn't save. Nothing changed. Try again in a moment." and nothing has changed. **The next try
   then waits `Recycle.RetrySeconds` = 10 s (REVIEW-2 X3)**, said out loud ("The save is having trouble. Nothing
   changed: try again in 8 s."): one client firing Recycle at the remote limit against a failing store made 80 profile
   writes in 10 s, against a write budget of 60 + 10 × players a minute that every autosave shares. Now 1.

A non-saving session never recycles. That is stricter than meteor-drop-tycoon's Falling Star, which may spawn in a
non-saving session [T]: there, a lost grant costs nothing; here, a recycle wipes a run, and a bolt that vanished at
the next join would wipe it for nothing.

### 9.3 The long-term goal: the Golden Factory

Each Gold Bolt repaints your factory, and everyone sees it (server-side material and colour on the wall, chimneys,
chute and dock; never red):

| bolts | grade | look |
|---|---|---|
| 0 | Rusty | rust brown 150,90,50, corrugated metal |
| 1 | Painted | safety yellow 230,190,60 |
| 2 | Steel | brushed steel 170,180,190 |
| 3 | Chrome | polished metal 220,225,235, high reflectance |
| 4 | **Gold** | gold 255,200,60 with a golden SCRAPLINE sign |

**The Golden Factory, 4 Gold Bolts, at 129.9 min for the normal player** (fast 125.3, slow 143.0) [M4]: 3.8× the
brag time and under 2 h 30 min. After it the bolts keep counting, every run asks for a faster line, and that climb is
the Top Recyclers board: the normal player holds 11 bolts after 6 hours, and the runs lengthen slowly, from 26.0
minutes (runs 5 and 6) to 39.0 minutes (run 11) [M4].

---

## 10. The Top Recyclers board: public and friends

### 10.1 The metric: Gold Bolts

Ranked on **Gold Bolts**. Ties go to whoever reached that count first. The board shows the grade next to the count
("🥇 4" for a Golden Factory).

**Why a script cannot inflate it.** Follow one bolt back to its source:
1. A bolt is minted only by the server, in the recycle's own atomic write (section 9.2).
2. A recycle is allowed only when the server's own flow model of your line ships the required rocket rate.
3. The flow reads only server state: station levels and twins, which change only through a `Buy` the server has
   priced and validated, and jams, which clear only through a `Fix` the server has validated against your trusted
   position (section 13).
4. Cash is minted only by the server's tick, from that flow.

No client input makes a station faster, a product worth more or a recycle cheaper. **Measured** [M5], over 8 hours:

| behaviour | Gold Bolts gained in 8 h |
|---|---|
| the normal player, from join | 13 |
| a bot with zero reaction time that fixes at the trusted-speed cap and buys the instant it can, from join | 14 |
| an auto-buy + auto-recycle macro that never fixes a jam, from join | **0** (it stalls at Plates) |
| the normal player hands over at 35 min to: the normal player / the bot / the macro / an anti-AFK jiggle | 14 / 14 / 0 / 0 |
| the normal player hands over at 130 min (Golden Factory) to: the same four | 11 / 11 / 0 / 0 |

The macro is the AFK farmer's cheapest tool; jams stop it cold, even from a Golden Factory, because a recycle needs a
whole run of play and the first unfixed jams cut the line. A bot that plays for you, walking to every sputter, climbs
at a human's pace (14 against 13). **Residual risk, stated:** a pathing bot that plays around the clock climbs like a
tireless human. No cumulative metric can stop that; this one makes sure it is never faster than a human.

**Bounded.** The encoding needs `metric < 4.5 × 10^6` [T: meteor-drop-tycoon 9.1]. Bolts are a small integer: 11
after 6 hours [M4], and never more than 52 (section 10.2).

### 10.2 Storage

| thing | value | reason |
|---|---|---|
| Store | OrderedDataStore `ScraplineTycoon_Board_v1`, key `u_<userId>` | The standard [T]. |
| Value | `bolts × 2e9 + (2e9 − boltsAt)` | The standard's encoding. `boltsAt` is the profile's `os.time()` when that count was reached, so ties go to whoever reached it first. The level cap bounds bolts at 52: a line of twinned level-100 stations ships at most 7.85 × 10^9 items/s (its Shredder is the slowest station), and recycle 52 asks for 1500 × 1.35^51 ≈ 6.65 × 10^9 [R, computed]. 52 bolts encode to 1.06 × 10^11, far under 2^53 [R]. `boltsAt` stays under 2e9 until May 2033 [T]. |
| Write | right after each successful recycle, only if the value improves on what this server last wrote or read for that player | "Write only when the metric improves" [T]. Recycles come about every half hour [M4], so a coalescing window would buy nothing. |
| Seed of "last value" | one pcall'd `GetAsync` of the player's own key at join | A rejoin never writes a lower or equal value. |

### 10.3 The two views

Copy meteor-drop-tycoon's board server code **after its REVIEW-1** (A4: per-viewer round-robin friend reads,
generations, one `GetFriendsAsync` per viewer in flight [T]) and its `Board.luau`:

* **Public**: `GetSortedAsync(false, 10)`, cached server-side for 60 s and shared by every player on the server [T].
* **Friends**, fetched only when the player switches to it: `Players:GetFriendsAsync(userId)`, pcall'd, capped at
  the first 200 friend ids; each friend's score is one `GetAsync`, at most 1 per second per server, only while the
  `GetAsync` budget stays above a reserve of 10, cached 300 s server-wide; friends on the same server are read from
  memory. The view fills in as scores arrive ("Loading friends… 34 / 120"), and the viewer's own row is always there
  [T].
* **Empty friends view**: "None of your friends has a Gold Bolt yet. Your best: 2 ⚙. Invite someone: there are six
  factories on every server." If `GetFriendsAsync` fails or is missing (as in `robloxemu`): "Friends list unavailable
  right now. Showing your own row."
* **Names** come from `Players:GetNameFromUserIdAsync`, pcall'd and cached for the server's lifetime. **A name is
  never stored**, only user ids [T].

### 10.4 The physical board

Each plot's board stands 11.4 studs from its arrival pad, turned to face it (section 3; REVIEW-2 R1 made it 10 × 10
and moved it to the dock side so a phone can read it). The rows take 82 % of the face in 11 slots: the public top 10
and, under them, **the viewer's own row whenever it is not among them** (REVIEW-2 R2: the server always sent it, but
the board drew only the first 10 rows, so anyone outside the top 10, in either view, never saw themselves). Its rows render in a
**SurfaceGui in the owner's PlayerGui with `Adornee` set to their own board**, so each player's rows and friends list
reach only that player [T]. The **toggle is a ProximityPrompt the owner's client creates on its own board** ("Top
Recyclers: switch Public / Friends", `MaxActivationDistance` 13); pressing it fires `BoardView`, and the server
answers that viewer only. A visitor sees only the board's title plate and gets no prompt on someone else's board.

---

## 11. Data model

### 11.1 What persists: DataStore `ScraplineTycoon_v1`, key `u_<userId>`

```
{
  session   = string | nil,   -- owner token: one HttpService:GenerateGUID per server session (fork-tower REVIEW-4 §10)
  jobId     = string,         -- diagnostics only
  lockUntil = integer,        -- os.time(); renewed by every write
  data = {
    v        = 1,
    cash     = number >= 0,
    stations = {              -- STRING keys, one per station (checklist: integer keys)
      shredder  = { n = 0..2, L = 1..100, j = 0..n },   -- n machines built, level, machines jammed
      furnace   = { ... }, press = { ... }, cutter = { ... }, assembler = { ... }, rocketbay = { ... },
    },
    jamIn    = number 0..210, -- line-seconds to the next sputter (section 5)
    tier     = 0..6,          -- highest product shipped this run (the band; 6 = this run's rocket has launched)
    bolts    = integer >= 0,  -- Gold Bolts (the board's metric)
    boltsAt  = integer,       -- os.time() when `bolts` was reached (the board's tie-break); 0 while bolts = 0
    tutorial = 0..4,          -- section 15's hint step, so a rejoin resumes and never repeats
  },
}
```

* `Save.normalise` (pure, spec'd) makes a loaded record safe: a non-number gives the default; negatives give 0;
  `n`, `L`, `j`, `tier`, `tutorial` are clamped to their ranges and floored; NaN or infinity gives the default; a
  station whose predecessor is unbuilt is reset to `n = 0` (the unlock rule holds for any record); `jamIn` is
  clamped to 0..`JamMax`.
* **Clocks**: `os.time()` for everything persisted; `tick()` for in-session timers (the line tick, the jam clock,
  rate limits), because `tick()` is the clock `robloxemu` advances (deep-vein measured that `os.clock()` barely
  moves headless [T]).
* **Session lock with an owner token**: copy meteor-drop-tycoon's `Save` and server save code after its REVIEW-1
  [T]: the load is one `UpdateAsync` that takes the lock unless another live session holds it; `canSave` only while
  this session's token is on the record; every later write is an owner-checked `UpdateAsync` that cancels when the
  token is not ours; loads retried `LoadAttempts = 3` times, 1 s and 2 s apart; a locked record re-read every 5 s for
  up to 15 s at the join; a read-only session re-checks every 15 s and takes over only if the record is exactly what
  it read; writes serialised per session (`WriteQueueSeconds = 60`); a write landing after the leave began never
  re-locks the record. `GetDataStore` itself is pcall'd [T].
* **Non-saving session**: everything works in memory except **Recycle**, which is refused (section 9.2). A banner
  says "⚠ Progress is not being saved this session".

| number | value | reason |
|---|---|---|
| `FlushTickSeconds` | 7 | A purchase, a fix, a sputter turning into a jam and a tutorial step mark the profile pending; at most one write per player per tick [T]. 6 players × 60 / 7 = 51.4 `UpdateAsync` a minute at most, against a budget of 60 + 10 × 6 = 120 [R]. |
| `AutosaveSeconds` | 60 | Renews the lock and saves `cash`, which changes every tick and so does **not** mark the profile pending: a crash loses at most a minute of income, never a purchase [R]. |
| `LockSeconds` | 120 | Twice the autosave [T]. |

### 11.2 What is server-only (Lua tables in `Main.server.luau`)

The server's `Random.new()`; each line's live sputter (machine, seconds left) and jam clock; the shipped-item
accumulators behind `tier`; each player's `Trace` (trusted position, burst bank); pending-save flags, write queues and
session tokens; the `recycling` flag; remote rate-limit buckets; board caches (public rows, friend scores, names).

### 11.3 What lives in `ServerStorage` (anomaly-observatory's "ServerStorage, not the zone")

* `ServerStorage.MachineKit`: one model per machine type, the factory-grade materials and the rocket model. The
  server clones these; clients have no reason to hold them.
* `ServerStorage.PlotInfo.<userId>`: attributes `Plot`, `JamIn`, `TrustedX`, `TrustedZ`, `Cash`, `Income`, `Tier`,
  `RocketRate`. They exist **only** for the headless checks and tools, as anomaly's `PassInfo` does [T]. `JamIn` is
  future information, which is exactly why it is here and nowhere a client can read.

### 11.4 What replicates, and why it is safe

| replicates | why that is fine |
|---|---|
| Every plot Part: floor, belt, chute, dock, launch pad, wall and its grade paint, crane, arrival, board frame, owner sign | Nothing about a plot is secret. |
| Machine models with a level plate (SurfaceGui "Lv 23"), the twin when built, sputter sparks and jam smoke (emitters the server enables), a "⚠ JAMMED" billboard | Present state, visible by design. |
| `leaderstats.Cash` (a compact string, "1.2M"), `leaderstats.Bolts` | Public by design; the board shows bolts too. |
| `State` (server → owner only): cash, income/s, the flow by product, each station's n / L / j / load, the bottleneck, the ★ and any save countdown, `tier`, bolts, the recycle requirement and the current rocket rate, the live sputter (station, seconds left), `saving`, `tutorial` | The owner's own **present** state. The time and target of the next sputter are never in it. |
| `LineState` (server → all): per plot, its owner's user id and each station's n / L / j | Public facts (anyone can walk over and look), sent so every client can draw belt items on every line it sees. |
| `Board` rows (server → the viewer only) | That player's own view of public data and their own friends. |
| `Announce` (server → all): a plot's first-rocket lift-off and the server-wide toast | Text and a plot index, already public. |
| Shared modules in `ReplicatedStorage` (Config, Line, Economy, Jams, Recycle, Save, Board, EnvBands, Hazards, Rest, Trace, …) | Public code. Nothing is seeded from a public value, so the code predicts nothing (fork-tower REVIEW-4 [T]). The jam schedule is a server-lifetime `Random.new()`. |

**The attribute rule: no attribute on any Instance under `workspace` or `ReplicatedStorage`.** Instance names carry
only visible facts (`Plot_3`, `Station_Press`, `Machine_Press_b`). The headless check enumerates every attribute under
both and requires the list to be **empty** (meteor-drop-tycoon's strictest form of fork-tower's wire inventory [T]).

### 11.5 Remotes (`ReplicatedStorage.ScraplineRemotes`)

| remote | direction | validation |
|---|---|---|
| `State`, `Toast`, `Fx`, `Board` | server → one player | none |
| `LineState`, `Announce` | server → all | none; public facts only |
| `Buy(kind, station)` | client → server | `kind` ∈ {"build", "twin", "up"} and `station` ∈ {"shredder", "furnace", "press", "cutter", "assembler", "rocketbay"}, both strings. Refused, **each with a toast**: unknown kind or station ("That isn't a machine"); locked ("Build a Press first"); already twinned ("This station already has its twin"); at `MaxLevel` ("The Cutter is at its top level"); not affordable ("Need 1.2M, you have 800K"); profile loading ("Loading your factory…"); recycling ("Recycling… one moment"). |
| `Fix(station, machine)` | client → server | strings: a station id and "a" or "b". Refused with a toast: not sputtering or jammed ("That machine is running fine"); trusted position more than `FixRange` = 12 studs away ("Get closer to fix it"); recycling. |
| `Recycle()` | client → server | section 9.2 |
| `BoardView(mode)` | client → server | `mode` ∈ {"public", "friends"}; the reply goes to the caller only |

| number | value | reason |
|---|---|---|
| `Remotes.MaxPerSecond` | 8 per remote per player | Above deliberate tapping on a phone. Excess calls are dropped with at most one "Slow down" toast per 5 s [T: steal-a-cryptid]. |

**Every ProximityPrompt is created by the owner's client on its own plot**: the station prompts (they only open the
line panel at that station, locally), the Fix prompts on sputtering or jammed machines, and the board toggle. Nothing
replicates, a visitor never sees a prompt on someone else's plot, and every press that changes anything is one of
the validated remotes above.

---

## 12. Spawn and respawn (`robloxemu/SPAWN-ORDER.md`)

The engine's order, measured in Studio: `CharacterAdded` fires while the character is unparented at the origin; one
frame later the engine parents it **and places it on a SpawnLocation**, discarding any CFrame written in between [T].
The design uses SPAWN-ORDER's **preferred pattern: let the engine place you** (grow-a-crystal, nightwatch-manor and
meteor-drop-tycoon do this [T]):

1. **Each plot's arrival pad is a real, enabled `SpawnLocation`** (`Plot_k.Arrival`, 6 × 1 × 6, top at y = 1,
   `Duration = 0` so there is no force-field bubble, `Neutral = true`). All 6 exist from server start. The Scrap
   Market has none, and there are no others.
2. **`PlayerAdded` claims a free plot and sets `plr.RespawnLocation = Plot_k.Arrival` synchronously, before any
   yield** (before the DataStore load). The engine's own placement is then already correct. Until the profile loads
   the plot shows only the free Shredder's glowing pad, and Buy answers "Loading your factory…".
3. **Belt and braces in `CharacterAdded`**: wait for `char.Parent ~= nil`, bounded at 300 frames of
   `task.wait(1/60)`; then **re-read** the player's plot (it can change across the yield); if the root is more than
   8 studs (horizontal) from the plot's arrival, CFrame it 3 studs above the pad top [T]. `WaitForChild` is not the
   wait: on the server both children already exist when the event fires [T].
4. **The trusted position resets** to the arrival pad after placement: a point the server chose, never one the
   client supplied (vault-runners' rule [T]).
5. **Leaving** frees the plot for the next joiner and resets it to the bare yard AT ONCE, then saves (a live sputter
   as a jam). REVIEW-1 A1: freeing it only after the save returned kicked a joiner who arrived meanwhile on a full
   server. A rejoin to the same server waits for that save to land before it loads (REVIEW-1 A3).

Headless (section 17): every plot has exactly one enabled SpawnLocation and there are no others; after
`simulateSpawn`, each of two players stands on their **own** arrival pad (XZ within 4 studs, not on each other); the
same after a respawn; and with `RespawnLocation` deliberately cleared, step 3 still puts the player on their own pad.
The assertions are on XZ, not Y, as SPAWN-ORDER §7 advises [T].

---

## 13. Anti-exploit model

vault-runners' rule [T]: do not try to detect cheating; remove what cheating is worth, and bound what cannot be
removed.

| a client can… | what it would buy | denied or bounded by |
|---|---|---|
| Fire `Buy` with a bad kind or station, while broke, out of order, or in a flood | Free machines, server work | String whitelists, the unlock rule, a price check, the 8/s rate limit, a toast for every refusal, writes coalesced to one per 7 s. |
| Claim a root position that is not a number (±inf, NaN) for one tick | Fix from anywhere, for the rest of the life | **REVIEW-2 X2:** inf/inf = NaN made the trusted position NaN for good, and NaN passed the range check. The server skips any claim that is not finite before `Trace.step`, and the range check is fail-closed (`not (dist <= FixRange)`). Measured: four bad claims (x +inf, z −inf, NaN, y +inf) leave the trusted position at (0, −30) and Fix from the pad is refused (`check_scraplinetycoon_guard` 1). Whether Roblox replicates such a CFrame at all is a Studio question. |
| Fire `Recycle` at the limit while the store fails | Burn the server's DataStore write budget, so everyone's autosaves queue | **REVIEW-2 X3:** a failed recycle write holds the next try 10 s (`check_scraplinetycoon_guard` 2: 1 store call in 10 s of spam, was 80), and every held call gets a toast. |
| Leave, rejoin the same server, leave again while a slow leave-save is in flight | (an honest accident) a lost leave-save | **REVIEW-2 X1:** a load that waited for its own earlier leave returns without taking the owner token if its player left meanwhile, and only a loaded session registers as leaving. `check_scraplinetycoon_save` M: with every write taking 10 s, an upgrade bought before the first leave survives a second session that came and went and a third that joined meanwhile. |
| Teleport or speed-hack to a sputtering machine | Fix from anywhere | `Fix` reads the **trusted position**: the server's own copy of the character, moving toward the claimed root at no more than 16 × 1.35 = 21.6 studs/s with a 3 s burst bank (meteor-drop-tycoon's `Trace` [T]). The most it saves is the walk, about 1.5 s. The bot that walks at that cap gains 14 bolts in 8 h against a human's 13 [M5]. |
| Fix someone else's machine | Nothing they want | `Fix` acts only on the caller's own plot (the session knows it). |
| Read replicated state or remote traffic | Know the next sputter | Nothing to read: the jam clock and its `Random.new()` never leave the server, `State` carries only the present, and there are no attributes (the check enforces an empty list). |
| Run an anti-AFK jiggle, alone or with an auto-buy + auto-recycle macro | Income and bolts while away | Jams: an untended line earns 0.00-0.01 of a tended one after 30 minutes [M7], and both gain 0 bolts in 8 h, from join, from 35 minutes in, and from a Golden Factory [M5]. |
| Rejoin or server-hop to clear jams or restart the jam clock | A fresh, jam-free line | Jams and `jamIn` are saved; a live sputter is saved as a jam (section 5). |
| Recycle to clear jams | A fresh, jam-free line | It costs the whole run (cash and machines) for one bolt, needs the rocket rate first, and keeps the jam clock: the macro that recycles the moment it can still gains 0 bolts [M5]. |
| Server-hop or crash to duplicate | Two sessions writing one profile, or a bolt twice | The session lock with an owner token on every write; the recycle is one atomic, owner-checked write, and a non-saving session cannot recycle (section 9.2). |
| Manipulate time | Income while away | No offline accrual; only the server's `tick()` and `os.time()` are read. |
| Write the board | A fake rank | Only the server writes, from the saved profile's bolts and `boltsAt`. |
| Delete hazards or fake a rest | Avoid knocks | Client-only and grant nothing; the only thing avoided is a stumble. Rest does not touch the jam clock. |
| Abuse a hazard's knock | Fling onto something | Client-only, on the player's own character; lift capped at 15 studs/s and there is nothing to land on [T]. |
| Spam the board toggle | Starve other players' friend views | Per-viewer round-robin reads with generations (meteor-drop-tycoon REVIEW-1 A4 [T]). |
| Spam `BoardView` at the remote limit | Multiply the server's web calls (names, friend lists) until they fail for everyone | A failed name lookup is not retried for 60 s and one lookup per id is in flight; each viewer's friend list is fetched once per 5 min (a failed one once a minute). Measured in REVIEW-1 A2: 60 s of public-view spam with lookups failing costs 10 lookups (was 4 806); 60 s of Friends toggling costs 1 friend-list fetch (was 48 + 144 pages). |
| Run a bot that walks to every sputter, 24/7 | A board rank no part-time human can reach | **Not denied: bounded only at human speed** (REVIEW-1 A4). The metric cannot be inflated, but it is cumulative: a bot that follows the ★ and walks at the trusted-speed cap earns what a human who never stops earns (`tests/LineModel.luau`, seeds 1-3: bot 1 / 14 / 21 / 27 bolts after 1 / 8 / 24 / 72 h, the normal player 1 / 13 / 21 / 27). Growth slows (each bolt needs ×1.35 the rocket rate for +0.5 value), but a bot running for days will sit at the top of the public board. Only the macros that never walk to a sputter gain nothing. The friends view is the human comparison. Owner's call whether a per-period or best-run metric should replace it. |

---

## 14. Fair monetization

**v1 sells nothing.** No Game Passes, no Developer Products, no premium currency, no promo codes. Rules for any
later version, written down now so they are not negotiated feature by feature:
1. **No paid randomness, ever**: no crates, eggs, wheels or paid rerolls.
2. **No cash, speed, levels, twins, jam immunity or bolts for Robux**: each would scale the bounds in section 13 and
   the board.
3. **Cosmetics only**: belt and machine skins, item trails, wall decals, a launch-pad flag.
4. **Nothing rewarded for likes, favourites or follows**, and no store text that implies it.

---

## 15. The first 60 seconds

Measured with the section-3 geometry and the profiles [M6] (the model places the free Shredder at 3.0 s). The
headless first-minute walk (section 17) has to reproduce the checkable rows through the real server.

| t (s) | what happens | source |
|---|---|---|
| 0 | The character lands on its own arrival pad, facing up the U. Junk trickles out of the chute at 0.5/s, rides the belt and sells at the dock ("+$1"). The Shredder's pad glows. Hint 0: "Tap the glowing pad (or 🔧 Build) to build your free Shredder". The Junkyard sky, crows overhead. | sections 3, 4.2, 6 |
| about 3 | One tap: the Shredder drops onto its pad with a puff. Junk becomes scrap ("+$2"). Hint 1: "Your Shredder makes Scrap. Tap ⬆ on it ★ to speed it up". **The core action at about 3 s.** | [M6]; the HUD button needs no walk |
| 14.8 | The first purchase, a Shredder upgrade ($8), for the normal player (fast 8.5 s, slow 31.5 s). | [M6], median; p10 9.9, p90 23.0 |
| 30 | Income $3.12/s. | [M6] |
| 60 | 6 purchases made; income $7.63/s. | [M6] |
| after the first purchase | Hint 2, until the ★ moves to the Furnace: "Buy the ★ row in 🏭 Line: it is the best buy for your line right now" (**REVIEW-2 R4**: it used to say "Save for a Furnace" from the first purchase, while the ★ still pointed at Shredder upgrades and its twin: the walk saw the two disagree from 22 to 77 s). | section 4.5 |
| the minute before 156 | Once the Furnace is 60 s of income away (★ rule 0), the ★ moves to it and the HUD counts the seconds down ("Saving for the Furnace"). Hint 2 now: "Save for a Furnace ★: Ingots sell for more". | section 4.5 |
| 156 | The Furnace is built and the first Ingot ships: 🔥 THE FOUNDRY. | [M2]: 2.6 min, median |
| 240 | The first sputter (`FirstJamIn`). Hint 3: "⚠ A machine is sputtering! Walk to it and hold Fix". The tutorial ends after the first fix. | section 5 |

No step needs a purchase the player cannot afford, every refusal on the way says why, and the hints are the persisted
`tutorial` step, so a rejoin resumes rather than repeats.

---

## 16. Look and HUD from the first build

**Fx from day 1** (checklist §2). Server: `Fx.applyLighting(Fx.Presets.Junkyard)` as the first line. Signature
particles: sparks off the Shredder's teeth, embers from the Furnace mouth, steam from the Press; `Fx.attachGlow` on
the next station's pad (interactive things read as interactive); a gold glow on the launch pad. Client:
`FxClient.shake` + `flash` + `fovPunch` on the lift-off and the recycle, a small shake on a hazard hit.

**Belt items** (client-only, never replicated): each client draws items on the lines near it from `LineState` and
the public flow rule, so the line you see is the line the server computes. Items appear at the chute at
`min(intake, 2.5)` per second, ride at 10 studs/s, and take on the product each station gives the right share of
them (an overloaded station visibly lets some through unchanged). Your own line: at most 33 items at once (2.5/s ×
13.2 s [R]); each other line in view: at most 8. Every item is one Part: junk a dull random block, scrap small grey
chips, an ingot an orange-glowing bar, a plate a flat polished square, a gear a brass disc, a robot a light-blue
block with cyan eyes, a rocket a white cylinder. "+$" pops at your dock, at most 2 a second.

**Machines move** on your own plot only (client): the Shredder's rollers turn, the Press stamps, the Cutter's blue
laser (a Beam) flickers, the Assembler's arms swing, the Rocket Bay's dome lights pulse.

**Phone first** (checklist §2b; `Responsive.luau` copied verbatim):
* The root Frame owns the `UIScale`, sized `1/scale`.
* **Top centre**: cash in compact form with the income per second; under it the band chip (format: "🔥 Foundry ·
  next: 🏗️ ship a Plate"); under it the alert line (format: "⚠ Press sputtering: Fix 0:12", amber, never red); then
  toasts and the one-line hint. Lift-off, band and recycle cards are centred and transient.
* **Right edge, between 45 % and 70 % of the height**: "🏭 Line", "☕ Break", and "♻ Recycle" once the Rocket Bay is
  built (a progress ring until the rate is met, format: "rockets/s now / needed"). **Nothing tappable in the bottom-left or bottom-right** (the
  thumbstick and jump button). Tap targets at least 44 screen px: `ceil(46 / scale)` design px on touch [T].
* **The line panel** slides in from the right edge (`Responsive.sideWidth` / `fitHeight`, a `ScrollingFrame`): a
  summary line (what the line ships, per product per second), then six station rows in belt order, each with its
  icon, its level and twin (format: "Lv 23 ×2"), the load bar, 🐢 on the bottleneck, and its buttons (⬆ price, ＋Twin price, or Build price, or
  "🔒 Build a Press first"), the ★ on one of them. When it opens, the button column moves with its left edge, so no
  two panels overlap.
* **The next station is impossible to miss**: its pad glows in the yard, its row sits at the top of the panel's
  scroll with a "NEW" badge once the ★ saves for it, and the HUD shows the save countdown.
* The headless HUD check runs `hudcheck` at six viewports with **`overlap = true`** (rule 4b asserted), touch and
  desktop, and re-lays out on `ViewportSize` changes.
* **Colour carries meaning**: red means a hazard ring and nothing else. `EnvConfig.spec` runs meteor-drop-tycoon's
  `isReddish` test (r ≥ 180, g ≤ 110, b ≤ 110; the ring is 255,40,40) over every product, machine, grade, band,
  weather, critter, accent and alert colour [T]. Amber means a machine needs you; gold means rockets and bolts.

**Budgets, capped in code** (`Config.Budget`):

| budget | value | reason |
|---|---|---|
| `MaxLocalParts` (client) | 200 | +1 Jump's and meteor-drop-tycoon's value [T]. Belt items ≤ 33 + 5 × 8 = 73, scenery ≤ 60, critters ≤ 15, hazard 2, lift-off/recycle effects ≤ 20: 170 [R]. |
| `MaxEmitters` / `MaxEmitterRate` / `MaxWeatherEmitters` | 4 / 60 per s / 2 | [T]; machine effects on your own plot share the 4. |
| `MaxBeams` / `MaxTrails` / `MaxLights` / `MaxHazards` | 8 / 8 / 3 / 1 | [T] |
| `MaxServerParts` | 640 | Per plot: 40 static (floor, 4 curbs, 8 belt pieces, chute 4, dock 3, launch pad 2, wall, 2 chimneys, sign, crane 4, arrival, board 3, 6 station pads) + 12 machines × at most 5 Parts = 100; × 6 = 600, + the Scrap Market's 20 + the Baseplate = 621, asserted ≤ 640 headless [R]. |
| `MaxServerLights` | 12 | One on each chute and each dock; machines glow with Neon [R]. |
| Server emitters | 2 per machine (sputter sparks, jam smoke), off unless that machine is in trouble | At most one sputter per plot at a time (section 5). |

---

## 17. Build plan: tests first

**Files** (checklist §1 scaffold; deep-vein's layout):

```
scrapline-tycoon/
  default.project.json       src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  src/shared/Config.luau     every tunable in this spec, one block each (World, Plot, Products, Stations, Line, Star,
                             Jams, Recycle, Grades, Env, Hazards, Rest, Trace, Save, Board, Remotes, Budget, Tutorial, Pacing)
  src/shared/Line.luau       speed, capacity, intake, flow, income, bottleneck, load (pure)
  src/shared/Economy.luau    prices, candidates, canBuy/apply (every check before the first assignment), star (pure)
  src/shared/Jams.luau       the jam scheduler: one sputter at a time, target choice, sputter -> jam, fix, save/load (pure; rand injected)
  src/shared/Recycle.luau    requirement, canRecycle, apply (all-or-nothing), grade of a bolt count (pure)
  src/shared/Save.luau       defaults, normalise (pure)
  src/shared/Board.luau      meteor-drop-tycoon's, with the metric renamed
  src/shared/EnvBands.luau   plus1-jump, verbatim
  src/shared/Hazards.luau    meteor-drop-tycoon's copy (plus1-jump + the marked DEEP VEIN ADAPTATION), verbatim
  src/shared/Rest.luau       plus1-jump, verbatim
  src/shared/Trace.luau      meteor-drop-tycoon's copy (vault-runners + its marked flat-plot ADAPTATION, three spots), verbatim
  src/shared/Fx.luau         + Presets.Junkyard (the only change); FxClient.luau, Responsive.luau verbatim
  src/shared/YardArt.luau    client art: bands, critters, weather, hazard models, belt items, machine animation
  src/server/Main.server.luau
  src/client/Hud.client.luau  (HUD, line panel, board SurfaceGui, local prompts)   src/client/Yard.client.luau (bands, hazards, rest, items)
  tests/*.spec.luau          tests/LineModel.luau (design/model.py's simulate, ported, reading Config)
  README.md (store text, section 21)  CLAUDE.md  EYECANDY.md  MARKETING.md  .gitignore (publish_*.bat, publish_*.sh, *.rbxl*)
```

No `Rng.luau`: nothing is seeded. Every draw is the server's `Random.new()`; pure modules take `rand: () -> number`,
and specs supply their own deterministic LCG [T: meteor-drop-tycoon]. Shared modules take their dependencies as
arguments: `require("./X")` resolves in the luau CLI and is invalid in Roblox.

**Unit specs, each written and watched failing before its module:**
* `Line.spec`: the flow table of section 4.2 for hand-worked lines (a jammed twin halves a station; overflow sells
  as what it is; the trickle with no Shredder and with a jammed Shredder); the bottleneck; every number in [M1].
* `Economy.spec`: every price; the unlock rule; twin and level refusals; the ★'s three rules, including "save for the
  next station within 60 s" and "a filler only if its payback beats the wait".
* `Jams.spec`: 240 s to the first sputter of a new profile; 150-210 s between; never two sputters; the clock stops
  while one is live; a sputter becomes a jam after exactly 15 s; a fix in time is "saved"; save/load keeps jams and
  `jamIn`; a live sputter saves as a jam; a recycle clears jams and keeps `jamIn`.
* `Recycle.spec`: the requirement `1500 × 1.35^bolts`; refused below it with jams counted; `apply` changes nothing
  when refused and exactly the section 9.2 fields when allowed; grades 0-4.
* `Save.spec`: normalise, clamps, string keys only, the unlock-rule repair.
* `Board.spec`: meteor-drop-tycoon's, with bolts.
* `EnvConfig.spec`: the bands validate; every band defines every lighting field; `ClockTime` rising and below 24;
  band 1 has no hazards; every hazard kind is used and validates; `fall ≤ commit` for each; rings leavable in 0.3 s;
  `PendingSeconds` ≥ the longest flight + 2; `isReddish` over every non-hazard colour; `Fx.Presets.Junkyard` equals
  band 1.
* The copied `EnvBands`, `Hazards`, `Rest`, `Responsive` and `Trace` specs, unchanged.
* `Pacing.spec`, running `LineModel` from Config: the normal, fast and slow players' first Rocket in 30-45 min; the
  mixed player's in 30-45; every first-run band lasts at least 2 min; the Golden Factory at least 3× the brag and
  under 3 h; the auto-buy macro and the jiggle gain 0 bolts in 8 h; the bot gains at most 1.1× the normal player.

**Headless gates** (`robloxemu`; rebuild with `py -3 wrap.py --game ../scrapline-tycoon --out
build/scrapline-tycoon.luau` before every run):
* `check_scraplinetycoon.luau`, **the real player path**: 6 plots exist and are parented; each has exactly one
  enabled SpawnLocation; spawn on your own pad (section 12); junk trickles and sells; `Buy` builds nothing before the
  load, then the free Shredder; scrap sells; upgrades, a Furnace, a twin, each moving `State`, the machine models and
  leaderstats; a sputter appears at 240 s of line time, is fixed by walking the character there, and a second one
  left alone becomes a jam that items visibly pass; every refusal answers with a toast; the empty attribute
  inventory; server parts ≤ 640; rejoin restores every saved field, jams included.
* `_save`: two sessions on one profile (the second is non-saving and cannot recycle); a late releasing write
  cancelled by the owner token; a recycle with the DataStore failing (nothing changes, a toast, then it works after
  recovery); a sputter at leave comes back as a jam.
* `_recycle`: a seeded profile one level short of the requirement is refused with the rate in the toast; one upgrade
  later the recycle wipes and keeps exactly the right fields, the grade repaints, the board value is written once.
* `_jams`: `Fix` from 30 studs refused, from 10 accepted; a teleported claim does not move the trusted position
  faster than 21.6 studs/s; `Fix` on another plot refused.
* `_sky`: every band and every seam, budgets asserted each frame; weather capped; a band change glides (no Lighting
  write above its share); the recycle snap happens under the flash; `Yard.client` fires no remote and writes
  nothing the server built.
* `_hazards`: only on your own plot, grounded, not resting, not during a sputter (a standing jam does not hold them since REVIEW-2 R5), the lift-off or the
  recycle; the drawn ring equals the zone; walking out of it in 8 directions always dodges; resting freezes the clock.
* `_hud`: `hudcheck` at six viewports with `overlap = true`, touch and desktop.
* `_board`: writes only on improvement, the encoding, public rows, the friends view falling back cleanly where
  `GetFriendsAsync` is missing.

Every new assertion is mutation-tested with a control (the standard §4).

---

## 18. Cut from v1

| cut | why |
|---|---|
| Free placement, moving machines, branching recipes, splitters, mergers, second belts | One right answer in a recipe chain; a chore, not a decision; and the hardest UI on a phone (section 2). |
| A separate chute track | It made single upgrades worthless in a balanced line (section 22, item 1). |
| Selling machines | Stations are fixed and only grow, so there is nothing to undo. |
| Buy ×10 / buy max | 137 single taps over 34 minutes is one every 15 s [M2]; worth adding only if play shows tapping fatigue. |
| Offline earnings | A clock-delta trust surface, and it would grow the board with nobody playing. |
| Co-op: fixing a friend's jams, visiting help, trading, PvP | Each needs its own trust rules (whose trusted position, whose income). |
| Orders and contracts, product quality grades | A second economy on top of the line; v1 keeps one number per station. |
| Grades beyond Gold | The board carries the long tail. |
| Promo codes, badges, daily rewards, streaks | Each is a one-time-grant or dashboard surface outside the core loop; badges also need the Creator Dashboard. |
| Sound and music | Needs asset ids (section 19 lists it as optional night-shift work). |
| Custom meshes, textures, skyboxes | v1 is code-only Parts, as the checklist expects. |
| Any Robux item | Section 14. |

---

## 19. Needs Studio (and needs a live server)

Only real rendering, real input or a published server can settle these. This list moves into `EYECANDY.md` when the
game is built.

1. **Every band's look**: exposure, ambient and bloom per band; whether the line and items read at night (Robot
   Works, Launch Site); the dusty Junkyard haze not washing out the HUD's view of the line.
2. **Stars at `ClockTime` 20.5** (Robot Works): do 1 500 stars show, or only later?
3. **Atmosphere vs fog**: Roblox ignores fog while an Atmosphere exists; density 0.08 at the Launch Site.
4. **Distant scenery on a phone**: chimneys, girders, far gears, the gantry and the moon may be culled at low graphics
   quality. If so: closer and smaller.
5. **Beams**: the Cutter's laser, the searchlights and the lift-off trail almost certainly need hand tuning.
6. **Belt items**: does a client-drawn item stream look continuous at 10 studs/s, and does the share of items that
   ride past an overloaded station read as "this station is too slow"?
7. **Machine silhouettes**: can a player tell the six machines apart at 20-45 studs on a phone, and the twin from
   the first machine?
8. **The sputter**: is 15 s with sparks, the amber alert and an off-screen pointer enough to notice while the line
   panel is open?
9. **Client-created ProximityPrompts** (station, Fix, board): do they show, hold and trigger on touch exactly as
   server ones do, and does the 0.5 s Fix hold feel right?
10. **The knock**: does `PlatformStand` plus `AssemblyLinearVelocity` push a humanoid on flat ground and release
    cleanly? Deep-vein, +1 Jump and meteor-drop-tycoon have the same open item.
11. **The crane telegraph**: does the trolley moving over you plus the ring read as "move", in the bright Junkyard
    light as well as at night?
12. **☕ Break's sit and camera drift**: `Humanoid.Sit` with no seat, from the client (+1 Jump's item 11); does the
    drift along the line feel good and release on the first move?
13. **Top-centre HUD on a notched phone**: safe area, emoji in `TextScaled` labels, the band chip's length.
14. **The board's SurfaceGui** in PlayerGui with `Adornee`: legible on a phone (REVIEW-2 R1 sized it by geometry: 10.1 px a row read from 5 studs at the default camera, 7.8 px from the pad); only the owner
    sees their rows.
15. **Frame time** on a mid/low phone with six full lines (up to 33 + 5 × 8 items) and the Robot Works rain.
16. **The lift-off** (smoke, flame, trail, shake, server toast): celebratory, not annoying; seen from other plots.
17. **The recycle sequence**: the crumble, the flash hiding the sky's jump back to midday, the repaint.
18. **`Players.MaxPlayers = 6`** in Game Settings; `SpawnLocation.Duration = 0` really removes the force field.
19. **Other players see a knock with nothing hitting** (client-only hazards). Does it look like a glitch?
20. **Live server only**: the friends board against real `GetFriendsAsync` pages and DataStore throttling;
    `GetSortedAsync` caching across real servers; a recycle with a real `UpdateAsync` failure.
21. **Optional, if assets are chosen**: a shredder crunch, a furnace roar, a sputter alarm, a lift-off rumble.
    Library audio ids only.

---

## 20. Planned thumbnail shots and clips

These seed `EYECANDY.md` (thumbnails, 1920 × 1080) and `MARKETING.md` (clips, 7-15 s, vertical 1080 × 1920, for
`tools/film_game.py`). A Studio session sets up each shot through a copy of Config in the place only, never `src/`,
the way +1 Jump's shot list does [T].

**Thumbnails**
1. **"Lift-off"** (Launch Site): camera low at the front-right of a plot; the first rocket a few studs above the pad
   on a flame and smoke column, the avatar beside the dock looking up, the whole U line lit under the stars and the
   gantry behind.
2. **"The line"** (Robot Works): high three-quarter view of a full U with six twinned stations, items of every
   product on the belt, neon signs, the crane overhead, rain streaks.
3. **"Jam!"** (Machine Shop): close on a smoking Assembler with its "⚠ JAMMED" sign, the avatar running to it, the
   items behind it passing as gears.
4. **"Close call"** (Foundry): a scrap bale one frame before impact under the crane magnet, the red ring on the
   ground, the avatar one step outside it.
5. **"Six factories"**: a wide shot from above the Scrap Market, six plots at different stages and grades (REVIEW-2 R8: the sky is the camera player's own band, so every plot is seen under one sky; what differs is the lines' length, the SCRAPLINE signs' accents and the paint), one of them
   gold.

**Clips** (how to stage each)
1. *First build* (8 s): a fresh profile; junk trickles; tap the glowing pad; the Shredder drops in; "+$2" pops.
2. *Bottleneck* (10 s): a profile with the 🐢 on the Press and 4 380 cash; open the line panel, buy the Press twin; the
   twin slides in, the load bar drops under 100 %, income ticks up.
3. *Sky change* (12 s): a profile in Press Works with 130 000 cash (the Cutter's price); build the Cutter; its first
   Gear ships and Press Works' late afternoon glides into the Machine Shop's sunset; the title card.
4. *Saved it!* (10 s): a sputter warning; run along the U; hold Fix; "Saved it!".
5. *Dodge* (10 s): hazards every 8-10 s in the place's Config copy; the trolley tracks, the ring turns red, step out,
   the bale thuds.
6. *Lift-off* (15 s): a profile with the Assembler running and 9.5M cash; build the Rocket Bay; the first rocket rides
   to the dock, onto the pad, and launches; the server toast.
7. *Recycle* (12 s): a ready line at 1.5K rockets/s; press Recycle and confirm; the crane sweeps, the machines
   crumble, the flash, the yard comes back painted yellow, a Gold Bolt spins into the HUD.
8. *Coffee break* (10 s): press ☕ Break in Robot Works; the avatar sits, the camera drifts along the neon line in
   the rain.

---

## 21. Store text (for `README.md`; 964 characters counted with Python, limit 1000, no coloured-square emoji)

```
🏭 Junk goes in. Rockets come out.

Build a production line on a conveyor belt: a Shredder, a Furnace, a Press, a Cutter, an Assembler and a Rocket Bay. Each machine turns what reaches it into something worth more: junk, scrap, ingots, plates, gears, robots, rockets.

Find your slowest machine and fix it: upgrade it, or build its twin. A sputtering machine needs a quick fix before it jams.

Your factory changes as it grows, from a dusty junkyard to a foundry, a machine shop, a neon robot works and a launch site under the stars. Now and then the crane drops something. A red ring shows exactly where it lands: step out of the ring and it misses.

Need a break? Press Break and watch your line run. Nothing falls on you while you rest.

Launch your first rocket, then Recycle your factory for a Gold Bolt: each bolt makes everything you ship worth more, forever. Climb the Top Recyclers board against everyone, or just your friends.

Nothing to buy. Just build.
```

---

## 22. Self-review

Checked against the task and `docs/complete-game-standard.md`, one line each:

* **Core loop in one paragraph**: section 1. **Every number with a reason**: each carries a tag or a worked reason;
  the player profiles are the only assumptions, and they are labelled.
* **Reachable from join**: section 15's first minute, and the real-player-path gate in section 17.
* **Spawn per SPAWN-ORDER**: section 12 (RespawnLocation before any yield, plus a bounded wait-and-correct).
* **Server-authoritative, nothing secret replicates**: 11.2-11.5, the empty attribute inventory, the jam clock in
  ServerStorage, no seeded generation.
* **DataStore**: pcall everywhere, `canSave` only while holding the lock, an owner token on every write, string keys,
  and the one irreversible action (Recycle) inside one atomic owner-checked `UpdateAsync`, refused when not saving.
* **No silent no-ops**: every refusal in 9.2 and 11.5 names its toast.
* **Bands**: six, each with its own light, colour, scenery, critters and weather, triggered by the product your line
  ships, glided (section 6).
* **Hazards**: rare (one per 2.6 min measured), telegraphed, the red ring is exactly the zone, one at a time, a hit
  costs a stumble (section 7).
* **Rest**: never an exploit (section 8).
* **Brag at 33.9 min** in the 30-45 window; **long-term goal at 129.9 min** (section 9).
* **Board**: public + friends, a metric a script cannot inflate with its residual stated, the standard's encoding,
  physical, with a prompt, cached names and a useful empty view (section 10).
* **Phone first**: section 16, with hudcheck `overlap = true`.
* **Needs-Studio list**: section 19. **Thumbnail shots and clip list**: section 20. **Store text**: section 21.
* **Fair monetization**: section 14. **Cut list**: section 18.

Consistency checks made while writing:
* The constants in `design/model.py` (md5 `dbc4110d05cf352490a2878ddf27bec9`) equal every value stated here. Two
  full runs gave the same `model.out.txt`, md5 `8ff877594560ac445a6929f630a8105a`; one run takes about 6 minutes.
* Band entry tiers 0/2/3/4/5/6 with fade 0 satisfy `EnvBands.validate` (first band at 0, strictly rising, fade ≤ gap).
* Every hazard kind's `fall ≤ commit`; `PendingSeconds` 7 ≥ 4.6 + 2.
* The board (11.4 studs from the arrival since REVIEW-2 R1) is inside its 13-stud prompt reach; the launch pad (26.1) is in view; the
  U-turn's outer edge (z = 35) stops a stud short of the back wall (z = 36).
* The model's station coordinates are section 3's; moving them all by the same offset changed no output (the second
  of the two final runs used the final coordinates, the first the previous ones, and their outputs are identical).
* Server parts ≤ 621, asserted ≤ 640.
* Store text 964 characters.
* `Rest.luau` and `EnvBands.luau` in meteor-drop-tycoon are byte-identical to plus1-jump's (`cmp`), so either copy
  is the template.

Contradictions and dead ends found while the model was built, so a reader sees why the rules are as they are. Items
1-4 and the first half of 5 were measured by earlier revisions of `design/model.py`, which the current file no
longer contains; the rest is in `model.out.txt`.
1. **A separate chute track and flat upgrade prices**: in a balanced line every single purchase added almost nothing.
   With free placement on ten pads the run never reached a Rocket in 60 minutes; with fixed stations and the chute
   still separate, the normal player once waited 14.7 minutes between two purchases and reached the Rocket at 56.3.
2. **Slow new stations** (each 0.4-1 item/s at level 1): deep stations could never catch up with the chute; the
   Cutter sat at 2.4 items/s against 33 junk/s.
3. **Upgrade prices growing ×1.25 per level**: levels ran into the cap of 60 by minute 30 and income reached about
   470 000/s; ×1.5 keeps the normal player's highest station at level 30 at the first Rocket [M2].
4. **A payout of `floor(sqrt(rockets / 1000))` bolts per recycle**: inside a 6-hour run the fast profile reached 17
   recycles, 4 281 bolts and a ×1 071 multiplier, with every station at the level cap. Replaced by one bolt per
   recycle behind a rising rate.
5. **A ★ without rule 0**: the `saver` profile never reaches a Robot in 90 minutes [M2]. With an earlier price set, a
   ★ without the save window made the fast player slower than the normal one (34.2 against 31.6 min) by spending just
   before each station; with the final prices, dropping the window costs the normal player 6.7 minutes (40.6 against
   33.9) [M8].
6. **The first recycle at 500 rockets/s**: it came 2 minutes after the first rocket and cut the Launch Site band to
   nothing in run 1; 1 500/s gives it 9.7 minutes [M4].

What this spec does **not** know: whether any of it looks or feels good (section 19), and whether the normal profile
is anything like a real player. Replace `Config.Pacing.Profiles.normal` with telemetry first, then re-run
`Pacing.spec`.

## 23. Re-checking the numbers

```
cd D:\Claude\Roblox\scrapline-tycoon
py -3 design/model.py > design/model.out.txt        # about 6 minutes; parts can be run alone: py -3 design/model.py 2 4
```
Part map: M1 economy tables, M2 first-run pacing per profile, M3 band durations, M4 recycles over 6 h, M5 AFK,
macros and bots over 8 h, M6 the first 60 seconds, M7 what jams cost an untended line, M8 sensitivity of the first
Rocket.
