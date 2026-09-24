# Labyrint — biomes you walk deeper into

Owner's brief (Gustav, 2026-09-17): every game richer and never monotonous, with the environment
changing as the player progresses, following what the game is about; rare, telegraphed hazards (about
one near-hit per 2-3 minutes, easy to see and avoid); a way to rest that can never be exploited; a
thumbnail shot list for a night session in Studio.

What this game is about decides everything below: **500 procedural maze levels, dark, one torch,
pulsing lava traps whose timings keep every level winnable, monsters slower than the player, medal
times from a shared seed.** So the rule was: the maze may look different, it may not *play* different
in any way that touches solvability, trap timing, how far you can see, or the fairness of medal times.

**State: built, unit-tested, headless-tested through the real server and clients, mutation-tested with
controls, adversarially reviewed, and every review finding closed (§12). NOT seen in Studio.** Nothing
committed, pushed or published. The server script is untouched (`git diff` on `src/server`: empty).

**Review fixes, 24.09 (§12):** the door sign no longer promises "nothing is lost" while a bought "Hjelp meg"
guide would be lost; a sinking secret door's dressing fades and is released instead of leaving spires and
columns sticking out of the floor; the hazard ring is **blue**, never the trap's lethal yellow; three rules no
suite held now have assertions; the budget peak is measured over every cell (49 parts, not 41); the thumbnail
place carries a never-publish warning.

**Resumed after a usage-limit cut (§11).** Earlier sessions had built everything except this file. The
resume session re-read every new file, found the last edit never built or gated, rebuilt, re-ran every gate,
fixed one real defect and one latent one, closed five test gaps (two found while planning the sweep, three by
it), added a compile gate and a tested shot-list helper, and ran a 42-mutation sweep with controls (§7).

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template**, byte-identical copy of +1 Jump's (progress → band + eased blend, glide, `capRates`, `hash01`). Pure. |
| `src/shared/Rest.luau` | **template**, byte-identical copy of +1 Jump's rest state machine. Pure. |
| `src/shared/Biomes.luau` | the eight biomes and every eye-candy number in one block: hue grades, air particles, 27 decor pieces, hazard config, rest config, budgets; `validate` enforces the rules in §2. Pure (EnvBands passed in). |
| `src/shared/CellHazards.luau` | rare falling hazards fixed to maze cells and the level clock (§3). Pure. Not the template's `Hazards`: that one aims random lanes at the player on a random clock, which a timed game with shared medal times cannot have. |
| `src/shared/BreakRoom.luau` | what "rest" means in a timed maze (§4). Pure (Rest passed in). |
| `src/shared/BiomeArt.luau` | builds decor pieces, the air emitter box and the hazard views. Client-only, code-only, pooled. |
| `src/client/Biome.client.luau` | the glue: level → grade (glided), air, decor, hazards + knock, title cards, hazard banner. |
| `src/client/RestClient.client.luau` | the lobby campfire corner (rest), the biome board, the free-break sign on each level's Lobby door. |
| `tests/` | new specs `Biomes`, `CellHazards`, `BreakRoom`, `Pacing`, plus the template's `EnvBands`, `Rest` specs verbatim; `MazeWalker.luau` (test-side player model). |
| `robloxemu/check_labyrintspill_*.luau` | `biomes`, `hazards`, `rest`, `cards`, `budget`, `layout`, `hud` (the stock HUD gate with all 13 clients), `lib` (shared boot); **resume session:** `compile`, `shots`. |
| `src/server/*` | **nothing.** |

Existing files: none edited. `check_labyrint.luau` still loads only the 11 original clients (its one-line
comment change dates from 2026-09-17 and is not this work); `check_labyrintspill_hud.luau` runs the same
gate with all 13.

---

## 2. The biomes and what triggers them

**Trigger: the LEVEL, never time.** Every `LevelInfo` payload the server sends for a maze carries the level
number the HUD shows. The biome is *named* by that number (title card, board, which hazard falls) and
*blended* over the `fade` levels before a boundary (colours, particles, decor share). Within a level
nothing changes; from level to level the colour grade glides with a 0.6 s half-life, so finishing level
23 and walking into 24 slides the torch about a third of the way from jungle lime toward ice white over a
couple of seconds instead of cutting (measured through the real client: no single write moves more than a
quarter of the change, no overshoot). Entering the maze from the lobby
snaps together with the darkness itself, as `LightingClient` already does (rule 1 in that file: darkness
does not fade in).

| # | biome | named from | blends in on | maze | traps | monsters | minutes to start (normal / fast / slow) | grade + torch | air (particles/s) | wall decor (share of faces) | hazard (cells per level) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏚️ Stone Dungeon | L1 | — | 6×6 | 0-1 | 0-1 | 0 | **the live game, number for number** | dust 6 | chains, unlit sconces, cracks, banners (35 %) | none |
| 2 | 🌿 Jungle Ruins | L11 | L9-10 | 7-8 | 1-2 | 1 | 5.1 / 4.5 / 5.9 | green fog, lime torch | fireflies 6 | vines, leaf clusters over the wall tops, moss, roots (45 %) | none |
| 3 | 🧊 Ice Cellar | L26 | L23-25 | 8-10 | 2-3 | 1-2 | 12.7 / 11.5 / 14.8 | cold blue, ice-white torch | snow 16 | icicle clusters, frost, snowcaps (50 %) | 🧊 icicle (2-3) |
| 4 | 🔥 Lava Forge | L51 | L47-50 | 11-15 | 3-6 | 2-4 | 40.6 / 33.1 / 46.3 | ember orange | embers 10 | chains, grates, soot, rusted pipes (40 %) | 🌋 lava bomb (4-7) |
| 5 | ✨ Crystal Caverns | L101 | L96-100 | 16-21 | 6-10 | 4-7 | 2.4 h / 2.0 h / 3.0 h | violet | sparkles 10 | crystal clusters, geodes, spires over the wall tops (45 %) | 🔷 crystal shard (8-13) |
| 6 | 💀 Haunted Crypt | L161 | L154-160 | 22-29 | 10-12 | 7-10 | 6.3 h / 5.3 h / 7.7 h | grave green | mist 4 | skulls on ledges, bones, cobwebs, candles (45 %) | 🕯️ chandelier (15-25) |
| 7 | ☁️ Sky Ruins | L241 | L232-240 | 30 | 12 | 10 | 17.5 h / 14.0 h / 20.3 h | night-sky blue | wisps 5 | marble columns and cloud puffs over the wall tops, gold trim, vines (45 %) | ⚡ lightning (27) |
| 8 | 🌌 Astral Labyrinth | L351 | L340-350 | 30 | 12 | 10 | 38.9 h / 29.7 h / 46.1 h | deep violet | stardust 12 | floating rocks, star bits, runes, spires (45 %) | ☄️ meteor (27) |

"Blends in on": the levels where the next biome already has a share (jungle: 26 % at L9, 74 % at L10).
Hazards do not blend: a band either has its falling hazard or not, from its first level exactly.

Also on screen: a title card on entering a biome (`🧊 YOU REACHED THE ICE CELLAR!` with a flash and FOV punch,
once per biome per session, when the player has never cleared a level there; otherwise a quiet
`🧊 Ice Cellar / Levels 26-50`), which always waits until the level-complete card has gone; the fanfare
card's subtitle introduces the biome's hazard (`🧊 ICICLE! watch for the blue ring`). In the lobby, the
**biome board** next to the campfire lists every biome reached with a tick, the next one with its level,
and the rest as `🔒 ???` — the brag.

### The rules the biomes are held to (`Biomes.validate`, `Biomes.spec`, `check_labyrintspill_biomes`)

1. **Darkness is the mechanic.** A biome may write six HUE fields only: fog colour, outdoor ambient,
   atmosphere colour and decay, the colour-correction tint and the torch colour, **each at the luma of the
   live value** (±1.5 %, or ±0.6 of 255 where that is larger: the near-black fog colours). The sight fields — `Ambient`, `Brightness`, `ClockTime`, `FogStart/FogEnd`,
   atmosphere `Density/Haze`, torch `Range/Brightness` — are not biome fields at all, and the check reads
   every one of them back at every biome and every seam through the real client. The first biome is the
   live game: identical values, asserted.
