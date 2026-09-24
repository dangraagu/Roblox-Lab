# +1 Jump Every Step 🔼 — Sky Temple Obby

An incremental climb-obby: **step on any tile → +1 Jump Power**. More jump power = you
clear taller sky-temple tiers. **REBIRTH** banks a permanent jump multiplier so you
climb faster next run. Single-server, shared procedurally-generated tower, DataStore
saves, codes + (stubbed) gamepasses, OrderedDataStore top-10.

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative game logic (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — display only: `Hud.client.luau` (counters, codes, board, rebirth)
  and `Sky.client.luau` (the sky bands, rare hazards, rest; cosmetic and local — see `EYECANDY.md`)
- `src/shared/` → `ReplicatedStorage` — pure, tested modules:
  - `Config.luau` — every tunable in one place (incl. `Env`, `Hazards`, `Rest`, `Pacing`, `Budget`)
  - `Rng.luau` — deterministic LCG PRNG (same in Studio and luau-CLI)
  - `Progression.luau` — jump/rebirth/tier math + the reachability invariant + altitude ↔ tiers
  - `TowerGen.luau` — deterministic per-tier layout generator
  - `Codes.luau` — pure code redemption
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
luau tests/Pacing.spec.luau        # space in 30-45 min for a normal player (measured)
```
Headless (robloxemu): `check_plus1`, `check_plus1_rejoin`, `check_plus1_spawn`, `check_plus1_sky`,
`check_plus1_sky_rejoin`, from review round 1 `check_plus1jump_hazards`, `_rest`, `_join`, `_bands`,
`_world`, `_leftout`, `_rebirth`, from the resume session `check_plus1jump_life`, and from review round 2
`check_plus1jump_dodge`, `_slowload`, `_budget`. The sky, hazards and rest are described in `EYECANDY.md`
(§12: review round 1, §13: the resume session, §14: review round 2, §9: the thumbnail shot list).
A hazard's red ring is its danger zone: step out of it, any direction, and it misses (§3).
`Progression.spec` guards the key correctness property: **every tier is clearable
with the jump power a no-rebirth player has when they arrive** (t = 1..2000).

## Codes (edit in `Config.Codes`)
`WELCOME` +10 · `SKYHIGH` +25 · `TEMPLE` +50 · `LAUNCH` +100 (each once per player).

## Deploy
No Roblox experience exists yet. To ship: create a new experience on Roblox → get its
**place id** → add a git-ignored publish script with the Open Cloud key (mirror
`labyrint-spill/publish_live.bat`; NEVER commit the key). Gamepasses are OFF until real
IDs are filled into `Config.Passes` and `Enabled = true`.
