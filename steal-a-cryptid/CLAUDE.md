# CLAUDE.md - Steal a Cryptid (Roblox)

Context so a fresh session can continue. Sibling of `deep-vein/`, `fork-tower/`, `vault-runners/`;
same stack: Rojo layout, every tunable in `Config.luau`, pure rules in `src/shared` tested from the
luau CLI, a pcall'd DataStore with a soft session lock, a phone-first HUD, `robloxemu` headless
gates. **DESIGN.md is the spec** (section numbers in source comments point into it); where v1 does
something else, the "Deviations" table below says what and why. README.md is the player-facing
description and the proposed store copy. **REVIEW-1.md** is the second adversarial review round and
how each of its ten findings was reproduced, tested and closed.

## State (2026-09-17)

- **v1 built and headless-tested. NEVER OPENED IN ROBLOX STUDIO. NOT PUBLISHED.** No experience, no
  place ID, no publish script. Nothing committed or pushed by the build or fix sessions.
- History: a first build pass (2026-09-16) went green; two reviewer probes (called "REVIEW-1" in older
  comments: an exploit lens and a reachability lens, scripts in a session scratchpad, no report file)
  found defects no gate saw; the first 2026-09-17 pass confirmed each with numbers, wrote a failing
  headless test for every one (guards G1-G14), fixed them and ran a 27-mutation sweep. Two further
  reviewers then reviewed THAT build and found ten more (A1-A6, B1-B4, one high). The second
  2026-09-17 pass (REVIEW-1.md) reproduced all ten with the reviewers' own probes, wrote failing tests
  (guards G15-G24 and spec/check assertions), fixed the game, re-ran every probe on the fixed build and
  ran a 62-edit mutation sweep with a proof that every edit reached the bundle. Every number below was
  measured in one of those passes.
- Nothing sells anything: no MarketplaceService, no purchase prompt, no Robux reference in `src/`.
- No reviewer has yet looked at the second pass's changes (the slide and pull-back, the barriers, the
  grab spot, the lock wait and re-check, the closing flag, camp seeds, the poacher placement rule).

## Gates - run all of them, in this order

The luau CLI writes to stderr: always append `2>&1`. Substitute your own `luau.exe` path.

```
cd D:/Claude/Roblox/steal-a-cryptid
luau tests/Rng.spec.luau 2>&1           # 32 passed, 0 failed   (copied verbatim from fork-tower)
luau tests/Responsive.spec.luau 2>&1    # 70 passed, 0 failed   (copied verbatim from deep-vein)
luau tests/Economy.spec.luau 2>&1       # 193 passed, 0 failed
luau tests/Offers.spec.luau 2>&1        # 36 passed, 0 failed
luau tests/Layout.spec.luau 2>&1        # 202 passed, 0 failed  (2 000 lairs, 2 000 camps per tier)
luau tests/Heist.spec.luau 2>&1         # 79 passed, 0 failed   (solver over 300 camps per tier)
luau tests/Trace2D.spec.luau 2>&1       # 52 passed, 0 failed
luau tests/Poacher.spec.luau 2>&1       # 51 passed, 0 failed   (4 000 lairs x 4 defenses)
luau tests/CryptidModel.spec.luau 2>&1  # 552 passed, 0 failed

for f in src/shared/*.luau src/server/*.luau src/client/*.luau tests/*.luau ../robloxemu/check_stealacryptid*.luau; do luau-compile --binary $f > /dev/null; done
luau-analyze src/shared/*.luau src/server/*.luau src/client/*.luau tests/*.spec.luau 2>&1 | grep -v "Unknown global\|Unknown type"
                                        # empty

cd ../robloxemu                         # ALWAYS rebuild the bundle before a headless run
py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
luau check_stealacryptid.luau 2>&1         # 332 passed, 0 failed
luau check_stealacryptid_guards.luau 2>&1  # 184 passed, 0 failed
luau check_stealacryptid_hud.luau 2>&1     # two PASS lines: box fit (hudcheck) and text legibility
cd ../steal-a-cryptid
luau tests/walk.luau 2>&1                  # 46 passed, 0 failed, and prints the loop in numbers
```

**The headless files draw a new random session salt every run** (camps, laser phases, offers,
poachers all change). Measured stability on the final tree of the second pass: `check_stealacryptid`
0 failing runs of 100, `check_stealacryptid_guards` 0 of 60, `walk` 0 of 60, the HUD gate 0 of 10.
A failure prints the camp seed.

## What each headless gate proves

- `robloxemu/check_stealacryptid.luau` asks the WORKSPACE: 12 plots built and parented from
  max(World.Plots 8, emulator MaxPlayers 12); exactly one enabled SpawnLocation and none in a lair or
  pocket; a joining character lands on its own arrival marker under the recorded Studio spawn order
  replayed by hand, under `simulateSpawn`, on a respawn, on a reused plot, and after a respawn DURING
  a raid; every lair ProximityPrompt within its MaxActivationDistance of a standable point, and every
  Part carrying a prompt glowing; every build tile clickable from every apron point (farthest 100.61
  of 128 studs); every Grab anchor glowing, and its prompt shown along the whole cage front and on at
  least 97 % of the points a 2 x 2 body stands on in the grab cell (a 0.25-stud grid against the built
  Parts); part budgets (road 60, a fresh lair with build mode 113-114, the worst reachable lair 242-244
  of 300, a tier-1 pocket 68-71 of 200); the first minute through real prompts and the pad; a tier-1
  raid walked along a solver route, the stolen cryptid walking into its cage afterwards; walking into
  an ON net; a claimed teleport (2.16 studs a tick) and a refused grab; a claimed noclip stopping at
  z 49; a grant whose DataStore write fails rolled back with the permit refunded; offline jars (100 s,
  10 days, a future savedAt); a profile locked by another server waited for (no lair state, a toast),
  then played unsaved and never written; a hunt far from the board refused; remote validation and the
  rate limiter; **zero attributes on any Instance under workspace or ReplicatedStorage**; leaving frees
  the plot and releases the lock; every toast and banner the run sent fits the HUD's text proof
  (longest toast 83-89 characters, banner 68).
