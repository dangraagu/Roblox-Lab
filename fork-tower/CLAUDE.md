# Fork Tower — context for a fresh session

Read this before touching anything. `README.md` says what the game is; this says what state it is
in, what must stay true, and what bit us building it.

---

## State (2026-09-10, after the Studio pass — read STUDIO.md)

**Built, green, PLAYED IN STUDIO, never published.** No Roblox experience exists, nothing is
committed, nothing is pushed — deliberately, per the build instruction. The tree is dirty.

```
Fork.spec        53 passed, 0 failed
Section.spec     50 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
check_forktower 119 passed, 0 failed   (robloxemu; was 108 — three new blocks from the Studio pass)
world.check      71 passed, 0 failed   (fork-tower's own: the read, the lane pool, the saved skip)
```

**It has now been opened in Roblox Studio and played.** `STUDIO.md` is the record: what ran, what
was measured, every screenshot, the console. Three things came out of it and all three are fixed:

1. **Every player spawned 174 studs from their own tower.** `CharacterAdded` fires while the
   character model is still UNPARENTED; one frame later the engine parents it AND drops it on the
   only enabled SpawnLocation, throwing away the CFrame `onCharacter` had just written. The game
   was unreachable, with eight green suites. `onCharacter` now waits for `char.Parent` first.
2. **A read costs 1.17 s, measured** — `PromptButtonHoldBegan` does reach the server, so REVIEW-3's
   open item 4 is closed and 1.1 s is the right number. But it arrives ~32 ms late, so the
   `remaining <= 0` fast path is never taken and every read flashed a "(0.0 s)" toast. The toast is
   now conditional; **the charge is unchanged.**
3. **`SignEmoji.crack` was 🪨 U+1FAA8, which Roblox draws as an empty box.** Now 🗿 U+1F5FF.
   Roblox's font covers Emoji 12.0 and not 13.0 — measured, see STUDIO.md.

`luau-analyze` is clean on every source after filtering Roblox-global noise. `find_mojibake.py`
reports nothing. REVIEW-3's mutation sweeps applied 11 then 12 deliberate defects to the shipping
source and killed every one; the controls (a door light's Brightness, and `RespawnLift`) were
correctly ignored.

**The core loop changed.** REVIEW-2's headline was that the game was dominated: the star count was
printed on every door, so never reading was optimal. A door now shows only that it is a door, and
reading the inscription costs `Config.Fork.ReadSeconds` on the SERVER's clock. That number is
measured, not chosen — see `tests/readcost.measure.luau` and REVIEW-3.md. Read REVIEW-3.md before
touching `dressFork`, `onReadInscription`, or anything in `Config.Fork`.

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

9. **An unread door shows NOTHING, and the read is timed by the server.** One function,
   `dressFork`, owns both states of a fork, and every placeholder in `buildFork` is the UNREAD one
   so that a fork which somehow escapes dressing fails closed. The `rule` payload in `pushState` is
   gated on the same `p.readFloors` set the world is, so the two cannot drift. The hold on the
   prompt is client-side feel; `onReadInscription` charges the time itself, which is why an
   exploiter firing the prompt gets no discount.

   **That includes the ATTRIBUTES.** `ForkPad.TellKind`, `ForkPad.RuleInverted` and `Door.Marked`
   replicate, and between them they ARE the fork — so `dressFork` writes them and removes them
   (`SetAttribute(name, nil)`) while the floor is unread. Never set a fork's own data in
   `buildFork`. What an unread fork puts on the wire is enumerated and asserted line for line in
   `robloxemu/check_forktower.luau`; adding an attribute anywhere under `Fork_<n>` turns that
   assertion red on purpose, including if you rename it or move it onto a child.

10. **A cost the player already paid is SAVED.** `profile.readFloors` and `profile.skipped`, both
    written as dense lists of level numbers because a JSON round-trip turns numeric keys into
    strings and `saved.readFloors[3]` comes back nil. A skip spent on a floor that is not recorded
    means `buildLane` re-derives `Fork.isTrap` on rejoin and rebuilds the penalty section — the
    player loses the skip AND gets the trap.

12. **NEVER place a character from inside `CharacterAdded` without waiting for `char.Parent`.**
    Measured in Studio: the event fires while the model is still unparented with the root part at
    the origin, and one frame later the engine parents it AND puts it on the enabled SpawnLocation,
    silently discarding whatever CFrame you wrote. This is the defect that made the whole game
    unreachable while every suite was green — see STUDIO.md §3. The wait is `task.wait(1 / 60)`,
    a DURATION, because a bare `task.wait()` is a zero-length yield on a virtual clock and the
    headless check cannot express the defect against one.

11. **The checkpoint sits at the MIDDLE of its clear band.** Hazard clearance and platform-edge
    margin always sum to the width of the feasible interval, so one is bought with the other and
    only the midpoint maximises the smaller. Both `Section.build` and `Section.check` know this.
    Neither end of the band is safe: the far end is 0.00 studs from the drop, the near end is
    inside the hazard.

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

0. **Read STUDIO.md first, then REVIEW-3.md's "Still open" list.** REVIEW-3 items 2, 3 and 4 are all
   CLOSED. What is still open from item 1: **no human has summited** (Studio played floors 1–2,
   both branches) and **no phone has seen it** (the viewport was 2889x1201 throughout). STUDIO.md
   §9 also carries four polish items, the top one being that on the first frame three billboards
   draw on top of each other because `MaxDistance = 220` reaches from a tower to the waiting pad.
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

# where Config.Fork.ReadSeconds comes from — re-run after any tuning change
cd D:/Claude/Roblox/fork-tower && luau tests/readcost.measure.luau

# headless boot (re-wrap after ANY src change) — BOTH runs, they cover different things
cd D:/Claude/Roblox/robloxemu
py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
luau check_forktower.luau
cd D:/Claude/Roblox/fork-tower && luau tests/world.check.luau

# open it in Roblox Studio and play it (see STUDIO.md §"What I ran")
cd D:/Claude/Roblox/fork-tower && rojo build -o ForkTower.rbxlx
# tools/studio_open.ps1's $places table has no "fork-tower" key yet — one line, someone who owns
# tools/ should add:  "fork-tower" = "ForkTower.rbxlx"
py -3 D:/Claude/Roblox/tools/studio_mcp.py studios   # the only honest test of the MCP toggle

# static
luau-compile --binary <file>
luau-analyze <file> 2>&1
py -3 D:/Claude/Roblox/tools/find_mojibake.py --root fork-tower
```

`luau*` are in
`C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/`.

Comments in the source are Norwegian where they match the sibling games; docs and commit messages
are English.
