# CLAUDE.md — Nightwatch Manor: Haunted Escape Tycoon (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/`, `anomaly-observatory/`; same stack (one CONFIG table, deterministic `Rng`,
DataStore with `canSave` + a soft session lock, pure logic tested from the luau CLI). Built from
Game-Radar concept #2 (2026-09-09) — the seasonal one, aimed at the Sept–Oct horror window.

## What it is

A two-phase horror tycoon.

**NIGHT** — the server builds a manor from `Manor.plan` (a seeded grid of modular rooms), fills it
with relics on pedestals, and starts one Nightwatcher on a patrol route through the doorways. The
player takes relics and has to reach the Servants' Exit before DREAD reaches 1.

**DAY** — a persistent per-player safehouse. Each upgrade is an in-world pad with a
ProximityPrompt; buying a level spends relics, stacks a visible prop on the pad, and moves a number
the next night reads.

Failure (caught, or evicted at full dread) costs the haul you were carrying. It does **not** roll
back the night and does **not** touch the safehouse.

## State — built, unit-tested, mutation-tested, booted headless. NOT published, NOT committed.

- **6 spec files, all green**: Manor 61, Watcher 71, Upgrades 92, Night 64, Rng 32, responsive 70.
- **`robloxemu/check_nightwatch.luau`: 84 passed, 0 failed** — boots the real server and plays the
  loop against the workspace.
- **`robloxemu/check_nightwatch_hud.luau`: PASS** across ten viewports, with both phone drawers
  opened by the warmup so the compact layout is actually measured rather than skipped.
- `luau-compile` clean; `luau-analyze` clean after filtering Roblox global/type noise.
- Never run in Studio or a real client. No experience created, nothing published, nothing pushed.

## Core model / invariants

- **Determinism**: `Manor.seedFor(cfg, night) = WorldSeed * SeedPrimeA + night * SeedPrimeB`. The
  userId is deliberately NOT folded in — night N is the same manor for everyone, which is what
  makes a best-night number comparable. Both products stay far under 2^53, so no low bits are lost
  to float rounding (the trap that pinned a sibling game to one outcome forever).
  The trade-off is real and accepted: layouts are memorisable across sessions.
- **Growth, not carving**: `Manor.plan` attaches each new room to a random room that still has a
  free orthogonal neighbour. That yields a connected tree by construction — no unreachable wing,
  no unreachable exit — and it terminates.
- **The exit is always the deepest room**, so every night is a full crossing.
- **Walls block sight with no raycast**: `Watcher.spots` is the cone AND a `roomOk` flag the server
  computes from `Manor.roomAtWorld` + `Manor.linked`. Roblox's `Raycast` is not modelled by the
  headless emulator, and this design does not need it.
- **The chase is our own BFS**, `Manor.pathBetween`, over at most 18 nodes — not
  PathfindingService. The watcher beelines at the centre of the next room on the path, which is
  what keeps it going through doorways instead of through walls.
- **Dread is accumulated from `task.wait`'s return value**, never from a wall clock. The emulator
  drives a virtual clock, so `os.clock()` would sit at zero for an entire simulated night and the
  loop would be untestable.
- **Three dispatch tables, three startup guards.** `ROOM_BUILDERS`, `RELIC_BUILDERS` and
  `UPGRADE_PROPS` are keyed by the ids in `Config`, and the server `error()`s at boot if any
  catalog entry has no handler. Adding an entry to a `Config` list does NOT make it happen. This is
  the pattern taken from `anomaly-observatory`, and each of the three failures it catches is
  silent and green to every unit test.
- **Nothing the client sends is trusted, because the client sends nothing.** Every action is an
  in-world ProximityPrompt whose handler checks `who == plr`. The only remotes are `State` and
  `Notice`, both server -> client.
- **Zone indices are recycled** through a free list on `PlayerRemoving`, so a long-lived server
  never marches out to where float precision degrades.
- **DataStore**: `GetDataStore` is pcall'd (it RAISES in an unpublished place and would otherwise
  kill the whole script at load). Soft session lock — always load the real data, save only while we
  hold the lock, and never clobber a lock somebody else took. Ownership is a stable per-session
  GUID, never a timestamp we also rewrite.
- **Effect ceilings**: `MaxDreadSlow` / `MaxWatcherSlow` / `MaxKeepOnCaught` are NOT binding with
  today's catalog (the natural maxima sit at or below them). They exist for the retune that will
  happen, and `Upgrades.spec` exercises them by temporarily raising every `max` — without that, a
  mutation deleting the `keepOnCaught` clamp passed the entire suite.