- `robloxemu/check_stealacryptid_guards.luau` is one block per review finding, each written before its
  fix and watched fail. First round: G1 trap-key alias mint, G1b duplicate saved strings, G2 banked
  jump through an ON net, G3 escaping through the fence away from the gate, G4 collecting mid-raid, G5
  the grab hold (fired away from the spot, stepping away mid-hold, a press a tick before the server
  sees the raider arrive), G6 silent abort, G7 pocket and tile churn, G8/G8b load retries and the
  load-failed banner, G9 a lock left behind by a player who left mid-load, G10 a grant whose write
  yields then fails, G10b a grant landing under an older in-flight write, G11 a lock taken over
  mid-session, G12 armed gaps visible while the net is off, G13 a trap blocking the click on its tile,
  G14 walkable cage-row cells. Second round (REVIEW-1.md): G15 a 0.5 s freeze turning into a fence gap
  (B1), G15b the pull-back (B1), G16 a corner squeeze (A6), G17 where the Grab prompt shows is where a
  grab works (B2), G18 a grant and a leave queued behind one write (A3), G19 a change during an
  in-flight write, and a failed write retried (A4), G20 a lock released after the join, lapsing after
  the wait, overwritten by the other server, and a take-over landing after the player left (A1), G21 a
  trap set under a walking poacher (A5), G22 camp seeds not computable from earlier ones (A2), G23 a
  slow load never yanks a walking player (B4), G24 a slide into a burning net judged leg by leg (B1).
  It joins players on their own thread and can make UpdateAsync yield (see Traps 7 and 8).
- `robloxemu/check_stealacryptid_hud.luau` runs `emu/hudcheck` over 10 viewports in three HUD modes
  (Hunt panel, build sheet, raiding with the banner) and ALSO estimates every shown string's rendered
  size with a 100-character toast and a 90-character banner on screen (rule in Traps 11).
- `tests/walk.luau` is a player held to what a player can do: it runs the real HUD client and presses
  its buttons, presses an in-world prompt only inside its reach (a press out of reach is a FAIL),
  clicks tiles only inside ClickDetector reach, and checks every apron step and every raid route
  sample against the collidable Parts for a 2 x 2-stud body. Join, buy, collect, raid tier 1, save up,
  force a fence line through the HUD's build sheet, sit through the first poacher, raid tier 2, leave,
  rejoin; and it is never pulled back. It prints every step with the clock.

## Core model / invariants

- **Pure modules, dependencies as arguments.** `Layout.generateCamp(cfg, Rng, seed, tier)`,
  `Heist.caught(cfg, Layout, L, ...)`, `Poacher.step(cfg, Layout, Heist, L, p, now)`. Nothing in
  `src/shared` requires anything: `require("./X")` resolves in the luau CLI and is invalid in Roblox.
- **The grid** (plot-local, DESIGN.md section 3): row 0 is the front fence with the gate at column 5,
  rows 1..8 the yard, row 9 the cages. Fence lines are full rows with gaps; lasers only in gaps; rocks
  and generated snares in free rows, never beside a gap, never on the entry cell (5,1) or row 8.
  Lasers are never 4-adjacent. Snares block route planning, lasers do not.
- **Every cell a client names goes through `Layout.isBuildCell`** (integer column 1..9, integer row
  1..7). `Layout.key(col, row)` aliases `(col + 32, row - 1)`; see Traps 1.
- **Every raid rule reads the trusted position** (`Trace2D`), never `hrp.Position`: at most
  16 x 1.35 = 21.6 studs/s walking, 16.2 carrying, per tick, with NO bank (Traps 2), on the map
  `Layout.freeRects` returns (floor cells grown 1 stud) and never across its barriers (Traps 15). A
  clamped move SLIDES along the wall with the rest of its allowance (Traps 14); no route is planned.
  When it makes no progress toward a claim more than 4 studs away for 1 s, the server pulls the
  character back to `Trace2D.settle` and says so. It starts where the server put the raider.
- **The catch is a continuous test along every leg of the tick's path** (`Heist.caughtPath` over
  `t.path`, each leg timed by its share of the length): each leg against every trap's danger rect, the
  first 0.2 s of each ON window treated as OFF. Out of a camp only through the gate cell
  (`Layout.escaped`).
- **The server publishes the present, never the schedule.** Nets are repainted as their state
  changes; every armed cell carries an always-visible emitter plate, so the Instance tree names only
  what a player can see. Server-only raid facts live in `ServerStorage.RaidInfo.<userId>`. Camp seeds
  are independent draws from a server-only `Random` stream (Traps 18).
- **The grab spot is the prompt's reach.** The server grabs when the trusted position is within
  `Raid.GrabReach` (5) of the cage's anchor on the flat; the prompt's MaxActivationDistance is the
  same 5 and the anchor hangs at root height (Traps 17). The hold is paid at the spot, on the server's
  clock: HoldBegan stamps the clock only while the trusted position is there (or, pressed just before
  it arrives, from the tick it does: `Raid.HoldAskSeconds`); leaving drops the stamp or cancels a
  pending grab; Triggered from outside is refused at once.
