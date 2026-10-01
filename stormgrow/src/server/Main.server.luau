-- STORMGROW: MUTATION FARM — the authoritative server (ServerScriptService).
--
-- The server is the only writer. It builds the valley, owns every profile, runs the global weather's strike
-- loop, and validates every farm action (DESIGN.md §8, §10). Clients display attributes and ask; nothing a
-- client sends is trusted:
--   * a tap reaches the server as Tap(slot, key) from the client, which picked the tile the player SEES under
--     their thumb (Pick.luau, REVIEW-1 B1); the server re-checks the farm owner, a 40-stud distance, the action
--     rate and ripeness on its own clock, and every refusal says why (a tap from too far says "Walk closer");
--   * marks and Almanac entries come ONLY from the strike loop below (Mutation.strikeTick), at the server's
--     own tick, with an unseeded Random that nothing public seeds (DESIGN.md §8.2);
--   * the session lock carries an owner token on every write, the release included (fork-tower REVIEW-4 §10).
-- Every refusal tells the player why (checklist: no silent no-ops).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Weather = require(ReplicatedStorage:WaitForChild("Weather"))
local Mutation = require(ReplicatedStorage:WaitForChild("Mutation"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Profile = require(ReplicatedStorage:WaitForChild("Profile"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Farm = require(ReplicatedStorage:WaitForChild("Farm"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

local F, W, M, B, S = Config.Farm, Config.Weather, Config.Marks, Config.Board, Config.Save

-- The first frame is already band 1 (Fx.Presets.Farm == Config.Env.Bands[1]); the client's sky takes over.
Fx.applyLighting(Fx.Presets.Farm)

--==================================================================================== the clock
-- Unix time at boot plus the difference of tick(). Only differences of tick() are used, so its time zone
-- never matters; in robloxemu tick() is the virtual clock, so a headless check can fast-forward the
-- weather and growth. ClockOffsetSeconds is 0 in src/ (a shots-place knob, DESIGN.md §14.2) and sits
-- inside `now`, so server and clients always agree on the weather.
local unixAtBoot = os.time()
local tickAtBoot = tick()
local function serverNow(): number
	return unixAtBoot + (tick() - tickAtBoot) + (W.ClockOffsetSeconds or 0)
end

local byId = {}
for _, c in Config.Crops do byId[c.id] = c end
local bragBand = Config.Env.Bands[EnvBands.indexOf(Config.Env.Bands, Config.Env.BragBandId) :: number]
local BRAG_AT = bragBand.from

-- The one unpredictable thing in the game: which ripe crop the next bolt picks. Unseeded (Roblox seeds it
-- from entropy), never replicated, drawn at the tick. Nothing visible is derived from it before a strike.
local strikeRng = Random.new()
local function strikeRand(): number
	return strikeRng:NextNumber()
end

--================================================================================= the valley
local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then (p :: any)[k] = v end
	end
	p.Parent = parent
	return p :: BasePart
end

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function nameOfPlayer(plr: Player): string
	local dn = (plr :: any).DisplayName
	if type(dn) == "string" and dn ~= "" then return dn end
	return plr.Name
end

-- MarketPad FIRST under Workspace: the engine's fallback when no farm pad is enabled for a player
-- (robloxemu/SPAWN-ORDER.md: the first enabled SpawnLocation in a depth-first walk).
local marketPad = part({
	ClassName = "SpawnLocation", Name = "MarketPad", Size = Vector3.new(6, 1, 6),
	CFrame = CFrame.new(0, 0.5, -14), Color = Color3.fromRGB(200, 180, 120), Material = Enum.Material.WoodPlanks,
}, workspace) :: SpawnLocation
marketPad.Neutral = true
marketPad.Enabled = true
marketPad.Duration = 0

local valley = Instance.new("Folder")
valley.Name = "Valley"
valley.Parent = workspace

part({
	Name = "Ground", Size = Vector3.new(F.WallRadius * 2 + 60, 2, F.WallRadius * 2 + 60),
	CFrame = CFrame.new(0, F.GroundY - 1, 0), Color = c3(Config.Env.Bands[1].ground), Material = Enum.Material.Grass,
}, valley)
part({
	Name = "MarketSquare", Size = Vector3.new(F.MarketRadius * 2, 0.4, F.MarketRadius * 2),
	CFrame = CFrame.new(0, F.GroundY + 0.2, 0), Color = Color3.fromRGB(190, 175, 150), Material = Enum.Material.Cobblestone,
}, valley)

-- The valley wall: invisible, so a hazard's knock can never push anyone out of the world. The hills
-- beyond it are client scenery.
do
	local wall = Instance.new("Folder")
	wall.Name = "ValleyWall"
	wall.Parent = valley
	local n = F.WallSegments
	local len = 2 * math.pi * F.WallRadius / n + 2
	for i = 1, n do
		local a = (i - 0.5) / n * 2 * math.pi
		local x, z = math.sin(a) * F.WallRadius, math.cos(a) * F.WallRadius
		part({
			Name = "Wall_" .. i, Size = Vector3.new(len, 80, 2),
			CFrame = CFrame.lookAt(Vector3.new(x, 40, z), Vector3.new(0, 40, 0)),
			Transparency = 1, CanCollide = true, CanQuery = false, CanTouch = false,
		}, wall)
	end
end

-- The Almanac board on the market square, facing the spawn side. Each player's view is a client-side
-- SurfaceGui on this part (Hud.client), so two players at the board can see different views.
local boardPart = part({
	Name = "AlmanacBoard", Size = Vector3.new(18, 11, 1),
	CFrame = CFrame.lookAt(Vector3.new(0, 7, 16), Vector3.new(0, 7, -14)),
	Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood,
}, valley)
for side = -1, 1, 2 do
	part({
		Name = "BoardPost", Size = Vector3.new(1, 13, 1), CFrame = CFrame.new(side * 8.5, 6.5, 16.8),
		Color = Color3.fromRGB(90, 65, 45), Material = Enum.Material.Wood,
	}, valley)
end
local boardPrompt = Instance.new("ProximityPrompt")
boardPrompt.Name = "BoardPrompt"
boardPrompt.ActionText = "Friends / Everyone"
boardPrompt.ObjectText = "🏆 Almanac board"
boardPrompt.HoldDuration = 0
boardPrompt.MaxActivationDistance = B.PromptReach -- where its rows read >= 12 pt on a phone (REVIEW-1 B5)
boardPrompt.RequiresLineOfSight = false
boardPrompt.Parent = boardPart

-- ── the six farms ─────────────────────────────────────────────────────────────────────────────────
local farmsFolder = Instance.new("Folder")
farmsFolder.Name = "Farms"
farmsFolder.Parent = workspace

local pads: { [number]: SpawnLocation } = {}
local hitboxes: { [number]: { [string]: BasePart } } = {}
local signs: { [number]: TextLabel } = {}

local function localCF(k: number, lx: number, y: number, lz: number, faceLx: number?, faceLz: number?): CFrame
	local x, z = Farm.toWorld(k, lx, lz, F)
	if faceLx ~= nil and faceLz ~= nil then
		local fx, fz = Farm.toWorld(k, faceLx, faceLz, F)
		return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(fx, y, fz))
	end
	-- aligned with the farm: local +z (outward) is the part's LookVector
	local ox, oz = Farm.toWorld(k, lx, lz + 1, F)
	return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(ox, y, oz))
end

for k = 1, F.Slots do
	local model = Instance.new("Model")
	model.Name = "Farm_" .. k
	model:SetAttribute("Slot", k)

	-- porch strip and the dirt bed the fields sit in
	part({ Name = "Porch", Size = Vector3.new(F.Width, 0.4, F.PorchDepth),
		CFrame = localCF(k, 0, F.GroundY + 0.2, F.PorchDepth / 2), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.WoodPlanks }, model)
	part({ Name = "Bed", Size = Vector3.new(F.Width, 0.2, F.Depth - F.PorchDepth),
		CFrame = localCF(k, 0, F.GroundY + 0.1, (F.Depth + F.PorchDepth) / 2), Color = Color3.fromRGB(120, 95, 60), Material = Enum.Material.Ground }, model)

	-- fence: left, right, back (the porch side is open)
	local fenceColor = Color3.fromRGB(235, 225, 205)
	part({ Name = "FenceLeft", Size = Vector3.new(0.6, 3, F.Depth), CFrame = localCF(k, -F.Width / 2, F.GroundY + 1.5, F.Depth / 2),
		Color = fenceColor, Material = Enum.Material.Wood }, model)
	part({ Name = "FenceRight", Size = Vector3.new(0.6, 3, F.Depth), CFrame = localCF(k, F.Width / 2, F.GroundY + 1.5, F.Depth / 2),
		Color = fenceColor, Material = Enum.Material.Wood }, model)
	part({ Name = "FenceBack", Size = Vector3.new(F.Width, 3, 0.6), CFrame = localCF(k, 0, F.GroundY + 1.5, F.Depth),
		Color = fenceColor, Material = Enum.Material.Wood }, model)

	-- The owner's name plate, low on the porch's front edge, facing the market. (REVIEW-1: it stood 4.5-7.5 studs up on
	-- a post right behind the spawn pad, and from a camera behind a farmer on the pad it hid all of field 1 at a
	-- 15-20 degree pitch and the ground around their feet at most pitches; check_stormgrow_aim part 4.)
	local signPart = part({ Name = "Sign", Size = Vector3.new(12, 1.2, 0.4),
		CFrame = localCF(k, 0, F.GroundY + 0.4 + 0.6, 0.3, 0, -10), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood }, model)
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "SignGui"
		sg.Face = Enum.NormalId.Front
		sg.PixelsPerStud = 40
		sg.Parent = signPart
		local label = Instance.new("TextLabel")
		label.Name = "Owner"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 245, 220)
		label.Text = "🌾 Free farm"
		label.Parent = sg
		signs[k] = label
	end

	-- the pad: a real SpawnLocation, enabled only while the farm is claimed, facing field 1
	local fx, fz = Farm.fieldCentre(k, 1, F)
	local px, pz = Farm.padPos(k, F)
	local pad = part({ ClassName = "SpawnLocation", Name = "FarmPad_" .. k, Size = Vector3.new(F.PadSize, 1, F.PadSize),
		CFrame = CFrame.lookAt(Vector3.new(px, F.GroundY + 0.5, pz), Vector3.new(fx, F.GroundY + 0.5, fz)),
		Color = Color3.fromRGB(170, 130, 80), Material = Enum.Material.WoodPlanks }, model) :: SpawnLocation
	pad.Neutral = true
	pad.Duration = 0
	pad.Enabled = false
	pads[k] = pad

	-- The Almanac board on the porch: the standard wants the board NEAR SPAWN, and a farmer spawns here, ~105
	-- studs from the market board. Since REVIEW-1 B5 it stands 15 studs from the pad (it stood 36 away, with rows
	-- of 5.6 pt on a phone), between field 1's column and field 3's, turned to the spawn camera, and shows the top
	-- five in rows that read >= 12 pt from its prompt. It hides no field-1 tile from the pad (check_stormgrow_board
	-- part 6). Each client draws its own view on its own porch's board.
	local PB = B.Porch
	local bx, bz = Farm.toWorld(k, PB.X, PB.Z, F)
	local tx, tz = Farm.toWorld(k, PB.FaceX, PB.FaceZ, F)
	local by = F.GroundY + 0.4 + PB.Height / 2
	local farmBoard = part({ Name = "FarmBoard_" .. k, Size = Vector3.new(PB.Width, PB.Height, 0.4),
		CFrame = CFrame.lookAt(Vector3.new(bx, by, bz), Vector3.new(tx, by, tz)),
		Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood }, model)
	local fp = Instance.new("ProximityPrompt")
	fp.Name = "BoardPrompt"
	fp.ActionText = "Friends / Everyone"
	fp.ObjectText = "🏆 Almanac board"
	fp.HoldDuration = 0
	fp.MaxActivationDistance = B.PromptReach
	fp.RequiresLineOfSight = false
	fp.Parent = farmBoard

	-- 54 soil plates and 54 tile parts. A tile part is the soil plate's invisible twin: it carries the tile's public
	-- attributes (what the clients draw) and nothing else. It is NOT a click target: until REVIEW-1 it was a 6-stud
	-- invisible ClickDetector column, and Roblox delivers a click to the first queryable part on the ray, so from
	-- in front of a field two taps in three reached the tile in FRONT of the one tapped (B1). Taps are now picked
	-- on the client against what is drawn (Pick.luau) and sent as Tap(slot, key).
	hitboxes[k] = {}
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model
	for f = 1, F.Fields do
		for t = 1, F.TilesPerField do
			local lx, lz = Farm.tileLocal(f, t, F)
			local key = Farm.tileKey(f, t)
			part({ Name = "Soil_" .. key, Size = Vector3.new(F.SoilSize, F.SoilHeight * 0.6, F.SoilSize),
				CFrame = localCF(k, lx, F.GroundY + F.SoilHeight * 0.3, lz), Color = Color3.fromRGB(95, 70, 45),
				Material = Enum.Material.Ground, CanQuery = false }, tiles)
			local hb = part({ Name = "Tile_" .. key, Size = Vector3.new(F.SoilSize, F.SoilHeight * 0.6, F.SoilSize),
				CFrame = localCF(k, lx, F.GroundY + F.SoilHeight * 0.3, lz), Transparency = 1, CanCollide = false,
				CanQuery = false, CanTouch = false }, tiles)
			hb:SetAttribute("Farm", k)
			hb:SetAttribute("Field", f)
			hb:SetAttribute("Tile", t)
			hb:SetAttribute("Key", key)
			hb:SetAttribute("Owner", 0)
			hb:SetAttribute("Crop", "")
			hb:SetAttribute("PlantedAt", 0)
			hb:SetAttribute("Grow", 0)
			hb:SetAttribute("Marks", 0)
			hb:SetAttribute("LastStrike", 0)
			hb:SetAttribute("Locked", f > 1)
			hitboxes[k][key] = hb
		end
	end
	model.Parent = farmsFolder
end

--=================================================================================== remotes
local remotes = Instance.new("Folder")
remotes.Name = "StormRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local ToastEvent = remote("Toast") -- server -> client: (text, kind?)
local BoardEvent = remote("Board") -- server -> client: (payload)
local TapEvent = remote("Tap") -- client -> server: (slot, key), the tile the player tapped
local SelectEvent = remote("Select") -- client -> server: (cropId)
local UnlockEvent = remote("Unlock") -- client -> server: ()
local BuyFieldEvent = remote("BuyField") -- client -> server: ()
remotes.Parent = ReplicatedStorage

local function toast(plr: Player, text: string, kind: string?)
	ToastEvent:FireClient(plr, text, kind or "info")
end
local function announce(text: string)
	ToastEvent:FireAllClients(text, "announce")
end

--================================================================================== sessions
type Session = {
	plr: Player, slot: number?, token: string, profile: any, loaded: boolean, canSave: boolean,
	lastAction: number, lastRateToast: number, board: any, boardMode: string, friendSet: any,
	friendsAt: number, actionSeq: number, leaving: boolean, lastTempestToast: number,
	-- REVIEW-1: what a read-only session keeps trying ("load" | "lock" | nil) and the lock it saw (A1, A2)
	recover: string?, lockSeen: any, recovering: boolean,
	-- the board value of the last profile that LANDED in the store (the board never runs ahead of it, A5), and a
	-- save asked for soon after a new Almanac entry
	savedValue: number, lastSaveAt: number, saveSoon: boolean, lastSoonAt: number,
	joinOrder: number, lastPromptAt: number, lastPromptToast: number, -- (A3: who waits longest; A6: the prompt)
}
local sessions: { [Player]: Session } = {}
local slotOwner: { [number]: Player? } = {}

local store = DataStoreService:GetDataStore(S.Store)
local boardStore = DataStoreService:GetOrderedDataStore(B.Store)

local function keyOf(plr: Player): string
	return "u_" .. tostring(plr.UserId)
end

local function publishPlayer(s: Session)
	local plr, p = s.plr, s.profile
	if p == nil then return end
	plr:SetAttribute("Coins", p.coins)
	plr:SetAttribute("Harvested", p.harvested)
	plr:SetAttribute("Fields", p.fields)
	plr:SetAttribute("Unlocked", p.unlocked)
	plr:SetAttribute("Selected", p.selected)
	plr:SetAttribute("AlmanacCount", p.almanacCount)
	plr:SetAttribute("AlmanacBits", Mutation.bits(p.almanac, Config.Crops))
	plr:SetAttribute("Harvests", p.harvests)
	plr:SetAttribute("CanSave", s.canSave)
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local coins = ls:FindFirstChild("Coins") :: IntValue?
		local alm = ls:FindFirstChild("Almanac") :: IntValue?
		if coins then coins.Value = p.coins end
		if alm then alm.Value = p.almanacCount end
	end
end

local function bump(s: Session)
	s.actionSeq += 1
	s.plr:SetAttribute("ActionSeq", s.actionSeq)
end

local function applyTile(slot: number, key: string, tile: any)
	local hb = hitboxes[slot] and hitboxes[slot][key]
	if hb == nil then return end
	if tile == nil then
		hb:SetAttribute("Crop", "")
		hb:SetAttribute("PlantedAt", 0)
		hb:SetAttribute("Grow", 0)
		hb:SetAttribute("Marks", 0)
	else
		local c = byId[tile.c]
		hb:SetAttribute("Crop", tile.c)
		hb:SetAttribute("PlantedAt", tile.at)
		hb:SetAttribute("Grow", if c then c.grow else 0)
		hb:SetAttribute("Marks", tile.m)
	end
end

local function applyFarm(s: Session)
	local slot = s.slot
	if slot == nil or s.profile == nil then return end
	for key, hb in hitboxes[slot] do
		hb:SetAttribute("Owner", s.plr.UserId)
		hb:SetAttribute("Locked", (hb:GetAttribute("Field") :: number) > s.profile.fields)
		applyTile(slot, key, s.profile.tiles[key])
	end
end

local function clearFarm(slot: number)
	for key, hb in hitboxes[slot] do
		hb:SetAttribute("Owner", 0)
		hb:SetAttribute("Locked", (hb:GetAttribute("Field") :: number) > 1)
		hb:SetAttribute("LastStrike", 0)
		applyTile(slot, key, nil)
	end
	signs[slot].Text = "🌾 Free farm"
	pads[slot].Enabled = false
	slotOwner[slot] = nil
end

--==================================================================================== saving
-- Every write carries the owner token and lands only while the record still carries it (fork-tower
-- REVIEW-4 §10). A session that finds its token gone stops writing and says so.
local function save(s: Session, release: boolean): boolean
	if not S.Enabled or not s.canSave or s.profile == nil then return false end
	local doc = Profile.serialize(s.profile)
	local lost, dropped = false, false
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(s.plr), function(old: any)
			lost, dropped = false, false
			if type(old) ~= "table" or type(old.session) ~= "table" or old.session.token ~= s.token then
				lost = true
				return nil
			end
			-- A save still queued when the farmer began to leave carries an OLDER copy than the leave's release, and
			-- would lock the record again for LockSeconds (the next join: 30 s of waiting, then read-only). Drop it.
			if s.leaving and not release then
				dropped = true
				return nil
			end
			doc.session = { token = s.token, lockUntil = if release then 0 else serverNow() + S.LockSeconds }
			return doc
		end)
	end)
	if not ok then
		warn("[StormGrow] save failed for " .. s.plr.Name .. ": " .. tostring(err))
		return false
	end
	if dropped then return false end
	if lost then
		s.canSave = false
		s.plr:SetAttribute("CanSave", false)
		warn("[StormGrow] " .. s.plr.Name .. "'s record is held by another session; this one stops saving")
		if s.plr.Parent == Players then
			toast(s.plr, "Your farm was opened in another server: progress here won't save", "warn")
		end
		return false
	end
	-- the board may now show what this save holds, and no more (REVIEW-1 A5)
	s.savedValue = math.max(s.savedValue, Board.encode(doc.almanacCount, doc.almanacAt, B))
	s.lastSaveAt = serverNow()
	return true
end

-- The Almanac board: only a session holding the lock writes, only upward, at most once per 30 s, and only what the
-- profile store already holds (REVIEW-1 A5: the board wrote the live count up to 60 s before the save did, so a
-- crash in between left the board ahead of the profile for good). A new entry asks for a save soon (strikeAll).
local function flushBoard(s: Session, force: boolean?)
	if not s.canSave or s.profile == nil then return end
	local value = s.savedValue
	local now = serverNow()
	if not Board.due(s.board, value, now, B, force) then return end
	local ok, err = pcall(function()
		boardStore:UpdateAsync(Board.keyOf(s.plr.UserId), Board.transform(value))
	end)
	if ok then
		Board.wrote(s.board, value, now)
	else
		warn("[StormGrow] board write failed: " .. tostring(err))
	end
end

local sendBoard: (s: Session) -> () -- below

local function finishLoad(s: Session)
	if s.plr.Parent ~= Players then
		-- left while loading: give the lock straight back
		if s.canSave then save(s, true) end
		return
	end
	s.loaded = true
	if s.slot then
		signs[s.slot].Text = "🌾 " .. nameOfPlayer(s.plr) .. "'s farm"
		applyFarm(s)
	end
	publishPlayer(s)
	s.plr:SetAttribute("ActionSeq", s.actionSeq)
	s.plr:SetAttribute("Loaded", true)
	task.spawn(sendBoard, s)
end

-- One attempt to load the record and lock it. -> verdict, the record as found:
--   "ok"     the record (or none yet: a new farmer) now carries this session's lock
--   "locked" another session's lock is still running; nothing was written
--   "newer"  a NEWER version of the game wrote it (REVIEW-1 A4): this server must never write it
--   "error"  the call failed
local function tryLoad(s: Session): (string, any)
	local seen, verdict = nil, "ok"
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(s.plr), function(old: any)
			seen, verdict = old, "ok"
			local now = serverNow()
			if Profile.isNewer(old) then
				verdict = "newer"
				return nil
			end
			if type(old) == "table" and type(old.session) == "table" and old.session.token ~= s.token
				and (tonumber(old.session.lockUntil) or 0) > now then
				verdict = "locked"
				return nil
			end
			local doc = Profile.serialize(Profile.normalize(old, Config, now))
			doc.session = { token = s.token, lockUntil = now + S.LockSeconds }
			return doc
		end)
	end)
	if not ok then return "error", err end
	return verdict, seen
