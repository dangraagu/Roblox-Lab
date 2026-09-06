-- Main.server.luau — authoritative server for "Anomaly: Night Shift at the Observatory".
--
-- Per player: a private observatory concourse built at a far offset. Each PASS the server
-- rebuilds the hall CLEAN, rolls (Anomaly.rollPass), and if the roll is anomalous applies
-- exactly ONE spottable mutation. The player walks to the end and triggers ADVANCE or
-- TURN BACK (ProximityPrompts — server-authoritative, no client trust). Progression.resolve
-- decides: correct -> Day+1 and the hall loops; wrong -> the night resets to Day 1.
--
-- There is NO chase / pathfinding AI. Persistence uses a soft session-lock (load real data
-- always; only save while we hold the lock) with an atomic flush for code redemption.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage
local Config = require(Shared:WaitForChild("Config"))
local Rng = require(Shared:WaitForChild("Rng"))
local Anomaly = require(Shared:WaitForChild("Anomaly"))
local Progression = require(Shared:WaitForChild("Progression"))
local Codex = require(Shared:WaitForChild("Codex"))
local Codes = require(Shared:WaitForChild("Codes"))
local Fx = require(Shared:WaitForChild("Fx"))

-- Visual polish (code-only, additive): cold + dense horror rig with post-fx. Atmosphere is
-- half of this genre — without it the concourse reads as grey boxes instead of a night shift.
Fx.applyLighting(Fx.Presets.Horror)

-- ------------------------------------------------------------------ Remotes
local Remotes = Instance.new("Folder")
Remotes.Name = "AnomalyRemotes"
Remotes.Parent = ReplicatedStorage
local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end
local StateRemote = makeRemote("State") -- server -> client: full HUD state
local RevealRemote = makeRemote("Reveal") -- server -> client: hint result
local DeathRemote = makeRemote("Death") -- server -> client: run ended at day N
local RedeemRemote = makeRemote("Redeem") -- client -> server: code string
local HintRemote = makeRemote("UseHint") -- client -> server: spend a hint
local TintRemote = makeRemote("SetTint") -- client -> server: pick a flashlight tint

-- ------------------------------------------------------------------ DataStore
local ok, profileStore = pcall(function()
	return DataStoreService:GetDataStore(Config.Save.Store)
end)
if not ok then
	profileStore = nil
	warn("[Anomaly] DataStore unavailable — running without saves (Studio API access off?)")
end
local orderedOk, bestBoard = pcall(function()
	return DataStoreService:GetOrderedDataStore(Config.Save.LeaderStore)
end)
if not orderedOk then
	bestBoard = nil
end

type Profile = {
	bestDay: number,
	caught: Codex.Set,
	hintTokens: number,
	redeemed: Codes.RedeemedSet,
	tint: string, -- the SELECTED tint
	ownedTints: { [string]: boolean }, -- everything the player may select (string keys)
	canSave: boolean, -- true only if we hold the session lock
	lockToken: string, -- STABLE per-session ownership token (not a timestamp)
}

type PassState = {
	day: number,
	clean: boolean,
	anomalyId: string?,
	serial: number,
	awaiting: boolean,
	salt: number, -- per-session anomaly-sequence salt (server memory only, never replicated)
	startedAt: number, -- os.clock() when this pass went live (anti-autoclicker plausibility)
}

local profiles: { [Player]: Profile } = {}
local zones: { [Player]: Model } = {}
local passState: { [Player]: PassState } = {}

-- Zone index allocator with a FREE LIST: indices are recycled on PlayerRemoving so a
-- long-lived server never drifts out to hundreds of thousands of studs (physics/render
-- precision degrades out there). Lowest free index is always reused first.
local nextZoneIndex = 0
local freeZoneIndices: { number } = {}

local function acquireZoneIndex(): number
	if #freeZoneIndices > 0 then
		table.sort(freeZoneIndices)
		return table.remove(freeZoneIndices, 1) :: number
	end
	nextZoneIndex += 1
	return nextZoneIndex
end

local function releaseZoneIndex(index: number)
	if index <= 0 then
		return
	end
	for _, taken in freeZoneIndices do
		if taken == index then
			return -- already free; never double-release
		end
	end
	table.insert(freeZoneIndices, index)
end

-- Server-side salt source for the per-session anomaly sequence. Never persisted, never
-- sent to a client, so the answer order cannot be memorised/recorded across sessions.
local saltSource = Random.new()

-- Forward declarations for the mutually-recursive loop functions (assigned below).
local beginPass: (Player) -> ()
local resolveChoice: (Player, string) -> ()
local useHint: (Player) -> ()
local awardMilestone: (Player, number) -> ()

local function nowStamp(): number
	return os.time()
end

-- A unique, STABLE token for this play session. Compared against old.lock.token so our own
-- writes are never mistaken for a foreign session's lock (a timestamp cannot do this: every
-- write moves it, so the guard would fire against ourselves).
local function newSessionToken(): string
	local ok3, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok3 and typeof(guid) == "string" then
		return guid
	end
	-- fallback (GenerateGUID should never fail, but never hand back a constant)
	return string.format("%d-%d", os.time(), saltSource:NextInteger(1, 2147483647))
