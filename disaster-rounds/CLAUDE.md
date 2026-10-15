# CLAUDE.md - Disaster Rounds (Roblox)

Context so a fresh session can continue. Sibling of `plus1-jump/`, `deep-vein/` and the rest; same stack: one `Config`,
pure rules in `src/shared` tested from the CLI, an authoritative server, a phone-first HUD, plus1-jump's eye-candy
templates verbatim. Built 2026-10-07 from `DESIGN.md` (862 lines, the spec; read §1-§2 before changing a number).

## What it is

Round-based survival. Every 88 s (20 s on the Lookout deck, a 4 s drop onto a freshly generated 13 x 13 terraced
island, a 60 s disaster, a 4 s outro) everyone not on a break is dropped onto a new island. The disaster (Meteor
Shower, Flood, Tornado, Earthquake; an even draw every round, so the same one can come again) is named 4 s after the
drop. **Every danger is drawn
in red first and the red is exactly where it hits.** One hit sends you to the Lookout until the next round. Surviving
raises your streak; Heat = min(5, floor(streak / 2)) aims more rings at you. Bands by lifetime survivals (the brag,
Falling Sky, at 21: 35.1 min median). Board: best streak, counted up to 25. No currency, nothing costs Robux.

## State (2026-10-07, after REVIEW-1)

**REVIEW-1 (`REVIEW-1.md`) closed all eleven findings of two adversarial reviewers**, each reproduced first, a failing
test first, then a game fix: the 4 s outro is no longer "during a round" (F1); off the island is the sea in every
disaster (F2); a leave's write is not lost behind a write in flight, and `BindToClose` waits (F3); the next disaster
is an even draw (F4); the board counts a streak up to 25 (F5, an owner decision on the number); JumpIn refusals are
throttled (F6); every red piece is a volume that shows on every terrace (F7); the tornado's red is its reach exactly,
behind the funnel too, from the name (F8); a SetRest over the rate is applied late, never dropped (F9); the guard
keeps nothing from its quiet second (F10); budgets are capped in code (F11). Three new checks (`_outro`, `_exploit`,
`_terrace`); 22 new mutants and the builder's 35 (ported) all killed; the control survived all 31 gates.

The build session's state, unchanged where REVIEW-1 does not say otherwise:

**Built, every gate green, mutation-tested with a control. Never opened in Studio, never played by a person, not
published, no universe, not committed, not independently reviewed.** The first build session stopped at 21:20 with the
code and the checks in place but no README / CLAUDE / EYECANDY / MARKETING; the resume session (from 22:26) re-ran every
gate, added `check_disasterrounds_zones` (the red is the hit zone, through the real server and client) and
`check_disasterrounds_guard` (the movement guard through the real server), ran the mutation sweep in a sandbox copy,
and wrote the documents. No game code changed in the resume session.

Gates, last full run (REVIEW-1, `<scratchpad>/r1/gates_r1.sh`, bundle rebuilt first): **syntax 57 files, 0 bad; 17 specs 1 083 passed, 0 failed; 12 headless checks 495 passed, 0 failed, and the HUD check PASS; the walk 24 passed, 0 failed** (table below).
Mutation sweeps: the build's **35 of 35** (control unnoticed by 11 gates); REVIEW-1's **22 of 22** new mutants and the
build's 35 ported to the new code, **35 of 35**, all killed; the REVIEW-1 control unnoticed by all 31 gates.

## Running the gates

