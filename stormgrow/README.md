# StormGrow: Mutation Farm

A Roblox farming game where the weather is the whole point. Built 2026-10-01 from `DESIGN.md`, test-first, to
`docs/complete-game-standard.md`. **Not published, never opened in Studio, never played by a person.** Every
number below was measured headless (luau CLI and `robloxemu`); nothing here has been rendered.

## What it is

Six farms around a market square, one per player. Tap an empty tile to plant the selected seed (Radish is free,
so nobody gets stuck). Crops grow on real time, also while you are offline. One tap on a ripe crop harvests it,
sells it on the spot and replants.

Over everything runs one **weather clock tied to the real clock, the same in every server**: a storm at every
:x0 (90 s), frost at every :x5 (90 s), and a rainbow right after the :00 and :30 storms (60 s). **Only ripe
crops catch the weather**: every 5 s of an event, each ripe crop may take that event's mark (Charged x5, Frosted
x5, Prismatic x8; published odds 1 in 2, 1 in 2, 1 in 2.9 over a whole event). Marks multiply, up to the Tempest
(x200). So the choice every minute is to harvest now or leave ripe crops in the ground for the event the forecast
promises. Coins unlock 8 crops (in order) and 6 fields. Lifetime harvest moves your sky through 7 bands, from
Sunny Meadow to the Eye of the Storm (the brag, about 37 minutes in) and Starfall Summit (about 2 hours). Every
crop-and-mark combination found for the first time fills one of 56 Almanac entries, and the Almanac is what the
public and friends leaderboard ranks: on a board at the market square and on a board on your own porch, 15 studs
from where you spawn (a prompt on either switches Friends / Everyone).

Nothing costs Robux. No gamepasses, no codes, no gambling: the only randomness is free weather with published odds.

## Measured (see `CLAUDE.md` for every gate)

| what | number | where |
|---|---|---|
| normal player reaches the brag (Eye of the Storm) | 36.6 min median (p10 33.4, p90 39.2) | `tests/Pacing.spec.luau`, 200 sessions on the real modules |
| the same, played through the real server and clients with every tap made on the screen (REVIEW-1) | 33.0-39.3 min over 8 boot phases (median 36.8); 1,651 screen clicks, every one answered by the tile aimed at | long walks: `tests/walk.luau`'s player, played to the brag |
| fast / slow player | 36.1 / 39.5 min | same |
| player who ignores the forecast | 45.8 min (the core mechanic pays: 25 % slower without it) | same |
| band 7 (Starfall Summit) | 120.8 min | same |
| all 56 Almanac entries (a player who follows the "N to find" hint) | 4.3 h median | same, 20 sessions of 8 h |
| first tap to first Radish, a brand-new player | 0.8 s after joining | `robloxemu/check_stormgrow_firstmin.luau` |
| the walk: a normal player, real odds, real clock, through the real server and clients, every tap a click on the screen (60 runs, one per minute of boot phase over the hour, REVIEW-1) | median Carrot 0.8 min, Corn 4.7, field 2 7.4, Tomato 10.2 (the pacing model says 0.9 / 4.4 / 7.2 / 9.8); every planted crop ripe after 5 min offline in 60 of 60; 7,503 clicks, all answered by the tile aimed at; 303 hazard rings stepped out of, 0 hits | `tests/walk.luau` |
| hazards in play | one per 150 s for a player who keeps moving (20 min measured), ring drawn exactly as the hit zone | `check_stormgrow_hazards.luau` |
| hazards on a normal farmer's path (stands still between sweeps; idle rest after 90 s) | 10-14 per session, one per 159-213 s (median 173 s); 3.8-14.6 % of frames in rest; the ring drawn on the porch, pad or soil the farmer stands on | the 8 long walks above (REVIEW-1 B2); `check_stormgrow_hazards.luau` part G |
| taps land on the tile under the thumb | 1,599 of 1,599 aimed taps, 6 fields x 6 camera poses, an 800 x 360 phone; no tap on your own farm is silent; from the spawn camera nothing hides field 1 at pitches 10-45 | `check_stormgrow_aim.luau` |

## Layout

Rojo (`default.project.json`): `src/server` -> ServerScriptService, `src/client` -> StarterPlayerScripts,
`src/shared` -> ReplicatedStorage. Pure, CLI-tested modules in `src/shared`; the authoritative server in
`src/server/Main.server.luau`; three display-only client scripts (`Hud`, `Farm`, `Sky`). Tests in `tests/`,
headless checks in `robloxemu/check_stormgrow*.luau`. Design: `DESIGN.md`. Eye candy: `EYECANDY.md`.
Clips: `MARKETING.md`. How to work on it: `CLAUDE.md`.

## Store text (997 characters, plain ASCII, measured)

```
The weather here runs on the real clock, and it is the same in every server. A storm breaks every ten minutes, starting on the hour. Frost comes five minutes after each storm breaks, and at :00 and :30 a rainbow follows the storm.

Only ripe crops catch it. Lightning makes a crop Charged, worth x5. Frost makes it Frosted, also x5, and the rainbow makes it Prismatic, x8. Leave a Charged pumpkin in the ground until the frost and it can become Stormglass, x25. A crop that catches all three is a Tempest, x200, and the whole server hears about it.

So you plan: plant so your crops are ripe when the storm hits, watch the bolts land, then harvest. The forecast is always at the top of the screen.

Eight crops, six fields and an Almanac of 56 mutations to find. The sky over your farm changes as the farm grows, from a sunny meadow to the eye of the storm. Crops keep growing while you are away. The leaderboard counts Almanac discoveries, for everyone and for your friends.

Nothing costs Robux.
```

Every claim in it was checked against the code on 2026-10-01: the schedule (`Config.Weather`, `tests/Weather.spec`),
the multipliers (`Config.Marks`, `tests/Mutation.spec`), the server-wide Tempest toast (`Main.server.luau`
strike loop), offline growth (`tests/walk.luau`: 18 of 18 crops ripe on return), the 8 crops, 6 fields and 56
entries (`Config`, `tests/Farm.spec`, `tests/Mutation.spec`), the board (`check_stormgrow_board.luau`).
