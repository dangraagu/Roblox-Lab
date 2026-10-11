-- Nightwatch Manor — the position guard: a night the character did not WALK is void. Run: luau check_nightwatchmanor_posguard.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- Second review, 2026-10-09, HIGH: the exit's guard (check_nightwatchmanor_guard) measured the clock and the room at
-- the moment of the press and nothing in between, and the Nightwatcher sees by ROOM. So a script could teleport out of
-- the manor (never seen: it is in no room), wait out the clock, teleport into the exit room and press E: one safe
-- night every ~12 s, the board's 500 nights in under two hours. The server now samples the root every tick of a night
-- (PosGuard.luau; the pure rules and the honest-player margins are tests/PosGuard.spec.luau) and VOIDS the night on
-- evidence: outside every room, or more ground than a walk covers.
--
-- This boots the REAL server (and the real clients for the first player) with the guard as it ships
-- (posGuard = true: the kit switches it off for the other checks, which teleport by design), and checks:
--   1. THE EXPLOIT: out of the manor, wait, into the exit room, press. The night is not counted, the player is told
--      why, and nothing is written to the board's store or the profile.
--   2. AN HONEST WALK to the exit, at WalkSpeed through the doorways: counted, and the board's store has it.
--   3. Staying inside and teleporting to the door, pressing in the same tick: void, for moving too fast.
--   4. A 3 s LAG GAP in an honest walk (the server sees nothing, then one sample makes it up): counted.
--   5. A DEATH and RESPAWN deep into a night (the dead root drifts out of the manor: not judged, and no way out;
--      the engine drops the new character on the safehouse's pad first, and the server puts it back in the foyer,
--      further away than the bank could ever pay for): not a void, and the walk counts.
-- The Nightwatcher is blinded in memory throughout (SightRange 0, CatchRadius 0, the kit's own way): this is about
-- the walk, not the chase, and every section asserts it was never caught.

local Kit = require("./check_nightwatchmanor_kit")
local DT = require("./emu/datatypes")
local Vector3, CFrame = DT.Vector3, DT.CFrame

local ME, LONG = 4242, 6161
local BOARD_STORE = "NightwatchManorBoard_v1" -- written out, not read from Config
local ctx = Kit.boot({ name = "nwm-posguard", userId = ME, posGuard = true, profile = { night = 7, stash = 0, best = 6, bestAt = 1780000000, levels = { lockbox = 3 } } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local RS = ctx.RS
local Manor = h:_require(RS:FindFirstChild("Manor"))
local Crossing = h:_require(RS:FindFirstChild("Crossing"))
local SS = h.game:GetService("ServerStorage")
local DSS = h.services.DataStoreService
local board = DSS:GetOrderedDataStore(BOARD_STORE)
local V = Config.Player.WalkSpeed
local TICK = Config.TickSeconds

local function section(s) print("== " .. s) end

eq(Config.Save.LeaderStore, BOARD_STORE, "set-up: the board's store is " .. BOARD_STORE)
truthy(Config.Guard.PositionChecks ~= false, "the position guard is ON in this check, as it ships")
eq(V, 20, "set-up: WalkSpeed 20")
eq(TICK, 0.1, "set-up: the night steps every 0.1 s")

local W = Config.Watcher
W.SightRange, W.CatchRadius = 0, 0

local function noticesOf(plr, kind: string): { any }
	local out = {}
	for _, s in ctx.noticeRemote:sentTo(plr) do
		local p = s.args[1]
		if type(p) == "table" and p.kind == kind then table.insert(out, p) end
	end
	return out
end
local function allNotices(plr): { any }
	local out = {}
	for _, s in ctx.noticeRemote:sentTo(plr) do
		if type(s.args[1]) == "table" then table.insert(out, s.args[1]) end
	end
	return out
end
local function stateOf(plr): any
	local list = ctx.stateRemote:sentTo(plr)
	for i = #list, 1, -1 do
		if type(list[i].args[1]) == "table" then return list[i].args[1] end
	end
	return {}
end
local function manorOf(plr)
	local z = h.workspace:FindFirstChild("Zone_" .. plr.UserId)
	return z and z:FindFirstChild("Manor")
end
local function hrpOf(plr)
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end
local function pressDoorAs(plr)
	local house = h.workspace:FindFirstChild("Zone_" .. plr.UserId):FindFirstChild("Safehouse")
	house.ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
end
local function wait(s: number) ctx.seconds(s, TICK) end
-- every write the server makes to the board's store, as { key, the value stored after it }
local boardWrites: { any } = {}
do
	local oUpdate, oSet = board.UpdateAsync, board.SetAsync
	board.UpdateAsync = function(self, key, ...)
		local r = table.pack(oUpdate(self, key, ...))
		table.insert(boardWrites, { key = key, value = board:GetAsync(key) })
		return table.unpack(r, 1, r.n)
	end
	board.SetAsync = function(self, key, ...)
		local r = table.pack(oSet(self, key, ...))
		table.insert(boardWrites, { key = key, value = board:GetAsync(key) })
		return table.unpack(r, 1, r.n)
	end
end
local function nightOn(uid: number): number?
	local v = board:GetAsync("u_" .. uid)
	return if type(v) == "number" then math.floor(v / 2e9) else nil
end
-- The board catches up with a best night saved before this session (the autosave's job): let it, so that everything
-- after is this session's doing.
local function settleBoard(uid: number, best: number)
	ctx.seconds(Config.Save.AutosaveSeconds * 2 + 1, 0.1)
	eq(nightOn(uid), best, string.format("set-up: the board holds the best night this player came with (%d)", best))
end
local function saved(uid: number): any
	local rec = ctx.store:GetAsync("u_" .. uid)
	return rec and rec.data or {}
end

-- The night standing for `plr`: its plan, the manor's origin in the world (from the foyer's floor), the door.
local function nightOf(plr)
	local m = manorOf(plr)
	local plan = Kit.planOf(h, plr.UserId)
	local floor = nil
	for _, f in m:GetChildren() do
		if string.match(tostring(f.Name), "^Room%d+_foyer$") then floor = f:FindFirstChild("Floor") end
	end
	local cx, cz = Manor.roomCenter(Config, Manor.roomById(plan, plan.entranceId))
	local ox, oz = floor.Position.X - cx, floor.Position.Z - cz
	local door = m:FindFirstChild("ExitDoor")
	local n = { manor = m, plan = plan, ox = ox, oz = oz, y = floor.Position.Y + 4, door = door,
		prompt = door:FindFirstChildOfClass("ProximityPrompt"), stand = Kit.exitStand(m),
		need = Kit.crossSeconds(h, plr.UserId) }
	function n.world(x: number, z: number) return Vector3.new(ox + x, n.y, oz + z) end
	function n.room(pos): number? return Manor.roomAtWorld(plan, Config, pos.X - ox, pos.Z - oz) end
	return n
end

-- The honest route: from where the night puts you, through the middle of every doorway on the way, to the spot in
-- front of the exit. World points.
local function routeOf(n): { any }
	local plan = n.plan
	local sx, sz = Crossing.start(Config, plan)
	local pts = { n.world(sx, sz) }
	local path = Manor.pathBetween(plan, plan.entranceId, plan.exitId)
	for i = 1, #path - 1 do
		local mx, mz = Manor.doorwayBetween(Config, plan, path[i], path[i + 1])
		table.insert(pts, n.world(mx, mz))
	end
	table.insert(pts, Vector3.new(n.stand.X, n.y, n.stand.Z))
	return pts
end
local function lengthOf(pts): number
	local d = 0
	for i = 2, #pts do d += (pts[i] - pts[i - 1]).Magnitude end
	return d
end
local function pointAt(pts, d: number)
	for i = 2, #pts do
		local span = (pts[i] - pts[i - 1]).Magnitude
		if d <= span then return pts[i - 1] + (pts[i] - pts[i - 1]) * (if span > 0 then d / span else 0) end
		d -= span
	end
	return pts[#pts]
end
-- Walk it the way a player does: 2 studs every tick. `from`/`to` are distances along the route; `gap` = { at, seconds }
-- is a lag gap (the server sees the character stand still for that long, then where it would have walked to).
local function walk(plr, pts, from: number, to: number, gap: { number }?): number
	local d = from
	local gapped = false
	while d < to - 1e-6 do
		if gap and not gapped and d >= gap[1] then
			gapped = true
			wait(gap[2]) -- nothing arrives...
			d = math.min(to, d + V * gap[2]) -- ...then all of it at once
		else
			d = math.min(to, d + V * TICK)
		end
		local hrp = hrpOf(plr)
		if hrp then hrp.CFrame = CFrame.new(pointAt(pts, d)) end
		wait(TICK)
	end
	return d
end

--======================================================================= 1. the exploit
section("1. THE EXPLOIT: out of the manor, wait, into the exit room, press E")

local me = ctx.me
do
	settleBoard(ME, 6)
	local writesBefore = #boardWrites
	local began = h.scheduler:now()
	ctx.pressDoor()
	wait(1.5)
	eq(stateOf(me).phase, "NIGHT", "set-up: night 7 is running")
	eq(stateOf(me).night, 7, "set-up: ...night 7")
	local n = nightOf(me)
	truthy(n.room(ctx.hrp.Position) == n.plan.entranceId, "set-up: standing in the foyer, where the night put us")
	-- a relic in the bag (the prompt, as the other checks press it), so the void has something to take
	for _, c in n.manor:GetChildren() do
		if string.match(tostring(c.Name), "^Pedestal_") then
			c:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
			break
		end
	end
	wait(0.2)
	eq(stateOf(me).carried, 1, "set-up: a relic in the bag")
	-- three Lockboxes: being CAUGHT would keep 60% of it. A void keeps nothing (a script must not farm relics by it).
	local Upgrades = h:_require(RS:FindFirstChild("Upgrades"))
	truthy(Upgrades.effects(Config, { lockbox = 3 }).keepOnCaught >= 0.5, "set-up: this player's Lockboxes keep over half a haul when caught")
	truthy((stateOf(me).carriedWorth or 0) >= 2, "set-up: ...and the bag is worth something (" .. tostring(stateOf(me).carriedWorth) .. ")")

	-- OUT: 30 studs past the manor's outer wall, straight out from the foyer (the first cell that way with no room in
	-- it). In no room: the Nightwatcher cannot see it.
	local cx, cz = Manor.roomCenter(Config, Manor.roomById(n.plan, n.plan.entranceId))
	local out = nil
	for cells = 1, 12 do
		for _, d in { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } } do
			local p = n.world(cx + d[1] * (cells * 40 + 10), cz + d[2] * (cells * 40 + 10))
			if out == nil and n.room(p) == nil then out = p end
		end
	end
	truthy(out ~= nil, "set-up: a spot outside the manor, 30 studs past its outer wall")
	out = out or n.world(cx, cz + 5000)
	truthy(n.room(out) == nil, "set-up: ...in no room at all")
	ctx.hrp.CFrame = CFrame.new(out)
	-- wait out the clock, in safety
	local left = n.need + 0.6 - (h.scheduler:now() - began)
	wait(math.max(left, 1.2))
	truthy(h.scheduler:now() - began > n.need, string.format("set-up: the night's clock is past the shortest crossing (%.2f s)", n.need))
	-- IN: the exit room, at the door, and press
	ctx.hrp.CFrame = CFrame.new(n.stand)
	n.prompt.Triggered:Fire(me)
	wait(0.3)

	eq(#noticesOf(me, "EXTRACTED"), 0, "the exploit does NOT get out: no night is survived")
	wait(Config.BeatSeconds + 0.6)
	eq(stateOf(me).night, 7, "...still night 7")
	eq(stateOf(me).best, 6, "...the best night is still 6")
	eq(stateOf(me).phase, "DAY", "...and the night is over: back in the safehouse")
	eq(stateOf(me).stash, 0, "...with nothing banked from the bag, Lockboxes or not")
	eq(#noticesOf(me, "CAUGHT"), 0, "CONTROL: it was not the Nightwatcher that ended it")
	-- told why, in the notice's TEXT
	local why = nil
	for _, p in allNotices(me) do
		if string.find(tostring(p.text), "VOID", 1, true) then why = p end
	end
	truthy(why ~= nil, "the player is told the night is VOID")
	truthy(why ~= nil and string.find(string.lower(tostring(why.text)), "outside", 1, true) ~= nil,
		"...and why, in the notice's own text: outside the manor (" .. tostring(why and why.text) .. ")")
	-- nothing reached a store
	wait(Config.Save.AutosaveSeconds + 1)
	eq(#boardWrites, writesBefore, "NOTHING is written to the board's store")
	eq(nightOn(ME), 6, "...which still holds night 6")
	eq(saved(ME).best, 6, "...and the saved profile's best night is still 6")
	eq(saved(ME).night, 7, "...on night 7")
end

--======================================================================= 2. an honest walk
section("2. AN HONEST WALK to the exit is counted")

do
	local began = h.scheduler:now()
	ctx.pressDoor()
	wait(0.3)
	eq(stateOf(me).phase, "NIGHT", "set-up: night 7 again")
	local n = nightOf(me)
	local pts = routeOf(n)
	local total = lengthOf(pts)
	print(string.format("  the walk: %.0f studs through %d doorways; the clock asks for %.2f s", total, #pts - 2, n.need))
	walk(me, pts, 0, total)
	truthy(h.scheduler:now() - began >= n.need, string.format("the walk at WalkSpeed took %.1f s, longer than the clock asks", h.scheduler:now() - began))
	eq(stateOf(me).phase, "NIGHT", "walking the whole way at WalkSpeed never voided the night")
	n.prompt.Triggered:Fire(me)
	wait(0.3)
	eq(#noticesOf(me, "EXTRACTED"), 1, "at the door after an honest walk: OUT")
	eq(stateOf(me).night, 8, "...on to night 8")
	eq(stateOf(me).best, 7, "...and the best night is 7")
	eq(#noticesOf(me, "CAUGHT"), 0, "CONTROL: never caught")
	wait(Config.BeatSeconds + 0.6)
	if nightOn(ME) ~= 7 then wait(Config.Save.AutosaveSeconds * 2 + 1) end -- at most one board write per 30 s
	eq(nightOn(ME), 7, "the board's store holds night 7 for this player")
	eq(stateOf(me).phase, "DAY", "set-up: back in the safehouse")
end

--======================================================================= 3 - 5. a long manor: the jump, the lag gap, a respawn
-- Night 120's public manor (the server's own PublicLayouts switch): its walk is over 170 studs, more than twice what
-- the bank can ever hold, so a hop from the foyer to the door is a JUMP however long the wait.
SS.NightwatchSecrets:SetAttribute("PublicLayouts", true)
ctx.store:SetAsync("u_" .. LONG, { data = { night = 120, stash = 0, best = 119, bestAt = 1781000000, levels = {} } })
local long = h:join("Longwalker", LONG)
h.Players:simulateSpawn(long, h.workspace)
wait(1)

section("3. inside all along, then a teleport to the door and E in the same tick")
do
	eq(stateOf(long).night, 120, "set-up: a second player on night 120")
	settleBoard(LONG, 119)
	local writesBefore = #boardWrites
	local began = h.scheduler:now()
	pressDoorAs(long)
	wait(0.3)
	local n = nightOf(long)
	local total = lengthOf(routeOf(n))
	truthy(total > 150, string.format("set-up: night 120's walk is %.0f studs", total))
	wait(n.need + 0.6 - (h.scheduler:now() - began)) -- in the foyer, in a room, the whole time
	eq(stateOf(long).phase, "NIGHT", "standing in the foyer is not a void, however long")
	local denied = #noticesOf(long, "DENIED")
	hrpOf(long).CFrame = CFrame.new(n.stand)
	n.prompt.Triggered:Fire(long) -- no tick in between: the press itself has to be judged
	wait(0.3)
	eq(#noticesOf(long, "EXTRACTED"), 0, "teleport to the door and press: NOT out")
	local why = nil
	for _, p in allNotices(long) do
		if string.find(tostring(p.text), "VOID", 1, true) then why = p end
	end
	truthy(why ~= nil and string.find(string.lower(tostring(why.text)), "faster", 1, true) ~= nil,
		"...the night is VOID, and the text says why: faster than a walk (" .. tostring(why and why.text) .. ")")
	eq(#noticesOf(long, "DENIED"), denied, "...(a void, not the exit's own 'too soon' or 'too far')")
	wait(Config.BeatSeconds + 0.6)
	eq(stateOf(long).night, 120, "...still night 120")
	eq(stateOf(long).best, 119, "...best still 119")
	eq(#noticesOf(long, "CAUGHT"), 0, "CONTROL: never caught")
	wait(Config.Save.AutosaveSeconds + 1)
	eq(#boardWrites, writesBefore, "NOTHING is written to the board's store")
	eq(nightOn(LONG), 119, "...which still holds night 119")
	eq(saved(LONG).best, 119, "...and the saved best is still 119")
end

section("4. an honest walk with a 3 s lag gap in the middle is counted")
do
	pressDoorAs(long)
	wait(0.3)
	eq(stateOf(long).phase, "NIGHT", "set-up: night 120 again")
	local n = nightOf(long)
	local pts = routeOf(n)
	local total = lengthOf(pts)
	walk(long, pts, 0, total, { 40, 3 }) -- 40 studs in: 3 s of nothing, then 60 studs in one sample
	eq(stateOf(long).phase, "NIGHT", "a 3 s gap made up in one sample (60 studs along the walk) is not a void")
	n.prompt.Triggered:Fire(long)
	wait(0.3)
	eq(#noticesOf(long, "EXTRACTED"), 1, "...and the walk counts: OUT")
	eq(stateOf(long).night, 121, "...on to night 121")
	wait(1)
	if nightOn(LONG) ~= 120 then wait(Config.Save.AutosaveSeconds * 2 + 1) end -- at most one board write per 30 s
	eq(nightOn(LONG), 120, "the board's store holds night 120 for them")
	wait(Config.BeatSeconds + 0.6)
end

section("5. a respawn deep into a night is not a void")
do
	pressDoorAs(long)
	wait(0.3)
	eq(stateOf(long).phase, "NIGHT", "set-up: night 121")
	local n = nightOf(long)
	local pts = routeOf(n)
	local total = lengthOf(pts)
	local deep = total - 20
	truthy(deep > Config.Guard.JumpSlack + V * (1 + Config.Guard.SpeedSlack) * Config.Guard.LagSeconds + 10,
		string.format("set-up: night 121's walk is %.0f studs; %.0f studs in is further from the foyer than the bank ever holds", total, deep))
	walk(long, pts, 0, deep)
	eq(stateOf(long).phase, "NIGHT", "set-up: deep in night 121, on foot")
	-- It DIES there, running (a reset). A dead root does not collide: it drops through the floor and drifts on, out
	-- through the wall, for the seconds before the respawn. That is not a teleport and not hiding: not judged.
	local oldHrp = hrpOf(long)
	long.Character:FindFirstChildOfClass("Humanoid").Health = 0
	local drift = n.world(0, 0)
	for cells = 1, 12 do
		local p = oldHrp.Position + Vector3.new(cells * 40, 0, 0)
		if n.room(p) == nil then drift = p; break end
	end
	truthy(n.room(drift) == nil, "set-up: the dead root has drifted out of the manor")
	oldHrp.CFrame = CFrame.new(drift)
	wait(1.5)
	eq(stateOf(long).phase, "NIGHT", "a dead character's root drifting outside for 1.5 s does not void the night")
	-- ...but a dead character cannot use the exit either (it is not judged, so it is never at the door)
	local deniedBefore = #noticesOf(long, "DENIED")
	oldHrp.CFrame = CFrame.new(n.stand)
	n.prompt.Triggered:Fire(long)
	wait(0.2)
	eq(#noticesOf(long, "EXTRACTED"), 1, "a DEAD character at the door does not get out")
	eq(#noticesOf(long, "DENIED"), deniedBefore + 1, "...it is told to stand at the exit")
	eq(stateOf(long).phase, "NIGHT", "...and the night goes on")
	-- The character is replaced. CharacterAdded fires with the model unparented at the world origin; a frame later
	-- the engine parents it and drops it on the safehouse's SpawnLocation; the server's placement then wins.
	local char = h.Players:simulateSpawn(long, h.workspace)
	wait(2.5)
	eq(stateOf(long).phase, "NIGHT", "a respawn does not void the night (the server moved the character, not the player)")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	truthy(n.room(hrp.Position) == n.plan.entranceId, "...and the new character stands in the foyer")
	walk(long, pts, 0, total)
	eq(stateOf(long).phase, "NIGHT", "...and the walk from there is clean")
	n.prompt.Triggered:Fire(long)
	wait(0.3)
	eq(#noticesOf(long, "EXTRACTED"), 2, "...and counts: OUT")
	eq(stateOf(long).night, 122, "...on to night 122")
	eq(#noticesOf(long, "CAUGHT"), 0, "CONTROL: never caught")
end
SS.NightwatchSecrets:SetAttribute("PublicLayouts", nil)

eq(ctx.serverCalls, 0, "no client ever fired a remote at the server")
ctx.finish("nightwatchmanor posguard")
