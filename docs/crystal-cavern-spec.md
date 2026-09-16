# The cavern spec for Grow a Crystal

Three independent designs were proposed and judged; this is the one to build, with the
best ideas from the other two grafted in. The survey that preceded it is what turned up
the unparented sockets.

## Decision

**Build "The Sunken Grotto" (C)** — restructured, with the stairs, the priced lock, and the collider invariant taken from B, and the declared stand-points, symmetric reachability proof and per-feature salts taken from A.

I verified the ground truth before scoring. Confirmed by reading source: `makeSocket` (Main.server.luau:180-209) never assigns `part.Parent` — the eight `Parent` assignments in the file are at lines 30, 31, 152, 195 (the ClickDetector), 231 (the crystal, into the orphan), 408, 409, 420, and none is the socket. The live game is one pad and nothing else. Confirmed by execution (`luau.exe` against the real LCG constants) that the jitter is degenerate — all six sockets in a row draw the identical value, 8 distinct values across 48 sockets — and that the socket AABB runs z −4.3 … +72.9 against a pad ending at z 50, so chamber 5 already overhangs by 3 studs and chambers 6-7 float free. Confirmed `src/client/` touches the world only via `workspace.CurrentCamera` (3 lines), so this is a server-only change.

### Scoring

| | A Hollow | B Deepening | C Grotto |
|---|---|---|---|
| Visual payoff / part | Medium — carving 8 voids out of 12-thick walls costs 35 wall boxes before any decoration; 217 of 270 parts are dressing | Low-medium — 8 copies of one corridor; the priced bulkhead is the one great idea | **High** — 8 terraces = 8 parts (each slab's own front face is its riser); pool+shaft = 6 parts and 2 lights buys the entire thumbnail |
| Survives 20 plots | 6,360 parts, all at join | **Best** — 47 parts at 1 chamber, 242 at 8; but 8 dust emitters/plot = 160 at 20 players, uncounted | 4,520; one 56×28 **Glass** plane per plot is the worst single object in any proposal (C admits it) |
| Determinism | Strong (per-feature salts) but needs the `Rng.below` port | Weakest — one sequential stream, so inserting any decoration shifts everything downstream; also needs the port | **Best** — per-feature salts *and* draws via `rng:next()` (high bits), so **no change to Rng.luau at all** and the 56 existing Rng tests can't be disturbed |
| Testability | `stands[socketId]` is the best idea here | axis-aligned-collider invariant is the best idea here | most complete list, incl. control mutation and a "jitter is not degenerate" test that fails on today's code |
| Trap risk | **Worst** — 5-stud terrace drops reversible only via 2 ramps; its own writeup says the return-fill caught a one-way pit mid-design | **Best** — full-width 54-stud treads, 1.5 rises, nothing to fall off | Middling — 14 rotated ramps, 14 chances at bad trig, and a 2.5-stud lane it admits is the tightest number in the build |
| Fixes ch-7 overhang | Yes | Yes, structurally | Yes, structurally |
| One sitting | **No** — 26 hand-specified side-wall boxes around 8 alcove voids | Yes, cheapest | Yes once the ramps are gone |

C wins the thing that actually matters — the game's problem is that it has no cavern and no thumbnail — and every one of its weaknesses is removable for free. Removing them is the spec below.

**What was grafted, and why it costs nothing:**
- **B's full-width stepped treads replace C's 14 rotated ramps.** Deletes the trig, deletes the only rotated colliders, and makes falling impossible because there is no edge. Same part count.
- **B's axis-aligned collider invariant.** Every walkability and containment assertion becomes exact AABB arithmetic instead of an OBB approximation.
- **B's priced lock**, made safe: a locked chamber gets a non-colliding, non-querying rubble cap over its socket row plus a price on the riser face — never a wall. A's objection (a failed teardown must not strand a player) is honoured; the worst failure is cosmetic.
- **B's "empty socket plate is Neon, planted plate is Slate."** Kills C's 48 inlay parts *and* the 48 socket PointLights, at zero part cost, and keeps the HUD hint literally true.
- **A's `stands[socketId]`** — the generator declares a proven standing point per socket, so reach and line-of-sight tests assert rather than search.
- **A's lamp nubs as emitted parts**, so the pure generator is the single source of truth for where light comes from and the light count is unit-assertable.
- **Rejected from C: Glass.** SmoothPlastic T0.5 / Reflectance 0.3 is the default, not the fallback; the Neon bed under the water does the work.
- **Rejected from A: exterior cladding.** The shell is sealed, so nobody can ever see its outside. Saves 18 parts/plot.

---

# SPEC — Grow a Crystal: The Sunken Grotto

## 0. Coordinate contract (get this wrong and nothing else matters)

`CavernGen` returns **plot-LOCAL** coordinates with the plot origin at `(0,0,0)`. The server adds `(plotIndex * 80, 0, 0)` at instantiation and nowhere else. Local X is across the slice, Z is depth, Y is up.

Roblox identity CFrame looks down **−Z**. The spawn look direction is +Z, so `place()` must use an explicit two-argument `CFrame.new(pos, target)` / `CFrame.lookAt`, never `CFrame.new(pos)`.

## 1. Module and signature

New file `src/shared/CavernGen.luau` (Rojo maps `src/shared` → ReplicatedStorage; the robloxemu harness auto-registers `shared/*` as ModuleScripts).

```lua
CavernGen.build(cfg: any, plotIndex: number): Cavern
CavernGen.socketPos(cfg: any, socketId: number): Vec3          -- pure, no RNG, no plotIndex
CavernGen.spawn(cfg: any): { position: Vec3, look: Vec3 }      -- pure, no RNG, no plotIndex

type Vec3 = { x: number, y: number, z: number }

type PartDef = {
  name: string,          -- unique within the plot
  group: string,         -- "deck"|"tread"|"apron"|"shelf"|"basin"|"wall"|"ceiling"
                         -- |"water"|"glow"|"shaft"|"lamp"|"stalactite"|"boulder"
                         -- |"rubble"|"vein"|"stem"|"cap"|"lock"
  shape: string,         -- "Block" | "Cylinder" | "Ball"
  size: Vec3,
  position: Vec3,        -- LOCAL centre
  orientation: Vec3,     -- degrees; {0,0,0} = identity
  material: string,      -- "Slate"|"Rock"|"Basalt"|"Neon"|"SmoothPlastic"
  color: { r: number, g: number, b: number },   -- 0..255
  transparency: number,
  reflectance: number,
  collide: boolean,
  query: boolean,        -- CanQuery; false => can never block a ClickDetector ray
  castShadow: boolean,
  walkable: boolean,     -- top face is intended standing ground
  chamber: number,       -- -1 = always present; 0..7 = a lock cap, live only while c >= owned
  chamberLabel: number?, -- present only on decks 1..7; the chamber this riser advertises
}

type LightDef = { name: string, position: Vec3, color: {r,g,b}, brightness: number, range: number }
type DustDef  = { name: string, position: Vec3, size: Vec3, color: {r,g,b}, rate: number }

type Cavern = {
  parts:   { PartDef },   -- 149 entries
  lights:  { LightDef },  -- 10, each matching a group=="lamp" part by name
  dust:    { DustDef },   -- 2
  sockets: { Vec3 },      -- [1..48] socket-plate centres, local
  stands:  { Vec3 },      -- [1..48] declared standing point for clicking socket s
  spawn:   { position: Vec3, look: Vec3 },
  camera:  { hero: {from: Vec3, at: Vec3}, wide: {from: Vec3, at: Vec3} },
  bounds:  { minX,maxX,minY,maxY,minZ,maxZ: number },
}
```

`cfg` is passed as an argument (like `Economy`/`Growth`) so a test can feed a stub. It reads only `cfg.WorldSeed` and `cfg.Economy.{MaxChambers, SocketsPerChamber}`. The module must contain **none** of: `Vector3`, `CFrame`, `Color3`, `Enum`, `Instance`, `game`, `workspace`, `task`, `Random`. None of those exist in the luau CLI.

## 2. Constants

```
PITCH        = 13    -- Z per terrace
RISE         =  3    -- Y per terrace
HALF_W       = 32    -- interior half-width; interior x in [-32, +32]
WALL_T       =  4    -- walls occupy x in [±32, ±36]
DECK_BOTTOM  = -3    -- every deck/tread slab reaches down to y = -3
CEIL_UNDER   = 44
CEIL_TOP     = 48
G            =  8    -- chambers
```

Terrace `c` (0-based, 0..7): deck top `y = 3c`, deck spans `Z [13c, 13c+13]`.
Terrace 0 = `Z [0,13]` top 0. Terrace 7 = `Z [91,104]` top 21.

**Bounds:** x `[-36, +36]`, y `[-6, +48]`, Z `[-18, +138]`.
`|x|max = 36` against the ±38 limit → an **8-stud rock gap** between adjacent shells.

## 3. Geometry — every part, with numbers

All positions are local centres. All structural parts are `orientation = {0,0,0}`.

### 3.1 Decks — 8 parts, group `deck`
`Deck_<c>`, `c = 0..7`: size `(64, 3c+3, 13)`, position `(0, 1.5c-1.5, 13c+6.5)`, Slate, colour `(56-3c, 62-3c, 76-3c)`, collide, query, walkable, castShadow.
Each slab reaches from `y = -3` to `y = 3c`, so its exposed front face is the 3-stud riser. **No separate riser parts.**
Decks 1..7 carry `chamberLabel = c`.
- Deck_0 = `(64,3,13)` @ `(0,-1.5,6.5)`; Deck_7 = `(64,24,13)` @ `(0,9,97.5)`.

### 3.2 Stair treads — 14 parts, group `tread`
For each riser `c = 0..6`, occupying `Z [13c+9, 13c+13]` on top of deck `c`, full 64-stud width:
- `TreadA_<c>`: size `(64, 3c+4.5, 2)`, position `(0, 1.5c-0.75, 13c+10)` → top `3c+1.5`
- `TreadB_<c>`: size `(64, 3c+6, 2)`, position `(0, 1.5c, 13c+12)` → top `3c+3`

Slate, colour `(64,70,84)` (deliberately lighter than the decks so the steps read), collide, query, walkable, castShadow.
Rises: `3c → 3c+1.5 → 3c+3 → deck c+1 (flush)`. Two 1.5-stud steps, symmetric up and down, full width, **no edge anywhere**. Check c=6: TreadB top = 21 = Deck_7 top, spanning `Z [89,91]` flush against Deck_7's `Z [91,104]`.

### 3.3 Entrance apron — 1 part, group `apron`
`Apron`: size `(64, 3, 14)`, position `(0, -1.5, -7)`, top `y = 0`, Slate `(56,62,76)`, collide, query, walkable, castShadow.
Combined with Deck_0 this is 22 studs of flat ground at `y = 0` from `Z = -14` to `Z = 8`.

### 3.4 Pool shelf — 4 parts, group `shelf`; 1 part, group `basin`
All tops at `y = 21`, flush with Deck_7 — you step from terrace 8 onto the shelf with no step.
- `ShelfFront`: `(64,3,4)` @ `(0,19.5,106)`
- `ShelfBack`: `(64,3,4)` @ `(0,19.5,132)`
- `ShelfLeft`: `(4,3,22)` @ `(-30,19.5,119)`
- `ShelfRight`: `(4,3,22)` @ `(30,19.5,119)`
- `BasinFloor`: `(56,3,22)` @ `(0,17.9,119)`, top `19.4`
All Slate `(38,48,60)`, collide, query, walkable, castShadow.
Together they tile `x [-32,32] × Z [104,134]` with no gap. The shelf's inner faces (y 18→21) form the basin walls at zero extra cost.

### 3.5 Water — 3 parts
- `Water`: `(56,0.6,22)` @ `(0,20.5,119)`, top `20.8`, **SmoothPlastic**, Transparency `0.5`, Reflectance `0.3`, colour `(60,130,150)`, **collide false, query false**, walkable false, castShadow false. Group `water`.
- `GlowBed`: `(54,0.4,20)` @ `(0,19.6,119)`, resting on the basin floor, Neon `(70,190,200)`, T `0.35`, collide false, query false. Group `glow`. *This is what makes the water read as glowing rather than as a sheet of plastic.*
- Water depth is `20.8 − 19.4 = 1.4`; the lip from the basin floor to the shelf is `1.6`, under R15's 2.0 hip height, so you step out anywhere. There is no Terrain water, so the Humanoid never enters Swimming — at 1.4 studs that reads as wading. **Do not deepen it.**

### 3.6 Light shaft — 3 parts, group `shaft`
A Roblox Cylinder runs along its local X; `orientation {0,0,90}` stands it up and `size = (length, diameter, diameter)`.
- `ShaftInner`: `(24,12,12)` @ `(0,32.8,119)`, ori `(0,0,90)`, Neon `(205,230,245)`, T `0.82`
- `ShaftOuter`: `(24,24,24)` @ `(0,32.8,119)`, ori `(0,0,90)`, Neon `(180,215,240)`, T `0.93`
- `ShaftSplash`: `(0.4,26,26)` @ `(0,20.9,119)`, ori `(0,0,90)`, Neon `(170,220,235)`, T `0.7`
All collide false, query false, castShadow false. Two concentric cylinders fake a falloff one part cannot.

### 3.7 Ceiling — 4 parts, group `ceiling`
Underside `y = 44`, thickness 4, spanning `x [-36,36] × Z [-18,138]` minus a hole at `x [-14,14] × Z [112,126]` over the water:
- `CeilFront`: `(72,4,130)` @ `(0,46,47)`
- `CeilBack`: `(72,4,12)` @ `(0,46,132)`
- `CeilLeft`: `(22,4,14)` @ `(-25,46,119)`
- `CeilRight`: `(22,4,14)` @ `(25,46,119)`
Rock `(34,36,46)`, collide, query, walkable false, castShadow.

### 3.8 Sealing walls — 4 parts, group `wall`
`y [-6, 48]`:
- `WallLeft`: `(4,54,156)` @ `(-34,21,60)`
- `WallRight`: `(4,54,156)` @ `(34,21,60)`
- `WallFront`: `(72,54,4)` @ `(0,21,-16)`
- `WallBack`: `(72,54,4)` @ `(0,21,136)`
Rock `(38,40,52)`, collide, query, walkable false, castShadow.
Highest walkable point is 21; walls top at 48, i.e. 27 studs above, far beyond the ~7.2-stud jump. The shell is closed on all six sides.

### 3.9 Lamp nubs — 10 parts, group `lamp`
`(0.4,0.4,0.4)` cubes, Transparency 1, collide false, query false, castShadow false. Each has a matching `LightDef` with the same name; the server does `Fx.attachGlow(nub, colour, brightness, range)`.

| name | position | colour | brightness | range |
|---|---|---|---|---|
| `Lamp_ShaftBase` | (0, 22.5, 119) | (200,230,245) | 3.0 | 60 |
| `Lamp_PoolDeep` | (0, 19.9, 119) | (80,200,210) | 2.0 | 40 |
| `Lamp_Shroom1` | (-29, 2.5, -4) | cluster hue | 1.4 | 24 |
| `Lamp_Shroom2` | (29, 2.5, 6) | cluster hue | 1.4 | 24 |
| `Lamp_Shroom3` | (-29, 8.5, 32) | cluster hue | 1.4 | 24 |
| `Lamp_Shroom4` | (29, 14.5, 58) | cluster hue | 1.4 | 24 |
| `Lamp_Shroom5` | (-29, 20.5, 84) | cluster hue | 1.4 | 24 |
| `Lamp_VeinLow` | (-31, 10, 20) | (110,190,220) | 1.3 | 34 |
| `Lamp_VeinMid` | (31, 18, 62) | (110,190,220) | 1.3 | 34 |
| `Lamp_Entrance` | (0, 20, -11) | (255,186,120) | 1.8 | 44 |

Ten lights per plot, against 96 today. Cozy sets `ClockTime = 0` — there is no sun and no fill — so if these do not parent, the cave is **pitch black**, which is strictly worse than today's bare pad and completely silent. The emulator gate must assert the light count, not just the part count.

### 3.10 Decoration — 74 parts
All `collide = false`, `query = false`, `castShadow = false`. Seeded (§5).
- **Stalactites** (16, group `stalactite`): Blocks `(w, h, w)`, `w ∈ [1.4,2.6]`, `h ∈ [6,12]`, top at `y = 44` so centre `y = 44 - h/2`; tilt `±6°` on X and Z; `x ∈ [-30,30]`, `Z ∈ [-10,100]`. Rock `(30,32,42)`. At ClockTime 0 with all light from below they read as silhouettes; one part each is correct.
- **Boulders** (14, group `boulder`): Blocks sized `[5,14]`, rotation `±25°` on all three axes. Ten with centres 2–4 studs **inside** the side-wall faces (`|x| ∈ [29,33]`) at deck level along `Z ∈ [0,100]`; four on the pool ring. Burial depth plus free rotation is what makes an axis-agnostic box read as a rock lump with no seam.
- **Rubble** (10, group `rubble`): 1–3 stud Blocks on the apron and decks 0–2, `|x| ≤ 30`, `Z ∈ [-13,35]`.
- **Veins** (10, group `vein`): `(0.4, 1.2, L)` with `L ∈ [10,20]`, at `x = ±31.9` (0.1 proud of the wall face), `y ∈ [4,30]`, `Z ∈ [0,120]`. Neon, pale teal `(90,180,205)`, T `0.25`. Neon blooms under Cozy's threshold-0.9 Bloom, so these glow at **zero light cost**.
- **Mushrooms** (12, = 12 `stem` + 12 `cap` = 24 parts) in the five clusters at the lamp positions: stem = Cylinder `(2.5,0.9,0.9)` ori `(0,0,90)`, SmoothPlastic `(70,74,88)`; cap = **uniform** Ball `2.6` (a Roblox Ball renders as a sphere of its smallest axis — keep it uniform), Neon, T `0.15`, hue drawn per cluster from `{(90,220,210), (170,130,240), (255,190,120)}`. Cluster centres at `x = ±29` — 5 studs clear of the socket AABB edge, 3 studs clear of the wall face.

### 3.11 Chamber locks — 24 parts, group `lock`
For each `c = 0..7`, three slabs over that terrace's socket row, tagged `chamber = c`:
`Lock_<c>_<i>`, size `(20, 1.2, 7)`, position `(-16 + 16i, 3c+0.6, 13c+5)` for `i = 0,1,2`, Y-only rotation `±14°`, Rock `(26,27,34)` (near-black — a locked bed is a hole), **collide false, query false**, castShadow false.

Live only while `c >= profile.chambers`. Because they neither collide nor block a ray, the worst possible failure is a stale rock over working sockets — cosmetic. **There is no wall, plug or door anywhere in this design, so a failed teardown can never strand a player behind geometry they paid for.**

The price is a SurfaceGui on deck `c`'s exposed riser face (`Face = Front`, i.e. −Z), driven by `chamberLabel`. The server renders `"CHAMBER " .. (c+1)` when owned and `"CHAMBER " .. (c+1) .. "  ·  " .. cost .. " DUST"` with `cost = Economy.chamberCost(c, Config.Economy)` when locked. Set `SurfaceGui.MaxDistance = 60`. CavernGen never touches Economy — it emits the index, the server formats the money.

Deck 0's front face is buried against the apron (both span `y [-3,0]` at `Z = 0`), so it carries no label; with `StartChambers = 1` chamber 0 is always owned and never needs one.

### 3.12 Dust — 2 volumes, via `Fx.dustVolume` into the plot folder
- `Dust_Shaft`: size `(28,26,20)` @ `(0,32,119)`, colour `(210,235,245)`, rate 22 — motes inside the beam. This is the single most "cozy grotto" detail in the build.
- `Dust_Grotto`: size `(64,40,110)` @ `(0,20,50)`, colour `(150,200,220)`, rate 12.

These **replace** the global volume at Main.server.luau:25, which is 600×600 centred on `x = 0` and therefore covers only plots 0-3; plot 19 sits at `x = 1520` and gets no dust at all today. Delete line 25.

## 4. Socket layout

`socketId ∈ 1..48` remains the identity. `p.plants` is keyed by socketId and never stores a position; the client has zero world references. So `socketWorldPos` (Main.server.luau:167-176) is **deleted** and replaced by `CavernGen.socketPos`, with no save-format, remote-payload or HUD migration.

For socket `s`: `c = floor((s-1)/6)`, `col = (s-1) % 6`.

```
x = col*8 - 20 + jx        -- column centres -20,-12,-4,+4,+12,+20; jx in [-0.75, +0.75]
y = 3c                     -- plate centre AT the deck top: a 6x1x6 plate half-sunk, 0.5-stud lip
z = 13c + 5                -- no Z jitter
```

- **Plate AABB per chamber:** `x [-23.75, +23.75]`, `y [3c-0.5, 3c+0.5]`, `Z [13c+2, 13c+8]`.
- **Deck c:** `x [-32,+32]`, `Z [13c, 13c+13]`, top `3c`.
- **Margins:** 8.25 studs of deck to each side wall; 2 studs to the terrace front; **1 stud** to the stair band at `13c+9`. Worst case `c = 7`: plates at `Z [93,99]` inside Deck_7's `Z [91,104]`.
- Minimum centre-to-centre spacing at worst-case jitter is 6.5, so with 6-wide plates the minimum edge gap is 0.5 — plates can never overlap.

**Containment is structural, not checked after the fact:** deck `c` and socket row `c` are both generated from the same `c` and the same `PITCH`, so they cannot drift apart. Contrast today, where the pad is a hand-written literal and the sockets are a formula, and they diverged by 23 studs.

**`stands[s] = (socketX, 3c, 13c+1)`** — bare deck, one stud past the top tread, four studs in front of its own socket. Eye point is `stands[s] + (0,4.5,0)`; the segment to the socket top is ~5.7 studs long against a `MaxActivationDistance` of 32, with nothing between it and the sky.

**Z jitter is deliberately absent.** Ragged Z on a carved stone terrace reads as a mistake rather than as nature, and it would eat the 1-stud margin to the stair.

**Socket positions do not vary by `plotIndex`.** `claimPlot` takes the lowest free index and `onPlayerRemoving` frees it, so indices are recycled; a rejoining player must find their grid where muscle memory expects it. Never seed anything on `UserId`.

## 5. What is seeded, and how

Every draw uses `rng:next()` — `state / 2^32`, the **high** bits. Never `rng:int()`.

`Rng.int` is `min + (step() % span)` — the low bits — and that is exactly the bug in the shipped code: the jitter seed steps by 31 per socket, `int(-15,15)` spans 31, `A*31k` never wraps 2^32 for `k ≤ 5` and is divisible by 31, so `state % 31` is invariant within a row. I confirmed this by execution: chamber 0 draws `[-1.3, -1.3, -1.3, -1.3, -1.3, -1.3]`, and there are 8 distinct values across all 48 sockets. The "organic" look the comment promises has never existed. This is the low-bit LCG trap already written down in `docs/new-game-checklist.md` §3.

Using `next()` fixes it **without touching `Rng.luau`**, so no `Rng.below` port is needed and the 56 existing Rng tests cannot be disturbed. Helpers, inside CavernGen:

```lua
local function urange(rng, lo, hi) return lo + rng:next() * (hi - lo) end
local function upick(rng, list)  return list[math.min(#list, 1 + math.floor(rng:next() * #list))] end
```

One stream per feature group, distinct prime salt, so adding or removing a group later cannot shift another group's numbers:

```
Rng.new(cfg.WorldSeed * 7919 + plotIndex * 104729 + SALT)
  SALT: stalactites 11, boulders 13, rubble 17, mushrooms 19, veins 23, locks 29
Rng.new(cfg.WorldSeed * 7919 + 31)          -- socket jitter: NO plotIndex
```

`20260905 * 7919 ≈ 1.604e11` is exact in a double (53-bit mantissa) and `Rng.new` reduces mod 2^32.

**Identical on every plot:** all 41 structural parts, all 10 lamps, all 24 lock caps, all 48 socket positions, all 48 stands, the spawn, both cameras.
**Varies by plot:** only the `stalactite`, `boulder`, `rubble`, `vein`, `stem` and `cap` groups — silhouette, scatter, mushroom hue. Each grotto has its own rock and its own colour of glow while the gameplay grid stays byte-identical.

Parts are appended to the array in fixed program order. Never iterate with `pairs()` in a way that reaches the output.

## 6. Spawn and camera

**Spawn:** floor point `(0, 0, -6)`; HRP placed at `(0, 4, -6)`; look direction `+Z`.
The player's first frame is: terrace 0's six Neon socket plates 8 studs ahead (row front edge at `Z = 2`), seven more terraces climbing away, and 120 studs up the hall the glowing pool with the light shaft falling into it. Gameplay and postcard in one frame. Turn the camera and the entrance lamp and mushrooms fill in behind.

**Keep-out:** no part of any kind may intersect the cylinder radius 6 at `(0, *, -6)`, `y ∈ [0, 16]`.

**Committed cameras** (returned in `camera`, for a dev snap command and for the store thumbnail):
- `hero`: from `(-9, 9.5, 34)` — standing on terrace 2, off-centre — looking at `(2, 22, 116)`. Foreground: terrace 2 and 3 crystals. Midground: terraces climbing. Background: the pool glowing with the shaft in it. Stalactites silhouetted top.
- `wide`: from `(0, 25, 130)` on the pool's back strip, looking at `(0, 2, 0)`. All eight terraces descending to the dark entrance, water in the foreground. The "look what I built" shot.

## 7. Part and light budget — and the defence

| | always | max | fresh player (1 chamber) | maxed (8 chambers) |
|---|---|---|---|---|
| structure | 41 | 41 | 41 | 41 |
| lamp nubs | 10 | 10 | 10 | 10 |
| decoration | 74 | 74 | 74 | 74 |
| lock caps | 0 | 24 | 21 | 0 |
| **generated** | 125 | **149** | 146 | 125 |
| dust hosts | | 2 | 2 | 2 |
| sockets | | | 6 | 48 |
| crystals | | | 0 | ≤48 |
| **live parts** | | | **154** | **223** |
| **PointLights** | | | **10** | 10 (+ gated crystal lights) |

Of the 149, exactly **36 collide** (8 decks, 14 treads, 1 apron, 4 shelf, 1 basin, 4 ceiling, 4 wall) and exactly **28 are walkable**. All 36 colliders are axis-aligned. `castShadow == collide` for every part.

**Defence, in two currencies.** Parts are the cheap one: 4,460 anchored, script-free, ~76% `CanCollide=false` parts across 20 maxed players is a small world by Roblox standards, and Cozy's `FogEnd = 240` against 80-stud spacing means a client renders roughly five plots — about 1,100 parts in view. Lights are the scarce one: under Future lighting the engine renders a bounded number of dynamic lights near the camera and silently drops the rest, and today's build carries **96 PointLights per plot** (48 socket glows + 48 crystal glows) = 1,920 in a 20-player server. This design carries 10, and each plot is a sealed rock pocket so the camera typically has 2-4 in range. That 8-10× cut, not the part count, is the performance argument.

This is a defensible number, not a measured one — the game has never been run on a phone, or at all. Every decoration count belongs in one `cfg.Cavern` block so a low-detail pass can halve `stalactites`/`boulders`/`rubble`/`veins` without touching structure or any invariant test.

**Terrain is rejected**, as the brief suspects: it is one global voxel grid, so per-plot teardown means `FillBlock`/`ReplaceMaterial` over the slice on every join and leave; the emulator has no Terrain shim; and it cannot be expressed as the plain-table pure function the testability constraint requires. Parts only.

## 8. Server changes (all required, all in one change)

1. **`makeSocket` must set `part.Parent = plotFolder`.** This is the shipped defect. Without this line nothing else in this spec matters — the cavern will be perfect and empty, and every unit test will pass.
2. Per-plot `Folder` named `Plot_<plotIndex>` under `workspace.Plots`. **Everything** goes in it: cavern parts, lamp nubs, dust hosts, socket plates, crystals.
3. Instantiation loop (~30 lines): for each PartDef where `chamber == -1 or chamber >= p.chambers`, create `Part` (set `.Shape` for Cylinder/Ball), `Anchored = true`, `Size`, `CFrame = CFrame.new(origin + pos) * CFrame.Angles(rad(rx), rad(ry), rad(rz))`, Material, Color, Transparency, Reflectance, CanCollide, CanQuery, `CanTouch = false`, CastShadow, Name, `SetAttribute("Chamber", chamber)`, `Parent = folder`. **Count what you parent and `assert` it against `#cav.parts` filtered.**
4. **Build order, and it matters:** the 36 colliders synchronously first (so a spawn that fires early cannot drop the player through the world), then the sockets, then decoration + lamps + dust with a `task.wait()` every ~30 parts. A 20-player server filling at once otherwise instantiates ~3,000 parts in one burst.
5. Delete the pad (`Pad_<UserId>`, lines 415-420) and `socketWorldPos` (167-176). Delete the global `Fx.dustVolume` at line 25.
6. `place()` reads `CavernGen.spawn` and uses `CFrame.new(pos, pos + look)`.
7. `makeSocket`: **remove `Fx.attachGlow`**; an empty plate is `Material = Neon`, `Color = (58,104,132)`, `Transparency = 0.35`. This keeps the HUD hint "Click a glowing socket to PLANT" literally true at 1 part and **0 lights**, instead of 48 lights.
8. `refreshSocketVisual`: on plant, set the plate to `Material = Slate`, `Color = (52,56,70)` so the crystal is the bright thing; on harvest, restore Neon. **Gate `Fx.attachGlow(c, …)` on `prog >= 1 and plant.tier >= 3`** — growing crystals are Neon under a threshold-0.9 Bloom and glow fine unlit, and the light becomes the "ready, and it's a rare one" tell. Without this gate the 10-light budget is a lie.
9. `refreshSocketVisual`: give the Crystal its **own** `ClickDetector` (`MaxActivationDistance = 32`) wired to the same handler. A ClickDetector parented to a BasePart only activates from that part's own surface, so today the HUD's "click a grown crystal to HARVEST" is already false.
10. `Buy` handler, `kind == "chamber"`: after `buildChambers`, destroy every descendant of the plot folder whose `Chamber` attribute equals the newly-owned index.
11. `onPlayerRemoving`: destroy the plot folder **first**, then free `usedPlots[idx]`, so a join in the same frame cannot collide with a name that is still taken. Teardown becomes one `:Destroy()` instead of walking a Lua table plus a name lookup — and nothing can leak, which today it does (nothing but sockets and the pad is ever cleaned up).

## 9. Test plan — every item written so it can fail

Unit tests in `tests/CavernGen.spec.luau`, in the existing house style (hand-rolled `eq`/`truthy`, `passed`/`failed` counters, `require("../src/shared/CavernGen")`). Run with the luau CLI at `C:/Users/bahs_admin/.../scratchpad/luau/luau.exe` — use the long path form; the 8.3 short path `BAHS_A~1` breaks relative requires with `could not reset to requiring context`, and `require` accepts only `./` or `../` prefixes.

1. **Socket containment.** For all 48 sockets at **both** jitter extremes, the 6×1×6 plate AABB is strictly inside exactly one `walkable` part whose top `y` equals the socket centre `y`, with ≥ 0.5 stud of margin on all four sides, and ≥ 1 stud clear of that terrace's stair band. *Fails today for sockets 31-48.*
2. **Slice containment.** For every part, the orientation-aware half-extent (`|R|·s`) satisfies `|position.x| + halfExtentX <= 38`, and `bounds` matches the computed union. Include a deliberately failing fixture part at `x = 39` to prove the OBB→AABB maths fires rather than passing vacuously.
3. **Axis-aligned collider invariant.** Every part with `collide == true` has `orientation == {0,0,0}`, and there are exactly 36 of them. This is what makes tests 4-7 exact arithmetic rather than approximation.
4. **Walkability, one component, symmetric.** Rasterise the 28 walkable tops onto a 1-stud grid (`x [-32,32] × Z [-14,134]`), 4-connect with a **symmetric** rule `|dy| <= 2.0`, flood-fill from the spawn cell, and assert all 48 `stands` cells and every terrace, the apron, all four shelf strips and the basin floor are in that one component. Because the rule is symmetric, one fill proves both "can reach every socket" and "can never be trapped". *Control: raise one tread to a 3-stud rise; the test must go red.*
5. **No fall-out.** No walkable cell is 4-adjacent to a cell outside the walkable set unless that direction is backed by a `collide` part whose top is ≥ 8 studs above the cell (jump height 7.2). Separately: the union of colliders forms a closed shell — no ray axis-aligned from any walkable cell escapes `bounds`.
6. **Water safety.** `BasinFloor` top is ≤ 1.9 below every shelf top bordering it (actual 1.6), and the basin's XZ footprint is fully ringed by walkable shelf parts with no gap.
7. **Stair continuity.** Every consecutive rise on every riser is exactly 1.5; each tread spans the full 64-stud interior width; `TreadB_<c>` top equals `Deck_<c+1>` top; each tread's slab bottom is `-3` (no crawlspace).
8. **Query invariant.** Every part whose group is not in `{deck, tread, apron, shelf, basin, wall, ceiling}` has `query == false`. This is what structurally prevents any future decoration from silently killing a ClickDetector.
9. **Line of sight.** For each socket, the segment from `stands[s] + (0,4.5,0)` to the socket top centre intersects no `query == true` part other than that socket. Segment-vs-AABB. *Control: set one stalactite `query = true` and drop it into a doorway line; the test must detect it.*
10. **Crystal headroom.** For every socket, no `collide` part occupies `(x ± 1, y .. y+7, z ± 1)`. A mature crystal is 6 studs tall from the plate centre; 7 gives margin. Actual worst case is 17 studs clear under the ceiling.
11. **Character headroom.** For every reachable walk cell, no `collide` part occupies `y+0.2 .. y+6`.
12. **Spawn safety.** A walkable top exists directly under the spawn at `y = 0`, and the keep-out cylinder (r 6, `y ∈ [0,16]` at `(0,*,-6)`) intersects **no** part of any group.
13. **Lock coverage and safety.** For every chamber `c`, the three `Lock_<c>_*` slabs cover ≥ 80% of that socket row's XZ footprint; all 24 have `collide == false` and `query == false`; decks 1..7 each carry `chamberLabel == c` and deck 0 carries none.
14. **Budget.** `#parts == 149`; `#lights == 10`; `#dust == 2`; colliders `== 36`; walkable `== 28`; `castShadow == collide` for every part; every `LightDef` name has a matching `group == "lamp"` part at the same position.
15. **Determinism, in-process.** `build(cfg, 3)` twice deep-equals; a canonical serialisation (fixed field order, numbers at `%.4f`) hashes identically.
16. **Determinism, cross-process.** A second luau CLI invocation printing that serialisation produces byte-identical stdout to a recorded golden. Commit the golden.
17. **Plot invariance.** `build(cfg,0)`, `build(cfg,7)` and `build(cfg,19)` are element-wise identical in every group except `stalactite|boulder|rubble|vein|stem|cap`, with **no translation applied** (coordinates are local), and all 48 socket positions and 48 stands are identical across the three. Assert at least 8 decoration parts genuinely differ, so the variation is not accidentally switched off.
18. **Jitter is not degenerate.** The six sockets in any one chamber have six distinct `jx` values, and there are ≥ 40 distinct values across all 48. *Fails against today's generator, which produces 6 identical values per row and 8 distinct across 48.*
19. **No Roblox globals.** `luau-analyze` clean, plus a source scan of `CavernGen.luau` asserting it contains none of `Vector3 CFrame Color3 Enum Instance game workspace task Random`.
20. **Control mutation.** One edit the suite must **not** notice — change a boulder's colour by 2 RGB — and confirm everything still passes. Then mutate every guard the suite claims: shift one socket 1 stud past its deck edge (kills 1), delete `TreadA_3` (kills 4), set a stalactite `query = true` over a socket (kills 8 and 9), swap `next()` for `int()` in the jitter (kills 18), rotate a wall 5° (kills 3). Each must kill at least one **named** test. A sweep where everything dies is a broken harness, not a strong one.

### 21. Emulator gate — mandatory, and the only test that can see the live defect

Rebuild the bundle (`py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau`), boot the real server through `robloxemu`, join one player, advance the clock, then walk `h.workspace` and assert:
- `workspace.Plots.Plot_0` exists, and no part named `Pad_*` exists anywhere.
- Its BasePart descendant count is exactly **154** for a 1-chamber player (125 always + 21 caps + 2 dust hosts + 6 sockets).
- Parts `Socket_<uid>_1` … `Socket_<uid>_6` are present with a `Parent` chain reaching `workspace`.
- PointLight count under `Plot_0` is exactly **10**.
- `check_crystal.luau` still passes (HUD fit).

Today's build fails every one of these: the workspace after one join is `FxDustVolume`, `Plots`, `Pad_12345` — four descendants, zero `Socket_*`. An unparented part throws nothing, logs nothing, and passes any test that only inspects a returned table. This gate is not polish.

---

## 10. What this design does NOT do

State these plainly so nobody later files them as bugs.

1. **Players never see each other.** Each plot is a sealed rock pocket. Today's floating pads allowed cross-plot sightlines by accident; this removes that deliberately. A shared lobby with portals is a separate build, not a tweak.
2. **No Terrain, no smoothing, no destructible rock.** Every surface is a box. The cave reads as hewn, not eroded.
3. **No structural variety between plots.** Plot 3 and plot 17 have identical decks, stairs, pool, walls, spawn and all 48 socket positions. Only rock and flora vary. This is required, because `claimPlot` recycles indices and a rejoining player must not find their saved plants in a differently shaped room.
4. **Nothing outside the shell is dressed.** No exterior cladding, because a sealed cavern means no player can ever look at it. If a spectator or free-cam mode is ever added, ~14 cladding boulders per plot become necessary.
5. **No per-socket lighting.** An empty socket is a dim Neon plate, not a lit one. If that reads flat in-game, the fix is rewording the onboarding hint, not restoring 48 PointLights per plot.
6. **Unowned chambers are not gated.** You can walk to terrace 8 and stand at the pool on day one. The lock is rubble and a price tag, never a wall — which is precisely why a failed teardown cannot strand anyone.
7. **No save-format, remote-payload, HUD or client change.** Server-only. A player logged in across the update simply finds their crystals in a new room.
8. **It does not fix the 5-second refresh loop.** The cavern is static so it does not join that churn, but the loop still destroys and rebuilds every crystal Part, PointLight and sparkle emitter every 5 seconds — up to 960 rebuilds per tick at 20 maxed players. Unchanged, and out of scope.
9. **It does not stream.** `StreamingEnabled` is off, so all 20 plots replicate to every client. Sized for the stated 20 players; 40 would need streaming or a halved decoration block, and nothing in the code enforces the cap.
10. **It has never been run in Roblox.** Every number here is proven by arithmetic and by the headless emulator. Four things are engine behaviours the pure tests are structurally blind to and that must be checked in Studio or a real client before this is called done: that a 1.5-stud tread is walked over by the default R15 humanoid in both directions; that `CanQuery = false` really does stop a ClickDetector's mouse raycast (the whole decoration strategy leans on it); that a Humanoid wading 1.4 studs in a non-Terrain slab reads as wading and not as a bug; and the actual frame cost of ~4,460 parts and 200 lights on a phone.
11. **Rebuilding the world does not by itself fix the Reddit complaint.** "i cant even place a seed" was caused by the unparented sockets, not by the free-starter-seeds gap that commit `3375197` addressed. The cavern and §8.1 must ship together, and the play-through gate in `MARKETING.md` still has to actually happen.
