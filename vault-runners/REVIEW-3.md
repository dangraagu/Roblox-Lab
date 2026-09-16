# Vault Runners — the difficulty curve

**Third pass, 2026-09-10.** REVIEW-2 closed seven findings and then reported two things its own
fixes had broken:

> *"The floor counter stopped being a difficulty curve. […] From floor 26 onward every floor of
> every tier is the identical difficulty spec."*
>
> *"The countdown now swings hard in both directions between adjacent floors, so 'deeper'
> regularly means 'shorter and easier'."*

Both are closed. The 6x5 size cap stays where it is; **the slack is the curve now**, and the
budget is measured against the maze the generator actually produced rather than against a nominal
size. Every number below came out of something that was run; the tools are in the tree
(`measure_curve.luau` to tune, `tests/Curve.spec.luau` to gate, `walk_vaultrunners.luau` to play).

## What changed

| | before | after |
|---|---|---|
| `Config.Collapse.Slack` | 2.0 | **1.85** (floor 1) |
| `Config.Collapse.MinSlack` | 1.5, a hard floor reached at floor 26 | **1.21, an asymptote never reached** |
| the decay | `TightenPerFloor = 0.02`, linear | `TightenFloors = 25`, `TightenExponent = 0.75`, power law |
| the demand | the BFS shortest path | shortest path **+ `WasteWeight` 0.25 × the cells in dead-end branches off it** |
| `Config.Save.FlushTickSeconds` | 5 | **7** |

```
slack(f) = MinSlack + (Slack − MinSlack) · (1 + (f−1)/TightenFloors)^(−TightenExponent)

f        1      10      30      60     100     200     400    1000    4000
slack  1.850  1.718   1.569   1.468   1.403   1.334   1.287   1.250   1.224
```

A power law has no floor. The old schedule shed **nothing** between floor 26 and floor 20000; this
one is still shedding 0.037 between floors 400 and 1000 and 0.026 between 1000 and 4000. There is
no depth at which the next floor is not measurably tighter, which is the property
`tests/Curve.spec.luau` asserts at every single floor from 1 to 1000 rather than at samples.

## 1. The shortest-path distribution at the 6x5 cap

2000 seeds at the cap (`measure_curve.luau` §0). A cell step is 24 studs, walked at
`Config.Movement.WalkSpeed` = 24 studs/s, so one step is 1.0s; a storey costs 6 treads ×
`ClimbSecondsPerStep` 0.9 = 5.4s.

