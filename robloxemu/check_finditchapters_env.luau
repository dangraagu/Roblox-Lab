-- Find It! Chapters: the eye-candy glue, through the REAL server and client scripts (DESIGN.md §7, §18).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_env.luau 2>&1
--
-- Every chapter 1-15 and a Daily Case, opened the way the Case Book opens them, measured after the light settles:
--   * the light, grade and sky glide to the room's band (EnvBands at progress = chapter) and the five bands differ;
--   * the band's own decor, critters and weather are in the room and no other band's are; lamps light it;
--   * budgets in code: local parts <= Budget.LocalParts (the worst room measured), lights <= 4, emitters <= 4,
--     weather <= 2 emitters and <= 60 particles/s; the previous room is gone when the next one opens;
--   * the light never moves during a search; clearing a band's last chapter glides the room toward the next band;
--     Lighting is written at most LightingHz times a second; back in the hub, the hub's look returns.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-env", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService

-- a returning player with chapters 1-14 cleared (every chapter open) and the Daily open
do
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true, w = false, s = false } end
	DSS:GetDataStore("FindIt_Players_v1"):SetAsync("u_808", { data = { v = 1, book = { cleared = 14, stars = stars },
		daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 }, solved = 14, solvedAt = 1791000000, boarded = 14, seenIntro = true, firstJoin = 1791000000 } })
end
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, EnvBands, RoomArt, Bands, Ledger = mod("Config"), mod("EnvBands"), mod("RoomArt"), mod("Bands"), mod("Ledger")
local Bus = mod("ClientBus")
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")
local Lighting = h.Lighting

local plr = h:join("Eve", 808)
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Room.client"))
assert(h:tryRun("client/Board.client"))

local writesThisFrame, maxWritesPerSecond, frameLog = 0, 0, {}
local function frame(d)
	RunService.Heartbeat:Fire(d)
	RunService.RenderStepped:Fire(d)
	h:advance(d)
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(1 / 30, seconds - t)
		frame(d)
		t += d
	end
end
local function stats()
	local s = {}
	Bus.fire("__stats", s)
	return s
