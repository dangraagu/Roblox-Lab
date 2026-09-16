# Nightwatch Manor - review after the first round of fixes

**Verdict: BLOCK**

Second pass, 2026-09-10. The reviewer verified each claimed fix with its OWN measurement
rather than by re-running the fixer's tests, and then went looking for what the fixing
broke. Read alongside REVIEW.md, which is the first pass.

## Independently confirmed closed (8)

- 1. THE HUNTER IS NO LONGER STRICTLY FASTER — CONFIRMED by my own sweep, not theirs. I swept Watcher.speed over dread 0..1 in 1000 steps x watcherSlow 0..MaxWatcherSlow in 40 steps x hunting {false,true}, plus out-of-range inputs (dread 5, dread -3, slow -1): the fastest the Nightwatcher ever moves is 12.48 studs/s (dread 1.000, slow 0, hunting) against Config.Player.WalkSpeed 20. Margin 7.52 studs/s = 52.6 studs over a 7s hunt, more than a 40-stud room. Patrol speed 8.00-10.40. The 'seen = caught, always' state is gone. It is also not decoration: a wall-respecting player who NEVER looks at the watcher and just walks the greedy full-clear route is caught on 39 of 60 nights (37/60 even with beartraps 5 / wardstones 5 / floodlights 4).

- 2. THE JOINING PLAYER HAS A WORLD — CONFIRMED structurally. src/server/Main.server.luau:393-412 builds OriginPlate + a real SpawnLocation at script load, before Players.PlayerAdded is connected at :1482. buildSafehouse (:634-647) makes the pad a SpawnLocation and assigns plr.RespawnLocation. onPlayerAdded (:1296-1402) does zone -> safehouse -> prompt wiring -> CharacterAdded -> placeCharacter ALL synchronously, and only then calls claimProfile at :1402. I re-verified by mutation: M5 (RespawnLocation never assigned) KILLED 4 headless assertions; M6 (WalkSpeed not set on the spawn frame) KILLED 'got 16, want 20'; M10 (character not placed on the spawn frame) KILLED 'moved to its own zone on the SAME frame it appears'. claimProfile is fully pcall'd (:457-475), so prof.loaded can never be stranded false by a DataStore error.

- 3. DETERMINISM — CONFIRMED by my own signature diff. For nights 1, 7, 14, 30, 60 I hashed the full plan (id:kind@gx,gz+depth for every room, sorted link list, relic room/slot/tier list, exitId, patrol) computed three ways: plan(rng,cfg,night), plan(rng,cfg,night,12) with a stray hub level, and plan again. 0 mismatches. Manor.roomCount(cfg,7)=9 and roomCount(cfg,7,12)=9. Config.Manor.RoomsPerHubLevel is gone. README.md:34-49 now states one claim and records the old one as wrong.

