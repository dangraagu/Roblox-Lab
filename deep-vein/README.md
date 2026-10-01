# Deep Vein ⛏️ — Mining Simulator

Every dive drills through a genuinely procedural cave. Drop into your own shaft, swing at the
rock, break into voids nobody has seen before, haul the ore up, upgrade, and rebirth for a
permanent multiplier and a brand new cave.

Built from Game-Radar #3 (2026-09-09). Sibling of `labyrint-spill/`, `plus1-jump/`,
`grow-a-crystal/` and `anomaly-observatory/` — same stack: one CONFIG table, pure logic in
`src/shared` tested from the luau CLI, a server that owns every decision, a phone-first HUD.

---

## Store description

The text for the experience page (docs/complete-game-standard.md §4), checked against the game on 2026-10-01:
994 characters (the dashboard allows 1000), plain ASCII, no emoji at all (Roblox rejected coloured-square emoji,
`docs/publishing.md`). "About half an hour" is the pacing model's number, not telemetry: a normal player first
stands in the magma at 24.0-33.6 min over eight drawn caves (`tests/Pacing.spec.luau`) and at 23.6 min through the
real server (`check_deepvein_pace`). The game is not published, so there is no live text; `docs/marketing/store-text.json`
has no Deep Vein entry and is not this game's to write (it is filled by `tools/store_text.py` after publishing).

```
Your own mine shaft, and a cave nobody else has. Click a block to swing at it: stone takes a few hits, ore goes in your backpack. Break into a hidden cave and it opens all at once.

Copper near the top, then iron, gold, diamond and obsidian deeper down. When the bag is full, SURFACE + SELL takes you up and sells in one press. Spend it on a better pickaxe, a bigger bag and a wider lamp: there is no sun down here. Your tunnels are saved.

Eleven strata from the grass to the core, each with its own rock, light and wall finds. The magma comes about half an hour in, by our estimate.

Rare hazards: a rock works loose overhead, a steam vent bursts underfoot. A ring at your feet shows where. Step into the next cell and it misses; a hit only knocks you down. Press Rest to take a break.

REBIRTH at the bedrock: a permanent cash multiplier and a new cave, 72 studs deeper.

The Deepest Miners board in your mine shows Public or Friends. Ties go to whoever got there first. Nothing costs Robux.
```

---

## The loop

1. **Spawn in the mouth of your shaft** — a 7×7 open room at the surface, walled by bedrock that
   stands three cells proud of the ground so you cannot jump out of the mine.
2. **Click a block to swing at it.** Each block has hit points; your pickaxe has power. Break it
   and the faces behind it appear — including, sooner or later, a natural cave void that opens up
   all at once.
3. **Ore goes in your backpack** (copper from layer 1, iron from 3, gold from 6, diamond from 10
   and obsidian from 14 — every tier reachable, and findable in numbers, inside the rebirth-0
   depth wall at layer 24). Stone is real, minable and worth nothing.
4. **🛗 SURFACE + SELL** teleports you back to the mouth, onto an anchored deck that no
   swing can reach, and sells the haul in one press.
   **⬇️ DESCEND** drops you back to the deepest cell you have opened.
5. **Spend cash** on pickaxe tier (swing power), backpack capacity, and lamp radius — the mine
   has no sun, so the lamp is the difference between seeing a vein and walking past it.
   Spending can never cost you a rebirth: the rebirth gate is on what this run has **earned**,
   which only ever goes up.
6. **Hit the depth wall.** Below layer 24 is indestructible bedrock, and it tells you so; so does a
   click on the bedrock walls around the shaft (the edge of your claim).
   The walls and the floor are five anchored slabs rather than a grid — see *Why the box is five
   Parts*, below.
7. **♻️ REBIRTH** wipes cash, this run's earnings, haul, upgrades and this run's depth for a
   permanent cash multiplier, a wall twelve layers deeper, and **a completely new cave seed**.
   It costs a fixed fraction of the cave it is charged against — measured at 27-35% of the shaft,
   at every one of the 25 levels.

**The Deepest Miners board** (complete-game-standard §3) hangs on the south wall of your own mouth, the
wall you face when you spawn. It ranks the deepest layer each miner has ever opened (the server measures it: a
layer counts only when the server opens a cell there), survives every rebirth, and breaks ties by who got there
FIRST: the OrderedDataStore value is `layer * 2e9 + (2e9 - reachedAtUnix)`, written only when it deepens.
Walk up to it and press E (or tap) to switch between PUBLIC (the top 10, read at most once a minute) and
FRIENDS (your Roblox friends, fetched only when you ask, capped at 200 and throttled). Names are looked up
on the server and never saved. `src/shared/Board.luau` is +1 Jump's module, byte-identical;
`check_deepvein_board.luau` drives all of it through the real server and client.

