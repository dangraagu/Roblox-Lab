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

## State (updated 2026-10-01) — live since 2026-09-06; the current tree is NOT published yet
- **Live:** universe `10544008743`, place `123669267191209` —
  https://www.roblox.com/games/123669267191209
  Made by repurposing the unused Private placeholder "Labyrinth Mariozo 1" (0 visits, updated
  22.7.2026 — verified empty before reuse), since Roblox web "Create Experience" only offers Studio.
- Audience **Public**, genre **Survival / Escape** (genre locked until Oct 4 2026),
  maturity **Mild — descriptor `Fear (Repeated/Mild)`**, **no region blocks**.
  Published via git-ignored `publish_anomaly.bat` (Open Cloud). The last publish on disk is
  `publish_response.json` = versionNumber 11, written 2026-09-10 11:06: it predates the night sky, the
  break, the Field Guide board, the saved run, the critters and the weather. Publishing is the night shift's job.
  The `labmario` Open Cloud key now covers all 4 universes (re-add ALL when editing it).
- **Gates (2026-10-01, pass 2): 12 specs, 978 assertions; 17 robloxemu checks** — all listed under "Gates" below,
  counts in `EYECANDY.md` §7. Only `luau.exe` is available: `luau-compile` / `luau-analyze` have not been
  run on the code added since 2026-09-23 (a syntax error still fails every gate, since they execute it).
- Adversarial review found **23 confirmed defects — all fixed** (2 critical: passSeed float
  overflow that pinned every modern player to ONE day-1 anomaly, and the session-lock stamp
  desync that silently dropped saves). Later reviews: 2026-09-24 (5 findings) and 2026-09-30 (7), all
  closed (`EYECANDY.md` §0b, §0c; re-measured closed 2026-10-01, §0g). The 2026-10-01 night (§0f) was
  mutation-tested the same morning (§0g: its 20 mutants, 18 killed, 2 near-equivalent survivors; controls survived)
  but has had no review. Pass 2 (2026-10-01, §0h) added every band's own weather and light against the standard;
  mutation-tested (§0h), not reviewed.
- **Visuals from the start:** Fx `Horror` preset + hall dust + camera shake/red flash on a wrong call.
- Nothing since the live version has been seen in Studio: `EYECANDY.md` §8 is the list.

## Core model / important invariants
- **Fresh-rebuild each pass**: server does `zone:ClearAllChildren()` + `buildClean()` before
  every roll, so anomaly appliers never need reset code and can't leave residue.
