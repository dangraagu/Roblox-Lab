# Fork Tower in Roblox Studio — the first time anybody opened it

**Verdict: it plays.** The one reason REVIEW-3 held the verdict at BLOCK — *nobody has ever opened
it in Roblox Studio or played it* — is closed. It also found one defect that would have shipped a
dead game, and no test outside the engine could have seen it.

Date: 2026-09-10. Studio `version-93202a13414c4131`, window 3373x1456, game viewport 2889x1201,
one player (`Gustav1337l2p`), Play Solo. Four play sessions across three builds of the place.

```
what changed in this pass
  src/server/Main.server.luau     onCharacter waits for the engine before placing the character
  src/server/Main.server.luau     the reading toast is only sent when it has something to say
  src/shared/Config.luau          SignEmoji.crack  🪨 U+1FAA8  ->  🗿 U+1F5FF
  robloxemu/check_forktower.luau  three new blocks, 11 new assertions, 108 -> 119

after
  Fork.spec 53/0   Section.spec 50/0   Build.spec 31/0   Codes.spec 19/0   Rng.spec 32/0
  responsive.spec 70/0   world.check 71/0   check_forktower 119/0
  luau-compile clean on all 11 sources; luau-analyze clean; find_mojibake.py clean
```

---

## What I ran

```
cd D:/Claude/Roblox/fork-tower
rojo build -o ForkTower.rbxlx                      # rojo 7.7.0

# open it — see "the tools" below; tools/studio_open.ps1 does not know this game yet
powershell -ExecutionPolicy Bypass -File <scratchpad>/ft/open_forktower.ps1
py -3 tools/studio_mcp.py studios                  # {"studios":[{"name":"ForkTower.rbxlx"}]}
```

Then, through MCP: `start_stop_play`, `execute_luau` (Server and Client), `character_navigation`,
`user_keyboard_input`, `get_console_output`, and a GDI window grab for the pictures.

Play sessions: **spawn → read the floor-1 inscription with a real held R → walk to a door → press
E → climb the section → reach floor 2 → read again → take the TRAP door on purpose → walk into a
hazard → land on the checkpoint.** Twice on the shipping build, twice on the fixed one.

---

## 1. `PromptButtonHoldBegan` — the named unmeasured assumption. It replicates.

**It reaches the server. A read costs ~1.17 s end to end, not 2.2 s. The 1.1 s in the design is the
right number.**

Two clocks, one timeline (`workspace:GetServerTimeNow()`, which is shared), listeners added
*alongside* the game's own so nothing was disturbed. Reading floor 2, verbatim:

```
  1789023936.6559  CLIENT  PromptButtonHoldBegan
  1789023936.6881  SERVER  PromptButtonHoldBegan          <-- +32.2 ms, it DOES replicate
  1789023937.7720  CLIENT  PromptTriggered                    (client hold: 1.1161 s)
  1789023937.7878  SERVER  Triggered                          (server elapsed: 1.0997 s)
  1789023937.8054  SERVER  Fork.Read = true
  1789023937.8212  CLIENT  Door_2_1 -> "💨 Vindsteg ★★"
  1789023937.8213  CLIENT  Door_2_2 -> "🌌 Nullsegl ★★★★★"
```

Four measured reads, hold-begin to doors-resolve, three builds:

| | total | server's own elapsed | HoldBegan replication lag |
|---|---|---|---|
| floor 1, shipping build | 1.1648 s | 1.0996 s | 32.2 ms |
| floor 2, shipping build | 1.1653 s | 1.0997 s | 32.2 ms |
| floor 1, after the spawn fix | 1.1829 s | — | — |
| floor 1, final build | 1.1660 s | — | — |

So REVIEW-3's "assumption holds" branch is the real one. `began` is set, `onReadInscription`
charges only the remainder, and nothing waits a second 1.1 s.

### ...but the "instant" branch is never actually taken, and that was visible

The lag cuts both ways. The server starts its clock 32 ms after the player does, so its own elapsed
for a *full honest hold* is 1.0997 s of the 1.1 s it wants. `remaining` therefore lands at about
**+0.0004 s — positive** — so `if remaining <= 0 then finish()` is dead code for an honest player,
and every read went through `task.delay` and fired

