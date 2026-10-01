-- Vault Runners — THE ENDGAME TURNS: the halls of the deepest stratum, driven through the REAL client
-- script against the real server. Run (from robloxemu): luau check_vaultrunners_halls.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Owner decision 2026-09-30 (EYECANDY.md §10): every Gold floor was the Volcano Temple, and a player
-- may live in Gold for hours. Past Config.Env.Halls.from the deepest stratum moves to its next hall
-- every Env.Halls.every depths — its own light, weather and props — and wraps round. The palette
-- (walls, floors, pads, gems) stays the stratum's own, so what the runner must read reads the same.
-- This profile runs one vault in each of the three halls:
--   Gold floor 1   = depth 56 = the Magma Hall    (the Volcano Temple as it was)
--   Silver floor 23 = depth 48 = the Obsidian Hall
--   Bronze floor 52 = depth 52 = the Ash Hall
-- and checks, per hall, on the real server's vault as the client painted it: the chip names the hall,
-- the weather and the props are the hall's, the light glides to the hall's, the pads and gems are the
-- stratum's own colours, and a title card names each new hall — with the fanfare only for a hall
-- deeper than any floor this player has cleared (Bronze 51 is their deepest).

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

local ME = 8484
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 52, [2] = 23, [3] = 1 }, escapes = 80, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local VaultEnv = mod("VaultEnv")
local EnvBands = mod("EnvBands")
local bands = Config.Env.Bands
local H = Config.Env.Halls
local RunService = h.game:GetService("RunService")
local Lighting = h.game:GetService("Lighting")
RunService:setIsServer(false)
Config.Hazards.IntervalMin = 1e6 -- no drops: this file is about the look
Config.Hazards.IntervalMax = 1e6 + 1

local plr = h:join("Deep", ME)
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
local chip = gui:FindFirstChild("BandChip", true)
local cam = h.workspace.CurrentCamera
local vaults = h.workspace:FindFirstChild("Vaults")
local EnterRemote = RS:FindFirstChild("VaultRemotes"):FindFirstChild("Enter")

local FANFARE = Color3.fromRGB(255, 244, 220)
local cards, fanfares, lastCard = {}, 0, ""
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
			if f and math.abs(f.BackgroundColor3.R - FANFARE.R) < 0.01 and math.abs(f.BackgroundColor3.G - FANFARE.G) < 0.01
				and math.abs(f.BackgroundColor3.B - FANFARE.B) < 0.01 then fanfares += 1 end
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
local function arr(c: Color3) return { c.R * 255, c.G * 255, c.B * 255 } end
local function close(a, b, tol)
	return math.abs(a[1] - b[1]) <= tol and math.abs(a[2] - b[2]) <= tol and math.abs(a[3] - b[3]) <= tol
end
local UNIQUE = { lamp = "PropBulb", brazier = "PropBowl", embers = "PropCage", panel = "PropPanel", icicles = "PropIcicle" }

run(1, 1 / 30)
truthy(chip ~= nil, "(the band chip exists)")

