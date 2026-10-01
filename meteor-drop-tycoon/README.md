# Meteor Drop Tycoon

A chill drop-and-collect tycoon for up to 8 players. Meteors fall onto your own round plot; each landing
spot glows in the meteor's rarity colour 1.5 s before impact. Walk over a landed meteor and it zips into
your Smelter, which melts its ore into Stardust at a steady rate. Stardust buys three machines:

- **Beacon** (unbounded): more meteors, richer and rarer ones, and a new sky over your plot.
- **Collector** (8 levels): a dish around the Smelter that catches meteors for you. It sleeps 10 minutes
  after your last hand pickup, so it rewards playing, not idling.
- **Smelter** (unbounded): melts faster. Its hopper holds 20 s of melting.

The HUD stars the upgrade that adds the most income per Stardust for a player who walks to about one meteor
every 2.5 s, keeps the Smelter ahead of the rain, and moves to the Smelter whenever your hopper keeps filling up
(a player who collects much faster than that reaches the Falling Star about 3 minutes sooner by skipping the
Collector, which is the machine for breaks; REVIEW-1.md). Your Beacon level moves the sky through
six bands (Dusk Meadow, Twilight, Aurora, Starfall, Nebula, Galactic Core). At Beacon 22 a guaranteed
**Falling Star** comes down by your arrival pad (the brag moment: 35.5 min for a normal player in the
pacing model; the scripted walker in `tests/walk.luau`, buying only through the HUD, caught it at a median of
35.9 min over 40 runs in the built world, range 32.3-38.6). The **Star Chart** by your pad ranks everyone, or just your friends, by Beacon level.
Rare space junk falls in a red ring that is exactly its hit zone; **Stargaze** rests you and pauses it.
No stealing, no PvP, nothing sold for Robux.

**State (2026-10-01): v1 built and green in every headless gate; two adversarial reviews closed in `REVIEW-1.md`.
Never played by a person, never opened in Studio, not published, no universe.** Everything only real rendering, input or a live server can settle is
in `EYECANDY.md` §8 (needs Studio). The spec is `DESIGN.md`; the gates and traps are in `CLAUDE.md`.

## Store description

For the experience page. 814 characters by `len()` in Python (the dashboard allows 1000), no coloured-square
emoji (`docs/publishing.md`: 🟦 and 🟩 were rejected; ☄️ has not been tried against the endpoint yet, so if the
write is refused, bisect that line first). "Walk over them" and "the red ring shows exactly where it will land"
are what the headless gates assert (`robloxemu/check_meteordroptycoon*.luau`).

```
☄️ Meteors fall from the sky onto your own plot. Walk over them to collect them, feed your Smelter, and turn space rock into Stardust.

Upgrade three machines:
• Beacon: reach further into space for more and rarer meteors, and a new sky
• Collector: a dish that catches meteors for you
• Smelter: turns ore into Stardust faster

Your Beacon changes the sky over your plot: dusk, twilight, aurora, a starfall, a nebula and the galactic core. Now and then space junk falls too. A red ring shows exactly where it will land: step out of the ring and it misses.

Need a break? Press Stargaze to sit back and watch the sky. Nothing falls on you while you rest.

Catch your first Falling Star, then climb the Star Chart against everyone, or just against your friends.

No stealing, no raids, nothing to buy. Just meteors.
```

## Layout (Rojo, `default.project.json`)

- `src/server/Main.server.luau` → ServerScriptService: the world (8 plots, each with a real SpawnLocation),
  meteors, pickups against the trusted position, the Smelter, purchases, saving with a session lock and owner
  token, the one-time Falling Star, the Star Chart store.
- `src/client/Hud.client.luau` → StarterPlayerScripts: the phone-first HUD, the upgrade panel, the Star Chart
  rows on your own board (a SurfaceGui in your own PlayerGui).
- `src/client/Sky.client.luau`: the sky bands, meteor streaks, rare hazards and Stargaze (client-only,
  cosmetic, fires no remote).
- `src/shared/` → ReplicatedStorage: `Config` (every tunable), pure rules with specs (`Economy`, `Meteors`,
  `PlotGeom`, `Board`, `Save`, `HudLayout`, `Trace`), the templates (`EnvBands`, `Rest` verbatim from
  plus1-jump; `Hazards` = plus1-jump + deep-vein's marked vertical section; `Fx` + the `Dusk` preset;
  `FxClient`, `Responsive` verbatim) and `SkyArt` (client art).

## Run

```
# pure specs (from this directory)
luau tests/<Name>.spec.luau
# headless gates: rebuild the bundle first, every time
cd ../robloxemu && py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
luau check_meteordroptycoon.luau          # and _save, _board, _sky, _hazards, _hud, _compile
cd ../meteor-drop-tycoon && luau tests/walk.luau
```

In Studio: `rojo build -o MeteorDrop.rbxlx` (git-ignored), open it, Play. DataStores need a published place or
*Game Settings → Security → Enable Studio Access to API Services*; without them the server says so and the
session does not save. Set **Players.MaxPlayers = 8** in Game Settings (one plot per player).
