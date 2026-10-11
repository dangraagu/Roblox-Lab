# Labyrinth Mariozo — Free Marketing Plan

A zero-budget plan to grow the player base, sequenced around the one thing that
currently gates everything: account verification. Everything here is free.

Game link: https://www.roblox.com/games/121268951050692/Labyrinth-Mariozo-Maze-Obby
(Use the "Copy link" button on the Creator Dashboard → Overview if the URL ever changes.)

---

## The one thing blocking everything: verification

The experience is set to **Public**, but Roblox still limits it to **"16+ users
and trusted friends"** until your submitted **ID / age verification clears**.
That check is on Roblox's side — nothing in the settings can override it.

**What that means for marketing:**

- Kids under 16 — your main audience — **cannot play or find it in search** yet.
- Random players you send to it will mostly hit a wall and bounce.
- **Trusted friends can already play right now.**

So the strategy is: **do all the on-platform work now** (it compounds and is
ready the moment the gate lifts), **invite friends now**, and **save the public
blast for when verification clears.** Blasting strangers today wastes the effort.

---

## Phase 0 — Do now (works even while 16+ limited)

### 1. On-platform SEO — the biggest free lever (mostly done)

Roblox's search and "recommended" algorithm reward keyword-rich listings,
likes/favorites, playtime, and recent updates. Levers:

- [x] **Description rewritten** with searchable keywords up front (*maze, obby,
  traps, monsters, coins, gems, leaderboards, friends*) and a "⭐ Like + Favorite"
  call to action. Applied to the live listing.
