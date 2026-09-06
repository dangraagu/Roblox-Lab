# Roblox Game Radar — 2026-09-06

On-demand scan (6 platform scouts → rank → concept briefs) for the SOLO portfolio dev.
**Excluded** the three already-shipped lanes (500-level maze obby · "+1 Jump Every Step" escape obby · "Grow a Crystal" cozy idle-grow), so every opportunity below is a **fresh genre**.
Ranked by `demand*0.4 + buildability*0.35 + differentiation*0.25`. 11 agents, 0 errors.

## Signal summary (what players want, past 7 days)

1. **"Steal a X" is the platform's #1 loop** (Steal An Egg #1 ~1.87M CCU; Steal a Brainrot record 25.8M CCU) — **but a demand trap**: hundreds of clones AND legally hot (Steal-a-Brainrot devs filed 4+ lawsuits). Do NOT clone it.
2. **Front page refills WEEKLY from micro-launches** (Zarahaven +2,153%/7d, Steal a Lucky Egg +1,149%, Would You Rather: Anime Tower +916%, Illegal Soccer +658%) — the exact window one solo dev can hit.
3. **Anomaly / single-location "service horror"** is explicitly called *"Roblox's defining 2026 genre"* and is the best-named solo sweet spot: procedural anomaly catalog + DataStore streak + single-server + **NO chase AI**.
4. **Co-op survival & escape horror** is surging into the **Sept→Oct Halloween spike** (99 Nights 300K+ CCU; Roblox's own "Monster in the Mansion"; Reddit "I NEED THIS" + rejecting "unscary Hold-E" filler; TikTok proximity-chat = top reaction-clip format; YouTube's strongest LIVE funnel).
5. **Loud anti-brainrot cohort** wants a REAL grind that isn't a clone; cozy/collection quietly resurging (Fish It +18 places).
6. **Idle/tycoon with automation + offline gains** = most consistently profitable solo genre.
7. **Avoid studio-scale lanes** Roblox is investing in (shooters, racing, sports, high-fidelity) — not solo-scale.
8. **Clip-worthiness IS distribution** — design shareable failure/reveal moments = free TikTok/YouTube marketing.

## Ranked opportunities

| # | Genre | Score | D | B | Diff | One-line concept |
|---|-------|:---:|:-:|:-:|:-:|------|
| 1 | Anomaly / single-location service horror | **8.75** | 9 | 9 | 8 | Night caretaker patrols a looping observatory; spot the procedurally-injected anomaly or extend your streak |
| 2 | Procedural roguelite escape-horror (Doors-style) | **8.05** | 9 | 7 | 8 | Descend a procedurally-assembled sunken station, evade one entity, bank meta-unlocks between runs |
| 3 | Exploration collection hunt ("Find the [X]") | **7.65** | 6 | 10 | 7 | Hunt hundreds of hidden lantern-spirits in a world that re-scatters each season |
| 4 | Choice tower / "Would You Rather" climb | **7.55** | 7 | 10 | 5 | Climb a fate tower; each two-door dilemma permanently mutates your avatar + stats |
| 5 | Idle-automation tycoon (offline gains + prestige) | **7.50** | 8 | 8 | 6 | Asteroid-salvage refinery; automation unlocks in minute 1, offline gains + prestige resets |
| 6 | Tower defense (fixed-lane, procedural waves) | **7.05** | 8 | 6 | 7 | Defend a lighthouse vs procedurally-scaled sea-fog waves; merge + upgrade beacons |

**Recommendation: build #1 (Anomaly: Night Shift at the Observatory).** Highest score, ~1–2 week MVP, and maps almost 1:1 onto the proven stack (procedural randomizer + DataStore streak + single-server + minimal UI) with **zero chase/pathfinding AI** — the hardest horror system is avoided entirely. Launches straight into the Sept→Oct horror spike, and every wrong call is a shareable clip.

---

## Concept 1 — Anomaly: Night Shift at the Observatory 🔭  *(top pick, score 8.75)*

**Hook:** Patrol the same looping observatory all night — spot what changed, or you'll never clock out.

