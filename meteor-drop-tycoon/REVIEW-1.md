# REVIEW-1: Meteor Drop Tycoon, two adversarial reviews closed (2026-10-01)

Two reviewers read v1 after its second build pass: one through an exploit/correctness lens (six findings), one
through reachability and the player's path (three findings). This pass reproduced every finding first, wrote a
failing test for each one that reproduced, fixed the GAME, mutation-tested every new assertion with a control,
and re-ran every gate and the walk. No git command, no Studio, nothing published.

**Result: 9 of 9 findings reproduced. 8 closed in the game. B2 is half closed: the dish's bounces are fixed, and the
rest needs the owner's decision (see "Still open").**

"Before" numbers come from the reviewers' own probes (`scratchpad/mdt_rev_exploit/robloxemu/check_x_*.luau`), run
again in this pass against the unchanged source in a scratch mirror. "After" numbers come from the same probes on
the fixed game, plus the new gates. Every failing-first run used the pristine original source
(`scratchpad/mdt_rv1/orig`).

## Exploit / correctness lens

### A1 (medium): one transient DataStore error at join meant a blank, unsaved session. CLOSED

- **Reproduced:** `check_x_lock` T2 (one injected failure, at the load). The saved profile was Beacon 21, Collector
  5, Smelter 15, 1 500 Stardust. The HUD showed 0 / 0 / 0, 0 Stardust, `saving = false`. In 600 s of play the
  store got 0 calls, and the record was unchanged after leaving.
- **Fix:** the load is tried `Save.LoadAttempts` = 3 times, `LoadRetrySeconds` × attempt apart (1 s, then 2 s),
  before the session plays unsaved. This is steal-a-cryptid's REVIEW-1 fix (`Main.server.luau` `load`).
- **Test, failing first:** `check_meteordroptycoon_save` K (one failed read, then the real profile, writable,
  record intact). Case E was updated so the store stays down through all three attempts, so it still tests the
  unsaved path. On the original: 3 failed.
- **After:** `check_x_lock` T2 now shows `saving = true` and Beacon 25-26 after 600 s (two runs, the last on the
  final build). The record matched each time, and the store got 89 calls during play.

### A2 (medium): the session lock was read once at join, so a lock that cleared seconds later cost the whole session. CLOSED

- **Reproduced:** `check_x_lock` T1. The lock was released 2 s after the join. The player then reached Beacon 25-26
  and caught the Falling Star with `saving = false` throughout. The record still read Beacon 21, star 0.
- **Fix:**
  - At the join, a locked record is re-read every `LockRetrySeconds` = 5 s for up to `LockWaitSeconds` = 15 s.
    The player sees one toast: "⏳ Your save is open on another server. Waiting for it…".
  - A session that still starts read-only runs `recheckLock` every `LockRecheckSeconds` = 15 s.
  - In one transform, `recheckLock` takes the lock with a fresh token only when the lock is gone AND the record's
    `data` is exactly what this session read (`sameData`). Its progress since the join is then saved
    ("✅ Your save is back"). If another server wrote meanwhile, the session stays unsaved for good and says rejoin.
  - A session that lost its token to a newer one never switches back (case B is unchanged).
- **Tests, failing first:** `_save` H (the lock clears 2 s after the join: the session waits, then saves under its
  own token), I (still locked after the wait: read-only, then it takes over, and a purchase made while read-only
  is saved), and J (the other server wrote meanwhile: never overwritten, told to rejoin). Cases A and G now wait out
  the join wait. On the original: H 5 failed, I 4 failed, J 1 failed.
- **After:** `check_x_lock` T1 now shows `saving = true`. The record after leaving reads Beacon 25 and star 2
  (final build, md5 ada7a78e...; every reviewer probe below was re-run on it).

### A3 (low): catching the Falling Star wrote the profile from inside the shared 10 Hz tick. CLOSED

