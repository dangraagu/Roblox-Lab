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

--============================================================================ the clock

-- ONE clock for every throttle below. os.clock() is the obvious-looking choice and it is WRONG
-- here: in Roblox it measures CPU time used by Lua, so on a quiet server a three-second cooldown
-- outlives the player who is waiting on it. GetServerTimeNow is the modern wall clock; tick() is
-- the fallback for engines (and for the headless harness) that do not have it. Probed once, at
-- load, rather than pcalled on every check.
local clock: () -> number
do
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	clock = if ok and type(t) == "number" then function()
		return (workspace :: any):GetServerTimeNow()
	end else tick
end

--============================================================================ startup guard

-- The reachability invariant, re-checked at boot. Section.spec proves it for 200 levels across
-- every theme; this is the runtime half, so that a live tuning change to Config shows up in the
-- Output rather than as a floor nobody can climb. It warns rather than refusing to build: a
-- tuning mistake should not brick a running game.
--
-- The tower is chained the way buildSection chains it — each section's exit is the next floor's
-- fork origin — because that chain is where the lane corridor is actually spent. Checking ten
-- independent sections would have said nothing about the run that walks through all ten.
do
	local firstBad, detail = nil, ""
	for _, penalty in ipairs({ false, true }) do
		for seed = 1, 8 do
			local originX = 0
			for level = 1, Config.Tower.Floors do
				local sec = Section.build(Config, seed, level, "fire", penalty, Rng, originX)
				local ok, problems = Section.check(sec, Config)
				if not ok and firstBad == nil then
					firstBad = level
					detail = problems[1] or "?"
				end
				originX += sec.exit.dx
			end
		end
	end
	if firstBad then
		warn(string.format(
			"[ForkTower] ADVARSEL: klarerbarhets-invarianten BRUTT på etasje %d (%s). Juster Config.Tower — tårnet kan bli uklarerbart!",
			firstBad, detail))
	end

	-- The write budget. Roblox grants the SERVER 60 + 10 per player UpdateAsync calls a minute. A
	-- floor of S seconds between one player's writes caps them at 60/S a minute, so N players cost
	-- 60N/S — which stays inside 60 + 10N for every N exactly when S >= 6. This is the assertion
	-- that says SaveMinInterval is derived and not decorative.
	if 60 / Config.Limits.SaveMinInterval > 10 then
		warn(string.format(
			"[ForkTower] ADVARSEL: SaveMinInterval %.1fs gir %.0f skriv/spiller/minutt — over de 10 Roblox gir pr spiller. En full server vil miste lagringer.",
			Config.Limits.SaveMinInterval, 60 / Config.Limits.SaveMinInterval))
	end
	-- The autosave loop is the only thing refreshing the session lock, so it has to run inside it.
	if Config.Save.AutosaveSeconds >= Config.Save.SessionLockSeconds then
		warn(string.format(
			"[ForkTower] ADVARSEL: AutosaveSeconds (%d) >= SessionLockSeconds (%d) — session-låsen rekker å utløpe mellom to lagringer.",
			Config.Save.AutosaveSeconds, Config.Save.SessionLockSeconds))
	end

	-- The lane budget. A corridor that does not fit inside half a lane means two towers touch,
	-- and Config is the only place either number lives.
	local WIDEST_PAD = 30 -- the summit pad; the fork and lobby pads are 26
	if Config.World.CorridorHalfWidth + WIDEST_PAD / 2 > Config.World.LaneSpacing / 2 then
		warn(string.format(
			"[ForkTower] ADVARSEL: korridoren (%.0f) + bredeste plate (%.0f) går utenfor halve banen (%.0f) — nabotårn kan overlappe!",
			Config.World.CorridorHalfWidth, WIDEST_PAD / 2, Config.World.LaneSpacing / 2))
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
	-- WHICH FLOORS THE PLAYER HAS PAID FOR. Both are saved, and both are saved because losing
	-- them costs the player something they already spent:
	--   readFloors — the inscription costs Config.Fork.ReadSeconds to read; a rejoin that made
	--                you pay again would charge twice for one fork.
	--   skipped    — a skip spent on a floor turned that floor's trap into a normal section.
	--                Nothing recorded THAT, so buildLane recomputed `Fork.isTrap` on rejoin and
	--                rebuilt the penalty section: the player lost the skip AND got the trap, and
	--                because Section.build mixes PENALTY_MIX into the seed the whole walk changed
	--                under them mid-climb.
	readFloors: { [number]: boolean },
	skipped: { [number]: boolean },
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
		readFloors = {},
		skipped = {},
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

