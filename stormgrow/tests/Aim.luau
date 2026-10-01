-- tests/Aim.luau — a TEST helper, never bundled (wrap.py reads src/ only): a player's thumb on a phone screen.
--
-- REVIEW-1 B1 found that no gate aimed: every check fired the tile it MEANT straight into the server, so a tap
-- that Roblox would have delivered to a different tile (an invisible 6-stud hitbox in front of it) could not be
-- seen. This helper aims like a player: it stands somewhere, puts the camera behind the character, looks at the
-- point it wants to tap, projects it to the screen and taps THAT screen point (UserInputService.TouchTap).
--
-- Everything that grades the game is written here, independently of the game's own Pick.luau:
--   * the projection (screenOf) is the test's pinhole math, not Pick.project;
--   * the oracle (firstVisible) is "the first VISIBLE part along the ray", over every part in the workspace that
--     is drawn as a surface (Transparency < 0.6: a translucent glow is seen through), characters excluded; the tile it belongs to is what the player sees under
--     their thumb, so it is the tile the tap must reach;
--   * the engine model (engineClick) is how Roblox delivers a ClickDetector click: the first CanQuery part along
--     the ray, a ClickDetector on it or an ancestor, the character within MaxActivationDistance. It is here so the
--     same check measures the ClickDetector design (before REVIEW-1) and the client-pick design (after) alike.
-- Like the game's Pick, it treats a ball or a cylinder as its bounding box (the visible shape, slightly generous).
--
-- The harness installs Vector3 / CFrame as globals of the CHECK file only (a required module has its own
-- globals in the luau CLI), so this module takes them from the harness's datatypes.

local Aim = {}
Aim.__index = Aim

-- Roblox's own touch controls, as robloxemu/emu/hudcheck.luau draws them (a tap there never reaches the game).
local THUMBSTICK_FRACTION, JUMP_FRACTION, MAX_CONTROL_PAD = 0.35, 0.25, 150
-- below this Transparency a part is a surface the eye stops at (crop parts are 0 to 0.45; the Ice shell 0.45)
local OPAQUE = 0.6

function Aim.new(h: any, opts: any?): any
	local o = opts or {}
	local dt = h.instance.datatypes
	local self = setmetatable({
		h = h,
		V3 = dt.Vector3,
		CF = dt.CFrame,
		V2 = dt.Vector2,
		Enum = dt.Enum,
		cam = h.workspace.CurrentCamera,
		uis = h.game:GetService("UserInputService"),
		inset = o.inset or 36, -- GuiService:GetGuiInset() in robloxemu: the topbar
		touch = if o.touch == nil then true else o.touch,
	}, Aim)
	return self
end

-- the camera a player has: behind the character along `facing` (horizontal unit), `pitch` degrees down,
-- `zoom` studs from the focus (the head, root + 1.5)
function Aim:pose(rootPos: any, facing: any, pitchDeg: number, zoom: number)
	local V3 = self.V3
	local horiz = V3.new(facing.X, 0, facing.Z).Unit
	local p = math.rad(pitchDeg)
	local look = horiz * math.cos(p) + V3.new(0, -math.sin(p), 0)
	local focus = rootPos + V3.new(0, 1.5, 0)
	self.cam.CFrame = self.CF.lookAt(focus - look * zoom, focus)
end

-- world point -> (x, y) in GUI-inset space (what TouchTap reports), plus whether a thumb can tap it there
function Aim:screenOf(p: any): (number?, number?, boolean)
	local cf = self.cam.CFrame
	local l = cf:PointToObjectSpace(p)
	if l.Z >= -0.05 then return nil, nil, false end
	local th = math.tan(math.rad(self.cam.FieldOfView) / 2)
	local vs = self.cam.ViewportSize
	local W, H = vs.X, vs.Y
	local nx = l.X / (-l.Z * th * (W / H))
	local ny = l.Y / (-l.Z * th)
	local vx, vy = (nx + 1) / 2 * W, (1 - ny) / 2 * H
	local ok = vx >= 2 and vx <= W - 2 and vy >= self.inset + 2 and vy <= H - 2
	if ok and self.touch then
		local pad = math.min(MAX_CONTROL_PAD, H * 0.35)
		if vy >= H - pad and (vx <= W * THUMBSTICK_FRACTION or vx >= W * (1 - JUMP_FRACTION)) then ok = false end
	end
	return vx, vy - self.inset, ok
end

