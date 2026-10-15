# Outpost Zero: Sky City Tycoon

A calm city-builder for up to 6 players, one floating rock shelf each, on a ring above a sea of cloud. Walk to a lot on
your shelf and press its sign post's prompt: a **Home** brings settlers, a **Workshop** brings jobs, and every settler
who has a job is a citizen earning 0.25 credits a second. Spend the credits on new lots and on storeys (4 studs each,
up to 22), so the skyline rises as you play. A ★ over one lot marks the build that pays for itself soonest, counting
the wait. Every build gives your workers **Orders** for 10 minutes: they earn that long after your last build, online
or off, and then wait for you. Districts open at population 80 / 900 / 6 400 / 35 000 / 185 000 (Market Row, Sky-Rail
Yard, Skyport, Reactor Quarter, Crown Heights), each in a slot your city's own seed picks. The sky follows your
population through six bands, from Fogbound Dawn to Aurora Crown. When the Skyport opens, the **Grand Airship** flies
in over 12 s and moors above your Town Hall for the whole server to see (the brag moment). Now and then something
falls from the sky inside a red ring that is exactly its hit zone; **☕ Break** sits you down and pauses that. The
**Census** board beside your spawn ranks everyone, or just your friends, by population. Nothing is sold for Robux.

**State (2026-10-07): v1 built test-first from `DESIGN.md`, REVIEW-1 and its round 2 closed (`REVIEW-1.md`), green in
all 26 gates (`tools/gates.sh`). Never
played by a person, never opened in Studio, not published, no universe, nothing committed.** The gates ran on
`tools/luaujs` (a Luau runtime written for this build because the native luau CLI was missing from the machine; it
reproduces meteor-drop-tycoon's 20 recorded gate counts exactly, see `CLAUDE.md`). Re-run every gate on the native CLI
when it is back. Everything only real rendering, input or a live server can settle is in `EYECANDY.md` §8.

Measured, not promised (all headless, `CLAUDE.md` has the commands): the pacing model playing the game's own
`Economy` and `City` puts the Skyport at 37.1 min for a normal player (slow 38.8), Crown Heights at 133.9 min and a
complete skyline at 4.30 h; the scripted walker in `tests/walk.luau`, playing only through the HUD, built first at
3.6-4.2 s, made 6 purchases in the first minute and saw the Grand Airship dock at 37.6-37.7 min (four printed runs;
runs vary with the hazards it meets). That is for a player who follows the star; one who always buys the cheapest
storey instead gets it at 47.7 min (slow: 50.5), see `REVIEW-1.md` round 2, B3.

## Store description

For the experience page. 974 characters by `len()` in Python (the dashboard allows 1000), plain ASCII, so no
coloured-square emoji (`docs/publishing.md`). Every claim is a rule the gates assert: 22 storeys (`Economy.spec`),
the star (`Economy.spec`, `check_outpostzero`), six districts and a per-city layout (`City.spec`), the six skies
(`check_outpostzero_sky`), the airship (`check_outpostzero_airship`), the red ring (`check_outpostzero_hazards`), the
break (`_sky`, `_hazards`), the board (`check_outpostzero_board`), no Robux (nothing in the code sells anything).

```
Build a city on an empty sky-shelf above the clouds.

Walk to a glowing lot and tap BUILD. Homes bring settlers, Workshops bring jobs, and every settler with a job is a citizen who earns you credits. Keep them in balance and stack storeys until your towers stand 22 floors tall. A star marks the build that pays for itself soonest.

Your city grows into six districts, from the Landing Field to Crown Heights, and each city draws its own layout. The sky grows with your population: the fog lifts, balloons drift past, lanterns rise at dusk, a storm rolls through, and at last the aurora and the sky whales come.

Open the Skyport and the Grand Airship docks above your Town Hall for the whole server to see.

Now and then something falls from the sky. A red ring shows exactly where: step out of it and it misses. Press Break to sit down; nothing falls while you rest.

The Census board by your spawn ranks everyone, or just your friends, by population. Nothing costs Robux.
```

## Layout (Rojo, `default.project.json`)

- `src/server/Main.server.luau` → ServerScriptService: six shelves (rock, plaza, parapet with 12-stud glass, Town
  Hall, a real SpawnLocation each, the Census board), the city per owner (lots, sign posts with prompts, buildings,
  locked-district signs), the economy on the server's clock, saving with a session lock and owner token, the Grand
  Airship, the Census store. There is no client -> server remote: every action is a ProximityPrompt.
- `src/client/Hud.client.luau` → StarterPlayerScripts: the phone-first HUD (credits, balance bar, Orders, the ★ line,
  toasts, hints, ★ Show me), the ★ marker over the lot, the Census rows on your own board.
- `src/client/Sky.client.luau`: the six sky bands, Storm Front's lightning, the airship's flight, rare hazards and the
  ☕ Break (client-only, cosmetic, fires nothing).
- `src/shared/` → ReplicatedStorage: `Config` (every tunable), the pure rules with specs (`Economy`, `City`, `Board`,
  `Save`, `HudLayout`), the templates (`EnvBands`, `Rest`, `Responsive`, `FxClient` verbatim from plus1-jump; `Hazards`
  verbatim from meteor-drop-tycoon; `Rng` verbatim from anomaly-observatory; `Fx` with one added preset, `Dawn`), and
  `SkyArt` (the client's scenery, critters, weather, hazard models and airship).
- `tests/`: 12 specs, `project_check.py` (the place settings: StreamingEnabled pinned off), `CityModel.luau` (the
  pacing model) and `walk.luau` (the player's path). `design/`: the
  design-time Python model `DESIGN.md` quotes. `tools/`: `gates.sh` and the `luaujs` runtime.

`CLAUDE.md` says how to run every gate and names this game's traps. `EYECANDY.md` covers the sky, hazards, the break,
budgets, the needs-Studio list and the thumbnail shots; `MARKETING.md` the clips.
