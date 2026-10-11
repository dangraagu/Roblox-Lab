-- check_nightwatchmanor_kit.luau — shared setup for the check_nightwatchmanor_*.luau checks. Not a check
-- itself (running it does nothing): each check requires it, boots the REAL server and the REAL clients
-- (Hud.client + Haunt.client) through the emulator, and drives frames the way Roblox would.
--
-- Headless limits, stated once for all of them: nothing renders and there is no physics. Frames are
-- driven by firing RunService.RenderStepped; the character does not move unless the check moves it; a
-- knock is observed as the velocity and PlatformStand the client writes. Whether any of it LOOKS right is
-- on EYECANDY.md's Studio list.
--
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau

local Harness = require("./emu/harness")
-- A required module has its own globals table in the luau CLI, so the harness's Roblox globals are not
-- visible in here; take the same datatype module the harness installs (it is one cached instance).
local DT = require("./emu/datatypes")
local Enum, Vector3, CFrame = DT.Enum, DT.Vector3, DT.CFrame

local Kit = {}

--==================================================================== the Servants' Exit, the way a player uses it
-- Since the highscore board (2026-10-01) the exit opens only to a character whose root stands within the prompt's
-- reach of the door, once the night has run the shortest possible walk there (Crossing.luau). These helpers let a
-- check extract honestly: rebuild the manor standing now from the server's own ServerStorage record, work out that
-- minimum, stand at the door, press.

-- The plan of `userId`'s manor standing now ("night:a:b" = Salt.new(a, b); "night:public" = the public seed).
function Kit.planOf(h: any, userId: number): any
	local secrets = h.game:GetService("ServerStorage"):FindFirstChild("NightwatchSecrets")
	local rec = secrets and secrets:GetAttribute("u_" .. userId)
	if type(rec) ~= "string" then return nil end
	local RS = h.ReplicatedStorage
	local Config = h:_require(RS:FindFirstChild("Config"))
	local Manor = h:_require(RS:FindFirstChild("Manor"))
	local night, a, b = string.match(rec, "^(%d+):(%d+):(%d+)$")
	if night then
		local Salt = h:_require(RS:FindFirstChild("Salt"))
		return Manor.plan(Salt.new(tonumber(a) :: number, tonumber(b) :: number), Config, tonumber(night) :: number)
	end
	local pn = string.match(rec, "^(%d+):public$")
	if pn then
		local Rng = h:_require(RS:FindFirstChild("Rng"))
		return Manor.plan(Rng.new(Manor.seedFor(Config, tonumber(pn) :: number)), Config, tonumber(pn) :: number)
	end
	return nil
end

-- The server's crossing minimum for that manor, in seconds of night.
function Kit.crossSeconds(h: any, userId: number): number
	local plan = Kit.planOf(h, userId)
	if not plan then return 0 end
	local RS = h.ReplicatedStorage
	local Crossing = h:_require(RS:FindFirstChild("Crossing"))
	return Crossing.minSeconds(h:_require(RS:FindFirstChild("Config")), plan, h:_require(RS:FindFirstChild("Manor")))
end

-- Where a player stands to use the exit: 4 studs from the door toward the exit room's middle, at root height.
function Kit.exitStand(manor: any): any
	local door = manor and manor:FindFirstChild("ExitDoor")
	if not door then return nil end
	local best, bestD = nil, nil
	for _, c in manor:GetChildren() do
		local f = string.match(tostring(c.Name), "^Room%d+_") and c:FindFirstChild("Floor")
		if f then
			local d = math.abs(f.Position.X - door.Position.X) + math.abs(f.Position.Z - door.Position.Z)
			if bestD == nil or d < bestD then best, bestD = f, d end
		end
	end
	if not best then return nil end
	local flat = Vector3.new(best.Position.X - door.Position.X, 0, best.Position.Z - door.Position.Z)
	local p = door.Position + flat.Unit * 4
	return Vector3.new(p.X, best.Position.Y + best.Size.Y / 2 + 3, p.Z)
