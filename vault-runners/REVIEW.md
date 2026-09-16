# Vault Runners - adversarial review

**Verdict: BLOCK**

Built and reviewed 2026-09-09/10. NOT published, and not to be published until the
findings below are closed. Every one of them was proved by running something, not by
reading - the proof is quoted with each.

## Findings (8)

### 1. The Silver and Gold vaults are UNWINNABLE on floor 1, and Bronze becomes unwinnable around floor 7. The kill plane's speed is (vault height)/(countdown), so adding storeys makes the plane rise FASTER through the lower ones. Bronze sweeps 46 studs in 70s (0.657 studs/s); Silver sweeps 64 studs in 80s (0.800); Gold 82 studs in 90s (0.911). A player standing on storey 0 (HumanoidRootPart at local Y=3, KillMargin=2) dies when planeY reaches 1 — at t=16.7s in Bronze, 13.75s in Silver, 12.2s in Gold. The deadline gets EARLIER exactly as the maze gets BIGGER (4x4 -> 5x5 -> 6x6). The difficulty curve is inverted against the geometry, and nothing in the repo measures traversal time.

**Where:** `D:/Claude/Roblox/vault-runners/src/shared/Config.luau (Config.Tiers[*].storeys / collapseSeconds, Config.Vault.KillPlaneStart/KillPlaneTop) + D:/Claude/Roblox/vault-runners/src/shared/VaultFloor.luau:224-230`

**What it costs a player:** 1200 banked gems — roughly 25 flawless Bronze runs — buys the player a vault they can never clear, no matter how well they play. They will die on the ground floor of Silver, every time, and conclude the game is broken. Gold (6000 gems) is worse. The whole mid- and late-game is dead on arrival.

**Proof:** Booted the REAL server in robloxemu and walked the character along the exact BFS-optimal maze path at Roblox's default WalkSpeed 16, with the storey-to-storey climb costing ZERO seconds (maximally generous). Results, real server, real collapse: bronze f1 -> escaped at 41.8s of 70.0s; bronze f6 -> escaped at 32.8s of 62.5s; bronze f10 -> DIED on storey 0 at 13.5s of 56.5s; silver f1 -> DIED on storey 0 at 13.7s of 80.0s; gold f1 -> DIED on storey 0 at 12.0s of 90.0s. With a realistic climb (6 jumps x 0.8s per storey) silver/gold are identical — the player never leaves storey 0. Separately swept the assumptions analytically over walk in {16,20,24} studs/s and jump in {0.0,0.4,0.8}s per step: even at WalkSpeed 24 with free climbing, worst-storey slack is silver f1 -6.2s and gold f1 -16.7s. Last winnable floor at walk=16/jump=0.4: bronze floor 6, silver NONE, gold NONE. Also confirmed nothing in the game sets WalkSpeed/JumpPower (grep over src/ finds only HumanoidRootPart lookups), and no spec or check measures path length or traversal time — check_vaultrunners.luau:207 teleports the root part straight onto the ExitPad.

### 2. beginRun starts a full run even when the player has no character. The teleport into the vault is guarded (`local hrp = char and char:FindFirstChild("HumanoidRootPart"); if hrp then ...`) but the run, the vault build, the slot claim and the countdown are not. The player stays in the hub while the server runs a vault they are not in.

**Where:** `D:/Claude/Roblox/vault-runners/src/server/Main.server.luau:700-745 (beginRun)`

**What it costs a player:** Players.RespawnTime is 5 seconds by default and Reset is how players get unstuck, so any player who taps a vault button during a respawn is locked out of the game for the entire countdown — 70s on Bronze, 90s on Gold. Every further tap is refused with 'You are already inside a vault.' At the end they get '🔒 The vault sealed with 0 gems inside' and a permanent wipes += 1 for something they never did.

**Proof:** Ran the real server in robloxemu, joined a player and deliberately did NOT call simulateSpawn (plr.Character == nil, exactly the respawn window), then fired the Enter remote. Output: 'vaults built while the player has no body: 1', 'the HUD was told a run STARTED: true', then after h:advance(75) -> 'reason=sealed banked=0', last toast '🔒 The vault sealed with 0 gems inside. Nothing banked.' The vault was torn down correctly afterwards and the player could re-enter, so it is a timed lockout rather than a permanent one.

