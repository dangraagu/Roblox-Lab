-- Outpost Zero — the first builds, whatever a new player presses (REVIEW-1 F5).
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_start.luau 2>&1
--
-- The walk and the pacing model always follow the ★, so they never met this: a new player who taps two Homes (or two
-- Workshops) first spent the 30 starting credits on one side. Population = min(settlers, jobs) stayed 0, so there was
-- no income; the safety net needs income; the save kept 0 credits; the city was dead for good. Here, through the real
-- server and the real prompts:
--   1. two Homes first: the second is refused and says why; the Workshop it asks for is affordable and works
--   2. two Workshops first: the mirror
--   3. players who press random lots in reach (never the ★) for a minute, then follow the ★: every one gets citizens
--   4. a stranded record saved before this fix (two Homes, 0 credits) is lifted at the join, once, and logged

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local remotes = RS:FindFirstChild("CityRemotes")
local T = Config.Tutorial
local function stateOf(plr)
	local sent = remotes.State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function lastToast(plr)
	local t = remotes.Toast:sentTo(plr)
	return t[#t] and t[#t].args[1] or nil
end
local function join(name, uid)
	local plr = h:join(name, uid)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	return plr, char:FindFirstChild("HumanoidRootPart")
end
-- stand 2 studs street-side of the post (within the prompt's reach) and press
local function press(plr, hrp, lot)
	local post = lot.Post
	local centre = plr.RespawnLocation.Parent.Rock.Position
	local dir = Vector3.new(centre.X - post.Position.X, 0, centre.Z - post.Position.Z).Unit
	hrp.CFrame = CFrame.new(post.Position.X + dir.X * 2, 3.5, post.Position.Z + dir.Z * 2)
	assert((hrp.Position - post.Position).Magnitude <= post.BuildPrompt.MaxActivationDistance, "within reach")
	post.BuildPrompt.Triggered:Fire(plr)
	h:advance(0.3)
end
local function lotsOf(plr, action)
	local out = {}
	for _, lot in plr.RespawnLocation.Parent.Lots:GetChildren() do
		if lot.Post.BuildPrompt.ActionText == action then table.insert(out, lot) end
	end
	table.sort(out, function(a, b) return a.Name < b.Name end)
	return out
end

--============================================================================ 1-2. two of a kind first
for _, case in { { zone = "Home", other = "Workshop", hint = T.NeedJobs, uid = 4242 }, { zone = "Workshop", other = "Home", hint = T.NeedHomes, uid = 4243 } } do
	local plr, hrp = join("Kid" .. case.uid, case.uid)
	local same = lotsOf(plr, "Build " .. case.zone)
	eq(#same, 3, "set-up: three " .. case.zone .. " lots in the Landing Field")
	press(plr, hrp, same[1])
	local st = stateOf(plr)
	eq(st.credits, 15, "the first " .. case.zone .. " builds (15 left)")
	press(plr, hrp, same[2])
	st = stateOf(plr)
	eq(same[2]:FindFirstChild("Body"), nil, "a second " .. case.zone .. " before any " .. case.other .. " is refused")
	eq(st.credits, 15, "...and costs nothing: 15 credits left for the " .. case.other)
	eq(lastToast(plr), case.hint, "...and the toast says why and what to build")
	eq(st.star and st.star.zone, if case.other == "Home" then "H" else "W", "the ★ is the " .. case.other)
	truthy(st.star and st.credits >= st.star.price, "...and it is affordable now")
	local other = lotsOf(plr, "Build " .. case.other)
	press(plr, hrp, other[1])
	st = stateOf(plr)
	eq(st.population, 4, "building the " .. case.other .. " makes 4 citizens")
	eq(st.income, 1, "...earning a credit a second")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ 3. random pressers, then the ★
do
	local r = Random.new(20261007)
	local players, citizens, refusals, presses, deadEver = 0, 0, 0, 0, 0
	local slowest = 0
	for n = 1, 24 do
		local plr, hrp = join("Rnd" .. n, 5000 + n)
		players += 1
		local lots = plr.RespawnLocation.Parent.Lots:GetChildren()
		local t0 = h.scheduler:now()
		while h.scheduler:now() - t0 < 60 do
			local lot = lots[r:NextInteger(1, #lots)]
			local n0 = #remotes.Toast:sentTo(plr)
			press(plr, hrp, lot)
			presses += 1
			local tt = remotes.Toast:sentTo(plr)
			if #tt > n0 and (tt[#tt].args[1] == T.NeedJobs or tt[#tt].args[1] == T.NeedHomes) then refusals += 1 end
			h:advance(r:NextNumber() * 2)
		end
		-- then follow the ★ for up to 2 minutes
		local t1 = h.scheduler:now()
		while h.scheduler:now() - t1 < 120 and stateOf(plr).population == 0 do
			local st = stateOf(plr)
			if st.star and st.credits >= st.star.price then
				press(plr, hrp, plr.RespawnLocation.Parent.Lots:FindFirstChild("Lot_" .. st.star.key))
			end
			h:advance(1)
		end
		local st = stateOf(plr)
		if st.population > 0 and st.income > 0 then citizens += 1 else deadEver += 1 end
		slowest = math.max(slowest, h.scheduler:now() - t1)
		h:leave(plr)
		h:advance(1)
	end
	print(string.format("  %d random pressers: %d presses, %d refused as stranding; %d got citizens (the slowest %.0f s after following the ★)",
		players, presses, refusals, citizens, slowest))
	truthy(refusals > 0, "set-up: random presses did try to strand cities")
	eq(citizens, players, "every random presser gets citizens once they follow the ★")
	truthy(slowest <= 3, string.format("...at once: the ★'s build is always affordable (slowest %.0f s)", slowest))
end

--============================================================================ 4. a record stranded before this fix is lifted at the join
do
	local UID = 4300
	local now = os.time()
	-- two Homes on whatever lots the seed made Homes: find them with the real layout
	local City, Rng = h:_require(RS:FindFirstChild("City")), h:_require(RS:FindFirstChild("Rng"))
	local L = City.layout(Config, 4300, Rng)
	local homes = {}
	for _, l in L.lots do
		if l.d == 1 and l.zone == "H" then table.insert(homes, l.key) end
	end
	local lots = { [homes[1]] = 1, [homes[2]] = 1 }
	store:SetAsync("u_" .. UID, { data = { v = 1, seed = 4300, credits = 0, lifetime = 30, lots = lots, savedAt = now - 86400,
		ordersUntil = now - 86400 + 600, popAt = 0, airshipSeen = false, tutorial = 2 } })
	local w0 = #h.warnings
	local plr, hrp = join("Stranded", UID)
	local st = stateOf(plr)
	eq(st.population, 0, "set-up: a saved city with two Homes and no Workshop")
	eq(st.credits, 15, "the join lifts it to the Workshop's 15 credits")
	local lifted = 0
	for i = w0 + 1, #h.warnings do
		if string.find(h.warnings[i], "no citizens", 1, true) then lifted += 1 end
	end
	eq(lifted, 1, "...and logs it once")
	eq(st.star and st.star.zone, "W", "the ★ is the Workshop")
	press(plr, hrp, plr.RespawnLocation.Parent.Lots:FindFirstChild("Lot_" .. st.star.key))
	st = stateOf(plr)
	eq(st.population, 4, "the Workshop makes 4 citizens")
	truthy(st.income > 0, "...and the city earns again")
	h:leave(plr)
	h:advance(1)
	local saved = store:GetAsync("u_" .. UID).data
	truthy(saved.lifetime >= saved.credits, "the lift counts in lifetime, which never trails credits")
	-- the lift is for a city that cannot otherwise start: a normal new city gets no extra credits
	local plr2 = join("Fresh", 4301)
	eq(stateOf(plr2).credits, 30, "a new city starts with 30, as before")
	h:leave(plr2)
	h:advance(1)
end

print("")
local stray = {}
for _, w in h.warnings do
	if not string.find(w, "no citizens", 1, true) then table.insert(stray, w) end
end
eq(#stray, 0, "no other warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero start: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero start check failed", 0) end
