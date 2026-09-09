# Fork Tower - adversarial review

**Verdict: BLOCK** — all six findings CLOSED 2026-09-10; see the Resolution at the
bottom of this file for what changed, and for the gaps that are still open.

Built and reviewed 2026-09-09/10. NOT published, and not to be published until the
findings below are closed. Every one of them was proved by running something, not by
reading - the proof is quoted with each.

## Findings (6)

### 1. A lane's X position is an unbounded random walk. Each section's exit X becomes the next floor's fork origin, so ten floors of left/right steps accumulate with nothing clamping them to the lane's own 220-stud slot. Adjacent players' towers physically interpenetrate.

**Where:** `D:/Claude/Roblox/fork-tower/src/server/Main.server.luau — buildSection's `lane.forkTop[level + 1] = base + Vector3.new(sec.exit.dx, ...)` fed forward into buildFork, with Config.World.LaneSpacing = 220`

**What it costs a player:** A player jumping inside their own tower can be blocked by, or land on, a stranger's platform; a stranger's floor 8 can sit inside your summit pad. It looks like the game is broken and it is not recoverable by anything the player can do. Worst measured reach is 379.5 studs — nearly two whole lanes over.

**Proof:** Replicated the server's exact forkTop chain in luau over 5000 run seeds x 4 play strategies: 29.4% of reader runs and 46.7% of trap-taking runs put geometry past +/-110 studs (half of LaneSpacing) from their own lane centre. Then confirmed it in the BUILT world: robloxemu, two players seeded to run 39, one playing safe and one playing traps, driven to the summit -> `Lane_0 SummitPad@(100.0,308.0,861.2) <-> Lane_1 Plat_8_4@(111.0,309.5,868.5)`, 2 intersecting solid-part pairs; Lane_0 spans X [-24.0, 115.0] and Lane_1 spans [68.0, 233.0], 47 studs of overlap. Mutating LaneSpacing 220 -> 20 SURVIVED all six suites and the headless check.

### 2. When all 24 lanes are taken claimLane returns index 0 without marking failure, so the 25th+ player gets a tower built at the exact coordinates of player 1's. teardownLane then frees that index on departure even though the original owner still occupies it, so the collision persists and spreads.

**Where:** `D:/Claude/Roblox/fork-tower/src/server/Main.server.luau — claimLane() `return 0` fallback and teardownLane()'s `laneTaken[lane.index] = nil`; Config.World.MaxLanes = 24`

**What it costs a player:** The 25th player onward plays inside two or three other players' towers — overlapping fork pads, doors and platforms. Nothing in the repo couples MaxLanes to the place's max-player count (default.project.json has no Workspace or place-config entry at all), so this is one Studio slider away from being live.

**Proof:** robloxemu: joined 27 players -> `DUPLICATE lane folders (two towers at the SAME world position): Lane_0 x4` — four complete towers at identical coordinates, zero server errors, nothing warned. Then had one overflow player leave and a new one join: still `Lane_0 x4`, confirming the freed-index cascade. Mutation MaxLanes 24 -> 1 SURVIVED all six suites and the headless check.

### 3. The checkpoint a hazard platform hands you is inside that hazard's footprint. Hitting a hazard teleports you onto the hazard, with no debounce and no grace window.

**Where:** `D:/Claude/Roblox/fork-tower/src/server/Main.server.luau — buildSection: platform Touched sets `lane.checkpoint = pos + Vector3.new(0, Config.World.RespawnLift, 0)` where pos is the platform CENTRE; hazard Touched teleports to exactly that point`

**What it costs a player:** Every player meets this on every floor from 2 upward — 36 hazards in a full ten-floor trap run. Best case the player jitters and fights their way out; worst case they are pinned at the checkpoint. Touched also fires repeatedly, and each fire sends a Notice RemoteEvent, so it is a client remote-spam loop as well. Section.check validates the LANDING BAND on the platform but never checks the checkpoint against the hazard, and no test puts a character anywhere.

**Proof:** robloxemu, full ten-floor trap run on seed 4, measured every hazard in the built world against the checkpoint its own platform hands the player: all 36 hazards sit exactly 1.50 studs horizontally from the checkpoint XZ, and the checkpoint's HRP Y equals the hazard's top Y (62.90 vs a hazard occupying Y [59.90, 62.90]). A Roblox character is 4 studs wide (half-width 2 > 1.50) and hangs ~3 studs below the HRP, so it arrives overlapping the block in both axes.

