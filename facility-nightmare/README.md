# FACILITY: Endless Nightmare

A Roblox roguelite about light running out. Ride a service elevator down into a research facility
that is generated from scratch for every sublevel. The power is failing: starting from the elevator
you arrived in, the rooms go dark one ring of doorways at a time, each flickering for two seconds
first. Find the fuses, carry them to the freight elevator, and choose: **EXTRACT** and bank what this
run earned, or **DESCEND** to a deeper sublevel that pays more and goes dark faster. If the dark takes
you, the run is over and you keep a quarter of it. Between runs, Essence buys permanent perks.

The full design, with the measurement behind every number, is [DESIGN.md](DESIGN.md). How to build,
test and change it is [CLAUDE.md](CLAUDE.md).

## What it honestly is today

- **Built and tested headless, never played by a person, never opened in Studio, not published.**
  No universe exists. Nothing here has been seen rendered: not the lighting, not the flashlight,
  not a room.
- **One player per zone on a shared server.** Other players share the break room. There is no
  co-op.
- **No monster.** The threat is the dark itself, spreading on a schedule derived from each
  generated floor. A silent black figure sometimes stands in a dark room you already walked
  through; it changes no rule and is gone when you look back.
- **No sound.** There is not one `Sound` in the game. It needs asset IDs this project does not have.
- **Seven environment bands, client-side only.** Every sublevel is a new layout of the same room shells,
  dressed by how deep it is: admin offices, laboratories (from sublevel 3), a server vault (5), flooded
  maintenance (7), the reactor core (9), an overgrown bio-lab (11) and the void (13). The dressing, colour
  grade and particles never make a room brighter than the server built it and never stand where an item can.
  A band's paint returns 60-100 % of the server's light and keeps every closed door as much darker than its
  wall as the server built it, so doors are no harder to find. A door between rooms of two bands wears the band of the
  side you see it from. Every self-lit piece and every particle goes dark with its room. Each band has its own
  weather (dust motes in the offices, fumes, sparks, drips, steam, spores, motes) and its own critter (a cockroach, a
  lab mouse, a moth, a rat, a bat, a beetle, a pale drifter), in about 7 of 10 rooms; a critter moves only while its
  room is lit and near you, never glows and never blocks you, and is held to the same rules over its whole path.
  [EYECANDY.md](EYECANDY.md) has the rules and the numbers.
- **A brag and a long-term goal.** The first time your record reaches the overgrown bio-lab (sublevel 11) or the void
  (13), the powered lift plays a fanfare. A headless bot at the medium speed proxy gets to the bio-lab after a median
  of 26.9-37.0 minutes (six samples of 30 players, EYECANDY.md §2); the void takes longer, and the slow proxy mostly
  does not reach the bio-lab (a median later than 150 minutes). One brag for everyone, timed for normal play, is the
  owner's decision (2026-09-30, EYECANDY.md §10).
