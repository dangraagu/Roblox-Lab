-- Hud.client.luau — HUD for "Anomaly: Night Shift at the Observatory".
-- The ADVANCE / TURN BACK / USE HINT actions are in-world ProximityPrompts (keys E / Q / H),
-- so this is display + the code-redeem box + the tint picker only. All state is pushed by
-- the server via the State remote; the client trusts nothing it computes itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
-- Shared data lives in ReplicatedStorage and is required the ROBLOX way — with an Instance.
-- Never `require("./Config")`: a path string resolves in the luau CLI but is invalid in
-- Roblox and makes the whole LocalScript fail to load.
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("AnomalyRemotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local RevealRemote = Remotes:WaitForChild("Reveal") :: RemoteEvent
local DeathRemote = Remotes:WaitForChild("Death") :: RemoteEvent
local RedeemRemote = Remotes:WaitForChild("Redeem") :: RemoteEvent
local TintRemote = Remotes:WaitForChild("SetTint") :: RemoteEvent

-- id -> catalog entry { id, name, kind, hint }. Lets a death name the anomaly the player
-- walked straight past, which is the single most useful teaching beat in the game.
local ANOMALY_BY_ID = {}
for _, entry in Config.Anomaly.Catalog do
	ANOMALY_BY_ID[entry.id] = entry
end

local gui = Instance.new("ScreenGui")
gui.Name = "AnomalyHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = plr:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(120, 180, 255)
local WARN = Color3.fromRGB(230, 90, 80)
local GOOD = Color3.fromRGB(90, 200, 130)

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, ts: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(235, 235, 245)
	l.TextScaled = false
	l.TextSize = ts
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- top-left status panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(230, 96)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Parent = gui
-- visual polish: rounded + cold stroke so the HUD reads as part of the horror theme
FxClient.theme(panel, { corner = 10, stroke = Color3.fromRGB(90, 120, 170), strokeThickness = 1.5, strokeTransparency = 0.35 })

local dayLbl = label(panel, "DAY 1", UDim2.fromOffset(200, 34), UDim2.fromOffset(14, 8), 28)
dayLbl.Font = Enum.Font.GothamBold
dayLbl.TextColor3 = ACCENT
local bestLbl = label(panel, "Best: Day 0", UDim2.fromOffset(200, 20), UDim2.fromOffset(14, 44), 15)
local codexLbl = label(panel, "Field Guide: 0/0", UDim2.fromOffset(200, 20), UDim2.fromOffset(14, 66), 15)

-- instructions (top-center)
local help = label(gui, "Walk the hall. Something wrong? TURN BACK (Q). Looks normal? ADVANCE (E). Wrong call = back to Day 1.",
	UDim2.fromOffset(680, 24), UDim2.new(0.5, -340, 0, 20), 15)
help.TextXAlignment = Enum.TextXAlignment.Center
help.TextColor3 = Color3.fromRGB(200, 205, 220)

-- hint pill (top-right)
local hintLbl = label(gui, "Hints: 0  (H at start pad)", UDim2.fromOffset(240, 22), UDim2.new(1, -256, 0, 18), 15)
hintLbl.TextXAlignment = Enum.TextXAlignment.Right

-- transient toast (center)
local toast = label(gui, "", UDim2.fromOffset(600, 40), UDim2.new(0.5, -300, 0.5, -120), 26)
toast.Font = Enum.Font.GothamBold
toast.TextXAlignment = Enum.TextXAlignment.Center
-- second, smaller line under the toast: the "what you missed" explanation after a wrong call.
local toastDetail = label(gui, "", UDim2.fromOffset(680, 26), UDim2.new(0.5, -340, 0.5, -80), 18)
toastDetail.TextXAlignment = Enum.TextXAlignment.Center
toastDetail.TextColor3 = Color3.fromRGB(210, 216, 232)
-- `lifetime` (seconds) defaults to the original 1.8s fade; the death toast asks for longer
-- because its detail line is the teaching beat and has to be readable (kept under the
-- server's 2.5s death pause so it never bleeds into the next pass).
local function showToast(text: string, color: Color3, detail: string?, lifetime: number?)
	toast.Text = text
	toast.TextColor3 = color
	toast.TextTransparency = 0
	toastDetail.Text = detail or ""
	toastDetail.TextTransparency = 0
	task.spawn(function()
		local myText = text
		local steps = math.max(1, math.floor((lifetime or 1.8) / 0.06))
		for i = 1, steps do
			if toast.Text ~= myText then return end
			toast.TextTransparency = i / steps
			toastDetail.TextTransparency = i / steps
			task.wait(0.06)
		end
		if toast.Text == myText then
			toast.Text = ""
			toastDetail.Text = ""
		end
	end)
end

-- bottom-left: code redeem
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.fromOffset(150, 30)
codeBox.Position = UDim2.new(0, 16, 1, -46)
codeBox.BackgroundColor3 = DARK
codeBox.BackgroundTransparency = 0.15
codeBox.BorderSizePixel = 0
codeBox.Font = Enum.Font.Gotham
codeBox.TextColor3 = Color3.fromRGB(235, 235, 245)
codeBox.PlaceholderText = "enter code"
codeBox.TextSize = 15
codeBox.Text = ""
codeBox.ClearTextOnFocus = false
codeBox.Parent = gui
Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 8)

local redeemBtn = Instance.new("TextButton")
redeemBtn.Size = UDim2.fromOffset(90, 30)
redeemBtn.Position = UDim2.new(0, 172, 1, -46)
redeemBtn.BackgroundColor3 = ACCENT
redeemBtn.BorderSizePixel = 0
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.TextColor3 = DARK
redeemBtn.TextSize = 15
redeemBtn.Text = "REDEEM"
redeemBtn.Parent = gui
Instance.new("UICorner", redeemBtn).CornerRadius = UDim.new(0, 8)
redeemBtn.Activated:Connect(function()
	local t = codeBox.Text
	if #t > 0 then
		RedeemRemote:FireServer(t)
		codeBox.Text = ""
	end
end)

-- bottom-right: tint picker (populated from State)
local tintRow = Instance.new("Frame")
tintRow.Size = UDim2.fromOffset(300, 30)
tintRow.Position = UDim2.new(1, -316, 1, -46)
tintRow.BackgroundTransparency = 1
tintRow.Parent = gui
local tintLayout = Instance.new("UIListLayout")
tintLayout.FillDirection = Enum.FillDirection.Horizontal
tintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
tintLayout.Padding = UDim.new(0, 6)
tintLayout.Parent = tintRow

-- Colours come from Config.TintRGB (plain {R,G,B} triples so the shared module stays usable
-- by the pure luau-CLI tests) — one source of truth for the swatch AND the carried light.
local TINT_FALLBACK = Color3.fromRGB(200, 200, 200)
local function tintColor(name: string): Color3
	local rgb = Config.TintRGB and Config.TintRGB[name]
	if type(rgb) == "table" and #rgb >= 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return TINT_FALLBACK
end

local tintButtons: { [string]: TextButton } = {}
-- ownership as of the LAST State push. Read at click time (never captured in the closure) so
-- a tint unlocked mid-session — redeeming ECLIPSE — is clickable without a rebuild.
local tintOwned: { [string]: boolean } = {}

-- Creates any swatch that doesn't exist yet. Appearance is NOT decided here (see
-- refreshTints): the old build-once guard is exactly why an unlocked tint kept looking
-- locked, and every locked tint kept looking live.
local function buildTints(tints: { string })
	for _, name in tints do
		if not tintButtons[name] then
			local b = Instance.new("TextButton")
			b.Name = "Tint_" .. name
			b.Size = UDim2.fromOffset(26, 26)
			b.Text = ""
			b.Font = Enum.Font.GothamBold
			b.TextSize = 13
			b.TextColor3 = Color3.fromRGB(20, 22, 32)
			b.AutoButtonColor = false
			b.BackgroundColor3 = tintColor(name)
			b.BorderSizePixel = 0
			b.Parent = tintRow
			Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
			local ring = Instance.new("UIStroke")
			ring.Name = "SelectionRing"
			ring.Color = ACCENT
			ring.Thickness = 2
			ring.Transparency = 1 -- shown only on the SELECTED tint
			ring.Parent = b
			b.Activated:Connect(function()
				if not tintOwned[name] then
					-- the server silently drops an unowned tint; without this the player just
					-- sees nothing happen and assumes the game is broken.
					showToast("Tint locked", WARN, "Unlock " .. name .. " with a code first.")
					return
				end
				TintRemote:FireServer(name)
			end)
			tintButtons[name] = b
		end
	end
