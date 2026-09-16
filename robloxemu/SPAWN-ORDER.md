# The engine spawns the character AFTER `CharacterAdded`, and the engine wins

What `robloxemu` modelled about `Player.CharacterAdded` was backwards, in the direction that makes
a broken game look fine. This file records the engine's real order, the change that puts the
emulator on the same side of it, the pattern a game has to use, and exactly what every headless
check in this repo did afterwards.

Nothing in any game directory was touched. No `check_*.luau` was touched. Nothing was committed,
pushed or published.

```
what changed
  emu/services.luau         Players:simulateSpawn rewritten to the engine's order + placement
  emu/instance.luau         Signal:FireOnThreads; SpawnLocation defaults; Player.RespawnLocation
  tests/services.spec.luau  10 new assertions (179 -> 189), written first and watched fail

after
  84 headless runs (every robloxemu check + every game's own tests)
  83 green, 1 red: deep-vein/tests/walk.luau  -- and it looks like a REAL defect
  luau-compile clean on both changed files; luau-analyze clean on both
```

---

## 1. The engine's order

Measured in Roblox Studio on 2026-09-10 and written up in `fork-tower/STUDIO.md`, from a
server-side `Player.CharacterAdded` handler sampling `HumanoidRootPart` every Heartbeat. Verbatim:

```
[0.0000] f01 parent=nil        hrp=0.00,0.00,0.00
[0.0051] f02 parent=Workspace  hrp=0.00,3.51,-160.00      <- Waiting.WaitingSpawn
[0.0149] f03 parent=Workspace  hrp=0.00,3.51,-160.00
     ... unchanged for 20 frames
```

So the sequence is:

1. the engine builds the character model **unparented**, with the root part **at the world origin**;
2. `Player.Character` is set and **`CharacterAdded` fires** — still unparented, still at the origin;
3. **one frame later** the engine parents the model to `Workspace` **and** places it on the enabled
   `SpawnLocation`, overwriting whatever the handler wrote in between. Silently: no error, no
   warning, the assignment succeeded and was thrown away.

With **no** enabled `SpawnLocation` the engine instead drops the character above the highest ground
at the origin — which on a sealed shell is the **roof**. That is a separate trap this repo has been
bitten by twice (`grow-a-crystal/src/server/Main.server.luau:648`,
`nightwatch-manor/src/server/Main.server.luau:625`), and it is why both of those games build a real
`SpawnLocation` and point `plr.RespawnLocation` at it.

The old `simulateSpawn` did the exact opposite of steps 1-3: `char.Parent = parent` **before**
`CharacterAdded`, and no placement at all, ever. A game that wrote the character's CFrame inside
`CharacterAdded` therefore passed every headless check in this repo and failed in Roblox. Fork
Tower shipped that way past eight green suites, this emulator and two rounds of adversarial review,
with every player spawning 174 studs from their own tower over empty sky.

---

## 2. What `simulateSpawn` does now

`emu/services.luau`, `Players:simulateSpawn(plr, parent)` — same signature, same return value.

```
1. build the Model unparented; HumanoidRootPart explicitly at CFrame.new(0, 0, 0)
2. plr.Character = char
3. fire CharacterAdded -- one fresh coroutine PER CONNECTION (Signal:FireOnThreads)
4. the engine's step: char.Parent = parent, AND place the root part
5. advance the virtual clock by one frame (1/60 s)
```

**Step 3 fires on threads because Roblox does.** The old `Signal:Fire` calls handlers straight off
the calling thread, so a handler that yields raises `thread yielded unexpectedly`. The correct fix
for this defect *has* to yield, so firing inline would have made the emulator reject correct game
code. `Signal:FireOnThreads(spawner, ...)` in `emu/instance.luau` takes `task.spawn` from the
caller and gives each connection its own thread; `Fire` is unchanged everywhere else.

**Step 4 is ordered after step 3 rather than scheduled a frame out, on purpose.** `sched:spawn`
runs each handler synchronously up to its first yield, so by the time step 4 runs every handler has
either finished (and written a CFrame it is about to lose) or parked. Ordering — not a timestamp —
is the property the trace actually pins down, and ordering is what decides whether a game's write
survives. The alternative, `task.delay(1/60, ...)`, was written first and rejected: because this
scheduler's bare `task.wait()` is a **zero-length** yield, a delayed engine step also fails a poll
written `while char.Parent == nil do task.wait() end`. That poll is correct against the real engine,
so failing it would be a false alarm, and "write `task.wait(1/60)` instead" would be an
emulator-only affordance. `tests/services.spec.luau` pins the decision with an explicit bare-wait
test.

