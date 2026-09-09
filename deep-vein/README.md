# Deep Vein ⛏️ — Mining Simulator

Every dive drills through a genuinely procedural cave. Drop into your own shaft, swing at the
rock, break into voids nobody has seen before, haul the ore up, upgrade, and rebirth for a
permanent multiplier and a brand new cave.

Built from Game-Radar #3 (2026-09-09). Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/` and `anomaly-observatory/` — same stack: one CONFIG table, pure logic in
`src/shared` tested from the luau CLI, a server that owns every decision, a phone-first HUD.

---

## The loop

1. **Spawn in the mouth of your shaft** — a 7×7 open room at the surface, ringed by bedrock
   three cells tall so you cannot jump out of the mine.
2. **Click a block to swing at it.** Each block has hit points; your pickaxe has power. Break it
   and the faces behind it appear — including, sooner or later, a natural cave void that opens up
   all at once.
3. **Ore goes in your backpack** (copper from layer 1, iron from 4, gold from 9, diamond from 14
   and obsidian from 19 — every tier reachable inside the rebirth-0 depth wall at layer 24).
   Stone is real, minable and worth nothing.
4. **🛗 SURFACE + SELL** teleports you back to the mouth, onto an anchored deck that no
   swing can reach, and sells the haul in one press.
   **⬇️ DESCEND** drops you back to the deepest cell you have opened.
5. **Spend cash** on pickaxe tier (swing power), backpack capacity, and lamp radius — the mine
   has no sun, so the lamp is the difference between seeing a vein and walking past it.
6. **Hit the depth wall.** Below layer 24 is indestructible bedrock, and it tells you so.
7. **♻️ REBIRTH** wipes cash, haul, upgrades and this run's depth for a permanent cash
   multiplier, a wall twelve layers deeper, and **a completely new cave seed**.

Deepest-ever depth goes to a global OrderedDataStore leaderboard and survives every rebirth.

---

## Why a grid of Parts and not voxel Terrain

Roblox's voxel Terrain would look better and would be untestable: the only way to ask it what is
at a point is to ask a running engine. A grid of cells answers *"what is at this cell, and what
does breaking it yield"* as arithmetic, so the whole cave — the carving, the ore gating, the
sealed box, the reveal rules — is asserted from the luau CLI before the game is ever opened.
That trade is the single biggest design decision in this game.

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
luau tests/Mine.spec.luau           #  100 passed, 0 failed
luau tests/Economy.spec.luau        #  122 passed, 0 failed
luau tests/Prestige.spec.luau       #  117 passed, 0 failed
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
luau check_deepvein.luau                     # 87 passed, 0 failed
```

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
- **Side tunnels are not saved.** A rejoining player gets their cash, upgrades, rebirths, best
  depth and a restored *centre elevator column* down to the depth they had reached — but the
  rooms they carved out to the sides are gone. Saving the full broken-cell set is a DataStore
  size problem this version does not solve.
- **No auto-sell, no drill, no pets, no codes, no trading.** The brief mentions auto-sell-on-
  pickup as an alternative to hauling; only hauling is built.
- **Balance is arithmetic, not play.** Expected value and swings-per-block were computed at every
  depth and the incentive gradient is right (deeper always pays more per swing, and each pickaxe
  tier is a large multiplier), but nobody has actually played it for an hour.
- **The surface deck blocks one cell.** The landing point is held up by an anchored slab filling
  the top stud of the cell below it, so a player cannot dig straight down from exactly where they
  spawn — they have to step one cell over. That is the price of SURFACE always having ground
  under it; the alternative was a 150-stud drop onto bedrock every time they pressed it.
- **A very large excavation keeps adding Parts.** One swing now costs at most
  `Config.Mine.PartsPerFrame` (64) instances per frame, whatever size the void behind the wall
  turns out to be, but the TOTAL is still only bounded by the shaft itself (a closed box, at most
  ~2,000 cells at rebirth 0) and there is no unload of blocks far above the player.
- **Balance is measured, not played.** Every rebirth is now provably payable out of the shaft it
  is charged against — the tightest is rebirth 0 at 3.5x, i.e. you can buy it having mined
  under a third of your cave — but the middle of the ladder is generous (rebirths 3-15 cost
  under a tenth of their cave) and nobody has played an hour of it to say whether that reads as
  momentum or as a missing gate.
