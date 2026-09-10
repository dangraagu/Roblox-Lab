# Deep Vein — the unload

**REVIEW-3 left one shipping blocker that was not "nobody has opened Studio": there is no unload,
a fully excavated deep shaft is 10 097 Parts, and every one of them is rebuilt on every join.
It is fixed. The worst state this game can reach went from 19 115 Parts to 1 124, the state
REVIEW-3 actually named went from 10 097 to 5, and the join cost went from 158 frames to 18.**

Fourth pass, 2026-09-10. Every number below is the output of a command run against this tree.
The gates: unit **1866 / 0** (Ore 1272, Mine 173, Economy 131, Prestige 220, Responsive 70),
`tests/walk.luau` **116 / 0**, `robloxemu/check_deepvein.luau` **136 / 0**. `luau-compile --binary`
clean on all 10 sources; `luau-analyze` emits 460 diagnostics and **0** of them are anything but an
`Unknown global` / `Unknown type` for a Roblox name.

---

## 1. The measurement, before anything was changed

`Mine.faces` over a seeded world, classified by what the Part actually is. Every figure is per
player, per shaft.

| state | Parts | rock | ore | bedrock |
|---|---:|---:|---:|---:|
| r0 fresh join (the mouth) | 113 | 41 | 8 | 64 (56.6%) |
| r0 dig straight down to the wall | 1 080 | 387 | 209 | 484 (44.8%) |
| r0 fully excavated | 881 | 0 | 0 | **881 (100%)** |
| r24 fresh join | 113 | 46 | 3 | 64 (56.6%) |
| r24 dig straight down to the wall | **11 960** | 4 142 | 2 772 | 5 046 (42.2%) |
| r24 fully excavated (REVIEW-3's figure) | **10 097** | 0 | 0 | **10 097 (100%)** |
| r24 lattice dig (adversarial) | **19 115** | 5 406 | 3 612 | 10 097 (52.8%) |
| r24 ceiling: every solid cell in the box | 20 919 | | | |

Three things fall out of that table, and they decide the whole fix.

**(a) The 10 097 is 100% bedrock.** 10 048 of it is the ring (32 cells per layer × 314 layers) and
49 is the floor. Excavate a shaft completely and there is no rock left to have a face, so *culling
the interior of solid rock saves exactly nothing here* — the reveal already only builds exposed
faces, and the exposed set of a finished shaft is the box.

**(b) 10 097 is not the worst case, and the bound REVIEW-3 asserted was measured off a
non-maximum.** `Mine.spec` asserted `#faces <= 12000` against the fully excavated shaft. But a
lattice dig — every other cell on each axis, which is what a strip mine is — puts an opened cell
within reach of every solid cell in the box and exposes **19 115**. Even the ordinary "dig straight
down to the wall" reaches **11 960**, 40 Parts under a bound that was supposed to have headroom.
That assertion is replaced (§7c/7d of `Mine.spec`).

**(c) 47% of the true worst case is rock and ore**, which no amount of bedrock cleverness touches.

Two more numbers set the shape of the answer:

- **A depth window is nearly free.** At the adversarial maximum, the widest ±16-layer window
  anywhere in the shaft holds **1 080** rock+ore faces out of 9 018 — 12%.
- **The mine has no sun.** `Fx.Presets.Horror` sets `ClockTime = 0.2`; the only light underground
  is the head lamp, and the best lamp money can buy in this game is
  `BaseRadius 26 + MaxLevel 8 × PerLevel 6 = ` **74 studs**. 16 layers is **96 studs**.

---

## 2. The options, and why this one

| option | what it would buy | why not / why yes |
|---|---|---|
| **Cull the interior of solid rock** | **0 Parts.** Measured. | `Mine.reveal`/`Mine.faces` already build only exposed faces. A fully surrounded cell has never had a Part in this game. Dead on arrival. |
| **Pool and reuse Parts** | 0 resident Parts. | Cuts `Instance.new` churn, not the count. The complaint is a client *rendering* ten thousand Parts, and pooling leaves ten thousand parented. |
| **`workspace.StreamingEnabled`** | Client-side only. | The engine's own answer, one project-file property — and untestable from here (robloxemu does not model streaming), so it would ship as an unmeasured claim. It also leaves the **server** holding 11 960 instances *per player*: 30 players in one server is 358 800 instances to hold and replicate. Recommended as a later belt-and-braces once a human has it in Studio, not as the fix. |
| **Merge the bedrock box into slabs** | **10 097 → 5.** Exact. | The ring is an indestructible rectangular tube and the floor is a flat slab. Same volume, same collision, same colour, no policy, nothing to tune, and it cannot regress because the box does not move. It is the entire fully-excavated case and 52.8% of the adversarial one. |
| **Stream rock faces by depth** | **9 018 → 1 080** at the adversarial max. | The only thing that bounds the half a bedrock trick cannot reach. Cheap here because the shaft is one-dimensional: a 9×9 box, so "distance from the player" is "distance in layers". |

**Picked: the last two together**, because they cover disjoint halves of the number and neither
alone is enough — the slabs do nothing for a half-dug shaft (11 960 → 6 918) and the band does
nothing about spending half of every window on a featureless wall (1 080 → 2 136).

Why it beats streaming alone *for this game specifically*: the box is the one part of the world
that is provably static — `Mine.kindAt` returns `bedrock` for those cells at every seed, every
rebirth, for ever — so paying a per-frame streaming policy for it is paying for a decision that was
made at compile time.

Why it beats slabs alone: a player who tunnels rather than excavates never removes the rock faces,
and rock faces are 47% of the worst case.

### The band is sized by the light, not by taste

`Config.Mine.StreamLayers = 16` — 96 studs, a third further than the 74-stud maximum lamp. Nothing
a player could have seen is ever missing. `StreamHysteresis = 4` keeps a miner stepping down one
cell from re-deriving the face set; `StreamPeriod = 0.35` is the sweep cadence.

---

## 3. Before and after, in the same units as the 10 097

Parts held by one shaft. "after" is the worst window anywhere in that state, plus the five slabs.

| state | before | after | cut |
|---|---:|---:|---:|
| r0 fresh join | 113 | 54 | 2.1x |
| r0 dig to the wall | 1 080 | 601 | 1.8x |
| r0 fully excavated | 881 | **5** | 176x |
| r24 fresh join | 113 | 54 | 2.1x |
| r24 dig to the wall | 11 960 | **906** | 13.2x |
| **r24 fully excavated (REVIEW-3's 10 097)** | **10 097** | **5** | **2019x** |
| **r24 lattice (the true maximum)** | **19 115** | **1 124** | **17x** |

- **Join cost: 158 frames → 18** at `PartsPerFrame = 64` (2.6 s → 0.3 s at 60 fps), worst case in
  the game rather than worst case of the excavated shaft.
- **The whole shaft is now bounded by a constant**, not by the box: no seed, no rebirth, no lucky
  void and no amount of digging can push it past a band.

Observed in the built world rather than computed, from `tests/walk.luau` and
`check_deepvein.luau`:

```
  Shaft_0 on join: 56 parts (41 rock, 8 ore, 0 bedrock cubes, 5 shell slabs, 1 pad), 51 clickdetectors
  STREAM: 120-layer column, miner at the mouth -> 143 cell parts + 5 slabs, layers 1..17
  STREAM: after DESCEND            ->  92 cell parts + 5 slabs, layers 104..120
  STREAM: after SURFACE            -> 143 cell parts + 5 slabs, layers 1..17
  STREAM: walked (not teleported) to layer 40 -> 172 cell parts, layers 24..56
```

A fresh shaft was **115** Parts and is **56**. That veteran's 120-layer column un-banded is **821**
faces; the miner holds 143 of them at a time.

---

## 4. What it cost

- **A teleport has to build its own landing.** DESCEND aims at the deepest *opened* cell, which is
  empty by definition, and what holds the miner up is whatever is under it — which, in a streaming
  shaft, may not exist yet. `streamTo` moves the band and builds the landing **synchronously,
  before the CFrame is set**. It is narrowed to the 3×3 column under the miner rather than the
  whole two-layer band: the widest such column anywhere in the game measures **43 Parts**, inside
  one frame's 64. The whole band would be **202**, which is a three-frame hitch on every elevator
  press.
- **Damage has to survive an unload.** `setBand` keeps `cellHp` for a block a player is part-way
  through and drops it for an undamaged one, and `makeCellPart` honours it. Without that, walking
  away heals every half-broken block — a swing the player paid for and did not get.
- **A queued build has to re-check the band.** The pump drains a queue that may have been filled
  for a band the miner has since left. `drainBuild` drops those instead of building them one frame
  behind the unload that was supposed to prevent them.
- **Both headless gates now move the miner.** They used to fire ClickDetectors from wherever the
  character happened to be — REVIEW-3 listed `MaxActivationDistance` as something neither gate
  could see. They stand on the block first, which is what digging down is, and the walk reports the
  worst reach it used: **6.0 studs against `ReachStuds = 26`**. That is a side effect of the fix
  rather than the point of it, but it closes half of a named gap.
- **`RIM_MULT` is gone from the server.** The three-cell rim is `Config.Mine.RimCells`, honoured by
  `Mine.shell`, and asserted purely (the wall must stand proud of the mouth) instead of being a
  special case in the part factory.

## 5. What REVIEW-3 closed, re-verified

Nothing here is allowed to unpick the last round, and each of these is a live assertion:

- **The cave is still one bit per cell.** `Mine.packOpened` / `unpackOpened` / `faces` are
  unchanged in meaning; `faces` gained an optional band and returns the whole shaft when it is not
  given one, asserted directly (`faces() with no band is unchanged`). **The Parts were always
  derived from `opened`** — that is what made the restore possible in the first place — so
  unloading one forgets a rendering, not a dig. The walk proves it end to end: mine a cell at the
  bottom of a 120-layer shaft, ride to the surface (which unloads all of it), ride back down, and
  the cell is still mined.
- **A stranger still cannot mine your shaft.** `check_deepvein.luau`, unchanged, green.
- **`LandingCell` is still honest.** Both gates read it off the deck rather than hard-coding a
  column; unchanged, green.
- **The veteran's restored column still restores** — and now only the part of it the veteran is
  standing in. The check asserts the restore is real where they are, that nothing below their band
  is built, and that DESCEND brings the bottom with it.
- **The box is still sealed.** This is the invariant the slabs could most easily have lost.
  `Mine.spec` samples the centre and four corners of **every** bedrock cell of the box at rebirths
  0, 1 and 24 and requires each one to be inside a slab; then requires that **no** slab reaches
  into a cell a player is supposed to be able to dig. `tests/walk.luau` does the same from the
  built world, against all 800 ring cells of the real shaft.

---

## 6. Mutation sweep

14 mutations, each applied alone to `src/`, `wrap.py` re-run, all six gates re-measured, and
`src/` restored and **sha256-verified byte-identical** afterwards.

| mutation | killed by |
|---|---|
| M1 the band never unloads anything | walk (7 assertions) |
| M2 the band is ignored when building | walk |
| M3 bedrock cubes come back on top of the shell | walk, check |
| M4 a wall slab is one cell short | Mine |
| M5 the walls reach one cell further in | Mine, walk |
| M6 the rim is one cell tall again | Mine, walk, check |
| M7 the floor slab stays at rebirth 0's depth | Mine, walk |
| M8 a teleport builds nothing synchronously | walk |
| M9 damage is forgotten when a block unloads | walk |
| M10 the drain ignores the band | walk |
| M11 `faces()` ignores the band it was given | Mine |
| M12 the periodic sweep never runs | walk |
| **CONTROL** shell slab colour → red | **nothing (correct)** |
| **CONTROL** sweep period 0.35 → 0.30 | **nothing (correct)** |

12 of 12 real defects killed; both controls survived, so the harness can still tell a change from
no change.

**Four of those twelve survived the first run of the sweep, and that is the useful part of it.**
Each survivor was a missing assertion, not a harmless mutation:

- **M8** survived because the pump happens to build its first 64 Parts inside the caller's own
  frame, so "there was ground under the landing" can be luck rather than the guarantee `streamTo`
  makes. It is now asserted as the thing the pump *cannot* do: the **whole** 3×3 landing column is
  up in the landing frame **while the pump is still visibly behind**.
- **M12** survived because every band move in the gates came from a teleport, which moves the band
  explicitly. A player who walks or falls down their own open column moves it by *moving*, and only
  the sweep notices. The walk now walks down to layer 40 without touching the elevator.
- **M2/M10** survived twice. First because the periodic sweep tidies the spike away 0.35 s later,
  so a single measurement after the fact sees a clean world either way — the walk now samples the
  deepest built layer **every frame** for ten frames, so a one-frame spike cannot hide. Then
  because the test pressed DESCEND while the miner was *already* at the bottom, which queues
  nothing at all; it rides to the surface first.

---

## 7. The walk — what the runner experienced

`tests/walk.luau` plays the game with the miner standing where a player would have to stand.
Verbatim:

```
  SURFACE: whole spawn column dug out (16 cells), landing y=4.00,
           ground SurfaceDeck_4001 top y=-1.00, drop 5.00 studs
  PUMP: one Part poisoned mid-dig -> 6 of 8 layers still dug, 247 further parts built
        around the missing one
  PUMP: pump thread killed by a failing warn -> world grew again: true
  RELOG: mined 11 cells out before leaving
  RELOG: after leaving and rejoining, 0 of 11 mined cells are standing again; cash $48 came back
  STREAM: 120-layer column, miner at the mouth -> 143 cell parts + 5 slabs, layers 1..17
  STREAM: after DESCEND -> 92 cell parts + 5 slabs, layers 104..120
  STREAM: after SURFACE -> 143 cell parts + 5 slabs, layers 1..17
  STREAM: walked (not teleported) to layer 40 -> 172 cell parts, layers 24..56
  WALK: 772 swings, 195 blocks broken, 4 surface trips, deepest layer 24, $10016 earned,
        rebirth needs $6473
  WALK: peak 486 cell parts + 5 slabs held at once; worst swing reached 6.0 studs (ReachStuds 26)
```

**Part count at each stage of the loop.** Spawn **54** (49 cells + 5 slabs). Digging: peak **491**
across the whole run, against **1 080** for the same dig before this change and **11 960** for the
same dig at the deepest wall. Bag full → SURFACE → sell → shop → DESCEND: the band follows, and
DESCEND has its landing column up in the frame it lands. Rebirth: the old cave and its save are
thrown away and the new one is **49 cells + 5 slabs**, not 113 blocks.

The economics are unchanged by any of this — same 772 swings, same 195 blocks, same $10 016 against
a $6 473 price, same layer 24, same rebirth granted. That is the point: the miner sees the same
game and the renderer sees a twentieth of it.

---

## 8. What is still open

- **Nothing has been rendered, and nobody has played it.** Unchanged from REVIEW-2 and REVIEW-3 and
  unchangeable from here: no material, colour, lighting, camera or humanoid-on-a-6-stud-grid
  observation exists. **This is now the only remaining blocker.** The one new thing to look at in
  Studio is the four wall slabs: the two long ones are 54 × 165 × 6 studs at rebirth 0 and 54 × **1 893** × 6 at
  the deepest wall, and a single `Basalt` face that big may want a texture or a per-layer seam that
  6-stud cubes gave away for free.
- **A player who outruns the streamer while falling.** The band moves at `StreamPeriod` (0.35 s)
  and reaches 96 studs ahead. Roblox gravity is 196.2 studs/s² with no terminal velocity, so a
  1 800-stud free fall down a fully dug shaft ends up faster than the band can rebuild ledges in
  front of it. The floor and the walls are slabs and always present, so the fall always *ends*
  safely — but a rock ledge partway down could be fallen through. Not reachable in either gate (the
  emulator has no physics), and the fix if a human sees it is an asymmetric band, deeper below than
  above.
- **`workspace.StreamingEnabled` is not set.** With the server-side band the client already
  receives only a band's worth, so this is now an optimisation rather than a fix — but it is one
  line in `default.project.json` and worth measuring in Studio, where its interaction with
  ClickDetectors can actually be observed.
- **Two Parts of slack in `cellHp`.** A damaged block keeps its hit points across an unload for the
  life of the session, keyed by cell. Bounded by the number of cells the player has ever damaged
  and never released, which is at most the box (15 337 numbers) — a few hundred KB, and only for
  cells actually swung at. Deliberate: the alternative is healing blocks.
- **The three smaller things REVIEW-3 left deliberately** are unchanged: a failed Part leaves a hole
  until something re-reveals it, `Prestige.requirement` duplicates `Mine.maxLayer`'s arithmetic
  (asserted equal at all 26 levels), and two pumps can briefly overlap harmlessly.