**Step 5 is the one side effect on unrelated timers,** and it is deliberate: it means a handler that
*did* wait has finished placing the character by the time `simulateSpawn` returns, so the **42
existing call sites in 12 files** keep working unchanged. That was the choice — keep every caller
working rather than hand the next phase 42 edits. Measured cost in §4.

### Where the character lands when the game does not wait

`engineFinishSpawn` picks the spawn the engine would pick:

| order | rule |
|---|---|
| 1 | `plr.RespawnLocation`, when it is an **enabled** `SpawnLocation` still descended from `Workspace`. A disabled or destroyed one is ignored, as in Roblox. |
| 2 | otherwise the **first** enabled `SpawnLocation` in a depth-first walk of `Workspace`. |
| 3 | otherwise the **highest collidable top face over the world origin** — the sealed-shell roof. |
| 4 | otherwise `(0, 2.51, 0)` — nothing to stand on, exactly as Roblox would give you nothing. |

`SpawnLocation.Enabled` now defaults to **true** on the class (`emu/instance.luau`), as it does in
Roblox, so a spawn a game created and never configured counts — the engine would use it.

The root part is placed at the spawn's **top face + 2.51 studs**. That constant is the one fitted
number here and its provenance is stated in the source: the single recorded placement is Fork
Tower's `WaitingSpawn`, Position `(0, 0.5, -160)`, Size `(6, 1, 6)` — a top face at y = 1.0 — and
the root read y = **3.51** the frame the engine placed it. 3.51 - 1.0 = 2.51.

---

## 3. The pattern a game must use

Both of these are real Roblox patterns. Neither is an emulator affordance.

**Preferred — let the engine place you.** Build a real `SpawnLocation` where you want the player
and point `plr.RespawnLocation` at it *before* the character loads. Then there is no race to lose:
the engine's own placement is already correct, and the handler does not have to yield at all.
`grow-a-crystal` and `nightwatch-manor` do this, and the emulator now honours it — measured with a
throwaway probe against the built bundles: `grow-a-crystal` lands at `0.00, 4.00, -6.00` against
`RespawnLocation Spawn_<id>` at `(0, 0, -6)`, `nightwatch-manor` at `3000.00, 104.00, 20.00`
against `SpawnPad` at `(3000, 100.6, 20)`.

**When the destination is not a SpawnLocation** — a per-run checkpoint that moves as the player
climbs, say — yield until the character is genuinely in the world, then write:

```lua
local frames = 0
while char.Parent == nil and frames < 300 do
    task.wait(1 / 60)
    frames += 1
end
-- re-read anything you cached: the world can be rebuilt while you yield
local lane = lanes[plr]
if hrp and lane then (hrp :: BasePart).CFrame = CFrame.new(lane.checkpoint) end
```

`char.Parent` becoming non-nil is the signal, because the recording shows parent **and** placement
landing in the same frame: by the time a polling handler sees a parent, the engine has already
finished. Bound the loop — a character that never arrives must not leave a handler parked for the
session. A bare `task.wait()` works here too (§2), but a duration is clearer and survives any
future change to the scheduler.

What does **not** work, measured in Studio: reaching for `char:WaitForChild("Humanoid", 10)` and
`char:WaitForChild("HumanoidRootPart", 10)` first and assuming they buy you a frame. Fork Tower's
shipping handler did exactly that and still lost the race — on the server both children already
exist when `CharacterAdded` fires, so neither call yields.

---

## 4. Results — every headless check in the repo

84 runs: 14 `robloxemu/check_*.luau`, 4 `robloxemu/tests/*.spec.luau`, every game's own `tests/`,
and `vault-runners`' four root-level scripts. Baseline before the change: **84/84 green.** After:
**83 green, 1 red.**

### The one that fails

| check | what it says | verdict |
|---|---|---|
| `deep-vein/tests/walk.luau:257` | `FAIL: the spawn point has ground under it` — `114 passed, 1 failed` (was `116 passed, 0 failed`) | **REAL defect the old order was hiding** |

Measured with a throwaway probe against the built bundle: a fresh Deep Vein miner's root part ends
at **`-80.00, 2.51, 0.00`** — standing on `MinersRest`, the game's own `SpawnLocation` at
`(-80, -0.5, 0)` — and is still there a second later. Their shaft is at x = 0. The check searches
for ground **inside the player's own shaft folder**, finds none, and fails; the dependent
`...within a step` assertion is then skipped, which is the 116 -> 114 + 1 arithmetic.

