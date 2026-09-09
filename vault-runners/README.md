# Vault Runners 💎

A procedural **maze-escape** crossed with a pet collector. Drop into a freshly generated vault,
climb it grabbing gems while a collapse rises underneath you, and **get out before it seals** —
gems only bank if you escape in time. Bank enough and you unlock a harder vault and buy
Vault-Keeper pets that multiply what you bring out.

> The concept brief calls this a "Procedural Rage-Obby". **It is not one, and it never was.** See
> the first entry under "What is NOT built yet".

Concept brief: `../docs/game-radar/2026-09-09-roblox-game-radar.md`, "1. Vault Runners".

---

## The loop

1. **Hub.** Three portals (Bronze / Silver / Gold) and a stall of eight Vault-Keeper pets. One
   click on a portal starts a run — no purchase, no prerequisite in front of it.
2. **The vault.** A tower of maze storeys, generated fresh from the world seed for that tier and
   floor number. You enter at one corner of storey 0 and climb a spiral of steps at the opposite
   corner, through a hole in the floor above, into the next storey's maze.
3. **The collapse.** A kill plane sweeps up from below storey 0 while a seal descends onto the
   exit. Both are driven by one countdown. Below the top storey the collapse is lethal; on the
   top storey the **seal** ends the run.

   **The countdown is DERIVED from the vault, never typed in.** The vault is generated first, then
   `VaultPath` walks its shortest possible route — BFS through each storey's maze, entry cell to
   stair cell, plus the climb — and the countdown is that time times a slack factor. It used to be
   three hand-picked numbers (70 / 80 / 90 seconds) with the plane's speed computed as (vault
   height) / (countdown), which meant **adding storeys made the plane rise faster through the
   lower ones**: Silver and Gold were mathematically unwinnable on floor 1 and Bronze died around
   floor 7. `tests/Collapse.spec.luau` now simulates a BFS-optimal runner against the real kill
   plane for every tier across 200 floors, and fails if any of them cannot be cleared with real
   slack to spare.
4. **The exit.** Reach the pad on the top storey **before the countdown expires** and everything
   you are carrying banks, multiplied by your equipped pet. Reach it late, or not at all, and the
   vault keeps the lot.
5. **Back at the hub.** Banked gems buy pets. **Total** gems banked (never the wallet) unlocks the
   next vault, so spending on a pet can never take a vault away. A successful escape advances your
   floor number in that vault; the next floor is a bigger maze with **less slack over the optimal
   route** — the countdown itself still grows with the maze, because it is measured from it.

Floor 1 countdowns as generated today: **Bronze 78s, Silver 165s, Gold 258s.** Across three tiers
and two hundred floors the range is 63s to 258s, and `Config.Collapse.MaxSeconds` (300) is what
holds `Config.Curve`'s size caps down — a bigger cap means a longer run, all of it lost on one
death.

**How much of a vault you can actually take**, measured with a greedy nearest-gem tour (a very
good player, not a perfect one): Bronze floor 1 clears all 12 gems in 72.8s of its 78s and Silver
floor 1 all 20 in 154.2s of 165s, so the first floor of each tier can be emptied. Nothing deeper
can: Bronze floor 10 needs 120.8s of a 93s countdown for its 15 gems, and Gold floor 1 misses a
full clear by nine seconds (267.6s of 258s). From there on the game is a **choice about what to
leave behind**, which is the intended shape — but it is measured, not playtested, and
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
luau tests/Progression.spec.luau    #  64 passed, 0 failed
luau tests/Pets.spec.luau           #  75 passed, 0 failed
luau tests/RunState.spec.luau       #  75 passed, 0 failed
luau tests/VaultFloor.spec.luau     # 201 passed, 0 failed
luau tests/responsive.spec.luau     #  70 passed, 0 failed
luau tests/Collapse.spec.luau       # 274 passed, 0 failed   IS THE VAULT WINNABLE AT ALL
luau tests/Trace.spec.luau          #  23 passed, 0 failed   the anti-teleport throttle
```

Then the headless boot, which runs the REAL server script inside `robloxemu`:

```
cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
cd ../vault-runners
luau check_vaultrunners.luau        # 107 passed, 0 failed
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

- **THERE IS NO OBBY.** This is the biggest gap in the list and the one a player meets first. The
  brief's genre line is "Procedural Rage-Obby", its thumbnail concept is "a player mid-air leaping
  between two crumbling stone platforms", and the store copy leads with "ROBLOX RAGE OBBY" and
  "Endless PROCEDURALLY-GENERATED climbing towers". What is built is a **flat maze walk per storey
  plus one six-step spiral staircase in a single corner cell**. Nothing crumbles, there are no
  platforms to miss, and there is no jump in the whole game a player can fail: the treads rise 3
  studs each and the top one lands flush with the floor above. A player arriving from "rage obby"
  finds a maze runner. Either the platforming gets built or the genre line, the thumbnail and the
  store copy get rewritten — and until one of those happens, this paragraph is the only honest
  thing in the repo about it.

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
- **Gold is a long run.** Gold floor 1 is a 6x6 maze over five storeys and its derived countdown is
  258 seconds. That number is measured rather than guessed, and it is deliberately under
  `Config.Collapse.MaxSeconds` — but four minutes with total loss on a single death is a pacing
  call nobody has playtested.
- **Never played by a person.** Everything below has been verified headless and by unit test. The
  countdown is no longer a guess — it is derived from the vault's own BFS-optimal route and
  `tests/Collapse.spec.luau` proves every generated floor is clearable — but
  `Config.Collapse.Slack`, how much room over that route a real human needs, is still a judgement
  call and it is the first thing a real playtest should re-tune.
- **Not published.** No Roblox experience exists for this; nothing here has been uploaded.
