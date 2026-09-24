# Fork Tower — fifth pass: the trap plan was computable on the client

**Scope.** One finding, measured 2026-09-17, fixed, and measured again. Nothing committed, pushed or
published. Read after REVIEW-3.md (whose attribute gating this pass shows was necessary and not
sufficient) and STUDIO.md.

> **Read §9 too.** An adversarial pass on the fix in §1–8, the same day, won 240 of 240 forks with
> no read paid: a READ-ONLY session planned the SAVED secrets and saved nothing, so it was a free
> oracle for the run the player went back to. §9 is that finding, the fix, and its measurement.
> §1–8 are kept as written, except §8 item 5, which §9 proved wrong.
>
> **And §10.** §9's trust rule took "the record is released" to mean "the last session wrote its final
> state", and §9.8 item 4 said the rule did not depend on write order. It did: a shutdown writes two
> releases per player, and a late one re-released a record the next session had already trusted and
> revealed from (120 of 120 in the emulator). §10 adds an owner to every write.

```
                           before (sources as of 2026-09-10)    after
Fork.spec                  53 passed, 0 failed                  71 passed, 0 failed
Section.spec               50 / 0                               50 / 0
Build.spec                 31 / 0                               31 / 0
Codes.spec                 19 / 0                               19 / 0
Rng.spec                   32 / 0                               32 / 0
responsive.spec            70 / 0                               70 / 0
world.check                71 / 0                               71 / 0   (file unchanged)
check_forktower           129 / 0                              129 / 0   (seeded profiles carry secrets)
check_forktower_plansecret  (new) 24 passed, 17 failed          41 passed, 0 failed
readcost.measure           break-even 1.110 s                   break-even 1.110 s (to the digit)
```

`luau-compile --binary` clean on Fork.luau, Config.luau and Main.server.luau. `luau-analyze` reports
nothing on Fork.luau, Fork.spec, Build.spec or readcost.measure, and only Roblox-global noise
(`Unknown global`/`Unknown type`, 170 lines) on Main.server.luau and the two robloxemu checks.
`find_mojibake.py` reports nothing.

---

## 1. The finding

`src/shared/Fork.luau` lives in ReplicatedStorage. It derived every floor — trap side, liar line,
tell, traits, sign carvings — from `Config.WorldSeed` (replicated) and the run seed, and the run seed
is `leaderstats.Rebirths + 1` (replicated). A probe read 30 forks honestly over 3 runs and compared
them with `Fork.plan(Config, Rebirths.Value + 1, Rng).floors[level].trapDoor` computed from
ReplicatedStorage modules only: **30 of 30**.

REVIEW-3 had removed `TellKind`, `RuleInverted` and `Marked` from unread forks and enumerated the
wire to prove it. That was correct and it stopped nothing: an exploiter never needed the attributes,
they had the generator. Every read an honest player stood still `Config.Fork.ReadSeconds` for was free
to a script, and the 1.110 s break-even that prices the read described a game only honest players
were playing. Also true and worse: two players on the same run seed had the SAME tower, so a player
could read the traps off anyone else's already-climbed sections.

Every fairness assertion in Fork.spec passed the leaking generator. Balance, readability, sign
exchangeability and prize neutrality are all properties a public generator can have. Witness F now
re-creates that generator and shows it.

---

## 2. The design: what decides the trap now

**A floor has two halves with two owners.**

* **Visible** — the two doors' sign carvings. Still `f(WorldSeed, runSeed, level)` through the public
  sign stream, the same for everyone on a run seed. A client may compute them.
* **Hidden** — trap side, liar line, which exclusive sign is the tell, both traits and which door holds
  which. A function of `profile.floorSecrets[level]` and **nothing public**: one uniform 32-bit
  integer per floor per run.

The secrets are drawn in `Main.server.luau` by `mintSecret`, which is a server-lifetime
`Random.new()` created at load, XORed with a fresh `Random.new()` per floor. They are re-drawn on
rebirth, saved in the same `UpdateAsync` write as `readFloors` and `slots` (so a saved read is never
saved without the secret it was read under), and never written to an Instance, an attribute, a
leaderstat or a remote. `Fork.plan(cfg, runSeed, Rng, secrets)` refuses to run without a valid secret
for every floor. There is no public fallback, because a public fallback is the defect.

Inside Fork.luau the hidden streams are seeded exactly as the public ones were, with the secret
standing where the public base stood: `Rng.new(mix32(secret + salt * SALT_MIX))`. Invariant 5 (seeds
are avalanche-hashed) and invariant 6 (a plain fair coin) are untouched.

### Why the client cannot recover it — the two traps in the brief, one at a time

**Trap 1: a 32-bit salted seed brute-forced against visible geometry.** Salting the one seed would
have left 2^32 candidates, and if that seed still drew the carvings, a script tries them all offline
against floor 1. Here, **nothing a client sees before a read is derived from a secret**:

* the carvings come from the public stream only. Fork.spec re-draws the secrets 3 times for each of
  200 run seeds and **0 of 6000** carvings move;
* the section geometry (`Section.build`) never took the plan seed. The new check re-derives every
  built platform from the public seed plus the two bits walking through the door revealed (its
  `Theme` and `Penalty`): **0 of ~7100 platforms** off that derivation;
* the unread fork, every rendered field and every attribute, is identical for all 10 readers on the
  same run seed while their secrets differ: **0 of 80** forks rendered differently.

With nothing to test a candidate against, there is no brute force. Witness G builds the naive fix
(carvings salted with the secret). It passes the public-predictor check at chance and is killed by the
visible-half check (**777 of 800** carvings move under a re-draw).

**Trap 2: 1 bit per read, and a 32-bit stream pinned by ~32 reads.** There is no run-wide stream.
Each floor has its own independently drawn secret, and **re-drawing one floor's secret moves 0 of
13 500 other floors' hidden or visible fields** (Fork.spec). A read reveals the trap side, the liar
line, the tell and two traits, roughly 10 bits and all of them hashes of that floor's secret. Even
brute-forcing that floor's 32-bit secret offline to a handful of candidates buys that floor, which the
player already paid for, and nothing about the next one. The one remaining link between floors is the
server's generator. Recovering it needs the internal state of `secretSource` (a search over its whole
state, from hashed partial observations) **and** the fresh `Random.new()` of every floor, which is why
the two are XORed.

**The hidden half depends on nothing public.** With the secrets held fixed, changing the run seed or
WorldSeed moves **0 of 4000** floors' trap, marked door, liar line or traits. A fresh draw moves the
trap on **0.4830** of floors, a coin's half.

### Why this shape and not the other acceptable one

The brief also allowed "a secret stream with well over 64 bits of state that influences nothing
visible". A per-floor secret already meets that, and it is simpler: floor independence is a
structural fact (Fork.spec asserts it) rather than a cryptographic hope about a hand-rolled wide
generator, and `Rng`/`mix32` did not have to change. It also costs 10 numbers in the profile.

### What was deliberately given up

