-- Grow a Crystal — a refused player action says why (review round 2, finding 6; standard §1 "no silent no-ops").
-- Run: luau check_growacrystal_refused.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- A reviewer's probe found six refusals that sent the player nothing at all: clicking a crystal that is still
-- growing, Buy Chamber, the Luck booster and a locked seed with 5 dust, and Crack Geode with 5 dust. Only planting
-- with no seed and no dust said anything, and it said "not enough Gem Dust" even when the real reason was that
-- the seed is locked. That is the class of defect behind the first player report ("i cant even place a seed").
--
-- Every refusal below, through the real server, must send the player a toast that names the reason (and the
-- price, where money is the reason), and must change nothing. The HUD must answer an empty code too.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
local function profile(uid, d)
	local data = { dust = 5, seeds = {}, chambers = 1, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} }
	for k, v in d do data[k] = v end
	store:SetAsync("u_" .. uid, { data = data })
end
profile(5150, { dust = 5, seeds = { [1] = 1 } })
assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Geode = h:_require(RS:FindFirstChild("Geode"))
local R = RS:FindFirstChild("CrystalRemotes")
local State, Toast = R:FindFirstChild("State"), R:FindFirstChild("Toast")

local function lastState(plr)
	local s = State:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
-- one refused action: a toast that contains every `want` (case-insensitive), and nothing else changed
local function refused(plr, label, fn, want: { string })
	local t0 = #Toast:sentTo(plr)
	local s = lastState(plr)
	local dust0, ch0, luck0 = s.dust, s.chambers, s.luckLevel
	fn()
	h:advance(0.5)
	local toasts = Toast:sentTo(plr)
	local got = toasts[#toasts]
	local text = if #toasts > t0 and got then tostring(got.args[1]) else nil
	truthy(text ~= nil, label .. ": the player is told why")
	if text then
		for _, w in want do
			truthy(string.find(string.lower(text), string.lower(w), 1, true) ~= nil,
				string.format("%s: the message names %q (%q)", label, w, text))
		end
	end
	local s2 = lastState(plr)
	eq(s2.dust, dust0, label .. ": no dust spent")
	eq(s2.chambers, ch0, label .. ": no chamber bought")
	eq(s2.luckLevel, luck0, label .. ": no booster bought")
	return text
end

-- ── a player with 5 dust and one free Shard ─────────────────────────────────
local plr = h:join("Refused", 5150)
h:advance(1)
local function socket(uid, id) return h.workspace:FindFirstChild("Socket_" .. uid .. "_" .. id, true) end
local sock1 = socket(5150, 1)
sock1:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr) -- plants the free Shard
h:advance(0.5)
local crystal = sock1:FindFirstChild("Crystal")
truthy(crystal ~= nil, "the free Shard is planted on socket 1")
local grow = Config.Growth.SecondsPerStage[1] * Config.Growth.StageCount
refused(plr, "clicking a crystal that is still growing", function()
	crystal:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
end, { "growing", tostring(grow) .. "s" })
refused(plr, "Buy Chamber with 5 dust", function() R:FindFirstChild("Buy"):simulateFireServer(plr, "chamber") end,
	{ "gem dust", tostring(Config.Economy.ChamberBaseCost) })
refused(plr, "the Luck booster with 5 dust", function() R:FindFirstChild("Buy"):simulateFireServer(plr, "booster", "Luck") end,
	{ "luck", tostring(Config.Boosters.Luck.BaseCost) })
refused(plr, "the Growth booster with 5 dust", function() R:FindFirstChild("Buy"):simulateFireServer(plr, "booster", "Growth") end,
	{ "growth", tostring(Config.Boosters.Growth.BaseCost) })
refused(plr, "buying a Legendary seed at chamber 1", function() R:FindFirstChild("Buy"):simulateFireServer(plr, "seed", 5) end,
	{ "legendary", "chamber " .. Config.Economy.SeedShopUnlockedByChamber[5] })
refused(plr, "buying a Quartz seed with 5 dust", function() R:FindFirstChild("Buy"):simulateFireServer(plr, "seed", 2) end,
	{ "quartz", tostring(Config.Economy.SeedCost[2]) })
refused(plr, "Crack Geode with 5 dust", function() R:FindFirstChild("Geode"):simulateFireServer(plr) end,
	{ tostring(Config.Geode.CostDust) })
