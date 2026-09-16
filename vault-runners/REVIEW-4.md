# Vault Runners — the obby

**Fourth pass, 2026-09-10.** REVIEW.md's finding 7 was the last thing gating publishing, and it
was not a bug:

> *"THERE IS NO OBBY. […] What is built is a flat maze walk per storey plus one six-step spiral
> staircase in a single corner cell. Nothing crumbles, there are no platforms to miss, and there
> is no jump in the whole game a player can fail."*

The decision was to **build the obby, not retitle the game** — the whole reason this concept beat
three others is demand for that genre, and softening the store page to "timed maze runner" throws
away the market fit that justified building it.

It is built. This document is what was measured while building it. Every number came out of
something that was run; the tools are in the tree (`measure_curve.luau` §6 to tune,
`tests/Ascent.spec.luau` + `tests/VaultFloor.spec.luau` to gate, `mutate_obby.sh` to check the
gates, `walk_vaultrunners.luau` to play it).

---

## 1. What the obby is, and why this shape

**The shaft out of every storey**, in the one maze cell the hole in the floor above is cut from:

| | v1 | now |
|---|---|---|
| pads per storey | 6 treads, 3-stud rises | 6 pads, 3-stud rises (unchanged) |
| pad footprint | 5 x 5 | **3 x 3** |
| centre-to-centre | 6 studs | **8 studs** (`Config.Vault.StepReach`) |
| **open air between pads** | **1.0 stud** | **5.0 studs** |
| as a share of the jump's reach | 57% | **76%** |
| crumbles | no | **1.1s after you first stand on it, back 3.0s later** |

**Why gaps and crumbling, and not moving platforms or timed sections.** The vault is 12-stud
cells and 18-stud storeys, and the shaft has to live inside ONE cell — the hole above it is one
maze cell wide, and widening that would rewrite the floor tiling, the entry alignment and the
kill lines. Twelve studs is too small for a moving platform to travel and too small for a timed
section to mean anything. It is exactly big enough for a straight eight-stud hop from one corner
of the cell to the next with real air under it, and that is the one thing a 12-stud box does well.
Crumbling is what the brief's own thumbnail says
("a player mid-air leaping between two crumbling stone platforms") and it adds the second failure
mode a static gap cannot: you cannot stop on a pad and line the next jump up.

**THE SHAFT DOES NOT SCALE WITH DEPTH, AND THAT IS DELIBERATE.** Swept over 1200 generated
vaults — 3 tiers x 400 floors, **23 800 hops** — every single hop is 5.00 studs of gap at 75.7%
of the jump's reach. Floor 1's shaft is floor 400's shaft. REVIEW-3 established that the slack
schedule is the difficulty curve and the size caps are a pacing budget; adding a second curve
here would mean a second thing to tune against a second model, and the first one already has no
floor. What changes with depth is how little room there is to afford a fall, which is exactly
what §3 measures.

**5.0 studs of air is the load-bearing number.** `Config.Movement.RunnerWidth` is 2 (R15's
HumanoidRootPart), so a 1-stud slot is a seam a runner walks over — v1's shaft could not be
missed no matter how badly you jumped, because there was nowhere to fall. Five studs is a hole.

**76% of the jump is the other one, and it is solved, not guessed.** The game leaves
`Workspace.Gravity` (196.2) and `Humanoid.JumpPower` (50) at Roblox's defaults, so
`VaultPath.jumpReach` solves the projectile: a runner at WalkSpeed 24 carries **12.23 studs** on
the level and **10.57 studs** while gaining the 3 studs to the next pad. The hop asks for 8.
`tests/VaultFloor.spec.luau`'s new `climbIsFailable` check holds both ends of that at every pad
of every shaft — the gap must be wider than the runner AND the hop must sit between 60% and 90%
of what the jump actually carries — so neither "it went back to a staircase" nor "it became
unclimbable" can land silently.

**And the shaft cannot be short-cut.** Every pad-to-pad pair was checked, not just the consecutive
ones. A Roblox jump peaks at 6.37 studs, so the only skip that exists anywhere in the shaft is
**floor -> pad 2**, straight up six studs from under it: one hop saved at the very bottom, and it
is skill, not a bypass. Every other pair needs a rise of 9 studs or more (unreachable at any
speed) or asks 11.31 studs of a 7.59-stud reach. From pad 1 there is nowhere to go but pad 2.