### 4. No throttle, no cooldown, no server-side confirmation. Each fire runs a full teardown + buildLane + saveProfile, and saveProfile is a DataStore UpdateAsync. The confirm-twice guard lives entirely in Hud.client.luau.

**Where:** `D:/Claude/Roblox/fork-tower/src/server/Main.server.luau — RebirthEvent.OnServerEvent`

**What it costs a player:** One client empties the whole server's DataStore write budget (60 + 10 per player per minute) in well under a second. That starves every other player's autosave AND the 45-second session-lock refresh, so other players stop saving silently and can be flipped to read-only mid-session. 200 Fork.plan calls plus 200 world rebuilds in one frame is also a server-wide hitch.

**Proof:** robloxemu: wrapped store.UpdateAsync to count calls, then fired `Rebirth:simulateFireServer(P)` 200 times back-to-back in a single frame -> `server DataStore UpdateAsync calls caused: 200`, `rebirths leaderstat now: 200`, `lane folders left in workspace: 1`, `server errors: 0`. Nothing refused, nothing slowed it down.

### 5. The irreversible half of answering a fork — `p.stage = "climb"`, buildSection, and disabling both ProximityPrompts — runs unconditionally BEFORE that guard, while the checkpoint move that makes the section reachable sits inside it. If plr.Character or its HumanoidRootPart is absent at that instant, the floor is spent and the checkpoint is still the fork pad.

**Where:** `D:/Claude/Roblox/fork-tower/src/server/Main.server.luau — onDoorChosen: `if first and hrp then ... lane.checkpoint = target end``

**What it costs a player:** Reset your character during the 0.35s prompt hold, or in the trigger's network round trip, and you are standing on a spent fork pad with both doors dead and your own section out of reach. The only in-game exit is Rebirth, which wipes the entire run. Rejoining the server does silently recover it (buildLane's mid-climb branch recomputes the checkpoint) but nothing tells the player that. It is one line in the wrong scope.

**Proof:** robloxemu: joined a player, deliberately did NOT simulateSpawn (Character nil, exactly the state between a Reset and the next CharacterAdded), fired floor 1's door prompt -> `section built while character absent: true`, `fork-1 prompts still answerable: 0`. Then spawned the character: the server placed it at (0.0, 4.0, 14.0), the fork pad. Platform 1 sits at (0.0, 2.9, 42.0) — 13.50 studs edge-to-edge against a traitless running jump of 8.67 studs (16 * 2*sqrt(2*7.2/196.2)). `>>> UNREACHABLE`.

### 6. The 47-test fairness spec that the README calls the enforcement of promise #2 cannot see an unreadable fork. Fork.readTrap reads the markedDoor FIELD, so the spec compares a field against a field; it never asserts the property the promise actually is — that exactly one of the two doors bears the sign the inscription names.

**Where:** `D:/Claude/Roblox/fork-tower/tests/Fork.spec.luau — lines 194 and 496, `if Fork.readTrap(floor) ~= floor.trapDoor``

**What it costs a player:** Not a defect in the shipping code: Fork.luau is correct today. But the guard on the game's core promise is one end-to-end file, not the spec that claims to hold it. Any future edit to the sign construction — the exact area that already cost three red rounds during the build — is unprotected by the 40 000-fork spec.

**Proof:** Mutated src/shared/Fork.luau so the tell is no longer restricted to signs the marked door holds exclusively (both doors may then bear it, making the fork a genuine coin flip). All six suites stayed green, including `Fork: 47 passed, 0 failed`. Only check_forktower.luau, which derives the marked door from the `Marked` attribute the way a player reads the doors, caught it: `fork tower: 34 passed, 24 failed`.

## What the review could NOT break (10)

