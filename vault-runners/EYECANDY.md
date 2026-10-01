# Vault Runners: the strata you run through

Owner's brief (Gustav, 2026-09-17): every game visually richer and never monotonous, with the
environment changing as the player progresses in a way that fits the game; rare hazards that are
telegraphed and easy to dodge (about one near-hit per 2-3 minutes); a way to rest that can never be
an exploit; and a thumbnail shot list for the night Studio session.

For this game the brief adds: a timed vault run (a maze floor with the collapse racing you, an obby
shaft of crumbling pads between storeys, and a slack schedule tuned so pressure rises with depth).
The crumbling pads must stay readable, the time budget must not change, and rest must not freeze the
collapse mid-run.

**State: built, unit-tested, headless-tested, mutation-tested, through two independent adversarial
reviews (§12, §13) whose findings are all closed, and with the owner's three decisions applied
(§10, DECIDED 2026-09-30). It has NOT been seen in Studio.** The eye candy up to §12 was committed as
511793d (2026-09-24). §13 (REVIEW-5, 2026-09-30) is in the working tree, not committed, not pushed,
not published. The eye candy still never touches a rule; REVIEW-5 changed the server only for the
obby review (how often it looks at the shaft, REVIEW-5.md §1.3), not for anything on this page.

**Resumed after a usage limit (§11).** The earlier attempt had finished the code and its tests and
was running its mutation sweep when it stopped. It had printed nothing and had not written this
file. The resume session re-read every new and changed file, rebuilt the bundle (byte-identical to the
one on disk), and re-ran every gate: all green. It then found and fixed three defects in the game and
one in its tests, each one test first (§11). It also closed three promises that no test held and
measured the budgets with drops in the air, and it ran the mutation sweep in full (§7).

**Review round (2026-09-24, §12).** An independent adversarial review re-ran every gate and found five
things. All five reproduced. Four are fixed, each with a failing test written first:
* the crumbling pad read WHOLE, or flashed "it's back", for 0.07-0.25 s plus ping right before the
  server dropped it;
* gems vanished into the Frozen Vault's ice (1.10:1) and the tomb's sandstone (1.16:1);
* the drop's ring vanished on the Frozen Vault's snow (1.16:1);
* the hub's stratum signs overlapped the portal labels on a phone.

The fifth (near-hits on a moving runner) was the owner decision in §10, now DECIDED.

**Second review round and owner decisions (2026-09-30, §13, REVIEW-5.md).** Three more findings, all
reproduced and fixed test first: every `Config.Budget` is now a CAP in code, not only a number the
checks compare against; gems and the exit pad no longer wear the pads' colour (in four strata, not
the two reported); the stale "uncommitted" text is gone. The owner's decisions: the Frozen Vault (the
brag) now arrives inside 30-45 minutes; near-hits are left as they are; and the endgame turns through
three HALLS of the Volcano Temple instead of being one room for ever.

**Pass-1 re-run (2026-10-01, §14).** The workflow ran pass 1 again on the tree above. It treated that
tree as unverified: every finding was reproduced on HEAD 511793d and measured fixed in the working
tree, the owner's decisions were re-measured, and the mutation sweep was re-run. It changed one
comment (`Config.Budget` said the budgets were only measured; they are caps) and the state text, and
it found one thing the gem rule does not cover: a pad CRUMBLING under a Bronze runner passes 44.6 RGB
from the orange gem in the Bank Vault (§8.6, on the Studio list). A highscore board was half-built in
the tree by a later, interrupted pass, with its check red on purpose; pass 2 finished it (§15).

**Pass 2 (2026-10-01, §15): the rest of docs/complete-game-standard.md.** The DEEPEST ESCAPES board
stands west of the hub spawn (public top 10 or friends, toggled by its ProximityPrompt), built against
the check the interrupted pass left red, with that pass's tie bug fixed. Four more gaps closed test
first: a per-session owner token on every profile write, every player's `RespawnLocation` on the hub
spawn, a shutdown that saves every profile, and a gated store text. And one the reviewer had not listed:
the standard asks every band for its own **critters**, and the strata had none. Now each has its own
(§2.5): rats, scarabs, drones, frost bats and salamanders, client-only and inert, inside the maze
cells around the runner, capped by a new `Budget.MaxCritters`. `MARKETING.md` holds the clip list; §8
and §9 gained the board and the critters. No drop, rest rule or existing budget changed.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template, verbatim** from +1 Jump (`diff` is empty): progress value → band + eased blend, glide (`approach`), weather cap (`capRates`), announcer. Pure. |
| `src/shared/Rest.luau` | **template, verbatim** from +1 Jump: rest rules, `validate` refuses `WakeOnMove = false` and `BlockWhileThreat = false`. Pure. |
| `src/shared/Hazards.luau` | **template, adapted.** Kept from the template: the scheduler (a clock that runs only while you play, frozen and never reset), one hazard at a time, a due hazard HELD while you stand somewhere it must not fire, the zone rule (the ring IS the danger) and the capped knock. Changed: the flight. A vault storey is a maze with a ceiling 16 studs up, so a lane flying in from the sky would pass through walls. A vault hazard is a **chunk of ceiling** that follows you, locks, and drops. Pure. |
| `src/shared/VaultEnv.luau` | new, pure: `depth` (the progress value), `locate`, `inShaft`, `hazardEligible` (where and when a drop may start), `danger` (the collapse as the runner feels it, from the real kill plane), `propSites` (decoration from storey, cell and seed only), `contrast` / `readablePad` / `palette` / `crackedPad` (the obby stays readable). |
| `src/shared/VaultArt.luau` | new, client-only art: ceiling props, sky pieces over the top storey, weather, collapse dust and sparks, the drops, debris, pad cracks, the hub's vault door. Code-only, pooled, inert. |
| `src/client/Vault.client.luau` | new glue: depth → strata → Lighting / colours / props / sky / weather; the collapse's dust, sparks, grade and rumble; pad cracks; drops and the knock; rest in the hub; the band chip, title cards and portal signs. |
| `src/client/Hud.client.luau` | a few lines: each unlocked vault row also shows the stratum emoji of its next floor (`Floor 1 🏦`). |
| `src/shared/Config.luau` | + `Env` (5 bands, hub look, danger grade, shaft thinning, pad contrast), `Hazards` (5 kinds), `Rest`, `Budget`, `Pacing` (model profiles; the resume session added `reader`). Nothing above the `Env` section changed. |
| `tests/` | `EnvBands.spec`, `Rest.spec` (template, verbatim), `Hazards.spec` (adapted), new `VaultEnv.spec`, `EnvConfig.spec`, `Pacing.spec`, and `VaultModel.luau` (a test-side model of a player on the real vaults). |
| `check_vaulthud.luau` | now loads `Vault.client` as well, so the fit and overlap rules measure both ScreenGuis together. |
| `robloxemu/check_vaultrunners_env.luau` | the strata through the real client and server (§2, §5, §6). |
| `robloxemu/check_vaultrunners_hazards.luau` | the drops through the real client (§3); the resume session added §6 (budgets with drops in the air) and §7 (the chunk hangs from the ceiling and lands on the floor). |
| `robloxemu/check_vaultrunners_static.luau` | every bundled source compiles (`loadstring`), no string `require`, the client fires no remote, writes no attribute, and writes only `Color` / `Reflectance` on server parts. |
| `robloxemu/check_vaultrunners_shaft.luau` | **new in the resume session**: the shaft stays readable (§2). |
| `robloxemu/check_vaultrunners_cards.luau` | **new in the resume session**, from the mutation sweep: a returning player's title cards (fanfare only when deeper than ever cleared), and the weather cap and the unreadable-pad fallback forced in memory (§7). |
| `robloxemu/check_vaultrunners_readable.luau` | **new in the review round** (§12): the gems, the exit pad and the drop's ring read against the floor and walls AS PAINTED, in the tomb, the Frozen Vault and the Volcano Temple; the hub's signs never overlap the portal labels (14 175 projected views). §13 adds: the gems and exit are not the pads' colour. |
| `robloxemu/check_vaultrunners_budget.luau` | **new in §13**: every budget is a cap. Forced in memory: props in every cell, and budgets below what the scene asks for. |
| `robloxemu/check_vaultrunners_halls.luau` | **new in §13**: the Volcano Temple's three halls through the real client. |

---

## 2. The strata and what triggers them

**Trigger: DEPTH, never time.** `depth = Config.Env.TierDepth[tier] + floor`, read from the run the
SERVER started (its `"start"` event carries the tier and floor). A harder vault is a deeper vault
(`TierDepth = { 0, 25, 55 }`: Bronze floor f is depth f, Silver floor 1 is depth 26, Gold floor 1 is
depth 56), so unlocking Silver or Gold carries on down the strata instead of starting again at the
bank. `Pacing.spec` checks that no tier unlock ever sends a normal, fast or slow player back to an
earlier band. The chip, cards and signs read the same number, so they always agree.

**The pad colours changed in §13** (bank gold to marble, tomb cream to gilded gold, volcano bone to
jade) and the Frozen Vault's gem from sapphire to amethyst, so that no gem or exit pad wears its
pads' colour (§13.2). The Frozen Vault moved from depth 24 to 18 so the brag arrives inside 30-45
minutes (§10, DECIDED).

**The endgame turns: halls** (owner decision, §10, DECIDED 2026-09-30). Every Gold floor is the
Volcano Temple, and a player may live in Gold for hours. From depth 44 it moves to its next hall every
4 depths and wraps round, for ever (`Config.Env.Halls`, `VaultEnv.hall`):