- **Reproduced:** `check_x_stall`. A 0.3 s write froze a bystander's plot for 0.3 s, and a 3 s write froze it for
  3.0 s. `check_x_gap`: the catch write lands 4.08 s after the grant write on the same key.
- **Fix:** the catch spawns its write in its own thread: `task.spawn(writeProfile, s, false, true)`. Because two
  writes of one session can now overlap, `writeProfile` is serialised per session:
  - The periodic flush skips while a write is in flight. The grant, the catch and the leave wait their turn
    (`WriteQueueSeconds` = 60).
  - `pending` is cleared before the yield and set again on failure (steal-a-cryptid REVIEW-1 A4).
  - A write that lands after the leave began never re-locks the record (`release or s.leaving`, read inside the
    transform).
- **Tests, failing first:**
  - `_save` N: with 3 s per write, the bystander's plot never stands still. Measured 0.0 s; the original froze
    3.0 s.
  - O: a slow older write never lands over a newer one. On the original the record ended at Beacon 10 instead of
    11, and was re-locked after the release.
  - P: a purchase made during a write reaches the store at the next flush tick. On the original it waited for the
    60 s autosave.
- **After:** `check_x_stall 3` reports the bystander frozen for 0.0 s, and the record has star 2.
- **Live-only:** Roblox throttles a key written more often than about every 6 s. The catch write can still queue
  behind the grant write; it now waits in its own thread (EYECANDY §8 item 23).

### A4 (low): one server-wide FIFO for friends reads let a big friends list starve everyone's view. CLOSED

- **Reproduced:** `check_x_friends`. An honest 3-friend view took 3 s alone and 203 s behind a 200-friend view. It
  took 1 001 s behind a player who toggled the prompt 33 times in 4 s, and the server made 1 002 reads, each of the
  same 200 keys about 5 times.
- **Fix** (`Main.server.luau`, the Star Chart):
  - Reads wait per viewer (`friendJobs`) and are served round-robin (`friendTurn`), at 1 read per second per
    server as before.
  - Every job carries its view's generation. A newer press or a switch to Public drops the old reads, including
    when its `GetFriendsAsync` lands after the yield.
  - At most one `GetFriendsAsync` per viewer is in flight.
  - The 300 s score cache is checked when a read is due, not only when it is queued.
- **Tests, failing first:** `check_meteordroptycoon_board` §5, with `GetFriendsAsync` stubbed at 0.3 s per page of
  50:
  - an honest view loads within 10 s behind a 200-friend view (6 s measured);
  - a second honest view loads within 12 s behind a prompt-spammer (9 s, with three viewers reading in turn);
  - no key is read twice inside its cache (398 reads from the spam on, 0 duplicates);
  - the spammer's own view still finishes.

  On the original: 203 s, 1 000 s, and 200 keys read twice.
- **After:** the reviewer's probe gives 6 s with 6 reads (honest) and 6 s with 7 reads (spam).

### A5 (low): `afterLoad` spawned the Falling Star after a yield without re-checking ownership. CLOSED

- **Reproduced:** `check_x_strayStar join`. An owner with Beacon 40 and star 1 left during `afterLoad`'s board
  read. The next player on Plot_1 was paid 18 888 Stardust and a Star Core, and the server announced "Stranger
  caught a Falling Star!". The owner kept star 1.
- **Fix:** `spawnStar` refuses a plot its session no longer owns (`s.leaving`, `sessions[s.plr] ~= s`,
  `plot.owner ~= s.plr`). `afterLoad` also returns after its board read if the player left.
- **Tests, failing first:** `_save` L1 (the join path; on the original: 4 failed), L2 (the grant path, the owner
  leaving mid-grant) and L3. In L3 the grant's write outlasts the leave's 60 s wait for it, so the plot is freed
  before the write lands, and only `spawnStar`'s guard protects it. L3 was added after mutant R5 survived (see the
  mutation table).
- **After:** both reviewer probe paths leave nothing on the freed plot and pay the stranger 0.