"The same tower for everyone on a run seed" now holds only for the visible half. Fork.spec used to
assert that a leaderboard time only means something on a shared tower. A trap shared by everyone on a
run seed is a trap anyone can compute from that run seed, so that claim and the fix cannot both hold.
docs/new-game-checklist.md already states the rule this follows.

---

## 3. Migration: existing profiles and runs in progress

**No run is reshuffled, at any level.** `resolveSecrets` runs once per load, after every field it
reads is final. For each floor:

* a valid saved secret is kept;
* otherwise, if the player has **already seen that floor's hidden half** (answered it, read it, or
  climbed past it: `level < p.level or slots[level] or readFloors[level]`) it gets
  `Fork.legacySecrets(Config, runSeed)[level]`, which reproduces the 2026-09-17 plan **field for
  field** (Fork.spec: **0 of 5000** floors differ from the frozen module on any field);
* anything else gets a fresh secret.

Nothing visible depends on a secret, so re-drawing a floor the player has not read changes nothing on
their screen. The legacy floors are computable by a client, and that is harmless for exactly the
reason they were chosen: the player has already seen them.

Measured in `check_forktower_plansecret.luau` part E, against five legacy profiles at run seed 4,
level 3, doors 1 and 2 taken, floors 1-3 read, no `floorSecrets`:

* both climbed sections keep their trap and theme (10/10); all three paid inscriptions keep trap,
  tell and liar line (15/15), their traits (15/15) and their carvings (15/15);
* the first save stores secrets for all 5; floors 1-3 hold the legacy secret (15/15), floors 4-10
  hold fresh ones (35/35), and no two migrants share one (0 of 70 pairs);
* climbing to floor 4, its carvings are the pre-fix carvings (5/5) and its trap is the one the fresh
  saved secret plans (5/5);
* a migrant who rejoins keeps the migrated secrets, so migration happens once;
* a legacy profile at floor 1 that had read nothing gets a fresh secret on all 10 floors.

A **rejoin rebuilds the same tower** (part D): a player reads floors 1-3, answers 1-2 and leaves. On
rejoin, the traps, trait labels, both read forks (every rendered field) and both sections (every
part's position relative to the lobby) are byte-identical. Floor 4, first read after the rejoin, is
the trap the pre-rejoin secrets planned, and the load did not mint new secrets.

---

## 4. The check, written first

`robloxemu/check_forktower_plansecret.luau` (sha256 `013169ea…433a`) boots the built bundle.

**A: the measurement.** 10 readers × 8 runs × 10 floors = **800 forks**, each read honestly (hold
begun, `ReadSeconds` on the server's clock, released), and each **confirmed against the world**: every
reader walks through door 1 and the section's `Penalty` must agree with the read (800/800). Without
that confirmation, a broken read would score every predictor at chance and report a leak as fixed.
Three public predictors:

* **P1** is the replicated Fork module, compiled fresh from the bundle's ReplicatedStorage source (a
  client's own copy, never the server's module table), fed only `Config` and `Rebirths + 1`. First the
  probe verbatim; if the module refuses that, whatever else it computes without a server secret
  (after the fix: `Fork.legacySecrets`).
* **P2** is the 2026-09-17 `Fork.luau` itself, byte-for-byte (`tests/fixtures/Fork_20260917.luau`,
  sha256 `0c840300…5b07`), so an API change that only stops P1 from running cannot hide the old
  derivation.
* **P3** is another reader on the same public inputs, so any function of what two players share is
  caught, not only the one Fork.luau happens to use.

**The threshold.** For a correct game each prediction is an independent fair coin against the read,
so matches m ~ Binomial(n, ½). A predictor passes when **|m − n/2| ≤ 4.9·√n/2**: 331..469 at n = 800,
and 295..425 at n = 720 for P3. Z = 4.9 gives a false alarm about once per million runs per
predictor. The threshold is that strict because the sample differs on every run: the emulator seeds
`Random.new()` from os.time/os.clock. It is two-sided because a reliably wrong predictor is as good as
a reliably right one. It still has plenty of power: a 62%-accurate predictor lands about 4 σ outside
the band, and the leak was 100%.

**B: the visible world is public** (section 2, trap 1).

**C: nothing secret replicates.** The secrets are taken from the DataStore (server-only). They are
proved to be the secrets in play (Fork.plan with them re-derives 800/800 reads), no two readers share
a list, and no rebirth repeats one. The needles are every saved secret plus its four hidden stream
seeds `mix32(secret + salt·2654435761)`, 4000 in all. The sweep searches every written property and
attribute (names and values) of every client-replicated service (Workspace, ReplicatedStorage,
Players with everything under each player, Lighting, StarterGui, StarterPlayer, Teams, SoundService,
TextChatService), every payload any RemoteEvent ever sent, and the `Redeem` RemoteFunction's return.
Values are matched as numbers exactly, and inside strings as whole decimal tokens (for needles of 7+
digits) or whole 8-digit hex tokens. After its verdict the sweep is shown a planted secret in three
places (a workspace StringValue, a player attribute, a hex string in a Notice payload) and must find
all three.

**RED first**, on the bundle built from the untouched sources (`72fa55ad…1b80`):

```
  forks read honestly: 800 (10 readers x 8 runs x 10 floors)
  P1 replicated Fork module + leaderstats: 800/800 = 100.0% (chance band 331..469)
  P2 the 2026-09-17 derivation, frozen:    800/800 = 100.0% (chance band 331..469)
  P3 a second reader, same public inputs:  720/720 = 100.0% (chance band 295..425)
  B: 80 unread forks, 0 rendered differently between readers; 6920 platforms, 0 off the public derivation
FAIL: C: the server saved 10 valid 32-bit secrets per floor ... (0 of 80 profiles)
  ... (no secrets, nothing to sweep, the planted control has nothing to plant, no migration)
fork tower plan secret: 24 passed, 17 failed
```

**GREEN**, on the fixed bundle:

```
  P1 replicated Fork module + leaderstats: 430/800 = 53.8% (chance band 331..469)
  P2 the 2026-09-17 derivation, frozen:    430/800 = 53.8% (chance band 331..469)
  P3 a second reader, same public inputs:  378/720 = 52.5% (chance band 295..425)
  B: 80 unread forks, 0 rendered differently between readers; 7104 platforms, 0 off the public derivation
  C: swept 5126 replicated instances and 5160 RemoteEvent payloads for 4000 needles: 0 hits
fork tower plan secret: 41 passed, 0 failed
```

**Flakiness, measured.** 25 consecutive runs, each with its own server randomness: 25/25 at 41/0, P1
between **373 and 422** of 800 (band 331..469).

Order of work: the check was written and watched red before any source changed. The Fork.spec
additions were written next and watched red against the untouched Fork.luau (4 FAILs, then a crash
on the missing `Fork.isSecret`). Only then were Fork.luau and Main.server.luau changed.

---

## 5. Fork.spec, 53 → 71

The 40 000-fork fairness sweep now runs on **server-shaped** secrets: uniform 32-bit, drawn from
Luau's `math.random` (seeded 20260917). That generator shares no arithmetic with `mix32` or `Rng`, so
nothing can pass because the test's randomness and the module's are the same function. All the old
fairness assertions pass on it. New assertions, with what they printed:

```
  plan secret: carvings moved by a re-draw 0/6000; hidden half moved by run seed or WorldSeed 0/4000;
  trap moved by a re-draw 0.4830; other floors moved by one floor's re-draw 0/13500;
  public derivation names the trap 0.4988 of 40000; legacy migration differs on 0/5000 floors
  witness G: salted carvings moved 777 of 800 under a re-draw (real: 0)
```

Plus fail-closed checks (no secrets, a short list, a value ≥ 2^32 and a non-integer are all refused)
and `Fork.isSecret`'s exact domain. Two old claims changed on purpose. "Same runSeed rebuilds the
plan" became "same runSeed and same saved secrets", and "changing WorldSeed changes the trap layout"
became "...changes the sign carvings", because WorldSeed must no longer reach the trap.

Build.spec and readcost.measure plan with `Fork.legacySecrets`, so the rarity quintiles and the 1.110 s
break-even, both measured on those exact plans, stay reproducible to the digit.
`check_forktower.luau`'s seeded profiles carry `floorSecrets = Fork.legacySecrets(runSeed)`, so "run
seed 4 lies on floors 4, 6 and 8" and every other number recorded there stays true. Without that,
it went 127/2 (the liar floors became 7, 9).

---

## 6. Mutation sweep

Each mutation was applied by a byte-level patcher (exact single-occurrence replacement), followed by
a re-wrap and a check that **every mutated line is present in build/fork-tower.luau** and that the
bundle sha differs. Then all four world-level gates ran, the original bytes were restored, and an
11-file sha256 manifest was compared with baseline. All seven restores were byte-identical. The
final bundle is `bdc1c523…a79e` again. The sweep was run twice, the second time on the final sources.

| mutation | bundle sha256 | plansecret | Fork.spec | world | check_forktower | killed by |
|---|---|---|---|---|---|---|
| **M1** trap re-derived from the public stream in Fork.luau | `8cfcab5d…` | **38/3** | **66/5** | 71/0 | 129/0 | P1, P2, P3 all 800/800, 800/800, 720/720 |
| **M1b** server hands out `Fork.legacySecrets` for every floor and on rebirth | `8e1abaae…` | **33/8** | 71/0 | 71/0 | 129/0 | P1/P2/P3 at 100%; readers share lists (360); migrants' unseen floors not fresh |
| **M2a** secret as a number attribute `Seal` on each `Fork_n` folder | `a36a2010…` | **39/2** | 71/0 | 71/0 | **127/2** | the sweep (100 hits); part B (80 of 80 unread forks render differently) |
| **M2b** secret in the `State` RemoteEvent payload | `87256fe3…` | **40/1** | 71/0 | 71/0 | 129/0 | the wire sweep (2410 hits) — **no other gate sees it** |
| **M2c** whole list as a string attribute `RunKey` on the Player | `eec45142…` | **40/1** | 71/0 | 71/0 | 129/0 | the sweep (200 hits) — **no other gate sees it** |
| CONTROL C1 door light `Brightness` 2.2 → 3.4 | `9b422dac…` | 41/0 | 71/0 | 71/0 | 129/0 | correctly invisible |
| CONTROL C2 `Config.Fork.LiarChance` 0.3 → 0.4 | `8b399f7c…` | 41/0 | 71/0 | 71/0 | 128/1 | invisible to plansecret; check_forktower pins seed 4's liar floors (got 4,6,7,8) |

M1's five Fork.spec kills are the hidden-half-is-secret assertion (3040 of 4000 floors moved), "a fresh
draw moves the trap" (0.000), the public derivation at chance (1.0000 of 40 000), witness F's
real-fork line, and witness G's "passes the public-predictor check".

**The controls, and why these two.** C1 changes a field that part B's rendered record reads on every
door, and part B must not care because it changes identically for everyone. Without it, "0 rendered
differently" could come from a record that reads nothing. C2 moves real hidden decisions (which floors
lie) in every tower, legacy floors included, and the check must not care because the hidden half is
still secret and the legacy identity still holds (the fixture reads the same Config). A check that
went red on it would be detecting "Fork changed" rather than "Fork leaks".