- Every claimed test count reproduces exactly: Fork 47/0, Section 32/0, Build 31/0, Codes 19/0, Rng 32/0, responsive 70/0, and the rebuilt bundle gives `fork tower: 50 passed, 0 failed`. luau-compile --binary is clean on all 11 sources; luau-analyze 2>&1 produces nothing but Roblox-global/type noise after filtering (Enum, Color3, Instance, Vector3, UDim2, BasePart, IntValue ...) — no real finding left.
- ATTACK 1, unparented Instances: clean. Scanned every Instance.new in all 11 sources and traced each variable to a .Parent assignment — none missing. The server routes all of them through `make(className, parent, props)` which takes the parent positionally and asserts it non-nil before creating anything; Fx.luau parents each PointLight/ParticleEmitter/Attachment/Trail/dust host explicitly; FxClient's or-Instance.new idiom assigns .Parent on the next line; and every one of the HUD's 35 creations chains up to `gui.Parent = player:WaitForChild("PlayerGui")`. The defect that shipped in grow-a-crystal is genuinely not here.
- ATTACK 2, path requires: clean. No `require("./X")` anywhere in src/. Both scripts require only from ReplicatedStorage:WaitForChild, every shared module takes Rng/cfg as arguments, and only tests/ uses relative requires.
- ATTACK 3, DataStore: clean. Both GetDataStore and GetOrderedDataStore go through `tryStore(fn, what)`, which pcalls, warns "the game runs, progress will NOT be saved this session", and returns nil; every write path checks `store`/`orderedLB` first. The server survives an unpublished place.
- ATTACK 4, mutations that SHOULD be caught: 5 applied to the real source, 5 killed. (1) tell no longer exclusive to the marked door -> headless 34/24; (2) penalty section made steeper by +0.5 rise -> Section.spec 30/2 + headless 49/1; (3) the cross-lane owner guard `if plr ~= owner then return end` disabled -> headless 48/2; (4) liar mechanic killed via `markedDoor = trapDoor` -> Fork.spec 42/5 + headless 46/4; (5) immediate reversal allowed by deleting both the redraw loop AND the forward fallback -> Section.spec 31/1. All files restored; `diff -r` against the pre-mutation backup reports src and tests byte-identical, and the full suite plus headless is green again.
- THE HUD GATE THE README SAYS WAS NEVER RUN — I RAN IT, AND IT PASSES. Wrote a runner for robloxemu/emu/hudcheck.luau against fork-tower with a warmup that fires real State / Reveal / Leaderboard / Notice payloads, with the reveal card built by calling the real Build.reveal on a ten-pick run so the shape cannot drift. Result: PASS on all ten viewports (800x360, 640x300, 414x800, 800x600, 1024x768, 1366x768 mouse and touch, 1920x1080, and the two flag-flip pairs). Panels cover 9.0%-30.1%, no interactive control under 44 screen px, nothing in the thumbstick or jump-button band. Caveat the gate itself reports: three ScrollingFrames (Stats, List, CardTraits) use AutomaticCanvasSize and are listed NOT VERIFIED rather than passed, so "can you scroll to the last of your ten picks" is still unmeasured.
- The two fairness promises hold in the code as written. The tell is constructed only from signs exclusive to the marked door, so exactly one door bears it; the inscription's inverted line is stated on the pad and mirrored in the door attributes; trait totals are clamped UPWARD to BaseJump/WalkSpeed so no build can fall outside Section.spec's traitless clearability proof; and the penalty adds platforms and hazards after the clamp while step and gap are byte-identical.
- The section walk cannot repeat an XZ cell — z is non-decreasing and only fwd changes it, so returning to an earlier x with z unchanged would require the reversal the generator forbids. No platform can sit directly over a jump.
- Every item on the builder's own notDone list checks out: Config.Passes is read by nothing (profile.passes appears exactly twice, both in load and save), there is not one Sound/SoundService reference in src/, and hz.kind is written to an attribute and never rendered — all four hazard kinds are the same red neon cube.
- The cross-lane door guard is real and correctly ordered: onDoorChosen compares the prompt's captured lane owner against the puller BEFORE reading any profile, so a prompt fired in someone else's tower advances nobody. Confirmed by mutation (disabling it turns the headless check red).


---

# Resolution — 2026-09-10

All six findings closed. Every fix was driven by an assertion that was watched to FAIL first, and
every new guard was then mutated to prove it bites. The suites now read:

```
Fork 53/0   Section 47/0   Build 31/0   Codes 19/0   Rng 32/0   responsive 70/0
check_forktower.luau 85/0
```

