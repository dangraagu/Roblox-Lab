# Escape Room Lab — design spec (v1)

**Status (2026-10-01): built.** The game in `src/` implements this spec; `CLAUDE.md` lists every gate and each deviation
from this document with its reason. The text below is the design as written on 2026-09-30.

**Status at the time of writing: design only.** No game code existed. Nothing is committed, pushed or published, no universe
exists and Studio was not opened. Written 2026-09-30.

**Built from:** `docs/game-radar/2026-09-28-roblox-game-radar.md` ranked entry #5 "Procedural escape-room /
co-op logic puzzle" and its runner-up note (line 346), and `docs/game-radar/2026-09-06-roblox-game-radar-round2.md`
"Rising Tide 2 Player Co-Op Escape Room" (line 99).

**The finish line it is written against:** `docs/complete-game-standard.md` (every section of it is answered
below), `docs/new-game-checklist.md` (the traps), `robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md` (a seed
the client can brute-force is a leak), `anomaly-observatory/CLAUDE.md` ("ServerStorage, not the zone"),
`plus1-jump/EYECANDY.md` and `plus1-jump/src/shared/{EnvBands,Hazards,Rest}.luau` (the templates), and
`deep-vein/` (the layout).

---

## 0. How to read the numbers

Every number carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.luau` (`luau design/model.luau 2>&1`, about 20 s). The model runs the three puzzle generators this spec defines thousands of times, then walks simulated players through the Lab. It is a design tool, not game code. It is deterministic: a second run reproduced every number exactly, except generation times in ms. Those are CPU timings on this box and are quoted as the range over the two runs. |
| **[P]** | Printed by `design/hazard_probe.luau`, which runs plus1-jump's `Hazards.luau` and `Rest.luau` **unmodified** (it `require`s them from `plus1-jump/src/shared`) against this game's config. |
| **[S file]** | Measured earlier in this repo, on a sibling game, with the file named. Not a measurement of this game. |
| **[R]** | Arithmetic or a stated rule, worked inline. |
| **[A]** | An assumption. Every human reading, thinking and error rate in the pacing model is one (§10.1). The first real play session replaces them. |
| **[DOC]** | Roblox documentation. Not measured here. |
| **[STUDIO]** | A starting value only real rendering or input can settle. It is on the needs-Studio list (§20). |

---

## 1. Core loop

You ride a lift from the Lab's Atrium into a sealed room. Its exit door is a **Code Lock**: a board of clue
lines like `4 8 1 — One digit is correct and well placed.` Together the lines fit exactly one code. Some lines
are dark when you arrive, and each one is lit by solving a **feeder station** elsewhere in the room: a **Lamp
Grid** (tap a lamp and it flips with its neighbours; light them all) or a **Flask Shelf** (put the flasks in
the one order the clue sentences allow). When every line is lit, the keypad wakes up. Deduce the code, enter it,
the door opens, and you step into the exit lift for the next room. Every room is generated fresh on the server
as you ride up, and every puzzle is checked for a unique logical answer before you see it. Fifteen rooms climb
through five wings (Reception, Archive, Greenhouse, Cold Storage, Reactor), each with its own light, scenery,
creatures and weather that bleed into the last room of the wing before. After room 15 the lift goes up to the
**Roof**: you escaped the Lab. Each room pays up to three stars: **Escaped**, **Clean** (you made no wrong
try) and **Unaided** (you took no hint). Stars are kept per room, best result only. The public and friends
**Star Board** in the Atrium ranks the star total, ties going to whoever got there first. Play solo, or ride the
Pair Lift with a friend into one shared room. Rooms have no timer. The only pressure is the rare thing lowering
from the ceiling, whose red ring on the floor is exactly where it can hit you, and a **Break** button that
makes the Lab leave you alone.

---

## 2. Where v1 departs from the briefs, and why

| a brief said | v1 does | why |
|---|---|---|
| Rising Tide: rising water, three strikes and you both drown, a 6-minute round | **No clock and no fail state.** A room waits for you. | The standard says a hit "costs a little, never a run", and `Rest.luau`'s own header says a game with a clock must not map rest onto it. A flood timer would turn logic into speed-reading and make every pause a loss. The tension in v1 is the rare hazard, which costs 0.6 s. |
| Rising Tide: Diver and Keeper see different halves; the manual is rendered only on the Keeper's client | **Cut.** A pair shares one room and sees the same things. | It needs per-client secret rendering, a role UI, a solo mode that plays both roles, and a check that neither screen ever holds the other's half. The emulator has one datamodel and one `LocalPlayer` per run (`robloxemu/emu/harness.luau` line 342), so that check cannot be made headless. Listed in §21. |
| Six module types | **Three puzzle kinds**: Code Lock, Flask Shelf, Lamp Grid | Each kind has a generator whose fairness is measured (§3). Three done well beat six done thin. The table is data, so a fourth kind is an update (§21). |
| 2 players, scales to 4 | **Solo or a pair** | A room has 2 or 3 stations (§4.1), and the hands-on rule (§4.3) needs one per player, so a room has work for at most two [R]. |
| "20 depths, ranks and a global leaderboard" | **15 rooms to the roof, then stars to 45.** One board, on stars. | Any speed or volume metric is won by a solver script (§11.2). Stars are bounded at 45, so a script can only tie. |
| Seed = `RoundSeed * 1000003 + depth * 2654435761` | **No seed exists.** Each room draws from a fresh server `Random.new()`, seeded from engine entropy [DOC]. | A seed built from public numbers lets a client regenerate the answer (fork-tower REVIEW-4 §1: 30 of 30 traps predicted). A 32-bit seed can be brute-forced offline against the visible clues (REVIEW-4 "Trap 1"). §14.1. |
| Private servers + one-click rematch | Private servers are Roblox's own feature. A "rematch" is the exit lift's NEXT. | Nothing to build. |
| A daily shared seed, the return hook of the round-2 radar's "Find The Items" brief, is the obvious add-on for a procedural puzzle game | **Not built.** | A room shared by everybody is a room whose answer is shared in a Discord minutes after it goes live, and a public seed is fork-tower REVIEW-4 §1's defect. |

**Store text consequence.** The Rising Tide description may not ship: "rising water", "you both drown",
"20 depths" and "up to 4" are all false for v1. The v1 text is in §19.1.

---

## 3. The puzzles

All three are pure modules in `src/shared` (`CodeLock.luau`, `Shelf.luau`, `Lamps.luau`). Randomness is
injected as `rand: () -> number` in [0, 1). The server passes a closure over a per-room `Random.new()`. Tests
and the model pass the repo's LCG. `design/model.luau` contains a reference implementation of each generator,
and the numbers below come from running it.

Each module also exports a pure `solve` that works from the **visible** input only: the codes that fit a set of
lines, the orders that fit a set of clues, a minimum press set for a grid. The server uses `Lamps.solve` for lamp
hints. The headless walk uses all three to play from what is rendered (§3.5). A solver in public code is not a
leak: it is the rules, which any player can also write down.

### 3.1 Code Lock (the exit door)

- **The code**: L **distinct** digits from an alphabet. The alphabet is `1-6` in Reception (120 codes) and
  `0-9` everywhere else: 720 codes at L = 3, 5040 at L = 4 [M 1].
- **A clue line** is a guess (L distinct digits from the same alphabet) and its feedback against the secret:
  **A** digits correct and in place, **B** digits correct but in the wrong place. The line reads as a sentence
  (`Text.codeLine`), never as coloured pegs:
  - (0,0) `Nothing is correct.`
  - (A,0) `One digit is correct and well placed.` / `Two digits are ...`
  - (0,B) `One digit is correct but wrongly placed.` / `Two digits are ...`
  - (A,B) `One digit is correct and well placed, one is correct but wrongly placed.`

  Every (A, B) the generator produced appears in [M 1]: `0/0 0/1 0/2 0/3 1/0 1/1 1/2 2/0` at L = 3, plus
  `0/4 1/3 2/1 2/2 3/0` at L = 4. `Text.spec` asserts a sentence for **every** (A, B) with A + B ≤ L except
  (L, 0), so a rare form can never render blank.
- **Generation** (`CodeLock.generate`):
  1. draw the secret;
  2. draw random guesses (never the secret), keeping a line only when it removes at least one candidate, until
     one code is left;
  3. **minimise**: in random order, drop each line if the code stays unique without it. Every surviving line
     is necessary;
  4. shuffle the board order;
  5. accept or regenerate (§3.4).

  Over 2000 sets per alphabet and 600 at L = 4: **0 failures and 0 unnecessary lines** [M 1]. The model's
  sanity part checks the rule against the classic published puzzle (`682 / 614 / 206 / 738 / 780 -> 042`): one
  solution, `042` [M 0].
- **Hidden lines.** A room with *f* feeders hides *f* lines, one per feeder. Because the set is minimal,
  **every hidden line is necessary**: the visible lines alone always leave two or more codes. Measured with
  one line hidden at L = 3, 0-9: **min 2, p50 4, max 252** codes still fit; with two hidden, p50 24 [M 1].
  The door cannot be read before its feeders are solved, even by perfect logic.
- **The gate.** The keypad takes **no code until every line is lit.** Guessing among the candidates the visible
  lines leave is therefore impossible, not merely costly.
- **Entry.** A keypad of the alphabet's digits plus ⌫ and ENTER. Digits outside the alphabet are hidden, and a
  digit already entered greys out, because every code has distinct digits. The honest HUD can therefore never
  send a malformed code (§12.4).
- **A wrong code** costs the submitter's **Clean** star (§4.3) and starts the station's lockout (§6.4). The
  in-world keypad shows the wrong code with ✗ while the lockout runs. That is the player's own guess, not the answer.
- **Hint** (`Digit 2 is 7.`): reveals one position the player has not been told. At most L − 1 per door, so the
  last digit is always the player's.

### 3.2 Flask Shelf (feeder)

- **N flasks** (3, 4 or 5) in N numbered slots, with a random N of five colours: **Red, Blue, Green, Yellow,
  Purple**. Each flask carries its letter (R B G Y P), so colour is never the only cue.
- **Clue sentences**, each true for the secret order (`Text.shelfClue`):

  | type | sentence |
  |---|---|
  | left | `Red stands somewhere left of Blue.` |
  | adj | `Red stands right next to Blue.` |
  | notadj | `Red does not stand next to Blue.` |
  | notslot | `Red is not in slot 2.` |
  | atend | `Red stands at one end.` |
  | notend | `Red is not at either end.` |

  "Red is in slot 2" does not exist: it is an answer, not a clue.
- **Generation** is the Code Lock's steps 1-3 over the N! orders. **0 failures and 0 unnecessary clues** in 3000
  sets per size [M 2]. Clues per shelf: **N = 3: 2-3; N = 4: 3-7 (p50 4); N = 5: 4-9 (p50 6)** [M 2].
- **The starting order** is random and never the answer. That tells a player one wrong order out of N! (1 of 6
  on a 3-flask shelf), which a first TEST would tell them anyway.
- **Play**: tap one flask, then another, and they swap. Then pull **TEST**. A wrong order costs the tester's Clean
  star and starts the lockout. No partial feedback is given: the clues hold all the information.
- **Hint** (`Green goes in slot 3.`): at most N − 2 per shelf.

### 3.3 Lamp Grid (feeder)

- An n × n grid (3 × 3 or 4 × 4). Tapping a lamp flips it and the lamps above, below, left and right of it.
  **Goal: every lamp lit.** No submission: the station is solved the moment the server's copy of the grid is all lit.
- **Generation**: from the lit grid, press a hidden set S of k distinct lamps. Keep S only if the **minimum**
  number of presses that solves the result is exactly k, so the difficulty knob is exact. That minimum is taken
  over S and every press set that changes nothing. The 3 × 3 grid has none besides pressing nothing, so its
  solution is unique; the 4 × 4 grid has 16 (a null space of dimension 4) [M 3]. Attempts needed: the first try
  for every k ≤ 4 on both sizes. At 4 × 4, k = 5 takes a mean of 1.19 attempts (max 5), k = 6 takes 2.73
  (max 16), and k = 7 takes 30.3 (max 279) [M 3]. **v1 uses k ≤ 5.**
- A grid is solvable by construction and never starts solved, because a set whose minimum is k ≥ 1 changes
  something.
- There is no wrong try, so a Lamp Grid can never cost the Clean star.
- **Hint**: highlights one lamp of a minimum solution **from the current grid**, so presses already made are
  accounted for. At most max(1, k − 1) per grid.

### 3.4 Acceptance rules (regenerate otherwise), measured

| rule | why | cost [M 1b / M 2b] |
|---|---|---|
| Door: at least one line visible at the start (m ≥ f + 1) | the door is a puzzle from the moment you walk in | 3 digits 0-9 with 2 feeders: 1.05 generations per door on average, max 4 |
| Door: at most 6 lines (`MaxDoorLines`) | the in-world board has six rows | 4 digits with 2 feeders: 1.01 generations, max 2. The raw generator made 7 lines in 2 of 600 [M 1]. |
| **Room 1** door: at most 3 lines (`FirstRoomMaxLines`) | a first door a new player can take in at a glance | 1.09 generations, max 3. Accepted sets: 2 lines 376, 3 lines 1124 of 1500 |
| Shelf: at most 7 clues (`MaxShelfClues`) | the overlay's list stays one short scroll | 5 flasks: 1.02 generations, max 3 |

Generation time per door in the luau CLI on this box, over two runs [M 1b]: **3 digits with 2 feeders: p90
1.03-1.16 ms, max 2.82-3.71 ms; 4 digits: p90 9.02-10.13 ms, max 16.66-19.40 ms.** Shelves take p90 under 0.2 ms,
and lamp grids under 0.02 ms [M 2, M 3]. The server generates during the 2.5 s lift ride (§6.2). Whether a 20 ms
step hitches a live server is §20 item 7.

### 3.5 Fairness invariants (each one a spec assertion, written before the code)

1. Code Lock: exactly one code fits all lines; every line is necessary; the visible lines alone fit two or more
   codes; a sentence exists for every (A, B).
2. Shelf: exactly one order fits; every clue is necessary; the start order is not the answer.
3. Lamp Grid: the grid is not all lit at the start; the minimum number of presses is exactly k.
4. **Solvable from what the player sees.** The headless walk (§18.3) solves every station **from the rendered
   text and lamp states only**, through the pure solvers, the way a player would. No server-side answer mirror
   exists for it to cheat with (§12.2). This is lost-found-depot's argument, and it proves the visible
   information is sufficient, which an answer table never could.

---

## 4. The Lab

### 4.1 Rooms and wings (`Config.Lab.Wings`)

Five wings of three rooms: 15 rooms, then the Roof. Feeders are named A and B on their station signs.

| wing | door code | feeders per room | room 1 | room 2 | room 3 |
|---|---|---|---|---|---|
| 1 Reception | 3 digits from 1-6 | 1 | Lamp 3×3, k 2 | Shelf 3 | Lamp 3×3, k 3 |
| 2 Archive | 3 digits from 0-9 | 1 | Shelf 4 | Lamp 3×3, k 4 | Shelf 4 |
| 3 Greenhouse | 3 digits from 0-9 | 2 | Lamp 3×3 k 4 + Shelf 4 | Shelf 4 + Lamp 4×4 k 3 | Lamp 4×4 k 4 + Shelf 4 |
| 4 Cold Storage | 3 digits from 0-9 | 2 | Shelf 4 + Lamp 4×4 k 4 | Lamp 4×4 k 4 + Shelf 4 | Shelf 4 + Lamp 4×4 k 5 |
| 5 Reactor | 4 digits from 0-9 | 2 | Lamp 4×4 k 5 + Shelf 5 | Shelf 5 + Lamp 4×4 k 5 | Lamp 4×4 k 5 + Shelf 5 |

Door clue lines in accepted sets [M 1b]: room 1: 2-3; the rest of Reception: 2-4; Archive: 2-6;
Greenhouse and Cold Storage: 3-6; Reactor: 3-6. Of these, *f* start dark.

**Why this table and not the first draft** [M 5b], in minutes to the Roof, p50 [p10-p90] for the normal profile:

| table | what changed | normal | careful | first-timer |
|---|---|---|---|---|
| V1 | 4-digit doors in Cold Storage and the Reactor, a 3-feeder finale | 44.2 [42.0-46.4] | 32.6 | 59.7 |
| V2 | 3-digit doors through Cold Storage, no 3-feeder room | 42.0 [40.0-43.9] | 31.0 | 56.6 |
| V3 | V2 with one feeder in the Archive | 40.6 [38.8-42.7] | 30.1 | 54.9 |
| **V4 (this table)** | V3 with 5-flask shelves only in the Reactor | **39.4 [37.6-41.3]** | 29.2 | 53.0 |

V1 put the normal player's p90 past the owner's 45-minute window. V4 puts the p50 within 2 minutes of the
window's centre (37.5), and the p90 inside the window. The difficulty still peaks in the last wing: the only
4-digit doors and the only 5-flask shelves are in the Reactor.

### 4.2 Continue: which room the lift takes you to

- **Frontier** = the first room you have never escaped (1-15), or 16 once you have escaped all 15. It is derived
  from the stars, never stored (§12.1).
- **Continue** (solo): your frontier while it is 15 or below. After the Roof it is the lowest room with fewer
  than 3 stars. With all 45 stars it is the room after the one you played last, wrapping from 15 to 1.
- **Continue** (pair): the lower of the two players' Continue rooms. Rooms unlock in order, so that room is
  unlocked for both.
- **A replay generates a new room** for the same slot: same wing, same kinds and sizes, new puzzles. The Room
  Directory (pick any room) is cut from v1 (§21). Continue already walks you to exactly the rooms missing stars.

### 4.3 Stars (`Config.Stars`), per player, per room

| star | earned when the door opens, if | why |
|---|---|---|
| ★ Escaped | you escaped this room, **and in a pair you completed at least one of its stations yourself** | a partner cannot carry you to stars (the hands-on rule). Escaping still advances your frontier, so a carried friend still gets to see the Roof. |
| ★ Clean | **you** made no wrong submission in this room | per player, so a partner's wrong tries never cost your star |
| ★ Unaided | **you** took no hint in this room | a hint is shown only to the player who took it (§12.4), so a partner's hint does not spoil your star |

"Completed a station" means the server accepted the solve from your action: the press that lit the last lamp,
the TEST that matched, or the ENTER that opened the door. Best per room is kept, and a replay can only raise it.
Maximum 3 × 15 = **45**.

[review-1 2026-10-01, `REVIEW-1.md` A4: in a pair, **Clean and Unaided are the pair's**, not each player's. Per-player
marks let one partner take every hint and every wrong try and tell the other the code: the other made ONE Act
call per room and got 3 stars (9 in 3 rooms, measured). Now a wrong try or a hint marks everyone in the room, and
the mark stays with whoever carries on if the other leaves; the hint's text still goes to its taker only. The
cost: a partner can now cost you those two stars in that room (not Escaped), and a replay restores them. A
partner who plays perfectly can still hand you the code: you then get what the pair earned, 3 stars.]

### 4.4 The pair

- **The Pair Lift** (Atrium) has two pads and a GO prompt. It departs when two players stand on the pads and
  **both** pressed GO within 10 s, after a 3 s countdown. Stepping off cancels it with a toast. A third player is
  told "The Pair Lift is full."
  [review-1 A1, B2: the partner is a player on the OTHER pad who pressed GO inside the window; anyone who merely
  stands on a pad is ignored (one idle player on either pad used to answer every GO with "full", switching the
  only way to play together off for the server). A second player on the same pad is told
  `One player per pad: step onto the other pad and press GO.` "Full" is for a third player during a countdown.
  At departure, after the ride, only those still inside the Pair Lift go; one who walked away stays in the
  Atrium, told `You stepped out of the lift before it left. Step back in to ride.`, and the other rides solo.]
- Any two players can ride it. A friends-only gate is unnecessary for safety, because every star is per player
  and the hands-on rule stops carrying. [review-1: Clean and Unaided are now the pair's (§4.3), so a random partner
  can cost you those two stars in one room; leaving is one prompt and a replay restores them.] It would also be untestable headless, since the emulator's
  `IsFriendsWith` always returns false and methods cannot be overridden (`robloxemu/emu/instance.luau`).
  Private servers remain the friends-only option.
- Both players see and act on the same room. Lamp presses, flask swaps and the door keypad are shared state,
  and a lockout belongs to the station, not the player, so two players cannot double the brute-force rate.
- **Leaving** is always one prompt away (ATRIUM ⌂ in either cab). If one of the pair leaves, the other continues
  the same room solo, and from then on the hands-on rule no longer applies to them.
- **The exit lift's NEXT** departs only with every remaining member inside it: "Waiting for <name>."

---

## 5. The world

All positions are in studs. Up is +Y and every floor top is at y = 0 unless stated.

| place | where | contents |
|---|---|---|
| **Atrium** (hub) | origin, interior x −32..32, z −24..24, 20 tall | `AtriumSpawn` at (0, 0.5, 14), 6×1×6, facing −Z. The **Solo Lift** cab (8 × 8 interior) is centred at (−7, 0, −3), its doorway on the +Z side. The **Pair Lift** cab (12 × 8, two pads) is centred at (8, 0, −3). The **Star Board** (10 × 7) stands at (16, 6, 12), facing the spawn. The **Roof Access** door is on the north wall at (0, 0, −24), signed "ROOF — for Lab escapees". A wing directory sign is on the west wall. |
| **Zone i** (i = 1..Z) | origin (300·i, 0, 0) | one room at a time. **Room interior** x −16..16, z −16..16, 16 tall. **Entry cab** (8 × 8) south, through a 6 × 8 doorway in the south wall. **Exit door** (6 × 8) centred in the north wall, carrying the door station's prompt at (0, 4, −15.5); then a short corridor, then the **exit cab** (8 × 8). The door board (12 × 7) hangs left of the door at (−10, 8, −15.5), clear of the doorway (x −3..3); the keypad hangs right of it at (7, 5, −15.5). Feeder A is on the west wall at (−15.5, 6.5, 0), feeder B on the east wall at (15.5, 6.5, 0). An `AtriumArrival` plain Part in front of the Atrium lifts is where ATRIUM ⌂ returns you. |
| **Roof** | deck top at (0, 150, 0), 48 × 48 with a railing | the observatory dome and telescope, an arrival pad, and a "Back down" prompt. |

Distances that matter, all [R]:
- spawn to the Solo Lift doorway (−7, 1): **14.8 studs = 0.9 s** at 16 studs/s;
- spawn to the Star Board: 16 studs = 1.0 s;
- entry doorway (0, 16) to feeder A's stand point (−12, 0): 20 studs = 1.25 s;
- feeder A's prompt to the door's prompt: 21.9 studs ((−15.5, 0) to (0, −15.5)), and the same from feeder B;
- feeder A to feeder B: 31 studs;
- every station prompt is at least 21.9 studs from every other, more than twice the 8-stud prompt reach, so only
  one station's prompt shows at a time.

---

## 6. Every number

### 6.1 World and server (`Config.World`)

| name | value | reason |
|---|---|---|
| `WalkSpeed` | 16 | Read off a live Humanoid in Studio [S `fork-tower/STUDIO.md` §5]. The server assigns it on every character, so no test ever runs at a speed nobody configured. |
| `MaxPlayers` | 8 | Zones and the DataStore budget (§12.5) are worked at 8. A puzzle game has no crowd mechanic to feed. |
| `Zones` | `max(8, Players.MaxPlayers)` | A floor, not a cap, so a Studio slider can never seat more players than zones [S `facility-nightmare/DESIGN.md` §5.5, from fork-tower REVIEW-3]. A pair uses one zone, so zones never run out. Indices are recycled on leave (checklist: unbounded coordinates). |
| `ZoneSpacing` | 300 | A zone reaches its footprint's half-width, 17 (z extends to 26 but zones are spaced along x), plus the longest light range, 26: 43 [R]. Two zones need 86, so 300 leaves 214. The Atrium, lit with the same 26-stud range, reaches 32 + 26 = 58, well short of zone 1's near edge at 283 [R]. |
| `RoomSize` | 32 × 32 interior, 16 tall | Height: the hazard lane needs 12 studs above a root that is 3 studs over the floor. It starts at y 14.95, 1.05 under the ceiling [P]. Width: station prompts 21.9+ studs apart (§5), and a 7-stud ring always leaves floor to step out onto [P]. |
| Doorway | 6 wide × 8 tall | A 4-stud hull plus 1 each side, from facility-nightmare's unmeasured model [STUDIO]. |
| Room lights | 2 ceiling fixtures at (0, 15, ±8), `Range` 26 | The farthest floor corner of each half is √(16² + 15² + 8²) = 23.3 studs from its fixture [R]. Brightness [STUDIO]. At most 3 PointLights per room: two fixtures plus the door's lock glow. |
| Parts per room (server) | ≤ 160, asserted headless | Counted: shell and doorways 10, two cabs 14, door leaf and board and keypad and lock lamps 6, a 4×4 grid 17, a 5-flask shelf 16, wing props ≤ 30, fixtures 2: **95** [R]. The cap leaves 65 of margin for the builder. |
| `StreamingEnabled` | false | The server moves characters 300+ studs. With streaming on, the destination might not have streamed in yet [DOC]. 8 × 160 room parts plus the Atrium and Roof need no streaming [R]. |
| `Players.RespawnTime` | 3 | Only a reset respawns (§13) [DOC: the default is 5]. |
| `Players.CharacterAutoLoads` | true | The engine spawns; the game never calls `LoadCharacter`. |

### 6.2 Lifts (`Config.Lift`)

| name | value | reason |
|---|---|---|
| `BoardSeconds` | 1.0 | Standing in the Solo Lift's dead-end cab for 1 s starts the ride. That keeps the first station about 5.7 s from spawn (§16) and still ignores a player who walks in and straight out. |
| `RideSeconds` | 2.5 | The server generates (under 20 ms per 4-digit door [M 1b]) and builds (≤ 160 parts) during it. It is also a breather between rooms. The model charges 3.5 s per room for board plus ride [M 5]. Feel [STUDIO]. |
| `PairGoWindowSeconds` | 10 | Time for the second player to press GO after the first [A]. |
| `PairCountdownSeconds` | 3 | Time to step off after a mistaken GO [A]. |
| `ArrivalGraceSeconds` | 8 | No hazard in a room's first 8 s. That time belongs to the room card (3 s read [A]) and the 1.25 s walk to the first station, with room to spare [R]. |

### 6.3 Puzzles (`Config.Puzzles`)

| name | value | reason |
|---|---|---|
| the wing table | §4.1 | [M 5b] |
| `MaxDoorLines` / `FirstRoomMaxLines` / `MaxShelfClues` | 6 / 3 / 7 | §3.4 [M 1b, M 2b] |
| Door alphabet, Reception | `1-6` | 120 codes need a minimal set of 2-5 lines, p50 3, against 2-6, p50 4, for `0-9` [M 1]. A shorter first door, and at most 3 lines in room 1. |
| Lamp `k` | ≤ 5 | Generated first try for k ≤ 4, 1.19 attempts on average at k = 5 on 4 × 4; k = 7 needs up to 279 attempts [M 3]. |
| Flask colours | Red, Blue, Green, Yellow, Purple, each with its letter | Five names a young reader knows. The letter carries the meaning for colour-blind players [STUDIO for legibility]. |

### 6.4 Stars, hints, wrong tries, actions (`Config.Stars`, `Config.Hints`, `Config.Act`)

| name | value | reason |
|---|---|---|
| `Lockout` | 3, 6, 12, then 20 s per consecutive wrong submission on a station; reset when the station is solved | Trying every answer costs [M 4]: a 3-digit 0-9 door 2.40 h, a 4-digit door 17.7 h, a 5-flask shelf 22.1 min, a 4-flask shelf 3.7 min. A whole room takes the normal profile 1.3 min in Reception to 4.1 min in the Reactor (band minutes / 3, [M 5]). An honest normal player's first wrong try costs 3 s. The two cheap cases are both in Reception: a 1-6 door takes 23.3 min but is gated behind its feeder anyway, and a 3-flask shelf takes 28 s, about what logic takes. Brute force there costs the Clean star, which is the lesson. |
| lockout scope | per **station**, shared by a pair | Two players cannot double the trial rate. |
| `HintCooldownSeconds` | 20 per player | Spaces hints so each is read before the next [A]. It limits nothing the board measures: Unaided is gone at the first hint. |
| hint caps | door L − 1, shelf N − 2, lamp max(1, k − 1) | A hint never finishes a station; the last step is the player's [R]. |
| `ActRatePerSecond` | 10, bucket of 10 | The largest grid in v1 needs 5 presses [M 3]; a person taps under 10/s [A]. Excess is dropped with one toast per 5 s. |
| `PromptDistance` | 8 | With station prompts 21.9+ studs apart, one prompt shows at a time [R]. |
| `StationReach` | 12 | Prompt reach 8 plus 4: a stride of latency at 16 studs/s is 0.25 s = 4 studs [R]. Checked by the server against its own view of the root part. |

### 6.5 Save and board (`Config.Save`, `Config.Board`)

| name | value | reason |
|---|---|---|
| `Store` / `BoardStore` | `EscapeRoomLab_v1` / `EscapeRoomLab_Stars_v1` (ordered) | The standard's key `u_<userId>` in both. |
| `AutosaveSeconds` | 20 | The sibling convention (anomaly-observatory `src/shared/Config.luau`, `Config.Save`, lines 119-120). It renews the session lock. |
| `SessionLockSeconds` | 45 | Longer than two autosaves, so one failed autosave does not drop the lock (same file). |
| `SaveCoalesceSeconds` | 6 | Roblox allows one write per key every 6 s [DOC]. An escape saves at once unless a write for that key went out less than 6 s ago, in which case it is queued. |
| `PublicRows` / `PublicCacheSeconds` | 10 / 60 | The standard: `GetSortedAsync(false, 10)`, cached about 60 s. |
| `FriendCap` | 200 | The standard's example. At most 200 reads per friends list; §11.4 paces them. |
| `FriendScoreCacheSeconds` / `FriendListCacheSeconds` | 300 / 600 | A friend's stars change at most once per room (about 2.6 min for a normal player [M 5]); lists change rarely [A]. |
| `GetAsyncReserve` | 10 | Friend reads never spend the last 10 of the server's GetAsync budget [DOC: 60 + 10 × players per minute], so profile loads always have room. |
| `NameCacheSeconds` | 3600 | Names change rarely; they are looked up, never stored (the standard). |

---

## 7. Environment bands

### 7.1 What drives them: the game's own progress

The **progress value** is the room you are in and how much of it you have solved:

```
p = (wing - 1) + (room - 1 + solved / stations) / 3
```

`wing` is 1-5, `room` is 1-3, `solved` counts the stations solved in this room, and `stations` = feeders + 1
(the door). So p climbs as you solve. It is 0 in the Atrium and 5 on the Roof. Entering a room sets it to that
room's start, and the door opening sets it to the room's end. It is **never time.** The client reads it from
the `RoomState` payload (§12.4), which holds only public counts.

Bands start at p = 0, 1, 2, 3, 4, 5. Every band after the first fades in over **1/3 before its `from`**. That is
exactly the last room of the previous wing: `p` runs from w − 1/3 to w in room 3 of wing w, as its stations are
solved. **The next wing seeps into the last room of each wing**, and is fully there when that room's door opens.
`EnvBands.validate` accepts it (fade 1/3 ≤ 1, the gap to the previous band). The band's **name** (HUD chip,
title card, which hazard flies) follows the room's integer wing, while every **blend** follows p. This is
+1 Jump's rule for keeping the HUD and the sky in agreement (plus1-jump `EYECANDY.md` §10).

`src/shared/EnvBands.luau` is byte-identical to the template (md5 `c6fc63a1…`), and so is its spec
(`tests/EnvBands.spec.luau`, md5 `e2a9d464…`). A lift ride makes p jump. Every written value glides with
`EnvBands.approachTable` at a 0.6 s half-life (+1 Jump's number). Lighting is written at most 10 times a
second, and only when a value changed.

### 7.2 The six bands

Every band defines the same lighting fields, enforced by `EnvConfig.spec` as in +1 Jump. Band 1's lighting
equals the new server preset `Fx.Presets.Lab`, so the client takes over from the server with no jump. Exposure,
ambient and bloom values are [STUDIO]. The server builds each room's shell and props in its wing's materials.
The client adds the decor, creatures, weather and lighting, and fades them with the band weights.

| # | band (from, fade) | light and colour | scenery (server props + client decor) | creatures | weather | hazard |
|---|---|---|---|---|---|---|
| 1 | **Reception** (0, 0) | warm late afternoon through window blinds; cream walls, teal carpet | desk, ferns, water cooler, wall clock + sun shafts through the blinds | 2 houseflies looping by the windows | dust motes in the shafts, 4/s | none (the onboarding wing) |
| 2 | **Archive** (1, 1/3) | amber lamplight, sepia grade, low exposure | filing shelves, a rolling ladder, box stacks, green banker's lamps + cobwebs and dust cloths on the ceiling | 4 moths circling the lamps | dust and drifting paper scraps, 6/s | spider on a thread |
| 3 | **Greenhouse** (2, 1/3) | bright humid green under a glass ceiling, strong bloom | palms, planters, misting pipes + vines hanging from the ceiling | 5 butterflies | mist 8/s and drips | seed pod on a vine |
| 4 | **Cold Storage** (3, 1/3) | cold blue-white, high contrast, low saturation | freezer racks, frozen crates + icicles along the ceiling edges, frost on the upper walls | 3 maintenance drones with blinking lights | snow flurries from ceiling vents, 20/s | ice drone |
| 5 | **Reactor** (4, 1/3) | dark, teal and violet neon, strongest bloom | a glass-walled core cylinder, pipes, hazard stripes + pulsing ceiling pipes | 4 spark-bugs (tiny glowing drones) | steam wisps 6/s and sparks 4/s | crane claw |
| 6 | **Roof** (5, 1/3) | night, 3000 stars, moon, deep blue grade | the observatory dome and telescope (server) + a city skyline of lit windows 250-500 studs out (client) | 3 bats, a rare shooting star | a light wind of leaves, 4/s | none (the brag is peaceful) |

Rules the build asserts:
- **Decor keeps off the play space.** Client decor lives on the ceiling or flush on the walls above 9 studs, never
  in front of a station's face (the face plus 3 studs), never in a doorway. Creatures fly between y = 8 and 14,
  above head height and under the ceiling. Everything local is `CanCollide`, `CanQuery` and `CanTouch` false.
  Checked on every frame in `check_escaperoomlab_env` (§18.3).
- **Indoor creatures follow bounded paths**, not +1 Jump's open-sky spawn ring. `EnvBands.ambientSpawn` places
  life 70-900 studs out, and a room is 32 studs across. This is an adaptation, and it lives in the game's own
  `Decor.luau`, not in the template: `Decor.critterPos(kind, i, t, room)` computes loops and figure-eights, and
  `Decor.spec` asserts every sampled position stays inside the room's upper volume.
- **Budgets, capped in code** (`Config.Budget`): at most 120 local parts; 3 emitters on (2 weather, via
  `EnvBands.capRates` with `MaxWeatherEmitters = 2` and `MaxEmitterRate = 60` per second, plus 1 hazard); 4
  beams; 2 trails; 2 local lights. Measured at the middle of every band and at every fade window. These are part
  counts, not frame time: frame time on a phone is §20 item 12.
- **A title card** ("WING 2 · THE ARCHIVE") plays once per new highest band. `EnvBands.newAnnouncer` is seeded
  from the loaded profile's frontier, and waits for the profile to have LOADED, per +1 Jump's slow-load finding.

---

## 8. Hazards

### 8.1 The template, verbatim, and the one adaptation

`src/shared/Hazards.luau` is **byte-identical** to `plus1-jump/src/shared/Hazards.luau` (md5 `c2775461…`), and so
is its spec, `tests/Hazards.spec.luau` (md5 `2f42278c…`). The template's scheduler, ring rule, swept hit test and
knock are all used unchanged.

**The adaptation lives in the config and the glue, not the code.** Indoors, a lane cannot start on screen at a
distance: at a station the camera looks at a wall a few studs away. So every kind has `pitch = 85` (the
template's `MAX_ELEVATION`) and `pitchSpread = 0`, and the glue passes `ctx.pitch = math.rad(85)` to
`Hazards.step`. With the view window centred on 85°, the template plans a **near-vertical lane from the ceiling
straight down onto the player**. Run verbatim against this config [P]:

| measurement [P] | result |
|---|---|
| `Hazards.validate` / `Rest.validate` | both true |
| lane start over 2000 plans (root at y 3, ceiling at y 16) | y **14.954** every time; at most **1.046** studs sideways of the target |
| the ring (hit radius 2.0 + player radius 1.5) | **7.00** studs wide |
| stand still, 36 directions | **36 of 36 hit** |
| walk 3.9 studs out once the lane locks, 36 directions, jitter included | **0 of 36 hit** |
| 20 h of exposed time | 482 hazards = **one per 149.4 s** (+1 Jump's own spec: one per 150.9 s over 20 h) |
| [review-1] step out 3.9 studs at any time 0.0-1.8 s after the ring shows, 36 directions | **0 of 684 hit**; the ring never moves (it moved up to 3.9 studs while the lane tracked); a player who stands still is hit at 2.133 s |
| [review-1] 20 h of exposed time at 80-120 s | 714 hazards = **one per 100.8 s** |
| knock on a player 0.5 studs off-centre | (19.4, 0.0, −4.8) studs/s: **20 sideways, no lift** |

What this gives up, said plainly: the template guarantees a lane **starts** on screen. Here it starts above the
player, usually out of frame. The **telegraph is therefore the ring, the banner and the sound**, as in
facility-nightmare's first-person rooms: a red ring at your feet, a HUD banner
`⚠ SPIDER — STEP OUT OF THE RING` that turns green (`CLEAR`) once you are out, a creak, and the thing entering the
frame as it lowers. Whether that reads in time on a phone is §20 item 4.

### 8.2 Rules

- **Rarity.** One per **120-180 s of exposed time**, never two at once. Exposed means inside a room's play area,
  in a band that has a hazard, not resting, and past the room's 8-s arrival grace. Reception has no hazard: a due
  hazard there is re-rolled, the template's quiet-band rule, so entering the Archive never releases a backlog. In
  the Atrium, the cabs and on the Roof, the glue passes `ctx.resting = true`, so the clock **freezes** and is
  never reset. During the arrival grace and away from a legal spot, it passes `ctx.grounded = false`: a due
  hazard **waits** for a legal spot, and exactly one comes.
  [review-1 B4: no longer. A hazard that came due at the door station (never a legal spot) was HELD through the
  door, the corridor and the ride and fired the instant the next room's grace ended: 15 of 40 hazards came
  exactly 8.0 s after arrival in four full runs. The glue now passes `resting = true` wherever no hazard may be
  released (outside the interior, off a legal spot, inside the grace), so the clock is frozen there and nothing
  backs up: in eight full runs after the fix, none of 77 hazards came at the end of the grace; the earliest came 9 s after arrival.
  Exposed time is therefore a legal spot past the grace, and the interval is set on it (below).]
- **Legal spot**: the root is inside the room's interior shrunk by 1 stud, and at least 5 studs from both
  doorways, so a knock never pushes anyone into a cab.
- **One kind per hazard band**, all with the same numbers. Only the look differs:

  | `Config.Hazards` | value | reason |
  |---|---|---|
  | `IntervalMin` / `IntervalMax` | 120 / 180 | Verbatim. One per 149.4 s [P] = about one near-miss per 2.5 exposed minutes, the standard's "one per 2-3 minutes". |
  | [review-1] `IntervalMin` / `IntervalMax` | **80 / 120** | With the door and the grace no longer exposed, 120-180 gave 6-7 hazards per run to the Roof (median gaps 241-302 s of play, four full runs). 80-120 gives 9-11 (eight full runs, median gaps 170-206 s): about the standard's one per 2-3 minutes of PLAY, as the reviewed build had. One per 100.8 s of exposed time [P]; the pacing model counts 10.2 for a normal player. |
  | `speed`, `telegraph`, `commit`, `pass` | 4 studs/s, 3.0 s, 1.5 s, 0.6 s | speed × telegraph = 12 studs puts the lane's start 1.05 studs under the 16-stud ceiling, room for a 2-stud model [P]. One more stud would put the model into the ceiling [R]. The lane passes 2.4 studs below the root before it ends, 0.6 studs above the floor [R]. |
  | `hitRadius`, `PlayerRadius` | 2.0, 1.5 | A 7-stud ring. Leaving it takes a 3.9-stud walk = 0.24 s at 16 studs/s, inside the 1.5 s after the lock [R, P]. |
  | [review-1] `commit` | **3.0** (= telegraph) | B1: the lane LOCKS on its first frame. With commit 1.5 the ring followed the player for 1.5 s, and a 4 studs/s drop touches the 3.5-stud zone 0.875 s before arrival, at 2.13 s: stepping out dodged only 1.45-2.05 s after the ring showed (108 of 108 hit up to 1.40 s; through the real client a step 1.0 s after the ring was hit 5 of 5). The row above was wrong: the "1.5 s after the lock" ended 0.875 s early. Now the ring stands where the player stood when it appeared, and stepping out at any time up to 1.8 s dodges (0 of 684); the hit lands at 2.13 s. Config only; `Hazards.luau` stays verbatim. |
  | `knock`, `KnockLift`, `KnockSeconds` | 20, 0, 0.6 | A stumble, not a launch, in a walled room [P]. 0.6 s of PlatformStand [STUDIO]. |
  | `MinTelegraphSeconds`, `MinCommitSeconds`, `MaxRetargetSpeed` | 3, 1.5, 1.5 | Verbatim from +1 Jump. |
  | `AimJitter`, `SpreadDegrees`, `ViewPitchDegrees`, `KindFitDegrees` | 0.8, 0, 20, 25 | At 85° the heading spread does nothing, and jitter stays well inside the 3.5-stud ring radius. The last two are the template's values, and the view window is centred on the 85° the glue passes. |

  | band | kind | the look |
  |---|---|---|
  | Archive | spider | a black spider lowering on a silk thread from a ceiling crack |
  | Greenhouse | seed pod | a heavy pod lowering on its vine |
  | Cold Storage | ice drone | a small drone hovering down, frost trailing |
  | Reactor | crane claw | a claw lowering on its cable, sparking |

- **While a station overlay is open** (§17.2) and a hazard spawns, the overlay **collapses** to its title bar, so
  the ring and the banner are visible. It **reopens** when the hazard is done, if the player is still within
  reach of the station.
- **A hit**: 20 studs/s sideways, no lift, 0.6 s of PlatformStand, a camera shake and a white flash. **Nothing is
  lost**: no star, no station progress. The server never hears of it.
- **Hazards are client-side**, as in +1 Jump (`EYECANDY.md` §5). They harm only the local player, whose
  character physics that client owns. A pair gets one hazard stream per client, so your partner sees you
  stumble with nothing hitting you (§20 item 10).

### 8.3 How often a player meets one [M 5]

The normal profile meets **13.7 hazards** (p10 13.0, p90 14.5) on the way to the Roof. The first hazard band
starts at minute **3.9** (p50), and the first hazard comes 2-3 exposed minutes after that. A careful player
meets 10.0, a first-timer 18.5.

---

## 9. Rest: the Break button

`src/shared/Rest.luau` is **byte-identical** to the template (md5 `19226cb6…`), with its spec
(`tests/Rest.spec.luau`, md5 `4c38d41f…`).

| `Config.Rest` | value | reason |
|---|---|---|
| `WakeOnMove`, `BlockWhileThreat` | true | Required by `Rest.validate`. |
| `RequireGrounded` | true | As in +1 Jump: a Break never starts mid-air. |
| `WakeGraceSeconds` | 0.4 | Verbatim. |
| `PendingSeconds` | 6 | The longest hazard flight is telegraph + pass = 3.6 s, plus the template's 2.4 s to stand still: 6.0 [R]. |
| `IdleSeconds` | **0** (idle rest off) | **An adaptation, and why:** standing still is how a puzzle is thought through. The template's 20-s idle rest would switch hazards off at every station, so they would only ever meet players who were walking. In +1 Jump, idle rest spared an AFK climber from losing height to a knock. Here a knock costs a 0.6 s stumble, so an AFK player loses nothing. `Rest.validate` accepts 0 [P]. |

- **☕ Break** (top right, at least 44 screen px): your avatar sits, the screen dims a little, and the chip reads
  `☕ Break — the Lab leaves you alone. Move to carry on.` Press it again, or move, to carry on.
- **One game rule on top of the template:** opening a station ends the Break (`Rest.stop`), and pressing Break
  closes the open overlay. A Break is a pause from the room, never a hazard-free way to solve it.

**Why it can never be an exploit:**
1. **Nothing runs on time.** Rooms have no clock, stars have no time component, and nothing accrues while you
   stand, sit or idle.
2. **Nothing can be solved while resting**, because opening a station ends the rest.
3. **It is not a panic button.** A Break cannot start with a hazard inbound (`BlockWhileThreat`). The request is
   queued, the hazard still arrives, and stepping out of the ring keeps the request (the template's
   review-finding-6 behaviour).
4. **Toggling does not thin hazards.** The clock freezes and never resets. +1 Jump's spec measured this, and the
   same spec file ships here verbatim.

---

## 10. The brag moment and the long-term goal

### 10.1 The pacing model [M 5], and what it assumes

`design/model.luau` Part 5 walks 1500 simulated players per profile through the V4 table, using doors and
shelves drawn from the accepted pools of [M 1b / M 2b]. The **human** numbers are all [A]:

| profile | door, per clue line: read + think (think × 1.5 at 4 digits) | shelf, per clue: read + think (think × 1.3 per flask over 3) | lamp: think per press (× 1.25 on 4×4) / presses made per press needed | wrong first try: door 3 / door 4 / shelf | takes a hint: door 3 / door 4 / shelf / lamp |
|---|---|---|---|---|---|
| careful | 3 + 8 s | 3 + 5 s | 3 s / 1.2 | 0.03 / 0.04 / 0.03 | 0 / 0 / 0 / 0 |
| normal | 4 + 11 s | 4 + 7 s | 5 s / 1.8 | 0.15 / 0.25 / 0.12 | 0.08 / 0.15 / 0.08 / 0.10 |
| first-timer | 5 + 16 s | 5 + 10 s | 8 s / 2.5 | 0.28 / 0.40 / 0.22 | 0.20 / 0.35 / 0.20 / 0.25 |

Plus, per room: a tap 0.6 s, a digit 1.2 s, a hint saving 40% of the remaining think time, a wrong try costing
its lockout and 30% of the think time again, and a repeat wrong try at half the first chance. Walking is from §5,
the room card takes 3 s, lift and board 3.5 s, and a dodge 2.5 s per hazard. All of these are [A], except the
walking [R] and the lift times, which are §6.2.

### 10.2 Results

| | careful | **normal** | first-timer |
|---|---|---|---|
| minutes to **the Roof** (the brag) | 29.2 [28.2-30.2] | **39.3 [37.6-41.5]**, max 44.6 | 53.1 [50.0-56.5] |
| stars after the first pass | 44 | 38 [35-41] | 31 |
| minutes to **45 stars** (the long-term goal) | 30.5 | **69.8 [54.7-91.0]** | 205.1 [143.6-290.5] |
| minutes per band: Reception / Archive / Greenhouse / Cold Storage / Reactor | 3.0 / 4.7 / 6.1 / 6.3 / 9.0 | 3.9 / 6.2 / 8.2 / 8.6 / 12.3 | 5.2 / 8.3 / 11.1 / 11.6 / 16.7 |

The owner's window is 30-45 minutes for a normal player, and the model puts the normal p50 at 39.3 and p90 at
41.5. Every band's p50 is at least 3.0 minutes for every profile, and no simulated player spent under 2.5
minutes in any band [M 5]. The build ports Part 5 into `tests/Pacing.spec.luau` (with `tests/LabModel.luau`)
and asserts that the normal p50 is within 5 minutes of 37.5, that the normal p90 is at most 45, and that every
band lasts at least 2 minutes, so a retune that drifts fails loudly. **When real session data exists, retune the
profiles first, then the wing table.**

[review-1 2026-10-01: the model now counts only feeder time past the grace as exposed (B4) and the interval is
80-120 s. `Pacing.spec`: normal Roof p50 **39.1** [p10 37.3, p90 41.2], 45 stars p50 **69.5**; careful 29.0;
first-timer 52.8; hazards on a normal player's way to the Roof p50 **10.2** (eight full headless paths: 9-11).]

### 10.3 The brag: the Roof

When the door of room 15 opens for the first time, the exit lift goes **up**. Its doors open onto the Roof at
night: stars, a moon, the city lit below and the telescope dome. The screen shows `YOU ESCAPED THE LAB`, with a
white flash, an FOV punch (`FxClient`) and three fireworks bursts on the client. Every player in the server gets
the notice **"<name> escaped the Lab!"** The profile stores `escapedAt`. From then on, the Atrium's Roof Access door
takes you up any time, to show a friend. Before that it says **"Roof access is for Lab escapees. You are at room
N of 15."** A signpost from the first minute is also a goal.

### 10.4 The long-term goal: 45 stars

After the Roof, Continue walks you through every room still missing a star (§4.2). **Normal: 69.8 minutes** in
total to all 45 [M 5]. A careful player reaches 45 almost with the Roof (30.5 minutes), so for them the long-term
goal in v1 is only the board. Night Shift, a harder second pass, is the planned answer (§21).

---

## 11. The Star Board

### 11.1 The metric: total stars, 0-45

Stored in the OrderedDataStore `EscapeRoomLab_Stars_v1`, key `u_<userId>`:

```
value = stars * 2e9 + (2e9 - reachedAtUnix)
```

`reachedAtUnix` is the server's `os.time()` at the door verdict that **first** brought the total to its current
value. [M 6]: the largest value is 90 209 273 600, under 2^53, and an integer. A higher star count always ranks
higher as long as two reach times are less than 2e9 s apart. Every stored time is after 2026-09-30
(1 790 726 400), so that holds until 2090. At equal stars, the earlier reach ranks higher.

It is written **only when the total improves**, via an `UpdateAsync` whose transform keeps `max(old, new)`. A late
or stale write can therefore never lower a rank. The board write happens only after the profile write carrying
the new total has landed, so the board never shows more than the saved profile does. `boarded` in the profile
remembers the last total written, and a failed board write is retried on the next autosave.

### 11.2 Why a script cannot inflate it

1. **Server-measured.** Stars come only from the server's own verdicts: the door code it accepted, the wrong
   submissions it rejected, the hints it granted. No remote carries a star, a result, a time or a room to credit.
2. **Bounded.** 3 per room, best only, 15 rooms: 45. A replay can raise a room's best but never add to it.
3. **What a script can do is the rules.** The clues are public, so a solver script plays perfectly. That is the
   ceiling a careful human also reaches: 44 stars after the first pass, 45 about one replay later [M 5]. A script
   can reach 45 sooner, but it cannot go higher, and the tie-break puts it **behind every player who reached 45
   before it**.
4. **Time never enters the metric.** Every speed board in this repo is winnable by a bot. Lost-found-depot
   measured a travel-limited bot clearing a shift in 9.8 s against an expert's 86.0 s
   [S `lost-found-depot/DESIGN.md` §10.3]. Stars are what a careful human and a perfect bot share.
5. **Carrying is closed.** The hands-on rule (§4.3) means a pair room pays stars only to a player who completed
   one of its stations. [review-1 A4: it was not. The hands-on rule asked for ONE action, so a partner could
   absorb every hint and wrong try and hand over the code: 3 stars for one Act call per room, measured. Clean and
   Unaided are now the pair's (§4.3): the same play pays the boosted account 1 star per room.]
6. **Guessing is closed.** The keypad is dark until every line is lit, and brute force is priced by the lockout
   [M 4]. Both kinds of wrong try cost the Clean star.

**The residual, stated:** until ten real players reach 45, a bot account that also reaches 45 can hold a top-10
public row. It can never displace anyone who got there first, and the friends board is unaffected.
[Build note 2026-10-01, measured: a solver script on a hostile client reached 45 stars 62 s after joining (15
rooms). Because ties go to the FIRST to reach 45, a bot that gets there before ten real players have keeps its
top-10 row for good; players who reach 45 later rank below it. The sentence above understated that.]
[review-1 B5, measured: this is not only the bot case. Ten players at 45 on launch day fill the public top 10 for
good; a player who reaches 45 an hour or a year later is not on it. It follows from what the owner's standard
prescribes (a metric that cannot be inflated, ties to who reached it FIRST) on a metric capped at 45. Not changed
in the build: a seasonal board or a different metric is the owner's decision. The friends view still compares.]

### 11.3 The physical board

A 10 × 7 board stands 16 studs from the spawn, facing it. Its SurfaceGui reads `STAR BOARD`, then the mode, then
10 rows of `1. name ★ 45`, then `You: ★ 38`. The **public** view is built by the server in the world, the same
for everyone, and refreshed from a `GetSortedAsync(false, 10)` cached for 60 s. A **ProximityPrompt** ("Show
friends" / "Show public", reach 10) toggles the view **for that player only**. The friends view is a local
SurfaceGui (`Adornee` = the board) that the client draws from a `Board` payload, over the public face.
`GetNameFromUserIdAsync` is pcall'd and cached for 3600 s. Names are never stored.

### 11.4 Friends, throttle-safe

- **On demand only**: the first "Show friends" fetches `Players:GetFriendsAsync(userId)` pages (pcall'd), up to
  200 ids, and caches the list for 600 s.
- Friends in this server are read from memory. Every other id is read with the ordered store's `GetAsync`
  (pcall'd), and a server-wide score cache keeps each result for 300 s.
- **Paced**: before each read, `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)`
  must exceed the reserve of 10, or the pacer waits a second. The board fills in as results arrive:
  `Loading friends 40/120`.
- **Rows**: friends with at least one star, sorted by value, top 10, plus you with your rank among them.
- **Empty** [build: no friends at all reads `Add friends on Roblox to compare stars here. Met someone in the Pair
  Lift? Add them!`; friends without stars read `None of your N friends has a star yet...`]: `None of your friends has a star yet. Ride the Pair Lift with one!` **Failed**:
  `Couldn't load your friends list. Try again in a minute.`