end

local function tintIsKnown(name: string): boolean
	for _, t in Config.Tints do
		if t == name then
			return true
		end
	end
	return false
end

-- Owned-tint set from persisted data. Always contains the free default; legacy profiles
-- (which stored ownership implicitly in `tint`) keep whatever they were wearing.
local function sanitizeOwnedTints(raw: any, currentTint: string): { [string]: boolean }
	local owned: { [string]: boolean } = { [Config.DefaultTint] = true }
	if type(raw) == "table" then
		for k, v in raw do
			if type(k) == "string" and v and tintIsKnown(k) then
				owned[k] = true
			end
		end
	end
	if tintIsKnown(currentTint) then
		owned[currentTint] = true
	end
	return owned
end

-- Fresh default profile (used for brand-new players and when a load fails).
local function defaultProfile(): Profile
	return {
		bestDay = 0,
		caught = {},
		hintTokens = Config.Hint.StartTokens,
		redeemed = {},
		tint = Config.DefaultTint,
		ownedTints = { [Config.DefaultTint] = true },
		canSave = false,
		lockToken = "",
	}
end

-- Load the real profile via UpdateAsync and, if the previous lock is stale/absent, claim a
-- new lock. canSave is set only when we acquire the lock, so a second session never clobbers
-- the first, and a failed load never overwrites real data.
local function loadProfile(plr: Player): Profile
	local prof = defaultProfile()
	if not profileStore then
		prof.canSave = false
		return prof
	end
	local myToken = newSessionToken()
	local key = "u_" .. plr.UserId
	local success, err = pcall(function()
		profileStore:UpdateAsync(key, function(old)
			old = old or {}
			-- Claim only when the lock is absent, STALE, or already ours (UpdateAsync may run
			-- this transform more than once — the second pass must recognise our own lock).
			local lock = old.lock
			local heldByOther = false
			if type(lock) == "table" and lock.token ~= myToken then
				local age = nowStamp() - (tonumber(lock.at) or 0)
				if age < Config.Save.SessionLockSeconds then
					heldByOther = true
				end
			end

			-- adopt the stored data either way (a live read never overwrites, only reads)
			prof.bestDay = old.bestDay or 0
			prof.caught = old.caught or {}
			prof.hintTokens = old.hintTokens or Config.Hint.StartTokens
			prof.redeemed = old.redeemed or {}
			local storedTint = old.tint
			prof.tint = (type(storedTint) == "string" and tintIsKnown(storedTint)) and storedTint or Config.DefaultTint
			prof.ownedTints = sanitizeOwnedTints(old.ownedTints, prof.tint)

			if heldByOther then
				-- someone else holds it: load read-only, do NOT take the lock
				prof.canSave = false
				prof.lockToken = ""
				return old -- unchanged
			end

			-- free / stale / ours: take the lock
			prof.canSave = true
			prof.lockToken = myToken
			old.bestDay = prof.bestDay
			old.caught = prof.caught
			old.hintTokens = prof.hintTokens
			old.redeemed = prof.redeemed
			old.tint = prof.tint
			old.ownedTints = prof.ownedTints
			old.lock = { at = nowStamp(), token = myToken }
			return old
		end)
	end)
	if not success then
		warn("[Anomaly] load failed for", plr.Name, err)
		prof.canSave = false -- never save over data we couldn't read
		prof.lockToken = ""
	end
	return prof
end

-- Persist the profile. Only writes while we hold the lock; refreshes the lock timestamp so
-- the soft-lock TTL keeps sliding for as long as we're online. Ownership is decided by our
-- STABLE session TOKEN, so our own previous write can never lock us out of the next one.
-- Returns true only when the write actually landed (never lies to the caller).
local function saveProfile(plr: Player, releaseLock: boolean): boolean
	local prof = profiles[plr]
	if not prof or not prof.canSave or not profileStore then
		return false
	end
	local key = "u_" .. plr.UserId
	local wrote = false
	local success = pcall(function()
		profileStore:UpdateAsync(key, function(old)
			old = old or {}
			wrote = false -- reset per transform attempt (UpdateAsync may retry)
			-- only write if the lock is still ours (or gone / stale)
			local lock = old.lock
			if type(lock) == "table" and lock.token ~= prof.lockToken then
				local age = nowStamp() - (tonumber(lock.at) or 0)
				if age < Config.Save.SessionLockSeconds then
					-- another session grabbed the lock; abort our write
					return old
				end
			end
			old.bestDay = math.max(old.bestDay or 0, prof.bestDay)
			old.caught = prof.caught
			old.hintTokens = prof.hintTokens
			old.redeemed = prof.redeemed
			old.tint = prof.tint
			old.ownedTints = prof.ownedTints
			if releaseLock then
				old.lock = nil -- release: the next session claims immediately
			else
				old.lock = { at = nowStamp(), token = prof.lockToken }
			end
			wrote = true
			return old
		end)
	end)
	if not success then
		warn("[Anomaly] save failed for", plr.Name)
	elseif not wrote then
		warn("[Anomaly] save aborted for", plr.Name, "— session lock held elsewhere")
	end
	return success and wrote
