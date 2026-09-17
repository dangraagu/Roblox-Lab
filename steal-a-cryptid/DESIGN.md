# Steal a Cryptid - v1 design spec

Design only. No game code exists yet. Written 2026-09-16 from game-radar 2026-09-14 section 3
("Steal a Cryptid!"), that file's "What players want" and "Avoid solo" sections, and this repo's
hard-won lessons: `docs/new-game-checklist.md`, `robloxemu/SPAWN-ORDER.md`, `fork-tower/STUDIO.md`,
`fork-tower/REVIEW-3.md`, `anomaly-observatory/CLAUDE.md` ("ServerStorage, not the zone"),
`vault-runners/CLAUDE.md` (the trusted-position model) and `deep-vein/` as the layout template.

**Where the numbers come from.** Every tunable below has a stated reason. Every *derived* claim
(how long a raid takes, how often a poacher is caught, when a player reaches a tier) comes from a
measurement run on 2026-09-16 against a Python model of exactly the rules in this document -
throwaway scripts in the session scratchpad, described in section 17. They are a model of the
rules, not the game: the build phase must port the generator, solver and economy checks into
`tests/*.spec.luau` and re-measure against the real modules before any number here is quoted as a
property of the game.

---

## 1. The core loop

You own a moonlit Lair on a shared forest road. You buy cryptids you can see - never a mystery
roll - from three Sighting pedestals outside your gate; each one sits in a cage and fills an
Essence jar every second, online or off, until you step on your Collect Pad. From the Hunt Board you
enter a Rival Camp: a lair built from a fresh seed in a private pocket of the same server, fenced
into lines whose gaps are guarded by timed laser nets, with snares between. You walk in, hold to grab a caged
cryptid, carry it back out through the same gaps at a slower pace, and if you reach the gate it is
yours; a laser or snare sends you home empty-handed and the permit is gone. Back home you place your
own lasers and snares, because every few minutes an NPC poacher walks your yard toward your fullest
jar, and your traps catch it for a bounty or it leaves with half that jar. Better cryptids unlock
harder camps, harder camps hold better cryptids, and nothing in the loop ever puts two live players
against each other or costs Robux.

---

## 2. What v1 changes from the brief, and why

| Brief says | v1 does | Why |
|---|---|---|
| Sighting Crates hatch random tiers | Three pedestals show the exact species, tier, rate and price before you pay; a free re-roll has a cooldown | No paid randomness anywhere. The radar's own wedge is the backlash against gambling mechanics; the cleanest answer is to have none. |
| Raid = teleport to a reserved server replaying another player's DataStore snapshot | Raid = a pocket built in the same server from a procedurally generated **Rival Camp** | A new game has near-zero CCU, so a raid layer that needs other players' snapshots has no targets on day one. `TeleportService` is not modelled by `robloxemu`, and Roblox does not perform teleports from a Studio play session, so a teleport-based raid could not be tested anywhere before publishing. The camp uses the same layout type a player lair uses, so real-player targets are a v1.1 source swap, not a rewrite (section 16). |
| Traps, alarms, cameras, turrets | Two trap kinds: Laser Net (timed) and Snare (static) | Two kinds already give a timing puzzle (lasers) and a routing puzzle (snares). Each extra kind is a renderer, a rule, a solver case and a visual Studio check. |
| 12-15 cryptids incl. Skinwalker | 8 species across 4 tiers; Skinwalker dropped | Skinwalkers come from living Navajo belief, not tall-tale folklore; turning one into a collectible is a cultural-respect problem the game does not need. Hodag and Jackalope (American tall tales) replace it. Eight species built from four procedural body plans is a set that can be built well. |
| Two currencies (Cryptid Coins, Fear Essence) | One: Fear Essence ("Essence") | With no Robux currency in v1, a second soft currency is bookkeeping with no decision behind it. |
| Prestige into Forest/Swamp/Arctic/Urban biomes | One biome (Pine Hollow), no rebirth | Cut, listed in section 16. |
| Store text: "15+ cryptids", "every like = bonus Fear Essence", "new biomes weekly" | Store text must say 8 cryptids, one biome, and must not promise anything for likes | v1 grants nothing for likes and has one biome. A reward or content the game does not give is a false claim, and trading rewards for likes is engagement bait this game does not want. |

---

## 3. The world

One server holds a road, one plot per player, and one raid pocket per player. All coordinates are
recycled by index (checklist trap "Unbounded coordinates").

**Plot-local frame.** Origin at the road-side front-left corner of the plot, +x across the plot,
+z away from the road, y = 0 at floor top.

```
z 96 +---------------------------------------+  back fence
     | C  C  C  C  C  C  C  C  C |  row 9  cages (slot order by column 5,4,6,3,7,2,8,1,9)
z 88 |...................................... |  row 8  cage walk - never a trap, rock or fence
     |  yard rows 1..8, 9 columns x 8 studs  |
     |  player lairs: fence lines at rows 3 and 6, three gaps each
z 24 +----------------+ gate +---------------+  front fence, gap at column 5 (x 32..40)
     |                | row0 |               |  row 0: the gate approach, kept clear
z 16 +---------------------------------------+
     |  P3(6,8)  P2(16,8)  P1(26,8)  *(36,8)  Pad(48,8)  Board(62,8)  |  apron
z 0  +---------------------------------------+  road edge
                                  * = arrival marker
```

| Name | Value | Reason |
|---|---|---|
| `World.CellSize` | 8 studs | A laser area is the cell inset by 1 stud (6 x 6). At 16 studs/s crossing it takes 0.375 s, long enough to see; a 4-stud cell (a 2-stud area after the inset) would make it 0.125 s. 12 studs would make the 9-column lair 108 studs, past the 96-stud plot pitch. |
| `World.YardCols` x `YardRows` | 9 x 8 | Odd column count gives a centre gate column. 9 columns fit three gaps per fence line at least 2 columns apart. 8 rows fit the hardest camp's three fence lines (rows 2, 4, 6) with a free row between each, plus the entry row and the cage walk. |
| `World.CageRow` | row 9, max 9 cages, unlocked centre-out: columns 5, 4, 6, 3, 7, 2, 8, 1, 9 | One cage per column; every cage is grabbed from the cell in front of it on row 8. Centre-out keeps a small lair symmetric behind its gate instead of lopsided. |
| `World.FenceHeight`, `RockHeight` | 10 studs | Above the measured Studio `JumpHeight` of 7.2 (fork-tower/STUDIO.md), with 2.8 studs margin. Anything a player can jump over physically but the server treats as a wall would desync an honest player. |
| `World.ApronDepth` | 16 studs | Room for pedestals, pad and board in front of row 0 without putting any of them in the gate approach. |
| Apron positions | P1 (26,8), P2 (16,8), P3 (6,8), arrival (36,8), Collect Pad (48,8), Hunt Board (62,8) | Arrival to P1 is 10 studs = 0.625 s at 16 studs/s, so the first action is inside the checklist's 5 seconds with room to read. Pad 12 studs (0.75 s), board 26 studs (1.625 s). |
| `World.PlotPitch` | 96 studs | 72-stud lair plus 24 studs between neighbours; plot depth is also 96 (16 apron + 80 grid). |
| `World.RoadWidth` | 32 studs | Two plot rows face each other across it; wide enough that neighbours' aprons do not touch. |
| `World.Plots` | 8 | Eight lairs plus eight simultaneous pockets is what keeps the server inside the part budget below (the only Studio-measured part count in this repo). Plot count is `max(World.Plots, Players.MaxPlayers)`, the fork-tower rule: a Studio slider must never seat more players than there are plots. Plot `i` goes to column `floor(i/2)`, side `i % 2`, gates facing the road. |
| Place setting `MaxPlayers` | 8 | Matches `World.Plots` so live servers never build spare plots. (The emulator defaults to 12 and so builds 12; checks must compute the expected count from both inputs.) |
| `World.PocketOriginX`, `PocketPitch` | 4000, 128 studs | Pocket slot `s` is built at x = 4000 + 128 s: far outside the road's fog, under 10 000 studs so float precision is a non-issue, and 128 > 96 so neighbouring pockets never touch. |
| Pocket shape | grid rows 0-9 only; row 0 is an antechamber walled on its three outer sides, whose only opening is the gate; no apron, no SpawnLocation | The raider starts somewhere no trap can reach and cannot wander off the pocket floor. A pocket has no reason to be a spawn. |
| `World.TrailheadSize` | 12 x 1 x 12 at world (0, 0.5, 0) | The one enabled SpawnLocation (section 9). |