### 3. Every rejected remote still writes to the DataStore. doBuy and doEquip fall through their failure branches ('poor', 'owned', 'unknown', 'unowned') straight into flush(plr, false), which calls store:UpdateAsync on the player's key. There is no debounce, no rate limit, and no 'nothing changed, skip the write' check.

**Where:** `D:/Claude/Roblox/vault-runners/src/server/Main.server.luau:757-793 (doBuy, doEquip) and 148-176 (flush)`

**What it costs a player:** Roblox throttles writes to a single key to roughly one per 6 seconds with a 30-deep queue before it starts erroring. An ordinary player tapping down the eight-pet list to compare multipliers generates one UpdateAsync per tap; a client firing EquipEvent in a loop takes their own save path down and fills the server's DataStore budget. The failure is silent — flush pcalls and warns — so the player simply loses progress with no signal.

**Proof:** Counted the emulator DataStore's own __calls counter (robloxemu/emu/services.luau:305 increments it per API call) around bursts of remote fire against the real server: 60 FAILED equips (pet not owned) -> 60 DataStore API calls; 60 FAILED buys (wallet empty, pet costs 12000) -> 60 calls; 60 equips of a pet id that does not exist -> 60 calls. Every single rejected request wrote.

### 4. During a run, the Timer panel overlaps the Wallet panel on portrait phones. Wallet is 300x62 design px at (14,14); Timer is 280x92 anchored (0.5,0) at x=50%. Under the UIScale the root is 1/scale design px wide, so at 414x800 (scale 0.60) the design width is 690: wallet spans x 14..314, timer spans 205..485 — 109 design px of overlap, both at y 14..~106. Timer is created after wallet so it draws on top of the gem count.

**Where:** `D:/Claude/Roblox/vault-runners/src/client/Hud.client.luau:110-116 (wallet, timer) and D:/Claude/Roblox/vault-runners/check_vaulthud.luau`

**What it costs a player:** Phone-first is the stated design of this HUD, and 414x800 is one of the ten viewports the project already checks. Mid-run — the only moment that matters — the collapse clock sits on top of the player's gem and multiplier readout. At 360x640 (design width 600) it is worse.

**Proof:** Computed the in-run layout directly from the shipped src/shared/Responsive.luau and the literal constants in Hud.client.luau across seven viewports. 414x800 and 360x640 both report WALLET OVERLAPS TIMER; 640x300, 800x360, 800x600, 1366x768 and 1920x1080 are clear. The reason check_vaulthud.luau reports PASS on the same 414x800 viewport is that it never fires a Run 'start' event, so timer.Visible stays false and the panel is never measured — the check has no in-run state at all.

### 5. The session-lock release path has zero test coverage. The builder correctly uses `old.jobId = if releaseLock then nil else game.JobId`, but reverting it to the `releaseLock and nil or game.JobId` form they say they fixed leaves the entire suite green. Only luau-analyze's MisleadingAndOr sees it.

**Where:** `D:/Claude/Roblox/vault-runners/src/server/Main.server.luau:159-167 (flush, the releaseLock branch)`

**What it costs a player:** The bug this line guards against is a player locked out of their own save for LockSeconds (120s) after leaving — 'the game would not let me back in'. Because no test exercises it, the next person who tidies that line, or ports it to another game, reintroduces it silently and every gate still says green.

**Proof:** Applied the mutation to src/server/Main.server.luau, rebuilt the bundle with `py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau`, and ran the headless check: 'vault-runners headless: 71 passed, 0 failed' — unchanged. luau-analyze on the same file: './src/server/Main.server.luau(166,16): MisleadingAndOr'. For contrast, the two server mutations that ARE covered were both killed: removing `part.Parent = parent` from instantiate() hard-errors the check, and freezing the collapse plane gives 'FAIL: the collapse plane actually rose (190.0 -> 190.0)'. File restored.