| hall | depths | light (over the volcano's) | weather | props |
|---|---|---|---|---|
| Magma Hall | 44-47, 56-59, 68-71, ... | the Volcano Temple's own | embers 12/s | ember cages |
| Obsidian Hall | 48-51, 60-63, ... | violet Ambient, violet haze, cool tint | obsidian glints (glitter) 8/s | hanging braziers |
| Ash Hall | 52-55, 64-67, ... | grey Ambient, grey haze, a little desaturated | ash 12/s (a new grey weather) | brass lamps |

The palette (walls, floor, pads, gems, the drop's ring) is the volcano's in every hall, so every
readability number below holds in every hall. The chip reads `🌋 Volcano Temple · Obsidian Hall`; a
card names each new hall, with the fanfare only for a hall deeper than any floor the player has
cleared. Measured (`Pacing.spec`, two 8-hour careers): a normal player sees 38 hall changes, one hall
lasting 6.7-21.1 minutes.

**Transitions never cut.** A band blends in over `fade` depths before its `from` (smoothstep), so a
blend floor is half one stratum and half the next: its walls, accents, props (each ceiling site rolls
which band's prop it hangs), weather (both kinds, capped together) and lighting. The floor colour is
the dominant band's own, and the pad colour is CHOSEN, never blended (§2.3). Inside a run every
written value glides with a 0.6 s half-life, and Lighting is written at most 10 times a second, only
on change. Measured through the real client (`check_vaultrunners_env` §5): hub → Bank Vault, the
biggest single frame moves Ambient 12.5 % of the change, with no overshoot. Volcano Temple → hub:
11.3 %.

| # | stratum | depth (fade) | which floors | first reached, minutes: normal · fast · slow (seeds 7 / 8) | walls · floor · **pad** | weather | ceiling props | over the top storey | drop |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏦 Bank Vault | 0 | Bronze 1-2 (3-4 blend into the tomb) | 0 · 0 · 0 | steel grey (a little reflective) · dark green · **marble** | gold glitter 6/s | brass lamps, 30 % of cells | a brass dome ring and a 118-stud skylight | marble slab |
| 2 | 🏺 Pyramid Tomb | 5 (2) | Bronze 5-10 (11-13 blend) | 4.9 / 5.3 · 4.3 / 4.6 · 9.2 / 15.4 | sandstone · brown · **gilded gold** | drifting sand 10/s | hanging braziers with flames, 30 % | a winged sun, 80 studs across | sandstone block |
| 3 | ⚛️ Reactor Core | 14 (3) | Bronze 14-15 (16-17 blend) | 25.7 / 23.8 · 20.3 / 21.1 · 36.9 / 44.0 | gunmetal · dark · **cyan** | sparks 8/s | neon light panels with a beacon, 35 % | a turning neon reactor ring (radius 60) round a glowing core | coolant pipe |
| 4 | ❄️ Frozen Vault | **18** (2) | Bronze 18-33, Silver 1-8 (Bronze 34-39, Silver 9-14 blend) | **40.8 / 37.9** · 32.6 / 32.6 · 54.2 / 62.5 | ice blue (shiny) · snow white · **navy** | snow 14/s | icicle clusters, 35 % | a pale moon and three aurora ribbons | icicle |
| 5 | 🌋 Volcano Temple | 40 (6) | Bronze 40+, Silver 15+, **every Gold floor**; from depth 44 in three HALLS (below) | 135.3 / 134.9 · 106.9 / 119.1 · 210.8 / 218.6 | basalt · near black · **jade** | embers 12/s (rising) | ember cages, 30 % | a basalt crater rim round a lake of lava light | lava bomb |

Lighting per stratum: its own Ambient / OutdoorAmbient tint, Atmosphere colour and haze, bloom and
colour grade (`Config.Env.Bands[*]`). ClockTime stays 0 (night) everywhere, as the server's Cozy
preset has it. The hub has its own look, which is exactly the server's `Fx.Presets.Cozy` numbers, so
the client's first write changes nothing (`check_vaultrunners_env` §1).

Minutes are **minutes of play until a player first RUNS a vault in that stratum**, measured by
`tests/Pacing.spec.luau` playing the real vaults (real seeds, real countdowns, the real kill rule, the
real drops), with the human part written down as a profile in `Config.Pacing`:

* **normal**: 0.85 × WalkSpeed, 0.6 s reading every new junction, misses 8 % of hops (twice what the
  countdown prices), 12 s in the hub between runs, and replays a lost floor along the route it now
  knows. **fast** and **slow** bracket it. Silver unlocks at 90 / 65 / 155 min (normal / fast / slow).
  Gold unlocks after the Volcano Temple for all three.
* Asserted: the tomb within 10 min; the reactor at 15-40; **the Frozen Vault, the one to brag about,
  inside 30-45 min** (was 45-90, at 61); the Volcano Temple at least twice as far and inside 5 h; no
  band lasts under 4 minutes; a slow player reaches the ice within 2 h; in the halls, no hall lasts a
  normal player over 30 minutes or under 4. There is no telemetry yet: **when there is, retune
  `Profiles.normal` first, then the `from` numbers.** The spec prints where each band lands.
* The brag target is 30-45 minutes (docs/complete-game-standard.md §2; DECIDED 2026-09-30, §10).

### 2.5 Critters (pass 2, 2026-10-01)

docs/complete-game-standard.md §2 asks every band for its own light, colour, scenery, **critters** and
weather. Each stratum now has a kind of its own (`Config.Env.Bands[*].critters`, drawn by `VaultArt`,
three parts each, never Neon):

| stratum | critter | where | speed |
|---|---|---|---|
| 🏦 Bank Vault | rats, grey-brown | on the floor | 4 studs/s |
| 🏺 Pyramid Tomb | scarabs, dark teal | on the floor | 1.2 |
| ⚛️ Reactor Core | maintenance drones, gunmetal | 8.5 studs up, bobbing | 2.5 |
| ❄️ Frozen Vault | frost bats, charcoal | 10 studs up, bobbing | 5 |
| 🌋 Volcano Temple (every hall) | salamanders, dark red | on the floor | 2 |

* **Placed like a prop, from (storey, cell, floor seed) only** (`VaultEnv.critterSites`, salted apart
  from the props). A critter lives in ONE maze cell and walks a loop inside it (`VaultEnv.critterOffset`:
  an ellipse of at most `CritterRoam` 3.5 studs, never faster than its speed). A cell centre is always
  open in a perfect maze, so a critter never needs the walls and cannot mark the route or a dead end.
  Never in the shaft cell or over the hole.
* **The runner meets the ones within `CritterReach` (2) cells** of the cell they stand in, nearest
  first, at most `Budget.MaxCritters` (4). On a blend floor each critter belongs to whichever stratum
  its roll falls in, like a prop. None in the hub.
* **Never treasure, never a pad:** `EnvConfig.spec` keeps every critter's body colour at least
  `MinGemPadDistance` (80 RGB) from every gem colour and the pad painted on its floor at every depth
  0-100; the worst is the frost bat against the navy pad on the reactor › frozen blend, 98.3.
* **They yield first:** a critter is hung only under `MaxLocalParts` less the headroom a drop, a
  cracking shaft and debris may need, and `enforceBudget` takes critters down before props.
* Measured through the real client (`check_vaultrunners_env` §4b): in every stratum, standing in the
  storey-0 critter cell nearest the entry, the client shows exactly the critters `VaultEnv` says (4 in
  each), of that stratum's kind, inert, not Neon, in an open cell of the maze, moving; forced to
  `MaxCritters = 1` in memory it shows one.

### 2.1 Inside a run: the collapse as the runner feels it

`VaultEnv.danger` reads the kill plane the server actually moves: 0 while it is 18 studs or more below
the height at which it would catch you, 1 at that height. As it rises: ceiling dust over you goes from
1.5 to 11.5 particles/s, sparks off the plane from 3 to 18 particles/s, the grade pulls up to 55 %
toward a hot red (contrast and saturation up, warm tint), and above danger 0.25 the camera rumbles
every 7.5 s, shortening to every 3 s at danger 1. Measured in `check_vaultrunners_env` §7 (dust,
sparks and grade all rise) and `check_vaultrunners_shaft` §2: three rumbles on the open floor while
the collapse closes in on storey 0, and none in the stairwell.

### 2.2 The obby: read at a glance

* The pad you stand on **cracks**: three dark crack lines spread across its top, and its colour pulls
  toward the crack colour over the 1.1 s crumble.
* **The crack is then HELD at full until the SERVER drops the pad** (review round, §12). It is held for
  as long as you stand on it, and for `CrackHoldSeconds` (1.5 s) past the crumble once you have stepped
  off. A pad only brushed on the way past may never have been counted by the server, and then it
  never drops. Before this fix the pad read whole, or flashed, for 0.07-0.25 s plus ping right before
  it fell (`VaultEnv.padLook`; `check_vaultrunners_shaft` §5: 0 frames of anything but "cracking"
  between the first crack and the drop, on Bronze and Gold, hopping on at 12 and 50 studs/s).
* When the SERVER drops it, **debris** falls. When it comes back 3 s later, it **flashes** for
  `PadFlashSeconds` (0.45 s), unless you land on it first: then it is cracking, and the flash is
  cancelled for good.
* A crack is never drawn on a pad the server says is gone (`check_vaultrunners_env` §6).

### 2.3 The pads stay readable (the brief's own words)

* **The pad colour is chosen, never blended.** On a blend floor, walls and accents lerp, but a lerped
  pad can land on the lerped floor. The reactor's cyan over the frozen white meets at 1.2:1, which
  nobody can read. So the pad is the candidate that stands out most against that floor, or black or
  white if neither reaches 3:1.
* **Contrast, measured at every depth from 0 to 100 in 1/8 steps** (`EnvConfig.spec`; the numbers
  after §13's palette changes):
  * pad against floor: worst 5.64:1 (the assertion is ≥ 3);
  * pad against wall: worst 1.62:1 (≥ 1.5);
  * a pad about to crumble, against the floor: worst 3.06:1 (≥ 2);
  * a cracked pad against a whole one: ≥ 1.5.
* **In the shaft, the weather and the ceiling dust thin to 30 %; the rumble never fires there, and
  since the resume session neither does a drop's landing shake.** `check_vaultrunners_shaft`:
  * volcano embers 12.0/s in the open, 3.6 in the stairwell, 3.6 on pad 3;
  * dust 1.50, 0.45, 0.45;
  * a drop's landing gives 1 camera shake for a runner who stepped aside in the open, and 0 for one in
    the shaft.
* **What a runner has to find stays findable too** (review round, §12):
  * the gems and the exit pad keep their tier's colour where it reads (≥ 3:1 against the floor,
    ≥ 1.8:1 against the walls, and since §13 ≥ 80 apart in RGB from the pads). Where it would not,
    they wear the stratum's own gem colour: gold coin, pearl, isotope green, amethyst (sapphire until
    §13), molten gold. So Silver's gems are amethyst in the Frozen Vault (6.25:1 floor, 4.81:1 wall,
    100 from the navy pads), and Bronze's are pearl in the tomb (7.22 / 2.02, 176.6 from the gilded
    pads);
  * worst over every tier and depths 0-100: 4.70:1 against the floor, 1.82:1 against the wall, and
    90.9 apart from the pads. The black-or-white fallback is never needed (`EnvConfig.spec`);
  * the drop's ring is drawn in the first colour that reads ≥ 3:1 against the floor under it: yellow on
    the dark floors, dark gold on the snow; locked: hot coral red on the dark floors, crimson on the
    snow. Worst 3.20:1 (tomb), and the lock always looks different from the follow (≥ 79 apart in RGB).
    A pure red lock cannot reach 3:1 on the bank's or the tomb's floor at any opacity.
* **No drop can start in the stairwell, on a pad, or next to the hole in the floor above**
  (§3). Nothing hangs below the ceiling over the pads: props skip the stairwell cell and the hole
  cell, and hang no lower than 12.8 studs over their floor. A jumping head tops out near 12.

### 2.4 On screen

* **Band chip**, bottom centre between the thumbstick and the jump button:
  * in a run: `🏺 Pyramid Tomb · ⚛️ in 9 floors`;
  * in the hub: `🏠 Hub · deepest: ❄️ Frozen Vault`.
* **Title card** on the first run in a new stratum this session. It carries a white flash and an FOV
  punch only the first time this player has gone that deep (deeper than the deepest floor they have
  cleared).
* **Portal signs** in the hub, local billboards reading `Floor 1 · 🌋 Volcano Temple`. Each is anchored
  at the server's portal label's own point and laid out 4 px under it IN PIXELS, so the two never
  overlap at any distance or viewport height. The first cut put it 6 studs lower, and fixed-pixel
  billboards 6 studs apart met beyond ~36 studs on a 390 px phone, i.e. from the spawn view
  (`check_vaultrunners_readable` §3, 14 175 projected views, tightest gap 4.0 px).
* **HUD vault rows** show the next floor's stratum emoji.
* **Hub vault door**: a 50-stud round steel door with a brass rim, spokes and bolts, standing behind
  the three portals. Local, never collidable.

---

## 3. Hazards: ceiling drops, and their measured rarity

| kind | stratum | warning | locks | falls | ring across (hitRadius + 1) × 2 | knock |
|---|---|---|---|---|---|---|
| marble slab | bank | 3.0 s | 1.2 s before | last 0.35 s | 6.8 | 12 studs/s |
| sandstone block | tomb | 3.0 s | 1.2 s | 0.35 s | 7.0 | 12 |
| coolant pipe | reactor | 3.2 s | 1.3 s | 0.35 s | 6.8 | 12 |
| icicle | frozen | 3.4 s | 1.4 s | 0.30 s | 6.0 | 10 |
| lava bomb | volcano | 3.0 s | 1.2 s | 0.40 s | 7.0 | 14 |

**The rule** (`Hazards.luau` + `VaultEnv.hazardEligible`, both validated at load; an invalid config
turns drops OFF with a warning, it never breaks the game):

* **When:** one drop per **120-180 s of run time**, on a clock that runs only while a run is going and
  is frozen, never reset, in the hub. Never two at once.
