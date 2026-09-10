# Fork Tower — third pass: the core loop, and REVIEW-2's open list

**Verdict: still BLOCK**, and now for exactly one reason — the game has never been opened in Roblox
Studio and no human has ever played it. Everything else REVIEW-2 left open is closed and each
closure is backed by a measurement quoted below with its numbers.

**This file covers two passes.** The third pass (everything down to the first mutation sweep) closed
REVIEW-2's list and named three new findings, two of which it was not allowed to fix because they
needed `robloxemu/check_forktower.luau`. A **fourth pass** with that file writable closed both — the
section titled *FOURTH PASS* is its evidence, and the "What I could NOT close" list below is marked
up accordingly. The one remaining open item that is not "nobody has played it" is finding 4, an
unmeasured engine assumption, written up there with what to watch for in Studio.

Read alongside REVIEW.md (first pass) and REVIEW-2.md (second pass, the authority on what was
broken).

```
Fork.spec        53 passed, 0 failed      (unchanged)
Section.spec     50 passed, 0 failed      (was 47/0 — three new assertions)
Build.spec       31 passed, 0 failed      (unchanged)
Codes.spec       19 passed, 0 failed      (unchanged)
Rng.spec         32 passed, 0 failed      (unchanged)
responsive.spec  70 passed, 0 failed      (unchanged)
check_forktower 108 passed, 0 failed      (robloxemu; was 85/0 — see the fourth pass below)
world.check      71 passed, 0 failed      (in this repo; was 70/0 — one new assertion)
```

`luau-compile --binary` clean on all 11 sources. `luau-analyze` clean on all 11 sources and on both
new test files after filtering Roblox-global/type noise — two real findings it produced along the
way (a `math.abs` union type and a shadowed `band`) were fixed rather than filtered.
`find_mojibake.py` reports nothing.

---

## A + B — the headline finding, closed

> REVIEW-2: *"THE CORE LOOP IS DOMINATED: the optimal way to play Fork Tower is to never read an
> inscription."* Always-strongest beat always-safe on **95.1% of 3000 seeds** (45.26 vs 37.10 mean
> score), and the star count was printed on every door on a billboard **larger than the inscription
> it dominated**.

### (A) The inscription is the only information

`dressFork(lane, level)` in `src/server/Main.server.luau` owns both states of a fork and is the
only thing that writes either. An **unread** door now carries:

| | before | after |
|---|---|---|
| `TraitLabel` billboard | `👑 Forgylte vinger` + `★★★★` | `🚪 DØR` |
| door `Color` | the trait's theme colour | `Config.Fork.UnreadColor` |
| `DoorGlow.Color` | the theme accent | `Config.Fork.UnreadAccent` |
| prompt `ObjectText` | the trait's label | `🚪 DØR` |
| pad `Inscription` billboard | the rule, in full | `🔒 INNSKRIPSJONEN ER ULEST / HOLD LES — 1.1 s` |
| `State.rule` on the wire | sent every push | `nil` until the floor is read |

The theme colour is in that list because it was most of the leak on its own: it narrows twelve
traits to two, and `gold` / `void` are the strong pair (powers 5/4 and 5/4) while `troll` is the
1-or-4 pair. A player who learned six colours would have kept playing always-strongest without ever
reading a word.

The **signs stay visible**, and that is deliberate rather than an oversight. `Fork.luau` draws the
ordered pair of distinct sign sets *before* anything consults the trap, so the arrangement is
uninformative by construction — REVIEW.md's 40 000-fork spec measures exactly that. The signs are
the vocabulary the inscription is about to use; hiding them would make the read unreadable rather
than expensive.

Every placeholder written in `buildFork` is the UNREAD one, so a fork that somehow escaped dressing
fails **closed**. The client gate and the world gate read the same `p.readFloors` set, so there is
one condition and not two that can drift apart.

### (B) Reading costs 1.1 seconds, on the server's clock

`Config.Fork.ReadSeconds = 1.1`. The mechanic is a hold on a `ProximityPrompt` on the fork pad —
but the hold is only what the player *feels*. `ProximityPrompt.HoldDuration` lives on the client and
is the first thing an exploiter deletes (`fireproximityprompt` triggers a prompt with no hold at
all), so `onReadInscription` charges the time itself, two ways so neither fails open:

* **the honest path** — `PromptButtonHoldBegan` replicates, so the server knows when the hold
  started. A full hold is already 1.1 s old when `Triggered` arrives and the read completes on the
  spot;
* **anything else** — a client that fires the prompt directly is charged the **remainder** on the
  server's own clock, via a `task.delay` that re-checks the player is still standing at that
  unanswered fork before it hands anything over.

