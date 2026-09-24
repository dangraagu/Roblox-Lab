# Deep Vein: the strata you dig through

Owner's brief (Gustav, 2026-09-17): richer, never monotonous, the world changes as you progress, in the logic
of the game; rare, telegraphed hazards (about one near-hit per 2-3 minutes, easy to see and avoid) that knock
you down; a way to rest that can never be exploited; the environments worth photographing, and a shot list
for the night Studio session.

In a mining sim the progress is DEPTH, so the world changes with the layer you stand in. There are eleven
strata: topsoil and roots, grey stone, iron veins, an underground river, a glowshroom grotto, magma, a
crystal geode, fossil beds, lost ruins, obsidian depths and the core. Each stratum changes the rock itself,
the light, the air, the particles, the critters and the finds on the walls. Its hazards fit it: rocks and
stalactites work loose overhead, steam and magma burst from the floor.

**State: built, unit-tested, headless-tested and mutation-tested (§8); adversarially reviewed once, and
all six findings closed test-first (§13). NOT seen in Studio.** Nothing was committed, pushed or published.
Studio was not opened. REVIEW-4's part budget holds: the server builds exactly the Parts it built before (§6).

**Review round (2026-09-24, §13).** An independent reviewer found six defects; each was reproduced before
anything changed, then fixed with a failing check first:
1. In a one-layer tunnel a falling rock was drawn through the miner's head, then dropped in one frame. It
   now pokes out of the roof above the head, falls where it can be seen, and lands on the floor.
2. The deep strata's stone (obsidian 4.5 RGB away, the core and magma on Basalt itself) looked like the
   unbreakable bedrock walls. No stone may now use the bedrock's material or come within 45 RGB of it.
3. On a phone, an open shop or top-10 drawer hid the hazard banner and the Rest button. The row now moves
   into the side the drawer leaves free.
4. The shadow ring jumped 6 studs into the air when the player jumped, and stayed there if the jump spanned
   the lock. It now stays on the floor the miner stood on.
5. Glowing decor was coloured like ore (ice-blue crystals were diamond, gold glyphs were gold). Every
   glowing decor colour now comes from one palette that is held 70 RGB from any ore that can sit beside it.
6. The underground fill light was 1.6-2.9x the server's dark preset, which weakens the paid lamp. The fill
   is now within 1.25x of the preset: the strata tint it, they do not brighten it.

**Resume session (2026-09-24, §11).** Two earlier build attempts were cut off by a usage limit. They left
all the code and checks, but not this file, no mutation sweep and no record of either. This session read
every new and changed file, rebuilt the bundle (byte-identical to the one on disk) and ran every gate: all
green. It then found and fixed, test-first:
1. The named layer sat on a knife edge: a real R15 root a hair low read the layer below.
2. The hazard ring and the rest lantern were drawn off the floor.
3. A falling rock under a tunnel's ceiling hung inside the rock, invisible.
4. A count in `check_deepvein_cave` could flake.