---

## Why a grid of Parts and not voxel Terrain

Roblox's voxel Terrain would look better and would be untestable: the only way to ask it what is
at a point is to ask a running engine. A grid of cells answers *"what is at this cell, and what
does breaking it yield"* as arithmetic, so the whole cave — the carving, the ore gating, the
sealed box, the reveal rules — is asserted from the luau CLI before the game is ever opened.
That trade is the single biggest design decision in this game.

It is also why the cave can be SAVED. `opened` — the set of cells this player has dug out — is
the only record that any digging happened, because the generator is stateless and calls a mined
cell "rock" for ever. One bit per cell, six bits per character, and a whole rebirth-0 shaft dug
out completely fits in 336 characters of a DataStore. Without it, every cell except the centre
elevator column was standing again on the next login, ore included, and the same shaft could be
sold over and over by leaving and coming back.

---

## Why the box is five Parts

The ring and the floor are bedrock: indestructible, unclickable (bar the floor, which has to be
able to say "rebirth to go deeper"), and identical at every seed. Built cell by cell they were the
*entire* cost of a finished shaft — a fully excavated cave at the deepest wall is 10 097 Parts and
**every single one of them** is ring (10 048) or floor (49), because excavating a shaft leaves no
rock to have a face. So they are `Mine.shell`'s four wall slabs and one floor slab instead, and
10 097 becomes 5. `Mine.spec` samples every bedrock cell of the box at three rebirth counts and
requires each one to be inside a slab, and requires that no slab reaches into a cell a player can
dig.

## Why the shaft streams by depth

That leaves the rock and the ore, which a tunneller never removes: 11 960 Parts for an ordinary
dig-straight-down at the deepest wall, and 19 115 for a lattice dig, which is what a strip mine is.
So a Part exists only while its layer is within `Config.Mine.StreamLayers` (16) of the miner, and
the rest are destroyed and rebuilt from `opened` when the miner comes back. **`opened` is the cave
and none of this touches it** — the Parts were always derived from it, which is what makes the
restore possible at all, so unloading one forgets a rendering, not a dig.

16 layers is 96 studs, and that is set by the LIGHT rather than by taste: the mine has no sun and
the best lamp in the game reaches 74 studs, so nothing a player could have seen is ever missing.
The worst window anywhere in the game holds 1 124 Parts against 19 115. Full measurement, and why
this beats culling / pooling / `StreamingEnabled`, in `REVIEW-4.md`.

---

The cave is coherent **value noise** over a stateless hash of `(seed, x, y, z)`, *not* an LCG
stream like `grow-a-crystal`'s `Rng`. A stream's output depends on the order cells are drawn in,
and a player uncovers cells in whatever order they choose to dig. **Which cave is a secret**
(2026-09-30): the generator replicates, so a cave decided by `WorldSeed` and the rebirth count, as it
used to be, could be computed on any client (an ore x-ray; one memorisable map per rebirth). Each
player's cave at each rebirth now comes from a 64-bit key the server draws, saves with the profile and
never replicates (`Mine.world(cfg, rebirths, key)`, EYECANDY.md §14). Rebirth prices are analytic, so
they are the same for everybody, and every drawn cave stays inside the same payable band.

Blocks are only built where the player has actually exposed them. `Mine.reveal` floods through
open cells with 6-neighbour connectivity (what you can walk through) and collects solid faces
with 26-neighbour connectivity (what you can *see*) — the second half is why the four corner
posts of the shaft are not a diagonal gap you can look straight out of the world through.

---

## The strata: the world changes as you dig

Eleven strata, named by the layer you stand in (never by a clock). In order they are 🌱 topsoil and roots with a
timber pithead at dusk, 🪨 grey stone, ⛓️ iron veins, 🌊 an underground river, 🍄 a glowshroom grotto, 🔥 magma,
💎 a crystal geode, 🦴 fossil beds, 🏛️ lost ruins, 🌑 obsidian and 🌋 the core with its glowing floor.

* **The server** builds each stratum into the rock: the colour and material of every stone Part it already
  builds, so REVIEW-4's part budget is untouched.
