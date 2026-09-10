# Vault Runners 💎

A procedural **maze-escape with a crumbling climb**, crossed with a pet collector. Drop into a
freshly generated vault, cross each storey's maze, **leap the six crumbling pads** out of it, and
**get out before it seals** — gems only bank if you escape in time. Bank enough and you unlock a
harder vault and buy Vault-Keeper pets that multiply what you bring out.

> The concept brief calls this a "Procedural Rage-Obby". **It is now partly one.** The climb out
> of every storey is six 3x3 pads with five studs of open air between them, and they crumble a
> beat after you land. A missed hop is a real fall onto a floor the collapse is still rising
> toward. It is not a pure jump-tower — most of the clock is still maze — and the store copy in
> "The store description" below says so. See REVIEW-4.md.

Concept brief: `../docs/game-radar/2026-09-09-roblox-game-radar.md`, "1. Vault Runners".

---

## The loop

1. **Hub.** Three portals (Bronze / Silver / Gold) and a stall of eight Vault-Keeper pets. One
   click on a portal starts a run — no purchase, no prerequisite in front of it.
2. **The vault.** A tower of maze storeys, generated fresh from the world seed for that tier and
   floor number. You enter at one corner of storey 0 and cross the maze to the opposite corner.
3. **The ascent.** The way out of a storey is a shaft of **six 3x3 pads** spiralling the corners
   of that one cell, eight studs apart — **five studs of open air between them**, which is wider
   than the runner, so a missed hop is a fall and not a stumble. Each hop asks for 76% of what a
   Roblox jump actually carries at a 3-stud rise, and **every pad crumbles 1.1s after you first
   stand on it** and comes back 3s later. There is no checkpoint: a miss drops you onto the floor
   you came from and the shaft starts again at pad 1, with the collapse still rising.
   **A missed jump costs SECONDS, and the collapse is what turns seconds into a lost run.**
4. **The collapse.** A kill plane sweeps up from below storey 0 while a seal descends onto the
   exit. Both are driven by one countdown. Below the top storey the collapse is lethal; on the
   top storey the **seal** ends the run.

   **The countdown is DERIVED from the vault, never typed in.** The vault is generated first, then
   `VaultPath` measures what that vault DEMANDS — BFS through each storey's maze, entry cell to
   stair cell, plus the climb, plus a quarter of the cells sitting in dead-end branches off that
   route (`Config.Collapse.WasteWeight`, because a player cannot see the maze from above and a
   6x6 maze varies far more in branch mass than in route length) — and the countdown is that
   demand times a slack factor. It used to be
   three hand-picked numbers (70 / 80 / 90 seconds) with the plane's speed computed as (vault
   height) / (countdown), which meant **adding storeys made the plane rise faster through the
   lower ones**: Silver and Gold were mathematically unwinnable on floor 1 and Bronze died around
   floor 7. `tests/Collapse.spec.luau` now simulates a BFS-optimal runner against the real kill
   plane for every tier across 200 floors, and fails if any of them cannot be cleared with real
   slack to spare.
5. **The exit.** Reach the pad on the top storey **before the countdown expires** and everything
   you are carrying banks, multiplied by your equipped pet. Reach it late, or not at all, and the
   vault keeps the lot.
6. **Back at the hub.** Banked gems buy pets. **Total** gems banked (never the wallet) unlocks the
   next vault, so spending on a pet can never take a vault away. A successful escape advances your
   floor number in that vault. **The slack IS the difficulty curve.** The maze stops growing at
   floor 26 (Gold starts at both size caps), so what changes with depth is how much room over the
   demand you are owed: `slack(f)` decays from 1.85 toward 1.21 as a power law and never arrives,
   so there is no floor at which the next one is not measurably tighter. Modelled completion falls
   98% -> 88% -> 68% -> 50% at floors 1 / 30 / 100 / 400, WITH the crumbling shaft in the run. See
   REVIEW-3.md for how the schedule was derived and REVIEW-4.md for how the obby composes with it.

Floor 1 countdowns as generated today: **Bronze 79s, Silver 165s, Gold 270s.** Across three tiers
and two hundred floors the range is 68s to 273s, and `Config.Collapse.MaxSeconds` (300) is what
holds `Config.Curve`'s size caps down — a bigger cap means a longer run, all of it lost on one
death.

**How much of a vault you can actually take**, walked on the real server by
`walk_vaultrunners.luau` — a greedy nearest-gem runner that climbs the shaft pad by pad and rolls
each hop against `Config.Ascent.ModelMissChance`:

