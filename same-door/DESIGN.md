# The Same Door: design spec (v1)

Status, 2026-09-30: **spec only. No game code exists yet.** Nothing is committed, pushed, published or
opened in Studio. Source concept: `docs/game-radar/2026-09-23-roblox-game-radar.md`, section 3
("The Same Door: Daily Seed Dungeon Speedrun"), ranked #3 (score 7.8). Finish line:
`docs/complete-game-standard.md`. Build recipe and traps: `docs/new-game-checklist.md`.

**Build note, 2026-10-01 (after the first adversarial review, `REVIEW-1.md`).** This file is the design
stage's spec and keeps its numbers. The build moved some of them: P is now the tight line in the
whole-run check's own geometry (§3.2, §6.1), so the medals are 1.71 / 1.33 / 1.18 P; the record is
version 2 in `SameDoor_Days_v2`; the movement windows carry a 0.4 s stall (§11). `CLAUDE.md` ("Where the
build differs") has each change and its measurement.

**Where the numbers come from.** Every number below carries a tag:

| tag | meaning |
|---|---|
| **[M]** | measured with the throwaway model in `design/measure/` (luau CLI; how to rerun in §20). Model numbers hold *under the model's written-down assumptions* (§6.3), not for real players |
| **[R]** | taken from a sibling game in this repo, file named |
| **[D]** | Roblox documentation, fetched 2026-09-30 (create.roblox.com, data store limits page) |
| **[C]** | a design choice; the reason is given next to it |
| **[S]** | provisional until Studio measures it; it is on the needs-Studio list (§19) |

---

## 1. The core loop

Every UTC day the dungeon rearranges itself around the same old Door, and every player on Roblox
gets the identical layout. From the hub you step through the arch into your own copy of today's
dungeon. The clock starts when **the server sees you** cross the start line. You explore dark stone
halls that appear two cells ahead of you as you move, find the **3 Seals** (any order), and reach
**the Door**, which opens only when you carry all three. The clock stops there. Your time is ranked
on today's public and friends board, and your medal is graded against the day's *perfect line*.
Then you tap **Run again**: same layout, fresh clock, and now you know where things are. The loop is
exploring, then learning a route (the order of the seals and which loops are shortcuts), then
executing it faster (cutting corners, stepping around the red rings). Tomorrow brings a new Door.

---

## 2. What v1 is, and what is cut

**In v1:** a hub (spawn pad, the arch, the board with a yesterday plaque, a campfire); one dungeon
lane per player; the daily layout minted once per UTC day and shared by every server; the
server-side run monitor (clock, seals, Door, movement checks); four medals and five ranks; a Door
streak; five environment bands; three fork hazards per day; rest at the campfire; a phone-first HUD.

**Cut from v1** (each would ship thin, so it is cut rather than half-built):

| cut | why |
|---|---|
| timed gates, moving walls, keys and locked doors inside the maze | the seals and the Door already carry the route puzzle. Each extra mechanic needs its own fairness proof on a shared, ranked layout |
| ghost replays / racing your best | needs a stored path per run, a replay renderer and budget checks. v2 candidate |
| a minimap of explored cells | would help: about 20 % of model days (29 of 150, normal) end on a longer-than-optimal *known* route [M]. But it is a whole UI of its own. First v2 candidate |
| practice mode (random unranked doors) | only a Studio-only fallback door exists (§3.5), for the night shift's shots |
| an all-time board | today's board plus yesterday's top 3 is the social layer. Long-term progress is personal (§6.4) |
| badges, promo codes, gamepasses, anything that costs Robux | nothing to grant, and nothing is for sale in v1. No gambling, no pay-to-win |
| audio | needs assets. Listed for later |
| spectating, co-op, races in one dungeon | a speedrun on a shared layout is solo by design |
| rank icons on the board, titles over heads | the rank shows as the torch colour and on the finish card |
| streak freezes, notifications, weekly long doors | engagement features beyond v1 |
| auditing the top runs' paths | the server logs every void with its reason for tuning. A stored path for the top 10 is v2 |

---

## 3. The day: how a Door is made, why no client can compute it, why everyone gets the same one

### 3.1 The rule

The daily layout **is not derived from a seed**. The radar suggested "hash of the date string", and
that is the defect this section exists to avoid: anyone could compute tomorrow's dungeon tonight.
A salted 32-bit seed is not enough either. It also drives visible geometry, so a client could
brute-force it offline against the first room it sees (fork-tower `REVIEW-4.md` §2, trap 1).

Instead the **layout itself is the secret**. It is drawn from server entropy once, on the day, and
stored as data:

1. `dayIndex = floor(os.time() / 86400)` (UTC). The Door number shown to players is
   `dayIndex - 20725`, so 2026-09-30 (dayIndex 20726, measured with Python's `datetime`) is Door #1.
2. A server needs day D, either at boot or when its once-per-second clock check sees the date change.
   It calls `GetAsync("d_" .. D)` on the DataStore `SameDoor_Days_v1`. If there is a valid record, it
   uses it. If not, it calls `UpdateAsync("d_" .. D, keepOrMint)`, where `keepOrMint(old)` returns
   `old` when that is a valid record and otherwise mints a new one. UpdateAsync is atomic per key,
   so two servers racing at 00:00 both end up holding the one record that was written.
   GetAsync is only a cheap first look. The UpdateAsync is what decides.
3. **Minting.** The dungeon generator (`src/server/Dungeon.luau`, a ModuleScript in
   ServerScriptService, so it never replicates) takes a random source as an argument. On the server
   that source is `draw(n)`: `bit32.bxor(life:NextInteger(0, 4294967295), fresh:NextInteger(0, 4294967295))`
   mapped to `1..n` through its high bits (checklist: never `state % span`). `life` is a `Random.new()`
   created at server start. `fresh` is a new `Random.new()` for each mint. This is the same
   construction fork-tower uses for `mintSecret` (REVIEW-4 §2). In tests the source is the repo's
   deterministic `Rng`.
4. A server only ever mints the day its own clock is in. Nothing is pre-minted, so **no record for
   day D exists before 00:00 UTC of day D**, and there is nothing to compute early.
5. Every server reads the one stored record, so the layout is **identical for every player that
   day**. The Studio fallback (§3.5) is the only exception.

### 3.2 The generator (pure, `src/server/Dungeon.luau`, unit-tested)

| step | rule | number, reason |
|---|---|---|
| grid | W × H cells | **9 × 9** [M]. Normal model first run p50 151 s, perfect line p50 27.3 s (band-filtered). 7 × 7 gave a funnel p50 of 22.3 s and 11 × 11 gave 32.5 s. 9 × 9 keeps a first run near 2.5 min |
| maze | recursive backtracker from the entrance (the labyrint-spill `MazeGen` algorithm), then extra openings | **8 loop openings** [M]. The par route covers 42 % of cells (12 openings: 37 %). Loops make "which way round" a real choice |
| entrance | fixed cell | **(4, 0)**, the south-middle cell [C]. The antechamber and start line are then the same every day |
| seal A | path distance from the entrance | **3..6 cells** [M]. First seal p50 **8.4 s** after the line (p90 33.2 s, normal) |
| seals B, C | distance from the entrance, and all three seals pairwise | **≥ 6 cells** each [C], so the order of seals matters. Placement never failed in 2000 9 × 9 mints (first attempt every time) [M] |
| Door | path distance from the entrance; distance to each seal | **≥ 0.6 × the farthest cell's distance; ≥ 4 from each seal** [C]. Measured Door distance p50 19 cells, range 8..47 [M] |
| route | best of the 6 seal orders, by BFS cell steps | exact (6 permutations) |
| perfect line P | string-pulled path (funnel algorithm) along that route, with a clearance margin | **margin 2.5 studs** = wall half-thickness 1 + player radius 1.5 ([R] `plus1-jump` `Config.Hazards.PlayerRadius`). P = length / WalkSpeed, stored as `perfectMs` |
| difficulty band | accept a mint only if **22 s ≤ P ≤ 34 s**, else draw again | [M] 73.5 % of mints are accepted. The band is the unfiltered p15..p85, so every day is a similar size |
| mint attempts | then fail closed | **50** [C]. The chance of 50 rejections in a row is 0.265^50 ≈ 1.6e-29 |
| hazards | 3 fork cells (§8) | chosen by the same draw |

The funnel was checked against geometry before any number was taken from it: an L-turn through
16-stud cells with a 2.5 margin measures **22.952 studs**, which matches the analytic value
(`design/measure/funnel_test.luau`). P is about **0.71** of the cell-centre route: the median ratio
is 0.714, the range 0.61..0.84 [M]. That is why medals use P and not a cell-count "par". A par
would make days with many turns far easier to medal.

### 3.3 The stored record (`SameDoor_Days_v1`, key `d_<dayIndex>`, about 300 characters)

A compact JSON sample of this shape measures 301 characters.

```
{ v = 1, day = <dayIndex>, w = 9, h = 9,
  open = "<41 hex digits: 2 bits per cell, E then N passage, 162 bits>",
  entrance = { x = 4, y = 0 },
  seals = { {x=<int>,y=<int>}, {x=<int>,y=<int>}, {x=<int>,y=<int>} },
  door = { x = <int>, y = <int> },
  hazards = { {x=<int>,y=<int>,slot=1}, {x=<int>,y=<int>,slot=2}, {x=<int>,y=<int>,slot=3} },
  perfectMs = <int>, mintedAt = <unix> }
```

Only string keys and dense arrays, so JSON has no sparse integer keys to turn into strings
(checklist trap). **Validation on load:** `v` is known; the dimensions match; the `open` length is
right; every seal and the Door are reachable from the entrance; the placement and hazard rules hold;
and recomputed `perfectMs` equals the stored value within 1 ms (proof that this server builds the
same dungeon the minter measured). **An invalid record fails closed**: the arch says so, and the
server never re-mints over it, because that would change a day's layout mid-day. A record with an
unknown `v` gets "This server is out of date for today's Door; rejoin". Rule for future versions:
a generator change bumps `v`, takes effect from the next minted day, and the builder keeps reading
older `v`.

### 3.4 Why a client cannot compute the layout faster than playing it

| route to the layout | closed by |
|---|---|
| compute it from public inputs (date, a replicated seed, a module in ReplicatedStorage) | there are no inputs to compute from. The layout is stored data from server entropy, and the generator is server-only anyway |
| brute-force a seed against what it has seen (REVIEW-4 trap 1) | there is no seed. Recovering the layout would mean recovering two Roblox `Random` states from hashed 2-bit maze choices. That is reasoning, not measurement: fork-tower §8.2 has the same caveat |
| read the geometry of cells it has not reached | **unrevealed cells never leave the server.** Maze walls and contents are built on the client, from `Cell` payloads the server sends only for revealed cells (§5.2). No other client ever receives your cells |
| reveal cells fast by teleporting or flying around | **reveal follows validated movement only.** The first failed movement check voids the run, and the server sends no further cells for it. A new run starts again at the entrance. Revealing the maze therefore costs walking it at walking speed |
| a read-only session as a free oracle (REVIEW-4 §9) | there are no per-player hidden bits. The day is shared, and a read-only session reveals exactly what playing reveals |
| read the day record from a replicated place | a copy for rigs and checks lives only in `ServerStorage.SameDoor.Day` (a StringValue, JSON), following anomaly-observatory's "ServerStorage, not the zone" |

**What a client does know before playing:** the grid size, the entrance, that there are 3 seals and
3 hazards, and `perfectMs`, which appears as the medal times in the antechamber. That is one number:
the route's length. Everything else is revealed by walking.

### 3.5 Studio fallback door

In Studio with API access off, the DataStore is unavailable and a live server would fail closed.
The night shift still needs to shoot, so **only when `RunService:IsStudio()` is true** and the Days
store cannot be reached, the server generates a fixed "Studio door" from `Config.StudioDoorSeed`
(`20260930`) with the deterministic `Rng`. Every run on it is unranked, twice over: `canSave` is
false, and the board and profile writers refuse any record marked `studio = true`. The HUD day chip
says `Studio door (unranked)`. A live server (IsStudio false) with a failing Days store shows
`Today's Door is still being carved; retrying` and retries after 2, 4, 8, 16 and then every 30 s [C].
No run can start meanwhile. That is asserted headless.

### 3.6 Midnight in a live server

Runs in progress keep the record they started with and post to that day's board. A run that
started on day D may finish up to `RunCap` after midnight [C]. The next **Run again** uses the new
record, and the finish card says `A new Door opened at 00:00 UTC. This is Door #N`.

---

## 4. The world

| thing | number | reason |
|---|---|---|
| cell | **16 studs** | [C] one cell per second at WalkSpeed 16. The free interior is 14 × 14, wide enough for an 8-stud hazard ring with a 1.5-stud lane beside it (§8) |
| wall | **2 thick, 14 high; ceiling at 14** | [C] the root sits about 3 above the floor and a default jump adds 7.2, so a jumping head stays under 14 and nobody sees over a wall. The camera in 14-stud halls is [S] |
| walk / jump | **WalkSpeed 16, JumpHeight 7.2** | [R] Roblox defaults (`plus1-jump` Config). Jumping gives no speed on flat ground, and the dungeon is flat |
| run cap | **900 s** | [M] 1.72 × the slowest of 2000 model first runs (522 s, slow profile). At the cap: `The torches burned out (15 min). Run not counted.` |
| MaxPlayers | **12** | [C] a livelier hub. Budgets at 12 players: ordered-store writes 30 + 5 × 12 = 90/min [D], against about 18/min if every player posted a best every 40 s |
| lanes | one per player, **x = (i - 1) × 256, z = +1000** from the hub; indices from a free list, recycled | [C] 144-stud grid + 16-stud antechamber + margins. Coordinates stay bounded (checklist: unbounded coordinates) |

**Server-built** parts are identical in every lane and every day, and reveal nothing. They are the
lane's floor slab, ceiling slab, perimeter walls (the south wall in two pieces around the entrance
gap), the antechamber (16 × 16, with the start line on the entrance cell's south edge), and the
**Dawn Sanctum** (a small open-air balcony north of the lane, where every finish lands).

**Client-built** from `Cell` payloads: the interior walls (56 per layout [M]: 91 closed edges minus
35 perimeter), the seals, the Door, hazard fixtures, and a **veil**. A veil is a matte black box
filling every cell not yet revealed, so a doorway always looks into darkness and never at missing
walls. Veils are uniform, so they carry no information [S: does it read as darkness].

Why client-built walls cost no security: a player character's physics is simulated by its own
client, so collisions with *any* wall are the client's business anyway, and a noclip exploit ignores
server walls just as easily. The server polices movement against the cell graph instead (§11).

---

## 5. The run

### 5.1 Sequence

1. **Arch** (hub, ProximityPrompt `Enter Today's Door`, HoldDuration 0). The server refuses with a
   reason if the day is not loaded, a run is already live, or the lane pool is full. Otherwise it
   builds the lane shell if needed and moves the character into the antechamber with a server
   `PivotTo`. The character has been parented for a long time by then, so this is not the spawn
   race (§14). The first `Cell` batch (the ring around the entrance) is sent at the same moment.
2. **Antechamber card:** `Door #N · Find 3 Seals, then open the Door. The clock starts at the line.`
   plus the medal times.
3. **Start.** The server samples the root every Heartbeat. The official clock starts at the first
   northward crossing of the line, interpolated between the two samples that bracket it. The client
   starts its own display clock when **it** sees its character cross the line. Hazards run on that
   client clock, so they sit at the same moments of every player's own run whatever the ping.
4. **Reveal.** When the server sees the root enter a cell, that cell is *visited*. Every cell within
   **2 open-passage steps** of a visited cell is *revealed* and sent once. [C] The next unrevealed
   cell is then always at least one cell (16 studs, 1 s of walking) beyond the player, which covers
   round trips up to about 1 s [S].
5. **Seals.** A seal is taken when the server sees the root within **4 studs** horizontally of its
   centre. The test also checks the segment between consecutive samples. [C] 4 studs is under half
   the free width, so the route has to go through the middle of the cell. The client hides the seal
   and the band changes (§7).
6. **Door.** Root within **4 studs** of the Door's centre with 3 seals: the run finishes at the
   interpolated entry time. With fewer seals: `The Door needs 3 Seals (1/3)`. There is never a
   silent refusal.
7. **Finish.** The character moves to the Dawn Sanctum and the finish card shows the time
   (hundredths), the medal, today's best, the streak, and any rank-up. It has **Run again** (back to
   the antechamber, the same layout) and **Hub** buttons. Model assumption: 8 s per retry, card to
   line [C]. The headless check measures the real figure.
8. **Leaving early** (the pause button; §9), a character reset, or leaving the game ends the run.
   Nothing is posted, and it is not counted as a failure.

### 5.2 What the client is sent

`Cell` (server to the owning client only):
`{ run = runId, cells = { { x, y, sides = N1|E2|S4|W8, kind = "seal"|"door"|"hazard"|nil, slot = 1..3|nil } } }`.
Only revealed cells, each once. The client ignores a stale `runId`. The server times
(`startedAt`, `finishMs`) come in `Run` payloads (§13).

---

## 6. Medals, the brag moment, the long-term goal

### 6.1 Medals, per day, graded against P (the day's perfect line)

| medal | threshold | normal model: cumulative play minutes to the first one [M] | days it is earned [M] (normal, 20-min sessions) |
|---|---|---|---|
| Bronze | finish | first run, p50 151 s | 100 % (every model first run finishes) |
| Silver | ≤ **1.60** × P | p50 4.8 (p90 7.6) | 95 % |
| Gold | ≤ **1.25** × P | p50 8.1 (p90 26.6) | 83 % |
| **Sealer** | ≤ **1.10** × P | **p50 33.7** (p10 12.3, p90 98.5); typically on day 2 (p50), p90 day 5 | 33 % |

The same measurements for the other profiles: **fast**, 30-minute sessions: Sealer at p50
10.0 min, earned on 76 % of days. **Slow**, 15-minute sessions: Gold at p50 15.2 min, earned on 51 %
of days. Slow players essentially never reach Sealer: 113 of 120 did not within 14 days, and 0 % of
days. For them Gold is the summit. **Owner decision** (§21).

Where P can be beaten: seal pickups and the Door trigger 4 studs early, so a perfect bot finishes a
little under P. Medals are relative to P. The board ranks raw time.

### 6.2 The brag moment: "THE DOOR IS SEALED"

The **first Sealer medal ever**. The Door flares white-gold in the Sanctum with a flash, an FOV
punch and the card `THE DOOR IS SEALED · Door #N · <s.cc> s`. The torch turns white-gold for good,
and today's board row gets a `SEALED` plate. It lands at a **median of 33.7 minutes of cumulative
normal play** [M], inside the owner's 30-45 min band. It usually falls on the player's **second**
day, because a daily game gates it by days. That is an interpretation of "30-45 min of normal play"
for a daily genre; the owner signs it off in §21.

### 6.3 The pacing model (to be rebuilt as `tests/RunnerModel.luau` + `tests/Pacing.spec.luau`)

This is the model behind every [M] minute above (`design/measure/model.luau`,
`design/measure/run_days2.luau`), on the game's own generator and 16-stud cells:

* **First run: exploration.** The player walks at `effExplore × 16` studs/s and sees 2 cells down
  straight open corridors. They go for the nearest known seal, then the Door; otherwise to the
  nearest unvisited known cell, or a random one with probability `wander`. They pause `decide` s at
  a new fork and `deadEnd` s at a dead end.
* **Later runs.** The player takes the best seal order over **the passages they know**. Run time =
  the funnel length of that route × (1 + slop) / 16, plus fork hesitation that decays per run.
  Slop follows the **power law of practice**,
  `slopMin + (slop1 - slopMin) × (r - 1)^-alpha`, with lognormal run-to-run variance (sigma 0.35)
  and an occasional 1-4 s mistake. With probability `qScout` a run also scouts `scoutCells`
  unexplored cells, which costs time and may find a shortcut. Each retry costs 8 s of overhead.
* **Profiles** (the human part, written down):

| profile | effExplore | decide / deadEnd s | wander | slop1 → slopMin | alpha | pMistake | qScout / cells | session |
|---|---|---|---|---|---|---|---|---|
| fast | 0.95 | 0.3 / 0.3 | 0.10 | 0.25 → 0.06 | 0.6 | 0.15 | 0.35 / 6 | 30 min/day |
| normal | 0.85 | 0.8 / 0.6 | 0.25 | 0.35 → 0.12 | 0.5 | 0.25 | 0.25 / 5 | 20 min/day |
| slow | 0.75 | 1.5 / 1.0 | 0.40 | 0.45 → 0.20 | 0.4 | 0.35 | 0.15 / 4 | 15 min/day |

* **Two model choices, both measured.** An exponential learning curve had normal players at Gold
  (×1.30) in 6.8 min (`design/measure/pacing.luau`). A power law with no run-to-run variance made
  every run of the same count identical, which put a knife-edge at the asymptote
  (`design/measure/pacing2.luau`: ×1.16 at 27.4 min, but 44 of 150 days never reached it in 90 min).
  The power law with variance (`pacing3.luau`, `run_days2.luau`) is the empirically grounded shape:
  best-of-many attempts is how medals are earned. It is the one used above.
* **`Pacing.spec` asserts:** the normal profile's median cumulative minutes to the first Sealer is
  within [30, 45]; fast ≤ normal ≤ slow; the normal hazard near-miss rate is within [1/3, 1/2] per
  running minute (§8); and no profile's first run exceeds `RunCap`.

### 6.4 Long-term: ranks and the Door streak

| rank | earned by | normal model: when [M] | torch |
|---|---|---|---|
| Wanderer | first Door opened | ~2.5 min | warm orange (default) |
| Gilded | first Gold | p50 8.1 min | gold |
| Sealer | first Sealer (the brag moment) | p50 33.7 min, day 2 | white-gold |
| Warden | a 7-day Door streak | 7 consecutive UTC days with a finish | teal |
| **Keeper of the Same Door** | **30 Sealer days** | Sealer on 33 % of 20-min days, so about 91 days (fast: 76 %, about 40 days) | violet |

The **Door streak** counts consecutive UTC days with at least one finish (§12). The torch is a
server-made PointLight on the character, so others in the hub see its colour. Its colours must stay
clear of the seal gold and the hazard red, like every other decor colour (§7).

---

## 7. Environment bands: they follow your own run

**Trigger: the number of seals you carry, from the server's `Run` payload; never time.** Every run
passes all five, and a band lasts about as long as a leg between seals. The progress value is
`seals` (0..3), and 4 once the Door opens. Bands use `from = 0, 1, 2, 3, 4` with `fade = 0`. The
glide is the template's `EnvBands.approach` with a **0.8 s half-life** [C]: after 2.4 s, 87.5 % of
the change has landed, so a seal pickup reads as a wave of light rather than a cut. Lighting is
written at most **10 times per second** [R] (`plus1-jump` `Config.Env.LightingHz`).
`EnvBands.luau` is copied **verbatim** from `plus1-jump/src/shared`, with its spec.

| # | band | when | light and colour | scenery (on revealed walls) | critters | weather |
|---|---|---|---|---|---|---|
| 1 | Cold Cellar | 0 seals | cool blue-grey ambient, pale torch | cobwebs, hanging chains, wet stone, drip stubs | bats flitting across a corridor | dust motes |
| 2 | Moss Halls | 1 seal | green ambient, soft cyan-green mushroom glow | moss patches, ferns, glowing mushrooms | fireflies (cyan-green) | drifting spores |
| 3 | Crystal Seams | 2 seals | violet ambient, blue crystal glints | crystal clusters, geodes | crystal moths | glitter |
| 4 | Ember Vault | 3 seals: the Door is awake | warm amber ambient, the Door glows brighter | braziers, bronze trim | fire sprites | rising embers |
| 5 | Dawn Sanctum | Door opened | open sky at sunrise, warm pink light | columns, flower beds, distant peaks | birds | petals |

The hub is not a band: it keeps one daylight look (`Fx.applyLighting` on the server), and the client
restores it on return. The colour values themselves are Studio's call [S]. The **rules** are fixed
and tested (`Bands.validate`, after labyrint-spill's biome rules):

* **Decor never encodes the layout.** Placement is a pure function of the wall's grid position, its
  face and the band, never of what a cell contains. Nothing points toward a seal or the Door, and
  embers rise straight up.
* **Nothing but a seal glows seal-gold, and nothing but a hazard ring is red.** Every decor, critter,
  weather and torch colour keeps a minimum RGB distance from both. `plus1-jump`'s "anything the
  player chases should glow" then holds in reverse too.
* Decor sits at most 1.2 studs out of a face and only on revealed walls within 24 studs of the
  player, **at most 30 pieces** [C]. Critters stay inside the player's current and adjacent revealed
  cells, above head height, and are non-collidable and non-queryable.
* Weather goes through `EnvBands.capRates`: at most **2 weather emitters** and **60 particles/s**
  [R] (`plus1-jump` `Config.Budget`).

---

## 8. Hazards: part of the day, not the player

**Why not `plus1-jump`'s `Hazards.luau`:** it launches a lane at the player from wherever the
camera looks, on a random clock. On a ranked, shared layout that would put luck into the time.
The base is instead **`labyrint-spill/src/shared/CellHazards.luau` with its spec**. That module is
the family's reviewed adaptation of the template for a timed, shared-seed maze: same cells, same
moments of the run for everyone, a ring that is exactly the hit zone, and a knock that costs a
little. `DoorHazards.luau` changes four things, and says why:

1. **Where** comes from the day record, not `hash01(level)`. A hash of a public number would let a
   client compute the hazard cells, which is a layout leak.
2. **Only fork cells** (3 or more open sides). This is the measured fix for rarity (below), and a
   fork is visibly a fork once revealed, so it tells nobody anything. An earlier draft of this spec
   put one hazard on the par route. That was rejected: a hazard would then have said "the optimal
   route passes here".
3. **Staggered slots, so a run never has two at once.** The impact of the hazard in slot k is at
   `6 + 4 × (k - 1) + 12 × n` s after the line. A hazard is active for 3.0 s of warning + 0.8 s of
   debris = 3.8 s, which fits inside the 4 s slot, so windows never overlap. labyrint allowed two
   drawn at once.
4. **The ring is red**, as the standard says. labyrint used blue because red and yellow mean a
   lethal floor there. The Same Door has no lethal floor.

| number | value | reason |
|---|---|---|
| cells per day | **3**, forks only, ≥ 3 cells from the entrance, never a seal or the Door, pairwise ≥ 4 apart | [M] 3 placed on every one of 480 model days |
| cycle / slot / first impact | **12 s / 4 s / 6 s** after the line | [M] rate below. The first warning starts at 3 s |
| warning / debris | **3.0 s / 0.8 s** | [R] labyrint (warning floor 2 s) |
| zone | strike radius **2.5** + player radius **1.5** = **4.0** (an 8-stud ring) | [C] fits the 14-stud free cell with a 1.5-stud lane each side for the root. A corner-cutting line through a turning cell passes 5.66 studs from the centre, outside the ring |
| height cap | a hit needs the root ≤ **12** studs over the floor | [R] labyrint `MIN_HIT_HEIGHT`. A jump is no dodge |
| a hit | knocked down **0.8 s**, pushed **5 studs/s** away (4 studs), never up | [R] labyrint. It costs about a second, never a run |
| near-miss | an impact within **12 studs** of the root that does not hit | [R] labyrint's definition |

**Measured rarity** [M] (`design/measure/hzrand2.luau`, 480 model days, runners who react):
**0.410 near-misses per running minute for normal (one per 2.4 min)**, 0.415 for fast (2.4) and
0.426 for slow (2.3). The standard asks for about one per 2-3 minutes. The rejected variants for
normal players, measured the same way, were:

* 3 random cells, 12 s cycle: one per 3.3 min (`hzrand.luau`);
* 4 random cells, 16 s cycle: one per 3.6 min (`hzrand.luau`);
* 3 non-dead-end cells, 12 s cycle: one per 3.1 min (`hzrand2.luau`);
* 3 cells on an 18 s cycle with one on the par route: one per 2.2 min (`run_days2.luau`), rejected
  for the leak in item 2.

The model counts a near-miss as an impact within 0.4 s of the runner being in the cell.
`Pacing.spec` will measure it with the 12-stud definition. It will also measure the hit rate of a
runner who ignores warnings, which this model did not.

**Telegraph** (client): the fixture over the cell (stalactite, spore pod, crystal, ember bomb; the
kind follows the band and is cosmetic only) shakes. A **red** ring on the floor, exactly the zone,
pulses. A banner reads `Step out of the red ring`. The hit test runs on the client, because the
knock moves the client's own character. An exploiter who deletes hazards saves at most the knock
that a careful player never takes.

---

## 9. Rest and pause

**The run clock never stops**, because it is the medal and the record. `Rest.luau`'s own header says
the same: rest pauses things that exist to bother the player, never a thing they race. So rest lives
**between runs** (labyrint-spill's `BreakRoom` precedent). `Rest.luau` is copied **verbatim** from
`plus1-jump`, with its spec.

* **Campfire (hub):** a `Rest by the fire` prompt, and a Rest button top-centre in the hub. You sit,
  the view softens, and nothing is running. Any move wakes you (`WakeOnMove`, enforced by
  `Rest.validate`). A pure `mayRest(ctx)` returns true only in the hub and outside a run, and fails
  closed. Config [C]: `IdleSeconds = 0` (the hub has nothing to be safe from; labyrint does the same),
  `RequireGrounded = true`, `BlockWhileThreat = true` (validate requires it; the hub never has a
  threat), `WakeGraceSeconds = 0.4` [R plus1], and `PendingSeconds = 2`. A default jump lasts 0.54 s
  (2 × √(2 × 7.2 / 196.2)), so 2 s covers landing from any hub jump.
* **The pause button in a run** (top-right, not a bottom corner) opens a sheet:
  `The clock never stops. Leave this run and rest by the fire?` with **Leave run** and **Keep running**.
  The clock keeps running while the sheet is open, so there is no free thinking time. **Leave run**
  ends the run: nothing is posted, it is not a failure, and you arrive sitting at the campfire.
* **Why it cannot be exploited:** nothing is ever paused. Hazards exist only inside a run, on the run
  clock, so there is no hazard clock to freeze outside one. Resting sends no remote and earns
  nothing. Roblox's roughly 20-minute idle kick still applies in the hub, and loses nothing because
  the profile is saved. An idle player inside a run is ended by `RunCap`.

---

## 10. The highscore board

**Metric: today's best verified run time, in milliseconds.** Lower is better. Ties go to whoever
reached it first.

* **Store:** OrderedDataStore `SameDoor_Board_v1`, **scope `d<dayIndex>`**, key `u_<userId>`.
* **Encoding** (the standard's form, with a higher-is-better metric):
  `value = (CapMs - timeMs) × 2e9 + (2e9 - reachedAtUnix)`, where `CapMs = 900000` (RunCap). The
  largest value is 1.800002e15, below 2^53 = 9.007e15, so every intermediate is an exact integer.
  The tie-break term stays positive until 2e9 unix = **2033-05-18** (computed). Before then the
  encoding needs a new version.
* **Writes:** only by the server, only for a verified finish, via `UpdateAsync` that keeps the old
  value unless the new time is better. The profile records `today.postedMs`. On join, a best that
  never reached the board (a throttled write, a crash) is posted again, so the board converges.
* **Public:** `GetSortedAsync(false, 10)`, cached server-side for **60 s**. The documented budget is
  5 + 2 × players GetSortedAsync calls per minute [D]; this uses 1, plus 1 per hour for yesterday.
* **Yesterday's Keepers:** a plaque beside the board with the top 3 of scope `d<dayIndex-1>`,
  refreshed every **3600 s** [C].
* **Friends:** `Players:GetFriendsAsync`, capped at **200** (the standard's example), fetched only on
  demand when you toggle the board. Each friend is one ordered `GetAsync`, read only while
  `GetRequestBudgetForRequestType(GetAsync)` stays above a reserve of **20** [C] (saves and the day
  record come first). The documented budget is 60 + 40 × players per minute [D]. The board shows
  `Loading friends <n>/<cap>`, then caches for **300 s**. All of it is pcall'd. Empty:
  `None of your friends have opened today's Door yet. They get the exact same dungeon: tell them
  your time.` The emulator has no `GetFriendsAsync`, so the headless check stubs it.
* **Names:** `GetNameFromUserIdAsync`, cached per server (at most **500** entries [C]). Names are
  never stored.
* **In the world:** a physical board facing the spawn pad. Rows are rendered by the client, so each
  player can toggle Public/Friends through the board's ProximityPrompt without changing anyone
  else's view. Each row shows the name, the time (hundredths) and today's medal, plus the `SEALED`
  plate.

**Why a script cannot inflate it:** the only way a time reaches the board is a server-observed
character moving from the line through 3 seals to the Door, through open passages, at walking speed
(§11). No remote carries a time, a position, a seal or a finish. The clock is the server's. What a
script *can* do is play: a bot on the perfect line gets about P, the same ceiling a perfect human
has, plus at most the 2 % the speed tolerance allows (§11). That residual is stated, not hidden.

---

## 11. Anti-exploit model

The server samples every player in a run on **every Heartbeat** (60 Hz) and keeps its own
**run clock as the sum of Heartbeat `dt`**. `os.clock` is CPU time and barely moves headless
(deep-vein's `CLAUDE.md`), and `tick()` follows the wall clock.

| threat | defence | residual |
|---|---|---|
| teleport, noclip through a wall | **continuity**: each sample is in the same cell, an open-passage neighbour, or a diagonal cell with a 2-step open path. After a gap > 0.25 s, the open-path distance may be at most `ceil(gap × 16 × 1.5 / 16) + 1`. A failed sample voids the run | none found |
| speed hack, burst | the displacement in any **0.5 s** window is at most 16 × 0.5 × 1.5 + 2 = **14 studs** [S] | none above 1.5× |
| speed hack, sustained | any **3 s** window: at most 16 × 3 × 1.05 + 2 = **52.4 studs** [S]. Whole run: path length (samples every 0.25 s) / time ≤ 16 × **1.02** [S] | a sustained speed-up under 2 %: at most about 0.6 s on a 30 s run |
| lag switch (the start seen late, then a catch-up) | the catch-up has to move faster than walking: caught by the windows and the whole-run check | the same 2 % |
| flying or jumping over walls | root Y within the floor top **-2..+13** (the ceiling is at 14) | none |
| forged remotes | no remote carries a time, position, seal or finish. `Leave` and `RunAgain` are rate-limited to one per second and checked against the run state | none |
| reveal scraping | reveal follows only validated movement, and stops at the first void (§3.4) | none |
| board or profile tampering | server-only writes, an owner token on every profile write (fork-tower `old.session`, REVIEW-4 §10), and a monotonic board `UpdateAsync` | none |
| hazard deletion | client-side knock only | at most the knocks a careful player never takes |
| a perfect bot | none possible: it plays the game | reaches about P, the human ceiling |

A void always explains itself, for example `Run not ranked: position jumped <d> studs in <t> s
(connection hiccup?). Your time is shown but not posted.` Target: **under 1 % of honest runs voided** [S]. The
tolerances above are provisional until Studio records honest runs on desktop and on a phone over
4G (§19 item 1).

---

## 12. Data model

**Persists** (DataStore; everything pcall'd):

| store | key | content |
|---|---|---|
| `SameDoor_Days_v1` | `d_<dayIndex>` | the day record (§3.3), minted once, never overwritten |
| `SameDoor_Players_v1` | `u_<userId>` | `{ v=1, session=<token>, lockUntil=<unix>, today={ day, bestMs, bestAt, medal, runs, finishes, postedMs }, life={ doors, silverDays, goldDays, sealerDays, streak, bestStreak, lastDay, runs, firstDay }, seenIntro }`. `doors` counts days with a finish (Bronze days); each `*Days` counts days whose best medal reached that tier; Keeper reads `sealerDays` |
| `SameDoor_Board_v1` (ordered) | scope `d<dayIndex>`, key `u_<userId>` | the encoded best (§10) |

Profile rules: the session lock holds an owner token that is stable for the session and never a
timestamp (checklist trap). Autosave every **20 s** under a **45 s** lock [R] (`plus1-jump`: autosave
must be shorter than the lock). `canSave` is true only while the lock is held. A read-only session
(lock held elsewhere) may run, but **unranked**, and says why. A finish that changes the medal,
streak, ranks or best is flushed immediately in **one atomic `UpdateAsync`**. Medal counters and
rank-ups are one-time grants and happen only inside that flush. The streak and rank logic is a pure,
tested `Ledger.luau`. When `today.day` is not the current day, `today` resets; the lifetime counters
were already updated at finish time. The Door streak continues if `lastDay` is yesterday, stays the
same if it is today, and restarts at 1 otherwise.

**Server-only** (never in an Instance a client can see): the day record, both in server-script
memory and as the one copy in `ServerStorage.SameDoor.Day` for rigs and checks; each run's visited,
revealed and taken sets, samples and void state; profiles; name and friends caches.

**Replicates, and why that is safe:**

| what | why it is safe |
|---|---|
| hub, lane shells, antechambers, sanctums | identical everywhere, every day |
| characters, torches | ordinary avatars, and the torch colour is a rank |
| `leaderstats`: `Best` (StringValue, today's time) and `Streak` | public by design |
| `Cell` payloads, to the owner only | only revealed cells |
| `Run` payloads, to the owner only | seal count, run state, medal times, official time, void reason |
| board rows | names and times, public by design |
| ReplicatedStorage modules: `Config`, `EnvBands`, `Rest`, `DoorHazards`, `Responsive`, `Fx`, `FxClient`, `Day`, `Medals`, `Board`, `Ledger`, `Bands` | none can produce a layout: no seed exists, and the generator lives in ServerScriptService |

---

## 13. Client and server, remotes

| what | where | why |
|---|---|---|
| day mint and load, generator, run monitor, clock, seals, Door, reveal, voids, saves, board | server | authoritative |
| building revealed cells, veils, decor, bands, critters, weather, hazards and knock, rest, HUD | client | cosmetic or own-character only. It is sent only what it may know |

Remotes (`ReplicatedStorage.SameDoorRemotes`): `Cell` and `Run` (server to the owning client),
`Board` (server to client, public rows to all, friends rows to the one who asked), `Toast` (server to
client, the reason for every refusal), `Leave` and `RunAgain` (client to server, one per second,
state-checked). The ProximityPrompts (arch, board toggle) are handled server-side, and the campfire
prompt client-side (rest is client-only).

---

## 14. Spawn placement (`robloxemu/SPAWN-ORDER.md`)

* **Exactly one enabled SpawnLocation**, `HubSpawn`, 14 studs south of the arch and facing it. The
  headless check asserts it is the world's only enabled spawn, as deep-vein's `walk.luau` does.
* `plr.RespawnLocation = HubSpawn`, set in `PlayerAdded`, before the character loads. The engine's
  own placement is then already correct, and **`CharacterAdded` never writes a CFrame**, so there is
  no race to lose.
* Moving into a run is a **server `PivotTo` after the arch prompt**, long after the character is
  parented. The antechamber floor is server-built before that move (deep-vein: build the landing
  first).
* A reset, a death or leaving mid-run ends the run on the server (`Humanoid.Died` /
  `CharacterRemoving`), and the engine respawns the player at `HubSpawn`. No mid-run respawn
  placement exists at all.

---

## 15. HUD, phone first

A root Frame owns a `UIScale` (`Responsive.luau` copied verbatim from a sibling). Tap targets are
at least **44 screen px**, nothing tappable sits in the bottom-left or bottom-right thumb zones,
the layout redoes on `ViewportSize`, and **hudcheck runs with `overlap = true`**.

* **Top-centre:** the run timer (large), with 3 seal pips under it. In the hub, the Rest button sits
  here instead.
* **Top-left:** the day chip `Door #N · new Door in <hh:mm:ss>`.
* **Top-right:** the medal-times panel (it collapses when `layout.compact`) and, in a run, the pause
  button.
* **Centre:** the antechamber card, the finish card (Run again and Hub side by side in the middle of
  the lower half, never in a corner), and the pause sheet.
* **The timer** shows the client clock and **snaps to the official time** at the finish. The
  difference is network jitter only, because both clocks start on the player's own crossing.

---

## 16. The first 60 seconds of a new player

These are model medians plus the geometry above. The headless check measures the real path.

| t | what happens |
|---|---|
| 0 s | spawn on `HubSpawn`, facing the glowing arch 14 studs ahead, with the board on the left and the campfire on the right. HUD hint: `Walk to the glowing arch and press E (tap ENTER)` |
| ~1-3 s | 4 studs of walking bring the arch's prompt (MaxActivationDistance **10**) up. Tap it. This is the core action within about 5 s, as the checklist asks |
| ~3-6 s | in the antechamber: the card, 3 empty seal pips, and the medal times. The line is 8 studs ahead |
| ~6-7 s | cross the line and the clock starts. The first cells glow in the Cold Cellar's blue |
| ~15 s | **first Seal**: p50 **8.4 s** after the line [M], p90 33 s. The pip fills, the halls glide into green Moss Halls, and a toast reads `1/3 Seals. The moss wakes.` |
| by 60 s | usually 1-2 seals. Maybe a first red ring, since the first impact comes 6 s after the line |

Seal A is always 3..6 cells from the entrance, which is what makes the first reward land in the
first minute. A normal first run then finishes at p50 **151 s** [M] with Bronze. Silver follows at
about 4.8 min.

---

## 17. Budgets (enforced in code, measured headless)

| budget | cap | reasoning |
|---|---|---|
| client local parts | **220** | worst case 56 interior walls + 81 veils + 26 contents (3 seals × 3, a Door of 8, 3 fixtures × 3) + 30 decor + 8 critters = 201, although walls and veils cannot both peak at once. That leaves 19 parts (about 9 %) of headroom |
| client lights | **4** | the torch + the 3 nearest sconces |
| emitters | **4** | 2 weather (via `capRates`) + the nearest 2 of seal glow and Door glow |
| emitter rate | **60/s** | [R] plus1 |
| server parts | about **25 per lane × 12 + about 150 hub** | fixed shells, independent of the day |
| day mint | about 1.36 attempts on average (1 / 0.735 [M]), each a few ms in the CLI | once per server per day |

---

## 18. Files and gates (the build plan, short)

`default.project.json` as in deep-vein (`src/server` → ServerScriptService, `src/client` →
StarterPlayerScripts, `src/shared` → ReplicatedStorage). `.gitignore` covers `publish_*.bat` and
`publish_*.sh`.
**Shared** (pure, dependencies passed in as arguments; `require("./X")` resolves in the CLI and is
invalid in Roblox): `Config`, `Rng`, `Fx`, `FxClient`, `Responsive`, `EnvBands`, `Rest` (all
verbatim), `DoorHazards` (from labyrint `CellHazards`), `Day`, `Medals`, `Board`, `Ledger`, `Bands`.
**Server:** `Main.server.luau`, `Dungeon.luau` (generator, placement, funnel, record
validation and serialisation), `RunCheck.luau` (continuity and windows).
**Client:** `Hud.client.luau`, `Dungeon.client.luau`, `DungeonArt.luau`.
**Specs, written first:** Dungeon (connectivity, placement, the P band, hazards, a record round-trip,
fail-closed validation), RunCheck (honest traces pass; teleport, burst, sustained 1.03×, noclip,
lag-switch and fly traces fail), Day, Medals, Board (encoding bounds, ties, monotonic), Ledger
(streaks across UTC days, one-time grants), DoorHazards, EnvBands and Rest (verbatim), Bands, and
Pacing.
**Headless** (rebuild the bundle before every run: `py -3 wrap.py --game ../same-door --out build/same-door.luau`):

* `check_samedoor.luau` walks the real path: join, `HubSpawn`, arch, the walker follows the day's
  route read from `ServerStorage.SameDoor.Day` at 16 studs/s, 3 seals, the Door; the time is within a
  frame of path/16; the profile and board are written; Run again; rejoin keeps best and streak.
* `check_samedoor_secret.luau`: at every frame no Part sits inside an unrevealed cell except its veil;
  every `Cell` payload contains only cells revealed at send time; no replicated value, attribute or
  payload contains 8 or more characters of the record's `open` string; reveal stops after a void; a
  pre-seeded record is used verbatim; a failing Days store with IsStudio false lets no run start.
  **Planted-leak control:** the record in a workspace StringValue, a player attribute and a `Toast`
  payload must all be found.
* `check_samedoor_cheat.luau`: every threat row in §11 voids; an honest walker at 1.00× is ranked.
* `_hud`, `_bands`, `_budget`, `_hazards`, `_rest`, modelled on the plus1 and labyrint checks.
  Every new assertion is mutation-tested with a control that must survive.

---

## 19. Needs Studio (only a real engine, network or device can settle these)

1. **Honest movement statistics:** the largest 0.5 s and 3 s displacement and the whole-run
   path/time ratio, desktop and phone over Wi-Fi and 4G. Set the §11 tolerances so that under 1 % of
   honest runs are voided. Also confirm a humanoid on flat ground never exceeds WalkSpeed.
2. `Random:NextInteger(0, 4294967295)` and `bit32.bxor` on values ≥ 2^31 (the same open item as
   fork-tower REVIEW-4 §8.1).
3. The OrderedDataStore stores and returns an encoded value near 1.8e15 exactly.
4. `GetFriendsAsync` paging on a real account with many friends; the friends-board fill time under
   the real budget.
5. Client-built walls: local collision; the camera in 14-high halls with a ceiling on a phone; a
   first-person feel.
6. **Veils:** do they read as darkness, or as black walls?
7. Band lighting indoors (Ambient, ColorCorrection, Atmosphere under a ceiling); readability at a low
   graphics level; whether a 0.8 s glide feels like a wave.
8. The seal glow and the awake Door readable from 2 cells away.
9. The hazard telegraph on a dark floor. Can a phone player pass by the ring in its 1.5-stud lane?
   How does the 0.8 s knock feel?
10. Reveal latency: no pop-in in front of a player at 16 studs/s on a 300 ms connection.
11. The display timer against the official time at the finish (it should only jitter).
12. Hub: the board's SurfaceGui legible from the spawn; the ProximityPrompt toggle; the campfire sit
    (`Humanoid.Sit` without a seat, as plus1 EYECANDY §8.11).
13. The Sanctum's dawn look and the "THE DOOR IS SEALED" fanfare (flash + FOV punch).
14. Frame time on a low-end phone at 220 local parts, 4 lights and 4 emitters.
15. Place settings: MaxPlayers 12, avatar type (the vertical check assumes a root about 3 studs up).
16. The Studio fallback door with API access off (for thumbnails and clips).
17. The midnight rollover in a live server (headless covers the logic, with the check overriding
    `os.time`).
18. The top bar under a notch or safe area.

---

## 20. Reproducing the numbers

The scripts are in `same-door/design/measure/`. They are measurement tools, not game code; Rojo
never maps them. Run from that folder with the luau CLI, appending `2>&1`:

| script | prints |
|---|---|
| `funnel_test.luau` | the funnel against the analytic L-turn (22.952) |
| `stats.luau` | route and perfect-line statistics for 7 × 7 .. 11 × 11 |
| `extras.luau -a band` | the band-filtered perfect line, first seal, first runs, walls, Door distance (`extras.luau` alone: unfiltered and acceptance rate) |
| `run_days2.luau` | cumulative minutes to each medal over daily sessions |
| `perday.luau` | medals per day |
| `hzrand2.luau` | hazard near-miss rates (fork placement) |
| `hzrand.luau` | hazard near-miss rates (the rejected random placements) |
| `pacing3.luau -a 9 9 8 150` | the multiplier sweep, variance model |
| `pacing2.luau -a 9 9 8 150` | the same sweep without variance (the rejected knife-edge) |
| `pacing.luau -a 9 9 8 1.6 1.3 1.1 200` | the rejected exponential learning curve |

`store.txt` holds the store text draft (§22).

---

## 21. Open decisions for the owner (defaults in force until he says otherwise)

1. **The brag moment's timing.** Default: the first Sealer (×1.10 P), at a median of 33.7 cumulative
   minutes for a normal player, usually on day 2. The single-session alternative would move Sealer
   so the same player reaches it in one 45-minute sitting, which sits close to that player's
   asymptote (×1.16 gave 27.4 min with 44 of 150 days never reached in 90 min; `pacing2.luau`, the
   no-variance model). The default is recommended.
2. **Slow players' summit is Gold** (51 % of their days). A gentler brag for them would be a new
   feature, and is not in v1.
3. **MaxPlayers 12** (§4).

## 22. Artifacts that follow from this spec (written at build time, seeded here)

**Store text** (for `README.md`): 836 characters, measured, ASCII only, no emoji. The draft is in
`design/measure/store.txt`. It says: the same dungeon for everyone; new every day at 00:00 UTC;
3 Seals and the Door; unlimited retries, best counts; medals including Sealer; red rings; public
and friends boards with ties to whoever was first; streaks; nothing to buy.

**Clip seeds** (`MARKETING.md`, vertical 1080 × 1920, 7-15 s, staged on the Studio door by walking,
since a teleport inside a run voids it and stops the reveal, by design):

1. The line and the first seal: the clock starts, then the Cellar-to-Moss glide.
2. The third seal: the Ember Vault, and the Door waking in the next hall.
3. The red ring at a fork: a sidestep, and the stalactite lands a stud away.
4. SEALED: the finish at ≤ 1.10 P, the white-gold Door, the Sanctum at dawn.
5. The board flipping from Public to Friends in the hub.
6. Run again: the same hall taken faster, corner-cut, timer on screen.

**Thumbnail seeds** (`EYECANDY.md`, 1920 × 1080): the Door head-on at the end of a torchlit hall;
the Sanctum with the sealed Door at sunrise; a fork with the red ring and the falling stalactite;
the hub board with medal plates. The full shot list, with camera and place for the Studio door,
is written when the Studio door's coordinates exist.