- The pure part (`Board.luau`: the value encoding, decoding, merge, sort, and when a read may go) is unit-tested
  with a fake pager. `GetFriendsAsync` does not exist in the emulator, so the headless check covers only the
  failure path through the real glue. The success path is §20 item 8.

---

## 12. Data model

### 12.1 What persists (DataStore `EscapeRoomLab_v1`, key `u_<userId>`)

The record is `{ data = <profile>, lock = { session, until } }`.

```json
{
  "v": 1,
  "best": { "1": 3, "2": 2, "3": 0 },
  "starsAt": 1790726400,
  "escapedAt": 0,
  "boarded": 5,
  "rooms": 2
}
```

| field | meaning |
|---|---|
| `best` | the best stars per room, 0-3, keyed by the **strings** `"1"`..`"15"`. JSON turns sparse integer keys into strings (checklist), so they are strings from the start. |
| `starsAt` | unix time when the current total was first reached (the board's tie-break) |
| `escapedAt` | unix time of the first Roof arrival; 0 until then |
| `boarded` | the star total last written to the board |
| `rooms` | rooms escaped, ever (stats) |

- **Derived, never stored:** the star total (the sum of `best`), the frontier (the first room with best 0), and
  Continue. A derived number cannot disagree with its source.
- **`sanitize` on load** (pure, and `Profile.spec` feeds it hostile records): unknown keys dropped; `best` values
  floored and clamped to 0..3; keys outside `"1"`..`"15"` dropped; `starsAt` and `escapedAt` clamped to
  0..now + 60; `escapedAt` set to 0 if any room has best 0; `boarded` clamped to 0..total.
- **Not saved: anything about a room in progress.** A room takes the normal profile 1.3-4.1 minutes on average,
  by wing [M 5], and a rejoin gets a fresh room. So there is no saved secret, and fork-tower REVIEW-4 §9's
  read-only-session oracle has nothing to read.
- **Save discipline** follows the siblings and fork-tower REVIEW-4 §10:
  - `GetDataStore` is pcall'd. It raises in an unpublished place.
  - The profile loads with `UpdateAsync`, which takes the lock if it is free, expired or ours, and writes a fresh
    **`session` token** (`HttpService:GenerateGUID(false)`).
  - **Every write lands only while the record still carries our token.** Otherwise the transform returns nil,
    `canSave` goes false, and the player is told.
  - `canSave` is true only while we hold the lock.
  - Saves happen on each escape (coalesced, §6.5), every 20 s, on `PlayerRemoving` and in `BindToClose`. A
    releasing write sets `until = 0`.
- **When the store is unavailable**, the player plays with defaults and gets one toast: `Progress will not save
  this session.` [Build 2026-10-01: that is only for a server with no DataStore at all. A load CALL that fails is
  retried on every autosave tick, with `Couldn't load your stars yet. Play on: we keep trying, and what you earn
  now is kept.`; the release write on leave clears the session token, and no later write of that session lands.] The board shows `Board unavailable`. When the lock is held elsewhere, the toast is `Your save is
  open on another server — retrying`, and the load is retried on each autosave tick.
- **No one-time grants exist in v1**: no codes, no purchases, no badges (§21). Stars are max-merged by construction.

### 12.2 What is server-only

Everything below lives in **Lua tables inside the server script** (`Main.server.luau` and server modules under
`ServerScriptService`). It is **never** an Instance, an attribute or a value under `Workspace`,
`ReplicatedStorage` or a player. v1 needs no `ServerStorage` mirror either: the headless check solves from what
the player sees (§3.5.4), which is the stronger proof.

| state | why it must not replicate |
|---|---|
| each door's secret code | the answer |
| each hidden line's guess and feedback, until its feeder is solved | it narrows the door's answer before it is earned |
| each shelf's secret order | the answer |
| each lamp grid's press set S | the answer (derivable from the grid by algebra, which is solving) |
| the room's `Random` object | it generated everything above |
| lockout timers, wrong-try and hint counts, who completed what | server bookkeeping behind the stars |
| session token, `canSave`, `boarded`, write queues | server bookkeeping |

### 12.3 What replicates, and why each is safe

| what | where | safe because |
|---|---|---|
| Room shells, props, cabs, doors | `Workspace` | public geometry; other zones hold other rooms |
| Lamp states, flask arrangement, **visible** door lines, dark line slots labelled with the feeder that lights them, the keypad's last wrong code while its lockout runs | `Workspace` (SurfaceGui text, Part colours) | the puzzle's input, meant to be read |
| a solved feeder's revealed line | `Workspace` | only after its feeder is solved, which is what earns it |
| the open door, a solved station's glow | `Workspace` | only after the solve |
| `leaderstats.Stars` | player | public by design (the player list) |
| the public Star Board rows | `Workspace` | public by design |
| module source: `Config`, `CodeLock`, `Shelf`, `Lamps`, `Lab`, `Profile`, `Board`, `Decor`, `Text`, `Rng`, `EnvBands`, `Hazards`, `Rest`, `Fx`, `FxClient`, `Responsive` | `ReplicatedStorage` | public rules and public code. The generators are useless without the room's `Random` state (§14.1). **No secret may live in code.** |

**Attribute allowlist: empty.** v1 writes no attributes on any Instance. Stations are found by Instance name
(`Station_A`, `Station_B`, `Door`), and names carry no answer. Per fork-tower REVIEW-3, the check enumerates every
attribute on every Instance under every zone against an **exact** expected list, which is empty. A leak that is
renamed or moved onto a BillboardGui therefore still fails.

### 12.4 Remotes (`ReplicatedStorage.LabRemotes`)

| remote | direction | payload | validation / notes |
|---|---|---|---|
| `Act` | C → S | `(stationId: string, verb: string, a: any?, b: any?)`; verbs `press(i)`, `swap(i, j)`, `test`, `enter(code)`, `hint` | See the checks below. |
| `RoomState` | S → C, each member | `{ wing, room, slot, members, stations = { { id, kind, size, lamps?, flasks?, clues?, solved, lockedFor } }, door = { L, alphabet, lines = { { text } or { dark = true, by = "A" } }, enterable, lockedFor, lastWrong? }, you = { wrong, hinted, handsOn } }` | Sent on every change, never on a timer. The key set is an allowlist, asserted. |
| `Hint` | S → C, the taker only | `{ station, text }` | Rendered in the taker's overlay only, never in the world. |
| `Notice` | S → C | `{ kind, text }` | Toasts. The escape brag goes to all players. |
| `Profile` | S → C, owner | `{ stars, best, frontier, continue, escaped, canSave }` | |
| `Board` | S → C, requester | `{ mode, rows = { { rank, name, stars, you } }, you, loading?, message? }` | |

**Checks on `Act`:**
- the argument types must be exact, or it is dropped;
- `stationId` must be at most 16 characters and name a station **in the player's current room**;
- the reach check: the root part must be within 12 studs of the station, measured by the server;
- the rate: 10 per second;
- the state: not solved, not locked out, and the door `enterable`;
- `press`: an integer 1..n²;
- `swap`: two distinct integers 1..N;
- `enter`: an array of L integers, each in the alphabet, all distinct;
- `hint`: the cooldown and cap.

**No remote takes a star, a result, a time, a position or a room to credit.** Lifts, GO, NEXT, ATRIUM, the Roof
door and the board toggle are ProximityPrompts, whose Instance the engine supplies. Malformed payloads, which the
honest HUD cannot produce, are dropped without a toast (§16.2). Every refusal an honest player can hit is
answered with a toast (§16.1).

### 12.5 DataStore budget at 8 players

| call | worst case | budget |
|---|---|---|
| profile `UpdateAsync` | 8 × 3 autosaves per minute + escapes (at most 1 per minute per player): 32/min | 140/min for Get and Set each [DOC 60 + 10 × players] |
| board `UpdateAsync` | at most 45 per player, ever | same |
| `GetSortedAsync` | 1 per 60 s | 21/min [DOC 5 + 2 × players] |
| friend `GetAsync` | paced to keep 10 in reserve | 140/min |

---

## 13. Spawn and respawn (per `robloxemu/SPAWN-ORDER.md`)

In real Roblox, `CharacterAdded` fires while the character is unparented at the origin. One frame later the
engine parents it and places it on an enabled `SpawnLocation`, discarding any CFrame written in between. With no
enabled spawn, it drops the character on the highest ground over the origin, which in this world is the Roof
deck at y 150 [S `fork-tower/STUDIO.md` §3, SPAWN-ORDER §1]. v1 uses the preferred pattern and never races the
engine.

1. **At boot, before `PlayerAdded` is connected and before any DataStore call:** build the Atrium with
   `AtriumSpawn` (`Enabled = true`, `Neutral = true`, `Duration = 0`, so no ForceField [DOC]). **It is the only
   enabled `SpawnLocation` anywhere.** Cabs, zones and the Roof use plain Parts. The engine picks arbitrarily among
   several enabled spawns (SPAWN-ORDER §7), and deep-vein's `walk.luau` asserts the same "only one" rule.
2. **In `PlayerAdded`, as the first statement, before any yield:** `plr.RespawnLocation = AtriumSpawn`. Then load
   the profile. The same function runs for players already present when the script starts.
3. **`CharacterAdded` writes no CFrame and does not yield.** It sets `Humanoid.WalkSpeed = 16`. If the player was
   in a room, it ends their membership with `You left the room. Your stars are safe.`, because the engine has put
   them on `AtriumSpawn`. A partner continues solo (§4.4).
4. **Every other move is a server write on a character already in the world**: Atrium lift to entry cab; exit
   cab to the next entry cab; exit cab to the Roof; the Atrium's Roof Access door up to the Roof; the Roof's
   "Back down" prompt and ATRIUM ⌂ back to `AtriumArrival`, in front of the Atrium lifts. Each is guarded by
   `char.Parent ~= nil`, `Humanoid.Health > 0` and an existing `HumanoidRootPart`. If the guard fails, a start
   is refused with a toast. Any other move is skipped, because that character is already on the reset path (3).

**Headless assertions** (`check_escaperoomlab_spawn`):
- after boot with no players, exactly one enabled `SpawnLocation` exists, and it is `AtriumSpawn`;
- a joining player's root ends over `AtriumSpawn` (assert XZ and "above the pad", never the Y to the centimetre,
  SPAWN-ORDER §7), on the first spawn and after a second `simulateSpawn`;
