--[[
	robloxemu/emu/datatypes.luau

	Pure-Luau reimplementations of the Roblox datatypes our games actually use, good enough to
	run real game code headlessly under the luau CLI. Returns ONE table; the harness injects the
	members as globals.

	Owned by the datatypes agent. Nothing here touches any game's src/.

	Deliberate approximations (safe for headless build + scene dump, documented so nobody has to
	rediscover them):
	  * Random is NOT bit-compatible with Roblox's PRNG (xoshiro128** here). Our games only need
	    "deterministic for a given seed" + correct ranges, which this gives.
	  * EnumItem.__tostring returns the ITEM NAME ("SmoothPlastic"), not Roblox's
	    "Enum.Material.SmoothPlastic" -- the scene dump writes bare material names. Use .Name.
	  * Auto-created EnumItem.Value counts up from 0 per family in first-touch order; it is stable
	    within a run but is NOT Roblox's real numeric id.
	  * CFrame has no quaternion constructor and no :Lerp (no slerp). CFrame.new with 7 args errors.
	  * NumberSequence/ColorSequence keypoint lists are validated the way Roblox validates them
	    (>= 2 keypoints, first t == 0, last t == 1, non-decreasing) so a malformed list is caught
	    here rather than silently rendering wrong.
]]

local M = {}

local TWO32 = 4294967296

-- metatable -> datatype name, so the harness/scene dumper can tell a Color3 from a Vector3
local TYPE_OF: { [any]: string } = {}

local function typeOf(v)
	if type(v) == "table" then
		local name = TYPE_OF[getmetatable(v)]
		if name then return name end
	end
	return typeof(v)
end
M.typeOf = typeOf

local function isNum(v) return type(v) == "number" end

local function num(v, default)
	if isNum(v) then return v end
	if v == nil then return default end
	error("expected a number, got " .. typeof(v), 3)
end

-- a numeric argument with no default: nil is an error, not a silent 0
local function reqnum(v, what)
	if isNum(v) then return v end
	error(what .. " must be a number, got " .. typeof(v), 3)
end

local function fmt(n)
	return string.format("%g", n)
end

--============================================================================ Vector3

local V3 = {}
TYPE_OF[V3] = "Vector3"

local function newV3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end

local function isV3(v) return type(v) == "table" and getmetatable(v) == V3 end

local function magnitude(v)
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local V3methods = {}

function V3methods.Dot(a, b)
	if not isV3(b) then error("Vector3:Dot() expects a Vector3", 2) end
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function V3methods.Cross(a, b)
	if not isV3(b) then error("Vector3:Cross() expects a Vector3", 2) end
	return newV3(
		a.Y * b.Z - a.Z * b.Y,
		a.Z * b.X - a.X * b.Z,
		a.X * b.Y - a.Y * b.X
	)
end

function V3methods.Lerp(a, b, t)
	if not isV3(b) then error("Vector3:Lerp() expects a Vector3", 2) end
	return newV3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end

function V3methods.FuzzyEq(a, b, epsilon)
	epsilon = epsilon or 1e-5
	return math.abs(a.X - b.X) <= epsilon
		and math.abs(a.Y - b.Y) <= epsilon
		and math.abs(a.Z - b.Z) <= epsilon
end

V3.__index = function(self, k)
	if k == "Magnitude" then
		return magnitude(self)
	elseif k == "Unit" then
		local m = magnitude(self)
		return newV3(self.X / m, self.Y / m, self.Z / m)
	elseif k == "x" then
		return self.X
	elseif k == "y" then
		return self.Y
	elseif k == "z" then
		return self.Z
	end
	return V3methods[k]
end

V3.__add = function(a, b)
	if not (isV3(a) and isV3(b)) then error("Vector3 + expects two Vector3s", 2) end
	return newV3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

V3.__sub = function(a, b)
	if not (isV3(a) and isV3(b)) then error("Vector3 - expects two Vector3s", 2) end
	return newV3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

