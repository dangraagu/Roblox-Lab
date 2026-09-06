# Roblox Game Radar — 2026-09-06 (round 2)

Second on-demand scan (6 platform scouts -> rank -> concept briefs), run after **Anomaly** shipped.
**Excluded** all four built lanes (maze obby, +1-per-step obby, cozy idle-grow sim, anomaly/spot-the-difference service horror), so every opportunity below is a fresh genre.
Ranked by `demand*0.4 + buildability*0.35 + differentiation*0.25`. 11 agents, 0 errors.

## Signal summary

Five signals converge across all six scouts. (1) The satisfying task-completion cluster is the highest demand-per-unit-of-work lane on the platform: Clean all the leaves ~67M plays in a month at 54-67K CCU, Clean The Library 83,591 peak CCU / 70M visits with an independent rival (Librarian: Tidy Up) clearing 17.2M plays in the same month, Concrete Cleaning Sim 8.35M visits since April — four mid-size winners, no consolidator, and every one is state tables plus UI with no AI, combat or netcode. (2) The 2026 discovery algorithm now weights 24-48h session RETURN over CCU and session length (target 1.2+ sessions/user/day), which structurally favours sub-15-minute loops one person can build and punishes the long-session tycoons and survival games a studio builds. (3) The loudest unmet player demand is 2-player co-op PvE that is neither obby nor tycoon — asked three separate ways on Reddit in seven days with zero consensus answer — alongside asymmetric-information co-op (Defusal crossed 100M visits this week with no competing field) and an unanswered 'parallel play while on Discord' brief. (4) Aesthetic/style is the fastest-growing search bucket at 12% of ~50M daily searches (~6M queries/day) and is served at scale by exactly one game, Dress To Impress at 57.8K CCU, which is also the most-engaged Roblox subject on TikTok (3.6M). (5) Every scout warns the steal/brainrot lane is saturated, litigated (4+ lawsuits), press-hostile and now policy-constrained by the 26-29 Aug doomscroll-reward ban, while players open recommendation threads with anti-slop NOT-lists.

