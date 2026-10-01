-- Vault Runners — THE CLIENT'S BUDGETS ARE CAPS IN CODE, not only numbers a check compares against.
-- Run (from robloxemu): luau check_vaultrunners_budget.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Second adversarial review of the eye candy (2026-09-30), finding 1: Config.Budget named six budgets
-- and the running game enforced one of them (the weather's, through EnvBands.capRates). The parts,
-- emitter, particle-rate, light and beam budgets were read only by the checks. The reviewer set the
-- reactor's prop density to 1.0 and the client hung 235 parts on Bronze floor 14 against a budget of
-- 180; nothing in the game stopped it. docs/complete-game-standard.md §2: budgets are "measured and
-- capped in code". So here the DEMAND and the BUDGETS are forced in memory, never in src/:
--   §1  every band hangs props in every cell (density 1.0), with drops in the air: on every frame, on
--       every storey of Bronze 14 (reactor), Silver 1 (frozen) and Gold 1 (volcano), the client's
--       parts stay within Budget.MaxLocalParts — and the props kept are the runner's own storey's;
--   §2  the budgets forced BELOW what the scene asks for (2 emitters, 20 particles/s, 0 lights, 1
--       beam) in the Frozen Vault with its aurora, snow, collapse dust and sparks and a drop in the
--       air: every frame stays inside them, and the drop's telegraph keeps its priority (its dust
--       trickle is on whenever a chunk hangs over the runner);
--   §3  CONTROL: the shipped budgets and densities cap nothing — the same scene hangs every prop its
--       sites ask for and every emitter at the rate it asked for.
--
-- Headless limits: nothing renders. These are counts of Instances and property values, the same
-- measure check_vaultrunners_env §9 uses; frame time on a phone is on EYECANDY.md's Studio list.

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

local ME = 7373
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
-- Bronze floor 14 (the reactor), Silver floor 1 (the Frozen Vault), Gold floor 1 (the Volcano Temple)
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 14, [2] = 1, [3] = 1 }, escapes = 13, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local VaultEnv = mod("VaultEnv")
local EnvBands = mod("EnvBands")
local Progression = mod("Progression")
local VaultFloor = mod("VaultFloor")
local MazeGen = mod("MazeGen")
local Rng = mod("Rng")
local bands = Config.Env.Bands
local B = Config.Budget
local SHIPPED = table.clone(B)
local SHIPPED_DENSITY = {}
for i, b in bands do SHIPPED_DENSITY[i] = b.props.density end

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- a drop every 8-10 s of run time (set before the client loads: its scheduler rolls at load), and a
-- collapse that stays far below (the server reads Config when it builds each vault)
Config.Hazards.IntervalMin = 8
Config.Hazards.IntervalMax = 10
Config.Collapse.Slack = 20
Config.Collapse.MinSlack = 19.9

local plr = h:join("Budgeter", ME)
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
local EnterRemote = RS:FindFirstChild("VaultRemotes"):FindFirstChild("Enter")

local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0 }
local function measure()
	local m = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, props = 0 }
	for _, d in fx:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			m.parts += 1
			if string.sub(d.Name, 1, 4) == "Prop" then m.props += 1 end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate or 0
		elseif cls == "PointLight" and (d.Brightness or 0) > 0 and d.Enabled ~= false then
			m.lights += 1
		elseif cls == "Beam" and d.Enabled ~= false then
			m.beams += 1
		end
	end
	for k in peak do peak[k] = math.max(peak[k], m[k]) end
	return m
end
local function resetPeak() for k in peak do peak[k] = 0 end end

local each = nil
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local m = measure()
	if each then each(m) end
end
local function run(seconds, dt)
	for _ = 1, math.floor(seconds / dt + 0.5) do frame(dt) end
end
local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function respawn()
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.1)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	ground()
end
local cur = nil
local function enter(tier)
	if myVault() then respawn() end
	run(0.3, 1 / 30)
	EnterRemote:simulateFireServer(plr, tier)
	h:advance(0.05)
	local v = myVault()
	local floor = ({ 14, 1, 1 })[tier]
	local spec = Progression.difficulty(Config, tier, floor)
	spec.seed = Progression.seedFor(Config, tier, floor)
	cur = { v = v, tier = tier, floor = floor, model = VaultFloor.build(Config, spec, MazeGen, Rng), spec = spec,
		origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, 1, 0) }
	return cur
end
-- the runner on storey s, at the first open fine cell of that storey that is not the stairwell
local function standOn(s)
	local m = cur.model
	for fy = 1, m.gRows - 2, 2 do
		for fx_ = 1, m.gCols - 2, 2 do
			local p = cur.origin + Vector3.new((fx_ - (m.gCols - 1) / 2) * m.cellSize, s * m.storeyHeight + Config.Run.RunnerRootHeight,
				(fy - (m.gRows - 1) / 2) * m.cellSize)
			local lp = p - cur.origin
			if not VaultEnv.inShaft(Config, m, { x = lp.X, y = lp.Y, z = lp.Z }) then
				hrp.CFrame = CFrame.new(p)
				ground()
				return
			end
		end
	end
