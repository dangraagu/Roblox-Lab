# Find It! Chapters: design spec (v1)

**Status, 2026-10-07: spec only. No game code exists.** Nothing is committed, pushed or published, no universe
exists, and Studio was not opened. Source concepts: `docs/game-radar/2026-09-14-roblox-game-radar.md` ranked entry #5
"Chapter-based hide & search puzzle (procedural hidden-object)" (line 56, and the runner-up note at line 313), and
`docs/game-radar/2026-09-06-roblox-game-radar-round2.md` "Multiplayer hidden-object search race (round-based,
seeded)" (line 38, brief at line 145). Finish line: `docs/complete-game-standard.md`. Build recipe and traps:
`docs/new-game-checklist.md`. Also read for this spec: `robloxemu/SPAWN-ORDER.md`, `fork-tower/REVIEW-4.md`,
`anomaly-observatory/CLAUDE.md` ("ServerStorage, not the zone"), `plus1-jump/src/shared/{EnvBands,Hazards,Rest}.luau`
and `plus1-jump/EYECANDY.md`, `same-door/DESIGN.md`, `escape-room-lab/DESIGN.md` (the indoor hazard config) and
`lost-found-depot/DESIGN.md` §10.3 (why no time board).

---

## 0. How to read the numbers

Every number carries a tag.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.py` (`py -3 design/model.py`, about 8 minutes, deterministic seeds; the last output is saved as `design/model.out.txt`). A design-time model, not game code. Model numbers hold under the model's written-down assumptions ([A] below), not for real players. |
| **[S file]** | Measured or reviewed earlier in this repo, on a sibling game, with the file named. Not a measurement of this game. |
| **[R]** | Arithmetic or a stated rule, worked inline. |
| **[C]** | A design choice. The reason is next to it. |
| **[A]** | An assumption about people. Every human time and error rate in the model is one. The first real play session replaces them. |
| **[DOC]** | Roblox documentation, fetched 2026-10-07 (create.roblox.com, data store error codes and limits). |
| **[STUDIO]** | A starting value only real rendering, input or a live server can settle. It is on the needs-Studio list (§20). |

**Why the model is Python.** The brief names a luau CLI in the session scratchpad. On 2026-10-07 that directory was
empty, and no `luau.exe` exists on this machine (searched C:, D: and WSL). A download needs the owner's go
(`grow-a-crystal/CLAUDE.md` records the same rule), so the measurements are in `design/model.py`. The build phase
ports Parts 2-3 into `tests/FinderModel.luau` + `tests/Pacing.spec.luau` against the real `Config.luau` and
re-measures them (§19).

**The player profiles [A].** `read`: seconds to read one clue chip. `tau`: mean seconds to notice ONE given matching
prop in a 36-prop room. When m matching props are still unsearched, the next one is noticed after Exp(tau / m), so the
last one is the slowest, and tau grows with sqrt(S / 36) for clutter. `select`: the first tap (outline and label)
before the confirming tap. `slip`: chance a search of a matching prop is preceded by a search of a prop that fits no
clue (a misread). `hint at`: takes the hint when less than this share of the clock is left. `hit`: share of hazards
that land.

| profile | read | tau | walk efficiency × detour | select | slip | hint at | hit |
|---|---|---|---|---|---|---|---|
| fast | 1.0 s | 6 s | 0.95 × 1.20 | 0.3 s | 0.03 | never | 0.05 |
| **normal** | 1.5 s | 10 s | 0.85 × 1.25 | 0.4 s | 0.07 | 30 % left | 0.15 |
| slow | 2.5 s | 16 s | 0.75 × 1.30 | 0.6 s | 0.12 | 40 % left | 0.30 |

Two scripted strategies bound the humans: the **bot** (a script that knows the clue rules: no reading, no noticing, no
select tap, never off-clue, nearest matching prop next, walks at exactly 16 studs/s) and the **tap-everything** player
(ignores clues, searches the nearest unsearched prop, 0.5 s to pick it, normal walking). A third, the **sweeper**, is
a sensitivity case: a systematic human who walks the room and checks each prop against the list (0.35 s + 0.1 s per
unfound clue [A]), searching only what fits.

Walking in the model is a straight line, times the detour factor, at 16 studs/s times the efficiency, stopping 5 studs
short of the prop. It is not a physics model.

### Where each item of the standard lives

| `docs/complete-game-standard.md` | here |
|---|---|
| §1 core loop reachable from join, walked headless | §1, §16, §19.3 (`check_finditchapters.luau`) |
| §1 spawn per SPAWN-ORDER | §13 |
| §1 server-authoritative, nothing secret replicates, salted seeds | §3.3, §12, §14 |
| §1 DataStore: pcall, lock, owner token, string keys, atomic one-time grants | §12.1 |
| §1 no silent no-ops | §17.2 |
| §2 Fx preset, signature particles | §17.3 |
| §2 bands (5), hazards (ring = hit zone), rest, budgets | §7, §8, §9, §18 |
| §2 brag in 30-45 min, long-term goal, pacing model in tests | §10 |
| §2 phone first, UIScale root, hudcheck `overlap = true` | §17.1 |
| §3 public + friends board on an uninflatable metric, ties to first | §11 |
| §3 no Robux, no gambling, no pay-to-win | §15 |
| §4 store text, EYECANDY needs-Studio + shot list, MARKETING clips, CLAUDE.md | §19.4, §20, §21 |

---

## 1. The core loop

You open the Case Book in the Finder's Agency, the hub, and step into a chapter: a cozy, cluttered room built fresh
for this attempt, with a list of 3 to 9 things to find. **Where they are is never in the room.** Each thing has a clue
made of two of a prop's three visible traits, like "a BLUE BOX" or "something YELLOW up HIGH", and exactly 3 to 5
props in the room fit each clue. You look around for the props that fit, tap one to look at it, and tap it again to
search it. Searching takes a second, and the server answers: the thing pops out in a burst of gold, or there is
nothing there. Every attempt has a clock and a number of **looks** (searches), and careful play can never run out of
looks, while tapping everything does. Find the whole list in time and the chapter is cleared, with up to three stars
(Found, Swift, Sharp Eye), and the next chapter opens. A failed attempt costs nothing but the time: Retry builds a new
room. Fifteen chapters in five themed bands make Book One, and solving its last case, in the observatory, is the
brag moment, at about 33 minutes for a normal player [M 3]. After that, every UTC day brings a **Daily Case**, and the
public board ranks **Cases Solved**: the chapters you have cleared plus the Daily Cases you have solved, at most one per
day.

---

## 2. What v1 is, and what is cut

**In v1:** the hub (spawn, the Case Book lectern, the Daily Case door, the board); one room lane per player; the
room generator and the secret hiding draw; search, looks, hint, clock and stars; Book One (15 chapters, 5 bands);
the Daily Case; five environment bands; five themed ceiling-drop hazards; pause; the Cases Solved board (public and
friends); a phone-first HUD.

**Cut from v1**, each because it would ship thin:

| cut | why |
|---|---|
| a multiplayer race in one shared room (round-2 radar) | rivals watching you find the key learn where it is. Shared rooms need per-viewer replication of finds and a lobby/round loop with its own fairness proof. v2 candidate |
| a daily layout shared by everyone (round-2 radar's "daily shared seed") | answers spread the same day ("the key is in the green basket"), so later players are spoiled and the board measures who read the spoiler. Every attempt draws its own secret (§3.3) |
| the radar's `seed = math.floor(os.time()/86400)` | a seed any client can compute is the fork-tower REVIEW-4 defect. There is no seed (§3.3) |
| players hiding things for each other | moderation, griefing and a second UI |
| coins, a shop, upgrades, gamepasses, developer products | nothing to spend on that is not either cosmetic-thin or pay-to-win (a better magnifier buys the skill). Nothing costs Robux in v1 |
| a Finder's Album (collect every item kind) | its own UI and persistence; a v2 long-term goal |
| hot/cold feedback on a miss | a deduction layer that needs a "which item am I hunting" selection on a phone and a posterior a script computes better than a child |
| a "junk inside the container" spotting step after opening | the reveal is already server-gated; this adds art and a second pick |
| Book Two | content after the first measured play sessions |
| badges, promo codes, audio, music, spectating, a hub armchair | nothing to grant; audio needs assets; the hub runs nothing, so it is already the place to rest |

---

## 3. The rules of a room

### 3.1 Props and their three traits [C]

Every searchable prop has exactly three traits, each readable from across the room:

| trait | values | why these |
|---|---|---|
| **kind** | box, basket, jar, vase, pot, cushion, bag, chest | 8 silhouettes that differ in outline, not detail: a cube, a woven bowl with a handle, a lidded cylinder, a narrow neck, a tapered pot, a flat pillow, a tied sack, a round-lidded trunk. Free-standing props, so "where" never depends on furniture |
| **colour** | WHITE, YELLOW, BLUE, GREEN | 4 colours apart in hue and lightness. **Never red** (the hazard ring owns red) and **never gold** (gold means found or hinted). Colour-blind players are covered by the label chip: a selected prop's label names its colour (§17.1) |
| **height** | FLOOR, TABLE, HIGH | on the floor, on a table or counter top, or on a wall shelf above head height. Three bands with gaps between them, so no prop is "sort of high" |

Decor that is **not** searchable (furniture, scenery, critters) never uses a kind's silhouette, so "is this a prop?"
is never a question. A tap on decor answers "Nothing to search there" on the client.

### 3.2 Clues [C]

A clue names one or two traits. Forms: **K** ("a BASKET"), **CK** ("a BLUE BOX"), **CH** ("something YELLOW up
HIGH"), **KH** ("a JAR on the FLOOR"). Early chapters use K and CK; CH and KH (which make you look at heights) come in
from chapters 3 and 5 (§4). On the HUD a clue is two glyphs: a colour swatch with its initial letter, a kind
silhouette, or a height arrow. Tapping the chip spells it out.

**The two rules every room keeps, by construction:**
1. **Exactly k props fit each clue** (k = 3, 4 or 5 by chapter).
2. **No prop fits two clues.** The candidate sets are disjoint, so a search can only ever tell you about one thing on
   the list, and a careful player's reasoning ("one of these 4") is exactly the best reasoning there is: the hiding
   spot is uniform over the k candidates (§3.3), so a script that computes the exact posterior knows nothing a careful
   child does not.

A new clue is rejected if one clue's constraints contain another's (every BLUE BOX is a BOX, so "a BOX" and "a BLUE
BOX" cannot both have disjoint sets).

### 3.3 How a room is made, and why no client can know where anything is

The order is the whole security argument:

1. **Clues.** The server draws the chapter's N clues from its forms.
2. **Dressing.** It builds exactly k candidate props per clue (traits fitting that clue and no other), then fills the
   room to S props. A share ρ of the fillers are **partial matches** of a two-trait clue (BLUE but not a BOX, for
   "a BLUE BOX"): the near-misses a careless reader searches. The rest are random props that fit no clue.
3. **Positions.** S positions are drawn for the whole room (3-stud minimum spacing, nothing within 6 studs of the door
   mat), the props are shuffled, and positions and ids are dealt to the shuffled list. A prop's id and place say
   nothing about its role. Chapter 1 only: clue 1's three candidates take the three positions nearest the door, so the
   first find is in view (§16). That is public and still says nothing about which of the three.
4. **The payload.** The room (every prop's id, kind, colour, height, position, yaw and model variant; the decor; the
   clues) is serialised **now**, before step 5 runs. It cannot depend on the secret.
5. **The secret.** For each clue, one of its k candidates is drawn uniformly. That draw is the only secret, and it
   lives in server memory (§12.2).

**Every draw is server entropy; no seed exists.** The draw function is fork-tower's `mintSecret` construction
[S fork-tower/REVIEW-4.md §2]: `bit32.bxor(life:NextInteger(0, 4294967295), fresh:NextInteger(0, 4294967295))`,
where `life` is a `Random.new()` made at server start and `fresh` a new `Random.new()` per draw, mapped to a range
through its **high bits** (`docs/new-game-checklist.md`: never `state % span`). Generators take the draw function as
an argument, so tests pass the repo's deterministic `Rng`. A client therefore has nothing to brute-force against what
it sees (REVIEW-4 trap 1): the dressing and the secret are separate draws, and the secret drives nothing visible.

**Measured [M 1].** Over 2000 rooms per chapter (and the Daily Case), every room had exactly k props per clue and no
prop fitting two clues (0 rooms off). The generator needed 1.000 to 1.084 attempts on average and at most 4. Over
120 000 hides of one fixed chapter-8 room, every candidate was picked 1/k of the time: chi-square 26.2 on 24 degrees of
freedom (the 0.1 % critical value is about 46), worst cell 1.65 % off.

### 3.4 Searching [C]

* **Tap to look, tap again to search.** The first tap outlines the prop (white, never red or gold) and shows its label
  chip, for example `BLUE BOX · HIGH`, with a Search button. A second tap on the same prop, or the button, sends
  `Search(id)`. Desktop: click, then click again or press E. The two taps cost a little time (the model's `select`)
  and stop a stray tap from spending a look.
* **Reach: 10 studs**, horizontal distance from the root to the prop, any height. The server allows **+2 studs** of
  slack, for a player walking at 16 studs/s whose position reaches the server about 0.1 s late. Out of reach, the
  client says `Walk closer` and sends nothing; the server checks again anyway.
* **A search takes 1.0 s** (the rummage animation), hit or miss. The server answers at the end of that second **in
  both cases**, so the answer's timing says nothing. One search at a time.
* **The answer** goes to the searcher only. A hit: the item pops out of the prop with a gold burst, flies to its list
  chip, and the chip turns gold. A miss: a puff of dust, and the prop gets a small grey tick (client-side, for memory).
  A miss on a prop that fits no clue you still need also says why: `That WHITE BASKET doesn't fit any clue you still
  need`.
* **Searching the same prop again** is free and instant: `Already searched`.

### 3.5 Looks [C, M 2, M 7]

Every attempt has **N × k + 2 looks**. A player who only searches props that fit a clue they still need uses at most
N × k, so careful play **can never run out**, whatever the luck. Out of looks with things left on the list ends the
attempt (`Out of looks! Read the clues and try again`).

**Why looks exist: without them, tapping everything beat reading.** The first draft had no limit, and the model
measured the tap-everything player clearing chapter 15 in 124.9 s on average against 207.1 s (p50) for a normal
reader, inside the clock every time [M 2]. A hidden-object game where reading the clue is the slow way is broken. With
N × k + 2 looks, tap-everything solves 32 % of chapter-1 attempts and 5-21 % from chapter 2 on, while the normal
profile ran out of looks 3 times in 2000 attempts in chapter 1 and never in any other chapter [M 2].

### 3.6 The hint [C]

One per attempt. Tap a list chip, then **Hint**: the server sends that item's prop id, and the prop sparkles gold. You
still search it (one look). A hint costs the Sharp Eye star. It is the valve for a stuck child: the normal profile
takes it with 30 % of the clock left, the slow one at 40 % [A].

### 3.7 The clock and the three stars

The clock is the **server's**: the sum of Heartbeat `dt` while the attempt is live and not paused (`os.clock` is CPU
time and barely moves headless, `deep-vein/CLAUDE.md`). It starts when the 3-second intro card closes (1.5 s on a
retry), and searches before that are refused (`Get ready...`).

| star | earned when | why |
|---|---|---|
| **Found** | every item found before the clock and the looks run out | clears the chapter |
| **Swift** | Found, with the last item found inside the first **two thirds** of the clock | the speed star, personal only (§11 says why time is never ranked) |
| **Sharp Eye** | Found, **at most one** search of a prop that fit no clue you still needed, and no hint | the careful star. It does not depend on luck: it counts only your misreads, never your unlucky candidates. One slip is allowed because phones mis-tap |

A star, once earned in a chapter, is kept. **Gold Book** = all 45.

---

## 4. Book One

Five bands of three chapters (§7). N items, k candidates per clue, S props, ρ the share of fillers that are partial
matches, room interior W × D studs [C]. The ramp adds one thing at a time: more items, then k from 3 to 5, then the
height clues, then more near-miss decoys.

**Clocks [M 2]** come from the normal profile's uncapped clear time (hint off, no hazards), rounded up to 5 s:
chapters 1-3 at its 97th percentile (learning), chapters 4-15 at its 90th. `design/model.py` stops if its `CLOCKS`
table differs from this derivation.

| ch | band | N | k | S | ρ | forms | room | looks | clock | normal clear p50 (uncapped) | first try, normal: Found / Swift / Sharp | tap-everything solves |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Cottage | 3 | 3 | 16 | 0.25 | K, CK | 32 × 24 | 11 | 70 s | 35.4 s | 0.99 / 0.75 / 0.85 | 0.32 |
| 2 | Cottage | 4 | 3 | 20 | 0.25 | K, CK | 32 × 24 | 14 | 95 s | 50.7 s | 0.99 / 0.74 / 0.80 | 0.21 |
| 3 | Cottage | 4 | 4 | 26 | 0.30 | CK, CH | 40 × 30 | 18 | 120 s | 62.8 s | 0.99 / 0.76 / 0.75 | 0.19 |
| 4 | Library | 5 | 4 | 30 | 0.30 | CK, CH | 40 × 30 | 22 | 125 s | 82.3 s | 0.98 / 0.53 / 0.58 | 0.20 |
| 5 | Library | 5 | 4 | 34 | 0.35 | CK, CH, KH | 44 × 34 | 22 | 130 s | 86.0 s | 0.97 / 0.47 / 0.53 | 0.10 |
| 6 | Library | 6 | 4 | 38 | 0.35 | CK, CH, KH | 44 × 34 | 26 | 155 s | 109.1 s | 0.96 / 0.43 / 0.48 | 0.08 |
| 7 | Greenhouse | 6 | 4 | 42 | 0.40 | CK, CH, KH | 44 × 34 | 26 | 160 s | 110.8 s | 0.96 / 0.42 / 0.45 | 0.06 |
| 8 | Greenhouse | 6 | 5 | 46 | 0.40 | CK, CH, KH | 44 × 34 | 32 | 175 s | 122.4 s | 0.95 / 0.40 / 0.40 | 0.12 |
| 9 | Greenhouse | 7 | 5 | 50 | 0.45 | CK, CH, KH | 48 × 38 | 37 | 210 s | 148.9 s | 0.96 / 0.37 / 0.36 | 0.10 |
| 10 | Ship | 7 | 5 | 52 | 0.45 | CK, CH, KH | 48 × 38 | 37 | 210 s | 151.4 s | 0.95 / 0.33 / 0.29 | 0.08 |
| 11 | Ship | 7 | 5 | 54 | 0.45 | CK, CH, KH | 48 × 38 | 37 | 215 s | 153.3 s | 0.95 / 0.37 / 0.33 | 0.05 |
| 12 | Ship | 8 | 5 | 56 | 0.50 | CK, CH, KH | 48 × 38 | 42 | 245 s | 177.6 s | 0.95 / 0.36 / 0.29 | 0.08 |
| 13 | Observatory | 8 | 5 | 58 | 0.50 | CK, CH, KH | 48 × 38 | 42 | 245 s | 178.0 s | 0.94 / 0.34 / 0.28 | 0.09 |
| 14 | Observatory | 8 | 5 | 60 | 0.50 | CK, CH, KH | 48 × 38 | 42 | 250 s | 181.0 s | 0.95 / 0.38 / 0.30 | 0.06 |
| 15 | Observatory | 9 | 5 | 64 | 0.50 | CK, CH, KH | 48 × 38 | 47 | 275 s | 207.1 s | 0.94 / 0.28 / 0.22 | 0.05 |

"First try" includes the hint policy and hazards [M 2]. The other profiles, first try, Found / Swift / Sharp [M 2]:
**fast** 1.00 / 0.84-0.98 / 0.81-0.99 across the chapters; **slow** 0.93 / 0.48 / 0.42 at chapter 1, falling to
0.49 / 0.06 / 0.01 at chapter 15. A slow player clears the late chapters about every second attempt; Retry is free and
builds a new room.

**What the clue rules are worth, measured [M 2].** The bot (a script with the rules) clears chapter 15 in 33.9 s on
average (27.2 s if it teleports); the sweeper takes 117.8 s (p50) and the normal reader 207.1 s. Every one of them
searches the same number of matching props on average: 26.98 for the bot, 26.94 for the normal reader, against
N(k + 1)/2 = 27 expected. **A script reads faster; it does not search better.** That is why the board never ranks time
(§11).

**Item lists** [C]: a shared pool of 12 small items (key, rubber duck, teacup, coin, gem, toy car, button, marble,
whistle, thimble, pocket watch, little bell) plus 3 per band (Cottage: ball of wool, teddy, cookie; Library: quill,
reading glasses, bookmark; Greenhouse: seed packet, snail shell, tiny gnome; Ship: compass, spyglass, bottle with a
message; Observatory: star map, moon rock, tiny planet). A list never repeats an item. Which item goes with which clue
is drawn independently and is cosmetic. Items are small, so any prop can hold any item.

---

## 5. The Daily Case

| rule | value | why |
|---|---|---|
| when | one per UTC day, `dayIndex = floor(os.time() / 86400)` on the server | the same clock for every server |
| number | Case #`dayIndex - 20732`, so 2026-10-07 (dayIndex 20733, computed) is Case #1 | a counter players can talk about |
| theme | band `((dayIndex - 20733) mod 5) + 1` | public and cosmetic: everyone's Daily is in the same kind of room that day |
| size | N 6, k 4, S 44, ρ 0.40, forms CK/CH/KH, room 44 × 34, 26 looks | chapter 7's size: hard enough to be a case, short enough for a daily visit (2.0 min per attempt, normal p50 [M 5]) |
| clock | **195 s**: the normal profile's uncapped p98, rounded up [M 5] | the Daily feeds the board, so it must be solvable by any careful player. Normal solves on the first attempt 0.994, fast 1.000, slow 0.837 [M 5] |
| opens | after Book chapter 3 is cleared | about 3.0 minutes in for a normal player [M 3]. By then three of the four clue forms are familiar; the fourth (KH) is spelled out by its chip |
| attempts | unlimited, each a fresh room and a fresh secret | a solve is binary, so a retry cannot inflate anything (§11) |
| credit | the **first** Found of the UTC day the attempt **started** on: Daily solved +1, Cases Solved +1, streak | one per day, whatever happens |
| titles | lifetime Daily solves 7 **Detective**, 30 **Inspector**, 100 **Master Finder** [C] | a week, a month, a season of visits |

Tap-everything solves the Daily 3.8 % of the time [M 5]. The rules bot takes 19.6 s [M 5]; it gets the same +1 a
day as anyone.

---

## 6. The world and the server

| thing | value | reason |
|---|---|---|
| MaxPlayers | **12** [C] | a lively hub; 12 lanes |
| walk / jump | WalkSpeed 16, JumpHeight 7.2 | Roblox defaults [S plus1-jump Config] |
| hub | a 64 × 64 "Finder's Agency" at the origin, warm daylight (`Fx.Presets.Cozy`) | [C] runs nothing, so it is always safe |
| HubSpawn | SpawnLocation 6 × 1 × 6 at (0, 0.5, 18), facing −Z | [C] §13 |
| Case Book lectern | (0, 0, 8): 10 studs ahead of the spawn; ProximityPrompt `Open the Case Book`, HoldDuration 0, MaxActivationDistance 8 | a 2-stud walk brings the prompt up (§16) |
| Daily Case door | (18, 0, 10), prompt distance 8 | [C] |
| board | (−18, 0, 10), facing the spawn, prompt distance 10 | [C] about 20 studs from the spawn, readable [STUDIO] |
| lanes | 12, lane i centred at x = −385 + 70 (i − 1), z = −220; indices from a free list, recycled | [C] 18 studs between shells; every coordinate fixed and bounded, |x| ≤ 411 (checklist: unbounded coordinates) |
| lane shell | server-built: floor, ceiling at 16, four walls 1 thick around a 50 × 40 interior, a door mat at the south wall | [C] the largest room is 48 × 38. The ceiling height is the indoor hazard geometry [S escape-room-lab] |
| a chapter's room | client-built inside the shell from the `Room` payload: props, tables, shelves, decor, and screens that close the shell down to W × D | [C] only the owner's client builds it; other players never receive it (§12.3) |
| cards | intro 3.0 s (1.5 s on a retry), clear or time's-up card 4.0 s, the move 1.0 s | [C] the model's overheads |

**Why client-built props cost no security.** A player's character physics runs on its own client, so collisions
with props are that client's business anyway. What matters is server-side: reach is checked against the server-seen
root, and the answer comes from server memory.

---

## 7. Environment bands: they follow the Book

**Trigger: the chapter you are in** (`progress = chapter`, the Daily Case uses its theme's band). Bands use
`from = 0, 4, 7, 10, 13` with `fade = 0`, and the glide is the template's `EnvBands.approach` with a **0.8 s
half-life** [S same-door/DESIGN.md §7]: entering a room glides from the hub's look to the band's, and **clearing the
third chapter of a band glides the room you are standing in toward the next band**, as the reward. The light never
changes during a search (only at entry and at the clear), so a clue colour never shifts under a player who is reading
it. Lighting is written at most **10 times a second** [S plus1-jump `Config.Env.LightingHz`]. `EnvBands.luau` is
copied **verbatim** from `plus1-jump/src/shared`, with its spec.

| # | band | chapters | light and colour | scenery (decor, never searchable) | critters | weather | hazard |
|---|---|---|---|---|---|---|---|
| 1 | Sunny Cottage | 1-3 | morning, warm white sun through the window | gingham curtains, rag rug, herbs on the sill, cuckoo clock | a sleeping cat on the sill; butterflies outside | dust motes in the sunbeams | a pinecone from the rafters |
| 2 | Old Library | 4-6 | afternoon amber, reading lamps | tall bookcases, a rolling ladder, a globe | moths circling the lamps | floating dust in god rays | a heavy book off the gallery |
| 3 | Greenhouse | 7-9 | golden sunset through glass, green-gold | ferns, hanging vines, watering cans | butterflies; a frog on a ledge | drizzle beading on the glass, low mist | a flowerpot from the hanging rack |
| 4 | Ship's Cabin | 10-12 | stormy night, lanterns warm against blue portholes | ropes, barrels, a hammock, portholes | a parrot on its perch; fish passing a porthole | rain streaks and far lightning on the portholes only | a crate from the cargo net |
| 5 | Star Observatory | 13-15 | deep violet night, starlight | telescopes, star charts, an orrery | drifting star-motes | twinkling sparkles | a meteorite pebble from a crack in the dome |

The colour values are Studio's call [STUDIO]. The **rules** are fixed and tested (`Bands.validate`):
* **Decor never encodes the secret.** It is placed from the room's public layout and the band, before the secret is
  drawn (§3.3 step 4), never near a particular candidate.
* **Nothing but a hazard ring is red; nothing but a found or hinted thing glows gold.** Every decor, critter, weather
  and lamp colour keeps a minimum RGB distance from both.
* **The four clue colours stay apart under every band's light.** Each band's tint applied to WHITE, YELLOW, BLUE and
  GREEN keeps a minimum pairwise distance, and the lightning flicker is on the porthole panes only, never the room.
* Weather goes through `EnvBands.capRates` (at most 2 emitters, 60 particles/s [S plus1-jump `Config.Budget`]).
  Critters sit above head height or outside windows, are non-collidable and cannot be tapped.

---

## 8. Hazards

`Hazards.luau` is copied **verbatim** from `plus1-jump/src/shared`, with its spec. The adaptation is the config, and
it is escape-room-lab's reviewed indoor config, unchanged [S escape-room-lab/src/shared/Config.luau and DESIGN.md §8]:
every kind has `pitch = 85`, `pitchSpread = 0`, and the glue passes `ctx.pitch = math.rad(85)`, so the template plans
a near-vertical drop from the ceiling onto the player. Indoors, a lane cannot start on screen at a distance, so the
telegraph is the ring, the banner and the object wobbling overhead.

| `Config.Hazards` | value | reason |
|---|---|---|
| `IntervalMin` / `IntervalMax` | **100 / 140 s of exposed time** | [M 4] one hazard per 2.34 minutes of play (p10 2.25, p90 2.45) and **one near-miss per 2.74 minutes** for a normal player on the way to BOOK ONE SOLVED; the standard asks for one per 2-3 minutes. 80-120 gave a near-miss per 2.27 min and 120-180 one per 3.42 [M 4] |
| `speed`, `telegraph`, `commit`, `pass` | 4 studs/s, 3.0 s, **3.0 s**, 0.6 s | [S escape-room-lab] speed × telegraph = 12 studs starts the drop under the 16-stud ceiling. commit = telegraph locks the lane on its first frame, so the ring never moves: stepping out at any time 0.0-1.8 s after it shows dodged 0 of 684, standing still is hit at 2.13 s |
| `hitRadius`, `PlayerRadius` | 2.0, 1.5 | a **7.00-stud ring** [S escape-room-lab]. A hit needs the root inside the ring, so the ring is exactly the hit zone |
| `knock`, `KnockLift`, `KnockSeconds` | 20, 0, 0.6 | a stumble, not a launch [S escape-room-lab] |
| `MinTelegraphSeconds`, `MinCommitSeconds`, `MaxRetargetSpeed`, `AimJitter`, `SpreadDegrees`, `ViewPitchDegrees`, `KindFitDegrees` | 3, 1.5, 1.5, 0.8, 0, 20, 25 | [S escape-room-lab] |
| kinds | pinecone, book, flowerpot, crate, pebble: one per band, identical numbers | only the look differs; none is red or gold |

**Rules.**
* **Exposed time** is a live attempt, not paused, past a 5-second arrival grace, with the root on a **legal spot**:
  inside the room shrunk by 4 studs and more than 4 studs from the door mat, so the ring always fits on the floor and a
  3.9-stud step out always exists. Anywhere else the glue passes `ctx.resting = true`, so the clock **freezes** and
  nothing backs up. This is escape-room-lab's review finding B4: a hazard that came due where it could not be released
  was held and fired the instant the grace ended [S escape-room-lab/DESIGN.md §8.2].
* **Never two at once** (the template's scheduler). The hazard clock persists across chapters and is never reset.
* **A hit costs a little, never a run:** a 0.6 s stumble, a camera shake, a white flash. No look, no item and no star is
  ever taken. The model counts 2.0 s per hazard dodged and 0.6 s more per hit [A]; the normal profile meets 14 on the
  way to BOOK ONE SOLVED [M 3].
* **Client-side**, as in +1 Jump: a hazard can only touch its own player's character, whose physics that client owns.
  The server never hears of it. A cheater who deletes hazards saves the stumbles a careful player never takes.

---

## 9. Rest and pause

`Rest.luau` is copied **verbatim** from `plus1-jump/src/shared`, with its spec, under escape-room-lab's config
[S escape-room-lab/src/shared/Config.luau]: `WakeOnMove = true`, `BlockWhileThreat = true`, `RequireGrounded = true`,
`WakeGraceSeconds = 0.4`, `PendingSeconds = 6` (the longest drop is 3.6 s, plus 2.4 s to stand still), and
**`IdleSeconds = 0`**: standing still is how a room is read, and an idle rest would switch off hazards for every
player who stops to look.

**The pause button** (top-right, in a room). It goes through `Rest.request`, so it cannot start mid-air or with a
drop on its way: it is queued (`Pausing after the drop...`), the drop still comes, and stepping out of the ring keeps
the request. When it starts, the client sends `Pause`, and the server:
1. **stops the chapter clock** and refuses `Search` and `Hint` (`You're on a break: move or tap Resume`);
2. dims the room behind a card: `Paused. The clock is stopped. While you rest, things get moved around.` with
   **Resume** and **Hub**.

