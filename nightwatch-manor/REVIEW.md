# Nightwatch Manor - adversarial review

**Verdict: BLOCK**

Built and reviewed 2026-09-09/10. NOT published, and not to be published until the
findings below are closed. Every one of them was proved by running something, not by
reading - the proof is quoted with each.

## Findings (6)

### 1. The hunting Nightwatcher is strictly faster than the player from 0.8 seconds into night 1 and every moment thereafter, so once it has seen you there is no counterplay. Hunt speed = (11 + 9*dread) * 1.45 = 15.95 at dread 0, rising to 29.00 at dread 1. The player is fixed at 16: `grep -rn "WalkSpeed|Sprint|JumpPower|Humanoid\b" src/` returns nothing, so there is no sprint and the server never raises WalkSpeed. Breaking sight requires getting two rooms away (sight is 55 studs and rooms are 40, so an adjacent room is always in range), and getting two rooms away requires being faster than it. The game's own on-screen advice at Main.server.luau:939 — notice(plr, "SPOTTED", "IT SEES YOU", "Break line of sight and keep moving.") — instructs the player to do the one thing the numbers forbid, as does the paste-ready store description's "Outsmart the Nightwatcher's chase — hide, run, survive". Hiding works; running does not.

**Where:** `src/shared/Config.luau Config.Watcher (BaseSpeed 11, SpeedPerDread 9, HuntSpeedMul 1.45) vs. the player's un-modified Roblox WalkSpeed of 16`

**What it costs a player:** This is the core loop, it reaches every player on every night, and it is not on the builder's notDone list. A new player with no upgrades is caught every time they are seen. The only escapes that exist are never being seen, or already standing next to the exit. The counterplay the game advertises in its own HUD text and its own store copy does not exist. Buying it back costs 1541 relics (all 5 Bear Trap levels, computed via Upgrades.cost), which only moves the crossover to dread 0.413 — and Bear Traps raise hubLevel, which enlarges the manor and lengthens the crossing (see the hubLevel finding).

**Proof:** Two independent measurements, both against the real code. (1) Kinematics: I tabulated Watcher.speed(Config, dread, watcherSlow, true) against 16 across the night and binary-searched the crossover — no upgrades, the hunter is faster from dread 0.004, i.e. 0.8s into a 210s night 1; with 5 Bear Traps, from dread 0.413. (2) Behaviour: I drove the REAL server in robloxemu with a player fleeing at exactly 16 studs/s toward whichever linked room was farthest from the watcher, swept nights 1-12 with no upgrades. The player was spotted on 7 of 12 nights and was caught on 7 of 7 of those — it never once escaped. Median survival after being seen: 2.4s (night 1: spotted at 0.1s, caught at 3.8s; night 2: spotted 0.1s, caught 2.0s). For fairness I also proved the game is NOT unwinnable: a player who ignores every relic and beelines for the exit extracts on night 1 in 6.1s, and taking 1 or 2 relics first still extracts (4.9s / 12.8s); taking 3 gets you caught at 9.0s. EVICTED never fired in any run, so the 210-second dread timer is dead content — the watcher ends every failed night long before dread does.

### 2. A joining player is dropped into a completely empty world and free-falls until a blocking DataStore round-trip finishes. There is no SpawnLocation anywhere, Players.CharacterAutoLoads is never set false, and every safehouse is built at x = index*3000, y = 100 — the first player gets index 1, i.e. x = 3000. I confirmed in the emulator that the workspace contains 0 BaseParts before anyone joins, 0 SpawnLocations, and 0 BaseParts within 500 studs of (0,0,0) even after a player has joined and their zone is fully built. The teleport that rescues them is gated behind claimProfile's synchronous UpdateAsync at line 1162, which runs before the zone even exists.

**Where:** `src/server/Main.server.luau:1157-1250 (onPlayerAdded) — claimProfile at :1162 blocks on DataStore UpdateAsync before acquireZoneIndex/buildSafehouse/teleport at :1176-1252`

