# What checking the store descriptions against the source turned up

Four writers drafted a description each from the game's own code, then a reviewer opened the
files and tried to break every claim. Every one of the four came back REWRITE. The drafts are
kept here because the reviewer's findings are worth more than the copy: several are defects in
the games, not defects in the writing.

The drafts below are NOT what shipped. They lean hard into confession - "nobody has played it",
"I have never tested a rejoin", "there is no cavern" - which is the right voice for a
dev-feedback subreddit and the wrong voice for a store page a player is deciding on. What
shipped keeps the specifics and the first person and drops the self-harm. The defects get
fixed instead of advertised.


## Labyrinth Mariozo

Proposed title: `[🔥] Labyrinth Mariozo - Maze Obby`

### Claims the code does not support (4)

**Every level is generated from a single world seed, so level 40 is the exact same maze for everyone, forever**

Determinism is real, the word "forever" is not. CONFIG.WorldSeed is a single editable literal at D:/Claude/Roblox/labyrint-spill/src/server/MazeGame.server.luau:35 and the comment directly above it tells you to change the number to redraw every level ("Endre tallet for aa trekke om alle nivaaene"). Nothing pins it: there is no test asserting the seed value, unlike LightingPresets.MAZE which IS pinned by tests/lightingpresets.spec.luau. Any future edit silently invalidates every record and medal time on the board, so the code cannot promise "forever".

**Touch the green EXIT and the same maze rebuilds one level harder with you still in it**

It is not the same maze. advanceInstance at MazeGame.server.luau:2388 does inst.level += 1 then buildInstance(inst), and buildInstance seeds a brand new maze from Random.new(CONFIG.WorldSeed * 1000003 + inst.level * 2654435761) at :1817, with size = clamp(6 + floor((L-1)/10), 6, 30). The player stays in and the clock resets (startClock[p] = os.clock()), but the layout is the next level's, not the current one's, which also contradicts the copy's own second sentence. "One level harder" is only strictly true of monster speed (+0.02/level); size steps every 10 levels, traps every 16 (MaxTraps 12), monsters every 25 (MaxMonsters 10).

**Grab coins and gems, 3 on level 1 and 90 on a full 30x30**

Those two numbers are coins only. MazeGen.luau:42 gives coins = max(MinCoins 3, floor(cells * 0.10)), so 6x6 = 36 cells -> 3 and 30x30 = 900 -> 90. Gems are a different formula on line 43: StartGems + floor(L / GemsPerLevels) = 3 + floor(L/125), which is 3 on level 1 and 4 on a 30x30 maze (size 30 first appears at level 241), topping out at 7 by level 500. Bolted onto "coins and gems", the 90 reads as both and overstates gems by roughly 20x.

**Tags: Parkour, Platformer**

There is no jumping mechanic anywhere in src/. Nothing sets JumpPower or JumpHeight in the server or any client script; the only movement stat written is hum.WalkSpeed = CONFIG.PlayerWalkSpeed + bonus at MazeGame.server.luau:1486. Walls are WallHeight 24 and the trap notes state a jump reaches about 6.4 studs, so nothing can be jumped over or onto. It is a walk-only maze, and those two tags describe content that is not in the build. Drop them; Maze, Obby, Escape, Speedrun, Survival, Multiplayer and Singleplayer all hold up.

### Where the first draft read as machine-written (6)

- 🔦 Welcome to Labyrinth Mariozo 🔦
  - The store-page greeting that opens half the AI descriptions on Roblox, and it spends the single most valuable line on the page repeating the title that is already printed directly above it. Zero information.
- How to Play:
  - A section heading inside a page this short, and it is not even accurate: only three of the six bullets under it are instructions, the rest are features. A heading here is filing-cabinet instinct, not writing.
- 🚪 Pick a door / 🪙 Grab coins / 🔥 Time the lava / 👹 Outrun the monsters / 🟦 Hit a coloured button / 🏁 Touch the green EXIT
  - Six bullets in a row, every one an emoji plus an imperative verb, every one between 9 and 16 words. Uniform grammar at uniform length is the loudest rhythm tell in the whole post, and it flattens the lava into the same weight as the buttons even though the lava is the mechanic the dev actually rebuilt the game around.