---

## 7. Files

| file | sha256 after | change |
|---|---|---|
| `fork-tower/src/shared/Fork.luau` | `6de71f07…d464` | public/secret split, `Fork.isSecret`, `Fork.legacySecrets`, `Fork.plan(..., secrets)` fails closed |
| `fork-tower/src/server/Main.server.luau` | `934391fa…c74c` | `mintSecret`/`mintSecrets`/`resolveSecrets`; load, save, buildLane, rebirth |
| `fork-tower/src/shared/Config.luau` | `3a51da21…eb2f` | the WorldSeed comment only (it promised the same tower for everyone) |
| `fork-tower/tests/Fork.spec.luau` | `db61d848…1089` | 53 → 71 |
| `fork-tower/tests/fixtures/Fork_20260917.luau` | `0c840300…5b07` | NEW, byte copy of the leaking module |
| `fork-tower/tests/Build.spec.luau` | `5cfad09d…bca5` | two call sites pass `legacySecrets` |
| `fork-tower/tests/readcost.measure.luau` | `23d514e8…22de` | two call sites pass `legacySecrets` |
| `robloxemu/check_forktower.luau` | `5bdd6721…23f3` | seeded profiles carry their secrets |
| `robloxemu/check_forktower_plansecret.luau` | `013169ea…433a` | NEW |

Unchanged and verified by sha256: `src/client/Hud.client.luau`, `src/shared/Section.luau`,
`tests/world.check.luau`. No client or visual code was touched.

---

## 8. Still open

1. **`Random:NextInteger(0, 4294967295)` and `bit32.bxor` on values ≥ 2^31 are unmeasured in the real
   engine.** Everything above ran in the emulator, whose `Random` is xoshiro128**, not Roblox's PCG.
   In Studio: print 20 `mintSecret()` values and confirm some exceed 2^31 and none is negative. If
   NextInteger rejected the range, `buildLane` would raise at the first join (fail closed, not open).
2. **Roblox's unseeded `Random.new()` entropy source is undocumented beyond "internal entropy".** The
   XOR with a server-lifetime generator is the mitigation for a time-based seed. It is reasoning, not
   a measurement.
3. **The sweep sees the final world plus the full wire history, not every intermediate world.** A
   leak written to an Instance and destroyed before the sweep (for example on a lane torn down by
   rebirth) would be missed. The wire half has no such gap.
4. **The sweep looks for the secrets and their stream seeds, not for every function of them.** A
   server that replicated a hidden-half bit (say the next floor's trap side as an innocuous leaderstat
   or payload field) would evade C. The attribute inventory in check_forktower covers only the `Fork_n`
   subtree, and world.check only the `rule` payload. The stronger, generic check would score every
   replicated scalar against the upcoming trap across the 800 forks. Not written.