Part budget, asserted headless by walking the workspace: **at most 300 BaseParts per lair and 200 per
pocket, and at most 100 for the road and Trailhead.** 8 x 300 + 8 x 200 + 100 = 4 100, inside the only part count this repo
has measured in Studio (fork-tower: 4 110 parts, draw batches unchanged). This is why a procedural
cryptid model is capped at `Cryptids.MaxParts = 14`: twelve models (9 caged + 3 on pedestals) are
the bulk of a lair.

---

## 4. Cryptids and the economy

### Species

A cryptid's price is its rate times its tier's payback time, so a species cannot be priced out of
line with its own income.

| Species | Tier | Body plan | Rate (Essence/s) | Price |
|---|---|---|---:|---:|
| Jackalope | Common | quadruped, small, antlers | 1 | 30 |
| Hodag | Common | quadruped, horns, spine ridge | 2 | 60 |
| Chupacabra | Common | quadruped, back spines | 3 | 90 |
| Dogman | Rare | biped, canine head | 12 | 3 600 |
| Jersey Devil | Rare | winged biped, bat wings | 18 | 5 400 |
| Mothman | Legendary | winged biped, red eyes | 70 | 168 000 |
| Nessie | Legendary | serpent, humps (cage is a tank) | 100 | 240 000 |
| Bigfoot | Mythic | biped, large | 450 | 6 480 000 |

Rates reason: within a tier species differ by 1.5-3x so the pedestal draw is a real choice, and the
best of a tier always earns less than the worst of the next (3 < 12, 18 < 70, 100 < 450, checked in
the model), so moving up a tier is never a sidegrade.

### Economy numbers

| Name | Value | Reason |
|---|---|---|
| `Economy.Payback` | Common 30 s, Rare 300 s, Legendary 2 400 s, Mythic 14 400 s | Chosen by measurement (section 4, pacing). The first curve tried (30/180/900/3 600) let an idle-only player fill a lair with Mythics in 205-209 simulated minutes, which is a v1 with no endgame once rebirth is cut. This curve measures 770-811 minutes idle-only. |
| `Economy.StartEssence` | 30 | Exactly one Jackalope, so the first action is a purchase the player can already afford (checklist: give the starting resource). |
| `Economy.StartCages` / `MaxCages` | 3 / 9 | Three: room for the first purchase, the first steal and one more before the first upgrade decision. Nine: one per column. |
| `Economy.ExpansionPrice` | cage 4: 150, 5: 1 500, 6: 15 000, 7: 150 000, 8: 1 500 000, 9: 6 000 000 | Each costs about one cryptid of the tier the player is buying when their cages fill: 150 = 2.5 Hodags, 15 000 = 3-4 Rares, 1 500 000 = 6-9 Legendaries, 6 000 000 = most of one Bigfoot. The last step is x4, not x10, so the ninth cage is not a wall in front of the first Mythic. |
| `Economy.SellFraction` | 0.5 | Releasing a cryptid returns half its price. Buying then releasing always loses, so the cage limit is a real upgrade decision, and a stolen-then-released cryptid is worth at most half a steal (the anti-farm bound in section 5). |
| `Economy.JarHours` | 8 | A jar holds 8 hours of its cryptid's rate, one night's sleep. The cap also bounds the worst a timestamp defect can mint: one jar per cage. |
| `Economy.IncomeTickSeconds` | 1 | Jars and their billboards update once a second; finer than that is replication spent on digits nobody reads. |
| `Economy.CollectDebounceSeconds` | 0.5 | A pad touch fires repeatedly while standing on it; one collect per half second is one per step. |
| `Economy.ReleaseHoldSeconds` | 1.0 | Release is irreversible and costs half the price, so it is a hold, not a tap. |
| `Economy.BuyTweenSeconds` | 2 | The bought cryptid walks from its pedestal to its cage, so the purchase is visibly delivered. |
| `Offers.Pedestals` | P1 Common; P2 tier max(1, rank); P3 tier min(4, rank + 1); the species is drawn uniformly within the tier | `rank` is the highest tier in the Journal (ever owned, never current; 0 before the first cryptid). P1 is always cheap (30-90), P2 matches the player, P3 is the next goal. There is always an offer one tier up, so offers never starve progression. |
| `Offers.TutorialFirst` | P1 is a Jackalope while the tutorial step is 0 | Guarantees the first purchase equals `StartEssence`. The purchase itself advances the step, so no separate flag is saved. |
| `Offers.Refill` | a bought pedestal draws a new offer by its rule when the bought cryptid reaches its cage (`BuyTweenSeconds`); when `rank` rises, P2 and P3 redraw at once | An empty pedestal is never left standing, and a rank-up immediately shows the next tier's goal. |
| `Offers.RerollCooldownSeconds` | 30 | Re-rolling is free. The cooldown keeps it a choice ("show me other sightings") rather than a lever to pull until a species appears. P1 is excluded from re-roll while `TutorialFirst` holds. |

### Pacing, measured

Greedy-payback player model, active play, jars collected every 30 s, a poacher every 210 s (from
300 s on) taking half of 30 s of the best cage's income, 3 seeds each (`econ.py`/`tune.py`, section
17). Minutes of active play:

| Player model | First Rare | First Legendary | First Mythic | Nine Mythics | Income at 10 min |
|---|---|---|---|---|---|
| Idle-only (never raids) | 8.0-10.0 | 61.0-69.5 | 315.0-325.5 | 770.5-810.5 | 12-21 /s |
| Raider, timing error 0.25 s, 2x optimal raid time | 3.1-5.1 | 14.2-16.8 | 107.0-140.5 | 541.5-571.0 | 42-66 /s |
| Raider, timing error 0.35 s, 3x optimal raid time | 4.5-6.0 | 16.1-17.6 | 119.0-182.5 | 566.5-618.5 | 34-45 /s |
| Flawless bot (100 % success, optimal time) | 2.3-3.3 | 13.8-14.8 | 109.5-120.0 | 540.5-553.5 | 60-78 /s |

What the table says: raiding cuts the time to a first Legendary by about three quarters (61.0-69.5
minutes to 14.2-16.8) and takes about 30 % off the whole game (770.5-810.5 minutes to 541.5-571.0),
which is the fantasy doing its job. **The flawless bot finishes at most 3.3 % sooner than the
timing-error-0.25 human on every seed** (553.5 vs 555.0, 553.0 vs 571.0, 540.5 vs 541.5 minutes):
the limit on raid value is Heat and permits, not skill, which is the anti-exploit property section
10 depends on. Offline jars shorten calendar time on top of this and are not in the model.

---

## 5. Raids

### Rival Camps

A camp is the same 9 x 8 yard as a lair. Fence lines are full rows of fence with gaps; lasers only
ever sit in gaps; rocks and snares sit in the free rows between lines.

| Tier | Fence line rows | Gaps per line | Gaps armed with a laser | Forced laser lines | Rocks | Snares | Laser on / off (s) | Grab hold (s) |
|---|---|---|---|---|---|---|---|---|
| 1 Common | 4 | 3 | 1 | 0 | 6 | 1 | 1.0 / 2.2 | 1.0 |
| 2 Rare | 3, 6 | 2, 2 | 2, 1 | 1 | 6 | 2 | 1.4 / 1.9 | 1.5 |
| 3 Legendary | 3, 6 | 2, 2 | 2, 2 | 2 | 6 | 3 | 1.8 / 1.6 | 2.0 |
| 4 Mythic | 2, 4, 6 | 2, 1, 2 | 2, 1, 2 | 3 | 4 | 3 | 2.2 / 1.4 | 3.0 |

Reasons, column by column:
- **Lines, gaps, armed gaps.** A fully armed line cannot be walked around, so "forced laser lines"
  is exact by construction: every route crosses it. Tier 1 forces nothing (a first raid is learnable
  by watching); each tier after adds one forced line. That is the whole difficulty ladder, and it is
  readable from the gate.
