# Vault Runners — context for a fresh session

## State

v1 is **built and green, and has never been run by a person or published.** No Roblox experience
exists for it and no `publish_*.bat` exists. The eye candy was committed as 511793d (2026-09-24);
everything REVIEW-5 changed (2026-09-30) is in the working tree, NOT committed.

**Complete against docs/complete-game-standard.md as far as code can take it (pass 2, 2026-10-01,
EYECANDY.md §15), in the working tree, NOT committed.** Pass 2 finished the highscore board (the
DEEPEST ESCAPES sign west of the hub spawn: public top 10 or friends, invariant 15) against the check
an interrupted pass had left red, fixed that WIP's tie bug (`bestAt` is now stamped when the server
banks a new deepest escape), and closed four more gaps of the standard, each test first: the owner
token is per SESSION, not the server's JobId (invariant 9d); every player's `RespawnLocation` is the hub
spawn (invariant 16); a shutdown saves and releases every profile (`BindToClose`, invariant 18); the
store text is rewritten and gated (`check_store_text.py`). It also found a gap the reviewer had not
listed: the standard asks every band for its own CRITTERS, and the strata had none; now each has its
own (invariant 19). `MARKETING.md` has the clip list. The seed is deliberately NOT salted, and
invariant 17 says why. What is left is Studio and people: nobody has
played it, seen it, or seen the board (EYECANDY.md §8).