The prompt also has its own key (`Enum.KeyCode.R` / `ButtonY`). `ProximityPrompt.Exclusivity`
defaults to `OnePerButton`, and the doors sit 8 studs from the middle of a pad that is 20 deep —
well inside both activation radii — so on `E` the read prompt would have vanished exactly when the
player drifted toward a door. That is engine documentation, not a measurement; nothing here renders
a prompt.

### The number, and the measurement behind it

`tests/readcost.measure.luau`, 5000 real run seeds × 10 floors against the real `Fork` and
`Section` modules. The trap's only cost is time, so the read is priced in time.

**The model, with every assumption stated.** A hop between platform centres costs
`(TileSize + gap(level)) / walkSpeed` — Roblox keeps horizontal velocity while airborne, so ground
speed governs. A section of `count` platforms costs `count` hops. `walkSpeed` is the speed the
player *actually has* on that floor, `Config.WalkSpeed` plus every trait taken so far, clamped
upward exactly as the server's `traitTotals` does. A hazard hit costs one hop. Jump height does not
enter: every rise is clearable by construction and the airborne time is already paid for by the
horizontal speed.

```
  hit rate | reader s | guesser s | guesser extra s | break-even read s
  ---------+----------+-----------+-----------------+------------------
     0.00  |    38.25 |     49.35 |           11.10 |            1.110
     0.25  |    40.64 |     52.96 |           12.32 |            1.232
     0.50  |    43.02 |     56.57 |           13.55 |            1.355
     0.75  |    45.41 |     60.18 |           14.77 |            1.477
     1.00  |    47.79 |     63.78 |           15.99 |            1.599

  traitless upper bound (WalkSpeed fixed at 16, hit rate 0): break-even 1.499 s
```

The hazard hit rate is the one number in the model that is not derived from anything, so the whole
range is reported and the shipping number is taken from **hit rate 0 — the perfect climber, who
gets the SMALLEST justified read cost**. The traitless row is reported because it is what a naive
reading of Config would give, and it is **35% too generous**: strong traits are slow traits (the
five- and four-power traits all have `speed = 0`), so a real player's speed grows from 16 to 24-28
and their seconds-per-platform shrinks.

**1.110 s is the break-even. 1.1 s ships.** At that number, over 5000 seeds:

```
  hit rate 0.00: READ 49.25 s (38.25 climbing + 11.00 reading), GUESS 49.35 s -> read is -0.2%
  hit rate 0.50: READ 54.02 s (43.02 climbing + 11.00 reading), GUESS 56.57 s -> read is -4.5%
  per seed at 1.10 s: READ faster on 2333, GUESS faster on 2667, tied 0 (of 5000)
  worst case for a reader +79.3%, worst case for a guesser -46.0%
  traps a guesser ate, by count: 0:5 1:48 2:252 3:635 4:992 5:1263 6:945 7:611 8:207 9:40 10:2
```

That is the trade the brief asked for, and it is a genuine one: **0.2% apart on the mean**, with the
guesser ahead on 53.3% of individual seeds because their trap count is a coin and the reader's is
zero. The reader is buying variance away, not seconds — worst case for a guesser is **-46.0%** (they
ate all ten) against **+79.3%** for the reader on the five seeds in 5000 where the guesser ate none.
Reading is never worse than 0.2% and is 4.5% better for anyone who is not perfect, which is the
"still worth it on most forks" half.

### Is the loop still dominated? No — and here is the number

The dominance was never that safe beats strong. It was that the **score-maximising strategy needed
zero reads**, so the mechanic the whole game is built on was optional. Same sweep, same seeds:

| strategy | reads | traps eaten | total seconds | mean score |
|---|---|---|---|---|
| GUESS (never read) | 0 | 4.94 | 49.35 | 31.65 |
| READ, take the safe door | 10 | 0.00 | 49.25 | 31.72 |
| READ, take the stronger door | 10 | 4.99 | 64.21 | **39.21** |

Taking the safe door is worth **+0.07 score** over guessing — nothing, and it should be nothing,
because `Config.Fairness.PowerBalanceTolerance` deliberately decorrelates the trap from the reward.
The safe reader is buying time and certainty. The **greedy** reader is the one the ordered
leaderboard rewards, and greedy is now **unreachable without ten reads**: a non-reader cannot tell
`🚪 DØR` from `🚪 DØR`, so their expected score is the 31.65 of a coin. Reading is worth **+7.56
score (+24%)** and costs 30.1% more wall clock than guessing. The leaderboard now rewards the
mechanic instead of routing around it, which is the inversion REVIEW-2 asked for.

### What I saw when I played it

`robloxemu`, run seed 4, a reader walking all ten floors and a guesser walking the same tower
without reading anything. Verbatim from the walk:

