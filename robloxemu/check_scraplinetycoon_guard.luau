-- Scrapline Tycoon — the server's guards against claims a client can make (REVIEW-2 X2, X3).
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_guard.luau 2>&1
--
--   1. A root position that is not a finite number (x = +inf, z = -inf, NaN, y = +inf) for one tick must not poison
--      the server's TRUSTED position (Trace.luau): with inf/inf = NaN it used to stay NaN for the rest of the life,
--      and the Fix range check `dist > FixRange` is false for NaN, so Fix worked from anywhere. Probed on Plot_2,
--      whose axis turns an infinite claim into an infinite local x (Plot_1's turns it into NaN at once).
--   2. A Recycle against a failing store is held for Config.Recycle.RetrySeconds after a failed write: one client
--      firing Recycle at the remote limit used to make about 7 profile writes a second, against a write budget of
--      60 + 10 x players a minute that every autosave on the server shares. Every held call still gets a toast.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
local IDS = { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" }
local function prof(shL, L, jamIn)
	local st = {}
	for i, id in IDS do st[id] = { n = 2, L = if i == 1 then shL else L, j = 0 } end
	return { v = 1, cash = 5e9, stations = st, jamIn = jamIn, tier = 6, bolts = 0, boltsAt = 0, tutorial = 4 }
end
local PROBES = { 501, 502, 503, 504, 505 }
for _, uid in PROBES do store:SetAsync("u_" .. uid, { data = prof(5, 5, 2) }) end
store:SetAsync("u_602", { data = prof(31, 40, 200) }) -- a line fast enough to recycle (twinned Shredder L31: 1615.5 rockets/s)

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local remotes = h.ReplicatedStorage:FindFirstChild("ScraplineRemotes")
local State, Toast, Fix, Recycle = remotes.State, remotes.Toast, remotes.Fix, remotes.Recycle
local function stateOf(plr) local s = State:sentTo(plr); return s[#s] and s[#s].args[1] end
local function lastToast(plr) local t = Toast:sentTo(plr); return t[#t] and tostring(t[#t].args[1]) or "" end
local info = h.game:GetService("ServerStorage").PlotInfo

--============================================================================ 1. a non-finite root claim (REVIEW-2 X2)
local filler = h:join("Filler", 777)
h.Players:simulateSpawn(filler, h.workspace)
h:advance(1)
eq(filler.RespawnLocation.Parent.Name, "Plot_1", "set-up: a filler takes Plot_1, so every probe below plays on Plot_2")

local function probe(uid, label, bad)
	local plr = h:join("P" .. uid, uid)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local pad = plr.RespawnLocation
	local sp
	for _ = 1, 100 do
		h:advance(0.5)
		local st = stateOf(plr)
		if st and st.sputter then sp = st.sputter break end
	end
	truthy(sp ~= nil, label .. ": set-up: a machine sputters")
	if sp == nil then return end
	if bad then
		hrp.CFrame = CFrame.new(bad) -- one tick at a position that is not a number, then straight back onto the pad
		h:advance(0.15)
	end
	hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, 3, 0))
	h:advance(0.25)
	local tx = info[tostring(uid)]:GetAttribute("TrustedX")
	local tz = info[tostring(uid)]:GetAttribute("TrustedZ")
	local n0 = #Toast:sentTo(plr)
	Fix:simulateFireServer(plr, IDS[sp.t], if sp.m == 1 then "a" else "b")
	h:advance(0.1)
	local toast = lastToast(plr)
	print(string.format("  %-26s on %s: trusted (%s, %s); Fix from the pad: %q", label, pad.Parent.Name, tostring(tx), tostring(tz), toast))
	eq(pad.Parent.Name, "Plot_2", label .. ": set-up: on Plot_2")
	truthy(finite(tx) and finite(tz), label .. ": the trusted position stays a finite number")
	truthy(#Toast:sentTo(plr) > n0 and string.find(toast, "Get closer", 1, true) ~= nil, label .. ": a Fix from the arrival pad is refused: " .. toast)
	eq(stateOf(plr).sputter ~= nil, true, label .. ": ...and the machine still sputters")
	h:leave(plr)
	h:advance(1)
end
probe(501, "control (no bad position)", nil)
probe(502, "root at x = +inf", Vector3.new(math.huge, 3, 0))
probe(503, "root at z = -inf", Vector3.new(0, 3, -math.huge))
probe(504, "root at NaN", Vector3.new(0 / 0, 3, 0 / 0))
probe(505, "root at y = +inf", Vector3.new(0, math.huge, 0))
h:leave(filler)
h:advance(1)

--============================================================================ 2. Recycle spam against a failing store (REVIEW-2 X3)
do
	local p = h:join("Spam", 602)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(2)
	local st = stateOf(p)
	truthy(st and st.recycleReady and st.saving, "set-up: a saving line that is ready to recycle")
	h:advance(10) -- let any flush settle
	local calls0 = store.__calls
	local toasts0 = #Toast:sentTo(p)
	store.__failAll = true
	local fired = 0
	for _ = 1, 10 * 10 do -- 10 s at 10 calls a second (the remote allows 8)
		Recycle:simulateFireServer(p)
		fired += 1
		h:advance(0.1)
	end
	local spam = store.__calls - calls0
	local toasts = #Toast:sentTo(p) - toasts0
	store.__failAll = false
	print(string.format("  2. store failing: %d Recycle calls in 10 s cost %d profile-store calls and drew %d toasts", fired, spam, toasts))
	truthy(spam <= 2, string.format("a failed recycle write is not retried at the remote's rate: %d store calls in 10 s (at most 2)", spam))
	truthy(toasts >= 80, string.format("...and every call the remote let through is answered with a toast (%d of the 80 allowed)", toasts))
	local held = lastToast(p)
	truthy(string.find(held, "try again", 1, true) ~= nil, "a held recycle says when to try again: " .. held)
	eq(stateOf(p).bolts, 0, "nothing was granted while the store failed")
	-- the store is back: once the hold is over, the recycle lands
	h:advance(Config.Recycle.RetrySeconds + 1)
	Recycle:simulateFireServer(p)
	h:advance(2)
	eq(stateOf(p).bolts, 1, "after the store recovers and the hold ends, one Recycle lands its Gold Bolt")
	eq(store:GetAsync("u_602").data.bolts, 1, "...in the record")
	h:leave(p)
	h:advance(2)
end

print("")
local stray = {}
for _, w in h.warnings do
	if not string.find(w, "injected DataStore failure", 1, true) then table.insert(stray, w) end
end
eq(#stray, 0, "no other warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("scraplinetycoon guard: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon guard check failed", 0) end