end
-- ...or at the first open fine cell of storey s where a ceiling drop may start
local function standWhereADropMayStart(s)
	local m = cur.model
	for fy = 1, m.gRows - 2 do
		for fx_ = 1, m.gCols - 2 do
			local p = cur.origin + Vector3.new((fx_ - (m.gCols - 1) / 2) * m.cellSize, s * m.storeyHeight + Config.Run.RunnerRootHeight,
				(fy - (m.gRows - 1) / 2) * m.cellSize)
			local lp = p - cur.origin
			if m.grids[s + 1][fy] and m.grids[s + 1][fy][fx_] == false
				and VaultEnv.hazardEligible(Config, m, { x = lp.X, y = lp.Y, z = lp.Z }, { elapsed = 60, timeLeft = 999, danger = 0 }) then
				hrp.CFrame = CFrame.new(p)
				ground()
				return true
			end
		end
	end
	return false
end
-- how many prop PARTS the client would hang on storey s and the one above, uncapped (what the sites ask for)
local PROP_PARTS = 3 -- every prop kind VaultArt builds is three parts
local function asked(s)
	local m = cur.model
	local pal = VaultEnv.palette(Config, EnvBands, VaultEnv.depth(Config, cur.tier, cur.floor))
	local a, b = bands[pal.band], bands[pal.next]
	local density = a.props.density + (b.props.density - a.props.density) * pal.t
	local n = 0
	for st = s, math.min(s + Config.Env.PropStoreysAbove, m.storeys - 2) do
		n += #VaultEnv.propSites(m, st, cur.spec.seed, density)
	end
	return n * PROP_PARTS
end

run(1, 1 / 30)

--============================================================================ §1 parts: props in every cell

do
	for _, b in bands do b.props.density = 1 end
	resetPeak()
	local worstOver, keptOwn, askedMax = 0, true, 0
	-- CRITTERS YIELD FIRST (EYECANDY.md §2.5): wherever the props alone fill the parts budget, no critter
	-- is on show, even with critters in reach. Counted only where some were in reach, so it cannot pass
	-- by there being none.
	local critterWhenFull, fullWithCritters = 0, 0
	for _, tier in { 1, 2, 3 } do
		enter(tier)
		for s = 0, cur.model.storeys - 1 do
			standOn(s)
			local want = asked(s)
			askedMax = math.max(askedMax, want)
			run(1.5, 1 / 30)
			local m = measure()
			worstOver = math.max(worstOver, m.parts - B.MaxLocalParts)
			do
				local pal = VaultEnv.palette(Config, EnvBands, VaultEnv.depth(Config, cur.tier, cur.floor))
				local a = bands[pal.band]
				local mm = cur.model
				local lp = hrp.Position - cur.origin
				local loc = VaultEnv.locate(Config, mm, { x = lp.X, y = lp.Y, z = lp.Z })
				local cx = math.clamp(math.floor((loc.fx - 1) / 2 + 0.5), 0, mm.cells - 1)
				local cy = math.clamp(math.floor((loc.fy - 1) / 2 + 0.5), 0, mm.cells - 1)
				local inReach = #VaultEnv.critterNear(VaultEnv.critterSites(mm, loc.storey, cur.spec.seed, a.critters.density),
					cx, cy, Config.Env.CritterReach, B.MaxCritters)
				local critterParts = 0
				for _, d in fx:GetChildren() do
					if string.sub(d.Name, 1, 8) == "Critter_" then critterParts += 1 end
				end
				if inReach > 0 and m.props < want then
					fullWithCritters += 1
					if critterParts > 0 then critterWhenFull += 1 end
				end
			end
			-- the props that are kept are this storey's own before the next one's: if anything hangs
			-- over the storey above, every site of this one is hung
			if s <= cur.model.storeys - 2 then
				local H, ownHung, aboveHung = cur.model.storeyHeight, 0, 0
				for _, d in fx:GetChildren() do
					if (d.ClassName == "Part" or d.ClassName == "WedgePart") and string.sub(d.Name, 1, 4) == "Prop" then
						local st = math.floor((d.Position.Y - cur.origin.Y) / H)
						if st == s then ownHung += 1 elseif st == s + 1 then aboveHung += 1 end
					end
				end
				local ownAsked = #VaultEnv.propSites(cur.model, s, cur.spec.seed, 1) * PROP_PARTS
				if aboveHung > 0 and ownHung < ownAsked then keptOwn = false end
			end
		end
		run(12, 1 / 30) -- a drop comes and lands on the top storey, props and all
	end
	-- THE HEADROOM IS RESERVED, NOT TAKEN: the props of the storey you stand on do not come down when
	-- a drop appears over it. The telegraph, the cracks and the debris have their parts set aside when
	-- the props are hung, so the per-frame cap never has to take a prop down to make room for them.
	enter(1)
	truthy(standWhereADropMayStart(0), "§1 (storey 0 has a cell where a drop may start)")
	run(1, 1 / 30)
	local before = measure().props
	local minP, maxP, hung = math.huge, 0, 0
	each = function(m)
		minP = math.min(minP, m.props)
		maxP = math.max(maxP, m.props)
		local ring = fx:FindFirstChild("HazardRing")
		if ring and ring.Transparency < 1 then hung += 1 end
	end
	run(25, 1 / 30)
	each = nil
	truthy(hung > 0 and before > 0, string.format("§1 (a drop hung over storey 0 for %d frames under %d prop parts)", hung, before))
	print(string.format("  §1 a drop hung over storey 0 for %d frames; its props: %d before, %d-%d during", hung, before, minP, maxP))
	truthy(minP == before and maxP == before, string.format(
		"§1 no prop comes down, or goes up, while a drop hangs over the storey (%d before; %d-%d during)", before, minP, maxP))
	print(string.format("  §1 props forced to every cell: the sites ask for up to %d prop parts; peak %d client parts (budget %d)",
		askedMax, peak.parts, B.MaxLocalParts))
	truthy(askedMax + 40 > B.MaxLocalParts, "§1 (the forced scene really asks for more than the budget)")
	truthy(peak.parts <= B.MaxLocalParts, string.format("§1 the client's parts never exceed Budget.MaxLocalParts on any frame (peak %d, budget %d)",
		peak.parts, B.MaxLocalParts))
	truthy(keptOwn, "§1 the props that are kept are the runner's own storey's first")
	print(string.format("  §1 the props filled the budget with critters in reach on %d storeys; a critter was up on %d of them",
		fullWithCritters, critterWhenFull))
	truthy(fullWithCritters > 0, "§1 (the props filled the budget with critters in reach " .. fullWithCritters .. " times)")
	eq(critterWhenFull, 0, "§1 critters yield first: none is on show while the props alone fill the budget")
	for i, b in bands do b.props.density = SHIPPED_DENSITY[i] end
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §2 emitters, particles/s, lights, beams

