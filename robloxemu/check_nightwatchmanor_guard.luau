-- Nightwatch Manor — the manor's secret, and the guard on the way out. Run: luau check_nightwatchmanor_guard.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- docs/complete-game-standard.md §1: "Nothing secret replicates ... A seed a player could memorise gets a server-only
-- salt, and a salt on a 32-bit seed that also drives visible geometry is not enough." Until 2026-10-01 night N's manor
-- was Manor.plan(Rng.new(WorldSeed * A + N * B)): Config and Manor ship to every client, so anyone could compute every
-- night's rooms, relics, exit and patrol ahead of time. Now the server plans from two 32-bit halves of its own
-- (Salt.luau, 2^64 states), drawn once per player per night per SESSION: a retry after being caught is the same manor
-- (you learn it, the way a person does), a new night or a new session is a new one, and nobody can compute any of them.
--
-- §3: the board's metric (the best night survived) must be one a script cannot inflate. The only way to survive a
-- night is the Servants' Exit, and the client moves its own character, so the exit opens only to a character the
-- SERVER measures standing at it, after the night has run the shortest walk there at WalkSpeed (Crossing.luau). A
-- refusal says why.
--
-- This boots the REAL server and clients and checks, in the built world:
--   1. the halves live only in ServerStorage: no Instance name, attribute or remote payload anywhere else carries them;
--   2. the manor standing IS the salted plan, and the public seed does not predict it;
--   3. per player, per night, per session: a retry is the same manor; the next night, a rejoin and another player
--      on the same night are not;
--   4. the server's own switch back to public layouts (for the thumbnail recipe and the layout-bound checks);
--   5. the guard: too soon is refused and says how long is left, too far is refused and says where to stand, the
--      haul survives a refusal, and standing at the door after the shortest walk gets you out.

local Kit = require("./check_nightwatchmanor_kit")
local DT = require("./emu/datatypes")
local Vector3, CFrame = DT.Vector3, DT.CFrame

