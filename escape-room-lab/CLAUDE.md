# CLAUDE.md — Escape Room Lab (Roblox)

Context so a fresh session can continue. Sibling of `deep-vein/`, `lost-found-depot/`, `plus1-jump/` and
the rest; same stack (one Config, pure logic in `src/shared` tested from the luau CLI, an authoritative
server, a phone-first HUD, `robloxemu` headless gates). Built 2026-09-30/10-01 from `DESIGN.md` (read it
first: every number in it carries its source). The finish line is `docs/complete-game-standard.md`; the
status of every item is in `EYECANDY.md` §0.

## What it is
You ride a lift from the Atrium into a sealed room whose exit door is a Code Lock (3 or 4 distinct digits,
sentence clue lines). Some lines are dark until you solve a feeder station on the walls: a Lamp Grid
(lights out, all lit) or a Flask Shelf (the one order the clue sentences allow). The keypad accepts
nothing until every line is lit. 15 rooms in 5 wings, then the Roof (the brag moment). Stars per room:
Escaped (in a pair only if you completed a station yourself), Clean (no wrong try), Unaided (no hint);
best per room, 45 in all; in a pair, Clean and Unaided are the pair's (a wrong try or a hint by either costs
both). Solo, or two players via the Pair Lift. Nothing costs Robux.

## State — every headless gate green; NEVER OPENED IN STUDIO; NOT published; NOT committed
Last run of every gate on the final source: 2026-10-01, after the second adversarial review's fixes
(`REVIEW-1.md`). All 31 gates were run 6 times in a row (rooms are random): 0 failures in 186 runs. `luau` is the CLI at the session
scratchpad (`.../scratchpad/luau/luau.exe`); it writes to stderr, so ALWAYS append `2>&1`.

**Rebuild the bundle before every headless run**, or you test the last build, not the source:
`cd ../robloxemu && py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau`

