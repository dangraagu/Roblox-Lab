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
  wall as the server built it, so doors are no harder to find. Every self-lit piece and every particle goes
  dark with its room. [EYECANDY.md](EYECANDY.md) has the rules and the numbers.
- **Rare environmental hazards from the laboratories down**: a chemical leak, an arcing cable, a burst pipe, a
  steam valve, a spore pod, a rift. One every 2-3 minutes of lit time at most; measured in real runs, about
  one per 4-5 minutes on a floor (one per 3.3-4 in the bands that have them). Telegraphed 2.8-3.2 s with a
  red ring and a banner; a hit is a shove and nothing is lost. Never in a dark room: the dark stays the
  threat. The ring is drawn where you stood, so a player who keeps walking is usually clear before it bursts
  (about 1 % of bursts landed within 8 studs of a bot that never stops); how often a hazard should be a
  near-miss is the owner's call (EYECANDY.md §10).
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
7. Between runs, rest in the break room: sit on a bench, or just stand still. Nothing runs there, and the
   DEPTH RECORD board shows how deep you have been.

Perks (Essence only): Deep Cell (+10 s battery per rank), Night Eyes (+1 s grace), Marathon (+1 s
sprint), Soul Anchor (+10% kept on death), Second Wind (once per run, the dark lets you go).
Everything costs 970 Essence in total.

Controls: **F** or the **LIGHT** button for the flashlight, hold **Shift** or tap **SPRINT** to
sprint (gamepad: **Y** and **L3**). At the powered elevator, **E** or the **EXTRACT** button, **Q** or
the **DESCEND** button. The perk terminal in the break room, or the **PERKS** button.

## Proposed store description

Under 1000 characters, no emoji. It promises nothing the game does not do today.

```
FACILITY: Endless Nightmare

The power is failing, and it is failing toward you.

Ride the service elevator into a research facility that rebuilds itself every time you go down. Rooms open as you reach them. Behind you, the lights die one ring of rooms at a time.

- Find the fuses and carry them to the freight elevator.
- Stay in the light. Your flashlight holds the dark off, but its battery has to last the whole run.
- EXTRACT to bank your Essence, or DESCEND: the next sublevel pays more, and the dark comes faster.
- If the dark takes you, the run is over and you keep a quarter of what you earned.
- Spend Essence on permanent perks: a bigger battery, a longer grace in the dark, more sprint, a second wind.

Procedurally generated permadeath runs. You play your own facility; other players share the break room. No monster chases you and nothing jumps out at you. There is only the dark.

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
tests/*.spec.luau      one spec per shared module
tests/Bot.luau         a headless player that knows only what a client could know
tests/walk.luau        join -> three sublevels -> extract -> perk -> a second run, in numbers
tests/curve.luau       a measurement: the built game's difficulty curve, played by the bot
tests/hazards.measure.luau  a measurement: how often hazards come in real runs, through Env.client
../robloxemu/check_facilitynightmare*.luau
                       the headless gates: world and rules; the HUD on 10 viewports; every
                       button and key pressed through the real HUD on a phone; a mouse-and-
                       keyboard player; the environment (_env), its hazards (_hazards), and every
                       new room dressed on its first frame at 60 Hz (_firstframe)
REVIEW-1.md            two adversarial reviews' findings and how each was closed
EYECANDY.md            the environment bands, hazards, rest, budgets, gates and the thumbnail shot list
design-measure/        the measurement rig DESIGN.md's numbers came from (not game code)
```
