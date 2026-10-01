# Lost & Found Depot

A solo sorting job for Roblox. You work a private bay in a lost-property depot: eight lost items on
a tray, each wearing a luggage tag, and six bins in an arc beyond it. Read the tag, walk the item to
the bin the tag names, press E. The tag's letter was drawn without looking at the item, so it
disagrees with what the item looks like three times in four. Trust the tag, not the item.

**Status, honestly:** v1 is built and passes every headless gate in this repo: 17 unit specs, a
walk of the player's first two shifts, and 15 checks against the built world (counts in
`CLAUDE.md` and `EYECANDY.md` §7). A first adversarial review (REVIEW-1) found real defects, and every one was fixed test
first: saves lost or locked when the DataStore is slow, a tutorial hint that caused a misfile, a
stuck camera, hidden toasts on a phone, a missing catalog, taps that picked the wrong item and boards
that hid the tray. A second round found nine more, all fixed test first (`REVIEW-1.md`): pick and
put-back spam, a server hop that spent cash twice, a shift the tray made predictable, a tutorial item
that vanished into the cart, nothing saying which item E drops, "press E" on a phone, tags covering
the memo board, and missing deposit feedback. The game has **never been opened in Roblox Studio, never been played by a person,
and is not published.** Nothing here has been rendered, so nothing about how it looks, feels or reads
on a phone is known yet. The list of what only Studio can answer is in `CLAUDE.md` (the game) and
`EYECANDY.md` §8 (the wings).

The full design, with the measurement behind every number, is `DESIGN.md`; `design/model.luau`
reproduces those numbers.

**The wings (2026-09-24, `EYECANDY.md`).** The depot now moves you to a new wing as your career grows:
a city depot, an airport lost-and-found, a train station, a theme park, a lost property office on a
**space station** (about 35 minutes of play for a normal player) and, as the long-term goal, the last
lost-and-found beyond the galaxy. Each wing has its own light and sky, a roof over your bay, landmarks over
the walls, life in the air and weather, all built on your own client. From the second wing on, a rare
runaway (about one per shift) rolls across your sorting floor. It can only knock you once you have stood a
full second inside its red ring, and never sooner than 2 s after its warning appeared, walking or not: step
out of the ring and it cannot touch you; if it does, you only stumble. A BREAK button lets you sit down
between shifts; pressed mid-shift it books the break for the end of the shift, because the clock is the
game. Built and tested headless, mutation-tested, and adversarially reviewed twice: the first review's six
findings (a walker warned too late, a phone drawer hiding the warning, runaways rolling through the tray, a
cosmetic error stranding a knocked player, the title card over the hotbar, an unpinned promise) are fixed
test first (`EYECANDY.md` §13), and so are the second's (the BREAK standing you back up on the sit's own
drop, a phone drawer kept open as a hazard shield, the wing panel on the HUD on the smallest phones, a gate
measured a step late, budgets that only a test enforced, an unpinned wake rule: §14, with the owner's
decisions of 2026-09-30). **Not yet seen in Studio.**

**The complete-game standard (2026-10-01, `docs/complete-game-standard.md`).** A public + friends **Top Sorters**
board stands on the wall behind your spawn pad. It ranks Perfect Shifts that the server saw walked at the speed
your shoes allow (a teleport or a speed hack is still a Perfect for you, but not on the board, and the summary card
says so), earliest first on a tie, and a prompt switches it between everyone and your Roblox friends. Every wing now
has weather and life of its own (the city got gulls and blowing leaves, the airport ticket stubs drifting from the
glass roof). On the smallest phones (568x320) the clock stays in the top row and a full cart's hotbar takes one
row, so the HUD no longer covers itself there. The store copy below covers the wings, and `MARKETING.md` has the clip
list for the night shift. Unreviewed: the board's code was found in the tree with no notes and has been
mutation-tested since, but no independent reviewer has read it.

---

## The loop

1. **Tap an item** on the tray to pick it up. You carry 2 at first. The first item is within reach of
   the spawn pad, so the first action needs no step.
2. **Read its tag** — `T · 3 · RED` plus the item's name — against the Depot Manual on the wall:
   - a RED route goes to CLAIMS,
   - condition 5 goes to REPAIR,
   - otherwise the letter picks the bin: B = BAGS & WEAR, E = ELECTRONICS, K = KEYS & WALLETS, T = TOYS.
