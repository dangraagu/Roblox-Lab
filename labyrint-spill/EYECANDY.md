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
controls, adversarially reviewed twice, and every finding of both reviews closed (§12, §13). Every open owner
decision is taken (§10, §13). NOT seen in Studio.** The eye-candy work is committed (`a983d11`); the 30.09 pass
is not committed, pushed or published. The server script changed in the 30.09 pass for the first time in this
work: two small rules (a Friends host can rejoin their own run; a bought guide is kept until its level is cleared).

**Pass 2, 01.10 (§15): complete against `docs/complete-game-standard.md`.** Pass 2's cut-off work is finished and
documented: a public + friends highscore board by the spawn (ties to whoever got there first), a session lock with an
owner token on every save, a walk guard on the exit, critters in every biome, `RespawnLocation`, a headless walk of the
whole player path, HUD rule 4b asserted. New in the resume: one falling hazard at a time is enforced in code, the board
says so when its store is down (and retries a lost write), the README has the store text (984 characters), MARKETING.md
a 9-clip list, the Studio and thumbnail lists are current, and `tests/docs_check.py` holds all four documents to the
game. Pass 2's assertions had never been mutation-tested; they are now (§15). Every gate green. Not committed, not
published, not seen in Studio.

**Pass 1 re-run, 01.10 (§14):** the five second-review findings were measured again on the current tree, which also
holds pass 2's uncommitted, undocumented work from 01.10 00:09-00:50 (critters, a highscore board, save locks, new
checks; cut off before its docs). Four findings do not reproduce. Finding 4 came back in a new form: the new critters
could make their home in the start cell, and a crypt spider climbed straight through the Lobby door and the
free-break sign (37 of 481 levels). Closed test-first: the start cell is no critter's home. The 30.09 pass's 47
mutations were re-run on the current tree with the new ones (§14). No owner decision is open.

**Second review + owner decisions, 30.09 (§13):** a Friends host who walks out under the free-break sign can get
back to their friends; the ring can no longer be retuned into a colour the maze asks you to step on (a CIE delta E
floor against the buttons, the guide dots, coins, gems and the exit, through every biome grade); the biome card
waits for the daily-reward popup too; no decor on the Lobby door's wall face; the part, emitter and light budgets are
enforced by `Biomes.validate`, not only measured. Owner decisions: a bought "Hjelp meg" guide is **kept** until its
level is cleared; a hazard hit is a **stagger**, never a knock-down, when a monster is close enough to catch you;
the ring stays blue; no themed trap skins; the later biomes stay where they are, now held by a pacing assertion.

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
| `src/server/*` | **nothing** in the eye-candy work. 30.09 (§13): a Friends host may rejoin their own run (`findFriendsInstance`), and a bought guide is kept until its level is cleared (`applyKeptGuide`, saved as `guideLevel`). 01.10 (§15): the highscore board, the session lock and owner token, the walk guard, `RespawnLocation`. |
| `src/shared/Board.luau`, `BoardConfig.luau`, `src/client/BoardClient.client.luau` | (01.10, §15) the highscore board: +1 Jump's template, this game's settings, the board drawn per player. |
| `tests/Board.spec.luau`, `tests/docs_check.py` | (01.10, §15) the board's pure rules; the four ship-and-market documents held to the game (Python: the luau CLI cannot read a file). |
| `robloxemu/check_labyrintspill_*` (01.10) | `board`, `boarddown`, `critters`, `journey`, `overlap`, `save` (§15). |

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
  `Biomes.hazardBanner/hazardIntro`, which the layout check measures. **Never a "step here" colour either (second
  review, §13):** on this floor a glowing blue disc is a secret button and the guide's cyan dots say "walk here".
  `validate` keeps the ring at least CIE76 delta E 25 from every colour the maze asks you to step on or walk to
  (`Biomes.StepOnColors`: the four button colours, the guide dots, coin, gem, exit pad, which
  `check_labyrintspill_biomes` §0 reads back out of the server script), through every biome grade. The shipped ring
  keeps 31.8 from its nearest, the deep-blue button; the cyan button and the guide dots, which players already
  tell apart, are 11.0 apart. A readable blue cannot get much further: the brightest blues sit between the
  deep-blue button, the cyan button and the gem.
* **The hit rule:** at the impact instant, your root within 4.2 studs horizontally of the cell centre
  (strike radius 3.2 + player radius 1.0) **and at most 20 studs above the floor** (resume session: a jump
  never dodges, but a god-mode flyer over the maze is not knocked out of the air). The zone is 8.4 studs
  across inside a 9-stud cell, so **the passage next to a hazard cell is always safe**: a hazard can make
  you wait, never wall a level off. Debris is harmless; standing in the ring during the warning is harmless.
* **A hit** knocks you down for 0.8 s (`PlatformStand`) with a 5 studs/s horizontal push away from the
  impact (4 studs at most), never upward; camera shake and a white flash. `validate` proves the farthest
  knock cannot carry you onto the neighbouring cell's trap (8.2 studs from the hazard centre at most; the
  next trap's edge, player radius included, is 13.5 away). Nothing is taken: no death, no coins, no time
  penalty beyond the 0.8 s.
* **Never with a monster close (owner decision, 30.09, §13).** A knock-down with a monster on your heels could let
  it catch you, and the owner's standard is "a hit costs a little, never a run". So when a monster is within
  `MonsterSafeRadius` (24 studs, horizontal) at the impact, the hit is a **stagger**: the same shake, flash and
  shove, and you keep your feet (no `PlatformStand`). `CellHazards.validate` refuses a radius under the worst case:
  the fastest monster (the server's `MonsterSpeedMax` 15, parsed back out of the server) closing for the whole
  0.8 s, the 5 studs/s shove toward it, and a 4-stud reach: (15 + 5) × 0.8 + 4 = 20 studs. The client reads the
  server's replicated `Monster` models in the player's own maze, only at the instant of a hit.

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
  **Not while a guide is active (review fix, §12):** a "Hjelp meg" guide used to be bought for ONE run and a
  walk-out lost it with no refund. While the server's `AssistState` says a guide is active, the sign is not
  shown (`BreakRoom.freeBreak(elapsed, cfg, run)` returns false), and it goes at once if the guide is bought while
  it is up. **Since 30.09 (owner decision, §13) the buyer keeps the guide** until its level is cleared: dying or
  walking out no longer loses it, and the next attempt at that level starts with it, free. The sign still stays
  down while a guide is active: a guided run is no plain fresh start, and in a shared run the guide may be
  someone else's. Proven end to end: three counted walk-outs at L42, the guide offered and bought 0.5 s into the
  run, the sign gone on the next frame and staying gone; after the walk-out the next attempt at L42 has the guide
  again at no cost (and no sign), and L41 has neither.
  **In a shared run too (second review, §13):** the server lets you into a Friends run only if you are a friend
  of its host, and Roblox never counts you as your own friend, so a HOST who walked out could not get back (the
  Friends door opened a picker to host a new run and left the friends alone). The Friends door and the picker's
  own route now put a host back into their own run first; strangers still get a picker. A Group player who walks
  out is matched back into the same run by the Group door (asserted as well).
* Inside a run, rest does not exist: the prompt is off, and `BreakRoom.mayRest` fails closed if it fires
  anyway.
* Roblox's own ~20-minute idle disconnect still applies in the lobby; nothing is lost by it (progress is
  saved by the server as before).

**Why it cannot be exploited**

1. **Nothing is paused.** Leaving a run ends it: its clock is thrown away, no time is recorded, the next
   attempt starts a fresh clock with the same maze (levels are deterministic). No clock is ever frozen.
2. **The only promise the sign makes is the server's own**, and it expires before the server's rule does.
   Walking out after the sign is gone costs exactly what it always cost (one counted attempt, which only
   ever moves the "Hjelp meg" offer closer). It never shows while a guide is active (and since 30.09 a buyer's
   guide is kept through a walk-out anyway, §13), and a Friends host who walks out can get back in (§13).
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
| runs, run clock, medals, records, `accepted`, traps, monsters, the Assist counter, saves | **server** | authoritative, as before; changed only by two 30.09 rules (§13): a Friends host may rejoin their own run, and a bought guide is kept (saved as `guideLevel`) until its level is cleared |

