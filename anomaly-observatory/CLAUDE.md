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

## State — v1 pure logic + server/client built + tested; adversarial review done; NOT deployed
- **73 luau-CLI tests pass** (Rng 10, Anomaly 20, Progression 22, Codex 11, Codes 10).
  luau-compile clean, luau-analyze clean (only Roblox type/global noise).
- No Roblox experience yet. Deploy = create experience → git-ignored `publish_*.bat` with
  Open Cloud key → questionnaire → Public (mirror the sibling games).

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