**Still not published.** The findings are closed; the game has still never been opened in Studio
and no human has ever played it. See "What is still not good enough" at the bottom.

## What changed, per finding

**1 — unbounded X random walk.** Fixed in the MODEL, not by widening the lane. `Section.build`
now takes `originX` (the section origin's offset from its lane's centre line) and refuses any step
that would leave `Config.World.CorridorHalfWidth` = 60 studs; the fallback is FORWARD, which has
`dx = 0`, so the exit is inside the corridor too and the bound holds by induction over any number
of floors. `Section.check` re-derives it. `buildSection` passes
`lane.forkTop[level].X - lane.origin.X`, and the boot guard now chains the tower the way the
server does instead of checking ten independent sections.

*Red first:* `no platform of 500 chained floors leaves the corridor (worst 2544.8 at seed 8 floor
500, bound 60)`, and in the world `no tower reaches outside its own 220-stud lane slot (worst
152.0 studs, Lane_3)` plus `no two towers overlap in X (Lane_2/Lane_3)`.

Lanes also alternate around the origin now (0, +220, -220, +440 ...) rather than marching out
along +X, halving how far a full server's furthest tower sits from spawn.

**2 — claimLane returned 0 when full.** It returns `nil` now, and the pool is
`math.max(Config.World.MaxLanes, Players.MaxPlayers)` — MaxLanes is a floor, so a Studio slider
can no longer put more players in the server than there are towers. A player the server genuinely
cannot seat is refused out loud (`notice(..., "full", ...)`, repeated on CharacterAdded because the
first one goes out before their HUD can have connected) and stands on a new `workspace.Waiting`
pad carrying the place's only ENABLED SpawnLocation — every lane spawn is `Enabled = false`, and a
world whose spawns are all disabled drops the character wherever Roblox likes.

*Red first:* `no two towers share a lane index (Lane_0,Lane_0,Lane_0,Lane_0,Lane_0,Lane_0,Lane_0,
Lane_0,Lane_0,Lane_0) -> got 10, want 0`.

**3 — checkpoint inside the hazard.** A platform's centre is exactly where a hazard standing on it
is (near face 1.50 studs out, against a 2.0-stud character half-width): 7200 of 7200 hazards
overlapped the checkpoint their own platform handed back. `Section.respawn(section, index)` names
the point now — the clear band on the far side, as far in as the character can go while staying
wholly on the platform — and `Section.check` refuses a section whose respawn point is not in it.
Hazards also carry a `Platform` attribute and a per-lane `HazardCooldown`, because `Touched` fires
once per limb per frame and every one of them used to be another teleport landing on the last one
plus another Notice down the wire.

*Red first:* `Section.respawn` did not exist (`attempt to call a nil value`), and in the world
`forty Touched fires in one contact cost the client 40 notices, not forty`.

**4 — Rebirth had no throttle.** Two layers, because the button was the symptom and write
amplification was the cause. `saveProfile` coalesces: a floor of `SaveMinInterval` seconds between
one player's writes, forced only for leaving, BindToClose and code redemption. The number is
derived — Roblox grants the server 60 + 10*players UpdateAsync calls a minute, so 60N/S <= 60 + 10N
holds for every N exactly when S >= 6 — and the boot guard warns if anyone lowers it. The ordered
leaderboard is only written when the score has actually moved. Rebirth and ArmSkip additionally sit
behind `onCooldown`, which refuses ONCE per window rather than answering every fire (a refusal per
fire would have moved the amplification rather than removed it).

*Red first:* `200 Rebirth fires in one frame granted 200 rebirths, not 200` and `...cost 200
DataStore calls, not 200`; then, after the first fix, `...answered them with 200 messages, not one
refusal per fire`.

**5 — the floor spent while the character was absent.** `lane.entry[level]` is recorded when the
section is built, and `onDoorChosen` assigns `lane.checkpoint = entry` unconditionally; only the
TELEPORT is still gated on a HumanoidRootPart. The mid-climb restore in `buildLane` reads the same
table instead of re-deriving the position from `Plat_<level>_1`.

*Red first:* `a player who spawns AFTER answering a fork stands on their new section (20.2 studs
from platform 1)` and `...and not stranded on the spent fork pad (0.0 studs away from it)` — 0.0,
i.e. standing exactly on it.

