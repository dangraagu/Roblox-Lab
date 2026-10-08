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
failing test for each, fixed the game, and re-ran every gate and a 75-mutation sweep. **Review round 2 (2026-09-30,
§14):** a second reviewer found six more (a predictable refraction roll, a Mythic losing its celebration inside a
Legendary row, the title card over the Relax button on landscape phones, uncapped per-plot lights and sparkles,
saves with no owner token, silent refusals). All six reproduced; each got a failing test first and a game fix. The
owner's two open decisions were taken the same day (§11, "DECIDED 2026-09-30"). **Pass 2 of the complete-game
standard (2026-09-30/10-01, §15)** added the public + friends highscore board, the end-to-end walk check, the named brag
moment, a readable first-run hint, the store text, the clip list, and this document's shot size and new Studio items.
**Pass 1 re-run (2026-10-01, §16)** re-ran the reviewer's own probes on the reviewed tree (all six findings reproduce)
and on this tree (none does), re-ran round 2's 43-mutation sweep, and took the last open owner decision: a paid pass
never moves the highscore board. **Pass 2b (2026-10-01, §17)** checked the standard item by item again and closed
three gaps, each test-first: a session that could not save said nothing and never recovered (now it says so and
retries on every autosave), the clip list could not be staged in Studio (codes and the Geode now work for the session
when nothing can ever save), and bands 2 and 3 had no critters of their own (glowflies, fireflies, glow-worm silk).

**In one paragraph.** The progress value is **how many chambers the player owns**. It is read from the player's own
sockets in the world and from the server's State push, and it drives five looks: 💧 Sunken Grotto → ✨ Glow-worm Hollow
→ 🍄 Mushroom Terraces → 🌊 Waterfall Chamber → 💎 Heart of the Geode. Every chamber purchase changes the cavern, and
nothing is ever taken away: glow-worms fill the ceiling, giant glowing mushrooms grow along the walls, an underground
waterfall pours into the pool, crystal prisms line the geode wall. Each look has life and weather of its own: blinking
glowflies and drifting silk under the glow-worms, fireflies over the mushrooms, bats by the waterfall, wisps rising in the
geode. Light, fog, bloom and colour glide into each new look.
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
p10 / median / p90), re-measured on 2026-09-30 with the Shard at 7 dust (§11). Offline growth is not modelled, so real
players who leave crystals growing overnight get there sooner.

| # | band | first shows | full | normal: minutes | slow: median | lighting | scenery (cumulative) | life | particles | visitors |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 💧 Sunken Grotto | ch 1 | ch 1 | 0 | 0 | = the server's `Fx.Presets.Cozy`, number for number (dark teal, bloom 0.9) | shimmer on the pool | 2 moths | ceiling drips 6/s | none |
| 2 | ✨ Glow-worm Hollow | ch 2 | ch 3 | 1 / 1 / 1 → 1 / 1 / 1 | 2 → 2 | cooler blue-green, darker ambient so the worms pop, bloom 1.05 | + 16 glow-worm strands (thread + bead) hanging from the ceiling | 3 moths, **5 glowflies** (blinking blue-green beads among the strands) | **glow-worm silk 4/s** drifting down + drips 3/s | moth swirl |
| 3 | 🍄 Mushroom Terraces | ch 4 | ch 5 | 19 / 38 / 51 → 51 / 65 / 78 | 75 → 130 | warm violet/amber, saturation 0.28 | + 6 giant glowing mushrooms along the walls (stem, cap, gill ring) | 4 moths, **6 fireflies** (blinking amber, a low layer under the moths) | spores rising 8/s + drips 3/s | moth swirl |
| 4 | 🌊 Waterfall Chamber | ch 6 | ch 7 | 81 / 99 / 111 → 152 / 171 / 184 | 198 → 342 | aqua mist, haze 1.8, bloom 1.15 | + an underground waterfall into the pool (sheet, core, foam, spray) | 4 moths, 4 bats | mist 12/s + spores 4/s | bat swoop, moth swirl |
| 5 | 💎 Heart of the Geode | ch 8 | ch 8 | 219 / 238 / 249 | 472 (p90 not within 8 h) | amethyst/magenta, strongest bloom 1.3, deepest pulse | + 10 crystal prisms lining the geode wall around the pool, 8 glowing seams on the ceiling and upper wall | 4 moths, 3 bats, 5 wisps rising up the light shaft | sparkle 10/s + mist 8/s | bat swoop, moth swirl |

**Every band has life and weather of its own** (pass 2b, §17; `EnvConfig.spec`): each band after the first brings a
critter kind and a particle kind the band before it did not have. Before, the first three bands had moths only and
the first two drips only, against the standard's "each with its own light, colour, scenery, critters and weather".

The **geode pulse** gets deeper with each band: depth 0.08 in the grotto, 0.35 in the geode, with a period of 9 s
down to 7 s. It dims every glowing element and nudges bloom by up to ±4 %. Its phase is integrated, so a change of
period never makes it jump.