**Core loop:** Walk one direction down a looping observatory concourse. Each pass, a procedural randomizer either leaves the hall normal or injects exactly ONE anomaly (moved telescope, flickered star chart, extra door, wrong reflection, a figure that shouldn't be there). At the hall's end: **ADVANCE** if it looked normal, **TURN BACK** if you spotted something wrong. Correct → streak/day ticks up, loop reshuffles. Wrong → reset to Day 1. DataStore saves best streak, the unlocked **Field Guide** of caught anomalies, and earned shifts/floors/endings. Tension is pure observation — no chase AI.

**Why it trends:** Anomaly horror = Roblox's defining 2026 genre (Scary Shawarma Kiosk 1B+ plays; Exit 8 film + official Roblox port mainstreamed "spot the difference / obey the rules"), and Google shows a Sept→Oct horror search spike. Every wrong call = a TikTok/Shorts clip (self-distributing). Differentiation: nearly every clone reskins the food kiosk — a fresh observatory setting + a persistent Field Guide / ranks / unlockable shifts is the retention layer rivals leave shallow.

**Solo build scope (~1–2 wk):** (1) ONE modular concourse room set (dark palette, fog, point lights). (2) Loop = a single teleport/reset back to hall start + re-roll. (3) Randomizer = Lua table of ~20–30 anomaly defs (toggle/move/recolor/swap a part), roll ~50% clean vs one-anomaly, store answer server-side. (4) Two ProximityPrompts (ADVANCE/TURN BACK) → compare to stored answer → streak++ or reset. (5) DataStore: bestStreak + caughtAnomalies set + currentDay. (6) Minimal UI: day/streak counter, Field Guide grid, death screen. Anomaly table is pure data → add more weekly, zero new systems. Polish = ambient hum + stingers + one jumpscare on death. **No chase AI, no pathfinding, no monster modeling.**

**Genre tag:** Horror → Survival / Escape (anomaly / liminal-space "spot-the-difference").

**Thumbnail:** Split "spot the difference" — LEFT normal concourse, RIGHT same hall with a pale figure between the telescopes circled in red + a subtle upside-down chart. Bold "WHICH ONE IS WRONG?" + "😱 DON'T ADVANCE". Dark teal/blue, one red accent.

**Paste-ready Roblox description:**

> 🔭 ANOMALY: NIGHT SHIFT AT THE OBSERVATORY 🔭 The scariest spot-the-difference anomaly horror on Roblox!
>
> You're the lone night caretaker of a looping observatory. Every pass, something might be WRONG. Spot an anomaly? TURN BACK. Nothing off? ADVANCE. One wrong call ends your night. 😱
>
> Inspired by Exit 8 & the 2026 anomaly horror wave — how long can your streak survive?
>
> 🌙 100+ hand-crafted anomalies to spot
> 📓 Unlock a Field Guide of every anomaly you catch
> 🕯️ New shifts, floors & endings as you rank up
> 👥 Play solo or bring friends to panic together
> 🔊 Headphones ON — sound is a clue
>
> Can you reach Day 100 flawless?
>
> ❤️ LIKE + ⭐ FAVORITE to save your progress — then share your scariest clip!
>
> anomaly game • spot the difference horror • night shift horror roblox • exit 8 roblox • obey the rules horror • service horror 2026

---

## Concept 2 — FATHOM 🌊 Sunken Escape Horror  *(score 8.05)*

**Hook:** Descend a flooding research station room by room — one thing down there is hunting you, and it never stops.

**Core loop:** Descend a drowned station; each room is procedurally assembled from modular prefabs (no two dives alike). Search each chamber for the exit valve/keycard while managing **oxygen, flashlight battery, NOISE**. ONE entity patrols by line-of-sight + sound — sprint/splash and it locks on; creep, kill your light, hide in lockers to break chase. Grab SALVAGE, descend deeper (darker, tighter, faster entity). Die/bank → surface hub → spend salvage on a meta-unlock tree (quieter swimming, bigger battery, revive, faster valve, entity-radar). Dive again, deeper, chase the leaderboard.

**Why it trends:** Demand converges across 5/6 scouts (99 Nights 300K+ CCU; Roblox fall co-op horror slate; Reddit begging for genuinely scary MP horror; TikTok proximity-chat = #1 horror reaction format; YouTube's strongest LIVE funnel). Edge = **discipline**: solo devs over-scope horror, so ONE polished procedural level + ONE strong entity out-retains sprawling half-finished games. Roguelite meta-unlocks = "one more dive."

**Solo build scope:** Ship **single-player first** (no netcode in MVP). (1) ~15–20 modular room prefabs with snap sockets → seeded assembler stitches a 10–15 room descent, difficulty by depth. (2) DataStore meta store: SALVAGE + small unlock tree. (3) ONE entity, compact state machine (Patrol → Investigate → Chase via LOS raycast + speed burst → Search/Reset); aggro from sprint/splash/light, lose by hiding + going dark. (4) oxygen/battery/noise meters + HUD, hide interaction, valve/keycard exit, ambient + entity audio, surface hub. **Defer to v1.1:** drop-in co-op via default character replication + built-in proximity voice (zero custom netcode), more prefabs, 2nd entity. Buildability 7 — the entity behavior + audio/atmosphere are the real cost.

**Genre tag:** Horror → Survival (escape room / roguelite).

**Thumbnail:** Diver with flashlight in a tilted flooded corridor looking back in terror; huge dark silhouette with glowing eyes + tentacles behind. Green murk + red emergency light. "IT'S BEHIND YOU 😱" + "NEW HORROR".

**Paste-ready Roblox description:**

> 🌊 SUNKEN HORROR • ESCAPE • ROGUELITE 🌊
>
> Trapped in a flooding research station with ONE relentless entity hunting you. Descend room by room, find the exit, and DON'T let it hear you. The station rebuilds itself every dive — no run is ever the same. 😱
>
> Love DOORS, PRESSURE or scary co-op Roblox horror games? This is your next obsession.
>
> 🔦 A DIFFERENT station every run (procedural rooms)
> 🐙 ONE smart entity that stalks by sight & sound
> 🫧 Manage oxygen, light & noise to survive
> ⚙️ Bank salvage → unlock upgrades between runs
> 🎙️ Proximity chat — scream with friends (drop-in co-op)
> 🏆 Dive deeper. Climb the leaderboard.
>
> Can you reach the bottom… or become part of the wreck?
>
> ❤️ LIKE + ⭐ FAVORITE to keep the lights on!
> 🔔 Join the group for updates + codes.

---

## Concept 3 — Find the Lanterns 🏮 (Spirit Hunt)  *(score 7.65 · highest buildability, 10/10)*

**Hook:** Hundreds of hidden lantern-spirits, a world that re-scatters every season — the cozy collectathon that never ends.

**Core loop:** Explore → spot a glowing lantern-spirit (cave/tree/secret room) → touch to collect → collection counter + badge progress tick up → milestones unlock cosmetics (trails, glowing skins) + new areas → world **RE-SCATTERS** on a daily/seasonal timer so the hunt refreshes forever. Retention = the visible "X / 200 collected" bar + re-scatter.

**Why it trends:** "Find the [X]" is the most algorithm-friendly, evergreen Roblox convention (Find the Markers = millions of visits) → steady compounding discovery, not a spiky fad. Directly answers the loud **anti-brainrot** appetite (real progression, no p2w, wholesome/parent-approved). Badges = badge-list discoverable; seasonal re-scatter = cheap "NEW UPDATE" thumbnails that re-trigger the algorithm. Demand held at 6 (evergreen not viral); buildability **10** — pure fit to the stack.

**Solo build scope (weeks):** ONE place, ONE modular map. Procedural-placement script picks N anchors from a larger pool at server start, parents a spirit model to each (this IS the re-scatter). Touched → collect RemoteEvent → server validates + appends spirit ID to saved set. DataStore (session-lock + retry) persists collected IDs + count. ScrollingFrame grid (found/silhouetted) + "X / total" bar. Roblox Badges at 10/50/100/all. Cosmetics gated by count (no purchases in MVP). No netcode beyond default replication, no AI. Updates = new models + anchors + flip seasonal seed.

**Genre tag:** Adventure → Exploration ("Find the X" / collectathon).

**Thumbnail:** Dusk forest glowing with floating lanterns; cute avatar reaching for one, delighted. "FIND THEM ALL!" + "0 / 100" counter badge. Warm orange/teal, one hero lantern bigger.

**Paste-ready Roblox description:**

> 🏮 Find the Lanterns! The cozy Roblox find the game where you explore, collect, and unlock EVERYTHING! 🌙
>
> Hundreds of glowing lantern-spirits are hidden across a world that RE-SCATTERS every season — so the hunt NEVER ends. No brainrot. No pay-to-win. Just a chill exploration collectathon with REAL progression. ✨
>
> 🔦 100+ hidden lantern-spirits to find
> 🗺️ Explore forests, caves, ruins & secret rooms
> 🏅 Unlock BADGES as your collection grows
> 🎨 Earn trails, glowing skins & cosmetics
> 🔄 Seasonal re-scatter = a fresh hunt every update
> 👨‍👩‍👧 Family-friendly & 100% FREE
>
> How many can YOU collect? 🧭
>
> 💛 LIKE + ⭐ FAVORITE to help more hunters find the game!
>
> find the markers, find the roblox, collect all, badge hunt, chill roblox games, exploration, collectathon

---

## Concept 4 — Would You Rather: Tower of Fate ⚖️  *(score 7.55 · fastest MVP)*

**Hook:** Every door rewrites your destiny — climb a tower where each "would you rather" choice permanently mutates your body, powers, and fate.

**Core loop:** Each floor = TWO doors, a fate/mythology "would you rather" dilemma (e.g. "grow dragon wings but never run again" vs "touch gold but crumble everything you love"). Pick via ProximityPrompt → avatar **permanently mutates** (cosmetic: wings/horns/halo/gold/chains + stat delta on Power/Luck/Curse/Speed). Build-card GUI updates. Climb; dilemmas escalate + branch on prior picks. Every ~10 floors a "Fate Gate" checkpoint saves (DataStore) + awards a Relic/Title. Compare your one-of-a-kind avatar, screenshot/clip, Rebirth for new branches. Retention = weekly dilemma-pack drops + secret endings.

**Why it trends:** Format exploding (Would You Rather: Anime Tower +916%/7d). Both Roblox + Google scouts flag the choice tower as the single best solo-buildable breakout because it's **"pure content + DataStore"** — no procedural gen, physics, or PvP netcode → fast MVP + cheap weekly content. Viral-by-design (every player's mutated avatar is screenshot bait). Differentiation only 5 (shovelware-flooded) — moat = a deep, well-written tree on a **fresh non-brainrot mythology/fate theme** (the "clones are shovelware" gap).

**Solo build scope (days):** ONE reusable floor prefab (room + two door parts + ProximityPrompts). Data-driven dilemma module: Lua table of ~50–100 `{prompt, doorA{text,statDelta,cosmetic}, doorB{...}}` — content = data. Mutation system: apply accessories/meshes + Humanoid property changes on pick. Fate-stats per player + build-card GUI. DataStore: floor, stat build, relics, mutations, rebirth. OrderedDataStore leaderboard (highest floor). "Fate Gate" checkpoint every 10 floors. Everyone climbs own instance in one server. Monetization stubs: gamepass (peek both outcomes / extra rebirth), dev product (skip floor). Post-launch = weekly dilemma packs (all data).

**Genre tag:** Party & Casual → Story / Choose-Your-Path (choice-tower climb).

**Thumbnail:** Shocked avatar between two giant glowing doors — LEFT gold/blue (angel wings + halo version), RIGHT red/purple (demon horns + chains). "WOULD YOU RATHER?" + red-vs-blue lightning divide, arrows on each door.

**Paste-ready Roblox description:**

> 🔮 Would You Rather: Tower of Fate ⚖️ — the ultimate Would You Rather tower on Roblox!
>
> Every floor = TWO doors, ONE impossible choice. Would you rather grow dragon wings but never run again? Touch gold but crumble everything you love? Each pick PERMANENTLY mutates your avatar, powers & fate — no two climbers look the same! 👀
>
> 🏛️ Climb an endless fate-themed tower
> 🚪 100+ hand-crafted Would You Rather dilemmas
> 🧬 Mutate your body, stats & abilities forever
> 😈 Chase rare Curses, godly Relics & secret endings
> 📸 Screenshot your build & compare with friends
> 🔁 Rebirth for all-new branching paths
>
> ⭐ LIKE + FAVORITE to unlock weekly dilemma drops & new floors!
>
> would you rather, wyr, choice tower, pick a door, roblox party game 2026

---

## Also ranked (no full brief — top 4 got briefs)

- **#5 Idle-automation tycoon** (score 7.50) — asteroid-salvage refinery, **automation unlocked in minute 1** (most idle games hit a day-3 wall because automation unlocks too late), offline gains + prestige. Reuses DataStore + single-server economy. Must stay clearly different from Grow a Crystal. Keywords: roblox tycoon, idle tycoon roblox, offline gains roblox, prestige simulator, automation tycoon, afk tycoon.
- **#6 Tower defense** (score 7.05) — original-theme (lighthouse vs sea-fog) fixed-lane TD riding the Plants-vs-Brainrots fusion wave while sidestepping the litigated brainrot skin. Lowest buildability (6) — wave logic + tower balancing + merge economy are more systems. Keywords: roblox tower defense, merge tower defense roblox, wave defense, roblox td.

---

*Generated by the `roblox-game-radar` workflow (6 scouts: Roblox charts, Reddit, Google, TikTok, YouTube, buildability). Same pipeline as the weekly Monday cloud routine.*