### 6. The part-budget assertion measures one arbitrary floor and calls it the global maximum. It builds `build(3, 900)` and asserts 'the very worst floor in the game is %d parts', while the print on the very next line reports gold floor 31 at 620 parts — larger than the 618 it just called the worst. Both floors are cells=8/storeys=7 (the caps) but different seeds give different wall-run counts, so 'floor 900' is not extremal, just late.

**Where:** `D:/Claude/Roblox/vault-runners/tests/VaultFloor.spec.luau:516-520`

**What it costs a player:** Nothing breaks today — both numbers are far under the 1500 budget — but README.md and CLAUDE.md both repeat '618 is the worst floor in the game' as if it were a bound, and it isn't one. The next person who tunes MazeGen or raises MaxCells will trust a number that was never a maximum.

**Proof:** Ran `luau tests/VaultFloor.spec.luau`: the suite passes 199/0 and prints 'parts: bronze f1 = 96, gold f31 = 620, worst case = 618' — the printed 'worst case' is smaller than the gold f31 sample printed beside it. Read spec lines 516-520 to confirm the assertion's sample is the single `build(3, 900)` call.

### 7. The brief sells a 'Procedural Rage-Obby' — 'climb/obby through it', 'crumbling platforms', thumbnail 'a player mid-air leaping between two crumbling stone platforms', store copy 'ROBLOX RAGE OBBY', 'Endless PROCEDURALLY-GENERATED climbing towers'. What is built is a flat maze walk per storey plus one 6-step spiral staircase in a single corner cell. There are no platforms to miss, nothing crumbles, and there is no jump the player can fail. README.md's otherwise very honest 'What is NOT built yet' list does not mention this.

**Where:** `D:/Claude/Roblox/vault-runners/src/shared/VaultFloor.luau:131-164 vs D:/Claude/Roblox/docs/game-radar/2026-09-09-roblox-game-radar.md section 1`

**What it costs a player:** The primary genre tag and the entire thumbnail concept describe a game the build is not. A player arriving from 'rage obby' finds a maze walker, and the one mechanic the store copy leads with is absent.

**Proof:** Read the brief section verbatim (docs/game-radar/2026-09-09-roblox-game-radar.md, '1. Vault Runners') against VaultFloor.build. The only vertical challenge in the generator is the `Step_<s>_<k>` loop at VaultFloor.luau:149-164: 6 anchored 5x1x5 blocks at StepRise=3, spiralling inside one 12x12 cell, with the top step landing flush at baseY+18. Every other part is a wall, a floor rectangle, a gem, the exit pad, the seal or the kill plane. Cross-checked against the README's omissions list, which covers pets/eggs/levels/boosts/sound/leaderboard/seal-collision but not the obby.

### 8. Both gem pickup and the escape trigger are pure distance tests against hrp.Position, with no displacement sanity check. In Roblox the client owns its own character's physics, so the position the server reads is whatever the client says it is. There is no per-tick 'you cannot have moved more than WalkSpeed*dt' guard anywhere in the run loop.

**Where:** `D:/Claude/Roblox/vault-runners/src/server/Main.server.luau:594-625 (tickRun gem + exit checks)`

**What it costs a player:** The game's entire economy is one number — gems banked — and it is decided by a coordinate the player controls. A trivial fly/teleport exploit banks 100% of every vault instantly, which is also the only way the Silver and Gold vaults can be completed at all (see finding 1). Honest players compete against that for unlocks and pets.

**Proof:** Read the two checks: `if (local_ - vec(g.position)).Magnitude <= RUN.CollectRadius` and `if (local_ - vec(model.exit.position)).Magnitude <= RUN.ExitRadius`, both fed from `hrp.Position - a.origin`. Demonstrated the same mechanism from the test side: in the emulator, writing hrp.CFrame straight to the ExitPad banks the full carry with no traversal (this is exactly what check_vaultrunners.luau:207-215 does to assert a successful escape). grep over src/ finds no speed, distance-per-tick, or waypoint validation of any kind.

## What the review could NOT break (10)

