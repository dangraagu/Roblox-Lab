# CLAUDE.md — Outpost Zero: Sky City Tycoon (Roblox)

Read `DESIGN.md` for the why of every number (it tags each one: [M n] the pacing model, [T] a template game, [R] a rule,
[A] an assumption), `EYECANDY.md` for the sky, hazards, the break, budgets, the needs-Studio list and the thumbnail
shots, `MARKETING.md` for the clips, `README.md` for the store text.

## What it is

A calm city-builder for 6 players, one floating rock shelf each on a ring 220 studs out. Press a lot's sign-post prompt
to build a Home (settlers) or a Workshop (jobs) or add a storey (up to 22); population = min(settlers, jobs) earns 0.25
credits a second each, while the workers' Orders run (10 minutes after the last build, online or off, plus a safety
net while nothing is affordable). Districts open at population 80 / 900 / 6 400 / 35 000 / 185 000 in slots the city's
server-only seed picks; the sky follows the population through six bands; the Skyport brings the Grand Airship (the
brag, ~37 min); the Census ranks population, public and friends. No client -> server remote; nothing for Robux.

## State (2026-10-07)

v1 built test-first from `DESIGN.md`; **REVIEW-1 closed** (two adversarial reviewers, 8 findings: 7 fixed test-first,
1 left to the owner; `REVIEW-1.md`), then **REVIEW-1 round 2 closed** (two more reviewers, 8 findings: 7 fixed
test-first, 1 fixed in part with the rest left to the owner; `REVIEW-1.md` "Round 2"); **green in all 26 gates**. **Never played by a person, never opened in Studio,
not published, no universe, nothing committed.** Nothing only Studio can settle has been settled: `EYECANDY.md` §8.

**The gates ran on `tools/luaujs`, not the native luau CLI.** The scratchpad's `luau/luau.exe` was deleted at 17:43 on
2026-10-07 (every file in the scratchpad went), nothing else on the machine (PATH, WSL, cargo/npm/pip caches) has a Luau
runtime, and downloading one needs the owner's go. So this build wrote one: `tools/luaujs/` (Node, ~3 000 lines: a Luau
parser with type syntax, a compiler to JavaScript generators so coroutines yield from any depth, the standard library,
Lua patterns, C-exact `string.format`, the CLI's sandboxed `require`, `loadstring` bound to the calling thread's
globals, and load-time import resolution as luau_load does it). Before any game code it was validated against recorded
results: **meteor-drop-tycoon's 20 gates reproduced their recorded counts exactly** (12 specs 45/119/124/132/153/1814/79/
11/55/54/22/70, the 7 checks 195/40/194/44/PASS/109/72, the walk 22/0), robloxemu's own specs 249/153/21/189 (services
matches SPAWN-ORDER.md's 189), plus1-jump's 12 specs and anomaly's Rng 32/0. A deliberately failing control exits 1 and a
syntax error is reported. **Round 2 found and fixed one luaujs defect** (finding B5): a table lost its newest key after
32 deletions (its hash part compacted, then the key went into the dropped map), so the 34th player to join one
headless server read `sessions[plr] == nil`. No gate result changed (the reviewer re-ran all 24 on a patched copy and
on an independent runtime: same counts), and `tests/Runtime.spec.luau` now pins the table semantics the gates lean on
(it passes trivially on the native CLI). meteor-drop-tycoon's 12 specs gave their recorded counts again after the fix.
**When the native CLI is back, re-run everything with `LUAU=<luau.exe> bash tools/gates.sh`.**
Until then, "compiles" in `check_outpostzero_compile` means luaujs's parser accepted the source.

## How to run every gate

```
bash outpost-zero/tools/gates.sh                       # all 26, with tools/luaujs (rebuilds the bundle first)
LUAU=C:/path/to/luau.exe bash outpost-zero/tools/gates.sh   # the same with the native CLI
# one at a time (from outpost-zero/ for tests/, from robloxemu/ for checks; ALWAYS rebuild the bundle first):
cd robloxemu && py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
node ../outpost-zero/tools/luaujs/luau.js check_outpostzero.luau
cd ../outpost-zero && node tools/luaujs/luau.js tests/Pacing.spec.luau
```

