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

## State — v1 built + tested; two strata reviews closed; NEVER RUN BY A PERSON; NOT published
- **COMPLETE-GAME PASS (2026-10-01, `EYECANDY.md` §15, `docs/complete-game-standard.md`).** Every item of the
  standard checked; what was missing was built test-first (each new check watched failing on the unchanged game):
  1. *The board, public + friends* (§3): `Board.luau` (+1 Jump's, byte-identical) + `Config.Board`; the metric is
     `bestLayer` (server-measured), stored as `layer * 2e9 + (2e9 - bestAt)` in `DeepVein_LB_v2`, written only when
     it deepens (`writeBoard`, `Board.keepHigher`); a physical board per miner on the mouth's SOUTH wall (the wall
     they face at spawn) in `workspace.DeepBoards`, a ProximityPrompt toggling Public/Friends for its owner;
     friends on demand, capped 200, cached, throttled; names resolved and cached on the server, never saved;
     `Board.client` draws each player's own view. `check_deepvein_board` 92 / 0, `tests/Board.spec` 75 / 0.
  2. *Spawn* (§1): every player's `RespawnLocation` is `MinersRest` (`walk.luau`).
  3. *No silent no-ops* (§1): a click on a bedrock WALL now toasts why (`check_deepvein`).
  4. *Pacing in tests/* (§2): `tests/Pacing.spec.luau` plays the pace bot on the pure modules (`tests/DigModel.luau`)
     over eight drawn cave sequences: the magma (the brag) at 24.0-33.6 min normal, always in the third run; the
     core at 386 min. `check_deepvein_pace` stays as the end-to-end twin.
  5. *Ship and market* (§4): the store text in `README.md` (994 characters, plain ASCII), `MARKETING.md` (nine
     clips), `EYECANDY.md` §9 items 25-29 and §10 (1920x1080, shot 7: the board).
  Mutation sweep 7 (§15): 25 mutants, all killed; 4 controls, all unnoticed. Not committed, not published, Studio
  not opened, not independently reviewed.
- **SECOND REVIEW ROUND + OWNER DECISIONS (2026-09-30/10-01, `EYECANDY.md` §12, §14).** Eight findings, all
  reproduced first and closed test-first in the game:
  1. *The cave was computable on a client* (the generator and `WorldSeed` replicate; the probe predicted
     462 of 462 hidden ore cells). Each player's cave per rebirth is now a server-drawn 64-bit key
     (`Mine.world(cfg, rebirths, key)`; there is no keyless path), saved with the profile, never replicated.
  2. *A save overwrote another session's record.* Every write carries this session's token and this
     server's jobId, or it is cancelled.
  3. Core floor and hazard-model colours are config and held 70 RGB from ore. 4. The colour grade may not
     lift the unlit cave. 5. On phones the title card waits for a hazard warning, and the chip is never
     hidden and always readable (it shortens its text). 6. The server tells the client of every swing
     (`Swing` remote), so any swing wakes a resting miner. 7. Client budgets are capped in code. 8. The
     chip never counts down to a stratum below the depth wall.
  Owner decisions ("take the recommended option for all"; neither had a marked recommendation): (a) the
  first brag stays the magma, third run, 23.6-31.4 min normal over 8 drawn caves, asserted 20-45; (b) hazard
  clock 110-160 s, ordinary play one per 2.5-2.8 min, asserted one per 2-3.
  **Resume (2026-10-01):** the first attempt was cut off before its record and its sweep. The resume reproduced
  all eight findings on the unchanged game (the reviewer's probes; the new checks fail there), re-measured the
  decisions, ran mutation sweep 6 (45 mutants: 44 killed, P4 survived and is now killed; controls K1, K2, K4,
  K5 unnoticed, K3 rightly noticed because it changes the chip's text)
  and fixed four things in the round's own work: the session half of the owner check was untested (L3; a
  same-server takeover is now in `check_deepvein_lock`), the hazard cap in `CaveArt.showHazard` was
  unreachable (P4; `check_deepvein_cave_cap` now calls it directly), a race in `check_deepvein_cave`'s rest
  set-up (a hazard in flight; flaked 1 in 14), and a stray LF line. `EYECANDY.md` §14. Gates below.
- **THE STRATA (2026-09-23/24, `EYECANDY.md`, owner's brief of 2026-09-17).** The world changes with the
  depth you stand in: 11 strata from topsoil to the core, rare telegraphed vertical hazards (a rock
  overhead, a vent underfoot; one per ~3 min of ordinary digging, measured), and an unexploitable ⛺ Rest.
  The server only colours and textures the rock Parts it already builds (`Strata.rockLook`), so
  REVIEW-4's budget is untouched; everything else is `Cave.client` + `CaveArt`. Specs **2578 / 0**
  (+ EnvBands 124, Hazards 140, Rest 76, Strata 103, EnvConfig 269). Headless: walk 129,
  check_deepvein 136, check_deepvein_cave 387, _cave_budget 10, _cave_hud PASS, _cave_join 22,
  _strata 45, _pace 29, _rarity 15, all green. Mutation sweeps and the Studio shot list are in
  EYECANDY.md. **Adversarially reviewed once (2026-09-24): six findings, all closed test-first
  (EYECANDY.md §13). Not seen in Studio.**
- **1866 luau-CLI unit tests pass** for the game itself (Ore 1272, Mine 173, Economy 131,
  Prestige 220, Responsive 70).
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
- **Which cave: a SECRET KEY, not a public seed (2026-09-30).** `src/shared` replicates, so the cave must
  not follow from anything a client has. `Mine.world(cfg, rebirths, key)` takes `{ a, b }`, two 32-bit words
  the server draws (`drawKey`: a GUID through `Mine.keyFromHex`) for each player at each rebirth: `a` seeds
  the chain, `b` enters every cell's LAST mix (ore roll, every carving-noise corner), so no 32-bit state
  decides the cave. Saved as `data.caveKey` in the same write as `openedBits`; a rebirth draws a new one inside
  its atomic flush (snapshot and rollback include it); a session that cannot save digs a throwaway key (else a
  read-only session scouts the saved cave for free). NEVER put the key in an Instance, an attribute or a
  payload (`check_deepvein_secret` scans all three). `Mine.legacyKey(cfg, r)` is the old public cave, for
  test fixtures and the Studio shot recipe only; a fixture that needs a KNOWN cave stores it as `caveKey`.
- **Session lock: an owner token on every write (2026-09-30).** The load that takes the lock writes a fresh
  `session` GUID; `saveProfile` writes only while the record holds this session's token AND this server's
  jobId, else it cancels, sets `canSave = false`, pushes state and toasts. The jobId half catches a server
  running code from before tokens (it leaves our token in place); the token half catches a newer session on
  THIS server (same jobId). `check_deepvein_lock` stages both (mutants L2 and L3).
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
Server `src/server/Main.server.luau`; clients `src/client/Hud.client.luau`,
`src/client/Cave.client.luau` (the strata) and `src/client/Board.client.luau` (the board); shared `Board.luau` (+1
Jump's, byte-identical) and
`Config / Mine / Ore / Economy / Prestige / Fx / FxClient / Responsive.luau`, plus the strata's
`EnvBands / Hazards / Rest` (+1 Jump's templates; EnvBands byte-identical, the other two with marked
Deep Vein sections), `Strata` (pure) and `CaveArt` (client-only art);
tests `tests/*.spec.luau` (+ `tests/DigModel.luau`, the model `Pacing.spec` plays); headless gates `tests/walk.luau` (ours, editable),
`../robloxemu/check_deepvein.luau` (the emulator's) and `../robloxemu/check_deepvein_*.luau` (the
strata and the rest). Reviews: `REVIEW.md`, `REVIEW-2.md`, `REVIEW-3.md`, `REVIEW-4.md`; the strata: `EYECANDY.md`;
the clip list: `MARKETING.md`; the store text: `README.md`.

**Strata invariants.** The strata are driven by DEPTH, never time. The named layer is `Mine.layerOfY`
at the ROOT, the server's own `minerLayer`; at the feet it sat on the floor's plane, fixed 2026-09-24.
The client decides "open" from Parts it can see, never from the cave generator. A hazard launches
only when the miner has an open cell beside them. Rest can neither start with a hazard inbound nor be
toggled between swings (`SettleSeconds`, `MinAwakeSeconds`). The client fires no remote and changes
nothing the server built (`check_deepvein_cave` §8). From the 2026-09-24 review (EYECANDY.md §13):
a falling hazard is DRAWN by `Strata.dropY` (never inside the miner, `Env.HeadTopAboveFloor`; falls
visibly; lands on the floor) while the plan and the hit stay the plan's; its ring lies on the floor the
miner last stood on (`Strata.ringLayer`), not the root's layer; no stone uses the bedrock's material or
comes within `Env.MinBedrockContrast` of its colour (`Config.Mine.BedrockColor`; since 2026-10-01 the walls carry a
ClickDetector only to say why they cannot be mined, never a cell); every glowing decor colour is `Env.DecorGlow` and stays `MinDecorOreContrast` from any
ore beside it; underground fill light stays within `Env.LampFill` of the server's dark preset, so the
paid lamp stays the light; a phone HUD drawer moves the strata row aside, never hides it.
From the 2026-09-30 review (EYECANDY.md §14): the core floor's and every hazard model's colours are config
(`Env.PieceGlow`, `Env.HazardLook`) and held `MinDecorOreContrast` from ore; the colour grade's Brightness
never lifts over the preset (`LampFill.MaxBrightnessLift` 0); a title card never shares the screen with the
hazard warning (it waits, and comes back); the chip is never hidden and picks the longest of four texts that
gets 6 screen px per character; the chip never counts down past the depth wall (read off the floor slab);
the server's `Swing` remote wakes a resting miner on any swing; decor and critters are admitted only within
`Budget.MaxLocalParts` after the pieces and fixed items, the weather leaves one emitter and 16 particles/s for
a hazard, pieces light at most `MaxLights` − 2, one hazard model at a time.

**Board invariants (2026-10-01).** The metric is `bestLayer`, raised only by `noteOpen` (a cell the server opened),
which also stamps `bestAt`; a profile with a best and no `bestAt` is stamped at load (a `bestAt` of 0 would encode
as one layer deeper: mutant M3 showed Dee's 9 stored as 10). `writeBoard` runs only after a profile write landed,
only when `bestLayer > boardLayer`, through `Board.keepHigher`. The board lives in `workspace.DeepBoards`, NOT in
the shaft folder (the shaft's part counts are asserted, and a rebirth rebuilds the shaft), and goes when its owner
leaves. Only the owner toggles it. The HUD's top 10 gets decoded depths in studs and the server's names; no client
looks a name up.

## Gates: how to run every one (26 suites, all green on 2026-10-01, pass 2)
```
cd D:\Claude\Roblox\robloxemu && py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau   # ALWAYS first
cd D:\Claude\Roblox\deep-vein && luau tests/<X>.spec.luau        # 12 specs: Ore 1272, Mine 223, Economy 131,
                                                                # Prestige 295, Responsive 70, EnvBands 124,
                                                                # Hazards 140, Rest 76, Strata 103, EnvConfig 283,
                                                                # Board 75, Pacing 36
luau tests/walk.luau                                            # 130
cd D:\Claude\Roblox\robloxemu && luau check_deepvein<_X>.luau   # check_deepvein 144, _board 92, _cave 589,
    # _cave_budget 10, _cave_cap 14, _cave_hud PASS (18 viewports), _cave_join 22, _cave_row 13, _strata 45,
    # _pace 29, _rarity 15, _secret 27, _lock 49
```
Specs 2828 / 0, headless 1179 / 0 + PASS. The slow ones: `_pace` (50-110 s), `_rarity` (20-55 s), `Pacing.spec`
(about 20 s), `Prestige.spec` (up to 20 s). Append `2>&1` (a failing assert goes to stderr).

**This game's traps** (on top of `docs/new-game-checklist.md`):
- A stale bundle: every headless gate reads `build/deep-vein.luau`, not `src/`.
- A fixture that expects a particular cave (a void, a pit, a hand count) must store `caveKey =
  Mine.legacyKey(Config, r)`; a fresh player digs a drawn cave. The emulator's GUIDs are a counter, so a new
  `GenerateGUID` call anywhere shifts every later key in a check (the pace check's minutes move with it).
- The hazard clock is random and unseeded: a check that times rest or idle must keep hazards out of its
  window (an inbound hazard resets the idle clock by design), and a swing under a threat never drops a queued
  rest, so a set-up that expects it dropped must let a hazard in flight play out first (fixed 2026-10-01 in
  `check_deepvein_cave`; it flaked 1 in 14).
- A cap that the normal flow never reaches (the client always hides a hazard before the next) is only tested
  by calling the code directly (`check_deepvein_cave_cap`'s never-hiding caller).
- `CaveArt` builds colours from `Config.Env` palettes; a hard-coded colour bypasses `EnvConfig.spec`, and only
  `check_deepvein_cave`'s as-built reads catch it.
- CRLF (measured 2026-10-01): `Config`, `CaveArt`, `Hazards`, `Rest`, `Cave.client`, `Hud.client`,
  `tests/Hazards.spec`, `tests/Rest.spec`, `CLAUDE.md`, `EYECANDY.md`, `README.md` and
  `robloxemu/check_deepvein_cave.luau`; the rest LF. Edit in the file's own line ending.
  Pass 2's new files: `MARKETING.md` CRLF; `Board.luau`, `Board.client`, `tests/Board.spec`, `tests/Pacing.spec`,
  `tests/DigModel` and `check_deepvein_board` LF, as their +1 Jump originals. Git Bash's `grep -c $'\r$'`
  miscounts here: count line endings with Python.
- The board: `Board.luau` is a byte-identical copy of `plus1-jump/src/shared/Board.luau` (sha256 `07fa43c3…`); a
  fix belongs in +1 Jump first. The emulator's `Players` methods cannot be wrapped (assigning one throws), so the
  board check proves "the names come from the server" with a name only the server knows (Eve, from a friends
  list). A friends check supplies its own `Players.GetFriendsAsync` (the emulator has none).
- `Pacing.spec` and `check_deepvein_pace` are two measurements of one bot; a change to the bot's policy goes in
  both (`tests/DigModel.luau` and the check).

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
0. **Against `docs/complete-game-standard.md` only the night shift's items remain** (its §5): the Studio check of
   `EYECANDY.md` §9 (items 1-29), the thumbnails (§10, 1920x1080), the clips (`MARKETING.md`; each needs a
   scenario in `tools/film_game.py`, which is the tools owner's), the universe, publishing,
   `docs/marketing/store-text.json` (after publishing) and marketing. Pass 2 has not had an independent review.
1. **Open it in Studio and play it.** Nothing here has been seen by a human. First real session
   will surface camera/click/fall problems no emulator can. The strata's own Studio list and the
   thumbnail shot list (with a recipe to start deep without saves) are in `EYECANDY.md` §9-§10.
   The strata's first adversarial review (2026-09-24) is closed (§13); the palette and fill-light
   changes it forced are exactly the things only Studio can judge (§9 items 1, 7, 17).
2. Create the experience, upload, run the content-maturity questionnaire, set Public.
3. Then: auto-sell upgrade, a drill (area mining), codes, gamepasses (2x cash, auto-sell, lamp),
   (The per-rebirth biome palette is done: that is the strata.)