Why this reads as a defect rather than a harness gap: `src/server/Main.server.luau:1309` is
`local function place(char)`, connected straight to `CharacterAdded`, and it CFrames the miner into
their shaft with no wait — the naive shape exactly. `MinersRest` was built (see the comment at
`:220`) for "the frame or two BEFORE that runs"; the Studio measurement says the engine's placement
comes **after**, so the pad is not a stopgap, it is the final answer. The only other writes to the
root part (`:1178` elevator, `:1243` rebirth) are player-initiated — there is no periodic rescue to
heal it — so a Deep Vein player stands 80 studs west of shaft 0, and 160 studs further out for each
additional player, with their mine out of reach and nothing pointing at it.

Residual uncertainty, stated because nobody has opened Deep Vein in Studio: `place` begins with
`char:WaitForChild("HumanoidRootPart", 10)`, and if that yielded in the real engine `place` would
land after the engine step and win. The evidence says it does not — Fork Tower's shipping handler
called both `WaitForChild`s and its write was still discarded, measured. I did not fix it; that is
the next phase's call.

### Everything else, and why green means different things

| game | does its `CharacterAdded` move the character? | result |
|---|---|---|
| **fork-tower** | yes, and it **waits** for `char.Parent` (the STUDIO.md fix) | green: `check_forktower` 119/0, `world.check` 71/0 — the fixed game passes the new order |
| **grow-a-crystal** | `plr.RespawnLocation` **and** a `task.defer` re-write next frame | green, and now green *for the right reason*: the deferred write lands after the engine step |
| **nightwatch-manor** | `plr.RespawnLocation` per safehouse | green; the probe confirms the character lands on `SpawnPad` |
| **anomaly-observatory** | yes — but `task.wait(0.2)` **before** teleporting | green: it yields far past the engine step, so it wins |
| **vault-runners** | no (`onCharacter` only sets `WalkSpeed`) | green: unaffected |
| **labyrint-spill** | no CFrame write in `onCharacterAdded` | green — and no check in the repo spawns a labyrint character at all |
| **plus1-jump** | **yes, naive** (`:391 onCharacter`, no wait) | green, but see below |
| **deep-vein** | **yes, naive** (`:1309 place`, no wait) | **red**, above |

**`plus1-jump` is green and should not be read as safe.** `check_plus1_rejoin.luau` calls
`simulateSpawn` *before* running the server, so the placement it measures comes from
`onPlayerAdded`'s direct `if plr.Character then onCharacter(...) end` call, not from
`CharacterAdded` — the racing path is never exercised by any check. Its `CharacterAdded` write is
the naive shape, and the game survives it only because a fall-rescue loop (`:407`) teleports the
climber back to their frontier platform within 0.4 s — the "teleport-rykk" its own comment
describes. That is a mask, not a fix, and it is one the emulator still cannot see.

### Two outputs changed without failing

* `vault-runners/walk_vaultrunners.luau` — a printed timing moved from `200.0s` / `2.8s waiting` to
  `200.2s` / `3.0s waiting`. That is §2 step 5: 12 spawns x 1/60 s. The script has **no
  assertions**; it is a measurement report. Attributable to this change, and harmless.
* `robloxemu/check_anomaly_attrs.luau` — its printed roll sequence and instance count move. **Not
  attributable to this change**: the file is non-deterministic run to run, because the server takes
  a per-session salt from a real random source. Proved by running it twice in a row on identical
  code and diffing — `324 passed` then `325 passed`, different sequences, both green. It has never
  failed.

Every other one of the 84 runs is **byte-identical** to its baseline output.

---

## 5. Would the new emulator have caught the bug that started this?

Yes, and it was checked rather than assumed. In an isolated copy of the repo under the scratchpad
(nothing in `D:\Claude\Roblox` touched), Fork Tower's spawn fix was reverted to the shipped-broken
shape, the bundle rebuilt, and `grep -c "while char.Parent == nil" build/fork-tower.luau` returned
**0** — proof the mutation reached the built bundle rather than surviving in a stale artifact.