Last full run (2026-10-07, after REVIEW-1 round 2, bundle rebuilt first): **26 of 26 green.**

| gate | result | what it pins |
|---|---|---|
| Board.spec | 64 / 0 | the Census encoding, write-on-improve, the 200-friend cap, ranking, texts, the 10-row window that always holds the viewer's own row |
| City.spec | 255 / 0 | 1 000 seeds: corners <= 72.01, inner edge >= 33.06, gaps 4.00 / 6.09, posts >= 14.00, 3 + 3 per district, slot 0, determinism |
| Economy.spec | 144 / 0 | prices, caps, thresholds, the dead-end rule (256.3 s), min, Orders + net, offline, the ★ (short side first, even next to a cheaper surplus lot), purchases, refusals, texts (the prompt's "+N settlers / jobs", round 2 B3), the stranding rule (startNeed; 300 layouts x 40 random presses: 0 dead cities) |
| EnvBands.spec (plus1-jump, verbatim) | 124 / 0 | |
| EnvConfig.spec | 189 / 0 | six bands = six districts, the DESIGN 5.2 light table, ClockTime rising, weather budget, hazards, isReddish |
| Hazards.spec (meteor-drop-tycoon, verbatim) | 153 / 0 | |
| HudLayout.spec | 968 / 0 | hudcheck's 10 viewports, every piece at once: on screen, no overlap, 44 px taps, clear of the controls |
| Pacing.spec | 54 / 0 | the brag 37.1 (slow 38.8) in 30-45, Crown Heights 133.9, bands >= 3.38 min, 0 lapses, teleport 36.5, AFK/macros, 7 buys/min, 13 hazards, idle 0.5 %; [M12] players who do not follow the ★ (round 2 B3): the ★ fastest, a prompt-reader inside 30-45, nobody on the short side over 1.6x the ★ |
| Rest.spec (plus1-jump, verbatim) | 55 / 0 | |
| Rng.spec (anomaly-observatory, verbatim) | 32 / 0 | |
| Runtime.spec | 10 / 0 | the table semantics the gates lean on: 200-300 key churns (object, string, sparse number keys) read back and never come back in iteration (round 2 B5: luaujs lost a key after 32 deletions) |
| Save.spec | 59 / 0 | defaults, normalise, clamps, string keys, the seed, the v guard, pack |
| responsive.spec (verbatim) | 70 / 0 | |
| project_check.py (Python) | 5 / 0 | `default.project.json`: Workspace.StreamingEnabled pinned false, the Rojo tree |
| check_outpostzero | 212 / 0 | the real player path (below); every server part of a full city and its moored airship has a size Roblox draws as written (round 2 B1) |
| check_outpostzero_save | 73 / 0 | lock, owner token, failures, retries, v2, a corrupt seed, offline in a read-only session |
| check_outpostzero_board | 60 / 0 | public + friends, written only when it improves and only what was saved, fairness, the viewer's own row with 12 cities above (both views), 40 presses on someone else's board: 2 toasts; the leave's Census write retried (one failure: still ranked; a dead store: 3 tries, logged once); the friends LIST fetched once per 300 s however often the board is switched, a failing service asked at most once per 30 s (round 2 A2, A3) |
| check_outpostzero_sky | 93 / 0 | every band and seam, the glide, Dawn = band 1, lightning, the airship flight, budgets, the break, a client that writes nothing; every part shown has a size Roblox draws as written (B1); a break asked for in mid-air says it starts on landing, and does (B4) |
| check_outpostzero_hazards | 48 / 0 | own shelf, grounded, not resting, not during the airship, ring = zone at the feet (and on a roof), 8-direction dodge, a title card and a hazard never share the screen; every hazard part met has a size Roblox draws (B1) |
| check_outpostzero_airship | 37 / 0 | announced once, moored after 12 s at y = 120, airshipSeen saved, a mid-flight leave replays once |
| check_outpostzero_hud | PASS at 20 viewports | hudcheck, overlap = true, idle and busy (toast, hint, warning, card) |
| check_outpostzero_compile | 194 / 0 | 17 sources compile, no string require, 159 Enum uses all real (MeshType.Sphere added to the hand-written list), a broken control fails |
| check_outpostzero_latency | 51 / 0 | every DataStore call takes 0.4 s: a storey bought inside a flush, two finished cities ranked by who finished first, a full server's freed shelf given to the next player, a leaver's airship never moored on the next owner's shelf; E: a hop to another server with a flush in flight (2 s calls) never loads an older city; F: a rejoin to the same server 0.3 s after the leave gets every storey (round 2 A1) |
| check_outpostzero_start | 30 / 0 | two Homes / two Workshops first, 24 random pressers then the ★, a stranded record lifted at the join |
| check_outpostzero_handover | 16 / 0 | the Grand Airship at 60 fps (round 2 B2): no blank frame, no turn between frames, the copy's last pose = the moored 12 parts (0.000 studs, 0.00°), the copy gone the frame the model is there, the moored nose broadside to the plaza's view, a mooring that never comes held 2.9 s then dropped |
| walk | 389-396 / 0 | the player's path through the HUD (below); counts vary with the hazards met |

`check_outpostzero.luau` is the real player path: 6 shelves built AND parented, exactly one enabled SpawnLocation each
and none elsewhere, a joining character lands on its own pad under the engine's spawn order (also after a respawn and
with RespawnLocation cleared), the city loads (6 lots, 5 locked-district signs), every lot prompt reachable from the
street side, the first build by walking to the ★ (2.3-2.6 s after the load in this check's straight walk), the second
makes 4 citizens and +1 credit/s, Add storey makes the building 8 studs, refusals speak (not enough credits, someone
else's lot, a 40-press flood cut at 8/s with one "Slow down"), population 80 opens Market Row where its sign stood (the
Town Hall gains its clock), the Orders run out after 10 minutes and a purchase restarts them, the fall rescue, a full
city (1 031 184; 36 lots at 88 studs; prompts disabled; 239 parts on its shelf), no attribute under workspace or
ReplicatedStorage, nothing red, a rejoin restoring every field and paying the offline earnings once, 6 shelves for 6
players and a seventh kicked with a reason, and the Census rendered on the owner's own board.

`tests/walk.luau` is somebody playing on a phone-sized touch screen: it reads only the HUD (the ★ marker over a post,
the ★ line's "ready now", the hint, the warning), walks at 85 % of WalkSpeed after a 1 s look, presses only from within
the prompt's reach, steps out of the red ring three times in four, plays to the docked airship, leaves, comes back 5
minutes later and plays 3 more minutes. It also checks that the HUD's balance line and ★ line never name different
sides. The last printed run (2026-10-07): first build 4.2 s, 6 purchases in the first minute, population 12 / 320 /
800 / 4 544 / 5 764 at 1 / 5 / 10 / 20 / 30 min, bands entered at 3.4 / 12.4 / 37.4 min, the airship docked at 37.6 min
after 322 purchases, 14 hazards (11 stepped out of, 1 hit), 0 Orders lapses, 0 side clashes, the rejoin paid +517K for
the 5 minutes away (300 s of Orders x 1 725 credits/s), and loop 2 made 47 purchases (population 6 900 -> 18 400). The
run before it: first build 4.0 s, the airship at 37.7 min. After REVIEW-1: first build 4.0 s, 6 purchases in the first
minute, the airship docked at 37.7 min after 323 purchases, 13 hazards (10 stepped out of, 1 hit), +517K on the rejoin,
loop 2 made 48 purchases. After round 2: first build 3.6 s, 6 purchases in the first minute, population 12 / 340 /
796 / 4 548 / 5 764, the airship docked at 37.7 min after 322 purchases, 14 hazards (11 stepped out of, 2 hits), 0
Orders lapses, +517K on the rejoin, loop 2 made 52 purchases (6 900 -> 19 900). The design model says 37.1 min for the
same profile.

## Mutation sweep

2026-10-07, `scratchpad/oz/mut/sweep.py`: each mutant in its own copy of `outpost-zero` + `robloxemu` (emu, wrap.py,
the 8 checks); one string replacement that must occur exactly once; sha256 of the file before and after recorded; the
bundle rebuilt and the mutation confirmed in it; all 21 gates run; a gate that dies without a summary counts as
KILLED. **35 runs: 32 of 33 mutants KILLED and both controls SURVIVED; the survivor (M22) exposed a weak fixture,
was closed test-first, and is now KILLED too (re-run on the final gates: KILLED by Economy.spec and the walk, the
control still SURVIVED).**

| mutant | killed by |
|---|---|
| M1 RespawnLocation not set in PlayerAdded | check_outpostzero |
| M2 no CharacterAdded correction | check_outpostzero |
| M3 no shelf-ownership check on lot prompts | check_outpostzero |
| M4 rate limit 800/s | check_outpostzero |
| M5 a purchase does not renew the Orders | check_outpostzero, walk |
| M6 the safety net always on (earning ignores the Orders) | Economy.spec, Pacing.spec, check_outpostzero |
| M7 savedAt not written | check_outpostzero, _save |
| M8 no owner-token check | _save |
| M9 a v2 record locked and written | _save |
| M10 the board written from the unsaved population | _board |
| M11 the board's tie-break uses the write time | _board |
| M12 hazards off your own shelf | _hazards |
| M13 the ring drawn smaller than the zone | _hazards |
| M14 hazards during the airship's arrival | _hazards |
| M15 the sky snaps (half-life 0.01 s) | _sky |
| M16 rain at 70/s | EnvConfig.spec, _sky |
| M17 tap targets not grown on touch | HudLayout.spec, _hud |
| M18 the buttons in the bottom-right corner | HudLayout.spec, _hud |
| M19 Growth 1.30 | Economy.spec, Pacing.spec, walk |
| M20 Market Row at 800 | Economy.spec, EnvConfig.spec, Pacing.spec, check_outpostzero, _sky, _hazards, _airship, walk |
| M21 population = max(settlers, jobs) | Economy.spec, Pacing.spec, check_outpostzero |
| M22 the ★ ignores the short side | **SURVIVED the first sweep** (in both spec cases the nearest affordable lot was on the short side anyway, and the pace barely moves: equal prices make the cheapest storeys alternate sides). Three spec cases added (a surplus-side lot nearer, money to spare) and a walk guard (the balance line and the ★ line never name different sides); re-run: KILLED by Economy.spec, walk |
| M23 district 1 not in slot 0 | City.spec, Pacing.spec |
| M24 the seed as an attribute on the shelf model | check_outpostzero |
| M25 no fall rescue | check_outpostzero |
| M26 airshipSeen saved when the flight starts | _airship |
| M27 hazards during a break | _sky, _hazards |
| M28 reddish lot paving | EnvConfig.spec, check_outpostzero |
| M29 offline earnings past the Orders | Economy.spec, check_outpostzero, _save, walk |
| M30 a locked-out session saves | _save |
| M31 a topped-out prompt stays enabled | check_outpostzero |
| M32 BUILD does not end a break | _sky |
| M33 20 starting credits (not both first builds) | Pacing.spec, Save.spec, check_outpostzero, _save, walk |
| CONTROL C1 the Town Hall clock face's blue 226 -> 227 | survived all 21 gates, as it must |
| CONTROL C2 the HUD stroke's transparency 0.35 -> 0.36 | survived all 21 gates, as it must |

(M18's row printed "gates=22": hudcheck's own "FAIL — …" summary line echoed by gates.sh; it is killed either way.)

**REVIEW-1 sweep** (2026-10-07, `scratchpad/oz1/mut/sweep_r1.py`, the same method, 24 gates): M1-M33 and C1-C2 re-run
on the new code (M14 re-pointed at the edited `canDodge` line), plus N1-N12 and the controls C3-C5. **50 runs: 45 of
45 mutants KILLED, 5 of 5 controls SURVIVED.** The manifest of the real repo's code (50 files) was identical before and
after. Full table: `REVIEW-1.md`.

| mutant | killed by |
|---|---|
| N1 the Census pair from the live population | _latency |
| N2 the shelf freed after the leaver's writes | _latency |
| N3 the tick runs a leaving session | _latency (D: the airship moored on the next owner's shelf) |
| N4 the foreign board toasts every press | _board |
| N5 no stranding guard | Economy.spec, _start |
| N6 no lift at the join | _start |
| N7 the guard checks the wrong side | Economy.spec, check_outpostzero, _save, _latency, _start, walk |
| N8 no Board.window | _board |
| N9 the window drops the viewer's row | Board.spec, _board |
| N10 no card hold | _hazards |
| N11 no card defer | _hazards |
| N12 StreamingEnabled true | project_check.py |
| CONTROL C3 Windsock blue 90 -> 91 | survived |
| CONTROL C4 the lift log's wording | survived |
| CONTROL C5 Board.window's copy loop, rewritten equivalently | survived |

**Round-2 sweep** (2026-10-08, `scratchpad/oz2fix/mut/sweep_r2.py`, the same method, 26 gates): M1-M33, N1-N12 (N2
re-pointed) and C1-C5 re-run on the new code, plus R1-R20 (R13 as a and b) and controls C6-C9. **75 runs: all 66
mutants KILLED, all 9 controls SURVIVED**; the code manifest (52 files) was identical before and after. The table, with
the assertion each R mutant fired, is in `REVIEW-1.md` "Round 2 mutation sweep".

| mutant | killed by |
|---|---|
| R1 an in-flight flush frees the lock / R2 no rejoin wait / R3 the leave-write not counted | _latency (E; F; F) |
| R4 the leave's Census write tried once / R5 its retries x10 | _board §6 |
| R6 no friends-list cache / R7 no back-off after a failure / R8 the cache never expires | _board §7, §3 |
| R9 SkyArt keeps stretched Balls / R10 Main keeps them | _sky + _hazards / check_outpostzero + _sky |
| R11 the copy's nose off its heading / R12 the copy by its hull bottom / R13a a wrong nose sent / R13b the moored airship turned to the ring / R14 no hold / R15 the hold never ends / R16 the copy kept after the mooring | _handover |
| R17 the airborne break reason removed | _sky |
| R18 luaujs's stale map | Runtime.spec |
| R19 the prompt without "+N" / R20 the ★ without its payback | Economy.spec / Economy.spec, Pacing.spec, walk |
| CONTROL C6 HandOverSeconds 3.5, C7 the Census log's wording, C8 the mesh's name, C9 runtime.js `this['hm']` | survived |

## Invariants and this game's traps (each is asserted somewhere; the gate is named)

- **Spawn** (`robloxemu/SPAWN-ORDER.md`): every shelf's Arrival is a real, enabled SpawnLocation (Duration 0) built
  before anyone joins; `PlayerAdded` sets `plr.RespawnLocation` synchronously, before any yield; `CharacterAdded` waits
  (bounded, 300 frames) for `char.Parent`, re-reads the session, re-points RespawnLocation, and corrects a root more
  than 8 studs from the pad. Assert XZ, not Y (`check_outpostzero` §3).
- **There is no client -> server remote.** Every action is a server-side ProximityPrompt.Triggered: 36 lot prompts per
  owned shelf and the board's toggle. The lot handler checks the session, the 8/s rate, shelf ownership, the load, then
  `Economy.canBuy` (district open, under 22 storeys, the server's credits against the server's price) and answers every
  refusal with a toast. The handler never yields (robloxemu fires prompts inline; Roblox gives each its own thread).
- **The economy runs on the server's clock**: `settle()` brings credits up to `tick()` by `Economy.earn` (the Orders,
  then the safety net up to the cheapest storey, never past it; a complete city gets no net) before every purchase,
  every tick and every write. Orders are `tick()`-based in session and `os.time()`-based in the profile.
- **credits and savedAt travel together** in one UpdateAsync; offline earnings are `Economy.offline` from `savedAt` to
  `os.time()` (a backwards clock pays nothing) and are banked at the next flush (`check_outpostzero` §11, `_save` O).
  A read-only session shows them and never saves them, so the next saving session pays them once.
- **The layout seed is server-only**: drawn with `Random.new()` at profile creation, kept in the profile and
  `ServerStorage.CityInfo.<userId>` (attributes Shelf, Seed, Credits, OrdersLeft, Population, for checks and tools).
  Every layout has the same lots and prices. The locked-district signs do show which slot a district will take; that
  is a visible fact and buys nothing (DESIGN 10.3). A corrupt seed is redrawn and logged (`_save` S).
- **No attributes under workspace or ReplicatedStorage** (`check_outpostzero` §2, §10 enumerate them and require 0).
  Names carry only visible facts: `Shelf_3`, `Lot_2_4`, `Sign_5`.
- **Saving**: the load is an `UpdateAsync` that takes the lock with a fresh `session` token (or touches nothing when
  another live server holds it, or when the record is from a newer version); `canSave` only while holding it; every
  write cancels when `old.session ~= token` and then stops saving (fork-tower REVIEW-4 §10). Load retried 3 times (1 s,
  2 s apart); a lock re-read every 5 s for 15 s at the join; a read-only session re-checks every 15 s and takes over only
  when the lock is gone AND the data is exactly what it read (meteor-drop-tycoon REVIEW-1). Writes serialised per
  session; `pending` cleared before the yield. String lot keys only (`Save.pack`, `_save` F). **Only the leave-write
  (`release`) frees the lock** (round 2, A1): a flush already in flight at the leave carries an older city, and
  freeing the lock there let another server load that city and cancel the leave-write (`_latency` E). **A rejoin to the
  same server waits for its leave-write** (`leaveWrites[userId]`, at most `RejoinWaitSeconds` = 60), because the lock
  rule treats this server's own JobId as free (`_latency` F).
- **The Census writes only what was saved** (`savedPop` / `savedPopAt`, set by a successful profile write, BOTH from
  the snapshot packed before the write yields: a storey bought during the yield must not pair its population with the
  older popAt, REVIEW-1 F1, `_latency` A/B), only when it improves, at most once a minute plus once on leaving, never from a read-only session; `popAt` is when the
  population was first reached (`_board` §2, §3b, `_save` A). Friends: GetFriendsAsync capped at 200, round-robin reads
  at 1/s per server above a budget reserve of 10, a 300 s cache checked when a read is due. The friends LIST is cached
  too (round 2, A3): one GetFriendsAsync per viewer per `FriendListCacheSeconds` (300), none for
  `FriendListRetrySeconds` (30) after a failure ("unavailable" at once meanwhile), dropped when the player leaves.
  The Census write at the leave is tried `LeaveWriteAttempts` (3) times, 1 s then 2 s apart, and a give-up is logged
  (round 2, A2): nothing else writes that key until the player returns. robloxemu has no GetFriendsAsync, which is the
  "unavailable" path; `_board` §3, §5 and §7 stub one.
- **Leaving frees the shelf first** (REVIEW-1 F2): `onPlayerRemoving` resets the shelf and clears its owner BEFORE the
  writes yield, so a player Roblox sends in meanwhile gets it rather than a "6 shelves are taken" kick; from then on
  the leaving session touches only `s.data` / `s.st`, and `stepSession` returns at once for a leaving session (else
  its airship would moor on the next owner's shelf). `_latency` C/D, with 0.4 s and 20 s DataStore calls.
- **A city with nobody in it can always get its first citizens** (REVIEW-1 F5): population 0 means income 0, and the
  safety net needs income. `Economy.canBuy` refuses ("needjobs" / "needhomes", toasted as the hint's own words) a
  purchase that would leave less than the other side's cheapest storey while that side is empty; a saved record
  below `Economy.startNeed` is lifted to it once at the join and logged. `Economy.spec` 6b, `_start`.
- **The Census face has 10 rows and the viewer's own row is always one of them** (`Board.window`, REVIEW-1 F6), in
  both views. Every prompt is rate-limited before anything else, the board's too (F3).
- **A title card and a hazard never share the screen** (REVIEW-1 F7): a card holds a due hazard; a card that arrives
  during a hazard waits for it (`Sky.client`, `_hazards` §8).
- **Workspace.StreamingEnabled = false**, pinned in `default.project.json` (REVIEW-1 F8, `tests/project_check.py`):
  the HUD finds the ★ post and the board face under workspace once.
- **The ★ is the server's** (`Economy.bestNext`, the player's position for ties), pushed at once when it moves. The
  client draws its marker and glow on the starred post; the pacing model plays the same function. Every lot's prompt
  also says how many people its next storey brings ("Home 6/22 · 90 · +4 settlers" beside "Workshop 0/22 · 90 · +20 jobs", round 2 B3), so a player who
  compares prompts can see the better buy; `Pacing.spec` [M12] measures players who do not follow the ★.
- **The Grand Airship** (`_airship`): the purchase into the Skyport adds the mast and Announces the 12 s flight to all;
  the server moors the 12-part airship after it and saves `airshipSeen` (cosmetic, the only flag; no grant exists in
  v1). A leave mid-flight replays it once on the next join (3 s after the load). Hazards are held from the flight's
  start until 3 s after the mooring (`_hazards` §7). **The hand-over is one airship** (round 2, B2; `_handover`): the
  server sends the moored nose's direction; the copy flies in along that line with one fixed heading, its gondola as
  the pivot (`GondolaY`), holds its last pose until the moored model is on that shelf (at most `HandOverSeconds`), and
  goes that frame. The moored pose is the original one (nose along the shelf's +X: broadside to thumbnail 1).
- **Sizes the engine draws as written** (round 2, B1): Roblox forces a Ball uniform, a Cylinder round (Y = Z) and
  clamps axes at 2 048; robloxemu does not. `makePart` (server) and `addPart` (SkyArt) turn any non-uniform Ball into
  a Block with a Sphere `SpecialMesh`; the dome roof is a uniform sphere sunk into the roof. `_sky`, `_hazards` and
  `check_outpostzero` assert every part shown.
- **Hazards and the break are client-only** and grant nothing; the hazard clock runs only on your own shelf, grounded,
  not resting; the ring is drawn on what the player stands on (root - HipHeight - half the root: a roof is ground).
  A queued break's chip names the real reason: a hazard inbound ("step out of the red ring first"), in the air ("it
  starts when you land", round 2 B4) or still walking ("stand still to sit down").
- **The HUD's layout is one pure function** (`HudLayout`) both client scripts call. The airship's card and the band's
  card share Sky.client's one card slot, so the stack plus one card fits a 640 x 300 phone.
- **One red**: the hazard ring. `EnvConfig.spec` and `check_outpostzero` run isReddish over every colour and every
  built part.

## Departures from DESIGN.md (each with its reason)

- The ★ glows on the client (a PointLight and a ★ BillboardGui on the starred post), not by lighting the server's plate:
  the ★ is the owner's own state, and a server glow would cost a light per shelf over the 12-light budget.
- The building kit is built procedurally; `ServerStorage.CityKit` holds only the airship template.
- The State payload is also sent before the load ("Loading your city…" as the hint), and offline earnings are banked at
  the next flush; both were found by `_save` (H and O failed first).
- The airship's title card and the Lantern Dusk card are one card ("🏮 LANTERN DUSK · ⚓ SKYPORT OPEN!"), the docking
  card follows 12 s later in the same slot: two stacked cards did not fit the smallest phone.
- `CityInfo` carries `OrdersLeft` (seconds) instead of `OrdersUntil`.
- REVIEW-1 F5 adds a rule DESIGN 4 did not have: while the population is 0, a purchase that would leave too few
  credits to build the other side is refused, and a saved record in that state is lifted once at the join. DESIGN
  4.3's safety net assumed income > 0, which a city with nobody in it does not have.
- REVIEW-1 F7: a band's title card waits for a live hazard (at most ~4.6 s) and holds a due one while it shows.
- Round 2: the lot prompt's ObjectText adds the storey's people ("+4 settlers", B3); the airship's flight comes in
  along the moored nose's line (DESIGN 8 had it fly in from outside the ring) and holds at the mooring for the
  replicated model (B2); the Reactor Quarter dome is a sunk uniform sphere, not a flattened Ball (B1); the friends
  list has its own cache and retry period, and the leave's Census write three tries (A2, A3).

## robloxemu and machine quirks met while building this

- robloxemu's HumanoidRootPart is a default Part (not R15's 2 x 2 x 1) with no HipHeight: checks that care about the
  feet set `hrp.Size = (2, 2, 1)` and `HipHeight = 2` (`_hazards`, the walk).
- `FireClient` fires `OnClientEvent` for every connection whatever the target: run client scripts with one player in
  the server (`check_outpostzero` §13 leaves everyone else first).
- `ProximityPrompt.Triggered:Fire(plr)` runs handlers inline: a handler that yielded would stall the check; this
  server's never does.
- A Config change after a client script loaded does not move an already-scheduled hazard (the scheduler drew its due
  time at creation): set intervals before running Sky.client.
- os.time() is the wall clock while tick() is virtual: checks move absences by editing `savedAt`/`ordersUntil` in the
  record, never by waiting.
- The scratchpad is shared and was wiped once during this session; nothing this build needs lives there except the
  mutation drivers (`scratchpad/oz/mut/sweep.py`, `oz1/mut/sweep_r1.py`, `oz2fix/mut/sweep_r2.py`).
- robloxemu has no `CFrame:ToAxisAngle`; `_handover` measures the turn between two frames from the axes' dot products.
- `Enum.MeshType` is permissive in robloxemu like every Enum, so `_compile`'s hand-written list carries
  `MeshType.Sphere`.

## Files

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
src/server/Main.server.luau   shelves, the city per owner, prompts, the economy tick, saving, the airship, the Census
src/client/Hud.client.luau    credits, balance, Orders, the ★ line and marker, toasts, hints, ★ Show me, the Census rows
src/client/Sky.client.luau    bands, lightning, the airship flight, hazards, ☕ Break, chip / warning / title card
src/shared/  Config Economy City Board Save HudLayout SkyArt (game)
             EnvBands Rest Responsive FxClient (plus1-jump, verbatim)  Hazards (meteor-drop-tycoon, verbatim)
             Rng (anomaly-observatory, verbatim)  Fx (+ Presets.Dawn, the only edit)
tests/       *.spec.luau (13, Runtime.spec new in round 2), project_check.py, CityModel.luau (the pacing model,
             design/model.py ported onto Economy + City, with the non-★ strategies of [M12]), walk.luau
design/      model.py + model.out.txt (the design-time model DESIGN.md quotes; Pacing.spec reproduces its numbers)
tools/       gates.sh (every gate), luaujs/ (the Luau runtime the gates ran on)
../robloxemu/check_outpostzero*.luau (11; _handover new in round 2)
```

## Things the suite does not see

- Anything rendered: colours, readability, Beams, bloom, the SurfaceGui, the camera tilt, the airship's look
  (`EYECANDY.md` §8).
- Real physics: the knock, sitting without a seat, climbing towers, walking with a thumbstick, prompt selection.
- Real networking and services: replication of the 0.35 s storey tween, real DataStore throttling and budgets
  (robloxemu returns 1000), real GetFriendsAsync pages, MaxPlayers. `_latency` adds a fixed delay to every profile
  UpdateAsync and Census SetAsync; real latency varies, and real throttling queues.
- Real players: the pacing profiles are assumptions; the walk is a script. Replace `Config.Pacing.Profiles.normal` with
  telemetry after the first sessions and re-run `Pacing.spec`.
- The native Luau compiler (see State).

## Next (night shift, 00:00-06:00, per `docs/complete-game-standard.md` §5)

The Studio check of `EYECANDY.md` §8, the thumbnails (§9), the clips (`MARKETING.md`), then the universe, publishing (a
git-ignored `publish_*.bat`), the maturity questionnaire, and only after that marketing. Before any of it: re-run the
gates on the native luau CLI.
