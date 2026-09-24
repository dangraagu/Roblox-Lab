-- Shared helpers for the labyrint-spill eye-candy checks (check_labyrintspill_*.luau). Not a check.
--
-- Boots the REAL server (server/MazeGame.server) with a seeded profile, joins one player, lets the
-- engine spawn them, runs the requested client scripts, and drives frames the way the
-- +1 Jump checks do: the camera is placed behind the character, RunService.RenderStepped is fired,
-- the virtual clock advances. Headless limits, stated: nothing renders and there is no physics; the
-- character only moves when a check moves it, and a knock is observed as the PlatformStand and
-- velocity the client writes.

local Harness = require("./emu/harness")
-- The harness installs Roblox globals into the RUNNER's globals, not into this module's, so this file
-- takes its datatypes straight from the emulator (the same module table the harness uses).
local DT = require("./emu/datatypes")
local Enum, Vector3, CFrame = DT.Enum, DT.Vector3, DT.CFrame

local Lib = {}

function Lib.counter(name: string)
	local c = { name = name, passed = 0, failed = 0 }
	function c.truthy(cond: any, msg: string)
		if cond then c.passed += 1 else c.failed += 1; print("FAIL: " .. msg) end
	end
	function c.eq(a: any, b: any, msg: string)
		if a == b then c.passed += 1 else
			c.failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
		end
	end
	function c.near(a: any, b: number, tol: number, msg: string)
		if type(a) == "number" and math.abs(a - b) <= tol then c.passed += 1 else
			c.failed += 1
			print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
		end
	end
	function c.finish(h: any)
		if h and #h:errors() > 0 then
			for _, e in h:errors() do
				print("scheduler error: " .. e)
				c.failed += 1
			end
		end
		print(string.format("%s: %d passed, %d failed", c.name, c.passed, c.failed))
		if c.failed > 0 then error(c.name .. " failed", 0) end
	end
	return c
end

-- Every client script the game ships, as the live game runs them.
Lib.ALL_CLIENTS = {
	"HudClient", "MinimapClient", "LeaderboardClient", "AssistClient", "AdminBroadcastClient", "ShopClient",
	"PerkClient", "LobbyClient", "GodModeClient", "LightingClient", "SoundClient", "Biome", "RestClient",
}
-- The same without SoundClient, for checks that FINISH levels: the emulator's Sound has no :Play(), and
-- the emulator calls a client's remote handler inline inside the server's FireClient, so SoundClient's
-- level-complete jingle would throw straight into the server's finishRun. That is an emulator gap
-- (robloxemu/emu is not ours to change), not a game defect; SoundClient plays sounds and nothing else.
Lib.CLIENTS_NO_SOUND = {
	"HudClient", "MinimapClient", "LeaderboardClient", "AssistClient", "AdminBroadcastClient", "ShopClient",
	"PerkClient", "LobbyClient", "GodModeClient", "LightingClient", "Biome", "RestClient",
}

