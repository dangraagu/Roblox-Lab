-- anomaly-observatory — WHERE DOES THE PLAYER ACTUALLY LAND?  Run: luau check_anomaly_spawn.luau
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- WHY THIS EXISTS. Until now NO check in this repo ever spawned an anomaly-observatory
-- character. `check_anomaly.luau` measures GUI rectangles; `check_anomaly_attrs.luau` says so in
-- as many words at its own line 262 — "No character is spawned, here or above" — because the old
-- `simulateSpawn` fired `CharacterAdded` inline on the calling thread, where `onCharacter`'s
-- `task.wait(0.2)` took the whole run down. So this game's spawn was not "passing"; it was
-- unobserved. A check that never looks cannot fail, and this file is the one that looks.
--
-- WHAT THE ENGINE DOES (robloxemu/SPAWN-ORDER.md, measured in Studio 2026-09-10):
--   1. the character Model is built UNPARENTED with its HumanoidRootPart at the world origin;
--   2. `Player.CharacterAdded` fires — still unparented, still at the origin;
--   3. ONE FRAME LATER the engine parents it AND places it, discarding whatever the handler
--      wrote in between.
-- With no enabled SpawnLocation the engine drops the character over the world ORIGIN. This game
-- has no SpawnLocation anywhere — `Anomaly.rbxlx` contains no Workspace at all and the server
-- builds none — and every concourse is at `zoneOrigin(index) = (index * 1000, 100, 0)` with
-- `index` starting at 1. So the engine's own answer is the void at (0, ~3, 0): no floor, 100
-- studs below and >=1000 studs west of the hall the player is supposed to be reading.
--
-- WHAT IS ASSERTED
--   1. By the time the engine's spawn step has finished, the player is on their OWN StartPad —
--      not one frame later, not 12 frames later. That is the difference between "the game placed
--      the player" and "the game happened to out-sleep the engine": a wall-clock `task.wait`
--      long enough to win today is a coincidence, and it leaves the player in the void for every
--      one of those frames, on every spawn and every respawn.
--   2. They are still there a second later (nothing rescues them back to the origin).
--   3. A SECOND player lands in their OWN zone, not in player one's hall. The halls are private
--      by construction and the entire game is "spot what changed in YOUR hall", so landing in
--      someone else's is both a placement bug and a spoiler.
--   4. A RESPAWN lands on the pad too. The join path has a second, independent rescue
--      (`beginPass` teleports at the end of `PlayerAdded`); a respawn has only `onCharacter`,
--      so this is the path where a lost race is permanent.
--   5. The carried tint light — the game's only cosmetic and ECLIPSE's only reward — is
--      actually built for a fresh character. `applyTintLight` reads `char.Parent` at
--      CharacterAdded time, which step 2 above says is nil, and its guard is a silent early
--      return with no retry.
--
-- WHAT THE EMULATOR DOES NOT MODEL, and what this check supplies instead. `simulateSpawn` builds
-- a character out of a HumanoidRootPart and a Humanoid only — there is no Head, and `ensureLight`
-- parents the SpotLight to the Head. On the real server both are already there when
-- CharacterAdded fires (STUDIO.md: neither `WaitForChild` yielded). The earliest this file can
-- reach a character is its own `CharacterAdded` handler, so that is where the Head is added, and
-- it is stated here rather than hidden: assertion 5 is a differential — same Head, same timing,
-- in both directions — and it isolates exactly one variable, the `char.Parent` guard.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function fmt(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end

local function zoneOf(plr)
	for _, c in workspace:GetChildren() do
		if c.Name == "Concourse_" .. tostring(plr.UserId) then return c end
	end
	return nil
end

local function rootOf(plr)
	local char = plr.Character
	if char == nil then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp == nil or not hrp:IsA("BasePart") then return nil end
	return hrp
end

-- "standing on that pad": the XZ is over it and the root is above its top face but not in orbit.
-- SPAWN-ORDER.md is explicit that the stand-off height is fitted from ONE sample and must not be
-- asserted to the centimetre, so this asserts the XZ hard and the Y as a band.
local function onPad(plr, pad): (boolean, string)
	local hrp = rootOf(plr)
	if hrp == nil then return false, "no HumanoidRootPart" end
	local p, q = hrp.Position, pad.Position
	local top = q.Y + pad.Size.Y / 2
	local dx, dz = math.abs(p.X - q.X), math.abs(p.Z - q.Z)
	local ok = dx <= 3 and dz <= 3 and p.Y >= top and p.Y <= top + 8
	return ok, string.format("root at %s; pad %s top %.2f (dx %.2f, dz %.2f)", fmt(p), fmt(q), top, dx, dz)
end

--============================================================ the world as the engine finds it
h:run("server/Main.server")
h:advance(0.2)

local spawns = 0
local function countSpawns(x)
	for _, c in x:GetChildren() do
		if c:IsA("SpawnLocation") then spawns += 1 end
		countSpawns(c)
	end
end
countSpawns(workspace)
print(string.format("   %d enabled-or-not SpawnLocation(s) in the Workspace", spawns))

--============================================================ player one
local p1 = h:join("Walker", 424242)
h:advance(0.2)
h:run("client/Hud.client")
h:advance(0.2)

local z1 = zoneOf(p1)
assert(z1 ~= nil, "player one got no concourse")
local pad1 = z1:FindFirstChild("StartPad")
assert(pad1 ~= nil, "player one's concourse has no StartPad")
print(string.format("   p1 zone index %s, StartPad at %s", tostring(z1:GetAttribute("Index")), fmt(pad1.Position)))

-- The Head the emulator does not build (see the header). Connected AFTER the client script, so
-- the client's own CharacterAdded handler still runs first — exactly the order it sees in game.
local function attachHead(char)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Parent = char
end
p1.CharacterAdded:Connect(attachHead)

h.Players:simulateSpawn(p1, workspace)

-- 1. the engine's step has finished. Where is the player?
local ok1, why1 = onPad(p1, pad1)
truthy(ok1, "as soon as the engine has finished spawning, p1 stands on their own StartPad -- " .. why1)
local hrp1 = rootOf(p1)
truthy(hrp1 ~= nil and hrp1.Position.Magnitude > 100,
	"p1 is not left at the world origin, where this game has no floor at all -- root at "
		.. (hrp1 and fmt(hrp1.Position) or "nil"))

-- 2. and is still there a second later
h:advance(1.0)
local ok2, why2 = onPad(p1, pad1)
truthy(ok2, "a second later p1 is still on their own StartPad -- " .. why2)

-- 5. the carried tint light exists
local function lightOn(plr)
	local char = plr.Character
	local head = char and char:FindFirstChild("Head")
	if head == nil then return nil, "the character has no Head" end
	local l = head:FindFirstChild("AnomalyTintLight")
	if l == nil then return nil, "the Head carries no AnomalyTintLight" end
	return l, "ok"
end
local l1, lwhy = lightOn(p1)
truthy(l1 ~= nil and l1:IsA("SpotLight"),
	"a fresh character carries the tint light (the game's only cosmetic) -- " .. tostring(lwhy))

--============================================================ player two lands in their OWN hall
local p2 = h:join("Walker2", 515151)
h:advance(0.2)
local z2 = zoneOf(p2)
assert(z2 ~= nil, "player two got no concourse")
local pad2 = z2:FindFirstChild("StartPad")
assert(pad2 ~= nil, "player two's concourse has no StartPad")
truthy(z2:GetAttribute("Index") ~= z1:GetAttribute("Index"), "the two players got different zone indices")

h.Players:simulateSpawn(p2, workspace)
local ok3, why3 = onPad(p2, pad2)
truthy(ok3, "as soon as the engine has finished spawning, p2 stands on their OWN StartPad -- " .. why3)
local ok4 = onPad(p2, pad1)
truthy(not ok4, "p2 did not land in p1's hall (whose anomaly is not theirs to see)")

h:advance(1.0)
local r1, r2 = rootOf(p1), rootOf(p2)
truthy(r1 ~= nil and r2 ~= nil and (r1.Position - r2.Position).Magnitude > 500,
	string.format("the two players are in separate halls, %s studs apart",
		(r1 and r2) and string.format("%.0f", (r1.Position - r2.Position).Magnitude) or "?"))

--============================================================ respawn: the unrescued path
-- On JOIN, `beginPass` teleports at the end of PlayerAdded, so a lost CharacterAdded race is
-- healed by a second, unrelated write. A respawn has no such backstop -- `onCharacter` is the
-- only thing that will ever move that character -- so this is where a lost race is permanent.
h.Players:simulateSpawn(p1, workspace)
local ok5, why5 = onPad(p1, pad1)
truthy(ok5, "a RESPAWNED p1 stands on their own StartPad, with no beginPass to rescue them -- " .. why5)
h:advance(1.0)
local ok6, why6 = onPad(p1, pad1)
truthy(ok6, "and is still there a second after the respawn -- " .. why6)

--============================================================ the engine's own answer is the pad
-- (docs/complete-game-standard.md §1; robloxemu/SPAWN-ORDER.md §3, the preferred pattern) The player's
-- RespawnLocation is a real, enabled SpawnLocation on their OWN start pad, so the engine places them there
-- itself: no frame in the void over the world origin before onCharacter's teleport. It must be set BEFORE
-- PlayerAdded yields (the profile load), or a character that loads during the yield goes to whichever
-- enabled SpawnLocation the engine finds first: someone else's hall.
do
	for _, pp in { { p1, pad1, "p1" }, { p2, pad2, "p2" } } do
		local plr, pad, who = pp[1], pp[2], pp[3]
		local rl = plr.RespawnLocation
		truthy(rl ~= nil and rl:IsA("SpawnLocation") and rl.Enabled == true and rl:IsDescendantOf(workspace),
			who .. "'s RespawnLocation is a real, enabled SpawnLocation in the world (" .. tostring(rl and rl.ClassName) .. ")")
		if rl ~= nil then
			truthy(math.abs(rl.Position.X - pad.Position.X) < 0.01 and math.abs(rl.Position.Z - pad.Position.Z) < 0.01,
				who .. "'s spawn is on their own start pad (" .. fmt(rl.Position) .. " vs " .. fmt(pad.Position) .. ")")
			truthy(rl.Transparency >= 1 and rl.CanCollide == false and rl.Duration == 0,
				who .. "'s spawn is invisible and intangible, with no force-field bubble (the pad is what they see and stand on)")
		end
	end
	-- the ordering: make the profile load yield, and look while PlayerAdded is parked in it
	local store = h.game:GetService("DataStoreService"):GetDataStore("AnomalyObs_v1")
	rawset(store, "UpdateAsync", function(self, ...)
		task.wait(1)
		return getmetatable(self).UpdateAsync(self, ...)
	end)
	local co = coroutine.create(function() h:join("Slowpoke", 626262) end)
	local okCo = coroutine.resume(co)
	local slow = h.Players:GetPlayerByUserId(626262)
	local rl = slow and slow.RespawnLocation
	truthy(okCo and slow ~= nil and rl ~= nil and rl:IsA("SpawnLocation"),
		"while the profile is still loading, the new player's RespawnLocation is already set")
	rawset(store, "UpdateAsync", nil)
	h:advance(1.5)
	local zs = slow and zoneOf(slow)
	local padS = zs and zs:FindFirstChild("StartPad")
	truthy(padS ~= nil and rl ~= nil and math.abs(rl.Position.X - padS.Position.X) < 0.01,
		"and it is on the start pad of the hall that player then gets")
	h:leave(slow)
	h:advance(0.2)
	truthy(rl == nil or rl.Parent == nil, "a player who leaves takes their spawn with them")
end

--============================================================ the entrance is not a cliff
-- (review 2026-09-30, finding 7) The hall is open at +Z so the player can turn round at the start pad
-- and look out at the sky, and beyond z = +10 there is nothing: the floor ends at the entrance plane
-- and the zone is 100 studs over the void. Walking 14 studs back from the spawn dropped the player off
-- the world (a respawn: seconds, not the Day, but nobody said why). robloxemu has no physics, so this is
-- measured as geometry: from the start pad, every way out through the opening (a grid over the doorway,
-- floor to ceiling, so a jump does not clear it either) meets something COLLIDABLE before the floor ends.
do
	local zone = zoneOf(p1)
	local o = pad1.Position - Vector3.new(0, 1, -4) -- zone origin: the pad sits at origin + (0, 1, -4)
	local floor = zone:FindFirstChild("Floor")
	local floorEnd = floor.Position.Z + floor.Size.Z / 2 -- the entrance plane
	-- does the segment a -> b pass through part's box?
	local function segHits(part, a: Vector3, b: Vector3): boolean
		local la, lb = part.CFrame:PointToObjectSpace(a), part.CFrame:PointToObjectSpace(b)
		local half = part.Size / 2
		local t0, t1 = 0, 1
		for _, axis in { "X", "Y", "Z" } do
			local s, e, hx = la[axis], lb[axis], half[axis]
			local d = e - s
			if math.abs(d) < 1e-9 then
				if s < -hx or s > hx then return false end
			else
				local u0, u1 = (-hx - s) / d, (hx - s) / d
				if u0 > u1 then u0, u1 = u1, u0 end
				t0, t1 = math.max(t0, u0), math.min(t1, u1)
				if t0 > t1 then return false end
			end
		end
		return true
	end
	local open, total = {}, 0
	for x = -9, 9, 1.5 do
		for y = 1, 15, 1 do
			total += 1
			-- from just past the start pad's back edge (the pad itself must not count as a wall)
			local a = Vector3.new(o.X + x, o.Y + y, pad1.Position.Z + pad1.Size.Z / 2 + 0.5)
			local b = Vector3.new(o.X + x, o.Y + y, floorEnd + 0.01) -- just past the last of the floor
			local blocked = false
			for _, d in zone:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide and segHits(d, a, b) then
					blocked = true
					break
				end
			end
			if not blocked then table.insert(open, string.format("(%.1f, %.0f)", x, y)) end
		end
	end
	print(string.format("   entrance: %d of %d lines out of the hall are blocked before the floor ends",
		total - #open, total))
	truthy(#open == 0, string.format("nothing walks or jumps off the end of the floor: %d of %d lines out through the doorway are open, e.g. %s",
		#open, total, table.concat(open, " ", 1, math.min(#open, 6))))
end

--============================================================
truthy(not h:hadErrors(), "no runtime errors")
for _, e in h:errors() do print("   ERR " .. e) end

print(string.format("\ncheck_anomaly_spawn: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly spawn check failed", 0)
end