```
  1789023937.8207  CLIENT  NOTICE read: "Leser innskripsjonen … (0.0 s)"
  1789023937.8214  CLIENT  NOTICE read: "👁️ STOL PÅ RIMET — DEN MERKER FELLA"
```

— a "you are waiting 0.0 seconds" toast, two frames before the inscription replaced it. Observed on
every read.

**Fixed, and NOT the way REVIEW-3 forbade.** The charge is untouched: `task.delay(remaining, finish)`
still runs for the whole remainder on the server's own clock, so an exploiter firing the prompt with
no hold still waits the full `Config.Fork.ReadSeconds`. Only the `notice()` became conditional, on
`remaining >= 0.05` — which is not a magic number, it is what `%.1f` rounds to zero.

*Test first:* `check_forktower.luau` "STUDIO FINDING 3" fires `PromptButtonHoldBegan`, advances the
scheduler by `ReadSeconds - 0.032` (the measured lag, recorded not invented), then `Triggered`, and
requires no reading toast and a completed read. The second half fires `Triggered` alone — the
`fireproximityprompt` path — and requires that the player *is* told, is **not** read after 0.9 s,
and is read only after the full 1.1 s. Mutation: with the `if` removed the first assertion fails
`-> got 1, want 0`. Control: `Config.World.RespawnLift` 4 → 7 leaves all 119 green.

---

## 2. An unread door is unreadable. Confirmed, on screen.

`studio-shots/01-fork-unread-with-probe.jpg`, `06-spawn-fixed.jpg`, `07-crack-sign-fixed.jpg`.

Both doors, on every fork looked at: same `Color` (74,70,96), same `DoorGlow` (150,145,175), same
`TraitLabel` text **`🚪 DØR`**, same prompt `ObjectText` `🚪 DØR`, same size, same material. The
only thing that differs is the sign nubs, which is the design: they are the vocabulary the
inscription is about to name, drawn before anything consults the trap.

`02-fork-read.jpg` is the same fork one read later — `🌌 Tomromssteg ★★★★` against
`💨 Vindsteg ★★`, themed colours, and the pad reading `👁️ STOL PÅ ØYET — DEN MERKER FELLA`. The
contrast between 01 and 02 is the mechanic.

**Nothing else on screen distinguishes them.** No defect here.

One thing worth knowing that is not a leak: both doors' `Choose` prompts are on `E`, and
`ProximityPrompt.Exclusivity` defaults to `OnePerButton`, so **only one `VELG` prompt is ever
rendered** — the nearer door's. Which one that is depends on where the player stands, not on the
trap, and walking two steps swaps it. It is also the thing the read prompt's separate `R` key was
put there to avoid, and that half works: `LES` and `VELG` are both on screen at once
(`07-crack-sign-fixed.jpg`).

---

## 3. THE DEFECT: every player spawned 174 studs from their own tower

**This is what opening it in Studio was for.** Eight green suites, an emulator, and two adversarial
reviews all missed it, and it made the game unreachable.

First thing I did after `start_stop_play`:

```
hrp = 0.00, 3.00, -160.00        <- Waiting.WaitingSpawn
Lane_0.Fork_1.ForkPad_1 at 0.0, -1.0, 14.0
lane Owner attribute = 11327553533 = the player's own UserId
```

The player owns Lane_0, the HUD says `ETASJE 1/10 — Velg en dør` and
`🔒 INNSKRIPSJONEN ER ULEST`, and they are standing on the waiting pad, 174 studs away across empty
sky, with no way to walk there. `onCharacter` writes `hrp.CFrame = CFrame.new(lane.checkpoint)` and
it does not take.

### Why. Frame trace from a server-side `CharacterAdded` handler, sampling every Heartbeat:

```
[0.0000] f01 parent=nil        hrp=0.00,0.00,0.00
[0.0051] f02 parent=Workspace  hrp=0.00,3.51,-160.00
[0.0149] f03 parent=Workspace  hrp=0.00,3.51,-160.00
     ... unchanged for 20 frames
```

**`CharacterAdded` fires while the character model is still UNPARENTED, with the root part at the
origin.** One frame later the engine parents it to Workspace *and* drops it on the only enabled
`SpawnLocation`. Everything `onCharacter` writes before that is thrown away, silently — no error,
no warning, the assignment succeeds and is overwritten.