end

-- Re-style every swatch for the CURRENT ownership set + selection. Called on every State
-- push, so the gold swatch lights up the moment ECLIPSE is redeemed.
local function refreshTints(owned, selected)
	-- fail OPEN if the server ever omits ownedTints: a HUD where nothing is clickable would
	-- be worse than the bug being fixed. The live server always sends the set.
	local haveSet = typeof(owned) == "table"
	for name, b in tintButtons do
		local isOwned = (not haveSet) or owned[name] == true
		tintOwned[name] = isOwned
		b.BackgroundColor3 = tintColor(name)
		b.BackgroundTransparency = if isOwned then 0 else 0.6
		b.Text = if isOwned then "" else "\u{1F512}" -- padlock on locked swatches
		local ring = b:FindFirstChild("SelectionRing")
		if ring and ring:IsA("UIStroke") then
			ring.Transparency = if name == selected then 0 else 1
		end
	end
end

-- ---------------------------------------------------------------- carried flashlight
-- The tint was stored, validated, persisted, replicated and pickable — but nothing ever lit
-- anything with it, so the cosmetic (and ECLIPSE's only reward) was invisible. A small light
-- carried by the local character: thematic for a dark observatory, deliberately not a
-- floodlight, and client-only (it is a cosmetic for its owner).
local LIGHT_NAME = "AnomalyTintLight"
local currentTint = Config.DefaultTint

local function ensureLight(char: Model): SpotLight?
	local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
	if not head or not head:IsA("BasePart") then return nil end
	local existing = head:FindFirstChild(LIGHT_NAME)
	if existing and existing:IsA("SpotLight") then return existing end
	if existing then existing:Destroy() end
	local s = Instance.new("SpotLight")
	s.Name = LIGHT_NAME
	s.Face = Enum.NormalId.Front -- the head's front == where the player is looking
	s.Angle = 55
	s.Range = 26
	s.Brightness = 1.2
	s.Shadows = false -- cheap: this is ambience, not a lighting rig
	s.Parent = head
	return s
end

-- yields (WaitForChild) — always call via task.spawn.
local function applyTintLight(char: Model?)
	if not char or not char.Parent then return end
	local light = ensureLight(char)
	if light then
		light.Color = tintColor(currentTint)
	end
end

plr.CharacterAdded:Connect(function(char)
	task.spawn(applyTintLight, char)
end)
if plr.Character then
	task.spawn(applyTintLight, plr.Character)
end

-- ---------------------------------------------------------------- remote wiring
StateRemote.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dayLbl.Text = "DAY " .. tostring(s.day)
	bestLbl.Text = "Best: Day " .. tostring(s.best)
	codexLbl.Text = "Field Guide: " .. tostring(s.codexCount) .. "/" .. tostring(s.codexTotal)
	hintLbl.Text = "Hints: " .. tostring(s.hintTokens) .. "  (H at start pad)"
	if s.tints then
		buildTints(s.tints)
		refreshTints(s.ownedTints, s.tint)
	end
	if type(s.tint) == "string" and s.tint ~= currentTint then
		currentTint = s.tint
		task.spawn(applyTintLight, plr.Character) -- no character yet? CharacterAdded re-applies
	end
end)