5. **WRONG, and the attack that proved it is §9.** This item said a read-only session (the profile
   locked by another server) was "consistency, not safety": unseen floors are re-drawn on the next
   load, every re-draw costs a paid read, read-only sessions bank nothing. That held only for a
   profile that had never been saved. A read-only session loaded the SAVED secrets, so a door walked
   there was free information about the saved run: 240 of 240 forks. Closed in §9.
6. **`docs/new-game-checklist.md`'s "Replayable RNG" row** says to mix a server-only salt into a
   memorisable seed. This pass shows that is not enough when the seed is 32 bits and also drives
   anything visible. Worth a sentence there. docs/ was outside this pass's ownership.
7. Fork.spec now takes about 10 s (the new blocks re-plan whole runs per floor). Acceptable, but noted
   in case the EYECANDY workflow wants a faster inner loop.
8. Everything REVIEW-3 and STUDIO.md left open is unchanged: no human has summited, no phone has seen
   it, and `hudcheck` is still not wired in.

---

## 9. Second pass: a session that cannot keep what it reveals was an oracle

```
                             after §1–8 (Main 934391fa)       after §9
Fork.spec                    71 / 0                           71 / 0    (file unchanged)
Section.spec                 50 / 0                           50 / 0
Build.spec                   31 / 0                           31 / 0
Codes.spec                   19 / 0                           19 / 0
Rng.spec                     32 / 0                           32 / 0
responsive.spec              70 / 0                           70 / 0
world.check                  71 / 0                           71 / 0    (file unchanged)
check_forktower             129 / 0                          129 / 0    (file unchanged)
check_forktower_plansecret   41 / 0, and 72 / 7 on the        79 / 0
                             final check (part F added)
readcost.measure             break-even 1.110 s               1.110 s
```

### 9.1 The attack

An adversarial pass on §1–8 the same day tried every route in §2–4 and found them closed: the public
predictors stayed at chance over 7200 real mints, 228 two-session write-log diffs showed nothing
secret-dependent before a read, revealed bits did not predict later floors, and migration held. One
route won:

**A read-only session was a free oracle: 240 of 240 forks, 0 reads paid.** 12 attackers, 2 runs
each. Once a run's secrets are saved (any autosave, door or read), the attacker joins a second
session while the first server still holds the session lock. `loadProfile` read the whole record,
`floorSecrets` included, and played READ-ONLY. There the attacker walked through door 1 on every
floor, read the replicated `Section_n.Penalty` attribute, touched the exit and left. Once the first
server's leave-save released the lock they rejoined writable: the same run, the same secrets, every
trap known. Taking the predicted-safe door without reading: 240 safe, 0 traps. Without the oracle,
always door 1: 26 of 60 traps. A probe before anything had been saved: 29 of 60 (nothing saved,
nothing to reveal).