```
--- FLOOR 1 -------------------------------------------------
  before reading   pad: ETASJE 1/10 / 🔒 INNSKRIPSJONEN ER ULEST / HOLD LES — 1.1 s
                 doors: [🚪 DØR] signs flame,eye   |   [🚪 DØR] signs frost,eye
              HUD says: read=false  rule=(nothing)
  half-way through the hold (0.55 s): pad still says ... INNSKRIPSJONEN ER ULEST ...
  read completed after 1.15 s
  after reading    pad: ETASJE 1/10 / ❄️ STOL PÅ RIMET — DEN MERKER FELLA
                 doors: [👑 Forgylte vinger / ★★★★]   |   [🍌 Bananforbannelse / ★]
  the player concludes: door 2 is the trap -> walks through door 1
  toast: safe: Trygt valg: 👑 Forgylte vinger
  section built: 5 platforms, 0 hazards, penalty=false, theme=gold
```

Floor 4 is the liar floor on this seed and it reads correctly:
`👁️ VOKTEREN LYVER — ØYET MERKER DEN TRYGGE DØRA`. Floor 10 is the game in one line — the
inscription resolves to *`🌌 Nullsegl ★★★★★` is the trap, `🍌 Bananforbannelse ★` is safe* — which
is exactly the "would you rather" the title promises and which the player could not even have been
asked before this pass, because they would simply have taken the five stars.

Ten reads cost **11.50 s** of the run as driven (11.00 s of charge plus the harness's 0.05 s
settle per floor). The reader summited with 70 platforms, zero traps, and
`Tomroms Kongsklatrer — Uvanlig, 35 points`. The guesser, always taking the left door and reading
nothing, ate **3 traps** (a lucky seed; the mean is 4.94), climbed **82 platforms**, and scored
**37** — *higher* than the reader. That is the mechanic working, not failing: reading the
inscription and taking the safe door is a time-and-variance play, not a score play. Zero server
errors, zero warnings across both runs.

---

## The two SURVIVED MUTATIONS — closed by fixing the ASSERTIONS

### M2, the hazard-clearance guard

REVIEW-2: halving the respawn offset dropped the minimum clearance from 2.00 studs to **0.75** —
below the `CharacterHalfWidth = 2` the whole model is built on — and every suite stayed at baseline,
because `tests/Section.spec.luau` only asked `if ox > 1e-9 and oz > 1e-9`, which any clearance above
zero satisfies.

The assertion now measures the **whole geometry**, re-derived in the spec from the section's own
numbers rather than read out of `Section.luau`. The hazard sits `d` studs from the platform centre
on its own axis and the character stands `t` studs the other way, bounded by

```
   t <= p.size/2 - ch            (the whole character stays on the platform)
   t >= ch + hz.size/2 - |d|     (the whole character clears the hazard)
```

and — this is the part that makes it a real assertion — **hazard clearance + edge margin equals the
width of that interval for every `t` inside it**. One stud of clearance costs exactly one stud of
edge. So the only point that maximises the smaller of the two is the midpoint, and asserting
`min(clearance, edge) >= band/2` pins it uniquely.

*Red first, watched:* with the assertion added and `Section.luau` untouched —

```
FAIL: the checkpoint sits at the MIDDLE of its clear band, not at either end
      (worst side is 1.00 studs short of the 1.00-stud half-band;
       worst hazard clearance 2.00, worst platform-edge margin 0.00)
  respawn band: 2.00 studs wide, worst clearance 2.00, worst edge 0.00
Section: 49 passed, 1 failed
```

That single inequality closes **two** findings at once, because "flush with the platform edge" and
"halved offset" are the two ends of the same interval. `Section.build` now takes the midpoint and
`Section.check` refuses a section that leaves it.

*Mutation re-applied:* `local t = (p.size / 2 - ch) / 2` — REVIEW-2's M2, literally —

```
Section: 47 passed, 3 failed
FAIL: the checkpoint sits at the MIDDLE of its clear band ... worst hazard clearance 0.75,
      worst platform-edge margin 1.25
FAIL: Section.check passes a real section
FAIL: ...with nothing to report -> got 4, want 0
```

0.75 studs, the number REVIEW-2 measured, to the decimal. `Section.luau` restored and sha256-verified
byte-identical. In the built world (`tests/world.check.luau`, measured on the real Parts by touching
every hazard in a full trap run): **36 hazards, worst clearance 1.00, worst edge margin 1.00.**

### M5, "MaxLanes is a FLOOR"

REVIEW-2: flipping `math.max(Config.World.MaxLanes, Players.MaxPlayers)` to `math.min` left every
suite and the headless check green, because `check_forktower.luau` line 900 only asserts
`seated > 0` — the seated **count** was never compared to the pool.

