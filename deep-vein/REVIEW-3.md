# Deep Vein — answering REVIEW-2

**Verdict on the work: 7 of REVIEW-2's 8 open findings closed outright, all 3 of its regressions
closed, and 1 defect neither review found. The eighth finding is a bundle of four: two of them
(no SpawnLocation, the hard-coded surface column) are closed, and two (no unload, nothing has ever
been rendered) are NOT — they are now measured and bounded instead of unknown.**

**The repo does not go fully green.** `robloxemu/check_deepvein.luau` reports 115 passed / 1
failed, and that one assertion demands a defect: putting the coplanar surface deck back turns that
file green and this game's own gate red. robloxemu is read-only from this seat; the one-line patch
is at the bottom of this file.

Third pass, 2026-09-10. Every number below is the output of a command run against this tree, not
a reading. Where a fix could be mutated away, it was: the sweep table is at the bottom.

## Gate totals, before and after

| gate | REVIEW-2 baseline | now |
|---|---|---|
| `tests/Ore.spec.luau` | 1272 / 0 | **1272 / 0** |
| `tests/Mine.spec.luau` | 100 / 0 | **135 / 0** |
| `tests/Economy.spec.luau` | 122 / 0 | **131 / 0** |
| `tests/Prestige.spec.luau` | 117 / 0 | **220 / 0** |
| `tests/Responsive.spec.luau` | 70 / 0 | **70 / 0** |
| unit total | 1681 / 0 | **1828 / 0** |
| `tests/walk.luau` (new, ours) | — | **73 / 0** |
| `robloxemu/check_deepvein.luau` | 116 / 0 | **115 / 1** — see "not closed", below |

`luau-compile --binary` clean on all 10 sources. `luau-analyze` emits 444 diagnostics, every one
of them an `Unknown global`/`Unknown type` for a Roblox name (`game`, `Instance`, `UDim2`,
`Player`, `BasePart`, `Trail`, …) — the same noise floor REVIEW-2 measured.

## The thing neither review found

**THE REWARD GRADIENT INVERTED BELOW LAYER 40. Every rebirth past the fourth bought a mine that
paid LESS per swing than the one before it.** Block hit points grew by `HardnessPerLayer` for
ever, while the ore weights clamp at `MaxWeight` a few dozen layers down — so past the point where
the world stops getting richer, each extra layer was strictly worse. README and CLAUDE.md both
asserted the opposite ("deeper always pays more per swing") and nothing measured it.

**Measurement.** Expected ore value per expected hit point, over the real weight table and the
real hardness curve, at the shipped numbers: layer 1 `0.0804`, layer 14 `0.5383`, **peak 1.2065 at
layer 40**, layer 100 `0.8166`, layer 200 `0.4592`, **layer 312 `0.3085`** — a 3.9x decline across
exactly the range the last twenty rebirths open up. Since `Mine.maxLayer(cfg, 24) = 312`, this was
the entire late game.

**Fix.** `Config.Mine.HardnessCapLayer = 40`, honoured in `Mine.hardnessAt`: the ramp stops where
the weights finish saturating. Same measurement after: layer 312 `0.9713` against a best-anywhere
of `1.0023`, and the worst layer in the game pays 89.8% of the best layer above it (layer 40, a
sawtooth from flooring hit points to whole numbers). `Mine.spec` walks all 312 layers and fails
below 85%; the control (an uncapped ramp) measures 19.5% and fails.

## REVIEW-2's "still open" list (8)

### 1. The currency printer — CLOSED. The cave is now saved.

`opened` was per-session, so a rejoining player found every cell but the centre elevator column
standing again, ore included. Fixed by saving it: `Mine.packOpened` / `Mine.unpackOpened` /
`Mine.faces` / `Mine.deepestOpened` / `Mine.parseKey`, one bit per cell of the box, six bits per
character over a URL-safe base64 alphabet, trailing zeros trimmed.

