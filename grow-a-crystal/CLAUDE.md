# CLAUDE.md — Grow a Crystal (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/` and `plus1-jump/`;
same stack (CONFIG-driven, deterministic Rng, DataStore w/ canSave + soft session-lock,
pure logic tested with the luau CLI). Built from Game-Radar #2 (2026-09-05).

## What it is
Cozy idle-grow sim. Plant seed-crystals in a per-player cavern (grid of socket Parts) →
they grow over REAL time (offline counts) → harvest a mature crystal → a **refraction
roll** may climb its rarity tier (Shard→Quartz→Amethyst→Prism→Legendary→Mythic) → Gem
Dust → buy rarer seeds / chambers / luck+growth boosters → weekly Geode + codes + Gem
Codex. Single shared server, per-player plots.

## State (2026-10-01)
- **Live:** universe `10543994765`, place `106123351742435` — https://www.roblox.com/games/106123351742435
  Audience **Public**, genre Simulation, maturity Minimal / None. Last published **2026-09-10, version 11**
  (`publish_response.json`, via the git-ignored `publish_crystal.bat`). Everything since — the living cavern, review
  rounds 1 and 2, the owner's economy decisions, the highscore board — is **not live**.
- **Reach tier:** still "limited to 16+ users and trusted friends" — separate gate, needs 25 engaged players/60d OR
  1000 Robux spend. Lifts with real traffic.
- **Complete-game standard (`docs/complete-game-standard.md`): every item met in code and gates** except what only
  Studio or the owner can do (below). Pass 2 (2026-09-30/10-01, `EYECANDY.md` §15) added the public + friends board,
  the end-to-end walk check, the named brag moment, the readable hint, the store text and the clip list.