- a lift start puts the root inside the zone's entry cab;
- a reset mid-room lands on `AtriumSpawn` and leaves the partner's room running;
- mutations:
  - a second enabled spawn in a zone: the check **fails**, because it asserts exactly one;
  - `RespawnLocation` removed: the first assertion still holds, since the only enabled spawn is `AtriumSpawn`.
    This mutation is equivalent, and the sweep must not count it as a hole;
  - `AtriumSpawn.Enabled = false`: the check **fails**, because the character lands on the highest ground over
    the origin, which is the Roof deck at y 150. That is also why "exactly one enabled spawn" is a gate: without
    it, a new player would start on the escapees' Roof.

---

## 14. Anti-exploit model

The client owns its character's physics, reads everything that replicates, reads every module in
`ReplicatedStorage` and fires any remote with any arguments. **Every rule reads the server's own state.**

### 14.1 The generator cannot be replayed

There is **no seed**. Each room is generated from a fresh `Random.new()` with no argument, which Roblox seeds from
an internal entropy source [DOC]. Nothing public goes into it: not a user id, a time, a room number or a world
seed. It is never replicated and never saved. So fork-tower's two traps are both absent:

- **A public seed** (REVIEW-4 §1): none exists.
- **A 32-bit seed brute-forced offline against visible content** (REVIEW-4 "Trap 1"): there is no 32-bit number
  to try.