do
	B.MaxEmitters, B.MaxEmitterRate, B.MaxLights, B.MaxBeams = 2, 20, 0, 1
	resetPeak()
	local hung, trickleOn, over = 0, 0, nil
	each = function(m)
		if over == nil and (m.emitters > B.MaxEmitters or m.rate > B.MaxEmitterRate + 1e-6 or m.lights > B.MaxLights or m.beams > B.MaxBeams) then
			over = string.format("%d emitters, %.1f/s, %d lights, %d beams", m.emitters, m.rate, m.lights, m.beams)
		end
		local ring = fx:FindFirstChild("HazardRing")
		local stream = fx:FindFirstChild("HazardStream")
		if ring and ring.Transparency < 1 and stream then
			hung += 1
			local t = stream:FindFirstChild("Trickle")
			if t and t.Enabled and t.Rate > 0 then trickleOn += 1 end
		end
	end
	enter(2) -- Silver 1: the Frozen Vault (aurora, snow)
	standOn(cur.model.storeys - 1) -- the top storey: the aurora overhead
	run(30, 1 / 30)
	each = nil
	print(string.format("  §2 budgets forced to %d emitters, %d/s, %d lights, %d beams: peak %d, %.1f/s, %d, %d; a chunk hung on %d frames, its trickle on for %d",
		B.MaxEmitters, B.MaxEmitterRate, B.MaxLights, B.MaxBeams, peak.emitters, peak.rate, peak.lights, peak.beams, hung, trickleOn))
	truthy(over == nil, "§2 every frame stays inside the forced budgets (first frame over: " .. tostring(over) .. ")")
	truthy(hung > 0, "§2 (a drop hung over the runner during the section)")
	eq(trickleOn, hung, "§2 the drop's telegraph keeps its priority: its trickle is on whenever a chunk hangs")
	for k, v in SHIPPED do B[k] = v end
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §3 CONTROL: the shipped numbers cap nothing

do
	resetPeak()
	enter(2)
	standOn(0) -- storey 0: its own props and storey 1's are asked for
	run(3, 1 / 30)
	local m = measure()
	local want = asked(0)
	truthy(want > 0, "§3 (storey 0 asks for props: " .. want .. " parts)")
	eq(m.props, want, string.format("§3 CONTROL: with the shipped density every prop storey 0 and 1's sites ask for is hung (%d of %d parts)", m.props, want))
	standOn(cur.model.storeys - 1) -- the top storey: the aurora overhead
	run(20, 1 / 30)
	truthy(peak.emitters <= B.MaxEmitters and peak.rate <= B.MaxEmitterRate and peak.beams <= B.MaxBeams,
		string.format("§3 CONTROL: the shipped scene sits inside the shipped budgets (%d emitters, %.1f/s, %d beams)", peak.emitters, peak.rate, peak.beams))
	eq(peak.beams, 3, "§3 CONTROL: all three aurora ribbons are drawn when the budget allows them")
	respawn()
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
print(string.format("vault-runners budget: %d passed, %d failed", passed, failed))