* **The client** does the rest: lighting, air, grade, the set pieces, finds on the walls (waterfalls,
  glowing fungus, lavafalls, crystals, ammonites, arches, runes), bats and glowmoths, and drips, spores,
  embers and sparks.
* **Everything glides**, even on an elevator ride.
* **Rare hazards** fit the depth: a rock or crystal works loose overhead, a steam vent bursts underfoot. There
  is about one every 3 minutes of ordinary digging. Each is telegraphed by a ring at your feet and knocks you
  down if you stay in it; step into the next cell and it misses.
* **⛺ Rest** makes the cave leave you alone and can never be used to dodge anything.

Design, measurements, budgets, gates and the thumbnail shot list: **`EYECANDY.md`**. An adversarial review
(2026-09-24) found six defects in the strata, all closed test-first (EYECANDY.md §13): a falling rock drawn
through the miner's head in a tunnel, deep stone that looked like the unbreakable bedrock walls, a phone drawer
hiding the hazard banner, the shadow ring jumping with the player, glowing decor coloured like ore, and a fill
light that halved what the paid lamp is for.

---

## Layout

```
deep-vein/
  default.project.json      Rojo: src/server -> ServerScriptService,
                            src/client -> StarterPlayerScripts, src/shared -> ReplicatedStorage
  src/shared/Config.luau    EVERY tunable, one table
  src/shared/Mine.luau      the cave: hash, noise, cell contents, reveal, geometry   (pure)
  src/shared/Ore.luau       depth-keyed rarity table, values, hardness               (pure)
  src/shared/Economy.luau   shop, backpack, sale                                     (pure)
  src/shared/Prestige.luau  rebirth requirement, multiplier, apply                   (pure)
  src/shared/Fx.luau        lighting + particle kit          (verbatim from grow-a-crystal)
  src/shared/FxClient.luau  camera/HUD juice                 (verbatim from grow-a-crystal)
  src/shared/Responsive.luau phone-first layout rules        (verbatim from grow-a-crystal)
  src/shared/EnvBands.luau  progress -> band blend, smoothing (verbatim from plus1-jump)  (pure)
  src/shared/Hazards.luau   rare telegraphed hazards (plus1-jump's + vertical kinds)    (pure)
  src/shared/Rest.luau      rest rules (plus1-jump's + settle / min-awake)             (pure)
  src/shared/Strata.luau    depth, the rock look, open cells, wall decor layout        (pure)
  src/shared/CaveArt.luau   the strata's art, built in code; CLIENT ONLY
  src/shared/Board.luau     the highscore board's rules: stored value, ties, views  (verbatim from plus1-jump) (pure)
  src/server/Main.server.luau   authoritative; the ONLY file that knows Roblox exists
  src/client/Hud.client.luau    display + buttons
  src/client/Cave.client.luau   the strata, hazards and rest (cosmetic / local-only)
  src/client/Board.client.luau  draws this player's view of the board in their own mouth
  tests/*.spec.luau         one per pure module (+ EnvConfig.spec for the shipped numbers,
                            Pacing.spec for the minutes, played on tests/DigModel.luau)
  MARKETING.md              the clip list for tools/film_game.py
```

**Shared modules take their dependencies as ARGUMENTS.** A bare `require("./Ore")` resolves in
the luau CLI and is *invalid in Roblox*; only the server and client scripts require, and they do
it from `ReplicatedStorage`. This exact mistake once made a server fail to load while every unit
test stayed green.

---

## Running the tests

```
cd deep-vein
luau tests/Ore.spec.luau            # 1272 passed, 0 failed
luau tests/Mine.spec.luau           #  223 passed, 0 failed
luau tests/Economy.spec.luau        #  131 passed, 0 failed
luau tests/Prestige.spec.luau       #  295 passed, 0 failed
luau tests/Responsive.spec.luau     #   70 passed, 0 failed
luau tests/EnvBands.spec.luau       #  124 passed, 0 failed
luau tests/Hazards.spec.luau        #  140 passed, 0 failed
luau tests/Rest.spec.luau           #   76 passed, 0 failed
luau tests/Strata.spec.luau         #  103 passed, 0 failed
luau tests/EnvConfig.spec.luau      #  283 passed, 0 failed
luau tests/Board.spec.luau          #   75 passed, 0 failed   (+1 Jump's board rules, and the metric)
luau tests/Pacing.spec.luau         #   36 passed, 0 failed   (~20 s: the brag and the long-term goal)
```

