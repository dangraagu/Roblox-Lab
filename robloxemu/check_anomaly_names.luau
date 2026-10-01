-- anomaly-observatory — the hall a client receives must not NAME the answer.
-- Run: luau check_anomaly_names.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- WHY THIS EXISTS (review 2026-09-30, finding 1). The roll's own attributes were moved to
-- ServerStorage in 2026-09-10 because `Clean = true` on a replicated Instance hands a client the answer
-- as a label (CLAUDE.md, "The pass is now visible from outside the server script"). The appliers did
-- the same thing with Instance NAMES: `door_extra` parented a part called "DoorExtra" into the zone,
-- `twin_scope` one called "TelescopeTwin", `cold_breath` one called "Fog", three anomalies a Model
-- called "Figure"; `scope_gone`, `plant_gone` and `count_off` destroyed a named part. The zone is in
-- workspace, so every client receives those names: `zone:FindFirstChild("DoorExtra")` answered the
-- pass without looking. The reviewer's probe told 25 of 64 anomalous passes apart by child names
-- alone, 10 ids, each at 100%.
--
-- What remains readable is R12 (Main.server.luau): the anomaly is a visible change, so the PROPERTIES
-- of the replicated parts differ from the clean hall's, and a determined script can diff them against
-- a clean build it recorded. That is the cost CLAUDE.md accepts ("derive it"); a name is the cost it
-- rejects ("every client is told it"). This file holds the line between the two:
--
--   1. For EVERY catalog id, forced through the game's own Config (a one-entry catalog, chance 1, in
--      memory, this run only), the zone's instance tree - every descendant's path, name and class, IN
--      ORDER - is identical to the clean hall's. No anomaly adds, removes, renames or reorders anything.
--   2. Every one of those anomalies still changes the hall (its fingerprint differs from clean within a
--      short window: `flicker_hall` is temporal), so constancy was not bought by switching one off.
--   3. The server's roll is the forced one (PassInfo, read on the server), so (1) and (2) were measured
--      on the anomaly they name.
--   4. In the clean hall, anything that is not drawn cannot be felt either: every part with
--      Transparency 1 has CanCollide, CanTouch and CanQuery off, and every light inside it is off.
--   5. CONTROL: the tree comparison can fail - a part renamed in memory is reported.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
-- the game's own Config module, the one the server required
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local A = Config.Anomaly
local original = {
	Catalog = A.Catalog, StartPool = A.StartPool, PoolPerDay = A.PoolPerDay,
	BaseChance = A.BaseChance, ChancePerDay = A.ChancePerDay, MaxChance = A.MaxChance,
}

local function zoneOf(plr)
	return h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
end
local function infoOf(plr)
	local root = h.game:GetService("ServerStorage"):FindFirstChild("PassInfo")
	return root and root:FindFirstChild(tostring(plr.UserId))
end

-- The tree as a client receives it: path / name / class of every descendant, in order.
local function treeOf(zone): { string }
	local rows = {}
	for _, d in zone:GetDescendants() do
		local path, p = d.Name, d.Parent
		while p and p ~= zone do
			path = p.Name .. "/" .. path
			p = p.Parent
		end
		table.insert(rows, path .. " <" .. d.ClassName .. ">")
	end
	return rows
end

