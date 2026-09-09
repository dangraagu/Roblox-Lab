# Vault Runners 💎

A procedural rage-obby crossed with a pet collector. Drop into a freshly generated vault, climb it
grabbing gems while a collapse rises underneath you, and **get out before it seals** — gems only
bank if you escape in time. Bank enough and you unlock a harder vault and buy Vault-Keeper pets
that multiply what you bring out.

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
4. **The exit.** Reach the pad on the top storey **before the countdown expires** and everything
   you are carrying banks, multiplied by your equipped pet. Reach it late, or not at all, and the
   vault keeps the lot.
5. **Back at the hub.** Banked gems buy pets. **Total** gems banked (never the wallet) unlocks the
   next vault, so spending on a pet can never take a vault away. A successful escape advances your
   floor number in that vault; the next floor is a bigger maze and a shorter countdown.

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
  check_vaultrunners.luau       headless boot: builds a vault and plays five runs
  check_vaulthud.luau           headless HUD fit across ten viewports
```

**Pure logic lives in `src/shared` and takes its dependencies as ARGUMENTS.** Nothing in
`src/shared` requires anything: a bare `require("./X")` resolves in the luau CLI and is invalid in
Roblox, and that exact mistake has made a server in this repo fail to load while every unit test
stayed green. Only the server and client scripts require, and they do it from ReplicatedStorage.

## Running the tests

Every spec runs in the luau CLI with no Roblox present.

```
cd vault-runners
luau tests/Rng.spec.luau            # 37 passed, 0 failed
luau tests/Progression.spec.luau    # 63 passed, 0 failed
luau tests/Pets.spec.luau           # 75 passed, 0 failed
luau tests/RunState.spec.luau       # 75 passed, 0 failed
luau tests/VaultFloor.spec.luau     # 199 passed, 0 failed
luau tests/responsive.spec.luau     # 70 passed, 0 failed
```

Then the headless boot, which runs the REAL server script inside `robloxemu`:

```
cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
cd ../vault-runners
luau check_vaultrunners.luau        # 71 passed, 0 failed
luau check_vaulthud.luau            # PASS - fits every viewport checked
```

`check_vaultrunners.luau` asks the workspace how many parts arrived (112 for Bronze floor 1),
walks onto gems, escapes in time, gets sealed in, gets caught by the collapse, buys a pet from a
pedestal, and leaves mid-run. An unparented Instance raises nothing and is invisible to unit
tests; this is the file that would notice.

Syntax and types:

```
luau-compile --binary <file>        # every src file compiles
luau-analyze <file> 2>&1            # clean, except MazeGen (see CLAUDE.md)
```

## What is NOT built yet

Honest list. The concept brief and the paste-ready store description promise some of these.

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
- **Never played by a person.** Everything below has been verified headless and by unit test. The
  70-second Bronze countdown against a 3-storey 4x4 maze is a guess at a difficulty curve, not a
  measured one, and the first thing a real playtest should re-tune.
- **Not published.** No Roblox experience exists for this; nothing here has been uploaded.
