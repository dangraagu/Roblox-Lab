# REVIEW-1 — two adversarial reviews of SIGNAL LOST v1, closed (2026-10-01)

**Inputs:** an exploit review (3 findings) and a play review (5 findings), both run on scratch copies of the v1 build.
**Rules:** every finding is reproduced on the unchanged build first. The fix is test-first (the test is shown RED), and
it fixes the game, not the test. Every new assertion has a mutant that fails it, and the sweep includes a control.
No git writes, no Studio, no publish. Everything below was measured in this session; the reviewers' own numbers are
labelled as theirs.

## Findings

| # | sev | finding | reproduced (unchanged build) | verdict |
|---|---|---|---|---|
| 1 | high | A client that writes its own position crosses vacuum almost free | Reviewer's `check_rev_trust`: honest dock → V → B costs 2.70 s of AIR (3 of 3); the teleport has 2 ticks end in vacuum and costs 0.10 s, and the way back costs 0.00 s (5 of 5) | **CLOSED** |
| 2 | med | A leaving or shutting-down session keeps ticking; its stray saves re-lock the profile; a splice lands after the leave | `check_rev_relock` at 0.5 s latency: A (ride), B (hypoxic), C (mid-splice) all left the lock HELD for 45 s, and the rejoin was told "open on another server". C stored best 1 and salvage 12 (2 from the leave + 10 bonus). Shutdown of 6 riders: 2 of 6 locked at 0.3 s, 4 of 6 at 0.6 s | **CLOSED** |
| 3 | low | `BuyUpgrade` answers every call before any rate limit | `check_rev_flood`: 1000 replies to 1000 calls in each of 4 cases | **CLOSED** |
| 4 | med | Hazards almost never reach the player | Reviewer's `probe_hz2`, one campaign to relay 30: 8 of 8 warnings called off mid-telegraph, 0 with the player in the ring at arrival | **CLOSED** |
| 5 | low | The documented hazard rate is false on the real path | One warning per 3.32-3.59 min of play at k ≥ 5 over 4 campaigns, and 2.98-4.32 over 9 in all. README and DESIGN promised 2.5-2.6 | **CLOSED** |
| 6 | low | Client dressing is fixed before the splice, so it overlaps the floor hatch and relay console | Reviewer's `probe_rr2`: dressing on the floor hatch in 7-8 of 30 splices; a Tank in the console in 1-4 of 30 | **CLOSED** |
| 7 | low | REST within 5 s of a splice shows the wrong hint | Same probe: REST in the relay room read "Drop through the hatch to go deeper." | **CLOSED** |
| 8 | low | luau-analyze not run | No `luau-analyze` anywhere I searched (PATH, ~/.aftman, ~/.rokit, ~/.foreman, ~/.cargo/bin, scoop, Program Files, %LOCALAPPDATA%\Programs and \Temp\claude, D:\Claude, Documents) | **OPEN**: valid. Downloading a binary needs the owner's go |

None was rejected: all eight reproduced.

### 1. AIR was charged by the module a tick ended in
- **Fix:**
  - `Air.vacuumCharge`: a tick costs its time in vacuum or the trusted vacuum distance ÷ the vacuum walk speed,
    whichever is more.
  - Vacuum time already paid while covering less ground is kept as credit and covers a later burst, so a replication
    stall is never paid twice. The credit is capped at `Config.Air.CreditSeconds` = 1 and ends with the vacuum stretch.
  - `Trust.step(..., isVac)` reports `t.vacStuds` from the substeps it actually walked.
  - The last doorway of a route no longer aims 0.5 studs past a claim that is just over the edge. That detour would
    otherwise be charged to honest walkers.
  - The server drains `charge`, then refills if the tick ended in air.
- **RED → GREEN:**
  - Trust.spec §5: 17 failures (`vacStuds` nil).
  - Air.spec: `vacuumCharge` nil, then reach 468.2 against 314.8.
  - `check_signallost_review` R1: 0.10 s into V and 0.00 s out.
- **After:**
  - The honest walk dock → V → dock costs **2.80 s**, the same as before the fix.
  - The writer's whole visit to V costs **2.67 s**: 1.37 in, 0.30 standing (3 ticks), 1.00 out, the standing having
    been paid as credit toward the exit.
    That equals walking it.
  - Pure reach before blackout:

    | tank | honest walker | position-writing script, before | script, after |
    |---|---|---|---|
    | base | 314.8 studs (unchanged) | 468.2 | 315.9 |
    | maxed | 734.4 studs (unchanged) | 1034.6 | 736.6 |