- 4. THE GATE CAN NOW SEE BALANCE — CONFIRMED. I mutated the NEW code 22 times with an exact-match patcher that refuses on a pattern miss. KILLED by Chase.spec alone: M1 WalkSpeed 20->16 ('a fleeing player gains at least a room's width (39.2 studs)'), M2 ExtraDoorChance 0.75->0.05 ('caught: night 10 at 104.4s, night 18 at 5.7s'; '6.8% dead ends'), M3 MaxRepairRooms 5->1 ('10.1% of rooms'; 'no night is generated as a pure tree -> got 1'), M7 repair rooms attach through one doorway instead of every shared wall ('22.2% of rooms', 6 nights caught), M18 the ceiling deleted from Watcher.speed ('hostile retune ... got 475.00'). Genuine CONTROLS survived: C1 reword a comment, C2 recolour the Nightwatcher's torso, M21 rename a relic tier, M22 rewrite an upgrade blurb — all SURVIVED at 592 passed, 0 failed, so the harness is not reporting everything as killed.

- 5. THE ALARM BELL BLURB — CONFIRMED. src/shared/Config.luau:159 now reads 'Rings when something is close, through walls and around corners.' tests/Upgrades.spec.luau:40-50 asserts the blurb contains none of seen/sees/sight/spot AND that one level (25 studs) reaches past the 20-stud half-room, so a retune cannot make level 1 a no-op. Watcher.hears(warnRange,wx,wz,px,pz) still takes no facing and no sight argument.

- 6. THE TWO OWNERSHIP GUARDS ARE COVERED — CONFIRMED independently. M19 (exit-door 'if who ~= plr' -> 'if false') KILLED 3 headless assertions ('...and does not advance it -> got 2, want 1', '...and I am not told I got out -> got 1, want 0'). M20 (pedestal guard) KILLED 2 ('a STRANGER pressing my pedestal puts nothing in my bag -> got 3, want 2').

- SUITE COUNTS, run by me at the end on restored sources: Chase 79/0, Manor 64/0, Night 64/0, Rng 32/0, Upgrades 99/0, Watcher 71/0, responsive 70/0 = 479 spec assertions, 0 failed. Headless (py -3 wrap.py --game ../nightwatch-manor then luau check_nightwatch.luau): 113 passed, 0 failed. check_nightwatch_hud.luau: PASS on all ten viewports. luau-compile --binary clean on all 8 sources; luau-analyze clean apart from Roblox-global noise and the pre-existing FunctionUnused 'approx' in tests/Night.spec.luau. All 20 tracked files sha256-match the pre-review baseline after every mutation.

- NOT COLLAPSED, checked because the brief warned about it: weighting growth toward compactness did NOT pile the manor into one shape. Nights 1-200 produce 197 distinct footprints, 59 distinct exit cells, and only 2 of 200 manors touch the GridSpan boundary. Over the full Config.Night.MaxNight range 1-500: 0 nights with no route to the exit, 0 pure-tree nights, 61 dead ends of 10350 rooms (0.59%), worst bare crossing 14.5% of the night (night 185) — so the spec's 1-60 sweep is not hiding a late-night blow-up.

## Still open (6)

### Finding 1's headline assertion is certified by a simulated player that walks through walls, and with that removed a chased player IS still caught. tests/Chase.spec.luau moves its player point-to-point with no collision — from a room corner straight to the next room's centre, which crosses the wall, not the 10-stud doorway that buildWall actually leaves. The substance of finding 1 is fixed (no counterplay -> counterplay), but the claim 'a player who is seen and runs is never caught' is a property of the bot, not of the game.

**Proof:** I audited their own bot's path against the real wall geometry (walls occupy |offset| 19.5..20.5 from a room centre; a doorway is |along| <= 5 on a LINKED shared edge): over nights 1-20 ambushed, 126 of 5445 studs (2.3%) of its escape crosses a wall rather than a doorway, in 2-3 ticks per night — and those ticks are the escape moments. Then I re-ran their EXACT bot (same candidate set, same 'furthest from the watcher', same CatchRadius+3 filter, same tick order, same ambush start) with one change: it may not cross a wall, and slides on X then Z the way a Roblox character does. Result: ambush=true walls=false -> seen 40/40, CAUGHT 0/40 (reproduces their number). ambush=true walls=true -> seen 40/40, CAUGHT 5/40, at 1.6-2.0s, in rooms of degree 2 and 3 — NOT dead ends. On a stricter doorway-graph model (room interiors convex, doors the only crossing) the same greedy bot is caught 34/40 and a competent path-planning player with 0.5s reaction is caught 11/40; ordinary foyer starts, competent, 6/40. The mechanism is a doorway snag, which is exactly the class the resolution log's own notFixed line calls unmodelled.

### The prof.loaded gate on ENTERING A NIGHT — the new guard that stops somebody really on night 14 walking into night 1's manor and having the load rewrite the night under them — is not tested by anything.

**Proof:** M11: src/server/Main.server.luau:1209 'if not prof.loaded then' -> 'if false then'. Result: SURVIVED, 592 passed, 0 failed. The in-flight test in robloxemu/check_nightwatch.luau:539-613 does hold the join inside a 1-second UpdateAsync and does press a pad, but it never presses the manor door in that window.

### The companion prof.loaded gate on BUYING is also untested — the assertion that looks like it covers it passes for an unrelated reason, so it is a fixture that cannot fail on the thing it names.

**Proof:** M13: src/server/Main.server.luau:695 'if not p.loaded then' -> 'if false then'. Result: SURVIVED, 592 passed, 0 failed. Cause: the in-flight test presses the lanterns pad against the DEFAULT profile, whose stash is 0, so Upgrades.canBuy already returns (false, 'poor') and the server still emits a DENIED notice and still builds no prop. Both assertions ('pressing a pad before the profile lands builds nothing' and '...and says so rather than failing silently') stay green with the gate gone.

### The position of the world-origin SpawnLocation is not asserted, so finding 2's exact failure mode can be reintroduced with a green gate.

**Proof:** check_nightwatch.luau:60-73 asserts only nearOrigin > 0 (ANY BasePart within 500 studs of the origin) and spawns > 0 (ANY SpawnLocation anywhere in the workspace). M12 (OriginPlate moved to y=-4000, SpawnLocation kept) SURVIVED 592/0. M15 (OriginSpawn moved to y=-4000, plate kept) SURVIVED 592/0 — and that is the engine spawning a character 4000 studs under the world, i.e. the free-fall-and-destroy this finding was about. Each object only covers the other's absence; neither is pinned.

### spawnPad.Enabled is untested, and a disabled SpawnLocation is not a legal RespawnLocation — which is what the fixer's own comment on that very line says.

**Proof:** M16: src/server/Main.server.luau:645 'spawnPad.Enabled = true' -> 'false'. Result: SURVIVED, 592 passed, 0 failed. The headless check asserts the pad exists, is a SpawnLocation, sits inside the player's zone, and is the RespawnLocation — but never that the engine would accept it. Flipping it silently reverts the respawn half of the fix (Roblox falls back to picking a random enabled neutral SpawnLocation, and every player's pad in this game is Neutral and Enabled).