Two structural levers apply whichever lane wins, and both favour this dev specifically. Procedural generation is absent from the ENTIRE chore/sort/hidden-object cluster — every incumbent ships hand-authored fixed maps that are finished after one 100% run — so a reseeded layout is both an infinite content pipeline and a differentiator eyeball-cloners cannot reproduce. And the two cheapest known flywheels are a mystery/secret-ending wrapper gated behind 100% completion (the leaf game's actual viral hook, cost: a text file and one cutscene) and a disciplined monthly codes drop, which buys a permanent Dexerto/PCGamesN/Destructoid article cycle plus its 'ALL NEW CODES' video wave for one RemoteFunction. Speed is the real moat: Steal An Egg went launch-to-#1 in six weeks, Jump for Animals cleared 18M plays in three — a 1-2 week MVP is on the same clock as the winners. Ranked below by demand*0.4 + buildability*0.35 + differentiation*0.25.

## Ranked opportunities

| # | Genre | Score | D | B | Diff | Concept |
|---|---|:-:|:-:|:-:|:-:|---|
| 1 | Organizing / sort-and-restore job sim (single-player-first, co-op optional) | **8.75** | 9 | 9 | 8 | A procedurally restocked lost-property depot where every mislabeled item must be decoded to the right bin by a learnable tag system under a shift timer, with a hidden back-room story unlocked at 100% clearance. |
| 2 | Asymmetric-information co-op puzzle (2-player, timed) | **8.25** | 8 | 8 | 9 | One player crawls a flooding lighthouse machine room reading dials and valves while their partner topside holds a procedurally generated repair manual — neither can see the other's screen and the water never stops rising. |
| 3 | Multiplayer hidden-object search race (round-based, seeded) | **7.95** | 7 | 9 | 8 | A procedurally dressed hoarder estate where 8-12 players race the same item list, with a daily shared seed so every player's run is comparable on one leaderboard. |
| 4 | Judged creative round game (non-fashion, peer-voted) | **7.9** | 8 | 7 | 9 | A 60-second theme prompt, a free parts library, and a peer-voted reveal — but the medium is a miniature diorama shelf (a shrine, a bento box, a terrarium) instead of an outfit, with nothing thematic behind a paywall. |
| 5 | Plot tycoon with offline income (PvE risk, zero player theft) | **7.8** | 9 | 7 | 7 | A salvage-yard claim tycoon where the only enemy is your own greed: expeditions can lose the whole haul, the plot earns while you are logged off, and no other player can ever touch your stuff. |
| 6 | Procedural co-op escape-horror roguelite (environmental threat, no chasing AI) | **7.45** | 9 | 6 | 7 | A 3-player descent through a procedurally assembled flooded subway line where the threat is water, light and doors rather than a monster — every run reseeds and ends in 12-20 minutes. |

### Rationales + keywords

**Organizing / sort-and-restore job sim (single-player-first, co-op optional)** — score 8.75

This is the convergent 'satisfying task-completion' cluster every scout independently flagged, and it is the highest demand-per-unit-of-work lane on the board: Clean The Library peaked 83,591 CCU / 70M visits, its independent rival Librarian: Tidy Up cleared 17,241,862 plays in the SAME month (26-27 May launches), Clean all the leaves banked ~67M plays in a month at 54-67K CCU, and Concrete Cleaning Sim has 8.35M visits since April — four separate mid-size winners with no consolidator, which the buildability scout calls the clearest proof a second well-made entrant is not locked out. Technically it is a table lookup plus a proximity check: no AI, no combat, no physics, no server-authoritative anti-exploit surface — progression/upgrades/percent-complete is pure DataStore and the shelf layout plus spawn set is a config-driven procedural generator, i.e. the maze generator re-pointed. The two differentiators the incumbents all lack are exactly the dev's edge: every trending chore/sort game ships hand-authored fixed maps that are dead after one 100% run, so a PROCEDURALLY reseeded depot is infinitely replayable and cannot be eyeball-cloned; and the leaf game's actual viral hook was not the raking, it was the 100%-gated secret ending, which costs a text file and one scripted scene. Original domain (a lost-property depot with real internal coding rules) converts label-reading into a masterable system, which the buildability scout names the single highest-conviction gap on its list. Explicitly NOT the shipped anomaly lane: the verb is sort-and-decode, not spot-the-difference, there is no horror layer, and it is timed/active rather than observational — it reuses that service-sim architecture instead of repeating it. Also aligned with the 2026 algorithm shift that weights 24-48h return over CCU: an 8-minute shift with a daily reseeded depot is a native 1.2+ sessions/day shape.

*Keywords:* sorting game, tidy up, clean the library, organize simulator, lost and found roblox, job simulator, secret ending, co op sorting game

**Asymmetric-information co-op puzzle (2-player, timed)** — score 8.25

This targets the loudest unmet demand in the entire Reddit dataset, asked three separate ways inside seven days with no consensus answer: verbatim 'games that aren't either some ridiculous obby or another 2 player tycoon... We aren't really into PvP', plus 'recommendations for games for couples?' (12 pts) and 'LOVEEE co-op games because solo games are boring to me'. The Google scout independently found Defusal crossing 100 MILLION visits inside the 7-day window with essentially no competing field, and calls a Keep-Talking-shaped loop the best scope-to-signal ratio in its whole dataset. It also silently satisfies two other unanswered asks: the 'parallel play / talking on Discord' post (only 2 replies) — because the design MECHANICALLY forces talking rather than requiring voice chat — and the session-reset/private-server ask that got literally zero comments. Buildability is high and safe for a solo dev: no AI, no pathfinding, no combat, no physics, no persistence needed for v1 (round state only), and the puzzle modules plus the manual are a PROCEDURAL GENERATOR over a rules table — the dev's strongest existing muscle, and the thing that makes content cost near-zero forever. The only real cost is a clean two-screen UI. Differentiation is the highest available because the Roblox field is empty while proximity-voice small-group co-op is documented as the most YouTube-native configuration on the platform (raw footage is already the entertainment, no editing), and A24's Backrooms film plus Roblox's own Monster in the Mansion are actively pushing players toward small co-op sessions.

*Keywords:* co op games, 2 player games, defuse, escape room 2 player, games to play with friends, co op puzzle, bomb defusal roblox, couples games roblox

**Multiplayer hidden-object search race (round-based, seeded)** — score 7.95

Search For The Needle took 37,000 CCU from a 23 Aug 2026 launch — one of the two strongest new releases of the month — on a mechanic the Roblox scout describes as trivially cheap to author (place objects, gate a level), and it explicitly notes there is NO large multiplayer entrant on the platform despite 'find' sitting inside the 18% action-verb search bucket of Roblox's 50M daily searches. Buildability is near the ceiling for this dev: object scatter is procedural generation, the round is single-server logic, scoring/streaks/cosmetics are DataStore, and there is zero AI, combat or physics — the whole content pipeline is a spawn table, which is the 'cheap content unit' the buildability scout says a solo dev must have to sustain the now-mandatory weekly update cadence. The differentiator is the seed: every incumbent hidden-object game is a fixed hand-authored room that is finished forever once solved, whereas a per-round procedural dressing plus a DAILY SHARED SEED creates a comparable-run leaderboard, which is the strongest possible 24-hour return hook under the 2026 algorithm's return-rate weighting (target 1.2+ sessions/user/day). It is also clip-shaped in the way YouTube and TikTok reward — 'last item, four seconds left' is a complete 10-second Short — and the reveal moment is free to produce. Demand is scored honestly at 7: 37K CCU is real but an order of magnitude below the chore cluster, and the ceiling depends on the social layer nobody has proven yet.

*Keywords:* find the, hidden object, search for, seek and find, find the items, scavenger hunt roblox, race to find, daily challenge game

**Judged creative round game (non-fashion, peer-voted)** — score 7.9

This is the single largest raw arbitrage in the dataset: style/aesthetic terms (Y2K, cute, aesthetic, realistic) are 12% of ~50M daily on-platform searches — roughly 6M queries a day, and the FASTEST-GROWING bucket — served at scale by exactly one game, Dress To Impress at 57,870 CCU. DTI is simultaneously the most-engaged Roblox subject on TikTok (top #roblox video at 3.6M engagement) precisely because its structure is a complete narrative arc in one clip: prompt, panic, reveal, verdict. The TikTok scout's explicit recommendation is to take the STRUCTURE, not the dress-up, and point it at a non-fashion medium — which is what this is, so it inherits the search bucket without entering DTI's own lane. Buildability is 7 rather than 9 honestly: the code is easy (round timer, snapping placement, voting UI, DataStore unlocks) but the cost moves to art and curation of the parts library, which is the inverse of most Roblox competition and therefore the moat — the Roblox scout calls exactly this 'low technical difficulty, high art/curation difficulty... a defensible moat for whoever does the taste work.' Two cheap force-multipliers apply: Roblox is itself publishing a 2D/stylized pixel title (Caramel) this month, signalling the audience accepts a cheap stylized look over 3D fidelity; and Reddit's most specific anti-monetization brief ('nothing in a theme is behind a paywall... no rarity gambling spin wheel that costs 89 per spin') is a free positioning promise here — creative breadth free, cosmetics paid.

*Keywords:* build to impress, decorate, aesthetic games, cute games, design competition, y2k, roleplay build, vote runway

**Plot tycoon with offline income (PvE risk, zero player theft)** — score 7.8

Tycoon is now the #2 most-played category on Roblox with top titles above 100K CCU and ~38% seven-day retention on prestige designs, and offline income is documented as the single best 24-hour return hook on the platform — 'automation is the biggest reason a 2026 tycoon retains players past day three', which is a design lever, not a content-volume problem, and therefore ideal for one person. Jump for Animals proves the entry speed: 18,000,180+ plays and ~68K CCU roughly three weeks after a 12 Aug launch. The deliberate design decision here is to take the tycoon/offline-income half and DROP the theft half. That is where solo scope explodes (server-authoritative cross-plot ownership, anti-exploit validation, abuse handling — 'where the money-losing bugs live'), and it is also where the platform risk sits: Steal a Brainrot's developers have filed 4+ lawsuits against imitators since November, Steal An Egg was pulled and forced a platform policy change on 26-29 Aug barring doomscroll-reward games from the Kids/Select catalogs, and Reddit's dominant tone is anti-slop NOT-lists naming steal/brainrot clones first. Replacing theft with self-inflicted risk — expedition gambles, shaft flooding, over-extension decay — keeps the tension and the video hooks ('I lost everything on the last run' is a complete clip) while removing the entire netcode and moderation burden. Offline income is a DataStore timestamp-delta problem the dev already solves safely; buildability is 7 only because economy balancing and the upgrade ladder are genuine multi-week work, and this lane demands the monthly codes cadence (Dexerto/PCGamesN/Destructoid publish a fresh codes article for any game that ships them) as its acquisition engine.

*Keywords:* tycoon, offline income, idle tycoon, afk earnings, salvage tycoon, mining tycoon, plot tycoon, tycoon codes

**Procedural co-op escape-horror roguelite (environmental threat, no chasing AI)** — score 7.45

'Horror' is the single highest-volume search keyword on the entire platform across 50M daily searches, horror games average 47% higher CCU than the platform average at 3.2x baseline content-creator appeal, and there is a hard timing window: Halloween applies a 2.5-3.0x multiplier but October is the year's most saturated launch month, so RoLearn's explicit advice is to ship in LATE SEPTEMBER and enter October with an established rating — that window is open for about three more weeks and then closes for a year. Within horror the shape is settled: every top-10 horror game by average CCU is multiplayer (~8,500 avg CCU vs ~6,300 solo), 99 Nights in the Forest is still top-6 more than a year on, Roblox is first-party-seeding co-op horror (Monster in the Mansion, 8 players), and jumpscare horror has ~2% day-7 retention — it acquires and does not hold. The design choice that makes this solo-viable is cutting the pursuer: Reddit's horror asks explicitly ban Doors and 'Hold E simulator' horror and demand dread through wrongness, so making the threat ENVIRONMENTAL and scripted (rising water, failing light, door states) removes enemy AI, pathfinding and animation rigs — the exact systems the buildability scout says burn a solo fortnight each — while the procedurally assembled tunnel layout is the maze generator redeployed, giving replayability that hand-authored Doors clones cannot match. Buildability is still the lowest here at 6 (atmosphere, audio and lighting polish are real work, and 3-player state replication is non-trivial), and it is scored below the top five for that reason: take it only if the late-September date is actually hittable, otherwise the window argues for deferring rather than shipping thin.

*Keywords:* horror games, co op horror, scary games with friends, escape horror, survive the night, procedural horror, backrooms co op, 3 player horror

---

## Concept briefs (top 4)

## Lost & Found Depot 🧳 Sorting Simulator

**Hook:** Every item in the depot is mislabeled — crack the tag code, sort it into the right bin before your shift ends, and hit 100% to unlock what's behind the back-room door.

**Genre tag:** Primary: Simulation → Incremental Simulator (this is where the "simulator" grind + upgrade shape gets surfaced, and where the Clean/Tidy cluster's traffic sits). Strong alternate to A/B after launch: Party & Casual → Childhood Game, which the chore/tidy winners also index on and which skews younger and more mobile. Do not tag Puzzle — the tag system is a masterable system, not a puzzle-solver audience, and Puzzle discovery would misroute the traffic you actually want.

**Core loop:** One shift = 8 minutes. (1) A returns cart dumps 30-60 procedurally chosen lost items onto the intake table. (2) Each item carries a 3-part tag — CATEGORY letter / CONDITION number / ROUTE colour (e.g. "K-3-Amber") — and the tag deliberately contradicts what the item looks like: the umbrella is tagged Electronics because it's a lightning-rod novelty, the teddy bear is tagged Hazardous because it's damp. The player must learn the depot's real coding rules, not eyeball the object. (3) Grab (ProximityPrompt) up to your carry limit, walk it to a bin, deposit. Correct = cash + combo multiplier + a satisfying stamp/chime/percent tick. Wrong = the item bounces to the MISFILE shelf, costs 5 seconds and breaks the combo. (4) The wall board shows live CLEARED %. Hit 100% before the timer for a Perfect Shift bonus; run out of time and the leftovers roll into next shift as backlog. (5) Cash buys upgrades: handheld tag scanner (reveals one code part), bigger cart, faster grab, extra shift minutes, and new wings (Umbrella Aisle → Electronics Cage → Aquatics → Cursed Items), each wing adding new tag rules to master. (6) Shift ends, depot RESEEDS — new layout, new item set, new labels — so it never becomes a memorized map. Lifetime clearance % is saved; at 100% lifetime the back-room key drops and a one-time scripted scene plays. Optional: friends join the same depot and split the floor.

**Why it trends:** It lands in the exact cluster that four separate mid-size winners just proved is under-served with no consolidator: Clean The Library peaked 83,591 CCU / 70M visits, its rival Librarian: Tidy Up cleared 17.2M plays in the same month from a launch days apart, Clean all the leaves banked ~67M plays in a month at 54-67K CCU, and Concrete Cleaning Sim has 8.35M visits since April. Four winners, none of them dominant — a well-made second entrant is not locked out. It then attacks the two things every incumbent is weak on. First, replay: all of them ship hand-authored fixed maps that are dead after one 100% run, so a procedurally reseeded depot is infinitely replayable and, critically, cannot be eyeball-cloned by the copy farms that strip-mine this genre. Second, the actual viral engine: the leaf game's hook was never the raking, it was the 100%-gated secret ending — a text file and one scripted scene that produced the "I FOUND THE SECRET" video wave. Building that in from day one instead of bolting it on later means the shorts/TikTok loop starts at launch. The tag system is the retention layer nobody else has: chore games are pure motion, this one is a masterable system, so returning players get faster in a way they can feel and brag about. And the shape fits the 2026 algorithm shift that weights 24-48h return over raw CCU — an 8-minute shift plus a daily reseeded depot is natively 1.2+ sessions/day, not a one-and-done.

**Audience:** Core: 8-15 year-old Roblox players who already play the chore/tidy/cleaning cluster (Clean The Library, Librarian: Tidy Up, Clean all the leaves, cleaning sims) — mobile-first, short session, high sensitivity to satisfying feedback (chimes, percent bars, combo pops). Secondary and the growth engine: the secret-ending/lore hunters and small YouTube/TikTok creators who farm "100% clearance = HIDDEN ENDING" content in exactly this genre. Third: friend duos who want a low-pressure co-op job to talk over — no combat, no skill gate, no way to grief each other. Also picks up the "oddly satisfying / organizing" adult-adjacent audience that made real-life sorting content huge, which is why the domain (a lost-property depot with real internal coding rules) matters — it reads as a real job, not a kiddie chore.

**Solo build scope:** MVP is one room, one shift type, one ending — ships in roughly 2-3 focused weekends by re-pointing existing strengths. (1) Depot generator: the maze generator, re-pointed. Instead of walls, place a grid of shelf rows + 6 bin stations from a seeded RNG; the seed is date+shift so every player's daily depot matches and can be talked about. Config-driven, one ModuleScript. (2) Tag system: a single ItemRules ModuleScript table — item name → {category, condition, route} plus a small set of override rules that generate the mislabels. Whole "game" is a table lookup plus a proximity check; no AI, no combat, no physics, no server-authoritative anti-exploit surface (worst case is a player self-reporting a sort, which costs nothing real). (3) Items: 35-45 meshes/part assemblies is plenty — umbrella, phone, teddy, keys, lunchbox, skateboard, water bottle, etc. Reskin/recolor variants multiply the set for free. Billboard GUI tag above each item, no decal work needed. (4) Interaction: ProximityPrompt pickup, weld to character, walk to bin, TouchEnded → validate → play stamp sound + particle + percent tick. That is the whole verb. (5) Persistence: DataStore for cash, owned upgrades, wings unlocked, lifetime clearance %, perfect-shift count. Single-server, no cross-server messaging needed in MVP. (6) Shift loop: one 8-minute server timer, intermission, reseed. (7) Progression MVP: 4 upgrades and 1 extra wing — hold the other wings back as the week-2 and week-4 updates that re-trigger the algorithm. (8) Secret ending: literally a text file and one scripted camera/lighting scene behind a locked back-room door at 100% lifetime clearance. Cheapest highest-leverage asset in the build. Deliberately CUT from MVP: co-op sync polish (ship solo-first, co-op is just "same server, shared percent"), pets, gamepasses beyond a 2x-cash and a scanner, leaderboards beyond a simple top-clearance board, any cutscene beyond the one ending, any horror layer.

**Thumbnail:** Split-frame, high-contrast, readable at 256px. LEFT: a chaotic mountain of lost items (umbrellas, phones, teddy bears, backpacks) spilling across the floor with bright red MISLABELED tags flapping off them, a shocked Roblox worker avatar in a hi-vis vest clutching an over-stacked crate. RIGHT: the same aisle spotless, six colour-coded bins glowing, a huge green "100%" stamp slammed across it. Down the centre seam, a dark cracked-open back-room door with a single beam of light and a question mark, plus small yellow text "WHAT'S IN THERE?". Top banner in fat white outlined text: "SORT IT ALL. 100% = SECRET." Palette: warehouse amber/grey against one saturated green success accent, so the before/after reads instantly in the feed. Companion icon: a single luggage tag with a glowing question mark on it.

**Paste-ready Roblox description:**

> 🧳 Lost & Found Depot — the sorting game where you tidy up, organize and clear an endless lost property warehouse!
> 
> Every item is MISLABELED. Read the tag, crack the depot's secret coding system, and sort it into the right bin before the shift timer hits zero. Clear 100%... and the back room unlocks. 🔦
> 
> 🏷️ Learn the real tag system — letter, number, colour
> ♻️ A NEW procedurally generated depot every single shift
> ⏱️ Fast 8-minute shifts, perfect combos, huge payouts
> 💰 Upgrade your scanner, cart and carry limit
> 🚪 SECRET ENDING hidden behind 100% clearance
> 👥 Sort solo or bring friends into your depot
> 
> Tags: sorting game, tidy up, clean the library, organize simulator, lost and found, job simulator, cleaning simulator, sort it out, secret ending, co op sorting game
> 
> ⭐ LIKE + FAVORITE to help the depot grow — new wings and new secrets drop every week!

## Rising Tide 🌊 2 Player Co-Op Escape Room

**Hook:** One of you is drowning in the machine room; the other one is holding the only manual — and you can't see each other's screen.

**Genre tag:** Puzzle → Escape Room (Roblox genre "Puzzle", subgenre "Escape Room"). Secondary discovery tags/keywords to set: co op, 2 player, escape room, defuse, games to play with friends, co op puzzle, couples, teamwork. Maturity: Minimal — no blood, no combat, no romance; the drowning fail-state is a fade-to-black with no body, which keeps it Minimal and keeps the widest region reach.

**Core loop:** A 6-minute round for a pair (scales to 4). Roles are assigned in the lobby: DIVER goes down the ladder into the lighthouse machine room; KEEPER stays in the lamp room topside. A round seed procedurally generates 5 repair modules (Valve Bank, Dial Gauge, Fuse Board, Breaker Sequence, Signal Lamps, Pressure Wheel) AND the matching repair manual from the same rules table — the manual is a mathematical inverse of the answer key, so they can never disagree, and it is different every round so nobody can memorize it. Only the Diver can see the hardware; only the Keeper's client renders the manual. The Diver describes ("three brass valves, middle one hissing, tag says H-7"), the Keeper reads the branching rule ("if the tag letter is H and any valve is hissing, close them RIGHT to LEFT"), the Diver acts. A correct fix kicks the pump on: water drops ~8 studs and a stress meter cools. A wrong fix = a strike: water surges, lights flicker, the module re-rolls. Water rises continuously the whole time. Three strikes or full flood = you both drown, together. Fix all 5 and the lamp relights, both escape, and the next Depth unlocks (deeper = more modules, faster tide, dirtier manual pages: water-stained lines, torn corners, a page that must be read upside down). Roles auto-swap next round, so both players learn both halves. Loop closes on "one more" pressure: the failure is always a communication failure, never a skill gap, so the rematch button is irresistible.

**Why it trends:** It answers the loudest unmet ask in the dataset in its own words: "games that aren't either some ridiculous obby or another 2 player tycoon... We aren't really into PvP" — this is co-op, non-PvP, and the tension comes from the water and the clock, never from each other. It also lands "recommendations for games for couples?" and "LOVEEE co-op games because solo games are boring." The Defusal signal is the proof of demand: 100M+ visits inside a 7-day window on a Keep-Talking-shaped loop, with essentially no competing field on Roblox — the format is validated and the shelf is empty, which is the rarest combination available. The design mechanically forces talking instead of requiring voice chat, which quietly solves the "parallel play / talking on Discord" post that got only 2 replies: text chat, Discord, or two phones on one couch all work identically, and it dodges Roblox's voice-chat age gate that kills most "talk to your friend" games. Private servers plus a one-click rematch answer the session-reset ask that got literally zero comments. And it is YouTube/TikTok-native in the way proximity-voice co-op already is: raw footage of two people screaming valve numbers at each other IS the entertainment — no editing, no commentary needed — so creators do the marketing for free. Tailwind: A24's Backrooms film and Roblox's own Monster in the Mansion are actively pushing the algorithm toward small, tense, session-based co-op right now. Search-wise it sits on high-volume evergreen queries ("2 player games", "games to play with friends", "co op games") that no strong Roblox result currently owns.

**Audience:** Primary: 13-22 friend pairs and couples who play together on two devices or one couch — the exact people writing the "co-op, not PvP, not another tycoon" posts. Secondary: Discord squads doing parallel play who want a reason to be in voice; short-form creators and small streamers hunting a duo format where raw capture is already funny; Keep Talking and Nobody Explodes fans who don't own a PC or VR headset; siblings and parent-kid pairs (no combat, no gore, no chat requirement, Minimal maturity-safe); and burned-out obby/tycoon players looking for something to think about. Cross-platform matters: mobile-first players can be the Keeper (pure reading + tapping) while the PC player dives, so a phone-only friend is never the weak link.

**Solo build scope:** MVP is one place, one server, zero teleports — reusing the lobby-hub + per-group instance architecture already proven in labyrint-spill (instances offset thousands of studs apart, teardown on solve/death/leave). No AI, no pathfinding, no combat, no physics, no persistence needed to be fun.

The whole game is one procedural generator over a rules table — the strongest existing muscle. `ModuleRules.luau` is a pure Luau table: each module type declares its state space and its rule tree. `RoundGen.luau` takes a seed (`Random.new(RoundSeed * 1000003 + depth * 2654435761)`, same deterministic pattern as the maze) and emits `{moduleStates, answerKey, manualPages}` from that one table, so the manual is generated FROM the answer key and cannot drift out of sync. That is the entire content engine: new content forever = new rows in a table, near-zero cost.

Build order (two focused weekends):
- Weekend 1 — pure logic, no engine needed. ModuleRules for 6 module types, RoundGen, and the Luau-CLI test suite: for 10,000 seeds, assert that following the generated manual yields exactly the generated answer key, that no two modules in a round collide, and that no rule branch is unreachable. Include a control mutation the suite MUST notice. This is all testable with the scratchpad luau.exe before a single Part exists.
- Weekend 2 — the two screens. One lighthouse interior (~8 parts of geometry, reusable), 6 module models built from Parts + SurfaceGui + ClickDetector, water = a single tweened Part with a height check (no physics), Keeper manual = a ScreenGui page-turner rendered client-side from a server-sent page payload that is NEVER replicated to the Diver, Diver HUD = timer + strikes + water depth. Lobby pairing with a Solo-Practice door (both roles, one screen) so a single player can still learn it.

v1 persistence is deliberately thin: round state only, plus a small DataStore for rank / deepest Depth / lighthouses relit, using the existing `canSave` load-success sentinel so a DataStore failure never wipes real data. Private server + one-click rematch ship in v1 (they are the retention lever and cost almost nothing).

Explicit cut list for v1: voice chat, cosmetics/shop, more than 6 module types, Robux products, animated water shaders, any monster. Ship, then add module types weekly — each new one is a table row plus one model, which is exactly the kind of content that keeps a page alive without keeping the dev up.

Known risks to plan for: (1) anti-peek is the whole game — the manual must be assembled server-side and sent only to the Keeper's client, never parented anywhere the Diver's client can read; (2) mobile Keeper UI needs real text scaling (TextScaled + MaxSize, same treatment as the maze HUD); (3) runtime-untested is the standing weakness on this box — budget one real Studio play-through with a second person before publishing, because a two-screen game cannot be validated by unit tests alone.

**Thumbnail:** Hard vertical split with a jagged crack down the middle, like the screen itself tore in half. LEFT (cold blue-green, underlit): the Diver chest-deep in black water in a rusted machine room, torch beam catching a glowing red valve wheel, mouth open mid-shout, one hand reaching. RIGHT (warm gold lamp light): the Keeper up top, giant open manual filling half the frame with visibly fake diagram scribbles and one circled rule, finger jabbing the page, also mid-shout. Neither avatar looks at the other — they face THEIR OWN panel, which sells the premise instantly. Big bold yellow text across the crack: "YOU CAN'T SEE THEIR SCREEN". Red digital timer 00:47 in the top-center with a water line visibly above the Diver's shoulders. The blue-vs-gold split and the two open mouths read at thumbnail size on a phone; the timer supplies the urgency; the text supplies the entire pitch in five words. Icon variant: just the two shouting faces either side of the crack, no text.

**Paste-ready Roblox description:**

> 🌊 2 PLAYER CO-OP ESCAPE — one reads the manual, one fixes the machine!
> 
> The lighthouse is flooding and you CAN'T see each other's screen. One of you climbs into the machine room full of valves, dials and fuse boards. The other holds the repair manual topside. Talk fast — the water never stops rising. ⏱️
> 
> 🔧 Co-op puzzle for 2 players (up to 4)
> 📖 A NEW procedurally generated manual EVERY round — nobody can memorize it
> 🌊 Rising water + 3 strikes and you both drown
> 🔁 Swap roles each round: Diver ↔ Keeper
> 🏆 20 depths, ranks and a global leaderboard
> 🎧 No voice chat needed — chat, Discord or same couch works
> 🔒 Private servers for just you and your friends
> 
> Made for couples, best friends, siblings and Discord squads. If you love defusal, escape room and 2 player games to play with friends — this is your new one.
> 
> ❤️ LIKE + ⭐ FAVORITE so we keep building it!

## 🔍 Find The Items! Hoarder House Race

**Hook:** Every player on Roblox gets the SAME messy house and the SAME item list for 24 hours — 12 racers, one timer, one daily leaderboard.

**Genre tag:** Primary: Puzzle → Scavenger Hunt (exact-match subgenre, very low competition, lands the game directly in front of "find the / seek and find" searchers). Alternate if the sort favors social traffic: Party & Casual → Party Game. Do NOT tag Adventure — it buries the game under a saturated, high-CCU shelf.

**Core loop:** 60-second lobby fills to 8-12 players → server rolls the round seed and procedurally re-dresses one hoarder mansion (attic, basement, garage, 6 cluttered rooms) with 1000+ props from a spawn table → every player receives the IDENTICAL 20-item checklist on a HUD card → 5-minute race: sprint, scan piles, open closets, tap items to bank them (server-validated) → live ticker shows rivals' progress ("Mia found 14/20"), which drives the panic → first to 20 (or most found at zero) wins → 20-second results board: rank, split time, personal best, streak +1, coins → coins buy flashlights, magnifiers, trails, hint pings → the DAILY SEED round (same house + list worldwide, one attempt per day) sits at the top of the lobby with a countdown, giving the player a reason to return tomorrow → repeat.

**Why it trends:** It rides a proven, unowned wave. Search For The Needle hit 37,000 CCU from a 23 Aug 2026 cold launch, proving "find" demand is live right now — and "find" sits inside the 18% action-verb bucket of Roblox's ~50M daily searches, so "Find The Items" is a query players already type. Critically, every incumbent is single-player and hand-authored: solve the room once and the game is over forever. There is NO large multiplayer entrant. Three trend levers stack on that gap: (1) MULTIPLAYER converts a quiet puzzle into a social race, which is what pushes session length and friend-invite virality; (2) the DAILY SHARED SEED is the Wordle mechanic — a comparable run everyone can argue about — which is the strongest possible 24-hour return hook under the 2026 algorithm's return-rate weighting (target 1.2+ sessions/user/day, the single metric that decides sort placement); (3) it is natively clip-shaped — "last item, four seconds left" is a finished 10-second Short, and the reveal costs nothing to produce, so YouTube/TikTok creators farm it for free. Procedural dressing also kills the content treadmill: the game is never "solved", so it survives past week two, and a weekly update is just new props in a spawn table.

**Audience:** Core: 8-14 casual Roblox players who already search "find the" and play obby/collect-a-thon games — low skill floor, no combat, no gear check, instantly readable. Secondary: 13-17 leaderboard chasers and speedrunners who want a fair, comparable daily run (the Wordle/daily-challenge crowd) and will fight over a global time. Tertiary: sibling pairs and 3-5 friend parties looking for a "we can all join one server right now" game, plus small Shorts/TikTok creators who need a clip-per-round format. Skews slightly female relative to the combat-heavy Roblox average, which is an underserved and cheap-to-acquire segment.

**Solo build scope:** MVP shippable in ~2 weeks solo, reusing existing procedural-gen + DataStore + single-server strengths; zero AI, zero combat, zero physics sim.
1) MAP (2 days): ONE hand-built house shell, ~8 rooms, and ~250 named SpawnPoint attachments (shelves, floor piles, under beds, cupboards). Built once, reused forever.
2) SEEDED SCATTER (2 days): `Random.new(seed)` shuffles a spawn table of ~120 props into the 250 anchor points, then picks 20 as the round's target list. Deterministic = same seed reproduces the same house on every server. This is the whole content pipeline: adding props = adding content.
3) ROUND LOOP (2 days): one ModuleScript state machine — Intermission(60s) → Dress → Race(300s) → Results(20s). Single-server, no cross-server logic, no matchmaking service.
4) COLLECT (1 day): ClickDetector/ProximityPrompt → RemoteEvent → server checks the item is on YOUR list and unclaimed → banks it. Never trust the client.
5) UI (2 days): checklist card, timer, rival progress ticker, results board. Roblox default fonts; no custom art needed for v1.
6) PERSISTENCE (2 days): ProfileStore-style DataStore for wins/best time/streak/coins; ONE OrderedDataStore per date key `daily_YYYYMMDD` holding ms-times for the daily leaderboard, plus an all-time board.
7) DAILY SEED (half day): `seed = math.floor(os.time()/86400)` — no backend, no scheduler, every server derives it independently.
8) MONETIZATION (1 day): 2 gamepasses (Extra Hint x3/round, VIP glow trail) + 1 dev product (skip-the-wait instant round).
CUT FROM V1: pets, multiple houses, custom lighting/horror mode, cross-server parties, trading, avatar shop, mobile-specific UI polish. Week 2+ updates = new prop packs, a second house wing, seasonal item lists — all spawn-table edits, no new systems.

