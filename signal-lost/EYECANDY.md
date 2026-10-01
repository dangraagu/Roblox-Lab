# SIGNAL LOST — eye candy, hazards, rest, the brag

The owner's finish line (docs/complete-game-standard.md §2): the environment changes as the player progresses,
following the game's own logic; rare telegraphed hazards whose red ring is exactly the hit zone; a rest that is never
an exploit; budgets measured and capped in code; a brag moment in about 30-45 minutes. Modelled on
`plus1-jump/EYECANDY.md`. **Nothing here has been seen rendered.** Every number is measured headless (`robloxemu`) or
in the luau CLI, or is arithmetic marked [ARITH]; what only Studio can settle is §8.

## 1. The templates, and what was adapted

| file | source | md5 at copy | md5 now | |
|---|---|---|---|---|
| `src/shared/EnvBands.luau` + spec | `plus1-jump/src/shared` | `c6fc63a1` (spec `e2a9d464`) | same | verbatim |
| `src/shared/Hazards.luau` + spec | `plus1-jump/src/shared` | `f36a9ac2` (modified there 2026-09-30 22:48, copied 23:40; spec `2f42278c`) | `cf439641` (spec `46b22286`; REVIEW-1 changed adaptation 4) | adapted, below |
| `src/shared/Rest.luau` + spec | `plus1-jump/src/shared` | `19226cb6` (spec `4c38d41f`) | `bef9da7f` (spec `ef33afb6`) | adapted, below |
| `Responsive.luau`, `FxClient.luau` | any sibling | `8cf3ba92`, `92d83a20` | same | verbatim |
| `Rng.luau`, `MazeGen.luau` | `vault-runners/src/shared` | `217e5d06`, `c269d302` | same | verbatim |
| `Fx.luau` | anomaly-observatory (`142bf959`) | | `0f964b2e` | + `Fx.Presets.Station` |

**Hazards, adapted because the genre needs it** (the header of `Hazards.luau` lists them; DESIGN.md §5.1):
1. the clock runs only while `ctx.eligible`: a vacuum module, a band that has hazards, at least 6 s into the sector,
   AIR at least 10 s, not resting. Air modules are the safe places, and a hazard must never add to a player about to
   black out;
2. `clampLane`: a module is a 32-stud box, not open sky. A lane's start is pulled inside the module; a clamped lane is
   shorter and drifts slower, and its arrival time is unchanged, so the warning never shortens;
3. a due hazard waits up to 15 s of eligible time for the player to stand still (≤ 4 studs/s), so it comes at them from
   ahead with the ring at their feet;
4. a live hazard whose player walks into another module of the sector LOCKS its lane (it never follows anyone into
   another module) and flies on through the ring they left; it is called off only when the player leaves the sector
   (a ride, a blackout, RETURN, a new sector). REVIEW-1 finding 4: calling it off at the module edge made 111 of 112
   warnings vanish mid-telegraph on the real client path, because a player in vacuum keeps walking;
5. the first hazard of a session is due after 30 s of eligible time;
6. `checkHitStation`: zero-g debris drifts at 5-6 studs/s and is within reach long before it arrives, so with the
   template's swept test a player who stepped out of the ring TOWARD it was hit (measured: template 200 of 200, adapted
   0 of 200, `Hazards.spec`). A hit counts only from `HitLeadSeconds` (0.25 s) before arrival, and the lane is aimed at
   the ring's exact centre (`AimJitter` 0), so the ring is exactly the hit zone in every direction.

**Rest, adapted:** rest is allowed only where there is air (`AllowedIn = { hub, air }`), refused in vacuum with the
reason, never queued there. `Rest.validateStation` refuses any config that allows vacuum.

## 2. The bands