end

local function publishBest(plr: Player)
	if not bestBoard then
		return
	end
	local prof = profiles[plr]
	if not prof or prof.bestDay <= 0 then
		return
	end
	pcall(function()
		bestBoard:SetAsync("u_" .. plr.UserId, prof.bestDay)
	end)
end

-- ------------------------------------------------------------------ Scene build
local WHITE = Color3.fromRGB(235, 235, 245)
local DARK = Color3.fromRGB(30, 34, 48)

local HALL_LEN = 80 -- studs from start to the decision point

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function zoneOrigin(index: number): Vector3
	return Vector3.new(index * 1000, 100, 0)
end

-- Build a CLEAN concourse under `zone` at `origin`. All the objects the anomalies can
-- touch are named so the appliers can find them. The hall runs along -Z.
local function buildClean(zone: Model, origin: Vector3)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z))
	end
	-- shell
	newPart({ Name = "Floor", Size = Vector3.new(20, 1, HALL_LEN + 20), CFrame = at(0, 0, -HALL_LEN / 2), Color = DARK, Parent = zone })
	newPart({ Name = "Ceiling", Size = Vector3.new(20, 1, HALL_LEN + 20), CFrame = at(0, 16, -HALL_LEN / 2), Color = DARK, Parent = zone })
	newPart({ Name = "WallL", Size = Vector3.new(1, 16, HALL_LEN + 20), CFrame = at(-10, 8, -HALL_LEN / 2), Color = DARK, Parent = zone })
	newPart({ Name = "WallR", Size = Vector3.new(1, 16, HALL_LEN + 20), CFrame = at(10, 8, -HALL_LEN / 2), Color = DARK, Parent = zone })
	newPart({ Name = "EndWall", Size = Vector3.new(20, 16, 1), CFrame = at(0, 8, -HALL_LEN - 6), Color = DARK, Parent = zone })

	-- lit fixtures (a Folder of PointLights so lights_out / flicker can find them)
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = zone
	for i = 1, 5 do
		local fixture = newPart({
			Name = "Fixture" .. i, Size = Vector3.new(3, 0.4, 3),
			CFrame = at(0, 15.5, -i * 14 + 4), Color = WHITE, Material = Enum.Material.Neon, Parent = zone,
		})
		local pl = Instance.new("PointLight")
		pl.Brightness = 2
		pl.Range = 24
		pl.Color = WHITE
		pl.Parent = fixture
		pl.Name = "PL"
		local ref = Instance.new("ObjectValue")
		ref.Name = "L" .. i
		ref.Value = fixture
		ref.Parent = lights
	end

	-- fixtures the anomalies mutate
	newPart({ Name = "Telescope", Size = Vector3.new(2, 6, 2), CFrame = at(-6, 3.5, -20) * CFrame.Angles(0.4, 0, 0), Color = Color3.fromRGB(120, 130, 150), Material = Enum.Material.Metal, Parent = zone })
	newPart({ Name = "ChartWall", Size = Vector3.new(0.3, 8, 10), CFrame = at(9.5, 8, -40), Color = Color3.fromRGB(40, 60, 110), Material = Enum.Material.Neon, Parent = zone })
	newPart({ Name = "Clock", Size = Vector3.new(0.3, 3, 3), CFrame = at(-9.5, 11, -30), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = zone })
	newPart({ Name = "Plant", Size = Vector3.new(2, 4, 2), CFrame = at(7, 2.5, -10), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = zone })
	newPart({ Name = "Monitor", Size = Vector3.new(0.3, 3, 5), CFrame = at(-9.5, 6, -50), Color = Color3.fromRGB(20, 30, 40), Material = Enum.Material.Glass, Parent = zone })
	newPart({ Name = "Window", Size = Vector3.new(8, 8, 0.3), CFrame = at(0, 9, -HALL_LEN - 5.4), Color = Color3.fromRGB(180, 200, 230), Transparency = 0.4, Material = Enum.Material.Glass, Parent = zone })
	newPart({ Name = "Bench", Size = Vector3.new(6, 2, 2), CFrame = at(6, 1.5, -60), Color = Color3.fromRGB(90, 70, 55), Material = Enum.Material.Wood, Parent = zone })
	newPart({ Name = "Mirror", Size = Vector3.new(0.3, 6, 4), CFrame = at(9.5, 6, -64), Color = Color3.fromRGB(200, 220, 240), Reflectance = 0.6, Material = Enum.Material.Glass, Parent = zone })
	-- z must stay IN FRONT of the EndWall (centre z = -(HALL_LEN+6), 1 thick -> front face at
	-- -(HALL_LEN+5.5)). At -5.9 the sign was buried inside the wall and invisible, which made
	-- the `sign_swap` anomaly unspottable (a guaranteed unfair Day reset).
	newPart({ Name = "ExitSign", Size = Vector3.new(4, 1.5, 0.3), CFrame = at(0, 13, -HALL_LEN - 5.0), Color = Color3.fromRGB(40, 200, 90), Material = Enum.Material.Neon, Parent = zone })
	newPart({ Name = "DoorMain", Size = Vector3.new(5, 12, 0.5), CFrame = at(0, 6, -HALL_LEN - 5.6), Color = Color3.fromRGB(70, 55, 45), Material = Enum.Material.Wood, Parent = zone })
	-- four chairs (count_off / chair_moved touch these)
	for i = 1, 4 do
		newPart({ Name = "Chair" .. i, Size = Vector3.new(2, 3, 2), CFrame = at(-6, 1.5, -44 - i * 3), Color = Color3.fromRGB(80, 80, 95), Parent = zone })
	end

	-- spawn pad (start of the loop) + decision pads (end)
	newPart({ Name = "StartPad", Size = Vector3.new(6, 0.2, 6), CFrame = at(0, 1, -4), Color = Color3.fromRGB(60, 90, 140), Material = Enum.Material.Neon, Transparency = 0.3, Parent = zone })

	-- Floating dust motes down the length of the hall — cheap, code-only atmosphere. Rebuilt
	-- with the rest of the clean hall each pass, so it can never linger as a false "anomaly".
	Fx.dustVolume(zone, Vector3.new(18, 14, HALL_LEN), at(0, 8, -HALL_LEN / 2), Color3.fromRGB(200, 210, 230), 10)