What remains is recovering the `Random` object's internal state from one room's visible outputs. That needs the
engine's exact algorithm and draw order, and even complete success reveals only the **hidden door lines** early.
The door takes no entry until the feeders are solved (§3.1), and the feeders' answers are fixed by their own
public clues, so success buys nothing that solving does not.

### 14.2 Threats

| a client can | what it would buy | the response | residual |
|---|---|---|---|
| Read replicated Instances, attributes and payloads | answers | Answers never leave server memory (§12.2). The attribute allowlist is empty and the payload keys are an allowlist, and both are enumerated in `check_escaperoomlab_leak` before and after each solve. | none known |
| Run a solver on the public clues | perfect stars, fast | Not deniable: it is the rules run by a program. The metric is bounded, with ties to the first to reach it (§11.2). | a bot can hold a top-10 row until ten players reach 45 |
| Try every code or order | skipping the logic | The lockout [M 4], and the Clean star lost | a 3-flask shelf (Reception room 2) brute-forces in 28 s, about what logic takes |
| Enter the door code before the feeders are solved | skipping feeders by guessing | The keypad takes nothing until every line is lit | none |
| Fire `Act` from anywhere, or at another room's station | remote solving | The station must be in the player's current room, and the root must be within 12 studs by the server's view | a teleporting client can reach any station in its own room, and still has to solve it |
| Send malformed `Act` arguments (NaN, 1e9, strings, tables) | odd server states | Exact type and range checks; dropped | none |
| Spam `Act` | server load, or averaging lockouts | 10/s bucket; per-station lockout | none |
| Spam hints | the answer | Cap per station, 20 s cooldown, Unaided lost at the first | none |
| Ride along in a pair doing nothing | stars without work | The hands-on rule | none |
| [review-1] Do one action in a pair while the partner takes the hints and wrong tries | 3 stars a room | Clean and Unaided are the pair's (§4.3) | a perfect partner can still hand over the code: you get what the pair earned |
| Grief a partner (undo lamps, reshuffle flasks, burn the lockout) | the partner's time | Stars are per player, so a griefer cannot cost anyone a star. Leaving is one prompt. | up to 20 s of lockout per wrong try, plus undone moves |
| [review-1] Grief a partner by a wrong try or a hint | the partner's Clean or Unaided star in that room | Leaving is one prompt; a replay restores the stars (best per room) | the two stars of one room, once per room |
| [review-1] Stand idle on a Pair Lift pad | blocking every pair | Ignored: only a GO-presser on the other pad is a partner | none |
| [review-1] Ride the Solo Lift on a loop | the doorway held shut for everyone | The doors are each rider's own local part; the server never shuts the doorway, and checks who is aboard at departure | none (60 s of three riders on a loop: 0 of 1200 frames blocked) |
| Edit its own `leaderstats` or the board | rank | leaderstats are server-set; clients cannot write DataStores | none |
| Join a second server while the first holds the lock | double writes, clobbering | The session token on every write (fork-tower REVIEW-4 §10); board writes keep `max(old, new)` | none known |
| Delete hazards locally, fly, noclip | nothing: hazards take nothing, and no reward depends on movement | none needed | none |
| Replay a room | more than 3 stars there | Best per room, never a sum | none |
| Leave and rejoin to reroll a hard room | an easier puzzle | Allowed. A reroll still needs a clean solve for its stars, and costs the ride. | none |
| Change its clock | the tie-break | `reachedAt` is the server's `os.time()` at the door verdict | none |

