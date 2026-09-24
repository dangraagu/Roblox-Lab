-- Vault Runners — WHAT A RUNNER HAS TO FIND STAYS FINDABLE, driven through the REAL client script
-- against the real server. Run (from robloxemu): luau check_vaultrunners_readable.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Written from the adversarial review of the eye candy (2026-09-24). The client repaints the vault
-- per stratum, and three things a runner has to SEE were measured to vanish into the new colours:
--   §1  the gems (and the exit pad, which wears the gem colour): Silver's pale blue on the Frozen
--       Vault's ice read 1.10:1 against the wall, Bronze's orange on the tomb's sandstone 1.16:1.
--       Every gem and the exit pad must now read against the floor and the walls AS PAINTED, and a
--       tier keeps its own gem colour where that still reads (Gold in the Volcano Temple);
--   §2  the ring a ceiling drop draws at the runner's feet — the danger zone itself — read 1.16:1 on
--       the Frozen Vault's snow while it followed, and its red lock 1.6:1 on the bank's and tomb's
--       floors. Both must now read, measured on the Part as drawn over the floor as painted;
--   §3  the hub's local stratum signs overlapped the server's portal labels on a phone from the spawn
--       view (fixed-pixel billboards 6 studs apart meet beyond ~36 studs at 390 px). They must never
--       overlap, from anywhere on the hub, at any viewport height.
--
-- Headless limits: nothing renders. Contrast is the WCAG ratio (VaultEnv.contrast, the metric that
-- holds the pads) on the colours the parts actually carry; §3 projects the billboards' own sizes and
-- offsets with a pinhole camera at Roblox's default 70° vertical field of view. Neon glow, bloom and
-- how it looks on a real phone are on EYECANDY.md's Studio list.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 6262
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
-- Bronze floor 8 (depth 8: the Pyramid Tomb), Silver floor 1 (depth 26: the Frozen Vault), Gold floor 1
-- (depth 56: the Volcano Temple), every vault unlocked
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 8, [2] = 1, [3] = 1 }, escapes = 0, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local VaultEnv = mod("VaultEnv")
local Progression = mod("Progression")
local VaultFloor = mod("VaultFloor")
local MazeGen = mod("MazeGen")
local Rng = mod("Rng")
local Trace = mod("Trace")
local Hz = Config.Hazards
local bands = Config.Env.Bands
local MIN_GEM_FLOOR = Config.Env.MinGemContrast or 3
local MIN_GEM_WALL = Config.Env.MinGemWallContrast or 1.8
local MIN_RING = Config.Env.MinRingContrast or 3

local remotes = RS:FindFirstChild("VaultRemotes")
local EnterRemote = remotes:FindFirstChild("Enter")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- a drop every 20-25 s of run time, set before the client loads (its scheduler rolls at load)
Hz.IntervalMin = 20
Hz.IntervalMax = 25

local plr = h:join("Finder", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
local function ground()
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
ground()

assert(h:tryRun("client/Hud.client"))
local okVault, errVault = h:tryRun("client/Vault.client")
truthy(okVault, "Vault.client loads (" .. tostring(errVault) .. ")")
local fx = h.workspace:FindFirstChild("VaultRunnersFx")
local vaults = h.workspace:FindFirstChild("Vaults")
local cam = h.workspace.CurrentCamera

local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end
local function arr(c: Color3) return { c.R * 255, c.G * 255, c.B * 255 } end
local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function respawn()
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.1)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	ground()
end

--============================================================================ §3 the hub's signs (first: the hub is where every session starts)

