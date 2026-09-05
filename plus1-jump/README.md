# +1 Jump Every Step 🔼 — Sky Temple Obby

An incremental climb-obby: **step on any tile → +1 Jump Power**. More jump power = you
clear taller sky-temple tiers. **REBIRTH** banks a permanent jump multiplier so you
climb faster next run. Single-server, shared procedurally-generated tower, DataStore
saves, codes + (stubbed) gamepasses, OrderedDataStore top-10.

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative game logic (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — HUD only (`Hud.client.luau`)
- `src/shared/` → `ReplicatedStorage` — pure, tested modules:
  - `Config.luau` — every tunable in one place
  - `Rng.luau` — deterministic LCG PRNG (same in Studio and luau-CLI)
  - `Progression.luau` — jump/rebirth/tier math + the reachability invariant
  - `TowerGen.luau` — deterministic per-tier layout generator
  - `Codes.luau` — pure code redemption

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
```
`Progression.spec` guards the key correctness property: **every tier is clearable
with the jump power a no-rebirth player has when they arrive** (t = 1..2000).

## Codes (edit in `Config.Codes`)
`WELCOME` +10 · `SKYHIGH` +25 · `TEMPLE` +50 · `LAUNCH` +100 (each once per player).

## Deploy
No Roblox experience exists yet. To ship: create a new experience on Roblox → get its
**place id** → add a git-ignored publish script with the Open Cloud key (mirror
`labyrint-spill/publish_live.bat`; NEVER commit the key). Gamepasses are OFF until real
IDs are filled into `Config.Passes` and `Enabled = true`.
