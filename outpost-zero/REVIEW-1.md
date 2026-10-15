# REVIEW-1 — Outpost Zero: Sky City Tycoon

Two rounds of adversarial review. **Round 2** (below, first) closed 8 more findings; **Round 1** (after it) is kept
as it was written, with its headings one level down.

## Round 2 (2026-10-07): two more reviewers, 8 findings

Two adversarial reviewers went over the tree after round 1: one hunted exploits and failure paths (A), one played the
game and its look (B). **All 8 findings reproduced. 7 are fixed test-first; B3 is fixed in part, and the rest of it
is the owner's call.** Every finding was reproduced in the real repo's bundle first, mostly with the reviewers' own
probes (`scratchpad/oz2x_exploit_v7k3/robloxemu/probe_*.luau`, `scratchpad/oz2rev_play_t4n8/fixed/*/rv*`, copied to
`scratchpad/oz2fix/repro`). Then came a gate that failed for the reviewer's reason, then the fix in the game, then the
reviewer's probe again. All runs used `tools/luaujs`; the native luau CLI is still missing. Nothing was committed,
published or opened in Studio.

| # | severity | finding | verdict | gate that pins it |
|---|---|---|---|---|
| A1 | low | A flush in flight at the leave freed the lock, so another server (or a quick rejoin to the same one) could load an older city and cancel the leave-write | **fixed** | `check_outpostzero_latency` E, F |
| A2 | low | The Census write at the leave was tried once | **fixed** | `check_outpostzero_board` §6 |
| A3 | low | The friends list itself was not cached | **fixed** | `check_outpostzero_board` §7 |
| B1 | medium | The airship's hull and 8 other visible parts were stretched Balls, which Roblox draws uniform | **fixed** (10 parts, the sandbag too) | `check_outpostzero`, `_sky`, `_hazards` |
| B2 | low | The airship hand-over dropped 1.5 studs, snapped round twice and left 5 blank frames | **fixed** | `check_outpostzero_handover` (new) |
| B3 | low | The 30-45 min brag holds only for players who follow the ★ | **fixed in part**; re-tuning is the owner's call | `Economy.spec`, `Pacing.spec` [M12] |
| B4 | low | Break pressed mid-jump said "step out of the red ring" with no ring | **fixed** | `check_outpostzero_sky` |
| B5 | medium | luaujs lost table keys after 32 deletions | **fixed** | `tests/Runtime.spec.luau` (new) |

### A1 — only the leave-write frees the lock; a rejoin to the same server waits for it (low, fixed)

**Reproduced.** `probe_hop` (another server modelled by Main's own lock rule, polled every 0.05 s; 3 storeys bought
inside the flush): at LAT 2.0 s the in-flight flush landed at leave+1.92 s and **released** the lock; the other server
could load from leave+1.95 s and read 38 storeys, while the leaver's final record held 41. At LAT 0.4 s: released at
+0.32 s, loadable from +0.35 s, 38 of 41. `probe_rejoin` (LAT 0.4 s, same server, rejoin 0.3 s after the leave): the
rejoined city had population 76 instead of 80 (38 of 41 storeys, Market Row lost), the leave-write was ABORTED and the
server logged "a newer session owns this city".

**Failing test.** `check_outpostzero_latency` E (the hop, 2 s DataStore calls) and F (the same-server rejoin): 5 FAIL
- E: "server B could first load at leave+1.90 s; loads that would get an older city: 41 of 263".
- F: population 76 (want 80), 38 storeys (want 41), the record 38 (want 41), and the "newer session" warning.

**Fix** (`Main.server.luau`).
- `writeProfile`: `lockUntil = if release then 0 else ...`. A flush in flight at the leave keeps the lock; only the
  leave-write (and BindToClose) frees it.
- `leaveWrites[userId]` counts this server's leave-writes in flight. `load()` first waits for it to reach 0 (at most
  `Config.Save.RejoinWaitSeconds` = 60, as long as a leave-write may itself queue), because the lock rule treats this
  server's own JobId as free. The reviewer's suggested one-token fix alone did not cover this path, as they said.

**After.** E: the other server can first load at leave+3.95 s, and 0 of 222 polls would have read an older city. F:
population 80, 41 storeys, saving, the record holds 41, no warning. The reviewer's probes: hop LAT 2.0 s, first load
at +4.00 s reading 41; LAT 0.4 s, +0.80 s reading 41; rejoin after 0.3 s and 3 s (LAT 0.4) and after 0.3 s (LAT
2.0): population 80, 41 storeys every time. If the leave-write itself fails now, the lock simply expires
(`LockSeconds` 120) and the next server takes over through its existing read-only re-check, with the data intact.

### A2 — the leave's Census write is retried (low, fixed)

**Reproduced.** `probe_boardleave`: the profile flush saved population 240, then one injected SetAsync failure at the
leave. The Census said 220 right after and still 220 a virtual hour later.

**Failing test.** `check_outpostzero_board` §6: one failed write at the leave left the Census at 36 (want 40, the
saved population), still 36 an hour later; a store that keeps failing was tried 1 time and nothing was logged. 4 FAIL.

**Fix.** `boardWrite(s, force, attempts)`: the leave passes `Config.Board.LeaveWriteAttempts` = 3, 1 s then 2 s apart
(the load's own retry pattern), and logs the give-up once. The periodic write keeps 1 try (it runs again within a
minute). BindToClose is unchanged: on a shutdown Roblox also fires PlayerRemoving, which retries.

