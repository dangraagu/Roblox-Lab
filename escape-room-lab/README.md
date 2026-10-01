# Escape Room Lab

A Roblox logic-puzzle game. You ride a lift into a sealed room whose exit door is a code lock with a
board of clue lines. Some lines stay dark until you solve a Lamp Grid or a Flask Shelf on the walls.
When every line is lit, you work out the code, the door opens, and the lift takes you to the next room.
Fifteen rooms in five wings (Reception, Archive, Greenhouse, Cold Storage, Reactor), then the Roof.
Every room is generated fresh on the server, and every puzzle is checked to have exactly one answer
that follows from its clues. Each room pays up to three stars (escaped, no wrong try, no hint); the
public and friends Star Board in the Atrium ranks total stars, ties to whoever got there first.

**State:** built 2026-09-30/10-01 from `DESIGN.md`, every headless gate green (numbers in `CLAUDE.md`).
Never opened in Studio, not published, no universe, nothing committed. What only Studio can settle is
listed in `EYECANDY.md` §8.

## Honest description

- Solo, or two players on the Pair Lift (both press GO). Up to 8 players per server, each pair or solo
  player in their own room.
- Three puzzle kinds: a Code Lock (the door: 3 or 4 digits, none repeat, with sentence clues such as
  "One digit is correct and well placed."), a Flask Shelf (put 3-5 flasks in the one order the clue
  sentences allow; each flask carries a letter as well as a colour), and a Lamp Grid (lights out, 3x3 or
  4x4; light every lamp).
- No timer and no fail state. A wrong try locks that station for 3, 6, 12, then 20 seconds.
- Hints are free and cost only that room's Unaided star. A hint never finishes a station.
- Rare hazards come down from the ceiling (from the Archive on, about one every three minutes of play;
  never at the door keypad or in a room's first 8 seconds). A red ring on the floor shows exactly where one
  can land, and it stays put: step out of it any time in the first two seconds. A hit is a short stumble
  and costs nothing.
- A Break button: your avatar sits and the Lab leaves you alone until you move.
- In a pair, the no-wrong-try and no-hint stars are the pair's: a wrong try or a hint by either costs both.
- Measured with a pacing model (assumed human times, `tests/Pacing.spec.luau`): a normal player reaches
  the Roof in about 39 minutes (p10 37.3, p90 41.2) and all 45 stars in about 70 minutes.
- Nothing costs Robux. No game passes, no developer products, no gambling, no promo codes in v1.

## Store text

Measured: 933 characters (the block below, without its fences), plain ASCII, no emoji.

```
Crack the codes, light the lamps, line up the flasks and get out of the Lab.

Every room is built fresh when you walk in, and the game checks every puzzle before you see it: each one can be solved by logic alone, no guessing.

- 15 rooms in five wings: Reception, Archive, Greenhouse, Cold Storage and the Reactor. Each wing has its own light, weather and wildlife.
- Three kinds of logic puzzle: number locks with clue lines, flask-order riddles and lamp grids.
- Play solo, or ride the Pair Lift with a friend and split the work.
- Up to 3 stars per room: escape, make no wrong tries, use no hints.
- Stuck? Hints are free. They only cost that room's hint star.
- Watch the ceiling. When something comes down, a red ring shows exactly where it lands. Step out of it.
- Need a breather? Press Break and the Lab leaves you alone.
- Reach the roof, then climb the star board, public or friends only.

Nothing in this game costs Robux.
```

Genre: Puzzle. Maturity: decided by the questionnaire, whose Preview page is the ground truth
(`docs/new-game-checklist.md` §6). Nothing in v1 is violent or gory.

## Layout

```
default.project.json   src/server -> ServerScriptService, src/client -> StarterPlayerScripts,
                       src/shared -> ReplicatedStorage, Workspace.StreamingEnabled = false
src/server/Main.server.luau   the whole authoritative server (world, rooms, Act, save, board)
src/client/Hud.client.luau    every 2D control (phone first)
src/client/Lab.client.luau    bands, decor, creatures, weather, hazards, the Break
src/shared/                   pure modules (unit-tested) + the verbatim templates
tests/                        *.spec.luau, the pacing model, the walk
design/                       design-time measuring tools (not shipped)
```

`CLAUDE.md` has every gate, how to run it, and the traps. `EYECANDY.md` has the bands, hazards, the
Break, budgets, the needs-Studio list and the thumbnail shot list. `MARKETING.md` has the clip list.