### A6 (low): a rejoin re-armed the sleeping Collector for 10 minutes without a hand pickup. CLOSED

- **Reproduced:** `check_x_afk`. The Collector was asleep after 600 s with no hand pickup. After a rejoin it showed
  `awake` = 599 s and made 53 dish catches in the next 300 s.
- **Fix:** the profile saves the Collector's awake time (`Save` field `awake`, written with every write, clamped
  to 0..600). A record without it starts awake, so a new player's first Collector works at once. On load the
  session carries the saved time, unless it made a hand pickup during the load.
- **Why seconds left, not a timestamp:** robloxemu's `os.time()` is the wall clock while its task clock is virtual,
  so a timestamp could not be tested. Offline time is not subtracted, so a player keeps at most what they left
  with. That is never more than staying.
- **Tests, failing first:**
  - `Save.spec` (9 new assertions on the field; 10 failed on the original);
  - `_save` M (asleep, leave, rejoin: still asleep and 0 catches in 120 s; a brand-new player starts with 600 s).
  - The original showed 598.8 s and 24 catches.
- **After:** `check_x_afk` shows `awake` = 0 s after the rejoin and 0 dish catches in 300 s.

## Reachability lens

### B1 (medium): the hopper was full a fifth to over half of the climb, and the refusal contradicted the HUD's star. CLOSED

- **Reproduced:**
  - Pacing model, 20 seeds, join to the star: the hopper was full 18.5% of the time (median; p90 24.3%), and the
    dish lost 16.8% of its catches.
  - The instrumented walk on the original, 9 runs: full 8.4-32.5% of the time, 14.7-45.1% of dish catches
    bounced, and 19-64 "Hopper full!" refusals per walk that said "Upgrade the Smelter" while the star was on
    another machine.
  - Cause, as the reviewer said: the star's steady model caps the hand rate at 0.4/s, and rares and epics overfill
    a Smelter that only matches the average.
- **Fix** (`Economy.luau`, `Config.Smelter`):
  1. `StarHeadroom` = 0.85: the star treats the Smelter as full at 85% of its rated melt.
  2. The star listens to the hopper. The server keeps `fullEma`, a 30 s moving share of the time the hopper was
     full, reset when a Smelter level is bought. At `StarFullShare` = 10% or more, the star is on the Smelter.
     This rule applies only once a first machine is bought, so the first ★ stays the Beacon (DESIGN [M8]). 40
     walks without that gate showed the cost: one rare filled a fresh 12-ore hopper, the star sat on the Smelter,
     and the first purchase came at 81 s instead of about 40 s.
     The server computes the star once (`bestOf`) and pushes a change before any refusal can quote it.
  3. `Economy.fullText`: the refusal names the Smelter only when the star is on it. Otherwise it says
     "Hopper full! It takes meteors again in N s."
  4. The pacing model (`tests/PlotModel.luau`) plays the same rule.
- **Sweep behind the numbers** (scratch copy):
  - Headroom alone: 0.80 put the model's star at 38.6 min, 0.75 at 39.2 min, and 0.65 at 46.3 min (past 45).
  - The measured fullness took the walker from about 11% full to about 7% (medians).
- **Tests, failing first:**
  - `Economy.spec`: the cap, a sweep of 17 builds whose supply sits at 90-98% of the melt rate where the star must
    be on the Smelter, the measured-fullness rule, and the refusal text.
  - `Pacing.spec`: full ≤ 8% and dish loss ≤ 8%, medians over 20 seeds.
  - `check_meteordroptycoon` §6:
    - a second full hopper with the star elsewhere: the refusal does not send you to the Smelter, and it says
      when the hopper takes meteors again;
    - a newcomer whose hopper is full keeps the star on the Beacon until the first purchase, and gets the Smelter
      after it (failed first: "got smelter, want beacon").
  - `walk`: 0 contradicting refusals (exact). The full and bounced shares are printed, not asserted. One walk is
    one draw, and the ranges before and after overlap: 40 fixed-game walks reached 20.2% full and 31.8% bounced,
    which the bounds I first set (20% / 25%) failed on correct code.
  - On the original: Economy.spec 4 failed and Pacing.spec 2 failed (both deterministic), the check 2 failed, and
    the walk's contradiction assertion failed in 9 of 9 runs.