There is a second reason that mutation was invisible and REVIEW-2 did not name it: **the emulator's
default `Players.MaxPlayers` is 12, which is BELOW `MaxLanes = 24`**, so a test run at the default
cannot tell `max` from `min` in the direction the claim is actually about. The claim is *"a Studio
slider can no longer put more players in the server than there are towers"* — which is only
exercised when the slider is above the config.

`tests/world.check.luau` therefore boots its own server with `Players.MaxPlayers = 40` set before
the script runs (`laneCount` is computed once, at load), joins `pool + 3 = 43` players, and asserts
`seated == min(present, max(MaxLanes, MaxPlayers))` — with the expected pool computed in the test
from the two inputs and never read back out of the server.

*Mutation re-applied:*

```
FAIL: the lane pool is max(MaxLanes 24, MaxPlayers 40) = 40, so 40 of 43 players are seated
      -> got 24, want 40
fork tower world: 69 passed, 1 failed
```

Baseline prints `crowd: 43 players present, 40 seated, 3 unseated (pool should be 40)`.

**This does not repair `check_forktower.luau` itself.** That file lives in `robloxemu/`, which this
pass could only read. Its weak assertion still stands there. See "Still open", item 2.

---

## The spent-skip refund — closed

REVIEW-2: a skip armed and spent on a floor turned that floor's trap into a normal section, but
nothing recorded *that it had been spent on that floor*. `buildLane` recomputed
`Fork.isTrap(floorData, slot)` on rejoin and rebuilt the penalty section — the player lost the skip
**and** got the trap. Worse, `Section.build` mixes `PENALTY_MIX` into its seed, so the rebuilt
section was a completely different walk and the world moved under a player mid-climb.

The profile now carries `skipped` (and, for the same reason, `readFloors`), both written as **dense
lists of level numbers** rather than as maps — a JSON round-trip through DataStore turns numeric
keys into string keys, so `saved.skipped[3]` comes back `nil` and the fix would have worked in
memory and failed on disk. `denseList`, which this file already trusts for `picks` and `slots`,
reads them back.

`buildLane` is now `Fork.isTrap(floorData, slot) and not p.skipped[level]`.

*Mutation re-applied* (`and not p.skipped[level]` removed):

```
FAIL: a skip spent on a floor is STILL spent after a rejoin — the trap does not come back
      -> got true, want false
FAIL: ...and the section is the same length it was (5 platforms) -> got 9, want 5
FAIL: ...and platform for platform it is the same walk, not a reseeded one -> got 5, want 0
```

5 platforms → 9, and all five surviving platforms at different coordinates: exactly the two symptoms
REVIEW-2 described. The check also asserts the skip count itself did not come back (3 armed → 2
left, still 2 after the rejoin).

---

## The three "Broken BY the fixes" — closed

### 1. A player the server could not seat is never handed a lane that frees up

`claimLane` was only ever called from `buildLane`, and `buildLane` only from `PlayerAdded` and
`Rebirth`, so nothing re-ran it when `teardownLane` freed an index. `seatWaiting()` now runs from
`PlayerRemoving` — **and from nowhere else**, which is the part that matters: `buildLane` tears its
own lane down before re-claiming one, so sweeping from inside `teardownLane` would let a waiting
player take the lane out from under a player who was merely rebirthing. A lane only genuinely frees
when its owner leaves.

The contradictory copy is fixed too. The waiting pad's sign says *"Venter på et ledig tårn …"* while
the toast said *"prøv en annen server"*; the toast now says
*"Alle tårnene er opptatt akkurat nå — du får det første som blir ledig"*, which is a promise the
server now keeps.

*Mutation re-applied* (the `seatWaiting()` call deleted):

```
FAIL: a SEATED player leaving hands their freed lane to the player who was waiting
FAIL: ...the very lane that was freed -> got nil, want Lane_0
FAIL: ...and the player was actually moved into it, not left on the waiting pad
```

The check asserts the waiter gets **the very lane index that was freed**, and that their character
was actually moved into it rather than left standing on the waiting pad.

*A defect in my own test, found by the sweep and fixed:* the first version of that block **raised**
instead of failing when the seating sweep was missing (`forkOf(nil, 1)`), so the mutation reported
`CRASH` rather than a count. A check that crashes where it means to fail reports the same thing for
every defect and tells you nothing about which one you have.

### 2. The respawn point flush with the platform edge

Closed by the same midpoint fix as M2, above. Measured: **0.00 studs of edge margin → 1.00**, and
2.00 studs of hazard clearance → 1.00. The band is 2.00 studs wide, so 1.00/1.00 is the best the
geometry allows and every other split is strictly worse on its smaller side.

### 3. The per-LANE hazard debounce

One `lane.hazardReadyAt` meant one hit made **every hazard in the whole tower** inert for a full
second. `readyAt` is now an upvalue per hazard — one number per hazard, and the scope the cooldown
always meant.

