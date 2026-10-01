# The Same Door

A daily dungeon speedrun for Roblox. Every UTC day the dungeon rearranges itself around the same old
Door, and every player on Roblox gets the identical layout. You walk through the hub arch into your own
copy of today's dungeon (9 x 9 halls of 16 studs), find the 3 Seals in any order and reach the Door. The
server times you from the start line to the Door, and your best time goes on today's public and friends
board. Then you run it again, faster. Tomorrow brings a new Door.

Status (2026-10-01): **v1 built and tested headless. Never run by a person, never opened in Studio, not
published, not committed.** `DESIGN.md` is the spec, `CLAUDE.md` has the gates and this game's traps,
`EYECANDY.md` the bands, hazards, rest, budgets, the needs-Studio list and the thumbnail shots,
`MARKETING.md` the clip list.

## Store description (980 characters, ASCII, no emoji; measured)

```
THE SAME DOOR - one dungeon, the same for everyone, new every day.

Every day at 00:00 UTC the dungeon rearranges itself around the same old Door. Every player on Roblox gets the exact same layout that day. Find the 3 Seals in any order, open the Door, and your time goes on today's board.

- The clock starts when you cross the line and stops at the Door. Run it as often as you like: your best time counts.
- Learn the halls, find the fastest order, cut the corners.
- Earn Bronze, Silver, Gold, and the Sealer medal for a run within 18% of the day's perfect line.
- The halls change as you carry more Seals: cellar, moss, crystal, embers, dawn.
- Watch the ceilings: a red ring shows exactly where the rock will land. Step out of it.
- Public and friends boards. A tie goes to whoever got there first.
- Keep your Door streak alive, day after day. Rest by the campfire between runs.

Nothing to buy. No pay-to-win. Just you, today's Door, and everyone else trying the same one.
```

## The loop

| step | what the player does | what the server does |
|---|---|---|
| join | lands on `HubSpawn`, facing the glowing arch 14 studs ahead; the hint says "Walk to the glowing arch and press E (tap ENTER)" | `RespawnLocation = HubSpawn` before the character loads; loads the profile under a session lock |
| arch | 4.5 studs of walking bring the prompt up (0.28 s, measured) | builds the lane shell, moves the character into the antechamber, sends the first cells |
| antechamber | reads the card: Door #, "Find 3 Seals, then open the Door", the medal times | nothing runs yet |
| the line | crosses it: the clock starts | starts its own clock at the interpolated crossing it saw |
| the halls | walls appear 2 cells ahead; seals turn the halls from Cold Cellar to Moss, Crystal and Ember | sends each cell once, when the player has walked within 2 steps of it; checks every sample (continuity, speed, height) |
| the Door | with 3 seals it opens: Dawn Sanctum, the finish card | the official time; the medal; one atomic profile write; the board write if it improved |
| Run again | same layout, fresh clock | a new run on the same day (or the new Door after midnight) |

Medals are graded against the day's perfect line P: the shortest line from the start line through the
three seals' pickup circles to the Door's, 2 studs off every corner, the same geometry the server's
whole-run check holds every run to (REVIEW-1). Silver <= 1.71 P, Gold <= 1.33 P, Sealer <= 1.18 P. The first
Sealer ever is the brag moment, "THE DOOR IS SEALED". The pacing model puts it at a median of **36.6
minutes** of cumulative play for a normal player (usually on day 2; `tests/Pacing.spec.luau`). Ranks: Wanderer, Gilded, Sealer, Warden (a
7-day Door streak), Keeper of the Same Door (30 Sealer days); your torch shows your rank.

## Why the layout cannot be computed early

There is no seed. The day is drawn from server randomness (two Roblox `Random`s XORed, read through
their high bits) once, on the day, and stored as a record of about 300 characters in
`SameDoor_Days_v2`. Every server reads the one stored copy. The generator lives in ServerScriptService,
the only copy outside server memory is `ServerStorage.SameDoor.Day`, and a client is sent a cell only
after the server has seen it walk within 2 open steps of it. `robloxemu/check_samedoor_secret.luau`
checks all of that, with a planted-leak control.

## Fair by construction

Nothing costs Robux. No gamepasses, no codes, no gambling, no pay-to-win. The board ranks a time the
server measured from its own samples of your character; no remote carries a time, a position, a seal or
a finish. The stated residual: a speed-up under 2 % on the published perfect line (about 0.5 s on a 26 s
run; the line is the server's own lower bound, so no walk can beat it), and a bot that simply plays
perfectly.

## Layout

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
src/server/  Main.server.luau (authoritative), Dungeon.luau (generator + record), RunCheck.luau (movement guard), RunState.luau (the run)
src/client/  Hud.client.luau (phone-first HUD, rest), Dungeon.client.luau (built cells, bands, hazards, budgets), Board.client.luau
src/shared/  Config, Day, Medals, Board, Ledger, Grid, Bands, DoorHazards, Pause, DungeonArt,
             EnvBands + Rest (verbatim from +1 Jump), Responsive, Fx, FxClient, Rng (verbatim from siblings)
tests/       *.spec.luau, RunnerModel.luau + Pacing.spec.luau (the brag-moment minutes), walk.luau
design/      the design-stage measurement kit (not game code; Rojo never maps it)
```

How to run everything: `CLAUDE.md`.
