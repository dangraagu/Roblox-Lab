# Roblox Game Radar — 2026-09-05

On-demand run of the `roblox-game-radar` workflow (6 platform scouts → synthesis → 4 concept briefs). Focus: trending Roblox demand, last 7 days, ranked by demand × solo-buildability × differentiation for a solo dev whose proven stack is **procedural generation + DataStore + single-server**.

> Note: +1 Jump Every Step (built + shipped 2026-09-05) already captures the #1 "+1-per-step" lane. The lighthouse concept below is the same loop, different theme — treat it as a v2/reskin idea, not a new build.

## Convergent signals
- **"Steal a X" idle-collector loop = biggest concurrency on Roblox** (Steal an Egg #1 ~1.87M CCU; Steal a Brainrot only game ever past 25M) — **but saturated + litigated** (4+ lawsuits) and Roblox forced Steal an Egg to strip its AI "Reels" doomscroll (Aug 29). Playbook: copy the LOOP, never the brainrot THEME, 100% original art, no AI reels.
- **"+1 per step" incremental-walk obby is the clearest solo sweet spot** — multiple clones jumped 40–45% in an hour and crossed 10K CCU; +1 Speed Keyboard Escape ~267K CCU at #4. Built on exactly our proven skills.
- **Cozy idle-grow / collection sims durable + DataStore-native** — Grow a Garden 1.0–1.2M CCU, 1B visits in 33 days; Fish It! ~114K climbing. A niche BEYOND pets/eggs/fish/plants is "wide open".
- **Co-op survival/roguelite horror durable, not a spike** — 99 Nights peaked 14.2M CCU / 26B visits; Monster in the Mansion = Fall-2026 spotlight. Psychological/atmospheric horror under-supplied + AI-slop-resistant.
- **Cross-cutting rules:** social/multiplayer hook = the retention gate; every climbing game ships `<game> codes` + steady updates; TikTok reaction-clip (a manufactured 5–15s payoff/loss beat) = free distribution; persistent-progression + leaderboard + rebirth out-rank round-based.

## Ranked opportunities (score = demand·0.4 + buildability·0.35 + differentiation·0.25)
| # | Genre | Concept | D | B | Diff | Score |
|---|-------|---------|---|---|------|-------|
| 1 | Incremental escape-obby (+1/step) | Endless lighthouse; every step widens lantern glow; rebirth to pierce fog | 9 | 10 | 6 | **8.6** |
| 2 | Cozy idle-grow / collection sim | Procedural crystal cavern; seeds grow/refract into rarer gems offline | 8 | 9 | 6 | **7.85** |
| 3 | Idle-income collector (+ light steal) | Glow deep-sea aquarium mints pearls; optional raid rival tanks | 10 | 7 | 5 | **7.7** |
| 4 | Co-op roguelite escape-horror | Procedural derelict space station; one entity hunts 1–4 players | 8 | 6 | 8 | **7.3** |
| 5 | Satisfying restoration clicker | Power-wash/restore procedural ruins; no timers, ASMR beat | 6 | 10 | 5 | **7.15** |
| 6 | Procedural roguelite dungeon RPG | Infinite daily-seeded dungeon; class-based; persistent gear; 1–4 co-op | 7 | 5 | 9 | **6.8** |

RPG is the biggest **latent** gap (Reddit: ~253 games vs ~31M median visits) but heaviest to build (combat/AI) — do it AFTER a fast-win lane funds it.

---

## Concept 1 — +1 Light Per Step 🔦 Escape Obby  *(score 8.6 · same loop as the shipped +1 Jump; a themed v2)*
**Hook:** Every step widens your lantern's glow — climb an endless fog-choked lighthouse, rebirth to shine brighter/faster, light up the global leaderboard.
**Core loop:** step → +1 Light (glow radius grows) → bigger glow pierces fog → reveals next platforms so brighter = faster/safer → ascend endless procedural lighthouse → rebirth for permanent multipliers (light/step, fog-vision, climb speed, start floor) → global leaderboard → codes drop instant Light. Satisfying clip beat = the glow bubble swelling out of darkness.
**Solo scope:** Days. Reuse the maze/+1 Jump stack: vertical procedural generator, server-authoritative step-count → client PointLight radius + Lighting fog, DataStore (floor/light/rebirth/mult), rebirth button, OrderedDataStore board, codes table, 2–3 gamepasses (2x Light, faster climb, starter glow).
**Genre tag:** Obby & Platformer → Tower-climb / Incremental (rebirth) escape obby.
**Paste-ready description:**
```
🔦 +1 LIGHT PER STEP! Every step GROWS your lantern in this NEW incremental escape obby! Climb an ENDLESS procedurally-built lighthouse, pierce the fog, and REBIRTH to shine brighter, climb faster & top the GLOBAL leaderboard! ⬆️✨

How high can you reach before the fog wins?

⭐ FEATURES:
🔦 +1 Light every step — watch your glow GROW
🌫️ Endless procedural lighthouse — never the same climb twice
⚡ Speed obby action — race up the stairs
🔁 REBIRTH for permanent boosts + deeper fog vision
🏆 Persistent GLOBAL leaderboard — flex your floor
🎁 CODES drop often — FREE Light boosts!

👍 LIKE + ⭐ FAVORITE for more CODES + updates!

Tags: +1 per step, +1 light per step codes, escape obby, speed obby roblox, rebirth obby, incremental obby, grow per step, roblox obby codes
```
**Thumbnail:** dark navy fog bg; blocky avatar mid-stride on glowing spiral stairs wrapped in a radiant glow bubble; giant "+1" bursting off the step; before/after tiny→huge glow; bright UP arrow + "REBIRTH" button; "+1 LIGHT!" top-left.

---

## Concept 2 — Grow a Crystal 💎 (Cavern Idle)  *(score 7.85 · best NEW-genre bet)*
**Hook:** Plant seed-crystals in your cavern and watch them grow/refract into rare gems — even while you're offline!
**Core loop:** plant seed → timed growth stages w/ hidden "refraction roll" upgrading rarity (Shard→Quartz→Amethyst→Prism→Legendary→Mythic) → harvest for Gem Dust → spend on rarer seeds / new chambers / luck+growth boosters → auto-expand procedural chambers (biome rarity modifiers) → offline growth = log in to a full cavern → weekly Geode event + codes + trade dupes to complete Gem Codex.
**Solo scope:** DataStore-native, single-server-per-player plot. Offline growth via timestamp diffing on join (no live sim). Rarity/refraction = plain Lua config. Procedural cavern = grid of reusable emissive "socket" parts, tiny art budget. MVP = plant→grow→offline-harvest→expand + Geode + codes; defer trading/gamepasses/leaderboard.
**Genre tag:** Simulation → Idle (incremental / collection simulator).
**Paste-ready description:**
```
💎 Grow a Crystal 💎 — the COZY idle mining sim where seed-crystals GROW into rare gems even while you're offline! 🌙

Plant glowing seed-crystals, watch your cavern expand, and refract plain shards into LEGENDARY & MYTHIC gems. An AFK-friendly grow game — earn gems while you sleep! 😴✨

⛏️ FEATURES:
🌱 Plant & grow seed-crystals into 50+ rarities
💤 OFFLINE growth — come back to a fuller cavern
🔮 Weekly GEODE events for exclusive gems
🔁 Trade rare gems & complete your Gem Codex
🕳️ Auto-expanding procedural crystal cavern
🎁 Redeem crystal cavern CODES for free boosts!

Love Grow a Garden, Fisch & cozy idle simulators? This is your next obsession. 💖

👍 LIKE + ⭐ FAVORITE to unlock more gems, codes & updates!

🔎 grow a crystal • idle mining sim roblox • cozy roblox game • afk grow game • gem collection sim • grow a garden alternative
```
**Thumbnail:** shocked/happy avatar kneeling in glowing cavern holding a huge rainbow "Mythic" gem; rows of crystals stepping up in size; "GROW A CRYSTAL!" + "💎 NEW! 💎"; dark bg so neon gems pop; "AFK = FREE GEMS" tag.

---

## Concept 3 — Steal a Fish 🐠 Glow Aquarium Tycoon  *(score 7.7 · highest demand; ship idle-first, steal later)*
**Hook:** Grow a glowing deep-sea aquarium that mints pearls while you sleep — then dive into rival tanks and swipe their rarest catch.
**Core loop:** place bioluminescent creatures (passive pearls, offline via timestamp delta) → spend pearls to roll new creatures (procedural rarity tiers, gacha beat) → upgrade tank tier / unlock darker biomes → leaderboard + codes → **(Phase 2)** dive to rival tank, siphon one rare on contact, defend with guardians → the "they stole my RARE!" clip beat.
**Solo scope:** Ship the IDLE COLLECTOR first — pure DataStore + procedural rarity rolls, single-server, NO steal (steal/raid is multiplayer-heavy, the wrong solo-first bet). MVP ~2–4 wks: one tank/player, offline earnings, procedural creature generator, pearls + roll + tier upgrades + biomes, DataStore save + BindToClose, leaderboard + codes, fair cosmetic monetization (NO AI reels). Defer on-contact steal/raid + defense to a later update.
**Genre tag:** Simulator → Idle / Incremental tycoon (collect-and-steal).
**Paste-ready description:**
```
🐠 STEAL A FISH! Build a glowing deep-sea AQUARIUM TYCOON where bioluminescent fish earn you PEARLS on their own — even offline! 💎🌊

Collect rare fish, roll for legendary glow creatures & grow the richest tank on Roblox. The ultimate idle pet income sim + brainrot alternative — 100% original art, NO reels, all fun!

✨ FEATURES
🐟 Idle income — your fish earn pearls 24/7
💎 Roll rare & LEGENDARY glow creatures
🏆 Upgrade your tank & unlock deep-sea biomes
🌊 RAID rival tanks & steal their rarest catch (soon!)
🎁 Redeem codes for free pearls
🏅 Top the leaderboard for the rarest fish

"They stole my RARE?!" 😱 Defend your tank & flex your collection!

👍 LIKE + ⭐ FAVORITE + follow for update codes! 🐠
```
**Thumbnail:** split-screen on black water; LEFT huge neon aquarium overflowing with pearls + legendary anglerfish; RIGHT shocked avatar as a diver yanks a golden fish out (red "RARE!" arrow); "STEAL A FISH" top; bioluminescent glow.

---

## Concept 4 — DERELICT — Deep Space Escape Horror  *(score 7.3 · highest differentiation; needs co-op day one)*
**Hook:** 1–4 players wake on a dead starship that rebuilds itself every run — escape room by room before the thing in the dark reaches you.
**Core loop:** squad spawns in cryo bay of a procedurally-chained station → push room-to-room (keycard / reroute power / disarm hazard / force airlock) → one relentless entity hunts sound + light (kill flashlight, hold, throw flare, sprint) → downed w/ short revive window, wipe ends run → reach escape pod, bank salvage → spend salvage in lobby on permanent unlocks (gadgets, perks, skins, deeper sectors) → codes → requeue, everything rerolls.
**Solo scope:** Heaviest of the top 4 — co-op must be in from day one. MVP: 1 sector (8–12 modular room prefabs stitched by the maze generator), ONE entity with a readable state machine (patrol→investigate→chase→search→reset) + one signature scare (no full survival AI), 1–4 players in a single server (default/friends join), objectives (keycard→power→pod), salvage + DataStore meta-progression + lobby shop, codes, lobby hub. Post-launch: more sectors/entities/difficulties/seasonal codes.
**Genre tag:** Horror → Survival (co-op escape / roguelite); tag escape, co-op, multiplayer, space horror.
**Paste-ready description:**
```
👽 DERELICT — the #1 CO-OP HORROR escape game on Roblox! 🚀 Grab 1-4 friends and escape a deep-space station that REBUILDS itself every run… while one relentless entity hunts you room by room. 💀

Love DOORS-style games, procedural horror & multiplayer scary games? This is your next obsession — every run is different, every scream is real. 🔦

🩸 FEATURES:
🚪 Procedurally-generated station — no two runs alike
👾 One relentless entity that NEVER stops hunting
🤝 1-4 player co-op — revive your friends or die trying
🔓 Persistent unlocks: gadgets, perks & skins between runs
🎁 Redeem CODES for free salvage!

Can your squad reach the escape pod before it finds you? 🛸

❤️ LIKE + ⭐ FAVORITE to help us drop more sectors, entities & scares!
```
**Thumbnail:** red-emergency-lit corridor; 2–4 avatars sprinting at camera, panicked, flashlight beams; massive shadowed entity w/ glowing eyes + reaching claw behind; "CAN YOU ESCAPE?" + "1-4 PLAYERS" badge + DERELICT logo.

---

## Recommendation
- **Next fast-win build:** Concept 2 (**Grow a Crystal**) — highest score after the already-shipped +1 lane, opens a genuinely under-served cozy niche, reuses DataStore + procedural-gen + single-server exactly, near-zero art budget, and its offline-growth loop is the retention engine the charts reward.
- **Highest ceiling if willing to add multiplayer later:** Concept 3 (aquarium idle now, steal later).
- **Portfolio depth / craft play:** Concept 4 (horror) — but co-op is required day one, so it's the biggest lift of the top 4.