## 2. What a miss costs, and how the budget pays for it

**A missed hop costs SECONDS. It does not cost progress and it does not end the run.** You fall
onto the storey you came from, the shaft starts again at pad 1, and the collapse has not paused.
No new death rule, no lost gems, no teleport — the vault already has exactly one way to lose, and
an obby that invented a second would be two games sharing a countdown. It also means the obby
cannot make a vault unwinnable on its own, which is what `tests/Collapse.spec.luau` depends on.

**The cost, in closed form.** Six hops, each missed with probability *p*, and a miss restarts the
shaft — the textbook "n consecutive successes with restart":

```
E[attempts] = (1 - q^n) / (p q^n)        q = 1 - p
E[misses]   = p * E[attempts]
```

At the shipped `p = 0.04`: **6.938 hop attempts and 0.277 falls per storey transition.** A fall
costs the drop plus getting back under pad 1 — and misses are *not* spread evenly up the shaft,
because hop *k* is only reached with probability q^(k-1), so the drop is weighted by that and the
square root is taken inside the expectation, not outside. One storey transition:

| | seconds |
|---|---|
| clean climb (6 hops at `ClimbSecondsPerStep`) | **5.400** |
| priced climb (attempts + falls) | **6.532** |
| the retry half of it | **1.132** (+21.0%) |
| 20 000 rolled climbs, `tests/Curve.spec.luau` | **6.52** (worst single climb 28.89s) |

The rolled figure and the closed form agree to **0.2%**, and the spec that rolls them never calls
`VaultPath.climbSeconds` — the same arrangement REVIEW-3 used for `wastedCells`. That independence
paid immediately: the first closed form used `E[misses] = E[attempts] - n`, which counts the
successful hops of a failed round as failures. It over-priced the shaft by 10% and the rolled
climbs are what caught it.

**THE OBBY IS PAID AT COST, NOT AT SLACK.** This is the one real design decision in the pass. The
countdown is now

```
frac(s) * T   >=   slack * walk(s)  +  obby(s)          per storey
        T     >=   slack * walk(top) + obby(top)         the escape
```

and **not** `slack * (walk + obby)`. Slack exists to cover what nobody can predict — how much of
a maze a runner who cannot see it from above will wander into. The obby's expected cost is not
that: it is a number this repo computes exactly, so multiplying it by 1.85 at floor 1 would hand
out a premium on the one part of the run that is not uncertain. It is not a taste call — it was
measured both ways, 6000 modelled runs per floor:

| Gold completion | f1 | f10 | f30 | f60 | f100 | f200 | **f400** |
|---|---|---|---|---|---|---|---|
| pre-obby (REVIEW-3 §3) | 98.1 | 95.4 | 87.8 | 76.8 | 68.8 | 58.5 | **49.1** |
| obby charged INSIDE the slack | 98.7 | 96.2 | 89.2 | 79.2 | 70.8 | 61.7 | **52.1** |
| obby charged AT COST (shipped) | 98.3 | 95.3 | 87.8 | 76.8 | 68.5 | 59.7 | **50.3** |

Charging it inside the slack made **the rage obby make the game easier** — three points of curve
handed back at floor 400, which is precisely backwards. At cost, REVIEW-3's whole schedule
survives with the obby in it and nothing about `Config.Collapse` moved.

The bottom row was re-measured afterwards against the SHIPPED `VaultPath.countdown` rather than
the scratch implementation the choice was made with, and it comes back identical to the decimal —
98.3 / 95.3 / 87.8 / 76.8 / 68.5 / 59.7 / 50.3 — so the table is a fact about the code that ships,
not about a thing that was tried.

**The falls are charged to the storey they land on.** A clean climb is a monotone rise out of the
collapse; a *missed* hop puts the runner back on a floor the plane is rising toward. So storey
*s*'s own deadline covers `(s+1) * retry` — every fall on every transition up to and including the
one out of storey *s* — while the clean climb stays inside the walk demand. `m.obbyBy[s+1]` is
that quantity and `tests/Collapse.spec.luau` asserts it storey by storey.