**Leak review.** The clients read: the `LevelInfo` payload (level, the player's own `accepted`), the
player's own maze folder (walls and secret doors *into one table without their names*, trap parts, the
floor, the Lobby door), the player's own character and `Lighting`; and (review fix) the player's own
`AssistState`, which the server already sends to that player alone, for the door sign; and (owner decision 30.09)
the positions of the `Monster` models in the player's own maze, which the server replicates to everyone in it,
only at the instant of a hazard hit (stagger or knock-down). Decor never depends on
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
**Enforced in code since 30.09 (second review, §13):** `Biomes.validate` refuses any budget whose worst case,
`Biomes.partBound()` = MaxDecorPieces × MaxPrimsPerPiece + MaxHazardsShown × MaxHazardViewParts + 1, exceeds
`MaxLocalParts` (a decor cap of 40 is refused: 179 parts), any budget where two air kinds plus one burst per
hazard view exceed `MaxEmitters`, and any maze light at all; and the client turns the whole biome layer off rather
than run such a config. `MaxHazardViewParts` (9) is held to the real `BiomeArt` views by `check_labyrintspill_budget`.
The campfire's light exists only while `MaxLobbyLights` ≥ 1.

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

(01.10: the pass-1 re-run's counts, with pass 2's new gates, are in §14; the final counts after pass 2 are in §15.)

"Before" is the committed game (`git archive HEAD`, rebuilt and run in a scratch copy). "Previous session"
is the last gate log the cut-off session wrote (`scratchpad/labyrint_eyecandy/gates_after1.txt`); its last
source edit came 35 s after that run and was never built or gated (§11). "Resume" is that session's final
run on its final tree. "Review fix" is the final run after the adversarial review's findings were closed (§12),
on bundle md5 `5d8c2b9b9c7cc2fcc3153cb7ddac9c7a`. "Second review + decisions" is the final run of the 30.09 pass (§13),
on bundle md5 `0c9940195b2afcd4a1c9de8180fc4ed8`; a second full run gave identical summaries.

| gate | before | previous session | **resume (final)** | **review fix (final)** | **second review + decisions (30.09)** |
|---|---|---|---|---|---|
| `tests/Assist.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 | **78 / 0** |
| `tests/Contributors.spec` | 18 / 0 | 18 / 0 | 18 / 0 | 18 / 0 | 18 / 0 |
| `tests/Hazard.spec` (the lava pulse) | 36 / 0 | 36 / 0 | 36 / 0 | 36 / 0 | 36 / 0 |
| `tests/Progression.spec` | 33 / 0 | 33 / 0 | 33 / 0 | 33 / 0 | 33 / 0 |
| `tests/lightingpresets.spec` | 41 / 0 | 41 / 0 | 41 / 0 | 41 / 0 | 41 / 0 |
| `tests/mazeref.spec` | 27 / 0 | 27 / 0 | 27 / 0 | 27 / 0 | 27 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/touchtarget.spec` | 52 / 0 | 52 / 0 | 52 / 0 | 52 / 0 | 52 / 0 |
| `tests/Biomes.spec` | — | 1 115 / 0 | **1 121 / 0** | **1 183 / 0** | **1 216 / 0** |
| `tests/CellHazards.spec` | — | 66 / 0 | **73 / 0** | 73 / 0 | **83 / 0** |
| `tests/BreakRoom.spec` | — | 28 / 0 | 28 / 0 | **35 / 0** | 35 / 0 |
| `tests/EnvBands.spec` (template) | — | 124 / 0 | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/Rest.spec` (template) | — | 55 / 0 | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Pacing.spec` | — | 278 / 0 | 278 / 0 | 278 / 0 | **280 / 0** |
| **spec total** | **347 / 0** | **2 013 / 0** | **2 026 / 0** | **2 095 / 0** | **2 148 / 0** |
| `robloxemu/check_labyrint` (HUD fit, 11 clients) | PASS | PASS | PASS | PASS | PASS |
| `robloxemu/check_labyrint_spawn` | 34 / 0 | 34 / 0 | 34 / 0 | 34 / 0 | 34 / 0 |
| `robloxemu/check_lighting` | 19 / 0 | 19 / 0 | 19 / 0 | 19 / 0 | 19 / 0 |
| `robloxemu/check_secretdoors` | 50 / 0 | 50 / 0 | 50 / 0 | 50 / 0 | 50 / 0 |
| `robloxemu/check_themes` | 23 / 0 | 23 / 0 | 23 / 0 | 23 / 0 | 23 / 0 |
| `robloxemu/check_labyrintspill_hud` (HUD fit, all 13 clients) | — | PASS | PASS | PASS | PASS |
| `robloxemu/check_labyrintspill_biomes` | — | 259 / 0 | 259 / 0 | **291 / 0** | **324 / 0** |
| `robloxemu/check_labyrintspill_hazards` | — | 48 / 0 | **50 / 0** | **66 / 0** | **72 / 0** |
| `robloxemu/check_labyrintspill_rest` | — | 53 / 0 | **55 / 0** | **67 / 0** | **69 / 0** |
| `robloxemu/check_labyrintspill_cards` | — | 14 / 0 | **17 / 0** | 17 / 0 | 17 / 0 |
| `robloxemu/check_labyrintspill_budget` | — | 12 / 0 | **15 / 0** | **26 / 0** | **28 / 0** |
| `robloxemu/check_labyrintspill_layout` | — | 266 / 0 | 266 / 0 | 266 / 0 | 266 / 0 |
| `robloxemu/check_labyrintspill_compile` | — | — | **46 / 0** (new) | 46 / 0 | 46 / 0 |
| `robloxemu/check_labyrintspill_shots` | — | — | **54 / 0** (new) | 54 / 0 | 54 / 0 |
| `robloxemu/check_labyrintspill_friends` | — | — | — | — | **26 / 0** (new) |
| `robloxemu/check_labyrintspill_guide` | — | — | — | — | **30 / 0** (new) |
| `robloxemu/check_labyrintspill_popups` | — | — | — | — | **9 / 0** (new) |
| **headless check total** | **126 / 0 + PASS** | **778 / 0 + 2 PASS** | **888 / 0 + 2 PASS** | **959 / 0 + 2 PASS** | **1 067 / 0 + 2 PASS** |

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
16. **(30.09) The stagger**: a hit with a monster within 24 studs keeps you on your feet (shake, flash, a 5 studs/s
    shove that the humanoid's own control may cancel at once). Does it still read as being hit? Is 24 studs the
    right distance in a real chase (monsters path around walls; the radius is straight-line)?
17. **(30.09) A Friends run with two real accounts**: the host walks out under the sign and takes the Friends door
    back. The server no longer depends on what `IsFriendsWith(own id)` returns, but the whole flow has only been
    seen headless with a modelled friendship.
18. **(30.09) The kept guide's lobby card** ("💡 Guide kept ... It lights up again when you go back in") on a phone,
    and the guide lighting up at once when the player walks back into that level.
19. **(01.10, pass 2) The TopBoard at the spawn.** Its SurfaceGui (560 x 400 px at 40 px a stud, LightInfluence 0) seen
    from the pad 15 studs away and on a phone: readable? Does the prompt show at 10 studs, does E or a tap toggle PUBLIC
    and FRIENDS, and does the board crowd the doors or the Content Contributors pole?
20. **A real OrderedDataStore and real friends.** `GetSortedAsync`, `GetFriendsAsync` (paged, capped at 200) and
    `GetNameFromUserIdAsync` have only run headless (the emulator has no `GetFriendsAsync`; the checks supply one). With
    API access on in the published place: the public top 10 with real names, and one real account's Friends view
    (look, never film it). With API access off: "Couldn't load the board right now. It will try again in a minute."
    when the store's calls fail, or "No one on the board yet..." when the store cannot be opened at all: which one
    Studio does is for Studio to show.
21. **The critters** (pass 2: rats, butterflies, bats, salamanders, beetles, spiders, swallows, star jellies; 2-3 per
    band, sharing the decor slots). Under one torch, do they read as living things, do the motions (scurry, climb,
    flutter, glide, float) look natural, and is any of them ever mistaken for a monster at a glance?
22. **The session lock with two real servers.** Join server A, then server B with the same account: B must say "Your
    progress is open in another server right now, so this session will not be saved." Leave A, rejoin: progress is
    there. And Studio with API access off: the "could not be loaded" banner, read on a phone. (`check_labyrintspill_save`
    models both; real DataStore timing and `game.JobId` only exist on Roblox.)
23. **The walk guard on a real fast player.** With the speed perk and corner cutting, a clean run must never get "Too
    fast: nobody can run this maze in ..." (the floor is `Progression.minClearSeconds` at 0.85 slack; the model's fast
    player needs at least twice the floor, `Progression.spec`). Try the fastest real runs of the smallest levels.
