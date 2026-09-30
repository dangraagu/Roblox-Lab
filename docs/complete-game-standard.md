# What a complete game has (owner's standard, 2026-09-30)

The owner asked for "complete games, including everything we have discussed". This is that list, collected
from the owner's decisions since 2026-09-04. Every game in this repo, old or new, is measured against it.
`docs/new-game-checklist.md` is the build recipe and the list of correctness traps. This file is the finish line.

## 1. It works, and it is honest
- The core loop is reachable from join. Walk the real player path headless: spawn, first objective, one full
  loop, earn, spend, rejoin. Green unit tests are not a working game.
- Spawn follows `robloxemu/SPAWN-ORDER.md`: `plr.RespawnLocation` points at a real, enabled SpawnLocation.
- Server-authoritative. Nothing secret replicates: server-only state lives in `ServerStorage`, never as an
  attribute or an Instance under `workspace`, `ReplicatedStorage` or the player. No RemoteEvent payload
  hands over an answer. A seed a player could memorise gets a server-only salt, and a salt on a 32-bit seed
  that also drives visible geometry is not enough (fork-tower REVIEW-4).
- DataStore: pcall everything, `canSave` only while holding the session lock, an owner token on every
  write (fork-tower `old.session`), string keys, one-time grants inside one atomic UpdateAsync.
- No silent no-ops: a refused player action says why.

## 2. It looks good from the first build
- Fx preset and signature particles from day 1 (`docs/new-game-checklist.md` §2).
- **Eye candy** (owner, 2026-09-17): the environment changes as the player progresses, following the game's
  own logic, so it never feels monotonous. Use the +1 Jump templates verbatim: `EnvBands.luau`,
  `Hazards.luau`, `Rest.luau` (from `plus1-jump/src/shared`, with their specs). Adapt only where the game
  needs it, and say why.
  - **Bands:** at least 5, each with its own light, colour, scenery, critters and weather, glided smoothly.
  - **Hazards:** rare and themed. They are telegraphed, and a red ring marks exactly where a hit can land,
    so stepping out of it always dodges. Aim for about one near-miss per 2-3 minutes and never more than
    one hazard at a time. A hit costs a little, never a run. If knock-downs are wrong for the genre
    (for example idle games), use harmless rare events instead and say why.
  - **Rest / pause:** the player can take a break somehow ("man skal kunne trykke på pause"). A rest must
    never become an exploit: it freezes the hazard clock and earns nothing it should not.
  - **Budgets** (parts, emitters, lights) are measured and capped in code.
- **A brag moment** within about 30-45 minutes of normal play (+1 Jump: reaching space), and a long-term
  goal beyond it. Measure the minutes with a pacing model in `tests/`.
- **Phone first:** a root Frame with a `UIScale`, nothing tappable under the thumbstick or jump button,
  tap targets of 44 screen px or more, and the HUD overlap rule 4b asserted (`overlap = true` in the game's
  hudcheck), or a written reason why not.

## 3. Players can compare themselves
- **A highscore board, public and friends** (owner, 2026-09-16, designed for Anomaly). Rank on a
  server-measured metric that a script cannot inflate, with ties broken by who reached it FIRST.
  - Store it in an OrderedDataStore, key `u_<userId>`, and encode the value as
    `metric * 2e9 + (2e9 - reachedAtUnix)`. Write only when the metric improves.
  - Public board: `GetSortedAsync(false, 10)`, cached server-side for about 60 s.
  - Friends board: `Players:GetFriendsAsync`, capped (for example 200), fetched only on demand, cached,
    all pcall'd and throttle-safe.
  - Show it on a physical board in the world near spawn, with a ProximityPrompt that toggles
    Public/Friends. Resolve names with `GetNameFromUserIdAsync` and cache them; never store names.
  - An empty friends board says something useful.
- Promo codes, if any, are public by design. Never a Robux cost in v1, and never gambling or pay-to-win.

## 4. It is ready to ship and to market
- `README.md` has the store description: at most 1000 characters, honest, with no coloured-square emoji.
- `EYECANDY.md` has a **needs-Studio list** (what only real rendering and input can settle) and a
  **thumbnail shot list** (camera, place, what is in frame; 1920x1080).
- A **clip list**: 5-10 short gameplay moments (7-15 s, vertical 1080x1920) for `tools/film_game.py`,
  each with how to stage it. Put it in `MARKETING.md`.
- `CLAUDE.md` says how to run every gate and names the traps this game has.
- Every gate is green, TDD throughout, and new assertions are mutation-tested with a control.

## 5. What only the night shift does (Studio, 00:00-06:00)
The Studio check of the needs-Studio list, thumbnails, clips, creating the universe, publishing, and then
marketing. It follows `C:\Users\bahs_admin\.claude\scheduled-tasks\roblox-night-shift\SKILL.md`.
Marketing (Reddit and forums) starts only after the new version is live, spread over a day and the next,
one game at a time, in communities whose rules allow self-promotion, labelled as AI-assisted.