local ME = 4242
local ctx = Kit.boot({ name = "nwm-guard", userId = ME, profile = { night = 3, stash = 0, best = 2, levels = {} } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local RS = ctx.RS
local Manor = h:_require(RS:FindFirstChild("Manor"))
local Rng = h:_require(RS:FindFirstChild("Rng"))
local Salt = h:_require(RS:FindFirstChild("Salt"))
local Crossing = h:_require(RS:FindFirstChild("Crossing"))
local SS = h.game:GetService("ServerStorage")
local SIZE = Config.Manor.RoomSize

local function section(s) print("== " .. s) end

-- the server's record for a player: night, a, b (a == "public" for the public seed)
local function record(uid: number): (number?, string?, string?)
	local secrets = SS:FindFirstChild("NightwatchSecrets")
	local rec = secrets and secrets:GetAttribute("u_" .. uid)
	if type(rec) ~= "string" then return nil, nil, nil end
	local n, a, b = string.match(rec, "^(%d+):(%d+):(%d+)$")
	if n then return tonumber(n), a, b end
	local pn = string.match(rec, "^(%d+):public$")
	if pn then return tonumber(pn), "public", nil end
	return nil, nil, nil
end

-- A manor as a string: every room's cell relative to the foyer and its kind, the exit room's cell and the exit door's
-- side. From the BUILT world (folders and floors) or from a plan; equal strings are the same manor.
local function builtSig(manor): string
	if not manor then return "none" end
	local rooms, foyer = {}, nil
	for _, f in manor:GetChildren() do
		local kind = string.match(tostring(f.Name), "^Room%d+_(%a+)$")
		local floor = kind and f:FindFirstChild("Floor")
		if floor then
			table.insert(rooms, { kind = kind, x = floor.Position.X, z = floor.Position.Z })
			if kind == "foyer" then foyer = floor.Position end
		end
	end
	if not foyer then return "nofoyer" end
	local out = {}
	for _, r in rooms do
		table.insert(out, string.format("%d,%d,%s", math.floor((r.x - foyer.X) / SIZE + 0.5), math.floor((r.z - foyer.Z) / SIZE + 0.5), r.kind))
	end
	table.sort(out)
	local door = manor:FindFirstChild("ExitDoor")
	local ex = door and string.format("exit %.0f,%.0f", door.Position.X - foyer.X, door.Position.Z - foyer.Z) or "noexit"
	return table.concat(out, ";") .. "|" .. ex
end
local function planSig(plan): string
	local e = Manor.roomById(plan, plan.entranceId)
	local out = {}
	for _, r in plan.rooms do
		table.insert(out, string.format("%d,%d,%s", r.gx - e.gx, r.gz - e.gz, r.kind))
	end
	table.sort(out)
	local dx, dz = Crossing.exitDoor(Config, plan, Manor)
	return table.concat(out, ";") .. "|" .. string.format("exit %.0f,%.0f", dx - e.gx * SIZE, dz - e.gz * SIZE)
end
local function publicPlan(night: number)
	return Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
end

local function noticesOf(plr, kind: string): { any }
	local out = {}
	for _, s in ctx.noticeRemote:sentTo(plr) do
		local p = s.args[1]
		if type(p) == "table" and p.kind == kind then table.insert(out, p) end
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
local function pressDoorAs(plr)
	local house = h.workspace:FindFirstChild("Zone_" .. plr.UserId):FindFirstChild("Safehouse")
	house.ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
end
local function manorOf(plr)
	local z = h.workspace:FindFirstChild("Zone_" .. plr.UserId)
	return z and z:FindFirstChild("Manor")
end

--======================================================================= 1. the halves are the server's alone
section("1. the halves live in ServerStorage and nowhere else")

local secrets = SS:FindFirstChild("NightwatchSecrets")
truthy(secrets ~= nil, "the server keeps its manor records in ServerStorage.NightwatchSecrets")
eq(secrets and secrets.Parent, SS, "...under ServerStorage, which never replicates to a client")
truthy(secrets == nil or secrets:GetAttribute("PublicLayouts") ~= true, "public layouts are OFF unless somebody switches them on")

ctx.pressDoor()
ctx.seconds(0.6, 0.1)
local n1, a1, b1 = record(ME)
eq(n1, 3, "entering night 3 recorded the manor standing for this player (night 3)")
truthy(a1 ~= nil and a1 ~= "public" and b1 ~= nil, "...planned from two salt halves, not the public seed (" .. tostring(a1) .. ", " .. tostring(b1) .. ")")
truthy(a1 ~= nil and b1 ~= nil and Salt.valid(tonumber(a1), tonumber(b1)), "each half a whole number in [0, 2^32)")

-- every Instance a client could see (all but ServerStorage and ServerScriptService), every attribute, and every
-- payload the server ever sent: none carries a half
local function leaks(a: string, b: string): (number, string?)
	local found, example = 0, nil
	local function hit(where: string, v: any)
		local s = if type(v) == "number" then string.format("%.0f", v) else tostring(v)
		if string.find(s, a, 1, true) or string.find(s, b, 1, true) then
			found += 1
			example = example or where
		end
	end
	local hidden = { [SS] = true, [h.game:GetService("ServerScriptService")] = true }
	local function walk(inst)
		if hidden[inst] then return end
		hit(inst:GetFullName() .. " (name)", inst.Name)
		for k, v in inst:GetAttributes() do
			hit(inst:GetFullName() .. "@" .. k, k)
			hit(inst:GetFullName() .. "@" .. k, v)
		end
		for _, c in inst:GetChildren() do walk(c) end
	end
	walk(h.game)
	local function deep(where: string, v: any, depth: number)
		if depth > 8 then return end
		if type(v) == "table" then
			for k, x in v do
				deep(where .. "." .. tostring(k), k, depth + 1)
				deep(where .. "." .. tostring(k), x, depth + 1)
			end
		elseif type(v) == "number" or type(v) == "string" then
			hit(where, v)
		end
	end
	for _, r in ctx.remotes:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			for i, s in r:getSent() do deep(r.Name .. "#" .. i, s.args, 0) end
		end
	end
	return found, example
end
do
	local found, example = leaks(a1 or "?", b1 or "?")
	eq(found, 0, "no Instance name, attribute or remote payload outside ServerStorage carries either half (" .. tostring(example) .. ")")
	-- CONTROL: the scan does see the halves where they are (it is not blind)
	local seen = 0
	for k, v in (secrets and secrets:GetAttributes() or {}) do
		if type(v) == "string" and string.find(v, a1 or "?", 1, true) then seen += 1 end
		local _ = k
	end
	eq(seen, 1, "CONTROL: the halves are in ServerStorage's record (the scan above would have found them anywhere else)")
end

--======================================================================= 2. the manor IS the salted plan
section("2. the manor standing is the salted plan, and the public seed does not predict it")

local sig1 = builtSig(ctx.manor())
do
	local plan = ctx.plan()
	truthy(plan ~= nil, "the record rebuilds a plan")
	eq(sig1, plan and planSig(plan) or "noplan", "every room, its kind and the exit door are where Manor.plan(Salt.new(a, b)) put them")
	local pub = planSig(publicPlan(3))
	truthy(sig1 ~= pub, "...and NOT where the public seed would have put them (what a client can compute predicts nothing)")
	local peds = 0
	for _, c in ctx.manor():GetChildren() do
		if string.match(tostring(c.Name), "^Pedestal_") then peds += 1 end
	end
	eq(peds, plan and #plan.relics or -1, "one pedestal per relic of that plan")
end

--======================================================================= 3. per player, per night, per session
section("3. a retry is the same manor; a new night, a rejoin or another player is not")

-- caught: walk into the Nightwatcher
do
	local w = ctx.manor() and ctx.manor():FindFirstChild("Nightwatcher")
	truthy(w ~= nil, "set-up: night 3 has its Nightwatcher")
	if w then ctx.hrp.CFrame = CFrame.new(w:GetPivot().Position) end
	ctx.seconds(0.5, 0.1)
	eq(#noticesOf(ctx.me, "CAUGHT"), 1, "set-up: caught on night 3")
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
	eq(ctx.lastState().phase, "DAY", "set-up: back in the safehouse")
	eq(ctx.lastState().night, 3, "set-up: still night 3 (being caught never advances it)")
end
ctx.pressDoor()
ctx.seconds(0.6, 0.1)
do
	local n2, a2, b2 = record(ME)
	eq(n2, 3, "the retry is night 3")
	truthy(a2 == a1 and b2 == b1, "the retry is planned from the SAME halves: the manor you were caught in, to learn")
	eq(builtSig(ctx.manor()), sig1, "...and the same rooms, kinds and exit stand in the world")
end
-- ...but not forever. A salted manor can be one a player keeps getting caught in (Pacing.spec: 2 of 31 model players
-- were stuck on one night for the rest of 200 minutes when a retry was always the same manor). After Config.Manor.ShiftAfterFails
-- failures in a row in the same halls, the manor SHIFTS: new halves, same night, and the player is told.
do
	local shiftAfter = Config.Manor.ShiftAfterFails
	eq(shiftAfter, 3, "the manor shifts after 3 failures in a row (Config.Manor.ShiftAfterFails)")
	local function caught()
		local w = ctx.manor() and ctx.manor():FindFirstChild("Nightwatcher")
		if w then ctx.hrp.CFrame = CFrame.new(w:GetPivot().Position) end
		ctx.seconds(0.5, 0.1)
		ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
	end
	-- caught once already (above); fail until one short of the shift, retrying the same manor each time
	for i = 2, (shiftAfter or 3) - 1 do
		caught()
		ctx.pressDoor()
		ctx.seconds(0.6, 0.1)
		local _, ai, bi = record(ME)
		truthy(ai == a1 and bi == b1, string.format("failure %d: the retry is still the same manor", i))
	end
	local nightNotices = #noticesOf(ctx.me, "NIGHT")
	caught()
	eq(#noticesOf(ctx.me, "CAUGHT"), shiftAfter, "set-up: caught " .. tostring(shiftAfter) .. " times on night 3")
	ctx.pressDoor()
	ctx.seconds(0.6, 0.1)
	local n3, a3, b3 = record(ME)
	eq(n3, 3, "still night 3 (failing never advances it)")
	truthy(a3 ~= nil and a3 ~= "public" and not (a3 == a1 and b3 == b1), "after the third failure the manor SHIFTS: new halves")
	truthy(builtSig(ctx.manor()) ~= sig1, "...and different halls stand in the world")
	local nn = noticesOf(ctx.me, "NIGHT")
	local shiftNote = nn[#nn]
	eq(#nn, nightNotices + 1, "set-up: the night's own notice came")
	truthy(shiftNote and string.find(string.lower(tostring(shiftNote.detail)), "shifted", 1, true) ~= nil,
		"...and it tells the player the manor has shifted (" .. tostring(shiftNote and shiftNote.detail) .. ")")
	a1, b1, sig1 = a3, b3, builtSig(ctx.manor())
end
-- survive night 3: night 4 is a new manor
local pressedOut = ctx.pressExit(0.1)
truthy(pressedOut, "set-up: escaped night 3 at the door")
ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
eq(ctx.lastState().night, 4, "set-up: on to night 4")
ctx.pressDoor()
ctx.seconds(0.6, 0.1)
local n4, a4, b4 = record(ME)
eq(n4, 4, "night 4 has its own record")
truthy(a4 ~= nil and a4 ~= "public" and not (a4 == a1 and b4 == b1), "...from new halves")
local sig4 = builtSig(ctx.manor())

-- another player on the same night: their own manor
local other = h:join("Lantern", 5151)
h.Players:simulateSpawn(other, h.workspace)
ctx.seconds(1, 0.1)
do
	-- a fresh profile starts at Config.Night.StartNight; whatever night it is, its halves must be its own
	pressDoorAs(other)
	ctx.seconds(0.6, 0.1)
	local on, oa, ob = record(5151)
	truthy(on ~= nil and oa ~= nil and oa ~= "public", "another player's night is salted too")
	truthy(not (oa == a4 and ob == b4) and not (oa == a1 and ob == b1), "...with halves of their own")
	h:leave(other)
	ctx.seconds(1, 0.1)
	eq(record(5151), nil, "...and their record goes when they leave")
end

-- a rejoin: a new session plans night 4 afresh
do
	h:leave(ctx.me)
	ctx.seconds(1, 0.1)
	eq(record(ME), nil, "leaving drops the record (it was only ever this session's)")
	local again = h:join("Nightwalker", ME)
	h.Players:simulateSpawn(again, h.workspace)
	ctx.seconds(1, 0.1)
	eq(stateOf(again).night, 4, "set-up: rejoined on night 4")
	pressDoorAs(again)
	ctx.seconds(0.6, 0.1)
	local rn, ra, rb = record(ME)
	eq(rn, 4, "the rejoin's night 4 has a record")
	truthy(ra ~= nil and ra ~= "public" and not (ra == a4 and rb == b4), "...from new halves: a new session is a new manor")
	truthy(builtSig(manorOf(again)) ~= sig4 or (ra == a4 and rb == b4), "...and the world shows it")
	ctx.me = again -- the rest of this check plays as the rejoined player
	local char = again.Character
	ctx.char = char
	ctx.hrp = char and char:FindFirstChild("HumanoidRootPart")
end

--======================================================================= 4. the server's switch back to public layouts
section("4. the server's own switch: public layouts")

do
	local me = ctx.me
	-- leave the night (caught), switch, come back
	local w = manorOf(me) and manorOf(me):FindFirstChild("Nightwatcher")
	if w then ctx.hrp.CFrame = CFrame.new(w:GetPivot().Position) end
	ctx.seconds(0.5, 0.1)
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
	eq(stateOf(me).phase, "DAY", "set-up: back in the safehouse")
	SS.NightwatchSecrets:SetAttribute("PublicLayouts", true)
	pressDoorAs(me)
	ctx.seconds(0.6, 0.1)
	local pn, pa = record(ME)
	truthy(pn == 4 and pa == "public", "with PublicLayouts set (Studio's command bar, server side), the night is planned from the public seed")
	eq(builtSig(manorOf(me)), planSig(publicPlan(4)), "...and the public plan of night 4 is what stands")
	local w2 = manorOf(me) and manorOf(me):FindFirstChild("Nightwatcher")
	if w2 then ctx.hrp.CFrame = CFrame.new(w2:GetPivot().Position) end
	ctx.seconds(Config.BeatSeconds + 1.1, 0.1)
	SS.NightwatchSecrets:SetAttribute("PublicLayouts", nil)
end

--======================================================================= 5. the guard on the Servants' Exit
section("5. the Servants' Exit opens only at the door, after the shortest walk")

do
	local me = ctx.me
	-- The Nightwatcher is blinded in memory for this section (SightRange 0, CatchRadius 0: both then need it exactly on
	-- the player's point): the foyer's start point lies on its patrol line, and this section is about the door, not
	-- the chase. Put back at the end.
	local W = Config.Watcher
	local sight, catch = W.SightRange, W.CatchRadius
	W.SightRange, W.CatchRadius = 0, 0
	local caughtBefore = #noticesOf(me, "CAUGHT")
	local began = h.scheduler:now()
	pressDoorAs(me)
	ctx.seconds(0.6, 0.1)
	local m = manorOf(me)
	local door = m and m:FindFirstChild("ExitDoor")
	local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
	truthy(prompt ~= nil, "set-up: night 4 again, salted again, with its exit")
	eq(prompt and prompt.MaxActivationDistance, Config.Guard.ExitPromptDistance, "the ESCAPE prompt's reach is Config.Guard.ExitPromptDistance")
	eq(Config.Guard.ExitPromptDistance, 12, "...12 studs, like every prompt in the game")
	local need = Kit.crossSeconds(h, ME)
	print(string.format("  this manor's shortest crossing: %.2f s of night", need))
	truthy(need > 1, string.format("the shortest walk to the door takes over a second (%.2f s)", need))

	-- take a relic first: a refusal must not cost the haul
	for _, c in m:GetChildren() do
		if string.match(tostring(c.Name), "^Pedestal_") then
			c:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
			break
		end
	end
	ctx.seconds(0.3, 0.1)
	eq(stateOf(me).carried, 1, "set-up: a relic in the bag")

	-- too soon: a teleport straight to the door
	local stand = Kit.exitStand(m)
	ctx.hrp.CFrame = CFrame.new(stand)
	local deniedBefore = #noticesOf(me, "DENIED")
	prompt.Triggered:Fire(me)
	ctx.seconds(0.2, 0.1)
	eq(stateOf(me).phase, "NIGHT", "at the door " .. string.format("%.1f", h.scheduler:now() - began) .. " s into the night: refused, the night goes on")
	local d = noticesOf(me, "DENIED")
	local last = d[#d]
	eq(#d, deniedBefore + 1, "...and the player is told why (no silent no-op)")
	-- the HUD shows a DENIED notice's TEXT only (Hud.client: showToast(text, MUTED, nil, ...)), so the why goes there
	truthy(last and string.find(tostring(last.text), "opens in", 1, true) ~= nil,
		"...and when the exit opens, in the toast's own text (the HUD drops a DENIED detail) (" .. tostring(last and last.text) .. ")")
	eq(stateOf(me).carried, 1, "...and the haul is still in the bag")

	-- long enough, but not at the door
	local left = need + 0.3 - (h.scheduler:now() - began)
	if left > 0 then ctx.seconds(left, 0.1) end
	local entrance = nil
	for _, f in m:GetChildren() do
		if string.match(tostring(f.Name), "^Room%d+_foyer$") then entrance = f:FindFirstChild("Floor") end
	end
	ctx.hrp.CFrame = CFrame.new(entrance.Position + Vector3.new(0, 4, 12))
	local far = (ctx.hrp.Position - door.Position).Magnitude
	prompt.Triggered:Fire(me)
	ctx.seconds(0.2, 0.1)
	eq(stateOf(me).phase, "NIGHT", string.format("long enough, but %.0f studs from the door (a trigger from across the manor): refused", far))
	d = noticesOf(me, "DENIED")
	last = d[#d]
	truthy(last and string.find(tostring(last.text), "Stand at the Servants' Exit", 1, true) ~= nil, "...and told to stand at the exit (" .. tostring(last and last.text) .. ")")

	-- long enough, close enough, but through the wall: just outside the exit room, behind the door (the prompt needs no
	-- line of sight, so before pass 2 this pressed ESCAPE from the room next door)
	do
		local exitFloor = nil
		local best = math.huge
		for _, f in m:GetChildren() do
			local fl = string.match(tostring(f.Name), "^Room%d+_") and f:FindFirstChild("Floor")
			if fl then
				local dd = (Vector3.new(fl.Position.X, 0, fl.Position.Z) - Vector3.new(door.Position.X, 0, door.Position.Z)).Magnitude
				if dd < best then best, exitFloor = dd, fl end
			end
		end
		local out = Vector3.new(door.Position.X - exitFloor.Position.X, 0, door.Position.Z - exitFloor.Position.Z).Unit
		local behind = door.Position + out * 8 -- 22 studs from the exit room's centre: past its wall (20)
		ctx.hrp.CFrame = CFrame.new(behind.X, exitFloor.Position.Y + 4, behind.Z)
		local dd = (ctx.hrp.Position - door.Position).Magnitude
		truthy(dd <= Config.Guard.ExitPromptDistance, string.format("set-up: behind the wall, %.1f studs from the door (inside the prompt's reach)", dd))
		local before = #noticesOf(me, "DENIED")
		prompt.Triggered:Fire(me)
		ctx.seconds(0.2, 0.1)
		eq(stateOf(me).phase, "NIGHT", "within reach of the door but through the wall, outside the exit room: refused")
		local dn = noticesOf(me, "DENIED")
		truthy(#dn == before + 1 and string.find(tostring(dn[#dn].text), "Stand at the Servants' Exit", 1, true) ~= nil,
			"...and told to stand at the exit (" .. tostring(dn[#dn] and dn[#dn].text) .. ")")
	end

	-- at the door, after the shortest walk: out
	local stashBefore, worth = stateOf(me).stash, stateOf(me).carriedWorth
	ctx.hrp.CFrame = CFrame.new(stand)
	prompt.Triggered:Fire(me)
	ctx.seconds(0.3, 0.1)
	eq(#noticesOf(me, "EXTRACTED"), 1, "at the door after the shortest walk: out")
	eq(stateOf(me).night, 5, "...on to night 5")
	eq(stateOf(me).stash, stashBefore + worth, "...with the haul the refusals left alone")
	eq(#noticesOf(me, "CAUGHT"), caughtBefore, "CONTROL: nothing in this section was the chase (never caught)")
	W.SightRange, W.CatchRadius = sight, catch
end

eq(ctx.serverCalls, 0, "no client ever fired a remote at the server")
ctx.finish("nightwatchmanor guard")
