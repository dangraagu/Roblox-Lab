# CLAUDE.md — SIGNAL LOST: Derelict Station (Roblox)

Context so a fresh session can continue. Sibling of the other Roblox-Lab games; same stack (Rojo, Config-driven, a
pcall'd DataStore with a session lock, pure logic tested from the luau CLI, a phone-first HUD, headless gates in
`robloxemu`). Spec: `DESIGN.md` (every number tagged with where it came from). Finish line:
`docs/complete-game-standard.md`.

## What it is
A space-station survival explorer. The LIFT drops you into a sector: a grid of 32-stud modules generated per attempt,
built only as you open their hatches. Air modules refill your tank; breached modules have 20 % gravity and drain AIR
1 s per second; the lamp over every hatch says AIR or VACUUM. A server-computed 5-bar SIGNAL meter leads to the one
relay; reaching it splices: carried salvage banked plus a bonus, relays restored +1, the lights come on, a floor hatch
into the next (bigger, emptier) sector. 0 AIR + 5 s = blackout: half of what you carried, a newly generated sector.
Salvage buys AIR TANK and MAG-BOOTS. Relay 30 = the Main Array (the brag); sectors never end. Public + friends board of
relays restored. No monster, no Robux.

## State — v1 built and headless-tested (2026-09-30/10-01); NEVER OPENED IN STUDIO; NOT PUBLISHED
- No universe, no place id, no publish script. Nothing committed by the build sessions.
- Every gate below green on the last run (2026-10-01, after REVIEW-1, bundle rebuilt first): specs **1253 / 0** (Air 64,
  Board 81, Config 121, Economy 120, EnvBands 124, EnvConfig 224, Hazards 157, MazeGen 3, Meter 19, Responsive 70, Rest
  81, Rng 37, Station 46, Trust 82, Pacing 24); `check_signallost_compile` 49 / 0 (23 sources); `check_signallost`
  169 / 0; `check_signallost_board` 61 / 0; `check_signallost_hud` PASS (10 viewports x 3 modes, overlap = true);
  `check_signallost_env` 233 / 0; `check_signallost_review` 46 / 0; `check_signallost_campaign` 16 / 0;
  `tests/walk.luau` 82 or 91 / 0 (it plays different sectors); `rojo build` OK. Repeated runs: `check_signallost` 60 of
  60 green (it was 55 of 60 before REVIEW-1 fixed two set-ups), env / review / board / hud 20 of 20, campaign 22 of 22.
- **REVIEW-1.md** (2026-10-01): two adversarial reviews, 8 findings, 7 closed test-first, 1 open (luau-analyze); plus
  the gamepad prompt buttons and a queued-REST line. Read it before changing AIR, the trust, the leave / shutdown path,
  `BuyUpgrade`, the hazards or the relay room.
- Two defects found and closed test-first in the resume session (2026-10-01): (1) after a splice, a player who wandered
  back into vacuum picked leftover salvage up for "+0" (a silent loss) and, on blacking out, was woken in the relay
  they had just spliced instead of the next sector — the next sector is now always `best + 1`, and leftover salvage
  stays with a toast (`check_signallost` L3); (2) the exterior (planet, dish, 30 relay beacons) sat where neither the
  lifeboat window nor any vacuum glass could show it — measured 0 % planet and 0 / 30 beacons from both benches; it is
  now placed per opening (`EnvArt.LAYOUT`, EYECANDY.md §2.3) and `check_signallost_env` ray-casts through the real parts.
