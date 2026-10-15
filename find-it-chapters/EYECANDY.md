# Find It! Chapters: the rooms you see, the rare drops, the Pause

Built with the game (2026-10-07) from `DESIGN.md` §7-9 and §17-18, to `docs/complete-game-standard.md`. The +1 Jump
templates (`EnvBands.luau`, `Hazards.luau`, `Rest.luau` and their specs) are copied verbatim; every adaptation
lives in this game's config and glue and is listed in §10. **Nothing here has been rendered.** Every number below
is a headless measurement or arithmetic; what only Studio can judge is §8. All gates ran under `luaujs`, a Luau
runtime written for this session because the luau CLI was missing (`CLAUDE.md`, "The runtime").

## 0. The owner's standard, item by item

| standard | status | how, and which gate proves it |
|---|---|---|
| §1 core loop reachable from join | met | `tests/walk.luau` (44-60/0; one assertion per tapped prop): join, HubSpawn, a 5-stud walk, the Case Book prompt, Chapter 1 through the real HUD and Room client (taps at projected screen points, the client's own pick), Next on the card, Chapter 2 through a Pause and a re-dress. `check_finditchapters` (137/0): chapters 1-3, the Daily, the board, a death in a room, rejoin; `check_finditchapters_brag` (34/0): chapter 15 to BOOK ONE SOLVED on a phone, rejoin; `check_finditchapters_exit` (30/0): out of a live room in 1.5 s with the Leave button, Next while a clear saves (REVIEW-1 round 2 D1, D4) |
| §1 spawn per SPAWN-ORDER.md | met | HubSpawn is the one enabled SpawnLocation, built before PlayerAdded; RespawnLocation first in PlayerAdded; CharacterAdded writes no CFrame. `check_finditchapters` asserts the landing at join, after a death and at rejoin; mutants M7b, M8 (M7 is an equivalent mutant, §7) |
| §1 server-authoritative, nothing secret replicates | met | the secret is drawn after the payload is sent, lives in server memory, one copy in `ServerStorage.FindIt.Attempts`; no attribute writes anywhere (`check_finditchapters_compile`); payload key allowlists; `check_finditchapters_secret` (143/0): 8 predictors over 1330 finds at chance (all |z| <= 1.2), predictors from the pre-pause room at chance after a re-dress, planted leaks caught; mutants M3, M21 |
| §1 a seed a player could memorise | n/a, stronger | no seed exists: every draw is `life:NextInteger XOR Random.new():NextInteger` (fork-tower's mintSecret); mutant M21 (a public seed) is killed |
| §1 DataStore discipline | met | pcall everywhere; a session token on every write; canSave only with the lock; string keys `c1`..`c15`; a clear is ONE atomic UpdateAsync (stars, first clear, the Daily credit by the start day, Cases Solved); writes 6 s apart; nothing about an attempt saved. `check_finditchapters`, `check_finditchapters_cheat` (42/0: a read-only session and a stolen lock grant nothing), `Ledger.spec` (82/0); REVIEW-1 A1-A3: every clear is queued until a write carrying it lands, and every write folds the queue in (`check_finditchapters_save`, 49/0: a clear survives a leave or a shutdown inside the write gap, a failed write, a retrying load); round 2: the release's clear reaches the board too (`_release`, C1), a hopper is loaded within seconds and never thrown into Chapter 1 (`_hop`, C3), a late write never rolls the session back (`_race`, C4); mutants M6, M14, R1, R3, round 4 M1-M2, M9-M14 (`REVIEW-1.md`) |
| §1 no silent no-ops | met | every honest refusal has words (`Config.Text`); malformed payloads (only a script sends them) are dropped; a flood of refused calls gets a handful of answers (a bucket of 4, refilled 4/s: an honest HUD never empties it); Hub has its own bucket and a refused Hub has words (round 2 D4). `check_finditchapters_cheat`, `check_finditchapters_remotes` (33/0), `_exit`; mutants R6, round 4 M17 |
| §2 Fx preset + signature particles | met | `Fx.Presets.Agency` first thing on the server (= `Config.Env.Hub`, so the client's glide starts from it); the gold found-burst and the hint glint (emitters); a sparkle on the Case Book; FOV punch on a clear, flash + FOV on BOOK ONE SOLVED, shake + flash on a hit |
| §2 bands: >= 5, own light/colour/scenery/critters/weather, glided | met (headless) | 5 bands (§2); every critter and every weather emitter is INSIDE the room, where a closed room can show it (REVIEW-1 round 2 D2: the ship's fish and rain and the greenhouse drizzle used to be beyond the east wall): the fish swim in the portholes, the rain runs down them, lightning flashes in them, drizzle runs down the greenhouse's north glass, and no streak reaches the props' band. `Bands.spec` (278/0), `check_finditchapters_env` (361/0: all 15 chapters and a Daily through the real client; the ship's storm over 30 s); mutants round 4 M20-M24. Whether the porthole storm reads on a real screen: §8 item 26 |
| §2 hazards: rare, telegraphed, ring = hit zone, one at a time, cost little | met | §3; one per 85-120 s of exposed time (round 2 D5: re-measured with the game's own legal-spot rule); `Config.spec`, `Hazards.spec` (template, 111/0), `check_finditchapters_hazards` (51/0), `Pacing.spec` (51/0); mutants M9, M10, round 4 M28 |
| §2 rest / pause, never an exploit | met | §4; a break is capped at 10 minutes in all (round 2 C2: an unbounded pause carried a Daily's start-day credit across midnight); a live room has a Leave button (round 2 D1). `check_finditchapters_hazards`, `Attempt.spec` (120/0), `check_finditchapters_remotes` (A4: after a re-dress the next Pause waits 30 s of clock), `_midnight`, `_exit`, the walk; mutants M11, M16, R4, round 4 M5-M8, M15-M16 |
| §2 budgets measured and capped in code | met | §6; `check_finditchapters_env`, the walk; mutant M15 |
| §2 brag moment in 30-45 min, long-term goal | met (model) | BOOK ONE SOLVED p50 34.1 min (p10 31.2, p90 39.5) for the normal profile on the real rules; the Gold Book p50 114.3 min; the Gold Book (all 45 stars) and the Daily streak are on show in the Case Book, and the clear that earns the 45th star says GOLD BOOK (round 2 D6); the Daily titles (`tests/Pacing.spec.luau`, 51/0). Human times are assumptions; a sweeper gets there at 20.6. The moment itself is gated: `check_finditchapters_brag` (card, the dome slit SEEN to open: a ray from the eye meets the slit, then the night sky behind it (round 2 D3), 3 shooting stars none inside a wall, the server notice, the tag, the gold Case Book, the board, rejoin); mutants R17, R18, round 4 M25-M27, M29-M32 |
| §2 phone first, overlap = true | met | root Frame + UIScale sized 1/scale, 48 px touch targets, buttons in the thumb-free middle column, re-layout on ViewportSize and TouchEnabled; the topbar inset read from `GuiService:GetGuiInset` (REVIEW-1 B4); the Case Book list shows >= 3 whole rows on every viewport (B3). `check_finditchapters_hud` (36 px topbar) and `check_finditchapters_hud58` (58 px) PASS: 140 viewport x mode measurements each (14 modes, incl. the Leave button, a loading Case Book, the break card, the Gold Book card), 1860 controls contained, 0 spills, 30 Case Book menus with >= 3 rows; mutants M12, M20, R12-R15 |
| §3 public + friends board, un-inflatable metric, first-reach ties | met | Cases Solved (server-counted, calendar-capped), OrderedDataStore `FindIt_Solved_v1`, `u_<userId>`, `solved*2e9+(2e9-reachedAt)`, keep-max, written after the profile lands and only on a rise (and after a release write: round 2 C1); public top 10 cached 60 s; friends on demand, capped 200, cached 300 s, single-flight, one budget-checked read at a time; names cached in memory only. **reachedAt is the start of the UTC day the count rose** (round 2 C2; round 1 A5 had done so for a Daily only): the same count reached the same day ties (a shared rank), an earlier day always ranks first, no race at 00:00:20. `Board.spec` (78/0), `Ledger.spec` (94/0), `check_finditchapters_board` (23/0), `_midnight` (35/0), `check_finditchapters` (the board renders); mutants M13, round 4 M3-M4 |
| §3 no Robux, no gambling | met | nothing sold, no codes, no MarketplaceService call in `src/` |
| §4 README store text <= 1000 chars | met | 897 characters, ASCII, no emoji (`README.md`) |
| §4 EYECANDY.md: needs-Studio list + thumbnail shot list | met | §8, §9 |
| §4 clip list | met | `MARKETING.md`, 8 clips |
| §4 CLAUDE.md: every gate + traps | met | `CLAUDE.md` |
| §4 every gate green, TDD, mutation-tested with a control | met, with a caveat | 33 gates green (§7, `CLAUDE.md`); rounds 1-2: 24 mutants, 23 killed, 1 equivalent; round 3 (REVIEW-1 round 1 fixes): 17 of 17; round 4 (round 2 fixes, `REVIEW-1.md`): see there; the controls survived every round; `luau-analyze`/`luau-compile` not on this machine; every gate ran under `luaujs`, not the luau CLI |
| §5 night shift (Studio, publish, marketing) | not done, by rule | Studio only 00:00-06:00; §8 is its list |

---

## 1. What is where

| file | what |
|---|---|
| `src/shared/EnvBands.luau`, `Hazards.luau`, `Rest.luau`, `Responsive.luau`, `FxClient.luau` | templates, **verbatim** from `plus1-jump/src/shared` (md5 c6fc63a1, f36a9ac2, 19226cb6, 8cf3ba92, 92d83a20); specs verbatim (e2a9d464, 2f42278c, 4c38d41f, 2b51033c) |
| `src/shared/Rng.luau` | fork-tower's / escape-room-lab's (with `below`), verbatim (54635d1d), spec verbatim (35a8be6c) |
| `src/shared/Board.luau` | escape-room-lab's (plus1-jump's plus three review fixes); rows carry `solved` (§10) |
| `src/shared/Fx.luau` | plus1-jump's plus one preset, `Fx.Presets.Agency` (§10) |
| `src/shared/RoomArt.luau` | every look as data: the 8 prop silhouettes, decor per band, critters and their paths, weather styles, hazard models, items, lamp spots, the part count |
| `src/shared/Bands.luau` | which band a room is in; `Bands.validate` (the colour rules, decor placement) |
| `src/client/Room.client.luau` | the room build, taps, the band glide, decor, critters, weather, lamps, drops and the ring, the Pause through `Rest` |
| `src/client/Hud.client.luau` | the phone-first HUD |

## 2. The bands and what triggers them

The trigger is the chapter you are in: progress = chapter, `from` = 0, 4, 7, 10, 13, fade 0. A Daily Case uses
its theme's band (`(dayIndex - 20733) mod 5 + 1`). In the hub the target is `Config.Env.Hub` (= `Fx.Presets.Agency`).
Entering a room glides every Lighting, Atmosphere, Bloom, ColorCorrection and Sky value toward the band at a
0.8 s half-life (`EnvBands.approachTable`), written at most 10 times a second (measured: 30 writing frames in
3 s at 30 fps). The light changes only on entering a room and on a clear, so it never moves during a search
(`check_finditchapters_env`: 0 Lighting writes during a search once settled). Clearing a band's last chapter
moves progress to the next band's start while you stand in the room: the reward (measured: chapter 12's ship's
cabin glides to the observatory's ClockTime within 6 s of the clear).

| # | band | chapters | light (ClockTime, tint) | scenery | critters | weather | hazard | minutes in it, normal p50 |
|---|---|---|---|---|---|---|---|---|
| 1 | Sunny Cottage | 1-3 | 9.0, warm white | window with curtains, rag rug, herbs on the sill, cuckoo clock | a cat asleep on a ledge, 2 butterflies | dust motes | pinecone | 3.0 |
| 2 | Old Library | 4-6 | 16.5, amber | book spines high on the walls, a rolling ladder, a globe, a book stack | 3 moths circling the lamps | floating dust | book | 5.0 |
| 3 | Greenhouse | 7-9 | 17.6, green-gold | corner ferns, hanging vines, a watering can, glass roof frames | 3 butterflies, a frog on a ledge | mist; drizzle running down the north glass, high up | flowerpot | 6.8 |
| 4 | Ship's Cabin | 10-12 | 21.5, lantern on blue | ropes, corner barrels, a hammock, 4 portholes (a night-sea view, glass, a brass rim) | a parrot on a ledge, 2 fish swimming in the portholes | a storm: rain running down the portholes, lightning flashing in them (one every 6-11 s) | crate | 8.5 |
| 5 | Star Observatory | 13-15 | 0.5, violet night | a telescope, star charts, a hanging orrery, the dome (its slit opens on BOOK ONE SOLVED onto a glowing strip of night sky) | 4 drifting star-motes | twinkles | meteorite pebble | 9.9 |

Colour rules, measured by `Bands.validate` (`Bands.spec`): the nearest non-prop colour to the ring's red is 105
RGB away (the flowerpot hazard), the nearest to the find gold 112 (the ship's lamp), rule 90; the two closest
clue colours under any band's light are 123 apart (white and yellow in the library), rule 70; the lightning flash
is a checked colour too. **Everything a band shows is inside the room** (REVIEW-1 round 2 D2): a room is a closed
box (the opaque lane shell and ceiling, the client's screens), so the fish and the rain that used to be beyond the
east wall, and the greenhouse drizzle, were never seen, and the Sky's stars cannot be seen in any room. Now the
fish swim and the rain runs in each porthole's 0.3-stud window box (between its night-sea view and its glass),
the drizzle runs down the inside of the greenhouse's north glass at y 12-14, and no streak falls below y 10.5
(the props' band: `Bands.spec`, and `check_finditchapters_env` reading each live emitter's speed, life and pull),
so no weather ever crosses or tints a clue colour. A lightning flash lights the four porthole views only (Neon,
0.12 s): `check_finditchapters_env` measured 3-4 flashes in 30 s (two runs), the views lit on 10-16 of 900 frames, and the Lighting
(clock, brightness, exposure, ambient) the same on every frame.

## 3. Hazards and their measured rarity

A drop from the ceiling: `Hazards.luau` verbatim under escape-room-lab's reviewed indoor config (pitch 85, commit
= telegraph, speed 4, telegraph 3.0 s, pass 0.6 s, a 7-stud ring). The clock runs on **exposed** time only: a live
attempt, past the 5 s arrival grace, on a legal spot (the room shrunk by 4 studs, more than 4 studs from the door
mat); anywhere else the glue passes `resting = true`, so a due drop is never held and fired later (escape-room-lab
REVIEW-1 B4). One per 85-120 s of exposed time; never two at once; the clock is never reset.

REVIEW-1 round 2 D5: the pacing model had counted every second past the grace as exposed; the game counts only
the seconds on a legal spot (86% of them for the normal profile). With the game's rule in `FinderModel` the old
100-140 s gave one near-miss per 3.13-3.17 minutes, outside the standard's 2-3; 85-120 s gives 2.69 (500 careers;
`Pacing.spec` asserts the 1000-career median in [2, 3]). Headless through the real client over 1200 s on a legal
spot: 10 drops, one per 111 s of exposure, intervals 85.9-115.9 s; standing still was hit 5 of 5 times, a 5-stud
step 1 s after the ring showed 0 of 5; the ring matched the hit zone 10 of 10 times.

Measured (`tests/Pacing.spec.luau`, normal profile, 1000 careers to BOOK ONE SOLVED): 15 drops on the way (p50),
one per 2.28 minutes of play, one near-miss (dodged) per 2.70 minutes. Through the real client (`check_finditchapters_hazards`): the first drop comes after the 5 s grace
plus 85-120 s of exposed time; the ring is centred on
`Hazards.zone`, at the player's feet, 7 studs across, red; standing still is a hit 2.15 s after the ring showed
(arrival at 3.0 s), a 0.6 s stumble that takes no look
and no item; one 4-stud step the moment the ring shows is a dodge; 150 s on the door mat brings nothing and the
hazard clock does not move; a finished room and the intro card run no hazard clock.

## 4. The Pause (what "pause" means here)

The Pause button goes through `Rest.request` (`IdleSeconds = 0`: standing still is how a room is read). It cannot
start mid-air or with a drop on its way: it is queued (`Pausing after the drop...`) and the drop still comes
(measured). When it starts, the client sends Pause and the server stops the chapter clock and refuses searches
and hints; the card says `Paused. The clock is stopped. While you rest, things get moved around.` A move (or
Resume) wakes it; the server applies the Resume no sooner than 3 s after the Pause and **re-dresses the room**:
every prop moves to new ids, every unfound item gets a fresh clue that fits exactly as many props as it had
unsearched candidates, and a fresh hiding spot; found items stay found, the looks never change, a hinted item's
count is 1 so its prop sparkles again. After a re-dress the next Pause waits for 30 s of attempt clock (`Config.Pause.EverySeconds`; REVIEW-1 A4: back-to-back
pauses were a free re-roll of the unfound part of the room); the button says `You can pause again in N s` and the
server refuses it too. Why it is not an exploit: the hazard clock freezes and is never reset;
everything studied while paused is replaced (predictors from the pre-pause room are at chance in the re-dressed
room: `check_finditchapters_secret`); the looks are never refilled. The design model measured a tap-everything
player who pauses to refill solving LESS often than one who never pauses (DESIGN.md §9).

**The break is capped** (REVIEW-1 round 2 C2): an unbounded pause let a Daily opened at 23:58 be solved the next
morning on its start day's credit. Paused time is summed over the attempt on the server's frame clock; at
`Config.Pause.MaxBreakSeconds` (600) the room closes (`BREAK OVER`, Retry or Hub; nothing earned, nothing saved).
The paused card counts down what is left. `check_finditchapters_midnight` measured the close 600 s into a pause,
and a Resume the next morning does not reopen it. A long break belongs in the hub, where nothing runs a clock.

**A live room has its own way out** (round 2 D1): after a Resume the next Pause waits 30 s of clock (A4), and the
paused card's Hub was the only exit, so leaving took ~30 s. The Leave button (top row, left of Pause) leaves on a
second tap within 3 s; the first says what leaving costs. `check_finditchapters_exit`: in the hub 1.5 s after the
arming tap; one tap alone never leaves. Leaving abandons the attempt: no re-roll of anything, since a room opened
again starts from scratch.

## 5. Client vs server

The server owns the attempt: the room, the secret, the looks, the clock (a Heartbeat sum), the answers, the stars,
the save. The owner's client builds its own room from the payload (other players never receive it) and owns
everything cosmetic: the bands, decor, critters, weather, drops and the Pause's rest state. A drop can only touch
its own player's character, whose physics that client owns, so the server never hears of one; a cheater who
deletes drops saves the stumbles a careful player never takes. The Pause is server-side where it matters (the
clock, searches, the re-dress) and client-side where it is cosmetic (the dim, the hazard clock).

## 6. Budgets (measured, capped in code)

| budget | cap | measured |
|---|---|---|
| local parts in a room | 280 (`localPart` refuses past it; 8 reserved for the drop and its ring) | 70 (chapter 1) to 162-170 (the ship, chapters 10-12) and 160-163 (the observatory) through the real client (2026-10-08); 204 for the worst of 300 generated chapter-15 rooms counted with `RoomArt.roomParts` (+8 reserve = 212) |
| lights | 4 (`localLight`) | 4 (the lamps) |
| emitters | 4 (`localEmitter`) | 2 in a fresh room (the weather hosts); the found burst and the hint glint are made on first use, 4 at most |
| weather | 2 emitters, 60 particles/s (`EnvBands.capRates`) | 1-2 emitters on, 5-30 particles/s (cottage 5, library 6, greenhouse 13 on 2, ship 30, observatory 8) |
| critters | 6 at once | 3-4 per band (3-8 parts) |
| decor parts | 40 per room | 9-20 (the ship's 4 portholes are 12: view, glass, rim) |
| hub | 160 server parts | 13 |
| a lane shell | 9 server parts | 8 (12 lanes) |

A room is torn down before the next is built (the walk asserts 0 refusals and only the current room's screens and
lamps standing; the first walk found rooms piling up to 191 parts because a `typeof(p) == "Instance"` guard is
always false in the emulator, where instances are tables; the guard is gone).

## 7. Gates and the mutation sweep

The gate list with commands and counts is in `CLAUDE.md`. The mutation sweep is below.

Before REVIEW-1: all 23 gates, two full runs in a row, 46 of 46 green; the random-dependent ones four more times,
28 of 28. After the REVIEW-1 fixes (28 gates): see `CLAUDE.md` for the final runs; the random-dependent ones (the
walk, the main check, env, hazards, secret, cheat, board, remotes, save, brag) three more times in a row: 30 of 30.

**Mutation sweep** (`.../scratchpad/fic_mutate.py`): each mutant is applied to a pristine scratch copy of the game
(never to `D:/Claude/Roblox`), its file's md5 is recorded before and after, the bundle is rebuilt from the copy,
and every gate runs (Pacing too when the mutant touches Config); a gate that dies before its summary counts as a
kill. Round 1: 21 mutants + the control. Round 2 (after round 1's survivors got assertions, and after the last
fixes): M7b, M9, M12, M22, M23 + the control again.

| # | mutation | result | killed by |
|---|---|---|---|
| M1 | ids dealt in generation order (no shuffle) | KILLED | Dressing.spec |
| M2 | a hit answered at once (the timing tells) | KILLED | Attempt.spec |
| M3 | the State payload carries the next hidden prop (key `tip`) | KILLED | check_finditchapters_secret (allowlist) |
| M4 | no server reach check | KILLED | check_finditchapters, _cheat |
| M5 | a search spends no look | KILLED | Attempt.spec, check_finditchapters, _cheat |
| M6 | the Daily credits every solve | KILLED | Ledger.spec, check_finditchapters |
| M7 | CharacterAdded writes a CFrame into lane 1 | **SURVIVED: equivalent** | the engine's spawn step overwrites the write (SPAWN-ORDER.md), so nothing changes: the trap's danger is a game that RELIES on such a write. M7b is that game |
| M7b | CharacterAdded waits for the parent, then moves the character into lane 1 | KILLED | walk, check_finditchapters |
| M8 | RespawnLocation never set | KILLED | check_finditchapters |
| M9 | the drop aimed from the camera's pitch | survived round 1; KILLED round 2 | check_finditchapters_hazards (new: the drop starts 11.95 studs above the player, 1.03 to the side) |
| M10 | the hazard clock runs on the door mat | KILLED | check_finditchapters_hazards |
| M11 | idle rest on (IdleSeconds 20) | KILLED | Config.spec, _env, _hazards |
| M12 | no re-layout on ViewportSize | survived round 1; KILLED round 2 | check_finditchapters_env (new: a rotation alone re-lays-out the HUD; hudcheck's mode hooks push state, which re-lays-out anyway, so they could not see it) |
| M13 | the board written without a rise | KILLED | check_finditchapters_board |
| M14 | a locked session grants anyway | KILLED | check_finditchapters_cheat |
| M15 | a room never torn down | KILLED | walk, _env |
| M16 | Resume does not re-dress | KILLED | Attempt.spec, walk, _secret, _cheat |
| M17 | the library band starts at chapter 5 | KILLED | Bands.spec, check_finditchapters |
| M18 | a table never blocks a tap | KILLED | Pick.spec |
| M19 | searches accepted on the intro card | KILLED | Attempt.spec, check_finditchapters |
| M20 | touch targets shrink to 40 px | KILLED | check_finditchapters_hud |
| M21 | the secret drawn from a seed a client knows | KILLED | check_finditchapters_secret (predictors) |
| M22 | a re-dress leaves found items floating | KILLED | check_finditchapters_env |
| M23 | the Case Book never turns gold | KILLED | check_finditchapters_env |
| CONTROL | the hub sign reads THE FINDERS AGENCY (no gate reads it) | **SURVIVED all 23 gates, both rounds** | the sweep can produce a SURVIVED, so the kills are not a broken harness |

24 behavioural mutants: 23 killed, 1 survived as an equivalent mutant (M7, explained).

**Round 3** (2026-10-07 evening: the REVIEW-1 fixes and this session's; `.../scratchpad/fic_mutate3.py`, the same
method, every one of the 28 gates of `fic_gates3.sh`):

| # | mutation | result | killed by |
|---|---|---|---|
| R1 | A1: the release write does not fold the clear queue | KILLED | check_finditchapters_save |
| R3 | A3: the load does not merge clears made while it retried | survived pass 1 (a later autosave carried the clear before the check looked); the check now looks the moment the load lands; KILLED pass 2 | check_finditchapters_save |
| R4 | A4: a pause is accepted right after a re-dress | KILLED | Attempt.spec, check_finditchapters_hazards, _remotes |
| R5 | A5: a Daily is reached at its second, not its day | KILLED | Ledger.spec, check_finditchapters, _save |
| R6 | A6: every refusal of a flood is answered | KILLED | check_finditchapters_remotes |
| R7 | B1: the lectern prompt eats the Open bucket | KILLED | check_finditchapters_remotes |
| R8 | B2: HubSpawn faces the back wall | KILLED | check_finditchapters |
| R9 | B7: the Daily door faces the east wall | KILLED | check_finditchapters |
| R10 | B9: 6-stud hub walls | KILLED | check_finditchapters |
| R11 | B5: streaming left on | KILLED | tests/project_check.py |
| R12 | B3: the Case Book never runs the middle column | KILLED | check_finditchapters_hud, _hud58 |
| R13 | B4: the HUD assumes a 36 px topbar | KILLED | check_finditchapters_hud58 |
| R14 | the selection bar never goes one-row | KILLED | check_finditchapters_hud58 |
| R15 | the banner stays under the top row beside a tall menu | KILLED | check_finditchapters_hud, _hud58 |
| R16 | rain from a 30-stud host half over the room | KILLED | check_finditchapters_env |
| R17 | no shooting stars on BOOK ONE SOLVED | KILLED | check_finditchapters_brag |
| R18 | the server never tells others about BOOK ONE SOLVED | KILLED | check_finditchapters_brag |
| CONTROL | the hub sign reads THE FINDERS AGENCY | **SURVIVED both passes** | |

Round 3: 17 behavioural mutants, 17 killed (R3 after its assertion was tightened). Not mutated: the headless pick's
topbar read in `Room.client` (the emulator's inset is 36 and the walk taps at 36, so a fixed 36 is equivalent
headless; the real engine takes the `ScreenPointToRay` path).

**Round 4** (2026-10-08, the REVIEW-1 round 2 fixes C1-C4 and D1-D6; `.../scratchpad/fic_mutate4.py`, the same
method over all 33 gates of `fic_gates4.sh`, three workers on separate scratch copies): the table is in
`REVIEW-1.md`.

## 8. Needs Studio (only real rendering, input, devices or a live server can settle these)

1. **Tap-to-select on a phone:** picking a jar on a high shelf from 10 studs; the white outline and the label
   readable; dragging to turn the camera never selects (`Pick.isTap`: under 12 px and 0.5 s).
2. **The ray:** `Camera:ScreenPointToRay` against `InputObject.Position` (the headless pick adds the 36 px topbar
   inset to reach viewport coordinates); confirm the prop under the finger is the prop picked.
3. **The 8 silhouettes** told apart at 15+ studs on a phone; FLOOR / TABLE / HIGH clear from eye level under a
   16-stud ceiling (props on shelves at y 8, tables at 3).
4. **The four clue colours under every band's light**, including a colour-blind simulation; the label chip
   (`BLUE BOX · HIGH`) and the swatch letters as the fallback.
5. **The HUD row of 9 chips** on a notch phone (two rows on a portrait phone); the callout; 48 px targets; the
   selection bar clear of the thumbstick and jump button.
6. **Drops indoors:** the ring readable on rugs and clutter; the wobble overhead visible; the 0.6 s stumble's feel.
7. **Pause:** the dim (a depth-of-field effect) and whether the re-dress reads as "things moved", not a glitch.
8. **Search feel:** the 1.0 s wait, the gold burst (`ParticleEmitter:Emit`, not modelled headless), the item
   popping out of the prop.
9. **Frame time** on a low-end phone at 280 local parts, 4 lights and 4 emitters.
10. **Payload latency:** a 64-prop Room payload on 4G; how long the room takes to appear.
11. **Client-built rooms:** tables and screens collide; props do not (by design: no snagging); the screens hold.
12. **The move into a lane** (`Model:PivotTo`): no fall, no camera snap.
13. **Desktop:** click to select, click again or E to search.
14. **The board's** SurfaceGui legible from the spawn (about 20 studs); the Friends/Public prompt; the friends
    face drawn on the part for the presser only.
15. **BOOK ONE SOLVED:** the dome slit (now under the disc) fading onto the glowing strip of night sky behind it,
    seen from the floor; three gold shooting stars under the dome; the flash and FOV punch, the server notice, the
    gold name tag.
16. `Random:NextInteger(0, 4294967295)` and `bit32.bxor` on values of 2^31 and above in the real engine.
17. `GetFriendsAsync` paging on a real account; the friends fill time under the real request budget.
18. The 00:00 UTC rollover in a live server (the Daily credit goes by the day the attempt started; the board stamp
    by the day it was solved; `check_finditchapters_midnight` crosses a faked midnight headless).
19. Place settings: MaxPlayers 12.
20. The Studio shot room (`Config.Studio.ShotSeed`, `Config.Studio.Cleared`) with API access off: deterministic
    rooms, chapters unlocked, nothing saved.
23. **The topbar:** `GuiService:GetGuiInset()` on the current topbar (58 px expected) and the HUD placed under it;
    headless runs both 36 and 58, but the emulator scales the inset by the root's UIScale (it reports a scaled HUD
    up to 23 px higher than Roblox draws it), so the bottom edge on a small phone is Studio's to confirm.
24. **The Case Book on a phone:** the menu runs the full height of the middle column (>= 3 rows of 48 px at 640x300
    under a 58 px topbar); a locked row's words show in the left column beside it.
25. **The one-row selection bar** (label left of Search) on a short phone screen: the label stays readable.
26. **The ship's storm** (replaces "rain outside", REVIEW-1 round 2 D2): the rain (0.12-stud particles at 15/s per
    porthole) and the fish (0.7 studs) in each porthole's window box, behind glass at Transparency 0.6, 12 studs up:
    do they read from the floor on a phone? Does a particle behind transparent glass draw? The lightning flash
    (the four views Neon for 0.12 s) under the band's bloom. The drizzle on the greenhouse's north glass.
21. The critters' paths (`RoomArt.critterPos`) look alive and stay above the props; the fish read as swimming past
    a porthole (not floating in front of a wall).
27. **The Leave button** (top row, left of Pause, "Leave" / "Leave?") on a notch phone: tappable, not confused with
    Pause.
28. **A server hop** in a live game: how often the old server's lock is still held at join (the 6 s per-key write
    throttle), and that the hopper's load lands within the 3 s quick retries (`check_finditchapters_hop` measured
    1.0 s after the lock was freed, headless).
29. **The break cap:** the paused card's countdown ("stays open 9:59 more"), and the BREAK OVER card after 10 minutes.
30. **The Gold Book:** the Case Book title's star count (`THE CASE BOOK * 30/45`) and the Daily row's streak legible
    in the menu on a phone; the GOLD BOOK card.
22. The decor reads as each band's place and never as a prop (it never uses a prop kind's silhouette; corner
    pieces, wall pieces above y 10.5, flat rugs).

## 9. Thumbnail shot list (1920 x 1080, subject inside the middle 1280 px)

Shots use the Studio shot room: only when `RunService:IsStudio()` is true and saving is off, `Config.Studio.ShotSeed`
makes the dressing and the secret repeatable and `Config.Studio.Cleared` unlocks chapters. Nothing is saved or
ranked there. Room-local coordinates: the door mat's centre is (0, 0, 0), the room runs +z; lane 1's origin is
(-385, 0, -240).

1. **Hero, Ship's Cabin** (Cleared 10, chapter 11): over the shoulder at lantern height, camera at (6, 7, 6)
   looking at (-2, 3, 18); a chest on a table mid-burst, a compass popping out; a porthole behind with rain running
   down it, caught mid lightning flash (one every 6-11 s); HUD hidden.
2. **Library shelves** (Cleared 4, chapter 5): low angle up the west wall, camera at (-12, 2, 10) looking at
   (-23, 9, 16); a yellow jar on a shelf mid-burst, a gold item in the air.
3. **BOOK ONE SOLVED** (Cleared 14, chapter 15, solved in the shot room): inside the observatory, camera at
   (0, 6, 4) looking at (0, 15, 11): the dome slit (y 15.0-15.2, under the disc) opening onto the glowing night-sky
   strip, shooting stars under the dome, the avatar's back to camera.
4. **The ring** (Cleared 7, chapter 8): the greenhouse at sunset, camera at (8, 9, 8) looking at the avatar on a
   legal spot; the red ring at the feet, the flowerpot wobbling overhead (wait for a natural drop: 90-125 s on a
   legal spot).
5. **The hub:** the Case Book on its lectern at (0, 3.9, 8), the board at (-18, 5.5, 10) behind, the Daily door,
   three avatars; camera at (10, 6, 26) looking at (-4, 4, 6).

## 10. The templates, and every adaptation (with its reason)

- `EnvBands`, `Hazards`, `Rest`, `Responsive`, `FxClient`, `Rng`: verbatim. The adaptations are config and glue:
  bands with `fade = 0` (the light must not move during a search), the indoor hazard config (pitch 85, commit =
  telegraph), `Rest.IdleSeconds = 0`, the hazard clock frozen off legal spots.
- **The Pause deviates from `Rest.luau`'s advice on purpose** (its header says not to map rest onto a clock players
  race). Here the frozen time buys nothing: the room is re-dressed on resume (DESIGN.md §9, measured in §4).