**One more thing the pads got wrong, and it was not the maths.** The server decides a runner is
standing on a pad by comparing the trusted position to the pad's top. The first cut compared the
runner's ROOT — and pad 1's top is exactly `StepRise` (3) above the storey floor while a standing
root is exactly `Run.RunnerRootHeight` (3) above whatever it is standing on. Those are the same
height. So merely walking across the stairwell cell registered as standing on pad 1: the pad began
crumbling while the runner was still approaching, and was gone by the time they jumped. The fix is
to compare the FEET, where "on the pad" is 0 and "on the floor below it" is -3 and the two cannot
be confused. It is worth real gems: the GRABBER on Gold floor 400 banked **594 before the fix and
638 after**, because it stopped losing three seconds to a pad it had destroyed on the way in.

## 3. The monotonicity table, reproduced

`tests/Curve.spec.luau`'s own instrument, unchanged from REVIEW-3 except that the explorer now
**rolls every hop of every shaft** instead of adding an average — 120 mazes x 12 explorer runs per
floor, Gold. Like-for-like, same harness, same seeds:

| floor | 1 | 10 | 30 | 60 | 100 | 200 | 400 |
|---|---|---|---|---|---|---|---|
| **REVIEW-3, staircase** | 98% | 96% | 88% | 78% | 68% | 59% | 50% |
| **now, crumbling shaft** | 98% | 96% | 88% | 77% | 68% | 61% | 51% |

Still **strictly decreasing at every floor from 1 to 1000** — the property `tests/Curve.spec.luau`
asserts at every floor rather than at samples — and the 6000-run measurement in §2 above says the
same thing at four times the resolution. **The schedule did not have to move.**

Rolling the hops rather than averaging them is the whole point of putting the obby in that file.
A budget that pays the expected cost and a runner who pays the expected cost cancel exactly; what
the obby actually adds to a run is the **tail** — most climbs are clean, some cost four falls —
and a tail only exists if the hops are rolled. The worst of 20 000 rolled climbs took 28.9
seconds against a 5.4-second clean one.

**The countdowns that come out of it**, over 3 tiers x 200 floors:

| | before | after |
|---|---|---|
| countdown range | 66..268s | **68..273s** |
| tightest storey, clear air over the collapse (bound: 4s) | 5.7s | **9.7s** |
| tightest escape, spare seconds (bound: 8s) | 32.2s | **32.9s** |
| headroom under `Collapse.MaxSeconds` (300) | 32s | **27s** |

## 4. The one assumption, swept

`Config.Ascent.ModelMissChance` is **a model, not a measurement**, in exactly the way
`measure_curve.luau`'s blind explorer is. Nobody has played this game, so there is no observed
miss rate to put there, and no number in this repo would make one up. Nothing in the running game
reads it — it exists only so the countdown can price the obby. So it is swept rather than
defended (`measure_curve.luau` §6, at-par pricing, 120 mazes x 12 runs per cell):

```
    p | climb  falls/ | worst |    f1   f10   f30   f60  f100  f200  f400 | mono
      |  (s)   storey |  cd   |
 0.00  |  5.40   0.00  |  268s |  98.1  96.9  88.1  76.7  70.1  58.8  52.0 | yes
 0.02  |  5.93   0.13  |  270s |  97.8  96.5  88.2  75.8  68.1  60.3  51.2 | yes
 0.04* |  6.53   0.28  |  273s |  98.2  96.0  87.6  76.9  67.6  61.2  51.1 | yes
 0.06  |  7.21   0.45  |  275s |  98.1  96.0  88.0  76.8  68.3  60.6  53.2 | yes
 0.08  |  7.97   0.65  |  279s |  97.8  96.1  87.8  77.6  68.5  61.6  53.8 | yes
 0.12  |  9.82   1.15  |  286s |  98.0  95.1  87.2  76.6  69.0  64.0  56.0 | yes
```

The curve is **monotone at every value swept**, and the `p = 0.00` row is the pre-obby derivation
exactly — which is the sanity property that matters: with the obby costing nothing, the countdown
is byte-for-byte the one REVIEW-3 signed off.

What the sweep does say is that `MaxSeconds` is the binding constraint on *p*: at 0.12 the worst
countdown the game can generate is 286s against a 300s promise, and there is no room for a
playtest to move *p* much past that without the size caps coming down with it. At the shipped
0.04, six hops is a **78% chance of a clean climb**, **1.11 expected falls in a five-storey Gold
run**, and a **62% chance that a Gold run contains at least one fall**.

