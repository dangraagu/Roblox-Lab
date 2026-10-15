-- Find It! Chapters: BOOK ONE SOLVED, the brag moment (docs/complete-game-standard.md §2), through the REAL server and
-- the REAL HUD, Room and Board clients on a phone (800x360, touch).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_brag.luau 2>&1
--
-- A returning player with 14 chapters cleared walks to the lectern, opens the Case Book, taps Continue (chapter 15),
-- searches the nine hiding props (read from the server's ServerStorage copy: a test may peek, a client cannot) and
-- clears it. Then: the card says BOOK ONE SOLVED and offers no Next; the observatory's dome slit fades and three gold
-- shooting stars cross it; another player in the server is told; the solver wears the gold tag; the Case Book in
-- the hub is gold for the solver; the public board ranks the 15; a rejoin keeps all of it.
-- Adapted from the 2026-10-07 reviewer's probe_brag (which printed, and asserted nothing).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-brag", viewport = { 800, 360 }, touch = true })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
do
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true, w = false, s = false } end
	DSS:GetDataStore("FindIt_Players_v1"):SetAsync("u_515", { data = { v = 1, book = { cleared = 14, stars = stars },
		daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 }, solved = 14, solvedAt = 1791000000, boarded = 14, seenIntro = true, firstJoin = 1791000000 } })