end

-- create a dark humanoid-shaped "figure" (no AI, purely visual)
local function makeFigure(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Figure"
	local torso = newPart({ Name = "Torso", Size = Vector3.new(2, 3, 1), CFrame = cf, Color = Color3.fromRGB(8, 8, 12), Material = Enum.Material.SmoothPlastic })
	torso.Parent = m
	local head = newPart({ Name = "Head", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = cf * CFrame.new(0, 2.2, 0), Color = Color3.fromRGB(8, 8, 12) })
	head.Parent = m
	local eye = Instance.new("PointLight")
	eye.Color = Color3.fromRGB(255, 60, 60)
	eye.Brightness = 3
	eye.Range = 8
	eye.Parent = head
	m.PrimaryPart = torso
	return m
end

local function findPart(zone: Model, name: string): Part?
	local p = zone:FindFirstChild(name)
	return (p and p:IsA("Part")) and p or nil
end

local function setLights(zone: Model, on: boolean)
	local lights = zone:FindFirstChild("Lights")
	if not lights then return end
	for _, ref in lights:GetChildren() do
		if ref:IsA("ObjectValue") and ref.Value then
			local fix = ref.Value :: Part
			local pl = fix:FindFirstChild("PL")
			if pl and pl:IsA("PointLight") then
				pl.Enabled = on
			end
			fix.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

-- Apply exactly one anomaly to an already-clean zone. Keyed by anomaly id; every entry makes
-- a genuinely spottable change (the hall is rebuilt clean before each pass, so no reset code
-- is needed). Missing parts are tolerated (pcall-free nil checks) so a mutated scene can't
-- error the loop.
local APPLIERS: { [string]: (Model, Vector3) -> () } = {
	figure_end = function(zone, origin)
		makeFigure(CFrame.new(origin + Vector3.new(0, 2.5, -HALL_LEN - 3)) * CFrame.Angles(0, math.pi, 0)).Parent = zone
	end,
	door_extra = function(zone, origin)
		newPart({ Name = "DoorExtra", Size = Vector3.new(5, 12, 0.5), CFrame = CFrame.new(origin + Vector3.new(-8, 6, -70)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(70, 55, 45), Material = Enum.Material.Wood, Parent = zone })
	end,
	scope_gone = function(zone)
		local p = findPart(zone, "Telescope"); if p then p:Destroy() end
	end,
	lights_out = function(zone)
		setLights(zone, false)
	end,
	chart_flip = function(zone)
		-- ChartWall is a plain uniform-colour box: a bare 180° flip about a principal axis maps
		-- it exactly onto itself and is INVISIBLE (the player is reset for an unspottable pass).
		-- Flip it AND hang it crooked + slipped along the wall so the change is unmistakable.
		local p = findPart(zone, "ChartWall")
		if p then
			p.CFrame = p.CFrame * CFrame.new(0, -2, 3) * CFrame.Angles(math.pi, 0, math.rad(28))
		end
	end,
	poster_red = function(zone)
		local p = findPart(zone, "ChartWall"); if p then p.Color = Color3.fromRGB(200, 40, 40) end
	end,
	chair_moved = function(zone)
		local p = findPart(zone, "Chair1"); if p then p.CFrame = p.CFrame * CFrame.new(4, 0, 3) end
	end,
	clock_stop = function(zone)
		local p = findPart(zone, "Clock"); if p then p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(140)) end
	end,
	twin_scope = function(zone)
		local p = findPart(zone, "Telescope"); if p then local c = p:Clone(); c.Name = "TelescopeTwin"; c.CFrame = p.CFrame * CFrame.new(4, 0, 0); c.Parent = zone end
	end,
	reflection_off = function(zone)
		local p = findPart(zone, "Mirror"); if p then p.Reflectance = 0; p.Color = Color3.fromRGB(20, 20, 30); p.Transparency = 0.1 end
	end,
	flicker_hall = function(zone)
		local lights = zone:FindFirstChild("Lights")
		if not lights then return end
		local ref = lights:FindFirstChild("L3")
		if ref and ref:IsA("ObjectValue") and ref.Value then
			local fix = ref.Value :: Part
			fix.Color = Color3.fromRGB(90, 255, 120)
			local pl = fix:FindFirstChild("PL")
			if pl and pl:IsA("PointLight") then
				pl.Color = Color3.fromRGB(90, 255, 120)
			end
		end
	end,
	scale_bench = function(zone)
		local p = findPart(zone, "Bench"); if p then p.Size = p.Size * 1.7 end
	end,
	figure_window = function(zone, origin)
		-- Must stay on the PLAYER side of EndWall (z = -HALL_LEN - 6, opaque, full cross-section)
		-- and of the Window pane (z = -HALL_LEN - 5.4): anything beyond is sealed out of sight.
		-- Floating in front of the pane at window height reads as "a face in the window".
		makeFigure(CFrame.new(origin + Vector3.new(0, 9, -HALL_LEN - 4.2)) * CFrame.Angles(0, math.pi, 0)).Parent = zone
	end,
	plant_gone = function(zone)
		local p = findPart(zone, "Plant"); if p then p:Destroy() end
	end,
	sign_swap = function(zone)
		local p = findPart(zone, "ExitSign"); if p then p.CFrame = p.CFrame * CFrame.Angles(0, math.pi, 0); p.Color = Color3.fromRGB(200, 120, 30) end
	end,
	floor_tilt = function(zone)
		local p = findPart(zone, "Floor"); if p then p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(4)) end
	end,
	dupe_door = function(zone, origin)
		newPart({ Name = "DoorDupe", Size = Vector3.new(5, 12, 0.5), CFrame = CFrame.new(origin + Vector3.new(6, 6, -HALL_LEN - 5.6)), Color = Color3.fromRGB(70, 55, 45), Material = Enum.Material.Wood, Parent = zone })
	end,
	moon_recolor = function(zone)
		local p = findPart(zone, "Window"); if p then p.Color = Color3.fromRGB(200, 40, 40); p.Transparency = 0.2 end
	end,
	static_screen = function(zone)
		local p = findPart(zone, "Monitor"); if p then p.Color = Color3.fromRGB(200, 200, 200); p.Material = Enum.Material.Neon end
	end,
	figure_ceiling = function(zone, origin)
		makeFigure(CFrame.new(origin + Vector3.new(0, 14, -HALL_LEN / 2)) * CFrame.Angles(math.pi, 0, 0)).Parent = zone
	end,
	mirror_extra = function(zone, origin)
		newPart({ Name = "MirrorExtra", Size = Vector3.new(0.3, 6, 4), CFrame = CFrame.new(origin + Vector3.new(9.5, 6, -30)), Color = Color3.fromRGB(200, 220, 240), Reflectance = 0.6, Material = Enum.Material.Glass, Parent = zone })
	end,
	scope_tilt = function(zone)
		local p = findPart(zone, "Telescope"); if p then p.CFrame = p.CFrame * CFrame.Angles(-1.4, 0, 0) end
	end,
	cold_breath = function(zone, origin)
		newPart({ Name = "Fog", Size = Vector3.new(18, 14, 30), CFrame = CFrame.new(origin + Vector3.new(0, 8, -HALL_LEN / 2)), Color = Color3.fromRGB(220, 230, 240), Transparency = 0.75, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = zone })
	end,
	count_off = function(zone)
		local p = findPart(zone, "Chair4"); if p then p:Destroy() end
	end,
}

