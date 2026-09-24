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

-- opts = { name, userId, profile = { night, stash, best, levels } | nil, viewport = {w,h}, touch,
--          beforeClient = function(ctx) end (runs after the server boots and the player joins, before
--          the client scripts load: the place to change Config in memory), slowLoad = seconds | nil,
--          noSpawn = true | nil }
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
	h:advance(1)
	ctx.RS = h.ReplicatedStorage
	ctx.Config = h:_require(ctx.RS:FindFirstChild("Config"))
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
	function ctx.pressDoor()
		ctx.house().ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
	end
	function ctx.pressExit()
		local m = ctx.manor()
		local door = m and m:FindFirstChild("ExitDoor")
		if door then door:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me) end
	end
	-- Extract `n` nights through the real server: door, exit, wait out the beat. Frames run throughout.
	function ctx.surviveNights(n: number, dt: number?)
		for _ = 1, n do
			ctx.pressDoor()
			ctx.seconds(0.6, dt)
			ctx.pressExit()
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
