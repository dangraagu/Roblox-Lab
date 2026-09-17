# Steal a Cryptid

A Roblox steal-and-defend idle game about folklore monsters, built code-only (no assets) in this
repo's Rojo layout. **v1 is built and headless-tested. Nobody has opened it in Roblox Studio or
played it, it is not published, and there is no experience or place ID.** DESIGN.md is the spec;
CLAUDE.md is how to work on it, where v1 departs from the spec, and everything only Studio can answer.

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

- 8 cryptids in 4 tiers: Jackalope, Hodag, Chupacabra (Common); Dogman, Jersey Devil (Rare);
  Mothman, Nessie (Legendary); Bigfoot (Mythic).
- 4 camp tiers, 1 map (Pine Hollow), 1 currency (Essence).
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

## What is not in v1

Raiding other real players' lairs, teleports to reserved servers, rebirth and extra biomes,
mutations, sounds and music, leaderboards, codes, badges, trading, and anything sold for Robux.
DESIGN.md section 16 says why for each.

## Proposed store copy (895 characters as pasted, measured; ASCII only, no emoji)

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
> 8 cryptids across Common, Rare, Legendary and Mythic, from the Jackalope to Bigfoot. 4 camp
> tiers. You never fight or steal from other live players.

The copy promises only what v1 does: 8 cryptids, one map, poachers only while you play, no rewards
for likes or favourites, no "new content weekly". It must be re-checked against the game before
anything is published.

## Status

| | |
|---|---|
| Unit specs (luau CLI) | 9 files, 1 267 assertions, 0 failed |
| `robloxemu/check_stealacryptid.luau` | 332 passed, 0 failed (0 failing runs of 100) |
| `robloxemu/check_stealacryptid_guards.luau` | 184 passed, 0 failed (0 failing runs of 60) |
| `robloxemu/check_stealacryptid_hud.luau` | PASS: 10 viewports x 3 HUD modes, box fit and text legibility (0 failing runs of 10) |
| `tests/walk.luau` | 46 passed, 0 failed (0 failing runs of 60) |
| Mutation sweep | 56 of 56 mutations killed, 6 of 6 controls survived, every edit proven to reach the bundle |
| Adversarial reviews | two rounds; the second's ten findings are in REVIEW-1.md, all reproduced and closed |
| Opened in Roblox Studio | **never** |
| Published | **no** |

CLAUDE.md lists everything only Studio or a published place can answer.