RevealRemote.OnClientEvent:Connect(function(r)
	if typeof(r) ~= "table" then return end
	if r.redeem ~= nil then
		if r.redeem == "ok" then
			showToast("Code redeemed!", GOOD)
		elseif r.redeem == "already" then
			showToast("Code already used", WARN)
		elseif r.redeem == "unknown" then
			showToast("Unknown code", WARN)
		elseif r.redeem == "empty" then
			showToast("Enter a code", WARN)
		elseif r.redeem == "unavailable" or r.redeem == "retry" then
			-- saving is down / another session holds the lock: nothing was granted, so say so
			-- instead of silently doing nothing (server refuses to grant what it can't persist)
			showToast(r.message or "Saving unavailable — try again in a moment", WARN)
		end
		return
	end
	-- one-shot "this session cannot save" notice (server sets readOnly when it does not hold
	-- the DataStore lock, and clears it if a later retry wins the lock back). Without this the
	-- player grinds a best day that will never persist and is never told.
	if r.readOnly ~= nil then
		if r.readOnly then
			showToast(r.message or "Progress is NOT saving this session", WARN,
				"Another session holds your save, or the data service is down. Try rejoining.", 3.2)
		else
			showToast(r.message or "Saving restored", GOOD, nil, 2.2)
		end
		return
	end
	-- hint reveal
	if r.ok == false then
		if r.reason == "too_far" then
			-- the hint is only spendable at the start pad; say so instead of looking dead
			showToast("Too far from the start pad", WARN, "Walk back to the glowing pad to use a hint.", 2.4)
		else
			showToast("No hints left", WARN)
		end
	elseif r.ok == true then
		-- the server tells us how many tokens survived the spend; show it so the player can
		-- budget the last hint instead of guessing.
		local left = ""
		if type(r.remaining) == "number" then
			local n = math.max(0, math.floor(r.remaining))
			left = "  (" .. tostring(n) .. (if n == 1 then " hint left)" else " hints left)")
		end
		if r.clean then
			showToast("HINT: the hall looks clean" .. left, GOOD)
		else
			showToast("HINT: something is WRONG" .. left, WARN)
		end
	end
end)

DeathRemote.OnClientEvent:Connect(function(d)
	if typeof(d) ~= "table" then return end
	-- the jumpscare beat: red vignette flash + camera shake + a short FOV punch
	FxClient.flash(Color3.fromRGB(180, 20, 20), 0.6, 0.7)
	FxClient.shake(0.5, 1.6)
	FxClient.fovPunch(12, 0.08, 0.4)
	local msg, detail
	if d.wasClean then
		msg = "You turned back on a CLEAN hall — Night reset (reached Day " .. tostring(d.reached) .. ")"
		detail = "Nothing was wrong that pass. ADVANCE (E) when the hall looks normal."
	else
		msg = "You MISSED an anomaly — Night reset (reached Day " .. tostring(d.reached) .. ")"
		-- name what was actually wrong: the whole point of a spot-the-difference game is
		-- learning the tell you walked past.
		if type(d.anomalyId) == "string" then
			local entry = ANOMALY_BY_ID[d.anomalyId]
			if entry then
				detail = "It was " .. tostring(entry.name) .. " — " .. tostring(entry.hint)
			else
				detail = "It was: " .. d.anomalyId -- id from a newer catalog than this client
			end
		end
	end
	showToast(msg, WARN, detail, 2.4)
end)

print("[Anomaly] HUD ready.")