---

## 15. Fair monetization

- **v1 sells nothing**: no game passes and no developer products. Private servers, if turned on, are set to
  free [DOC].
- **No gambling**: no spins, crates or random paid rewards of any kind.
- **No AFK or idle rewards**: nothing accrues with time.
- **No promo codes in v1**: there is nothing to grant (§21).
- **If a store comes later, it is cosmetic only**: lab-coat colours, a keycard trail, a door-open effect. It must
  change nothing the game measures. Rejected now, with the reason each is pay-to-win here:
  - paid hints: help sold for money. Hints are free and cost only the Unaided star;
  - skip-a-room or skip-a-feeder: buys stars and the frontier;
  - shorter lockouts: buys brute-force speed;
  - "reveal a line": buys the door.

---

## 16. The first 60 seconds of a new player

Times are [R] from §5 and §6.2 plus the normal profile's [A] think times.

| t | what happens |
|---|---|
| 0 s | Spawn on `AtriumSpawn`, facing the lifts. The Solo Lift's rim glows. HUD: `Walk into the SOLO LIFT` with an arrow. The Star Board is on the right, and the Roof Access door ("ROOF — for Lab escapees") is ahead. |
| 0.9 s | In the Solo Lift (14.8 studs). |
| 1.9 s | After 1.0 s standing, the doors close: `Going up to Reception…` |
| 4.4 s | The doors open on **Room 1, Reception**: afternoon sun through blinds, dust in the shafts. The card reads `ROOM 1 · RECEPTION — The door's code is in its clue lines. Solve the LAMP GRID to light the last one.` Lamp Grid A glows on the west wall. |
| ≈ 5.7 s | At the grid (20 studs, 1.25 s); the prompt says `Open`. **The core action**, about 5-6 s from spawn (checklist §4 asks for about 5). |
| ≈ 19 s | The overlay shows a 3×3 grid needing 2 presses, and one line: `Tap a lamp: it and its neighbours switch. Light them all.` A normal player needs about 13 s (2 × 5 s think, 4 taps) [A]. Solved: the lamps glow, a sparkle plays, and the door board lights its dark line: `Line 3 is lit!` HUD: `Now crack the door code`, with an arrow. |
| ≈ 21 s | At the door (21.9 studs). The overlay shows the 2-3 clue lines (digits 1-6) and the keypad. |
| ≈ 70 s | About 45 s of thinking for 3 lines [A], then the code: the door slides up with a flash. `ESCAPED ★★★` (or which star was missed, and why). The exit lift waits: `NEXT ▶` / `ATRIUM ⌂`. |