do
	run(1, 1 / 30)
	local hub = h.workspace:FindFirstChild("Hub")
	-- the vertical screen span (top, bottom; y grows downward) of a BillboardGui, or of one of its
	-- children, seen from `camPos` looking at `target`, on a viewport `H` px tall
	local FOV = math.rad(70)
	local function span(bb, child, camPos, target, H)
		local adornee = bb.Adornee or bb.Parent
		local at = adornee.Position + (bb.StudsOffset or Vector3.new(0, 0, 0))
		local fw = target - camPos
		local fl = math.sqrt(fw.X ^ 2 + fw.Y ^ 2 + fw.Z ^ 2)
		local f = { fw.X / fl, fw.Y / fl, fw.Z / fl }
		-- right = forward x worldUp; up = right x forward
		local r = { -f[3], 0, f[1] }
		local rl = math.sqrt(r[1] ^ 2 + r[3] ^ 2)
		r = { r[1] / rl, 0, r[3] / rl }
		local u = { r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1] }
		local d = at - camPos
		local z = d.X * f[1] + d.Y * f[2] + d.Z * f[3]
		if z <= 0.5 then return nil end
		local y = d.X * u[1] + d.Y * u[2] + d.Z * u[3]
		local focal = (H / 2) / math.tan(FOV / 2)
		local cy = H / 2 - y / z * focal
		local bh = bb.Size.Y.Scale * 0 + bb.Size.Y.Offset -- offset-sized: fixed pixels at any distance
		local top = cy - bh / 2
		if child then
			top += child.Position.Y.Scale * bh + child.Position.Y.Offset
			return top, top + child.Size.Y.Scale * bh + child.Size.Y.Offset, z
		end
		return top, top + bh, z
	end
	local checked, overlaps, worst, worstAt = 0, 0, math.huge, nil
	for i = 1, #Config.Tiers do
		local portal = hub and hub:FindFirstChild("Portal_" .. i)
		local label = portal and portal:FindFirstChild("Label")
		local sign = fx:FindFirstChild("PortalSign_" .. i)
		local bb = sign and sign:FindFirstChild("Stratum")
		local text = bb and bb:FindFirstChild("Text")
		truthy(label ~= nil and label.ClassName == "BillboardGui", "§3 (portal " .. i .. " carries the server's name label)")
		truthy(text ~= nil, "§3 (and this client's stratum sign)")
		eq(bb and bb.Size.X.Scale, 0, "§3 the sign is sized in pixels, like the label (a scale-sized sign would grow with distance)")
		eq(bb and bb.Size.Y.Scale, 0, "§3 (in both directions)")
		eq(label and label.Size.Y.Scale, 0, "§3 (the server's label is pixel-sized)")
		if label and text then
			for _, H in { 320, 375, 390, 720, 1080 } do
				for x = -40, 40, 4 do
					for z = -14, 44, 4 do
						for _, y in { 5, 9, 15 } do
							local camPos = Vector3.new(x, y, z)
							local labelAt = portal.Position + label.StudsOffset
							local dist = (labelAt - camPos).Magnitude
							if dist <= (bb.MaxDistance or math.huge) and dist >= 4 then
								local lt, lb = span(label, nil, camPos, labelAt, H)
								local st, sb = span(bb, text, camPos, labelAt, H)
								if lt and st then
									checked += 1
									local gap = math.max(st - lb, lt - sb) -- > 0: apart
									if gap < 0 then overlaps += 1 end
									if gap < worst then worst, worstAt = gap, string.format("portal %d, camera (%d, %d, %d), %d px tall, %.0f studs", i, x, y, z, H, dist) end
								end
							end
						end
					end
				end
			end
		end
	end
	print(string.format("  §3 %d views of the portal labels and signs: %d overlap; tightest gap %.1f px (%s)", checked, overlaps, worst, tostring(worstAt)))
	truthy(checked > 1000, "§3 (the whole hub was looked at: " .. checked .. " views)")
	eq(overlaps, 0, "§3 a portal's stratum sign never overlaps its server label, from anywhere on the hub, at any viewport height")
end

--============================================================================ vaults

local cur = nil
local function enter(tier)
	if myVault() then respawn() end
	EnterRemote:simulateFireServer(plr, tier)
	h:advance(0.05)
	local v = myVault()
	local start = nil
	local sent = remotes:FindFirstChild("Run"):getSent()
	for k = #sent, 1, -1 do
		if sent[k].args[1] == "start" and sent[k].player == plr then start = sent[k].args[2]; break end
	end
	local spec = Progression.difficulty(Config, tier, start.floor)
	spec.seed = Progression.seedFor(Config, tier, start.floor)
	cur = { v = v, tier = tier, floor = start.floor, model = VaultFloor.build(Config, spec, MazeGen, Rng),
		origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, 1, 0) }
	cur.depth = VaultEnv.depth(Config, tier, start.floor)
	cur.band = bands[EnvBands.indexAt(bands, cur.depth)].id
	return cur
end
local function painted(prefix)
	for _, d in cur.v:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix) == prefix then return arr(d.Color) end
	end
	return nil
end

--============================================================================ §1 gems and the exit pad

local CASES = { { 1, "tomb" }, { 2, "frozen" }, { 3, "volcano" } }
do
	for _, case in CASES do
		local tier, wantBand = case[1], case[2]
		local e = enter(tier)
		run(1, 1 / 30)
		local label = string.format("§1 %s floor %d (%s)", Config.Tiers[tier].name, e.floor, e.band)
		eq(e.band, wantBand, label .. ": (the stratum this case is about)")
		local wall, floor = painted("Wall_"), painted("Floor_")
		local own = Config.Tiers[tier].gemColor
		local n, worstF, worstW, keptOwn, same, first = 0, math.huge, math.huge, true, true, nil
		local exit = nil
		for _, d in e.v:GetDescendants() do
			if d:IsA("BasePart") and (string.sub(d.Name, 1, 4) == "Gem_" or d.Name == "ExitPad") then
				local c = arr(d.Color)
				if d.Name == "ExitPad" then exit = c else n += 1 end
				worstF = math.min(worstF, VaultEnv.contrast(c, floor))
				worstW = math.min(worstW, VaultEnv.contrast(c, wall))
				if math.abs(c[1] - own.r) > 1 or math.abs(c[2] - own.g) > 1 or math.abs(c[3] - own.b) > 1 then keptOwn = false end
				first = first or c
				if math.abs(c[1] - first[1]) > 1 or math.abs(c[2] - first[2]) > 1 or math.abs(c[3] - first[3]) > 1 then same = false end
			end
		end
		truthy(n > 0 and exit ~= nil, string.format("%s: (%d gems and the exit pad)", label, n))
		print(string.format("  %s: gems and exit pad {%d, %d, %d}: %.2f:1 against the floor as painted, %.2f:1 against the wall",
			label, math.round(first[1]), math.round(first[2]), math.round(first[3]), worstF, worstW))
		truthy(worstF >= MIN_GEM_FLOOR, string.format("%s: every gem and the exit pad stand out against the floor (worst %.2f:1)", label, worstF))
		truthy(worstW >= MIN_GEM_WALL, string.format("%s: and against the walls (worst %.2f:1)", label, worstW))
		truthy(same, label .. ": the exit pad glows in the gems' colour, as it always has")
		if wantBand == "volcano" then
			truthy(keptOwn, label .. ": where the tier's own gem colour reads, it is kept")
		end
		respawn()
		run(0.3, 1 / 30)
	end