**What it costs a player:** This is the first thing every player experiences. At Roblox's gravity of 196.2 studs/s^2 the character reaches the default FallenPartsDestroyHeight of -500 in roughly 2.3-2.5 seconds of fall. DataStore UpdateAsync latency routinely exceeds that on a cold server or under throttling, at which point the character is destroyed, the player dies without ever seeing the game, and waits the default 5-second RespawnTime before the CharacterAdded handler finally teleports the second character. The builder's notDone item 8 does flag the missing SpawnLocation but characterises it as briefly falling at the world origin and calls it the cheapest bug on the list; it does not connect it to the blocking DataStore call in front of the teleport, which is what turns a cosmetic stutter into a death and a respawn. The fix is also not simply adding a SpawnLocation, since zones are per-player at x = index*3000 — it needs Players.CharacterAutoLoads = false plus an explicit LoadCharacter() once the zone is built, or a static platform at the origin.

**Proof:** Ran the real server headless with an instrumented runner: before any player joins the workspace holds 0 BaseParts and 0 SpawnLocations; after a player joins, their zone index is 1 with safehouse origin (3000, 100, 0) and manor origin (3000, 100, -400), and there are still 0 BaseParts within 500 studs of (0,0,0) on all three axes. Read confirmed the ordering in onPlayerAdded: claimProfile (UpdateAsync) at :1162, zone creation at :1176, buildSafehouse at :1237, the CharacterAdded connect at :1221 and the already-has-character fallback teleport at :1249 — all strictly after the network call returns.

### 3. The headline determinism claim is false. The README states "A manor is seeded from WorldSeed and the night number and nothing else — not your userId. Night 7 is the same manor for every player in the world, which is what makes 'I got out of night 14' a claim worth comparing." The SEED is indeed only WorldSeed+night, but the PLAN is not: Manor.roomCount folds in hubLevel, which changes the room target, which changes the grown tree, the exit room, the relic placement and the patrol. Night 7 is a 9-room manor with the exit at grid(2,1) depth 3 for a player with no upgrades, and a 13-room manor with the exit at grid(2,2) depth 4 for a player at hub level 12. The same README asserts the opposite two paragraphs earlier ("The manor also grows with your hub level"), so the document contradicts itself.

**Where:** `README.md "Determinism" section and CLAUDE.md "Core model / invariants", vs. src/shared/Manor.luau Manor.plan / Manor.roomCount (which take hubLevel) called from src/server/Main.server.luau:1082`