-- ------------------------------------------------------------------ Prompts
local function makePrompt(parent: Part, text: string, key: Enum.KeyCode?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = text
	pp.ObjectText = "Observatory"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	if key then
		pp.KeyboardKeyCode = key
	end
	pp.Parent = parent
	return pp
end

-- ------------------------------------------------------------------ Loop
-- Minimum wall-clock time between a pass going live and a decision being accepted. Walking
-- the ~80-stud hall takes many seconds, so this only ever bites scripted triggers.
local MIN_PASS_SECONDS = 0.75

local function teleportToStart(plr: Player, origin: Vector3)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(origin + Vector3.new(0, 4, -4))
	end
end

-- Per-pass seed. THREE constraints:
--  1. No intermediate may exceed 2^53 or the low bits are silently rounded away (the old
--     `UserId * 2654435761` blew past it for every modern UserId, making the low bits — the
--     ones a power-of-two pool consumes — a CONSTANT for essentially every live player).
--  2. Every term multiplies by an ODD constant so the low bits actually vary.
--  3. `salt` is a per-SESSION server-only value, so the anomaly order is reproducible within
--     a session but not memorisable/recordable across sessions (Best-Day leaderboard).
local SEED_MOD = 4294967296 -- 2^32, matches Rng's state space
local UID_MOD = 1000003 -- prime; keeps UserId small before it is multiplied

-- Avalanche mix so consecutive serials don't merely step by a fixed stride (a linear seed
-- through an LCG leaves a visible low-bit cycle on a power-of-two pool). Defense-in-depth:
-- correctness does not depend on it, but it holds even if a caller consumes low bits.
-- OVERFLOW BOUND: bit32 results are < 2^32 and both multipliers are < 2^21, so the largest
-- product is 4294967295 * 2038073 = 8.75e15 < 2^53 — every step is exact.
local function mixSeed(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = (x * 2038073) % SEED_MOD
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 1832993) % SEED_MOD
	return bit32.bxor(x, bit32.rshift(x, 16))
