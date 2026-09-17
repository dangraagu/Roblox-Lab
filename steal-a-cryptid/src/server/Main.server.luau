-- STEAL A CRYPTID - the server. Authoritative. Lives in ServerScriptService.
--
-- This file owns the engine: Instances, positions, remotes, the DataStore. Every rule lives in a
-- pure module in ReplicatedStorage, unit-tested from the luau CLI without Roblox:
--   Economy       prices, jars, cages, heat, permits, bounties, the saved profile's shape
--   Offers        the three Sighting pedestals
--   Layout        the yard grid: lairs, Rival Camps, reachability, trap placement, danger areas
--   Heist         laser timing and the continuous catch test
--   Trace2D       the trusted position a raid is judged on
--   Poacher       the NPC that walks your yard
--   CryptidModel  the eight procedural Part models
-- DESIGN.md is the spec; the section numbers in comments below point into it.
--
-- Every require is an INSTANCE require. A bare `require("./X")` resolves in the luau CLI and is
-- invalid in Roblox; that mistake once made a server in this repo fail to load with every unit
-- test green.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Offers = require(ReplicatedStorage:WaitForChild("Offers"))
local Layout = require(ReplicatedStorage:WaitForChild("Layout"))
local Heist = require(ReplicatedStorage:WaitForChild("Heist"))
local Trace2D = require(ReplicatedStorage:WaitForChild("Trace2D"))
local Poacher = require(ReplicatedStorage:WaitForChild("Poacher"))
local CryptidModel = require(ReplicatedStorage:WaitForChild("CryptidModel"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

local W = Config.World
local RAID = Config.Raid

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function flat(a: Vector3, b: Vector3): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

--============================================================================ lighting (first thing)

-- [13] Fx.Presets.Horror with four overrides, held in Config as plain data so Fx.luau stays
-- byte-identical to its siblings. Colours and the Technology enum are converted here.
local function lightingPreset()
	local function conv(src)
		local out = {}
		for k, v in src do
			out[k] = if type(v) == "table" then rgb(v) else v
		end
		return out
	end
	local L = conv(Config.Lighting.lighting)
	L.Technology = Enum.Technology[Config.Lighting.lighting.Technology]
	return {
		lighting = L,
		atmosphere = conv(Config.Lighting.atmosphere),
		bloom = conv(Config.Lighting.bloom),
		colorCorrection = conv(Config.Lighting.colorCorrection),
	}
end
Fx.applyLighting(lightingPreset())

--============================================================================ remotes

local remotes = Instance.new("Folder")
remotes.Name = "CryptidRemotes"
local function mk(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateEvent = mk("State") -- server -> owner: the owner's present, never the future
local ToastEvent = mk("Toast") -- server -> owner: one line
local FxEvent = mk("Fx") -- server -> owner: camera juice and panel openers
local HuntEvent = mk("Hunt") -- client -> server: Hunt(tier)
local LeaveEvent = mk("LeaveCamp")
local RerollEvent = mk("Reroll")
local ExpandEvent = mk("Expand")
local BuildEvent = mk("BuildMode")
local TrapEvent = mk("TrapAction")
remotes.Parent = ReplicatedStorage

local function toast(plr: Player, text: string)
	ToastEvent:FireClient(plr, text)
end

-- [7] Drawn once, never leaves the server: laser phases, offers and poachers cannot be predicted
-- across sessions or rejoins.
local sessionSalt = Random.new():NextInteger(0, 2147483646)
-- Every camp's seed is its own draw from this server-only stream (REVIEW-1.md A2). DESIGN.md's
-- (salt + raidSerial x 2654435761) made each seed the last one plus a constant: one camp's seed,
-- recovered from its sign and layout by brute force, gave every later camp on the server, prize and
-- laser phases included, before its permit was paid.
local campRandom = Random.new()

--============================================================================ data

-- GetDataStore RAISES in an unpublished place. Unwrapped, that kills this script at load: no
-- world, no remotes, no game. Saving is what degrades, never the game.
local store = nil
if Config.Save.Enabled then
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then
		store = ds
	else
		warn("[Cryptid] datastore unavailable (" .. tostring(ds) .. ") - the game runs, progress will NOT be saved this session.")
	end
end

local NOT_SAVING = "Not saving this session"
local LOCKED = "Not saving: your save is open on another server. Rejoin in 2 minutes"
local LOAD_FAILED = "Your save could not be loaded, so nothing is saved this session. Rejoin to try again"
local LOCK_WAITING = "Your save is still open on another server - waiting for it to close"
local LOCK_CHANGED = "Not saving: your save changed on another server. Rejoin to load it"
local LOCK_TAKEN = "Your save is free again - this session is saving now"

local sessions: { [Player]: any } = {}

local function key(plr: Player): string
	return "u_" .. plr.UserId
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepCopy(x) end
	return out
end

-- EXACTLY the fields a flush writes, as one comparable string. A profile whose fingerprint has not
-- moved since the last successful write has nothing to save.
local function fingerprint(p: any): string
	local cages = {}
	for i = 1, 9 do cages[i] = p.cages[i].sp .. "=" .. string.format("%.1f", p.cages[i].jar) end
	return table.concat({
		string.format("%.2f", p.essence), tostring(p.cagesUnlocked), table.concat(cages, ","),
		table.concat(p.traps, ","), string.format("%d,%d,%d,%d", p.heat.t1, p.heat.t2, p.heat.t3, p.heat.t4),
		table.concat(p.journal, ","), tostring(p.tutorial),
		string.format("%d,%d,%d", p.stats.steals, p.stats.caught, p.stats.poachersCaught),
	}, "|")
end

-- [8] Soft session lock on game.JobId, a STABLE per-session token. A profile another server still
-- holds is played in memory and never written.
--
-- A DataStore call can fail for a moment and succeed the next (REVIEW-1: ONE failed UpdateAsync at
-- join used to hand a veteran a blank 30-Essence lair for the whole session). So the load is
-- tried Save.LoadAttempts times, waiting LoadRetrySeconds x attempt between tries, and only then
-- does the session fall back to a non-saving one, with a banner that says the save was not read.
--
-- A LOCK is waited for too (REVIEW-1.md A1). A player who rejoins quickly, or reconnects after a drop,
-- usually finds the old server's lock still on the record for the few seconds its leave-write takes;
-- the lock was read once at join, so a lock that cleared one second later cost the whole session
-- (603 s of play, 17 877 Essence, never saved). The load re-reads the record every LockRetrySeconds
-- for up to LockWaitSeconds, telling the player once, before it plays unsaved. The fourth return is
-- the saved data exactly as read (a deep copy), for the session's later re-check of the lock.
local function loadProfile(plr: Player): (any, boolean, string?, any)
	if not store then
		return Economy.defaultProfile(Config), false, NOT_SAVING, nil
	end
	local failures, waited = 0, 0
	while true do
		local raw, locked = nil, false
		local ok, err = pcall(function()
			store:UpdateAsync(key(plr), function(old)
				old = old or {}
				local now = os.time()
				raw = old.data
				locked = old.jobId ~= nil and old.jobId ~= game.JobId and (tonumber(old.lockUntil) or 0) > now
				if locked then
					return nil -- abort: somebody else owns the slot, and we write nothing
				end
				old.jobId = game.JobId
				old.lockUntil = now + Config.Save.LockSeconds
				return old
			end)
		end)
		if ok then
			local profile = Economy.normalizeProfile(Config, raw, os.time())
			if not locked then
				return profile, true, nil, deepCopy(raw)
			end
			if waited >= Config.Save.LockWaitSeconds then
				warn("[Cryptid] " .. plr.Name .. " is locked by another server; playing without saving.")
				return profile, false, LOCKED, deepCopy(raw)
			end
			if waited == 0 then toast(plr, LOCK_WAITING) end
			task.wait(Config.Save.LockRetrySeconds)
			waited += Config.Save.LockRetrySeconds
		else
			failures += 1
			warn(string.format("[Cryptid] load attempt %d of %d failed for %s: %s", failures, Config.Save.LoadAttempts, plr.Name, tostring(err)))
			if failures >= Config.Save.LoadAttempts then
				return Economy.defaultProfile(Config), false, LOAD_FAILED, nil
			end
			task.wait(Config.Save.LoadRetrySeconds * failures)
		end
		if plr.Parent ~= Players then
			-- left while waiting: nothing was taken, and the caller sees the player gone
			return Economy.defaultProfile(Config), false, LOAD_FAILED, nil
		end
	end
end

-- Deep equality of two values read from the store (tables of strings, numbers, booleans).
local function sameValue(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in a do
		if not sameValue(v, b[k]) then return false end
	end
	for k in b do
		if a[k] == nil then return false end
	end
	return true
end

-- Hand back a lock this server took for a player who left before their load finished. Only OUR
-- lock is cleared; anything another server wrote meanwhile is left alone.
local function releaseLock(userKey: string)
	if not store then return end
	local ok, err = pcall(function()
		store:UpdateAsync(userKey, function(old)
			if type(old) ~= "table" or old.jobId ~= game.JobId then return nil end
			old.jobId = nil
			old.lockUntil = 0
			return old
		end)
	end)
	if not ok then warn("[Cryptid] could not release the lock on " .. userKey .. ": " .. tostring(err)) end
end

local pushState -- forward: a flush that finds its lock taken tells the player at once

-- One write. `force` writes even when nothing changed (the raid grant, the lock renewal);
-- `releaseLock` hands the slot back on leave. Returns true only when a value was committed.
--
-- WRITES ARE SERIALISED PER SESSION. A flush copies the profile BEFORE its UpdateAsync yields, so
-- two overlapping writes can land in the wrong order and the older copy overwrites the newer one
-- (REVIEW-1: a grant committed while the periodic flush was still in flight was then overwritten by
-- that flush's pre-grant copy, and the store lost the steal). `waitTurn` = wait for the write in
-- flight (the grant, a leave); without it (the periodic loops) a flush that finds one in flight
-- simply skips, leaving `pending` set for the next tick.
local function flush(S: any, releaseLock: boolean, force: boolean?, waitTurn: boolean?): boolean
	if not store or not S.canSave or not S.loaded then return false end
	if S.writing then
		if not waitTurn then return false end
		local waited = 0
		while S.writing and waited < Config.Save.WriteQueueSeconds do
			task.wait(0.1)
			waited += 0.1
		end
		if S.writing or not S.canSave then return false end
	end
	local p = S.profile
	local fp = fingerprint(p)
	if not force and not releaseLock and fp == S.savedFingerprint then
		S.pending = false
		return true
	end
	local data = deepCopy(p)
	data.savedAt = os.time()
	local wrote, lost = false, false
	-- This write carries every change made so far. A change made while it yields marks `pending`
	-- again and is written at the next flush tick (REVIEW-1.md A4: clearing `pending` AFTER the write
	-- wiped a request made during it, and that change waited for the 60 s autosave).
	S.pending = false
	S.writing = true
	local ok, err = pcall(function()
		store:UpdateAsync(key(S.plr), function(old)
			wrote, lost = false, false
			old = old or {}
			if old.jobId ~= nil and old.jobId ~= game.JobId and (tonumber(old.lockUntil) or 0) > os.time() then
				lost = true
				return nil
			end
			-- A session that is closing never locks again, whichever of its queued writes lands last
			-- (REVIEW-1.md A3: a grant queued behind a write landed after the leave's release and locked
			-- the record for 120 s with the player gone). Read INSIDE the transform, at commit time.
			local release = releaseLock or S.closing == true
			-- if-then-else, never `release and nil or game.JobId`, which always yields the JobId
			old.jobId = if release then nil else game.JobId
			old.lockUntil = if release then 0 else os.time() + Config.Save.LockSeconds
			old.data = data
			wrote = true
			return old
		end)
	end)
	S.writing = false
	if not ok then
		warn("[Cryptid] save failed for " .. S.plr.Name .. ": " .. tostring(err))
		S.pending = true
	end
	if ok and wrote then
		S.savedFingerprint = fp
		p.savedAt = data.savedAt
	elseif ok and lost then
		-- another server took the record over mid-session. This session stops writing for good and
		-- says so; it never goes back to saving (it would have to merge with what that server wrote)
		warn("[Cryptid] " .. S.plr.Name .. "'s lock was taken by another server; this session stops saving.")
		S.canSave = false
		S.banner = LOCKED
		S.pending = false
		if sessions[S.plr] == S then
			ToastEvent:FireClient(S.plr, LOCKED)
			pushState(S)
		end
	end
	return ok and wrote
end

-- Handlers mark; the flush loop writes, at most once per FlushTickSeconds per player.
local function requestSave(S: any)
	S.pending = true
end

-- REVIEW-1.md A1, after the join wait: a session that started unsaved because another server held
-- the lock re-reads the record every LockRecheckSeconds. When the lock is gone AND the saved data is
-- exactly what this session loaded (the other server crashed, or its lock lapsed), nothing can be
-- lost by continuing: the session takes the lock in the same transform and saves from then on. When
-- the data changed (the other server wrote after this session read it), writing would erase that
-- write, so the session stays unsaved for good and tells the player to rejoin.
local function recheckLock(S: any)
	while sessions[S.plr] == S and not S.canSave and S.banner == LOCKED and not S.closing do
		task.wait(Config.Save.LockRecheckSeconds)
		if sessions[S.plr] ~= S or S.closing then return end
		local state = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key(S.plr), function(old)
				state = nil
				old = old or {}
				local now = os.time()
				if old.jobId ~= nil and old.jobId ~= game.JobId and (tonumber(old.lockUntil) or 0) > now then
					state = "locked"
					return nil
				end
				if not sameValue(old.data, S.loadedData) then
					state = "changed"
					return nil
				end
				state = "taken"
				old.jobId = game.JobId
				old.lockUntil = now + Config.Save.LockSeconds
				return old
			end)
		end)
		if not ok then
			warn("[Cryptid] lock re-check failed for " .. S.plr.Name .. ": " .. tostring(err))
		elseif state == "taken" then
			if sessions[S.plr] ~= S or S.closing then
				-- left while the write was in flight: hand the lock straight back
				releaseLock(key(S.plr))
				return
			end
			S.canSave = true
			S.banner = nil
			S.savedFingerprint = nil
			requestSave(S)
			toast(S.plr, LOCK_TAKEN)
			pushState(S)
			return
		elseif state == "changed" then
			S.banner = LOCK_CHANGED
			toast(S.plr, LOCK_CHANGED)
			pushState(S)
			return
		end
	end
end

--============================================================================ world frames

local plotCount = math.max(W.Plots, Players.MaxPlayers)

-- Plot i sits in road column floor(i/2), on side i % 2, its gate facing the road. The frame maps
-- plot-local (x, y, z) to the world; side 1 is turned 180 degrees so both rows face the road.
local function plotFrame(index: number): CFrame
	local col = math.floor(index / 2)
	local x0 = col * W.PlotPitch - W.PlotWidth / 2
	local half = W.RoadWidth / 2
	if index % 2 == 0 then
		return CFrame.new(x0, 0, half)
	end
	return CFrame.new(x0 + W.PlotWidth, 0, -half, -1, 0, 0, 0, 1, 0, 0, 0, -1)
end

local function pocketFrame(slot: number): CFrame
	return CFrame.new(W.PocketOriginX + W.PocketPitch * slot, 0, 0)
end

local function at(frame: CFrame, x: number, y: number, z: number): CFrame
	return frame * CFrame.new(x, y, z)
end

-- Where a character stands at home: over the arrival marker, root at RootHeight, facing P1.
local function arrivalCFrame(index: number): CFrame
	local frame = plotFrame(index)
	local a, p1 = W.Apron.Arrival, W.Apron.P1
	local pos = frame:PointToWorldSpace(Vector3.new(a.x, W.RootHeight, a.z))
	local look = frame:PointToWorldSpace(Vector3.new(p1.x, W.RootHeight, p1.z))
	return CFrame.new(pos, look)
end

--============================================================================ part helpers

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent -- an unparented Part raises nothing and is invisible to everyone
	return p
end

local function label(host: Instance, text: string, color: Color3, offsetY: number, width: number?, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(width or 200, 56)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 70
	gui.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.35
	t.Text = text
	t.Parent = gui
	gui.Parent = host
	return t
end

local function prompt(host: Instance, name: string, action: string, object: string, hold: number, distance: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = distance
	pp.RequiresLineOfSight = false
	pp.Parent = host
	return pp
end

local WOOD = Color3.fromRGB(58, 44, 34)
local STONE = Color3.fromRGB(88, 92, 98)
local RED = Color3.fromRGB(255, 50, 50)
local AMBER = Color3.fromRGB(255, 170, 40)

--============================================================================ cryptid templates

-- [7] Built once into ServerStorage (never replicated) and cloned. PrimaryPart is the first part;
-- its model-space offset is kept so a clone can be stood on the ground with one PivotTo.
local templates = Instance.new("Folder")
templates.Name = "CryptidTemplates"
templates.Parent = ServerStorage
local templateOffset: { [string]: Vector3 } = {}

for _, s in Config.Species do
	local m = Instance.new("Model")
	m.Name = s.id
	local tierColor = rgb(Config.Tiers[s.tier].color)
	local primary = nil
	for _, d in CryptidModel.parts(Config, s.id) do
		local p = Instance.new("Part")
		p.Name = d.name
		p.Shape = Enum.PartType[d.shape]
		p.Material = Enum.Material[d.material]
		p.Color = rgb(d.color)
		p.Size = Vector3.new(d.size.x, d.size.y, d.size.z)
		p.CFrame = CFrame.new(d.pos.x, d.pos.y, d.pos.z)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = m
		if primary == nil then
			primary = p
			templateOffset[s.id] = Vector3.new(d.pos.x, d.pos.y, d.pos.z)
		end
	end
	m.PrimaryPart = primary
	local aura = CryptidModel.aura(Config, s.id)
	if aura == "dust" then
		Fx.dust(primary, tierColor, 5)
	elseif aura == "glow" or aura == "gold" then
		Fx.attachGlow(primary, tierColor, if aura == "gold" then 2.4 else 1.6, 12)
		Fx.sparkle(primary, tierColor)
	end
	m.Parent = templates
end

local function spawnCryptid(sp: string, groundCF: CFrame, parent: Instance, name: string): Model
	local m = (templates:FindFirstChild(sp) :: Model):Clone()
	m.Name = name
	m:PivotTo(groundCF * CFrame.new(templateOffset[sp]))
	m.Parent = parent
	return m
end

--============================================================================ the road

local roadFolder = Instance.new("Folder")
roadFolder.Name = "Road"
roadFolder.Parent = workspace

local columns = math.ceil(plotCount / 2)
local roadLength = columns * W.PlotPitch + 120
local roadCentreX = (columns * W.PlotPitch) / 2 - W.PlotWidth / 2

newPart("Ground", Vector3.new(roadLength, 1, 260), CFrame.new(roadCentreX, -0.7, 0), Color3.fromRGB(34, 46, 32), Enum.Material.Grass, roadFolder)
newPart("RoadSurface", Vector3.new(roadLength, 1, W.RoadWidth), CFrame.new(roadCentreX, -0.5, 0), Color3.fromRGB(70, 58, 46), Enum.Material.Ground, roadFolder)

-- [9] THE ONE ENABLED SPAWNLOCATION. The engine parents a character and places it here one frame
-- after CharacterAdded; the handler below then moves it home. Never add a second enabled spawn
-- (the engine picks among all of them) and never disable this one (with none, Roblox drops the
-- character on the highest ground over the origin).
local trailhead = Instance.new("SpawnLocation")
trailhead.Name = "Trailhead"
trailhead.Anchored = true
trailhead.Size = Vector3.new(W.TrailheadSize.x, W.TrailheadSize.y, W.TrailheadSize.z)
trailhead.CFrame = CFrame.new(W.TrailheadPosition.x, W.TrailheadPosition.y, W.TrailheadPosition.z)
trailhead.Material = Enum.Material.Slate
trailhead.Color = Color3.fromRGB(80, 90, 84)
trailhead.Enabled = true
trailhead.Neutral = true
trailhead.Duration = 0
trailhead.Parent = workspace

do
	local post = newPart("TrailSign", Vector3.new(1, 8, 1), CFrame.new(0, 4, -12), WOOD, Enum.Material.Wood, roadFolder)
	label(post, "STEAL A CRYPTID\nPine Hollow", rgb(Config.Hud.Accent), 6, 260, 120)
	-- pines in the gaps between lairs, on both sides of the road
	local n = 0
	for col = 0, columns do
		for _, side in { 1, -1 } do
			for _, depth in { 34, 78 } do
				local x = col * W.PlotPitch - W.PlotWidth / 2 - 12
				local z = side * (W.RoadWidth / 2 + depth)
				n += 1
				newPart("PineTrunk_" .. n, Vector3.new(1.6, 10, 1.6), CFrame.new(x, 5, z), Color3.fromRGB(56, 40, 30), Enum.Material.Wood, roadFolder)
				local crown = newPart("PineCrown_" .. n, Vector3.new(9, 14, 9), CFrame.new(x, 15, z), Color3.fromRGB(26, 52, 36), Enum.Material.Grass, roadFolder)
				crown.Shape = Enum.PartType.Ball
				crown.CanCollide = false
			end
		end
	end
end

--============================================================================ plots

local lairsFolder = Instance.new("Folder")
lairsFolder.Name = "Lairs"
lairsFolder.Parent = workspace

local pocketsFolder = Instance.new("Folder")
pocketsFolder.Name = "Pockets"
pocketsFolder.Parent = workspace

local poachersFolder = Instance.new("Folder")
poachersFolder.Name = "Poachers"
poachersFolder.Parent = workspace

local raidInfoFolder = Instance.new("Folder")
raidInfoFolder.Name = "RaidInfo"
raidInfoFolder.Parent = ServerStorage

local plotFolders: { [number]: Folder } = {}
local plotSigns: { [number]: TextLabel } = {}
local plotOwner: { [number]: Player } = {}

for i = 0, plotCount - 1 do
	local frame = plotFrame(i)
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. i
	folder.Parent = lairsFolder
	newPart("Floor", Vector3.new(W.PlotWidth, 1, W.PlotDepth), at(frame, W.PlotWidth / 2, -0.5, W.PlotDepth / 2),
		Color3.fromRGB(40, 54, 38), Enum.Material.Grass, folder)
	local sign = newPart("Sign", Vector3.new(1, 7, 1), at(frame, W.PlotWidth - 2, 3.5, 2), WOOD, Enum.Material.Wood, folder)
	plotSigns[i] = label(sign, "Empty lair", Color3.fromRGB(200, 205, 190), 5, 220, 90)
	plotFolders[i] = folder
end

local function claimPlot(plr: Player): number?
	for i = 0, plotCount - 1 do
		if plotOwner[i] == nil then
			plotOwner[i] = plr
			return i
		end
	end
	return nil
end

--============================================================================ state to the owner

local function tierName(t: number): string
	return Config.Tiers[t] and Config.Tiers[t].name or "?"
end

local function speciesName(id: string): string
	local s = Economy.species(Config, id)
	return s and s.name or ""
end

function pushState(S: any)
	if not S.loaded then return end
	local p = S.profile
	local now = os.time()
	local cages, maxJar = {}, 0
	for col = 1, 9 do
		local c = p.cages[col]
		cages[col] = {
			sp = c.sp, name = speciesName(c.sp), jar = c.jar, rate = Economy.rate(Config, c.sp),
			tier = Economy.tierOf(Config, c.sp) or 0, unlocked = Economy.isUnlockedCage(Config, p, col),
		}
		if c.sp ~= "" then maxJar = math.max(maxJar, c.jar) end
	end
	local offers = {}
	for slot = 1, Config.Offers.Pedestals do
		local sp = S.offers[slot]
		offers[slot] = {
			sp = sp, name = speciesName(sp), tier = Economy.tierOf(Config, sp) or 0,
			price = Economy.price(Config, sp) or 0, rate = Economy.rate(Config, sp),
		}
	end
	local camps = {}
	for tier = 1, #Config.Camps do
		local unlocked = Economy.campUnlocked(Config, tier, p.journal)
		local heatLeft = math.max(0, (p.heat["t" .. tier] or 0) - now)
		local reason = nil
		if not unlocked then
			reason = "Own a " .. tierName(tier - 1) .. " cryptid to unlock"
		elseif heatLeft > 0 then
			reason = "On alert for " .. heatLeft .. " s"
		end
		camps[tier] = {
			tier = tier, name = tierName(tier), unlocked = unlocked, permit = Economy.permit(Config, tier),
			heatLeft = heatLeft, reason = reason,
		}
	end
	local raid = nil
	if S.raid then
		local R = S.raid
		raid = {
			tier = R.tier, campName = R.name,
			timeLeft = math.max(0, math.ceil(RAID.RaidSeconds - (tick() - R.startTick))),
			carrying = if R.carrying then speciesName(R.carrying.sp) else nil,
		}
	end
	local poacher = nil
	if S.poacher then
		poacher = { active = true }
	elseif S.warningAt then
		poacher = { warningLeft = math.max(0, math.ceil(S.appearAt - tick())) }
	end
	local okReroll, rerollLeft = Offers.canReroll(Config, S.rerollAt, tick())
	StateEvent:FireClient(S.plr, {
		essence = math.floor(p.essence),
		rate = Economy.lairRate(Config, p),
		journal = #p.journal,
		journalMax = #Config.Species,
		cages = cages,
		maxJar = maxJar,
		cagesUnlocked = p.cagesUnlocked,
		expandPrice = Economy.expansionPrice(Config, p.cagesUnlocked),
		offers = offers,
		rerollLeft = if okReroll then 0 else rerollLeft,
		lasers = Layout.count(S.layout, "laser"),
		snares = Layout.count(S.layout, "snare"),
		maxLasers = Config.Traps.MaxLasers,
		maxSnares = Config.Traps.MaxSnares,
		laserPrice = Config.Traps.LaserPrice,
		snarePrice = Config.Traps.SnarePrice,
		camps = camps,
		tutorial = p.tutorial,
		collectHint = p.tutorial == 1 and maxJar >= Config.Tutorial.CollectHintJar,
		raid = raid,
		buildMode = S.buildMode,
		canSave = S.canSave,
		saveBanner = S.banner,
		stats = { steals = p.stats.steals, caught = p.stats.caught, poachersCaught = p.stats.poachersCaught },
		poacher = poacher,
	})
end

--============================================================================ rate limits

-- [8] 8 calls per remote per player per second; excess is dropped with at most one "Slow down"
-- toast per 5 s, so a flood is neither silent nor spammy.
local function allow(S: any, name: string): boolean
	local now = tick()
	local b = S.buckets[name]
	if b == nil or now - b.start >= 1 then
		b = { start = now, n = 0 }
		S.buckets[name] = b
	end
	b.n += 1
	if b.n <= Config.Remotes.MaxPerSecond then return true end
	if now - (S.slowToastAt or -math.huge) >= Config.Remotes.SlowDownToastSeconds then
		S.slowToastAt = now
		toast(S.plr, "Slow down")
	end
	return false
end

-- In-world prompts and build tiles are rate limited on the CALLER's own session: a
-- fireproximityprompt loop must not schedule hundreds of server-timed holds.
local function allowWho(who: Player, name: string): boolean
	local WS = sessions[who]
	return WS ~= nil and allow(WS, name)
end

--============================================================================ laser visuals

-- [8] The server publishes the PRESENT, never the schedule: a net's state is written as it
-- happens, and no period, phase or next-switch time exists on any Instance. OFF is no net at all,
-- WARN flickers amber, ON is a red neon net with a light.
local function paintLaser(entry: any, state: string)
	local flick = false
	if state == "warn" then
		entry.flick = not entry.flick
		flick = entry.flick
	end
	local shown = state .. (if flick then "+" else "")
	if entry.shown == shown then return end
	entry.shown = shown
	local part, light = entry.part, entry.light
	if state == "on" then
		part.Color = RED
		part.Transparency = 0.35
		light.Enabled = true
	elseif state == "warn" then
		part.Color = AMBER
		part.Transparency = if flick then 0.55 else 0.9
		light.Enabled = false
	else
		part.Transparency = 1
		light.Enabled = false
	end
end

local function buildTrapPart(trap: any, frame: CFrame, parent: Instance): any
	local x, z = Layout.cellCenter(Config, trap.col, trap.row)
	if trap.kind == "laser" then
		local part = newPart("Laser_" .. trap.col .. "_" .. trap.row, Vector3.new(6, W.FenceHeight, 6), at(frame, x, W.FenceHeight / 2, z),
			RED, Enum.Material.Neon, parent)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = RED
		light.Brightness = 2
		light.Range = 14
		light.Enabled = false
		light.Parent = part
		-- The emitter plate is ALWAYS visible. REVIEW-1: with only the net, an armed gap was named in
		-- the workspace (Laser_c_r) while its net was fully transparent, in 20 of 20 fresh camps, so
		-- a script knew which gap was armed and a player did not until the net first lit. Names
		-- carry only what is visible, so the armed cell is made visible. A child of the net, so
		-- clearing the trap removes both; never collides, never takes a mouse ray or a touch.
		local plate = newPart("Emitter", Vector3.new(7, 0.16, 7), at(frame, x, 0.08, z), Color3.fromRGB(110, 26, 26), Enum.Material.Neon, part)
		plate.Transparency = 0.35
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.CastShadow = false
		return { part = part, light = light, trap = trap, shown = nil, flick = false }
	end
	local part = newPart("Snare_" .. trap.col .. "_" .. trap.row, Vector3.new(5.5, 0.4, 5.5), at(frame, x, 0.2, z),
		Color3.fromRGB(120, 40, 36), Enum.Material.CorrodedMetal, parent)
	part.CanCollide = false
	part.CanTouch = false
	-- a click on a snared tile must reach the tile under it (REVIEW-1: the snare covered 55 % of the
	-- tile's top face, so clearing it meant clicking the rim)
	part.CanQuery = false
	Fx.attachGlow(part, Color3.fromRGB(255, 70, 50), 1, 9)
	return { part = part, trap = trap }
end

--============================================================================ lairs

local function cageLabelText(S: any, col: number): string
	local p = S.profile
	if not Economy.isUnlockedCage(Config, p, col) then return "Locked" end
	local c = p.cages[col]
	if c.sp == "" then return "Empty cage" end
	local s = Economy.species(Config, c.sp)
	return string.format("%s - %s\n+%d/s  jar %d", s.name, tierName(s.tier), s.rate, math.floor(c.jar))
end

local function refreshCageLabel(S: any, col: number)
	local entry = S.lair and S.lair.cages[col]
	if entry and entry.label then
		local text = cageLabelText(S, col)
		if entry.label.Text ~= text then entry.label.Text = text end
	end
end

local function cageGround(S: any, col: number): CFrame
	local x, z = Layout.cellCenter(Config, col, W.CageRow)
	-- face the yard (plot-local -z)
	return at(plotFrame(S.plotIndex), x, 0.4, z)
end

local handleRelease -- forward

local function buildCage(S: any, col: number)
	local lair = S.lair
	local old = lair.cages[col]
	if old then
		for _, inst in { old.base, old.bars, old.model } do
			if inst then inst:Destroy() end
		end
	end
	local frame = plotFrame(S.plotIndex)
	local x, z = Layout.cellCenter(Config, col, W.CageRow)
	local entry: any = {}
	lair.cages[col] = entry
	if not Economy.isUnlockedCage(Config, S.profile, col) then
		entry.base = newPart("CageLocked_" .. col, Vector3.new(7.6, 0.4, 7.6), at(frame, x, 0.2, z),
			Color3.fromRGB(30, 30, 34), Enum.Material.Slate, lair.cageFolder)
		entry.label = label(entry.base, "Locked", Color3.fromRGB(150, 150, 150), 3, 160, 50)
		return
	end
	entry.base = newPart("Cage_" .. col, Vector3.new(7.6, 0.4, 7.6), at(frame, x, 0.2, z),
		Color3.fromRGB(60, 62, 70), Enum.Material.DiamondPlate, lair.cageFolder)
	entry.bars = newPart("Bars_" .. col, Vector3.new(7.6, 8, 7.6), at(frame, x, 4.4, z),
		Color3.fromRGB(150, 160, 170), Enum.Material.Glass, lair.cageFolder)
	entry.bars.Transparency = 0.8
	-- a faint rim glow on every interactable (DESIGN.md section 13; REVIEW-1.md B3: cages had none)
	Fx.attachGlow(entry.base, rgb(Config.Hud.Accent), 0.8, 8)
	entry.label = label(entry.base, cageLabelText(S, col), Color3.fromRGB(230, 235, 225), 9.5, 200, 60)
	local c = S.profile.cages[col]
	entry.prompt = prompt(entry.base, "Release", "Release", if c.sp ~= "" then speciesName(c.sp) else "Empty cage",
		Config.Economy.ReleaseHoldSeconds, W.PromptDistance)
	entry.prompt.PromptButtonHoldBegan:Connect(function(who)
		if who == S.plr then S.releaseBegan[col] = tick() end
	end)
	entry.prompt.Triggered:Connect(function(who)
		handleRelease(S, col, who)
	end)
	if c.sp ~= "" then
		entry.model = spawnCryptid(c.sp, cageGround(S, col), lair.cageFolder, "Cryptid_" .. col)
	end
end

-- The cryptid now in cage `col` walks there from plot-local (fromX, fromZ) over BuyTweenSeconds: a
-- purchase from its pedestal (DESIGN.md section 4), a steal from the arrival marker the raider lands
-- on (section 12; REVIEW-1.md B3: a stolen cryptid used to appear in its cage).
local function walkInto(S: any, col: number, sp: string, fromX: number, fromZ: number)
	local entry = S.lair.cages[col]
	local model = entry and entry.model
	if not model then return end
	local from = plotFrame(S.plotIndex):PointToWorldSpace(Vector3.new(fromX, 3, fromZ))
	local to = cageGround(S, col)
	local steps = 20
	task.spawn(function()
		for i = 0, steps do
			if model.Parent == nil then return end
			local pos = from:Lerp(to.Position, i / steps)
			model:PivotTo(CFrame.new(pos) * to.Rotation * CFrame.new(templateOffset[sp]))
			if i < steps then task.wait(Config.Economy.BuyTweenSeconds / steps) end
		end
	end)
end

local function refreshPedestal(S: any, slot: number)
	local ped = S.lair.pedestals[slot]
	if ped.model then
		ped.model:Destroy()
		ped.model = nil
	end
	local sp = S.offers[slot]
	if sp == "" then
		ped.label.Text = "A new sighting is on its way"
		ped.prompt.ObjectText = "Sighting"
		ped.prompt.ActionText = "Wait"
		return
	end
	local s = Economy.species(Config, sp)
	local price = Economy.price(Config, sp) :: number
	ped.label.Text = string.format("%s - %s\n+%d/s  |  %d Essence", s.name, tierName(s.tier), s.rate, price)
	ped.label.TextColor3 = rgb(Config.Tiers[s.tier].color)
	ped.prompt.ObjectText = s.name
	ped.prompt.ActionText = "Buy (" .. price .. ")"
	ped.glow.Color = rgb(Config.Tiers[s.tier].color)
	local a = W.Apron["P" .. slot]
	ped.model = spawnCryptid(sp, at(plotFrame(S.plotIndex), a.x, 3, a.z), ped.part, "Offer_" .. slot)
end

local handleBuy, handleCollect, openHunt -- forward

local function buildTraps(S: any)
	local lair = S.lair
	for _, e in lair.trapParts do e.part:Destroy() end
	lair.trapParts = {}
	for _, t in Layout.traps(S.layout) do
		lair.trapParts[Layout.key(t.col, t.row)] = buildTrapPart(t, plotFrame(S.plotIndex), lair.trapFolder)
	end
end

local function buildLair(S: any)
	local frame = plotFrame(S.plotIndex)
	local folder = Instance.new("Folder")
	folder.Name = "Lair"
	local lair: any = { folder = folder, cages = {}, pedestals = {}, trapParts = {} }
	S.lair = lair

	-- fences: the front fence (row 0 but the gate), the sides, the back, and the two fence lines
	local fences = Instance.new("Folder")
	fences.Name = "Fences"
	fences.Parent = folder
	local H = W.FenceHeight
	local function fenceRun(name: string, c0: number, c1: number, row: number)
		local r0 = Layout.cellRect(Config, c0, row)
		local r1 = Layout.cellRect(Config, c1, row)
		newPart(name, Vector3.new(r1.x1 - r0.x0, H, W.CellSize), at(frame, (r0.x0 + r1.x1) / 2, H / 2, (r0.z0 + r0.z1) / 2),
			WOOD, Enum.Material.WoodPlanks, fences)
	end
	fenceRun("FrontL", 1, W.GateCol - 1, 0)
	fenceRun("FrontR", W.GateCol + 1, W.YardCols, 0)
	local yardZ0, yardZ1 = W.ApronDepth + W.CellSize, W.ApronDepth + W.CellSize * (W.CageRow + 1)
	newPart("SideL", Vector3.new(1, H, yardZ1 - yardZ0), at(frame, -0.5, H / 2, (yardZ0 + yardZ1) / 2), WOOD, Enum.Material.WoodPlanks, fences)
	newPart("SideR", Vector3.new(1, H, yardZ1 - yardZ0), at(frame, W.PlotWidth + 0.5, H / 2, (yardZ0 + yardZ1) / 2), WOOD, Enum.Material.WoodPlanks, fences)
	newPart("Back", Vector3.new(W.PlotWidth + 2, H, 1), at(frame, W.PlotWidth / 2, H / 2, yardZ1 + 0.5), WOOD, Enum.Material.WoodPlanks, fences)
	for _, line in S.layout.lines do
		local c = 1
		while c <= W.YardCols do
			if Layout.cellKind(S.layout, c, line.row) == "fence" then
				local c1 = c
				while c1 + 1 <= W.YardCols and Layout.cellKind(S.layout, c1 + 1, line.row) == "fence" do c1 += 1 end
				fenceRun("Line_" .. line.row .. "_" .. c, c, c1, line.row)
				c = c1 + 1
			else
				c += 1
			end
		end
	end

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = folder
	for _, r in S.layout.rocks do
		local x, z = Layout.cellCenter(Config, r[1], r[2])
		newPart("Rock_" .. r[1] .. "_" .. r[2], Vector3.new(7.6, W.RockHeight, 7.6), at(frame, x, W.RockHeight / 2, z), STONE, Enum.Material.Slate, rocks)
	end

	lair.cageFolder = Instance.new("Folder")
	lair.cageFolder.Name = "Cages"
	lair.cageFolder.Parent = folder

	lair.trapFolder = Instance.new("Folder")
	lair.trapFolder.Name = "Traps"
	lair.trapFolder.Parent = folder

	local pedFolder = Instance.new("Folder")
	pedFolder.Name = "Pedestals"
	pedFolder.Parent = folder
	for slot = 1, Config.Offers.Pedestals do
		local a = W.Apron["P" .. slot]
		local part = newPart("Pedestal_" .. slot, Vector3.new(4, 3, 4), at(frame, a.x, 1.5, a.z),
			Color3.fromRGB(70, 74, 80), Enum.Material.Marble, pedFolder)
		local glow = Fx.attachGlow(part, rgb(Config.Hud.Accent), 1.2, 10)
		local ped: any = {
			part = part,
			glow = glow,
			label = label(part, "", Color3.fromRGB(230, 235, 225), 7, 220, 50),
			prompt = prompt(part, "Buy", "Buy", "", 0, W.PromptDistance),
		}
		ped.prompt.Triggered:Connect(function(who) handleBuy(S, slot, who) end)
		lair.pedestals[slot] = ped
	end

	local pa = W.Apron.Pad
	lair.pad = newPart("CollectPad", Vector3.new(W.PadSize.x, W.PadSize.y, W.PadSize.z), at(frame, pa.x, -0.4, pa.z),
		Color3.fromRGB(90, 230, 190), Enum.Material.Neon, folder)
	lair.pad.Transparency = 0.25
	lair.pad.CanTouch = true
	label(lair.pad, "COLLECT", Color3.fromRGB(150, 255, 220), 3, 140, 50)
	Fx.attachGlow(lair.pad, Color3.fromRGB(90, 230, 190), 1.4, 12)
	lair.pad.Touched:Connect(function(hit) handleCollect(S, hit) end)

	local b = W.Apron.Board
	lair.board = newPart("HuntBoard", Vector3.new(8, 6, 1), at(frame, b.x, 4, b.z), WOOD, Enum.Material.WoodPlanks, folder)
	label(lair.board, "HUNT BOARD\nRival camps", Color3.fromRGB(255, 200, 120), 5, 200, 60)
	Fx.attachGlow(lair.board, Color3.fromRGB(255, 180, 90), 1.2, 12)
	local hp = prompt(lair.board, "Hunt", "Open", "Hunt Board", 0, W.PromptDistance)
	hp.Triggered:Connect(function(who) openHunt(S, who) end)

	local ar = W.Apron.Arrival
	local arrival = newPart("Arrival", Vector3.new(4, 0.1, 4), at(frame, ar.x, 0.05, ar.z), rgb(Config.Hud.Accent), Enum.Material.Neon, folder)
	arrival.Transparency = 0.6
	arrival.CanCollide = false
	arrival.CanQuery = false
	arrival.CanTouch = false

	folder.Parent = plotFolders[S.plotIndex]

	for col = 1, 9 do buildCage(S, col) end
	for slot = 1, Config.Offers.Pedestals do refreshPedestal(S, slot) end
	buildTraps(S)
end

--============================================================================ build mode tiles

local function clearTiles(S: any)
	if S.lair and S.lair.tileFolder then
		S.lair.tileFolder:Destroy()
		S.lair.tileFolder = nil
	end
end

local function buildTiles(S: any)
	clearTiles(S)
	local frame = plotFrame(S.plotIndex)
	local folder = Instance.new("Folder")
	folder.Name = "BuildTiles"
	-- every cell the rocks and fences leave reachable; snares do not count as walls here, so a
	-- tile under an existing snare stays clickable to clear it
	local bare = Layout.fromSpec(Config, { kind = "lair", lines = S.layout.lines, rocks = S.layout.rocks })
	local reach = Layout.reachableFrom(bare, W.EntryCol, W.EntryRow)
	for row = 1, W.YardRows - 1 do
		for col = 1, W.YardCols do
			if reach[Layout.key(col, row)] and not (col == W.EntryCol and row == W.EntryRow) then
				local x, z = Layout.cellCenter(Config, col, row)
				local tile = newPart("Tile_" .. col .. "_" .. row, Vector3.new(7.4, 0.2, 7.4), at(frame, x, 0.1, z),
					Color3.fromRGB(120, 255, 170), Enum.Material.Neon, folder)
				tile.Transparency = 0.75
				tile.CanCollide = false
				tile.CanTouch = false
				local cd = Instance.new("ClickDetector")
				cd.Name = "Click"
				cd.MaxActivationDistance = W.BuildTileDistance
				cd.Parent = tile
				cd.MouseClick:Connect(function(who)
					if not allowWho(who, "Tile") then return end
					if who ~= S.plr then
						toast(who, "This is " .. S.plr.Name .. "'s lair")
						return
					end
					if not S.buildMode then
						toast(who, "Turn on Build mode first")
						return
					end
					local t = Layout.trapAt(S.layout, col, row)
					FxEvent:FireClient(who, "buildCell", { col = col, row = row, trap = t and t.kind or nil })
				end)
			end
		end
	end
	folder.Parent = S.lair.folder
	S.lair.tileFolder = folder
end

--============================================================================ in-lair actions

local SAVING_STEAL = "Saving your steal - one moment"

-- Every lair action goes through this. `granting` is the raid grant's write in flight: until it
-- lands or is rolled back, nothing may spend or move what it is writing (REVIEW-1: a hunt started
-- and a release paid out during that write).
local function onHome(S: any): boolean
	if S.raid then
		toast(S.plr, "You are on a hunt")
		return false
	end
	if S.granting then
		toast(S.plr, SAVING_STEAL)
		return false
	end
	return true
end

local function ownerOnly(S: any, who: Player): boolean
	if who ~= S.plr then
		toast(who, "This is " .. S.plr.Name .. "'s lair")
		return false
	end
	return true
end

local function refreshOffersAfterRank(S: any, oldRank: number)
	local newRank = Economy.rank(Config, S.profile.journal)
	if newRank > oldRank then
		S.offers = Offers.onRankChange(Config, S.offerRng, S.offers, oldRank, newRank, S.profile.tutorial)
		for slot = 2, Config.Offers.Pedestals do refreshPedestal(S, slot) end
	end
end

function handleBuy(S: any, slot: number, who: Player)
	if not allowWho(who, "Prompt") then return end
	if not S.loaded or not ownerOnly(S, who) or not onHome(S) then return end
	local p = S.profile
	local sp = S.offers[slot]
	if sp == "" then
		toast(who, "A new sighting is on its way")
		return
	end
	local price = Economy.price(Config, sp) :: number
	local name = speciesName(sp)
	if p.essence < price then
		toast(who, string.format("%s costs %d Essence - you have %d", name, price, math.floor(p.essence)))
		return
	end
	local col = Economy.firstEmptyCage(Config, p)
	if not col then
		toast(who, "Your cages are full - release one at its cage, or add a cage on the Hunt Board")
		return
	end
	local oldRank = Economy.rank(Config, p.journal)
	p.essence -= price
	p.cages[col] = { sp = sp, jar = 0 }
	if not Economy.journalHas(p.journal, sp) then table.insert(p.journal, sp) end
	if p.tutorial == 0 then p.tutorial = 1 end
	S.offers[slot] = ""
	refreshPedestal(S, slot)
	buildCage(S, col)

	-- [4] the bought cryptid walks from its pedestal to its cage, so the purchase is visibly delivered
	local a = W.Apron["P" .. slot]
	walkInto(S, col, sp, a.x, a.z)
	task.delay(Config.Economy.BuyTweenSeconds, function()
		if sessions[S.plr] ~= S or not S.lair then return end
		if S.offers[slot] == "" then
			S.offers[slot] = Offers.draw(Config, S.offerRng, slot, Economy.rank(Config, S.profile.journal), S.profile.tutorial)
			refreshPedestal(S, slot)
			pushState(S)
		end
	end)
	refreshOffersAfterRank(S, oldRank)
	toast(who, string.format("You bought a %s! +%d Essence/s", name, Economy.rate(Config, sp)))
	FxEvent:FireClient(who, "bought", { sp = sp })
	requestSave(S)
	pushState(S)
end

function handleRelease(S: any, col: number, who: Player)
	if not allowWho(who, "Prompt") then return end
	if not S.loaded or not ownerOnly(S, who) or not onHome(S) then return end
	local c = S.profile.cages[col]
	if c.sp == "" then
		toast(who, "This cage is empty - buy or steal a cryptid to fill it")
		return
	end
	local sp = c.sp
	local began = S.releaseBegan[col]
	S.releaseBegan[col] = nil
	-- the hold is charged on the server's clock, the fork-tower way: a client that fires the
	-- prompt with no hold waits the full ReleaseHoldSeconds before anything happens
	local remaining = Config.Economy.ReleaseHoldSeconds - (tick() - (began or tick()))
	local function finish()
		if sessions[S.plr] ~= S or S.raid then return end
		local cage = S.profile.cages[col]
		if cage.sp ~= sp then return end
		local value = Economy.sellValue(Config, sp)
		local jar = math.floor(cage.jar)
		S.profile.essence += value + jar
		S.profile.cages[col] = { sp = "", jar = 0 }
		buildCage(S, col)
		toast(S.plr, string.format("Released the %s: +%d Essence (+%d from its jar)", speciesName(sp), value, jar))
		requestSave(S)
		pushState(S)
	end
	if remaining <= 0 then finish() else task.delay(remaining, finish) end
end

function handleCollect(S: any, hit: Instance)
	if not S.loaded then return end
	local char = hit and hit.Parent
	local who = char and Players:GetPlayerFromCharacter(char)
	if not who then return end
	if who ~= S.plr then
		local last = S.visitorToast[who]
		if last == nil or tick() - last > 5 then
			S.visitorToast[who] = tick()
			toast(who, "This is " .. S.plr.Name .. "'s Collect Pad - yours is at your own lair")
		end
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	-- the pad also requires the root near it: a touch replicated from far away collects nothing
	if not hrp or flat(hrp.Position, S.lair.pad.Position) > W.PadReach then return end
	local now = tick()
	if S.raid or S.granting then
		-- lair actions wait until the raider is home (REVIEW-1: the pad paid out mid-raid)
		if now - (S.busyPadToastAt or -math.huge) > 5 then
			S.busyPadToastAt = now
			toast(who, if S.raid then "You are on a hunt - collect when you are home" else "Saving your steal - one moment")
		end
		return
	end
	if now - S.lastCollect < Config.Economy.CollectDebounceSeconds then return end
	S.lastCollect = now
	local total = Economy.collect(Config, S.profile)
	if total < 1 then
		if now - (S.emptyToastAt or -math.huge) > 5 then
			S.emptyToastAt = now
			toast(who, "Your jars are empty - cryptids fill them every second")
		end
		return
	end
	S.profile.essence += total
	if S.profile.tutorial == 1 then S.profile.tutorial = 2 end
	for col = 1, 9 do refreshCageLabel(S, col) end
	toast(who, string.format("+%d Essence collected", math.floor(total)))
	FxEvent:FireClient(who, "collect", { amount = math.floor(total) })
	requestSave(S)
	pushState(S)
end

function openHunt(S: any, who: Player)
	if not allowWho(who, "Prompt") then return end
	if not S.loaded then return end
	if who ~= S.plr then
		toast(who, "This is " .. S.plr.Name .. "'s Hunt Board - use the one at your own lair")
		return
	end
	FxEvent:FireClient(who, "openHunt")
	pushState(S)
end

--============================================================================ raids

local pocketUsed: { [number]: Player } = {}

local function claimPocket(plr: Player): number
	local s = 0
	while pocketUsed[s] do s += 1 end
	pocketUsed[s] = plr
	return s
end

local function sendHome(S: any)
	local char = S.plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and char.Parent then
		(hrp :: BasePart).CFrame = arrivalCFrame(S.plotIndex)
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = RAID.WalkSpeed end
end

-- The grab spot: the trusted position within Raid.GrabReach of the cage's anchor, exactly where its
-- prompt shows (Layout.inGrabReach, REVIEW-1.md B2).
local function atGrabSpot(R: any, col: number): boolean
	return Layout.inGrabReach(Config, col, R.trace.x, R.trace.z)
end

local endRaid -- forward

local function doGrab(S: any, R: any, col: number)
	local cage = R.cages[col]
	if not cage or cage.taken then return end
	cage.taken = true
	R.carrying = { col = col, sp = cage.sp, prize = cage.prize }
	R.holdBegan = {}
	R.holdAsked = {}
	R.pendingGrab = nil
	if cage.model then cage.model:Destroy() end
	local char = S.plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = RAID.CarrySpeed end
	if hrp then
		-- carried above the head: massless, welded, never colliding
		local m = (templates:FindFirstChild(cage.sp) :: Model):Clone()
		m.Name = "Carried"
		m:PivotTo(hrp.CFrame * CFrame.new(0, 4, 0) * CFrame.new(templateOffset[cage.sp]))
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.Massless = true
				d.CanCollide = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = d
				weld.Parent = d
			end
		end
		m.Parent = char
		R.carriedModel = m
	end
	toast(S.plr, string.format("Got the %s! Get back out the gate", speciesName(cage.sp)))
	FxEvent:FireClient(S.plr, "grab", { sp = cage.sp })
	pushState(S)
end

local function buildPocket(S: any, R: any)
	local frame = R.frame
	local camp = R.camp
	local folder = Instance.new("Folder")
	folder.Name = "Pocket_" .. R.slot
	local H = W.FenceHeight
	local yardZ0, yardZ1 = W.ApronDepth, W.ApronDepth + W.CellSize * (W.CageRow + 1)
	newPart("Floor", Vector3.new(W.PlotWidth, 1, yardZ1 - yardZ0), at(frame, W.PlotWidth / 2, -0.5, (yardZ0 + yardZ1) / 2),
		Color3.fromRGB(46, 40, 32), Enum.Material.Mud, folder)

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = folder
	local function run(name: string, c0: number, c1: number, row: number, parent: Instance, color: Color3, mat: Enum.Material)
		local r0 = Layout.cellRect(Config, c0, row)
		local r1 = Layout.cellRect(Config, c1, row)
		newPart(name, Vector3.new(r1.x1 - r0.x0, H, W.CellSize), at(frame, (r0.x0 + r1.x1) / 2, H / 2, (r0.z0 + r0.z1) / 2), color, mat, parent)
	end
	run("FrontL", 1, W.GateCol - 1, 0, walls, WOOD, Enum.Material.WoodPlanks)
	run("FrontR", W.GateCol + 1, W.YardCols, 0, walls, WOOD, Enum.Material.WoodPlanks)
	local gate = Layout.cellRect(Config, W.GateCol, 0)
	-- the antechamber's front wall carries the camp's name
	local sign = newPart("CampSign", Vector3.new(W.CellSize, H, 1), at(frame, (gate.x0 + gate.x1) / 2, H / 2, gate.z0 - 0.5), WOOD, Enum.Material.WoodPlanks, folder)
	label(sign, R.name .. "\nTier " .. R.tier .. " - " .. tierName(R.tier), rgb(Config.Tiers[R.tier].color), 7, 260, 120)
	newPart("SideL", Vector3.new(1, H, yardZ1 - yardZ0 - W.CellSize), at(frame, -0.5, H / 2, (yardZ0 + W.CellSize + yardZ1) / 2), WOOD, Enum.Material.WoodPlanks, walls)
	newPart("SideR", Vector3.new(1, H, yardZ1 - yardZ0 - W.CellSize), at(frame, W.PlotWidth + 0.5, H / 2, (yardZ0 + W.CellSize + yardZ1) / 2), WOOD, Enum.Material.WoodPlanks, walls)
	newPart("Back", Vector3.new(W.PlotWidth + 2, H, 1), at(frame, W.PlotWidth / 2, H / 2, yardZ1 + 0.5), WOOD, Enum.Material.WoodPlanks, walls)
	for _, line in camp.lines do
		local c = 1
		while c <= W.YardCols do
			if Layout.cellKind(camp, c, line.row) == "fence" then
				local c1 = c
				while c1 + 1 <= W.YardCols and Layout.cellKind(camp, c1 + 1, line.row) == "fence" do c1 += 1 end
				run("Line_" .. line.row .. "_" .. c, c, c1, line.row, walls, WOOD, Enum.Material.WoodPlanks)
				c = c1 + 1
			else
				c += 1
			end
		end
	end

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = folder
	for _, r in camp.rocks do
		local x, z = Layout.cellCenter(Config, r[1], r[2])
		newPart("Rock_" .. r[1] .. "_" .. r[2], Vector3.new(7.6, W.RockHeight, 7.6), at(frame, x, W.RockHeight / 2, z), STONE, Enum.Material.Slate, rocks)
	end

	local traps = Instance.new("Folder")
	traps.Name = "Traps"
	traps.Parent = folder
	R.laserParts = {}
	for _, t in Layout.traps(camp) do
		local e = buildTrapPart(t, frame, traps)
		if t.kind == "laser" then table.insert(R.laserParts, e) end
	end

	local cages = Instance.new("Folder")
	cages.Name = "Cages"
	cages.Parent = folder
	R.cages = {}
	for _, cg in camp.cages do
		local x, z = Layout.cellCenter(Config, cg.col, W.CageRow)
		local tier = Economy.tierOf(Config, cg.sp) :: number
		local tc = rgb(Config.Tiers[tier].color)
		local base = newPart("Cage_" .. cg.col, Vector3.new(7.6, 0.4, 7.6), at(frame, x, 0.2, z), Color3.fromRGB(60, 62, 70), Enum.Material.DiamondPlate, cages)
		local bars = newPart("Bars_" .. cg.col, Vector3.new(7.6, 8, 7.6), at(frame, x, 4.4, z), tc, Enum.Material.Glass, cages)
		bars.Transparency = 0.78
		local title = (if cg.prize then "PRIZE: " else "") .. speciesName(cg.sp)
		label(base, title .. "\n" .. tierName(tier), tc, 9.5, 220, 120)
		local model = spawnCryptid(cg.sp, at(frame, x, 0.4, z), cages, "Cryptid_" .. cg.col)
		local ax, az = Layout.grabAnchor(Config, cg.col)
		local anchor = newPart("GrabAnchor_" .. cg.col, Vector3.new(1, 1, 1), at(frame, ax, RAID.AnchorHeight, az), tc, Enum.Material.Neon, cages)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		-- the grab spot glows in the tier's colour: a tier-1 camp's Commons carry no aura, and nothing
		-- else showed where to stand (DESIGN.md section 13; REVIEW-1.md B3)
		Fx.attachGlow(anchor, tc, 1, 8)
		local pp = prompt(anchor, "Grab", "Grab", title, Config.Camps[R.tier].hold, RAID.GrabPromptDistance)
		R.cages[cg.col] = { col = cg.col, sp = cg.sp, prize = cg.prize, model = model }
		-- [5] The hold is charged on the server's clock AND at the grab spot (within Raid.GrabReach of
		-- the anchor: where this prompt shows, REVIEW-1.md B2). PromptButtonHoldBegan stamps the clock
		-- only while the TRUSTED position is at the spot, and the raid loop drops the stamp the tick it
		-- leaves. REVIEW-1: DESIGN.md's rule checked the cell only when
		-- the hold ended, so a prompt fired while still walking in completed on arrival after 0.10 s of
		-- standing against a 1.0 s hold.
		-- The trusted position is read once per raid tick, so an honest press on the frame the root
		-- steps into reach can arrive a tick before the server sees it there. Such a press is kept as
		-- a request for HoldAskSeconds and the hold starts from the tick the server sees the raider
		-- arrive: the time charged is still time at the spot.
		pp.PromptButtonHoldBegan:Connect(function(who)
			if who ~= S.plr or S.raid ~= R then return end
			if atGrabSpot(R, cg.col) then
				R.holdBegan[cg.col] = tick()
			else
				R.holdAsked[cg.col] = tick()
			end
		end)
		pp.Triggered:Connect(function(who)
			if not allowWho(who, "Prompt") then return end
			if who ~= S.plr then
				toast(who, "That camp belongs to another hunter")
				return
			end
			if S.raid ~= R then return end
			if R.carrying then
				toast(who, "You are already carrying a cryptid - get it out the gate")
				return
			end
			if not atGrabSpot(R, cg.col) then
				R.holdBegan[cg.col] = nil
				toast(who, "Stand right in front of the cage to grab it")
				return
			end
			local began = R.holdBegan[cg.col]
			R.holdBegan[cg.col] = nil
			local hold = Config.Camps[R.tier].hold
			local remaining = hold - (tick() - (began or tick()))
			if remaining <= 0 then
				doGrab(S, R, cg.col)
				return
			end
			-- a hold not (fully) seen by the server - fireproximityprompt, or a HoldBegan that never
			-- replicated - waits out the rest at the spot; stepping away cancels it (raid loop)
			if remaining >= 0.05 then toast(who, string.format("Hold still... %.1f s", remaining)) end
			local token = {}
			R.pendingGrab = { col = cg.col, token = token }
			task.delay(remaining, function()
				if S.raid ~= R or R.carrying or not R.pendingGrab or R.pendingGrab.token ~= token then return end
				R.pendingGrab = nil
				if not atGrabSpot(R, cg.col) then
					toast(who, "Stand right in front of the cage to grab it")
					return
				end
				doGrab(S, R, cg.col)
			end)
		end)
	end

	-- The cage row is walkable nowhere in the trusted map, so where a camp has no cage the row is
	-- solid brush. REVIEW-1: those cells were open floor (1 008-1 080 standing points per camp outside
	-- the trusted map); a raider who wandered in left the trusted position clamped at the row's edge
	-- and lagging behind on the way back out.
	local caged = {}
	for _, cg in camp.cages do caged[cg.col] = true end
	for col = 1, W.YardCols do
		if not caged[col] then
			local bx, bz = Layout.cellCenter(Config, col, W.CageRow)
			newPart("Brush_" .. col, Vector3.new(W.CellSize, W.RockHeight, W.CellSize), at(frame, bx, W.RockHeight / 2, bz),
				Color3.fromRGB(34, 52, 34), Enum.Material.Grass, cages)
		end
	end

	Fx.dustVolume(folder, Vector3.new(W.PlotWidth, 14, yardZ1 - yardZ0), at(frame, W.PlotWidth / 2, 7, (yardZ0 + yardZ1) / 2),
		Color3.fromRGB(170, 185, 200), 8)
	folder.Parent = pocketsFolder
	return folder
end

local function raidLoop(S: any, R: any)
	local ticks = 0
	while S.raid == R do
		task.wait(RAID.TickSeconds)
		if S.raid ~= R then break end
		local now = tick()
		local dt = now - R.lastTick
		R.lastTick = now
		local t = now - R.startTick
		for _, e in R.laserParts do
			paintLaser(e, Heist.laserState(Config, e.trap, t))
		end
		if t >= RAID.RaidSeconds then
			endRaid(S, "dawn")
			break
		end
		local char = S.plr.Character
		if char ~= R.char then
			endRaid(S, "abort")
			break
		end
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- WHERE THE CLIENT SAYS IT IS, and where a raider could actually have got to by now.
			-- Every rule below reads the second one.
			local lp = R.frame:PointToObjectSpace((hrp :: BasePart).Position)
			local speed = if R.carrying then RAID.CarrySpeed else RAID.WalkSpeed
			Trace2D.step(Config, R.trace, R.rects, lp.X, lp.Z, dt, speed, R.barriers)
			R.info:SetAttribute("TrustedX", R.trace.x)
			R.info:SetAttribute("TrustedZ", R.trace.z)
			-- along every leg of the tick's path: a slide bends it (REVIEW-1.md B1)
			local trap = Heist.caughtPath(Config, Layout, R.camp, R.trace.path, R.lastT, t)
			R.lastT = t
			if trap then
				endRaid(S, trap.kind)
				break
			end
			-- a hold in progress is forfeited by leaving the grab spot, even for one tick
			for col, _ in R.holdBegan do
				if not atGrabSpot(R, col) then R.holdBegan[col] = nil end
			end
			-- a press made just before the server saw the raider arrive starts its hold now
			for col, askedAt in R.holdAsked do
				if atGrabSpot(R, col) then
					if R.holdBegan[col] == nil then R.holdBegan[col] = now end
					R.holdAsked[col] = nil
				elseif now - askedAt > RAID.HoldAskSeconds then
					R.holdAsked[col] = nil
				end
			end
			if R.pendingGrab and not atGrabSpot(R, R.pendingGrab.col) then
				R.pendingGrab = nil
				toast(S.plr, "You stepped away from the cage - hold again to grab")
			end
			-- out through the GATE only (Layout.escaped, REVIEW-1 R1-5)
			if R.carrying and Layout.escaped(Config, R.trace.x, R.trace.z) then
				endRaid(S, "escape")
				break
			end
			-- REVIEW-1.md B1, the backstop: the character has been where the trusted position cannot
			-- follow for StuckSeconds (a noclip, or a freeze the slide could not undo). It is put back
			-- where the server last saw it, in standable space, and walks on from there. Without this a
			-- raider could stand at the cage, holding Grab, refused for the rest of the raid.
			if R.trace.stuck >= RAID.StuckSeconds then
				local sx, sz = Trace2D.settle(Config, R.rects, R.barriers, R.trace.x, R.trace.z)
				local root = hrp :: BasePart
				local at = R.frame:PointToWorldSpace(Vector3.new(sx, W.RootHeight, sz))
				root.CFrame = CFrame.new(at) * (root.CFrame - root.CFrame.Position)
				R.trace.stuck = 0
				if now - (R.pulledToastAt or -math.huge) > 5 then
					R.pulledToastAt = now
					toast(S.plr, "You were pulled back to where the server last saw you - walk on from there")
				end
			end
		else
			R.lastT = t
		end
		ticks += 1
		if ticks % 5 == 0 then pushState(S) end
	end
end

-- [5] The grant, its Heat and the Journal entry are ONE write. In a saving session a failed write
-- undoes the grant and refunds the permit, so a grant can never be redeemed without being persisted.
--
-- The write YIELDS, and the game goes on around it: jars fill, a poacher walks. So a failed write
-- undoes exactly the four things this grant did and nothing else. REVIEW-1: restoring a snapshot
-- taken before the write wiped every jar that filled meanwhile (and, before `granting` existed,
-- the permit of a hunt started during the write). The caller holds S.granting for the duration.
local function grant(S: any, R: any): boolean
	local p = S.profile
	local sp = R.carrying.sp
	local oldRank = Economy.rank(Config, p.journal)
	local col = Economy.firstEmptyCage(Config, p)
	if not col then
		toast(S.plr, "No free cage - the " .. speciesName(sp) .. " slipped away")
		return false
	end
	local tierKey = "t" .. R.tier
	local heatBefore = p.heat[tierKey]
	local newInJournal = not Economy.journalHas(p.journal, sp)
	p.cages[col] = { sp = sp, jar = 0 }
	if newInJournal then table.insert(p.journal, sp) end
	p.heat[tierKey] = os.time() + Economy.heatSeconds(Config, R.tier)
	p.stats.steals += 1
	if S.canSave and not flush(S, false, true, true) then
		if p.cages[col].sp == sp then p.cages[col] = { sp = "", jar = 0 } end
		if newInJournal then
			local i = table.find(p.journal, sp)
			if i then table.remove(p.journal, i) end
		end
		p.heat[tierKey] = heatBefore
		p.stats.steals = math.max(0, p.stats.steals - 1)
		p.essence += R.permit
		if sessions[S.plr] == S then
			toast(S.plr, "Your steal could not be saved, so the " .. speciesName(sp) .. " went back and your permit was refunded")
		end
		return false
	end
	if sessions[S.plr] ~= S then return true end -- left while it saved: the write is what counts
	buildCage(S, col)
	walkInto(S, col, sp, W.Apron.Arrival.x, W.Apron.Arrival.z)
	refreshOffersAfterRank(S, oldRank)
	return true
end

-- reason: escape | laser | snare | dawn | leave (the player's own button) | abort (respawn, death,
-- character removed) | left (the player left the game)
function endRaid(S: any, reason: string)
	local R = S.raid
	if not R then return end
	S.raid = nil
	local plr = S.plr
	local p = S.profile
	if R.carriedModel then R.carriedModel:Destroy() end
	R.folder:Destroy()
	R.info:Destroy()
	pocketUsed[R.slot] = nil
	for _, c in R.conns do c:Disconnect() end
	if p.tutorial == 3 then p.tutorial = 4 end

	if reason == "escape" and R.carrying then
		-- home FIRST: the pocket is already gone, and the write below yields (REVIEW-1: the raider
		-- stood 4 036 studs out over nothing for as long as the write took)
		sendHome(S)
		S.granting = true
		pushState(S)
		local ok = grant(S, R)
		S.granting = false
		if sessions[plr] ~= S then return end
		if ok then
			toast(plr, string.format("You stole a %s!", speciesName(R.carrying.sp)))
			FxEvent:FireClient(plr, "escaped", { sp = R.carrying.sp })
		end
		requestSave(S)
		pushState(S)
		return
	elseif reason == "abort" then
		-- never silent (REVIEW-1): a respawn or a death ends a hunt, and the player is told
		toast(plr, "Your hunt ended when your character respawned - the permit is gone")
	elseif reason == "laser" then
		p.stats.caught += 1
		toast(plr, "Caught by a laser net - the permit is gone")
		FxEvent:FireClient(plr, "caught", { reason = reason })
	elseif reason == "snare" then
		p.stats.caught += 1
		toast(plr, "Caught in a snare - the permit is gone")
		FxEvent:FireClient(plr, "caught", { reason = reason })
	elseif reason == "dawn" then
		toast(plr, "Dawn broke - the camp woke up and you fled empty-handed")
		FxEvent:FireClient(plr, "caught", { reason = reason })
	elseif reason == "leave" then
		toast(plr, "You left the camp empty-handed")
	end
	if reason == "left" then return end
	if reason ~= "abort" then
		sendHome(S)
	end
	requestSave(S)
	pushState(S)
end

local function startRaid(S: any, tier: any)
	local plr = S.plr
	local p = S.profile
	if type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > #Config.Camps then
		toast(plr, "Pick a camp from 1 to " .. #Config.Camps)
		return
	end
	if S.raid then
		toast(plr, "You are already on a hunt")
		return
	end
	if S.granting then
		toast(plr, SAVING_STEAL)
		return
	end
	-- REVIEW-1: a Hunt + LeaveCamp loop built 79 pockets (491 Parts a second) in 10 s. A real raid
	-- lasts 15 s or more, so a cooldown between raid STARTS costs an honest player nothing.
	local since = tick() - (S.lastRaidStart or -math.huge)
	if since < RAID.RestartCooldownSeconds then
		toast(plr, string.format("You can hunt again in %d s", math.ceil(RAID.RestartCooldownSeconds - since)))
		return
	end
	if not Economy.campUnlocked(Config, tier, p.journal) then
		toast(plr, string.format("Camp %d is locked - own a %s cryptid first", tier, tierName(tier - 1)))
		return
	end
	local heatLeft = (p.heat["t" .. tier] or 0) - os.time()
	if heatLeft > 0 then
		toast(plr, string.format("Camp %d is on alert for %d s after your last steal", tier, heatLeft))
		return
	end
	local permit = Economy.permit(Config, tier)
	if p.essence < permit then
		toast(plr, string.format("The Camp %d permit costs %d Essence - you have %d", tier, permit, math.floor(p.essence)))
		return
	end
	if not Economy.firstEmptyCage(Config, p) then
		toast(plr, "Free a cage first - release one at its cage")
		return
	end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and char.Parent and hrp and hum and hum.Health > 0) then
		toast(plr, "Still respawning - try again in a moment")
		return
	end
	if flat(hrp.Position, S.lair.board.Position) > W.HuntStartReach then
		toast(plr, "Stand at your Hunt Board to start a hunt")
		return
	end

	p.essence -= permit
	S.lastRaidStart = tick()
	local slot = claimPocket(plr)
	local seed = campRandom:NextInteger(0, 2147483646)
	local camp = Layout.generateCamp(Config, Rng, seed, tier)
	local gx, gz = Layout.cellCenter(Config, W.GateCol, 0)
	local R: any = {
		tier = tier, seed = seed, camp = camp, slot = slot, frame = pocketFrame(slot), permit = permit,
		name = Layout.campName(Config, seed),
		-- the trusted position starts where the SERVER puts the raider, never where the client says
		trace = Trace2D.new(Config, gx, gz),
		startTick = tick(), lastTick = tick(), lastT = 0,
		carrying = nil, holdBegan = {}, holdAsked = {}, char = char, conns = {},
	}
	-- the trusted map, and the barriers across its corner squeezes (REVIEW-1.md A6)
	R.rects, R.barriers = Layout.freeRects(Config, camp)
	R.folder = buildPocket(S, R)

	-- [8] server-only raid facts for the headless checks and capture tooling
	local info = Instance.new("Folder")
	info.Name = tostring(plr.UserId)
	local phases = {}
	local prizeCol = 0
	for _, t in Layout.traps(camp) do
		if t.kind == "laser" then table.insert(phases, string.format("%d,%d:%.6f", t.col, t.row, t.phase)) end
	end
	for _, c in camp.cages do
		if c.prize then prizeCol = c.col end
	end
	info:SetAttribute("Tier", tier)
	info:SetAttribute("Seed", seed)
	info:SetAttribute("PrizeColumn", prizeCol)
	info:SetAttribute("LaserPhases", table.concat(phases, ";"))
	info:SetAttribute("Pocket", slot)
	info:SetAttribute("TrustedX", gx)
	info:SetAttribute("TrustedZ", gz)
	info.Parent = raidInfoFolder
	R.info = info

	S.raid = R
	if p.tutorial == 2 then p.tutorial = 3 end
	if S.buildMode then
		S.buildMode = false
		clearTiles(S)
	end
	local start = R.frame:PointToWorldSpace(Vector3.new(gx, W.RootHeight, gz))
	hrp.CFrame = CFrame.new(start, start + Vector3.new(0, 0, 1))
	hum.WalkSpeed = RAID.WalkSpeed
	table.insert(R.conns, hum.Died:Connect(function()
		if S.raid == R then endRaid(S, "abort") end
	end))
	toast(plr, string.format("%s - grab a cryptid and carry it out the gate", R.name))
	FxEvent:FireClient(plr, "raidStart", { tier = tier })
	requestSave(S)
	pushState(S)
	task.spawn(raidLoop, S, R)
end

--============================================================================ poachers

local function poacherModel(S: any): Model
	local m = Instance.new("Model")
	m.Name = "Poacher_" .. S.plotIndex
	local coat = Color3.fromRGB(70, 60, 44)
	local root = newPart("Body", Vector3.new(2, 3, 1.2), CFrame.new(0, 3.5, 0), coat, Enum.Material.Fabric, m)
	newPart("LegL", Vector3.new(0.8, 2, 0.8), CFrame.new(-0.5, 1, 0), Color3.fromRGB(40, 36, 30), Enum.Material.Fabric, m)
	newPart("LegR", Vector3.new(0.8, 2, 0.8), CFrame.new(0.5, 1, 0), Color3.fromRGB(40, 36, 30), Enum.Material.Fabric, m)
	newPart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 5.6, 0), Color3.fromRGB(190, 160, 130), Enum.Material.SmoothPlastic, m)
	local hat = newPart("Hat", Vector3.new(2, 0.4, 2), CFrame.new(0, 6.3, 0), Color3.fromRGB(30, 26, 22), Enum.Material.Fabric, m)
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	Fx.attachGlow(hat, AMBER, 1.5, 12)
	m.PrimaryPart = root
	return m
end

local function removePoacher(S: any)
	if S.poacherModel then
		S.poacherModel:Destroy()
		S.poacherModel = nil
	end
	S.poacher = nil
	S.warningAt = nil
	S.appearAt = nil
end

local function schedulePoacher(S: any, now: number)
	local span = Config.Poacher.IntervalMax - Config.Poacher.IntervalMin
	S.nextPoacherAt = now + Config.Poacher.IntervalMin + S.poacherRng:next() * span
end

local function tickPoacher(S: any, now: number)
	local p = S.profile
	if S.poacher == nil then
		if S.warningAt == nil then
			if now >= S.nextPoacherAt and Economy.cryptidCount(Config, p) >= Config.Poacher.MinCryptids then
				S.warningAt = now
				S.appearAt = now + Config.Poacher.WarningSeconds
				local line = string.format("A poacher is sneaking toward your lair - %d s! Traps catch poachers: use Build.", Config.Poacher.WarningSeconds)
				toast(S.plr, line)
				FxEvent:FireClient(S.plr, "poacherWarning", { seconds = Config.Poacher.WarningSeconds })
				pushState(S)
			end
		elseif now >= S.appearAt then
			local target = Economy.fullestCage(Config, p)
			local np = target and Poacher.new(Config, Layout, S.layout, target, S.poacherRng, now)
			if not np then
				removePoacher(S)
				schedulePoacher(S, now)
				return
			end
			S.poacher = np
			S.warningAt = nil
			local m = poacherModel(S)
			local x, z = Poacher.position(Config, Layout, np)
			m:PivotTo(at(plotFrame(S.plotIndex), x, 0, z) * CFrame.new(0, 3.5, 0))
			m.Parent = poachersFolder
			S.poacherModel = m
			pushState(S)
		end
		return
	end

	local np = S.poacher
	local ox, oz = Poacher.position(Config, Layout, np)
	local ev = Poacher.step(Config, Layout, Heist, S.layout, np, now)
	local x, z = Poacher.position(Config, Layout, np)
	if S.poacherModel then
		local frame = plotFrame(S.plotIndex)
		local pos = frame:PointToWorldSpace(Vector3.new(x, 3.5, z))
		local dx, dz = x - ox, z - oz
		if dx * dx + dz * dz > 1e-6 then
			local ahead = frame:PointToWorldSpace(Vector3.new(x + dx, 3.5, z + dz))
			S.poacherModel:PivotTo(CFrame.new(pos, ahead))
		else
			S.poacherModel:PivotTo(CFrame.new(pos) * S.poacherModel:GetPivot().Rotation)
		end
	end
	if ev.grabbed then
		local cage = p.cages[np.targetCol]
		local loot = if cage.sp ~= "" then Economy.theft(Config, cage.jar) else 0
		cage.jar -= loot
		np.loot = loot
		refreshCageLabel(S, np.targetCol)
		if loot > 0 then
			toast(S.plr, string.format("The poacher grabbed %d Essence from your %s jar - catch it before it leaves!", math.floor(loot), speciesName(cage.sp)))
			FxEvent:FireClient(S.plr, "poacherGrab", { amount = math.floor(loot) })
		end
		requestSave(S)
	end
	if ev.caught then
		local bounty = Economy.bounty(Config, Economy.lairRate(Config, p))
		p.essence += bounty
		p.stats.poachersCaught += 1
		if ev.returned then
			local cage = p.cages[np.targetCol]
			if cage.sp ~= "" then
				cage.jar = math.min(Economy.jarCap(Config, cage.sp), cage.jar + ev.returned)
			else
				p.essence += ev.returned
			end
		end
		local what = if ev.caught.kind == "laser" then "laser net" else "snare"
		toast(S.plr, string.format("Your %s caught the poacher! +%d Essence bounty%s", what, bounty,
			if ev.returned and ev.returned > 0 then " and the stolen Essence is back" else ""))
		FxEvent:FireClient(S.plr, "bounty", { amount = bounty })
		removePoacher(S)
		schedulePoacher(S, now)
		requestSave(S)
		pushState(S)
	elseif np.state == "gone" then
		if np.loot > 0 then
			toast(S.plr, string.format("The poacher got away with %d Essence. Force it through a laser net next time.", math.floor(np.loot)))
		else
			toast(S.plr, "The poacher left empty-handed")
		end
		removePoacher(S)
		schedulePoacher(S, now)
		pushState(S)
	end
end

--============================================================================ remotes in

local function sessionFor(plr: Player): any
	local S = sessions[plr]
	if not S then return nil end
	if not S.loaded then
		toast(plr, "Your lair is still loading")
		return nil
	end
	return S
end

HuntEvent.OnServerEvent:Connect(function(plr, tier)
	local S = sessionFor(plr)
	if not S or not allow(S, "Hunt") then return end
	startRaid(S, tier)
end)

LeaveEvent.OnServerEvent:Connect(function(plr)
	local S = sessionFor(plr)
	if not S or not allow(S, "LeaveCamp") then return end
	if not S.raid then
		toast(plr, "You are not on a hunt")
		return
	end
	endRaid(S, "leave")
end)

RerollEvent.OnServerEvent:Connect(function(plr)
	local S = sessionFor(plr)
	if not S or not allow(S, "Reroll") or not onHome(S) then return end
	local ok, left = Offers.canReroll(Config, S.rerollAt, tick())
	if not ok then
		toast(plr, "New sightings in " .. left .. " s")
		return
	end
	S.rerollAt = tick()
	S.offers = Offers.reroll(Config, S.offerRng, S.offers, Economy.rank(Config, S.profile.journal), S.profile.tutorial)
	for slot = 1, Config.Offers.Pedestals do refreshPedestal(S, slot) end
	toast(plr, "New sightings on your pedestals")
	pushState(S)
end)

ExpandEvent.OnServerEvent:Connect(function(plr)
	local S = sessionFor(plr)
	if not S or not allow(S, "Expand") or not onHome(S) then return end
	local p = S.profile
	local price = Economy.expansionPrice(Config, p.cagesUnlocked)
	if not price then
		toast(plr, "All nine cages are unlocked")
		return
	end
	if p.essence < price then
		toast(plr, string.format("The next cage costs %d Essence - you have %d", price, math.floor(p.essence)))
		return
	end
	p.essence -= price
	p.cagesUnlocked += 1
	buildCage(S, Config.World.CageOrder[p.cagesUnlocked])
	toast(plr, "Cage " .. p.cagesUnlocked .. " unlocked")
	requestSave(S)
	pushState(S)
end)

BuildEvent.OnServerEvent:Connect(function(plr, on)
	local S = sessionFor(plr)
	if not S or not allow(S, "BuildMode") then return end
	if type(on) ~= "boolean" then
		toast(plr, "Build mode is either on or off")
		return
	end
	-- REVIEW-1: every BuildMode(true) destroyed and rebuilt every tile (352 Parts a second under
	-- spam). Asking for the mode you are already in changes nothing, and switching ON is limited.
	if on == S.buildMode then
		pushState(S)
		return
	end
	if on then
		if not onHome(S) then return end
		local since = tick() - (S.buildOnAt or -math.huge)
		if since < Config.Traps.BuildOnCooldownSeconds then
			toast(plr, string.format("Build mode can switch on again in %d s", math.ceil(Config.Traps.BuildOnCooldownSeconds - since)))
			return
		end
		S.buildOnAt = tick()
	end
	S.buildMode = on
	if on then buildTiles(S) else clearTiles(S) end
	pushState(S)
end)

local function trapPrice(kind: string): number
	return if kind == "laser" then Config.Traps.LaserPrice else Config.Traps.SnarePrice
end

TrapEvent.OnServerEvent:Connect(function(plr, col, row, action)
	local S = sessionFor(plr)
	if not S or not allow(S, "TrapAction") then return end
	if not S.buildMode then
		toast(plr, "Turn on Build mode first")
		return
	end
	if not onHome(S) then return end
	local p = S.profile
	if action == "clear" then
		if type(col) ~= "number" or type(row) ~= "number" then
			toast(plr, "Pick a cell in your yard")
			return
		end
		local kind = Layout.clear(S.layout, col, row)
		if not kind then
			toast(plr, "Nothing to clear there")
			return
		end
		local refund = math.floor(trapPrice(kind) * Config.Traps.RefundFraction)
		p.essence += refund
		local s = Layout.trapString(kind, col, row)
		local i = table.find(p.traps, s)
		if i then table.remove(p.traps, i) end
		local k = Layout.key(col, row)
		local e = S.lair.trapParts[k]
		if e then e.part:Destroy() end
		S.lair.trapParts[k] = nil
		toast(plr, string.format("Cleared - %d Essence refunded", refund))
	elseif action == "laser" or action == "snare" then
		-- REVIEW-1.md A5: a trap dropped on the cell a poacher is walking caught every visit, and with
		-- the 100 % refund it cost nothing (5 of 5 visits, +180 each). Traps are set BEFORE a poacher
		-- comes, during its warning at the latest; clearing is still allowed.
		if S.poacher then
			toast(plr, "A poacher is in your yard - set traps before it comes, not under its feet")
			return
		end
		local ok, why = Layout.validatePlacement(Config, S.layout, col, row, action)
		if not ok then
			toast(plr, why :: string)
			return
		end
		local price = trapPrice(action)
		if p.essence < price then
			toast(plr, string.format("A %s costs %d Essence - you have %d", if action == "laser" then "laser net" else "snare", price, math.floor(p.essence)))
			return
		end
		local placed, why2, trap = Layout.place(Config, S.layout, col, row, action)
		if not placed then
			toast(plr, why2 :: string)
			return
		end
		if trap.kind == "laser" then
			trap.phase = S.laserRng:next() * (trap.on + trap.off)
		end
		p.essence -= price
		table.insert(p.traps, Layout.trapString(action, col, row))
		S.lair.trapParts[Layout.key(col, row)] = buildTrapPart(trap, plotFrame(S.plotIndex), S.lair.trapFolder)
		toast(plr, if action == "laser" then "Laser net placed - poachers crossing it while it burns are caught" else "Snare placed - poachers walk around it")
	else
		toast(plr, "Unknown trap")
		return
	end
	requestSave(S)
	pushState(S)
end)

--============================================================================ players

local function onCharacter(plr: Player, char: Model)
	local S = sessions[plr]
	if S and S.raid then
		endRaid(S, "abort") -- a respawn during a raid aborts it; the permit stays spent
	end
	-- [9] CharacterAdded fires while the character is UNPARENTED at the origin; the engine parents
	-- it and places it on the Trailhead one frame later, discarding any CFrame written before.
	-- Wait for the parent (bounded), then re-read everything the yield could have changed.
	-- WaitForChild is not this wait: on the server both children already exist when this fires.
	local frames = 0
	while char.Parent == nil and frames < 300 do
		task.wait(1 / 60)
		frames += 1
	end
	S = sessions[plr]
	if not S or plr.Character ~= char or char.Parent == nil or S.raid then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp then (hrp :: BasePart).CFrame = arrivalCFrame(S.plotIndex) end
	if hum then hum.WalkSpeed = RAID.WalkSpeed end
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	-- [9] the plot is claimed synchronously, BEFORE any yield, so a character that spawns during
	-- the DataStore load already has a home to be moved to
	local index = claimPlot(plr)
	if not index then
		toast(plr, "This server has no free lair")
		return
	end
	local S: any = {
		plr = plr, plotIndex = index, loaded = false, buckets = {}, releaseBegan = {}, visitorToast = {},
		lastCollect = -math.huge, buildMode = false, pending = false, offers = { "", "", "" },
	}
	sessions[plr] = S
	plotSigns[index].Text = plr.Name .. "'s Lair (loading)"
	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	plr.CharacterRemoving:Connect(function(char)
		local S2 = sessions[plr]
		if S2 and S2.raid and S2.raid.char == char then endRaid(S2, "abort") end
	end)
	-- A character that existed before this handler connected CharacterAdded (Studio play-solo joins
	-- before server scripts run) is sent home NOW, not after the load. REVIEW-1.md B4: placing it
	-- after the load moved a character that spawned during the load a second time, yanking a player
	-- who had started walking back to the marker (9.6 studs after a 0.6 s load, 35.2 after a retry).
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end

	local profile, canSave, banner, loadedData = loadProfile(plr) -- yields in Roblox
	if sessions[plr] ~= S or plr.Parent ~= Players then
		-- left during the load; PlayerRemoving already freed the plot. The lock the load just took is
		-- handed back, or the player's next server would play them unsaved for LockSeconds (REVIEW-1)
		if canSave then releaseLock(key(plr)) end
		return
	end
	S.profile = profile
	S.canSave = canSave
	S.banner = banner
	S.loadedData = loadedData
	S.layout = Layout.generateLair(Config, Rng, Layout.lairSeed(Config, plr.UserId))
	S.offerRng = Rng.new(Offers.seed(Config, sessionSalt, plr.UserId))
	S.laserRng = Rng.new((sessionSalt * 13 + index * 7919) % 2147483647)
	S.poacherRng = Rng.new((sessionSalt * 17 + (plr.UserId % 999983) * 7919) % 2147483647)

	-- [6] saved traps replay through the CURRENT rules; what no longer fits is refunded, once
	-- Only the first string naming a cell is ever refunded (Layout.reconcile, REVIEW-1 R1-1)
	local kept, removed, refundable = Layout.reconcile(Config, S.layout, profile.traps)
	if #removed > 0 then
		for _, s in refundable do
			local kind = Layout.parseTrap(s)
			if kind then profile.essence += math.floor(trapPrice(kind) * Config.Traps.RefundFraction) end
		end
		profile.traps = kept
		requestSave(S)
	end
	for _, t in Layout.traps(S.layout) do
		if t.kind == "laser" then t.phase = S.laserRng:next() * (t.on + t.off) end
	end

	S.offers = Offers.initial(Config, S.offerRng, Economy.rank(Config, profile.journal), profile.tutorial)
	S.sessionStart = tick()
	S.nextPoacherAt = S.sessionStart + Config.Poacher.FirstAfterSeconds
	buildLair(S)
	S.savedFingerprint = if canSave then fingerprint(profile) else nil
	S.loaded = true
	plotSigns[index].Text = plr.Name .. "'s Lair"
	pushState(S)
	if not canSave then toast(plr, banner :: string) end
	if #refundable > 0 then
		toast(plr, #refundable .. " saved trap(s) no longer fit your lair and were refunded")
	end
	if banner == LOCKED then
		task.spawn(recheckLock, S)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- anyone already in when this script finished loading (Studio play-solo joins before server scripts)
for _, plr in Players:GetPlayers() do
	if sessions[plr] == nil then task.spawn(onPlayerAdded, plr) end
end

Players.PlayerRemoving:Connect(function(plr)
	local S = sessions[plr]
	if not S then return end
	S.closing = true -- no write of this session locks the record again (REVIEW-1.md A3)
	if S.raid then endRaid(S, "left") end -- leaving mid-raid grants nothing
	removePoacher(S)
	if S.loaded then flush(S, true, nil, true) end
	if S.lair then S.lair.folder:Destroy() end
	plotSigns[S.plotIndex].Text = "Empty lair"
	plotOwner[S.plotIndex] = nil
	sessions[plr] = nil
end)

game:BindToClose(function()
	for _, S in sessions do
		S.closing = true
		if S.loaded then flush(S, true, nil, true) end
	end
end)

--============================================================================ loops

-- income: jars fill once a second; jar growth never marks a save (it is recomputed from savedAt)
task.spawn(function()
	local last = tick()
	while true do
		task.wait(Config.Economy.IncomeTickSeconds)
		local now = tick()
		local dt = now - last
		last = now
		for _, S in sessions do
			if S.loaded then
				for col = 1, 9 do
					local c = S.profile.cages[col]
					if c.sp ~= "" then
						c.jar = Economy.accrue(Config, c.sp, c.jar, dt)
						refreshCageLabel(S, col)
					end
				end
				pushState(S)
			end
		end
	end
end)

-- lair nets and poachers, ten times a second
task.spawn(function()
	while true do
		task.wait(Config.Poacher.TickSeconds)
		local now = tick()
		for _, S in sessions do
			if S.loaded and S.lair then
				for _, e in S.lair.trapParts do
					if e.light then paintLaser(e, Heist.laserState(Config, e.trap, now)) end
				end
				tickPoacher(S, now)
			end
		end
	end
end)

-- coalesced writes: at most one per player per FlushTickSeconds
task.spawn(function()
	while true do
		task.wait(Config.Save.FlushTickSeconds)
		for _, S in sessions do
			if S.loaded and S.pending then flush(S, false) end
		end
	end
end)

-- the autosave renews the session lock
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, S in sessions do
			if S.loaded then flush(S, false, true) end
		end
	end
end)

print(string.format("[Cryptid] Steal a Cryptid server ready - %d plots, %d species, %d camp tiers.", plotCount, #Config.Species, #Config.Camps))