-- Everything an applier can change, relative to the zone origin (check_anomaly_attrs' fingerprint,
-- plus lights, which three anomalies switch).
local function fingerprint(zone): string
	local ox = (tonumber(zone:GetAttribute("Index")) or 0) * 1000
	local rows = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			table.insert(rows, string.format("%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d,%d,%d|%.2f|%.2f|%s|%s",
				d.Name, x - ox, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, d.Size.X, d.Size.Y, d.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				d.Transparency, d.Reflectance, tostring(d.Material), tostring(d.CanCollide)))
		elseif d:IsA("Light") then
			table.insert(rows, string.format("light %s in %s|%s|%s", d.Name, d.Parent and d.Parent.Name or "?", tostring(d.Enabled), tostring(d.Color)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function force(entry)
	A.Catalog = { entry }
	A.StartPool, A.PoolPerDay = 1, 0
	A.BaseChance, A.ChancePerDay, A.MaxChance = 1, 0, 1
end
local function forceClean()
	A.Catalog = original.Catalog
	A.StartPool, A.PoolPerDay = original.StartPool, original.PoolPerDay
	A.BaseChance, A.ChancePerDay, A.MaxChance = 0, 0, 0
end
local function restore()
	for k, v in original do A[k] = v end
end

--============================================================ the clean hall
forceClean()
local cleanPlr = h:join("CleanRef", 700000)
h:advance(0.05)
local cleanZone = zoneOf(cleanPlr)
assert(cleanZone ~= nil, "the clean reference got no concourse")
eq(infoOf(cleanPlr):GetAttribute("Clean"), true, "the reference pass is clean (the server's own roll)")
local cleanTree = treeOf(cleanZone)
local cleanFp = fingerprint(cleanZone)
print(string.format("   clean hall: %d descendants", #cleanTree))

-- 4. what is not drawn cannot be felt. The one exception is the pane across the entrance (finding 7),
-- whose whole job is to be felt: it keeps the player from walking off the end of the floor.
do
	local felt = {}
	for _, d in cleanZone:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency >= 1 and d.Name ~= "EntranceGlass" then
			if d.CanCollide or d.CanTouch or d.CanQuery then
				table.insert(felt, d.Name .. " (collide/touch/query " .. tostring(d.CanCollide) .. "/" .. tostring(d.CanTouch) .. "/" .. tostring(d.CanQuery) .. ")")
			end
			for _, l in d:GetDescendants() do
				-- `~= false`: robloxemu leaves a new light's Enabled nil, and Roblox's default is TRUE, so an
				-- unset light is a lit one
				if l:IsA("Light") and l.Enabled ~= false then table.insert(felt, d.Name .. " carries a lit " .. l.ClassName) end
			end
		end
	end
	eq(#felt, 0, "in the clean hall every invisible part is also intangible and unlit: " .. table.concat(felt, "; "))
end

--============================================================ every id
local function sameTree(a: { string }, b: { string }): (boolean, string)
	local n = math.max(#a, #b)
	for i = 1, n do
		if a[i] ~= b[i] then
			return false, string.format("first difference at #%d: clean %s, anomalous %s (%d vs %d descendants)",
				i, tostring(a[i]), tostring(b[i]), #a, #b)
		end
	end
	return true, ""
end

local byName, told = {}, 0
for i, entry in original.Catalog do
	force(entry)
	local plr = h:join("Forced_" .. entry.id, 710000 + i)
	h:advance(0.05)
	local zone = zoneOf(plr)
	assert(zone ~= nil, entry.id .. ": no concourse")
	local info = infoOf(plr)
	eq(info and info:GetAttribute("AnomalyId"), entry.id, entry.id .. ": the server rolled the forced anomaly")
	local same, why = sameTree(cleanTree, treeOf(zone))
	truthy(same, entry.id .. ": the replicated tree (every path, name and class, in order) is the clean hall's -- " .. why)
	if not same then
		told += 1
		byName[entry.id] = why
	end
	-- 2. and it still changes the hall
	local differs = fingerprint(zone) ~= cleanFp
	for _ = 1, 8 do
		if differs then break end
		h:advance(0.05)
		differs = fingerprint(zone) ~= cleanFp
	end
	truthy(differs, entry.id .. ": the anomaly still changes the hall (fingerprint differs from clean)")
end
print(string.format("   %d of %d catalog ids could be told from the clean hall by the tree alone", told, #original.Catalog))
restore()

--============================================================ 5. control
do
	local zone = zoneOf(cleanPlr)
	local victim = zone:FindFirstChildWhichIsA("BasePart")
	local oldName = victim.Name
	victim.Name = oldName .. "_renamed"
	local same = sameTree(cleanTree, treeOf(zone))
	victim.Name = oldName
	eq(same, false, "CONTROL: the tree comparison reports a part renamed in memory")
	eq(sameTree(cleanTree, treeOf(zone)), true, "CONTROL: and agrees again once the name is back")
end

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomaly_names: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly names check failed", 0)
end
