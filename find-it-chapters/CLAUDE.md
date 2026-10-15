# CLAUDE.md: Find It! Chapters (Roblox)

Context so a fresh session can continue. Sibling of `escape-room-lab/` and `plus1-jump/` (same stack: one Config,
pure logic in `src/shared` tested from the CLI, an authoritative server, a phone-first HUD, `robloxemu` headless
gates). Built 2026-10-07 from `DESIGN.md` (read it first; every number there carries its source). The finish line
is `docs/complete-game-standard.md`; the status of every item is `EYECANDY.md` §0.

## What it is
A hidden-object game in chapters. A cluttered room is built fresh for every attempt, with a list of 3-9 things;
each hides in one of the k (3-5) props that fit its clue ("a BLUE BOX", "something YELLOW up HIGH"); no prop fits
two clues. Tap a prop to look, tap again to search (1.0 s, one look of n*k+2). Find the list before the clock and
the looks run out. Stars: Found, Swift (inside 2/3 of the clock), Sharp Eye (at most one off-clue search, no hint).
15 chapters in 5 bands; BOOK ONE SOLVED is the brag (normal p50 34.1 min, model). After chapter 3 a Daily Case
opens every UTC day. The board ranks Cases Solved (chapters + Daily Cases, at most one a day). Nothing is sold.

## State: every headless gate green (33); two review rounds closed (`REVIEW-1.md`); NEVER OPENED IN STUDIO; NOT published; NOT committed
No universe, no publish script (`.gitignore` already covers `publish_*.bat` / `publish_*.sh`). Studio work is the
night shift's (00:00-06:00): `EYECANDY.md` §8 is its list, §9 the thumbnails, `MARKETING.md` the clips.

## The runtime (read this before trusting a number)
On 2026-10-07 the luau CLI was gone from the session scratchpad (`.../scratchpad/luau/` was empty) and no
`luau.exe` exists on C:, D: or in WSL; a download needs the owner's go. Every gate below therefore ran under
**luaujs**, a Luau runtime written for this session in Node (`.../scratchpad/fic_luaujs/`: a Luau parser, a
compiler to JS generator functions, the runtime and the standard library; `node luau.js <file>` from the same
directory layout). It reproduces the luau CLI's semantics this repo relies on: `require` relative to the
requiring file, each module in its own sandboxed globals, `loadstring` bound to the calling thread's globals,
load-time import caching of globals (except `game`, `workspace`, `script`, `_G`, ...), the inlined `typeof`,
coroutines (the scheduler), Lua patterns, `string.format`, `bit32`, Luau's sort. **Validated before use** against
suites with recorded results: plus1-jump's 12 specs give exactly the recorded 696 assertions and its 22 headless
checks the recorded 645 + PASS; robloxemu's own 4 specs give 249/153/21/189 (services.spec's 189 is the count
SPAWN-ORDER.md records). It is still not the real CLI: **when luau.exe is back, re-run every gate under it.**
`luau-compile` and `luau-analyze` were never available (as for escape-room-lab); the compile gate below is the
loadstring half.

## Gates (rebuild the bundle first, every time)
`cd ../robloxemu && py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau` (the checks and the
walk read the bundle, not `src/`). `L` = the runtime (`luau` when it is back, else `node .../fic_luaujs/luau.js`);
append `2>&1`. Counts are from the last full run (2026-10-08, after REVIEW-1 round 2).