- **Not done:** the reviewer's second suggestion, clamping the trust's banked burst to the vacuum cap. AIR is now charged
  per trusted stud, so the bank changes how fast a script moves, not how far its air goes. Clamping it would also throttle
  honest catch-up after a stall.
- **Residuals:**
  - A speed script still moves at 1.35 × speed, so it reaches the board's metric sooner, not higher.
  - A script gains at most 1 s of AIR per vacuum stretch, and only by first standing still that long.

### 2. Closing sessions kept ticking
- **Fix:**
  - The tick loop skips any `sess.closing`; `onCharacter`, `Died`, the lock-claim retry and `BuyUpgrade` return on it.
  - `saveProfile` refuses a non-releasing write once a session is closing.
  - `BindToClose` marks every session closing first, then runs all releasing writes at once and waits for them.
- **RED → GREEN:** `check_signallost_review` R2 had 12 failures.
- **After**, at 0.5 s latency, A, B and C:
  - every lock is released and stays released;
  - the rejoin holds its own file and the LIFT takes it down;
  - C stores best 0 and salvage = carried ÷ 2, and the public board holds no relay for it;
  - B records no blackout after the leave.
- **Shutdown** of 6 riders at 0.6 s latency: 0 of 6 locked, and every attempt is settled. `BindToClose` returns in
  **0.70 s** (it was 3.65 s, the writes one after another).

### 3. `BuyUpgrade` replies
- **Fix:** the cooldown is checked first, and "One moment…" is said at most once per cooldown window.
- **After:**
  - 1000 calls in one frame get **2 replies** in each case (id 42, id "x", "tank" away from the fabricator).
  - One nonsense call after the cooldown gets 1 reply, with its reason.
  - At the fabricator, 1000 calls give 1 rank, 1 write and 2 replies.
- The existing check J ("two requests inside 0.5 s buy once; the second one is told why") is unchanged and green.

### 4. Hazards called off at the module edge
- **Fix** (Hazards adaptation 4):
  - A live hazard whose player walks into another module of the same sector **locks its lane** and flies on through
    the ring they left: a near-miss behind them, with the banner at YOU ARE CLEAR.
  - It is called off only when the player leaves the sector: `ctx.module` false, or `ctx.sector` changed.
  - Env passes `sector = k`.
  - REST asked for in air while that debris still flies is queued and **said**: "Resting as soon as the debris has
    passed." This window did not exist before the fix, and without the line the REST tap would be a silent no-op.
- **RED → GREEN:**
  - Hazards.spec: 4 failures.
  - `check_signallost_env` G was rewritten to the new rule. It is RED under mutant M11.
  - The queued-REST line: 2 failures.
- **After:** `check_signallost_campaign` in 22 of 22 runs:
  - 0 hazards called off while the player is in the sector;
  - every warning ends in a finished flight;
  - nobody is shoved from outside the ring, and nobody inside it at arrival is missed;
  - near-misses on every run.

### 5. The rate
- **Fix:** `IntervalMin/Max` 80 / 120 → **55 / 85** s of eligible time.
- **Why the old figure was wrong:** the design rig assumed 62-65 % of play is eligible; the second reviewer measured
  50-57 % on the real client.
- **Measured:** per minute of all play from the first k ≥ 5 arrival to relay 30 (hub, rides and relay rooms included):
  - **one warning per 2.32-3.08 min, median 2.54**, over 47 campaigns (bot speed 1.0 × 41, 0.8 × 3, 0.65 × 3);
  - 8-12 warnings per campaign, the first in sector 5-11.
- **Gate:** `check_signallost_campaign` asserts 1.8-3.3 per run. That is the standard's "about": more than 4 sd either
  side of the median (sd 0.16). A strict 2.0-3.0 failed one run at 3.08.
- **Pinned:** `Config.spec` holds the interval, and `Hazards.spec` its eligible-time rate (52 an hour, one per 68.8 s).
- **Docs:** README, DESIGN §5.1 / §5.3 / §8.5 and EYECANDY §3 now give the measured figures.

### 6. The relay room
- **Fix:** `Env.client` keeps a keep-out signature per dressed module (which of ReturnConsole / RelayConsole /
  FloorHatch / RelayMast exist). When it changes, the module is dressed again around the new parts, in the band it was
  first dressed in.
- **After:** 0 pieces at any height on the floor hatch's footprint and 0 in the console, after every one of 30 splices,
  on every campaign run (RED: 9 and 4).

### 7. The REST hint
- **Fix:** the hint line puts resting before a timed event hint.
- **After:** the RESTING line shows in the relay room within a second of a splice (RED: "Drop through the hatch…").

### Also closed (the play reviewer's "could not verify")
- **The problem:** every prompt defaulted to gamepad **ButtonX**, which the HUD binds to REST, and the relay console's two
  prompts shared it. Roblox shows one prompt per button.
