# Grow a Crystal 💎 (Cavern Idle)

A cozy idle-grow sim: **plant seed-crystals in your cavern, watch them grow and refract
into rarer gems — even while you're offline.** Harvest for Gem Dust, buy rarer seeds +
new chambers + luck/growth boosters, crack a weekly Geode, complete your Gem Codex, and
climb the highscore board by your spawn. Game-Radar #2 concept (2026-09-05); reuses the
procedural-gen + DataStore + single-server stack from the maze / +1 Jump games.

Live: universe `10543994765`, place `106123351742435` (https://www.roblox.com/games/106123351742435).
Last published 2026-09-10 (version 11, `publish_response.json`), so the live build has none of the work from
2026-09-23 on (the living cavern, both review rounds, the board); publishing waits for the night shift's Studio check
(`EYECANDY.md` §8).

## Store description

At most 1000 characters (this one is 950), no emoji, and it promises nothing the game does not do today.
The odds are `Rarity.upgradeChance` multiplied out (0.5 x 0.35 x 0.22 x 0.12 x 0.05 = 1 in 4,329; at Luck 10 every
step is x2.5, capped at 0.95: 1 in 58). The live text in `docs/marketing/store-text.json` is older (it still says
the Shard costs 10 and loses money, and that the board refreshes every 30 seconds) and should be replaced by this
one when the new version is published.

```
Grow a Crystal (Cavern Idle)

Plant a seed-crystal in a glowing socket, come back when it has grown, and harvest it for Gem Dust. A Shard takes 60 seconds. Rarer seeds take longer, and every seed keeps growing while you are offline.

Each harvest rolls refraction: the crystal climbs one tier per hit and stops at the first miss. Shard, Quartz, Amethyst, Prism, Legendary, Mythic. A Mythic from a plain Shard is 1 in 4,329 at Luck 0 and about 1 in 58 at Luck 10.

- Dust buys seeds, Luck, Growth and new chambers: 8 terraces, 48 sockets.
- The cavern changes as you open chambers: glow-worms, giant mushrooms, a waterfall, the Heart of the Geode.
- A weekly Geode, a Gem Codex, and free codes: WELCOME, CRYSTAL, GEODE, MYTHIC.
- A highscore board behind your spawn ranks Gem Dust earned from harvests. Its prompt switches it to your Roblox friends.
- Relax: sit down while your crystals grow.

Built solo, code only. Nothing in this game costs Robux.
```

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — HUD (`Hud.client.luau`) and the living cavern (`Grotto.client.luau`)
- `src/shared/` → `ReplicatedStorage` — pure, unit-tested modules:
  - `Config.luau` — every tunable (tiers, refraction odds, growth times, economy, geode, codes, board, pacing)
  - `Rng.luau` — deterministic LCG (same in Studio + luau-CLI)
  - `Rarity.luau` — refraction roll (climb-a-tier, luck-boosted, server-only salt)
  - `Growth.luau` — offline growth math (stateless timestamp diff)
  - `Economy.luau` — harvest value + shop purchases (mutate-on-success)
  - `Geode.luau` — weekly event (week bucketing + rotation)
  - `Codex.luau` — discovered-rarity tracking
  - `Codes.luau` — one-time code redemption
  - `Board.luau` — the highscore board's rules (encoding, tie-break, views, caches, read limiter)
  - `Cavern.luau` — the cavern's geometry, the spawn and the board's spot; plus the eye-candy modules below

## Core loop
Plant (consumes a seed) → grows over real time (offline counts) → harvest a mature
crystal → **refraction roll** may upgrade its tier → Gem Dust → buy rarer seeds / chambers
/ boosters → the cavern changes with every chamber → weekly Geode + codes + Codex chase, and the
highscore board.

**The brag moment** is your first Mythic crystal: the game's biggest celebration (magenta flash, a beam of light,
a title card) and 1500 Gem Dust on the board. The pacing model puts it at a median of 31 minutes of normal play
(p10 4, p90 70; `tests/Pacing.spec.luau`). **The long-term goals** are the Heart of the Geode (chamber 8, median
238 minutes) and the board.