**Measurements.**
- A rebirth-0 shaft dug out **completely** (1 225 cells) packs to **336 characters** and unpacks
  to exactly 1 225 cells (`Mine.spec`).
- The worst case the game can produce — rebirth 24, wall at layer 312, 15 337 cells — packs to
  **4 224 characters** and rebuilds **10 097 faces**, i.e. 158 frames at `PartsPerFrame = 64`.
  Asserted as a bound in `Mine.spec` so it cannot grow quietly.
- End to end in the emulator (`tests/walk.luau`): a player mines the 8 ore cells exposed in the
  mouth plus a 3-cell side tunnel, sells for **$48**, **leaves, rejoins**. Verbatim:
  `RELOG: after leaving and rejoining, 0 of 11 mined cells are standing again; cash $48 came back`.
  The sell pad then pays `0` and toasts "Nothing to sell"; `runEarned` comes back unchanged; and
  the three side-tunnel cells (`4:1:6`, `4:2:6`, `3:2:6` — not on the elevator column, so gone
  entirely under the old column-only restore) are still empty.
- The server prints what it restored: `restored 88 dug cells for Relog (64 faces up front, 168
  queued)`.

Two mutations kill it: dropping `openedBits` from the save, and making the restore a no-op. Both
turn `tests/walk.luau` red and leave every other gate green.

The rebirth-flush trap is guarded and commented: `openedBitsOf` refuses to pack while
`worlds[plr].rebirths ~= profile.rebirths`, because the atomic rebirth flush calls `saveProfile`
while the OLD world is still live and `p.rebirths` already names the new one. Removing that guard
turns both headless gates red (the new cave arrives pre-drilled).

### 2. The shop can spend a player out of the rebirth — CLOSED. The gate reads earnings.

`Economy.sell` now banks `profile.runEarned` as well as `totalCash`; `Prestige.canRebirth` and
`Prestige.progress` read it; `Prestige.apply` zeroes it. Earnings only go up and spending does not
touch them, so no purchase sequence can move the gate.

**Measurement.** `Prestige.spec` reproduces the review's exact trace against the real modules:
harvest every ore cell of the rebirth-0 shaft through `Economy.addOre`/`Economy.sell` — **287 ore
cells, $20 390 earned against a $6 473 price** — then buy everything affordable in the order the
HUD offers it until nothing is affordable: **10 purchases, $78 left in the wallet**. That wallet
is far below the requirement (asserted as a CONTROL, because it is precisely the old gate's dead
end) and `Prestige.canRebirth` still returns `true, "ok"`, with `runEarned` unmoved.

Migration: a profile written before `runEarned` existed loads as `max(runEarned, cash)`. Cash in
hand is always a lower bound on this run's earnings — the only source of cash is a sale, a sale
banks the same earnings, and rebirth zeroes both — and `Economy.spec` asserts that invariant over
60 mixed sells and buys. Without it, every returning player's rebirth progress would have been
deleted on the first login after this change.

The HUD says the right thing now — `Rebirth 0 (x1.0) · earn $6473 this run · $<earned> so far`
rather than a "need $6473" that a player holding $6 500 would be refused against, and rather than a
target that visibly falls every time they buy a pickaxe.

### 3. 46% of the rebirth-0 shaft in four obsidian cells — CLOSED at 15.7%.

Retuned: `MinLayer` `{1,4,9,14,19}` → `{1,3,6,10,14}`, `BaseWeight`
`{.150,.070,.030,.020,.008}` → `{.150,.100,.060,.036,.018}`, `Value`
`{6,20,80,340,1400}` → `{6,20,70,240,800}`.

**Census of the rebirth-0 shaft, before → after** (`Mine.spec` prints it):