end

--============================================================================ §2 the drop's ring

local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor
local function worldAt(s, fx_, fy_)
	local m = cur.model
	return cur.origin + Vector3.new((fx_ - (m.gCols - 1) / 2) * m.cellSize, s * m.storeyHeight + Config.Run.RunnerRootHeight,
		(fy_ - (m.gRows - 1) / 2) * m.cellSize)
end
local function walkTo(target)
	for _ = 1, 4000 do
		local p = hrp.Position
		local dx, dz, dy = target.X - p.X, target.Z - p.Z, target.Y - p.Y
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 0.5 and math.abs(dy) < 0.5 then break end
		local mh = math.min(flat, WALK_H * 0.1)
		hrp.CFrame = CFrame.new(p.X + (if flat > 1e-6 then dx / flat * mh else 0), p.Y + (if dy > 0 then math.min(dy, WALK_UP * 0.1) else dy),
			p.Z + (if flat > 1e-6 then dz / flat * mh else 0))
		frame(0.1)
	end
end
local function eligibleCell(s)
	local m = cur.model
	for fy = 1, m.gRows - 2 do
		for fx_ = 1, m.gCols - 2 do
			if m.grids[s + 1][fy][fx_] == false then
				local p = worldAt(s, fx_, fy) - cur.origin
				if VaultEnv.hazardEligible(Config, m, { x = p.X, y = p.Y, z = p.Z }, { elapsed = 60, timeLeft = 100, danger = 0 }) then
					return { fx = fx_, fy = fy }
				end
			end
		end
	end
	return nil
end

do
	for _, case in CASES do
		local tier = case[1]
		local e = enter(tier)
		local S = e.model.storeys - 1
		local cell = eligibleCell(S)
		local label = string.format("§2 %s floor %d (%s)", Config.Tiers[tier].name, e.floor, e.band)
		truthy(cell ~= nil, label .. ": (the top storey has somewhere a drop may start)")
		walkTo(worldAt(S, cell.fx, cell.fy))
		ground()
		local floor = painted("Floor_")
		local worst, frames, colours, sawLock = math.huge, 0, {}, false
		local seen = false
		run(Hz.GraceSeconds + Hz.IntervalMax + 10, 1 / 30, function()
			local ring = fx:FindFirstChild("HazardRing")
			if ring and ring.Transparency < 0.99 then
				seen = true
				frames += 1
				local c, t = arr(ring.Color), ring.Transparency
				-- the ring as the eye gets it: its colour over the floor, weighted by its opacity (computed
				-- here, not with the client's own helper: this file measures what the client drew)
				local over = { c[1] * (1 - t) + floor[1] * t, c[2] * (1 - t) + floor[2] * t, c[3] * (1 - t) + floor[3] * t }
				worst = math.min(worst, VaultEnv.contrast(over, floor))
				colours[string.format("%d,%d,%d@%.2f", math.round(c[1]), math.round(c[2]), math.round(c[3]), t)] = true
				local warning = plr.PlayerGui.VaultFx.Root.HazardWarning
				if warning.Visible and string.find(warning.Text.Text, "MOVE!", 1, true) then sawLock = true end
			elseif seen then
				return false
			end
		end)
		local n = 0
		local list = {}
		for k in colours do n += 1; table.insert(list, k) end
		table.sort(list)
		truthy(seen and sawLock, label .. ": (a drop came, followed and locked)")
		print(string.format("  %s: the ring over the floor as painted, %d frames: worst %.2f:1 (%s)", label, frames, worst, table.concat(list, " / ")))
		truthy(worst >= MIN_RING, string.format("%s: the ring reads against the floor while it follows AND once it locks (worst %.2f:1)", label, worst))
		truthy(n >= 2, label .. ": and the lock looks different from the follow")
		respawn()
		run(0.3, 1 / 30)
	end
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. tostring(e))
end
local warns = 0
for _, w in h.warnings do
	if string.find(w, "[VaultFx]", 1, true) then warns += 1; print("  warning: " .. w) end
end
eq(warns, 0, "the client never warned")
print(string.format("vault-runners readable: %d passed, %d failed", passed, failed))
