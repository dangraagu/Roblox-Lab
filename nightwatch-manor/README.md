# Nightwatch Manor — Haunted Escape Tycoon

A horror-tycoon for Roblox. Survive a procedurally laid-out haunted manor, loot its relics, then
spend them on a safehouse that makes the next night survivable.

Built from concept #2 in `docs/game-radar/2026-09-09-roblox-game-radar.md`. It is the seasonal
one: horror carries a documented 3x CCU multiplier in the September–October window, and
horror-tycoon is a sub-genre two independent scouts flagged as having almost no competition yet.

Sibling of `labyrint-spill/`, `plus1-jump/`, `grow-a-crystal/` and `anomaly-observatory/`, and it
uses the same stack: one CONFIG table, deterministic `Rng`, pure logic in `src/shared` tested from
the luau CLI with no Roblox present, and a DataStore layer with a session lock and an owner token on every write.

## The loop

**NIGHT.** The server builds a manor from a modular room kit — foyer, portrait hall, library,
dining room, nursery, cellar, chapel, servants' exit — laid out on a grid by a generator seeded in secret (below).
Relics stand on pedestals, weighted toward the deep rooms. One Nightwatcher walks a patrol route
through the doorways. It sees you inside a view cone, and only in its own room or one directly
linked to it, so walls actually hide you. Once it has seen you it comes at you along the shortest
room path until its hunt timer runs out. Take relics, reach the Servants' Exit before DREAD fills.

**You are faster than it, always.** `Watcher.speed` is capped at a fraction of
`Config.Player.WalkSpeed` — 12.5 studs/s at its worst against your 20 — so turning and running
gains you ground, and the manor is generated with circuits in it rather than as a tree of dead
ends, so running has somewhere to go. That is the whole counterplay: the Nightwatcher costs you
route and dread, not the run. It catches people who freeze, who corner themselves, or who walk
into it. The real timer is DREAD.

**DAY.** Back in your own safehouse, every upgrade is a pad on the floor with a prompt on it.
Buying a level costs relics, stacks a visible piece of hardware on the pad, and changes a number
the next night reads: how far your lantern lights, how fast the manor wakes, how fast the
Nightwatcher walks, how early the alarm bell warns you, what a relic banks for, how much you keep
when it catches you, how long you get. The manor does **not** grow with your hub level — see
Determinism.

Getting caught, or running out of night, costs you the haul you were carrying — never the night
you are on and never the safehouse. The tycoon progress is the thing you are allowed to keep.