## 5. The obby cannot be, and is not, difficulty from the anti-cheat

REVIEW-3 §6 recorded that a standing player banks enough allowance to move 97 studs and gain 1.4
storeys in a single tick. Re-measured against the shaft that now exists:

| | measured |
|---|---|
| trusted allowance | 32.40 studs/s flat, 8.333 studs/s up |
| banked burst, vertical | **25.0 studs = 1.39 climb shafts = 8.3 hops** |
| a teleport claim gaining a whole 72-stud Gold vault | 8.65s of trusted time |
| an honest climb of the same vault | 26.13s (21.60s if nothing is missed) |
| ratio | **3.02x** (it was 2.50x before the obby) |

**So yes: a lying client skips a shaft, and this is said plainly rather than fixed by tightening
`Trace`.** One banked burst is worth more than a whole storey's climb. The ratio got *worse* with
the obby, not better, because the honest climb got slower and the tolerance did not.

That is fine, and it is the point of measuring it: **the obby's difficulty has never rested on the
anti-cheat.** It rests on five studs of open air and on client-side physics the server does not
own. `Trace` bounds what a liar *gains*; it was never going to be what makes an honest player miss
a jump. Tightening `TrustedClimbFactor` to close this would need testing against real replication
lag — that is an anti-cheat change, not a spec — and it is deliberately not done here.
`tests/Trace.spec.luau` now asserts the one bound that does matter (a single burst cannot buy the
whole climb of a full-size vault) and **prints the shaft figure every run**, so it stays a
disclosed number rather than an implicit one.

## 6. It was played

`walk_vaultrunners.luau` boots the real server in robloxemu and walks a real character through
the real maze at the WalkSpeed the server wrote onto the Humanoid, with `Trace`'s throttle in the
way. It now **climbs the shaft pad by pad** — the first version flew straight up the middle of the
stairwell, which is the one thing a player cannot do, and it meant the obby was invisible to the
only tool in the repo that plays the game. A crumbled pad is *waited for*, because that is what a
runner standing under it has to do.

Three runners. SOLVER takes the BFS line; GRABBER detours for gems nearest-first; **FUMBLER is a
GRABBER who misses the top hop of every shaft once** — fifteen studs down, back to pad 1.

| tier / floor | countdown | runner | took | outcome | banked / on floor | falls (fell, waited) |
|---|---|---|---|---|---|---|
| bronze 1 | 79s | solver | 45.0s | escaped | 8 / 48 | 2 (0.2s, 2.4s) |
| bronze 1 | 79s | grabber | 59.6s | escaped | 36 / 48 | 0 |
| bronze 1 | 79s | **fumbler** | 31.6s | **COLLAPSE** | 0 / 48 | 4 (1.2s, 2.2s) |
| gold 1 | 270s | solver | 149.2s | escaped | 66 / 660 | 6 (3.6s, 3.6s) |
| gold 1 | 270s | grabber | 219.1s | escaped | 506 / 660 | 2 (0.7s, 0.0s) |
| gold 1 | 270s | fumbler | 237.6s | escaped | 484 / 660 | 8 (4.4s, 1.8s) |
| gold 30 | 227s | grabber | 200.0s | escaped | 726 / 990 | 1 (0.8s, 2.8s) |
| gold 100 | 184s | grabber | 159.2s | escaped | 594 / 990 | 0 |
| gold 400 | 189s | grabber | 181.9s | escaped | 638 / 990 | 4 (1.7s, 2.0s) |
| gold 400 | 189s | **fumbler** | 115.6s | **COLLAPSE** | 0 / 990 | 6 (3.0s, 2.0s) |

**A runner actually experienced a failed jump, and it actually ended runs.** On Bronze floor 1 the
FUMBLER fell four times, spent 1.2s falling and 2.2s standing under a pad that had not respawned
yet, and was caught at 31.6s — storey 0's deadline on that vault is 34% of a 79-second countdown,
which is 26.8s. It banked nothing. On Gold floor 400 the same runner was caught at 115.6s after
six falls. That is the obby doing exactly what it was designed to do: it never kills you, it costs
you seconds, and the collapse spends them.