**Resume** (the button, or any move: `WakeOnMove`) sends `Resume`, and the server **re-dresses the room**: every prop
moves, and every item still on the list gets a fresh clue that fits **exactly as many props as that item had
unsearched candidates**, and a fresh hiding spot among them. Found items stay found, the looks are unchanged, and the
clock runs again. A hinted item's count is 1, so its new prop sparkles again. The server applies a Resume no sooner
than **3 s** after the Pause [C], which caps re-dresses at one per 3 s per player.

**This deviates from the template's advice, on purpose.** `Rest.luau`'s header says a game must not map rest onto a
clock players race, because a frozen clock is free thinking time. Here the frozen time buys nothing: everything a
player could study while paused (where props are, which ones fit) is replaced on resume, and what they had already
earned (which candidates they had ruled out) is kept as a smaller candidate count, so nothing is lost either.

**Measured [M 7].** With a pause before about one search in seven, careful players ran out of looks **0 times in
20 000** attempts in each of chapter 1, 7, 15 and the Daily; with 7 % slips, pausing changed the out-of-looks count by
in the tens per 20 000 with or without pauses (ch1 48 with vs 44 without, ch7 9 vs 13, ch15 2 vs 2, Daily 13 vs 3). A tap-everything player who
pauses every time its looks run short solves **less** often than one who never pauses (ch1 0.189 vs 0.292, ch7 0.020
vs 0.046, ch15 0.024 vs 0.052, Daily 0.015 vs 0.033), because a re-dress puts the props it had already emptied back
into the room. The rejected rule, a pause that resets clues and looks, raised those to 0.525, 0.228, 0.208 and 0.287.

