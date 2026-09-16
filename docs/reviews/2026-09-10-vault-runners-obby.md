# Adversarial review of the Vault Runners obby — 2026-09-10

Filed here rather than in `vault-runners/` because when it landed, that directory was owned by
another agent. **Act on it after the spawn-order workflow finishes.**

The reviewer read a tree that was moving under it: the author edited `Ascent.luau`, `Config.luau`,
`Main.server.luau` and `REVIEW-4.md` between 09:27 and 09:34, and ran `mutate_obby.sh` — which
mutates real source in place — between 09:30 and 09:36. Everything below is pinned to the 09:38
snapshot: `Ascent.luau dba8198`, `Config.luau 623122c`, `VaultPath.luau 2473bb6`,
`VaultFloor.luau 081bacf`, `Main.server.luau ae9a10c`, `REVIEW-4.md ecabe4e`. Suite green at that
snapshot: Ascent 68/0, VaultFloor 215/0, Collapse 281/0, Curve 23/0, Trace 28/0, headless 115/0.

That overlap is the hazard [[feedback_parallel_mutators_contaminate]] describes, and the reviewer
handled it the right way — by measuring one fixed snapshot and naming it — rather than reporting
the author's in-flight mutations as defects.

## Found live and already fixed by the author mid-review

`Ascent.padUnder` measured vertical from the runner's **root**: `dy = pos.y - pad.y` in
`[0, StandHeight]`. `Vault.StepRise == Run.RunnerRootHeight == 3`, so a runner standing on the
storey floor beside pad 1 had `dy == 0` exactly and was reported as standing on pad 1 — the pad
began crumbling while they were still walking toward it. Now `(pos.y - RunnerRootHeight) - pad.y`
in `[-stepRise/2, StandHeight]`, `StandHeight` cut 5 → 2. No action needed.

## Open, ranked

### 1. MEDIUM — hop 1 of 6 cannot be missed, is never checked, and is priced as if it can be

`tests/VaultFloor.spec.luau:334` loops `for k = 2, #pads`. It checks the five pad-to-pad hops and
never the floor→pad-1 transition — which has **zero open air**: storey `s`'s floor hole is at
`entryCell(s)` and the shaft at `exitCell(s)`, so the floor under pad 1 is solid, and pad 1 (3×3
at ±4) leaves 8.5 studs of floor on its west side. The runner stands 0.5 studs clear of the pad
edge and hops 3 studs up over ≤3 studs of travel against a 10.565-stud reach: **28% of the jump**,
below `climbIsFailable`'s own `REACH_FLOOR = 0.6`. If the check looked at it, it would reject it as
a staircase.

Meanwhile `VaultPath.climbAttempts` / `missSeconds` and `tests/Curve.spec.luau:154` all use
`n = floor(storeyHeight/stepRise) = 6` independently-missable hops. **Five failable hops priced as
six.** The direction is safe — the countdown over-pays about 0.28 s per transition, ~1.1 s per Gold
run — but REVIEW-4 §1's "`climbIsFailable` holds both ends of that at every pad of every shaft" and
§2's "Six hops, each missed with probability *p*" are not supported by the code.

### 2. MEDIUM — the spec comment states the exact defect the review says it caught

`src/shared/Config.luau:282`: `-- and 0.94 expected falls per storey transition — about 3.7 falls
in a five-storey Gold run.` The code computes **0.2775** per transition and **1.110** per run, and
`REVIEW-4.md:206` says 1.11. `0.9384` is precisely `attempts - n` (6.9384 − 6) — the closed form's
own first bug, the one §2 says the rolled climb caught and §7 keeps as a live mutation.

Nothing reads the comment. But this repo's whole method is that the comment is the spec, and this
is the file declared to be the single table of numbers.

### 3. MEDIUM-LOW — the crumble is a 5 Hz poll, and its box is looser than the pad

`Main.server.luau:696-698` calls `Ascent.padUnder` once per `Run.TickSeconds` (0.2 s) against the
trusted position. No `Touched`, no `FloorMaterial`, no raycast. Both directions are wrong:

- **Misses one it should catch.** The feet band is `[-1.5, +2]`. A 3-stud hop has 0.44 s of flight;
  a player who re-jumps on the landing frame — which Roblox permits — has ~0.1–0.2 s of ground
  contact per pad, and the poll phase is fixed, so a chained hopper can cross pads without ever
  being sampled inside the band. The mechanic weakens for exactly the players it is aimed at.
- **Catches one it should not.** `StandRadius = 3` against a pad half-extent of 1.5 is a full
  pad-width of tolerance. Verified: `padUnder(x = pad1.x - 3, y = pad1.y + 3)` returns pad 1 — 1.5
  studs out into the 5-stud gap. A runner who landed short and is about to fall is recorded as
  having stood on the pad, and starts its crumble. The defensible bound is
  `1.5 + RunnerWidth/2 = 2.5`.

`tests/Ascent.spec.luau` pins `StandRadius` only to `(1.4, 4)` — lip probe at 1.4, midpoint at 4 —
so neither end is held.

### 4. LOW — `VaultPath.luau:334`: `obbyBy[model.storeys]` counts a climb out of the top storey

`obbyBy[s+1] = (s+1) * climbRetry` runs for `s = 0 .. storeys-1`, so the top entry is
`storeys * climbRetry` while there are only `storeys-1` transitions. `demand` never reads it, so it
is dead — but `tests/Collapse.spec.luau:338-341` asserts the dead entry **at the same wrong value**.
A spec that pins an off-by-one is not a guard against it.