refused(plr, "planting on socket 2 with no seed and 5 dust", function()
	socket(5150, 2):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
end, { "gem dust", tostring(Config.Economy.SeedCost[1]) })
-- the selected seed is locked: the reason is the lock, not the money
R:FindFirstChild("Select"):simulateFireServer(plr, 5)
h:advance(0.2)
refused(plr, "planting a selected Legendary seed at chamber 1", function()
	socket(5150, 3):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
end, { "legendary", "chamber " .. Config.Economy.SeedShopUnlockedByChamber[5] })

-- ── a player at the top: every chamber, max luck, this week's geode already cracked ──
local week = Geode.weekIndex(os.time(), Config.Geode)
profile(6161, { dust = 999999, chambers = Config.Economy.MaxChambers, luckLevel = Config.Boosters.Luck.MaxLevel,
	growthLevel = Config.Boosters.Growth.MaxLevel, lastGeodeWeek = week })
local top = h:join("AtTheTop", 6161)
h:advance(1)
refused(top, "Buy Chamber with every chamber open", function() R:FindFirstChild("Buy"):simulateFireServer(top, "chamber") end,
	{ "every chamber" })
refused(top, "Luck at its max level", function() R:FindFirstChild("Buy"):simulateFireServer(top, "booster", "Luck") end,
	{ "luck", "max" })
refused(top, "Growth at its max level", function() R:FindFirstChild("Buy"):simulateFireServer(top, "booster", "Growth") end,
	{ "growth", "max" })
refused(top, "Crack Geode twice in one week", function() R:FindFirstChild("Geode"):simulateFireServer(top) end,
	{ "next week" })

-- ── the geode cannot be saved: rolled back, and the player is told ───────────
profile(7272, { dust = 5000 })
local unlucky = h:join("NoSave", 7272)
h:advance(1)
local seeds0 = 0
for _, n in lastState(unlucky).seeds do seeds0 += n end
refused(unlucky, "Crack Geode when the save fails", function()
	store.__failAll = true
	R:FindFirstChild("Geode"):simulateFireServer(unlucky)
	store.__failAll = false
end, { "try again" })
local seeds1 = 0
for _, n in lastState(unlucky).seeds do seeds1 += n end
eq(seeds1, seeds0, "the geode's seed was rolled back with the dust")

-- ── a dead end is not a refusal (owner decision 2026-09-30, EYECANDY.md §11) ─────────────────────────────
-- Nothing growing, no seed of any tier and less dust than a Shard: every click used to say "not enough Gem Dust",
-- forever. Now the click plants a free Shard and says so; with a crystal growing, the next click is refused.
profile(8383, { dust = 3, seeds = {}, plants = {} })
local broke = h:join("Broke", 8383)
h:advance(1)
local bt0 = #Toast:sentTo(broke)
socket(8383, 1):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(broke)
h:advance(0.5)
local free = socket(8383, 1):FindFirstChild("Crystal")
truthy(free ~= nil, "a player at a dead end who clicks a socket gets a crystal growing there")
local bt = Toast:sentTo(broke)
local freeMsg = if #bt > bt0 then tostring(bt[#bt].args[1]) else ""
truthy(string.find(string.lower(freeMsg), "free", 1, true) ~= nil, string.format("... and is told it was a free Shard (%q)", freeMsg))
local bs = lastState(broke)
eq(bs.dust, 3, "the free Shard costs nothing")
eq(bs.plants["1"] and bs.plants["1"].tier, 1, "it is a Shard")
refused(broke, "a second click while the free Shard grows", function()
	socket(8383, 2):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(broke)
end, { "gem dust", tostring(Config.Economy.SeedCost[1]) })
eq(socket(8383, 2):FindFirstChild("Crystal"), nil, "no second free seed while one grows")

-- ── someone else's socket or crystal (2026-09-30, pass 2): the click was ignored without a word ─────────────
-- Caverns are sealed, so this should never be reachable; if it ever is (a teleport, a shared camera), the player
-- is told why instead of clicking at nothing.
do
	local planted = socket(8383, 1):FindFirstChild("Crystal")
	for label, part in { ["another player's empty socket"] = socket(8383, 3), ["another player's crystal"] = planted } do
		local t0 = #Toast:sentTo(plr)
		local cd = part and part:FindFirstChildOfClass("ClickDetector")
		if cd then cd.MouseClick:Fire(plr) end
		h:advance(0.3)
		local ts = Toast:sentTo(plr)
		local msg = if #ts > t0 then tostring(ts[#ts].args[1]) else nil
		truthy(msg ~= nil and string.find(string.lower(msg), "cavern", 1, true) ~= nil,
			string.format("clicking %s says whose it is (%s)", label, tostring(msg)))
	end
	eq(socket(8383, 3):FindFirstChild("Crystal"), nil, "and plants nothing there")
	truthy(socket(8383, 1):FindFirstChild("Crystal") ~= nil, "nor harvests the owner's crystal")
