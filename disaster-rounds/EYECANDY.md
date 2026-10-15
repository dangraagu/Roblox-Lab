# Disaster Rounds - the sky you survive into

Owner's standard (`docs/complete-game-standard.md` §2, 2026-09-17 and 2026-09-30): the environment changes with the
player's own progress so it never feels monotonous; rare, telegraphed hazards whose red ring is exactly where a hit
can land; a rest that is never an exploit; budgets measured and capped in code; a brag moment within about 30-45
minutes; a needs-Studio list and a thumbnail shot list. Model document: `plus1-jump/EYECANDY.md`.

**State (2026-10-07): built with the game from its first build, headless-tested, mutation-tested with a control.
Never opened in Studio, never seen on a screen, not published, not independently reviewed.** Every number below
marked *measured* was printed by a gate in this repo (§7). There is no luau CLI on this machine: the gates ran under
a Luau-to-LuaJIT shim (`CLAUDE.md` "Running the gates"), so they are measurements of the same code on a different
VM. Nothing here has been judged by eye; that is §8.

---

## 1. What is where

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, byte-identical to `plus1-jump/src/shared/EnvBands.luau`** (sha256 `42d148b64af3376c...`): progress value -> band + eased blend, the disaster overlay, frame-rate-independent smoothing, the announcer, `capRates`. Pure. |
| `src/shared/Hazards.luau` | **template, byte-identical** (`bd470578ce83da9b...`): the Lookout strays. Pure. |
| `src/shared/Rest.luau` | **template, byte-identical** (`450440980871991c...`): manual + idle rest, queued while a stray is inbound, wake on move, freezes the stray clock. Pure. |
| `src/shared/Fx.luau` | the shared kit plus ONE new preset, `Coast` (= band 1's light, so the server's first frame is already band 1). |
| `src/shared/FxClient.luau`, `Responsive.luau`, `Board.luau`, `Rng.luau` | byte-identical to plus1-jump's. |
| `src/shared/Config.luau` | `Config.Env` (6 bands, 4 disaster overlays, critters, scenery ring), `Config.Hazards` (4 stray kinds), `Config.Rest`, `Config.Budget`, `Config.Shots` (nil in `src/`). |
| `src/shared/SkyArt.luau` | code-only art: far scenery per band, critters, weather emitters, the stray models. Client only. |
| `src/client/Sky.client.luau` | the glue: `Survived` -> bands -> Lighting / scenery / critters / weather; the disaster overlay; strays + knock; rest + the AFK clock; band title cards. |
| `src/client/World.client.luau` | the disasters' show: ring pulses and projectiles, the red tint on cells about to flood or crack, the tornado's red path ribbon and funnel, falling chunks, Heat flames over every player, confetti. |
| `src/server/Main.server.luau` | the truth the show is drawn from: ring Parts, the flood's water and red line, `CrackAt` / `Dropped`, the `Path` attribute, the `Funnel` anchor; `Fx.applyLighting(Fx.Presets.Coast)` first thing. |

The templates' own specs are copied with them (`tests/EnvBands.spec`, `Hazards.spec`, `Rest.spec` byte-identical;
`EnvConfig.spec` copied and extended for this game's bands; `Board.spec` copied plus a Disaster Rounds section).

**Adaptations, and why** (none inside the templates; all in the glue):
1. **A break pressed on the island waits for the round to end.** `Rest.luau` says rest must never pause a clock the
   player races, and a round is one. The glue holds it as "☕ Break after this round" and calls `Rest.request` back on
   the deck. (`check_disasterrounds_rest` 2; mutant M22.)
2. **Server moves are not movement.** The server bumps the Player attribute `MoveSeq` at every drop, practice landing,
   sweep-out and outro return; for 1.0 s after a bump the glue reports "not moving". Without it the two teleports of
   every cycle would wake every break and reset every idle clock. (`check_disasterrounds_rest` 3.)