- [x] **Beta mode is OFF** (Beta mode hides the game from Home recommendations —
  correct that it's off).
- [ ] **Thumbnails** — see "Assets to capture" below. Currently one real image
  (the logo) plus a placeholder ROBLOX castle image. Weak thumbnails kill
  click-through. **This is the highest-impact thing left.**
- [ ] **Gameplay video** — Roblox boosts experiences that have a video. Capture a
  20–30s clip (see below).
- [ ] **Name / genre tweaks** — optional, branding-sensitive, see "Decisions for you".

### 2. Invite trusted friends (works today)

Trusted friends bypass the 16+ lock. This is the only channel that converts right now.

- On the Roblox game page, hit **···  → Invite / Share** or share the game link.
- Have Mio add his real-life friends as Roblox friends, then send them the link —
  as friends they can play immediately.
- Every friend who plays and **favorites/likes** feeds the algorithm, so the game
  is better-ranked the day the gate lifts.

### 3. Keep updating (free algorithm boost)

Roblox surfaces recently-updated games. Ship a small visible update every week or
two (a new theme, a tweak, a seasonal skin) and the "Updated" date refreshes.
You already have a fast deploy path (`publish_live.bat`).

---

## Phase 1 — The moment verification clears (the public blast)

When the "16+ and trusted friends" banner disappears, run all of this in the same
week so the traffic lands together (concentrated traffic ranks better than a trickle).

### Assets are ready below. Post order:

1. **YouTube Shorts + TikTok** — short-form video is where Roblox discovery
   actually happens now. A 15–30s clip of a fast maze run + a near-miss trap +
   the win screen. Post the same clip to both. Caption + hashtags below.
2. **Reddit** — post to r/roblox and r/RobloxGameDev (as "I made this, feedback
   welcome" — NOT spam). One post each, respond to comments.
3. **Discord** — share in any Roblox / game-dev servers you're in, plus a small
   "share your game" server. Never mass-DM.
4. **Word of mouth** — Mio tells school friends; they search "Labyrinth Mariozo"
   or use the link.

### Ready-to-post captions

**TikTok / YouTube Shorts (caption):**
> 500 mazes. Each one harder than the last. Dodge the traps, beat your best time —
> can you clear level 50? 🌀 Play **Labyrinth Mariozo** on Roblox (link in bio).
> #roblox #robloxgames #maze #obby #robloxobby #fyp

**Reddit (title + body):**
> Title: I built a 500-level maze game on Roblox — every maze is unique and gets harder
>
> Body: It's called Labyrinth Mariozo. Solo climb, group race, or play with friends;
> your progress saves so you continue where you left off. Dodge traps and monsters,
> unlock wall themes, and race the leaderboards for fastest time and highest level.
> Free to play, no purchases needed. Would love feedback on the difficulty curve.
> [link]

**Discord / friend share (one-liner):**
> 🌀 Made a maze game on Roblox — 500 levels, gets harder each time, race your
> friends' times. Free, come try it: [link]

### Hashtags to reuse
`#roblox #robloxgames #robloxgame #maze #obby #robloxobby #robloxdev #fyp`

---

## Assets to capture (Mio or you, in-game — free)

You can't screenshot real gameplay from outside the engine, so grab these from
inside the running game:

- **In Roblox, press the menu → screenshot**, or `PrintScreen`. Capture:
  1. A dramatic maze-from-above or a tense moment near a trap/monster.
  2. The win / best-time screen.
  3. The lobby with Mio's statue.
- Upload as **thumbnails** on Creator Dashboard → the start place → Thumbnails.
  Put the most exciting one first.
- **Video:** record 20–30s with any screen recorder (Windows `Win+G` Game Bar
  works), show a fast run + a win, upload under "Upload a video" on Content
  settings. No editing needed.

Good thumbnails + a video typically lift click-through more than anything else
free, so this is worth 15 minutes.

---

## Clip list

Nine short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer,
HUD and physics; never the emulator). `film_game.py laby <name>` records the vertical strip and encodes it at
1080x1920; each clip's staging goes into `marketing/clips/manifest.json`. The YouTube/TikTok caption above fits all
of them. `tests/docs_check.py` holds this table to its rules (lengths, size, a staging entry per clip, and `exists`
only for a scenario `film_game.py` really has).

Filming is the night shift's job (Studio 00:00-06:00, docs/complete-game-standard.md §5). This list says what to film
and how to stage it. `tools/` belongs to the tools owner: a clip marked **new** needs a scenario added to `LABY` in
`tools/film_game.py`. The two marked **exists** are there and were recorded on 2026-09-17, before the biomes, the
board and the walk guard: `lobby_enter.mp4` (7.0 s) and `coins_and_exit.mp4` (14.7 s), both 1080x1920. The third
recording, `level2_run.mp4`, is 19.5 s, too long for this list, and is left off it.

| # | clip | status | length | what the viewer sees |
|---|---|---|---|---|
| 1 | `lobby_enter` | exists | 7-8 s | the lobby, the Solo Climb door, the level picker, and the dark level-1 maze |
| 2 | `coins_and_exit` | exists | 13-15 s | coins and gems in the torchlight, the EXIT, the Level 1 complete card (played at 2x) |
| 3 | `lava_pulse` | new | 9-12 s | a lava trap goes safe, flashes yellow, burns orange; the player waits, then crosses in the safe window |
| 4 | `icicle_dodge` | new | 9-12 s | the ICICLE! banner, the blue ring, a step out of it, the icicle shattering where the player stood |
| 5 | `ice_fanfare` | new | 10-13 s | level 25's exit, the level card, then YOU REACHED THE ICE CELLAR!: flash, FOV punch, falling snow |
| 6 | `forge_bomb` | new | 9-12 s | the Lava Forge: embers, rusted pipes, a salamander, a lava bomb hanging over its ring, then falling |
| 7 | `crypt_chandelier` | new | 9-12 s | the Haunted Crypt: a spider on the wall, mist, the chandelier over its ring, the drop |
| 8 | `board_toggle` | new | 7-9 s | at the spawn: the TOP MAZE RUNNERS board, E pressed, PUBLIC turns to FRIENDS |
| 9 | `campfire_rest` | new | 8-10 s | the lobby campfire: "Rest by the fire", the character sits, the view softens, the biome board beside it |

### Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and use the game's own prompts
and remotes. It never edits the game's numbers and never fakes progress the HUD then shows.

**The deep levels need the thumbnail place.** Clips 3-7 play levels 6-201. A new account starts at level 1, so they
are filmed in the shots place of `EYECANDY.md` §9 (steps 1-2: `Labyrint-shots.rbxlx`, built from `src/`, **never
published or saved to Roblox**), whose edits are: no saving, `accepted = 480` so any level up to 481 can be started,
and no monsters. Those clips **hide the HUD** with the clean-frame snippet (§9 step 6), except where a banner or a
card is the point (clips 4 and 5, below), and their manifest staging list says "thumbnail place: no saves, level
started directly, monsters off". Start a level with `StartRun:FireServer(<level>, "solo")` from the lobby (§9 step 3)
and wait 6 s (the free-break sign) before recording.

**The walk guard (2026-10-01) and the path guard (2026-10-11).** The server does not count an exit reached faster
than anyone could walk there (`EYECANDY.md` §15), nor one it did not see the character walk to, however long the
clip waits first (`EYECANDY.md`, "Night shift 2026-10-11"). A clip that teleports next to the exit and touches it
gets "Too fast: nobody can run this maze in ..." or "That exit only counts when you walk the maze to it ..." and no
level card. So the clips that end on an exit (2 and 5) walk the whole way from the level's start: `laby_collect`
already navigates cell by cell at walking speed. A staging teleport inside a maze loses the path: put the character
back on the start cell and walk from there. Never switch a guard off to make a card appear: that would be the faked
progress the rules forbid.

**Never film a real friends list** (clip 8): the Friends view shows Roblox usernames. Use a Studio Local Server test
player (no friends: the board then says what an empty friends board says) or blur it.

### Staging, clip by clip

1. **`lobby_enter`** (exists). New Play session, camera distance pinned to 16 studs, behind the character facing the
   doors. Walk to the Solo Climb door (-16, 4, -15), hold its prompt, click Continue in the picker. A fresh account
   is honest here: it is on level 1.
2. **`coins_and_exit`** (exists). Straight after clip 1: level 1, camera pitched high behind the player. It collects
   the coins and gems nearest first, then walks to the exit: the Level 1 complete card. Cut 1.0-28.5 s of the raw
   take, played at 2x (say so in the manifest, as the 2026-09-17 take does).
3. **`lava_pulse`** (new). Thumbnail place, `StartRun(6)` (the first level with a trap), HUD hidden. Run the §9 helper
   with `LEVEL = 6, TARGET = "trap"`: the avatar stands in the passage beside the trap, facing it. Camera low beside
   the avatar, 8 studs back, the trap plate in the lower third. The trap cycles every 5.2 s (3.0 s safe, the last 0.8
   of it flashing yellow, then 2.2 s deadly orange): record one full cycle standing still, then, the moment the
   orange goes dark, `nav` across the trap cell to the passage beyond.
4. **`icicle_dodge`** (new). Thumbnail place, `StartRun(38)` (Ice Cellar). Keep the `LabyrintBiome` ScreenGui (the
   banner is the point) and hide the rest, the level panel included: its records are a no-save test player's.
   Helper `LEVEL = 38, TARGET = "hazard"`. Camera behind and to one side, 8 back and 6 up, catching the icicle
   overhead. The ring lights within 14 s and warns for 3 s: when it lights, `nav` one step into the ring, then
   straight back to the passage; keep the take where the icicle lands in the empty ring and throws its shards.
   Falling snow and icicle clusters on the wall tops are in frame.
5. **`ice_fanfare`** (new). Thumbnail place with one change: `accepted = 24` instead of 480 (the fanfare plays only
   for a player who has never cleared a level in the Ice Cellar; with 480 it shows the quiet card). `StartRun(25)`,
   HUD shown (the level card and the biome card are the point; nothing on them claims progress the test player has
   not made in this session). Walk level 25 to its exit with `laby_collect([])` (no pickups, straight to the exit,
   at walking speed, so the walk guard counts it). Record from 2 s before the exit: the level card (about 4.5 s),
   then the run goes on into level 26 and the Ice Cellar card plays with its flash and FOV punch, in falling snow
   (the ice grade has been blending in since level 23; level 26 is the first level named the Ice Cellar). The
   fanfare plays once per Play session: record the first try.
6. **`forge_bomb`** (new). Thumbnail place, `StartRun(76)`, HUD hidden. Helper `LEVEL = 76, TARGET = "hazard"`
   (the lava bomb); a trap in view from there is better still. Camera 10 back, level with the wall tops. In frame:
   embers rising, rusted pipes, grates and soot on the walls, a salamander at the foot of a wall, the basalt bomb
   with its molten core over the blue ring; record through the drop (orange sparks).
7. **`crypt_chandelier`** (new). Thumbnail place, `StartRun(201)`, HUD hidden. Helper `LEVEL = 201, TARGET =
   "hazard"`. Camera low beside the avatar, looking up at the chandelier (iron hoop, four candles) over its ring;
   mist, skulls on ledges and cobwebs on the walls. Spiders climb wall faces near the player (two per crypt level,
   and a bat): wait until one is in frame, then record through the drop.
8. **`board_toggle`** (new). Studio Local Server, 1 player (a test player). Fresh Play: the character stands on the
   green pad. Walk toward the board at (-15, 3, 2) until its prompt shows (it shows from 10 studs), press E once.
   Camera over the shoulder at 14 studs, the board filling the upper two thirds. With no data store it shows PUBLIC
   and "No one on the board yet. Clear level 1 and be the first!", then FRIENDS with the empty-friends message. With
   API access on, in the published place's Studio session, the real public top 10 shows instead (real usernames:
   the public view only, never the Friends view).