end

-- ── the HUD: Redeem with an empty box ───────────────────────────────────────
h.game:GetService("RunService"):setIsServer(false)
h.Players.LocalPlayer = plr -- the harness makes the LAST player to join the local one
assert(h:tryRun("client/Hud.client"))
local rec = State:sentTo(plr)[#State:sentTo(plr)]
State.OnClientEvent:Fire(table.unpack(rec.args, 1, rec.args.n))
h:advance(0.2)
local hudRoot = plr.PlayerGui.CrystalHud.Root
local codeBtn, codeBox
for _, d in hudRoot:GetDescendants() do
	if d.ClassName == "TextButton" and d.Text == "Redeem" then codeBtn = d end
	if d.ClassName == "TextBox" then codeBox = d end
end
truthy(codeBtn ~= nil and codeBox ~= nil, "the HUD has a code box and a Redeem button")
if codeBtn and codeBox then
	codeBox.Text = ""
	codeBtn.Activated:Fire()
	h:advance(0.1)
	local shown = codeBtn.Text
	local result = codeBtn.Parent:FindFirstChild("CodeResult")
	if result and result.Visible then shown = result.Text end
	truthy(string.find(string.lower(shown), "type a code", 1, true) ~= nil,
		string.format("Redeem with an empty box says what to do (%q)", shown))
	h:advance(2.5)
	eq(codeBtn.Text, "Redeem", "and the button reads Redeem again afterwards")
end

-- ── the session lost its record to another server (check_growacrystal_lock has the rest) ─────────────────
profile(9494, {})
local moved = h:join("Moved", 9494)
h:advance(1)
local mt0 = #Toast:sentTo(moved)
store:SetAsync("u_9494", { jobId = "SERVER-B", session = "SERVER-B-SESSION", lockUntil = os.time() + 45, data = { dust = 1 } })
h:advance(Config.Save.AutosaveSeconds + 1)
truthy(#Toast:sentTo(moved) > mt0, "a session whose record another server took is told it no longer saves")

-- ── every message above is readable on every screen ─────────────────────────────────────────────────────
-- The toast line is one TextScaled label, so a long reason comes out small. Estimated like
-- check_growacrystal_redeem (one line at ~0.6 em per glyph, capped by the label's height and its
-- UITextSizeConstraint): at least 12 screen px at every viewport hudcheck uses.
do
	local HudCheck = require("./emu/hudcheck")
	local msgs, seen = {}, {}
	for _, who in { plr, top, unlucky, broke, moved } do
		for _, rec2 in Toast:sentTo(who) do
			local m = tostring(rec2.args[1])
			if not seen[m] then seen[m] = true; table.insert(msgs, m) end
		end
	end
	truthy(#msgs >= 15, string.format("%d different messages collected", #msgs))
	for _, m in msgs do print("    toast: " .. m) end
	local worst, worstAt = math.huge, ""
	for _, v in HudCheck.VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		for _, m in msgs do
			Toast.OnClientEvent:Fire(m)
			h:advance(0.05)
			for _, g in plr.PlayerGui:GetChildren() do h:settleLayouts(g, v.w, v.h) end
			local shown = nil
			for _, r in h:guiRects(plr.PlayerGui.CrystalHud, v.w, v.h) do
				if r.shown and r.class == "TextLabel" and r.obj.Text == m then shown = r end
			end
			if shown then
				-- emu's guiRects applies a UISizeConstraint only to auto-sized heights; Roblox caps the width too
				local sw = shown.sw
				local sc = shown.obj:FindFirstChildOfClass("UISizeConstraint")
				if sc and sc.MaxSize.X < math.huge then sw = math.min(sw, sc.MaxSize.X * shown.scale) end
				local px = math.min(shown.sh, sw / (0.6 * utf8.len(m)))
				local cc = shown.obj:FindFirstChildOfClass("UITextSizeConstraint")
				if cc then px = math.min(px, cc.MaxTextSize * shown.scale) end
				if px < worst then worst, worstAt = px, string.format("%s %dx%d: %q", v.name, v.w, v.h, m) end
			else
				worst, worstAt = -1, v.name .. ": not on screen: " .. m
			end
		end
	end
	truthy(worst >= 12, string.format("every refusal reads at 12 px or more on every screen (smallest %.1f px, %s)", worst, worstAt))
	print(string.format("  smallest refusal text: %.1f px (%s)", worst, worstAt))
end

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal refused: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal refused check failed", 0) end
