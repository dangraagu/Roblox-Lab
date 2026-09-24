-- Vault Runners — title cards for a RETURNING player, and the two guards shipped numbers never trip.
-- Run (from robloxemu): luau check_vaultrunners_cards.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Written in the resume session because the mutation sweep (EYECANDY.md §7) found three promises no
-- check held:
--   §1  the fanfare (white flash + FOV punch) plays only the first time a player goes DEEPER than the
--       deepest floor they have cleared. check_vaultrunners_env only ever plays a fresh profile, for
--       which every new card is also a new depth, so "fanfare on every card" passed it. Here the saved
--       profile has already cleared Bronze floor 29 (the Frozen Vault): its first Frozen card must be
--       quiet, its first Volcano card must celebrate;
--   §2  the weather cap (EnvBands.capRates, Config.Budget.MaxWeatherRate) is applied by the glue. The
--       shipped bands never ask for more than the cap, so it is forced here IN MEMORY;
--   §3  a pad whose stratum colour cannot be read on its floor falls back to black or white
--       (VaultEnv.readablePad, Config.Env.MinPadContrast). The shipped palettes never need the
--       fallback, so an unreadable palette is forced here IN MEMORY, and the pad actually painted on
--       the server's part is measured against the floor actually painted.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 6262
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
-- Bronze floor 30 next = Bronze 29 cleared = depth 29, the Frozen Vault. Silver and Gold on floor 1.
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 30, [2] = 1, [3] = 1 }, escapes = 29, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local VaultEnv = mod("VaultEnv")
local EnvBands = mod("EnvBands")
local bands = Config.Env.Bands
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
Config.Hazards.IntervalMin = 1e6 -- no drops: this file is about cards and colours
Config.Hazards.IntervalMax = 1e6 + 1

local plr = h:join("Returner", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic

assert(h:tryRun("client/Hud.client"))
local okVault, errVault = h:tryRun("client/Vault.client")
truthy(okVault, "Vault.client loads (" .. tostring(errVault) .. ")")
local fx = h.workspace:FindFirstChild("VaultRunnersFx")
local gui = plr.PlayerGui:FindFirstChild("VaultFx")
local card = gui.Root:FindFirstChild("BandCard")
local cam = h.workspace.CurrentCamera
local vaults = h.workspace:FindFirstChild("Vaults")
local EnterRemote = RS:FindFirstChild("VaultRemotes"):FindFirstChild("Enter")

local function sameColor(a, b, tol)
	tol = tol or 1.5 / 255
	return a ~= nil and b ~= nil and math.abs(a.R - b.R) <= tol and math.abs(a.G - b.G) <= tol and math.abs(a.B - b.B) <= tol
end
local FANFARE = Color3.fromRGB(255, 244, 220) -- Vault.client's celebration flash; the HUD's flashes are other colours
local cards, fanfares = {}, 0
local lastCard = ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			local f = g:FindFirstChildOfClass("Frame")
			if f and sameColor(f.BackgroundColor3, FANFARE) then fanfares += 1 end
		end
	end
end
local function run(seconds, dt)
	for _ = 1, math.floor(seconds / dt + 0.5) do frame(dt) end
end
local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function respawn()
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.1)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
end
local function enter(tier)
	if myVault() then respawn() end
	run(0.5, 1 / 30)
	EnterRemote:simulateFireServer(plr, tier)
	h:advance(0.05)
	run(3, 1 / 30)
	return myVault()
end

run(1, 1 / 30)

--============================================================================ §1 a returning player's cards

do
	local cleared = VaultEnv.deepestCleared(Config, { 30, 1, 1 })
	eq(bands[EnvBands.indexAt(bands, cleared)].id, "frozen", "§1 (the saved profile has cleared the Frozen Vault: depth " .. cleared .. ")")
	local c0, f0 = #cards, fanfares
	truthy(enter(2) ~= nil, "§1 (Silver floor 1 is running)")
	eq(cards[#cards], "❄️ FROZEN VAULT", "§1 the first run of the session names its stratum")
	eq(#cards - c0, 1, "§1 (one card)")
	eq(fanfares - f0, 0, "§1 but no fanfare: this player has run deeper than Silver floor 1 before")
	local c1, f1 = #cards, fanfares
	truthy(enter(3) ~= nil, "§1 (Gold floor 1 is running)")
	eq(cards[#cards], "🌋 VOLCANO TEMPLE", "§1 Gold floor 1 is the Volcano Temple")
	eq(#cards - c1, 1, "§1 (one card)")
	eq(fanfares - f1, 1, "§1 and the fanfare: deeper than this player has ever cleared")
	local c2, f2 = #cards, fanfares
	truthy(enter(1) ~= nil, "§1 (Bronze floor 30 is running)")
	eq(cards[#cards], "❄️ FROZEN VAULT", "§1 back in the Frozen Vault: its card again (the stratum changed)")
	eq(#cards - c2, 1, "§1 (one card)")
	eq(fanfares - f2, 0, "§1 and no fanfare: not deeper than before")
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §2 the weather cap is applied by the glue

do
	local frozen = bands[EnvBands.indexOf(bands, "frozen")]
	local shipped = frozen.weather.rate
	frozen.weather.rate = 200 -- far over any budget; the glue must cap it
	truthy(enter(1) ~= nil, "§2 (Bronze floor 30, the Frozen Vault, with its snow forced to 200/s in memory)")
	local total, n = 0, 0
	for _, d in fx:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled and string.sub(d.Name, 1, 8) == "Weather_" then
			total += d.Rate
			n += 1
		end
	end
	truthy(n >= 1, "§2 (the snow is falling)")
	truthy(total <= Config.Budget.MaxWeatherRate + 1e-6,
		string.format("§2 the weather is capped at the budget however much a band asks for (%.1f/s, cap %d)", total, Config.Budget.MaxWeatherRate))
	frozen.weather.rate = shipped
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §3 an unreadable pad falls back to black or white

do
	local frozen = bands[EnvBands.indexOf(bands, "frozen")]
	local shippedPad = frozen.palette.pad
	frozen.palette.pad = { 232, 240, 246 } -- snow on snow: about 1.05:1 on the frozen floor
	local v = enter(1)
	truthy(v ~= nil, "§3 (Bronze floor 30 with the frozen pads forced to the floor's own white, in memory)")
	local pad, floorPart = v:FindFirstChild("Step_0_1"), v:FindFirstChild("Floor_0")
	local function c(p) return { p.Color.R * 255, p.Color.G * 255, p.Color.B * 255 } end
	local k = VaultEnv.contrast(c(pad), c(floorPart))
	-- written out, not read from Config: a rule checked against its own number is not a check
	truthy(k >= 3, string.format("§3 the pad actually painted still reads against the floor actually painted (%.1f:1, want >= 3)", k))
	frozen.palette.pad = shippedPad
	respawn()
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. tostring(e))
end
local warns = 0
for _, w in h.warnings do
	if string.find(w, "[VaultFx]", 1, true) then warns += 1; print("  warning: " .. w) end
end
eq(warns, 0, "the client never warned")
print(string.format("  cards seen: %s; fanfares: %d", table.concat(cards, " | "), fanfares))
print(string.format("vault-runners cards: %d passed, %d failed", passed, failed))
