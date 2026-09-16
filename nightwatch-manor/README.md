# Nightwatch Manor — Haunted Escape Tycoon

A horror-tycoon for Roblox. Survive a procedurally laid-out haunted manor, loot its relics, then
spend them on a safehouse that makes the next night survivable.

Built from concept #2 in `docs/game-radar/2026-09-09-roblox-game-radar.md`. It is the seasonal
one: horror carries a documented 3x CCU multiplier in the September–October window, and
horror-tycoon is a sub-genre two independent scouts flagged as having almost no competition yet.

Sibling of `labyrint-spill/`, `plus1-jump/`, `grow-a-crystal/` and `anomaly-observatory/`, and it
uses the same stack: one CONFIG table, deterministic `Rng`, pure logic in `src/shared` tested from
the luau CLI with no Roblox present, and a DataStore layer with a soft session lock.

## The loop

**NIGHT.** The server builds a manor from a modular room kit — foyer, portrait hall, library,
dining room, nursery, cellar, chapel, servants' exit — laid out on a grid by a seeded generator.
Relics stand on pedestals, weighted toward the deep rooms. One Nightwatcher walks a patrol route
through the doorways. It sees you inside a view cone, and only in its own room or one directly
linked to it, so walls actually hide you. Once it has seen you it comes at you along the shortest
room path until its hunt timer runs out. Take relics, reach the Servants' Exit before DREAD fills.

**You are faster than it, always.** `Watcher.speed` is capped at a fraction of
`Config.Player.WalkSpeed` — 12.5 studs/s at its worst against your 20 — so turning and running
gains you ground, and the manor is generated with circuits in it rather than as a tree of dead
ends, so running has somewhere to go. That is the whole counterplay: the Nightwatcher costs you
route and dread, not the run. It catches people who freeze, who corner themselves, or who walk
into it. The real timer is DREAD.

**DAY.** Back in your own safehouse, every upgrade is a pad on the floor with a prompt on it.
Buying a level costs relics, stacks a visible piece of hardware on the pad, and changes a number
the next night reads: how far your lantern lights, how fast the manor wakes, how fast the
Nightwatcher walks, how early the alarm bell warns you, what a relic banks for, how much you keep
when it catches you, how long you get. The manor does **not** grow with your hub level — see
Determinism.

Getting caught, or running out of night, costs you the haul you were carrying — never the night
you are on and never the safehouse. The tycoon progress is the thing you are allowed to keep.

**Determinism.** A manor is generated from `WorldSeed` and the night number and nothing else —
not your userId, and not your hub level. Night 7 is the same manor for every player in the world,
which is what makes "I got out of night 14" a claim worth comparing.

This claim used to be false. The SEED was only `WorldSeed + night`, but `Manor.roomCount` folded
in the player's hub level, so the room target, the exit, the relics and the patrol all moved with
how much safehouse you had built: night 7 was a 9-room manor for a new player and a 13-room one
at hub level 12. Worse, `Upgrades.hubLevel` sums EVERY upgrade level and the exit is always the
deepest room, so every purchase in the game quietly lengthened your walk out, with nothing on
screen to say so. The hub level no longer reaches the generator at all — `Manor.plan` does not
take it — and `Manor.spec` asserts that passing it changes nothing.

## Layout

```
default.project.json        rojo: src/server -> ServerScriptService
                                  src/client -> StarterPlayerScripts
                                  src/shared -> ReplicatedStorage
src/shared/Config.luau      every tunable, one table
src/shared/Manor.luau       the seeded layout generator + room-graph queries   (pure)
src/shared/Watcher.luau     patrol movement, sight cone, hunt state, dread     (pure)
src/shared/Upgrades.luau    costs, levels, aggregated effects                  (pure)
src/shared/Night.luau       how a night ends and what it pays                  (pure)
src/shared/Rng.luau         deterministic LCG (copied verbatim from siblings)
src/shared/Fx.luau          lighting/particle kit          (copied verbatim)
src/shared/FxClient.luau    camera + HUD juice             (copied verbatim)
src/shared/Responsive.luau  phone-first layout maths       (copied verbatim)
src/server/Main.server.luau authoritative: builds the world, runs the night, persists
src/client/Hud.client.luau  display only — it sends the server nothing
tests/*.spec.luau           one spec per pure module, plus Chase.spec (is it PLAYABLE)
```

Every module in `src/shared` takes its dependencies **as arguments** and requires nothing. A bare
`require("./Rng")` resolves in the luau CLI and is invalid in Roblox, and that exact mistake once
made a sibling game's server fail to load while all 119 of its unit tests stayed green. Only the
server and client scripts require, and they do it from `ReplicatedStorage` with an Instance.

## Running the tests

From this directory, with the luau CLI on hand:

```
luau tests/Manor.spec.luau        # 86 passed, 0 failed
luau tests/Watcher.spec.luau      # 87 passed, 0 failed
luau tests/Upgrades.spec.luau     # 99 passed, 0 failed
luau tests/Night.spec.luau        # 64 passed, 0 failed
luau tests/Rng.spec.luau          # 32 passed, 0 failed
luau tests/responsive.spec.luau   # 70 passed, 0 failed
luau tests/Chase.spec.luau        # 32 passed, 0 failed
```

`Chase.spec` reports the smallest number and covers the most ground: one assertion sweeping nights
1-500 replaced sixty that each swept a single night. Read the printed measurements, not the count.