## Files

- `src/shared/Config.luau` — every tunable, plus the three catalogs.
- `src/shared/Manor.luau` — layout generation, room-graph queries, `pathBetween`.
- `src/shared/Watcher.luau` — route maths, `dread`, `speed`, `sees`, `spots`, `hears`, `caught`,
  and the PATROL/HUNT state machine.
- `src/shared/Upgrades.luau` — `cost`, `canBuy`, `buy` (never mutates its input), `effects`,
  `sanitize`, `EFFECT_KEYS`.
- `src/shared/Night.luau` — `dreadSeconds`, `payout`, `startState`, `resolve` (raises on an
  outcome nobody defined).
- `src/server/Main.server.luau` — world building, the night loop, persistence.
- `src/client/Hud.client.luau` — display only.
- `../robloxemu/check_nightwatch.luau`, `../robloxemu/check_nightwatch_hud.luau`.

## Mutation results (run 2026-09-09, all restored afterwards)

Killed: remove the carried lantern; remove the pedestal `Taken` attribute; unparent every wall;
remove the `who ~= plr` guard on an upgrade pad; delete a `ROOM_BUILDERS` entry (refuses to boot);
break `exit is deepest`; make CAUGHT advance the night; make the sight cone always true; drop the
`keepOnCaught` clamp (after the spec was strengthened).

Survived once, then fixed: passing `Upgrades.effects(Config, {})` into `Night.resolve` instead of
the player's real effects — invisible until the headless check bought a Relic Vault first.

Controls (changes the suites must NOT notice, all verified silent): renaming a room kind, renaming
a relic tier, rewriting an upgrade blurb, retuning `HuntSpeedMul`, renaming an upgrade.

## NOT built — be honest about these before writing any store copy

1. **No environmental puzzles.** The brief says "solve light environmental puzzles". There are
   none. A night is walk, take, avoid, leave.
2. **One currency, not two.** The brief and the paste-ready description say "relics **& cash**".
   Cash is folded into relic worth. Either add the second currency or edit the description.
3. **No audio at all.** No ambience, no footsteps, no stinger. In a horror game that is the single
   biggest gap, and it needs assets we do not have.
4. **No real jumpscare.** Being caught is a red screen flash, a camera shake and a toast. There is
   no jumpscare model, animation or sound.
5. **Traps do not fire.** Bear Traps slow the Nightwatcher globally and stack a prop on their pad;
   they are not placeable traps that trigger in the manor. Same for the Alarm Bell (it grants a
   proximity warning, it does not ring) and the turrets in the description, which do not exist.
6. **No unlock gate.** The brief has the safehouse "gating access to harder/larger manor seeds".
   Hub level grows the manor, but nothing is locked behind it — the night simply advances when you
   extract.
7. **No character death.** Being caught teleports you home and takes the haul. The Humanoid is
   never damaged and there is no ragdoll or respawn beat.
8. **No spawn point.** Players are teleported on `CharacterAdded` (and immediately, if the
   character already exists). There is no `SpawnLocation` in the safehouse, so a joining player can
   briefly fall at the world origin before the handler catches them. Worth fixing early.
9. **No leaderboard surface.** Best night is written to an OrderedDataStore but nothing reads it
   back — there is no in-world board and no HUD ranking.
10. **No codes, no gamepasses, no badges, no cosmetics.**
11. **Never run in Roblox.** Everything above was verified by the luau CLI and the headless
    emulator. The emulator is not Roblox: it models no physics, no rendering and no Raycast, so
    first real play will surface things neither gate can see — furniture the player can get stuck
    on, a pedestal clipping a bookshelf, a manor too dark to navigate.

## Next

1. Open it in Studio and walk a night. Check the manor is navigable and lit enough to read, the
   prompts are reachable, and the Nightwatcher is a threat rather than scenery.
2. Add a `SpawnLocation` in the safehouse (item 8) — it is the cheapest real bug on the list.
3. Audio pass (item 3) — the largest genre gap, and it needs marketplace assets.
4. Decide the currency question (item 2) and fix the description to match the code before the
   experience is created.
5. Then the usual ship path: create the experience, git-ignored `publish_nightwatch.bat` with the
   Open Cloud key inline, maturity questionnaire (the Preview page is ground truth — a green check
   means "answered", not "No"), then Public. `git push` does NOT update the live game.