end
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Bus = mod("Config"), mod("ClientBus")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")
local function frame(d) RunService.Heartbeat:Fire(d); RunService.RenderStepped:Fire(d); h:advance(d) end
local function run(s) local t = 0 while t < s - 1e-9 do local d = math.min(1 / 20, s - t); frame(d); t += d end end
local function last(name, p) local s = remotes:FindFirstChild(name):sentTo(p); return s[#s] and s[#s].args[1] end
local function count(prefix)
	local n = 0
	local lr = ws:FindFirstChild("FindItLocalRoom")
	for _, c in (lr and lr:GetChildren() or {}) do if string.sub(c.Name, 1, #prefix) == prefix then n += 1 end end
	return n
end

-- REVIEW-1 round 2 D3: can a player SEE it? The box a part fills (from its CFrame and Size), a ray against it (slabs),
-- and the first OPAQUE part (Transparency < 0.5) of the local room a ray from an eye to a point meets. Moving or
-- passing things (critters, hazards, found items, the brag's own stars) and the invisible emitter hosts are not walls.
local function aabb(p)
	local cf, s = p.CFrame, p.Size
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w = cf * Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)
				local c = { w.X, w.Y, w.Z }
				for k = 1, 3 do
					lo[k] = math.min(lo[k], c[k])
					hi[k] = math.max(hi[k], c[k])
				end
			end
		end
	end
	return lo, hi
end
local function rayBox(o, d, lo, hi)
	local t0, t1 = 0, math.huge
	for k = 1, 3 do
		if math.abs(d[k]) < 1e-12 then
			if o[k] < lo[k] or o[k] > hi[k] then return nil end
		else
			local a, b = (lo[k] - o[k]) / d[k], (hi[k] - o[k]) / d[k]
			if a > b then a, b = b, a end
			t0, t1 = math.max(t0, a), math.min(t1, b)
			if t0 > t1 then return nil end
		end
	end
	return t0
end
local NOT_WALLS = { "Critter_", "Hazard", "Item_", "WeatherHost_", "BurstHost", "GlintHost", "ShootingStar_" }
local function opaqueParts(except)
	local out = {}
	for _, c in ws.FindItLocalRoom:GetChildren() do
		local skip = c == except or not c:IsA("BasePart") or c.Transparency >= 0.5
		for _, pre in NOT_WALLS do if string.sub(c.Name, 1, #pre) == pre then skip = true end end
		if not skip then table.insert(out, c) end
	end
	return out
end
local function firstHit(eye, target)
	local o = { eye.X, eye.Y, eye.Z }
	local d = { target.X - eye.X, target.Y - eye.Y, target.Z - eye.Z }
	local best, bestT = nil, math.huge
	for _, c in opaqueParts(nil) do
		local lo, hi = aabb(c)
		local t = rayBox(o, d, lo, hi)
		if t and t <= 1 + 1e-9 and t < bestT then best, bestT = c, t end
	end
	return best
end
local function buried(p)
	local q = p.Position
	for _, c in opaqueParts(p) do
		local lo, hi = aabb(c)
		if q.X > lo[1] and q.X < hi[1] and q.Y > lo[2] and q.Y < hi[2] and q.Z > lo[3] and q.Z < hi[3] then return c.Name end
	end
	return nil
end

local watcher = h:join("Watcher", 516)
local plr = h:join("Bragger", 515)
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client")); assert(h:tryRun("client/Room.client")); assert(h:tryRun("client/Board.client"))
run(1)
local hud = plr.PlayerGui.FindItHud.Root
eq(last("Profile", plr).cleared, 14, "the returning player has 14 chapters cleared")
eq(last("Profile", plr).continue, 15, "Continue points at chapter 15")

-- the lectern, the menu, Continue
local book = ws.FindItWorld.Hub.CaseBook
local goldBefore = book.Color
hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 4)
run(0.2)
book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
run(1.2)
truthy(hud.Menu.Visible, "the Case Book prompt opens the menu")
local cont = hud.Menu.List:FindFirstChild("Continue")
truthy(cont and string.find(cont.Text, "Chapter 15", 1, true) ~= nil, "the menu's Continue row says Chapter 15")
cont.Activated:Fire()
run(0.3)
local st = last("State", plr)
eq(st.where, "room", "Continue opens a room")
eq(st.chapter, 15, "chapter 15")
eq(st.band, 5, "in the Star Observatory band")
run(3.2)
truthy(count("Decor_") > 0, "the observatory is dressed")
local slit = nil
for _, c in ws.FindItLocalRoom:GetChildren() do if string.find(c.Name, "domeSlit", 1, true) then slit = c end end
truthy(slit ~= nil, "the observatory has a dome slit")
local slitBefore = slit and slit.Transparency

-- search every hiding prop (the test peeks at the server's ServerStorage copy)
local rig = HttpService:JSONDecode(ServerStorage.FindIt.Attempts:FindFirstChild("515").Value)
local pl = last("Room", plr)

-- D3: from a player's eye near the door, the slit is the first thing the eye meets on its way up (round 2 found it
-- inside the opaque dome disc: the "dome opens" beat could never be seen)
local o3 = Vector3.new(pl.origin[1], pl.origin[2], pl.origin[3])
local eye = o3 + Vector3.new(3, 5.5, 4)
local sky = nil
for _, c in ws.FindItLocalRoom:GetChildren() do if string.find(c.Name, "domeSky", 1, true) then sky = c end end
local slitPoint = slit and Vector3.new(slit.Position.X, slit.Position.Y, o3.Z + pl.D * 0.3)
do
	local hit = slit and firstHit(eye, slitPoint)
	eq(hit and hit.Name, slit and slit.Name, "D3: before the brag, a ray from the eye to the dome slit meets the slit first (it is in sight)")
end
local function propOf(id) for _, q in pl.props do if q.id == id then return q end end end
for _, id in rig.hidden do
	local q = propOf(id)
	local o = pl.origin
	local wx, wz = o[1] + q.x, o[3] + q.z
	local cx, cz = o[1], o[3] + pl.D / 2
	local d = Vector3.new(cx - wx, 0, cz - wz)
	local u = if d.Magnitude > 0 then d.Unit else Vector3.new(0, 0, 1)
	hrp.CFrame = CFrame.new(wx + u.X * 3, 3, wz + u.Z * 3)
	run(0.1)
	Bus.fire("tapProp", id); run(0.1)
	Bus.fire("tapProp", id); run(1.1)
end
eq(#rig.hidden, Config.Chapters[15].n, "chapter 15 hides " .. Config.Chapters[15].n .. " things")
-- the stars leave 0.6 s apart and fly 1.2 s each: collect the distinct ones while they fly, and where each first shows
local starNames, t = {}, 0
local starsBuried = {}
while t < 9 do
	run(0.1)
	t += 0.1
	local lr = ws:FindFirstChild("FindItLocalRoom")
	for _, c in (lr and lr:GetChildren() or {}) do
		if string.sub(c.Name, 1, 13) == "ShootingStar_" then
			if not starNames[c.Name] then
				local inside = buried(c)
				if inside then table.insert(starsBuried, c.Name .. " inside " .. inside) end
			end
			starNames[c.Name] = true
		end
	end
end
eq(#starsBuried, 0, "D3: no shooting star starts inside an opaque part (" .. table.concat(starsBuried, ", ") .. ")")
local seenStars = 0
for _ in starNames do seenStars += 1 end
run(8)
st = last("State", plr)
eq(st.state, "done", "the room is done")
eq(st.result and st.result.reason, "found", "everything was found")
eq(st.result and st.result.bookSolved, true, "the result says BOOK ONE SOLVED")
eq(st.result and st.result.solved, 15, "Cases Solved is 15")
truthy(hud.Card.Visible and hud.Card.Title.Text == Config.Text.BookSolved, "the card says " .. Config.Text.BookSolved .. ": " .. hud.Card.Title.Text)
truthy(not hud.Card.Buttons.NextButton.Visible, "there is no Next after the last chapter")
truthy(hud.Card.Buttons.HubButton.Visible and hud.Card.Buttons.RetryButton.Visible, "Hub and Retry are offered")
truthy(seenStars >= 3, "three gold shooting stars cross the dome (" .. seenStars .. " distinct)")
eq(count("ShootingStar_"), 0, "the shooting stars are gone afterwards")
truthy(slit ~= nil and slit.Transparency > (slitBefore or 0) + 0.5, string.format("the dome slit fades (%.2f -> %.2f)", slitBefore or -1, slit and slit.Transparency or -1))
do
	-- D3: with the slit open, the same eye now sees the night-sky strip behind it
	local skyPoint = slitPoint and Vector3.new(slitPoint.X, (sky and sky.Position.Y) or (slitPoint.Y + 0.4), slitPoint.Z)
	local hit = skyPoint and firstHit(eye, skyPoint)
	truthy(sky ~= nil and hit == sky, "D3: after the brag the eye sees the night sky through the open slit (first opaque part: " .. tostring(hit and hit.Name) .. ")")
	truthy(sky ~= nil and sky.Material == Enum.Material.Neon and sky.Transparency < 0.5, "D3: the sky strip glows (Neon)")
end
local notes = remotes.Notice:sentTo(watcher)
local told = false
for _, n in notes do if n.args[1].kind == "brag" and string.find(n.args[1].text or "", "Bragger", 1, true) then told = true end end
truthy(told, "another player in the server is told that Bragger solved Book One")
truthy(char:FindFirstChild("FindItTag", true) ~= nil, "the solver wears the tag")

-- the hub: a gold Case Book for the solver
hud.Card.Buttons.HubButton.Activated:Fire()
run(1)
eq(last("State", plr).where, "hub", "Hub returns to the hub")
truthy((hrp.Position - ws.FindItWorld.Hub.HubSpawn.Position).Magnitude < 12, "the solver stands at the hub spawn")
local g = Config.Reserved.Gold
truthy(math.abs(book.Color.R * 255 - g[1]) < 2 and math.abs(book.Color.G * 255 - g[2]) < 2 and math.abs(book.Color.B * 255 - g[3]) < 2,
	string.format("the Case Book is gold for the solver (%.0f %.0f %.0f)", book.Color.R * 255, book.Color.G * 255, book.Color.B * 255))
truthy(book.Color ~= goldBefore, "it was not gold before")
run(62)
local row1 = ws.FindItWorld.Hub.CasesBoard.PublicFace:FindFirstChild("Row_1")
truthy(row1 and string.find(row1.Text, "Bragger", 1, true) and string.find(row1.Text, "15", 1, true), "the public board's first row is Bragger with 15: " .. tostring(row1 and row1.Text))

-- a rejoin keeps it
h:leave(plr)
run(2)
local plr2 = h:join("Bragger", 515)
run(1)
local c2 = h.Players:simulateSpawn(plr2, ws)
run(1)
local p2 = last("Profile", plr2)
eq(p2.cleared, 15, "rejoin: 15 chapters cleared")
eq(p2.bookSolved, true, "rejoin: Book One stays solved")
truthy(c2:FindFirstChild("FindItTag", true) ~= nil, "rejoin: the tag is back")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	failed += 1
	print("FAIL: a warning: " .. w)
end
print(string.format("find it brag: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_brag failed", 0) end