- **Laser timing.** The *padded carry window* is the part of a cycle in which a carrying raider can
  start a crossing with 0.3 s of reaction pad on both ends: `off - 2 x 0.3 - 6/12`. It shrinks
  1.10 s, 0.80 s, 0.50 s, 0.30 s, which is 34.4 %, 24.2 %, 14.7 %, 8.3 % of each cycle (measured,
  `camps.py`). Periods stay 3.2-3.6 s so a full cycle can be watched in one glance.
- **Rocks and snares.** Detours and route choice in the free rows. Tier 4 has 4 rocks, not 6,
  because its free rows are single rows that rocks cut easily: measured over 2 000 seeds, 6 rocks
  needed a resample on 1 067 layouts (worst 12 attempts) against 859 (worst 9) with 4, for no
  difficulty the forced lines do not already provide.
- **Grab hold.** The only time a raider stands still. It rises with the prize so a Mythic grab is a
  visible commitment of about one laser period, and it is never exposed: row 8 carries no trap.

**Three cages per camp**, at three distinct random columns. The prize (the camp's tier) takes the
column farthest from the gate column; the other two hold a species one tier lower (tier 1 camps:
Common). A tie for farthest goes to the lower column number, so generation is deterministic. The
raider chooses which to take. Three, because one prize and two lesser cages is the
smallest set that offers a risk-for-reward choice; more cages add Parts without adding a new choice.

**Generation guarantees.** Gap columns in a line are at least 2 apart; the cells directly above and
below a gap are never rocks or snares; lines are at least 2 rows apart; row 8 and the entry cell
(5,1) are always free. Together these mean **no two lasers are ever 4-adjacent**. Rocks and snares
are placed, then row 8 must be reachable from (5,1) (row 8 is one free connected row, so one cage
reachable means all are); otherwise resample.

| Name | Value | Reason |
|---|---|---|
| `Camp.MaxLayoutAttempts` | 32 | Measured over 2 000 seeds per tier: layouts needing any resample 3 / 82 / 117 / 859; worst case 1 / 2 / 2 / 9 attempts. 32 is 3.5x the worst seen. After 32, the camp is built with no rocks and no snares, which is reachable by construction (lines have gaps, free rows are full rows). |

**Every camp is beatable, by construction, not by search.** A laser on a route always has a
non-laser cell on each side (no 4-adjacency), a raider can wait on those, and every tier's `off`
satisfies `off - 2 x 0.3 >= 6/12` (smallest off is 1.4 s against the 1.1 s needed). So each forced
laser can be crossed within one period from a safe cell. The measurement agrees: **0 of 1 200 camps
unsolvable** (300 per tier) under the padded human model.

### Raid time, measured (300 camps per tier, `camps.py`)

Optimal total time gate to prize to gate, including the grab hold, moving centre to centre at 16
studs/s in and 12 out. "Human model" pads every laser ON window by 0.3 s on both sides.

| Tier | Human model median | p90 | p99 | max | Flawless (no pad) median | No lasers median | Median cost of the lasers |
|---|---|---|---|---|---|---|---|
| 1 | 15.40 s | 16.60 | 18.45 | 20.20 | 15.40 | 15.40 | 0.00 s |
| 2 | 19.25 s | 24.20 | 28.20 | 30.45 | 18.10 | 15.90 | 2.38 s |
| 3 | 22.55 s | 27.45 | 30.70 | 31.75 | 20.50 | 17.60 | 4.50 s |
| 4 | 30.03 s | 35.80 | 40.30 | 40.65 | 26.98 | 21.00 | 8.75 s |

The grid-centre model is conservative: a real player moves continuously and can cut corners, so
real optimal times are at or below these. Humans add hesitation and navigation on top.

### Success, modelled

Per forced crossing the player aims at the centre of the feasible start window (`off` minus the area
crossing time) and misses by a normal error. Crossings in and out are both counted (`success.py`):

| Timing error (1 sigma) | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---|---|---|---|
| 0.15 s | 100.0 % | 100.0 % | 99.9 % | 99.0 % |
| 0.25 s | 100.0 % | 99.3 % | 91.8 % | 70.7 % |
| 0.35 s | 100.0 % | 92.6 % | 66.1 % | 32.4 % |

The sigma values are assumptions swept, not measurements of people. Studio playtests replace them.

### Catch rules (the server's, not the model's)

Everything is judged on the XZ plane from the **trusted position** (below); height is ignored
entirely, so jumping and flying change nothing.

- **Laser Net.** Danger area = the laser's cell inset by 1 stud (6 x 6), drawn as a translucent net
  from floor to fence height so it visibly cannot be jumped. States cycle OFF, WARN, ON. The raider is
  caught if the trusted segment for a tick passes through the danger area at any instant that falls in
  an ON window, with time interpolated linearly along the segment. A continuous segment test, not a
  point sample: the poll rate cannot let anyone slip between two samples (the vault-runners review's
  crumble-poll finding).
- **Snare.** Danger area = its cell inset by 1 stud; always armed; the same segment test.
- **Inset of 1 stud.** R15's root part is 2 studs wide, so a root 1 stud inside the cell edge means
  the body is visibly on the trap. Catching earlier than that would look unfair.

| Name | Value | Reason |
|---|---|---|
| `Raid.TickSeconds` | 0.1 | The raid loop. With the continuous segment test the tick sets responsiveness, not correctness. |
| `Raid.WalkSpeed` / `CarrySpeed` | 16 / 12 studs/s | 16 is Roblox's default, read off a live Humanoid in Studio (fork-tower/STUDIO.md). Carrying at 75 % makes the way out the hard half: a laser area takes 0.5 s instead of 0.375 s. The server writes WalkSpeed on the Humanoid. |
| `Raid.WarnSeconds` | 0.5 | The last 0.5 s of OFF flickers amber. It is not shorter than the 0.3 s reaction pad the difficulty model assumes, so a player who never starts a crossing during WARN is playing the model's game. |
| `Raid.LatencyGraceSeconds` | 0.2 | The server treats the first 0.2 s of every ON window as OFF, because the client sees the switch about one round trip late. The value is an assumption about typical ping; section 15. |
| `Raid.TrustedSpeedFactor` | 1.35 | Carried over from vault-runners' `Run.TrustedSpeedFactor` (replication jitter tolerance, not speed). Not re-measured here; section 15. |
| `Raid.TrustedBurstSeconds` | 0.5 | Unused allowance banks at most 16 x 1.35 x 0.5 = 10.8 studs. Covers a half-second replication stall. Two laser areas are never closer than 22 studs far edge to far edge (6 + 1 + 8 + 1 + 6, because lasers are never 4-adjacent), so a banked jump can never skip two, and jumping through one ON area is still caught by the segment test. vault-runners uses 3 s; at 3 s the bank would be 64.8 studs, most of a camp. |
| `Raid.WallShrinkStuds` | 1 | For the trusted-position wall test only, every fence, rock and cage rectangle is shrunk by 1 stud. An honest root can never be within 1 stud of a wall (R15 root half-width), so honest movement never clamps; a noclipper gains 1 stud. |
| `Raid.RaidSeconds` | 150 | Hard cap, then "Dawn broke" and the raid fails. 3.7x the worst measured human-model optimal time (40.65 s, tier 4), so no competent attempt gets near it, and a parked pocket is freed in bounded time. |
| `Raid.PermitFraction` | 0.10 of the cheapest species of the camp's tier; tier 1 free | Tier 2: 360, tier 3: 16 800, tier 4: 648 000. Break-even success is 10 %: cheap enough to try a camp you might fail, costly enough that throwing yourself at one you cannot beat bleeds Essence. Tier 1 is free because it is the first-minute tutorial raid. Spent at raid start, never refunded on a failure. |
| `Raid.Heat` | equals the tier's payback: 30 s, 300 s, 2 400 s, 14 400 s | After a **successful** raid, that tier's camps are "on alert" for this long (wall clock, persisted, shown on the Hunt Board). A stolen tier-k cryptid is worth its price = rate x payback, so steals of tier k are worth at most one tier-k cryptid's income per second, even to a flawless raider. Measured with the flawless raid times: 0.66, 1.32, 1.98, 11.32, 16.98, 69.41, 99.15, 449.16 /s against rates 1, 2, 3, 12, 18, 70, 100, 450. Failures set no Heat; the permit is the failure cost. |
| Anti-farm bound | steal-then-release <= half the rate | (0.5 x price - permit) / (Heat + raid time) measured 0.33 to 179.66 /s, each under half its species' rate. Stealing to sell never beats owning. |
| `Raid.Unlock` | tier k needs a tier k-1 species in the Journal; tier 1 always open | The Journal is ever-owned, so releasing a cryptid can never re-lock a camp (checklist: ownership vs selection; vault-runners invariant 4). |

### The trusted position

Adapted from `vault-runners/src/shared/Trace.luau`, in 2D with walls. The client owns its
character's physics, so the root position the server reads is a claim. Each tick:

1. allowance += speed x factor x dt, capped at the burst;
2. move toward the claim in a straight line by at most the allowance;
3. if that segment enters a (shrunk) fence, rock or cage rectangle, stop at the boundary. No
   rerouting: a reroute that times lasers for the player would be an auto-dodge for anyone who
   noclips.

The trusted position starts where the **server** put the raider, never where the client says.
Every raid rule reads it: the catch test, the grab cell check, the escape check.

### Raid flow

1. **Start** (`Hunt(tier)` from the Hunt Board panel). Refused, each with a toast: already raiding;
   tier locked; Heat active; permit unaffordable; no empty cage ("Free a cage first - release one at
   its cage"); character missing or unparented; more than 20 studs from your own Hunt Board (the
   board's prompt reaches 10 studs, and the other 10 let a player drift while reading the panel; a
   raid starts from home so that leaving home is a real risk). Then:
   spend the permit, claim a pocket slot, generate the camp, build it synchronously, write the
   trusted start, CFrame the root to the pocket's row 0, set WalkSpeed 16. While raiding, lair actions
   (buy, release, expand, build) are refused with "You are on a hunt".
2. **Grab.** Each camp cage has a ProximityPrompt whose HoldDuration is the tier's grab hold,
   parented to an invisible anchor at the cage front (z = 88 in the pocket's own grid frame, the
   front edge of the cage row, 3 studs up) with
   `MaxActivationDistance = 10`: every point of the grab cell is within hypot(4, 8) = 8.94 studs of
   that anchor, so the prompt shows wherever a grab can succeed. The hold
   is charged on the server the fork-tower way: `PromptButtonHoldBegan` stamps the clock (measured in
   Studio to replicate at +32 ms), and `Triggered` completes only after the full hold has elapsed on
   the server's clock, re-checking that the trusted position is still on that cage's grab cell. A
   client firing the prompt with no hold waits the full duration. On completion the cryptid model is
   welded above the character (Massless), WalkSpeed drops to 12.
3. **Escape.** Trusted position enters row 0 while carrying: the grant (cryptid into the first empty
   cage, Journal, Heat, stats) is written in **one** atomic flush. If this is a saving session and the
   write fails, the grant is rolled back, the permit refunded and the player told. Then home.
4. **Caught.** Camera shake and red flash, "Caught by a laser net" / "Caught in a snare", prize back in
   its cage, home, no Heat. **Timeout** is the same with "Dawn broke". A "Leave camp" HUD button ends
   the raid as a failure.
5. **Abort.** Character removed, Humanoid died, or player left: no grant, pocket destroyed, slot
   freed. The permit stays spent (leaving is not a refund path).
6. **Home** means the root is CFramed to the lair's arrival marker. The character is live and
   parented here, so this is not the spawn race; a death goes through section 9 instead.

---

## 6. Defense: your traps, and poachers

### Your lair

Player lairs use the same yard with **two fence lines, rows 3 and 6, three gaps each**, and 6 rocks
in the free rows, all from the player's lair seed (section 7). Closing two gaps of a line with snares
and arming the third with a laser forces every poacher through that laser: the defense puzzle is
readable and has a measured payoff. Six rocks, because the free rows hold 32 cells a rock may use
(45 free-row cells minus the entry cell and the 12 cells beside gaps): 6 is enough to make two lairs
route differently while leaving 26 of those 32 cells buildable.

| Name | Value | Reason |
|---|---|---|
| `Traps.LaserPrice` / `SnarePrice` | 250 / 100 | The best measured layout (4 snares + 2 lasers) costs 900, which is 43-75 s of idle-only income at minute 10 (measured 12-21 /s). Affordable around the time poachers start. Prices stay flat because trap **caps**, not prices, bound defense value. |
| `Traps.MaxLasers` / `MaxSnares` | 4 / 6 | 4 snares + 2 lasers fully force both lines; the remaining 2 of each allow shaping. Also keeps a lair under its 300-part budget. |
| `Traps.RefundFraction` | 1.0 | Clearing a trap refunds it fully, so experimenting with layouts is free. Buy-and-clear nets zero, so there is nothing to farm. |
| `Traps.LairLaserOn` / `Off` | 1.4 / 1.9 s | The tier 2 camp timing, so the lasers a player builds at home teach the lasers they meet in their first forced line. |

**Placement rules** (`Layout.validatePlacement`, every refusal toasts its reason): the cell is in
rows 1-7; not a fence, rock or trap already; not the entry cell (5,1); a laser has no laser
4-neighbour ("Lasers need a safe cell between them"); caps respected; after a snare, row 8 must still
be reachable from (5,1) ("That would wall off your cages - poachers and raiders must have a way in");
and the cell must be reachable from (5,1) at all ("Nothing can ever walk there"). That last rule
exists because measured over 2 000 lair seeds, rocks wall in 535 free cells in total, and a trap there
is Essence spent on nothing. On load, `Layout.reconcile` removes any saved trap the current rules
reject, refunds it and toasts once, so a later Config change can never leave a lair invalid.

### Poachers

| Name | Value | Reason |
|---|---|---|
| `Poacher.FirstAfterSeconds` | 300 of session time, and only once the lair holds 2 cryptids | The first five minutes are the tutorial window: the measured raider reaches a Rare at 3.1-5.1 minutes. |
| `Poacher.IntervalSeconds` | uniform 180-240 | A defense beat every few minutes. A jar nobody collected holds at least 3 minutes of income when the next poacher arrives, so collecting before the grab matters. |
| `Poacher.WarningSeconds` | 10 | The poacher appears on the lair's gate approach (row 0, column 5) when the warning ends, and leaves the same way. Measured race: from any walkable cell of their own lair the owner reaches the Collect Pad in at most 224.97 studs = 14.06 s (208 studs of yard path, the worst over 2 000 lairs, plus 16.97 from the gate approach to the pad). The earliest a poacher can take anything is 10 s of warning + 64 studs at 10 studs/s + 2 s hold = 18.4 s. An owner at home always wins the race if they run. |
| `Poacher.Speed` | 10 studs/s | Slower than the owner's 16, which is what makes the race above winnable. |
| `Poacher.HoldSeconds` | 2 | A visible grab at the cage the owner can see from the apron. |
| `Poacher.PathLaserCost` | 5 (a floor cell costs 1) | Poachers route around a laser unless a detour costs more than 4 cells, so an unforced laser barely matters (measured 3.1 % catch) and a forced one does. |
| `Poacher.Caution` | 0.6 | At each laser crossing the poacher times it safely with probability 0.6, otherwise walks straight in. Measured catch rates below: defense matters and is never a wall. |
| `Poacher.TheftFraction` | 0.5 of the fullest jar at grab time | The owner who ignores a warning loses half of one jar, never a cryptid, never the wallet. Caught on the way out, the theft goes back in the jar. |
| `Poacher.BountySeconds` | 30 s of lair income, minimum 10 Essence | If every poacher were caught this is at most 30/180 = 16.7 % extra income; at the best measured catch rate and the mean interval it is 0.669 x 30 / 210 = 9.6 %. Traps pay for themselves without trap-farming beating cryptids. The minimum keeps a one-Jackalope lair's reward visible. |

Poachers visit **only while the owner is in the server** (online, visible, answerable). They still
come while the owner is raiding: leaving home is a risk, bounded by half of one jar. A poacher never
touches an offline lair, so a returning player never logs in to a loss.

Measured catch rates, 4 000 lair seeds each (`poacher.py`):

| Defense | Caught | ...on the way in | ...on the way out | Theft succeeds | Median trip of a successful theft |
|---|---|---|---|---|---|
| No traps | 0.0 % | 0.0 | 0.0 | 100.0 % | 19.6 s |
| One laser in a gap, no snares | 3.1 % | 1.8 | 1.2 | 96.9 % | 21.2 s |
| One line forced (2 snares + 1 laser) | 42.4 % | 23.2 | 19.2 | 57.6 % | 24.3 s |
| Both lines forced (4 snares + 2 lasers) | 66.9 % | 43.3 | 23.6 | 33.1 % | 29.2 s |

A snare placed on a walking poacher's next cell catches it. Traps never affect players in their own
or anyone else's lair; only poachers.

---

## 7. Procedural generation

All generation lives in pure shared modules that take `Rng` and `cfg` as arguments (never
`require("./X")`, which resolves in the luau CLI and is invalid in Roblox). `Rng.luau` is copied
verbatim from `fork-tower/src/shared/Rng.luau` - three different `Rng.luau` files exist in the repo,
and this one is byte-identical in anomaly-observatory, fork-tower and nightwatch-manor. Every
small-range draw uses `Rng.below` (high bits), never `Rng.int`.

| What | Seed | Server-only salt? | Why |
|---|---|---|---|
| **Lair layout** (fence-line gap columns, 6 rocks) | `(WorldSeed * 7919 + (userId % 999983) * 104729) % 2147483647` | No | A player's own home, the same every session, so saved trap coordinates stay meaningful without saving the layout. Nothing competitive to memorise. userId is reduced first (checklist: seed overflow); the largest intermediate is 265 173 308 682, far under 2^53. |
| **Rival Camp** | `(WorldSeed * 31 + sessionSalt * 7 + (raidSerial % 1000000) * 2654435761 + tier * 104729) % 2147483647` | Yes | `sessionSalt` is an integer in [0, 2^31 - 1] drawn once from an unseeded `Random.new()` at server start, and never leaves the server, so a camp cannot be predicted or memorised across raids (checklist: replayable RNG). `raidSerial` counts raids started in this server. Largest intermediate 2 654 448 767 457 080, under 2^53 = 9 007 199 254 740 992. |
| **Camp laser phases** | the same `Rng` stream that built the camp, continued after the lasers are placed | Yes | Phases are never published (section 8); a player learns them by watching, the same as a script. |
| **Lair laser phases** | `(sessionSalt * 13 + plotIndex * 7919) % 2147483647`, one stream per plot, one draw per laser placed or loaded | Yes | Same reason. Only poachers ever cross a lair laser in v1. |
| **Offers** | `(sessionSalt * 7 + (userId % 999983) * 104729) % 2147483647`, one stream per player | Yes | Offers are shown anyway; the salt only stops "rejoin until the right species" from being predictable, and re-rolls are free regardless. |
| **Camp name** | camp seed | Yes | 8 first words x 8 names (e.g. "Muddy Boots' Camp") = 64 names. Flavour on the pocket sign. |
| **Cryptid models** | none: a pure function of the species table | - | Four body plans (quadruped, biped, winged biped, serpent) built from Parts with per-species proportions and colours and a tier aura: Rare `Fx.dust`, Legendary `Fx.attachGlow` + `Fx.sparkle`, Mythic the same in gold. At most 14 Parts. Built once into `ServerStorage.CryptidTemplates` and cloned. |

`Config.WorldSeed = 20260916`. Changing it redraws every lair; saved traps on now-invalid cells are
removed and refunded by `Layout.reconcile` (section 6).

Generator order for a camp, so a test can replay it: fence lines and gap columns; rocks; snares;
cage columns; prize column; reachability check (resample up to 32); then lasers into gaps as the
tier's armed counts say; then phases.

---

## 8. Data model

### Persisted (DataStore `StealACryptid_v1`, key `u_<userId>`)

```
{
  jobId      = string | nil,   -- session lock owner: game.JobId, a STABLE per-session token
  lockUntil  = integer,        -- os.time() seconds; renewed by every write
  data = {
    v              = 1,
    essence        = number,
    savedAt        = integer,                   -- os.time() at this write
    cagesUnlocked  = integer 3..9,
    cages          = { {sp = "jackalope", jar = 12.5}, ... },  -- ALWAYS 9 entries; sp "" = empty
    traps          = { "L:4:3", "S:2:3", ... },  -- kind:col:row strings, dense list
    heat           = { t1 = integer, t2 = integer, t3 = integer, t4 = integer }, -- os.time() expiry
    journal        = { "jackalope", "hodag", ... },  -- species ever owned, dense list
    tutorial       = integer 0..4,              -- hint step (section 12); 0 also means the
                                                -- guaranteed Jackalope is still on P1
    stats          = { steals = n, caught = n, poachersCaught = n },  -- shown in the Hunt
                                                -- Board panel's footer
  },
}
```

Why this shape:
- **No integer keys anywhere** (checklist: JSON round-trips sparse integer keys to strings).
  `cages` is always nine dense entries with `""` for empty, `heat` uses `t1`..`t4`, the other lists
  are dense.
- **The layout is not saved**, only trap coordinates; the layout is a pure function of the lair seed.
- **Jars are saved with `savedAt`**, and on load each occupied cage gets
  `jar = min(rate x JarHours x 3600, jar + rate x clamp(os.time() - savedAt, 0, JarHours x 3600))`.
  A negative or huge delta (clock skew between servers) mints at most one jar.
- **Two clocks, never mixed.** `os.time()` for everything persisted (`savedAt`, `lockUntil`, Heat
  expiries). `tick()` for in-session timers (income tick, laser cycles, holds, the raid cap), because
  it is the clock `robloxemu` advances; deep-vein measured that `os.clock()` barely moves headless.
  Headless checks test the persisted clock by seeding timestamps in the past.

| Name | Value | Reason |
|---|---|---|
| `Save.FlushTickSeconds` | 7 | Coalesced writes, at most one per player per tick. vault-runners measured 5 as under Roblox's roughly-6-second per-key cadence and refused to sit on 6. 8 players at one write per 7 s is 68.6 writes/min against a budget of 60 + 10 x 8 = 140. |
| `Save.AutosaveSeconds` | 60 | Jar growth does not mark a save pending: it is recomputed from `savedAt` on load, so a crash loses none of it. Every other change (a collect, a purchase, a trap, a theft, a raid) marks the profile pending and reaches the store within one 7 s flush tick. The autosave exists to renew the session lock. |
| `Save.LockSeconds` | 120 | Twice the autosave, so a live session always renews before expiry. Same value as vault-runners. |

`GetDataStore` is pcall'd (unwrapped, it raises in an unpublished place and kills the server script).
A session whose store is unavailable, or whose profile is locked by another server, is a
**non-saving session**: everything works in memory, a HUD banner says "Progress is not being saved
this session" (when locked: "...rejoin in 2 minutes", because the other server's lock lapses after
`Save.LockSeconds`), and nothing is ever written for the rest of the session. It never switches to
saving mid-session, because that would have to merge in-memory progress with whatever the store holds.
Raids are allowed in it, because a grant that is never written cannot be redeemed twice. In a saving
session, a failed write of a raid grant rolls the grant back (section 5).