**Thumbnail:** Split-frame, high contrast, readable at 150px wide. LEFT 70%: a first-person-ish view into an absurdly cluttered room — junk stacked to the ceiling — with ONE item (a glowing rubber duck) circled by a fat yellow spotlight ring, and a giant red arrow pointing at it. RIGHT 30%: a Roblox avatar mid-sprint, eyes wide, holding a magnifying glass, mouth open in panic. Overlaid top-left: a red timer reading "0:04" with a pulse glow. Overlaid bottom: chunky yellow outlined text "19/20". Palette: warm amber clutter, one saturated red timer, one yellow highlight — nothing else competes. Variant B for A/B testing: same room, but the checklist HUD shows 19 green ticks and one blinking red "???", with the caption "CAN YOU FIND IT?" — invites the click before the player even opens the page.

**Paste-ready Roblox description:**

> 🔍 FIND THE ITEMS in the messiest hoarder house on Roblox! Hidden object search race, 12 players, ONE timer. Find them all first and WIN.
> 
> 🏠 NEVER THE SAME HOUSE - every round re-scatters 1000+ props, so no room is ever "solved"
> 📅 DAILY SEED - the whole game gets the SAME house + SAME item list for 24 hours. Beat your friends' time!
> 🏆 DAILY LEADERBOARD - fastest finder in the world gets crowned every day
> 🔥 STREAKS + REWARDS - play daily to unlock skins, pets, flashlights + hint boosts
> 👀 Clutter, closets, attics, basements - the last item is ALWAYS the hardest
> 
> Can you find every hidden item before the clock hits zero?
> 
> 👍 LIKE + ⭐ FAVORITE for new rooms every week!
> 
> find the items, hidden object, seek and find, scavenger hunt, search for, hide and seek, daily challenge