| tier / floor | countdown | took | banked / on the floor | falls |
|---|---|---|---|---|
| bronze 1 | 79s | 59.6s | 36 / 48 | 0 |
| gold 1 | 270s | 219.1s | 506 / 660 | 2 |
| gold 30 | 227s | 200.0s | 726 / 990 | 1 |
| gold 100 | 184s | 159.2s | 594 / 990 | 0 |
| gold 400 | 189s | 181.9s | 638 / 990 | 4 |

Nothing but the first Bronze floor can be emptied, so from there the game is a **choice about what
to leave behind**, which is the intended shape. The same file also walks a FUMBLER — the same
runner, but it misses the top hop of every shaft once — and that runner is **killed by the
collapse on Bronze floor 1 and on Gold floor 400**. That is the obby doing its job: it does not
kill you, it costs you seconds, and the collapse spends them. It is measured, not playtested, and
`tests/Collapse.spec.luau` only guarantees the weaker thing: one gem per storey always fits.

Everything is saved to a DataStore: gems, lifetime banked, pets owned, the pet equipped, and the
floor you have reached in each of the three vaults.

## Layout

```
vault-runners/
  default.project.json          rojo: src/server -> ServerScriptService
                                      src/client -> StarterPlayerScripts
                                      src/shared -> ReplicatedStorage
  src/shared/Config.luau        EVERY tunable, one table
  src/shared/VaultFloor.luau    the vault geometry, PURE
  src/shared/VaultPath.luau     how long the vault takes to walk -> the countdown, PURE
  src/shared/Ascent.luau        which pads of the climb shaft are THERE right now, PURE
  src/shared/Trace.luau         the server's own position for the runner, PURE
  src/shared/RunState.luau      the banking rule, PURE
  src/shared/Progression.luau   unlocks + the floor curve, PURE
  src/shared/Pets.luau          the stall, PURE
  src/shared/MazeGen.luau       labyrint-spill's maze generator, copied VERBATIM
  src/shared/Rng.luau           deterministic LCG (+ NextInteger, so MazeGen runs in the CLI)
  src/shared/Fx.luau            visual kit, copied from a sibling game
  src/shared/FxClient.luau      camera/HUD juice, copied
  src/shared/Responsive.luau    HUD sizing rules, copied
  src/server/Main.server.luau   authoritative: the world, the run loop, the DataStore
  src/client/Hud.client.luau    display only, phone-first
  tests/*.spec.luau             one per pure module
  check_vaultrunners.luau       headless boot: builds vaults and plays runs, walking not warping
  check_vaulthud.luau           headless HUD fit, 11 viewports x {hub, mid-run}
  walk_vaultrunners.luau        plays the real server: SOLVER / GRABBER / FUMBLER, pad by pad
  measure_curve.luau            the tuning instrument (where Config.Collapse's numbers came from)
  mutate_obby.sh                the obby's mutation gate — 13 mutations + 2 controls
```

**Pure logic lives in `src/shared` and takes its dependencies as ARGUMENTS.** Nothing in
`src/shared` requires anything: a bare `require("./X")` resolves in the luau CLI and is invalid in
Roblox, and that exact mistake has made a server in this repo fail to load while every unit test
stayed green. Only the server and client scripts require, and they do it from ReplicatedStorage.

## Running the tests

Every spec runs in the luau CLI with no Roblox present.

```
cd vault-runners
luau tests/Rng.spec.luau            #  37 passed, 0 failed
luau tests/Progression.spec.luau    #  66 passed, 0 failed
luau tests/Pets.spec.luau           #  75 passed, 0 failed
luau tests/RunState.spec.luau       #  75 passed, 0 failed
luau tests/VaultFloor.spec.luau     # 215 passed, 0 failed
luau tests/responsive.spec.luau     #  70 passed, 0 failed
luau tests/Collapse.spec.luau       # 281 passed, 0 failed   IS THE VAULT WINNABLE AT ALL
luau tests/Curve.spec.luau          #  23 passed, 0 failed   IS "DEEPER" ACTUALLY HARDER
luau tests/Ascent.spec.luau         #  68 passed, 0 failed   THE PADS CRUMBLE, AND COME BACK
luau tests/Trace.spec.luau          #  28 passed, 0 failed   the anti-teleport throttle
```

Then the headless boot, which runs the REAL server script inside `robloxemu`:

