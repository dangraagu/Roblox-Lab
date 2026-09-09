# Fork Tower — Would You Rather Obby

Two doors on every floor. Both give you the trait behind them. **One of them is a trap** — it
builds a longer, busier climb instead of a normal one. An inscription on the fork platform names
the sign that marks the trap, so the choice is never a guess: it is "do I want *that* trait
enough to pay for it?" Ten floors up, your picks become a **Build Reveal** card — a title, a
rarity and a score. Rebirth rerolls the seed and the whole choice tree.

Concept brief: `../docs/game-radar/2026-09-09-roblox-game-radar.md`, section "4. Fork Tower".

---

## The two promises, and where they are enforced

Everything except these two sentences is presentation.

**1. No floor is unwinnable.** Both doors always grant their trait. The trap is a *toll*, never a
wall: the section behind it is longer and carries more hazards, and byte-for-byte the same step
height and the same gap. Every jump in the game is proven clearable by a player with **zero
traits**, because every floor grants one and an invariant that assumed the traits you happen to
have would depend on the choices it exists to protect.

> `tests/Section.spec.luau` — sweeps 200 levels × 6 themes × {normal, penalty} and asserts every
> rise fits inside `Safety × BaseJump` and every gap inside `Safety × maxJumpRun`, where
> `maxJumpRun` is *derived* from Roblox's gravity, not guessed. `src/server/Main.server.luau`
> re-runs `Section.check` at boot and warns loudly if a config change breaks it.

**1b. Your tower is yours alone.** A lane is 220 studs wide and the tower inside it is bounded to
a 60-stud corridor around its own centre line, so no part of your tower can reach into a
neighbour's — and the pool of lanes is sized to the place's `Players.MaxPlayers`, so there is never
a player the server has to seat on top of somebody else. Every checkpoint the tower hands you is a
point on a platform's *clear band*, never its centre, because the centre is where the hazard is.

> `tests/Section.spec.luau` chains 500 floors the way the server chains them and asserts nothing
> leaves the corridor; `Section.check` re-derives both bounds and rejects a section that breaks
> either. `check_forktower.luau` plays two full towers on the same seed, one safe and one taking
> every trap, and asserts no two towers overlap in X at all — then joins thirty players into a
> twenty-four lane server and asserts nobody ends up in somebody else's.

**2. No run is a coin flip all the way down.** Every fork is readable to certainty. Both doors
carry exactly two signs; exactly one door carries the sign the inscription names; and the
inscription says outright whether that marks the trap or — from floor 4, when the warden starts
lying — the safe door. Read it and you never eat a trap. Flip a coin and you eat one half the
time. That gap *is* the game.

> `tests/Fork.spec.luau` — 40 000 forks. A reader hits **zero** traps; a blind left-door climber
> hits 50%; a climber who knows the signs but ignores the liar line is wrong on exactly the
> inverted floors. Plus everything that could become a *second* tell: door position, sign
> arrangement, single signs, trait power, and what the previous one and three floors predict.
>
> The reader is measured **off the doors' own sign lists**, not off `floor.markedDoor`. That field
> is derived from `trapDoor` inside `Fork.plan`, so a check written against it compares a field
> with the field it came from and is true by construction — a mutation that put the named sign on
> *both* doors, turning every fork into a real coin flip, left this suite green at 47/0. Witness E
> is that mutation, kept.

---

## Run the tests

```
cd D:/Claude/Roblox/fork-tower
luau tests/Fork.spec.luau          # 53 passed, 0 failed
luau tests/Section.spec.luau       # 47 passed, 0 failed
luau tests/Build.spec.luau         # 31 passed, 0 failed
luau tests/Codes.spec.luau         # 19 passed, 0 failed
luau tests/Rng.spec.luau           # 32 passed, 0 failed
luau tests/responsive.spec.luau    # 70 passed, 0 failed
```

`luau` is the CLI at
`C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe`.
No Roblox is needed: every module under `src/shared/` is pure and takes its dependencies as
arguments.

Syntax and analysis:

```
luau-compile --binary src/shared/*.luau src/server/*.luau src/client/*.luau
luau-analyze <file> 2>&1     # writes to STDERR; without 2>&1 you filter nothing
py -3 ../tools/find_mojibake.py --root fork-tower
```

## Boot it headless

A game that has never been booted headless is not finished.

```
cd D:/Claude/Roblox/robloxemu
py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
luau check_forktower.luau          # 82 passed, 0 failed
```

`check_forktower.luau` runs the real server script against the emulator and then *plays the game*:
a reader walks all ten floors following the inscription (and must build zero penalty sections), a
second climber ignores the liar line (and must be punished on exactly floors 4, 6 and 8 of run
seed 4), their floor-4 sections are compared platform for platform, hazards are touched, an
answered door is re-pulled, another player's door is pulled, the summit card is caught off the
remote, a rebirth is taken and a lane index is recycled.