* **Where it may start:** only on the open floor of the maze, never in the stairwell, on a pad, within
  one fine cell of the stairwell or of the hole in the floor above, in the first 12 s of a run, in the
  last 15 s before the seal (the HUD's seal warning shows at 10), or with the collapse within half a
  storey. A drop that comes due there is HELD and starts at the first moment you are somewhere it may.
  It is not re-rolled, so waiting in the shaft cannot shop for a quiet stretch.
* **Telegraph:**
  * a crack opens in the ceiling over you and dust trickles out of it;
  * the chunk wobbles as it hangs from the ceiling, and a red light blinks;
  * a ring at your feet follows you (yellow; dark gold on the Frozen Vault's snow, where yellow read
    1.16:1);
  * the banner reads `⚠️ MARBLE SLAB — keep moving!`.
* **The lock:** 1.2-1.4 s before it lands, the ring LOCKS and turns red (hot coral red on the dark
  floors, crimson on snow: every ring reads ≥ 3:1 against its floor, §2.3), the banner turns red
  (`⚠️ MOVE! MARBLE SLAB ⬇`), the trickle thickens and the light blinks faster. If you walk somewhere
  a drop may not land, it locks where you last stood.
* **The ring IS the danger** (the template's round-2 rule): a hit needs you inside the ring when it
  lands, on the same storey. Step out of it in any direction and you are clear. A runner who never
  stops is never under it: it locks behind you.
* **A hit:**
  * the cost: PlatformStand for 0.9 s, a 10-14 studs/s shove away from the landing and a 4 studs/s
    hop, a camera shake and a white flash;
  * no gems, no death, no pad, no time taken from the countdown. The countdown is VaultPath's, byte
    for byte.
  * Every allowed spot is at least ring + 4 studs from the hole in the floor (`VaultEnv.spec`, every
    fine cell of Gold floor 1), so a knock never sends anyone down a storey.
* Since the resume session, the chunk **hangs from the ceiling** (its top at the underside) and
  **lands ON the floor**, for every kind (§11).

**Measured:**

| measurement | where | result |
|---|---|---|
| scheduler, 20 h of run time | `Hazards.spec` | 480 drops = **one per 150.0 s**; gaps 120.2-180.1 s; never 2 at once |
| the hub freezes the clock | `Hazards.spec` | a 1 000 s pause after 40 s of run time moves the first drop by 0 run-seconds |
| real vaults, normal player, 2 careers × 4 h | `Pacing.spec` | one drop per **2.60 min** of run time (reacts), 2.59 (ignores every warning), 2.59 (freezes when one appears) |
| same: hits | `Pacing.spec` | reacts **0**, ignores **0**, freezes 170 of 170 (the ring is the rule) |
| same: where it lands | `Pacing.spec` | median **23.4 studs** from the runner (p10 19.0, p90 30.1); within 8 studs: 3 of 168 |
| a player who stops 3 s at every new junction (`reader`), first attempts | `Pacing.spec` | ignores every warning: hit by **47 of 238** drops (19.7 %); reacts: 0 |
| what a hit costs that reader | `Pacing.spec` | completion without drops / reacts / ignores: Bronze 1 52.0 / 52.7 / 52.0, Bronze 10 28.0 / 30.0 / 27.3, Gold 1 30.0 / 33.3 / 30.0. **At most 0.7 points** |
| what drops cost a normal player | `Pacing.spec` | Gold 1 / 30 / 100 / 400: 46.0 / 23.3 / 8.0 / 0.7 % in every mode (identical) |
| through the real client and server, shipped interval, 30 min of run time | `check_vaultrunners_hazards` §5 | **12-13 drops = one per 2.31-2.50 min**, never two within 120 s |
| step out after the lock, 8 directions | `check_vaultrunners_hazards` §2 | **8 of 8 dodged**; a runner circling at 20 studs/s for 90 s: 0 hits |
| where a drop may start, through the client | `check_vaultrunners_hazards` §3 | none in the first 12 s; none in 45 s in the stairwell or 10 s on a pad; the held drop starts ≤ 0.1 s after stepping out; none with danger > 0.5; the last starts ≥ 15 s before the seal |
| the ring through the client | `check_vaultrunners_hazards` §1 | exactly as wide as the rule, centred under the runner (≤ 0.05 studs), on the storey floor |

A probe (not a gate) over whole careers:

* a 3 s reader who ignores every warning is hit by 6.7 % of drops (1 per 39 run-minutes), and 8.5 % land
  within 8 studs of them;
* a 6 s reader: 8.0 %;
* the slow profile: 2.0 %.

**The honest reading of "one near-hit per 2-3 minutes" here.** Every drop comes FOR you: the ring
follows your feet for about 2 s under a cracking ceiling and a banner. That happens once per 2.3-2.6
minutes of run time, measured. But a runner who keeps moving is 19-30 studs past it when it lands, so
a drop that lands within a stride of you happens only to a player who stopped (about once every 145
run-minutes for the normal model; about once every 31 for one who stops 3 s at every junction). That
fits the game (the collapse punishes standing still, and so do the drops), but it is not the same
feel as +1 Jump's near-misses. **DECIDED 2026-09-30 (owner: take recommended): leave it** (§10).

---

## 4. Rest: what "pause" means in Vault Runners

A Roblox server cannot pause, and a vault run is a timed round, so **rest is the hub, between runs.**

* In the hub nothing can hurt you, no clock runs (the drop clock is frozen, and there is no countdown
  outside a vault), and no run starts by itself.
* The **☕ Rest** button (bottom centre, thumb-sized on touch) sits you down, softens the view (depth
  of field) and sets the chip to `☕ Resting — the vault waits for you`.
* Press `▶ Play` or move to get up. Tapping a portal starts a run and wakes you. Nothing is lost or
  earned while resting.
* There is **no idle rest** (`IdleSeconds = 0`): there is nothing in the hub to rest from, and nothing
  in a run may pause.
* Roblox's own idle kick (about 20 min) still applies, and the profile is saved on leaving.

**Why it cannot be exploited:**

1. **It cannot follow you into a vault.** The button is hidden during a run. A press that reaches it
   anyway is refused, both in the button handler (`inRun`) and in the rule (`threat = inRun`, and
   `Rest.validate` rejects `BlockWhileThreat = false`). A run starting wakes a resting player.
   `check_vaultrunners_env` §3 drives all of it through the real client.
2. **It touches nothing the server owns.** Rest is client state; the collapse, the seal, the gems, the
   pads and the save are the server's, and the server never hears about rest. It cannot freeze the
   collapse because nothing in the game can.
3. **It cannot thin out drops.** Drops only happen in runs; in the hub their clock is already frozen,
   resting or not. Toggling rest has no effect on when the next drop comes.
4. **Waking needs no permission and costs nothing**, so rest cannot be a trap either.

The shipped Rest module is the template's verbatim (55 assertions); `EnvConfig.spec` pins
`IdleSeconds = 0` and `Rest.validate` on the shipped config.

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| strata, Lighting, colours on the vault (walls, floors, pads, gems, the exit pad), props, sky pieces, weather, collapse dust / sparks / grade / rumble, pad cracks and debris, title cards, chip, portal signs, hub door | **client** (`Vault.client` + `VaultArt`) | cosmetic and per-player (your strata follow YOUR vault); they cost the server nothing and replicate nothing |
| drops: schedule, telegraph, hit test, knock | **client** | they harm only the local player, whose character physics the client already owns. The server trusts nothing from it: every rule in the run loop reads the server's own `Trace` position, and an exploiter who deletes drops gains nothing |
| rest | **client** | it only sits you down in the hub |
| the vault, the countdown, the collapse, the seal, gems, pads, pets, saves | **server, unchanged** | authoritative, as before |

**Leak review:**

* **What the client reads:** its own character and camera, its own run's `"start"` / `"tick"` / `"end"`
  events and state pushes, the parts of its OWN vault folder (`Vault_<its UserId>`), and `Config`.
* **It rebuilds the vault's layout locally** from the public seed (`VaultFloor.build`), the same modules
  and numbers the server uses. The layout is deterministic per tier and floor by design, and its walls
  are already on the client's screen, so this adds nothing a player did not have.
* **Decoration never reads the maze, the route or the gems.** Prop sites depend on storey, cell and
  seed only; two different mazes of one size hang identical props (`VaultEnv.spec`), so no lamp marks a
  dead end.
* **What it never does:**
  * fire or add a remote, or write an attribute (`check_vaultrunners_static`);
  * touch another player's vault (`check_vaultrunners_env` §10 clones a neighbour's real vault next to
    it and checks it is never repainted);
  * write anything on a server part except `Color` and `Reflectance`. It never writes Material, Size,
    CFrame, CanCollide, CanQuery, Transparency or attributes, so physics and the obby are exactly what
    the server built (`check_vaultrunners_env` §4 snapshots every server part before the client sees
    it; `check_vaultrunners_static` scans the source).
* **Every part it makes is local, anchored, non-collidable, non-queryable and non-touchable.**
* **Spawn order** (`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's
  CFrame at spawn, and `Main.server.luau` is unchanged.

**What other players see:** almost nothing of it. Each run is in the player's own vault, 400 studs
from the next slot, so a knock-down in a vault is seen by nobody else. The hub has no drops.

---

## 6. Budgets (measured)

Client-built only. The server's own vault is unchanged, and so are its own effects: glow on the kill
plane, the seal, the exit and one torch per storey, plus one `Fx.dustVolume` at 10/s. The client's
budget sits on top of that. Mobile is the target.

**Per stratum.** Measured after 5 s standing in each vault through the real client
(`check_vaultrunners_env` §9, 4 535 frames, drops off):

| where | parts | emitters (particles/s) | beams | lights |
|---|---|---|---|---|
| hub | 17 (vault door 14, portal-sign anchors 3) | 0 | 0 | 0 |
| bank (Bronze 1) | 62 | 3 (13.8) | 0 | 0 |
| bank › tomb blend (Bronze 4) | 65 | **4** (16.4) | 0 | 0 |
| tomb (Bronze 5) | 50 | 3 (17.3) | 0 | 0 |
| reactor (Bronze 14) | **106** | 3 (14.1) | 0 | 0 |
| frozen (Silver 1) | 77 | 3 (20.1) | 3 | 0 |
| volcano (Gold 1) | 98 | 3 (17.4) | 0 | 0 |

(Pass 2 added the critters: the counts above include the ones a runner standing in the entry cell meets,
3-9 parts; they were 56 / 56 / 47 / 100 / 68 / 89 before. The peak over every measured frame is now 112,
in the reactor; with drops in the air 108.)

The highest particle rate with drops off was 35.5/s, standing on storey 0 of the bank while the
collapse closed in (weather + thick ceiling dust + sparks).

**With drops in the air** (`check_vaultrunners_hazards` §6, new in the resume session): about 36 000
frames per run, 3 450-3 650 of them with a drop in flight. Five runs on the final build all peaked at
99 parts, 4 emitters, 1 light and 3 beams, and at 63.5-65.5 particles/s.

| metric | measured peak | budget (`Config.Budget`) |
|---|---|---|
| local parts | **112** (reactor, Bronze 14, with its drones; 100 before the critters) | 180 |
| enabled particle emitters | 4 | 6 |
| particles per second | **65.5** (a drop's trickle + weather + collapse dust and sparks) | 90 |
| weather emitters | 2 (a blend floor) | 2 (enforced in code by `EnvBands.capRates`) |
| point lights | 1 (the drop's blink) | 3 |
| beams | 3 (aurora) | 6 |
| drops at once | 1 | 1 (structural: `Hazards` has one `state.active` slot; no code reads `MaxHazards`, and `EnvConfig.spec` pins it to 1) |
| critters at once | 4 | 4 (`MaxCritters`, a cap in `VaultArt.updateCritters`; forced to 1 in memory, `check_vaultrunners_env` §4b shows one) |

**How it stays cheap:**

* Everything is **pooled**: props per kind, sky pieces per id, one weather host with at most one
  emitter per kind, two collapse hosts, one model per drop kind plus one shared ring / crack /
  trickle / light, at most 8 debris chunks, and 3-part crack items.
* What is not in use is **unparented** (no draw calls): props of storeys you are not on or next to,
  sky pieces at zero weight, the weather host with nothing falling, everything at a run's end.
* Nothing stacks: the same vault entered three times parents the same part count, and back in the hub
  nothing of any vault is left (`check_vaultrunners_env` §9).
* Lighting is written at most 10 times a second, only on change.
* Pad colours are written only when the look changes (20 crack steps, 10 flash steps).

These are part and emitter counts, not frame time; phone frame time is on the Studio list.

**Since §13 every budget is a CAP in code, not only a number these checks compare against.** Before,
the running game enforced only the weather's (`EnvBands.capRates`); a retune that hung props in every
cell put 235 parts on a phone against 180 and nothing stopped it. Now (`VaultArt`):

* every part the client parents is counted, the hub's sign anchors included;
* props are hung, the runner's own storey first, only while they fit under `MaxLocalParts` less a
  31-part headroom for a drop in the air, a whole shaft of cracking pads and a full set of debris;
* `enforceBudget`, the last thing in every client frame, takes props and then debris down if
  anything still passes the cap, grants the emitters by priority within `MaxEmitters` and
  `MaxEmitterRate` (the drop's trickle first, then the collapse's sparks and dust, then the weather;
  `VaultEnv.grantRates`), and caps lights and beams.

`check_vaultrunners_budget` forces the demand and the budgets in memory. With props in every cell the
peak is 173 parts against 180, and the props on the runner's storey do not change while a drop hangs
over it (132 before, 132 during). With the budgets forced to 2 emitters, 20 particles/s, 0 lights and
1 beam, every frame stays inside them and the drop's trickle is on for every frame a chunk hangs. With
the shipped numbers nothing is capped: every prop is hung and all three aurora ribbons are drawn.
The reviewer's side note reproduced: over 360 floors the most prop parts on one storey pair is 75
(Bronze 31, storey 0); the table above samples six floors.

---

## 7. Gates

**The current counts are in §15** (pass 2, 2026-10-01: specs 1 963 / 0, headless 955 / 0 + PASS, store
text 10 / 0; every gate green). §14 has pass 1's, §13.4 REVIEW-5's.
The table below is the history up to the first review round.

Every gate for this game, before the eye candy (HEAD, run from a `git archive` copy), at the start of
the resume session (the earlier attempt's tree), and at the end:

| gate | HEAD | resume start | resume end | review round (final) |
|---|---|---|---|---|
| `tests/Ascent.spec` | 68 / 0 | 68 / 0 | 68 / 0 | 68 / 0 |
| `tests/Collapse.spec` | 281 / 0 | 281 / 0 | 281 / 0 | 281 / 0 |
| `tests/Curve.spec` | 23 / 0 | 23 / 0 | 23 / 0 | 23 / 0 |
| `tests/Pets.spec` | 75 / 0 | 75 / 0 | 75 / 0 | 75 / 0 |
| `tests/Progression.spec` | 66 / 0 | 66 / 0 | 66 / 0 | 66 / 0 |
| `tests/Rng.spec` | 37 / 0 | 37 / 0 | 37 / 0 | 37 / 0 |
| `tests/RunState.spec` | 75 / 0 | 75 / 0 | 75 / 0 | 75 / 0 |
| `tests/Trace.spec` | 28 / 0 | 28 / 0 | 28 / 0 | 28 / 0 |
| `tests/VaultFloor.spec` | 215 / 0 | 215 / 0 | 215 / 0 | 215 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/EnvBands.spec` | — | 124 / 0 | 124 / 0 | 124 / 0 |
| `tests/Rest.spec` | — | 55 / 0 | 55 / 0 | 55 / 0 |
| `tests/Hazards.spec` | — | 91 / 0 | 91 / 0 | 91 / 0 |
| `tests/VaultEnv.spec` | — | 70 / 0 | 70 / 0 | **112 / 0** |
| `tests/EnvConfig.spec` | — | 319 / 0 | **323 / 0** | **366 / 0** |
| `tests/Pacing.spec` | — | 36 / 0 | **47 / 0** | 47 / 0 |
| **spec total** | **938 / 0** | **1 633 / 0** | **1 648 / 0** | **1 733 / 0** |
| `check_vaultrunners.luau` (headless boot) | 138 / 0 | 138 / 0 | 138 / 0 | 138 / 0 |
| `check_vaulthud.luau` (11 viewports × hub / mid-run, overlap on) | PASS | PASS | PASS (both clients) | PASS (both clients) |
| `robloxemu/check_vaultrunners_env` | — | 255 / 0 | 255 / 0 | 255 / 0 (§6 strengthened) |
| `robloxemu/check_vaultrunners_hazards` | — | 38 / 0 | **50 / 0** | 50 / 0 |
| `robloxemu/check_vaultrunners_shaft` | — | — | **25 / 0** (new) | **53 / 0** (§5 new) |
| `robloxemu/check_vaultrunners_cards` | — | — | **20 / 0** (new) | 20 / 0 |
| `robloxemu/check_vaultrunners_static` | — | 86 / 0 | 86 / 0 | 86 / 0 |
| `robloxemu/check_vaultrunners_readable` | — | — | — | **47 / 0** (new) |
| **headless total** | **138 / 0 + PASS** | **517 / 0 + PASS** | **574 / 0 + PASS** | **649 / 0 + PASS** |
| `mutate_obby.sh` (the obby's gate, run on a scratch copy) | 13 mutations: 12 killed, 1 disclosed survivor (REVIEW-4 §8), 2 controls survived | same | same | same (re-run, tree intact) |
| `walk_vaultrunners.luau` (instrument, no assertions) | README table | — | identical to the README table | byte-identical to the pre-fix output |

CLAUDE.md said `check_vaultrunners.luau` was 115: that was stale before this work, since HEAD itself
reads 138.

**Stability.** The emulator's `Random` is unseeded, so drop kinds and timing vary from run to run.

* `check_vaultrunners_hazards` was run 5 times on the final build (bundle md5 `c5ceb082…`) and was
  50 / 0 every time. Its counts vary: 12-13 drops in §5, 37-39 drops and 21-25 knock-downs in all,
  36 100-36 800 frames.
* `check_vaultrunners_shaft` was run 3 times, 25 / 0 each time with identical numbers.
* Everything else is deterministic.

**Compile and analyze.** `luau-compile` and `luau-analyze` are not on this machine (the scratchpad has
only `luau.exe`). Compilation is checked by `check_vaultrunners_static`, which runs `loadstring` on
every bundled source (21 files: 18 shared modules, the server script, the two client scripts), and
by every headless check actually loading the scripts. This is weaker than `luau-analyze`; running it
is on the list (§10).

**Mutation sweep** (`scratchpad/vr_resume/sweep/`). Run on a fresh scratch copy of the game and the
emulator; the real tree was never mutated. For each mutation:

* exactly one occurrence replaced;
* the bundle rebuilt and **proved to contain the mutation** (the mutated bundle equals the baseline
  bundle with the same single replacement);
* all 22 suites run (23 in round 2, with `check_vaultrunners_cards`);
* the original bytes restored, with the md5 checked.

**Round 1: 73 mutations on the tree as it stood before the last two test additions.**

* **61 KILLED.** Every source mutation was proved to reach the bundle, except A1 (client parts made
  collidable). A1's replaced text also occurs earlier in the bundle, in another module, so the
  single-replacement comparison picked the other occurrence. The mutation was applied, and
  `check_vaultrunners_env` §10 killed it.
* **All 6 CONTROLS survived, as they must.** The controls were:
  * the vault door's bolts a shade warmer;
  * the reactor ring turning a little slower;
  * the tomb card's subtitle reworded;
  * a landing shake 0.02 s longer;
  * the parts budget one part roomier;
  * the reader's unused near-miss radius.
* **6 non-control survivors:**

| id | mutation | why it survived | done | round 2 |
|---|---|---|---|---|
| V10 | the fanfare plays for every new card | the env check only plays a fresh profile, for which every new card is also a new depth | new `check_vaultrunners_cards` §1: a saved profile that has cleared the Frozen Vault gets a quiet Frozen card and a fanfare only for the Volcano | **KILLED** (cards) |
| V15 | the weather cap removed in the glue | the shipped bands never ask for more than it (two bands blend at most, and 14 + 12 < 30) | `check_vaultrunners_cards` §2 forces 200/s in memory | **KILLED** (cards) |
| C1 | `MinPadContrast` 3 → 1 | the shipped palettes never need the black/white fallback (the worst chosen pad is 5.68:1) | `check_vaultrunners_cards` §3 forces a snow-on-snow pad in memory and measures the parts actually painted | **KILLED** (cards) |
| P2 | the reader pauses 0.6 s instead of 3 | the Pacing "reader IS hit" assertion was `> 0`, and 0.6 s players are hit once or twice | it now asks for a sample of ≥ 20 hits | **KILLED** (Pacing) |
| V2 | the Rest button's `inRun` guard removed | belt and braces: the rule's own `threat = inRun` still refuses | disclosed; V2 and V3 together are KILLED by `check_vaultrunners_env` §3 | survives, as designed |
| V3 | the rule's `threat = inRun` removed | the button's guard still refuses | as above | survives, as designed |

**Round 2** (`sweep_r2.log`) was run on the final tree with the new check in it (23 suites). It
covered the six survivors, all six controls, and three earlier kills re-run as a sanity sample
(H1, V18, A9). C1, V10, V15 and P2 are now KILLED. V2 and V3 alone still survive, as designed. All six
controls survived, and H1, V18 and A9 were still KILLED.

After both rounds the scratch sources were byte-identical to the originals, the bundle identical to
its baseline, and every suite green. The earlier attempt's harness and mutation list
(`scratchpad/vr_eye_q7/`) were reused and extended: its list had 52 mutations (3 of them controls),
and the resume session added 21 aimed at its own changes and at promises nothing had mutated. A first run of round 1
crashed on printing an emoji to a cp1252 console after 17 mutations (`sweep_first_aborted.log`); it was
re-run in full with UTF-8 output.

Mutations killed only by the new suites (round 1):

| suite | killed |
|---|---|
| `check_vaultrunners_shaft` | V16 (no thinning in the shaft), V17 (rumble on the pads), V18 (landing shake on the pads), C9 (`DangerStuds` 18 → 4) |
| `check_vaultrunners_hazards` §6 | A4 (props never pooled: 1 832 parts at the peak; the env check's re-entry count did not see it), A6 (a 400/s trickle), A7 (the warning light never blinks), C10 (the particle budget below what a drop measures) |
| `check_vaultrunners_hazards` §7 | V21, V22, A8, A9 (the chunk's hang and landing, the ring's floor) |
| `EnvConfig.spec` (knock-down vs the model's stun) | P1 |
| `Pacing.spec` (the reader) | P3 (a hit costing 30 s: −6 and −8 points) |

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Each stratum's look.** Ambient tints, bloom and the grade per band, with ClockTime 0. Does the
   vault read as a bank / tomb / reactor / ice vault / volcano temple, and is it bright enough to run
   a maze in? Also: the frozen walls' 0.15 reflectance, and the bank's 0.06.
2. **Atmosphere vs fog.** Fog values are blended, but Roblox ignores fog while an Atmosphere exists.
   Is a haze density of 0.28-0.40 too thick inside a 16-stud maze?
3. **Weather inside a maze.** The emitter host is a 50 × 50 plate 10 studs above the camera, which puts
   it above the storey's ceiling. Particles do not collide, so they fall through the ceiling slab. Does
   that read as dust, sand or snow coming from the ceiling, or as particles clipping through geometry?
   Also: embers rising from a downward emission.
4. **Sky pieces 110 studs above the top storey's walls**, visible only from the top storey (there is no
   roof):
   * do the dome, winged sun, reactor ring, aurora and crater read;
   * are they culled at distance on low graphics settings;
   * the aurora Beams (`CurveSize`, `FaceCamera = false`) almost certainly need hand tuning.
5. **Ceiling props** at 12.8+ studs in 12-stud corridors with the default third-person camera: do they
   show, do they read as the stratum, and is 30-35 % of cells the right density?
6. **Pad readability under real light.** Contrast is measured on sRGB colours; Ambient tint, bloom and
   haze change what the eye gets, especially navy pads on white ice, gilded gold on brown, marble on
   the bank's dark green, and jade on basalt (the last three new in §13). Also: do the three crack lines on a 3 × 3 pad read, and does the crumble tint read as
   "going"? And with real ping: the crack is held until the server's drop arrives; watch that a pad
   you stepped off and the server never counted lets its crack go within 1.5 s rather than looking
   doomed for ever.
   * **Gems and the exit pad under real light** (review round). They are Neon, so they glow brighter
     than their albedo, which the contrast numbers ignore. Do the stratum gems (pearl in the tomb,
     amethyst on the ice, isotope green in the reactor) read as TREASURE in each place? Does a dark
     amethyst Neon ball glow or look dull? The server's sparkles and the exit's glow keep the tier's
     colour; do they clash with a recoloured gem? And is the tier identity missed (Silver's gems are
     amethyst, not pale blue, in the Frozen Vault)? §13 measures gem-to-pad distance in RGB (≥ 80);
     under real light, do gems and pads read as different things?
   * **A crumbling pad under a Bronze runner** (§14). The 80 bar is for the resting pad. Every
     stratum shares the crack colour (255, 90, 50), an orange red 95.7 from Bronze's orange gem, and a
     crumbling pad is pulled 70 % of the way to it. Measured over Bronze floors 1-400: in the Bank
     Vault the marble pad passes 44.6 RGB from the gem (at 81 % of the crumble); at a full crack it
     ends 60.9 away in the reactor and 70.5 in the Frozen Vault and the volcano; the tomb stays 176.6
     away. Silver stays 81.5 or more away and Gold 110.2. It is only ever the pad under the runner's own
     feet (gems are never in a stairwell), and only while it goes. Does it read as "going", or as
     treasure? If treasure, the fix is a crack colour chosen by eye: a dark one that keeps the bank's
     whole path 80 away, for example (200, 20, 60) at 80.9, reads 1.96:1 against the bank's dark green
     floor, under the 2:1 bar for a pad about to go, so the numbers alone cannot pick it.
7. **The drop's telegraph on a phone**:
   * the ceiling crack decal and the trickle;
   * the wobble;
   * the red light's 12-stud range;
   * a 6-7 stud ring in a 12-stud corridor, in its per-floor colours: yellow following and hot coral
     red locked on the dark floors, dark gold and crimson on the Frozen Vault's snow. Does coral still
     read as "locked, move now" after yellow? The icicle chunk itself (pale Ice on pale ice walls) is
     faint by the same measure; the crack, the trickle, the banner and the ring carry the warning, but
     look at it;
   * the banner text length at the top third of the screen;
   * whether "keep moving" is the obvious response.
8. **The knock on a real client.** Does PlatformStand plus a 10-14 studs/s shove plus a 4 studs/s hop
   tumble or slide the humanoid, and how far? `KnockClearStuds = 4` is the assumption the hole margin is
   asserted against, and the slide depends on the server floors' material. Does it get up cleanly after
   0.9 s?
9. **Avatar size.** `VaultEnv` assumes the root sits 3 studs over the floor (`Run.RunnerRootHeight`,
   which the server's own rules also assume). An avatar whose root is more than 1 stud off that reads
   as "not on the floor" and simply gets no drops (fail-safe). Since the resume session the ring and the
   landed chunk are drawn on the storey's real floor whatever the avatar.
10. **Rest's sit.** Does `Humanoid.Sit = true` from the client without a seat sit and replicate? Does
    walk input produce `MoveDirection` while seated (which wakes you)? Does jump unsit? How strong is
    the depth-of-field softening?
11. **Title card and fanfare** (flash + FOV punch) on a new stratum: celebratory or annoying? Also the
    chip at the bottom centre on a notched phone. The portal signs now sit 4 px under the server's
    portal labels at every distance (projected, not rendered): check the pair reads as one caption and
    that `AlwaysOnTop` does not put them over the avatar awkwardly at the spawn view.
12. **Frame time** on a mid or low phone in the densest scene: the reactor (100 client parts on top of
    the server's vault), a blend floor with two weather emitters, and a drop in flight (about 65
    particles/s).
13. **Stars** (200-3 000) with ClockTime 0 and an Atmosphere, from the top storey: do they show?
14. **The hub vault door** (50 studs, centre (0, 25, -36), just behind the hub pad's back edge): its
    proportion against the 14-stud portals, and whether it reads as a bank vault door.
15. **The collapse at danger 1**: rumble strength, dust thickness, and sparks off a plate the size of
    the vault's footprint.
16. **A drop crashing about 20 studs behind a runner who kept moving** (the camera faces forward): is it
    noticed at all? The landing shake is 0.16-0.27 at that distance, plus debris. The owner decided
    (§10) to leave it; this is where a playtest would say whether "keep moving" is still read.
17. **The Volcano Temple's halls** (§2, §13): do the Obsidian Hall's violet light and the Ash Hall's
    grey read as new places, or as a colour filter over the same room? The ash is a new weather kind
    (grey flakes, slow): does it read as ash or as dust? Braziers and brass lamps take the volcano's
    orange accent and glow: do they look like they belong? A hall card on every new hall: welcome or
    noise?
18. **The budgets as caps** (§6, §13): the shipped scene never reaches a cap, so nothing a player sees
    is trimmed today. If a later retune hits one, props go first (from the storey above), then debris;
    look at whether a trimmed ceiling reads as sparse or as broken.
19. **The DEEPEST ESCAPES board** (§15), a 16 x 11 stud sign at (-18, 5.5, 4), turned to face the
    spawn, gold trim behind it. From the spawn pad (18.4 studs away): are ten rows at 22 px on a 640 x
    440 px face readable, on a phone too? Does a stratum emoji (❄️, 🌋) render in a SurfaceGui? Does the
    sign block the walk to the Bronze portal or crowd the round vault door? With API access off it must
    say it is offline (`Config.Board.Text.Offline`); the rows, the names and the Friends toggle can only
    be seen on a published place. **Never film or screenshot the Friends view with a real account.**
20. **The board's prompt.** It sits low on the sign's face, 11.6 studs from the spawn pad's nearest
    edge and reaching 10, so it must NOT show while standing on the pad, and must show (E, or a tap on a
    phone) a step or two in front of the sign. Does one tap switch the view at once, and does the
    "Checking your friends: n of m" note move for a player with many friends?
21. **Streaming.** If the published place streams (StreamingEnabled), the hub can stream out while a
    runner is 200 studs up in a vault. `Board.client` remounts its drawing when the sign comes back
    (asserted headless, `check_vaultrunners_board` §11), and `Vault.client` was written streaming-safe;
    neither has been watched in a real streaming session.
22. **The critters** (§2.5). Three-part rats, scarabs, drones, frost bats and salamanders: do they read
    as animals and machines, or as clutter? A crawler walks an ellipse inside one cell: does it look
    alive or like it is on a rail? Do the bats and drones at 8.5-10 studs ever sit in the camera's way
    in a 12-stud corridor (they cannot collide and cannot catch a camera ray, but they can be in
    front of it)? And do they ever draw the eye from a gem or the next pad?

---

## 9. Thumbnail shot list (for the night Studio session)

**This recipe has not been tried in Studio. Verify step 1 before relying on the rest.**

1. **Build a place that has the strata.** In `vault-runners/`, run
   `rojo build -o VaultRunners-shots.rbxlx` and open that file. `*.rbxlx` is git-ignored. Keep Rojo
   disconnected while you edit the place.
2. **No saves.** Turn *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The
   server's `tryStore` then fails softly, `canSave` stays false, and every Play session starts from a
   fresh profile (Bronze floor 1, nothing banked).
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`. Nothing is published from
   Studio. Every session: `Tiers[2].unlockGems = 0` and `Tiers[3].unlockGems = 0`, so all three
   portals open on a fresh profile. Then use four Play sessions:
   * **A (hub, bank, frozen, volcano, the leap):** `Hazards.IntervalMin = 100000`,
     `Hazards.IntervalMax = 100001`, `Collapse.Slack = 20`. No drop interrupts a frame, and floor 1
     countdowns become 12-45 min instead of 79-270 s, so the collapse stays far below and the grade
     stays calm.
   * **B (tomb, reactor):** as A, plus `Env.TierDepth = { 5, 14, 55 }`. Bronze floor 1 is then depth
     6, pure Pyramid Tomb; Silver floor 1 is depth 15, pure Reactor Core.
   * **C (the drop):** `Collapse.Slack = 20`, `Hazards.IntervalMin = 8`, `Hazards.IntervalMax = 10`.
     The first drop comes 12 s into the run (the grace), then one every 8-10 s of run time while you
     stand in the open.
   * **D (the collapse):** shipped config apart from the unlocks.
4. **A vault opens at slot 0**, origin (0, 200, 0), for the only player in the place. Storey s's floor
   top is at y = 200 + 18 s, its ceiling 16 studs above that, and the top storey has no roof.
5. **Move the avatar** (command bar, Server context):
   `local c = game.Players:GetPlayers()[1].Character; c:PivotTo(CFrame.new(x, y, z))`.
   Allow about 4 s for the look to glide in. The server's `Trace` lets its trusted position catch up
   at walking pace after a teleport, which does not matter with `Slack = 20`.
6. **Clean frames** (command bar, Client context):
   `local g = game.Players.LocalPlayer.PlayerGui; g.VaultHud.Enabled = false; g.VaultFx.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   Freecam is Shift+P. It hides ScreenGuis while active, so use the normal camera for any shot that
   needs the HUD or the drop banner.

Positions are for `WorldSeed 20260909`, recomputed from `VaultFloor.build` in the resume session.

1. **"The vault door": the hub** (session A).
   * **Avatar:** on the spawn pad at (0, 3, 0), facing -Z.
   * **Camera:** about (0, 9, 24), looking at (0, 16, -30).
   * **In frame:**
     * the avatar from behind in the lower third;
     * the three glowing portals at x = -22 / 0 / 22, z = -22, each with its name label and this
       client's stratum sign: `Floor 1 · 🏦 Bank Vault` / `Floor 1 · ❄️ Frozen Vault` /
       `Floor 1 · 🌋 Volcano Temple` (with the unlocks at 0, the three signs name three strata);
     * the 50-stud brass-rimmed round vault door behind them, centre (0, 25, -36);
     * night sky and stars.
2. **"The leap": mid-air between crumbling pads, in the Volcano Temple** (session A, Gold floor 1;
   this is the brief's own thumbnail).
   * **The shaft:** storey 0's stairwell is the cell centred at (60, 200, 60). It opens to -X and -Z.
     Its pads' top surfaces are:

     | pad | top surface |
     |---|---|
     | 1 | (64, 203, 64) |
     | 2 | (56, 206, 64) |
     | 3 | (56, 209, 56) |
     | 4 | (64, 212, 56) |
     | 5 | (64, 215, 64) |
     | 6 | (56, 218, 64) |

   * **Getting there:** walk or teleport to (48, 204, 60), just west of it.
   * **Camera:** in the corridor at about (44, 210, 60), looking at (60, 211, 60).
   * **Action:** climb pads 1 → 3. Mid-hop from pad 3 to pad 4, anchor the root from the Server command
     bar: `c.HumanoidRootPart.Anchored = true`. Un-anchor it afterwards.
   * **In frame:** the avatar in the air between two pads; the pad behind showing dark crack
     lines and a red-orange crumble tint (it falls away 1.1 s after you land on it, with debris); jade
     pads against basalt (bone until §13); orange grade; embers drifting (thinned to 30 % in the shaft).
     Gold floor 1 is the Magma Hall, which is the Volcano Temple as it always was.
   * **Variant:** the same in the Bank Vault (Bronze floor 1, stairwell (36, 200, 36), pads
     (40, 203, 40) … (32, 218, 40)), for marble pads on a dark green floor (gold until §13).
   * **Variant, the halls** (§13): in session A also set `Env.TierDepth = { 0, 25, 47 }` for the
     Obsidian Hall on Gold floor 1 (depth 48: violet light, braziers, glints) or `{ 0, 25, 51 }` for
     the Ash Hall (depth 52: grey light, brass lamps, falling ash). Same shaft, same jade pads.
3. **"The tomb"** (session B, Bronze floor 1 = Pyramid Tomb).
   * **Avatar:** teleport to (-24, 240, -36) on the top storey (storey 2, floor y = 236). That is
     the corridor just east of the entry corner. Do NOT stand on the corner cell (-36, -36) itself:
     above storey 0 the entry cell is the hole you climbed out of, and you would drop a storey.
   * **Camera:** low behind the avatar, looking up at about 60° toward (0, 362, 0).
   * **In frame:**
     * sandstone walls with teal accents framing the sky (and, if the shaft is in frame, gilded gold
       pads since §13);
     * hanging braziers with flames (on storey 2, sites sit in 30 % of cells; one at the corner is
       luck, so frame along the +X corridor);
     * drifting sand;
     * the winged sun (an 80-stud disc, sandstone wings at ±75) floating 110 studs above the walls.
4. **"The reactor"** (session B, Silver floor 1 = Reactor Core).
   * **Avatar:** teleport to (36, 258, 48) on the top storey (storey 3, floor y = 254). That is the
     corridor just west of the entry corner (48, 48), which is the hole: do not stand on it.
   * **Camera:** behind the avatar, looking up toward (0, 380, 0).
   * **In frame:** cyan pads, gunmetal walls, neon light panels with beacons hanging, sparks, and the
     neon reactor ring (radius 60, ten bars) turning slowly round its glowing core overhead. Take a
     burst: the ring turns.
5. **"The Frozen Vault"** (session A, Silver floor 1 = Frozen Vault).
   * **Avatar:** the same spot, (36, 258, 48), beside the hole.
   * **Camera:** looking up toward the moon at about (90, 440, -40).
   * **In frame:** ice-blue shiny walls, snow-white floor, navy pads if the shaft is in frame, icicle
     clusters hanging, snow falling, and three aurora ribbons across the sky with the pale moon. Take
     several: Beams are the least predictable thing in this list. Variant at eye level: an amethyst gem
     glowing in an ice corridor (Silver's gems are amethyst here since §13; sapphire before).
6. **"Ceiling drop": the marble slab over a runner** (session C, Bronze floor 1 = Bank Vault).
   * **Avatar:** teleport to the open maze cell at (-12, 204, -12) on storey 0. A drop may start
     there, and a brass lamp hangs there.
   * **Wait:** about 12 s into the run, the crack opens overhead and the yellow ring follows you. Stand
     still. (For the snow variant, Silver floor 1 in session C: a dark gold ring, crimson when locked.)
   * **Camera:** the default third-person, zoomed out, pitched up so the ceiling is in frame.
   * **Shoot during the red lock** (the last 1.2 s): the slab hanging from the ceiling under its dark
     crack, the dust trickle, the red blinking light, the hot coral-red ring at your feet, and the banner
     `⚠️ MOVE! MARBLE SLAB ⬇` (HUD on).
   * **Then step out of the ring** (any direction), or you are knocked down. The next drop comes 8-10 s
     of run time later.
   * **Variant: "the collapse rising up the shaft"** (session D, Bronze floor 1):
     * teleport straight to storey 1 beside the hole, (24, 222, 36); the hole is the cell at
       (36, 218, 36) and opens to -X;
     * look down through the hole into storey 0's stairwell;
     * from about 26 s into the run, the red kill plane sweeps up through storey 0's shaft, with
       sparks shooting off it, ceiling dust pouring and the grade warming;
     * it reaches storey 1 at about 52 s and ends the run, so shoot between 35 and 50 s.
7. **"Deepest Escapes": the board** (§15). **HELD until the game is published:** in Studio with API
   access off the sign correctly says it is offline, and turning API access on would write to the live
   DataStore, which step 2 forbids.
   * **On the live server:** the avatar on the spawn pad, turned west.
   * **Camera:** about (-4, 7, 10), looking at the sign's centre, (-18, 5.5, 4).
   * **In frame:** the dark sign with its gold trim, the title, PUBLIC, rows of names with their depths
     and strata (a ❄️ row is the brag), the prompt's E, and the spawn pad's neon edge in the corner.
   * **Only the PUBLIC view**, or a test account with no friends: never a real account's friends.

---

## 10. Still open: owner decisions and loose ends

* **Owner decision: near-hits in a maze** (§3). Every drop comes for you once per 2.3-2.6 run-minutes,
  but a drop lands within 8 studs of a MOVING runner about once every 145 run-minutes. The ones that
  land close land on players who stopped. Options:
  * leave it (it rewards moving, which is the game);
  * shorten `commit` toward `MinCommitSeconds = 1.0` (lands about a sixth closer behind);
  * aim ahead of a runner, which would hit players who keep moving and break "keep moving".

  The adversarial review (§12) confirmed the numbers and added the cost of leaving it: the banner says
  "keep moving!" every ~2.5 run-minutes and the chunk then lands 20+ studs BEHIND a camera that faces
  forward, so the landing is rarely seen, and players may learn to ignore the banner.

  **DECIDED 2026-09-30 (owner: take recommended): leave it.** It is the option the list argued for
  (it rewards moving, which is the game), and it is the one that is fair and never punishing: a
  shorter lock gives a player who stopped less time to step out and moves the landing only a sixth
  closer, and aiming ahead would hit the players who do what the banner says. Measured after the
  other changes of §13: one drop per 2.60 run-minutes, reacting players hit by 0 of 170. No code
  changed. Whether the landing behind a forward camera is noticed stays on the Studio list (§8.16).
* **Owner decision: the endgame is one stratum.** Gold floor 1 is depth 56, so **every Gold floor is
  the Volcano Temple**, and Silver is too from floor 15. The whole slack curve the game is tuned
  around lives in Gold. +1 Jump's galaxy is also "the last band forever", but a Vault Runners player
  may live in Gold for hours. The options, if he wants more: a sixth stratum, deeper `TierDepth`
  spacing, or a per-floor variant inside the volcano.

  **DECIDED 2026-09-30 (owner: take recommended): a per-floor variant inside the volcano — the
  HALLS (§2).** No option was marked, so the one that serves "never monotonous" where the problem
  is: a sixth stratum or a deeper spacing only moves the last room further down, and the player who
  lives in Gold for hours still ends in one room. The halls turn every 4 depths for ever, change the
  light, the weather and the props, and never the palette, so nothing a runner reads changes (fair),
  and they change nothing a run is judged by (never exploitable). A normal player meets a new hall
  every 6.7-21.1 minutes.
* **Owner decision: the pacing target.** The brief's 30-45 min was +1 Jump's. Here: tomb about 5 min,
  reactor about 25, Frozen Vault about 61 (the brag), volcano 135-145, for a MODELLED normal player.

  **DECIDED 2026-09-30 (owner: take recommended): the brag inside 30-45 minutes**, which is what
  docs/complete-game-standard.md §2 now asks of every game. The Frozen Vault moved from depth 24
  (fade 4) to 18 (fade 2): a normal player first runs it at 40.8 / 37.9 minutes (fast 32.6, slow 54.2
  / 62.5); the tomb, the reactor and the volcano did not move (5, 25, 135 minutes). `Pacing.spec`
  asserts 30-45.
* **The review round's own fixes (§12) were re-read by the second review** (§13), which found the
  budget and gem/pad issues below; those fixes (§13) have not had a third reviewer. §14 re-measured
  them and re-ran their mutation sweep, by the same kind of writer pass, which is not a review.
* **`luau-analyze` has never been run** on the new files (not installed here). `check_vaultrunners_static`
  only proves they compile. That includes pass 2's `Board.client.luau` and the board, token and shutdown
  code in `Main.server.luau` (§15).
* **Pass 2 (§15) has had no reviewer.** It was written and mutation-tested by one writer pass, and
  that includes the critters (§2.5).
* **The model cannot price what reading the maze buys** (§11 item 4). A drop that hurries a reading
  player makes them faster in the model; whether real hurrying costs wrong turns is a playtest
  question.
* The Studio list (§8).

---

## 11. Resume session: what was found and fixed

The earlier attempt's tree was taken as unverified. Every new and changed file was read. The bundle
was rebuilt, and it was byte-identical to the one on disk, so the checks had been measuring the current
code. Every gate was green. Then:

1. **A drop's landing shook the camera of a runner on the pads.** The collapse rumble was already
   suppressed in the shaft, but the landing shake was not. A drop that started beside the stairwell
   and landed while the runner climbed jolted the camera mid-hop, which goes against the brief's
   "crumbling pads must stay readable".
   * New `check_vaultrunners_shaft` §3, written first: it failed on the unfixed build with
     `got 1, want 0`, while its control (the same landing seen from the open floor) saw the shake.
   * Fix: `Vault.client` shakes only `if not inShaft`.
2. **The chunk came to rest at chest height, and hung through the ceiling.** The rule's point falls to
   the runner's ROOT (3 studs up), and the art drew the model at that point.
   * The measured effect: a landed chunk hovered 1.4-2.4 studs above the floor for its 1.6-1.8 s
     `pass`. A hanging lava bomb was sunk 1.1 studs into the ceiling, and a hanging icicle poked 1.7
     studs up through the floor of the storey above.
   * New `check_vaultrunners_hazards` §7, written first: 5 failures on the unfixed build, 2 through the
     glue and 3 over every kind in `VaultArt` directly.
   * Fix: `VaultArt` measures each model's reach above and below its origin at build time. The glue
     passes the fall fraction, and the model now hangs with its top at the ceiling's underside and lies
     with its bottom on the floor, for every kind.
3. **The ring and the landed chunk were drawn at "root minus 3", not on the floor.** The check's own
   walk leaves the root 0.33 studs low, and the rewritten §1 assertion failed there (`-0.33 studs`).
   Any avatar whose root is not exactly 3 studs up would float or sink them.
   * Fix: both are placed on the storey's real floor (`floorY` from the zone's storey).
4. **"A hit costs little" was measured on a player who is never hit.** `Pacing.spec` asserted that
   ignoring every warning costs at most 3 points. But the normal model is never hit even when it
   ignores warnings (0 of 169), so that number was zero by construction.
   * Added the `reader` profile (3 s at every new junction) and a section that measures the cost on it.
     It asserts that the reader IS hit, often enough for the cost to be a measurement (≥ 20 hits; 47 of
     238), and by fewer than half the drops (the template's bound).
   * The first draft of that section asserted that drops change a reacting reader's completion by
     ≤ 2 points **in either direction**, and it FAILED the other way: Gold 1 was 33.3 with drops
     against 30.0 without. The model's reacting reader cuts its reading pause short, and in the model a
     pause buys nothing. The requirement is one-sided (drops must not make a run harder), so the
     assertion is now one-sided, and the reason is written next to it. This is a finding about the
     model, not a defect in the game.
   * `EnvConfig.spec` now also pins that no pacing profile charges a hit less than the game's
     knock-down (`StunSeconds >= KnockSeconds`).
5. **Three promises no test held**, all now in `check_vaultrunners_shaft`, and each watched failing on a
   mutant in §7:
   * weather and dust thin in the shaft (§1);
   * no rumble in the shaft (§2);
   * nothing drawn over the pads (§4).
6. **Budgets were only measured with drops OFF.** `check_vaultrunners_env` pushes the first drop past
   the end of its run, so a drop's parts, trickle emitter and light were never counted.
   `check_vaultrunners_hazards` §6 now measures every frame: the peak particle rate with drops in the
   air is 63.5-65.5/s against 35.5/s without. That is inside the 90 budget, and now asserted.
7. **Cleanup:** dead code (`VaultArt.bursts`, never written) and an unused constant were removed.
   Measurement prints were added to the env check (glide and hub numbers); no assertion changed there.
8. **The earlier attempt's mutation sweep** had been cut off before printing a result. It was re-run
   here, extended to the resume session's changes, on the final tree (§7). It left four real gaps,
   all closed and then re-swept:
   * the fanfare rule was only ever tested on a fresh profile, so "fanfare on every card" passed;
   * the weather cap was never reached by the shipped numbers;
   * the unreadable-pad fallback was never reached by the shipped numbers;
   * the Pacing sample-size assertion was `> 0` hits, which a normal-speed player also passes.

   The first three are now held by the new `check_vaultrunners_cards`, and the fourth by a ≥ 20-hit
   sample.

Files written by the resume session:

* in `vault-runners/`: `src/client/Vault.client.luau`, `src/shared/VaultArt.luau`,
  `src/shared/Config.luau`, `tests/Pacing.spec.luau`, `tests/EnvConfig.spec.luau`, this file,
  `README.md`, `CLAUDE.md`;
* in `robloxemu/`: `check_vaultrunners_shaft.luau` and `check_vaultrunners_cards.luau` (new),
  `check_vaultrunners_hazards.luau`, `check_vaultrunners_env.luau`, and `build/vault-runners.luau`
  (rebuilt; md5 `c5ceb0822d09c0a8896510eeeb06fef4`).

Nothing else was written. `robloxemu/emu`, `tools`, `docs`, every `marketing` folder and the other
games were untouched. Nothing was committed, pushed or published, and Studio was not opened.
(All of it was committed later, as 511793d on 2026-09-24.)

---

## 12. Review round (2026-09-24): the adversarial review's findings, closed

An independent reviewer re-ran every gate from a clean bundle (all green, the same counts as §7's
resume end), read the new code, and reported five findings. Each was **reproduced first**, then fixed
test first: the failing test was written and watched failing on the unfixed build, and only then was
the game changed (never the test). `Main.server.luau`, `VaultPath`, `RunState`, `Ascent`, `VaultFloor`,
`Trace` and `Progression` are untouched, so the countdown, the collapse, the gems' value, the pads'
timing and the saves are exactly what they were.

### 12.1 MEDIUM: the crumbling pad looked whole (or flashed "it's back") right before it dropped: FIXED

* **Reproduced** with the reviewer's own probe on the unfixed bundle (Bronze 1 and Gold 1, hopping on
  at 12 and 50 studs/s):
  * the pad read WHOLE for 0.067-0.25 s before the server removed it (the emulator has no network, so
    live play adds a round trip);
  * on a pad landed on again right after it came back, the crack ended in the white "it's back" flash
    0.25-0.33 s before it fell.
* **Cause.** The crack ran on the client's own clock from its own landing and ended at
  CrumbleSeconds. The server's timer starts later: when its trusted position reaches the pad, on its
  0.2 s tick, and the drop then has to replicate back. The flash timer was only decremented while no
  crack ran, so a crack that started during a flash resumed that flash when it ended. The client could
  also start a crack cycle on a pad the server had not yet brought back.
* **Test first:** `check_vaultrunners_shaft` §5. Every frame from the first crack to the server's drop
  must read "cracking" (crack lines up, pad tinted, never whole, never the flash). A pad landed on while
  it still flashes must crack and never flash. A returned pad seen from the floor below must flash
  (the control half). On the unfixed build: 6-11 non-cracking frames per landing and 9-13 flash
  frames; 12 failures, with the control passing.
* **Fix:** `VaultEnv.padLook`, a pure rule used by `Vault.client`. `VaultEnv.spec` gained 42
  assertions this round, across `padLook`, the gem rule and the ring rule:
  * the crack starts when the runner first stands on the pad (by geometry) since the server last put it
    back, and is HELD at full until the server drops it;
  * it is held indefinitely while the runner stands on it (the server will count that stand), and for
    `CrackHoldSeconds` = 1.5 s past the crumble once they have left, then let go (a pad only brushed on
    the way past may never be counted and never drop);
  * a pad that comes back is fresh and flashes for `PadFlashSeconds` = 0.45 s, unless a runner is on
    it: then it cracks, and the crack cancels the flash for good.

  `EnvConfig.spec` pins the hold at ≥ 5 server ticks and ≤ RespawnSeconds.
* **After:** the reviewer's probe shows CRACKING straight into GONE on all four runs, and §5 reads 0
  non-cracking frames in 65-67 frames per landing.
* **A test in `check_vaultrunners_env` §6 was strengthened.** Its "flashes as it returns" assertion
  compared the RED channel. A fully cracked bank pad is 9/255 redder than a whole one, so it passed on
  the crack tint, not a flash. It also left the runner hovering where the pad had gone, a state no
  player can reach. It now drops the runner to the floor when the pad goes and detects the flash by the
  G/B channels, which the crack lowers and the flash raises. It is still 255 / 0 and now kills a
  "never flash" mutant (K6).

### 12.2 MEDIUM: gems and the exit pad vanished into the Frozen Vault and the tomb: FIXED

* **Reproduced** with the reviewer's `probe_gems` and then through the real client
  (`check_vaultrunners_readable` §1, on the unfixed build):
  * Silver's gems on Silver floor 1 (Frozen Vault): 1.19:1 against the floor as painted, 1.10:1
    against the wall;
  * Bronze's on Bronze floor 8 (tomb): 1.16:1 against the wall.
* **Fix:** the gems and the exit pad (which has always worn the gem colour) are repainted by the
  client, Color only, like the walls:
  * each tier keeps its own gem colour where that reads ≥ `MinGemContrast` (3) against the floor and
    ≥ `MinGemWallContrast` (1.8) against the walls;
  * where it would vanish, they wear the stratum's own `palette.gem`, the better-reading of the two
    blending bands' (`VaultEnv.gem`): gold coin, pearl, isotope green, sapphire, molten gold;
  * the wall bar is 1.8 because no bright gem reaches 2 on the tomb's sandstone (pearl: 2.02).
* **After:**

  | case | before (floor / wall) | after (floor / wall) |
  |---|---|---|
  | Silver, Frozen Vault | 1.19 / 1.10 | sapphire, 5.79 / 4.45 |
  | Bronze, tomb | 4.16 / 1.16 | pearl, 7.22 / 2.02 |
  | Gold, volcano | 13.33 / 10.42 | unchanged: the tier's own colour kept |

  Over every tier and depths 0-100 in 1/8 steps, the worst is 4.16:1 against the floor and 1.81:1
  against the wall. The black-or-white fallback is never needed. Gems keep the tier colour at 615-625
  of 801 depths.
* **Not changed:** the server's sparkles on each gem and the exit pad's glow keep the tier colour (the
  client writes Color on server parts, never on their emitters or lights). That is on the Studio list
  (§8.6).

### 12.3 LOW: the drop's ring was nearly invisible on the Frozen Vault's snow: FIXED

* **Reproduced** with `probe_ring`:
  * the yellow following ring on snow: 1.16:1;
  * the red locked ring: 1.58-2.72:1 on every floor.

  Through the real client on the unfixed build (`check_vaultrunners_readable` §2), the worst was
  1.58:1 in the tomb, 1.16:1 on the ice and 2.72:1 in the volcano.
* **Fix:** the ring is drawn in the first colour that reads ≥ `MinRingContrast` (3) against the floor
  under it, seen through its own transparency (`VaultEnv.ring` and `readableRing`,
  `Config.Env.RingFollow` and `RingLock`):
  * following: yellow on the dark floors, dark gold on snow;
  * locked: hot coral red on the dark floors, crimson on snow.

  A pure red lock cannot reach 3:1 on the bank's or the tomb's floor at any opacity; the search is in
  §12.6. `EnvConfig.spec` also holds the lock at ≥ 60 apart in RGB from the follow on every floor.
* **After:**

  | floor | following | locked | follow vs lock (RGB) |
  |---|---|---|---|
  | bank | 3.46 | 3.57 | 88 apart |
  | tomb | 3.20 | 3.21 | 87 apart |
  | reactor | 5.07 | 5.81 | 93 apart |
  | frozen | 3.49 | 4.71 | 79 apart |
  | volcano | 5.70 | 6.82 | 98 apart |

  Through the real client: 3.20:1 (tomb), 3.49:1 (ice), 5.70:1 (volcano), identical on 5 repeated
  runs.
* **Not changed:** the icicle chunk's own pale colour. The crack, trickle, blinking light, banner and
  ring carry the warning; the chunk is on the Studio list (§8.7).

### 12.4 LOW: near-hits for moving players: CONFIRMED, left to the owner

The reviewer's numbers match `Pacing.spec`:
* one drop per 2.60 run-minutes;
* median landing 23.4 studs from the runner;
* within 8 studs about once per 146 run-minutes.

This was already an owner decision (§10), and the review's extra point is now written there: the
landing happens behind a forward-facing camera, so the banner may come to be ignored. No code changed.

### 12.5 LOW: the hub's stratum signs overlapped the portal labels on phones: FIXED

* **Reproduced** by projecting the two billboards' own sizes and offsets. The server label is 60 px
  at portal + 9 studs; the client sign was 34 px at portal + 3 studs. Both are fixed-pixel and
  AlwaysOnTop.

  `check_vaultrunners_readable` §3, written first, covers:
  * camera positions over the whole hub (x -40..40, z -14..44, three heights);
  * viewport heights of 320, 375, 390, 720 and 1080 px;
  * 70° vertical FOV;
  * the sign's MaxDistance of 90.

  On the unfixed build, **6 979 of 14 175 views overlapped**, by up to 31.9 px.
* **Fix:** the sign is anchored at the server label's own world point (its `StudsOffset` and height
  are read from the server's BillboardGui) and laid out IN PIXELS: a taller transparent billboard whose
  bottom 34 px sit 4 px under the label's bottom edge.
* **After:** 0 of 14 175 views overlap, with a tightest gap of 4.0 px, which is the design gap at
  every distance. Hub parts are still 17.

### 12.6 How the colours were chosen (measured, not guessed)

* **Gems:** WCAG contrast of each stratum's floor and wall against 15 candidate gem colours.
  * On the tomb, no colour reaches 2:1 against the sandstone wall AND 3:1 against the brown floor
    except near-white (the chosen pearl: 7.2 / 2.0), and near-black (2.5 / 9.0) fails the floor.
  * On the ice, every dark saturated blue or violet reads 4.4-7.6 against the floor.
* **Rings:** 12 colours at 3 opacities against the five floors, then 18 more colour/opacity pairs. Then a grid of red-family colours
  (R 255, G 60-200, B 40-200, transparency 0.10-0.35) for the lock on the four dark floors. The most
  saturated that reaches 3:1 on all four is a coral near (255, 140-150, 130-150) at 0.10-0.15
  transparency. The scripts are in the scratchpad (`vr_fix/baseline/vault-runners/probe_feas*.luau`).

### 12.7 Mutation sweep

Run on a scratch copy of the game and the emulator (`scratchpad/vr_fix/sweep.py`); the real tree
was never mutated. For each mutation:
* exactly one occurrence replaced;
* the bundle rebuilt and **proved to carry it** (the mutated bundle equals the baseline bundle with
  the same single replacement);
* all 24 suites run (16 specs, `check_vaultrunners`, `check_vaulthud`, and the six emulator checks);
* the original bytes restored, with the md5 checked.

After the sweep every source was byte-identical to the real tree and the bundle back at its baseline
md5.

**24 mutations and 5 controls (29 runs): 22 KILLED, all 5 CONTROLS survived, and 2 survivors that are
equivalent mutants** (explained below the table).

| id | mutation | killed by |
|---|---|---|
| K1 | no hold: the crack ends at CrumbleSeconds (the reviewed defect) | shaft §5 (8), VaultEnv.spec (3) |
| K2 | the hold times out even while the runner stands on the pad | VaultEnv.spec (1) |
| K3 | a returned pad is not fresh: the old crack carries over | VaultEnv.spec (2) |
| K4 | a crack does not cancel the flash | VaultEnv.spec (1), the long-flash case |
| K5 | the glue never sees the runner on a pad | env §6 (2), shaft §5 (8) |
| K6 | the returned pad never flashes | env §6 (1, strengthened), shaft §5 (4) |
| K7 | `CrackHoldSeconds` 0.05, shorter than the server's lag | EnvConfig.spec (1) only |
| G1 | the gems not repainted | readable §1 (5) |
| G2 | the tier's colour always kept | readable (3), EnvConfig (6), VaultEnv.spec (5) |
| G3 | the gem wall bar lowered to 1.0 | EnvConfig (1) |
| G4 | the worse-reading stratum gem chosen | EnvConfig (3), VaultEnv.spec (3) |
| G5 | the blending-in band's gem never offered | EnvConfig (3), VaultEnv.spec (1) |
| G6 | the exit pad keeps the tier colour | readable §1 (5) |
| R1 | the glue passes no ring style | readable §2 (3) |
| R2 | the snow follow ring pale again | readable (1), EnvConfig (1) |
| R3 | the first ring candidate regardless of the floor | readable (1), EnvConfig (2), VaultEnv.spec (2) |
| R4 | the ring style's transparency ignored | readable §2 (2) |
| R5 | the old red lock | readable (2), EnvConfig (4) |
| S2 | the sign billboard no taller than the sign | readable §3 (1) |
| S3 | a negative gap | readable §3 (1) |
| S5 | the sign centred on the label's point | readable §3 (1) |
| S6 | the sign anchored 2.7 studs above the label's point | readable §3 (1) |
| S1 | the sign's text moved to the billboard's TOP | **survived: equivalent** |
| S4 | the sign anchored 4.5 studs lower | **survived: equivalent** |
| C1-C5 | CONTROLS: pearl a shade warmer, hold 0.1 s longer, sign 4 px wider, coral a shade lighter, isotope green a shade bluer | **all survived, as they must** |

**The two survivors are equivalent mutants.** The billboard is symmetric about the label's point, so
S1 puts the sign 4 px ABOVE the label instead of below. S4 moves it further down. Both still never
overlap, and "never overlaps" is the requirement, not "below". The non-equivalent versions of the same
two edits, S5 and S6, are killed.

**K7 is killed only by the config pin.** In the emulator, with no network, the runner is still on the
pad when the server drops it, and a crack is held indefinitely while the runner stands on the pad.
So only a live round trip after stepping off exercises the length of the hold. That is on the Studio
list (§8.6).

### 12.8 Gates at the end of the review round

All in §7's last column. In total:
* specs **1 733 / 0**;
* headless **649 / 0 + PASS**;
* `mutate_obby.sh`: 13 mutations, 12 killed, 1 disclosed survivor, 2 controls survived, tree intact;
* `walk_vaultrunners`: byte-identical to its pre-fix output.

Budgets, measured again, did not move: peak 100 parts, 4 emitters, 35.5 particles/s with drops off,
and 63.7 with drops in the air. The fixes change colours and one billboard's layout, not part counts.

Repeat runs, because the emulator's `Random` is unseeded:
* `check_vaultrunners_readable`: 5 runs, 47 / 0 each time with identical numbers;
* `check_vaultrunners_shaft`: 3 runs, 53 / 0 each time;
* `check_vaultrunners_hazards`: 3 runs, 50 / 0 each time.

Files written in the review round:
* in `vault-runners/`: `src/shared/VaultEnv.luau`, `src/shared/VaultArt.luau` (one optional parameter
  on `showHazard`), `src/shared/Config.luau` (Env additions only), `src/client/Vault.client.luau`,
  `tests/VaultEnv.spec.luau`, `tests/EnvConfig.spec.luau`, this file, `README.md` and `CLAUDE.md`;
* in `robloxemu/`: `check_vaultrunners_readable.luau` (new), `check_vaultrunners_shaft.luau` (§5),
  `check_vaultrunners_env.luau` (§6 strengthened) and `build/vault-runners.luau` (rebuilt; md5
  `451e55788de2f29da1a0eabad4424310`, verified to equal a fresh rebuild of the final sources).

Nothing else was written. Nothing was committed, pushed or published, and Studio was not opened.
(The review round was committed later with the rest of the eye candy, as 511793d on 2026-09-24.)

---

## 13. Second review round and the owner's decisions (2026-09-30, REVIEW-5)

The full account, with the obby review that shared the pass, is `REVIEW-5.md`. For this page:

### 13.1 The budgets are caps (second review, finding 1): FIXED

Reproduced by the new `check_vaultrunners_budget`: with props forced into every cell the client hung
235 parts against 180, and with the budgets forced below the scene 3 emitters, 57 particles/s, 1 light
and 3 beams went through. Now every budget is enforced in `VaultArt` (§6): after the fix, 173 parts at
most, the forced budgets held on every frame, the drop's trickle on for every frame a chunk hung, no
prop taken down while a drop hangs over its storey, and the shipped numbers cap nothing.

### 13.2 Gems and the exit are not the pads' colour (second review, finding 2): FIXED

Reproduced in `EnvConfig.spec` at every tier and depth: the tomb's pearl gems 41.5 apart (RGB) from
its cream pads, the Frozen Vault's sapphire 41.8 from its navy pads, and two the review did not name,
Bronze's orange 39.9 from the bank's gold pads and Gold's own gems 70.8 from the volcano's bone pads.
Now `Env.MinGemPadDistance = 80` is part of the gem rule, and four palette entries changed: bank pads
marble, tomb pads gilded gold, Frozen Vault gems amethyst, volcano pads jade. Worst after: 100.0
(Bronze), 100.0 (Silver), 90.9 (Gold); as painted through the real client 176.6 (tomb), 100.0 (Frozen
Vault), 188.6 (volcano). Every earlier readability bar still holds (§2.3).

### 13.3 The state text (second review, finding 3), and the owner's decisions: DONE

"Uncommitted" is gone from CLAUDE.md and from this file's header; the historical "nothing was
committed" lines of §11 and §12 now say they were committed later as 511793d. The three decisions are
recorded in §10 as DECIDED 2026-09-30 (owner: take recommended): the brag inside 30-45 minutes (the
Frozen Vault at depth 18), near-hits left as they are, and the halls of the Volcano Temple (§2).

### 13.4 Gates at the end of REVIEW-5

| gate | before (§12) | REVIEW-5 |
|---|---|---|
| `tests/Ascent.spec` | 68 / 0 | 77 / 0 |
| `tests/Collapse.spec` | 281 / 0 | 282 / 0 |
| `tests/Curve.spec` | 23 / 0 | 29 / 0 |
| `tests/EnvBands.spec` | 124 / 0 | 124 / 0 |
| `tests/EnvConfig.spec` | 366 / 0 | 401 / 0 |
| `tests/Hazards.spec` | 91 / 0 | 91 / 0 |
| `tests/Pacing.spec` | 47 / 0 | 51 / 0 |
| `tests/Pets.spec` | 75 / 0 | 75 / 0 |
| `tests/Progression.spec` | 66 / 0 | 66 / 0 |
| `tests/Rest.spec` | 55 / 0 | 55 / 0 |
| `tests/Rng.spec` | 37 / 0 | 37 / 0 |
| `tests/RunState.spec` | 75 / 0 | 75 / 0 |
| `tests/Trace.spec` | 28 / 0 | 28 / 0 |
| `tests/VaultEnv.spec` | 112 / 0 | 138 / 0 |
| `tests/VaultFloor.spec` | 215 / 0 | 231 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 |
| **spec total** | **1 733 / 0** | **1 830 / 0** |
| `check_vaultrunners.luau` | 138 / 0 | 138 / 0 |
| `check_vaulthud.luau` | PASS | PASS |
| `robloxemu/check_vaultrunners_env` | 255 / 0 | 255 / 0 |
| `robloxemu/check_vaultrunners_hazards` | 50 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_shaft` | 53 / 0 | 63 / 0 |
| `robloxemu/check_vaultrunners_cards` | 20 / 0 | 20 / 0 |
| `robloxemu/check_vaultrunners_static` | 86 / 0 | 91 / 0 |
| `robloxemu/check_vaultrunners_readable` | 47 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_budget` | — | 15 / 0 (new) |
| `robloxemu/check_vaultrunners_halls` | — | 68 / 0 (new) |
| **headless total** | **649 / 0 + PASS** | **750 / 0 + PASS** |

The mutation sweep is in REVIEW-5.md §4.

Files written in REVIEW-5, all in the working tree and none committed: in `vault-runners/`,
`src/shared/{Config,VaultPath,Ascent,VaultEnv,VaultArt}.luau`, `src/server/Main.server.luau`,
`src/client/Vault.client.luau`, `tests/{Ascent,Collapse,Curve,EnvConfig,Pacing,VaultEnv,VaultFloor}.spec.luau`,
`tests/VaultModel.luau`, `check_vaultrunners.luau`, `mutate_obby.sh`, `REVIEW-5.md`, this file,
`CLAUDE.md`, `README.md`; in `robloxemu/`, `check_vaultrunners_{env,shaft,static,readable}.luau`, the
new `check_vaultrunners_{budget,halls}.luau`, and `build/vault-runners.luau` (rebuilt). Studio was not
opened.

---

## 14. Pass-1 re-run (2026-10-01)

The full account is REVIEW-5.md §6. For this page:

* **All three second-review findings reproduced on HEAD 511793d and are fixed in the tree.** With
  the reviewer's own mutant (reactor props in every cell), HEAD hung 235 client parts on Bronze 14 and
  the tree hangs 160. Gem to pad on HEAD: tomb 41.5 RGB, Frozen Vault 41.8; in the tree the worst is
  90.9. The "uncommitted" text is gone. The tests that hold each fix fail on HEAD's source (budget
  13 / 2, readable 47 / 3).
* **The owner's three decisions** are recorded in §10 as "DECIDED 2026-09-30 (owner: take
  recommended)". Measured again: the Frozen Vault at 40.8 / 37.9 minutes for a normal player, 38 hall
  changes in two 8-hour careers, one drop per 2.60 run-minutes with reacting players hit by 0 of 170.
* **Changed:** `Config.Budget`'s comment (it said the budgets were only measured; they are caps, and
  `MaxHazards` is the scheduler's single slot, pinned by `EnvConfig.spec`), §6's table row for drops,
  and §8.6.
* **Found, not changed, and on the Studio list (§8.6):** the gem rule's 80 RGB is for the resting pad.
  A pad crumbling under a Bronze runner passes 44.6 from the orange gem in the Bank Vault. Every crack
  colour that keeps that path 80 away measured under the 2:1 floor bar.
* **Mutation sweep, again:** 40 mutations, 39 killed, 1 disclosed survivor (B1g); 6 of 6 controls
  survived; 46 of 46 bundles proved; scratch sources sha256-identical.

| gate | §13.4 | §14 |
|---|---|---|
| 16 specs | 1 830 / 0 | 1 830 / 0 |
| `tests/Board.spec` (board WIP, CLAUDE.md) | — | 69 / 0 |
| `check_vaultrunners.luau` | 138 / 0 | 138 / 0 |
| `check_vaulthud.luau` | PASS | PASS |
| `robloxemu/check_vaultrunners_{env,hazards,shaft,cards}` | 255, 50, 63, 20 / 0 | 255, 50, 63, 20 / 0 |
| `robloxemu/check_vaultrunners_static` | 91 / 0 | 93 / 0 (Board.luau is one more module) |
| `robloxemu/check_vaultrunners_{readable,budget,halls}` | 50, 15, 68 / 0 | 50, 15, 68 / 0 |
| `robloxemu/check_vaultrunners_board` (board WIP) | — | RED: 30 FAIL, then it stops at line 381 |

Nothing was committed, pushed or published, and Studio was not opened.

---

## 15. Pass 2 (2026-10-01): the rest of docs/complete-game-standard.md

Every item of the standard was checked against the tree, not only the reviewer's list. What was missing
was built test first (an assertion written, run, watched fail, then the code); what was there was left
alone. Nothing was committed, pushed or published, and Studio was not opened.

| standard | before pass 2 | now |
|---|---|---|
| §1 core loop from join, incl. rejoin | spawn, runs, bank, buy were walked; a rejoin was not | `check_vaultrunners` "REJOIN": wallet, banked total, every vault's floor and the pets come back on a new session |
| §1 spawn: `RespawnLocation` | never set (one enabled spawn only) | the hub spawn, set in `onPlayerAdded` before the load yields (CLAUDE.md invariant 16) |
| §1 nothing secret; a salted seed | `WorldSeed` in ReplicatedStorage, unsalted | unchanged ON PURPOSE: the maze is replicated geometry, and a retried floor is the same floor (invariant 17) |
| §1 DataStore owner token | `game.JobId` (per server); `flush` wrote when the record's jobId was nil or its lock had lapsed | a GUID per session; a lost record stops writing, warns once, tells the player (invariant 9d) |
| §1 DataStore at shutdown | no `BindToClose` | every profile written and its lock released (invariant 18) |
| §1 integer keys | `numKeys` existed, but no check reached it: removing it survived every gate (round 2 below) | a sparse, string-keyed `floors` is staged and loads as 7 / 1 / 2 |
| §2 bands: critters | none | five kinds (§2.5, invariant 19) |
| §2 brag in 30-45 min, budgets as caps, hazards, rest | done (§10, §13, §14) | unchanged |
| §2 HUD overlap rule 4b | `overlap = true` in `check_vaulthud` | unchanged |
| §3 board, public + friends | half-built, its check red, the tie bug | the DEEPEST ESCAPES sign (invariant 15) |
| §4 store text | 708 characters, stale, the README said "No leaderboard" | rewritten (897 characters) and gated: `check_store_text.py` |
| §4 clip list | none | `MARKETING.md`: 9 clips, 2 held until published |
| §4 needs-Studio list, thumbnails | §8: 18 items, §9: 6 shots | §8: 22 items, §9: 7 shots |

**The board**, built against the check the interrupted pass left red (30 FAIL, then a stop at its line
381), which pass 2 did not weaken: it added to it (names cached, a shallower escape never re-stamps the
reach time, the sign streaming back). The WIP's tie bug is fixed: `bestAt` is stamped in `finishRun`
when the server banks an escape deeper than any before, so a new player's first board write no longer
carries reach time 0. The sign is at (-18, 5.5, 4), not the WIP config's -16: at -16 the prompt was 9.6
studs from the spawn pad, inside its 10-stud reach, and showed on every spawn (measured by the check);
at -18 it is 11.6. Measured: one `GetSortedAsync` per minute (3 in 180 s); 450 friends cost 41 reads in
the first second, 100 in the first minute, exactly 200 in all, over 3 pages.

**Mutation sweeps** (scratchpad `vr7`, on frozen snapshots, never the real tree; every mutated bundle was
checked against the expected build; every scratch source sha256-identical afterwards):

* Round 1 (board, owner token, spawn, shutdown): **31 mutations, 31 killed; 3 of 3 controls survived.**
* Round 2 (rejoin, critters): 18 mutations: 13 killed, 4 survived, and 1 was written invalid (its
  "kill" was a compile error: `break` not last in its block); 3 of 3 controls survived. The survivors,
  and what was done: `numKeys` removed (no check reached it; the sparse-key check above was written for
  it); the critter cap removed from `VaultArt` alone (the glue asks for at most `MaxCritters` too); the
  critters' parts allowance removed alone (`enforceBudget` takes them down in the same frame); the
  run's end no longer clearing them (the frame loop already passes nil every frame without a run, so
  that line was REMOVED as redundant).
* Round 3: 4 mutations, 2 killed, 2 survived; 1 of 1 control survived. Killed: `numKeys` removed, by
  the new sparse-key check; BOTH critter caps removed, by `check_vaultrunners_env` (10 failures). Survived:
  "critters not taken down first" alone (the allowance keeps them out first), and the allowance AND the
  take-down both removed, which no check could see: critters then pushed props out. `check_vaultrunners_budget`
  §1 now asserts that wherever the props alone fill the budget no critter is up (7 storeys measured).
* Round 4: that pair, killed by the new assertion; 1 of 1 control survived.
* **Disclosed survivors, by design (each masked by its twin, both together killed):** the critter cap in
  `VaultArt` alone (the glue's), the critters' parts allowance alone (`enforceBudget`), and "critters
  not taken down first" alone (the allowance). The same shape as REVIEW-5's B1g.

| gate | §14 (pass 1) | §15 (pass 2) |
|---|---|---|
| 17 specs | 1 899 / 0 | **1 963 / 0** (EnvConfig 401 → 432, VaultEnv 138 → 171; the rest unchanged) |
| `check_vaultrunners.luau` | 138 / 0 | **157 / 0** (owner token, RespawnLocation, rejoin, sparse keys, shutdown) |
| `check_vaulthud.luau` | PASS | PASS |
| `robloxemu/check_vaultrunners_env` | 255 / 0 | **340 / 0** (§2 no critters in the hub; §4b each stratum's critters) |
| `robloxemu/check_vaultrunners_{hazards,shaft,cards}` | 50, 63, 20 / 0 | 50, 63, 20 / 0 |
| `robloxemu/check_vaultrunners_static` | 93 / 0 | **100 / 0** (Board.client compiles, fires and writes nothing) |
| `robloxemu/check_vaultrunners_{readable,budget,halls}` | 50, 15, 68 / 0 | 50, **17**, 68 / 0 (budget §1: critters yield first) |
| `robloxemu/check_vaultrunners_board` | RED: 30 FAIL, stop at line 381 | **90 / 0** |
| `check_store_text.py` (new) | — | 10 / 0 (and 5 of 5 bad store texts caught, a reworded control passes) |

Bundle `robloxemu/build/vault-runners.luau` sha256 5c761d72... at the final run.