```
cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
cd ../vault-runners
luau check_vaultrunners.luau        # 115 passed, 0 failed
luau check_vaulthud.luau            # PASS - fits every viewport checked
```

`check_vaultrunners.luau` asks the workspace how many parts arrived (112 for Bronze floor 1),
**walks** onto gems, escapes in time, gets sealed in, gets caught by the collapse, buys a pet from
a pedestal, proves a rejected remote costs the DataStore nothing, proves leaving releases the
session lock, and leaves mid-run. An unparented Instance raises nothing and is invisible to unit
tests; this is the file that would notice.

It **walks** rather than teleporting, and that is not a detail. Every earlier version proved an
escape by writing the root part straight onto the ExitPad — which is exactly the exploit an
adversarial review found in the game itself, so the gate was demonstrating the cheat and scoring
it a pass. The server now keeps its own trusted position (`src/shared/Trace.luau`) and every rule
reads that, so the check has to move at a speed a runner actually has.

Syntax and types:

```
luau-compile --binary <file>        # every src file compiles
luau-analyze <file> 2>&1            # clean, except MazeGen (see CLAUDE.md)
```

## What is NOT built yet

Honest list. The concept brief and the paste-ready store description promise some of these.

- **The obby exists now, but it is not the whole game.** REVIEW.md's finding 7 said there was no
  obby at all: a flat maze walk plus a six-step staircase whose treads were one stud apart, with
  no jump in the game a player could fail. That is fixed — the climb out of every storey is six
  3x3 pads eight studs apart with five studs of open air between them, and every pad crumbles
  1.1s after you stand on it (REVIEW-4.md). What is still true is the PROPORTION: on Gold floor 1
  the maze is about 110 seconds of the run and the four shafts are about 26, so "ROBLOX RAGE
  OBBY" as a genre line still oversells it. The proposed store copy under "The store description"
  below leads with the collapse and names the crumbling pads without claiming the game is a jump
  tower. The brief's thumbnail — "a player mid-air leaping between two crumbling stone
  platforms" — is now accurate.

- **Pets are bought, not hatched.** The description says "HATCH rare Vault-Keeper PETS" and the
  brief's own scope line says no eggs in v1. You click a pedestal and pay gems. There is no egg,
  no hatch animation, and no randomness in what you get.
- **No pet levels and no squad.** The description says "Collect & level up your pet squad". You
  own as many as you buy but you equip exactly ONE, and it never levels. `Pets.multiplier` reads
  the equipped pet only.
- **No run-boosts.** The brief's core loop mentions buying run-boosts at the hub alongside pets.
  Not built; the stall sells pets and nothing else.
- **The seal is visual, not physical.** The descending slab over the exit does not collide. It is
  a countdown you can see; the rule that ends the run is the timer in `RunState`.
- **Dying is a teleport, not a death.** Getting caught by the collapse moves you back to the hub
  with a toast and a screen shake. There is no ragdoll, no death animation, and no respawn wait.
- **No leaderboard.** Runs are deterministic per (tier, floor) and times would be comparable, but
  nothing records or displays them.
- **No sound.** Not one Sound instance in the game.
- **No "give up" button.** Once you are in a vault the only ways out are the exit and the
  collapse.
- **The anti-cheat is a throttle, not a wall.** `Trace` moves the server's trusted position toward
  the client's claim no faster than a runner moves, so teleporting to the exit no longer banks
  anything instantly. It does **not** test walls: a flier still gets the straight-line route
  instead of the maze route, at walking pace. That is a real remaining advantage, bounded by speed
  rather than removed. Closing it needs a walkability test against the storey's grid, which risks
  throttling honest players who cut corners and was left out on purpose.
  **It does not stop a lying client skipping the obby either**, and that is measured rather than
  hoped: standing still banks enough upward allowance to move 25 studs in one tick, and a climb
  shaft is 18. A cheating client climbs a whole vault in 8.65s of trusted time against an honest
  26.13s — 3.02x. That ratio was 2.50x before the obby (the honest climb got slower, the tolerance
  did not). The obby's difficulty has never rested on `Trace`: it rests on five studs of open air
  and on physics the server does not own. `tests/Trace.spec.luau` prints the number every run.
- **Gold is a long run.** Gold floor 1 is a 6x6 maze over five storeys and its derived countdown is
  270 seconds. That number is measured rather than guessed, and it is deliberately under
  `Config.Collapse.MaxSeconds` — but four minutes with total loss on a single death is a pacing
  call nobody has playtested.
