# Lost & Found Depot — design spec (v1)

**Status: design only.** No game code exists yet. Nothing is committed, pushed or published, and no
universe exists. Written 2026-09-16 from the round-2 radar brief
(`docs/game-radar/2026-09-06-roblox-game-radar-round2.md`, "Lost & Found Depot" and its ranked entry
"Organizing / sort-and-restore job sim") and the "What players want" / "Avoid solo" sections of
`docs/game-radar/2026-09-14-roblox-game-radar.md`.

## How to read the numbers

Every number in this file carries a tag saying where it came from.

| tag | meaning |
|---|---|
| **[M n]** | Printed by Part *n* of `design/model.luau`. Run it with `luau design/model.luau 2>&1` (about 90 s, deterministic). The model is a design-time tool, not game code. |
| **[S]** | Measured in Roblox Studio **on a sibling game**, with the file cited. It is not a measurement of this game. |
| **[R]** | Arithmetic or a stated design rule, worked inline. |
| **[A]** | An assumption. The model's player profiles are assumptions (below), and every number derived from them inherits that. The first Studio session replaces them. |

The model's player profiles, all **[A]**: `decode` is the number of seconds needed to read one tag and
decide, `err` is the chance a first attempt goes to a wrong bin, and a pick or deposit press costs
0.5 s.

| profile | decode s (+torn, +memo) | err | carry | walk speed | picks items |
|---|---|---|---|---|---|
| first-timer | 3.0 (+1.0, +1.0) | 0.20 | 2 | 16 | in tray order |
| regular | 1.5 (+0.5, +0.5) | 0.08 | 2 | 16 | in tray order |
| regular+kit | 1.5 (+0.5, +0.5) | 0.08 | 5 | 22 | in tray order |
| expert+kit | 0.8 (+0.3, +0.3) | 0.02 | 5 | 22 | the shortest route among the 8 visible |
| guesser | 0 | 5/6 (random bin; told the answer after a miss) | 2 | 16 | in tray order |

The model simulates 2000 seeded shifts per data point. Walking is modelled as straight lines at
exactly the walk speed. It is not a physics model.

---

## 1. Core loop

You work a private sorting bay in a lost-property depot. Eight lost items sit on your intake tray.
Each one wears a luggage tag like `T · 3 · RED`, and the tag's letter is drawn without looking at the
item, so it contradicts what the item looks like three times in four. Tap an item to pick it up (you carry two at first), then read its tag against the Depot Manual:
a RED route goes to CLAIMS, condition 5 goes to REPAIR, and otherwise the letter names the bin. Walk
the item to one of six bins standing in an arc beyond the tray and drop it in. A correct first
try pays cash, grows your combo and knocks one item off the depot's 500-item BACKLOG. A wrong bin
bounces the item back to the tray with the right answer written on its tag, takes 8 seconds off the
shift clock and breaks the combo. A shift is 30 items against a 330-second clock, and the clock only
starts when you pick up your first item. Clear all 30 with at most three misfiles for a Perfect
Shift. Between shifts the depot reseeds: new items, new tags, the six bins shuffled around the arc,
and, from your third shift, a one-line MEMO that bends one rule. Cash buys a bigger cart and faster
shoes at the locker beside your spawn. Clear the whole backlog and the locked Back Room door behind
the bins opens on the depot's one secret.

---

## 2. Where v1 departs from the brief, and why

| the brief said | v1 does | why |
|---|---|---|
| Deposit by `TouchEnded` on the bin | A `ProximityPrompt` on each bin, validated by the server | Touch events come from physics: they are not modelled headless (`robloxemu` has no physics), and a client can fire them. |
| "No server-authoritative anti-exploit surface (worst case is a player self-reporting a sort)" | The server decides every sort. The client never names a bin or claims a result. | A self-reported sort is a free sort. Fork Tower's REVIEW-3 fourth pass is what a "harmless" client-readable answer turned out to cost. |
| Seed = date + shift, so every player shares a daily depot | A hashed per-player seed that includes a server-only per-session salt | Checklist trap "Replayable RNG". Also, feeding the repo's LCG consecutive raw seeds repeats the first item's letter on **99.8%** of consecutive shifts; the hashed seed repeats it on **24.4%**, against 25.0% for independent draws **[M 0]**. |
| An 8-minute shift of 30–60 items | 30 items, 330 s | A first-timer needs a median **285.5 s** for 30 items at stage 3 and **380.6 s** for 40 **[M 3]**. 330 s is the shortest clock under which the slow reader clears stage 3 in at least 90% of shifts (§6.3), in keeping with the 2026 signal of return rate over session length. |
| Scanner upgrade "reveals one code part" | Cut | A torn tag part does not exist on the server either (§7.3), so there is nothing to reveal. A scanner that resolves a rule instead is an auto-solver sold for cash. |
| "Extra shift minutes" upgrade | Cut | 330 s already clears **96.0%** of a first-timer's stage-3 shifts **[M 6]**. |
| Leftovers roll into the next shift as backlog | Cut | It makes the slowest player's next shift bigger, a death spiral aimed at the players the game most needs to keep. |
| One extra wing in the MVP | Cut to a post-launch update | Each wing is a new rule layer, a new archetype set and its tests. v1 already has three layers (base, torn tags, memos). The ending's key is the hook for the wing. |
| Gamepasses: 2x cash and a scanner | Nothing costs Robux | A task rule. It is also correct on the merits: 2x cash buys the upgrade ladder, which buys shift time (§11). |
| A simple top-clearance leaderboard | Cut. Players get a personal best only. | A bot held to the tightest honest travel limit the model could build still clears a shift in **9.8 s** against an expert's **86.0 s** **[M 7]**. No ranking is defensible (§10.3). |
| Friends join the same depot | Cut. Every player gets a private bay. | A shared tray is a griefing surface (hoarding items, misfiling on purpose) plus shared-state sync. The "Avoid solo" list warns off exactly this kind of netcode. |
| Procedural shelves and aisles | The bin arrangement is reshuffled each shift. The floor stays open. | Obstacle aisles need a connectivity generator and a physics walk check, and they add walking, not decisions. Reshuffled bins force you to read the signs every shift for none of that cost. |
| Stamp and chime sounds | A visual stamp only | Audio asset ids cannot be verified without Studio. An unverified id plays silence. |
| Emoji-rich labels | Text, plus glyphs already photographed rendering in Studio | Fork Tower shipped U+1FAA8, which Roblox draws as an empty box **[S `fork-tower/STUDIO.md` §4]**. |

**Store text consequence.** The brief's paste-ready description promises "A NEW procedurally
generated depot every single shift", "Sort solo or bring friends into your depot" and "new wings and
new secrets drop every week". v1 must not ship those three lines. Say instead: "new items, new tags
and reshuffled bins every shift", and drop the friends line and the weekly-wings line until both
exist.

---

## 3. The rules

### 3.1 The tag

A tag has three parts:

- **LETTER**: B, E, K or T.
- **CONDITION**: 1 to 5, where 1 is like new and 5 is broken.
- **ROUTE**: RED, GREEN, BLUE, YELLOW, PURPLE or WHITE, printed as the **word** in its colour.

It renders as `T · 3 · RED`, with the item's name on a second line (`Teddy Bear`). A torn part is
drawn as a grey `?`. The route is always spelled out, so no rule depends on seeing colour.

### 3.2 The catalog: each item's own letter

| letter | bin | items |
|---|---|---|
| B | BAGS & WEAR | Backpack, Sneaker, Baseball Cap, Scarf |
| E | ELECTRONICS | Phone, Headphones, Camera, Laptop |
| K | KEYS & WALLETS | Keyring, Wallet, Padlock, ID Badge |
| T | TOYS | Teddy Bear, Toy Car, Beach Ball, Rubber Duck |

The other two bins are **REPAIR** and **CLAIMS**, so there are six bins in all. Each item exists in 2
colour variants. No rule reads the variant.

### 3.3 The Depot Manual, verbatim

This text appears on the bay wall and in the HUD's MANUAL drawer. It is ASCII only; see §13.4 for the
glyph rule.

Stage 1:

```
DEPOT MANUAL - check in this order
1. RED route?              -> CLAIMS
2. Condition 5?            -> REPAIR
3. Otherwise the LETTER picks the bin:
   B = BAGS & WEAR    E = ELECTRONICS    K = KEYS & WALLETS    T = TOYS
Trust the TAG, not the item.
```

Stage 2 adds:

```
TORN TAGS
- Route torn off?          It is not claimed. Keep going.
- Condition torn off?      -> REPAIR (unless step 1 already sent it to CLAIMS)
- Letter torn off?         Use the item's own letter (see the catalog).
```

Stage 3 adds a box: `TODAY'S MEMO: <one line>`. The twelve memo lines are:

| family | line | count |
|---|---|---|
| EXTRA_CLAIM | `GREEN route counts as claimed today -> CLAIMS` (also BLUE, YELLOW, PURPLE, WHITE) | 5 |
| EXTRA_BROKEN | `Condition 4 counts as broken today -> REPAIR` | 1 |
| SWAP | `B and T swap bins today: B -> TOYS, T -> BAGS & WEAR` (also BE, BK, EK, ET, KT) | 6 |

**A memo never changes the order of the manual. It changes what counts at one step.** A torn letter
is resolved to the item's own letter first, and then the swap applies to it.

### 3.4 Resolution: one pure function

