-- SIGNAL LOST — THE PLAYER'S PATH, walked in the built world, from join into a second loop.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--       cd ../signal-lost && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green tests are not a working game. This boots the real server script and the real clients (HUD, environment,
-- board, low gravity), joins one brand-new player with no save file, and plays through tests/Bot.luau — which knows
-- only what a client could know and moves at the speed the server wrote onto the Humanoid — and prints what
-- happened in numbers (the docs/complete-game-standard.md §1 walk):
--
--   LOOP 1  spawn -> walk into the LIFT -> sector 1 -> splice -> the floor hatch -> sector 2 -> ... until the
--           wallet affords the first upgrade -> the relay module's fabricator: buy the AIR TANK -> RETURN at its
--           console -> back in the lifeboat
--   LEAVE   the profile in the store, checked
--   LOOP 2  rejoin -> spawn -> the LIFT -> sector best + 1 with the bigger tank -> splice -> the next dock
--
-- Every salvage figure asserted is recomputed from DESIGN.md §9 by hand here (value(k) = 5 + (k - 1), bonus(k) =
-- 10 + 2 (k - 1)), never read back from shared/Economy.luau. Every stream is engine entropy, so every run walks
-- different sectors; the numbers printed are one sample, not a distribution, and the assertion count varies.

local Harness = require("../../robloxemu/emu/harness")
local Bot = require("./Bot")

