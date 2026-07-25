# Labyrint-spill — Lobby, Doors & Sequential Progression (design spec)

**Date:** 2026-07-25
**Status:** Approved for planning
**Scope:** Rearchitect the maze game from one global shared maze into a lobby hub
with per-player/per-group maze *instances*, strict per-player sequential
progression, three play modes, and god-mode-fair leaderboards.

---

## 1. Problem & goals

Today there is **one** global maze and one global `currentLevel`; everyone in a
server is forced onto the same level and advances together. This causes:

- **Carry bug:** player 2 (low level) joins a room at level 200 and gets credited
  for completing 200 they never earned.
- **God-mode inflation:** a god-mode player can reach level 500, and the
  leaderboard/records can't cleanly distinguish legit from god runs.
- **No player agency:** no way to play solo, with friends, or replay a level.

**Goals**

1. **Strict sequential progression, per player:** a player can only become
   *accepted* for level `N` if they already hold `N-1`. No skipping, no carrying.
2. **Lobby with doors:** a hub where players spawn, see each other + the
   leaderboard, and walk through a door to start a run.
3. **Three modes:** Solo Climb, Group, Play with Friends.
4. **God-mode fairness:** if anyone in an instance has god mode on when it is
   solved, that clear counts for **nothing** on any leaderboard/record and grants
   no `accepted`. Separate "with god" ledger for bragging.
5. Preserve coins/gems/themes/perks/best-times.

**Non-goals (deferred):** teleport/reserved-server private games (we stay
single-server, per §3); Robux economy; cosmetic gem shop; replay of a level you
have not yet unlocked.

---

## 2. Core progression model

Per-player saved fields (DataStore `LabyrintSpill_v1`, additive):

| Field | Meaning |
|---|---|
| `accepted` | Highest level completed in strict sequence with **no god** in the run. Leaderboard basis. Default seeded on migration (see §7). `0` = nothing cleared; next playable = `accepted + 1`. |
| `bestWithGod` | Highest level ever reached including god runs. Bragging only; never on the public leaderboard. |

Existing fields kept: `coins, gems, trophies, best, owned, theme, receipts,
bestByLevel, perks, gifts, rewardDay, streak`. The old `level` (resume pointer)
is superseded by `accepted` and removed from gameplay logic (kept read-only for
migration only).

**Sequential rule (the invariant):** `accepted` may only ever increase by exactly
`+1`, and only when a player cleanly completes level `accepted + 1`. It can never
jump. This is enforced server-side at clear time.

**God rule (global to an instance):** an instance tracks `hadGod` — set true the
moment **any** participant enables god mode during that instance's current level,
reset when the instance builds a new level. On a solve, if `hadGod` is true (or
any participant currently has god active), the clear yields:

