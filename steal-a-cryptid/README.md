# Steal a Cryptid

A Roblox steal-and-defend idle game about folklore monsters, built code-only (no assets) in this
repo's Rojo layout. **v1 is built and headless-tested. Nobody has opened it in Roblox Studio or
played it, it is not published, and there is no experience or place ID.** DESIGN.md is the spec;
CLAUDE.md is how to work on it, where v1 departs from the spec, and everything only Studio can answer.
EYECANDY.md is the night (its bands, hazards, rest, the thumbnail shot list); MARKETING.md is the clip list.

## What the game is

You own a moonlit lair on a shared forest road. Three pedestals outside your gate each show a
cryptid you can buy: the exact species, tier, income and price, never a mystery roll. Each cryptid
sits in a cage and fills an Essence jar every second, online or off (up to 8 hours), until you step
on your Collect Pad.

From your Hunt Board you enter a Rival Camp: a camp generated for that raid in a private pocket of
the same server. Its yard is split by fence lines whose gaps hold timed laser nets, with snares in
between. Walk in, stand at a cage and hold to grab one of its three cryptids, and carry it back out
through the gate at a slower pace. Reach the gate and it is yours. Walk into a burning net or a snare
and you are sent home with nothing, and the permit you paid is gone. After a successful raid that
camp tier stays on alert for a while.

At home you place your own laser nets (up to 4) and snares (up to 6). Every few minutes while you
are in the server, a poacher NPC walks your yard toward your fullest jar, 10 seconds after a warning.
If your traps catch it you get a bounty; if not, it leaves with half of that one jar. Traps are set
before it comes: once a poacher is in the yard, no new trap can be placed. Owning a cryptid of one tier opens the
next camp tier, and harder camps hold better cryptids.

