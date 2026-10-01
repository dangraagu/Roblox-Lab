-- SIGNAL LOST — one campaign on the REAL player path (REVIEW-1 findings 4-7). Run: luau check_signallost_campaign.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--
-- A campaign from join to relay 30 through the real server and the real Env / Hud / Board / Move clients, driven
-- by tests/Bot.luau (buying the recommended upgrade at the relay fabricator), with Hazards.step wrapped to log what
-- happens to every hazard. Asserted:
--   * a hazard is never called off while its player is still in the sector (finding 4: walking on through a hatch
--     made 111 of 112 warnings vanish mid-telegraph); every warning ends in a finished flight, a near-miss or a hit,
--     or is called off only by leaving the sector;
--   * a player outside the ring when it arrives is never shoved, and one inside it is;
--   * the rate the standard asks for, measured, not modelled (finding 5): about one warning per 2-3 minutes of play
--     in the hazard bands (k >= 5), counted over ALL play time from the first k >= 5 arrival to relay 30 (hub, transit
--     and relay rooms included). One campaign per run (the emulator allows one harness per process): about 24 min of
--     such play and 8-12 warnings; measured per run at 55..85 s: one per 2.32-3.08 min (median 2.54) over 47
--     campaigns at bot speed 1.0 (41) / 0.8 (3) / 0.65 (3); at the old 80..120 s: one per 2.98-4.32 min over 9. A run
--     passes at 1.8-3.3 (the standard's "about"; see the assertion);
--   * the relay room the splice builds is not covered (finding 6): after every one of the 30 splices, no dressing piece
--     stands on the floor hatch or cuts into the relay console (they are built AFTER the module was first dressed);
--   * REST tapped in the relay room right after a splice shows the RESTING line, not the splice's hint (finding 7);
--   * with every prompt built (after the first splice), no two prompts a player can stand in reach of at once share a
--     keyboard key or a gamepad button (Roblox shows one prompt per button), and none uses ButtonX, REST's button
--     (the second reviewer's "could not verify": every prompt defaulted to ButtonX, two on one console).
-- Each campaign plays different sectors (engine entropy), so the counts vary run to run; only the bounds are asserted.

local Harness = require("./emu/harness")
local Bot = require("../signal-lost/tests/Bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local KMAX = 30
local errorsTotal = 0

local function campaign(run)
	local h = Harness.new({ bundle = require("./build/signal-lost"), name = "signal-lost", viewport = { 1280, 720 }, touch = false })
	assert(h:tryRun("server/Main.server"))
	h:advance(1)
	local RS = h.game:GetService("RunService")
	local function frame() RS.RenderStepped:Fire(0.1); RS.Heartbeat:Fire(0.1) end
	local plr = h:join("Camp" .. run, 56000 + run)
	h.Players:simulateSpawn(plr, h.workspace)
	RS:setIsServer(false)
	for _, c in { "client/Hud.client", "client/Env.client", "client/Board.client", "client/Move.client" } do
		assert(h:tryRun(c))
	end
	local HZ = h.modules["shared/Hazards"].value
	local HzCfg = h.modules["shared/Config"].value.Hazards
	local EnvBus = h.modules["shared/EnvBus"].value
	local o = { spawn = 0, spawn5 = 0, done = 0, nearMiss = 0, inRing = 0, cancelIn = 0, cancelOut = 0, hits = 0,
		hitOutside = 0, inRingNoHit = 0, firstK = nil }
	local curK = 0
	local live = nil
	local origStep = HZ.step
	HZ.step = function(state, cfg, dt, ctx, rand)
		local ev = origStep(state, cfg, dt, ctx, rand)
		local plan = state.active
		if plan and ctx.aim and not plan._arr and plan.t >= plan.arriveAt then
			plan._arr = true
			plan._inAtArr = HZ.inZone(plan, ctx.aim, HzCfg.PlayerRadius)
		end
		if ev and ev.type == "spawn" then
			o.spawn += 1
			if curK >= 5 then o.spawn5 += 1 end
			o.firstK = o.firstK or curK
			live = ev.plan
		elseif ev and ev.type == "done" then
			o.done += 1
			if ev.plan._inAtArr then o.inRing += 1 else o.nearMiss += 1 end
			if ev.plan._inAtArr and not ev.plan.hit then o.inRingNoHit += 1 end
			live = nil
		elseif ev and ev.type == "cancel" then
			if ctx.module then o.cancelIn += 1 else o.cancelOut += 1 end
			live = nil
		end
		return ev
	end
	-- a shove is judged where the real client tests it: the position it passes, at that moment, must be in the ring
	-- (a hit counts from HitLeadSeconds before the arrival, and the shove itself then carries the player out)
	local origCheck = HZ.checkHitStation
	HZ.checkHitStation = function(cfg, plan, t0, t1, pos, radius)
		local hit = origCheck(cfg, plan, t0, t1, pos, radius)
		if hit and not HZ.inZone(plan, pos, radius) then o.hitOutside += 1 end
		return hit
	end
	EnvBus.on(function(kind, data)
		if kind == "hazard" and type(data) == "table" and data.phase == "hit" then o.hits += 1 end
	end)
	local LOCAL = h.workspace:FindFirstChild("SignalEnvLocal")
	local function aabb(p)
		local sz, c = p.Size, p.Position
		return { c.X - sz.X / 2, c.X + sz.X / 2, c.Y - sz.Y / 2, c.Y + sz.Y / 2, c.Z - sz.Z / 2, c.Z + sz.Z / 2 }
	end
	local function overlapXZ(a, b) return a[1] < b[2] - 1e-6 and b[1] < a[2] - 1e-6 and a[5] < b[6] - 1e-6 and b[5] < a[6] - 1e-6 end
	o.splices, o.roomChecked, o.onHatch, o.inConsole, o.examples = 0, 0, 0, 0, {}
	-- after a splice: the relay module's dressing against the floor hatch and the console the splice built
	local function relayRoom(k)
		local hatch, console
		for _, m in h.workspace.Station:GetDescendants() do
			if m.Name == "FloorHatch" then hatch = m end
			if m.Name == "RelayConsole" then console = m end
		end
		local id = hatch and tonumber(string.match(hatch.Parent.Name, "(%d+)$"))
		local dress
		for _, f in LOCAL.Dressing:GetChildren() do
			if id and string.match(f.Name, "_" .. id .. "_" .. k .. "$") then dress = f end
		end
		if not (dress and hatch and console) then return end
		o.roomChecked += 1
		local hb, cb = aabb(hatch), aabb(console)
		for _, p in dress:GetChildren() do
			if p:IsA("BasePart") then
				local b = aabb(p)
				if overlapXZ(b, hb) then -- at ANY height: a wall piece over the hatch hides it from above too
					o.onHatch += 1
					table.insert(o.examples, string.format("k%d %s overlaps the floor hatch's footprint (bottom %.1f)", k, p.Name, b[3]))
				end
				if overlapXZ(b, cb) and b[3] < cb[4] and cb[3] < b[4] then
					o.inConsole += 1
					table.insert(o.examples, string.format("k%d %s cuts into the relay console", k, p.Name))
				end
			end
		end
	end
	local bot = Bot.new(h, plr, { onTick = frame })
	bot:waitSeconds(0.5)
	assert(bot:board())
	assert(bot:waitPhase("sector", 6))
	local t5, tEnd = nil, nil
	local guard = 0
	while guard < 400 do
		guard += 1
		local st = bot:state()
		if not st or st.phase ~= "sector" then
			bot:waitPhase("sector", 8)
			st = bot:state()
		end
		curK = st.k
		if st.k >= 5 and not t5 then t5 = bot.stats.seconds end
		local r = bot:playSector(600)
		if r == "blackout" then
			bot:waitPhase("sector", 8)
			continue
		end
		if r ~= "spliced" then print("  STOP: sector " .. st.k .. " -> " .. tostring(r)) break end
		o.splices += 1
		if o.splices == 1 then
			-- every prompt exists now: the lifeboat's two, the dock's RETURN, the relay console's two
			o.prompts = {}
			for _, d in h.workspace:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					local host = d.Parent
					local pos = if host.ClassName == "Attachment" then host.Parent.CFrame * host.Position else host.Position
					table.insert(o.prompts, { name = d.Name, action = d.ActionText, host = host, pos = pos, reach = d.MaxActivationDistance,
						-- unset = Roblox's defaults: KeyboardKeyCode E, GamepadKeyCode ButtonX [DOC ProximityPrompt]
						kb = d.KeyboardKeyCode or Enum.KeyCode.E, gp = d.GamepadKeyCode or Enum.KeyCode.ButtonX })
				end
			end
			-- REST, tapped in the relay room within a second of the splice (the most natural place to pause)
			bot:waitSeconds(0.5)
			local hud = plr.PlayerGui.SignalHud.Root
			hud.RestButton.Activated:Fire()
			bot:waitSeconds(0.5)
			o.restHint = hud.Hint.Text
			o.restLabel = hud.RestButton.Text
			hud.RestButton.Activated:Fire()
			bot:waitSeconds(0.5)
		else
			bot:waitSeconds(0.5) -- two dressing passes (DressEverySeconds 0.25) after the splice built the room
		end
		relayRoom(st.k)
		if st.k >= KMAX then tEnd = bot.stats.seconds break end
		local s2 = bot:state()
		local rec, price = s2.recommended, nil
		for _, row in s2.upRows do if row.id == rec then price = row.price end end
		if rec and price and s2.salvage >= price then
			bot:toRelayPiece("RelayConsole")
			bot:waitSeconds(0.3)
			local console
			for _, m in h.workspace.Station:GetDescendants() do if m.Name == "RelayConsole" then console = m end end
			console.FabricatorPrompt.Triggered:Fire(plr)
			bot:waitSeconds(0.3)
			for _ = 1, 4 do
				local s3 = bot:state()
				local r3, p3 = s3.recommended, nil
				for _, row in s3.upRows do if row.id == r3 then p3 = row.price end end
				if not r3 or not p3 or s3.salvage < p3 then break end
				plr.PlayerGui.SignalHud.Root.Shop.List["Row_" .. r3].BuyButton.Activated:Fire()
				bot:waitSeconds(0.6)
			end
		end
		if not bot:toRelayPiece("FloorHatch") then print("  STOP: no floor hatch at k" .. st.k) break end
		bot:waitPhase("transit", 2)
		bot:waitPhase("sector", 6)
	end
	o.reached = tEnd ~= nil
	o.minutes5 = ((tEnd or bot.stats.seconds) - (t5 or 0)) / 60
	o.stillLive = if live then 1 else 0
	errorsTotal += #h:errors()
	for _, e in h:errors() do print("ERR " .. e) end
	return o
end

print("== hazards on the real player path, one campaign to relay 30")
do
	local o = campaign(1)
	local Config = require("../signal-lost/src/shared/Config")
	print(string.format("  relay 30 %s; %.1f min of play at k >= 5, %d warnings there (%d in all, first in sector %s); finished %d (near-miss %d, in the ring %d), shoves %d, called off in-sector %d, on leaving the sector %d",
		if o.reached then "reached" else "NOT reached", o.minutes5, o.spawn5, o.spawn, tostring(o.firstK), o.done, o.nearMiss, o.inRing, o.hits, o.cancelIn, o.cancelOut))
	truthy(o.reached, "the campaign reaches relay 30")
	eq(o.cancelIn, 0, "no hazard is called off while its player is still in the sector")
	eq(o.done + o.cancelOut + o.stillLive, o.spawn, "every warning ends in a finished flight, or is called off by leaving the sector")
	truthy(o.spawn > 0 and o.nearMiss >= 1, "the near-miss happens on the real path (" .. o.nearMiss .. ")")
	eq(o.hitOutside, 0, "nobody is shoved from outside the ring")
	eq(o.inRingNoHit, 0, "nobody inside the ring at the arrival is missed")
	truthy(o.firstK ~= nil and o.firstK >= 5, "the first hazard comes in the hazard bands (sector " .. tostring(o.firstK) .. ")")
	local per = o.minutes5 / math.max(o.spawn5, 1)
	print(string.format("  one warning per %.2f min of play at k >= 5", per))
	-- "about one per 2-3 minutes": one run is ~24 min and 8-12 warnings, so a run's rate scatters around the median
	-- (2.53, sd 0.16, 2.32-3.08 over 41 runs at bot speed 1.0); 1.8-3.3 is the standard's "about", >4 sd either side.
	-- The interval itself is pinned by Config.spec; 80..120 s gave 2.98-4.32 and 120..180 s gives ~5.
	truthy(per >= 1.8 and per <= 3.3, string.format("about one hazard per 2-3 minutes of play in the hazard bands (one per %.2f min)", per))
	print(string.format("  relay room after %d splices (%d checked): dressing on the floor hatch %d, in the relay console %d",
		o.splices, o.roomChecked, o.onHatch, o.inConsole))
	for i = 1, math.min(6, #o.examples) do print("    " .. o.examples[i]) end
	truthy(o.roomChecked >= 25, "the relay room was checked after most of the 30 splices (" .. o.roomChecked .. ")")
	eq(o.onHatch, 0, "no dressing piece, at any height, overlaps the footprint of the floor hatch the splice built")
	eq(o.inConsole, 0, "no dressing piece cuts into the relay console the splice built")
	local prompts = o.prompts or {}
	truthy(#prompts >= 5, "after the first splice, every prompt is built (" .. #prompts .. ")")
	local onX, clashes = 0, {}
	for i, a in prompts do
		if a.gp == Enum.KeyCode.ButtonX then onX += 1; table.insert(clashes, a.name .. " uses ButtonX (REST)") end
		for j = i + 1, #prompts do
			local b = prompts[j]
			-- somewhere both are in reach at once (RequiresLineOfSight is off: through a wall too). Two prompts that do the
			-- SAME thing (the dock's RETURN and the relay console's RETURN when the relay is next to the dock) may share
			-- a button: whichever Roblox shows does what the other would.
			local both = (a.pos - b.pos).Magnitude <= a.reach + b.reach and a.action ~= b.action
			if both and a.gp == b.gp then table.insert(clashes, a.name .. " and " .. b.name .. " share gamepad " .. tostring(a.gp)) end
			if both and a.kb == b.kb then table.insert(clashes, a.name .. " and " .. b.name .. " share key " .. tostring(a.kb)) end
		end
	end
	for _, c in clashes do print("    prompt clash: " .. c) end
	eq(#clashes, 0, "no two prompts in reach at once share a key or a gamepad button, and none uses REST's ButtonX")
	eq(o.restLabel, "RESTING", "REST in the relay room right after the splice: the button says RESTING")
	eq(o.restHint, Config.Rest.Text.Resting, "and the hint line is the RESTING line, not the splice's hint")
	eq(errorsTotal, 0, "no scheduler errors")
end

print(string.format("\nsignal-lost campaign: %d passed, %d failed", passed, failed))
assert(failed == 0, "signal-lost campaign check failed")