**Two things the walkthrough caught that no unit test would have.**

* Its first shaft-climbing version drowned the GRABBER on Gold floor 1 and Gold floor 400 — runs
  that escaped comfortably before the obby existed. The gem budget reserved four seconds of air
  plus the *expected retry*, arrived at the stair with that in hand, and then fell. **Reserving
  the expected retry is not enough: the runner is still at storey height for the first hop or
  two, so what has to be reserved is the whole climb.** That is a real property of the game with
  the obby in it — a gem-greedy player has to leave room for a fall. Reserving the whole climb
  costs the GRABBER real loot: it banks 506 of Gold floor 1 where the pre-obby run banked 528,
  and 594 of Gold floor 100 where the pre-obby run banked 638. That is the obby being paid for
  out of gems rather than out of the countdown, which is the correct place for it to come from.
* The GRABBER now finishes Gold floor 400 with **7.1 seconds in hand** (181.9s of 189s), against
  **50.9s** on Gold floor 1 (219.1s of 270s). The curve is visible in seconds a player would
  feel, on the real server, and nothing in that column reads `Config.Collapse`.

## 7. Mutation gate

Every assertion added in this pass, and the mutation it has to catch. `mutate_obby.sh` applies
each one to the real source, runs the entire suite, and puts the file back; the tree is verified
byte-identical afterwards by `sha256sum -c`.

**13 mutations, 12 killed, 2 controls survived.** `(n)` is how many assertions in that suite
failed.