end

-- Wait until `userId`'s night (entered at virtual time `since`) has run the crossing minimum, then press ESCAPE.
-- `advance(seconds)` drives time the caller's way (frames or h:advance). It waits STANDING AT THE EXIT, with the
-- Nightwatcher blinded in memory (Config.Watcher SightRange 0 and CatchRadius 0: both then need the watcher exactly on
-- the player's point, and the stand point is on the exit's outer face, which no patrol walks toward), and puts both
-- back before the press. These checks are about everything BUT the chase (check_walk and Chase.spec are the chase).
-- Pass 2 (2026-10-01): the first version waited at the night's start point with CatchRadius -1, which squares to a
-- 1-stud catch; the foyer's start point lies ON the patrol line to the foyer's +Z doorway, so night 7 was caught every
-- time (measured: "IT SEES YOU", "IT CAUGHT YOU" at 5.9 s). Returns whether ESCAPE was pressed on a standing door.
function Kit.extract(h: any, plr: any, userId: number, since: number, advance: (number) -> ()): boolean
	local zone = h.workspace:FindFirstChild("Zone_" .. userId)
	local manor = zone and zone:FindFirstChild("Manor")
	local door = manor and manor:FindFirstChild("ExitDoor")
	if not door then return false end
	local at = Kit.exitStand(manor)
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	local W = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Watcher
	local sight, catch = W.SightRange, W.CatchRadius
	-- This helper TELEPORTS to the door, which is what the position guard (PosGuard.luau) voids a night for: a check
	-- that extracts this way runs with the guard off from here on (Kit.posGuard). The guard's own check walks.
	Kit.posGuard(h, false)
	W.SightRange, W.CatchRadius = 0, 0
	if at and hrp then hrp.CFrame = CFrame.new(at) end
	local left = Kit.crossSeconds(h, userId) + 0.25 - (h.scheduler:now() - since)
	if left > 0 then advance(left) end
	W.SightRange, W.CatchRadius = sight, catch
	if door.Parent == nil then
		return false -- the night ended while waiting (it is the caller's to notice: the night does not advance)
	end
	if at and hrp then hrp.CFrame = CFrame.new(at) end -- a hazard may have knocked us off the spot
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return false end
	prompt.Triggered:Fire(plr)
	return true
end

-- Switch the position guard on or off in the running server's Config (see Kit.boot's posGuard). For the checks that
-- boot their own Harness.
function Kit.posGuard(h: any, on: boolean)
	local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
	if type(Config.Guard) == "table" then
		Config.Guard.PositionChecks = on
	end
end