local volcano = bands[#bands]
local looks = {}
-- The first run of the session names the STRATUM (its card is the stratum's, the hall in the
-- subtitle); every later hall change names the hall. The first run is also the one before the
-- client has heard which floors this player has cleared (the server pushes that right after "start"),
-- so the no-fanfare case goes first.
local CASES = {
	{ tier = 2, floor = 23, hall = "obsidian", card = "🌋 VOLCANO TEMPLE", fanfare = 0 },
	{ tier = 3, floor = 1, hall = "magma", card = "🌋 MAGMA HALL", fanfare = 1 },
	{ tier = 1, floor = 52, hall = "ash", card = "🌋 ASH HALL", fanfare = 1 },
	-- back to the Obsidian Hall, now that the client knows Bronze 51 is this player's deepest: a card
	-- for the new hall, and no fanfare, because it starts at depth 48 (REVIEW-5 §4, mutation D7)
	{ tier = 2, floor = 23, hall = "obsidian", card = "🌋 OBSIDIAN HALL", fanfare = 0 },
}
for _, case in CASES do
	local depth = VaultEnv.depth(Config, case.tier, case.floor)
	local hall = VaultEnv.hall(Config, depth)
	local label = string.format("%s floor %d (depth %d)", Config.Tiers[case.tier].name, case.floor, depth)
	eq(hall and hall.id, case.hall, label .. ": (the hall this case is about)")
	if myVault() then respawn() end
	run(0.5, 1 / 30)
	local c0, f0 = #cards, fanfares
	EnterRemote:simulateFireServer(plr, case.tier)
	h:advance(0.05)
	run(6, 1 / 30) -- the light glides in (0.6 s half-life)
	local v = myVault()
	truthy(v ~= nil, label .. ": (the vault is running)")
	-- the chip names the hall
	truthy(chip and string.find(chip.Text, hall.name, 1, true) ~= nil,
		string.format("%s: the chip names the %s (%q)", label, hall.name, chip and chip.Text or "?"))
	-- the weather is the hall's
	local wantW = (hall.weather or volcano.weather).kind
	local on = {}
	for _, d in fx:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled and string.sub(d.Name, 1, 8) == "Weather_" then on[string.sub(d.Name, 9)] = true end
	end
	truthy(on[wantW] == true, string.format("%s: the %s's weather (%s) is falling", label, hall.name, wantW))
	local others = 0
	for k in on do if k ~= wantW then others += 1 end end
	eq(others, 0, label .. ": and no other weather")
	-- the props are the hall's
	local wantP = (hall.props or volcano.props).kind
	local names = {}
	for _, d in fx:GetChildren() do names[d.Name] = true end
	truthy(names[UNIQUE[wantP]] == true, string.format("%s: the %s's props (%s) hang from the ceilings", label, hall.name, wantP))
	for kind, n in UNIQUE do
		if kind ~= wantP then truthy(names[n] ~= true, string.format("%s: and not the %s", label, kind)) end
	end
	-- the light is the hall's (Ambient is the stratum's, overlaid by the hall's)
	local amb = arr(Lighting.Ambient)
	local wantA = (hall.overlay and hall.overlay.lighting and hall.overlay.lighting.Ambient) or volcano.lighting.Ambient
	truthy(close(amb, wantA, 3), string.format("%s: the light glides to the %s's (Ambient {%d, %d, %d}, want {%d, %d, %d})",
		label, hall.name, math.round(amb[1]), math.round(amb[2]), math.round(amb[3]), wantA[1], wantA[2], wantA[3]))
	looks[case.hall] = amb
	-- ...and what the runner reads is the stratum's own, in every hall
	local pad = v:FindFirstChild("Step_0_1")
	truthy(pad and close(arr(pad.Color), volcano.palette.pad, 1.5), string.format("%s: the pads are the %s's own colour", label, volcano.name))
	local floorPart = v:FindFirstChild("Floor_0")
	truthy(floorPart and close(arr(floorPart.Color), volcano.palette.floor, 1.5), label .. ": and so is the floor")
	-- a card per hall; the fanfare only for a hall deeper than ever cleared
	eq(#cards - c0, 1, label .. ": one title card")
	eq(cards[#cards], case.card, label .. ": the card")
	eq(fanfares - f0, case.fanfare, label .. ": fanfare only for a hall deeper than any floor this player has cleared")
end
truthy(not close(looks.magma, looks.obsidian, 10) and not close(looks.obsidian, looks.ash, 10) and not close(looks.magma, looks.ash, 10),
	"the three halls are three different lights")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. tostring(e))
end
local warns = 0
for _, w in h.warnings do
	if string.find(w, "[VaultFx]", 1, true) then warns += 1; print("  warning: " .. w) end
end
eq(warns, 0, "the client never warned")
print(string.format("  cards: %s; fanfares: %d", table.concat(cards, " | "), fanfares))
print(string.format("vault-runners halls: %d passed, %d failed", passed, failed))