**6 — the fairness spec could not see an unreadable fork.** Correct, and the review was right that
`Fork.luau` itself is not wrong. `Fork.readTrap` reads `markedDoor`, which `Fork.plan` derives from
`trapDoor` eight lines earlier, so the old assertion compared a field with the field it came from.
Fork.spec now also reads every fork off the DOORS' own sign lists (`bearerOfTell`) and asserts
three things: exactly one door bears the named sign, it is the door the plan calls marked, and
reading it names the trap. WITNESS E is the review's own mutation, kept permanently.

*Red first:* re-applying that mutation to `src/shared/Fork.luau` now gives `FAIRNESS 2: exactly one
of the two doors bears the sign the inscription names, on all 40000 forks -> got 15985, want 0` —
where before it left Fork.spec at 47 passed, 0 failed. Fork.luau was restored byte-identical.

## Mutation sweep over the new guards

Every guard this pass added, mutated on the shipping source, plus a control the suite must NOT
notice:

| mutation | result |
|---|---|
| corridor clamp removed | Section 45/2, headless 76/3 |
| `Section.respawn` returns the platform centre | Section 44/3, headless 77/2 |
| `claimLane` returns 0 when full | headless 76/3 |
| rebirth cooldown removed | headless 78/1 |
| checkpoint moved back inside the `hrp` test | headless 77/2 |
| hazard debounce removed | headless 78/1 |
| `saveProfile` coalescing removed | headless 78/1 |
| leaderboard write-dedup removed | headless 84/1 |
| refusal sent on every fire | headless 82/1 |
| WaitingSpawn `Enabled = false` | headless 80/1 |
| CONTROL: `ArmSkipCooldown` 0.25 -> 0 | 47/0, 53/0, 79/0 — correctly invisible |

The control is doing its job in both directions: it shows the harness is not simply reporting
everything red, and it names a real gap (below). The `saveProfile` coalescing SURVIVED the first
sweep — the rebirth cooldown alone satisfied the DataStore assertion — which is why the check now
also measures the cost of one ordinary ten-floor run.

## What is still not good enough

Written down here rather than left for a player to find.

1. **Nothing in this repo simulates a character.** Every reachability claim — "a traitless player
   clears every jump", "the checkpoint is clear of the hazard" — is arithmetic over axis-aligned
   boxes. The emulator has no physics on purpose (`Workspace:Raycast` raises). A character in
   motion, or one that lands on a platform edge, can still brush a hazard the instant it respawns;
   the one-second cooldown covers that window but nothing has measured it.
2. **`CharacterHalfWidth = 2` is taken from Roblox's default character, not derived from anything
   in this repo,** and nothing verifies it against a real Humanoid. If an avatar scale setting ever
   widens the character, the hazard clearance shrinks silently.
3. **`Config.Limits.ArmSkipCooldown` is asserted by nothing** — the mutation control proved it:
   setting it to 0 changed no test. It is a belt on a cheap remote.
4. **The three `AutomaticCanvasSize` ScrollingFrames (Stats, List, CardTraits) are still
   unmeasured.** The HUD gate lists them NOT VERIFIED, so "can you scroll to the last of your ten
   picks" remains an open question. Unchanged by this pass.
5. **`hudcheck.luau` is still not wired into this repo's gates.** The review ran it from an ad-hoc
   runner that was never committed, so nothing re-runs it.
6. **Lane count at large `MaxPlayers` is untested.** At 220 studs a slot and an alternating layout,
   a 50-player server puts the furthest tower about 5 500 studs from spawn; nothing has been
   measured at that range, and Roblox's streaming and float precision out there are unexamined.
7. **The clock falls back to `tick()`,** which Roblox documents as deprecated, when
   `workspace:GetServerTimeNow()` is unavailable. It works today and it is what makes the throttles
   testable headless, but it is a call that could be removed under us.
8. **Everything on the builder's original notDone list is still true:** `Config.Passes` is read by
   nothing, there is not one Sound in `src/`, and `hz.kind` is written to an attribute and never
   rendered — all four hazard kinds are the same red neon cube.
9. **The game has never been opened in Roblox Studio and has never been published.** Every claim
   above is made by the luau CLI and by an emulator, not by the engine.