*Mutation re-applied* (hoisted back to the lane):

```
FAIL: two DIFFERENT hazards on floor 10 both bite inside one cooldown window (1 did) -> got 1, want 2
```

The check fires two different hazards 0.05 s apart (well inside the 1 s cooldown) and requires two
bites, then fires the *same* hazard forty more times and requires zero — so it measures the debounce
in both directions rather than just switching it off.

---

## Mutation sweep

Eleven deliberate defects applied one at a time to the shipping source, every suite plus both
headless runs after each, restored and sha256-verified between each. Plus a control the sweep must
NOT notice.

| mutation | result |
|---|---|
| M5: `math.max` → `math.min` on the lane pool | world 69/1 |
| M2: respawn offset halved | Section 47/3, headless 84/1, world 69/1 |
| stars back on an unread door | world 65/5 |
| theme colour back on an unread door | world 68/2 |
| `rule` pushed to a client that has not read | world 68/2 |
| the read is instant | world 66/4 |
| the read is charged client-side only (an exploiter reads free) | world 66/4 |
| the spent skip is forgotten | world 67/3 |
| `readFloors` not saved | world 67/3 |
| a freed lane goes to nobody | world 66/4 |
| the hazard debounce back to per-lane | world 69/1 |
| CONTROL: door light `Brightness` 2.2 → 3.4 | 53/0, 50/0, 31/0, 19/0, 32/0, 70/0, 85/0, 70/0 — correctly invisible |

The control is doing its job in both directions: the harness is not simply reporting everything red,
and a real, visible change that no assertion in this repo claims to see passes untouched.

Note the shape of that table. Every one of the eleven is caught by `world.check.luau` and only two
are caught by anything else — which is the honest statement of where this pass's coverage lives, and
a reason to run both headless files rather than one.

*(Superseded by the fourth pass's sweep, further down: with `check_forktower.luau`'s two weak
assertions fixed and the wire enumeration added, the headless file now catches ten of twelve on its
own. The lopsidedness above was the symptom of the two weak lines, not a property of the defects.)*

---

## FOURTH PASS — the replication hole, and the two weak assertions in `robloxemu/`

Same day, a pass with `fork-tower/` **and** `robloxemu/check_forktower.luau` writable. It closes
open items 3 and 2 above, in that order, because they are one change: the fix breaks the harness's
`readFork` helper and the two edits only make sense together.

### 3 — the fork's own data no longer replicates

**What crossed the wire before.** `buildFork` wrote `ForkPad.TellKind`, `ForkPad.RuleInverted` and
`Door.Marked` at build time. Attributes replicate to every client, and with the sign nubs already
carved in the open those three ARE the fork: `TellKind` + the visible signs give you the marked
door, and `RuleInverted` turns that into the trap. A player running a script resolved every
inscription instantly and never paid the 1.1 s or ate a trap; a player without one paid both. The
5000-seed break-even that prices the read was describing a game only honest players were playing.

**The fix is four lines and one function.** All three moved into `dressFork`, gated on the same
`read` flag everything else there is gated on, written as `SetAttribute(name, if read then v else
nil)` — `nil` removes the attribute outright, so an unread fork on a rejoin looks exactly like an
unread fork on a fresh build. `buildFork` now writes `Level`, `Slot` and `Signs` and nothing else.
Nothing on the server ever read those three: `Fork.isTrap(floorData, slot)` works off the plan.

**What crosses the wire now.** `check_forktower.luau` walks the whole `Fork_<n>` subtree and lists
every attribute on every Instance, with the level and slot numbers folded out of the names so one
string covers every floor and both doors. Verbatim, and asserted against an exact expected list:

```
  . [Folder] :: Read                                  ForkPad_L [Part] :: Level
  Door_L_S [Part] :: Level,Signs,Slot                 ForkPad_L/Inscription [BillboardGui] ::
  Door_L_S/Choose [ProximityPrompt] ::                ForkPad_L/Inscription/Text [TextLabel] ::
  Door_L_S/DoorGlow [PointLight] ::                   ForkPad_L/PadGlow [PointLight] ::
  Door_L_S/Sign_* [Part] :: Sign                      ForkPad_L/Read [ProximityPrompt] ::
  Door_L_S/Sign_*/SignGlow [PointLight] ::            FxDustVolume [Part] ::
  Door_L_S/Sign_*/SignLabel [BillboardGui] ::         FxDustVolume/FxDust [ParticleEmitter] ::
  Door_L_S/Sign_*/SignLabel/Text [TextLabel] ::
  Door_L_S/TraitLabel [BillboardGui] ::
  Door_L_S/TraitLabel/Text [TextLabel] ::
```

