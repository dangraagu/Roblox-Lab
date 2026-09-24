-- Grow a Crystal — the join push must reach EVERY client script: this time the HUD connects first.
-- Run: luau check_growacrystal_queue_hudfirst.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The other order of check_growacrystal_queue.luau (read its header for Roblox's queue rule and how this
-- file models it). With the HUD first, the cavern script is the one that would have missed the push. It
-- used to fall back on counting its sockets, which is why nothing looked wrong; here sockets 13..48 never
-- replicate (only chambers 1 and 2 are in the world), so the cavern can only reach the Heart of the Geode
-- if the pushed profile reached it too.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})
local ME = 4343
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("u_" .. ME, {
	data = {
		dust = 77777, seeds = { [1] = 5 }, chambers = 8, luckLevel = 1, growthLevel = 0,
		plants = {}, codex = { [1] = true, [2] = true }, redeemed = {}, lastGeodeWeek = -1,
		totalDust = 90000, passes = {},
	},
})

local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local bands = Config.Env.Bands
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Returner", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

-- only chambers 1 and 2 ever replicate: the sockets alone would say "2 chambers"
local plotFolder = h.workspace:FindFirstChild("Socket_" .. ME .. "_1", true).Parent
local withheld = 0
for id = 13, 48 do
	local sk = plotFolder:FindFirstChild("Socket_" .. ME .. "_" .. id)
	if sk then
		sk.Parent = nil
		withheld += 1
	end
end
eq(withheld, 36, "36 sockets never replicate")

local remotes = RS:FindFirstChild("CrystalRemotes")
local State = remotes:FindFirstChild("State")
local queued = table.clone(State:sentTo(plr))
truthy(#queued >= 1, "the server pushed the profile before any client script ran")
local join = queued[#queued].args[1]
eq(join.chambers, 8, "the join push says 8 chambers")

local sig = State.OnClientEvent
local realConnect = sig.Connect
local flushedTo = 0
sig.Connect = function(self, fn)
	local conn = realConnect(self, fn)
	if queued ~= nil then
		local q = queued
		queued = nil
		flushedTo += 1
		task.defer(function()
			for _, rec in q do
				fn(table.unpack(rec.args, 1, rec.args.n))
			end
		end)
	end
	return conn
end

-- the HUD starts first, and the queue is flushed before the cavern script even starts
local okH, errH = h:tryRun("client/Hud.client")
truthy(okH, "Hud.client loads (" .. tostring(errH) .. ")")
h:advance(0.1)
local okG, errG = h:tryRun("client/Grotto.client")
truthy(okG, "Grotto.client loads (" .. tostring(errG) .. ")")
eq(flushedTo, 1, "the queue was handed to exactly one connection (the first)")
eq(sig:GetConnectionCount(), 1, "State has exactly ONE client connection, shared by the HUD and the cavern")

local RunService = h.game:GetService("RunService")
for _ = 1, 30 * 14 do
	RunService.RenderStepped:Fire(1 / 30)
	h:advance(1 / 30)
end

local texts = {}
for _, d in plr.PlayerGui.CrystalHud:GetDescendants() do
	if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then texts[d.Text] = true end
end
truthy(texts["💎 77777"] == true, "the HUD shows the saved dust")
truthy(texts[Config.Tiers[1] .. " (5)"] == true, "and the saved seed count")

local chip = plr.PlayerGui.CrystalGrotto.Root.BandChip
truthy(string.find(chip.Text, bands[#bands].name, 1, true) ~= nil,
	"the cavern, started after the push was flushed to the HUD, still names the Heart of the Geode (" .. chip.Text .. ")")
local target = EnvBands.sample(bands, 8, "lighting")
near(h.Lighting.Brightness, target.Brightness, 0.02, "and glided to its look, although only 2 chambers of sockets are in the world")
near(h.Lighting.FogEnd, target.FogEnd, 0.5, "(fog too)")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("  warning: " .. w) end
print(string.format("growacrystal queue (HUD first): %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal queue (HUD first) check failed", 0) end