**Trigger: the sector number**, the game's own progress (you cannot stand in sector 23 without splicing 22 relays). The
band's NAME follows the integer sector, the number the HUD and the board show. The BLEND follows
`p = (k - 1) + visited / n^2`, so it creeps forward as you open modules (`visited` and `n` are public: the blend leaks
nothing). Each band blends in over the whole previous sector with EnvBands' smoothstep (`fade = 1`) and the grade
glides on a 0.6 s half-life, five half-lives inside the 3 s transit ride; the ride names the band (`SECTOR 10 — CARGO
SPINE`) with its flavour line. Foreshadowing: in the sector before a band, a module wears the next band's kit when
`hash01(k, module)` is under the next band's blend weight.

Reached = the minute of play the band's first sector is entered, p50 over 200 campaigns per model player, measured on
the REAL `Station` module by `tests/Pacing.spec.luau` (fast / medium / slow).

| # | band | sectors | reached | outside | dressing (client) | critters (harmless) | weather | hazard |
|---|---|---|---|---|---|---|---|---|
| 1 | DOCKING RING | 1-4 | 0 | the planet's day side | lockers, handrails, placards, netting, tool racks, a blue guide light | tools tumbling in vacuum modules | frost | none (the tutorial) |
| 2 | HYDROPONICS | 5-9 | 2.0 / 2.5 / 2.9 min | the sunlit limb | plant racks, magenta grow lamps, vines, seed trays, water bladders | glow moths in air modules | mist | WATER GLOBE |
| 3 | CARGO SPINE | 10-15 | 5.1 / 6.5 / 8.5 | the station's trusses | crate stacks, containers, cargo nets, ceiling rails, hazard stripes | drones on rails | dust | LOOSE CRATE |
| 4 | REACTOR RING | 16-22 | 10.9 / 14.4 / 18.9 | the terminator, a red sunset line | coolant pipes with glowing bands, heat vents, gauges, tanks | ember wisps | embers | SLAG BLOB |
| 5 | ARRAY SPINE | 23-30 | 17.7 / 22.9 / 30.2 | night side, aurora; the dish grows (scale 0.3 at sector 23 to 1.0 at 30) | antennas, cable bundles, waveform screens, racks, dishlets | satellites crossing outside | blue static | PANEL SHARD |
| 6 | THE DEEP | 31-59 | 28.5 / 36.9 / 49.3 | eclipse: a black disc ringed with light | ice sheets, frozen pools, dead screens, icicles, frost | meteors outside | ice glints | ICE CHUNK |
| 7 | THE ECHO | 60+ | 69.7 / 95.7 / 132.1 | a violet nebula, the planet gone | flickering violet panels, dark crates, residue | dark shapes OUTSIDE only | violet static | STATIC ORB |

Every band after the first lasts at least 3.1 minutes at every proxy (the shortest: Hydroponics, fast, 2.0 to 5.1).

### 2.1 Fairness rules for the art (all held by `tests/EnvConfig.spec.luau` and on real instances by `check_signallost_env`)
- Nothing covers an item or a hatch: every dressing piece hugs a wall (within 2.5 studs), keeps 4 studs off every
  doorway's line, stays out of the item square and off the consoles, mast and floor hatch.
- The four signal colours stay unique: nothing that glows comes within 30 degrees of hue of the salvage amber, the
  canister cyan, or the red and green hatch lamps.
- A palette may change hue, not how much light a surface returns: 60-100 % of the server's colour in linear light.
- Critters never collide and never approach; exterior life stays outside; no dressing drifts toward the player or copies
  its band's hazard loose. A thing coming at you is always a hazard, and a hazard always has its ring.
- The environment client fires no remote, sets no attribute, never reads ServerStorage, and creates no light source.

### 2.2 Low gravity
In a vacuum module the server sets WalkSpeed 12 (+1 per Mag-Boots rank) and JumpHeight 1.8; `Move.client` enables a
VectorForce lifting 80 % of the character's weight (asserted headless: 13.5 x 196.2 x 0.8 in vacuum, off in air). A
1.8-stud jump under 20 % gravity rises to a 9-stud apex, 1.36 s airborne, 16 studs of drift at 12 studs/s [ARITH].
How it feels is §8 item 2.

