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
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Fork = require(ReplicatedStorage:WaitForChild("Fork"))
local Section = require(ReplicatedStorage:WaitForChild("Section"))
local BuildCard = require(ReplicatedStorage:WaitForChild("Build"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
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
local LeaderboardEvent = make("RemoteEvent", remotes, { Name = "Leaderboard" }) -- the HUD's top 10 (public)
local BoardEvent = make("RemoteEvent", remotes, { Name = "Board" }) -- the board by your spawn: YOUR view of it
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
	-- THE HIDDEN HALF OF THIS RUN: one server-drawn 32-bit secret per floor, 1..Floors. Fork.plan
	-- decides the trap, the liar line, the tell and both traits from these and from nothing public.
	-- Saved, because a rejoin must rebuild the same tower; re-drawn on rebirth; and NEVER written to
	-- an Instance, an attribute, a leaderstat or a remote. See mintSecret below.
	floorSecrets: { number },
	skips: number,
	armedSkip: boolean, -- runtime only; never saved
	rebirths: number,
	-- Summits reached, one per run (reachExit at the top). The summit's crown grows rarer with it
	-- (Config.Env.CrownTiers; owner decision 2026-09-30). NOT rebirths: Rebirth works from any floor.
	summits: number,
	bestScore: number,
	-- When bestScore was reached (os.time). The board breaks a tie by it: the first to reach a score ranks
	-- above everyone who reached the same score later (Board.encode).
	bestScoreAt: number,
	-- The best score this profile last WROTE to the board. The board is written only when bestScore passes it.
	boardScore: number,
	bestTitle: string,
	redeemed: { [string]: boolean },
	canSave: boolean, -- load-success sentinel: never write over data we failed to read
	-- Runtime only. True once a save that RELEASES the lock has been attempted for this session
	-- (leaving, or BindToClose while the player is still here). From then on nothing on the hidden
	-- half may be revealed: see "trusted" at loadProfile.
	released: boolean,
	-- Runtime only. The token this session wrote into the record when its load took the lock; nil
	-- when it did not take it. A write only lands while the record still carries this token, so
	-- once a later load has taken the record nothing this session wrote late can land over it. See
	-- "OWNERSHIP" at saveProfile.
	session: string?,
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
		floorSecrets = {}, -- filled by loadProfile; an empty list makes Fork.plan refuse, not guess
		skips = Config.Skips.StartSkips,
		armedSkip = false,
		rebirths = 0,
		summits = 0,
		bestScore = 0,
		bestScoreAt = 0,
		boardScore = 0,
		bestTitle = "",
		redeemed = {},
		canSave = false,
		released = false,
		session = nil,
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

--============================================================================ the plan secret

-- EVERY TRAP IN THE GAME IS DRAWN HERE, BY THE SERVER, AND NOWHERE ELSE.
--
-- Measured 2026-09-17 (REVIEW-4.md): Fork.luau is in ReplicatedStorage and used to derive the whole
-- plan from Config.WorldSeed and the run seed, and the run seed is leaderstats.Rebirths + 1. A
-- client computed 30 of 30 honestly-read traps without reading one. Gating TellKind, RuleInverted
-- and Marked (REVIEW-3) had closed the attributes and left the generator wide open.
--
-- So the hidden half of each floor is a secret: one uniform 32-bit integer per floor per run,
-- drawn from server randomness, saved in the profile and never replicated. Fork.plan refuses to
-- plan without them. What a player sees before reading — the carvings — stays public and is not
-- derived from these, so there is nothing on screen to brute-force a secret against; and each
-- floor's secret is drawn on its own, so a read that pins one floor buys that floor and no other.
--
-- Two generators, XORed, so neither is the whole secret on its own. `secretSource` is created once
-- when the server starts, so pressing Rebirth at a known moment seeds nothing; the fresh
-- Random.new() per floor means that even recovering secretSource's internal state would not
-- predict the next floor. Neither is Fork's mix32 or Rng's LCG, which are public.
local SECRET_MAX = 4294967295 -- 2^32 - 1
local secretSource = Random.new()

local function mintSecret(): number
	return bit32.bxor(secretSource:NextInteger(0, SECRET_MAX), Random.new():NextInteger(0, SECRET_MAX))
end

local function mintSecrets(): { number }
	local out = {}
	for level = 1, Config.Tower.Floors do
		out[level] = mintSecret()
	end
	return out
end

-- THE SECRETS A LOADED PROFILE PLAYS UNDER — and the migration of a profile saved before they
-- existed, which is every profile written up to 2026-09-17.
--
-- A floor keeps its saved secret when there is a valid one. Otherwise the rule is about what the
-- player has ALREADY SEEN of that floor's hidden half:
--   * answered it, read it, or climbed past it -> Fork.legacySecrets, which reproduces the
--     2026-09-17 plan field for field (Fork.spec asserts it). The section they climbed, the
--     inscription they paid for and the traits they took stay exactly as they were;
--   * anything else -> a fresh secret. Nothing visible is derived from a secret, so re-drawing a
--     floor the player has not read changes nothing on their screen: same carvings, same fork.
-- So a run already in progress is NOT reshuffled, at any level, and the floors still ahead of it are
-- no longer computable. The legacy floors ARE computable by a client, and that is harmless for
-- exactly the reason they were chosen: the player has already seen them.
--
-- The result is saved on the next write alongside readFloors and slots, so a migration happens
-- once. A player whose profile could not be saved (read-only session) is migrated again on the
-- next load; the floors they had seen come out the same, and the unseen ones are re-drawn unseen.
--
-- `trustUnseen` is the second rule, and it exists because the first fix lost to it (REVIEW-4.md §9).
-- A saved secret for a floor the player has NOT seen is only used by a session that will end up
-- holding everything it reveals. Otherwise the unseen floors are drawn fresh for this session, and
-- the saved secrets of those floors are never planned from. Measured before this: a READ-ONLY
-- session planned the saved secrets, let a script walk through every door and saved nothing, and
-- the real session afterwards was the same run with 240 of 240 traps known and no read paid.
-- A floor already SEEN keeps its saved secret whatever the session: the player knows it, so there
-- is nothing left to learn from it, and changing it would reshuffle what they saw.
local function resolveSecrets(p: Profile, saved: any, trustUnseen: boolean): { number }
	local legacy = Fork.legacySecrets(Config, p.runSeed)
	local out = {}
	for level = 1, Config.Tower.Floors do
		local v = if type(saved) == "table" then (saved[level] or saved[tostring(level)]) else nil
		local seen = level < p.level or p.slots[level] ~= nil or p.readFloors[level] == true
		if seen then
			out[level] = if Fork.isSecret(v) then v else legacy[level]
		elseif trustUnseen and Fork.isSecret(v) then
			out[level] = v
		else
			out[level] = mintSecret()
		end
	end
	return out
end

-- Load + soft session lock (anti-dupe). We ALWAYS read the real data, even when another live
-- session holds the lock — we simply play READ-ONLY (canSave = false) rather than clobbering it.
-- The lock is refreshed by autosave and expires after SessionLockSeconds, so a crashed session
-- does not lock a player out and a fast rejoin never sees floor 1 again.
--
-- WHICH SAVED SECRETS A SESSION MAY PLAN FROM. A session TRUSTS the saved secrets of floors its
-- player has not seen only when both hold:
--   * it can save (canSave): it holds the lock and its load landed, so what it reveals is written;
--   * the record was RELEASED when it loaded (lockUntil == 0): the session before it wrote its
--     final state on the way out, and that write carries every reveal it made, because every
--     reveal (a door's slot, a read's readFloors) goes into the profile BEFORE the world shows it,
--     and nothing is revealed after a releasing save is attempted (see `released`).
-- Anything else means the record may be missing a reveal the player saw: another server still
-- holds the lock (read-only), or the last session crashed or lost its writes (lockUntil > 0 from
-- its own load or autosave). Then every unseen floor is drawn fresh (resolveSecrets), so a door
-- walked where nothing lands teaches nothing about the run that is saved. The saved secrets of an
-- unseen floor are only ever used where their reveal will be kept.
--
-- "The session before it wrote its final state" also needs that no OLDER write can land after this
-- load. A shutdown makes two releasing saves per player (BindToClose, then PlayerRemoving), and
-- queued DataStore writes need not land in order: measured in the third pass (REVIEW-4.md §10), a
-- late BindToClose write landed after the next session had loaded, trusted and walked every door,
-- and re-released the record with a state in which no floor was walked — 120 of 120 traps known.
-- So the load that takes the lock writes a fresh `session` token, and saveProfile writes only while
-- the record still carries its own (see OWNERSHIP there).
local function loadProfile(plr: Player): Profile
	local p = defaultProfile()
	local savedSecrets = nil
	if not store then
		p.floorSecrets = resolveSecrets(p, nil, false)
		return p
	end
	local token = HttpService:GenerateGUID(false)
	local acquired = false
	local recordReleased = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedUntil = tonumber(old.lockUntil) or 0
			local lockedByOther = lockedUntil > now and old.jobId ~= game.JobId
			-- Read before this transform writes its own lock, and re-read on every invocation.
			recordReleased = lockedUntil <= 0
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
				p.summits = math.max(0, math.floor(tonumber(d.summits) or 0))
				p.bestScore = math.floor(tonumber(d.bestScore) or 0)
				p.bestScoreAt = math.floor(tonumber(d.bestScoreAt) or 0)
				p.boardScore = math.floor(tonumber(d.boardScore) or 0)
				p.bestTitle = tostring(d.bestTitle or "")
				p.redeemed = (type(d.redeemed) == "table") and d.redeemed or {}
				-- Only noted here. The transform may run more than once and must not draw anything;
				-- resolveSecrets runs once, below, after every field it reads is final.
				savedSecrets = d.floorSecrets
			end
			if lockedByOther then
				acquired = false
				return old -- respect the other live session; do not touch the lock
			end
			acquired = true
			old.jobId = game.JobId
			old.session = token
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		warn("[ForkTower] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		p.session = if acquired then token else nil
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
	-- After the clamp, because the migration rule reads p.level.
	p.floorSecrets = resolveSecrets(p, savedSecrets, p.canSave and recordReleased)
	-- Saved before 2026-10-01: a best score with no time. When it was reached is unknown, so it is stamped
	-- with this session; on the board it ranks behind everyone who reached the same score before today.
	if p.bestScore > 0 and p.bestScoreAt <= 0 then
		p.bestScoreAt = os.time()
	end
	return p
end

-- When each player's profile last actually reached the DataStore.
local lastSaveAt: { [Player]: number } = {}

-- THE BOARD (OrderedDataStore Config.Save.Leaderboard). Written only when the best score has passed the last one
-- this profile wrote, and never lower than what is stored: Board.keepHigher cancels the UpdateAsync otherwise, so
-- a same score reached later never replaces the first one (Board.encode: score * 2e9 + (2e9 - reachedAt)). It
-- was a raw SetAsync before pass 2 (2026-10-01): no tie-break, and a session holding an older, lower best could
-- overwrite a higher one. Called only after the profile write landed, so only the session that owns the record
-- writes the board.
local function writeBoard(p: Profile, userId: number)
	if not orderedLB or p.bestScore <= p.boardScore then
		return
	end
	local score = p.bestScore
	local value = Board.encode(score, p.bestScoreAt, Config.Board)
	local ok = pcall(function()
		orderedLB:UpdateAsync(key(userId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then
		p.boardScore = score -- also when keepHigher cancelled: what is stored is at least as high
	end
end

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
	if p and releaseLock then
		-- Set BEFORE the write, so a door pulled while it is in flight is refused too. A released
		-- record is one the next load trusts; a reveal after it would be lost with the server
		-- (BindToClose runs while players are still here) and known to the player next session.
		p.released = true
	end
	if not p or not p.canSave or not store then
		return
	end
	local t = clock()
	if not (force or releaseLock) and t - (lastSaveAt[plr] or -math.huge) < Config.Limits.SaveMinInterval then
		return -- the autosave loop below forces a write every AutosaveSeconds, so nothing is lost
	end
	lastSaveAt[plr] = t
	-- OWNERSHIP. The write lands only if the record still carries the token this session's load wrote.
	-- If another load has taken the record since, this write is cancelled (a nil return), whatever it
	-- is: an autosave, a leave, or a BindToClose write that sat in the queue. Without this, a late
	-- releasing write re-released a record a newer session had loaded, trusted and revealed from, and
	-- it re-released it WITHOUT those reveals. It also stops a session whose lock expired from
	-- writing over the session that took it. `lost` is set on every invocation: the transform may run
	-- more than once.
	local lost = false
	local wrote = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			if old.session ~= p.session then
				lost = true
				return nil
			end
			lost = false
			old.data = {
				runSeed = p.runSeed, level = p.level, stage = p.stage,
				picks = p.picks, slots = p.slots, skips = p.skips,
				readFloors = levelList(p.readFloors), skipped = levelList(p.skipped),
				-- In the SAME write as readFloors and slots, so a saved read is never saved without
				-- the secret it was read under.
				floorSecrets = p.floorSecrets,
				rebirths = p.rebirths, bestScore = p.bestScore, bestTitle = p.bestTitle,
				bestScoreAt = p.bestScoreAt, boardScore = p.boardScore,
				-- no `passes`: no gamepasses in v1 (owner decision 2026-09-30; an old record's empty field is dropped)
				redeemed = p.redeemed, summits = p.summits,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if lost then
		-- Another session owns this profile now. Nothing this one does is kept from here on, so it
		-- stops writing (and Redeem, which refuses without canSave, stops granting).
		p.canSave = false
		warn("[ForkTower] " .. plr.Name
			.. ": en nyere økt har tatt over profilen; progresjon denne økta lagres ikke lenger.")
		return
	end
	-- Only when it has actually MOVED (writeBoard). bestScore changes at most once per summit, so re-publishing
	-- it on every autosave would be a second write per save buying nothing: the same amplification as above,
	-- one budget over.
	if wrote then
		writeBoard(p, plr.UserId)
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
local waitingSpawn: SpawnLocation
do
	local pad = slab(waiting, "WaitingPad", Vector3.new(30, 2, 30),
		Vector3.new(0, -1, -160), Color3.fromRGB(44, 42, 62), Enum.Material.Slate)
	billboard(pad, "WaitingLabel", "🔀 FORK TOWER\nVenter på et ledig tårn …", 8,
		Color3.fromRGB(235, 225, 255), Vector2.new(400, 120))
	waitingSpawn = make("SpawnLocation", waiting, {
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
local onBoardPrompt -- ... and so does the board's (the board section is further down)
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
	-- kept for the exit rule (lane.tryExit): the geometry the least climbing time is measured on
	lane.sectionGeo[level] = sec
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
			lane.exitPart[level] = part
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
				lane.tryExit(level, char:FindFirstChild("HumanoidRootPart"))
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
		local t = ls:FindFirstChild("Topper")
		if t then (t :: IntValue).Value = p.summits end
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
		p.bestScoreAt = os.time() -- the board's tie-break: who reached this score first
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
		return -- plr.RespawnLocation is still the WaitingSpawn onPlayerAdded set first
	end
	local origin = laneOrigin(index)
	local folder = make("Folder", towers, { Name = "Lane_" .. index })
	folder:SetAttribute("Owner", plr.UserId)

	local lane: any = {
		index = index,
		folder = folder,
		origin = origin,
		plan = Fork.plan(Config, p.runSeed, Rng, p.floorSecrets),
		forkTop = {},
		forkFolder = {},
		sectionFolder = {},
		entry = {}, -- level -> the checkpoint at the bottom of that floor's section
		readHoldAt = {}, -- level -> when the player STARTED holding LES, by the server's clock
		readPending = {}, -- level -> a server-timed read is already counting down
		sectionGeo = {}, -- level -> Section.build's section (the exit rule measures on it)
		exitPart = {}, -- level -> the section's exit platform
		climbFrom = {}, -- level -> when the server put the player at the bottom of that section (its clock)
		exitTold = {}, -- level -> the player was told once why an early exit did not count
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
			-- one summit per run: reachExit runs once per floor, and this is the top floor's
			local function crownAt(n: number)
				local best = nil
				for _, t in ipairs(Config.Env.CrownTiers or {}) do
					if n >= t.summits then best = t end
				end
				return best
			end
			local was = crownAt(prof.summits)
			prof.summits += 1
			local now = crownAt(prof.summits)
			if now ~= nil and now ~= was then
				notice(plr, "summit", "Du nådde toppen! 👑 Ny krone: " .. now.name .. " (" .. prof.summits .. " topper)")
			else
				notice(plr, "summit", "Du nådde toppen! Build Reveal er klar.")
			end
		else
			buildFork(plr, lane, prof.level)
			lane.checkpoint = lane.forkTop[prof.level] + Vector3.new(0, Config.World.RespawnLift, 0)
			notice(plr, "floor", "Etasje " .. level .. " klarert. Les innskripsjonen.")
		end
		pushState(plr)
		saveProfile(plr, false)
	end

	-- THE EXIT COUNTS ONLY FOR A BODY THAT COULD HAVE CLIMBED THERE (queued job I, found 2026-09-24 by
	-- the plan-secret attacker; REVIEW-4.md §9.8 item 5). A client owns its character's physics, so a
	-- script could choose a door and teleport onto the exit at once, or fire the exit's Touched from
	-- anywhere: a trap cost it nothing whatever it predicted, and the read's price bound only honest
	-- players. So both of these must hold, on the SERVER's clock and the server's view of the body:
	--   * the root part stands on the exit platform (Config.Exit), not merely somewhere a Touched came from;
	--   * Section.minClimbSeconds has passed since the server put the player at the bottom of the section
	--     (the door, or a mid-climb rejoin): the straight line on the ground from the entry to the exit's
	--     reach at the player's own WalkSpeed * Config.Exit.SpeedSlack. Nobody moves sideways faster than
	--     their WalkSpeed; tests/Pacing.spec.luau measures that no honest climber is ever refused.
	-- An early touch is refused and said once per section (trap 3). onCharacter's poll clears the floor
	-- for a body that is standing on the exit once the time is up, so an honest player whose landing
	-- came from a limb or a hair early is never left standing on a spent exit.
	-- robloxemu/check_forktower_exit.luau is the measurement.
	lane.tryExit = function(level: number, root: Instance?): boolean
		local prof = profiles[plr]
		if not prof or prof.level ~= level or prof.stage ~= "climb" then
			return false
		end
		local exit, geo = lane.exitPart[level], lane.sectionGeo[level]
		if exit == nil or geo == nil or root == nil or not root:IsA("BasePart") then
			return false
		end
		local pos = (root :: BasePart).Position
		local ex = Config.Exit
		local reach = exit.Size.X / 2 + Config.World.CharacterHalfWidth + ex.FootprintMargin
		local reachZ = exit.Size.Z / 2 + Config.World.CharacterHalfWidth + ex.FootprintMargin
		local top = exit.Position.Y + exit.Size.Y / 2
		if math.abs(pos.X - exit.Position.X) > reach or math.abs(pos.Z - exit.Position.Z) > reachZ
			or pos.Y < top - ex.Below or pos.Y > top + ex.Above then
			return false -- the body is not on the exit: whatever fired the Touched, it was not a climb
		end
		if lane.climbFrom[level] == nil then
			lane.climbFrom[level] = clock() -- no recorded start (should not happen): count from now, fail closed
		end
		local _, speed = traitTotals(prof)
		local need = Section.minClimbSeconds(Config, geo, speed)
		if clock() - lane.climbFrom[level] < need then
			if not lane.exitTold[level] then
				lane.exitTold[level] = true
				notice(plr, "blocked", "Utgangen teller først når du har klatret opp seksjonen.")
			end
			return false
		end
		lane.reachExit(level)
		return true
	end

	local padSize = Vector3.new(Config.World.LobbyPadSize[1], Config.World.LobbyPadSize[2], Config.World.LobbyPadSize[3])
	local lobby = slab(folder, "LobbyPad", padSize, origin - Vector3.new(0, padSize.Y / 2, 6),
		Color3.fromRGB(48, 46, 66), Enum.Material.Slate)
	billboard(lobby, "Welcome",
		"🔀 FORK TOWER\nTo dører. Én er en felle.\nLES INNSKRIPSJONEN.", 8,
		Color3.fromRGB(235, 225, 255), Vector2.new(400, 140))
	-- THE ENGINE'S SPAWN IS THE PLAYER'S OWN TOWER (docs/complete-game-standard.md §1, robloxemu/SPAWN-ORDER.md):
	-- plr.RespawnLocation points at this real, enabled SpawnLocation on their own lobby, so the frame the engine
	-- places a character it already stands in its own tower, not on the waiting pad 160 studs away. The game
	-- then moves it to its checkpoint (onCharacter, which waits for the engine first: the checkpoint climbs with
	-- the player, so it is not a SpawnLocation). It was Enabled = false, a marker, until pass 2 (2026-10-01).
	-- Every player's RespawnLocation is set before their character can load (onPlayerAdded), so an enabled
	-- LaneSpawn is never the engine's pick for anybody else.
	local laneSpawn = make("SpawnLocation", folder, {
		Name = "LaneSpawn",
		Anchored = true,
		CanCollide = false,
		Transparency = 1,
		Size = Vector3.new(6, 1, 6),
		Position = origin + Vector3.new(0, 0.5, -4),
		Neutral = true,
		Enabled = true,
	})
	plr.RespawnLocation = laneSpawn

	-- THE TOPLIST BOARD (docs/complete-game-standard.md §3), at the back of this tower's lobby, its front facing
	-- the spawn on floor 1's fork pad, out of the climb (which runs +Z from that pad). Every tower has its own,
	-- because every player spawns in their own tower. The server owns every number on it and sends each player
	-- THEIR view (BoardEvent); Board.client draws it on the player's own board, locally, so two players never
	-- fight over one sign. The prompt switches Public / Friends for whoever presses it.
	do
		local centre = origin + Vector3.new(-6, 5.5, -15)
		local faceTo = Vector3.new(origin.X, centre.Y, origin.Z + 14)
		local board = make("Part", folder, {
			Name = "TopBoard",
			Anchored = true,
			CanCollide = true,
			Size = Vector3.new(14, 11, 1),
			CFrame = CFrame.lookAt(centre, faceTo), -- the front face (where the board is drawn) looks at the spawn
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(24, 22, 40),
		})
		-- a gold rim behind it: what is interactive should look interactive (docs/new-game-checklist.md §2)
		make("Part", folder, {
			Name = "TopBoardTrim",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Size = Vector3.new(14.8, 11.8, 0.6),
			CFrame = board.CFrame * CFrame.new(0, 0, 0.35), -- local +Z = behind the board
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 205, 90),
		})
		local at = make("Attachment", board, { Name = "PromptAt", Position = Vector3.new(0, -3.5, -0.6) })
		local prompt = make("ProximityPrompt", at, {
			Name = "BoardPrompt",
			ActionText = Config.Board.Text.Prompt,
			ObjectText = Config.Board.Text.Object,
			HoldDuration = 0,
			MaxActivationDistance = Config.Board.PromptDistance,
			RequiresLineOfSight = false,
			KeyboardKeyCode = Enum.KeyCode.E,
		})
		prompt.Triggered:Connect(function(who: Player)
			onBoardPrompt(who)
		end)
	end

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
		-- the section's clock starts again: the player is put back at its bottom (tryExit)
		lane.climbFrom[p.level] = clock()
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
	if p.released then
		notice(plr, "blocked", "Serveren stenger — innskripsjonen kan ikke leses nå. Bli med igjen om litt.")
		return
	end

	local finish = function()
		lane.readPending[level] = nil
		local prof = profiles[plr]
		-- Everything is re-checked here rather than captured: the delay below is a full
		-- ReadSeconds during which the player can answer the fork, rebirth, or leave — or the
		-- server can start shutting down and release the lock (see `released`).
		if prof == nil or lanes[plr] ~= lane or prof.released then
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
	-- SAY IT ONLY IF THERE IS SOMETHING TO SAY.
	--
	-- Measured in Studio 2026-09-10 (STUDIO.md): PromptButtonHoldBegan takes ~32 ms to reach the
	-- server, so for a full honest 1.1 s hold the server's own elapsed is 1.0997 s and `remaining`
	-- lands at about 0.0004 s — POSITIVE. The `remaining <= 0` fast path above is therefore never
	-- taken by an honest player, and every honest read flashed "Leser innskripsjonen … (0.0 s)"
	-- for the two frames before the inscription's own toast replaced it. Three separate reads,
	-- timed end to end, showed it every time.
	--
	-- What is NOT changed here is the charge: task.delay still runs for the whole remainder on the
	-- server's clock, so an exploiter firing the prompt with no hold at all still waits the full
	-- Config.Fork.ReadSeconds. Shortening THAT is the one repair that would make this fail open.
	-- 0.05 is not a magic number: it is what "%.1f" below rounds to zero.
	if remaining >= 0.05 then
		notice(plr, "read", string.format("Leser innskripsjonen … (%.1f s)", remaining))
	end
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
	-- The lock is already released (the server is shutting down with the player still in it). A
	-- section built now would show the trap, and the write that should carry this door may never
	-- land, while the released record is one the next load trusts. So no door opens.
	if p.released then
		notice(plr, "blocked", "Serveren stenger — valget kan ikke lagres nå. Bli med igjen om litt.")
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
	-- the section's clock starts now: the exit counts only once the climb could have been made (tryExit)
	lane.climbFrom[level] = clock()
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
	p.floorSecrets = mintSecrets() -- a new run is a new draw; the old run's secrets are never reused
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

--============================================================================ the board: public + friends

-- docs/complete-game-standard.md §3 (owner, 2026-09-16), built on the +1 Jump template (Board.luau, verbatim).
-- The metric is the best Build Reveal score a summit banked (revealFor): the server computes it from the run's
-- picks and no client sends a number. Stored encoded (writeBoard, above): ties go to whoever reached the score
-- first. The public top 10 is read at most once per PublicCacheSeconds. Friends are read only when a player
-- asks on the board, capped, cached and throttled (Board.newLimiter and Roblox's own budget). Names are looked up
-- here, remembered in memory and never saved; the HUD used to look every name up itself on every refresh.
local BC = Config.Board

-- Names: from the players in this server, a friends list, or GetNameFromUserIdAsync; remembered, never saved.
local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local ok, res = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(res) == "string" then
		nameCache[userId] = res
		return res
	end
	return "#" .. tostring(userId) -- not remembered: the next view tries again
end
local function withNames(rows: { any }): { any }
	local out = {}
	for i, r in rows do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

-- A player's own value, from memory (fresher than the store, which is written at the autosave).
local function liveValue(p: Profile?): number
	if not p or p.bestScore <= 0 then
		return 0
	end
	return Board.encode(p.bestScore, p.bestScoreAt, BC)
end

local boardMode: { [Player]: string } = {} -- "public" | "friends", per player
local publicView: any = { rows = {}, note = BC.Text.Loading }

local function sendBoard(plr: Player, mode: string, view: any)
	-- `viewer`: FireClient reaches only this player in Roblox; the field lets a client ignore anything else.
	BoardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
end

local function refreshPublic()
	if not orderedLB then
		publicView = Board.publicView({}, BC)
		return
	end
	local ok, page = pcall(function()
		return orderedLB:GetSortedAsync(false, BC.PublicRows)
	end)
	if not ok or not page then
		return -- keep the last list
	end
	local okPage, items = pcall(function()
		return page:GetCurrentPage()
	end)
	if not okPage or type(items) ~= "table" then
		return
	end
	local entries = {}
	for _, e in ipairs(items) do
		local uid = Board.userIdOf(tostring(e.key))
		if uid and type(e.value) == "number" then
			table.insert(entries, { userId = uid, value = e.value })
		end
	end
	local view = Board.publicView(entries, BC)
	publicView = { rows = withNames(view.rows), note = view.note }
end

-- The HUD's top list (decoded scores and the server's names, never a stored value) and, for a player looking
-- at Public, the board.
local function sendPublic(plr: Player)
	local hudRows = {}
	for i, r in publicView.rows do
		hudRows[i] = { userId = r.userId, score = r.tier, name = r.name }
	end
	LeaderboardEvent:FireClient(plr, hudRows)
	if (boardMode[plr] or "public") == "public" then
		sendBoard(plr, "public", publicView)
	end
end

-- Friends: only on request, capped at FriendsCap, cached per player. A failed fetch is retried after a minute,
-- not on every press.
local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local fetching: { [Player]: boolean } = {}

local function friendIdsOf(plr: Player): ({ number }, boolean)
	local now = clock()
	local hit = Board.cacheGet(friendsCache, plr.UserId, now)
	if hit then
		return hit, false
	end
	if Board.cacheHas(friendsFailed, plr.UserId, now) then
		return {}, true
	end
	local ok, pages = pcall(function()
		return (Players :: any):GetFriendsAsync(plr.UserId)
	end)
	local ids = {}
	local broken = not ok or pages == nil
	while not broken and #ids < BC.FriendsCap do
		local okPage, items = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not okPage or type(items) ~= "table" then
			broken = #ids == 0
			break
		end
		for _, item in ipairs(items) do
			local id = tonumber(item.Id)
			if id and #ids < BC.FriendsCap then
				table.insert(ids, id)
				if type(item.Username) == "string" then
					nameCache[id] = item.Username
				end
			end
		end
		if pages.IsFinished or #ids >= BC.FriendsCap then
			break
		end
		if not pcall(function()
			pages:AdvanceToNextPageAsync()
		end) then
			break
		end
	end
	if broken then
		Board.cachePut(friendsFailed, plr.UserId, true, now)
		return {}, true
	end
	Board.cachePut(friendsCache, plr.UserId, ids, now)
	return ids, false
end

-- Always leave BudgetReserve GetAsync in Roblox's budget (if it cannot be read, only the limiter applies).
local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

-- A friend's stored value (0 = never summited), or nil when the read is throttled (try again later). A read that
-- fails counts as 0 without being cached, so one bad key does not stop the list.
local function friendValue(userId: number): number?
	local here = Players:GetPlayerByUserId(userId)
	if here and profiles[here] then
		return liveValue(profiles[here])
	end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then
		return Board.cacheGet(scoreCache, userId, now)
	end
	if not orderedLB then
		return 0
	end
	if not budgetLeft() or not Board.take(readLimiter, now) then
		return nil
	end
	local ok, v = pcall(function()
		return orderedLB:GetAsync(key(userId))
	end)
	if not ok then
		return 0
	end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr: Player)
	if fetching[plr] then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading }) -- the one running sends soon
		return
	end
	fetching[plr] = true
	task.spawn(function()
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values: { [number]: number } = {}
		local status = { friendCount = #ids, checked = 0, failed = failedList }
		local function push()
			values[plr.UserId] = liveValue(profiles[plr])
			local view = Board.friendsView(plr.UserId, values, status, BC)
			sendBoard(plr, "friends", { rows = withNames(view.rows), note = view.note })
		end
		local i, lastPush = 1, -math.huge
		while i <= #ids and plr.Parent == Players and boardMode[plr] == "friends" do
			local v = friendValue(ids[i])
			if v == nil then
				status.checked = i - 1
				if clock() - lastPush >= 0.5 then
					push()
					lastPush = clock()
				end
				task.wait(1) -- throttled: wait for the limiter
			else
				values[ids[i]] = v
				i += 1
			end
		end
		status.checked = i - 1
		if plr.Parent == Players and boardMode[plr] == "friends" then
			push()
		end
		fetching[plr] = nil
	end)
end

onBoardPrompt = function(plr: Player)
	if profiles[plr] == nil then
		return -- still loading: the board says so ("Laster ...") until the first view arrives
	end
	boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
	if boardMode[plr] == "friends" then
		showFriends(plr)
	else
		sendBoard(plr, "public", publicView)
	end
end

--============================================================================ players

local function onCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)

	-- WAIT FOR THE ENGINE TO FINISH SPAWNING BEFORE PLACING ANYBODY. THIS IS NOT DEFENSIVE, IT IS
	-- THE WHOLE REASON THE GAME WAS REACHABLE OR NOT.
	--
	-- Measured in Roblox Studio, 2026-09-10 (STUDIO.md), sampling every Heartbeat from inside a
	-- server-side CharacterAdded handler:
	--
	--     [0.0000] f01 parent=nil        hrp=0.00,0.00,0.00
	--     [0.0051] f02 parent=Workspace  hrp=0.00,3.51,-160.00     <- Waiting.WaitingSpawn
	--
	-- CharacterAdded fires while the character model is STILL UNPARENTED and its root part is at
	-- the origin. One frame later the engine parents it AND drops it on the only enabled
	-- SpawnLocation. A CFrame written here before that happens is thrown away without a warning:
	-- every player spawned on the waiting pad, 174 studs from their own tower across empty air,
	-- while the HUD told them to read floor 1's inscription. Eight green suites, an emulator and
	-- two adversarial reviews all missed it, because nothing outside the engine models this order
	-- (the emulator's own simulateSpawn parents the model first and never applies a spawn point).
	--
	-- So yield until the character is genuinely in the world, then place it. Bounded, so a
	-- character that never gets parented cannot leave this handler running for the session; and
	-- `lanes[plr]` is read AFTER the wait, because a rebirth can rebuild the lane while we yield.
	--
	-- `task.wait(1 / 60)` and not a bare `task.wait()`: one frame, spelled as a DURATION. A bare
	-- wait is a zero-length yield on a virtual clock, so a frame-poll written that way spins its
	-- whole bound inside a single scheduler step and the headless check cannot express this
	-- defect at all. 300 frames is a five-second bound, which is there so a character that never
	-- arrives cannot leave this handler parked for the session.
	local frames = 0
	while char.Parent == nil and frames < 300 do
		task.wait(1 / 60)
		frames += 1
	end

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
	sendPublic(plr) -- the board and the HUD's top list, now that the client is listening (see the note above)

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
			-- and a body standing on its section's exit clears the floor once the climb could have been
			-- made, whether or not a Touched arrived in time (tryExit)
			local prof = profiles[plr]
			if l and hrp and l.tryExit and prof and prof.stage == "climb" then
				l.tryExit(prof.level, hrp)
			end
			task.wait(Config.Exit.PollSeconds)
		end
	end)
end

local function onPlayerAdded(plr: Player)
	-- FIRST, before loadProfile yields: the engine may load the character while the profile loads, and with every
	-- tower's LaneSpawn enabled a player with no RespawnLocation could be dropped in somebody else's tower for a
	-- frame. buildLane points it at the player's own LaneSpawn once there is a tower.
	plr.RespawnLocation = waitingSpawn
	local p = loadProfile(plr)
	profiles[plr] = p

	local ls = make("Folder", plr, { Name = "leaderstats" })
	for _, n in ipairs({ "Floor", "Best", "Rebirths", "Topper" }) do
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
	boardMode[plr] = nil
	fetching[plr] = nil
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
		refreshPublic() -- at most one GetSortedAsync per PublicCacheSeconds
		for _, plr in ipairs(Players:GetPlayers()) do
			sendPublic(plr)
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

print("[ForkTower] Fork Tower lastet. WorldSeed=" .. Config.WorldSeed
	.. " Floors=" .. Config.Tower.Floors)
