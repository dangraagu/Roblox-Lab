# Grow a Crystal 💎 — marketing: clip list, media status, drafts

Live: **https://www.roblox.com/games/106123351742435** · universe `10543994765` / place `106123351742435`.
Last published 2026-09-10 (version 11). Everything since (the living cavern, review rounds 1 and 2, the highscore
board, the readable hint) is **not live yet**.

## The rules (docs/complete-game-standard.md §4-§5, read first)

- Marketing starts **only after the new version is live**, spread over a day and the next, one game at a time, in
  communities whose rules allow self-promotion, and **labelled as AI-assisted** (r/RobloxDevelopers rule 6 requires it).
- Studio, thumbnails, clips and publishing belong to the night shift (00:00-06:00,
  `C:\Users\bahs_admin\.claude\scheduled-tasks\roblox-night-shift\SKILL.md`).
- Clips are filmed with `tools/film_game.py` (real Studio viewport, `--source capture`), vertical **1080x1920**,
  **7-15 s**. A clip may stage only where the character starts, the camera, and the codes every player gets. It never
  edits the game's numbers and never fakes progress. Each clip's staging goes into `marketing/clips/manifest.json`.
- Nothing here costs Robux, and there is no gambling language: refraction is a free roll on a crystal you grew.

## What media exists, and why it is stale

| File | Made | Shows | Use now? |
|---|---|---|---|
| `marketing/thumbnail.png`, `marketing/shots/` | 2026-09-09 | the cavern before the living-cavern bands | no: replace with EYECANDY.md §9 |
| `marketing/clips/plant_seed.mp4` (5 s) | 2026-09-17 | one click plants a Shard | no: too short, old look |
| `marketing/clips/grow_timelapse.mp4` (68 s at 6.5x) | 2026-09-17 | three Shards grow | no: old look |
| `marketing/clips/harvest.mp4` (6 s) | 2026-09-17 | harvest, dust counter rises | no: no bursts yet |
| `marketing/clips/cavern_climb.mp4`, `cavern_descend.mp4` | 2026-09-17 | scripted camera up/down the terraces | no: no bands |

None of them has a band, a harvest burst, a beam, the Relax button or the board: they were recorded before
2026-09-23. `tools/content_schedule.py` still queues them for Shorts; after the re-shoot it should point at the new
files.

## Clip list (for `tools/film_game.py`, vertical 1080x1920, 7-15 s)

All of these start from a fresh Play session: Studio has no DataStore with API access off (EYECANDY.md §9 step 2),
so every take is a new player with 30 Gem Dust and 3 free Shard seeds. "Codes" means the HUD's code box with
`WELCOME` (+100), `CRYSTAL` (+500) and `MYTHIC` (+5000): 5 630 dust, which buys chambers 2 and 3 (500 + 1 100) and
leaves 4 030. A session that can never save grants the codes and the weekly Geode for that session only (nothing
persists, so nothing can be duplicated) and says "Saving is off here: progress won't save" at join; before 2026-10-01
it refused them, and clips 4-7 could not be staged at all. `robloxemu/check_growacrystal_clips.luau` plays every
staging step below in such a session, through the HUD's own buttons, and checks every number in this table.
Coordinates are Plot_0's, which are world coordinates. "Scenario" says whether `film_game.py` already has it (`CRYSTAL`
in that file) or the night shift has to add it (`tools/` is theirs).

**Clicking the HUD from `film_game.py`.** `laby_click_gui(shot, pattern, gui)` clicks the first TextButton under that
ScreenGui whose text matches a Lua pattern. The patterns the check verified: `"Buy Chamber"` and `"Crack Geode"` in
`CrystalHud`; `"^Legendary"` (or `"^Mythic"`) in `CrystalHud` for the seed row, anchored because the Geode button's
text ends in "→ Legendary" too; `"Relax"` in `CrystalGrotto`. A code: set the `TextBox` under `CrystalHud` with
`shot.lua`, then `"Redeem"`.