-- opts = { name, userId, profile = { night, stash, best, levels } | nil, viewport = {w,h}, touch,
--          beforeClient = function(ctx) end (runs after the server boots and the player joins, before
--          the client scripts load: the place to change Config in memory), slowLoad = seconds | nil,
--          noSpawn = true | nil, publicLayouts = true | nil, posGuard = true | nil }
-- publicLayouts: plan every night from the old public seed (the server's ServerStorage switch, the one the
-- thumbnail recipe uses), for checks that find their rooms through Manor.plan(Rng.new(Manor.seedFor(...))). Without
-- it every night is a fresh server-salted manor, as in the game (Salt.luau); ctx.plan() rebuilds the one standing.
-- posGuard: keep the position guard (PosGuard.luau, 2026-10-11) as it ships. WITHOUT it the kit switches the guard
-- off in memory (Config.Guard.PositionChecks = false) once the server has booted: these checks place the character
-- by writing its CFrame (to the exit, onto the Nightwatcher, across the manor), which is exactly what the guard voids
-- a night for. The same reason, and the same way, Kit.extract blinds the Nightwatcher. The guard itself is
-- check_nightwatchmanor_posguard (the real server, as shipped) and tests/PosGuard.spec.luau.
function Kit.boot(opts: any)
	local h = Harness.new({
		bundle = require("./build/nightwatch-manor"),
		name = opts.name or "nightwatch-manor-haunt",
		viewport = opts.viewport or { 1280, 720 },
		touch = opts.touch == true,
	})
	local ctx = { h = h, passed = 0, failed = 0 }
	function ctx.eq(a, b, msg)
		if a == b then ctx.passed += 1 else
			ctx.failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
		end
	end
	function ctx.truthy(c, msg)
		if c then ctx.passed += 1 else ctx.failed += 1; print("FAIL: " .. msg) end
	end
	local ME = opts.userId or 4242
	ctx.ME = ME
	local store = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
	ctx.store = store
	if opts.profile then
		store:SetAsync("u_" .. ME, { data = opts.profile })
	end
	local g = h.scheduler:globals()
	if opts.slowLoad then
		local realUpdate = getmetatable(store).UpdateAsync
		store.UpdateAsync = function(self, key, fn)
			g.task.wait(opts.slowLoad)
			return realUpdate(self, key, fn)
		end
	end

	assert(h:tryRun("server/Main.server"))
	ctx.secrets = h.game:GetService("ServerStorage"):FindFirstChild("NightwatchSecrets")
	if opts.publicLayouts then
		assert(ctx.secrets ~= nil, "the server made no ServerStorage.NightwatchSecrets folder")
		ctx.secrets:SetAttribute("PublicLayouts", true)
	end
	h:advance(1)
	ctx.RS = h.ReplicatedStorage
	ctx.Config = h:_require(ctx.RS:FindFirstChild("Config"))
	if opts.posGuard ~= true then
		Kit.posGuard(h, false) -- (never switched ON here: with posGuard the check runs whatever Config ships)
	end
	ctx.remotes = ctx.RS:FindFirstChild("ManorRemotes")
	ctx.stateRemote = ctx.remotes:FindFirstChild("State")
	ctx.noticeRemote = ctx.remotes:FindFirstChild("Notice")
	-- the server's replicated surface, and a tap on every remote a client could fire at it
	ctx.remoteNames = {}
	for _, r in ctx.remotes:GetChildren() do table.insert(ctx.remoteNames, r.Name) end
	table.sort(ctx.remoteNames)
	ctx.serverCalls = 0
	for _, r in ctx.remotes:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			r.OnServerEvent:Connect(function() ctx.serverCalls += 1 end)
		end
	end
	-- the server's lighting, before any client runs
	ctx.serverLighting = {
		Ambient = h.Lighting.Ambient, OutdoorAmbient = h.Lighting.OutdoorAmbient, Brightness = h.Lighting.Brightness,
		ExposureCompensation = h.Lighting.ExposureCompensation,
	}
	local atm = h.Lighting:FindFirstChild("FxAtmosphere")
	ctx.serverAtmosphere = atm and { Density = atm.Density, Haze = atm.Haze, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Offset = atm.Offset }
	local cc = h.Lighting:FindFirstChild("FxColorCorrection")
	ctx.serverCC = cc and { Brightness = cc.Brightness, Contrast = cc.Contrast, Saturation = cc.Saturation, TintColor = cc.TintColor }
	local bl = h.Lighting:FindFirstChild("FxBloom")
	ctx.serverBloom = bl and { Intensity = bl.Intensity, Size = bl.Size, Threshold = bl.Threshold }

	local RunService = h.game:GetService("RunService")
	ctx.RunService = RunService
	local me
	if opts.slowLoad then
		g.task.spawn(function() me = h:join(opts.playerName or "Nightwalker", ME) end)
		h:advance(0.05)
		me = h.Players:GetPlayerByUserId(ME)
		-- the join is parked inside the server's DataStore call, before Harness.join got to give the
		-- player the PlayerGui (and LocalPlayer) Roblox gives them at once; do what it would have done
		if me:FindFirstChild("PlayerGui") == nil then
			local pg = h.instance.Instance.new("PlayerGui")
			pg.Name = "PlayerGui"
			pg.Parent = me
		end
		h.Players.LocalPlayer = me
	else
		me = h:join(opts.playerName or "Nightwalker", ME)
	end
	ctx.me = me
	local char = h.Players:simulateSpawn(me, h.workspace)
	ctx.char = char
	ctx.hrp = char:FindFirstChild("HumanoidRootPart")
	ctx.hum = char:FindFirstChildOfClass("Humanoid")
	ctx.hum.FloorMaterial = Enum.Material.WoodPlanks
	ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
	ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	if not opts.slowLoad then h:advance(0.5) end

	RunService:setIsServer(false) -- the scripts run from here on are client scripts
	if opts.beforeClient then opts.beforeClient(ctx) end
	local okHud, errHud = h:tryRun("client/Hud.client")
	ctx.truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
	local okHaunt, errHaunt = h:tryRun("client/Haunt.client")
	ctx.truthy(okHaunt, "Haunt.client loads (" .. tostring(errHaunt) .. ")")
	-- Roblox queues a RemoteEvent fired before a client connects and delivers it on connect; the
	-- emulator does not, so the server's join-time push (if it has happened) is replayed exactly.
	local sent = ctx.stateRemote:sentTo(me)
	if #sent > 0 then
		ctx.stateRemote:FireClient(me, sent[#sent].args[1])
	end

	ctx.folder = h.workspace:FindFirstChild("NightwatchLocal")
	local pg = me:FindFirstChild("PlayerGui")
	ctx.gui = pg and pg:FindFirstChild("NightwatchHaunt")
	ctx.root = ctx.gui and ctx.gui:FindFirstChild("Root")
	ctx.chip = ctx.root and ctx.root:FindFirstChild("BandChip")
	ctx.restBtn = ctx.root and ctx.root:FindFirstChild("RestButton")
	ctx.warning = ctx.root and ctx.root:FindFirstChild("HazardWarning")
	ctx.card = ctx.root and ctx.root:FindFirstChild("BandCard")
	ctx.cardSub = ctx.root and ctx.root:FindFirstChild("BandCardSub")
	ctx.hud = pg and pg:FindFirstChild("NightwatchHud")

	ctx.cam = h.workspace.CurrentCamera
	ctx.camYaw, ctx.camPitch = 0, math.rad(-15) -- the camera looks along (sin yaw, ., cos yaw)
	ctx.time = 0
	ctx.cards = {} -- every distinct card text shown, in order
	ctx.flashes = 0
	local lastCard = ""
	function ctx.placeCamera()
		local look = Vector3.new(math.sin(ctx.camYaw) * math.cos(ctx.camPitch), math.sin(ctx.camPitch), math.cos(ctx.camYaw) * math.cos(ctx.camPitch))
		local headPos = ctx.hrp.Position + Vector3.new(0, 1.5, 0)
		ctx.cam.CFrame = CFrame.lookAt(headPos - look * 12.5, headPos)
	end
	function ctx.frame(dt: number)
		ctx.placeCamera()
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		ctx.time += dt
		if ctx.card and ctx.card.Visible and ctx.card.Text ~= lastCard and ctx.card.Text ~= "" then
			lastCard = ctx.card.Text
			table.insert(ctx.cards, lastCard)
		elseif ctx.card and not ctx.card.Visible then
			lastCard = ""
		end
		if ctx.onFrame then ctx.onFrame(dt) end
	end
	function ctx.frames(n: number, dt: number?)
		for _ = 1, n do ctx.frame(dt or 1 / 30) end
	end
	function ctx.seconds(s: number, dt: number?)
		local step = dt or 1 / 30
		ctx.frames(math.max(1, math.floor(s / step + 0.5)), step)
	end
	function ctx.zone()
		return h.workspace:FindFirstChild("Zone_" .. ME)
	end
	function ctx.manor()
		local z = ctx.zone()
		return z and z:FindFirstChild("Manor")
	end
	function ctx.house()
		local z = ctx.zone()
		return z and z:FindFirstChild("Safehouse")
	end
	function ctx.lastState()
		local list = ctx.stateRemote:sentTo(me)
		for i = #list, 1, -1 do
			if type(list[i].args[1]) == "table" then return list[i].args[1] end
		end
		return nil
	end
	ctx.nightSince = 0 -- virtual time of the last ctx.pressDoor (where the crossing guard's clock starts)
	function ctx.pressDoor()
		ctx.nightSince = h.scheduler:now()
		ctx.house().ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
	end
	-- The plan of the manor standing now, and the server's crossing minimum for it (Kit.planOf / crossSeconds).
	function ctx.plan()
		return if ctx.manor() then Kit.planOf(h, ME) else nil
	end
	function ctx.crossSeconds(): number
		return Kit.crossSeconds(h, ME)
	end
	function ctx.exitStand(): Vector3?
		return Kit.exitStand(ctx.manor())
	end
	-- Press ESCAPE the way a player does: standing at the door (the server measures the root's distance to it), once
	-- the night has run the crossing guard's minimum since the last ctx.pressDoor (Kit.extract; frames run while it
	-- waits). Returns whether ESCAPE was pressed.
	function ctx.pressExit(dt: number?): boolean
		if not ctx.manor() then return false end
		return Kit.extract(h, me, ME, ctx.nightSince, function(s) ctx.seconds(s, dt) end)
	end
	-- Extract `n` nights through the real server: door, then (once the night has run the crossing guard's minimum,
	-- Kit.extract) the exit, then wait out the beat. Frames run throughout.
	function ctx.surviveNights(n: number, dt: number?)
		for _ = 1, n do
			ctx.pressDoor()
			ctx.seconds(0.6, dt)
			ctx.pressExit(dt)
			ctx.seconds(ctx.Config.BeatSeconds + 0.4, dt)
		end
	end
	-- What the client has parented under its folder right now.
	function ctx.count()
		local c = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0 }
		if not ctx.folder then return c end
		for _, d in ctx.folder:GetDescendants() do
			if d:IsA("BasePart") then c.parts += 1 end
			if d.ClassName == "ParticleEmitter" and d.Enabled then
				c.emitters += 1
				c.rate += d.Rate or 0
			end
			if d.ClassName == "PointLight" and d.Enabled then c.lights += 1 end
			if d.ClassName == "Beam" and d.Enabled then c.beams += 1 end
			if d.ClassName == "Trail" and d.Enabled then c.trails += 1 end
		end
		return c
	end
	-- Each frame: every budget in Config.Budget, asserted by the caller through ctx.budgetFails.
	ctx.peak = { parts = 0, emitters = 0, rate = 0, lights = 0 }
	ctx.budgetFails = 0
	ctx.budgetExample = nil
	function ctx.checkBudget(where: string)
		local c = ctx.count()
		local B = ctx.Config.Budget
		for _, k in { "parts", "emitters", "rate", "lights" } do
			if c[k] > ctx.peak[k] then ctx.peak[k] = c[k]; ctx.peak[k .. "At"] = where end
		end
		local over = c.parts > B.MaxParts or c.emitters > B.MaxEmitters or c.rate > B.MaxEmitterRate + 1e-6 or c.lights > B.MaxLights
		if over then
			ctx.budgetFails += 1
			ctx.budgetExample = ctx.budgetExample or string.format("%s: %d parts, %d emitters (%.0f/s), %d lights", where, c.parts, c.emitters, c.rate, c.lights)
		end
		return c
	end
	function ctx.finish(label: string)
		print("")
		for _, w in h.warnings do print("warning: " .. w) end
		ctx.eq(#h.warnings, 0, "no warnings from the server or the clients")
		for _, e in h:errors() do
			print("scheduler error: " .. e)
			ctx.failed += 1
		end
		print(string.format("%s: %d passed, %d failed", label, ctx.passed, ctx.failed))
		if ctx.failed > 0 then
			error(label .. " failed", 0)
		end
	end
	return ctx
end

return Kit
