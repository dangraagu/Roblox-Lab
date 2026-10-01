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
local ServerStorage = game:GetService("ServerStorage")
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
local Highscore = require(Shared:WaitForChild("Highscore"))

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
-- The Field Guide board's own ordered store (queued job A). Not the Best-Day store: that one ranks a
-- Day streak and is left exactly as it was.
local guideOk, guideStore = pcall(function()
	return DataStoreService:GetOrderedDataStore(Config.Save.GuideStore)
end)
if not guideOk then
	guideStore = nil
end

type Profile = {
	bestDay: number,
	caught: Codex.Set,
	hintTokens: number,
	redeemed: Codes.RedeemedSet,
	tint: string, -- the SELECTED tint
	ownedTints: { [string]: boolean }, -- everything the player may select (string keys)
	canSave: boolean, -- true only if we hold the session lock (RE-EVALUATED, see retryClaim)
	lockToken: string, -- STABLE per-session ownership token (not a timestamp)
	closing: boolean, -- R7: set before the releasing save; blocks any further lock RENEWAL
	publishedBest: number, -- R2/R9: highest day already on the leaderboard (or loaded from the store)
	lastPublishAt: number, -- R9: os.clock() of the last OrderedDataStore write
	readOnlyNotified: boolean, -- R5: the "this session can't save" notice is one-shot
	redeemBusy: boolean, -- R4: an UpdateAsync redeem is in flight for this player
	remoteAt: { [string]: number }, -- R4: per-remote last-accepted os.clock(), for the cooldown
	pendingTint: string?, -- a tint picked inside SetTint's cooldown: applied when it ends (the last pick wins)
	run: Run?, -- the Day streak and its live pass, saved (owner decision 2026-09-30, see sanitizeRun)
	loadedRunId: string?, -- the run id this session loaded (or adopted): retryClaim's staleness test
	-- the Field Guide board (queued job A): types caught as the board counts them, when that count was
	-- first reached (unix), the count last written to the board store, and os.clock() of that write
	guideCount: number,
	guideAt: number,
	guidePublished: number,
	lastGuideAt: number,
}

-- The saved run (owner decision 2026-09-30: "never punishing"). Saved WITH the live pass, so leaving
-- is never a re-roll; a wrong call replaces it (new id, Day 1, no pass) and is flushed at once.
type Run = {
	id: string, -- a new id for every run: a run ended by a wrong call can never be resumed
	day: number,
	pass: { clean: boolean, anomalyId: string? }?, -- nil between a wrong call and the next roll
}

type PassState = {
	day: number,
	clean: boolean,
	anomalyId: string?,
	serial: number,
	awaiting: boolean,
	salt: number, -- per-session anomaly-sequence salt (server memory only, never replicated)
	startedAt: number, -- os.clock() when this pass went live (anti-autoclicker plausibility)
	runId: string, -- the run this Day belongs to (Run.id)
	ownRun: boolean, -- this session started the run (fresh, or after its own wrong call): see retryClaim
	hinted: boolean, -- a hint was bought for THIS pass: pressing H again re-shows it, free
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
local beginPass: (Player, any?) -> ()
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

-- A stored run, or nil when there is nothing usable. The store is data from an earlier version (or a
-- hand-edited one), so everything is checked: the id a short string, the Day a whole number inside
-- the streak's range, the pass a boolean roll whose anomaly THIS catalog still has. An unknown anomaly
-- keeps the Day and drops the pass (the next pass is rolled): that is a catalog change, never
-- something a player can arrange, so it is not a re-roll they can use.
local function sanitizeRun(raw: any): Run?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" or #raw.id > 64 then
		return nil
	end
	local d = tonumber(raw.day)
	if d == nil or d ~= d or d % 1 ~= 0 then
		return nil
	end
	d = math.clamp(d, Config.Progression.StartDay, Config.Progression.MaxDay)
	local pass = nil
	local p = raw.pass
	if type(p) == "table" and type(p.clean) == "boolean" then
		if p.clean then
			pass = { clean = true }
		elseif type(p.anomalyId) == "string" and Anomaly.byId(Config, p.anomalyId) ~= nil then
			pass = { clean = false, anomalyId = p.anomalyId }
		end
	end
	return { id = raw.id, day = d, pass = pass }
end

local function isKnownAnomaly(id: string): boolean
	return Anomaly.byId(Config, id) ~= nil
end

-- The board's count follows the Field Guide: only ids THIS catalog knows count (a profile carrying
-- retired ids can never show more than the catalog has), and a new count is stamped with the time it
-- was first reached, which breaks ties on the board.
local function reconcileGuide(prof: any)
	local known = Codex.countKnown(prof.caught, isKnownAnomaly)
	if known > prof.guideCount then
		prof.guideCount = known
		prof.guideAt = os.time()
	elseif known < prof.guideCount then
		prof.guideCount = known -- the catalog retired ids since; the board store keeps what it has
	end
end

-- The stored { count, at, published }, or zeros.
local function readGuide(prof: any, raw: any)
	if type(raw) ~= "table" then
		return
	end
	local c, a, pub = tonumber(raw.count), tonumber(raw.at), tonumber(raw.published)
	if c and c == c then prof.guideCount = math.max(0, math.floor(c)) end
	if a and a == a then prof.guideAt = math.floor(a) end
	if pub and pub == pub then prof.guidePublished = math.max(0, math.floor(pub)) end
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
		closing = false,
		publishedBest = 0,
		lastPublishAt = -math.huge, -- so the first publish is never throttled
		readOnlyNotified = false,
		redeemBusy = false,
		remoteAt = {},
		guideCount = 0,
		guideAt = 0,
		guidePublished = 0,
		lastGuideAt = -math.huge, -- so the first board write is never throttled
	}
end

-- What one lock-claim attempt learned: the stored values (always) and whether we now own the
-- lock (`got`). Kept separate from Profile so a RETRY can merge instead of overwrite.
type ClaimResult = {
	got: boolean,
	bestDay: number,
	caught: any,
	hintTokens: number,
	redeemed: any,
	tint: string,
	ownedTints: { [string]: boolean },
	run: any, -- raw; sanitizeRun decides what of it is usable
	guide: any, -- raw; the board's { count, at, published }
}

-- Read the real profile via UpdateAsync and, if the previous lock is absent/stale/ours, claim
-- it. Used both at join and by the periodic RETRY (R1), so there is exactly ONE copy of the
-- lock rules. Returns nil when the DataStore call itself failed (never guess at that point).
local function claimLock(plr: Player, myToken: string): ClaimResult?
	if not profileStore then
		return nil
	end
	local res: ClaimResult = {
		got = false,
		bestDay = 0,
		caught = {},
		hintTokens = Config.Hint.StartTokens,
		redeemed = {},
		tint = Config.DefaultTint,
		ownedTints = { [Config.DefaultTint] = true },
	}
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

			-- adopt the stored data either way (a live read never overwrites, only reads).
			-- Re-assigned on every transform attempt, so a retry can never leave a half-read mix.
			res.got = false
			res.bestDay = tonumber(old.bestDay) or 0
			res.caught = old.caught or {}
			res.hintTokens = tonumber(old.hintTokens) or Config.Hint.StartTokens
			res.redeemed = old.redeemed or {}
			local storedTint = old.tint
			res.tint = (type(storedTint) == "string" and tintIsKnown(storedTint)) and storedTint or Config.DefaultTint
			res.ownedTints = sanitizeOwnedTints(old.ownedTints, res.tint)
			res.run = old.run
			res.guide = old.guide

			if heldByOther then
				-- R8: someone else holds it — load READ-ONLY. Returning `old` here still counts
				-- as an UpdateAsync WRITE (a full profile round-trip on every locked-out join,
				-- for nothing). Returning nil aborts the write and keeps only the read.
				return nil
			end

			-- free / stale / ours: take the lock
			res.got = true
			old.bestDay = res.bestDay
			old.caught = res.caught
			old.hintTokens = res.hintTokens
			old.redeemed = res.redeemed
			old.tint = res.tint
			old.ownedTints = res.ownedTints
			old.lock = { at = nowStamp(), token = myToken }
			return old
		end)
	end)
	if not success then
		warn("[Anomaly] lock claim failed for", plr.Name, err)
		return nil
	end
	return res
end