**Why it can never be an exploit:** the hazard clock freezes and is never reset (the template, measured by its
spec); the chapter clock freezes, but nothing studied while paused survives the resume; looks are never refilled;
nothing can be searched while paused; nothing accrues while paused. **Hub** abandons the attempt, which costs nothing
because nothing of an unfinished attempt is ever saved. Between chapters the hub is always safe: it runs nothing.

---

## 10. The brag moment and the long-term goal

### 10.1 The pacing model [M 3]

1000 simulated players per profile play Book One from a fresh join: session start 4 s, then for each chapter the
intro card, the move, attempts until Found (with the hint policy and hazards on a hazard clock that persists), and the
clear card. Retries are fresh rooms. Then, for the long-term goal, replays of every chapter still missing a star.

| | fast | **normal** | slow | sweeper |
|---|---|---|---|---|
| **BOOK ONE SOLVED** (min from join) | 24.7 [22.7-26.7] | **33.4 [30.4-38.3]** | 63.9 [48.8-85.2] | 20.6 [19.8-21.4] |
| attempts to clear the Book (p50) | 15 | 15 | 23 | not run |
| minutes per band: Cottage / Library / Greenhouse / Ship / Observatory | 2.2 / 3.8 / 5.0 / 6.2 / 7.2 | 3.0 / 5.0 / 6.6 / 8.3 / 9.7 | 3.8 / 8.0 / 11.7 / 16.3 / 20.1 | not run |
| **Gold Book** (45 stars), min from join, p50 (p90) | 30.3 (37.0) | **104.9 (143.8)** | not within 600 min for 998 of 1000 | 30.1 |
| first find, s from join (p50) | 15.2 | 18.1 | 22.6 | not run |
| chapter 1 cleared, s from join (p50) | 36.7 | 46.9 | 58.8 | not run |