end

local function passSeed(plr: Player, salt: number, serial: number): number
	local uid = plr.UserId % UID_MOD -- <= 1e6
	local sum = (Config.WorldSeed % SEED_MOD) -- < 4.3e9
		+ (salt % SEED_MOD) -- < 4.3e9
		+ uid * 40503 -- < 4.1e10
		+ (serial % UID_MOD) * 2654435 -- < 2.7e12  (total stays ~3 orders under 2^53)
	return mixSeed(sum % SEED_MOD)
end

local function pushState(plr: Player)
	local prof = profiles[plr]
	local ps = passState[plr]
	if not prof or not ps then return end
	StateRemote:FireClient(plr, {
		day = ps.day,
		best = prof.bestDay,
		hintTokens = prof.hintTokens,
		tint = prof.tint,
		-- S11: count only ids the CURRENT catalog still knows. A returning player's persisted
		-- set can hold ids a later catalog renamed/dropped; Codex.count would then report
		-- nonsense like "27/24" in the HUD.
		codexCount = Codex.countKnown(prof.caught, function(id)
			return Anomaly.byId(Config, id) ~= nil
		end),
		codexTotal = Anomaly.count(Config),
		tints = Config.Tints,
		ownedTints = prof.ownedTints, -- which of `tints` this player may actually select
	})
end

-- Rebuild the hall and roll the next pass for this player.
beginPass = function(plr: Player)
	local prof = profiles[plr]
	local ps = passState[plr]
	local zone = zones[plr]
	if not prof or not ps or not zone then return end

	local index = tonumber(zone:GetAttribute("Index")) or 0
	local origin = zoneOrigin(index)

	-- rebuild CLEAN
	zone:ClearAllChildren()
	buildClean(zone, origin)

	-- roll
	ps.serial += 1
	local rng = Rng.new(passSeed(plr, ps.salt, ps.serial))
	local pass = Anomaly.rollPass(rng, Config, ps.day)
	ps.clean = pass.clean
	ps.anomalyId = pass.anomalyId
	ps.awaiting = true
	ps.startedAt = os.clock()

	if not pass.clean and pass.anomalyId then
		local applier = APPLIERS[pass.anomalyId]
		if applier then
			applier(zone, origin)
		end
	end

	-- decision prompts on the end wall
	local endWall = findPart(zone, "EndWall")
	if endWall then
		local advPart = newPart({ Name = "AdvancePad", Size = Vector3.new(3, 6, 1), CFrame = endWall.CFrame * CFrame.new(-4, -3, 1), Color = Color3.fromRGB(50, 160, 90), Material = Enum.Material.Neon, Parent = zone })
		local backPart = newPart({ Name = "BackPad", Size = Vector3.new(3, 6, 1), CFrame = endWall.CFrame * CFrame.new(4, -3, 1), Color = Color3.fromRGB(180, 70, 60), Material = Enum.Material.Neon, Parent = zone })
		local advPrompt = makePrompt(advPart, "ADVANCE", Enum.KeyCode.E)
		local backPrompt = makePrompt(backPart, "TURN BACK", Enum.KeyCode.Q)
		advPrompt.Triggered:Connect(function(who)
			if who == plr then resolveChoice(plr, Progression.ADVANCE) end
		end)
		backPrompt.Triggered:Connect(function(who)
			if who == plr then resolveChoice(plr, Progression.TURN_BACK) end
		end)
	end

	-- hint prompt at the start pad
	local startPad = findPart(zone, "StartPad")
	if startPad then
		local hintPrompt = makePrompt(startPad, "USE HINT", Enum.KeyCode.H)
		hintPrompt.Triggered:Connect(function(who)
			if who == plr then useHint(plr) end
		end)
	end

	teleportToStart(plr, origin)
	pushState(plr)
end