- **A grant is one write, and the game waits for it.** On escape the raider is sent home FIRST,
  `S.granting` refuses every lair action and hunt until the write lands, the write waits behind any
  write already in flight (`flush(..., waitTurn)`, writes are serialised per session), and a failed
  write undoes exactly the grant's four changes and refunds the permit. A non-saving session keeps
  grants in memory. The stolen cryptid then walks from the arrival marker into its cage.
- **Saving.** Load is tried 3 times (waits 1 s, 2 s). A record another server holds is re-read every
  5 s for up to 15 s at join, with one toast; still locked, the session plays unsaved with a banner and
  re-checks every 15 s, taking the lock over only if the lock is gone AND the saved data is exactly what
  it loaded (else a "rejoin to load it" banner) (Traps 19). A profile that could not be read at all is
  played as a fresh one with a different banner and never written; a lock taken over mid-session flips
  the session to non-saving; a player who leaves while the load is in flight has this server's lock
  released. `pending` is cleared when a flush copies the profile, before it yields, and set again if
  the write fails. `S.closing` (set first thing in PlayerRemoving and BindToClose) makes every later
  write of that session release the lock instead of taking it.
- **Traps in a lair** are placed and cleared in build mode, with a 100 % refund; placing is refused
  while a poacher is in the yard (during its 10 s warning it is allowed).
- **Two clocks.** `os.time()` for everything persisted (savedAt, lock, Heat). `tick()` for session
  timers because it is the clock robloxemu advances.
- **Plots** are claimed synchronously in PlayerAdded before the DataStore yield; a character that
  already exists when PlayerAdded runs is sent home before the load, one that spawns during it by
  CharacterAdded. Pockets sit at x = 4000 + 128 s; a raid START is allowed once per 3 s per player.

## Traps (each one cost a red run or a shipped defect somewhere)

