-- Rene tester for Rng (deterministisk LCG). Kjør: luau tests/Rng.spec.luau
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

-- Determinisme: samme frø -> samme sekvens
local a = Rng.new(42)
local b = Rng.new(42)
for i = 1, 50 do
	eq(a:int(1, 1000), b:int(1, 1000), "same seed same seq @" .. i)
end

-- Ulike frø -> (nesten helt sikkert) ulik første verdi
local c = Rng.new(42)
local d = Rng.new(43)
truthy(c:step() ~= d:step(), "different seeds differ")

-- int-grenser: alltid innenfor [min,max]
local r = Rng.new(7)
local within = true
local sawMin, sawMax = false, false
for _ = 1, 5000 do
	local v = r:int(1, 6)
	if v < 1 or v > 6 then within = false end
	if v == 1 then sawMin = true end
	if v == 6 then sawMax = true end
end
truthy(within, "int stays within bounds")
truthy(sawMin and sawMax, "int hits both endpoints")

-- next i [0,1)
local r2 = Rng.new(99)
local okNext = true
for _ = 1, 1000 do
	local v = r2:next()
	if v < 0 or v >= 1 then okNext = false end
end
truthy(okNext, "next in [0,1)")

-- pick returnerer et element fra lista
local list = { "a", "b", "c" }
local r3 = Rng.new(5)
local isMember = true
for _ = 1, 100 do
	local v = r3:pick(list)
	if v ~= "a" and v ~= "b" and v ~= "c" then isMember = false end
end
truthy(isMember, "pick returns a member")

-- int med min==max -> alltid min
eq(Rng.new(1):int(4, 4), 4, "int min==max")

print(string.format("Rng: %d passed, %d failed", passed, failed))
assert(failed == 0, "Rng tests failed")
