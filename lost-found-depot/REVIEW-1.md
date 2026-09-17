# REVIEW-1 — Lost & Found Depot, pass 3 (fixes for the second round of review)

Two adversarial reviewers looked at build pass 2 on 2026-09-17:

- an **exploit reviewer**, working in a scratch copy called `rev3`;
- a **player-path reviewer**, working in `rev-reach`.

This file covers the fix pass that followed. Nothing is committed, pushed or published. The game has
**never been opened in Roblox Studio**.

Every number below comes from a run made in this pass.

- **"Before"** is the pass-2 source. Before any change, every file under `src/` and `tests/`, and all
  six `check_lostfounddepot*.luau`, had the same sha256 as both reviewers' copies.
- **"After"** is the final source.

The earlier REVIEW-1 findings (R1-*, R2-*, 6, 8, 13) are in `CLAUDE.md`. To keep the ids distinct,
this pass calls the exploit reviewer's findings **E1-E3** and the player-path reviewer's **U1-U6**.

**How each finding was handled:**

1. Reproduce it on the unmodified source, with the reviewer's own script or my own.
2. Write the failing assertion and watch it fail.
3. Fix the game.
4. Re-run the reviewer's script.
5. Mutation-test the new assertion.

Nothing was rejected: all nine findings reproduced.

## Summary

| id | severity | verdict | before | after | gate |
|---|---|---|---|---|---|
| E1 | high | **closed** | **Pick + put-back, 10,000 pairs in one frame:** 20,000 State payloads (17.89 MB), 80,000 `Instance.new`. **10,000 clicks with full hands:** 10,000 toasts. **10,000 Redeem "NOPE":** 10,000 toasts. | **Pairs:** 10 payloads, 40 Instances, 2 toasts. **Full hands:** 1 toast. **"NOPE":** 2 toasts. | `_save` E1 |
| E2 | medium | **closed** | Server hop: the store ended with cart 2 + shoes 2 (2,100 worth) for 1,050 cash. | A read-only purchase is refused. The store ends with cash 0, cart 2, shoes 0 (1,050 worth), and the merge re-prices purchases. | `_save` E2, `Economy.spec` E2 |
| E3 | low | **closed, with the limit stated in E3** | The seed a client can recover from the tray predicted 66 of 66 cart items, and the recovered salt predicted 2 of 2 next seeds. | 0 of 66 cart items; 0 of 2 next seeds. | `_rng`, `Seed.spec`, `Shift.spec` |
| U1 | high | **closed** | The misfiled tutorial Phone vanished in 6 of 6 runs, and the TAP HERE slot was nil in 6 of 6. 6,873 of 56,000 non-tutorial items on career shift 1 were a Teddy Bear or a Phone. | 0 of 6; 0 of 6; 0 of 56,000. | `_firstmin` A1, A2b, B; `Shift.spec` U1 |
| U2 | medium | **closed, with the trade-off stated in U2** | A bot that takes the item it picked first to its bin: 17 / 10 / 8 wrong bins at carry 2 / 3 / 5. Nothing on screen named the item. | That bot: 0 / 0 / 0. At all 337 deposits read, the Drop prompt names the item E drops. | `_firstmin` A3, B |
| U3 | low | **closed** | 8 of 24 misfiled or put-back items went to the cart. | 0 of 21. Five put-backs in one frame lose none. | `_firstmin` A2, A2b |
| U4 | low | **closed** | On a phone the tutorial said "...and press E." and the marker said "PRESS E HERE". | A phone gets "...and tap Drop." and "DROP HERE"; a keyboard keeps "press E". | `_firstmin` B, the walk, `_hudflow` |
| U5 | low | **closed** | Over 588 cameras, tray tags covered the memo board 41.7% (mean) and 53.6% (worst). The board also hid the name sign in 140 camera checks. | 0.0% / 0.0%, and 0 checks. | `_view` |
| U6 | low | **closed headless only; the effects are on the Studio list** | There was no deposit stamp, no MANUAL pulse and no bin light pulse. | All three exist and are asserted against the HUD model. | `_firstmin` B |

---

## E1 (high): picking and putting back had no rate limit

### Reproduced
I ran the reviewer's `rev_spam.luau` on the pass-2 bundle.

- One honest pick + put-back costs 2 State payloads and 7 `Instance.new` calls.
- 10,000 pairs in one frame cost 20,000 State payloads (17.89 MB as JSON) and 70,000 `Instance.new`.

