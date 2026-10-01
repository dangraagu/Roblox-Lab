-- +1 Jump Every Step — the real player path, end to end. Run: luau check_plus1jump_walk.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- docs/complete-game-standard.md §1: "Walk the real player path headless: spawn, first objective, one full
-- loop, earn, spend, rejoin. Green unit tests are not a working game." Plus the rules that path has to keep:
--   * the climb is credited only the honest way (§3: the board's metric must not be inflatable by a script):
--     a platform touched from far away, or teleported to faster than a jump can rise, earns nothing;
--   * a refused action says why (rebirth too early, an empty code box, a code that cannot be saved);
--   * a one-time grant happens inside one atomic write, and is refused (and rolled back) when it cannot land;
--   * every save carries the session's owner token: once another session has taken the profile, this one
--     writes nothing more.
-- The climber moves the way a player does: stands on each platform, and a jump's worth of time passes
-- before the touch (Config.Guard lets a 60-stud jump rise 60 studs in 0.78 s; 1 s per platform is honest).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")

-- a profile another live server holds (read-only for us), for section 6
store:SetAsync("u_777", { jobId = "another-server", session = "their-token", lockUntil = os.time() + 3600,
	data = { frontierTier = 3, frontierIdx = 2, jumpPower = 20, rebirths = 0, bestTier = 3, redeemed = {}, passes = {} } })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local remotes = RS:FindFirstChild("Plus1Remotes")
h.game:GetService("RunService"):setIsServer(false)

local plr = h:join("Walker", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
assert(h:tryRun("client/Hud.client"))
h:advance(0.5)
local stats = plr:FindFirstChild("leaderstats")
local tower = h.workspace:FindFirstChild("Tower")
local hud = plr.PlayerGui:FindFirstChild("Plus1Hud")
local function hudButton(name) return hud and hud:FindFirstChild(name, true) end

--======================================================================= 1. spawn

do
	local pad = tower:FindFirstChild("TempleSpawn")
	eq(plr.RespawnLocation, pad, "the player's RespawnLocation is the temple spawn")
	local p = hrp.Position
	truthy(math.abs(p.X - pad.Position.X) < 6 and math.abs(p.Z - pad.Position.Z) < 6 and p.Y > pad.Position.Y,
		string.format("a fresh climber stands on the spawn pad (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z))
	eq(stats.Jumps.Value, 0, "with 0 jump power")
	eq(stats.Tier.Value, 0, "on tier 0")
end

--======================================================================= 2. the first objective and one full loop

local function stepOn(name, wait)
	local part = tower:FindFirstChild(name)
	assert(part, "the server built " .. name)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3.5, 0))
	h:advance(wait or 1)
	part.Touched:Fire(hrp)
	return part
end
local function climb(fromTier, toTier)
	for t = fromTier, toTier do
		for i = 1, Config.Tower.TilesPerTier do stepOn("P_" .. t .. "_" .. i) end
	end
end

stepOn("P_1_1")
eq(stats.Jumps.Value, 1, "the first new tile: +1 jump power")
local h0 = hum.JumpHeight
stepOn("P_1_2")
eq(stats.Jumps.Value, 2, "the second: +1 again")
truthy(hum.JumpHeight > h0, string.format("and the jump grows (%.2f -> %.2f)", h0, hum.JumpHeight))
stepOn("P_1_2")
eq(stats.Jumps.Value, 2, "standing on an old tile again earns nothing")
climb(1, 10)
eq(stats.Tier.Value, 10, "an honest climb to tier 10")
eq(stats.Jumps.Value, 60, "60 jump power for 60 tiles")
eq(plr:GetAttribute("BestTier"), 10, "best tier 10")

--======================================================================= 3. what a script cannot do

do
	-- touching the next platform without being there (from the pad)
	hrp.CFrame = CFrame.new(Vector3.new(0, Config.Tower.BaseY + 4, 0))
	h:advance(2)
	tower:FindFirstChild("P_11_1").Touched:Fire(hrp)
	eq(stats.Jumps.Value, 60, "a platform touched from far away earns nothing")
	eq(stats.Tier.Value, 10, "and moves nothing")

	-- teleporting three tiers up in one go
	local target = tower:FindFirstChild("P_14_1")
	hrp.CFrame = CFrame.new(target.Position + Vector3.new(0, 3.5, 0))
	h:advance(5)
	target.Touched:Fire(hrp)
	eq(stats.Tier.Value, 10, "a teleport three tiers up (" .. math.floor(target.Position.Y) .. " studs) earns nothing, even after 5 s")
	eq(plr:GetAttribute("BestTier"), 10, "and the best tier (the board's metric) does not move")

	-- a bot: teleports to the platform after its last credited one, every 0.05 s, for 10 s
	local fromY = tower:FindFirstChild("P_10_6").Position.Y
	local topY = fromY
	local attempts, credits, t, i = 0, 0, 11, 1
	for _ = 1, 200 do
		local part = tower:FindFirstChild("P_" .. t .. "_" .. i)
		hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3.5, 0))
		h:advance(0.05)
		local before = stats.Jumps.Value
		part.Touched:Fire(hrp)
		attempts += 1
		if stats.Jumps.Value > before then
			credits += 1
			topY = part.Position.Y
			i += 1
			if i > Config.Tower.TilesPerTier then t += 1; i = 1 end
		end
	end
	local g = h.workspace.Gravity
	local H = Config.Jump.MaxJumpHeight
	local allowed = Config.Guard.BurstJumps * H + Config.Guard.RateFactor * math.sqrt(g * H / 2) * 10
	print(string.format("  bot, 200 teleports in 10 s: %d credited, rose %.0f studs (a %d-stud jumper: at most %.0f)",
		credits, topY - fromY, H, allowed))
	truthy(topY - fromY <= allowed, string.format(
		"a bot teleporting every 0.05 s for 10 s rises no more than a %d-stud jumper could (%.0f of %.0f studs, %d of %d tries credited)",
		H, topY - fromY, allowed, credits, attempts))
	truthy(credits < attempts, "(and most of its tries are refused: " .. (attempts - credits) .. ")")
