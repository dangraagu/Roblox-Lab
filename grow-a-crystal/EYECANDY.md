# Grow a Crystal — the cavern that comes alive

Owner's brief (Gustav, 2026-09-17): richer and never monotonous, with environment changes that follow what the game is
about; rare, easy-to-avoid knock-down hazards; a way to rest that can never be exploited; a thumbnail shot list for the
night Studio session. The brief also said that an idle game should not punish the player, so knock-down hazards are
probably wrong here, and asked for a justification either way.

**State: built, unit-tested, headless-tested through the real server + HUD + client, mutation-tested, and through one
round of independent adversarial review, whose three findings are closed (§13). NOT seen in Studio.** Nothing was
committed, pushed or published. The first attempt at this task had only
copied two template modules (an out-of-date `EnvBands.luau` without `capRates`) and started a pacing probe. The second
replaced both copies with the current template, built everything else and ran a mutation sweep, and was cut off
before it wrote this document's gate and mutation sections. The third (2026-09-24, §12) re-read every file, re-ran
every gate, closed the sweep's one surviving mutation with a new check, re-ran the whole sweep, and rebuilt the shot
list after a geometry probe found that five of its seven camera set-ups left out something they promised to show,
and two put a landmark on the wrong side of the frame (§9). A separate reviewer then found three defects: the HUD
could lose the join push to the cavern script (high), a phone player's code answer was about 6 px tall (low), and a
row of Legendary harvests stacked full-screen flashes (low). The fourth session (§13) reproduced all three, wrote a
failing test for each, fixed the game, and re-ran every gate and a 75-mutation sweep.