**There is no luau CLI on this machine** (2026-10-07: the scratchpad's `luau/` folder is empty, no `luau.exe` on C: or
D:, none in WSL; fetching one needs the owner's go). Every gate in this file ran under a **Luau-to-LuaJIT shim** the
first build session wrote: `<scratchpad>/dr/luaushim/luaurun.py` (`luau2lua.py` transpiles Luau to Lua 5.1 + LuaJIT,
keeping line numbers; `runtime.lua` supplies Luau's library differences; it runs on OBS Studio's `lua51.dll`).
`<scratchpad>` = `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad`.
Evidence it is faithful: robloxemu's own suites through it give datatypes 249/0, instance 153/0, scheduler 21/0,
services **189/0** (SPAWN-ORDER.md records 189 under the real CLI), and plus1-jump's 12 specs are all green. It is not
the real VM: **re-run everything with `luau` the first time a real CLI exists.** It sometimes dies before flushing
(an empty run): 2 of about 160 runs on 2026-10-07, both while other shim processes were running; re-run it, never
count it as a pass or a kill.

With a real CLI (append `2>&1`, the CLI writes to stderr):
```
cd disaster-rounds && for t in tests/*.spec.luau; do luau $t 2>&1 | tail -1; done
cd ../robloxemu && py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau   # ALWAYS first
luau check_disasterrounds.luau 2>&1        # and _hud _env _rest _save _board _wire _zones _guard _outro _exploit _terrace _fair
cd ../disaster-rounds && luau tests/walk.luau 2>&1
```
With the shim: replace `luau` with `py -3 <scratchpad>/dr/luaushim/luaurun.py`; `--check <files>` is the syntax gate
(transpile + LuaJIT compile). `<scratchpad>/r1/gates_r1.sh` runs everything in order (13 headless checks) and
re-runs an empty run; `GAME=` and `EMU=` point it at a sandbox copy.
`check_disasterrounds_bot.luau` is a module (the scripted dodger), not a check.

| gate | what it proves | last run |
|---|---|---|
| `tests/*.spec.luau` (17) | Board 77, EnvBands 124, EnvConfig 151, Flood 57, Guard 21, Hazards 111, MapGen 39, Pacing 27, Progress 70, Quake 17, Responsive 70, Rest 55, Rng 56, Round 71, Strikes 47, Tornado 22, Zones 68 | 1 083 / 0 |
| `check_disasterrounds` | the board says it counts up to 25 (F5); the world BUILT and PARENTED, the next island hidden in ServerStorage, joins LAND on LookoutSpawn under the engine spawn order, the board prompt reachable from the deck, the board RENDERS stored streaks and toggles Public/Friends, the loop: drop, name, dodge, SURVIVED, Heat 1, stand still = swept, practice counts nothing, leave mid-round = streak lost + told on rejoin | 89 / 0 |
| `check_disasterrounds_hud` | hudcheck, **`overlap = true`**, 6 extra phone viewports, 4 HUD modes (idle, card + toast, Jump-in + banner, Codex) | PASS |
| `check_disasterrounds_env` | band 1 = the server's first frame, every band and seam, glides, overlays, budgets with 8 players at Heat 5, the scenery caps obeyed when lowered and the server-Part ceiling at every cap (F11), nothing red | 85 / 0 |
| `check_disasterrounds_rest` | rest + strays + the AFK clock (§5 of EYECANDY.md) | 30 / 0 |
| `check_disasterrounds_save` | lock, owner token on every write incl. the release, read-only + takeover, failed load writes nothing, newer version never written | 41 / 0 |
| `check_disasterrounds_board` | written only on improvement and only saved values, max-merge, caches, failure paths; the cap: 25 written with the time it was first reached, nothing written past it (F5) | 34 / 0 |
| `check_disasterrounds_wire` | nothing replicates before its telegraph (Kind, cracks, path, water), no session token anywhere a client sees | 3 / 0 (10 566 ticks swept) |
| `check_disasterrounds_zones` | **the red is the hit zone**: ring discs (volumes over the levels they reach), flood tint = flooded set, the tornado's discs and boxes from the funnel on, crack tint; 0.05 studs in = hit, 0.05 out = not | 70 / 0 |
| `check_disasterrounds_guard` | 27-stud jump allowed, 29 caught; walking never trips; the island box; practice unguarded; one stale deck position 0.05-0.8 s after a drop never trips it (F10) | 29 / 0 |
| `check_disasterrounds_outro` | F1 + F3: a leave, respawn, death or fall in the outro keeps the streak; a leave behind an in-flight write still releases the lock and still eliminates mid-disaster; BindToClose waits for the release | 51 / 0 |
| `check_disasterrounds_exploit` | F2 + F4 + F6 + F9: a flier over the sea is swept in all four disasters within 0.6 s; the island's last strip is still ringed; 500 JumpIn -> 2 toasts; on/off/on in 0.6 s -> on, through the real HUD too; the same disaster back to back in 40 natural rounds | 28 / 0 |
| `check_disasterrounds_terrace` | F7 + F8: every ring shows red at the ground of every cell it reaches (412 rings, 52 % over more than one level); the tornado's red sampled at 600 frames = its reach exactly; a player 4 studs behind the funnel stands on red | 23 / 0 |
| `check_disasterrounds_fair` | 8 bots at Heat 5, 50 islands per disaster: 0 of 1 600 bot-rounds lost; at Heat 0, 0 of 320; an idle player is swept every round (13.2 s at the latest; 22.6 s at Heat 0); every landing faces level | 12 / 0 (212 s) |
| `tests/walk.luau` | the player's path from join into the third round, printed in numbers | 24 / 0 |

### Mutation sweep (2026-10-07, sandbox copy `<scratchpad>/dr/mutbox`, driver `mutate_box.py`)

Each mutant is applied to a copy of `src/`, the sandbox bundle rebuilt, its gates run, the file restored and its
sha256 checked. An empty (crashed) run is re-run, never counted as a kill. 35 mutants + 1 control:
Z1-Z10 (the zones check: ring drawn wider, ring hits short or long, flood tint misses its level, red line a stud high,
flood judges the wrong level, path ribbon too narrow, funnel reaches past its red, a dropped cell stays red, a crack hits
past its edges), G1-G4 (guard never consulted, practice guarded, no island box, trips at 26), and the first build's
21 mutants M1-M23 (M17 and M19 unused; never recorded then, re-run here; the list is `<scratchpad>/dr/mutants_all.py`).

**Results: 35 of 35 KILLED; the CONTROL (the Lookout's lamp bulbs 1.5 studs instead of 1.4) SURVIVED all 11 headless
gates** (`mutation_results.txt`, `mutation_results2.txt`; the sandbox's sources were restored byte-identical, checked by
sha256). One mutant survived the first pass and was not left that way: **G2 (practice players guarded too)** survived
because `_guard` asserted the practice jump inside the guard's quiet second after the landing teleport, where nothing
is judged; the jump now comes 1.5 s after the landing and G2 is killed (17 / 2). Z1-Z10 and G1-G4 were re-run against
the final `_zones` (70) and `_guard` (19), all killed, the control unnoticed by both.

## Files

```
src/server/Main.server.luau   the Lookout, LookoutSpawn, the round clock (10 Hz, tick()), islands (ServerStorage until
                              the freeze), disasters, hit tests, the guard, saves + lock, the board + prompt
src/client/Hud.client.luau    phone-first HUD: root Frame + UIScale, StatsPanel / PhasePanel / ButtonsPanel / BannerPanel /
                              CardPanel / ToastPanel / CodexPanel; Jump-in; nothing tappable at the bottom
src/client/World.client.luau  ring pulse + projectiles, flood/crack tints, path ribbon, funnel, chunks, Heat flames, confetti
src/client/Sky.client.luau    bands, overlay, scenery, critters, weather, strays + knock, rest + AFK, band cards
src/client/Board.client.luau  this player's view of the board (SurfaceGui under the board part)
src/shared/  Config; pure: MapGen Round Zones Strikes Flood Tornado Quake Guard Progress; templates (byte-identical to
             plus1-jump): EnvBands Hazards Rest Board Responsive Rng FxClient; Fx (+ preset Coast); art: SkyArt
tests/       17 specs; RoundModel.luau (pacing on the real modules); walk.luau
robloxemu/check_disasterrounds*.luau  the 13 headless checks + the bot module; robloxemu/build/disaster-rounds.luau
```

## Traps this game has (each one bit, or nearly bit, during the build)

1. **The engine places a spawning character AFTER `CharacterAdded`** (robloxemu/SPAWN-ORDER.md). `PlayerAdded` sets
   `plr.RespawnLocation = LookoutSpawn` before any yield; the only CFrame write in `onCharacter` (the facing) waits for
   `char.Parent` (bounded, 300 frames). Drops and returns are `PivotTo` on a parented character, never spawns.
2. **robloxemu fires `PlayerAdded` inline**, where a wait is an error; Roblox gives a handler its own thread. The handler
   is wrapped in `task.spawn`, which still sets `RespawnLocation` before the first yield.
3. **`CFrame.lookAt` toward the point you stand on is NaN.** A drop on the centre cell faced its own position and became an
   unhittable NaN body (found by `_fair`, 2026-10-07). `facingCentre` faces +X there; `updateIsland` sweeps out a NaN
   root as "fell". Mutant M15.
4. **Nothing about a round may be visible while a player can still sit it out.** The next island is built under
   `ServerStorage` and parented at the drop, after the roster freezes; `Kind` is set at the name, never earlier
   (anomaly-observatory CLAUDE.md "ServerStorage, not the zone"; mutants M7, M8).
5. **Two random streams.** The map's `Random` builds islands and picks drop cells; the disaster draws from its own
   `Random.new()`, fresh every round; no seed exists anywhere a client can see (fork-tower REVIEW-4).
6. **Timers use `tick()`**, never `os.clock` (it freezes headless, deep-vein). Clients extrapolate the server's clock
   from the `ServerNow` attribute (1 Hz, at most 1.5 s).
7. **The disaster tick and the round clock are pcall'd separately**: one error in a disaster tick froze a round forever
   (found by `_fair`).
8. **`Zones.overCell` must use `MapGen.cellAt`'s exact arithmetic**: a different formula put x = 3.999999999999999 in
   cell 8 for every client and cell 7 for the drop judge (found by `_fair`; mutant M18).
9. **The island's last 1.5 studs are not standing ground** (`STAND_HALF`): counting the edge let a third ring into a
   one-cell pocket (found by `_fair`).
10. **Server moves are not movement** (`MoveSeq`), and **the AFK clock counts the player's own input**: `Rest.luau`'s idle
    clock resets on every stray, so an AFK player on the deck never went on a break (found by `_rest`; mutant M12).
11. **A break pressed on the island waits for the round's end** (mutant M22). Rest must never pause a clock the player races.
12. **Leaving or resetting during a round is an elimination**, saved in the leave's write; `BindToClose` voids the round.
13. **The guard is quiet for 1.0 s after every server teleport and keeps NOTHING it sees then** (REVIEW-1 F10: the
    build kept recording, and one late-replicated deck position swept every dropped player a second later). It judges
    from the first sample after that second; a teleport inside it only moves where you start, on the island, 4 s
    before the name. Practice players are never guarded.
14. **The board writes only from SAVED values, only from the lock holder** (`writeBoard` after a landed `saveProfile`).
15. **The board's SurfaceGui is not in PlayerGui**: hudcheck measures everything in PlayerGui as a screen panel.
16. **robloxemu has no physics, no Raycast, no PhysicsService, no LoadCharacter.** Every outcome is computed from the red
    zones, never from physics; the collision group is pcall'd and is EYECANDY.md needs-Studio #9. The checks move roots.
17. **robloxemu's `PivotTo` multiplies rotation error** (about 4x per call; NaN after ~25 moves of one model). In Roblox
    the Humanoid keeps a body upright; the bot re-squares an idle root. Not a game defect.
18. **`require("./X")` works only in the CLI.** Shared modules take dependencies as arguments (`Strikes.canPlace` takes
    `Zones.exitDistance`); specs and checks may require by path, game code never does.
19. **An empty island ends the disaster at once** (the early end). A check that sweeps its only player must read the
    verdict after its loop, not only inside it.
20. **The round ends when the disaster does** (REVIEW-1 F1). `endDisaster` moves the survivors from `cur.on` to
    `cur.returning`: a leave, respawn, death or fall in the 4 s outro is not a leave or reset "during a round".
    `returnAll` takes both sets home.
21. **Off the island is the sea, in every disaster and the drop** (REVIEW-1 F2). A flier parked over the sea inside the
    guard's box was never ringed (no standing ground in reach), out of the funnel's reach, over no cell to crack.
22. **A save works on the session object, never `sessions[plr]`** (REVIEW-1 F3): a leave clears `sessions[plr]` at once,
    and the leave's own write may be waiting behind one in flight. `writesInFlight` is counted down only after the
    waiting write, so `BindToClose` never sees 0 in between.
23. **Any rule about which disaster comes next leaks to a resting player** (REVIEW-1 F4): the last disaster is public
    and a break chooses which rounds you play. The pick is an even draw, owing nothing to history.
24. **Red must show at the ground of every cell it reaches** (REVIEW-1 F7, F8). The hit tests are 2-D, the island is
    terraced: a red piece is a volume from 0.05 over the lowest top to 0.25 over the highest (`Zones.redSpan`), and the
    cell lists include a cell whose edge the red only touches (`cellRange`'s 1e-6: a ring at x = 32.5 reaches x = 28.0).
25. **A call in the middle of an argument list passes ONE value.** `Board.encode(Progress.boardEntry(p, cfg), BC)`
    hands `encode` the metric and `BC`; REVIEW-1 nearly shipped it. Capture both returns first.
26. **A rate limit that drops a request needs a client that resends** (REVIEW-1 F9). SetRest's client sends only on a
    change, so the server applies a request over the rate when the second is up instead of dropping it.

## Owner decisions still open (DESIGN.md §17, he may veto any)

Physics is presentation only; the map is a terraced height grid; 4 disasters in v1; the board ranks best streak (not
total survivals); 8 players per server; **the board counts a streak up to 25** (REVIEW-1 F5; `Config.Board.StreakCap`,
`math.huge` restores the uncapped board that a dodge script tops in about 25 minutes); **the next disaster is an even
draw** (REVIEW-1 F4: "never twice in a row" was a leak).

## Next

1. The night shift (Studio, 00:00-06:00): `EYECANDY.md` §8 needs-Studio list (26 items), §9 thumbnails,
   `MARKETING.md` clips.
2. REVIEW-1 is done; a second review pass on REVIEW-1's own changes would be the standard's next step before a publish.
3. Re-run every gate with a real luau CLI when one exists.
4. Publish only on the owner's go: create the universe, `MaxPlayers = 8`, a git-ignored `publish_disaster.bat`, the
   content-maturity questionnaire, the store text in `README.md` (990 characters).