| gate | command | result |
|---|---|---|
| Clue | `L tests/Clue.spec.luau` | 49 / 0 |
| Dressing | `L tests/Dressing.spec.luau` (4800 rooms + 3000 for the id/position tests; ~35 s) | 262 / 0 |
| Attempt | `L tests/Attempt.spec.luau` (incl. chi-square over 30 000 hides; the A4 pause window; the C2 break cap) | 120 / 0 |
| Ledger | `L tests/Ledger.spec.luau` (incl. C2: every rise stamped with its UTC day; D6: the Gold Book) | 94 / 0 |
| Board | `L tests/Board.spec.luau` (incl. A5 ties: a shared rank) | 78 / 0 |
| Bands | `L tests/Bands.spec.luau` (incl. D2/D3: critters, weather and the dome slit visible from inside the room) | 278 / 0 |
| Pick | `L tests/Pick.spec.luau` | 25 / 0 |
| Config | `L tests/Config.spec.luau` (design-critical numbers pinned) | 132 / 0 |
| Pacing | `L tests/Pacing.spec.luau` (`FinderModel.luau` on the real rules, hazards on a legal spot only (D5); ~50 s) | 51 / 0 |
| templates, verbatim | `L tests/EnvBands.spec.luau`, `Hazards.spec.luau`, `Rest.spec.luau`, `responsive.spec.luau`, `Rng.spec.luau` | 124 / 111 / 55 / 70 / 32, 0 failed |
| the project file (B5) | `py -3 tests/project_check.py` (StreamingEnabled pinned off; the Rojo mapping) | 5 / 0 |
| the walk | `L tests/walk.luau` (join -> Chapter 1 -> Next -> Chapter 2 with a Pause, through the real HUD and Room client) | 44-60 / 0 (one assertion per tapped prop) |
| world, spawn, prompts, board, the path | `cd ../robloxemu && L check_finditchapters.luau` | 137 / 0 |
| HUD fit, overlap ON, 36 px topbar | `cd ../robloxemu && L check_finditchapters_hud.luau` (the sweep is `check_finditchapters_hudlib.luau`, 14 modes) | PASS: 140 viewport x mode measurements, 1860 controls contained, 0 spills, 30 Case Book menus with >= 3 rows |
| HUD fit, overlap ON, 58 px topbar (B4) | `cd ../robloxemu && L check_finditchapters_hud58.luau` | PASS: the same counts |
| eye candy over 15 chapters + a Daily; rotation; the gold Case Book; the re-dress; critters and weather inside the room; the ship's storm | `cd ../robloxemu && L check_finditchapters_env.luau` | 361 / 0 |
| drops, the ring, the Pause (incl. the A4 window) | `cd ../robloxemu && L check_finditchapters_hazards.luau` | 51 / 0 |
| the predictor check, allowlists, planted leaks | `cd ../robloxemu && L check_finditchapters_secret.luau` | 143 / 0 |
| every defended row of DESIGN.md §14 | `cd ../robloxemu && L check_finditchapters_cheat.luau` | 42 / 0 |
| the board, public and friends | `cd ../robloxemu && L check_finditchapters_board.luau` | 23 / 0 |
| syntax, no string require, no attribute writes | `cd ../robloxemu && L check_finditchapters_compile.luau` | 22 sources, 66 / 0 |
| B1 the lectern then a menu tap; A6 refusal floods; A4 pause/resume cycles | `cd ../robloxemu && L check_finditchapters_remotes.luau` | 33 / 0 |
| A1-A3: a clear survives a leave, a shutdown, a failed write, a retrying load | `cd ../robloxemu && L check_finditchapters_save.luau` | 49 / 0 |
| BOOK ONE SOLVED on a phone: card, the dome slit SEEN to open (rays), stars, notice, tag, gold book, board, rejoin | `cd ../robloxemu && L check_finditchapters_brag.luau` | 34 / 0 |
| C1: a clear the release carries reaches the board (leave, shutdown); D6: the Gold Book through the server | `cd ../robloxemu && L check_finditchapters_release.luau` | 19 / 0 |
| C2: the board across a faked UTC midnight; the break cap closes a paused room | `cd ../robloxemu && L check_finditchapters_midnight.luau` | 35 / 0 |
| C3: a server hop onto a still-held lock (3 autosave phases + a lock held for good) | `cd ../robloxemu && L check_finditchapters_hop.luau` | 38 / 0 |
| C4: a write that answers 9 s late never rolls the session back | `cd ../robloxemu && L check_finditchapters_race.luau` | 8 / 0 |
| D1: the Leave button; D4: Hub after a refused Next, Next remembered while a clear saves | `cd ../robloxemu && L check_finditchapters_exit.luau` | 30 / 0 |

Rooms and secrets are random (server entropy): run a new gate several times. `.../scratchpad/fic_gates4.sh <game>
<robloxemu>` runs all 33 and prints one line each (~3 min).

**Mutation sweep** (`EYECANDY.md` §7, scratch copies only): rounds 1-2 (`fic_mutate.py`): 24 mutants, 23 killed,
1 equivalent (M7: a CharacterAdded CFrame write the engine discards). Round 3 (`fic_mutate3.py`, the REVIEW-1 fixes):
17 mutants, 17 killed (R3 after its assertion was tightened). Round 4 (`fic_mutate4.py`, the round-2 fixes):
`REVIEW-1.md`. The controls survived every round. Final counts and repeat runs: `REVIEW-1.md`.