3. **The AFK clock counts the player's own input**, not `Rest.luau`'s idle clock: on the deck a stray comes every
   60-90 s and `Rest.luau` resets idle on every threat, so an AFK player there never reached `IdleSeconds` and stayed
   on every roster. Found by `check_disasterrounds_rest` on 2026-10-07; `Rest.luau` itself is unchanged. (Mutant M12.)
4. **The strays only run on the Lookout**, while awake, because on the island the disaster is already one long hazard
   and the standard forbids two at once.

---

## 2. The bands and what triggers them

**Trigger: lifetime counted survivals, never time.** The server writes the Player attribute `Survived` at a round's
end; it only goes up. Each client blends `Config.Env.Bands` by its own player's `Survived` with `EnvBands`, so two
players in one server can see different skies over the same island (the island, water, rings and Lookout are
shared). The story: the more disasters you live through, the wilder your world, until the sky falls, and long after,
a new dawn. Every value glides on a 0.6 s half-life; Lighting is written at most 10 times a second and only on a change.

Minutes: `tests/Pacing.spec.luau`, 1 500 simulated 4-hour sessions per profile on the real modules, median
(p10 / median / p90 for normal). Parts: the band's far scenery measured by `check_disasterrounds_env`.

| # | band | from (survivals) | fade | normal | fast | slow | light | far scenery (250-450 studs) | critters | weather | parts |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏝️ Calm Cove | 0 | - | 0 | 0 | 0 | clear morning, ClockTime 9.5 (= `Fx.Presets.Coast`) | two palm islets, a sailboat | 4 gulls | sea spray | 21 |
| 2 | 🌬️ Windy Point | 2 | 1 | 2.7 / **3.3** / 4.4 | 3.3 | 3.8 | bright midday, 13.5 | a lighthouse on a sea stack, wind-bent trees | 4 albatross | wind streaks | 24 |
| 3 | ⛈️ Storm Coast | 6 | 2 | 8.7 / **9.9** / 11.8 | 9.3 | 11.6 | overcast late afternoon, 16.5, violet-grey fog | a storm-cloud bank with silent lightning, a shipwreck | 5 petrels | drizzle | 13 |
| 4 | 🌋 Ember Isles | 12 | 3 | 18.1 / **19.9** / 22.3 | 18.5 | 23.8 | dusk, 18.0, amber | a smoking volcano with a lava glow | 6 bats | ash | 7 |
| 5 | ☄️ **Falling Sky** (the brag) | 21 | 4 | 32.8 / **35.2** / 38.4 | 32.7 | 42.0 | deep violet night, 20.0, exposure kept up so rings read, strong bloom | a huge cracked comet low on the horizon, far meteor streaks | 5 fire-birds | sparks | 19 |
| 6 | 🌅 New Dawn | 100 | 20 | 163.0 / **168.4** / 174.1 | 155.7 | 199.8 | golden sunrise, 6.4 | a rainbow arc, flowering islets | 6 butterflies, 3 dolphins | pollen | 70 |

Measured: every band's median stay is at least 2 minutes for every profile (normal 3.3 / 5.9 / 10.3 / 14.7 / 133.5
in bands 1-5). **No band, overlay or island palette is red** (`tests/EnvConfig.spec`: no TintColor has red more than
0.15 above both green and blue; `check_disasterrounds_env` 6: nothing the sky builds is red), because red means "it
hits here".

**On screen:** the band chip under the streak ("🏝️ Calm Cove · 🌬️ at 2"); a title card on entering a band during play
("⛈️ STORM COAST - Your sky changed: 6 disasters survived"); a returning player gets the chip, not the card.

### 2.1 The disaster on top of the band

The running disaster is a server-wide overlay (`EnvBands.overlay`), weighted in over 3 s at the name and out over 3 s
after the end, so each player's band stays underneath (`check_disasterrounds_env` 4 measures both glides).