| # | Clip | Length | What the viewer sees | Staging | Scenario |
|---|---|---|---|---|---|
| 1 | `first_plant` | 8 s | three glowing plates, three real taps, three crystals sprouting; the dust counter and "Shard (3)" going down | fresh session; fixed scripted camera behind the spawn on terrace 0 (`crystal_static_cam`, from (-4, 6.5, -7) at (-4, 2.5, 5)); character parked behind the camera | exists: `grow_cycle`, cut `plant_three` lengthened from 5 s to 8 s |
| 2 | `grow_timelapse` | 10.5 s | the same three crystals growing through four stages; 68 s of real time at 6.5x, and the caption says it is sped up | same take as 1 | exists: `grow_cycle`, cut `grow_timelapse` |
| 3 | `harvest_burst` | 9 s | three real harvest clicks: a burst of shards in each crystal's refracted colour, the dust counter climbing, the ring on the socket | same take as 1 | exists: `grow_cycle`, cut `harvest_three` (66.0, 9.0) |
| 4 | `glowworm_glide` | 12 s | one tap on "Buy Chamber 3": the rubble over terrace 2 goes, the ceiling fills with glow-worms over about 4 s, blinking glowflies come out and glow-worm silk drifts down, the title card names Glow-worm Hollow | off camera: codes, then buy chamber 2 with the HUD; camera EYECANDY §9 shot 1, (-2, 8, -12) looking at (3, 28, 60); record the real click: `laby_click_gui(shot, "Buy Chamber", gui="CrystalHud")` | add |
| 5 | `legendary_beam` | 10 s | the brag moment's family: a real harvest of a Legendary seed: the gold (or magenta) beam to the ceiling for 2.5 s, the flash, the "LEGENDARY!" card | off camera: codes, buy chamber 2 (socket 9 is on its terrace); crack the weekly Geode (1 000 dust) **only in a Legendary or Mythic week** (the HUD's Geode button names it: from 2026-09-07 the weeks rotate Prism, Legendary, Mythic, Legendary, so 2026-09-28..10-04 and 2026-10-12..18 are Legendary and 2026-10-19..25 Mythic); select the Legendary (or Mythic) row in the seed panel (`"^Legendary"`), plant it on socket 9 and wait 20 min (Legendary) or 40 min (Mythic) of real time; camera EYECANDY §9 shot 5, (6, 12, -12) looking at (-3.8, 20, 18); record the click. A Legendary seed always ends Legendary or Mythic, so the beam always fires | add |
| 6 | `relax_pool` | 9 s | the avatar walks to the pool ring, taps 🛋 Relax, sits; the view softens; the chip says "Relaxing — your crystals keep growing" | off camera: codes, chambers 2-3 (the terraces are walkable at any chamber); `character_navigation` to (-4, 21, 106) (a floor, checked); camera EYECANDY §9 shot 6, (-9, 27, 97) looking at (0, 28, 125); record the real click: `laby_click_gui(shot, "Relax", gui="CrystalGrotto")` | add |
| 7 | `cavern_climb` | 11 s | the camera climbs all eight terraces, glow-worms overhead, locked chambers under rubble, to the lit pool | off camera: codes, chambers 2-3, so the second band is in it; then the existing path camera | exists: `cavern_climb` (re-shoot) |
| 8 | `board_turnaround` | 8 s | from the spawn the player turns round: the TOP MINERS board on the entrance wall, rows of names and dust, the prompt | **HELD.** In Studio the board has no rows (with no DataStore it says it is offline, or keeps loading in the published place with API access off; turning API access on writes to the live DataStore, which §9 forbids). Film it on the live server after publishing. **Never film the Friends view with a real account: it shows real friends' names.** | add, after publishing |

Two more that only a long take can catch, if there is time: a **moth swirl** visitor (one every 120-180 s from
Glow-worm Hollow on, `Config.Visitors`; record up to 3 minutes at chamber 3 and cut by hand; the **bat swoop** only
comes from the Waterfall Chamber, chamber 7, out of the codes' reach), and the **Heart of the Geode** (chamber 8;
only with a real long-played profile on the live server).

## Thumbnail and icon

The shot list is `EYECANDY.md` §9 (six set-ups, each with camera, place and what is in frame, output **1920x1080**),
recorded against the real geometry. Its recipe edits `ReplicatedStorage.Config` in a Studio-only copy (start dust,
growth time) to reach the late bands quickly; that is fine for a still, and it is why no clip uses that recipe.
Icon (512x512): a crop of shot 4 or 5.

## Positioning

- **One-liner:** plant glowing seed-crystals, watch them grow (even offline), and refract plain shards into
  Legendary and Mythic gems.
- **Genre anchors (what players search):** Grow a Garden, cozy idle / AFK sim.
- **Hooks:** offline growth · the refraction roll (climb a tier per hit) · a cavern that changes with every chamber
  · weekly Geode · Gem Codex · a highscore board with a friends view · free codes.
- **Audience:** all ages (maturity Minimal). No "paid random items" language: nothing is for sale.

## Drafts (HELD until the new version is live; post them yourself, labelled AI-assisted)

### r/robloxgamedev or r/RobloxDevelopers (check the sub's self-promotion rule the day you post)

**Title:** Grow a Crystal: a cozy idle game where crystals grow while you're offline (AI-assisted, feedback wanted)

**Body:**
> I made this with a lot of AI help (code and tests), and I'd like real players to tell me what feels off.
> You plant seed-crystals in your own cavern; they grow over real time, offline too, and each harvest rolls
> refraction: the crystal climbs one tier per hit (Shard → Quartz → Amethyst → Prism → Legendary → Mythic) and stops
> at the first miss. Gem Dust buys seeds, Luck and Growth, and new chambers, and the cavern changes as you open them:
> glow-worms, giant mushrooms, a waterfall, the Heart of the Geode. There's a weekly Geode, a Gem Codex, a highscore
> board behind your spawn that can switch to your Roblox friends, and a Relax button.
>
> Play: https://www.roblox.com/games/106123351742435 · codes `WELCOME` `CRYSTAL` `GEODE` `MYTHIC`
>
> Questions I'm stuck on: is a first Mythic at around half an hour too fast or too slow? Does the board read from the
> spawn?

Attach clip 5 or 3 where the sub allows media.

### r/roblox (media required)

**Title:** A cozy game where you grow crystals and refract them into Mythic gems (AI-assisted)

**Body:** clip 5 (`legendary_beam`) or 4 (`glowworm_glide`), then one line: "Free codes: WELCOME, CRYSTAL, GEODE,
MYTHIC. Built with AI help; feedback welcome." and the link.

### TikTok / YouTube Shorts

The clips above, one per post, with the caption saying what is real and what is staged (the manifest has it).
Grow a Crystal is on the shorts plan (`tools/content_schedule.py`, key `crystal`); swap its files for the re-shoot.

## Do-not

- No gambling or "paid random items" language; nothing costs Robux.
- No player counts, "trending" or claims the game does not back.
- Never show a real account's friends list, username list or DataStore contents in a clip.
- No new-platform accounts, no joining Discords just to drop a link, no paid promotion without the owner's go.