Before the fix that list read `Door_L_S [Part] :: Level,Marked,Signs,Slot` and
`ForkPad_L [Part] :: Level,RuleInverted,TellKind`. **The test is the enumeration, not the three
names**, which is what makes it survive a rename or a relocation — proved below with two mutations
that do exactly that.

Five attributes survive, and each is pinned to something the player can already see, so none of
them can be a smuggler's pocket under a permitted name: `Fork.Read` is the boolean the pad's own
prompt state shows; `ForkPad.Level` and `Door.Level` are the floor number printed on the pad;
`Door.Slot` is the door's own index; `Door.Signs` is asserted to list exactly `SignsPerDoor` kinds,
each of which has a `Sign_<kind>` nub rendering it above the door.

**Nothing distinguishes the trapped door from the safe one.** The inventory covers attributes; the
second half covers everything rendered. `check_forktower.luau` records `Size, Color, Material,
Transparency, Anchored, CanCollide, CanQuery, CanTouch, Brightness, Range, StudsOffset,
AlwaysOnTop, MaxDistance, Text, TextColor3, TextScaled, Font, TextStrokeTransparency,
BackgroundTransparency, ActionText, ObjectText, HoldDuration, MaxActivationDistance, Enabled,
RequiresLineOfSight, KeyboardKeyCode, GamepadKeyCode` for a door and everything under it, and
gathers one record per unread door from every fork six players walked past. Position and CFrame are
excluded on purpose: door 1 and door 2 are mirrored across the pad and floor 7 is higher than floor
1. Measured:

```
  wire: 102 unread doors -> 1 distinct record; 51 unread pads -> 1
```

**One record over 102 doors.** Since every unread door renders the same string, the trapped door
renders what the safe one renders, on every floor of every run in the file. What is left varying
between the two doors is the SIGNS, and that is the point — they are the vocabulary the inscription
is about to use. `Fork.luau` draws the ordered pair of distinct sign sets *before* anything consults
the trap and `Fork.spec` measures that over 40 000 forks (sign count, single signs and whole
arrangements all uninformative). So the client's whole view of an unread fork is a function of
(level, sign arrangement) and nothing else, and the sign arrangement is independent of the trap.
That is the complete statement, in two halves, and neither half is "we renamed it".

The harness had to be taught to pay: `readFork` now calls `payRead`, which fires
`PromptButtonHoldBegan`, advances the scheduler by `ReadSeconds`, then fires `Triggered` — the
honest path, idempotent so a floor already read is not charged twice. `tests/world.check.luau`'s
`trapSideOf` needed the same reordering and gained the assertion that an **unread** fork returns
nil to a script, which is the exploiter's-eye view of the whole fix.

### 2 — the two weak assertions, fixed in place

**The hazard-clearance guard.** It counted only `gap < 0` — checkpoints *inside* their hazard — so
any clearance above zero satisfied it. Now it re-derives the clear band from the real Parts (the
platform's own size, the hazard's own size and offset, the axis read off the world rather than off
an attribute) and requires `min(clearance, edge) >= band/2`. Baseline prints
`checkpoints: 36 hazards, worst clearance 1.00, worst edge margin 1.00`.

*Mutation re-applied* — REVIEW-2's M2, `local t = (p.size / 2 - ch) / 2`:

```
FAIL: ...and lands the player in the MIDDLE of the clear band, not at either end (36 of 36
      off-centre; worst is 0.25 studs short of half its band; worst hazard clearance 0.75,
      worst platform-edge margin 1.25)  -> got 36, want 0
fork tower: 106 passed, 2 failed
```

0.75 studs, REVIEW-2's number to the decimal. The second failure is `Section.check`'s own warning,
and that raises the question the mutation alone cannot answer: is the new assertion measuring the
world, or just riding on the warning? So it was run again with **`Section.check`'s midpoint guard
silenced as well**, which removes the warning entirely:

```
M2' (offset halved AND Section.check's own guard replaced by `if false`)
FAIL: ...and lands the player in the MIDDLE of the clear band ... worst hazard clearance 0.75,
      worst platform-edge margin 1.25  -> got 36, want 0
fork tower: 107 passed, 1 failed          <- the only failure in the file
```

**The lane pool.** `truthy(seated > 0)` was the whole of it. It now computes the pool in the test
from the two inputs — `MaxLanes` spelled out at the top of the file, and the `Players.MaxPlayers`
the server actually booted with — and asserts `seated == min(present, pool)`. Baseline prints
`crowd: 33 players present, 24 seated, 9 unseated (pool = max(MaxLanes 24, MaxPlayers 12) = 24)`.

*Mutation re-applied* — REVIEW-2's M5, `math.max` → `math.min`:

```
FAIL: the lane pool is max(MaxLanes 24, MaxPlayers 12) = 24, so 24 of the 33 players present
      are seated -> got 12, want 24
fork tower: 107 passed, 1 failed
```

