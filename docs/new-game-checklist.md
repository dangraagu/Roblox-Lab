# New Roblox game — standard scaffold & checklist

The recipe every new game in this repo follows, so a game **looks good and is correct from day 1**
instead of getting a polish/bugfix pass bolted on later. Derived from shipping labyrint-spill,
plus1-jump, grow-a-crystal and anomaly-observatory.

---

## 1. Scaffold

```
<game>/
  default.project.json        # Rojo: src/server->ServerScriptService, src/client->StarterPlayerScripts, src/shared->ReplicatedStorage
  src/shared/                 # pure, unit-tested modules + the shared kit
    Config.luau               # EVERY tunable in one block
    Rng.luau                  # deterministic LCG (copy verbatim)
    Fx.luau                   # visual polish kit (copy verbatim)      <-- FROM THE START
    FxClient.luau             # camera/HUD juice (copy verbatim)       <-- FROM THE START
    <GameLogic>.luau          # pure rules, cfg passed as `cfg: any`
  src/server/Main.server.luau # authoritative
  src/client/Hud.client.luau  # display only
  tests/*.spec.luau           # luau-CLI tests for every pure module
  README.md  CLAUDE.md  .gitignore
```

`.gitignore` must contain `publish_*.bat` / `publish_*.sh` — **publish scripts hold the Open Cloud
API key inline and must never be committed.**

## 2. Visuals are part of the build, not a later pass

Copy `Fx.luau` + `FxClient.luau` from any sibling game, then **on the very first playable build**:

1. **Server, first thing:** `Fx.applyLighting(Fx.Presets.<Theme>)`
   Presets: `Horror` (dark/cold/dense), `Cozy` (warm glow), `Temple` (bright/airy/sunrays),
   `Maze` (post-fx only — sets **no** `lighting` fields, so a game that manages its own fog is safe).
   Add a new preset rather than hand-rolling Lighting code in the game.
2. **Signature particles** — one or two, themed: `Fx.attachGlow`, `Fx.sparkle`, `Fx.dustVolume`, `Fx.trail`.
   Rule of thumb: anything the player *earns* or *chases* should glow; anything interactive should
   read as interactive (a faint rim glow on a clickable part is onboarding, not decoration).
3. **Client** — `FxClient.theme()` on HUD frames (corner/stroke/gradient), and camera juice on the
   one signature event: `FxClient.shake` / `FxClient.flash` / `FxClient.fovPunch`.

All of the above is **code-only — no art assets required.** What genuinely needs assets (and so must
come from the user or the marketplace): custom meshes/textures, skyboxes, audio, custom fonts.

## 3. Correctness traps — check these every time

These are real defects that shipped or nearly shipped in this repo. Treat them as a standing gate.

| Trap | Rule |
|---|---|
| **DataStore integer keys** | JSON round-trips sparse INTEGER keys to STRINGS. Use string keys, or normalise on load (`numKeys`). |
| **LCG low bits** | `state % span` collapses for even/power-of-two spans. Use `Rng.below` (high bits), never `Rng.int`, for small ranges. |
| **Seed overflow** | Keep every intermediate under 2^53. `userId * <big constant>` overflows and silently zeroes the low bits. Reduce the userId first. |
| **Session lock** | Ownership must be a **stable per-session token**, never a timestamp you also rewrite on each save (the guard then fires against yourself and silently stops saving). |
| **Replayable RNG** | Mix a per-session, server-only salt into any seed whose sequence a player could memorise, or the leaderboard is farmable. |
| **Silent no-ops** | Never `return` out of a player action without telling the player why. (Grow a Crystal's "i cant even place a seed" was exactly this.) |
| **One-time rewards** | Grant only inside an atomic flush, and **refuse** the grant when you cannot persist — otherwise it is re-redeemable. |
| **Unfair randomness** | Every "spot it" variant must be genuinely perceivable and not occluded. Verify each one. |
| **Unbounded coordinates** | Recycle per-player zone indices; never let offsets march outward forever. |
| **Ownership vs selection** | Keep an owned-set; never infer ownership from the currently-selected value. |

## 4. First-run UX (the thing that actually kills new games)

A new player must perform the **core action within ~5 seconds** with no hidden prerequisites.
- Give the starting resource for free (don't make step 1 a purchase).
- Collapse multi-step setup into one click where possible (auto-buy on interact).
- On-screen hint naming the exact action + key/click.
- Never fail silently.

## 5. Verify before ship

```
luau tests/<each>.spec.luau          # all pass, 0 failed
luau-compile --binary <each src>     # syntax (rojo build does NOT compile Luau)
luau-analyze <each src>              # clean after filtering Roblox global/type noise
```
Then an **adversarial review** (parallel reviewers per dimension + verification of each finding)
before publishing. Pure logic gets TDD; the server/client glue gets the review.

## 6. Ship

Create the experience → git-ignored `publish_*.bat` (Open Cloud key inline) → **content-maturity
questionnaire** (the Preview page is ground truth; a green check means "answered", not "No") →
set Public. Remember: `git push` does **not** update the live game — run the publish script.