| | before | after |
|---|---|---|
| rock cells | 842 | 842 |
| Copper / Iron / Gold / Diamond / Obsidian | 108 / 69 / 27 / 7 / 4 | **110 / 91 / 49 / 27 / 10** |
| total ore value | $12 168 | **$20 390** |
| richest four cells | $5 600 (**46.0%**) | $3 200 (**15.7%**) |
| cumulative value crosses the price at layer | 18 of 24 | **15 of 24** |

The census floor moved from `>= 3` to `>= 10` per tier (a margin of one cell is not a margin), and
a new assertion caps the richest four cells at 25% of the shaft. Its control — a config where the
whole shaft's value is one rare tier — measures above 25% and fails, so the assertion is not
vacuous. Peak total ore weight is 0.452, so stone is still the majority of every layer.

### 4. The middle of the ladder is skippable — CLOSED. The price is computed from the world.

The price is no longer a curve fitted to the world; it *is* the world.
`Prestige.requirement(cfg, Ore, r) = floor(PriceFraction * shaftOre(cfg, Ore, r) * multiplier(r))`,
where `shaftOre` integrates the ore table over every layer the rebirth-`r` wall exposes — 1 560
multiply-adds at the deepest wall, cheap enough for a state push.

**Measurement.** Ratio of what a real seeded shaft holds to what its rebirth costs, censused at
all 25 levels (`Prestige.spec` prints the extremes):

| | shipped | REVIEW-2's round | now |
|---|---|---|---|
| tightest | 0.196x (r0) | 3.48x (r0) | **2.88x (r14)** |
| loosest | 0.38x | **26.97x (r6)** | **3.54x (r1)** |
| spread | — | 7.8x | **1.23x** |

Both sides are now asserted (`>= 2` and `<= 5`) with a control for each direction. A geometric
curve cannot do this, which is why the SHAPE changed rather than the constants: the world's value
triples between the first two rebirths and then flattens as the ore weights saturate. Sweeping
`RequirementGrowth` across 1.00-1.40 with `BaseRequirement` re-fitted at every step, the best
geometric available leaves a **7.8x** spread on the old ore table and **4.4x** on the new one,
against **1.23x** for a price computed from the table itself.

The old CONTROL ("a balance pass on ore values must not move the requirement") was exactly
backwards under the new design and has been replaced by its opposite: the requirement must be
unchanged by the seed, the carving threshold and the hardness curve (asserted at 13 levels), must
double when every ore price doubles, and must rise when the wall moves faster.

### 5. The deck's landing footprint is asserted nowhere — CLOSED.

`tests/walk.luau` asserts the deck covers at least 85% of the cell on X and Z and no more than
100%. The review's surviving mutations now die: `deck.Size = Vector3.new(1, 1, 1)` turns the walk
gate red (and, as the review found, leaves everything in `robloxemu/` green).

### 6. `pumping` is one boolean with no pcall — CLOSED, and reached by a test.

Two changes, covering different failures:
- `drainBuild` pcalls **each cell**, so a Part that will not build costs that Part and nothing
  else — the pre-pump behaviour, where an error cost one swing.
- `pumpBuild` guards on a **lease** (`pumpLease = tick() + 1`, renewed every frame by the running
  pump) instead of a latch. A pump that dies for any reason at all stops renewing and the next
  enqueue takes over a second later.

The review could not reach an error through a legitimate path. This does, from outside the game:
`tests/walk.luau` wraps `Instance.new` before the server ever runs and fails it once.

**Measurements.** With one Part poisoned mid-dig: the server warns
`[DeepVein] could not build cell 4:2:4: injected: the Part factory failed`, the miner keeps digging
(**6 of the 8 layers aimed at — the other two were already open air**), and **429 further parts**
are built around the missing one. Then the
harder case, which no pcall can cover — the error **handler** failing: `warn` is poisoned as well,
so the error escapes the per-cell pcall and kills the pump thread outright (visible as
`[scheduler] coroutine error: injected: warn itself failed`). The world starts growing again
within a second of further swinging. Reverting the lease to a latch (`if pumpLease ~= 0 then
return end`) turns the walk gate red on exactly that assertion.