It also added `check_deepvein_rarity` (hazards measured in ordinary play) and ran four mutation sweeps
(59 mutants, 6 controls). Those showed three more promises the checks did not hold: the elevator glide,
set pieces fading and the ring's geometry. All three are now held (§8).

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **+1 Jump's template, byte-identical**: progress → band + eased blend, frame-rate-independent smoothing, announcer, `capRates` (the weather budget). Pure. |
| `src/shared/Hazards.luau` | the template plus **vertical kinds** (`drop = "above" / "below"`, `height`, `fall`): a hazard hangs over (or under) the miner, tracks them, locks, then drops straight at the spot. Also `ctx.canDodge == false` holds a due hazard (nowhere to step) and a fallback knock direction for a dead-centre hit. The template's sideways kinds, zone rule and swept hit test are unchanged. Pure. |
| `src/shared/Rest.luau` | the template plus `SettleSeconds` and `MinAwakeSeconds` (§4): progress here is CLICKING, so a rest must wait for stillness and cannot be toggled between swings. Pure. |
| `src/shared/Strata.luau` | new, Deep Vein's half. It covers: depth and the named layer from the character's root (the server's own `minerLayer` arithmetic); the rock's colour and material at a layer (the band palette across the fade, the old per-cell jitter, accent cells); the open cells beside a miner and the open layers above them (both from Parts the client can see); the bedrock walls' inner faces; where the wall decorations go; **(review round)** where a falling hazard is drawn (`dropY`) and which floor its ring lies on (`ringLayer`). Pure. |
| `src/shared/CaveArt.luau` | new, client-only art built in code (no assets): the pithead set piece, the core's glowing floor, 17 kinds of wall decoration, 6 critters, 10 weather kinds, 8 hazard models with their shadow ring and lane, the rest lantern. |
| `src/shared/Config.luau` | + `Env` (11 bands), `Hazards` (8 vertical kinds), `Rest`, `Budget`, `Pacing`. **Review round:** `Mine.BedrockColor/BedrockMaterial`, `Env.HeadTopAboveFloor`, `MinBedrockContrast`, `MinDecorOreContrast`, `DecorGlow`, `LampFill`; new rock for magma, obsidian and the core; the underground fill scaled down. |
| `src/client/Cave.client.luau` | new, the glue: depth → bands → Lighting, set pieces, decor, critters and weather; hazards and the knock; rest and its button; the band chip, title cards and fanfare. |
| `src/client/Hud.client.luau` | the brag: the emoji of the stratum a depth reaches, next to your best depth and on every top-10 row (`best 240m 🔥`, `3. Miner — 900m 🌋`). |
| `src/server/Main.server.luau` | the rock a stone Part is made of follows its depth (`Strata.rockLook`): colour and material only, on the Part it already built. Two requires and one helper (`rockLookOf`); `tintOf` and `makeCellPart` changed. **Review round:** the bedrock's colour and material are read from `Config.Mine` (the same values). Nothing else. |
| `tests/` | `EnvBands.spec` (template, byte-identical), `Hazards.spec` and `Rest.spec` (template + a Deep Vein section each), `Strata.spec` and `EnvConfig.spec` (new). |
| `robloxemu/check_deepvein_cave.luau` | the glue through the real server and client: depth, glide, every band and seam within budget, hazards, the pit, rest, critters, no leaks, the HUD fit, the brag. |
| `robloxemu/check_deepvein_cave_{budget,hud,join}.luau` | budgets under 400 fast elevator rides with hazards every 6-7 s; the repo's HUD-fit gate with the strata row on; title cards and the fanfare after a slow profile load. |
| `robloxemu/check_deepvein_{strata,pace}.luau` | the server really builds the strata into the rock, and a rebuilt cell looks the same; how long a player takes to reach each stratum. |
| `robloxemu/check_deepvein_rarity.luau` | **resume session**: hazards in ORDINARY play (the pace bot digging, the real client on modelled time). |

---

## 2. The strata and what triggers them

**Trigger: depth, never time.** Every frame the client reads its own character's root in its own shaft:

* **continuous depth** (`Strata.depthAt`, in layers) drives every BLEND: lighting, atmosphere, post-fx, set
  pieces, critters, weather;
* the **named layer** (`Strata.layerAt` = `Mine.layerOfY` at the root, exactly the server's `minerLayer`)
  NAMES the stratum. That covers the chip, the title cards, which hazards come, where the ring and lantern are
  set down and which wall decorations are built. The chip counts metres the way the HUD does
  (`Mine.depthStuds`, layer × 6), so standing at your deepest dig, `⛏️ 240m deep` and
  `🔥 Magma Glow · 240 m` read the same number. **Fixed this session:** it was read at the feet (root - 3),
  and a settled R15's feet are ON the floor's plane, so a root a hair low named the layer below.

The rock itself follows depth on the **server** (`Strata.rockLook`, applied to every stone Part it builds):
the band's colour and material, blended across the band's fade so a boundary is a gradient and never a line,
with the old per-cell jitter and an occasional accent cell (a rust streak, a moss patch). Ore keeps its own
Neon colour. `EnvConfig.spec` walks every layer a player can reach and checks every ore that can exist there
against the darkest and lightest jitter of both plain and accent rock. Worst: **81.0** (copper on the topsoil's
Ground), against a floor of 70. **Review round:** the same walk holds every stone look at least 45 RGB from
the bedrock walls and off their Basalt (closest now 47.0, the topsoil's accent), and every glowing decoration
at least 70 from any ore that can sit beside it (closest 74.1, a lava crack beside copper).

**Transitions never cut.** A band blends in over `fade` layers above its `from`, eased. On top of that, every
written value glides with a 0.6 s half-life, so an elevator ride glides too. Lighting is written at most
10×/s and only when a value changed. Measured, DESCEND from layer 1 to 312: `ClockTime` 17.61 → 23.59 with no
single write above 11% of the change (the first one included), no overshoot, and Ambient likewise. The
headframe fades out at ≤ 0.1 transparency per frame, followed by reference so that vanishing would count.

| # | stratum | from layer (fade) | first reached (run) | normal / fast / slow min | rock | light and air | life and weather | on the walls / set piece | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌱 Topsoil & Roots | 0 | spawn | 0.0 | brown Ground, dark accents | the client's dusk (ClockTime 17.6), warm haze, sun rays | fireflies · golden motes | roots · **the pithead**: timber headframe with sheave wheel and cable, rim lanterns, grass on the rim, a meadow out to 90 studs | none |
| 2 | 🪨 Grey Stone | 4 (2) | run 0 | 0.2 / 0.1 / 0.3 | grey Slate | night underground, cold grey grade | moths · dust | slate seams, pebbles | rock |
| 3 | ⛓️ Iron Veins | 10 (3) | run 0 | 0.4 / 0.2 / 0.6 | Slate, **rust-red streaks** | rust-tinted | bats · rust flakes | mine timbers, rust streaks | rock |
| 4 | 🌊 Underground River | 18 (3) | run 0 (wall 24) | 0.8 / 0.5 / 1.3 | wet blue Slate | cold blue, stronger bloom | bats · **falling drips** | **waterfalls**, wet patches | stalactite, steam |
| 5 | 🍄 Glowshroom Grotto | 28 (4) | run 1 (wall 36) | 11.7 / 7.4 / 18.9 | mossy Rock, green accents | teal-green, bloom 1.1 | **glowmoths** · rising spores | **glowing fungus shelves** (teal or pink) | stalactite, steam |
| 6 | 🔥 **Magma Glow** ★ | 40 (5) | run 2 (wall 48) | **27.8** / 17.5 / 44.7 | dark red-brown Rock, red-hot accents | orange, glare, bloom 1.3 | cinders · **rising embers** | **lava cracks, lavafalls** | lava drip, steam |
| 7 | 💎 Crystal Geode | 54 (6) | run 3 (wall 60) | 51.1 / 31.7 / 82.4 | violet Marble | violet, saturated | wisps · glints | **crystal clusters** (violet or rose) | falling crystal, steam |
| 8 | 🦴 Fossil Beds | 78 (8) | run 5 (wall 84) | 108.9 / 66.9 / 176.2 | Sandstone | warm dust | bats · sand | **ammonites, rib cages** | rock, stalactite |
| 9 | 🏛️ Lost Ruins | 100 (8) | run 7 (wall 108) | 181.2 / 110.3 / 293.9 | pale Limestone | gold | wisps · golden motes | **sandstone arches with turquoise keystones, turquoise glyphs** | crumbling ruin, rock |
| 10 | 🌑 Obsidian Depths | 124 (8) | run 9 (wall 132) | 279.8 / 168.6 / 454.7 | dark violet Slate, brighter violet accents | deep violet | wisps · violet motes | **black glass shards with pink-violet lit edges** | falling shard, magma burst |
| 11 | 🌋 **The Core** ★ | 150 (12) | run 11 (wall 156) | **386.7** / 232.2 / 629.1 | deep crimson Rock | red-orange, strongest bloom 1.6 | cinders · **sparks** | glowing runes, lava cracks · **the glowing, cracked bedrock floor** | lava drip, magma burst |

**Review round (§13):** the magma, obsidian and core rock changed (the old near-black obsidian and black-red
Basalt looked like the bedrock walls), the glowing decor colours changed (crystals were diamond-blue, glyphs
gold), and every stratum below the surface now has the server's dark fill tinted by its colour rather than
1.6-2.9x as bright. Light and air still differ by stratum in hue, fog, atmosphere, grade and bloom.

★ = a fanfare the first time you ever stand in it: `🔥 YOU REACHED THE MAGMA!` / `🌋 YOU REACHED THE CORE!`,
an orange flash and an FOV punch. That happens once, and only for a stratum deeper than your saved best. The
first card of a session waits for the profile to load, so a returning player gets a quiet card naming where
they are (`check_deepvein_cave_join`, with a 20-second load). Any new stratum you stand in during a session
gets a quiet title card (`🌊 UNDERGROUND RIVER`, `108 m deep`).

On screen all the time: a chip under the HUD's readout (`🔥 Magma Glow · 240 m · 💎 in 84 m`), the `⛺ Rest`
button, and the brag emoji next to your best depth and on the top-10 board.

**Placed on the game's own ladder.** The depth wall is 24 + 12 × rebirths, and a run spends most of its time
near the bottom of its shaft, so strata open near the bottom of a rebirth. The first four come in the first
minute. After that a new stratum is the bottom of a run at least every second run
(`river, grotto, magma, geode, geode, fossils, fossils, ruins, ruins, obsidian, obsidian, core`, asserted ≤ 2
in a row).

**Pacing is a model** (`check_deepvein_pace`, no telemetry exists). The pace bot plays the real server, with
every swing on a real ClickDetector, every haul sold at the real SELL, every upgrade bought and every rebirth
taken through the real atomic flush. The human costs are written down in `Config.Pacing.Profiles`: normal =
0.45 s per swing, 1.5 s per new block, 12 s per surface trip (fast 0.32 / 0.8 / 7, slow 0.7 / 2.5 / 20). The
owner gave no Deep Vein target. The check asserts that the magma, the first fanfare and the first brag, comes
during the third run inside 25-45 min, and that the core is at least 3× that (it is 13.9×: about 6.4 hours).
That is the long-term goal, like +1 Jump's galaxy.

---

## 3. Hazards and their measured rarity

A mine shaft is a box of rock, so nothing flies in sideways: every Deep Vein hazard is **vertical**.

| kind | strata | drops | hangs (s) | telegraph | locks before it lands | hitbox | ring (the danger zone) | knock |
|---|---|---|---|---|---|---|---|---|
| falling rock | stone, iron, fossils, ruins | from 22 studs up in 0.6 s | 2.6 | 3.2 s | 1.6 s | 1.6 | 6.0 studs across (one cell) | 32 |
| stalactite | river, grotto, fossils | 20 up, 0.5 s | 2.7 | 3.2 s | 1.6 s | 1.6 | 6.0 | 30 |
| lava drip | magma, core | 18 up, 0.7 s | 2.7 | 3.4 s | 1.7 s | 1.6 | 6.0 | 30 |
| falling crystal | geode | 20 up, 0.5 s | 2.7 | 3.2 s | 1.6 s | 1.6 | 6.0 | 32 |
| crumbling ruin | ruins | 22 up, 0.6 s | 2.6 | 3.2 s | 1.6 s | 1.6 | 6.0 | 34 |
| falling shard | obsidian | 20 up, 0.5 s | 2.7 | 3.2 s | 1.6 s | 1.6 | 6.0 | 32 |
| steam vent | river, grotto, magma, geode | bursts up from 7 below in 0.35 s | 3.05 | 3.4 s | 1.8 s | 1.6 | 6.0 | 28 |
| magma burst | obsidian, core | 7 below, 0.35 s | 3.25 | 3.6 s | 1.8 s | 1.6 | 6.0 | 36 |

**Rules** (`Hazards.luau` + `Config.Hazards`, validated at load; an invalid config switches hazards OFF with
a warning, it never costs the game):

* **When.** One hazard every **120-180 s of mining**, on a clock that only runs while you are not resting.
  Never two at once. None in the topsoil (the mouth, the SELL pad, the spawn). A hazard that comes due in a
  quiet band is re-rolled, so arriving somewhere never releases a backlog.
* **Only when you can step out of it.** It launches only while you stand on something AND have an open cell
  beside you (`Strata.openSides`, from the Parts your client can see; the bedrock ring never counts). In a
  one-cell pit a due hazard waits, and it comes as soon as there is room (measured: under 2 s after climbing
  out, 0 in 8 minutes in the pit).
* **The telegraph.** The ⚠️ marker is on top of everything, even through rock. The hazard's model is
  dropping dust (or, for a vent, a hissing orange glow on the floor). The **ring at your feet** is a dark
  shadow for a rock and an orange glow for a vent; its dark disc is exactly the danger zone and its neon rim
  sits 0.2 studs outside it. It lies on the floor you last stood on, so a jump does not lift it (review
  round, `Strata.ringLayer`). A lane line runs from the model's tip to the ring, and a HUD banner reads
  `⚠️ FALLING ROCK ABOVE ▲` / `⚠️ STEAM VENT BELOW ▼`. While the warning runs, the hang point follows you
  (it comes FOR you). 1.6-1.8 s before it lands it LOCKS: line and rim turn red and the banner says
  `⚠️ MOVE! Step out of the shadow ▲`. Following you never needs more than 1.5× its fall speed; an elevator
  ride locks it where it is.
* **Seen where it hangs.** The plan hangs a rock 18-22 studs up. Under an open column that is in plain
  sight. Under a tunnel's roof it was first inside the rock (invisible until it hit), then, in the resume
  session, drawn "just under the ceiling", which in a one-layer tunnel (6 studs) put a 2-3.8-stud model
  through a 5.2-stud avatar's head (review round, finding 1). It is now drawn by `Strata.dropY`: under the
  real ceiling if there is room, never lower than `Env.HeadTopAboveFloor` (5.3) plus half its height, so in a
  one-layer tunnel it pokes 0.7 studs out of the roof, a stone working loose with its dust and marker; in a
  room two layers tall it hangs whole between head and roof. It falls from there and passes the aim height
  at the plan's own moment (the hit), turning about the vertical axis, then lies on the floor. Measured, every
  falling kind in a tunnel with a settled R15: bottom at 5.30 while hanging, a fall of 5.30 studs over 10-18
  frames at 15 fps, never below the floor, every one still a hit. Drawing only: the plan, the zone and the hit
  are unchanged.
* **The dodge.** The ring is `2 × (hitRadius 1.6 + PlayerRadius 1.4)` = 6 studs across, **one cell**, and a
  hit needs you inside it. Step into any open cell beside you: 3 studs at 16 studs/s is 0.2 s, and the lock
  leaves 1.6-1.8 s (`EnvConfig.spec` asserts time to walk two cells).
* **A hit.** A horizontal push away from the hazard (toward your open side if it lands dead centre) plus 8
  studs/s of lift (capped at 15 by `Hazards.validate`: it can never launch you onto anything). You also get
  `PlatformStand` for 0.9 s: you are knocked down. Camera shake and a light flash. **Nothing is lost:** no
  health, no ore, no cash, no depth.

**Measured:**

| measurement | where | result |
|---|---|---|
| raw scheduler, 20 h | `Hazards.spec`, `EnvConfig.spec` (real config) | 477 hazards = **one per 150.9 s**; gaps 120.5-180.0 s; never 2 in the air |
| standing still beside an open cell, geode, 20 min | `check_deepvein_cave` §5a, real client | 8-9 hazards (crystal, steam), **every one hits**, each warned ≥ 3.13 s before; knock ≥ 28 studs/s sideways, ≤ 8 up; it wears off every time |
| stepping one cell aside at `MOVE!`, 20 min | §5b | 7-8 hazards, **0 hits** |
| a one-cell pit, 8 min / the mouth, 10 min | §5c / §5d | **0** / **0**; the held hazard launches < 2 s after there is room |
| **ordinary play: the pace bot digging runs 0-5 (142 modelled minutes), real server + real client** | `check_deepvein_rarity` (new) | **46-50 hazards = one per 2.8-3.1 min of play** (0.32-0.35/min), one per 2.6-2.9 min below the surface; median gap 2.5-2.7 min, shortest 2.0 min; an open cell beside the miner 49% of the time underground; most in the geode (20-24), magma (8-12) and grotto (7-9) |
| same bot, which never dodges | `check_deepvein_rarity` | hit by **9-16 of 46-50 (19-32%)**: it keeps moving between blocks, which walks it out of most rings |
| 400 elevator rides with hazards every 6-7 s | `check_deepvein_cave_budget` | 177-178 hazards, never 2 at once, every budget held on every frame |
| **review round:** a jump under a warning, and a jump across the lock (60 fps, real jump speed) | `check_deepvein_cave` §5f | ring ≤ 0.09 studs off the floor in the air and after landing (was 6.09); the hazard still lands |
| **review round:** a phone with the shop open, a hazard inbound | `check_deepvein_cave` §9 | banner on 94 of 94 warning frames (was 0), Rest button on 94 |
| rest-toggle exploit probe, 6 h | `Hazards.spec` | never rests **142**, toggles every 7 s **142**, rests 40 s of every 150 s **142** |

So in ordinary digging a player meets **one hazard every 2.8-3.1 minutes**. That sits at the slow end of the
owner's "about one per 2-3 minutes". Every one is a near-hit by construction (it comes for you), easy to step
out of, and costs nothing if you do not. The knob is `Config.Hazards.IntervalMin/Max` (seconds of mining);
`check_deepvein_rarity` asserts that ordinary play stays between one per 2 and one per 4 minutes.

---

## 4. Rest: what "pause" means in a mine

A Roblox server cannot stop the world for one player, so **rest is a state the player is in**:

* **⛺ Rest** (the button beside the band chip, thumb-sized on touch): you sit down and a lantern is set down
  beside you on the floor. The view softens (depth of field) and the chip says
  `⛺ Resting — the cave leaves you alone`. The button says `▶ Mine`. Press it, swing, or move to carry on.
* **Idle rest:** 20 s with no step and no swing and the cave leaves you alone too (`💤 Idle`), which makes
  you AFK-safe. You are not sat down.
* **While resting:** no hazard launches and the hazard clock FREEZES (it is never reset). The strata, bats,
  drips and embers carry on. Nothing is lost and nothing is earned.
* **Roblox's idle disconnect** (about 20 minutes without input) still applies. Nothing is lost then either:
  the cave, the haul and the depth are saved and restored on rejoin (REVIEW-3).

Deep Vein's progress is **clicking**, not walking: you stand still and swing. So two rules sit on top of the
template (`Rest.luau`, both mandatory in `EnvConfig.spec`):

* **A swing is activity.** A click on the world, or a TAP on a phone, wakes you and stops idle rest.
  A finger dragged across the screen turns the camera and does NOT wake you (checked).
* **`SettleSeconds` 1.5:** a rest starts only after 1.5 s without a step or a swing.
  **`MinAwakeSeconds` 6:** after a rest ends, the next cannot start until you have been awake 6 s. A request
  that cannot start yet is queued (`⛺ …`), and a swing drops it.

**Why it cannot be exploited**

1. **There is nothing to dodge.** Deep Vein has no round clock, no raid, no timed event and no penalty. The
   leaderboard is best-ever DEPTH, which only digging changes. The rebirth price is on what this run has
   earned. Rest touches none of these. The only thing it pauses is hazards, and a hazard takes nothing.
2. **You cannot mine while resting.** Digging is the server's ClickDetector on the server's rock, and any
   swing wakes you. The server does not know rest exists. A modified client that never woke up would only
   skip its own hazards, and it could delete them outright anyway.
3. **Not a panic button.** Rest cannot START in the air or with a hazard inbound (`BlockWhileThreat`,
   mandatory in `Rest.validate`). The request queues, the hazard still lands on a miner who does not move,
   and a hit voids the request (checked through the real client). A queued request outlives the longest
   hazard (4.8 s) by more than 2 s.
4. **Toggling does not thin hazards.** Rest FREEZES the mining clock, never resets it. Measured: 142 hazards
   per 6 climbing hours whether you never rest, toggle every 7 s or rest 40 s of every 150. Through the real
   client, the next hazard after a 10-minute rest came 120-180 MINING seconds after the previous one. A
   miner who swings and presses Rest between every swing for a minute rested **0 frames**.
   (`Rest.spec`'s controls: with neither Deep Vein rule the same toggler rests over 300 of 600 seconds, and with `MinAwakeSeconds` alone it still rests between swings, which is why `SettleSeconds` exists.)
5. **Rest never removes a hazard already in flight.**

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| the rock's colour and material per stratum | **server** (`Main.server` → `Strata.rockLook`) | a Part's Color and Material replicate with it anyway: no extra Instance, no extra traffic, and every client sees the same strata. Deterministic per cell, so a streamed-out cell comes back looking exactly the same (checked). |
| lighting, atmosphere, post-fx, the pithead, the core's floor, wall decor, critters, weather, chip, cards, fanfare | **client** (`Cave.client` + `CaveArt`) | cosmetic and per-player (your strata follow YOUR depth); costs the server nothing, replicates nothing |
| hazards: schedule, telegraph, hit test, knock | **client** | harms only the local player, whose character physics the client already owns |
| rest | **client** | it only pauses client hazards |
| digging, ore, cash, depth, best depth, the leaderboard, rebirth, saves, the streamer | **server** (unchanged) | authoritative, as before; it trusts nothing from the client |
| the brag emoji | client (`Hud.client`) | read from depths already on the board and in your own state |

**Leak review.** The client reads its own character, its own camera, `Config` (already replicated), its own
`leaderstats.Depth` (to know its best before the first card), and the Parts of its own shaft the server
already replicated. It never reads the cave generator:

* "open beside you" and "open above you" come from which cells have a Part. Every cell next to an opened
  one is revealed, so that is exactly what you can already see.
* Wall decorations are laid out from `(layer, Env.DecorSeed)` alone. They are the same in every shaft and at
  every rebirth, and say nothing about ore or voids.
* The rock look is a seed-0 per-cell hash plus the layer: nothing about what is behind a face.
* Critters fly only through cells you have stood in.

It fires no remote, adds no remote, sets no attribute and changes nothing the server built.
`check_deepvein_cave` §8 snapshots every server Part's colour, material, transparency, size, collision and
`CellKey` before the client starts and compares at the end. It also asserts that the client added exactly one
workspace folder and two Lighting effects (its rest focus and the surface's sun rays) and fired no remote.
Every local Part is anchored and non-collidable, non-queryable and non-touchable: a swing's click passes
straight through a crystal to the rock behind it, and nothing can be stood on. Spawn order
(`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame at spawn, and
`place`'s wait-for-parent is unchanged.

**What other players see.** The strata in the rock (server). Not your lighting, decor, critters or hazards:
those are yours. Shafts are private boxes 160 studs apart, so a knock with nothing hitting is essentially
never seen by anyone else.

---

## 6. Budgets (measured)

**Server: REVIEW-4's budget holds, unchanged.** The strata are two properties of a Part the server already
built. The measured shaft numbers are identical before and after:
* `check_deepvein`: shaft 0 on join, 56 parts (41 rock, 8 ore, 0 bedrock cubes, 5 shell slabs, 1 pad).
* `walk`: peak 486 cell parts + 5 slabs.
* `Mine.spec`: worst ±16-layer window of a lattice dig 1 080 rock+ore faces, 19 115 unbanded. REVIEW-4's
  worst state, **1 124 Parts**, is untouched: the strata change what a Part is made of, never whether it
  exists.

**Client**, built only by the client. `check_deepvein_cave` measures after 12 s at the middle of every stratum
and at the midpoint of every seam, with the trail walked, and on every frame a hazard flies. Re-measured
after the review round: every number below is unchanged (the fixes change colours, placements and one
formula, never what is built):

| where | parts | emitters (rate) | lights |
|---|---|---|---|
| topsoil | 49 | 1 (3.8/s) | 1 |
| topsoil › stone | 50 | 2 (5.0/s) | 1 |
| stone | 31 | 1 (5.9/s) | 0 |
| stone › iron | 39 | 2 (6.0/s) | 0 |
| iron | 39 | 1 (5.9/s) | 0 |
| iron › river | 35 | 2 (10.2/s) | 0 |
| river | 35 | 1 (13.9/s) | 0 |
| river › grotto | 40 | 2 (12.0/s) | 0 |
| grotto | 36 | 1 (10.0/s) | 0 |
| grotto › magma | 40 | 2 (13.8/s) | 0 |
| magma | 40 | 1 (17.8/s) | 0 |
| magma › geode | 49 | 2 (13.0/s) | 0 |
| geode | 68 | 1 (7.8/s) | 0 |
| geode › fossils | 69 | 2 (6.8/s) | 0 |
| fossils | 64 | 1 (5.9/s) | 0 |
| fossils › ruins | 62 | 2 (6.7/s) | 0 |
| ruins | 69 | 1 (6.9/s) | 0 |
| ruins › obsidian | 74 | 2 (7.8/s) | 0 |
| obsidian | **79** | 1 (8.9/s) | 0 |
| obsidian › core | 75 | 2 (18.7/s) | 1 |
| core | 63 | 1 (**27.9/s**) | 1 |

| metric | normal play, peak | stress (400 rides, hazards every 6-7 s) | budget (`Config.Budget`) |
|---|---|---|---|
| local parts | **79** (obsidian) | 102-106 | 200 |
| particle emitters | 2 | 3 (2 weather + a hazard's dust) | 4 |
| particles per second | **27.9** (core sparks) | 43.9-44.0 | 60 |
| point lights | 1 | 2 | 3 |
| beams / trails | 0 / 0 | 0 / 0 | 4 / 6 |
| hazards at once | 1 | 1 | 1 |

**How it stays cheap:**
* **Set pieces** (the pithead, the core's floor) are built the first time their band needs them, faded by
  weight and UNPARENTED at weight 0.
* **Wall decor** exists only within 10 layers of the miner (the best lamp reaches 12) and is built at most
  2 layers per frame, nearest first. It is destroyed when the miner moves on and rebuilt identically from the
  seed. In the stress run 15 098 were built and 15 070 destroyed, leaving 28, all within range: decor is
  churned, not pooled, which costs `Instance.new` calls but never a pile-up.
* **Critters** are pooled per kind, at most one spawned per kind per frame.
* **Weather:** one host box around the camera, at most `MaxWeatherEmitters` = 2 on, summed rate capped at 60/s
  (`EnvBands.capRates`).
* **Hazards:** one model per kind, one ring, one lane.
* **Rest:** one lantern.

Lighting is written ≤ 10×/s, only on change. These are part and emitter counts, not frame times: phone frame
time is on the Studio list. On top of the server's shaft (up to 1 124 Parts in the worst state the game can
reach, typically 50-500), the client adds at most ~80 in play.

---

## 7. Gates

Every gate green on the final tree. "Before" is the game as REVIEW-4 and the spawn fix left it. "Earlier
attempt" is the last run the interrupted build made (2026-09-23 18:17), before its final edit.

| gate | before the strata | earlier attempt | resume session | **review round (final)** |
|---|---|---|---|---|
| `tests/Ore.spec` | 1272 / 0 | 1272 / 0 | 1272 / 0 | **1272 / 0** |
| `tests/Mine.spec` | 173 / 0 | 173 / 0 | 173 / 0 | **173 / 0** |
| `tests/Economy.spec` | 131 / 0 | 131 / 0 | 131 / 0 | **131 / 0** |
| `tests/Prestige.spec` | 220 / 0 | 220 / 0 | 220 / 0 | **220 / 0** |
| `tests/Responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | **70 / 0** |
| `tests/EnvBands.spec` (template) | — | 124 / 0 | 124 / 0 | **124 / 0** |
| `tests/Hazards.spec` | — | 140 / 0 | 140 / 0 | **140 / 0** |
| `tests/Rest.spec` | — | 76 / 0 | 76 / 0 | **76 / 0** |
| `tests/Strata.spec` | — | 74 / 0 | 83 / 0 | **103 / 0** (where a falling hazard is drawn; which floor its ring lies on) |
| `tests/EnvConfig.spec` | — | 246 / 0 | 246 / 0 | **269 / 0** (stone vs bedrock; glowing decor vs ore; the fill light; head clearance) |
| **spec total** | **1866 / 0** | **2526 / 0** | **2535 / 0** | **2578 / 0** |
| `tests/walk.luau` | 129 / 0 | 129 / 0 | 129 / 0 | **129 / 0** |
| `robloxemu/check_deepvein` | 136 / 0 | 136 / 0 | 136 / 0 | **136 / 0** |
| `robloxemu/check_deepvein_cave` | — | 231 / 0 | 251 / 0 | **387 / 0** (every falling kind in a tunnel, settled root; jumps; both phone drawers at six viewports; the banner live with the shop open; the fill vs the server's real Lighting; every glowing decoration built; the pit's walls streamed before the count) |
| `robloxemu/check_deepvein_cave_budget` | — | 10 / 0 | 10 / 0 | **10 / 0** |
| `robloxemu/check_deepvein_cave_hud` (HUD fit, 10 viewports, overlap on) | — | PASS | PASS | **PASS** |
| `robloxemu/check_deepvein_cave_join` | — | 22 / 0 | 22 / 0 | **22 / 0** |
| `robloxemu/check_deepvein_pace` | — | 29 / 0 | 29 / 0 | **29 / 0** |
| `robloxemu/check_deepvein_strata` | — | 38 / 0 | 38 / 0 | **45 / 0** (real stone Parts vs the bedrock, an obsidian miner added; the core's material read from config) |
| `robloxemu/check_deepvein_rarity` | — | — | 15 / 0 | **15 / 0** |
| **headless total** | **265 / 0** | **595 / 0 + PASS** | **630 / 0 + PASS** | **773 / 0 + PASS** |
| compile (`loadstring`, see below) | — | — | 35 / 35 files clean | **35 / 35 files clean** |

`luau-compile` and `luau-analyze` are not in the shared scratchpad any more (another session removed them).
Compilation was checked the way the sibling sessions did: each file's source is handed to `loadstring`,
which compiles without running. The checker was proved able to fail on a broken file. All 16 sources, 11 test
files and 8 `check_deepvein*` files compile. The headless checks also RUN every source (server, HUD, cave
client) and fail on any scheduler error. **No type analysis was run this session.**

The emulator's `Random` is unseeded, so the hazard counts in `check_deepvein_cave` vary run to run (8 or 9 in
§5a; 7 or 8 in §5b). §5a/§5b used to stop counting at the 20-minute mark, which could count a hazard at launch
but miss its landing. Seen once this session, as `8 hits of 9`: a windowing flake, not a defect. Both
sections now play the hazard in flight out before comparing. `check_deepvein_rarity` gave 46-50
hazards in seven runs (46, 47, 48, 49, 50, 50, 50), every run green. The final
`check_deepvein_cave` (251) ran green five times and `check_deepvein_cave_budget` five times.

**Review round.** All 19 suites were run on the real tree after the last edit: all green, with the counts in
the table. The bundle rebuilt from the final sources has md5 `dc9e9559536b37fce9893f0eec3755d6`, twice. Compile
is 35 / 35 files clean, and the checker was shown to fail on a broken file. No type analysis was run.
* **Stability.** On a copy identical to the real tree: `check_deepvein_cave` (387) green 20 times out of 20,
  `check_deepvein_rarity` 5 out of 5 (46, 48, 49, 50 and 52 hazards, one per 2.7-3.1 minutes; the hazard
  logic is untouched), and `check_deepvein_cave_budget` 3 out of 3.
* **Two latent races in `check_deepvein_cave`, older than this round, surfaced and fixed.**
  * §10: the server pushes its real top-10 every 30 s. When that push landed inside the check's 0.5 s
    window, it replaced the fake rows the check was reading. This happened in 1 of 24 runs of the pre-fix
    check. The check now re-sends its rows if the server's board is what arrived.
  * §5c: the check teleports the miner 43 layers into the pit by hand, where nothing is streamed yet. For a
    few frames the client took the unbuilt walls for open cells, so a hazard due at that moment launched
    (reproduced by forcing one due on arrival). A real arrival that deep is DESCEND, which builds the landing
    cell's neighbourhood synchronously first (REVIEW-4). So the check lets the server stream the pit in
    first, and asserts that its four walls exist before counting.
  * Neither race is a game defect, and neither assertion was loosened.

---

## 8. Mutation sweep

Four sweeps, all on scratch copies of the game and the emulator. The real tree was never mutated. The
harness is `scratchpad/dv_resume/sweep/sweep.py`, adapted from Fork Tower's. For every mutation it:
* checks that exactly one occurrence was replaced (edited in the file's own CRLF or LF);
* rebuilds the bundle and **proves the mutation reached `build/deep-vein.luau`**: the mutated bundle must
  equal the baseline bundle with the same single replacement;
* runs all 19 suites (10 specs, `walk`, 8 `check_deepvein*`);
* restores the original bytes and re-checks the md5.

After every sweep every suite was green again. Before each, the scratch copy was verified identical to the
real tree and its bundle identical to the real bundle apart from path lines. Logs and results are in
`sweep*.log` and `results_muts*.json`.

**Sweep 1: 45 mutations of the earlier attempts' code and this session's first three fixes.** The tree was as
it stood before the ceiling fix.
* **42 KILLED, 3 SURVIVED; both controls SURVIVED** (timber a shade redder; the rest lantern a little
  brighter).

| id | mutation | killed by |
|---|---|---|
| S1 | the named layer read at the feet again | Strata.spec, check_deepvein_cave |
| S2 | no accent cells ever | Strata.spec |
| S3 | the bedrock ring counts as a way out | Strata.spec |
| S4 | every layer's decor from the topsoil band | Strata.spec, check_deepvein_cave |
| S5 | depth above the mouth goes negative | Strata.spec |
| V1 / V2 | server: rock material / colour ignore the stratum | check_deepvein_strata |
| V3 | server: the accent roll random per build | check_deepvein_strata |
| C1 | Iron Veins' rust streak copper-coloured | EnvConfig.spec (ore readability) |
| C2 | hazards every 40-180 s | EnvConfig.spec |
| C3 | a rock's ring wider than one cell | EnvConfig.spec |
| C4 | falling rocks at the surface | EnvConfig.spec, check_deepvein_cave |
| C5 / C6 | MinAwakeSeconds / SettleSeconds off | EnvConfig.spec (C6 also check_deepvein_cave) |
| R1-R3 | Rest: awake rule always passes / moving never resets stillness / a stop does not start the awake clock | Rest.spec, check_deepvein_cave |
| H1-H6 | Hazards: falls before it locks / chases an elevator ride / does not track / launches with nowhere to step / dead-centre knock ignores the open side / moves from t = 0 | Hazards.spec (H4, H6 also check_deepvein_cave) |
| K1 | a swing is not activity | check_deepvein_cave, check_deepvein_rarity |
| K2 | a camera drag counts as a swing | check_deepvein_cave |
| K3 | always somewhere to step | check_deepvein_cave |
| **K4** | band weights snap on an elevator ride | **SURVIVED** → closed, see below |
| **K5** | lighting snaps instead of gliding | **SURVIVED** → closed, see below |
| K6 | rest does not freeze the hazard clock | check_deepvein_cave |
| K7 | a hit does not void a rest | check_deepvein_cave |
| K8 | the first card does not wait for the profile | check_deepvein_cave_join |
| K9 | the fanfare for a stratum already reached | check_deepvein_cave |
| K10 | the ring at root - 3 again | check_deepvein_cave |
| K11 | the strata row over an open HUD drawer | check_deepvein_cave |
| K12 | a knock without PlatformStand | check_deepvein_cave |
| K13 | Rest does not sit the miner | check_deepvein_cave |
| A1 | a band you left keeps its parts | check_deepvein_cave, _rarity, _cave_budget |
| A2 | decor never unloaded | check_deepvein_cave (493 parts), _cave_budget |
| A3 | critters wander into the rock | check_deepvein_cave |
| A4 | weather ignores the emitter cap | check_deepvein_cave_budget (5 emitters) |
| A5 | the lantern at root - 3 | check_deepvein_cave |
| A6 | local parts collidable | check_deepvein_cave |
| **A7** | the shadow ring half as wide as the danger zone | "killed", **for the wrong reason** → closed, see below |
| **A8** | the shadow ring a cell away from the danger zone | **SURVIVED** → closed, see below |
| U1 | the brag emoji gone | check_deepvein_cave |

**What the survivors showed, and how they were closed.** In each case the check was fixed, passed on the
real build, and was watched killing the mutant for the stated reason. A control survived every time.
* **K5:** the glide assertion took its baseline from the first frame AFTER DESCEND. A snap in that very
  frame therefore measured as "no change" and passed vacuously.
* **K4:** a set piece that snaps to weight 0 is unparented at once, and the check only read the headframe
  while it was parented.
* **Fix for K4 and K5 (`check_deepvein_cave` §2):** the series now starts before the ride, the headframe is
  followed by reference (unparented counts as transparent), and Ambient is held too. Sweep 3 on the final
  tree: **K4 KILLED** (`worst 1.000 per frame`), **K5 KILLED** (`worst step 26.0 of 26.0`), control (the
  rest blur) SURVIVED.
* **A7 was reported killed, but by `only the band's own kinds fly (magma)` and `7 hits of 8`.** A magma
  burst launched at the end of the band sweep (in the core) was still in flight when §5a moved the miner to
  the geode. That is a second flake in the check, independent of A7. Its real reach was the same as A8's:
  **the ring's geometry was not asserted at all.**
* **Fix for A7 and A8:** §5a now plays out anything in flight first, and asserts the dark disc is exactly
  `2 × (hitRadius + PlayerRadius)` across and centred where the miner stands. §5b asserts that a locked ring
  stays where the miner stood while they walk out of it. Sweep 4 on the final tree: **A7 KILLED** (`3.000
  studs off`), **A8 KILLED** (`6.000 studs off` twice), control (the rim's transparency) SURVIVED.

**Sweep 2: 10 mutations of this session's final code, plus 2 controls.**
* **9 KILLED, 1 SURVIVED; both controls SURVIVED** (the clamp's margin 0.1 → 0.15; timber on the final tree).
* N1 the rock drawn at the plan's height again, N2 `openAbove` never sees rock, N3 `ceilingY` one cell high,
  N4 half height 0, N6 the lane from the plan's start: all check_deepvein_cave (N2/N3 also Strata.spec).
* N5 the open mouth counts as a ceiling: Strata.spec.
* N8 S1 again on the final tree: Strata.spec, check_deepvein_cave. N9 the layer a cell high: Strata.spec,
  check_deepvein_cave, check_deepvein_cave_join.
* N10 a hazard needs two open sides: check_deepvein_cave. The rarity check alone would not catch it; the
  bot usually has two.
* **N7 SURVIVED, and it is equivalent:** it applies the ceiling clamp to vents too. A vent rises from under
  the floor, so the clamp can only change its jet's head once that head has passed the tunnel's roof, which
  is inside the rock, where nothing renders it. It was not "fixed" with a test for an invisible difference.

**Totals: 59 mutations of real behaviour.** All killed for the stated reason on the final tree except the
one equivalent mutant (N7). Six controls, all survived.

**Sweep 5 (review round): 20 mutations of the review round's fixes, plus 3 controls.** Same
harness, moved to `scratchpad/dv_r5/sweep/`; the scratch copy was verified identical to the real tree
(41 files) and its bundle identical to the real bundle apart from path lines; every source mutation was
proven to reach the bundle; every original was restored byte for byte. Result: **20 KILLED, 0 SURVIVED;
controls 3 of 3 survived (unnoticed), as they must.**

| id | mutation | killed by |
|---|---|---|
| D1 | F1 dropY: no head clamp (drawn through the miner again) | check_deepvein_cave, Strata.spec |
| D2 | F1 dropY: sinks 20 studs through the floor after the hit | check_deepvein_cave, Strata.spec |
| D3 | F1 dropY: falls in one frame | check_deepvein_cave, Strata.spec |
| D4 | F1 glue: head clearance measured from the floor itself | check_deepvein_cave |
| D5 | F1 glue: the ceiling is never found (hangs 22 up inside the rock) | check_deepvein_cave |
| D6 | F1 art: the lane from the model's centre (up into the rock) | check_deepvein_cave |
| D7 | F1 art: the fall tumbles again (a plate dips through the floor) | check_deepvein_cave |
| R1 | F4 ringLayer: always the root's layer (the jump lifts the ring) | check_deepvein_cave, Strata.spec |
| R2 | F4 ringLayer: a locked ring follows the miner's floor | Strata.spec (the check_deepvein_cave failures in that run were the two check races below, since fixed) |
| R3 | F4 glue: the ring believes the miner is always grounded | check_deepvein_cave |
| U1 | F3 rowSpan ignores an open drawer (row under the shop) | check_deepvein_cave |
| U2 | F3 the row hides again while a drawer is open (the reviewed behaviour) | check_deepvein_cave |
| U3 | F3 the banner stays in a squeezed left zone | check_deepvein_cave |
| B1 | F2 obsidian rock near-black again | EnvConfig.spec, check_deepvein_strata |
| B2 | F2 the core's rock is Basalt like the bedrock | EnvConfig.spec, check_deepvein_strata |
| B3 | F2 server: the bedrock is built of Slate, a stone material | check_deepvein_strata |
| G1 | F5 the ruins' glyphs gold again | check_deepvein_cave, EnvConfig.spec |
| G2 | F5 art: crystals hard-code ice-blue, bypassing the palette | check_deepvein_cave |
| L1 | F6 the ruins' fill light 2.6x again | check_deepvein_cave, EnvConfig.spec |
| L2 | F6 LampFill quotes a brighter preset than the server's | check_deepvein_cave |

| control | edit | result |
|---|---|---|
| K1 | rest lantern cap a shade redder | SURVIVED |
| K2 | teal glowshroom caps 2 points redder (still far from every ore) | SURVIVED |
| K3 | the lane line slightly more transparent | SURVIVED |

**Totals after the review round: 79 mutations of real behaviour, 78 killed for the stated reason, 1 equivalent
(N7); 9 controls, all unnoticed.**

---

## 9. Needs Studio (only real rendering, physics and a real device can judge)

1. **Every stratum's look.** Is it rich or muddy? Rock colour × material (Ground, Slate, Rock, Marble,
   Sandstone, Limestone) under each band's Ambient, grade and bloom, with the head lamp (26-74 studs) as the
   main light. Are the eleven strata visibly different in the lamp's circle, or only in the numbers?
2. **Ore readability.** RGB distance is ≥ 81 everywhere, but material textures and lighting change what the
   eye sees. Look at copper on topsoil Ground, gold on fossil Sandstone and ruin Limestone, and iron on grey
   Slate.
3. **Atmosphere density 0.4-0.5 in a 42-stud shaft.** Does it read as dusty underground air or as a wall?
   Roblox ignores `FogStart/End` while an Atmosphere exists, so the Atmosphere is what shows.
4. **Neon + bloom 1.1-1.6** on fungus, lavafalls, crystals, glyphs, runes and the core floor: glow or blown
   out.
5. **Wall decor scale.** Each find is 1-11 studs on a 6-stud cell face, only visible once the wall-side cell
   is dug. Is it a pleasant find or too rare to notice? Density knob: `Env.Bands[i].decor.perLayer`.
6. **The surface panorama.** The meadow ends 90 studs out and the neighbours' shafts stand 160 studs apart,
   so their basalt walls may show dropping into the void. Also check the pithead's proportions against the
   Roblox camera, where the dusk sun sits, and the sun rays.
7. **The falling rock under a ceiling** (review round, drawing only). In a one-layer tunnel it pokes 0.7 studs
   out of the roof over the avatar's head with its dust and marker, then falls 5.3 studs in 0.5-0.7 s and lies
   in the ring. Does 0.7 studs read as "a rock working loose above me" from the camera the tunnel forces? If not,
   the knob is `Env.HeadTopAboveFloor` (5.3): lower shows more rock, at the price of overlapping tall avatars.
8. **The camera in a 6-stud cell.** Roblox's camera collides with rock, so it may push in close. Check that
   the ring at your feet, the ⚠️ marker and the lane stay visible, that bats and moths do not fly into the
   lens, and that the banner is readable on a phone.
9. **The dodge on a real grid.** Step one cell aside in 1.6 s with a thumbstick. A neighbour cell one layer up
   needs a jump (6 of 7.2 studs), one layer down you drop into, which also leaves the ring.
10. **The knock in a narrow cell:** `PlatformStand` + a sideways push, often into a rock face. Knocked down,
    or stuck in the wall? It should release cleanly after 0.9 s.
11. **Rest's sit.** `Humanoid.Sit = true` from the client without a seat: does it sit and replicate? The
    lantern stands 2.2 studs to the right; at a cell's edge it may clip into rock.
12. **Real R15 root height.** The client now names the layer at the root (mid-cell), so it no longer depends on
    the feet. Confirm the chip, the cards and the fanfare land on the layer the HUD shows while standing,
    sitting and jumping in an open column.
13. **The fanfares** (orange flash + FOV punch): celebratory, not annoying.
14. **Frame time** on a mid and a low phone at the busiest spots: the obsidian band (79 parts) and the core
    (27.9 particles/s), on top of a streamed shaft of up to 1 124 server Parts.
15. **The four long wall slabs** (REVIEW-4): 54 × up to 1 893 studs of Basalt. Now they carry decor too.
    Does a seam or texture still look needed?
16. **Top row on a phone:** the chip's text length (`🍄 Glowshroom Grotto · 168 m · 🔥 in 72 m`), emoji in
    `TextScaled` labels, notch and safe area. With the shop or top-10 open the row moves beside the drawer
    (review round): on a 640x300 phone with the shop open the chip is only 83 design px wide; check it reads.
17. **The lamp against the fill (review round).** The underground fill was cut from 1.6-2.9x the server's dark
    preset to within 1.25x. Side by side at the ruins (the brightest band before) and the grotto: lamp level 1
    against lamp level 8. The paid lamp should visibly matter; the strata's tint should still show. If the
    strata look too alike now, raise `Env.LampFill.MaxAmbientRatio` a little rather than restoring 2.6x.
18. **The new rock (review round):** magma and the core are now `Rock` (dark red-brown, deep crimson), obsidian
    a dark violet `Slate`. Next to the near-black Basalt walls: do the walls read as the edge of the claim at a
    glance? And the new glow colours: rose crystals, turquoise glyphs and keystones, redder lava.

---

## 10. Thumbnail shot list (for the night Studio session)

**Getting there.** *This recipe has not been tried in Studio: verify steps 1-3 before relying on the rest.*

1. **Build a place.** In `deep-vein/`, run `rojo build -o DeepVein-shots.rbxlx` and open it (`*.rbxlx` is
   git-ignored). Keep Rojo disconnected while you edit the place.
2. **No saves exist to touch.** Deep Vein has never been published, so it has no DataStore. The server warns
   `datastore unavailable` and every Play starts from `defaultProfile()`, a fresh rebirth-0 miner whose wall is
   at layer 24. Nothing is saved.
3. **Start deep, in THIS place only, never in `src/`.** Open `ServerScriptService → Main` and, in
   `defaultProfile()`, set `pickTier = 5, backpackLevel = 12, lampLevel = 8, rebirths = 12`, plus the
   `depthLayer` / `bestLayer` each shot names below. On join the server builds a rebirth-12 shaft (wall at
   layer 168) and reopens its centre elevator column from layer 1 down to `depthLayer`. This is the legacy
   restore path for a profile with a depth and no saved cave, one cell per frame, about 3 s. Press
   **⬇️ DESCEND**: the elevator drops you to the bottom of that column. The tier-5 Singularity Bore breaks
   stone in one swing, so a room takes seconds. `lampLevel = 8` is the 74-stud head lamp: underground it is
   most of the light.
   **Use exactly the depths below.** The restore floods any natural cave the column breaks into. At some
   depths that cave reaches deeper than the column: in this seed at rebirth 12, 36 → 40, 64 → 68 and
   148 → 152. DESCEND would then land in the cave, not the column, and the saved best would already be past
   the next stratum, so its fanfare would never play. Every depth, block and wall position below was checked
   against the real cave generator, running the server's own restore on the pure modules.
4. **The look follows the AVATAR, not the camera.** Cave.client names the stratum from where the character
   stands, so park the avatar in the stratum and fly the camera. Freecam is Shift+P (it takes the movement
   keys).
5. **Clean frames** (command bar, Client):
   `local g = game.Players.LocalPlayer.PlayerGui; g.DeepVeinHud.Enabled = false; g.DeepVeinCave.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`
6. **Coordinates** are for shaft 0 (the first player in the server), whose mouth is centred on the world
   origin. Layer `L`'s floor is at `y = -6L` and a block of layer `L` is centred at `y = -6L + 3`. The column
   is at `x = z = 0`; "east" is +X, "south" is +Z. The walls' inner faces are at ±21. "Dig east 3" = click the
   blocks centred at x = 6, 12 and 18 on your layer, walking into each hole.
   The wall decorations named here come from `Strata.decorAt` with the shipped `DecorSeed`.

**Shot 1: "The pithead at dusk"** (🌱 surface). *Any session, even an unedited profile.*
Avatar at the spawn on the mouth's north edge (0, 4, -18). Freecam outside and above the meadow, about
(-70, 40, -80), looking at (0, 30, 0). In frame:
* the timber headframe on the rim: posts x = ±7, z = ±24, from y 15 to 47, the sheave wheel at y ≈ 53 and the
  cable hanging into the shaft;
* the two rim lanterns (x = ±12, z = -24);
* grass on the rim and the meadow;
* the mouth with its green SELL pad;
* the low dusk sun with sun rays: orbit until the sun sits behind the headframe.

**Variant:** the camera low in the mouth at about (10, 2, 10), looking up at (0, 50, 0): the headframe and the
wheel silhouetted against the dusk sky, fireflies around the avatar.

**Shot 2: "The underground river"** (🌊 layer 25). `depthLayer = 25, bestLayer = 25`.
DESCEND → (0, -146, 0). Dig east 3 (blocks at x 6, 12, 18; y -147), then the block at (18, -147, 6): the
river's waterfall hangs on the east wall at z ≈ 3.4. Avatar at (12, -146, 0) facing the wall. Camera in the
column at about (-2, -145, -2), looking at (21, -147, 4). In frame:
* the neon waterfall on the bedrock face;
* the wet blue rock with blue accent cells, and ore glowing in it;
* falling drip streaks and a bat or two in the tunnel;
* the cold blue grade.

**Shot 3: "Glowshroom grotto"** (🍄 layer 29). `depthLayer = 29, bestLayer = 29`.
DESCEND → (0, -170, 0). Dig south 3 (blocks at z 6, 12, 18; y -171, with gold and diamond in them). The third
opens a small natural cave to the west, and glowing fungus shelves stick out of the south wall at x ≈ -8.2.
Camera at about (0, -169, 8), looking at (-8, -171, 21); the avatar at the cave's mouth. In frame:
* the teal or pink fungus shelves;
* rising spores and glowmoths;
* mossy green rock;
* the green bloom.

**Shot 4: "YOU REACHED THE MAGMA!"** (🔥 layers 35 → 40, then 46).
* **Fanfare, first:** `depthLayer = 35, bestLayer = 35`, HUD ON. DESCEND → (0, -206, 0); the magma already
  tints the grotto from layer 35. Dig straight down (x = z = 0). Breaking layer 36 opens a natural cave
  around you (72 cells, layers 34-40); keep digging the column through 37, 38, 39 and 40. The first moment you
  STAND in layer 40 plays `🔥 YOU REACHED THE MAGMA!`, an orange flash and an FOV punch, **once per
  session**, so take a burst with the normal camera.
* **Main shot:** `depthLayer = 46, bestLayer = 46`. DESCEND → (0, -272, 0). Dig east 3 (y -273): a lavafall
  runs down the east wall at z ≈ 1.6. Camera about (4, -271, -4), looking at (21, -273, 2). In frame:
  * the lavafall on dark red-brown rock with red-hot accent cells, against the near-black bedrock wall;
  * embers rising and cinders drifting;
  * the orange grade and glare;
  * the avatar silhouetted against the lava light.

**Shot 5: "Close call in the geode"** (💎 layer 54). `depthLayer = 54, bestLayer = 54`, **and** in this
place's `ReplicatedStorage → Config`: `Hazards.IntervalMin = 8`, `Hazards.IntervalMax = 10`,
`Rest.IdleSeconds = 0`. Without `IdleSeconds = 0`, 20 s of standing still while you frame the shot rests
the miner and no hazard comes; `Rest.validate` accepts 0.

**Changed in the review round.** Under a one-layer tunnel's 6-stud roof a 3.4-stud crystal cannot hang over a
5-stud avatar: it now pokes out of the roof (finding 1). So this shot builds a room two layers tall.

DESCEND → (0, -320, 0). Dig south 3 (blocks at z 6, 12, 18; y -321). The first opens a small natural pocket
east of it (layers 54-56) that does not touch the shot. Then, from inside the tunnel, dig the two blocks of its
ROOF at (0, -315, 6) and (0, -315, 12). Both are diamond, and so are the blocks around them, so the room glows
cyan. The room is now 12 studs tall over z 3-15 and opens into the column.
Stand the avatar at (0, -320, 12) facing SOUTH, down the tunnel, so the normal camera sits behind it in the
tall room and the open column (freecam would take the movement keys). A hazard needs an open cell beside you,
and the tunnel gives two. Within 8-10 s a **falling crystal** (or a steam vent) comes. The violet crystal hangs
whole between the avatar's head and the roof, 8.5-11.9 studs over the floor (world y -315.5 to -312.1), with its
⚠️ marker. The dark ring with its yellow rim lies at the feet. Zoom out until all three are in frame. When the
rim turns red (`⚠️ MOVE!`), walk one cell south into the tunnel (0, -320, 18; its floor is a gold ore block),
out of the ring. Shoot as the crystal drops into the empty ring in the foreground and lies there.
Checked on the real generator (the restore plus each dig): the standing cell keeps rock east and west and a
floor under it, and the drawn crystal's height comes from `Strata.dropY` with the shipped config.
In frame:
* the crystal with its marker;
* the ring;
* the avatar just clear of it;
* the diamond-lit walls of the room.
Optional reverse angle: dig west 2 at the tunnel's end ((-6, -321, 18) and (-12, -321, 18)) for the violet or
rose crystal cluster on the south wall at x ≈ -11.2.

A hit only knocks the avatar down; take the next one.

**Shot 6: "The Core"** (🌋 layer 168, the bottom of a rebirth-12 shaft). `depthLayer = 168, bestLayer = 168`.
DESCEND drops you onto the bedrock floor (y -1008): the **glowing, cracked core floor** shows in every dug
cell of layer 168. Dig a plus around the column (blocks at (±6, -1005, 0) and (0, -1005, 6); the cell at
(0, -1005, -6) is already a small cave). Freecam in
the open column above, about (1, -990, 1), looking straight down at (0, -1008, 0). In frame:
* the avatar standing on the orange neon floor with its bright cracks;
* sparks streaking up and cinders drifting;
* the deep crimson rock, against the near-black bedrock walls;
* the strongest bloom and orange haze.

**Variant for the fanfare:** `depthLayer = 146, bestLayer = 146`, DESCEND → (0, -872, 0). Dig down: breaking
layer 147 opens a cave from 147 to 152 that includes the column's layers 150 and 151. Dig 148 and 149 and you
drop to layer 151: `🌋 YOU REACHED THE CORE!`.

*Spares if a shot disappoints:*
* 🏛️ Lost Ruins, layer 106: dig east 3; a sandstone arch with a turquoise keystone on the east wall at z ≈ 1.6.
* 🦴 Fossil Beds, layer 85: dig east 3 plus (18, y, 6); an ammonite on the east wall at z ≈ 3.4.
* 🌑 Obsidian, layer 124: the same dig, black glass shards with pink-violet edges at z ≈ 5.2, on dark violet slate.

---

## 11. Resume session (2026-09-24): what was found and fixed

The two earlier attempts left the code, the specs and six `check_deepvein_*` files complete and green, but no
EYECANDY.md, no mutation sweep and no note of what had been verified. This session:

* **Re-read** every new and changed file and diffed the three template modules against +1 Jump's.
  EnvBands and its spec are byte-identical. Hazards and Rest carry marked, additive Deep Vein sections, and
  their specs keep every template assertion and add their own.
* **Rebuilt the bundle**: byte-identical to the one on disk, so the earlier runs had tested the current
  code. **Re-ran every gate: all green** (2 526 spec + 598 headless + PASS; `check_deepvein_cave` was 234 by then, the earlier attempt's last edit had added 3).
* **Fixed, test-first** (each assertion watched failing on the unfixed build, for the stated reason):
  1. **The named layer sat on a knife edge.** It was read at `root - 3`. A settled R15's root is 3.0 studs
     over the floor, so that is ON the floor's plane, and a root 0.001 studs low named the layer below: the
     chip, the fanfare, the hazard kinds and the critter trail one layer too deep.
     * The spec failed on 972 of 2 268 settled samples and every seated one.
     * `check_deepvein_cave` failed at all 10 stratum boundaries (a root 2.98 over the floor read
       `🔥 Magma Glow · 240 m` in layer 39).
     * Fix: `Strata.layerAt` = `Mine.layerOfY` at the ROOT, the server's own `minerLayer`, which the old
       comment already claimed it was.
  2. **The ring and the lantern floated.** Both were drawn at `root - 3`: 1.09 and 1.00 studs over the floor
     for the server's placement, and below the floor for a seated miner. Both now sit on the floor of the
     cell. `Env.FeetBelowRoot` is gone.
  3. **A falling rock under a tunnel's roof was invisible until it hit** (§3). It is now drawn just under the
     ceiling, and the lane line runs from it. Measured: its top was 27 studs over the floor, inside the rock;
     now 5.90 under a 6-stud ceiling.
  4. **A flaky count.** `check_deepvein_cave` §5a/§5b stopped at 20:00 sharp, so a hazard launched in the last
     seconds was counted without its landing (`8 hits of 9`). They now play it out.
* **Measured rarity in ordinary play** (`check_deepvein_rarity`, new): the pace bot through the real
  client on modelled time, one hazard per 2.8-3.1 minutes (§3). The earlier measurement (8 per 20 min) was
  a miner standing beside an open cell. A tunneller in a one-cell column has nowhere to step and gets none, so
  real play needed its own number.
* **Mutation sweeps** (§8): four sweeps, 59 mutants and 6 controls. They exposed three unheld promises and a
  second flake, all closed in `check_deepvein_cave`: the ride's glide, set pieces cut, the ring's size,
  centre and lock, and a hazard carried over between sections.
* **Shot list** worked out from the real geometry:
  * the decor positions come from `Strata.decorAt` with the shipped seed;
  * the recipe starts deep with no saves through the server's own legacy restore path;
  * every depth and block was checked by running that restore on the pure modules (`Mine.column` +
    `Mine.reveal`, as `Main.server` does). That check moved three shots. The first draft's layers 36, 64
    and 148 flood natural caves deeper than the column, which would have put DESCEND in a cave and silently
    cancelled both fanfares.
  * The scratch scripts are in the session scratchpad under `dv_resume/` (`restore_scan.luau`,
    `void_sim.luau`, `cells_sim.luau`).

Files written this session:
* `deep-vein/src/shared/Strata.luau`, `CaveArt.luau` and `Config.luau`; `src/client/Cave.client.luau`;
  `tests/Strata.spec.luau`; `EYECANDY.md`, `README.md` and `CLAUDE.md`.
* `robloxemu/check_deepvein_cave.luau` and `check_deepvein_cave_budget.luau`, and the new
  `check_deepvein_rarity.luau`; the rebuilt `robloxemu/build/deep-vein.luau`.

Nothing else was written: robloxemu/emu, tools, docs, the marketing folders and the other games were not
touched (the other games were read only for the template, +1 Jump).

---

## 12. Not done / open

* **Reviewed once (§13).** The six findings are closed. The review round's own changes (the drawing, the ring,
  the drawer layout, the palettes and the fill) have been mutation-tested (§8, sweep 5) but not reviewed by a
  second independent pass.
* **Decisions for Gustav, surfaced, not taken:**
  * **(a) When the first brag comes.** The magma and its fanfare come at about 28 minutes for a normal player,
    during the third run. The core, the long-term goal, comes at about 6.4 hours in the twelfth. The owner
    gave +1 Jump a 30-45 min target for space and no number for Deep Vein; `check_deepvein_pace` asserts
    25-45 min for the magma.
  * **(b) The hazard rate.** In ordinary digging it is one per 2.8-3.1 minutes, the slow end of "2-3". The knob
    is `Config.Hazards.IntervalMin/Max` (120/180 s of mining).
* **The wall-decor layout repeats every 60 layers** (template `EnvBands.hash01`'s mixing). The kinds differ by
  stratum, so nobody will notice; noted, not changed, because the template is shared.
* **Right after an elevator ride** the client can briefly count a not-yet-built cell as open (the server's
  pump builds 64 Parts a frame). A hazard could then launch a few frames before the walls around the miner
  appear. It would still be dodgeable.
* REVIEW-4's open items are unchanged: a long fall outrunning the streamer, `StreamingEnabled` not set, and
  the slab faces.
* Not committed, not pushed, not published. Studio not opened.
* §9 in full.

---

## 13. Review round (2026-09-24): six findings, all closed

An independent adversarial reviewer read the whole strata diff and probed it in a scratch copy; it wrote
nothing in the repo. It re-ran every gate (all green, every count matching the resume session's), confirmed
the server's part budget, the hazard rarity, the rest rules and the replication, and reported six findings.
This round reproduced each finding on the unchanged build before changing anything. For each one it then
wrote the check that fails, fixed the game (never the test), mutation-tested the new checks with controls
(§8, sweep 5) and re-ran every gate (§7). All the probing ran in scratch copies.

| # | severity | finding | reproduced (before) | after |
|---|---|---|---|---|
| 1 | medium | a falling hazard was drawn through the miner's head in a side tunnel and dropped in one frame | settled R15 in a one-layer tunnel: stalactite drawn 2.10-5.90 over the floor, crystal 2.50-5.90, shard 2.30-5.99; still for 93 of 94 frames; a one-frame drop | every falling kind: bottom 5.30 while hanging (0.70 shows below the roof), falls 5.30 studs over 10-18 frames, never below the floor, still a hit |
| 2 | medium | deep stone looked like the unbreakable bedrock walls | obsidian 4.5 RGB from the bedrock at layer 142; magma and core on Basalt itself (24.1, 18.8) | closest stone 47.0 RGB (the untouched topsoil accent); no stone on Basalt; real Parts closest 48.4 |
| 3 | low | a phone drawer hid the hazard banner and the Rest button | 812x375 touch, shop open: banner on 0 of 95 hazard frames | 800x360 touch, shop open: banner on 94 of 94, Rest on 94; no overlap at any viewport with either drawer open |
| 4 | low | the shadow ring jumped with the player and stayed up if the jump spanned the lock | ring at floor + 6.09 in the air, and 6.09 after landing | ≤ 0.09 off the floor in the air and after landing |
| 5 | low | glowing decor coloured like ore | ice-blue crystals 15.7 RGB from diamond, glyphs 11.9 from gold, keystone 13.6, shard edge 40.1 from obsidian ore, lava 55.7-68 from copper and gold; also the waterfall's pool, 53.7 from diamond | worst 74.1 (floor 70), over 4012 decor/ore pairs and the 400 decorations the client really built |
| 6 | low | the underground fill light was 1.6-2.9x the server's dark preset, weakening the paid lamp | Ambient luma x1.57-2.62, OutdoorAmbient up to x1.66, exposure +0.10 to +0.25 EV | ≤ x1.19 in config, ≤ x1.21 as the real client writes it; exposure ≤ +0.10 EV |

### 1. The falling hazard, drawn where it can be seen (medium)

*Why:* the resume session drew an overhead hazard "just under the ceiling". A one-layer tunnel is 6 studs
tall and a standing R15 about 5.2, so a model 2-3.8 studs tall could only hang through the head. A hazard
launches only with an open cell beside the miner, which mostly means a side tunnel, so this was the common case.

*Fix (drawing only; the plan, the zone and the hit are the plan's):* `Strata.dropY`.
* **Hang.** The model hangs under the real ceiling if there is room, and never lower than
  `Env.HeadTopAboveFloor` (5.3) plus half its height. In a one-layer tunnel it pokes 0.7 studs out of the roof:
  a stone working loose, with its falling dust and ⚠️ marker. In a room two layers tall it hangs whole between
  the head and the roof.
* **Fall.** It passes the aim height at the plan's own moment, which is the hit, turning about the vertical
  axis only (so a relic's plate never dips through the floor).
* **Landing.** It lies still on the floor until the plan ends, instead of sinking 18 studs through it.
* **Lane.** The lane line runs from the model's tip.

*Checks:*
* `Strata.spec`: +14 assertions. The open column, a one-layer tunnel for a 2.6- and a 3.8-stud model, a
  two-layer room, a roof above the plan's height and a degenerate aim; always monotone, always on the floor.
* `check_deepvein_cave` §5e, rewritten. Each of the six falling kinds is forced in turn over the tunnel with
  the root where a real R15 settles (floor + 3.0), plus once at the server's floor + 4. The old §5e asserted
  only "centre ≥ 3.5", which the defect passed.
* On the unfixed build the new §5e failed on the bottom (3.90 < 5.3) and on the landing (−17.6).
* **A flaw in my own first draft of the check, found and fixed before it counted:** its fall counter also
  counted frames of the old model sinking through the floor, so it passed on the defect. It now counts
  only frames above the floor.

**Shot 5 changed with it** (§10): the close call is framed in a room two layers tall, where the whole
crystal hangs over the avatar.

### 2. The bedrock reads as the boundary again (medium)

*Why:* only the floor slab carries a ClickDetector; the four walls never have (REVIEW-4, asserted by
`check_deepvein`), because the near-black Basalt read as the edge of the claim. The strata put near-black
slate beside them and gave the magma and the core the bedrock's own Basalt.

*Fix:*
* **The bedrock's look is config.** `Config.Mine.BedrockColor` / `BedrockMaterial` hold the same values as
  before, and the server reads them (with a pcall: a typo costs the look, never the wall).
* **The rule** (`EnvConfig.spec`, every layer 1-312, plain and accent, both jitter extremes): no stone uses
  the bedrock's material, and every stone look stays at least `Env.MinBedrockContrast` = 45 RGB from it.
  That is more than the 38.1 two stone cells of one stratum can differ by jitter alone.
* **New rock:**
  * magma {60,42,40} Basalt → {82,52,46} Rock;
  * obsidian {36,32,46} → {64,50,92} Slate, accent {92,70,134};
  * core {46,28,26} Basalt → {110,24,20} Rock, a deep crimson.
* **An existing check caught my first core.** A first try at {96,40,30} failed
  `check_deepvein_strata`'s "the core's rock is visibly not the topsoil's" (46 apart, needs 60), so the red
  was deepened. The check was not touched.
* **Checks on real Parts.** `check_deepvein_strata` compares the stone Parts the server really built (at the
  mouth, in the core, and for a new miner parked at layer 142 in the obsidian band) with the real wall slab.
  Against the old palette it failed: 7.1 RGB, and 60 stone Parts on Basalt.
* **Not done:** a tap on a wall still does nothing, as before the strata. A client hint would need a raycast,
  which the emulator does not implement, so it could not be tested; with the look restored, the pre-strata
  state holds.

### 3. A phone drawer no longer hides the row (low)

*Fix:* the chip, the Rest button and the banner used to hide while the phone's shop or top-10 drawer was
open. They now move into the side the drawer leaves free (`rowSpan` / `placeRow` in `Cave.client`).
* A drawer is at most a quarter of the screen (`Responsive.sideWidth`), so there is always room.
* When the elevator pair splits the row on a short phone, each piece goes to the side of it that has room.
* With no drawer open, the placement is exactly the old one.

*Checks (`check_deepvein_cave` §9):*
* At all six phone-class viewports, with the shop and then the top-10 open, all three are shown and overlap
  no piece of the HUD, the open drawer included.
* The banner is at least 200 design px wide at every viewport, drawers open or shut.
* Live: a hazard inbound with the shop open on an 800x360 touch screen.

### 4. The ring stays on the floor (low)

*Fix:* `Strata.ringLayer`. While the hazard still follows the miner, the ring lies on the floor they last
stood on. Once the hazard locks, the ring stays where it is. The ceiling used for the drawing is found from
the same layer.

*Checks:*
* `Strata.spec`: +6 assertions.
* `check_deepvein_cave` §5f (new): a real-speed jump (50 studs/s, gravity 196.2, 60 fps), off the ground the
  whole way, once early in a warning and once timed to span the lock. The ring stays on the floor (the 0.09
  is its own drawing offset); the hazard still lands on a miner who came back down in it.

### 5. Glowing decor never passes for ore (low)

*Fix:* every Neon colour a decoration builder uses now comes from `Config.Env.DecorGlow`.
* **The rule** (`EnvConfig.spec`): each colour stays at least `MinDecorOreContrast` = 70 RGB (the
  ore-vs-rock floor) from every ore that can exist at any layer where that decoration can be.
* **New colours:**
  * crystals violet {214,140,255} or rose {255,120,200};
  * the ruins' glyphs and keystones turquoise {60,230,190};
  * lava redder ({255,80,20}, {255,96,24}, {255,86,22});
  * the waterfall's pool {60,140,230};
  * the obsidian shards' lit edge {230,140,255}.
* **Hazard models to match:** the relic's plate turquoise, the crystal and the shard's edge violet, the lava
  drip redder, so a hazard poking out of a roof does not read as ore either.
* **Check on what was built.** `check_deepvein_cave` §3 reads all 400 glowing decorations the real client
  built across the band sweep. Each colour must be from the palette and at least 70 from any ore within a
  layer of it. This catches a builder that hard-codes a colour past the palette (sweep 5, G2).

### 6. The lamp stays the light (low)

*The decision:* the lamp is a paid 8-level track (26 → 74 studs), and the server's preset says the head
lamp and the glowing ore are all the light. So a stratum may TINT the fill but not brighten it.

*Fix:*
* **`Env.LampFill`** quotes the server's preset. `check_deepvein_cave` asserts it IS the server's real
  Lighting, read before the client runs, so the two cannot drift apart.
* **The rule** (`EnvConfig.spec`): Ambient and OutdoorAmbient luma within 1.25x of the preset, and exposure
  within +0.1 EV, at every layer below the surface band.
* **New values:**
  * each underground band's Ambient and OutdoorAmbient scaled to at most 1.2x, keeping its hue;
  * every exposure shifted down by 0.15 EV, keeping the ladder's relative steps (the brightest, the core,
    is now −0.05);
  * the surface band (the dusk and the pithead) is unchanged.
* **Measured:** at most x1.21 as the real client writes it, at every stratum and seam.

Whether this now reads right is the one question only Studio can answer: §9 items 17 and 18.

### Files written in the review round

* **`deep-vein`:**
  * `src/shared/Strata.luau` (dropY, ringLayer);
  * `src/shared/Config.luau` (the fields above, three rock palettes, the fill, the glow palette);
  * `src/shared/CaveArt.luau` (builders take the palette; hazard models, landing and lane);
  * `src/client/Cave.client.luau` (the drawing, the ring, the drawer layout);
  * `src/server/Main.server.luau` (the bedrock's look read from Config);
  * `tests/Strata.spec.luau`, `tests/EnvConfig.spec.luau`;
  * `EYECANDY.md`, `README.md`, `CLAUDE.md`.
* **`robloxemu`:** `check_deepvein_cave.luau`, `check_deepvein_strata.luau` and the rebuilt
  `build/deep-vein.luau`.
* **Nothing else:** not robloxemu/emu, tools, docs, any marketing folder or any other game. Nothing
  committed, pushed or published; Studio not opened.
* **Scratch work** is in the session scratchpad under `dv_r5/`: the reviewer's probes re-run, the old-palette
  run, `shot5_sim.luau` and the sweep.

### Gates at the end of the round

Specs **2578 / 0**. Headless **773 / 0 + PASS**:
* walk 129
* check_deepvein 136
* check_deepvein_cave 387
* check_deepvein_cave_budget 10
* check_deepvein_cave_hud PASS
* check_deepvein_cave_join 22
* check_deepvein_pace 29
* check_deepvein_rarity 15
* check_deepvein_strata 45

All run on the real tree after the last edit. Sweep 5: 20 of 20 killed, 3 of 3 controls unnoticed (§8).
Two older races in `check_deepvein_cave` were fixed along the way (§7).

**The reviewer's own probes, re-run on the fixed build:**
* banner visible on 94 of 95 frames with the shop open (was 0; the 95th is the hit frame);
* ring 0.09 over the floor through a jump and across the lock (was 6.09);
* closest stone 47.0 from the bedrock (was 4.5);
* underground fill x1.16-1.19 (was up to x2.62).

Their ceiling probe measures the model's span down to the hit, which now includes the visible fall, so its
lower bound is no longer the hang height. §5e measures the hang and the fall separately.
