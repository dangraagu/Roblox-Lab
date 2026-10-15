# Disaster Rounds - survive the round

Every 88 seconds the server builds a new island and drops everyone who is not on a break onto it. Four seconds later
it names the disaster: a meteor shower, a flood, a tornado or an earthquake, a fresh draw every round. For
60 seconds you survive it. **Every danger is drawn in red first, and the red is exactly where it hits.** One hit
sends you back to the Lookout until the next round. Survive rounds in a row and your Heat rises, which aims more of
the danger at you. Your sky changes with every few disasters you live through, until it falls (about 35 minutes in).

Built 2026-10-07 from `DESIGN.md` (Game-Radar 2026-09-23 #5 and 2026-09-04 #5). Sibling of `plus1-jump/` and
`deep-vein/`, same stack: one `Config`, pure rules in `src/shared` tested from the CLI, a server that owns every
decision, a phone-first HUD. **Not published, never opened in Studio, never played by a person.** How to run the
gates and what this game's traps are: `CLAUDE.md`. The look, the needs-Studio list and the thumbnail shots:
`EYECANDY.md`. The clip list: `MARKETING.md`.

---

## Store description

Checked against the build on 2026-10-07 (after REVIEW-1): **990 characters** (the dashboard allows 1000), plain ASCII,
no emoji.
Every sentence is something the game does; "Up to 8 players" needs `MaxPlayers = 8` set at publish (it is not a
project-file property, `EYECANDY.md` needs-Studio #20).

```
Every round the island is new and the disaster is a fresh draw: a meteor shower, a flood, a tornado or an earthquake. Be standing when the minute is up and you survived.

One rule covers them all: red shows exactly where it hits. Step out of the red ring before the meteor lands. Get above the red line before the water does. Stay off the red path and the tornado misses you. Get off the red cracked ground before it falls.

Survive rounds in a row and your Heat goes up: more of the danger is aimed at you, and everyone can see your flame. One hit and you are out until the next round.

The more disasters you survive, the more your sky changes, from a calm cove to a sky that is falling, and later a new dawn. The leaderboard ranks the longest streaks, up to 25 in a row, for everyone and for your friends. The Codex keeps the hottest Heat you have survived for each disaster.

Up to 8 players. Need a break? Sit down on the Lookout and the rounds go on without you.

Nothing costs Robux.
```

---

## The loop

| phase | seconds | where | what happens |
|---|---|---|---|
| intermission | 20 | the Lookout, a cliff-top deck west of the island | the result card, the board, the countdown; tap ☕ to sit the next rounds out |
| drop | 4 | the island | everyone not on a break lands on their own cell, at least 2 cells apart; the island was built out of sight (`ServerStorage`) and appears only now |
| disaster | 60 | the island | named with an icon and a six-word rule; every threat is drawn in red first |
| outro | 4 | the island | SURVIVED with confetti, then everyone back to the deck |

The four disasters, each with its red rule:

* **☄️ Meteor Shower - "Step out of the red rings."** Rings 9 studs across, 3.0 s before impact, aimed at where you stand.
* **🌊 Flood - "Get above the red line."** Three rises (to y = 2, 6, 10). A red line at the coming height and every cell
  that will flood tinted red, 9 s before each rise. Levels 3-4 always stay dry, and every map has at least 18 of them.
* **🌪️ Tornado - "Stay off the red path."** The funnel (13 studs wide, 9 studs/s; you walk 16) and the ground it will
  cover in the next 4 s, drawn red, nothing further.
* **🏚️ Earthquake - "Get off the red ground."** Every 6 s up to 10 cells crack red and drop 3.0 s later; every red
  cell has a safe neighbour one step away.

Every disaster also aims rings at each player (meteors, lightning, flying debris, boulders): one every 6.0 s at Heat
0 down to 2.5 s at Heat 5 in a Meteor Shower, 15 s down to 5 s in the others. Heat = min(5, floor(streak / 2)).

* **One hit** sends you to the Lookout. Your streak goes to 0; your survivals, your best streak and your Codex never go
  down. Leaving or resetting during a round counts as being swept out; the round ends when the disaster does, so the
  4 s outro after SURVIVED is safe to leave (REVIEW-1 F1).
* **Survive** and your streak, survivals and Codex row for that disaster go up.
* **Joined mid-round?** Tap **▶ Jump in (practice)** until 10 s before the end. A practice round counts for nothing.
* **☕ Rest** on the Lookout: you sit, you are not dropped, nothing is earned. Pressed on the island, it waits for the
  round to end. Two and a half minutes without input puts you on a break by itself.

## What you work toward

| goal | when (pacing model, `tests/Pacing.spec.luau`, normal player median) |
|---|---|
| band 2, Windy Point (2 survivals) | 3.4 min |
| band 3, Storm Coast (6) | 9.8 min |
| band 4, Ember Isles (12) | 19.9 min |
| **band 5, Falling Sky (21): the brag, "☄️ THE SKY IS FALLING"** | **35.1 min** (p10 32.7, p90 38.3; fast 32.7, slow 41.9) |
| 🔥 MAX HEAT, the first streak of 10 | 28.4 min (fast 15.4, slow 98.8) |
| the Codex, 4 disasters x Heat 0-5 | 1.9 h |
| band 6, New Dawn (100) | 168.1 min |
| the board: your **best streak, up to 25** | normal 12 at 1 h, 16 at 4 h; fast 21 and 33. A fast player's best reaches 25 in 43 % of one-hour sittings, a normal player's in 2 % |

These are model numbers (reaction times and lapses written down in `Config.Pacing.Profiles`), not telemetry. Re-measured
after REVIEW-1 made the next disaster an even draw (the same one can come again).

## The board

"Longest Streaks", 12 x 8 studs at the north end of the deck, with a ProximityPrompt that switches Public / Friends.
OrderedDataStore `DisasterRounds_Streak_v1`, key `u_<userId>`, value `best * 2e9 + (2e9 - reachedAt)`, so ties go to
whoever got there first. Written only when a saved best streak rises, only by the session that holds the save lock.
Only the server's own end-of-round check can raise a streak, at most once per 88 s round. **The board counts a streak
up to 25** (`Config.Board.StreakCap`, REVIEW-1 F5): a script that reads the replicated red never misses, so without a
cap it would top the board in about 25 minutes and keep climbing; 25 is a run a fast human makes. Past 25 the time
that ranks a tie is when 25 was first reached. Your own streak, Heat and Codex go on past it.

## Layout

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts,
                       src/shared -> ReplicatedStorage; Workspace.StreamingEnabled = false
src/server/Main.server.luau   the authoritative glue: the Lookout, the round clock, islands, disasters, hits,
                              saves, the board
src/client/Hud.client.luau    the phone-first HUD (display only)
src/client/World.client.luau  the disasters' show: ring pulses, projectiles, tints, the path ribbon, chunks,
                              Heat flames, confetti
src/client/Sky.client.luau    the bands, the disaster overlay, scenery, critters, weather, Lookout strays, rest
src/client/Board.client.luau  draws this player's view of the board
src/shared/   Config; pure rules: MapGen Round Zones Strikes Flood Tornado Quake Guard Progress;
              templates copied verbatim from plus1-jump: EnvBands Hazards Rest Board Responsive Rng FxClient,
              Fx (+ one preset, Coast); art: SkyArt
tests/        17 specs, RoundModel.luau (the pacing model on the real modules), walk.luau (the player's path)
design/       the design-time Python model (retired by tests/Pacing.spec.luau, kept for the record)
```

No Robux, no currency, no gamepasses, no codes, no gambling in v1 (`DESIGN.md` §16).