| emulator | `check_forktower.luau` against the same broken source |
|---|---|
| old (`git show HEAD:robloxemu/emu/*.luau`) | `117 passed, 2 failed` — only the hand-rolled "STUDIO FINDING 1" block, which replays the recorded order by hand and deliberately does not use `simulateSpawn` |
| new | `116 passed, 3 failed` — plus `FAIL: a player who spawns AFTER answering a fork stands on their new section (469.6 studs from platform 1)`, which comes from an ordinary `simulateSpawn` call |

`fork-tower/tests/world.check.luau` stayed `71 passed, 0 failed` against the broken source both
times: it spawns six characters and asserts nothing about where any of them lands.

---

## 6. Mutation sweep

Every assertion added to `tests/services.spec.luau` was mutation-tested against the code it is
supposed to guard. Each mutation was applied to a restored-from-original copy; the file's md5 was
recorded before and after so a patch that did not apply could not be mistaken for a surviving
mutation; and a run that failed to print a summary line counts as KILLED, with its error shown.

| # | mutation (in `emu/`) | result |
|---|---|---|
| M1 | engine step moved **before** `CharacterAdded` (the old order) | KILLED — 5 assertions |
| M2 | engine parents the model but never **places** it | KILLED — 3 |
| M3 | a **disabled** `SpawnLocation` counts as enabled | KILLED |
| M4 | `Player.RespawnLocation` ignored | KILLED |
| M5 | no-spawn fallback picks the **lowest** ground, not the highest | KILLED |
| M6 | stand-off `2.51` -> `3.51` | KILLED — 3 |
| M7 | handlers fired **inline** instead of on their own threads | KILLED (`thread yielded unexpectedly`) |
| M8 | `SpawnLocation.Enabled` no longer defaults to true | KILLED |
| M9 | ground scan drops its `CanCollide` filter | KILLED |
| M10 | `simulateSpawn` no longer advances its frame | KILLED |
| **CONTROL** | `Workspace` default `Gravity` `196.2` -> `9.81` | **SURVIVED all 84 runs** |

M7, M9 and M10 survived the first sweep and were not left that way. M7 was a defect in my own
mutation driver, which read "no summary line" as a pass when the suite had in fact died. M9 and M10
were genuine holes, and each got an assertion: a `CanCollide = false` banner hung above the shell
roof, and the patient handler's placement asserted with **no** further `advance`.

The control is a real behavioural change to a real property in `emu/services.luau`, chosen because
nothing in the repo ever reads `workspace.Gravity` — every game carries its own `Config` constant.
Applied, it changed nothing in any of the 84 runs except `check_anomaly_attrs`' known
non-deterministic count. That is the point: the sweep can produce a SURVIVED, so the ten KILLED
results above are not a broken harness reporting 10/10.

---

## 7. What I could not determine

* **The exact placement height.** One recorded sample (`3.51` over a 1-stud spawn centred at
  `y = 0.5`) fits three parameterisations equally well — top face + 2.51, centre + 3.01, bottom
  face + 3.51. The top-face form was chosen because it degrades sensibly for a thicker spawn brick.
  There is no physics here, so nothing settles afterwards: **assert on the XZ and on "above the
  spawn", not on this Y to the centimetre.**
* **Which spawn Roblox picks when several are enabled.** Roblox chooses among the eligible ones;
  this takes the first in depth-first tree order so a check gets a repeatable answer. A game that
  leaves two enabled spawns in the world therefore gets **one** of the engine's possible answers
  here, not all of them.
* **Team / `TeamColor` spawn matching is not modelled at all.** Only `Enabled` and
  `RespawnLocation` are consulted. No game in this repo uses teams.
* **The no-spawn ground scan is axis-aligned and origin-only.** Rotation is ignored, and Roblox's
  small spawn *area* around the origin is modelled as the single column over `(0, 0)`. Enough to
  answer "roof or floor"; not a physics engine.
* **Whether `char:WaitForChild("HumanoidRootPart")` ever yields on the server.** Fork Tower's
  Studio trace says it did not there, which is what makes Deep Vein's `place` a defect rather than
  a coincidence — but that is one game, one session.
* **Whether Deep Vein is *actually* broken in the real engine.** Everything in §4 is this emulator
  agreeing with a Studio measurement taken on a *different* game. Nobody has opened Deep Vein in
  Studio.
* **`CharacterRemoving`, `CharacterAppearanceLoaded`, `Players.RespawnTime`, and
  `Humanoid.Died` -> auto-respawn** are still not modelled. This change covers the spawn only, and
  a game whose bug lives in the respawn *cycle* is still invisible here.