- UNPARENTED INSTANCES — the headline defect class. Mechanically audited all 46 Instance.new sites under src/ with a script that requires a matching `<var>.Parent =` assignment within 60 lines: zero misses. Then mutated it for real — deleted `part.Parent = parent` from instantiate() in Main.server.luau, rebuilt the bundle, and check_vaultrunners.luau hard-errors on buildVault's own `assert(landed >= wanted)`. The 'ask the folder, don't count the loop' guard is genuine.
- PATH REQUIRES — `grep -rn 'require *( *["'\'']' src/` returns nothing. Every require in src/ is an Instance require from ReplicatedStorage (Main.server.luau:21-28, Hud.client.luau:19-21). The only string requires live in tests/ and the two check_*.luau files, which never ship to Roblox. Nothing in src/shared requires anything at all.
- DataStoreService:GetDataStore IS wrapped — Main.server.luau:63-75, `tryStore` pcalls it, warns, and returns nil so the game still boots with saving degraded. Every store use downstream is `if not store then return` guarded.
- THE BANKING RULE — could not find any path that turns carried gems into wallet gems except RunState.tryEscape. Replacing tryEscape with an unconditional payout at the exit pad was killed by 4 headless assertions ('and it was NOT a success', 'got escaped, want sealed', 'nothing was banked -> got 4, want 0'). Leaving mid-run destroys the vault and banks nothing; dying banks nothing; collecting the same gem twice is refused by run.collected.
- THE PURE-MODULE MUTATION GATE IS REAL — 7 source mutations applied to src/ (not to any test model), all 7 killed: seal boundary >= -> >; unlock >= -> >; Pets.multiplier reading `equipped` instead of the ledger; upper floors as one solid slab (50 failures incl. climbHoleOpen); KillPlaneTop 0 -> 6; wallHeight no longer derived; gem value ignored. Two controls to prove the harness is not just failing on any input: deleting the unreachable `elseif v < 1 then v = 1` clamp in Rng.below survived all five suites, and repainting Config.Hud.PanelColor magenta survived responsive.spec. All files restored.
- GEOMETRY / STUCK STATES — could not construct one. The maze's outer ring is always solid so you cannot walk off the vault; walls are 16 studs against a ~7.35-stud jump so you cannot get on top of one; the top storey has no ceiling but also no way up; the climb hole is open on every storey above 0 and the stair's 6th step lands flush at baseY+18 with only a 0.5-stud gap to the surrounding floor; falling back through a hole drops you onto the step or the storey below, both recoverable. Vault slots are recycled and 400 studs apart against a 204-stud maximum footprint, so no overlap and no outward march.
- REMOTE INPUT VALIDATION — Enter with a non-number, a float, math.huge or NaN all fall out through `Progression.tier` returning nil and produce a toast, not an error (NaN table reads are legal in Lua; only NaN writes raise). Buy/Equip with a non-string or an unknown id are refused. Entering a locked vault builds nothing and names the exact gem shortfall. beginRun has no yield between its `active[plr]` guard and `active[plr] = a`, so remote spam cannot open two runs.
- MazeGen IS verbatim — `diff -q D:/Claude/Roblox/labyrint-spill/src/shared/MazeGen.luau D:/Claude/Roblox/vault-runners/src/shared/MazeGen.luau` reports IDENTICAL.
- REPORTED COUNTS ALL REPRODUCE — Rng 37/0, Progression 63/0, Pets 75/0, RunState 75/0, VaultFloor 199/0, responsive 70/0 (519 total), headless 71/0 after a fresh `py -3 wrap.py`, and check_vaulthud PASS on all 10 viewports. One inaccuracy worth noting: 'luau-analyze is clean on every file except MazeGen' is not what the tool prints — there is no .luaurc and no Roblox type definitions in the tree, so Fx, FxClient, Main.server and Hud.client each emit ~25 'Unknown global Instance/game/Enum/Color3' lines. That is environmental noise, not a defect, and MisleadingAndOr still surfaces through it (proved by mutation S3).
- FULLY RESTORED — `sha256sum` over all 12 files in src/ is byte-identical to the pre-review baseline, the bundle was rebuilt from the restored tree, all six specs plus both headless checks are green, and every scratch file I created was deleted. Nothing committed, published or pushed. (The `robloxemu/check_adv_*.luau` and `robloxemu/_*.luau` files in git status are pre-existing from earlier sessions on other games, not mine.)