**After.** One failure: the Census holds 40, an hour later too. A dead store: 3 tries, one log line. The reviewer's
probe: 240 and 240.

### A3 — the friends list is cached (low, fixed)

**Reproduced.** `probe_friends`: one owner pressing their board at the 8/s limit for 60 s with 200 friends in 4 pages
made 60 GetFriendsAsync calls and 240 page requests at 0.2 s per web call, and 240 calls / 960 page requests at
0.05 s.

**Failing test.** `check_outpostzero_board` §7: 480 presses in 60 s gave 240 calls and 960 page requests (want 1 and
4); the list was not re-fetched after the cache period (241 calls, want 2 — it was fetched every time); a failing
service was asked 240 times in 60 s (want at most 3). 5 FAIL.

**Fix.** `friendListCache[userId]`: one fetch per `FriendListCacheSeconds` (300, the friends' scores' own period); after
a failure none for `FriendListRetrySeconds` (30), showing "Friends list unavailable" at once meanwhile; dropped when
the player leaves (bounded to the players in the server).

**After.** 1 call and 4 page requests for 480 presses; a second fetch after 300 s; 2 calls in 60 s against a failing
service. The reviewer's probes: 1 call, 4 page requests in both cases. **Test change to disclose:** three existing
board fixtures replace the friends service or list mid-run (§3 installs one 1 s after a failed fetch; §3 and §3c swap
the list). They now advance past the 30 s retry or the 300 s cache period before pressing again; no assertion was
changed.

### B1 — sizes Roblox draws as written (medium, fixed)

**Reproduced.** The reviewer's `rv_shapes` (server and Sky.client, the ★ pressed from 0 to 1 031 184) printed 9
stretched Balls: FogBank 120x26x70, CloudPuff 160x40x120, the balloon Envelope 14x17x14, Flight_Envelope 44x14x14, the
moored Envelope 44x14x14, StormCloud 900x360x300, CloudFlash 160x30x160, the dome Roof 7x3x7, WhaleBody 14x11x34.

**Failing test.** The engine rule (a Ball uniform, a Cylinder Y = Z, no axis over 2 048, from anomaly-observatory's
round of the same finding) asserted on every part shown:
- `check_outpostzero` (the full city and its moored airship): 1 FAIL listing Envelope and Roof.
- `_sky` (every band and seam, every frame): 1 FAIL listing 9 parts.
- `_hazards` (every hazard kind met): 1 FAIL listing 8, including one the reviewer did not have, the sandbag hazard
  (3 x 3.6 x 3).

**Fix.** `makePart` (server) and `SkyArt`'s `addPart` build any non-uniform Ball as a Block whose Sphere SpecialMesh
fills the box, so it cannot come back through either helper. The Reactor Quarter dome became a uniform 7-stud sphere
sunk into the roof: a 3-stud cap over a 6.9-stud circle, the rest hidden in the 8-stud body, so the collision is the
cap you see (a box with a mesh would have let players stand on air at its edges). `_compile`'s hand-written Enum list
gained `MeshType.Sphere`.

**After.** All three assertions pass; the reviewer's probe prints nothing. Which axis Roblox would have kept no longer
matters. `EYECANDY.md` §8 #25 asks Studio whether the ovals read as designed.

### B2 — the hand-over is one airship (low, fixed)

**Reproduced.** The reviewer's `rv_handover2` (shelf 2, 60 fps): the copy's nose yaw -120.0 snapped to 90.0 at
11.767 s; its last frame at 11.850 s had the gondola at y 123.00; the moored model appeared at 11.933 s with the
gondola at 121.50 and yaw 150.0: gap 0.083 s, a 1.50-stud drop, a 60° turn.

**Failing test.** The new `check_outpostzero_handover` (60 fps through the real server and Sky.client): 5 FAIL. 4 frames
with no airship, a 150° turn between two frames, the copy's last pose up to 20.93 studs and 60° from the moored parts
(the gondola 1.50 studs), and no hold for a mooring that replicates late (0.00 s).

**Fix.**
- The server sends the moored nose's direction with the arrival (`nose`).
- The copy starts 1 500 studs back along that line, 60 studs higher, and keeps one fixed heading. The old code
  re-derived it from a look-ahead that vanished at the end, hence the snap.
- The gondola is the pivot on both sides (`Config.Airship.GondolaY`; the copy was placed by its hull bottom, hence the
  1.5 studs).
- The copy holds its last pose until the moored model is on that shelf (at most `HandOverSeconds` = 3 s) and goes
  that frame.

The moored pose itself is unchanged: yaw 150.0 on shelf 2, before and after. My first version turned the moored airship
toward the ring's centre instead. Before the sweep I saw that it would show thumbnail 1 (EYECANDY §9, looking past the
Town Hall toward district 1) the airship's tail instead of its 44-stud broadside. So the copy now follows the moored
pose, not the reverse, and the check asserts the moored nose is square to the shelf's line to the ring's centre
(mutant R13b).

**After.** 0 blank frames, 0.00° between any two frames, the copy's last pose equals the 12 moored parts (0.000
studs, 0.00°), 1 frame drawing both (the same pose), held 2.90 s for a mooring that never comes and then dropped. The
reviewer's probe: "gap 0.000 s, jump 0.00 studs (dy 0.00), turn -0.0 degrees".

