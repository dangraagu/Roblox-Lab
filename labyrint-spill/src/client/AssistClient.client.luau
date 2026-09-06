--[[==================================================================
	LABYRINT-SPILL  -  "HJELP MEG"-GUIDEN (klient)
	Laget for Marius & onkel :)

	Serveren teller hvor mange ganger du har feilet SAMME nivå. Har du feilet nok
	ganger, sender den AssistRemotes/AssistState og dette kortet dukker opp — inne
	i labyrinten som en kjøp-knapp, i lobbyen som et hint om at hjelpen finnes.

	Klienten bestemmer INGENTING: den viser bare det serveren sier, og sender et
	ønske uten argumenter (ingen pris, intet nivå). All validering skjer på
	serveren (se "HJELP MEG"-GUIDEN i MazeGame.server.luau). All tekst er engelsk.

	Kortet har knapper og står nederst, så på berøringsskjerm løftes det opp over
	båndet der Roblox tegner sine egne kontroller (styrepinne nede-venstre, hopp
	nede-høyre). Ellers ville kjøp-knappen ligget under tommelen og aldri kunne
	trykkes.
==================================================================]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Delt skjermstørrelse-modul (ren data — se src/shared/Responsive.luau).
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
-- Delt trykk-mål-modul (ren data — se src/shared/TouchTarget.luau).
local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("AssistPanel")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AssistPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 13
gui.Enabled = false
gui.Parent = playerGui

--==================  EFFEKTIV HØYDE (topplinja)  ================--
-- IgnoreGuiInset står på false (standard), så Roblox korter ned det tegnbare området med
-- topplinje-innslaget (~36 px) — mens budsjettene under regnes fra camera.ViewportSize.Y,
-- altså HELE skjermen. Et panel som fyller den høyden stikker nøyaktig innslaget for langt
-- ned, ned i båndet der mobil-kontrollene bor. Derfor mates den EFFEKTIVE høyden inn i
-- Responsive.layout og i alt som regnes ut av den. GetGuiInset gir TO Vector2-er; den
-- første er innslaget øverst til venstre. pcall fordi et oppsett som ikke gir oss innslaget
-- skal ende med hele høyden — som før — og ikke velte tegningen.
local function effectiveY(vy: number): number
	if gui.IgnoreGuiInset then
		return vy
	end
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and inset ~= nil and type(inset.Y) == "number" and vy - inset.Y > 0 then
		return vy - inset.Y
	end
	return vy
end

local function corner(inst, r)
	local u = Instance.new("UICorner"); u.CornerRadius = UDim.new(0, r or 8); u.Parent = inst
end

--====================  ROT-RAMME MED UISCALE  ====================--
-- En UIScale gjør INGENTING når den henger rett på en ScreenGui, så vi trenger en
-- gjennomsiktig rot-ramme som eier skaleringen, og kortet henger under den.
-- Active = false: spilleren holder finger på skjermen nesten hele tiden i en
-- hinderløype, og en gjennomsiktig ramme som sluker trykk ville låst bevegelsen.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- Gjeldende skjerm-oppsett. Settes ordentlig av applyLayout() rett under.
local rlayout = Responsive.layout(0, 0, UserInputService.TouchEnabled)

-- Avstand fra nederste kant når det IKKE finnes berøringskontroller å ta hensyn til.
local BOTTOM_MARGIN = 14
local CARD_W = 340
-- Knapperada starter her, og kortet slutter en luft under den. Knappene VOKSER på
-- berøring (44 design-piksler ble 26 på skjermen), så kortets høyde regnes ut av
-- applyLayout i stedet for å stå fast.
local BTN_Y, BTN_GAP = 66, 6

-- Trykk-mål i SKJERM-rom: UIScale-en som får kortet til å passe på en telefon krymper
-- samtidig begge knappene. tap() vokser design-tallet med 1/skala og lar det aldri lande
-- under 44 px-gulvet; grow() gjør det samme uten gulv, for tekst-takene, som må få lov
-- til å være små. Ingen av dem gjør noe uten berøringskontroller, så desktop står stille.
local function tap(designPx)
	return TouchTarget.tap(designPx, rlayout)
end
local function grow(designPx)
	return TouchTarget.grow(designPx, rlayout)
end

-- Nederst i midten: der blikket er når man står fast og lurer på hva man skal gjøre.
local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
card.Size = UDim2.fromOffset(CARD_W, BTN_Y + 44 + BTN_GAP)
card.BackgroundColor3 = Color3.fromRGB(28, 31, 44)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Active = false -- selve kortflata skal ikke sluke trykk; knappene under gjør sitt
card.Parent = root
corner(card, 12)

-- Ekstra nedskalering av selve kortet, oppå rot-skaleringen: kortet er 340 faste
-- piksler bredt, og på en veldig smal design-flate må det krympe litt til.
local scale = Instance.new("UIScale"); scale.Parent = card