A first-time player gets the rule line on the first station of each kind, and one arrow at a time. Nothing needs
buying, reading a manual or a prerequisite.

### 16.1 No silent no-ops (the toast list)

| refusal | toast |
|---|---|
| out of reach | `Walk up to the station.` |
| door not yet enterable | `The keypad is dark: solve LAMP GRID A to light the last line.` |
| lockout | `Locked for 6 s after a wrong try.` |
| already solved | `Already solved.` |
| hint cooldown | `Next hint in 12 s.` |
| hint cap | `No more hints here. The last step is yours.` |
| rate | `Slow down.` (at most once per 5 s) |
| exit NEXT with a member outside | `Waiting for <name>.` |
| Pair Lift | `The Pair Lift needs two players who both press GO.` / `The Pair Lift is full.` |
| [review-1] Pair Lift, same pad as a GO | `One player per pad: step onto the other pad and press GO.` ("full" only for a third player during a countdown; one of the departing pair is told `The Pair Lift leaves in a moment.`) |
| [review-1] left a lift during its ride | `You stepped out of the lift before it left. Step back in to ride.` |
| [review-1] NEXT while the lift is already going up | `The lift is already on its way.` (NEXT also goes dark as it leaves) |
| Solo Lift with two inside | [build 2026-10-01: each rides to a room of their own, told `Solo Lift: each of you gets a room of your own. Take the PAIR LIFT to play together.`; "One at a time" let one player block every solo ride] |
| Roof door, not escaped | `Roof access is for Lab escapees. You are at room N of 15.` |
| no DataStore | `Progress will not save this session.` |
| lock held elsewhere | `Your save is open on another server — retrying.` |