end

-- the record loaded and locked: this session owns it now
local function adopt(s: Session, seen: any)
	local p, fixes = Profile.normalize(seen, Config, serverNow())
	for _, fix in fixes do warn("[StormGrow] " .. s.plr.Name .. ": " .. fix) end
	s.profile = p
	s.canSave = true
	s.recover = nil
	s.savedValue = Board.encode(p.almanacCount, p.almanacAt, B) -- (the store holds exactly this now)
end

-- read-only behind another session's lock: remember the lock as seen, to take it only if it runs out untouched
local function behindLock(s: Session, seen: any)
	s.profile = Profile.normalize(seen, Config, serverNow())
	s.canSave = false
	s.recover = "lock"
	s.lockSeen = { token = seen.session.token, lockUntil = tonumber(seen.session.lockUntil) }
end

-- give a lock straight back, the data untouched (a player who left while a background load took it)
local function release(s: Session)
	pcall(function()
		store:UpdateAsync(keyOf(s.plr), function(old: any)
			if type(old) ~= "table" or type(old.session) ~= "table" or old.session.token ~= s.token then return nil end
			old.session.lockUntil = 0
			return old
		end)
	end)
end

local function loadProfile(s: Session)
	local plr = s.plr
	if not S.Enabled then
		s.profile = Profile.default(Config)
		s.canSave = false
		finishLoad(s)
		return
	end
	local errors, waits, warned = 0, 0, false
	while true do
		local verdict, seen = tryLoad(s)
		if verdict == "ok" then
			adopt(s, seen)
			finishLoad(s)
			return
		elseif verdict == "newer" then
			-- shown as it is, never written: this server would drop what the newer version added
			s.profile = Profile.normalize(seen, Config, serverNow())
			s.canSave = false
			if plr.Parent == Players then
				toast(plr, "This server runs an older version of StormGrow: progress here won't save. Rejoin for the update", "warn")
			end
			finishLoad(s)
			return
		elseif verdict == "error" then
			warn("[StormGrow] load failed for " .. plr.Name .. ": " .. tostring(seen))
			errors += 1
			if errors > S.LoadRetries then
				-- An outage: a fresh farm that never writes over the real one, and the load keeps being retried in
				-- the background; when it lands, the real farm replaces this one (recover). (Until REVIEW-1 A2 a
				-- single failed call made the whole session a blank, read-only farm.)
				s.profile = Profile.default(Config)
				s.canSave = false
				s.recover = "load"
				if plr.Parent == Players then
					toast(plr, "Couldn't load your farm: this one won't save. Still trying in the background…", "warn")
				end
				finishLoad(s)
				return
			end
			task.wait(S.LoadRetrySeconds * 2 ^ (errors - 1)) -- 1, 2, 4 s
		else
			waits += 1
			if waits > S.LockRetries then
				behindLock(s, seen)
				if plr.Parent == Players then
					toast(plr, "Your farm is open in another server: progress here won't save", "warn")
				end
				finishLoad(s)
				return
			end
			if not warned and plr.Parent == Players then
				warned = true
				toast(plr, "Your farm is still open in another server: waiting for it to save…", "warn")
			end
			task.wait(S.LockRetrySeconds)
		end
		if plr.Parent ~= Players then return end
	end