- **Rare environmental hazards from the laboratories down**: a chemical leak, an arcing cable, a burst pipe, a
  steam valve, a spore pod, a rift. One every 90-140 s of lit time (the owner's decision, 2026-09-30); measured in
  real runs at the medium proxy, one per 3.3 minutes on a floor, and one per 2.6-3.1 in the bands that have them.
  Telegraphed 2.8-3.2 s with a red ring and a banner; a hit is a shove and nothing is lost. Never in a dark room
  (the dark stays the threat), never on arrival, and never at the powered lift while you choose. The ring is drawn
  where you stood, so a player who keeps walking is usually clear before it bursts: 1.4 % of bursts landed within
  8 studs of a bot that never stops (EYECANDY.md §3, §10).
- **A TOP DIVERS board, public and friends**, on the break room's north wall facing the spawn. It ranks the deepest
  sublevel whose freight elevator the server powered for you (behind the trusted position, so a script cannot put a
  number on it), ties to whoever got there first. Walk up and press E (or tap) to switch Public / Friends. Stored in an
  OrderedDataStore, written only when your record rises; names are looked up, never stored (docs/complete-game-standard.md §3).
- **Press pause: a REST button in the break room**, beside PERKS. It rests at once (a bench and 20 s of standing still
  do too); moving or pressing GET UP ends it. It exists only between runs: a run is a race against the dark, and a
  pause there would be the exploit (EYECANDY.md §4).
- **Nothing costs Robux.** No game passes, no developer products, no spin wheels, no paid revives.
- **Every survival number is a model number.** Battery, grace, the speed of the dark and the perk
  values were measured against a simulated explorer walking at 16 / 12.8 / 10.4 studs per second,
  not against people. The first Studio playtest (CLAUDE.md, "Needs Studio" item 1) replaces them.
- **The built game plays a little harder than that model.** A headless bot playing the real server
  (`tests/curve.luau`, 400 perk-less runs) powered sublevel 4 / 5 / 6 / 8 on 66% / 45% / 29% / 10%
  of runs at 10.4 studs per second, where the design's model explorer did 89% / 63% / 38% / 9%. The bot is not that explorer (it detours for every item it can see), so this checks the order
  of the numbers, not the numbers.

## The loop

1. Spawn in the break room. Walk 16 studs into the service elevator.
2. Ride down. Only the room you arrive in exists; doors open by themselves as you walk up to them,
   and the room behind a door is built as it opens.
3. Find 3 fuses (4 from sublevel 4, 5 from sublevel 9). Green battery cells add 15 seconds.
4. Stay in the light. In a dark room with your flashlight off, your exposure fills; after 4 seconds
   the dark takes you. The flashlight holds exposure steady but drains a battery that must last the
   whole run (45 seconds). Sprint for 4 seconds at 24 studs per second.
5. Walk the fuses into the freight elevator room. It powers up, pays `10 + 5 x (sublevel - 1)`
   Essence into the run, and asks: EXTRACT or DESCEND. A powered elevator never goes dark; an
   unpowered one is the last room to lose its light, one ring after the rest of the floor.
6. On your very first run, the dark waits until you pick up your first fuse.
7. Between runs, rest in the break room: press REST, sit on a bench, or just stand still. Nothing runs there. The
   DEPTH RECORD board shows how deep you have been, and the TOP DIVERS board how deep everyone else has (public or
   friends). Reaching the overgrown bio-lab is the brag; the void is the long-term goal.

Perks (Essence only): Deep Cell (+10 s battery per rank), Night Eyes (+1 s grace), Marathon (+1 s
sprint), Soul Anchor (+10% kept on death), Second Wind (once per run, the dark lets you go).
Everything costs 970 Essence in total.

Controls: **F** or the **LIGHT** button for the flashlight, hold **Shift** or tap **SPRINT** to
sprint (gamepad: **Y** and **L3**). At the powered elevator, **E** or the **EXTRACT** button, **Q** or
the **DESCEND** button. The perk terminal in the break room, or the **PERKS** button. **REST** beside it rests; **E** at
the TOP DIVERS board switches Public / Friends.

## Proposed store description

957 characters (at most 1000; counted with `py -3`), plain ASCII, no emoji. It promises nothing the game does not do today: the bands,
the hazards, the rest and the board are all in the built game (headless-tested, EYECANDY.md and CLAUDE.md), and the
bands are named only as far as the reactor, so the store does not spoil the bio-lab and the void.

```
FACILITY: Endless Nightmare

The power is failing, and it is failing toward you.

Ride the service elevator into a research facility that rebuilds itself every time you go down. Behind you, the lights die one ring of rooms at a time.

- Find the fuses and carry them to the freight elevator.
- Stay in the light. Your flashlight holds the dark off, but its battery has to last the whole run.
- EXTRACT to bank your Essence, or DESCEND: deeper pays more, and the dark comes faster.
- If the dark takes you, you keep a quarter of the run. Essence buys permanent perks.
- The deeper you go, the stranger it gets: offices, labs, a server vault, flooded maintenance, the reactor, and further down.
- Rare hazards give fair warning: step out of the red ring.
- Rest on a bench in the break room between runs.
- Compare your deepest dive on the Top Divers board, public or friends.

No monster chases you. There is only the dark.

Nothing in this game costs Robux.
```

Before publishing, check it against DESIGN.md §17: no "stalker", no "co-op", no "added weekly".

## Layout

```
default.project.json   Rojo: src/server -> ServerScriptService, src/client -> StarterPlayerScripts,
                       src/shared -> ReplicatedStorage; StreamingEnabled false, RespawnTime 3,
                       EnableMouseLockOption false
src/shared/            Config, Facility, Survival, Trust, Economy (pure, tested), Rng, MazeGen,
                       Responsive (verbatim copies), Fx (+ the Facility preset), FxClient;
                       the environment: EnvBands (verbatim from plus1-jump), Hazards, Rest (adapted),
                       Dressing (pure, tested), EnvBus, EnvArt (client art)
src/server/Main.server.luau
src/client/Hud.client.luau
src/client/Env.client.luau   the environment: bands, dressing, hazards, rest (EYECANDY.md)
src/client/Board.client.luau the TOP DIVERS board, as this player sees it (public or friends)
src/shared/Board.luau  the board's pure rules (verbatim from plus1-jump: encode, ties, caches, the read limiter)
tests/*.spec.luau      one spec per shared module
tests/Bot.luau         a headless player that knows only what a client could know
tests/walk.luau        join -> three sublevels -> extract -> perk -> a second run -> leave and rejoin, in numbers
tests/curve.luau       a measurement: the built game's difficulty curve, played by the bot
tests/hazards.measure.luau  a measurement: how often hazards come in real runs, through Env.client
tests/pacing.measure.luau   a measurement: minutes from join to the brag and the long-term goal, per speed proxy
../robloxemu/check_facilitynightmare*.luau
                       the headless gates: world and rules; the HUD on 10 viewports; every
                       button and key pressed through the real HUD on a phone; a mouse-and-
                       keyboard player; the environment (_env), its hazards (_hazards), every
                       new room dressed on its first frame at 60 Hz (_firstframe), the TOP DIVERS board
                       (_board) and the board with its store down (_boardoff)
REVIEW-1.md            two adversarial reviews' findings and how each was closed
EYECANDY.md            the environment bands, hazards, rest, budgets, gates, the needs-Studio list and the thumbnail shot list
MARKETING.md           eight vertical clips for tools/film_game.py, each with its staging
design-measure/        the measurement rig DESIGN.md's numbers came from (not game code)
```