resolveChoice = function(plr: Player, choice: string)
	local prof = profiles[plr]
	local ps = passState[plr]
	if not prof or not ps or not ps.awaiting then
		return -- ignore double-triggers / triggers between passes
	end
	-- Plausibility gate: ProximityPrompt.Triggered can be fired programmatically, so a bot
	-- could farm the Best-Day board at machine speed. The hall is ~80 studs; no human reaches
	-- the pads within MIN_PASS_SECONDS. Keep `awaiting` set so a real player can simply retry.
	if os.clock() - (ps.startedAt or 0) < MIN_PASS_SECONDS then
		return
	end
	ps.awaiting = false

	local pass = { clean = ps.clean, anomalyId = ps.anomalyId }
	local newState, res = Progression.resolve({ day = ps.day }, choice, pass, Config)

	-- record a caught anomaly in the Field Guide
	local caughtId = Progression.caughtAnomalyId(choice, pass)
	if caughtId then
		Codex.discover(prof.caught, caughtId)
	end

	if res.correct then
		ps.day = newState.day
		-- new best?
		local newBest = Progression.bestAfter(prof.bestDay, res.day)
		if newBest > prof.bestDay then
			prof.bestDay = newBest
			publishBest(plr)
			awardMilestone(plr, newBest)
		end
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			local d = ls:FindFirstChild("Day"); if d then (d :: IntValue).Value = ps.day end
			local b = ls:FindFirstChild("Best"); if b then (b :: IntValue).Value = prof.bestDay end
		end
		beginPass(plr)
	else
		local reached = ps.day
		ps.day = Config.Progression.StartDay
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			local d = ls:FindFirstChild("Day"); if d then (d :: IntValue).Value = ps.day end
		end
		DeathRemote:FireClient(plr, { reached = reached, wasClean = pass.clean, anomalyId = pass.anomalyId })
		task.wait(2.5) -- brief death beat
		if profiles[plr] then -- still here?
			beginPass(plr)
		end
	end
end

useHint = function(plr: Player)
	local prof = profiles[plr]
	local ps = passState[plr]
	if not prof or not ps or not ps.awaiting then return end
	if prof.hintTokens <= 0 then
		RevealRemote:FireClient(plr, { ok = false })
		return
	end
	prof.hintTokens -= 1
	RevealRemote:FireClient(plr, { ok = true, clean = ps.clean, remaining = prof.hintTokens })
	pushState(plr)
end

awardMilestone = function(plr: Player, day: number)
	-- Milestones are Config-listed; badge asset ids are wired in Config later.
	-- Kept idempotent + pcall-guarded so it can never break the loop.
	-- (Badge wiring intentionally deferred until real Badge asset ids exist.)
end

-- ------------------------------------------------------------------ Remote handlers
RedeemRemote.OnServerEvent:Connect(function(plr, code)
	if typeof(code) ~= "string" then return end
	local prof = profiles[plr]
	if not prof then return end
	local result = Codes.redeem(code, prof.redeemed, Config)
	if not result.ok or not result.reward then
		RevealRemote:FireClient(plr, { redeem = result.reason or "unknown" })
		return
	end
	local key = Codes.normalize(code)

	-- A one-time reward we cannot PERSIST is a reward that can be farmed once per lockless
	-- session (after a load failure the redeemed set is empty, so every code looks unused).
	-- Refuse instead of granting into thin air.
	if not profileStore or not prof.canSave then
		RevealRemote:FireClient(plr, {
			redeem = "unavailable",
			message = "Saving is unavailable right now — try the code again in a minute.",
		})
		return
	end

	-- Atomic flush: mark redeemed + grant in ONE UpdateAsync so a crash can't dupe/lose it.
	local applied = false
	local alreadyOnRecord = false
	local lockBlocked = false
	local ok2 = pcall(function()
		profileStore:UpdateAsync("u_" .. plr.UserId, function(old)
			old = old or {}
			applied, alreadyOnRecord, lockBlocked = false, false, false -- reset per transform attempt
			-- never grant through a live foreign session's lock
			local lock = old.lock
			if type(lock) == "table" and lock.token ~= prof.lockToken then
				if (nowStamp() - (tonumber(lock.at) or 0)) < Config.Save.SessionLockSeconds then
					lockBlocked = true
					return old
				end
			end
			old.redeemed = old.redeemed or {}
			if old.redeemed[key] then
				alreadyOnRecord = true -- genuinely used before; distinct from a failed write
				return old
			end
			old.redeemed[key] = true
			if result.reward.hintTokens then
				old.hintTokens = (old.hintTokens or 0) + result.reward.hintTokens
			end
			if result.reward.tint then
				old.ownedTints = old.ownedTints or { [Config.DefaultTint] = true }
				old.ownedTints[result.reward.tint] = true -- OWNERSHIP is persistent + separate
				old.tint = result.reward.tint
			end
			old.lock = { at = nowStamp(), token = prof.lockToken }
			applied = true
			return old
		end)
	end)

	if ok2 and applied then
		prof.redeemed[key] = true
		if result.reward.hintTokens then prof.hintTokens += result.reward.hintTokens end
		if result.reward.tint then
			prof.ownedTints[result.reward.tint] = true
			prof.tint = result.reward.tint
		end
		RevealRemote:FireClient(plr, { redeem = "ok", reward = result.reward })
		pushState(plr)
	elseif ok2 and alreadyOnRecord then
		prof.redeemed[key] = true -- keep memory in step with the record
		RevealRemote:FireClient(plr, { redeem = "already" })
	elseif ok2 and lockBlocked then
		RevealRemote:FireClient(plr, {
			redeem = "retry",
			message = "Another session is holding your save — nothing was used, try again in a minute.",
		})
	else
		-- transient: throttle / outage / foreign lock. NOTHING was granted, so never claim
		-- the code was already used — the player must be able to retry.
		RevealRemote:FireClient(plr, {
			redeem = "retry",
			message = "Couldn't reach the save service — nothing was used, try again shortly.",
		})
	end
end)