-- Drop a lock we own WITHOUT needing a live profile entry. Used when a retry wins the lock for
-- a player who has already left (the profile table entry is gone, so saveProfile can't help).
local function releaseLockToken(userId: number, token: string)
	if not profileStore or token == "" then
		return
	end
	pcall(function()
		profileStore:UpdateAsync("u_" .. userId, function(old)
			if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.token ~= token then
				return nil -- not ours (or already gone): change nothing, write nothing
			end
			old.lock = nil
			return old
		end)
	end)
end

-- canSave is set only when we acquire the lock, so a second session never clobbers the first,
-- and a failed load never overwrites real data. A read-only session is NOT permanent any more:
-- the autosave loop re-attempts the claim (see retryClaim, R1).
local function loadProfile(plr: Player): Profile
	local prof = defaultProfile()
	if not profileStore then
		return prof
	end
	local myToken = newSessionToken()
	local res = claimLock(plr, myToken)
	if not res then
		-- load failed: we know NOTHING about the stored data, so stay read-only and keep
		-- publishedBest at 0 (publishBest is gated on canSave, so it can't publish anyway).
		return prof
	end
	prof.bestDay = res.bestDay
	prof.caught = res.caught
	prof.hintTokens = res.hintTokens
	prof.redeemed = res.redeemed
	prof.tint = res.tint
	prof.ownedTints = res.ownedTints
	prof.publishedBest = res.bestDay -- R2: never publish BELOW what we actually loaded
	prof.canSave = res.got
	prof.lockToken = res.got and myToken or ""
	-- A read-only session starts from the stored run too (the player sees their Day), and retryClaim
	-- decides what wins once it can save.
	prof.run = sanitizeRun(res.run)
	prof.loadedRunId = prof.run and prof.run.id or nil
	readGuide(prof, res.guide)
	reconcileGuide(prof) -- a profile from before the board: its count is stamped now (when is unknown)
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
	-- R7: once the profile is CLOSED (PlayerRemoving / ghost reap started the releasing save)
	-- only that release may still write. Cheap short-circuit; the authoritative check is inside
	-- the transform below, because a renew can already be in flight when `closing` is set.
	if prof.closing and not releaseLock then
		return false
	end
	local key = "u_" .. plr.UserId
	local wrote = false
	local success = pcall(function()
		profileStore:UpdateAsync(key, function(old)
			old = old or {}
			wrote = false -- reset per transform attempt (UpdateAsync may retry)
			-- R7: the profile may have been closed while THIS UpdateAsync was in flight. A renew
			-- landing after the releasing save re-arms the lock for a player who already left,
			-- locking the real player out of saving on every other server for the whole TTL.
			-- UpdateAsync re-runs the transform on a write conflict, so the last runner sees it.
			if prof.closing and not releaseLock then
				return nil -- abort: write nothing
			end
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
			old.run = prof.run
			old.guide = { count = prof.guideCount, at = prof.guideAt, published = prof.guidePublished }
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

-- R9: minimum seconds between OrderedDataStore writes for one player. A fast climb used to
-- burn one SetAsync per day; the ordered-store budget is per-key rate limited, so a good run
-- could start dropping writes. `force` (on leave / shutdown) always flushes the final value.
local PUBLISH_MIN_INTERVAL = 30

local function publishBest(plr: Player, force: boolean?)
	if not bestBoard then
		return
	end
	local prof = profiles[plr]
	if not prof then
		return
	end
	-- R2: the leaderboard is persistent state like any other, so it needs the SAME ownership
	-- gate as saveProfile. Without it a session whose load failed (bestDay defaults to 0) or a
	-- session locked out by another server could overwrite the player's real entry with a
	-- lower number. Two guards: we must hold the lock, and we never publish below the value we
	-- actually loaded / already published.
	if not prof.canSave or prof.lockToken == "" then
		return
	end
	if prof.bestDay <= 0 or prof.bestDay <= prof.publishedBest then
		return
	end
	local now = os.clock()
	if not force and (now - prof.lastPublishAt) < PUBLISH_MIN_INTERVAL then
		return
	end
	local target = prof.bestDay
	local okPub = pcall(function()
		bestBoard:SetAsync("u_" .. plr.UserId, target)
	end)
	if okPub then
		prof.publishedBest = math.max(prof.publishedBest, target)
		prof.lastPublishAt = now
	end
end

-- The Field Guide board (queued job A): write this player's count when it has gone UP since the last
-- write. UpdateAsync keeps the larger value, so a write can never lower the board (on an equal count
-- the earlier time is the larger value). Same ownership gate as publishBest; throttled per player, and
-- `force` (autosave, leave, shutdown) flushes whatever is waiting.
local function publishGuide(plr: Player, force: boolean?)
	if not guideStore then
		return
	end
	local prof = profiles[plr]
	if not prof or not prof.canSave or prof.lockToken == "" then
		return
	end
	if prof.guideCount <= 0 or prof.guideCount <= prof.guidePublished then
		return
	end
	local now = os.clock()
	if not force and (now - prof.lastGuideAt) < Config.Guide.PublishMinSeconds then
		return
	end
	prof.lastGuideAt = now
	local count = prof.guideCount
	local value = Highscore.encode(count, prof.guideAt, Anomaly.count(Config))
	local okPub = pcall(function()
		guideStore:UpdateAsync(Highscore.key(plr.UserId), function(old)
			if type(old) == "number" and old >= value then
				return nil -- the board already holds this count (or better): write nothing
			end
			return value
		end)
	end)
	if okPub then
		prof.guidePublished = math.max(prof.guidePublished, count)
	end
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

-- HIDDEN and SHOWN (review 2026-09-30, finding 1). The zone is in workspace, so every client receives
-- its instance tree: names, classes, parents. The appliers used to ADD parts named after the answer
-- ("DoorExtra", "TelescopeTwin", "Fog", a Model "Figure") and DESTROY named ones ("Telescope",
-- "Plant", "Chair4"), so `zone:FindFirstChild("DoorExtra")` answered the pass without looking, the
-- same labelled answer the PassInfo move (CLAUDE.md) took away from `Clean = true`. Now everything
-- an anomaly can add is built into EVERY hall, hidden, and everything it can remove is hidden in
-- place; an applier only changes properties of parts that are always there. The tree is identical on
-- every pass (robloxemu/check_anomaly_names.luau forces every catalog id and compares it, in order).
-- What a script can still do is diff PROPERTIES against a clean hall it recorded: that is R12 below,
-- the cost this game accepts, because the anomaly has to be drawn to be seen.
--
-- Hidden is Fx.dustVolume's convention: not drawn, not felt, not touched, not hit by a ray (so the
-- default camera's occlusion ignores it too), no shadow.
local function hide(p: BasePart)
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
end

-- Shown: an ordinary part again (the engine's defaults), at the transparency the anomaly draws.
local function show(p: BasePart, transparency: number, collide: boolean)
	p.Transparency = transparency
	p.CanCollide = collide
	p.CanTouch = true
	p.CanQuery = true
	p.CastShadow = true
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
	-- The entrance (+Z) stays open to the eye, because the sky outside is the game's progress view
	-- (EYECANDY.md), but not to the feet: the floor ends at z = +10 and past it is the void, so walking
	-- out to look dropped the player off the world (review 2026-09-30, finding 7). An invisible pane,
	-- floor to ceiling, just inside the entrance plane. Transparency 1 keeps it out of every photo and
	-- out of the default camera's occlusion (Poppercam only stops at parts under 0.25 transparency);
	-- 0.5 thick at z 9.5..10, so shot 1's caretaker (EYECANDY.md §9, parked at z = 8.5) stands clear.
	newPart({ Name = "EntranceGlass", Size = Vector3.new(20, 16, 0.5), CFrame = at(0, 8, 9.75), Transparency = 1, CanTouch = false, CastShadow = false, Parent = zone })

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
	-- The clock needs a FACE. It used to be a blank white slab, so "the wall clock reads the
	-- wrong time" was unreadable by construction - there was no time on it to read. The old
	-- applier rotated the whole slab 140 degrees, which drove its corner through WallL and
	-- looked like a build glitch rather than a stopped clock. Face plus two hands; the anomaly
	-- moves a hand.
	local clock = newPart({ Name = "Clock", Size = Vector3.new(0.3, 3, 3), CFrame = at(-9.5, 11, -30), Color = WHITE, Material = Enum.Material.SmoothPlastic, Parent = zone })
	-- Hands stand just proud of the face (the face's outward normal is +X, into the hall).
	-- Each is positioned by rotating about the clock's local X and then pushing out along its
	-- local Y, so the pivot is the clock's centre and a hand sweeps like a hand.
	local function clockHand(name: string, len: number, thick: number, angle: number)
		newPart({
			Name = name,
			Size = Vector3.new(0.12, len, thick),
			CFrame = clock.CFrame * CFrame.new(0.21, 0, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, len / 2, 0),
			Color = Color3.fromRGB(25, 25, 30),
			Material = Enum.Material.SmoothPlastic,
			Parent = zone,
		})
	end
	clockHand("ClockHandHour", 0.8, 0.16, math.rad(60))   -- pointing to 2
	clockHand("ClockHandMinute", 1.25, 0.11, math.rad(0)) -- pointing to 12
	newPart({ Name = "Plant", Size = Vector3.new(2, 4, 2), CFrame = at(7, 2.5, -10), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = zone })
	newPart({ Name = "Monitor", Size = Vector3.new(0.3, 3, 5), CFrame = at(-9.5, 6, -50), Color = Color3.fromRGB(20, 30, 40), Material = Enum.Material.Glass, Parent = zone })
	newPart({ Name = "Window", Size = Vector3.new(8, 8, 0.3), CFrame = at(0, 9, -HALL_LEN - 5.4), Color = Color3.fromRGB(180, 200, 230), Transparency = 0.4, Material = Enum.Material.Glass, Parent = zone })
	newPart({ Name = "Bench", Size = Vector3.new(6, 2, 2), CFrame = at(6, 1.5, -60), Color = Color3.fromRGB(90, 70, 55), Material = Enum.Material.Wood, Parent = zone })
	newPart({ Name = "Mirror", Size = Vector3.new(0.3, 6, 4), CFrame = at(9.5, 6, -64), Color = Color3.fromRGB(200, 220, 240), Reflectance = 0.6, Material = Enum.Material.Glass, Parent = zone })
	-- z must stay IN FRONT of the EndWall (centre z = -(HALL_LEN+6), 1 thick -> front face at
	-- -(HALL_LEN+5.5)). At -5.9 the sign was buried inside the wall and invisible, which made
	-- the `sign_swap` anomaly unspottable (a guaranteed unfair Day reset).
	newPart({ Name = "ExitSign", Size = Vector3.new(4, 1.5, 0.3), CFrame = at(0, 13, -HALL_LEN - 5.0), Color = Color3.fromRGB(40, 200, 90), Material = Enum.Material.Neon, Parent = zone })
	-- The sign needs something DIRECTIONAL on it. `sign_swap` used to yaw the sign 180 degrees,
	-- and a uniform-coloured box maps onto itself under that rotation - geometrically a no-op,
	-- exactly the failure the chart_flip comment already documents. The only thing the player
	-- could actually see was the colour change, while the hint said "pointing the wrong way".
	-- This arrow block sits on the right half of the sign; the anomaly moves it to the left.
	newPart({ Name = "ExitArrow", Size = Vector3.new(1.1, 0.7, 0.34), CFrame = at(1.3, 13, -HALL_LEN - 4.98), Color = Color3.fromRGB(240, 255, 240), Material = Enum.Material.Neon, Parent = zone })
	newPart({ Name = "DoorMain", Size = Vector3.new(5, 12, 0.5), CFrame = at(0, 6, -HALL_LEN - 5.6), Color = Color3.fromRGB(70, 55, 45), Material = Enum.Material.Wood, Parent = zone })
	-- four chairs (count_off / chair_moved touch these)
	for i = 1, 4 do
		newPart({ Name = "Chair" .. i, Size = Vector3.new(2, 3, 2), CFrame = at(-6, 1.5, -44 - i * 3), Color = Color3.fromRGB(80, 80, 95), Parent = zone })
	end

	-- spawn pad (start of the loop) + decision pads (end)
	newPart({ Name = "StartPad", Size = Vector3.new(6, 0.2, 6), CFrame = at(0, 1, -4), Color = Color3.fromRGB(60, 90, 140), Material = Enum.Material.Neon, Transparency = 0.3, Parent = zone })

	-- The SPARES (finding 1, see `hide` above): what an anomaly can add, in every hall, hidden. Each is
	-- built exactly as its applier used to build it, so a shown spare is the anomaly it always was.
	local figure = makeFigure(at(0, 2.5, -HALL_LEN - 3) * CFrame.Angles(0, math.pi, 0))
	figure.Parent = zone
	for _, p in figure:GetChildren() do
		if p:IsA("BasePart") then hide(p) end
	end
	local head = figure:FindFirstChild("Head")
	local eye = head and head:FindFirstChildOfClass("PointLight")
	if eye then eye.Enabled = false end -- a hidden figure must not glow red through the hall
	hide(newPart({ Name = "Door2", Size = Vector3.new(5, 12, 0.5), CFrame = at(-8, 6, -70) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(70, 55, 45), Material = Enum.Material.Wood, Parent = zone }))
	local scope = zone:FindFirstChild("Telescope") :: Part
	local twin = scope:Clone()
	twin.Name = "Telescope2"
	twin.CFrame = scope.CFrame * CFrame.new(4, 0, 0)
	twin.Parent = zone
	hide(twin)
	local mirror2 = newPart({ Name = "Mirror2", Size = Vector3.new(0.3, 6, 4), CFrame = at(9.5, 6, -30), Color = Color3.fromRGB(200, 220, 240), Reflectance = 0, Material = Enum.Material.Glass, Parent = zone })
	hide(mirror2)
	hide(newPart({ Name = "Mist", Size = Vector3.new(18, 14, 30), CFrame = at(0, 8, -HALL_LEN / 2), Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.SmoothPlastic, Parent = zone }))

	-- Floating dust motes down the length of the hall — cheap, code-only atmosphere. Rebuilt
	-- with the rest of the clean hall each pass, so it can never linger as a false "anomaly".
	Fx.dustVolume(zone, Vector3.new(18, 14, HALL_LEN), at(0, 8, -HALL_LEN / 2), Color3.fromRGB(200, 210, 230), 10)
end

-- Stand the hidden Figure at `cf` and show it (three anomalies share the one figure; a pass carries
-- at most one anomaly).
local function showFigure(zone: Model, cf: CFrame)
	local m = zone:FindFirstChild("Figure")
	if not m then return end
	local torso = m:FindFirstChild("Torso")
	local head = m:FindFirstChild("Head")
	if torso and torso:IsA("BasePart") then
		torso.CFrame = cf
		show(torso, 0, true)
	end
	if head and head:IsA("BasePart") then
		head.CFrame = cf * CFrame.new(0, 2.2, 0)
		show(head, 0, true)
		local eye = head:FindFirstChildOfClass("PointLight")
		if eye then eye.Enabled = true end
	end
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
	-- Anomalies that ADD or REMOVE something show a hidden spare or hide a part in place: they never
	-- create, destroy or rename an Instance (finding 1, `hide` above).
	figure_end = function(zone, origin)
		showFigure(zone, CFrame.new(origin + Vector3.new(0, 2.5, -HALL_LEN - 3)) * CFrame.Angles(0, math.pi, 0))
	end,
	door_extra = function(zone, origin)
		local p = findPart(zone, "Door2")
		if p then
			p.CFrame = CFrame.new(origin + Vector3.new(-8, 6, -70)) * CFrame.Angles(0, math.rad(90), 0)
			show(p, 0, true)
		end
	end,
	scope_gone = function(zone)
		local p = findPart(zone, "Telescope"); if p then hide(p) end
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
		-- Move the MINUTE HAND, not the clock. Rotating the whole slab pushed its corner through
		-- WallL and read as a build glitch; and with no hands on the face there was no time to
		-- read in the first place. Swinging the minute hand to roughly 20-past against an hour
		-- hand still on 2 is a clock that says something wrong.
		local clock = findPart(zone, "Clock")
		local hand = findPart(zone, "ClockHandMinute")
		if clock and hand then
			local len = hand.Size.Y
			hand.CFrame = clock.CFrame * CFrame.new(0.21, 0, 0) * CFrame.Angles(math.rad(125), 0, 0) * CFrame.new(0, len / 2, 0)
		end
	end,
	twin_scope = function(zone)
		local p = findPart(zone, "Telescope2"); if p then show(p, 0, true) end
	end,
	reflection_off = function(zone)
		local p = findPart(zone, "Mirror"); if p then p.Reflectance = 0; p.Color = Color3.fromRGB(20, 20, 30); p.Transparency = 0.1 end
	end,
	flicker_hall = function(zone)
		-- It has to actually flicker. This used to recolour fixture L3 green and stop, so the
		-- anomaly named "The Flicker", whose hint promises "a light strobing that shouldn't",
		-- was a steady green lamp. A player who missed it was then told to look for a strobe
		-- that the game had never once produced - which in a spot-the-difference game teaches
		-- the wrong lesson and costs the run after that one too.
		local lights = zone:FindFirstChild("Lights")
		if not lights then return end
		local ref = lights:FindFirstChild("L3")
		if not (ref and ref:IsA("ObjectValue") and ref.Value) then return end
		local fix = ref.Value :: Part
		local pl = fix:FindFirstChild("PL")
		local litColor, litMaterial = fix.Color, fix.Material

		-- The loop dies on its own: beginPass calls zone:ClearAllChildren() before every pass,
		-- which unparents the fixture, so `fix.Parent == nil` ends it. No bookkeeping, and no
		-- way for a stale strobe to survive into the next hall.
		task.spawn(function()
			-- Irregular on purpose. A metronome reads as an effect; an unsteady lamp reads as a
			-- fault, which is the thing the player is meant to notice.
			local gaps = { 0.06, 0.09, 0.05, 0.42, 0.07, 0.05, 0.28, 0.11 }
			local i = 0
			while fix.Parent ~= nil do
				i += 1
				local on = (i % 2) == 1
				fix.Material = on and litMaterial or Enum.Material.SmoothPlastic
				fix.Color = on and litColor or Color3.fromRGB(45, 45, 55)
				if pl and pl:IsA("PointLight") then
					pl.Enabled = on
				end
				task.wait(gaps[(i % #gaps) + 1])
			end
		end)
	end,
	scale_bench = function(zone)
		-- Scaling IN PLACE drove the bench out of the world: 6x2x2 at (6, 1.5) becomes
		-- 10.2x3.4x3.4, so it reached x = 11.1 (WallR's inner face is 9.5) and sank to y = -0.2
		-- (the floor's top face is 0.5). Clipping through the wall and floor reads as a BUILD
		-- BUG, not "that bench is too big" — the player learns to distrust the hall instead of
		-- reading it. Grow it, then re-seat it: flush on the floor, held inside the wall.
		local p = findPart(zone, "Bench")
		if not p then return end
		p.Size = p.Size * 1.7
		local pos = p.Position
		local floor = findPart(zone, "Floor")
		local floorTop = floor and (floor.Position.Y + floor.Size.Y / 2) or (pos.Y - 1)
		local wall = findPart(zone, "WallR")
		local wallInner = wall and (wall.Position.X - wall.Size.X / 2) or (pos.X + 3.5)
		local maxX = wallInner - p.Size.X / 2 - 0.4 -- 0.4 stud of daylight so it never z-fights
		p.CFrame = CFrame.new(math.min(pos.X, maxX), floorTop + p.Size.Y / 2, pos.Z)
	end,
	figure_window = function(zone, origin)
		-- Must stay on the PLAYER side of EndWall (z = -HALL_LEN - 6, opaque, full cross-section)
		-- and of the Window pane (z = -HALL_LEN - 5.4): anything beyond is sealed out of sight.
		-- Floating in front of the pane at window height reads as "a face in the window".
		showFigure(zone, CFrame.new(origin + Vector3.new(0, 9, -HALL_LEN - 4.2)) * CFrame.Angles(0, math.pi, 0))
	end,
	plant_gone = function(zone)
		local p = findPart(zone, "Plant"); if p then hide(p) end
	end,
	sign_swap = function(zone)
		-- Mirror the arrow to the other half of the sign. Yawing the sign itself did nothing
		-- visible: a uniform box is symmetric under 180 degrees, so the only tell was the
		-- colour, and the hint promised a direction.
		local sign = findPart(zone, "ExitSign")
		local arrow = findPart(zone, "ExitArrow")
		if arrow and sign then
			local d = arrow.Position - sign.Position
			arrow.Position = sign.Position + Vector3.new(-d.X, d.Y, d.Z)
		end
		if sign then sign.Color = Color3.fromRGB(200, 120, 30) end
	end,
	floor_tilt = function(zone)
		local p = findPart(zone, "Floor"); if p then p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(4)) end
	end,
	dupe_door = function(zone, origin)
		local p = findPart(zone, "Door2")
		if p then
			p.CFrame = CFrame.new(origin + Vector3.new(6, 6, -HALL_LEN - 5.6))
			show(p, 0, true)
		end
	end,
	moon_recolor = function(zone)
		local p = findPart(zone, "Window"); if p then p.Color = Color3.fromRGB(200, 40, 40); p.Transparency = 0.2 end
	end,
	static_screen = function(zone)
		local p = findPart(zone, "Monitor"); if p then p.Color = Color3.fromRGB(200, 200, 200); p.Material = Enum.Material.Neon end
	end,
	figure_ceiling = function(zone, origin)
		showFigure(zone, CFrame.new(origin + Vector3.new(0, 14, -HALL_LEN / 2)) * CFrame.Angles(math.pi, 0, 0))
	end,
	mirror_extra = function(zone)
		local p = findPart(zone, "Mirror2")
		if p then
			p.Reflectance = 0.6
			show(p, 0, true)
		end
	end,
	scope_tilt = function(zone)
		local p = findPart(zone, "Telescope"); if p then p.CFrame = p.CFrame * CFrame.Angles(-1.4, 0, 0) end
	end,
	cold_breath = function(zone)
		local p = findPart(zone, "Mist"); if p then show(p, 0.75, false) end
	end,
	count_off = function(zone)
		local p = findPart(zone, "Chair4"); if p then hide(p) end
	end,
}

-- Refuse to start if any catalog entry has no applier. An id without one is not a missing
-- feature the player never sees - it is an UNWINNABLE ROUND. beginPass sets ps.clean = false
-- and ps.anomalyId, then finds no applier and mutates nothing, so the player walks a pristine
-- hall the game believes is wrong: ADVANCE is scored as a miss and resets them to Day 1, and
-- TURN BACK is scored correct on no evidence at all. Nothing about that is visible from
-- inside the game, and the existing spec only checks that ids are unique.
--
-- Failing here is loud, happens once at boot, and is impossible to miss in the F9 console.
for _, entry in Config.Anomaly.Catalog do
	if APPLIERS[entry.id] == nil then
		error(string.format(
			"[Anomaly] catalog entry '%s' (%s) has no APPLIERS handler. Every anomaly must "
				.. "change the hall, or the round it is drawn for cannot be won by looking.",
			tostring(entry.id), tostring(entry.name)
		), 0)
	end
end

-- ------------------------------------------------------------------ Prompts
local function makePrompt(parent: Part, text: string, key: Enum.KeyCode?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = text
	pp.ObjectText = "Observatory"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	-- Show BOTH decision prompts at once. ProximityPrompt defaults to Exclusivity = OneGlobally,
	-- which shows only the closest one; ADVANCE and TURN BACK sit 8 studs apart on the same wall,
	-- so a player between them sees one of the two choices rather than both. For a game whose
	-- entire interface is "press one of these two keys", showing both is plainly right.
	--
	-- Being careful about what this does NOT claim: presses were also being lost during
	-- automated playtesting, and this was briefly blamed for that. It was not the cause. The
	-- cause was in the test harness - it walked to the pad while the player was still being
	-- teleported back to the start, and pressed from out of range. This setting is a UI
	-- improvement, not a bug fix, and no dropped input has been demonstrated in real play.
	pp.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	if key then
		pp.KeyboardKeyCode = key
	end
	pp.Parent = parent
	return pp
end

-- ------------------------------------------------------------------ Loop
-- Minimum wall-clock time between a pass going live and a decision being accepted. Walking
-- the ~80-stud hall takes many seconds, so this only ever bites scripted triggers.
--
-- R12 — WHAT THIS DOES NOT DO. This bounds the RATE, not the TOTAL: a patient bot can still
-- reach Config.Progression.MaxDay, it just takes MaxDay * MIN_PASS_SECONDS to do it. And the
-- gate cannot be tightened into an anti-cheat, because the correct answer is inherently
-- OBSERVABLE CLIENT-SIDE: the anomaly is a real Instance replicated into the player's own
-- zone, so a client can read it and always answer correctly without ever looking at the hall.
-- Hiding it would mean not replicating the mutation, i.e. not having a game. So: treat the
-- Best-Day board as a fun counter, NOT as a trustworthy competitive ranking, and do not build
-- rewards on top of it that would pay out to a determined cheater.
-- (2026-09-30) What a client can read is now only the drawn change itself: the PROPERTIES of parts
-- that exist on every pass. The instance tree (names, classes, parents) is the same clean or not
-- (`hide`/`show` above, check_anomaly_names.luau), so no pass is answered by FindFirstChild; a
-- script must record a clean hall and diff it, which is the cost this game accepts. The Field Guide
-- board ranks on types caught, capped at the catalog's size, so this costs it at most the tie-break.
local MIN_PASS_SECONDS = 0.75

-- R10: the hint's in-world ProximityPrompt sits on the StartPad (MaxActivationDistance 12).
-- The remote must enforce the same reach or it is a strictly better hint with no cost.
-- Slightly larger than the prompt so replication lag never eats a legitimate press.
local HINT_RADIUS = 14

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
		-- R5: a read-only session must not be silent. The HUD shows this so the player knows
		-- the day they are grinding will not persist (and that we are retrying in background).
		readOnly = not prof.canSave,
	})
end

-- R5: one-shot notice when the session cannot save (and, on recovery, when it can again).
-- Silence meant a player could grind a best day for an hour with nothing being written.
local function notifyReadOnly(plr: Player)
	local prof = profiles[plr]
	if not prof or prof.canSave or prof.readOnlyNotified then
		return
	end
	prof.readOnlyNotified = true
	RevealRemote:FireClient(plr, {
		readOnly = true,
		message = "Progress can't be saved right now — another session may still be open. Retrying in the background.",
	})
end

-- R1: a read-only session RE-ATTEMPTS the claim instead of being read-only forever. One
-- transient DataStore error at join, or a rejoin while the previous lock is still warm (TTL
-- 45s), used to disable saving for the WHOLE session — while the redeem message promised
-- "try again in a minute", which the code could never honour.
--
-- Clobber safety: whoever held the lock may have written newer data, so we do NOT push our
-- in-memory copy over it. We ADOPT the freshly read values and merge only where merging is
-- strictly non-destructive (max for bestDay, union for the Field Guide).
local function retryClaim(plr: Player)
	local prof = profiles[plr]
	if not prof or prof.canSave or prof.closing or not profileStore then
		return
	end
	local myToken = newSessionToken()
	local res = claimLock(plr, myToken) -- YIELDS
	if not res or not res.got then
		return -- still held elsewhere, or the store is still unhappy: try again next tick
	end

	-- We yielded. If the player left (or the entry was replaced) during the claim, we now hold
	-- a lock for a session that no longer exists — release it immediately rather than letting
	-- it sit for the full TTL and lock the real player out on the server they moved to.
	if profiles[plr] ~= prof or prof.closing or plr.Parent ~= Players then
		releaseLockToken(plr.UserId, myToken)
		return
	end

	prof.bestDay = math.max(prof.bestDay, res.bestDay)
	if type(res.caught) == "table" then
		for id in res.caught do
			prof.caught[id] = true -- union: never drop a discovery from either side
		end
	end
	-- the board: the other session's count and time win when it got further, or got there first
	do
		local mine = { guideCount = prof.guideCount, guideAt = prof.guideAt, guidePublished = prof.guidePublished }
		readGuide(mine, res.guide)
		if mine.guideCount > prof.guideCount or (mine.guideCount == prof.guideCount and mine.guideAt > 0 and mine.guideAt < prof.guideAt) then
			prof.guideCount, prof.guideAt = mine.guideCount, mine.guideAt
		end
		prof.guidePublished = math.max(prof.guidePublished, mine.guidePublished)
		reconcileGuide(prof)
	end
	-- These are all authoritative-elsewhere values: the other session owned the write path, so
	-- its numbers win over ours (adopting can only over-credit the player, never rob them).
	prof.hintTokens = res.hintTokens
	prof.redeemed = res.redeemed
	local localTint = prof.tint
	prof.ownedTints = res.ownedTints
	prof.tint = prof.ownedTints[localTint] and localTint or res.tint
	prof.publishedBest = math.max(prof.publishedBest, res.bestDay)
	prof.canSave = true
	prof.lockToken = myToken
	prof.readOnlyNotified = false

	-- The run (owner decision 2026-09-30). This session started from the run it loaded, read-only. If
	-- the stored run is no longer that one, the other session wrote after our read: most importantly a
	-- wrong call's reset, which a stale copy must never undo. So unless this session has a run of its
	-- own (it started fresh, or made its own wrong call, whose reset stands), the stored run wins.
	local ps = passState[plr]
	local stored = sanitizeRun(res.run)
	local adopt: Run? = nil
	if ps and stored and stored.id ~= prof.loadedRunId and not ps.ownRun then
		adopt = stored
		ps.day = stored.day
		ps.runId = stored.id
		prof.run = stored
		prof.loadedRunId = stored.id
	end
	plr:SetAttribute("SavesRun", true)

	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local b = ls:FindFirstChild("Best")
		if b then (b :: IntValue).Value = prof.bestDay end
		local d = ls:FindFirstChild("Day")
		if d and ps then (d :: IntValue).Value = ps.day end
	end
	RevealRemote:FireClient(plr, {
		readOnly = false,
		message = if adopt
			then string.format("Saving restored — your saved run is back: Day %d.", adopt.day)
			else "Saving restored — your progress is being recorded again.",
	})
	if adopt then
		beginPass(plr, adopt.pass) -- the stored run's own hall (or a fresh roll if it had none)
	else
		pushState(plr)
	end
end

-- Where the server says out loud what it just rolled, for tools that need to know: the marketing
-- capture rig, which has to shoot a MATCHED pair of the same hall clean and anomalous, and the
-- headless check. `passState` is a table local to this script, so without this there is no way
-- from outside to tell whether the hall standing in the workspace is clean or which anomaly is
-- in it, and both were left inferring it from pixels or from geometry they had to re-derive.
--
-- ServerStorage, deliberately. See the note at the write site in beginPass.
local passInfoRoot = ServerStorage:FindFirstChild("PassInfo")
if not passInfoRoot then
	passInfoRoot = Instance.new("Folder")
	passInfoRoot.Name = "PassInfo"
	passInfoRoot.Parent = ServerStorage
end

local function passInfoFor(plr: Player): Folder
	local key = tostring(plr.UserId)
	local existing = passInfoRoot:FindFirstChild(key)
	if existing then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = key
	f.Parent = passInfoRoot
	return f
end

-- ------------------------------------------------------------------ The Field Guide board (job A)
-- Queued job A, design approved by the owner 2026-09-16. A sign on the right-hand wall just behind the
-- start pad ranks players on Field Guide completion: anomaly TYPES caught, 0..the catalog's size, ties
-- broken by who reached that count first (Highscore.luau encodes both into one ordered-store integer).
-- Its prompt (L, gamepad Y, or a tap) switches PUBLIC / FRIENDS:
--   * PUBLIC is GetSortedAsync(false, 10) inside Highscore.range (a fabricated value above the cap is
--     never fetched), ONE fetch per server per Config.Guide.PublicCacheSeconds, shared by every sign;
--   * FRIENDS is Players:GetFriendsAsync (first FriendsCap) and one GetAsync per friend, only when the
--     player asks, cached per player, stopping early if the server's GetAsync budget runs low, all
--     pcall'd; the player's own row comes from memory. An empty friends board says why.
-- Names come from GetNameFromUserIdAsync (or the Player in this server), cached in memory, NEVER stored.
--
-- Where, and why there: the capture rig (tools/film_anomaly.py) shoots from hall-local (0, 7.5, +4)
-- looking down the hall, and the hero thumbnail (marketing/ShotList.luau, shot 1) from (2, 5.5, -2)
-- looking out of the doorway. On the right-hand wall at z 0..4 the sign is outside both frames
-- (robloxemu/check_anomaly_board.luau projects its corners): the pairs must not differ by a scoreboard
-- and no thumbnail carries a player's name. It is NOT part of the zone model: the hall is rebuilt every
-- pass and must stay identical (check_anomaly_names); the sign changes. Its SurfaceGui is on the part, the
-- usual way for a physical board (robloxemu's HUD gate walks everything in PlayerGui as a screen panel).
type BoardRow = { userId: number, caught: number, at: number, name: string? }
type Board = {
	model: Model,
	part: Part,
	prompt: ProximityPrompt,
	labels: { [string]: TextLabel },
	mode: string, -- "public" | "friends"
	friends: any?, -- { at, rows, ids, checked, failed, partial } once fetched
	friendsLoading: boolean,
}
local boards: { [Player]: Board } = {}
local nameCache: { [number]: string } = {} -- userId -> name, memory only
local nameCount = 0
local publicBoard: { at: number, rows: { BoardRow }?, failed: boolean, fetching: boolean } =
	{ at = -math.huge, rows = nil, failed = false, fetching = false }

local BOARD_BG = Color3.fromRGB(14, 18, 30)
local BOARD_TEXT = Color3.fromRGB(205, 215, 240)
local BOARD_DIM = Color3.fromRGB(140, 150, 185)

local function nameOf(userId: number): string
	local here = Players:GetPlayerByUserId(userId)
	if here then
		return here.Name
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(n) == "string" and n ~= "" then
		if nameCount >= 2000 then
			table.clear(nameCache) -- a bound, not a policy: names are cheap to look up again
			nameCount = 0
		end
		nameCache[userId] = n
		nameCount += 1
		return n
	end
	return "(unknown player)"
end

local function rowOrder(total: number): (BoardRow, BoardRow) -> boolean
	return function(a, b)
		return Highscore.encode(a.caught, a.at, total) > Highscore.encode(b.caught, b.at, total)
	end
end

-- The public list, re-read at most once per window for the whole server; a failure is not retried
-- inside the window either (the stale list, if any, stays up).
local function fetchPublic()
	if not guideStore then
		publicBoard.failed = true
		return
	end
	local now = os.clock()
	if publicBoard.at > -math.huge and now - publicBoard.at < Config.Guide.PublicCacheSeconds then
		return
	end
	if publicBoard.fetching then
		return
	end
	publicBoard.fetching = true
	local total = Anomaly.count(Config)
	local lo, hi = Highscore.range(total)
	local ok, entries = pcall(function()
		return (guideStore :: any):GetSortedAsync(false, Config.Guide.BoardSize, lo, hi):GetCurrentPage()
	end)
	if ok and type(entries) == "table" then
		local rows: { BoardRow } = {}
		for _, e in entries do
			local uid = Highscore.userIdFromKey(e.key)
			if uid and type(e.value) == "number" then
				local c, at = Highscore.decode(e.value, total)
				if c >= 1 then
					table.insert(rows, { userId = uid, caught = c, at = at, name = nameOf(uid) })
				end
			end
		end
		table.sort(rows, rowOrder(total))
		publicBoard.rows = rows
		publicBoard.failed = false
	else
		publicBoard.failed = true
	end
	publicBoard.at = now
	publicBoard.fetching = false
end

-- What the server may still spend on GetAsync this minute (nil when Roblox will not say).
local function getAsyncBudget(): number?
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return if ok and type(n) == "number" then n else nil
end

-- This player's friends on the board: only when asked for, cached per player.
local function fetchFriends(plr: Player, board: Board)
	local now = os.clock()
	local f = board.friends
	if f and now - f.at < (if f.failed then Config.Guide.FriendsFailSeconds else Config.Guide.FriendsCacheSeconds) then
		return
	end
	if board.friendsLoading then
		return
	end
	board.friendsLoading = true
	local result = { at = now, rows = {}, ids = 0, checked = 0, failed = false, partial = false }
	local okF, pages = pcall(function()
		return Players:GetFriendsAsync(plr.UserId)
	end)
	if not okF or pages == nil or not guideStore then
		result.failed = true
	else
		local ids: { number } = {}
		local cap = Config.Guide.FriendsCap
		while #ids < cap do
			local okP, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if not okP or type(page) ~= "table" then
				break
			end
			for _, fr in page do
				local id = type(fr) == "table" and tonumber(fr.Id) or nil
				if id and #ids < cap then
					table.insert(ids, id)
				end
			end
			local finished = true
			pcall(function()
				finished = pages.IsFinished
			end)
			if finished or #ids >= cap then
				break
			end
			if not pcall(function()
				pages:AdvanceToNextPageAsync()
			end) then
				break
			end
		end
		result.ids = #ids
		local total = Anomaly.count(Config)
		for _, id in ids do
			local budget = getAsyncBudget()
			if budget ~= nil and budget <= Config.Guide.MinGetBudget then
				result.partial = true -- the rest next time: never spend the server's whole budget here
				break
			end
			local okG, v = pcall(function()
				return (guideStore :: any):GetAsync(Highscore.key(id))
			end)
			result.checked += 1
			if okG and type(v) == "number" then
				local c, at = Highscore.decode(v, total)
				if c >= 1 then
					table.insert(result.rows, { userId = id, caught = c, at = at })
				end
			end
		end
		table.sort(result.rows, rowOrder(total))
		while #result.rows > Config.Guide.BoardSize do
			table.remove(result.rows)
		end
		for _, r in result.rows do
			r.name = nameOf(r.userId)
		end
	end
	board.friends = result
	board.friendsLoading = false
end

local function renderBoard(plr: Player)
	local board = boards[plr]
	local prof = profiles[plr]
	if not board or not prof then
		return
	end
	local L = board.labels
	local total = Anomaly.count(Config)
	local rows: { BoardRow } = {}
	local status = ""
	if board.mode == "friends" then
		L.Mode.Text = "FRIENDS  ·  press L or tap for public"
		board.prompt.ActionText = "Show public"
		local f = board.friends
		if f == nil then
			status = "Loading your friends…"
		elseif f.failed then
			status = "Couldn't reach Roblox for your friends list. Try again in a minute."
		else
			for _, r in f.rows do
				table.insert(rows, r)
			end
			if prof.guideCount >= 1 then
				table.insert(rows, { userId = plr.UserId, caught = prof.guideCount, at = prof.guideAt, name = plr.Name })
			end
			if f.ids == 0 then
				status = "Add friends on Roblox to compare Field Guides here."
			elseif #f.rows == 0 then
				status = string.format("None of your friends has caught an anomaly yet. The Field Guide has %d to find: bring one along!", total)
			elseif f.partial then
				status = string.format("Checked %d of %d friends (Roblox's request limit). The rest next time.", f.checked, f.ids)
			end
		end
	else
		L.Mode.Text = "PUBLIC  ·  press L or tap for friends"
		board.prompt.ActionText = "Show friends"
		if publicBoard.rows then
			for _, r in publicBoard.rows do
				table.insert(rows, r)
			end
			if #rows == 0 then
				status = string.format("Nobody has caught an anomaly yet. %d to find: be the first!", total)
			end
		elseif publicBoard.failed then
			status = "The board can't reach Roblox right now. It tries again every minute."
		else
			status = "Loading the board…"
		end
	end
	table.sort(rows, rowOrder(total))
	for i = 1, Config.Guide.BoardSize do
		local r = rows[i]
		L["Row" .. i].Text = if r then string.format("%d. %s  %d/%d", i, r.name or "(unknown player)", r.caught, total) else ""
	end
	L.Status.Text = status
end

local function buildBoard(plr: Player, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "GuideBoard_" .. plr.UserId
	-- 4 studs wide (z 0..4), 5 tall, on the right-hand wall's inner face, facing into the hall (-X)
	local part = newPart({ Name = "Board", Size = Vector3.new(0.3, 5, 4), CFrame = CFrame.new(origin + Vector3.new(9.3, 6, 2)),
		Color = BOARD_BG, Material = Enum.Material.SmoothPlastic, CastShadow = false })
	part.Parent = model
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GuideBoardGui"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50 -- a 200 x 250 px canvas
	gui.LightInfluence = 0 -- readable in the dark hall
	gui.Parent = part
	local labels: { [string]: TextLabel } = {}
	local function label(name: string, y: number, h: number, size: number, color: Color3, bold: boolean)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 8, 0, y)
		l.Size = UDim2.new(1, -16, 0, h)
		l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextWrapped = true
		l.Text = ""
		l.Parent = gui
		labels[name] = l
	end
	label("Title", 6, 20, 15, BOARD_TEXT, true)
	labels.Title.Text = "📖 FIELD GUIDE · TOP " .. Config.Guide.BoardSize
	label("Mode", 26, 16, 10, BOARD_DIM, true)
	for i = 1, Config.Guide.BoardSize do
		label("Row" .. i, 44 + (i - 1) * 16, 16, 12, BOARD_TEXT, false)
	end
	label("Status", 44 + Config.Guide.BoardSize * 16 + 2, 44, 10, BOARD_DIM, false)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Show friends"
	prompt.ObjectText = "Field Guide board"
	prompt.KeyboardKeyCode = Enum.KeyCode.L
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY -- the hint prompt on the pad next to it has ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent = part
	model.Parent = workspace

	local board: Board = { model = model, part = part, prompt = prompt, labels = labels, mode = "public", friends = nil, friendsLoading = false }
	boards[plr] = board
	prompt.Triggered:Connect(function(who)
		if who ~= plr or boards[plr] ~= board then
			return
		end
		-- No cooldown needed: a switch re-renders from the caches, and a fetch is never run twice at once.
		board.mode = if board.mode == "public" then "friends" else "public"
		renderBoard(plr)
		task.spawn(function()
			if board.mode == "friends" then
				fetchFriends(plr, board)
			else
				fetchPublic()
			end
			if boards[plr] == board then
				renderBoard(plr)
			end
		end)
	end)
	renderBoard(plr)
	task.spawn(function()
		fetchPublic()
		if boards[plr] == board then
			renderBoard(plr)
		end
	end)
end

local function dropBoard(plr: Player)
	local board = boards[plr]
	if board then
		board.model:Destroy()
		boards[plr] = nil
	end
end

-- Called by the autosave loop: one fetch for the whole server once the window has passed, then every
-- sign showing the public board is redrawn.
local function refreshPublicBoards()
	local any = false
	for _, b in boards do
		if b.mode == "public" then
			any = true
			break
		end
	end
	if not any then
		return
	end
	fetchPublic()
	for p, b in boards do
		if b.mode == "public" then
			renderBoard(p)
		end
	end
end

-- Rebuild the hall and roll the next pass for this player. `restore` (a saved run's pass, already
-- through sanitizeRun) rebuilds THAT pass instead of rolling: a rejoin gets the hall it left.
beginPass = function(plr: Player, restore: any?)
	local prof = profiles[plr]
	local ps = passState[plr]
	local zone = zones[plr]
	if not prof or not ps or not zone then return end

	local index = tonumber(zone:GetAttribute("Index")) or 0
	local origin = zoneOrigin(index)

	-- rebuild CLEAN
	zone:ClearAllChildren()
	buildClean(zone, origin)

	-- roll (or restore the saved pass)
	ps.serial += 1
	local pass
	if type(restore) == "table" and type(restore.clean) == "boolean" then
		pass = { clean = restore.clean, anomalyId = if restore.clean then nil else restore.anomalyId }
	else
		local rng = Rng.new(passSeed(plr, ps.salt, ps.serial))
		pass = Anomaly.rollPass(rng, Config, ps.day)
	end
	ps.clean = pass.clean
	ps.anomalyId = pass.anomalyId
	ps.awaiting = true
	ps.startedAt = os.clock()
	ps.hinted = false

	if not pass.clean and pass.anomalyId then
		local applier = APPLIERS[pass.anomalyId]
		if applier then
			applier(zone, origin)
		else
			-- The startup guard above makes this unreachable. It stays as the second net,
			-- because the failure it catches is silent and expensive: the alternative to a
			-- warning here is a player being reset to Day 1 for correctly reading a hall that
			-- nothing had changed.
			warn("[Anomaly] no applier for '" .. tostring(pass.anomalyId) .. "'; treating this pass as CLEAN")
			ps.clean = true
			ps.anomalyId = nil
		end
	end

	-- Publish the roll on the zone itself.
	--
	-- `passState` is a table local to this script, so from outside it there is no way to tell
	-- whether the hall standing in the workspace is clean or which anomaly is in it. Anything
	-- that needs to know - the marketing capture rig, which has to shoot a MATCHED pair of the
	-- same hall clean and anomalous, or a headless check - was left inferring it from pixels or
	-- from geometry it had to re-derive. These two attributes say out loud what the server just
	-- decided, and they cost nothing to keep honest because they are written in the one place
	-- the decision is made.
	--
	-- These live in ServerStorage, which does NOT replicate. They were briefly written onto the
	-- zone model instead, which is parented to workspace, on the argument that it gave away
	-- nothing hidden: per R12 the anomaly is a real Instance in the player's own zone, so a
	-- client that wanted to cheat could already read the answer off the hall.
	--
	-- That argument is wrong, in one decisive place. On a CLEAN pass there is nothing in the
	-- hall to read. Finding the anomaly by inspecting the world means proving a NEGATIVE against
	-- a reference build you do not have; `Clean = true` hands that answer over as a labelled
	-- boolean, and `AnomalyId` names the object so you need not look at all. "A determined
	-- exploiter could derive it" and "every client is told it" are different costs, and the
	-- whole game is the looking.
	--
	-- The capture rig and the headless check read these through the SERVER datamodel, so
	-- ServerStorage costs them nothing.
	--
	-- Written AFTER the applier block on purpose: the missing-applier fallback demotes the pass
	-- to clean, and a pass demoted to clean must not still advertise an anomaly id.
	local info = passInfoFor(plr)
	info:SetAttribute("Clean", ps.clean)
	info:SetAttribute("AnomalyId", ps.anomalyId) -- nil removes the attribute
	info:SetAttribute("Serial", ps.serial)
	info:SetAttribute("Zone", zone.Name)

	-- the run as it now stands, with the pass that is live (saved by the next save; also after the
	-- missing-applier fallback above, so a demoted pass is saved as the clean pass it now is)
	prof.run = { id = ps.runId, day = ps.day, pass = { clean = ps.clean, anomalyId = ps.anomalyId } }

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
	if caughtId and Codex.discover(prof.caught, caughtId) then
		-- a NEW type: the board's count may go up (written at once, or by the autosave if throttled)
		local before = prof.guideCount
		reconcileGuide(prof)
		if prof.guideCount > before then
			task.spawn(publishGuide, plr, false)
			task.spawn(renderBoard, plr) -- the player's own row on their friends board
		end
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
		-- The run is over: a new one (new id, so no stale copy of the old one can ever be resumed, see
		-- retryClaim), with NO pass, since the Death payload below tells the player this pass's answer.
		-- Flushed now, not at the next autosave, so leaving during the death beat cannot undo it.
		ps.runId = newSessionToken()
		ps.ownRun = true
		prof.run = { id = ps.runId, day = ps.day }
		task.spawn(saveProfile, plr, false)
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			local d = ls:FindFirstChild("Day"); if d then (d :: IntValue).Value = ps.day end
		end
		DeathRemote:FireClient(plr, { reached = reached, wasClean = pass.clean, anomalyId = pass.anomalyId })
		task.wait(2.5) -- brief death beat
		-- R6: this resumes 2.5s later, and `profiles[plr]` alone is NOT proof the player is
		-- still here — PlayerRemoving yields inside saveProfile before it clears the tables, so
		-- the entry can still be present for a player who has already left. Building a fresh
		-- hall + teleporting a departed player leaks the zone rebuild and races the cleanup.
		if profiles[plr] and plr.Parent == Players then
			beginPass(plr)
		end
	end
end

useHint = function(plr: Player)
	local prof = profiles[plr]
	local ps = passState[plr]
	if not prof or not ps or not ps.awaiting then return end
	-- One hint per hall. Pressing H twice used to charge two hints for the same answer (the prompt has no
	-- cooldown and HoldDuration 0, so a double tap did it). The answer is already paid for: show it again.
	if ps.hinted then
		RevealRemote:FireClient(plr, { ok = true, clean = ps.clean, remaining = prof.hintTokens, again = true })
		return
	end
	if prof.hintTokens <= 0 then
		RevealRemote:FireClient(plr, { ok = false })
		return
	end
	prof.hintTokens -= 1
	ps.hinted = true
	RevealRemote:FireClient(plr, { ok = true, clean = ps.clean, remaining = prof.hintTokens })
	pushState(plr)
end

awardMilestone = function(plr: Player, day: number)
	-- Milestones are Config-listed; badge asset ids are wired in Config later.
	-- Kept idempotent + pcall-guarded so it can never break the loop.
	-- (Badge wiring intentionally deferred until real Badge asset ids exist.)
end

-- ------------------------------------------------------------------ Remote handlers
-- R4: RemoteEvents are client-driven, so their cost must be bounded server-side. Redeem is the
-- dangerous one — it runs UpdateAsync on ONE key, and a burst issues N CONCURRENT UpdateAsync
-- calls on that key: the per-key budget is exhausted, the transforms fight each other, and the
-- retry storm can starve real saves. Hint/Tint are cheap but still push a full state packet.
-- Cooldowns are per player and deliberately generous: a human taps these a few times a minute.
local REMOTE_COOLDOWN: { [string]: number } = {
	Redeem = 2.0,
	UseHint = 0.5,
	SetTint = 0.5,
}

local function rateLimited(prof: Profile, name: string): boolean
	local now = os.clock()
	local last = prof.remoteAt[name]
	if last and (now - last) < (REMOTE_COOLDOWN[name] or 0.5) then
		return true
	end
	prof.remoteAt[name] = now
	return false
end

-- Longest code in Config.Codes is 8 chars; anything wildly longer is spam, not a redemption.
local MAX_CODE_LEN = 64

RedeemRemote.OnServerEvent:Connect(function(plr, code)
	if typeof(code) ~= "string" then return end -- not something the HUD's box can send
	-- (standard §1, no silent no-ops) everything below that refuses a code says why: the HUD clears its box
	-- when it sends, so a refusal without a reply looks exactly like a game that ignored the player.
	if #code > MAX_CODE_LEN then
		RevealRemote:FireClient(plr, { redeem = "unknown" }) -- a pasted paragraph is no code of ours
		return
	end
	local prof = profiles[plr]
	if not prof then return end
	-- R4: one in-flight redeem per player (the flag), plus a cooldown (the burst). A refusal costs a reply,
	-- never an UpdateAsync, so the store is still protected from a burst.
	if prof.redeemBusy or rateLimited(prof, "Redeem") then
		RevealRemote:FireClient(plr, {
			redeem = "retry",
			message = "One code at a time: nothing was used, send it again in a moment.",
		})
		return
	end
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
	-- R3: what the RECORD already holds, captured when the code turns out to be already used.
	local syncRedeemed, syncTokens, syncTint, syncOwned = nil, nil, nil, nil
	prof.redeemBusy = true
	local ok2 = pcall(function()
		profileStore:UpdateAsync("u_" .. plr.UserId, function(old)
			old = old or {}
			applied, alreadyOnRecord, lockBlocked = false, false, false -- reset per transform attempt
			syncRedeemed, syncTokens, syncTint, syncOwned = nil, nil, nil, nil
			-- never grant through a live foreign session's lock
			local lock = old.lock
			if type(lock) == "table" and lock.token ~= prof.lockToken then
				if (nowStamp() - (tonumber(lock.at) or 0)) < Config.Save.SessionLockSeconds then
					lockBlocked = true
					return nil -- nothing changed: abort the write instead of committing a no-op
				end
			end
			old.redeemed = old.redeemed or {}
			if old.redeemed[key] then
				alreadyOnRecord = true -- genuinely used before; distinct from a failed write
				-- R3: the reward for this code is ALREADY granted on the record. Re-syncing only
				-- `redeemed` left hintTokens/tint/ownedTints stale in memory, and the very next
				-- saveProfile wrote that stale copy back — silently WIPING a reward the record
				-- says was paid out. Capture the whole reward-bearing state instead.
				syncRedeemed = old.redeemed
				syncTokens = tonumber(old.hintTokens)
				syncTint = old.tint
				syncOwned = old.ownedTints
				return nil -- nothing changed: abort the write
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

	prof.redeemBusy = false

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
		-- R3: adopt the record's full reward state, not just `redeemed`, so the next save can't
		-- overwrite a reward the record already paid out.
		if type(syncRedeemed) == "table" then
			prof.redeemed = syncRedeemed
		end
		prof.redeemed[key] = true -- keep memory in step with the record
		if syncTokens then
			prof.hintTokens = syncTokens
		end
		local recordTint = (type(syncTint) == "string" and tintIsKnown(syncTint)) and syncTint or prof.tint
		prof.ownedTints = sanitizeOwnedTints(syncOwned, recordTint)
		if prof.ownedTints[recordTint] then
			prof.tint = recordTint
		elseif not prof.ownedTints[prof.tint] then
			prof.tint = Config.DefaultTint
		end
		RevealRemote:FireClient(plr, { redeem = "already" })
		pushState(plr)
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
	local prof = profiles[plr]
	if not prof then return end
	if rateLimited(prof, "UseHint") then return end
	-- R10: the in-world prompt lives on the StartPad, so a hint has to be bought BEFORE you
	-- walk the hall — "commit, then look" is the whole cost of the mechanic. This remote let a
	-- client skip the prompt and buy the answer while standing on the decision pads at the far
	-- end, which is a strictly easier (and different) game. Enforce the prompt's own reach.
	local zone = zones[plr]
	local pad = zone and findPart(zone, "StartPad")
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not pad or not hrp or not hrp:IsA("BasePart") then return end
	if (hrp.Position - pad.Position).Magnitude > HINT_RADIUS then
		-- Say WHY, so a HUD button doesn't just look broken when pressed down the hall.
		RevealRemote:FireClient(plr, { ok = false, reason = "too_far" })
		return
	end
	useHint(plr)
end)

TintRemote.OnServerEvent:Connect(function(plr, tint)
	if typeof(tint) ~= "string" then return end
	local prof = profiles[plr]
	if not prof then return end
	-- Only allow tints the player OWNS. Ownership lives in its own persistent set: using
	-- `prof.tint` as both "owned" and "selected" meant picking the free white tint destroyed
	-- a code-earned tint forever (a one-time code can't be redeemed twice). The HUD says
	-- "Tint locked" and never sends an unowned one, so this refusal is a script's, not a player's.
	if not prof.ownedTints[tint] then
		return
	end
	if rateLimited(prof, "SetTint") then
		-- (standard §1, no silent no-ops) a second swatch tapped inside the cooldown used to vanish. It is
		-- applied when the cooldown ends instead: the LAST pick wins, and a burst still costs one push.
		local first = prof.pendingTint == nil
		prof.pendingTint = tint
		if first then
			local left = math.max(0, (REMOTE_COOLDOWN.SetTint or 0.5) - (os.clock() - (prof.remoteAt.SetTint or 0)))
			task.delay(left, function()
				local t = prof.pendingTint
				prof.pendingTint = nil
				if profiles[plr] ~= prof or t == nil or not prof.ownedTints[t] then
					return
				end
				prof.remoteAt.SetTint = os.clock()
				prof.tint = t
				pushState(plr)
			end)
		end
		return
	end
	prof.pendingTint = nil -- a pick that got through outranks one still waiting
	prof.tint = tint
	pushState(plr)
end)

-- ------------------------------------------------------------------ Lifecycle
-- SPAWN ORDER. `Player.CharacterAdded` fires while the character Model is still UNPARENTED with
-- its root at the WORLD ORIGIN; ONE FRAME LATER the engine parents it and places it, silently
-- discarding any CFrame written in between (measured in Studio 2026-09-10, robloxemu/SPAWN-ORDER.md).
-- So a handler must not write immediately — and this one used to sleep `task.wait(0.2)` instead,
-- which is not the same thing. Two problems with a sleep:
--
--   * it is a COINCIDENCE, not a rule. It beat the engine by twelve frames on the day it was
--     written; nothing ties it to the engine's step, and nothing would have noticed if the
--     number had ever been cut.
--   * it leaves the player in the WRONG PLACE for all twelve of those frames, on every spawn and
--     every respawn. This game has no SpawnLocation anywhere, and every concourse is out at
--     `index * 1000` studs with `index` starting at 1 — so the engine's own answer is the void
--     over the world origin: no floor under them, 100 studs below and >= 1000 studs west of the
--     hall they are meant to be reading. Twelve frames of falling through black, then a snap.
--
-- Wait for the thing that actually decides it. `char.Parent` becoming non-nil is the signal
-- because the engine parents and places in the SAME frame: once a parent is visible the engine
-- has finished and the next write is the last one. Bounded, so a character that never arrives
-- cannot park this handler for the session.
local SPAWN_WAIT_FRAMES = 300 -- 5 s at 60 Hz; a character that has not arrived by then never will

-- The engine's own answer (docs/complete-game-standard.md §1; SPAWN-ORDER.md §3, the preferred pattern):
-- every player gets a real, enabled SpawnLocation on their own start pad, and plr.RespawnLocation points
-- at it, so the engine itself places them in their hall and no frame is spent in the void over the
-- origin. onCharacter's teleport stays as the second net. The spawn is invisible and intangible (the
-- StartPad is what they see and stand on), gives no force-field bubble, and is NOT in the zone model:
-- the hall is rebuilt every pass and its tree must not change (check_anomaly_names).
local spawns: { [Player]: SpawnLocation } = {}

local function makeSpawn(plr: Player, origin: Vector3): SpawnLocation
	local sp = Instance.new("SpawnLocation")
	sp.Name = "Spawn_" .. plr.UserId
	sp.Anchored = true
	sp.Size = Vector3.new(6, 0.2, 6)
	sp.CFrame = CFrame.new(origin + Vector3.new(0, 1, -4)) -- exactly where buildClean puts the StartPad
	sp.Transparency = 1
	sp.CanCollide = false
	sp.CanTouch = false
	sp.CastShadow = false
	sp.Duration = 0
	sp.Neutral = true
	sp.Enabled = true
	sp.Parent = workspace
	return sp
end

local function dropSpawn(plr: Player)
	local sp = spawns[plr]
	if sp then
		sp:Destroy()
		spawns[plr] = nil
	end
end

local function onCharacter(plr: Player, char: Model)
	local frames = 0
	while char.Parent == nil and frames < SPAWN_WAIT_FRAMES do
		task.wait(1 / 60)
		frames += 1
	end
	if char.Parent == nil then
		return -- never made it into the world; there is nothing to place
	end
	-- Re-read the zone AFTER the wait: the player may have left, and their zone is destroyed on
	-- PlayerRemoving. Reading it before the yield would have teleported a corpse to a dead index.
	local zone = zones[plr]
	if zone == nil then
		return
	end
	teleportToStart(plr, zoneOrigin(tonumber(zone:GetAttribute("Index")) or 0))
end

Players.PlayerAdded:Connect(function(plr)
	-- The hall's index and the player's spawn come FIRST, before anything yields (loadProfile does): a
	-- character that loads during the yield must already have its RespawnLocation, or the engine puts it
	-- on the first enabled SpawnLocation it finds, which is someone else's hall.
	local index = acquireZoneIndex()
	spawns[plr] = makeSpawn(plr, zoneOrigin(index))
	plr.RespawnLocation = spawns[plr]

	local prof = loadProfile(plr)

	-- GHOST-SESSION GUARD. loadProfile YIELDS inside UpdateAsync. If the player left during
	-- that yield, PlayerRemoving already ran against empty tables and cleaned up nothing —
	-- so without this check we would install a profile for a player who is gone, and the
	-- autosave loop would renew their session lock every 20s (TTL 45s) for the life of the
	-- server. That locks the real player out of saving on EVERY other server, and leaks the
	-- zone + its index. Release what we took and bail instead.
	if plr.Parent ~= Players then
		if prof.canSave then
			prof.closing = true -- R7: nothing may renew this lock, only the release below
			profiles[plr] = prof
			saveProfile(plr, true) -- release the lock we just claimed
			profiles[plr] = nil
		end
		dropSpawn(plr)
		releaseZoneIndex(index)
		return
	end

	profiles[plr] = prof

	-- The saved run, if there is one (owner decision 2026-09-30): its Day and, on the first pass, its
	-- live pass. Without one this is a fresh run of this session's own.
	local run = prof.run
	local startDay = if run then run.day else Config.Progression.StartDay
	-- Whether this session saves the run: the break's idle caption promises "saved" only when it does.
	plr:SetAttribute("SavesRun", prof.canSave)

	-- leaderstats
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local day = Instance.new("IntValue"); day.Name = "Day"; day.Value = startDay; day.Parent = ls
	local best = Instance.new("IntValue"); best.Name = "Best"; best.Value = prof.bestDay; best.Parent = ls
	ls.Parent = plr

	-- private zone (index recycled from the free list, so origins never drift far out)
	local zone = Instance.new("Model")
	zone.Name = "Concourse_" .. plr.UserId
	zone:SetAttribute("Index", index)
	zone.Parent = workspace
	zones[plr] = zone
	buildBoard(plr, zoneOrigin(tonumber(zone:GetAttribute("Index")) or 0))
	task.spawn(publishGuide, plr, false) -- a profile from before the board has a count waiting
	passState[plr] = {
		day = startDay,
		clean = true,
		anomalyId = nil,
		serial = 0,
		awaiting = false,
		-- per-session salt: same sequence within this session, a different one next time
		salt = saltSource:NextInteger(0, 2147483646),
		startedAt = os.clock(),
		runId = if run then run.id else newSessionToken(),
		ownRun = run == nil,
		hinted = false,
	}

	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)

	beginPass(plr, run and run.pass)
	notifyReadOnly(plr) -- R5: say so ONCE if this session can't save
end)

Players.PlayerRemoving:Connect(function(plr)
	local leaving = profiles[plr]
	if leaving then
		-- R9: always flush the final best day, throttle or not — this is the last chance.
		publishBest(plr, true)
		publishGuide(plr, true)
		-- R7: mark CLOSED before the releasing save, so an autosave renew (in flight or about
		-- to start) can never land afterwards and re-arm the lock for a player who has left.
		leaving.closing = true
	end
	saveProfile(plr, true) -- flush + release lock
	local zone = zones[plr]
	if zone then
		releaseZoneIndex(tonumber(zone:GetAttribute("Index")) or 0)
		zone:Destroy()
	end
	local info = passInfoRoot:FindFirstChild(tostring(plr.UserId))
	if info then
		info:Destroy()
	end
	dropBoard(plr)
	dropSpawn(plr)
	profiles[plr] = nil
	zones[plr] = nil
	passState[plr] = nil
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do
		local prof = profiles[plr]
		if prof then
			publishBest(plr, true) -- R9: final flush; no-op unless the best day actually moved
			publishGuide(plr, true)
			prof.closing = true -- R7
		end
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
				local ghost = profiles[plr]
				if ghost then
					publishBest(plr, true) -- R9: final flush before we drop the profile
					publishGuide(plr, true)
					ghost.closing = true -- R7
				end
				saveProfile(plr, true)
				local zone = zones[plr]
				if zone then
					releaseZoneIndex(tonumber(zone:GetAttribute("Index")) or 0)
					zone:Destroy()
				end
				dropBoard(plr)
				dropSpawn(plr)
				profiles[plr] = nil
				zones[plr] = nil
				passState[plr] = nil
			elseif profiles[plr].canSave then
				publishGuide(plr, true) -- a count the throttle held back
				saveProfile(plr, false)
			else
				-- R1: read-only session — try to WIN the lock instead of staying mute forever.
				-- On success this adopts the freshly loaded values and starts saving; the
				-- notice is reset so the player is told saving came back.
				retryClaim(plr)
			end
		end
		refreshPublicBoards() -- the public board, re-read at most once a window, on every sign showing it
	end
end)

print("[Anomaly] Night Shift at the Observatory loaded.")
