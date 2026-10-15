-- Tap.luau (tests only): a finger on the screen, through the camera the player sees (REVIEW-1).
--
-- A pad has no ClickDetector any more: View.client picks a tap from its own camera. So the walk and the checks
-- tap the way a phone does: they read the CURRENT camera (CFrame, FieldOfView, ViewportSize), project a world
-- point with an independent pinhole written here (not GardenCam), and fire UserInputService.TouchTap at that
-- screen point, below the GUI inset as Roblox reports touch positions. They also measure what the finger had
-- to hit: a pad's cell on screen, in px.
--
-- A required module has globals of its own in the luau CLI, so the caller hands over its Vector2/Vector3:
--   local tap = Tap.bind(h, { Vector2 = Vector2, Vector3 = Vector3 })   -- then tap.pad(garden, i), ...
--
--   Tap.project(h, worldPos) -> sx, sy (screen px, below the inset), depth
--   Tap.at(h, sx, sy)                          a touch tap there
--   Tap.world(h, worldPos) -> sx, sy           a touch tap on that point of the world
--   Tap.padCentre(garden, padIndex) -> Vector3 the pad's top centre in the world
--   Tap.pad(h, garden, padIndex) -> sx, sy     a touch tap on the pad's centre
--   Tap.cellPx(h, garden, padIndex) -> w, h    the pad's 8-stud cell on screen
--   Tap.onScreen(h, worldPos) -> bool          in front of the camera and inside the viewport

local Tap = {}
local V2, V3 = nil :: any, nil :: any

local INSET = 36 -- robloxemu's GuiService:GetGuiInset() top, and Roblox's topbar

local function cam(h)
	return h.workspace.CurrentCamera
end

function Tap.project(h, p)
	local c = cam(h)
	local cf = c.CFrame
	local pos = cf.Position
	local f = cf.LookVector
	-- right = forward x up(0,1,0), up = right x forward (CFrame.lookAt with world up)
	local rx, rz = -f.Z, f.X
	local rl = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rl, rz / rl
	local ux, uy, uz = 0 * f.Z - rz * f.Y, rz * f.X - rx * f.Z, rx * f.Y - 0 * f.X
	local dx, dy, dz = p.X - pos.X, p.Y - pos.Y, p.Z - pos.Z
	local zc = dx * f.X + dy * f.Y + dz * f.Z
	local xc = dx * rx + dz * rz
	local yc = dx * ux + dy * uy + dz * uz
	local vs = c.ViewportSize
	local fl = (vs.Y / 2) / math.tan(math.rad(c.FieldOfView) / 2)
	return vs.X / 2 + xc / zc * fl, vs.Y / 2 - yc / zc * fl - INSET, zc
end

function Tap.at(h, sx, sy)
	local uis = h.game:GetService("UserInputService")
	uis.TouchTap:Fire({ V2.new(sx, sy) }, false)
end

function Tap.world(h, p)
	local sx, sy = Tap.project(h, p)
	Tap.at(h, sx, sy)
	return sx, sy
end

local function bedPads(garden)
	local Config = require("../src/shared/Config")
	local PathGen = require("../src/shared/PathGen")
	local path = PathGen.fromText(Config, garden:GetAttribute("PathCells"))
	return PathGen.pads(Config, path), Config
end

function Tap.padCentre(garden, idx)
	local pads = bedPads(garden)
	local pd = pads[idx]
	return V3.new(garden:GetAttribute("OriginX") + pd.cx, garden:GetAttribute("OriginY") + 0.6, garden:GetAttribute("OriginZ") + pd.cz)
end

function Tap.pad(h, garden, idx)
	return Tap.world(h, Tap.padCentre(garden, idx))
end

function Tap.cellPx(h, garden, idx)
	local pads, Config = bedPads(garden)
	local pd = pads[idx]
	local half = Config.Tile / 2
	local o = V3.new(garden:GetAttribute("OriginX"), garden:GetAttribute("OriginY"), garden:GetAttribute("OriginZ"))
	local xs, ys = {}, {}
	for _, dx in { -half, half } do
		for _, dz in { -half, half } do
			local x, y = Tap.project(h, o + V3.new(pd.cx + dx, 0.6, pd.cz + dz))
			table.insert(xs, x)
			table.insert(ys, y)
		end
	end
	return math.max(table.unpack(xs)) - math.min(table.unpack(xs)), math.max(table.unpack(ys)) - math.min(table.unpack(ys))
end

function Tap.onScreen(h, p)
	local sx, sy, z = Tap.project(h, p)
	local vs = cam(h).ViewportSize
	return z > 0 and sx >= 0 and sx <= vs.X and sy >= -INSET and sy <= vs.Y - INSET
end

-- every function with `h` bound; also installs the caller's datatypes
function Tap.bind(h, types)
	V2, V3 = types.Vector2, types.Vector3
	local out = {}
	for name, fn in Tap do
		if type(fn) == "function" and name ~= "bind" and name ~= "padCentre" then
			out[name] = function(...) return fn(h, ...) end
		end
	end
	out.padCentre = Tap.padCentre
	return out
end

return Tap