My gate's own counter wraps `Instance.new` before boot and also counts the item Model. It measured
80,000 for the same burst. Every pair was accepted, and the state stayed consistent (8 items on the
tray, 0 carried).

My own gate also measured the two smaller cousins:
- 10,000 clicks with full hands sent 10,000 toasts;
- 10,000 Redeem "NOPE" events sent 10,000 toasts.

### Fix
- **Action bucket.** Every accepted state change (pick, put back, deposit, buy) spends one token
  from a per-player bucket: `Config.Remotes.ActionBurst = 10`, refilling
  `ActionsPerSecond = 5`.
  - The spend happens after every other refusal and immediately before the state change, so a
    refused event costs nothing, and no handler yields between its check and its change.
  - An empty bucket refuses with "Slow down - one thing at a time."
- **Toast gate.** A "refused" or "info" toast whose text was already sent within
  `NoticeRepeatSeconds = 0.05` is dropped.
  - Beyond that, at most `NoticeBurst = 6` go out at once, refilling `NoticesPerSecond = 3`.
  - Results ("ok", "misfile", "perfect", "tutorial") always go; the action bucket already bounds them.

### Proof (`check_lostfounddepot_save.luau`, E1)
- **One honest pair:** 2 State payloads, 8 Instances.
- **10,000 pairs in one frame:** 10 payloads, 40 Instances, 2 toasts. Asserted: at most 20, 100 and 3.
- **A pair every frame for 10 s:** 59 payloads, 197 Instances. Asserted: at most 80 and 400.
- **10,000 clicks with full hands:** 1 toast. **10,000 Redeem "NOPE":** 2 toasts.
- **CONTROLS:**
  - a pick and a put-back every 0.25 s for 10 s: 40 of 40 accepted, and nobody is told to slow down;
  - the same refusal repeated 1 s later is sent again.

### The reviewer's scripts, re-run on the fixed bundle
- `rev_spam.luau`: 10 State payloads (0.01 MB), 2 toasts, 45 `Instance.new`.
- `rev_spam2.luau`:

| scenario | CPU | State payloads | toasts |
|---|---|---|---|
| 10,000 pick + put-back pairs (reviewer: 0.815 s) | 0.070 s | 10 | 1 |
| 10,000 Redeem "NOPE" | 0.005 s | – | 2 |
| 10,000 full-hands clicks | 0.036 s | – | 1 |

### Side effect, measured
The reviewer's teleport bot (`rev_tele.luau`) never advances the clock inside its drop loop. Once
the bucket is empty its refused drops spin, so the script hangs; that is the script, not the server.

With one frame allowed per attempt (`rev_tele_frames.luau`, in my scratch), the bot's Perfect Shift
takes **10.02 virtual s instead of 1.18 s**, and it still gets 655 cash. This finding did not target
bots, and DESIGN §10.3 accepts them.

### Residual
- The limits are headless numbers.
- A live server decides how fast the engine really delivers ClickDetector and ProximityPrompt
  triggers, and whether 5 actions a second ever pinches a fast real player. Both are on the Studio list.

---

## E2 (medium): a server hop spent the same cash twice

### Reproduced
I ran the reviewer's `rev_hop.luau` on the pass-2 bundle. The race is A's release taking 1.0 s while
B's load takes 0.2 s:

| step | cash | cart | shoes | note |
|---|---|---|---|---|
| A buys the cart twice | 0 | 2 | – | the store still says 1050 |
| B loads (read-only) | 1050 | – | – | stale |
| B buys the shoes twice | 0 | – | 2 | |
| store after one autosave | 0 | 2 | 2 | 2,100 of upgrades for 1,050 cash |

