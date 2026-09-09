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

**DAY.** Back in your own safehouse, every upgrade is a pad on the floor with a prompt on it.
Buying a level costs relics, stacks a visible piece of hardware on the pad, and changes a number
the next night reads: how far your lantern lights, how fast the manor wakes, how fast the
Nightwatcher walks, how early the alarm bell warns you, what a relic banks for, how much you keep
when it catches you, how long you get. The manor also grows with your hub level, so a stronger
safehouse buys a bigger, richer, longer night.

Getting caught, or running out of night, costs you the haul you were carrying — never the night
you are on and never the safehouse. The tycoon progress is the thing you are allowed to keep.

**Determinism.** A manor is seeded from `WorldSeed` and the night number and nothing else — not
your userId. Night 7 is the same manor for every player in the world, which is what makes "I got
out of night 14" a claim worth comparing.

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
tests/*.spec.luau           one spec per pure module
```

Every module in `src/shared` takes its dependencies **as arguments** and requires nothing. A bare
`require("./Rng")` resolves in the luau CLI and is invalid in Roblox, and that exact mistake once
made a sibling game's server fail to load while all 119 of its unit tests stayed green. Only the
server and client scripts require, and they do it from `ReplicatedStorage` with an Instance.

## Running the tests

From this directory, with the luau CLI on hand:

```
luau tests/Manor.spec.luau        # 61 passed, 0 failed
luau tests/Watcher.spec.luau      # 71 passed, 0 failed
luau tests/Upgrades.spec.luau     # 92 passed, 0 failed
luau tests/Night.spec.luau        # 64 passed, 0 failed
luau tests/Rng.spec.luau          # 32 passed, 0 failed
luau tests/responsive.spec.luau   # 70 passed, 0 failed
```

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
luau check_nightwatch.luau        # 84 passed, 0 failed
luau check_nightwatch_hud.luau    # PASS — fits every viewport checked
```

`check_nightwatch.luau` boots the real server, joins a player and plays the game: it counts the
parts that actually arrived in the workspace, buys upgrades off their pads and checks the hardware
appears, presses a stranger's finger on your pad and checks nothing is spent, walks into the manor,
takes relics off pedestals, escapes, gets caught, and checks the zone index is recycled on leave.

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