One honest limit, written into the file next to the assertion: this server's `MaxPlayers` is 12,
the emulator's default, which is **below** `MaxLanes`, so the *claim in words* — "the pool is never
smaller than the place's max-player count" — is trivially true here under `min` too. The line above
is what kills M5; the direction that separates the two is a slider set ABOVE `MaxLanes`, and that is
`tests/world.check.luau`, which boots at `MaxPlayers = 40`. Between the two files both directions
are now measured, and neither file is the only one that can see M5.

### The sweep, re-run whole

Twelve edits, applied one at a time to the shipping source with a byte-level patcher, every suite
plus both headless runs after each, restored and sha256-verified between each. A full manifest of
`src/` + `check_forktower.luau` was taken before and after and is identical.

Baseline: `Fork 53/0  Section 50/0  Build 31/0  Codes 19/0  Rng 32/0  responsive 70/0
headless 108/0  world 71/0`.

| mutation | headless | world | caught by |
|---|---|---|---|
| L1 `TellKind`+`RuleInverted` ungated (the leak, verbatim) | **107/1** | 71/0 | the inventory |
| L2 `Marked` ungated | **107/1** | **70/1** | the inventory; world's unread-fork check |
| L3 the same leak, **renamed** to `Tk` | **106/2** | 71/0 | the inventory, unread AND read |
| L4 the same leak, **relocated** onto the Inscription billboard | **106/2** | 71/0 | the inventory, unread AND read |
| L5 unread door painted its theme colour | **107/1** | **69/2** | 6 distinct door records, not 1 |
| L6 stars back on an unread door | **107/1** | **66/5** | 12 distinct door records, not 1 |
| L7 unread prompt's `ObjectText` names the trait | **107/1** | **69/2** | 12 distinct door records, not 1 |
| M2 respawn offset halved | **106/2** | **70/1** | the clear-band assertion + the warning |
| M2′ halved AND `Section.check` silenced | **107/1** | **70/1** | the clear-band assertion alone |
| M5 lane pool `max` → `min` | **107/1** | **70/1** | the seated-count assertion |
| CONTROL A door light `Brightness` 2.2 → 3.4 | 108/0 | 71/0 | correctly invisible |
| CONTROL B `Config.World.RespawnLift` 4 → 7 | 108/0 | 71/0 | correctly invisible |

**The controls, and why these two.** Control A is REVIEW-3's own control and it is now the sharper
of the two, because `Brightness` is a field the new door record *reads*: it changes every door
visibly and must still be invisible, because it does not distinguish one door from another. Without
it, "102 doors → 1 record" could be satisfied by a record that reads nothing at all. Control B
moves the height a respawning player is dropped from — a real change to the world that no assertion
in either repo claims to see — and it is the control for the clear-band assertion specifically,
which is horizontal and must not notice a vertical change. Both stayed at baseline on all eight
suites.

Note what L3 and L4 say: the leak renamed to `Tk`, and the leak moved onto a BillboardGui three
levels down, are each caught **twice** — once on the unread fork and once on the read one, because
the read inventory is asserted exactly too. "Nothing crosses the wire" is satisfied just as well by
a server that never writes the inscription at all, and that would be a game with no inscription
rather than a secret one.

---

## What I could NOT close

### 1. The game has still never been opened in Roblox Studio or played by a human

Unchanged from REVIEW-2, and the reason the verdict is still BLOCK. Every claim above, mine
included, is made by the luau CLI and by an emulator whose `Workspace:Raycast` raises on purpose.
Concretely still unmeasured, and now with two more:

* whether a Humanoid actually lands on the 1.00-stud clear band while moving, and whether the real
  collision hull is the 4 studs `CharacterHalfWidth = 2` assumes;
* whether a **1.1-second hold reads as deliberate or as tedious** — the number is derived from a
  time model, and no model can tell you whether a player will do it ten times;
* whether the read prompt on `R` and the door prompts on `E` are legible together on a phone, where
  both render as tap targets and neither shows a key;
* the three `AutomaticCanvasSize` ScrollingFrames, and ~230 parts per tower × 24 lanes.

`hudcheck.luau` is still not wired into any gate in this repo.

### 2. ~~`check_forktower.luau`'s two weak assertions~~ — CLOSED in the fourth pass

Both are fixed in place, in `robloxemu/check_forktower.luau`: the bare non-overlap test is now the
clear-band midpoint test, and `seated > 0` is now `seated == min(present, max(MaxLanes,
MaxPlayers))`. M2 and M5 are each killed by that file on its own — see the fourth-pass section
above for the red, the numbers and the controls. `tests/world.check.luau` keeps its own copies, so
neither file is the only thing that can see either defect.

### 3. ~~The fork's own data replicates, so an exploiter reads for free~~ — CLOSED in the fourth pass