### B3 — the brag for players who do not follow the ★ (low, fixed in part; the rest is the owner's call)

**Reproduced.** The reviewer's `rv/strat.luau` (20 seeds, zero walking or reaction time, so lower bounds): the ★ 36.5
min; cheapest storey on the short side, cheapest anywhere and new lots first 46.7; the dearest affordable storey on the
short side 48.0. Every seed gave the same number. With the pacing model's walking and reaction (`Pacing.spec` [M12],
10 seeds, median (max)):

| profile | ★ | value: reads "+N", waits for the most people per credit | valueNow: the same among what is affordable now | cheapest on the short side | cheapest anywhere | tallest affordable |
|---|---|---|---|---|---|---|
| normal | 37.1 (37.2) | 37.2 (37.3) | 46.3 (46.8) | 47.7 (47.9) | 47.7 (47.9) | 50.0 (51.9) |
| slow | 38.8 (39.1) | 39.5 (39.8) | 46.7 (47.0) | 50.5 (51.0) | 50.5 (51.0) | 57.4 (59.9) |

**Why the game cannot make every way equally fast.** A storey in a newer district brings 5x the people for 6x the
price, while a storey on an old tower costs 1.35x the one below. So the cheapest storey is usually the worst buy
(a Landing Field Home's 7th storey costs 90 credits and brings 4 settlers; a Market Row Home's first costs 90 and
brings 20), and the ★ weighs exactly that.

**Failing test, then the fix.** The prompt said "Home 6/22 · 90" and gave a player who compares prompts no way to see
this. `Economy.spec` now wants "Home 6/22 · 90 · +4 settlers", "Workshop 0/22 · 90 · +20 jobs" and "Home 0/22 · 116K ·
+12.5K settlers" (3 FAIL). `Economy.objectText` adds the storey's people. The new `Pacing.spec` [M12] pins three
things:
- the ★ is at least as fast as every other strategy;
- a player who reads the "+N" and waits for the best buy docks the airship inside 30-45 (slowest seed 37.3 normal,
  39.8 slow);
- no short-side strategy is more than 1.6x slower than the ★ (slowest: tallest/slow 59.9 vs 38.8).

**Still open (the owner's call).** Players who always buy the cheapest (or the tallest) storey stay outside 45. One
Config number moves everyone: the Skyport's population. Measured with the same model (5 seeds, max):

| Skyport at | ★ fast / normal / slow | cheapest normal / slow | tallest normal / slow |
|---|---|---|---|
| 6 400 (now) | 36.8 / 37.2 / 39.1 | 47.9 / 51.0 | 51.9 / 59.9 |
| 6 200 | 34.3 / 34.7 / 36.4 | 42.4 / 45.4 | 46.4 / 54.4 |
| 6 000 | 31.0 / 31.4 / 33.1 | 39.4 / 42.5 | 43.4 / 51.4 |
| 5 800 | 29.5 / 29.8 / 31.6 | 37.0 / 40.1 | 41.0 / 49.0 |

At 6 000 every cheapest-buyer lands inside 45 and the ★ player at 31-33 min, but the fast profile's 31.0 sits just over
30, and the tallest-buyer stays out. No single threshold fits everyone: tallest/slow over ★/normal is 1.61, wider than
the window's 45/30 = 1.5. Changing it moves DESIGN's pacing (the brag at 37 min, bands, checks set up at 6 384), so it
was not done here.

### B4 — a queued break says the real reason (low, fixed)

**Reproduced** by the new `_sky` section with no hazard, FloorMaterial = Air, then BreakButton.Activated. The break was
queued and the chip said "☕ Break queued: step out of the red ring first".

**Failing test.** 2 FAIL: the chip talked about a red ring with none on screen, and did not say it starts on landing.

**Fix.** `Sky.client` words the queued chip by the reason it waits. A hazard inbound: "step out of the red ring
first". In the air: "it starts when you land". Still walking: "stand still to sit down". Rest.luau stays verbatim.

**After.** "☕ Break queued: it starts when you land"; landing starts the break; the hazard case still says the red
ring.

### B5 — luaujs lost table keys after 32 deletions (medium, fixed)

**Reproduced.** `runtime.js` `hset` called `compact()`, which replaces `this.hm`, then wrote the new key into its stale
local `m`. A 200-churn repro lost the key at inserts 34, 68, 102, 136 and 170, and an emptied table iterated up to 5
ghost entries. In the game's harness (`scratchpad/oz2fix/repro/robloxemu/probe_joins.luau`, 60 players joining and
leaving one server in turn): 59 of 60 loaded, the 34th did not, and the 35th landed on Shelf_2.

**Failing test.** The new `tests/Runtime.spec.luau` (object, string and sparse number keys churned 200-300 times,
residents kept): 3 passed, 7 failed. On the native CLI it passes trivially.

**Fix.** `{ this.compact(); m = this.hm; }`.

**After.** Runtime.spec 10/0; probe_joins 60 of 60, the 35th on Shelf_1. Every one of the 24 earlier gates gave the
same counts as before. meteor-drop-tycoon's 12 specs gave their recorded counts again (45/119/124/132/153/1814/79/11/
55/54/22/70).

### Round 2 mutation sweep