local function fit()
	-- Alt under rot-rammen måles i DESIGN-piksler: rot-rammen er 1/scale så stor som
	-- skjermen, og UIScale krymper den ned igjen. Derfor deler vi skjermbredden på
	-- skalaen før vi sammenligner med kortets faste bredde — ellers krymper kortet
	-- én gang for mye på telefon.
	local vp = gui.AbsoluteSize
	if vp.X > 0 then
		scale.Scale = math.clamp((vp.X / rlayout.scale - 20) / CARD_W, 0.6, 1)
	end
end

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 24)
titleLbl.Position = UDim2.fromOffset(10, 8)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextScaled = true
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Color3.fromRGB(255, 224, 130)
titleLbl.Text = "Stuck?"
titleLbl.Parent = card
local ttc = Instance.new("UITextSizeConstraint"); ttc.MaxTextSize = 19; ttc.Parent = titleLbl

local bodyLbl = Instance.new("TextLabel")
bodyLbl.Size = UDim2.new(1, -20, 0, 30)
bodyLbl.Position = UDim2.fromOffset(10, 32)
bodyLbl.BackgroundTransparency = 1
bodyLbl.Font = Enum.Font.Gotham
bodyLbl.TextScaled = true
bodyLbl.TextWrapped = true
bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
bodyLbl.TextColor3 = Color3.fromRGB(198, 204, 218)
bodyLbl.Text = ""
bodyLbl.Parent = card
local btc = Instance.new("UITextSizeConstraint"); btc.MaxTextSize = 13; btc.Parent = bodyLbl

-- 44px høy: stor nok til å treffe med tommelen på telefon. Den endelige størrelsen
-- settes av applyLayout lenger nede; dette er bare noe å tegne før første kall.
local buyBtn = Instance.new("TextButton")
buyBtn.Size = UDim2.new(1, -60, 0, 44)
buyBtn.Position = UDim2.fromOffset(10, BTN_Y)
buyBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 190)
buyBtn.TextColor3 = Color3.new(1, 1, 1)
buyBtn.Font = Enum.Font.GothamBold
buyBtn.TextScaled = true
buyBtn.Text = "💡 Show me the way"
buyBtn.Parent = card
corner(buyBtn, 10)
local abtc = Instance.new("UITextSizeConstraint"); abtc.MaxTextSize = 17; abtc.Parent = buyBtn

local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.fromOffset(40, 44)
hideBtn.AnchorPoint = Vector2.new(1, 0)
hideBtn.Position = UDim2.new(1, -10, 0, BTN_Y)
hideBtn.BackgroundColor3 = Color3.fromRGB(64, 68, 86)
hideBtn.TextColor3 = Color3.new(1, 1, 1)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextScaled = true
hideBtn.Text = "✕"
hideBtn.Parent = card
corner(hideBtn, 10)
local hbtc = Instance.new("UITextSizeConstraint"); hbtc.MaxTextSize = 18; hbtc.Parent = hideBtn

local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	rlayout = Responsive.layout(v.X, effectiveY(v.Y), UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = rlayout.scale

	-- Rot-rammen må vokse med 1/skala så rot × skala lander nøyaktig på skjermkanten.
	-- Uten dette krymper kortet inn i øvre venstre hjørne på telefon, mens det ser
	-- helt riktig ut på desktop der skalaen er 1 og feilen er usynlig.
	root.Size = UDim2.fromScale(1 / rlayout.scale, 1 / rlayout.scale)

	-- Løft kortet opp over mobil-kontrollene. controlPad er SKJERM-piksler, mens
	-- posisjonen her er design-piksler, så vi deler på skalaen. På desktop er
	-- controlPad 0 og kortet står nøyaktig der det alltid har stått.
	local lift = BOTTOM_MARGIN + math.floor(rlayout.controlPad / rlayout.scale)
	card.Position = UDim2.new(0.5, 0, 1, -lift)

	-- The two buttons are the whole point of the card, so they are sized in screen space:
	-- 44 design px came out at 26 px on an 800x360 screen, well under the 44 px tap floor.
	-- The card grows with them, so a taller button never hangs out of its own card.
	local btnH = tap(44)
	local hideW = tap(40)
	buyBtn.Size = UDim2.new(1, -(hideW + 20), 0, btnH)
	buyBtn.Position = UDim2.fromOffset(10, BTN_Y)
	abtc.MaxTextSize = grow(17)
	hideBtn.Size = UDim2.fromOffset(hideW, btnH)
	hideBtn.Position = UDim2.new(1, -10, 0, BTN_Y)
	hbtc.MaxTextSize = grow(18)
	card.Size = UDim2.fromOffset(CARD_W, BTN_Y + btnH + BTN_GAP)

	fit()
end

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter
-- den ut ved enkelte respawn, så vi kobler lytteren på nytt når kameraet byttes.
local viewportConn
local function watchViewport()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end

--=======================  TILSTAND  =============================--
local buyAssistFn                 -- RemoteFunction (fylles ut nedenfor)
local latest = nil                -- siste tilstand fra serveren
local dismissedKey = nil          -- "nivå:antall-forsøk" spilleren har lukket kortet på
local busy = false

-- Myntene leses rett fra leaderstats, som serveren allerede oppdaterer live —
-- da trenger vi ingen ekstra trafikk bare for å vise "har du råd?".
local function coins()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	return (c and c.Value) or (latest and latest.coins) or 0
end

local function keyFor(s)
	return tostring(s.level) .. ":" .. tostring(s.fails) .. ":" .. tostring(s.inMaze)
end

local function render()
	local s = latest
	if not s or not s.enabled then gui.Enabled = false; return end

	-- Guide kjøpt: kort kvittering, så forsvinner kortet av seg selv.
	if s.active then
		titleLbl.Text = "💡 Guide active"
		titleLbl.TextColor3 = Color3.fromRGB(120, 235, 255)
		bodyLbl.Text = "Follow the blue lights to the exit. This run counts for progress, but not for the time records."
		buyBtn.Visible = false
		hideBtn.Visible = true
		gui.Enabled = true
		fit()
		return
	end

	if not s.offered then gui.Enabled = false; return end
	if dismissedKey == keyFor(s) then gui.Enabled = false; return end

	local have = coins()
	titleLbl.TextColor3 = Color3.fromRGB(255, 224, 130)
	titleLbl.Text = "Stuck on Level " .. s.level .. "?"
	buyBtn.Visible = s.inMaze
	hideBtn.Visible = true

	if not s.inMaze then
		-- I lobbyen: si at hjelpen finnes, og hvor man får tak i den.
		bodyLbl.Text = ("You've tried it %d times. Go back in and buy a Guide for %d coins — it lights the whole way to the exit.")
			:format(s.fails, s.price)
	elseif have >= s.price then
		bodyLbl.Text = ("A Guide lights the whole way to the exit, for this run. Costs %d coins (you have %d)."):format(s.price, have)
		buyBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 190)
		buyBtn.Text = "💡 Show me the way — " .. s.price
	else
		bodyLbl.Text = ("A Guide costs %d coins and you have %d. Grab coins on the way, or claim the Daily Reward in the lobby."):format(s.price, have)
		buyBtn.BackgroundColor3 = Color3.fromRGB(78, 82, 100)
		buyBtn.Text = "Need " .. (s.price - have) .. " more coins"
	end
	gui.Enabled = true
	fit()