24. **The records panel over a bought minimap on a tablet** (pass 2 fix in `LeaderboardClient`, measured headless at
    1024 x 768 only): the panel must move aside when the minimap is shown.

---

## 9. Thumbnail shot list (for the night Studio session)

*Not tried in Studio yet.* The two snippets below were run headless against the real server and clients
(`check_labyrintspill_shots`, 54 / 0) on every shot level; step 1-4 are plain Studio.

**Every thumbnail is 1920x1080** (16:9, what the experience page shows): size the Studio viewport to 16:9 before
shooting (or crop to it) and export at 1920x1080. The short vertical clips (1080x1920) are a separate list, in
`MARKETING.md` ("Clip list"), and use the same place and helpers.

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
🏆 **The TOP MAZE RUNNERS board** (lobby, pass 2): it stands at (-15, 5, 2), facing the spawn pad, with a gold trim.
Camera from the pad, 12-15 studs out, the board and the three doors behind in frame. In the shots place
(`SaveData = false`, so no board store) it says "No one on the board yet. Clear level 1 and be the first!"; for a
fuller board, shoot the published place's Studio session with API access on (the public view only: real usernames).

---

## 10. Not done / open

* **The adversarial review is done and its six findings are closed (§12).** The fixes themselves have not had
  a second independent pass: they are small and each is held by a failing-first test and a mutation sweep with
  controls, but the captain-mode rule (a reviewer before anything ships) applies to them too.
