# Lobby + Modes + Sequential Progression — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rearchitect the maze game into a lobby hub with per-player/per-group maze instances, strict per-player sequential `accepted` progression, three modes, and god-mode-fair leaderboards — shipped incrementally.

**Architecture:** One Roblox place/server. A lobby hub plus maze *instances* built at spatial offsets. A pure `Progression` module owns the accepted/god rules. The 1500-line `MazeGame.server.luau` is split into focused ModuleScripts (`MazeBuilder`, `RunController`, `InstanceManager`, `LobbyService`, `Matchmaking`, `Progression`).

**Tech Stack:** Roblox Luau, Rojo (`src/server`→ServerScriptService, `src/client`→StarterPlayerScripts, `src/shared`→ReplicatedStorage), DataStore + OrderedDataStore. Pure-logic tests via luau CLI when available; Studio smoke-test + adversarial review otherwise.

## Global Constraints

- Norwegian code comments; all player-facing strings **English**.
- Everything toggleable from a `CONFIG` block; a broken subsystem must not crash the rest (pcall-guard Roblox calls).
- `accepted` may only ever increase by exactly `+1`, only on a clean clear of `accepted + 1`. Never skips, never inflates. Enforced server-side.
- God rule: if **any** participant of an instance has god on when it is solved (or god was used during that level), the clear yields **no** `accepted`, **no** time record, **no** global-leaderboard submission. `bestWithGod` may still update.
- GodUsers (Mio) are additionally never on the public climbers board (existing rule kept).
- DataStore writes stay debounced/async and gated by the `d.canSave` load-success sentinel.
- Nothing goes live except via `publish_live.bat` after Studio smoke + adversarial review. Keep the current live game running until an increment is verified.

---

## Testing reality (read first)

There is **no** Roblox engine or (currently) luau runtime on this box. Therefore:
- **Pure modules** (`Progression`, and the existing `Medals`) get real table-driven Luau tests in `tests/`. Run with `luau tests/<file>.luau` **if** a luau CLI is on PATH; otherwise the reviewer verifies each asserted case by hand. Tests are written regardless (they run in CI / a dev box with luau, and they document intent).
- **Roblox-coupled code** (DataStore, Instances, remotes) is verified by `rojo build` (assembly), adversarial review of the diff, and manual Studio play-test. "Run the test" steps for these say exactly that.

---

# PHASE 1 — Progression + god-fairness + leaderboard v2 (ships in the CURRENT shared-maze architecture)

This phase needs **no** lobby. It makes the leaderboard carry-proof and god-proof
immediately. In the shared maze, the whole server is treated as one instance, so
"any participant had god" = "any player in the server had god this level".

### Task 1: `Progression` pure-logic module

**Files:**
- Create: `src/shared/Progression.luau`
- Test: `tests/Progression.spec.luau`

**Interfaces:**
- Produces:
  - `Progression.seedAccepted(bestByLevel: {[string]: number}) -> number` — highest contiguous `N` with `bestByLevel["1"]..["N"]` all present, else 0.
  - `Progression.resolveClear(args) -> result` where
    `args = { level:number, accepted:number, bestWithGod:number, hadGod:boolean, mode:"solo"|"group"|"friends", isHostLevel:boolean }`
    and `result = { newAccepted:number, newBestWithGod:number, acceptedGained:boolean, recordEligible:boolean, leaderboardEligible:boolean }`.
  - Rules encoded: `acceptedGained = (not hadGod) and (level == accepted + 1)`;
    `newAccepted = acceptedGained and (accepted+1) or accepted`;
    `recordEligible = leaderboardEligible = (not hadGod)`;
    `newBestWithGod = math.max(bestWithGod, level)`.

- [ ] **Step 1: Write the failing test**