| disaster | overlay | the show (World.client) |
|---|---|---|
| ☄️ Meteor Shower | warm orange haze, saturation up | a meteor per ring from one compass direction per round, landing on the ring's centre exactly at impact; a camera shake within 20 studs |
| 🌊 Flood | darker, blue-grey fog | rain, the water sheet, the red line at the coming height, every cell that will flood tinted red; a white spark (the lightning) falls on each aimed ring |
| 🌪️ Tornado | green-grey tint, dust haze | a dust emitter, the funnel (six spinning rings over the anchor), 12 pieces of debris, the red path ribbon |
| 🏚️ Earthquake | brown dust haze | a dust emitter; cracked cells tinted red; dropped cells fall as 6 chunks each (60 at most); a camera shake within 30 studs of a drop |

### 2.2 Signature effects

* **The red is the signature**: one red (255, 40, 40) for every "it hits here" in every disaster and on the deck; a ring
  pulses faster as its impact nears.
* **Heat glows**: an orange-gold flame aura on every player at Heat 1+, its rate 6 x Heat, and a 🔥N billboard;
  players with 21+ survivals keep a faint amber ember aura and a ☄️ billboard for good (the brag, worn).
* **SURVIVED**: a gold / white / teal confetti burst (never red) where you stood, a white flash and an FOV punch.
* **Swept out**: a soft blue flash and the card "💥 Hit by a meteor - Streak lost. Next round in 0:24".

---

## 3. The brag moment and the long-term goals

**"☄️ THE SKY IS FALLING"** at 21 survivals: a 4 s card with a white flash and an FOV punch, the comet and the far
meteors glide in with band 5, the ember aura for good, and a server-wide toast "☄️ *Name* has survived 21 disasters.
Their sky is falling." Only when it is crossed during play (`Progress.survive` returns `brag`). Measured (Pacing.spec,
re-run after REVIEW-1 made the next disaster an even draw): **normal 35.1 min median (p10 32.7, p90 38.3), fast 32.7,
slow 41.9**, all inside 30-45; asserted within 5 min of DESIGN.md's 35.2.

**"🔥 MAX HEAT"**, the first streak of 10: a server-wide toast. Normal 28.4 min median (p10 14.8, p90 72.6), fast
15.4, slow 98.8 (65 % of slow sessions within 4 h).

**Long-term:** the Codex 24/24 (every disaster survived at Heat 5): normal 1.9 h median (p10 0.6, p90 4.1); band 6
New Dawn at 100 survivals: normal 168.1 min; the board's best streak, counted up to 25 (REVIEW-1 F5): normal 10 / 12 /
16 at 30 / 60 / 240 min, fast 15 / 21 / 33; a fast player reaches 25 in 43 % of one-hour sittings, a normal one in 2 %.

---

## 4. Hazards

### 4.1 The disasters are the hazards

The standard's hazard rule is written for hazards that interrupt a game. Here the disasters *are* the game, so they
keep the parts that make them fair and drop the parts that would remove the game (DESIGN.md §4.1):