The emulator modelled the exact opposite order: `Players:simulateSpawn` in `emu/services.luau`
parents the model **first** and never applies a spawn point. That is why nothing saw it.

### The fix

`onCharacter` now yields until the character is genuinely in the world, then places it:

```lua
local frames = 0
while char.Parent == nil and frames < 300 do
    task.wait(1 / 60)
    frames += 1
end
local lane = lanes[plr]      -- re-read AFTER the wait: a rebirth can rebuild the lane
```

`task.wait(1 / 60)` and not a bare `task.wait()` on purpose — a bare wait is a zero-length yield on
a virtual clock, so a frame-poll written that way burns its whole bound inside one scheduler step
and the headless check cannot express the defect at all. That was not a guess either; the first
version of this fix was written with `task.wait()` and the new assertion stayed red.

Verified in Studio on the rebuilt place: **`hrp = 0.00, 3.00, 14.00`**, dead centre of the player's
own floor-1 fork pad, still there two seconds later. `studio-shots/06-spawn-fixed.jpg`.

### The test, watched fail first

`check_forktower.luau` "STUDIO FINDING 1" replays the *recorded* order rather than the emulator's:
build the character unparented with the root at the origin, fire `CharacterAdded` (on its own
thread, because Roblox runs handlers in a fresh coroutine and the fix has to be allowed to yield),
advance one frame, then parent it **and** put it on the enabled `SpawnLocation`. Against untouched
source:

```
FAIL: a character the engine placed on the spawn AFTER CharacterAdded still ends up in its own
      tower (hrp 0.0,3.5,-160.0; pad -440.0,-1.0,14.0; off by 440.0 x, 174.0 z)
FAIL: ...and specifically not left standing on the waiting pad
fork tower: 111 passed, 2 failed
```

440 studs and 174 studs — the same numbers Studio showed. With the fix: 113/0, and 119/0 with the
other two blocks.

**Was it survivable?** Barely, by accident: `Config.World.FallGrace = 70`, so a player who walked
off the waiting pad and fell 70 studs would be rescued to their checkpoint — which is in their
tower. That is not a design, it is a coincidence, and no player would find it.

---

## 4. A glyph that does not exist in Roblox's font

`Config.Fork.SignEmoji.crack` was **🪨 U+1FAA8**, and Roblox draws it as an **empty rectangle**. One
of the four sign vocabularies the inscription names was illegible — on the door, on the pad and in
the HUD. `find_mojibake.py` was right that the bytes are fine; it is the font that has no picture.

Measured by rendering candidates into a `GothamBlack` TextLabel and photographing the window
(`studio-shots/04-glyph-test.png`, `05-glyph-block-test.png`):

```
U+1FA79  Emoji 12.0  bandage        renders
U+1FA9F  Emoji 13.0  window         EMPTY BOX
U+1FAA8  Emoji 13.0  rock           EMPTY BOX     <- shipped
U+1FAB0  Emoji 13.0  fly            EMPTY BOX
U+1FAE0  Emoji 14.0  melting face   EMPTY BOX
```

Every other glyph in `src/` is Emoji 5.0 or older and every one of them renders. U+1FAA8 was the
only Emoji-13 codepoint in the game.

**Fixed:** `crack = "🗿"` (U+1F5FF), measured to render, grey like `SignColors.crack`, and stone
like SPREKKEN is stone. Photographed in the world on floor 2: `studio-shots/07-crack-sign-fixed.jpg`.

**Not a leak** — a box matches a box, and the signs are uninformative by construction. It is a
legibility defect.

*Test first:* `check_forktower.luau` "STUDIO FINDING 2" is deliberately **not** a test of Roblox's
font, because nothing headless can be one. It is the list of every glyph that has been *looked at*
in Studio, and it walks every `TextLabel` and `ProximityPrompt` in the built world and refuses
anything else. Against untouched source:

```
UNSEEN GLYPH U+1FAA8, 23 time(s), first at Workspace.Towers.Lane_1.Fork_2.ForkPad_2.Inscription.Text
FAIL: every glyph the built world renders is one that has been looked at in Roblox Studio
```

Add an emoji to a label and it goes red until somebody has photographed it rendering. It does not
cover `Hud.client.luau`'s own strings, which are screenshotted here but not guarded.

