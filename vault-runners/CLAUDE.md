# Vault Runners — context for a fresh session

## State

v1 is **built and green, and has never been run by a person or published.** No Roblox experience
exists for it, no `publish_*.bat` exists, and the tree was deliberately left dirty and
uncommitted.

Four review passes so far, and they supersede each other — read them newest first.
`REVIEW-4.md` is the obby: the crumbling climb shaft, how its cost was priced into the countdown,
the re-derived monotonicity table, and the mutation gate. `REVIEW-3.md` is the difficulty curve:
the slack schedule, where its numbers came from, the monotonicity and jitter measurements.
`REVIEW-2.md` is the independent re-check of the first round of fixes. `REVIEW.md` is the original
**BLOCK** on eight findings; all eight are now closed — the eighth (finding 7, "the game is not
the obby its brief sells") was closed by BUILDING the obby, not by retitling the game.
Do not assume a number in this file is the original.

```
tests/Rng.spec.luau             37 passed, 0 failed
tests/Progression.spec.luau     66 passed, 0 failed
tests/Pets.spec.luau            75 passed, 0 failed
tests/RunState.spec.luau        75 passed, 0 failed
tests/VaultFloor.spec.luau     215 passed, 0 failed   (+ climbIsFailable: THE JUMP CAN BE MISSED)
tests/responsive.spec.luau      70 passed, 0 failed
tests/Collapse.spec.luau       281 passed, 0 failed   IS THE VAULT WINNABLE AT ALL
tests/Curve.spec.luau           23 passed, 0 failed   IS "DEEPER" ACTUALLY HARDER
tests/Ascent.spec.luau          68 passed, 0 failed   THE PADS CRUMBLE, AND EVERY ONE COMES BACK
tests/Trace.spec.luau           28 passed, 0 failed   the anti-teleport throttle + its BOUNDS
check_vaultrunners.luau        115 passed, 0 failed   (headless boot: builds vaults, plays runs)
check_vaulthud.luau            PASS                   (11 viewports x {hub, mid-run})
walk_vaultrunners.luau         5 floors x 3 runners   (walks the real server, prints outcomes)
measure_curve.luau             the tuning instrument  (where Config.Collapse's numbers came from)
mutate_obby.sh                 the obby's mutation gate (13 mutations + 2 controls)
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
8b. **THE COUNTDOWN IS DERIVED FROM THE VAULT, NOT TYPED INTO IT.** `buildVault` generates the
   vault and only then calls `VaultPath.countdown`, which BFS-walks the maze that was actually
   produced and solves one inequality per storey — the runner must be off storey `s` before the
   plane reaches storey `s`'s kill line — for the countdown, then multiplies by the floor's slack.
   The demand is NOT the bare shortest path: it is the route plus `Config.Collapse.WasteWeight`
   (0.25) times the cells in dead-end branches off it (`VaultPath.wastedCells`), because the
   shortest path cannot see how much maze there is to get lost in and that is what varies between
   two mazes of one floor. See REVIEW-3.md.
   Do not put a `collapseSeconds` back on a tier. v1 did, with the plane's speed as (height) /
   (countdown), so a taller vault swept its LOWER storeys faster: Silver and Gold were unwinnable
   on floor 1 and nothing in the repo measured a traversal time to notice. `Config.Curve`'s
   `MaxCells` / `MaxStoreys` are now a PACING budget — raise either and the derived countdown
   grows with it, which is why `tests/Collapse.spec.luau` bounds it at `Collapse.MaxSeconds`.
8c. **The collapse's head start is in STOREYS** (`Config.Vault.KillPlaneLeadStoreys = 1`), derived
   in `VaultFloor` from `Run.RunnerRootHeight - Run.KillMargin`. Written as a stud offset (-10, as
   v1 had it) storey 0 got 11 studs of plane travel where every storey above it got 18 — the
   ground floor of every vault in the game had 39% less time than the ones above it.
8d. **THE SLACK SCHEDULE IS THE DIFFICULTY CURVE, AND IT MUST NEVER GO FLAT.** The size caps are
   a pacing budget and Gold floor 1 already sits at both of them, so from floor 26 the maze cannot
   grow. v1's slack shed a flat 0.02 a floor to a hard floor of 1.5 and hit it at floor 26 — Gold
   floor 26 and Gold floor 2000 were byte-identical difficulty specs. It is now a power law
   (`MinSlack + (Slack-MinSlack) * (1 + (f-1)/TightenFloors)^-TightenExponent`) which decays toward
   MinSlack and never arrives, so no floor is the last hard one. `tests/Curve.spec.luau` asserts
   STRICT decrease at every floor 1..1000 and a measured completion rate that falls floor by floor;
   both halves are needed, because a schedule can be strictly decreasing by 1e-6 and still flat.
8e. **THE CLIMB IS AN OBBY AND ITS COST IS PAID AT COST, NOT AT SLACK.** The shaft out of every
   storey is six 3x3 pads at `Vault.StepReach` (8) apart — five studs of open air, wider than
   `Movement.RunnerWidth`, so a missed hop is a FALL. v1's treads were 5x5 at a 6-stud reach: one
   stud of slot, and no jump in the game anybody could miss. `tests/VaultFloor.spec.luau`'s
   `climbIsFailable` holds both ends (the gap must be wider than the runner AND inside what
   `VaultPath.jumpReach` says a Roblox jump carries at that rise). A miss costs SECONDS and
   nothing else — no death rule, no lost gems — and the collapse is what spends them.
   The countdown is now `walk * slack + obby`, NOT `(walk + obby) * slack`. Slack exists for what
   nobody can predict (how much maze a blind runner wanders into); the obby's expected cost is a
   number `VaultPath.climbSeconds` computes exactly. Charging it inside the slack was measured at
   52.1% Gold floor-400 completion against a pre-obby 49.1% — **the rage obby made the game
   easier**. At cost it reads 50.3% and REVIEW-3's whole curve survives. See REVIEW-4.md §2.
8f. **`Config.Ascent.ModelMissChance` is a MODEL, and only the budget reads it.** Nothing in the
   running game consults it; it exists so the countdown can pay for the obby's expected cost, the
   way `WasteWeight` pays for the maze's. It is an assumption in the same class as
   `measure_curve.luau`'s blind explorer, and REVIEW-4 sweeps it 0..0.12 rather than defending
   one value. `E[misses] = p * E[attempts]`, NOT `E[attempts] - n` — the first cut was the second
   one and over-priced the shaft by 10%; `tests/Curve.spec.luau` rolls 20000 climbs and never
   reads the closed form, which is how that was caught.
9b. **Every rule in the run loop reads `Trace`, never `hrp.Position`.** The client owns its own
   character's physics, so the position the server reads is a claim. `Trace` moves the server's
   own position toward that claim at walking pace and the gem, exit and kill tests all read the
   trusted one. If you add a rule that reads a player position, read `local_`, not `claimed`.
9c. **A rejected remote must not write to the DataStore.** `flush` compares a fingerprint of
   exactly the fields it saves and returns early when nothing moved; remote handlers call
   `requestSave`, which only marks the profile pending for the flush loop. Do not call `flush`
   from a remote handler.
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

The shaft out of storey `s` lives in that storey's EXIT cell and nowhere else, because the hole in
the floor above is one maze cell wide. `VaultFloor` asserts `StepReach/2 + StepSize/2 <= CellSize/2`
rather than trusting a comment: a pad that pokes through the stairwell wall is a pad a player
reaches from the corridor, and the whole climb is then optional. The pads also come out of
`build` as structured data (`model.shafts[s+1].pads`, whose `y` is the WALKABLE TOP), so the
server's crumble loop, `src/shared/Ascent.luau` and `walk_vaultrunners.luau` all read the same
pads the Parts were built from instead of three copies of the same arithmetic.

You enter storey `s` at maze cell `(0,0)` when `s` is even and `(cells-1, cells-1)` when odd, and
leave from the opposite corner — so **storey s's exit IS storey s+1's entry**, and the stair, the
hole in the floor above, and the arrival cell are the same column by construction. Both corners are
always carved cells in a perfect maze, so this never needs a special case.

The floor of every storey above 0 is FOUR rectangles around a one-cell hole. The first cut used one
solid slab and the spec's first run said *"storey 1 floor covers its own entry hole"* — a beautiful
vault, full of gems, that no player could ever climb out of. That is what `CHECK.climbHoleOpen`
exists for.

Wall cells are run-length merged along X (Bronze floor 1 is 96 parts; the worst floor found by
sweeping all three tiers across 120 floors is Silver floor 42 at 314, against a 1500 budget the
spec asserts). That worst case is **found by a sweep, not sampled**: the spec used to build one
arbitrary late floor, call it "the very worst floor in the game", and print a different floor with
more parts on the next line. Two floors pinned to the same `Config.Curve` caps are the same SIZE
and still merge differently, so a single sample can never be a maximum — `VaultFloor.spec` asserts
that too, by counting the distinct part totals at the caps.

`CHECK.wallsMatchMaze` verifies the merge cell-by-cell in both directions AND that every wall edge
lands on a grid boundary — sampling cell centres alone could not see a run that grew half a cell
at each end, and the mutation gate proved it.

## Known noise

`luau-analyze src/shared/MazeGen.luau` prints type noise about `{{number}}` vs
`{{unknown & unknown}}`. It is **byte-identical to the noise labyrint-spill's own copy produces**
(verified by diff) and is inherited with the verbatim copy.

There is **no `.luaurc` and no Roblox type definitions in this tree**, so `Fx`, `FxClient`,
`Main.server` and `Hud.client` each emit roughly 25 `Unknown global Instance/game/Enum/Color3`
lines. That is environmental, not a defect — but "clean on every file except MazeGen" was never
what the tool actually printed, and `MisleadingAndOr` still surfaces through the noise, which is
how the session-lock and-or was found in the first place. One real line remains and predates this
work: `Main.server(895,85)`, a `never & number` complaint about `p.gems` inside a `string.format`
in `doBuy`'s "poor" branch. It is a narrowing artefact, not a bug.

## What to do next, in order

1. **Play it.** Nobody has. The countdown is derived, `tests/Collapse.spec.luau` proves every floor
   is clearable and `tests/Curve.spec.luau` proves deeper floors are tighter — but the whole slack
   schedule is calibrated against a MODEL of a player (`measure_curve.luau`'s blind explorer:
   perfect memory, no hesitation, no missed jump, no gem detour). It is optimistic by construction,
   so every completion percentage in this repo is a CEILING. Re-run `measure_curve.luau` after a
   playtest and move Slack / MinSlack to what real humans do; do not go back to typing seconds onto
   a tier. Watch for two things in particular: Gold floor 1 is a 264-second run, and
   `Config.Movement.WalkSpeed` is now 24 rather than Roblox's 16 and the server writes it onto the
   Humanoid, so the game feels faster than the brief imagined.
2. **Play the obby.** The decision was to BUILD it rather than retitle the game, and it is built:
   six 3x3 pads with five studs of air between them, crumbling 1.1s after you land. But
   `Config.Ascent.ModelMissChance` (0.04) is a MODEL, not a measurement — it is the one number in
   the obby nobody has checked against a human, and the countdown is priced against it. Re-run
   `measure_curve.luau` §6 after a playtest. Do NOT re-tune the crumble to make the shaft harder
   before somebody has climbed it.
3. Close the rest of the gap between the store description and the build. The two a player will
   actually notice are **pets are bought rather than hatched** and **pets do not level**.
4. Sound. There is not one Sound instance in the game, and a rising collapse with no audio is half
   a collapse.
5. A leaderboard. Runs are already deterministic per (tier, floor), so a time is comparable; only
   the recording is missing.

## What this game deliberately does NOT have

Ship-scope from the brief, held to on purpose: **3 vault tiers, 1 pet rarity, no breeding, no
trading, no eggs.** If a future session is about to add a fourth tier or a second rarity, that is a
scope decision to make explicitly, not a drift.
