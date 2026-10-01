# SIGNAL LOST: Derelict Station

A Roblox game in this repo (Roblox-Lab), built with Rojo. Built 2026-09-30/10-01 from `DESIGN.md`, test-first, to
`docs/complete-game-standard.md`. **Not published, no universe, never opened in Studio, never played by a person.**
Everything below was measured headless (`robloxemu`) or in the luau CLI; what only Studio can settle is listed in
`EYECANDY.md` §8.

## What it is

You are the engineer on a lifeboat docked to a dead space station. A LIFT drops you into **sector 1**, a small grid
of station modules generated a moment ago; only the module you stand in, and the ones whose hatches you have opened,
exist. **Air** modules have gravity and refill your suit; **breached** modules are open to space: 20 % gravity (you
drift), and your **AIR** drains one second per second. The lamp over every hatch says what is behind it, green AIR or
red VACUUM, so you plan a route from air pocket to air pocket. A five-bar **SIGNAL** meter, computed by the server,
leads to the sector's one **relay**, always in an air module far from the entrance. Salvage floats in the breached
modules. Reach the relay and it splices: carried salvage is banked plus a bonus, the sector's lights come on, and a
floor hatch drops you into a bigger, emptier sector. At 0 AIR you get five seconds, then you **black out**: you keep
half of what you carried and wake in a freshly generated sector. Salvage buys **AIR TANK** (20 to 40 s) and
**MAG-BOOTS** (12 to 16 studs/s in vacuum) at a fabricator. Relay 30 is the **Main Array**, the brag; sectors go on
without end after it. A public and friends board ranks **relays restored**.

There is no monster. The threats are the vacuum and, from sector 5 on, a rare drifting hazard (a water globe, a loose
crate, a slag blob, a panel shard, an ice chunk, a static orb) that is telegraphed and whose red ring is exactly where
it can hit; a hit is a shove that costs nothing. Rest is allowed wherever there is air. Nothing costs Robux.

**Controls.** Walk with the stick / WASD; jump (Roblox's own button) to drift in low gravity. Hatches open by
themselves as you walk up. **REST** (top edge) or **R** / gamepad **X** rests where there is air; the lifeboat's
benches are seats. **SHOP** (only at a fabricator: the lifeboat's, or a relay module's console after its splice) or
the fabricator's prompt (**E** in the lifeboat, **F** at a relay console, gamepad **Y**) opens the upgrade panel. **E**
/ gamepad **Y** at the RELAYS RESTORED board switches Public / Friends. The RETURN console in the dock (and the relay
console after a splice) rides back to the lifeboat (**E**, gamepad **B**). No prompt uses gamepad X, REST's button.

## Measured, not promised

- **First minute** (`tests/walk.luau`, three runs): spawn on `HubSpawn`, boarding the LIFT 1.6 s after spawning, the
  dock open at 4.6 s, relay 1 spliced 15.8 / 17.2 / 20.0 s later; the first upgrade bought 2.4-3.0 minutes after
  joining. The walk's player is a bot that never wastes a step, so these are floors.
- **The brag** (`tests/Pacing.spec.luau`, the real `Station` module, 200 campaigns per model player): relay 30 at
  p50 **36.9 min** for the medium proxy (p10 33.4, p90 41.1), 28.4 for the fast one and 49.2 for the slow one. The
  proxies are models, not people (DESIGN.md §0): they are perfectly careful, so real players will black out more.
- **Hazards** (`robloxemu/check_signallost_campaign.luau`, the real server and clients from join to relay 30): one
  warning per **2.32-3.08 minutes** of play from sector 5 on (median 2.54, 47 campaigns at three walking speeds), hub,
  rides and relay rooms included. Every warning ends in a finished flight: a player who walks on through the next
  hatch leaves the debris to fly through the empty ring behind them (REVIEW-1). The first comes in sector 5-11.

## Store description

997 characters (at most 1000; counted with `py -3`), plain ASCII, no emoji. It promises only what the built game
does: no Entity, no co-op, no weekly content (DESIGN.md §22 says why the radar's draft must not be used).

```
A dead space station has gone silent. You are the engineer sent to bring its signal back, one relay at a time.

Follow the signal through dark modules. Some still hold air. Some are open to space: gravity is almost gone, you drift, and your suit's air ticks down. The light over every hatch tells you what is behind it: green for air, red for vacuum. Plan a route between air pockets, grab salvage floating in the wreckage, and splice each sector's relay to bring its lights back.

Run out of air and you black out. You wake at the sector's entrance, and the sector rebuilds itself into a new layout. Spend salvage on a bigger air tank and mag-boots.

Restore 30 relays to reach the Main Array and send the signal home. Then find out what answered.

- A new station layout on every attempt
- No monster chases you: the danger is the vacuum (and some drifting debris)
- Rest wherever there is air
- Leaderboard of relays restored, public and friends
- Nothing costs Robux

Mild fear. No jumpscares.
```

## Layout

```
default.project.json   Rojo: src/server -> ServerScriptService, src/client -> StarterPlayerScripts,
                       src/shared -> ReplicatedStorage; StreamingEnabled false, RespawnTime 3, MaxPlayers 8
src/shared/            Config (every tunable), Station (the generator and module geometry), Air, Meter, Trust,
                       Economy, Board (pure, tested); Rng, MazeGen, Responsive, EnvBands, FxClient (verbatim
                       copies); Hazards, Rest (adapted from plus1-jump, EYECANDY.md §1); Fx (+ Presets.Station);
                       Dressing (pure, tested), EnvArt (client art), EnvBus (client message bus)
src/server/Main.server.luau   authoritative: lifeboat, zones, sectors, AIR, trust, splice, saves, the board
src/client/Hud.client.luau    the phone-first HUD (display only)
src/client/Env.client.luau    the environment: bands, exterior, dressing, weather, critters, hazards, rest
src/client/Move.client.luau   low gravity in vacuum modules (a VectorForce this client owns)
src/client/Board.client.luau  the RELAYS RESTORED board as this player sees it (public or friends)
tests/*.spec.luau      one spec per shared module, plus Pacing.spec (the brag's minutes) and EnvConfig.spec
tests/Bot.luau         a headless player that knows only what a client could know
tests/walk.luau        join -> loop 1 (sectors, a purchase, RETURN) -> leave -> rejoin -> loop 2, in numbers
tests/PacingModel.luau, tests/Streams.luau   the campaign model and the Rng adapter the specs use
../robloxemu/check_signallost*.luau   the headless gates (CLAUDE.md lists them)
DESIGN.md              the spec, every number tagged with where it came from
EYECANDY.md            bands, hazards, rest, budgets, the brag, gates, the needs-Studio list, the thumbnail shots
MARKETING.md           seven vertical clips for tools/film_game.py, each with its staging
CLAUDE.md              how to run every gate, and this game's traps
design-measure/        the measurement rig DESIGN.md's numbers came from (a design tool, not game code)
```
