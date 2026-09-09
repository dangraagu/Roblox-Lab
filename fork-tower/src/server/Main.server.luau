-- FORK TOWER — Would You Rather Obby (server, authoritative).
-- Lands in ServerScriptService. Every rule comes from ReplicatedStorage.Config and the pure,
-- unit-tested modules (Fork / Section / Build / Codes). Nothing here decides which door is the
-- trap; it asks Fork, builds what Fork said, and enforces it.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- SHAPE OF THE GAME
--   A player owns a LANE — their own tower, offset along X, exactly like grow-a-crystal's plots
--   and with the same index recycling, so a busy server never marches its lanes out to infinity.
--   Each floor is a FORK PAD carrying an inscription and two doors. Both doors grant their trait.
--   One of them is trapped: it builds a LONGER, busier section instead of a normal one. The
--   inscription names the sign that marks the trap (or, from Config.Fork.LiarFromFloor, says
--   outright that it marks the safe door instead), so the fork is always readable to certainty.
--   Climb the section, reach its top, meet the next fork. Ten floors up: the summit, and a Build
--   Reveal card generated from the picks. Rebirth rerolls the seed and the whole choice tree.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THE THREE TRAPS THIS FILE IS WRITTEN AROUND
--
--   1. AN UNPARENTED INSTANCE IS THE QUIETEST BUG IN ROBLOX. Grow a Crystal shipped a core loop
--      nobody could reach because one Part never had `.Parent` assigned: the function returned a
--      perfectly good Part, nothing raised, nothing warned, and all 166 unit tests stayed green
--      because none of them could see the workspace. So every Instance in this file is created
--      through `make(class, parent, props)`, which takes the parent as a REQUIRED argument and
--      asserts on it. There is no other way to make one here.
--
--   2. DataStoreService:GetDataStore RAISES in a place that has not been published, and again
--      when Studio API access is off. Unwrapped, that kills the whole script at load — no tower,
--      no remotes, no game, and the place cannot even be opened. Saving is what should degrade,
--      never the game.
--
--   3. A SILENT NO-OP IS A BUG REPORT WAITING TO HAPPEN. Every path that refuses a player action
--      tells them why, through the Notice remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Fork = require(ReplicatedStorage:WaitForChild("Fork"))
local Section = require(ReplicatedStorage:WaitForChild("Section"))
local BuildCard = require(ReplicatedStorage:WaitForChild("Build"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

Fx.applyLighting(Fx.Presets.Fork)

--============================================================================ tiny builders

local function c3(rgb)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- The only way an Instance is created in this file. `parent` is positional and required, and it
-- is assigned LAST, after every property, so nothing replicates half-built. See trap 1 above.
local function make(className: string, parent: Instance, props: { [string]: any }?): any
	assert(parent ~= nil, "make(" .. className .. "): every Instance must be parented")
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	inst.Parent = parent
	return inst
end

local function slab(parent: Instance, name: string, size: Vector3, pos: Vector3, color, material): BasePart
	return make("Part", parent, {
		Name = name,
		Anchored = true,
		CanCollide = true,
		Size = size,
		Position = pos,
		Material = material or Enum.Material.SmoothPlastic,
		Color = color,
	})
end

local function billboard(parent: Instance, name: string, text: string, offsetY: number, color, size: Vector2)
	local bb = make("BillboardGui", parent, {
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		StudsOffset = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = true,
		MaxDistance = 220,
	})
	make("TextLabel", bb, {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = color,
		TextStrokeTransparency = 0.35,
		Text = text,
	})
	return bb
end

--============================================================================ startup guard

-- The reachability invariant, re-checked at boot. Section.spec proves it for 200 levels across
-- every theme; this is the runtime half, so that a live tuning change to Config shows up in the
-- Output rather than as a floor nobody can climb. It warns rather than refusing to build: a
-- tuning mistake should not brick a running game.
do
	local firstBad, detail = nil, ""
	for level = 1, Config.Tower.Floors do
		for _, penalty in ipairs({ false, true }) do
			for seed = 1, 8 do
				local sec = Section.build(Config, seed, level, "fire", penalty, Rng)
				local ok, problems = Section.check(sec, Config)
				if not ok and firstBad == nil then
					firstBad = level
					detail = problems[1] or "?"
				end
			end
		end
	end
	if firstBad then
		warn(string.format(
			"[ForkTower] ADVARSEL: klarerbarhets-invarianten BRUTT på etasje %d (%s). Juster Config.Tower — tårnet kan bli uklarerbart!",
			firstBad, detail))
	end
end

--============================================================================ remotes

local remotes = make("Folder", ReplicatedStorage, { Name = "ForkRemotes" })
local StateEvent = make("RemoteEvent", remotes, { Name = "State" })
local NoticeEvent = make("RemoteEvent", remotes, { Name = "Notice" })
local RevealEvent = make("RemoteEvent", remotes, { Name = "Reveal" })
local RebirthEvent = make("RemoteEvent", remotes, { Name = "Rebirth" })
local ArmSkipEvent = make("RemoteEvent", remotes, { Name = "ArmSkip" })
local LeaderboardEvent = make("RemoteEvent", remotes, { Name = "Leaderboard" })
local RedeemFunc = make("RemoteFunction", remotes, { Name = "Redeem" })

local function notice(plr: Player, kind: string, text: string)
	NoticeEvent:FireClient(plr, { kind = kind, text = text })
end

--============================================================================ data

-- Trap 2. Unwrapped, this raises in an unpublished place and takes the whole server script with
-- it. Every write path below already checks `store`, so the game runs and only saving degrades.
local function tryStore(fn, what: string)
	if not Config.Save.Enabled then
		return nil
	end
	local ok, ds = pcall(fn)
	if ok then
		return ds
	end
	warn("[ForkTower] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") — the game runs, progress will NOT be saved this session.")
	return nil
end

local store = tryStore(function()
	return DataStoreService:GetDataStore(Config.Save.Store)
end, "profiles")
local orderedLB = tryStore(function()
	return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard)
end, "leaderboard")

type Profile = {
	runSeed: number,
	level: number, -- the fork still to answer; Floors + 1 means summited
	stage: string, -- "fork" | "climb" | "summit"
	picks: { string }, -- trait ids, in floor order
	slots: { number }, -- the door taken on each floor, in floor order
	skips: number,
	armedSkip: boolean, -- runtime only; never saved
	rebirths: number,
	bestScore: number,
	bestTitle: string,
	redeemed: { [string]: boolean },
	passes: { [string]: boolean },
	canSave: boolean, -- load-success sentinel: never write over data we failed to read
}

local profiles: { [Player]: Profile } = {}

local traitById = {}
for _, t in ipairs(Config.Traits) do
	traitById[t.id] = t
end

local function defaultProfile(): Profile
	return {
		runSeed = 1,
		level = 1,
		stage = "fork",
		picks = {},
		slots = {},
		skips = Config.Skips.StartSkips,
		armedSkip = false,
		rebirths = 0,
		bestScore = 0,
		bestTitle = "",
		redeemed = {},
		passes = {},
		canSave = false,
	}
end

-- JSON round-trips a Lua array fine, but only while it is DENSE: one hole and the whole thing
-- comes back as a string-keyed map. Rebuilding it as a dense list on load means a corrupted or
-- older save degrades to a shorter run instead of a table that silently is not an array.
local function denseList(v, coerce)
	local out = {}
	if type(v) ~= "table" then
		return out
	end
	local i = 1
	while true do
		local item = v[i] ~= nil and v[i] or v[tostring(i)]
		if item == nil then
			break
		end
		out[i] = coerce(item)
		i += 1
	end
	return out
end

local function key(userId: number): string
	return "u_" .. userId
end

-- Load + soft session lock (anti-dupe). We ALWAYS read the real data, even when another live
-- session holds the lock — we simply play READ-ONLY (canSave = false) rather than clobbering it.
-- The lock is refreshed by autosave and expires after SessionLockSeconds, so a crashed session
-- does not lock a player out and a fast rejoin never sees floor 1 again.
local function loadProfile(plr: Player): Profile
	local p = defaultProfile()
	if not store then
		return p
	end
	local acquired = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedUntil = tonumber(old.lockUntil) or 0
			local lockedByOther = lockedUntil > now and old.jobId ~= game.JobId
			if type(old.data) == "table" then
				local d = old.data
				p.runSeed = tonumber(d.runSeed) or 1
				p.level = math.max(1, math.floor(tonumber(d.level) or 1))
				p.stage = (d.stage == "climb" or d.stage == "summit") and d.stage or "fork"
				p.picks = denseList(d.picks, tostring)
				p.slots = denseList(d.slots, function(x)
					local n = tonumber(x) or 1
					return (n == 2) and 2 or 1
				end)
				p.skips = math.clamp(math.floor(tonumber(d.skips) or 0), 0, Config.Skips.MaxSkips)
				p.rebirths = math.floor(tonumber(d.rebirths) or 0)
				p.bestScore = math.floor(tonumber(d.bestScore) or 0)
				p.bestTitle = tostring(d.bestTitle or "")
				p.redeemed = (type(d.redeemed) == "table") and d.redeemed or {}
				p.passes = (type(d.passes) == "table") and d.passes or {}
			end
			if lockedByOther then
				acquired = false
				return old -- respect the other live session; do not touch the lock
			end
			acquired = true
			old.jobId = game.JobId
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		warn("[ForkTower] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		if not acquired then
			warn("[ForkTower] " .. plr.Name
				.. " lastet READ-ONLY (låst av en annen økt); progresjon denne økta lagres ikke.")
		end
	end

	-- A save can never describe a run past the top of the tower.
	if p.level > Config.Tower.Floors then
		p.level = Config.Tower.Floors + 1
		p.stage = "summit"
	end
	return p
end

local function saveProfile(plr: Player, releaseLock: boolean)
	local p = profiles[plr]
	if not p or not p.canSave or not store then
		return
	end
	pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			old.data = {
				runSeed = p.runSeed, level = p.level, stage = p.stage,
				picks = p.picks, slots = p.slots, skips = p.skips,
				rebirths = p.rebirths, bestScore = p.bestScore, bestTitle = p.bestTitle,
				redeemed = p.redeemed, passes = p.passes,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if orderedLB and p.bestScore > 0 then
		pcall(function()
			orderedLB:SetAsync(key(plr.UserId), p.bestScore)
		end)
	end
end

--============================================================================ the world

local towers = make("Folder", workspace, { Name = "Towers" })

type Lane = {
	index: number,
	folder: Folder,
	origin: Vector3,
	plan: any,
	forkTop: { [number]: Vector3 }, -- floor -> the fork pad's top-centre, in world space
	forkFolder: { [number]: Folder },
	sectionFolder: { [number]: Folder },
	checkpoint: Vector3,
}

local lanes: { [Player]: Lane } = {}
local laneTaken: { [number]: boolean } = {}

-- Recycled, never incremented forever: a server that hands out a fresh index per join walks its
-- lanes out along +X until they are kilometres from spawn.
local function claimLane(): number
	for i = 0, Config.World.MaxLanes - 1 do
		if not laneTaken[i] then
			laneTaken[i] = true
			return i
		end
	end
	return 0
end

local function laneOrigin(index: number): Vector3
	return Vector3.new(index * Config.World.LaneSpacing, 0, 0)
end

--------------------------------------------------------------------- fork platform + doors

local function signStrip(door: BasePart, floorData, slot: number)
	local doorData = floorData.doors[slot]
	local n = #doorData.signs
	for i, kind in ipairs(doorData.signs) do
		local rgb = Config.Fork.SignColors[kind] or { 255, 255, 255 }
		-- Spread across the top of the door, so both signs are readable head-on from the pad.
		local dx = (i - (n + 1) / 2) * 2.4
		local nub = make("Part", door, {
			Name = "Sign_" .. kind,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			Size = Vector3.new(1.8, 1.8, 0.4),
			Position = door.Position + Vector3.new(dx, 3.4, -0.8),
			Material = Enum.Material.Neon,
			Color = c3(rgb),
		})
		nub:SetAttribute("Sign", kind)
		make("PointLight", nub, {
			Name = "SignGlow",
			Color = c3(rgb),
			Brightness = 1.6,
			Range = 12,
		})
		billboard(nub, "SignLabel", Config.Fork.SignEmoji[kind] or "?", 1.4, c3(rgb), Vector2.new(72, 60))
	end
end

local onDoorChosen -- forward declaration; the prompt handler needs it

local function buildFork(plr: Player, lane: Lane, level: number)
	if lane.forkFolder[level] then
		return
	end
	local floorData = lane.plan.floors[level]
	local top = lane.forkTop[level]
	local W = Config.World

	local folder = make("Folder", lane.folder, { Name = "Fork_" .. level })
	lane.forkFolder[level] = folder

	local padSize = Vector3.new(W.ForkPadSize[1], W.ForkPadSize[2], W.ForkPadSize[3])
	local pad = slab(folder, "ForkPad_" .. level, padSize,
		top - Vector3.new(0, padSize.Y / 2, 0), Color3.fromRGB(58, 54, 78), Enum.Material.Slate)
	-- The inscription's own data, on the pad. Every one of these is ALSO carved on the doors in
	-- front of the player, so replicating them leaks nothing that is not already visible — and it
	-- is what lets the headless check read a fork the way a player reads it.
	pad:SetAttribute("Level", level)
	pad:SetAttribute("TellKind", floorData.tellKind)
	pad:SetAttribute("RuleInverted", floorData.ruleInverted)

	billboard(pad, "Inscription",
		string.format("ETASJE %d/%d\n%s %s", level, Config.Tower.Floors,
			floorData.ruleSign, floorData.ruleText),
		6, if floorData.ruleInverted then Color3.fromRGB(255, 140, 140) else Color3.fromRGB(255, 232, 170),
		Vector2.new(420, 120))

	make("PointLight", pad, {
		Name = "PadGlow",
		Color = Color3.fromRGB(220, 200, 255),
		Brightness = 2,
		Range = 34,
	})
	-- Signature particle #1: the fork platform breathes. Code-only, no assets. Fx.dustVolume
	-- parents its own invisible host part into `folder`, which is why the headless check counts
	-- ten BaseParts on a fresh lane rather than nine.
	Fx.dustVolume(folder, Vector3.new(26, 12, 20), CFrame.new(top + Vector3.new(0, 6, 2)),
		Color3.fromRGB(196, 178, 238), 10)

	for slot = 1, 2 do
		local doorData = floorData.doors[slot]
		local trait = traitById[doorData.traitId]
		local theme = Config.Themes[doorData.theme]
		local sx = (if slot == 1 then -1 else 1) * W.DoorSpread
		local doorSize = Vector3.new(W.DoorSize[1], W.DoorSize[2], W.DoorSize[3])
		local door = slab(folder, "Door_" .. level .. "_" .. slot, doorSize,
			top + Vector3.new(sx, doorSize.Y / 2, W.DoorDepth),
			c3(theme.color), Enum.Material.SmoothPlastic)
		door.CanCollide = false -- you walk THROUGH the door you picked
		door:SetAttribute("Level", level)
		door:SetAttribute("Slot", slot)
		door:SetAttribute("Marked", doorData.signSet[floorData.tellKind] == true)
		door:SetAttribute("Signs", table.concat(doorData.signs, ","))

		make("PointLight", door, {
			Name = "DoorGlow",
			Color = c3(theme.accent),
			Brightness = 2.2,
			Range = 20,
		})
		billboard(door, "TraitLabel",
			(trait and trait.label or doorData.traitId) .. "\n" .. string.rep("★", trait and trait.power or 1),
			7.5, c3(theme.accent), Vector2.new(280, 90))
		signStrip(door, floorData, slot)

		local prompt = make("ProximityPrompt", door, {
			Name = "Choose",
			ActionText = "VELG",
			ObjectText = (trait and trait.label or doorData.traitId),
			HoldDuration = 0.35,
			MaxActivationDistance = 14,
			RequiresLineOfSight = false,
		})
		-- `plr` is the lane's OWNER, captured here; `who` is whoever pulled the prompt. They are
		-- passed separately because they are not the same question, and conflating them was a
		-- real defect: onDoorChosen used to look up `lanes[who]`, so pulling a door in somebody
		-- else's tower answered the puller's OWN fork at that floor. The engine's
		-- MaxActivationDistance makes it hard to reach from outside, which is exactly the kind of
		-- "can't really happen" that ships.
		prompt.Triggered:Connect(function(who)
			onDoorChosen(who, plr, level, slot)
		end)
	end
end

--------------------------------------------------------------------- the obby section

local function buildSection(plr: Player, lane: Lane, level: number, theme: string, penalty: boolean)
	if lane.sectionFolder[level] then
		return lane.sectionFolder[level]
	end
	local sec = Section.build(Config, lane.plan.runSeed, level, theme, penalty, Rng)
	local themeCfg = Config.Themes[theme] or Config.Themes.fire
	local material = Enum.Material[themeCfg.material] or Enum.Material.SmoothPlastic

	-- Sections start just past the doors and climb from the fork pad's own height.
	local base = lane.forkTop[level] + Vector3.new(0, 0, Config.World.DoorDepth + Config.Tower.TileSize)
	local folder = make("Folder", lane.folder, { Name = "Section_" .. level })
	lane.sectionFolder[level] = folder
	folder:SetAttribute("Level", level)
	folder:SetAttribute("Penalty", penalty)
	folder:SetAttribute("Theme", theme)

	for _, pf in ipairs(sec.platforms) do
		local pos = base + Vector3.new(pf.dx, pf.dy - sec.thickness / 2, pf.dz)
		local part = slab(folder, "Plat_" .. level .. "_" .. pf.index,
			Vector3.new(pf.size, sec.thickness, pf.size), pos, c3(themeCfg.color), material)
		part:SetAttribute("Level", level)
		part:SetAttribute("Index", pf.index)

		if pf.index == #sec.platforms then
			-- The exit platform: touching it clears the floor. Marked in neon so the player can
			-- see where the section ends from the bottom of it.
			part.Color = c3(themeCfg.accent)
			part.Material = Enum.Material.Neon
			part:SetAttribute("Exit", true)
			make("PointLight", part, {
				Name = "ExitGlow", Color = c3(themeCfg.accent), Brightness = 2.4, Range = 26,
			})
			-- Signature particle #2: anything the player CHASES glows. The top of a section is
			-- the only thing worth climbing toward, so it is the only thing that sparkles.
			Fx.sparkle(part, c3(themeCfg.accent))
		end

		part.Touched:Connect(function(hit)
			local char = hit and hit.Parent
			local who = char and Players:GetPlayerFromCharacter(char)
			if who ~= plr then
				return
			end
			local prof = profiles[plr]
			if not prof then
				return
			end
			-- Landing anywhere in the section moves your checkpoint up with you, so a hazard
			-- costs you a few platforms rather than the whole climb.
			lane.checkpoint = pos + Vector3.new(0, Config.World.RespawnLift, 0)
			if pf.index == #sec.platforms and prof.level == level and prof.stage == "climb" then
				lane.reachExit(level)
			end
		end)
	end

	for i, hz in ipairs(sec.hazards) do
		local part = make("Part", folder, {
			Name = "Hazard_" .. level .. "_" .. i,
			Anchored = true,
			CanCollide = false,
			Size = Vector3.new(hz.size, hz.size, hz.size),
			Position = base + Vector3.new(hz.dx, hz.dy, hz.dz),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 70, 70),
		})
		part:SetAttribute("Hazard", hz.kind)
		part.Touched:Connect(function(hit)
			local char = hit and hit.Parent
			local who = char and Players:GetPlayerFromCharacter(char)
			if who ~= plr then
				return
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				(hrp :: BasePart).CFrame = CFrame.new(lane.checkpoint)
				;(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
			end
			notice(plr, "hazard", "Au! Tilbake til sjekkpunktet.")
		end)
	end

	-- Where the NEXT fork platform goes: at the section's exit, a little further along +Z.
	lane.forkTop[level + 1] = base
		+ Vector3.new(sec.exit.dx, sec.exit.dy, sec.exit.dz + Config.Tower.TileSize / 2 + 12)
	return folder
end

--------------------------------------------------------------------- summit

local function buildSummit(plr: Player, lane: Lane)
	local level = Config.Tower.Floors + 1
	if lane.forkFolder[level] then
		return
	end
	local top = lane.forkTop[level]
	local folder = make("Folder", lane.folder, { Name = "Summit" })
	lane.forkFolder[level] = folder

	local pad = slab(folder, "SummitPad", Vector3.new(30, 2, 30),
		top - Vector3.new(0, 1, 0), Color3.fromRGB(90, 76, 130), Enum.Material.Marble)
	pad:SetAttribute("Summit", true)
	local plinth = slab(folder, "Plinth", Vector3.new(6, 5, 6),
		top + Vector3.new(0, 2.5, 0), Color3.fromRGB(255, 215, 100), Enum.Material.Neon)
	make("PointLight", plinth, {
		Name = "SummitGlow", Color = Color3.fromRGB(255, 220, 130), Brightness = 4, Range = 60,
	})
	billboard(plinth, "SummitLabel", "👑 TOPPEN\nBUILD REVEAL", 5,
		Color3.fromRGB(255, 235, 170), Vector2.new(320, 120))
end

--------------------------------------------------------------------- lane assembly

local function traitTotals(p: Profile)
	local jump, speed = Config.Jump.BaseJump, Config.WalkSpeed
	for _, id in ipairs(p.picks) do
		local t = traitById[id]
		if t then
			jump += t.jump or 0
			speed += t.speed or 0
		end
	end
	-- Clamped UPWARD to the traitless values on purpose. Section.spec proves every step is
	-- clearable at BaseJump and WalkSpeed; handing a player less than that would put them
	-- outside the proof. Config forbids negative traits for the same reason — this is the belt.
	jump = math.clamp(jump, Config.Jump.BaseJump, Config.Jump.MaxJumpHeight)
	speed = math.max(speed, Config.WalkSpeed)
	return jump, speed
end

local function applyTraits(plr: Player)
	local p = profiles[plr]
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not p or not hum then
		return
	end
	local jump, speed = traitTotals(p)
	hum.UseJumpPower = false
	hum.JumpHeight = jump
	hum.WalkSpeed = speed
end

local function pushState(plr: Player)
	local p = profiles[plr]
	if not p then
		return
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local f = ls:FindFirstChild("Floor")
		local b = ls:FindFirstChild("Best")
		local r = ls:FindFirstChild("Rebirths")
		if f then (f :: IntValue).Value = math.min(p.level, Config.Tower.Floors) end
		if b then (b :: IntValue).Value = p.bestScore end
		if r then (r :: IntValue).Value = p.rebirths end
	end

	local jump, speed = traitTotals(p)
	local floorData = (p.level <= Config.Tower.Floors) and lanes[plr] and lanes[plr].plan.floors[p.level] or nil
	StateEvent:FireClient(plr, {
		level = p.level,
		floors = Config.Tower.Floors,
		stage = p.stage,
		picks = p.picks,
		skips = p.skips,
		armedSkip = p.armedSkip,
		rebirths = p.rebirths,
		bestScore = p.bestScore,
		bestTitle = p.bestTitle,
		jumpHeight = jump,
		walkSpeed = speed,
		-- Exactly what is carved on the pad and the doors in front of them, nothing more.
		rule = floorData and {
			text = floorData.ruleText,
			sign = floorData.ruleSign,
			tellKind = floorData.tellKind,
			inverted = floorData.ruleInverted,
			doors = {
				{ label = floorData.doors[1].label, signs = floorData.doors[1].signs },
				{ label = floorData.doors[2].label, signs = floorData.doors[2].signs },
			},
		} or nil,
	})
end

local function revealFor(plr: Player, banked: boolean)
	local p = profiles[plr]
	if not p then
		return
	end
	local card = BuildCard.reveal(Config, p.picks)
	if banked and card.score > p.bestScore then
		p.bestScore = card.score
		p.bestTitle = card.title
	end
	card.rebirths = p.rebirths
	card.banked = banked
	RevealEvent:FireClient(plr, card)
	return card
end

local function teardownLane(plr: Player)
	local lane = lanes[plr]
	if not lane then
		return
	end
	-- One Destroy on the lane folder. Walking a Lua table of parts by name is how a server leaks
	-- an entire tower on every join, forever.
	lane.folder:Destroy()
	laneTaken[lane.index] = nil
	lanes[plr] = nil
end

local function buildLane(plr: Player)
	local p = profiles[plr]
	if not p then
		return
	end
	teardownLane(plr)

	local index = claimLane()
	local origin = laneOrigin(index)
	local folder = make("Folder", towers, { Name = "Lane_" .. index })
	folder:SetAttribute("Owner", plr.UserId)

	local lane: any = {
		index = index,
		folder = folder,
		origin = origin,
		plan = Fork.plan(Config, p.runSeed, Rng),
		forkTop = {},
		forkFolder = {},
		sectionFolder = {},
		checkpoint = origin + Vector3.new(0, Config.World.RespawnLift, -4),
	}
	lanes[plr] = lane

	-- reachExit lives on the lane so the section's Touched handlers can call it without a
	-- forward-declared upvalue chain through three closures.
	lane.reachExit = function(level: number)
		local prof = profiles[plr]
		if not prof or prof.level ~= level or prof.stage ~= "climb" then
			return
		end
		prof.level = level + 1
		prof.stage = "fork"
		if prof.level > Config.Tower.Floors then
			prof.stage = "summit"
			buildSummit(plr, lane)
			lane.checkpoint = lane.forkTop[prof.level] + Vector3.new(0, Config.World.RespawnLift, 0)
			revealFor(plr, true)
			notice(plr, "summit", "Du nådde toppen! Build Reveal er klar.")
		else
			buildFork(plr, lane, prof.level)
			lane.checkpoint = lane.forkTop[prof.level] + Vector3.new(0, Config.World.RespawnLift, 0)
			notice(plr, "floor", "Etasje " .. level .. " klarert. Les innskripsjonen.")
		end
		pushState(plr)
		saveProfile(plr, false)
	end

	local padSize = Vector3.new(Config.World.LobbyPadSize[1], Config.World.LobbyPadSize[2], Config.World.LobbyPadSize[3])
	local lobby = slab(folder, "LobbyPad", padSize, origin - Vector3.new(0, padSize.Y / 2, 6),
		Color3.fromRGB(48, 46, 66), Enum.Material.Slate)
	billboard(lobby, "Welcome",
		"🔀 FORK TOWER\nTo dører. Én er en felle.\nLES INNSKRIPSJONEN.", 8,
		Color3.fromRGB(235, 225, 255), Vector2.new(400, 140))
	make("SpawnLocation", folder, {
		Name = "LaneSpawn",
		Anchored = true,
		CanCollide = false,
		Transparency = 1,
		Size = Vector3.new(6, 1, 6),
		Position = origin + Vector3.new(0, 0.5, -4),
		Neutral = true,
		Enabled = false, -- we place the character ourselves; this is a marker, not a spawn point
	})

	-- Floor 1's fork sits just in front of the lobby pad; everything above it is placed by the
	-- section below it, so the tower's geometry is generated rather than tabulated.
	lane.forkTop[1] = origin + Vector3.new(0, 0, 14)

	-- Rebuild the run as far as the save says it got. Building the fork BEFORE placing the
	-- character matters: onCharacter puts you on your checkpoint, and a checkpoint that has not
	-- been built yet leaves you standing at the bottom of your own tower.
	for level = 1, math.min(p.level, Config.Tower.Floors) do
		buildFork(plr, lane, level)
		local slot = p.slots[level]
		if slot ~= nil then
			local floorData = lane.plan.floors[level]
			local doorData = floorData.doors[slot]
			local trapped = Fork.isTrap(floorData, slot)
			buildSection(plr, lane, level, doorData.theme, trapped)
		end
	end
	if p.level > Config.Tower.Floors then
		buildSummit(plr, lane)
	end

	local restoreLevel = math.min(p.level, Config.Tower.Floors + 1)
	if p.stage == "climb" and lane.sectionFolder[p.level] then
		-- Mid-climb: put them back at the bottom of the section they were on, not at the fork —
		-- the fork has already been answered and its prompts are disabled.
		local first = lane.sectionFolder[p.level]:FindFirstChild("Plat_" .. p.level .. "_1")
		if first then
			lane.checkpoint = (first :: BasePart).Position + Vector3.new(0, Config.World.RespawnLift, 0)
		end
	elseif lane.forkTop[restoreLevel] then
		lane.checkpoint = lane.forkTop[restoreLevel] + Vector3.new(0, Config.World.RespawnLift, 0)
	end

	-- A fork already answered must not be answerable again.
	for level = 1, Config.Tower.Floors do
		if p.slots[level] ~= nil and lane.forkFolder[level] then
			for _, d in ipairs(lane.forkFolder[level]:GetChildren()) do
				local prompt = d:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.Enabled = false
				end
			end
		end
	end
end

--============================================================================ choosing a door

onDoorChosen = function(plr: Player, owner: Player, level: number, slot: number)
	-- A door belongs to the tower it stands in. Checked FIRST, before anything reads the puller's
	-- own profile, so that a prompt fired from another lane can never advance anybody's run.
	if plr ~= owner then
		return
	end
	local p = profiles[plr]
	local lane = lanes[plr]
	if not p or not lane then
		return
	end
	-- Trap 3: never refuse silently.
	if p.stage == "summit" then
		notice(plr, "blocked", "Du er allerede på toppen — bruk REBIRTH for et nytt tårn.")
		return
	end
	if level ~= p.level then
		notice(plr, "blocked", "Den forken er ikke din nå. Du står på etasje " .. p.level .. ".")
		return
	end
	if p.stage ~= "fork" then
		notice(plr, "blocked", "Du har alt valgt på denne etasjen — klatr opp til neste fork.")
		return
	end

	local floorData = lane.plan.floors[level]
	local doorData = floorData.doors[slot]
	local trapped = Fork.isTrap(floorData, slot)

	-- A skip is armed BEFORE you walk through, which is the only moment at which spending it is
	-- a decision rather than a refund. It turns a trapped door's penalty section into a normal
	-- one; the trait is yours either way.
	local skipped = false
	if trapped and p.armedSkip and p.skips > 0 then
		p.skips -= 1
		p.armedSkip = false
		trapped = false
		skipped = true
	end

	p.picks[level] = doorData.traitId
	p.slots[level] = slot
	p.stage = "climb"

	buildSection(plr, lane, level, doorData.theme, trapped)
	local section = lane.sectionFolder[level]
	local first = section and section:FindFirstChild("Plat_" .. level .. "_1")
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if first and hrp then
		local target = (first :: BasePart).Position + Vector3.new(0, Config.World.RespawnLift, 0)
		;(hrp :: BasePart).CFrame = CFrame.new(target)
		;(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
		lane.checkpoint = target
	end

	for _, d in ipairs(lane.forkFolder[level]:GetChildren()) do
		local prompt = d:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end

	applyTraits(plr)
	if skipped then
		notice(plr, "skip", "SKIP brukt — fella ble en vanlig seksjon. " .. p.skips .. " igjen.")
	elseif trapped then
		notice(plr, "trap", "FELLE! " .. (doorData.label or "") .. " er din, men veien opp er lang.")
	else
		notice(plr, "safe", "Trygt valg: " .. (doorData.label or ""))
	end
	pushState(plr)
	saveProfile(plr, false)
end

--============================================================================ remotes: in

RebirthEvent.OnServerEvent:Connect(function(plr)
	local p = profiles[plr]
	if not p then
		return
	end
	if p.stage ~= "summit" then
		-- Allowed, but never by accident: the client asks twice, and this is the second answer.
		notice(plr, "rebirth", "Du ga opp runet. Nytt tårn, nytt valgtre.")
	else
		notice(plr, "rebirth", "Rebirth! Nytt frø, nytt valgtre.")
	end
	p.rebirths += 1
	p.runSeed += 1
	p.level = 1
	p.stage = "fork"
	p.picks = {}
	p.slots = {}
	p.armedSkip = false
	buildLane(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and lanes[plr] then
		(hrp :: BasePart).CFrame = CFrame.new(lanes[plr].checkpoint)
	end
	applyTraits(plr)
	pushState(plr)
	saveProfile(plr, false)
end)

ArmSkipEvent.OnServerEvent:Connect(function(plr, wanted)
	local p = profiles[plr]
	if not p then
		return
	end
	local want = wanted == true
	if want and p.skips <= 0 then
		notice(plr, "blocked", "Du har ingen skips igjen. Løs inn en kode.")
		p.armedSkip = false
		pushState(plr)
		return
	end
	p.armedSkip = want
	notice(plr, "skip", if want then "SKIP armert — neste felle koster deg ingenting." else "SKIP avvæpnet.")
	pushState(plr)
end)

RedeemFunc.OnServerInvoke = function(plr, input)
	local p = profiles[plr]
	if not p then
		return { ok = false, reason = "notready" }
	end
	local ok, reward, reason = Codes.redeem(input, p.redeemed, Config.Codes)
	if not ok then
		return { ok = false, reason = reason }
	end
	local code = Codes.normalize(input)
	-- Marked redeemed and paid in ONE atomic flush, so a crash between the two can neither dupe
	-- the code nor eat the reward. And if we cannot persist, we do not grant: an ungranted code
	-- can be redeemed again, a granted-but-unsaved one is free skips forever.
	if not p.canSave and store ~= nil then
		return { ok = false, reason = "nosave" }
	end
	p.redeemed[code] = true
	p.skips = math.min(p.skips + (reward.skips or 0), Config.Skips.MaxSkips)
	saveProfile(plr, false)
	pushState(plr)
	return { ok = true, reason = "ok", skips = reward.skips }
end

--============================================================================ leaderboard

local function refreshLeaderboard()
	if not orderedLB then
		return
	end
	local ok, page = pcall(function()
		return orderedLB:GetSortedAsync(false, 10)
	end)
	if not ok or not page then
		return
	end
	local top = {}
	for _, entry in ipairs(page:GetCurrentPage()) do
		local uid = tonumber((string.gsub(entry.key, "^u_", "")))
		top[#top + 1] = { userId = uid, score = entry.value }
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		LeaderboardEvent:FireClient(plr, top)
	end
end

--============================================================================ players

local function onCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local lane = lanes[plr]
	if hrp and lane then
		(hrp :: BasePart).CFrame = CFrame.new(lane.checkpoint)
	end
	applyTraits(plr)
	pushState(plr)

	-- Signature particle #3: a trail on the climber, so a jump reads as a jump in a clip or a
	-- thumbnail. Parented to the root part, not to the lane, so it costs the lane nothing.
	if hrp then
		Fx.trail(hrp :: BasePart, Color3.fromRGB(206, 172, 255), 0.45)
	end

	-- Fall rescue. A player who drops off the tower comes back to their checkpoint rather than
	-- to floor 1 — the punishment for a trap is a long climb, never a lost run.
	task.spawn(function()
		while char.Parent ~= nil and hum and hum.Health > 0 do
			local l = lanes[plr]
			if l and hrp and (hrp :: BasePart).Position.Y < l.checkpoint.Y - Config.World.FallGrace then
				(hrp :: BasePart).CFrame = CFrame.new(l.checkpoint)
				;(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
			end
			task.wait(0.4)
		end
	end)
end

local function onPlayerAdded(plr: Player)
	local p = loadProfile(plr)
	profiles[plr] = p

	local ls = make("Folder", plr, { Name = "leaderstats" })
	for _, n in ipairs({ "Floor", "Best", "Rebirths" }) do
		make("IntValue", ls, { Name = n })
	end

	buildLane(plr)

	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		onCharacter(plr, plr.Character)
	end

	if p.stage == "summit" then
		revealFor(plr, false) -- show the card they already earned, without re-banking it
	end
	pushState(plr)
end

local function onPlayerRemoving(plr: Player)
	saveProfile(plr, true) -- release the lock
	teardownLane(plr)
	profiles[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		saveProfile(plr, true)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in ipairs(Players:GetPlayers()) do
			saveProfile(plr, false)
		end
	end
end)

task.spawn(function()
	while true do
		refreshLeaderboard()
		task.wait(30)
	end
end)

print("[ForkTower] Fork Tower lastet. WorldSeed=" .. Config.WorldSeed
	.. " Floors=" .. Config.Tower.Floors)
