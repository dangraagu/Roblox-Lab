# Fork Tower — context for a fresh session

Read this before touching anything. `README.md` says what the game is; this says what state it is
in, what must stay true, and what bit us building it.

---

## State (2026-09-10)

**Built and green, never published.** No Roblox experience exists, nothing is committed, nothing
is pushed — deliberately, per the build instruction. The tree is dirty.

```
Fork.spec        47 passed, 0 failed
Section.spec     32 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
check_forktower  50 passed, 0 failed   (robloxemu, boots the real server and plays ten floors)
```

`luau-analyze` is clean on every source after filtering Roblox-global noise. `find_mojibake.py`
reports nothing. A mutation sweep of 21 deliberate defects killed 21; 4 cosmetic controls were
correctly ignored.

---

## Invariants — do not break these without changing the spec first

1. **Shared modules take dependencies as ARGUMENTS.** `Fork.plan(cfg, runSeed, Rng)`,
   `Section.build(cfg, ...)`, `Build.reveal(cfg, picks)`. A bare `require("./Rng")` resolves in the
   luau CLI and is INVALID in Roblox. Only `Main.server.luau` and `Hud.client.luau` require, from
   ReplicatedStorage.

2. **Every Instance goes through `make(class, parent, props)`** in `Main.server.luau`. The parent
   is a required positional argument and is asserted. There is no other way to create one in that
   file, and that is on purpose: Grow a Crystal shipped an unreachable core loop because one Part
   never had `.Parent` assigned, with 166 green unit tests.

3. **`DataStoreService:GetDataStore` is pcall'd** (`tryStore`). Unwrapped it raises in an
   unpublished place and kills the whole server script at load.

4. **No trait may lower jump or speed.** Section.spec's clearability proof is measured against a
   *traitless* player; a negative modifier would put the build that took it outside the proof.
   `traitTotals` also clamps upward to `BaseJump` / `WalkSpeed` as a belt, which would silently
   no-op a negative trait — a defect of its own. Config says this at length.

5. **Seeds are avalanche-hashed, never derived linearly.** See the long note at the top of
   `Fork.luau`. Two LCGs that share a multiplier are related by `y_n - x_n = A^n * d` forever; an
   affine seed makes the whole tower one lattice. `mix32` (MurmurHash3's finalizer, with a
   halves-based `mul32` so nothing exceeds 2^53) is what breaks it. `Section.luau` carries the same
   mixer for the same reason.

6. **The trap side is a plain fair coin, floor to floor.** No anti-streak cap. A cap is a tell.

7. **The sign sets are exchangeable.** Both doors carry exactly `SignsPerDoor` signs; the pair of
   sets is drawn as an ordered pair of *distinct* subsets before anything consults the trap. Sign
   count, single signs and whole arrangements must all be uninformative — only the inscription
   resolves a fork.

8. **The trap is longer, never steeper.** `penalty` adds platforms and hazards and nothing else.

---

## What went wrong building it (all of it caught by a test, none of it by reading)

- **The first `Fork.luau` seeded a fresh LCG per floor as `base + level*3571` and took the first
  draw.** Consecutive seeds differ by a constant, so an LCG's first output moves by a constant:
  the trap side and the tell marched in a short repeating cycle, identical for every player. The
  50/50 check passed. The streak check passed — a cycle is *regular*, not streaky. Only a
  transition table saw it (0.136 off uniform).

- **Per-stream salts of 41/43/47/53 made four streams that were the same sequence.** Their first
  outputs differ by 1.4e-9. The trap side and the sign draw were correlated, and one arrangement of
  signs predicted the trap 57% of the time. Multiplying the salt to a large offset and burning six
  steps only got it to 56%. The lattice is the problem, not the spacing.

- **The anti-streak cap was a tell.** Capping identical trap sides at three means the fourth floor
  is free to anyone who counts. Removed; the order-3 transition table is what would notice it
  coming back.

- **The first "no second tell" check measured a tautology.** It asked "restricted to floors where
  a non-tell sign shows on exactly one door, is that door the trap half the time?" With four signs
  and two per door, 80% of forks have the doors sharing one sign and holding one each — so the
  marked door's lone sign *is* the tell and the other door's lone sign is its complement. The
  check reported a correct generator as 0.00 instead of 0.50 and would have forced a real design
  to be broken to satisfy it. Replaced with the question a player actually faces: for every
  *arrangement* of signs, is the trap on the left half the time?

- **The rarity ladder had a dead tier.** Thresholds 0/16/24/32/40 looked fine and made "Vanlig"
  unreachable: a real ten-floor run scores 19–57 however you play it. Build.spec now *plays* 400
  seeds three ways and requires every tier to be earnable. Thresholds are the measured quintiles.

- **A door acted on whoever pulled it.** `onDoorChosen` looked up `lanes[who]`, so pulling a prompt
  in somebody else's tower answered the puller's own fork at that floor. The check had an
  assertion for exactly this and it passed **for the wrong reason** — it ran after the reader had
  summited, so the server refused on "you are already at the top". The mutation sweep deleted the
  guard and the check stayed green. Fixed: the owner is captured at prompt-creation time and
  compared first; the assertion now runs with both climbers at their own floor 1.

- **A control caught a brittle spec.** Build.spec hardcoded `"🔥 Glødestøvler"` in a purity
  assertion, so renaming a trait turned the suite red for a cosmetic edit. Expected values are read
  from Config now. Codes.spec had the same shape and got the same fix.

---

## Next, roughly in order

1. **Point `hudcheck` at it.** `robloxemu/emu/hudcheck.luau` measures every panel across six
   viewports from 414x800 to 1920x1080. The HUD follows the Responsive rules but has never been
   measured, and the reveal card is a big centred frame — exactly the shape that fails a phone.
2. **Make choices narrow the tree.** The brief promises it and `Fork.plan` currently draws each
   floor's two traits independently of the picks above it. The plan is already built per run, so
   the history is available; the fairness spec would need a matching "narrowing still leaves every
   trait reachable" assertion.
3. **Give the trap more than one shape.** Longer-and-busier is the only punishment in the game.
4. **Make hazards move**, or drop the `kind` field that promises four of them and renders one.
5. **Wire or delete `Config.Passes` and `profile.passes`.** Dead as shipped.
6. Adversarial review, then the publish path: experience → git-ignored `publish_*.bat` →
   content-maturity questionnaire (the Preview page is ground truth) → Public.

---

## Commands

```
# tests
cd D:/Claude/Roblox/fork-tower && luau tests/<Name>.spec.luau

# headless boot (re-wrap after ANY src change)
cd D:/Claude/Roblox/robloxemu
py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
luau check_forktower.luau

# static
luau-compile --binary <file>
luau-analyze <file> 2>&1
py -3 D:/Claude/Roblox/tools/find_mojibake.py --root fork-tower
```

`luau*` are in
`C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/`.

Comments in the source are Norwegian where they match the sibling games; docs and commit messages
are English.