end

-- A read-only session keeps trying (every S.RecoverSeconds, REVIEW-1 A1 and A2):
--   "load": the load failed; as soon as one succeeds, the REAL farm replaces the fresh one and saving starts;
--   "lock": another session's lock; once it has RUN OUT with the record untouched since (the same token and the
--     same lockUntil: nobody wrote), this session takes the lock and saves on, with what it played meanwhile (a
--     server that crashed never releases its lock). A lock that moved on, renewed or released after a last save,
--     is never taken: this copy predates that write.
local function recover(s: Session)
	local plr = s.plr
	if s.recover == "load" then
		local verdict, seen = tryLoad(s)
		if plr.Parent ~= Players or s.leaving or sessions[plr] ~= s then
			if verdict == "ok" then release(s) end
			return
		end
		if verdict == "ok" then
			adopt(s, seen)
			if s.slot then applyFarm(s) end
			publishPlayer(s)
			bump(s)
			toast(plr, "Your farm loaded: everything saves from here on", "good")
			task.spawn(sendBoard, s)
		elseif verdict == "locked" then
			behindLock(s, seen)
			if s.slot then applyFarm(s) end
			publishPlayer(s)
			toast(plr, "Your farm loaded, but it is open in another server: progress here won't save", "warn")
		elseif verdict == "newer" then
			s.profile = Profile.normalize(seen, Config, serverNow())
			s.recover = nil
			if s.slot then applyFarm(s) end
			publishPlayer(s)
			toast(plr, "This server runs an older version of StormGrow: progress here won't save. Rejoin for the update", "warn")
		end
		return
	end
	if s.recover ~= "lock" or s.lockSeen == nil then return end
	local seenLock = s.lockSeen
	local took, movedOn, wroteValue = false, false, 0
	local ok = pcall(function()
		store:UpdateAsync(keyOf(plr), function(old: any)
			took, movedOn = false, false
			if type(old) ~= "table" or type(old.session) ~= "table" or old.session.token ~= seenLock.token
				or tonumber(old.session.lockUntil) ~= seenLock.lockUntil or Profile.isNewer(old) then
				movedOn = true
				return nil
			end
			local now = serverNow()
			if (seenLock.lockUntil or 0) > now then return nil end -- still running: ask again later
			local doc = Profile.serialize(s.profile)
			doc.session = { token = s.token, lockUntil = now + S.LockSeconds }
			took = true
			wroteValue = Board.encode(doc.almanacCount, doc.almanacAt, B)
			return doc
		end)
	end)
	if not ok then return end
	if movedOn then
		s.recover = nil -- read-only for the rest of the session
	elseif took then
		s.canSave = true
		s.recover = nil
		s.savedValue = math.max(s.savedValue, wroteValue)
		s.lastSaveAt = serverNow()
		if plr.Parent ~= Players or s.leaving then
			release(s)
			return
		end
		publishPlayer(s)
		toast(plr, "Your farm is saving again: the other server's lock ran out", "good")
	end