**What it costs a player:** Comparability of the best-night number is the entire stated justification for accepting the deliberate cost of memorisable layouts ("the trade-off is real and accepted" in CLAUDE.md). The cost was paid and the benefit was not received: two players who both report surviving night 14 did not survive the same manor, and the one with the bigger safehouse crossed a strictly larger one. Worse, Upgrades.hubLevel sums EVERY upgrade level, so every purchase in the game enlarges the manor and lengthens the walk to the exit — against a hunter the player cannot outrun. That is a silent anti-synergy in a tycoon: spending relics makes extraction harder in a way nothing on screen tells the player. Best night is also written to an OrderedDataStore that nothing reads back (builder's notDone item 9), so the claim is currently unfalsifiable in-game as well as untrue.

**Proof:** Ran Manor.plan against the real Config for nights 1, 7 and 14 at hubLevel 0 and hubLevel 12, comparing a full room signature (id:kind@gx,gz for every room). SAME LAYOUT was false for all three nights: night 1 = 6 rooms exit=room 5 vs 10 rooms exit=room 8; night 7 = 9 rooms exit=room 8 vs 13 rooms exit=room 11; night 14 = 12 rooms exit=room 10 vs 16 rooms exit=room 14. Confirmed Upgrades.hubLevel sums all levels by reading src/shared/Upgrades.luau, and confirmed Main.server.luau:1082 passes that hubLevel straight into Manor.plan.

### 4. Neither gate can see whether the game is playable. I mutated the two parameters that decide it and both mutations passed everything. HuntSpeedMul 1.45 -> 5.0 (the hunter chases at 55-100 studs/s against a player fixed at 16 — an instant, unavoidable death every night) SURVIVED all 390 spec assertions and all 84 headless assertions. SightRange 55 -> 2000 (it sees you anywhere in the manor the room rule allows) also SURVIVED everything. The builder's own report lists "retuning Watcher.HuntSpeedMul" as a deliberate CONTROL — a change the suite is designed NOT to notice — which is precisely why the un-outrunnable hunter shipped green.

**Where:** `The gate itself: tests/*.spec.luau (390 assertions) plus robloxemu/check_nightwatch.luau (84 assertions), against src/shared/Config.luau Config.Watcher`

**What it costs a player:** This is the reason the first finding exists and the reason it would have reached players. Every gate in the repo asserts structure (is it parented, is it prompted, does the arithmetic round correctly) and none asserts outcome (can a player who does a reasonable thing survive). A difficulty regression of any magnitude is invisible, so the balance of the core loop is currently unprotected by anything. The repo's own stated purpose — catching the class of defect that stays green through every unit test — is not being served for this class.

**Proof:** Applied 15 source mutations one at a time with an exact-match asserting patcher (refusing to proceed on a pattern miss, which caught one bad pattern of mine and voided that result), running all six specs plus a fresh wrap.py rebuild plus check_nightwatch.luau after each, then restoring. KILLED (11): relic draw with replacement (Manor spec, 2), cost never escalates (Upgrades 2 + headless 4), payout ignores relicValue (Night 2), DreadMin floor removed (Night 1), roomAtWorld unbounded (Manor 1), effects max-clamp removed (Upgrades 1), pedestal double-take guard removed (headless 2), BaseSpeed 11->55 (headless, but only incidentally — it caught the player during the check's 3-second patrol advance and crashed the run at line 327, it did not detect unplayability), SightHalfAngleDeg 50->180 (Watcher 5), DreadSeconds 210->15 (Night 2). SURVIVED (4): HuntSpeedMul 1.45->5.0, SightRange 55->2000, and the two ownership guards below. CONTROL (renaming a room kind) correctly SURVIVED, so the harness was not simply reporting everything as killed. All files restored; 17/17 sha256 match baseline and the rebuilt bundle is byte-identical to the builder's.

### 5. The Alarm Bell's catalog blurb describes a function the code cannot perform. Watcher.hears is a pure proximity test — it takes only warnRange and the two positions, ignores facing entirely, works through walls, and has no access to whether the watcher has seen anything. The server then fires the NEAR notice only in the `elseif near and not spotted` branch, so the bell is silent in exactly the case its blurb advertises. When the watcher HAS seen you, you get the SPOTTED notice, which you would have received without ever buying a bell. Watcher.luau's own comment is explicit that this is deliberate: "Distinct from sight on purpose."

**Where:** `src/shared/Config.luau Config.Upgrades.Catalog, the alarmbell entry: blurb "Warns you sooner that it has seen you", vs src/shared/Watcher.luau Watcher.hears and src/server/Main.server.luau:936-944`

**What it costs a player:** This is a paid item: 120 relics for level 1, escalating at 1.9x to 433 for level 3. The player is buying an early-warning-of-detection that does not exist; what they actually receive is a through-wall proximity ping, which is useful but is a different product. At level 1 the 25-stud range also sits well inside the 55-stud SightRange, so the first level — the one every buyer purchases — is the weakest version of a mechanic the blurb has already mis-sold. Store copy that promises what the code does not do is the exact habit the README says this repo is trying to break; the same sentence applies to a catalog blurb the player reads at the point of sale.

**Proof:** Read Watcher.hears (signature is `hears(warnRange, wx, wz, px, pz)` — no facing argument, no sight argument, no roomOk argument, so it is arithmetically incapable of knowing about detection), and read the notice dispatch at Main.server.luau:936-944 confirming NEAR fires only under `elseif near and not spotted`. Cross-checked the client at src/client/Hud.client.luau:440-446, whose own comment confirms the intended split ("SPOTTED is 'it is coming for you', NEAR is only what the Alarm Bell heard through a wall") — the code is coherent, it is the catalog blurb that is wrong. Costs computed by running Upgrades.cost against the real Config.

### 6. Two of the three ownership guards are untested. I replaced the exit door's `who ~= plr` check with `if false then` — anyone could end your night — and the entire suite plus the headless check stayed green. Same result for the relic pedestal's guard. The headless check does test this pattern, but only on an upgrade pad ("a STRANGER firing my pad spends none of my relics"), so the coverage does not extend to the two prompts inside the manor.

**Where:** `src/server/Main.server.luau — the exit-door prompt handler in buildManor and the pedestal prompt handler in buildManor (both `if who ~= plr then return end`)`

**What it costs a player:** Low severity as the code stands, and I want to be explicit about that rather than inflate it: zones are 3000 studs apart (Config.ZoneSpacing) and makePrompt sets MaxActivationDistance = 12, so no second player can physically reach another player's exit door or pedestals. These guards are defence-in-depth and are currently correct. The finding is the coverage gap, not a live exploit — if the zone layout, the prompt range, or any future shared/co-op mode changes, these two handlers would silently become griefable and nothing in the repo would notice. The builder's report cites removing the `who ~= plr` guard on an upgrade pad as a killed mutation, which is true, and that result should not be read as covering the other two.

**Proof:** Mutation M7 (exit door guard -> `if false then`) and M8 (pedestal guard -> `if false then`), each applied to source with an exact-match patcher, each followed by all six specs plus a wrap.py rebuild plus check_nightwatch.luau. Both reported SURVIVED — 390 spec assertions and 84 headless assertions green with the guard removed. Both files restored and checksum-verified against baseline.

## What the review could NOT break (14)

- Unparented Instances — the defect class that shipped in this repo before. Clean by three independent methods. (1) Runtime: I monkey-patched the emulator's Instance.new to record every construction plus a traceback, then ran the full 84-assertion server playthrough — 435 instances created, exactly 1 live orphan, and it was the harness's own _scriptStub, not game code. (2) Runtime on the client path: same instrumentation booting the real HUD, replaying the server's recorded State payload and firing all ten Notice kinds plus a night transition — 225 instances created, 2 live orphans, both harness Script stubs. (3) Static: every one of the 45 Instance.new sites accounted for — 40 assign .Parent directly, 4 use the two-arg constructor, and the single one that returns to its caller (newPart at Main.server.luau:151, which parents via its props table) has all 50 of its call sites passing a Parent key, verified by a brace-balanced parser over multi-line calls.
- Path requires. `grep -rn "require(" src/` shows every require goes through an Instance (ReplicatedStorage:WaitForChild). No `require("./X")` anywhere, and the emulator harness independently rejects string requires at emu/harness.luau:212-218.
- DataStore at load. Both stores are pcall'd — GetDataStore at Main.server.luau:59-65 (with a warn and a nil profileStore on failure) and GetOrderedDataStore at :66-71. The server boots and the game is fully playable with saves off, which is what an unpublished place gives you.
- Leaks over a long session. Soak-tested 40 consecutive nights on the real server: workspace BaseParts held at exactly 19 (the safehouse baseline) after 10, 20, 30 and 40 nights, with 0 warnings and 0 scheduler errors throughout, reaching night 41 / best 40. Manors are torn down cleanly and the per-night task loops die on their token.
- The economy and the pure logic. Six mutations aimed at it were all killed: cost escalation, the per-upgrade max clamp in effects, the Relic Vault payout multiplier, the DreadMin floor, roomAtWorld's bounds check, and the relic draw's without-replacement property. Relic slots genuinely cannot collide, so two pedestals can never spawn inside each other.
- Zone index recycling and the free list, including the double-release guard. Verified by the headless check and by reading acquireZoneIndex/releaseZoneIndex.
- The pedestal double-take guard — mutating it away was killed by the headless check (2 failures). You cannot mint relics from an emptied pedestal.
- The session lock. claimProfile handles both Roblox UpdateAsync hazards correctly: the transform may run more than once (result is reassigned every call, so the last wins) and returning nil aborts the write (so losing the race leaves the other session's lock untouched). Ownership is a stable per-session GUID, not a rewritten timestamp.
- Manor connectivity. Growth-by-attachment yields a tree by construction, so there is no unreachable wing and no unreachable exit; pathBetween is a correct BFS. Confirmed by the specs and by walking real plans.
- HUD responsiveness — reproduced PASS across all ten viewports from 414x800 to 1920x1080 with both phone drawers opened by the warmup, panels covering 7.0-18.1%.
- Client trust boundary. The only remotes are State and Notice, both server->client; grep confirms no OnServerEvent anywhere. Every action really is an in-world ProximityPrompt.
- A geometry worry I chased and disproved: the ExitDoor slab (10 wide) is planted 6 studs inside the exit room's +Z face, which is where a doorway can be. It does not seal the room — the room is 40 studs wide, leaving 15 studs of clear floor on each side — so it is an obstacle, not a blocker. Reported here rather than as a finding because I could not make it trap a player.
- Whether night 1 is unwinnable, which finding 1 initially suggested. It is winnable — beeline to the exit extracts in 6.1s, and 1 or 2 relics still extract. I could not construct a hard softlock; the failure mode is loss of counterplay, not an unwinnable state.
- Note on scope: everything above was measured with the luau CLI and the headless emulator, which model no physics, no rendering and no Raycast. The player-collision consequences of anchored moving parts (the Nightwatcher's torso is CanCollide and moves by PivotTo), whether furniture snags a character, and whether the manor is legible in the dark remain unverified by anything and need a real Studio session — as the builder's notDone item 11 already says.


---

# Resolution log — 2026-09-10

Written by the builder, against the six findings above. Every fix has a test that was watched to
FAIL first; the failures are quoted. Still NOT published, NOT committed. Test totals moved from
390 spec + 84 headless to **479 spec + 113 headless**.

## 1. The hunter was strictly faster than the player — CLOSED

Two separate defects were holding this up, and fixing only the first left it standing.

**The speed.** The player's speed was not in the model at all. Nothing set `WalkSpeed`, so the
number the Nightwatcher was racing was Roblox's default of 16 — a value no config knew, no test
asserted, and no retune could see. `Config.Player.WalkSpeed` (20) is now real data the server
assigns onto every Humanoid, and `Watcher.speed` clamps itself LAST to
`Config.Watcher.MaxSpeedFraction * Config.Player.WalkSpeed`. A bare constant here can be retuned
back into the same state at some other value; a fraction of the thing it is chasing cannot. The
curve underneath was retuned to sit well below the ceiling (BaseSpeed 11 -> 8, SpeedPerDread 9 ->
2.4, HuntSpeedMul 1.45 -> 1.2), so the ceiling is a guard rail and not the operating point:
fastest the watcher ever moves is now **12.48 studs/s at dread 1 while hunting, against 20**.
Main.server sweeps the whole dread range at boot and `error()`s if that ever stops being true.

Red, from `tests/Chase.spec.luau` against the shipped build:

```
  fastest the Nightwatcher ever moves: 29.00 studs/s (dread 1.00, slow 0.00, hunting true) vs the player's 16.00
FAIL: the Nightwatcher is never faster than the player (fastest 29.00 at dread 1.00 ... vs walk 16.00)
  a fleeing player gains -13.00 studs/s -> -91.0 studs over a 7s hunt
FAIL: a fleeing player gains at least a room's width (-91.0 studs) over one hunt
FAIL: a hostile retune (BaseSpeed 55, SpeedPerDread 40, HuntSpeedMul 5.0) still cannot outrun the player (got 475.00)
  fleeing player, nights 1-12, no upgrades: seen on 9, caught on 7
FAIL: a player who is seen and runs is never caught: night 1 at 3.6s, night 2 at 2.9s, night 5 at 10.6s, ...
```

**The manor.** Fixing the speed alone did NOT close the finding, and this is the part the review
did not reach. `Manor.plan` grew by attachment, which yields a TREE — every branch ends. A dead
end is a kill against a pursuer at *any* speed, and the measurement said so: with the watcher
7.5 studs/s slower than the player, a fleeing player was still cornered on **8 of nights 1-12**,
six of those in a room with exactly one door, after standing still for 3-5 seconds because the
only way out was through it. 4-6 of every 6-11 rooms were dead ends.

So the generator changed too, in three ways that are all about the same thing — running has to
have somewhere to go. Growth is now weighted toward cells that already touch built rooms (fill,
don't grow tendrils); every other shared wall gets a doorway with probability `ExtraDoorChance`;
and a repair pass then closes any remaining one-door room by placing a room that touches both it
and something else, or by squaring the corner into a 2x2 block. The repair consumes no rng draws,
only ever adds, and is bounded by `MaxRepairRooms`. Measured over nights 1-60: **1.36 doorways per
room, 4 dead ends in 1090 rooms (0.4%), and no night that is a pure tree** — up from 1.0 doorways
per room and ~55% dead ends.

Green now, with the simulated player *ambushed in its face* on every night rather than merely
wandering: `ambushed player, nights 1-20, no upgrades: seen on 20, caught on 0`, and
`running straight away at full dread: out of sight after 6.2s` — i.e. inside the 7-second hunt
window, so the HUD's advice now describes something that can be done. That advice was reworded to
say which way the fight goes: **"You are faster than it. Run, and put a room between you."**

The honest consequence, stated plainly: the Nightwatcher can no longer run down a player who
keeps moving. It is now a positional threat — it blocks routes, forces detours and spends your
dread — and it catches people who freeze, corner themselves, or walk into it. That also makes
EVICTED live content for the first time (the review noted it never fired). Whether that is still
*frightening* is a question only a real Studio session answers, and it is written down as such.

## 2. A joining player free-fell in an empty world — CLOSED

Fixed at the cause, which was the ordering, not just the missing SpawnLocation:

* a plate and a `SpawnLocation` at the world origin, built at script load, before anybody can join;
* each safehouse's spawn pad **is** a `SpawnLocation` (not a decorative slab) and is assigned as
  that player's `RespawnLocation`, which also covers the respawn after a death — something no
  `CharacterAdded` teleport can be relied on to win;
* the character is placed on the **frame it appears** (it used to wait `task.wait(0.2)`), and
  `teleport` re-asserts the CFrame on the next frame via `task.defer`, because the engine finishes
  placing a spawning character after the handler returns — the grow-a-crystal lesson;
* **the zone, safehouse and spawn point are now built BEFORE `claimProfile`**, not after it. The
  blocking DataStore round-trip no longer stands in front of the world. Buying and entering a
  night are gated on `prof.loaded` so nothing can be spent against the default profile, and a
  `profiles[plr] ~= prof or plr.Parent == nil` guard after the yield stops a departed player's
  zone from being resurrected and leaked.

The review said "the harness cannot reproduce it: its DataStore is synchronous and never yields".
It can now: `check_nightwatch.luau` wraps the very store object the server is holding so
`UpdateAsync` takes a second, joins on a scheduler thread, and asserts the world exists mid-call.
Every one of these assertions was mutation-verified by putting the defect back:

```
== A: no floor/SpawnLocation at the world origin       KILLED (2 failures)
== B: RespawnLocation never assigned                   KILLED (4 failures)
== C: the spawn pad is a plain Part again              KILLED (2 failures)
== D: placement waits 0.2s instead of the spawn frame  KILLED — "the joining character is moved to its own zone on the SAME frame it appears"
== E: the profile round-trip blocks in front again     KILLED (6 failures, incl. "their zone exists WHILE the profile call is still in flight")
== F: WalkSpeed left to the engine default             KILLED — "and the server set its WalkSpeed from Config.Player -> got 16, want 20"
```

(F is also the finding-1 premise, confirmed independently: with nothing assigning it, the player
really does walk at 16.)

## 3. The determinism claim was false — CLOSED, by changing the CODE

Chosen deliberately over editing the README. Comparability of the best-night number is the entire
justification for accepting memorisable layouts, and the hub-level coupling was additionally a
silent anti-synergy: `Upgrades.hubLevel` sums EVERY level and the exit is always the deepest room,
so every purchase in a tycoon game lengthened the walk out with nothing on screen to say so.

`Manor.roomCount(cfg, night)` and `Manor.plan(rng, cfg, night)` no longer take a hub level at all,
and `Config.Manor.RoomsPerHubLevel` is gone. Manor.spec asserts the property rather than the
prose: a stray fourth argument must change nothing. Red first, against the shipped build:

```
FAIL: night 1 is the SAME manor for a hub-level-12 player as for a brand new one
   fresh   (6 rooms, exit=5): 1:foyer@0,0|2:chapel@0,1|3:hall@1,0|4:dining@0,-1|5:vestibule@0,2|...
   veteran (10 rooms, exit=8): 1:foyer@0,0|2:hall@0,1|3:dining@1,0|4:library@0,-1|5:cellar@0,2|...
FAIL: night 7 is the SAME manor ...   fresh 9 rooms exit=8   vs   veteran 13 rooms exit=11
FAIL: night 14 is the SAME manor ...  fresh 12 rooms exit=10 vs   veteran 16 rooms exit=14
```

Re-folding hubLevel back into `roomCount` afterwards is killed by those three assertions.

The README said both things in the same document; it now says one, and explains what it used to
say and why that was wrong.

## 4. Neither gate could see whether the game is playable — CLOSED

`tests/Chase.spec.luau` (79 assertions) asserts OUTCOMES rather than structure: the speed ceiling
across the whole dread range and every upgrade stack; that the ceiling survives a deliberately
hostile retune (BaseSpeed 55, SpeedPerDread 40, HuntSpeedMul 5.0); that there is a corner of the
next room the watcher cannot see; that an ambushed player who runs is not caught on any of nights
1-20, with and without Bear Traps; that running straight away breaks contact inside the hunt
window; that the manor has circuits and almost no dead ends; and that crossing the manor never
eats more than 40% of the night (worst: night 35 at 12.7%).

The two mutations that survived everything:

```
== HuntSpeedMul 1.2 -> 5.0                        KILLED (Watcher.spec: "hunting multiplies its speed -> got 13, want 40")
                                                  ...and no longer breaks the GAME: the ceiling absorbs it
== SightRange 55 -> 2000                          KILLED (Chase.spec: "but NOT in the far corner of that room")
== MaxSpeedFraction 0.65 -> 3.0                   KILLED
== the ceiling deleted from Watcher.speed         KILLED
== ExtraDoorChance 0.75 -> 0                      KILLED (2 nights cornered, 7.6% dead ends)
== MaxRepairRooms 5 -> 0                          KILLED (6 nights cornered)
== CONTROL: rewrite an upgrade blurb              SURVIVED (correct)
== CONTROL: rename a relic tier                   SURVIVED (correct)
```

Both controls still survive, so the sweep is not simply reporting everything as killed.
`HuntSpeedMul` has been removed from the list of documented controls in CLAUDE.md — it is
load-bearing now, and the suite is supposed to notice.

## 5. The Alarm Bell's blurb described a function the code cannot perform — CLOSED

The review is right that the code is coherent and the blurb is the lie, so the blurb changed:
"Warns you sooner that it has seen you." -> **"Rings when something is close, through walls and
around corners."** Upgrades.spec now asserts the property, not the sentence: the bell's blurb may
not contain "seen" / "sees" / "sight" / "spot", because `Watcher.hears` takes no facing argument
and no sight argument and is arithmetically incapable of knowing about detection. Red first:

```
FAIL: the Alarm Bell blurb does not say 'seen' — it hears, it cannot see
```

The 25-stud first level was checked rather than assumed and left alone: it clears the 20-stud
half-room, so level 1 does reach through the wall into the room next door, which sight cannot do
at all. That is asserted too, so a retune cannot make the first level a no-op.

## 6. Two of the three ownership guards were untested — CLOSED

The review is explicit that this is a coverage gap and not a live exploit (zones are 3000 studs
apart, `MaxActivationDistance` is 12), and that reading is correct. `check_nightwatch.luau` now
joins a second player and has them press the manor's exit door and a loaded pedestal. Verified by
putting each defect back:

```
== G: the exit-door owner check -> `if false then`   KILLED (3 failures, incl. "...and I am not told I got out")
== H: the pedestal owner check -> `if false then`    KILLED ("a STRANGER pressing my pedestal puts nothing in my bag -> got 3, want 2")
```

## What this log does NOT close

* **Nothing here has been run in Roblox.** The scope note at the end of the review still stands in
  full, and one item in it got bigger: the manor now has ~36% more doorways and up to 5 extra
  rooms per night, so there is more geometry for a character to snag on, and the Nightwatcher's
  anchored CanCollide torso moving by `PivotTo` is still unmodelled by anything.
* **Whether the Nightwatcher is still scary** is now an open design question rather than a
  measurement. It cannot run you down any more. That was the point, and it is a real change to how
  the game feels.
* **4 dead ends remain in 1090 rooms across nights 1-60** — shapes the repair pass cannot close
  inside its budget. They are rare, and the exit room is often a legitimate one, but a player who
  runs into one while being chased is still caught.
* The store description still says "relics **& cash**" (one currency), and traps still do not
  fire. Both were already on the notDone list and neither was touched.