### 5. LOW — `ModelReapproachSeconds` is documented as covering a wait it does not model

`Config.luau:284-287` says the 0.8 s includes "the wait when the pad you fell off has not respawned
yet"; `missSeconds` is `E[fall] + 0.8` and nothing else. With `CrumbleSeconds + RespawnSeconds =
4.1` and a 0.9 s hop, a miss on hop 2 puts the runner under pad 1 at ~1.9 s against a pad returning
at 4.1 s — 2.2 s of waiting; hop 3 waits 1.25 s, hop 4 waits 0.30 s, hops 5–6 none. Weighted by the
conditional miss distribution that is ~0.65 s per miss the model does not carry. Corroborated on
the real server: `walk_vaultrunners` reports 3.6 s of waiting across the solver's six falls on Gold
1. Magnitude is negligible (~0.7 s per Gold run against 270 s). The Config sentence is what is
wrong.

### 6. LOW — `VaultPath.luau:265` has no guard for `p >= 1`

`if p <= 0 then return n, 0 end` handles the bottom. At `p = 1`, `qn = 0` and line 268 divides by
zero: an infinite countdown and an infinite-slack vault. `Config.luau:274-282` explicitly invites
re-tuning `ModelMissChance` after a playtest and `measure_curve.luau` §6 sweeps it, so an
out-of-range value is a plausible edit rather than an impossible one.

### 7. LOW — the top pad crumbles when the runner stands on the permanent floor above it

Pad 6's top is flush with storey `s+1`'s floor top and its centre sits 2 studs inside the 12-stud
hole, so with `StandRadius = 3` a runner up to 1 stud past the hole edge, on solid floor, registers
on pad 6. `tests/Ascent.spec.luau:117-120` now declares this correct by fiat, which contradicts
`Ascent.luau`'s own rule — a pad holds for `CrumbleSeconds` after the runner *first stands on it*.
Same root-vs-geometry looseness as finding 3, resolved in the harmless direction.

### 8. LOW — `Main.server.luau:716-718` justifies its placement with a scenario that cannot occur

"a respawn mid-climb finds a shaft with holes in it that never fill" — `onCharacter` fires
`finishRun(plr, "collapse")` on every `CharacterAdded`, so a respawn tears down the vault, the
`padParts` and the `ascent` state together. The placement outside `if hrp` is still right (a
transiently nil `HumanoidRootPart`); the reason given is not.

### 9. INFO — the tightest per-storey margin degrades outside the sampled range

`tests/Collapse.spec.luau` checks 3 tiers × 200 floors and prints `+9.7s`. Over 3 × 800 floors the
tightest is **+7.81 s** — still well over `MIN_STOREY_SLACK = 4` — and the max countdown 273 s (Gold
floor 3), 27 s under `MaxSeconds`. No breach, but §3's 9.7 s is a 600-floor figure quoted as the
game's floor.

### 10. INFO — the rolled climb's "independence" is narrower than §2 implies

`tests/Curve.spec.luau:154-172` avoids `VaultPath.climbSeconds` but re-uses `fallSeconds`,
`ModelReapproachSeconds`, the same `p` and the same `n`. It validates the combinatorics — which is
what caught `attempts - n` — and nothing about the physical model. It cannot see finding 1 or
finding 5, because it shares both assumptions.

### 11-12. INFO / latent

`Ascent.luau:127-130` returns on the first horizontally-matching pad even when that pad is gone,
instead of continuing the scan — correct today only because no two pads can be within `StandRadius`
of one position, and nothing asserts that precondition. And `Ascent.update` commits `state.shown[k]`
before the server has written the part, while `Main.server.luau:720` drops the change when
`a.padParts[...]` is nil: unreachable today, but the failure mode is "a pad stuck gone", which
`Ascent.luau`'s header promises cannot happen.

## Where the reviewer found nothing, having looked

- **The crumble state machine is clean** post-fix. `solid` is gone at exactly `t0 + Crumble` and
  back at `t0 + Crumble + Respawn`; `expire` drops an entry at the same threshold at which `solid`
  returns true for a missing one, so no window exists in which expiry makes a pad vanish. `touch`
  refuses to renew a crumbling pad, restarts a returned one, and survives a non-monotonic clock.
  Nothing grows without bound; no two runs share state.
- **No unwinnable vault** over 3 tiers × 800 floors: max countdown 273 s ≤ 300, tightest storey
  margin +7.81 ≥ 4, tightest escape +32.9 ≥ 8. Every pad returns unconditionally.
- **The shaft geometry is physically sound**: 5.0 studs of open air against a 2-stud runner, 76% of
  a 10.565-stud reach, 3-stud rises that cannot be walked up, 0.5 studs from pad edge to stairwell
  wall. The only bypass is client authority over physics, which REVIEW-4 §5 states plainly — a
  teleporting client up the middle of the stairwell is 4 studs from every pad centre, outside
  `StandRadius = 3`, so it crumbles nothing and ascends at 8.333 studs/s against an honest 3.33.
- **REVIEW-4's numbers reproduce** where checkable. §6's "48.4 s / 8.5 s in hand / 20%" were wrong
  when first read and the author corrected them to 50.9 / 7.1 / 34% at 09:34; 34% is what
  `planeFractionAt(killLines[1])` gives for a three-storey vault.