- **After:**
  - Model: full 5.3% (p90 8.1%), dish loss 4.0%. The Falling Star is caught at 35.5 / 37.1 / 35.0 min (normal /
    slow / fast), against 35.6 / 36.2 / 36.0 before. The Galactic Core comes at 137.6 min, 3.87× the brag.
  - The anti-AFK macro still gains at most 1 level in 8 h, and the bot collects 0.998× a normal player at the
    same build (0.993× before).
  - Walk, 40 runs of the final build: full 7.3% median (1.0-15.1%), bounced 6.9% median (0.0-20.5%), and 0
    contradicting refusals in all 40. The star moved about once a minute, purchases included.
- **Residual:** what is left of the full time is mostly the wait to afford a Smelter level the star is already
  pointing at. In 4 diagnostic walks, 81-96% of the full samples had the star on the Smelter, and most of those
  were "not affordable yet".

### B2 (low): the star's Collector picks do not pay an active player, and the README overclaimed. HALF CLOSED

- **Reproduced:** with the shipped star, 16.8% of the dish's ore bounced (model; walker 14.7-45.1%). On the original
  source a star that never picks the Collector caught the Falling Star at 30.8 min, against 35.6 min (median, 20
  seeds; the reviewer measured 31.5 against 35.9).
- **Closed:** the bounces. With B1's fix the dish loses 4.0% (model) and 6.9% median (walker, 0.0-20.5%), and its catches now
  reach the hopper. The README sentence was rewritten to say what the star actually optimises: the upgrade that
  adds the most income for a player who walks to about one meteor every 2.5 s, kept ahead by the Smelter. It also
  says that a much faster collector reaches the Falling Star sooner by skipping the Collector.
- **Not changed, and why:** measured again on the final rule, the never-Collector star reaches the Falling Star at
  32.2 min (median of 20 seeds) against the shipped 35.5 min. Both are inside 30-45. The Collector is the machine
  for breaks: it catches while you rest. Making the star model an active player's real hand rate removes the
  Collector from the climb entirely. With headroom 0.85 and an assumed 0.8/s, the median Collector level at the
  star was 0 for the normal, slow and fast profiles.
  That changes the game's second-act milestone (first Collector around minute 11, the tutorial's Collector hint).
  This is the owner's decision; see "Still open".

### B3 (low): the hazard's red zone was drawn under the arrival pad. CLOSED

- **Reproduced:** `check_meteordroptycoon_hazards` §6b on the original. The zone on a player standing on the pad
  spanned y 0.22-0.42 under a pad top of 1.00.
- **Fix:**
  - The zone is a translucent column from the disc up to the highest LOW surface it overlaps, plus 0.2.
    `PlotGeom.zoneFloor` covers the pad, the Smelter's base and the Beacon's base, but never the Smelter's body or
    the board; `Config.Plot.ArrivalTopY` and related values describe them.
  - The hit rule is horizontal, so the column is exactly the zone at every height. `Sky.client` passes the floor
    and `SkyArt.showHazard` draws it.
- **Tests, failing first:**
  - `Meteors.spec`: 10 new assertions (on the pad, at its edge, a stud clear, past the corner, on the Smelter's
    apron, by the Beacon, out in the ring).
  - `_hazards` §6b: a locked hazard on a pad-standing player draws a top above the pad and a bottom at the disc,
    with the exact radius. A drift guard measures the three floors on the built parts.
- **After:** y 0.22-1.22 over a pad top of 1.00, radius 3.70. How it looks is EYECANDY §8 item 22 (needs Studio).

## Three flaky assertions the sweep found (test fixes, not game fixes)