2. **The trap signal survives every grade, and nothing else glows in it.** The trap's yellow WARNING (255,205,60) and orange DEADLY
   (230,90,30) phases are the survival signal. Under each biome's colour grade their green/red ratios must
   stay ≥ 0.62 and ≤ 0.48 and at least 0.3 apart; grades are mild (no channel below 76 % of another) and the
   torch near-white (≥ 60 %). Nothing non-lethal glows in those colours: the falling-hazard ring is blue under
   every grade (§3; review fix).
3. **Walls are never recoloured** (the theme shop sells that). Biomes dress walls with small pieces:
   no Neon (in this maze glow means "interactive"), no lights, never below 3 studs (the secret door's
   coloured band and the floor stay clear), at most 1.2 studs out of the face (coins and buttons sit
   4.5 studs from a wall), at most a quarter of a face. Placement is a pure function of the wall's grid
   position, the face and the level, **never of what kind of wall it is**: a secret door is dressed
   exactly like the plain wall it pretends to be. Proven with a control that renames every secret door to
   `Wall` before the client sees it: byte-identical decor. When a door's button is pressed, its dressing
   rides down with it while it fades out (0.35 s), and is released at once if the door is already under the
   floor; a sinking or sunk door is never dressed again and takes no decor slot (`Biomes.wallState`: judged
   from the wall's position, which every player sees, never its name). Review fix, §12: before it, crystal
   spires and marble columns, which stand on the wall top and reach higher than the 26 studs a door sinks,
   were left sticking 2.5-3 studs out of the floor where the door had been.
4. **Decor is only built around walls within 24 studs** (inside the torch's 28; `validate` refuses a
   radius past `TorchRange - 4`), at most 26 pieces, nearest first.

### What "normal player" assumes (pacing)

There is no telemetry, so time-to-biome comes from `tests/MazeWalker.luau` walking **the game's own
mazes** (`MazeGen` at the live curve, which `check_labyrintspill_biomes` parses out of the server source
and compares) with a written-down player: 16 studs/s, depth-first exploration, heading for the exit
corner at a fork with probability 0.7 (fast 0.85, slow 0.55), 0.8 s at each fork (0.3 / 1.5), 0.6 s to turn
round at a dead end (0.3 / 1.0). **No deaths and no retries**, so every number is a lower bound; the model
cannot see monsters or traps. Asserted in `Pacing.spec`: the first new biome within 10 min (5.1), the
second within 25 (12.7), every biome lasts at least 5 min, fast ≤ normal ≤ slow. The later biomes are the
long goal of a 500-level game (the Astral Labyrinth is the equivalent of +1 Jump's galaxy). **To move a
biome, change its `from` in `Biomes.Bands`; `Pacing.spec` prints where it lands.**

---

## 3. Hazards and their measured rarity

A falling hazard belongs to the **level**, like the lava pulse: the same cells and the same moments of the
run for everyone on that level, so medal times stay comparable.

| kind | biome | what falls | warning | then |
|---|---|---|---|---|
| 🧊 icicle | Ice Cellar | an icicle cluster (ice wedges, faint core glow) | 3.0 s | ice shards |
| 🌋 lava bomb | Lava Forge | a basalt ball with a molten core | 3.0 s | orange sparks |
| 🔷 crystal shard | Crystal Caverns | a cluster of glass shards | 3.0 s | glass glints |
| 🕯️ chandelier | Haunted Crypt | an iron hoop with four candles | 3.0 s | candle-flame sparks |
| ⚡ lightning | Sky Ruins | a storm puff overhead; the bolt exists only for the strike | 3.0 s | white flash sparks |
| ☄️ meteor | Astral Labyrinth | a dark rock with a violet glow | 3.0 s | violet sparks |

**Rules** (`CellHazards.luau`, refused by `CellHazards.validate` if broken; an invalid config turns
hazards OFF with a warning, never half on):

* **Where:** a pure function of (level, maze size, the level's trap cells) — no RNG state, no clock, no
  player. 3 % of cells (at most 40 per level, never two within 3 cells of each other), never the start, the
  exit, a trap cell, or within 2 cells of the start. The client reads the trap cells from the replicated
  `Trap` parts, so it gets the server's real ones.
* **When:** each hazard cell runs a fixed 14 s cycle on the **level clock** (seconds since this level's
  payload arrived): quiet → a 3.0 s warning → one impact instant → 1.2 s of harmless debris → quiet. The
  first impact is never within the first 4 s of a level. `validate` refuses a warning under 2.5 s (floor 2 s)
  and a cycle without 3 s of quiet.
* **Telegraph:** a pulsing **blue** ring on the cell floor (the danger zone, exactly as wide as the hit
  rule), a dark inner disc so it reads as a ring, a shadow that grows toward the impact, the object hanging
  over the cell, shaking, and dropping in the last 0.35 s; a banner `⚠️ 🧊 ICICLE! step out of the blue ring`
  when it is within 20 studs. Drawn only within 26 studs of the player (inside the torch), at most two at
  once. **Why blue (review fix, §12):** the ring used to be the trap's own warning yellow, but glowing yellow
  on this floor has always meant "this floor kills you in a moment"; a yellow ring that only knocks you down
  teaches players that yellow is survivable. The server's own palette already refused the trap's yellow for
  the secret-door colours for the same reason. `Biomes.validate` holds the ring cool under every biome grade
  (blue/red ≥ 1.5, at least 1.0 above either trap phase), and the banner and biome card take their words from
  `Biomes.hazardBanner/hazardIntro`, which the layout check measures.
* **The hit rule:** at the impact instant, your root within 4.2 studs horizontally of the cell centre
  (strike radius 3.2 + player radius 1.0) **and at most 20 studs above the floor** (resume session: a jump
  never dodges, but a god-mode flyer over the maze is not knocked out of the air). The zone is 8.4 studs
  across inside a 9-stud cell, so **the passage next to a hazard cell is always safe**: a hazard can make
  you wait, never wall a level off. Debris is harmless; standing in the ring during the warning is harmless.
* **A hit** knocks you down for 0.8 s (`PlatformStand`) with a 5 studs/s horizontal push away from the
  impact (4 studs at most), never upward; camera shake and a white flash. `validate` proves the farthest
  knock cannot carry you onto the neighbouring cell's trap (8.2 studs from the hazard centre at most; the
  next trap's edge, player radius included, is 13.5 away). Nothing is taken: no death, no coins, no time
  penalty beyond the 0.8 s. **One real consequence, stated:** a player who takes a hit with a monster on
  their heels loses 0.8 s of their lead, and a monster within ~12 studs can then catch them. The warning
  (3 s, visible from the passage before the cell) is what makes that avoidable.

**Measured** (`tests/Pacing.spec.luau`: 40 levels spread over every hazard biome, one normal walk each,
1 443 minutes walked, 3 672 hazards in 122 200 cells = 3.00 %). A *near-hit* is an impact within 12 studs
of the player that did not hit them — in practice, waiting in the passage beside a falling icicle.

| biome | a player who reacts to the warning | a player who ignores every warning |
|---|---|---|
| 🧊 Ice Cellar | 0.392 near-hits/min (**one per 2.6 min**), 0 hits | 0.026 hits/min |
| 🔥 Lava Forge | 0.492 (**one per 2.0 min**), 0 hits | 0.062 |
| ✨ Crystal Caverns | 0.389 (**one per 2.6 min**), 0 hits | 0.080 |
| 💀 Haunted Crypt | 0.385 (**one per 2.6 min**), 0 hits | 0.053 |
| ☁️ Sky Ruins | 0.396 (**one per 2.5 min**), 0 hits | 0.073 |
| 🌌 Astral Labyrinth | 0.360 (**one per 2.8 min**), 0 hits | 0.051 |
| **all** | **0.387 (one per 2.59 min), 0 hits** | 0.095 near/min, 0.061 hits/min (**one hit per 16.3 min**) |

Asserted: 0.3-0.55 near-hits/min in every biome and 1/3-1/2 over all of them; a reacting player is never
hit; a player who ignores warnings is hit, at most about once per 8 minutes. None in the first two biomes.

**Medal fairness** (same file): a speedrunner on the **par route** (the route the medal times come from)
who waits only when it would otherwise be in a zone at an impact, over 240 levels: 41 levels delayed at all;
mean delay 0.074 s (0.036 % of par); worst level 1.71 s (0.65 % of par); longest single wait 0.66 s (asserted: never
more than one crossing of the 8.4-stud zone, 0.53 s, plus 0.15 s). Diamond is par × 1.3, so a hazard never costs anyone a medal, and since placement
and timing are fixed per level it is the same fraction for everyone on that level. (A runner who ignores
hazards is hit 39 times in 240 levels, 0.8 s each; that is a choice, not luck.) The one unfairness left is
network delay: the level clock starts when the payload *arrives*, so a player with 150 ms more ping meets
every impact 150 ms later in server time.

---

## 4. Rest — what "pause" means in the labyrinth

A Roblox server cannot stop the world for one player, and in this game **the run clock is the medal and
the record**, the traps pulse on the server and the monsters hunt on the server. A pause *inside* a run
would either freeze nothing that matters (and tell the player they are safe when they are not) or freeze
the clock (and hand out free medal time). So rest lives **between runs** (`BreakRoom.luau`):

* **The lobby is the break room.** It has no monsters, traps, hazards or clock, and now a campfire corner
  (logs, stones, three benches, flames, smoke, a warm light) with a `☕ Break room — Rest by the fire`
  prompt. One tap and you sit, the view softens (depth of field), and a toast says
  `☕ Resting by the fire — nothing is running. Move to get up.` Any move or jump gets you up (the template's
  `Rest` state, `WakeOnMove` enforced by `Rest.validate`). Idle rest is off (the lobby has nothing to be
  safe from). The biome board stands beside it.
* **Every level starts beside the 🚪 Lobby door.** For the first 6 s of a level a sign on that door says
  `☕ Need a break? Walk out now — it's free, nothing is lost`, fading out over its last second. That is the
  server's own rule: a voluntary return shorter than `CONFIG.Assist.MinRunSeconds` (8 s) is not counted as
  a failed attempt. The sign's window ends 2 s before the server's rule does (`validate` insists on at
  least 1.5 s of network margin), and its clock is the larger of frame time and wall time, so a stalled
  client's sign can only vanish early, never linger. Proven end to end against the server's own counter, burning real seconds: a walk-out under the
  sign or after a 6.3 s stall adds no failed attempt; after 8 s one is added, and no sign promised otherwise.
  **Not while a guide is active (review fix, §12):** a "Hjelp meg" guide is bought for ONE run and the server
  tears it down with the run, no refund, so a walk-out then does lose something. While the server's
  `AssistState` says a guide is active, the sign is not shown (`BreakRoom.freeBreak(elapsed, cfg, run)`
  returns false), and it goes at once if the guide is bought while it is up. Proven end to end: three counted
  walk-outs at L42, the server offers the guide, it is bought 0.5 s into the run, the sign is gone on the next
  frame and stays gone; the walk-out then loses the guide without a refund (server rule, unchanged).
* Inside a run, rest does not exist: the prompt is off, and `BreakRoom.mayRest` fails closed if it fires
  anyway.
* Roblox's own ~20-minute idle disconnect still applies in the lobby; nothing is lost by it (progress is
  saved by the server as before).

**Why it cannot be exploited**

1. **Nothing is paused.** Leaving a run ends it: its clock is thrown away, no time is recorded, the next
   attempt starts a fresh clock with the same maze (levels are deterministic). No clock is ever frozen.
2. **The only promise the sign makes is the server's own**, and it expires before the server's rule does.
   Walking out after the sign is gone costs exactly what it always cost (one counted attempt, which only
   ever moves the "Hjelp meg" offer closer). It never shows while a bought guide would be lost.
3. **Nothing can happen while resting.** Resting is only possible in the lobby, any movement ends it, and it
   sends nothing to the server (checked: zero remote calls).
4. **Hazards are part of the level, not the player**, so there is nothing to dodge by resting: the hazard
   clock restarts with every run, exactly like the lava pulse.

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| colour grade, air particles, decor, title cards, biome board, campfire, door sign | **client** (`Biome.client`, `RestClient`, `BiomeArt`) | cosmetic and per-player (each player is in their own maze instance at their own level); costs the server nothing and replicates nothing |
| falling hazards: cells, timeline, telegraph, hit test, knock | **client** | a hazard only harms the local player, whose character physics the client already owns. Nothing is awarded, removed or recorded by it. An exploiter who deletes hazards saves at most 0.66 s per hazard, far less than the teleport exploit `CLAUDE.md` already lists as a platform limit |
| rest | **client** (lobby only) | it pauses nothing; it sits you down |
| runs, run clock, medals, records, `accepted`, traps, monsters, the Assist counter, saves | **server, unchanged** | authoritative, as before |

**Leak review.** The clients read: the `LevelInfo` payload (level, the player's own `accepted`), the
player's own maze folder (walls and secret doors *into one table without their names*, trap parts, the
floor, the Lobby door), the player's own character and `Lighting`; and (review fix) the player's own
`AssistState`, which the server already sends to that player alone, for the door sign. Decor never depends on
a wall's kind (the rename control in §2), only on where a wall is (a sinking door is visibly moving for
everyone); hazards and decor are drawn only near the player, inside the torch. The clients
fire no remote and add none (checked by hooking every `RemoteEvent` on the server side), set no attribute
anywhere (checked with a before/after snapshot of every attribute in `Workspace` and `Players`), and every
part they create is anchored and non-collidable, non-queryable, non-touchable, shadowless — it cannot block
a monster's path (pathfinding is server-side and never sees it), catch a touch, swallow a camera ray or be
stood on. They do write *properties* on three server-built objects, locally: the torch's `Color`, the
Atmosphere's `Color/Decay` and the ColorCorrection's `TintColor` (never range, brightness, density or haze).
Those writes do not replicate. The only light added is the campfire's, in the lobby, switched off while you
are in a maze. Spawn order (`robloxemu/SPAWN-ORDER.md`) is untouched: neither client writes the character's
CFrame (asserted by source scan); the knock sets velocity only.

**What other players see.** Hazards are local. In a Group or Friends run each player's level clock starts
with their own payload, so two players in the same maze can see the same icicle fall at slightly different
moments, and when one is knocked the others see them fall over with nothing hitting them.

---

## 6. Budgets (measured)

Client-built only; the server builds none of this. Three measurements and one bound, all through the real
server and all 12 clients (SoundClient left out: see `check_labyrintspill_lib`):

**At the start of a run in every biome and every seam** (`check_labyrintspill_biomes`, 2.5 s in):

| where | level | local parts | air emitters (rate/s) | lights | decor parts |
|---|---|---|---|---|---|
| 🏚️ dungeon | 6 | 13 | 1 (6) | 0 | 12 |
| 🏚️ › 🌿 | 9 | 9 | 2 (6) | 0 | 8 |
| 🌿 jungle | 18 | 21 | 1 (6) | 0 | 20 |
| 🌿 › 🧊 | 24 | 9 | 2 (11) | 0 | 8 |
| 🧊 ice | 38 | 9 | 1 (16) | 0 | 8 |
| 🧊 › 🔥 | 48 | 9 | 2 (13.9) | 0 | 8 |
| 🔥 forge | 76 | 13 | 1 (10) | 0 | 12 |
| 🔥 › ✨ | 98 | 8 | 2 (10) | 0 | 7 |
| ✨ crystal | 131 | 12 | 1 (10) | 0 | 11 |
| ✨ › 💀 | 157 | 12 | 2 (7) | 0 | 11 |
| 💀 crypt | 201 | 14 | 1 (4) | 0 | 13 |
| 💀 › ☁️ | 236 | 6 | 2 (4.5) | 0 | 5 |
| ☁️ sky | 296 | 14 | 1 (5) | 0 | 13 |
| ☁️ › 🌌 | 345 | 14 | 2 (8.5) | 0 | 13 |
| 🌌 astral | 401 | 13 | 1 (12) | 0 | 12 |

**Walking 60 cells through the middle of each biome's biggest maze, every frame** (`check_labyrintspill_budget`):

| biome | level | maze | peak parts | peak decor parts | peak emitters (rate/s) | hazards drawn |
|---|---|---|---|---|---|---|
| 🏚️ dungeon | 10 | 6×6 | 29 | 28 | 2 (6) | 0 |
| 🌿 jungle | 25 | 8×8 | 41 | 40 | 2 (14.4) | 0 |
| 🧊 ice | 50 | 10×10 | 31 | 30 | 2 (10.6) | 0 |
| 🔥 forge | 100 | 15×15 | 29 | 28 | 2 (10) | 1 |
| ✨ crystal | 160 | 21×21 | 38 | 37 | 2 (4.3) | 1 |
| 💀 crypt | 240 | 29×29 | 39 | 33 | 2 (5) | 1 |
| ☁️ sky | 350 | 30×30 | 35 | 34 | 2 (11.9) | 1 |
| 🌌 astral | 480 | 30×30 | 40 | 34 | 1 (12) | 1 |

**Every open cell of each biome's biggest maze, one frame standing at its centre** (`check_labyrintspill_budget`,
review fix, §12: the 60-cell walk above understated the peak, 41 against the review's 49; a sample cannot
find a maximum, so the documented peak comes from here):