### 16.2 Silent by design

Malformed `Act` payloads are dropped without a toast. The honest HUD cannot produce them, so this protects the
server from non-players, and the checklist's rule protects players.

---

## 17. Visuals and HUD, from the first build

### 17.1 Fx

- **Fx**: copy `Fx.luau` from anomaly-observatory (md5 `142bf959…`, the variant that knows an `Atmosphere`
  replaces the legacy fog). Add one preset, `Fx.Presets.Lab`, equal to band 1's lighting.
  `Fx.applyLighting(Fx.Presets.Lab)` is the server's first statement.
- **FxClient** (md5 `92d83a20…`): `FxClient.theme` on every HUD frame. `flash` and `fovPunch` on an escape and on
  the Roof, `shake` on a hazard hit.
- **Signature light**: every unsolved station has a faint rim glow (`Fx.attachGlow`), because interactive things
  must read as interactive (checklist §2). A solve plays `Fx.sparkle` and turns the glow green. The door's lock
  lamps go red to green one per lit line. The Atrium has one `Fx.dustVolume`.

### 17.2 The HUD, phone first

`Responsive.luau` is copied verbatim (md5 `8cf3ba92…`), with its spec. A root Frame owns the `UIScale`, sized
`1/scale`, and everything re-lays-out on `ViewportSize` and `TouchEnabled` changes.

| element | where | interactive |
|---|---|---|
| star chip `★ 38/45 · Archive 2/3` | top left | no |
| **☕ Break** | top right | yes, ≥ 44 × 44 screen px |
| banner (hazard warnings, title cards, toasts) | top centre | no |
| **station overlay** | see below | yes, every control ≥ 44 screen px |
| escape card `ESCAPED ★★☆` | top centre, transient | no |

**The station overlay** is modal. While it is open, the star chip hides, so no two visible panels ever overlap;
the Break button stays.
- **On touch landscape**, it is the screen's **middle 40% column**, the one area Roblox's thumbstick (bottom-left
  35%) and jump button (bottom-right 25%) leave free at full height, below the top margin.
- **On portrait and larger screens**, it is the full width above the control pad, starting below the Break
  button's row.

On the smallest viewport the hudcheck uses (640 × 300, touch), `Responsive.layout` gives `controlPad` = 105 and
scale 0.6, so the column is **256 × 276 screen px** [R]. The content:
- a **4×4 lamp grid**: 4 × 44 + 3 × 6 = **194 px** square, plus a 44-px title bar = 238 px;
- a **5-flask shelf**: 5 × 44 + 4 × 6 = **244 px** wide, over a scrolling clue list and a TEST button;
- **the door**: two tabs, `Clues` (a scrolling list of lines, each showing its guess digits large with the
  sentence under them) and `Keypad`. The keypad is 3 columns × 4 rows of 44-px keys with 6-px gaps, 144 × 194 px;
  with a 30-px display of the digits entered and the 44-px title bar, it needs 268 of the 276 px [R]. The two
  tabs sit side by side on tablets and desktops.

Rules asserted by `check_escaperoomlab_hud` through `robloxemu/emu/hudcheck.luau` at all 10 viewports, with
**`overlap = true`** (rule 4b):
- every tap target is ≥ 44 screen px;
- nothing tappable lies in the thumbstick or jump bands;
- every ScrollingFrame's canvas covers its content;
- no two visible panels overlap.

A `warmup` pushes a `RoomState`, so the overlay's controls, which are built by a remote handler, exist when they
are measured. This is the anomaly tint-swatch lesson in hudcheck's own header.

**Colour is never the only cue.** Flasks carry letters. Lamps are bright with a filled centre when lit and dark
with a hollow ring when not, so they read in greyscale [STUDIO]. Red means exactly one thing: danger (the ring,
the hazard banner, a wrong-try ✗).

---

## 18. Build plan: tests first

### 18.1 Files (deep-vein's layout)

```
escape-room-lab/
  default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  src/shared/  Config  Rng(below, md5 54635d1d…)  Fx(+Lab)  FxClient  Responsive  EnvBands  Hazards  Rest
               CodeLock  Shelf  Lamps  Text  Lab  Profile  Board  Decor
  src/server/  Main.server.luau  (+ RoomBuilder, Store as server modules)
  src/client/  Hud.client.luau  Lab.client.luau (bands, decor, creatures, weather, hazards, Break)
  tests/       CodeLock Shelf Lamps Text Lab Profile Board Decor EnvConfig Pacing(+LabModel) .spec.luau
               EnvBands Hazards Rest responsive .spec.luau  (verbatim)
  design/      model.luau  hazard_probe.luau   (design tools, not shipped)
  DESIGN.md README.md CLAUDE.md EYECANDY.md MARKETING.md .gitignore (publish_*.bat / publish_*.sh)
```

Shared modules take their dependencies as arguments. `require("./X")` is valid only in the luau CLI.

### 18.2 Unit specs, each watched failing before its module exists

- `CodeLock` and `Shelf`: the §3.5 invariants over 1000+ seeded sets each, the acceptance rules of §3.4, and
  hint text never revealing more than the cap.
- `Lamps`: a null space of dimension 0 for 3×3 and 4 for 4×4; the minimum equals k; the hint is part of a
  minimum from the current grid.
- `Text`: a sentence for every (A, B) and every clue type, and every clue sentence plain ASCII. The HUD's ★ ☕ ⚠ ▶ ⌂
  are §20 item 18.
- `Lab`: the V4 table; Continue in solo, pair and after the Roof; the stars and the hands-on rule; p per §7.1.
- `Profile`: `sanitize` against hostile records; the derived frontier; `starsAt` moving only when the total rises.
- `Board`: the value encoding at the extremes of [M 6]; merge and sort; pacing against a fake budget.
- `Decor`: creature and decor bounds per room.
- `EnvConfig`: every band defines the same fields; `EnvBands.validate`; `Hazards.validate`; `Rest.validate`;
  `PendingSeconds` ≥ the longest flight + 2 s; speed × telegraph ≤ the ceiling height − 4.
- `Pacing`: §10.2's assertions.

### 18.3 Headless gates (`robloxemu`, which walks the real player path)

`py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau` before **every** run.

| check | what it proves |
|---|---|
| `check_escaperoomlab.luau` | **The walk.** Join, spawn, Solo Lift, room 1. Solve each station **from the rendered text** with the pure solvers. Escape and repeat for all 15 rooms, to the Roof. Then rejoin: the stars are kept, and Continue walks the missing stars. Also asserts the Parts per room. |
| `check_escaperoomlab_spawn.luau` | §13 |
| `check_escaperoomlab_leak.luau` | Snapshot every replicated string, attribute and payload **before** each solve, then search it for that station's answer once the solve reveals it. Empty attribute allowlist; payload key allowlist. Watched failing against a mutant that writes the door code as an attribute. |
| `check_escaperoomlab_pair.luau` | Two players, both pressing GO; shared state; the hands-on rule; lockout per station; one leaves and the other continues; NEXT waits. |
| `check_escaperoomlab_save.luau` | Session token; a stale write cancelled; board written only on improvement, keeping `max`; tie-break order; the store unavailable; the friends failure path. |
| `check_escaperoomlab_env.luau` | Bands per room, the seep-in during each wing's last room, the glide across lift rides, budgets on every frame, decor off the play space. |
| `check_escaperoomlab_hazards.luau` | Lanes under the ceiling; the drawn ring equals the zone; step-out dodges and standing still is hit, through the real client; the clock frozen in cabs, the Atrium and the Roof; the arrival grace; the overlay collapse and reopen; the Break frozen, queued and ended by a station. |
| `check_escaperoomlab_hud.luau` | §17.2 through hudcheck, with `overlap = true`. |

Every new assertion is mutation-tested, **with a control mutation that must survive**, before it counts. Then:
`luau-compile --binary` on every source, and `luau-analyze` clean after filtering Roblox noise.

### 18.4 Traps this game has (for its `CLAUDE.md`)

1. **The door gate.** The keypad must refuse every entry until all its lines are lit. Without the gate, the
   visible lines leave 2-252 candidates to guess among [M 1].
2. **Hidden line text is server memory until its feeder is solved.** It must never sit in the world early, not
   even in a hidden TextLabel or a disabled SurfaceGui: both replicate.