end

hideBtn.Activated:Connect(function()
	if latest then dismissedKey = keyFor(latest) end
	gui.Enabled = false
end)

buyBtn.Activated:Connect(function()
	if busy or not buyAssistFn or not latest or not latest.inMaze then return end
	if coins() < (latest.price or math.huge) then return end   -- serveren avviser uansett
	busy = true
	buyBtn.Text = "…"
	local ok, res = pcall(function() return buyAssistFn:InvokeServer() end)
	busy = false
	if ok and type(res) == "table" and res.ok then
		return   -- serveren sender ny AssistState; render() tar seg av resten
	end
	local reason = (ok and type(res) == "table" and res.reason) or "error"
	if reason == "insufficient" then
		bodyLbl.Text = "Not enough coins yet. Collect a few more, or claim the Daily Reward in the lobby."
	elseif reason == "notstuck" then
		bodyLbl.Text = "The Guide unlocks after a few tries on this level."
	elseif reason == "notinmaze" then
		bodyLbl.Text = "Go into the maze first, then buy the Guide."
	else
		bodyLbl.Text = "Couldn't buy the Guide right now. Try again in a moment."
	end
	buyBtn.Text = "💡 Show me the way"
end)

--==================  KOBLE TIL SERVEREN  ========================--
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("AssistRemotes", 30)
	if not folder then return end
	buyAssistFn = folder:WaitForChild("BuyAssist", 15)
	local stateEvent = folder:WaitForChild("AssistState", 15)
	if not stateEvent then return end
	stateEvent.OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		-- Nytt nivå (eller nytt forsøk) => kortet skal få vise seg igjen.
		if not latest or latest.level ~= s.level then dismissedKey = nil end
		latest = s
		pcall(render)
	end)
end)

--==============  FØRSTE OPPSETT + LYTTERE (ALLER SIST)  =========--
-- Rekkefølgen er med vilje: remotene kobles opp FØRST, så første oppsett, og lytteren på
-- inndata-enheten aller sist. Et LocalScript som reiser stopper på stedet, så det samme
-- kallet plassert over OnClientEvent-handlerne ville — den dagen det reiste — etterlatt
-- spilleren med et frosset HUD og ingen måte å merke det på.
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

-- Hver trykk-mål-størrelse henger på layout.controlPad, som kommer fra
-- UserInputService.TouchEnabled. Endrer berøringen seg UTEN at pikselstørrelsen gjør det
-- (et nettbrett som kobler fra tastaturet, en telefon som får mus), fyrer ViewportSize
-- aldri, og hver kontroll beholder størrelsen fra forrige inndata-enhet — nøyaktig slik
-- rekord-knappen ble stående på 29x29. Layout er kosmetikk; tilstands-røret er det ikke,
-- så selve Connect ligger i pcall.
local touchOk, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not touchOk then
	warn("[Guide] ingen TouchEnabled-lytter; oppsettet følger bare vinduet: " .. tostring(touchErr))
end