| biome | level | open cells visited | peak local parts | peak decor parts | where (fine cell) |
|---|---|---|---|---|---|
| 🏚️ dungeon | 10 | 71 | 44 | 43 | 3,8 |
| 🌿 jungle | 25 | 127 | **49** | 48 | 3,10 |
| 🧊 ice | 50 | 199 | 42 | 41 | 11,15 |
| 🔥 forge | 100 | 449 | 31 | 29 | 11,21 |
| ✨ crystal | 160 | 881 | 44 | 39 | 29,28 |
| 💀 crypt | 240 | 1 681 | 44 | 40 | 17,32 |
| ☁️ sky | 350 | 1 799 | 42 | 41 | 2,47 |
| 🌌 astral | 480 | 1 799 | 46 | 45 | 27,32 |

**The bound that holds whatever the position** (same check, built by the real `BiomeArt`): 26 decor pieces ×
4 parts + 2 hazard views × 9 parts (the largest kind, the chandelier: ring, inner disc, shadow, hoop, four
candles, flames) + 1 air box = **123 parts**, under the 140 budget. The every-cell peak is a measurement at
cell centres (decor is re-selected on entering a cell, from the entry point); the bound is the guarantee.

| metric | measured peak (any frame of any check) | budget (`Biomes.Budget`) |
|---|---|---|
| local parts in a maze | **49** (L25, every-cell sweep; structural bound 123) | 140 |
| decor pieces | about 10 wanted at a real maze position (the middle of L200); 48 parts peak | 26 pieces × 4 parts (proved to bind by forcing it to 5) |
| enabled emitters | 2 | 4 (2 air + impact bursts) |
| particles per second | **16** (ice cellar snow) | 40 |
| lights in a maze | **0** | 0 (a light would add sight) |
| hazards drawn at once | 1 | 2 |
| lobby break room | 13 parts, 2 emitters (27/s), 1 light — only while you are in the lobby | 1 light |