**The nights escalate.** The manor changes as you survive. The trigger is the night you are on, nudged by dread,
never time. There are six looks: 🌙 Quiet Night → 🌫️ The Mist Rises → 🌧️ Rain on the Glass → ⛈️ Thunderstorm →
🩸 Blood Moon (night 26: the brag moment, a median of 33.5 minutes of play for the pacing model's first-time players)
→ 🕯️ The Witching Hour (night 50, the long-term goal: a median of 66.8 minutes). What changes:
* windows on the outer walls with moon, stars, mist, rain and lightning;
* portraits whose eyes follow you;
* candles that flicker harder as the night wears on;
* a safehouse that grows cosier as you upgrade it.

Ghostly hazards (bats, a will-o'-wisp, flying crockery, a wraith) come through the walls, one every 90-130 s of night
(a close call about every 2-3 minutes in the manor), each with 3 s of warning and a ring to step out of, never while
the Nightwatcher is hunting you, and never knocking you down before its lane has locked. The safehouse is the break
room: ☕ Rest by the fire, where no lightning flashes. Lightning never comes closer than 4 s apart, and Roblox's
Reduced Motion setting or the ⚡ toggle next to ☕ Rest turns every flash off, the HUD's own included. All of it is client-side and cosmetic; the server,
the chase and the economy are unchanged and measured to stay that way. **`EYECANDY.md`** has the bands, the measured hazard rarity, what rest means here, the budgets, the
gates, the Studio list and the thumbnail shot list.

**Every manor is a secret, and night N is the same size for everybody.** `Manor.plan(rng, cfg, night)` takes nothing
else, and the night alone sets the manor's size, its relics, its patrol and its dread clock, so night 14 is equally
hard for every player and "I got out of night 14" is a claim worth comparing. The LAYOUT comes from two 32-bit halves
the server draws for you (`Salt.luau`, 2^64 states), kept in `ServerStorage` and never sent to a client: one pair per
player, per night, per session. A retry after being caught is the manor you were caught in, so you learn it; after
three failures in a row there it shifts ("The manor has shifted: these are new halls"), so nobody is stuck in halls
they cannot get out of. Until 2026-10-01 the layout came from the public `WorldSeed` and the night, so any client could
compute every night's exit before entering (`docs/complete-game-standard.md` §1). The server can still plan from that
public seed when told to from Studio's command bar (`ServerStorage.NightwatchSecrets` attribute `PublicLayouts`): the
thumbnail recipe and the layout-bound checks use it.

**The NIGHTS SURVIVED board.** A board on every safehouse wall, 29 studs from the spawn pad, ranks the best night the
server credited you with surviving; ties go to whoever got there first. Its prompt (F) switches between everyone
(the top 10, read at most once a minute) and your Roblox friends (read only when you ask, up to 200, cached and
throttled), and an empty friends board says what to do about it. Names are looked up, never stored. The only way to
survive a night is the Servants' Exit, and it opens only to a character the server measures standing in the exit room
at the door, after the night has run the shortest walk there at walking speed (`Crossing.luau`). And the night has to
have been WALKED: the server samples the character every tick, and a night in which it stood outside the manor's rooms
(where the Nightwatcher cannot see it) or covered more ground than walking covers is void, with nothing banked
(`PosGuard.luau`, 2026-10-11; before that a script could wait outside and teleport to the door, a night every ~12 s).
A refusal or a void says why. What this does not stop: a script that walks the doorways like a person, and a hop
short enough to look like a lag gap (`EYECANDY.md`, "Night shift 2026-10-11").

The size rule used to be false too. The SEED was only `WorldSeed + night`, but `Manor.roomCount` folded
in the player's hub level, so the room target, the exit, the relics and the patrol all moved with
how much safehouse you had built: night 7 was a 9-room manor for a new player and a 13-room one
at hub level 12. Worse, `Upgrades.hubLevel` sums EVERY upgrade level and the exit is always the
deepest room, so every purchase in the game quietly lengthened your walk out, with nothing on
screen to say so. The hub level no longer reaches the generator at all — `Manor.plan` does not
take it — and `Manor.spec` asserts that passing it changes nothing.

## Layout

```
default.project.json        rojo: src/server -> ServerScriptService
                                  src/client -> StarterPlayerScripts
                                  src/shared -> ReplicatedStorage
src/shared/Config.luau      every tunable, one table
src/shared/Manor.luau       the layout generator + room-graph queries          (pure)
src/shared/Salt.luau        the server-only 64-bit generator every manor is planned from  (pure)
src/shared/Crossing.luau    the guard on the Servants' Exit (the shortest walk, the room)  (pure)
src/shared/Board.luau       the NIGHTS SURVIVED board's rules: encoding, ranking, caches   (pure)
src/shared/Calm.luau        "fewer flashes": Reduced Motion or the ⚡ toggle (client)
src/shared/Watcher.luau     patrol movement, sight cone, hunt state, dread     (pure)
src/shared/Upgrades.luau    costs, levels, aggregated effects                  (pure)
src/shared/Night.luau       how a night ends and what it pays                  (pure)
src/shared/Rng.luau         deterministic LCG (copied verbatim from siblings)
src/shared/Fx.luau          lighting/particle kit          (copied verbatim)
src/shared/FxClient.luau    camera + HUD juice             (copied verbatim)
src/shared/Responsive.luau  phone-first layout maths       (copied verbatim)
src/shared/EnvBands.luau    progress -> band + blend       (template, verbatim from plus1-jump)
src/shared/Rest.luau        the rest state machine          (template, verbatim)
src/shared/Hazards.luau     rare telegraphed hazards        (template + 4 additions for a manor)
src/shared/Nightfall.luau   this game's eye-candy rules: progress, windows, fairness, hazard gate  (pure)
src/shared/HauntArt.luau    builds the client's local parts (windows, portraits, props, hazards)   (client)
src/server/Main.server.luau authoritative: builds the world, runs the night, persists
src/client/Hud.client.luau  display only — it sends the server nothing
src/client/Haunt.client.luau the nights escalate: bands, lighting, windows, hazards, rest (client, cosmetic)
tests/*.spec.luau           one spec per pure module, plus Chase.spec (is it PLAYABLE) and Pacing.spec
tests/NightModel.luau       Chase.spec's night simulation + a session model, for Pacing.spec
```

Every module in `src/shared` takes its dependencies **as arguments** and requires nothing. A bare
`require("./Rng")` resolves in the luau CLI and is invalid in Roblox, and that exact mistake once
made a sibling game's server fail to load while all 119 of its unit tests stayed green. Only the
server and client scripts require, and they do it from `ReplicatedStorage` with an Instance.

## Running the tests

From this directory, with the luau CLI on hand (every gate, in order, is in `CLAUDE.md` under State; counts measured
2026-10-01, twice, identical):

```
luau tests/Manor.spec.luau        # 86 passed, 0 failed
luau tests/Watcher.spec.luau      # 87 passed, 0 failed
luau tests/Upgrades.spec.luau     # 99 passed, 0 failed
luau tests/Night.spec.luau        # 64 passed, 0 failed
luau tests/Rng.spec.luau          # 32 passed, 0 failed
luau tests/responsive.spec.luau   # 70 passed, 0 failed
luau tests/Chase.spec.luau        # 32 passed, 0 failed
luau tests/EnvBands.spec.luau     # 124 passed, 0 failed   (template)
luau tests/Rest.spec.luau         # 55 passed, 0 failed    (template)
luau tests/Hazards.spec.luau      # 147 passed, 0 failed   (template + the manor's additions)
luau tests/Nightfall.spec.luau    # 185 passed, 0 failed
luau tests/EnvConfig.spec.luau    # 244 passed, 0 failed   (the shipped numbers against every rule)
luau tests/Pacing.spec.luau       # 62 passed, 0 failed    (minutes to each band, hazard rarity, the chase)
luau tests/Salt.spec.luau         # 31 passed, 0 failed    (the server-only generator; salted manors are good manors)
luau tests/Crossing.spec.luau     # 40 passed, 0 failed    (the exit's guard: a lower bound on every legal walk)
luau tests/Board.spec.luau        # 70 passed, 0 failed    (the board's encoding, ranking, caches)
```

`Chase.spec` reports the smallest number and covers the most ground: one assertion sweeping nights
1-500 replaced sixty that each swept a single night. Read the printed measurements, not the count.

`Chase.spec.luau` is the odd one out and the important one. Every other spec asserts STRUCTURE,
and structure was never the problem: an adversarial review retuned `HuntSpeedMul` from 1.45 to
5.0 — a Nightwatcher sprinting at 55-100 studs/s at a player fixed at 16, an unavoidable death
every night — and all 390 assertions plus all 84 headless ones stayed green, because nothing in
the repo knew how fast the player was. So this file asserts OUTCOMES instead: that the watcher can
never be faster than the player at any dread, with any upgrades, under a deliberately hostile
retune; that there is a corner of the next room it cannot see; that a player ambushed in its face
and running is not caught on any of nights 1-20; that a player who IGNORES the watcher loses the
haul on a third of nights or more, so the retune did not turn the hunter into furniture; and that
crossing the manor never eats more than 40% of the night.

Its simulated player has a BODY and cannot walk through walls. The first version moved point to
point with no collision at all -- from a room corner straight to the next room's centre, which
crosses the wall rather than the ten-stud doorway `buildWall` leaves -- and the headline "never
caught on 40 of 40 nights" turned out to be a property of the bot: re-run with collision it was
caught on 5 of 40, and on 19 of 40 once the bot was two studs wide like a real character. The wall
model here mirrors `buildWall` exactly, the player is a capsule, and it slides along a wall the way
a Roblox character does. There is a CONTROL on the collision model itself, because a `blocked()`
that always answered "walkable" would silently restore the old bot and turn every assertion below
it green again on a game nobody could play.

Syntax and types:

```
luau-compile --binary src/**/*.luau
luau-analyze src/**/*.luau 2>&1     # clean after filtering Roblox global/type noise
```

(On 2026-10-01 neither tool was on hand; all 57 Luau files of this game and its checks compiled through `loadstring`,
0 errors. luau-analyze was not run.)

## Booting it headless

Unit tests cannot see the workspace. Grow a Crystal shipped with sockets that were never
parented — the whole core loop was unreachable in a published game and 166 tests stayed green —
so this game is also booted for real, outside Roblox:

```
cd ../robloxemu
py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
luau check_nightwatch.luau        # 129 passed, 0 failed
luau check_nightwatch_hud.luau    # PASS — fits every viewport checked
luau check_nightwatchmanor_board.luau              # the NIGHTS SURVIVED board, public + friends (89)
luau check_nightwatchmanor_guard.luau              # the salt stays on the server; the exit's guard (64)
luau check_nightwatchmanor_save.luau               # a save lands only while this session owns the record
luau check_nightwatchmanor_sitdrop.luau            # the Studio trace of a sit's drop
luau check_nightwatchmanor_caps.luau               # the budgets held in code
luau check_nightwatchmanor_haunt.luau              # the eye candy through the real server + client
luau check_nightwatchmanor_hazards.luau            # hazards: rarity rules, dodging, the chase gate
luau check_nightwatchmanor_join.luau               # a slow profile load
luau check_nightwatchmanor_layout.luau             # the new UI around the HUD, 10 viewports
luau check_nightwatchmanor_rest.luau               # rest is the safehouse, and only the safehouse
luau check_nightwatchmanor_budget.luau             # every budget at its worst, every frame
luau check_nightwatchmanor_fairgate.luau -a light  # (and -a hazards, -a rest) hostile configs
luau check_nightwatchmanor_flash.luau -a storm     # (and -a calm) lightning gaps, blink rates, Reduced Motion
```

(`check_nightwatchmanor_kit.luau` is their shared setup, not a check. Counts: `EYECANDY.md` §8.)

...and three more that belong to this game and live in `tests/`, because `robloxemu/` is shared and
is not ours to edit:

```
cd tests
py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
luau check_walk.luau                       # 62 passed, 0 failed
luau check_world.luau                      # 38 passed, 0 failed
luau check_boot_guard.luau -a control      # 2 passed  (it boots)
luau check_boot_guard.luau -a fraction     # 4 passed  (it refuses)
luau check_boot_guard.luau -a walkspeed    # 4 passed  (it refuses)
luau check_boot_guard.luau -a saturated    # 4 passed  (it boots, and warns)
```

`check_walk.luau` is the one that matters. It does not read the plan -- the plan is what the server
INTENDED -- it reads the parts. It recovers the room graph from the `Floor` parts and from which
shared edges have no wall across them, builds a collision model out of every solid part at torso
height (walls, bookshelves, the dining table, the pedestals, the exit slab), routes over a two-stud
lattice, walks the character by hand at `WalkSpeed`, and presses a ProximityPrompt only from inside
its real `MaxActivationDistance`. Three nights: one relic and out, a full clear, and a chase in
which the Nightwatcher's own position is sampled every tick against the walls it is supposed to be
going around. Sealing every doorway, deleting the spawn placement, or growing the dining table to
fill its room all turn it red.

`check_boot_guard.luau` patches Config's SOURCE TEXT and asks whether the server refuses to start.
It is the only thing that can catch a boot guard whose condition has been quietly turned off, which
is a mutation that survived every other assertion in this repo.

`check_nightwatch.luau` boots the real server, joins a player and plays the game: it counts the
parts that actually arrived in the workspace, buys upgrades off their pads and checks the hardware
appears, presses a stranger's finger on your pad and checks nothing is spent, walks into the manor,
takes relics off pedestals, escapes, gets caught, and checks the zone index is recycled on leave.
It also holds the line on the join: that something solid and a `SpawnLocation` exist at the world
origin before anybody joins, that the character is moved into its own zone on the SAME frame it
appears, that `plr.RespawnLocation` points at a real `SpawnLocation` inside that zone, and — by
wrapping the harness's DataStore so `UpdateAsync` takes a second — that the whole zone is standing
WHILE the profile round-trip is still in flight, with spending refused until it lands.

`check_nightwatch_hud.luau` loads the real HUD across ten viewports from 414x800 to 1920x1080 and
measures every panel — with both phone drawers **opened** first, because a drawer parked shut
passes trivially and says nothing about where it opens.

## Not built yet

See `CLAUDE.md` for the full list. The short version: no environmental puzzles, no audio, no
jumpscare beyond a screen flash, and the upgrades are stat modifiers with visible props rather than
traps that physically fire. Never opened in Studio, never published; the clip list is `MARKETING.md`.

## Paste-ready Roblox description

```
🏚️ NIGHTWATCH MANOR — Haunted Escape Tycoon 🔪
Sneak into a haunted manor, take its cursed relics and reach the Servants' Exit before the dread runs out… and before the Nightwatcher finds you! 😱

🕯️ A new manor every night, laid out in secret, bigger the deeper you go
💰 Bank glowing relics and spend them on upgrades you can see: lanterns, wardstones, bear traps, an alarm bell, a relic vault, a lockbox and floodlights
👻 The Nightwatcher hunts you through the doorways, but it is never faster than you
🌧️ The nights escalate: mist, rain on the glass, thunderstorms, a Blood Moon and a total eclipse
🦇 Ghosts come through the walls: a ring on the floor shows where, so step out of it
🏆 Climb the NIGHTS SURVIVED board in your safehouse: everyone, or just your friends
☕ Rest by the fire between nights (⚡ fewer flashes if you need it)

How many nights can YOU survive?

👍 LIKE + ⭐ FAVORITE if you made it out!
```

Rewritten 2026-10-01 against the code, as on 2026-09-30, plus what pass 2 built: the manors are planned in secret
("laid out in secret": `Salt.luau`, a server-only salt per player, night and session) and grow with the night
(`Manor.roomCount`); the NIGHTS SURVIVED board stands in every safehouse with a Public / Friends prompt
(`robloxemu/check_nightwatchmanor_board.luau`); the seven upgrades by their names in `Config.Upgrades.Catalog` (props
you can see; they change numbers, they do not fire in the manor); the Nightwatcher's speed ceiling (`Watcher.speed`,
0.65 x WalkSpeed); the six bands (the last, the Witching Hour, is the eclipse); the hazards and their ring; rest and
the ⚡ toggle in the safehouse. One currency, relics (DECIDED 2026-09-30). No promise of updates, new rooms or audio.
909 characters (Unicode code points; 919 UTF-16 units, 955 UTF-8 bytes; measured 2026-10-01), no coloured-square
emoji; the store's limit is 1000.
