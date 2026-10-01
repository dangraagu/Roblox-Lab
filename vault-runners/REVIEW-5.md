# REVIEW-5 — the obby review closed, the second eye-candy review closed, three owner decisions applied

Pass 1 of 2, 2026-09-30. One writer in `vault-runners/`. Three jobs:

* **Queued job E**: `docs/reviews/2026-09-10-vault-runners-obby.md` (12 findings on the obby, REVIEW-4).
* **The second eye-candy review** (3 findings, EYECANDY.md §13).
* **The owner's decisions of 2026-09-30** ("take the recommended option for all", EYECANDY.md §10).

Every finding was reproduced first, then a failing test was written and watched failing, then the
GAME was changed. Every number below was measured in this pass. Nothing was committed, pushed or
published, and Studio was not opened.

---

## 1. The obby review (job E)

### 1.1 MEDIUM — hop 1 cannot be missed and was priced as if it could: FIXED

* **Reproduced.** `climbIsFailable` looks at the five pad-to-pad hops only. Hop 1 leaves from the
  storey floor, and the floor under pad 1 is solid, so a fluffed hop 1 lands where a miss would have
  put the runner anyway. `VaultPath` priced `floor(18 / 3) = 6` missable hops.
* **Tests first.**
  * `tests/VaultFloor.spec.luau`: new check `firstHopIsAStep` (pad 1's top is one StepRise over a
    solid floor, under the pad and a runner-width around it), run on 12 shipped vaults, with a
    mutation it must notice (the floor under pad 1 dropped into a pit). And `VaultPath.failableHops`
    must equal the shaft's pad count minus one: it failed (the function did not exist; 6 were priced).
  * `tests/Curve.spec.luau`: the rolled climb now rolls hop 1 as a sure step, 80 000 rolls instead
    of 20 000, tolerance 0.5 % instead of 2 %, and the standard error is asserted small enough for
    the tolerance to mean something. It failed: rolled 6.454 s, priced 6.532 s, **1.19 % apart**
    (standard error 0.14 %). The old 2 % tolerance could not see it.
* **Fix.** `VaultPath.failableHops` (n - 1). A round is hop 1 (sure) plus the missable hops;
  `E[hops] = E[missable attempts] + E[misses] + 1`. `missSeconds` weights missable hop j by q^(j-1)
  and a fall from pad j.