-- opts = { accepted, clients = { names }, viewport = {w,h}, touch, userId, beforeClients = fn(ctx) }
function Lib.boot(opts: any): any
	local bundle = require("./build/labyrint-spill")
	local h = Harness.new({ bundle = bundle, name = "labyrint-spill", viewport = opts.viewport or { 1280, 720 }, touch = opts.touch == true })
	local userId = opts.userId or 4242
	local store = h.services.DataStoreService:GetDataStore("LabyrintSpill_v1")
	store:SetAsync("p_" .. userId, { accepted = opts.accepted or 0, coins = opts.coins or 50, gems = 1, level = 1, bestByLevel = {} })
	local ok, err = h:tryRun("server/MazeGame.server")
	assert(ok, "server failed to load: " .. tostring(err))
	local ctx: any = { h = h, bundle = bundle }
	ctx.RS = h.game:GetService("RunService")
	ctx.Lighting = h.Lighting
	ctx.ReplicatedStorage = h.ReplicatedStorage
	local plr = h:join(opts.name or "Walker", userId)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	ctx.plr = plr
	ctx.char = char
	ctx.hrp = char:FindFirstChild("HumanoidRootPart")
	ctx.hum = char:FindFirstChildOfClass("Humanoid")
	ctx.hum.FloorMaterial = Enum.Material.Plastic
	ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
	if opts.beforeClients then opts.beforeClients(ctx) end
	ctx.RS:setIsServer(false)
	ctx.loadErrors = {}
	for _, c in (opts.clients or Lib.ALL_CLIENTS) do
		local okc, errc = h:tryRun("client/" .. c .. ".client")
		if not okc then table.insert(ctx.loadErrors, c .. ": " .. tostring(errc)) end
	end
	h:advance(0.5)
	ctx.cam = h.workspace.CurrentCamera
	ctx.clock = 0
	function ctx.frame(dt: number)
		local hrp = ctx.hrp
		if hrp and hrp.Parent then
			ctx.cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 14), hrp.Position)
		end
		ctx.RS.RenderStepped:Fire(dt)
		h:advance(dt)
		ctx.clock += dt
		if ctx.onFrame then ctx.onFrame() end
	end
	function ctx.run(seconds: number, dt: number?, each: ((number) -> any)?)
		local step = dt or (1 / 30)
		local n = math.max(1, math.floor(seconds / step + 0.5))
		for i = 1, n do
			ctx.frame(step)
			if each and each(i) == false then return end
		end
	end
	function ctx.folder(): Instance?
		local name = plr:GetAttribute("MazeFolder")
		return name and h.workspace:FindFirstChild(name) or nil
	end
	function ctx.startRun(level: number)
		if ctx.folder() ~= nil then ctx.toLobby() end
		local sr = h.ReplicatedStorage:WaitForChild("LobbyRemotes"):WaitForChild("StartRun")
		sr:simulateFireServer(plr, level, "solo")
		ctx.run(0.2)
	end
	function ctx.toLobby()
		local f = ctx.folder()
		local door = f and f:FindFirstChild("LobbyDoor")
		local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Fire(plr)
		end
		-- a player needs well over a second to walk from the lobby spawn to a door; LightingClient's
		-- 0.55 s lobby fade must finish before the next run starts, exactly as it does in the game
		ctx.run(1.0)
	end
	-- finish the current level: touch its exit (the server's own finishRun, then advanceInstance)
	function ctx.finishLevel()
		local f = ctx.folder()
		local exit = f and f:FindFirstChild("Exit")
		assert(exit, "no exit to touch")
		exit.Touched:Fire(ctx.hrp)
		ctx.run(0.1)
	end
	function ctx.moveTo(pos: Vector3)
		ctx.hrp.CFrame = CFrame.new(pos)
	end
	return ctx
end

-- The maze grid of a live folder, read the same way a player's client could read it, but
-- independently of Biome.client (so a check compares the client against the rules, not itself).
function Lib.grid(folder: Instance): any
	local floor = folder:FindFirstChild("Floor")
	local S = nil
	local walls, traps = {}, {}
	local wallList = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Wall" or d.Name == "SecretWall") then
			S = S or d.Size.X
			table.insert(wallList, d)
		end
	end
	local gCols = math.floor(floor.Size.X / S + 0.5)
	local gRows = math.floor(floor.Size.Z / S + 0.5)
	local o = floor.Position
	local function fine(p: Vector3): (number, number)
		return math.floor((p.X - o.X) / S + (gCols - 1) / 2 + 0.5), math.floor((p.Z - o.Z) / S + (gRows - 1) / 2 + 0.5)
	end
	local function world(fx: number, fy: number): Vector3
		return Vector3.new(o.X + (fx - (gCols - 1) / 2) * S, 4, o.Z + (fy - (gRows - 1) / 2) * S)
	end
	for _, w in wallList do
		local fx, fy = fine(w.Position)
		walls[fx .. "," .. fy] = w
	end
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Trap" then
			local fx, fy = fine(d.Position)
			traps[((fx - 1) // 2) .. "," .. ((fy - 1) // 2)] = true
		end
	end
	return { S = S, gCols = gCols, gRows = gRows, cols = (gCols - 1) // 2, rows = (gRows - 1) // 2, walls = walls,
		traps = traps, fine = fine, world = world, origin = o }
end

-- Everything this client built in its own folders.
function Lib.census(h: any, names: { string }?): any
	local out = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0, all = {} }
	for _, n in names or { "LabyrintBiomeLocal" } do
		local f = h.workspace:FindFirstChild(n)
		if f then
			for _, d in f:GetDescendants() do
				table.insert(out.all, d)
				if d:IsA("BasePart") then out.parts += 1 end
				if d:IsA("ParticleEmitter") and d.Enabled and (d.Rate or 0) > 0 then
					out.emitters += 1
					out.rate += d.Rate
				end
				if (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and d.Enabled ~= false then out.lights += 1 end
			end
		end
	end
	return out
end

function Lib.rgb(c: Color3): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end

-- The server source, for checks that must agree with a number the server keeps inside its script.
function Lib.serverSource(bundle: any): string
	return bundle["server/MazeGame.server"].source
end

return Lib