### Server-only state

Held in Lua tables in `Main.server.luau`, which no client can read:
- `sessionSalt`, every player's `Rng` streams, offers, re-roll cooldown stamps;
- raid state: camp layout, laser phases, trusted position and allowance, grab hold stamps, carried
  cage, start time, pocket slot;
- poacher state: next arrival time, path, caution rolls, carried theft;
- lair laser phases, remote rate-limit buckets, pending-save flags, profile fingerprints.

In `ServerStorage` (Instances that must exist server-side, never under `workspace` or
`ReplicatedStorage`, per anomaly-observatory's "ServerStorage, not the zone"):
- `ServerStorage.CryptidTemplates` - the eight built models, cloned on demand;
- `ServerStorage.RaidInfo.<userId>` - attributes `Tier`, `Seed`, `PrizeColumn`, `LaserPhases` (a
  string) for the headless checks and capture tooling, exactly as `PassInfo` serves anomaly's rig.

### What replicates, and why it is safe

| Replicates | Why that is fine |
|---|---|
| Every lair Part: fences, rocks, cages, caged cryptids, trap Parts, jar billboards with their amounts | Nothing in a lair is secret. Jars are visible by design. |
| Laser visuals: the server switches each net's Transparency/Color at OFF, WARN and ON as they happen | Timing is observable by design; a player learns it by watching and so does a script. The server publishes the **present**, never the schedule: no period, phase or next-switch time exists on any Instance. |
| Pocket Parts: camp fences, rocks, snares, lasers, cages and cryptids, the camp name sign | v1 has no hidden traps on purpose. A hidden trap would be unfair and would leak through replication anyway. The prize is labelled; nothing about it is secret. |
| The poacher model's CFrame as it walks | Its path is visible as it happens; its future path, caution rolls and target are server-only. |
| Shared modules in `ReplicatedStorage` (Config, Layout, Heist, Economy, ...) | The generator is public code, but camps need the server-only salt and phases come from server `Rng`, so the code predicts nothing. |
| `State` payload to the **owner only** (`FireClient`): essence, rate, jars, cages, journal, trap list, Heat remaining, camp unlocks and permits, tutorial step, raid time left, carrying | All of it is the player's own current information. None of it is future information. |

**The attribute rule: v1 puts no attributes on any Instance under `workspace` or
`ReplicatedStorage`.** The client learns everything from `State`. Instance names carry only what is
visible (`Laser_4_3`, `Cage_7`). The headless check enumerates every attribute under both and
requires the list to be empty - fork-tower's wire inventory, in its strictest form, so a renamed or
relocated leak (fork-tower mutations L3 and L4) is still caught.

### Remotes (`ReplicatedStorage.CryptidRemotes`)

| Remote | Direction | Validation |
|---|---|---|
| `State`, `Toast`, `Fx` | server to owner | - |
| `Hunt(tier)` | client to server | integer 1..4; the refusals in section 5 |
| `LeaveCamp()` | client to server | must be raiding |
| `Reroll()` | client to server | 30 s cooldown; not while raiding |
| `Expand()` | client to server | below 9 cages; affordable; not while raiding |
| `BuildMode(on)` | client to server | boolean; not while raiding |
| `TrapAction(col, row, action)` | client to server | integers in range; action is `"laser"`, `"snare"` or `"clear"`; build mode on; placement rules |

In-world interactions, all checked `who == owner` on the server, with a toast naming the lair's
owner for anyone else: pedestal buy prompts, cage release prompts (hold 1.0 s), the Hunt Board prompt
(opens the panel), the Collect Pad touch, and build tiles. Apron prompts set
`MaxActivationDistance = 10`: apron objects stand 10-14 studs apart, so a prompt belongs to the
object the player is standing at. The Collect Pad is 8 x 1 x 8 and also requires the root within 12
studs of its centre: the pad's half-diagonal (5.7) plus a character width and replication slack.
Build tiles are ClickDetectors created only while the owner's build mode is on and removed when it
ends, with `MaxActivationDistance = 128`: the farthest pairing of any apron point with any trap-tile
centre is 101.98 studs (measured), so every tile is clickable from anywhere on the apron. Camp cage
prompts check that the triggering player owns the pocket.

| Name | Value | Reason |
|---|---|---|
| `Remotes.MaxPerSecond` | 8 per remote per player | Above deliberate tapping speed on a phone; excess calls are dropped with at most one "Slow down" toast per 5 s, so a flood is neither silent nor spammy. |

**No silent no-ops.** Every refusal above sends a toast naming the reason (checklist; Grow a
Crystal's "i cant even place a seed").

---

## 9. Spawn and respawn

The Studio-measured order (robloxemu/SPAWN-ORDER.md): `CharacterAdded` fires while the character is
unparented at the origin; one frame later the engine parents it and places it on the enabled
SpawnLocation, discarding any CFrame written in between. With no enabled SpawnLocation it drops the
character on the highest ground over the origin.

The design uses the pattern fork-tower verified in Studio (the player landed on their own pad,
0.00, 3.00, 14.00):

1. **Exactly one enabled SpawnLocation**, `workspace.Trailhead`, at world (0, 0.5, 0) on the road.
   Never a second one, never one in a lair or a pocket: the engine picks among all enabled ones, so a
   second spawn would make placement a coin flip. There is ground under the origin, so the roof
   fallback can never be reached.
2. **The plot is claimed synchronously in `PlayerAdded`, before any yield** (before the DataStore
   load), so the destination exists by the time any character can spawn. Lair contents may appear a
   moment later once the profile loads.
3. **`CharacterAdded`**: wait for `char.Parent ~= nil`, bounded at 300 frames of `task.wait(1/60)`;
   then **re-read** the player's plot and raid state (both can change across the yield); then CFrame
   the root to the lair's arrival marker, 3 studs above apron top (where an R15 root sits over the
   floor it stands on; vault-runners' `RunnerRootHeight`), facing P1; set WalkSpeed 16.
   `WaitForChild` is not the wait: on the server both children already exist when the event fires.
4. **A respawn during a raid** first aborts the raid (Humanoid.Died / character removal, section 5),
   then goes through step 3 like any spawn, so the player lands home.
5. Leaving frees the plot index for the next joiner and destroys the lair; any poacher and pocket go
   with it.

Headless check (`check_stealacryptid.luau`): exactly one enabled SpawnLocation in the workspace,
none under any lair or pocket; after `simulateSpawn` each of two players stands on their **own**
apron (XZ within 4 studs of their marker, not at the Trailhead, not on each other); the same after a
second spawn; the same after a spawn during a raid. The assertion is on XZ, not Y, as SPAWN-ORDER.md
section 7 advises, and 4 studs is half a cell: close enough to be "on the marker", loose enough not
to pin the emulator's fitted placement height.

---

## 10. Anti-exploit model

The rule, taken from vault-runners' Trace: do not try to detect cheating; remove what cheating is
worth, and bound what cannot be removed.

| A client can... | What it would buy | Denied or bounded by |
|---|---|---|
| Teleport its character | Skip lasers, reach a cage or the gate instantly | Trusted position moves at most 21.6 studs/s (16.2 carrying) with a 10.8-stud bank; the segment test catches a jump through an ON area; no bank can span two laser areas. |
| Noclip through fences and rocks | Walk past forced lines | Trusted position clamps at shrunk walls and never reroutes, so the noclipper's trusted self stays behind the fence and can reach neither cage nor gate. |
| Fly or jump over traps | Avoid nets and snares | Height is ignored; the catch test is XZ only. Nets are drawn full height so nobody expects a jump to work. |
| Fire a prompt with no hold (`fireproximityprompt`) | Instant grab, instant release | Holds are charged on the server's clock; the grab also needs the trusted position on the grab cell. |
| Fire prompts, remotes or touches from afar | Buy, collect or grab remotely | Grab needs the trusted grab cell. Lair actions only affect the caller's own lair; collecting your own jars from afar saves a walk, has no economic value, and the pad also checks the root within 12 studs. |
| Keep walking at full speed while carrying (ignore the WalkSpeed the server wrote) | Shorter exposure on the way out (0.375 s vs 0.5 s per area) | Bounded, not removed: the trusted cap while carrying is 16.2 studs/s, above 16. Stated as residual risk. |
| Run a perfect-timing bot reading rendered laser states | Win every raid | Cannot be removed: states must be visible to be fair. Bounded by Heat and permits: the flawless bot finished a whole game at most 3.3 % sooner than the timing-error-0.25 human model (section 4), and steals of tier k are worth at most one tier-k cryptid's rate. |
| Read attributes, names or remote traffic | Camp seeds, phases, prize, poacher timing, next offers | Nothing to read: no attributes under `workspace`/`ReplicatedStorage`, names carry only visible facts, `State` holds only the owner's present, the salt and phases never leave the server. Enforced by the empty-attribute inventory check. |
| Rejoin | Reset Heat, get a failed raid's permit back, keep a prize mid-raid | Heat is a persisted wall-clock expiry; the permit is spent at start; leaving mid-raid aborts with no grant. |
| Server-hop to duplicate | Two sessions writing one profile | Soft session lock on a stable per-session token (`game.JobId`); a locked session never writes. |
| Crash or disconnect at the moment of a grant | Get the cryptid without paying the Heat, or twice | The grant, Heat and Journal are one atomic write; a failed write rolls back. |
| Spam remotes | Server work, pocket churn, write amplification | 8 calls/s per remote; one raid and one pocket per player; writes coalesced to one per 7 s per player. |
| Park in a pocket forever | Hold server Parts | `RaidSeconds = 150`. |
| Manipulate time | Mint jar Essence | Only server `os.time()` is used, clamped to 0..8 h per load. |
| Delete Parts locally | See through fences | Changes only its own view; the server's walls and rules are untouched. |

**Residual risks, stated so nobody reads more into the table than is there:** the carry-speed
tolerance above; a lag spike whose straight catch-up chord crosses a laser after the honest player
already did (rare, see section 15); an exploiter teleporting into someone else's pocket to body-block
a gap (player-to-player collision groups are not in v1 because `PhysicsService` collision groups
are not modelled by `robloxemu` and would be untested).

---

## 11. Fair monetization

**v1 sells nothing.** No Game Passes, no Developer Products, no premium currency. The radar's
differentiator is fairness, and the first version proves the loop before anything is priced.

Rules for any later version, written now so they are not negotiated feature by feature:
1. **No paid randomness, ever.** No crates, eggs, wheels or paid re-rolls. Free re-rolls stay free.
2. **Nothing that changes a raid or a defense.** No permit skips, no Heat reduction, no raid success,
   no trap slots, no poacher immunity, no carry speed. Those are exactly the numbers the anti-farm
   bounds in section 5 are built on.
3. **No Essence for Robux, directly or indirectly** (no "2x income" pass: it scales every bound in
   this document).
4. **Candidates are cosmetic only:** fence and cage skins, a carried-cage trail, apron decorations.
5. **No rewards for likes, favourites or follows**, and no store text that implies one.

---

## 12. The first 60 seconds

A new player, measured distances and modelled durations. Each row names its source; the headless
first-minute walk in section 14 has to reproduce the verifiable ones.

| t (s) | What happens | Source of the timing |
|---|---|---|
| 0 | Spawns on the Trailhead for one frame, lands on their own apron's arrival marker facing P1. HUD: "Buy your first cryptid - walk to the glowing pedestal and press E" (touch: "tap BUY"). Essence 30; P1 shows a Jackalope, 30, "+1/s". | Section 9 |
| ~1 | Reaches P1 (10 studs = 0.625 s) and buys. Journal 1/8. | Measured distance, WalkSpeed 16 |
| 1-3 | The Jackalope walks into cage 1 (centre column); its jar starts at +1/s. P3 now shows a Rare at 3 600-5 400 as the visible goal. | `BuyTweenSeconds` 2 |
| ~8 | Jar reaches 5; hint: "Step on the Collect Pad". P1 to pad is 22 studs = 1.4 s. | Hint threshold, measured distance |
| ~10 | Collects about 6 Essence. Hint: "Rival camps have cryptids too - use the Hunt Board". Pad to board 14 studs = 0.9 s. | Measured distance |
| ~15 | Opens the Hunt Board panel: Camp 1 open and free, Camp 2 open with permit 360, Camps 3-4 locked with their reason. Enters Camp 1. | Section 5 |
| 15-46 | Walks a tier-1 camp: one unforced laser, three cages of Commons. Hint on arrival: "Watch the red nets. Walk through when they go dark." At a cage: "Hold E to grab". Carrying: "Get back out the gate". The measured human-model optimum is 15.40 s median (11.80-20.20); a first-timer is assumed to take twice that. | `camps.py`; the 2x is an assumption |
| ~46 | Escapes; lands home; the stolen Common walks into cage 2. Gold flash, "You stole a Hodag!". Camp 1 on alert for 30 s. | Section 5 |
| 60 | Two cryptids, 2-4 Essence/s, a Rare offer visible, a 360 permit to save for. No poacher yet (not before 300 s). | Section 6 |

The core action (a purchase) happens at about 1 s; the headline action (a steal) finishes inside the
first minute; no step needs a purchase the player cannot afford, and every refusal on the way says
why.

The hints are a persisted step counter (`tutorial`, section 8), so a rejoin resumes rather than
repeats:

| Step | Hint shown | Advances when | Number and reason |
|---|---|---|---|
| 0 | Buy your first cryptid at the glowing pedestal | the first purchase | - |
| 1 | Step on the Collect Pad | the first collect | `Tutorial.CollectHintJar = 5`: shown once the jar holds 5 Essence, about 5 s after the Jackalope reaches its cage, so the second action follows the first without a wait and the collect visibly pays. |
| 2 | Rival camps have cryptids too - use the Hunt Board | a raid starts | - |
| 3 | In-camp hints (nets, hold to grab, get back out) | the first raid ends, either way | - |
| 4 | none; the first poacher warning carries its own "Build traps with the Build button" line | - | - |

---

## 13. Visuals and HUD from the first build

Code-only, no assets. Copy `Fx.luau`, `FxClient.luau` and `Responsive.luau` verbatim.

**Lighting.** `Fx.applyLighting(preset)` takes a preset table, so the game's preset lives in
`Config.Lighting` and `Fx.luau` stays byte-identical to its siblings. It is `Fx.Presets.Horror`
with four overrides, each for a reason:

| Override | Horror | Moonlit | Reason |
|---|---|---|---|
| `lighting.FogStart` / `FogEnd` | 10 / 120 | 40 / 220 | A raider must read a whole camp from its gate. Nothing within 40 studs (half a camp) is fogged, and the far edge of the cage row, 80 studs from row 0, sits (80 - 40) / (220 - 40) = 22 % into the fog ramp. Horror's 120 would put it at 64 %. |
| `colorCorrection.Saturation` | -0.35 | -0.10 | Tiers are colour-coded (Common grey-green, Rare blue, Legendary purple, Mythic gold); Horror's desaturation muddies them. |
| `bloom.Threshold` | 1.1 | 0.95 | Neon laser nets and tier auras must bloom. |
| `depthOfField` | present | removed | Far-field blur would blur the far side of the camp the player has to read. |

**Signature particles.** Tier auras on cryptids (section 7); a faint glow rim on every interactable
(pedestals, pad, board, cage prompts) so interactive things read as interactive; `Fx.dustVolume`
mist in camps; laser nets are Neon with a PointLight when ON.

**Camera juice** on the signature events only: caught (shake + red flash), escaped with a cryptid
(FOV punch + gold flash), poacher warning (brief red flash for the owner), bounty (gold flash).

**Colour is never the only signal.** Laser OFF is not a dim red net; it is no net. WARN is a flicker.
Tier is also written on each cage label.

**Text.** English. No emoji in any in-world or HUD string: fork-tower found an Emoji 13 glyph renders
as an empty box in Roblox's font, and v1 does not need emoji badly enough to photograph a whitelist.

**HUD, phone first** (`docs/mobile-ui-brief.md`): every HUD frame goes through `FxClient.theme`;
root Frame with the UIScale, sized 1/scale; side
panels through `Responsive.sideWidth`/`fitHeight`; re-layout on ViewportSize changes; nothing
tappable bottom-left or bottom-right. Layout: top bar (Essence, +rate/s, Journal n/8); top-edge
toggles (Build, Leave camp while raiding); toasts and hints top-centre; the Hunt panel and the build
action sheet (Laser 250 / Snare 100 / Clear / Close) as centre panels; raid chip (time left,
carrying) top-centre; the non-saving banner under the top bar.

---

## 14. Verification plan (tests first)

Scaffold per `docs/new-game-checklist.md` section 1: `default.project.json` (Rojo: `src/server` to
ServerScriptService, `src/client` to StarterPlayerScripts, `src/shared` to ReplicatedStorage),
`src/shared/{Config,Rng,Fx,FxClient,Responsive,Economy,Offers,Layout,Heist,Trace2D,Poacher,CryptidModel}.luau`,
`src/server/Main.server.luau`, `src/client/Hud.client.luau`, `tests/*.spec.luau`, `README.md`,
`CLAUDE.md`, `.gitignore` containing `publish_*.bat` and `publish_*.sh`.

Each pure module gets its spec written first and watched fail:
- `Economy.spec`: price = rate x payback; tier ordering; offline accrual clamps (negative delta, huge
  delta, cap); sell never profits; Heat = payback; the anti-farm bound for every species.
- `Offers.spec`: pedestal tier rule for ranks 0-4; tutorial Jackalope; re-roll cooldown; P1 excluded
  while the tutorial holds.
- `Layout.spec`: fence lines, gap spacing, protected cells, reachability, resample cap and fallback
  (over 2 000 seeds per tier, like `resample.py`); no two lasers 4-adjacent; placement rules and every
  refusal reason; `reconcile`.
- `Heist.spec`: laser state at t; the segment-vs-area timed catch, including a segment that crosses
  an ON area inside one tick and one that clips a corner; snare always armed; grace; the solver port
  of `camps.py` asserting **every generated camp of every tier is solvable under the padded model**
  and reporting the time table, so section 5's numbers are re-measured in Luau.
- `Trace2D.spec`: speed cap, burst cap, wall clamp with the 1-stud shrink, honest movement never
  clamped along a wall, teleport through an ON area caught.
- `Poacher.spec`: Dijkstra with laser cost, caution roll, theft returned on an outbound catch,
  bounty minimum, the catch-rate table re-measured.

Headless (`robloxemu`, rebuild the bundle before every run): `check_stealacryptid.luau` asks the
workspace, not the modules - plots parented and counted from both inputs; part budgets; the spawn
block in section 9; the first-minute walk in section 12 driven through real prompts, pad touches
and remotes; a raid walked with claimed positions (escape grants and flushes; walking into an ON
net catches; a claimed teleport is throttled; a claimed noclip is clamped); the empty-attribute
inventory; a grant whose flush is made to fail is rolled back; a seeded `savedAt` in the past
produces exactly the clamped jar. `check_stealacryptid_hud.luau` runs `hudcheck` across the six
viewports. Then a mutation sweep over the guards with at least one control that must survive, and an
adversarial review, before anything is called done.

---

## 15. Needs Studio

Nothing on this list is verified by anything above, and none of it may be reported as verified until
somebody has looked at it in Studio (or, where marked, a published place).

1. **Laser readability.** Whether OFF / WARN / ON read instantly under the Moonlit preset from the
   gate at 80 studs, on a phone-sized viewport too; whether the translucent full-height net reads as
   "cannot jump this".
2. **Latency grace.** Whether 0.2 s makes catches feel fair at window edges on a real connection, and
   whether honest players ever get caught by a catch-up chord after a lag spike.
3. **Trusted-position tolerance.** Whether `TrustedSpeedFactor 1.35` and a 0.5 s bank ever throttle an
   honest player; count throttled ticks during real play.
4. **Carried cryptid.** A welded, Massless model above the character: no fling, no network-ownership
   jitter, camera not obstructed.
5. **Hold prompts.** Tap-and-hold on cage prompts on touch; the grab hold charge with real
   `PromptButtonHoldBegan` replication on a live server (Studio measured +32 ms locally on fork-tower).
6. **Spawn.** The one-frame Trailhead flash before the apron; a respawn after Reset during a raid lands
   home.
7. **Build mode.** Tapping ClickDetector tiles on mobile; the hover cursor on desktop; reachability of
   the farthest tile at `MaxActivationDistance 128`.
8. **Fences and rocks.** A Humanoid cannot climb or jump a 10-stud fence or rock; walking along fence
   lines and through 8-stud gaps feels right.
9. **Cryptid silhouettes.** Whether 14-Part procedural models read as Mothman, Bigfoot, Nessie and the
   rest, and whether tier auras are distinguishable.
10. **Poacher.** Whether a server-stepped NPC model moves smoothly on clients and reads as sneaking;
    whether the 10-second warning is noticed.
11. **Performance.** Frame rate on a phone with 8 lairs and 8 pockets at the part budgets.
12. **Tier colours** under the modified preset, and for colour-blind readability alongside the text
    labels.
13. **The first 60 seconds** with a person who has never seen the game, against the table in section 12,
    especially the assumed 2x first-raid time.
14. **DataStore on a published place** (not Studio): session lock handoff between servers, write
    throttling at the 7 s flush, the non-saving banner when a second server holds the lock.
15. **Feel of the pacing**: whether a first Rare at 2.3-10.0 minutes and a first Legendary at
    13.8-69.5 minutes (the modelled range across all four player models, section 4) feel earned, and
    whether Tier 4's padded 0.30 s window is hard or unfair.

---

## 16. Cut from v1, and why

| Cut | Why | What v1 leaves ready |
|---|---|---|
| Raiding real players (same-server lairs, then cross-server snapshots) | Needs a population v1 will not have; cross-server snapshots add shared-key write limits and stranger-data moderation; any victim loss adds cross-profile writes. | A player lair and a camp are the same layout type with the same rules and solver, so a player lair is a valid raid target by construction. |
| TeleportService / reserved servers | Not testable in `robloxemu` or in Studio play. | Pockets in the same server. |
| Rebirth, prestige, biomes (Forest, Swamp, Arctic, Urban) | A second progression axis before the first is proven. | The pacing table in section 4 shows where the v1 curve ends. |
| Sighting Crates / any random purchase | Section 11 rule 1. | Visible offers. |
| Mutations / variants | Random value rolls are gambling-adjacent, and a second value axis doubles the balance work. | - |
| Species 9-15 | Eight built well beat fifteen built thin. | Species are table rows plus a body plan. |
| Alarms, cameras, turrets, floodlights; trap upgrades | Section 2. | Trap kinds are data plus one catch rule each. |
| Offline poachers | Logging in to a loss is the feel-bad the async design exists to avoid. | - |
| Leaderboards, codes, badges, trading, gifting | Not part of the loop. | - |
| All monetization | Section 11. | Rules written. |
| Sound and music | No assets available (checklist section 2), and the radar says lean on lighting instead. | Signature events already have visual beats that sound can attach to. |
| Custom meshes, textures, skybox | No assets. | Procedural Part models. |
| Player-to-player collision groups in pockets | Untestable headless (section 10). | - |

---

## 17. Where the numbers came from

Throwaway Python models of the rules in this document, run 2026-09-16 in the session scratchpad
(`C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/sac/`).
Not part of the game and not kept in the repo, so the directory may be gone by the time this is
read; the build phase re-measures in Luau (section 14).

| Script | What it measures | Key assumptions |
|---|---|---|
| `heist.py` | Time-expanded earliest-arrival solver over grid cells (0.05 s steps, bitmask layers); the first open-yard camp model, rejected because a raider routes around its lasers: median human-model time exceeded the no-laser median by only 0.00 / 0.00 / 3.60 / 7.33 s across tiers (20 camps per tier) | Centre-to-centre moves; waiting allowed on any non-laser cell or a laser cell while safe |
| `camps.py` | Fence-line camp generation per tier; solvability; optimal, flawless and no-laser times (300 camps per tier), re-run after adding the prize tie rule | Human model pads each ON window by 0.3 s both sides; in at 16, out at 12 studs/s |
| `resample.py` | Layout resample counts and worst attempts, 2 000 seeds per tier; re-run for Tier 4 with 6 rocks (1 067 resampled, worst 12) against the chosen 4 (859, worst 9) | - |
| `success.py` | Success per tier from a normal timing error per forced crossing | Sigma 0.15 / 0.25 / 0.35 s, swept, not measured on people |
| `poacher.py` | Catch rates for four defense layouts, 4 000 lairs each | Poacher 10 studs/s, laser cost 5, caution 0.6, lair laser 1.4 / 1.9 s |
| `race2.py` | Lair reachability resamples (4 of 2 000 raw layouts, max 1 resample); walled-in free cells (535); owner worst yard path (208 studs); poacher shortest gate-to-grab path (64 studs) | Cell-centre paths. The script's own print added a rounded 16-stud apron leg; the 16.97 in section 6 is the exact distance, recomputed separately. |
| `econ.py`, `tune.py` | Pacing for four player models, 3 seeds, two price curves; the chosen curve is `tune.py B`, re-run with the tie-rule raid medians (identical minutes, because raid durations round to whole seconds) | Greedy-payback purchases, collect every 30 s, poacher every 210 s, raid time = solver median x 2 or x 3, no offline time |
| `derived.py` | Trusted caps and bank, laser crossing times, apron walk times, Heat and anti-farm bounds (re-run with the tie-rule flawless times), seed maxima, bounty caps, write rate | Arithmetic on the values above |
| inline checks | Rock-eligible cells in a player lair (32 on all 500 seeds tried); farthest apron-to-trap-tile distance (101.98); grab cell to cage-front anchor (8.94); gate approach to Collect Pad (16.97) | Geometry in section 3 |