| mutation | Ascent | VaultFloor | Collapse | Curve | headless |
|---|---|---|---|---|---|
| v1's staircase restored (`StepSize` 5, `StepReach` 6) | **1** | **14** | 0 | 0 | 0 |
| the pads never crumble (`CrumbleSeconds` 1e9) | **2** | 0 | 0 | 0 | **5** |
| the pads never come back (`RespawnSeconds` 1e9) | **1** | 0 | 0 | 0 | **4** |
| standing on a pad renews it (a rug, not a crumbling platform) | **1** | 0 | 0 | 0 | **3** |
| the whole shaft reads as one platform (`StandRadius` 5) | **1** | 0 | 0 | 0 | 0 |
| the stand test reads the ROOT, not the feet | **5** | 0 | 0 | 0 | **3** |
| the budget stops paying for the obby (`ModelMissChance` 0) | 0 | 0 | **1** | **1** | 0 |
| the retry leaks into the walk demand (slack pays a premium on it) | 0 | 0 | **1** | 0 | 0 |
| `E[misses] = attempts - n` (the closed form's own first bug) | 0 | 0 | 0 | **1** | 0 |
| the falls are not charged to the storey they land on | 0 | 0 | **3** | 0 | 0 |
| **...nor to the per-storey deadline** | 0 | 0 | 0 | 0 | 0 |
| the SERVER never removes a pad (pure logic intact, no effect) | 0 | 0 | 0 | 0 | **1** |
| the server never notices a runner standing on a pad | 0 | 0 | 0 | 0 | **3** |
| CONTROL: the HUD accent repainted magenta | 0 | 0 | 0 | 0 | 0 |
| CONTROL: an unreachable nil-guard deleted from `Ascent.new` | 0 | 0 | 0 | 0 | 0 |

Plus two mutations inside `tests/VaultFloor.spec.luau`'s own named-check gate, which asserts by
NAME which check notices: v1's tread geometry restored on the built model, and the pads flung to
opposite corners of a jump nobody could make. `climbIsFailable` catches both, and — the point of
naming them — `stairsLineUp` catches **neither**. Every rise is legal, the top pad still meets the
floor above, every pad is still inside the stairwell cell. That is exactly how the vault shipped
with no jump in it anybody could miss.

**One survivor, disclosed in §8 rather than fitted around.** The gate also found a hole in the
spec it was checking: `RespawnSeconds = 1e9` originally survived `tests/Ascent.spec.luau`
entirely. Every assertion in that file was written in units of `RespawnSeconds` and therefore
scaled with it — the shaft was destroyed for the rest of the run and the spec stayed green. The
fix was an absolute ceiling that does not scale (the whole crumble-and-return cycle must be
shorter than one clean climb, so a runner who misses the top hop never comes back to a shaft with
a hole in it), and the mutation dies in that file now as well as in the headless boot. The harness
itself was checked by running the whole suite unmutated first.

The two controls are real edits to real tunables, not no-ops, and nothing noticed either. After
the sweep, `sha256sum -c` reports all five touched source files byte-identical to the baseline.

## 8. What is still open

**The survivor above is not papered over.** Dropping `obbyBy[s+1] / frac(s)` from the per-storey
constraint in `VaultPath.demand` is correct-in-principle and **not currently load-bearing**, and
that is measured rather than assumed. Over the 600 floors the game generates, the worst margin a
demand-pace runner has at any storey is **8.65s with the term and 7.65s without** — the term is
worth one second at the worst point in the game. Over the 1200-maze population at the cap and at
`MinSlack`, where the per-storey constraint actually binds (679 of 1200 mazes, against 436 without
it), it is worth **5.05s against 4.01s**. Nothing separates those cleanly from
`MIN_STOREY_SLACK = 4`, and a threshold chosen to sit between 4.01 and 5.05 would be a threshold
fitted to the mutation, which is worse than an honest gap. It becomes load-bearing if `MinSlack`
comes down or `ModelMissChance` goes up — at *p* = 0.12 the retry is 3.3s per transition and the
term is worth roughly three times what it is worth today.

**`ModelMissChance` is the single largest unknown in this document**, exactly as the explorer
model was the largest one in REVIEW-3. Everything about the shaft's geometry is measured against
Roblox's own gravity and jump; how often a human misses an 8-stud hop onto a crumbling 3x3 pad is
not, and cannot be until somebody plays it. Re-run `measure_curve.luau` §6 after a playtest.
**Do not re-tune the crumble to make the shaft harder before somebody has climbed it.**

**The obby is a minority of the run, and the store copy now says so.** On Gold floor 1 the maze is
about 104 seconds of a 130-second optimal route and the four shafts are about 26. "ROBLOX RAGE
OBBY" as a genre line would still oversell it, so the proposed copy in README leads with the
collapse and names the crumbling pads without claiming the game is a jump tower. The line-by-line
audit of the brief's paste-ready description — eleven lines, of which three are true, two
overstate, five are simply false and one is a promise nobody is rostered to keep — is in README
under "The store description". `docs/marketing/store-text.json` is untouched: it is the live text
for the four PUBLISHED games and Vault Runners is not among them.

**A miss is invisible to the HUD.** The client is told nothing when a pad crumbles or when a
runner falls; the pads simply stop colliding and the seconds go. A player who falls twice on Gold
floor 400 and then gets caught has no on-screen account of where the time went. That is a
presentation gap, not a correctness one, and it belongs with the sound that is also still missing.

**Falling is silent in every sense.** There is no sound, no camera shake, no particle when a pad
goes. `Fx` is already in the tree and already used for the collapse; the shaft does not use it.

**Finding 8's residual is unchanged**, and §5 above is the only thing this pass has to say about
it: a flier still gets straight-line routes through walls at walking pace, and now also skips a
shaft with a banked burst.

---

## Evidence

```
tests/Rng.spec.luau             37 passed, 0 failed
tests/Progression.spec.luau     66 passed, 0 failed
tests/Pets.spec.luau            75 passed, 0 failed
tests/RunState.spec.luau        75 passed, 0 failed
tests/VaultFloor.spec.luau     215 passed, 0 failed   (+14: climbIsFailable and its 2 mutations)
tests/responsive.spec.luau      70 passed, 0 failed
tests/Collapse.spec.luau       281 passed, 0 failed
tests/Curve.spec.luau           23 passed, 0 failed   (+2: the rolled climb vs the closed form)
tests/Ascent.spec.luau          68 passed, 0 failed   (new)
tests/Trace.spec.luau           28 passed, 0 failed   (+1: a burst cannot buy the whole climb)
check_vaultrunners.luau        115 passed, 0 failed   (+9: the pads crumble on the live server)
check_vaulthud.luau            PASS
```

`luau-analyze` on every changed source file: clean, and zero `MisleadingAndOr` across `src/`.
`src/shared/Ascent.luau` needed three `:: { any }` casts — narrowing an `any` with a nil-check
produces `unknown`, which has no keys — and nothing else in the tree emits anything new.
