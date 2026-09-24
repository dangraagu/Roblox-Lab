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

## The pass is now visible from outside the server script (2026-09-10)
`beginPass` publishes the roll into **`ServerStorage.PassInfo.<userId>`** as the attributes
`Clean`, `AnomalyId` (nil when clean), `Serial` and `Zone`, written AFTER the applier block so the
missing-applier fallback is reflected. What it buys is a deterministic capture rig:
`tools/film_anomaly.py` shoots matched clean/anomaly pairs keyed by those attributes into
`marketing/pairs/`, and `robloxemu/check_anomaly_attrs.luau` asserts the attributes are true by
comparing them with the world rather than with the server's own table.

**ServerStorage, not the zone.** They were first written onto the zone model, which is parented to
`workspace` and therefore replicates, on the argument that it leaked nothing: the R12 note in the
same file records that the anomaly is a real replicated Instance a client can read, which is why
the Best-Day board is explicitly not a trustworthy ranking.

That argument is wrong in one decisive place, and it was caught before the build went live. **On a
clean pass there is nothing in the hall to read.** Finding the anomaly by inspecting the world
means proving a *negative* against a reference build you do not have; `Clean = true` hands that
answer over as a labelled boolean, and `AnomalyId` names the object so you need not look at all.
"A determined exploiter could derive it" and "every client is told it" are different costs, and
the looking *is* the game. `check_anomaly_attrs.luau` now sweeps `workspace` and
`ReplicatedStorage` for those attribute names and fails if any survive; restoring the old write
site turns up 149 of them across 60 halls.

## Files
Server `src/server/Main.server.luau` (buildClean + APPLIERS table + loop + DataStore);
client `src/client/Hud.client.luau`; shared `Config/Rng/Anomaly/Progression/Codex/Codes.luau`;
tests `tests/*.spec.luau`.

## The night sky (2026-09-23) — full write-up in `EYECANDY.md`
Client-only sky that progresses with the Day (8 bands, moon phases) plus a "telescope break" rest.
`Sky.client.luau` (glue) + `SkyArt.luau` (Parts) + pure `NightSky.luau` / `EnvBands.luau` / `Rest.luau`
+ `Config.Sky`. **Main.server.luau and Hud.client.luau were NOT touched.** Invariants a future edit
must keep (each is asserted; `NightSky.validate` switches the sky OFF with a warning if broken):
- **The hall never changes.** Every sky part and every moving thing stays beyond the entrance plane
  (hall-local z > +10 + `Clearance`), exact oriented corners, tested in `SkyConfig.spec` and measured
  on the real Parts in `check_anomalyobservatory_sky`. The shell is sealed except that +Z entrance,
  which is behind the spawn and behind `tools/film_anomaly.py`'s camera (z = +4 looking -Z). The rig
  pairs clean/anomaly frames from DIFFERENT Days, so nothing in its crop may depend on the Day at all.
- **Nothing reads the pass**, the sky is a function of `leaderstats.Day` and its own clock only
  (a clean and an anomalous pass of the same Day get an identical settled sky — measured).
- **No Lighting writes except during a break**, restored behind a black fade before the camera comes
  back, with ONE exception set once at start and never changed: a `Sky` (`ObservatorySkybox`) with
  `CelestialBodiesShown = false`, so Roblox's phaseless default moon cannot hang behind the phased one
  (the Mirror reflects the skybox, so it must never change after that). **No Light, no red**
  (`NightSky.isReddish`: "Red Shift" and "Blood Moon" are anomalies), nothing collidable/touchable.
- **Sizes the engine draws as written** (`NightSky.engineSizeOk`, enforced by `validate`): a `Ball` is
  uniform, a `Cylinder` round, no axis over 2048; a flattened sphere is an `Ellipsoid` (Block + Sphere
  `SpecialMesh`). robloxemu keeps any size, so this rule is the only thing standing between a green
  check and a sky Roblox draws differently.
- **On a phone the sky writes nothing over the hall that the player did not ask for** (a caption there
  lies on the right-hand wall; `check_anomalyobservatory_occlusion` walks the hall on 13 viewports); news
  waits for the break, the button's highlight is steady (never a blink: "The Flicker" is an anomaly).
- **The break never calls the Day "safe"** (`NightSky.breakCaption`): the streak lives only for the
  session and Roblox disconnects an idle player; after `Player.Idled` it says what the kick costs.
- **The shot list is data** in `check_anomalyobservatory_shots` and prose in `EYECANDY.md` §9: edit both
  or neither. Looking out of the entrance, Roblox's camera has +X on its LEFT.
- The break fires no remote, never re-rolls or delays a pass, and its camera provably looks away from
  every hall (`NightSky.minRayZ` > 0 for 32:9 at FOV 70). The sky gui never re-enables itself
  (the capture rig switches every ScreenGui off for a shot).
- **Moving things are checked on every frame** (`check_anomalyobservatory_events`: meteors, the bolt,
  the turning stars; event rates per band), and the emitter budget is enforced in code
  (`check_anomalyobservatory_cap` makes it bind). Both added 2026-09-24 when a resumed build's
  mutation sweep found four survivors (EYECANDY.md §0, §7). No hazards exist, by design.
- Reviewed once (2026-09-24): five findings, all reproduced, failing-test-first, fixed and
  mutation-tested (EYECANDY.md §0b, §7). Still open: the fixes have had no second review; nothing seen
  in Studio (EYECANDY.md §8 lists what needs it, §9 is the thumbnail shot list for the night session);
  owner decision on saving the streak across sessions (§10).

## Next
1. In-game test in Studio (walk passes; verify each anomaly id is spottable + cleared next
   pass; wrong call resets to Day 1; rejoin keeps bestDay + Field Guide + hints + tint).
2. Create the experience, upload, run questionnaire, go Public.
3. Real Badge asset ids for `Config.Milestones` + wire `awardMilestone` (currently a no-op stub).
4. Optional: gamepass (extra hints / cosmetic tints), more anomalies (pure data — append to
   `Config.Anomaly.Catalog` + add an `APPLIERS[id]`), ambient audio + jumpscare SFX polish.