### Nothing has been run in Roblox, and the fix enlarged the exact thing that is unmodelled. Every result above and in the resolution log comes from the luau CLI and a headless emulator with no physics, no rendering, no Raycast and no character collision — and the manor now has 1.375 doorways per room (up from 1.0) and up to 5 extra rooms per night.

**Proof:** My own doorway-collision measurement above is the concrete cost of that gap: it flips the headline claim on 5 of 40 nights using the fixer's own bot. Measured part load if a Studio session happens: night 1 = 10 rooms / 134 BaseParts / 23 PointLights, night 20 = 19 rooms / 255 parts / 41 lights, night 40 = 23 rooms / 302 parts / 46 lights (workspace totals 155 / 276 / 323).

## Broken BY the fixes (6)

### The new fourth boot guard cannot fire for three of the four causes its own error message names. It sweeps Watcher.speed(), which has ALREADY been clamped to MaxSpeedFraction * WalkSpeed before it returns, so 'worst >= walk' is unreachable for any MaxSpeedFraction < 1 no matter how hot BaseSpeed / SpeedPerDread / HuntSpeedMul get — yet the error tells the reader to 'Lower BaseSpeed / SpeedPerDread / HuntSpeedMul'. It can only ever catch a MaxSpeedFraction >= 1 misconfiguration.

**Proof:** src/server/Main.server.luau:361-380. M4: Config SpeedPerDread 2.4 -> 12 pins the watcher at the 13 studs/s ceiling for essentially the whole night (a large difficulty swing). The boot guard did NOT fire; the only failure was Watcher.spec's arithmetic assertion 'at dread 1 it has picked up the whole SpeedPerDread -> got 13, want 20'. And M17 ('if worst >= walk then' -> 'if worst >= walk and false then') SURVIVED all 592 assertions, so the guard is untested as well as unreachable.