Brackets are p10-p90. The normal p50 is inside the owner's 30-45 minutes. **The uncertainty is the human model, and it
is stated:** a player who sweeps the room systematically instead of scanning for each clue reaches the brag at 20.6
minutes; the first real play sessions decide which is closer, and the chapter table is what gets retuned, not the
profiles. Every band lasts at least 3.0 minutes for the normal profile. For slow players the summit is the Book and
the Daily Cases; the Sharp Eye star on late chapters is out of their reach (0.01-0.05 per attempt [M 2]).

`tests/Pacing.spec.luau` (§19.2) will assert: the normal p50 BOOK ONE SOLVED within [30, 45] minutes; fast ≤ normal ≤
slow; every band's normal p50 at least 2.5 minutes; the normal first-try Found at least 0.90 in every chapter; a
careful player never out of looks; and the normal near-miss interval within [2, 3] minutes of play.

### 10.2 The brag: "BOOK ONE SOLVED"

The first clear of chapter 15. The observatory dome slides open, the telescope swings up, and gold shooting stars
cross the sky; a white flash and an FOV punch (`FxClient`), and the card `BOOK ONE SOLVED · You found all 93 things`
(the sum of N over the fifteen chapters [R]). Every player in the server gets the notice `<DisplayName> solved Book
One!`. The profile stores `bookSolvedAt`, the player's name tag gains a gold magnifier, and the hub's Case Book turns
gold for them. A signpost from the first minute: the Case Book's last page shows the observatory, locked.

