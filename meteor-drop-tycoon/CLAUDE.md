# CLAUDE.md — Meteor Drop Tycoon (Roblox)

Read `DESIGN.md` for the why of every number, `EYECANDY.md` for the sky, hazards, rest, budgets, the needs-Studio
list and the thumbnail shots, `MARKETING.md` for the clips, `README.md` for the store text, `REVIEW-1.md` for the
two adversarial reviews and what changed because of them.

## What it is

A chill drop-and-collect tycoon for 8 players on 8 round plots around an observatory. Meteors fall on your own plot
(a glow 1.5 s ahead), you walk over them, the Smelter melts ore into Stardust, Stardust buys the Beacon (more,
richer, rarer meteors and a new sky band), the Collector (a dish that catches with no walking and sleeps 10 min after
your last hand pickup) and the Smelter. Six sky bands follow the Beacon; the Falling Star at Beacon 22 is the brag
moment; the Star Chart ranks Beacon level (public + friends). No PvP, nothing for Robux.

## State (2026-10-01)

v1 built test-first from `DESIGN.md` and **green in every gate below**. **Never played by a person, never opened in
Studio, not published, no universe, nothing committed.** Nothing only Studio can settle has been settled: that list
is `EYECANDY.md` §8.

Second build pass (2026-10-01, morning): until then no gate ever tapped an upgrade row's BUY button (every purchase
in every check was `Buy:simulateFireServer`), the rejoined walker had no HUD, and the walk stopped at 11.7 min, before
the brag moment. `tests/walk.luau` now buys only by tapping ⬆ Upgrades and the starred row's gold BUY button, plays on
to Beacon 22 and catches the Falling Star, then rejoins with a fresh HUD (written failing first: 3 failures, then
green). Its new assertions were mutation-tested (table below), which found a defect in the walk itself: the
"never falls again" count was taken after the rejoin, so a re-granted star was already in it. Fixed.

