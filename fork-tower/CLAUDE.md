# Fork Tower — context for a fresh session

Read this before touching anything. `README.md` says what the game is; this says what state it is
in, what must stay true, and what bit us building it.

---

## State (2026-10-01, pass 2 of 2: the complete-game standard — EYECANDY.md §16)

Every item of `docs/complete-game-standard.md` was checked against pass 1's tree (EYECANDY §16.1 is the list) and
what was missing was built test first, mutation-swept (29 of 29 killed, the control survived all 27 suites) and
documented. Not seen in Studio, not re-reviewed, not committed or published.

1. **§3 the highscore board, public + friends** (`Board.luau`, +1 Jump's template verbatim; `Board.client.luau`; the
   board section of Main.server). The metric is the best Build Reveal score a summit banked, computed by the server.
   Stored encoded in `ForkTower_LB_v2` (ties to whoever reached it first), written only upward and only by the
   record's owner (invariant 21). A physical board behind every tower's spawn (`Lane_n.TopBoard`) with an
   `Offentlig / Venner` prompt; friends on demand, capped at 200, cached, throttled; names looked up by the server
   and remembered, never saved. It replaced a public-only HUD list that stored the raw score with `SetAsync` and
   looked every name up on every client on every refresh.
2. **§1 spawn**: `plr.RespawnLocation` is the player's own `LaneSpawn` (enabled now), or the `WaitingSpawn` until
   they have a tower (invariant 22). `check_forktower_board` also walks the whole player path once: spawn, earn a
   skip with FORK, spend it on a trap, ten floors, the summit's card on the board, leave, rejoin, rebirth.
3. **§2 the brag**: no crown landed in 30-45 min of normal play (the ice crown at 10 summits measured 45.4 min).
   The ice crown is now at **8 summits, 36.3 min** (`Config.Env.BragCrown`); the star crown at 25 (113.4 min) is the
   long-term goal. `Pacing.spec` holds both. **The 8 is a change to the owner's 5 / 10 / 25: flagged for him.**
4. **§4 the documents**: README's store description (977 characters), `MARKETING.md` (8 vertical clips with
   staging, all `new`: `tools/film_game.py` has no Fork Tower scenarios), the 1920x1080 thumbnail size, needs-Studio
   items 29-31, and `tests/docs_check.py`, which holds all of it (and this file's gate list) to the source.

```
specs     1308 / 0   (Board 66 new, Pacing 108; the rest as pass 1)
world.check 71 / 0   check_forktower 131 / 0   check_forktower_board 115 / 0 (new)   plansecret 96 / 0
env 235 / 0   env_secret 92 / 0   env_join 37 / 0   exit 30 / 0   sitdrop 15 / 0   crown 15 / 0
hud PASS (16 viewports, overlap on, Board.client loaded)   hud_open 259 / 0   hud_play 611 / 0
docs_check.py 94 / 0 (new)
```

---

## State (2026-10-01, pass 1 of 2: the second review, the owner's decisions, queued job I — EYECANDY.md §15)

The first attempt at this pass was cut off by a usage limit after the code and most tests, before the
mutation sweep and EYECANDY §15. The resume session (2026-10-01) re-read every changed and new file, ran
every gate on the tree as found (all green), finished the owner's decisions (one more: no gamepasses), ran
the mutation sweep and wrote §15. Every count below is from that session's final run.

The second review's six findings all reproduced; each is held by a test that fails with the fix taken out
(the sweep, EYECANDY §15.4) and is fixed in the game: the ☕ Hvil sit survives its own drop (the +1 Jump
Studio fix, ported); the HUD fits landscape phones down to 480 px wide (the row goes into the header, the
counter narrows, then the toggles become glyphs, the drawers narrow beside the inscription; the Rebirth
drawer is usable at 568x320); the ring and the warning stay up as long as a hit can land
(`Hazards.threatLive`); the part, beam, trail and light budgets are capped in TowerArt with a reserve the
telegraph always gets (and, found by the resume session, a piece the cap held back now fades in instead of
popping in); every band's second floor is its own lighting phase (`Config.Env.Layers`), so the
world never stands still for more than 53 s in any measured run; README's stale claims are fixed. The
owner said "take the recommended option for all": the inscription is hidden while climbing on a landscape
phone and the toast takes its slot; the summit's crown grows rarer at 5 / 10 / 25 SUMMITS (new saved
`summits`, public leaderstat `Topper`); the dead gamepass placeholders are deleted (no Robux in v1).
Queued job I is closed: the exit clears a floor only for a body the server sees standing on it, once the
section could have been climbed (invariant 16). Not seen in Studio, not re-reviewed, not published.

