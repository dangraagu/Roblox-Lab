# Gnome Garden Defense

A tower defence for phones: bugs march along a garden path toward your carrots, and the gnomes you plant beside
the path stop them. Rojo project (`default.project.json`): `src/server` -> ServerScriptService,
`src/client` -> StarterPlayerScripts, `src/shared` -> ReplicatedStorage.

## What you do
1. You spawn on the deck of your own garden bed (8 beds per server, one each). A fresh path is drawn every
   attempt: 30 cells from the hedge gap to the carrot patch.
2. The camera shows your whole garden from above the deck. Tap a glowing pad (on a phone the first tap zooms
   in on it and the next one picks it; the picked pad turns gold) and pick a gnome; the starred one is the
   gnome the glowing pads suit best: **Pebble** (slingshot, the first bug in reach),
   **Sprinkler** (slows every bug in reach), **Mushroom** (spore splash, from summer), **Lantern** (pierces
   armour, aims at the toughest bug, from autumn). Spring starts with 120 seeds: two pebbles.
3. Press **READY**. Stopped bugs pay seeds; surviving a wave pays a bonus. Plant more (14 at most) or tap a gnome
   to upgrade it twice or sell it: before the first wave of a bed a sale gives everything back (try pads
   freely), after it 70% of what you paid.
4. The tenth wave of each season brings a boss that eats all 20 carrots if it gets through. Stop it and the
   season turns, and the next gnome unlocks. Lose, and the season starts again on a fresh bed.
5. Spring (Stag Beetle), Summer (Snail Baron), Autumn (the Slug Queen, under the Harvest Moon), Frost (the Frost
   Mantis), then the endless **Moonlit Bed**: the same bed for everyone that day.

The garden changes with your progress: eleven bands from spring dawn to the aurora, with their own light,
scenery, critters and weather. Now and then an acorn (or an apple, an icicle...) falls where you stand: a red
ring shows where; step out of it. A hit only dazes you for 3 seconds. **PAUSE** freezes your whole garden,
bugs and gnomes alike, until you move or tap anything.

The board at the west end of your deck ranks the highest wave survived, measured by the server (public top 10
and your friends); walk up to it and the camera turns to read it. Nothing costs Robux: no passes, no products,
no loot boxes.

## State (2026-10-08)
Built and gated headless; not opened in Studio, not published. Four adversarial reviews in two rounds closed in
`REVIEW-1.md` (round 2 on top: nobody else can unpause you or end your AFK hold, a phone tap zooms before it picks
and the pick turns gold, no pad under the thumbstick, the best pads glow all game, the brag's line readable;
round 1 below it: the garden view and tap zoom, saves that recover, the brag shown for a win only), plus the
build's own pass past the brag. At publish: Max Players 8, Console OFF (no gamepad path). How to run every gate, and
this game's traps: `CLAUDE.md`. The numbers behind the balance: `DESIGN.md`. The look, the hazards, the budgets, what only Studio
can settle and the thumbnail shots: `EYECANDY.md`. Clips: `MARKETING.md`.

## Store description (Roblox, 815 characters)

```
Bugs are marching on your carrots. Plant gnomes beside the path and stop them!

- A fresh garden bed every attempt: the path is drawn new each time, so no two fights play the same.
- Four gnomes: Pebble (slingshot), Sprinkler (slows bugs), Mushroom (spore splash) and Lantern (pierces armour). Upgrade each one twice.
- Four seasons, four bosses: the Stag Beetle, the Snail Baron, the Slug Queen under the Harvest Moon, and the Frost Mantis.
- Then the endless Moonlit Bed, the same bed for everyone each day. How many waves can you hold?
- Public and friends leaderboard for your highest wave, counted by the server.
- Need a break? Pause, and your garden freezes until you are back.
- Made for phones: your whole garden on screen, and it zooms in where you tap.

Nothing costs Robux. No loot boxes, no pay-to-win.
```