Mutants that cannot touch a code path still failed it once each. Each turned out to be a timing or sampling race in
an existing assertion. None was weakened: each now waits for or samples the thing it means to check.

- **`_save` B** (owner-token takeover). The case waited 62 s for the session's next write. If a pickup on the pad
  made the session write just before the takeover, its 60 s autosave ran at a 7 s flush tick after the window.
  The window is now AutosaveSeconds + 2 flush ticks + 1 s = 75 s.
- **`check_meteordroptycoon` §7b and §8.** The trusted position walks to the far meteor in a straight line and
  collects what lies on the way. On Orion's untouched plot that can fill a fresh 12-ore hopper, and the far meteor
  is then refused until the hopper melts. §7b now waits up to 60 s (the "no sooner than a walk" bound is
  unchanged). §8's "unaffordable" refusal now uses the Collector (60 Stardust) rather than the Beacon (12), which
  Orion could afford by then.
- **`walk`, "the HUD explained the Collector before the walker bought it".** The walk sampled the hint only between
  shop visits. A star that moved to the Collector since the last step was bought before its hint was sampled. The
  walk now also reads the hint when it opens the panel, before tapping.

## Mutation table

Driver: `scratchpad/mdt_rv1/mut/sweep.py`, run in an isolated copy (`mut/work`), never in the repo. For each mutant
it:
1. restores every source from `mut/pristine`;
2. applies the edit (the old text must occur exactly once) and records the sha256 before and after;
3. rebuilds the bundle and confirms the mutated text is IN it;
4. runs all 20 gates;
5. restores the source, rebuilds, and confirms the restored file's sha256 equals the pristine one.

In every sweep, every entry had `inBundle = true` and `restored = true`. The repo's sources, tests and checks match
the final sweep's pristine copy byte for byte (`mut/repo_sha_final2.txt`, re-checked after the final gate run).

**Final sweep (10:00-10:15), on the final code and tests:** 19 of 19 mutants KILLED, both controls SURVIVED all 20
gates, the baseline green, and no gate failed for a reason the mutant could not cause.

**Earlier sweeps** are kept in `mut/old/`:
- First: R5 and R12 SURVIVED. Each exposed a missing test, not an equivalent mutant: `_save` L3 was added for R5,
  and `_board` §5 run 3 (two viewers sharing 50 friends) for R12.
- The first and second also tripped the three flaky assertions above.

| id | mutation (sha256 before -> after, first 12 hex) | killed by (failed assertions) |
|---|---|---|
| R1 | `LoadAttempts = 1` (Config c3ccefb24bc4 -> e151854846c7) | `_save` K (3) |
| R2 | `LockWaitSeconds = 0` (-> 0c729e2c379b) | `_save` H (4) |
| R3 | no `recheckLock` after a read-only start (Main.server 0bd6055ef402 -> 836f0e9a38cd) | `_save` I (5) |
| R4 | the re-check ignores data another server wrote (-> aac6e0b1cc48) | `_save` J (4) |
| R5 | `spawnStar`'s ownership guard removed (-> 79a48e31271b) | `_save` L3 (1); SURVIVED the first sweep |
| R5b | the guard AND `afterLoad`'s re-check removed (-> 98887e4e4e64) | `_save` L1 (5) |
| R6 | the catch writes inside the tick again (-> 19b2679f8adc) | `_save` N (1) |
| R7 | writes not serialised (-> 5e2c9e82fa9a) | `_save` O (1) |
| R8 | `pending` cleared after the write, the old order (-> 95946000265e) | `_save` P (1) |
| R9 | the Collector's awake time not saved (-> 8ce20c68f153) | `_save` M (2) |
| R10 | a loaded awake time ignored (Save 6c6ab8ad220d -> 82b73c709f72) | Save.spec (4), `_save` M (2) |
| R11 | friends reads FIFO again (-> b256ecb7156e) | `_board` §5 (2: 203 s, 203 s) |
| R12 | no score-cache check when a read is due (-> ed87d68239de) | `_board` §5 run 3 (2: 100 reads, 50 keys twice); SURVIVED the first sweep |
| R13 | `StarHeadroom = 1` (Config -> 782b1a93afcc) | Economy.spec (2), Pacing.spec (2) |
| R14 | the star ignores the measured fullness (Economy 2d51eec8a82c -> efa8abab52f2) | Economy.spec (2), check §6 Newbie (1) |
| R15 | the refusal always names the Smelter (-> dcb432447492) | Economy.spec (5), check §6 (2), walk (3 of 12 refusals contradicted the star) |
| R16 | the hazard zone drawn at the ground again (Sky.client 85e196cb5f86 -> c74852f24858) | `_hazards` §6b (1) |
| R17 | `ArrivalTopY = 0.5` (Config -> adbe992c1d14) | Meteors.spec (4), `_hazards` drift guard and §6b (2) |
| R18 | the measured fullness counts before the first purchase (Main.server -> b636b3414676) | check §6 Newbie (1) |
| C1 | CONTROL: the `LockTaken` wording (Config -> dada6327ac27) | SURVIVED all 20, as it must |
| C2 | CONTROL: the friends view's wording while its list is fetched (Main.server -> 4c555e06586e) | SURVIVED all 20, as it must |