3. **Walk it to that bin and press E** (on a phone, tap the Drop button). E drops the item in your
   first hotbar slot unless you tap another; the prompt names it. The server decides whether you were right.
   - Right, first try: `10 + combo` cash (capped at 20), the combo grows, and one item comes off the
     depot's 500-item backlog.
   - Wrong: the item goes back to the tray with the right answer written on its tag, 8 seconds come
     off the clock, and the combo resets. Sorting it correctly afterwards pays 5.
4. A **shift** is 30 items against a 5:30 clock that only starts when you pick something up. Clear
   all 30 with at most 3 wrong bins for a **Perfect Shift** (+100).
5. Between shifts the depot deals again: new items, new tags, the six bins reshuffled around the arc.
6. **Layers, one per shift:** torn tags from your second shift (a part of the tag is missing and the
   manual says what to do, with a catalog of each item's own letter for a torn letter), and from your
   third a one-line **memo** that bends one rule for that shift.
7. **The locker** by your spawn sells a bigger cart (carry 2 → 5) and faster shoes (walk 16 → 22),
   at 250 / 800 / 2000 per level.
8. **Clear the backlog** and the locked door behind the bins opens on the Back Room.

## What is in v1, and what is not

| in | not in (and why, in `DESIGN.md` §15) |
|---|---|
| Private bays, 12 per server | Co-op or a shared depot |
| 16 items, 3 rule layers, 12 memos | New items or rules per wing (the wings change the scenery, not the job) |
| Six wings, rare client-side hazards, a BREAK (`EYECANDY.md`) | Custom meshes, textures or skyboxes (all built from parts) |
| Cart and shoes upgrades | A scanner, overtime, 2x cash |
| A personal best (fastest Perfect Shift), and a Top Sorters board (Perfect Shifts; everyone or friends) | A speed leaderboard (a script that reads tags beats a careful person; DESIGN.md §10.3) |
| The Back Room ending | Audio, badges |
| One launch code, `SORTED` (+250) | Anything sold for Robux |

**Monetization: none.** No gamepasses, no developer products, no spin wheels, no loot boxes, no
idle rewards. If anything is ever sold it is cosmetic only (DESIGN.md §11).

## Fair play, briefly

The server decides every sort. The answer for an item never reaches a client until a wrong bin has
paid the 8-second penalty: no attribute (the allowlist is empty), no name, colour, tray position,
prompt text or remote payload carries it. The upcoming items come from server keys the tray never
touches, and each shift's salt is drawn fresh, so what a client can see of one shift predicts neither
the rest of its cart nor the next shift. The Back Room note and the code table live in
`src/server/Secret.luau`, which never replicates. What a client *can* do is run the public manual
against the public tag with a script. With no trading or shared state, that only speeds up its own
progress (DESIGN.md §10.3), with one exception: the Top Sorters board. It ranks a count of Perfect Shifts,
not a time, and a shift counts only when the server's travel ledger (`Ledger.luau`) found every pick and
deposit reachable at the player's own walk speed (25% tolerance, 2 studs and 1.5 s of slack). So a script
gets no more Perfect Shifts per hour than walking allows: measured headless, a walker with zero reading time
and the best cart and shoes needs 33 s for one, where the design model's regular player spends about 134 s a shift
late in the career (shifts 14-40) (`CLAUDE.md`, "The highscore board"). So a script earns them about four times as fast
as a regular, and one that plays for hours out-counts a person who plays for less; the board says what it
ranks, and nothing on it can be had without doing the walking.

## Layout

```
default.project.json        Rojo: src/server -> ServerScriptService, src/client -> StarterPlayerScripts,
                            src/shared -> ReplicatedStorage
src/shared/Config.luau      every tunable
src/shared/Rules.luau       the manual as pure functions: resolve, explain, memos, manual text, tags
src/shared/Shift.luau       one shift, generated from a seed
src/shared/Seed.luau        the hashed per-shift seed (mul32, fmix)
src/shared/Economy.luau     pay, Perfect, upgrades, save sanitizer
src/shared/Codes.luau       code normalisation and the redeem decision (the table is passed in)
src/shared/Layout.luau      bay geometry in bay-local studs
src/shared/Rng.luau  Fx.luau  FxClient.luau  Responsive.luau    copied verbatim from the siblings
src/shared/EnvBands.luau  Hazards.luau  Rest.luau              the environment template, verbatim from +1 Jump
src/shared/Wings.luau       the wings' pure rules: career progress, lanes on a walled floor, the ring, the BREAK
src/shared/WingArt.luau     every wing's scenery, critters, weather and hazard models (client only, no assets)
src/shared/StateCache.luau  the HUD hands each State payload to the wings (one listener on the remote)
src/shared/Board.luau       the Top Sorters board's pure rules: encode, keep-higher, public/friends views, caches
src/shared/Ledger.luau      the server's travel ledger: was each Perfect Shift walkable at the player's speed
src/server/Main.server.luau world, bays, spawn, shift loop, handlers, persistence
src/server/Secret.luau      the Back Room note and the code table (server only)
src/client/Hud.client.luau  the phone-first HUD
src/client/Wings.client.luau the wings, hazards and the break (client only; the server never hears of them)
tests/*.spec.luau           luau-CLI tests for every pure shared module
tests/walk.luau             the player's first two shifts, with the HUD running, in numbers
design/model.luau           the design-time model (not shipped)

../robloxemu/check_lostfounddepot.luau          the world is built and parented; a player plays it off the rendered world
../robloxemu/check_lostfounddepot_spawn.luau    where a joining character lands, under the engine's spawn order
../robloxemu/check_lostfounddepot_save.luau     saving and locking with a DataStore that takes time
../robloxemu/check_lostfounddepot_hudflow.luau  tutorial hints, toasts and the camera, on a phone
../robloxemu/check_lostfounddepot_view.luau     what a tap hits and what a player can see
../robloxemu/check_lostfounddepot_hud.luau      every HUD panel in six modes on twelve viewports (overlap rule on)
../robloxemu/check_lostfounddepot_rng.luau      what a client can predict from what it can see
../robloxemu/check_lostfounddepot_firstmin.luau a new player's first minute, and what pressing E drops
../robloxemu/check_lostfounddepot_wings.luau    the wings, hazards and the break through the real client
../robloxemu/check_lostfounddepot_wingview.luau taps and sightlines unchanged with every wing built
../robloxemu/check_lostfounddepot_hud_wings.luau the HUD and the wings' panel together on every viewport
../robloxemu/check_lostfounddepot_sitdrop.luau  the BREAK survives the sit's own drop (a Studio trace replayed)
../robloxemu/check_lostfounddepot_budget.luau   the phone budget holds in code under an over-budget config
../robloxemu/check_lostfounddepot_board.luau    the Top Sorters board through the real server: walked counts, teleported does not
../robloxemu/check_lostfounddepot_compile.luau  every source compiles; no require by string

MARKETING.md                the clip list for tools/film_game.py (vertical 1080x1920, 7-15 s)
EYECANDY.md                 the wings; §8 needs Studio, §9 the thumbnail shot list (1920x1080)
```

How to run every gate is in `CLAUDE.md`.

## Proposed store copy

940 characters, measured (Roblox allows 1000); no emoji, and no character outside ASCII but the `·` of the tag.
Rewritten on 2026-10-01 for the wings, the hazards, the BREAK and the board (the 2026-09-17 copy, 873 characters,
predated them). It still drops the three lines of the original brief that v1 cannot honour (co-op with friends,
weekly new wings, a procedurally generated depot every shift), and it names no minutes: the 35 minutes to the
space station are a model's, not telemetry.

```
Welcome to the Lost & Found Depot. You get your own sorting bay, a tray of lost things and six bins.

Every item wears a tag like T · 3 · RED. The tag was written without looking at the item, so a teddy bear can be tagged for ELECTRONICS. Trust the tag, not the item.

Read the tag against the Depot Manual, walk the item to the right bin and drop it in.

- 30 items against a 5:30 clock. A wrong bin costs 8 seconds
- Torn tags from your second shift, then a memo that bends one rule
- Earn cash for a bigger cart and faster shoes
- Your career takes the depot through six wings: city, airport, train station, theme park, a space station and beyond the galaxy
- Rare runaway trolleys, beach balls and space rocks: step out of the red ring
- Take a break between shifts
- A Top Sorters board of Perfect Shifts: everyone, or just your friends
- Clear the 500-item backlog to open the Back Room

Nothing in the game costs Robux.

Code: SORTED
```

Whether to print the launch code in the description: DECIDED 2026-09-30 (owner: take recommended): print it.
Codes are usually published this way, and the table is server-only so *unreleased* codes stay secret.