V3.__mul = function(a, b)
	if isNum(a) and isV3(b) then return newV3(a * b.X, a * b.Y, a * b.Z) end
	if isV3(a) and isNum(b) then return newV3(a.X * b, a.Y * b, a.Z * b) end
	if isV3(a) and isV3(b) then return newV3(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
	local other = if isV3(a) then b else a
	error("Vector3 * expects a number or a Vector3, got " .. typeOf(other), 2)
end

V3.__div = function(a, b)
	if isV3(a) and isNum(b) then return newV3(a.X / b, a.Y / b, a.Z / b) end
	if isV3(a) and isV3(b) then return newV3(a.X / b.X, a.Y / b.Y, a.Z / b.Z) end
	if isNum(a) and isV3(b) then return newV3(a / b.X, a / b.Y, a / b.Z) end
	error("Vector3 / expects a number or a Vector3", 2)
end

V3.__unm = function(a) return newV3(-a.X, -a.Y, -a.Z) end

V3.__eq = function(a, b)
	return isV3(a) and isV3(b) and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

V3.__tostring = function(self)
	return fmt(self.X) .. ", " .. fmt(self.Y) .. ", " .. fmt(self.Z)
end

local Vector3 = {}

function Vector3.new(x, y, z)
	return newV3(num(x, 0), num(y, 0), num(z, 0))
end

Vector3.zero = newV3(0, 0, 0)
Vector3.one = newV3(1, 1, 1)
Vector3.xAxis = newV3(1, 0, 0)
Vector3.yAxis = newV3(0, 1, 0)
Vector3.zAxis = newV3(0, 0, 1)

M.Vector3 = Vector3

--============================================================================ CFrame

local CF = {}
TYPE_OF[CF] = "CFrame"

-- Stored as position + a row-major 3x3 rotation matrix (R<row><col>), i.e. exactly the order
-- CFrame:GetComponents() reports and the scene JSON expects.
local function newCF(x, y, z, m00, m01, m02, m10, m11, m12, m20, m21, m22)
	return setmetatable({
		X = x, Y = y, Z = z,
		R00 = m00, R01 = m01, R02 = m02,
		R10 = m10, R11 = m11, R12 = m12,
		R20 = m20, R21 = m21, R22 = m22,
	}, CF)
end

local function isCF(v) return type(v) == "table" and getmetatable(v) == CF end

-- world = R * v  (v is a plain x,y,z triple)
local function rotate(c, x, y, z)
	return c.R00 * x + c.R01 * y + c.R02 * z,
		c.R10 * x + c.R11 * y + c.R12 * z,
		c.R20 * x + c.R21 * y + c.R22 * z
end

-- object = R^T * v
local function rotateT(c, x, y, z)
	return c.R00 * x + c.R10 * y + c.R20 * z,
		c.R01 * x + c.R11 * y + c.R21 * z,
		c.R02 * x + c.R12 * y + c.R22 * z
end

local CFmethods = {}

function CFmethods.GetComponents(self)
	return self.X, self.Y, self.Z,
		self.R00, self.R01, self.R02,
		self.R10, self.R11, self.R12,
		self.R20, self.R21, self.R22
end
CFmethods.components = CFmethods.GetComponents

function CFmethods.Inverse(self)
	-- R' = R^T, p' = -R^T * p
	local px, py, pz = rotateT(self, self.X, self.Y, self.Z)
	return newCF(-px, -py, -pz,
		self.R00, self.R10, self.R20,
		self.R01, self.R11, self.R21,
		self.R02, self.R12, self.R22)
end

function CFmethods.ToWorldSpace(self, cf)
	if not isCF(cf) then error("CFrame:ToWorldSpace() expects a CFrame", 2) end
	return self * cf
end

function CFmethods.ToObjectSpace(self, cf)
	if not isCF(cf) then error("CFrame:ToObjectSpace() expects a CFrame", 2) end
	return self:Inverse() * cf
end

function CFmethods.PointToWorldSpace(self, v)
	if not isV3(v) then error("CFrame:PointToWorldSpace() expects a Vector3", 2) end
	return self * v
end

function CFmethods.PointToObjectSpace(self, v)
	if not isV3(v) then error("CFrame:PointToObjectSpace() expects a Vector3", 2) end
	local x, y, z = rotateT(self, v.X - self.X, v.Y - self.Y, v.Z - self.Z)
	return newV3(x, y, z)
end

function CFmethods.VectorToWorldSpace(self, v)
	if not isV3(v) then error("CFrame:VectorToWorldSpace() expects a Vector3", 2) end
	return newV3(rotate(self, v.X, v.Y, v.Z))
end

function CFmethods.VectorToObjectSpace(self, v)
	if not isV3(v) then error("CFrame:VectorToObjectSpace() expects a Vector3", 2) end
	return newV3(rotateT(self, v.X, v.Y, v.Z))
end

CF.__index = function(self, k)
	if k == "Position" or k == "p" then
		return newV3(self.X, self.Y, self.Z)
	elseif k == "LookVector" then
		-- Roblox's look axis is the NEGATIVE third column
		return newV3(-self.R02, -self.R12, -self.R22)
	elseif k == "RightVector" or k == "XVector" then
		return newV3(self.R00, self.R10, self.R20)
	elseif k == "UpVector" or k == "YVector" then
		return newV3(self.R01, self.R11, self.R21)
	elseif k == "ZVector" then
		return newV3(self.R02, self.R12, self.R22)
	elseif k == "Rotation" then
		return newCF(0, 0, 0,
			self.R00, self.R01, self.R02,
			self.R10, self.R11, self.R12,
			self.R20, self.R21, self.R22)
	end
	return CFmethods[k]
end

CF.__mul = function(a, b)
	if not isCF(a) then
		error("CFrame * : left operand must be a CFrame (got " .. typeOf(a) .. ")", 2)
	end
	if isV3(b) then
		local x, y, z = rotate(a, b.X, b.Y, b.Z)
		return newV3(a.X + x, a.Y + y, a.Z + z)
	end
	if not isCF(b) then
		error("CFrame * expects a CFrame or a Vector3 (got " .. typeOf(b) .. ")", 2)
	end
	-- position: a.p + a.R * b.p
	local px, py, pz = rotate(a, b.X, b.Y, b.Z)
	-- rotation: a.R * b.R
	return newCF(a.X + px, a.Y + py, a.Z + pz,
		a.R00 * b.R00 + a.R01 * b.R10 + a.R02 * b.R20,
		a.R00 * b.R01 + a.R01 * b.R11 + a.R02 * b.R21,
		a.R00 * b.R02 + a.R01 * b.R12 + a.R02 * b.R22,

		a.R10 * b.R00 + a.R11 * b.R10 + a.R12 * b.R20,
		a.R10 * b.R01 + a.R11 * b.R11 + a.R12 * b.R21,
		a.R10 * b.R02 + a.R11 * b.R12 + a.R12 * b.R22,

		a.R20 * b.R00 + a.R21 * b.R10 + a.R22 * b.R20,
		a.R20 * b.R01 + a.R21 * b.R11 + a.R22 * b.R21,
		a.R20 * b.R02 + a.R21 * b.R12 + a.R22 * b.R22)
end

local function translated(a, b, sign)
	if not (isCF(a) and isV3(b)) then
		error("CFrame +/- expects a Vector3 on the right", 3)
	end
	return newCF(a.X + sign * b.X, a.Y + sign * b.Y, a.Z + sign * b.Z,
		a.R00, a.R01, a.R02, a.R10, a.R11, a.R12, a.R20, a.R21, a.R22)
end

CF.__add = function(a, b) return translated(a, b, 1) end
CF.__sub = function(a, b) return translated(a, b, -1) end

CF.__eq = function(a, b)
	if not (isCF(a) and isCF(b)) then return false end
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
		and a.R00 == b.R00 and a.R01 == b.R01 and a.R02 == b.R02
		and a.R10 == b.R10 and a.R11 == b.R11 and a.R12 == b.R12
		and a.R20 == b.R20 and a.R21 == b.R21 and a.R22 == b.R22
end

CF.__tostring = function(self)
	local parts = table.create(12)
	for i, v in { self:GetComponents() } do
		parts[i] = fmt(v)
	end
	return table.concat(parts, ", ")
end

local CFrame = {}

CFrame.identity = newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

function CFrame.fromMatrix(pos, vX, vY, vZ)
	if not (isV3(pos) and isV3(vX) and isV3(vY)) then
		error("CFrame.fromMatrix(position, vX, vY[, vZ]) expects Vector3s", 2)
	end
	if vZ == nil then
		vZ = vX:Cross(vY)
	end
	return newCF(pos.X, pos.Y, pos.Z,
		vX.X, vY.X, vZ.X,
		vX.Y, vY.Y, vZ.Y,
		vX.Z, vY.Z, vZ.Z)
end

function CFrame.lookAt(from, to, up)
	if not (isV3(from) and isV3(to)) then
		error("CFrame.lookAt(from, to[, up]) expects Vector3s", 2)
	end
	up = up or Vector3.yAxis
	local dir = to - from
	local m = magnitude(dir)
	if m == 0 then
		-- degenerate: keep the identity rotation at `from`
		return newCF(from.X, from.Y, from.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	dir = dir / m
	local right = dir:Cross(up)
	if magnitude(right) < 1e-9 then
		-- dir parallel to up: pick any perpendicular
		right = dir:Cross(newV3(up.Z, up.X, up.Y))
	end
	right = right.Unit
	local trueUp = right:Cross(dir)
	-- columns: right, up, -look
	return newCF(from.X, from.Y, from.Z,
		right.X, trueUp.X, -dir.X,
		right.Y, trueUp.Y, -dir.Y,
		right.Z, trueUp.Z, -dir.Z)
end

function CFrame.new(...)
	local n = select("#", ...)
	if n == 0 then
		return newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local a, b = ...
	if n == 1 then
		if isV3(a) then return newCF(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
		error("CFrame.new(v) expects a Vector3, got " .. typeOf(a), 2)
	end
	if n == 2 and isV3(a) and isV3(b) then
		-- CFrame.new(position, lookAt)
		return CFrame.lookAt(a, b)
	end
	if n == 3 then
		local x, y, z = ...
		return newCF(num(x, 0), num(y, 0), num(z, 0), 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if n == 12 then
		return newCF(...)
	end
	error("CFrame.new: unsupported argument count " .. n
		.. " (supported: 0, 1 Vector3, 2 Vector3s, 3 numbers, 12 numbers;"
		.. " the 7-arg quaternion form is not implemented)", 2)
end

-- Roblox applies the three rotations in the order R = Rx * Ry * Rz.
function CFrame.Angles(rx, ry, rz)
	local ca, sa = math.cos(num(rx, 0)), math.sin(num(rx, 0))
	local cb, sb = math.cos(num(ry, 0)), math.sin(num(ry, 0))
	local cc, sc = math.cos(num(rz, 0)), math.sin(num(rz, 0))
	return newCF(0, 0, 0,
		cb * cc,                   -cb * sc,                   sb,
		ca * sc + sa * sb * cc,    ca * cc - sa * sb * sc,     -sa * cb,
		sa * sc - ca * sb * cc,    sa * cc + ca * sb * sc,     ca * cb)
end

CFrame.fromEulerAnglesXYZ = CFrame.Angles

M.CFrame = CFrame

--============================================================================ Color3

local C3 = {}
TYPE_OF[C3] = "Color3"

local function newC3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end

local function isC3(v) return type(v) == "table" and getmetatable(v) == C3 end

local C3methods = {}

function C3methods.Lerp(a, b, t)
	if not isC3(b) then error("Color3:Lerp() expects a Color3", 2) end
	return newC3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

function C3methods.ToHSV(self)
	local r, g, b = self.R, self.G, self.B
	local maxc, minc = math.max(r, g, b), math.min(r, g, b)
	local d = maxc - minc
	local h = 0
	if d > 0 then
		if maxc == r then
			h = ((g - b) / d) % 6
		elseif maxc == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if maxc == 0 then 0 else d / maxc
	return h, s, maxc
end

C3.__index = function(self, k)
	if k == "r" then return self.R
	elseif k == "g" then return self.G
	elseif k == "b" then return self.B
	end
	return C3methods[k]
end

C3.__eq = function(a, b)
	return isC3(a) and isC3(b) and a.R == b.R and a.G == b.G and a.B == b.B
end

C3.__tostring = function(self)
	return fmt(self.R) .. ", " .. fmt(self.G) .. ", " .. fmt(self.B)
end

local Color3 = {}

-- Roblox's Color3.new does NOT clamp; keep the exact floats so the dumper controls rounding.
function Color3.new(r, g, b)
	return newC3(num(r, 0), num(g, 0), num(b, 0))
end

local function clamp255(v)
	v = num(v, 0)
	if v < 0 then return 0 elseif v > 255 then return 255 end
	return v
end

-- Exact division by 255: math.round(c.R * 255) recovers the original byte.
function Color3.fromRGB(r, g, b)
	return newC3(clamp255(r) / 255, clamp255(g) / 255, clamp255(b) / 255)
end

function Color3.fromHSV(h, s, v)
	h, s, v = num(h, 0), num(s, 0), num(v, 0)
	h = h % 1
	if s <= 0 then return newC3(v, v, v) end
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	local m = i % 6
	if m == 0 then return newC3(v, t, p)
	elseif m == 1 then return newC3(q, v, p)
	elseif m == 2 then return newC3(p, v, t)
	elseif m == 3 then return newC3(p, q, v)
	elseif m == 4 then return newC3(t, p, v)
	else return newC3(v, p, q) end
end

Color3.toHSV = function(c) return c:ToHSV() end

M.Color3 = Color3

--============================================================================ UDim / UDim2

local UD = {}
TYPE_OF[UD] = "UDim"

local function newUD(scale, offset)
	return setmetatable({ Scale = scale, Offset = offset }, UD)
end

local function isUD(v) return type(v) == "table" and getmetatable(v) == UD end

local UDmethods = {}
function UDmethods.Lerp(a, b, t)
	return newUD(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
end

UD.__index = UDmethods
UD.__add = function(a, b)
	if not (isUD(a) and isUD(b)) then error("UDim + expects two UDims", 2) end
	return newUD(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	if not (isUD(a) and isUD(b)) then error("UDim - expects two UDims", 2) end
	return newUD(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__unm = function(a) return newUD(-a.Scale, -a.Offset) end
UD.__eq = function(a, b)
	return isUD(a) and isUD(b) and a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(self) return fmt(self.Scale) .. ", " .. fmt(self.Offset) end

local UDim = {}
function UDim.new(scale, offset)
	return newUD(num(scale, 0), num(offset, 0))
end
M.UDim = UDim

local UD2 = {}
TYPE_OF[UD2] = "UDim2"

local function newUD2(x, y)
	return setmetatable({ X = x, Y = y }, UD2)
end

local function isUD2(v) return type(v) == "table" and getmetatable(v) == UD2 end

local UD2methods = {}
function UD2methods.Lerp(a, b, t)
	return newUD2(a.X:Lerp(b.X, t), a.Y:Lerp(b.Y, t))
end

UD2.__index = function(self, k)
	if k == "Width" then return self.X
	elseif k == "Height" then return self.Y
	end
	return UD2methods[k]
end
UD2.__add = function(a, b)
	if not (isUD2(a) and isUD2(b)) then error("UDim2 + expects two UDim2s", 2) end
	return newUD2(a.X + b.X, a.Y + b.Y)
end
UD2.__sub = function(a, b)
	if not (isUD2(a) and isUD2(b)) then error("UDim2 - expects two UDim2s", 2) end
	return newUD2(a.X - b.X, a.Y - b.Y)
end
UD2.__unm = function(a) return newUD2(-a.X, -a.Y) end
UD2.__eq = function(a, b)
	return isUD2(a) and isUD2(b) and a.X == b.X and a.Y == b.Y
end
UD2.__tostring = function(self)
	return "{" .. tostring(self.X) .. "}, {" .. tostring(self.Y) .. "}"
end

local UDim2 = {}

function UDim2.new(...)
	local n = select("#", ...)
	local a, b = ...
	if n == 2 and isUD(a) and isUD(b) then
		return newUD2(a, b)
	end
	local xs, xo, ys, yo = ...
	return newUD2(newUD(num(xs, 0), num(xo, 0)), newUD(num(ys, 0), num(yo, 0)))
end

function UDim2.fromOffset(x, y)
	return newUD2(newUD(0, num(x, 0)), newUD(0, num(y, 0)))
end

function UDim2.fromScale(x, y)
	return newUD2(newUD(num(x, 0), 0), newUD(num(y, 0), 0))
end

M.UDim2 = UDim2

--============================================================================ NumberRange

local NR = {}
TYPE_OF[NR] = "NumberRange"
NR.__index = NR
NR.__eq = function(a, b)
	return getmetatable(a) == NR and getmetatable(b) == NR and a.Min == b.Min and a.Max == b.Max
end
NR.__tostring = function(self) return fmt(self.Min) .. " " .. fmt(self.Max) end

local NumberRange = {}
function NumberRange.new(min, max)
	min = reqnum(min, "NumberRange.new min")
	if max == nil then max = min end
	max = reqnum(max, "NumberRange.new max")
	if min > max then
		error("NumberRange.new: min (" .. fmt(min) .. ") must be <= max (" .. fmt(max) .. ")", 2)
	end
	return setmetatable({ Min = min, Max = max }, NR)
end
M.NumberRange = NumberRange

--============================================================================ Sequences

local NSK = {}
TYPE_OF[NSK] = "NumberSequenceKeypoint"
NSK.__index = NSK
NSK.__eq = function(a, b)
	return getmetatable(a) == NSK and getmetatable(b) == NSK
		and a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NSK.__tostring = function(self)
	return fmt(self.Time) .. " " .. fmt(self.Value) .. " " .. fmt(self.Envelope)
end

local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(time, value, envelope)
	return setmetatable({
		Time = num(time, 0),
		Value = num(value, 0),
		Envelope = num(envelope, 0),
	}, NSK)
end
M.NumberSequenceKeypoint = NumberSequenceKeypoint

local CSK = {}
TYPE_OF[CSK] = "ColorSequenceKeypoint"
CSK.__index = CSK
CSK.__eq = function(a, b)
	return getmetatable(a) == CSK and getmetatable(b) == CSK
		and a.Time == b.Time and a.Value == b.Value
end
CSK.__tostring = function(self)
	return fmt(self.Time) .. " " .. tostring(self.Value)
end

local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(time, value)
	if not isC3(value) then
		error("ColorSequenceKeypoint.new(time, color) expects a Color3", 2)
	end
	return setmetatable({ Time = num(time, 0), Value = value }, CSK)
end
M.ColorSequenceKeypoint = ColorSequenceKeypoint

-- Roblox rejects malformed keypoint lists; so do we, so a bad list is caught here.
local function validateKeypoints(kind, list, keyMT)
	if #list < 2 then
		error(kind .. ".new: need at least 2 keypoints, got " .. #list, 3)
	end
	local last = -1
	for i, kp in list do
		if getmetatable(kp) ~= keyMT then
			error(kind .. ".new: keypoint " .. i .. " is not a " .. kind .. "Keypoint", 3)
		end
		if kp.Time < last then
			error(kind .. ".new: keypoints must be in non-decreasing time order", 3)
		end
		last = kp.Time
	end
	if list[1].Time ~= 0 then
		error(kind .. ".new: first keypoint must be at time 0", 3)
	end
	if list[#list].Time ~= 1 then
		error(kind .. ".new: last keypoint must be at time 1", 3)
	end
	return table.clone(list)
end

local NS = {}
TYPE_OF[NS] = "NumberSequence"
NS.__index = NS
NS.__tostring = function(self)
	local out = table.create(#self.Keypoints)
	for i, kp in self.Keypoints do out[i] = tostring(kp) end
	return table.concat(out, " ")
end

local NumberSequence = {}
function NumberSequence.new(a, b)
	local kps
	if type(a) == "table" and getmetatable(a) == nil then
		kps = validateKeypoints("NumberSequence", a, NSK)
	elseif isNum(a) and b == nil then
		kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, a) }
	elseif isNum(a) and isNum(b) then
		kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }
	else
		error("NumberSequence.new expects (n), (n0, n1) or ({keypoints})", 2)
	end
	return setmetatable({ Keypoints = kps }, NS)
end
M.NumberSequence = NumberSequence

local CS = {}
TYPE_OF[CS] = "ColorSequence"
CS.__index = CS
CS.__tostring = function(self)
	local out = table.create(#self.Keypoints)
	for i, kp in self.Keypoints do out[i] = tostring(kp) end
	return table.concat(out, " ")
end

local ColorSequence = {}
function ColorSequence.new(a, b)
	local kps
	if type(a) == "table" and getmetatable(a) == nil then
		kps = validateKeypoints("ColorSequence", a, CSK)
	elseif isC3(a) and b == nil then
		kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, a) }
	elseif isC3(a) and isC3(b) then
		kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }
	else
		error("ColorSequence.new expects (c), (c0, c1) or ({keypoints})", 2)
	end
	return setmetatable({ Keypoints = kps }, CS)
end
M.ColorSequence = ColorSequence

--============================================================================ Enum

-- Permissive: an unknown family or item is auto-created rather than raising, because game code
-- touches enums we have not catalogued and a crash there is worse than a stub.

local ITEM = {}
TYPE_OF[ITEM] = "EnumItem"

local itemFamily = setmetatable({}, { __mode = "k" })

ITEM.__index = function(self, k)
	if k == "EnumType" then return itemFamily[self] end
	return nil
end
-- Per the emulator contract: tostring(item) is the BARE NAME (Roblox would say
-- "Enum.Material.SmoothPlastic"); the scene dump writes bare names.
ITEM.__tostring = function(self) return self.Name end
ITEM.__newindex = function() error("EnumItem is read-only", 2) end

local FAMILY = {}
TYPE_OF[FAMILY] = "Enum"

local enumFamilies = {}

local function makeFamily(famName)
	local items = {}
	local order = {}
	local family = {}

	local statics = {
		Name = famName,
		GetEnumItems = function() return table.clone(order) end,
		FromName = function(_, name) return items[name] end,
		FromValue = function(_, value) return order[value + 1] end,
	}

	setmetatable(family, {
		__index = function(_, key)
			local s = statics[key]
			if s ~= nil then return s end
			if type(key) ~= "string" then return nil end
			local item = items[key]
			if item == nil then
				item = setmetatable({ Name = key, Value = #order }, ITEM)
				itemFamily[item] = family
				items[key] = item
				table.insert(order, item)
			end
			return item
		end,
		__newindex = function() error("Enum." .. famName .. " is read-only", 2) end,
		__tostring = function() return "Enum." .. famName end,
		__metatable = FAMILY,
	})
	return family
end

local Enum = setmetatable({}, {
	__index = function(_, famName)
		if type(famName) ~= "string" then return nil end
		local fam = enumFamilies[famName]
		if fam == nil then
			fam = makeFamily(famName)
			enumFamilies[famName] = fam
		end
		return fam
	end,
	__newindex = function() error("Enum is read-only", 2) end,
	__tostring = function() return "Enum" end,
})

-- Pre-register the families measured in our games (documentation + warm cache; any other family
-- still auto-creates on first touch).
for _, famName in {
	"Font", "Material", "TextXAlignment", "EasingStyle", "EasingDirection", "Technology",
	"ZIndexBehavior", "TextTruncate", "SortOrder", "KeyCode", "ProductPurchaseDecision",
	"PartType", "ApplyStrokeMode", "UserInputType", "SurfaceType", "NormalId",
} do
	enumFamilies[famName] = makeFamily(famName)
end

M.Enum = Enum

--============================================================================ TweenInfo

local TI = {}
TYPE_OF[TI] = "TweenInfo"
TI.__index = TI
TI.__tostring = function(self)
	return string.format("TweenInfo(%g, %s, %s, %d, %s, %g)",
		self.Time, tostring(self.EasingStyle), tostring(self.EasingDirection),
		self.RepeatCount, tostring(self.Reverses), self.DelayTime)
end

local TweenInfo = {}
function TweenInfo.new(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)
	return setmetatable({
		Time = num(time, 1),
		EasingStyle = easingStyle or Enum.EasingStyle.Quad,
		EasingDirection = easingDirection or Enum.EasingDirection.Out,
		RepeatCount = num(repeatCount, 0),
		Reverses = if reverses == nil then false else (reverses and true or false),
		DelayTime = num(delayTime, 0),
	}, TI)
end
M.TweenInfo = TweenInfo

--============================================================================ Random

-- xoshiro128** on 32-bit words. NOT bit-compatible with Roblox's PRNG; what our games need is
-- "deterministic for a given seed" plus correct, unbiased ranges, which this delivers.
-- Deliberately not an LCG: this codebase has already been bitten once by low-order-bit collapse
-- on seeds like i * 2048 (see Rng.below), so the generator must spread on such seeds.

local function mul32(a, b)
	-- exact 32x32 -> low 32 bits, staying inside the double's 53-bit mantissa
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	local lo = al * bl
	local mid = (ah * bl + al * bh) % 65536
	return (lo + mid * 65536) % TWO32
end

local function splitmix32(state)
	state = (state + 0x9E3779B9) % TWO32
	local z = state
	z = mul32(bit32.bxor(z, bit32.rshift(z, 16)), 0x21F0AAAD)
	z = mul32(bit32.bxor(z, bit32.rshift(z, 15)), 0x735A2D97)
	z = bit32.bxor(z, bit32.rshift(z, 15))
	return z, state
end

local function toWord(n)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.floor(n) % TWO32
end

local RND = {}
TYPE_OF[RND] = "Random"
RND.__index = RND
RND.__tostring = function() return "Random" end

local unseededCounter = 0

local function next32(self)
	local s = self._s
	local s0, s1, s2, s3 = s[1], s[2], s[3], s[4]
	local result = (bit32.lrotate((s1 * 5) % TWO32, 7) * 9) % TWO32
	local t = bit32.lshift(s1, 9)
	s2 = bit32.bxor(s2, s0)
	s3 = bit32.bxor(s3, s1)
	s1 = bit32.bxor(s1, s2)
	s0 = bit32.bxor(s0, s3)
	s2 = bit32.bxor(s2, t)
	s3 = bit32.lrotate(s3, 11)
	s[1], s[2], s[3], s[4] = s0, s1, s2, s3
	return result
end

function RND.NextNumber(self, min, max)
	local hi = next32(self)
	local lo = next32(self)
	-- 27 high bits + 26 high bits = a full 53-bit mantissa in [0, 1)
	local r = (bit32.rshift(hi, 5) * 67108864 + bit32.rshift(lo, 6)) / 9007199254740992
	if min == nil and max == nil then return r end
	min = num(min, 0)
	max = num(max, 1)
	return min + (max - min) * r
end

function RND.NextInteger(self, min, max)
	min = math.floor(reqnum(min, "Random:NextInteger() min"))
	max = math.floor(reqnum(max, "Random:NextInteger() max"))
	-- A NaN or infinite bound would make the rejection loop below spin forever. In a headless
	-- run a hang is far worse than an error, so refuse it up front.
	if min ~= min or max ~= max or min == math.huge or min == -math.huge
		or max == math.huge or max == -math.huge then
		error("Random:NextInteger() bounds must be finite numbers, got "
			.. tostring(min) .. ", " .. tostring(max), 2)
	end
	if min > max then
		error("Random:NextInteger(" .. min .. ", " .. max .. "): min must be <= max", 2)
	end
	local span = max - min + 1
	if span == 1 then return min end
	if span > TWO32 then
		local v = min + math.floor(self:NextNumber() * span)
		return if v > max then max else v
	end
	if span == TWO32 then return min + next32(self) end
	-- rejection sampling removes the modulo bias
	local limit = TWO32 - (TWO32 % span)
	local v
	repeat
		v = next32(self)
	until v < limit
	return min + (v % span)
end

function RND.NextUnitVector(self)
	-- uniform on the sphere
	local z = self:NextNumber(-1, 1)
	local a = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(math.max(0, 1 - z * z))
	return newV3(r * math.cos(a), r * math.sin(a), z)
end

function RND.Clone(self)
	local c = setmetatable({ _s = table.clone(self._s) }, RND)
	return c
end

local Random = {}

function Random.new(seed)
	local word, frac
	if seed == nil then
		unseededCounter += 1
		local t = os.clock()
		word = toWord(os.time() * 1000 + math.floor(t * 1000) + unseededCounter * 2654435761)
		frac = toWord(math.floor((t % 1) * 4294967296) + unseededCounter)
	else
		if type(seed) ~= "number" then
			error("Random.new(seed) expects a number, got " .. typeof(seed), 2)
		end
		word = toWord(seed)
		frac = toWord(math.floor((seed % 1) * 4294967296))
	end

	local sm = bit32.bxor(word, mul32(frac, 0x9E3779B9))
	local s = table.create(4)
	for i = 1, 4 do
		s[i], sm = splitmix32(sm)
	end
	if s[1] == 0 and s[2] == 0 and s[3] == 0 and s[4] == 0 then
		s[1] = 0x9E3779B9
	end
	local self = setmetatable({ _s = s }, RND)
	-- warm-up: decorrelates neighbouring / low-entropy seeds
	for _ = 1, 8 do next32(self) end
	return self
end

M.Random = Random

return M