Third pass, REVIEW-1 (2026-10-01): two adversarial reviewers (exploit/correctness and reachability) found 9 issues;
all 9 reproduced, 8 are closed in the game with tests written failing first, and the ninth is half closed (the
dish's bounces) with the rest an owner's call (`REVIEW-1.md`). Summary of what changed: the load retries and waits
for a lock, and a read-only session takes the lock over when it clears; writes are serialised per session; the
Falling Star's catch writes from its own thread; a star never spawns on a plot its owner left; the Collector's
awake time is saved; the friends board reads round-robin per viewer; the HUD's star keeps the Smelter ahead and
listens to the hopper, and the "Hopper full!" refusal follows the star; the hazard zone is drawn on top of the pad.

## How to run every gate

The luau CLI is `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe`
(call it `luau`). luau-compile / luau-analyze no longer exist on this machine; `check_meteordroptycoon_compile`
keeps the compile half.

```
# 1. pure specs, from meteor-drop-tycoon/
luau tests/Board.spec.luau        luau tests/Economy.spec.luau    luau tests/EnvBands.spec.luau
luau tests/EnvConfig.spec.luau    luau tests/Hazards.spec.luau    luau tests/HudLayout.spec.luau
luau tests/Meteors.spec.luau      luau tests/Pacing.spec.luau     luau tests/Rest.spec.luau
luau tests/Save.spec.luau         luau tests/Trace.spec.luau      luau tests/responsive.spec.luau
# 2. ALWAYS rebuild the bundle before anything headless (a stale bundle has cost this repo hours)
cd ../robloxemu && py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
# 3. headless gates, from robloxemu/
luau check_meteordroptycoon.luau           # the real player path (see below)
luau check_meteordroptycoon_save.luau      # lock, owner token, the Falling Star grant, failures, retries
luau check_meteordroptycoon_board.luau     # the Star Chart, public + friends, rendered on the owner's board
luau check_meteordroptycoon_sky.luau       # bands, seams, glide, budgets, streaks, Stargaze, client writes nothing
luau check_meteordroptycoon_hazards.luau   # where/when hazards launch, ring = zone, 8-direction dodge, rest
luau check_meteordroptycoon_hud.luau       # hudcheck, 20 viewports, overlap = true
luau check_meteordroptycoon_compile.luau   # compiles, no string require, every Enum item is real
# 4. the walk, from meteor-drop-tycoon/
luau tests/walk.luau
```

Last full run (2026-10-01 ~10:15, REVIEW-1 pass, bundle rebuilt first, md5 ada7a78e...): 20 of 20 gates green, every
count below re-measured (the second pass's count in brackets where REVIEW-1 changed it).

| gate | result |
|---|---|
| Board.spec | 45 passed, 0 failed |
| Economy.spec | 119 / 0 (101) |
| EnvBands.spec (plus1-jump, verbatim) | 124 / 0 |
| EnvConfig.spec | 132 / 0 |
| Hazards.spec (the merge) | 153 / 0 |
| HudLayout.spec | 1 814 / 0 |
| Meteors.spec | 79 / 0 (69) |
| Pacing.spec | 11 / 0 (9) |
| Rest.spec (plus1-jump, verbatim) | 55 / 0 |
| Save.spec | 54 / 0 (45) |
| Trace.spec (vault-runners, adapted) | 22 / 0 |
| responsive.spec (verbatim) | 70 / 0 |
| walk | 22 / 0 (21) |
| check_meteordroptycoon | 195 / 0 (184) |
| check_meteordroptycoon_board | 40 / 0 (33) |
| check_meteordroptycoon_compile | 194 / 0 (18 sources, 158 Enum uses) |
| check_meteordroptycoon_hazards | 44 / 0 (31) |
| check_meteordroptycoon_hud | PASS at 20 viewports (hudcheck's 10, then the same 10 with panel, the longest refusal toast, hint and warning up), overlap = true |
| check_meteordroptycoon_save | 109 / 0 (53) |
| check_meteordroptycoon_sky | 72 / 0 |

**Mutation sweep** (2026-10-01, on the final code, in an isolated copy under the scratchpad; each mutant's md5
recorded and confirmed present in the rebuilt bundle; all 20 gates run per mutant; a gate that dies without a summary
counts as KILLED): **25 of 26 mutants KILLED**, both controls SURVIVED.

| mutant | killed by |
|---|---|
| M1 RespawnLocation not set in PlayerAdded | check_meteordroptycoon (dies: no pad) |
| M2 pickups test the raw claim | check_meteordroptycoon §7b |
| M3 the 20-meteor cap ignored | check_meteordroptycoon §9 |
| M4 no owner-token check | _save B |
| M5 the star spawns though its grant write failed | _save C |
| M6 a session locked elsewhere saves | _save A |
| M7 hazards off your own plot | _hazards §3 |
| M8 hazards during the Falling Star | _hazards §7 |
| M9 ring smaller than the zone | _hazards §6 |
| M10 the column does not move with the panel | HudLayout.spec, _hud |
| M11 a legendary goes through the hopper | Economy.spec, _save D |
| M12 the board tie-break uses the write time | _board §3b |
| M13 the board written on every improvement | _board §2 |
| M14 the sky snaps | _sky (glide) |
| M15 the first meteor lands anywhere | check_meteordroptycoon §4 |
| M16 tap targets not grown on touch | HudLayout.spec, _hud |
| M17 Beacon price growth 1.20 | Economy.spec, Pacing.spec |
| M18 the Collector never sleeps | Meteors.spec, Pacing.spec |
| M19 no Buy rate limit | check_meteordroptycoon §8 |
| M20 no Collector clamp on load | Save.spec |
| M21 no CharacterAdded correction | check_meteordroptycoon §3 |
| M22 a non-saving session may write the board | **SURVIVED: equivalent.** `savedBeacon` (only set by a successful save) blocks the write on its own; M22b removes both guards and _save A kills it |
| M23 the ring is not red | _hazards §6 |
| M24 the weather cap bypassed | _sky (budget) |
| M25 Stargaze ends an idle rest | _sky (Stargaze) |
| CONTROL C1 the telescope's colour | survived all 20 gates, as it must |
| CONTROL C2 the fast profile's hit share | survived all 20 gates, as it must |

The first sweep's driver called `bash` from Python, which on this machine is WSL: every gate "ran" and printed
nothing, and all 27 mutants including both controls came back SURVIVED. It was caught because nothing was killed and
the bundle did not contain the mutations; the driver now calls Git Bash explicitly and flags any run with fewer than
20 gate lines or a mutation missing from the bundle.

**Walk sweep** (second pass, 2026-10-01, `scratchpad/mdt_r2/mutwalk.py`: an isolated copy, the original restored
before each mutant, md5 before/after recorded, the mutation confirmed in the rebuilt bundle, `tests/walk.luau` run per
mutant): **8 of 9 KILLED by the walk, the control SURVIVED.**

| mutant | walk result |
|---|---|
| MW1 every BUY button sends "beacon" | KILLED, 10 failed (no Smelter or Collector ever bought) |
| MW2 the BUY button is never connected | KILLED, 11 failed |
| MW3 a granted star never spawns | KILLED, 5 failed (no star, no card, no crown) |
| MW4 no crown on the catch | KILLED, 1 failed |
| MW5 no brag card | KILLED, 1 failed |
| MW6 a caught star resets to 0 on load (re-granted on rejoin) | KILLED, 1 failed. It SURVIVED the first sweep: the walk's "never falls again" count was taken after the rejoin; moved to before the leave |
| MW7 Beacon price growth 1.26 -> 1.30 | SURVIVED the walk (star at 44.7 min, inside 30-45); KILLED by Economy.spec (5 failed) and Pacing.spec (2 failed: slow player 45.2 min) |
| MW8 the wallet shows lifetime, not Stardust | KILLED, 1 failed (the rejoined HUD's wallet) |
| MW9 the starred row is not the server's best | KILLED, 10 failed |
| CONTROL the brag card lingers 5 s, not 4 | SURVIVED, 21 passed, as it must |

**REVIEW-1 sweep** (2026-10-01, `scratchpad/mdt_rv1/mut/sweep.py`, the same discipline: an isolated copy, sha256
before/after/restored, the mutation confirmed in the bundle, all 20 gates per mutant): **19 of 19 mutants KILLED, both
controls SURVIVED** on the final code and tests (R18, the first-purchase gate on the measured fullness, included). The first run had R5 (spawnStar's guard alone) and R12 (no cache check
when a friends read is due) surviving, which added `_save` L3 and `_board` §5 run 3. The full table is in
`REVIEW-1.md`. The sweep also exposed three flaky assertions, all fixed by waiting for or sampling the thing they
check (`_save` B's window, `check_meteordroptycoon` §7b/§8, and the walk's Collector-hint sampling). The driver is
`python` with `PYTHONIOENCODING=utf-8`, because a ★ in a failure line kills the cp1252 console.

`check_meteordroptycoon.luau` is the real player path: 8 plots built AND parented, exactly one enabled
SpawnLocation each and none elsewhere, a joining character lands on its own pad under the engine's spawn order
(also after a respawn and with RespawnLocation cleared), every prompt reachable, the first meteor lands 10 studs
ahead and walking onto it fills the hopper and then Stardust, a purchase moves the level, the tower and
leaderstats, play continues until the star points at the Collector and the dish catches, a full hopper refuses a
pickup with a toast, a visitor cannot collect, a teleport buys nothing (pickups use the trusted position), refusals
always speak, the Buy flood is cut at 8/s, budgets hold, the attribute inventory under workspace and
ReplicatedStorage is empty, nothing is red, a rejoin restores every saved field, 8 players fill 8 plots and a ninth is
kicked with a reason.

`tests/walk.luau` is somebody playing, through the HUD only: it lands on its pad, reads the hint, walks to meteors
(0.8 s reaction, 85% of WalkSpeed), and every 20 s, when ⬆ Upgrades shows its ★, taps it open and taps the starred
row's BUY button while that button is gold; a tap counts only when the server's level for that machine moved by one.
It plays loop 1 (first pickup, melt, first Beacon), loop 2, on through the first Smelter and Collector to a dish
catch, then to Beacon 22, the Falling Star (the toast, the brag card, the gold crown, the Starfall chip), leaves,
rejoins with a fresh HUD (the wallet shows the restored Stardust, the star does not fall again) and plays one more
loop. It runs in about 11 s; every run differs (nothing is seeded).

## Invariants and this game's traps (each is asserted somewhere; the gate is named)

- **Spawn** (`robloxemu/SPAWN-ORDER.md`): every plot's Arrival is a real, enabled SpawnLocation built before anyone
  joins; `PlayerAdded` sets `plr.RespawnLocation` synchronously, before any yield; `CharacterAdded` waits (bounded,
  300 frames) for `char.Parent`, re-reads the session, re-points RespawnLocation, and corrects a root more than 8
  studs from the pad. Assert XZ, not Y (`check_meteordroptycoon` §3, §11).
- **Pickups test the TRUSTED position only** (`Trace.luau`: vault-runners' module with three marked edits:
  Config.Trace speeds, its burst setting, y follows the claim both ways). Plot-local coordinates. The 3 s banked
  burst means a single teleport after standing still is credited up to 64.8 studs, never faster on average than
  21.6 studs/s (`Trace.spec`, `check_meteordroptycoon` §7b).
- **Nothing is seeded.** Every draw is one server-lifetime `Random.new()`; pure modules take `rand`. There is no
  Rng.luau and nothing a client could re-run (fork-tower REVIEW-4). Consequence for checks: every headless run
  differs; the checks are written to hold for any draw and were run several times each.
- **No attributes under workspace or ReplicatedStorage** (the check enumerates them and requires 0). Debug values
  for checks live in `ServerStorage.PlotInfo.<userId>` (anomaly-observatory's rule). Names carry only visible facts:
  `Incoming_Rare` is the glow everyone already sees; `Meteor_Rare` the landed rock.
- **Saving:** the load is an `UpdateAsync` that takes the lock with a fresh `session` token (or returns nil and
  touches nothing when another live server holds it); `canSave` only while holding it; every write is `UpdateAsync`
  that cancels when `old.session ~= token` and then stops saving (fork-tower REVIEW-4 §10). REVIEW-1: the load is
  tried 3 times (1 s, 2 s apart) before the session plays unsaved (`_save` K, E); a lock is re-read every 5 s for up
  to 15 s at the join, with a toast (H); a session that still starts read-only re-checks every 15 s and takes the
  lock over only when it is gone AND the record's data is exactly what it read (I), else stays unsaved and says
  rejoin (J). A session that lost its token never switches back (B). Writes are SERIALISED per session (`writing`;
  the flush skips, the grant, the catch and the leave wait their turn, O); `pending` is cleared before the yield (P);
  a write that lands after the leave began never re-locks (`release or s.leaving`, read in the transform). A player
  who leaves while the load is in flight gets the lock released. Integer keys never appear (`Save.pack`, F).
- **The Falling Star is a one-time grant inside one atomic write:** a saving session writes `star = 1` with the whole
  profile and spawns the star only after that write lands; on failure the player is told and it retries every flush
  tick; a non-saving session spawns it at once (an unsaved grant cannot be redeemed twice); the catch writes
  `star = 2` with its Stardust at once, FROM ITS OWN THREAD (REVIEW-1: inside the 10 Hz tick a 3 s write froze every
  plot for 3 s, `_save` N); `star = 1` falls again on rejoin (`check_meteordroptycoon_save` C, D, G). `spawnStar`
  refuses a plot its session no longer owns, and `afterLoad` re-checks after its board read (REVIEW-1: a stranger
  was paid 18 888 Stardust from a freed plot, `_save` L1-L3).
- **The Collector's awake time is saved** (`Save` field `awake`, written with every profile write; a record without
  it starts awake). REVIEW-1: a session used to start awake, so an auto-rejoin every 10 min re-armed it (`_save` M).
- **The HUD's star** (`Economy.bestNext`) caps the Smelter at `StarHeadroom` 0.85 of its melt and is on the Smelter
  whenever the hopper was full `StarFullShare` 10% of the recent time (`Economy.fullEma`, 30 s half-life, reset when a
  Smelter level is bought), from the first purchase on (before it the first ★ is the Beacon; `check` §6 Newbie). The server computes it once (`bestOf`) for the State payload and the refusal, and pushes a
  change before any refusal quotes it; `Economy.fullText` names the Smelter only when the star is on it. The pacing
  model plays the same rule (`PlotModel`: `fullEma`).
- **The Star Chart writes only what was SAVED** (`savedBeacon` / `savedBeaconAt`, set by a successful profile
  write), only when it improves, at most once a minute plus once on leaving, never from a non-saving session.
  `beaconAt` is when the level was first reached, not the write time. The owner's board is re-sent every 30 s (the
  first send can arrive before the HUD listens). Friends: GetFriendsAsync capped at 200, at most one in flight per
  viewer; reads 1/s per server while the GetAsync budget stays above 10, ROUND-ROBIN per viewer (REVIEW-1: one FIFO
  let a 200-friend list hold everyone else for 203 s), each job tagged with its view's generation, the 300 s score
  cache checked when a read is due (a key is never read twice inside it); friends in the server read from memory.
  robloxemu has no GetFriendsAsync, which is the "unavailable" path; `check_meteordroptycoon_board` §5 stubs one.
- **The HUD's layout is one pure function** (`HudLayout.luau`) that both client scripts call, so Hud.client's pieces
  and Sky.client's chip, Stargaze button and warning can never drift apart. The upgrade rows are placed explicitly
  (no UIListLayout: Roblox would override the positions hudcheck measures) and the canvas is the rows' extent. The
  title cards are TextLabels (never Active), placed below the stack and left of the button column; they are not
  Frames, so hudcheck's overlap rule does not see them and `HudLayout.spec` checks them instead. The Star Chart's
  SurfaceGui sits in a Folder in PlayerGui (`BoardGuis`), where hudcheck skips it; Roblox rendering it there is
  needs-Studio item 13.
- **Sky.client never fires a remote and never writes a server part** (`check_meteordroptycoon_sky`). It reads the
  upgrade panel's visibility each frame to move the Stargaze button. Its `MeteorSkyProbe` BindableFunction in
  PlayerGui is a read-only window for the headless checks; nothing in the game reads it.
- **Hazards.luau is a MERGE** of plus1-jump's template (2026-09-30, with `threatLive`) and deep-vein's marked vertical
  section. When plus1-jump's template changes, re-merge and re-run the merged spec. Off your own plot counts as rest
  for the hazard clock (`resting = resting or not onOwn`); `canDodge = false` from the star's grant to its catch.
- **Stargaze during an idle rest turns it into a stargaze** rather than ending it (found by the sky check).
- **The hazard zone is a column** from the disc up to the highest low surface it overlaps (`PlotGeom.zoneFloor`:
  the pad, the Smelter's base, the Beacon's base; `Config.Plot.ArrivalTopY` and friends describe them and
  `check_meteordroptycoon_hazards` §6b measures them on the built parts). REVIEW-1: drawn at the disc, 57-81% of a
  zone on the pad was hidden under it.
- **The first meteor lands 10 studs in front of the pad, and the Falling Star 4 studs in front of it,** inside the
  5-stud pickup radius of a player still standing on the pad: such a player catches the star without a step. The
  save check moves its player away first; whether to move the showcase is EYECANDY §8 item 19.

## robloxemu and machine quirks met while building this

- `Player.DisplayName` does not exist in robloxemu (reads nil): the server uses `displayName(plr)` with a Name
  fallback. `FireClient` fires `OnClientEvent` for every connection, whoever the target: checks that run the client
  scripts use one player. robloxemu's `Enum` accepts any item: the compile check's hand-written list catches typos.
  `Random.new()` without a seed is time-seeded, so runs vary. `tick()` is the virtual clock.
- A PointLight never given `Enabled` reads nil headless (Roblox: true): count lights as `Enabled ~= false`.
- **The scratchpad is shared with other agents.** Another agent's `scratchpad/mut` and `scratchpad/gates.sh` were
  there; name scratch files uniquely (this build used `scratchpad/meteordrop_mut/`). Python's `subprocess` `bash`
  is WSL on this machine: call `C:/Program Files/Git/usr/bin/bash.exe` explicitly.

## Files

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
src/server/Main.server.luau   world, meteors, pickups, Smelter, Buy, saving, the Falling Star, the Star Chart
src/client/Hud.client.luau    wallet, hopper, toasts, hint, Upgrades + panel, the Star Chart rows, the ⭐ over your plot
src/client/Sky.client.luau    bands, streaks, hazards, Stargaze, band chip / warning / title card
src/shared/  Config Economy Meteors PlotGeom Board Save HudLayout Trace SkyArt  (game)
             EnvBands Rest Responsive FxClient (verbatim)  Hazards (merge)  Fx (+ Presets.Dusk)
tests/       *.spec.luau (12), PlotModel.luau (the pacing model), walk.luau (the player's path)
design/      model.luau + model.out.txt (the design-time model DESIGN.md quotes; PlotModel supersedes it)
REVIEW-1.md  the two adversarial reviews of 2026-10-01: each finding, its fix and test, the mutation table
../robloxemu/check_meteordroptycoon*.luau (7)
```

## Things the suite does not see

- Anything rendered: colours, readability, beams, bloom, the SurfaceGui, the camera tilt (EYECANDY §8).
- Real physics: the knock (PlatformStand + velocity), sitting without a seat, walking with a thumbstick.
- Real networking: replication delay between the server's glow and the client's streak, remote queueing, real
  DataStore throttling and budgets (robloxemu returns a budget of 1000 always).
- Real players: the pacing profiles are assumptions. Over 20 walks (a scripted normal player, 2026-10-01) the first
  Beacon came at 0.67 min (median; max 1.01), the first Smelter at 2.34 (2.34-2.68) and the first Collector at 11.03
  (10.36-11.69), against the model's 0.67, 2.34 and 11.02. The walk loses more than the model: 11 of 20 walks lost
  nothing, 7 lost 0.6-1.9% of their meteors, and two lost 4.8% and 7.5% (burned on a full plot or bounced off a full
  hopper), where the model says 0.000 of the ore (median). The scripted walker keeps standing on a meteor its full
  hopper refuses while others pile up; a person reads "Hopper full!" and buys the Smelter. Watch this in real play:
  if people lose ore this way, the star's steady-income rule (`Economy.bestNext`) should weigh a full hopper.
  Second pass, 12 walks buying only through the HUD (2026-10-01): first Beacon 0.68 min (0.68-1.02), first Smelter
  2.69 (2.02-2.69), first Collector 11.03 (10.70-11.70); lost before the first dish catch 0.0-5.1% of meteors (6 of 12
  lost under 0.5%); the Falling Star caught at **35.9 min median (32.9-36.9)** against the model's 35.6, 5.9-13.9 s
  after it fell (the walker finishes its current target first; a person would turn at once). 12 of 12 green.
  REVIEW-1, 40 walks of the final build (all green): first Beacon 0.68 min (0.68-1.02), first Smelter 2.02
  (1.68-2.35), first Collector 10.70 (9.36-15.70); lost before the first dish catch 0.0-1.6%; the Falling Star caught
  at **35.9 min median (32.3-38.6)**, 4.3-13.8 s after it fell; from join to the star the hopper was full 7.3% of the
  time (median; 1.0-15.1%) and the dish bounced 6.9% of its catches (0.0-20.5%), with 0 refusals contradicting the
  star (the shipped star before REVIEW-1, 9 walks: full 8.4-32.5%, bounced 14.7-45.1%, 19-64 contradicting
  refusals). The star moved about once a minute (purchases included). What is left of the full time is mostly the
  wait to afford a Smelter level the star is already on: watch it in real play.

## Next (night shift, 00:00-06:00, per `docs/complete-game-standard.md` §5)

The Studio check of EYECANDY §8, thumbnails (EYECANDY §9), clips (MARKETING.md), then the universe, publishing
(a git-ignored `publish_*.bat`), the maturity questionnaire, and only after that marketing.