end

--==================================================================================== joining
local joinCounter = 0
local function claimSlot(plr: Player): number?
	for k = 1, F.Slots do
		if slotOwner[k] == nil then
			slotOwner[k] = plr
			return k
		end
	end
	return nil
end

-- SPAWN-ORDER.md §3: the engine places the character on the enabled RespawnLocation one frame AFTER
-- CharacterAdded, and a CFrame written before that is thrown away. The pad is already the right place;
-- this only turns the player to face field 1, after the character is genuinely in the world.
local function onCharacter(plr: Player, char: Model)
	local frames = 0
	while char.Parent == nil and frames < 300 do
		task.wait(1 / 60)
		frames += 1
	end
	local s = sessions[plr]
	local slot = s and s.slot
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if slot == nil or root == nil or char.Parent == nil then return end
	local pad = pads[slot]
	local fx, fz = Farm.fieldCentre(slot, 1, F)
	local top = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
	root.CFrame = CFrame.lookAt(top, Vector3.new(fx, top.Y, fz))
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	joinCounter += 1
	local s: Session = {
		plr = plr, slot = nil, token = HttpService:GenerateGUID(false), profile = nil, loaded = false,
		canSave = false, lastAction = -math.huge, lastRateToast = -math.huge, board = Board.newWriter(),
		boardMode = "public", friendSet = nil, friendsAt = -math.huge, actionSeq = 0, leaving = false,
		lastTempestToast = -math.huge, recover = nil, lockSeen = nil, recovering = false, savedValue = 0,
		lastSaveAt = -math.huge, saveSoon = false, lastSoonAt = -math.huge, joinOrder = joinCounter, lastPromptAt = -math.huge,
		lastPromptToast = -math.huge,
	}
	sessions[plr] = s
	-- claim the farm and point the engine at its pad BEFORE any yield (the profile load yields)
	s.slot = claimSlot(plr)
	if s.slot then
		local pad = pads[s.slot]
		pad.Enabled = true
		plr.RespawnLocation = pad
		signs[s.slot].Text = "🌾 " .. nameOfPlayer(plr) .. "'s farm"
	end
	plr:SetAttribute("Slot", s.slot or 0)
	plr:SetAttribute("Loaded", false)
	plr:SetAttribute("ActionSeq", 0)

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local alm = Instance.new("IntValue")
	alm.Name = "Almanac"
	alm.Parent = ls
	ls.Parent = plr

	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then task.spawn(onCharacter, plr, plr.Character) end
	if s.slot == nil then
		toast(plr, "All six farms in this valley are taken: you get the next one that frees up", "warn")
	end
	task.spawn(loadProfile, s)