```lua
-- tests/Progression.spec.luau
local P = require("../src/shared/Progression.luau")
local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else failed += 1; print("FAIL:", msg, "got", tostring(a), "want", tostring(b)) end
end

-- seedAccepted: contiguous run
eq(P.seedAccepted({}), 0, "empty -> 0")
eq(P.seedAccepted({ ["1"]=5, ["2"]=6, ["3"]=7 }), 3, "1..3 contiguous")
eq(P.seedAccepted({ ["1"]=5, ["3"]=7 }), 1, "gap at 2 -> 1")
eq(P.seedAccepted({ ["2"]=6 }), 0, "no level 1 -> 0")

-- resolveClear: clean earn of next level
local r = P.resolveClear({ level=51, accepted=50, bestWithGod=50, hadGod=false, mode="solo", isHostLevel=true })
eq(r.acceptedGained, true, "clean next -> gained")
eq(r.newAccepted, 51, "accepted -> 51")
eq(r.leaderboardEligible, true, "clean -> eligible")

-- resolveClear: carry (level far above accepted+1) -> no gain
local c = P.resolveClear({ level=200, accepted=50, bestWithGod=50, hadGod=false, mode="friends", isHostLevel=false })
eq(c.acceptedGained, false, "carry -> no gain")
eq(c.newAccepted, 50, "accepted unchanged on carry")
eq(c.newBestWithGod, 200, "bestWithGod tracks reached")

-- resolveClear: god active -> nothing counts
local g = P.resolveClear({ level=51, accepted=50, bestWithGod=50, hadGod=true, mode="solo", isHostLevel=true })
eq(g.acceptedGained, false, "god -> no accepted")
eq(g.leaderboardEligible, false, "god -> not eligible")
eq(g.recordEligible, false, "god -> no record")
eq(g.newBestWithGod, 51, "god still updates bestWithGod")

print(string.format("Progression: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progression tests failed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `luau tests/Progression.spec.luau` (from `labyrint-spill/`). Expected: FAIL — module missing. If no luau CLI: note "runtime absent; will assert by review" and continue.

- [ ] **Step 3: Write the minimal implementation**

```lua
-- src/shared/Progression.luau
-- Ren logikk for progresjon: "accepted"-nivå (sekvensielt), god-regel, seed.
local Progression = {}

function Progression.seedAccepted(bestByLevel)
	local n = 0
	if type(bestByLevel) == "table" then
		while type(bestByLevel[tostring(n + 1)]) == "number" do
			n += 1
		end
	end
	return n
end

function Progression.resolveClear(a)
	local hadGod = a.hadGod and true or false
	local gained = (not hadGod) and (a.level == (a.accepted or 0) + 1)
	return {
		newAccepted = gained and (a.accepted + 1) or a.accepted,
		newBestWithGod = math.max(a.bestWithGod or 0, a.level),
		acceptedGained = gained,
		recordEligible = not hadGod,
		leaderboardEligible = not hadGod,
	}
end

return Progression
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `luau tests/Progression.spec.luau`. Expected: `Progression: 13 passed, 0 failed`. If no luau CLI: reviewer confirms each case by reading the code against the asserts.

- [ ] **Step 5: `rojo build` to confirm the module assembles**

Run: `rojo build -o /tmp/check.rbxl`. Expected: success.

- [ ] **Step 6: Commit**

```bash
git add labyrint-spill/src/shared/Progression.luau labyrint-spill/tests/Progression.spec.luau
git commit -m "feat(labyrint): Progression module (accepted/god/seed rules) + tests"
```

### Task 2: Persist `accepted` + `bestWithGod` with migration

**Files:**
- Modify: `src/server/MazeGame.server.luau` (loadPlayer defaults + load block + savePlayer)

**Interfaces:**
- Consumes: `Progression.seedAccepted` (Task 1).
- Produces: `d.accepted:number`, `d.bestWithGod:number` on every player's data table.

- [ ] **Step 1: Add `require` + defaults.** In `loadPlayer`'s default table add `accepted = 0, bestWithGod = 0`. Add `local Progression = require(ReplicatedStorage:WaitForChild("Progression"))` near the other requires.