## Traps this game has (check them every time)
1. **The room payload is built and SENT before the secret is drawn**, and must not depend on it
   (`startAttempt`: `Dressing.build` -> `Dressing.payload` -> `Room:FireClient` -> `Attempt.hide`).
2. **Ids and positions are dealt after a shuffle**, never in generation order (`Dressing.spec`, mutant M1).
3. **A hit and a miss are answered after the same 1.0 s** (`Attempt.spec`, mutant M2).
4. **Found items and the room are built by the owner's client only**; other players never receive a Room payload.
5. **A re-dress keeps each item's unsearched-candidate count and never touches the looks**; ids continue after
   the old room's, so a pre-pause id is "not in this room" (`Attempt.spec`, mutant M16).
6. **Nothing about an attempt is persisted** (`Ledger` has no field for it; `Ledger.spec` pins the key set).
7. **The Daily credit is decided inside the atomic clear transform, by the day the attempt STARTED**
   (`att.startDay`, `Ledger.applyClear`; mutant M6), but **every rise's board stamp is the start of the UTC day it
   happened on**, chapter or Daily, never the start day (`Ledger` `rise`; REVIEW-1 round 2 C2). The break cap
   (trap 27) bounds how far after midnight a start-day credit can land (~14 min for a Daily).
8. **The board is written only after the profile write lands, and only on a rise** (mutant M13), **including after
   the release write on leave and in BindToClose** (round 2 C1).
9. **`CharacterAdded` never writes a CFrame**; HubSpawn is the one enabled spawn; RespawnLocation is the first line
   of PlayerAdded (mutants M7b, M8; a bare CFrame write, M7, is discarded by the engine and survives as an equivalent mutant).
10. **Where no drop may come, the glue passes `resting = true`** (the door mat, the intro, a pause, a finished room):
    a due drop is never held and fired later (mutant M10). `ctx.pitch` is ALWAYS rad(85) (mutant M9).
11. **The attempt clock is a Heartbeat sum; DataStore pacing and rate limits are wall time (`tick()`).** A loop that
    `task.wait`s on the Heartbeat sum spins inside one emulator frame (it did: "advance() did not converge").
12. **Star keys are strings** (`c1`..`c15`).
13. **The Studio shot room** (`Config.Studio.ShotSeed`, `Config.Studio.Cleared`) is honoured only when
    `RunService:IsStudio()` is true and the session cannot save; a live server never takes it (`check_finditchapters`).
14. **`typeof(x) == "Instance"` is always false in robloxemu** (instances are tables; the compiler inlines `typeof`).
    A teardown guarded by it was a silent no-op headless: rooms piled up to 191 parts (found by the walk). Do not
    guard Instance code with `typeof`.
15. **A line that starts with `(` continues the previous expression** (`x = a or (b)` then `(c :: any)[k] = v` is a
    call): it failed to compile. Start such lines with a local, not a parenthesis.
16. **`ParticleEmitter:Emit` is not modelled in robloxemu**: call it inside `pcall` (as labyrint-spill does).
17. **The HUD's panels never overlap**: a card, the callout and the menu share ONE centre slot and hide the list and
    the selection bar; on a touch screen the menu is capped at 42% of the screen height (hudcheck rule 5), except
    on a narrow one (trap 21).
18. **The payload key allowlists in `check_finditchapters_secret`** fail on any new key: review it, then add it.
19. **The clocks are derived, not chosen**: `Pacing.spec` fails if `Config.Chapters[*].clock` / `Config.Daily.clock`
    differ from the normal profile's p97 (ch1-3) / p90 (ch4-15) / p98 (Daily) on the real layout, rounded up to 5 s.
20. **The topbar is read, not assumed** (`GuiService:GetGuiInset`, 36 or 58 px): the HUD gate runs twice
    (`_hud` at 36, `_hud58` at 58), one CLI process each (the harness installs once per process).
21. **The Case Book on a narrow touch screen runs the middle column's full height** and the banner moves to the left
    column while it is open; elsewhere it is capped at 42% of the screen. Close sits in the title row.