CONTROL order (A's release lands first): B's purchase is refused, and the store holds 1,050 worth.

### Root cause
`Economy.merge` added B's cash delta (-1050) to 0, and sanitize floored the result at 0, while the
shoe levels were added and kept.

### Fix, two layers
1. **Server.** A session that is not saving (`store ~= nil and not canSave`) cannot buy. It is told
   "Upgrades wait until your progress is saving. Try again in a moment." The next autosave takes the
   lock as soon as the other session lets go, and buying works again.
2. **`Economy.merge`, which is pure.** It covers the case where a session loses its lock while it
   believes it holds it.
   - A purchase is **re-priced** at the level it lands on in the store.
   - A level past MaxLevel is not bought (its price comes back).
   - A purchase that the stored cash plus the session's earnings cannot cover is **undone**, most
     expensive first.
   - This also closes a known gap from pass 2: a purchase clamped at level 3 was never refunded.
3. **Walk speed on merge.** When a merge is folded into the live profile, the server now re-applies
   walk speed and pushes State. Before, the Humanoid kept the old speed.

### Proof
- **`Economy.spec` E2** (6 failed before the merge change):

| case | result |
|---|---|
| the hop | shoes 0, cart 2, cash 0; worth 1,050 or less |
| 300 in store | one shoes level kept, cash 50 |
| 400 earned after buying | one level kept, cash 150 |
| cart re-priced at level 3 | cash 5000 - 2000 = 3000 |
| CONTROL, store unchanged | both purchases stand |

- **`_save` E2, the hop:**
  - B is read-only and shows 1,050.
  - B's two Shoes presses leave shoes 0 and cash 1,050, and B is told why.
  - After B takes the lock, the store holds 1,050 or less in total.
  - B's live carry is 4, and walk speed matches the stored shoes.
  - CONTROL: once B is saving, a purchase is judged on the real balance ("costs 250. You have 0.").
- **`_save` E2, merge changes shoes live:**
  - B is read-only behind a live lock, walking at 16.
  - The other server saves shoes 2 and dies.
  - After one autosave B's shoes are 2 and the Humanoid walks at 20. Added after the first sweep;
    see mutation E2e.
- **`rev_hop.luau` re-run, RACE:** B's two presses are refused. The store holds cash 0, cart 2,
  shoes 0 (1,050 worth), and B walks at 16 with canSave true.

### Residual (not new)
A merge write whose answer is lost is still applied twice once the stale lock expires.

---

## E3 (low): the tray gave away the seed, the salt and everything after

### Reproduced
The reviewer's `rev_rng.luau` on the pass-2 bundle:
- scanned 715,827,886 candidate states in 17.9 s and found exactly 1 seed;
- inverted fmix to recover the salt;
- predicted shift 1's cart (22 of 22), shift 2's bins (6/6), tray (8/8) and cart (22/22), and
  shift 3's bins (6/6), tray (8/8) and memo.

My own gate reproduces the same attack headlessly: it reads the server console's `seed N`, which is
exactly what the brute force recovers, runs the same public `Shift.generate`, and inverts the last
fmix. On the pass-2 bundle it measured cart 66 of 66 and next-shift seeds 2 of 2.

### Fix
1. **Fresh salt every shift.** The salt is drawn from a new server `Random.new()` for every shift, not
   once per session. A salt recovered from one tray says nothing about the next shift.
2. **Separate cart keys.** The cart has its own keys: two more 32-bit values from a separate
   `Random.new()`.
   - `Seed.cartSeeds` gives item n (9-30) the seed `fmix(fmix(k1 xor n) xor k2)`.
   - `Shift.generate` draws each cart item from its own stream.
   - The tray, bins and memo still come from the one seed. The server console prints the seed and
     both keys, so a bug report still replays.

### Proof
- **`Seed.spec`:** 8 new assertions. `cartSeeds` gives one distinct 32-bit seed per cart item, and
  changing k1 or k2 changes all 22.
- **`Shift.spec`:**
  - the keys never change the tray, bins or memo;
  - one different key gives a different cart;
  - the same seed and keys replay the same shift;
  - over 2,000 shifts, 7 of 44,000 cart items equal the seed-only cart, which is chance;
  - worst archetype deviation 0.33 pp; stage-2 cart items torn 25.52%.
- **`check_lostfounddepot_rng.luau`** (new), over three shifts:
  - the recovered seed still regenerates every tray item (24 of 24) and every bin sign (18 of 18).
    These are CONTROLS: the premise still holds, and it reveals only what is already visible;
  - it predicts **0 of 66** cart items;
  - the recovered salt predicts **0 of 2** next-shift seeds.
- **`rev_rng.luau` re-run on the fixed bundle:**
  - the brute force still finds the seed in 17.6 s;
  - 0 of 22 cart items predicted on shift 1 and on shift 2.
  - It still reports shift 2's bins 6/6 and tray 8/8. That is a harness artifact: its `Random`
    wrapper hands **the same seed to every unseeded `Random.new()`**, so the per-shift salt comes
    out identical every shift.
- **The same script with each `Random.new()` seeded separately** (`rev_rng_indep.luau` in my
  scratch), which is what Roblox documents: shift 2 bins 1/6 and tray 0/8; shift 3 bins 0/6 and
  tray 0/8; cart 0/22 twice.

### The limit, stated
- The current shift's tray, bins and memo still come from a recoverable 32-bit seed. They are
  already on screen when the shift arms.
- A client that watches cart items roll in sees outputs of `fmix`-keyed streams under a 64-bit key.
  I did not attempt a cryptanalysis of that construction, and I claim no more than "no attack run in
  this pass predicts it".
- The fix assumes each Roblox `Random.new()` is seeded independently from the engine's entropy
  source. That needs a live check (Studio list).

---

## U1 (high): a misfiled or put-back tutorial Phone vanished into the cart

### Reproduced
- **Reviewer's scripts** on the pass-2 bundle:
  - `rv_tutorial_run.luau` — misfile=1, the Phone on neither tray nor hotbar, step=pick slot=nil,
    TAP HERE off, and a random `T · 4 · WHITE` Phone on the tray;
  - `rv_marker_run.luau` — the Phone rolled back 0.35 s after one pick, with the marker still off
    10 s later;
  - `rv_tutputback_run.luau` — R pressed on the pad sent the Teddy to the cart, marker off.
- **My `_firstmin` A1** (six new players each misfile the Phone by its look): vanished 6 of 6, no
  TAP HERE slot 6 of 6.
- **`Shift.spec`:** before the fix, 6,873 of 56,000 non-tutorial items on career shift 1 were a
  Teddy Bear or a Phone.

### Fix
1. **An item that comes back goes on the tray.** "Comes back" means a misfile, a put-back, or a
   reset or death.
   - It takes the first free slot.
   - With the tray full, it takes the slot of the item that most recently rolled in from the cart;
     that item goes to the front of the cart and rolls in again at the next refill.
   - Tutorial items are never bumped.
   - An item that itself just came back is bumped only when nothing else is left.
2. **No lookalikes on career shift 1.** Every archetype draw (one draw, over the 14 other
   archetypes) excludes the tutorial's own archetypes, so nothing else on that shift is a Teddy Bear
   or a Phone.
3. **The misfile toast names the item** (see U2).

### Proof
- **`_firstmin` A1:** vanished 0 of 6; no-slot 0 of 6; other Phones on the tray 0; the misfile toast
  names the item 6 of 6.
- **`_firstmin` A2b:**
  - five put-backs in one frame all stay on the tray;
  - six rounds of crowding put-backs on a new player's full tray leave both tutorial items on it.
- **`_firstmin` B** (real HUD, 800x360 touch):
  - the Teddy put back from the pad is on the tray, with TAP HERE over its slot, still up 10 s later;
  - the Phone misfiled at ELECTRONICS is on the tray labelled `MISFILED - goes to KEYS & WALLETS`,
    with TAP HERE over it after the Teddy is sorted.
- **`Shift.spec` U1:** 0 of 56,000. The other 14 archetypes' worst deviation stays within 1%.
  CONTROL: Teddy Bears and Phones still appear after shift 1.
- **Reviewer scripts re-run:**
  - `rv_tutputback_run.luau` — Teddy on tray slot 6, marker true, still true 10 s later;
  - `rv_decoy.luau` — a decoy Phone 0.0%, a decoy Teddy 0.0%, either 0.0%.
  - `rv_tutorial_run.luau` and `rv_marker_run.luau` follow the pass-2 rule that the last pick is
    selected, so under U2's rule they drop the Teddy first. Both misfiled items end on the tray, and
    the marker is on.

---

## U2 (medium): nothing said which item E drops

### Reproduced
- `rv_select_run.luau` on the pass-2 bundle (the reviewer's first-picked bot): 17 of 47, 10 of 40 and
  6 of 36 deposits were wrong bins at carry 2 / 3 / 5.
- My `_firstmin` A3 (stage 3, three strategies that never tap the hotbar) on the pass-2 bundle:

| carry | first-picked-first | last-picked-first |
|---|---|---|
| 2 | 17 wrong | 0 wrong |
| 3 | 10 wrong | 13 wrong |
| 5 | 8 wrong | 26 wrong |

Neither natural pattern was safe. A pick selected the new item, but a deposit selected the first.

### Fix
1. **A pick no longer moves the selection.** E drops the item in the first hotbar slot unless the
   player taps another; a deposit or a put-back selects the first again. This is a deliberate
   departure from DESIGN.md §5.1, which says a pick selects the new item.
2. **Every Drop prompt names the item and its tag**, e.g. "Drop Phone" over "K · 1 · BLUE".
   - The Put back prompt does the same.
   - A Select updates the prompt text on the same 0.1 s throttle as its State push, so Select spam
     cannot flood replicated property changes.
3. **The misfile toast names the item**, e.g. "-8 s. Phone: K goes to KEYS & WALLETS."

### Proof (`_firstmin` A3, final run)

| carry | first-picked-first | prompt reader |
|---|---|---|
| 2 | 0 wrong | 0 wrong |
| 3 | 0 wrong | 0 wrong |
| 5 | 0 wrong | 0 wrong |

- The prompt reader intends the last-picked item and taps the hotbar when the prompt names another.
- At all **337** deposits read, the Drop prompt named the item E drops: 0 mismatches.
- `_firstmin` B:
  - after tapping the Teddy then the Phone, E still drops the Teddy;
  - after a hotbar tap, the prompt says "Drop Phone";
  - the misfile toast names the Phone.
- `rv_select_run.luau` re-run: 0 misfiles at carry 2, 3 and 5.

### The trade-off, measured
A last-picked-first player who reads neither the prompt nor the hotbar now misfiles **20 / 33 / 37**
at carry 2 / 3 / 5 (before: 0 / 13 / 26).

The rule change moves the failure from one play style to the other, and the prompt text is what
makes either style safe. I chose a pick that keeps the selection for three reasons:
- the first slot is a stable place to look;
- the tutorial hint no longer jumps away from what the player was just told;
- all three agents that wrote a bot for this game (builder, both reviewers) took the first item first.

Which style real players use is a playtest question (Studio list).

---

## U3 (low): the promise "back to the tray" was false

### Reproduced
- `rv_putback_run.luau` on the pass-2 bundle: the put-back Laptop was not on the tray, and there was
  no toast.
- `_firstmin` A2 on the pass-2 bundle (a stage-3 veteran misfiling every third deposit and putting
  back every fourth pick): 8 of 24 returns went to the cart.

### Fix
The same placement rule as U1.

### Proof
- `_firstmin` A2: 0 of 21 returns went to the cart, and all 30 items are sorted in the end.
- A2b: five put-backs in one frame, 0 lost.
- `rv_putback_run.luau` re-run: the put-back item is on tray slot 3.

### Residual
With a full tray, the returned item bumps the newest roll-in, which disappears until the next refill.
Nothing is lost (A2 ends 30/30 sorted), but that item does leave the tray for a moment.

---

## U4 (low): a phone was told to press E

### Reproduced
- The pass-2 walk asserted "T means TOYS. Walk to the TOYS bin and press E." on its 800x360 touch
  viewport.
- The pass-2 `Hud.client.luau` hard-coded the bin marker's text as "PRESS E HERE" (line 549) and built
  both sort hints with "press E", with no touch check. I read this from the source; I did not re-run
  the reviewer's `rv_hudpath_run.luau`.

### Fix
- The HUD words the deposit from `layout.controlPad`: "tap Drop" and "DROP HERE" on touch, "press E"
  and "PRESS E HERE" otherwise.
- The layout pass re-words the hint whenever touch capability changes.

### Proof
- `_firstmin` B:
  - on touch, the hint says tap Drop and the marker says DROP HERE;
  - after `setTouch(false)`: "press E" and "PRESS E HERE";
  - back on touch: tap Drop again.
- The walk and `_hudflow` assert the touch wording.

### Residual
Gamepad players still read "press E" (Studio list).

---

## U5 (low): tray tags hid the memo board

### Reproduced
- The reviewer's `rv_memoboard.luau` (a static model) measured 39-49% of the face covered.
- I added the same geometry to `_view` using its own camera model: the pick point and every bin
  stand, 21 cameras each, 4 bays. On the pass-2 bundle it measured **mean 41.7%, worst 53.6%** over
  588 cameras.
- Adding the bay's name sign as a read target showed a second defect nobody had reported: the memo
  board also hid the **name sign** in 140 camera checks.

### Fix
The memo board moved to the right wall at bay-local (35.8, 8, -4), facing the arc. It now mirrors the
MANUAL board on the left wall.

I measured four placements before choosing:

| placement | tags covering it (mean) | name sign hidden |
|---|---|---|
| raised above the tray | 0% | 396 of 588 |
| raised, name sign moved aside | 0% | 68 of 588 |
| right wall, z = 2 | worst 2.3% | – |
| right wall, z = -4 | 0.0% | 0 |

### Proof (`_view`)
- Tray tags in front of the memo board: mean 0.0%, worst 0.0% of its face, over 588 cameras
  (asserted: at most 2%).
- 7,812 sightline checks, 0 hidden by decoration, including the name sign from the pick point and
  every bin stand.
- Every read board faces its reader.

### Residual
- The board is now about 36 studs from the pick point instead of about 9, so legibility is a Studio
  question.
- The HUD memo banner still carries the rule.
- `rv_memoboard.luau` hard-codes the old coordinates and was not re-run; `_view` replaces it.

---

## U6 (low): the stamp and the pulses were missing

### Reproduced
A case-insensitive grep for `stamp` and `pulse` in the pass-2 `Hud.client.luau`, `Main.server.luau`,
`Fx.luau` and `FxClient.luau` found only "timestamp" in a comment.

### Fix (client-side; nothing replicates)
- **Stamp.** A correct deposit shows a green "FILED" stamp ("RE-FILED" for a re-sort) for 0.9 s.
  - I first wrote "SORTED", and the main check's leak sweep caught it: SORTED is the launch code's
    name, and the client source replicates.
- **Bin light.** The tutorial's target bin light pulses (a looping Brightness tween to 3x) while the
  hint points at it, and returns to its base brightness afterwards.
- **MANUAL button.** It pulses for 4 s when the tutorial's closing toast arrives. That toast now has
  its own kind, "tutorial".

### Proof (`_firstmin` B)
- The TOYS light departs from base brightness while pointed at, and no other bin's light does.
- The TOYS light is back at base once the Teddy is sorted.
- The stamp is visible with text right after the deposit and hidden 2 s later.
- The MANUAL Pulse stroke is enabled after the closing toast and disabled 6 s later.

### Documentation part of the finding
DESIGN.md:196's slot hitbox is still stale; the correction is item 4 of CLAUDE.md's corrections list.
DESIGN.md itself was not edited, which keeps the pass-1 convention.

### Residual
The emulator's tween jumps to its goal instead of easing, and nothing renders. How the stamp and
pulses look is on the Studio list.

---

## Behaviour changes that changed EXISTING assertions (disclosed)

These are old assertions that encoded behaviour the findings above call defects. I rewrote the
expectation; no check was loosened.

| gate | what changed |
|---|---|
| `tests/walk.luau` | **Old:** asserted the touch hint "…press E" and the old tutorial order (Phone selected after two taps, KEYS & WALLETS first). **New:** asserts "…tap Drop", the Teddy staying selected, TOYS first, then KEYS & WALLETS. **Added:** "Drop Teddy Bear" on the prompt. 46 → 48 assertions. |
| `check_lostfounddepot_hudflow.luau` R2-2 | **Scenario:** "a tutorial item in hand but not selected" now picks the other item first (under U2 a pick does not select), and the hint wording is "tap Drop". **Unchanged:** R2-2's three properties (the hint follows the selection; a select step exists; following every hint never misfiles). 44 → 44. |
| `check_lostfounddepot_save.luau` R1-5 | One CONTROL: after two picks, the first stays selected. |

---

## Mutation sweep (pass 3)

**Method.**
- **In place, one mutation at a time** (`mutate.py` in my scratch):
  1. sha256 the source;
  2. apply one textual patch that must match exactly once;
  3. rebuild `robloxemu/build/lost-found-depot.luau`;
  4. **prove the patched text is in the bundle and the original text is not, and that the bundle's
     sha256 changed**;
  5. run all 17 suites;
  6. restore the original bytes and prove the sha256 is back.
- **After the sweep:**
  - the rebuilt bundle's sha256 equals the pre-sweep bundle's (`9cdcfd40…2563`);
  - all 31 game and check files match their pre-sweep sha256.
- **Harness control C0** is a patch whose old text equals its new text. It left the bundle
  unchanged (reached = false), and all 17 suites stayed green.

**After the sweep**, I made three comment-only edits (the headers of `Seed.luau`, `Shift.luau` and
`Main.server.luau`) and two test edits (the E2e scenario and a print in `_firstmin`), then re-ran every
gate. The final gate table below comes from that run.

**Result.** 29 mutations and 3 controls. The first sweep killed 28 and one survived (E2e). I added
the "merge changes shoes live" scenario, re-ran E2e, and it was **KILLED**. **Final: 29 of 29 KILLED;
C0, C1 and C2 SURVIVED, as they must.**

| id | mutation | result, first killing assertion |
|---|---|---|
| E1a | no action bucket | KILLED — `_save` "10,000 pairs … at most 20 State payloads (sent 20000)" |
| E1b | no toast gate | KILLED — `_save` "… at most 3 toasts (sent 19990)" |
| E1c | toast gate without the repeat-text rule | KILLED — `_save` "a press inside the cooldown is answered, not silent" (4 failures) |
| E1d | ActionBurst 10 → 100000 | KILLED — `_save` "at most 20 State payloads (sent 20000)" |
| E1e | ActionsPerSecond 5 → 2 (too tight) | KILLED — `_save` CONTROL "40 actions at 4 per second are all accepted" (19); `_rng` shift not finished |
| E2a | a read-only session may buy | KILLED — `_save` "a session that is not saving cannot buy … (got 2)" |
| E2b | merge adds purchases (old rule) | KILLED — `Economy.spec` "shoes bought on a balance the store no longer has are undone" (7 failures) |
| E2c | merge re-prices, never undoes | KILLED — `Economy.spec` same (6 failures) |
| E2d | merge without the MaxLevel cut | KILLED — `Economy.spec` raised in `landed` (price of level 4 is nil) at its cart-past-level-3 case: a crash, not an assertion |
| E2e | a merge adopted live does not re-apply walk speed | SURVIVED the first sweep (the hop never changes the shoes once read-only buying is refused); after the new scenario, KILLED — `_save` "a merge that changes the shoes changes how fast the character walks (got 16, want 20)" |
| E3a | server passes no cart seeds | KILLED — `_rng` "predicts the cart no better than chance (66 of 66)" |
| E3b | salt kept per session | KILLED — `_rng` "the salt … does not predict the next shift's seed (got 2)" |
| E3c | `cartSeeds` ignores k2 | KILLED — `Seed.spec` item 9's seed; `Shift.spec` "one different key gives a different cart (22 of 22)" |
| E3d | `Shift` ignores cart seeds | KILLED — `Shift.spec` (3 failures); `_rng` 66 of 66 |
| U1a | shift 1 draws lookalikes | KILLED — `Shift.spec` "(6873 of 56000)"; `_firstmin` "no other Phone on the tray (got 3)" |
| U1b | returned item to the cart front (old rule) | KILLED — `_firstmin` "a misfiled tutorial Phone is back on the tray (got 6)", then the check raised |
| U1c | a tutorial item may be bumped | KILLED — `_firstmin` "after six rounds … the Teddy and the Phone are still on the tray (got 1)" |
| U1d | a returned item ranks like any other | KILLED — `_firstmin` "five put-backs in one frame all stay on the tray (got 4 missing)" |
| U2a | a pick selects the new item again | KILLED — walk (13), `_save` CONTROL, `_hudflow` (5), `_firstmin` "first-picked … never misfiles (got 30)" |
| U2b | prompts do not name the item | KILLED — walk "the Drop prompt says what E drops"; `_firstmin` "(got 337)" |
| U2c | Select does not update the prompt text | KILLED — `_firstmin` "at the bin, the prompt says it drops the Phone (got Drop Teddy Bear)" |
| U2d | misfile toast without the item | KILLED — `_firstmin` "the misfile toast names the item (got 0, want 6)" |
| U4a | hint always "press E" | KILLED — walk (3), `_hudflow`, `_firstmin` (3) |
| U4b | a touch change does not re-word the hint | KILLED — `_firstmin` "with a keyboard it says press E" |
| U5a | memo board back behind the tray | KILLED — `_view` "never hidden by a decorative board (got 140)" and the tag-cover assertion |
| U6a | no stamp | KILLED — `_firstmin` "a correct deposit shows the stamp" |
| U6b | no MANUAL pulse | KILLED — `_firstmin` "the MANUAL button pulses" |
| U6c | no bin light pulse | KILLED — `_firstmin` "the TOYS bin's light pulses" |
| U6d | the pulse is never stopped | KILLED — `_firstmin` "the TOYS light stops pulsing once the Teddy is sorted" |
| C0 | HARNESS CONTROL: no change | SURVIVED (must); bundle unchanged, 17/17 green |
| C1 | CONTROL: stamp tilt -8 → -10 degrees | SURVIVED (must) |
| C2 | CONTROL: NoticesPerSecond 3 → 4 | SURVIVED (must) |

The 54-mutation sweep from pass 2 (in `CLAUDE.md`) was **not re-run** on this source.

---

## Final gates (the final source, bundle rebuilt first)

| gate | result |
|---|---|
| `tests/Codes.spec.luau` | 16 passed, 0 failed |
| `tests/Economy.spec.luau` | 157 passed, 0 failed (was 144) |
| `tests/Layout.spec.luau` | 32 passed, 0 failed |
| `tests/Rng.spec.luau` | 32 passed, 0 failed |
| `tests/Rules.spec.luau` | 95 passed, 0 failed |
| `tests/Seed.spec.luau` | 24 passed, 0 failed (was 16) |
| `tests/Shift.spec.luau` | 79 passed, 0 failed (was 66) |
| `tests/responsive.spec.luau` | 70 passed, 0 failed |
| `tests/walk.luau` | 48 passed, 0 failed (was 46) |
| `check_lostfounddepot` | 238 passed, 0 failed |
| `check_lostfounddepot_spawn` | 29 passed, 0 failed |
| `check_lostfounddepot_save` | 111 passed, 0 failed (was 76) |
| `check_lostfounddepot_hudflow` | 44 passed, 0 failed |
| `check_lostfounddepot_view` | 17 passed, 0 failed (was 15) |
| `check_lostfounddepot_hud` | PASS, 60 viewport × mode measurements |
| `check_lostfounddepot_rng` (new) | 24 passed, 0 failed |
| `check_lostfounddepot_firstmin` (new) | 67 passed, 0 failed |
| `luau-compile --binary` | 14 of 14 sources clean, plus every test and check |
| `luau-analyze` (Roblox-global filter) | 14 of 14 clean |

The analyzer flagged one real problem in my first E2 merge (string-indexing a typed record). It was
rewritten, not filtered.

### The walk (final)
- Joins 0.00 studs from the pad centre. Taps the Teddy, then the Phone (6.41 studs each, no step);
  the Teddy stays selected, and the hint says "T means TOYS. Walk to the TOYS bin and tap Drop."
- 34.0 studs to TOYS: +11. The hint moves to the Phone. 23.0 studs to KEYS & WALLETS: +12, and the
  closing toast shows.
- **Loop 1:** 30/30, 0 misfiles, Perfect, 70.3 s, 1,036 studs.
- **Loop 2:** 30/30 with one deliberate misfile (toast "-8 s. Keyring: K goes to KEYS & WALLETS."),
  Perfect, 63.7 s.
- **Total:** cash 1,045, backlog 59/500, 2,037 studs.

### Scope
- `robloxemu/emu/`, `wrap.py` and `docs/` are byte-identical to the start of this pass (sha256).
- `check_lostfounddepot.luau`, `_spawn` and `_hud` are unchanged.
- Nothing in `steal-a-cryptid` or `facility-nightmare` was read or written.

---

## Still open

**Needs Studio or a live server**
1. The engine's real ClickDetector and ProximityPrompt trigger rate, and whether ActionBurst 10 /
   5 per second ever pinches a fast honest player on a phone.
2. That each `Random.new()` in a live server is seeded independently (E3 relies on it).
3. Which item real players take to a bin first (U2's trade-off), and whether "Drop Teddy Bear" plus
   a tag line fits a phone's prompt button.
4. How the memo board reads at about 36 studs on the right wall.
5. The stamp, the bin-light pulse and the MANUAL pulse on screen.
6. Gamepad players:
   - the hint says "press E";
   - Cart and Shoes share one Part, and neither prompt sets `GamepadKeyCode` (the player-path
     reviewer's unverified note).
7. The exploit reviewer's unverifiable items:
   - whether a Part created and destroyed in one frame still replicates;
   - whether an exploiter can body-block another bay's owner.

**Headless gaps that remain**
8. A merge write whose answer is lost is still applied twice once the stale lock expires.
9. U3: a full-tray return briefly sends the newest roll-in back to the cart.
10. E3: the current shift's tray, bins and memo stay seed-determined (visible anyway). No
    cryptanalysis of the cart-key construction was attempted.
11. A lock lost mid-session followed by a purchase is now undone silently at merge. No toast
    explains the refund.
12. The pass-2 mutation sweep was not re-run.
13. This fix pass has had no independent adversarial review; only the author's tests and the sweep
    above have looked at it.