---

## 5. Does it play? Yes — floors 1 and 2, both branches.

Everything below is from the real engine, not the emulator.

* **Spawn.** Lands on the fork pad and stays (post-fix). Walk, jump and the camera behave normally.
* **Reading.** Hold `R` on the pad; the bar fills; the doors dress. 1.17 s. `LES` and `VELG` are
  both on screen at once, which is what the separate `R` key was for.
* **Choosing.** `E` on a door: `Trygt valg: 🌌 Tomromssteg` on the safe one,
  `FELLE! 💨 Vindsteg er din, men veien opp er lang.` on the trap. The trap section really is
  longer and busier: **5 platforms / 0 hazards** safe versus **9 platforms / 3 hazards** trapped, on
  the same floor.
* **Platforms are reachable at the real jump height.** Step 3.4 studs, gap 2.0, tile 9, against
  `JumpHeight = 7.2` and `WalkSpeed = 16` read off the live Humanoid. Every hop was made by the
  navigation without a retry, including the two lateral ones.
* **The checkpoint holds — the 1.00/1.00 margin is real.** Walked into `Hazard_2_3` (at z 123 on a
  platform centred at z 120) and sampled every frame:

  ```
  [0.20] 0.03,27.20,122.51   <- touching the hazard
  [0.33] 0.00,27.70,118.50   <- put back
  [0.42] 0.00,27.16,118.50
  [0.50] 0.00,27.20,118.50   <- and it STAYS there
  ```

  118.50 is exactly the midpoint the geometry predicts: 1.00 stud of hazard clearance, 1.00 stud of
  platform edge. The character does not slide off the edge and does not re-trigger the hazard.
  `Au! Tilbake til sjekkpunktet.` fires once.
* **The three `AutomaticCanvasSize` ScrollingFrames scroll.** With eleven rows in the reveal card:
  `CardTraits AbsSize 356x172, AbsCanvas 356x261` and setting `CanvasPosition.Y = 1000` clamps to
  **89** = 261 − 172. The leaderboard (10 rows, content 237 < 256) and the stats panel (206 < 236)
  correctly do not scroll. `studio-shots/03-hud-reveal-scroll.jpg`.
  **Honest caveat:** the reveal card and the leaderboard were driven by firing `Reveal` and
  `Leaderboard` from the server with a hand-built payload. They were not earned by summiting.

### What I did NOT verify

* **A complete ten-floor run.** I played floors 1–2, both branches, twice. The emulator's "a reader
  clears 35 points, a guesser 82 platforms" is still an emulator claim; no human has summited.
* **A phone.** The viewport was 2889x1201 the whole time. `responsive.spec` and `hudcheck.luau`
  still own that question, and `hudcheck` is still wired into no gate.
* **A real 24-player server.** See below.

---

## 6. Render cost at 24 lanes — inconclusive, and here is why

Cloned the built fork ten floors deep across 24 lanes at the real `LaneSpacing`, giving **4110
parts, 1687 PointLights, 241 ParticleEmitters** in the DataModel, camera in lane 0 where a player's
is:

```
                                   draw batches   indices   Stats FPS   client memory
  empty (30 parts, 7 lights)             36        49762      60.0        2479 MB
  24 lanes x 10 floors                   36        49726      60.0        2480 MB
```

**Batches and index count did not move**, which is the actual answer: the other 23 towers are 220+
studs away and the renderer culls them entirely. They cost about **1 MB** of DataModel memory and
nothing to draw. Part count is not the problem here.

But treat this as weak evidence. It is synthetic clones, not 24 real players, and the frame-rate
side of it could not be measured at all: **a Lua `RenderStepped` loop driven over MCP read 15.0 fps
in every state including an empty world**, while the engine's own `Stats.Workspace.FPS` read 60.0
throughout. Studio throttles rendering when it is not the focused window, and driving it over MCP
means it usually is not. Do not trust a Lua frame counter taken this way.

---

## 7. The console

`get_console_output` after every session, four sessions, three builds. Every time, exactly this and
nothing else:

```
[ForkTower] profiles datastore unavailable (You must publish this place to the web to access
            DataStore.) — the game runs, progress will NOT be saved this session.
[ForkTower] leaderboard datastore unavailable (...same...)
[ForkTower] Fork Tower lastet. WorldSeed=20260909 Floors=10
```

