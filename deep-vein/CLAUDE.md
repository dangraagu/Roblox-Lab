# CLAUDE.md — Deep Vein (Roblox)

Context so a fresh session can continue. Sibling of `grow-a-crystal/`, `labyrint-spill/`,
`plus1-jump/` and `anomaly-observatory/`; same stack (CONFIG-driven, DataStore with a pcall'd
`GetDataStore` + soft session-lock, pure logic tested from the luau CLI, phone-first HUD).
Built from Game-Radar #3 (2026-09-09): "Deep Vein: Mining Simulator", the evergreen entry.

## What it is
Procedural mining simulator. Your own shaft (a GRID OF PARTS, not Terrain) → click a block to
swing → hit points come off → it breaks, the ore lands in your backpack and the faces behind it
are revealed → haul up with 🛗 SURFACE + SELL → buy pickaxe / backpack / lamp → dig deeper → hit
the bedrock depth wall → ♻️ REBIRTH for a permanent cash multiplier, a deeper wall and a NEW cave
seed. Single shared server, one private shaft per player, no PvP.

## State — v1 built + tested; REVIEW-3's last blocker closed; NEVER RUN BY A PERSON; NOT published
- **1866 luau-CLI unit tests pass** (Ore 1272, Mine 173, Economy 131, Prestige 220, Responsive 70).
- **Two headless gates, both green.** `tests/walk.luau` (ours, 129 passed) and
  `robloxemu/check_deepvein.luau` (the emulator's, 136 passed).
- **THE SPAWN RACE IS FIXED (2026-09-10).** Measured in Studio on a sibling game and now modelled
  by `robloxemu`: `Player.CharacterAdded` fires while the character is still UNPARENTED at the
  world origin, and the engine parents AND places it on the enabled `SpawnLocation` **one frame
  later**, silently discarding any CFrame written inside the handler. `place` wrote one straight
  away, so every miner was left standing on `MinersRest` — measured at **-80.00, 2.51, 0.00**,
  82 studs from shaft 0's own landing at `0.00, 4.00, -18.00` and 240 studs from shaft 1's — and
  because the engine drops EVERY character on the same pad, **two miners who joined together stood
  0.0 studs apart**, in nobody's mine, on every join and every respawn. `place` now waits for
  `char.Parent` (bounded, 300 frames) and re-reads its state across the yield. `WaitForChild` is
  NOT that wait: on the server both children already exist when the event fires, so it never
  yields. Measured after the fix: `0.00, 4.00, -18.00` and `160.00, 4.00, -18.00`, exact.
- **REVIEW-4 closed the unload.** A fully excavated deep shaft was 10 097 Parts rebuilt on every
  join; it is 5. The worst state the game can reach — a lattice dig at rebirth 24, which is what a
  strip mine is and which REVIEW-3's `<= 12000` bound never measured — was 19 115 and is 1 124.
  Two changes, covering disjoint halves: the bedrock box is `Mine.shell`'s five slabs instead of
  10 097 cubes, and rock/ore Parts exist only within `Config.Mine.StreamLayers` (16) layers of the
  miner. See REVIEW-4.md.
- **`tests/walk.luau` plays the game**, with the miner standing where a player would have to
  stand: spawn → dig → fill the bag → SURFACE+SELL → shop → descend → repeat → rebirth. Last run:
  772 swings, 195 blocks broken, 4 surface trips, layer 24, $10 016 earned against a $6 473 price,
  **peak 491 Parts held** (1 085 for the same dig before REVIEW-4), worst swing 6.0 studs.
- **REVIEW-2's eight open findings and three regressions are closed**, plus one defect neither
  review found (the reward gradient inverted below layer 40). See REVIEW-3.md for the measurement
  behind every number. The load-bearing changes:
  1. *The cave is saved.* `Mine.packOpened`/`unpackOpened`/`faces` — one bit per cell, 336
     characters for a fully dug rebirth-0 shaft, 4 224 at the deepest wall. Before this, a relog
     regrew everything but the centre column and the same ore could be sold for ever.
  2. *The rebirth gate is on `runEarned`, not on `cash`.* Earnings only go up, so the three
     upgrade tracks can no longer spend a player permanently out of a rebirth.
  3. *The price is computed from the ore table*, not fitted to it: `Prestige.requirement` =
     `PriceFraction` x the analytic value of the whole shaft x the multiplier. All 25 levels now
     cost 2.88x-3.54x of their own cave; they used to run 3.5x .. 27x.
  4. *Hardness stops ramping at layer 40* (`Config.Mine.HardnessCapLayer`). It ramped for ever
     while the ore weights saturate, so expected value per hit point peaked at 1.2065 on layer 40
     and fell to 0.3085 by layer 312 — every rebirth past the fourth bought a WORSE mine.
  5. *The ore ladder starts shallower and flatter* (MinLayer 1/3/6/10/14, obsidian 1400 -> 800).
     The richest four cells were 46% of a rebirth-0 shaft; they are 15.7% now.
  6. *The surface deck is buried a stud deeper, inset 10%, and CanQuery = false*, so nothing is
     coplanar with it and no click can resolve to it.
  7. *The build pump runs on a lease, not a latch*, and pcalls each cell. One bad Part costs one
     Part; a pump killed by anything at all is replaced within a second.
  8. *There is a SpawnLocation* (`workspace.MinersRest`), west of shaft 0 and clear of every mine.
     Not a nicety for a frame nobody sees: after the spawn-race fix above, this pad is where the
     engine genuinely puts every miner for one frame before the game moves them. `walk.luau` now
     also asserts it is `Enabled` and that it is the world's ONLY enabled spawn, because the engine
     ignores disabled ones and picks arbitrarily among several.
- A 15-mutation sweep killed 13 of 13 real defects; both controls stayed green. Table in REVIEW-3.
- `luau-compile` clean on all 10 sources; `luau-analyze` clean apart from Roblox global/type noise.
- **Not published**: no experience, no place ID, no gamepasses, no maturity questionnaire.
- **Never rendered**: no material, colour, lighting, camera, click reach or humanoid-on-a-6-stud-
  grid observation exists anywhere. That is the single largest remaining risk.

## Core model / important invariants
- **The cave is a pure function.** `Mine.kindAt(cfg, world, x, y, z)` → `air | rock | bedrock |
  void`, and `Mine.cell` adds the ore and the hit points. No Roblox global anywhere in
  `src/shared`. The server is the only file that turns a cell into a Part.
- **Stateless hash, not an LCG stream.** A player uncovers cells in whatever order they dig, so
  cell contents must not depend on generation order. `Mine.hash` is a murmur3 finalizer over
  `(seed, x, y, z, salt)` with an exact 32-bit multiply (`mul32` splits into 16-bit halves —
  `a * b` near 2^32 is 2^64 and silently loses its low bits in a double).
- **Determinism**: `seed = WorldSeed * 7919 + rebirths * 104729`. Same rebirth count = same cave
  for everybody, which is the only thing that makes the depth leaderboard mean anything.
- **The shaft is a sealed box, and the box is FIVE PARTS.** Bedrock ring at x/z = 1 and GridW at
  every layer, bedrock floor at `maxLayer + 1`, open only at the top. `Mine.inWorld` bounds it; the
  reveal flood cannot escape upward. Those cells are never breakable and never change, so they are
  `Mine.shell`'s four wall slabs and one floor slab rather than one cube each — that was 100% of
  REVIEW-3's 10 097. The walls stand `Config.Mine.RimCells` (3) cells proud of the mouth because
  one 6-stud cell is under a Roblox jump and a player could hop out of the mine. The floor slab is
  the only bedrock carrying a ClickDetector: the depth wall has to explain itself.
- **The shaft STREAMS by depth.** A cell Part exists only while its layer is within
  `Config.Mine.StreamLayers` (16 = 96 studs, a third past the best lamp's 74) of the miner.
  `bandOf` / `setBand` / `restream` / `streamTo` in the server; `Mine.faces` takes the window.
  `opened` is untouched by any of it — the Parts were always derived from it, so unloading one
  forgets a rendering, not a dig. Three things this has to keep doing, all mutation-tested: a
  teleport builds its own 3x3 landing column SYNCHRONOUSLY before the CFrame moves (or the miner
  falls through a floor that does not exist yet), a half-broken block keeps its hit points across
  an unload, and `drainBuild` re-checks the band so a queue filled for a band the miner has left is
  dropped rather than built one frame behind the unload that was meant to prevent it.
- **Reveal: walk with 6, look with 26.** Flood through open cells with 6-neighbour connectivity
  (what you can move through), collect solid faces with all 26 (what you can see). Collecting
  with 6 leaves the four corner columns unbuilt — a diagonal gap straight out of the world.
- **Units**: `depthLayer` / `bestLayer` are LAYERS. Studs are display only
  (`Mine.depthStuds`). The leaderboard publishes studs.
- **DataStore integer-key trap**: `inventory` is keyed on ore tier (integers) and JSON
  round-trips sparse integer keys to STRINGS. `numKeys` normalises on load. Note that
  `Economy.carried` still reads *correct* with string keys (it sums values over `pairs`), so the
  assertion that actually catches a dropped `numKeys` is on **haul VALUE**, not on unit count.
- **Swing cooldown uses `tick()`, not `os.clock()`.** `os.clock` is CPU time and barely moves in
  a headless run, so a cooldown built on it refuses every swing the emulator makes and the entire
  dig loop becomes untestable. `tick()` is the clock the harness advances.
- **Rebirth is the only irreversible action** and is granted inside an atomic flush: snapshot →
  `Prestige.apply` → `saveProfile`; if the write did not persist, roll the snapshot back. The
  snapshot must include `runEarned` and `openedBits`, and `openedBitsOf` refuses to pack while
  `worlds[plr].rebirths ~= profile.rebirths` — otherwise the flush writes the OLD cave's dug cells
  under the NEW rebirth's number and the new cave arrives pre-drilled with holes in wrong places.
- **No silent no-ops.** Every refused action sends a Toast. That is what "i cant even place a
  seed" was in the sibling game.

## Files
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau`; shared
`Config / Mine / Ore / Economy / Prestige / Fx / FxClient / Responsive.luau`;
tests `tests/*.spec.luau`; headless gates `tests/walk.luau` (ours, editable) and
`../robloxemu/check_deepvein.luau` (the emulator's, read-only). Reviews: `REVIEW.md`,
`REVIEW-2.md`, `REVIEW-3.md`, `REVIEW-4.md`.

## Things the suite is known NOT to see
Two mutation sweeps have run: 13 real defects in REVIEW-3 and 12 in REVIEW-4, all 25 killed, with
four controls (deck colour, `AutosaveSeconds`, shell slab colour, `StreamPeriod`) correctly
unnoticed. What is genuinely uncovered: anything visual (nothing renders), the `plr.Parent == nil`
race in `onPlayerAdded` (the emulator's DataStore is synchronous and never yields, so no ordering
it can produce reaches it), and whether a Roblox humanoid can actually walk and jump on a 6-stud
grid of cubes. **Reach is now half-covered**: both gates stand the miner on the block before
swinging (worst measured 6.0 studs against `ReachStuds = 26`), but neither engine-checks
`MaxActivationDistance` itself. Also uncovered: a player who outruns the streamer in a long fall —
the emulator has no physics.

## Next
1. **Open it in Studio and play it.** Nothing here has been seen by a human. First real session
   will surface camera/click/fall problems no emulator can.
2. Create the experience, upload, run the content-maturity questionnaire, set Public.
3. Then: auto-sell upgrade, a drill (area mining), codes, gamepasses (2x cash, auto-sell, lamp),
   a per-rebirth biome palette so deep caves look different rather than just paying more.