**The eye candy (owner's brief 2026-09-17) is built and green, through two adversarial reviews
(EYECANDY.md §12 and §13, all findings closed), and NOT yet seen in Studio: read `EYECANDY.md`
first.** Five strata by depth, and past depth 44 the Volcano Temple turns through three halls (owner
decision 2026-09-30); rare ceiling drops; rest in the hub; all client-side. The client's budgets are
CAPS in code (`VaultArt.enforceBudget`), not just numbers the checks compare against.

Five review passes so far, and they supersede each other — read them newest first.
`REVIEW-5.md` closes the obby review (`docs/reviews/2026-09-10-vault-runners-obby.md`: hop 1 is no
longer priced as missable, the shaft is watched at 20 Hz with a derived stand box) and the second
eye-candy review, and records the owner's three decisions. Its §6 is the pass-1 re-run of
2026-10-01: every finding reproduced on HEAD 511793d and measured fixed, the sweep re-run (39 of 40
killed, 6 of 6 controls survive), and one thing the gem rule does not cover (a crumbling pad under a
Bronze runner, invariant 12).
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
tests/VaultFloor.spec.luau     231 passed, 0 failed   (+ climbIsFailable, firstHopIsAStep: WHICH HOPS CAN BE MISSED)
tests/responsive.spec.luau      70 passed, 0 failed
tests/Collapse.spec.luau       282 passed, 0 failed   IS THE VAULT WINNABLE AT ALL (3 tiers x 800 floors)
tests/Curve.spec.luau           29 passed, 0 failed   IS "DEEPER" ACTUALLY HARDER; the rolled climb and a rolled miss
tests/Ascent.spec.luau          77 passed, 0 failed   THE PADS CRUMBLE, EVERY ONE COMES BACK, the stand box is derived
tests/Trace.spec.luau           28 passed, 0 failed   the anti-teleport throttle + its BOUNDS
tests/EnvBands.spec.luau       124 passed, 0 failed   (the eye candy, EYECANDY.md, from here...)
tests/Rest.spec.luau            55 passed, 0 failed
tests/Hazards.spec.luau         91 passed, 0 failed
tests/VaultEnv.spec.luau       171 passed, 0 failed   (+ critters: placed from (storey, cell, seed) only, never in a wall)
tests/EnvConfig.spec.luau      432 passed, 0 failed   THE PADS, GEMS AND RING STAY READABLE; gems never the pads' colour; critters neither
tests/Pacing.spec.luau          51 passed, 0 failed   (...to here) the brag at 30-45 min; the halls turn
tests/Board.spec.luau           69 passed, 0 failed   the board's pure rules: stored value, ties, views, cache, limiter
check_vaultrunners.luau        157 passed, 0 failed   (headless boot: builds vaults, plays runs; owner token, RespawnLocation, rejoin, sparse keys, shutdown)
check_vaulthud.luau            PASS                   (11 viewports x {hub, mid-run}, HUD + Vault.client)
../robloxemu/check_vaultrunners_env.luau      340 passed, 0 failed   the strata, real client + server; §4b each stratum's critters
../robloxemu/check_vaultrunners_hazards.luau   50 passed, 0 failed   the drops (emulator Random unseeded)
../robloxemu/check_vaultrunners_shaft.luau     63 passed, 0 failed   the shaft stays readable; the server sees a chained hopper
../robloxemu/check_vaultrunners_cards.luau     20 passed, 0 failed   returning player's cards; forced guards
../robloxemu/check_vaultrunners_static.luau   100 passed, 0 failed   compiles; no remote, no attribute (Vault.client AND Board.client); Config's obby comment
../robloxemu/check_vaultrunners_readable.luau  50 passed, 0 failed   gems, exit, drop ring readable; not the pads' colour
../robloxemu/check_vaultrunners_budget.luau    17 passed, 0 failed   every Config.Budget is a CAP (forced demand + budgets); critters yield first
../robloxemu/check_vaultrunners_halls.luau     68 passed, 0 failed   the Volcano Temple's halls, through the real client
../robloxemu/check_vaultrunners_board.luau     90 passed, 0 failed   the board, public + friends, through the real server and Board.client
py -3 check_store_text.py      10 passed, 0 failed    the store description: <= 1000 chars, no coloured squares, no false brief claims
walk_vaultrunners.luau         5 floors x 3 runners   (walks the real server, prints outcomes)
measure_curve.luau             the tuning instrument  (where Config.Collapse's numbers came from)
mutate_obby.sh                 the obby's mutation gate (21 mutations: 20 killed, 1 disclosed; 2 controls survive; RUN IT ON A SCRATCH COPY)
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
   one and over-priced the shaft by 10%; `tests/Curve.spec.luau` rolls 80000 climbs and never
   reads the closed form, which is how that was caught. `ModelMissChance` outside [0, 1) is refused
   by name (at 1 the closed form divided by zero).
8g. **HOP 1 IS A STEP, NOT A HOP** (REVIEW-5 §1.1). It leaves from the storey floor and the floor
   under pad 1 is solid, so it cannot be missed: `VaultPath.failableHops` is pads - 1, and
   `VaultFloor.spec`'s `firstHopIsAStep` holds the geometry that makes it so. Pricing all six hops
   as missable cost 0.087 s per transition, and the 2% tolerance of the old rolled climb could not
   see it; the roll is now 80000 climbs at 0.5%, plus a rolled MISS at 1%.
8h. **THE SERVER WATCHES THE SHAFT AT 20 Hz** (`Config.Ascent.SampleSeconds`, REVIEW-5 §1.3).
   `watchRunner` steps `Trace`, touches the pad under the trusted position and draws the flips every
   0.05 s; `tickRun` judges gems, exit, collapse and seal every `Run.TickSeconds` (0.2) against the
   position `watchRunner` left in `a.trusted`. At 0.2 s the server never counted 18 of 48 chained
   landings (`check_vaultrunners_shaft` §6). `StandRadius` is DERIVED (pad half-width + runner
   half-width = 2.5), never typed.
9b. **Every rule in the run loop reads `Trace`, never `hrp.Position`.** The client owns its own
   character's physics, so the position the server reads is a claim. `Trace` moves the server's
   own position toward that claim at walking pace and the gem, exit and kill tests all read the
   trusted one. If you add a rule that reads a player position, read `local_`, not `claimed`.
9c. **A rejected remote must not write to the DataStore.** `flush` compares a fingerprint of
   exactly the fields it saves and returns early when nothing moved; remote handlers call
   `requestSave`, which only marks the profile pending for the flush loop. Do not call `flush`
   from a remote handler.
9d. **THE OWNER TOKEN IS PER SESSION** (docs/complete-game-standard.md §1, fork-tower's
   `old.session`). The load that takes the record writes a fresh `HttpService:GenerateGUID` as
   `session`, and `flush` writes only while the record still carries it; a lost record sets
   `canSave = false`, warns once and tells the player. `jobId` + `lockUntil` still decide whether a
   LOAD may take the record. The token used to be `game.JobId`, which every session on one server
   shares, and `flush` wrote whenever the record's jobId was nil or its lock had run out: the lock is
   renewed only by a write, so an idle player in the hub had an expired lock after two minutes, and a
   newer session's data could be written over (`check_vaultrunners`, "the OWNER TOKEN is per session").
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
12. **The eye candy is CLIENT-ONLY and never touches a rule** (EYECANDY.md §5). `Vault.client` writes
    only `Color` and `Reflectance` on the server's vault parts (never Material, Size, CFrame,
    collision, Transparency or an attribute), fires no remote, and reads only its own vault. Rest is
    the HUB: it must never be offered, or honoured, inside a run, because a run is a timed round the
    collapse must be allowed to finish. A ceiling drop must never start in the climb shaft, on a pad,
    next to the hole, in a run's first 12 s or last 15 s, or with the collapse within half a storey
    (`VaultEnv.hazardEligible`), and nothing may shake the camera of a runner in the shaft.
    **The pad's look follows the SERVER's pad** (`VaultEnv.padLook`): a crack is held at full until
    the server's drop arrives. Never end it on the client's own clock; that painted a pad WHOLE a beat
    (plus ping) before it fell. **What a runner must find must read in every stratum**: gems and the
    exit pad wear `VaultEnv.gem`, and the drop's ring `VaultEnv.ring`. Any new stratum palette is
    checked by `EnvConfig.spec` against those bars (review round, EYECANDY.md §12). **...and a gem is
    never the pads' colour**: `Env.MinGemPadDistance` (80, RGB) is part of the gem rule (§13). That
    rule is about the RESTING pad. A crumbling pad is pulled 70 % of the way to the shared `crack`
    colour (255, 90, 50), an orange red, so under a BRONZE runner (orange gems) it comes within 44.6
    RGB of the gem in the Bank Vault and ends 60.9-70.5 away in the reactor, Frozen Vault and volcano
    (Silver and Gold stay 81.5+ away; REVIEW-5 §6). Only the pad under the runner's own feet, only
    while it goes. It is on the Studio list (EYECANDY.md §8.6), not "fixed": a crack colour dark
    enough to keep the bank's path 80 away reads under the 2:1 bar on the bank's dark green floor.
13. **Every `Config.Budget` is a CAP in code** (EYECANDY.md §13). Parts go through
    `VaultArt._parent` (counted), props are hung only inside `MaxLocalParts` less the headroom, and
    `VaultArt.enforceBudget` runs LAST in every client frame: decoration yields first, emitters are
    granted by priority (the drop's trickle first), lights and beams are capped. An emitter never
    writes its own Rate or Enabled: it calls `_want`. `check_vaultrunners_budget` forces the demand
    and the budgets in memory and measures every frame. `MaxHazards` (1) is the one budget no code
    reads: the cap is structural (`Hazards` has a single `state.active` slot, `Hazards.spec` holds
    "never more than one drop at a time"), and `EnvConfig.spec` pins the number to it.
14. **The endgame turns** (owner decision 2026-09-30). Past `Env.Halls.from` (depth 44) the deepest
    stratum moves through `Env.Halls.list` every `every` (4) depths, for ever. A hall may change the
    light, the weather and the props, NEVER the palette: every readability bar holds in every hall
    because the pads, gems and floor are the stratum's own.
15. **The board ranks the DEEPEST VAULT ESCAPED, and only the server moves it** (Config.Board,
   `src/shared/Board.luau`, docs/complete-game-standard.md §3). The metric is
   `VaultEnv.deepestCleared(p.floors)`; `floors` moves only in `finishRun` when `RunState.tryEscape`
   banks a run judged on `Trace`, and no remote carries a depth, a floor or a time. Stored in the
   OrderedDataStore `Config.Save.Board`, key `u_<userId>`, value `depth * 2e9 + (2e9 - bestAt)`;
   `bestAt` is stamped in `finishRun` only when the escape is DEEPER than any before (never on a
   shallower one, never at the board write), saved with the floors, and offered to the board after the
   profile write lands and again at every join, through `UpdateAsync` + `Board.keepHigher` (a tie keeps
   the first reach time, the board is never lowered). Public: one `GetSortedAsync(false, 10)` per
   `PublicCacheSeconds` while anyone is here; a failed read keeps the last list. Friends: only when the
   prompt asks, `GetFriendsAsync` to `FriendsCap` (200), cached per player, reads cached and throttled
   (`Board.newLimiter` and Roblox's budget), players in this server from memory. Names from the server,
   the friends list or `GetNameFromUserIdAsync`, cached in memory, never stored. The sign is drawn by
   `Board.client` on the part (never in PlayerGui: the HUD fit check would measure it as screen), per
   player, and remounted if the part streams back in. Do not put a RUN TIME on this board: nothing
   records one, and a run time would need its own anti-cheat thinking.
16. **Every player's `RespawnLocation` is the hub spawn**, set in `onPlayerAdded` before the profile
   load yields (SPAWN-ORDER.md §3's preferred pattern). The world still holds exactly one enabled
   SpawnLocation; both are asserted in `check_vaultrunners`' "WHERE THE ENGINE PUTS YOU".
17. **`Config.WorldSeed` is NOT salted, on purpose** (docs/complete-game-standard.md §1 asks for a
   server-only salt on a seed a player could memorise; this is the written reason why not). A salt
   would hide nothing: every wall, gem and pad of a vault is a replicated Part the moment the run
   starts, so a script reads the maze off the workspace whatever the seed (the standard's own note:
   a salt on a seed that drives visible geometry is not enough). And remembering a floor is the design:
   a wiped floor is the SAME floor next attempt, like an obby course, and a depth on the board means the
   same thing for everyone only because every runner faced the same vaults. What a script cannot do is
   go faster than a runner: `Trace` and the countdown are the wall, and the board's metric needs no
   secret.
18. **A shutdown saves every profile** (`game:BindToClose`, `flush(plr, true)` for each): a purchase
   pending on the flush tick and the lock release would otherwise be lost when Roblox closes the server.
   Still through the owner token, so a late shutdown write never lands over a newer session.
19. **Every stratum has its own CRITTERS, and they are decoration** (docs/complete-game-standard.md
   §2; `Config.Env.Bands[*].critters`, `VaultEnv.critterSites/critterNear/critterOffset`,
   `VaultArt.updateCritters`). Client-only, inert, never Neon. Placed like props, from (storey, cell,
   floor seed) ONLY: a critter lives inside ONE maze cell (a cell centre is always open) and never reads
   the walls, so it cannot point at the route. Never in the shaft cell or over the hole. At most
   `Budget.MaxCritters`, within `CritterReach` cells of the runner; they yield FIRST (before props)
   when the parts budget is tight. A critter's body colour stays `MinGemPadDistance` from every gem
   and pad on its floor (`EnvConfig.spec`). A new stratum needs a critter kind VaultArt can draw.

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
   a tier. Watch for two things in particular: Gold floor 1 is a 269-second run, and
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
5. **See the board and the critters in Studio** (EYECANDY.md §8.19-22): with API access off the board says it is offline,
   which is correct; its rows, the prompt and the Friends toggle can only be seen on a published place
   (never film the Friends view with a real account). And whether the place streams: Board.client and
   Vault.client are written to survive it, but nobody has watched.
6. **Publishing** (night shift only): create the universe, a git-ignored `publish_*.bat`, the
   content-maturity questionnaire, then `MARKETING.md`'s clips and EYECANDY.md §9's thumbnails.
7. **An independent review of pass 2.** The board, the owner token, the shutdown and the critters were
   written and mutation-tested by one writer pass (EYECANDY.md §15); no reviewer has read them.

## What this game deliberately does NOT have

Ship-scope from the brief, held to on purpose: **3 vault tiers, 1 pet rarity, no breeding, no
trading, no eggs.** If a future session is about to add a fourth tier or a second rarity, that is a
scope decision to make explicitly, not a drift.