```
resolve(tag, ownLetter, rules):
  if tag.route ~= nil and rules.claim[tag.route]   -> CLAIMS
  if tag.cond == nil                               -> REPAIR      -- torn condition
  if rules.broken[tag.cond]                        -> REPAIR
  letter = tag.letter or ownLetter                                -- torn letter
  -> rules.letterMap[letter]
```

The `rules` are the base rules (`claim = {RED}`, `broken = {5}`, the identity letter map) with at
most one memo applied.

### 3.5 What each layer is worth, measured

| stage | bin shares | decided by | sorting by what the item LOOKS like is right | reading only the LETTER is right |
|---|---|---|---|---|
| 1: base | every bin 16.7% | route 16.7, cond 16.7, letter 66.7 | 16.7% | 66.7% |
| 2: + torn tags | REPAIR 22.5, CLAIMS 15.3, each letter bin 15.6 | + torn-cond 6.9, torn-letter 5.6 | 19.7% | 62.2% |
| 3: + a memo | CLAIMS up to 30.6 (EXTRA_CLAIM), REPAIR up to 38.1 (EXTRA_BROKEN) | varies by memo | 14.8–19.7% | 46.7–62.2% |

All figures are **[M 1]**. Ignoring the memo and applying the manual perfectly still sorts 68.9–84.7%
of items correctly, so **a memo changes the answer for 4.6 to 9.3 items of a 30-item shift** **[M 1]**.
All 24,960 (tag, own letter, rule set) combinations resolve to exactly one bin **[M 1]**.

Why these counts: with the route uniform over 6 (one of them claimed), the condition uniform over 5
(one of them broken) and the letter uniform over 4, stage 1 comes out exactly even:
CLAIMS = 1/6, REPAIR = 5/6 × 1/5 = 1/6, and each letter bin = 5/6 × 4/5 × 1/4 = 1/6 **[R]**. The
tag's letter is drawn independently of the item's own letter, so a look-sorter scores the chance
rate of 1 in 6 in stage 1. That is the "trust the tag, not the item" hook in one number.

### 3.6 Stages

The stage follows the career shift count: shift 1 is stage 1, shift 2 is stage 2, and shift 3 and
every shift after it are stage 3 **[R]**. The rule is one new layer per shift, so the first three
shifts each teach exactly one thing. For the first-timer profile those three shifts take less than
14 minutes of clock: a median 248.0 s at stage 1 and 285.5 s at stage 3 **[M 3]**. Stage 2 was not
timed separately. It adds torn tags but not the memo, so it costs no more than stage 3, and
248.0 + 285.5 + 285.5 = 819 s **[R]**. When a new layer unlocks, the MANUAL drawer opens by itself with the new lines marked
`NEW`. The clock does not start until the first pickup, so reading it costs nothing.

---

## 4. The bay

Coordinates are bay-local studs, with +Y up and the floor top at y = 0. **P**, the pick point, is the
origin. The bins lie toward −Z and the spawn toward +Z.

| thing | where / size | notes |
|---|---|---|
| Interior | x ∈ [−36, 36], z ∈ [−36, 20] | Walls are 16 tall. There is no roof. |
| Tray table | centre (0, 1.5, 6.5), size (16, 3, 6) | Its `PutBack` prompt sits at the centre: key R, `MaxActivationDistance` 8. |
| Tray slots | front row z = +5, back row z = +8; x = −6, −2, +2, +6 | Each slot is a transparent hitbox Part (3.5, 3, 2.5) holding a `ClickDetector` (`MaxActivationDistance` 12) and the `Tag` BillboardGui. The back-row item sits on a 1.5-stud step. |
| Spawn pad `BayPad` | centre (0, 0.5, 14), size (6, 1, 6) | A `SpawnLocation` with `Duration = 0`. See §9. |
| Bins `Bin_1..Bin_6` | centres at radius 28 from P, angle 15° + 30°·(k−1), each on the −Z side and facing P | A crate (8 wide, 4 tall, 6 deep), a sign board above it with a SurfaceGui facing P, a `Drop` prompt (key E, `MaxActivationDistance` 6) and one PointLight. The instance is named by **arc slot**; which bin it is lives only in the sign text. |
| Back Room | door (8 wide, 10 tall) in the back wall at x = 0, z = −36; room x ∈ [−10, 10], z ∈ [−50, −36], roof at y = 14 | The door has an `Open` prompt (key E, distance 6). The door is one bin wide, so it reads as a door and not a gap, and 10 tall, above the 7.2-stud jump. The roof sits below the 16-stud walls; the room only has to hold a shelf and a camera path. The room is **empty** until its owner unlocks it (§8.3). |
| Backlog sign | on the back wall above the door | `🔒 BACK ROOM` / `BACKLOG 0 / 500` |
| Memo board | above the tray at (0, 9, 9), facing P | Shows `TODAY'S MEMO` from stage 3. |
| Manual board | on the left wall x = −36, spanning z −4..8 and y 4..12, facing +X | The Depot Manual text for the player's stage. |
| Locker | (12, 0, 16), size (4, 6, 2) | Two prompts: `Cart` (key E) and `Shoes` (key R), distance 6. |
| Name sign | above the spawn pad | `<DisplayName>'S BAY` |
| Carried crate | a Part (2, 1.5, 1.5) welded 2 studs in front of the `HumanoidRootPart`, visible while carrying at least one item | `Massless`, and `CanCollide`, `CanQuery` and `CanTouch` all false. `CanQuery = false` is Deep Vein's lesson: nothing decorative may intercept a click. |

Bays sit on a row along +X. Bay *k* (0-based) has its origin at x = 100 + 80·k: the 72-stud interior
plus the walls plus a gap **[R]**. The Break Room (§9) is at the world origin, spanning ±20, with
16-stud walls. The last of 12 bays is centred at x = 980 **[R]**, well inside float precision. Bay
indices are recycled through a free list, so coordinates never march outward.

### 4.1 Geometry, measured

- Adjacent bin centres are **14.49** studs apart. Two prompt radii cover 12.0, which leaves a
  **2.49-stud gap**, so at most one bin's `Drop` prompt can be in range **[M 2]**.
  `ArcRadius = 28` is the smallest whole-stud radius that gives at least a 2-stud gap: it needs
  2R·sin 15° ≥ 14, so R ≥ 27.05 **[R]**.
- The farthest tray slot is **10.00** studs from P and **10.82** from the spawn pad's centre, against
  an `ItemReach` of 12. **Every item on the tray is tappable from the spawn pad without taking a
  step** **[M 2]**.
- The nearest bin centre to any tray slot is **24.35** studs away. Reach plus prompt distance is 18,
  so **every pick is followed by at least 6.35 studs of walking before a deposit**, and the walk is
  part of the loop by construction **[M 2]**.
- P to any bin's stand point is 23.0 studs, or 1.44 s at walk speed 16. Adjacent stand points are
  11.91 studs apart, or 0.74 s **[M 2]**.
- The farthest any bin stand point gets from any tray slot is 31.5 studs: stand point
  (23·cos 15°, −23·sin 15°) to slot (−6, 8) **[R]**. The tag's `MaxDistance` of 40 therefore lets
  you plan the next trip from the bins.
- The bins' outer edges stay within |x| ≤ 31 and z ≥ −31, which leaves 5 studs of walkway to every
  wall **[R]**.
- The gap between the crates of bins 3 and 4 is about 6.5 studs (14.49 − 8), and it is the path to
  the Back Room door. A player standing in it at (0, −31) is 5 studs from the door and 8.26 from
  either bin's centre, so only the door's prompt shows **[R]**.

### 4.2 Nobody climbs out

Walls are 16 studs. **No collidable fixture inside a bay has a top face above 6 studs**: bins are 4,
the tray 3 (4.5 at the step), the locker 6 and the spawn pad 1. A Roblox character jumps 7.2 studs
(**[S `fork-tower/STUDIO.md` §5]**, read off the live Humanoid), so the best possible climb is
6 + 7.2 = 13.2, which is 2.8 studs short of the wall top **[R]**.