---

## Layout

```
default.project.json      rojo: src/server -> ServerScriptService
                                src/client -> StarterPlayerScripts
                                src/shared -> ReplicatedStorage
src/shared/Config.luau    every tunable, one table
src/shared/Fork.luau      THE game: seed + floor -> which door is the trap  (pure)
src/shared/Section.luau   one themed obby section, clearability-checked     (pure)
src/shared/Build.luau     the summit card from a pick list                  (pure)
src/shared/Codes.luau     one-time redeemable codes                         (pure)
src/shared/Rng.luau       deterministic LCG (verbatim from the sibling games)
src/shared/Responsive.luau  HUD sizing rules (verbatim)
src/shared/Fx.luau        lighting presets + particles (+ a new `Fork` preset)
src/shared/FxClient.luau  camera/HUD juice (verbatim)
src/server/Main.server.luau  authoritative: lanes, doors, sections, saving
src/client/Hud.client.luau   display only
tests/*.spec.luau         one per pure module
```

**Shared modules take their dependencies as ARGUMENTS.** A bare `require("./Rng")` resolves in the
luau CLI and is invalid in Roblox; only the server and client scripts require, and they do it from
ReplicatedStorage. That exact mistake once made a server fail to load while every unit test stayed
green.

---

## Tuning

Everything lives in `src/shared/Config.luau`. The numbers that are *not* free to change:

| Field | Constraint |
|---|---|
| `Tower.StepMax` | must stay `<= Safety * Jump.BaseJump` — asserted |
| `Tower.GapMax` | must stay `<= Safety * Section.maxJumpRun(cfg)` — asserted |
| `Traits[].jump` / `.speed` | must never be negative, or the traitless clearability proof stops covering the build that took it — asserted |
| `Build.Rarities[].threshold` | every tier must be earnable by a real ten-floor run — asserted by *playing* 400 seeds three ways |
| `Fairness.*` | these are the thresholds `Fork.spec` measures against; loosening one is loosening the game's promise |

There is deliberately **no** "max identical trap sides in a row" setting. The first draft had one,
capped at three, and the cap leaks: after three left-traps you know the fourth is on the right,
free, without reading anything. `Fork.spec` caught it as a lopsided three-floor transition table.

---

## What is NOT built yet

Honest list. Every one of these is either scoped out of v1 or a gap between the concept brief and
the code.

**Not done at all**
- **No Roblox experience, no publish, no commit, no push.** The tree is deliberately dirty.
- **No marketing.** No thumbnail, no `MARKETING.md`, no store copy beyond the brief's paste-ready
  description, no `marketing/shots/`.
- **Gamepasses are dead.** `Config.Passes` has `ExtraSkip` and `GoldTrail` with id `0` and
  `Enabled = false`; nothing reads them. `profile.passes` is loaded and saved and then never
  consulted by a single code path.

**Gaps against the concept brief**
- **Choices do not narrow the next fork.** The brief says "each pick narrows/reshapes the next
  section's theme, hazards, and cosmetics". What is implemented: the section you climb takes the
  *theme of the trait you just took*. The next fork's two options are drawn independently of your
  history, so the choice tree is a sequence of independent binaries, not a narrowing tree.
- **"Skins" are door and platform colours.** No character skins, no cosmetics, no accessories.
  A trait changes your jump/speed numbers and the colour and material of the next section.
- **The card is not share-ready.** It renders client-side as promised, but there is no screenshot
  button, no copy-to-clipboard and no share flow — the player takes their own screenshot.
- **Hazards all look the same.** `Section` gives each hazard a `kind` (`spike`/`saw`/`brand`/
  `shard`) and the server writes it to an attribute, but every one of them renders as the same red
  neon cube. Nothing moves; they are static blocks that send you back to your checkpoint.
- **The leaderboard ranks best build score, not run time.** A speedrun board would need a clock,
  which does not exist.

**Known thin spots**
- **The HUD has never been measured by `hudcheck`.** The layout follows the same Responsive rules
  as the sibling games and the panels are authored the same way, but `robloxemu/emu/hudcheck.luau`
  has not been pointed at it across the six viewports, so "it fits a phone" is an argument here,
  not a measurement.
- **Ten floors of a ten-floor game is the whole game.** There is no endless mode, no difficulty
  tier beyond the level curve, and reaching the summit leaves you with one button: Rebirth.
- **One trap shape.** Every trap is "the section is four platforms longer and two hazards busier".
  There is no variety of punishment.