9. **`campfire_rest`** (new). Any Play session, in the lobby. Walk to the campfire corner at (24, 0, -4) until the
   "Rest by the fire" prompt shows (12 studs), use it. Camera 12 studs out at sitting height, the fire and the biome
   board (5 studs right of the fire, 7 back) in frame. Record the sit, the softened view, and the stand-up when the
   character walks off.

---

## Decisions for you (say the word and I'll apply)

These touch branding, so I left them for you to approve:

1. **Name for search.** "Labyrinth Mariozo" only contains one word kids search
   for. Appending a keyword raises discoverability, e.g.
   **"Labyrinth Mariozo 🌀 Maze Obby"**. Keeps Mio's name, adds search hooks.
   Want it? (Reversible.)
2. **Subgenre.** It's currently Puzzle / Escape Room. Because it has traps and
   parkour-style navigation, **Puzzle / Obby** (or Adventure) may pull more
   traffic, since "obby" is one of the biggest categories on Roblox. Keep
   Escape Room, or switch?

---

## What NOT to do

- Don't pay for Roblox sponsored ads yet — pointless while 16+ limited, and not free.
- Don't mass-DM or spam-post the link; Roblox and subreddits remove it and it
  hurts the account.
- Don't buy fake visits/likes — Roblox detects and penalizes it.

---

## Summary

- **Done now:** description SEO, confirmed Beta mode off, this plan + ready assets.
- **You/Mio, 15 min:** capture 2–3 thumbnails + a short video, upload them.
- **Now:** invite trusted friends (only channel that works pre-verification).
- **When verification clears:** run the Phase 1 blast (captions above) in one week.
- **Ongoing:** ship a small update every week or two to stay "recently updated".