## Final gates

Final run 2026-10-01 at about 10:15. The bundle was rebuilt first (md5 ada7a78ec4928d4f17ba29f064db2245).
**20 of 20 gates green.** The second pass's count is in brackets where this pass changed it.

| gate | result |
|---|---|
| Board.spec | 45 / 0 |
| Economy.spec | 119 / 0 (101) |
| EnvBands.spec | 124 / 0 |
| EnvConfig.spec | 132 / 0 |
| Hazards.spec | 153 / 0 |
| HudLayout.spec | 1 814 / 0 |
| Meteors.spec | 79 / 0 (69) |
| Pacing.spec | 11 / 0 (9) |
| Rest.spec | 55 / 0 |
| Save.spec | 54 / 0 (45) |
| Trace.spec | 22 / 0 |
| responsive.spec | 70 / 0 |
| check_meteordroptycoon | 195 / 0 (184) |
| check_meteordroptycoon_save | 109 / 0 (53) |
| check_meteordroptycoon_board | 40 / 0 (33) |
| check_meteordroptycoon_sky | 72 / 0 |
| check_meteordroptycoon_hazards | 44 / 0 (31) |
| check_meteordroptycoon_hud | PASS at 20 viewports, overlap = true (with the longest refusal toast up) |
| check_meteordroptycoon_compile | 194 / 0 (18 sources, 158 Enum uses) |
| walk | 22 / 0 (21; two noisy bounds of mine were removed again, see B1) |

**Walk, 40 runs of the final build, all green:**
- First Beacon at 0.68 min (0.68-1.02), first Smelter at 2.02 (1.68-2.35), first Collector at 10.70
  (9.36-15.70).
- 0.0-1.6% of meteors lost before the first dish catch.
- The Falling Star caught at **35.9 min median (32.3-38.6)**, 4.3-13.8 s after it fell.
- From join to the star:
  - the hopper was full 7.3% of the time (median; 1.0-15.1%);
  - the dish bounced 6.9% of its catches (0.0-20.5%);
  - 0 refusals contradicted the star in 40 walks;
  - the star moved about once a minute (0.86-1.28), purchases included.

The reviewers' own probes on the final game: see "After" under each finding.

## The complete-game standard (`docs/complete-game-standard.md`)

Status after this pass. Only §5 is not done, and it belongs to the night shift.

**§1 It works and is honest: met.**
- The core loop is reachable from join. The walk goes join, pickup, melt, HUD purchases, Smelter, Collector, dish
  catch, the Falling Star, rejoin, and a second loop. `check_meteordroptycoon` walks it too.