## Shelfie 🧸 Build To Impress

**Hook:** One theme, 60 seconds, one tiny shelf — fill it, light it, and let the whole room vote.

**Genre tag:** Primary: Party & Casual → Party/Minigame (round-based, judged, drop-in social loop — this is what the experience actually is and it matches how the algorithm serves short-session competitive rounds). Secondary tag to A/B against it: Roleplay & Avatar Sim → Dress Up, which is Dress To Impress's own shelf — worth testing for 2 weeks because it drops you directly in front of the 6M/day aesthetic-search audience; keep whichever produces better CCU-per-impression. Store keywords to attach regardless of genre: build to impress, decorate, aesthetic, cute, y2k, design competition, roleplay build, vote runway.

**Core loop:** A ~3.5 minute round, 8-12 players per server, looping forever:
1) THEME DROP (5s) — a prompt card flips: "Rainy Sunday", "Y2K Bedroom Shelf", "Bento for a Ghost", "Haunted Terrarium", "Grandma's Kitchen Window". 60 hand-written prompts, weighted shuffle, no repeats in a session.
2) BUILD (60s) — each player is teleported to their own private shelf pod. A searchable parts drawer (furniture, food, plants, candles, plushies, trinkets, posters, string lights, glass domes) snaps onto a 3-tier shelf grid. Recolor from a 12-swatch palette, scale in 3 steps, rotate in 15° increments, drop 2 lights and a backdrop sticker. Everything is free. A live "clutter meter" nudges players to fill the shelf.
3) REVEAL RUNWAY (8s each) — pods rotate into a spotlit gallery, camera dollies down the shelf while music plays. Every shelf gets its own beat.
4) VOTE — 1-5 stars, no self-voting, plus one single-use "Best Detail" token each player throws at the shelf with the best tiny idea. Score = mean stars + detail-token bonus.
5) RESULTS + KEEP — podium, Shelf Points payout, win-streak multiplier. Top-3 shelves auto-save to your personal Museum room, which other players can walk through between rounds. Photo Mode (freeze camera, frame, filter, screenshot) unlocks during reveal and results — the clip export is the growth engine.