- **Gates: 17 specs + 24 headless checks, all exit 0** (last run 2026-10-01 in pass 2b: 1 392 spec assertions,
  1 531 check assertions + 2 PASS verdicts, bundle sha256 `c4b2bc7ce01d…`; per-suite counts in `EYECANDY.md` §7).
  luau-analyze has never run (fetching the binary needs the owner's explicit go).
- **Pass 1 re-run (2026-10-01, `EYECANDY.md` §16):** the reviewer's own probes reproduce all six round-2 findings on the
  reviewed tree and none on this one; round 2's 43-mutation sweep re-run 43/43; the last open owner decision taken
  (a paid pass never moves the board, `check_growacrystal_pass`).
- **Pass 2b (2026-10-01, `EYECANDY.md` §17):** the standard checked item by item again; three gaps closed test-first:
  a session that could not save was silent and never recovered (now it says so and retries, `check_growacrystal_rejoin`),
  the clip list could not be staged in Studio (codes and the Geode now work for the session when nothing can ever save,
  `check_growacrystal_clips`), and bands 2-3 had no critters/weather of their own (glowflies, fireflies, silk). The salt
  check's flake (1 in 40) is gone (virtual clock). Sweep: 24/24 mutants killed, 2/2 controls survived.
- **Seen in Studio: never since 2026-09-17.** `EYECANDY.md` §8 (items 1-35) is the night shift's list.

## Core model / important invariants
- **Growth is stateless**: a plant = `{tier, at=os.time()}`; maturity/progress derived on
  demand from `plantedAt` vs now (Growth module). Offline growth is therefore automatic.
- **Server-authoritative**: plant/harvest/buy/geode/redeem all validate + mutate server-side;
  ClickDetector checks the clicker owns the plot; harvest re-checks maturity.
- **Refraction** = the gacha: `Rarity.roll` climbs one tier at a time while a luck-boosted
  roll succeeds. Fresh Rng per harvest. Odds/tiers in `Config.Refraction`.
- **DataStore**: soft session-lock (load real data always; canSave = we hold the lock; short
  TTL renewed by autosave), atomic flush after redeem + geode so a crash can't dupe/lose them.
  `saveState` (runtime): `ok`, `locked` (another server's lock at load), `retry` (the load call failed), `nostore` (no
  DataStore, or a failed load in Studio). The join toasts every non-`ok` state; every autosave runs `retryLoad` for
  `locked`/`retry`: it takes the lock when free, keeps what was played if nobody wrote the record since (the lock
  fingerprint), else loads the newer record and rebuilds the cavern. Only `nostore` keeps a code's or the Geode's grant
  without saving (nothing persists there, so nothing can be duplicated).
  **Integer-key trap**: `plants`/`seeds`/`codex` use integer keys; DataStore JSON round-trips
  sparse integer keys to STRINGS — load normalizes them back to numbers (see loadProfile).
- **Highscore board** (standard §3, pass 2): ranks `totalDust` (dust EARNED FROM HARVESTS only, never a pass's bonus) in points of
  `Config.Board.DustPerPoint` (100), ties to whoever reached the points first. OrderedDataStore
  `GrowCrystal_LB_v2`, key `u_<userId>`, value `Board.encode(points, boardAt)` = `points * 2e9 + (2e9 - boardAt)`,
  written through `UpdateAsync` + `Board.keepHigher` only when the points rise (`writeBoard`, after a profile save
  lands). `boardAt` = when the points last rose (set in `grantHarvest`, saved). A physical board per cavern on the
  entrance wall behind the spawn (`Cavern.board`), drawn by the server; its ProximityPrompt toggles everyone/friends.
  Public top 10 read once per 60 s per server; friends only on demand, capped 200, cached, throttled; names cached
  server-side and sent to the HUD panel, never saved.

## Spawn placement — the engine wins, so WAIT for it (2026-09-10)
`Player.CharacterAdded` fires while the character Model is still **unparented** with its root at
the world origin; **one frame later** the engine parents it AND places it on the spawn, discarding
whatever the handler wrote (measured in Studio, `robloxemu/SPAWN-ORDER.md`). `task.defer` does NOT
outlast that — it resumes at the end of the *current* resumption cycle, still before the engine's
step. `onPlayerAdded`'s `place()` used to write the CFrame twice, the second time from a
`task.defer`, and **both writes were thrown away**: the player landed at `0, 3.01, -6` facing
`0, 0, -1`, turned exactly around with all six sockets 11.9 studs behind their back. It now polls
`while char.Parent == nil` (bounded, 300 frames) and writes after. The `SpawnLocation` pad +
`plr.RespawnLocation` stay — they are what keeps an unsteered spawn off the roof (`y = 50.51`
against a roof top of `48.0`) — but they cannot fix *facing*, because the pad is not rotated.
Guarded by `robloxemu/check_crystal_spawn.luau`, which replays the recorded engine order by hand:
`simulateSpawn` alone cannot see this, because the emulator drains `task.defer` **after** its
engine step and Roblox drains it **before**.

## The living cavern (2026-09-23) — read `EYECANDY.md` first
Client-side bands keyed to **chambers owned** (read from the player's own sockets in the world AND the State push),
a geode pulse, harvest bursts + a Legendary/Mythic beam, rare harmless visitors, 🛋 Relax. **No knock-down hazards** (justified in
EYECANDY.md §3). Server change: +9 lines, `lastHarvest = { n, socket, seed, tier }` in the State push, sent after the
roll is paid. Also fixed: the phone code drawer's Redeem button sat under the thumbstick on 640×300.
Built, unit + headless + mutation tested (resumed 2026-09-24: sweep survivor closed with `check_growacrystal_critters`,
shot list rebuilt against the real geometry, EYECANDY.md §7 and §12). **Adversarial review round 1 (2026-09-24): 3
findings, all fixed with a failing test first (EYECANDY.md §13):** (1, high) the HUD could lose the join push to the
cavern script — Roblox flushes a queued RemoteEvent to the FIRST connection only — so State now has ONE client
connection, `src/shared/StateFeed.luau`, that both scripts subscribe to; **never add a second `State.OnClientEvent`
connection** (`check_growacrystal_queue` asserts one); (2) the phone code answer was ~6 px, now it takes the whole row;
(3) Legendary flashes stacked, now at most one per `Config.Env.HarvestFlash.cooldown`. **NOT seen in Studio.** The two
findings that were left for the owner were DECIDED on 2026-09-30 (owner: take recommended) — see below.

## Review round 2 + owner decisions (2026-09-30) — `EYECANDY.md` §14, §11
Six findings, all reproduced, each with a failing test first and a GAME fix (nothing in the tests was loosened):
1. **Refraction roll predictable** (high). The seed is now `Rarity.rollSeed(now, socket, userId, salt)` with a salt drawn
   PER HARVEST from `rollSalt = Random.new()`, a local of `Main.server` (never saved, sent or an attribute). Odds unchanged
   (100 000-roll comparison in `Rarity.spec`). `check_growacrystal_salt`.
2. **A Mythic inside a Legendary row lost its flash, card and beam.** A higher tier skips the flash cooldown and replaces
   the older flash; card and beam belong to the rarest harvest still playing (`Grotto.flashDue(..., lastTier, tier)`,
   `Grotto.outranked`). `check_growacrystal_flash` (new assertions).
3. **Title card over the Relax button on landscape phones.** The card sits under the row. `check_growacrystal_row`.
4. **Uncapped per-plot lights/sparkles + a 5 s rebuild of every crystal.** Crystals are built once per plant and updated
   in place; `applyPlotBudget` + `Config.PlotBudget` (6 crystal lights, 48 sparkle particles/s, every ready crystal still
   glints). `check_growacrystal_plotbudget`.
5. **Saves had no owner token.** The load writes `old.session`; every save lands only while the record carries that token
   AND this server's jobId, else it is cancelled, the session stops saving and the player is told once.
   `check_growacrystal_lock`.
6. **Silent refusals.** Every refused action toasts the reason (`refuse()` / `seedRefusal()` in `Main.server`); an empty
   code says "Type a code first"; the phone toast line may use its whole 24-px height and the screen width (it was capped
   at 9 screen px). `check_growacrystal_refused`.
Owner decisions: the Shard seed costs **7** (was 10; 112 % payback), and a **dead end** (nothing growing, no seed, under 7
dust) gets a free Shard (`Economy.needsFreeSeed`); `Pacing.spec` now asserts payback, chamber 2 without codes in the median
session, and no dead end. The salt above is the other decision. Fetching luau-analyze was NOT taken (a download needs an
explicit go). A paid pass never moves the board (DECIDED 2026-09-30 (owner: take recommended), taken 2026-10-01):
`DoubleDust` doubles spendable dust, `totalDust` gets the un-doubled harvest (`check_growacrystal_pass`).

## Files
Server `src/server/Main.server.luau`; clients `src/client/Hud.client.luau`, `src/client/Grotto.client.luau` (the
living cavern); shared `Config/Rng/Rarity/Growth/Economy/Geode/Codex/Codes/Cavern/Fx/FxClient/Responsive.luau`, plus
`EnvBands.luau` + `Rest.luau` (templates from plus1-jump, verbatim), `Visitors.luau`, `Grotto.luau` (pure),
`StateFeed.luau` (the one client State connection) and `CavernArt.luau` (client-only art); tests `tests/*.spec.luau` + `tests/IdleModel.luau` (pacing model, not shipped).
Headless (in `robloxemu/`): `check_crystal.luau` (HUD fit), `check_crystal_sockets.luau`
(sockets are in the world and clicking plants), `check_crystal_spawn.luau` (where a spawning
player ends up and which way they face), `check_growacrystal_harvest/env/hud/row/join/race/critters/queue/queue_hudfirst/redeem/flash.luau` (the living cavern),
`check_growacrystal_salt/refused/lock/plotbudget.luau` (review round 2), `check_growacrystal_pass.luau` (a paid pass never
moves the board, 2026-10-01), `check_growacrystal_board/walk/hint.luau`
(pass 2: the board, the whole player path in one run, the first-run hint), `check_growacrystal_rejoin/clips.luau` (pass 2b:
the saving rules; every clip in `MARKETING.md` staged as written, in a session with no DataStore). Shared module `Board.luau` (the board's
pure rules, adapted from plus1-jump) and spec `tests/Board.spec.luau`.

## Gates (run all of them; every one must exit 0)
```
cd robloxemu && py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau   # rebuild the bundle FIRST
cd grow-a-crystal/tests && for t in *.spec.luau; do luau $t 2>&1 | tail -1; done          # 17 specs
cd robloxemu && for c in check_crystal*.luau check_growacrystal*.luau; do luau $c 2>&1 | tail -1; done   # 24 checks
```
`luau` is the luau CLI (this machine: the session scratchpad's `luau/luau.exe`; append `2>&1`). Check exit codes, not
just the last line (EYECANDY.md §7.2): `check_crystal` and `check_growacrystal_hud` print a PASS verdict, every other
suite prints `N passed, 0 failed`. There are no `tests/*.check.luau` files in this game.

## Traps this game has (keep them fixed)
- DataStore integer keys (plants/seeds/codex) come back as strings: `numKeys` on load.
- Spawn: wait for `char.Parent` before writing the CFrame (above); keep the SpawnLocation + RespawnLocation.
- ONE client connection to State (`StateFeed`); never add a second `State.OnClientEvent` connection.
- The roll's salt is per harvest and server-only; never derive it from anything the client sees.
- Every save checks the owner token + jobId; never write the record without it.
- A session that cannot save says so at join and retries (`saveState`, `retryLoad`); never let one play on silently.
  Keep a grant without saving ONLY in `nostore`, never in `locked`/`retry` or after a lost lock (that is a dupe). No
  chamber while `locked`/`retry`: `reloadInto` only builds the cavern up (`check_growacrystal_rejoin`).
- Crystal visuals are updated in place; never destroy/recreate them on the 5 s loop; effects go through `applyPlotBudget`.
- Never `return` out of a player action without `refuse(plr, reason)`.
- The Grotto row mirrors Hud.client's header geometry (`rowTop`); change both together (`check_growacrystal_row`).
- The board metric is dust EARNED FROM HARVESTS at its UN-doubled value: never add code, Geode or purchase dust, or a
  pass's bonus, to `totalDust`, and never write the board on a timer; `writeBoard` runs after a profile save lands and only when the points rose.
- Keep the board's encoded value exact: `Config.Board.MaxMetric * 2e9 < 2^53` (`Board.spec`); if the points ever
  approach the cap (1959 h of end-game play away today, `Pacing.spec`), raise `DustPerPoint` in a NEW store version
  (stored points would change meaning), never `MaxMetric`.
- Never record or screenshot the board's Friends view with a real account (it shows real friends' names).
- `check_growacrystal_walk` swaps `os.time` for the emulator's clock before loading the game; a new check that needs
  real growth time should do the same rather than seed `at = 1` plants. `_rejoin`, `_clips` and `_salt` do too (the salt
  check read the real clock and failed 1 run in 40 when a harvest straddled a second).
- Line endings: `src/shared/Grotto.luau` and `CavernArt.luau` are CRLF in this worktree, everything else LF. On Windows a
  Python text-mode write turns LF into CRLF (pass 2b did that once and put it back): edit with the Edit tool or binary I/O.
- Every critter zone stays above y 30 (`Grotto.spec`) and 3.5 studs over a head (`EnvConfig.spec`); a new band must bring
  a critter and a weather kind of its own (`EnvConfig.spec`), with a look in `CavernArt` and a zone in `Grotto.layout`.
- The emulator records a remote's payload BY REFERENCE (`State:sentTo`): `seeds` in an old push is the server's live
  table. Copy scalars before the action you are measuring.

## Next
1. **Night shift (Studio, 00:00-06:00):** `EYECANDY.md` §8 items 1-35; the §9 thumbnails (1920x1080); the clips in
   `MARKETING.md` (clips 4-6 need new scenarios in `tools/film_game.py`, staged with the codes in a session with no
   DataStore, which `check_growacrystal_clips` proves; clip 8 and shot 7 wait for the live server); then publish with
   `publish_crystal.bat` and replace the live store text with the one in `README.md`.
2. After it is live: marketing per `MARKETING.md` (one game at a time, labelled AI-assisted), and point
   `tools/content_schedule.py` at the re-shot clips.
3. Owner: an explicit go to download `luau-analyze`/`luau-compile` (never run on this game).
4. Optional, not planned for v1: gamepasses (`Config.Passes`; decided: a pass never moves the board),
   trading, more biomes.