**Zero errors. Zero warnings.** Both DataStore lines are the `tryStore` pcall doing exactly what
invariant 3 says it is for, in an unpublished place. Nothing else was logged across a spawn, four
reads, four door choices, two section builds, a hazard hit, a checkpoint return and a character
reload.

---

## 8. Engine and tooling facts worth keeping

* **`screen_capture` over MCP does not render BillboardGuis.** Proved with a control: a brand-new
  opaque red `BillboardGui` parented to a door did not appear either. ScreenGuis (the HUD) do
  render. So every picture in this file was taken with a GDI `CopyFromScreen` grab of the Studio
  window instead. Anything in this repo family shot with `screen_capture` is missing its
  billboards, silently.
* **`user_keyboard_input` holds are flaky.** Two of five `keyDown R … keyUp R` sequences produced
  `PromptButtonHoldBegan` and `PromptButtonHoldEnded` 2.4 s and 2.8 s apart with **no**
  `PromptTriggered`, on a prompt whose `HoldDuration` is 1.1 s. The same input worked on the retry
  and on every other attempt. Not a game bug — the game's own handler never saw a trigger — but a
  driving-the-session hazard: always confirm the read landed, never assume the keypress took.
* **`character_navigation` leaves a walk order on the Humanoid.** Teleporting afterwards does not
  cancel it; the avatar walks back to the old target. `film_anomaly.py` already says this and it is
  still true — `MoveTo(newPosition)` *after* the teleport, not before.
* **`tools/studio_open.ps1` does not know this game.** Its `$places` table has four keys and none
  is `fork-tower`; the run fails with `Unknown game`. The whole change is one line —
  `"fork-tower" = "ForkTower.rbxlx"` — but `tools/` was read-only for this pass, so an adapted copy
  was used instead. **Somebody who owns `tools/` should add that line.**
* **The MCP toggle needs cycling once per Studio session, and it can miss.** It took two passes on
  the third open; `tools/studio_mcp.py studios` is the only honest test of whether it took.
* **Nothing was published and nothing was committed.**

---

## 9. Left open (polish, not blockers)

1. **The first frame is a pile of text.** On spawn, the LobbyPad's `🔀 FORK TOWER / To dører. Én er
   en felle.` billboard, the WaitingPad's `Venter på et ledig tårn` sign **174 studs away**, and the
   fork pad's own inscription all draw on top of each other — every billboard is
   `AlwaysOnTop = true` with `MaxDistance = 220`, and 220 reaches from a tower to the waiting pad.
   See `studio-shots/06-spawn-fixed.jpg`. Lowering `MaxDistance` on the two pad signs, or dropping
   `AlwaysOnTop` on the waiting-pad sign, would fix it.
2. **The fork pad's inscription draws through the player standing on it.** `StudsOffset` y = 6 puts
   it at chest height of a character on the pad. Legible, crowded.
3. **The sign nubs are blown out.** The Neon nub Parts behind the emoji render as solid white/orange
   rounded rectangles at close range; the emoji sit on top and stay readable, but the nub itself
   carries no shape any more.
4. **REVIEW-3's item 5 list is untouched** — `Config.Passes` still dead, no Sounds, `hz.kind` still
   renders one shape for four kinds, choices still do not narrow the tree.
5. ~~`studio-shots/` is 12.6 MB of PNGs.~~ Done before committing: the five viewport captures are
   now quality-92 JPEGs, 12.89 MB → 2.95 MB. The two glyph tests stay PNG — they are text on a
   flat background, the one place JPEG ringing could change what the picture proves.

---

## Verdict

**Playable, and now actually reachable.** The core loop works in the real engine exactly as
designed: an unread door tells you nothing, a hold on `R` costs 1.17 seconds of real time charged
by the server, the doors dress the instant the bar fills, the trap is longer and busier, and the
checkpoint catches you where the geometry says it should. The console is silent.

REVIEW-3's open item 4 is **closed**: `PromptButtonHoldBegan` replicates, the read costs 1.1 s and
not 2.2, and the number in the design is right.

REVIEW-3's open item 1 is **closed for floors 1–2 and open above them**: somebody has now opened it,
played it, and photographed it, but no human has summited and no phone has seen it.