- no `accepted` change for anyone,
- no time record,
- no global-leaderboard submission,
- `bestWithGod` may still update (it's the "with god" ledger).

---

## 3. Physical architecture — one server, many instances

One Roblox place, one server. No teleporting. Two kinds of space:

- **Lobby hub** (built once at server start): spawn pads, three doors, and the
  leaderboard display. All players share it and see each other here.
- **Maze instances**: each active run gets its own maze built in its own region
  of the world, offset far from the lobby and from other instances
  (`instanceIndex * OFFSET` on one axis). Players in a run are teleported (via
  `PivotTo`/`MoveTo` inside the place) to their instance's spawn; on finish/quit
  they return to the lobby.

### Instance record
```
Instance = {
  id            = number,       -- unique, also drives the spatial offset
  mode          = "solo"|"group"|"friends",
  level         = number,       -- the level currently built
  participants  = { [Player]=true },
  hostUserId    = number?,      -- friends mode: who opened the door
  folder        = Folder,       -- the built maze (destroyed on teardown)
  origin        = Vector3,      -- world offset for this instance
  hadGod        = boolean,      -- any god used on the current level
  gen           = number,       -- build generation (stops stale loops)
  -- per-instance run state (coins collected, exit unlocked, monsters, par, ...)
}
```

### Module boundaries (server)
- **LobbyService** — build the hub, the three doors (Touched → mode entry), and
  render the lobby leaderboard. One purpose: the hub UI/world.
- **InstanceManager** — create/assign/teardown instances; own the Player↔Instance
  map; pick spatial offsets; teleport players in/out. One purpose: instance
  lifecycle + routing.
- **MazeBuilder** — the existing maze generation, refactored to build **into a
  given instance** (origin offset, level, deterministic rng by level). Pure of
  global state. One purpose: build one maze.
- **RunController** — per-instance gameplay loop currently living in
  `buildLevel`/`onEscape`: spawn, pickups, traps, monsters, exit, timer, solve.
  Operates on an `Instance`, not globals.
- **Progression** — pure logic: given (level, accepted, hadGod, mode, isHost),
  decide `{ acceptedDelta, recordEligible, leaderboardEligible, withGodUpdate }`.
  No Roblox API → unit-testable.
- **Matchmaking** — Group: find an open instance at the player's `accepted`, else
  open one. Friends: find the host's instance (same server), join it.

### Module boundaries (client)
- **LobbyClient** — door prompts, mode selection, and the **Solo level chooser**
  ("Continue → level N" or "Pick a level" 1…accepted+1).
- Existing **HudClient / ShopClient / PerkClient / MinimapClient / GodModeClient /
  AdminBroadcastClient / LeaderboardClient** adapted to per-instance data (they
  already run per-player; they bind to the local player's current instance state).

Because `MazeGame.server.luau` is already ~1500 lines, this rearchitecture is the
right moment to split it into the modules above (ServerScriptService with
ModuleScripts), rather than growing the single script further.

---

## 4. The three doors

### Solo Climb (strict)
On entering the Solo door the client shows a chooser:
- **Continue** → build a solo instance at `accepted + 1`.
- **Pick a level** → a picker of `1 … accepted + 1`. Levels `≤ accepted` are
  replays (for better times/records); `accepted + 1` is the frontier.
- Never selectable above `accepted + 1`.

Clean clear of `accepted + 1` → `accepted += 1`. Clean clear of a replay level →
updates best time / global record only. Then: return to lobby, or "next level"
straight into `accepted + 1`.

### Group (strict)
Matched (Matchmaking) into a shared instance with server-mates **at the same
`accepted`**. Everyone climbs the same maze together; each participant earns their
own `accepted += 1` on their own clean clear. The instance advances its `level`
when the group moves on; because all were matched at the same `accepted`, they
stay in lockstep. If nobody matches, you get a solo-sized group instance others
can still join.

### Play with Friends (relaxed)
You (host) open a private instance; friends already in the server join through
your door (gated to your Roblox friends / same-party). The host chooses the level
up to `host.accepted + 1`. Lower-level friends may join a **higher** level for
fun. Earning is still strict: a carried friend clearing a level above their own
`accepted + 1` gets **no** `accepted` credit (only `bestWithGod`-style "reached"
tracking if desired); they only advance `accepted` when they themselves clear
their own `accepted + 1` in sequence.

---

## 5. God-mode fairness (all players)

- Instance `hadGod` set when any participant toggles god on during the current
  level; reset on each level build.
- At solve, Progression returns `leaderboardEligible = recordEligible =
  (acceptedDelta applies) = false` if `hadGod` or any participant currently god.
- `bestWithGod = max(bestWithGod, level)` still updates for participants.
- Mio's profile (and the lobby, for himself) shows **Highest (clean) = accepted**
  and **Highest (god) = bestWithGod** separately.
- This makes "god to 500, then clean-solve 500" impossible: `accepted` only
  advances one level at a time and only on fully-clean runs, so the 1..499 gap is
  never legitimately filled.

---

## 6. Leaderboards

- **Global climbers** — OrderedDataStore, keyed by `accepted`. **New store name
  `LabyrintTopp_v2`** so the old (possibly carry/god-inflated) values are not
  inherited. Submitted only on clean sequential clears; GodUsers still excluded
  from the public board entirely (existing rule kept).
- **Per-level fastest times** — existing `LabyrintRekord_v1`, top-3 per level
  (already built), now only written on clean (no-god) clears.
- Shown both on a **lobby board** (SurfaceGui in the hub, always readable) and the
  in-run top-right records panel (already built).

---

## 7. Migration (seed from best times)

On first load under the new system, if `accepted` is absent:
`accepted = ` the largest `N` such that `bestByLevel["1"], … , bestByLevel[tostring(N)]`
all exist (the highest **contiguous** run of personally-recorded clears),
else `0`. `bestWithGod = max(accepted, old d.level or 0)`. This preserves real
progress (Marius/Mio keep their legit sequential level) without importing
inflated/carried numbers. Coins/gems/themes/perks/best-times are untouched.

---

## 8. Testing strategy

- **Progression** (pure): table-driven cases — sequential increment only on
  `accepted+1`; no credit on carry (level ≠ accepted+1); no credit when `hadGod`;
  `bestWithGod` updates regardless; friends-carry grants nothing skipped;
  migration contiguous-seed. Unit-testable without Roblox (luau CLI when
  available; otherwise reviewed + logic-asserted).
- **MazeBuilder** (pure-ish gen): determinism per (level, seed); unchanged
  generator behavior.
- **InstanceManager**: assign/teardown, offset uniqueness, no orphaned folders,
  no cross-instance bleed (a solve in instance A never advances instance B).
- **Integration (Studio, manual):** the three modes, the god rule, the solo
  picker, lobby↔instance transitions.
- **Adversarial review** of the diff before publish (per repo workflow), with
  focus on the anti-cheat invariants and instance isolation.

---

## 9. Rollout

- Build behind the scenes; keep the current live game (v13) running.
- Publish only after Studio smoke-test of all three modes + the god rule +
  adversarial review.
- The maze generator, themes, medals, perks, shop, daily reward, broadcast, and
  records systems are **reused**; the new work is the lobby, instances, routing,
  and the accepted/god progression rules.

---

## 10. Open items (decide during planning, not blockers)

- Exact door UX (ProximityPrompt vs walk-through trigger) and lobby art.
- Group "advance in lockstep" edge cases (a member quits mid-level).
- Friends invite gate (Roblox friends check vs open "join host" in same server).
- Instance cap per server (memory) and teardown timing for empty instances.