end

-- A farm that frees up goes to whoever has waited longest for one (REVIEW-1 A3): its pad becomes their spawn, its
-- sign their name, and they are moved onto it.
local function handOver(slot: number)
	local waiting: Session? = nil
	for _, o in sessions do
		if o.slot == nil and not o.leaving and o.plr.Parent == Players and (waiting == nil or o.joinOrder < (waiting :: Session).joinOrder) then
			waiting = o
		end
	end
	if waiting == nil then return end
	local s = waiting :: Session
	slotOwner[slot] = s.plr
	s.slot = slot
	local pad = pads[slot]
	pad.Enabled = true
	s.plr.RespawnLocation = pad
	s.plr:SetAttribute("Slot", slot)
	signs[slot].Text = "🌾 " .. nameOfPlayer(s.plr) .. "'s farm"
	if s.loaded then applyFarm(s) end
	toast(s.plr, string.format("A farm freed up: farm %d is yours now", slot), "good")
	local char = s.plr.Character
	if char then task.spawn(onCharacter, s.plr, char) end
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.leaving = true
	-- the farm is free at once, BEFORE the leave's writes yield (REVIEW-1 A3: a newcomer who joined inside the
	-- save's round trip found every farm taken and stayed farmless for the session)
	local slot = s.slot
	s.slot = nil
	if slot then
		clearFarm(slot)
		handOver(slot)
	end
	if s.loaded then
		save(s, true)
		flushBoard(s, true)
	end
	sessions[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	for _, s in sessions do
		if s.loaded then
			save(s, true)
			flushBoard(s, true)
		end
	end
end)

