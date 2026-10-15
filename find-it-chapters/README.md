# Find It! Chapters

A Roblox hidden-object game in chapters. You step into a cluttered room with a list of 3-9 small things to find.
Each thing hides in a prop that fits its clue, for example "a BLUE BOX" or "something YELLOW up HIGH", and 3-5
props fit every clue. Tap a prop to look at it, tap again to search it; a search takes a second and costs one
look out of n x k + 2. Find the whole list before the clock and the looks run out. Fifteen chapters in five
themed rooms make Book One; after chapter 3 a Daily Case opens every UTC day, and the board ranks Cases Solved
(chapters cleared plus Daily Cases, at most one a day).

**Status (2026-10-08):** v1 built test-first from `DESIGN.md` to `docs/complete-game-standard.md`, then two
adversarial review rounds (two reviewers each; `REVIEW-1.md` has round 2 in full: every finding reproduced, then
fixed with a failing test first and mutation-tested). All 33 headless gates are green (`CLAUDE.md` lists them with
their counts). **Never opened in Studio, never played by a person, not published, no universe, not committed.**
The needs-Studio list is `EYECANDY.md` §8.

Honest limits, stated: the pacing numbers (Book One solved at about 34 minutes for a "normal" player) come from
a model of human reading and noticing times (`tests/FinderModel.luau`), not from players. A player who sweeps
the room prop by prop gets there in about 21 minutes. The gates ran under `luaujs`, a Luau runtime written for
this session because the luau CLI was missing from the machine (`CLAUDE.md`, "The runtime").

## Layout

| path | what |
|---|---|
| `default.project.json` | Rojo: `src/server` -> ServerScriptService, `src/client` -> StarterPlayerScripts, `src/shared` -> ReplicatedStorage |
| `src/shared/` | pure modules: `Config`, `Clue`, `Dressing` (the room generator), `Attempt` (the attempt state machine), `Stars`, `Ledger` (profile, Daily credit), `Board`, `Bands`, `Pick`, `RoomArt`; templates `EnvBands`, `Hazards`, `Rest`, `Responsive`, `Rng`, `Fx`, `FxClient`, `ClientBus` |
| `src/server/Main.server.luau` | the authoritative server: hub, lanes, attempts, saving, the board |
| `src/client/` | `Hud.client` (phone-first HUD), `Room.client` (the room, taps, bands, hazards, pause), `Board.client` (friends face) |
| `tests/` | `*.spec.luau`, `FinderModel.luau` (pacing model), `walk.luau` (the player's path) |
| `design/` | the design-time Python model and its output (not game code) |

## Store description (897 characters, ASCII)

```
Find It! Chapters is a hidden-object game where no room is ever the same twice. Each chapter puts you in a cozy, cluttered room with a list: a teacup, a key, a rubber duck. Every item has a clue, like "a BLUE BOX" or "something YELLOW up HIGH". Look around, spot what fits, and tap to search it before the clock runs out. You only get so many looks, so read the clues!

- 15 chapters in Book One: a sunny cottage, an old library, a greenhouse at sunset, a ship's cabin in a storm and a star observatory
- Every attempt rearranges the room and hides everything somewhere new
- Up to 3 stars per chapter: Found, Swift and Sharp Eye
- A new Daily Case every day at 00:00 UTC
- Falling books and tumbling crates: step out of the red ring!
- Take a break: the clock stops, and things get moved while you rest
- Public and friends boards for Cases Solved
- Nothing to buy. No gamepasses, no paid boosts.
```

Every claim in it is built: the room is re-dressed and re-hidden on every attempt (`Dressing`, `Attempt.hide`),
the stars are `Stars`/`Attempt.stars`, the Daily is `Ledger.dayIndex` (UTC), the hazards are the ceiling drops
(`check_finditchapters_hazards`), the pause stops the clock and re-dresses the room (`Attempt.resume`; a break
closes the room after 10 minutes), the ship's storm is rain running down its portholes and lightning flashing in
them, inside the room where it can be seen (`check_finditchapters_env`; whether it reads on a real screen is
`EYECANDY.md` §8), the boards are `check_finditchapters_board`, and nothing is sold (no MarketplaceService call
exists in `src/`).

## Running the gates

See `CLAUDE.md`. In short: rebuild the bundle (`cd ../robloxemu && py -3 wrap.py --game ../find-it-chapters --out
build/find-it-chapters.luau`), then run each `tests/*.spec.luau`, `tests/walk.luau` and each
`robloxemu/check_finditchapters*.luau`.