Then compile and analyze every source:

```
luau-compile --binary src/**/*.luau
luau-analyze src/shared/*.luau 2>&1          # analyze writes to STDERR
```

### Booting it headless

Unit tests cannot see the workspace. `robloxemu` runs the real server and the real HUD against a
fake engine and then asks the world what actually arrived:

```
cd ../robloxemu
py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
luau check_deepvein.luau                     # 144 passed, 0 failed
luau check_deepvein_board.luau               #  92 passed, 0 failed   (public + friends, on the mouth's wall)
luau check_deepvein_cave.luau                # 589 passed, 0 failed   (the strata client, EYECANDY.md)
luau check_deepvein_cave_budget.luau         #  10 passed, 0 failed
luau check_deepvein_cave_cap.luau            #  14 passed, 0 failed   (budgets capped in code)
luau check_deepvein_cave_hud.luau            # PASS (HUD fit with the strata row, 18 viewports)
luau check_deepvein_cave_join.luau           #  22 passed, 0 failed
luau check_deepvein_cave_row.luau            #  13 passed, 0 failed   (the chip, the card and the warning)
luau check_deepvein_strata.luau              #  45 passed, 0 failed
luau check_deepvein_pace.luau                #  29 passed, 0 failed
luau check_deepvein_rarity.luau              #  15 passed, 0 failed
luau check_deepvein_secret.luau              #  27 passed, 0 failed   (the cave key never reaches a client)
luau check_deepvein_lock.luau                #  49 passed, 0 failed   (an owner token on every write)
cd ../deep-vein
luau tests/walk.luau                         # 130 passed, 0 failed
```

Two headless gates, because they answer different questions. `check_deepvein.luau` is the
emulator's: it asks the workspace what actually arrived. `tests/walk.luau` is this game's own: it
asserts the corrected geometry, injects a failure into the Part factory to prove one bad Part
cannot stop the world, leaves and rejoins to prove the cave does not grow back, rides a 120-layer
veteran up and down to prove the shaft streams, and then **plays the game** — spawn to first
rebirth, reporting swings, hauls, cash and part counts rather than assertions.

Both of them put the miner *on the block* before swinging at it, because the shaft only holds
Parts for the layers around its miner, and because `MaxActivationDistance` says the same thing
about the real game.

**Re-run `wrap.py` after every source change.** The check reads the bundle, not `src/`, and a
stale bundle cost half an hour during this build: a fix already on disk simply was not in the
artefact under test, and the dig loop looked broken when it was not.

The check joins players, digs, sells, rides the elevator, rebirths and leaves. It exists because
Grow a Crystal shipped with `part.Parent` missing from `makeSocket` — the entire core loop of a
published game unreachable, and all 166 unit tests green, because none of them could see the
workspace.

---

## What is NOT built yet

- **Never run by a person.** No Studio session, no Roblox Player. Unit tests, a headless boot and
  a mutation sweep only.
- **No experience created, nothing published.** No place ID, no gamepasses, no thumbnail, no clip
  (the shot list is `EYECANDY.md` §10, the clip list `MARKETING.md`; both are the night shift's).
- **No auto-sell, no drill, no pets, no codes, no trading.** The brief mentions auto-sell-on-
  pickup as an alternative to hauling; only hauling is built.
- **Balance is arithmetic, not play.** Expected value and swings-per-block were computed at every
  depth and the incentive gradient is right (deeper always pays more per swing, and each pickaxe
  tier is a large multiplier), but nobody has actually played it for an hour.
- **The surface deck is a ledge inside the spawn cell.** The landing point is held up by an
  anchored slab buried one stud below the floor of the cell it stands in, inset a little on X and
  Z so no face of it shares a plane with the rock around it, and non-queryable so no click can
  resolve to it. A player CAN dig the cell they spawn on; when they do, the deck is what is left
  standing and SURFACE lands on it with a 5-stud drop. That is the price of SURFACE always having
  ground; the alternative was a 148-stud drop onto bedrock every time they pressed it.
- **Balance is measured, and now walked once.** Every rebirth is priced as a fixed fraction of the
  cave it is charged against, so all 25 levels land between 2.88x and 3.54x of their own shaft
  (they used to run from 3.5x to 27x). `tests/walk.luau` played the first one: **765 swings,
  195 blocks broken, 4 surface trips, layer 24 reached, $10 016 earned against a $6 473 price.**
  That is one run of one rebirth by a bot with a crude policy; nobody has played an hour of it.