- [ ] **Step 2: Load + migrate.** In the `if ok and typeof(saved) == "table"` block: `if typeof(saved.accepted)=="number" then d.accepted = saved.accepted end` and same for `bestWithGod`. After the block, if `d.accepted == 0` seed it: `d.accepted = Progression.seedAccepted(d.bestByLevel)` and `d.bestWithGod = math.max(d.bestWithGod, d.accepted, saved and saved.level or 0)`.

- [ ] **Step 3: Save.** Add `accepted = d.accepted, bestWithGod = d.bestWithGod,` to the `SetAsync` table in `savePlayer`.

- [ ] **Step 4: `rojo build`.** Expected: success.

- [ ] **Step 5: Commit** `feat(labyrint): persist accepted + bestWithGod with contiguous-best migration`.

### Task 3: Per-level `hadGod` tracking

**Files:**
- Modify: `src/server/MazeGame.server.luau` (STATE + buildLevel + SetGodMode handler)

**Interfaces:**
- Produces: module-level `local levelHadGod = false`, set true whenever any player enables god during the current level.

- [ ] **Step 1: Declare** `local levelHadGod = false` in the STATE section.
- [ ] **Step 2: Reset** it to `false` near the top of `buildLevel` (with the other per-build resets).
- [ ] **Step 3: Set on enable.** In the `SetGodMode` RemoteEvent handler, when god is turned ON for a verified GodUser, set `levelHadGod = true`.
- [ ] **Step 4: `rojo build`.** Commit `feat(labyrint): track god use per level (levelHadGod)`.

### Task 4: Use `Progression` at solve time

**Files:**
- Modify: `src/server/MazeGame.server.luau` (`onEscape` solve block; the advance loop)

**Interfaces:**
- Consumes: `Progression.resolveClear`, `levelHadGod`, `d.accepted`, `d.bestWithGod`.

- [ ] **Step 1:** In `onEscape`, before advancing, for the solving player compute
  `local res = Progression.resolveClear({ level = currentLevel, accepted = d.accepted, bestWithGod = d.bestWithGod, hadGod = levelHadGod or godActive[plr], mode = "group", isHostLevel = true })`. Set `d.accepted = res.newAccepted`, `d.bestWithGod = res.newBestWithGod`.
- [ ] **Step 2:** Gate the time-record write with `res.recordEligible` (replaces the current `not godActive[plr]` check; now also false if anyone used god this level).
- [ ] **Step 3:** In the advance loop, for each present player recompute their own `resolveClear` against `currentLevel` (so each earns their own accepted only if `currentLevel == their accepted+1` and no god) — this is what makes a low carried player earn nothing.
- [ ] **Step 4:** `rojo build`. Manual note: this changes credit semantics; document in commit body.
- [ ] **Step 5:** Commit `feat(labyrint): award accepted/records via Progression (carry- and god-proof)`.

### Task 5: Climbers leaderboard → `accepted` on `LabyrintTopp_v2`

**Files:**
- Modify: `src/server/MazeGame.server.luau` (topStore name; submitTopScore call sites)

- [ ] **Step 1:** Change `GetOrderedDataStore("LabyrintTopp_v1")` → `"LabyrintTopp_v2"` (clean board, no inflated data).
- [ ] **Step 2:** Change the advance-loop submit from `pd.level` to `pd.accepted`, and only submit when `res.acceptedGained` was true this clear and `not GodUsers.has(p)`.
- [ ] **Step 3:** `refreshLeaderboard`/`resolveName` unchanged (still highest-first).
- [ ] **Step 4:** `rojo build`. Commit `feat(labyrint): climbers board uses accepted on LabyrintTopp_v2`.

### Task 6: Surface `accepted` (+ Mio's god ledger)

**Files:**
- Modify: `src/server/MazeGame.server.luau` (sendLevelInfo payload), `src/client/LeaderboardClient.client.luau` or `HudClient.client.luau`

- [ ] **Step 1:** Add `accepted = d.accepted` and, for GodUsers, `bestWithGod = d.bestWithGod` to the `LevelInfo` payload.
- [ ] **Step 2:** Client shows "Accepted: N" (small, near the level field). For a GodUser, also "Clean N · God M".
- [ ] **Step 3:** `rojo build`. Commit `feat(labyrint): show accepted level + Mio god/clean ledger`.