- **Fix:** fabricators and the board use **ButtonY**, the RETURN consoles **ButtonB**.
- **Gate:** `check_signallost_campaign` audits every prompt after the first splice. Any two prompts in reach at once
  must differ in key and button, and none may use ButtonX. Two prompts that do the same thing are exempt (the dock's
  RETURN beside the relay's).
- **Result:** 6 clashes before, 0 after.

### Gate flakes found on the way (check code only, no game change)
- **How they surfaced:** the control and repeated runs showed `check_signallost` failing 5 of 60 runs. The unchanged
  v1 sources failed 6 of 60 too (2 + 3 and 3 + 3 below), so neither flake came from this session's changes.
- **G (2 of 60):** the set-up took any salvage module *next to* the dock. On some maps that module has no doorway to
  the dock. Station guarantees the onboarding piece only behind a doorway.
- **L3 (3 of 60):** the bot's route through a salvage module picked the piece up despite `skipItems`, so no leftover
  existed.
- **Fixed:** G now takes a doorway neighbour; L3 retries with a fresh player, up to 5 times, under one aggregate
  assertion (171 → 169 assertions). **0 of 60** after.

## Mutation sweep (final sources, every gate per mutant)

The driver is `scratchpad/slr1/rev1_mutate.py`. Each mutant is applied as an exact replacement that must match once.
The bundle is rebuilt and grepped for the mutated text. Every spec except Pacing, all 7 headless gates and the walk then
run. The file is restored and its sha256 compared. All 23 runs: mutation found in `build/signal-lost.luau`, source
restored byte-identical. A diff of all `src/` and `tests/` hashes before and after the sweep showed no change.

| # | mutation | result |
|---|---|---|
| M1 | AIR charged by the tick-end module only (the reviewed rule) | KILLED: review R1 |
| M2 | Trust reports no vacuum distance | KILLED: Air.spec, Trust.spec, review R1 |
| M3 | the credit uncapped | KILLED: Air.spec |
| M4 | the credit outlives the vacuum stretch | KILLED: Air.spec, review R1 |
| M5 | the route overshoots the last doorway again | KILLED: Trust.spec (1.6 against 1.0 studs), Air.spec (honest reach 312.4 / 715.2) |
| M6 | a closing session keeps ticking | KILLED: review R2 C (the board records relay 1) |
| M7 | `saveProfile` lets a non-releasing write through while closing | SURVIVED, **equivalent**: every caller is already gated by the tick skip and the closing guards. M21 removes both |
| M8 | `BindToClose` back to the sequential loop | KILLED: review R2 D (3.65 s) |
| M9 | every call inside the cooldown answered | KILLED: review R3 (1000 replies) |
| M10 | the id checked before the cooldown again | KILLED: review R3 |
| M11 | a hazard called off at the module edge (the old adaptation 4) | KILLED: Hazards.spec, env G, campaign (9 called off in-sector) |
| M12 | a hazard from another sector not called off when the module id repeats | KILLED: Hazards.spec |
| M13 | interval 80..120 again | KILLED: Config.spec, Hazards.spec, campaign |
| M14 | interval 120..180 | KILLED: Config.spec, Hazards.spec, campaign (one per 5.08 min) |
| M15 | the relay room never dressed again | KILLED: campaign (21 on the hatch, 3 in the console) |
| M16 | a timed hint beats RESTING again | KILLED: campaign |
| M17 | prompts back on ButtonX | KILLED: campaign (3 clashes) |
| M18 | the relay RETURN on ButtonY with its fabricator | KILLED: campaign (1 clash) |
| M19 | Env passes no sector | SURVIVED, **equivalent**: on the real path a sector change always passes through a ride or a blackout, where the module is false. The pure rule is M12. One earlier run "killed" it on the rate bound (3.08), which is how the strict bound's flake was found |
| M20 | time AND distance charged (honest players pay twice) | KILLED: Air.spec (honest reach 214.0 / 555.2) |
| M21 | both close guards off (the reviewed code) | KILLED: review R2 A / B / C locks |
| M22 | the queued REST says nothing | KILLED: env G |
| **C1** | **CONTROL:** `BindToClose` polls every 0.05 s instead of 0.1 s | **SURVIVED every gate**, three sweeps |

**The control's history:** in its first sweep it was "killed" by the prompt audit's first version. The relay sat next to
the dock, so the two RETURN prompts were in reach at once. The audit now exempts prompts that do the same thing. The
control has survived every gate since.

## Final gates (final sources, bundle `1d0e1eab…`, rebuilt first)

| gate | result |
|---|---|
| Specs | **1253 / 0**: Air 64, Board 81, Config 121, Economy 120, EnvBands 124, EnvConfig 224, Hazards 157, MazeGen 3, Meter 19, Responsive 70, Rest 81, Rng 37, Station 46, Trust 82, Pacing 24 |
| `check_signallost_compile` | 49 / 0 (23 sources) |
| `check_signallost` | 169 / 0; 60 of 60 runs green |
| `check_signallost_board` | 61 / 0; 20 of 20 |
| `check_signallost_hud` | PASS; 20 of 20 |
| `check_signallost_env` | 233 / 0; 20 of 20 |
| `check_signallost_review` (new) | 46 / 0; 20 of 20 |
| `check_signallost_campaign` (new) | 16 / 0; 22 of 22 |
| `tests/walk.luau` | 91 / 0 (82 or 91 by how far it gets; 10 of 10) |
| `rojo build` | OK |
| luau-analyze | **NOT RUN**: no binary |

**The walk** (the player path, final sources):
- Spawn on HubSpawn at (4.00, 3.51, 0.00); boarding at 1.6 s; the dock opens at 4.6 s.
- Six sectors spliced in 135.4 s of play, with 0 blackouts and a minimum AIR of 7.8-20.0 s per sector.
- AIR TANK 1 bought at a relay fabricator 2.7 min after joining.
- Leave stored best 6, salvage 26, earned 146.
- On rejoin, sector 7 spliced after 55.6 s.

## The complete-game standard after this review
- **§1 Works and is honest:** MET.
  - The core loop runs from join (the walk).
  - Spawn order holds (check B).
  - The server is authoritative, and a script can no longer skip the AIR cost (finding 1).
  - DataStore: the lock survives a slow leave or shutdown (finding 2).
  - No silent no-ops: the queued REST is said; floods get one answer per window.
- **§2 Looks good:** MET.
  - Fx and bands as before.
  - Hazards: rare, telegraphed, one at a time, the ring is exactly the hit zone (no shove from outside it on the real
    path), and **about one per 2.5 min of play, measured on the real client** (findings 4 and 5).
  - Rest is never an exploit, as before.
  - Budgets are capped and measured (env).
  - The brag lands in 30-45 min **by the model only** (Pacing p50 36.9 min for the medium proxy, unchanged).
  - Phone first: hud PASS.
- **§3 Compare:** MET. A splice that finishes after a leave can no longer reach the board.
- **§4 Ship and market:** MET except luau-analyze.
  - README store text: unchanged, 997 characters.
  - EYECANDY: the needs-Studio item 8 now covers the gamepad prompts.
  - MARKETING: the hazard interval is updated.
  - CLAUDE.md: the two new gates and 6 new traps (17-22).
  - TDD and a mutation sweep with a control: done.
- **§5 Night shift:** NOT DONE, by rule.

## Still open
1. **luau-analyze** (finding 8): no binary on this machine; downloading one needs the owner's go.
2. **Player-player collisions** (the exploit reviewer's needs-Studio note): no CollisionGroup is set. A client that
   writes its position into another player's zone could stand in an 8-stud doorway or shove someone in vacuum.
3. **Real `UpdateAsync` latency, and `BindToClose` with 8 players on a live server:** headless shows 0.70 s for 6
   players at 0.6 s latency.
4. **Whether a near-miss behind a player who walked on reads as a near-miss on screen.** Most of the bot's near-misses
   are that kind; EYECANDY §8 item 7.
5. **The 1.35 × trust allowance and the 1 s credit** (finding 1's residuals) need real replication to tune; DESIGN
   §20 item 5.
6. **The floor hatch's keep-out circle** (radius 3.5) is 0.04 studs short of the hatch's half-diagonal (3.54). A piece
   could in theory overlap a corner by that much; the campaign gate measured 0 at any height.
7. **Nothing has been rendered or played by a person.** Nothing is committed: the task forbade git writes, so
   `signal-lost/` and `robloxemu/check_signallost*.luau` exist only in the working tree.

**Files written in this review:**
- `signal-lost/src/server/Main.server.luau`
- `signal-lost/src/shared/{Air,Trust,Hazards,Config}.luau`
- `signal-lost/src/client/{Env,Hud}.client.luau`
- `signal-lost/tests/{Air,Trust,Hazards,Config}.spec.luau`
- `signal-lost/{README,DESIGN,EYECANDY,MARKETING,CLAUDE,REVIEW-1}.md`
- `robloxemu/check_signallost_{review,campaign}.luau` (new)
- `robloxemu/check_signallost{,_env}.luau`
- `robloxemu/build/signal-lost.luau`