**Chip** (under the HUD's header): `🍄 Mushroom Terraces  ·  🌊 Chamber 7`. With every chamber open it reads
`…  ·  every chamber open`, and while resting `🛋 Relaxing — your crystals keep growing`.

### The pacing model and the economy (DECIDED 2026-09-30 (owner: take recommended), §11)

`tests/IdleModel.luau` plays the game's own rules (Economy, Growth, Rarity, Codex, Rng, Config). The human part is
written down in `Config.Pacing.Profiles`:

* **normal**: visits the sockets every 75 s, redeems the four advertised codes, plants the Shard seed the HUD starts on,
  and buys the cheapest upgrade (chamber, luck, growth) while keeping enough dust to replant;
* **slow**: the same, every 150 s;
* **nocodes**: normal, but never types a code.

The model found something the looks could not fix: **at luck 0 no seed below Mythic paid back its price on average**,
and a player who never typed a code ran dry. The owner decided on 2026-09-30 (§11). Now:

| seed | costs | returns on average |
|---|---|---|
| Shard | **7** (was 10) | 7.82 (**112 %**, was 78 %) |
| Quartz | 50 | 14.63 (29 %) |
| Amethyst | 250 | 34.37 (14 %) |
| Prism | 1 200 | 99.52 (8 %) |
| Legendary | 6 000 | 360.00 (6 %) |

The rarer seeds still cost more than they return: they are bought for the codex, the beam and the brag, not for
dust. The Shard is the income. A price alone was not enough, because a player who hits a **dead end** (nothing growing,
no seed of any tier, less dust than a Shard) could never do anything again, so the server now plants a **free Shard**
at a dead end (`Economy.needsFreeSeed`). Measured with the pacing model, 40 sessions of 8 h per profile (the first
three rows by a scratch probe that stubs the rule or the price; the shipped row is what `Pacing.spec` runs):

| nocodes player | dead ends | owns chamber 2 within 8 h | chamber 2, p10 / median / p90 (min) |
|---|---|---|---|
| before (Shard 10, no free Shard) | 39 of 40 | 1 of 40 | never / never / never |
| Shard 7 only | 35 of 40 | 5 of 40 | 90 / never / never |
| Shard 10 + free Shard | 0 of 40 | 17 of 40 | – |
| **Shard 7 + free Shard (shipped)** | **0 of 40** | **36 of 40** | **24 / 182 / 472** |

The normal and slow players never hit a dead end and never got a free Shard (0 in 80 sessions); their numbers moved
only with the price (the table above). `Pacing.spec` now asserts, instead of the old FINDING: the Shard pays back at
luck 0; a code-less player owns chamber 2 in the median 8-hour session; no session of any profile reaches a dead end.
Band 1 stays rich on purpose: shimmer, drips, moths, the pulse, the harvest bursts and the Legendary beam all work in
chamber 1.

**The brag moment and the long-term goal (standard §2, pass 2).** `Config.Pacing.Brag` names it: **the first crystal
that refracts to Mythic**, the game's biggest celebration (magenta flash, beam, title card; `check_growacrystal_flash`)
and 1500 Gem Dust on the highscore board. `Pacing.spec` measures it: normal player p10 **4** / median **31** / p90 **70**
min; slow median **62**; a code-less player median **268**. It asserts the normal median is inside 20-45 min, p90 within
90 min, the slow player gets it in the session, and the **Heart of the Geode** (chamber 8, median **238** min) comes at
least 2 h of play after it. The board is the other long-term goal: a normal player earns **1 125 295** dust in 8 h and
then about **204 406** an hour at the end game, so the board's cap (400 million dust) is **1959** hours of play away
(asserted: at least 1000).

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
the Geode (a 0.4 flash, once per player) is not on this clock; a harvest flash now replaces it on screen instead of
stacking.

**The rarest harvest keeps its celebration** (review round 2, finding 2, §14). With the cooldown alone, a Mythic
harvested inside a row of Legendary harvests got no flash and no shake, and the next Legendary took its card and its
beam 0.25 s later. Now a HIGHER tier than the last flash skips the cooldown (`Grotto.flashDue(..., lastTier, tier)`)
and replaces the older flash, so there is still never more than one on screen; and the card and the beam belong to
the rarest harvest still playing (`Grotto.outranked`): a lower tier keeps its shards and ring but does not take them
over until they end (card 3 s + 0.8 s fade, beam 2.5 s). Equal or higher tiers do take them, so a row of Mythics
moves the beam to the latest click. Measured (`check_growacrystal_flash`): the Mythic at each position 2..6 of a
Legendary row at 4 clicks/s flashes once and shakes once, its magenta beam is still on its socket 2.3 s later and its
MYTHIC card still on screen 2.9 s later, never two flashes on screen, peak opacity 0.35.

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

**The refraction roll is no longer predictable (FIXED in review round 2, §14).** `grantHarvest` used to seed the roll
with `(os.time()*1000 + socketId*977 + UserId) % (2^31 - 1)`, all of it known to the client (its State push carries
`now`), and a probe predicted 48 of 48 rolls. The seed now adds a salt the server draws for EACH harvest from its own
entropy-seeded `Random` (`rollSalt`, a local of `Main.server`, never saved, sent or set as an attribute;
`Rarity.rollSeed`). The same predictor now matches only at chance level (9-12 of 48 Shards at luck 3 over three runs,
chance 13.2), and the odds are unchanged (§14).

---

## 6. Budgets (measured, `check_growacrystal_env`)

Client-built only. The server's own cavern is on top of this. Counted in the real plot through the emulator in the
resume session: **155 parts at chamber 1 and 176 at chamber 8** (each purchase adds a chamber's sockets and removes
its rubble caps), 10 lamp PointLights and 2 dust emitters (34 particles/s), plus one part per crystal. The build
session's "154" does not match this count (it did not say how it counted). **Since pass 2 each plot also holds the
highscore board: one Part with a SurfaceGui and a ProximityPrompt, no light, no emitter: 156 and 177**
(`check_crystal_sockets` pins 157 with one crystal growing). **The crystals' own effects were not
capped and this paragraph used to say "always 10 PointLights and 2 dust emitters"** (review round 2, finding 4, §14):
every ready crystal had a sparkle and every ready tier-3+ crystal a light, so 48 crystals that matured offline gave one
plot 58 PointLights, 50 emitters and 322 particles/s, all rebuilt every 5 s. Now (`Config.PlotBudget`,
`check_growacrystal_plotbudget`): every ready crystal still glints (the "ready to harvest" cue), the sparkles share at
most 48 particles/s, and at most the 6 rarest ready tier-3+ crystals cast light. Measured at chamber 8 with 48 ready
crystals: **16 PointLights (10 lamps + 6), 50 emitters, 82 particles/s**, and nothing is rebuilt while nothing changes. The client numbers below were measured after 12 s at
every chamber count (10 half-lives, settled). The even chambers 2, 4 and 6 are the seams, where two bands are live at
once.

| chambers | band | local parts | emitters on (particles/s) | lights |
|---|---|---|---|---|
| 1 | Sunken Grotto | 5 | 1 (6/s) | 0 |
| 2 | Sunken Grotto › Glow-worm | 24 (was 22) | 2 (6.5/s) | 0 |
| 3 | Glow-worm Hollow | 44 (was 40) | 2 (7/s; was 1, 5/s) | 0 |
| 4 | Glow-worm › Mushroom | 55 (was 50) | 2 (7/s) | 0 |
| 5 | Mushroom Terraces | 65 (was 60) | 2 (11/s) | 0 |
| 6 | Mushroom › Waterfall | 71 (was 68) | 2 (12/s) | 0 |
| 7 | Waterfall Chamber | 76 (was 75) | 2 (16/s) | 0 |
| 8 | Heart of the Geode | 97 (was 96; 107 with a visitor in flight) | 2 (18/s) | 0 |

Re-measured in pass 2b (§17) over 8 runs of `check_growacrystal_env`, with the glowflies, fireflies and silk in.

| metric | measured peak | where | budget (`Config.Budget`) |
|---|---|---|---|
| local parts | **130** (122 or 130 over 8 pass-2b runs; it was 121-129 before the new critters: 122 when the flock is the 10-part moth swirl) | chamber 8, a bat swoop in flight **and** a Legendary burst with its beam | 150 |
| scenery elements (all pieces) | 74 | layout | 80 |
| particle emitters on | 2 | every seam | 2 (`MaxWeatherEmitters`, enforced by `EnvBands.capRates`) |
| particles per second | 18 | chamber 8 | 30 (enforced) |
| point lights | 1 | the beam, for 2.5 s | 1 |
| visitors at once | 1 | | 1 |

By construction, the worst case is 80 scenery + 22 critters + 18 visitor parts + 12 shards + ring + beam + 8
weather-host slots = 143 ≤ 150 (`EnvConfig.spec`; 142 before pass 2b, the critters of bands 3 and 4 together are now
the worst neighbours). Every ambient critter, in every band, flies at least 3.5 studs over a standing head: measured
4.5-9.7 studs over 8 runs, and `EnvConfig.spec` checks every zone against the floor heights with 2 studs of slack.

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

Final run: pass 2b, 2026-10-01 (§17), on the bundle rebuilt from the final tree (sha256 `c4b2bc7ce01d…`).
**All 41 suites green (exit code 0 each): 17 specs, 1 392 assertions; 24 headless checks, 1 531 assertions plus 2
whole-screen PASS verdicts.** (The pass 1 re-run's final run was 39 suites: 17 specs, 1 323 assertions; 22 checks,
1 412 assertions plus 2 PASS, sha256 `6d308ffb651a…`. Review round 2's was 34 suites.) Rows marked *(R1)* are new or
changed in review round 1, *(R2)* in review round 2, *(P2)* in pass 2 (§15), *(P1b)* in the pass 1 re-run (§16),
*(P2b)* in pass 2b (§17).

| suite | what it pins | result |
|---|---|---|
| `tests/Rng.spec` | deterministic LCG (pre-existing) | 56 / 0 |
| `tests/Rarity.spec` | refraction roll (pre-existing); *(R2)* + `rollSeed` and the salted odds against the exact odds, 100 000 rolls per case | 33 / 0 |
| `tests/Growth.spec` | offline growth (pre-existing) | 20 / 0 |
| `tests/Economy.spec` | harvest value, shop (pre-existing); *(R2)* + the Shard's price (7) and `needsFreeSeed`; the two buySeed dust assertions now read `30 - SeedCost[1]` instead of the old price's 20 | 46 / 0 |
| `tests/Geode.spec` | weekly geode (pre-existing) | 22 / 0 |
| `tests/Codex.spec` | codex (pre-existing) | 8 / 0 |
| `tests/Codes.spec` | codes (pre-existing) | 12 / 0 |
| `tests/Cavern.spec` | the server's cavern layout (pre-existing); *(P2)* + the board on the entrance wall | 80 / 0 |
| `tests/responsive.spec` | HUD layout maths (pre-existing) | 70 / 0 |
| `tests/EnvBands.spec` | band lookup + blend, glide, `capRates` (template, verbatim) | 124 / 0 |
| `tests/Rest.spec` | rest rules (template, verbatim) | 55 / 0 |
| `tests/Visitors.spec` | the rare-visitor clock, rarity, rest-toggle probe | 34 / 0 |
| `tests/Grotto.spec` | progress, sockets → chambers, bursts, pulse, layout, zones, routes; *(R1)* + `flashDue`: at most one flash per cooldown, its edges, NaN (was 143); *(R2)* + the higher-tier bypass and `outranked`; *(P2b)* the glowfly and firefly zones and the silk volume pass the same zone rules | 191 / 0 |
| `tests/EnvConfig.spec` | the shipped `Config.Env` / `Visitors` / `Rest` / `Budget`; *(R1)* + `Env.HarvestFlash`: a tint, it fades, the cooldown outlasts the fade (was 430); *(P2b)* + at least five bands, each band after the first brings a critter kind and a weather kind of its own, every named kind can be drawn, every critter zone clears a standing head by 3.5 studs | 499 / 0 |
| `tests/Pacing.spec` | when a player reaches each look (`IdleModel`); *(R2)* the FINDING became requirements: the Shard pays back, chamber 2 without codes, no dead end; *(P2)* + the brag moment and the board's cap | 23 / 0 |
| `tests/Board.spec` *(P2)* | the board's pure rules: points, encoding and tie-break, keep-higher, views, caches, the limiter | 95 / 0 |
| `tests/StateFeed.spec` *(R1)* | one State connection per remote, a late subscriber handed the latest payload, either order, arguments intact, every call through the spawner | 24 / 0 |
| `robloxemu/check_crystal` | HUD fit, panel overlap on (pre-existing) | PASS |
| `robloxemu/check_crystal_sockets` | sockets in the world, clicks plant (pre-existing) | 36 / 0 |
| `robloxemu/check_crystal_spawn` | spawn order, facing (pre-existing; `SPAWN-ORDER.md`) | 30 / 0 |
| `robloxemu/check_growacrystal_harvest` | `lastHarvest` in the State push, nothing else | 23 / 0 |
| `robloxemu/check_growacrystal_env` | the whole client glue, budgets, rarity, rest, leaks; *(P2b)* + each full band's own glowflies, fireflies, wisps and weather are out at their rates, glowflies and fireflies blink, every ambient critter in every band stays 3.5 studs over a head | 173 / 0 |
| `robloxemu/check_growacrystal_hud` | HUD fit with both clients, every drawer open | PASS |
| `robloxemu/check_growacrystal_row` | the chip and Relax button against every HUD element; *(R2)* + the title card against the row and the HUD at 11 viewports | 581 / 0 |
| `robloxemu/check_growacrystal_join` | a slow profile load: one quiet card, glide, no replayed burst | 21 / 0 |
| `robloxemu/check_growacrystal_race` | the join push missed: chambers from the sockets | 12 / 0 |
| `robloxemu/check_growacrystal_critters` | critters held to their zone's height band (new, resume session) | 12 / 0 |
| `robloxemu/check_growacrystal_queue` *(R1)* | Roblox's queue rule replayed, the cavern script first: the HUD shows the saved profile with no click, one connection, later pushes reach both | 27 / 0 |
| `robloxemu/check_growacrystal_queue_hudfirst` *(R1)* | the same with the HUD first and only 2 chambers of sockets in the world: the cavern gets the push too | 13 / 0 |
| `robloxemu/check_growacrystal_redeem` *(R1)* | the code answer on 5 phone viewports and 2 mouse windows: size, place, nothing covered, timing; the box's hint | 131 / 0 |
| `robloxemu/check_growacrystal_flash` *(R1)* | six Mythic harvests at 4 clicks/s: one flash, one shake, six bursts; the cooldown; *(R2)* + a Mythic at each place in a Legendary row keeps its flash, shake, card and beam | 55 / 0 |
| `robloxemu/check_growacrystal_salt` *(R2)* | a client's prediction of the roll is at chance level; per-harvest salt; roll unchanged; salt not readable; *(P2b)* on the virtual clock (it dropped a harvest that straddled a wall-clock second: 1 failed run in 40 under load, 0 in 40 after) | 10 / 0 |
| `robloxemu/check_growacrystal_refused` *(R2)* | 15 refusals each toast their reason and change nothing; a dead end gets a free Shard; every toast ≥ 12 px at 10 viewports; *(P2)* + another player's socket or crystal says whose cavern it is | 103 / 0 |
| `robloxemu/check_growacrystal_lock` *(R2)* | the owner token: a takeover is never overwritten, the lost session stops saving and is told once; the normal path | 26 / 0 |
| `robloxemu/check_growacrystal_plotbudget` *(R2)* | crystal lights and sparkles capped per plot, every ready crystal glints, no rebuild while nothing changes | 32 / 0 |
| `robloxemu/check_growacrystal_board` *(P2)* | the public + friends board through the real server: metric, writes only on a rise, caches, friends cap, names, the physical board and its prompt | 81 / 0 |
| `robloxemu/check_growacrystal_walk` *(P2)* | the whole player path in one run: join, spawn, plant, harvest, buy, leave, offline growth, rejoin | 34 / 0 |
| `robloxemu/check_growacrystal_hint` *(P2)* | the first-run hint is readable (≥ 12 px) on every viewport | 17 / 0 |
| `robloxemu/check_growacrystal_pass` *(P1b)* | a paid pass (`DoubleDust`) doubles the dust a player spends but never the board metric or the board's points | 10 / 0 |
| `robloxemu/check_growacrystal_rejoin` *(P2b)* | a session that cannot save says so at join and retries on every autosave: a crash-rejoin resumes and saves what was played; a renewed lock is never taken, and its release loads the newer record; a failed load loads the real profile and rebuilds the cavern; a failed load that finds a lock waits for it; Studio without API access says "won't save" once and grants codes for the session; chambers wait; every message ≥ 12 px | 53 / 0 |
| `robloxemu/check_growacrystal_clips` *(P2b)* | every clip in `MARKETING.md` staged the way it says, in a session with no DataStore, through the HUD's buttons (found the way `film_game.py` finds them) and the sockets: codes 5 600 dust, chambers 2 and 3, the Glow-worm card, the Geode's Legendary in a Legendary week, socket 9 in range, 20 min, the beam and card, Relax at the pool, the board offline; this week (2026-09-28..10-04) is a Legendary week too | 51 / 0 |

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

**Pass 1 re-run (2026-10-01, §16).** Round 2's 43 mutations re-run unchanged on the current tree, now 39 suites per
mutant (pass 2's checks included): **40 of 40 real mutants KILLED, 3 of 3 controls SURVIVED; bundle proof 43 of 43;
restored byte-identical (sha256) 43 of 43**; the copy was identical to the real tree before and after. The new
decision's assertions: **5 of 5 KILLED, the control SURVIVED, bundle proof and restore 6 of 6** (table in §16).

**Round 2 (2026-09-30, §14): 43 mutations on the new code, 40 real and 3 controls. All 40 real mutants KILLED and all
3 controls SURVIVED; bundle proof 43 of 43; every file restored byte-identical (sha256) 43 of 43.** Harness:
`gac_p1/sweep.py` + `make_mutations.py` in the session's scratchpad (a scratch copy verified identical to the real tree
before and after, all 34 suites per mutant, 8 in parallel). Two things the sweep found, both fixed:
* the first run refused 15 mutants because the working tree is CRLF and their anchors had newlines (the harness now
  matches CRLF in the file and proves LF in the bundle), and one mutant survived: R10, the Grotto row mirroring a
  taller phone toast line. It was an equivalent mutant: the HUD's scale never goes below 0.6 on a phone, so the
  "taller" line was always 24 px. That code was removed; the real fix is the toast's text and width caps;
* the full re-run left two survivors, both gaps in the checks. R9 (the phone toast keeps its 460-px width cap)
  survived because `emu/guiRects` applies a `UISizeConstraint` only to auto-sized heights, so `refused` now applies the
  width cap in its own estimate, as Roblox does. C2 (the stacked row forgets the chip) survived because the stacked row
  only binds on a screen that is narrow AND short, so `row` now also measures the card at 360×400 (a portrait phone in
  split screen). Both re-swept: KILLED, with a control that SURVIVED.

| id | what the mutation breaks | killed by |
|---|---|---|
| S1-S3 | the server rolls with no salt / a constant salt / a one-bit salt | salt |
| S4-S5 | `rollSeed` drops the salt / keeps only salt mod 7 | Rarity.spec, salt |
| R1-R8 | each refusal silent or with the wrong reason; the empty code; the phone toast's 15-px cap | refused |
| R9 | the phone toast keeps the 460-px width cap | refused (after the fix above) |
| E1, E5 | a dead end refused forever; the free Shard given silently | refused |
| E2 | `needsFreeSeed` ignores a growing crystal | Economy.spec, refused |
| E3 | `needsFreeSeed` ignores owned seeds | Economy.spec |
| E4 | the Shard back to 10 | Economy.spec, Pacing.spec |
| K1 | no ownership check on a save | lock, refused |
| K2 / K3 | token only / jobId only | lock |
| K4 | a lost session keeps trying and toasting | lock |
| K5 | the load never writes its token | lock and 7 more checks |
| P1-P6 | lights uncapped / to the commonest / sparkle rate uncapped / the 5 s rebuild back / a few ready crystals lose their full glint / a harvest does not re-deal | plotbudget |
| F1, F6, F7 | `flashDue` never bypasses / equal tiers yield / the stage never expires | Grotto.spec, flash |
| F2-F5, F8 | no tiers passed / two flashes on screen / a Legendary takes the Mythic's card / beam / the flash tier never recorded | flash |
| C1 | the card back at 40 % | row |
| C2 | the stacked row forgets the chip | row (after the fix above) |
| CTRL-1..3 | *controls*: a crystal light 0.1 dimmer; the salt never 0; the free-seed toast's emoji | survived ✓ |

**Round 1 (review round 1 session, §13):**

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
23. **A Mythic inside a Legendary row** (new, review round 2): its flash replaces the Legendary's mid-fade. A clear
    "something rarer happened", or a flicker? Its card and beam now stay put while the next Legendaries burst.
24. **Sparkles on a full cavern** (new, review round 2): with 48 crystals ready the sparkles share 48 particles/s, so
    each glints about once a second (up to 8 ready crystals keep the full 6/s). Does a 1/s glint still read as "ready
    to harvest"? And frame time with 48 low-rate emitters and 16 lights in one plot, on a phone.
25. **The toast line on a phone** (new, review round 2): it is now allowed the whole screen width and 24 design px of
    text (about 14 screen px) on compact layouts. Readable over the cavern, and does a long reason ("Not enough Gem
    Dust: a Legendary seed costs 6000") fit on one line in portrait?
26. **The title card under the row** (new, review round 2): on a landscape phone the card now sits just below the chip
    and the Relax button instead of at 40 % of the height. Still in the middle of the action, or too high?
27. **A session that lost its record** (new, review round 2): only reachable when a server stalls past the 45 s lock.
    If it can be staged (two Studio test servers on one DataStore), check that the "Opened on another server" toast
    shows once and nothing is overwritten.
28. **The highscore board** (new, pass 2): a 14x9-stud slab on the entrance wall, 8.5 studs behind the spawn, a
    SurfaceGui at 40 px per stud with `LightInfluence = 0`. From the spawn, turning round: is it readable (ten rows,
    each about half a stud tall), does it glow too much or too little against the Cozy grade, and is it seen at all
    (it is behind the first frame on purpose)? In Studio with API access off it says it is offline, which is correct.
29. **The board's prompt** (new, pass 2): `MaxActivationDistance` 12, so it shows as soon as the player turns round at
    the spawn. Does it steal an E press or a tap meant for something else? Does "Show friends" / "Show everyone" read?
    With API access on, only on a server you may write to: does the Friends view list friends and count "Checking
    your friends: n of m"? **Never record or screenshot the Friends view with a real account.**
30. **The first-run hint** (new, pass 2): "Tap a socket to PLANT · tap a crystal to HARVEST" on phones (13.2 px
    estimated) and the longer line on desktop (16 px). Readable over the cavern? Is "socket" understood without
    "glowing"?
31. **The walk on a live server** (new, pass 2): `check_growacrystal_walk` proves join, plant, harvest, buy, leave and
    rejoin in the emulator with a virtual clock. The real proof is a rejoin on the live server: plant, leave, wait a
    minute, come back, and the crystal is grown.
32. **Glowflies and fireflies** (new, pass 2b): 0.22- and 0.26-stud Neon beads that blink (a 0.3-1.0 glow on a 2.9 s
    and a 2.0 s cycle). Do they read as fireflies, distinct from the steady cream moths, or as flicker? Glowflies
    drift among the glow-worm strands (y 34-42), fireflies in a low layer under the moths (y 30-35).
33. **Glow-worm silk** (new, pass 2b): 4 cyan motes/s falling slowly from the strands' height across the cavern.
    Visible, or lost against the beads? It must not read as rain.
34. **The Studio session that cannot save** (new, pass 2b): with API access off, the join toast must say "Saving is off
    here: progress won't save", and the codes must give 5 630 dust (that is how `MARKETING.md` stages clips 4-7).
    Note which way this Studio fails: `GetDataStore` raising (a rojo-built file) or every call raising (the published
    place with API access off); both are handled, and only the first shows the board's "offline" note (the second
    keeps "Loading...").
35. **A crash-rejoin on the live server** (new, pass 2b): only stageable with a real crash (or two test servers on
    one DataStore). The toast "Save open on another server: retrying" at join, and within about a minute "Your save
    is back: progress saves again". Proved in the emulator only (`check_growacrystal_rejoin`).

---

## 9. Thumbnail shot list (for the night Studio session)

**Output: 1920x1080 PNG** (16:9, the Roblox thumbnail size), captured from a 1920x1080 Studio viewport so nothing is
rescaled; the icon (512x512) is a square crop of shot 4 or 5. Every framing below assumes that 16:9 frame and Roblox's
default 70° vertical field of view. Hide the HUD for every shot except where it says otherwise.

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
     (−2, 40, 17), v +32..34) back to (3, 40, 70) and (12, 40, 72) just above the centre, with glowflies blinking
     among them (pass 2b; not part of the geometry probe, they wander);
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
7. **"Top miners"** (pass 2; **HELD for the live server**: in Studio the board has no rows, see §8 item 28). Stand at
   the spawn, (0, 4, −6), and turn round. Camera **(6, 9, −2) → (0, 8.5, −13.7)**: the whole board on the entrance wall
   across the middle of the frame (its corners 21-32° off the centre line against the frame's ±51° × ±35°), seen
   27° off its face. Public view only, never Friends. Checked by hand arithmetic only, not by the probe that checked
   shots 1-6.

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

* **Review round 2 is closed (§14); its fixes have been checked by their author's tests and mutation sweep, not by a
  third reviewer.**
* **Review round 1's fixes had their second look in round 2.** The second reviewer found one regression in them (the
  flash cooldown held back a Mythic inside a Legendary row, finding 2) and nothing wrong with `StateFeed` or the phone
  code answer.
* **Owner decision: the economy (§2). DECIDED 2026-09-30 (owner: take recommended).** The note named two options to
  evaluate: Shard DustValue 1 → 2, or SeedCost 10 → 7. Evaluated with the pacing model: DustValue 2 gives the Shard
  8.32 per 10 (83 %), still a loss, and the code-less player still never owns chamber 2; SeedCost 7 gives 112 %. So the
  Shard costs **7**. The price alone still left 35 of 40 code-less sessions at a dead end (nothing growing, no seed,
  under 7 dust), so a dead end now gets a **free Shard** (`Economy.needsFreeSeed`): never punishing, and not farmable
  (at most one Shard per grow cycle, only while the player has nothing else). Result: 0 dead ends in 120 sessions,
  36 of 40 code-less players own chamber 2 within 8 h (median 182 min). §2 has the numbers.
* **Owner decision: the predictable refraction roll (§5). DECIDED 2026-09-30 (owner: take recommended).** The
  recommended fix was the checklist's server-only salt. Applied with one change, and why: the salt is drawn per
  HARVEST from an entropy-seeded server `Random`, not once per session, because the client sees every roll's tier and
  a salt fixed for the session is a constant it could solve for. The odds are unchanged (§14).
* **luau-analyze was not run** in any session (the binary is absent, §7.2); compile was verified by `loadstring`.
  Fetching `luau-compile`/`luau-analyze` "needs the owner's go" (§7.2). **Not taken on 2026-09-30:** downloading a
  binary needs an explicit go in chat for that download, which a blanket "take the recommended option" is not.
  Still open (re-checked 2026-10-01, §16: same reason, not taken).
* **The shot list is geometry-checked, not seen** (§9, §8 items 18-20).
* **The join fix is proved in the emulator only** (§8 item 21): the queue rule is replayed there, not observed on a
  real server.
* **Pass 2 (§15) was checked by its author's tests and mutation sweep only**, like round 2's fixes; no third reviewer.
* **`docs/marketing/store-text.json` holds the old live store text** (Shard 10, "loses money", "board refreshes every
  30 seconds"). `docs/` is not this game's to edit; the new text is in `README.md` for whoever publishes.
* **Gamepasses stay off** (`Config.Passes`, no real IDs); none is planned for v1.
* **Owner decision: may a paid pass move the highscore board? DECIDED 2026-09-30 (owner: take recommended).** The note
  asked "decide first whether a paid pass may move the board" and marked no option. Taken: **no**. The owner's brief is
  fair and never exploitable, and the standard ranks "a server-measured metric that a script cannot inflate" and rules
  out pay-to-win (§3); a pass that doubled the board metric would let money buy rank. So `DoubleDust` still doubles the
  dust a player spends (what it would be sold as), and the board counts every harvest at its un-doubled value
  (`grantHarvest` in `Main.server`). Test first: `robloxemu/check_growacrystal_pass.luau` failed on the unchanged game
  (the pass owner's saved `totalDust` 23 600 against 21 800 un-doubled, board 236 points against 218), then 10 / 0.
  Details in §16.
* **Pass 2b (§17) was checked by its author's tests and mutation sweep only**; no third reviewer.
* **The save-state retry rests on the emulator's DataStore**, which never yields: the case of a player who leaves while
  a retry's UpdateAsync is in flight (the retry then gives the lock back) cannot be produced there, like the older
  "leaves during loadProfile" guard. It is read, not tested.
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

---

## 14. Review round 2 (2026-09-30): six findings, the owner's decisions, the queued job

A second independent reviewer worked on a scratch copy and reported six findings, with probes. This session ran each
probe against a bundle of the unchanged tree first. **All six reproduced; none was rejected.** Each got a failing test,
then a fix in the game. The owner's two open decisions (§11) and the queued job (the salt) were done the same way.

| # | finding | reproduced (unchanged tree) | failing test first | fix | after |
|---|---|---|---|---|---|
| 1 (high) | the refraction roll is predictable from the State push | `probe_predict`: 48 of 48 predicted | `check_growacrystal_salt` 3 failures (48 of 48, the client's seed 48 times, 1 distinct salt); `Rarity.spec` 2 | a salt per harvest from `rollSalt = Random.new()` in `Main.server`; `Rarity.rollSeed` | 9, 11 and 12 of 48 matched in three runs (chance 13.2), 48 distinct salts; the reviewer's probe 24 of 48 (its mix of Shard and Legendary seeds, chance 27.4) |
| 2 | a Mythic inside a Legendary row loses flash, shake, card and beam | `rv2_mythic`: 10 failures | `check_growacrystal_flash` 18 failures; `Grotto.spec` 7 | higher tier skips the cooldown and replaces the flash; `Grotto.outranked` for card and beam | flash 55/0, `rv2_mythic` 11/0 |
| 3 | the title card covers the Relax button and the chip on landscape phones | `rv2_card`: 8 of 40 (50×37 px of the button at 640×300) | `check_growacrystal_row` 8 failures | the card sits under the row | row 581/0, `rv2_card` 40/0 |
| 4 | per-plot lights and sparkles uncapped; every crystal rebuilt every 5 s; docs false | 58 lights, 50 emitters, 322 particles/s; 144 instances rebuilt per 5 s | `check_growacrystal_plotbudget` 19 failures | crystals updated in place; `applyPlotBudget`, `Config.PlotBudget` | 16 lights, 50 emitters, 82/s; 0 rebuilt in 30 s (and in the reviewer's `probe_churn` over 60 s) |
| 5 | an autosave overwrites a session another server holds | `probe_lock`: dust 99999 → 100, WELCOME redeemable again | `check_growacrystal_lock` 13 failures | a session token on load; every save checks token + jobId | lock 26/0; `probe_lock` keeps SERVER-B's record |
| 6 | refused actions give no feedback | `probe_silent`: 6 of 7 refusals sent nothing | `check_growacrystal_refused` 16 failures; its dead-end part 3 more before the free Shard, and its toast-size part 1 (9.0 px on an 800×360 phone) | `refuse()` with the reason and price everywhere; "Type a code first"; the phone toast's text and width caps | refused 99/0; `probe_silent` 7 of 7 toast; smallest toast 12.0 px |

**Why a salt per harvest, not per session.** The checklist says "a per-session, server-only salt". Here every roll's
result is shown to the player (their dust, codex and the burst), so a salt fixed for a session is one constant a script
could solve for from the tiers it has seen, and then predict the rest of the session. Drawing it per harvest from a
server-only `Random` seeded by the engine's entropy leaves nothing to solve for, and the stream is shared by every player
on the server. **The odds are unchanged:** with a uniform salt every seed in [0, 2^31 - 1) is equally likely, and
`Rarity.spec` measures it against the exact odds over 100 000 rolls per case (exact / salted / old formula):
Shard at luck 0 0.5000 / 0.4994 / 0.5000 (Quartz 0.3250 / 0.3255, Amethyst 0.1365 / 0.1364), Shard at luck 3 0.2750 /
0.2763 (Quartz 0.3571 / 0.3532), Legendary at luck 0 0.9500 / 0.9504; every tier within 5 sd (the worst |z| per case:
0.52, 2.52, 0.61).

**Refusals and their reasons** (all through `refuse()` in `Main.server`): "Still growing — ready in 60s"; "Not enough
Gem Dust: chamber 2 costs 500" (and for Luck Lv1, Growth Lv1, a seed, the Geode, each with its price); "Legendary seeds
unlock at chamber 5" (also when a selected locked seed is planted, which used to say "not enough Gem Dust"); "Every
chamber is already open"; "Luck is already at its max level"; "This week's Geode is cracked — back next week";
"Couldn't save — nothing spent, try again"; "Out of Gem Dust, so here's a free Shard seed 🌱"; "Opened on another server
— this one won't save" (once). The HUD answers an empty code with "Type a code first". On a phone the toast used to be
capped at 15 design px, which the 0.6 UIScale makes 9 screen px; it may now use its whole 24-px line and the screen's
width (smallest measured over 15 messages × 10 viewports: 12.0 px, on a 1024×768 tablet).

**Changed on the way, and why.** Two `Economy.spec` assertions pinned the old Shard price (30 - 10 = 20); they now read
`30 - SeedCost[1]` and a new assertion pins the decided price, 7. `Pacing.spec`'s two FINDING assertions were written to
fail when the economy was retuned (§2 said so) and are now requirements. `IdleModel` mirrors the server's free Shard
through the same pure rule. No other existing assertion was changed.

**Written in `grow-a-crystal/`:** `src/server/Main.server.luau` (salt, owner token, in-place crystals and the plot
budget, refusals, free Shard); `src/shared/Rarity.luau` (`rollSeed`), `Economy.luau` (`needsFreeSeed`), `Config.luau`
(Shard 7, `PlotBudget`, corrected budget comment), `Grotto.luau` (`flashDue` tiers, `outranked`), `CavernArt.luau`
(`BeamLife`); `src/client/Grotto.client.luau` (flash, card and beam ranks; the card under the row) and `Hud.client.luau`
(empty code, the phone toast); `tests/Rarity.spec`, `Economy.spec`, `Grotto.spec`, `Pacing.spec`, `IdleModel.luau`;
this file and `CLAUDE.md`, `README.md`. **In `robloxemu/`:** `check_growacrystal_salt`, `_refused`, `_lock`,
`_plotbudget` (new), new assertions in `check_growacrystal_flash` and `_row`, and `build/grow-a-crystal.luau`. Nothing in
`robloxemu/emu`, `tools`, `docs` or another game was written. Nothing was committed, pushed or published; Studio was not
opened. The probes and the sweep ran on scratch copies.

---

## 15. Pass 2: the complete-game standard (2026-09-30/10-01)

The owner's finish line is `docs/complete-game-standard.md`. Every item was checked against the game; this is what
was missing, what was built (each with a failing test first), and what is left.

**Built.**

1. **§3 Highscore board, public + friends** (`src/shared/Board.luau`, adapted from plus1-jump's; `Config.Board`;
   `Cavern.board`; the board section of `Main.server`). Before: a HUD panel of raw `totalDust`, `SetAsync` on every
   autosave (reproduced: **90 writes in 10 idle minutes** for three players with nothing changed), names looked up by
   the client on every 30-s refresh, no friends view, no physical board, no tie-break. Now: the metric is dust earned
   from harvests in points of 100 (codes, Geode and purchases never add to it; the roll is salted), stored as
   `points * 2e9 + (2e9 - reachedAt)` in `GrowCrystal_LB_v2` through `UpdateAsync` + `Board.keepHigher`, **written only
   when the points rise** (0 writes in 10 idle minutes). The time a player's points last rose is saved in the profile
   (`boardAt`), and a pre-board profile is stamped with its next session. The public top 10 is read once per 60 s for
   the whole server; friends are fetched only on the prompt, pages read to at most 200, cached 5 min, a failure cached
   60 s, score reads through one token bucket (40, then 1/s) with the DataStore budget reserve; friends on the server
   use their live points; names come from the friends pages or one cached lookup, never saved. The board stands on each
   cavern's entrance wall behind the spawn (8.5 studs; the prompt reaches 12); anyone but the owner who triggers it is
   told why. The HUD panel shows the same rows with names sent by the server. Tests: `tests/Board.spec.luau` (95),
   `Cavern.spec` +13, `robloxemu/check_growacrystal_board.luau` (81).
2. **§1 One walk of the whole path** (`robloxemu/check_growacrystal_walk.luau`, 34): join, spawn on the own pad facing
   the sockets, plant within 5 s, "still growing" 5 s early, harvest at 60 s, buy a Shard with the HUD's own button,
   leave (lock released), let the crystals grow offline, rejoin with dust, seeds, codex and both plants kept, harvest.
   `os.time` is the emulator's virtual clock in that run only; the game is unchanged.
3. **§2 The brag moment** named and measured (§2 above; `Config.Pacing.Brag`; `Pacing.spec` +8).
4. **§1 No silent no-ops**: clicking another player's socket or crystal now says whose cavern it is
   (`check_growacrystal_refused` +4; the text is short enough for 12 px on a tablet).
5. **The first-run hint** was about 7.6 px on a desktop monitor and 4.6 px on a phone: one 100-glyph sentence in a
   460-px line. Now a short "tap" line across the screen on phones and a shorter line up to 800 px on desktop; smallest
   12.8 px (tablet) (`robloxemu/check_growacrystal_hint.luau`, 17).
6. **§4 docs**: the store description in `README.md` (950 characters), the clip list in `MARKETING.md` (7 clips and one
   held), the 1920x1080 output size and a held board shot in §9, needs-Studio items 28-31, and `CLAUDE.md`'s gates,
   state and traps.

**Already met, checked, not rebuilt.** Spawn (`check_crystal_spawn`); the salted roll, the owner token and the
refusals (review round 2); Fx preset, five bands, harmless visitors instead of hazards, Relax; server budgets capped in
code (`applyPlotBudget`) and client budgets capped by construction (fixed pools, measured by `check_growacrystal_env`,
reason written next to `Config.Budget`); root Frame + UIScale, 44-px tap targets and the overlap rule 4b asserted with
`overlap = true` in both HUD checks (`check_crystal`, `check_growacrystal_hud`); codes public, no Robux cost.

**Mutation sweep (pass 2).** 46 mutants over every new assertion (Board rules 7, board placement 3, Config 6, server
21, HUD 5, the walk's guards 5): **46 killed** (one, B3, survived the first run because with 100 dust per point the
K-form truncation never binds; `Board.spec` now also checks a finer point, and B3 is killed). Each mutant was proved
to be in the rebuilt bundle and each file was restored byte-identical by sha256. The control (the board slab one
shade lighter) survived all 38 suites. `check_crystal_sockets`' exact part count moved 156 → 157 for the board (still
an exact pin).

---

## 16. Pass 1 re-run (2026-10-01): the round-2 findings re-verified, the last owner decision

The workflow ran pass 1 again ("try again"). The tree already held round 2's fixes (§14) and pass 2 (§15), so this
session checked them instead of rebuilding them, and took the one owner decision that was still open.

**The six findings, re-run with the reviewer's own probes.** Each probe ran on a bundle of the reviewer's scratch copy
of the reviewed tree and on a bundle of this tree (scratch copies; paths are the only bundle difference).

| # | probe | reviewed tree | this tree |
|---|---|---|---|
| 1 | `probe_predict` (luck 3, 48 crystals, half Shard, half Legendary) | 48 of 48 predicted | 23 of 48 (chance for this mix 27.4) |
| 2 | `rv2_mythic` | 1 passed, 10 failed | 11 / 0 |
| 3 | `rv2_card` | 32 passed, 8 failed (50×22 px of the Relax button at 800×360) | 40 / 0 |
| 4 | `probe_server_budget` (chamber 8, 48 ready) | 58 PointLights, 50 emitters, 322 particles/s per plot; 126 lights in the workspace | 16, 50, 82/s; 42 |
| 4 | `probe_churn` (60 s) | 144 instances rebuilt every 5 s | none rebuilt; 114 crystal instances |
| 5 | `probe_lock` | SERVER-B's record overwritten: dust 100, chambers 1, totalDust 0, WELCOME redeemable | kept: dust 99999, chambers 5, totalDust 5000, WELCOME redeemed; the session stops saving |
| 6 | `probe_silent` | Luck, a locked seed and the Geode with 5 dust: 0 toasts each | 1 toast each |

All six reproduce on the reviewed tree and none on this one; none was rejected. The queued job (the salt, finding 1)
is in place: `Rarity.rollSeed` with a per-harvest salt from `rollSalt = Random.new()`, odds measured in `Rarity.spec`
(§14). Round 2's mutation sweep, re-run: 43 of 43 as expected (§7.1).

**The last open owner decision (§11): a paid pass never moves the board.** DECIDED 2026-09-30 (owner: take
recommended). No option was marked, so the one that serves the brief was taken (fair, never exploitable, and the
standard's "never pay-to-win"): `DoubleDust` keeps doubling the dust a player spends, and `grantHarvest` adds the
un-doubled value to `totalDust`, the board metric. Passes are still off (`Config.Passes`); this settles the rule before
one is ever switched on.
* Test first: `robloxemu/check_growacrystal_pass.luau` (new). Two saved profiles with the same six ripe Legendary
  crystals, one owning `DoubleDust`; every crystal is clicked through the real server, both players leave, and the
  saved records and the board store are read back. On the unchanged game: 8 passed, 2 failed (`totalDust` 23 600
  against 21 800 un-doubled; 236 board points against 218). After the fix: 10 / 0, and 10 / 0 in five more runs.
* Mutations (`gac_p1b/pass_mutations.json`, the round-2 harness):

| id | what the mutation breaks | killed by |
|---|---|---|
| PM1 | the board counts the doubled dust again (the decision undone) | pass |
| PM2 | the board metric takes the pass flag | pass |
| PM3 | the pass no longer doubles spendable dust (the check would then test nothing) | pass |
| PM4 | every harvest counts double on the board, pass or not | pass |
| PM5 | `DoubleDust` triples | Economy.spec, pass |
| CTRL-P | *control*: `false` spelled `nil` (same behaviour) | survived ✓ |

* luau-analyze: still not fetched. Downloading a binary needs an explicit go in chat, and a relayed "take the
  recommended option" is not one.

**Gates (final tree, bundle sha256 `6d308ffb651a…`): 39 suites, every exit code 0.** 17 specs, 1 323 assertions;
22 headless checks, 1 412 assertions plus 2 PASS verdicts (§7).

**Written:** `src/server/Main.server.luau` (`grantHarvest`: the board metric adds the un-doubled harvest, +4 lines),
`robloxemu/check_growacrystal_pass.luau` (new), the bundle, this file (§7, §7.1, §11, §16), `CLAUDE.md` and
`README.md`. Nothing committed, pushed or published; Studio not opened. The probes and sweeps ran on scratch copies.

---

## 17. Pass 2b (2026-10-01): the standard checked item by item again, three gaps closed

The workflow ran pass 2 again. Every item of `docs/complete-game-standard.md` was checked against the code and the
gates, not only the reviewer's list (most of which §14-§16 had already closed). Three gaps were found. Each was
reproduced on the unchanged game, then a failing test was written first, then the game was fixed. Nothing in an
existing test was loosened.

**1. §1 "it works, and it is honest": a session that could not save said nothing and never recovered.** Probe on the
unchanged game: a player who rejoined within 45 s of a server crash (the dead server's lock still on the record) got
**0 messages**. They played a session that never saved: two minutes later, long after the lock had expired, they had
bought a seed and the record still said 1 234 dust. A returning player (4 321 dust) whose load call failed once was
shown a new profile (30 dust), with 0 messages, and nothing they did was saved. A server with no DataStore said nothing
either. A chamber could even be bought on the locked copy, and was lost on leaving. Now:
* `loadProfile` marks the session `locked` (another server's lock), `retry` (the call failed) or `nostore` (no
  DataStore, or a failed load in Studio, where API access is off for the whole session), and the join tells the
  player once (`Config.Save.Text`).
* Every autosave retries a `locked` or `retry` session (`retryLoad`). It takes the lock as soon as it is free. If
  nobody has written the record since this session read it (same jobId, token and lockUntil; every write of every
  version sets lockUntil), what was played meanwhile is kept and saved. Otherwise the record is newer, so it is loaded
  and the cavern is rebuilt to it. Either way the player is told.
* While waiting, codes and the Geode are refused (they could not persist), and chambers wait, because a built terrace
  cannot be taken down if a newer record replaces the copy.
* Test: `robloxemu/check_growacrystal_rejoin.luau`. Its first version gave **11 passed, 35 failed** on the unchanged
  game; the final version gives **53 / 0**. Every message reads at 12.0 px or more on every viewport.

**2. §4 the clip list could not be staged as written.** Clips 4-7 are staged "off camera: codes, then buy chamber 2",
and clip 5 with the weekly Geode, in Studio with API access off. Probe on the unchanged game, in a session with no
DataStore: WELCOME, CRYSTAL and MYTHIC all came back `retry` and dust stayed 30, and the Geode was refused the same way.
Both refuse a grant they cannot persist, which is right when a save is possible but failed, and pointless when no save
can ever happen. A session that can NEVER save (`nostore`) now keeps the codes' and the Geode's grants for the session.
Nothing from it persists, the reward included, so there is nothing to duplicate, and it says so at join. A session
that could save but cannot right now (`locked`, `retry`, a lost lock) still refuses, which `check_growacrystal_rejoin`
and `check_growacrystal_lock` hold. Test: `robloxemu/check_growacrystal_clips.luau` plays every clip's staging through
the real HUD and server: **32 passed, 19 failed** on the unchanged game, **51 / 0** now. It also checks the clip
list's numbers against the game: 5 600 dust from the codes, chambers 500 and 1 100, Legendary weeks 2026-10-12..18
and Mythic 2026-10-19..25 (and this week, 2026-09-28..10-04, is Legendary), 20 and 40 minutes of growth, socket 9 in click range from the spawn. And it checks the buttons
the way `film_game.py`'s `laby_click_gui` finds them (the first TextButton whose text matches a Lua pattern). The Geode
button reads "→ Legendary" too, so `MARKETING.md` anchors the seed row's pattern: `^Legendary`.

**3. §2 "each with its own … critters and weather".** The first three bands had moths only, and the first two had
drips only. Band 2 now has **glowflies** (5, blinking blue-green among the strands) and **glow-worm silk** (4/s
drifting down), and band 3 has **fireflies** (6, blinking amber in a low layer under the moths, y 30-35, above every
head like every other critter). `EnvConfig.spec` gave **11 failed** on the unchanged game: two bands had no critter of
their own, one had no weather of its own, and no critter kind had a look that could be asked for. It now gives
**499 / 0** with: at least five bands; each band after the first brings its own critter and weather kinds; every
kind can be drawn; every zone clears a standing head by 3.5 studs. `check_growacrystal_env` (+15) counts each full
band's own critters and weather in the world, sees glowflies and fireflies blink, and measures every ambient critter's
height in every band (lowest 4.5-9.7 studs over 8 runs). Budgets: §6 (peak 130 of 150 local parts).

**Also fixed: a flaky gate.** `check_growacrystal_salt` read the real clock and dropped a harvest that straddled a
wall-clock second. It failed **1 run in 40** under parallel load ("47 harvests, want 48"). It now runs on the virtual
clock (like the walk check): **0 in 40**. The two salt mutants below prove the check still bites.

**Already met, checked, not rebuilt.** §1: the walk (`check_growacrystal_walk`), spawn (`check_crystal_spawn`,
`RespawnLocation` = an enabled pad), the per-harvest server-only salt (the seed drives no geometry), the owner token,
string keys and `numKeys`, every refusal toasted. §2: Fx Cozy + signature particles, five glided bands, harmless
visitors instead of hazards (§3 says why), Relax (growth is server time, so a rest earns nothing extra), server budgets
capped in code (`applyPlotBudget`), client budgets capped by construction (fixed pools, `EnvBands.capRates`, measured),
the brag moment (first Mythic: median 31 min, p10 4, p90 70, normal profile; `Pacing.spec`) and the long-term goal
(Heart of the Geode, median 238 min), root Frame + UIScale, 44-px taps, and overlap rule 4b asserted (`overlap = true`
in `check_crystal` and `check_growacrystal_hud`). §3: the public + friends board, as built in pass 2
(`check_growacrystal_board`, 81 / 0). §4: the store text (950 characters, ASCII only, every number recomputed from
Config: 1 in 4 329 at Luck 0, 1 in 58.3 at Luck 10), the thumbnail shot list (1920x1080), the needs-Studio list.

**Mutation sweep (pass 2b).** Every mutant was run against all 41 suites (8 in parallel), proved in the rebuilt bundle
(the mutated file found verbatim in it), and its file restored byte-identical by sha256. The bundle hash after the
sweep equals the hash before it (`c4b2bc7ce01d…`).

| id | what the mutation breaks | killed by |
|---|---|---|
| SV1 | the join message removed | clips, rejoin |
| SV2 | a locked load is not marked locked | rejoin |
| SV3 | the autosave never retries a load | rejoin |
| SV4 | resume without the fingerprint (overwrites a newer record) | rejoin |
| SV5 | never resume (discards what was played while waiting) | rejoin |
| SV6 | a reload does not rebuild the chambers | rejoin |
| SV7 | chambers bought while waiting | rejoin |
| SV8 | no session-only code grant without a store | clips, rejoin |
| SV9 | no session-only Geode without a store | clips |
| SV10 | codes granted while locked (a dupe) | rejoin |
| SV11 | Studio without API access retries forever | rejoin |
| SV12 | the lock fingerprint is not kept | rejoin |
| SV13 | a failed load that finds the record locked does not load it | rejoin |
| BD1 | band 2 has no critter of its own | EnvConfig.spec, env |
| BD2 | band 2 has no weather of its own | EnvConfig.spec |
| BD3 | band 3 has no critter of its own | EnvConfig.spec, env |
| BD4 | fireflies at head height (zone from y 22) | EnvConfig.spec, Grotto.spec, env (+ salt, before its clock fix: a flake) |
| BD5 | glowflies and fireflies do not blink | env |
| BD6 | no silk volume | EnvConfig.spec, Grotto.spec, env |
| BD7 | no glowfly look | EnvConfig.spec, clips, env, race |
| BD8 | four bands (the waterfall band removed) | EnvConfig.spec, env |
| SALT0 | no salt (after the salt check's clock change) | salt |
| SALTFIX | one salt for the whole server | salt |
| GEO4 | the Geode rotation's fourth week Mythic, not Legendary | Geode.spec, clips |
| CTRL-A | *control*: the retry's session token `.. ""` (same string) | survived ✓ |
| CTRL-B | *control*: firefly `speedMax = 3` spelled `3.0` | survived ✓ |

24 of 24 real mutants killed, 2 of 2 controls survived, 26 of 26 in the bundle, 26 of 26 restored.

**Not tested, and why.** A player who leaves while a retry's UpdateAsync is in flight: the retry then gives back the
lock it has just taken. The emulator's DataStore never yields, so this cannot be produced there (the same holds for
the older "leaves during loadProfile" guard). It is read, not tested.

**Gates (final tree, bundle sha256 `c4b2bc7ce01d…`): 41 suites, every exit code 0.** 17 specs, 1 392 assertions;
24 headless checks, 1 531 assertions plus 2 PASS verdicts (§7).

**Written:** `src/server/Main.server.luau` (save states, the join message, `retryLoad`, the chamber wait, session-only
grants without a store), `src/shared/Config.luau` (`Config.Save.Text`; bands 2 and 3; the two critters),
`src/shared/Grotto.luau` (two zones, the silk volume), `src/shared/CavernArt.luau` (the two looks with their blink, the
silk emitter, `hasCritter`), `tests/EnvConfig.spec.luau`, `robloxemu/check_growacrystal_rejoin.luau` and
`check_growacrystal_clips.luau` (new), `check_growacrystal_env.luau` and `check_growacrystal_salt.luau`, the bundle,
this file (§2, §6, §7, §8 items 32-35, §9 shot 1, §11, §17), `MARKETING.md`, `README.md` and `CLAUDE.md`. Nothing was
committed, pushed or published, and Studio was not opened. The probes and sweeps ran on scratch copies and through
`scratchpad/gac_p2c/sweep.py`.

---

## Night shift 2026-10-09: Studio check and second review of 7e691f3 + ad8a823

**Studio** (job H step 1): see `STUDIO.md`. The blank HUD board was fixed (`Board.hudNote`).

**Second review** (job H step 2). One independent read-only reviewer was asked to refute both commits. It
confirmed these hold:
- the server-only refraction salt;
- the owner token on writes;
- the locked/retry handling;
- harvest-only board points with a server-side tie time;
- client-only eye-candy;
- checks that drive the real bundle.

Its verdicts:
- **7e691f3: SHIP.**
- **ad8a823: SHIP-WITH-DEFERRED.**

Findings:
1. **MEDIUM. No `RunService:IsStudio()` gate.** A Studio session run with §9's cheat config while API access is
   on would write that cheat dust and the board score to the live stores. **Not fixed.**
2. **MEDIUM, now CONFIRMED and FIXED: server freeze through Redeem.** `Codes.normalize`'s
   `"^%s*(.-)%s*$"` is quadratic on the raw RemoteFunction string. Measured in Studio:
   - 20 000 spaces: 1.37 s of server time;
   - 30 000 spaces: 3.1 s.

   Fixed in d35112e: `Codes.MaxInput = 64`, and the input is cut before the trim. The test went red first,
   the mutations were killed, and the control survived. +1 Jump had the same module and is fixed in the same
   commit. **It is not live until the next publish.**
3. **LOW-MEDIUM. A failed leave-save is not retried** (up to 20 s of progress lost). Not fixed.
4. **LOW-MEDIUM, suspected. BindToClose saves serially.** Not fixed.
5. **LOW. Spamming the board prompt queues unbounded friends reads.**
6. **LOW. A rollback after a failed save can leave a seed count at -1** (one free seed).
7. **LOW. The "locked" toast does not warn that the play on this server may be discarded.**
8. **LOW, suspected. A two-Studio-server test cannot show the lock**, because the JobId is empty.
9. **LOW. The commit message overstates the emitter cap.**
10. **LOW. A player who leaves during the load keeps the lock** (it recovers through "resume").