### Config.Manor.MaxRooms = 18 is now silently exceeded on 96 of 120 nights, up to 23 rooms, because the repair pass appends up to MaxRepairRooms on top of the already-clamped target. Nothing asserts #plan.rooms <= MaxRooms. Night 1 grew from 6 rooms to 10 (+67%) — the first thing a new player walks into is two thirds bigger than the number in the config says.

**Proof:** My own count over nights 1-120 driving Manor.plan with the real Config: 96 nights above 18 rooms, largest manor 23. Per-night: night 1 target 6 -> BUILT 10, night 20 target 15 -> 19, night 40 target 18 -> 23. src/shared/Manor.luau:327 'local budget = target + M.MaxRepairRooms'. Confirmed in the emulator: night 1 builds 10 room folders, night 40 builds 23.

### The ExitDoor slab now stands directly in front of a live doorway on 51% of nights, up from a tree layout where that was rare. It is 10 studs wide — exactly DoorWidth — planted 6 studs inside the exit room's +Z face, so it is aligned with the doorway gap rather than beside it. The original review disproved this as a blocker against the OLD 1.0-doorways-per-room manor; ExtraDoorChance 0.75 plus the repair pass changed the input to that judgement.

**Proof:** src/server/Main.server.luau ExitDoor at 'centre + Vector3.new(0, 6.5, 14)', Size (10, 12, 1.2); buildWall puts the doorway gap at |x| <= 5 on the +Z face. My count over nights 1-120: the exit room has a doorway to the cell at (gx, gz+1) on 61 of 120 nights, and on 1 of 120 that is the exit room's ONLY doorway — i.e. the only way into the room you must reach is through a 10-wide gap with a 10-wide slab 6 studs behind it.

### CLAUDE.md still asserts the pre-fix claim finding 3 was about, in the file the next session reads first.

**Proof:** D:/Claude/Roblox/nightwatch-manor/CLAUDE.md notDone item 6, line 150: 'Hub level grows the manor, but nothing is locked behind it — the night simply advances when you extract.' Manor.roomCount no longer takes a hub level at all and Config.Manor.RoomsPerHubLevel is deleted, so the first clause is now false. The resolution log's own notFixed list admits this ('hub level no longer even grows the manor, so the safehouse now gates nothing at all in the night') but the sentence in CLAUDE.md was not changed.

### CLAUDE.md's documented control list is wrong on one entry, which is the same failure mode as finding 4 in reverse: a change the doc promises the suites will not notice, which they do notice.

**Proof:** CLAUDE.md:132-134 lists 'renaming a room kind' as a verified-silent control. M9 (Config.luau: id="library", name="Library" -> name="Reading Room") was KILLED: 'Manor FAIL: kindById finds a kind -> got Reading Room want Library' (591 passed, 1 failed). The other listed controls do hold — M21 rename a relic tier SURVIVED, M22 rewrite an upgrade blurb SURVIVED.

### Not a defect, recorded because the brief asked whether the retune made the game trivial: it did not, but the early game is close to free and the balance now depends on layouts that are globally identical for every player.

**Proof:** Greedy full clear (take every relic, then leave), walked legally at 20 studs/s: night 1 costs 14.0s of a 210s night (6.7%), night 5 14.0s of 198 (7.1%), night 12 20.0s of 177 (11.3%); it climbs to 47.3% by night 100 and peaks at 65.5% on night 44 over the full 1-500 sweep. Since Manor.seedFor folds only WorldSeed and the night, one published route for night 1 is correct for everybody in the world. Against that: a player who ignores the watcher is still caught on 39/60 nights, so it is a real constraint, not decoration.