## The highscore board (public + friends)
A board on the entrance wall of your own cavern, 8.5 studs behind where you spawn. It ranks **Gem Dust earned from
harvests** (codes, the Geode and purchases never count), in whole points of 100, ties to whoever reached the score
first. Its prompt switches between everyone (the store's top 10, read once a minute per server) and your Roblox
friends (fetched only when you ask, up to 200, cached; their scores read at most 40 at once and then 1 a second).
Stored in the OrderedDataStore `GrowCrystal_LB_v2` as `points * 2e9 + (2e9 - reachedAtUnix)`, written only when
your points rise. Names are resolved on the server and cached, never stored. The HUD's "Top" panel shows the same
public rows. `Board.luau` is adapted from `plus1-jump/src/shared/Board.luau` (rows carry `metric`, and the metric is
dust in points of 100, because a normal player earns about 1.1 million dust in 8 hours and the encoded value is only
exact up to 4 million points).

## Run in Studio
1. `rojo serve` + connect from the Studio plugin, or `rojo build -o GrowCrystal.rbxlx`.
2. Press **Play**. Output: `[Crystal] Grow a Crystal lastet.`
3. DataStore needs a published place or Studio → Game Settings → Security → *Enable Studio
   Access to API Services*. Without it the game runs and saves nothing, says so at join ("Saving is off here"), grants
   the public codes and the Geode for that session only (nothing persists, so nothing can be duplicated), and the
   board says it is offline (or keeps loading, if the place is published and only API access is off).
4. You spawn on your private plot, facing the sockets. Click (tap) a glowing socket to plant, click a grown
   crystal to harvest. The board is behind you.

## The living cavern (client-side eye candy) — see `EYECANDY.md`
The cavern changes with the chambers you own: 💧 Sunken Grotto → ✨ Glow-worm Hollow → 🍄 Mushroom Terraces →
🌊 Waterfall Chamber → 💎 Heart of the Geode, gliding in (never a hard cut), each with its own life and weather
(glowflies and glow-worm silk, fireflies, bats and mist, wisps and sparkle), plus a slow geode pulse, harvest bursts in
the refracted tier's colour, a beam of light for Legendary/Mythic, rare harmless visitors (moth swirl, bat swoop), and
**🛋 Relax** (sit, soft focus, visitors leave you alone; crystals keep growing). No knock-down hazards, on purpose.
Everything is built on the client (`src/client/Grotto.client.luau` + `src/shared/CavernArt.luau`); the server only adds
the harvest's already-paid result to its State push.

## Tests — every gate must exit 0
Rebuild the bundle first, then run every spec and every headless check (`CLAUDE.md` has the exact commands):
```
cd robloxemu && py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
cd grow-a-crystal/tests && for t in *.spec.luau; do luau $t 2>&1 | tail -1; done       # 17 specs
cd robloxemu && for c in check_crystal*.luau check_growacrystal*.luau; do luau $c 2>&1 | tail -1; done   # 24 checks
```
Specs (pure logic, luau CLI): Rng, Rarity, Growth, Economy, Geode, Codex, Codes, Cavern, responsive, EnvBands
(template, verbatim), Rest (template, verbatim), Visitors, Grotto, EnvConfig, Pacing (with `tests/IdleModel.luau`),
StateFeed, Board. Headless (in `robloxemu/`): `check_crystal`, `check_crystal_sockets`, `check_crystal_spawn`, and
`check_growacrystal_{walk,board,hint,harvest,env,hud,row,join,race,critters,queue,queue_hudfirst,redeem,flash,salt,refused,lock,plotbudget,pass,rejoin,clips}`.
`check_growacrystal_walk` is the whole player path in one run: join, spawn, plant, harvest, buy, leave, rejoin.
`check_growacrystal_rejoin` holds the saving rules (a session that cannot save says so and retries), and
`check_growacrystal_clips` stages every clip in `MARKETING.md` the way it says.

## Codes (edit in `Config.Codes`)
`WELCOME` +100 dust · `CRYSTAL` +500 dust · `GEODE` free Amethyst seed · `MYTHIC` +5000 dust.
Codes are public by design; their dust never counts on the highscore board.

## Deploy
Published with the git-ignored `publish_crystal.bat` (Open Cloud key inline; never commit it). `git push` does not
update the live game. Publishing, the Studio check, thumbnails and clips belong to the night shift (00:00-06:00).
Gamepasses are OFF until real IDs fill `Config.Passes` + `Enabled = true`; none is planned in v1. A pass never moves the
highscore board: `DoubleDust` doubles the dust a player spends, the board counts every harvest un-doubled
(`check_growacrystal_pass`).
