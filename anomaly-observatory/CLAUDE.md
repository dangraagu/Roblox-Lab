# CLAUDE.md — Anomaly: Night Shift at the Observatory (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/`; same stack (CONFIG-driven, deterministic Rng, DataStore w/ canSave +
soft session-lock, pure logic tested with the luau CLI). Built from Game-Radar #1 (2026-09-06).

## What it is
Spot-the-difference **anomaly horror**. A looping observatory concourse. Each PASS the server
rebuilds the hall CLEAN, rolls (`Anomaly.rollPass`), and if anomalous applies exactly ONE
spottable mutation. Player walks to the end → **ADVANCE** (E) if normal / **TURN BACK** (Q)
if wrong. Correct → Day+1 (hall loops). Wrong → night resets to Day 1. **No chase AI.**
Hint (H at start pad) spends a token to reveal clean/anomaly.

## State — built + tested + adversarial-reviewed + DEPLOYED PUBLIC (2026-09-06)
- **Live:** universe `10544008743`, place `123669267191209` —
  https://www.roblox.com/games/123669267191209
  Made by repurposing the unused Private placeholder "Labyrinth Mariozo 1" (0 visits, updated
  22.7.2026 — verified empty before reuse), since Roblox web "Create Experience" only offers Studio.
- Audience **Public**, genre **Survival / Escape** (genre locked until Oct 4 2026),
  maturity **Mild — descriptor `Fear (Repeated/Mild)`**, **no region blocks**.
  Published via git-ignored `publish_anomaly.bat` (Open Cloud), version 3.
  The `labmario` Open Cloud key now covers all 4 universes (re-add ALL when editing it).
- **119 luau-CLI tests pass** (Rng 32, Anomaly 29, Progression 22, Codex 26, Codes 10).
  luau-compile clean, luau-analyze clean (only Roblox type/global noise).
- Adversarial review found **23 confirmed defects — all fixed** (2 critical: passSeed float
  overflow that pinned every modern player to ONE day-1 anomaly, and the session-lock stamp
  desync that silently dropped saves). A second review, of the fix code itself, was still
  running at deploy time → fix forward if it reports anything.
- **Visuals from the start:** Fx `Horror` preset + hall dust + camera shake/red flash on a wrong call.
- Still NOT runtime-tested in Studio/Player (no engine here) — first real play may surface UX gaps.

## Core model / important invariants
- **Fresh-rebuild each pass**: server does `zone:ClearAllChildren()` + `buildClean()` before
  every roll, so anomaly appliers never need reset code and can't leave residue.
- **Server-authoritative**: ADVANCE/TURN_BACK/HINT are in-world ProximityPrompts whose
  `.Triggered` handler checks `who == plr`. Redeem/SetTint are RemoteEvents with type + range
  validation (SetTint only allows the default tint or the one the profile already owns).
- **Deterministic roll**: `Rng.new(passSeed(plr, serial))` where passSeed folds WorldSeed +
  userId + serial — reproducible + distinct per pass. Pure `Anomaly.rollPass` is unit-tested.
- **Re-entrancy guard**: `passState[plr].awaiting` — set true when a pass is live, false on
  the first choice; stray/duplicate prompt triggers and triggers during the death beat are ignored.
- **DataStore**: soft session-lock (load real data always via UpdateAsync; `canSave` only when
  we hold the lock; short TTL renewed by autosave). Code redeem is an **atomic UpdateAsync flush**
  (mark redeemed + grant in one write) so a crash can't dupe/lose it. All persisted keys are
  STRINGS or scalars (caught/redeemed are string sets) → no integer-key JSON round-trip trap.
- **Leaderboard**: OrderedDataStore by best Day (`publishBest`).

## Files
Server `src/server/Main.server.luau` (buildClean + APPLIERS table + loop + DataStore);
client `src/client/Hud.client.luau`; shared `Config/Rng/Anomaly/Progression/Codex/Codes.luau`;
tests `tests/*.spec.luau`.

## Next
1. In-game test in Studio (walk passes; verify each anomaly id is spottable + cleared next
   pass; wrong call resets to Day 1; rejoin keeps bestDay + Field Guide + hints + tint).
2. Create the experience, upload, run questionnaire, go Public.
3. Real Badge asset ids for `Config.Milestones` + wire `awardMilestone` (currently a no-op stub).
4. Optional: gamepass (extra hints / cosmetic tints), more anomalies (pure data — append to
   `Config.Anomaly.Catalog` + add an `APPLIERS[id]`), ambient audio + jumpscare SFX polish.