- Spawn order: unchanged and green.
- Nothing secret replicates. The attribute inventory under workspace and ReplicatedStorage is still 0. The new State
  field `lockChanged` is the owner's own save status.
- DataStore, strengthened in this pass:
  - every call is pcall'd;
  - the load retries and waits for a lock;
  - a read-only session takes the lock over only when it is gone and the data is unchanged;
  - `canSave` holds only while the lock is held, every write carries the owner token, and writes are serialised;
  - the one-time grant is written in one atomic write, and the Falling Star spawns only on a plot its session owns;
  - keys are strings.
- No silent no-ops. The hopper refusal now follows the star and never contradicts it.

**§2 It looks good from the first build: met.**
- The Dusk preset and the chimney sparks.
- 6 glided bands.
- Rare telegraphed hazards whose red zone is the hit zone, now drawn on top of the pad.
- Stargaze, which never earns anything.
- Budgets capped in code.
- The brag moment, inside the window:

  | measure | Falling Star caught |
  |---|---|
  | model, normal | 35.5 min |
  | model, slow | 37.1 min |
  | model, fast | 35.0 min |
  | built-world walk, 40 runs | 35.9 min median (32.3-38.6) |

- The long-term goal: the Galactic Core at 137.6 min, 3.87× the brag.
- Phone first: hudcheck PASS at 20 viewports, with the longest refusal on screen.

**§3 Players can compare themselves: met.**
- The Star Chart ranks a Beacon level only the server can raise, with the first-reached tie-break, in an
  OrderedDataStore. Its friends view is now fair under load: round-robin per viewer, each key read once per cache
  window.
- Nothing costs Robux. No gambling, no codes.

**§4 Ready to ship and to market: met.**
- README store text: 814 characters, no coloured-square emoji.
- EYECANDY: the needs-Studio list (§8, now 23 items; the second pass reported 20 where there were 21) and 4
  thumbnail shots.
- MARKETING: 7 clips.
- CLAUDE.md: updated with the gates, traps and numbers.
- Gates green (20 of 20), TDD, and mutation-tested with controls (19 of 19 mutants killed, 2 controls survived).

**§5 Night shift** (the Studio check, thumbnails, clips, the universe, publishing, marketing): **not done.** It is
forbidden to this stage.

## Still open

1. **B2, the owner's call.** A player who collects much faster than the star's assumed pace reaches the Falling
   Star about 3.3 min sooner by never buying the Collector (model: 32.2 against 35.5 min; both inside 30-45). The
   options:
   - keep it: the Collector is the break-time machine and the README now says so;
   - model the real hand rate: the Collector then drops out of the climb before the star;
   - give the dish something an active player values.
2. **The walker's remaining full-hopper time** (median 7.3%, up to 15.1% in 40 walks) is mostly saving up for a Smelter level
   the star already points at. If real players feel it, the Smelter's price growth (1.38) is the knob. It was not
   touched, because it moves the brag minute.
3. **Live-server behaviour no headless gate can settle:**
   - the join's lock wait and the re-check against real UpdateAsync latency;
   - Roblox's per-key write limit (the catch write about 4 s after the grant write);
   - real GetFriendsAsync pages;
   - DataStore budgets (robloxemu always reports 1 000).

   See EYECANDY §8 items 17 and 23.
4. **Rendering:** how the zone column looks (EYECANDY §8 item 22), and the rest of the 23-item needs-Studio list.
   The game has never been played by a person or opened in Studio.
5. **A load that fails all 3 attempts** still plays the whole session unsaved, and says so (steal-a-cryptid's rule:
   it cannot merge a blank session into the real profile later).
6. **No headless assertion reads the HUD hint for the "changed elsewhere" case.** Case J asserts the toast; the
   hint (`Config.Tutorial.LockChanged`) is the same sentence, set from the State field.
7. **Not committed, not published, no universe.** Git writes were out of scope for this stage.
8. **The pacing profiles are still assumptions.** The first-pass equivalent mutant M22 still stands.