A note on why the wrapper is installed before `h:tryRun` rather than at the point of use: Luau
caches a chunk's global lookups on first execution, so a swap made after the server has already
built a Part is a swap the server never sees. Measured: swapping mid-run intercepted **0 of 109**
Parts; swapping before the first run intercepted **200 of 200**.

### 7. The surface test is bound to a hard-coded column — CLOSED.

`buildSurfaceDeck` publishes `deck:SetAttribute("LandingCell", Mine.key(c, 1, SPAWN_CELL_Z))`, and
`tests/walk.luau` digs the column that attribute names, after first asserting that SURFACE really
lands the miner over that cell. Moving `SPAWN_CELL_Z` moves the test with it. (The frozen check
still hard-codes `z = 2`; that is the second half of what makes REVIEW-2's control mutation C2 go
red there.)

### 8. The confirmed-still-open four — two closed, two still open.

- **No SpawnLocation** — CLOSED. `workspace.MinersRest`, an anchored neutral 16x1x16
  `SpawnLocation` at `(-80, -0.5, 0)`: west of shaft 0, clear of every shaft's 54-stud footprint
  (asserted by overlap test against every block of every shaft), parented to the workspace rather
  than to `Shafts`, which is per-player and gets destroyed. Deleting the call turns the walk gate
  red on `the world has a SpawnLocation…` and leaves the frozen check where it was.
- **No unload of parts far above the player** — STILL OPEN, but now bounded and asserted: the
  worst case in the game is 10 097 Parts and 4 224 saved characters, and `Mine.spec` fails if
  either grows past 12 000 / 6 000. Saving the cave made this worse, not better: a fully excavated
  deep shaft is now rebuilt on every join, for ever.
- **Reveal is triggered only by a break, never by movement** — unchanged, with 1.4x headroom on
  `RevealBudget` (worst connected void 1 137 against 1 600). Not a defect; recorded.
- **Nothing has ever been rendered** — STILL OPEN and unchanged. No Studio session exists. Nothing
  in this round can speak to materials, colour, lighting, camera, click reach, or whether a Roblox
  humanoid can walk and jump on a 6-stud grid of cubes.

## REVIEW-2's "broken by the fixes" list (3)

### The deck is coplanar and volume-overlapping with the rock it sits inside — CLOSED.

Three changes, because the review named three symptoms:
- **one stud lower** (`-s/2 - 1.5` instead of `-s/2 - 0.5`), so the deck's top face is at
  `y = -1.00` and shares no plane with the rock's top face at `y = 0`;
- **inset to 90% of the cell** on X and Z, so the four side faces are not coplanar either once the
  neighbouring floor is dug;
- **`CanQuery = false`**, so a mouse ray cannot resolve to it at all and a click on the spawn cell
  can never be a silent no-op.

**Measurement.** `tests/walk.luau` enumerates all six face planes of the deck and of every block
whose bounding box overlaps it: **0 shared planes**. Then it digs the landing column out and
presses SURFACE, verbatim:

```
  SURFACE: whole spawn column dug out (16 cells), landing y=4.00,
           ground SurfaceDeck_4001 top y=-1.00, drop 5.00 studs
```

— and that ground carries no ClickDetector, inside the 8-stud bar. Three mutations kill it (flush
again, 1x1 pillar, `CanQuery = true`).