`scratchpad/oz2fix/mut/sweep_r2.py` uses the round-1 method. Each mutant runs in its own copy of outpost-zero and
robloxemu (emu, wrap.py, every `check_outpostzero*.luau`) and is one string replacement that must occur exactly once.
The sweep records the file's sha256 before and after, rebuilds the bundle, confirms the mutation is in it, and runs
all 26 gates. A gate that dies without a summary counts as failed.

The real repo was never written during the sweep: the manifest of its code (src, tests, tools, the project file, the
11 checks; 52 files) was `166fe15cca1d…f205` before and after, **identical**.

**75 runs. All 66 mutants KILLED, all 9 controls SURVIVED.**
- M1-M33, N1-N12 (N2 re-pointed at the edited leave code) and C1-C5 were re-run on the new code; all came out as
  before.
- Every src mutant was confirmed in the rebuilt bundle.
- R18 and C9 (runtime.js) and N12 (default.project.json) are not bundled.
- C8's original text also occurs in Main, so the sweep's automatic check read "False". By hand, the mutated bundle
  holds 1 `"SphereMesh"` (SkyArt) and 1 `"EllipsoidMesh"` (Main): it arrived.
- The assertion that fired was captured one mutant at a time (`which_fail_r2.py`).

| mutant | what it breaks | killed by | the assertion that fired |
|---|---|---|---|
| R1 | an in-flight flush frees the lock again (A1 undone) | `_latency` | E: "server B can never load an older city ..." got 41 |
| R2 | no rejoin wait | `_latency` | F: population 76 (want 80), 38 storeys (want 41) |
| R3 | the leave-write not counted in `leaveWrites` | `_latency` | F: 76 / 80, 38 / 41 |
| R4 | the leave's Census write tried once (A2 undone) | `_board` | §6: the board holds 36 (want 40), an hour later too |
| R5 | the leave's retries x10 | `_board` | §6: "retried a bounded number of times (30)" |
| R6 | no friends-list cache (A3 undone) | `_board` | §7: 240 calls (want 1), 960 page requests (want 4) |
| R7 | no back-off after a failed fetch | `_board` | §7: "asked at most once per 30 s (240 calls)" |
| R8 | the list cache never expires | `_board` | §3: the changed list never shows ("an empty friends board says something useful") |
| R9 | SkyArt keeps stretched Balls (B1 undone, client) | `_sky`, `_hazards` | 7 and 8 parts not drawn as written |
| R10 | Main keeps stretched Balls (B1 undone, server) | check_outpostzero, `_sky` | 1 part (the moored Envelope) |
| R11 | the copy's nose not turned along its heading | `_handover` | a 90° turn and 29.53 studs at the hand-over |
| R12 | the copy placed by its hull bottom (the old 1.5 studs) | `_handover` | "no part jumps": Gondola 1.500 studs |
| R13a | the server sends a nose turned 90° | `_handover` | 90° and 29.53 studs at the hand-over |
| R13b | the moored airship turned toward the ring (my first B2 attempt) | `_handover` | "moored broadside ...": nose . inward = 1.000 |
| R14 | no hold at the dock | `_handover` | 4 blank frames; held 0.00 s |
| R15 | the hold never ends | `_handover` | "never forever (7.90 s, at most 3)" |
| R16 | the copy not dropped when the moored model appears | `_handover` | 177 frames drawing both |
| R17 | the airborne reason removed (B4) | `_sky` | "it says the break starts when you land" |
| R18 | luaujs's stale map (B5 undone) | Runtime.spec | 5 keys lost, 167 ghost iterations |
| R19 | the prompt without "+N" (B3 undone) | Economy.spec | "Home 6/22 · 90" (want "... · +4 settlers") |
| R20 | the ★ without its payback term | Economy.spec, Pacing.spec, walk | the score cases; the brag 47.4 min (outside 30-45) |
| C6 control | `HandOverSeconds` 3 -> 3.5 | none (SURVIVED) | |
| C7 control | the Census give-up log's wording | none (SURVIVED) | |
| C8 control | the SpecialMesh's name | none (SURVIVED) | |
| C9 control | runtime.js `this.hm` -> `this['hm']` (equivalent) | none (SURVIVED) | |

### Final gates (2026-10-08, after round 2, bundle rebuilt first, tools/luaujs)

**26 passed, 0 failed:**
- Specs: Board 64, City 255, Economy 144, EnvBands 124, EnvConfig 189, Hazards 153, HudLayout 968, Pacing 54, Rest 55,
  Rng 32, Runtime 10 (new), Save 59, responsive 70, all with 0 failed.
- project_check 5/0.
- Checks: check_outpostzero 212, _save 73, _board 60, _sky 93, _hazards 48, _airship 37, _compile 194 (159 Enum uses),
  _latency 51, _start 30, _handover 16 (new), all with 0 failed; _hud PASS at 20 viewports.