Root cause: `buildLane` planned from saved secrets while `canSave` was false, and `onDoorChosen`,
`onReadInscription` and `reachExit` never look at `canSave`. §8 item 5 had filed this as
"consistency, not safety". The condition in production is the server-hop race that read-only mode
exists for (a player loads on server B while server A's lock is still live). How often that race
happens was not measured, and after this fix it no longer matters for secrecy.

### 9.2 The defect in general, and the rule that closes it

The general shape: **a hidden bit is revealed by a session whose record will not hold that reveal,
while the record keeps the secret that decided it.** The next session trusts the record, and the bit
is free. There are four ways to get there, and part F of the check has a block for each:

| way | block |
|---|---|
| the lock is held by another server, so the session is read-only (the attack) | F1 |
| the session before crashed or lost its writes, and a session reveals after it (F2), or the crashing session itself revealed and never wrote (F2b) | F2, F2b |
| the load read a released record, then failed to write its own lock (`canSave` false) | F4 |
| BindToClose released the lock while the player was still in the server | F5 |

**The rule** (`loadProfile` and `resolveSecrets` in `Main.server.luau`). A session plans a floor the
player has **not** seen from its saved secret only when it **trusts** the record, and trust takes both:

* **`canSave`**: it holds the lock and its load landed, so what it reveals will be written; and
* **the record was released when it loaded** (`lockUntil == 0`). Only a leave-save and BindToClose
  write 0. A load and every autosave write a lock in the future. So a released record says the last
  session wrote its final state on the way out, and that write carries every reveal it made, because
  (a) every reveal puts the slot or the read into the profile before the world shows it, and (b)
  nothing is revealed once a releasing save has been attempted (below).

Without trust, every unseen floor gets a fresh `mintSecret()` for this session, which is never saved
from a session that cannot save. A floor the player has **already seen** (answered, climbed past, or
read) keeps its saved secret in every session: they know it, and changing it would reshuffle what
they saw.

**`p.released`** is set by `saveProfile` before any write that releases the lock. `onDoorChosen` and
`onReadInscription` refuse while it is set, and a read that is already counting down re-checks it in
`finish`. Without that, BindToClose would write a trusted record while players could still open
doors.

**Why the client cannot recover the saved plan now.** A session that cannot persist what it reveals
(read-only, after a crash, after a failed load, after a release) never plans an unseen floor from a
saved secret. The secrets it plays under come from the same server randomness, independently of the
saved ones, and are never replicated (the final sweep of part F). Walking doors there measures a coin
no later session uses. Nothing on screen differs either way, because nothing visible is derived from
a secret (part B). The saved secret of an unseen floor is only planned by a session whose reveals will
be written, which is the honest game.

### 9.3 Why this shape and not the others

* **Refuse doors and reads in a read-only session.** This closes the attack exactly, but it leaves the
  crash and failed-load routes open (F2, F2b and F4 are writable-looking sessions whose writes never
  land), and it makes a read-only session unplayable instead of just unsaved.
* **Commit before reveal** (an `UpdateAsync` that must land before `buildSection`). This closes every
  route, but it adds a DataStore round trip to every door and every read. Roblox allows one write per
  key every 6 seconds, and REVIEW-3 already had to coalesce saves because one client could drain the
  server's write budget. A door that waits up to 6 s for its commit is a gameplay regression, and the
  emulator cannot measure it.
* **Re-draw every unseen floor on every load.** This closes every route with no trust rule, and breaks
  "a rejoin rebuilds the same tower" for the floors ahead. Mutation M9 below is exactly that, and it
  turns part D, part E and F1's same-tower control red.

### 9.4 Migration and rejoin: what happens to a profile and a run in progress

* **A profile released normally**, which is every clean leave under the §1–8 build and this one, is
  trusted and loads exactly as before. F1 control: `Fork.plan` with the secrets saved before the probe
  re-derives **240 of 240** of the real session's reads. Parts D and E are unchanged and green.
* **A run in progress whose record is not trusted** (crashed, locked elsewhere, failed load) keeps
  every floor the player has seen byte for byte, and draws the unseen floors again. F3 measures it on
  players who read floors 1–3 and answered 1–2: both sections, all three read inscriptions and the
  trait labels are identical after a read-only load and after a crash (**6 of 6**). After the crash,
  the saved secrets of floors 1–3 are kept (**9 of 9**) and floors 4–10 are re-drawn (**21 of 21**).
  Nothing on screen moves, because nothing visible depends on a secret. **No run is reshuffled at any
  level.**
* **Legacy profiles** (no `floorSecrets`) follow §3. The trust rule only decides unseen floors, and §3
  already drew those fresh.
* **What an honest player can notice.** A read whose save never landed (a crash, or a read-only
  session) may show a different inscription next time. A read-only session plays its unseen floors on
  throwaway secrets, though it saved nothing before either. While a server shuts down, doors and reads
  are refused with a notice.

### 9.5 The check, extended first: part F of `robloxemu/check_forktower_plansecret.luau`

Every block boots the built bundle, drives sessions through the prompts and remotes a client has,
and scores what a hostile client learned against the honest reads of the session after it, confirmed
on the ground by walking door 1 (the section's `Penalty` must match the read on every fork). The
threshold is §4's: |m − n/2| <= 4.9·√n/2, which is **83..157 at n = 240** and **34..86 at n = 120**.

* **F1, the attack verbatim.** 12 attackers × 2 runs × 10 floors = 240 forks. Controls: all 24 probes
  really loaded READ-ONLY, wrote nothing, and walked all 240 doors, and every real session loaded
  writable. The same-tower control is 240 of 240.
* **F2, after a crash.** The first server's leave-save raises, so the record keeps its lock. The next
  session is writable, then an outage starts, it walks every door, and nothing lands. 120 forks.
* **F2b, the crashing session is its own probe.** Autosave, then the outage, then door walks, then the
  crash. 120 forks.
* **F3, nothing seen is reshuffled** (§9.4).
* **F4, a load that failed after reading.** The emulator raises injected failures before the transform
  runs, so this block replaces `store.UpdateAsync` for one call: the transform runs, then the call
  raises. Controls: the record was released beforehand, the injection was consumed by the probe's load,
  and the server warned "load failed". 120 forks.
* **F5, the shutdown window.** Before the shutdown, every read prompt and door prompt is live (control).
  A read is started with no hold, so it is counting down when `runBindToClose` releases every lock.
  Then every player tries to read and to walk all ten doors, and the server dies before any later write
  lands. The asserts: the count-down read hands nothing over (**0 of 12**), there are **0 reveals**
  after the release, and a player who joined after the shutdown save walks a door in the same server
  (control).
* **The sweep of part C again,** over everything part F put in the world and on the wire, with every
  secret list part F saw saved as needles: 4605 new needles, 0 hits.

Emulator note, found by the attacker: Luau resolves the import `game.JobId` when `Main.server` loads,
so setting `h.game.JobId` mid-run tests nothing. "Another server holds the lock" is written into the
record (`jobId` from another server, `lockUntil` in the future), and every probe asserts it really
loaded read-only.

**RED**, the final check (sha256 `209532ca…510d`) on the attacked source (`Main.server.luau`
`934391fa`, bundle `bdc1c523`, byte-identical to the §7 bundle), from the mutation sweep's PREFIX
entry:

```
  F1 read-only probe (door walks, 0 reads) vs the real run: 240/240 = 100.0% (chance band 83..157)
  F2 crashed-then-unsaved probe vs the next session: 120/120 = 100.0% (chance band 34..86)
  F2b a session's own unsaved walks vs the session after its crash: 120/120 = 100.0% (chance band 34..86)
FAIL: F3: ...while every floor they had NOT seen is drawn again ... -> got 0, want 21
  F4 probe whose load failed to commit vs the real run: 120/120 = 100.0% (chance band 34..86)
  F5 reveals after the shutdown save: 132 (12 of them reads already counting down); of those, 120 of 120 predicted the next session's trap
fork tower plan secret: 72 passed, 7 failed
```

The first draft of part F (F1, F2, F3 and the shutdown block) was the first thing written in this pass
and was watched red before `Main.server.luau` changed: **58 passed, 4 failed**, with F1 240/240, F2
120/120, F3 0/21 and 132 reveals after the shutdown. F2b, F4, the count-down read and the final sweep
were added while the fix was being hardened, and each was watched red through the PREFIX entry above.

**GREEN**, on the fixed bundle `d3ea4fed…02d7`:

```
  P1 replicated Fork module + leaderstats: 405/800 = 50.6% (chance band 331..469)
  C: swept 5134 replicated instances and 5160 RemoteEvent payloads for 4000 needles: 0 hits
  F1 read-only probe (door walks, 0 reads) vs the real run: 121/240 = 50.4% (chance band 83..157)
  F2 crashed-then-unsaved probe vs the next session: 48/120 = 40.0% (chance band 34..86)
  F2b a session's own unsaved walks vs the session after its crash: 71/120 = 59.2% (chance band 34..86)
  F4 probe whose load failed to commit vs the real run: 72/120 = 60.0% (chance band 34..86)
  F5 reveals after the shutdown save: 0 (0 of them reads already counting down); of those, 0 of 0 predicted the next session's trap
  F: swept 1308 replicated instances and 12781 RemoteEvent payloads for 8605 needles (4605 from part F): 0 hits
fork tower plan secret: 79 passed, 0 failed
```

**Flakiness.** 25 consecutive runs of the final check all passed at 79/0. The ranges were F1 99..136 of
240, F2 49..71 of 120, F2b 50..65, F4 51..74, and P1 344..420 of 800. Pooled over the 75 runs of the
three versions of part F, F1 matched 8853 of 18 000 (49.2%, z = −2.2), which is just outside a
2-sigma band. The two generators this depends on were then measured directly, outside the game. Over
60 000 floors, the server's mint puts the trap on door 1 0.4992 of the time (z = −0.38), and two
independent mints agree on 0.5014 (z = +0.70). The attack itself was then pooled at a larger n:
the attacker's unchanged script, run 60 times against the fixed bundle, predicted **7203 of 14 400**
forks (0.5002, z = +0.05). The −2.2 in the 75-run pool is sampling noise, not a residual correlation.

**The attacker's own script, unchanged** (`atk_readonly.luau`, sha256 `415c7ad8…`), run in scratch
against both bundles with 24 of 24 probes read-only both times: **240 of 240** predicted and 0 traps
eaten on the attacked bundle, **114 of 240** predicted and 126 traps eaten on the fixed one.

### 9.6 Mutation sweep

The patcher (scratchpad `ro/mutate.py`) makes exact single-occurrence replacements, or substitutes a
whole file for PREFIX. It re-wraps, asserts the mutated text is in `build/fork-tower.luau` and that
the bundle sha differs, runs plansecret, check_forktower and world.check (plus Fork.spec when
Fork.luau changed), then restores the bytes and compares a 13-file sha256 manifest. All 16 restores
were byte-identical, and the final bundle is `d3ea4fed…` again.

| mutation | bundle | plansecret | other gates | killed by |
|---|---|---|---|---|
| PREFIX the attacked Main.server.luau | `bdc1c523` | **72/7** | green | F1 240/240, F2 120/120, F2b 120/120, F3 0/21, F4 120/120, F5 132 reveals |
| M1 trap re-derived from the public seed (Fork.luau) | `ba10d440` | **72/7** | Fork.spec **66/5** | P1/P2/P3 at 100%; F1, F2, F2b, F4 at 100% |
| M2 secret list as a Player attribute `RunKey` | `da6c44fc` | **77/2** | green | sweep C (200 hits), sweep F (100 hits) |
| M3 every load trusts the saved secrets (the attacked rule) | `0f5e02e0` | **74/5** | green | F1, F2, F2b, F4 at 100%; F3 0/21 |
| M4 trust = `canSave` only | `f9e71c61` | **76/3** | green | F2, F2b at 100%; F3 0/21 |
| M5 trust = record released only | `1524a18f` | **78/1** | green | F4 120/120 |
| M6 no released gate on the door | `8669802f` | **78/1** | green | F5 120 reveals, 120/120 predicted |
| M7 no released gate on either read path | `11eb1db7` | **77/2** | green | F5 12 count-down reads handed over |
| M7a only the up-front read gate removed | `6d0f5b08` | 79/0 | green | **survives, by design**: `finish` refuses every read |
| M7b only the `finish` read gate removed | `a8ee502c` | **77/2** | green | F5 12 count-down reads handed over |
| M8 untrusted loads re-draw SEEN floors too | `9bbc136d` | **77/2** | green | F3 0/6 seen identical, 0/9 seen secrets kept |
| M9 no load trusts an unseen floor (a rejoin re-draws) | `90e6e548` | **74/5** | check_forktower **127/2** | D (floor 4, no re-mint), E rejoin, F1 same tower 107/240, F4 same tower 60/120 |
| M10 read-only session sends the saved secrets in a Notice | `1c1a62b8` | **78/1** | green | sweep F (270 hits); part C runs before F and sees nothing |
| M11 every write releases the lock (autosave writes 0) | `b72cba7e` | **75/4** | green | F2b 120/120; F3 crash control and 0/21 re-drawn; F2 crash control |
| CONTROL C1 the released door gate's notice text | `ecb98d82` | 79/0 | green | correctly invisible |
| CONTROL C2 `resolveSecrets` walks the floors top-down | `d8a4f813` | 79/0 | green | correctly invisible |

**M7a survives, and that is correct.** The up-front refusal in `onReadInscription` only exists to
send a notice. Every read hands its inscription over through `finish`, which re-checks `released`,
so removing the up-front gate reveals nothing. M7b removes the gate in `finish`, and F5's count-down
read kills it.

**The controls.** C1 changes text on the exact path F5 drives, so a check that fired on "Main changed
near the gate" would have gone red. C2 changes how `resolveSecrets` iterates, and with it which draw
lands on which floor, without changing what is trusted, so a check that fired on "the secrets
differ" would have gone red.

### 9.7 Files

| file | sha256 after | change |
|---|---|---|
| `fork-tower/src/server/Main.server.luau` | `b098da03…53c3` | trust rule in `loadProfile`/`resolveSecrets`, `p.released`, three reveal gates |
| `robloxemu/check_forktower_plansecret.luau` | `209532ca…510d` | part F (F1, F2, F2b, F3, F4, F5, final sweep); 41 → 79 assertions |
| `fork-tower/REVIEW-4.md` | — | this section; §8 item 5 marked wrong |
| `fork-tower/CLAUDE.md` | — | state block, invariant 13, what went wrong |
| `fork-tower/REVIEW-3.md` | — | one sentence under the existing pointer |

Unchanged, and verified by sha256 against the start of this pass: `Fork.luau` (`6de71f07`),
`Config.luau` (`3a51da21`), `Section.luau`, `Rng.luau`, `Hud.client.luau`, `Fork.spec.luau`,
`world.check.luau`, `check_forktower.luau` (`5bdd6721`), `emu/*`, `wrap.py`. No client or visual code
was touched. Nothing was committed, pushed or published.

### 9.8 Still open

1. **The `canSave` half of trust is only exercised by an injected failure.** F4 replaces
   `UpdateAsync` in the check, because the emulator's own injection raises before the transform.
   Whether Roblox ever fails an `UpdateAsync` after running its transform is not measured here, but
   the code handles it either way.
2. **The rule rests on one code invariant: only a releasing save writes `lockUntil = 0`.** M11 shows
   the check catches an autosave that breaks it. A new write path elsewhere (a future `SetAsync` of the
   profile, for example) must keep it.
3. **Honest-player consistency.** A read or door whose save never landed is re-drawn on an untrusted
   load. This is invisible except as a different inscription on a re-read, and it is safe.
4. **The per-key write cooldown and the ordering of queued writes on real DataStores are unmeasured.**
   The rule does not depend on them: any unreleased record is untrusted. **Wrong, see §10:** a
   RELEASED record can be written late, by the second of a shutdown's two releases, after a newer
   session trusted and revealed from it. The honest-player effect of a
   fast same-server rejoin landing before its own leave-save is that unseen floors are re-drawn.
5. **Not part of this finding, from the same adversarial pass.** First, a client that teleports its
   character can fire the exit's `Touched` without climbing, so to a script a trap costs nothing
   whatever it predicts, and the read-versus-guess economy only prices honest players. Second,
   `Config.Codes` is in ReplicatedStorage, so every redeem code is readable. Neither was in scope.
6. §8 items 1–4 and 6–8 stand as written, above all the unmeasured real-engine `Random` range and
   entropy source.

## 10. Third pass: a releasing write that lands late re-released a trusted record

```
                             after §9 (Main b098da03)          after §10 (Main 405956d0)
Fork.spec                    71 / 0                            71 / 0    (file unchanged)
Section.spec                 50 / 0                            50 / 0
Build.spec                   31 / 0                            31 / 0
Codes.spec                   19 / 0                            19 / 0
Rng.spec                     32 / 0                            32 / 0
responsive.spec              70 / 0                            70 / 0
world.check                  71 / 0                            71 / 0    (file unchanged)
check_forktower             129 / 0                           129 / 0    (file unchanged)
check_forktower_plansecret   79 / 0; 89 / 1 with F6 added,     96 / 0
                             91 / 5 on the final check
readcost.measure             break-even 1.110 s                1.110 s
```

### 10.1 The finding

§9 closed the read-only oracle with a trust rule: a session plans an unseen floor from its saved
secret only if it can save and the record was **released** (`lockUntil == 0`) when it loaded. §9.2
justified it with "a released record is the last session's final state". §9.8 item 4 then said the
rule does not depend on the order in which queued DataStore writes land. **That was wrong.** It was
found by reading the rule against the write paths, before any attacker ran:

* a shutdown makes **two releasing saves** for every player still in the server: BindToClose writes
  one, and PlayerRemoving writes another as the player is dropped. Both write `lockUntil = 0`;
* `saveProfile` wrote unconditionally. Nothing checked that the record still belonged to the session
  writing it;
* DataStore writes are queued, not instant. Roblox documents a per-key write cooldown and a
  server-wide request budget, and a full server's shutdown spends that budget at once. Queued writes
  need not land in the order they were made, or close together. The real ordering is not measured
  here.

So one releasing write can land **after a later session has loaded**. The measured sequence (part F6
below):

1. The home session's run is saved. The server shuts down: BindToClose's write is queued, and
   PlayerRemoving's write lands, releasing the record.
2. The player joins another server. It loads a released record, can save, **trusts** it, and plans the
   saved secrets.
3. The player walks through door 1 on every floor without reading. That server goes down before any of
   it is written, so the record still holds the probe's load lock.
4. The queued BindToClose write lands: `lockUntil = 0` again, with the home session's state, in which
   no floor was walked.
5. The next session trusts that record and plans the very secrets the probe walked.

**On the §9 source (`b098da03`): 120 of 120 traps predicted, 0 reads paid.** Every control held:

* the late write was one per player (12 of 12);
* the probe loaded writable and trusted: its walks are `Fork.plan` of the saved secrets on 120 of 120
  floors;
* none of its walks landed (12 of 12);
* all 12 late writes landed as a release.

What it costs an attacker in production: a server shutdown with the player inside (a published update
migrates every server), a queued write delayed past a whole session on another server, and that server
crashing. They control none of these, so it is a narrow race. It is also exactly §9.2's shape, a
trusted record that does not hold a reveal, which the rule claimed to have closed.

### 10.2 The rule that closes it: the record has an owner

The load that takes the lock writes a fresh **`session` token** into the record
(`HttpService:GenerateGUID(false)`), and the profile keeps it as `p.session`. **Every write in
`saveProfile` lands only while the record still carries that session's own token.** If another load
has taken the record since, the transform returns `nil` and the write is cancelled (by Roblox and by
the emulator), whatever the write is: an autosave, a leave, or a BindToClose write that sat in the
queue. The session that finds out sets `canSave = false`, warns, and stops writing, and Redeem refuses
from then on.

With that, the §9 argument holds under any ordering of writes:

* a released record is written only by the session that owns it, from its own memory;
* that memory holds every reveal the session made: every reveal goes into the profile before the world
  shows it, and nothing is revealed after a releasing save is attempted (§9.2);
* only one session can trust a released record: the one load that takes it. That load writes a lock
  and a new token in the same `UpdateAsync`, so every later load sees `lockUntil > 0` and does not
  trust. From that moment on, the previous owner's writes are cancelled.

So no released record can lack a reveal made from the secrets it carries. A second release from the
same session, with no load in between (BindToClose, then PlayerRemoving), still lands because the token
matches. F6c measures that.

The token also closes the ordinary clobber this code always had: a session whose lock expired while it
was still running used to write over the session that took the lock. F6d measures that.

### 10.3 Why this shape and not the others

* **At most one releasing write per session** (PlayerRemoving skips its write if BindToClose already
  released). This closes F6's exact order, but a player loses real progress when that one release
  fails and the retry is skipped. It also leaves every other late write, such as an autosave landing
  over a newer session, unconditional.
* **Re-draw every unseen floor on every load** (§9.3). This needs no trust at all, but a rejoin no
  longer rebuilds the same run (mutation M9 in §9.6).
* **Commit before reveal** (§9.3). This costs a DataStore round trip on every door, under a 6-second
  per-key cooldown.
* **An ownership token** is the standard session-lock pattern: a load takes the record, and each write
  checks it still owns it. It is three lines in the load and five in the save, and nothing a player
  sees changes.

### 10.4 Migration: an existing profile and a run in progress

* **Records saved before this pass** have no `session` field. The first load that takes the lock writes
  one, and every write of that session carries it from then on. Nothing else about the record changes.
* **A run in progress** loads exactly as under §9. The token decides only which writes land, never
  which secrets are planned. Part D (rejoin), part E (migration), F1–F5 and F3 (nothing seen is
  reshuffled) are unchanged and green. F6c shows that a clean session's late release still rebuilds
  the same tower: 48 of 48 unseen floors re-derived from the saved secrets.
* **A server running the previous build** during a deploy writes no token, so its late writes would
  not be refused, and the race stays open until those servers are gone. This build has never been
  published, so no such server exists today.
* **What an honest player can notice:** nothing, unless two of their sessions overlap. Then the older
  session is told it was taken over, and its unsaved progress is not written over the newer session.
  It used to be, and the newer session's next autosave usually overwrote it again anyway.

### 10.5 The check, extended first: F6, F6c, F6d

These blocks were added to `robloxemu/check_forktower_plansecret.luau` and run against the untouched
§9 bundle (`d3ea4fed`) before `Main.server.luau` changed.

* **F6, the late release.** 12 players × 10 floors = 120 forks. The held-back write is the server's
  own: `store.UpdateAsync` is swapped out for one `runBindToClose`, so the transform that lands late is
  the one the server built, closing over the real profile. The threshold is §4's: 34..86 at n = 120.
* **F6c, CONTROL: a lone late release still lands.** 6 players. PlayerRemoving's write fails, so the
  queued BindToClose write is the session's only release. It must land (`lockUntil = 0`, at floor 2
  with floor 2 read), and the next session must play the same tower: 48 unseen floors re-derived from
  the saved secrets. A fix that simply threw away late or second releases would pass F6 and fail here.
* **F6d, a live session whose record a newer load took.** 6 players. The older session is still
  running when the newer one loads. Its door, its forced write (a redeemed code) and its leave must not
  land over the newer session. It must be told, and it must refuse the next code (`nosave`). Control:
  the newer session's own leave releases.

**RED** on the §9 bundle `d3ea4fed…02d7`, with the check as it stood once F6 was written (sha256
`ad6d6ef3`; F6c and F6d were added next):

```
  F1 read-only probe (door walks, 0 reads) vs the real run: 124/240 = 51.7% (chance band 83..157)
  F5 reveals after the shutdown save: 0 (0 of them reads already counting down); of those, 0 of 0 predicted the next session's trap
  F6 late BindToClose writes that landed as a release after the probe had loaded: 12 of 12
FAIL: F6: the walks of a session that loaded before a late releasing write predicts the trap NO BETTER THAN CHANCE: 120 of 120 = 100.0% (a coin lands in 34..86 at Z = 4.9)
  F6 probe's walks vs the session after the late write: 120/120 = 100.0% (chance band 34..86)
fork tower plan secret: 89 passed, 1 failed
```

The RED run of F6d, and of the final check on the §9 source, is the sweep's PREFIX2 entry (§10.6):
**91 passed, 5 failed**. F6 is 120/120, and 12 of 12 late writes landed. F6d fails all four ways:

* the older session's writes landed over the newer session (6 of 6);
* it was never told (0 of 6);
* it never refused a code (0 of 6);
* its leave released the newer session's record (6 of 6).

**GREEN** on the fixed bundle `a9e7fba6…6961`, final check `02dc1fd3…a58b`:

```
  P1 replicated Fork module + leaderstats: 409/800 = 51.1% (chance band 331..469)
  C: swept 5174 replicated instances and 5160 RemoteEvent payloads for 4000 needles: 0 hits
  F1 read-only probe (door walks, 0 reads) vs the real run: 112/240 = 46.7% (chance band 83..157)
  F2 crashed-then-unsaved probe vs the next session: 59/120 = 49.2% (chance band 34..86)
  F2b a session's own unsaved walks vs the session after its crash: 73/120 = 60.8% (chance band 34..86)
  F4 probe whose load failed to commit vs the real run: 62/120 = 51.7% (chance band 34..86)
  F5 reveals after the shutdown save: 0 (0 of them reads already counting down); of those, 0 of 0 predicted the next session's trap
  F6 late BindToClose writes that landed as a release after the probe had loaded: 0 of 12
  F6 probe's walks vs the session after the late write: 61/120 = 50.8% (chance band 34..86)
  F: swept 1668 replicated instances and 14547 RemoteEvent payloads for 9505 needles (5505 from part F): 0 hits
fork tower plan secret: 96 passed, 0 failed
```

**Flakiness.** 12 consecutive runs of the final check all passed at 96/0. The ranges were F6 51..69 of
120, F1 106..139 of 240 and P1 375..411 of 800. Pooled over those 12 runs and 3 earlier green runs of
the same check, F6 matched 922 of 1800 (51.2%, z = +1.04). The threshold is §4's Z = 4.9 per
predictor. There are now eight predictors (P1, P2, P3, F1, F2, F2b, F4, F6), so a correct game fails a
run about 1e-5 of the time.

The final check differs from the one the sweep ran (`a98740f4`) in one F6c comment and one F6c message,
and nothing else. Both had overclaimed which write carried floor 2's read; the evidence that the late
release landed is `lockUntil = 0`.

### 10.6 Mutation sweep

The patcher is scratchpad `ro3/mutate3.py`: §9.6's patcher with a new list of mutations. It makes exact
single-occurrence replacements, or substitutes a whole file. It re-wraps, proves the edit reached
`build/fork-tower.luau`, runs plansecret, check_forktower and world.check (plus Fork.spec when
Fork.luau changed), restores the bytes, and compares a 13-file sha256 manifest. All 11 restores were
byte-identical, and the final bundle is `a9e7fba6…` again.

PREFIX2 only removes lines, so the patcher's text probe had nothing to look for. Its bundle sha **is**
§9's bundle `d3ea4fed`, byte for byte, which proves it reached.

| mutation | bundle | plansecret | other gates | killed by |
|---|---|---|---|---|
| PREFIX round-1 Main.server.luau (`934391fa`) | `bdc1c523` | **84/12** | green | §9's F1–F5, plus F6 120/120 and all four F6d asserts |
| PREFIX2 round-2 Main.server.luau (`b098da03`), trust rule without ownership | `d3ea4fed` | **91/5** | green | F6 120/120 (12 of 12 late writes landed), all four F6d asserts |
| M1 trap re-derived from the public seed (Fork.luau) | `a1353b00` | **88/8** | Fork.spec **66/5** | P1/P2/P3 at 100%; F1, F2, F2b, F4, F6 at 100% |
| M2 secret list replicated as Player attribute `RunKey` | `183d32b1` | **94/2** | green | sweep C 200 hits, sweep F 100 hits |
| M3 every load trusts the saved secrets | `5916e41a` | **90/6** | green | F1, F2, F2b, F4, F6 at 100%; F3 0/21 |
| M12 no ownership check on a write (`if false then`) | `501425eb` | **91/5** | green | F6 120/120, all four F6d asserts |
| M13 token = `game.JobId` (not unique per load) | `4b3232c9` | **91/5** | green | F6 120/120, all four F6d asserts |
| M14 a session that finds its record taken keeps `canSave` | `97428da4` | **95/1** | green | F6d: refused a code 0/6 |
| M15 the load does not write its own token | `68c2a4ba` | **crash** after 13 FAILs | check_forktower **127/2**, world **64/7** | every write cancelled: no secrets saved (C), D, E |
| CONTROL C1 released door gate's notice text | `3cd4b4b9` | 96/0 | green | correctly invisible |
| CONTROL C3 token in braces, `GenerateGUID(true)` | `e849f965` | 96/0 | green | correctly invisible |

M1 and M2 are the two edits the brief requires: the trap re-derived from the public seed, and the
secret replicated. C3 changes every token string but keeps them unique per load, so a check keyed to
the token's shape, instead of to ownership, would have gone red. §9.6's M4–M11 were not re-run: the
code they mutate and the blocks that kill them are unchanged, and M3 was re-run as their
representative.

### 10.7 Files

| file | sha256 after | change |
|---|---|---|
| `fork-tower/src/server/Main.server.luau` | `405956d0…24af3` | `HttpService`; `Profile.session`; the load writes a fresh token when it takes the lock; `saveProfile` cancels a write whose token is not the record's, then sets `canSave = false` and warns |
| `robloxemu/check_forktower_plansecret.luau` | `02dc1fd3…a58b` | F6, F6c, F6d and the header; 79 → 96 assertions |
| `fork-tower/REVIEW-4.md` | — | this section, the note at the top, §9.8 item 4 marked wrong |
| `fork-tower/CLAUDE.md` | — | state block; invariant 13 (owner token, four ways to reopen it); what went wrong; commands |
| `fork-tower/REVIEW-3.md` | — | one sentence under the existing pointer |

Unchanged, and verified by sha256 against the start of this pass: `Fork.luau` (`6de71f07`),
`Config.luau` (`3a51da21`), `Hud.client.luau` (`68e6f125`), `Fork.spec.luau` (`db61d848`),
`world.check.luau` (`69610377`), `check_forktower.luau` (`5bdd6721`), `emu/*`, `wrap.py`.

Static checks: `luau-compile --binary` is clean on Main.server.luau and the check; `luau-analyze` shows
only Roblox-global noise (172 lines); `find_mojibake.py` reports nothing. No client or visual code was
touched. Nothing was committed, pushed or published.

### 10.8 Still open

1. **Real DataStores are modelled, not measured.** That an `UpdateAsync` transform returning `nil`
   cancels the write is Roblox's documented contract, and the emulator's. How late a queued write can
   land, and whether a shutdown's two releases ever straddle a whole session on another server, are
   not measured. The fix does not rely on either.
2. **`HttpService:GenerateGUID` uniqueness is assumed.** The emulator's GUID is a counter. M13 shows
   what a non-unique token costs, and the check catches it; in production nothing would.
3. **Deploy window.** A server running a build without the token does not check owners, so its late
   writes are not refused. This build has never been published, so no such server exists. If a
   token-less build ever goes live, shut its servers down on the update.
4. **A session that has not yet found out it was taken over** still grants its first redeemed code in
   memory while the write is cancelled. The grant dies with that session and is never saved, and it is
   not a secrecy issue.
5. **§10.2 is an argument, measured only on the orderings F1–F6d construct.** It is not a model check of
   every interleaving of loads and writes.
6. **`docs/new-game-checklist.md`** (outside this pass's ownership) should gain a line: when trust
   depends on a released lock, every profile write needs an owner token.
7. §9.8 items 1–3 and 5–6 stand, above all the teleporting script that makes traps free to a cheater,
   and the unmeasured real-engine `Random`.
