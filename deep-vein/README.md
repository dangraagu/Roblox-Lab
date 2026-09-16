# Deep Vein ⛏️ — Mining Simulator

Every dive drills through a genuinely procedural cave. Drop into your own shaft, swing at the
rock, break into voids nobody has seen before, haul the ore up, upgrade, and rebirth for a
permanent multiplier and a brand new cave.

Built from Game-Radar #3 (2026-09-09). Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/` and `anomaly-observatory/` — same stack: one CONFIG table, pure logic in
`src/shared` tested from the luau CLI, a server that owns every decision, a phone-first HUD.

---

## The loop

1. **Spawn in the mouth of your shaft** — a 7×7 open room at the surface, walled by bedrock that
   stands three cells proud of the ground so you cannot jump out of the mine.
2. **Click a block to swing at it.** Each block has hit points; your pickaxe has power. Break it
   and the faces behind it appear — including, sooner or later, a natural cave void that opens up
   all at once.
3. **Ore goes in your backpack** (copper from layer 1, iron from 3, gold from 6, diamond from 10
   and obsidian from 14 — every tier reachable, and findable in numbers, inside the rebirth-0
   depth wall at layer 24). Stone is real, minable and worth nothing.
4. **🛗 SURFACE + SELL** teleports you back to the mouth, onto an anchored deck that no
   swing can reach, and sells the haul in one press.
   **⬇️ DESCEND** drops you back to the deepest cell you have opened.
5. **Spend cash** on pickaxe tier (swing power), backpack capacity, and lamp radius — the mine
   has no sun, so the lamp is the difference between seeing a vein and walking past it.
   Spending can never cost you a rebirth: the rebirth gate is on what this run has **earned**,
   which only ever goes up.
6. **Hit the depth wall.** Below layer 24 is indestructible bedrock, and it tells you so.
   The walls and the floor are five anchored slabs rather than a grid — see *Why the box is five
   Parts*, below.
7. **♻️ REBIRTH** wipes cash, this run's earnings, haul, upgrades and this run's depth for a
   permanent cash multiplier, a wall twelve layers deeper, and **a completely new cave seed**.
   It costs a fixed fraction of the cave it is charged against — measured at 27-35% of the shaft,
   at every one of the 25 levels.

Deepest-ever depth goes to a global OrderedDataStore leaderboard and survives every rebirth.

---

## Why a grid of Parts and not voxel Terrain

Roblox's voxel Terrain would look better and would be untestable: the only way to ask it what is
at a point is to ask a running engine. A grid of cells answers *"what is at this cell, and what
does breaking it yield"* as arithmetic, so the whole cave — the carving, the ore gating, the
sealed box, the reveal rules — is asserted from the luau CLI before the game is ever opened.
That trade is the single biggest design decision in this game.

It is also why the cave can be SAVED. `opened` — the set of cells this player has dug out — is
the only record that any digging happened, because the generator is stateless and calls a mined
cell "rock" for ever. One bit per cell, six bits per character, and a whole rebirth-0 shaft dug
out completely fits in 336 characters of a DataStore. Without it, every cell except the centre
elevator column was standing again on the next login, ore included, and the same shaft could be
sold over and over by leaving and coming back.

---

## Why the box is five Parts

The ring and the floor are bedrock: indestructible, unclickable (bar the floor, which has to be
able to say "rebirth to go deeper"), and identical at every seed. Built cell by cell they were the
*entire* cost of a finished shaft — a fully excavated cave at the deepest wall is 10 097 Parts and
**every single one of them** is ring (10 048) or floor (49), because excavating a shaft leaves no
rock to have a face. So they are `Mine.shell`'s four wall slabs and one floor slab instead, and
10 097 becomes 5. `Mine.spec` samples every bedrock cell of the box at three rebirth counts and
requires each one to be inside a slab, and requires that no slab reaches into a cell a player can
dig.

## Why the shaft streams by depth

That leaves the rock and the ore, which a tunneller never removes: 11 960 Parts for an ordinary
dig-straight-down at the deepest wall, and 19 115 for a lattice dig, which is what a strip mine is.
So a Part exists only while its layer is within `Config.Mine.StreamLayers` (16) of the miner, and
the rest are destroyed and rebuilt from `opened` when the miner comes back. **`opened` is the cave
and none of this touches it** — the Parts were always derived from it, which is what makes the
restore possible at all, so unloading one forgets a rendering, not a dig.

16 layers is 96 studs, and that is set by the LIGHT rather than by taste: the mine has no sun and
the best lamp in the game reaches 74 studs, so nothing a player could have seen is ever missing.
The worst window anywhere in the game holds 1 124 Parts against 19 115. Full measurement, and why
this beats culling / pooling / `StreamingEnabled`, in `REVIEW-4.md`.

---

The cave is coherent **value noise** over a stateless hash of `(seed, x, y, z)`, *not* an LCG
stream like `grow-a-crystal`'s `Rng`. A stream's output depends on the order cells are drawn in,
and a player uncovers cells in whatever order they choose to dig. Determinism still comes from
one `WorldSeed`: `seed = WorldSeed * 7919 + rebirths * 104729`, so two players at the same
rebirth count are digging the *same* cave, which is the only reason a depth leaderboard means
anything.