3. **Hints go to the taker only** (`FireClient`), never into the world, or the partner's Unaided star is spoiled.
4. **`ctx.pitch = math.rad(85)` must reach `Hazards.step`.** Pass the camera's real pitch instead, and lanes start
   out through the walls: the template then plans them at up to 20° off the camera's pitch, from 12 studs away.
5. **`Rest.IdleSeconds = 0` is deliberate** (§9). Restoring the template's 20 silently switches hazards off at
   every station.
6. **Exactly one enabled `SpawnLocation`.** With none, new players start on the Roof deck (§13).
7. **`Config.Studio.StartSlot`** must stay guarded by `RunService:IsStudio()` **and** `canSave == false`.
8. **Profile keys are the strings `"1"`..`"15"`** (checklist: JSON integer keys).
9. **The board write comes after the profile write lands, and keeps `max(old, new)`.**
10. **Rebuild the bundle before every headless run** (deep-vein's lesson in `check_deepvein.luau`).

---

## 19. Ship and market: drafts for README, EYECANDY and MARKETING

### 19.1 Store text (for `README.md`): 933 characters, measured, ASCII only

```
Crack the codes, light the lamps, line up the flasks and get out of the Lab.

Every room is built fresh when you walk in, and the game checks every puzzle before you see it: each one can be solved by logic alone, no guessing.

- 15 rooms in five wings: Reception, Archive, Greenhouse, Cold Storage and the Reactor. Each wing has its own light, weather and wildlife.
- Three kinds of logic puzzle: number locks with clue lines, flask-order riddles and lamp grids.
- Play solo, or ride the Pair Lift with a friend and split the work.
- Up to 3 stars per room: escape, make no wrong tries, use no hints.
- Stuck? Hints are free. They only cost that room's hint star.
- Watch the ceiling. When something comes down, a red ring shows exactly where it lands. Step out of it.
- Need a breather? Press Break and the Lab leaves you alone.
- Reach the roof, then climb the star board, public or friends only.

Nothing in this game costs Robux.
```

Genre: Puzzle → Escape Room. Maturity: decided by the questionnaire, whose Preview page is the ground truth
(checklist §6). Nothing in v1 is violent or gory.

### 19.2 Thumbnail shot list (for `EYECANDY.md`, 1920 × 1080)

Staging: a Studio copy built with `rojo build`, with Studio API access **off** so nothing saves. It uses
`Config.Studio.StartSlot`, which is honoured **only** when `RunService:IsStudio()` **and** `canSave` is false, so it
can never touch a real profile or run live. Room-local coordinates as in §5.

1. **"Crack the code"** (Archive). The avatar at (−8, 0, −11), facing the door board at (−10, 8, −15.5). Camera at
   (4, 7, −2), looking at (−9, 7, −15). In frame: the board with three lit lines and one dark slot, green banker's
   lamps, moths in the lamplight, drifting paper.
2. **"Step out of the ring"** (Cold Storage). The shot's Studio copy sets `Hazards.IntervalMin/Max = 8/10`. The
   avatar mid-step out of the red ring, the ice drone 4 studs above, snow flurries. Camera low at (0, 3, 6),
   looking up at (−2, 7, −2).
3. **"Two heads"** (Greenhouse, two Studio clients). Two avatars at the east-wall shelf, one pointing. Butterflies,
   sun through the glass ceiling. Camera at (4, 6, 6), looking at (13, 5, 0).
4. **"The Reactor opens"**. The exit door sliding up, with teal light and sparks pouring in. Camera at (0, 5, 4),
   looking at (0, 6, −16).
5. **"You escaped the Lab"** (the Roof). The avatar at the telescope rail, stars, moon, the lit city, a firework.
   Camera behind and above, looking out over the city.
6. **Icon**: the door keypad close up, with a glowing `? ? ?` and one lit clue line.

### 19.3 Clip list (for `MARKETING.md`: vertical 1080 × 1920, 7-15 s, `tools/film_game.py` rules)

The staging uses only a start position (`StartSlot` in Studio, as above) and the camera. No game number is edited
for a clip. The hazard clips wait for a natural hazard, which comes within 180 s of exposed time.

| # | clip | length | how to stage |
|---|---|---|---|
| 1 | **The last digit**: the final key, the door slams up, `ESCAPED ★★★` | 8 s | any room; solve the feeders, record from the keypad |
| 2 | **Spider drop**: creak, the red ring, the step out, the spider bonks the floor | 7 s | an Archive room; stand at a station and wait |
| 3 | **Three taps**: a 3×3 grid solved in 3 taps, the grid lights, a door line appears | 10 s | Reception room 3 (k 3) |
| 4 | **Which order?**: four clue sentences on screen, two swaps, TEST, green | 12 s | an Archive shelf room; hold on the clues 4 s |
| 5 | **The wing changes**: the last Archive room's door opens as greenhouse light floods in | 12 s | Archive room 3; record the door solve |
| 6 | **Pair up**: two players in the Pair Lift, then one reads, the other taps | 12 s | two Studio clients (§20 item 10) |
| 7 | **Roof**: the lift opens on the stars and fireworks, `YOU ESCAPED THE LAB` | 10 s | `StartSlot = 15` in the unsaved Studio copy; solve the room, record the ride up |
| 8 | **Crack this code?**: a still door board with four lines for 8 s, then the answer entered | 15 s | any 3-digit door; a caption asks the viewer |

---

## 20. Needs Studio (only real rendering, input or a live server can settle these)

1. **Every band's look indoors**: Ambient, exposure and bloom per wing; band 1 equal to `Fx.Presets.Lab`; the
   seep-in during each wing's last room reading as a change, not a glitch.
2. **Overlay legibility on a real phone**: clue sentences at the smallest size; the Clues and Keypad tabs; the
   scroll.
3. **ProximityPrompts on touch**: the 8-stud reach at a wall station; the prompt button not under a thumb.
4. **The vertical hazard**: a model lowering at 4 studs/s reads as "coming for you"; the ring reads on every floor
   material; the banner is seen in time although the lane starts above the frame (§8.1).
5. **The knock**: 20 studs/s with 0.6 s of PlatformStand pushes without flinging, and releases cleanly; the overlay
   collapse and reopen feels fair.
6. **Break**: `Humanoid.Sit` from the client sits, replicates, and wakes on stick input.
7. **Generation on a live server**: up to 19.40 ms per 4-digit door in the CLI [M 1b]. Is that a visible hitch?
   If so, yield between regenerations.
8. **Friends board**: `GetFriendsAsync` paging, `GetRequestBudgetForRequestType` behaviour and name lookups on a
   live server. Needs a published universe.
9. **The board's ordered `UpdateAsync` with `max`** on a live store.
10. **Two real clients in a pair**: shared state feels shared; a partner's knock with nothing visible hitting them
    (hazards are local) reads as odd or fine.
11. **Tap targets and the safe area** on real phones (notch, home indicator).
12. **Frame time** on a mid or low phone in the densest room (Reactor: up to 160 server parts, 120 local, 3 emitters).
13. **Creature and decor models**: orientation and scale; icicles and vines not reading as blocking the way.
14. **The Roof**: stars visible with the band's Atmosphere; the city skyline at 250-500 studs; fireworks.
15. **Door slide, sparkle, flash and FOV punch**: celebratory, not annoying.
16. **The lift illusion**: the teleport between two identical cabs with the doors shut is seamless (camera snap?).
17. **`Config.Studio.StartSlot`** works in Studio and is inert when published.
18. **Glyphs**: ★ (U+2605), ☕ (U+2615), ⚠ (U+26A0), ▶ and ⌂ render in the chosen fonts. Fork Tower saw U+1FAA8
    draw as an empty box [S `fork-tower/STUDIO.md` §4].
19. **Colour-blind check**: flask letters and lamp lit/unlit states in greyscale.
20. **Human times**: the first real sessions replace every [A] in §10.1, then Pacing is retuned.

After this list comes the night shift's own work (standard §5): the universe, publishing, the maturity
questionnaire, thumbnails, clips, and then marketing.

---

## 21. Cut from v1, and why

| cut | why | what would bring it back |
|---|---|---|
| Split-view co-op (Diver/Keeper, each seeing half) | per-client secret rendering plus a role UI plus a solo two-role mode; unprovable headless (§2) | a two-client harness, or a night-shift Studio test with two clients |
| Rising water, strikes, drowning | contradicts "a hit costs a little, never a run" and the rest template's clock rule (§2) | never, by design |
| Three more puzzle kinds (valves, dials, breakers) | three measured kinds beat six thin ones | a kind = a generator + its fairness spec + one station model; a content update |
| Up to 4 players | a room has 2-3 stations and the hands-on rule needs one per player (§2) | rooms with 3-4 feeders |
| Room Directory (pick any room) | Continue already walks the rooms missing stars (§4.2) | a 15-button panel in the lift |
| **Night Shift** (a harder second pass of all 15 rooms: 4-digit doors, 5-flask shelves, 4×4 grids everywhere, a night overlay on every band) | the long-term goal beyond 45 stars, especially for careful players (§10.4) | the next update: the generators are already parametric |
| Speed medals and par times | bot-won and anti-logic (§11.2) | personal bests only, never ranked |
| Badges ("Escaped the Lab") | need a universe and real badge ids; a stub would be a silent no-op | the night shift creates them; one line wires them |
| Promo codes | nothing to grant | a cosmetic store, if ever |
| Daily shared room | a shared room's answer is shared within minutes (§2) | never as a ranked mode |
| Audio | asset ids cannot be verified without Studio; an unverified id plays silence | the night shift picks and verifies them |
| Saving a room in progress | a room takes the normal profile 1.3-4.1 min [M 5]; a saved room is a saved secret (fork-tower REVIEW-4 §9) | never |
| Joining a friend mid-run | adds a late-join path to every room state | the Pair Lift covers "play with a friend" |
| A friends-only Pair Lift | untestable headless, and unnecessary with per-player stars (§4.4) | private servers already do it |

---

## 22. Self-review

- **Placeholders:** none. Every station, number, remote, field, toast and file is named. Values only Studio can
  settle (lighting, light brightness, the doorway size, the knock's feel, glyphs) are tagged [STUDIO] and listed
  in §20.
- **Contradictions checked:**
  - The store text says "with a friend", while the Pair Lift takes any two players. Both hold: riding with a
    friend is one case of "any two players who both press GO" (§4.4).
  - "Every puzzle can be solved by logic alone": the Code Lock and Shelf have unique minimal clue sets, and the
    Lamp Grid is solvable by construction (§3). The door gate removes guessing.
  - Hazards are "rare": 13.7 on the normal way to the Roof, one per 149.4 s exposed [M 5, P]. That matches the
    standard's "one per 2-3 minutes". [review-1: 10.2 on the normal way to the Roof, one per 100.8 s of exposed
    time, median gaps of 170-206 s of play in eight full headless paths.]
  - Rest `IdleSeconds = 0` is an adaptation, stated with its reason, and `Rest.luau` stays verbatim.
  - `ctx.pitch = 85°` is the Hazards adaptation, in the config and glue only. The file and its spec stay verbatim,
    and what is given up (a lane that starts on screen) is stated in §8.1.
  - The wing table in §4.1 is `LABS.V4` in `design/model.luau`, room for room.
- **Every number justified:** each has a tag. Assumptions are confined to human behaviour (§10.1) and a few
  UI pacing choices (GO window, countdown, hint cooldown), each marked [A].
- **Open risks, ranked:**
  1. The human times [A] set the 39.3-minute brag. They are the most likely number here to be wrong.
  2. The vertical hazard's readability (§20 item 4).
  3. Overlay space on the smallest phones: the arithmetic fits, and the real safe area is Studio's (§20 items 2, 11).
  4. A bot on the public board before ten players reach 45 (§11.2).