**What is pooled / how it stays cheap:** decor pieces are pooled per piece type and re-parented, never
rebuilt; the full re-selection runs only when the player crosses into a new grid cell, and between those
only fading pieces or pieces on a moving wall are re-placed. One invisible 34×18×34 box follows the player
and carries the air emitters (created lazily, one per kind, at most two enabled, their rates capped by
`EnvBands.capRates`). Two pooled hazard views (ring, inner disc, shadow, one burst emitter fired with
`Emit(18)` at the impact, the object's 2-6 parts, rebuilt only when the kind changes). Lighting is written
at most 10×/s and only when a value differs. The pools stop growing once warm: 479 unique instances created
over the whole budget check by the end of the first round of 8 biome hops (the every-cell sweep before it
builds most of the piece variety), **0 new** across two more rounds. A sinking door's pieces go back to the
pool once faded (or at once if the door is already under the floor), and a sinking or sunk door takes no
decor slot. These are part and emitter counts,
not frame rate: phone frame time is on the Studio list.

---

## 7. Gates

"Before" is the committed game (`git archive HEAD`, rebuilt and run in a scratch copy). "Previous session"
is the last gate log the cut-off session wrote (`scratchpad/labyrint_eyecandy/gates_after1.txt`); its last
source edit came 35 s after that run and was never built or gated (§11). "Resume" is that session's final
run on its final tree. "Review fix" is the final run after the adversarial review's findings were closed (§12),
on bundle md5 `5d8c2b9b9c7cc2fcc3153cb7ddac9c7a`.

| gate | before | previous session | **resume (final)** | **review fix (final)** |
|---|---|---|---|---|
| `tests/Assist.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/Contributors.spec` | 18 / 0 | 18 / 0 | 18 / 0 | 18 / 0 |
| `tests/Hazard.spec` (the lava pulse) | 36 / 0 | 36 / 0 | 36 / 0 | 36 / 0 |
| `tests/Progression.spec` | 33 / 0 | 33 / 0 | 33 / 0 | 33 / 0 |
| `tests/lightingpresets.spec` | 41 / 0 | 41 / 0 | 41 / 0 | 41 / 0 |
| `tests/mazeref.spec` | 27 / 0 | 27 / 0 | 27 / 0 | 27 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/touchtarget.spec` | 52 / 0 | 52 / 0 | 52 / 0 | 52 / 0 |
| `tests/Biomes.spec` | — | 1 115 / 0 | **1 121 / 0** | **1 183 / 0** |
| `tests/CellHazards.spec` | — | 66 / 0 | **73 / 0** | 73 / 0 |
| `tests/BreakRoom.spec` | — | 28 / 0 | 28 / 0 | **35 / 0** |
| `tests/EnvBands.spec` (template) | — | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/Rest.spec` (template) | — | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Pacing.spec` | — | 278 / 0 | 278 / 0 | 278 / 0 |
| **spec total** | **347 / 0** | **2 013 / 0** | **2 026 / 0** | **2 095 / 0** |
| `robloxemu/check_labyrint` (HUD fit, 11 clients) | PASS | PASS | PASS | PASS |
| `robloxemu/check_labyrint_spawn` | 34 / 0 | 34 / 0 | 34 / 0 | 34 / 0 |
| `robloxemu/check_lighting` | 19 / 0 | 19 / 0 | 19 / 0 | 19 / 0 |
| `robloxemu/check_secretdoors` | 50 / 0 | 50 / 0 | 50 / 0 | 50 / 0 |
| `robloxemu/check_themes` | 23 / 0 | 23 / 0 | 23 / 0 | 23 / 0 |
| `robloxemu/check_labyrintspill_hud` (HUD fit, all 13 clients) | — | PASS | PASS | PASS |
| `robloxemu/check_labyrintspill_biomes` | — | 259 / 0 | 259 / 0 | **291 / 0** |
| `robloxemu/check_labyrintspill_hazards` | — | 48 / 0 | **50 / 0** | **66 / 0** |
| `robloxemu/check_labyrintspill_rest` | — | 53 / 0 | **55 / 0** | **67 / 0** |
| `robloxemu/check_labyrintspill_cards` | — | 14 / 0 | **17 / 0** | 17 / 0 |
| `robloxemu/check_labyrintspill_budget` | — | 12 / 0 | **15 / 0** | **26 / 0** |
| `robloxemu/check_labyrintspill_layout` | — | 266 / 0 | 266 / 0 | 266 / 0 |
| `robloxemu/check_labyrintspill_compile` | — | — | **46 / 0** (new) | 46 / 0 |
| `robloxemu/check_labyrintspill_shots` | — | — | **54 / 0** (new) | 54 / 0 |
| **headless check total** | **126 / 0 + PASS** | **778 / 0 + 2 PASS** | **888 / 0 + 2 PASS** | **959 / 0 + 2 PASS** |

Stability: the emulator's `Random` is unseeded where the game does not seed it (monster wander), so every
headless check was run three more times after the final run: identical summaries all three times. (Review
fix: the final run and two more runs of every headless check gave identical summaries.)

Static: this machine has no `luau-analyze` or `luau-compile`. `check_labyrintspill_compile` compiles all
38 bundled sources through `loadstring` (the same compiler front end) and asserts the 8 new modules are
in the bundle; every test and check file compiles by running. A scratch lint for assignments to undeclared
globals (`scratchpad/lab_resume/globals_lint.py`) finds nothing in any `src/shared` or `src/client` file,
and does find the `signRun` defect of §11 in a copy with it put back (its control).

**Mutation sweep** (`scratchpad/lab_resume/sweep.py` + `mutations.py`; logs `sweep_r1.log`, `sweep_r2.log`,
results `sweep_r1_results.json` and `sweep_results_G11_G13_R2_CONTROL-1_CONTROL-2.json`). The real tree is
never mutated: two workers each get a scratch copy of `labyrint-spill/src`, `tests` and every robloxemu file
the gates use, verified byte-identical to the real tree, with a baseline bundle equal to the real one apart
from path strings and green on all 28 suites. For each mutation: exactly one occurrence in the file **and in
the bundle**; replaced; the bundle rebuilt and **proved to contain it** (the mutated bundle equals the
baseline bundle with the same single replacement: 42 of 42); all 28 suites run (14 specs, 14 checks); the
original bytes restored and the md5 re-verified. At the end the real sources were byte-identical to the
copies.

**Round 1: 42 mutations: 37 killed, 3 survived, both controls survived (as they must).**

| id | mutation | killed by |
|---|---|---|
| B1 | `validate`: the luma lock off (a biome may brighten) | `Biomes.spec` |
| B2 | client: secret doors not collected with the walls (a decor leak) | `check_labyrintspill_biomes` (the rename control, the sinking door) |
| B3 | `decorFor`: density ignored | `Biomes.spec` |
| B4 | `validate`: the decor-radius rule off (resume session) | `Biomes.spec` |
| B5 | the dungeon's fog colour 1/255 off, luma-true | `Biomes.spec`; `validate` then turns the biome layer off, so 6 checks too |
| B6 | `validate`: the trap-signal rule off (resume session's new case) | `Biomes.spec` |
| C1 | `validate`: a zone wider than the cell allowed | `CellHazards.spec` |
| C2 | `pick`: hazards may land on trap cells | `CellHazards.spec` |
| C3 | `checkHit` ignores the zone | `CellHazards.spec`, `_hazards`, `_shots` |
| C4 | `checkHit` without the height cap (resume session) | `CellHazards.spec`, `_hazards` §8 |
| C5 | the knock pushes upward | `CellHazards.spec` |
| C6 | the first impact inside the grace period | `CellHazards.spec`, `Pacing.spec`, `_hazards` |
| C7 | the warning half as long | `CellHazards.spec`, `_hazards` |
| C8 | `pick`: MinSpacing ignored | `CellHazards.spec` |
| P1 | density 3 % to 6 % | `Pacing.spec` (ice 1.172 near-hits/min) |
| P2 | cycle 14 s to 8 s | `Pacing.spec` (ice 0.595) |
| G1 | client writes `Lighting.Brightness` | `_biomes` (sight lock) |
| G2 | a level change cuts instead of gliding | `_biomes` |
| G3 | hazards drawn out to 3x ShowRadius | `_hazards` (267 far rings) |
| G4 | the ring drawn at 70 % of the zone | `_hazards` (5.88 vs 8.4) |
| G5 | the knock never wears off | `_hazards` |
| G6 | a dead player is knocked | `_hazards` |
| G7 | the level clock not restarted by a new run | `_hazards` |
| G8 | the fanfare repeats | `_cards` |
| G9 | the biome card covers the level-complete card | `_cards` |
| G10 | the grade kept in the lobby | `_biomes` |
| **G11** | **the decor cap ignored** | **SURVIVED**, then `_budget` (new section) |
| G12 | hazards in the dungeon and jungle | `_hazards` |
| **G13** | **the hazard banner shown over the level-complete card** | **SURVIVED**, then `_cards` (new section) |
| G14 | the torch range grows | `_biomes` |
| G15 | decor does not follow a sinking secret door | `_biomes` |
| A1 | local parts queryable | `_biomes` |
| A2 | decor built in Neon | `_biomes` |
| R1 | the Rest prompt stays on in a run | `_rest` |
| **R2** | **the in-lobby guard on the Rest prompt gone** | **SURVIVED**, then `_rest` (new assertion) |
| R3 | the door sign on frame time only | `_rest` §5 (the 6.3 s stall) |
| R4 | moving does not get you up | `_rest` |
| R5 | the campfire burns during a run | `_biomes`, `_rest` |
| K1 | `BreakRoom.validate`: the latency rule off | `BreakRoom.spec` |
| K2 | `Rest.validate`: WakeOnMove may be off | `BreakRoom.spec`, `Rest.spec` |
| CONTROL-1 | the dungeon chain's iron a shade redder | survived |
| CONTROL-2 | the icicle a shade redder | survived |

The survivors were closed in the only honest order a test gap allows: the new assertion was written and
passes on the real build (the behaviour was already right), then was watched failing on its mutant for the
stated reason:

* **G11**: no real maze position wants more than about 10 decor pieces inside the 24-stud radius (the middle
  of L200: 10), so the 26-piece cap never binds in play and nothing noticed a client that ignored it. The
  budget check now forces the cap to 5 in memory (the client reads `Biomes.Budget` live): on the mutant
  `with MaxDecorPieces forced to 5, exactly 5 pieces are shown -> got 10, want 5`.
* **G13**: no check put a hazard's warning under the level-complete card. The cards check now finishes level
  after level until the next one has a hazard whose first warning starts while that card is up (found on the
  first try) and stands beside it; it also asserts the exposure happened and that the banner shows once the
  cards have gone. On the mutant: `the hazard banner never shows while the level-complete card is up -> got
  33, want 0` (frames).
* **R2**: the frame loop also stands a seated player up inside a run, so a missing in-lobby guard on the
  prompt was only a one-frame sit, and the check looked 0.3 s later. It now also looks before any frame: on
  the mutant `triggering it inside a run does not sit you down, not even for a frame -> got true, want false`.

**Round 2** (G11, G13, R2 and both controls, on fresh copies carrying the new assertions): **3 killed,
both controls survived.**

A first launch of round 1 was stopped after 5 mutations: the harness listed the checks to run from the real
tree, and a check written during the sweep (`_shots`) was missing from the copies, which would have counted
as a kill for every later mutation. Each worker now lists its own copy; the sweep was relaunched from
scratch and the aborted results thrown away.

Not mutated here: `EnvBands.luau` and `Rest.luau` are byte-identical to +1 Jump's, whose sweeps covered them
(and their specs came along verbatim); K2 re-checks the one `Rest.validate` rule this game relies on.

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Is it eye candy at all in the dark?** Darkness is locked, so a biome is a hue shift at equal
   brightness plus decor, particles and hazards inside the torch's 28 studs. Does each biome read as a
   different place, or is the grade too subtle to notice? (If too subtle: raise decor density or particle
   rates within the budgets; the luma lock stays.)
2. **Decor under a single torch**: glass crystals and ice at 0.15-0.35 transparency, cobwebs at 0.6, wall-top
   pieces (leaves, snowcaps, columns, spires, cloud puffs) 21-30 studs up — visible from the default camera,
   and do they read as what they are?
3. **Particles**: fireflies, embers, sparkles and stardust use LightEmission 0.8-0.9 in pitch darkness —
   pretty or distracting; do they ever hide a monster (they are 0.12-0.6 studs and see-through)?
4. **The hazard ring vs the lava trap**: the ring is blue now (review fix, §12), so yellow on the floor still
   means only "lethal lava next". Does the blue Neon ring read as a warning in every biome (the ice cellar's
   blue grade most of all), and is it told apart from the cyan and deep-blue secret buttons (3-stud discs,
   not pulsing) and the cyan "Hjelp meg" guide dots?
5. **The hanging object behind a wall**: it hangs 21 studs up in a 24-stud maze; from the camera it can show
   over a wall top that a cell is there. Minor, but look.
6. **The knock on a real humanoid**: does `PlatformStand` + a 5 studs/s push read as being knocked down, and
   does the character stand up cleanly after 0.8 s? The monster interaction in §3.
7. **Readability on a phone**: the banner and title card sit under the level panel (measured headless at
   every viewport, all clear); the ring is 8.4 studs in a 9-stud corridor — readable from the passage?
8. **The campfire corner**: does a `ProximityPrompt` on a client-created part show and fire on the client?
   Does `Humanoid.Sit = true` from the client sit the character without a seat and replicate, and does
   walking stand it up? The depth-of-field look.
9. **The biome board** (BillboardGui on a post): readable size; does it crowd the lobby?
10. **The door sign**: readable from the maze start; does it fade out cleanly at 6 s?
11. **`Workspace.StreamingEnabled` must be OFF in the published place** (the existing minimap already
    assumes it). The biome client reads walls and traps from the replicated maze; with streaming on, decor
    and hazard cells could differ between clients and a hazard could land on a trap the client has not
    streamed yet. Nothing in the Rojo project sets it; read it in Studio.
12. **Frame time on a low phone** in a 30×30 maze with the full decor set and a hazard.
13. **Other players' view** of a knock (local hazard, visible fall) in a Group run.
14. **The torch perk**: its longer range is untouched by the biomes; does the recoloured torch still look right
    at the longer range?
15. **"Sky Ruins" inside a black-fog maze**: does night-sky blue with columns and cloud puffs read as ruins
    in the sky, or just as "blue"?

---

## 9. Thumbnail shot list (for the night Studio session)

*Not tried in Studio yet.* The two snippets below were run headless against the real server and clients
(`check_labyrintspill_shots`, 54 / 0) on every shot level; step 1-4 are plain Studio.

**Why there are no coordinates here:** the emulator's `Random` is not Roblox's, so no maze position measured
headless is valid in Studio. The helper reads the live maze instead.

1. **Build a place that has the biomes.** In `labyrint-spill/`, `rojo build -o Labyrint-shots.rbxlx` and open
   that file (`*.rbxlx` is git-ignored). Do not use `Labyrint.rbxlx`: it was built on 17.09, before the
   biomes, and its `.lock` says a Studio session had it open. Keep Rojo disconnected.
2. **Three edits in that place only, never in `src/`** (nothing is published from Studio;
   `publish_live.bat` builds from `src/`).
   > ⛔ **NEVER publish or save this place to Roblox.** Not *File → Publish to Roblox*, not *Save to Roblox*,
   > not "Publish" when Studio asks on close (choose *Don't Save*). With these edits it saves nothing, lets
   > every new player start any level up to 481, and has no monsters: published over place
   > 121268951050692 it would replace the live game with that. Close it when the shots are done and delete
   > `Labyrint-shots.rbxlx`. The live game is only ever published by `publish_live.bat`, from `src/`.

   In `ServerScriptService.MazeGame`:
   * `SaveData = true` → `SaveData = false` (no DataStore is touched: no saves, no records, no leaderboard);
   * in `loadPlayer`, `accepted = 0,` → `accepted = 480,` (so every level up to 481 can be started);
   * in `CONFIG.Curve`, `FirstMonsterLevel = 4` → `FirstMonsterLevel = 100000` (no monster kills the avatar
     mid-shot; monsters are drawn LAST from the level's pool, so walls, traps, coins, gems and buttons stay
     exactly the live levels).
   Studio settings: *Rendering → Quality Level 21* (bloom, glass and atmosphere at full quality).
3. **Start a level** (command bar, **Client** context, from the lobby):
   `game.ReplicatedStorage.LobbyRemotes.StartRun:FireServer(38, "solo")`. To leave: walk to the 🚪 Lobby
   door beside the start and use its prompt, or (Client context)
   `game.Players.LocalPlayer.Character.Humanoid.Health = 0` to respawn in the lobby. A new level only starts
   from the lobby.
4. **Wait 6 s** after a level starts (the free-break sign on the Lobby door fades out), and 4 s after a
   level change (the colour grade glides in).
5. **Stand beside the level's falling hazard** (command bar, **Client** context; change only `LEVEL`, and
   `TARGET` to `"trap"` to stand beside the nearest lava trap instead). The avatar lands in the passage beside
   the nearest hazard cell, facing it, where it is never hit; the ring lights within 14 s and the warning
   lasts 3 s, repeating every 14 s, so there is time for several takes:

```lua
local LEVEL, TARGET = 38, "hazard" -- TARGET: "hazard" (the level's falling hazard) or "trap" (a lava trap)
local RS, P = game:GetService("ReplicatedStorage"), game:GetService("Players").LocalPlayer
local B, CH, E = require(RS.Biomes), require(RS.CellHazards), require(RS.EnvBands)
assert(TARGET == "trap" or B.hazardKindAt(E, LEVEL), "no falling hazard on this level (the dungeon and the jungle have none)")
local f = workspace:FindFirstChild(P:GetAttribute("MazeFolder") or "")
local fl = f and f:FindFirstChild("Floor")
assert(fl, "start the level first (no maze for this player)")
local S, o = B.Hazards.CellSize, fl.Position
local gC, gR = math.floor(fl.Size.X / S + 0.5), math.floor(fl.Size.Z / S + 0.5)
local function fine(p) return math.floor((p.X - o.X) / S + (gC - 1) / 2 + 0.5), math.floor((p.Z - o.Z) / S + (gR - 1) / 2 + 0.5) end
local function world(x, y) return Vector3.new(o.X + (x - (gC - 1) / 2) * S, o.Y + fl.Size.Y / 2 + 3, o.Z + (y - (gR - 1) / 2) * S) end
local walls, traps = {}, {}
for _, d in f:GetChildren() do
	if d.Name == "Wall" or d.Name == "SecretWall" then local x, y = fine(d.Position); walls[x .. "," .. y] = true end
	if d.Name == "Trap" then local x, y = fine(d.Position); traps[((x - 1) // 2) .. "," .. ((y - 1) // 2)] = true end
end
local cells = {}
if TARGET == "trap" then
	for k in traps do local x, y = string.match(k, "(-?%d+),(-?%d+)"); table.insert(cells, { cx = tonumber(x), cy = tonumber(y) }) end
else
	cells = CH.pick(LEVEL, (gC - 1) // 2, (gR - 1) // 2, traps, B.Seed, B.Hazards)
end
local root = P.Character.HumanoidRootPart
local best, bestD
for _, h in cells do
	local d = (world(2 * h.cx + 1, 2 * h.cy + 1) - root.Position).Magnitude
	if bestD == nil or d < bestD then best, bestD = h, d end
end
assert(best, "nothing to stand beside on this maze")
local cx, cy = 2 * best.cx + 1, 2 * best.cy + 1
for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
	if not walls[(cx + d[1]) .. "," .. (cy + d[2])] then
		P.Character:PivotTo(CFrame.lookAt(world(cx + d[1], cy + d[2]), world(cx, cy)))
		print("[shot] beside " .. TARGET .. " cell " .. best.cx .. "," .. best.cy .. (if TARGET == "trap" then " - it pulses every 5.2 s" else " - its ring lights within 14 s"))
		break
	end
end
```

6. **Clean frame** (command bar, **Client** context): hides every ScreenGui, every label in your maze (the
   AlwaysOnTop `🚪 Lobby` and `EXIT` signs) and in the break room, and the core UI. Re-run it after every
   new level (a new level brings new labels):

```lua
local P = game:GetService("Players").LocalPlayer
for _, g in P.PlayerGui:GetChildren() do if g:IsA("ScreenGui") then g.Enabled = false end end
for _, root in { workspace:FindFirstChild(P:GetAttribute("MazeFolder") or ""), workspace:FindFirstChild("LabyrintBreakRoom") } do
	for _, b in root:GetDescendants() do if b:IsA("BillboardGui") then b.Enabled = false end end
end
pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
```

7. **Camera:** Freecam (Shift+P) or the normal camera. **Everything new is built around the avatar, not the
   camera** (decor within 24 studs of it, hazards within 26), and the torch on the avatar is the only key
   light, so keep the camera within about 20 studs of the avatar. No lighting edits for the store: the
   darkness is the game.

**The shots**

1. **"The icicle" — hero shot** (🧊 Ice Cellar, `LEVEL = 38`, helper `"hazard"`). Camera behind and to one
   side of the avatar, about 8 studs back and 6 up, looking past its shoulder into the hazard cell and tilted
   up enough to catch the object overhead. In frame: the avatar with its ice-white torch; the pulsing blue
   ring and the growing shadow on the cell floor; the icicle cluster hanging over it (≈ 21 studs up; it
   shakes, then drops in the last 0.35 s of the 3 s warning); icicle clusters and snowcaps along the wall
   tops; falling snow. Take a burst through the drop; the impact throws ice shards.
2. **"Into the jungle"** (🌿 Jungle Ruins, `L18`, no hazard). Walk two or three cells in from the start,
   away from the Lobby door. Camera low (≈ 2 studs off the floor), 6-8 studs behind the avatar, looking up
   along a corridor. In frame: vines hanging down the walls, leaf clusters over the wall tops against the
   dark, moss and roots low on the walls, fireflies drifting, the green-lit torch pool.
3. **"The forge"** (🔥 Lava Forge, `LEVEL = 76`). Take A: helper `"trap"` — the avatar at the edge of a lava
   trap; shoot on the orange DEADLY phase (2.2 s of every 5.2 s) with embers rising and rusted pipes, grates
   and soot on the walls. Take B: helper `"hazard"` — the lava bomb (basalt ball, molten core) hanging over its
   blue ring. The best frame has both a trap and a ring; wander a few cells after the helper to find one.
4. **"Crystal caverns"** (✨ `LEVEL = 131`, helper `"hazard"`). Camera 10-12 studs back, level with the wall
   tops, looking down the corridor. In frame: glass crystal clusters and spires on the walls catching the
   torch, violet grade, sparkles, the crystal shard hanging over its ring.
5. **"The crypt"** (💀 `LEVEL = 201`, helper `"hazard"`). Camera low beside the avatar, looking up at the
   chandelier (iron hoop, four candles, a ring of flame) hanging over its ring; skulls on stone ledges,
   cobwebs, candles and bones on the walls, mist.
6. **"Among the stars"** (🌌 Astral Labyrinth, `LEVEL = 401`, helper `"hazard"`). Camera above and behind,
   ≈ 12 studs up, pitched down so a corridor runs away from the avatar. In frame: floating rock chips and
   glassy star bits along the walls, violet runes, glowing stardust, the meteor's violet glow over its ring.

**Optional variants:** ☁️ Sky Ruins (`LEVEL = 296`): the lightning bolt exists only for the strike and the
first 0.3 s after it, so take a fast burst at the impact; marble columns and cloud puffs line the wall tops.
☕ **The break room** (lobby, no level): the campfire corner at (24, 0, -4) with its benches and the biome
board beside it; sit by the fire (`Rest by the fire`) for the soft-focus rest look. With `accepted = 480`
the board shows every biome ticked.

---

## 10. Not done / open

* **The adversarial review is done and its six findings are closed (§12).** The fixes themselves have not had
  a second independent pass: they are small and each is held by a failing-first test and a mutation sweep with
  controls, but the captain-mode rule (a reviewer before anything ships) applies to them too.
* **Owner decisions, not taken for him:**
  * **A guide bought, then a walk-out** (§4, §12 finding 1). Today the server tears a bought "Hjelp meg" guide
    down with the run, no refund; the fix only stops the sign from promising otherwise. Keeping the guide for
    the next attempt on the same level would be kinder to a stuck child, but it is a server change to the
    Assist economy (and needs its own exploit review: a guide must not be banked for a later level).
  * **The ring's colour** (§3, §12 finding 4) changed from the trap's yellow to blue on the reviewer's
    reasoning and the server's own palette rule; Studio decides whether this blue reads well in every biome.
  * **Themed trap skins** (in the original theme direction) were deliberately **not** built. The trap's plate
    and its yellow/orange phases are the survival signal and live on the server; a client skin around the
    plate would either make traps easier to spot in the dark (a difficulty change) or muddy the signal. If
    Gustav wants them, the safe version is a non-glowing rim outside the 7-stud plate, checked against the
    signal rule.
  * **How far the later biomes are.** The first three arrive at 5, 13 and 41 minutes; Crystal at ~2.4 h,
    Crypt ~6 h, Sky Ruins ~17 h, Astral ~39 h of play in the model (no deaths). That makes the last two the
    long-term brag, like +1 Jump's galaxy. The knob is `from` in `Biomes.Bands`.
  * **The knock with a monster behind** (§3): keep it (the brief says hazards knock you down), or make it a
    stagger without `PlatformStand`.
* Not committed, not pushed, not published. Studio not opened.
* §8 in full.

---

## 11. Resume session (this file's first version)

The earlier session was cut off after its last gate log and a final client edit, before writing this file.
What the resume found, in the order it found it:

1. **The last edit was never built or gated.** The previous session's final change to `Biome.client.luau`
   (write the grade again on the frame after a payload, because `LightingClient` re-applies the plain maze
   preset on that same payload) landed 35 s after its last gate run, and `build/labyrint-spill.luau` did not
   contain it. Rebuilt; the only difference in the bundle was that edit; every gate green on the rebuilt one.
2. **A latent defect: `signRun` in `RestClient` was a global.** `onPayload` assigned `signRun` before its
   `local` declaration further down, so it wrote a global while the frame loop read the local. Harmless
   today (the sign is never re-placed after it fades within a run), but a write to a global in a shipped
   script. The local now sits before `onPayload`; the lint above finds the pattern in a copy with it put back.
3. **A real defect: a god-mode flyer was knocked out of the air.** The hit test was horizontal only, so an
   icicle falling to the floor knocked a player flying 40 studs above it. Failing tests first
   (`CellHazards.spec` 5 failures; `check_labyrintspill_hazards` §8 on the old bundle: "a god-mode flyer 40
   studs over the ring is not knocked out of the air → got true"), then `MaxHitHeight = 20` in the config and
   the rule, with `validate` refusing anything under 12 (a jump must never dodge). A player at the top of a
   jump in the ring is still knocked, asserted through the client.
4. **Two assertions that never proved their rule:**
   * the Biomes spec's "a grade that turns the yellow warning orange is rejected" used a tint that the luma
     and mildness rules reject first, so the trap-signal clause of `validate` was untested. Added a mild,
     luma-true green-cyan grade that only the signal rule rejects (its preconditions asserted);
   * nothing kept the decor radius inside the torch: `validate` now refuses `DecorRadius > TorchRange - 4`,
     and the spec checks both the value and the refusal.
5. **New gates:** `check_labyrintspill_compile` (no compile binary on this machine) and
   `check_labyrintspill_shots` (the shot list's snippets, run through the real clients on every shot level).
6. **Three promises no test held**, found by the mutation sweep and closed (§7): the decor cap (G11), the hazard
   banner waiting for the level-complete card (G13) and the in-lobby guard on the Rest prompt (R2).
7. **The pacing comment in `Biomes.luau`** quoted round numbers ("26 ~15 min"); it now quotes what
   `Pacing.spec` prints (12.7 min).

Files written in the resume session: `labyrint-spill/src/shared/CellHazards.luau`, `Biomes.luau`,
`src/client/RestClient.client.luau`, `tests/CellHazards.spec.luau`, `tests/Biomes.spec.luau`, `EYECANDY.md`,
`CLAUDE.md` (a section pointing here) and `README.md` (one line); in robloxemu,
`check_labyrintspill_hazards.luau` (§8), `_cards.luau`, `_budget.luau`, `_rest.luau` (the survivors' sections),
`check_labyrintspill_compile.luau` and `check_labyrintspill_shots.luau` (new), and the rebuilt
`build/labyrint-spill.luau`. Scratch work (sweep harness, logs, lint, baseline copy) is in
`scratchpad/lab_resume`.

---

## 12. Adversarial review and its fixes (24.09.2026)

An independent reviewer, read-only and in its own scratch copies, re-ran every gate (the same counts as §7's
"resume" column) and reported six findings. The fix session was the only writer in `labyrint-spill`. Each
finding was **reproduced first** (on the unchanged tree, with a measurement), then closed test-first: the new
assertion was run against the unfixed build and watched failing for the stated reason, then the game (not the
test) was changed. `src/server` is still untouched.

| # | sev. | finding | reproduced (measured on the unchanged tree) | fix | failed first |
|---|---|---|---|---|---|
| 1 | medium | The door sign says "Walk out now, it's free, nothing is lost", but a "Hjelp meg" guide bought in those seconds is lost with no refund. | The reviewer's probe, re-run: three counted walk-outs at L42, the guide offered, bought 0.5 s into the run for 250 coins; at 1.5 s the sign is up and the guide active; after the walk-out `fails` is still 3, coins 4 900, and the next attempt has no guide. | `BreakRoom.freeBreak/signAlpha(elapsed, cfg, run)`: not free while `run.guideActive`. `RestClient` listens (read only) to the server's `AssistRemotes.AssistState`, takes the sign down at once when a guide is active, and never puts it up then. The server's rule is unchanged (owner decision, §10). | `BreakRoom.spec` 4 failures ("with a paid guide active, walking out is not free -> got true"); `check_labyrintspill_rest` §7 2 failures ("the sign is gone at once -> got BreakSign"). |
| 2 | medium | When a secret door sinks, crystal spires and marble columns on it are left sticking out of the floor. | The reviewer's probe, re-run: **21** decor parts above the floor over sunk doors in 10 of 16 levels; spire tops 3.00 studs and column tops 2.50 studs over the floor. Cause: the door sinks 26 studs, a spire reaches 29 over the wall's bottom, and the sunk door stayed dressed. | `Biomes.wallState` ("standing" / "sinking" / "gone", from the wall's position only) and `Biomes.decorAlpha` (fade in, and out over `DecorFadeSeconds` = 0.35 once sinking). The client dresses only standing walls, fades a sinking wall's pieces as they ride down, and releases them once faded, or at once when the door is under the floor. | `Biomes.spec` (the rule did not exist); the new sink section of `check_labyrintspill_biomes` on the old client: 13 failures, worst 4.47 / 3.00 studs (spire, L105) and 3.97 / 2.50 (column, L296). |
| 3 | low | Two knock rules no suite held (M1: a knock kept after leaving the maze; M4: a knock keeps upward speed); the real client's trap exclusion held only by one shot-list level (M2, M3). | My own sweep of the reviewer's four mutants on the unchanged tree: M1 **survived**, M4 **survived**, M2 and M3 killed only by `check_labyrintspill_shots` (L76), the control survived. | Test gaps (the behaviour was right): `check_labyrintspill_hazards` §9 (leave the maze while knocked: up at once, and still up in the lobby), §10 (knocked while rising at 25 studs/s: vertical speed ≤ 0), §11 (two levels where the trap exclusion matters, L68 and L76: a ring at every hazard cell of the pure rule, none on any trap cell over a whole cycle). | Watched failing on each mutant (sweep below): M1 "§9 leaving the maze while knocked down gets you up -> got true"; M4 "vy 25.0"; M2 and M3 "2 missed" and "a ring on a trap cell -> got 261". |
| 4 | low | The hazard ring reused the trap's exact warning colour, so floor yellow no longer meant only "lethal lava next". | Through the real client: the ring is (255, 205, 60) Neon, the server's `TRAP_LOOK.warn`. The server's own palette already refused that yellow for the secret doors for the same reason (the `PAIR_COLORS` comment). | `Biomes.Hazards.RingColor` = (100, 160, 255) blue, `RingWord` "blue"; `Biomes.validate` refuses a ring that is not cool under every grade (blue/red ≥ 1.5, and ≥ 1.0 above either trap phase); `BiomeArt.buildHazardView` takes the colour; the banner and card texts come from `Biomes.hazardBanner/hazardIntro` ("step out of the blue ring"), which the layout and cards checks now measure instead of their own copies. | `check_labyrintspill_hazards` §1: 4 failures ("the real client draws the ring in RingColor -> got 255,205,60"); `Biomes.spec` (no RingColor). |
| 5 | low | The reported budget peak is too low: every cell gives 49 local parts, not 41. | The reviewer's probe, re-run: **49** local parts at L25 (48 decor). | `check_labyrintspill_budget` now visits every open cell of each biome's biggest maze (8 levels, 7 106 cells) and prints the peak the docs quote: 49 at L25. It also builds the largest hazard view with the real `BiomeArt` and asserts the structural bound, 26 × 4 + 2 × 9 + 1 = 123 ≤ 140. §6 corrected. | A measurement, not a behaviour: no game code changed. The bound assertion is proven to bite by F5 below (179 > 140). |
| 6 | low | The thumbnail place is a full copy of the game with saves off, `accepted = 480` and no monsters, and nothing says "never publish it". | §9 said only "nothing is published from Studio". | A ⛔ box in §9 step 2 (never *Publish to Roblox*, *Save to Roblox*, or "Publish" on close; delete the file afterwards), and a line in `CLAUDE.md`. | None possible: the luau CLI has no file IO, so no gate can read this file. |

**Mutation sweep** (`scratchpad/lab_fix/sweep.py` + `mut_fix.py`, log `sweep_fix_r1.log`, results
`sweep_fix_r1.json`). Six workers, each on a scratch copy verified byte-identical to the real tree. For every
mutation: exactly one occurrence in its file and in the baseline bundle; the rebuilt bundle proved equal to the
baseline with that single replacement; all 28 suites run; the original bytes restored and md5-checked. Every
worker's copy was byte-identical to the real tree at the end. **16 mutations: 16 killed, all reached the
bundle. 3 controls: 3 survived.**

| id | mutation | killed by |
|---|---|---|
| F1a | `RestClient` never hears that a guide is active | `_rest` §7 |
| F1b | `BreakRoom.freeBreak` ignores the guide | `BreakRoom.spec` |
| F2a | a sinking or sunk door's faces are selected again (released the same frame, but they take decor slots) | `_biomes` (with the cap forced to 2 beside a sunk door: 1 piece shown, want 2) |
| F2b | a door already under the floor keeps its dressing until faded | `_biomes` (button motion: 22 part-frames, 3.00 studs) |
| F2c | no fade while sinking (the dressing pops out at the floor) | `_biomes` ("half-way down, none of it is still at full opacity -> got 18") |
| F2d | `decorAlpha` never fades out | `Biomes.spec`, `_biomes` |
| F2e | "gone" only 3 studs under the floor | `Biomes.spec`, `_biomes` |
| M1 | `leaveMaze` no longer releases a knock | `_hazards` §9 |
| M2 | the client ignores the real trap cells | `_hazards` §11, `_shots` |
| M3 | the trap-cell mapping one cell off | `_hazards` §11, `_shots` |
| M4 | a knock keeps upward speed | `_hazards` §10 |
| F4a | the client draws the ring in the trap's yellow | `_hazards` §1 |
| F4b | `validate`'s ring-colour rule off | `Biomes.spec` |
| F4c | the banner calls the ring yellow | `Biomes.spec` |
| F4d | the ring configured in the trap's yellow | `Biomes.spec`; `validate` then turns the biome layer off, so 6 checks too |
| F5 | a decor cap (40) whose worst case exceeds the part budget | `_budget` (structural bound 179 > 140) |
| CONTROL | moss 1/255 redder | survived |
| CONTROL | the ring a shade greener (100, 161, 255): still blue, still far from the traps | survived |
| CONTROL | `DecorFadeSeconds` 0.34: still inside every rule | survived |

**Why the sink fix has three states, not two.** This emulator's `Tween` does not interpolate
(`emu/services.luau`: it jumps to the goal after `TweenInfo.Time`), so the first version of the fix (fade out
once the door starts moving) still failed: the client first saw the door when it was already down. A Roblox
client can see the same thing after a hitch or when it arrives late, so "gone" (the door's top at or under the
floor) now releases at once. The sink section runs two motions per level: the real button (the emulator's
jump) and the door moved frame by frame the way Roblox's TweenService interpolates the server's tween (Quad
Out over 0.7 s, parsed from the server source). The fade (0.35 s plus two frames) ends before a Quad-Out
door's top reaches the floor (0.51 s); the spec and the check both hold that.

**Gates** (§7, "review fix" column): specs **2 095 / 0** (14 files), headless checks **959 / 0 + 2 PASS**
(14 files), on bundle md5 `5d8c2b9b9c7cc2fcc3153cb7ddac9c7a`; the final run and two more gave identical
summaries. A lint for writes to undeclared globals is clean on every `src/shared` and `src/client` file.

**Files written in the fix session:** `labyrint-spill/src/shared/BreakRoom.luau`, `Biomes.luau`,
`BiomeArt.luau`, `src/client/RestClient.client.luau`, `Biome.client.luau`, `tests/BreakRoom.spec.luau`,
`tests/Biomes.spec.luau`, `EYECANDY.md`, `CLAUDE.md`, `README.md`; in robloxemu,
`check_labyrintspill_rest.luau` (§7), `_biomes.luau` (the sink section), `_hazards.luau` (§1 ring colour,
§9-§11), `_budget.luau` (every-cell sweep, bound), `_cards.luau` and `_layout.luau` (texts from the shared
helpers), and the rebuilt `build/labyrint-spill.luau`. Scratch: `scratchpad/lab_fix` (mirrors, sweep harness,
logs). Not committed, not pushed, not published, Studio not opened.