**Why it trends:** 1) Search arbitrage, not competition. Style/aesthetic terms (Y2K, cute, aesthetic, realistic) are ~12% of ~50M daily on-platform searches — ~6M queries/day, the fastest-growing bucket — and are effectively served by ONE game. "Build To Impress", "decorate", "aesthetic games" and "cute games" are near-empty title space; this game inherits that traffic without competing head-on in Dress To Impress's dress-up lane.
2) It steals the STRUCTURE that made DTI the #1 Roblox subject on TikTok (top clip: 3.6M engagement), not the theme: prompt → panic → reveal → verdict is a complete narrative arc inside one 30-second vertical clip. Every round produces a shareable clip with a built-in punchline (the 5-star shelf next to the 1-star shelf). Photo Mode ships that for free.
3) The moat is inverted. The code is trivial (timer, snap placement, vote UI, DataStore); the cost is art and taste — parts-library curation — which is exactly where 99% of Roblox competitors are weakest and where a lead compounds. Weekly free theme drops make the moat widen every week.
4) Free positioning promise. The loudest anti-monetization complaint in the category is paywalled themes and rarity spin-wheels. "Nothing in a theme is behind a paywall. No spin wheels. Cosmetics only." is a headline, a pinned comment, a TikTok hook, and a differentiator that costs nothing to keep.
5) Platform tailwind: Roblox itself is shipping a 2D/stylized title this month — the audience has already accepted cheap stylized looks over 3D fidelity, so a solo dev's art budget is survivable.
6) Voting makes retention free: you cannot leave mid-round without losing your score, and the Museum gives a reason to log back in and see who starred your shelf.