-- A set of floor numbers, stored as a DENSE LIST of levels rather than as a map. JSON turns a
-- table with numeric keys into a string-keyed object, so `saved.readFloors[3]` comes back nil and
-- a player silently pays for every read a second time. A list of levels round-trips through
-- denseList above, which is already the shape this file trusts.
local function levelSet(v): { [number]: boolean }
	local out = {}
	for _, n in ipairs(denseList(v, tonumber)) do
		local level = math.floor(tonumber(n) or 0)
		if level >= 1 and level <= Config.Tower.Floors then
			out[level] = true
		end
	end
	return out
end

local function levelList(set: { [number]: boolean }): { number }
	local out = {}
	for level = 1, Config.Tower.Floors do
		if set[level] then
			out[#out + 1] = level
		end
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
				p.readFloors = levelSet(d.readFloors)
				p.skipped = levelSet(d.skipped)
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

-- When each player's profile last actually reached the DataStore, and the score last published to
-- the ordered leaderboard.
local lastSaveAt: { [Player]: number } = {}
local lastBanked: { [Player]: number } = {}

-- `force` is for the writes that MUST land: leaving, BindToClose, and redeeming a code (which
-- grants a reward in memory and would otherwise be re-redeemable after a crash).
--
-- Everything else is COALESCED, and that is the fix for a real hole rather than a nicety. A
-- DataStore write comes out of a budget the whole SERVER shares — 60 + 10 per player per minute —
-- so any remote that makes the server write on demand lets one client starve every other player's
-- autosave and, with it, the 45-second session-lock refresh that is the only thing keeping their
-- session writable. Measured before this: 200 Rebirth fires in a single frame produced 200
-- UpdateAsync calls and nothing refused them.
local function saveProfile(plr: Player, releaseLock: boolean, force: boolean?)
	local p = profiles[plr]
	if not p or not p.canSave or not store then
		return
	end
	local t = clock()
	if not (force or releaseLock) and t - (lastSaveAt[plr] or -math.huge) < Config.Limits.SaveMinInterval then
		return -- the autosave loop below forces a write every AutosaveSeconds, so nothing is lost
	end
	lastSaveAt[plr] = t
	pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			old.data = {
				runSeed = p.runSeed, level = p.level, stage = p.stage,
				picks = p.picks, slots = p.slots, skips = p.skips,
				readFloors = levelList(p.readFloors), skipped = levelList(p.skipped),
				rebirths = p.rebirths, bestScore = p.bestScore, bestTitle = p.bestTitle,
				redeemed = p.redeemed, passes = p.passes,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	-- Only when it has actually MOVED. bestScore changes once per summit, so re-publishing it on
	-- every autosave was a second write per save buying nothing — the same amplification as above,
	-- one budget over.
	if orderedLB and p.bestScore > 0 and p.bestScore ~= lastBanked[plr] then
		local banked = p.bestScore
		local ok = pcall(function()
			orderedLB:SetAsync(key(plr.UserId), banked)
		end)
		if ok then
			lastBanked[plr] = banked
		end
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

-- HOW MANY LANES THERE ARE, and why it is not just Config.World.MaxLanes.
--
-- Nothing in this repo coupled MaxLanes to the place's max-player count — default.project.json
-- has no Workspace or place-config entry at all — so the 24 was one Studio slider away from being
-- smaller than the number of players who can be in the server. MaxLanes is therefore a FLOOR, and
-- the pool is sized to whichever is larger. That makes "every player in this server stands in a
-- tower nobody else is standing in" true by construction instead of by hoping the slider agrees.
local laneCount = math.max(Config.World.MaxLanes, tonumber(Players.MaxPlayers) or 0)

-- Recycled, never incremented forever: a server that hands out a fresh index per join walks its
-- lanes out along X until they are kilometres from spawn.
--
-- Returns NIL when the pool is empty, never 0. Handing back a real-looking index for "no room"
-- is exactly what built the 25th player's tower at the coordinates of the first player's, and
-- teardownLane then freed that index on their way out while the original owner was still standing
-- in it, so the collision spread instead of clearing.
local function claimLane(): number?
	for i = 0, laneCount - 1 do
		if not laneTaken[i] then
			laneTaken[i] = true
			return i
		end
	end
	return nil
end

local function hasFreeLane(): boolean
	for i = 0, laneCount - 1 do
		if not laneTaken[i] then
			return true
		end
	end
	return false
end

-- Alternating around the origin — 0, +1, -1, +2, -2 — rather than marching out along +X, so a
-- full server's furthest tower is half as far from spawn.
local function laneOrigin(index: number): Vector3
	local step = math.floor((index + 1) / 2)
	local dir = if index % 2 == 1 then 1 else -1
	return Vector3.new(dir * step * Config.World.LaneSpacing, 0, 0)
end

-- Somewhere solid for a player the server has no lane for, and the place's only ENABLED
-- SpawnLocation. Without one, Roblox drops a character at the world origin: over a sealed shell
-- that is the roof, and over a tower with no floor at (0,0,0) it is a fall with no bottom. Placed
-- well behind every lobby pad on Z, so it sits in nobody's corridor.
local waiting = make("Folder", workspace, { Name = "Waiting" })
do
	local pad = slab(waiting, "WaitingPad", Vector3.new(30, 2, 30),
		Vector3.new(0, -1, -160), Color3.fromRGB(44, 42, 62), Enum.Material.Slate)
	billboard(pad, "WaitingLabel", "🔀 FORK TOWER\nVenter på et ledig tårn …", 8,
		Color3.fromRGB(235, 225, 255), Vector2.new(400, 120))
	make("SpawnLocation", waiting, {
		Name = "WaitingSpawn",
		Anchored = true,
		CanCollide = false,
		Transparency = 1,
		Size = Vector3.new(6, 1, 6),
		Position = Vector3.new(0, 0.5, -160),
		Neutral = true,
		Enabled = true,
	})
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
local onReadInscription -- ... and so does the inscription's

--------------------------------------------------------------------- read / unread dressing

-- THE INSCRIPTION IS THE ONLY INFORMATION IN THE WORLD.
--
-- This function is REVIEW-2's headline finding, made into code. The finding was that the optimal
-- way to play Fork Tower was to never read an inscription: the door's star count was printed on a
-- billboard LARGER than the inscription that was supposed to dominate it, so "take the door with
-- more stars" beat "read and dodge the trap" on 95.1% of 3000 seeds, and the 40 000-fork fairness
-- spec, the sign-exclusivity proof and the liar mechanic were all defending a decision the reward
-- curve had already made.
--
-- So an UNREAD door shows that it is a door and nothing else: no trait, no stars, no theme colour
-- (a theme narrows the trait to two of twelve, and gold/void are the strong pair — the colour was
-- most of the leak on its own), no trait in the prompt's own ObjectText. Everything a player knows
-- about a fork, they know because they spent Config.Fork.ReadSeconds reading the pad.
--
-- Called at build time and again the moment the read completes, so there is exactly one place
-- that decides what a fork looks like and no way for the two states to drift apart.
local function dressFork(lane: Lane, level: number)
	local folder = lane.forkFolder[level]
	if folder == nil then
		return
	end
	local floorData = lane.plan.floors[level]
	local read = folder:GetAttribute("Read") == true

	local pad = folder:FindFirstChild("ForkPad_" .. level)
	-- THE FORK'S OWN DATA IS PART OF WHAT THE READ BUYS.
	--
	-- Attributes REPLICATE. `TellKind` and `RuleInverted` used to be written in buildFork, and with
	-- the doors' signs already carved in the open they resolve any fork between them — so a player
	-- running a script read every inscription for nothing while an honest player stood still for
	-- Config.Fork.ReadSeconds. The break-even that prices the read (1.110 s over 5000 seeds) then
	-- describes a game only honest players are playing.
	--
	-- Written HERE instead, in the one function that owns both states of a fork, so the wire and the
	-- billboards can never disagree about what has been paid for. `SetAttribute(name, nil)` removes
	-- the attribute outright, which is what an unread fork must look like on a rejoin as well as on
	-- a fresh build.
	if pad then
		pad:SetAttribute("TellKind", if read then floorData.tellKind else nil)
		pad:SetAttribute("RuleInverted", if read then floorData.ruleInverted else nil)
	end
	local inscription = pad and pad:FindFirstChild("Inscription")
	local inscriptionText = inscription and inscription:FindFirstChild("Text")
	if inscriptionText then
		if read then
			(inscriptionText :: any).Text = string.format("ETASJE %d/%d\n%s %s",
				level, Config.Tower.Floors, floorData.ruleSign, floorData.ruleText)
			;(inscriptionText :: any).TextColor3 = if floorData.ruleInverted
				then Color3.fromRGB(255, 140, 140)
				else Color3.fromRGB(255, 232, 170)
		else
			(inscriptionText :: any).Text = string.format("ETASJE %d/%d\n%s\nHOLD LES — %.1f s",
				level, Config.Tower.Floors, Config.Fork.UnreadInscription, Config.Fork.ReadSeconds)
			;(inscriptionText :: any).TextColor3 = c3(Config.Fork.UnreadAccent)
		end
	end
	local readPrompt = pad and pad:FindFirstChildOfClass("ProximityPrompt")
	if readPrompt then
		readPrompt.Enabled = not read
	end

	for slot = 1, 2 do
		local door = folder:FindFirstChild("Door_" .. level .. "_" .. slot)
		if door then
			local doorData = floorData.doors[slot]
			local trait = traitById[doorData.traitId]
			local theme = Config.Themes[doorData.theme]
			-- Which door bears the sign the inscription names. Same reason as TellKind above: it
			-- replicates, and together with RuleInverted it IS the answer.
			door:SetAttribute("Marked",
				if read then (doorData.signSet[floorData.tellKind] == true) else nil)
			local name = (trait and trait.label) or doorData.traitId
			local stars = string.rep("★", (trait and trait.power) or 1)

			;(door :: any).Color = if read then c3(theme.color) else c3(Config.Fork.UnreadColor)
			local glow = door:FindFirstChild("DoorGlow")
			if glow then
				(glow :: any).Color = if read then c3(theme.accent) else c3(Config.Fork.UnreadAccent)
			end
			local bb = door:FindFirstChild("TraitLabel")
			local text = bb and bb:FindFirstChild("Text")
			if text then
				(text :: any).Text = if read then (name .. "\n" .. stars) else Config.Fork.UnreadDoor
				;(text :: any).TextColor3 = if read then c3(theme.accent) else c3(Config.Fork.UnreadAccent)
			end
			local prompt = door:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.ObjectText = if read then name else Config.Fork.UnreadDoor
			end
		end
	end
end

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
	-- The floor number, and NOTHING else. `TellKind` and `RuleInverted` used to be written here and
	-- they replicate, so between them and the doors' visible signs an exploiter resolved any fork
	-- without paying for it. dressFork writes them, and only once the read is bought.
	pad:SetAttribute("Level", level)

	-- Written by dressFork below, in both directions. The text here is the placeholder it
	-- overwrites on the very next line, and it is deliberately the UNREAD one: a fork that somehow
	-- escaped dressing must fail closed, showing nothing, rather than open.
	billboard(pad, "Inscription", Config.Fork.UnreadInscription, 6,
		c3(Config.Fork.UnreadAccent), Vector2.new(420, 120))

	-- READING COSTS TIME. The hold is what the player feels; the server's own clock is what
	-- actually charges them (see onReadInscription — a client that fires this prompt directly gets
	-- no discount). Parented to the pad, which already exists, so a fresh lane still holds exactly
	-- the ten BaseParts and seven PointLights the headless check counts.
	local readPrompt = make("ProximityPrompt", pad, {
		Name = "Read",
		ActionText = "LES",
		ObjectText = "Innskripsjonen",
		HoldDuration = Config.Fork.ReadSeconds,
		MaxActivationDistance = 16,
		RequiresLineOfSight = false,
		-- ITS OWN KEY, and not E. ProximityPrompt.Exclusivity defaults to OnePerButton, so two
		-- prompts bound to the same key and both in range show one at a time — and the doors sit
		-- eight studs from the middle of a pad that is twenty deep, well inside both radii. On E
		-- the read prompt would simply vanish whenever the player drifted toward a door, which is
		-- the one moment they most need it. Nothing in this repo can render a prompt, so this is
		-- reasoning about a documented engine rule rather than a measurement.
		KeyboardKeyCode = Enum.KeyCode.R,
		GamepadKeyCode = Enum.KeyCode.ButtonY,
	})
	readPrompt.PromptButtonHoldBegan:Connect(function(who)
		if who == plr then
			lane.readHoldAt[level] = clock()
		end
	end)
	readPrompt.Triggered:Connect(function(who)
		onReadInscription(who, plr, level)
	end)

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
		local sx = (if slot == 1 then -1 else 1) * W.DoorSpread
		local doorSize = Vector3.new(W.DoorSize[1], W.DoorSize[2], W.DoorSize[3])
		local door = slab(folder, "Door_" .. level .. "_" .. slot, doorSize,
			top + Vector3.new(sx, doorSize.Y / 2, W.DoorDepth),
			c3(Config.Fork.UnreadColor), Enum.Material.SmoothPlastic)
		door.CanCollide = false -- you walk THROUGH the door you picked
		door:SetAttribute("Level", level)
		door:SetAttribute("Slot", slot)
		-- `Marked` is dressFork's, for the same reason: it replicates. `Signs` stays, because the
		-- sign nubs above the door render it anyway — it is the vocabulary, not the answer.
		door:SetAttribute("Signs", table.concat(doorData.signs, ","))

		make("PointLight", door, {
			Name = "DoorGlow",
			Color = c3(Config.Fork.UnreadAccent),
			Brightness = 2.2,
			Range = 20,
		})
		-- Placeholder text and placeholder colour: dressFork owns both, and both start CLOSED.
		billboard(door, "TraitLabel", Config.Fork.UnreadDoor, 7.5,
			c3(Config.Fork.UnreadAccent), Vector2.new(280, 90))
		signStrip(door, floorData, slot)

		local prompt = make("ProximityPrompt", door, {
			Name = "Choose",
			ActionText = "VELG",
			ObjectText = Config.Fork.UnreadDoor,
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

	-- A read is a floor's own property and it is SAVED, so a rejoin mid-run comes back to a fork
	-- the player has already paid for rather than charging them twice.
	local prof = profiles[plr]
	folder:SetAttribute("Read", prof ~= nil and prof.readFloors[level] == true)
	dressFork(lane, level)
end

--------------------------------------------------------------------- the obby section

local function buildSection(plr: Player, lane: Lane, level: number, theme: string, penalty: boolean)
	if lane.sectionFolder[level] then
		return lane.sectionFolder[level]
	end
	-- WHERE THIS SECTION STARTS, measured from the lane's centre line. Handing it to Section.build
	-- is what keeps the tower inside its own lane: the exit of each section becomes the next
	-- floor's fork origin, so without a bound the tower's X is one long random walk — measured at
	-- 364 studs of drift over ten floors against a 220-stud lane, and 2942 over five hundred, with
	-- towers physically interpenetrating at the top. The generator now refuses any step that would
	-- leave Config.World.CorridorHalfWidth, and Section.check re-derives the bound.
	local originX = lane.forkTop[level].X - lane.origin.X
	local sec = Section.build(Config, lane.plan.runSeed, level, theme, penalty, Rng, originX)
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

		-- THE POINT THIS PLATFORM HANDS BACK. Section.respawn, never `pos`: `pos` is the platform's
		-- CENTRE, and the centre is exactly where a hazard standing on this platform is — its near
		-- face is TileSize/2 - HazardBite = 1.50 studs from the middle, closer than a character is
		-- wide. So the checkpoint a hazard sent you to used to be inside that same hazard, which
		-- fired it again, and again. Section.respawn is the clear band, and Section.check refuses a
		-- section whose respawn point is not in it.
		local rp = Section.respawn(sec, pf.index)
		local checkpoint = base + Vector3.new(rp.dx, rp.dy + Config.World.RespawnLift, rp.dz)
		if pf.index == 1 then
			-- Where answering this floor's fork drops you. Kept on the lane so onDoorChosen and
			-- the mid-climb restore both read the same number instead of re-deriving it.
			lane.entry[level] = checkpoint
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
			lane.checkpoint = checkpoint
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
		part:SetAttribute("Platform", hz.platform)
		-- ONE DEBOUNCE PER HAZARD, not one per lane. Touched fires many times for one contact — a
		-- limb per frame while the parts overlap — and without a debounce every one of them was
		-- another teleport landing on top of the previous one AND another Notice down the wire:
		-- forty per contact, measured.
		--
		-- The first fix kept a single `lane.hazardReadyAt`, which made ONE hit turn every hazard in
		-- the whole tower inert for a full second. At WalkSpeed 16-22 that second covers 16-22
		-- studs and adjacent platforms are 11.0-15.5 apart (TileSize + gap), so a player who ate
		-- one hazard walked through the next one or two for free — and "more hazards" is half of
		-- what a penalty section IS. An upvalue per hazard costs one number per hazard and is the
		-- scope the cooldown always meant.
		local readyAt = 0
		part.Touched:Connect(function(hit)
			local char = hit and hit.Parent
			local who = char and Players:GetPlayerFromCharacter(char)
			if who ~= plr then
				return
			end
			local t = clock()
			if t < readyAt then
				return
			end
			readyAt = t + Config.Limits.HazardCooldown
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
	-- THE CLIENT IS TOLD NOTHING IT HAS NOT PAID FOR. `rule` carries the tell, the liar line and
	-- both doors' labels; before REVIEW-2's fix it went out on every state push, which meant a HUD
	-- panel handed the player the answer the pad was supposed to sell them. It is now gated on the
	-- same readFloors set the world's own dressing is gated on, so there is one condition and not
	-- two that can drift.
	local atFloor = (p.level <= Config.Tower.Floors) and lanes[plr] ~= nil
	local hasRead = atFloor and p.readFloors[p.level] == true
	local floorData = (atFloor and hasRead) and lanes[plr].plan.floors[p.level] or nil
	StateEvent:FireClient(plr, {
		atFork = atFloor,
		read = hasRead,
		readSeconds = Config.Fork.ReadSeconds,
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
	if index == nil then
		-- Trap 3: never refuse silently — and never pretend, either. The player waits on the
		-- waiting pad with an explanation rather than inside somebody else's tower.
		warn(string.format(
			"[ForkTower] ingen ledig bane til %s (%d baner, %d spillere). Hev Config.World.MaxLanes eller senk MaxPlayers.",
			plr.Name, laneCount, #Players:GetPlayers()))
		-- The pad this player is standing on says "waiting for a free tower", so the toast has to
		-- say the same thing. It used to say "try another server" while the sign promised a wait,
		-- and the sign is the one that stays on screen. seatWaiting below is what makes the sign
		-- true.
		notice(plr, "full", "Alle tårnene er opptatt akkurat nå — du får det første som blir ledig.")
		return
	end
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
		entry = {}, -- level -> the checkpoint at the bottom of that floor's section
		readHoldAt = {}, -- level -> when the player STARTED holding LES, by the server's clock
		readPending = {}, -- level -> a server-timed read is already counting down
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
			-- `and not p.skipped[level]`: a skip already spent on this floor is what turned its
			-- trap into a normal section, and Fork.isTrap knows nothing about it. See the note in
			-- onDoorChosen.
			local trapped = Fork.isTrap(floorData, slot) and not p.skipped[level]
			buildSection(plr, lane, level, doorData.theme, trapped)
		end
	end
	if p.level > Config.Tower.Floors then
		buildSummit(plr, lane)
	end

	local restoreLevel = math.min(p.level, Config.Tower.Floors + 1)
	if p.stage == "climb" and lane.entry[p.level] then
		-- Mid-climb: put them back at the bottom of the section they were on, not at the fork —
		-- the fork has already been answered and its prompts are disabled.
		lane.checkpoint = lane.entry[p.level]
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

--============================================================================ reading the fork

-- READING THE INSCRIPTION IS A DELIBERATE, TIMED ACT — and the server, not the client, is what
-- times it.
--
-- ProximityPrompt.HoldDuration lives on the client: it is what the player sees filling up, and it
-- is also the first thing an exploiter deletes (`fireproximityprompt` triggers a prompt with no
-- hold at all). If the hold were the whole mechanic, the one player who cares enough to cheat
-- would be the one who reads for free, which is exactly backwards.
--
-- So the server charges the time itself, and it charges it TWO ways so that neither one can fail
-- open:
--
--   * the honest path — PromptButtonHoldBegan replicates, so the server knows when the hold
--     started and how long it has run. A full hold is already ReadSeconds old when Triggered
--     arrives, and the read completes on the spot;
--   * anything else — a client that fires the prompt directly, or an engine that does not
--     replicate the hold event — is charged the REMAINDER on the server's own clock, with a
--     task.delay that re-checks the player is still standing at that unanswered fork before it
--     hands anything over.
--
-- Either way the wall clock spent is ReadSeconds, which is the number tests/readcost.measure.luau
-- derived (break-even against never reading at all: 1.110 s over 5000 seeds).
onReadInscription = function(plr: Player, owner: Player, level: number)
	-- Same ownership question as a door, checked the same way and for the same reason: the pad
	-- belongs to the tower it stands in, not to whoever reached the prompt.
	if plr ~= owner then
		return
	end
	local p = profiles[plr]
	local lane = lanes[plr]
	if not p or not lane then
		return
	end
	if p.stage ~= "fork" or level ~= p.level then
		notice(plr, "blocked", "Den innskripsjonen er ikke din nå. Du står på etasje " .. p.level .. ".")
		return
	end
	if p.readFloors[level] then
		return -- already paid for; the prompt is disabled, but a client can re-arm one
	end

	local finish = function()
		lane.readPending[level] = nil
		local prof = profiles[plr]
		-- Everything is re-checked here rather than captured: the delay below is a full
		-- ReadSeconds during which the player can answer the fork, rebirth, or leave.
		if prof == nil or lanes[plr] ~= lane then
			return
		end
		if prof.stage ~= "fork" or prof.level ~= level or prof.readFloors[level] then
			return
		end
		prof.readFloors[level] = true
		local folder = lane.forkFolder[level]
		if folder then
			folder:SetAttribute("Read", true)
		end
		dressFork(lane, level)
		local floorData = lane.plan.floors[level]
		notice(plr, "read", floorData.ruleSign .. " " .. floorData.ruleText)
		pushState(plr)
		saveProfile(plr, false)
	end

	local began = lane.readHoldAt[level]
	local remaining = Config.Fork.ReadSeconds - (if began then clock() - began else 0)
	if remaining <= 0 then
		finish()
		return
	end
	if lane.readPending[level] then
		return -- already counting down; a held button must not become a queue of timers
	end
	lane.readPending[level] = true
	notice(plr, "read", string.format("Leser innskripsjonen … (%.1f s)", remaining))
	task.delay(remaining, finish)
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
		-- RECORDED, because the skip is spent and the floor has to remember it. `trapped` here is
		-- a local; buildLane re-derives it from Fork.isTrap on every rejoin, so without this the
		-- player who spent a skip on floor 3 came back to floor 3's PENALTY section — one skip
		-- poorer and standing in the trap they paid to avoid. Worse, Section.build mixes
		-- PENALTY_MIX into its seed, so the section was a different walk entirely and the
		-- checkpoint at the bottom of it moved with it.
		p.skipped[level] = true
	end

	p.picks[level] = doorData.traitId
	p.slots[level] = slot
	p.stage = "climb"

	buildSection(plr, lane, level, doorData.theme, trapped)

	-- THE CHECKPOINT MOVES WHETHER OR NOT THE PLAYER HAS A CHARACTER RIGHT NOW. Everything above
	-- has already spent the floor — stage, picks, slots, and both ProximityPrompts go dead below —
	-- so gating this on `hrp` (as it used to be) left a player who reset during the 0.35s prompt
	-- hold standing on a spent fork pad, 13.5 studs from a platform a traitless jump clears 8.67
	-- of, with both doors dead and Rebirth the only way out. Only the TELEPORT needs a character;
	-- the checkpoint is a number on the lane, and CharacterAdded will read it.
	local target = lane.entry[level]
	if target then
		lane.checkpoint = target
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			(hrp :: BasePart).CFrame = CFrame.new(target)
			;(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
		end
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

-- A RemoteEvent is a button anybody can hold down, and these two are the only ones a client can
-- press at will. Rebirth is the expensive one: each fire is a full teardown, a Fork.plan, a whole
-- world rebuild and a DataStore write. Measured before this, 200 fires in a single frame were all
-- honoured — 200 UpdateAsync calls, the entire server's minute budget, spent by one player in
-- under a second, and every other player silently stopped saving.
type Gate = { readyAt: number, told: boolean }
local gates: { [Player]: { [string]: Gate } } = {}

-- Returns true when the action is refused, and TELLS the player why (trap 3) — but only ONCE per
-- cooldown window. A refusal that answers every fire turns a held-down button into a remote sent
-- back at exactly the rate it came in, which is the amplification this throttle exists to stop;
-- refusing 199 fires with 199 messages would have moved the bug rather than fixed it.
local function onCooldown(plr: Player, what: string, seconds: number, msg: string): boolean
	local mine = gates[plr]
	if mine == nil then
		mine = {}
		gates[plr] = mine
	end
	local g = mine[what]
	if g == nil then
		g = { readyAt = 0, told = false }
		mine[what] = g
	end
	local t = clock()
	if t < g.readyAt then
		if not g.told then
			g.told = true
			notice(plr, "blocked", msg)
		end
		return true
	end
	g.readyAt = t + seconds
	g.told = false
	return false
end

RebirthEvent.OnServerEvent:Connect(function(plr)
	local p = profiles[plr]
	if not p then
		return
	end
	if onCooldown(plr, "rebirth", Config.Limits.RebirthCooldown,
		string.format("Vent %d sekunder før neste rebirth.", Config.Limits.RebirthCooldown)) then
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
	p.readFloors = {}
	p.skipped = {}
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
	if onCooldown(plr, "armskip", Config.Limits.ArmSkipCooldown, "Rolig — ett trykk om gangen.") then
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
	saveProfile(plr, false, true) -- forced: a granted-but-unwritten code is free skips forever
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
	elseif lane == nil then
		-- Said again HERE, not only in buildLane. buildLane runs inside PlayerAdded, and a
		-- FireClient sent before the player's own scripts have connected OnClientEvent is simply
		-- dropped — so the one message that explains why this player has no tower was the one
		-- message they could not receive. By CharacterAdded the HUD is listening.
		notice(plr, "full", "Alle tårnene er opptatt akkurat nå — du får det første som blir ledig.")
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

-- A LANE THAT FREES UP HAS TO GO TO SOMEBODY.
--
-- claimLane was only ever called from buildLane, and buildLane only from PlayerAdded and Rebirth,
-- so when teardownLane freed an index nothing re-ran it: a player the server could not seat waited
-- on the pad forever, under a sign that promised them a tower, and the only escape was to leave
-- and rejoin the server themselves. That was NEW — before the overflow fix they got a (broken,
-- overlapping) tower; after it they got a permanent dead state.
--
-- Called from PlayerRemoving and nowhere else, and that placement is deliberate. buildLane tears
-- its own lane down before re-claiming one, so sweeping from inside teardownLane would let a
-- WAITING player take the lane out from under a player who is merely rebirthing. A lane only
-- genuinely frees when its owner leaves.
local function seatWaiting()
	for _, plr in ipairs(Players:GetPlayers()) do
		if not hasFreeLane() then
			return
		end
		if profiles[plr] ~= nil and lanes[plr] == nil then
			buildLane(plr)
			local lane = lanes[plr]
			if lane ~= nil then
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					(hrp :: BasePart).CFrame = CFrame.new(lane.checkpoint)
					;(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
				end
				applyTraits(plr)
				notice(plr, "safe", "Et tårn ble ledig — du er inne. Les innskripsjonen.")
				pushState(plr)
			end
		end
	end
end

local function onPlayerRemoving(plr: Player)
	saveProfile(plr, true) -- release the lock; releaseLock always writes, throttle or no throttle
	teardownLane(plr)
	profiles[plr] = nil
	lastSaveAt[plr] = nil
	lastBanked[plr] = nil
	gates[plr] = nil
	seatWaiting()
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
			-- Forced: this loop is what flushes every write the throttle above coalesced, and it
			-- is the only thing refreshing the session lock. AutosaveSeconds must stay under
			-- SessionLockSeconds for that to hold.
			saveProfile(plr, false, true)
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