```
specs     1237 / 0   (Codes 20, Section 57, EnvConfig 505, Pacing 103; the rest unchanged; Pacing ~2 min)
world.check 71 / 0   check_forktower 129 / 0   check_forktower_plansecret 96 / 0 (helpers only)
check_forktower_env 235 / 0   env_secret 92 / 0   env_join 37 / 0   hud PASS (16 viewports)
check_forktower_hud_open 259 / 0   check_forktower_hud_play 611 / 0
NEW: check_forktower_exit 30 / 0   check_forktower_sitdrop 15 / 0   check_forktower_crown 15 / 0
```

**Any check that moves a body by hand must now climb like a person**: stand on the exit and give the server
the section's least time (`Section.minClimbSeconds`), or it will never clear a floor. Every fork-tower
check's climb helper does this now; copy one.

---

## State (2026-09-24, after the adversarial review — EYECANDY.md §14)

An independent review of the environment work found three things; all three were reproduced on the tree
below, held by a test that went red on it, fixed in the game, and mutation-swept (17 of 17 killed, 4 of 4
controls survived). The fixes themselves are not re-reviewed; nothing is committed, Studio not opened.

1. **On a landscape phone the band chip and ☕ Hvil sat over the player's own character** (head to waist,
   and the hazard strike point in 400 of 400 launches). `Hud.client` now has `PLAY_TOP`: nothing that stays
   up may reach the character, so on every landscape phone the row goes up into the header (the counter
   moves beside ☰ Meny where the chip needs the width). New gate `check_forktower_hud_play.luau` projects
   the character through Roblox's default camera; run it after ANY HUD layout change, with hud_open.
2. **A read begun on the exit platform's edge could be knocked mid-hold**: the next fork's LES prompt reaches
   16 studs, over the exit and off the pad. `Climb.gate` now dismisses a hazard in flight once the floor is
   cleared, and Ambience scans the lane the frame something arrives in it (invariant 15).
3. **The band title card covered the character's legs on a landscape phone, ran off a 640x300 screen, sat on
   open drawers in portrait, and covered the head on a 1366x768 laptop.** It now fills a HUD-placed slot: the
   strip above the character where it fits, else on the chip; a hazard warning ends it.

Measured and NOT fixed (pre-existing HUD, EYECANDY.md §10 items 22-24): the inscription panel hides 64-74 % of
a hazard's flight on an 800x360 phone at pitch -15/-30 (strike point and ring always visible now); the toast
covers the character's head there for 3.5 s after each notice; on 640x300 the inscription's edge crosses the
crown of a tall avatar's head (bounded in the check).

```
Climb.spec        67 passed, 0 failed   (was 66; the floor clear dismisses)
(every other spec unchanged: 1 069 / 0 in all; readcost 1.110 s and Pacing output byte-identical)
check_forktower_env        215 passed, 0 failed   (was 204; exit-edge read, floor-clear lag, warning ends a card)
check_forktower_hud_play   324 passed, 0 failed   (new; 242 / 72 on the tree below)
(world.check 71, check_forktower 129, plansecret 96, env_secret 92, env_join 37, hud PASS, hud_open 157: unchanged)
```

---

## State (2026-09-24 — the tower changes as you climb; read EYECANDY.md)

