# Vault Runners — context for a fresh session

## State

v1 is **built and green, and has never been run by a person or published.** No Roblox experience
exists for it, no `publish_*.bat` exists, and the tree was deliberately left dirty and
uncommitted.

```
tests/Rng.spec.luau            37 passed, 0 failed
tests/Progression.spec.luau    63 passed, 0 failed
tests/Pets.spec.luau           75 passed, 0 failed
tests/RunState.spec.luau       75 passed, 0 failed
tests/VaultFloor.spec.luau    199 passed, 0 failed
tests/responsive.spec.luau     70 passed, 0 failed
check_vaultrunners.luau        71 passed, 0 failed   (headless boot: builds a vault, plays 5 runs)
check_vaulthud.luau            PASS                  (HUD fits all 10 viewports)
```

Regenerate the emulator bundle after ANY edit under `src/`, or the headless checks measure the
previous build:

```
cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
```

## Invariants — do not break these

1. **Gems bank ONLY on an escape before `sealAt`.** `RunState.tryEscape` is the only place gems
   become real, and it refuses once `now >= sealAt` (INCLUSIVE — a boundary that pays out on the
   exact second is a boundary players sit on). Reaching the exit is not the win condition. If you
   are tempted to pay out somewhere else, the game has no risk in it any more.
2. **Nothing in `src/shared` requires anything.** Dependencies are arguments:
   `VaultFloor.build(cfg, spec, MazeGen, Rng)`. A bare `require("./MazeGen")` resolves in the luau
   CLI and is INVALID in Roblox.
3. **`src/shared/MazeGen.luau` is labyrint-spill's file, copied VERBATIM.** Do not edit it. It is
   the proven generator and it is only ever asked for a grid. It needs `rng:NextInteger(1, n)`,
   which is why `Rng` grew that method — routed through `Rng.below` (high bits), because MazeGen
   asks for 1..4 and that is a power-of-two span where the `Rng.int` modulo path collapses.
4. **Unlocks read `totalBanked`, never `gems`.** Spending on a pet must not lock a vault.
5. **Ownership is `profile.pets`, never `profile.equipped`.** `Pets.multiplier` checks the ledger;
   the first cut did not, and a profile owning nothing carried a 1.65x Crownwyrm.
6. **Every Instance gets a `Parent`.** `buildVault` counts BaseParts by walking the folder it just
   built and asserts against what the generator produced. Do not replace that with a loop counter
   compared against itself — that is the same arithmetic on both sides and can never disagree.
7. **`DataStoreService:GetDataStore` is pcall'd** (`tryStore`). Unwrapped it raises in an
   unpublished place and kills the whole server script at load.
8. **The kill plane stops AT the top storey's floor** (`Config.Vault.KillPlaneTop = 0`). If it
   climbs higher it kills a runner standing at the exit a second before the countdown expires, and
   the seal never fires in a real run. `VaultFloor.spec`'s `collapseSweepsVault` asserts both ends
   of that: it must reach the top floor, and it must not go past it by more than `Run.KillMargin`.
9. **One CONFIG table.** Every tunable is in `src/shared/Config.luau`. Per-feature RNG salts live
   in `VaultFloor.luau` (same convention as grow-a-crystal's `Cavern.luau`) because they are
   structure, not tuning.
10. **Determinism.** `Progression.seedFor(cfg, tier, floor)` =
    `WorldSeed * 1000003 + tier * 7919 + floor * 2654435761`, and every storey adds `storey * 6151`
    on top. Keep intermediates under 2^53; past that the low bits vanish and whole runs of floors
    generate the identical maze. Changing `Config.WorldSeed` changes every floor in the game.
11. **The HUD is design px; `AbsoluteContentSize` is screen px.** Divide by `uiScale.Scale` when
    setting a `CanvasSize`. Tap targets are sized `ceil(46 / scale)` on touch, so 44+ SCREEN px
    survives the UIScale. Both rules were caught by `check_vaulthud.luau`, not by reading.

## How the vault is put together

`VaultFloor.build` stacks `storeys` mazes. Storey `s`'s walkable floor top is `y = s * 18`. Walls
run from there to the underside of the floor above (`WallHeight` is DERIVED as
`StoreyHeight - FloorThickness`, so a gap band cannot be introduced by editing one number).

You enter storey `s` at maze cell `(0,0)` when `s` is even and `(cells-1, cells-1)` when odd, and
leave from the opposite corner — so **storey s's exit IS storey s+1's entry**, and the stair, the
hole in the floor above, and the arrival cell are the same column by construction. Both corners are
always carved cells in a perfect maze, so this never needs a special case.

The floor of every storey above 0 is FOUR rectangles around a one-cell hole. The first cut used one
solid slab and the spec's first run said *"storey 1 floor covers its own entry hole"* — a beautiful
vault, full of gems, that no player could ever climb out of. That is what `CHECK.climbHoleOpen`
exists for.

Wall cells are run-length merged along X (Bronze floor 1 is 96 parts; the worst floor in the game
is 618, against a 1500 budget the spec asserts). `CHECK.wallsMatchMaze` verifies the merge
cell-by-cell in both directions AND that every wall edge lands on a grid boundary — sampling cell
centres alone could not see a run that grew half a cell at each end, and the mutation gate proved
it.

## Known noise

`luau-analyze src/shared/MazeGen.luau` prints 18 lines of type noise about `{{number}}` vs
`{{unknown & unknown}}`. It is **byte-identical to the noise labyrint-spill's own copy produces**
(verified by diff) and is inherited with the verbatim copy. Every other file analyses clean.

## What to do next, in order

1. **Play it.** Nobody has. The 70-second Bronze countdown against a 3-storey 4x4 maze is a guess.
   Time a real climb before touching anything else; `Config.Tiers[n].collapseSeconds` and
   `Config.Curve.CollapseTightenPerFloor` are the two dials.
2. Close the gap between the store description and the build — see README's "What is NOT built
   yet". The two that a player will actually notice are **pets are bought rather than hatched**
   and **pets do not level**.
3. Sound. There is not one Sound instance in the game, and a rising collapse with no audio is half
   a collapse.
4. A leaderboard. Runs are already deterministic per (tier, floor), so a time is comparable; only
   the recording is missing.

## What this game deliberately does NOT have

Ship-scope from the brief, held to on purpose: **3 vault tiers, 1 pet rarity, no breeding, no
trading, no eggs.** If a future session is about to add a fourth tier or a second rarity, that is a
scope decision to make explicitly, not a drift.