local h = Harness.new({ bundle = require("../../robloxemu/build/signal-lost"), name = "signal-lost-walk",
	viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function say(fmt, ...) print(string.format(fmt, ...)) end

local UID = 90210
local store = h.services.DataStoreService:GetDataStore("SignalLost_v1")
local function stored()
	local rec = store:GetAsync("u_" .. UID)
	return rec and rec.data
end
local function value(k) return 5 + (k - 1) end
local function bonus(k) return 10 + 2 * (k - 1) end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.game:GetService("RunService")

local function frame()
	RS.RenderStepped:Fire(0.1)
	RS.Heartbeat:Fire(0.1)
end

--=========================================================================== LOOP 1
print("== LOOP 1")
local plr = h:join("Walker", UID)
h.Players:simulateSpawn(plr, h.workspace)
RS:setIsServer(false)
for _, c in { "client/Hud.client", "client/Env.client", "client/Board.client", "client/Move.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local bot = Bot.new(h, plr, { onTick = frame })
bot:waitSeconds(0.5)
local spawnPos = bot:pos()
local hubSpawn = h.workspace.Lifeboat.HubSpawn
say("spawn: (%.2f, %.2f, %.2f) on HubSpawn at (%.1f, %.1f, %.1f)", spawnPos.X, spawnPos.Y, spawnPos.Z,
	hubSpawn.Position.X, hubSpawn.Position.Y, hubSpawn.Position.Z)
truthy(math.abs(spawnPos.X - hubSpawn.Position.X) <= 3 and math.abs(spawnPos.Z - hubSpawn.Position.Z) <= 3
	and spawnPos.Y > hubSpawn.Position.Y, "a new player lands on HubSpawn")
eq(bot:state().phase, "hub", "in the lifeboat")
eq(bot:state().best, 0, "a new profile: 0 relays")

local t0 = bot.stats.seconds
truthy(bot:board(), "walking into the LIFT starts the ride")
local tBoard = bot.stats.seconds - t0
truthy(bot:waitPhase("sector", 5), "the ride arrives in sector 1's dock")
local tDock = bot.stats.seconds - t0
say("join -> ride %.1f s (the core action inside the checklist's 5 s: %s), dock opens at %.1f s", tBoard,
	tostring(tBoard <= 5), tDock)
truthy(tBoard <= 5, "the core action (boarding the LIFT) within 5 seconds of spawning")

local sectors = {}
local blackouts = 0
local lastSalvage = 0
local boughtAt = nil
for guard = 1, 30 do
	local st = bot:state()
	local k = st.k
	local tS = bot.stats.seconds
	local minAir0, vac0 = bot.stats.minAir, bot.stats.vacuumSeconds
	bot.stats.minAir = math.huge
	local before = st.salvage
	local r = bot:playSector(400)
	local after = bot:state()
	if r == "blackout" then
		blackouts += 1
		say("  sector %d: BLACKOUT after %.1f s (kept %s)", k, bot.stats.seconds - tS, tostring(bot:saw("blackout") and bot:saw("blackout").data.kept))
		bot:waitPhase("sector", 6)
		continue
	end
	truthy(r == "spliced", "sector " .. k .. " spliced (" .. r .. ")")
	if r ~= "spliced" then break end
	local sp
	for i = #bot.notices, 1, -1 do
		if bot.notices[i].kind == "spliced" then sp = bot.notices[i].data break end
	end
	local carried = sp and sp.carried or -1
	local pieces = carried / value(k)
	eq(sp and sp.paid, carried + bonus(k), string.format("sector %d banks carried + bonus(%d) = %d + %d", k, k, carried, bonus(k)))
	truthy(pieces == math.floor(pieces), string.format("carried %d is a whole number of value(%d) = %d pieces", carried, k, value(k)))
	eq(after.salvage, before + carried + bonus(k), "the wallet rises by exactly that")
	eq(after.best, k, "relays restored = " .. k)
	eq(plr.leaderstats.Relays.Value, k, "leaderstats.Relays follows")
	table.insert(sectors, { k = k, secs = bot.stats.seconds - tS, carried = carried, pieces = pieces, paid = sp.paid,
		minAir = bot.stats.minAir, vac = bot.stats.vacuumSeconds - vac0 })
	say("  sector %d: spliced after %.1f s, %d piece(s) = %d carried + %d bonus -> wallet %d; min AIR %.1f s, %.1f s in vacuum",
		k, bot.stats.seconds - tS, pieces, carried, bonus(k), after.salvage, bot.stats.minAir, bot.stats.vacuumSeconds - vac0)
	local _ = minAir0
	lastSalvage = after.salvage
	if after.salvage >= 120 then
		-- the relay module's fabricator: the console, its prompt, the panel, the purchase
		truthy(bot:toRelayPiece("RelayConsole"), "walk to the relay module's console")
		bot:waitSeconds(0.3)
		eq(bot:state().nearFab, true, "the State says a fabricator is in reach")
		local console
		for _, m in h.workspace.Station:GetDescendants() do
			if m.Name == "RelayConsole" then console = m end
		end
		local fab = console and console:FindFirstChild("FabricatorPrompt")
		truthy(fab ~= nil, "the console has a fabricator prompt")
		if fab then fab.Triggered:Fire(plr) end
		bot:waitSeconds(0.3)
		truthy(bot:saw("shop") ~= nil, "the prompt opens the fabricator panel")
		local hud = plr.PlayerGui:FindFirstChild("SignalHud")
		truthy(hud and hud.Root.Shop.Visible, "the HUD shows the shop")
		local w0 = bot:state().salvage
		local buy = hud.Root.Shop.List.Row_tank.BuyButton
		buy.Activated:Fire()
		bot:waitSeconds(0.5)
		local s2 = bot:state()
		eq(s2.up.tank, 1, "tapping the AIR TANK's price buys rank 1")
		eq(s2.salvage, w0 - 120, "for 120 salvage")
		boughtAt = bot.stats.seconds - t0
		say("  bought AIR TANK rank 1 at the relay's fabricator, %.1f min after joining: wallet %d -> %d", boughtAt / 60, w0, s2.salvage)
		-- RETURN at the same console
		local ret = console:FindFirstChild("ReturnPrompt")
		truthy(ret ~= nil, "the console has a RETURN prompt")
		if ret then ret.Triggered:Fire(plr) end
		truthy(bot:waitPhase("hub", 5), "RETURN rides back to the lifeboat")
		local home = bot:pos()
		local arr = h.workspace.Lifeboat.HubArrival.Position
		truthy(math.abs(home.X - arr.X) < 4 and math.abs(home.Z - arr.Z) < 4, "landing on HubArrival")
		eq(bot:state().salvage, w0 - 120, "a RETURN after the splice banks nothing more and loses nothing")
		break
	end
	truthy(bot:toRelayPiece("FloorHatch"), "walk onto the floor hatch")
	truthy(bot:waitPhase("transit", 2), "the floor hatch starts the transit ride")
	truthy(bot:waitPhase("sector", 5), "arriving in sector " .. (k + 1))
end
truthy(boughtAt ~= nil, "loop 1 earned and spent the first upgrade")

--=========================================================================== LEAVE
print("== LEAVE")
local beforeLeave = bot:state()
h:leave(plr)
h:advance(1)
local rec = stored()
truthy(rec ~= nil, "the profile is in the store")
if rec then
	eq(rec.best, beforeLeave.best, "stored best = " .. tostring(beforeLeave.best))
	eq(rec.salvage, beforeLeave.salvage, "stored salvage = " .. tostring(beforeLeave.salvage))
	eq(rec.up and rec.up.tank, 1, "stored Air Tank rank 1")
	eq(rec.open, nil, "nothing left open")
	local raw = store:GetAsync("u_" .. UID)
	eq(raw.lock, nil, "the session lock was released on leaving")
	say("stored: best %d, salvage %d, earned %d, attempts %d, blackouts %d, tank %d, boots %d",
		rec.best, rec.salvage, rec.salvageEarned, rec.attempts, rec.blackouts, rec.up.tank, rec.up.boots)
end
local lb = h.services.DataStoreService:GetOrderedDataStore("SignalLost_Relays_v1")
local ov = lb.__data["u_" .. UID]
truthy(type(ov) == "number" and math.floor(ov / 2e9 + 0.5) == beforeLeave.best, "the board holds relays restored = " .. beforeLeave.best .. " (" .. tostring(ov) .. ")")

--=========================================================================== LOOP 2
print("== LOOP 2 (rejoin)")
local plr2 = h:join("Walker", UID)
h.Players:simulateSpawn(plr2, h.workspace)
h:advance(0.5)
local bot2 = Bot.new(h, plr2, { onTick = frame })
bot2:waitSeconds(0.5)
local st2 = bot2:state()
eq(st2.best, beforeLeave.best, "the rejoin loads best " .. beforeLeave.best)
eq(st2.salvage, beforeLeave.salvage, "and the wallet")
eq(st2.up.tank, 1, "and the Air Tank")
local p2 = bot2:pos()
truthy(math.abs(p2.X - hubSpawn.Position.X) <= 3 and math.abs(p2.Z - hubSpawn.Position.Z) <= 3, "the rejoin lands on HubSpawn")
truthy(bot2:board(), "the LIFT again")
truthy(bot2:waitPhase("sector", 5), "arriving")
local s3 = bot2:state()
eq(s3.k, beforeLeave.best + 1, "the LIFT takes a returning player to sector best + 1 = " .. (beforeLeave.best + 1))
eq(s3.tank, 25, "with the bigger tank: 25 s of air")
local tL2 = bot2.stats.seconds
local r2 = bot2:playSector(400)
if r2 == "blackout" then
	say("  loop 2 sector %d: blackout; waking in a new dock", s3.k)
	bot2:waitPhase("sector", 6)
	r2 = bot2:playSector(400)
end
eq(r2, "spliced", "loop 2's first sector is spliced")
say("  loop 2: sector %d spliced after %.1f s; wallet %d; relays %d", s3.k, bot2.stats.seconds - tL2, bot2:state().salvage, bot2:state().best)
truthy(bot2:toRelayPiece("FloorHatch"), "and the floor hatch")
truthy(bot2:waitPhase("sector", 6), "into sector " .. (s3.k + 1) .. ": the second loop continues")

--=========================================================================== totals
print("== TOTALS")
local total = 0
for _, s in sectors do total += s.secs end
say("loop 1: %d sectors spliced in %.1f s of play (%.1f min), %d blackout(s); first purchase %.1f min after joining",
	#sectors, total, bot.stats.seconds / 60, blackouts, (boughtAt or 0) / 60)
say("virtual time %.1f s; hatches opened by the bot %d + %d", h.scheduler:now(), bot.stats.hatches, bot2.stats.hatches)
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
for _, w in h.warnings do
	print("warning: " .. w)
	failed += 1
end
print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
