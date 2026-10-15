# Disaster Rounds — design spec (v1)

Written 2026-10-07 from `docs/game-radar/2026-09-23-roblox-game-radar.md` ranked #5 ("Round-Based Survival —
procedural, physics-driven hazards (no PvP/AI combat)", line 56, and the runner-up note at line 323) and
`docs/game-radar/2026-09-04-roblox-game-radar.md` ranked #5 ("Disaster-escape survival-obby (procedural collapsing
map)", line 54). Measured against `docs/complete-game-standard.md` (the finish line) and `docs/new-game-checklist.md`
(the traps). **No game code exists yet.** Nothing was committed, pushed or published, and Studio was not opened.

"Measured" in this file means one of two things, and each number says which:
* **(m) modelled**: printed by `design/pacing_model.py` (sha256 `69c2b2dc…bbcd`, 2026-10-07; its full output is
  `design/model-output.txt`, sha256 `4d556cd1…2b5f`; full hashes in §18). Run it with
  `py -3 design/pacing_model.py` from this folder (about 5 min; `quick` for about 1 min). Seeded, so a re-run prints
  the same numbers. It is a design-time model with its own copy of the
  numbers in §2. When the game exists, `tests/Pacing.spec.luau` and the robloxemu checks must re-measure the same
  quantities against the real `Config.luau` and the real pure modules, and the model is retired.
  **Why Python:** on 2026-10-07 the luau CLI directory in the session scratchpad was empty and no `luau.exe` existed
  on the machine. Fetching one needs the owner's go, so the model is Python. It is arithmetic and Monte Carlo; the
  build re-measures everything in Luau.
* **(c) computed**: arithmetic on the design numbers, shown where it is used.

Every other number is a design choice, and its reason is next to it. Caps (parts, emitters, lights) are limits the
build enforces in code and measures headless. They are not measurements yet.

### Amended by REVIEW-1 (2026-10-07): where this spec changed after the adversarial review

Two adversarial reviewers found eleven defects; `REVIEW-1.md` has the evidence and the tests. The rules below replace
what this file says elsewhere wherever the two disagree:
* **F1** The round ends when the disaster does. In the 4 s outro nobody is "in" the round any more: a leave, a reset,
  a death or a fall there is not an elimination (§2.6), and a fallen body is put back on the Lookout.
* **F2** Off the island is the sea in every disaster and in the drop, as the flood always had it: a root over no cell
  for `GroundGrace` (0.6 s) in a row is swept out ("You fell into the sea"). §10's "fly or hover" row now holds.
* **F3** A save works on the session, not on `sessions[plr]`: the leave's write (the release and a mid-round
  elimination) is written after a write that was still in flight. `BindToClose` waits (up to 25 s) for such writes.
* **F4** The next disaster is an **even draw from all four, every round; the same one can come again**. The first
  build's "never twice in a row" told a resting player which disaster could not come next (§5 point 1 now holds).