-- the slab test: where the ray o + t * d (t >= 0) enters the part's box, or nil
local function enter(part: any, o: any, d: any): number?
	local cf = part.CFrame
	local lo = cf:PointToObjectSpace(o)
	local ld = cf:VectorToObjectSpace(d)
	local hs = part.Size / 2
	local tmin, tmax = 0, math.huge
	for _, ax in { "X", "Y", "Z" } do
		local oo, dd, s = lo[ax], ld[ax], hs[ax]
		if math.abs(dd) < 1e-9 then
			if oo < -s or oo > s then return nil end
		else
			local t1, t2 = (-s - oo) / dd, (s - oo) / dd
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	return tmin
end
Aim.enter = enter

local function isCharacterPart(d: any, players: any): boolean
	for _, plr in players:GetPlayers() do
		if plr.Character and d:IsDescendantOf(plr.Character) then return true end
	end
	return false
end

-- Transient effects a tap passes through and a player looks past: the hazard's model, ring and lane, critters,
-- bolts, bursts and "+N" pops. (The rare "found nothing to click" in two of 60 walks, 2026-10-01: a moment when such
-- an effect stood in front of every point of the aimed tile; the game's pick goes through them, as it should.)
local TRANSIENT = { Hazard = true, Critters = true, Bolts = true, StormStrikes = true }
local function isTransient(d: any): boolean
	local node = d.Parent
	while node ~= nil do
		if TRANSIENT[node.Name] then return true end
		node = node.Parent
	end
	return false
end

-- every part that is drawn (or, for the engine model, every CanQuery part), refreshed per call: crops grow,
-- bolts come and go
function Aim:parts(kind: string): { any }
	local out = {}
	local players = self.h.Players
	for _, d in self.h.workspace:GetDescendants() do
		if d:IsA("BasePart") and not isCharacterPart(d, players) then
			if kind == "visible" then
				if isTransient(d) then continue end
				-- a surface the eye stops at: a translucent glow (the Eye band's 0.88 sunbeam over the farm, a 0.92
				-- fog sheet) is seen through, so it is not "under the thumb"
				if (d.Transparency or 0) < OPAQUE then table.insert(out, d) end
			elseif d.CanQuery ~= false then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- the first part along the ray from `from` towards `to` (and beyond), among `parts`
function Aim:first(from: any, to: any, parts: { any }): (any?, number)
	local d = to - from
	local best, bt = nil, math.huge
	for _, p in parts do
		local t = enter(p, from, d)
		if t and t < bt then best, bt = p, t end
	end
	return best, bt
end

function Aim:firstVisible(from: any, to: any, parts: { any }?): (any?, number)
	return self:first(from, to, parts or self:parts("visible"))
end

-- which tile a part belongs to: a crop part (workspace.StormCrops.Crop_<slot>_<key>/*) or a soil plate
-- (workspace.Farms.Farm_<slot>.Tiles.Soil_<key>); nil for anything else (a fence, the ground, a sign)
function Aim:tileOf(part: any?): (number?, string?)
	if part == nil then return nil, nil end
	local parent = part.Parent
	if parent and parent.Parent and parent.Parent.Name == "StormCrops" then
		local slot, key = string.match(parent.Name, "^Crop_(%d+)_(.+)$")
		if slot then return tonumber(slot), key end
	end
	local key = string.match(part.Name, "^Soil_(.+)$") or string.match(part.Name, "^Tile_(.+)$")
	if key and parent and parent.Name == "Tiles" and parent.Parent then
		local slot = string.match(parent.Parent.Name, "^Farm_(%d+)$")
		if slot then return tonumber(slot), key end
	end
	return nil, nil
end

-- a thumb on the screen at (x, y), GUI-inset space; `processed` = the HUD or a touch control took it
function Aim:tap(x: number, y: number, processed: boolean?)
	self.uis.TouchTap:Fire({ self.V2.new(x, y) }, processed == true)
end

-- a mouse click at (x, y), GUI-inset space: a press and a release in place (InputObject.Position is a Vector3)
function Aim:click(x: number, y: number)
	local input = { UserInputType = self.Enum.UserInputType.MouseButton1, Position = self.V3.new(x, y, 0) }
	self.uis.InputBegan:Fire(input, false)
	self.uis.InputEnded:Fire(input, false)
end

-- where a farmer stands to work field f of farm k: field 1 from the pad, the side fields from the porch edge in
-- front of them, the back fields from the path between the rows; facing outward (the farm's local +z).
-- Farm and F are the game's own modules, used only to ADDRESS places.
function Aim:standFor(Farm: any, F: any, k: number, f: number): (any, any)
	local lx, lz
	if f == 1 then
		lx, lz = 0, F.PadLocalZ
	else
		local cx, cz = Farm.fieldCentreLocal(f, F)
		lx, lz = cx, cz - F.FieldSize / 2 - 2
	end
	local x, z = Farm.toWorld(k, lx, lz, F)
	local fx, fz = Farm.toWorld(k, lx, lz + 1, F)
	return self.V3.new(x, F.GroundY + 3, z), self.V3.new(fx - x, 0, fz - z).Unit
end

-- the points a player might put a thumb on for tile (k, key), the crop first: the middle of each drawn crop part
-- (the produce before the leaves), then three points on the soil plate (its middle and a point either side)
function Aim:targetsFor(k: number, key: string): { any }
	local out = {}
	local V3 = self.V3
	local crops = self.h.workspace:FindFirstChild("StormCrops")
	local folder = crops and crops:FindFirstChild("Crop_" .. k .. "_" .. key)
	if folder then
		local produce = folder:FindFirstChild("Produce")
		if produce and produce.Transparency < 0.95 then table.insert(out, produce.Position) end
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p ~= produce and p.Transparency < 0.95 then table.insert(out, p.Position) end
		end
	end
	local soil = self.h.workspace.Farms["Farm_" .. k].Tiles["Soil_" .. key]
	table.insert(out, soil.Position + V3.new(0, soil.Size.Y / 2, 0))
	table.insert(out, soil.CFrame * V3.new(2.6, soil.Size.Y / 2, 0.8))
	table.insert(out, soil.CFrame * V3.new(-2.6, soil.Size.Y / 2, -0.8))
	return out
end

-- the parts within r studs of a point (the oracle only needs what is near)
function Aim.within(parts: { any }, centre: any, r: number): { any }
	local out = {}
	for _, p in parts do
		if (p.Position - centre).Magnitude <= r + p.Size.Magnitude / 2 then table.insert(out, p) end
	end
	return out
end

-- Aim at tile (k, key) like a player: from where the character stands (rootPos, facing), try camera poses until
-- one of the tile's own drawn points is visible under the thumb and tappable, then tap (or click) it there. A tile
-- in the back row can be hidden behind tall crops in front at every pose from the field's working spot (two walks
-- in 60 had it: a Tomato behind a Tomato, a Sunflower behind Sunflowers); a player then walks into the field, so
-- `walkTo(pos)` (if given) is called with the spot just in front of the tile and the poses are tried again there.
-- -> (tapped, posesTried, walkedCloser)
function Aim:tapTile(k: number, key: string, rootPos: any, facing: any, how: string?, walkTo: ((any) -> ())?): (boolean, number, boolean)
	local tried = 0
	local function from(pos: any): boolean
		local visible = Aim.within(self:parts("visible"), pos, 100)
		for _, pose in { { 35, 12.5 }, { 55, 12.5 }, { 72, 16 } } do
			tried += 1
			self:pose(pos, facing, pose[1], pose[2])
			local camPos = self.cam.CFrame.Position
			for _, pt in self:targetsFor(k, key) do
				local x, y, ok = self:screenOf(pt)
				if ok then
					local s, kk = self:tileOf(self:firstVisible(camPos, pt, visible))
					if s == k and kk == key then
						if how == "click" then self:click(x :: number, y :: number) else self:tap(x :: number, y :: number) end
						return true
					end
				end
			end
		end
		return false
	end
	if from(rootPos) then return true, tried, false end
	if walkTo == nil then return false, tried, false end
	local soil = self.h.workspace.Farms["Farm_" .. k].Tiles["Soil_" .. key]
	local horiz = self.V3.new(facing.X, 0, facing.Z).Unit
	local closer = self.V3.new(soil.Position.X, rootPos.Y, soil.Position.Z) - horiz * 7
	walkTo(closer)
	return from(closer), tried, true
end

-- how Roblox would deliver a ClickDetector click for this ray: first CanQuery part, a ClickDetector on it or
-- an ancestor, the character within reach. Fires MouseClick as the engine would; returns the part or nil.
function Aim:engineClick(plr: any, from: any, to: any, parts: { any }?): any?
	local hit = self:first(from, to, parts or self:parts("query"))
	if hit == nil then return nil end
	local node = hit
	local cd = nil
	while node and node ~= self.h.workspace do
		cd = node:FindFirstChildOfClass("ClickDetector")
		if cd then break end
		node = node.Parent
	end
	if cd == nil then return nil end
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if root == nil or (root.Position - hit.Position).Magnitude > (cd.MaxActivationDistance or 32) then return nil end
	cd.MouseClick:Fire(plr)
	return hit
end

return Aim