| the standard's rule | in Disaster Rounds | measured |
|---|---|---|
| telegraphed | ring 3.0 s; flood red 9 s before the rise (11 s before the water reaches the cell); the red path shows the next 4 s; a crack 3.0 s before it drops | `check_disasterrounds_zones` |
| **the red marks exactly where a hit can land** | every ring is a red disc 2 x (3.0 + 1.5) = 9 studs across, a volume from 0.05 over the lowest cell top it reaches to 0.25 over the highest, so it shows on every terrace (REVIEW-1 F7); the flood's red cells are exactly the flooded set; the tornado's red is its reach exactly: a 13-stud disc on the funnel and on every published point ahead of it, 13-stud boxes between them, nothing behind it, drawn from the name (REVIEW-1 F8); the red cells are exactly the cracked ones | `check_disasterrounds_terrace`: 412 rings of 3 crowded Heat-5 rounds, 216 (52 %) reaching more than one level, red at the ground of all 1 444 cells they reach; the tornado sampled at 600 frames: 45 917 points within its reach all on red, 28 746 points 0.05 or more outside it none on red; a player stopping 4 studs behind the funnel stood on red in all 20 frames before it caught him. `check_disasterrounds_zones`: 60 rings of a crowded Heat-5 round all exact; red cells per rise 61 / 98 / 127, each exactly the flooded set; red = cracked in every frame of two batches; a root 0.05 studs outside a ring through its impact is not hit, 0.05 inside is; 0.05 on the dry side of a beach edge is not swept, 0.05 on the red side is; a rider 0.25 outside the funnel's reach for 3 s is never caught, 0.25 inside is caught in 0.32 s; 0.05 over a crack's edge onto the intact neighbour is not hit, 0.05 inside is |
| survivable by a player who reacts | the bot (0.6 s reaction, sees only what a client sees) is never hit | `check_disasterrounds_fair`: 8 bots at Heat 5, 50 islands per disaster, **0 of 1 600 bot-rounds lost**, 20 653 rings, 27 929 step-outs; and 0 of 320 at Heat 0 |
| rare, one at a time | **no**: dozens of rings a round is the genre; density is capped by `ExitStuds` 7 and `MaxCoverage` 0.25 instead | `tests/Strikes.spec` |
| a hit costs a little | a hit costs the round and the streak, **never progress** (`Survived`, `Best`, the Codex) | `check_disasterrounds` 5 |
| an idle player | is swept out in every round | `check_disasterrounds_fair`: at the latest 13.2 s after the name at Heat 5, 22.6 s at Heat 0 |

### 4.2 The Lookout strays (the standard's rule in full)

Debris from the island's disaster sometimes flies to the deck. `Hazards.luau` verbatim, client only, **only on the
Lookout and only while awake**, themed by the current (or last) disaster.

| kind (disaster) | speed | telegraph | lane locks | hit radius | ring (+1.5) | knock |
|---|---|---|---|---|---|---|
| ember (Meteor) | 30 | 3.0 s | 1.5 s before | 1.8 | 3.3 | 32 |
| spray (Flood) | 22 | 3.2 s | 1.6 s | 2.2 | 3.7 | 28 |
| plank (Tornado) | 34 | 3.0 s | 1.5 s | 2.0 | 3.5 | 34 |
| pebble (Quake) | 26 | 3.2 s | 1.6 s | 1.8 | 3.3 | 30 |

One every 60-90 s of awake Lookout time, never two at once, lanes start on screen (within 35 degrees of the camera's
heading, 20 degrees of its pitch), the red ring on the deck's top face, a knock that lifts 8 studs/s (0.16 studs:
never over the 4-stud rail), `PlatformStand` 0.9 s. **Measured** (`check_disasterrounds_rest` 5): 7 strays in 10
minutes awake on the deck, **0 in 10 minutes resting**, 6 in 20 minutes of toggling rest (400 s awake): toggling
does not thin them out. How often a normal player meets one depends on their deck time; the design model put it at
one per 4.6 minutes of play (DESIGN.md §4.2, `design/pacing_model.py`; **not re-measured in Luau**).

---

## 5. Rest - what "pause" means here

Tap ☕ on the Lookout: your character sits, the HUD says "☕ On a break - move or tap ☕ to rejoin the rounds", **you
are not dropped onto the next island**, the strays leave you alone, and the rounds go on without you. Move, or tap ☕
again, and you are back for the next drop. `Rest.luau` verbatim: `IdleSeconds` 150, `PendingSeconds` 8 (the longest
stray flight 5.7 s + 2), `WakeOnMove`, `BlockWhileThreat`, `RequireGrounded`.

**What it pauses:** your entry into rounds and the stray clock (frozen, never reset). **What it does not:** the round
cycle, one clock for the whole server. **Why it cannot be exploited:**
1. The roster freezes before anything about the round is visible: the next island is built under `ServerStorage` and
   parented only after the freeze; the disaster is named 4 s later (`check_disasterrounds` 1, mutant M7).
2. Rest earns nothing: no survival, no streak, no Codex (`check_disasterrounds_rest`: the AFK player survived none).
3. A break pressed on the island waits for the round's end; it never ends a round early (rest 2, mutant M22).
4. The server trusts the client's flag safely: claiming rest only keeps you off the island; hiding it only drops you
   onto it.
