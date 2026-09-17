-- LOST & FOUND DEPOT — server, authoritative. Lands in ServerScriptService.
--
-- Every rule comes from ReplicatedStorage.Config and the pure, unit-tested modules (Rules, Shift,
-- Seed, Economy, Codes, Layout). This file is the only one that knows Roblox exists: the modules
-- return plain tables and numbers, and here they become Parts, prompts and DataStore writes.
--
-- The loop (DESIGN.md §1): a private sorting bay. Eight lost items on a tray, each wearing a tag
-- whose letter was drawn without looking at the item. Tap an item, read its tag against the Depot
-- Manual, walk it to one of six bins, press E. The server decides every sort.
--
-- Things that are deliberate, not accidental:
--  * THE ANSWER NEVER LEAVES THIS SCRIPT. Each item's bin lives in the per-bay shift table below.
--    No attribute is written anywhere (the allowlist is empty), no Instance name, colour, tray
--    position or prompt text depends on it, and no remote carries it until the 8-second misfile
--    penalty has been paid. The cart queue (items 9-30), the seed, the per-shift salt and the cart
--    keys are server memory (the seed itself is recoverable from the visible tray; see arm()).
--  * NO REMOTE TAKES A BIN, AN ITEM, A RESULT OR A PRICE. Picks, deposits, put-backs, purchases and
--    the door are ClickDetectors and ProximityPrompts, whose Instance the engine supplies.
--  * NO HANDLER YIELDS BETWEEN ITS CHECK AND ITS STATE CHANGE, so a double trigger in one frame
--    sees the new state and is refused.
--  * NO SILENT NO-OPS. Every refused action sends a Notice saying why. The two remotes a client
--    drives (Select, Redeem) drop malformed payloads without one: the honest HUD cannot produce
--    them, so no player is left wondering (DESIGN.md §10.2).
--  * SPAWN: RespawnLocation is set in the synchronous head of PlayerAdded, AND CharacterAdded waits
--    for char.Parent and walks the character home if it landed anywhere else (SPAWN-ORDER.md).
--  * DataStoreService:GetDataStore RAISES in an unpublished place. It is pcall'd, so what degrades
--    is saving, not the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Seed = require(ReplicatedStorage:WaitForChild("Seed"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))
local Shift = require(ReplicatedStorage:WaitForChild("Shift"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Layout = require(ReplicatedStorage:WaitForChild("Layout"))
-- Server-only: the Back Room note and the code table. ServerScriptService never replicates.
local Secret = require(ServerScriptService:WaitForChild("Secret"))

-- Bright, airy, no depth of field: this game is read at 5-30 studs (DESIGN.md §13.1).
Fx.applyLighting(Fx.Presets.Temple)

local C = Config.Colors
local S = Config.Shift
local B = Config.Bay
local BIN_NAMES = Config.Rules.BinNames

-- ONE clock for the shift timer. os.clock() is CPU time in Roblox and barely moves on a quiet
-- server; GetServerTimeNow is the wall clock, tick() the fallback (and the clock robloxemu
-- advances). Probed once, at load (Fork Tower's probe).
local clock: () -> number
do
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	clock = if ok and type(t) == "number" then function()
		return (workspace :: any):GetServerTimeNow()
	end else tick
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

--============================================================================== remotes

local remotes = Instance.new("Folder")
remotes.Name = "DepotRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateEvent = remote("State") -- S -> owner: everything the HUD shows
local NoticeEvent = remote("Notice") -- S -> owner: toasts
local SceneEvent = remote("Scene") -- S -> owner, only when unlocked: the Back Room note
local SelectEvent = remote("Select") -- C -> S: which carried slot is selected
local RedeemEvent = remote("Redeem") -- C -> S: a typed code
remotes.Parent = ReplicatedStorage

-- Per player: when each limited toast text was last sent, and the toast bucket (Config.Remotes).
-- Cleared on leave.
local noticeGates: { [Player]: { tokens: number, at: number, recent: { [string]: number }, recentCount: number } } = {}

-- A client can make the server refuse something as often as it can fire an event. A refusal or an
-- info toast that repeats what is already on screen, or that comes faster than anyone reads, is
-- dropped here (REVIEW-1 pass 3, exploit finding 1). Results ("ok", "misfile", "perfect") always go.
local function noticeAllowed(plr: Player, kind: string, text: string): boolean
	if kind ~= "refused" and kind ~= "info" then
		return true
	end
	local R = Config.Remotes
	local now = clock()
	local g = noticeGates[plr]
	if g == nil then
		g = { tokens = R.NoticeBurst, at = now, recent = {}, recentCount = 0 }
		noticeGates[plr] = g
	end
	-- Two refusals alternating (an empty-hands put-back and an empty-slot pick) are each a repeat.
	local last = g.recent[text]
	if last and now - last < R.NoticeRepeatSeconds then
		return false
	end
	g.tokens = math.min(R.NoticeBurst, g.tokens + (now - g.at) * R.NoticesPerSecond)
	g.at = now
	if g.tokens < 1 then
		return false
	end
	g.tokens -= 1
	if last == nil then
		g.recentCount += 1
		if g.recentCount > 32 then -- refusal texts carry numbers; keep the table small
			g.recent, g.recentCount = {}, 1
		end
	end
	g.recent[text] = now
	return true
end

local function notice(plr: Player, kind: string, text: string, extra: { [string]: any }?)
	if not noticeAllowed(plr, kind, text) then
		return
	end
	local payload: { [string]: any } = { kind = kind, text = text }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	NoticeEvent:FireClient(plr, payload)
end

--============================================================================== persistence

type Session = {
	player: Player,
	userId: number,
	token: string,
	bayIndex: number?,
	loaded: boolean,
	profile: any,
	-- What the store held the last time this session read or wrote it. A session that does not hold
	-- the lock writes (profile - base) on top of the record, never its whole profile.
	base: any,
	canSave: boolean,
	-- Set synchronously at the head of PlayerRemoving / BindToClose. From then on only the release
	-- write may touch the record: an autosave already in flight re-checks it inside its transform.
	leaving: boolean,
	released: boolean,
	-- A write for this session is in flight (commit allows one at a time).
	writing: boolean,
	lastRedeem: number,
	redeemBusy: boolean,
	lastScene: number,
	selectPushAt: number,
	selectPushPending: boolean,
	-- The action bucket (Config.Remotes.ActionBurst / ActionsPerSecond) and when it last refilled.
	actionTokens: number,
	actionAt: number,
}

local sessions: { [Player]: Session } = {}
-- Release writes that have left and not come back; BindToClose waits for them.
local releasesInFlight = 0

local store = nil
if Config.Save.Enabled then
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then
		store = ds
	else
		warn("[Depot] datastore unavailable (" .. tostring(ds) .. ") - the game runs, progress will NOT be saved.")
	end
end

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

-- Another live session owns this record: a lock with a token that is not ours and has not expired.
-- Ownership is a per-session GUID, never a timestamp we also rewrite (checklist: session lock).
local function lockedByOther(record: any, session: Session): boolean
	local lock = record.lock
	return type(lock) == "table" and lock.token ~= session.token and (tonumber(lock.expires) or 0) > os.time()
end

-- Only string keys, only scalars and one string-keyed set: nothing for the JSON round-trip to bite.
local function snapshot(p: any)
	return {
		v = 1,
		cash = p.cash,
		cartLevel = p.cartLevel,
		shoesLevel = p.shoesLevel,
		shifts = p.shifts,
		perfects = p.perfects,
		backlog = p.backlog,
		bestPerfectSeconds = p.bestPerfectSeconds,
		endingSeen = p.endingSeen,
		redeemed = table.clone(p.redeemed),
	}
end

-- The load: read the record and take the lock if nobody else holds it. A call that RAISES is tried
-- Config.Save.Attempts times (REVIEW-1 R1-3: one transient error used to hand a veteran the
-- tutorial and 0 cash). -> profile, holdsLock, loadedFromStore
local function loadProfile(session: Session): (any, boolean, boolean)
	if store == nil then
		return Economy.defaultProfile(Config), false, false
	end
	for attempt = 1, Config.Save.Attempts do
		local data, acquired = nil, false
		local ok, err = pcall(function()
			store:UpdateAsync(key(session.userId), function(old)
				acquired = false
				old = if type(old) == "table" then old else {}
				data = Economy.sanitize(Config, old.data)
				if lockedByOther(old, session) then
					return nil -- abort: leave the holder's record exactly as it is
				end
				acquired = true
				old.lock = { token = session.token, expires = os.time() + Config.Save.SessionLockSeconds }
				return old
			end)
		end)
		if ok then
			if not acquired then
				warn("[Depot] " .. session.player.Name .. " READ-ONLY for now: another session holds the lock.")
			end
			return data or Economy.defaultProfile(Config), acquired, true
		end
		warn(string.format("[Depot] load failed for %s (attempt %d of %d): %s", session.player.Name, attempt,
			Config.Save.Attempts, tostring(err)))
		-- A call can raise after its write landed. A lock taken under the old token must never be
		-- mistaken for ours later: "ours" writes the whole profile, and this profile may be the
		-- defaults. Under a fresh token that stray lock is just another session's, and it expires.
		session.token = HttpService:GenerateGUID(false)
		if session.leaving or attempt == Config.Save.Attempts then
			break
		end
		task.wait(attempt)
	end
	return Economy.defaultProfile(Config), false, false
end

local pushState -- forward
local applyWalkSpeed -- forward

-- THE ONE WRITE PATH. Every save — autosave, shift end, the ending, the leave, BindToClose — comes
-- through here, and it decides INSIDE the transform, against the record it is about to overwrite:
--   * another live session holds the lock        -> write nothing;
--   * the lock is ours                           -> the record is our profile;
--   * the lock is free or stale (not ours)       -> the record is what the store holds PLUS what
--                                                   this session changed since `base`
--                                                   (Economy.merge), and the lock becomes ours.
-- The third case is how a session that could not take the lock at join (a crashed server's lock,
-- a rejoin during the first load, a load that raised) starts saving the moment it can, instead of
-- losing the whole session (REVIEW-1 R2-6).
--
-- `release` writes the lock away. A non-release write refuses once the session is leaving, and it
-- re-checks that inside the transform: an autosave already in flight when the player left must not
-- put the lock back after the release took it off (REVIEW-1 R1-1: 12 of 12 players came back
-- read-only after a mass leave).
--
-- -> "wrote" | "locked" | "error" | "skipped"
local function commit(session: Session, release: boolean): string
	if store == nil or not session.loaded or session.released then
		return "skipped"
	end
	if session.leaving and not release then
		return "skipped"
	end
	-- ONE WRITE PER SESSION AT A TIME. Two in flight can land out of order, and a merge has to be
	-- folded back into the live profile (below) before any later write reads it: a second write that
	-- saw "the lock is ours" before that happened would put the un-merged profile over the record.
	-- A save that finds one in flight is skipped (the next autosave, or the release, carries its
	-- state); the release waits for it.
	if session.writing then
		if not release then
			return "skipped"
		end
		local waited = 0
		while session.writing and waited < Config.Save.CloseWaitSeconds do
			task.wait(0.1)
			waited += 0.1
		end
	end
	session.writing = true
	local base = session.base
	local outcome, written, snap = "skipped", nil, nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(session.userId), function(old)
			outcome, written = "skipped", nil
			if session.leaving and not release then
				return nil
			end
			old = if type(old) == "table" then old else {}
			if lockedByOther(old, session) then
				outcome = "locked"
				return nil
			end
			-- The snapshot is taken HERE, when the write is decided, not when the request left:
			-- a snapshot taken before the yield landed after a newer one and put old data back.
			snap = snapshot(session.profile)
			local ours = type(old.lock) == "table" and old.lock.token == session.token
			local data = if ours then snap else snapshot(Economy.merge(Config, old.data, base, snap))
			old.data = data
			old.lock = if release then nil else { token = session.token, expires = os.time() + Config.Save.SessionLockSeconds }
			outcome, written = "wrote", data
			return old
		end)
	end)
	session.writing = false
	local plr = session.player
	local present = plr.Parent ~= nil and sessions[plr] == session
	if not ok then
		warn("[Depot] save failed for " .. plr.Name .. ": " .. tostring(err))
		if not session.canSave then
			-- This would have been a MERGE write, and it may have landed without us hearing back.
			-- Under the old token its lock would read as "ours" next time and the un-merged profile
			-- would overwrite the merged record; under a fresh token it is a stale lock that expires.
			session.token = HttpService:GenerateGUID(false)
		end
		return "error"
	end
	if outcome == "locked" then
		if session.canSave then
			session.canSave = false
			warn("[Depot] " .. plr.Name .. " READ-ONLY: another session holds the lock.")
			if present then
				notice(plr, "info", "Progress will not save this session.")
				pushState(plr)
			end
		end
		return "locked"
	end
	if outcome ~= "wrote" then
		return outcome
	end
	-- What changed in memory while the write was in flight rides on top of what was written.
	if written ~= snap then
		local live = Economy.merge(Config, written, snap, snapshot(session.profile))
		for k, v in live do
			session.profile[k] = v
		end
		-- A merge can change the upgrade levels under a live character (the store's own purchases,
		-- or one re-priced away): the Humanoid and the HUD follow the profile, not the other way.
		if present then
			applyWalkSpeed(plr)
			pushState(plr)
		end
	end
	session.base = written
	if release then
		session.released = true
	elseif not session.canSave then
		session.canSave = true
		if present then
			notice(plr, "info", "Progress is saving again.")
			pushState(plr)
		end
	end
	return "wrote"
end

--============================================================================== part factory

local function part(parent: Instance, className: string, name: string, size: Vector3, cf: CFrame, color: Color3,
	props: { [string]: any }?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false }

-- A decorative board with one text label on one face. CanCollide = false always: a collidable
-- board on a wall is a ledge to jump from (DESIGN.md §4.2).
--
-- ONE-SIDED. The Part is invisible and the board you see is the SurfaceGui's own opaque background,
-- which draws on its Face and only from in front of it. An opaque board part hid the tray tags, the
-- bin signs and the Back Room door from its BACK: the memo board from the spawn pad, each bin's sign
-- from a follow camera behind a player at that bin, 3288 blocked sightlines in all (REVIEW-1
-- findings 8 and 13; robloxemu check_lostfounddepot_view.luau). How it looks is on the Studio list.
local function board(parent: Instance, name: string, size: Vector3, cf: CFrame, face: Enum.NormalId, text: string,
	opts: { [string]: any }?): (BasePart, TextLabel)
	local p = part(parent, "Part", name, size, cf, rgb(C.SignBoard), DECOR)
	p.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = rgb(C.SignBoard)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = (opts and opts.font) or Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = rgb(C.SignText)
	label.TextXAlignment = (opts and opts.xAlign) or Enum.TextXAlignment.Center
	label.TextYAlignment = (opts and opts.yAlign) or Enum.TextYAlignment.Center
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return p, label
end

local function prompt(parent: Instance, name: string, action: string, object: string, keyCode: Enum.KeyCode,
	distance: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.KeyboardKeyCode = keyCode
	pp.MaxActivationDistance = distance
	pp.HoldDuration = 0
	-- The Drop prompt sits in the crate's base, inside its walls; line of sight would hide it.
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

--============================================================================== item recipes

-- Each archetype is at most 5 Parts, offset from the point the item rests on. Everything about
-- an item's look is a function of (archetype, variant) and nothing else — never of its tag or its
-- answer (asserted by the wire sweep in robloxemu/check_lostfounddepot.luau).
local V = Vector3.new
local DARK = Color3.fromRGB(35, 35, 40)
local LIGHT = Color3.fromRGB(240, 238, 232)
local STEEL = Color3.fromRGB(170, 175, 185)
local ORANGE = Color3.fromRGB(245, 150, 40)
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local FABRIC = Enum.Material.Fabric
local METAL = Enum.Material.Metal

local BUILDERS: { [string]: (Color3) -> { any } } = {
	backpack = function(c)
		return {
			{ size = V(2, 2.2, 1.2), offset = V(0, 1.1, 0), color = c, material = FABRIC },
			{ size = V(1.6, 0.9, 0.35), offset = V(0, 0.7, -0.7), color = c:Lerp(DARK, 0.35), material = FABRIC },
			{ size = V(0.25, 1.8, 0.2), offset = V(-0.6, 1.2, 0.65), color = DARK },
			{ size = V(0.25, 1.8, 0.2), offset = V(0.6, 1.2, 0.65), color = DARK },
		}
	end,
	sneaker = function(c)
		return {
			{ size = V(1, 0.3, 2.4), offset = V(0, 0.15, 0), color = LIGHT },
			{ size = V(0.9, 0.7, 1.7), offset = V(0, 0.65, 0.25), color = c },
			{ size = V(0.9, 0.45, 0.8), offset = V(0, 0.52, -0.75), color = c },
			{ size = V(0.5, 0.08, 0.9), offset = V(0, 1.02, 0.1), color = LIGHT },
		}
	end,
	cap = function(c)
		return {
			{ size = V(1.5, 1.5, 1.5), offset = V(0, 0.3, 0.1), color = c, material = FABRIC, shape = BALL },
			{ size = V(1.3, 0.12, 1), offset = V(0, 0.1, -0.85), color = c, material = FABRIC },
			{ size = V(0.25, 0.25, 0.25), offset = V(0, 1.05, 0.1), color = c:Lerp(DARK, 0.4), shape = BALL },
		}
	end,
	scarf = function(c)
		return {
			{ size = V(0.6, 0.25, 3), offset = V(0, 0.13, 0), color = c, material = FABRIC },
			{ size = V(0.62, 0.27, 0.3), offset = V(0, 0.13, 0.8), color = LIGHT, material = FABRIC },
			{ size = V(0.62, 0.27, 0.3), offset = V(0, 0.13, -0.8), color = LIGHT, material = FABRIC },
			{ size = V(0.6, 0.1, 0.25), offset = V(0, 0.05, 1.62), color = c:Lerp(DARK, 0.3), material = FABRIC },
		}
	end,
	phone = function(c)
		return {
			{ size = V(0.9, 0.14, 1.7), offset = V(0, 0.07, 0), color = c },
			{ size = V(0.78, 0.02, 1.45), offset = V(0, 0.15, 0), color = DARK, material = Enum.Material.Glass },
			{ size = V(0.15, 0.03, 0.15), offset = V(0.25, 0.16, -0.72), color = STEEL },
		}
	end,
	headphones = function(c)
		return {
			{ size = V(1.8, 0.25, 0.35), offset = V(0, 1.5, 0), color = c },
			{ size = V(0.15, 0.8, 0.2), offset = V(-0.85, 1.1, 0), color = c },
			{ size = V(0.15, 0.8, 0.2), offset = V(0.85, 1.1, 0), color = c },
			{ size = V(0.5, 0.9, 0.9), offset = V(-0.85, 0.5, 0), color = DARK, shape = CYL },
			{ size = V(0.5, 0.9, 0.9), offset = V(0.85, 0.5, 0), color = DARK, shape = CYL },
		}
	end,
	camera = function(c)
		return {
			{ size = V(1.6, 1, 0.8), offset = V(0, 0.5, 0), color = c },
			{ size = V(0.6, 0.65, 0.65), offset = V(0, 0.5, -0.65), color = DARK, shape = CYL, rot = V(0, 90, 0) },
			{ size = V(0.35, 0.2, 0.1), offset = V(-0.5, 0.8, -0.42), color = LIGHT },
			{ size = V(0.3, 0.12, 0.3), offset = V(0.5, 1.06, 0), color = DARK },
		}
	end,
	laptop = function(c)
		return {
			{ size = V(2, 0.12, 1.4), offset = V(0, 0.06, 0.2), color = c, material = METAL },
			{ size = V(1.8, 0.02, 0.7), offset = V(0, 0.13, 0.3), color = DARK },
			{ size = V(2, 1.3, 0.1), offset = V(0, 0.72, -0.55), color = c, material = METAL, rot = V(-12, 0, 0) },
			{ size = V(1.8, 1.1, 0.02), offset = V(0, 0.72, -0.49), color = DARK, material = Enum.Material.Glass, rot = V(-12, 0, 0) },
		}
	end,
	keyring = function(c)
		return {
			{ size = V(0.1, 1, 1), offset = V(0, 0.05, 0), color = STEEL, material = METAL, shape = CYL, rot = V(0, 0, 90) },
			{ size = V(0.25, 0.06, 1.1), offset = V(0.35, 0.08, 0.7), color = c, material = METAL, rot = V(0, 20, 0) },
			{ size = V(0.25, 0.06, 1.1), offset = V(-0.3, 0.12, 0.75), color = c, material = METAL, rot = V(0, -25, 0) },
			{ size = V(0.5, 0.05, 0.35), offset = V(0, 0.1, -0.7), color = c },
		}
	end,
	wallet = function(c)
		return {
			{ size = V(1.3, 0.3, 1), offset = V(0, 0.15, 0), color = c, material = Enum.Material.Leather },
			{ size = V(1.3, 0.06, 0.5), offset = V(0, 0.33, -0.25), color = c:Lerp(DARK, 0.3), material = Enum.Material.Leather },
			{ size = V(0.15, 0.08, 0.15), offset = V(0, 0.37, -0.45), color = STEEL, material = METAL },
		}
	end,
	padlock = function(c)
		return {
			{ size = V(1, 1, 0.5), offset = V(0, 0.5, 0), color = c, material = METAL },
			{ size = V(0.15, 0.7, 0.2), offset = V(-0.3, 1.3, 0), color = STEEL, material = METAL },
			{ size = V(0.15, 0.7, 0.2), offset = V(0.3, 1.3, 0), color = STEEL, material = METAL },
			{ size = V(0.75, 0.15, 0.2), offset = V(0, 1.6, 0), color = STEEL, material = METAL },
			{ size = V(0.12, 0.3, 0.05), offset = V(0, 0.45, -0.26), color = DARK },
		}
	end,
	badge = function(c)
		return {
			{ size = V(1, 0.08, 1.4), offset = V(0, 0.04, 0), color = LIGHT },
			{ size = V(0.45, 0.02, 0.55), offset = V(0, 0.09, 0.25), color = c },
			{ size = V(1, 0.02, 0.25), offset = V(0, 0.09, -0.5), color = c },
			{ size = V(0.3, 0.1, 0.2), offset = V(0, 0.08, -0.75), color = STEEL, material = METAL },
			{ size = V(0.12, 0.05, 1), offset = V(0, 0.05, -1.3), color = c, material = FABRIC },
		}
	end,
	teddy = function(c)
		return {
			{ size = V(1.3, 1.3, 1.3), offset = V(0, 0.65, 0), color = c, material = FABRIC, shape = BALL },
			{ size = V(1, 1, 1), offset = V(0, 1.55, 0), color = c, material = FABRIC, shape = BALL },
			{ size = V(0.4, 0.4, 0.4), offset = V(-0.38, 1.95, 0), color = c, material = FABRIC, shape = BALL },
			{ size = V(0.4, 0.4, 0.4), offset = V(0.38, 1.95, 0), color = c, material = FABRIC, shape = BALL },
			{ size = V(0.4, 0.4, 0.4), offset = V(0, 1.45, -0.45), color = c:Lerp(LIGHT, 0.5), material = FABRIC, shape = BALL },
		}
	end,
	toycar = function(c)
		return {
			{ size = V(1.8, 0.5, 1), offset = V(0, 0.45, 0), color = c },
			{ size = V(0.9, 0.45, 0.9), offset = V(-0.1, 0.92, 0), color = c:Lerp(LIGHT, 0.3) },
			{ size = V(1.1, 0.45, 0.45), offset = V(0.55, 0.23, 0), color = DARK, shape = CYL, rot = V(0, 90, 0) },
			{ size = V(1.1, 0.45, 0.45), offset = V(-0.55, 0.23, 0), color = DARK, shape = CYL, rot = V(0, 90, 0) },
		}
	end,
	ball = function(c)
		return {
			{ size = V(1.4, 1.4, 1.4), offset = V(0, 0.7, 0), color = c, shape = BALL },
			{ size = V(0.3, 1.42, 1.42), offset = V(0, 0.7, 0), color = LIGHT, shape = CYL },
			{ size = V(0.25, 0.25, 0.25), offset = V(0, 1.42, 0), color = LIGHT, shape = BALL },
		}
	end,
	duck = function(c)
		return {
			{ size = V(1.1, 1.1, 1.1), offset = V(0, 0.5, 0.1), color = c, shape = BALL },
			{ size = V(0.7, 0.7, 0.7), offset = V(0, 1.2, -0.3), color = c, shape = BALL },
			{ size = V(0.35, 0.15, 0.35), offset = V(0, 1.15, -0.72), color = ORANGE },
			{ size = V(0.4, 0.3, 0.3), offset = V(0, 0.8, 0.65), color = c },
		}
	end,
}

-- Startup guard: an archetype with no recipe would render as nothing at all.
do
	local missing = Shift.missingBuilders(Config, BUILDERS)
	if #missing > 0 then
		warn("[Depot] catalog items with no Part recipe: " .. table.concat(missing, ", "))
	end
end


--============================================================================== the Break Room

-- Built before any player can exist, with the one SpawnLocation that is ALWAYS enabled. Every bay
-- pad starts disabled, so before the first join there is exactly one enabled spawn and it is not a
-- roof (SPAWN-ORDER.md). A character only ever sees this room if the engine's first spawn beat
-- PlayerAdded; the re-place in onCharacter walks it home.
do
	local room = Instance.new("Folder")
	room.Name = "BreakRoom"
	local half = Config.BreakRoom.HalfSize
	local wh = Config.BreakRoom.WallHeight
	part(room, "Part", "Floor", V(2 * half + 2, 1, 2 * half + 2), CFrame.new(0, -0.5, 0), rgb(C.Floor),
		{ Material = Enum.Material.Concrete })
	part(room, "Part", "WallN", V(2 * half + 2, wh, 1), CFrame.new(0, wh / 2, -half - 0.5), rgb(C.Wall))
	part(room, "Part", "WallS", V(2 * half + 2, wh, 1), CFrame.new(0, wh / 2, half + 0.5), rgb(C.Wall))
	part(room, "Part", "WallW", V(1, wh, 2 * half), CFrame.new(-half - 0.5, wh / 2, 0), rgb(C.Wall))
	part(room, "Part", "WallE", V(1, wh, 2 * half), CFrame.new(half + 0.5, wh / 2, 0), rgb(C.Wall))
	part(room, "SpawnLocation", "StaffEntrance", V(6, 1, 6), CFrame.new(0, 0.5, 0), rgb(C.Locker),
		{ Enabled = true, Neutral = true, Duration = 0 })
	board(room, "Sign", V(12, 3, 0.4), CFrame.new(0, 8, -half + 0.2), Enum.NormalId.Back, "Finding your bay...")
	room.Parent = workspace
end

--============================================================================== the bays

local baysFolder = Instance.new("Folder")
baysFolder.Name = "Bays"
baysFolder.Parent = workspace

type Bay = { [string]: any }
local bays: { Bay } = {}

-- Forward-declared handlers, wired to each bay's prompts at build time.
local onPick, onDrop, onPutBack, onBuy, onDoor

local function buildBay(k: number): Bay
	local ox = Layout.bayOriginX(Config, k)
	local folder = Instance.new("Folder")
	folder.Name = "Bay_" .. k
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(ox + x, y, z)
	end
	local bay: Bay = { index = k, ox = ox, folder = folder, slots = {}, bins = {} }

	local wh, wt = B.WallHeight, B.WallThickness
	local wall = rgb(C.Wall)
	local depthZ = B.MaxZ - B.BackRoom.MinZ + 2 * wt -- from the front wall's outside to the Back Room's
	local midZ = (B.MaxZ + wt + B.BackRoom.MinZ - wt) / 2

	-- SHELL: the floor, five wall slabs, the lintel, the door and the Back Room's walls.
	part(folder, "Part", "Floor", V(B.MaxX - B.MinX + 2 * wt, 1, depthZ), at(0, -0.5, midZ), rgb(C.Floor),
		{ Material = Enum.Material.Concrete })
	local sideLen = B.MaxZ - B.MinZ + 2 * wt
	local sideMid = (B.MaxZ + B.MinZ) / 2
	part(folder, "Part", "WallLeft", V(wt, wh, sideLen), at(B.MinX - wt / 2, wh / 2, sideMid), wall)
	part(folder, "Part", "WallRight", V(wt, wh, sideLen), at(B.MaxX + wt / 2, wh / 2, sideMid), wall)
	part(folder, "Part", "WallFront", V(B.MaxX - B.MinX + 2 * wt, wh, wt), at(0, wh / 2, B.MaxZ + wt / 2), wall)
	local doorHalf = B.DoorWidth / 2
	local backSeg = (B.MaxX + wt) - doorHalf
	local backZ = B.MinZ - wt / 2
	part(folder, "Part", "WallBackL", V(backSeg, wh, wt), at(-(doorHalf + backSeg / 2), wh / 2, backZ), wall)
	part(folder, "Part", "WallBackR", V(backSeg, wh, wt), at(doorHalf + backSeg / 2, wh / 2, backZ), wall)
	part(folder, "Part", "Lintel", V(B.DoorWidth, wh - B.DoorHeight, wt), at(0, (wh + B.DoorHeight) / 2, backZ), wall)
	local door = part(folder, "Part", "Door", V(B.DoorWidth, B.DoorHeight, wt), at(0, B.DoorHeight / 2, backZ),
		rgb(C.Door), { Material = Enum.Material.Wood })
	bay.door = door
	bay.doorPrompt = prompt(door, "Open", "Open", "Back Room", Enum.KeyCode.E, B.DoorPromptDistance)
	-- the warm light leak the player chases
	Fx.attachGlow(door, Color3.fromRGB(255, 190, 120), 1.5, 12)

	local R = B.BackRoom
	local roomLen = B.MinZ - R.MinZ
	local roomMid = (B.MinZ - wt + R.MinZ) / 2
	part(folder, "Part", "BackRoomWallL", V(wt, wh, roomLen), at(R.MinX - wt / 2, wh / 2, roomMid), wall)
	part(folder, "Part", "BackRoomWallR", V(wt, wh, roomLen), at(R.MaxX + wt / 2, wh / 2, roomMid), wall)
	part(folder, "Part", "BackRoomWallBack", V(R.MaxX - R.MinX + 2 * wt, wh, wt), at(0, wh / 2, R.MinZ - wt / 2), wall)
	-- Not collidable: a player inside jumps 7.2, under the 14-stud roof, and nothing needs to stand on it.
	part(folder, "Part", "BackRoomRoof", V(R.MaxX - R.MinX + 2 * wt, 1, roomLen + wt), at(0, R.RoofY + 0.5, roomMid),
		wall, DECOR)

	-- FIXTURES: tray and step, six crates, the locker, the pad. No top face above 6.
	local tc, ts = B.TrayCentre, B.TraySize
	local tray = part(folder, "Part", "Tray", V(ts[1], ts[2], ts[3]), at(tc[1], tc[2], tc[3]), rgb(C.Tray),
		{ Material = Enum.Material.Wood })
	bay.tray = tray
	local trayTop = tc[2] + ts[2] / 2
	part(folder, "Part", "TrayStep", V(ts[1], B.StepHeight, ts[3] / 2), at(tc[1], trayTop + B.StepHeight / 2, B.BackRowZ),
		rgb(C.Tray):Lerp(Color3.new(0, 0, 0), 0.15), { Material = Enum.Material.Wood })
	bay.putBack = prompt(tray, "PutBack", "Put back", "Tray", Enum.KeyCode.R, B.PutBackDistance)
	-- the tray is interactive, so it reads as interactive
	Fx.attachGlow(tray, Color3.fromRGB(255, 225, 170), 0.8, 10)

	-- the eight slot hitboxes, each with its ClickDetector and its tag
	for s = 1, S.TraySlots do
		local x, z = Layout.slotXZ(Config, s)
		local e = B.SlotTile
		local hit = part(folder, "Part", "Slot_" .. s, V(e[1], e[2], e[3]), at(x, Layout.slotSurfaceY(Config, s) + e[2] / 2, z),
			rgb(C.Tray), { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = true })
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = B.ItemReach
		click.Parent = hit

		local tag = Instance.new("BillboardGui")
		tag.Name = "Tag"
		tag.Size = UDim2.fromScale(3.6, 1.3)
		tag.StudsOffset = V(0, B.TagAboveSurface - e[2] / 2, 0)
		tag.MaxDistance = B.TagMaxDistance
		-- NOT AlwaysOnTop: walls hide a neighbour's tags (Fork Tower's pile of text came from it).
		tag.AlwaysOnTop = false
		tag.LightInfluence = 0
		tag.Enabled = false
		local border = Instance.new("Frame")
		border.Name = "Border"
		border.Size = UDim2.fromScale(1, 1)
		border.BackgroundColor3 = rgb(C.TagBorder)
		border.BorderSizePixel = 0
		border.Parent = tag
		local line = Instance.new("TextLabel")
		line.Name = "TagLine"
		line.Position = UDim2.fromScale(0.03, 0.06)
		line.Size = UDim2.fromScale(0.94, 0.5)
		line.BackgroundColor3 = rgb(C.TagBackground)
		line.BackgroundTransparency = 0
		line.BorderSizePixel = 0
		line.RichText = true
		line.Font = Enum.Font.GothamBlack
		line.TextScaled = true
		line.TextColor3 = rgb(C.TagText)
		line.Text = ""
		line.Parent = tag
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Position = UDim2.fromScale(0.03, 0.56)
		nameLabel.Size = UDim2.fromScale(0.94, 0.38)
		nameLabel.BackgroundColor3 = rgb(C.TagBackground)
		nameLabel.BackgroundTransparency = 0
		nameLabel.BorderSizePixel = 0
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = rgb(C.TagText)
		nameLabel.Text = ""
		nameLabel.Parent = tag
		tag.Parent = hit

		bay.slots[s] = { part = hit, click = click, tag = tag, line = line, name = nameLabel }
		click.MouseClick:Connect(function(plr)
			onPick(bay, s, plr)
		end)
	end

	-- the six bins, named by ARC SLOT; which bin it is lives only in the sign text
	local steel = rgb(C.BinSteel)
	local P = V(ox, 0, 0)
	for arc = 1, 6 do
		local cx, cz = Layout.binCentre(Config, arc)
		local model = Instance.new("Model")
		model.Name = "Bin_" .. arc
		local frame = CFrame.lookAt(V(ox + cx, 0, cz), P) -- local -Z faces the pick point
		local bw, bh, bd = B.BinSize[1], B.BinSize[2], B.BinSize[3]
		local base = part(model, "Part", "Base", V(bw, 0.5, bd), frame * CFrame.new(0, 0.25, 0), steel,
			{ Material = Enum.Material.DiamondPlate })
		part(model, "Part", "SideFront", V(bw, bh, 0.5), frame * CFrame.new(0, bh / 2, -(bd / 2 - 0.25)), steel)
		part(model, "Part", "SideBack", V(bw, bh, 0.5), frame * CFrame.new(0, bh / 2, bd / 2 - 0.25), steel)
		part(model, "Part", "SideLeft", V(0.5, bh, bd - 1), frame * CFrame.new(-(bw / 2 - 0.25), bh / 2, 0), steel)
		part(model, "Part", "SideRight", V(0.5, bh, bd - 1), frame * CFrame.new(bw / 2 - 0.25, bh / 2, 0), steel)
		local _, label = board(model, "Sign", V(bw, 3, 0.4), frame * CFrame.new(0, bh + 2.5, bd / 2 - 0.2),
			Enum.NormalId.Front, "")
		local drop = prompt(base, "Drop", "Drop", "Bin", Enum.KeyCode.E, B.BinPromptDistance)
		drop.Enabled = false
		local light = Instance.new("PointLight")
		light.Name = "BinLight"
		light.Color = Color3.fromRGB(255, 244, 220)
		light.Brightness = B.BinLightBrightness
		light.Range = B.BinLightRange
		light.Parent = base
		local sparkle = Fx.sparkle(base, Color3.fromRGB(255, 240, 170))
		sparkle.Rate = 40
		sparkle.Enabled = false
		model.Parent = folder
		bay.bins[arc] = { model = model, base = base, prompt = drop, label = label, sparkle = sparkle }
		drop.Triggered:Connect(function(plr)
			onDrop(bay, arc, plr)
		end)
	end

	local lc, ls = B.LockerCentre, B.LockerSize
	local locker = part(folder, "Part", "Locker", V(ls[1], ls[2], ls[3]), at(lc[1], lc[2], lc[3]), rgb(C.Locker),
		{ Material = Enum.Material.Metal })
	bay.locker = locker
	bay.cartPrompt = prompt(locker, "Cart", "Upgrade", "Cart", Enum.KeyCode.E, B.LockerPromptDistance)
	bay.shoesPrompt = prompt(locker, "Shoes", "Upgrade", "Shoes", Enum.KeyCode.R, B.LockerPromptDistance)

	local pc, psz = B.PadCentre, B.PadSize
	local pad = part(folder, "SpawnLocation", "BayPad", V(psz[1], psz[2], psz[3]), at(pc[1], pc[2], pc[3]),
		rgb(C.Locker), { Enabled = false, Neutral = true, Duration = 0 })
	bay.pad = pad

	-- DECORATION: boards. All CanCollide = false.
	-- The memo board hangs on the RIGHT wall, facing the arc, opposite the manual on the left wall. It
	-- used to hang 0.8 studs behind the tray's back row, where the tags (camera-facing, 3.6 x 1.3)
	-- covered about 40% of it from the pick point and every bin stand, and where it stood in front of
	-- the bay's name sign (REVIEW-1 pass 3, player-path finding 5; check_lostfounddepot_view.luau).
	local _, memoLabel = board(folder, "MemoBoard", V(0.4, 4, 14), at(B.MaxX - 0.2, 8, -4), Enum.NormalId.Left, "",
		{ font = Enum.Font.GothamBold })
	bay.memoLabel = memoLabel
	local _, manualLabel = board(folder, "ManualBoard", V(0.4, 8, 12), at(B.MinX + 0.2, 8, 2), Enum.NormalId.Right, "",
		{ font = Enum.Font.RobotoMono, xAlign = Enum.TextXAlignment.Left, yAlign = Enum.TextYAlignment.Top })
	bay.manualLabel = manualLabel
	local _, backlogLabel = board(folder, "BacklogSign", V(10, 3, 0.4), at(0, 13, B.MinZ + 0.2), Enum.NormalId.Back, "")
	bay.backlogLabel = backlogLabel
	local _, nameSign = board(folder, "NameSign", V(14, 2.5, 0.4), at(0, 12, B.MaxZ - 0.2), Enum.NormalId.Front, "")
	bay.nameLabel = nameSign

	-- warehouse air
	Fx.dustVolume(folder, V(B.MaxX - B.MinX - 2, 14, B.MaxZ - B.MinZ - 2), at(0, 7, sideMid),
		Color3.fromRGB(235, 225, 205), 6)

	bay.cartPrompt.Triggered:Connect(function(plr)
		onBuy(bay, "cart", plr)
	end)
	bay.shoesPrompt.Triggered:Connect(function(plr)
		onBuy(bay, "shoes", plr)
	end)
	bay.putBack.Triggered:Connect(function(plr)
		onPutBack(bay, plr)
	end)
	bay.doorPrompt.Triggered:Connect(function(plr)
		onDoor(bay, plr)
	end)

	bay.owner = nil
	bay.state = "FREE"
	bay.generation = 0
	bay.carried = {}
	bay.cart = {}
	bay.slotItem = {}
	bay.slotAt = {}
	bay.where = {}
	bay.misfiled = {}
	bay.returned = {}
	bay.selected = 1
	bay.doorOpen = false

	folder.Parent = baysFolder
	return bay
end

-- max(Bay.Count, MaxPlayers): a Studio slider can never seat more players than bays (Fork Tower M5).
local BAY_POOL = math.max(B.Count, Players.MaxPlayers)
for k = 1, BAY_POOL do
	bays[k] = buildBay(k)
end

--============================================================================== bay contents

local tagTextOf -- forward

-- WHAT E DROPS, SAID WHERE E IS PRESSED. Every Drop prompt and the Put back prompt name the selected
-- carried item and its tag ("Drop Phone" over "K · 1 · BLUE"). Only a gold outline on a hotbar slot
-- used to say which item E would drop, and a player who took the item they picked first to its bin
-- misfiled 36% of deposits at carry 2 (REVIEW-1 pass 3, player-path finding 2). The name and the
-- tag are on the tray for anyone to read; neither is the answer.
local function updatePromptText(bay: Bay)
	local n = bay.shift and bay.carried[math.clamp(bay.selected, 1, math.max(1, #bay.carried))]
	for _, bin in bay.bins do
		if n then
			bin.prompt.ActionText = "Drop " .. bay.shift.items[n].name
			bin.prompt.ObjectText = (tagTextOf(bay, n))
		else
			bin.prompt.ActionText = "Drop"
			bin.prompt.ObjectText = if bin.label.Text ~= "" then bin.label.Text else "Bin"
		end
	end
	if n then
		bay.putBack.ActionText = "Put back " .. bay.shift.items[n].name
		bay.putBack.ObjectText = (tagTextOf(bay, n))
	else
		bay.putBack.ActionText = "Put back"
		bay.putBack.ObjectText = "Tray"
	end
end

local function updatePrompts(bay: Bay)
	local owned = bay.owner ~= nil
	local carrying = owned and #bay.carried > 0 and bay.state == "RUNNING"
	for _, bin in bay.bins do
		bin.prompt.Enabled = carrying
	end
	bay.putBack.Enabled = carrying
	bay.cartPrompt.Enabled = owned
	bay.shoesPrompt.Enabled = owned
	bay.doorPrompt.Enabled = owned
	updatePromptText(bay)
end

local function updateBacklogSign(bay: Bay, profile: any?)
	if profile == nil then
		bay.backlogLabel.Text = "\u{1F512} BACK ROOM"
		return
	end
	local size = Config.Economy.BacklogSize
	local lock = if profile.backlog >= size then "" else "\u{1F512} "
	bay.backlogLabel.Text = string.format("%sBACK ROOM\nBACKLOG %d / %d", lock, profile.backlog, size)
end

local function clearSlot(bay: Bay, slot: number)
	local s = bay.slots[slot]
	local item = s.part:FindFirstChild("Item")
	if item then
		item:Destroy()
	end
	s.tag.Enabled = false
	s.line.Text = ""
	s.name.Text = ""
	bay.slotItem[slot] = nil
end

tagTextOf = function(bay: Bay, n: number): (string, string)
	local item = bay.shift.items[n]
	if bay.misfiled[n] then
		local t = "MISFILED - goes to " .. BIN_NAMES[item.bin]
		return t, t
	end
	return Rules.tagText(Config, item.tag), Rules.tagRich(Config, item.tag)
end

local function setSlot(bay: Bay, slot: number, n: number)
	clearSlot(bay, slot)
	local item = bay.shift.items[n]
	local entry = Config.Catalog[item.archetype]
	local s = bay.slots[slot]
	local x, z = Layout.slotXZ(Config, slot)
	local rest = V(bay.ox + x, Layout.slotSurfaceY(Config, slot), z)
	local main = rgb(entry.colors[item.variant])
	local model = Instance.new("Model")
	model.Name = "Item"
	for _, piece in BUILDERS[entry.builder](main) do
		local p = Instance.new("Part")
		p.Name = "Piece"
		p.Anchored = true
		p.CanCollide = false
		-- The pieces ARE the tap target: the item Model's ClickDetector fires for any of them
		-- (Config.Bay.SlotTile explains why not an invisible box around them).
		p.CanQuery = true
		p.CanTouch = false
		p.Massless = true
		p.Size = piece.size
		p.Color = piece.color
		p.Material = piece.material or Enum.Material.SmoothPlastic
		if piece.shape then
			p.Shape = piece.shape
		end
		local cf = CFrame.new(rest + piece.offset)
		if piece.rot then
			cf = cf * CFrame.Angles(math.rad(piece.rot.X), math.rad(piece.rot.Y), math.rad(piece.rot.Z))
		end
		p.CFrame = cf
		p.Parent = model
	end
	model.Parent = s.part
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = B.ItemReach
	click.Parent = model
	click.MouseClick:Connect(function(plr)
		onPick(bay, slot, plr)
	end)
	local _, rich = tagTextOf(bay, n)
	s.line.Text = rich
	s.name.Text = item.name
	s.tag.Enabled = true
	bay.slotItem[slot] = n
	bay.slotAt[slot] = clock()
	bay.where[n] = "tray"
end

local function clearTray(bay: Bay)
	for slot = 1, S.TraySlots do
		clearSlot(bay, slot)
	end
end

-- AN ITEM COMING BACK (a misfile, a put-back, a reset) GOES ON THE TRAY, where the player can see it:
-- the first free slot, or, with the tray full, the slot of the item that most recently rolled in from
-- the cart, which goes back to the front of the cart and rolls in again at the next refill. The
-- returned item used to go to the front of the cart whenever the tray was full, and the 0.3 s refill
-- keeps it full: a misfiled tutorial Phone vanished (6 of 6 runs), and so did 8 of 24 misfiled and
-- put-back items in a stage-3 shift, against DESIGN.md §1's "bounces the item back to the tray"
-- (REVIEW-1 pass 3, player-path findings 1 and 3). A tutorial item is never bumped, and an item that
-- itself came back is bumped only when nothing else is left; with two tutorial items and eight
-- slots, some slot always qualifies.
local function placeInTray(bay: Bay, n: number)
	for slot = 1, S.TraySlots do
		if bay.slotItem[slot] == nil then
			setSlot(bay, slot, n)
			bay.returned[n] = true
			return
		end
	end
	local best, bestRank, bestAt = nil, math.huge, -math.huge
	for slot = 1, S.TraySlots do
		local m = bay.slotItem[slot]
		if not bay.shift.items[m].tutorial then
			local rank = if bay.returned[m] then 2 else 1
			local at = bay.slotAt[slot] or 0
			if rank < bestRank or (rank == bestRank and at > bestAt) then
				best, bestRank, bestAt = slot, rank, at
			end
		end
	end
	if best == nil then
		table.insert(bay.cart, 1, n) -- unreachable while Config.Shift.Tutorial has fewer items than the tray
		bay.where[n] = "cart"
		return
	end
	local bumped = bay.slotItem[best]
	table.insert(bay.cart, 1, bumped)
	setSlot(bay, best, n)
	bay.where[bumped] = "cart"
	bay.returned[n] = true
end

local function refillSlot(bay: Bay, slot: number)
	if bay.slotItem[slot] ~= nil or #bay.cart == 0 then
		return
	end
	local n = table.remove(bay.cart, 1)
	setSlot(bay, slot, n)
end

local function updateCrate(bay: Bay)
	local plr = bay.owner
	local char = plr and plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if #bay.carried == 0 or hrp == nil then
		if bay.crate then
			bay.crate:Destroy()
			bay.crate = nil
		end
		return
	end
	if bay.crate and bay.crate.Parent == char then
		return
	end
	if bay.crate then
		bay.crate:Destroy()
	end
	local crate = Instance.new("Part")
	crate.Name = "CarriedCrate"
	crate.Size = V(2, 1.5, 1.5)
	crate.Color = rgb(C.Tray)
	crate.Material = Enum.Material.Wood
	crate.Massless = true
	crate.Anchored = false
	crate.CanCollide = false
	crate.CanQuery = false
	crate.CanTouch = false
	crate.CFrame = (hrp :: BasePart).CFrame * CFrame.new(0, 0, -2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = crate
	weld.Parent = crate
	crate.Parent = char
	bay.crate = crate
end

-- Carried items go back to the tray: a reset, a fall, a death.
local function returnCarried(bay: Bay)
	if bay.shift == nil then
		bay.carried = {}
		return
	end
	local carried = bay.carried
	bay.carried = {}
	for _, n in carried do
		placeInTray(bay, n)
	end
	bay.selected = 1
	updateCrate(bay)
	updatePrompts(bay)
end

--============================================================================== state for the HUD

-- The tutorial's next instruction. It FOLLOWS THE SELECTION, because E deposits the selected item:
-- a "sort" hint only ever names the selected item (REVIEW-1 R2-2 — a player who tapped the Teddy
-- and then the Phone held the Phone selected while the hint said TOYS, so the tutorial's own
-- instruction was a misfile). The targets are fixed and public (DESIGN.md §7.2 step 4).
local function tutorialOf(bay: Bay)
	if bay.careerShift ~= 1 or bay.shift == nil or bay.state == "SUMMARY" then
		return nil
	end
	local function entry(n: number, step: string, hotbar: number?)
		local item = bay.shift.items[n]
		local slot = nil
		for s = 1, S.TraySlots do
			if bay.slotItem[s] == n then
				slot = s
			end
		end
		return {
			index = n,
			step = step,
			item = item.name,
			letter = item.tag.letter,
			bin = BIN_NAMES[item.bin],
			slot = slot,
			hotbar = hotbar,
		}
	end
	local function isTutorial(n: number?): boolean
		return n ~= nil and bay.shift.items[n].tutorial == true
	end
	-- 1. the selected item is a tutorial item: sort it
	local selected = bay.carried[bay.selected]
	if isTutorial(selected) then
		return entry(selected :: number, "sort")
	end
	-- 2. a tutorial item is in the hands but another is selected: select it first
	for i, n in bay.carried do
		if isTutorial(n) then
			return entry(n, "select", i)
		end
	end
	-- 3. otherwise the first tutorial item not yet sorted: pick it
	for k = 1, #S.Tutorial do
		if isTutorial(k) and bay.where[k] ~= "sorted" then
			return entry(k, "pick")
		end
	end
	return nil
end

local function stateFor(plr: Player)
	local session = sessions[plr]
	local bay = session and session.bayIndex and bays[session.bayIndex]
	if session == nil or not session.loaded then
		return { loaded = false, bayName = bay and bay.folder.Name or nil }
	end
	local p = session.profile
	local shift = nil
	if bay and bay.shift then
		local carried = {}
		for _, n in bay.carried do
			local plain, rich = tagTextOf(bay, n)
			table.insert(carried, { tag = plain, rich = rich, name = bay.shift.items[n].name, misfiled = bay.misfiled[n] == true })
		end
		local secondsLeft = S.Seconds
		if bay.state == "RUNNING" then
			secondsLeft = math.max(0, bay.endsAt - clock())
		elseif bay.state == "SUMMARY" then
			secondsLeft = 0
		end
		shift = {
			state = bay.state,
			careerShift = bay.careerShift,
			endsAt = bay.endsAt,
			serverNow = clock(),
			secondsLeft = secondsLeft,
			cleared = bay.run.sorted,
			total = S.Items,
			combo = bay.run.combo,
			misfiles = bay.run.misfiles,
			memo = if bay.shift.memo then Rules.memoLine(Config, bay.shift.memo) else nil,
			carried = carried,
			selected = bay.selected,
			tutorial = tutorialOf(bay),
			summary = bay.summary,
		}
	end
	local stage = if bay then bay.stage else 1
	return {
		loaded = true,
		bayName = bay and bay.folder.Name or nil,
		cash = p.cash,
		cartLevel = p.cartLevel,
		shoesLevel = p.shoesLevel,
		carry = Economy.carry(Config, p.cartLevel),
		walkSpeed = Economy.walkSpeed(Config, p.shoesLevel),
		prices = { cart = Economy.price(Config, p.cartLevel), shoes = Economy.price(Config, p.shoesLevel) },
		nextCarry = if p.cartLevel < Config.Economy.MaxLevel then Economy.carry(Config, p.cartLevel + 1) else nil,
		nextSpeed = if p.shoesLevel < Config.Economy.MaxLevel then Economy.walkSpeed(Config, p.shoesLevel + 1) else nil,
		stage = stage,
		newLayer = bay and bay.newLayer or nil,
		manual = if bay and bay.shift then Rules.manualSections(Config, stage, bay.shift.memo) else Rules.manualSections(Config, 1),
		shifts = p.shifts,
		perfects = p.perfects,
		best = p.bestPerfectSeconds,
		backlog = p.backlog,
		backlogSize = Config.Economy.BacklogSize,
		endingSeen = p.endingSeen,
		canSave = session.canSave,
		shift = shift,
	}
end

pushState = function(plr: Player)
	if plr.Parent == nil then
		return
	end
	StateEvent:FireClient(plr, stateFor(plr))
	local session = sessions[plr]
	local bay = session and session.bayIndex and bays[session.bayIndex]
	if bay and session.loaded then
		local p = session.profile
		local cartPrice = Economy.price(Config, p.cartLevel)
		local shoesPrice = Economy.price(Config, p.shoesLevel)
		bay.cartPrompt.ObjectText = "Cart (carry " .. Economy.carry(Config, p.cartLevel) .. ")"
		bay.cartPrompt.ActionText = if cartPrice then "Upgrade - " .. cartPrice else "Fully upgraded"
		bay.shoesPrompt.ObjectText = "Shoes (speed " .. Economy.walkSpeed(Config, p.shoesLevel) .. ")"
		bay.shoesPrompt.ActionText = if shoesPrice then "Upgrade - " .. shoesPrice else "Fully upgraded"
	end
end

applyWalkSpeed = function(plr: Player)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		return
	end
	local session = sessions[plr]
	-- Set explicitly, always: Nightwatch Manor shipped a chase tuned against a speed nobody set.
	hum.WalkSpeed = if session and session.loaded
		then Economy.walkSpeed(Config, session.profile.shoesLevel)
		else Config.Economy.WalkSpeed[1]
end

--============================================================================== the shift

local function arm(bay: Bay)
	local plr = bay.owner
	local session = plr and sessions[plr]
	if session == nil or not session.loaded then
		return
	end
	local p = session.profile
	bay.generation += 1
	clearTray(bay)
	bay.carried = {}
	bay.selected = 1

	local careerShift = p.shifts + 1
	local stage = Shift.stageFor(Config, careerShift)
	-- FRESH SERVER RANDOMNESS FOR EVERY SHIFT, never persisted, never replicated (REVIEW-1 pass 3,
	-- exploit finding 3). The tray, the bins and the memo are visible, so the one 32-bit seed they come
	-- from is recoverable (a brute force took 18 s) and so is the salt inside it. A salt kept for the
	-- whole session then predicted every later shift; it is drawn again for each one. The cart comes
	-- from two more keys the tray never touches (Seed.cartSeeds), drawn from a SEPARATE Random, so
	-- recovering the salt's generator output says nothing about them.
	local salt = Random.new():NextInteger(0, 4294967295)
	local cartRandom = Random.new()
	local k1, k2 = cartRandom:NextInteger(0, 4294967295), cartRandom:NextInteger(0, 4294967295)
	local seed = Seed.forShift(Config, plr.UserId, p.shifts, salt)
	-- Server console only, so a bug report can be replayed (seed + cart keys). It never reaches a client.
	print(string.format("[Depot] %s: shift %d, stage %d, seed %d, cart keys %d %d", plr.Name, careerShift, stage, seed, k1, k2))
	local sh = Shift.generate(Config, Rng, Rules, seed, stage, careerShift, Seed.cartSeeds(Config, k1, k2))
	bay.shift = sh
	bay.stage = stage
	bay.careerShift = careerShift
	bay.newLayer = if careerShift == Config.Rules.TornUnlockShift then 2
		elseif careerShift == Config.Rules.MemoUnlockShift then 3
		else nil
	bay.where = {}
	bay.misfiled = {}
	bay.returned = {}
	bay.slotItem = {}
	bay.slotAt = {}
	bay.cart = table.clone(sh.cart)
	for _, n in bay.cart do
		bay.where[n] = "cart"
	end
	for arc = 1, 6 do
		local name = BIN_NAMES[sh.binSlots[arc]]
		bay.bins[arc].label.Text = name
		bay.bins[arc].prompt.ObjectText = name
	end
	for slot = 1, S.TraySlots do
		setSlot(bay, slot, sh.tray[slot])
	end
	bay.memoLabel.Text = if sh.memo then "TODAY'S MEMO\n" .. Rules.memoLine(Config, sh.memo) else ""
	bay.manualLabel.Text = table.concat(Rules.manualLines(Config, stage, sh.memo), "\n")
	updateBacklogSign(bay, p)
	bay.run = Economy.newRun()
	bay.endsAt = 0
	bay.startedAt = 0
	bay.summary = nil
	bay.tutorialToasted = false
	bay.state = "ARMED"
	updateCrate(bay)
	updatePrompts(bay)
	pushState(plr)
end

local function endShift(bay: Bay, timedOut: boolean)
	local plr = bay.owner
	local session = plr and sessions[plr]
	if session == nil or bay.state ~= "RUNNING" then
		return
	end
	local p = session.profile
	local run = bay.run
	local perfect = Economy.isPerfect(Config, run.sorted, S.Items, run.misfiles, timedOut)
	local seconds = math.floor(math.max(0, clock() - bay.startedAt))
	local bonus = 0
	if perfect then
		bonus = Config.Economy.PerfectBonus
		p.cash += bonus
		p.perfects += 1
		p.bestPerfectSeconds = Economy.betterBest(p.bestPerfectSeconds, seconds)
	end
	-- A timed-out shift counts too, so a struggling player still unlocks stages (DESIGN.md §5).
	p.shifts += 1
	bay.summary = {
		sorted = run.sorted,
		total = S.Items,
		misfiles = run.misfiles,
		pay = run.pay + bonus,
		bonus = bonus,
		perfect = perfect,
		timedOut = timedOut,
		backlogGained = run.firstTry,
		seconds = seconds,
		best = p.bestPerfectSeconds,
	}
	bay.state = "SUMMARY"
	bay.generation += 1
	-- What was left on the tray and in the hands belongs to the finished shift.
	bay.carried = {}
	bay.cart = {}
	clearTray(bay)
	updateCrate(bay)
	updatePrompts(bay)
	if perfect then
		notice(plr, "perfect", "\u{2605} PERFECT SHIFT \u{2605}  +" .. bonus)
	elseif timedOut then
		notice(plr, "info", string.format("Time! %d of %d sorted.", run.sorted, S.Items))
	else
		notice(plr, "info", string.format("Shift cleared: %d of %d, %d misfiles.", run.sorted, S.Items, run.misfiles))
	end
	pushState(plr)
	task.spawn(commit, session, false)

	local gen = bay.generation
	task.delay(S.IntermissionSeconds, function()
		if bay.generation == gen and bay.owner == plr and bay.state == "SUMMARY" then
			arm(bay)
		end
	end)
end

--============================================================================== handlers

local STATE_REFUSAL = {
	LOADING = "Unpacking your cart...",
	SUMMARY = "Shift over - the next cart is rolling in.",
	FREE = "That's someone else's bay.",
}

-- The five checks every in-world handler makes, in this order, with no yield anywhere near them:
-- owner, profile loaded, state, alive with a root part, within reach (+ ReachSlack). Returns the
-- session, or nil after telling the player why.
local function admit(bay: Bay, plr: Player, target: Vector3, reach: number, tooFar: string,
	allowed: { [string]: boolean }): Session?
	if bay.owner ~= plr then
		notice(plr, "refused", "That's someone else's bay.")
		return nil
	end
	local session = sessions[plr]
	if session == nil or not session.loaded then
		notice(plr, "refused", "Unpacking your cart...")
		return nil
	end
	if not allowed[bay.state] then
		notice(plr, "refused", STATE_REFUSAL[bay.state] or "Not right now.")
		return nil
	end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- The clock is checked HERE, not only by the 0.25 s poll: a deposit that lands between zero and
	-- the next poll used to pay, and could even complete a Perfect Shift after time ran out.
	if bay.state == "RUNNING" and clock() >= bay.endsAt then
		endShift(bay, true) -- tells the player "Time!"
		return nil
	end
	if hum == nil or hum.Health <= 0 or hrp == nil then
		notice(plr, "refused", "You need to be on your feet for that.")
		return nil
	end
	if ((hrp :: BasePart).Position - target).Magnitude > reach + B.ReachSlack then
		notice(plr, "refused", tooFar)
		return nil
	end
	return session
end

-- One token per accepted state change (Config.Remotes.ActionBurst / ActionsPerSecond). Checked AFTER
-- every other refusal, immediately before the state change, so a refused event spends nothing and
-- the "no yield between check and change" rule still holds. -> true when the action may go ahead;
-- otherwise the player has been told to slow down (once: the toast gate drops the repeats).
local SLOW_DOWN = "Slow down - one thing at a time."
local function spendAction(session: Session): boolean
	local R = Config.Remotes
	local now = clock()
	session.actionTokens = math.min(R.ActionBurst, session.actionTokens + (now - session.actionAt) * R.ActionsPerSecond)
	session.actionAt = now
	if session.actionTokens < 1 then
		notice(session.player, "refused", SLOW_DOWN)
		return false
	end
	session.actionTokens -= 1
	return true
end

local PLAYING = { ARMED = true, RUNNING = true }
local ANY_LOADED = { ARMED = true, RUNNING = true, SUMMARY = true }

onPick = function(bay: Bay, slot: number, plr: Player)
	local s = bay.slots[slot]
	local session = admit(bay, plr, s.part.Position, B.ItemReach, "Too far - walk up to the tray.", PLAYING)
	if session == nil then
		return
	end
	local n = bay.slotItem[slot]
	if n == nil then
		local last = bay.lastPick
		if last and last.slot == slot and last.by == plr and clock() - last.at < B.SamePickSeconds then
			-- The same tap, reported twice (a double tap, or both the item's and the tile's
			-- ClickDetector). The first report already answered it: the item is in their hands.
			return
		end
		notice(plr, "refused", if #bay.cart > 0 then "The cart is still rolling the next item in."
			else "That spot on the tray is empty.")
		return
	end
	local carry = Economy.carry(Config, session.profile.cartLevel)
	if #bay.carried >= carry then
		notice(plr, "refused", string.format("Hands full (%d/%d). Drop something in a bin first.", #bay.carried, carry))
		return
	end
	if not spendAction(session) then
		return
	end
	-- the state change, in single assignments
	clearSlot(bay, slot)
	bay.lastPick = { slot = slot, by = plr, at = clock() }
	bay.where[n] = "carried"
	bay.returned[n] = nil
	table.insert(bay.carried, n)
	-- A pick does NOT move the selection: E drops the item in the first hotbar slot unless the player
	-- taps another, and a deposit or a put-back selects the first again. A pick used to select the
	-- new item while a deposit selected the first, so neither "the one I picked first" nor "the one I
	-- picked last" was reliably what E dropped (REVIEW-1 pass 3, player-path finding 2).
	if bay.state == "ARMED" then
		bay.state = "RUNNING"
		bay.startedAt = clock()
		bay.endsAt = bay.startedAt + S.Seconds
	end
	local gen = bay.generation
	task.delay(S.RefillSeconds, function()
		if bay.generation == gen and bay.state == "RUNNING" then
			refillSlot(bay, slot)
		end
	end)
	updateCrate(bay)
	updatePrompts(bay)
	pushState(plr)
end

onDrop = function(bay: Bay, arc: number, plr: Player)
	local bin = bay.bins[arc]
	local session = admit(bay, plr, bin.base.Position, B.BinPromptDistance, "Too far - walk up to the bin.", PLAYING)
	if session == nil then
		return
	end
	if #bay.carried == 0 then
		notice(plr, "refused", "Your hands are empty. Pick an item from the tray.")
		return
	end
	if not spendAction(session) then
		return
	end
	local p = session.profile
	local idx = math.clamp(bay.selected, 1, #bay.carried)
	local n = table.remove(bay.carried, idx)
	local item = bay.shift.items[n]
	local correct = bay.shift.binSlots[arc] == item.bin
	local firstTry = not bay.misfiled[n]
	local run, pay, backlogGain = Economy.deposit(Config, bay.run, correct, firstTry)
	bay.run = run
	bay.selected = 1
	if correct then
		bay.where[n] = "sorted"
		p.cash += pay
		p.backlog = math.min(Config.Economy.BacklogSize, p.backlog + backlogGain)
		notice(plr, "ok", "+" .. pay, { amount = pay, firstTry = firstTry })
		bin.sparkle.Enabled = true
		task.delay(0.35, function()
			bin.sparkle.Enabled = false
		end)
	else
		bay.misfiled[n] = true
		bay.endsAt -= S.MisfilePenalty
		placeInTray(bay, n)
		notice(plr, "misfile", "-" .. S.MisfilePenalty .. " s. " .. item.name .. ": " .. Rules.explain(Config, item.tag,
			item.own, bay.shift.rules, item.name))
	end
	updateBacklogSign(bay, p)
	updateCrate(bay)
	updatePrompts(bay)

	if bay.careerShift == 1 and not bay.tutorialToasted then
		local done = true
		for k = 1, #S.Tutorial do
			if bay.where[k] ~= "sorted" then
				done = false
			end
		end
		if done then
			bay.tutorialToasted = true
			-- its own kind: the HUD pulses the MANUAL button it names (DESIGN.md §12)
			notice(plr, "tutorial", "Tags beat looks. The rest is up to you - every rule is in MANUAL.")
		end
	end

	if run.sorted >= S.Items then
		endShift(bay, false)
		return
	end
	if clock() >= bay.endsAt then
		endShift(bay, true)
		return
	end
	pushState(plr)
end

onPutBack = function(bay: Bay, plr: Player)
	local session = admit(bay, plr, bay.tray.Position, B.PutBackDistance, "Too far - walk up to the tray.", PLAYING)
	if session == nil then
		return
	end
	if #bay.carried == 0 then
		notice(plr, "refused", "Your hands are empty.")
		return
	end
	if not spendAction(session) then
		return
	end
	local n = table.remove(bay.carried, math.clamp(bay.selected, 1, #bay.carried))
	placeInTray(bay, n)
	bay.selected = 1
	updateCrate(bay)
	updatePrompts(bay)
	pushState(plr)
end

onBuy = function(bay: Bay, track: string, plr: Player)
	local session = admit(bay, plr, bay.locker.Position, B.LockerPromptDistance, "Too far - walk up to the locker.",
		ANY_LOADED)
	if session == nil then
		return
	end
	local p = session.profile
	-- A session that is not saving may be showing a balance the store no longer holds (a server hop
	-- whose load landed before the old server's release). Buying on it spent the same cash twice
	-- (REVIEW-1 pass 3, exploit finding 2). It is refused until this session holds the lock, which
	-- the next autosave takes the moment the other session lets go.
	if store ~= nil and not session.canSave then
		notice(plr, "refused", "Upgrades wait until your progress is saving. Try again in a moment.")
		return
	end
	local ok, res, price = Economy.buy(Config, p, track)
	if not ok then
		if res == "max" then
			notice(plr, "refused", if track == "cart" then "Your cart is fully upgraded." else "Your shoes are fully upgraded.")
		elseif res == "cash" then
			local what = if track == "cart"
				then string.format("Cart (carry %d)", Economy.carry(Config, p.cartLevel + 1))
				else string.format("Shoes (speed %d)", Economy.walkSpeed(Config, p.shoesLevel + 1))
			notice(plr, "refused", string.format("%s costs %d. You have %d.", what, price :: number, p.cash))
		else
			notice(plr, "refused", "That is not for sale.")
		end
		return
	end
	if not spendAction(session) then
		return
	end
	p.cash = res.cash
	p.cartLevel = res.cartLevel
	p.shoesLevel = res.shoesLevel
	if track == "shoes" then
		applyWalkSpeed(plr)
		notice(plr, "ok", string.format("Shoes upgraded: walk speed %d.", Economy.walkSpeed(Config, p.shoesLevel)))
	else
		notice(plr, "ok", string.format("Cart upgraded: carry %d.", Economy.carry(Config, p.cartLevel)))
	end
	pushState(plr)
end

local function buildBackRoomProps(bay: Bay)
	local old = bay.folder:FindFirstChild("BackRoomProps")
	if old then
		old:Destroy()
	end
	local props = Instance.new("Folder")
	props.Name = "BackRoomProps"
	-- An empty shelf inside and a brass key on a hook beside the door. No text on either: other
	-- players' clients can see these, and only the owner's client receives the note.
	part(props, "Part", "Shelf", V(8, 5, 1.5), CFrame.new(bay.ox, 2.5, B.BackRoom.MinZ + 1), rgb(C.Tray),
		{ CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Wood })
	part(props, "Part", "Key", V(0.4, 1.2, 0.2), CFrame.new(bay.ox + B.DoorWidth / 2 + 1.5, 6, B.MinZ + 0.3),
		rgb(C.Brass), { CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Metal })
	props.Parent = bay.folder
end

onDoor = function(bay: Bay, plr: Player)
	local session = admit(bay, plr, bay.door.Position, B.DoorPromptDistance, "Too far - walk up to the door.", ANY_LOADED)
	if session == nil then
		return
	end
	local p = session.profile
	local size = Config.Economy.BacklogSize
	if p.backlog < size then
		notice(plr, "refused", string.format("Locked. Backlog: %d / %d.", p.backlog, size))
		return
	end
	if not bay.doorOpen then
		bay.doorOpen = true
		bay.door.CanCollide = false
		bay.door.Transparency = 1
		buildBackRoomProps(bay)
	end
	-- REVIEW-1 R1-4: every press was a DataStore write and a full note payload, so a client could
	-- spend the whole server's DataStore budget from one doorway. The ending is written once, when
	-- it is first seen; the note is re-sent at most once per SceneCooldownSeconds.
	local now = clock()
	if now - session.lastScene < B.SceneCooldownSeconds then
		notice(plr, "info", "The Back Room is open.")
		return
	end
	session.lastScene = now
	local firstTime = not p.endingSeen
	p.endingSeen = true
	-- To THIS player only. The camera path is public geometry (the door is visible to anyone).
	SceneEvent:FireClient(plr, {
		lines = table.clone(Secret.Note),
		camFrom = { bay.ox, 7, B.MinZ + 12 },
		camTo = { bay.ox, 5, B.BackRoom.MinZ + 3 },
	})
	pushState(plr)
	if firstTime then
		task.spawn(commit, session, false)
	end
end

--============================================================================== players

local function claimBay(): number?
	for k = 1, #bays do
		if bays[k].owner == nil then
			return k
		end
	end
	return nil
end

local function freeBay(bay: Bay)
	bay.generation += 1
	bay.owner = nil
	bay.state = "FREE"
	clearTray(bay)
	bay.carried = {}
	bay.cart = {}
	bay.shift = nil
	bay.run = nil
	bay.summary = nil
	if bay.crate then
		bay.crate:Destroy()
		bay.crate = nil
	end
	bay.pad.Enabled = false
	bay.nameLabel.Text = ""
	bay.memoLabel.Text = ""
	bay.manualLabel.Text = ""
	updateBacklogSign(bay, nil)
	for _, bin in bay.bins do
		bin.label.Text = ""
		bin.prompt.ObjectText = "Bin"
	end
	bay.doorOpen = false
	bay.door.CanCollide = true
	bay.door.Transparency = 0
	local props = bay.folder:FindFirstChild("BackRoomProps")
	if props then
		props:Destroy()
	end
	updatePrompts(bay)
end

local function displayName(plr: Player): string
	local ok, dn = pcall(function()
		return plr.DisplayName
	end)
	if ok and type(dn) == "string" and dn ~= "" then
		return dn
	end
	return plr.Name
end

local function onCharacter(plr: Player, char: Model)
	local session = sessions[plr]
	local bay = session and session.bayIndex and bays[session.bayIndex]
	if bay and #bay.carried > 0 then
		returnCarried(bay)
		pushState(plr)
	end

	-- THE ENGINE PLACES THE CHARACTER AFTER CharacterAdded, AND THE ENGINE WINS (SPAWN-ORDER.md).
	-- RespawnLocation should already have put it on its own pad; if the engine's first spawn beat
	-- PlayerAdded, it is in the Break Room or on another pad, and this brings it home. Bounded: a
	-- character that never arrives must not park this thread for the session.
	local frames = 0
	while char.Parent == nil and frames < B.CharacterWaitFrames do
		task.wait(1 / 60)
		frames += 1
	end
	-- re-read across the yield: the player may have left
	session = sessions[plr]
	bay = session and session.bayIndex and bays[session.bayIndex]
	if bay == nil or plr.Character ~= char or char.Parent == nil then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local pos = hrp.Position
		if not Layout.inside(Config, pos.X - bay.ox, pos.Y, pos.Z) then
			local top = bay.pad.Position + V(0, bay.pad.Size.Y / 2 + B.PlaceAbovePad, 0)
			hrp.CFrame = CFrame.lookAt(top, top + V(0, 0, -1))
		end
	end
	applyWalkSpeed(plr)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			local s = sessions[plr]
			local b = s and s.bayIndex and bays[s.bayIndex]
			if b and plr.Character == char and #b.carried > 0 then
				returnCarried(b)
				pushState(plr)
			end
		end)
	end
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then
		return
	end
	-- 1. THE SYNCHRONOUS HEAD. Nothing above the load may yield: RespawnLocation has to be in place
	-- before the engine's first spawn of this player, and two players joining in one frame must
	-- claim different bays.
	local idx = claimBay()
	local session: Session = {
		player = plr,
		userId = plr.UserId,
		token = HttpService:GenerateGUID(false),
		bayIndex = idx,
		loaded = false,
		profile = nil,
		base = nil,
		canSave = false,
		leaving = false,
		released = false,
		writing = false,
		lastRedeem = -math.huge,
		redeemBusy = false,
		lastScene = -math.huge,
		selectPushAt = -math.huge,
		selectPushPending = false,
		actionTokens = Config.Remotes.ActionBurst,
		actionAt = clock(),
	}
	sessions[plr] = session
	local bay = idx and bays[idx]
	if bay then
		bay.owner = plr
		bay.state = "LOADING"
		bay.pad.Enabled = true
		plr.RespawnLocation = bay.pad
		bay.nameLabel.Text = string.upper(displayName(plr)) .. "'S BAY"
		bay.memoLabel.Text = "Unpacking your cart..."
		updatePrompts(bay)
	end
	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end
	if bay == nil then
		warn("[Depot] no free bay for " .. plr.Name .. " (pool " .. #bays .. ")")
		notice(plr, "refused", "Every bay is taken right now. Try another server.")
		return
	end
	pushState(plr)

	-- 2. THE LOAD. Yields on UpdateAsync in Roblox; leaving during it is common.
	local profile, canSave = loadProfile(session)
	if session.leaving or plr.Parent == nil or sessions[plr] ~= session then
		if canSave and store then
			-- we took the lock for someone who is gone; give it back without touching their data
			pcall(function()
				store:UpdateAsync(key(session.userId), function(old)
					if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.token ~= session.token then
						return nil
					end
					old.lock = nil
					return old
				end)
			end)
		end
		return
	end
	session.profile = profile
	-- The delta a read-only session writes later is measured from what it loaded (defaults, when
	-- the load failed: then everything it earns is new).
	session.base = snapshot(profile)
	session.canSave = canSave
	session.loaded = true
	if not canSave then
		notice(plr, "info", "Progress will not save this session.")
	end
	applyWalkSpeed(plr)
	arm(bay)
end

local function onPlayerRemoving(plr: Player)
	local session = sessions[plr]
	if session == nil then
		return
	end
	-- EVERYTHING BEFORE THE FIRST YIELD, and in this order:
	--  * `leaving` first: an autosave already in flight re-checks it inside its transform and backs
	--    off, so it cannot put the lock back after the release below takes it off (REVIEW-1 R1-1).
	--  * the bay is freed at once, like the seat. It used to wait for the release save, and a
	--    newcomer who joined in that window got no bay at all (REVIEW-1 R1-2). Freeing it also
	--    discards the unfinished shift here, so a clock that runs out during the save cannot count
	--    it as played.
	session.leaving = true
	sessions[plr] = nil
	noticeGates[plr] = nil
	local bay = session.bayIndex and bays[session.bayIndex]
	if bay and bay.owner == plr then
		freeBay(bay)
	end
	-- Every sort already made keeps its cash and backlog.
	if session.loaded and store ~= nil then
		releasesInFlight += 1
		for attempt = 1, Config.Save.Attempts do
			local outcome = commit(session, true)
			if outcome ~= "error" then
				break
			end
			if attempt < Config.Save.Attempts then
				task.wait(attempt)
			end
		end
		releasesInFlight -= 1
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

--============================================================================== client remotes

SelectEvent.OnServerEvent:Connect(function(plr: Player, slot: any)
	local session = sessions[plr]
	local bay = session and session.loaded and session.bayIndex and bays[session.bayIndex]
	if not bay or bay.owner ~= plr then
		return
	end
	-- An integer in 1..#carried, or dropped. NaN fails `slot == slot`; infinities fail `% 1 == 0`.
	if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > #bay.carried then
		return
	end
	if bay.selected == slot then
		return
	end
	bay.selected = slot
	-- REVIEW-1 R1-5: one full State payload per event let a client make the server encode and send
	-- 14.4 MB in one frame. The selection applies at once (a deposit uses it immediately); the
	-- payload that shows it goes out at most once per SelectPushSeconds, and always carries the
	-- latest selection.
	-- The prompts' text is world state that replicates to everyone, so it rides on the same throttle.
	local now = clock()
	if now - session.selectPushAt >= Config.Remotes.SelectPushSeconds then
		session.selectPushAt = now
		updatePromptText(bay)
		pushState(plr)
	elseif not session.selectPushPending then
		session.selectPushPending = true
		task.delay(Config.Remotes.SelectPushSeconds, function()
			session.selectPushPending = false
			session.selectPushAt = clock()
			if sessions[plr] == session and bay.owner == plr then
				updatePromptText(bay)
				pushState(plr)
			end
		end)
	end
end)

RedeemEvent.OnServerEvent:Connect(function(plr: Player, raw: any)
	local session = sessions[plr]
	if session == nil or not session.loaded then
		return
	end
	if type(raw) ~= "string" or #raw > Config.Codes.MaxLength then
		return
	end
	local now = clock()
	if session.redeemBusy or now - session.lastRedeem < Config.Codes.RedeemCooldown then
		notice(plr, "refused", "One code at a time - try again in a moment.")
		return
	end
	session.lastRedeem = now
	local p = session.profile
	local res = Codes.redeem(Config, raw, p.redeemed, Secret.Codes)
	if not res.ok then
		local text = if res.reason == "already" then "You already redeemed " .. tostring(res.code) .. "."
			elseif res.reason == "unknown" then "That code does not exist."
			else "Type a code first."
		notice(plr, "refused", text)
		return
	end
	if store == nil or not session.canSave then
		notice(plr, "refused", "Codes need saving, and progress is not saving this session.")
		return
	end
	-- ONE atomic write: the cash and the redeemed mark land together or not at all. The grant is
	-- applied in memory only after the write succeeds, so a failed write has nothing to roll back
	-- and the code stays redeemable (checklist: one-time rewards).
	session.redeemBusy = true
	local granted = false
	local written = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			granted, written = false, nil
			old = if type(old) == "table" then old else {}
			-- Only while we hold the lock: a code grant is the one write that must never merge.
			if type(old.lock) ~= "table" or old.lock.token ~= session.token or session.leaving then
				return nil
			end
			if Economy.sanitize(Config, old.data).redeemed[res.code :: string] then
				return nil
			end
			local snap = snapshot(p)
			snap.cash += res.cash :: number
			snap.redeemed[res.code :: string] = true
			old.data = snap
			old.lock = { token = session.token, expires = os.time() + Config.Save.SessionLockSeconds }
			granted, written = true, snap
			return old
		end)
	end)
	session.redeemBusy = false
	if sessions[plr] ~= session then
		return
	end
	if ok and granted then
		p.cash += res.cash :: number
		p.redeemed[res.code :: string] = true
		session.base = written
		notice(plr, "ok", "+" .. tostring(res.cash) .. " cash from " .. tostring(res.code) .. ".")
		pushState(plr)
	else
		if not ok then
			warn("[Depot] redeem write failed for " .. plr.Name .. ": " .. tostring(err))
		end
		notice(plr, "refused", "That code could not be saved right now, so nothing was granted. Try again.")
	end
end)

--============================================================================== loops

-- The shift clock: a shift ends within a quarter second of zero.
task.spawn(function()
	while true do
		task.wait(S.TimerPoll)
		local now = clock()
		for _, bay in bays do
			if bay.state == "RUNNING" and now >= bay.endsAt then
				local ok, err = pcall(endShift, bay, true)
				if not ok then
					warn("[Depot] ending a shift failed: " .. tostring(err))
				end
			end
		end
	end
end)

-- Autosave, which also renews the session lock — and, for a session that does not hold the lock
-- yet, tries to take it (commit decides against the record itself; a live lock elsewhere is left
-- alone).
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, session in table.clone(sessions) do
			if session.loaded and not session.leaving then
				task.spawn(commit, session, false)
			end
		end
	end
end)

game:BindToClose(function()
	for plr, session in table.clone(sessions) do
		session.leaving = true
		sessions[plr] = nil
		if session.loaded then
			releasesInFlight += 1
			task.spawn(function()
				commit(session, true)
				releasesInFlight -= 1
			end)
		end
	end
	-- Releases started here, or by PlayerRemoving moments earlier, may still be in flight; the
	-- server closes when this function returns.
	local waited = 0
	while releasesInFlight > 0 and waited < Config.Save.CloseWaitSeconds do
		task.wait(0.25)
		waited += 0.25
	end
end)

print(string.format("[Depot] Lost & Found Depot loaded: %d bays, WorldSeed %d", #bays, Config.WorldSeed))