| | median | range | CV |
|---|---|---|---|
| BFS cell steps, 5 storeys | 94 | 58 .. 132 | 13.1% |
| optimal route seconds | 115.6s | 79.6 .. 153.6 | 10.7% |
| **cells in dead-end branches off that route** | **62** | **22 .. 102** | **22.1%** |
| demand seconds (the budget's base) | 134.4s | 96.6 .. 175.3 | 9.4% |

That third row is the finding. **At a fixed size the branch mass varies twice as much as the route
length does** (CV 22.1% against 13.1%), and a budget derived from the shortest path alone cannot
see any of it — which is why two mazes of one floor were two difficulties.

## 2. The run-completion model, and what the endpoints assume

**Assumed player:** WalkSpeed **24 studs/s** — not Roblox's default 16, and not a hope: the server
writes it onto the Humanoid in `onCharacter` and the headless check asserts `hum.WalkSpeed == 24`.
Climb 5.4s per storey. Gems are not modelled as detours; the slack is what pays for them.

**Assumed skill — the explorer.** A player cannot see the maze from above, so the model is one who
cannot: perfect memory (never re-enters an exhausted branch), uniform choice among untried exits at
each junction, one step back out of each dead end. It is deliberately the *optimistic* end of that
— no hesitation, no misread corner, no missed jump, no detour. **Every completion percentage in
this document is therefore a ceiling on the real one.** What it is good for is comparing floors.

For a perfect maze the explorer's expected cost is not a simulation but arithmetic: each wrong
branch is entered before the right one with probability exactly ½, and a wrong branch of *m* cells
costs 2*m* steps, so the expected loss is **the number of cells in branches off the route**. Fitted
against the simulator over 2000 storey samples, the coefficient this predicts (1.0) comes out at
**1.0002** by least squares, and `simulated / (route + waste)` has a median of **1.0000** and a CV
of **1.12%**. `VaultPath.wastedCells` uses the closed form; `tests/Curve.spec.luau` re-measures with
its own independent simulator and never calls it, so the agreement is a fact about the game rather
than something built into the test.

**Floor-1 endpoint = 1.85**, chosen for a modelled completion of ~98% (Bronze 100%, Silver 98%,
Gold 98% — `measure_curve.luau` §1). A first vault you cannot fail.

**Asymptote = 1.21**, and it is *not* a taste call: it is the lowest asymptote that clears every
absolute-seconds bound in `tests/Collapse.spec.luau` with 25% headroom, checked over 1200 real game
floors **and** a 1200-maze random population at the cap (floors past 400 draw from that population,
so the game's own seeds alone cannot bound it). At the shipped schedule the worst case anywhere in
those 2400 vaults is:

| bound | required | measured worst |
|---|---|---|
| clear air over the collapse leaving a storey | 4s | **5.7s** |
| spare seconds at the exit | 8s | **32.2s** |
| spare after one gem per storey | 2s | **24.4s** |
| countdown | 30..300s | **66..268s** |

No test threshold was moved to make this fit.

**Why `WasteWeight` is 0.25 and not 0 or 1.** Swept, 300 mazes × 20 runs at the cap, with each β's
own lowest legal asymptote:

| β | floor 1 → asymptote | per-maze jitter CV | hardest/easiest maze |
|---|---|---|---|
| 0.00 (shipped) | 94% → 34% | 12.14% | 2.17× |
| **0.25** | **99% → 34%** | **8.81%** | **1.72×** |
| 0.50 | 100% → 45% | 6.50% | 1.49× |
| 0.75 | 100% → 61% | 5.16% | 1.34× |
| 1.00 | 100% → 71% | 4.76% | 1.30× |

0.25 is the only point that beats the shipped 0 **on both axes at once** — a wider curve *and* less
jitter — so it needs no trade-off argument. Everything past it buys jitter by spending curve: at
1.00 the deepest floor the safety bounds allow still completes 71% of modelled runs, and the endgame
stops being one.

## 3. The curve is monotone

`tests/Curve.spec.luau`'s own instrument, 120 mazes × 12 explorer runs per floor, Gold — the same
harness before and after, so this is a like-for-like comparison:

| floor | 1 | 10 | 30 | 60 | 100 | 200 | 400 |
|---|---|---|---|---|---|---|---|
| **before** | 94% | 89% | 59% | 59% | 59% | **60%** | **60%** |
| **after** | 98% | 96% | 88% | 78% | 68% | 59% | **50%** |

Before: flat from floor 30, and *running backwards* at 100 → 200. After: strictly decreasing, 48
points of curve. The finer measurement (300 mazes × 20 runs = 6000 modelled runs per floor,
`measure_curve.luau` §4) agrees: 98.1 / 95.4 / 87.8 / 76.8 / 68.8 / 58.5 / **49.1%**, with the
median budget-to-run-time margin falling 1.425 → 1.322 → 1.216 → 1.134 → 1.087 → 1.035 → 0.996. It
keeps going: floor 1000 is 41.9%.

REVIEW-2 measured that "about 41% of the ladder runs backwards" over floors 1..60. Re-measured on
the shipped tree, of 59 adjacent floor pairs per tier:

| | Bronze | Silver | Gold |
|---|---|---|---|
| run backwards in **pressure** | **0** | **0** | **0** |
| run backwards in **wall clock** | 28 | 31 | 27 |

The wall-clock reversals are **intended and are not a defect** — see §5.

## 4. The jitter is smaller, and it was never where the report said

There are two different quantities that both get called "the countdown jitters", and separating
them is most of the work.

**(a) The paper multiple — budget ÷ demand.** Already essentially zero before this pass, because
the countdown was already `ceil(demand × slack)`. Measured across 60 mazes of each report floor,
the worst spread is **under 2%, and all of it is the round-up to a whole second.**
`tests/Curve.spec.luau` now pins it there permanently, so nothing can reintroduce a budget that is
not a fixed multiple of what the maze asks.

**(b) The real one — how hard the maze actually is.** Gold floor 100, 400 mazes × 20 explorer runs
each, cost expressed as explorer seconds ÷ that maze's demand:

| | median | range | CV | hardest ÷ easiest |
|---|---|---|---|---|
| **before** (shortest path only) | 1.464 | 0.981 .. 2.182 | **12.00%** | **2.23×** |
| **after** (`WasteWeight` 0.25) | 1.309 | 0.952 .. 1.680 | **8.55%** | **1.76×** |

A 29% cut in the spread and a 21% cut in the worst-to-best gap. `tests/Curve.spec.luau`'s
independent run of the same measurement: CV **12.26% → 9.03%**, gap **1.76× → 1.51×**. Within-floor
wall-clock budget CV falls 12.1% → 9.0% at the same time.

**It is reduced, not eliminated, and the residual is disclosed.** Two Gold floor-100 mazes still
differ by 1.76× in difficulty. Pushing β to 1.0 would take that to 1.30× and cost most of the curve
(table in §2); the remaining spread is also 58% *within-maze junction luck* rather than between
mazes, which no budget can price out.

## 5. What is still open

**The wall-clock countdown still swings between adjacent floors, and should.** Gold floor 100 is
179s and floor 400 is 184s. That is the budget doing its job: floor 400's maze happens to be longer,
so it gets more seconds. Pinning the wall clock would mean pricing the vault by nominal size, which
is exactly the bug that made Silver and Gold unwinnable in REVIEW.md's finding 1. What must be
monotone is the pressure, and that now is. **A player reading the floor counter still sees a number
of seconds that jumps around**, and if that reads badly in a playtest the fix is in the HUD — show
the slack or a difficulty pip, not the raw seconds — not in the derivation.

**The whole schedule is calibrated against a model, and nobody has played this game.** The explorer
is optimistic by construction, so floor 400's real completion rate is below the modelled 49%, by an
unknown amount. Re-run `measure_curve.luau` after a playtest and move `Slack` / `MinSlack` to what
humans actually do. This is the single largest source of uncertainty in this document.

**The asymptote is an asymptote.** Slack reaches 1.224 at floor 4000 against a 1.21 floor. Past a
few thousand floors the curve is real but no longer *felt*. Nobody will get there, and if anybody
does, that is a good problem.

**Finding 7 (no obby) is untouched and still gates PUBLISHING.** The generator's only vertical
challenge is the six-step spiral; nothing crumbles and no jump can be failed, while the brief's
genre line, thumbnail and store copy lead with "ROBLOX RAGE OBBY". Shipping the code is fine;
shipping that store page is not. A product decision, not a bug.

**Finding 8's residual is untouched.** `Trace` bounds the cheat rather than removing it; a flier
still gets straight-line routes through walls. That half is a limitation of not raycasting, not a
tuning choice, and it is unchanged.

## 6. Also closed this pass

**REVIEW-2: "the anti-cheat's own tuning constants have NO test floor."** The three mutations the
reviewer found surviving the entire suite are now killed, two assertions each:

| mutation | now |
|---|---|
| `TrustedSpeedFactor` 1.35 → 3.0 | a maze cell crossed in 0.35s of trusted time (bound 0.65s) |
| `TrustedClimbFactor` 2.5 → 10 | a whole storey gained in 0.55s (bound 1.8s) |
| `TrustedBurstSeconds` 3 → 60 | an idle-banked teleport moves 1944 studs, 1246% of a vault |

The new block in `tests/Trace.spec.luau` bounds the tolerance in the units the *vault* is built in —
one cell step, one storey, one footprint — rather than by restating the constants, so a legitimate
re-tune inside the bounds is free. Shipped values measured: cell step 0.75s, storey 2.20s, banked
burst 97 studs flat / 25 up. **That last pair is worth reading twice**: a player who stands still
banks enough allowance to move 97 studs — 62% of a full-size vault — in a single tick, and to gain
1.4 storeys. It is within the bound and it is the shipped design, but it is now written down and
measured instead of implicit. The constants were deliberately **not** re-tuned here: that is an
anti-cheat change that needs testing against real replication lag, not a spec.

**REVIEW-2: `FlushTickSeconds` below the cited write cadence.** 5 → **7**. Six sits exactly on the
documented one-write-per-six-seconds boundary, and this codebase already refuses to sit on one
boundary (`RunState`'s inclusive `now >= sealAt`).

## 7. Evidence

**Mutation gate — 6 killed, 2 controls survived.** A sweep that kills everything proves nothing, so
two edits the suite must *not* notice were included:

| | Curve | Collapse | Progression |
|---|---|---|---|
| `WasteWeight` 0.25 → 0.00 | **1 failed** | 0 | 0 |
| `TightenExponent` 0.75 → 0.00 | **13 failed** | **1 failed** | **4 failed** |
| the old flat 0.02-per-floor schedule restored | **7 failed** | 0 | **2 failed** |
| `VaultPath.wastedCells` always returns 0 | **1 failed** | 0 | 0 |
| `demand` reads the BFS timeline, not the demand timeline | **1 failed** | 0 | 0 |
| `MinSlack` 1.21 → 1.50 (shallower, still monotone) | **1 failed** | 0 | 0 |
| CONTROL: `Config.Hud.AccentColor` repainted magenta | 0 | 0 | 0 |
| CONTROL: an unreachable nil-guard deleted from `wastedCells` | 0 | 0 | 0 |

`sha256sum` over the three touched source files is byte-identical to the pre-sweep baseline.

**Green, on the shipped tree:**

```
tests/Rng.spec.luau             37 passed, 0 failed
tests/Progression.spec.luau     66 passed, 0 failed
tests/Pets.spec.luau            75 passed, 0 failed
tests/RunState.spec.luau        75 passed, 0 failed
tests/VaultFloor.spec.luau     201 passed, 0 failed
tests/responsive.spec.luau      70 passed, 0 failed
tests/Collapse.spec.luau       274 passed, 0 failed
tests/Trace.spec.luau           27 passed, 0 failed   (+4: the tolerance floor)
tests/Curve.spec.luau           21 passed, 0 failed   (new)
check_vaultrunners.luau        106 passed, 0 failed
check_vaulthud.luau            PASS                   (22 layouts)
```

`luau-analyze` on the three changed source files and the new spec: nothing beyond the documented
environmental noise, zero `MisleadingAndOr` across `src/`.

**And it was played.** `walk_vaultrunners.luau` boots the real server script in robloxemu, joins a
character, and walks it corridor by corridor through the real maze at the WalkSpeed the server
wrote onto the Humanoid, with `Trace`'s throttle in the way — no teleporting to the exit pad. Two
runners: SOLVER takes the BFS line and whatever gems are on it; GRABBER detours for gems,
nearest-first, and abandons a storey once the collapse deadline for *that storey* is close. The
countdown quoted is the one the server sent the client; the gems are what the server wrote to
leaderstats.

| tier / floor | countdown | SOLVER | GRABBER | GRABBER's spare |
|---|---|---|---|---|
| bronze 1 | 76s | 38.8s, escaped, 8 | 62.8s, escaped, 40 of 48 | 13.2s |
| gold 1 | 264s | 125.6s, escaped, 66 | 215.6s, escaped, 528 of 660 | **48.4s** |
| gold 30 | 222s | 123.6s, escaped, 462 | 197.6s, escaped, 770 of 990 | **24.4s** |
| gold 100 | 179s | 111.6s, escaped, 374 | 165.6s, escaped, 638 of 990 | **13.4s** |
| gold 400 | 184s | 131.6s, escaped, 462 | 177.6s, escaped, 748 of 990 | **6.4s** |

The right-hand column is the curve, on the real server, in seconds a player would feel: a
gem-collecting runner finishes Gold floor 1 with 48 seconds in hand and floor 400 with six. Nothing
in that table reads `Config.Collapse` or `VaultPath.wastedCells`.

**Two things the walkthrough caught that no unit test would have.** Both were bugs in the
walkthrough, not the game, and both are the reason it is worth writing:

* Its first version printed two *different* countdowns for what it labelled the same floor. A
  successful escape advances `p.floors`, and leaving flushes the live profile to the store — so
  writing the target floor *before* the leave had the server's own flush land on top of it and the
  "second run" was a floor deeper. The fix is to leave first, then write.
* Its GRABBER drowned on the ground floor of Bronze, because it budgeted `countdown / storeys` per
  storey. The collapse reaches storey 0 at ~20% of the countdown, not at 100/5% of the wall clock
  measured from the top. A player who over-farms the ground floor dies on it — which is a real
  property of this game and worth knowing before a playtest.