- walk 391/0 in the final run (389-396 across this round's runs; the count varies with the hazards met).

The gates went from 24 to 26: `tests/Runtime.spec.luau` and `check_outpostzero_handover.luau` are new.

The walk, after round 2:
- first build 3.6 s; 6 purchases in the first minute;
- population 12 / 340 / 796 / 4 548 / 5 764 at 1 / 5 / 10 / 20 / 30 min;
- the Grand Airship docked at 37.7 min after 322 purchases;
- 14 hazards (11 stepped out of, 2 hits); 0 Orders lapses;
- +517K on the rejoin 5 minutes later; loop 2 made 52 purchases.

Budgets, unchanged: worst client frame 51 parts and 2-3 lights; 52 local parts with a hazard; a full shelf 239 parts
(budget 244); the idle world 252 server parts.

### The complete-game standard, after round 2

**§1 It works and is honest.**
- **Core loop reachable from join:** met (check_outpostzero, `_start`, the walk).
- **Spawn:** met.
- **Server-authoritative:** met. The seed salt is not needed, because nothing hidden derives from the layout seed.
  Both round-2 reviewers accepted that under DESIGN 10.3.
- **DataStore:** met. It now also holds under a leave with a flush in flight, a hop to another server and a quick
  rejoin to the same one (A1).
- **No silent no-ops:** met. A queued break now gives the real reason (B4).

**§2 It looks good.**
- **Fx, bands, hazards, rest, budgets:** met. Every part shown now has a size Roblox draws as written (B1).
- **The brag:** the airship arrives as one airship (B2). It docks in 30-45 min for players who follow the ★ (37.1,
  slow 38.8, walk 37.7) or read the prompts' "+N" (37.2, slow 39.5). It does not for players who always buy the
  cheapest storey (47.7, slow 50.5) or the tallest (50.0, slow 57.4). B3: the owner's call.
- **The long-term goal:** met (Crown Heights 133.9 min, a complete skyline 4.30 h).
- **Phone first:** met headless; EYECANDY #22 waits for a real phone.

**§3 Highscore board:** met. The friends list is now cached (A3), and the leave's write survives a transient error
(A2). The tie-break from 2033 is still open (round-1 F4, the owner's standard).

**§4 Ready to ship.**
- README, EYECANDY (25 needs-Studio items, 4 shots), MARKETING (7 clips) and CLAUDE.md are updated.
- Every round-2 change was written failing-first and mutation-tested with controls.
- 26/26 gates green on luaujs.
- The store text is unchanged (974 characters).

**§5 Night shift:** not done, by design.

### Still open

- **The native CLI:** every count here comes from `tools/luaujs`. Re-run with `LUAU=<luau.exe> bash outpost-zero/tools/gates.sh`.
- **B3, the owner's call:** whether the 30-45 window must also hold for players who ignore both the ★ and the "+N".
  The Skyport threshold table above shows what each choice costs.
- **Round-1 F4:** the Census tie-break past 2033 (the standard's encoding).
- **Needs Studio:** `EYECANDY.md` §8, now 25 items. New: #25 (the stretched spheres as meshes). Updated: #5 (the
  hand-over under real replication, the new arrival line), #21 (the sunk dome), #24 (the hop and the rejoin with two
  live servers).
- **Real services:** `_latency` uses fixed delays. Real latency varies and throttling queues. The friends board has
  still only run against stubs.
- **The hazard-kind mix in `_hazards` varies between runs** (Sky.client draws them from an unseeded Random). The
  sandbag was met in each of the 3 runs whose kinds were printed, and its conversion goes through the same helper as every other
  stretched sphere.
- **Cosmetic, from round 1:** with one Home and no Workshop yet, the HUD's Orders line counts down although nobody
  works yet.
- Round 1's untested hypothesis about a same-server rejoin is now measured and fixed (A1, `_latency` F).

---


## Round 1 (2026-10-07): two reviewers, 8 findings

Two adversarial reviewers, 8 findings. **7 fixed test-first, 1 left to the owner** (it comes from the standard's own
encoding). Every finding was reproduced first, in the real repo's bundle, with the reviewers' own scratch checks
(`scratchpad/ozx/robloxemu/check_ozx_*.luau`, `scratchpad/ozrev_reach_q3m8/robloxemu/check_ozrev_*.luau`, copied to
`scratchpad/oz1/run`). Then came a failing gate, then the fix in the game, then the reviewers' scripts again. All runs used
`tools/luaujs`, because the native luau CLI is still missing from the machine. Nothing was committed, published or
opened in Studio.

| # | severity | finding | verdict | gate that pins it |
|---|---|---|---|---|
| F1 | medium | The Census pairs a live population with an older popAt; a later finisher can rank first | **fixed** | `check_outpostzero_latency` A, B |
| F2 | low | A player joining a full server is kicked while the leaver's save is in flight | **fixed** | `check_outpostzero_latency` C, D |
| F3 | low | The Census prompt toasts on every press from someone else, with no rate limit | **fixed** | `check_outpostzero_board` 3d |
| F4 | low | The Census tie-break stops working on 2033-05-18 | **open: owner** (the standard's encoding) | (measured, below) |
| F5 | critical | Two Homes (or two Workshops) as the first builds lock the city at 0 income for good | **fixed** | `Economy.spec` 6b, `check_outpostzero_start` |
| F6 | medium | The public Census drops the viewer's own row once 10 players rank above them | **fixed** (both views) | `Board.spec` window, `check_outpostzero_board` 3c |
| F7 | low | On landscape phones the HUD stack crosses the screen centre | **fixed for the title card**; the rest goes to needs-Studio #22 | `check_outpostzero_hazards` 8 |
| F8 | low | Workspace.StreamingEnabled is not pinned | **fixed** | `tests/project_check.py` |

### F1 — the Census pair comes from the snapshot the write saves (medium, fixed)

**Reproduced.** `check_ozx_race`: a storey bought inside a flush's yield raised the population from 220 to 224. The
Census was written as 224 with popAt +244, while the record still held 220 @ +244. Once the next flush landed, the record
held 224 @ +324, so the board was 80 s early. `check_ozx_race2`: X completed the city at +31 s and Y at +63 s, during an
autosave. The Census then said **#1 = Y, #2 = X**, with Y's popAt at -600 against its saved +63.

**Failing test.** The new `robloxemu/check_outpostzero_latency.luau` makes every profile UpdateAsync and every Census
SetAsync take 0.4 s of virtual time. It ties os.time() to the virtual clock and keeps a ledger of every
(population, popAt) pair a write actually saved. Before the fix, 5 assertions failed:
- A: one Census write was a pair no save holds (224 @ +244), and the Census ended 133 s earlier than the saved popAt.
- B: Y's popAt was -600 against a saved +520, and the Census ranked Y (7002) above X.

**Fix.** In `Main.server.luau`, writeProfile takes `packedPop = s.st.pop` together with `Save.pack`, before
UpdateAsync yields, and sets `savedPop = packedPop` on success.

**After.** A: the Census was written 7 times, and every value is a pair a save holds. B: X's popAt is +481 and
Y's is +520, both equal to the saved values, and X ranks first. The reviewers' scripts now print "0 s EARLIER" and
"#1 = X (completed at +31)".

### F2 — leaving frees the shelf before the save yields (low, fixed)

**Reproduced.** `check_ozx_kick` / `kick2`: the newcomer was kicked with "This server's 6 shelves are taken". The leaver
kept the shelf for 0.30 s after the leave, and for 0.95 s when it left during its own flush.

**Failing test.** `_latency` C (a full server; the leaver leaves during its own flush; a newcomer arrives 0.2 s later)
failed "not kicked" and "gets the freed shelf", then errored because the newcomer had no state.

**Fix.** `onPlayerRemoving` clears the owner and resets the shelf first, then writes. While a session is leaving,
`stepSession` returns at once, because by then its shelf may belong to the newcomer. Without that guard, a leaver's
Grand Airship in flight would moor on the newcomer's shelf. `_latency` D pins this: a 20 s save for the leaver, and the
newcomer on the freed shelf for 16 s, gives no Airship, no mooring mast and no "welcomed" announcement there. The
leaver's record lands with its last storey and `airshipSeen = false`, so the flight replays at the leaver's next join.

**After.** C and D pass (38/0 for the whole check). The newcomer gets the freed shelf, and the sign still names them
after the leaver's save lands. None of the leaver's buildings appear. The leaver's record is released with its city
in it. The reviewers' scripts show "kicked = false".

### F3 — the board's prompt is rate-limited first (low, fixed)

**Reproduced.** `check_ozx_flood`: 40 presses on someone else's board gave 40 toasts. The same 40 presses on their lot
gave 2.

**Failing test.** `check_outpostzero_board` 3d: 40 toasts, against a limit of 2 (the reason, then "Slow down").

**Fix.** `rateOk` now runs first, as it does on the lots. The foreign-board toast uses `toastEvery` (once per
ForeignToastSeconds).

**After.** 2 toasts, and the first one names the board's owner. Section 3's "a visitor is told whose board it is"
still passes.

### F4 — the tie-break after 2033-05-18 (low, open: the owner's standard)

**Reproduced.** `Board.encode(1 031 184, 2e9 + 100)` and `Board.encode(1 031 184, 2e9 + 86 400)` both give
2 062 368 000 000 001, because reachedAt is clamped to Scale - 1. 2e9 s is 2033-05-18 03:33:20 UTC; os.time() was
1 791 397 128 when this was measured.

**Not changed.** `docs/complete-game-standard.md` §3 fixes the encoding as `metric * 2e9 + (2e9 - reachedAtUnix)`, and
every game with a Census uses it. One way to keep it working past 2033 is to subtract an epoch: (2e9 - (t - 2026-01-01))
would last until 2089. That is a change to the standard, so the owner decides. Until then, ties at the same population
fall back to the lower userId from 2033 on.

### F5 — a city with nobody in it can always get its first citizens (critical, fixed)

**Reproduced.** `check_ozrev_softlock`: after two Workshops the city had credits 0, settlers 0, jobs 8, population 0
and income 0. It was still 0 after 15 minutes, still 0 after a rejoin a day later, and still 0 after one more hour.

**Failing tests.**
- `Economy.spec` 6b: `startNeed` did not exist. The section also adds a property test: 300 real layouts, 40 random
  presses each, and no dead state allowed.
- The new `robloxemu/check_outpostzero_start.luau`: 19 of 30 failed.
  - The second same-zone build was accepted, leaving 0 credits, and the city never got citizens.
  - Of 24 players who pressed random lots in reach for a minute and then followed the ★, **16 got citizens and 8 were
    dead**; the slowest was still at 0 after 121 s.
  - A record stranded before the fix was not lifted.

**Fix.**
- `Economy.canBuy`: while the population is 0 and the other side has nobody, a purchase that would leave less than
  that side's cheapest storey is refused. The reason is "needjobs" or "needhomes", and `refusalText` answers with the
  hint's own words ("Settlers need jobs: build the Workshop ★").
- `Economy.startNeed`: what a city with nobody in it needs.
- `afterLoad`: a saved record below `startNeed` is lifted to it once, counted in lifetime, and logged. Only a record
  saved before this rule can need it. A new city still starts with exactly 30.

**After.**
- `Economy.spec` 142/0: 578 purchases bought, 180 refused as stranding, 0 dead states.
- `_start` 30/0:
  - The second Home is refused with the toast, 15 credits are left, and the ★ is the Workshop, affordable now. Building
    it makes 4 citizens at 1 credit/s, and the mirror case behaves the same.
  - All 24 random pressers got citizens at once (1 130 presses, 15 refused as stranding).
  - The stranded record is lifted to 15, logged once, and the Workshop works.
- `Pacing.spec` and the walk are unchanged: brag 37.1 min, slow 38.8, teleport 36.5; the walk docked the airship at
  37.7 min.

### F6 — the viewer's own row is always on the face (medium, fixed)

**Reproduced.** `check_ozrev_board10`: the server sent 11 rows, the face drew 10, and the viewer's own row was not
drawn. The status text was empty.

**Failing tests.** `Board.spec` (no `Board.window`). `check_outpostzero_board` 3c, with 12 cities above Nova:
- In the friends view, Nova's row was not among the 10 drawn; she ranks 13th.
- In the public view, her row was not drawn either.

The reviewer saw only the public view. The friends view had the same bug.

**Fix.** `Board.window(rows, Config.Board.Rows)`, which is pure: past 10 rows it keeps the top 9 and then the viewer's
row, with its real rank. The server applies it to both views, and the HUD draws `Config.Board.Rows`.

**After.** `Board.spec` 64/0. On the face, Friends shows row 10 as "13. Nova"; Public shows row 10 as Nova under the
top 9. The reviewer's script prints "payload rows sent: 10 … own row rendered: true".

### F7 — a title card and a hazard never share the screen (low, fixed in part)

**Reproduced.** I measured `HudLayout.compute` (touch, 36 px inset, screen px):

| viewport | screen centre | warning | toast | hint | card |
|---|---|---|---|---|---|
| 800 x 360 | 180 | 153-171 | 175-192 | 195-212 | 216-249 |
| 640 x 300 | 150 | 153-171 | 175-192 | 195-212 | 216-249 |
| 844 x 390 | 195 | 153-171 | 175-192 | 195-212 | 216-249 |

hudcheck still passes, because it tests overlap between the HUD's own pieces, not against the avatar.

**What was fixable headless.** The title card is the piece that reaches the lower middle, where the feet and the red
ring are. Nothing guaranteed it and a hazard would not coincide: a band card comes with a purchase, and a hazard can
be live at that moment.

**Failing test.** `check_outpostzero_hazards` §8. (a) A hazard comes due in the air, then Storm Front's card goes up:
73 frames had both. (b) Aurora Crown's card arrives during a live hazard: 73 frames had both.

**Fix.** In `Sky.client`, a card holds a due hazard while it shows (the existing `canDodge` hold). A card that arrives
while a hazard is up is queued, keeping only the newest, until the hazard passes.

**After.** 47/0, with 0 frames showing both. The held hazard came 0.05 s after the card went; the queued card came the
frame the hazard passed (4.65 s).

**Still open.** Whether the warning, a toast or the hint (which can hold a whole-session "not saving" line) hides the
avatar on a short phone needs the real camera. That is `EYECANDY.md` §8 item 22, with the table above.

### F8 — StreamingEnabled pinned (low, fixed)

**Reproduced.** `default.project.json` had no Workspace node, and grep found "stream" in no document.

**Failing test.** The new `tests/project_check.py` (adapted from stormgrow) gave 3 passed, 2 failed. It is now a gate in
`tools/gates.sh`.

**Fix.** `"Workspace": { "$className": "Workspace", "$properties": { "StreamingEnabled": false } }`.

**After.** 5/0. Confirming it in the built place is `EYECANDY.md` §8 item 23.

### Mutation sweep

`scratchpad/oz1/mut/sweep_r1.py` runs each mutant in its own copy of outpost-zero and robloxemu (emu, wrap.py and the
10 checks). Each mutant is one string replacement that must occur exactly once. The sweep records the file's sha256
before and after, rebuilds the bundle, and confirms the mutation is in it (the new text is present, and the old text is
gone unless the new text contains it). It then runs all 24 gates. A gate that dies without a summary counts as
KILLED.

The real repo is never written. A manifest sha256 over its code is taken before and after the sweep: 50 files (src,
tests, tools, default.project.json, robloxemu/check_outpostzero*.luau).

**Result: 50 runs. All 45 mutants KILLED and all 5 controls SURVIVED, as expected.** Each mutation was confirmed in
the rebuilt bundle (N12 is in default.project.json, which is not bundled). The manifest was
b874c6c5f2bb…49dd over 50 files both before and after the sweep: identical, so the sources are byte-identical. The
REVIEW-1 rows (N, C3-C5) are below. M1-M33 and C1-C2 from the first sweep were re-run on the new code and are all
still KILLED / SURVIVED. M14 now points at the edited `canDodge` line. M22 is now killed by Economy.spec and `_start`,
and M5, M10, M11, M21, M26 and M33 are also killed by the new checks.

| mutant | what it breaks | killed by | the assertion that fired |
|---|---|---|---|
| N1 | the Census pair from the live population (F1 undone) | `_latency` | A: a pair no save holds, and the final popAt 133 s early; B: Y's popAt -600, Y ranked first (5 FAIL) |
| N2 | the shelf freed after the writes (F2 undone) | `_latency` | C: the newcomer is kicked ("6 shelves are taken") and gets no shelf |
| N3 | the tick runs a leaving session | `_latency` | D: Z's Airship moored on the new owner's shelf, and the "welcomed" announcement went out |
| N4 | the foreign board toasts every press | `_board` | 3d: more than 2 toasts for 40 presses |
| N5 | no stranding guard in canBuy | Economy.spec, `_start` | 6b (second Home accepted, dead states in the property test); `_start` 1-3 |
| N6 | no lift at the join | `_start` | 4: the stranded record stays at 0 credits, nothing is logged, no citizens (4 FAIL) |
| N7 | the guard checks the wrong side | Economy.spec, check_outpostzero, `_save`, `_latency`, `_start`, walk | the first builds are refused or a second Home is let through |
| N8 | no Board.window on the server | `_board` | 3c: Nova's row is not drawn |
| N9 | the window drops the viewer's row | Board.spec, `_board` | window cases; 3c |
| N10 | no card hold | `_hazards` | 8a: 73 frames with a card and a hazard |
| N11 | no card defer | `_hazards` | 8b: 73 frames with both; the card came at 0.05 s, not after the hazard |
| N12 | StreamingEnabled true | project_check.py | the pin |
| C3 control | Windsock blue 90 -> 91 | none (SURVIVED) | |
| C4 control | the lift log says "raised" instead of "lifted" | none (SURVIVED) | |
| C5 control | Board.window's copy loop rewritten equivalently | none (SURVIVED) | |

The killing assertions for N1, N2, N3, N6, N10 and N11 were confirmed one mutant at a time
(`scratchpad/oz1/mut/which_fail.py`). The sweep itself records which gate failed. A first attempt at the sweep hung:
M5 and M33 broke the economy, and `_latency` A waited for credits without a bound. The loop is now bounded (a set-up
assertion, which is why `_latency` has 38 assertions), the sweep has a 1 500 s per-run timeout, and it was re-run from
scratch.

### Final gates (2026-10-07, after REVIEW-1, bundle rebuilt first, tools/luaujs)

**24 passed, 0 failed:**
- Specs: Board 64, City 255, Economy 142, EnvBands 124, EnvConfig 189, Hazards 153, HudLayout 968, Pacing 40, Rest 55,
  Rng 32, Save 59, responsive 70 (all with 0 failed).
- project_check 5/0.
- Checks: check_outpostzero 211, _save 73, _board 50, _sky 86, _hazards 47, _airship 37, _compile 190 (all with 0
  failed); _hud PASS.
- New checks: _latency 38/0, _start 30/0.
- walk 391-394/0 (the count varies with the hazards met).

The gates went from 21 to 24: `tests/project_check.py`, `check_outpostzero_latency.luau` and
`check_outpostzero_start.luau` are new.

### The complete-game standard, after REVIEW-1

**§1 It works and is honest.**
- **Core loop reachable from join:** met. It is now also reachable from any order of first presses (`_start`; before,
  8 of 24 random new players were dead for good).
- **Spawn:** met.
- **Server-authoritative:** met.
- **Seed salt:** met, because nothing hidden derives from the seed. Every layout has the same lots and prices
  (City.spec: 3 + 3 lots per district over 1 000 seeds; prices depend only on district and storey). The future
  districts' slots are on their signs from the join. That is unlike fork-tower, where the seed fed hidden traps.
- **DataStore:** met, and the leave and the Census are now also checked under latency.
- **No silent no-ops:** met. The stranding refusal and the foreign board answer.

**§2 It looks good.**
- **Bands, hazards, rest, budgets, brag:** met as before. The card and hazard rule is new.
- **Phone first:** met for the headless rules. Item 22 waits for a real phone.

**§3 Highscore board:** met. The viewer's own row is always shown, and the Census holds only saved pairs. The tie-break
from 2033 is open (F4).

**§4 Ready to ship.**
- README, EYECANDY (now 24 needs-Studio items, 4 shots), MARKETING and CLAUDE.md are updated.
- Every REVIEW-1 change was written failing-first and mutation-tested with controls.
- The gates are green on luaujs.

**§5 Night shift:** not done, by design.

### Still open

- **Native CLI:** re-run `LUAU=<luau.exe> bash outpost-zero/tools/gates.sh` when the CLI is back. Every count here
  comes from `tools/luaujs`.
- **F4:** the tie-break past 2033 is the owner's call on the standard.
- **Needs Studio:** `EYECANDY.md` §8, now 24 items. New: #22 (the HUD stack over the avatar on short phones), #23 (the
  StreamingEnabled pin in the built place), #24 (a leave under real latency).
- **Real latency:** `_latency` uses a fixed 0.4 s delay. Real latency varies, and throttling queues. The friends board
  has still only run against stubs.
- **Not measured, a hypothesis:** if the same user rejoins the *same* server while their leave-write is in flight, the
  new load takes the lock (same JobId), and the leave-write is then dropped as stale. That would lose at most the
  progress since the last flush (at most 7 s plus anything pending). Not reviewed and not tested.
- **Cosmetic:** with one Home and no Workshop yet, the HUD's Orders line counts down (`working` is true while
  ordersLeft > 0) although nobody works yet. It lasts only until the Workshop, which is always affordable now.