- **The hall's instance TREE never changes** (2026-09-30, review round 2 finding 1): everything an anomaly
  can add (the Figure, `Door2`, `Telescope2`, `Mirror2`, `Mist`) is built into EVERY hall, hidden (`hide`:
  Transparency 1, no collide / touch / query / shadow, the figure's eye light off), and removals are hidden
  in place. An applier only `show`s, `hide`s, moves or recolours. So no pass is answered by
  `FindFirstChild`: names, classes and parents are the same clean or not (`check_anomaly_names` forces all
  24 ids). A new anomaly that needs a new part must add a hidden spare to `buildClean`, never create one.
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
- **Leaderboard**: OrderedDataStore by best Day (`publishBest`), unchanged.
- **The saved run** (owner decision 2026-09-30): `prof.run = { id, day, pass }` is saved with the profile;
  a rejoin restores the Day AND the same hall (`beginPass(plr, restore)`); a wrong call starts a new run
  (new id, no pass) and is flushed at once; `retryClaim` lets a stored run that CHANGED meanwhile win over a
  read-only session's copy unless that session made its own wrong call (`ownRun`). The player's `SavesRun`
  attribute says whether this session saves (the break's idle caption depends on it).
  `check_anomaly_rejoin` is the gate.
- **The Field Guide board** (queued job A, 2026-09-30): its own OrderedDataStore `Config.Save.GuideStore`,
  value `Highscore.encode(types caught, reachedAt, 24)`, written (UpdateAsync, keep the larger) only when
  the count goes up; `prof.guide = { count, at, published }`. The sign `GuideBoard_<userId>` is NOT in the
  zone, sits outside the capture rig's and the hero shot's frames, and toggles public / friends with **L**.
  `check_anomaly_board` is the gate (since 2026-10-01 it also feeds a friend a fabricated value above the cap:
  the friends board reads with GetAsync, outside the public query's window). Details: `EYECANDY.md` §0e.
- **Spawn** (standard §1): `Spawn_<userId>`, a real, enabled, invisible SpawnLocation on the player's start
  pad, and `plr.RespawnLocation` set BEFORE `loadProfile` yields. `onCharacter`'s teleport stays as the
  second net. `EntranceGlass` (invisible, collidable) keeps players from walking off the open entrance.

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
Server `src/server/Main.server.luau` (buildClean + APPLIERS table + loop + DataStore + the board);
clients `src/client/Hud.client.luau`, `src/client/Sky.client.luau`; shared `Config/Rng/Anomaly/Progression/
Codex/Codes/Highscore.luau` and the sky's `NightSky/SkyArt/EnvBands/Rest.luau`; tests `tests/*.spec.luau`
(+ the test-side pacing model `tests/NightModel.luau`); the shot list `marketing/ShotList.luau`.

## Player actions never fail silently (2026-10-01, standard §1)
Every refusal a player can cause answers: a second code inside the 2 s Redeem cooldown ("One code at a
time: nothing was used..."), a pasted code over 64 characters ("Unknown code"), a hint with none left or away
from the pad, a locked tint (the HUD). A second tint tapped inside SetTint's 0.5 s cooldown is APPLIED when
the cooldown ends (one pending pick per player; the newest pick wins). H on a hall already hinted re-shows
the answer free (`ps.hinted`, reset every pass). `robloxemu/check_anomaly_walk.luau` walks the whole player
path (spawn, walk, answer, earn, spend, wrong call, leave, rejoin) and asserts all of this off the HUD.

## The night sky (2026-09-23) — full write-up in `EYECANDY.md`
Client-only sky that progresses with the Day (8 bands, moon phases) plus a "telescope break" rest.
`Sky.client.luau` (glue) + `SkyArt.luau` (Parts) + pure `NightSky.luau` / `EnvBands.luau` / `Rest.luau`
+ `Config.Sky`. (That round left Main.server.luau and Hud.client.luau alone; 2026-09-30 changed both, see
above.) Invariants a future edit
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
- **The break never calls the Day "safe"** (`NightSky.breakCaption`), and outside the idle warning promises
  nothing about keeping progress. After `Player.Idled` it says the Day and the hall are saved ONLY when
  `SavesRun` is true, otherwise that saving is off. Every template is pinned word for word in
  `NightSky.spec`: change the words there too, and read what they may promise first.
- **The shot list has ONE copy**: `marketing/ShotList.luau` (data and prose), played by
  `check_anomalyobservatory_shots`, printed for the night shift by `luau marketing/print_shotlist.luau`.
  Never copy the table into `EYECANDY.md`. A side of the frame may appear in its prose only through a
  measured `where`. Looking out of the entrance, Roblox's camera has +X on its LEFT.
- The break fires no remote, never re-rolls or delays a pass, and its camera provably looks away from
  every hall (`NightSky.minRayZ` > 0 for 32:9 at FOV 70). The sky gui never re-enables itself
  (the capture rig switches every ScreenGui off for a shot).
- **Moving things are checked on every frame** (`check_anomalyobservatory_events`: meteors, the bolt,
  the turning stars; event rates per band), and the emitter budget is enforced in code
  (`check_anomalyobservatory_cap` makes it bind). Both added 2026-09-24 when a resumed build's
  mutation sweep found four survivors (EYECANDY.md §0, §7). No hazards exist, by design.
- **The critters are the harmless rare events** (2026-10-01, EYECANDY.md §0f): each band has its own kinds
  (`fireflies`, `bats`, `owl`, `geese`, `wisps` are FEATURES) or a `critterless` reason (only the Storm
  Front), and `validate` refuses a band with neither. One flight per 45 s slot at most, Chance 0.3 x the
  kinds' weight (0.4 a minute at full weight); a flight fades with its band (`NightSky.critterAlpha`), so a
  band ending mid-flight never cuts it off. `check_anomalyobservatory_critters` proves the client flies
  exactly the pure schedule, slot by slot, in every band.
- **Every band has its own weather and its own light** (2026-10-01 pass 2, EYECANDY.md §0h; standard §2). Weather:
  `thistledown`, `snow`, `frost`, `leaves`, `motes` are FEATURES, each one ParticleEmitter on its own invisible
  host out in front of the entrance (`Config.Sky.Weather`; the storm's rain counts as weather); a band with none
  carries a `clearSky` reason (the Meteor Shower, Deep Sky) and `validate` refuses a band with neither, a kind that
  can drift back to the entrance (`NightSky.envelopes`: fall/rise, spread, the breeze along X only, a particle),
  or a direction other than Bottom/Top. SkyArt asks `NightSky.emitterRates` and caps it with `EnvBands.capRates`
  (Budget.MaxEmitters 3). Light: the hall must never change, so a band's light is the BREAK's colour grade
  (`light` on every band, `NightSky.breakLight`, worn by `ObservatoryBreakGrade` in `wearLight`, followed if the
  Day changes mid-break); no tint is red, all bands or none. `check_anomalyobservatory_weather` is the gate.
- Reviewed twice: 2026-09-24 (five findings, EYECANDY.md §0b) and 2026-09-30 (seven findings, §0c), all
  reproduced, failing-test-first, fixed and mutation-tested (§7). The owner decisions are DECIDED (§0d).
  Still open (§10): no third review of this round; nothing seen in Studio (§8 lists what needs it).

## Gates (run every one; all must be green)
Rebuild the bundle first: `cd robloxemu && py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau`.
The luau CLI is `luau.exe` under `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/` (not on PATH); append `2>&1`.
- From `anomaly-observatory/`: every `tests/*.spec.luau` (12: Anomaly, Codes, Codex, EnvBands, Highscore,
  NightSky, Pacing, Progression, Rest, Rng, SkyConfig, responsive).
- From `robloxemu/`: every `check_anomaly*.luau` (17): `check_anomaly` (HUD fit, overlap on), `_attrs`
  (the roll is true to the hall; its count varies run to run with the per-session salt), `_names`,
  `_rejoin`, `_board`, `_spawn`, `_walk` (the whole player path), and
  `check_anomalyobservatory_{sky,rest,hud,events,cap,occlusion,shots,news,critters,weather}`.
- A headless check that answers passes spends real seconds: `MIN_PASS_SECONDS` (0.75) is wall-clock. The
  whole list takes about 6.2 minutes run one after another (370 s summed in the final run of 2026-10-01 pass 2;
  the weather check 47 s); they are independent and can run in parallel.

## Traps this game has
- **R12**: the anomaly is a replicated, visible change; a script can diff properties. Never replicate a
  LABEL of the answer (an attribute, a name, a count of children): `check_anomaly_attrs` sweeps attributes,
  `check_anomaly_names` the tree.
- **Forcing an anomaly in a check**: moving the target to the front of the catalog with a one-entry pool
  keeps the catalog whole. Shrinking the catalog to one entry also shrinks `Anomaly.count` and what counts as
  a known type (the board's cap), which is how a board test once measured the wrong thing.
- **robloxemu leaves a new Light's `Enabled` nil**; Roblox's default is TRUE. Count `~= false` as lit.
- **robloxemu's HUD gate walks everything in PlayerGui as a screen panel**: a SurfaceGui for a world sign goes
  on the part, not in PlayerGui.
- **Every `os.clock()` window** (publish throttles, board caches, the remote cooldowns) is wall-clock: a check
  shortens the Config number in memory or waits real time; `task.delay` (the pending tint) is virtual time.
- **`EnvBands.hash01` is affine in each argument**: `slotEvent`'s u[3..6] are u[2] (the roll) shifted by a
  constant. Anything that must not follow the roll goes through NightSky's `jitter` first (the critters' kind
  and path do; used raw, one kind of an even pair took 41 % of the flights).
- **The per-session salt is 31 bits** and drives the visible roll, so a script could brute-force it from a few
  passes and predict the rest (fork-tower REVIEW-4's trap). Here that buys nothing R12 does not already give
  away (the answer is drawn in the hall by design); if a future feature ever hides something behind the roll,
  give it its own secret, as fork-tower did.
- **Luau's ambiguous call**: a statement that ends in `)` followed by a line that starts with `(` (for example
  `wearLight()` then `(grade :: ColorCorrectionEffect).Enabled = true`) does not compile; end the first with `;`.
  The specs never load the client scripts: only the robloxemu checks compile `Sky.client` / `Hud.client`, so a
  client edit is not tested until a check has run (pass 2 caught exactly this one).
- **Weather is measured off the emitter, not the Config**: `check_anomalyobservatory_weather` grows each host by
  the REAL emitter's speed, lifetime, spread and acceleration on every frame. An unset property in robloxemu
  reads nil; the check substitutes Roblox's defaults (Speed 5, Lifetime 5-10, Top), so always set them.
- **A flight, a meteor or a bolt is live**: the sky check leaves `^Critter_` out of its settled prints and its
  one-frame step rule, but not out of its pop rules.

## Next
1. The night shift: the Studio list (EYECANDY.md §8, items 1-35; 31-35 are the weather and the light), the thumbnails (`marketing/ShotList.luau`),
   the clips (`MARKETING.md`), then publish (`publish_anomaly.bat`; `git push` does not update the live game).
2. Real Badge asset ids for `Config.Milestones` + wire `awardMilestone` (currently a no-op stub; the standard
   does not require badges).
3. `tools/film_game.py` has no Anomaly scenarios; `MARKETING.md` specifies nine (tools belong to their owner).
4. Optional: gamepass (extra hints / cosmetic tints), more anomalies (pure data — append to
   `Config.Anomaly.Catalog` + add an `APPLIERS[id]`), ambient audio + jumpscare SFX polish.