**The night deepens with your Journal** (EYECANDY.md). The lairs stand on a bluff over a dark ravine, with the
forest running on beyond it to the ridges (step off the bluff and you are simply put back at your lair). Pine
Hollow starts at dusk; your first Rare brings moonrise and owls on the pines, a Legendary brings strange lights (an
aurora, will-o'-wisps, red eyes in the treeline), and the Mythic brings Mythic Night: a gold aurora, UFOs over the
ridge, meteors, and Bigfoot himself walking the horizon. Past it, a lair earning 1 350 Essence a second (three
Bigfoots' worth) brings the Gathering: a crimson moon, embers, moths, and the legends of Pine Hollow (Mothman,
Dogman, the Jersey Devil) standing on the far rim to look at your lair. Each camp tier is its own place, with its
own weather and life: badlands (blowing sand, tumbleweeds), pine barrens (fireflies, the Jersey Devil circling over
the pines), a loch shore where Nessie glides past a ruined castle (mist, moths at its lit window), and a redwood
forest (drifting spores, wisps). Your own cages get a little habitat per species. Now and then a crow, bat,
will-o'-wisp or meteorite dives at you at home, well telegraphed (a red ring: step out of it); a hit is only a
stumble. A Rest button sits you by a campfire and the critters leave you alone; poachers, jars and raids do not
stop for it.

**The Top Lairs board** stands on every lair's front fence, behind the Collect Pad. It ranks the best lair income
each player has ever had, measured by the server from their own cages, and a tie goes to whoever got there first.
Press E at it to switch between everyone (the top 10) and your Roblox friends (once you own a cryptid, your own row
is always on that list, with your real rank).

- 8 cryptids in 4 tiers: Jackalope, Hodag, Chupacabra (Common); Dogman, Jersey Devil (Rare);
  Mothman, Nessie (Legendary); Bigfoot (Mythic).
- 4 camp tiers, 1 map (Pine Hollow), 1 currency (Essence), 5 home skies and 4 camp places.
- No player ever fights or steals from another live player. Rival camps are generated.
- **Nothing costs Robux.** No game passes, no developer products, no crates, eggs, wheels or paid
  re-rolls. Re-rolling the pedestals is free on a 30-second cooldown.

## How a session goes (measured headless by a scripted player, not by a person)

From one run of `tests/walk.luau` (the final run of the second 2026-09-17 pass). The walker presses
the real HUD's buttons, presses prompts only from inside their reach, and follows a well-timed route
through each camp, so it is a competent player, not a new one. Camps are random per server, so the
numbers move run to run.

- lands on its own lair's arrival marker; the HUD says "Buy your first cryptid - walk to the glowing
  pedestal and press E";
- walks 16.5 studs and buys the Jackalope (30 Essence) 2.1 s after landing; the third pedestal now
  shows a Rare Jersey Devil at 5 400 as the next goal;
- the Collect Pad hint appears at 7.3 s, when the jar holds 5; collects 7 Essence at 9.2 s;
- first raid: a Common camp with 1 net, 1 snare and 6 rocks, gate to prize to gate in 13.6 s against
  a 13.83 s plan; steals a Chupacabra and is home at 24.3 s; income goes from 1/s to 4/s;
- one minute after joining: 2 cryptids, 4 Essence/s, a 360 permit to save for;
- saves up 450 Essence and, through the Build button and a click on each tile, closes two gaps of the
  first fence line with snares and puts a laser net in the third;
- 300.3 s into the session the first poacher is announced; it appears 10.0 s later and, this run,
  slips past the net and leaves with 286 Essence from the Chupacabra's uncollected jar;
- a Rare camp (360 permit, 3 nets, 2 snares) steals a Jersey Devil in 21.4 s against a 21.56 s plan;
  income goes from 4/s to 22/s;
- leave and rejoin: cryptids, traps, Journal and 205 Essence are all still there, and the character
  lands on the arrival marker again.

## How long it takes (measured in Luau by a model player, not by people)

`tests/Pacing.spec.luau` plays 24 sessions per player model on the game's own rules: real generated camps solved by
the game's raid solver, raid success judged by the server's own catch rule against a timing error, the real prices,
pedestals, permits, alerts and poachers. Minutes of play, median (fastest-slowest):

| player | first Rare | first Legendary | first Mythic (Mythic Night) | the Gathering | nine Mythics |
|---|---|---|---|---|---|
| normal raider (timing error 0.25 s, raids at 2x the solver's time) | 3.9 | 14.5 | **35.6** (31.8-76.3) | 97.3 | 190.9 |
| casual raider (0.35 s, 3x) | 4.9 | 17.4 | 59.5 | 122.5 | 213.8 |
| never raids | 10.8 | 61.2 | 180.5 | 222.0 | 325.0 |

The first Mythic is the brag moment (the standard asks for one in about 30-45 minutes); nine Mythics is the
long-term goal, and the Top Lairs board the way to compare. The Mythic's price was lowered to reach that (one hour
of its own income instead of four: CLAUDE.md Deviations). These are a model's minutes, not playtests.

## What is not in v1

Raiding other real players' lairs, teleports to reserved servers, rebirth and extra biomes,
mutations, sounds and music, codes, badges, trading, and anything sold for Robux.
DESIGN.md section 16 says why for each. (DESIGN.md also cut leaderboards; the owner's complete-game standard asks
for one, so v1 has the Top Lairs board.)

## Store description (989 characters as pasted, measured; ASCII only, no emoji)

> Build a lair of folklore monsters, then sneak into rival camps and steal theirs.
>
> Buy cryptids from pedestals that show exactly what you get - species, income and price. No
> crates, no eggs, no spin wheels, and nothing in the game costs Robux.
>
> Every cryptid fills an Essence jar, even while you are offline (up to 8 hours). Step on your
> Collect Pad to bank it.
>
> Hunt from your Hunt Board. Each rival camp is freshly generated: fence lines, snares and laser
> nets that switch on and off. Time your crossing, hold to grab a cryptid, and carry it out the
> gate. Get caught and you go home empty-handed.
>
> Defend your own lair. Place laser nets and snares, because while you play, poachers come sneaking
> toward your fullest jar. Catch one for a bounty.
>
> 8 cryptids, from the Jackalope to Bigfoot. The rarer your collection, the deeper the night over
> Pine Hollow. Compare your best lair with everyone, or just your friends, on the Top Lairs board.
> You never fight or steal from other live players.

The count is of the text as pasted into the store's form: the paragraphs above joined with one blank line between
them, each paragraph on one line, without the quote marks. The copy promises only what v1 does: 8 cryptids, one
map, poachers only while you play, the board, no rewards for likes or favourites, no "new content weekly". It must
be re-checked against the game before anything is published.

## Status

Final tree of 2026-10-01 (pass 2 toward the complete-game standard): **37 suites, 4 100 assertions passed, 0 failed,
plus 7 PASS lines**.

| | |
|---|---|
| Unit specs (luau CLI) | 16 files, 2 441 assertions, 0 failed (the game: Economy 219, Offers 36, Layout 202, Heist 79, Trace2D 52, Poacher 51, CryptidModel 552, Pacing 17; the night: Night 477, NightConfig 298; templates: Rng 32, Responsive 70, EnvBands 124, Hazards 111, Rest 55, Board 66) |
| `robloxemu/check_stealacryptid.luau` | 334 passed, 0 failed |
| `robloxemu/check_stealacryptid_guards.luau` | 200 passed, 0 failed (6 of 6 runs after its last change) |
| `robloxemu/check_stealacryptid_board.luau` | 78 passed, 0 failed: the Top Lairs board, public + friends |
| `robloxemu/check_stealacryptid_hud.luau` | PASS x 2: 10 viewports x 3 HUD modes, box fit (overlap rule 4b on) and text legibility |
| `tests/walk.luau` | 46 passed, 0 failed |
| The night (EYECANDY.md): `check_stealacryptid_{night,hazards,rest,budget,budgetcap,card,compile,lateroad,keepout,life,longroad,edge,view,latehit,fall}` | 583 + 69 + 75 + 46 + 12 + 13 + 44 + 12 + 28 + 4 + 4 + 42 + 44 + 12 + 13 passed, 0 failed; `_nighthud` 5 x PASS |
| Mutation sweeps | pass 2 (EYECANDY.md section 15): 38 of 38 mutations killed, 5 of 5 controls survived, every edit proven in the bundle; earlier: 56 of 56 (the v1 review fixes), 70 of 70 and 38 of 38 (the night) |
| Adversarial reviews | two rounds on v1 (REVIEW-1.md), two on the night (EYECANDY.md sections 13, 14); **pass 2 is not reviewed** |
| Opened in Roblox Studio | **never** |
| Published | **no** |

CLAUDE.md lists everything only Studio or a published place can answer.
