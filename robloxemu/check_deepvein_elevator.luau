-- Deep Vein — THE ELEVATOR HAS A RIDE BUDGET. Second review 2026-10-09, MEDIUM: `ElevatorEvent` had no cooldown.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_elevator.luau
--
-- Every ride moves the streamed band and builds the layers at the landing synchronously, and SURFACE also sells.
-- A client that fired the remote in a loop, alternating up and down from a deep shaft, spent the server's frame
-- for every player in it. The server now takes each ride from a token bucket (Mine.takeRide,
-- Config.Mine.Elevator): Burst rides at once, then one per RefillSeconds.
--
-- This file drives the REAL server and asserts, on what it really does:
--   1. a remote fired 60 times in one frame is served Burst times, not 60;
--   2. a second of spamming is held to the refill rate, and builds a bounded number of parts;
--   3. one refused press says why, and a flood of them does not flood the toast feed;
--   4. an honest miner (a ride every few seconds, and a double tap) is never refused;
--   5. the budget is per player: one miner's spam does not cost another miner a ride;
--   6. a rejoin starts with a full budget (nothing leaks in the per-player table).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

local Config = require("../deep-vein/src/shared/Config")
local E = Config.Mine.Elevator or { Burst = 2, RefillSeconds = 0.75 }
local SPAMMER, HONEST = 5151, 5252
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local function profileData()
	return {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 0,
		rebirths = 0, depthLayer = 30, bestLayer = 30, runEarned = 0,
	}
end
store:SetAsync("u_" .. SPAMMER, { data = profileData() })
store:SetAsync("u_" .. HONEST, { data = profileData() })

assert(h:tryRun("server/Main.server"))
h:advance(1)

local remotes = h.services.ReplicatedStorage:FindFirstChild("VeinRemotes")
local ElevatorEvent = remotes:FindFirstChild("Elevator")
local ToastEvent = remotes:FindFirstChild("Toast")

local function enter(name, uid)
	local plr = h:join(name, uid)
	h:advance(1)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	return plr, plr.Character:FindFirstChild("HumanoidRootPart")
end

-- A ride is SERVED when the root part moves between the mouth and the shaft bottom. Alternating directions
-- means every served ride changes the height, and a refused one changes nothing.
local function fire(plr, hrp, dir)
	local y0 = hrp.CFrame.Position.Y
	ElevatorEvent:simulateFireServer(plr, dir)
	return math.abs(hrp.CFrame.Position.Y - y0) > 1
end

local spammer, sHrp = enter("Spammer", SPAMMER)
local honest, hHrp = enter("Honest", HONEST)
local sToasts = 0
ToastEvent.OnClientEvent:Connect(function() end)
local function toastsTo(plr)
	return #ToastEvent:sentTo(plr)
end

--======================================================================= 0. the fixture can ride at all
do
	truthy(fire(spammer, sHrp, "down"), "the fixture's DESCEND moves the miner (a saved shaft 30 layers deep)")
	h:advance(5)
	truthy(fire(spammer, sHrp, "up"), "...and SURFACE brings them back")
	h:advance(5)
end

--======================================================================= 1. sixty fires in one frame
do
	local served = 0
	for i = 1, 60 do
		if fire(spammer, sHrp, i % 2 == 1 and "down" or "up") then served += 1 end
	end
	eq(served, E.Burst, "60 rides fired in one frame: exactly Burst are served")
end

--======================================================================= 2. a second of spamming, 60 a frame
do
	h:advance(10) -- a full bucket again
	local parts0 = #h.workspace:GetDescendants()
	local served, toasts0 = 0, toastsTo(spammer)
	local n = 0
	for _ = 1, 60 do
		for _ = 1, 10 do
			n += 1
			if fire(spammer, sHrp, sHrp.CFrame.Position.Y > -1 and "down" or "up") then served += 1 end
		end
		h:advance(1 / 60)
	end
	local cap = E.Burst + math.ceil(1 / E.RefillSeconds) + 1
	truthy(served <= cap, string.format("600 fires over one second: %d served, at most %d", served, cap))
	truthy(served >= E.Burst, "...and the budgeted rides WERE served (" .. served .. ")")
	-- 3. the refusals are explained, once, not 590 times
	local told = toastsTo(spammer) - toasts0
	truthy(told >= 1, "a refused press says why (" .. told .. " toast(s))")
	truthy(told <= served + 2, "...and ~590 refused presses do not flood the toast feed (" .. told .. " toasts)")
	local sent = ToastEvent:sentTo(spammer)
	local sawReason = false
	for i = toasts0 + 1, #sent do
		if string.find(tostring(sent[i].args[1]), "levator", 1, true) then sawReason = true end
	end
	truthy(sawReason, "the refusal names the elevator")
	local _ = parts0
end

--======================================================================= 5. per player (asked while the spammer is dry)
do
	truthy(fire(honest, hHrp, "down"), "another miner rides while the spammer's bucket is empty")
	truthy(fire(honest, hHrp, "up"), "...and straight back up: the double tap is served")
	h:advance(10)
end

--======================================================================= 4. the honest pattern
do
	local refused = 0
	for i = 1, 20 do
		if not fire(honest, hHrp, i % 2 == 1 and "down" or "up") then refused += 1 end
		h:advance(3)
	end
	eq(refused, 0, "a ride every 3 s, twenty times: none refused")
	-- down, look, up at once, again a breath later
	refused = 0
	for _ = 1, 5 do
		if not fire(honest, hHrp, "down") then refused += 1 end
		if not fire(honest, hHrp, "up") then refused += 1 end
		h:advance(E.RefillSeconds * E.Burst)
	end
	eq(refused, 0, "five double taps, one per full refill: none refused")
end

--======================================================================= 6. a rejoin starts full
do
	for i = 1, 10 do fire(spammer, sHrp, i % 2 == 1 and "down" or "up") end -- dry
	h:leave(spammer)
	h:advance(3)
	local again, aHrp = enter("Spammer", SPAMMER)
	truthy(fire(again, aHrp, "down"), "after a rejoin the first ride is served")
end

print(string.format("deepvein elevator: %d passed, %d failed", passed, failed))
assert(failed == 0, "deepvein elevator check failed")