**Audience:** Core: 9-16, skewing girls 10-15 — the cozy/aesthetic/kawaii crowd already playing Dress To Impress, Royale High and Adopt Me who want to be judged on TASTE, not on an avatar. Second core: the deco/builder audience from Bloxburg, Livetopia and Brookhaven house-decorating who love arranging and hate scripting. Third: TikTok "cozy gamer" / shelf-decor / bento / crystal-shrine aesthetic viewers, who convert at very high rates because the clip literally shows the whole game. Secondary: boys and older teens who bounce off dress-up entirely but will happily build a haunted terrarium or a gaming-desk setup — the non-fashion medium widens the funnel DTI can't reach.

**Solo build scope:** MVP shippable in ~2 focused weeks solo; alpha in 1.
ARCHITECTURE (all single-server, no matchmaking, no cross-server anything):
- One lobby place. 12 shelf pods placed procedurally in a ring at runtime from a single pod model + CFrame math — one model, zero level design. Pod ownership assigned on join, released on leave.
- Round state machine: ONE ModuleScript (THEME → BUILD → REVEAL → VOTE → RESULTS) driven by a server tick, with RemoteEvents fanning phase + timer to clients. ~300 lines.
- Placement: raycast to the shelf surface, snap to a 0.25-stud grid across 3 tiers, 15° rotation steps. Every placed part is Anchored, CanCollide false, CanQuery false — no physics, no constraints, no jitter, no exploit surface for falling props. Client previews with a ghost part; the server re-validates the grid cell, part ID, and per-shelf part cap (60) before spawning. Server-authoritative by construction.
- Shelf serialization: a shelf is a flat array of {id, x, y, tier, rot, color, scale} — ~15 bytes per part, ~1KB per shelf. That single format gives you DataStore saves, the Museum, replay/rebuild, moderation review, and future cross-server showcases for free. Use it from day one.
- Voting: server tallies, self-vote blocked by UserId, one Best Detail token per player per round, results computed server-side and broadcast.
- Persistence: ProfileService-style session-locked DataStore holding Shelf Points, 3 Museum slots, streak, and owned cosmetics. Nothing else.
ART SCOPE (the real cost — budget 60% of your time here):
- 120-150 parts at launch, mostly simple meshes and primitives, deliberately stylized/chunky so quality is achievable. A 12-swatch recolor palette + 3 scale steps turns 130 parts into thousands of distinct looks — procedural variety instead of art volume.
- 20 backdrop stickers (decals) and 6 shelf frames. Lighting is 2 PointLights + one Attachment sparkle emitter, reused everywhere.
- 60 theme prompts in a table. Text is free content; write 60, then 10 more every week.
MONETIZATION (build last, ~1 day): shelf frames, room wallpapers, mascot avatars, camera filters/frames, extra Museum slots, an emote pack, and a "double Shelf Points" gamepass. Every theme-relevant PART stays free forever — that promise is the marketing.
EXPLICIT CUT LIST FOR v1: no cross-server leaderboards, no trading, no friend parties, no custom themes, no UGC uploads, no mobile-specific editor rewrite (design the drawer touch-first from the start instead), no daily quests. Ship the loop, the library, and Photo Mode.