### Task 7: Review + smoke + publish Phase 1

- [ ] **Step 1:** Capture the diff; dispatch adversarial reviewers (server progression/anti-cheat; client). Focus: sequential invariant, no accepted on carry, no leaderboard/record when god used, migration correctness.
- [ ] **Step 2:** Fix any confirmed findings.
- [ ] **Step 3:** `rojo build` green.
- [ ] **Step 4:** (User) Studio play-test: earn a level (accepted+1), confirm carry earns nothing, confirm a god run credits nothing.
- [ ] **Step 5:** Commit + push; run `publish_live.bat`; confirm `versionNumber`.

---

# PHASES 2–7 — the lobby + instance rewrite (roadmap; each expanded to full task detail when reached)

Each phase below is its own shippable increment and will get its own detailed
task breakdown (like Phase 1) immediately before it is built.

### Phase 2 — Modularize the server (no behavior change)
Extract from `MazeGame.server.luau`, keeping current behavior identical:
- `src/server/MazeBuilder.luau` — build a maze into a given `origin`+`level`, return the built pieces (grid, spawn, exit, coin/gem/button cells, monsters). Pure of globals.
- `src/server/RunController.luau` — the per-run loop (pickups, traps, monsters, exit unlock, timer, solve) operating on an instance table, not globals.
- Verify by `rojo build` + Studio smoke that the single-maze game still plays identically. Ship.

### Phase 3 — InstanceManager + lobby hub (single active instance)
- `src/server/LobbyService.luau` — build the hub (spawn pads, one door, lobby leaderboard SurfaceGui).
- `src/server/InstanceManager.luau` — create/assign/teardown one instance at an offset; teleport player in on door touch, back to lobby on solve/quit.
- Deliverable: spawn in lobby → walk through the (single) door → play your maze at `accepted+1` → return to lobby. Ship.

### Phase 4 — Solo door + level chooser
- `src/client/LobbyClient.client.luau` — Solo door UI: "Continue (level accepted+1)" or "Pick a level" (1…accepted+1 picker), send choice to server.
- Server: build the chosen level (reject > accepted+1). Ship.

### Phase 5 — Group matchmaking
- `src/server/Matchmaking.luau` — Group: find/open an instance at the player's `accepted`; multiple players climb in lockstep; each earns their own accepted. Handle a member leaving mid-level. Ship.

### Phase 6 — Play with Friends
- Friends door: host opens a private instance; friends in the server join (Roblox friends / same-party gate); host picks level ≤ host.accepted+1; carried friends earn nothing skipped (`Progression` already enforces this). Ship.

### Phase 7 — Lobby leaderboard + polish
- Lobby SurfaceGui board (climbers + records), door art/prompts, instance memory cap + empty-instance teardown timing, mobile polish. Ship.

---

## Self-review (plan vs spec)

- Spec §2 (accepted/bestWithGod/sequential/god rule) → Tasks 1–4. ✓
- Spec §3 (one server, instances, module split) → Phases 2–3 + roadmap module list. ✓
- Spec §4 (three doors) → Phases 4–6. ✓
- Spec §5 (god fairness) → Tasks 1,3,4 (rule) + Task 6 (ledger display). ✓
- Spec §6 (leaderboards, Topp_v2, lobby board) → Task 5 + Phase 7. ✓
- Spec §7 (migration seed) → Tasks 1–2. ✓
- Spec §8 (testing) → Task 1 tests + review/smoke throughout. ✓
- Spec §9 (rollout, live kept running) → Global Constraints + Task 7. ✓
- Placeholder scan: Phase 1 tasks contain real code; Phases 2–7 are an explicit roadmap to be expanded before build (not silent TBDs). ✓
- Type consistency: `resolveClear` result fields (`newAccepted`, `newBestWithGod`, `acceptedGained`, `recordEligible`, `leaderboardEligible`) used identically in Tasks 1,4,5. ✓