**In one paragraph.** The progress value is **how many chambers the player owns**. It is read from the player's own
sockets in the world and from the server's State push, and it drives five looks: 💧 Sunken Grotto → ✨ Glow-worm Hollow
→ 🍄 Mushroom Terraces → 🌊 Waterfall Chamber → 💎 Heart of the Geode. Every chamber purchase changes the cavern, and
nothing is ever taken away: glow-worms fill the ceiling, giant glowing mushrooms grow along the walls, an underground
waterfall pours into the pool, crystal prisms line the geode wall. Light, fog, bloom and colour glide into each new look.
A slow **geode pulse** makes everything that glows breathe. A harvest throws **shards in the colour of the tier it
refracted into**, and a Legendary or Mythic harvest sends a **beam of light** up to the ceiling. There are **no knock-down
hazards** (§3). Instead, rare, harmless **visitors** (a moth swirl down the light shaft, a bat swoop under the ceiling)
pass about once every 2.5 minutes of play. **🛋 Relax** sits you down and softens the view, and visitors leave you alone
while you rest. The crystals keep growing, because growth runs on the server's clock.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from `plus1-jump` (review round 2, with `capRates`; md5 `c6fc63a1…`, identical). Progress → band + eased blend, `approach`, `capRates`. Pure. |
| `src/shared/Rest.luau` | **template, verbatim** (md5 `19226cb6…`, identical). Rest rules. Pure. |
| `src/shared/Visitors.luau` | **new, pure.** The rare-event clock from +1 Jump's `Hazards`, without the hazard. One visitor every 120-180 s of play, launch to launch. Never two at once, none in a band with no visitor kinds (re-rolled, never stored up). Frozen, never reset, while resting. A visitor in flight finishes. |
| `src/shared/Grotto.luau` | **new, pure,** the game-specific rules. `progress` (chambers, clamped; a remote payload is not trusted). `chambersFromSockets` (the world's count). `chipText`, `burst` (the harvest effect per tier; a copy). `flashDue` (the Legendary/Mythic flash at most once per cooldown, §13). `pulse`. `layout`: every client-built element, its particle volumes, critter zones and visitor routes, in plot-local coordinates, like `Cavern.build`. `routePoint` (Catmull-Rom). |
| `src/shared/StateFeed.luau` | **new in review round 1, pure, client only.** The ONE client connection to the State remote. `Hud.client` and `Grotto.client` subscribe to it instead of connecting one each, so Roblox's queue rule (the join push goes to the first connection only) can no longer pick a loser. A script that subscribes late is handed the latest payload (§2, §13). |
| `src/shared/CavernArt.luau` | **new, client only.** Builds and pools the local parts: scenery pieces that fill in by weight, critters (moths, bats, wisps), particle "weather" (drips, spores, mist, sparkle), visitor flocks, harvest shards, ring and beam. |
| `src/client/Grotto.client.luau` | **new, the glue.** Chambers → bands → lighting (10 Hz, glided) → scenery, critters and weather → rest → visitors → bursts → chip, Relax button and title cards. Subscribes to `StateFeed`; the harvest flash and the Mythic shake wait out `Env.HarvestFlash.cooldown` (§13). |
| `src/shared/Config.luau` | + `Env` (5 bands, layout counts, critters, harvest rules, `HarvestFlash`), `Visitors`, `Rest`, `Pacing` (model assumptions), `Budget`. All cosmetic; the server never reads them. |
| `src/server/Main.server.luau` | **+9 lines.** A per-session `harvests[plr] = { n, socket, seed, tier }`, set in `grantHarvest` after the reward is paid and sent in every State push as `lastHarvest`. Cleared on leave. Nothing else on the server changed: no new remote, no change to growth, harvest, economy, saving or spawning. |
| `src/client/Hud.client.luau` | **a pre-existing defect, fixed.** On a phone the open code drawer's Redeem button sat 4 px inside the thumbstick's band on a 640×300 screen, where a tap never lands. It is now one row (box + button) on compact layouts. The new HUD gate found it; `check_crystal` never opens a drawer. **Review round 1 (§13):** State through `StateFeed`; on compact layouts the server's answer to a code takes the whole row for its 2 s (box and button hidden meanwhile) instead of the thumb-wide button, and the box's hint is "Code". Desktop behaves as before. |
| `tests/` | `EnvBands.spec`, `Rest.spec` (verbatim from the template), `Visitors.spec`, `Grotto.spec`, `EnvConfig.spec`, `Pacing.spec` + `IdleModel.luau` (test-side model, not shipped), and `StateFeed.spec` (review round 1). The previous attempt's `_probe_pace.luau` was removed. |
| `robloxemu/check_growacrystal_*.luau` | `harvest` (server push), `env` (the whole glue: takeover, bands, glide, bursts, visitors, rest, budgets, leak rules), `hud` (the HUD gate with both clients, every drawer open), `row` (the chip/button against every HUD element), `join` (a slow profile load), `race` (the join push missed entirely), `critters` (new in the resume session, §12: the real `CavernArt` with a scripted rand, critters born on their zone's floor and ceiling, held to the height band that keeps them over every head). New in review round 1 (§13): `queue` and `queue_hudfirst` (Roblox's queue rule replayed against the real scripts in both start orders), `redeem` (the code answer's size, place and timing on every phone), `flash` (a row of Mythic harvests). |

---

## 2. The bands and what triggers them

**Trigger: chambers owned, never time.** This is the number the HUD's "Buy Chamber" button counts and the rubble
caps show, and it is the cavern itself: each chamber is a terrace with six sockets. The client reads it two ways and
takes the larger:

* **from the world:** its own plot's sockets, `Socket_<UserId>_<id>`. Chamber *c* counts once its last socket,
  6*c*, is there, counting from 1 with no gaps (`Grotto.chambersFromSockets`);
* **from the server's State push** (`s.chambers`, clamped by `Grotto.progress`).

Why two: Roblox queues a RemoteEvent that fires before any listener exists and **flushes the queue to the first
connection only**, and the next push only comes when the player plants, harvests or buys. `Hud.client` and
`Grotto.client` both need State, in a start order Roblox does not define. The build session handled that for the
cavern only (the sockets); the HUD could still lose the join push to the cavern script and read "💎 0" (review
round 1, finding 1, §13). Now both scripts subscribe to **one** connection (`StateFeed.luau`): whichever starts first
makes it, the queue goes to it, and the other is handed the latest payload when it subscribes
(`check_growacrystal_queue` and `_queue_hudfirst` replay the queue rule in both orders). The sockets stay as the belt
for a push that is late or never comes: `check_growacrystal_race` runs the client with no State push at all, and the
cavern still reaches the Heart of the Geode from its sockets. The count never shrinks: chambers only grow, and a stale
push is not believed over the sockets.

**Transitions never cut.** A band fades in over `fade` chambers *before* its `from` (EnvBands, smoothstep), so every
purchase moves the look: chamber 2 is half-way to the glow-worms, 3 is all of them, 4 half-way to the mushrooms, and so
on (`EnvConfig.spec`: every one of the seven purchases changes a band weight by more than 0.05). On top of that, every
value glides with a 1.2 s half-life, and Lighting is written at most 10×/s and only when a value moved. Measured through
the real client on each purchase: no frame moves Brightness or FogEnd by more than **7.0 %** of the change (a hard cut
would be 100 %; the gate is 10 %), and Ambient by at most 10 % of its change or one 0-255 colour step per frame. Scenery fills in rather
than switching: a piece at weight *w* shows the first ⌈*w*·*n*⌉ of its *n* elements, and the last one fades in. The
order is bit-reversed, so a half-weight piece is thin everywhere rather than full at one end. Later bands keep every
piece of the earlier ones (`EnvConfig.spec`), so the cavern only ever gains.

**The first card is quiet** and waits until the chamber count has held still for 1 s, because a batch of sockets can
replicate over several frames. A returning player gets "💎 HEART OF THE GEODE · chamber 8 of 8" with no flash, never
a card for half the sockets followed by a fanfare (`check_growacrystal_join`, `check_growacrystal_race`). After that,
a purchase that opens a band shows its card. The last band opens with a flash and an FOV punch. A purchase that only
starts the next look shows a teaser ("✨ Glow-worms are waking up…").

Minutes = minutes of PLAY to own the chamber (40 seeded sessions of 8 h per profile, `tests/Pacing.spec.luau`,
p10 / median / p90). Offline growth is not modelled, so real players who leave crystals growing overnight get there
sooner.

| # | band | first shows | full | normal: minutes | slow: median | lighting | scenery (cumulative) | life | particles | visitors |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 💧 Sunken Grotto | ch 1 | ch 1 | 0 | 0 | = the server's `Fx.Presets.Cozy`, number for number (dark teal, bloom 0.9) | shimmer on the pool | 2 moths | ceiling drips 6/s | none |
| 2 | ✨ Glow-worm Hollow | ch 2 | ch 3 | 1 / 1 / 1 → 1 / 1 / 1 | 2 → 2 | cooler blue-green, darker ambient so the worms pop, bloom 1.05 | + 16 glow-worm strands (thread + bead) hanging from the ceiling | 5 moths | drips 5/s | moth swirl |
| 3 | 🍄 Mushroom Terraces | ch 4 | ch 5 | 20 / 42 / 68 → 60 / 78 / 99 | 85 → 158 | warm violet/amber, saturation 0.28 | + 6 giant glowing mushrooms along the walls (stem, cap, gill ring) | 6 moths | spores rising 8/s + drips 3/s | moth swirl |
| 4 | 🌊 Waterfall Chamber | ch 6 | ch 7 | 94 / 112 / 134 → 168 / 190 / 210 | 225 → 380 | aqua mist, haze 1.8, bloom 1.15 | + an underground waterfall into the pool (sheet, core, foam, spray) | 4 moths, 4 bats | mist 12/s + spores 4/s | bat swoop, moth swirl |
| 5 | 💎 Heart of the Geode | ch 8 | ch 8 | 239 / 262 / 281 | not within 8 h (p10 478) | amethyst/magenta, strongest bloom 1.3, deepest pulse | + 10 crystal prisms lining the geode wall around the pool, 8 glowing seams on the ceiling and upper wall | 4 moths, 3 bats, 5 wisps rising up the light shaft | sparkle 10/s + mist 8/s | bat swoop, moth swirl |

The **geode pulse** gets deeper with each band: depth 0.08 in the grotto, 0.35 in the geode, with a period of 9 s
down to 7 s. It dims every glowing element and nudges bloom by up to ±4 %. Its phase is integrated, so a change of
period never makes it jump.

**Chip** (under the HUD's header): `🍄 Mushroom Terraces  ·  🌊 Chamber 7`. With every chamber open it reads
`…  ·  every chamber open`, and while resting `🛋 Relaxing — your crystals keep growing`.

### The pacing model and an economy FINDING (owner decision, §11)

`tests/IdleModel.luau` plays the game's own rules (Economy, Growth, Rarity, Codex, Rng, Config). The human part is
written down in `Config.Pacing.Profiles`:

* **normal**: visits the sockets every 75 s, redeems the four advertised codes, plants the Shard seed the HUD starts on,
  and buys the cheapest upgrade (chamber, luck, growth) while keeping enough dust to replant;
* **slow**: the same, every 150 s;
* **nocodes**: normal, but never types a code.

The model found something the looks cannot fix. **At luck level 0, no seed below Mythic pays back its price on
average:**

| seed | costs | returns on average |
|---|---|---|
| Shard | 10 | 7.82 (78 %) |
| Quartz | 50 | 14.63 (29 %) |
| Amethyst | 250 | 34.37 (14 %) |
| Prism | 1 200 | 99.52 (8 %) |
| Legendary | 6 000 | 360.00 (6 %) |

A player who never types a code starts with 3 free Shards and 30 dust, runs dry after about 27 harvests, and **never
owns chamber 2** (40 of 40 sessions, 8 h each). That player never leaves the first band. The codes (`MYTHIC` alone is
5 000 dust) are what make the game progress at all. `Pacing.spec` asserts this as a FINDING, not a requirement, so this
note stays true. When the economy is retuned those two assertions fail, and this section and the table above must be
re-measured. Band 1 was made rich on purpose for exactly this reason: shimmer, drips, moths, the pulse, the harvest
bursts and the Legendary beam all work in chamber 1.

---

## 3. Hazards: none, on purpose. Visitors instead, at the same rarity

**Why there are no knock-down hazards in this game:**

1. **There is nothing to be knocked off.** The terraces are full-width stairs inside a sealed shell with no edge
   anywhere (`Cavern.luau`: "there is no edge anywhere to fall off"). A knock could only shove a player a few studs
   sideways on the floor they were standing on. That costs nothing, so it cannot be a challenge. It can only be an
   interruption.
2. **What it would interrupt is the core loop.** The player is either clicking sockets from up to 32 studs away or
   watching crystals grow. A hazard that makes you look away from your crystals punishes exactly the attention the game
   is built on, and there is no failure state for it to feed.
3. **"Cozy idle" is the product.** A game whose store page promises relaxing growth should not have things flying at
   you.

What the brief wanted from hazards is still here in the part that fits: **something rare, easy to see, that breaks
the monotony about every 2-3 minutes**. That is the visitors. They are flocks that fly a fixed route down the light
shaft, along the terraces under the ceiling and back up the shaft, well above everyone's head, and they touch nothing.

| visitor | bands | model | route | duration |
|---|---|---|---|---|
| 🦋 moth swirl | glow-worm, mushroom, waterfall, geode | 10 glowing moths spiralling around the route (radius 2) | down the light shaft, a loop over the pool and the top terrace, back up the shaft; 110 studs | 7 s (16 studs/s) |
| 🦇 bat swoop | waterfall, geode | 6 bats (body + flapping wings), strung out and offset around the route | down the shaft, the length of the cavern under the ceiling to the entrance and back, up the shaft; 309 studs | 6 s (51 studs/s) |

**Measured rarity:**

| measurement | where | result |
|---|---|---|
| raw clock, 20 h of play | `Visitors.spec` | 482 visitors = **one per 149.4 s** (0.402/min); launch-to-launch gaps **120.2-180.0 s**; never 2 at once |
| rest-toggle probe, 20 h of play | `Visitors.spec` | never rests **482** · toggles every 7 s **482** · rests 40 of every 150 s **482** (identical per hour of PLAY) |
| through the real client, chamber 8, 20 simulated minutes | `check_growacrystal_env` | **8-9 visitors** (one per 133-150 s; 8 runs in the build session, 8 in each of 6 more in the resume session), gaps inside 120-180 s, never a swoop and a swirl at once |
| the first band | `check_growacrystal_env` | 5 simulated minutes at chamber 1: **0** visitors |
| 10 minutes of Relax | `check_growacrystal_env` | **0** visitors; the next one came within one interval of play after waking |
| routes | `Grotto.spec` | 400 samples per route: inside the cavern (or up the light-shaft hole), **≥ 4 studs over a standing head**, enter and leave by the shaft (nothing pops into view mid-air), smooth (largest step < 3 studs per 1/400) |
| flocks and critters as drawn | `check_growacrystal_env` | every moth and bat inside the cavern and **≥ 3.5 studs** over a standing head (asserted), flock offsets included, across 20 minutes; the lowest measured was **4.9 studs** (5 of 5 runs, and 6 of 6 in the resume session) |
| ambient critters' height band | `check_growacrystal_critters` | critters born **on** their zone's floor and ceiling, the bob's phase stepped round the circle, 20 s at 30 fps: moths stay in **31.000-40.000**, bats in **34.000-42.000**, wisps in 21.5-46.98 (band 21-47). Without CavernArt's clamp a moth sinks to 30.49 and a bat to 33.22 (§12) |
| harmlessness | `check_growacrystal_env` | over about 35 simulated minutes the client **never wrote the character's velocity or `PlatformStand`** (sentinel values unchanged); every client part is anchored, `CanCollide`/`CanQuery`/`CanTouch` = false |
| hazards | `EnvConfig.spec` | `Config.Hazards == nil`; no band lists hazards |

### Harvest bursts and the beam of light

The server's State push says what a harvest rolled, after paying for it (`lastHarvest`, §5). The client draws it at
that socket, in `Config.TierColor[tier]`:

| tier | shards | ring | beam of light | flash | shake | card |
|---|---|---|---|---|---|---|
| Shard | 4 | – | – | – | – | – |
| Quartz | 6 | – | – | – | – | – |
| Amethyst | 8 | ✓ | – | – | – | – |
| Prism | 10 | ✓ | – | – | – | – |
| Legendary | 12 | ✓ | ✓ | ✓ | – | 🌟 LEGENDARY! |
| Mythic | 12 | ✓ | ✓ | ✓ | 0.5 | 💎 MYTHIC! |

Shards fly out and up for 1.1 s and fade. The ring expands from 2 to 11 studs over 0.7 s. The beam is a white-cored
cylinder with a halo in the tier colour, from the socket to the ceiling (checked to reach it within 0.6 studs), with
the only client light (a PointLight, brightness 3 → 0). It grows in 0.2 s and fades out by 2.5 s. When a crystal
refracted, the card's sub-line says "refracted from a Quartz seed ✨". Pooled: 12 shards, 1 ring, 1 beam.
`Grotto.spec` pins that effects only ever grow with the tier and that only Legendary and Mythic get the beam.

**The flash and the shake are rate-limited** (review round 1, finding 3, §13). A Legendary seed always refracts to
Legendary or Mythic, so a player harvesting a terrace of them got a flash on every click: three on screen at once, 73 %
opaque. Now the full-screen part (a 0.35 tint fading over 0.8 s, and Mythic's shake) plays at most once per
`Env.HarvestFlash.cooldown` = 2 s (`Grotto.flashDue`); the cooldown outlasts the fade, so two flashes are never on screen
together (`EnvConfig.spec`). Shards, ring, beam and card still play for **every** harvest. Measured
(`check_growacrystal_flash`): six Mythic harvests at 4 clicks/s give 1 flash, 1 shake, 6 bursts each at its own socket,
peak opacity 0.35; a Legendary 2 s later flashes again, one 1 s after that does not. The band fanfare for the Heart of
the Geode (a 0.4 flash, once per player) is not on this clock; a Legendary harvest within 0.8 s of buying chamber 8 can
overlap it once.

---

## 4. Rest: what "pause" means in Grow a Crystal

A Roblox server cannot stop the world for one player, and in this game it must not stop anything anyway: **crystals
grow on the server's clock** (`os.time()`), online and offline. So rest is a state the player is in, and it only
calms what exists to catch the eye:

* **🛋 Relax** (in the row under the HUD's header, a 44-px tap target on phones): your character **sits down**, the
  view **softens** (depth of field glides from the band's 0.1 to 0.35), the chip says `🛋 Relaxing — your crystals
  keep growing`, and **no visitor comes**. Their clock is frozen, never reset. Ambient moths, bats, wisps, the
  waterfall and the pulse carry on.
* **Waking up**: press **▶ Back**, or just move or jump. Pressed in mid-air, Relax is queued (`🛋 …`) and taken on
  landing, or forgotten after 3 s.
* **No idle rest** (`IdleSeconds = 0`). In an idle game, standing still *is* playing. An idle trigger would take the
  visitors away from exactly the players who watch the most, and nothing here can hurt an AFK player.
* Roblox's own idle disconnect (about 20 minutes with no input) still applies to a resting player, and the game cannot
  stop it. Nothing is lost: progress autosaves every 20 s and on leaving, and the crystals kept growing the whole time.

**Why it cannot be exploited:**

1. **There is nothing to dodge.** No round clock, no raid, no penalty. Growth is a timestamp difference on the
   server. The weekly Geode is keyed to server time. The leaderboard ranks `totalDust`, earned only by clicking mature
   crystals.
2. **The server never hears about rest.** The client fires no remote and sets no attribute (asserted, including a scan
   of the source for `FireServer`/`InvokeServer`/`SetAttribute`). Rest cannot speed growth up, pause it, or change a
   single number the server keeps.
3. **Toggling does not thin or bunch visitors.** Rest freezes their clock and never resets it: 482 visitors per 20 h
   of play whether the player never rests, toggles every 7 s, or rests 40 s of every 150 s. It would not matter if it
   did, because a visitor gives and takes nothing.
4. **The template's guard rails stay on.** `Rest.validate` refuses `WakeOnMove = false` and
   `BlockWhileThreat = false`. There are no threats here, so Relax is never held back by one; the rule is kept so a
   future hazard could not turn Relax into a panic button.

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| bands, lighting, pulse, scenery, critters, particles, visitors, bursts, beam, cards, chip, Relax | **client** (`Grotto.client` + `CavernArt`) | cosmetic and per-player (your cavern follows *your* chambers). Costs the server nothing and replicates nothing. |
| the harvest's result (`lastHarvest`) | **server** → client, in the existing State push | only the server knows the refraction roll. It is sent **after** the roll is paid and recorded, to that player only. |
| rest | **client** | it only pauses client visitors |
| the one State connection (`StateFeed`) | **client** | a dispatcher inside the client: it hands the same push the HUD always got to the cavern too. It fires nothing at the server (asserted by source scan in `check_growacrystal_queue`) and the server never requires it. |
| growth, harvest, dust, chambers, codex, geode, codes, saves, leaderboard, spawn | **server**, unchanged | authoritative, as before |

**Leak review.** The client reads its own plot's sockets (already replicated: `Socket_<UserId>_<id>`, named by the
server), its own character and camera, its own State push, and `Config`. `lastHarvest` is
`{ n, socket, seed, tier }` of a harvest that has **already happened and been paid** (`check_growacrystal_harvest`
asserts exactly those four keys, and across 16 harvests that the tier reported is the tier paid for). The player
already learns that tier from their dust and codex, so it reveals nothing new, and nothing about a future roll or
another player. The client creates only local parts in its own `workspace.CrystalLocalGrotto` folder, never in the
server's plot folders (asserted by name), all inside its own cavern's bounds (asserted). Spawn order
(`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame, and `check_crystal_spawn`
is green and unchanged.

**What other players see:** nothing of yours. Every plot is a sealed shell, and all of this is local to its owner.

**An existing exploit, found in passing, NOT caused or changed by this work (§11):** `grantHarvest` seeds the
refraction roll with `os.time()*1000 + socketId*977 + UserId`. A client that knows the server time can predict each
second's roll and click only on a Mythic second. That is the checklist's "replayable RNG" trap.

---

## 6. Budgets (measured, `check_growacrystal_env`)

Client-built only. The server's own cavern is on top of this. Counted in the real plot through the emulator in the
resume session: **155 parts at chamber 1 and 176 at chamber 8** (each purchase adds a chamber's sockets and removes
its rubble caps), always 10 PointLights and 2 dust emitters, plus one part per growing crystal. The build session's
"154" does not match this count (it did not say how it counted). The client numbers below were measured after 12 s at
every chamber count (10 half-lives, settled). The even chambers 2, 4 and 6 are the seams, where two bands are live at
once.

| chambers | band | local parts | emitters on (particles/s) | lights |
|---|---|---|---|---|
| 1 | Sunken Grotto | 5 | 1 (6/s) | 0 |
| 2 | Sunken Grotto › Glow-worm | 22 | 1 (5.5/s) | 0 |
| 3 | Glow-worm Hollow | 40 | 1 (5/s) | 0 |
| 4 | Glow-worm › Mushroom | 50 | 2 (8/s) | 0 |
| 5 | Mushroom Terraces | 60 | 2 (11/s) | 0 |
| 6 | Mushroom › Waterfall | 68 | 2 (12/s) | 0 |
| 7 | Waterfall Chamber | 75 | 2 (16/s) | 0 |
| 8 | Heart of the Geode | 96 | 2 (18/s) | 0 |

| metric | measured peak | where | budget (`Config.Budget`) |
|---|---|---|---|
| local parts | **129** (121-129 over 8 runs, and again 121/129 over 6 resume runs: 121 when the flock is the 10-part moth swirl) | chamber 8, a bat swoop in flight **and** a Legendary burst with its beam | 150 |
| scenery elements (all pieces) | 74 | layout | 80 |
| particle emitters on | 2 | every seam | 2 (`MaxWeatherEmitters`, enforced by `EnvBands.capRates`) |
| particles per second | 18 | chamber 8 | 30 (enforced) |
| point lights | 1 | the beam, for 2.5 s | 1 |
| visitors at once | 1 | | 1 |

By construction, the worst case is 80 scenery + 21 critters + 18 visitor parts + 12 shards + ring + beam + 4
weather hosts = 142 ≤ 150 (`EnvConfig.spec`).

**How it stays cheap.** Pieces are built the first time their weight rises above 0, and each element is unparented
while its share of the weight is 0. Pieces, the pulse and fades update at 10 Hz, and a transparency is written only
when it moves by more than 0.01. Critters are pooled per kind, at most one spawned per kind per frame, and faded in
and out. There is one pooled flock per visitor kind, parented only while it flies. There is one host part per
particle kind, created lazily; at most 2 are enabled, the strongest by rate, with the summed rate capped. Lighting is
written ≤ 10×/s, only on change. These are part and emitter counts, not frame time; phone frame time is on the Studio
list.

---

## 7. Gates

Every gate for this game, run on the final tree (bundle `robloxemu/build/grow-a-crystal.luau` rebuilt from it). The
runner checks each process's exit code, not just its last line. That mattered once: the HUD gate printed nothing after
"loaded" and would have passed a `tail -1` reading (§7.2).

Final run: review round 1 session, 2026-09-24 (§13), on the bundle rebuilt from the final tree (md5 `e53f03c4…`; the
resume session's was `749f1a1e…`). **All 30 suites green: 16 specs, 1 144 assertions; 14 headless checks, 870
assertions plus 2 whole-screen PASS verdicts.** Rows marked *(R1)* are new or changed in that session.

| suite | what it pins | result |
|---|---|---|
| `tests/Rng.spec` | deterministic LCG (pre-existing) | 56 / 0 |
| `tests/Rarity.spec` | refraction roll (pre-existing) | 12 / 0 |
| `tests/Growth.spec` | offline growth (pre-existing) | 20 / 0 |
| `tests/Economy.spec` | harvest value, shop (pre-existing) | 36 / 0 |
| `tests/Geode.spec` | weekly geode (pre-existing) | 22 / 0 |
| `tests/Codex.spec` | codex (pre-existing) | 8 / 0 |
| `tests/Codes.spec` | codes (pre-existing) | 12 / 0 |
| `tests/Cavern.spec` | the server's cavern layout (pre-existing) | 67 / 0 |
| `tests/responsive.spec` | HUD layout maths (pre-existing) | 70 / 0 |
| `tests/EnvBands.spec` | band lookup + blend, glide, `capRates` (template, verbatim) | 124 / 0 |
| `tests/Rest.spec` | rest rules (template, verbatim) | 55 / 0 |
| `tests/Visitors.spec` | the rare-visitor clock, rarity, rest-toggle probe | 34 / 0 |
| `tests/Grotto.spec` | progress, sockets → chambers, bursts, pulse, layout, zones, routes; *(R1)* + `flashDue`: at most one flash per cooldown, its edges, NaN (was 143) | 157 / 0 |
| `tests/EnvConfig.spec` | the shipped `Config.Env` / `Visitors` / `Rest` / `Budget`; *(R1)* + `Env.HarvestFlash`: a tint, it fades, the cooldown outlasts the fade (was 430) | 435 / 0 |
| `tests/Pacing.spec` | when a player reaches each look (`IdleModel`); the economy FINDING | 12 / 0 |
| `tests/StateFeed.spec` *(R1)* | one State connection per remote, a late subscriber handed the latest payload, either order, arguments intact, every call through the spawner | 24 / 0 |
| `robloxemu/check_crystal` | HUD fit, panel overlap on (pre-existing) | PASS |
| `robloxemu/check_crystal_sockets` | sockets in the world, clicks plant (pre-existing) | 36 / 0 |
| `robloxemu/check_crystal_spawn` | spawn order, facing (pre-existing; `SPAWN-ORDER.md`) | 30 / 0 |
| `robloxemu/check_growacrystal_harvest` | `lastHarvest` in the State push, nothing else | 23 / 0 |
| `robloxemu/check_growacrystal_env` | the whole client glue, budgets, rarity, rest, leaks | 158 / 0 |
| `robloxemu/check_growacrystal_hud` | HUD fit with both clients, every drawer open | PASS |
| `robloxemu/check_growacrystal_row` | the chip and Relax button against every HUD element | 389 / 0 |
| `robloxemu/check_growacrystal_join` | a slow profile load: one quiet card, glide, no replayed burst | 21 / 0 |
| `robloxemu/check_growacrystal_race` | the join push missed: chambers from the sockets | 12 / 0 |
| `robloxemu/check_growacrystal_critters` | critters held to their zone's height band (new, resume session) | 12 / 0 |
| `robloxemu/check_growacrystal_queue` *(R1)* | Roblox's queue rule replayed, the cavern script first: the HUD shows the saved profile with no click, one connection, later pushes reach both | 27 / 0 |
| `robloxemu/check_growacrystal_queue_hudfirst` *(R1)* | the same with the HUD first and only 2 chambers of sockets in the world: the cavern gets the push too | 13 / 0 |
| `robloxemu/check_growacrystal_redeem` *(R1)* | the code answer on 5 phone viewports and 2 mouse windows: size, place, nothing covered, timing; the box's hint | 131 / 0 |
| `robloxemu/check_growacrystal_flash` *(R1)* | six Mythic harvests at 4 clicks/s: one flash, one shake, six bursts; the cooldown | 18 / 0 |

**Stability.** The client uses `Random.new()`, which the emulator does not seed, so the headless numbers can move
between runs. In the resume session `check_growacrystal_env` ran 8 times (the gate run at the start, the 6 measuring
runs in §3 and §6, the final gate run). `harvest`, `join`, `race`, `check_crystal_sockets` and `check_crystal_spawn`
ran 5 times each (both gate runs plus 3 repeats), and the two HUD gates and `row` twice. Every run gave the same
counts. `check_growacrystal_critters` uses no random numbers at all; its 3 repeat runs printed byte-identical output.
In the review round 1 session the four new checks ran 5 times each (2 gate runs and 3 repeats) with identical counts
and, for `flash`, identical measurements. Compilation: `loadstring` over every module in the bundle, 21 of 21 (with
`StateFeed`), 0 errors (luau-analyze is unavailable, §7.2).
Spawn order: `check_crystal_spawn` is green and `Main.server.luau`'s spawn code is untouched (the server diff is the 9
`lastHarvest` lines), so the `SPAWN-ORDER.md` fix stands.

### 7.1 Mutation sweep

**Result (review round 1 session, §13): 75 mutations, the resume session's 49 re-run on the new tree plus 26 new.
All 69 real mutants KILLED, and all 6 controls SURVIVED, as they must.** Bundle proof held for **75 of 75**, and every
file was restored byte-identical (75 of 75). The harness is `gac_r2/sweep.py` in the session's scratchpad, not in the
repo (log `sweep_full.log`, results `sweep_results_full.json`, mutation list `mutations.json` built by
`make_mutations.py`, which refuses an anchor that does not occur exactly once).

After the full sweep, `check_growacrystal_queue` was tightened: the queue is now flushed to the cavern script before
the HUD starts, which is the reported case, so the HUD has to be handed the push late. The 6 mutants that check
touches (F1-F4, K5, A5) and a control were re-swept against the final tree (`sweep_queue_recheck.log`). All 6 were
KILLED and the control SURVIVED; `queue` now also kills F1.

The resume session's round 2 (49 mutations, 46 killed, 3 controls survived, in `gac/`) is kept for its history. The
harness never touches the real tree:
* it works on a fresh scratch copy (sources, tests, the 14 checks, `wrap.py` and `emu`), verified byte-identical to
  the real files except `emu`, which is copied but not compared, with its bundle identical to the real one once paths
  are normalised;
* each mutation replaces exactly one occurrence of its text (the run refuses otherwise);
* the bundle is rebuilt and **proved to contain the mutation**: the mutated bundle must equal the baseline bundle
  with the same single replacement, and the replaced text must occur once in the baseline;
* all 30 suites run (16 specs + 14 checks, exit codes, 300 s timeout each);
* the original bytes and the baseline bundle are restored and their md5s re-checked.

The baseline was green before the first mutation. After the last, the copy was again identical to the real tree
and all 30 suites green. The old mutants are killed by the same suites as in round 2, plus four new catches:
* K2 (the first card is a fanfare) is now also caught by `flash`;
* K5 (a repeated push replays the burst) and A5 (shards never leave) by `queue`;
* H1 (the phone code drawer stacked again) by `redeem`.

| id | what the mutation breaks | killed by |
|---|---|---|
| V1 | rest does not freeze the visitor clock | Visitors.spec |
| V2 | a visitor in flight neither blocks nor finishes | Visitors.spec, env |
| V3 | a quiet band stores a backlog | Visitors.spec |
| V4 | rest RESETS the visitor clock | Visitors.spec |
| G1 | progress keeps fractions | Grotto.spec |
| G2 | glow-worms may hang in the light-shaft hole | Grotto.spec |
| G3 | geode prisms down on the pool walkway | Grotto.spec |
| G4 | giant mushrooms in the socket zone | Grotto.spec |
| G5 | half-weight glow-worms bunch at one end | Grotto.spec |
| G6 | a chamber counts from its FIRST socket | Grotto.spec |
| G7 | `routePoint` does not clamp u | Grotto.spec |
| G8 | `burst` hands out Config's own table | Grotto.spec |
| G9 | the bat swoop dips below head height | Grotto.spec, env |
| C1 | visitors in the first band | EnvConfig.spec, env |
| C2 | idle rest on (visitors vanish for watchers) | EnvConfig.spec, env, join |
| C3 | looks snap instead of gliding (`Env.HalfLife = 0`) | env, join |
| C4 | Legendary loses its beam | Grotto.spec, env |
| C5 | Prism gets a beam | Grotto.spec |
| C6 | visitors twice as often | EnvConfig.spec, env |
| K1 | client lighting snaps | env, join |
| K2 | the first card is a fanfare | env, join, race, *(R1)* flash |
| K3 | the first card does not wait for the count to settle | race |
| K4 | sockets ignored (the join-push race) | race |
| K5 | a repeated push replays the burst | env, join, *(R1)* queue |
| K6 | resting does not pause visitors | env |
| K7 | Relax does not sit | env |
| K8 | moving never wakes | env |
| K9 | no soft focus while resting | env |
| K10 | a malformed harvest record reaches `socketTop` | join |
| K11 | no teaser card | env |
| K12 | weather budget not enforced (`capRates` skipped) | env |
| K13 | visitors fly in every band | env |
| A1 | a piece shows all or nothing | env |
| A2 | critters drift out of their height band (the clamp removed) | **critters** (survived round 1) |
| A3 | the flock spreads 8× wider | env |
| A4 | the beam stops short of the ceiling | env |
| A5 | shards never leave | env, join, *(R1)* queue |
| A6 | client parts are queryable (re-anchored) | env |
| A7 | the beam's light stays on | env |
| A8 | a flock never leaves | env |
| A9 | wisps never start again from the water | env, **critters** (new) |
| A10 | the height band lets critters 1 stud under its floor | **critters** only (new) |
| S1 | the server reports the SEED tier, not the roll | harvest |
| S2 | the harvest counter never grows | harvest |
| S3 | the State push drops `lastHarvest` | harvest, env |
| H1 | the phone code drawer stacked again (Redeem under the thumbstick) | hud, *(R1)* redeem |
| CTRL-A | *control*: the waterfall teaser's wording | survived ✓ |
| CTRL-B | *control*: a moth one shade warmer | survived ✓ |
| CTRL-C | *control*: a wisp one shade less blue (new) | survived ✓ |
| F1 *(R1)* | a late subscriber is NOT handed the latest payload | StateFeed.spec, queue, queue_hudfirst |
| F2 *(R1)* | every `StateFeed.of` makes a new feed and connection | StateFeed.spec, queue, queue_hudfirst |
| F3 *(R1)* | the HUD connects to State directly again | queue, queue_hudfirst |
| F4 *(R1)* | the cavern connects to State directly again | queue, queue_hudfirst |
| F5 *(R1)* | dispatch iterates the live subscriber list (no snapshot) | StateFeed.spec |
| F6 *(R1)* | dispatch bypasses the spawner (one broken subscriber stops the rest) | StateFeed.spec |
| F7 *(R1)* | a feed without a spawner is accepted | StateFeed.spec |
| F8 *(R1)* | the replay drops every argument after the first | StateFeed.spec |
| R1 *(R1)* | phone: the answer goes back into the narrow button | redeem |
| R2 *(R1)* | phone: the box and button stay tappable under the answer | redeem |
| R3 *(R1)* | the row never comes back after the answer | redeem |
| R4 *(R1)* | phone: the long "Enter code..." hint in the narrow box | redeem |
| R5 *(R1)* | phone: the answer only a third of the row wide | redeem |
| R6 *(R1)* | an older answer's timer cuts a newer answer short | redeem |
| L1 *(R1)* | `flashDue` always true (every harvest flashes) | Grotto.spec, flash |
| L2 *(R1)* | `flashDue` excludes the cooldown's own edge | Grotto.spec |
| L3 *(R1)* | the client never records when it flashed | flash |
| L4 *(R1)* | the Mythic shake is not gated with the flash | flash |
| L5 *(R1)* | a cooldown shorter than a flash's fade (0.5 s) | EnvConfig.spec, flash |
| L6 *(R1)* | the burst itself waits for the flash cooldown | flash |
| L7 *(R1)* | the flash ignores the configured alpha (0.6) | flash |
| L8 *(R1)* | `flashDue`: a NaN last time silences the flash | Grotto.spec |
| L9 *(R1)* | `flashDue`: the session's first flash never comes | Grotto.spec, env, flash |
| CTRL-D *(R1)* | *control*: the answer label's corner radius 6 → 8 | survived ✓ |
| CTRL-E *(R1)* | *control*: the spawner assert's wording | survived ✓ |
| CTRL-F *(R1)* | *control*: flash cooldown 2 → 2.5 s (still ≥ the fade, ≤ 5) | survived ✓ |

(Specs are `tests/*.spec.luau`; the short names are `robloxemu/check_growacrystal_<name>.luau`.) Two mutants are
caught only by the resume session's new check: A2 (the round 1 survivor) and A10. That is the gap it closes: the
older suites hold critters "3.5 studs over a head", which leaves 1.4 studs of slack under the lowest measured moth
or bat. The zone floors that `Grotto.spec` pins in the layout were never checked while the critters actually fly.

### 7.2 Things that went wrong on the way (kept, because they are what the gates are for)

* **The HUD gate was red and looked fine.** `check_growacrystal_hud` failed in its warmup: the first title card now
  waits for the count to settle, and the warmup waited 0.33 s. The failure went to stderr before the progress lines,
  and a `tail -1` read showed "client loaded". The gate runner now checks exit codes.
* **The first glide assertion measured quantisation, not a cut.** Ambient is written in whole 0-255 steps, so a 3-step
  change "moved 33 % in one frame". Glide is now measured on continuous values (Brightness, FogEnd), with colours held
  to one step.
* **A name collision in the leak check.** The giant mushrooms were called `Shroom_*`, the same prefix as the server's
  own small mushrooms, so the "nothing of ours in the server's plots" check flagged the server's parts. They are now
  `Giant_*`.
* **The visitor clock first counted only between flights.** A flight that ended during a rest then cost no play time,
  so toggling rest gave 2 % more visitors per hour (471 vs 461 in the spec). It now measures launch to launch, and the
  three probe patterns give 482/482/482.
* **The race in §2** was found by reading the client against Roblox's queueing rule, not by any check. Now it is
  `check_growacrystal_race` (watched failing 8 of 12 before the socket source existed).
* `luau-compile` and `luau-analyze` disappeared from the shared scratchpad mid-session (the folder was recreated with
  only `luau.exe`), and fetching them again needs the owner's go. So compilation was checked by `loadstring` on every
  module in the bundle, and **luau-analyze was not run**. They were still absent (not on PATH either) in the resume
  session, which re-checked compilation the same way: 20 of 20 bundled modules, 0 errors.
* **The first sweep had a survivor nobody followed up** (resume session). A2 removes CavernArt's height clamp, and it
  passed all 24 suites. The only height rule was `check_growacrystal_env`'s "3.5 studs over a head", and the lowest
  critter there is 4.9 studs up. Without the clamp a critter's bob, a bounded sine velocity, takes it at most 0.5
  (moth) to 0.8 (bat) studs out of its zone, so that rule could never see it. The zone floor is the actual contract:
  `Grotto.spec` pins the moth and bat floors at y ≥ 30, above every head (wisps rise out of the pool, below that). The
  new `check_growacrystal_critters` asserts it directly and deterministically. It failed 2 assertions on the A2 mutant
  (a moth at 30.49 and a bat at 33.22, under floors of 31 and 34) and passes 12 of 12 on the real code.
* **One mutation had not proved it reached the bundle.** A6's replaced line, `p.CanQuery = false`, occurs twice in
  the bundle (CavernArt and the older `Fx.luau`), so the proof "mutated bundle = baseline with that one replacement"
  could not hold, although the mutant was killed. The resume sweep anchors it on CavernArt's four-line property block,
  which occurs once.
* **The shot list was never checked against the geometry** (§9, §12). A probe of the real layout found the promised
  side-wall prisms 69-73° off-axis, the Legendary socket 51° below the frame, and the wide camera inside the light
  shaft's outer cylinder.

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Every band's look**: the lighting numbers per band. Does the Cozy → geode grade read as "richer", or just
   darker/pinker? Does the glow-worm band's darker ambient still let the sockets read?
2. **Glow-worms**: do 0.08-stud Neon threads with 0.45-stud beads read as glow-worms on a phone, or disappear? Is 16
   strands enough to feel like a starry ceiling? (`Config.Env.Layout.Glowworms`; the budget has 6 parts of room.)
3. **Giant mushrooms**: Ball caps (Roblox cannot flatten a Ball) with a wider gill ring. Mushroom or lollipop? They
   stand at |x| = 29.5, against the walls and away from every socket. Walking along the wall passes through a stem
   (non-collidable, like the server's own boulders); does that look wrong?
4. **The waterfall**: a translucent Neon sheet plus core, foam and spray discs, and mist particles. Water, or a glowing
   curtain? Does it need a texture or a sound (assets needed)?
5. **Geode prisms and seams**: Neon blocks jutting from the walls at 25-55°. Crystals, or sticks? Do they bloom out
   under bloom 1.3?
6. **The geode pulse**: breathing, or flicker? (Depth 0.35 at 7 s in the last band.)
7. **Bats**: body + two flapping wing blocks. Do they read as bats at 51 studs/s? Is the swoop exciting or startling?
   The moth swirl at 16 studs/s: a swirl, or a smear?
8. **The Legendary/Mythic beam**: brightness, width, the one PointLight, the flash strength. Celebratory or blinding?
9. **Clicks through scenery**: every client part is `CanQuery = false`. Confirm a click on a crystal behind a
   glow-worm thread or a mushroom cap still reaches its ClickDetector.
10. **Relax**: `Humanoid.Sit = true` from the client with no seat. Does it sit and replicate? Does WASD produce
    `MoveDirection` while seated (that is what wakes)? Does jump stand up? The soft focus strength.
11. **The row under the HUD's header** on a real phone: notch/safe area, the chip text size in its narrow form
    (portrait phones stack the chip under the button), and the 🛋 and ✨ emoji in `TextScaled` labels.
12. **The one-row code drawer** (the HUD fix): is a 45-px "Redeem" button readable on a 640×300 phone? And the
    answer to a code, which on a phone now takes the whole row for 2 s (§13): does "Invalid code" read at the
    estimated 20 px (13 px in portrait), and is it obvious that the box comes back?
13. **Frame time** on a mid/low phone in the Heart of the Geode with all 48 crystals growing, a flock and a beam.
14. **Title cards**: quiet first card, teasers, the geode fanfare (flash + FOV punch). Welcome or noisy?
15. **The join**: on a real server, does the cavern reach the right look before the player notices (sockets and the
    push both), and does the first card ever show the wrong band on a slow phone connection?
16. **Particle volumes**: drips across the whole ceiling at 5-6/s, spores rising through the terraces. Visible, or lost?
17. **StreamingEnabled**: the chamber count is read from the player's own sockets. Every socket is within about
    140 studs of the player, so it should always be streamed in. If the place streams, confirm that a returning
    player's cavern still reaches the right look without a State push.
18. **The light shaft between camera and geode** (new, from the shot probe). Any view of the geode's back wall from
    the front of the pool looks through the shaft's two Neon cylinders (0.82 and 0.93 transparency) under bloom 1.3.
    A player who walks up the terraces to the pool sees the prisms that way. Do the prisms behind the column still
    read, or does it wash them out? Shot 4 and its through-the-light variant are the two framings to compare.
19. **The hero wide shot's terraces** (§9 shot 4, wide variant). From the back corner the stairs descend away at
    nearly the angle of the view, so the eight crystal rows stack along the horizon (v −5..+1). Rich, or one smear?
    If it is a smear, a lower aim point cannot help (the camera height sets it), and the camera is already 6 studs
    under the ceiling. Try shot 1's direction instead, from the apron with the aim lowered.
20. **The shot list itself.** Every set-up in §9 was checked for geometry only: in frame, not blocked, camera not
    inside a part, how much of the shaft it looks through. Whether each one is a good picture is the photographer's
    call.
21. **The join push on a real server** (new, review round 1). The fix rests on Roblox's queue rule as the repo
    understands it (a push fired before any listener goes to the first connection). With one shared connection it
    works whether the queue goes to the first connection or to every one, but it has only been replayed in the
    emulator. Rejoin with a saved profile (dust, seeds, codex, chambers 8) and stand still: the HUD must show the
    saved dust, seed counts and prices, and the cavern the Heart of the Geode, before any click. Try it a few times;
    the script start order can differ between joins.
22. **The harvest flash cooldown** (new, review round 1): harvest a terrace of Legendary crystals quickly. One tint
    per 2 s: still a celebration, or does the second and third Legendary now feel flat? The cooldown is
    `Config.Env.HarvestFlash.cooldown`.

---

## 9. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *This recipe has not been tried in Studio. Verify step 2 before relying
on the rest.*

1. **Build a place that has the new cavern.** In `grow-a-crystal/`, run `rojo build -o GrowCrystal-shots.rbxlx` and
   open that file (`*.rbxlx` is git-ignored). Do **not** reuse `GrowCrystal.rbxlx`: it was built on 17 Sep, before
   any of this, and its `.lock` shows a Studio session had it open.
2. **No saves.** *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server then warns
   "datastore unavailable … progress will NOT be saved" and runs anyway (`tryStore`). Nothing reaches the live
   DataStore or the leaderboard.
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`, and before pressing Play. Nothing is
   published from Studio (`publish_crystal.bat` builds from `src/`):
   * `Economy.StartDust = 10000000`: a fresh profile can buy every chamber and any seed;
   * `Growth.SecondsPerStage = { 1, 1, 1, 1, 1, 1 }`: with `StageCount = 4`, every crystal matures in 4 s;
   * only if you want a visitor in shots 3 or 4: `Visitors.IntervalMin = 8`, `Visitors.IntervalMax = 10` (valid: both
     kinds fly for less than 8 s).
4. **Play solo.** You get `Plot_0`, whose origin is (0, 0, 0), so **every coordinate below is a world coordinate**.
   Buy chambers one at a time with the HUD; each purchase glides the cavern into its next look over about 4 s. Shoot
   in the order below, going up, because chambers cannot be sold: **chamber 3** → shot 1; **chamber 5** → shot 2 (and
   shot 5 here if you want its violet light); **chamber 7** → shot 3; **chamber 8** → shots 4, 4-wide, 5 and 6.
5. **Fill the sockets with colour before each shot**: select a seed row (Amethyst, Prism and, from chamber 5,
   Legendary look best), click every empty socket, and wait 4 s so the crystals stand full-size and sparkle.
6. **Clean frames** (command bar, Client context):
   `local g = game.Players.LocalPlayer.PlayerGui; g.CrystalHud.Enabled = false; g.CrystalGrotto.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   For shot 5 keep `CrystalGrotto` on (the "🌟 LEGENDARY!" card lives in it) and hide only `CrystalHud`. Place the
   camera exactly with (Client context)
   `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable; workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(FROM), Vector3.new(AT))`,
   and give control back with `workspace.CurrentCamera.CameraType = Enum.CameraType.Custom`.

**How every set-up below was checked (resume session).** A probe ran each camera against the real `Cavern.build`
(all 149 server-built parts, orientation included) and `Grotto.layout`. For each one it checked that the camera is
not inside any part. It measured how far the centre line of sight runs through the light shaft's two Neon cylinders
(inner: radius 6, transparency 0.82; outer: radius 12, transparency 0.93; both from y 20.8 to 44.8 around (0, 119)).
For every named thing, it checked whether it falls inside the frame and whether an opaque server part (rock, deck,
tread, wall, shelf) stands between it and the camera. The frame is Roblox's default 70° vertical field of view at 16:9,
so ±51° × ±35°. `h`/`v` below are degrees right of and above the frame's centre; **screen right is −X when you look
into the cavern (+Z)**. The first shot list failed this probe in five of its seven set-ups (§12), and none of the
set-ups below does. What the probe cannot judge (bloom, the glow columns, whether it is pretty) is in §8.

1. **"A ceiling of glow-worms"** (chamber 3: ✨ Glow-worm Hollow at full strength, no mushrooms yet). Walk the avatar
   up to terrace 2 and stand at about (6, 6, 30), facing the entrance. Camera from the entrance apron, 2 studs in
   front of the front wall, **(−2, 8, −12) → (3, 28, 60)**. In frame:
   * the upper half is glow-worm beads on their threads, from the top edge (beads at (−4, 38, 14) and
     (−2, 40, 17), v +32..34) back to (3, 40, 70) and (12, 40, 72) just above the centre;
   * the light shaft's glow at the far end, just under the centre (v −5);
   * the crystal rows of terraces 1 and 2 across the lower third, from socket 7 at the right edge (h +38) to socket
     12 at the left (h −34); terrace 0's middle crystals sit at the bottom edge;
   * the avatar small, a little left of and below the centre (h −7, v −14).

   The bead at (−12, 39, 57) sits just behind a server stalactite and may be half-hidden. The two beads over the
   apron are behind the camera.
2. **"Mushroom Terraces"** (chamber 5: 🍄 at full strength; chamber 6 starts tinting it toward the waterfall's aqua).
   Camera over the apron on the −X side, **(−20, 20, 8) → (29.5, 14, 55)**, looking across and up the cavern at the
   +X wall. In frame:
   * the four +X-wall giant mushrooms receding up the terraces from left to right: caps at (29.5, 11.5, 20) h −30,
     (29.5, 13.8, 33) h −17, (29.5, 24.5, 72) h +9 and (29.5, 28.2, 85) h +14, all near the horizon line (v −6..+10),
     gill rings glowing;
   * spores in the air;
   * the crystal rows of terraces 1-4 stepping up in the lower half.

   Terrace 0 is below the frame. The two −X-wall mushrooms are outside it on the right.
3. **"The waterfall"** (chamber 7: 🌊). Camera over the top terrace (floor y 21), **(10, 27, 96) → (−18, 30, 127)**.
   In frame:
   * the waterfall in the middle, pouring from the back ceiling at x = −18 (top v +16) into the pool (foam and
     mist v −11..−13);
   * the glowing pool just left of its foot;
   * the light shaft on the **left** (h −18);
   * bats under the ceiling (wait for a swoop, or use the visitor override in step 3).

   The line of sight crosses 18 studs of the shaft's faint outer glow, not its inner column.
4. **"Heart of the Geode"** (chamber 8: 💎). Camera over the top of terrace 6 (floor y 21) on the −X side,
   **(−20, 28, 90) → (−4, 40, 133)**. In frame, **all ten** crystal prisms:
   * the seven on the back wall in a row across the upper middle (v −4..+2), from prism 1 at x −23 (h +24) to prism
     10 at x +24 (h −26);
   * the two on the −X side wall high on the right (h +48, v +18..+32);
   * the one on the +X wall at the left edge (h −47).

   Also in frame:
   * the waterfall right of the centre (h +16..+19, from v +8 down to −24);
   * the light shaft left of the centre (h −14), with wisps rising in it;
   * the pool in the lower-left corner;
   * sparkle, and the purple grade at its strongest.

   The centre line misses the inner shaft column. Prisms 7 and 8 are seen through 9-11 studs of it, and every other
   prism is clear.
   * **Through-the-light variant** (the first list's framing, kept as an alternative):
     **(0, 24, 104) → (−2, 38, 133)** from the front of the pool ring. The light column fills the middle of the frame
     (13 studs of the inner column on the centre line). Prisms 4, 5 and 7 are seen through it, the side-wall prisms
     are **out** of frame (69-73° off-axis), and the waterfall is on the **right** (h +32). Use it only if the column
     reads as magic rather than haze.
   * **Wide variant, the store-page hero**: from the back corner over the pool ring's +X side, 6 studs under the
     ceiling, **(22, 38, 128) → (−4, 6, 20)**, looking back down the whole cavern. In frame, with a clear line to
     every one:
     * all six giant mushrooms, the +X wall's on the right (h +17..+23) and the −X wall's on the left (h −18..−23);
     * a crystal row on every terrace from 0 to 7, stacked along the horizon (v −5..+1);
     * glow-worms across the upper third (v +16..+18);
     * the light shaft at the left edge (h −51) and the pool in the lower-left corner.

     The first list's wide camera, (0, 25, 130), sat **inside** the shaft's outer cylinder, saw the whole cavern
     through 12 studs of the inner column, and had the terrace edges hiding the terraces behind them from that height.
5. **"A Legendary refracts"** (chamber 5 or later: Legendary seeds unlock at chamber 5). Stand at the spawn,
   (0, 4, −6); socket 9 is 24.3 studs away, inside the 32-stud click range. Camera above the apron,
   **(6, 12, −12) → (−3.8, 20, 18)**. Select **Legendary**, click socket 9 at (−3.8, 3, 18) on terrace 1, wait 4 s,
   then **click the crystal on screen** (below the centre, v −25). A Legendary seed always refracts to Legendary or
   Mythic, so the beam always fires. In frame, all clear:
   * the socket and its expanding ring (v −29..−30);
   * shards flying up to v −18;
   * the gold (or magenta) beam from the socket to the ceiling (top v +31);
   * the "🌟 LEGENDARY!" card and the flash.

   The avatar at the spawn is below the frame (v −53 and lower). The beam lasts 2.5 s, so take a burst of captures,
   then replant for another try. The first list's camera, (6, 6, 4), had socket 9, and with it the ring and the
   shards, 51° below the frame's centre.
6. **"Relax by the pool"** (chamber 8; if you used the visitor override, it can stay: Relax holds visitors off
   either way). Walk to the front of the pool ring at about (−4, 21, 106) (flush with the top terrace), face the
   pool (+Z) and press **🛋 Relax**. Camera behind and above the avatar, **(−9, 27, 97) → (0, 28, 125)**. In frame:
   * the seated avatar left of and below the centre (h −11, v −24), looking into the light column;
   * the column just left of the centre, with wisps rising in it;
   * the waterfall on the right (h +34);
   * the soft focus on.

   The centre line crosses 11 studs of the inner column, on purpose: the avatar is a silhouette against the light.
   Keep the Grotto row visible for one variant so the "🛋 Relaxing — your crystals keep growing" chip is in the
   picture.

---

## 10. Notes for the next game, and where this one differs from the template

* **The progress value can be discrete.** Chambers are whole numbers, so the smooth part is the time glide
  (`approach`) and the `fade` window only decides how far one purchase moves the look (fade 2 = half-way). Blend by
  it, name bands by `indexAt`, and make every step change something (`EnvConfig.spec` asserts that).
* **A value pushed over a remote can be missed.** When two LocalScripts listen to the same RemoteEvent, the queued
  events before the first connection go to one of them only. Protecting only the new script is not enough: the build
  session read the chambers from the world for the cavern and left the HUD, the script that had always owned the
  push, able to lose it (review round 1, §13). Give each remote **one** client connection and let every script
  subscribe (`StateFeed.luau`, which hands a late subscriber the latest payload), or keep the old owner as the only
  listener and pass payloads on (`lost-found-depot/src/shared/StateCache.luau`). Test it by replaying the queue rule
  in both start orders (`check_growacrystal_queue*.luau`). Reading progress from the world stays a good belt, and
  settle before the first announcement.
* **Check every text a narrow control can show, not only its label.** The one-row code drawer kept its button a
  thumb wide, and the button also shows the server's answer; "Invalid code" came out about 6 px (§13). Measure the
  estimated TextScaled size of each string at each phone viewport.
* **A celebration that can repeat needs a clock.** "Rare" by tier is not rare by frequency once a player can buy the
  seed that guarantees the tier (§3).
* **Hazards are optional; the clock is not.** `Visitors.luau` is the template's hazard clock without the hazard. Keep
  it for any game where knocking the player around would be punishment rather than play.
* **Harmless things still need rules**: routes above heads, inside the level, entering and leaving through an
  opening; no writes to the character (sentinel-checked).
* **Idle games: no idle rest.** Standing still is playing.
* **Every glowing element breathes with one pulse** whose depth grows by band. It is cheap and does the most for
  "alive".

---

## 11. Not done / open

* **Review round 1 is closed; a second look at its fixes is not done.** An independent adversarial reviewer ran on
  2026-09-24 and found three defects; all three are fixed and tested (§13). The fixes themselves (`StateFeed`, the
  phone code answer, the flash cooldown) have been checked by their author's own tests and mutation sweep, not by a
  second reviewer. The reviewer found the server diff, the `lastHarvest` leak argument, the rest rules, hazards and
  budgets clean.
* **Owner decision: the economy (§2).** At luck 0 every seed returns less than it costs on average (Shard 78 %,
  Legendary 6 %). A player who skips the codes never owns chamber 2, and so never sees anything past the first band.
  Not changed here: tuning the economy of a live game is the owner's call. The cheapest fix to evaluate is Shard
  DustValue 1 → 2 (or SeedCost 10 → 7) and re-running `Pacing.spec`.
* **Found in passing, not changed: the refraction roll is predictable** (§5). The seed is
  `(os.time()*1000 + socketId*977 + UserId) % 2147483647`, all known to the client. An exploit script can click only on
  seconds that roll Mythic, and the leaderboard is `totalDust`. The checklist's fix is to mix a per-session,
  server-only salt into the seed. That is a server change, so not in this work.
* **luau-analyze was not run** in any session (the binary is absent, §7.2); compile was verified by `loadstring`.
* **The shot list is geometry-checked, not seen** (§9, §8 items 18-20).
* **The join fix is proved in the emulator only** (§8 item 21): the queue rule is replayed there, not observed on a
  real server.
* Not committed, not pushed, not published. Studio not opened.
* §8 in full.

---

## 12. Resume session (2026-09-24): what was checked, found and changed

The build session was cut off by a usage limit after its mutation sweep and before it wrote §7. This session took
nothing on trust:

**Re-read, file by file**:
* every new file: `Visitors`, `Grotto`, `CavernArt`, `Grotto.client`, the six new specs, `IdleModel` and the six
  `check_growacrystal_*` checks;
* every edited one, through `git diff`: `Config` (+180 lines, cosmetic tables only), `Main.server` (+9 lines, the
  `lastHarvest` record), `Hud.client` (the one-row code drawer), `CLAUDE.md`, `README.md`;
* the template copies, compared by md5 with `plus1-jump`: `EnvBands` and `Rest` (sources and specs) are identical.

No half-written code, no TODO, and no defect in the game source. The client:
* fires no remote and adds none;
* reads only its own `Socket_<UserId>_*` parts;
* never writes the character's CFrame or velocity;
* builds only anchored, non-collidable, non-queryable, non-touchable local parts in its own folder.

Every frame is wrapped so an error stops the visuals, never the game.

**Re-ran, before touching anything**: the bundle rebuilt byte-identical to the one on disk (md5 `749f1a1e…`), all 24
suites that existed then were green, and every number this document quotes from them (482 visitors, 7.0 % glide,
121/129 peak parts, 18 particles/s, 4.9 studs, the pacing table) was re-printed and matched.

**Found and fixed (tests and docs only; no game source changed)**:
1. **The sweep's one survivor, A2**, had not been followed up: the critter height clamp could be deleted and
   every suite stayed green. That is now `check_growacrystal_critters` (§7.2), written as a failing test first: 2
   failures on the mutant, 12 of 12 on the real code, byte-identical output over 3 runs. It also kills two new
   mutants the old suites could not see (A9 and A10, §7.1).
2. **A6's bundle proof failed** in the first sweep: its anchor line occurs twice in the bundle. It is re-anchored.
3. **The shot list** (§9) was run through a geometry probe of the real layout (`Cavern.build`'s 149 parts +
   `Grotto.layout`). Every camera was checked for being inside a part, how far it looks through the shaft cylinders,
   and whether each promised thing is inside a 70°, 16:9 frame and in clear line of sight:
   * shot 1: the avatar (42° below the centre) and terrace 0's outer sockets were out of frame;
   * shot 2: terrace 0 was out of frame;
   * shot 3: the light shaft is on the left, not the right;
   * shot 4: the side-wall prisms were out of frame, the three central back-wall prisms were behind the glow
     column, and the waterfall is on the right, not the left;
   * shot 4 wide: the camera sat inside the shaft's outer cylinder and looked through 12 studs of the inner one, and
     from its height of 25 the deck and tread edges of terraces 6-7 hid the terraces behind them;
   * shot 5: socket 9, its ring and its shards were 51° below the centre, and the socket must be on screen to be
     clicked;
   * shot 6 passed.

   Every set-up in the new §9 comes from that probe, the geode shot from a grid search: all ten prisms, the
   waterfall and the shaft in frame, and the centre line clear of the inner column.
4. **Docs corrected**:
   * the server builds 155 parts per plot at chamber 1 and 176 at chamber 8, counted in the emulator, where §6 said
     "154";
   * the seam chambers are the even ones;
   * the seed formula's modulo covers the whole sum.

**Written in `grow-a-crystal/`**: this file, one line in `README.md` and two in `CLAUDE.md` (the new check, and the
state line). **Written in `robloxemu/`**: only `check_growacrystal_critters.luau` (new). The bundle
`build/grow-a-crystal.luau` was rebuilt, byte-identical. Nothing in `robloxemu/emu`, `tools`, `docs`, any `marketing`
folder or any other game was written. The sweep and all probes ran on scratch copies.

---

## 13. Review round 1 (2026-09-24): three findings, reproduced, tested first, fixed

An independent adversarial reviewer worked on a scratch copy of the resume session's tree. It found three defects and
called everything else clean: the server diff, the `lastHarvest` leak argument, the rest rules, hazards, budgets,
replication, and the shot-list recipe's config keys. This session took each finding in the same order: reproduce it
(or reject it with a measurement), write a test that fails on the unchanged game, fix the game (never the test), then
sweep the new assertions with mutants and a control. **All three reproduced exactly as reported; none was rejected.**

### Finding 1 (high): the HUD could lose the join push to the cavern script

**The defect.** Roblox queues a RemoteEvent fired before any listener exists and hands the queue to the first
connection only. The server sends State at join, usually before the LocalScripts start, and again only after a plant,
harvest, buy, geode or code. Before the living cavern, `Hud.client` was the only State listener, so it always got that
push. `Grotto.client` added a second listener, and LocalScripts start in an order Roblox does not define. The build
session protected the cavern (its socket count) but not the HUD.

**Reproduced** with the reviewer's own probe on the unchanged bundle (md5 `749f1a1e…`). The saved profile had dust
523 456, chambers 8, luck 3, growth 2 and codex 3.
* With the HUD alone, or the HUD first, the HUD showed `💎 523456`, `📖 Codex: 3/6`, `Shard (9)`, `Chambers MAX`
  and `Luck Lv3 → 💎2332`.
* With the cavern script first, the HUD showed `💎 0`, `📖 Codex: 0/6`, `Shard`, `Buy Chamber` and `Luck`, after 20 s
  of standing still. The cavern's chip was right.

The other order had the mirror defect, hidden by the sockets. With the HUD first, the cavern never got the push. In
`check_growacrystal_queue_hudfirst`, only 2 chambers' sockets are in the world while the push says 8; there the
cavern stayed in 💧 Sunken Grotto.

**Failing tests first.** Both new checks model Roblox's queue in the check itself, because the emulator drops a push
nobody listens to. The pushes the server sent before any client ran are handed, deferred and once, to the first
connection anybody makes to `State.OnClientEvent`.
* `check_growacrystal_queue` (cavern first): 12 passed, **11 failed** on the unchanged game. All seven HUD values were
  missing, it showed `💎 0`, there were 2 connections, and `StateFeed` did not exist.
* `check_growacrystal_queue_hudfirst`: 9 passed, **4 failed**. There were 2 connections, and the chip, Brightness and
  FogEnd were still at the grotto's values.
* `tests/StateFeed.spec` could not load its module.

**Fix: `src/shared/StateFeed.luau`**, pure and client only; the server never requires it.
* `StateFeed.of(remote, task.spawn)` returns the one feed for that RemoteEvent. The first caller makes the only
  connection.
* `feed:subscribe(fn)` delivers every later payload, and hands over the latest one straight away if one has already
  arrived. State is a full snapshot, so the latest is the whole truth.
* Each call goes through `task.spawn`, as a separate connection's would, so a subscriber that errors or yields cannot
  hold up another.
* `Hud.client` and `Grotto.client` each require it and change their State line from `OnClientEvent:Connect` to
  `subscribe`; the handlers themselves are unchanged.

There is no server change and no new remote, and the client still fires nothing. The sockets stay as the belt for a
push that is late or lost (`check_growacrystal_race`, unchanged apart from its header).

Why not the reviewer's alternative, the server re-pushing on a client hello: that needs a new client→server remote,
and the cavern would stop being a script that fires nothing. Why not the shape `lost-found-depot` uses (the HUD stays
the only listener and hands payloads to a cache the other script polls every frame): the cavern would depend on the
HUD running, and two pushes landing in one frame would lose a harvest burst.

**After.**
* `StateFeed.spec`: 24/0.
* `check_growacrystal_queue`: 27/0. The HUD shows the saved profile with no click, State has exactly one client
  connection, a purchase's live push updates the HUD, a harvest push bursts once, and `StateFeed` calls no
  `FireServer`, `InvokeServer`, `SetAttribute` or `FireAllClients`.
* `check_growacrystal_queue_hudfirst`: 13/0. The cavern reaches the Heart of the Geode's look with only 2 chambers
  of sockets in the world.
* The reviewer's probe on the fixed bundle: all three orders show `💎 523456`, `📖 Codex: 3/6`, `Shard (9)` and
  `Luck Lv3 → 💎2332`, with 1 connection each.

### Finding 2 (low): on a phone the answer to a code was about 6 px tall

**Reproduced.** In the one-row code drawer on compact layouts, the Redeem button, which also shows the server's
answer, is 45 × 44.4 screen px on every phone. The reviewer's probe gave the same numbers: at 640×300, 667×375,
800×360 and 896×414, "Invalid code" is estimated at **6.3 px**. The new `check_growacrystal_redeem` goes through the
real server's Redeem function and measures the same: 6.3 px for "Invalid code" and "Already used", 6.8 px for
"✅ Redeemed!". That held on the four landscape phones, the 414×800 portrait phone and an 800×600 mouse window (compact
without touch): **10 failures** on the unchanged game.

**Found on the way.** In portrait the one-row box is only about 49 screen px wide once its padding is taken off, and
its hint "Enter code..." came out at **6.2 px**. The check caught this with a new assertion, which failed before the
fix.

**Fix (`Hud.client`, compact layouts only).**
* The answer takes the whole row for its 2 s, in a `CodeResult` label.
* The box and the button are **hidden** meanwhile, not just covered, so nothing invisible can be tapped.
* A mistyped code stays in the box, to be corrected.
* A token keeps an older answer's timer from cutting a newer one short.
* The box's hint is "Code" (the drawer's toggle says "🎟 Code" too).

Desktop behaves as before: the full-width button still shows the answer, and the hint is still "Enter code...".

**After** (estimated TextScaled size, 0.6 em per glyph, parent padding taken off). The floor is 12 px.

| viewport | the answer | the box's hint |
|---|---|---|
| 640×300, 667×375, 800×360, 896×414 | "Invalid code" 19.8 px, "✅ Redeemed!" 21.6 px | "Code" 39.8 px |
| 414×800 portrait | "Invalid code" 13.3 px, "✅ Redeemed!" 14.5 px | "Code" 20.2 px |
| 800×600 mouse window | 17.5 px | 17.5 px |
| 1280×720 desktop | 22.8 px (in the button, as before) | "Enter code..." 26.6 px |

`check_growacrystal_redeem` holds 131 assertions at 7 viewports:
* the answer is on screen and not under Roblox's touch controls;
* nothing tappable is under 44 px, or covered by the answer, while it shows;
* the row is back after 2 s, with a 44-px Redeem button and the mistyped code still in the box;
* on desktop, a second answer 1 s after the first keeps its full 2 s.

For scale, the stacked drawer before the thumbstick fix gave about 20 px on a landscape phone and 13 px in portrait,
the same as now.

### Finding 3 (low): Legendary and Mythic flashes stacked into a wash

**Reproduced.** The reviewer's budget probe on the unchanged bundle ran 20 minutes at chamber 8, with 144
Legendary/Mythic harvests in bursts of 6 at 4 clicks/s. It had **3 FxFlash GUIs at once, 73 % combined opacity**. A
Legendary seed always refracts to Legendary or Mythic, so every such harvest fired the flash, and every Mythic the
shake.

**Failing tests first.**
* `check_growacrystal_flash` replays six Mythic harvests at 4 clicks/s through the real client, using the server's
  own push shape. On the unchanged game: **6 flash calls, 6 shakes, 3 flashes on screen at once, peak opacity 0.73**;
  7 failures.
* `Grotto.spec` failed calling the missing `flashDue`.
* `EnvConfig.spec` failed 5 assertions on the missing `Env.HarvestFlash`.

**Fix.**
* `Grotto.flashDue(lastAt, now, cooldown)`, pure.
* `Config.Env.HarvestFlash = { alpha = 0.35, fade = 0.8, cooldown = 2 }`. The spec requires the cooldown to outlast
  the fade, so two flashes can never overlap.
* `Grotto.client` plays the full-screen part (the flash and Mythic's shake) only when `flashDue` says so. The burst,
  ring, beam and card play for every harvest.

**After.**
* `check_growacrystal_flash`, 18/0:
  * the six Mythic harvests give **1 flash, 1 shake, never 2 on screen, peak opacity 0.35**, and 6 bursts, each at
    its own socket, with the MYTHIC card every time;
  * a Legendary after the cooldown flashes again, and one 1 s later does not.
* The reviewer's probe on the fixed bundle: **1 FxFlash GUI at most**. Its peak opacity is 0.40, from the Heart of the
  Geode band fanfare: the probe buys chamber 8, and the fanfare is a 0.4 flash, once per player. It is not a harvest
  flash.
* Parts peaked at 120, against the budget of 150 and 113 in the reviewer's run; the visitors and bursts are random.

### Mutation sweep, and what was written

**75 mutations: every one of the 69 real mutants was KILLED and all 6 controls SURVIVED** (§7.1). That includes all
23 new ones: F1-F8 (StateFeed and its wiring), R1-R6 (the phone code answer) and L1-L9 (the flash cooldown). Each was
proved to be in the rebuilt bundle, and the sources were restored byte-identical after each one.

One lesson came out of the sweep's killer list. The first version of `check_growacrystal_queue` ran both scripts
before the deferred flush, so both had subscribed by the time the push arrived, and it never exercised handing a late
subscriber the latest payload. F1 (no replay) got past it and was caught only by `StateFeed.spec` and
`queue_hudfirst`. The check now lets the flush land on the cavern script before the HUD starts, which is the case the
reviewer reported. It fails 11 assertions on the unchanged game, passes 27/27 on the fix, and kills F1 in a re-sweep
(§7.1). The case where both scripts are already subscribed is still covered by the live pushes in the same check and
by `StateFeed.spec`.

**Written in `grow-a-crystal/`:**
* `src/shared/StateFeed.luau` (new);
* `src/client/Hud.client.luau`: the feed, the phone answer and the hint;
* `src/client/Grotto.client.luau`: the feed and the flash gate;
* `src/shared/Grotto.luau`: `flashDue`;
* `src/shared/Config.luau`: `Env.HarvestFlash`;
* `tests/StateFeed.spec.luau` (new); `tests/Grotto.spec.luau` and `tests/EnvConfig.spec.luau` (new assertions only;
  no existing assertion changed);
* this file, `README.md` and `CLAUDE.md`.

The template copies `EnvBands.luau` and `Rest.luau`, and the server, were not touched.

**Written in `robloxemu/`:**
* `check_growacrystal_queue.luau`, `check_growacrystal_queue_hudfirst.luau`, `check_growacrystal_redeem.luau` and
  `check_growacrystal_flash.luau` (all new);
* the header comment of `check_growacrystal_race.luau` (no code);
* `build/grow-a-crystal.luau` (rebuilt).

Nothing in `robloxemu/emu`, `tools`, `docs`, any `marketing` folder or any other game was written. The probes and the
sweep ran on scratch copies.