The README claimed a rule the code did not implement ("the surface deck blocks one cell … they
have to step one cell over"). Rather than making the cell unmineable, the README now describes
what the code does: you *can* dig the cell you spawn on, and the deck is the ledge left standing.

### A reachable permanent dead end — CLOSED by the two fixes above.

The soft-lock needed both halves: a wallet-based gate and a cave that refills on relog. The gate
is on monotone earnings and the cave does not refill; `Prestige.spec` runs the exact purchase
sequence and `tests/walk.luau` runs the exact leave/rejoin.

### The surviving mutation that showed dead code — CLOSED by deletion.

`drainBuild`'s `and not opened[plr][s.key]` re-check is gone, and the comment now says what the
remaining check is for (two reveals in one frame queueing the same face). What protects against a
real regression is the symptom, asserted from outside: after the walk digs a column top to bottom,
`tests/walk.luau` checks every cell of it and requires **0 rebuilt**.

## The walk — what actually happened when somebody played it

`tests/walk.luau` joins, spawns, and plays: pick the deepest exposed ore or rock, swing at it,
haul up and sell when the bag is full, buy whatever is affordable, descend, repeat, and take the
rebirth when it becomes available. Verbatim output:

```
  SURFACE: whole spawn column dug out (16 cells), landing y=4.00,
           ground SurfaceDeck_4001 top y=-1.00, drop 5.00 studs
  PUMP: one Part poisoned mid-dig -> 6 of 8 layers still dug, 429 further parts built
        around the missing one
  PUMP: pump thread killed by a failing warn -> world grew again: true
  RELOG: mined 11 cells out before leaving
  RELOG: after leaving and rejoining, 0 of 11 mined cells are standing again; cash $48 came back
  WALK: 765 swings, 195 blocks broken, 4 surface trips, deepest layer 24, $10016 earned,
        rebirth needs $6473
```

So: the first rebirth costs about **195 of a 842-block cave** and four trips to the surface, the
walker reached the depth wall, and the button at the end of it worked — rebirth 1 granted, cash
and earnings wiped, wall moved to 216 studs, multiplier x1.8 live, and a fresh 113-block mouth
built from a new seed. Leaving and rejoining after that rebirth gives a clean 113-block mouth
again, not the old cave's holes.

Things the walk found that no unit test did, and that are fixed: the depth wall carries a
ClickDetector on purpose, so a "deepest clickable block" policy hammers bedrock for ever (first
run: **6 000 swings, 0 blocks broken**). That is a thing a player can do too; the toast is what
stops them, and it fires.

## Mutation sweep

15 mutations, each applied alone to `src/`, with `wrap.py` re-run and all six gates re-measured.

| mutation | killed by |
|---|---|
| S1 the save drops the cave | walk |
| S2 the rejoin never restores it | walk |
| S3 deck shrinks to a 1x1 pillar | walk |
| S4 deck top back flush with the floor | walk (**frozen check goes GREEN**) |
| S5 deck is queryable again | walk |
| S6 no per-cell pcall in the drain | walk |
| S7 pump guard is a permanent latch again | walk |
| S8 no SpawnLocation | walk |
| S9 rebirth saves the old cave into the new one | walk, frozen |
| S10 a sale banks no earnings | Economy, Prestige, walk |
| S11 the rebirth gate reads the wallet again | Prestige |
| S12 hardness ramp uncapped again | Mine |
| S13 `Mine.faces` forgets a cell was dug out | Mine, walk |
| CONTROL deck colour | **nothing (correct)** |
| CONTROL autosave period 20 → 17 | **nothing (correct)** |

13 of 13 real defects killed; both controls survived, so the harness can still tell a change from
no change.

Two notes on how the sweep itself was checked, because a mutation that fails to COMPILE reports as
caught by everything and proves nothing. S8's first form deleted the text `buildSpawnPad()` and hit
the function's own declaration line, so the game did not parse; it was rewritten to delete only the
call, re-run, and the corrected result is the one in the table (walk red on
`the world has a SpawnLocation…`, frozen unchanged at its one stale failure). S9 was re-run for the
same reason and fails on real assertions rather than a parse error: without the rebirth guard the
new cave comes up as **984 parts** carrying the old cave's holes, and `this run's depth is wiped`
reports 144.

## What is NOT closed

### `robloxemu/check_deepvein.luau` reports 1 failure, and that assertion demands the defect.

```
FAIL: …with its top flush with the mouth floor -> got -1, want 0
```

That is `eq(deck.Position.Y + deck.Size.Y / 2, 0, ...)` at check_deepvein.luau:178 — the assertion
REVIEW-2 identified as "what pins the defect in place". Mutation S4 proves it directly: putting the
coplanar deck back turns that file **fully green** and turns our own gate red. I could not fix it,
because robloxemu is read-only from this seat. The patch is one line:

```lua
-- was: eq(deck.Position.Y + deck.Size.Y / 2, 0, "…with its top flush with the mouth floor")
truthy(deck.Position.Y + deck.Size.Y / 2 < 0, "…with its top BELOW the mouth floor, not in the
    same plane as the rock it is buried in")
```

Two more lines in that file are stale for the same reason and will bite the next person who moves
the spawn: `digColumn(surfer, SURF, 5, 2, 24)` hard-codes `z = 2` where the game now publishes
`deck:GetAttribute("LandingCell")`.

Everything else in that file passes, including the 115-part mouth, the 50 ClickDetectors, the
one-frame part budget, the veteran's restored column, the stranger who cannot mine your shaft, and
the rebirth.

### Nothing has been rendered, and nobody has played it.

Unchanged from REVIEW-2 and unchangeable from here: no material, colour, lighting, camera, click
reach, or humanoid-on-a-6-stud-grid observation exists. `tests/walk.luau` fires ClickDetectors
directly and never checks `MaxActivationDistance`, so "can a player actually reach that block" is
still an open question in exactly the way REVIEW-2 said. The next thing that should happen to this
game is a human opening it in Studio.

### Smaller things left deliberately

- **A failed Part leaves a hole.** When the per-cell pcall catches a build failure the cell is
  skipped and `cellParts` is not marked, so a later reveal that re-collects the face will queue it
  again — but nothing forces that reveal. Bounded to one cell per error, and no legitimate path
  produces one.
- **`Prestige.requirement` duplicates `Mine.maxLayer`'s arithmetic** so the module can depend on
  `Ore` alone. `Prestige.spec` asserts the two agree at all 26 rebirth counts.
- **Two pumps can briefly overlap** if a single drain takes longer than the lease. Harmless: they
  share one queue, `head` only moves forward, and a cell that already has a Part is skipped.

## Addendum, 2026-09-10 — the frozen check is no longer frozen, and it now bites

`robloxemu/check_deepvein.luau` was read-only from the seat that wrote this review, which is why it
was left at 115/1 with one assertion demanding the defect. Both repairs are applied:

- `eq(deck.Position.Y + deck.Size.Y / 2, 0, ...)` at line 178 is now
  `truthy(deck.Position.Y + deck.Size.Y / 2 < 0, ...)`. The old form pinned the coplanar deck in
  place: restoring the defect turned that file green and this game's gate red.
- `digColumn(surfer, SURF, 5, 2, 24)` no longer hard-codes the spawn cell. It reads
  `LandingCell` off the deck, asserts the attribute exists and parses as `x:y:z`, and digs that.
  The hard-coded form would have gone on passing while digging an untouched column somewhere else
  the moment the spawn moved.

**`check_deepvein.luau` now reports 119 passed, 0 failed.**

Both repairs were mutation-tested rather than trusted:

| what was done to the game | check |
|---|---|
| deck put back coplanar (`-s/2 - 0.5`, top flush at the mouth floor) | **118 / 1 — KILLED** |
| `LandingCell` publishes `SPAWN_CELL_Z + 3`, a column nobody stands on | **118 / 1 — KILLED** |
| CONTROL: deck colour changed to red | 119 / 0 — correctly unnoticed |

`src/server/Main.server.luau` restored and sha256-verified byte-identical after the sweep.

Still open from this review, unchanged: no unload (a fully excavated deep shaft is 10 097 Parts
rebuilt on every join — bounded and asserted, not fixed), and nothing has ever been rendered.