22. **A room is a closed box: nothing beyond its walls is ever seen.** Critters and weather emitters stay INSIDE
    the room (round 2 D2: the ship's fish and rain and the greenhouse drizzle used to be beyond the east wall, and the
    Sky's stars are never visible). Rain and drizzle run down glass (`RoomArt.weatherSpots`): in the portholes' window
    boxes and on the greenhouse's north glass, and no streak falls below `RoomArt.DECOR_HIGH` (never over a prop).
23. **After a re-dress the next Pause waits `Config.Pause.EverySeconds` (30) of clock** (REVIEW-1 A4): server
    (`Attempt.pause` -> "soon", `Attempt.pauseIn`) and client (`pauseWait`) both; `State.pauseIn` carries the wait.
24. **Every clear is queued (`s.pending`) until a write carrying it lands**, and every profile write folds the queue
    in (REVIEW-1 A1-A3): the clear's own write, the autosave, the load, the release.
25. **Every profile write is numbered when its transform runs (`nextSeq`), and `settle` ignores an answer older than
    the last one applied** (round 2 C4: an autosave answering late rolled the session back a chapter).
26. **A locked or failed first load retries after `Save.QuickRetrySeconds` (3), `QuickRetries` (4) times**, then the
    20 s tick; the lectern's straight-into-Chapter-1 shortcut needs state `ready` or `nostore`, and the HUD's
    Continue row says "Loading" until then; the locked toast says it is retrying, never "won't save" (round 2 C3).
27. **A break is capped at `Pause.MaxBreakSeconds` (600) summed over the attempt** on the server's frame clock
    (`Attempt.breakLeft`, `Attempt.closeBreak`); at the cap the room closes with reason `break` (round 2 C2).
28. **Hub has its own rate bucket (`Limits.Hub`) and a refused Hub has words; the HUD never hides a card before the
    server moves the player; a Next tapped while a clear saves is remembered (`att.nextQueued`) and runs when the
    save lands, unless the player left or retried** (round 2 D4). A live room has a two-tap Leave button (D1).
29. **The dome slit hangs under the opaque dome disc, over a Neon night-sky strip; the brag's shooting stars start
    under the disc** (round 2 D3: a property gate passed while nothing could be seen). Visibility is gated with rays
    in `check_finditchapters_brag`.
30. **The pacing model's hazard clock runs on a legal spot only, as the game's** (`FinderModel.legal`; round 2 D5).

## Deviations from DESIGN.md, each with its reason
- **`Hide.luau` is `Attempt.hide`** (the draw is one function; its secret is the server's entropy, not its code).
- **`Dressing` and `Attempt` are shared modules (ReplicatedStorage), not server ModuleScripts.** robloxemu's harness
  can only require shared modules (escape-room-lab hit the same wall). Their code is public; the secret is the
  draws, made in the server's memory from server entropy, so nothing a client can read predicts them
  (`check_finditchapters_secret`: 8 predictors at chance over 1330 finds).
- **The clocks moved** (DESIGN.md §4 had the design model's uniform points): on the real layout (HIGH props on wall
  shelves, TABLE props on tables) 9 of 15 chapter clocks moved by 5-10 s: 70, 95, 115, 120, 130, 160, 160, 180, 215,
  215, 215, 245, 250, 250, 285; the Daily stays 195. Measured outcomes still meet §10.1 (BOOK ONE SOLVED p50 34.1 min).
- **`Fx.Presets.Agency`** (warm daylight) instead of `Cozy` (a night cavern) for the hub.
- **`Board.luau` is escape-room-lab's** (plus1-jump's plus three review fixes); rows carry `solved`.
- **Remotes**: `AskHint` (C->S) next to `Hint` (S->C), and `Hello` (C->S, no payload: the HUD asks for its state once
  its handlers are connected, as escape-room-lab does).
- **A Pause asked for while a search is in flight waits for the answer**, then pauses (the design did not say).
- **A Daily replayed after today's credit is allowed** (with a toast) and credits nothing.
- **Picking is analytic** (`Pick.luau`: a ray-box test over the room's props, tables as occluders), using the
  engine's `Camera:ScreenPointToRay` for the ray when it exists. The same code runs headless.
- **The floor corners (3.6 studs) are kept for decor**; the greenhouse's "pots" decor is glass roof frames (a pot is
  a searchable kind's silhouette).
- **Friends' names come from the GetFriendsAsync pages** (cached in memory, never stored), saving name calls.
- **`Config.Studio.Cleared`** (new): unlocks chapters in the Studio shot room so later bands can be filmed.
- **The hazard interval is 85-120 s** (DESIGN §8: 100-140), re-measured with the game's legal-spot rule (round 2 D5).
- **The board's reach time is the UTC day, for every rise** (round 2 C2; the standard encodes a unix time: a
  same-day tie shares a rank, so no race at 00:00 UTC). One line in `Ledger` (`rise`) to change if the owner
  wants second-resolution ties back.
- **A break closes the room after 10 minutes** (not in DESIGN §9; round 2 C2).
- **The ship's fish swim in the portholes and its rain runs down them** (DESIGN §7 said "passing a porthole" and
  "on the portholes only"; the first build had put both beyond the wall).