end

-- back to honest climbing from wherever the frontier is: still credited normally
do
	local ft = stats.Tier.Value
	local before = stats.Jumps.Value
	-- find the first platform past the frontier by trying each in order, the honest way
	local credited = false
	for t = ft, ft + 1 do
		for i = 1, Config.Tower.TilesPerTier do
			if not credited then
				local b = stats.Jumps.Value
				stepOn("P_" .. t .. "_" .. i)
				if stats.Jumps.Value > b then credited = true end
			end
		end
	end
	truthy(credited and stats.Jumps.Value == before + 1, "after all that, an honest step onto the next platform is credited as usual")
end

--======================================================================= 4. spend: rebirth, and a refused one says why

do
	local reb = remotes:FindFirstChild("Rebirth")
	local btn = hudButton("RebirthButton")
	local tierBefore = stats.Tier.Value
	truthy(tierBefore >= 10, "set-up: at tier " .. tierBefore .. ", a rebirth is allowed")
	btn.Activated:Fire()
	h:advance(0.2)
	eq(stats.Rebirths.Value, 1, "REBIRTH: rebirths 1")
	eq(stats.Jumps.Value, 0, "jump power back to 0")
	eq(stats.Tier.Value, 0, "back to tier 0")
	truthy(hrp.Position.Y < Config.Tower.BaseY + 10, string.format("and back on the pad (y %.1f)", hrp.Position.Y))
	eq(plr:GetAttribute("BestTier") >= 10, true, "the best tier survives")

	reb:clearSent()
	btn.Activated:Fire()
	h:advance(0.2)
	eq(stats.Rebirths.Value, 1, "a second rebirth at tier 0 is refused")
	local sent = reb:sentTo(plr)
	local reply = sent[#sent] and sent[#sent].args[1]
	truthy(type(reply) == "table" and reply.ok == false and reply.reason == "tier",
		"the server says why (" .. (if type(reply) == "table" then tostring(reply.reason) else "no reply") .. ")")
	eq(type(reply) == "table" and reply.need, 18, "and names the tier it needs (18)")
	truthy(string.find(string.lower(btn.Text), "not yet", 1, true) ~= nil and string.find(btn.Text, "18", 1, true) ~= nil,
		"the HUD shows it on the button (" .. btn.Text .. ")")

	-- the guard starts again at the pad: a teleport from the pad to tier 5 is refused, even below the old frontier
	local t5 = tower:FindFirstChild("P_5_1")
	hrp.CFrame = CFrame.new(t5.Position + Vector3.new(0, 3.5, 0))
	h:advance(1)
	t5.Touched:Fire(hrp)
	eq(stats.Jumps.Value, 0, "after a rebirth a teleport from the pad to tier 5 earns nothing (the guard starts at the pad again)")
	-- climbing again from the pad right after the rebirth is credited
	stepOn("P_1_1")
	eq(stats.Jumps.Value, 1, "after the rebirth the first tile pays +1 again")
end

--======================================================================= 5. earn: codes, in one atomic write

do
	local box = hudButton("CodeBox")
	local go = hudButton("RedeemButton")
	box.Text = ""
	go.Activated:Fire()
	h:advance(0.1)
	truthy(string.find(string.lower(go.Text), "type a code", 1, true) ~= nil, "an empty code box says so (" .. go.Text .. ")")

	local jp = stats.Jumps.Value
	box.Text = "welcome"
	go.Activated:Fire()
	h:advance(0.1)
	eq(stats.Jumps.Value, jp + 10, "WELCOME: +10")
	local rec = store:GetAsync("u_4242")
	eq(rec and rec.data and rec.data.redeemed and rec.data.redeemed.WELCOME, true, "the code is saved as used ...")
	eq(rec and rec.data and rec.data.jumpPower, jp + 10, "... in the same write as the jump power it paid")

	-- the write fails: nothing is granted, and the code can still be used
	jp = stats.Jumps.Value
	store.__failNext = true
	box.Text = "SKYHIGH"
	go.Activated:Fire()
	h:advance(0.1)
	eq(stats.Jumps.Value, jp, "SKYHIGH while the save fails: no jump power")
	truthy(string.find(string.lower(go.Text), "save", 1, true) ~= nil, "and the HUD says the save failed (" .. go.Text .. ")")
	local redeem = remotes:FindFirstChild("Redeem")
	local res = redeem:simulateInvokeServer(plr, "SKYHIGH")
	eq(res and res.ok, true, "the save works again: SKYHIGH can be redeemed after all")
	eq(stats.Jumps.Value, jp + 25, "+25")
	eq(redeem:simulateInvokeServer(plr, "SKYHIGH").reason, "already", "and only once")
end

--======================================================================= 6. a profile another server holds: read-only, grants refused

do
	h:join("Other", 777)
	h:advance(0.5)
	local other = h.Players:FindFirstChild("Other")
	local jp = other.leaderstats.Jumps.Value
	local res = remotes:FindFirstChild("Redeem"):simulateInvokeServer(other, "TEMPLE")
	eq(res and res.reason, "nosave", "a read-only session is refused a code (it could not be saved)")
	eq(other.leaderstats.Jumps.Value, jp, "and gets nothing")
	eq(store:GetAsync("u_777").session, "their-token", "and the other server's record is untouched")
	h:leave(other)
	h.Players.LocalPlayer = plr
end

--======================================================================= 7. rejoin

do
	local jp, tier, reb = stats.Jumps.Value, stats.Tier.Value, stats.Rebirths.Value
	h:leave(plr)
	local rec = store:GetAsync("u_4242")
	eq(rec.lockUntil, 0, "leaving releases the lock")
	eq(rec.data.jumpPower, jp, "and saves the jump power")
	eq(rec.data.rebirths, reb, "the rebirths")
	eq(rec.data.frontierTier, tier, "the frontier")
	truthy(type(rec.data.bestTierAt) == "number" and math.abs(rec.data.bestTierAt - os.time()) < 600, "and when the best tier was reached")

	plr = h:join("Walker", 4242)
	char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	h:advance(0.5)
	stats = plr:FindFirstChild("leaderstats")
	eq(stats.Jumps.Value, jp, "rejoined: the jump power is back")
	eq(stats.Rebirths.Value, reb, "the rebirths too")
	eq(stats.Tier.Value, tier, "and the frontier")
	local b = stats.Jumps.Value
	stepOn("P_1_2")
	eq(stats.Jumps.Value, b + 1, "and the next tile pays, from where they stood")
end

--======================================================================= 8. the owner token: a newer session wins

do
	-- another server takes the record (this one's lock expired, say, during an outage)
	store:UpdateAsync("u_4242", function(old)
		old.jobId = "newer-server"
		old.session = "newer-token"
		old.lockUntil = os.time() + 3600
		old.data.jumpPower = 999
		return old
	end)
	stepOn("P_1_3")
	h:advance(Config.Save.AutosaveSeconds + 1)
	local rec = store:GetAsync("u_4242")
	eq(rec.session, "newer-token", "the autosave does not take the record back")
	eq(rec.data.jumpPower, 999, "and does not overwrite what the newer session wrote")
	h:leave(plr)
	rec = store:GetAsync("u_4242")
	eq(rec.lockUntil > os.time(), true, "leaving does not release the newer session's lock")
	eq(rec.data.jumpPower, 999, "nor overwrite its data")
end

print("")
local expected = { "READ%-ONLY", "tatt over" }
local unexpected = {}
for _, w in h.warnings do
	local known = false
	for _, pat in expected do if string.find(w, pat) then known = true end end
	if not known then table.insert(unexpected, w) end
end
eq(#unexpected, 0, "no other warnings (read-only load + one takeover warning expected)")
for _, w in unexpected do print("warning: " .. w) end
local takeover = 0
for _, w in h.warnings do if string.find(w, "tatt over") then takeover += 1 end end
eq(takeover, 1, "the takeover is warned about exactly once")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump walk: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump walk check failed", 0)
end