The only collidable Parts are the **shell** (floor, walls, the lintel over the door, the door
itself, and the Back Room's walls) and the **fixtures** (tray and step, bins, locker, spawn pad).
Every decorative Part (sign boards, memo board, manual board, backlog sign, name sign, shelf, key) is
`CanCollide = false`. This matters for boards mounted on walls: a collidable manual board with its
top at y = 12 would be a ledge to jump from, to 19.2. The Back Room roof is `CanCollide = false`
too, because a player inside the room jumps to 7.2, which is under the 14-stud roof. Private bays
only stay private if the walls cannot be climbed, and the headless check asserts both halves of this
rule (§14.3).

---

## 5. A shift, step by step

Each bay's shift is in one of four states, and **the server owns all of them**.

```
LOADING --profile loaded--> ARMED --first accepted pickup--> RUNNING --all 30 sorted, or clock hits 0--> SUMMARY
   ^                          ^                                                                           |
   |                          +------------------------ IntermissionSeconds (4 s) -------------------------+
 player joins
```

- **LOADING.** The bay is claimed and the tray is empty; the memo board reads
  `Unpacking your cart...`. Every interaction is refused with that same line.
- **ARMED.** The shift is generated (§7): 8 items on the tray, 22 in the cart queue (server memory
  only), bins permuted and the memo set. The HUD clock shows `5:30` and
  `starts when you pick something up`. Nothing is running.
- **RUNNING.** `endsAt = clock() + 330`, where `clock` is Fork Tower's probe: `GetServerTimeNow`,
  falling back to `tick()`, which is the clock `robloxemu` advances (it has no `GetServerTimeNow`). A server loop per bay checks
  `clock() >= endsAt` every 0.25 s, so a shift ends within a quarter second of zero; the HUD counts
  down on its own. A misfile does `endsAt -= 8`.
- **SUMMARY.** The shift is scored: items sorted out of 30, misfiles, pay, `★ PERFECT SHIFT ★`,
  backlog gained and personal best. `shifts += 1` (a timed-out shift counts too, so a struggling
  player still unlocks stages). The HUD card stays up until tapped or until the next shift's first
  pickup. After `IntermissionSeconds` the bay re-arms with a fresh shift.

### 5.1 The interactions

Every in-world handler (pick, deposit, put back, buy, door) checks, **in this order and without
yielding between the check and the state change**:

1. The player owns this bay.
2. The profile is loaded.
3. The state allows the action.
4. The character is alive and has a `HumanoidRootPart`.
5. The root part is within the target's reach plus `ReachSlack` (2 studs).

| action | how the player does it | server effect | refused with (never silent) |
|---|---|---|---|
| **Pick** | tap or click a tray item (its slot hitbox's `ClickDetector`) | tray slot → carried; this item becomes the selected one; the slot refills from the cart; the first pick of an ARMED shift starts the clock | `Hands full (2/2). Drop something in a bin first.` / `Too far - walk up to the tray.` / `That's someone else's bay.` |
| **Select** | tap a HUD hotbar slot, which fires the `Select(slot)` remote | `selected = slot` | Malformed payloads are dropped without a toast; see §10.2 for why that is not a silent no-op. |
| **Deposit** | press E at a bin | resolves the **selected** carried item against this bin; see below | `Your hands are empty. Pick an item from the tray.` / `Too far - walk up to the bin.` |
| **Put back** | press R at the tray | the selected carried item returns to a free tray slot, or to the front of the cart | `Your hands are empty.` |
| **Buy** | E (Cart) or R (Shoes) at the locker | spends the next level's price | `Cart (carry 3) costs 250. You have 180.` / `Your cart is fully upgraded.` |
| **Back Room** | E at the door | §8.3 | `Locked. Backlog: 312 / 500.` |

**Deposit, correct, first attempt:** the item is sorted, `combo += 1`, it pays `10 + min(combo, 10)`,
and `backlog += 1`. **Deposit, correct, after an earlier misfile:** the item is sorted and pays `5`;
the combo and the backlog are unchanged. Either way the HUD gets the amount (`+11` for a first sort)
and the client runs the stamp effect (§13).

**Deposit, wrong:** `misfiles += 1`, `combo = 0`, `endsAt -= 8`. The item goes back to a free tray
slot, or to the front of the cart, marked misfiled, and its tag now reads
`MISFILED - goes to REPAIR`. The toast explains the deciding rule, generated by `Rules.explain`:
`-8 s. Condition 5 goes to REPAIR.`

After a deposit or a put-back, `selected` moves to the first remaining carried item.

The bins' `Drop` prompts and the tray's `PutBack` prompt are `Enabled` only while that bay's owner
carries something, which keeps the screen quiet. The empty-hands toast still exists for a prompt
fired anyway.

**Leaving mid-shift:** every sort already made keeps its cash and backlog, and both are saved on
`PlayerRemoving`. The unfinished shift is discarded and does not count toward `shifts`.

**Dying or resetting mid-shift** (the game has no damage, so this means a reset or a fall): carried
items go back to the tray (or the front of the cart), the clock keeps running, and the player
respawns on their pad (§9).

---

## 6. Every number

### 6.1 Rules and generation

| name | value | reason |
|---|---|---|
| letters / conditions / routes / bins | 4 / 5 / 6 / 6 | Makes stage 1 exactly even at 1/6 per bin **[R §3.5]**. |
| items in the catalog | 16 (4 per letter), 2 colour variants each | Every name is unambiguous to a child, and the name is printed on the tag, so recognising a Part-built model is never needed for a correct sort **[R]**. The variant costs one colour field. |
| `TornChance` | 0.25 | The lowest value tried at which **both** torn clauses decide at least one item in more than 4 shifts in 5: torn-condition in 88.5% and torn-letter in 82.0% of 30-item shifts. At 0.15 those are 72.1% and 63.8%; at 0.35 they are 95.4% and 91.2%, but a third of all tags are torn **[M 1]**. |
| memos | 12 (5 EXTRA_CLAIM, 1 EXTRA_BROKEN, 6 SWAP) | Each changes the answer for 4.6–9.3 of 30 items, so no memo can be ignored **[M 1]**. |
| `TornUnlockShift` / `MemoUnlockShift` | 2 / 3 | One layer per shift **[R §3.6]**. |
| `TutorialItems` | 2 (career shift 1 only) | One item whose tag matches its look, then one whose tag contradicts it. That is the whole hook, taught in two moves (§12). |
| `WorldSeed` | 20260916 | The date this spec was written. Any constant works: the per-session salt, not the world seed, is what makes a seed unpredictable (§7.1). |

### 6.2 The bay

| name | value | reason |
|---|---|---|
| `ArcRadius` | 28 | The smallest radius with a ≥ 2-stud gap between neighbouring prompt ranges **[R §4.1]**; measured gap 2.49 **[M 2]**. |
| `BinPromptDistance` | 6 | A player standing against the 6-deep crate is 3 studs from its centre, so 6 gives them 3 studs of room in front **[R]**. |
| `ItemReach` | 12 | Covers the farthest slot from the spawn pad (10.82) with about a stud to spare, so the first pick needs no step. Reach plus prompt (18) is still under the nearest bin-to-slot distance (24.35), so walking is never optional **[M 2]**. |
| `ReachSlack` | 2 studs | The server sees a moving root part late. The only lag measured in this repo is 32 ms on localhost **[S `fork-tower/STUDIO.md` §1]**, about 0.7 studs at walk speed 22; 2 studs allows about 3x that. Live cellular lag is unmeasured (§16.2). If it is too tight, the failure is a toast and a second press, never a lost item. |
| tray | 2 rows × 4, 4-stud spacing, rows 3 apart | 8 slots is the knee: going from 4 to 8 visible items cuts an expert's shift from 97.9 s to 86.0 s (−12.1%), and going from 8 to 12 only reaches 83.3 s (−3.1%) **[M 4]**. Slot hitboxes of 3.5 × 2.5 leave 0.5-stud gaps between neighbours **[R]**. |
| walls / tallest standable top | 16 / 6 | 6 + 7.2 jump = 13.2 < 16 **[S, R §4.2]**. |
| bay pitch / first bay x | 80 / 100 | 72-stud interior plus walls plus gap. The Break Room is ±20 at the origin **[R]**. |
| `Bay.Count` = experience `MaxPlayers` | 12 | Bays are private, so a bigger server only adds chat presence and Parts. The pool is `max(Bay.Count, Players.MaxPlayers)` (Fork Tower's M5 lesson), so a Studio slider can never seat more players than bays. |
| Parts per bay | ≤ 120, asserted headless | Counted from §4: floor 1, walls and lintel 6, Back Room with door 5, tray and step 2, slot hitboxes 8, bins 6 × (base, 4 sides, sign board) = 36, memo, manual, backlog and name boards 4, locker 1, spawn pad 1, shelf 1 and key 1 → **66**. Add 8 tray items × at most 5 Parts = 40, the carried crate and the dust volume → **108** **[R]**. 12 bays come to at most 1,440 plus the Break Room's 7. Render cost is §16. |
| tag `MaxDistance` | 40 | Above 31.5, the farthest a bin stand point gets from a tray slot **[R §4.1]**. The tags are not `AlwaysOnTop`, so walls hide a neighbour's tags; Fork Tower's pile of text came from `AlwaysOnTop` **[S `fork-tower/STUDIO.md` §9]**. |
| `PutBack` prompt distance | 8, from the tray centre | The tray centre is 6.5 studs from P, so this reaches P with 1.5 studs to spare **[R]**. |
| locker position | (12, 0, 16) | 12 studs from the spawn pad's centre, outside its prompts' range of 6, so in the first seconds the only interactive thing in reach is the tray **[R]**. |
| `SpawnLocation.Duration` | 0 | There is no damage in the game. The default 10 s ForceField shimmer would cover exactly the first-60-seconds window for no benefit **[R]**. |
| character wait | 300 frames × 1/60 s | The bounded `char.Parent` wait from `robloxemu/SPAWN-ORDER.md` §3, as used by Fork Tower and Deep Vein. |

### 6.3 The shift

| name | value | reason |
|---|---|---|
| `ShiftItems` | 30 | The brief's lower bound. At 40 items the first-timer's median stage-3 clear is 380.6 s, over 6 minutes; at 30 it is 285.5 s **[M 3]**. |
| `MisfilePenalty` | 8 s | The smallest penalty tried at which a **slow reader beats a guesser by at least 25% at stage 3**. At 5 s, guessing takes only 1.10x as long as reading, so for a first-timer reading barely pays. At 8 s the ratio is 1.30x, and at 10 s it is 1.41x, which is harsher on learners, who misfile 20% of the time **[M 5]**. |
| `ShiftSeconds` | 330 | The shortest 30-s step at which the first-timer clears stage 3 in ≥ 90% of shifts: 96.0% at 330 against 71.7% at 300. A guesser clears 4.8% at 330. A regular clears 100% at every clock tried **[M 6]**. |
| `PerfectMaxMisfiles` | 3 | A regular misfiles a median of 2 (p90 4) at stage 3 **[M 3]**. With 3 allowed, Perfect lands on **78.3%** of a regular's shifts, 11.9% of a first-timer's and **0.0%** of a guesser's **[M 6]**. |
| `IntermissionSeconds` | 4 | A pacing beat for the cart rolling in. The summary card is not bound to it (it stays until the next pickup), so a shorter beat saves nothing that matters: 4 s × 18 shifts is 72 s over the whole road to the ending **[R, M 9]**. |
| timer poll | 0.25 s | The server ends a shift within a quarter second of zero. The HUD clock is client-side, so a player never sees the difference **[R]**. |

### 6.4 The economy

| name | value | reason |
|---|---|---|
| first-try pay | `10 + min(combo, 10)`, where combo counts this sort | Integer arithmetic only. Pay rises from 11 to 20, a 2x cap the kids' cluster can read at a glance (`+11`). The maximum is 555 per shift from sorts **[M 8]**. |
| re-sort pay (after a misfile) | 5 | Half. A guesser's shift pays a median **146** against a regular's **557** and a first-timer's **364** **[M 8]**. Reading pays, but guessing is not a zero, so a child who cannot read yet still progresses. |
| `PerfectBonus` | 100 | About 18% of a regular's shift pay: noticeable, never the majority. The maximum shift pay is 655 **[M 8]**. |
| Cart levels (carry) | 2 → 3 → 4 → 5 | Base 2 means fewer tags to hold in mind on shift 1. The cap of 5 keeps the HUD hotbar at 5 slots (§13.3), and leaves the 8-slot tray with at least 3 items to choose among at max carry **[R]**. |
| Shoes levels (walk speed) | 16 → 18 → 20 → 22 | 16 is Roblox's default, read off the live Humanoid **[S `fork-tower/STUDIO.md` §5]**, and the server assigns it explicitly: Nightwatch Manor shipped a chase tuned against a speed nobody had set. +2 per level ends at +37.5%; how that feels is §16. |
| price per level, both tracks | 250 / 800 / 2000 | Level 1 of both tracks is affordable after shift 1 for a regular (a median stage-1 shift pays 556 ≥ 500 **[M 8]**), and the last upgrade lands **before** the ending for both reading profiles: regular kit complete at shift 11 against the ending at 18; first-timer 17 against 21. The alternative ladder 250/600/1400 finishes the kit at shift 9 / 13 and leaves 9 and 8 shifts with nothing to buy **[M 9]**. |
| `BacklogSize` | 500 first-try correct sorts | The ending lands after **18 shifts (45 min of shift clock) for a regular** and 21 shifts (88 min) for a first-timer who never improves. A guesser does not reach it within 80 shifts **[M 9]**. At 15 minutes of shift clock a day, that is the 3rd day for a regular (45 / 15) and the 6th for the slowest reader (88 / 15 = 5.9) **[R]**: a multi-day return goal built from sub-15-minute loops, as the 2026 radar recommends. |
| launch code `SORTED` | +250 cash | Exactly one level-1 price, so a player arriving from a codes article buys their first upgrade in their first minute **[R]**. |

### 6.5 Persistence and remotes

| name | value | reason |
|---|---|---|
| `AutosaveSeconds` / `SessionLockSeconds` | 20 / 45 | Deep Vein's shipped pair (`deep-vein/src/shared/Config.luau`). The lock outlives two autosave periods, so one late autosave never drops it **[R]**. |
| `RedeemCooldown` | 2 s | One attempt per human-typed code. It also bounds `UpdateAsync` calls from a spamming client **[R]**. |
| `CodeMaxLength` | 20 characters | The longest v1 code is 6 characters, so 20 leaves room for future codes and bounds the payload **[R]**. |

---

## 7. Procedural generation

### 7.1 The seed

```
seed = fmix(fmix(fmix(fmix(WorldSeed) xor (userId % 1000003)) xor shifts) xor salt)
```

- `fmix` is the murmur3 finalizer with an exact 32-bit multiply (`mul32`, Deep Vein's `Mine.hash`
  technique). Its largest intermediate is 12,884,508,675, a factor of 699,072 under 2^53, so no low
  bits are lost to float rounding **[M 0]**.
- `userId % 1000003`: the `bit32` functions take values below 2^32 and Roblox user ids exceed that.
  Any reduction works, because the salt, not the user id, makes the seed unpredictable.
- `shifts` is the persisted career shift count, so every shift within a session differs.
- `salt` is one 32-bit value from a server-side `Random.new()` per player session. It is never
  persisted and never replicated. It is what makes the next shift unpredictable, even though the
  generator itself ships in `ReplicatedStorage`.
- **Why hash rather than feed `Rng.new` directly:** consecutive raw seeds give the repo's LCG a
  first draw that repeats the item's letter on 99.8% of consecutive shifts; hashed, the rate is
  24.4% against the independent 25.0% **[M 0]**.
- The seed is printed to the **server** console at every ARMED transition, so a bug report can be
  replayed. It never reaches a client.

### 7.2 Generation order (one `Rng`, every small range through `Rng.below`)

1. **The memo** (stage 3 only): `MEMOS[Rng.below(12)]`.
2. **The bin arrangement**: a Fisher–Yates shuffle of the six bins over the six arc slots.
3. **30 items**, each in this fixed draw order: archetype (`below(16)`), variant (`below(2)`), letter
   (`below(4)`), condition (`below(5)`), route (`below(6)`), then from stage 2 on a torn roll
   (`next() < TornChance`) and, if torn, which part (`below(3)`). **The torn part is then deleted
   from the item.** The resolved bin is computed and kept in server memory.
4. **Tutorial overrides**, on career shift 1 only: item 1 becomes Teddy Bear, `T · 2 · GREEN` (TOYS,
   matching its look), and item 2 becomes Phone, `K · 1 · BLUE` (KEYS & WALLETS, contradicting its
   look). Neither is torn. They are placed in the two back-row centre slots, x = −2 and x = +2. The
   pad's centre is 6.32 studs from each **[R]**.
5. **Tray fill order** is the generation order: items 1–8 fill slots 1–8 (on career shift 1, items 3–8
   fill the six slots the tutorial items leave free, in slot order), and items 9–30 are the cart
   queue. Whenever a slot empties, the next cart item fills it.

### 7.3 What is never generated

- **The value of a torn part.** If the route is torn, the item has no route at all, on the server
  too. There is no hidden truth to leak, to scan, or for a friend to post (§10).
- **Any correlation between an item's own letter and its tag letter.** They are drawn independently.
  `Shift.spec` asserts that tag letter and own letter agree in 25% ± 1% of 40,000 items.
- **Any correlation between tray order and the answer.** `Shift.spec` asserts each of the six bins
  is 1/6 ± 1% of the answers **in each** of the 8 initial tray positions, over 40,000 stage-1 shifts
  that are not career shift 1. That is 40,000 samples per position: one standard deviation is 0.19
  percentage points, so the tolerance sits 5.4 standard deviations out on each of the 48 (position,
  bin) comparisons, and correct code does not flake **[R]**.

---

## 8. Data model

### 8.1 What persists (DataStore `LostFoundDepot_v1`, key `u_<userId>`)

The record is `{ data = <profile>, lock = { token, expires } }`.

```json
{
  "v": 1,
  "cash": 0,
  "cartLevel": 0,
  "shoesLevel": 0,
  "shifts": 0,
  "perfects": 0,
  "backlog": 0,
  "bestPerfectSeconds": 0,
  "endingSeen": false,
  "redeemed": { "SORTED": true }
}
```

- **Every key is a string and every value is a scalar or a string-keyed set.** No integer-keyed map
  exists, so the JSON round-trip trap from the checklist has nothing to bite.
- **`sanitize` on load.** Numbers are floored; NaN and negatives become 0. `cartLevel` and
  `shoesLevel` are clamped to 0..3, `backlog` to 0..500, `perfects` to 0..`shifts`. Unknown keys are
  dropped. `sanitize` is pure, and `Economy.spec` feeds it hostile records.
- **What is deliberately not saved:** anything about the current shift. A shift is 5.5 minutes at
  most, and resuming one would mean persisting the cart queue, which is exactly the thing that must
  not leave the server.
- **Save discipline** follows the siblings: `GetDataStore` is pcall'd (it raises in an unpublished
  place), there is a soft session lock whose ownership is a per-session GUID token (never a
  timestamp we also rewrite), `canSave` is true only while we hold the lock, and we autosave every 20
  s, on `PlayerRemoving` and in `BindToClose`. When the store is unavailable, the player plays with
  defaults and gets one toast: `Progress will not save this session.`
- **Codes are the only one-time grant.** Redemption is one atomic `UpdateAsync` flush that adds cash
  and marks the code redeemed in the same write. If the write fails, the grant is refused and the
  in-memory profile is rolled back, so a code can never be re-redeemed.

### 8.2 What is server-only

`ServerStorage` holds **nothing** in v1. There is no answer mirror for tests to read, on purpose: the
headless check derives every answer from the **rendered** tag text and memo board through
`Rules.resolve`, the way a player does (§14.3). That proves the visible information is sufficient,
which a server-side answer table could never prove. Anomaly Observatory's `ServerStorage.PassInfo`
existed for a capture rig this game does not need.

| state | where | why it must not replicate |
|---|---|---|
| each item's resolved bin | the per-bay shift table in `Main.server` | It is the answer. |
| the cart queue (items 9–30) | same | Upcoming items would let a planner see the future. Building them as Instances, even hidden ones, would replicate them. |
| the seed, the salt, the next shift's memo | same | They predict the next shift. |
| session lock token, `canSave`, redeem-in-flight flag | the per-player profile table | Server bookkeeping. |
| **the Back Room note text** | `src/server/Secret.luau`, a ModuleScript under `ServerScriptService` | **It is the game's viral secret.** Anything under `src/shared` becomes `ReplicatedStorage`, where every client can datamine it. |
| the code table (`SORTED` → 250, plus future codes) | `src/server/Secret.luau` | Unreleased codes would be datamined before their article drops. |

### 8.3 The Back Room, specifically

- **Before unlock:** the room is an empty enclosure behind a closed door. Its sign shows only the
  backlog count and `🔒`.
- **On unlock** (`backlog >= 500`, checked by the server at the door prompt): the server opens that
  bay's door (`CanCollide = false`, `Transparency = 1`), builds two props (an empty shelf inside the
  room and a brass key Part on a hook beside the door, **no text on either**), sets
  `endingSeen = true`, and fires `Scene` to **that player only** with the note. The client tweens the
  camera through the doorway over 3 s, long enough to read as a scene and short enough not to hold
  the camera hostage (the feel is §16.1), and shows the note on a card. From then on the HUD title
  reads `DEPOT KEEPER`.
  Pressing E at the open door again re-sends the note to its owner only.
- **Other players' clients never receive the text**, because it only ever travels in a
  `FireClient(owner)` payload. The props they can see carry no text.

The note, verbatim:

```
THE BACK ROOM

You cleared the backlog. Nobody has done that since this depot opened.

Every item on those shelves was somebody's, and most of them went home.
This key never did. It was the first thing ever handed in, the night the
depot opened, and its tag was already torn clean off: no letter, no
condition, no route.

I kept it on this shelf for thirty-nine years and never found out what it opens.

It is yours now, Keeper. Somewhere in this depot, a door is still locked.

- R. Okafor, first Depot Keeper
```

### 8.4 What replicates, and why each part is safe

| instance or data | where | safe because |
|---|---|---|
| Bay shells, bins, bin sign text (which bin is where) | `Workspace` | The arrangement is meant to be read; that is the point of reshuffling it. |
| The 8 tray items: model, colour variant, tag text, item name | `Workspace` | It is the puzzle's **input**. A player must see it. |
| A misfiled item's `MISFILED - goes to X` text | `Workspace` | Only after the 8-second penalty has been paid. |
| Memo board text, manual board text | `Workspace` | Rules the player is meant to read. |
| Cart count, CLEARED x/30, backlog count, `<name>'S BAY` | `Workspace` | Counts and public names. |
| `Config`, `Rules`, `Shift`, `Seed`, `Economy`, `Codes` logic, `Fx`, `FxClient`, `Responsive`, `Rng` | `ReplicatedStorage` | Public rules and public code. `Shift` is useless to a client without the salt. `Codes` holds only the normalise/redeem logic; the table is in `Secret`. |
| `State` payload, to the owner only | remote | The owner's own progress, their carried items' tag text, the memo line, and on career shift 1 the tutorial's public target slot and bin. |
| `Notice` payload, to the owner only | remote | Toasts, including the post-penalty explanation. |
| `Scene` payload, to the owner only, only when unlocked | remote | §8.3. |

**Attribute allowlist: empty.** v1 writes no attributes on any Instance. The server maps a clicked
slot hitbox to its item through a table keyed by the Instance, never through an attribute or a name.
Tray slots are named `Slot_1..Slot_8` by position; every item model is named `Item`; bins are named
by arc slot.

### 8.5 Remotes

| remote | direction | payload | validation |
|---|---|---|---|
| `State` | S → C (owner) | `{ cash, cartLevel, shoesLevel, prices, stage, shift = { state, endsAt, serverNow, cleared, total, combo, misfiles, memo, carried = { {tag, name, misfiled} }, selected, tutorial? }, backlog, backlogSize, perfects, best, endingSeen, canSave }` | sent after every state change, never on a timer. The client counts down from `endsAt - serverNow` + its own clock. |
| `Notice` | S → C (owner) | `{ kind = "ok" \| "misfile" \| "refused" \| "info" \| "perfect", text }` | none |
| `Scene` | S → C (owner) | `{ lines = { string } }` | none |
| `Select` | C → S | `slot` | Must be a number that is an integer in 1..#carried; anything else is dropped. |
| `Redeem` | C → S | `code` | Must be a string of at most 20 characters, at least 2 s after this player's previous attempt, with no attempt already in flight. |

**There is no remote that takes a bin, an item, a result or a price.** Picks, deposits, put-backs,
purchases and the door are in-world interactions, whose `Instance` is supplied by the engine, not
the client's arguments.

---

## 9. Spawn and respawn

`robloxemu/SPAWN-ORDER.md` is the governing document. In real Roblox, `CharacterAdded` fires while
the character is **unparented** at the origin. One frame later the engine parents it **and** places
it on a `SpawnLocation`, discarding any CFrame written before that. With no enabled `SpawnLocation`,
it lands on the highest ground over the origin. v1 uses the preferred pattern and the fallback
pattern together, as Grow a Crystal does.

1. **At boot, before any player exists:** build the Break Room at the world origin with its
   `StaffEntrance` `SpawnLocation`, which is **always enabled** (`Neutral = true`, `Duration = 0`,
   sign `Finding your bay...`). Build all `max(Bay.Count, Players.MaxPlayers)` bay shells, each
   `BayPad` with **`Enabled = false`**. There is therefore always exactly one enabled spawn before
   the first join, and it is not a roof.
2. **In `PlayerAdded`, as the very first statements, before any yield:** take a bay index from the
   free list, set that bay's `BayPad.Enabled = true` and **`plr.RespawnLocation = BayPad`**. Only
   then begin the profile load, which yields. The same function runs for every player already in
   `Players:GetPlayers()` when the script starts. If a character already exists by then, the
   placement step (3) runs on it directly, because `CharacterAdded` will not fire for it again: the
   `plus1-jump` shape that no check exercised.
3. **In `CharacterAdded` (on its own thread; it yields):** wait with
   `while char.Parent == nil and frames < 300 do task.wait(1/60) frames += 1 end`. Then **re-read**
   the player's bay, since the player may have left during the wait. If the `HumanoidRootPart` is
   not inside the bay's interior bounds, CFrame it to the pad's top face plus 3 studs, facing −Z. The
   engine's own placement is top face + 2.51, fitted from Fork Tower's pad
   **[S `robloxemu/SPAWN-ORDER.md` §2]**; 3 is that plus a half-stud drop, so the root part is never
   placed inside the pad.
   Then set `Humanoid.WalkSpeed` from `shoesLevel` (or 16 if the profile is not loaded yet; the load
   re-applies it). Carried items from a previous character have already gone back to the tray (5.1).
4. **In `PlayerRemoving`:** `BayPad.Enabled = false`, clear the bay's contents, reset its door, and
   return the index to the free list.

**Why both a `RespawnLocation` and a re-place.** The preferred pattern needs `RespawnLocation` to
exist before the engine's first spawn of this player, and whether the synchronous head of
`PlayerAdded` always wins that race in the real engine is unmeasured (§16.1). If it loses, the only
other enabled spawns are the Break Room pad and other players' pads, and step 3 moves the player
home within its bounded wait. Two players joining in the same frame claim distinct indices, because
the claim is synchronous.

**Headless assertions** (`check_lostfounddepot_spawn.luau`):

- After boot with no players, the only enabled `SpawnLocation` is `StaffEntrance`.
- Every joining player's root part ends inside **their own** bay, on the first spawn and after a
  second `simulateSpawn`.
- Two players joining in one frame end up in different bays.
- A leave followed by a join recycles the bay, and the old pad is disabled while it is free.
- With `RespawnLocation` deliberately not set (a mutation), step 3 still brings the player home.
- With step 3 deliberately removed (a mutation), the first assertion still holds through
  `RespawnLocation` alone.
- **With both removed, the assertion fails.** That is the mutation that proves the check can see the
  defect at all. The two halves are redundant by design, so neither single-half mutation can be
  expected to fail, and the sweep must not count their survival as a hole.

---

## 10. Anti-exploit model

### 10.1 What a client can read, and what it never gets

What a client can read is §8.4. What it **never** gets is §8.2: the answer for any item it has not
already paid for, the cart queue, the seed and salt, the next memo, torn values (which do not exist),
the ending note before its owner unlocks it, and unreleased codes.

**The one thing a client can do with what it reads:** run the public manual against the public tag
with a script, and sort perfectly. That is not a leak. It is the game's rules executed by a program,
and §10.3 says why v1 accepts it.

### 10.2 What a client can fake, and the denial

| a client can | denied by |
|---|---|
| Fire a tray `ClickDetector` or a bin prompt from anywhere | The server's own reach check against the root part, plus `ReachSlack`. |
| Fire **another** player's bay prompts | The owner check, first in every handler. |
| Claim a sort, or name a bin | No remote accepts either (§8.5). |
| Send `Select` garbage (NaN, 1e9, a string, a table) | Must be an integer in 1..#carried, else the payload is dropped. The honest HUD cannot produce an invalid slot, so dropping it without a toast is not a silent no-op for any player: the checklist's rule protects players, and this protects the server from non-players. |
| Spam `Redeem`, or send huge strings | 20-character cap, 2 s cooldown, one attempt in flight, atomic flush. |
| Trigger twice in one frame (the same item picked twice, one carried item deposited twice) | No handler yields between its check and its state change. An item's state moves tray → carried → sorted in single assignments, so the second trigger sees the new state and is refused. |
| Buy without the cash, or past level 3 | The price comes from `Config` and the level is clamped by `Economy.buy`, which never mutates its input. |
| Open the Back Room early | The server checks `backlog >= BacklogSize` at the prompt. |
| Tamper with a save | Clients cannot write DataStores. `sanitize` runs on every load anyway. |
| Teleport between tray and bins, or raise its own `WalkSpeed` | **Not denied in v1.** See 10.3. |
| Solve tags with a script | **Not denied, and cannot be.** See 10.3. |

### 10.3 What v1 deliberately does not deny, with the measurement behind it

**Throughput.** A script can read every tag, apply the manual and teleport. The model priced a server
**travel ledger**. From a shift's first accepted interaction, each accepted interaction adds
`max(0, |p - pPrev| - PositionSlack) / (WalkSpeed * SpeedTolerance)` seconds to `required`, where `p`
is the server-observed root-part position, and an interaction is accepted only when
`elapsed + LatencySlack >= required`.

- **A first draft granted the latency slack once per leg, and it did nothing:** in an earlier run of
  the model, a bot held to it cleared 30 items in **4.3 s**, because on short legs the per-leg slack
  is longer than the leg. The current model keeps only the corrected rule, which grants the slack
  **once per ledger**.
- Held to the ledger, a bot with full kit clears a shift in **9.8 s** (p10 8.9, p90 10.7), against
  **86.0 s** for the expert+kit profile. With no ledger at all, a teleporting bot takes 0 s. Speed
  tolerance barely matters: at 1.00 the bot takes 12.4 s, at 1.10 it takes 11.2 s **[M 7]**. **A
  bot's advantage is not walking. It never reads and never taps.** No walking limit can close that.
- The ledger is safe for honest players: with the server's view of an honest player off by up to 2
  studs and 0.6 s, it made **0 refusals across 8,000 shifts** at every tolerance tried. At 4 studs and
  1.2 s it made 672–742 **[M 7]**.

**Therefore v1 builds neither the ledger nor any leaderboard.** A bot's throughput is harmless in v1
because every surface where it could hurt another player is gone:

- no leaderboard or ranking of any kind (only a personal best, visible to its owner),
- no trading, gifting or shared bays,
- nothing bought with Robux that a bot could farm or devalue,
- no AFK income,
- a Back Room note that only its unlocker's client receives.

A botter speeds up only their own progress. **If a leaderboard is ever added, the ledger is its
prerequisite, and even then the only defensible boards rank something a bot cannot do faster than a
careful human.** No time-based board qualifies.

---

## 11. Fair monetization

- **v1 sells nothing.** No gamepasses, no developer products, no paid private servers.
- **No gambling.** No spin wheels, loot boxes, random paid rewards or "mystery" purchases. The
  2026-09-14 radar records the backlash against slot-machine wheels bolted onto games in this
  audience's lane.
- **No AFK or idle rewards.** The shift clock does not run until you pick something up, and nothing
  accrues while you stand still. That keeps clear of the 26–29 August 2026 doomscroll-reward catalog
  restriction noted in the round-2 radar.
- **Codes give cash only**, and the launch code is worth exactly one level-1 upgrade.
- **If monetization comes later, it is cosmetic only**: vest colours, a tag-stamp effect, a bay
  paint. It must change nothing the game measures. Explicitly **rejected**, with the reason each is
  pay-to-win here:
  - 2x cash buys the upgrade ladder, which buys shift time.
  - A scanner or auto-sort buys the skill itself.
  - Extra shift time buys Perfect Shifts.
  - A backlog skip buys the ending, which is the thing the community is meant to earn and talk about.

---

## 12. The first 60 seconds of a new player

Distances are **[M 2]** or **[R]**. Durations marked **[A]** are estimates from the profile
assumptions. Real load time and real walking feel are §16.

| t | what happens |
|---|---|
| 0.0 | Join. The bay is claimed and `RespawnLocation` is set before any yield. The profile load starts. |
| ~0–1 **[A: live DataStore latency unmeasured]** | The character stands on `BayPad`, facing the arc (§16.1). In view: the empty tray in front, the six bins in their arc beyond it, and centred between bins 3 and 4, the Back Room door with `🔒 BACK ROOM / BACKLOG 0 / 500` above it. (The memo board above the tray faces the pick point, not the spawn, and is blank on shift 1.) The HUD shows only `Unpacking your cart...`. |
| profile loaded | Shift 1 arms. The tray fills, and the HUD shows `CASH 0`, `TIME 5:30 - starts when you pick something up` and `CLEARED 0/30`. The Teddy Bear (`T · 2 · GREEN`) sits in the back row at x = −2, **6.32 studs** from the pad's centre, inside the 12-stud reach. **No step is needed.** Hint: `Tap the Teddy Bear on the tray`, with an arrow over it. |
| ~3–5 **[A]** | Tap. The clock starts. The hotbar shows `T · 2 · GREEN / Teddy Bear`. Hint: `T means TOYS. Walk to the TOYS bin and press E.` The TOYS bin's light pulses (tutorial highlight; the answer is fixed and public). |
| ~5–12 **[A]** | The walk: around the tray's end (it spans x ±8) to the TOYS stand point, about 40 studs from the pad, about 2.5 s at 16 **[R]**, plus finding the bin. Press E: the stamp, a sparkle burst on the bin, an FOV punch, `+11`, `CLEARED 1/30`. |
| ~12–25 **[A]** | Hint: `Now the Phone. Read its TAG, not the phone: K means KEYS & WALLETS.` The KEYS & WALLETS bin pulses. Walk back 23 studs, tap, walk, press E: `+12`. Toast: `Tags beat looks. The rest is up to you - every rule is in MANUAL.` The MANUAL button pulses once and the highlights stop for good. |
| ~25–60 **[A]** | Two items per trip. Within the next few trips a RED route or a condition 5 comes up, since each is 1/6 of stage-1 answers **[M 1]**. If they misfile: a red flash, a small shake, `-8 s. Condition 5 goes to REPAIR.`, and the item returns to the tray labelled with its answer. At the first-timer profile's stage-1 pace of 248.0 s per 30 items **[M 3]**, about 8.3 s an item, the 35 seconds after the tutorial hold about 4 more sorts, so a new player has sorted roughly 6 items by the one-minute mark **[A]**. |

The checklist's "core action within about 5 seconds, with no hidden prerequisite" holds by
construction: the first item is in reach of the spawn, the first action is one tap, and nothing
needs buying or clocking in first.

---

## 13. Visuals, feedback and HUD: part of build one

### 13.1 Fx, from the first playable build

- **Server, first statement:** `Fx.applyLighting(Fx.Presets.Temple)`. Temple is the bright preset,
  and it has **no depth-of-field**. Horror, Cozy and Maze each set one (verified in
  `deep-vein/src/shared/Fx.luau`), and this is a game read at 5–30 studs. No new preset and no
  hand-rolled Lighting.
- **The signature particles:**
  - `Fx.dustVolume` over each bay, for warehouse air.
  - `Fx.sparkle` burst on the bin at every correct deposit, the thing the player earns.
  - `Fx.attachGlow` on the tray (it is interactive) and a warm light leak at the Back Room door (the
    thing the player chases).
  - One low-`Range` PointLight per bin, because bins are interactive.
- **Client camera juice**, on the one signature event and its opposite:
  - Correct deposit: `FxClient.fovPunch` (small).
  - Misfile: `FxClient.flash` red plus a small `FxClient.shake`.
  - Perfect Shift: a green `FxClient.flash` plus a shake.
  - `FxClient.theme` on every HUD frame and `FxClient.popIn` on the summary card.

### 13.2 Colour carries exactly one meaning

**Colour means route.** Bins are one depot-steel grey with white text on dark sign boards, so no bin
colour can be confused with a route word. The tag is dark (34, 36, 42) with a manila border strip.
Route words are RED (255, 90, 90), GREEN (80, 220, 110), BLUE (110, 170, 255), YELLOW (255, 215, 60),
PURPLE (200, 130, 255) and WHITE (245, 245, 245); the text is (245, 245, 245) and the torn `?` is
(150, 150, 160). Every one clears WCAG AA contrast for normal text against the tag, **worst 5.07:1**
for RED **[M 10]**. The route is always spelled out, so colour vision is never required.

### 13.3 HUD: phone first

Built on `Responsive.luau` (copied verbatim) under `docs/mobile-ui-brief.md`'s rules: a root Frame
owns the `UIScale`, sized `1/scale`, and everything re-lays-out on `ViewportSize`.

- **Top centre:** the clock (`5:30`), a `CLEARED 12/30` bar, `COMBO x7` when the combo is at least 2,
  and the memo banner under them at stage 3. The tutorial hint line sits below that.
- **Top left:** `CASH`. **Top right, along the top edge:** `MANUAL`, `UPGRADES` (read-only prices,
  plus `Buy at the locker by your spawn`) and `CODES` drawers. `compact` layouts collapse them behind
  top-edge toggles, with at most one open at a time.
- **Bottom centre, above `controlPad`:** the hotbar, one slot per item the cart can carry (2 to 5
  slots). Each slot
  shows its tag line (the route word coloured through RichText) and the item name; the selected slot
  is outlined, and tapping selects. **Width is capped to the centre 40% of the viewport**, the band
  between the thumbstick's left 35% and the jump button's right 25% (mobile brief rule 4). Slots are
  100 design px and shrink to fit.
- **Centre:** toasts (scale-width with a `UISizeConstraint`), the summary card and the Back Room note
  card.

### 13.4 Glyphs

In-world and HUD text uses ASCII plus only these codepoints at or above U+2000, each already
photographed rendering in Roblox Studio **[S `fork-tower/STUDIO.md` §4; the list in
`robloxemu/check_forktower.luau`]**: `—` U+2014, `…` U+2026, `★` U+2605, `🔒` U+1F512, and the
invisible U+FE0F. The tag separator `·` is U+00B7, Latin-1, and not in question. Arrows in the manual
are the ASCII `->`. `check_lostfounddepot.luau` walks every TextLabel and ProximityPrompt string in
the built world, and every TextLabel in the owner's `PlayerGui` after a played shift, and refuses any
other codepoint at or above U+2000. (Fork Tower's version left its HUD strings unguarded.)

---

## 14. Build plan: tests first

### 14.1 Files (the scaffold from `docs/new-game-checklist.md` §1)

```
lost-found-depot/
  default.project.json          Rojo: src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  design/model.luau             this spec's measurements (not shipped)
  src/shared/Config.luau        every tunable in §6
  src/shared/Rng.luau           copied verbatim
  src/shared/Seed.luau          mul32, fmix, Seed.forShift(cfg, userId, shifts, salt)
  src/shared/Rules.luau         base rules, the 12 memos, resolve, explain (toast text), manualLines(stage), memoLine(memo)
  src/shared/Shift.luau         generate(cfg, seed, stage, careerShift) -> { memo, binSlots, items }
  src/shared/Economy.luau       pay, perfect, price, buy (non-mutating), sanitize
  src/shared/Codes.luau         normalize + redeem logic only; the table is passed in
  src/shared/Fx.luau  FxClient.luau  Responsive.luau    copied verbatim
  src/server/Main.server.luau   world, bays, spawn, shift loop, handlers, persistence
  src/server/Secret.luau        the Back Room note and the code table (never replicated)
  src/client/Hud.client.luau    display plus the Select and Redeem remotes only
  tests/*.spec.luau
  README.md  CLAUDE.md  .gitignore (with publish_*.bat and publish_*.sh)
```

Shared modules take `cfg` and their dependencies as arguments. **No `require("./X")` in any Roblox
source.** Server and client use `require(ReplicatedStorage:WaitForChild(...))`.

### 14.2 Unit specs, written and watched fail before each module

1. **`Seed.spec`:**
   - `mul32` matches exact 32-bit multiplication on edge values.
   - The hashed first letter repeats across consecutive shifts in 25% ± 1.5% of 20,000.
   - No intermediate reaches 2^53.
   - The result is an integer in [0, 2^32).
2. **`Rules.spec`:**
   - All 24,960 combinations resolve to a bin.
   - Stage-1 shares are exactly 1/6.
   - The coverage numbers in §3.5 hold to ±0.1 percentage point.
   - Every torn clause behaves as §3.4 says.
   - A swap applies to a torn letter after the own-letter step.
   - `explain` names the deciding rule for every combination.
   - Every manual, memo and explain string is ASCII.
3. **`Shift.spec`:**
   - The same seed gives the same shift.
   - A torn part is `nil`.
   - Own letter vs tag letter independence (§7.3).
   - Answer uniformity per tray position (§7.3).
   - The bin permutation is uniform over slots.
   - The tutorial overrides appear on career shift 1 and never on shift 2.
   - Stage gating: no torn tags at stage 1, no memo before stage 3.
   - A startup-guard helper reports any archetype without a builder id.
4. **`Economy.spec`:**
   - The pay sequence 11..20 and then 20s, with a maximum of 555 from sorts.
   - Re-sorts pay 5 and do not touch the combo; a misfile resets it.
   - The Perfect boundary at 3 vs 4 misfiles, and at the clock.
   - The price ladder and clamps; `buy` never mutates its input.
   - `sanitize` against NaN, negatives, strings, over-max levels, `perfects > shifts` and unknown
     keys.
5. **`Codes.spec`:** normalisation, and the unknown / already / empty / ok cases.
6. **`responsive.spec`:** copied with `Responsive.luau`.

Then `luau-compile --binary` and `luau-analyze` on every source, filtered only for Roblox
global and type noise.

### 14.3 Headless gates (`robloxemu`, which walks the real player path)

Rebuild the bundle before every run:
`py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau`.

**`check_lostfounddepot.luau`:**

- **The world exists.** 12 bays; each has 8 **parented** slot hitboxes with `ClickDetector`s, 6 bins
  with prompts, the tray `PutBack` prompt, the locker's two prompts, a door prompt and a
  `SpawnLocation`. Parts per bay are at most 120.
- **Nobody climbs out.** Every collidable Part in a bay is either a named shell Part (floor, walls,
  lintel, door, Back Room walls) or a fixture (tray, step, bins, locker, spawn pad). No collidable
  fixture has a top face above 6. Every decorative Part, and the Back Room roof, has
  `CanCollide = false` (§4.2).
- **A new player plays shift 1 from the spawn pad.**
  - Find the item whose rendered tag reads `T · 2 · GREEN`, and fire its `MouseClick` from the
    **spawn pad position** (proving it is in reach with no step).
  - Move the root part to the TOYS bin's stand point and fire `Drop`.
  - Then play all 30 items: **read each tag from the world, run `Rules.resolve` against the memo
    board's rendered text, walk to the bin whose sign says it**, and deposit.
  - Assert 30/30, zero misfiles, a Perfect Shift, cash equal to `Economy`'s expected total, and
    backlog 30.
- **A misfile**:
  - The item returns to the tray, and its tag reads its answer.
  - The clock loses exactly 8 s.
  - The re-sort pays 5 and adds no backlog.
- **Reach**: a pick fired from 40 studs away and a deposit fired from the tray are both refused, with
  a `Notice`.
- **Double trigger**: two `MouseClick`s on one item in the same frame produce one carried item.
- **Stages**: play shifts 2 and 3 and assert the torn and memo layers switch on exactly there.
- **Upgrades**: buy at the locker; carry and `WalkSpeed` change; unaffordable and max-level purchases
  are refused with a toast.
- **Wire sweep, exact:**
  - No attribute on any Instance under `Workspace` or `ReplicatedStorage`.
  - Every tray item's rendered record (all Parts' `Size`, `Color`, `Material`, `Transparency`, plus
    the Tag's non-text properties) is a function of (archetype, variant) alone. Group records over 20
    shifts by (archetype, variant) and assert one distinct record per group.
  - No string from `Secret.luau`'s note or code table appears anywhere under `Workspace`,
    `ReplicatedStorage` or any `PlayerGui`, or in any remote payload to a player who has not unlocked
    the room.
  - After unlock, the note reaches the owner's `Scene` payload and **no other player's**.
- **The ending**: a preloaded save with `backlog = 499`. Before the sort, the door prompt refuses with
  `Locked. Backlog: 499 / 500.`. After one correct first-try sort, the door prompt opens that bay's
  door and no other bay's, and `endingSeen` persists across a rejoin.
- **Persistence**: every key of the saved JSON is a string; a leave and rejoin keeps cash, levels,
  shifts and backlog; a second concurrent session does not clobber the lock holder.
- **The glyph allowlist** (§13.4).

**`check_lostfounddepot_spawn.luau`:** the assertions in §9.

**`hudcheck`:** panels, hotbar and toasts measured across the six viewports; nothing tappable in the
bottom-left 35% or bottom-right 25% inside `controlPad`.

**Mutation sweep before any review**, with one owner per file and the sha256 of each file recorded
before and after. At minimum:

- the attribute leak (the answer written as an attribute),
- the tint leak (tag colour chosen by bin),
- the reach check removed,
- the owner check removed,
- `RespawnLocation` not set **and** the re-place removed, together (each alone survives by design,
  §9),
- `backlog` counting re-sorts,
- a torn value kept on the item,
- `Secret` moved to `src/shared`,
- `BayPad.Enabled` left on for free bays,

plus **one control** the suite must not notice: the bin PointLight `Brightness`.

---

## 15. Cut from v1

| cut | why | when it could return |
|---|---|---|
| Co-op, a shared depot | A griefing surface and shared-state sync; the "Avoid solo" list | When there is a design where one player cannot slow another |
| Global leaderboard (and the travel ledger it would need) | A bot is 9.8 s against an expert's 86.0 s even with the ledger **[M 7]** | Only with a metric a bot cannot farm faster than a careful human |
| Extra wings (Umbrella Aisle, Electronics Cage, Aquatics, Cursed Items) | Each is a rule layer plus a catalog plus tests | Post-launch; the Keeper's key and "a door is still locked" set it up |
| Scanner upgrade | No hidden information exists to reveal (§7.3) | Never, in that form |
| Overtime (shift-time) upgrade | 330 s already clears 96.0% for slow readers **[M 6]** | If live data shows otherwise |
| Leftovers carried into the next shift | A death spiral for slow players | Never |
| Procedural shelving aisles and obstacles | A connectivity generator plus a physics walk check, for more walking and no more decisions | If a wing needs a search element |
| A shared daily seed | Conflicts with the per-session salt; small social value | With a shared, public-only daily memo, if wanted |
| Audio (stamp, chime, buzz) | Asset ids cannot be verified without Studio | The first Studio session (§16.1) |
| Badges | Need asset creation, which is publishing | At publish time |
| Anything bought with Robux | The task rule, and §11 | Cosmetics only, after launch |
| Custom meshes and textures, pets, cutscenes beyond the ending, any horror layer | Scope, and assets a solo build does not have | Case by case |
| Emoji beyond the four verified glyphs | Unverified glyphs render as boxes **[S]** | One Studio photograph each |
| A time-remaining bonus | Speed already pays through more shifts per hour | Not planned |

---

## 16. Needs Studio, and needs a live server

Nothing in this list is claimed verified anywhere in this spec.

### 16.1 Needs Studio

1. **First-spawn order.** Does a `RespawnLocation` set in the synchronous head of `PlayerAdded` beat
   the engine's first spawn? Trace the root part per Heartbeat on join, as `fork-tower/STUDIO.md` §3
   did. The step-3 re-place covers the loss either way.
2. **Spawn facing.** Does the character face the arc (−Z) on `BayPad`, and does the default camera
   show the tray, the bins and the Back Room door in the first frame?
3. **Tapping one of 8 tray items on a phone viewport.** Does the intended slot's 3.5 × 3 × 2.5
   hitbox win the tap, and from where does Roblox measure `ClickDetector.MaxActivationDistance`?
4. **Legibility:**
   - tag BillboardGuis at 5–12 studs,
   - bin SurfaceGui signs at 23–28 studs,
   - the memo board from P,
   - the manual board from P,
   - all of the above on a phone viewport, under the Temple preset's bloom and sun shadows from
     16-stud walls,
   - the route words at their measured contrast in the actual renderer.

   Use GDI window grabs, not MCP `screen_capture`, which does not render BillboardGuis
   **[S `fork-tower/STUDIO.md` §8]**.
5. **Recognisability** of the 16 Part-built items. The tag's name line makes sorting fair without
   it, but the "tag contradicts the look" hook needs the look to read.
6. **Prompts:**
   - exactly one `Drop` prompt at the 2.49-stud gap,
   - `PutBack` on R alongside the bins' E,
   - both locker prompts,
   - all of them as tap buttons on a phone.
7. **Feel:**
   - walk speed 16 → 22,
   - the 23-stud tray-to-bin leg,
   - whether two items per trip on shift 1 is too few or too many,
   - whether 8 s reads as fair,
   - the model's decode and error assumptions against a real first play.
8. **The carried crate:** does a welded, massless, non-querying Part obstruct the camera, prompts or
   movement?
9. **Climbing:** can anything in a bay really be climbed out of? Walk and jump along every wall from
   the bins, the tray step and the locker.
10. **Render cost** of 12 bays, 80 studs apart: about 96 PointLights and 12 dust emitters. Fork
    Tower's 4,110-Part test was culled at 220+ studs, so it does not answer this
    **[S `fork-tower/STUDIO.md` §6]**.
11. **Fx:** the sparkle, FOV punch, flashes and the 3 s Back Room camera tween.
12. **The HUD on a real phone-sized window:** the hotbar in the centre band and the drawers along
    the top.
13. **Glyphs:** the four allowlisted glyphs in this game's fonts, and any string added later.
14. **Audio:** choose and verify three sound asset ids, as the first post-v1 addition.

### 16.2 Needs a live, published server

1. **Profile load time** on join. It sets how long a first-timer looks at an empty tray.
2. **Real replication lag and jitter** on mobile networks, to confirm `ReachSlack = 2` produces no
   honest reach refusals. Count refusal toasts per shift in the server log.
3. **DataStore behaviour** under the session lock during a real server shutdown (`BindToClose`).
4. **The content-maturity questionnaire and its Preview page.**

---

## 17. Self-review

Read end to end after writing, against the three review questions: no placeholders, no two sections contradicting each other, every number justified.

**No placeholders or TBDs.** Every table cell holds a value. The memo lines, the manual text, the
catalog, the Back Room note, the launch code, the colours, the coordinates and the remote payloads
are all written out. The one open unknown, the actual sound ids, is a cut item with a return
condition, not a hole in the spec.

**Contradictions found and fixed while writing:**

1. **The travel floor.** An early draft had the server enforce a per-leg travel floor. An earlier run
   of the model showed it did nothing (a 4.3 s bot). A cumulative ledger worked (9.8 s), but showed that no
   walking limit bounds a bot, and with no leaderboard there is nothing for it to protect. The
   anti-exploit section, the cut list and §2 now all say "not built, and why", and `model.luau`'s
   comment was changed from "what the server enforces" to "evaluated, not shipped".
2. **The penalty and the clock.** A 5 s penalty with a 300 s clock was first proposed. An earlier run
   of the model, made before the penalty changed, showed a guesser clearing 61.5% of stage-3 shifts
   under it; the current model still prints that reading beat guessing by only 1.10x at 5 s
   **[M 5]**. Both moved, to 8 s and 330 s. §2, §6.3 and §12 all quote 330 s (`5:30`) and 8 s, and
   `Config` values are stated once, in §6.
3. **`ItemReach`.** It was first 10, which put the farthest tray slot exactly on the edge (10.00).
   It is 12, and §4, §4.1, §6.2, §7.2 and §12 agree.
4. **The scanner.** It stayed in the upgrade list after torn values were made nonexistent. It is now
   cut everywhere, with the reason in §2 and §15.
5. **The seed.** The brief's shared date seed conflicts with the checklist's per-session salt. §2,
   §7.1 and §15 now consistently choose the salt.
6. **The store text.** The brief's description promised co-op, weekly wings and "a new procedurally
   generated depot". §2 now names the three lines v1 must not ship.
7. **Colour.** The first bin colours would have collided with route colour words (a BLUE route
   beside a blue bin). Colour now means route only (§13.2).
8. **`Codes`.** The code table was going to live in shared `Config`. It is in `Secret.luau`
   (§8.2), and the shared `Codes` module takes the table as an argument (§14.1).
9. **Climbing.** 12-stud walls, beside bins a player can stand on, left 0.8 studs of margin. Walls
   are now 16, and a "tallest standable top" rule is stated and checked (§4.2).
10. **The climbing check contradicted the shell.** The first wording of §14.3 said "every Part whose
    bottom is above y = 6 is non-collidable". The lintel over the Back Room door (y 10–16) is shell
    and must collide, so the check would have failed a correct world. The rule now names the shell,
    names the fixtures, and bounds only fixtures. The same pass found the opposite hole: a collidable
    manual board is a ledge at y = 12, so every decorative Part is non-collidable, whatever its
    height (§4.2).
11. **The combo on a re-sort.** §5.1 first read as if a re-sort after a misfile also grew the combo,
    while §6.4 said re-sorts leave it alone, which is also what the model does. §5.1 now splits the
    two cases.
12. **The spawn mutations.** §9 first called both halves of the spawn pattern "independently
    load-bearing" while asserting that removing either one alone still passes. The halves are
    redundant by design, and the mutation that proves the check can see the defect removes both.
13. **A test that would have flaked.** §7.3 first asked for 1/6 ± 1% per tray position "over 40,000
    items", which is 5,000 samples per position. One standard deviation of a 1/6 share over 5,000
    samples is 0.53 percentage points, so the tolerance was 1.9 standard deviations, applied to 48
    (position, bin) comparisons at once: correct code would fail most runs. It is now 40,000 samples
    per position, where the tolerance is 5.4 standard deviations per comparison **[R]**.
14. **The Back Room props.** The key was described both "on the shelf inside" and "hanging beside
    the door". It is one key, on a hook beside the door; the shelf inside is empty (§8.3), and the
    Parts count in §6.2 counts it once.
15. **The first frame showed data that did not exist yet.** §12's opening row put `CASH 0` and the
    shift clock on the HUD before the profile had loaded, while §5 says LOADING shows only
    `Unpacking your cart...`. It also listed the memo board as readable from the spawn, where you
    see its back. Both rows now match §4 and §5.
16. **The mutation list contradicted §9.** It listed "`RespawnLocation` not set" and "the re-place
    removed" as separate kills, which §9 says each survive by design. The list now asks for them
    together.
17. **Overclaims.** The core loop said every tag "deliberately does not match" its item; the letter
    matches one time in four by construction. §4.2 said "nothing collidable" is above 6 studs; the
    walls are. §3.6 cited a stage-2 time the model never printed. All three now say what is true, and
    the 4.3 s per-leg bot is labelled as an earlier model run.

**Every number justified.** Each number in §6 has a reason and a source tag. Numbers resting on the
model's player-profile assumptions are marked, and the assumptions themselves are in the table at
the top. What only Studio or a live server can answer is §16, and nothing in §16 is claimed anywhere
else in this file.

**Checklist traps** (`docs/new-game-checklist.md` §3), each answered:

| trap | answer |
|---|---|
| DataStore integer keys | None exist (§8.1). |
| LCG low bits | `Rng.below` everywhere (§7.2). |
| Seed overflow | `mul32`'s largest intermediate is 1.29e10, far under 2^53 (§7.1). |
| Session lock | A GUID token (§8.1). |
| Replayable RNG | The per-session salt (§7.1). |
| Silent no-ops | A toast for every refusal (§5.1), and why malformed remote payloads differ (§10.2). |
| One-time rewards | An atomic code flush that refuses when it cannot persist (§8.1). |
| Unfair randomness | Every combination resolves; torn values do not exist; the name is on the tag (§3.5, §7.3). |
| Unbounded coordinates | The bay free list (§4). |
| Ownership vs selection | Upgrades are levels, and the selected carried slot never implies ownership of anything (§8.1). |