* **Owner decisions.** The owner decided on 2026-09-30: "take the recommended option for all". Where no option
  was marked as recommended, the one that best serves the brief (fair, fun, never punishing, never exploitable)
  was taken, and the reason is given. Details, tests and mutants in §13.
  * **A guide bought, then a walk-out** (§4, §12 finding 1). **DECIDED 2026-09-30 (owner: take recommended):
    the guide is KEPT** until its level is cleared: dying or walking out no longer loses it, the next attempt at
    that level starts with it at no cost, and it is saved with the player's data. No option was marked; this is
    the one the text called kinder to a stuck child, and "never punishing" decides it. Its exploit review (§13):
    it lights only on the level it was bought for (never banked for a harder one), cannot be bought twice, is
    used up by a clear, and a guided run still gives no time record.
  * **The ring's colour** (§3, §12 finding 4). **DECIDED 2026-09-30 (owner: take recommended): blue stays**, as
    built on the reviewer's reasoning and the server's own palette rule, now also held at least delta E 25 from
    every colour the maze asks you to step on (second review, §13). Studio still judges how it reads (§8, 4).
  * **Themed trap skins.** **DECIDED 2026-09-30 (owner: take recommended): not built.** The text recommended
    against them: the trap's plate and its yellow/orange phases are the survival signal, and a skin would either
    make traps easier to spot in the dark or muddy that signal.
  * **How far the later biomes are.** **DECIDED 2026-09-30 (owner: take recommended): they stay where they are**
    (Forge at 40.6 min, Crystal ~2.4 h, Crypt ~6.3 h, Sky Ruins ~17.5 h, Astral ~38.9 h of normal play in the
    model), the last two being the long-term goal. `Pacing.spec` now holds it: exactly one biome's fanfare lands
    30-45 min into normal play (the owner's brag window: the Lava Forge, 40.6), and the last two stay over 10 h away.
  * **The knock with a monster behind** (§3). **DECIDED 2026-09-30 (owner: take recommended): a stagger, but only
    when a monster is close enough to catch you** (within 24 studs); otherwise the knock-down stays. No option was
    marked; the owner's standard says "a hit costs a little, never a run", which a knock-down with a monster on
    your heels breaks, while the brief's knock-down is kept everywhere it cannot cost the run.
* **Re-checked 01.10 (pass 1 re-run, §14):** no owner decision is open. Each of the five above is recorded as
  "DECIDED 2026-09-30 (owner: take recommended)", and the mutations that hold them (O1-O5) were re-run on the
  current tree and still kill. The "open items" in `docs/superpowers/specs/2026-07-25-lobby-modes-design.md` §10
  were planning choices for the lobby modes, settled by the build (doors with prompts, the friends check), not
  owner decisions.
* The 30.09 pass and the 01.10 re-run are not committed, pushed or published. Studio not opened.
* §8 in full.
* **01.10, pass 2 (§15):** the standard's items are all built or have a written reason; what is left is the night
  shift's (§8, §9, `MARKETING.md` "Clip list"), the clip scenarios marked **new** in `tools/film_game.py` (the tools
  owner's), and replacing the live store text with `tools/store_text.py` after the next publish.

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

---

## 13. Second review and the owner's decisions (30.09.2026)

A second independent reviewer reported five findings, all low. The same day the owner decided every open
question in §10: "take the recommended option for all". This pass was the only writer in `labyrint-spill`.
Each finding was **reproduced first on the unchanged tree** (numbers below), then closed test-first: the new
assertion was run against the unfixed build and watched failing for the stated reason, then the game (never the
test) was changed. Each owner decision got its assertions first too. Two rules changed on the server this time.

| # | finding | reproduced (unchanged tree) | fix | failed first |
|---|---|---|---|---|
| 1 | A Friends host who walks out under "it's free, nothing is lost" cannot get back to their friends. | New `check_labyrintspill_friends` (Roblox's friendship modelled in the check: A and B friends, nobody their own friend): A hosts L31, the sign is up 1.0 s in, B joins, A walks out 1.5 s in; the Friends door leaves A in no maze and sends A a picker; StartRun("friends") puts A in a new `Maze_2`; B stays alone in `Maze_1`. | `findFriendsInstance` on the server: the player's own Friends run first, then a friend's, never a stranger's or a full one; used by the Friends door and by StartRun. Group runs already kept the promise (asserted). | 4 failures, e.g. "the Friends door puts the host back in the same run as their friend -> got nil, want Maze_1"; "StartRun(friends) ... -> got Maze_2". |
| 2 | The ring is only held away from the trap's colours; a ring in a "step on this" colour passes every gate. | RGB distances through every grade, exactly the reviewer's: deep-blue button 51.2-52.8, cyan button 56.6-61.9, guide dots 64.8-69.3; `Biomes.validate` accepted RingColor (70,110,255) and (90,235,255). | `Biomes.StepOnColors` (the server's four button colours, guide dots, coin, gem, exit pad; `_biomes` §0 parses them back out of the server script) and a `validate` rule: the ring stays at least CIE76 delta E 25 from each, through every biome grade (`Biomes.lab/deltaE/graded`, pinned to known values). The shipped ring passes: nearest is the deep-blue button at 31.8 (the game's own cyan button and guide dots are 11.0 apart). | `Biomes.spec`: the colour maths absent, "a ring in the deep-blue secret button's own colour is rejected -> got true", and the same for the guide cyan, the cyan button and a half-way blue (12 failures in that section). |
| 3 | The biome card does not wait for the daily-reward popup; on a phone the popup covers it. | New `check_labyrintspill_popups` (800x360, touch, the Group door 1.6 s after spawn, L26): card and popup both visible **2.67 s** (the reviewer's figure), 0.00 s of card after the popup. | `Biome.client` waits for both centre cards (`OppsummeringsKort`, `DagligBelonning`), and a card already on screen steps aside when one pops over it and comes back whole afterwards, without a second fanfare flash (a card that has waited 8 s is shown regardless). After: **0.03 s** (the one frame in which the popup appears), 3.53 s of card after it, one flash. | 2 failures: "never on screen together for more than one frame (2.67 s)", "shown in full once the popup has gone (0.00 s)". |
| 4 | Decor stands in front of the free-break sign on some levels. | Pure count: `decorFor` dressed the Lobby door's face (fine cell 1,0, +Z) on **220 of 500** levels. New §7 of `_biomes`, real server and client: 2 parts in front of the sign at L2 and L5, 3 at L103 and L108, 1 at L50 and L55 plus 1 inside the door slab; the controls L3 and L51 had 0. | `Biomes.reservedFace`: `decorFor` never dresses the start cell's back wall (the server always starts a maze in cell 0,0 and puts the door on its -Z wall); a rule on grid position, like every decor rule. After: 0 everywhere; the same face one wall along and the door wall's other side are still dressed. | `Biomes.spec` "no level dresses the Lobby door's face -> got 220, want 0"; `_biomes` §7: 8 failures. |
| 5 | The 140-part budget is not enforced by any code in the game. | `Biomes.validate` accepted MaxDecorPieces = 40 (worst case 179 parts) and MaxHazardsShown = 9; MaxLocalParts, MaxEmitters, MaxMazeLights and MaxLobbyLights were read by nothing shipped. | `validate` refuses a worst case (`Biomes.partBound()` = decor cap x parts per piece + hazard views x `MaxHazardViewParts` + 1 air box) over `MaxLocalParts` (123 <= 140 shipped), air + bursts over `MaxEmitters`, and any maze light; the client then keeps the biome layer off. `_budget` holds `MaxHazardViewParts` (9) to the real views; the campfire's light exists only while `MaxLobbyLights` >= 1. | `Biomes.spec`: 13 failures, e.g. "a decor cap of 40 is rejected -> got true". |

**The owner's decisions** (recorded in §10 as "DECIDED 2026-09-30 (owner: take recommended)"):

| decision | taken | why | held by |
|---|---|---|---|
| A guide bought, then a walk-out | **The guide is kept** until its level is cleared: dying or walking out no longer loses it; the next attempt at that level starts with it at no cost; a run that moves on into that level lights it; it is saved with the player (`guideLevel`); the lobby card says "Guide kept", and the offer no longer says "for this run". | No option was marked. "Never punishing": a stuck child who bought a guide and was then caught by a monster lost up to 250 coins. Exploit review: it lights only on the level it was bought for (never banked for a harder one), cannot be bought twice (`inst.assist`), is used up by a clear (`Assist.afterClear`, for everyone in the clearing run), is decided by the server from saved data, and a guided run still gives no time record. In a shared run a kept guide lights for the whole run, exactly as buying it there would. | `Assist.spec` (8 new), `check_labyrintspill_guide` (new, 30), `check_labyrintspill_rest` §7 (D), whose two assertions of the old rule (the guide lost on a walk-out, the next attempt without it) now expect the new rule: the only existing assertions changed, because the rule changed. |
| The ring's colour | **Blue stays**, now also at least delta E 25 from every step-on colour (finding 2). | The recommendation in §10 (the reviewer's reasoning and the server's palette rule); Studio still judges how it reads. | `Biomes.spec`, `_hazards` §1. |
| Themed trap skins | **Not built.** | The recommendation in §10: the trap's plate and phases are the survival signal. | Unchanged code; the trap-signal rules in `Biomes.validate`. |
| How far the later biomes are | **They stay**: Forge 40.6 min, Crystal ~2.4 h, Crypt ~6.3 h, Sky Ruins ~17.5 h, Astral ~38.9 h of normal play in the model. | The recommendation in §10 (the long-term brag), and the owner's standard: a brag moment 30-45 min in, a long-term goal beyond. | `Pacing.spec`: exactly one biome's fanfare lands 30-45 min in (the Lava Forge, 40.6), and the last two stay over 10 h away (17.5 h, 38.9 h). |
| The knock with a monster behind | **A stagger when a monster is within 24 studs** (the same shake, flash and shove, on your feet); the knock-down everywhere else. | No option was marked. The standard says "a hit costs a little, never a run"; a knock-down with a monster on your heels breaks it, and the brief's knock-down is kept wherever it cannot. `CellHazards.validate` holds the radius over the worst case: (15 + 5) x 0.8 + 4 = 20 studs. | `CellHazards.spec` (10 new), `_hazards` §12 (a monster at 10 and at 23 studs: no `PlatformStand`, still a flash and a 5 studs/s shove; at 26: knocked down). Every other `_hazards` section now parks the run's monsters far away first: headless they never move, and on L60 a monster stood within 24 studs of the cells tested, which turned 6 knock-down assertions into staggers until it was parked. |

**Mutation sweep** (`scratchpad/lab_p1_0930/sweep.py` + `muts.py`, `muts2.py`; logs `sweep_r1.log`, `sweep_r2.log`).
Same harness as §12: four workers on scratch copies verified byte-identical to the real tree; for every
mutation exactly one occurrence in its file and in the baseline bundle, the rebuilt bundle proved equal to the
baseline with that single replacement, all 31 suites run (14 specs, 17 checks), the original bytes restored and
md5-checked; every worker's copy was identical to the real tree at the end, and the real tree's sha256 was
unchanged across both rounds. **40 mutations: 40 killed, 40 reached the bundle. 5 controls: 5 survived.**

| id | mutation | killed by |
|---|---|---|
| F1a / F1b / F1c | the host's own run not looked for / the Friends door never joins / a stranger may join | `_friends` |
| F2a | the step-on rule off | `Biomes.spec` |
| F2b / F2c | the ring in the deep-blue button's / the guide dots' colour (the reviewer's two survivors) | `Biomes.spec`; `validate` then turns the biome layer off, so 7 checks too |
| F2d / F2e | the mirror drifts / the server's palette changes without it | `Biomes.spec` + 7 checks / `_biomes` §0 |
| F2f / F2g | delta E floor 5 / a wrong Lab conversion | `Biomes.spec` |
| F3a / F3b / F3c | the card waits only for the summary card / never steps aside / flashes again | `_popups` |
| F4a / F4b / F4c | no reserved face / the wrong face / `decorFor` ignores it | `Biomes.spec`, `_biomes` §7 |
| F5a / F5d / F5e | the part bound / the emitter rule / the maze-light rule off | `Biomes.spec` |
| F5b | the reviewer's O5: decor cap 40 | `Biomes.spec` + 7 checks |
| F5c | `MaxHazardViewParts` 8 (under the real 9) | `Biomes.spec`, `_budget` |
| F5f | `MaxLobbyLights` 0 | `_biomes` §6, `_rest` |
| O5a / O5d / O5e | `hitMode` always knocks / the safe-radius rule off / radius 12 | `CellHazards.spec` (O5a also `_hazards`; O5e also 3 checks, with hazards then off) |
| O5b / O5c | the client ignores `hitMode` / sees no monsters | `_hazards` §12 |
| O5f | `MonsterSpeedMax` mirrored as 12 | `_biomes` §0 |
| O1a / O1f / O1g | a kept guide never lit / buying forgets the level / a run moving on into the level does not light it | `_guide` (and `_rest` for O1a, O1f) |
| O1b / O1c | the guide lights on any level / is never used up | `Assist.spec`, `_guide` (+ `_rest` for O1b) |
| O1d / O1e / O1h / O1i / O1j | a clear does not use it up / not saved / no lobby card / AssistState never says kept / the offer still says "for this run" | `_guide` |
| O4a / O4b | the Forge moved to L66 / Sky Ruins to L181 | `Pacing.spec` |
| CONTROL x5 | the ring (100,161,255); safe radius 23; delta E floor 26; two punctuation changes in the guide texts | survived |

**Gates** (§7, last column): specs **2 148 / 0** (14 files), headless checks **1 067 / 0 + 2 PASS** (17 files), on
bundle md5 `0c9940195b2afcd4a1c9de8180fc4ed8`; a second full run gave identical summaries. The lint for writes to
undeclared globals is clean on every `src` file.

**Files written in this pass:** `labyrint-spill/src/server/MazeGame.server.luau`, `src/shared/Biomes.luau`,
`CellHazards.luau`, `Assist.luau`, `BreakRoom.luau` (comments only), `src/client/Biome.client.luau`,
`RestClient.client.luau`, `AssistClient.client.luau`, `tests/Biomes.spec.luau`, `CellHazards.spec.luau`,
`Assist.spec.luau`, `Pacing.spec.luau`, `EYECANDY.md`, `CLAUDE.md`; in robloxemu, `check_labyrintspill_friends.luau`,
`_guide.luau`, `_popups.luau` (new), `_biomes.luau` (§0 mirrors, §7), `_budget.luau`, `_hazards.luau` (§12, parked
monsters), `_rest.luau` (§7 D), `_lib.luau` (its helpers follow `ctx.plr`, so a check can rejoin), and the rebuilt
`build/labyrint-spill.luau`. Not committed, not pushed, not published; Studio not opened.

**Not done here** (the complete-game standard, left for a later pass): the highscore board is public only (no
Friends board, key `tostring(userId)` rather than `u_<userId>`, no reached-first tie-break); saves use `SetAsync`
without a session lock or owner token; the README has no store description of at most 1000 characters; `MARKETING.md`
has no 5-10 clip list in the standard's form.

---

## 14. Pass 1 re-run (01.10.2026)

The workflow ran pass 1 again. The tree it found was not the tree §13 left: pass 2 had worked in `labyrint-spill`
from 01.10 00:09 to 00:50 and was cut off before writing any docs. Its uncommitted work is still there, untouched by
this re-run except for one rule below: critters in every band (`Biomes.Critters`, `Biome.client`, `BiomeArt`), a
highscore board (`Board.luau`, `BoardConfig.luau`, `BoardClient`), server changes (save locks, a walk guard), and the
checks `_board`, `_critters`, `_journey`, `_overlap` and `_save`. Every gate was green on it before this re-run
touched anything (first column below). Each of the five second-review findings was measured again on that tree.

| # | finding | measured on the current tree (before any edit) | verdict |
|---|---|---|---|
| 1 | A Friends host who walks out under the free-break sign cannot get back. | The reviewer's scenario through the real server (friendship modelled as in `_friends`): the sign reads "Need a break? Walk out now — it's free, nothing is lost" 1.0 s in; B joins `Maze_1`; A walks out at 1.5 s and is in no maze; the Friends door puts A back in `Maze_1`, **0** OpenPicker sent, B still in `Maze_1`. | Does not reproduce (closed 30.09). |
| 2 | A ring in a "step on this" colour passes every gate. | `Biomes.validate` refuses RingColor (70,110,255) ("looks like the deep-blue secret button") and (90,235,255) ("looks like the cyan secret button"), and the positive control (255,205,60). The shipped ring keeps CIE76 delta E **31.8** from its nearest step-on colour (the deep-blue button) through every grade. | Does not reproduce (closed 30.09). |
| 3 | The biome card does not wait for the daily-reward popup. | `_popups` (800x360, touch, the Group door 1.6 s after spawn): card and popup on screen together **0.03 s** (the reviewer measured 2.67 s), 3.53 s of card after the popup. | Does not reproduce (closed 30.09). |
| 4 | Something client-built stands in front of the free-break sign. | **Decor:** `decorFor` dresses the Lobby door's face on **0** of 500 levels (220 with `reservedFace` switched off in the probe); `_biomes` §7 counts 0 decor parts in front of the sign and 0 in the door slab at L2, L5, L103, L108, L50, L55 and the controls L3, L51. **Critters (pass 2's new dressing): reproduces.** A probe over L1-481 through the real server and clients (two walks a level in the sign's 6 s: away along the route to the exit, and 2 s out then back toward the door): a crypt **spider** climbing the start cell's back wall stood in front of the sign while it was up on **37 levels** (39 walks); **12 843** critter part-frames inside the door slab (rats, salamanders, spiders), **209 864** in the start cell. Cause: `findHome` could home a critter in the start cell once the player had walked out of it. | **Reproduced in a new form; fixed.** |
| 5 | The 140-part budget is not enforced in code. | `validate` refuses MaxDecorPieces 40 (179 parts) and MaxHazardsShown 9 (186 parts); the shipped bound is 123 <= 140. Critters take decor slots, and `validate` holds MaxCritters <= MaxDecorPieces and every critter to MaxPrimsPerPiece parts, so the bound still covers them. | Does not reproduce (closed 30.09). |

**The fix (finding 4, critters).** `Biomes.critterHomeFree(fx, fy)`: the open cell the reserved face looks into (the
start cell, fine 1,1) is no critter's home; `Biome.client`'s `findHome` asks it. A rule on grid position only, like
`reservedFace`. Nothing visible is lost: the player starts in that cell and a critter never shares the player's cell.
Failing first, on the unfixed tree: `Biomes.spec` 2 failures ("the cell the Lobby door's face looks into ... is no
critter's home -> got true"; "exactly one open cell of a 30 x 30 maze is closed to critters -> got 0, want 1");
`_biomes` §8 (new: L161-200, the out-and-back walk, every frame of the sign's window) 3 failures: **559** critter
part-frames in front of the sign on 13 of 40 levels, **2 329** in the door slab, **16 620** in the start cell.
After: 0, 0 and 0, with the sign up in 6 933 of 7 213 frames and critters on show in all 7 213 (the exposure is
asserted, so a 0 is not a walk without critters). The whole-game probe after the fix: **0** walks with a critter in
front of the sign, **0** part-frames in the door slab, **0** in the start cell, on all 481 levels (179 446 frames).

**Owner decisions.** None open. The five in §10 are recorded "DECIDED 2026-09-30 (owner: take recommended)", and
every mutation that holds them still kills on the current tree (below). The "open items" in
`docs/superpowers/specs/2026-07-25-lobby-modes-design.md` §10 were planning choices for the lobby modes, settled by
the build; no owner decision is pending there.

**Mutation sweep** (`scratchpad/lab_p1r_1001/sweep.py` + `muts_r.py`, log `sweep_r1.log`, results `sweep_r1.json`;
the 30.09 harness). Five workers on scratch copies verified byte-identical to the real tree; each worker's first job
was a no-op run that had to come out green on all 37 suites (it did, five times). For every mutation: exactly one
occurrence in its file and in the baseline bundle, the rebuilt bundle proved equal to the baseline with that single
replacement, all 37 suites run (15 specs, 22 checks), the original bytes restored and md5-checked. Every worker's
copy was identical to the real tree at the end, and the real tree's 80 source, test and check files had the same
sha256 after the sweep as before it. **43 mutations: 43 killed, 43 reached the bundle. 11 controls: 11 survived.**

| id | mutation | killed by |
|---|---|---|
| N1 | the client homes critters in the start cell again | `_biomes` §8 |
| N2 | `critterHomeFree` closes nothing | `Biomes.spec`, `_biomes` §8 |
| N3 | it closes the next cell in instead of the start cell | `Biomes.spec`, `_biomes` §8 |
| F1a-c, F2a-g, F3a-c, F4a-c, F5a-f, O1a-j, O4a-b, O5a-f | §13's 40 mutations, re-run on the current tree (F1b retargeted to its one line: the server script has CRLF line ends since pass 2, and the bundle carries LF) | all killed, by the same suites as in §13, plus pass 2's new checks wherever a mutant turns the biome layer off |
| CONTROL | one spider leg 1/255 redder (new); §13's five controls; five no-op baselines | survived |

**Gates** (bundle md5 `1efe2dcd03d264bd9b64a96a099d12ca`; a second full run gave identical summaries):

| gate | start of the re-run (pass 2's tree, bundle `1cb110bf...`) | end of the re-run |
|---|---|---|
| `tests/Assist.spec` | 78 / 0 | 78 / 0 |
| `tests/Biomes.spec` | 1 367 / 0 | **1 371 / 0** |
| `tests/Board.spec` (pass 2) | 66 / 0 | 66 / 0 |
| `tests/BreakRoom.spec` | 35 / 0 | 35 / 0 |
| `tests/CellHazards.spec` | 83 / 0 | 83 / 0 |
| `tests/Contributors.spec` | 18 / 0 | 18 / 0 |
| `tests/EnvBands.spec` | 124 / 0 | 124 / 0 |
| `tests/Hazard.spec` | 36 / 0 | 36 / 0 |
| `tests/Pacing.spec` | 280 / 0 | 280 / 0 |
| `tests/Progression.spec` | 43 / 0 | 43 / 0 |
| `tests/Rest.spec` | 55 / 0 | 55 / 0 |
| `tests/lightingpresets.spec` | 41 / 0 | 41 / 0 |
| `tests/mazeref.spec` | 27 / 0 | 27 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 |
| `tests/touchtarget.spec` | 52 / 0 | 52 / 0 |
| **spec total (15 files)** | **2 375 / 0** | **2 379 / 0** |
| `check_labyrint` | PASS | PASS |
| `check_labyrint_spawn` | 36 / 0 | 36 / 0 |
| `check_labyrintspill_biomes` | 324 / 0 | **329 / 0** |
| `check_labyrintspill_board` (pass 2) | 74 / 0 | 74 / 0 |
| `check_labyrintspill_budget` | 28 / 0 | 28 / 0 |
| `check_labyrintspill_cards` | 17 / 0 | 17 / 0 |
| `check_labyrintspill_compile` | 49 / 0 (41 sources) | 49 / 0 |
| `check_labyrintspill_critters` (pass 2) | 53 / 0 | 53 / 0 |
| `check_labyrintspill_friends` | 26 / 0 | 26 / 0 |
| `check_labyrintspill_guide` | 30 / 0 | 30 / 0 |
| `check_labyrintspill_hazards` | 72 / 0 | 72 / 0 |
| `check_labyrintspill_hud` | PASS | PASS |
| `check_labyrintspill_journey` (pass 2) | 52 / 0 | 52 / 0 |
| `check_labyrintspill_layout` | 266 / 0 | 266 / 0 |
| `check_labyrintspill_overlap` (pass 2) | 28 / 0 | 28 / 0 |
| `check_labyrintspill_popups` | 9 / 0 | 9 / 0 |
| `check_labyrintspill_rest` | 69 / 0 | 69 / 0 |
| `check_labyrintspill_save` (pass 2) | 63 / 0 | 63 / 0 |
| `check_labyrintspill_shots` | 54 / 0 | 54 / 0 |
| `check_lighting` | 19 / 0 | 19 / 0 |
| `check_secretdoors` | 50 / 0 | 50 / 0 |
| `check_themes` | 23 / 0 | 23 / 0 |
| **headless check total (22 files)** | **1 342 / 0 + 2 PASS** | **1 347 / 0 + 2 PASS** |

The lint for writes to undeclared globals is clean on both changed source files.

**Files written in the re-run:** `labyrint-spill/src/shared/Biomes.luau` (`critterHomeFree`),
`src/client/Biome.client.luau` (`findHome` asks it; a comment), `tests/Biomes.spec.luau` (4 assertions),
`EYECANDY.md` (the state paragraph, §7 and §10 notes, this section), `CLAUDE.md` (one bullet); in robloxemu,
`check_labyrintspill_biomes.luau` (§8, 5 assertions) and the rebuilt `build/labyrint-spill.luau`. Not committed,
not pushed, not published; Studio not opened. Pass 2's own work still needs its docs (CLAUDE.md and this file say
nothing about the board, the save locks, the walk guard or the critters beyond this section).

---

## 15. Pass 2: complete against the standard (01.10.2026)

Pass 2 worked in this game from 01.10 00:09 to 00:50 and was cut off by a usage limit before writing any docs; pass 1
then re-ran (06:40-07:35, §14) on top of its uncommitted work. This resume (from 07:36) read every changed and new
file, ran every gate first (identical to §14's end: specs **2 379 / 0** in 15 files, checks **1 347 / 0 + 2 PASS** in
22 files, bundle `1efe2dcd...`), checked the game against every item of `docs/complete-game-standard.md` itself, built
what was missing test-first, mutation-tested pass 2's assertions (never swept before) and its own, and wrote the docs.
Not committed, pushed or published; Studio not opened.

### What pass 2 had built (found complete, now documented)

* **The highscore board** (`Board.luau` = +1 Jump's template, `BoardConfig.luau`, `BoardClient`, the server's board
  section): metric `accepted`, the highest level cleared in sequence, measured by the server at the exit behind the
  walk guard, never by a god-mode run; `LabyrintTopp_v3`, key `u_<userId>`, value `level * 2e9 + (2e9 - reachedAtUnix)`
  (`acceptedAt` is saved with the profile), written only when it rises (`writeBoard` + `Board.keepHigher` in an
  `UpdateAsync`); the public top 10 fetched at most every 60 s and shown both on the old HUD panel and on the board;
  friends only on demand (`GetFriendsAsync`, at most 200, cached 300 s, every friend's value cached 120 s, a 40 + 1/s
  read limiter that leaves 10 of Roblox's budget); a physical board ("TOP MAZE RUNNERS", lobby (-15, 5, 2), 15 studs
  from the pad, facing it, gold trim) with a ProximityPrompt (E) that toggles PUBLIC and FRIENDS per player; names from
  the server, the friends list or `GetNameFromUserIdAsync`, cached in memory, never stored; useful notes for an empty
  public board, no friends, friends with no levels, a failed friends fetch, and "checking N of M". The old
  `LabyrintTopp_v2` (raw level) is carried over once per server start. Held by `tests/Board.spec` (66) and
  `check_labyrintspill_board`.
* **Session lock and owner token** (`loadPlayer`, `savePlayer`, `grantOnce`): one `UpdateAsync` to load, which takes
  the lock unless another live server holds it (then the session is read-only and the player is told); every save an
  `UpdateAsync` that lands only while the record carries this session's token (otherwise the session stops saving and
  says so); the autosave (60 s) renews the 180 s lock, leaving releases it, an expired lock is taken over; the
  starter gift, the contributor reward and the daily reward are granted inside one write or rolled back.
  `check_labyrintspill_save` (63).
* **The walk guard** (`Progression.minClearSeconds`, `CONFIG.WalkGuard`, slack 0.85): an exit reached faster than the
  shortest route (secret doors open, corners cut) can be walked at the top speed does not count, and the player is
  told "Too fast: nobody can run this maze in ... s". `tests/Progression.spec` (43), `check_labyrintspill_journey`.
* **`plr.RespawnLocation`** = the lobby pad, set on join and for players who were in before the lobby existed.
* **Critters in every biome** (`Biomes.Critters`, `crittersAt`, `critterPose`, `BiomeArt`, `Biome.client`): rats,
  butterflies, bats, salamanders, beetles, spiders, swallows, star jellies; 2-3 near the player, inert, in open cells,
  never the start cell (§14), sharing the decor cap. `Biomes.spec`, `check_labyrintspill_critters` (53).
* **HUD rule 4b asserted** by `check_labyrintspill_overlap` (28), with the reason it is not switched on in the stock
  gate written in `check_labyrintspill_hud` (re-measured here: with `overlap = true` the stock gate reports **13**
  overlaps, every one a closed ScreenGui counted as shown or a `UISizeConstraint` ignored). Its first run found a
  real defect, fixed in pass 2: `LeaderboardClient` looked for the minimap's `Kart` frame at its old place, so on a
  tablet the records panel lay over a bought minimap (120 x 120 px on 1024 x 768).
* **The whole player path, walked** (`check_labyrintspill_journey`, 52): joins before the server script runs, is
  spawned on the pad by the engine, walks to the Solo door, uses the prompt, picks Continue, walks level 1 cell by
  cell over every coin to the exit, is refused a teleport to level 2's exit (and told why), walks it, walks out
  through the Lobby door, buys the Longer torch with the coins it earned, leaves (the lock is released), rejoins:
  coins, trophies, the perk, `accepted` 2 and the board entry are all there.

### The standard, item by item (checked on this tree)

| § | item | state | held by |
|---|---|---|---|
| 1 | core loop reachable from join, whole path walked headless (spawn, objective, loop, earn, spend, rejoin) | done (pass 2) | `check_labyrintspill_journey` |
| 1 | `plr.RespawnLocation` at a real, enabled SpawnLocation | done (pass 2) | `check_labyrint_spawn` (36), `_journey` |
| 1 | server-authoritative, nothing secret replicates | holds; one written reason | the maze is geometry every player sees, and a secret wall is coloured like its button on purpose; the server sets one attribute (`MazeFolder`, the player's own maze). **No salt on `WorldSeed`, by the owner's design**: every player gets the same mazes so medal times are fair; memorising a visible maze is learning a route, and the board ranks levels cleared in order, not luck (`CLAUDE.md`, "Feller å kjenne til") |
| 1 | DataStore: pcall, lock, owner token, string keys, one-time grants in one atomic write | done (pass 2) | `check_labyrintspill_save` |
| 1 | no silent no-ops | done; one gap closed here | a refused exit, a read-only session, a failed friends fetch say why; **new**: a board whose store is down says so instead of "Loading..." for ever (`_boarddown`) |
| 2 | Fx preset and signature particles | done (before) | `Fx.applyLighting(Fx.Presets.Maze)`; coins and gems Neon and spinning; biome air, impact bursts, the campfire |
| 2 | 5+ bands with light, colour, scenery, critters, weather | done (8 biomes; critters pass 2) | light is hue only, on purpose (darkness is the mechanic, §2 rule 1); `Biomes.spec`, `_biomes`, `_critters` |
| 2 | hazards rare, telegraphed, ring marks the zone, one at a time, a hit costs a little | done; one rule enforced here | one near-hit per 2.59 min (`Pacing.spec`); ring blue and stagger near a monster (owner, §13); **new**: one at a time is enforced in `CellHazards.validate` |
| 2 | rest / pause that is no exploit | done (before) | §4; `BreakRoom.spec`, `_rest` |
| 2 | budgets measured and capped in code | done (30.09) | `Biomes.validate` (`partBound` 123 <= 140), `_budget` |
| 2 | brag moment in 30-45 min, long-term goal beyond | done (30.09) | `Pacing.spec`: exactly one biome fanfare in the window, the Lava Forge at 40.6 min (normal player, no deaths: a lower bound); Sky Ruins 17.5 h, Astral Labyrinth 38.9 h, and the board |
| 2 | phone first: UIScale root, nothing under the thumbstick or jump, 44 px, rule 4b | done | stock gate (`check_labyrint`, `_hud`), `touchtarget.spec` (52), `_overlap` with the written reason in `_hud` |
| 3 | public + friends board, first-reached tie-break, physical board with toggle | done (pass 2); two gaps closed here | `Board.spec`, `_board` (**new**: god-mode users never on it), `_boarddown` (**new**) |
| 3 | promo codes public, no Robux cost, no gambling or pay-to-win | holds | no codes; `RobuxConfig.EnableRobux = false`; perks are bought with coins earned in play |
| 4 | README store text (<= 1000 chars, honest, no coloured squares) | **new** | `tests/docs_check.py`: 984 characters, every number checked against the source |
| 4 | EYECANDY needs-Studio list and 1920x1080 thumbnail shot list | updated | §8 (24 items: 6 new for pass 2), §9 (1920x1080, a board shot) |
| 4 | clip list: 5-10 clips, 7-15 s, vertical 1080x1920, with staging | **new** | `MARKETING.md` "Clip list": 9 clips (2 exist, 7 new), `docs_check.py` |
| 4 | CLAUDE.md: every gate and the traps | updated | the gate table and "Feller å kjenne til"; `docs_check.py` fails if a gate file is not named |
| 4 | every gate green, TDD, mutation-tested with a control | done | below |
| 5 | Studio, thumbnails, clips, publish, marketing | night shift | §8, §9, `MARKETING.md` |

### What this pass built, each test first

1. **One falling hazard at a time, enforced** (`CellHazards.validate`). It held already: two hazard cells are at
   least `MinSpacing` (3) maze cells apart, 54 studs, more than two `ShowRadius` (52), so no spot has two near it.
   Measured: the closest two hazard cells on any of 400 levels are 56.9 studs apart, and a probe through
   `Pacing.spec`'s walks (240 levels, 1 430 min, every 0.05 s) found **0** frames with two warnings inside the banner's
   20 studs or inside `ShowRadius`. But no rule kept a retune from breaking it. Failing first: `CellHazards.spec` 3
   failures (`MinSpacing` 2 and `ShowRadius` 28 accepted; a config without `ShowRadius` accepted). Now `validate`
   refuses `MinSpacing * 2 * CellSize <= 2 * ShowRadius` and a missing `ShowRadius`.
2. **The board while its store is down** (`refreshPublic`, the autosave, `BoardConfig.Text.PublicFailed`). Found here:
   when a server's first `GetSortedAsync` failed, the board said "Loading..." for as long as the store was down, and a
   board write lost to the outage waited for the player's next join. Failing first, in a new check (the emulator runs
   one harness per process, and `_board` needs a store that works): `check_labyrintspill_boarddown` 5 failures
   ("Loading..." with the store down; no note; `u_601` never written once the store answered; the board empty). Now
   the board says "Couldn't load the board right now. It will try again in a minute." while it has never had rows to
   show (a later failure keeps the last list), and the autosave retries a write that is owed (`writeBoard` makes no
   call when nothing is). 9 / 0.
3. **The ship-and-market documents, held to the game** (`tests/docs_check.py`; Python because the luau CLI cannot read
   a file). Failing first: **75** failures (no store text, no clip list, no 1920x1080, a needs-Studio list without
   pass 2, `CLAUDE.md` not naming 28 gates). Then: the README store text (984 characters, ASCII; 25 numbers checked
   against the source, from the biome levels and trap timings to the perk prices and the pacing model's 41 minutes,
   which it runs), the 9-clip list in `MARKETING.md`, §8 items 19-24, §9's size and board shot, and `CLAUDE.md`'s gate
   table and traps. **146 / 0.**
4. **Test gaps the sweep found** (the behaviour was right; each assertion passes on the real build and was then
   watched failing on its mutant in round 2): god-mode users never stand on the board (`_board`, S2); the critter cap
   may not exceed the decor cap (K1), no band may want more critters than the cap (K3), and the seam trim holds a forced
   cap of 2 (K5) (`Biomes.spec`).
5. `check_labyrintspill_hud`'s comment now says where rule 4b is asserted and why not there (13 artifacts, measured).

### Mutation sweep

Same harness as §13-§14 (`scratchpad/lab_p2b_1001/sweep.py`, `muts.py`, `sweep_r1.log`/`.json`; round 2 `sweep2.py`,
which also takes several replacements in one file, `muts2.py`, `sweep_r2.log`/`.json`). Five workers on scratch copies
verified byte-identical to the real tree; each worker's first job a no-op run that had to be green on all 38 suites
(15 specs, 23 checks); for every mutation exactly one occurrence in its file and in the baseline bundle, the rebuilt
bundle proved equal to the baseline with that replacement, all 38 suites run, the original bytes restored and checked.
Every worker's copy was identical to the real tree at the end of both rounds, and the real tree's sources, tests and
checks had the same sha256 after each round as before it (the one difference after round 1 is the god-mode assertion,
written into `_board` while round 1 ran on its own copies).

**Round 1: 33 mutations of pass 2's work and this pass's, all 33 reached the bundle. 26 killed for the stated reason,
1 "killed" only because the mutated server did not load (W3), 6 survived. All 8 controls survived (5 no-op runs, 3
real edits).**

| id | mutation | round 1 | round 2 |
|---|---|---|---|
| P1 | `Board.encode`: a later reach of the same level ranks higher | `Board.spec`, `_board` | |
| P2 | `keepHigher`: a same-level later reach overwrites the first | `Board.spec` | |
| P3 | `friendsView`: the viewer's own row not pinned below the shown rows | `Board.spec` | |
| P4 | an empty friends board (no friend has a level) says nothing | `Board.spec`, `_board` | |
| P5 | key `tostring(userId)`, not `u_<userId>` | `Board.spec`, `_board`, `_boarddown`, `_journey` | |
| S1 | the public top 10 fetched every 5 s, not 60 | `_board` §4 | |
| S2 | god-mode users written to the board | **SURVIVED** (no assertion) | killed by `_board`'s new section: `got 80240000000, want nil` |
| S3 | written on every call, not only when the level rose | `_board` §3 | |
| S4 | the friends loop's own cap removed | **SURVIVED: equivalent** (two more guards hold 200) | S4b, the cap raised to 250: killed by `_board` §8 (`got 250, want 200`) |
| S5 | the prompt never switches to Friends | `_board` | |
| S6 | (this pass) the outage note removed | `_boarddown` | |
| S7 | (this pass) the autosave's retry removed | `_boarddown` | |
| L1 | a live server's lock overwritten at load | `_save` | |
| L2 | saved without checking the owner token | `_save` | |
| L3 | leaving never releases the lock | `_save`, `_journey` | |
| L4 | an expired lock blocks for ever | `_save` | |
| L5 | `grantOnce` keeps a grant it could not save | `_save` | |
| L6 | `canSave = true` after a failed load | **SURVIVED: equivalent** (the missing session token still stops every write) | L6c, both guards gone: killed by `_save` §8 (`the stored record is intact -> got 150, want 42`: the default profile plus a daily reward over the real one) |
| W1 | `minClearSeconds` returns 0 | `Progression.spec`, `_journey` | |
| W2 | `finishRun` ignores the walk guard | `_journey` | |
| W3 | a refused exit says nothing | 23 checks failed because the mutated server did not load (a statement opening with a parenthesis): **not a kill** | W3b, `local _ = ...`: killed by `_journey` alone (`the player is told why: nil`) |
| W4 | the walk clock not restarted when the run moves on | `_journey` | |
| R1 | `RespawnLocation` never set | `_spawn`, `_journey` | |
| K1 | `validate`: the critter cap may exceed the decor cap | **SURVIVED** (no assertion) | killed by `Biomes.spec` |
| K3 | `validate`: a band may want more critters than the cap | **SURVIVED** (the old assertion was refused by a different clause) | killed by `Biomes.spec` |
| K4 | `validate`: a critter in a signal colour | `Biomes.spec` | |
| K5 | `crittersAt` does not trim a seam's blend to the cap | **SURVIVED** (the shipped cap never binds) | killed by `Biomes.spec` (cap forced to 2: `got 171, want 0`) |
| K6 | the client's critters ignore the shared decor slots | `_critters` | |
| K7 | the wall dressing leaves no slots for critters | `_biomes` | |
| K8 | critters stay when the player walks out to the lobby | `_critters` | |
| V1 | `LeaderboardClient` looks for `Kart` at its old place | `_overlap` | |
| H1 | (this pass) one-at-a-time rule off | `CellHazards.spec` | |
| H2 | (this pass) `ShowRadius` no longer required | `CellHazards.spec` | |
| controls | 5 no-op runs; the board's trim 1/255 greener; the outage note reworded; a rat's fur 1/255 redder | survived | 2 no-op runs and the trim: survived |

The survivors were closed in the order a test gap allows: the assertion written, passing on the real build, then
watched failing on its mutant in round 2. **Round 2: 7 mutations (S2, S4b, L6c, W3b, K1, K3, K5), 7 killed, 7 reached
the bundle; 3 controls survived.** S4 and L6 are equivalent mutants (the code guards those rules twice and three
times); S4b and L6c show the assertions behind them are live.

**The documents' check** (`scratchpad/lab_p2b_1001/docmut.py`): one replacement at a time in README, MARKETING,
EYECANDY or CLAUDE.md, `docs_check.py` run, the bytes restored (sha256 verified for all four files after the run).
**11 killed**: the Forge's level 51 to 50; the store text over 1000 characters (1026); a blue-square emoji; a clip of
9-16 s; a `new` clip marked `exists`; both 1920x1080 mentions removed from §9 (D6b; D6, removing one of the two, is
equivalent and survived); 41 minutes to 30; the torch at 250; a gate missing from `CLAUDE.md`'s table; a clip without
its staging entry; the needs-Studio list without the critters. **2 controls survived** (the README's last full stop
made an exclamation mark; a clip description reworded).

### Gates

Final run on bundle md5 `f339d37c07635379dda336f823e966a9`:

| gate | start of this pass | end |
|---|---|---|
| `tests/Biomes.spec` | 1 371 / 0 | **1 376 / 0** |
| `tests/CellHazards.spec` | 83 / 0 | **88 / 0** |
| the other 13 specs (Assist 78, Board 66, BreakRoom 35, Contributors 18, EnvBands 124, Hazard 36, Pacing 280, Progression 43, Rest 55, lightingpresets 41, mazeref 27, responsive 70, touchtarget 52) | unchanged | unchanged |
| **spec total (15 files)** | **2 379 / 0** | **2 389 / 0** |
| `check_labyrintspill_board` | 74 / 0 | **77 / 0** |
| `check_labyrintspill_boarddown` | — | **9 / 0** (new) |
| the other 21 checks (check_labyrint PASS, _spawn 36, _biomes 329, _budget 28, _cards 17, _compile 49, _critters 53, _friends 26, _guide 30, _hazards 72, _hud PASS, _journey 52, _layout 266, _overlap 28, _popups 9, _rest 69, _save 63, _shots 54, lighting 19, secretdoors 50, themes 23) | unchanged | unchanged |
| **headless check total** | **1 347 / 0 + 2 PASS (22 files)** | **1 359 / 0 + 2 PASS (23 files)** |
| `tests/docs_check.py` | — (75 failures, written first) | **146 / 0** (new) |

A second full run of every gate gave identical summaries.

The lint for writes to undeclared globals is clean on the three changed source files (`CellHazards.luau`,
`BoardConfig.luau`, `MazeGame.server.luau`).

**Files written in this pass:** `src/shared/CellHazards.luau` (the one-at-a-time rule), `src/shared/BoardConfig.luau`
(`PublicFailed`), `src/server/MazeGame.server.luau` (`refreshPublic`'s outage note; the autosave retries `writeBoard`),
`tests/CellHazards.spec.luau`, `tests/Biomes.spec.luau`, `tests/docs_check.py` (new), `README.md`, `MARKETING.md`,
`EYECANDY.md`, `CLAUDE.md`; in robloxemu, `check_labyrintspill_board.luau` (the god-mode section),
`check_labyrintspill_boarddown.luau` (new), `check_labyrintspill_hud.luau` (a comment) and the rebuilt bundle.

### Still open

* The night shift (§5 of the standard): §8 (24 items), §9 (6 shots + variants, 1920x1080), and the 9 clips of
  `MARKETING.md`, 7 of which need a scenario in `tools/film_game.py` first (the tools owner's).
* The live store text (`docs/marketing/store-text.json`) is replaced with `tools/store_text.py` after the next publish,
  not before.
* Nothing is committed, pushed or published, and Studio was not opened.