1. **`Layout.key` aliases cells.** `(row + 2) * 32 + (col + 2)` gives `(col + 32, row - 1)` the same
   key as `(col, row)`. The first build's "clear" only checked `type(number)`: a clear at the alias
   refunded the trap and left its saved string, and every rejoin refunded the string again. Measured:
   40 cycles and a rejoin turned 1 000 stored Essence into 11 000. Validate cells, and only the first
   saved string per cell is ever refundable (`Layout.reconcile`'s third return).
2. **A trusted-position BANK defeats a continuous catch test.** DESIGN.md's 0.5 s bank let one tick
   spend 10.8 studs; that segment spends 0.056 s inside a 6-stud net, all of it inside the 0.2 s
   latency grace. Measured on the first build: a jump claimed the tick after a net was painted ON was
   caught 0 of 4 times, an honest walk 4 of 4. No bank; a server hitch still credits at most 0.5 s.
3. **"row <= 0" is not "through the gate".** Every row-1 cell's trusted rect reaches 1 stud into the
   front fence. Measured: a carrier escaped from (9,1), 4 cells from the gate.
4. **A grab checked only when the hold ENDS is not a hold.** Measured: a prompt fired while walking in
   completed after 0.10 s of standing against a 1.0 s hold. And the fix has an honest-player trap of
   its own: the server reads positions once per 0.1 s tick, so a press on the frame the player
   arrives can land before the trusted position does. Without `HoldAskSeconds` that player holds twice.
5. **A write that yields is a window.** The emulator's UpdateAsync returns at once; a real one does
   not. With a yield: the pocket was already destroyed while the raider still stood in it (4 036
   studs out over nothing), a tier-1 hunt started, a snapshot rollback wiped every jar that filled
   meanwhile (22.0 at escape, 22.0 after), and a grant that landed before an older in-flight flush was
   overwritten by that flush (commit order older #5 after grant #3). All four fixed, all four tested.
   The second round found two more in the same window: Traps 19.
6. **One failed load is not "the store is down".** Measured: one injected UpdateAsync failure gave a
   veteran (5 000 000 Essence, 4 species) a blank 30-Essence lair for the whole session.
7. **`Players:simulateJoin` fires PlayerAdded inline**, and a scheduler wait on the main thread only
   moves the clock (or raises "thread yielded unexpectedly"). A handler that yields (the load retry,
   the lock wait) must be tested with a player joined on its own thread, which is what Roblox does.
8. **Make the emulator's DataStore yield from the check, not from `emu/`.** The guards file replaces
   `store.UpdateAsync` with a wrapper that waits on the virtual clock (and can then fail) before
   calling the emulator's own method; a `when` predicate picks one write (the grant) out of the
   periodic ones by peeking at what the transform would commit.
9. **CharacterAdded fires on an UNPARENTED character.** `onCharacter` waits for `char.Parent`
   (300 frames of `task.wait(1/60)`), re-reads the session, then CFrames home. Exactly one enabled
   SpawnLocation. Sweep M27 removes the wait and check, guards and walk all fail. And place a character
   ONCE: calling `onCharacter` again after a slow load yanked a player who had started walking back to
   the marker (9.6 studs after a 0.6 s load, 35.2 after a retry; REVIEW-1.md B4).
10. **Random camps make headless checks flaky unless the check redraws, or looks for what CHANGED.**
    Guards G5 once stepped into row 7 and got caught on a snare (1 run in 10); check section 6 assumed
    every tier-1 camp has a trap-free walk below its net (seed 651182418 walls it off, 1 in 60); the
    stolen-cryptid walk-in check once looked in the cage of the SAME species bought earlier (the prize
    was a Jackalope). Each now chooses a trap-free direction, draws another camp, or finds the cage the
    steal filled.
11. **Text that fits is not text that reads.** `emu/hudcheck` measures boxes. On an 844x390 phone the
    first build's toast was a 360 x 13 screen-px box holding 112 characters and the banner 276 x 10.8
    holding 99, both "fitting". The HUD gate now estimates each string's size (0.55 em per character,
    1.2 em per line: ASSUMPTIONS about GothamBold) and fails text below 11 px unless it is at least
    8 px AND at least 85 % of its own design size times UIScale. The rule is not a flat 11 px floor
    because the repo's mobile brief scales every HUD to 0.6 on purpose; what it catches is squeezing.
    First run: 98 squeezed strings. After wrapping toast, hint, banner, row labels and buttons and
    dropping the camp name from the raid chip: 0. The checks assert the server never sends a toast
    over 100 or a banner over 90 characters; the first build's raid-start toast was 112.
12. **Prompts reach from the part's centre, not its top.** The arrival marker is 10.11 studs from P1's
    prompt, so the first purchase is one step away; the walk measures it (first purchase 2.1 s after
    landing).
13. **fireproximityprompt and ClickDetector spam** bypass remote rate limits unless the prompt and
    tile handlers call the limiter themselves (`allowWho`). They do.
14. **A trusted position that stops on a wall's margin can be locked out for the whole raid.** A
    catch-up chord after a replication freeze cuts a fence corner, stops 1 stud into the fence, and
    from there every straight line toward a raider past the corner leaves the map, so it never moves
    again: every grab and escape refused until dawn (REVIEW-1.md B1; 7 of 25 phases of a 0.5 s freeze at
    1-stud clearance; over 600 honest routes 8 817 of 33 482 phases of a 1.0 s freeze). The slide
    removes the common case (0.7 s: 186 -> 0; 1.0 s: 8 817 -> 329); the pull-back ends the rest within
    1 s. A slide bends the tick's path, and a catch judged on the chord misses a slide along a gap's
    margin into its net (694 of 1 440 000 random ticks disagreed): judge every leg (G24).
15. **Grown floor rects overlap at a checkerboard corner.** Two rocks touching only at a corner leave
    0.57 studs between their Parts, but the two floor cells on the other diagonal, each grown 1 stud,
    overlap there and the trusted position walked through (REVIEW-1.md A6; squeezes in 947 / 680 / 682 /
    0 of 2 000 camps per tier). `freeRects` returns a barrier across each such corner.
16. **A claim ON a line computes `s = 1 + 2e-16`.** The first barrier test was exact and inclusive;
    a walker whose claims step centre to centre lands exactly on the shared corner, missed the hit and
    stood on the barrier, where `cellAt` put it in the far cell. Tolerance 1e-9, and back off 0.001
    studs. A spec that tried four corners did not notice the tolerance removed (sweep M37 survived
    once); it now walks all 192 corner cases, 35 of which fail without the tolerance.
17. **A server rule the prompt cannot draw.** A ProximityPrompt shows inside a sphere; a grab rule on
    the grab CELL (a square open along x) missed 12-14 % of the cell and showed a refusing rim beyond it
    (REVIEW-1.md B2). The rule is the sphere now. Changing it quietly weakened guards G5 (e), whose press
    no longer arrived early (sweep M08 survived once): when a region changes, re-check every test that
    positions a player relative to it.
18. **A seed that is the last one plus a constant is one seed.** DESIGN.md's camp seed
    (salt + raidSerial x 2654435761) let a player recover one camp's seed from its sign and layout by
    brute force (107.9 s of interpreted Luau) and compute every later camp on the server, prize and
    laser phases included, before paying its permit (REVIEW-1.md A2). Draw each seed independently.
19. **A lock read once, a flag cleared after a yield, a release that is not last.** A lock that
    cleared 1 s after the join cost the whole session (A1); `pending = false` after the write wiped a
    change made during it (A4: 52.4 s to the store instead of 5); a grant queued behind a write landed
    after the leave's release and locked the record again for 120 s (A3: 6 of 10 offsets).
20. **Python's text mode on Windows writes CRLF.** An edit script that did `open(p, 'w').write(...)`
    turned nine LF source files into CRLF, and every multi-line mutation string stopped matching (20 of
    62 edits "not found" in a dry run). Edit with the Edit tool or write bytes; scan for `\r` after.

## Deviations from DESIGN.md, and why

| DESIGN.md | v1 does | Why |
|---|---|---|
| `Raid.TrustedBurstSeconds` 0.5 s bank | no bank; `MaxTrustedTickSeconds` 0.5 caps a hitch | Traps 2 |
| trusted position: straight toward the claim, stop at the map's edge, no rerouting | a clamped move slides along the wall (no route planned); no progress for `StuckSeconds` 1 with the claim over `StuckStuds` 4 away pulls the character back, with a toast | Traps 14 |
| trusted map: floor cells grown by 1 stud | plus a barrier across every checkerboard corner | Traps 15 |
| catch test on each tick's segment | on each leg of the tick's path | Traps 14 |
| escape when the trusted position reaches row 0 | only through the gate cell plus its 1-stud margin | Traps 3 |
| grab prompt anchor on the cage front, reach 10; grab needs the grab cell | anchor over the grab cell's centre at root height; the server grabs within 5 studs of it on the flat, and the prompt reaches exactly 5 | the reach-10 prompt showed at points where 64 % were on no grab cell; the cell rule then missed 12-14 % of the cell (Traps 17) |
| grab re-checks the cell when the hold completes | the whole hold is spent at the grab spot; Triggered from outside refused at once; a press on arrival counts from arrival | Traps 4 |
| danger area = cell inset by 1 stud | inset 1 towards open floor, 1 stud INTO walls, 0 at a trap neighbour | a plain inset left a noclip lane along each side of a gap net |
| a failed raid-grant write rolls back | rolls back only the grant's own changes; raider home first; actions refused during the write; writes serialised | Traps 5 |
| a non-saving session when the store is unavailable | load retried 3 times first; its own banner; a lock lost mid-session also flips to non-saving | Traps 6; DESIGN.md only covered a lock seen at load |
| a profile locked at load is played unsaved for the session ("rejoin in 2 minutes") | waited for up to 15 s at join; then unsaved, re-checked every 15 s, taken over only if the saved data is untouched, else "rejoin to load it" | Traps 19 (A1) |
| Rival Camp seed = WorldSeed, salt, raidSerial x 2654435761, tier | an independent draw from a server-only `Random` per raid; `Layout.campSeed` survives only as the specs' seed enumerator | Traps 18 |
| (not in the design) | 3 s between raid starts; build mode switches on at most once a second; asking for the mode you are in does nothing | a Hunt + Leave loop built 79 pockets (491 Parts/s), BuildMode spam rebuilt tiles 80 times (352 Parts/s) in 10 s |
| traps placed and cleared in build mode, 100 % refund | placing refused while a poacher is in the yard | a snare dropped on the walking poacher and cleared after caught 5 of 5 visits for nothing (REVIEW-1.md A5) |
| lair actions refused while raiding: buy, release, expand, build | also the Collect Pad | the pad paid 66 Essence mid-raid |
| "Laser OFF is not a dim net; it is no net" | still no net, but every armed cell has an always-visible emitter plate | the Instance tree named every armed gap while its net was invisible (20 of 20 camps) |
| (camp cage row) | empty cage-row cells are solid brush | they were walkable floor outside the trusted map (1 008-1 080 standing points per camp) |
| snare Part | `CanQuery = false` | it covered 55 % of its build tile, so it could only be cleared by clicking the tile's rim |
| abort (respawn, death) grants nothing | ...and says so in a toast | it was silent |
| saved traps rejected on load are refunded | only the first string naming a cell is refunded | Traps 1 |
| raid chip: time left, carrying | no camp name (it is on the camp's sign) | on a phone it squeezed the timer to ~7.6 px |
| "Arrival to P1 is 10 studs" implies a prompt at spawn | P1's prompt is 10.11 studs away: one step | measured; prompts reach from the part centre |
| poacher steals half "the fullest jar at grab time" | half the jar of the cage it walked to (the fullest when it appeared) | it is standing at that cage |
| Release prompts on occupied cages | a Release prompt on every unlocked cage; an empty one says so | no prompt appears or vanishes as cages change |
| top-edge toggles: Build, Leave camp | Hunt, Build, Leave camp; Add cage and Re-roll in the Hunt panel | the design names Reroll and Expand remotes but no control for them |
| generator order ends with phases | ...phases, then cage species | the species draw was unplaced; last keeps earlier draws replayable |
| Timeout and Leave camp | not counted in `stats.caught` | only a laser or a snare is a catch |

## Numbers re-measured in Luau (DESIGN.md's came from Python models)

- **Layout** (`Layout.spec`, 2 000 seeds): lairs resampled 7 (worst 2 attempts), 553 walled-in free
  cells in total, 0 fallbacks. Camps resampled 5 / 95 / 111 / 825 per tier, worst 2 / 3 / 4 / 9
  attempts, 0 fallbacks. (Python: 4; 535; 3 / 82 / 117 / 859.) Corner squeezes in 947 / 680 / 682 / 0
  camps (1 252 / 809 / 804 / 0 barriers), every one between two rocks, none standable.
- **Raid time, gate-prize-gate** (`Heist.spec`, 300 camps per tier, human pad 0.3 s): median
  15.00 / 18.88 / 21.58 / 29.24 s, p90 16.69 / 23.55 / 26.33 / 35.31, p99 19.67 / 26.88 / 30.12 /
  40.19, max 19.74 / 32.86 / 30.49 / 44.69; flawless median 15.00 / 17.83 / 19.56 / 26.27; no-laser
  median 15.00 / 15.50 / 16.00 / 20.50; median laser cost 0.00 / 2.28 / 4.46 / 8.60. 0 of 1 200 camps
  unsolvable. Padded carry windows 1.10 / 0.80 / 0.50 / 0.30 s (34.4 / 24.2 / 14.7 / 8.3 % of a cycle).
  The tier-4 max, 44.69 s, is above DESIGN.md's 40.65; `Raid.RaidSeconds` 150 is still 3.4 times it.
- **Poacher catch rate** (`Poacher.spec`, 4 000 lairs each): no traps 0.0 %; one net in a gap 4.3 %;
  one line forced 41.4 %; both lines forced 62.9 %. Theft trip medians 21.2 / 21.2 / 24.0 / 29.1 s.
  Earliest grab 8.40 s after the poacher appears (18.4 s after the warning starts). These are traps set
  before the visit, which is now the only way to set them.
- **Trusted position:** an honest walker with a 0.5 s replication stall is throttled for 14 ticks and
  never clamped (`Trace2D.spec`). Freezes of 0.2-1.0 s turning a fence corner or a rock corner, every
  phase, walk and carry, clearance 1-4: 0 of 1 922 and 0 of 2 276 leave it behind. Over 600 honest
  corner-cutting routes (scratch measurement, REVIEW-1.md B1): freezes of 0.3 / 0.5 / 0.7 s never lock
  it; 1.0 s locks 329 of 33 482 phases and 1.5 s 4 708, each ended by the pull-back.
- **Grab spot:** reach 5 covers the whole cage front and 97.9 % of the grab cell's standing points;
  the reviewer's flood-fill probe measures 98.8-99.0 % per tier (worst cage 98.3 %).
- **The walk** (final run of the second pass; camps vary): first purchase 2.1 s after landing; tier-1
  raid 13.6 s against a 13.83 s plan; one minute after joining 4 Essence/s; first poacher warning at
  300.3 s, appearing 10.0 s later; tier-2 raid 21.4 s against 21.56 s (income 4/s -> 22/s); 162 studs
  walked, every apron step and route sample standable, 3 prompt presses all in reach, 0 pull-backs.
  Across this pass's walks tier-1 raids took 13.6-14.8 s and tier-2 16.4-21.4 s, each within 0.25 s of
  its plan.
- **Not re-measured:** DESIGN.md's success-rate table (`success.py`) and pacing table (`econ.py`,
  `tune.py`). They remain Python-model numbers and must not be quoted as the game's.

## Mutation sweep (2026-09-17, second pass)

Driver: `scratchpad/sacfix-r2/sweep.py` (not kept in the repo). Each mutation is an exact-string edit
set applied alone to `src/`, sha256 verified changed; the bundle is rebuilt and PROVEN to carry the
edit (its text differs from the baseline bundle and contains every inserted string; the "bundle"
column is the mutated bundle's sha256 prefix, the baseline's was 6c52f37e5131); all 13 gates run (9
specs, check, guards, HUD, walk); the source is restored and sha256 verified identical. Any gate not
fully green is KILLED; a CONTROL must survive. The `src/` manifest and the bundle were identical
before and after the sweep. Baseline: every gate green at the counts above.

**Result: 56 of 56 mutations KILLED, 6 of 6 controls SURVIVED, every edit reached the bundle.** M01-M27
are the first pass's mutations re-run on the new tree (M05, "grab prompt reach back to 10", is
superseded by M40-M43 now that the grab spot is the prompt's reach); M28-M57 cover every guard the
second pass added or changed. A first sweep of the same list found three survivors, each fixed in the
TESTS, not by weakening a mutation: M08 (guards G5 (e) no longer pressed early once the grab spot grew,
Traps 17), M34 (no test told the per-leg catch from the chord: G24 added after measuring 694
disagreements in 1 440 000 random ticks) and M37 (four corners did not hit the rounding case, Traps
16). "check 331/1" means 331 passed, 1 failed.

| # | mutation | result | bundle | red gates |
|---|---|---|---|---|
| M01 | isBuildCell drops its range check | KILLED | ca2b22c284d9 | Layout 198/4, guards 171/13 |
| M02 | reconcile refunds every removed string | KILLED | 39d182541828 | Layout 199/3, guards 183/1 |
| M03 | escape from any row-0 position again | KILLED | b3e016da9c5e | Layout 200/2, guards 180/2 |
| M04 | the 0.5 s trusted bank restored | KILLED | ca1707602c60 | Trace2D 46/6, guards 183/1 |
| M06 | grab fired away from the grab spot not refused | KILLED | 0cea68d575d8 | check 331/1, guards 182/2 |
| M07 | stepping away mid-hold does not cancel | KILLED | 17dbd787c36b | guards 183/1 |
| M08 | press-on-arrival never starts the hold | KILLED | 48f1fc3174a6 | guards 183/1 |
| M09 | Collect Pad pays mid-raid | KILLED | 02f31219bac8 | guards 182/2 |
| M10 | abort is silent again | KILLED | c94a1890ddae | guards 182/2 |
| M11 | restart cooldown 0 | KILLED | 7ef14880a1bb | guards 182/2 |
| M12 | BuildMode(true) while on rebuilds | KILLED | f89f55a4b51c | guards 183/1 |
| M13 | one load attempt | KILLED | dcc7f8a2fa32 | guards 182/2 |
| M14 | failed load shows the generic banner | KILLED | e06f33f77da3 | guards 183/1 |
| M15 | no lock release after leaving mid-load | KILLED | 756bd0fcb45c | guards 183/1 |
| M16 | home only AFTER the grant write | KILLED | 961ca4ed875b | guards 183/1 |
| M17 | no busy guard during the grant write | KILLED | 18ffcc0c85ee | guards 182/2 |
| M18 | rollback keeps the Journal entry | KILLED | 65e47bf01d0a | check 331/1, guards 183/1 |
| M19 | writes not serialised | KILLED | 1e1dce94d872 | guards 181/3 |
| M20 | lost lock does not stop saving | KILLED | 3696e3cfda03 | guards 182/2 |
| M21 | emitter plate never parented | KILLED | 5b015f88ffad | guards 182/2 |
| M22 | snare takes mouse rays | KILLED | 9a370d54d51b | guards 183/1 |
| M23 | no brush in empty cage-row cells | KILLED | 327bb22fb214 | guards 178/6 |
| M24 | toast does not wrap | KILLED | bbc7e7374c5d | hud FAIL (1 PASS lines, rc 1) |
| M25 | the 112-char raid toast is back | KILLED | ff18158aa3ef | check 331/1, guards 183/1 |
| M26 | failed grant keeps the permit | KILLED | 9848b3882c32 | check 331/1, guards 178/1 |
| M27 | CharacterAdded does not wait for the parent | KILLED | bd95248e92ac | check 321/11, guards 180/4, walk 44/2 |
| M28 | B1 no slide along walls | KILLED | 53316ec679fa | Trace2D 50/2, guards 179/5 |
| M29 | B1 no pull-back in the raid loop | KILLED | a4557e0944fc | guards 182/2 |
| M30 | B1 stuck time never counted | KILLED | c66b3d510c78 | Trace2D 51/1, guards 182/2 |
| M31 | B1 stuck counted even while making progress | KILLED | 1a119978636f | Trace2D 51/1 |
| M32 | B1 settle leaves the wall margin in | KILLED | 83bf03cc4394 | Trace2D 51/1, guards 183/1 |
| M33 | B1 caughtPath judges only the chord | KILLED | ab76b7401fcd | Heist 77/2, guards 182/2 |
| M34 | B1 raid loop judges the chord, not the legs | KILLED | 57d5f52456d7 | guards 182/2 |
| M35 | B1 slide legs not recorded in the path | KILLED | eec8cee2e338 | Trace2D 51/1, guards 182/2 |
| M36 | A6 no barriers | KILLED | f89ccf8ca669 | Trace2D 43/9, guards 183/1 |
| M37 | A6 barrier hit without tolerance | KILLED | 3b05b75f8b18 | Trace2D 51/1 |
| M38 | A6 raid loop does not pass the barriers | KILLED | ee96202a873a | guards 183/1 |
| M39 | A6 a leg stops ON the barrier | KILLED | 5a40eda8d914 | Trace2D 47/5 |
| M40 | B2 reach back to 4.25 (server and prompt) | KILLED | f95e3cd6d349 | Layout 200/2, check 326/6, guards 182/2 |
| M41 | B2 server grabs on the grab cell again | KILLED | 5a624c04f1f4 | guards 183/1 |
| M42 | B2 server reach 10, prompt 5 | KILLED | 3ee9b192ae0a | Layout 199/3, guards 179/5 |
| M43 | B2 prompt reach 10, server 5 | KILLED | 482d25380fb0 | Layout 200/2, guards 182/2 |
| M44 | A3 a closing session's late write locks again | KILLED | 44b6067aac51 | guards 183/1 |
| M45 | A4 pending cleared after the write again | KILLED | 3c5ce65764b6 | guards 183/1 |
| M46 | A4 a failed write is not retried at the next tick | KILLED | 3b549f9484cb | guards 183/1 |
| M47 | A1 no wait for a lock at join | KILLED | 6ecf15afa7e8 | check 330/2, guards 182/2 |
| M48 | A1 no re-check of a lock after the wait | KILLED | 55a7c4c9eedf | guards 179/5 |
| M49 | A1 re-check takes a lock over changed data | KILLED | 54874b3a82dc | guards 181/3 |
| M50 | A1 a take-over after leaving keeps the lock | KILLED | 1289c92c8268 | guards 183/1 |
| M51 | A5 traps allowed while a poacher is in the yard | KILLED | 129f37ef1c7e | guards 180/4 |
| M52 | A2 camp seed back to salt + serial step | KILLED | c135f69fdef2 | guards 182/2 |
| M53 | B4 the post-load re-placement is back | KILLED | f2d633817307 | guards 182/2 |
| M54 | B4 an early character is never placed | KILLED | 1955b39e8eb0 | guards 183/1 |
| M55 | B3 lair cages do not glow | KILLED | 00cfdea9ad2b | check 331/1 |
| M56 | B3 grab anchors do not glow | KILLED | 36d461c3b2ee | check 329/3 |
| M57 | B3 a stolen cryptid appears in its cage | KILLED | 88877551f77f | check 331/1 |
| C1 | CONTROL road pine crown 9x14x9 -> 10x15x10 | SURVIVED, correctly | d4bb9291f6b1 | - |
| C2 | CONTROL hunt panel background 0.08 -> 0.12 | SURVIVED, correctly | 4e86f2fd1c70 | - |
| C3 | CONTROL emitter plate transparency 0.35 -> 0.45 | SURVIVED, correctly | 370bd0a7d95b | - |
| C4 | CONTROL cage glow brightness 0.8 -> 0.9 | SURVIVED, correctly | 3a126a8e64ae | - |
| C5 | CONTROL pull-back toast wording after 'pulled back' | SURVIVED, correctly | 436e478d947d | - |
| C6 | CONTROL lock-wait toast wording | SURVIVED, correctly | 0648461cb4a3 | - |

## Needs Studio (nothing here is verified; do not report any of it as verified)

1. **Lighting and laser readability.** Whether OFF / WARN / ON read instantly from the gate 80 studs
   away, at phone size too; whether the full-height translucent net reads as unjumpable; whether the
   always-on emitter plate reads as "armed" and is distinguishable from a snare; whether the faint cage
   and grab-anchor glows read as "interact here" at night. Also whether `FogStart/FogEnd 40/220` does
   anything while the Horror Atmosphere (Density 0.42) exists: anomaly-observatory's Fx comment says
   an Atmosphere makes legacy fog inert.
2. **Latency grace (0.2 s)** on a real connection, and catch-up chords after a lag spike: after a
   freeze the trusted position crosses a net later than the player did.
3. **Trusted-position tolerance** without a bank (1.35x, per tick): count throttled ticks, slides and
   pull-backs in real play. How often does replication freeze for a second or more? What does a
   server-set CFrame on a client-owned character look like (snap, fling, camera), and is the
   "pulled back" toast noticed?
4. **The grab prompt**: a 5-stud sphere around a point 3 studs up assumes an R15 root at 3; an avatar
   with a different hip height sees it in a different region than the server's flat disc. Between two
   adjacent cages both prompts are in reach; which one Roblox shows. `HoldAskSeconds` 0.5 with real
   HoldBegan latency (+32 ms locally on fork-tower). Tap-and-hold on touch.
5. **The carried cryptid**: welded, Massless, parented to the character. Flinging, jitter, camera.
6. **Spawn**: the one-frame Trailhead flash; a Reset during a raid lands home.
7. **Build mode**: tapping ClickDetector tiles on a phone, reach at 128 studs, hover cursor, and the
   camera angles from which fences and rocks hide tiles (a reviewer ray probe found 6-35 of 44 tiles
   hittable from one camera angle at the arrival marker, depending on zoom).
8. **Fences, rocks and the brush**: a Humanoid cannot climb or jump a 10-stud block; 8-stud gaps feel
   right; two corner-touching rocks really do stop a body.
9. **Cryptid silhouettes** (6-12 Parts each) and tier auras; the stolen cryptid's walk-in through
   fences (it passes through them, like a bought one).
10. **Poacher**: a server-pivoted 5-Part model at 10 Hz reads as sneaking; the 10 s warning is noticed;
    the refusal to place traps under a walking poacher does not read as a bug.
11. **Performance** with 8 lairs and 8 pockets on a phone (worst lair measured 242-244 Parts headless),
    now with up to 9 cage PointLights per lair and 3 anchor lights per pocket.
12. **Tier colours** under the modified preset, and colour-blind readability with the text labels.
13. **HUD text**: the legibility gate is an estimate (0.55 em per character is an assumption). A
    photograph at 844x390 settles it. Whether the join-time State reaches a client that has not
    connected yet (Roblox queues remote events; the emulator does not: the walk's HUD filled on the
    next once-a-second push, 1.0 s after joining). The lock-wait toast arrives before the HUD exists.
14. **The first 60 seconds** with a person who has never seen it.
15. **DataStore on a published place**: lock handoff (does an old server's leave-write land inside the
    15 s join wait?), the re-check every 15 s against request budgets, write throttling (a grant forces
    a write on top of the 7 s flush), the not-saving, load-failed and changed-save banners, "Saving your
    steal" wait times.
16. **Pacing feel**, and whether tier 4's 0.30 s padded window is hard or unfair.
17. **The BillboardGuis** (MaxDistance 50-120, AlwaysOnTop off): clutter, legibility.
18. **Streaming.** `default.project.json` does not set `Workspace.StreamingEnabled`, and pockets sit at
    x >= 4000. If the published place streams, a server teleport into a pocket (or home) may land before
    the floor streams in. Both second-round reviewers flagged it; the emulator does not model streaming.

## Known gaps (not defects fixed, not Studio questions)

- **Road part budget scales with MaxPlayers.** At the design's place setting of 8 players it is inside
  budget (60 of 100 at the emulator's 12); a reviewer probe at MaxPlayers 50 measured 212 road Parts
  and 50 plots. Set the place's MaxPlayers to 8 before publishing.
- **No player-to-player collision groups** in pockets (a teleporting exploiter could body-block a gap).
- **Carry speed**: the trusted cap while carrying is 16.2 studs/s, above the walk speed of 16.
- **A rejoin to the SAME server within a load window** could have the first join's late lock release
  clear the new session's lock until that session's next write.
- **Freezes of a second or more** can still stop the slide (a raider straight behind a rock); the
  pull-back then costs the player a walk round. Measured: 329 of 33 482 phases at 1.0 s, 4 708 at 1.5 s.
- **`Random` is not a cryptographic generator.** Recovering the camp stream's state from brute-forced
  31-bit seeds, with other players drawing in between, was not attempted. A camp's own seed is still
  recoverable from its layout; that shows nothing the camp does not.
- **A LOAD_FAILED session never retries in the background**, and a locked session whose old server
  writes a final save after the 15 s wait stays unsaved until the player rejoins.
- **No reviewer has seen the second pass's changes** (see State).

## Files

```
default.project.json            Rojo: src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
REVIEW-1.md                     the second review round: ten findings, evidence, fixes, mutation table
src/shared/Config.luau          every tunable
src/shared/Rng.luau             verbatim fork-tower
src/shared/Fx.luau              verbatim fork-tower
src/shared/FxClient.luau        verbatim
src/shared/Responsive.luau      verbatim
src/shared/Economy.luau         prices, jars, cages, heat, permits, bounty, the profile's shape
src/shared/Offers.luau          the three pedestals
src/shared/Layout.luau          grid, lair + camp generation, reachability, placement, cell validation, escape, danger rects, free rects + barriers, grab reach
src/shared/Heist.luau           laser timing, the catch test (per segment and per path), the raid solver (timed route)
src/shared/Trace2D.luau         the trusted position: step (slide, stuck time), settle
src/shared/Poacher.luau         the NPC's route, caution and stepping
src/shared/CryptidModel.luau    the eight procedural models
src/server/Main.server.luau     everything that touches the engine
src/client/Hud.client.luau      the HUD
tests/*.spec.luau               one per shared module (+ Rng, Responsive)
tests/walk.luau                 the player's path through the real HUD, join to a second loop
../robloxemu/check_stealacryptid.luau         world / spawn / reach / raid / security gate
../robloxemu/check_stealacryptid_guards.luau  one block per review finding (G1-G24)
../robloxemu/check_stealacryptid_hud.luau     HUD fit (hudcheck) + text legibility
```

## Next

1. Open it in Studio (00:00-06:00 night job) and work through Needs Studio, starting with 1, 3, 4, 6,
   8, 13 and 18.
2. An adversarial review by a separate reviewer of the second pass's changes (REVIEW-1.md).
3. Port `econ.py` pacing and `success.py` into a Luau measure.
4. Only then: create the experience (MaxPlayers 8), the maturity questionnaire, a git-ignored publish
   script.
