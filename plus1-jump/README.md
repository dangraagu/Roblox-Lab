# +1 Jump Every Step 🔼 — Sky Temple Obby

An incremental climb-obby: **step on any tile → +1 Jump Power**. More jump power = you
clear taller sky-temple tiers. **REBIRTH** sends you back to the pad and banks a permanent
multiplier on jump HEIGHT (you still earn +1 per platform). It is prestige, not a shortcut: the jump
caps at 60 studs and every tier is clearable without it, so it never makes the climb faster (owner's
decision 2026-09-30, `EYECANDY.md` §11). Single-server, shared procedurally-generated tower, DataStore
saves, codes (gamepasses: off in v1 and cosmetic only, never pay-to-win), and a Top Climbers board by the spawn (Public / Friends, best tier, ties to
whoever got there first; `EYECANDY.md` §16).

## Store description

The text for the experience page, checked against the game on 2026-09-30: 987 characters (the dashboard allows
1000), plain ASCII, no emoji at all (Roblox rejected coloured-square emoji, `docs/publishing.md`). "About 35 minutes"
is the pacing model's number (`tests/Pacing.spec.luau`: 34.4 min for a normal player), not telemetry. The live text
(`docs/marketing/store-text.json`) predates the sky and the board; it is replaced with `tools/store_text.py` after
the new version is published, never before.

```
Every new platform you step on gives +1 Jump Power: 0.6 studs more jump. Six platforms per tier; the tower never ends. The +1 only counts past the highest platform you have reached this run, so walking old ground pays nothing.

The sky changes as you climb: temple grounds, treetops, the cloud sea, a storm, the edge of space, SPACE at tier 85 (about 35 minutes in, by our estimate), deep space, and beyond the galaxy at tier 240.

Rare hazards come with a warning and a red ring. Step out of the ring and they miss. A hit only knocks you off, and a fall puts you back on the platform you last earned. No kill bricks. You cannot die.

Tap Rest to take a break. Nothing flies at you while you rest.

REBIRTH from tier 10 multiplies your jump HEIGHT: 2x, 5x, 10x and up. It is prestige, not a shortcut: the jump caps at 60 studs.

The Top Climbers board by the spawn shows Public or Friends, ranked by best tier. Ties go to whoever got there first.

Codes: WELCOME, SKYHIGH, TEMPLE, LAUNCH
```

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative game logic (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — display only: `Hud.client.luau` (counters, codes, top-10 panel, rebirth),
  `Sky.client.luau` (the sky bands, rare hazards, rest; cosmetic and local — see `EYECANDY.md`) and
  `Board.client.luau` (draws this player's view of the Top Climbers board on the board part by the spawn)
- `src/shared/` → `ReplicatedStorage` — pure, tested modules:
  - `Config.luau` — every tunable in one place (incl. `Env`, `Hazards`, `Rest`, `Pacing`, `Budget`)
  - `Rng.luau` — deterministic LCG PRNG (same in Studio and luau-CLI)
  - `Progression.luau` — jump/rebirth/tier math + the reachability invariant + altitude ↔ tiers
  - `TowerGen.luau` — deterministic per-tier layout generator
  - `Codes.luau` — pure code redemption
  - `Board.luau` — the highscore board's pure rules (stored value with the earliest-first tie-break, the public
    and friends views, a TTL cache, the read limiter)
  - `EnvBands.luau`, `Hazards.luau`, `Rest.luau` — game-agnostic template modules for progress-driven
    environments, rare telegraphed hazards and rest (copy them with their specs)
  - `SkyArt.luau` — +1 Jump's code-built sky scenery, critters and hazard models (client only)
  - `Fx.luau`, `FxClient.luau`, `Responsive.luau` — the repo's shared visual and phone-layout kit

## Run in Studio
1. `rojo serve` and connect from the Rojo Studio plugin, **or** `rojo build -o Plus1.rbxlx`.
2. Press **Play**. Watch Output for `[Plus1] +1 Jump Every Step lastet.`
3. DataStore needs a published place **or** Studio → Game Settings → Security →
   *Enable Studio Access to API Services*.

## Tests (pure logic, no Roblox)
Uses the luau CLI (already in this repo's scratch tooling):
```
luau tests/Rng.spec.luau
luau tests/Progression.spec.luau
luau tests/TowerGen.spec.luau
luau tests/Codes.spec.luau
luau tests/responsive.spec.luau
luau tests/EnvBands.spec.luau      # sky bands (template module)
luau tests/Hazards.spec.luau       # rare telegraphed hazards (template module)
luau tests/Rest.spec.luau          # rest rules (template module)
luau tests/Altitude.spec.luau      # altitude <-> tiers climbed
luau tests/EnvConfig.spec.luau     # +1 Jump's sky/hazard/rest config
luau tests/Pacing.spec.luau        # space in 30-45 min for a normal player (measured); the climb guard
luau tests/Board.spec.luau         # the highscore board's rules
```
Headless (robloxemu): `check_plus1`, `check_plus1_rejoin`, `check_plus1_spawn`, `check_plus1_sky`,
`check_plus1_sky_rejoin`, from review round 1 `check_plus1jump_hazards`, `_rest`, `_join`, `_bands`,
`_world`, `_leftout`, `_rebirth`, from the resume session `check_plus1jump_life`, and from review round 2
`check_plus1jump_dodge`, `_slowload`, `_budget`, from the night of 2026-09-27 `check_plus1jump_sitdrop`, and from
pass 1 of 2026-09-30 `check_plus1jump_ringtime`, `_bestseed`, and from pass 2 of 2026-09-30 `check_plus1jump_board`
(the board) and `_walk` (the whole player path, the climb guard, refusals, the owner token), and from its re-run
on 2026-10-01 `_paywin` (no Robux cost in v1, no pay-to-win pass). The sky, hazards and rest are described in `EYECANDY.md`
(§12: review round 1, §13: the resume session, §14: review round 2, §15: pass 1, §16: pass 2, §17: its re-run, §9: the
thumbnail shot list). Marketing clips: `MARKETING.md`.
A hazard's red ring is its danger zone: step out of it, any direction, and it misses (§3).
`Progression.spec` guards the key correctness property: **every tier is clearable
with the jump power a no-rebirth player has when they arrive** (t = 1..2000).

## Codes (edit in `Config.Codes`)
`WELCOME` +10 · `SKYHIGH` +25 · `TEMPLE` +50 · `LAUNCH` +100 (each once per player).

## Deploy
The experience exists (universe 10543598100, place 120040655253410, see `CLAUDE.md`). Publish with the
git-ignored `publish_plus1.bat` (Open Cloud key inline; NEVER commit it). `git push` does not update the
live game. Gamepasses are OFF in v1 (`Config.Passes.Enabled = false`; the standard allows no Robux cost in v1).
A pass may only change how a player looks (`SkyTrails`), never how they climb: the old `DoubleJump` (2x jump power)
and `AutoWalk` were removed on 2026-10-01, and `check_plus1jump_paywin` fails if one comes back.