* **F5** The board counts the best streak **up to `Config.Board.StreakCap` = 25**, with the time it was first reached
  (`Progress.boardEntry`). A script reading the replicated red never misses; 25 is a run a fast human makes in 43 % of
  one-hour sittings (model). The streak, Heat and the Codex go on past 25 as before. Owner decision (§17 #6).
* **F6** `JumpIn` refusals over the rate are toasted at most every 2 s (`Config.Rates.JumpInToastSeconds`).
* **F7** Every red piece (a ring, a piece of the tornado's path) is a red **volume** from 0.05 over the lowest cell top
  it reaches to 0.25 over the highest (`Zones.redSpan`), so its red shows on every terrace it reaches (§2.3).
* **F8** The tornado's red is its reach exactly: a disc on the funnel itself and on every published point ahead, and
  13-stud boxes joining them; nothing behind the funnel; drawn from the name, before touchdown (§2.5).
* **F9** A `SetRest` request over the rate (2 a second) is applied when the second is up, the last one winning; it is
  never dropped (§2.7).
* **F10** The movement guard keeps nothing it sees during its quiet second after a server teleport (§2.7).
* **F11** Budgets are capped in code: live rings `Budget.Rings` 16 (`Strikes.maxLive`), far scenery
  `SceneryPartsPerPiece` 125 and `SceneryParts` 500 (`SkyArt.updatePiece` trims), the tornado's red pieces
  `PathRibbon` 40 (§3.5).

### Where each item of the standard lives

| standard (complete-game-standard.md) | here |
|---|---|
| §1 core loop reachable from join, walked headless | §1, §11, §13 (`check_disasterrounds.luau` walks it) |
| §1 spawn per SPAWN-ORDER | §9 |
| §1 server-authoritative, nothing secret replicates, salted seeds | §8, §10 |
| §1 DataStore lock, owner token, string keys, one-time grants | §8.1, §8.4 |
| §1 no silent no-ops | §12.3 |
| §2 Fx preset + signature particles | §3.4 |
| §2 bands (≥ 5), hazards (red = hit zone), rest, budgets | §3, §4, §5, §3.5 |
| §2 brag at 30-45 min + long-term goal, pacing model in tests/ | §6, §2.8 |
| §2 phone first, UIScale root, hudcheck overlap = true | §12 |
| §3 public + friends board, unscriptable metric, tie by first | §7 |
| §3 no Robux, no gambling, no pay-to-win | §2.6, §16 |
| §4 README store text, EYECANDY needs-Studio + shot list, MARKETING clips, CLAUDE.md | §14 (drafts), §15 |

---

## 1. The core loop

Every 88 seconds the server builds a new island and drops everyone who is not on a break onto it.
Four seconds later it names the disaster: a meteor shower, a flood, a tornado or an earthquake, an even draw every
round (the same one can come again; REVIEW-1 F4). For 60 seconds you survive it. **Every danger is drawn in red first, and the red
is exactly where it hits:** step out of a red ring before the meteor lands, get above the red line before the water
does, stay off the red path the tornado will take, get off the red cracked ground before it drops. One hit and you
are swept back to the Lookout, the cliff-top deck where everyone waits and watches, until the next round. Still
standing at the end means you survived it: your **streak** goes up, and every two rounds in a row your **Heat** rises
(🔥1 to 🔥5), which aims more of the danger at you personally and puts a flame over your head that everyone can see.
Every disaster you survive moves your sky one step along its story, from a calm cove through storms and fire to the
sky falling (the brag, about 35 minutes) and, much later, a new dawn. The **Codex** keeps the hottest Heat you have
survived for each disaster, and the **leaderboard ranks your best streak**.

---

## 2. Every number, with its reason

### 2.1 The round cycle (`Config.Round`, pure `Round.luau`)

| number | value | reason |
|---|---|---|
| intermission | 20 s on the Lookout | time to read the result card, look at the board and decide to take a break. Genre norm is 15-20 s |
| drop | 4 s on the island before the disaster is named | to look around a new island. The disaster is named only after everyone has landed (§10) |
| disaster | 60 s | long enough for 3 flood rises or 9 quake batches with a hold at the end; short enough that a player swept out early waits at most 80 s for the next round (c: 60 − 4.5 + 4 + 20; the earliest possible hit is a tornado at 4.5 s, §2.5) |
| outro | 4 s on the island | the SURVIVED card and confetti where it happened, then everyone is moved to the Lookout |
| cycle | **88 s** (c) | 40.9 rounds an hour (c: 3600 / 88) |
| early end | the disaster ends the moment nobody (counted or practice) is left on the island | a solo player swept out at 10 s does not wait 50 s for nothing. Not in the model, which uses the fixed 88 s and so is slightly pessimistic for weak or solo players |
| players needed | 1 | a new game has few players. Rounds pause (intermission repeats) only when every player in the server is on a break |
| practice drop-in | from the start of the drop until 50 s into the disaster (10 s before it ends) | a player who joins mid-round taps **▶ Jump in (practice)** and is on the island in about 3 s. **A practice round counts for nothing** (no survival, no streak change, no Codex), so arriving late can never be used to face less of a disaster. First time on the island after joining: **p50 3.0 s, p90 28.2 s, max 37.0 s** (m) |

Precisely: `JumpIn` is accepted while `Phase == "drop"`, or while `Phase == "disaster"` and fewer than 50 s of it have
run. It is refused to anyone in this round's roster, anyone swept out of this round, anyone already dropped in, and
anyone resting (§12.3 gives each refusal's text).

### 2.2 The island (`Config.Island`, pure `MapGen.luau`)

| number | value | reason |
|---|---|---|
| grid | 13 × 13 cells of **8 studs**, 104 × 104 studs, centred on the world origin | a cell is about one ring wide (a ring is 9 studs across, §2.4), so "the cell you stand on" is a unit players can read. Crossing the island takes 6.5 s at walk speed (c: 104 / 16) |
| levels | 0-4, each **4 studs** (cell top at y = 4·level) | a 4-stud step is a jump (Roblox's default jump clears about 7 studs), so every climb is a small obby move. Level 0 is beach |
| shape | max of 1-3 cones (peak heights 4-6, slopes 0.55-0.95 levels per cell), clipped to 0-4 **and to the cell's distance from the edge** | `max` and `min` of 1-Lipschitz functions are 1-Lipschitz, so **neighbouring cells never differ by more than one level** and every cell is reachable on foot. The edge clip makes a beach ring and keeps peaks off the shore. Peaks sit in the inner 5 × 5 core |
| validation | (1) no step over one level; (2) **≥ 18 cells at level ≥ 3** (dry after the last flood rise, holds 8 players, §2.5); (3) **no flood traps**: every level-k cell (k ≤ 2) reaches a level ≥ k+1 cell without stepping down; (4) the longest such escape ≤ 80 studs cell-centre path (100 studs walked at the 1.25 path factor) | a map failing any rule is re-rolled. Measured over 500 maps (m): **97.7 % of generated candidates pass, never more than 2 tries per map**; level ≥ 3 cells min **18**, median **45**, max **49**; share of cells per level 0-4: 0.339 / 0.232 / 0.183 / 0.136 / 0.110; worst flood escape on any map **76 studs** (median map 36) |
| disaster-agnostic | **every accepted map supports every disaster** | the map is visible at the drop, before the disaster is named. If maps were built for their disaster, the map would name it (§10) |
| styles | 3, chosen per round: **Palm Atoll** (sand, grass, palms, beach rocks), **Pine Isle** (gravel, moss, snow-capped tops, pines, logs), **Ochre Mesa** (tan and ochre sandstone layers, cacti, bleached rocks) | variety from the first round at code-only cost: a palette per level and two prop kinds per style. No palette uses saturated red: red is reserved for danger (§3.4) |
| props | ≤ 80 Parts per island, **CanCollide, CanQuery and CanTouch all false** | decor only, so they never change a path or block a dodge. The reachability rules above stay true |
| walls | invisible, CanCollide, at \|x\|, \|z\| = 53, 40 studs tall (a jump from level 4 reaches about y = 23, c: 16 + 7) | a dodge or a jump never ends in the sea. The only ways off the island are holes (quake) and water (flood), both drawn in red first |
| fall-out height | root below y = −6 | below the sea surface (y = −2). In a round that is an elimination; on the Lookout it returns you to the deck |
| `MaxPlayers` | **8** (set at publish) | the flood's last dry area can be as small as 18 cells (1 152 sq studs, c). With 8 players at 🔥5 the crowded-plateau model still has a reacting bot survive 100 % and a normal player 97.0 % of the hold (m, §4.1). The part budget (§3.5) is sized for 8 |
| drop placement | each roster player gets a distinct level ≥ 1 cell, ≥ 2 cells from every other player's, facing the island centre | spread out so the first rings do not land on a crowd |

### 2.3 The red rule and the hit test (`Config.Hits`, pure `Zones.luau`)

**Red means exactly where it hits.** One colour, one meaning, in all four disasters and in the Lookout strays.

| number | value | reason |
|---|---|---|
| `PlayerRadius` | 1.5 | the template's value (plus1-jump `Config.Hazards`) |
| server sample rate | 10 Hz (`SampleSeconds` 0.1), positions are the server's view of the root | the only positions the server has |
| `LagGrace` | **0.2 s: a hit needs the root inside the zone at every server sample in [T, T + 0.2]** | the server sees a root about one latency late. A player who stepped out just before T on their own screen is out by T + 0.2 on the server. **Ties go to the dodger**, and what the player sees is what decides |
| 2-D tests | every hit test uses the root's X and Z (plus, for flood and quake, the state of the cell under it) | jumping or hovering over a red zone never helps, and a flying exploit gains nothing (§10) |
| clock | `tick()` on the server, published as `workspace` attribute `ServerNow` at 1 Hz; clients extrapolate ≤ 1.5 s | deep-vein `Main.server.luau:1108` records that `os.clock` would freeze every timer headless (StormGrow `DESIGN.md` §2.5 applies the same rule) |

### 2.4 Aimed rings and Heat (`Config.Strikes`, pure `Strikes.luau`)

Every disaster also aims **rings at each player personally**: meteors in a Meteor Shower, lightning in a Flood,
flying debris in a Tornado, falling boulders in a Quake. They are the one mechanic every round shares, and Heat
scales them.

| number | value | reason |
|---|---|---|
| ring | hitRadius 3.0 + `PlayerRadius` 1.5 = **4.5 studs** (9 across, a little over one cell) | big enough to read on a phone at 30 studs, small enough that one step out of it (≤ 4.5 studs, 0.28 s at walk speed, c) always escapes |
| telegraph | **3.0 s** from the ring appearing to impact | the template's `MinTelegraphSeconds`. A first draft used 2.5 s: the slow profile then survived a heat-0 Meteor Shower only 0.35 of the time (an earlier model run, §2.8). At 3.0 s: 0.64 (m) |
| centre | the target's server-seen root at the moment the ring appears; never moves | a fixed ring is the clearest promise. A moving player is often half out already |
| pass | 0.6 s after impact the ring is gone | the impact animation |
| first ring at a player | ≥ 5 s after the disaster is named (or after a practice landing) | time to read the disaster card |
| interval jitter | ±20 % | a steady beat would let a player stop watching |
| intervals at Heat 0-5, Meteor Shower | **6.0 / 5.0 / 4.2 / 3.5 / 3.0 / 2.5 s** | rings per round (m): 8.7 / 10.3 / 12.3 / 14.8 / 17.2 / 20.6 |
| intervals at Heat 0-5, Flood / Tornado / Quake | **15 / 12 / 9.5 / 7.5 / 6.0 / 5.0 s** | rings per round (m): 3.4 / 4.3 / 5.5 / 6.9 / 8.7 / 10.4. **Heat 0 still aims at least one ring in the first 20 s (c: 5 + 15)**, so a player who never moves is always swept out (§10, AFK) |
| live rings per player | at most 2 (c: Meteor 🔥5, shortest interval 2.0 s against a 3.6 s life); 1 in the other disasters (shortest 4.0 s) | |
| **`ExitStuds`** | **7**: a ring is placed only if every player it covers can stand outside all red within 7 studs; otherwise it waits 0.25 s and tries again | the fairness rule. With 8 bots at 🔥5 in a Meteor Shower (m, 1 200 bot-rounds each): rule off and a naive dodger **33 lost**; rule on, naive dodger **1**; a dodger that does not walk through a ring as it lands **0** with the rule on or off. The rule protects players who dodge less well |
| `MaxRingCoverage` | 0.25: live rings never cover more than a quarter of the walkable area | 42 live rings on a whole island, 4 on an 18-cell flood plateau (c: floor(0.25 × area / 63.6)). A deferred ring waits for a free slot |
| Heat | **`heat = min(5, floor(streak / 2))`**, frozen for the round at the drop | "every two rounds in a row" is easy to say. 🔥5 at streak 10. Normal players first reach 🔥5 at **28.8 min** median (p10 14.8, p90 73.9), fast 15.5, slow 97.8 (59 % within 4 h) (m) |
| sky radiant | meteors, lightning and boulders fall from one fixed compass direction per round; debris flies from the funnel | players learn where to look up. The ring is the truth; the projectile is the show and lands exactly at impact. Whether the projectile is on screen at the default camera is a needs-Studio item (§15 #6); the ring does not depend on it |

### 2.5 The four disasters

Every disaster is named with an icon and a rule of at most six words, and its first threat starts no earlier than
3 s after the name (`DisasterLeadSeconds`).

**☄️ Meteor Shower — "Step out of the red rings."** Only aimed rings, on the Meteor schedule above. Each impact
leaves a scorch decal (client, cosmetic; the cell does not change).

**🌊 Flood — "Get above the red line."** (`Flood.luau`)

| number | value | reason |
|---|---|---|
| rises | **3**: water to y = 2, 6 and 10 (covers levels 0, 1 and 2 by 2 studs) | levels 3-4 stay dry, which MapGen guarantees is ≥ 18 cells (§2.2) |
| warning per rise | **9 s**: a red translucent slab at the coming water height, and every cell top below it tinted red | the slab and the tint are exactly the cells that flood |
| rising | 4 s, linear, from 2 studs under the flooding level's top to 2 over it | the water passes a cell's top 2 s into the rise |
| timeline | warnings at 3, 16, 29 s; rising 12-16, 25-29, 38-42 s; hold 42-60 s with the aimed lightning | three rises and an 18 s finish on the plateau |
| hit | the cell under your root is flooded (water above its top) for ≥ **0.6 s** in a row | 0.6 s covers `LagGrace` and a jump across a one-cell flooded gap. Hovering does not help: the cell decides |
| time to escape | **11.6 s** (c: 9 + 2 + 0.6) against the longest escape 76 studs × 1.25 = 95 studs walked, 5.9 s (c) | the slowest walker still has 5.7 s to react (c) |
| measured | 1.0 flood threats per player per round, normal survives the water itself 100 % (m) | the Flood is the spectacle: everyone running uphill. Its rings make it a real round: normal survives 0.946 at 🔥0, 0.860 at 🔥5 (m) |

**🌪️ Tornado — "Stay off the red path."** (`Tornado.luau`)

| number | value | reason |
|---|---|---|
| funnel | hit radius 5.0 + 1.5 = **6.5 studs** (the path is 13 studs wide) | a big, readable threat |
| speed | **9 studs/s** | walk speed is 16, so anyone can step out of its way (1.78 × faster, c) |
| the red path | the area the funnel will cover in the **next 4.0 s**, drawn on the ground, nothing further | outside it you are safe for 4 s; inside it you will be hit when it passes. The path beyond 4 s is not decided yet (§8.2) |
| path | decided 0.25 s at a time at the 4 s horizon; steers toward a target with ≤ 30° of turn per second; target = a random player on the island (50 %) or a random point (50 %), re-chosen every 5 s or when reached; reflects off the island edge | it hunts, but readably |
| start | touches down at 3 s at a random edge point **≥ 20 studs from every player on the island**; its first 4 s of path are drawn at the name | nobody is hit while still reading the card: the earliest possible hit is 4.5 s (c: 3 + (20 − 6.5) / 9). The 20-stud rule is not in the model; it can only remove early hits |
| warning time | ≥ 3.3 s from the path reaching you to the funnel's edge reaching you (c: 4.0 − 6.5 / 9); escape ≤ 6.5 studs, 0.41 s (c) | |
| hit | root within 6.5 studs of the funnel centre for ≥ `LagGrace` | |
| measured | 1.19 path threats per player per round, normal survives the funnel 0.986 (m) | one funnel in v1 (a split into two is cut, §16) |

**🏚️ Earthquake — "Get off the red ground."** (`Quake.luau`)

| number | value | reason |
|---|---|---|
| batches | every **6 s** from 3 s: cells crack red for **3.0 s**, then drop into the sea | 9 batches, the last drop at 54 s (c) |
| batch size | ≤ **10 cells**: for each player on the island (random order), 60 % chance to crack their own cell plus one neighbour; the rest random | it comes for you, and the island still breaks up everywhere |
| eligibility | a cell may crack only if a 4-neighbour is intact, not cracking and at most one level away, **and adding it never strands a cell already chosen** | every red cell has a safe step at most one cell away: escape ≤ 10 studs (c: 8 + 1.5 + 0.5), 0.72 s with jump overhead (c). A cell whose neighbours are all gone can never crack, so an isolated pocket is safe |
| cap | ≤ **45 %** of the island (76 of 169 cells, c) | the island is broken but standing; measured share at round end p50 0.45, max 0.45 (m) |
| hit | the root over a dropping cell at every sample in [drop, drop + 0.2]; later, the root over a hole for ≥ 0.6 s, or below y = −6 | holes are visible (you see the sea), so walking into one is a readable mistake |
| measured | 4.45 crack threats per player per round; a bot with 0.6 s reaction never had less than **1.97 s** to spare (m) | the Quake is the hardest disaster at 🔥0: normal 0.893 (m) |

### 2.6 Streak, survivals, Codex (`Progress.luau`)

| number | value | reason |
|---|---|---|
| counted round | you were in the roster at the drop, and not a practice drop-in | |
| survived | still in the round at 60 s, and the movement guard never failed (§10) | |
| on survival | `survived += 1`, `streak += 1`, `best = max(best, streak)`, Codex row of this disaster filled up to your Heat | |
| on elimination | `streak = 0`. `survived` and `best` never go down | a hit costs a round and a streak, never progress |
| leaving during a round | **counts as an elimination**, saved at the leave. The round ends when the disaster does: the 4 s outro is not "during" it (REVIEW-1 F1) | otherwise quitting under a red ring would protect a streak (§10) |
| resetting your character in a round | an elimination ("You reset — round lost") | same reason |
| server shutdown during a round (`BindToClose`) | the round is void for everyone: nothing gained, no streak lost | not the player's doing |
| Codex | 4 disasters × Heat 0-5 = **24 entries**. Surviving a disaster at Heat h fills that disaster's row up to h | one entry per heat would make low-heat entries need a lost streak. Cumulative rows reward the hottest survival. Normal fills it at **1.3 h** median (p10 0.5, p90 3.3), fast 0.6 h (m); entries at 30/60/120 min: normal 17/22/24, slow 10/13/16 (m) |
| prices | **none: v1 has no currency** | nothing to buy means nothing to balance and nothing that could be pay-to-win (§16) |

### 2.7 Timers, limits, caches

| number | value | reason |
|---|---|---|
| movement guard | a counted player whose server-seen root moves more than **28 studs** in any trailing 1.0 s (c: 16 × 1.5 + 4), or leaves the island box by more than 4 studs, is swept out ("Movement check failed") | walking is 16 studs/s; the margin absorbs network bunching. Reset for 1.0 s after every server teleport, and nothing seen in that second is kept (REVIEW-1 F10: one late-replicated deck position swept every dropped player). Live false positives are a needs-Studio item (§15 #8) |
| `JumpIn` rate | 1 request per second per player; a refusal over the rate is toasted at most every 2 s (REVIEW-1 F6) | |
| `SetRest` rate | 2 per second per player; a request over the rate is applied when the second is up, the last one winning, never dropped (REVIEW-1 F9: the client sends only on a change, so a dropped request left its HUD "on a break" while the server dropped it into rounds) | |
| saves | one `UpdateAsync` per counted player at each round end, plus leave and `BindToClose`; a lock-renewal write every 120 s for players with no round result | at most 8 writes per 88 s, 5.5 per minute (c), against Roblox's 60 + 10 × players per minute |
| session lock TTL | 300 s, renewed by every write | 2.5 renewals (120 s apart) can fail before another server may take the record; a resting player still renews every 120 s |
| load | 3 attempts (1, 2, 4 s apart), then a fresh unsaved profile and a retry every 10 s | StormGrow REVIEW-1 A2 |
| lock wait | re-read every 5 s for 30 s; then read-only, re-checked every 10 s, and an expired lock on an untouched record is taken over | StormGrow REVIEW-1 A1, meteor-drop-tycoon REVIEW-1 A2 |
| writes | serialised per player; a write that lands after the leave began never re-locks | meteor-drop-tycoon REVIEW-1 A3, StormGrow F2 |
| public board cache | 60 s, `GetSortedAsync(false, 10)` | the standard's number |
| friends board | plus1-jump's `Config.Board`: `GetFriendsAsync` capped at 200, friends cached 300 s, each friend's best read with `GetAsync` (burst 40, then 1 per second, 10 requests of budget always left), scores cached 120 s | plus1-jump's measured design, copied with `Board.luau` |
| board prompt | one switch a second per player; a failed name lookup is cached 60 s | StormGrow REVIEW-1 A6 |

### 2.8 Measured pacing (m; 3 000 sessions of 4 h per profile, random join phase)

**Profiles** (the human part, written down instead of hidden). Reaction time per threat is lognormal with the
median below and sigma 0.35. A *lapse* is a threat noticed late: 1-4 s late for a ring, a path or a crack, 2-8 s for
a flood warning. Every player then walks at 16 studs/s to the nearest point outside all the red they have noticed,
and does not walk through a ring as it lands. **bot** is the fairness floor: a scripted dodger with 0.6 s reaction
and no lapses. If the bot is ever hit, the disaster is unfair.

| profile | reaction median | lapse per ring/path/crack | lapse per flood warning |
|---|---|---|---|
| fast | 0.55 s | 0.8 % | 0.5 % |
| normal | 0.80 s | 2.0 % | 1.0 % |
| slow | 1.20 s | 3.5 % | 2.0 % |
| bot | 0.60 s fixed | 0 | 0 |

**Chance to survive a round, at Heat 0 / 1 / 2 / 3 / 4 / 5:**

| | Meteor | Flood | Tornado | Quake | average |
|---|---|---|---|---|---|
| fast | .956 .936 .922 .918 .914 .912 | .976 .982 .958 .970 .948 .946 | .973 .978 .955 .967 .945 .943 | .955 .961 .937 .949 .927 .925 | .965 → .932 |
| **normal** | .868 .850 .806 .802 .740 .748 | .946 .920 .920 .914 .872 .860 | .932 .907 .907 .901 .860 .848 | .893 .868 .868 .862 .823 .811 | **.910 → .817** |
| slow | .642 .612 .572 .500 .410 .372 | .864 .798 .804 .748 .666 .616 | .853 .788 .794 .739 .658 .608 | .720 .665 .670 .624 .555 .514 | .770 → .527 |
| **bot** | 1.000 at every Heat | 1.000 | 1.000 | 1.000 | **1.000** |

(Each value combines parts measured on at least 500 simulated player-rounds each, so it carries up to about ±0.022
of sampling noise, c: one standard error √(p(1 − p) / 500); that is why a few neighbouring Heats are out of order. The bot's 1.000 is every round of every
table, 250 rounds per ring table and the same global parts as the others.)

**Minutes to each band (p10 / median / p90):**

| band (survivals) | normal | fast | slow |
|---|---|---|---|
| 2 Windy Point (2) | 2.7 / 3.4 / 4.7 | 2.7 / 3.3 / 3.9 | 2.8 / 3.8 / 6.0 |
| 3 Storm Coast (6) | 8.7 / 9.9 / 12.0 | 8.6 / 9.4 / 10.8 | 9.4 / 11.9 / 15.4 |
| 4 Ember Isles (12) | 18.0 / 20.0 / 22.7 | 17.5 / 18.6 / 20.5 | 20.5 / 23.9 / 28.6 |
| **5 Falling Sky (21), the brag** | **32.6 / 35.2 / 38.6** | 30.9 / 32.7 / 34.9 | 37.4 / 41.8 / 47.6 |
| 6 New Dawn (100) | 162.5 / 168.4 / 175.0 | 151.7 / 155.7 / 160.4 | 190.1 / 200.4 / 211.5 |

Median minutes spent in bands 2-5, normal: 5.9 / 10.3 / 14.7 / 133.5 (band 1: 3.4). Every band's median duration is ≥ 2 minutes
for every profile (m). Survivals per hour (median): normal 35.8, fast 38.5, slow 30.0 (m).

**Best streak (the board's metric), median at 30 / 60 / 120 / 240 min:** normal 10 / 13 / 16 / 17, fast
15 / 22 / 30 / 34, slow 6 / 8 / 9 / 9 (m). The board separates skill.

**Sensitivity of the brag to the lapse assumption** (normal, band 5 median): lapses halved 33.3 min (survival
.951 at 🔥0, .877 at 🔥5); lapses doubled **38.7 min** (p90 43.5; survival .814 → .712) (m). The brag stays inside
30-45 min either way.

**How the numbers were tuned** (kept, because each step was a finding):

| step | finding |
|---|---|
| band 5 at 40 survivals, band 6 at 150 (first guess) | brag at 69.2 min for normal: far too late. Thresholds re-read from the survival curve: 2 / 6 / 12 / 21 / 100 |
| ring telegraph 2.5 s, Meteor intervals 5.0 … 2.3 s | slow players survived a heat-0 Meteor Shower 0.35 of the time and reached the brag at 54 min. 3.0 s (the template's minimum) and 6.0 … 2.5 s fixed both |
| no placement rule | 8 naive bots at 🔥5 lost 33 of 1 200 bot-rounds, cornered against the walls. `ExitStuds` 7 added |
| Codex = one entry per (disaster, Heat) | a fast player needed to lose a streak to fill the low-Heat entries (fast took as long as normal). Rows made cumulative |
| practice window = the first 20 s of a disaster | max wait to first time on the island 66.9 s. Widened to 50 s: max 37.0 s |

---

## 3. Environment bands

### 3.1 Trigger: the game's own progress, never time

The progress value is **`survived`**: lifetime counted survivals, server-written to the player's `Survived`
attribute. It only goes up. The game's logic is a story told in sky: **the more disasters you have lived through, the
wilder your world gets, until the sky itself falls, and if you keep going, the dawn after the end of the world.**
The client blends by it with `EnvBands.luau` (plus1-jump, **verbatim**). Every value glides with a 0.6 s half-life
(`EnvBands.approach`), so a survival or a rejoin deep in the ladder never cuts. Lighting is written at most 10 times
a second and only when a value changed. The band name chip shows the band whose threshold you have passed.

Bands are per player and client-only: two players in the same server may see different skies over the same island.
The island, the water, the rings and the Lookout are shared and look the same to everyone.

Because `survived` is an integer, a fade is a number of survivals over which the next band blends in, and each step
glides on the 0.6 s half-life. Each fade is about the last third to half of its gap, so the next sky starts showing
a round or two before its name does. `EnvBands.validate` accepts the fades: every fade ≤ its gap to the previous
threshold (c: 1 ≤ 2, 2 ≤ 4, 3 ≤ 6, 4 ≤ 9, 20 ≤ 79).

### 3.2 The six bands

| # | band | from (survivals) | fade | normal reaches it (median, m) | light | scenery (far ring, 250-450 studs, client) | critters | ambient weather |
|---|---|---|---|---|---|---|---|---|
| 1 | 🏝️ Calm Cove | 0 | – | 0 min | clear morning, ClockTime 9.5, turquoise sea, warm white sun | two palm islets, a sailboat | gulls gliding | faint sea-spray motes |
| 2 | 🌬️ Windy Point | 2 | 1 | 3.4 | bright midday, ClockTime 13.5, cooler, fast clouds | a lighthouse on a sea stack, wind-bent trees on the islets | albatross pairs | white wind streaks |
| 3 | ⛈️ Storm Coast | 6 | 2 | 9.9 | overcast late afternoon, ClockTime 16.5, violet-grey, low fog | a storm-cloud bank with silent lightning, a shipwreck on a reef | storm petrels | drizzle |
| 4 | 🌋 Ember Isles | 12 | 3 | 20.0 | dusk, ClockTime 18.0, amber-orange | a smoking volcano on a far island with an orange lava glow | bats | falling ash and embers |
| 5 | ☄️ **Falling Sky** | 21 | 4 | **35.2** | deep violet night, ClockTime 20.0, kept bright enough to read rings (§15 #2), strong bloom | **a huge cracked comet low over the horizon, far meteor streaks crossing the sky** (always beyond the island, harmless) | fire-birds (golden-orange glow) | drifting sparks |
| 6 | 🌅 New Dawn | 100 | 20 | 168.4 | golden sunrise, ClockTime 6.4, high saturation | a rainbow arc over the sea, flowering islets | butterflies near the Lookout, leaping dolphins | pollen glints |

Every band defines the **same** lighting fields (ClockTime, Brightness, Ambient, OutdoorAmbient,
ExposureCompensation, FogColor, Atmosphere Density/Color/Decay/Haze, ColorCorrection Tint/Saturation/Contrast, Bloom
Intensity). `tests/EnvConfig.spec.luau` (copied from plus1-jump) enforces it. The exact colour values are set in
`Config.Env.Bands` at build time and judged in Studio (§15 #13). They are art, not balance.

### 3.3 The disaster on top of the band

The running disaster is a server-wide **overlay** (`EnvBands.overlay`), weighted 0 → 1 over 3 s at the name and
1 → 0 over 3 s after the disaster ends, so each player's band stays underneath:

| disaster | overlay | effects (client) |
|---|---|---|
| ☄️ Meteor Shower | warm orange haze, saturation up | meteor trails from the radiant, impact sparks and scorch, a camera shake for an impact within 20 studs |
| 🌊 Flood | Brightness × 0.6, blue-grey fog | heavy rain, the water surface, spray at the waterline, lightning bolts on the aimed rings |
| 🌪️ Tornado | green-grey tint, dust haze | the funnel (stacked spinning rings and a dust volume), flying debris, props on its path tossed (client copies; the real props are not moved) |
| 🏚️ Earthquake | brown dust haze | camera rumble while cells drop, falling chunks from every dropped cell (client physics), dust bursts |

### 3.4 Fx and signature particles (checklist §2, from the first build)

* Server, first thing: `Fx.applyLighting(Fx.Presets.Coast)`. `Coast` is a **new preset** in the game's copy of
  `Fx.luau`, equal to band 1's lighting, so the first frame before the client's bands take over is already band 1.
* **The red ring is the signature**: a neon ring that pulses faster as impact nears, the same red for every zone in
  every disaster. Red is the game's only "it hits here" colour: no island palette, band light or disaster overlay
  tints anything red (the warm bands and the Meteor overlay are amber and orange), so a ring never has to compete
  with its background. `EnvConfig.spec` asserts no band or overlay `ColorCorrection.TintColor` has red more than
  0.15 above both green and blue.
* **Heat glows** (anything the player chases glows): an orange-gold flame aura on characters at 🔥1+, its rate
  growing with Heat, and a 🔥N billboard over their head. **Survivors get a confetti burst** (gold, white, teal) on
  the SURVIVED card. Characters with `Survived` ≥ 21 carry a faint amber ember aura for good (the brag, worn).
* Client juice: `FxClient.shake` on a near impact and on quake drops, `FxClient.flash` + `fovPunch` on the SURVIVED
  card and the brag, a soft flash when you are swept out. `FxClient.theme()` on every HUD frame.

### 3.5 Budgets (caps enforced in code, measured headless at every band, every seam and during every disaster with 8 players at 🔥5)

| what | cap | how it is kept |
|---|---|---|
| server Parts | 400 | island columns ≤ 169 + props ≤ 80 + the fixed Parts + rings ≤ `Budget.Rings` 16 (capped in `Strikes.maxLive`, REVIEW-1 F11) |
| client scenery Parts | 500 | ≤ 125 per piece and ≤ 2 pieces per band, two bands cross-faded at a seam; `SkyArt.updatePiece` trims (REVIEW-1 F11) |
| client critters | 10 models | nearest first |
| weather emitters | 2 | `EnvBands.capRates` (plus1-jump's `MaxWeatherEmitters`) |
| disaster emitters | 6 | rain/dust/waterline/funnel, nearest first |
| falling chunks (quake) | 60 | 6 per dropped cell, nearest cells first, each destroyed after 3 s |
| tornado debris | 12 | |
| projectiles | 16 | one per live ring |
| path ribbon Parts | 40 | the funnel's own disc, and per 0.25 s of the 4 s drawn a box and a disc (REVIEW-1 F8), pooled and capped in `World.client` |
| heat auras + billboards | 8 + 8 | one per player |
| PointLights | 6 | lava glow, comet, auras, nearest first |
| Lookout strays | 1 | Hazards.luau's own rule |

---

## 4. Hazards

### 4.1 The disasters are the hazards

The standard's rule ("rare, telegraphed, a red ring marks exactly where a hit can land, never more than one at a
time, a hit costs a little") is written for hazards that interrupt a game. In Disaster Rounds the disasters *are* the
game, so they keep the parts of the rule that make them fair and drop the parts that would remove the game:

| the standard's rule | disasters |
|---|---|
| telegraphed | **yes, all of them**: ring 3.0 s, flood 9 s + 2 s, path ≥ 3.3 s, crack 3.0 s (§2.4, §2.5) |
| the red marks exactly where a hit can land | **yes**: ring, slab + tint, path, cracked cells. Each is drawn from the same numbers the hit test uses (`Zones.luau`), and `check_disasterrounds_zones` asserts points just inside are hit and points just outside are not |
| survivable by a player who reacts | **yes, measured**: the bot survives 100 % at every Heat in every disaster, on the open island, on the crowded plateau and 8-at-a-time (m, §2.8) |
| rare, one at a time | **no**: dozens of rings a round is the genre. Instead the density is capped by `ExitStuds` and `MaxRingCoverage` |
| a hit costs a little | **a hit costs the round and the streak, never progress** (`survived`, `best` and the Codex never go down) |

**Crowded plateau** (m): 8 players at 🔥5 on an 18-cell flood plateau for the 18 s hold: the bot survives 1.000,
normal 0.970. **8 bots at 🔥5 in a Meteor Shower on the open island:** 1.000.

### 4.2 The extra ambient events: strays at the Lookout

These follow the standard's rule in full. **`Hazards.luau` is copied verbatim from plus1-jump with its spec** (take
the working copy at build time and record its sha256; StormGrow §4 notes `Hazards.threatLive` came after the
committed version). Strays are client-only, like plus1-jump's and StormGrow's: they never touch server state.

**Where and why:** on the Lookout, debris from the island's disaster sometimes flies all the way to the deck. It runs
only while you are on the Lookout and not resting, because on the island the disaster is already one long hazard and
the standard forbids two at once.

| rule | value | reason |
|---|---|---|
| interval | **60-90 s of Lookout time** (`IntervalMin/Max`), clock frozen while resting or on the island, never reset | normal players spend 0.27 of their time on the Lookout (m), so one stray per **4.6 min** of play (fast 5.1, slow 3.9) (m). Rarer than the standard's 2-3 min on purpose: the disasters supply a near-miss every few seconds |
| one at a time, telegraphed ≥ 3.0 s, lane locks ≥ 1.5 s before arrival | the template | |
| the red ring is the zone | radius hitRadius + 1.5, drawn on the deck's top face (StormGrow REVIEW-1 F3: a ring at the wrong height is invisible) | |
| a hit | horizontal knock + lift 8 studs/s, `PlatformStand` 0.9 s, shake + flash | a stumble. Lift 8 rises 0.16 studs (c: 8² / (2 × 196.2)), so it never clears the 4-stud rail |
| kind | themed by the current (or last) disaster | |

| kind (disaster) | speed | telegraph | commit | pass | hitRadius | ring | lane length (c) | knock | pitch |
|---|---|---|---|---|---|---|---|---|---|
| ember (Meteor) | 30 | 3.0 | 1.5 | 2.5 | 1.8 | 3.3 | 90 | 32 | 14 ± 6 |
| spray (Flood) | 22 | 3.2 | 1.6 | 2.5 | 2.2 | 3.7 | 70 | 28 | 6 ± 4 |
| plank (Tornado) | 34 | 3.0 | 1.5 | 2.5 | 2.0 | 3.5 | 102 | 34 | 8 ± 6 |
| pebble (Quake) | 26 | 3.2 | 1.6 | 2.5 | 1.8 | 3.3 | 83 | 30 | 18 ± 6 |

`SpreadDegrees` 35, `ViewPitchDegrees` 20, `KindFitDegrees` 25, `MaxRetargetSpeed` 1.5, `AimJitter` 1.2,
`PlayerRadius` 1.5, `KnockLift` 8, `KnockSeconds` 0.9: the template's values. The longest flight is 5.7 s (c: spray or
pebble, 3.2 + 2.5), which sizes Rest's `PendingSeconds` (§5). Players on the Lookout face the island, so the lanes,
which start within 35° of the camera's heading, come from the island side: the debris visibly flies in from the
disaster. **No adaptation of `Hazards.luau` is needed**; the deck is flat ground with a rail, like StormGrow's farm.

---

## 5. Rest

`Rest.luau` is copied **verbatim** from plus1-jump with its spec. Config: `WakeOnMove = true`, `BlockWhileThreat = true`
(both mandatory in `Rest.validate`), `RequireGrounded = true`, **`IdleSeconds = 150`**, `WakeGraceSeconds = 0.4`,
**`PendingSeconds = 8`** (the longest stray flight 5.7 s + 2, rounded up: the template's own rule).

**What a break is:** tap ☕ on the Lookout and your character sits down; the HUD says "☕ On a break — move or tap ☕
to rejoin the rounds". **You are not dropped onto the next island**, the strays leave you alone, and the rounds go on
without you. Move, or tap ☕ again, and you are back for the next drop.

**The genre adaptation, made in the glue and not in `Rest.luau`:** `Rest.luau` says rest must never pause a clock
the player races. A round is one. So:
* ☕ pressed **while you are on the island** is held by the glue as "☕ Break after this round" and handed to
  `Rest.request` when you are back on the deck. It never ends the round early and never removes you from it. A player
  already swept out to the Lookout is not in the round any more, so their ☕ goes straight to `Rest.request`.
* `Rest.update` runs everywhere; its `threat` input is the Lookout strays only (`Hazards.threatLive`). Idle time
  therefore counts on the island too, so an AFK player who is on the island when the 150 s run out is taken off the
  next roster the same way.
* **Server moves are not movement.** `moving` is the root's own horizontal speed above 1 stud/s, but the server bumps
  the Player attribute `MoveSeq` at every drop, practice landing, sweep-out and outro return, and for 1.0 s after a
  bump the glue reports `moving = false, grounded = true`. Without this, the two teleports of every cycle would wake
  every break and reset every idle clock, and an AFK player (still for at most 80 s between teleports, c) would never
  reach 150 s.

**What rest pauses:** your entry into rounds and the Lookout stray clock (frozen, never reset). **What it does not
pause:** the round cycle, which is one clock for the whole server.

**Why it cannot be exploited:**
1. **The roster is frozen before anything about the round is visible.** The next island is built under
   `ServerStorage` during the intermission and parented to `workspace` only after the roster is fixed; the disaster
   is named 4 s after that, and it is an even draw that owes nothing to the rounds before it (REVIEW-1 F4: a "never
   twice in a row" rule leaked which disaster could not come next). A rest request after the freeze applies to the
   next round. Resting therefore cannot be used to skip a disaster you have seen coming, or one you could infer.
2. **Rest earns nothing:** no survival, no streak, no Codex. It freezes the streak, which is what a pause is; there
   is no information advantage to sell it for (point 1).
3. It cannot start in the air or with a stray inbound; the request is queued and the stray still arrives.
4. Moving wakes you, so nothing that needs movement happens while resting.
5. The server trusts the client's rest flag, and that is safe: a client claiming rest only stays off the island; a
   client hiding its rest is only dropped onto it.

**`IdleSeconds = 150`, and why not 20 (plus1-jump) or 90 (StormGrow):** standing still is normal here: a player
swept out early watches the rest of the round. The longest still stretch for an engaged player is 112 s (c: from
landing, 4 s drop + 60 s disaster + 4 s outro + 20 s intermission + 4 s drop + at most 20 s until the first ring at
you forces a step). 150 s is 1.34 × that, and two full cycles (176 s, c) of AFK can never pass without it. StormGrow REVIEW-1 B2 is the warning: an idle
rest that fires during normal play changes the game.

---

## 6. The brag moment and the long-term goal

**The brag: "☄️ THE SKY IS FALLING"**, at 21 survivals. Modelled (m): **normal 35.2 min** (p10 32.6, p90 38.6), fast
32.7, slow 41.8, normal with lapses doubled 38.7. Inside 30-45 min for all of them. What happens: a title card with a
white flash and an FOV punch; over 4 s the cracked comet rises over the horizon and the far meteor streaks begin;
your character gets the ember aura for good; a server-wide toast "☄️ *Name* has survived 21 disasters. Their sky is
falling." It plays only when you cross the threshold during play, after `Loaded`. A player who joins already past it
gets a quiet "☄️ Falling Sky" chip instead (plus1-jump's first-card rule).

**The skill brag: 🔥 MAX HEAT**, the first time a streak reaches 10. Server toast "🔥 *Name* hit MAX HEAT: 10 in a
row". Modelled: normal **28.8 min** median (p10 14.8, p90 73.9), fast 15.5, slow 97.8 (59 % within 4 h) (m).

**The long-term goals:**

| goal | modelled (m) |
|---|---|
| the Codex 24/24 (survive every disaster at 🔥5) | normal 1.3 h median (p10 0.5, p90 3.3), fast 0.6 h |
| band 6 🌅 New Dawn, 100 survivals | normal 168.4 min (2.8 h), fast 155.7, slow 200.4 |
| **your best streak on the board** | open-ended: normal median 13 at 1 h and 17 at 4 h, fast 22 and 34 |

---

## 7. The highscore board

**Metric: best streak (most counted rounds survived in a row) up to `Config.Board.StreakCap` = 25, ties broken by who
reached it first** (REVIEW-1 F5: past the cap the time is when 25 was first reached).

Why a script cannot inflate it:
* **Only the server's round-end evaluation raises it**, from the server's own hit tests on the server's view of the
  root. No RemoteEvent, attribute, `Touched` or ClickDetector can add a survival (§10).
* **Teleporting, flying and speed hacks do not help**: every hit test is 2-D or decided by the cell under you, and the
  movement guard sweeps out anyone moving faster than walking (§2.7).
* **The rate is capped by the round clock:** at most one per 88 s cycle, 40.9 per hour (c). A script that dodges
  perfectly from the replicated red never misses, and the clock alone does not bound it (REVIEW-1 F5: the build's own
  bot survived 40 of 40 rounds, best 40 in 59 minutes). **The board therefore counts a streak up to 25**, a run a fast
  human makes in 43 % of one-hour sittings and 82 % of two-hour ones (model): a script reaches what a person can and
  nothing more. Nothing beyond the telegraph horizon replicates (§8.3).
* Leaving, resetting or crashing out of a round counts as being swept out, so a streak cannot be parked.
* The tie-break time is the server's time of the round end.

**Storage** (the standard's format, plus1-jump's `Board.luau` verbatim): OrderedDataStore
`DisasterRounds_Streak_v1`, key `u_<userId>`, value `Board.encode(best, reachedAtUnix)` =
`best * 2e9 + (2e9 - reachedAt)`. `Board.keepHigher` inside `UpdateAsync`, so a stale server never lowers it and a
later equal streak never replaces the first. Written only when `best` rose, **only from a session that holds the
save lock, and only the `best` that a profile save has already landed** (StormGrow REVIEW-1 A5). `MaxMetric` 4e6
keeps every value exact under 2^53 (Board.luau); at 40.9 per hour that is 11 years of nonstop rounds (c).

**Public view:** top 10, cached 60 s. **Friends view** (on demand): plus1-jump's design (§2.7). You are always in your
own view. **Empty state:** "None of your 7 friends has survived a round yet. Invite one and see who lasts longer!"
**No friends:** "No Roblox friends yet. Friends you add show up here, ranked against you." **Failure:** "Couldn't
load your Roblox friends right now. Try again in a minute."

**In the world:** a physical board, 12 × 8 studs (StormGrow REVIEW-1 B5 measured a 10 × 6.6 board at 15 studs as
13 pt on a 360-pt phone; this one is a little larger at a similar distance), at the north end of the Lookout deck,
16 studs from the spawn and facing it, with a ProximityPrompt "🏆 Public / Friends" (per player; each player sees their own view through a
SurfaceGui in their PlayerGui with `Adornee` = the board). Rows: rank, name, 🔥 best streak; your own row pinned at
the bottom. Names from `GetNameFromUserIdAsync`, cached, never stored. `leaderstats`: `Streak` and `Best`.

---

## 8. Data model

### 8.1 What persists: DataStore `DisasterRounds_v1`, key `u_<userId>`, one document per player

```
{
  v        = 1,
  survived = <int >= 0, never decreases>,            -- the band progress value
  played   = <int >= 0>,                             -- counted rounds; drives the first-rounds hints
  streak   = <int >= 0>,                             -- kept across sessions; 0 after any elimination or a mid-round leave
  best     = <int >= 0, never decreases>, bestAt = <Unix s>,
  codex    = { meteor = <-1..5>, flood = <-1..5>, tornado = <-1..5>, quake = <-1..5> },  -- hottest Heat survived
  lastEnd  = { reason = "left" | "reset" | "guard" | "<kind>", streak = <int> },          -- told once on rejoin
  session  = { token = "<GUID of this server-session>", until = <Unix s> },
}
```

* **String keys only** (checklist trap: sparse integer keys come back as strings). The Codex is four named numbers,
  not a bitset or an array.
* **Load normalises:** negative or non-integer counters are clamped; `best` below `streak` is raised to `streak`;
  Codex values outside -1..5 are clamped; unknown Codex keys are dropped. A record with a higher `v` is shown
  read-only and never written (StormGrow REVIEW-1 A4). Each fix logs a warning.
* **Size:** 265 bytes of JSON for a worst case with six-digit counters (measured on a sample record).
* **One-time grants: none in v1.** No codes, no daily rewards. The default profile is written once, by the first
  successful locked save.

### 8.2 What is server-only

| state | where | why |
|---|---|---|
| every profile, authoritative | the server script's tables | the server is the only writer |
| **the next island**, while it is built | **`ServerStorage.NextIsland`**, parented to `workspace.Round` only after the roster freezes | anomaly-observatory `CLAUDE.md`, "ServerStorage, not the zone": nothing about a round may be visible while players can still choose to sit it out |
| **the disaster RNG** | one `Random.new()` per round (entropy-seeded by Roblox), separate from the map's `Random.new()` | fork-tower `REVIEW-4.md` trap 1: the map is visible, so whatever builds the map must not also predict the disaster. Nothing public seeds either, and **no seed exists in any replicated place** |
| the disaster plan beyond its telegraph | server tables: which kind comes next, future crack batches, the tornado's target and its path beyond 4 s, ring timers | fork-tower trap 2 (a stream pinned by what it reveals): each crack batch, path segment and ring timer is drawn at its telegraph moment from the round's server-only `Random`, and a new `Random` is made every round. What a round shows of it is a few heavily processed choices (shuffled cell picks, turn targets, ±20 % jitter); recovering the generator's state from those is not a practical attack, and it would buy at most a few seconds' notice of threats that are drawn 3-4 s ahead anyway. A ring's centre is just where you stood |
| movement-guard histories, rate-limit clocks, session tokens, write queues, board and name caches | server tables | none of it needs to replicate; the token must not |

Never an attribute or an Instance under `workspace`, `ReplicatedStorage` or the player for any of this.

### 8.3 What replicates, and why it is safe

**The game has no hidden answer to leak: everything that will hurt you is shown before it does.** The only rule is
that nothing is shown *earlier* than its telegraph.

| replicated | contents | why it is safe |
|---|---|---|
| `workspace.Round` (Folder) attributes | `Phase`, `PhaseEnds`, `RoundId`, `Style`; `Kind` **set at the name, never earlier**; flood: `WaterFrom`, `WaterTo`, `RiseAt`, `RiseEnd` of the current rise only, set when its warning starts; tornado: `Path` = the funnel's points for [now − 0.25, now + 4.0] at 0.25 s, updated at 4 Hz | all of it is drawn on screen anyway; none of it reaches past the telegraph |
| island cell Parts | geometry; attributes `Level`, `CrackAt` (set when the cell starts cracking) | visible geometry and a visible red crack |
| ring Parts in `workspace.Round.Rings` | `ImpactAt`, `Radius`, `TargetId`, `Theme` | the ring is the telegraph |
| `workspace` attribute `ServerNow` | the server clock, 1 Hz | public by design |
| `ReplicatedStorage` | `Config` and the pure modules | the rules and the odds are public by design; no seed exists |
| Player attributes | `Survived`, `Streak`, `Best`, `Heat`, `Codex` (four numbers as "m,f,t,q"), `InRound` ("" / "counted" / "practice"), `Resting`, `MoveSeq` (bumped at every server move, §5), `Loaded`, `Saving` | the player's own progress, harmless to others; attributes replicate with the Instance, so there is no RemoteEvent join race (grow-a-crystal review finding 1) |
| `leaderstats` | `Streak`, `Best` | the player list |
| RemoteEvents, server → client | `Toast(text)`, `Card(kind, data)`, `Board(mode, rows)` | text, result cards and public board rows. **Exactly one client connection each** (in `Hud.client`) |
| RemoteEvents, client → server | `JumpIn()`, `SetRest(on)` | requests, validated (§10). Nothing a client sends can grant anything |

`check_disasterrounds_wire` sweeps every replicated property, attribute and remote payload each tick of several
rounds and fails on: a session token; `Kind` (or any kind-specific Instance) before the name; a `CrackAt` earlier
than 3.0 s before its drop; a path point more than 4.25 s ahead; any water target beyond the current rise.

### 8.4 Saving rules (the standard, applied)

* Every DataStore call is pcall'd. The load uses `UpdateAsync` and takes the lock (`session.token`, `until = now +
  300`). Retries and read-only recovery as in §2.7. **A failed load never writes a default profile over real data.**
* **Every write carries the owner token**: the transform returns nil (abort) unless `old.session.token == myToken`.
  That includes the release on leave (`until = 0`), because a late release must never unlock a record the next session
  already holds (fork-tower `REVIEW-4.md` §10).
* A round's result (survival or elimination) is saved in the round-end write; a leave during a round writes the
  elimination in the leave's write. A crash without `BindToClose` loses that round's result either way.
* The profile is one document, so a survival's `survived`, `streak`, `best` and Codex land together or not at all.

---

## 9. Spawn placement (`robloxemu/SPAWN-ORDER.md`)

* There is **one SpawnLocation, `LookoutSpawn`** (6 × 1 × 6, `Enabled`, `Neutral`), on the Lookout deck at
  (-74, 28.5, 0), facing +X toward the island. The deck is 20 × 36 studs (x -82 to -62, z -18 to 18), floor top
  y = 28, 12 studs above the island's highest top. The spawn is 22 studs from the island's west edge and 74 from its
  centre (c), so the whole island is in front of a new player's camera. The deck has a visible 4-stud rail and
  invisible walls 20 studs tall, because a default jump clears the rail.
* `PlayerAdded` sets `plr.RespawnLocation = LookoutSpawn` **synchronously, before any yield** (before the profile
  load). The engine then places the character on it at every spawn and respawn: SPAWN-ORDER §3's preferred pattern,
  so there is no race to lose. Nothing writes a CFrame inside `CharacterAdded`.
* **Facing:** if the engine does not keep the spawn's yaw (§15 #10), the handler waits until `char.Parent ~= nil`
  (bounded, 300 frames of 1/60 s) and then turns the character toward the island: SPAWN-ORDER §3's second pattern.
* **Drops and returns are not spawns.** The round loop moves characters with `char:PivotTo` at the drop, at a
  practice landing, when a player is swept out and at the outro, always on a character that is already parented. A
  roster player whose character is not in the world at the drop is skipped and can jump in for practice.
* **Check** (`check_disasterrounds_spawn.luau`): eight joins all land on `LookoutSpawn` (XZ within 3 studs, above the
  pad, per SPAWN-ORDER §7); a respawn lands there again; at a drop every roster player stands on their own assigned
  cell (XZ within 2 studs, above its top); a swept-out player and every outro return land on the deck; the only
  SpawnLocation in the place is `LookoutSpawn` and it is enabled.

---

## 10. Anti-exploit model

| attempt | what stops it |
|---|---|
| teleport or speed hack to escape a zone | the movement guard: more than 28 studs in any 1.0 s, or outside the island box, sweeps you out ("Movement check failed"). Server teleports reset it |
| fly or hover over water or a hole | the hit test is the cell under your root, not your height |
| fly or noclip off the island (over the sea, inside the guard's box) | off the island is the sea in every disaster: swept out after 0.6 s (REVIEW-1 F2; the first build let a client parked in a corner survive every meteor, tornado and quake round) |
| noclip into terrain | the same: hit tests are 2-D plus cell state, and the box check catches leaving the island |
| dodge perfectly from replicated red | it plays like a perfect human and never misses; the board counts a streak only up to 25, a run a fast human makes (§7, REVIEW-1 F5) |
| predict the next disaster, crack or path | no seed replicates; the disaster RNG is separate from the map's; each batch, segment and ring is drawn at its telegraph moment (§8.2) |
| read the disaster from the map | every map supports every disaster (§2.2), and the map is hidden in `ServerStorage` until the roster freezes |
| rest to skip a bad round | the roster freezes before the island is visible; a later request applies to the next round; the next disaster is an even draw, so the last one says nothing about it (§5, REVIEW-1 F4) |
| leave, reset or crash out to save a streak | each counts as being swept out, saved at once |
| hop servers for an easy round | nothing about a round is known before its drop in any server |
| fire `JumpIn` to farm | a practice round grants nothing; the request is refused outside the window, to the roster, to the swept out and twice in a round, with a reason (§12.3) |
| fire `SetRest` | it only removes you from the next roster, or puts you back on it |
| write attributes from the client | client writes do not replicate, and the server never reads its own values back from Instances |
| play two servers at once | session lock with an owner token on every write (§8.4) |
| inflate the board | only round-end survivals raise `best`; written from saved values, by the lock holder, max-merged, at most once a round (§7) |
| AFK or a jiggle-bot farming survivals | every round aims a ring at every player within its first 20 s (c), so a player who does not react is swept out in every disaster; 150 s still puts you on a break (§5) |
| push other players into the red | characters do not collide with each other (a `PhysicsService` collision group, pcall'd because robloxemu has no PhysicsService; §15 #9) |
| jump off the Lookout onto the island | invisible walls 20 studs tall around the deck; below y = −6 you are returned to the deck |
| delete strays on the client | strays are client-only by design; deleting them saves a 0.9 s stumble and changes nothing on the server |

---

## 11. The first 60 seconds of a new player

Targets. `check_disasterrounds_firstmin.luau` walks them through the real server and HUD. Times marked (m) are
modelled for a normal player over a random join phase.

| time | what happens | on screen |
|---|---|---|
| 0 s | `PlayerAdded`: `RespawnLocation = LookoutSpawn` before any yield; the profile load starts | "Loading…" chip until `Loaded` |
| ≈ 0-1 s | the character lands on the Lookout, facing the island | the island below, or the round in progress on it |
| joined in the intermission | the countdown: "Next round 0:14 — you're in! Survive the disaster." and "Red always shows where it hits." | wait ≤ 20 s |
| joined during a drop or the first 50 s of a disaster | a big **▶ Jump in (practice)** button at the top centre, and under it what is happening: "That's a FLOOD — get above the red line" | **first time on the island: p50 3.0 s, p90 28.2 s, max 37.0 s (m)** |
| landing | "Get ready…" (a counted drop) or "Practice round — it won't count" | |
| the name | card: "☄️ METEOR SHOWER — Step out of the red rings" | |
| **first ring at you** | **Meteor round: median 13.2 s after joining (p90 39.7); other disasters: 19.5 s (p90 44.9) (m)** | the ring pulses under you; banner "⚠️ MOVE — a ring is under you" |
| the first dodges | the meteor lands where you stood | "Dodged!" pops for your first 3 dodges only: it confirms the rule, then gets out of the way |
| round end | "SURVIVED! 🔥 streak 1" with confetti, or "☄️ Hit by a meteor — next round in 0:24" | the band 2 sky after your second survival: 3.4 min median (m) |

Hints come from state (`played`, `Loaded`, the phase) and need no tutorial flag: a returning player never sees them.

---

## 12. HUD (phone first)

### 12.1 Layout
* **A root Frame owns the `UIScale`**, sized `1/scale`. `Responsive.luau` copied verbatim. Layout re-runs on
  `ViewportSize` and `TouchEnabled` changes.
* **Top left** (not tappable): 🔥 Heat with "streak 7 · best 9", the band chip ("⛈️ Storm Coast · 🌋 at 12"), 🏆
  survived.
* **Top centre:** the phase chip ("Next round 0:14" / "🌊 FLOOD · 0:42" / "☕ On a break"), the rule line under it,
  and under that, when allowed, **▶ Jump in (practice)**. The threat banner ("⚠️ MOVE — a ring is under you", "🌊
  Water rising in 6") sits below; it is not tappable.
* **Top right:** ☕ Rest and 📖 Codex.
* **Centre:** cards (the name, SURVIVED, swept out, the brag). Not tappable, gone after 2.5 s: long enough to read
  six words, short enough not to cover the first ring (≥ 5 s after the name).
* **Codex:** a centred modal, 4 disasters × 🔥0-5, filled cells lit, with "Survive a Tornado at 🔥3 to fill this".
  Opening it hides every other panel, so no two visible panels overlap and rule 4b holds without an exception.
* **Nothing tappable in the bottom-left or bottom-right**, and nothing tappable at the bottom at all. Every tap target
  ≥ 44 screen px on touch.
* **Gate:** `robloxemu/check_disasterrounds_hud.luau` runs `hudcheck` with **`overlap = true`** across its
  viewports, with a warmup that shows each card, the Jump-in button, the threat banner and the Codex in turn.

### 12.2 In the world
Heat billboards over heads (🔥N), the board's SurfaceGui, the ring, slab, path and crack visuals (all
`CanQuery = false`, so nothing in the world ever blocks a tap or a camera ray).

### 12.3 No silent no-ops (every refusal says why)
Jump in: "You're already on the island" · "You were swept away this round — next round in 0:23" · "Too late to jump in
— next round in 0:23" · "You're on a break — tap ☕ to come back" · "No safe spot to land right now — try again in a
second" · "One tap is enough". Rest: "☕ Break after this round" · "☕ On a break — move or tap ☕ to rejoin the rounds"
· "Back in! Next round in 0:12". Round: "Movement check failed: you moved faster than walking. Round lost." · "You
reset — round lost." · on rejoin after a mid-round leave: "You left during a round, so your streak ended at 7." Board:
"One switch a second." Save: "⏳ Your save is open in another server. Waiting for it…" · "Progress here won't save:
your save is open in another server." · "Couldn't load your profile — nothing will be saved this session. Rejoin to
try again."

---

## 13. Build plan and gates (for the builder)

**Layout** (deep-vein's): `default.project.json` maps `src/server` → ServerScriptService, `src/client` →
StarterPlayerScripts and `src/shared` → ReplicatedStorage, and **pins `Workspace.StreamingEnabled = false`**
(StormGrow REVIEW-1 B4). Plus `tests/*.spec.luau`, `README.md`, `CLAUDE.md`, `EYECANDY.md`, `MARKETING.md`, and a
`.gitignore` with `publish_*.bat` / `publish_*.sh`. Shared modules take their dependencies as arguments;
`require("./X")` works only in the CLI. Randomness is always injected as `rand(): number`.

| file | kind | spec (TDD, failing test first) |
|---|---|---|
| `Config.luau` | every tunable in §2-§5 | `EnvConfig.spec`: bands share fields and fades validate; `Hazards.validate` and `Rest.validate` pass; `PendingSeconds` ≥ longest stray flight + 2; `ExitStuds` > ring radius (7 > 4.5, so a lone ring always passes the placement rule); `IdleSeconds` > the 112 s longest still stretch (§5); `Config.Shots.ForceKind`, `ForceHeat` and `IslandSeed` are nil in `src/` |
| `MapGen.luau` | generate, validate, flood escapes, drop cells, styles and props | `MapGen.spec`: 1 000 seeds: one-level steps, ≥ 18 high cells, no flood traps, escape ≤ 80, accept rate ≥ 90 %, props non-colliding, drop cells spaced |
| `Round.luau` | phase clock, roster freeze, early end, drop-in window and eligibility | `Round.spec` |
| `Zones.luau` | the red rule: ring/slab/path/crack membership, `LagGrace` judging, `exitDistance` | `Zones.spec`: just inside hit, just outside safe, for all four; ties go to the dodger |
| `Strikes.luau` | ring schedule by kind and Heat, jitter, first-ring delay, `ExitStuds`, coverage cap | `Strikes.spec`: rings per round within 5 % of §2.4; an idle player is always ringed by 20 s |
| `Flood.luau`, `Tornado.luau`, `Quake.luau` | plans and hit tests | their specs: timelines, the 4 s horizon, turn limit, quake eligibility and the cap |
| `Guard.luau` | the movement guard | `Guard.spec`: a 16 studs/s walk with jitter never trips; a 30-stud teleport does |
| `Progress.luau` | streak, Heat, survivals, Codex, bands, profile default and normalise | `Progress.spec`: string keys only, every rule in §2.6 and §8.1 |
| `Board.luau` | **verbatim** from plus1-jump | its spec, copied |
| `EnvBands` / `Hazards` / `Rest` / `Fx` / `FxClient` / `Responsive` / `Rng` | **verbatim** copies, sha256 recorded (`Fx` gains the `Coast` preset) | their own specs, copied |
| `tests/Pacing.spec.luau` + `tests/RoundModel.luau` | this file's model rebuilt on the real modules | asserts: normal brag in 30-45 and within 5 min of 35.2; fast and slow medians inside 30-45; every band ≥ 2 min; band 6 < 4 h; Codex < 4 h for normal |
| `src/server/Main.server.luau` | authoritative glue | the headless checks below |
| `src/client/Hud.client.luau`, `World.client.luau` (rings, water, path, cracks, debris), `Sky.client.luau` (bands, overlays, scenery, critters, strays, rest) | display | the headless checks below |

**Headless checks** (`robloxemu/check_disasterrounds*.luau`; rebuild the bundle before every run with
`py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau`). The emulator has no physics, no
`Raycast`, no `LoadCharacter` and no `PhysicsService`, so the game never depends on them for an outcome; checks walk
characters by moving their root, as the other checks in the repo do.
`check_disasterrounds` (**the walk**: join → Lookout → drop → the name → a scripted player that reads only the
replicated red dodges every ring, path, crack and rise → SURVIVED, streak 1 → several rounds → Heat 1 → stand still
and be swept out → streak 0, `best` kept → practice drop-in counts nothing → leave mid-round → rejoin: streak 0,
"you left" toast, survived/best/Codex kept), `_spawn` (§9), `_firstmin` (§11), `_hud` (§12), `_env` (bands follow
`Survived`, glides, overlays, budgets at every band, seam and disaster), `_zones` (§2.3 and §4.1, all four), `_fair`
(8 bots, 0.6 s reaction, 200 islands × 4 disasters × 🔥5: zero hits; an idle player is hit in every round by 23 s),
`_rest` (§5: no drop while resting, an in-round request applies after the round, the stray clock freezes, toggling
does not thin strays, a server move neither wakes a break nor resets the idle clock, an AFK player is dropped into at
most 2 rounds (c: a 150 s window holds at most 2 drops 88 s apart)), `_strays` (the ring on the deck, the rail stops the knock), `_guard`, `_jumpin`, `_board`
(write only on improvement and only saved values, max-merge, caches, the failure path), `_save` (lock, owner token on
release, read-only and takeover, a failed load writes nothing, a newer version is never written), `_wire` (§8.3).
Every new assertion is mutation-tested with a control, as in SPAWN-ORDER §6.

---

## 14. Ship documents (drafts; the builder re-checks every claim against the code)

### 14.1 Store text (for `README.md`; 948 characters, ASCII only, measured on this draft)
```
Every round the island is new, and so is the disaster: a meteor shower, a flood, a tornado or an earthquake. Be standing when the minute is up and you survived.

One rule covers them all: red shows exactly where it hits. Step out of the red ring before the meteor lands. Get above the red line before the water does. Stay off the red path and the tornado misses you. Get off the red cracked ground before it falls.

Survive rounds in a row and your Heat goes up: more of the danger is aimed at you, and everyone can see your flame. One hit and you are out until the next round.

Every disaster you survive changes your sky, from a calm cove to a sky that is falling, and later a new dawn. The leaderboard ranks the longest streaks, for everyone and for your friends. The Codex keeps the hottest Heat you have survived for each disaster.

Up to 8 players. Need a break? Sit down on the Lookout and the rounds go on without you.

Nothing costs Robux.
```

### 14.2 Thumbnail shots (1920 × 1080, for `EYECANDY.md`)
Staging for all: a shots place from `rojo build`, Studio API access off so nothing reaches real saves, and in that
place's own `ReplicatedStorage.Config` only: `Shots.ForceKind`, `Shots.ForceHeat`, `Shots.IslandSeed`. Set the band
from the command bar (Server): `plr:SetAttribute("Survived", n)`; the server rewrites it only at a round end.
1. **"Step out of the ring"**: Meteor Shower, 🔥4, band 5. Camera 4 studs up, 14 studs behind an avatar mid-step out
   of a red ring, the flaming meteor about 1 s from impact, two more rings nearby, the cracked comet on the horizon.
2. **"Get above the line"**: Flood at the second rise, band 3. Aerial three-quarter view from 70 studs: water over
   the beach and level 1, the red slab at the next height, players crowding up the terraces under the storm bank.
3. **"Off the path"**: Tornado, band 4. Ground camera 2 studs up, the funnel 15 studs away, the red path under it, an
   avatar diving off the path, debris in the air, the volcano behind.
4. **"The ground gave way"**: Quake at its 6th batch. A red cell dropping in chunks, an avatar jumping to the next
   cell, holes showing the sea.
5. **"New Dawn"**: band 6, the Lookout from the island side at sunrise, the rainbow over the sea, survivors waving.

### 14.3 Clips (7-15 s, 1080 × 1920, for `MARKETING.md` / `tools/film_game.py`)
`tools/film_game.py` may stage only the character's start (a server teleport before recording), the camera and
in-game codes; it never edits the game's numbers or fakes progress. So every clip below is the normal game, filmed
by **waiting for the right disaster** (each round is one of the three kinds that did not just run, so a given kind
comes within 3 rounds, 4.4 min, with probability 0.70, or 0.56 when it just ran; c: 1 − (2/3)^3 and 1 − (2/3)^2) and
recording from a stated second of the disaster.
MAX HEAT and the Falling Sky need 10 and 21 real survivals; they are thumbnails (§14.2), not clips, until the night
shift's own play reaches them.
1. **Two rings** (12 s, Meteor Shower, from second 5): two rings land at the avatar's feet, two sidesteps, each
   meteor hits where it stood. At 🔥0 the interval is 6 s, so 12 s holds two.
2. **Water's rising** (12 s, Flood, from second 2): the first red slab appears, the avatar runs up two terraces, the
   water swallows the beach behind it.
3. **It turned toward me** (10 s, Tornado, solo): stand in the open; the path bends onto the avatar (half the funnel's
   targets are a player, and solo that is you), a sidestep at the last second, the funnel passes.
4. **The ground gave way** (9 s, Quake, from second 2): the avatar's cell cracks red; it steps to the next cell as
   its old one drops in chunks into the sea.
5. **Jump in** (10 s): join mid-round, tap ▶ Jump in, land on the island, the first ring arrives.
6. **Survived!** (8 s): the last 5 s of any round and the SURVIVED card with confetti.
7. **Swept away** (7 s, Meteor Shower): stand still in a ring; the hit, the whoosh, the Lookout.
8. **The sky changes** (12 s): a fresh profile's second survival (3.4 min median, m): the card, and the sky gliding
   from Calm Cove to Windy Point.

---

## 15. Needs Studio (only real rendering, input, network and live services can settle these)

1. **Jumping 4-stud steps** on a phone (jump button) and on PC; whether a running jump crosses a one-cell (8-stud)
   hole, which the 0.6 s flood/hole grace assumes; how often a player misses a step while fleeing a flood.
2. **Ring readability** on every style's top materials and in every band's light, especially band 5 at night and band
   4 at dusk; a ring that straddles two levels; the red against ochre sandstone and against lava-orange light.
3. **Water**: translucency, the red slab at the coming height, the red tint on cells about to flood, on a phone.
4. **The tornado**: funnel look, the red path on uneven terraces, debris frame time.
5. **Quake drops**: falling chunks (client physics) frame time; crack readability; holes visibly open to the sea.
6. **Meteors from the radiant**: on screen from the default camera at the usual pitch; lightning and boulders the
   same.
7. **`PivotTo` drops and returns**: camera snap, character state after the move, whether a drop mid-jump misbehaves.
8. **The movement guard on a real network**: false positives under jitter and lag spikes at 28 studs per 1.0 s; log
   every trip for several live rounds before trusting it.
9. **No player-player collision** (collision group): nobody can be pushed into the red.
10. **Spawn yaw** on `LookoutSpawn`; whether the post-parent facing write looks like a snap.
11. **Rest's sit** (`Humanoid.Sit` without a seat): does it replicate; does moving wake it as designed.
12. **Lookout strays**: lanes start on screen with the camera facing the island; the knock with `PlatformStand`; the
    rail and the invisible walls.
13. **Every band's look and every disaster overlay**: exposure, fog against Atmosphere, bloom in band 5, the far
    scenery at 250-450 studs (culled at low graphics quality? if so, closer and smaller).
14. **The HUD on a real phone**: notch and safe area, the Jump-in button, card text length, 🔥 billboards.
15. **Frame time** on a low phone: 8 players at 🔥5 in a Meteor Shower (16 rings and projectiles), and a quake's
    debris.
16. **Live services**: OrderedDataStore and `GetFriendsAsync` with real friends and throttles; the session lock across
    a fast server hop; `BindToClose` voiding a round.
17. **Server-wide toasts** (MAX HEAT, Falling Sky) in a full server: exciting or spammy.
18. **Sound** needs chosen assets (meteor whistle, flood siren, tornado roar, quake rumble, survive chime). v1 is silent
    until they are picked.
19. **Being swept out**: does the whoosh and the move to the Lookout read as "swept away" or as a glitch, for the
    player and for others.
20. **Publish settings**: `MaxPlayers = 8`; `StreamingEnabled` false (also pinned in the project file).

---

## 16. Cut from v1, and why

| cut | why |
|---|---|
| physics deciding who is hit | unfair (the red would not be the truth) and untestable headless (robloxemu has no physics or `Raycast`). Physics is presentation only |
| double disasters, the tornado splitting in two | the fairness proof (the bot never hit) would have to cover every pair. Two funnels are the first v2 candidate |
| more disasters (lightning storm, blizzard, volcano, acid rain, sandstorm, tsunami wave) | four disasters with four different rules, done well. Each new one needs its own red rule and its own bot proof |
| a health bar or shields | one hit and out is the genre's tension; Heat already scales difficulty, and heat 0 is gentle (normal 0.910) |
| walkable buildings, stairs, interiors | the reachability and flood-escape proofs are on a height grid; buildings would need a pathfinder in `MapGen` |
| coins, a cosmetic shop, gear (balloons, coils) | no currency means no prices to balance and nothing pay-to-win. Cosmetic trails for coins are a v2 candidate |
| voting on maps or disasters | voting lets a server avoid a disaster; it also needs UI and a timer |
| a spectator camera | the Lookout already overlooks the island |
| rebirth or prestige | streaks reset by themselves; the Codex and New Dawn carry the long term |
| promo codes, daily rewards | one-time grants need an atomic flush; v1 needs none |
| gamepasses or anything that costs Robux | the owner's rule for v1 |
| bot detection beyond the movement guard | a legal-speed perfect dodger is indistinguishable from a perfect human; it is rate-limited by the round clock (§7) |
| intensity ramps within a round | Heat already scales; a flat rate inside a round keeps the red rule's timing simple to test |
| island size by player count | one size, proven once |
| music and sound | needs assets (§15 #18) |

## 17. Deviations from the radar brief (the owner may veto any of these)

1. **"Physics-driven hazards"**: physics is presentation (client debris, falling chunks); every outcome is computed
   from telegraphed red zones. Reason: fairness (the standard's red-ring rule) and server authority.
2. **The procedural map is a terraced height grid** (13 × 13, three styles), not free-form structures.
3. **Four disasters** in v1.
4. **The board ranks best streak**, not total survivals: totals grow with hours played, streaks with skill.
5. **Eight players per server.**
6. **The board counts a best streak up to 25** (REVIEW-1 F5). Without a cap a script that reads the replicated red
   tops the board in about 25 minutes and climbs 41 an hour for as long as it runs. The number is the owner's to set
   (`Config.Board.StreakCap`; `math.huge` restores the uncapped board).

## 18. Self-review (done before handing over)

* **Placeholders:** none. Band colour values are left to build time and Studio on purpose (§3.2, §15 #13), because
  they are art, not balance; prices are absent because v1 has no currency (§2.6).
* **Contradictions checked:** cycle 20 + 4 + 60 + 4 = 88 s everywhere (§2.1, §2.8, §7, the model). Ring 4.5 studs /
  3.0 s / 0.6 s pass in §2.4, §4.1 and the model. Meteor 6.0 … 2.5 s and others 15 … 5.0 s in §2.4 and the model.
  Heat = floor(streak / 2), max 5 at streak 10, in §1, §2.4 and §6 (the store text says only that it goes up). Bands
  2 / 6 / 12 / 21 / 100 in §2.8, §3.2, §6 and the model. Flood 3 rises, 9 s + 4 s, levels 3-4 dry, ≥ 18 high cells
  in §2.2, §2.5, §4.1. `ExitStuds` 7 and coverage 0.25 in §2.4 and the model. Earliest hit 4.5 s (tornado, 20-stud
  touchdown rule) in §2.1 and §2.5. `IdleSeconds` 150 against a 112 s longest still stretch, and `PendingSeconds` 8,
  in §5. `MaxPlayers` 8 in §2.2, §3.5, §14.1, §15, §17. Leaving mid-round = being swept out in §2.6, §7, §8.1, §10,
  §12.3. Store text 948 characters (measured with Python on the exact block in §14.1).
* **What the model does not cover**, so the build must measure it: the early end (§2.1, it only shortens waits); the
  tornado's 20-stud touchdown rule (it only removes early hits); rings and global threats in the same moment (the
  model multiplies their survival as if independent; `_fair` measures them together); terrain while dodging rings
  (the ring model is flat ground); walking into a hole by mistake; the guard's false positives; a real player's
  reading of the red.
* **Model files:** `design/pacing_model.py` sha256
  `69c2b2dc52e1d2dedec19e7199936048fba39e1a24d2c4c58052dddfd905bbcd`; `design/model-output.txt` sha256
  `4d556cd1448c4f2787b1db697e076ed53eb907737b2a39bcbb8c93ca5fce2b5f`. A second full run printed a byte-identical
  output (seeded).
* **Known limits kept on purpose:** a disconnect during a round counts as being swept out (the server cannot tell it
  from quitting); a server crash without `BindToClose` loses that round's result; a scripted perfect dodger reaches
  the board like a perfect human would, at one streak per round (§7). (The board's encoding is not a limit: Board.luau
  notes it stays exact for reach times up to 2065-01.)