* **Measured.** Priced climb 6.532 s -> **6.445 s** per storey transition (rolled 6.454, 0.14 %
  apart). That is **0.087 s per transition, 0.35 s per five-storey run**. The review estimated about
  0.28 s per transition and 1.1 s per Gold run; that did not reproduce. Gold floor 1's countdown is
  269 s (was 270). Gold completion (Curve.spec's model): f1 98 %, f30 88 %, f100 69 %, f400 51 %,
  still strictly falling.

### 1.2 MEDIUM — the Config comment was wrong by 3.4x: FIXED

* **Reproduced.** `Config.luau` said 0.94 expected falls per transition and 3.7 per Gold run.
  0.94 is `attempts - n`, the closed form's own first bug.
* **Test first.** `robloxemu/check_vaultrunners_static.luau` now reads the comment out of the
  bundled Config and recomputes every number from the bundled `VaultPath`: the missable-hop count,
  the miss chance, the chance of a fall per storey, the falls per transition and per Gold run. It
  failed 5 of 5 on the old comment.
* **Fix.** The comment now says five missable hops at 0.04, 18 %, 0.23 per transition, 0.91 per
  five-storey Gold run (model: 18.46 %, 0.2264, 0.906).

### 1.3 MEDIUM-LOW — the 5 Hz poll and the loose stand box: FIXED

* **Reproduced, both directions.**
  * Too loose: `padUnder(pad.x - 3, pad.y + 3)` returned the pad, 1.5 studs out into the gap.
  * Too slow: new `check_vaultrunners_shaft.luau` §6 climbs storey 0's shaft the way physics carries
    a runner (Roblox's JumpPower and Gravity, a hop that lands on the next pad's top, one frame of
    contact), at four phases of the server tick, on Bronze 1 and Gold 1. **18 of 48 pad landings
    were never counted by the server**, so those pads never crumbled. Worst landing-to-drop 1.317 s.
    The CONTROL half (a 0.25 s stand on every pad) crumbled every pad on both builds.
* **Fix.**
  * `Config.Ascent.StandRadius` is derived: `StepSize / 2 + RunnerWidth / 2` = 2.5 (was 3).
  * The server watches the runner and the shaft every `Config.Ascent.SampleSeconds` (0.05 s):
    `watchRunner` steps `Trace`, touches the pad under the trusted position and draws the flips.
    The gems, the exit, the collapse and the seal are still judged every `Run.TickSeconds` (0.2 s),
    against the position `watchRunner` left. One clock (`a.elapsed`) for both.
* **After.** 0 of 48 landings missed, worst landing-to-drop 1.067 s. `tests/Ascent.spec.luau`
  pins the radius to its derivation and both sides of the edge.

### 1.4 The LOW and INFO findings

| # | finding | result |
|---|---|---|
| 4 | `obbyBy[top]` charged a climb out of the top storey, and Collapse.spec pinned the wrong value | FIXED. Collapse.spec now wants `(storeys - 1) * retry` for the top entry; it failed (3.135 vs 2.090). `VaultPath.measure` caps it. |
| 5 | `ModelReapproachSeconds` claimed to cover the wait for a crumbled pad | FIXED (the sentence). The wait is not modelled; measured on the real server it is 0.46 s per fall (22.2 s over 48 falls, `walk_vaultrunners.luau`), about 0.4 s per priced Gold run. |
| 6 | no guard for `ModelMissChance >= 1` | FIXED. `VaultPath` refuses it by name. Curve.spec: 1, 1.5 and -0.1 are refused (they priced inf, 83.0 and 5.4 s before); 0.9 is still finite. |
| 7 | the top pad crumbled under a runner standing on the floor above | FIXED by 1.3's radius. A runner on the floor's lip with their body clear of the pad (2.8 studs from its centre) is not on it; with radius 3 they were (Ascent.spec). One whose body still overlaps it is. |
| 8 | a comment justified the flip loop's placement with a respawn that cannot happen | FIXED (rewritten in `watchRunner`: `onCharacter` ends the run on every respawn). |
| 9 | INFO: Collapse.spec's tightest margin was a 600-floor sample | Collapse.spec now sweeps 3 x 800 floors: countdowns 68-272 s, tightest storey +7.70 s (Silver 661, storey 0), tightest escape +33.1 s. |
| 10 | INFO: the rolled climb is not independent of the physical model | Disclosed, not changed. It now rolls hop 1 as sure, but it still shares `fallSeconds`, `ModelReapproachSeconds`, p and n with the closed form. |
| 11 | latent: `padUnder` stopped at a gone pad instead of scanning on | FIXED. Ascent.spec: on a made-up shaft with a gone pad over a solid one it returned nil; now the solid one. Also asserted: in the shipped vaults no two pads at feet-band height are within two stand boxes of each other. |
| 12 | latent: a flip for a pad with no part would leave the pad stuck | FIXED. `buildVault` refuses to build a vault in which any Ascent pad has no part. |

`mutate_obby.sh` (the obby's own gate) had gone stale: four of its thirteen targets no longer
existed, and it applied mutations with a bare `replace` that reports nothing when it misses. It now
refuses a mutation whose target is not in the file exactly once, runs the shaft and static checks
too, carries REVIEW-5's mutations, and says to run it on a scratch copy. Result in §4.

---

## 2. The second eye-candy review

### 2.1 LOW — only the weather budget was capped at runtime: FIXED

* **Reproduced.** New `robloxemu/check_vaultrunners_budget.luau` forces, in memory only, props in
  every cell (§1) and budgets below the scene (§2: 2 emitters, 20 particles/s, 0 lights, 1 beam).
  On the unfixed build: **235 client parts** against 180 (the reviewer's number exactly), and 3
  emitters, 57 particles/s, 1 light and 3 beams against the forced budgets.
* **Fix.** In `VaultArt`: every parenting is counted (`live`); props are hung only while they fit
  under `MaxLocalParts` less a 31-part headroom for the telegraph, the pad cracks and the debris;
  `enforceBudget` (last thing in every client frame) takes props and then debris down if anything
  still passes the cap, grants emitters by priority (the drop's trickle, then the collapse's sparks
  and dust, then the weather) through the new pure `VaultEnv.grantRates`, and caps lights and beams.
* **After.** 173 parts at most with props in every cell and drops in the air; the props on the
  runner's storey do not change while a drop hangs over it (132 before, 132 during: the headroom is
  reserved, not taken); 2 emitters, 20.0/s, 0 lights, 1 beam with the forced budgets; the drop's
  trickle on for every frame a chunk hung. §3,
  the CONTROL, shows the shipped numbers cap nothing: every prop storeys 0-1 ask for is hung, all
  three aurora ribbons are drawn. The reviewer's side note reproduced: over 360 floors the most prop
  parts on one storey pair is 75 (Bronze 31, storey 0).

### 2.2 LOW — gems and the exit wore the pads' colour: FIXED, and it was wider than reported

* **Reproduced** (EnvConfig.spec, every tier, depths 0-100 in 1/8 steps, RGB distance gem to pad):
  tomb pearl vs cream 41.5, Frozen Vault sapphire vs navy 41.8, and two the review did not name:
  **Bronze's orange vs the bank's gold pads 39.9** (the first four floors of the game) and **Gold's
  own gems vs the volcano's bone pads 70.8** (every Gold floor).
* **Fix.** `Config.Env.MinGemPadDistance = 80` is part of `VaultEnv.readableGem`: a colour closer
  than that to the pad painted on the same floor does not count as reading. Four palette entries
  changed so no depth needs the black-or-white fallback: bank pads marble (215, 210, 200), tomb pads
  gilded (255, 226, 60), Frozen Vault gems amethyst (120, 40, 190), volcano pads jade (80, 220, 190).
* **After.** Worst distance 100.0 (Bronze), 100.0 (Silver), 90.9 (Gold). As painted through the
  real client (`check_vaultrunners_readable` §1): tomb 176.6, Frozen Vault 100.0, volcano 188.6.
  Every earlier bar still holds: pad/floor 5.64, pad/wall 1.62, cracked pad/floor 3.06, gems 4.70
  against the floor and 1.82 against the wall at worst. Gold keeps its own gem colour in the volcano.

### 2.3 LOW — CLAUDE.md and EYECANDY.md said "uncommitted": FIXED

`git log` shows the eye candy committed as 511793d. Both files now say so.

---

## 3. Owner decisions (2026-09-30: "take the recommended option for all")

| decision | taken | measured |
|---|---|---|
| **the pacing target** (the brag at 30-45 min, docs/complete-game-standard.md §2) | the Frozen Vault from depth 24 (fade 4) to depth 18 (fade 2) | normal player 40.8 / 37.9 min (was 61.8 / 61.2), fast 32.6 / 32.6, slow 54.2 / 62.5; reactor still 25.7 / 23.8, volcano 135.3 / 134.9. Pacing.spec asserts 30-45. |
| **near-hits in a maze** | leave it, the option argued for: it rewards moving, never punishes a mover, and the two alternatives either change little (a 1.0 s lock, a sixth closer) or hit players who keep moving | no code change; Pacing: one drop per 2.60 run-minutes, reacting players hit 0 of 170 |
| **the endgame is one stratum** | no option was marked, so the one that serves "never monotonous" in the endgame itself: halls inside the volcano (a sixth stratum only moves the last room further down) | past depth 44 the Volcano Temple turns through the Magma, Obsidian and Ash Halls every 4 depths, for ever; light, weather and props change, the palette does not. A normal player sees 38 hall changes in two 8-hour careers, 6.7-21.1 min per hall. |

The halls are held by `VaultEnv.spec` (the rule), `EnvConfig.spec` (the config), `Pacing.spec`
(minutes) and the new `robloxemu/check_vaultrunners_halls.luau` (68 assertions through the real
client: the chip, weather, props, light, pads and floor, and a card per hall with the fanfare only
for a hall deeper than any floor cleared). Its first version failed 21 of 52 before the client glue
existed; the sweep then showed it could not see a fanfare on every hall (§4, D7), so it now also
returns to a shallower hall once the client knows the cleared floors.

---

## 4. Mutation sweep

Run on scratch copies of `vault-runners/` and the robloxemu files it needs (the real tree was never
mutated), by `scratchpad/vr5/sweep.py`. For each mutation: every target text found exactly once (else
refused), the bundle rebuilt and **proved** to carry the mutation (the rebuilt bundle equals the
baseline bundle with the same replacement), all 26 gates run, the file restored and its sha256
checked. After each sweep every scratch source was byte-identical to its baseline (sha256).

**Round 1: 38 mutations and 5 controls.** 33 killed; 5 survived; 4 controls survived and 1 was
noticed. Every one of the six was followed up:

| id | mutation | round 1 | what was done | final |
|---|---|---|---|---|
| E2 | a miss off pad j priced as a fall from pad j-1 (0.28 % of a climb) | SURVIVED: inside the rolled climb's 0.5 % | Curve.spec now also rolls the cost of one MISS (18 213 rolled misses, 1 % tolerance) | **killed** (Curve) |
| B1a | props hung without the parts allowance | SURVIVED: the per-frame cap trimmed them | budget §1: the props on the runner's storey must not change while a drop hangs (the headroom is reserved, not taken) | **killed** (budget) |
| B1j | no headroom for the telegraph | SURVIVED: same | same | **killed** (budget) |
| D7 | a fanfare for every hall | SURVIVED: the only no-fanfare case ran before the client knew the cleared floors | halls check returns to a shallower hall afterwards | **killed** (halls) |
| B1g | the per-frame parts cap removed, headroom intact | SURVIVED | disclosed: belt and braces. It only acts if the headroom is ever wrong; with both removed (B1k) the parts budget is broken and the check kills it | survives, by design |
| C5 | CONTROL: the shaft looked at 0.04 s instead of 0.05 s | NOTICED by `check_vaultrunners` (2) | the check left the runner hovering where a crumbled pad had been; the returning pad was re-touched and crumbled again, and the assertion landed in that second cycle depending on sampling phase. The check now drops the runner to the floor, as gravity would (the same fix §12 made to env §6) | **survives** |

Killed in round 1 and unchanged since (33): E1 (Curve, Pacing, VaultFloor, static), E3 (Curve), E4
(Curve, Pacing, static), E5 (Collapse), E6 (Ascent), E7 (shaft §6), E8 (Ascent), E9 (every headless
check: the vault refuses to build), E10 (static), B1b-e (budget), B1f (VaultEnv), B1h (budget), B1i
(budget, cards, env, halls, hazards, shaft), B1k (budget), B2a (EnvConfig, VaultEnv), B2b
(EnvConfig), B2c (EnvConfig, readable), B2d (EnvConfig), B2e (EnvConfig, VaultEnv), B2f (EnvConfig,
readable), B2g (EnvConfig), D1 (Pacing), D2 (Pacing, VaultEnv, halls), D3-D6 (halls), D8 (halls), D9
(Pacing, halls), D10 (halls).

**Follow-up rounds** on fresh scratch copies of the final tests: E2, B1a, B1j, B1k, D6, D7 and a
re-run of E7 killed; B1g survived; controls C1, C2, C3, C4 and C5 survived.

**A hang, found by the sweep.** The pads-never-come-back mutant (RespawnSeconds 1e9, E11) did not
fail: it hung `check_vaultrunners_env` §6 and `check_vaultrunners_shaft` §5, whose frame loops waited
`RespawnSeconds + 1` seconds for the pad to return — 6e10 frames. The same shape was in the shaft §6
hopper and in the headless check's `h:advance`. All four are now capped (20, 10, 5 and 30 s), and both
harnesses kill a suite after 600 s and report it. E11 is then killed by Ascent (1), the headless check
(3), env (6) and shaft (12); CrumbleSeconds 1e9 (E12) by Ascent (2), headless (4), env (9) and shaft
(21).

**Final: 40 mutations (38 + E11, E12), 39 killed, 1 survivor by design (B1g); 5 of 5 controls
survive.**

`mutate_obby.sh`, run on its own scratch copy after the fixes above: **21 mutations, 20 killed, 1
survivor, 0 not applied; both controls survived; every mutated file sha256-identical afterwards.** The
survivor is REVIEW-4 §8's disclosed one (the per-storey obby term in `VaultPath.demand` is not yet
load-bearing), unchanged. Its four stale targets were retargeted (§1.4).

---

## 5. Gates at the end of pass 1

Run on the real tree after a fresh bundle build (`py -3 wrap.py --game ../vault-runners`):

| gate | before (EYECANDY §12) | REVIEW-5 |
|---|---|---|
| 16 specs (`tests/*.spec.luau`) | 1 733 / 0 | **1 830 / 0** |
| `check_vaultrunners.luau` | 138 / 0 | 138 / 0 |
| `check_vaulthud.luau` | PASS | PASS |
| `robloxemu/check_vaultrunners_env` | 255 / 0 | 255 / 0 |
| `robloxemu/check_vaultrunners_hazards` | 50 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_shaft` | 53 / 0 | 63 / 0 |
| `robloxemu/check_vaultrunners_cards` | 20 / 0 | 20 / 0 |
| `robloxemu/check_vaultrunners_static` | 86 / 0 | 91 / 0 |
| `robloxemu/check_vaultrunners_readable` | 47 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_budget` (new) | — | 15 / 0 |
| `robloxemu/check_vaultrunners_halls` (new) | — | 68 / 0 |
| **headless total** | **649 / 0 + PASS** | **750 / 0 + PASS** |

Per spec: Ascent 77, Collapse 282, Curve 29, EnvBands 124, EnvConfig 401, Hazards 91, Pacing 51,
Pets 75, Progression 66, Rest 55, Rng 37, RunState 75, Trace 28, VaultEnv 138, VaultFloor 231,
responsive 70. There is no `tests/*.check.luau` in this game.

Still open (not in this pass's brief): nobody has played it or seen it in Studio; the halls and the
new pad and gem colours join EYECANDY.md's Studio list (§8.6, §8.17); docs/complete-game-standard.md
§3's highscore board, a `MARKETING.md` clip list and a store text under 1000 characters are not built.
The first run of a session cannot fanfare (the client hears the cleared floors just after "start");
the halls check orders its cases around that rather than changing it.

---

## 6. Pass-1 re-run, 2026-10-01: checked again, not redone

The workflow started pass 1 again ("try again"). The tree it found already held §1-§5, uncommitted,
plus a highscore board that a later pass had started and not finished (CLAUDE.md, State). This re-run
treated that tree as unverified. It reproduced every finding on **HEAD 511793d** (the snapshot the
reviewers read) and measured it fixed in the working tree. It ran the current tests against HEAD's
`src/` to show they fail there, measured the owner's decisions again and ran the mutation sweep again.
One writer. Nothing was committed, pushed or published, and Studio was not opened.

### 6.1 The second eye-candy review, finding by finding

| finding | on HEAD 511793d | in the working tree |
|---|---|---|
| 1 budgets not capped | the reviewer's own mutant (reactor prop density 1.0): `check_vaultrunners_env` 254 / 1, **peak 235 parts** on Bronze 14. The current `check_vaultrunners_budget` on HEAD's source: 13 / 2 (§1 peak 245 parts with a drop hung; §2 3 emitters, 57.0/s, 1 light and 3 beams against a forced 2, 20, 0 and 1) | the same mutant: env 255 / 0, peak **160** parts; budget 15 / 0 (peak 173; the forced budgets hold on every frame) |
| 2 gems and exit wear the pads' colour | tomb 1.12:1 and **41.5** RGB apart, Frozen Vault 1.02:1 and **41.8**, bank 39.9, volcano 70.8. `check_vaultrunners_readable` on HEAD's source: 47 / 3 | worst 100.0 (Bronze), 100.0 (Silver), 90.9 (Gold); as painted 176.6 / 100.0 / 188.6. Cross-checked in a second metric (CIE76 ΔE): HEAD's closest playable pair 14.3 (the tomb); now the closest of all 12 pairs is 41.2 |
| 3 stale "uncommitted" | CLAUDE.md:7 and :9, EYECANDY.md:15, :782 and :1011 | gone, or annotated "committed later as 511793d" |

§2.1 said the budget check read "235 ... the reviewer's number exactly" on the unfixed build. That was
the check's first version. Since the B1a follow-up its §1 also hangs a drop, and on HEAD's source it
now reads 245. The reviewer's 235 is still exactly what env §9 reads with the reviewer's mutant.

### 6.2 The obby review (job E): the tests fail on HEAD's source and pass now

The current specs and checks, run against HEAD's `src/`:

* `Curve` 24 / 5: the rolled climb 6.454 s against 6.532 s priced (1.19 % apart); a miss priced
  1.0356 s against 1.0895 s rolled; ModelMissChance 1, 1.5 and -0.1 not refused.
* `VaultFloor` 228 / 3 (no `failableHops`). `Ascent` 72 / 5 (StandRadius 3; 1.5 studs out into the gap
  counted as on the pad; the top pad under a runner on the floor above; a gone pad hiding a solid one).
  `Collapse` 280 / 2 (the top storey charged 3.396 s, want 2.264 s).
* `check_vaultrunners_shaft` 54 / 9: **18 of 48** chained landings never counted, worst 1.317 s from
  landing to drop. `check_vaultrunners_static` stops at its line 102 (no `VaultPath.failableHops`), and
  HEAD's Config still says "0.94 ... 3.7".

In the working tree all of these pass. The climb is priced 6.445 s against 6.454 s rolled (0.14 %), a
miss 1.0888 s against 1.0895 s; Gold floor 1's countdown is 269 s; Gold completion f1 98 %, f30 88 %,
f100 69 %, f400 51 %; **0 of 48** landings missed, worst 1.067 s; tightest storey +7.70 s (Silver 661),
tightest escape +33.1 s, countdowns 68-272 s over 3 x 800 floors.

Two things checked by hand. The comment's numbers: at p = 0.04 and five missable hops, the chance of a
fall per storey is 1 - 0.96^5 = 18.46 %, the falls per transition are (1 - q^5) / q^5 = 0.2264, and a
five-storey run has four transitions: 0.906. And the 20 Hz watch hands a cheat nothing: `Trace.step`
scales its allowance by `dt` and banks it up to a cap, so four steps of 0.05 s grant the same distance
as one of 0.2 s.

### 6.3 The owner's decisions

All three are recorded in EYECANDY.md §10 as "DECIDED 2026-09-30 (owner: take recommended)". Measured
again (`Pacing.spec`): a normal player first runs the Frozen Vault at 40.8 / 37.9 minutes (fast
32.6 / 32.6, slow 54.2 / 62.5); 38 hall changes in two 8-hour careers, 6.7-21.1 minutes a hall; one drop
per 2.60 run-minutes, and reacting players are hit by 0 of 170. There is no other open owner decision
in EYECANDY.md, CLAUDE.md or REVIEW*.md: the "store page" decision of REVIEW-2 and REVIEW-3 was
closed by building the obby (REVIEW-4).

### 6.4 What this re-run found, and what it changed

* **`Config.Budget`'s comment** still said the budgets were "measured every frame by
  check_vaultrunners_env". It now says they are caps and what enforces each one. Comment only: the
  sweep ran it as control C6, and nothing noticed it.
* **`MaxHazards` is the one budget no code reads.** Its cap is structural (`Hazards` has one
  `state.active` slot; `Hazards.spec`: never more than one drop at a time), and `EnvConfig.spec` pins
  the number to 1. CLAUDE.md invariant 13 said "every Config.Budget is a CAP in code"; it now says
  which kind of cap this one is.
* **The gem rule covers the resting pad, not a crumbling one.** Every stratum shares the crack colour
  (255, 90, 50), an orange red, and a crumbling pad is pulled 70 % of the way to it. Under a Bronze
  runner (orange gems; Bronze floors 1-400) it passes **44.6** RGB from the gem in the Bank Vault (at
  81 % of the crumble), and ends 60.9 away in the reactor and 70.5 in the Frozen Vault and the
  volcano. Silver stays 81.5 or more away, Gold 110.2. At HEAD the bank's gold pad cracked to within
  9.8 of the gem. It is only ever the pad under the runner's own feet (gems are never placed in an
  entry or exit cell), and only while it goes. **Not changed; on the Studio list (EYECANDY.md §8.6).**
  A crack colour dark enough to keep the bank's whole path 80 away, for example (200, 20, 60) at
  80.9, reads 1.96:1 against the bank's floor, under the 2:1 bar for a pad about to go. That trade
  needs eyes, not numbers.
* **The bundle on disk was stale** at the start: built at 00:47, two minutes before the last edit to
  `Main.server.luau`. It was rebuilt before every run.
* **The board WIP was left alone.** CLAUDE.md now describes it, with one gap it has: `bestAt` is
  stamped at load only, never on a new deepest escape, so a new player's first board write would
  carry reach time 0 and win every tie. Its check already fails on exactly that ("stamped when he got
  there").

### 6.5 The mutation sweep, again

`scratchpad/vr6/sweep6.py` ran §4's 40 mutations and 5 controls, plus control C6, on scratch copies
of a frozen snapshot of the tree. For each one: the target found exactly once (else refused), the
rebuilt bundle **proved** equal to the baseline bundle with the same replacement, every gate run, and
the file restored and its sha256 checked. The board check is red before any mutation, so a gate counts
as noticing a mutant when its result differs from the baseline's.

**40 mutations: 39 killed and 1 survivor (B1g, the per-frame parts guard removed with the headroom
intact, the survivor §4 disclosed). 6 of 6 controls survived. 46 of 46 bundles were proved, and every
scratch source was sha256-identical afterwards.** The kills match §4: E1 by Curve, Pacing, VaultFloor
and static; E2 and E3 by Curve; E4 by Curve, Pacing and static; E5 by Collapse; E6 by Ascent; E7 by
shaft (9); E8 by Ascent; E9 by every headless check (the vault refuses to build); E10 by static; E11
and E12 by Ascent, headless, env and shaft; B1a-e, B1h, B1j and B1k by budget; B1f by VaultEnv; B1i by
budget, cards, env, halls, hazards and shaft; B2a-g by EnvConfig (plus VaultEnv or readable for a, c,
e and f); D1 by Pacing; D2 by Pacing, VaultEnv and halls; D3-D8 and D10 by halls; D9 by Pacing and
halls.

### 6.6 Gates at the end of the re-run

After a fresh bundle build, on the real tree:

| gate | §5 | §6 |
|---|---|---|
| the 16 specs of §5 | 1 830 / 0 | 1 830 / 0 |
| `tests/Board.spec` (WIP) | — | 69 / 0 |
| `check_vaultrunners.luau` | 138 / 0 | 138 / 0 |
| `check_vaulthud.luau` | PASS | PASS |
| `robloxemu/check_vaultrunners_env` | 255 / 0 | 255 / 0 |
| `robloxemu/check_vaultrunners_hazards` | 50 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_shaft` | 63 / 0 | 63 / 0 |
| `robloxemu/check_vaultrunners_cards` | 20 / 0 | 20 / 0 |
| `robloxemu/check_vaultrunners_static` | 91 / 0 | 93 / 0 (Board.luau is one more module: it compiles, and has no string require) |
| `robloxemu/check_vaultrunners_readable` | 50 / 0 | 50 / 0 |
| `robloxemu/check_vaultrunners_budget` | 15 / 0 | 15 / 0 |
| `robloxemu/check_vaultrunners_halls` | 68 / 0 | 68 / 0 |
| `robloxemu/check_vaultrunners_board` (WIP) | — | **RED: 30 FAIL, then it stops at line 381** (no `client/Board.client`) |

Specs: 1 899 / 0 over 17 files. Headless: 752 / 0 plus PASS over 10 checks, with the board check red
as above. There is no `tests/*.check.luau` in this game. Files written by the re-run:
`src/shared/Config.luau` (the Budget comment), `CLAUDE.md`, `EYECANDY.md`, this section, and
`robloxemu/build/vault-runners.luau` (rebuilt).