end
local function last(name)
	local s = remotes:FindFirstChild(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local localRoom = ws:FindFirstChild("FindItLocalRoom")
truthy(localRoom ~= nil, "the client's local room folder exists")
local function namesWith(prefix)
	local out = {}
	for _, c in localRoom:GetChildren() do
		if string.sub(c.Name, 1, #prefix) == prefix then table.insert(out, c) end
	end
	return out
end
local function colorClose(c, rgb, tol)
	return math.abs(c.R * 255 - rgb[1]) <= tol and math.abs(c.G * 255 - rgb[2]) <= tol and math.abs(c.B * 255 - rgb[3]) <= tol
end

run(2)
-- the hub's look, from the start
do
	local hubL = Config.Env.Hub.lighting
	truthy(math.abs(Lighting.ClockTime - hubL.ClockTime) < 0.05, string.format("the hub's light: ClockTime %.2f (hub %.2f)", Lighting.ClockTime, hubL.ClockTime))
end

local B = Config.Env.Bands
local worstParts, worstWhere = 0, ""
local seenClock = {}
local function openChapter(ch)
	if last("State") and last("State").where == "room" then
		remotes.Hub:simulateFireServer(plr)
		run(1.1)
	end
	remotes.Open:simulateFireServer(plr, ch)
	run(0.2)
end
for ch = 1, 15 do
	openChapter(ch)
	local st = last("State")
	eq(st and st.chapter, ch, "chapter " .. ch .. " opened")
	-- the glide: 0.8 s half-life; after 6 s the gap is under 1%
	run(6)
	local bi = Bands.forChapter(ch, Config)
	local band = B[bi]
	local want = EnvBands.sample(B, ch, "lighting")
	truthy(math.abs(Lighting.ClockTime - want.ClockTime) < 0.1, string.format("ch%d: ClockTime %.2f glided to %s's %.2f", ch, Lighting.ClockTime, band.id, want.ClockTime))
	local cc = Lighting:FindFirstChild("FxColorCorrection")
	truthy(cc and colorClose(cc.TintColor, band.colorCorrection.TintColor, 3), string.format("ch%d: the grade is %s's tint", ch, band.id))
	seenClock[bi] = Lighting.ClockTime
	-- decor: this band's sets, no other band's
	local decor = namesWith("Decor_")
	local mine, foreign = 0, 0
	for _, d in decor do
		local set = string.match(d.Name, "^Decor_([^_]+)_")
		if table.find(band.decor, set) then mine += 1 else foreign += 1 end
	end
	truthy(mine >= 6, string.format("ch%d: %d decor parts of %s's scenery", ch, mine, band.id))
	eq(foreign, 0, "ch" .. ch .. ": no other band's scenery")
	-- critters: this band's kinds
	local crit = namesWith("Critter_")
	local kinds = {}
	for _, c in crit do kinds[string.match(c.Name, "^Critter_([^_]+)_")] = true end
	for _, c in band.critters do truthy(kinds[c.kind], string.format("ch%d: the %s is in the room", ch, c.kind)) end
	for k in kinds do
		local ok = false
		for _, c in band.critters do if c.kind == k then ok = true end end
		truthy(ok, "ch" .. ch .. ": no stray critter (" .. k .. ")")
	end
	-- critters: INSIDE the room (a closed box: beyond a wall nothing is seen; REVIEW-1 round 2 D2 found the ship's
	-- fish there) and above head height, sampled over 4 s of their motion
	local pl = last("Room")
	local critBad = nil
	for _ = 1, 8 do
		for _, c in namesWith("Critter_") do
			local p = c.Position - Vector3.new(pl.origin[1], pl.origin[2], pl.origin[3])
			if math.abs(p.X) > pl.W / 2 or p.Z < 0 or p.Z > pl.D or p.Y < 10 or p.Y > Config.Room.Height then
				critBad = critBad or string.format("%s at (%.1f, %.1f, %.1f)", c.Name, p.X, p.Y, p.Z)
			end
		end
		run(0.5)
	end
	truthy(critBad == nil, string.format("ch%d: every critter part stays inside the %dx%d room, above head height (%s)", ch, pl.W, pl.D, critBad or "all inside"))
	-- weather: the band's kinds, capped
	local s = stats()
	local on, total = 0, 0
	for kind, rate in s.weatherOn do
		on += 1
		total += rate
		local ok = false
		for _, w in band.weather do if w.kind == kind then ok = true end end
		truthy(ok, "ch" .. ch .. ": weather " .. kind .. " belongs to " .. band.id)
	end
	-- every emitting weather host is centred INSIDE the room (REVIEW-1 round 2 D2: rain and drizzle used to fall
	-- beyond the east wall, where nothing is seen); rain and drizzle (RoomArt.WeatherOnGlass) run down the glass on
	-- the room side, within 0.6 studs of a wall, and the lowest a drop can fall (its speed, life and pull, read off
	-- the live emitter) stays above the props' height band (RoomArt.DECOR_HIGH): never over a prop
	local glassKinds, glassHosts = {}, 0
	for kind in s.weatherOn do if RoomArt.WeatherOnGlass[kind] then glassKinds[kind] = true end end
	for _, wh in s.weather or {} do
		local host, e = wh.host, wh.emitter
		if e and e.Enabled and e.Rate > 0 then
			local p = host.Position - Vector3.new(pl.origin[1], pl.origin[2], pl.origin[3])
			truthy(math.abs(p.X) <= pl.W / 2 and p.Z >= 0 and p.Z <= pl.D and p.Y <= Config.Room.Height,
				string.format("ch%d: the %s host is centred inside the room (%.1f, %.1f, %.1f)", ch, tostring(wh.kind), p.X, p.Y, p.Z))
			if glassKinds[wh.kind] then
				glassHosts += 1
				local x0, x1 = p.X - host.Size.X / 2, p.X + host.Size.X / 2
				local z0, z1 = p.Z - host.Size.Z / 2, p.Z + host.Size.Z / 2
				local onWall = (x1 >= pl.W / 2 - 0.6 or x0 <= -pl.W / 2 + 0.6 or z1 >= pl.D - 0.6) and x0 >= -pl.W / 2 and x1 <= pl.W / 2 and z1 <= pl.D
				truthy(onWall, string.format("ch%d: the %s runs down a wall on the room side (x %.2f..%.2f, z %.2f..%.2f)", ch, wh.kind, x0, x1, z0, z1))
				local life = e.Lifetime.Max
				local fall = e.Speed.Max * life + 0.5 * math.abs(e.Acceleration.Y) * life * life
				local lowest = p.Y - host.Size.Y / 2 - fall
				truthy(lowest >= RoomArt.DECOR_HIGH, string.format("ch%d: no %s drop falls below y %.2f (lowest %.2f): never over a prop", ch, wh.kind, RoomArt.DECOR_HIGH, lowest))
			end
		end
	end
	local nGlass = 0
	for _ in glassKinds do nGlass += 1 end
	truthy(glassHosts >= nGlass, string.format("ch%d: every falling weather kind runs down some glass (%d hosts for %d kinds)", ch, glassHosts, nGlass))
	print(string.format("  ch%2d %-11s decor %2d parts, critter parts %d, weather %d emitter(s) %.0f/s, %d local parts, %d lights, %d emitters",
		ch, band.id, mine, #crit, on, total, s.parts, s.lights, s.emitters))
	truthy(on >= 1 and on <= Config.Budget.WeatherEmitters and total <= Config.Budget.MaxEmitterRate + 1e-9,
		string.format("ch%d: weather %d emitters, %.0f particles/s (caps %d, %d)", ch, on, total, Config.Budget.WeatherEmitters, Config.Budget.MaxEmitterRate))
	-- lamps and budgets
	eq(#namesWith("Lamp_"), 4, "ch" .. ch .. ": four lamps")
	truthy(s.lights <= Config.Budget.Lights, string.format("ch%d: %d lights <= %d", ch, s.lights, Config.Budget.Lights))
	truthy(s.emitters <= Config.Budget.Emitters, string.format("ch%d: %d emitters <= %d", ch, s.emitters, Config.Budget.Emitters))
	truthy(s.parts <= Config.Budget.LocalParts, string.format("ch%d: %d local parts <= %d", ch, s.parts, Config.Budget.LocalParts))
	eq(s.refusedParts + s.refusedLights + s.refusedEmitters, 0, "ch" .. ch .. ": nothing refused by a budget")
	eq(#namesWith("Screen_") <= 3, true, "ch" .. ch .. ": only this room's screens stand (the last room was torn down)")
	local propParts = 0
	for _, p in pl.props do propParts += RoomArt.propParts(p.kind) end
	eq(#namesWith("Prop_"), propParts, "ch" .. ch .. ": every prop of this room is built, and only this room's")
	if s.parts > worstParts then worstParts, worstWhere = s.parts, "ch" .. ch end
end
print(string.format("  worst room of the 15: %d local parts in %s (cap %d)", worstParts, worstWhere, Config.Budget.LocalParts))
do
	local distinct = {}
	local n = 0
	for _, c in seenClock do
		local k = string.format("%.1f", c)
		if not distinct[k] then n += 1; distinct[k] = true end
	end
	eq(n, 5, "five bands, five different lights")
end

--============================================================ a rotation alone re-lays-out the HUD (no server push)
do
	local Responsive = mod("Responsive")
	local root = plr.PlayerGui:FindFirstChild("FindItHud"):FindFirstChild("Root")
	for _, vp in { { 800, 360 }, { 360, 800 }, { 1280, 720 } } do
		h:setViewport(vp[1], vp[2])
		h:advance(0.05) -- no frame, no remote: only Camera.ViewportSize changed
		local l = Responsive.layout(vp[1], vp[2], false)
		local want = vp[1] / l.scale
		truthy(math.abs(root.Size.X.Offset - want) < 0.5, string.format("rotating to %dx%d re-lays-out the HUD by itself (root %.0f, want %.0f design px)",
			vp[1], vp[2], root.Size.X.Offset, want))
	end
end

--============================================================ the worst case the generator allows: a full-budget room
do
	-- 300 chapter-15 rooms from the real generator, counted with the client's own art tables
	local Dressing, Rng = mod("Dressing"), mod("Rng")
	local r = Rng.new(99)
	local spec = Dressing.spec("book", 15, Config)
	local worst = 0
	for _ = 1, 300 do
		local room = Dressing.build(spec, function() return r:next() end, Config)
		local pl = Dressing.payload(room, {}, 5, Config)
		local n = RoomArt.roomParts(pl, B[5], Config)
		worst = math.max(worst, n)
	end
	print(string.format("  worst of 300 generated chapter-15 rooms: %d parts before the hazard reserve of %d (cap %d)", worst, Config.Budget.HazardParts, Config.Budget.LocalParts))
	truthy(worst + Config.Budget.HazardParts <= Config.Budget.LocalParts, "the worst generated room plus the hazard reserve fits the cap")
end

--============================================================ the light holds still during a search
do
	openChapter(7)
	run(20) -- past the intro, and the glide from the observatory fully settled (0.5^(20/0.8) of the change left)
	local pl = last("Room")
	local before = { Lighting.ClockTime, Lighting.Brightness }
	local o = pl.origin
	local p = pl.props[1]
	hrp.CFrame = CFrame.new(o[1] + p.x * 0.8, 3, o[3] + math.max(4, p.z * 0.8))
	local w0 = stats().lightingWrites
	remotes.Search:simulateFireServer(plr, p.id)
	run(1.2)
	local w1 = stats().lightingWrites
	truthy(math.abs(Lighting.ClockTime - before[1]) < 1e-3 and math.abs(Lighting.Brightness - before[2]) < 1e-3, "a search changes nothing in the light")
	eq(w1 - w0, 0, "no Lighting property is written during a search (settled light)")
	eq(last("State").progress, 7, "the band's progress is still the chapter")
end

--============================================================ the ship's storm: lightning in the portholes, the light untouched
-- REVIEW-1 round 2 D2: the store text promises "a ship's cabin in a storm" and the cabin showed no weather at all. Now
-- the rain runs down the portholes (above) and lightning flashes in them; a flash changes the porthole glass only,
-- never a Lighting property, so a clue colour never changes under it.
do
	openChapter(10)
	run(20) -- the glide settled (0.5^(20/0.8) of the change left)
	local ports = {}
	for _, d in namesWith("Decor_portholes_port") do
		if string.match(d.Name, "^Decor_portholes_port[EW]%d") then table.insert(ports, d) end
	end
	eq(#ports, 4, "the ship has four porthole views")
	local w0, f0 = stats().lightingWrites, stats().lightning or 0
	local neonFrames, darkFrames, frames = 0, 0, 0
	local function lightNow()
		return string.format("%.4f %.4f %.4f %.3f %.3f %.3f", Lighting.ClockTime, Lighting.Brightness, Lighting.ExposureCompensation,
			Lighting.Ambient.R, Lighting.Ambient.G, Lighting.Ambient.B)
	end
	local light0, lightMoved = lightNow(), 0
	for _ = 1, 30 * 30 do -- 30 s at 30 fps
		frame(1 / 30)
		frames += 1
		if lightNow() ~= light0 then lightMoved += 1 end
		local lit, dark = false, 0
		for _, p in ports do
			if p.Material == Enum.Material.Neon then lit = true end
			if p.Material ~= Enum.Material.Neon and colorClose(p.Color, { 28, 40, 72 }, 3) then dark += 1 end
		end
		if lit then neonFrames += 1 end
		if dark == #ports then darkFrames += 1 end -- the night-sea view, restored after each flash
	end
	local flashes = (stats().lightning or 0) - f0
	print(string.format("  the ship's storm: %d lightning flashes in 30 s, the portholes lit on %d of %d frames", flashes, neonFrames, frames))
	truthy(flashes >= 2 and flashes <= 8, string.format("D2: lightning flashes in the portholes now and then (%d in 30 s)", flashes))
	truthy(neonFrames >= flashes and neonFrames <= frames * 0.1, string.format("D2: each flash is short (%d of %d frames lit)", neonFrames, frames))
	eq(stats().lightingWrites - w0, 0, "D2: lightning writes no Lighting property (a clue colour never changes under it)")
	eq(lightMoved, 0, "D2: the light (clock, brightness, exposure, ambient) is the same on every frame of the storm")
	truthy(darkFrames >= frames * 0.9, string.format("D2: between flashes the porthole views are dark (unlit on %d of %d frames)", darkFrames, frames))
end

--============================================================ Lighting writes are rate-limited (LightingHz)
do
	-- count the frames that wrote anything, during a fresh glide (hub -> greenhouse)
	remotes.Hub:simulateFireServer(plr)
	run(4)
	remotes.Open:simulateFireServer(plr, 8)
	local writingFrames, frames = 0, 0
	local prev = stats().lightingWrites
	for _ = 1, 90 do -- 3 s at 30 fps
		frame(1 / 30)
		frames += 1
		local now = stats().lightingWrites
		if now > prev then writingFrames += 1 end
		prev = now
	end
	print(string.format("  a fresh glide: Lighting written on %d of %d frames in 3 s at 30 fps", writingFrames, frames))
	truthy(writingFrames <= 3 * Config.Env.LightingHz + 1, string.format("Lighting written on %d of %d frames in 3 s (at most %d a second)", writingFrames, frames, Config.Env.LightingHz))
end

--============================================================ clearing a band's last chapter glides toward the next band
do
	openChapter(12)
	run(3.5)
	local pl = last("Room")
	-- the server-only rig names the hidden props (this check reads it to finish the room quickly)
	local HttpService = h.game:GetService("HttpService")
	local rigv = h.game:GetService("ServerStorage").FindIt.Attempts:FindFirstChild("808")
	local secret = HttpService:JSONDecode(rigv.Value)
	local o = pl.origin
	local function propOf(id) for _, q in pl.props do if q.id == id then return q end end end
	run(1)
	local shipClock = Lighting.ClockTime
	for _, id in secret.hidden do
		local q = propOf(id)
		hrp.CFrame = CFrame.new(o[1] + q.x * 0.85, 3, o[3] + q.z * 0.85 + 0.5)
		remotes.Search:simulateFireServer(plr, id)
		run(1.1)
	end
	local st = last("State")
	eq(st.state, "done", "chapter 12 cleared")
	eq(st.progress, 13, "the clear moves progress to the observatory's 13")
	run(6)
	local obs = EnvBands.sample(B, 13, "lighting").ClockTime
	truthy(math.abs(Lighting.ClockTime - obs) < 0.15, string.format("the ship's cabin glides to the observatory's light (%.2f -> %.2f, target %.2f)", shipClock, Lighting.ClockTime, obs))
end

--============================================================ a Daily Case uses its theme's band; the hub returns
do
	remotes.Hub:simulateFireServer(plr)
	run(1.2)
	local hubL = Config.Env.Hub.lighting
	run(6)
	truthy(math.abs(Lighting.ClockTime - hubL.ClockTime) < 0.1, string.format("back in the hub, the hub's light returns (%.2f)", Lighting.ClockTime))
	eq(#namesWith("Prop_"), 0, "no room parts stay behind in the hub")
	eq(#namesWith("Decor_"), 0, "no decor stays behind in the hub")
	remotes.OpenDaily:simulateFireServer(plr)
	run(6)
	local st = last("State")
	eq(st.kind, "daily", "the Daily opens")
	local day = Ledger.dayIndex(os.time())
	local bi = Ledger.dailyBand(day, Config)
	eq(st.band, bi, "the Daily's band is its theme (" .. B[bi].id .. ")")
	local want = EnvBands.sample(B, Bands.progressForDaily(day, Config), "lighting").ClockTime
	truthy(math.abs(Lighting.ClockTime - want) < 0.1, string.format("the Daily's room has %s's light", B[bi].id))
end

--============================================================ BOOK ONE SOLVED: the hub's Case Book turns gold for this player
do
	local book = ws.FindItWorld.Hub.CaseBook
	local before = book.Color
	local prof = {}
	for k, v in remotes.Profile:sentTo(plr)[#remotes.Profile:sentTo(plr)].args[1] do prof[k] = v end
	prof.bookSolved = true
	remotes.Profile:FireClient(plr, prof)
	run(0.2)
	truthy(colorClose(book.Color, Config.Reserved.Gold, 2), "a player who solved Book One sees a gold Case Book")
	truthy(not colorClose(before, Config.Reserved.Gold, 2), "it was not gold before")
end

--============================================================ a re-dress leaves no found item floating at an old spot
do
	remotes.Hub:simulateFireServer(plr)
	run(1.2)
	remotes.Open:simulateFireServer(plr, 5)
	run(3.5)
	local pl = last("Room")
	local HttpService = h.game:GetService("HttpService")
	local secret = HttpService:JSONDecode(h.game:GetService("ServerStorage").FindIt.Attempts:FindFirstChild("808").Value)
	local o = pl.origin
	local q = nil
	for _, p in pl.props do if p.id == secret.hidden[1] then q = p end end
	hrp.CFrame = CFrame.new(o[1] + q.x * 0.85, 3, o[3] + q.z * 0.85 + 0.5)
	remotes.Search:simulateFireServer(plr, q.id)
	run(1.2)
	eq(#namesWith("Item_"), 1, "the found item stands on its prop")
	remotes.Pause:simulateFireServer(plr)
	run(0.2)
	remotes.Resume:simulateFireServer(plr)
	run(3.5)
	eq(last("Room").redress, true, "re-dressed")
	eq(#namesWith("Item_"), 0, "after a re-dress no found item floats where its prop used to be (the chip stays gold)")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	failed += 1
	print("FAIL: a warning: " .. w)
end
print(string.format("find it env: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_env failed", 0) end