### 10.3 The long-term goals

* **Gold Book**: every chapter at three stars. Normal p50 104.9 minutes from join [M 3].
* **The Daily Case**: a streak, and the titles Detective (7), Inspector (30) and Master Finder (100 lifetime solves).
* **The board**: Cases Solved keeps growing by one a day for anyone who comes back (§11).

---

## 11. The board: Cases Solved

**Metric: Cases Solved = Book chapters cleared (at most 15, first clears only) + Daily Cases solved (at most one per
UTC day).** Higher is better; ties go to whoever reached that number first.

* **Store:** OrderedDataStore `FindIt_Solved_v1`, key `u_<userId>`, value `solved * 2e9 + (2e9 - reachedAtUnix)` (the
  standard's encoding, `Board.luau` copied from `plus1-jump/src/shared` with its spec). After ten years of Daily
  Cases the largest value is 7.336e12, under 2^53 = 9.007e15 [M 6]. The tie-break term turns negative after
  2033-05-18 (unix 2e9) and the order still holds, because two reaches of one count are never 63 years apart
  [S plus1-jump/src/shared/Board.luau].
* **Written** only by the server, only when `solved` rises, with an `UpdateAsync` that keeps the larger value, and
  only **after** the profile write carrying the new count has landed [S escape-room-lab/DESIGN.md §11.1]; `boarded`
  in the profile remembers what was written, and a failed board write is retried at the next autosave.
* **Public:** `GetSortedAsync(false, 10)`, cached server-side for **60 s** (1 call a minute against 5 + 2 × 12 = 29
  allowed [DOC]).
* **Friends:** `Players:GetFriendsAsync`, capped at **200**, fetched only when a player toggles the board, cached for
  **300 s**; each friend not in the server is one ordered `GetAsync`, made only while
  `GetRequestBudgetForRequestType(GetAsync)` stays above a reserve of **20** (60 + 40 × 12 = 540 allowed a minute
  [DOC]); all pcall'd, with `Checking your friends: n of m...` while it fills [S same-door/DESIGN.md §10]. Empty:
  `None of your friends has solved a case yet. Invite one: every room is different, so nobody can tell them where
  things are.` The emulator has no `GetFriendsAsync`; the headless check stubs it.
* **Names:** `GetNameFromUserIdAsync`, pcall'd, cached per server (at most 500); never stored.
* **In the world:** the physical board in the hub, facing the spawn. The public face is server-built; a ProximityPrompt
  (`Show friends` / `Show public`) toggles a local SurfaceGui for that player only. Rows: rank, name, Cases Solved.
* `leaderstats.Solved` (an IntValue) shows the same number, public by design.

**Why a script cannot inflate it.**
1. **Server-counted.** It rises only when the server's own attempt state machine sees every item found by searches it
   answered, in time and within the looks. No remote carries a find, a count, a time or a credit.
2. **Bounded by the calendar.** At most 15 from the Book, ever, and at most one a day from the Daily. A script that
   plays perfectly gets exactly what a careful player who visits daily gets: it cannot go higher, and hopping servers
   or rerolling attempts adds nothing, because a day credits once (§12.1).
3. **Luck cannot be farmed.** Solving is binary, and the normal profile solves the Daily on the first attempt 0.994 of
   the time [M 5], so best-of-many attempts has nothing to improve.
4. **Time is never ranked.** The rules bot clears chapter 15 in 33.9 s against a normal reader's 207 s [M 2], and a
   travel-limited script beat an expert 9.8 s to 86 s in lost-found-depot [S lost-found-depot/DESIGN.md §10.3]. A
   time board would be the bots' board.

**The residual, stated.** Ties go to whoever reached a count first, so a bot that clears the Book quickly at launch
and solves each Daily just after 00:00 UTC leads its tie group, and so does a human in a time zone where 00:00 UTC is
the afternoon. It can never pass a player with a higher count. And a lifetime count favours whoever started earliest:
a newcomer reaches the top 10 only by outlasting it. The friends board always compares. A monthly scope is the
alternative (§22).

---

## 12. Data model

### 12.1 What persists (DataStore, everything pcall'd)

| store | key | content |
|---|---|---|
| `FindIt_Players_v1` | `u_<userId>` | `{ v = 1, session = "<guid>", lockUntil = <unix>, book = { cleared = <0..15>, stars = { c1 = { f = true, w = false, s = true }, ... } }, daily = { lastDay = <dayIndex>, solved = <int>, streak = <int>, bestStreak = <int> }, solved = <int>, solvedAt = <unix>, boarded = <int>, bookSolvedAt = <unix or nil>, seenIntro = <bool>, firstJoin = <unix> }` |
| `FindIt_Solved_v1` (ordered) | `u_<userId>` | the encoded Cases Solved (§11) |

* **String keys only** (`c1`..`c15`), so JSON cannot turn sparse integer keys into strings (checklist trap).
* **Session lock with an owner token** [S fork-tower/REVIEW-4.md §10]: the load that takes the lock writes a fresh
  `HttpService:GenerateGUID(false)` as `session`, and every write lands only while the record still carries it; a write
  that finds another token is cancelled, sets `canSave = false`, and the player is told. Autosave every **20 s** under
  a **45 s** lock [S plus1-jump `Config.Save`: autosave must be shorter than the lock].
* **A clear is one atomic `UpdateAsync`**: stars, `book.cleared`, the Daily credit, `solved` and `solvedAt` in one
  transform. A one-time grant (a first clear, a day's credit) happens only inside it, and only while holding the lock;
  a session that cannot save says so on the clear card (`This server can't save your progress right now`) and grants
  nothing. Writes to one key stay at least 6 s apart [S fork-tower/REVIEW-4.md §9.3]: a clear flush waits until 6 s
  after the key's last write and pushes the next autosave back 20 s, and two clears are always at least 6.5 s apart
  anyway (the clear card 4.0 s, the move 1.0 s and the shortest intro 1.5 s [R]).
* **The Daily credit** checks `daily.lastDay < startDay` inside the transform, so two servers cannot both credit one
  day. The streak continues if `lastDay` is yesterday and restarts at 1 otherwise.
* **Nothing about an attempt is ever persisted**: not the room, not the secret, not progress inside an unfinished
  attempt. This closes fork-tower's read-only-session oracle at the root [S fork-tower/REVIEW-4.md §9]: there is no
  saved secret for any session to reveal.

### 12.2 What is server-only (never an Instance or attribute a client can see)

* Each live attempt: the hidden prop id per item, the clue-to-candidate sets, the searched set, looks, the clock, the
  hint, the pause state, the off-clue count. In server-script memory, with one copy as a JSON StringValue in
  `ServerStorage.FindIt.Attempts.<userId>` for headless checks and the filming rig ("ServerStorage, not the zone"
  [S anomaly-observatory/CLAUDE.md]).
* The generators: `Dressing.luau`, `Hide.luau` and `Attempt.luau` are ModuleScripts in ServerScriptService. Their code
  is not the secret (the draws are), but they have no reason to replicate.
* Profiles, the name cache, the friends cache.

### 12.3 What replicates, and why each is safe

| what | to whom | why it is safe |
|---|---|---|
| hub, lane shells | everyone | identical for every player and attempt |
| characters, the gold-magnifier name tag | everyone | a public achievement |
| `leaderstats.Solved` | everyone | public by design |
| `Room` payload (props with id, traits, position, yaw, variant; screens; decor; band) and the clues | the owner only | built **before** the secret is drawn and byte-identical whatever it is (§3.3, gated in §19.3); ids and positions are dealt to a shuffled list |
| `Result` (prop id, hit or miss, item id on a hit, off-clue flag) | the owner only | answers only the prop that was searched, after the fixed 1.0 s |
| `State` (clock start and length, paused, looks, found list, stars at the end) | the owner only | nothing about unsearched props |
| `Hint` reply (one prop id) | the owner only | the player spent the hint on exactly that |
| board rows | everyone / the asker | names and counts, public by design |
| ReplicatedStorage modules: `Config`, `Rng`, `Fx`, `FxClient`, `Responsive`, `EnvBands`, `Hazards`, `Rest`, `Clue`, `Stars`, `Ledger`, `Board`, `Bands` | everyone | none of them can produce a hiding spot: there is no seed, and the draw function is server-only |

### 12.4 Remotes (`ReplicatedStorage.FindItRemotes`)

Server to client: `Room`, `State`, `Result`, `Toast` (the reason for every refusal), `Notice` (the brag, to all),
`Board`. Client to server, each checked against the attempt state and rate-limited: `Open(chapter)` and `OpenDaily()`
(from the Case Book menu and the Daily door; 1 per second), `Search(id)` (one in flight), `Hint(item)` (once per
attempt), `Pause()` / `Resume()` (Resume applied no sooner than 3 s after Pause), `Next()` / `Retry()` / `Hub()` (card
buttons; 1 per second). Malformed payloads (NaN, huge numbers, strings, tables where an integer belongs) are dropped;
the honest HUD cannot send them, so no player is left without an answer. Prompts (lectern, Daily door, board toggle)
are handled server-side.

---

## 13. Spawn placement (`robloxemu/SPAWN-ORDER.md`)

* **Exactly one enabled SpawnLocation**, `HubSpawn` (§6). The headless check asserts it is the world's only enabled
  spawn.
* `plr.RespawnLocation = HubSpawn`, set in `PlayerAdded` **before** the profile load yields and before the character
  loads. The engine's own placement is then correct, and **`CharacterAdded` never writes a CFrame**, so there is no race
  to lose.
* **Entering a room** is a server `PivotTo` onto the lane's door mat after a prompt or card button, long after the
  character is parented, so it is not the spawn race. The lane shell (floor included) is server-built at server start,
  before any move (deep-vein: build the landing first).
* A reset or death in a room ends the attempt (`Humanoid.Died` / `CharacterRemoving`), and the engine respawns the
  player on `HubSpawn`. No mid-room respawn placement exists.

---

## 14. Anti-exploit model

| threat | defence | residual |
|---|---|---|
| read where things are from replicated data | the secret is drawn after the room payload is built and is never sent before a find or a hint (§3.3, §12) | none found; gated by the predictor check (§19.3) |
| compute it from a seed or a public generator | no seed exists; every draw is `life ⊕ fresh` server entropy. Recovering it means recovering Roblox `Random` state from a few bits per find | reasoning, not measurement (fork-tower REVIEW-4 §8.2 has the same caveat) |
| use the posterior better than a person | candidate sets are disjoint and the hiding spot uniform, so "one of these k" is the whole truth: the bot and the normal reader search 26.98 and 26.94 matching props in chapter 15 [M 2] | a script reads faster (unranked) |
| tap everything | looks = N × k + 2 (§3.5): tap-everything solves 5-21 % from chapter 2 on [M 2] | it loses Sharp Eye and mostly fails; it can still solve sometimes |
| pause to study, or to refill | re-dress on resume, looks unchanged (§9) | pausing lowers a tap-everything player's odds [M 7] |
| read-only session or crash as an oracle (REVIEW-4 §9) | nothing about an attempt is persisted | none |
| a late or stale write over a newer session (REVIEW-4 §10) | owner token on every profile write | none found |
| credit a Daily twice (two servers, a rejoin) | `lastDay` checked inside the one atomic transform | none |
| forged remotes | no remote carries a find, a time, a count or a credit; ids are looked up in the sender's own attempt; one search in flight; hint once; malformed payloads dropped | none |
| search from anywhere (teleport) | reach checked against the server-seen root, +2 slack | **not policed in v1**: a teleporter saves walking. Nothing ranked depends on time, every search still costs a look and 1.0 s, and the board counts solves. It buys only the Swift star, which is personal |
| speed hack | as teleport | as teleport |
| delete hazards | client-side, own character only | saves stumbles |
| a clock trick | the clock is the server's Heartbeat sum | none |
| scan during the intro card | the card covers the room for an honest player; a script that ignores it gets 3 s | unranked |
| the bot | it plays the rules | the board residual in §11 |

Every refusal says why (§17.2). Every void or cancelled write is logged server-side with its reason.

---

## 15. Fair monetization

v1 sells nothing: no gamepasses, no developer products, no paid hints, no paid looks, no paid time, no paid private
servers. No gambling: no spins, crates or mystery rewards. No AFK rewards: nothing accrues while you stand still, and
the clock runs only in a live attempt. No promo codes (nothing to grant). If anything is ever sold, it is cosmetic
only (a magnifier skin, a found-burst colour that is not gold), and never looks, hints, time or the Daily.

---

## 16. The first 60 seconds of a new player

Model medians [M 3] plus the geometry in §6. The headless walk measures the real path.

| t | what happens |
|---|---|
| 0 s | spawn on `HubSpawn`, facing the Case Book on its lectern 10 studs ahead, glowing; the board on the left, the Daily door on the right (`Opens after Chapter 3`). Hint: `Walk to the Case Book and press E (tap Open)` |
| ~1-4 s | a 2-stud walk brings the prompt up. Tap it. A first-time player goes straight into Chapter 1 (no menu): the core action within about 5 s (the model allows 4 s) |
| ~5 s | in the Sunny Cottage, on the door mat (the move takes 1 s). The intro card: `Find 3 things! Each one hides in something that fits its clue. Tap to look, tap again to search.` |
| ~8 s | the 3-second card closes and the clock (70 s) starts. Clue 1's three candidates are the three props nearest the door |
| **~18 s** | **the first find** (p50 18.1 s from join [M 3]): a gold burst, the chip turns gold, a chime |
| **~47 s** | **Chapter 1 cleared** (p50 46.9 s from join [M 3]): the card with its stars and **Next chapter** |

---

## 17. HUD and feedback, phone first

### 17.1 Layout

A root Frame owns a `UIScale` (`Responsive.luau` copied verbatim from a sibling, `docs/mobile-ui-brief.md`). Tap
targets are at least **44 screen px**, nothing tappable sits in the bottom-left or bottom-right thumb zones, the
layout is redone on `ViewportSize`, and **hudcheck runs with `overlap = true`**.

* **Top-left:** the chapter chip (`Ch 7 · Greenhouse`), not tappable.
* **Top-centre:** the clock, large, and the looks counter (magnifier icon and a number) beside it.
* **Under them, the list:** one chip per item (up to 9), each showing the item and its two clue glyphs; a found chip
  turns gold. Tapping a chip opens a callout with the clue in words and the **Hint** button. In the compact layout the
  chips are 44 × 44 glyph-only and the callout carries the item.
* **Top-right:** the Pause button.
* **Bottom-centre, between the thumb zones:** the selection bar when a prop is selected: its label
  (`BLUE BOX · HIGH`) and **Search**.
* **Centre:** cards (intro, clear, time's up, out of looks, paused, BOOK ONE SOLVED) and the Case Book menu (Continue,
  then the chapters with their stars).

### 17.2 No silent no-ops: every refusal and its words

| the player | the answer |
|---|---|
| taps decor | `Nothing to search there` (client) |
| taps a prop out of reach | `Walk closer: you can search things within 10 studs` (client; the server repeats it if asked) |
| searches before the clock starts | `Get ready...` |
| searches during a search | `One search at a time` |
| searches while paused | `You're on a break: move or tap Resume` |
| searches after time or with no looks | `Time's up` / `No looks left` |
| searches a searched prop | `Already searched` (free) |
| searches a prop that fits no clue still needed | the miss, plus `That WHITE BASKET doesn't fit any clue you still need` |
| a second hint | `You've used this chapter's hint` |
| Hint with no chip chosen | `Tap a thing on your list first` |
| opens a locked chapter / the Daily early | `Clear Chapter N first` / `The Daily Case opens after Chapter 3` |
| pauses during a drop | `Pausing after the drop...` |
| plays in a read-only session | `Your progress is open in another server. This session won't save.` |
| a clear that cannot be saved | on the clear card: `This server can't save your progress right now` |

### 17.3 Fx from the first build

`Fx.applyLighting(Fx.Presets.Cozy)` in the hub; bands set the room look on the client. Signature particles: the
**gold found-burst** (the thing you chase glows, `Fx.sparkle`) and the **hint glint**; props get a faint rim on hover
or selection, so they read as interactive. Camera juice: `FxClient.fovPunch` on a clear, `flash` + `shake` on a hazard
hit, `flash` + `fovPunch` on BOOK ONE SOLVED. HUD frames through `FxClient.theme()`.

---

## 18. Budgets (capped in code, measured headless)

| budget | cap | reasoning |
|---|---|---|
| client local parts in a room | **280** | [M 1] the worst of 3900 generated rooms needs 171 for props, tables and shelves; plus capped extras (4 screens, 40 decor, 10 critter parts, 27 found items, 3 hazard, 4 lamps) = 259. 280 leaves 21 (8 %) of headroom |
| client lights | **4** | the room's lamps |
| emitters | **4** | 2 weather (via `capRates`), the found-burst, the hint glint |
| emitter rate | **60/s** | [S plus1-jump `Config.Budget`] |
| critters | **6** at once | each 1-2 parts |
| server parts | hub ≤ 160 + 12 lane shells × 9 | fixed, independent of attempts |
| DataStore at 12 players | profile writes about 36 autosaves + about 6 clears a minute against 540 allowed; ordered writes at most about 6 a minute against 90 [DOC] | §11, §12 |

---

## 19. Build plan (short)

### 19.1 Files (deep-vein's layout)

`default.project.json`: `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts, `src/shared` →
ReplicatedStorage. `.gitignore` covers `publish_*.bat` and `publish_*.sh`. Shared modules take their dependencies as
arguments (`require("./X")` resolves in the CLI and is invalid in Roblox).

* **Shared (pure):** `Config`, `Rng`, `Fx`, `FxClient`, `Responsive`, `EnvBands`, `Hazards`, `Rest`, `Board` (verbatim
  copies); `Clue` (traits, forms, matching, glyphs, words); `Stars`; `Ledger` (Daily credit, streak, titles, Cases
  Solved); `Bands` (validation).
* **Server:** `Main.server.luau`; `Dressing.luau` (§3.3 steps 1-4, the re-dress with per-item counts); `Hide.luau`
  (step 5, the draw function); `Attempt.luau` (the pure state machine: clock, looks, search answers, off-clue, hint,
  pause, stars).
* **Client:** `Hud.client.luau`, `Room.client.luau` (build from payloads, pick, select, bands, hazards, rest glue),
  `RoomArt.luau` (prop silhouettes, decor, critters, weather, item models).

### 19.2 Unit specs, each watched failing before its module exists

`Dressing.spec` (exact k, disjoint, partial share, spacing, door clearance, ids dealt after a shuffle, re-dress keeps
each count, no subsumed clue pairs), `Hide.spec` (uniform over candidates, chi-square; independent of ids and
positions; the payload is unchanged by re-drawing the secret), `Attempt.spec` (looks, the 1.0 s answer for hit and
miss, repeat search free, off-clue count, hint once, pause/resume rules, clock, stars), `Clue.spec`, `Stars.spec`,
`Ledger.spec` (one credit per dayIndex, streaks across UTC days), `Board.spec`, `Bands.spec`, the verbatim
`EnvBands`/`Hazards`/`Rest`/`Responsive`/`Rng` specs, and `Pacing.spec` with `tests/FinderModel.luau` (the port of
`design/model.py` Parts 2-3; its assertions are in §10.1).

### 19.3 Headless gates (rebuild the bundle before every run)

`cd robloxemu && py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau`, then:

* `check_finditchapters.luau`: **walks the real player path.** Join, `HubSpawn` is the only enabled spawn and the
  character lands on it, the lectern prompt, Chapter 1 room, read the secret from `ServerStorage` (the rig), walk to
  each prop and `Search` it as the client does, clear, Next, through Chapter 3, the Daily opens and is solved, the
  profile and the board are written, rejoin keeps progress, a second Daily solve the same day credits nothing.
* `check_finditchapters_secret.luau`: **the predictor check**, after fork-tower's part A: over at least 1000 finds,
  every predictor built only from replicated data (the payload's order, ids, positions, traits; every attribute in
  the client-replicated services) names the hidden prop no better than chance, |m − n/k| within 4.9 standard
  deviations of Binomial(n, 1/k); the `Room` and clue payloads are **byte-identical** when only the secret is
  re-drawn; no `Result` before a find carries the hidden id; after a resume, predictors built from the pre-pause room
  are at chance. **Planted-leak control:** the hidden id written as a workspace attribute, as a player attribute and
  in a `Toast` payload must each be caught.
* `check_finditchapters_cheat.luau`: every row of §14 that has a defence: forged ids, out of reach, during a search,
  paused, no looks, after time, two searches in one frame (one look spent), hint twice, Resume within 3 s, a
  read-only session cannot credit, two servers cannot credit one day, the owner token.
* `_hud` (overlap = true, phone viewports), `_bands`, `_budget`, `_hazards` (rate, ring = zone, frozen off legal
  spots), `_rest`, `_board`. Every new assertion is mutation-tested with a control that must survive.

### 19.4 Traps this game has (for its `CLAUDE.md`)

1. The room payload must be built before the secret is drawn and must not change with it.
2. Ids and positions are dealt after a shuffle; never in generation order.
3. A hit and a miss are answered after the same 1.0 s.
4. Found items are built by the owner's client only.
5. A re-dress keeps each item's unsearched-candidate count and never touches the looks.
6. Nothing about an attempt is persisted.
7. The Daily credit is decided inside the atomic clear transform, by the start day.
8. The board is written only after the profile write lands.
9. `CharacterAdded` never writes a CFrame.
10. Where no hazard may come, the glue passes `resting = true` (never a held hazard).
11. Clocks are Heartbeat sums, never `os.clock`.
12. Star keys are strings (`c1`..`c15`).
13. The Studio shot room (§21.2) runs only when `RunService:IsStudio()` is true and saving is off; a live server
    with a failing store never takes it.

---

## 20. Needs Studio (only real rendering, input, devices or a live server can settle these)

1. **Tap-pick on a phone:** selecting a jar on a high shelf from 10 studs; the outline and label readable; drag to
   turn the camera never selects.
2. **The traits read:** the 8 silhouettes at 15+ studs on a phone; FLOOR / TABLE / HIGH unambiguous from eye level in a
   16-stud room with a ceiling.
3. **Colours under every band**, including colour-blind simulation; the label chip as the fallback.
4. **The HUD row of 9 chips** on a notch phone; the callout; 44 px everywhere; the selection bar clear of the
   thumbstick and jump button.
5. **Hazards indoors:** the ring readable on rugs and clutter; the wobble overhead visible; the 0.6 s stumble's feel.
6. **Pause:** the dim, the re-dress on resume (does it read as "things moved", not a glitch?).
7. **Search feel:** the 1.0 s rummage, the gold burst and the fly-to-chip.
8. **Frame time** on a low-end phone at 280 local parts, 4 lights and 4 emitters.
9. **Payload latency:** a 64-prop `Room` payload on 4G; how long the room takes to appear.
10. **Client-built rooms:** collisions with props; no snagging in aisles; the screens hold.
11. **The PivotTo into a lane:** no fall, no camera snap.
12. **Desktop:** click to select, click or E to search.
13. **The board's** SurfaceGui legible from the spawn; the toggle prompt.
14. **BOOK ONE SOLVED:** the dome, the shooting stars, the fanfare.
15. `Random:NextInteger(0, 4294967295)` and `bit32.bxor` on values ≥ 2^31 (fork-tower REVIEW-4 §8.1).
16. `GetFriendsAsync` paging on a real account; the friends fill time under the real budget.
17. The 00:00 UTC rollover in a live server (headless covers the logic with an overridden `os.time`).
18. Place settings: MaxPlayers 12.
19. The Studio shot room with API access off (§21.2).

---

## 21. Ship and market: seeds for README, EYECANDY and MARKETING

### 21.1 Store text (for `README.md`)

**896 characters, ASCII only, no emoji** [M 6]; the draft is `design/store.txt`. It says: a hidden-object game where no
room is the same twice; a list with clues like "a BLUE BOX"; tap to search before the clock runs out; limited looks;
15 chapters in five themes; every attempt rearranged; three stars; a Daily Case at 00:00 UTC; red rings; pause that
stops the clock and moves things; public and friends boards; nothing to buy.

### 21.2 Thumbnail shot list (for `EYECANDY.md`, 1920 × 1080, subject inside the middle 1280 px)

Shots use a **Studio shot room**: only when `RunService:IsStudio()` is true and saving is off, `Config.Studio.ShotSeed`
makes the dressing and the secret deterministic, so a shot can be framed twice. Nothing is saved or ranked there.

1. **Hero, Ship's Cabin:** over the shoulder at lantern height, a chest on a table bursting gold as a compass pops
   out; portholes with rain behind; HUD hidden.
2. **Library shelves:** low angle up a bookcase wall, a yellow jar on the top shelf mid-burst, a gold item in the air.
3. **BOOK ONE SOLVED:** inside the observatory, the dome open, shooting stars, the avatar's back to camera.
4. **The ring:** the greenhouse at sunset, the red ring at the avatar's feet, the flowerpot wobbling overhead.
5. **The hub:** the gold Case Book on its lectern, the board behind, three avatars.

### 21.3 Clip list (for `MARKETING.md`: vertical 1080 × 1920, 7-15 s, `tools/film_game.py`)

1. **Last item, four seconds left:** the clock at 0:04, the final search, the burst, CLEARED.
2. **Read the clue:** the chip `something YELLOW up HIGH`, a pan along the shelves, two taps, found.
3. **Wrong one:** a BLUE BASKET for "a BLUE BOX", the dust puff and its line, then the right box.
4. **Step out of the ring:** a book falls in the library; a sidestep; it lands a stud away.
5. **Pause:** the room dims, Resume, the props shuffle into new places.
6. **BOOK ONE SOLVED:** the dome opening and the shooting stars.
7. **The Daily Case:** the door in the hub opening on Case #N, the board flipping to Friends.

Staged in the Studio shot room by walking and tapping; a clip never fakes a find.

---

## 22. Open decisions for the owner (defaults in force until he says otherwise)

1. **The board metric.** Default: Cases Solved, lifetime (§11). Alternatives: the same count scoped per month (fresh
   each month; ties then go to who solved each Daily earliest), or Book stars (capped at 45, so the top 10 freezes once
   ten players have all 45: escape-room-lab's review B5).
2. **The brag's timing.** Default: chapter 15, normal p50 33.4 minutes, with the sweeper sensitivity at 20.6. If real
   players sweep, the retune is more items or more chapters, not a slower clock.
3. **Pause freezes the clock**, with the re-dress (§9). The alternative is same-door's: the clock never stops and the
   pause button leaves the attempt.
4. **Looks.** "Out of looks" is a second way to fail; it is what makes reading the clues the right way to play (§3.5).
5. **MaxPlayers 12.**

---

## 23. Reproducing the numbers

`design/model.py` is a measurement tool, not game code; Rojo never maps it. From `find-it-chapters/`:

| command | prints |
|---|---|
| `py -3 design/model.py --part 1` | generator acceptance, exact-k/disjoint check, uniform hiding (chi-square), the parts worst case |
| `--part 2` | the clock derivation (it stops if `CLOCKS` differs), first-try stars per profile, out-of-looks counts, the bot / teleport / tap-everything rows, the sweeper |
| `--part 3` | BOOK ONE SOLVED, minutes per band, Gold Book, first find, chapter 1 cleared, hazards met, the sweeper career |
| `--part 4` | hazard and near-miss rates for intervals 80-120, 100-140 and 120-180 |
| `--part 5` | the Daily clock derivation, solve rates, minutes per attempt, tap-everything, the bot |
| `--part 6` | the board's largest encoded value; the store text length |
| `--part 7` | the pause rule against the looks budget, and the rejected reset rule |

`design/model.out.txt` is the full output of the run these numbers come from.

---

## 24. Self-review

* **Standard, item by item:** each line of `docs/complete-game-standard.md` is mapped in §0 and answered where it
  points. Things the standard asks for that a spec cannot do yet (green gates, mutation tests, Studio checks) are in
  §19 and §20 as work, not claimed as done.
* **Placeholders:** none. Every number carries a tag; the human assumptions are [A] and listed in one table (§0).
* **Contradictions checked:** looks = N × k + 2 in §3.5, §4 and §5 (Daily 26); clocks in §4 equal `CLOCKS` in the
  model (Part 2 stops otherwise) and the Daily clock 195 s in §5 equals Part 5's; bands `from = 0, 4, 7, 10, 13` match
  the chapter ranges in §4 and §7; the hazard interval 100-140 s is the one Part 3 and Part 4 run with; the brag sum
  of N (3+4+4+5+5+6+6+6+7+7+7+8+8+8+9 = 93) matches §10.2; the store text's claims match §3-§11.
* **What is a model, not a measurement of the game:** every [M] number. The largest uncertainty is the human noticing
  time, which moves the brag between 20.6 (sweeper) and 33.4 (normal) minutes; it is stated in §10.1 and §22.
* **Cut rather than thin:** §2. The two mechanics the spec added beyond the brief, looks and the pause re-dress,
  are there because the model showed the game broken without them (§3.5, §9), not as features.