Resumed 2026-09-24 after the first build session was cut off mid-sweep (EYECANDY.md §13): two of the new
checks were flaky (a lightning flash inside a snapshot; a coverage count that depended on random
critters; a hazard due inside the env check's first run), fixed; a Config name typo silently deleting scenery and the join card's wait for the profile
were untested, now held by `check_forktower_env` and the new `check_forktower_env_join`; TowerArt's
hide-then-show rule and weather cap were untested, now probed directly; the phone drawers and the Build
Reveal card were 1 px tall on a landscape phone, fixed (below); the whole mutation sweep re-run on the
final tree (50 mutations, 4 controls). Counts below are the final tree's.

**Six environment bands, rare telegraphed hazards, rest, and a thumbnail shot list, per the owner's brief
(2026-09-17). All client-side; the server is byte-identical.** Dungeon (floors 1-2), overgrown garden (3-4),
clockwork (5-6), storm (7-8), observatory (9-10), the star crown (the summit). The band is NAMED by the
server's floor and BLENDED by the climb inside the chosen section, so at a fork it is a function of the
floor number alone and identical for both doors. Hazards run only while climbing a section: the fork pads
are a sanctuary (nothing runs, launches or hits there), which is where a player reads and where they rest.
Measured: one near-hit per 2.4 min of play for a normal reader who reacts, never a hit; the read's
break-even is untouched for anyone who reacts. NOT seen in Studio, not independently reviewed, nothing
committed.

```
Fork.spec        71 passed, 0 failed
Section.spec     50 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
Climb.spec       66 passed, 0 failed   (new)
EnvConfig.spec  361 passed, 0 failed   (new)
Pacing.spec      87 passed, 0 failed   (new; tests/PlayModel.luau is its model)
EnvBands.spec   124 passed, 0 failed   (template, verbatim)
Hazards.spec    102 passed, 0 failed   (template, verbatim)
Rest.spec        55 passed, 0 failed   (template, verbatim)
world.check      71 passed, 0 failed
check_forktower 129 passed, 0 failed
check_forktower_plansecret 96 passed, 0 failed
check_forktower_env        204 passed, 0 failed   (new: the glue through the real client)
check_forktower_env_secret  92 passed, 0 failed   (new: the environment reveals nothing)
check_forktower_env_join    37 passed, 0 failed   (new: the join card waits for the profile, 16/40 s loads)
check_forktower_hud        PASS                   (new: hudcheck, HUD + ambience row, overlap on)
check_forktower_hud_open   157 passed, 0 failed   (new: the phone drawers and the Build Reveal card, OPEN)
```

**The HUD on a landscape phone was broken, and the ambience row made it worse** (EYECANDY.md §13 item 7):
the open ☰ Meny drawer (Rebirth!), the 🏆 Topp drawer and the Build Reveal card were 35 px tall on 800x360
before the row and 1 px after it; hudcheck never measures an open drawer or the card. Fixed in
`Hud.client.luau` (compact only: drawers clear the centred stack only where they share its columns; the
card takes the free column right of the inscription when there is no room under it). The new
`check_forktower_hud_open.luau` is the gate; run it after ANY HUD layout change.

---

## State (2026-09-17, third pass — a late releasing write re-released a trusted record; REVIEW-4.md §10)

**The second-pass trust rule assumed a released record is the last session's final state, and a
queued write broke that.** A shutdown makes two releasing saves per player (BindToClose and
PlayerRemoving), and `saveProfile` wrote whether or not the record was still its own. Measured in
the emulator: one lands, the next server loads the released record, trusts it and walks every door,
crashes before writing; the other, queued write lands late and re-releases the record without those
walks. The session after that planned the walked secrets: 120 of 120 traps known on the second-pass
source. Found by reading the rule against the write paths, not by an attacker. Closed by an ownership
token (invariant 13): the load that takes the lock writes a fresh `session`, and every write lands
only while the record still carries its own. Now 59 of 120 (chance). Still never published, nothing
committed.

```
Fork.spec        71 passed, 0 failed
Section.spec     50 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
world.check      71 passed, 0 failed
check_forktower 129 passed, 0 failed
check_forktower_plansecret 96 passed, 0 failed   (was 79; F6, F6c, F6d added; 91/5 on the second-pass source)
```

---

## State (2026-09-17, second pass — a session that cannot save was an oracle; REVIEW-4.md §9)

**The fix below was attacked the same day and the attacker won 240 of 240 forks with no read paid.**
A READ-ONLY session (another server still holding the lock) loaded the SAVED secrets, let a script
walk through every door, and saved nothing; the real session afterwards was the same run with every
trap known. Closed by the trust rule in invariant 13: a session plans an unseen floor from its saved
secret only if it can save AND the record was released when it loaded; otherwise unseen floors are
drawn fresh, seen floors are kept, and nothing is revealed after a releasing save. The attacker's own
script now scores 114 of 240 (7203 of 14 400 pooled over 60 runs). Still never published, nothing
committed.

```
Fork.spec        71 passed, 0 failed
Section.spec     50 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
world.check      71 passed, 0 failed
check_forktower 129 passed, 0 failed
check_forktower_plansecret 79 passed, 0 failed   (was 41; part F added; 72/7 on the attacked source)
```

---

## State (2026-09-17, the plan secret — read REVIEW-4.md)

**The trap plan was computable on the client, and now it is not.** Measured 2026-09-17: `Fork.luau`
is in ReplicatedStorage and derived every floor from `Config.WorldSeed` and the run seed, and the
run seed is `leaderstats.Rebirths + 1`. A probe matched 30 of 30 honestly-read forks from
replicated data alone; REVIEW-3's attribute gating had closed the attributes and left the generator
open. The hidden half of every floor is now a server-drawn 32-bit secret per floor (invariant 13).
Still never published, nothing committed.

```
Fork.spec        71 passed, 0 failed   (was 53 — 18 new: the plan secret, witnesses F and G)
Section.spec     50 passed, 0 failed
Build.spec       31 passed, 0 failed
Codes.spec       19 passed, 0 failed
Rng.spec         32 passed, 0 failed
responsive.spec  70 passed, 0 failed
world.check      71 passed, 0 failed
check_forktower 129 passed, 0 failed   (robloxemu; seeded profiles now carry their secrets)
check_forktower_plansecret 41 passed, 0 failed   (robloxemu, NEW; 24/17 on the pre-fix bundle)
```

`tests/readcost.measure.luau` still prints the 1.110 s break-even to the digit, and Build.spec's
rarity quintiles are unchanged: both now plan with `Fork.legacySecrets`, which reproduces the
2026-09-17 plans field for field.

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
check_forktower 129 passed, 0 failed   (robloxemu; 108 -> 119 from the Studio pass, -> 129 once
                                        the emulator learned the engine's spawn order)
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

1. **Shared modules take dependencies as ARGUMENTS.** `Fork.plan(cfg, runSeed, Rng, secrets)`,
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
   mixer for the same reason. The hidden streams (invariant 13) are seeded the same way, with the
   floor's secret standing where the public base stood: `mix32(secret + salt * SALT_MIX)`.

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

    **The wait buys a SECOND thing, and it is easy to delete by accident.** The fall-rescue loop
    at the bottom of `onCharacter` is `while char.Parent ~= nil do`, so starting it while the
    model is still unparented starts a loop whose condition is already false: it exits on its
    first test and a player who walks off their tower is never brought back. Measured against the
    built bundle with the wait removed — a root part dropped to y = -500 was still at
    `0.00, -500.00, 0.00` a full second later; with the wait it was back on its checkpoint the
    same second. `robloxemu/check_forktower.luau` "SPAWN ORDER, ORDINARY PATH" now runs that
    loop; nothing else in the repo does.

    `robloxemu/Players:simulateSpawn` models the engine's order as of 2026-09-10
    (`robloxemu/SPAWN-ORDER.md`), so an ORDINARY `simulateSpawn` in a check is now a real test of
    this — it no longer has to be replayed by hand the way STUDIO FINDING 1 does.

13. **Half of every floor is a SERVER SECRET, and nothing public may compute it.** `Fork.luau` and
    `Config.luau` are in ReplicatedStorage and the run seed is `leaderstats.Rebirths + 1`, so
    anything derived from `(WorldSeed, runSeed, level)` is computed by any client that cares to.
    Measured 2026-09-17: 30 of 30 traps predicted without a read. So a floor has two halves:

    * **visible** — the two doors' sign carvings — from the public seed, the same for everyone on a
      run seed;
    * **hidden** — trap side, liar line, which exclusive sign is the tell, both traits and their
      slots — from `profile.floorSecrets[level]` and NOTHING public: one uniform 32-bit integer per
      floor per run, drawn by `mintSecret` (a server-lifetime `Random` XOR a fresh `Random.new()`),
      re-drawn on rebirth, saved in the same write as `readFloors`/`slots`, and never written to an
      Instance, an attribute, a leaderstat or a remote.

    Three rules keep it a secret, and each has a Fork.spec assertion and a witness that breaks it:
    **nothing visible before a read is derived from a secret** (or a script brute-forces 2^32 seeds
    against floor 1's carvings — witness G, "the naive salt fix"); **each floor's secret is drawn on
    its own** (or a few paid reads pin one 32-bit secret and the rest of the run is free); **the
    hidden half depends on no public input at all** (witness F, the 2026-09-17 leak re-created).
    `Fork.plan` REFUSES to plan without secrets — there is no public fallback, because a public
    fallback is the defect.

    `Fork.legacySecrets(cfg, runSeed)` is the public derivation, kept for exactly one job: a profile
    saved before 2026-09-17 keeps it on the floors its player had ALREADY SEEN (answered, read, or
    climbed past) and gets fresh secrets for the rest (`resolveSecrets`). Nothing visible depends on a
    secret, so the unseen re-draw changes nothing on screen: no run is reshuffled, at any level.
    Using `legacySecrets` for any floor a player has not seen reopens the leak.

    **A saved secret for an UNSEEN floor is only planned by a session that will keep what it
    reveals.** Measured 2026-09-17 (REVIEW-4.md §9): a READ-ONLY session planned the saved secrets
    and saved nothing, so a script walked every door there and knew all 240 of 240 traps in the real
    session afterwards. `loadProfile` now TRUSTS the record only when both hold: `canSave` (the lock
    is held and the load landed) and the record was RELEASED when it loaded (`lockUntil == 0`, which
    only a leave-save or BindToClose writes). A released record carries every reveal of the session
    that wrote it, because every reveal goes into the profile before the world shows it and
    `p.released` (set before a releasing write) makes `onDoorChosen`, `onReadInscription` and the
    read's `finish` refuse afterwards. Untrusted — read-only, after a crash, after a failed load —
    every unseen floor gets a fresh `mintSecret()`; floors already seen keep their saved secret, so
    nothing on screen moves and no run is reshuffled.

    **The record has ONE owner, and only the owner's writes land** (REVIEW-4.md §10). "A released
    record carries every reveal" is only true if no older write can land after a newer load, and a
    shutdown makes two releasing writes per player (BindToClose, then PlayerRemoving), which a queue
    may land late: measured, 120 of 120 traps known after a late BindToClose write re-released a
    record the next session had trusted and walked. So the load that takes the lock writes a fresh
    `session` token (`HttpService:GenerateGUID`) in the same `UpdateAsync`, and `saveProfile`'s
    transform returns `nil` (cancels) unless the record still carries `p.session`. A session that
    finds its record taken sets `canSave = false` and stops writing.

    Four things reopen it: planning an unseen floor from `savedSecrets` without that trust, any write
    other than a release setting `lockUntil = 0`, revealing anything after a releasing save, and any
    write to the profile key that does not check the owner token (a new `SetAsync`, a second
    `UpdateAsync` path, a load that takes the lock without writing a new token).

    `robloxemu/check_forktower_plansecret.luau` is the measurement: 800 forks read honestly against
    three public predictors (the replicated module + leaderstats, the frozen 2026-09-17 module, and
    another reader on the same run seed), each required to be a coin at |m − n/2| <= 4.9·√n/2; plus a
    sweep of every replicated property, attribute and RemoteEvent payload for the saved secrets and
    their stream seeds. Any new client-visible thing a floor carries must be derived from public
    inputs or from what the player has already revealed, or that check's part B goes red. Its part F
    replays the read-only oracle (F1), a crash (F2, F2b), a load that failed after reading (F4) and
    the shutdown window (F5) at the same threshold, proves seen floors survive an untrusted load
    (F3), replays a releasing write that lands late (F6; F6c is its control, a lone late release
    that must still land) and an older live session whose record a newer load took (F6d), and sweeps
    the wire again. Faking "another server holds the lock" means writing `jobId` and
    `lockUntil` into the RECORD: Luau caches `game.JobId` at script load, so changing it mid-run
    tests nothing.

14. **The environment knows nothing about a fork** (EYECANDY.md §6). `Ambience.client.luau`, `TowerArt.luau`
    and `Climb.luau` read, in the player's own lane, only the pads' positions and sizes and a chosen
    section's `Exit` platform, plus the `Owner` attribute that says which lane is theirs. They never read a
    door, a sign, the inscription, `Marked`/`TellKind`/`RuleInverted`, `Read`, a penalty, a theme, the Fork
    module or a secret, write no attribute and fire no remote. At a fork the progress is exactly
    `floor - 1`, so the world in front of two unread doors depends on the floor number and nothing else.
    `robloxemu/check_forktower_env_secret.luau` holds all of it (static audit of the shipped sources, door
    clearance and mirrored walls at every unread fork, a read changes nothing drawn, no saved secret in
    anything drawn); adding a read of anything a fork carries turns it red on purpose.

15. **The fork pad is a sanctuary, and so is a cleared floor** (`Climb.gate`). The hazard clock runs only
    while the player climbs a section, off every pad; nothing launches or hits on a pad and a hazard in
    flight is dismissed on arrival. It is also dismissed the moment the floor is cleared, wherever the
    player stands, and nothing hits a player who is not climbing: the next fork's LES prompt reaches 16
    studs, over the front of the exit platform and off the pad (review 2026-09-24: a reader there was
    knocked 0.97 s into the hold). Ambience scans the lane the frame anything arrives in it, so the
    dismissal lands in the first frame the next fork exists, not at the 4 Hz tick. The read costs `Config.Fork.ReadSeconds` on the server's clock and nothing may add to it: a
    hazard that could knock a reader off the pad would put a price on reading that
    `tests/readcost.measure.luau` never measured. `tests/Pacing.spec.luau` measures the rest: the
    break-even moves only up (a trap's longer climb meets more hazards), 0 for anyone who reacts.

16. **The exit counts only for a body that could have climbed there** (queued job I, 2026-09-30;
    `lane.tryExit` in Main.server). A client owns its character's physics: a script could choose a door and
    teleport onto the exit, or fire its Touched from anywhere, and a trap cost it nothing. A floor now clears
    only when the server's own view puts the root part on the exit platform (Config.Exit) AND
    `Section.minClimbSeconds` has passed on the server's clock since the server put the player at the
    bottom of the section (the door choice; a mid-climb rejoin restarts it). The bound is the straight line
    on the ground from the entry to the exit's reach at the player's own WalkSpeed x SpeedSlack 1.25: nobody
    moves sideways faster than their WalkSpeed. `tests/Pacing.spec.luau` measures that no honest climber is
    ever refused (the quickest, a climber who never lines up a hop, took 1.32x the bound); the fall-rescue
    loop polls the exit every 0.4 s so a limb-first landing is never stranded. Mean bound at base speed
    (400 seeds): 1.3 s on floor 1 to 3.3 s on floor 10, 22.6 s for ten floors; a trap adds 1.6 s. Measured
    against the climb model (30 runs, read strategy): a script that moves at WalkSpeed x 1.25 in straight
    lines climbs 2.35x faster than a perfect bunny-hopper and 12.5x faster than a normal reader. Waiting
    at the bottom and teleporting once the time is up buys nothing over that walk: both end at the same
    second. A "seen on the path" rule cannot raise the bound either (a script can teleport along the
    platforms too); only a per-hop airtime bound would, and that rests on physics only Studio can measure
    (step-up, limb touches), so it is not built. `robloxemu/check_forktower_exit.luau` is the measurement.

17. **A band's second floor is its own phase, and it is 0 or 1 at every fork** (`Config.Env.Layers`,
    EnvConfig.spec). Anything else would make the world in front of two unread doors depend on more than the
    floor number (invariant 14). `Pacing.spec` asserts the world never stands still for more than 90 s.

18. **The budgets are capped in TowerArt, and the telegraph is never what the cap cuts** (`TowerArt:usage`,
    `reserve`, `room`). Scenery and critters are drawn only if they fit the budget minus the reserve (the
    biggest hazard model, its lane and ring, a bolt, the weather host, the lantern); a shown wall holds its
    whole slot capacity, also when it is asked for again. A piece the budget held back enters invisible
    and fades in over 0.5 s (`ENTER_SECONDS`), whatever weight it reached meanwhile: without that, the cap
    itself made pop-ins whenever it bit (found 2026-10-01 with six bats raised to 60). `check_forktower_env`'s
    four probes hold it (everything at once, the moving wall, the wall asked for again, the held-back piece).

19. **The crown counts summits, never rebirths.** Rebirth works from any floor every 3 s; a goal a button
    can buy is not a goal. `profile.summits` is counted once per run in `reachExit` at the top, saved, and
    shown as the public leaderstat `Topper`, which is the one thing the ambience reads to pick the crown
    (`check_forktower_env_secret` allows that name and no other new one).

20. **No Robux in v1** (docs/complete-game-standard.md §3; owner decision 2026-09-30). `Config.Passes` and
    `profile.passes` are deleted, not left dead: ExtraSkip would have sold the one thing a trap costs.
    `Codes.spec` holds the config, `check_forktower_crown` holds the saved record. Skips come from the free,
    public codes only.

21. **The board is written only upward, and only by the record's owner** (pass 2; `writeBoard`). It runs after the
    profile's own write landed (so a session whose record was taken writes nothing), only when `bestScore` has
    passed `boardScore` (the last score written, saved with the profile), and through `UpdateAsync` with
    `Board.keepHigher`. Never `SetAsync` the board: a session holding an older, lower best would overwrite a higher
    one, and a same score reached later would take the first reach's place. The metric is the server's
    `Build.reveal` score; a client never sends a number. `check_forktower_board` holds it.

22. **Every player's `RespawnLocation` is an enabled SpawnLocation** (pass 2; docs/complete-game-standard.md §1):
    their own tower's `LaneSpawn`, set in `buildLane`, or the `WaitingSpawn`, set FIRST in `onPlayerAdded` before the
    profile load can yield. Every `LaneSpawn` is enabled now, so a player with no `RespawnLocation` could be put in
    somebody else's tower by the engine; that is why the join sets it before anything else. The checkpoint still
    climbs with the player, so `onCharacter` still waits for the engine and then moves them (invariant 12).
    `check_forktower` asserts every enabled spawn is the WaitingSpawn or a LaneSpawn on its own lobby.

23. **The board knows nothing about a fork.** `Board.client` reads only the lane's `Owner` attribute and its
    `TopBoard` part; the Ambience scan ignores the board by name (invariant 14's audit covers Ambience, TowerArt and
    Climb). The board's payloads carry user ids, names and decoded scores, which are public (`Best` is a leaderstat);
    `check_forktower_plansecret`'s wire sweep runs with them on the wire.

11. **The checkpoint sits at the MIDDLE of its clear band.** Hazard clearance and platform-edge
    margin always sum to the width of the feasible interval, so one is bought with the other and
    only the midpoint maximises the smaller. Both `Section.build` and `Section.check` know this.
    Neither end of the band is safe: the far end is 0.00 studs from the drop, the near end is
    inside the hazard.

---

## What went wrong building it (all of it caught by a test, none of it by reading)

- **The second fix trusted "released" without asking WHO released it.** A released record was taken
  to be the last session's final state, and REVIEW-4 §9.8 even wrote that the rule did not depend on
  the order queued writes land in. But a shutdown writes two releases per player and `saveProfile`
  never checked it still owned the record, so a late BindToClose write re-released a record the next
  session had already trusted and revealed from (120 of 120 in F6). This one WAS found by reading,
  the rule against the write paths, and then proved with a test that went red before the fix. The
  lesson: a lock flag says what state a record is in, not whose state it is. Give writes an owner.

- **The first plan-secret fix left the saved secrets one read-only session away.** Every public
  predictor was at chance and no secret was on the wire, and an attacker still won 240 of 240: join
  while another server holds the lock, walk every door in the READ-ONLY session (which planned the
  saved secrets and saved nothing), rejoin. REVIEW-4 had filed read-only sessions under "consistency,
  not safety". The lesson: a secret is only as safe as the least persistent session allowed to plan
  from it. Gates never ran a locked load; part F of check_forktower_plansecret does now.

- **The generator itself was the leak, after the attributes had been closed.** REVIEW-3 removed
  `TellKind`, `RuleInverted` and `Marked` from unread forks and enumerated the wire to prove it, and
  every trap was still one `Fork.plan(Config, Rebirths + 1, Rng)` away on the client, because the
  module that computes the plan replicates and so does every input it took. 30 of 30 in a probe on
  2026-09-17, 800 of 800 in the check written for it. Every fairness assertion in Fork.spec passed
  the leaking generator — balance, readability, sign exchangeability and prize neutrality are all
  properties a public generator can have (witness F). The lesson is in invariant 13: gating what a
  server SENDS is not enough while the client can COMPUTE it.

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
1. ~~**Point `hudcheck` at it.**~~ Done (2026-09-24): `check_forktower_hud`, `_hud_open` and `_hud_play`
   measure the HUD at sixteen to nineteen viewports, down to 480x270 since 2026-09-30.
2. **Make choices narrow the tree.** The brief promises it and `Fork.plan` currently draws each
   floor's two traits independently of the picks above it. The plan is already built per run, so
   the history is available; the fairness spec would need a matching "narrowing still leaves every
   trait reachable" assertion.
3. **Give the trap more than one shape.** Longer-and-busier is the only punishment in the game.
4. **Make hazards move**, or drop the `kind` field that promises four of them and renders one.
5. ~~**Wire or delete `Config.Passes` and `profile.passes`.**~~ **DECIDED 2026-09-30 (owner: take
   recommended): deleted** (invariant 20; the owner's standard allows no Robux cost in v1).
6. Adversarial review, then the publish path: experience → git-ignored `publish_*.bat` →
   content-maturity questionnaire (the Preview page is ground truth) → Public.
7. **For the tools owner** (pass 2): `tools/film_game.py` needs a Fork Tower scenario table for `MARKETING.md`'s
   eight clips, `tools/studio_open.ps1` a `fork-tower` key, `tools/store_text.py` a Fork Tower entry once there is an
   experience.
8. **For the owner**: the ice crown moved from 10 to 8 summits (the brag, 36.3 min); one number puts it back.

---

## Commands

```
# tests (every tests/*.spec.luau: Board.spec, Build.spec, Climb.spec, Codes.spec, EnvBands.spec, EnvConfig.spec,
# Fork.spec, Hazards.spec, Pacing.spec, Rest.spec, Rng.spec, Section.spec, responsive.spec)
cd D:/Claude/Roblox/fork-tower && luau tests/<Name>.spec.luau

# where Config.Fork.ReadSeconds comes from — re-run after any tuning change
cd D:/Claude/Roblox/fork-tower && luau tests/readcost.measure.luau

# headless boot (re-wrap after ANY src change) — BOTH runs, they cover different things
cd D:/Claude/Roblox/robloxemu
py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
luau check_forktower.luau
luau check_forktower_plansecret.luau     # the plan secret: 800 honest reads vs 3 public predictors,
                                         # plus part F: read-only / crashed / failed / shutdown oracles,
                                         # a late releasing write, and an older session taken over
cd D:/Claude/Roblox/fork-tower && luau tests/world.check.luau
cd D:/Claude/Roblox/robloxemu
luau check_forktower_env.luau            # the environment glue through the real client (~10 s)
luau check_forktower_env_secret.luau     # the environment reveals nothing
luau check_forktower_env_join.luau       # the first title card at a join, slow profile loads included
luau check_forktower_hud.luau            # hudcheck: HUD + ambience row, drawers closed, ten viewports
luau check_forktower_hud_open.luau       # the drawers and the Build Reveal card OPEN, ten viewports
luau check_forktower_hud_play.luau       # the HUD and the band card keep off the player's own character
luau check_forktower_exit.luau           # the exit cannot be teleported to (queued job I)
luau check_forktower_sitdrop.luau        # the ☕ Hvil sit survives its own drop (the Studio trace)
luau check_forktower_crown.luau          # summits, the Topper leaderstat and the summit's crown
luau check_forktower_board.luau          # the toplist board (public + friends), RespawnLocation, and the
                                         # whole player path: spawn, earn, spend, ten floors, summit, rejoin

# the documents (README store text, MARKETING.md clips, EYECANDY lists, this file naming every gate)
cd D:/Claude/Roblox/fork-tower && py -3 tests/docs_check.py

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