`TellKind`, `RuleInverted` and `Marked` are written by `dressFork` and removed outright while a fork
is unread. What crosses the wire is enumerated and asserted against an exact list; every unread door
in a six-player run renders one identical record. Ten mutations, including the same leak renamed and
the same leak relocated onto a BillboardGui, are each caught; two controls stayed invisible. Details
above.

### 4. NEW — `PromptButtonHoldBegan` replicating to the server is an engine assumption

**Nothing in this repo has measured it and this pass did not try.** `check_forktower.luau` and
`world.check.luau` both fire it themselves on an emulated `ProximityPrompt`, which proves the
server's handler is wired up and proves nothing at all about the engine.

**The assumption, exactly.** `src/server/Main.server.luau` connects
`readPrompt.PromptButtonHoldBegan` on the SERVER and stores `clock()` in `lane.readHoldAt[level]`.
`onReadInscription` then charges `ReadSeconds - (clock() - began)`. Roblox documents `PromptShown` /
`PromptHidden` as client-only and does **not** so mark `PromptButtonHoldBegan`, so it should reach
the server — but "the docs do not say it is client-only" is an inference, not a measurement.

**What to watch in Studio, and what it looks like either way.** Hold LES on a fork pad for the full
bar and time the gap between the bar filling and the doors lighting up.

* *assumption holds* — `began` is set, `remaining <= 0` when `Triggered` arrives, the read completes
  on the spot, and the player sees the doors dress the instant the bar fills. Total ≈ **1.1 s**.
* *assumption fails* — `began` is nil, `remaining` is the full `Config.Fork.ReadSeconds`, and the
  server starts a fresh `task.delay(1.1)` **after** the client's own 1.1 s hold has already
  finished. The player sees the bar fill, then a `Leser innskripsjonen … (1.1 s)` toast, then a
  second of nothing. Total ≈ **2.2 s**.

**It fails in the safe direction.** Too expensive, never free: the fallback is the path an exploiter
firing the prompt directly already takes, so the 1.1 s is charged on the server's clock either way
and the break-even measurement is not invalidated. It is a feel regression, not a break, and the
game is still correct while it is broken. **Do not "fix" it by trusting the client's hold** — that
is the one change that would make it fail open.

If it turns out not to replicate, the repair is to make the honest path start the clock from
something that does: an explicit `RemoteEvent` fired by the client when the hold begins, rate-limited
and still only ever used to make the read *cheaper by at most the time already elapsed*, never to
skip it. Until somebody has stood on a pad in Studio, treat 1.1 s as the intended cost and 2.2 s as
the shipping risk.

### 5. Unchanged from the earlier passes

`Config.Passes` is read by nothing and `profile.passes` is loaded and saved and never consulted;
there is not one Sound in `src/`; `hz.kind` is written to an attribute and all four kinds render as
the same red neon cube; choices still do not narrow the next fork; there is still exactly one shape
of trap; `Config.Limits.ArmSkipCooldown` is still asserted by nothing; the clock still falls back to
the deprecated `tick()`; lane count at large `MaxPlayers` is now *tested* at 40 but the geometry out
at 4400 studs is still unexamined for streaming and float precision.

---

## A note on the order this was done in, because it matters

The Section clear-band assertion was written first and **watched fail** against untouched source —
the red is quoted above with its numbers. The rest of the third pass was not done in that order: the
A+B mechanic, the saved skip, the seating sweep and the per-hazard debounce were built, and then each
assertion was proved by **re-introducing the exact defect it claims to catch** and quoting the
failure. That is the evidence in the mutation table, and it is stronger evidence about the
assertions than "it was red before" would have been — but it is not test-first, and calling it that
would be a lie about how the work was done.

The **fourth pass** was test-first, and here is the order, because it is the part that is checkable.
The wire enumeration went into `check_forktower.luau` before a line of `Main.server.luau` changed,
and it was run against untouched source:

```
    ON THE WIRE, unexpected: Door_L_S [Part] :: Level,Marked,Signs,Slot
    ON THE WIRE, unexpected: ForkPad_L [Part] :: Level,RuleInverted,TellKind
    MISSING from the wire: Door_L_S [Part] :: Level,Signs,Slot
    MISSING from the wire: ForkPad_L [Part] :: Level
FAIL: an unread fork puts NOTHING on the wire that names the tell, the rule or the marked door
fork tower: 100 passed, 1 failed
```

One failure, naming the three attributes. Then `dressFork` changed and it went green. The two weak
assertions were done the other way round — the mutation first, then the assertion strengthened while
the mutation was still applied, so the new line was watched go red before the source was restored.
Both reds are quoted above with their numbers, and both were re-run in the full sweep afterwards
from a verified-clean tree.
