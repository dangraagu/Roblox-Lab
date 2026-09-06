-- Pure tests for the robloxemu datatypes. Run: luau tests/datatypes.spec.luau
local T = require("../emu/datatypes")

local Vector3 = T.Vector3
local CFrame = T.CFrame
local Color3 = T.Color3
local UDim = T.UDim
local UDim2 = T.UDim2
local NumberRange = T.NumberRange
local NumberSequence = T.NumberSequence
local NumberSequenceKeypoint = T.NumberSequenceKeypoint
local ColorSequence = T.ColorSequence
local ColorSequenceKeypoint = T.ColorSequenceKeypoint
local TweenInfo = T.TweenInfo
local Random = T.Random
local Enum = T.Enum

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg, eps)
	eps = eps or 1e-9
	if type(a) == "number" and math.abs(a - b) <= eps then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end
local function approxV3(v, x, y, z, msg, eps)
	eps = eps or 1e-9
	if math.abs(v.X - x) <= eps and math.abs(v.Y - y) <= eps and math.abs(v.Z - z) <= eps then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(v), "want ~", x .. ", " .. y .. ", " .. z)
	end
end
-- compares all 12 components of a CFrame against a hand-written expected list
local function approxCF(cf, want, msg, eps)
	eps = eps or 1e-9
	local got = { cf:GetComponents() }
	if #got ~= 12 then
		failed += 1; print("FAIL:", msg, "-> GetComponents returned", #got, "values, want 12")
		return
	end
	for i = 1, 12 do
		if math.abs(got[i] - want[i]) > eps then
			failed += 1
			print("FAIL:", msg, "-> component " .. i, "got", got[i], "want", want[i])
			print("      full:", tostring(cf))
			return
		end
	end
	passed += 1
end

-- ---------------------------------------------------------------- Color3
do
	local c = Color3.fromRGB(30, 34, 48)
	eq(math.round(c.R * 255), 30, "fromRGB round-trip R")
	eq(math.round(c.G * 255), 34, "fromRGB round-trip G")
	eq(math.round(c.B * 255), 48, "fromRGB round-trip B")

	-- every byte survives the /255 * 255 round trip (this is what the scene dumper does)
	local allOk = true
	for v = 0, 255 do
		if math.round(Color3.fromRGB(v, v, v).R * 255) ~= v then allOk = false end
	end
	truthy(allOk, "fromRGB round-trips all 256 byte values")

	eq(Color3.fromRGB(255, 255, 255).R, 1, "fromRGB(255) == 1.0")
	eq(Color3.fromRGB(0, 0, 0).B, 0, "fromRGB(0) == 0.0")
	eq(Color3.fromRGB(300, -20, 128).R, 1, "fromRGB clamps above 255")
	eq(Color3.fromRGB(300, -20, 128).G, 0, "fromRGB clamps below 0")

	local n = Color3.new(0.25, 0.5, 0.75)
	eq(n.R, 0.25, "Color3.new keeps 0-1 floats (R)")
	eq(n.G, 0.5, "Color3.new keeps 0-1 floats (G)")
	eq(n.B, 0.75, "Color3.new keeps 0-1 floats (B)")
	eq(n.r, 0.25, "lowercase .r alias")

	truthy(Color3.fromRGB(1, 2, 3) == Color3.fromRGB(1, 2, 3), "Color3 __eq by value")
	truthy(Color3.fromRGB(1, 2, 3) ~= Color3.fromRGB(1, 2, 4), "Color3 __eq distinguishes")

	-- fromHSV: hue 0 = red, 1/3 = green, 2/3 = blue
	local red = Color3.fromHSV(0, 1, 1)
	approxV3(Vector3.new(red.R, red.G, red.B), 1, 0, 0, "fromHSV(0,1,1) is red")
	local green = Color3.fromHSV(1 / 3, 1, 1)
	approxV3(Vector3.new(green.R, green.G, green.B), 0, 1, 0, "fromHSV(1/3,1,1) is green", 1e-12)
	local blue = Color3.fromHSV(2 / 3, 1, 1)
	approxV3(Vector3.new(blue.R, blue.G, blue.B), 0, 0, 1, "fromHSV(2/3,1,1) is blue", 1e-12)
	local grey = Color3.fromHSV(0.4, 0, 0.5)
	approxV3(Vector3.new(grey.R, grey.G, grey.B), 0.5, 0.5, 0.5, "fromHSV with s=0 is grey")

	-- ToHSV inverts fromHSV
	local h, s, v = Color3.fromHSV(0.7, 0.6, 0.8):ToHSV()
	approx(h, 0.7, "ToHSV h", 1e-9)
	approx(s, 0.6, "ToHSV s", 1e-9)
	approx(v, 0.8, "ToHSV v", 1e-9)

	eq(T.typeOf(Color3.new()), "Color3", "typeOf(Color3)")
end

-- ---------------------------------------------------------------- Vector3
do
	local a = Vector3.new(1, 2, 3)
	local b = Vector3.new(4, 5, 6)

	eq(a.X, 1, ".X"); eq(a.Y, 2, ".Y"); eq(a.Z, 3, ".Z")
	eq(a.x, 1, "lowercase .x alias")
	truthy(Vector3.new(0, 0, 0) == Vector3.zero, "Vector3.zero")
	truthy(Vector3.new() == Vector3.zero, "Vector3.new() defaults to zero")

	truthy(a + b == Vector3.new(5, 7, 9), "v + v")
	truthy(b - a == Vector3.new(3, 3, 3), "v - v")
	truthy(a * 2 == Vector3.new(2, 4, 6), "v * scalar")
	truthy(2 * a == Vector3.new(2, 4, 6), "scalar * v")
	truthy(a * b == Vector3.new(4, 10, 18), "v * v componentwise")
	truthy(b / 2 == Vector3.new(2, 2.5, 3), "v / scalar")
	truthy(b / Vector3.new(2, 5, 3) == Vector3.new(2, 1, 2), "v / v componentwise")
	truthy(-a == Vector3.new(-1, -2, -3), "unary minus")
	truthy(a ~= b, "__eq distinguishes")

	eq(Vector3.new(3, 4, 0).Magnitude, 5, "Magnitude 3-4-5")
	eq(Vector3.new(0, 0, 0).Magnitude, 0, "Magnitude of zero")
	approx(Vector3.new(1, 2, 2).Magnitude, 3, "Magnitude 1-2-2")
	approxV3(Vector3.new(0, 5, 0).Unit, 0, 1, 0, "Unit of an axis vector")
	approx(Vector3.new(3, -4, 12).Unit.Magnitude, 1, "Unit has magnitude 1")

	eq(a:Dot(b), 32, "Dot 1*4 + 2*5 + 3*6")
	eq(Vector3.xAxis:Dot(Vector3.yAxis), 0, "orthogonal axes Dot to 0")
	-- right-handed: X cross Y = Z
	truthy(Vector3.xAxis:Cross(Vector3.yAxis) == Vector3.zAxis, "X x Y == Z (right-handed)")
	truthy(Vector3.yAxis:Cross(Vector3.zAxis) == Vector3.xAxis, "Y x Z == X")
	truthy(a:Cross(b) == Vector3.new(-3, 6, -3), "Cross of (1,2,3)x(4,5,6)")
	truthy(a:Cross(b) == -(b:Cross(a)), "Cross is anticommutative")

	eq(tostring(Vector3.new(1, 2.5, -3)), "1, 2.5, -3", "__tostring")
	eq(T.typeOf(a), "Vector3", "typeOf(Vector3)")

	-- a Vector3 must not silently multiply with a foreign datatype
	truthy(not pcall(function() return a * Color3.new(1, 1, 1) end), "v * Color3 raises")
end

-- ---------------------------------------------------------------- CFrame
-- These are the load-bearing tests: the scene dump and every occlusion check ride on them.
local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
do
	-- constructors
	approxCF(CFrame.new(), { 0, 0, 0, table.unpack(IDENTITY_R) }, "CFrame.new() is identity")
	approxCF(CFrame.new(1, 2, 3), { 1, 2, 3, table.unpack(IDENTITY_R) }, "CFrame.new(x,y,z)")
	approxCF(CFrame.new(Vector3.new(4, 5, 6)), { 4, 5, 6, table.unpack(IDENTITY_R) },
		"CFrame.new(Vector3)")
	truthy(CFrame.new(1, 2, 3).Position == Vector3.new(1, 2, 3), ".Position is a Vector3")
	truthy(CFrame.new(1, 2, 3).p == Vector3.new(1, 2, 3), ".p alias")

	-- GetComponents order and arity
	local cf = CFrame.new(7, 8, 9)
	local comps = { cf:GetComponents() }
	eq(#comps, 12, "GetComponents returns 12 values")
	eq(comps[1], 7, "GetComponents[1] == x")
	eq(comps[2], 8, "GetComponents[2] == y")
	eq(comps[3], 9, "GetComponents[3] == z")
	eq(comps[4], 1, "GetComponents[4] == R00")
	eq(comps[8], 1, "GetComponents[8] == R11")
	eq(comps[12], 1, "GetComponents[12] == R22")

	-- default look/right/up axes
	approxV3(CFrame.new().LookVector, 0, 0, -1, "identity LookVector is -Z")
	approxV3(CFrame.new().RightVector, 1, 0, 0, "identity RightVector is +X")
	approxV3(CFrame.new().UpVector, 0, 1, 0, "identity UpVector is +Y")
end

do
	-- CFrame.Angles about each axis, hand-computed 3x3 matrices.
	local h = math.pi / 2

	-- Rx(90) = [[1,0,0],[0,0,-1],[0,1,0]]
	approxCF(CFrame.Angles(h, 0, 0), { 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 1, 0 },
		"CFrame.Angles(pi/2,0,0) == Rx(90)")
	-- Ry(90) = [[0,0,1],[0,1,0],[-1,0,0]]
	approxCF(CFrame.Angles(0, h, 0), { 0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0 },
		"CFrame.Angles(0,pi/2,0) == Ry(90)")
	-- Rz(90) = [[0,-1,0],[1,0,0],[0,0,1]]
	approxCF(CFrame.Angles(0, 0, h), { 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0, 1 },
		"CFrame.Angles(0,0,pi/2) == Rz(90)")

	approxCF(CFrame.Angles(0, 0, 0), { 0, 0, 0, table.unpack(IDENTITY_R) },
		"CFrame.Angles(0,0,0) is identity")
	-- Ry(180) = [[-1,0,0],[0,1,0],[0,0,-1]]
	approxCF(CFrame.Angles(0, math.pi, 0), { 0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
		"CFrame.Angles(0,pi,0) == Ry(180)")

	-- axis rotations move the axes the right way (right-hand rule)
	approxV3(CFrame.Angles(h, 0, 0) * Vector3.new(0, 1, 0), 0, 0, 1, "Rx(90): +Y -> +Z")
	approxV3(CFrame.Angles(0, h, 0) * Vector3.new(0, 0, -1), -1, 0, 0, "Ry(90): -Z -> -X")
	approxV3(CFrame.Angles(0, 0, h) * Vector3.new(1, 0, 0), 0, 1, 0, "Rz(90): +X -> +Y")
	approxV3(CFrame.Angles(0, h, 0).LookVector, -1, 0, 0, "Ry(90) LookVector is -X")

	-- ORDER: Roblox composes R = Rx * Ry * Rz.
	-- Rx(90)*Ry(90) = [[0,0,1],[1,0,0],[0,1,0]]  (Ry(90)*Rx(90) would be [[0,1,0],...])
	approxCF(CFrame.Angles(h, h, 0), { 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0 },
		"Angles(x,y,0) applies Rx*Ry, not Ry*Rx")
	local xy = CFrame.Angles(h, 0, 0) * CFrame.Angles(0, h, 0)
	approxCF(CFrame.Angles(h, h, 0), { xy:GetComponents() },
		"Angles(x,y,0) == Angles(x,0,0) * Angles(0,y,0)")
	local xyz = CFrame.Angles(0.3, 0, 0) * CFrame.Angles(0, 0.7, 0) * CFrame.Angles(0, 0, -0.2)
	approxCF(CFrame.Angles(0.3, 0.7, -0.2), { xyz:GetComponents() },
		"Angles(x,y,z) == Rx * Ry * Rz for arbitrary angles")
end

do
	-- CFrame * CFrame composition against hand-computed values.
	local h = math.pi / 2
	local ry90 = CFrame.Angles(0, h, 0)

	-- translation THEN rotation: position untouched, rotation replaced
	approxCF(CFrame.new(10, 0, 0) * ry90, { 10, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0 },
		"CFrame.new(10,0,0) * Angles(0,90,0)")

	-- rotation THEN translation: the offset is rotated. Ry(90) sends (10,0,0) to (0,0,-10).
	approxCF(ry90 * CFrame.new(10, 0, 0), { 0, 0, -10, 0, 0, 1, 0, 1, 0, -1, 0, 0 },
		"Angles(0,90,0) * CFrame.new(10,0,0) rotates the offset to (0,0,-10)")

	-- composing two rotations adds the angles
	approxCF(ry90 * ry90, { 0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
		"Ry(90) * Ry(90) == Ry(180)")

	-- full rigid transform: pos + R * offset, rotation multiplied
	local base = CFrame.new(1, 2, 3) * CFrame.Angles(0, h, 0)
	local composed = base * CFrame.new(0, 0, -4)
	-- Ry(90) sends (0,0,-4) to (-4,0,0); 1 + -4 = -3
	approxCF(composed, { -3, 2, 3, 0, 0, 1, 0, 1, 0, -1, 0, 0 },
		"(pos * Ry90) * CFrame.new(0,0,-4) walks 4 studs along its own look axis")

	-- multiplication is associative, not commutative
	local a = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, 0.2, 0.1)
	local b = CFrame.new(-4, 0.5, 2) * CFrame.Angles(-0.7, 1.1, 0.4)
	local c = CFrame.new(0, 3, -1) * CFrame.Angles(0.9, -0.2, 0.6)
	approxCF((a * b) * c, { (a * (b * c)):GetComponents() }, "CFrame * is associative", 1e-12)
	truthy(not (a * b == b * a), "CFrame * is not commutative here")

	-- identity is a two-sided identity
	approxCF(a * CFrame.identity, { a:GetComponents() }, "a * identity == a")
	approxCF(CFrame.identity * a, { a:GetComponents() }, "identity * a == a")

	-- inverse
	approxCF(a * a:Inverse(), { 0, 0, 0, table.unpack(IDENTITY_R) }, "a * a:Inverse() == identity",
		1e-12)
	approxCF(a:Inverse() * a, { 0, 0, 0, table.unpack(IDENTITY_R) }, "a:Inverse() * a == identity",
		1e-12)

	-- rotation matrix stays orthonormal after composition (columns unit + mutually orthogonal)
	local r = a * b * c
	approx(r.RightVector.Magnitude, 1, "composed RightVector stays unit", 1e-12)
	approx(r.UpVector.Magnitude, 1, "composed UpVector stays unit", 1e-12)
	approx(r.LookVector.Magnitude, 1, "composed LookVector stays unit", 1e-12)
	approx(r.RightVector:Dot(r.UpVector), 0, "composed Right . Up == 0", 1e-12)
	approx(r.RightVector:Dot(r.LookVector), 0, "composed Right . Look == 0", 1e-12)
	-- right-handed basis: Right x Up == -Look (Look is the negative Z axis)
	approxV3(r.RightVector:Cross(r.UpVector), -r.LookVector.X, -r.LookVector.Y, -r.LookVector.Z,
		"Right x Up == -Look (basis stays right-handed)", 1e-12)
end

do
	-- CFrame * Vector3 point transforms
	local h = math.pi / 2
	approxV3(CFrame.new(3, 4, 5) * Vector3.new(1, 0, 0), 4, 4, 5, "pure translation of a point")
	approxV3(CFrame.new(3, 4, 5) * Vector3.zero, 3, 4, 5, "origin maps to the position")
	approxV3(CFrame.Angles(0, h, 0) * Vector3.new(0, 0, -5), -5, 0, 0,
		"Ry(90) point transform: (0,0,-5) -> (-5,0,0)")
	approxV3(CFrame.Angles(0, h, 0) * Vector3.new(2, 3, 0), 0, 3, -2,
		"Ry(90) point transform: (2,3,0) -> (0,3,-2)")

	local cam = CFrame.new(0, 6, 10) * CFrame.Angles(0, math.pi, 0)
	-- looking down +Z after a 180 turn, so a point 4 studs "ahead" is at z = 14
	approxV3(cam * Vector3.new(0, 0, -4), 0, 6, 14, "camera-space point to world")
	approxV3(cam.LookVector, 0, 0, 1, "180-turned camera looks down +Z", 1e-15)

	-- ToWorldSpace / PointToWorldSpace agree with *
	local base = CFrame.new(-2, 7, 1) * CFrame.Angles(0.2, -0.5, 0.8)
	local off = CFrame.new(1, -2, 3) * CFrame.Angles(0.1, 0.1, 0.1)
	approxCF(base:ToWorldSpace(off), { (base * off):GetComponents() }, "ToWorldSpace == base * cf")
	local pt = Vector3.new(1.5, -0.5, 2)
	local w = base:PointToWorldSpace(pt)
	approxV3(w, (base * pt).X, (base * pt).Y, (base * pt).Z, "PointToWorldSpace == base * v3")
	-- and the object-space round trip returns the original point
	approxV3(base:PointToObjectSpace(w), pt.X, pt.Y, pt.Z, "PointToObjectSpace inverts", 1e-12)
	approxCF(base:ToObjectSpace(base * off), { off:GetComponents() }, "ToObjectSpace inverts",
		1e-12)
	-- vector transforms ignore the translation
	approxV3(base:VectorToWorldSpace(Vector3.zero), 0, 0, 0, "VectorToWorldSpace ignores position")

	-- CFrame + Vector3 translates without touching the rotation
	approxCF(base + Vector3.new(1, 1, 1),
		{ base.X + 1, base.Y + 1, base.Z + 1, select(4, base:GetComponents()) },
		"CFrame + Vector3 translates only")

	-- lookAt points the look axis at the target
	local la = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10))
	approxV3(la.LookVector, 0, 0, -1, "lookAt down -Z")
	local la2 = CFrame.lookAt(Vector3.new(0, 6, 10), Vector3.new(0, 6, -40))
	approxV3(la2.LookVector, 0, 0, -1, "scene-camera lookAt")
	approxV3(la2.Position, 0, 6, 10, "lookAt keeps the from position")

	eq(T.typeOf(CFrame.new()), "CFrame", "typeOf(CFrame)")
	truthy(not pcall(function() return CFrame.new(1, 2, 3) * 4 end), "CFrame * number raises")
	truthy(not pcall(function() return CFrame.new(1, 2, 3, 4, 5, 6, 7) end),
		"CFrame.new with 7 args raises (quaternion form not implemented)")
end

-- ---------------------------------------------------------------- UDim / UDim2
do
	local u = UDim.new(0.5, 12)
	eq(u.Scale, 0.5, "UDim.Scale"); eq(u.Offset, 12, "UDim.Offset")
	truthy(UDim.new(0.5, 12) + UDim.new(0.25, 3) == UDim.new(0.75, 15), "UDim __add")

	local d = UDim2.new(0.5, 10, 0.25, -4)
	eq(d.X.Scale, 0.5, "UDim2 .X.Scale"); eq(d.X.Offset, 10, "UDim2 .X.Offset")
	eq(d.Y.Scale, 0.25, "UDim2 .Y.Scale"); eq(d.Y.Offset, -4, "UDim2 .Y.Offset")
	eq(d.Width.Offset, 10, "UDim2 .Width alias")

	local o = UDim2.fromOffset(120, 40)
	eq(o.X.Scale, 0, "fromOffset scale is 0"); eq(o.X.Offset, 120, "fromOffset X offset")
	eq(o.Y.Offset, 40, "fromOffset Y offset")

	local s = UDim2.fromScale(0.3, 0.7)
	eq(s.X.Scale, 0.3, "fromScale X"); eq(s.Y.Scale, 0.7, "fromScale Y")
	eq(s.X.Offset, 0, "fromScale offset is 0")

	truthy(UDim2.new(0.5, 10, 0.25, -4) + UDim2.new(0.5, 5, 0.25, 4)
		== UDim2.new(1, 15, 0.5, 0), "UDim2 __add")
	truthy(UDim2.new(0, 1, 0, 1) == UDim2.new(0, 1, 0, 1), "UDim2 __eq")
	truthy(UDim2.new(UDim.new(1, 2), UDim.new(3, 4)) == UDim2.new(1, 2, 3, 4),
		"UDim2.new(UDim, UDim)")
	eq(T.typeOf(d), "UDim2", "typeOf(UDim2)")
end

-- ---------------------------------------------------------------- ranges + sequences
do
	local r = NumberRange.new(0.2, 0.8)
	eq(r.Min, 0.2, "NumberRange.Min"); eq(r.Max, 0.8, "NumberRange.Max")
	local one = NumberRange.new(5)
	eq(one.Min, 5, "NumberRange.new(v) Min"); eq(one.Max, 5, "NumberRange.new(v) Max")
	eq(NumberRange.new(-20, 20).Min, -20, "NumberRange accepts negatives")
	truthy(not pcall(function() return NumberRange.new(5, 1) end), "NumberRange min > max raises")

	local kp = NumberSequenceKeypoint.new(0.3, 0.55)
	eq(kp.Time, 0.3, "NSK.Time"); eq(kp.Value, 0.55, "NSK.Value"); eq(kp.Envelope, 0, "NSK default envelope")
	eq(NumberSequenceKeypoint.new(0.3, 0.55, 0.1).Envelope, 0.1, "NSK envelope arg")

	local flat = NumberSequence.new(0.4)
	eq(#flat.Keypoints, 2, "NumberSequence.new(v) makes 2 keypoints")
	eq(flat.Keypoints[1].Time, 0, "NS flat first t == 0")
	eq(flat.Keypoints[2].Time, 1, "NS flat last t == 1")
	eq(flat.Keypoints[2].Value, 0.4, "NS flat value")

	local ramp = NumberSequence.new(1, 0)
	eq(ramp.Keypoints[1].Value, 1, "NumberSequence.new(a,b) start")
	eq(ramp.Keypoints[2].Value, 0, "NumberSequence.new(a,b) end")

	-- the exact shape our Fx.luau builds
	local seq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	eq(#seq.Keypoints, 3, "NumberSequence from a keypoint list")
	eq(seq.Keypoints[2].Value, 0.18, "keypoint list preserves values")
	truthy(not pcall(function()
		return NumberSequence.new({ NumberSequenceKeypoint.new(0.1, 0), NumberSequenceKeypoint.new(1, 0) })
	end), "NumberSequence rejects a list not starting at t=0")
	truthy(not pcall(function()
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, 0) })
	end), "NumberSequence rejects a single keypoint")

	local top, bottom = Color3.fromRGB(255, 225, 120), Color3.fromRGB(240, 180, 30)
	local cs = ColorSequence.new(top, bottom)
	eq(#cs.Keypoints, 2, "ColorSequence.new(c0,c1)")
	truthy(cs.Keypoints[1].Value == top, "ColorSequence start colour")
	truthy(cs.Keypoints[2].Value == bottom, "ColorSequence end colour")
	local cs1 = ColorSequence.new(top)
	truthy(cs1.Keypoints[1].Value == top and cs1.Keypoints[2].Value == top,
		"ColorSequence.new(c) is flat")
	local cs2 = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	eq(#cs2.Keypoints, 2, "ColorSequence from a keypoint list")
end

-- ---------------------------------------------------------------- TweenInfo
do
	local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	eq(ti.Time, 0.25, "TweenInfo.Time")
	truthy(ti.EasingStyle == Enum.EasingStyle.Quint, "TweenInfo.EasingStyle")
	truthy(ti.EasingDirection == Enum.EasingDirection.Out, "TweenInfo.EasingDirection")
	eq(ti.RepeatCount, 0, "TweenInfo.RepeatCount default")
	eq(ti.Reverses, false, "TweenInfo.Reverses default")
	eq(ti.DelayTime, 0, "TweenInfo.DelayTime default")

	local d = TweenInfo.new()
	eq(d.Time, 1, "TweenInfo default time is 1")
	truthy(d.EasingStyle == Enum.EasingStyle.Quad, "TweenInfo default style is Quad")
	truthy(d.EasingDirection == Enum.EasingDirection.Out, "TweenInfo default direction is Out")

	local full = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.5)
	eq(full.RepeatCount, -1, "TweenInfo.RepeatCount"); eq(full.Reverses, true, "TweenInfo.Reverses")
	eq(full.DelayTime, 0.5, "TweenInfo.DelayTime")
end

-- ---------------------------------------------------------------- Random
do
	-- determinism for a fixed seed
	local a, b = Random.new(42), Random.new(42)
	local same = true
	for _ = 1, 200 do
		if a:NextNumber() ~= b:NextNumber() then same = false end
	end
	truthy(same, "same seed -> identical NextNumber sequence")

	local ia, ib = Random.new(1337), Random.new(1337)
	local sameInt = true
	for _ = 1, 200 do
		if ia:NextInteger(1, 1000) ~= ib:NextInteger(1, 1000) then sameInt = false end
	end
	truthy(sameInt, "same seed -> identical NextInteger sequence")

	truthy(Random.new(1):NextNumber() ~= Random.new(2):NextNumber(), "different seeds diverge")

	-- NextNumber ranges
	local within, min01, max01 = true, 1, 0
	local r = Random.new(7)
	for _ = 1, 20000 do
		local v = r:NextNumber()
		if v < 0 or v >= 1 then within = false end
		if v < min01 then min01 = v end
		if v > max01 then max01 = v end
	end
	truthy(within, "NextNumber() in [0,1)")
	truthy(min01 < 0.01 and max01 > 0.99, "NextNumber() spans the unit interval")

	local rangeOk = true
	local r2 = Random.new(11)
	for _ = 1, 5000 do
		local v = r2:NextNumber(-20, 20)
		if v < -20 or v > 20 then rangeOk = false end
	end
	truthy(rangeOk, "NextNumber(min,max) stays in range")

	-- NextInteger: inclusive bounds, integral, hits every value
	local r3 = Random.new(9)
	local lo, hi, integral, inRange = false, false, true, true
	for _ = 1, 20000 do
		local v = r3:NextInteger(1, 6)
		if v ~= math.floor(v) then integral = false end
		if v < 1 or v > 6 then inRange = false end
		if v == 1 then lo = true end
		if v == 6 then hi = true end
	end
	truthy(inRange, "NextInteger(1,6) in [1,6]")
	truthy(integral, "NextInteger returns integers")
	truthy(lo and hi, "NextInteger hits both inclusive bounds")
	eq(Random.new(3):NextInteger(5, 5), 5, "NextInteger(n,n) == n")
	truthy(not pcall(function() return Random.new(1):NextInteger(5, 1) end),
		"NextInteger(min>max) raises")
	-- a non-finite bound must ERROR, never spin the rejection loop forever (a hang would be
	-- invisible in a headless run)
	truthy(not pcall(function() return Random.new(1):NextInteger(1, 0 / 0) end),
		"NextInteger with a NaN bound raises instead of hanging")
	truthy(not pcall(function() return Random.new(1):NextInteger(1, math.huge) end),
		"NextInteger with an infinite bound raises instead of hanging")
	truthy(not pcall(function() return Random.new(1):NextInteger(0 / 0, 5) end),
		"NextInteger with a NaN min raises")

	-- a power-of-two range must not collapse (the classic LCG low-bit trap this repo already hit)
	local r4 = Random.new(555)
	local seen, distinct = {}, 0
	for _ = 1, 20000 do
		local v = r4:NextInteger(1, 8)
		if not seen[v] then seen[v] = true; distinct += 1 end
	end
	eq(distinct, 8, "NextInteger(1,8) hits all 8 values")

	-- ...and one draw from a FRESH Random per low-bits-zero seed must still spread
	local seen2, distinct2 = {}, 0
	for i = 1, 3000 do
		local v = Random.new(i * 2048):NextInteger(1, 8)
		if not seen2[v] then seen2[v] = true; distinct2 += 1 end
	end
	eq(distinct2, 8, "NextInteger(1,8) spreads across i*2048 seeds")

	-- big seeds like Random.new(WorldSeed * 1000003 + level * 2654435761)
	local big1 = Random.new(20260906 * 1000003 + 3 * 2654435761)
	local big2 = Random.new(20260906 * 1000003 + 3 * 2654435761)
	eq(big1:NextInteger(1, 1000000), big2:NextInteger(1, 1000000), "huge seeds stay deterministic")
	truthy(Random.new(1 * 2654435761) :NextNumber() ~= Random.new(2 * 2654435761):NextNumber(),
		"neighbouring huge seeds diverge")

	-- negative and fractional seeds are accepted and deterministic
	eq(Random.new(-5):NextNumber(), Random.new(-5):NextNumber(), "negative seed deterministic")
	eq(Random.new(3.9):NextNumber(), Random.new(3.9):NextNumber(), "float seed deterministic")

	-- unseeded Random still works (the games use it for a session salt)
	local u = Random.new()
	local uOk = true
	for _ = 1, 1000 do
		local v = u:NextInteger(1, 2147483647)
		if v < 1 or v > 2147483647 or v ~= math.floor(v) then uOk = false end
	end
	truthy(uOk, "unseeded Random:NextInteger(1, 2^31-1) stays in range")
	local un = Random.new():NextNumber()
	truthy(un >= 0 and un < 1, "unseeded Random:NextNumber() in [0,1)")
	truthy(Random.new():NextNumber() ~= Random.new():NextNumber(),
		"two unseeded Randoms differ")
	eq(Random.new(0):NextInteger(0, 2147483646) >= 0, true, "NextInteger from 0 works")
end

-- ---------------------------------------------------------------- Enum
do
	-- the measured families
	eq(Enum.Material.SmoothPlastic.Name, "SmoothPlastic", "Enum.Material.SmoothPlastic.Name")
	eq(Enum.Font.GothamBold.Name, "GothamBold", "Enum.Font.GothamBold.Name")
	eq(Enum.EasingStyle.Quad.Name, "Quad", "Enum.EasingStyle.Quad.Name")
	eq(Enum.KeyCode.E.Name, "E", "Enum.KeyCode.E.Name")
	eq(tostring(Enum.Material.SmoothPlastic), "SmoothPlastic",
		"tostring(EnumItem) is the bare name (what the scene dump writes)")
	eq(tostring(Enum.PartType.Ball), "Ball", "tostring on another family")

	-- stable identity: the same item is the same value every time
	truthy(Enum.Material.Neon == Enum.Material.Neon, "EnumItem identity is stable")
	truthy(Enum.Material.Neon ~= Enum.Material.Glass, "different items differ")
	truthy(Enum.Material.Neon ~= Enum.SurfaceType.Neon, "same name in a different family differs")
	truthy(rawequal(Enum.Material, Enum.Material), "the family object is cached")

	-- .Value is a number and is stable across accesses
	truthy(type(Enum.Material.Neon.Value) == "number", "EnumItem.Value is a number")
	eq(Enum.Material.Neon.Value, Enum.Material.Neon.Value, "EnumItem.Value is stable")
	truthy(Enum.TextTruncate.AtEnd.Value ~= Enum.TextTruncate.None.Value,
		"two items in a family get distinct values")

	-- auto-creation: an UNKNOWN family and an UNKNOWN item must not error
	local okFam, fam = pcall(function() return Enum.TotallyMadeUpFamily end)
	truthy(okFam and fam ~= nil, "unknown Enum family auto-creates")
	local okItem, item = pcall(function() return Enum.TotallyMadeUpFamily.SomeItem end)
	truthy(okItem and item ~= nil, "unknown Enum item auto-creates")
	eq(item.Name, "SomeItem", "auto-created item .Name")
	eq(tostring(item), "SomeItem", "auto-created item tostring")
	truthy(Enum.TotallyMadeUpFamily.SomeItem == item, "auto-created item is cached")
	eq(Enum.NotAFamilyEither.AlsoNew.Name, "AlsoNew", "second unknown family auto-creates")

	-- families report their own name and their touched items
	eq(Enum.Material.Name, "Material", "family .Name")
	truthy(#Enum.TotallyMadeUpFamily:GetEnumItems() >= 1, "GetEnumItems lists touched items")

	eq(T.typeOf(Enum.Material.Neon), "EnumItem", "typeOf(EnumItem)")
	eq(T.typeOf(Enum.Material), "Enum", "typeOf(Enum family)")
	truthy(Enum.Material.Neon.EnumType == Enum.Material, "EnumItem.EnumType points at its family")
end

-- ---------------------------------------------------------------- export surface
do
	for _, name in {
		"Vector3", "CFrame", "Color3", "UDim", "UDim2", "NumberRange", "NumberSequence",
		"NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "TweenInfo",
		"Random", "Enum",
	} do
		truthy(T[name] ~= nil, "exports " .. name)
	end
end


--============================================================ Vector2
-- Added for the GUI layer (AnchorPoint, AbsoluteSize). Roblox reports it as "Vector2".
do
	local v = T.Vector2.new(3, 4)
	eq(v.X, 3, "Vector2 keeps X")
	eq(v.Y, 4, "Vector2 keeps Y")
	eq(T.typeOf(v), "Vector2", "typeOf reports Vector2")
	eq(v.Magnitude, 5, "Vector2 magnitude is the hypotenuse")
	eq(T.Vector2.new(0, 0).X, 0, "Vector2.new defaults are numeric")
	eq(T.Vector2.zero.X, 0, "Vector2.zero exists")
	eq(T.Vector2.one.Y, 1, "Vector2.one exists")
	truthy(T.Vector2.new(1, 2) == T.Vector2.new(1, 2), "equal Vector2 values compare equal")
	truthy(T.Vector2.new(1, 2) ~= T.Vector2.new(2, 1), "different Vector2 values differ")
	local sum = T.Vector2.new(1, 2) + T.Vector2.new(3, 4)
	eq(sum.X, 4, "Vector2 addition adds X")
	eq(sum.Y, 6, "Vector2 addition adds Y")
	local diff = T.Vector2.new(5, 5) - T.Vector2.new(1, 2)
	eq(diff.X, 4, "Vector2 subtraction subtracts X")
	eq(diff.Y, 3, "Vector2 subtraction subtracts Y")
	eq((T.Vector2.new(2, 3) * 2).X, 4, "Vector2 scales by a number on the right")
	eq((2 * T.Vector2.new(2, 3)).Y, 6, "Vector2 scales by a number on the left")
	eq((T.Vector2.new(4, 6) / 2).X, 2, "Vector2 divides by a number")
	eq((-T.Vector2.new(1, 2)).X, -1, "Vector2 negates")
	local u = T.Vector2.new(0, 7).Unit
	eq(u.X, 0, "Vector2 unit keeps the zero axis")
	eq(u.Y, 1, "Vector2 unit normalises the other axis")
	eq(tostring(T.Vector2.new(1.5, 2)), "1.5, 2", "Vector2 tostring matches Roblox formatting")
	-- AnchorPoint is the real reason this type exists; it must survive a property round-trip.
	eq(T.Vector2.new(0.5, 1).X, 0.5, "Vector2 keeps fractional components")
end

print(string.format("datatypes: %d passed, %d failed", passed, failed))
if failed > 0 then error("datatypes tests failed") end
