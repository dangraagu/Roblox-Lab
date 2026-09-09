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

## State — v1 built + tested + REVIEW FINDINGS CLOSED; NEVER RUN BY A PERSON; NOT published
- **1681 luau-CLI unit tests pass** (Ore 1272, Mine 100, Economy 122, Prestige 117, Responsive 70).
- **116 headless assertions pass** (`robloxemu/check_deepvein.luau`) — the real server and the
  real HUD boot against the fake engine, a fresh shaft lands exactly 115 BaseParts in the
  workspace, digging breaks blocks and reveals neighbours, a mined block STAYS mined, selling
  pays, the elevator moves the character, and rebirth rebuilds a different cave.
- **REVIEW.md's four blocking findings are closed**, plus two more the review did not find:
  1. *Mined blocks grew back.* `Mine.reveal` collected solid faces without consulting `opened`,
     although the air half of the same loop did. Any neighbour you broke rebuilt the cell you had
     just mined, at full hit points with a fresh ore payload. Fixed in `Mine.luau`; the assertion
     lives in `Mine.spec` ("reveal never reports an already-mined cell as a solid face again").
  2. *SURFACE dropped you down your own hole.* The landing is a fixed cell whose floor was
     ordinary breakable rock to bedrock. There is now a `SurfaceDeck_<uid>` — anchored, no
     ClickDetector, filling the top stud of the cell below the landing point, so the destination's
     support cannot be removed by any game mechanic.
  3. *One reveal instantiated unbounded Parts.* `RevealBudget` caps AIR cells, not the solid list
     that comes out of them (measured: 334 parts at rebirth 0, 3031 at rebirth 24, in ONE frame).
     Solids now go through a per-player build queue drained `Config.Mine.PartsPerFrame` at a time.
  4. *Obsidian could not spawn.* MinLayer 26 vs a rebirth-0 wall of 24. The ladder moved to
     `{1, 4, 9, 14, 19}` with richer deep tiers; `Ore.spec` now asserts every tier is legal above
     the wall and `Mine.spec` censuses the rebirth-0 shaft for at least 3 cells of each.
  5. *(new) The restored elevator column was solid rock.* The rejoin restore marked each column
     cell opened but never removed the Part built for it by the reveal of the cell above — 18 of
     24 layers, with DESCEND aimed at the bottom. `openCell` now destroys anything standing in a
     cell it opens.
  6. *(new) The rebirth ladder was mathematically unreachable.* Mining out EVERY cell of a
     rebirth-0 shaft pays $5,876 against a $30,000 requirement, and the gap widened at every one
     of the 25 levels (0.196x, 0.382x, … 0.000x). Finding 1's infinite currency printer was
     hiding it. `Prestige.requirement` is now quoted in ORE (multiplied by the same rebirth
     multiplier that inflates every sale) and grows 1.21x per rebirth, which is the world's own
     measured growth; `Prestige.spec` walks all 25 levels and demands 2x headroom.
- `luau-compile` clean on all 10 sources; `luau-analyze` clean apart from Roblox global/type noise.
- **Not published**: no experience, no place ID, no gamepasses, no maturity questionnaire.
- **Not play-tested**: balance is arithmetic only. See README "What is NOT built yet".

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
- **The shaft is a sealed box.** Bedrock ring at x/z = 1 and GridW at every layer, bedrock floor
  at `maxLayer + 1`, open only at the top. `Mine.inWorld` bounds it; the reveal flood cannot
  escape upward. The layer-0 ring is instantiated **three cells tall** (`RIM_MULT`) because one
  6-stud cell is under a Roblox jump and a player could hop out of the mine.
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
  `Prestige.apply` → `saveProfile`; if the write did not persist, roll the snapshot back.
- **No silent no-ops.** Every refused action sends a Toast. That is what "i cant even place a
  seed" was in the sibling game.

## Files
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau`; shared
`Config / Mine / Ore / Economy / Prestige / Fx / FxClient / Responsive.luau`;
tests `tests/*.spec.luau`; headless gate `../robloxemu/check_deepvein.luau`.

## Things the suite is known NOT to see
A mutation sweep ran 12 real defects through the gates; all 12 turned it red, and two controls
(dropping `part.CastShadow = false`, retuning `Config.Save.AutosaveSeconds`) stayed green as they
should. What is genuinely uncovered: anything visual (nothing renders), the `plr.Parent == nil`
race in `onPlayerAdded` (the emulator's DataStore is synchronous and never yields, so no ordering
it can produce reaches it), and the real `MaxActivationDistance` — the check fires ClickDetectors
directly and never checks that a player is actually close enough to swing.

## Next
1. **Open it in Studio and play it.** Nothing here has been seen by a human. First real session
   will surface camera/click/fall problems the emulator cannot.
2. Fix the remaining untidy edges: no unload of blocks far above the player, and no
   `SpawnLocation` anywhere (the game relies on `CharacterAdded` CFrame-ing the root part, which
   the headless check does exercise, but Roblox will pick its own spot for the frame before it).
3. Create the experience, upload, run the content-maturity questionnaire, set Public.
4. Then: auto-sell upgrade, a drill (area mining), codes, gamepasses (2x cash, auto-sell, lamp),
   a per-rebirth biome palette so deep caves look different rather than just paying more.