--================================================================================ farm actions
-- Shared gate for every farm action: loaded, and not faster than a human (tick(), never os.clock(): the
-- emulator's os.clock is CPU time, deep-vein Main.server.luau:1108).
local function gate(s: Session?): boolean
	if s == nil then return false end
	if not s.loaded or s.profile == nil then
		toast(s.plr, "🌱 Your farm is still loading…")
		return false
	end
	local t = tick()
	if t - s.lastAction < Config.Play.ActionMinSeconds then
		if t - s.lastRateToast >= Config.Play.RateToastSeconds then
			s.lastRateToast = t
			toast(s.plr, "Easy: one tap at a time")
		end
		return false
	end
	s.lastAction = t
	return true
end

local function onTileClick(plr: Player, hb: BasePart)
	local s = sessions[plr]
	if s == nil then return end
	local slot = hb:GetAttribute("Farm") :: number
	if slotOwner[slot] ~= plr then
		local owner = slotOwner[slot]
		if owner then
			toast(plr, "This is " .. nameOfPlayer(owner) .. "'s farm")
		elseif s.slot then
			toast(plr, "This farm is free: yours is the one with your name on the sign")
		else
			toast(plr, "All six farms are taken: rejoin to get one")
		end
		return
	end
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil or (root.Position - hb.Position).Magnitude > F.ServerReach then
		toast(plr, "Walk closer to tap this crop")
		return
	end
	if not gate(s) then return end
	local key = hb:GetAttribute("Key") :: string
	local p = s.profile
	local before = p.harvested
	local r = Economy.tap(p, Config, key, serverNow())
	if not r.ok then
		toast(plr, r.text)
		return
	end
	applyTile(slot, key, p.tiles[key])
	if r.text then toast(plr, r.text) end
	publishPlayer(s)
	bump(s)
	if before < BRAG_AT and p.harvested >= BRAG_AT then
		announce(bragBand.emoji .. " " .. nameOfPlayer(plr) .. "'s farm entered the " .. bragBand.name .. "!")
	end
end

-- A tap. Anything but a real tile's (slot, key) is junk from a hostile client and is dropped; a real tile goes
-- through every check above, each refusal saying why.
TapEvent.OnServerEvent:Connect(function(plr, slot, key)
	local byKey = hitboxes[slot] -- (junk of any type finds no tile here: check_stormgrow_wire fires 14 kinds)
	local hb = byKey and byKey[key]
	if hb == nil then return end
	onTileClick(plr, hb)
end)

SelectEvent.OnServerEvent:Connect(function(plr, id)
	local s = sessions[plr]
	if not gate(s) then return end
	local ok, text = Economy.select((s :: Session).profile, Config, id)
	if not ok then toast(plr, text) end
	publishPlayer(s :: Session)
end)

UnlockEvent.OnServerEvent:Connect(function(plr)
	local s = sessions[plr]
	if not gate(s) then return end
	local ok, text = Economy.unlock((s :: Session).profile, Config)
	toast(plr, text, if ok then "good" else "info")
	if ok then
		publishPlayer(s :: Session)
		bump(s :: Session)
	end
end)

BuyFieldEvent.OnServerEvent:Connect(function(plr)
	local s = sessions[plr] :: Session
	if not gate(s) then return end
	local ok, text = Economy.buyField(s.profile, Config)
	toast(plr, text, if ok then "good" else "info")
	if ok then
		applyFarm(s)
		publishPlayer(s)
		bump(s)
	end
end)

--=============================================================================== the weather
-- The strike loop: at every strike tick of the global clock, every loaded farm's ripe crops that lack the
-- event's mark roll for it. Ticks are processed at their own time T (a crop ripe at T), in order, and a
-- tick more than 30 s late (a long server hitch) is skipped rather than replayed onto today's farm.
local function strikeAll(kind: string, T: number)
	for plr, s in sessions do
		if s.loaded and s.slot and s.profile then
			local p = s.profile
			local struck = Mutation.strikeTick(p.tiles, kind, T, strikeRand, W, M, byId)
			if #struck > 0 then
				local newEntries, tempests = {}, 0
				for _, st in struck do
					local hb = hitboxes[s.slot][st.key]
					if hb then
						hb:SetAttribute("Marks", st.marks)
						hb:SetAttribute("LastStrike", T)
					end
					if Mutation.grant(p, st.crop, st.marks, T) then
						s.saveSoon = true -- the entry is the board's metric: save it soon, the board follows (A5)
						local crop = byId[st.crop]
						table.insert(newEntries, Mutation.emoji(st.marks, M) .. " " .. Mutation.variant(st.marks, Config.Variants) .. " " .. crop.name)
					end
					if st.marks == 7 then tempests += 1 end
				end
				publishPlayer(s)
				if #newEntries == 1 then
					toast(plr, "📖 NEW in the Almanac: " .. newEntries[1], "good")
				elseif #newEntries > 1 then
					toast(plr, string.format("📖 %d NEW in the Almanac: %s", #newEntries, table.concat(newEntries, ", ")), "good")
				end
				if tempests > 0 and T - s.lastTempestToast >= 30 then
					s.lastTempestToast = T
					local name = byId[struck[#struck].crop].name
					for _, st in struck do
						if st.marks == 7 then name = byId[st.crop].name end
					end
					announce("⚡❄️🌈 " .. nameOfPlayer(plr) .. " grew a TEMPEST " .. name .. "!")
				end
			end
		end
	end
end

task.spawn(function()
	local lastTick = math.floor(serverNow() / W.TickSeconds)
	while true do
		task.wait(0.2)
		local now = serverNow()
		local k = math.floor(now / W.TickSeconds)
		while lastTick < k do
			lastTick += 1
			local T = lastTick * W.TickSeconds
			local kind = Weather.isTick(T, W)
			if kind and now - T < 30 then
				strikeAll(kind, T)
			end
		end
	end
end)

-- The server clock for every client: growth bars, the forecast and the sky all read this.
workspace:SetAttribute("ServerNow", serverNow())
task.spawn(function()
	while true do
		task.wait(1 / Config.Play.ServerNowHz)
		workspace:SetAttribute("ServerNow", serverNow())
	end
end)

--================================================================================== autosave
task.spawn(function()
	while true do
		task.wait(S.AutosaveSeconds)
		for _, s in sessions do
			if s.loaded and not s.leaving then
				task.spawn(save, s, false)
			end
		end
	end
end)

-- read-only sessions keep trying (recover above)
task.spawn(function()
	while true do
		task.wait(S.RecoverSeconds)
		for _, s in sessions do
			if s.recover and s.loaded and not s.leaving and not s.recovering then
				task.spawn(function()
					s.recovering = true
					local ok, err = pcall(recover, s)
					if not ok then warn("[StormGrow] recover failed for " .. s.plr.Name .. ": " .. tostring(err)) end
					s.recovering = false
				end)
			end
		end
	end
end)

--===================================================================================== board
-- Public: GetSortedAsync(false, 100), top 10 shown, cached 60 s per server. Friends: on demand only,
-- GetFriendsAsync capped at 200, scored from players in this server plus a top-500 cache (5 pages of
-- 100, refreshed at most every 120 s). Names come from GetNameFromUserIdAsync, cached, never stored.
local names: { [number]: string } = {}
local nameFailedAt: { [number]: number } = {}
local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then return cached end
	local fallback = "Farmer " .. tostring(userId)
	-- a lookup that failed (a deleted account) is not retried for a while: until REVIEW-1 A6 every board view
	-- asked again, so prompt presses could spend the server's name-lookup budget
	local failedAt = nameFailedAt[userId]
	if failedAt and serverNow() - failedAt < B.NameRetrySeconds then return fallback end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		names[userId] = name
		nameFailedAt[userId] = nil
		return name
	end
	nameFailedAt[userId] = serverNow()
	return fallback
end

local publicCache = { rows = {}, at = -math.huge, failed = false, loaded = false }
local topCache = { list = {}, at = -math.huge, failed = false }

local function refreshPublic(force: boolean?)
	local now = serverNow()
	if not force and now - publicCache.at < B.PublicCacheSeconds then return end
	publicCache.at = now
	local ok, pageOrErr = pcall(function()
		local pages = boardStore:GetSortedAsync(false, B.PublicFetch)
		return pages:GetCurrentPage()
	end)
	if ok then
		publicCache.rows = Board.publicRows(pageOrErr, B.PublicShown)
		publicCache.failed = false
		publicCache.loaded = true
	else
		publicCache.failed = true
		warn("[StormGrow] board read failed: " .. tostring(pageOrErr))
	end
end

local function refreshTop()
	local now = serverNow()
	if now - topCache.at < B.TopCacheSeconds then return end
	topCache.at = now
	local ok, err = pcall(function()
		local list = {}
		local pages = boardStore:GetSortedAsync(false, 100)
		for i = 1, B.TopCachePages do
			for _, e in pages:GetCurrentPage() do
				local id = Board.userIdOf(e.key)
				if id then table.insert(list, { userId = id, value = e.value }) end
			end
			if pages.IsFinished or i == B.TopCachePages then break end
			pages:AdvanceToNextPageAsync()
		end
		topCache.list = list
	end)
	topCache.failed = not ok
	if not ok then warn("[StormGrow] top-500 read failed: " .. tostring(err)) end
end

local function loadFriends(s: Session): boolean
	if s.friendSet ~= nil then return s.friendSet ~= false end
	if serverNow() - s.friendsAt < 60 then return false end
	s.friendsAt = serverNow()
	local ok, setOrErr = pcall(function()
		local ids = {}
		local pages = Players:GetFriendsAsync(s.plr.UserId)
		while #ids < B.FriendsCap do
			for _, item in pages:GetCurrentPage() do
				table.insert(ids, item.Id)
				if #ids >= B.FriendsCap then break end
			end
			if pages.IsFinished or #ids >= B.FriendsCap then break end
			pages:AdvanceToNextPageAsync()
		end
		local set = Board.capFriends(ids, B.FriendsCap)
		return set
	end)
	if ok then
		s.friendSet = setOrErr
		return true
	end
	warn("[StormGrow] GetFriendsAsync failed: " .. tostring(setOrErr))
	return false
end

local function named(rows: { any }, me: number): { any }
	local out = {}
	for _, r in rows do
		table.insert(out, { rank = r.rank, name = nameOf(r.userId), count = r.count, you = r.userId == me })
	end
	return out
end

sendBoard = function(s: Session)
	if s.plr.Parent ~= Players or not s.loaded then return end
	local me = s.plr.UserId
	local count = s.profile and s.profile.almanacCount or 0
	local payload
	if s.boardMode == "friends" and loadFriends(s) then
		refreshTop()
		local sources = {}
		for _, other in sessions do
			if other.profile then
				table.insert(sources, { userId = other.plr.UserId, value = Board.encode(other.profile.almanacCount, other.profile.almanacAt, B) })
			end
		end
		for _, e in topCache.list do table.insert(sources, e) end
		local view = Board.friendsView(me, s.friendSet, sources, B.PublicShown)
		payload = {
			mode = "friends", title = "🏆 Almanac · your friends (top 500)",
			rows = named(view.rows, me), you = Board.youLine(view.rows, me, count),
			note = if view.empty then Board.TEXT.friendsEmpty elseif topCache.failed then Board.TEXT.publicFailed else nil,
		}
	else
		refreshPublic()
		local failedFriends = s.boardMode == "friends"
		payload = {
			mode = "public", title = "🏆 Almanac · everyone",
			rows = named(publicCache.rows, me), you = Board.youLine(publicCache.rows, me, count),
			note = if failedFriends then Board.TEXT.friendsFailed
				elseif publicCache.failed then Board.TEXT.publicFailed
				elseif #publicCache.rows == 0 then Board.TEXT.publicEmpty
				else nil,
		}
	end
	BoardEvent:FireClient(s.plr, payload)
end

-- the market board's prompt and every porch board's prompt toggle the same per-player view
local function onBoardPrompt(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if not s.loaded then
		toast(plr, "🌱 Your farm is still loading…")
		return
	end
	-- one switch a second (REVIEW-1 A6: 200 presses in a second sent 200 boards and 200 toasts); a press inside
	-- the cooldown says so, at most once per RateToastSeconds
	local t = tick()
	if t - s.lastPromptAt < B.PromptCooldownSeconds then
		if t - s.lastPromptToast >= Config.Play.RateToastSeconds then
			s.lastPromptToast = t
			toast(plr, "🏆 One moment: the board is switching")
		end
		return
	end
	s.lastPromptAt = t
	s.boardMode = if s.boardMode == "public" then "friends" else "public"
	toast(plr, if s.boardMode == "friends" then "🏆 Showing your friends" else "🏆 Showing everyone")
	task.spawn(sendBoard, s)
end
boardPrompt.Triggered:Connect(onBoardPrompt)
for k = 1, F.Slots do
	local fb = farmsFolder:FindFirstChild("Farm_" .. k):FindFirstChild("FarmBoard_" .. k)
	fb:FindFirstChildOfClass("ProximityPrompt").Triggered:Connect(onBoardPrompt)
end

-- board upkeep: writes (coalesced), then the public cache and every viewer, once a minute
task.spawn(function()
	local sinceRefresh = 0
	while true do
		task.wait(5)
		for _, s in sessions do
			if s.loaded and not s.leaving then
				-- a new entry's save; one that failed (the store is down) is tried again, every SoonSeconds at most
				local now = serverNow()
				if s.saveSoon and s.canSave and now - s.lastSaveAt >= S.SoonSeconds and now - s.lastSoonAt >= S.SoonSeconds then
					s.saveSoon = false
					s.lastSoonAt = now
					task.spawn(function()
						if not save(s, false) and s.canSave then s.saveSoon = true end
					end)
				end
				flushBoard(s)
			end
		end
		sinceRefresh += 5
		if sinceRefresh >= B.PublicCacheSeconds then
			sinceRefresh = 0
			refreshPublic(true)
			for _, s in sessions do
				if s.loaded and not s.leaving then task.spawn(sendBoard, s) end
			end
		end
	end
end)

print(string.format("[StormGrow] valley built: %d farms, %d tiles each; weather clock at %s (Unix %d)",
	F.Slots, F.Fields * F.TilesPerField, Weather.minuteLabel(serverNow(), W), math.floor(serverNow())))