- Mutation sweeps with a control: EYECANDY.md §11 (the build) and REVIEW-1.md (the review's fixes).
- The single largest risk: nothing has been rendered or played by a person. EYECANDY.md §8 is the needs-Studio list.

## How to run every gate

Git Bash, from `D:\Claude\Roblox`. `L` = the luau CLI directory (only `luau.exe` exists on this machine now:
`luau-compile.exe` and `luau-analyze.exe` were deleted from the shared scratchpad on 2026-09-23/24; the compile half of
that gate is `check_signallost_compile`, and luau-analyze is NOT run). The luau CLI prints to stderr: always `2>&1`.
Use `py -3`, never `python`/`python3` (in Git Bash those are the Windows Store stub and hang on stdin).

```
# 1. pure specs (one per shared module + the pacing model)
cd signal-lost
for s in Air Board Config Economy EnvBands EnvConfig Hazards MazeGen Meter Responsive Rest Rng Station Trust Pacing; do
  $L/luau.exe tests/$s.spec.luau 2>&1 | tail -1; done          # Pacing takes ~45 s (200 campaigns x 3 proxies)

# 2. ALWAYS rebuild the bundle before anything headless (the gates read build/, not src/)
cd ../robloxemu && py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau

# 3. headless gates
$L/luau.exe check_signallost_compile.luau 2>&1 | tail -1  # every source compiles (loadstring); no string require; controls
$L/luau.exe check_signallost.luau 2>&1 | tail -1          # world built+parented, spawn order, prompts, trust, AIR, blackout,
                                                          # splice, purchases, reset, crash-settle, locks, after-the-splice,
                                                          # the dock's RETURN, part caps, zero attributes, glyphs
$L/luau.exe check_signallost_board.luau 2>&1 | tail -1    # the board: stored value, ties, writes, caches, friends (stubbed
                                                          # GetFriendsAsync), budget gate, the Main Array, names never stored
$L/luau.exe check_signallost_hud.luau 2>&1 | tail -1      # HUD x 10 viewports x 3 modes (lifeboat, vacuum, shop), overlap = true
$L/luau.exe check_signallost_env.luau 2>&1 | tail -1      # bands, grade glide, dressing on real modules, low gravity, rest,
                                                          # hazards through the real client, what the openings show, budgets
$L/luau.exe check_signallost_review.luau 2>&1 | tail -1   # REVIEW-1's server regressions: a position-writing client pays
                                                          # the AIR of the vacuum it crosses; a leave / shutdown at 0.5-0.6 s
                                                          # latency stops ticking and leaves no lock; BuyUpgrade floods
$L/luau.exe check_signallost_campaign.luau 2>&1 | tail -1 # one real campaign to relay 30 (~10 s): hazard rate and near-misses,
                                                          # none called off in-sector, the relay room after every splice, REST
                                                          # there, prompt buttons
cd ../signal-lost && $L/luau.exe tests/walk.luau 2>&1     # the player's path, in numbers (join -> loop 1 -> leave -> rejoin -> loop 2)

# 4. the place builds
rojo build default.project.json -o <somewhere outside the repo>.rbxlx
```

Seeds are engine entropy, so every headless run plays different sectors. `check_signallost` (169), `_board`, `_hud`,
`_env` (233), `_review` (46) and `_campaign` (16) print stable assertion counts; the walk's count varies with how far it
gets. Only failures matter. A set-up that depends on the map must not assume one: two did, and failed 5 of 60 runs.

## The traps this game has (each is asserted somewhere; do not "simplify" them away)
1. **The relay stream draws exactly once and drives nothing visible** (`Station.plan` step 3). Walls, air and loot each
   come from their own stream; changing the relay stream changes the relay and nothing else (`Station.spec`).
2. **Production streams are `Random.new()` with no seed**, one object per stream per attempt (`Station.freshStreams`).
   Tests pass `tests/Streams.luau`, an adapter over `Rng.new(seed)` with the same two methods. There is no seed to leak
   (fork-tower REVIEW-4).
3. **The air map never reads the relay** (the reach rule reads walls and air only), and the relay is chosen after it.
4. **Nothing secret is an Instance.** Server-only state is a Lua table plus `ServerStorage.SignalDebug` (test data, never
   replicated). Zones carry ZERO attributes; the State payload's key set is asserted exactly; a relay mast exists only
   once its module is built. (anomaly-observatory: "ServerStorage, not the zone".)
5. **Every rule reads the TRUSTED position** (`Trust.luau`: 1.35 x the server's speed, 3 s burst, module changes only
   through hatches the server opened). No Raycast, no Touched, no PathfindingService. A teleport builds and picks up nothing.
6. **The server assigns WalkSpeed and JumpHeight on every module change** (`applyMove`); the client's low gravity is a
   VectorForce it owns, worth nothing to the server.
7. **Spawn order** (`robloxemu/SPAWN-ORDER.md`): the lifeboat and `HubSpawn` are built before `PlayerAdded`;
   `HubSpawn` is the only enabled SpawnLocation; `plr.RespawnLocation = HubSpawn` in `PlayerAdded`;
   **`onCharacter` writes no CFrame and never yields** (`check_signallost` B reads its source). Blackouts never kill the
   Humanoid.
8. **An unspliced sector is paid exactly once**: `open` is set when an attempt begins and cleared in the same write that
   pays it (`Economy.splice` / `Economy.settle`); every way out (blackout, return, reset, left, shutdown, crashed) pays
   floor(carried / 2) through the idempotent `endSector`.
9. **The next sector is always `best + 1`** — the LIFT, the floor hatch, and a blackout's wake-up, including a blackout
   AFTER a splice. Salvage left in a spliced sector stays where it floats, with a toast; nothing is ever "+0".
10. **Hazards only in vacuum, rest only in air.** `Rest.validateStation` refuses a config that allows vacuum; the hazard
    clock freezes while resting and never resets.
11. **The ordered value is an integer under 2^53**: `best * 2e9 + (2e9 - bestAt)`, `MaxMetric` 4 000 000; written only
    when `best` improved, at most once per 60 s per player plus on leaving; `UpdateAsync` keeps the larger value.
12. **Session lock**: a stable per-session GUID owner, never a rewritten timestamp; `canSave` only while holding it; a
    purchase is snapshot -> apply -> whole-profile flush -> rollback if it did not persist.
13. **The Hazards template changed while this game was designed**: copied from `plus1-jump` at md5 `f36a9ac2` (modified
    2026-09-30 22:48, copied 23:40). Its adaptations are listed in `Hazards.luau`'s header and EYECANDY.md §1. Do not
    re-copy over them.
14. **The exterior must sit where the openings look** (`EnvArt.LAYOUT`): the window shows only -1.5 to 10.4 degrees of
    elevation from the benches, a vacuum pane only about 30 degrees around the zenith. Move it and
    `check_signallost_env`'s ray casts will say so.
15. **Shared modules take their dependencies as arguments.** A bare `require("./X")` resolves in the luau CLI and is
    invalid in Roblox; only `tests/` may use it (`check_signallost_compile` scans the bundle).
16. **Glyphs:** only ★ — … (photographed rendering in Studio) and Latin-1 (the middle dot ·). Check N sweeps every
    string and toast.
17. **AIR is time OR trusted vacuum distance, whichever is more** (`Air.vacuumCharge`, REVIEW-1 finding 1). Charging only
    the module a tick ENDS in let a client that writes its position cross a vacuum module between two ticks free.
    `Trust.step(..., isVac)` reports `t.vacStuds`; the last doorway of a route never aims past the claim (an overshoot
    would be charged to honest walkers). Credit for paid-but-unwalked time is capped at `CreditSeconds` (1 s) and dies
    with the vacuum stretch.
18. **A closing session never ticks, and only its releasing write saves** (REVIEW-1 finding 2). Otherwise an arrival,
    blackout or splice during a slow release write re-takes the lock for 45 s, or a splice (and its board write)
    lands after the leave. `BindToClose` marks EVERY session closing first, then writes them all at once.
19. **`BuyUpgrade` checks its cooldown before anything else** and says "One moment…" at most once inside it.
20. **A hazard whose player walks into another module locks and flies on; only leaving the sector calls it off**
    (REVIEW-1 finding 4: called off at the module edge, 111 of 112 warnings vanished). REST asked for while that
    debris still flies is queued and SAID (`Config.Rest.Text.Queued`).
21. **The relay module is dressed again when the splice builds its floor hatch and console** (`keepSignature`), in the
    band it was first dressed in. Before, racks stood on the hatch and tanks cut into the console.
22. **No prompt uses gamepad ButtonX** (REST's button): fabricators and the board ButtonY, RETURN ButtonB. Roblox shows one
    prompt per button, and the relay console carries two.

## Files
- `src/shared/Config.luau` — every tunable, pinned by `tests/Config.spec.luau`.
- `src/shared/Station.luau` — the generator (four streams) and the module geometry the server builds.
- `src/shared/Air.luau`, `Meter.luau`, `Trust.luau`, `Economy.luau`, `Board.luau` — pure rules, one spec each.
- `src/shared/EnvBands.luau` (verbatim), `Hazards.luau`, `Rest.luau` (adapted), `Dressing.luau` (pure: kits and the art's
  fairness rules), `EnvArt.luau` (client art, including `LAYOUT`), `EnvBus.luau`, `Fx.luau` (+ `Presets.Station`),
  `FxClient.luau`, `Responsive.luau`, `Rng.luau`, `MazeGen.luau` (verbatim).
- `src/server/Main.server.luau` — the authoritative server.
- `src/client/Hud.client.luau`, `Env.client.luau`, `Move.client.luau`, `Board.client.luau`.
- `tests/` — the specs, `PacingModel.luau` (campaign model on the real `Station`), `Streams.luau`, `Bot.luau` (a headless
  player that knows only what a client could know; `skipItems` leaves pieces floating), `walk.luau`.
- `design-measure/` — the rig DESIGN.md's numbers came from. A design tool, not game code.
- `README.md` (store text), `EYECANDY.md`, `MARKETING.md`.

## Next (the night shift, Studio 00:00-06:00 only)
Walk EYECANDY.md §8 (item 8 now includes the gamepad prompt buttons, item 7 the near-miss behind a player who walks
on), take the thumbnails (§9), film MARKETING.md's clips, then create the universe, a git-ignored
`publish_signal.bat`, the maturity questionnaire, and only then marketing. None of that has started.