## Files
- `src/server/Main.server.luau`: hub, HubSpawn, lanes, remotes, attempts (draw, payload, secret, Heartbeat clock,
  answers, pause/re-dress), the atomic clear, save/lock, the public board and friends.
- `src/client/Hud.client.luau`, `Room.client.luau`, `Board.client.luau` (see `README.md`).
- `src/shared/`: `Config`, `Clue`, `Dressing`, `Attempt`, `Stars`, `Ledger`, `Board`, `Bands`, `Pick`, `RoomArt`,
  `ClientBus`; templates `EnvBands`, `Hazards`, `Rest`, `Responsive`, `Rng`, `Fx`, `FxClient`.
- `tests/`: the specs, `FinderModel.luau` (pacing), `walk.luau`. `design/`: the design-time Python model.
- `robloxemu/check_finditchapters*.luau` (18 files: `_hudlib` is the HUD sweep the `_hud` and `_hud58` runners call)
  and `robloxemu/build/find-it-chapters.luau` (generated).

## REVIEW-1 (2026-10-07, two adversarial reviewers: exploits/saves and reachability/HUD), every finding fixed
A1 a clear inside the 6 s write gap was lost on leave/shutdown; A2 one failed UpdateAsync lost a clear; A3 (= B6)
clears during a retrying load were not merged; A4 back-to-back pauses re-rolled the room for free; A5 a Daily's
tie went to whoever solved it first after 00:00 UTC (now reached on its day); A6 every refused call of a flood
was answered; B1 the lectern prompt ate the Open bucket, so a quick menu tap did nothing; B2 HubSpawn faced the
back wall; B3 the Case Book list showed under one row on a phone; B4 the HUD assumed a 36 px topbar; B5 streaming
was not pinned off; B7 the Daily door faced the wall; B9 a jump cleared the 6-stud hub walls. Fixed in code with a
test each (`check_finditchapters_save`, `_remotes`, `_hud58`, `project_check.py`, the specs). Found while finishing
the round: rain fell over the props in the ship and the greenhouse (fixed), and BOOK ONE SOLVED had no gate
(`check_finditchapters_brag`). Mutation round 3 covers all of it (`EYECANDY.md` §7).

## REVIEW-1 round 2 (2026-10-07/08, two more adversarial reviewers), `REVIEW-1.md`
C1 a clear the release carried never reached the board; C2 a Daily stamped with its day's 00:00 out-ranked an
earlier chapter clear, and an unbounded Pause banked a Daily across midnight; C3 a server hop onto a still-held lock
showed an empty book, "won't save", and threw the player into Chapter 1 for up to 20 s; C4 a late write rolled the
session back; D1 no way out of a live room for ~30 s after a Resume; D2 the ship's weather and fish and the
greenhouse drizzle were beyond the wall (invisible); D3 the dome slit was inside the opaque disc; D4 a Hub tap after
a refused Next was swallowed; D5 the hazard rarity was measured on a rule the game does not use; D6 the Gold Book,
stars and streak were never shown; D7 the gates ran under luaujs (still open). Every one reproduced first, fixed
with a failing test first, mutation-tested (round 4). Five new gates: `_release`, `_midnight`, `_hop`, `_race`, `_exit`.

## What is NOT done
- Studio: nothing rendered, tapped on a device or run in a live server (`EYECANDY.md` §8, now 30 items).
- `luau-analyze` / `luau-compile`; a re-run of every gate under the real luau CLI (round 2 D7).
- A third adversarial review after the round-2 fixes.
- A live server's real 00:00 UTC (a faked midnight is `check_finditchapters_midnight`).
- `tools/film_game.py` has no scenarios for this game (`tools/` is not ours): `MARKETING.md`.
- The telescope "swinging up" on BOOK ONE SOLVED (DESIGN.md §10.2).
- Audio, badges, Book Two, a shared-room race: cut from v1 (DESIGN.md §2).