- `Board`: escape-room-lab's file (it fixed three defects plus1-jump's has: 0 stored as 0, the reach time clamped,
  friend reads paced by the request budget); rows carry `solved`.
- `Fx`: one preset added, `Agency` (warm daylight). DESIGN.md §6 named `Cozy`, which is a night cavern
  (ClockTime 0, teal); the checklist says to add a preset rather than hand-roll Lighting.
- Decor: the greenhouse's "pots" set is glass roof frames (a pot is a searchable kind's silhouette); the floor
  corners (3.6 studs) are kept for decor, so no prop or table enters them.

## 11. Open

- Everything in §8: nothing has been rendered, tapped on a device, or run in a live server.
- The pacing is a model of people; the first play sessions replace its assumptions (DESIGN.md §10.1).
- The Daily's credit by the START day and the board stamp by the day solved are tested in `Ledger.spec` and across
  a faked midnight in `check_finditchapters_midnight`; a live server's real midnight is §8 item 18.
- The telescope "swinging up" on BOOK ONE SOLVED (DESIGN.md §10.2) is not built; the dome, the stars, the flash,
  the notice, the tag and the gold book are.
- `luau-analyze` and `luau-compile` were not available; all gates ran under `luaujs` (`CLAUDE.md`).
- robloxemu (not ours) resolves a scaled HUD's topbar inset as `inset * scale` (`Harness.guiRects`), so it is up to
  `inset * (1 - scale)` px lenient at the bottom edge of a phone. The HUD's own geometry places everything above
  `H - 8` of the real usable height; the night shift confirms on a device (§8 item 23).