5. **The next disaster is an even draw** (REVIEW-1 F4). The first build never repeated the last disaster, so a player
   who rested except after a flood never met a flood (0 of 15 rounds in the review's probe). Now the last disaster
   says nothing about the next (`check_disasterrounds_exploit` 4: the same disaster back to back 11 times in 40 rounds).
6. **A break the client asked for is the break the server applies** (REVIEW-1 F9): a request over SetRest's rate is
   applied when the second is up, never dropped (three quick taps on ☕ had left the HUD "on a break" while the server
   dropped the player into rounds and swept them, streak 6 to 0).

**Measured** (`check_disasterrounds_rest`): an AFK player is on a break after 150 s of no input; the drops, returns,
strays and knocks on the way did not reset that clock; they were dropped into 4 rounds on the way (alone, each round
ends the moment they are swept) and survived none.

---

## 6. Budgets (caps in `Config.Budget`, capped in code since REVIEW-1 F11, measured by `check_disasterrounds_env`)

| what | cap | measured peak |
|---|---|---|
| far scenery Parts, one piece / one band / at a seam | 125 / 250 / 500, trimmed in `SkyArt.updatePiece` (a band has at most 2 pieces) | 70 (New Dawn) / 89 at the worst seam; with the caps lowered to 3 per piece and 10 in all, the client keeps to them |
| critters | 10 | 9 |
| weather emitters | 2 | 2 |
| PointLights | 6 | 1 |
| server Parts (island + props + Lookout + board + walls + rings) | 400: every source that varies is capped (169 cells, `MaxProps` 80, `Budget.Rings` 16) and the sum at the caps fits | 313 (8 players at Heat 5, all four disasters); 315 at every cap (50 fixed + 169 + 80 + 16) |
| projectiles | 16 | 13 |
| falling chunks | 60 | 60 |
| tornado debris | 12 | 12 |
| tornado red pieces (discs + boxes, pooled) | 40 | 34 |
| Heat auras / billboards | 8 / 8 | 8 / 8 |
| disaster emitters | 6 | 2 |
| live rings (server), capped in `Strikes.maxLive` | 16 | 15 |
| strays | 1 | 1 |

---

## 7. Gates

All green after REVIEW-1 (2026-10-08; counts and how to run them: `CLAUDE.md`, the review: `REVIEW-1.md`).
Eye-candy specific: `tests/EnvBands.spec` 124, `Hazards.spec` 111, `Rest.spec` 55, `EnvConfig.spec` 151,
`Pacing.spec` 27; `check_disasterrounds_env` 85, `check_disasterrounds_rest` 30, `check_disasterrounds_zones` 70,
`check_disasterrounds_terrace` 23, `check_disasterrounds_exploit` 28, `check_disasterrounds_hud` PASS (overlap =
true), `check_disasterrounds_fair` 12. Both mutation sweeps (the build's 35, REVIEW-1's 22 plus the build's 35 ported)
killed every mutant aimed at a promise in this file; the control survived every gate.

---

## 8. Needs Studio (only real rendering, input, network and live services can settle these)

1. **Jumping 4-stud steps** on a phone (jump button) and on PC; whether a running jump crosses a one-cell (8-stud) hole,
   which the 0.6 s flood / hole grace assumes; how often a player misses a step while fleeing a flood.
2. **Ring readability** on every style's top materials (sand, grass, pebble, snow, sandstone) and in every band's
   light, above all band 5 at night and band 4 at dusk; a ring that straddles two or more levels is now a translucent
   red VOLUME from just over the lowest top to just over the highest (REVIEW-1 F7: 52 % of rings in crowded rounds do;
   a flat disc was buried in the higher cell): does a 4-12 stud red column on a step read as "the ring", and does it
   hide the player inside it; the red against ochre sandstone and lava-orange light.
3. **Water**: the 0.25-transparent sheet, the red line at the coming height, the red tint (cell colour lerped 0.65
   toward red) on cells about to flood, on a phone.
4. **The tornado**: the stacked-ring funnel's look; its red (REVIEW-1 F8): a 13-stud disc under the funnel and on every
   published point ahead, boxes between them, each a volume over every terrace it reaches, shown from the name: up to
   35 translucent Parts moved every frame (pooled): frame time on a phone, and whether overlapping translucent pieces
   read as one path; debris frame time.
5. **Quake drops**: falling chunks frame time, crack readability, holes visibly open to the sea.
6. **Meteors from the radiant** (one compass direction per round, from 160 studs up the line): on screen from the
   default camera at the usual pitch? Lightning and boulders the same. The ring does not depend on it.
7. **`PivotTo` drops and returns**: camera snap, the character's state after the move, a drop mid-jump.
8. **The movement guard on a real network**: false positives under jitter and lag spikes at 28 studs per 1.0 s.
   Log every trip for several live rounds before trusting it (`check_disasterrounds_guard` proves the threshold
   headless: 27 studs allowed, 29 caught). Since REVIEW-1 F10 nothing the server sees in the quiet second after a drop
   is kept (one stale deck position 0.05-0.8 s after it no longer sweeps the player); a stale position seen AFTER
   that second still trips it. Whether the engine ever shows the server the old spot after a server `PivotTo` of a
   client-owned character, and for how long, only a live server can say.
9. **No player-player collision**: the `DRPlayers` collision group (pcall'd; robloxemu has no PhysicsService).
   Accessories added after `CharacterAdded` are not put in the group; check that players still walk through each
   other and nobody can be pushed into the red.
10. **Spawn yaw** on `LookoutSpawn`, and whether the post-parent facing write (SPAWN-ORDER §3) looks like a snap.
11. **Rest's sit** (`Humanoid.Sit` without a seat): does it replicate; does moving wake it as designed.
12. **Lookout strays**: lanes start on screen with the camera facing the island; the knock with `PlatformStand`; the
    rail and the 20-stud invisible walls hold.
13. **Every band's look and every disaster overlay**: exposure, fog against Atmosphere, bloom in band 5, the far
    scenery at 250-450 studs (culled at low graphics quality? if so, closer and smaller).
14. **The HUD on a real phone**: notch and safe area, the Jump-in button, card text length, the 🔥 billboards.
15. **Frame time on a low phone**: 8 players at Heat 5 in a Meteor Shower (13 live rings, 12 projectiles measured
    headless) and a quake's 60 chunks.
16. **Live services**: OrderedDataStore and `GetFriendsAsync` with real friends and throttles; the session lock
    across a fast server hop; `BindToClose` voiding a round.
17. **Server-wide toasts** (MAX HEAT, Falling Sky) in a full server: exciting or spammy.
18. **Sound** needs chosen assets (meteor whistle, flood siren, tornado roar, quake rumble, survive chime). v1 is silent.
19. **Being swept out**: does the flash and the move to the Lookout read as "swept away" or as a glitch, for the player
    and for others watching.
20. **Publish settings**: `MaxPlayers = 8` (the store text says "Up to 8 players"); `StreamingEnabled` false (also
    pinned in `default.project.json`).
21. **The board** (12 x 8 studs, 40 px per stud, at the deck's north end 16 studs from the spawn): readable from the
    spawn on a phone; the emoji in SurfaceGui labels; the prompt's tap target. The SurfaceGui is made by
    `Board.client` under the board part, not in `PlayerGui` (DESIGN.md §7 said PlayerGui + Adornee; the HUD fit
    check measures everything in PlayerGui as a screen panel).
22. **The band title card on a phone** while a disaster card is up (both centre cards).
23. **The default player list on PC** (REVIEW-1): `leaderstats` (Streak, Best) turn on Roblox's player list in the
    top-right corner, where the ☕ Rest and 📖 Codex buttons sit. Check that they are not covered on a desktop window
    (phones collapse the list); if they are, move the buttons or hide the list's leaderstats.
24. **Flying off the island** (REVIEW-1 F2): off the island is now the sea in every disaster. Check with a real
    character that nothing honest gets a root past the cells (|x| or |z| 52 or more): the invisible walls stand at 53
    and hold a walking root at about 51.5; a knock-back, a ragdoll or a jump against a wall must not push it out.
25. **Real `UpdateAsync` latency** (REVIEW-1 F3): it sets how long a leave's release waits behind a write in flight
    (now written after it) and how long `BindToClose` waits (at most 25 s).
26. **The board prompt's reach on the server**: whether `ProximityPrompt.Triggered` is distance-checked by the engine;
    the only effect is a 1-a-second Public/Friends toggle, but say so after looking.

---

## 9. Thumbnail shot list (for the night Studio session)

Every shot is **1920 x 1080**: set the Studio viewport to 16:9, capture at 1920 x 1080 or larger and scale down. Keep
the subject inside the middle 1280 px (a phone's carousel crop).

**Getting there without touching real saves.** *Not tried in Studio yet; verify step 1 first.*
1. **A shots place.** In `disaster-rounds/`, `rojo build -o DisasterRounds-shots.rbxlx` and open it (`*.rbxlx` is
   git-ignored). Keep Rojo disconnected while you edit it. Never edit `src/`.
2. **No saves.** The place is not published, so the DataStore is unavailable: the server warns that progress will
   not be saved (or the load fails three times, about 7 s, then "Couldn't load your profile"). Either way nothing is
   written anywhere. Wait for the warning before staging: a player whose load has not finished is not dropped.
3. **Edit `ReplicatedStorage.Config` in the shots place only:** `Config.Shots.ForceKind = "<kind>"` (the next named
   disaster), `Config.Shots.ForceHeat = <0-5>` (everyone's Heat at the drop), `Config.Shots.IslandSeed = <n>` (the
   same island every round; try seeds until a pretty one). `Rest.IdleSeconds = 0` turns idle rest off while you frame.
4. **The band** (command bar, Server): `game.Players:GetPlayers()[1]:SetAttribute("Survived", 21)`. Set it in the
   intermission; the server rewrites it only at that player's round end or sweep-out. The HUD would show the staged
   number, so **hide the HUD** for these shots (`DRHud` ScreenGui `Enabled = false`, Client) unless a shot says otherwise.
5. **Several players**: Test -> Clients and Servers -> Local Server with 3 players; move them with
   `plr.Character:PivotTo(CFrame.new(x, y, z))` (Server) between rounds, or walk them.
6. **Camera**: `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable` and set its `CFrame` (Client).

| # | shot | staging | in frame |
|---|---|---|---|
| 1 | **Step out of the ring** | `ForceKind = "meteor"`, `ForceHeat = 5`, `Survived = 21` (band 5) | camera 4 studs up and 14 behind an avatar mid-step out of a red ring, the meteor about 1 s from impact (53 studs up the radiant line), two more rings near, the cracked comet on the horizon |
| 2 | **Get above the line** | `ForceKind = "flood"`, `Survived = 6` (band 3), 3 players | the second warning (16-25 s after the name): aerial three-quarter view from 70 studs; water over the beach, the red line at y = 6, the level-1 cells tinted red, players climbing the terraces under the storm bank |
| 3 | **Off the path** | `ForceKind = "tornado"`, `Survived = 12` (band 4) | ground camera 2 studs up, the funnel about 15 studs away, the red path under it, an avatar jumping off the path, debris in the air, the volcano behind |
| 4 | **The ground gave way** | `ForceKind = "quake"`, `Survived = 2` (band 2) | the 6th batch (33-39 s after the name): a red cell dropping in chunks, an avatar jumping to the next cell, holes showing the sea |
| 5 | **New Dawn** | `Survived = 100` (band 6), 3 players on the deck | the Lookout from the island side at sunrise, the rainbow over the sea, butterflies on the deck, the board behind |
| 6 | **The Lookout at the drop** (HUD on) | a fresh profile, no Config edits | from behind a player on the deck as the island appears and the countdown turns to "Landing"; HUD on: every number on it is real (all zero) |