### 2.3 What the openings show (the exterior)
The only openings onto space are the lifeboat's north window (38 x 8 studs, 4 to 12 studs up) and each vacuum module's
cracked glass pane (16 x 16, 18 studs up; the Main Array's control room has a full glass ceiling). The exterior is one
client-side model (planet + atmosphere, the Main Array's dish in 8 parts, 30 relay beacons lit one per relay restored,
the brag's beam, 3 crossers) placed where those openings look (`EnvArt.LAYOUT`):
- **lifeboat:** fixed beyond the window and low, because from the benches the window shows only -1.5 to 10.4 degrees of
  elevation: the planet's limb fills the bottom of the window (centre 14 degrees below the horizon, 18 degrees of
  radius at 2 400 studs), the beacons arc just above it (6.6-7.6 degrees, 700 studs), the dish stands to the right.
- **sector:** overhead and following the character (re-placed whenever it has moved 2 studs), because a pane 13 studs
  above the eye shows only sky within about 30 degrees of the zenith: the planet 78 degrees up (22 degrees of radius),
  the dish 10 degrees off the zenith, the beacons in a ring 13 degrees around it.

**Found while writing the shot list, and fixed test-first.** The first placement put the planet 37 degrees up and the
beacons about 30 degrees up. Measured on the real instances: from both benches, which face the window, 0 % of the
window showed the planet, 0 of 30 beacons and no dish; from the spawn 3 % planet; and no vacuum module's glass ever
showed a beacon or the dish. `check_signallost_env` now casts 11 x 11 rays through the REAL window and glass parts:

| where | planet (share of the opening) | beacons seen | dish |
|---|---|---|---|
| lifeboat, bench 1 | 15 % | 30 / 30 | yes |
| lifeboat, bench 2 | 14 % | 30 / 30 | yes |
| lifeboat, the spawn | 9 % | 30 / 30 | yes |
| vacuum glass, module centre | 34 % | 30 / 30 | yes |
| vacuum glass, 6 studs off-centre (4 diagonals) | 12-26 % | 13-14 / 30 | 2 of 4 |

What the eye makes of it (scale, colour, whether a 1 800-stud ball 2 400 studs away is drawn at low graphics quality)
is §8 item 14.

## 3. Hazards

Rare, themed, telegraphed, one at a time, client-side (a hit is a shove the client applies to its own character; it
costs no AIR, salvage or progress, and the server never hears of it).

| kind | band | telegraph | commit | speed | ring radius | knock | lift |
|---|---|---|---|---|---|---|---|
| WATER GLOBE | Hydroponics | 3.2 s | 1.5 s | 5 | 3.5 | 14 | 0 |
| LOOSE CRATE | Cargo Spine | 3.0 | 1.5 | 6 | 3.7 | 18 | 1 |
| SLAG BLOB | Reactor Ring | 3.0 | 1.5 | 6 | 3.5 | 18 | 0 |
| PANEL SHARD | Array Spine | 3.0 | 1.5 | 6 | 3.7 | 20 | 1 |
| ICE CHUNK | The Deep | 3.0 | 1.5 | 6 | 3.7 | 20 | 1 |
| STATIC ORB | The Echo | 3.4 | 1.5 | 5 | 3.5 | 16 | 0 |

**Measured on the real player path** (`robloxemu/check_signallost_campaign.luau`: the real server and clients from
join to relay 30; REVIEW-1 finding 5): one warning per **2.32-3.08 minutes of play** from sector 5 on (median 2.54, 47
campaigns at bot speed 1.0 / 0.8 / 0.65; hub, rides and relay rooms included), 8-12 per campaign, the first in sector
5-11; every one finished its flight (none called off while its player stayed in the sector), nearly all as near-misses
behind a player who walked on. That needed `IntervalMin/Max` 55 / 85 s of eligible time: the spec's 80 / 120 gave one
per 2.98-4.32 min there, because only 50-57 % of that play is eligible, not the design rig's 62-65 % (M7). The pure
module (`tests/Hazards.spec.luau`): 52 hazards in an hour of eligible time, one per 68.8 s after the first; the
template's own clock: 477 in 20 h of climbing (one per 150.9 s). The first hazard of a session, through the real client in
`check_signallost_env`: on the 4th vacuum visit of one run, after 26.4 s of standing still in vacuum, in sector 5
(HYDROPONICS). Every ring is left in at most 1.5 s at the slowest modelled walk (7.8 studs/s) plus 0.5 s reaction; a
player who walks out of the ring 0.5 s after the lock dodges every kind in every direction, and a player who stands in
it is always hit (`Hazards.spec`). The HUD banner reads `LOOSE CRATE — STEP OUT OF THE RING`, then `LOOSE CRATE — YOU
ARE CLEAR`.

## 4. Rest

REST (top edge) or R / gamepad X, the lifeboat's benches (real Seats), or 20 s standing still — **only where there is
air** (the lifeboat, any air module). In vacuum it is refused: `No air here — rest where the hatch light is green.` Any
movement wakes you. It pauses exactly what the template pauses: the hazard clock, frozen, never reset. REST asked for in
air while debris still flies through a ring the player just left (up to about 5 s, REVIEW-1) is queued and said:
`Resting as soon as the debris has passed.`

**Why it is never an exploit:** nothing in the world runs out (the tank drains only in vacuum and refills in any air
module whether you rest or not); rest cannot happen where anything drains; hazards never happen where rest is allowed;
nothing is earned by time; and rest is client presentation, so a modified client that "rests" in vacuum pauses its own
hazards and nothing else while its AIR still drains on the server. The template's own probe, re-run here: hazards
counted over the same 6 h of climbing were 142 for a player who never rests, 142 for one who toggles rest every 7 s and
142 for one who rests 40 s of every 150 s (`Hazards.spec`). After `Player.Idled` the rest line warns that Roblox's
20-minute idle disconnect would keep only half of the carried salvage.

## 5. Client vs server

The server builds the structure (modules, hatches, lamps, items, masts, consoles) and owns every rule; the client
dresses and recolours it on this client only, draws the exterior, the weather, the critters and the hazards, applies
low gravity, and rests. Nothing the client does reaches a server number. Server-only state lives in a Lua table plus
`ServerStorage.SignalDebug` (never replicated); zones carry zero attributes (asserted by enumerating every attribute
under every zone against an empty list).

## 6. Budgets (caps in code, measured)

Client budgets are caps in `Config.Budget`, enforced in `Env.client` / `EnvArt` / `Dressing`, and audited on every
frame of `check_signallost_env` (7 036-7 276 frames per run: sectors 1-9 played, then bands 3-7's content in a real
sector each). Server parts are counted from the built folders by `check_signallost` M, on a 6 x 6 sector (sector 23)
opened completely by a walker with every upgrade.

| budget | cap | measured peak |
|---|---|---|
| dressing parts (client) | 300 | 71-93 over three runs. By construction at most 220: dressing stops at DressRadius 80, and no point on the 32-stud grid has more than 22 module centres within 80 studs (`EnvConfig.spec`), times 10 per module |
| dressing parts in one module | 10 | 10 |
| weather emitters | 2 | 2 |
| active emitters | 4 | 2 |
| interior critters | 3 | 2 |
| exterior parts | 45 | 44 (planet + atmosphere, dish 8, 30 beacons, beam, 3 crossers) |
| client light sources | 0 (the modules' own lights carry the scene) | 0 |
| hazards at once | 1 | 1 |
| server Parts per module | 20 (hatch leaves counted apart) | 19-20 |
| server Parts per zone | 900 | 526-574 (36 of 36 modules built) |

The render cost of eight full zones plus dressing is unmeasured: §8 item 6.

## 7. The brag and the long-term goal

**Relay 30, the Main Array.** Its relay module is a control room with a glass ceiling. Splicing it: the splice banks as
always; on the splicing player's screen the card SIGNAL SENT — `Relay 30. The Main Array is transmitting.`, a white
flash and an FOV punch, the dish swings, a beam fires, and three seconds later `…something answered.`; every player in
the server gets `★ <DisplayName> restored the MAIN ARRAY`; the board shows ★ beside every name with relays ≥ 30; the
dish's lamp stays lit; `arrayAt` is written once (`check_signallost_board` §9).

**When** (`tests/Pacing.spec.luau`, 200 campaigns per proxy on the real `Station` module): relay 30 at p10 / p50 / p90
**33.4 / 36.9 / 41.1 min** for the medium proxy, 25.7 / 28.4 / 31.3 fast, 43.8 / 49.2 / 55.5 slow. The spec asserts the
medium p50 within 30-45 minutes. The proxies are perfectly careful models, so real players will black out more (§8 item 1).

**Beyond it:** the Deep (31-59) and the Echo (60+, entered at p50 95.7 min medium); sectors never end. The curve keeps
falling with every upgrade bought (medium, all 8 ranks, P(splice) per attempt: k30 1.000, k40 0.986, k60 0.932, k80
0.861, k100 0.816, k150 0.739, `Pacing.spec`), so the board keeps separating players; the 7th and 8th upgrade ranks
land after the brag.

## 8. Needs Studio (only real rendering, input and players can settle these)

Nothing on this list is verified.

1. **Real players against the model proxies.** Time sectors 1-10 and relay 30; count blackouts per band (the model's
   are a floor). Refit the proxies, re-run `tests/Pacing.spec.luau` before touching the schedule.
2. **Low gravity.** VectorForce at 80 % of weight + JumpHeight 1.8: is the apex 9 studs and 1.36 s airborne, does the
   Humanoid walk, land and turn sanely, does it snag on hatch frames, can every salvage height (3-8 studs) be reached
   with one hop, is the gravity switch at a hatch smooth?
3. **`Fx.Presets.Station`.** Air modules readable, vacuum modules dim but readable; the red and green hatch lamps (they
   also say VACUUM / AIR in text) unmistakable on a phone, including for red-green colour-blind players.
4. **Geometry:** 8 x 10 hatches with a low-gravity hop through them; the 18-stud ceiling against a real jump; the glass.
5. **The trusted position** (1.35 x speed, 3 s burst) on real replication, including the 16 to 12 speed change at a hatch.
6. **Render cost:** up to 8 zones x 900 Parts plus client dressing; read `Stats` FPS. If too heavy, cap MaxPlayers at 6.
7. **Hazards:** a 5-6 studs/s drifting lane reads as a threat; the ring is visible in third person; the wait-for-still
   rule produces near-misses; knock 14-20 with KnockSeconds 0.6 feels like a stagger under low gravity.
8. **Phone and input:** AIR gauge and SIGNAL bars readable at 800 x 360; REST on the top edge; fabricator, RETURN and
   board prompts on touch; keyboard R and gamepad ButtonX free of engine bindings. Gamepad (REVIEW-1): the prompts show
   Y (fabricators, the board) and B (RETURN), never X (REST); both relay-console prompts are offered at once; pressing X
   beside a prompt rests and triggers nothing else.
9. **The brag sequence:** dish swing, beam, beacons, the server-wide toast; the dish growing through sectors 23-30.
10. **Friends board:** real FriendPages, `GetRequestBudgetForRequestType`, OrderedDataStore reads under load.
11. **DataStore on a published place** (an unpublished one raises on `GetDataStore`).
12. **Spawn and reset:** HubSpawn, RespawnLocation, RespawnTime 3, no ForceField; BindToClose settles 8 players in time.
13. **Glyphs:** v1 uses only ★ — … (photographed in Studio for fork-tower) and the Latin-1 middle dot ·.
14. **The exterior** (§2.3): the planet, the beacons and the dish through the lifeboat window and the vacuum glass; the
    planet's phase per band; nothing z-fighting; whether a 1 800-stud ball 2 400 studs away is drawn at every graphics
    quality level (Roblox may cull far geometry on low settings).
15. **Transit and lift rides** land cleanly with streaming off; no camera snap.
16. **Console:** zero errors and warnings across a sector, a blackout, a splice, a purchase, a return and a rejoin.
17. **Maturity questionnaire:** mild fear, no blood, no jumpscares; the Preview page is the ground truth.
18. **`Random.new()` as a stream:** NextInteger bounds inclusive and NextNumber in [0, 1), as the test adapter assumes.

## 9. Thumbnail shot list (for the night Studio session)

Every shot is **1920 x 1080**: set the Studio viewport to 16:9, capture at 1920 x 1080 or larger, scale down. Keep the
subject inside the middle 1280 px (a phone's carousel crop). *This recipe has not been tried in Studio.*

**The shots place.** `rojo build default.project.json -o Signal-shots.rbxlx` (git-ignored), open it from disk, never
publish it. *Game Settings → Security → Studio Access to API Services* **OFF**: the server cannot open its DataStore,
says so, and nothing reaches the live store or the board. Edit Config only in this place, never in `src/`.
Clean frames (command bar, Client): `local g = game.Players.LocalPlayer.PlayerGui; g.SignalHud.Enabled = false;
game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`. **Teleporting does not stage anything**: the server
moves only its own trusted position, through hatches it opened (a `PivotTo` builds and picks up nothing). Walk.

1. **"Red light"** (sector 1, honest). Every module next to sector 1's dock is vacuum and one holds the first salvage.
   Open its hatch (walk up to the red VACUUM lamp), step in, hop toward the amber piece. Camera behind and below the
   character at about 10 studs, looking up past it so the cracked ceiling glass and what it shows (§2.3) are in the top
   third and the red lamp over the doorway is in frame. HUD hidden.
2. **"Air or vacuum"** (any sector, honest). Stand in an air module facing a wall with two doorways whose lamps differ:
   red VACUUM on the left, green AIR on the right. HUD on (the AIR gauge, top right, partly drained: come in from vacuum).
3. **"The Main Array"** (sector 30). Honest route, or the shots-place edit of `ServerScriptService.Main`,
   `tryStartSector`: `local k = sess.profile.best + 1` -> `local k = 30`, plus `Config.Air.TankBase = 40`, HUD hidden.
   Walk the 6 x 6 sector to the relay (the SIGNAL meter leads); its module is the control room with a full glass
   ceiling. Camera on the floor looking up through the glass: the dish overhead (full size at sector 30) and the planet.
   A second take during the brag's 6 s: the beam.
4. **"The lifeboat"** (spawn, honest). Camera low behind a bench at about (-13, 3, -12) looking at about (0, 8, 20): the
   planet's limb in the window, the beacon arc above it, the dish to the right, the benches in the foreground. Variant:
   from (14, 6, 0) toward the RELAYS RESTORED board at (29.4, 7, 9) with the window at the left edge. With API access
   off the public board says "No relays restored yet…": frame it so the text is not the subject; never show a real
   friends list.

## 10. Gates

`CLAUDE.md` lists every gate with its command and its last result.

## 11. Mutation sweep

Run by a throwaway driver in the session scratchpad (not in the repo): each mutant is ONE exact replacement that must
match exactly once, the file's md5 is recorded before and after (so a patch that did not apply cannot pass for a
survivor), the bundle is rebuilt, every gate runs (a mutant stops at its first failing gate; the control runs them all),
and the file is restored and its md5 checked against the original. 2026-10-01.

| # | mutation | result |
|---|---|---|
| M1 | a blackout after a splice replays the spliced sector (this session's fix reverted) | KILLED — `check_signallost` L3 |
| M2 | salvage after the splice is picked up for "+0" (fix reverted) | first SURVIVED: L3 only met a leftover piece on about half the runs. L3 now leaves sector 1's pieces floating (`Bot.skipItems`) so the path runs every time; re-run: KILLED — L3 |
| M3 | leaving a sector keeps ALL carried salvage | KILLED — `Economy.spec` |
| M4 | the relay is always the first candidate (one draw, not uniform) | KILLED — `Station.spec` (chi-square 60000 against 16.3) |
| M5 | the trusted position may move 50 x faster | KILLED — `Trust.spec` |
| M6 | the relay cell written as an attribute on the zone | KILLED — `check_signallost` E (zero attributes) |
| M7 | hazards eligible in air modules | KILLED — `Air.spec` |
| M8 | the client lets a player rest in vacuum | KILLED — `check_signallost_env` D |
| M9 | ties go to whoever reached it LAST | KILLED — `Board.spec` |
| M10 | CharacterAdded writes a CFrame (the spawn-order trap) | KILLED — `check_signallost` B |
| M11 | the SIGNAL meter drops into the jump button's band | KILLED — `check_signallost_hud` (6 problems) |
| M12 | the HUD's scaled Root is not sized 1 / scale | SURVIVED — **equivalent**: every child of Root is positioned and sized in design-px offsets computed from the viewport, so Root's own size never reaches the screen, and the hudcheck measures the screen |
| M13 | the Main Array is not announced to the server | KILLED — `check_signallost_board` §9 |
| M14 | the LIFT skips a sector | KILLED — `check_signallost` E |
| M15 | settling does not close the sector (pays on every exit) | KILLED — `Economy.spec` |
| M16 | the station hit test's early return removed | SURVIVED — **equivalent**: the swept test below it already starts at `max(t0, from)`. Replaced by M16b |
| M16b | the station hit test reverts to the template's whole-flight sweep | KILLED — `Hazards.spec` (200 of 200 who step toward the debris are hit) |
| M17 | friends reads ignore the DataStore budget reserve | KILLED — `check_signallost_board` §8 |
| M18 | the State payload carries the relay cell | KILLED — `check_signallost` E (exact key set) |
| M19 | the 300-part dressing cap not enforced | SURVIVED — **equivalent**: the radius bound (22 x 10 = 220) keeps the total under it. Now asserted as that bound in `EnvConfig.spec`; M24 tests it |
| M20 | the lifeboat's planet back at 37 degrees up (the first placement) | KILLED — `check_signallost_env` (0 % of the window from bench 1) |
| M21 | the sector's beacon ring 35 degrees off the zenith | KILLED — `check_signallost_env` (8 of 30 through the glass) |
| M22 | the exterior stays anchored at the lifeboat while in a sector | KILLED — `check_signallost_env` (11 of 30 beacons) |
| M23 | RETURN works from anywhere in the sector | KILLED — `check_signallost` L4 |
| M24 | DressRadius 80 -> 130 | KILLED — `EnvConfig.spec` (the radius bound) |
| **CONTROL** | the Cargo Spine's dust one unit redder (200 -> 201) | **SURVIVED every gate**, twice (round 1; round 2 after the flake below was fixed) |

**The control caught a flaky gate.** In round 2 the control was "killed" by `check_signallost_env` F ("a hazard came").
Re-run on clean code, F failed 2 of 6 times: the section reused the Bot's module-type memory from the previous sector,
module ids repeat, and a stale "AIR" sent the shuttle to refill in a vacuum module until it blacked out. Fixed (the
section forgets the last sector); 12 of 12 runs green after, and the control then survived every gate. The killed
results above all failed on the property they mutated, not on F.

**REVIEW-1 (2026-10-01)** ran its own sweep on the review's fixes: 22 mutants and a control, every one shown in the
bundle and restored by sha256; 20 killed, two survivors equivalent (a redundant guard; a field the real path never
needs). See `REVIEW-1.md`. It also found
L3's set-up still failing 3 of 60 runs (a route through a salvage module picks the piece up despite `skipItems`) and G's
2 of 60 (a salvage module next to the dock with no doorway); both set-ups are fixed, 0 of 60 after.

## 12. Open, not done
- Audio (cut from v1, DESIGN.md §21): the biggest gap for a game about fear.
- A colour-blind symbol on hatch lamps beyond the AIR / VACUUM text, if §8 item 3 says the colours alone are not enough.
- Nothing has been rendered; §8 is the list.