HintRemote.OnServerEvent:Connect(function(plr)
	useHint(plr)
end)

TintRemote.OnServerEvent:Connect(function(plr, tint)
	if typeof(tint) ~= "string" then return end
	local prof = profiles[plr]
	if not prof then return end
	-- Only allow tints the player OWNS. Ownership lives in its own persistent set: using
	-- `prof.tint` as both "owned" and "selected" meant picking the free white tint destroyed
	-- a code-earned tint forever (a one-time code can't be redeemed twice).
	if not prof.ownedTints[tint] then
		return
	end
	prof.tint = tint
	pushState(plr)
end)

-- ------------------------------------------------------------------ Lifecycle
local function onCharacter(plr: Player, char: Model)
	local origin = zones[plr] and zoneOrigin(tonumber(zones[plr]:GetAttribute("Index")) or 0)
	if origin then
		task.wait(0.2)
		teleportToStart(plr, origin)
	end
end

Players.PlayerAdded:Connect(function(plr)
	local prof = loadProfile(plr)

	-- GHOST-SESSION GUARD. loadProfile YIELDS inside UpdateAsync. If the player left during
	-- that yield, PlayerRemoving already ran against empty tables and cleaned up nothing —
	-- so without this check we would install a profile for a player who is gone, and the
	-- autosave loop would renew their session lock every 20s (TTL 45s) for the life of the
	-- server. That locks the real player out of saving on EVERY other server, and leaks the
	-- zone + its index. Release what we took and bail instead.
	if plr.Parent ~= Players then
		if prof.canSave then
			profiles[plr] = prof
			saveProfile(plr, true) -- release the lock we just claimed
			profiles[plr] = nil
		end
		return
	end

	profiles[plr] = prof

	-- leaderstats
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local day = Instance.new("IntValue"); day.Name = "Day"; day.Value = Config.Progression.StartDay; day.Parent = ls
	local best = Instance.new("IntValue"); best.Name = "Best"; best.Value = prof.bestDay; best.Parent = ls
	ls.Parent = plr

	-- private zone (index recycled from the free list, so origins never drift far out)
	local zone = Instance.new("Model")
	zone.Name = "Concourse_" .. plr.UserId
	zone:SetAttribute("Index", acquireZoneIndex())
	zone.Parent = workspace
	zones[plr] = zone
	passState[plr] = {
		day = Config.Progression.StartDay,
		clean = true,
		anomalyId = nil,
		serial = 0,
		awaiting = false,
		-- per-session salt: same sequence within this session, a different one next time
		salt = saltSource:NextInteger(0, 2147483646),
		startedAt = os.clock(),
	}

	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)

	beginPass(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	saveProfile(plr, true) -- flush + release lock
	local zone = zones[plr]
	if zone then
		releaseZoneIndex(tonumber(zone:GetAttribute("Index")) or 0)
		zone:Destroy()
	end
	profiles[plr] = nil
	zones[plr] = nil
	passState[plr] = nil
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do
		saveProfile(plr, true)
	end
	task.wait(1)
end)

-- Autosave loop (renews the soft lock). Second half of the ghost-session guard: REAP any
-- entry whose Player is no longer in the game instead of renewing its lock forever. Iterate a
-- snapshot, because saveProfile yields and the table is mutated by PlayerRemoving meanwhile.
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		local snapshot = {}
		for plr in profiles do
			table.insert(snapshot, plr)
		end
		for _, plr in snapshot do
			if not profiles[plr] then
				continue -- left while we were saving someone else
			end
			if plr.Parent ~= Players then
				-- ghost: flush + RELEASE the lock, then drop it so we stop renewing
				saveProfile(plr, true)
				local zone = zones[plr]
				if zone then
					releaseZoneIndex(tonumber(zone:GetAttribute("Index")) or 0)
					zone:Destroy()
				end
				profiles[plr] = nil
				zones[plr] = nil
				passState[plr] = nil
			else
				saveProfile(plr, false)
			end
		end
	end
end)

print("[Anomaly] Night Shift at the Observatory loaded.")
