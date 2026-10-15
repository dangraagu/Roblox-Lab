# Scrapline Tycoon

A production-line tycoon for up to 6 players, one plot each, on a ring around a junk-heap landmark. Junk pours out
of a chute onto a U-shaped conveyor belt and rides past six stations to a dock that sells whatever arrives: a
**Shredder**, **Furnace**, **Press**, **Cutter**, **Assembler** and **Rocket Bay** turn junk into scrap, ingots,
plates, gears, robots and rockets (worth 1, 2, 5, 12, 30, 75 and 200). A station handles only so many items a
second; what it cannot take rides past unchanged and sells for less, so the line is only as good as its slowest
station (the HUD marks it 🐢). You spend on that bottleneck: upgrade it, build its **twin** (doubles the station), or
save for the next station; the HUD's ★ points at the best choice. Every 150-210 s of line time one machine
**sputters**: walk over and hold Fix within 15 s, or it jams and items pass it unchanged until you fix it.

The yard changes with the highest product your line has shipped: Junkyard, Foundry, Press Works, Machine Shop,
Robot Works, Launch Site, each with its own light, scenery, critters and weather. Your first **Rocket** of a run
lifts off from your launch pad for the whole server (the brag moment). Once the line ships 1 500 rockets a second
(×1.35 more each time) you can **Recycle** for a **Gold Bolt**: +50 % value forever, a factory one grade shinier,
and a fresh run. Four bolts make the Golden Factory. The **Top Recyclers** board by your arrival pad ranks Gold
Bolts, for everyone or just your friends. Now and then the gantry crane drops something; a red ring shows exactly
where, and stepping out of it always dodges. **☕ Break** sits you down; nothing falls on you while you rest, but the
line keeps running and its machines can still jam (a break is not a pause of the factory). No PvP, nothing sold for
Robux, no offline income.

Measured (pacing model on the game's own rules, `tests/Pacing.spec.luau`, 20 seeds; the profiles are assumptions):
the first Rocket at **34.0 min** for a player who follows the ★ (fast 33.1, slow 36.0, three-in-four 36.5; one who taps any green button 36.8); the
first recycle at 43.6 min; the Golden Factory at 130.0 min. The scripted walker in `tests/walk.luau`, buying only
through the HUD on a phone-sized screen and standing still between taps, launched its first Rocket at 33.9-34.1 min
over 4 walks after REVIEW-1's round 2, and got a crane drop every 2.43-2.64 min; in its green mode (tapping any gold
or green button, not the ★) at 34.2-34.6 min.

**State (2026-10-08): v1 built test-first, then two rounds of adversarial review (22 findings) closed in
`REVIEW-1.md`; green in every gate (28: 4 799 assertions, 0 failed, HUD PASS). Never played by a person, never opened in Studio, not published, no universe, nothing committed.** The luau CLI was missing on this machine during the build:
every gate ran through a Luau-to-LuaJIT shim (see `CLAUDE.md`), so re-run them with the real luau CLI before
shipping. What only real rendering, input or a live server can settle is in `EYECANDY.md` §8. The spec is
`DESIGN.md`; gates and traps are in `CLAUDE.md`; clips are in `MARKETING.md`.

## Store description

For the experience page. **986 characters** by `len()` in Python (the dashboard allows 1000); no coloured-square
emoji (`docs/publishing.md`: 🟦 and 🟩 were rejected; 🏭 has not been tried against the endpoint yet, so if the write
is refused, bisect that line first). Every claim is one a gate asserts: the red ring is exactly the hit zone
(`check_scraplinetycoon_hazards` §6), nothing falls during a rest (§5) while the line keeps earning
(`check_scraplinetycoon_yard` ☕ Break; the jam clock does not stop, `Pacing.spec` "an untended line winds down"), the
board has a friends view (`check_scraplinetycoon_board`), nothing is for sale (no MarketplaceService call exists).

```
🏭 Junk goes in. Rockets come out.

Build a production line on a conveyor belt: a Shredder, a Furnace, a Press, a Cutter, an Assembler and a Rocket Bay. Each machine turns what reaches it into something worth more: junk, scrap, ingots, plates, gears, robots, rockets.

Find your slowest machine and fix it: upgrade it, or build its twin. A sputtering machine needs a quick fix before it jams.

Your factory changes as it grows, from a dusty junkyard to a foundry, a machine shop, a neon robot works and a launch site under the stars. Now and then the crane drops something. A red ring shows exactly where it lands: step out of the ring and it misses.

Need a break? Press Break: nothing falls on you while you sit, but your line keeps running and can still jam.

Launch your first rocket, then Recycle your factory for a Gold Bolt: each bolt makes everything you ship worth more, forever. Climb the Top Recyclers board against everyone, or just your friends.

Nothing to buy. Just build.
```

## Layout (Rojo, `default.project.json`)

- `src/server/Main.server.luau` → ServerScriptService: the world (6 plots, each with a real SpawnLocation, built
  before anyone joins), the line's tick, jams against the trusted position, purchases, the recycle (one atomic
  owner-checked write), saving with a session lock and owner token, the Top Recyclers store.
- `src/client/Hud.client.luau` → StarterPlayerScripts: the phone-first HUD, the paged line panel, the recycle
  confirmation, every ProximityPrompt (created on the player's own plot only), the board rows on your own board.
- `src/client/Yard.client.luau`: the environment bands, belt items, machine animation, the lift-off, hazards and
  ☕ Break (client-only, cosmetic, fires no remote).
- `src/shared/` → ReplicatedStorage: `Config` (every tunable), pure rules with specs (`Line`, `Economy`, `Jams`,
  `Recycle`, `Save`, `Board`, `PlotGeom`, `HudLayout`), the templates (`EnvBands`, `Rest`, `Responsive`, `FxClient`
  verbatim from plus1-jump; `Hazards` and `Trace` verbatim from meteor-drop-tycoon; `Fx` + the `Junkyard` preset) and
  `YardArt` (client art).

## Run

```
# pure specs (from this directory)
luau tests/<Name>.spec.luau
# headless gates: rebuild the bundle first, every time
cd ../robloxemu && py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
luau check_scraplinetycoon.luau          # and _save, _board, _yard, _hazards, _hud, _compile, _prompts
cd ../scrapline-tycoon && luau tests/walk.luau
```

In Studio: `rojo build -o Scrapline.rbxlx` (git-ignored), open it, Play. DataStores need a published place or *Game
Settings → Security → Enable Studio Access to API Services*; without them the server says so, the session does not
save, and Recycle is refused. Set **Players.MaxPlayers = 6** in Game Settings (one plot per player).