| gate | command (from `escape-room-lab/` unless it says robloxemu) | result |
|---|---|---|
| Text | `luau tests/Text.spec.luau` | 1346 passed, 0 failed |
| CodeLock | `luau tests/CodeLock.spec.luau` (1000 doors per 3-digit kind, 120 at 4 digits) | 90 / 0 |
| Shelf | `luau tests/Shelf.spec.luau` (1000 shelves per size) | 54 / 0 |
| Lamps | `luau tests/Lamps.spec.luau` (400 grids per size and k) | 66 / 0 |
| Lab | `luau tests/Lab.spec.luau` (the V4 table room for room, stars, Continue, progress) | 173 / 0 |
| Profile | `luau tests/Profile.spec.luau` (sanitize vs hostile records) | 49 / 0 |
| Board | `luau tests/Board.spec.luau` (encoding incl. 0 stars and any reach time, partial view, `readStep`) | 68 / 0 |
| RoomView | `luau tests/RoomView.spec.luau` (the payload key allowlist) | 52 / 0 |
| Decor | `luau tests/Decor.spec.luau` | 51 / 0 |
| EnvConfig | `luau tests/EnvConfig.spec.luau` (bands, hazards probe incl. the dodge window from the ring's first frame, rest) | 203 / 0 |
| Pacing | `luau tests/Pacing.spec.luau` (the brag minutes; hazards met on the way) | 11 / 0 |
| templates, verbatim | `luau tests/EnvBands.spec.luau`, `Hazards.spec.luau`, `Rest.spec.luau`, `responsive.spec.luau`, `Rng.spec.luau` | 124 / 111 / 55 / 70 / 32, 0 failed |
| the walk | `luau tests/walk.luau` (two rooms through the real HUD; the rider's own Solo Lift doors) | 37-38 / 0, exit 0 in all 6 (one assertion per door line read; every room is freshly generated) |
| world, spawn, prompts, board | `cd ../robloxemu && luau check_escaperoomlab.luau` | 116-117 / 0 (the count follows room 1's random puzzle) |
| HUD fit, overlap ON | `cd ../robloxemu && luau check_escaperoomlab_hud.luau` | PASS, 60 viewport x mode measurements, 712 overlay controls contained, 0 spill |
| eye candy over 15 rooms | `cd ../robloxemu && luau check_escaperoomlab_env.luau` | 114 / 0 |
| hazards and the Break; the ring fixed from its first frame; no backlog at the door or the grace's end | `cd ../robloxemu && luau check_escaperoomlab_hazards.luau` | 64 / 0 |
| nothing leaks | `cd ../robloxemu && luau check_escaperoomlab_leak.luau` | 45 / 0 |
| save, lock, board writes, a failed load retried | `cd ../robloxemu && luau check_escaperoomlab_save.luau` | 41 / 0 |
| the release on leave vs a save in flight; a leave while the LOAD is in flight | `cd ../robloxemu && luau check_escaperoomlab_release.luau` | 22 / 0 |
| the Pair Lift; the pair's shared Clean/Unaided stars | `cd ../robloxemu && luau check_escaperoomlab_pair.luau` | 53 / 0 |
| the lifts: Solo doorway never shut for others, ATRIUM hold, the Roof, idle pad players, who is aboard at departure, NEXT during the ride | `cd ../robloxemu && luau check_escaperoomlab_lifts.luau` | 55 / 0 |
| the friends board under load | `cd ../robloxemu && luau check_escaperoomlab_friends.luau` | 16 / 0 |
| a lamp hint through the real HUD | `cd ../robloxemu && luau check_escaperoomlab_hint.luau` | 14 / 0 |
| the Act remote | `cd ../robloxemu && luau check_escaperoomlab_act.luau` | 25 / 0 |
| the part cap in code | `cd ../robloxemu && luau check_escaperoomlab_budget.luau` | 5 / 0 |
| syntax, no string require, no attribute writes | `cd ../robloxemu && luau check_escaperoomlab_compile.luau` | 21 sources, 63 / 0 |
| analysis | `luau-analyze` | **NOT RUN**: luau-compile.exe and luau-analyze.exe are not on this machine (only luau.exe); the compile check above is the loadstring half |

`robloxemu/check_escaperoomlab_lib.luau` is shared helpers for the checks, not a check. The emulator runs ONE
harness per process: a check that needs a differently wired world (the release race's UpdateAsync latency) is
its own file.

**Mutation sweeps.** First sweep (2026-10-01, build): 40 mutations, **40 KILLED**; the control (the Atrium
directory's title text) survived all 27 gates of the time. Review sweep (2026-10-01, after the fixes below): 19
mutations of the fixed code (scratch copies; the game never edited), **19 KILLED**; the same control **survived
all 31 gates**. One review mutant survived at first (M1: the release keeps its token AND the transform skips
the `releasing` check): the release check only left BEFORE an autosave tick, where the early return already
stops the tick's save. A third case (leave 0.1 s AFTER the tick, the tick's save 0.5 s, the release 0.1 s) now
kills it. Either guard alone holds; that redundancy is deliberate. The list is `EYECANDY.md` §7.
Second review sweep (`REVIEW-1.md`, after its fixes): **24 of 24 KILLED** (22 of the fixes, and the first sweep's two
leak mutants re-run against the re-scoped leak gate), two controls (the directory title, the rider's door
colour) **survived all 31 gates**, each mutant proved present in the bundle the gates ran.

**Second adversarial review (2026-10-01, `REVIEW-1.md`)**: 9 findings. Closed, each red first: an idle player on a
Pair Lift pad blocked every pair (A1); the first review's shared Solo Lift door could be held shut by riders on
a loop (A2; the doors are now each rider's own local part, and the server checks at departure who is aboard);
a leave during an in-flight load left the lock taken (A3); one partner could absorb every hint and wrong try and
hand the other 3 stars (A4; Clean and Unaided are now the pair's); stepping out of the ring dodged only
1.45-2.05 s after it showed (B1; the lane now locks on its first frame); a pair partner who walked away during
the ride was taken (B2); a second NEXT press was told "The door is still shut." (B3); hazards backed up at the
door and fired as the next room's grace ended (B4; the clock now runs only where one may be released, interval
80-120 s to keep one per 2-3 minutes of play). Not changed: the public board freezes once ten players reach 45
(B5), which is what the owner's standard prescribes; an owner decision.

**First adversarial review (2026-10-01)**: two reviewers probed the build in scratch copies. Confirmed and fixed, each
with a failing gate first (the red counts are in `EYECANDY.md` §7):
1. One failed load call left `canSave` false for the session, the stored stars hidden (veteran: HUD 0 of 11,
   room 1; 1 store call in 10 healthy minutes). Now retried every autosave tick, progress merged and saved.
2. A save in flight with the leave's release re-took the lock for 45 s: an immediate rejoin got 0 stars,
   `canSave` false, "open on another server". The release is now final.
3. A second player standing in the Solo Lift ("One at a time") held everyone in the Atrium: a griefer blocked
   every solo ride. Now each rider gets a room of their own.
4. The friends board: 41 presses = 11 GetFriendsAsync calls, 1005 GetAsync reads, 6 in flight. With the
   request budget modelled so the game sees it (a scratch patch of the emulator, 80 reads/min for 2 players):
   11 calls, 662 reads (195 friends read twice), 15 reads under the reserve of 10, and an honest player's
   200-friend view took 443 s. Now single-flight per player and one reader per server, same probe and patch:
   2 calls, 400 reads, none twice, 1 in flight, 0 under the reserve (lowest budget 10.3), honest view 247 s.
5. A 0-star player showed on the friends board with 1 star (`starsAt = 0` encoded to 2e9). Found by the new
   friends check. `Board.encode` stores 0 stars as 0 and clamps the reach time.
6. A solo escapee who took ATRIUM from room 15 and then the Roof door never got the brag card or the server
   announcement. Now the first Roof arrival plays it, either way up.
7. A pair riding up from room 15 was told "Ann went back to the Atrium. Carry on solo." The party is now
   dissolved as a whole.
8. A lamp hint's ring and banner stayed after the hinted press; pressing the ringed lamp again undid it.
9. The HUD says "Stand inside and the doors close": the Solo Lift had no doors, and a rider who walked out
   during the ride was still taken. The doors now shut for the ride.
10. On arrival the entry cab's ATRIUM button is the only prompt in reach (3.8 studs); it now needs a 0.5 s hold.
Accepted residual, measured: a solver script reached 45 stars 62 s after joining. With ties to the first to
reach 45, a bot that gets there before ten real players keeps a top-10 public row for good (DESIGN.md §11.2
said "until ten real players reach 45"; corrected there).

## Traps this game has (check them every time)
1. **The door gate.** The keypad refuses every code while a line is dark, right or wrong, and judges
   nothing (no lockout, no wrong try). Without it the visible lines leave 2-252 codes to guess among.
   `check_escaperoomlab` tries every code of room 1's space against a dark door.
2. **Hidden line text is server memory until its feeder is solved.** Never in the world early, not even in
   a hidden TextLabel or a disabled SurfaceGui: both replicate. The board's dark row shows `? ? ?` and which
   station lights it. `check_escaperoomlab_leak` searches everything replicated before each solve.
3. **Hints go to the taker only** (`FireClient`), never into the world. `check_escaperoomlab_pair`.
4. **`ctx.pitch = math.rad(85)` must reach `Hazards.step`** (Lab.client). Pass the camera's pitch instead
   and lanes start up to 11.6 studs sideways, through the walls (mutant C1).
5. **`Rest.IdleSeconds = 0` is deliberate**: standing still is how a puzzle is thought through. The
   template's 20 would switch hazards off at every station. `EnvConfig.spec` pins it.
6. **Exactly one enabled SpawnLocation** (AtriumSpawn), built before `PlayerAdded`; `RespawnLocation` is
   set first thing in `PlayerAdded`; `CharacterAdded` writes no CFrame and never yields. With no enabled
   spawn a new player starts on the Roof deck at y 150 (the highest ground over the origin).
7. **`Config.Studio.StartSlot`** is honoured only when `RunService:IsStudio()` AND the profile cannot save.
8. **Profile keys are the strings "1".."15"**, and a key PRESENT means the room was escaped: a carried
   escape in a pair stores 0 and still advances the frontier (DESIGN.md said "frontier = first room with
   best 0", which would have stranded a carried player; see "Deviations").
9. **The board write comes after the profile write lands, through `UpdateAsync` keeping max(old, new).**
   `Board.decode` is exact for reach times 2026-09-21..2090-01 (`Board.EPOCH`); the order holds either way.
10. **Rebuild the bundle before every headless run** (deep-vein's lesson).
11. **A required module in the luau CLI has its own globals**: the harness's fake `Enum`/`CFrame`/`Vector3`
    are not visible inside `check_escaperoomlab_lib.luau` unless handed over (it takes them at boot).
12. **The hazard's ring draws on a reserved share of the local part budget.** Under a full budget it was
    skipped once (found by `check_escaperoomlab_budget`): a hit with no telegraph. Keep `reserved = true`
    on the hazard's parts.
13. **Unseeded `Random` in the emulator is clock-seeded**: a gate that searches for a random answer must
    scope its search, or it is flaky (see the sweep above). The leak gate's search for the door code's ARRAY
    form skips the shelf's public `flasks` field: colours are 1-5, so an order like [1,4,3] can equal a code
    (REVIEW-1: one false positive in about 140 runs).
14. **The release is final.** `saveNow(plr, true)` sets `releasing` before its write, writes the lock with
    session `""` and `until = 0`, and every other write of that session returns early or aborts in its
    transform. Never write the session token on release (`check_escaperoomlab_release`, case 3).
15. **A failed load CALL is state "retry", not "nostore".** "nostore" is only for a server with no DataStore.
    The autosave loop retries "locked" and "retry"; a successful retry merges and saves within CoalesceSeconds.
16. **`Board.encode(0, ...)` is 0, and the reach time is clamped to [EPOCH, EPOCH + 2e9 - 1].** A 0-star
    `myValue` used to read as 1 star on every friends board.
17. **Friend reads go one at a time per SERVER** (`readerBusy`), and a player's fetch is single-flight and
    never aborted by a toggle. Several concurrent readers all pass the budget check at once.
18. **The Roof arrival is one function** (`arriveRoof`) for room 15's lift and the Atrium's Roof door. Room
    15's lift dissolves the party whole (`removeMember` toasts "went back to the Atrium").
19. **Everyone in the Solo Lift rides alone.** Do not bring back "One at a time": one player could hold every
    solo ride. **The doors are the rider's own**: Lab.client makes a local `SoloDoorLocal` on its own ride notice
    (`lift = "solo"`) and opens it at the next RoomState. Never put a collidable door on the server: two riders
    on a loop held the shared one shut 99% of the time (REVIEW-1 A2). `aboard()` checks at departure that each
    rider is still in the Solo Lift (or the Pair Lift); anyone else stays in the Atrium and is told why.
20. **The Pair Lift's partner is a GO-presser on the OTHER pad** inside the window, the earliest first. Never let
    a player who merely stands on a pad block or join anyone (REVIEW-1 A1). "full" is only for a third player
    during a countdown; one of the departing pair is told it is leaving.
21. **Clean and Unaided are the pair's** (`markTeam`): a wrong try or a hint marks every member, the mark stays
    when one leaves (`party.shared`), and the lost star reaches both (a hint resends RoomState to the party; the
    hint TEXT still goes to its taker only, trap 3). Per-player marks let a partner launder them (REVIEW-1 A4).
22. **A session that is gone never takes the lock**: `onPlayerRemoving` sets `s.gone` first; the load transform
    aborts on it, and a load that landed for a gone session releases what it took (`releaseGone`). Either guard
    alone is tested (`check_escaperoomlab_release` gives the fallback write 5 s in the "late" case).
23. **The hazard lane locks on its first frame** (`commit = telegraph`, Config only): a 4 studs/s drop touches the
    3.5-stud zone 0.875 s before arrival (at 2.13 s), so the template's 1.5 s of tracking left no dodge window
    before 1.45 s. **The hazard clock runs only where one may be released** (a legal spot past the grace): run
    anywhere else and a due hazard is HELD and fires the instant the player steps out (REVIEW-1 B4). The
    interval (80-120 s) is calibrated to that exposed time; re-measure it (Pacing.spec, a full path) if either
    rule changes.

## Deviations from DESIGN.md, each with its reason
- **One server file.** `robloxemu`'s harness can only `require` shared modules, so the design's server
  modules (RoomBuilder, Store) live in `Main.server.luau`; the payload builder moved to a pure shared
  module, `RoomView.luau`, so its allowlist is unit-tested and the HUD check can build a worst-case room.
- **Two new remotes.** `Open` (S->C, `{ station }`): the server answers a station's ProximityPrompt after
  its own reach check, and the HUD opens that overlay. `Hello` (C->S, no payload): the HUD asks for its
  state once its handlers are connected (Roblox queues early events, but a HUD that loads after the first
  Profile must not start blank; mutant H5 shows the walk starts blank without it). Neither carries a
  star, a result, a time or a position.
- **`ClientBus.luau`**: Hud.client owns every 2D control and forwards RoomState/Profile/Notice; Lab.client
  owns the world, hazards and the Break. One layout decides where everything goes.
- **A carried escape stores 0** (trap 8). Stars and the frontier are both derived from `best`.
- **The overlay's height is capped at 46% of the screen** (portrait phones covered 61% otherwise, over
  hudcheck's 50% rule), and the door keypad picks 3, 4 or 6 columns to fit, every key a full tap target.
- **Decor is shown in rooms and on the Roof, not in the Atrium** (the Atrium is 64 x 48 and 20 tall; the
  room decor is authored for 32 x 32 x 16). The Atrium keeps band 1's light, dust and flies.
- **Hazards.luau is plus1-jump's CURRENT file** (md5 f36a9ac2..., with `threatLive`, 2026-09-30), not the
  c2775461 the design quoted; its spec is the one plus1-jump ships with it (2f42278c).
- **Server props** are 2-3 parts each in four slots; room parts measured 52-75 (cap 160).
- **Review fixes (2026-10-01)**: the Solo Lift takes everyone in it, each alone (DESIGN.md §16.1 said "One at a
  time"); the Solo Lift has real doors; the rooms' ATRIUM buttons need a 0.5 s hold; a failed load is retried
  (DESIGN.md §12.1 had one toast and no retry); the no-friends note says how to get friends on the board;
  a partial friends view (request budget) says "Checked N of M friends"; `Board.encode` stores 0 stars as 0.
  The DESIGN.md passages they contradict (§11.2, §11.4's empty text, §12.1, §16.1) carry a [build] note.
- **Second review fixes (2026-10-01, `REVIEW-1.md`)**: the Solo Lift's doors are the rider's local part, never a
  server part; both Atrium lifts take only who is aboard at departure; the Pair Lift ignores anyone who did not
  press GO; Clean and Unaided are shared in a pair (DESIGN.md §4.3 had them per player); the hazard lane locks on
  its first frame and the clock runs only on a legal spot past the grace (DESIGN.md §8.2 had tracking for 1.5 s
  and a held hazard); the interval is 80-120 s, not the template's 120-180 (one per 2-3 minutes of PLAY, see
  §8.2). The passages they contradict (§4.3, §4.4, §8.2, §11.2, §14.2, §16.1) carry a [review-1] note.

## Files
- `src/server/Main.server.luau` — world (Atrium, Roof, zones), rooms (generation in server memory, the
  build), Act, prompts, lifts (who is aboard at departure, the Pair Lift's partner), save/lock (load retry,
  final release, no lock for a session that is gone), the public board, friends (on demand, single-flight,
  one reader per server).
- `src/client/Hud.client.luau` — the phone-first HUD: star chip, Break, banner, cards, the station overlay,
  the local friends face on the board.
- `src/client/Lab.client.luau` — bands, lighting glide, decor, creatures, weather, hazards, the Break,
  title cards, the guide arrow, the Roof's fireworks and shooting star, the rider's own Solo Lift doors.
- `src/shared/` — Config, CodeLock, Shelf, Lamps, Text, Lab, Profile, Board, RoomView, Decor, ClientBus;
  templates verbatim: EnvBands, Hazards, Rest, Responsive, Rng (fork-tower's, with `below`), FxClient;
  Fx is anomaly-observatory's plus one preset, `Fx.Presets.Lab` (= band 1).
- `tests/` — the specs above, `LabModel.luau` (pacing), `walk.luau`.
- `design/` — `model.luau`, `hazard_probe.luau` (design-time only).

## What is NOT done
- The public board freezes once ten players reach 45 (REVIEW-1 B5): the owner's standard prescribes the
  first-reach tie-break; a seasonal board or another change is the owner's decision.
- Studio: nothing here has been rendered; the needs-Studio list is `EYECANDY.md` §8.
- No universe, no publish script (`.gitignore` already covers `publish_*.bat` / `publish_*.sh`).
- `tools/film_game.py` has no scenarios for this game yet (tools/ belongs to its owner): `MARKETING.md`.
- `luau-analyze` not run (not installed).
- Audio, badges, Night Shift: cut from v1 (DESIGN.md §21).