Blocks are only built where the player has actually exposed them. `Mine.reveal` floods through
open cells with 6-neighbour connectivity (what you can walk through) and collects solid faces
with 26-neighbour connectivity (what you can *see*) — the second half is why the four corner
posts of the shaft are not a diagonal gap you can look straight out of the world through.

---

## Layout

```
deep-vein/
  default.project.json      Rojo: src/server -> ServerScriptService,
                            src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  src/shared/Config.luau    EVERY tunable, one table
  src/shared/Mine.luau      the cave: hash, noise, cell contents, reveal, geometry   (pure)
  src/shared/Ore.luau       depth-keyed rarity table, values, hardness               (pure)
  src/shared/Economy.luau   shop, backpack, sale                                     (pure)
  src/shared/Prestige.luau  rebirth requirement, multiplier, apply                   (pure)
  src/shared/Fx.luau        lighting + particle kit          (verbatim from grow-a-crystal)
  src/shared/FxClient.luau  camera/HUD juice                 (verbatim from grow-a-crystal)
  src/shared/Responsive.luau phone-first layout rules        (verbatim from grow-a-crystal)
  src/server/Main.server.luau   authoritative; the ONLY file that knows Roblox exists
  src/client/Hud.client.luau    display + buttons
  tests/*.spec.luau         one per pure module
```

**Shared modules take their dependencies as ARGUMENTS.** A bare `require("./Ore")` resolves in
the luau CLI and is *invalid in Roblox*; only the server and client scripts require, and they do
it from `ReplicatedStorage`. This exact mistake once made a server fail to load while every unit
test stayed green.

---

## Running the tests

```
cd deep-vein
luau tests/Ore.spec.luau            # 1272 passed, 0 failed
luau tests/Mine.spec.luau           #  173 passed, 0 failed
luau tests/Economy.spec.luau        #  131 passed, 0 failed
luau tests/Prestige.spec.luau       #  220 passed, 0 failed
luau tests/Responsive.spec.luau     #   70 passed, 0 failed
```

Then compile and analyze every source:

```
luau-compile --binary src/**/*.luau
luau-analyze src/shared/*.luau 2>&1          # analyze writes to STDERR
```

### Booting it headless

Unit tests cannot see the workspace. `robloxemu` runs the real server and the real HUD against a
fake engine and then asks the world what actually arrived:

```
cd ../robloxemu
py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
luau check_deepvein.luau                     # 136 passed, 0 failed
cd ../deep-vein
luau tests/walk.luau                         # 116 passed, 0 failed
```

Two headless gates, because they answer different questions. `check_deepvein.luau` is the
emulator's: it asks the workspace what actually arrived. `tests/walk.luau` is this game's own: it
asserts the corrected geometry, injects a failure into the Part factory to prove one bad Part
cannot stop the world, leaves and rejoins to prove the cave does not grow back, rides a 120-layer
veteran up and down to prove the shaft streams, and then **plays the game** — spawn to first
rebirth, reporting swings, hauls, cash and part counts rather than assertions.

Both of them put the miner *on the block* before swinging at it, because the shaft only holds
Parts for the layers around its miner, and because `MaxActivationDistance` says the same thing
about the real game.

**Re-run `wrap.py` after every source change.** The check reads the bundle, not `src/`, and a
stale bundle cost half an hour during this build: a fix already on disk simply was not in the
artefact under test, and the dig loop looked broken when it was not.

The check joins players, digs, sells, rides the elevator, rebirths and leaves. It exists because
Grow a Crystal shipped with `part.Parent` missing from `makeSocket` — the entire core loop of a
published game unreachable, and all 166 unit tests green, because none of them could see the
workspace.

---

## What is NOT built yet

- **Never run by a person.** No Studio session, no Roblox Player. Unit tests, a headless boot and
  a mutation sweep only.
- **No experience created, nothing published.** No place ID, no gamepasses, no thumbnail.
- **No auto-sell, no drill, no pets, no codes, no trading.** The brief mentions auto-sell-on-
  pickup as an alternative to hauling; only hauling is built.
- **Balance is arithmetic, not play.** Expected value and swings-per-block were computed at every
  depth and the incentive gradient is right (deeper always pays more per swing, and each pickaxe
  tier is a large multiplier), but nobody has actually played it for an hour.
- **The surface deck is a ledge inside the spawn cell.** The landing point is held up by an
  anchored slab buried one stud below the floor of the cell it stands in, inset a little on X and
  Z so no face of it shares a plane with the rock around it, and non-queryable so no click can
  resolve to it. A player CAN dig the cell they spawn on; when they do, the deck is what is left
  standing and SURFACE lands on it with a 5-stud drop. That is the price of SURFACE always having
  ground; the alternative was a 148-stud drop onto bedrock every time they pressed it.
- **Balance is measured, and now walked once.** Every rebirth is priced as a fixed fraction of the
  cave it is charged against, so all 25 levels land between 2.88x and 3.54x of their own shaft
  (they used to run from 3.5x to 27x). `tests/walk.luau` played the first one: **765 swings,
  195 blocks broken, 4 surface trips, layer 24 reached, $10 016 earned against a $6 473 price.**
  That is one run of one rebirth by a bot with a crude policy; nobody has played an hour of it.