**Thumbnail:** Main (16:9): three spotlit shelves in a dark gallery, shot slightly low so they feel like museum pieces. Left shelf is a gorgeous pastel Y2K shrine with a glowing ⭐⭐⭐⭐⭐ overlay; right shelf is two sad blocks and a candle with a red ⭐ 1.0 overlay; center shelf is mid-build with a "0:07" timer burning red above it. Bottom-left: a shocked Roblox avatar face (hands on cheeks) reacting. Top text in fat outlined type: "60 SECONDS TO BUILD" with "THEY VOTE 👀" underneath in a smaller pink strip. High-saturation pink/teal on near-black so it pops against the beige of the Roblox home feed.
Alt A/B test: extreme close-up of ONE perfect miniature shelf (fairy lights, tiny ramen bowl, plushie, glass dome) filling the whole frame with a single word — "SHELFIE" — and five stars. Cozy-aesthetic audiences click the beautiful object; the reaction-face version clicks better with the general feed. Run both.
Vertical crop (9:16) for TikTok: same center shelf + timer, since the clip loop is prompt → panic → reveal → verdict.

**Paste-ready Roblox description:**

> 🧸 BUILD TO IMPRESS — decorate a tiny shelf, then get voted on the runway ✨
> 
> Aesthetic games + design competition in one! You get a THEME, 60 SECONDS, and the WHOLE parts library free. Cute, cottagecore, Y2K, goth, kawaii, cozy — build a shrine, a bento box, a terrarium, a dream bedroom shelf. Then everyone votes ⭐
> 
> 🕯️ 60-second themed build rounds
> 🎀 1,000+ FREE parts — nothing thematic is paywalled
> ⭐ Peer-voted reveal + Best Detail award
> 📸 Photo Mode for your TikToks
> 🏆 Save your best builds to your own Museum
> 🌸 New themes every week, always free
> 
> No spin wheels. No rarity gambling. Cosmetics only.
> 
> ❤️ LIKE + ⭐ FAVORITE to unlock themes faster!
> 
> decorate • aesthetic • cute games • y2k • design competition • roleplay build • vote runway

---

*Generated by the `roblox-game-radar` workflow (scouts: Roblox charts, Reddit, Google, TikTok, YouTube, buildability).*