- 💻 Supports Desktop, Mobile and Tablet players
  - Spec-sheet register dropped into a page otherwise written in first person. "Supports X, Y and Z" is a compatibility matrix, not something a person says, and it tells a phone player nothing about whether the game is actually playable on a phone.
- 🛠️ Built by an uncle and his nephew. No music yet, and every sound is one Roblox ping at 8 pitches.
  - The admissions are excellent and rare, but they are the only place the writer has an opinion. Every other feature gets identical weight and nothing is named as the good part, which is the flatness that makes a post read as generated even when the facts are real. The lava pulse is the one thing here with a story behind it (a player reported a lava pool blocking the only route on level 6, so it neve
- 🎨 17 wall themes to buy with coins or gems, classic is free.  Nothing costs Robux
  - Two unrelated facts welded into one bullet, with a stray double space at the seam. The Robux line is the strongest thing on the page for a Roblox parent or a sceptical player and it is riding shotgun on a cosmetics bullet.

### The draft, unedited

```
Dark maze, one torch, one way out. Every level comes out of one world seed, so level 40 is the same maze for you as it is for me, and it stays that way as long as I leave the seed alone. That is the only reason the medal times and the record board mean anything.

🚪 Three doors: Solo Climb, Group, Play with Friends. Group and Friends cap at 4 in one maze
🪙 Coins: 3 on level 1, 90 once the maze reaches 30x30 around level 241
🔥 Lava pulses. 3 seconds safe, the last 0.8 flashes yellow, then 2.2 that kill you. First one is on level 6. It used to sit on the only route and never switch off, and a real player got walled in and quit. The pulse is my fix and the best thing in here
👹 Monsters top out at 15. You walk 16
🟦 Hit a coloured button, the wall wearing that colour drops into the floor
🏁 Touch the green EXIT and the next maze builds around you, clock reset. No skipping, the picker only offers levels you have cleared plus one

Medal targets come from the maze: par is the straight walk from start to exit, Diamond is par x 1.3, same for everyone. Top 3 times per level are kept across every server.

🛒 Coins buy 4 perks: torch 300, extra life 600, speed 500, minimap 800
🎨 17 wall themes, coins or gems. Classic is free
💸 Nothing costs Robux
🧭 Failed a level 3 times? Buy a glowing route to the exit, 40 + 6 per level, capped at 250. You still have to walk it, and a guided run sets no record
🎁 Daily login pays 150 coins, 1050 on day 7
📱 Phone works, the side panels fold behind a button so they miss your thumbstick

🛠️ Built by an uncle and his nephew. No music yet, and every sound is the same Roblox ping at 8 pitches. Movement is client-side, so a cheater can post a fake time and I cannot stop that from the server.

🙏 Send me a screenshot or clip I actually use and the lobby board pays 25000 coins + 2500 gems
👍 Like and favourite it if you get past level 20

❓ Can you clear level 50 without buying the route?
```

## Grow a Crystal

Proposed title: `Grow a Crystal 💎 [GEODE]`

### Claims the code does not support (3)

**⛏️ click the grown crystal to harvest it**

The ClickDetector is parented to the SOCKET part, not the crystal. Main.server.luau:193-205 creates the ClickDetector on the 6x1x6 slate socket Part; the crystal is a separate Part built at :220-231 as a child of that socket with no ClickDetector of its own. Harvesting is only guaranteed by clicking the socket; a click that lands on the crystal itself depends on the engine walking up the ancestor chain from a BasePart (not a Model), which nothing in this repo tests. Never runtime-tested at all per CLAUDE.md. Changed to 'click one again when it finishes growing'.

**🍀 ... 6 sockets each, 48 at chamber 8 (sold alongside 'A flat pad, the sockets and the glowing crystals are the whole scene')**

48 sockets do get built (Config.luau:54-55, Main.server.luau:239-249), but they do not fit on the pad. socketWorldPos (Main.server.luau:167-176) places chamber index c at z = c*10, so chambers 7 and 8 (sockets 37-48) land at z=60 and z=70, while the pad (Main.server.luau:416-417, Position z=20, Size z=60) ends at z=50. Chamber 6 straddles the edge at z=50. So the last two chambers a player buys hang in the air with no ground under them, and the copy sells the 48-socket endgame while conceding only that the world is one flat pad. Revision states the floating chambers outright.

**Tag: Mining**

There is no mining mechanic anywhere in src/. The only world interaction is a ClickDetector on a socket that plants or harvests (Main.server.luau:193-205). The word appears once in the codebase, as the leaderboard heading 'TOP MINERS' (Hud.client.luau:~248). Recommend swapping the Mining tag for Clicker, which the code actually supports.

### Where the first draft read as machine-written (8)

- 💎Welcome to Grow a Crystal💎
  - Template greeting. It repeats the title, carries zero information, and is the single most common opening line on an AI-written store page. A scene-setting intro before the feature list is the intro-body-conclusion shape the format does not need.
- How to Play:
  - A section heading inside a 250-word post. Headings belong in the planning doc; here a blank line does the same job and does not announce that a list is coming.
- 💎 click an empty socket to plant the selected seed tier / ✨ a Shard is grown in 60 seconds, a Mythic seed takes 40 minutes / ⛏️ click the grown crystal to harve
  - Seven bullets, every one a single line, every one emoji-led, every one starting with a lowercase verb or noun, all within a few words of the same length. Uniform bullets read as generated. Unequal effort is the truth here, and the bullets should show it.
- 💻 Supports Desktop, Mobile and Tablet players
  - Spec-sheet line. 'Supports' is a QA-report frame, and nothing in it can be seen, counted, or photographed. It also reads as coverage-hedging, listing every device so no player feels excluded.
- Can you fill the Codex to 6/6, or does every roll die at Quartz?
  - The 'do you have what it takes / how far can you go' closer. It is a challenge aimed at the reader rather than a question with a wrong answer, and it restates the Codex bullet in new words, which is the closing-kicker shape.
- Built solo, code only, no art.
  - The only history in the post, and it is written with the person removed. No 'I', nothing ranked as the good part, nothing named as the weak part. Uniform enthusiasm across every feature.
- Mythic out of a plain Shard is 1 in 4,329 at Luck 0 and about 1 in 58 at Luck 10. A Shard seed is a losing buy until you own the first Luck level. Amethyst seed
  - Three sentences of 17, 14 and 13 words with the same clause shape, back to back. The best numbers in the post are laid out like a spec table, and the middle claim states a verdict without the number behind it.
- [ ALPHA ] There is no cavern built yet. A flat pad, the sockets and the glowing crystals are the whole scene. Harvest never announces your tier either, you read
  - Right instinct, wrong shape. The confession is the tidiest paragraph in the post: four balanced sentences, one admission each, all roughly the same length. Real notes are lopsided, and the ugliest fact should be the longest sentence.

### The draft, unedited

```
You plant seed-crystals in six socket tiles and click one again when it finishes growing. A Shard takes 60 seconds. A Mythic seed takes 40 minutes and keeps growing while you are logged out.

The harvest is the gacha. Every crystal rolls refraction, one tier up per hit, stopping at the first miss: Shard, Quartz, Amethyst, Prism, Legendary, Mythic.

💎 Mythic out of a plain Shard is 1 in 4,329 at Luck 0. About 1 in 58 at Luck 10.
💎 A Shard seed costs 10 Dust and pays back 7.8 on average, so it loses money until you own the first Luck level. Amethyst seeds and up never earn their price back at any Luck level.
💎 6 sockets per chamber, 48 at chamber 8. Dust also buys Luck and Growth.
💎 Codex counts to 6/6. The top 10 Dust board pulls every 30 seconds.
⚠️ Clicking a socket when you own no seed of that tier just spends your Dust on one. No confirm box. I know.

Codes: WELCOME, CRYSTAL, GEODE, MYTHIC. 5,600 Dust and an Amethyst seed between them. One Geode a week for 1,000 Dust, rotating Prism, Legendary, Mythic.

Alpha. There is no cavern. Your plot is one flat 48 by 60 pad with slate sockets and neon crystals on it, and the last two chambers you buy sit off the edge of that pad, floating. Harvest never tells you what tier you rolled either. You read it off the Dust counter. The refraction roll is the good part and the only part I would defend. Built solo, code only, no art. Someone reported the HUD covering their whole phone screen, so the panels now hide behind three buttons at the top.

Is 1 in 4,329 too stingy for a Shard at Luck 0? That is the number I am least sure about.

Tags: Grow a Crystal, grow a cristal, crystal, gem, idle, afk, offline growth, gacha, grow a garden, simulator
```

## +1 Jump Every Step

Proposed title: `[LAUNCH] +1 Jump Every Step Obby`

### Claims the code does not support (2)

**Touch a platform you have never touched and you get +1 Jump Power / step on a new platform for +1 Jump Power**

The gate is not "never touched", it is "past your frontier". Main.server.luau:287-291 isBeyondFrontier returns true only when tier > frontierTier, or tier == frontierTier and idx > frontierIdx, and grantStep at :301 returns early otherwise. A platform you have genuinely never touched pays nothing if it sits behind your highest position, and the source comment at :303-307 says so outright ("hopp forbi tomrom teller likevel bare de faktisk trakkede"). Skipping is reachable in play: earn is fixed at 1 while the rebirth multiplier only scales Humanoid.JumpHeight (Progression.luau:18-20, Main.server.luau:305), so a rebirthed player on the 60 stud ceiling clears two 5-30 stud steps at once on tiers 2-11 and permanently forfeits those points. Going back down to collect them returns nothing.

**Saves every 20 seconds and respawns you on your own platform, not at the bottom**

The save half checks out (Config.luau:81 AutosaveSeconds = 20, loop at Main.server.luau:457-464). The respawn half only holds mid-session. On a join, onPlayerAdded (Main.server.luau:419-437) yields inside loadProfile on a DataStore UpdateAsync, then at :432 calls onCharacter for an already-spawned character, and only builds the tower up to frontierTier at :435-437, AFTER the placement has run. onCharacter :383 requires builtTiers[p.frontierTier] to exist and otherwise falls through to :388, which is the base pad. On a fresh server only tier 1 is built (:246), so a returning tier 30 player whose character loaded during the DataStore call is put at the bottom, which is precisely what the line promises will not happen. Never runtime-tested (zero visits, luau-CLI unit tests only).

### Where the first draft read as machine-written (9)

- 🏛️ Welcome to +1 Jump Every Step 🏛️
  - Scene-setting greeting with emoji bookends, then intro, then features, then a closing invitation. That is the intro-body-conclusion shape, and a store page should be one line of what it is followed by the list.
- How to Play:
  - A section heading inside a 200 word post. Headings belong in the planning doc; a blank line does the same job here.
- No kill bricks, no lava, nothing to lose by falling.
  - Tricolon where the third item is an abstraction. Kill bricks and lava can be screenshotted; "nothing to lose" cannot. It is the exact shape the pattern warns about.
- ⬆️ jump higher, clear the next tier, repeat
  - Parallel imperative triple, three clauses of near-identical length, and it says nothing the line above it did not. It is rhythm filling a bullet slot.
- 💻 Desktop, Mobile and Tablet.
  - Reads as a QA/platform badge on a game nobody has opened on a phone. A tested-platforms line from an untested build is exactly the flat confidence that gives AI copy away.
- Built solo, zero visits so far, nobody has played it yet.
  - The second and third clauses are the same fact in different words, arranged as a comma triple. The honesty is the best thing in the post and the restatement blunts it.
- Step height stops growing at tier 17 and jump height caps at 60 studs, so the tower keeps going but the steps stay the same size after that.
  - The clause after "so" restates the clause before it in new words, which is the closing-kicker move at sentence scale.
- How high before you burn it all on a rebirth?
  - Closing rhetorical question from the "how far can you go" family. There is no wrong answer to it, so it asks nothing. A real question names the number you keep changing.
- 🏛️ step on a new platform... ⬆️ jump higher... 🧗 everyone in the server... ⬇️ fall and you get... ♻️ REBIRTH at tier 10... 🏆 top 10 board...
  - Six bullets, one emoji each, all between 7 and 13 words. Uniform shape reads as generated. Unequal bullets are evidence of unequal effort, which is the truth.

### The draft, unedited

```
You start on a stone pad with a normal 7.2 stud jump. Every platform past the highest one you have already reached gives +1 Jump Power, and each point is +0.6 studs of jump height. Six platforms per tier.

One catch: the +1 only fires on platforms past your highest. Skip one on the way up, come back for it later, and it pays nothing.

🏛️ everyone in the server climbs the same tower, seed 20260905
⬇️ fall and you get put back on the exact platform you last earned, no death, nothing lost
♻️ REBIRTH at tier 10, then 18, then 26. The multipliers are 2x, 5x, 10x, 25x, 50x, 100x, and they multiply jump HEIGHT only, you still earn +1 per platform
🏆 top 10 board is your best tier ever and it survives a rebirth
💾 autosaves every 20 seconds

Codes: WELCOME, SKYHIGH, TEMPLE, LAUNCH. One use each. LAUNCH is +100 Jump Power on its own, which parks you on the 60 stud jump ceiling straight off the pad.

The red neon blocks from tier 5 up are decoration with collision switched off, so you pass straight through them. No kill bricks, no lava. You cannot die in this game at all.

Step height stops growing at tier 17 and jump height caps at 60 studs. Above that it is the same climb forever.

Desktop, mobile and tablet. On a phone the two side panels fold behind a Menu button and a Top button along the top edge. I wrote that layout without ever opening the game on a phone, so tell me if it covers your screen.

Built solo, zero visits, nobody has played it. Rejoining is the part I trust least: your tier and Jump Power are saved, but I have never tested a rejoin, and there is a path in the code that can drop you on the starting pad instead of your own platform.

Like it if you clear tier 20.

Is tier 10 too long a first climb before the rebirth unlocks? That is the number I keep moving.
```

## Anomaly: Night Shift

Proposed title: `Anomaly: Night Shift 🔭 [DAY ONE]`

### Claims the code does not support (3)

**📓 catch an anomaly to log it in the Field Guide, 24 entries**

INFLATED. There is no Field Guide. The caught set is real and persisted (Codex.discover, Main.server.luau:895) and the denominator is real (codexTotal = Anomaly.count(Config) = 24, Main.server.luau:737), but the entire client-side surface is one TextLabel: `codexLbl` created at Hud.client.luau:151 and written at Hud.client.luau:665 as "Field Guide: N/24". Hud.client.luau builds exactly three Frames (Root, Status, Tools) plus a tint row - no ScrollingFrame, no list, no entry panel anywhere in the 780-line file. A catalog entry's name and hint are rendered to the player in exactly one place, Hud.client.luau:745-757, and only on a MISS (the death toast). So catching an anomaly increments a number you can never open, and the only way to ever read the 24 entries is to fail at them. "24 entries" as a browsable guide is not in the code.

**🔦 press H at the start pad for a hint / press E to ADVANCE / press Q to TURN BACK, alongside 💻 Supports Desktop, Mobile and Tablet**

HALF-SUPPORTED, and the half that fails is the one the copy sells. Mobile/tablet support is real (Responsive.classify returns phone/tablet/desktop, Responsive.luau:63-69; MAX_CONTROL_PAD 150 reserved at :44; applyLayout in Hud.client.luau). But all three actions are in-world ProximityPrompts (makePrompt, Main.server.luau:646-659) and E/Q/H are only KeyboardKeyCode values - on touch Roblox draws a tap button and no key exists. The HUD even hardcodes the desktop-only string on every device: hintLbl reads "Hints: N  (H at start pad)" at Hud.client.luau:665 with no touch branch. There is also no HUD hint button at all - Hud.client.luau:25-29 wires State, Reveal, Death, Redeem and SetTint, and never requires the UseHint remote - despite the server comment at Main.server.luau:1103 reasoning about "a HUD button". So the copy tells a phone player to press three keys their device does not have.

**Tags: ... Survival ... Exploration**

UNSUPPORTED by the game. There is no survival layer: no health, no resources, no timer, no hazard - a wrong call just sets ps.day back to Config.Progression.StartDay (Main.server.luau:914-916). And there is nothing to explore: buildClean lays out one straight 80-stud corridor with fixed part positions (Main.server.luau:440-497), rebuilt identically every pass, with no branching, no map and no second room. Both tags will pull players expecting a different game and hurt the retention signal on a 0-visit launch.

### Where the first draft read as machine-written (7)

- 🔭 Welcome to Anomaly: Night Shift 🔭
  - The scene-setting "Welcome to X" opener, and it burns the single most valuable line in the post - the first line is what Roblox shows in the game card and search snippet - on repeating the title that is already directly above it. Zero information.
- How to Play:
  - A section heading inside a 200-word post. Headings belong in the planning doc; here it announces a list that is obviously a list.
- 🔭 walk the 80 studs and look at everything\n🚪 press E to ADVANCE if the hall looked clean\n↩️ press Q to TURN BACK if you caught the anomaly\n🌙 right call is Da
  - Six bullets, all one line, all 8-14 words, all emoji + lowercase imperative. Identical shape and identical length across the whole block reads as generated. Uneven bullets are evidence of unequal effort, which is the truth - the hint rule is genuinely more interesting than the E key.
- 💻 Supports Desktop, Mobile and Tablet
  - Spec-sheet frame. "Supports X, Y and Z" is how a QA report writes it, not how a dev talks about their own game.
- 🎧 Max graphics recommended, the hall runs at ClockTime 0.2
  - A headphones emoji on a graphics line, one line under "No sound in this game at all yet." Emoji picked to decorate rather than to mean something - a human writing that line right after typing "no sound" would have caught it.
- ❓ Can you reach Day 33, when all 24 are in play?
  - Closing kicker in the "how far can you go" family, and it restates a fact given two paragraphs earlier. It is also a question with no wrong answer, so it invites nothing.
- No gamepasses, no shop, no pets, no daily rewards. Built solo, and the Best Day board is just the Roblox player list.
  - The only honest line in the post, and it is honest about absences only. Nothing in the copy is ranked - every anomaly gets the same weight, and no part of the game is admitted rough. Keep the line, but it is carrying the whole first-person load by itself.

### The draft, unedited

```
Nothing chases you. The hall gets torn down and rebuilt before every pass, and either it is clean or exactly one thing is wrong.

Walk the 80 studs and look at everything. Then:
E to ADVANCE if it looked clean
Q to TURN BACK if you caught it
Right call is Day +1. A wrong one puts you back on Day 1 no matter how deep you were.
H at the start pad spends a hint token, and all it tells you is clean or not clean, never which one. Phone and tablet get a tap button instead of the key.
Catching one ticks a counter, 0/24. There is no book to open yet, just the number going up.

Day 1 draws from the 8 obvious ones. A new type joins every 2 days and all 24 are in play from Day 33. Anomaly chance starts at 50% and stops climbing at 62% on Day 31. Miss one and the game names the thing you walked past.

Best two: The Watcher stands at the far end facing you, The Climber is upside down on the ceiling halfway along, and both have a red point light where the face should be. Worst one: The Flicker does not flicker. It turns one ceiling light green and that is it. Fixing that next.

⚠️ No sound at all yet. The wrong-call scare is a red flash and a camera shake, that is the whole scare.
🎁 Code WELCOME for 3 hint tokens.
Turn the graphics up. The hall runs at ClockTime 0.2 and it is meant to be that dark.

No gamepasses, no shop, no pets, no daily rewards. Built solo, and the Best Day board is just the Roblox player list.

Nobody has played this yet. Is 50% on Day 1 too generous? That is the number I keep moving.

Tags: horror, spot the difference, anomaly, anomaly hunter, night shift, observatory, liminal, single player, anomoly, night shift horror
```
