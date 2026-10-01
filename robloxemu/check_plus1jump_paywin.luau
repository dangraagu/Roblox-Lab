-- +1 Jump Every Step — no Robux cost in v1, nothing pay-to-win. Run: luau check_plus1jump_paywin.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- docs/complete-game-standard.md §3: "Promo codes, if any, are public by design. Never a Robux cost in v1, and never
-- gambling or pay-to-win." Until 2026-10-01 `Config.Passes` listed a stubbed `DoubleJump` pass ("2x jump power per
-- tile") and an `AutoWalk` pass, and the server paid +2 per tile to any profile whose saved `passes` said DoubleJump.
-- Nothing sold them yet (`Enabled = false`, no purchase code), but CLAUDE.md's next step was to fill in real ids
-- and switch them on. This pins the standard: passes are off in v1, the only pass the config knows is cosmetic,
-- and a save that claims any pass earns exactly what everyone earns (+1 per new tile, the same jump).
-- The climber stands on each platform and lets a jump's time pass before the touch (the climb guard's honest way).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")

-- a save that claims every pass the old config listed (as a purchase flow, or a hand-edited record, would write)
store:SetAsync("u_5151", { data = { frontierTier = 0, frontierIdx = 0, jumpPower = 0, rebirths = 0, bestTier = 0,
	redeemed = {}, passes = { DoubleJump = true, AutoWalk = true, SkyTrails = true } } })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Progression = h:_require(RS:FindFirstChild("Progression"))
h.game:GetService("RunService"):setIsServer(false)

--======================================================================= 1. the config

eq(Config.Passes.Enabled, false, "gamepasses are off in v1 (no Robux cost)")
local COSMETIC = { SkyTrails = true } -- a pass may only change how a player looks, never how they climb
local other = {}
for k in Config.Passes do
	if k ~= "Enabled" and not COSMETIC[k] then table.insert(other, tostring(k)) end
end
table.sort(other)
eq(table.concat(other, ", "), "", "every pass in Config.Passes is cosmetic (non-cosmetic passes listed)")

--======================================================================= 2. a save that claims passes earns what everyone earns

local plr = h:join("Payer", 5151)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
h:advance(0.5)
local stats = plr:FindFirstChild("leaderstats")
local tower = h.workspace:FindFirstChild("Tower")

local function stepOn(name)
	local part = tower:FindFirstChild(name)
	assert(part, "the server built " .. name)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3.5, 0))
	h:advance(1)
	part.Touched:Fire(hrp)
end

stepOn("P_1_1")
eq(stats.Jumps.Value, 1, "the first new tile pays +1, pass or no pass")
for i = 2, Config.Tower.TilesPerTier do stepOn("P_1_" .. i) end
eq(stats.Jumps.Value, Config.Tower.TilesPerTier, "a whole tier pays +1 per tile")
eq(stats.Tier.Value, 1, "(and the climb itself was credited: tier 1)")
local want = Progression.jumpHeight(Config.Tower.TilesPerTier, 1, Config.Jump)
eq(math.abs(hum.JumpHeight - want) < 1e-6, true,
	string.format("the jump is a passless player's (%.2f, want %.2f)", hum.JumpHeight, want))

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump paywin: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump paywin check failed", 0)
end