- **Never played by a person.** Everything below has been verified headless and by unit test. The
  countdown is no longer a guess — it is derived from the vault the generator actually produced,
  `tests/Collapse.spec.luau` proves every floor is clearable and `tests/Curve.spec.luau` proves
  deeper floors are harder — but the slack schedule is calibrated against a MODEL of a player (a
  blind explorer with perfect memory and no hesitation, `measure_curve.luau`), which is optimistic
  by construction. Every completion percentage in this repo is an upper bound on the real one, and
  a playtest is what turns the model's floor-400 50% into a number about human beings.
- **Nobody knows how often a real player misses a hop.** `Config.Ascent.ModelMissChance` is 0.04
  and it is an ASSUMPTION, not a measurement — it exists only so the countdown can pay for the
  obby's expected cost. REVIEW-4 sweeps it from 0 to 0.12 and the curve stays monotone at every
  value, but the shipped number is the single thing about the obby a playtest would move.
- **Not published.** No Roblox experience exists for this; nothing here has been uploaded.

## The store description

`docs/marketing/store-text.json` is the live text for the four PUBLISHED games and Vault Runners
is not one of them, so this is the PROPOSAL, kept here until there is a place to paste it.

```
🏆 VAULT RUNNERS 🏆 CRUMBLING OBBY meets PET COLLECTOR! 💎

Race up a COLLAPSING VAULT before it seals forever! Every floor is a new procedural maze
tower — grab GEMS, then LEAP the crumbling pads out of every storey while the collapse
rises underneath you. Miss a jump and it is still rising.

⭐ FEATURES ⭐
💎 Bank gems to BUY rare Vault-Keeper PETS
🧱 Endless PROCEDURALLY-GENERATED vault towers
🧗 SIX CRUMBLING PADS out of every storey — one miss and you fall
🔥 Gems bank ONLY if you get out before the seal
📈 Every floor deeper is measurably tighter
💾 Progress auto-SAVES — come back stronger

Love obby towers AND pet-collecting games? This is your new obsession.

👍 LIKE + ⭐ FAVORITE to help the Vault grow!
```

**What changed from the brief's paste-ready copy, and why.** Every line below was checked against
what the build now does, not against what it was meant to do.

| the brief's line | verdict | what it says now |
|---|---|---|
| "ROBLOX RAGE OBBY meets PET COLLECTOR" | **overstated** — the obby is real now, but on Gold floor 1 it is ~26s of a ~150s run; the rest is maze | "CRUMBLING OBBY meets PET COLLECTOR" |
| "Every run is a brand-new PROCEDURAL OBBY tower" | **false** — vaults are deterministic per (tier, floor), so a floor you die on is the same vault next attempt. That is deliberate: it is what makes a time comparable | "Every floor is a new procedural maze tower" |
| "dodge the closing walls" | **false** — nothing closes in. The seal over the exit does not even collide; the hazard is a rising kill plane | "while the collapse rises underneath you" |
| "Bank gems to HATCH rare Vault-Keeper PETS" | **false** — you click a pedestal and pay. No egg, no hatch, no randomness | "Bank gems to BUY rare Vault-Keeper PETS" |
| "Vault SEALS FAST — pure rage-obby tension" | **overstated** — countdowns run 68s to 273s; Gold floor 1 is four and a half minutes | "Gems bank ONLY if you get out before the seal" |
| "Collect & level up your pet squad" | **false** — eight pets, you own what you buy, you equip exactly ONE, and it never levels | dropped; the BUY line covers it |
| "Endless PROCEDURALLY-GENERATED climbing towers" | true, kept | "Endless PROCEDURALLY-GENERATED vault towers" |
| "Harder floor tiers unlock as you climb" | true, and now measurable | "Every floor deeper is measurably tighter" |
| "Progress auto-SAVES" | true, kept | unchanged |
| "Love jump-tower obbies AND egg/pet-collecting games?" | **false** — there are no eggs | "Love obby towers AND pet-collecting games?" |
| "new floors & pets added weekly" | **an unkeepable promise** on an unpublished game with nobody rostered to it | dropped |

The one line that got *stronger* is the obby: "SIX CRUMBLING PADS out of every storey — one miss
and you fall" is now a literal description of `Config.Vault.StepReach` and `Config.Ascent`, held
by `tests/VaultFloor.spec.luau`'s `climbIsFailable` and `tests/Ascent.spec.luau`. The brief's
thumbnail concept — a player mid-air between two crumbling stone platforms — is what the game
actually looks like now.