`Chase.spec.luau` is the odd one out and the important one. Every other spec asserts STRUCTURE,
and structure was never the problem: an adversarial review retuned `HuntSpeedMul` from 1.45 to
5.0 — a Nightwatcher sprinting at 55-100 studs/s at a player fixed at 16, an unavoidable death
every night — and all 390 assertions plus all 84 headless ones stayed green, because nothing in
the repo knew how fast the player was. So this file asserts OUTCOMES instead: that the watcher can
never be faster than the player at any dread, with any upgrades, under a deliberately hostile
retune; that there is a corner of the next room it cannot see; that a player ambushed in its face
and running is not caught on any of nights 1-20; that a player who IGNORES the watcher loses the
haul on a third of nights or more, so the retune did not turn the hunter into furniture; and that
crossing the manor never eats more than 40% of the night.

Its simulated player has a BODY and cannot walk through walls. The first version moved point to
point with no collision at all -- from a room corner straight to the next room's centre, which
crosses the wall rather than the ten-stud doorway `buildWall` leaves -- and the headline "never
caught on 40 of 40 nights" turned out to be a property of the bot: re-run with collision it was
caught on 5 of 40, and on 19 of 40 once the bot was two studs wide like a real character. The wall
model here mirrors `buildWall` exactly, the player is a capsule, and it slides along a wall the way
a Roblox character does. There is a CONTROL on the collision model itself, because a `blocked()`
that always answered "walkable" would silently restore the old bot and turn every assertion below
it green again on a game nobody could play.

Syntax and types:

```
luau-compile --binary src/**/*.luau
luau-analyze src/**/*.luau 2>&1     # clean after filtering Roblox global/type noise
```

## Booting it headless

Unit tests cannot see the workspace. Grow a Crystal shipped with sockets that were never
parented — the whole core loop was unreachable in a published game and 166 tests stayed green —
so this game is also booted for real, outside Roblox:

```
cd ../robloxemu
py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
luau check_nightwatch.luau        # 113 passed, 0 failed
luau check_nightwatch_hud.luau    # PASS — fits every viewport checked
```

...and three more that belong to this game and live in `tests/`, because `robloxemu/` is shared and
is not ours to edit:

```
cd tests
py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
luau check_walk.luau                       # 62 passed, 0 failed
luau check_world.luau                      # 38 passed, 0 failed
luau check_boot_guard.luau -a control      # 2 passed  (it boots)
luau check_boot_guard.luau -a fraction     # 4 passed  (it refuses)
luau check_boot_guard.luau -a walkspeed    # 4 passed  (it refuses)
luau check_boot_guard.luau -a saturated    # 4 passed  (it boots, and warns)
```

`check_walk.luau` is the one that matters. It does not read the plan -- the plan is what the server
INTENDED -- it reads the parts. It recovers the room graph from the `Floor` parts and from which
shared edges have no wall across them, builds a collision model out of every solid part at torso
height (walls, bookshelves, the dining table, the pedestals, the exit slab), routes over a two-stud
lattice, walks the character by hand at `WalkSpeed`, and presses a ProximityPrompt only from inside
its real `MaxActivationDistance`. Three nights: one relic and out, a full clear, and a chase in
which the Nightwatcher's own position is sampled every tick against the walls it is supposed to be
going around. Sealing every doorway, deleting the spawn placement, or growing the dining table to
fill its room all turn it red.

`check_boot_guard.luau` patches Config's SOURCE TEXT and asks whether the server refuses to start.
It is the only thing that can catch a boot guard whose condition has been quietly turned off, which
is a mutation that survived every other assertion in this repo.

`check_nightwatch.luau` boots the real server, joins a player and plays the game: it counts the
parts that actually arrived in the workspace, buys upgrades off their pads and checks the hardware
appears, presses a stranger's finger on your pad and checks nothing is spent, walks into the manor,
takes relics off pedestals, escapes, gets caught, and checks the zone index is recycled on leave.
It also holds the line on the join: that something solid and a `SpawnLocation` exist at the world
origin before anybody joins, that the character is moved into its own zone on the SAME frame it
appears, that `plr.RespawnLocation` points at a real `SpawnLocation` inside that zone, and — by
wrapping the harness's DataStore so `UpdateAsync` takes a second — that the whole zone is standing
WHILE the profile round-trip is still in flight, with spending refused until it lands.

`check_nightwatch_hud.luau` loads the real HUD across ten viewports from 414x800 to 1920x1080 and
measures every panel — with both phone drawers **opened** first, because a drawer parked shut
passes trivially and says nothing about where it opens.

## Not built yet

See `CLAUDE.md` for the full list. The short version: no environmental puzzles, no audio, no
jumpscare beyond a screen flash, and the upgrades are stat modifiers with visible props rather than
traps that physically fire.

## Paste-ready Roblox description

```
🏚️ NIGHTWATCH MANOR — Roblox Horror Tycoon 🔪
Survive a NEW haunted manor every single night, loot its cursed relics, then ESCAPE before it finds you! 😱

🕯️ Procedurally-generated haunted house — no two nights are ever the same
💰 Loot relics & cash from every run
🛡️ Spend your loot on YOUR safehouse — build traps, alarms, lights & defenses
👻 Outsmart the Nightwatcher's chase — hide, run, survive
🎃 New horrors & rooms added all Halloween season

Perfect for fans of Doors, Rooms, Piggy, and horror tycoons who love a good scare AND a good grind.

Can YOU survive the manor tonight… and build a safehouse strong enough for tomorrow?

👍 LIKE + ⭐ FAVORITE to help Nightwatch Manor grow — new updates weekly!
#horror #tycoon #haunted #roblox
```

Note before this copy is pasted anywhere: it says "relics **& cash**", and this build has one
currency, not two. Either drop that word or add the second currency before publishing — shipping a
description that promises something the code does not do is the exact habit this repo is trying to
break.
