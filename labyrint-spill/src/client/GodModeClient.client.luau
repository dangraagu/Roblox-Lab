--[[==================================================================
	LABYRINT-SPILL  -  GUDEMODUS (fly + gå gjennom vegger)  [klient]
	Laget for Marius & onkel :)

	Dette er et LOKALT skript (Rojo legger src/client i StarterPlayerScripts).
	Det gir "gudemodus" til NAVNGITTE spillere: fly rundt + gå gjennom vegger.
	Udødelighet ordnes av SERVEREN — vi ber bare pent om den via en Remote.

	Kun for spillere i ReplicatedStorage/GodUsers (match på Roblox-brukernavn).
	Vanlige spillere: skriptet stopper HELT med en gang (ingen GUI, ingenting).

	MOBIL FØRST: spilleren er et barn på TELEFON. Alt styres med TRYKK:
	  - En stor "✈️ Gudemodus"-knapp på HØYRE kant, midt på skjermen (klar av
	    styrepinnen nede-venstre, hoppknappen nede-høyre og knapperaden øverst).
	  - Når gudemodus er PÅ dukker to store pileknapper opp OVER knappen:
	    ▲ = fly opp, ▼ = fly ned (holdes inne med tommelen).
	  - Vannrett bevegelse kommer GRATIS fra styrepinnen (og WASD på PC) via
	    humanoid.MoveDirection — derfor virker det på telefon uten egen kode.
	  - PC i tillegg: Mellomrom = opp, venstre Ctrl = ned.

	Ingen bilder/lyder/assets — bare Frame / TextButton / TextLabel / UICorner /
	UIStroke. Alt er nil-sjekket: mangler figuren eller remoten, krasjer vi aldri.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--==========================  PORTVAKT (FØRST)  ===================--
-- MÅ komme først: bare navngitte gude-spillere slipper forbi. Alle andre
-- returnerer med en gang — ingen GUI, ingen løkker, ingenting.
local GodUsers = require(ReplicatedStorage:WaitForChild("GodUsers"))
local LocalPlayer = Players.LocalPlayer

if not GodUsers.has(LocalPlayer) then
	return
end

-- Everything below this line only ever runs for a god user — including the GuiService lookup,
-- so a normal player still walks straight out of the gate above without touching a thing.
-- Shared sizing rules so the panel survives a phone; note the require form, since a bare
-- string require like `require("./Responsive")` resolves in the luau CLI but is invalid in
-- Roblox.
local GuiService = game:GetService("GuiService")
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))

--============================  INNSTILLINGER  ====================--
local FLY_SPEED = 55           -- studs/sek — rask, men grei for en fly-juks
local COL_OFF = Color3.fromRGB(64, 70, 92)    -- knapp når gudemodus er AV
local COL_ON = Color3.fromRGB(60, 180, 90)    -- grønn når gudemodus er PÅ
local COL_ARROW = Color3.fromRGB(64, 120, 200) -- pileknappene

--============================  TILSTAND  =========================--
-- godOn overlever respawn (serveren respawner deg hvert nivå), så gudemodus
-- kan slås på én gang og fortsette gjennom nivåene.
local godOn = false

-- Gjeldende figur. Nil-sjekkes HVER frame — vi rører aldri en figur som ikke er der.
local character = LocalPlayer.Character
local humanoid = nil
local root = nil

-- Hold-tilstand for opp/ned. Knapp og tastatur er to uavhengige kilder som slås
-- sammen til én "opp"/"ned" hver frame (holder du begge, blir det 0 = svever).
local btnUp, btnDown = false, false
local keyUp, keyDown = false, false

local heartbeatConn = nil       -- den ENE fly/noclip-løkka (aldri stablet)
local setGod = nil              -- server-remoten (fylles ut når vi finner den)

--==========================  HJELPERE  ===========================--
local function corner(inst, r)
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, r or 8)
	uc.Parent = inst
	return uc
end

local function stroke(inst, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick or 1
	s.Parent = inst
	return s
end

-- Be serveren skru udødelighet av/på. Alltid nil-sjekket + pakket i pcall, så et
-- nettverksrykk eller en manglende remote aldri kan velte skriptet.
local function fireGod(enabled)
	if not setGod then
		return
	end
	pcall(function()
		setGod:FireServer(enabled and true or false)
	end)
end

--============================  UI-OPPSETT  =======================--
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Aldri to like GUI-er. Skriptet kjører normalt bare én gang (StarterPlayerScripts
-- kopieres én gang pr spiller, ikke ved respawn), men om en gammel henger igjen
-- hopper vi heller helt av enn å stable duplikater.
if playerGui:FindFirstChild("Gudemodus") then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "Gudemodus"
gui.ResetOnSpawn = false        -- MÅ være av: serveren respawner deg hvert nivå
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 15           -- over de andre panelene
gui.Parent = playerGui

--==================  EFFEKTIV HØYDE (topplinja)  ================--
-- IgnoreGuiInset står på false (standard), så Roblox korter ned det tegnbare området med
-- topplinje-innslaget (~36 px) — mens budsjettene under regnes fra camera.ViewportSize.Y,
-- altså HELE skjermen. En stabel som bygges opp fra bunnen av den høyden havner nøyaktig
-- innslaget for langt ned, ned i båndet der mobil-kontrollene bor. Derfor mates den
-- EFFEKTIVE høyden inn i Responsive.layout og i alt som regnes ut av den. GetGuiInset gir
-- TO Vector2-er; den første er innslaget øverst til venstre. pcall fordi et oppsett som
-- ikke gir oss innslaget skal ende med hele høyden — som før — og ikke velte tegningen.
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

-- A UIScale does nothing parented to a ScreenGui, so the buttons hang off this root Frame
-- and the root is what the scale acts on. Called uiRoot, because `root` in this file is
-- already the character's HumanoidRootPart.
local uiRoot = Instance.new("Frame")
uiRoot.Name = "Root"
uiRoot.BackgroundTransparency = 1
uiRoot.BorderSizePixel = 0
uiRoot.Size = UDim2.fromScale(1, 1)
uiRoot.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = uiRoot

-- Gjeldende skjerm-oppsett. Settes ordentlig av applyLayout() lenger nede; kameraet leses
-- ikke her, fordi workspace.CurrentCamera er nil et bilde eller to ved oppstart og byttes
-- ut ved enkelte respawn (se watchViewport nederst).
local layout = Responsive.layout(0, 0, UserInputService.TouchEnabled)

-- A button drawn 50 px tall comes out at 50 * scale on screen, which is 30 px on a phone —
-- too small for the child thumb this panel was designed around. Both helpers below only do
-- anything where the player is on touch (controlPad is non-zero exactly then); on a
-- mouse-driven window they hand back the design number untouched.
--
--   tap()  — something the player presses. Grown by 1/scale AND floored at 44 screen px.
--   grow() — text size caps. Grown, but no floor: a 17 px cap with a 44 px floor on it would
--            come out as lettering taller than the button it sits in.
--
-- The arithmetic lives in the shared TouchTarget module rather than in a copy per file.
local function tap(designPx)
	return TouchTarget.tap(designPx, layout)
end
local function grow(designPx)
	return TouchTarget.grow(designPx, layout)
end

-- ---- Av/på-knappen: HØYRE kant, LITT UNDER midten ----
-- Flyttet ned (0.5, +60) så den ikke krasjer med rekord-panelet øverst-til-høyre,
-- men fortsatt over hopp-knappen (nede-høyre). applyLayout nederst i fila plasserer
-- knappen og pilene, og holder hele stabelen klar av mobil-kontrollene.
local toggle = Instance.new("TextButton")
toggle.Name = "GudeKnapp"
toggle.Size = UDim2.fromOffset(160, 50)
toggle.AnchorPoint = Vector2.new(1, 1)
toggle.Position = UDim2.new(1, -14, 0.5, 85)
toggle.BackgroundColor3 = COL_OFF
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextScaled = true
toggle.Text = "✈️ God mode OFF"
toggle.AutoButtonColor = true
toggle.Parent = uiRoot
corner(toggle, 10)
stroke(toggle, Color3.fromRGB(20, 24, 34), 1)
local toggleTsc = Instance.new("UITextSizeConstraint")
toggleTsc.MaxTextSize = 17
toggleTsc.MinTextSize = 11
toggleTsc.Parent = toggle
local togglePad = Instance.new("UIPadding")
togglePad.PaddingLeft = UDim.new(0, 8)
togglePad.PaddingRight = UDim.new(0, 8)
togglePad.Parent = toggle

-- ---- Stor pileknapp-fabrikk (>=56px, lett for en barne-tommel) ----
-- Størrelse og plassering settes av applyLayout; verdiene her er bare noe å tegne
-- før første kall.
local function makeArrow(name, glyph)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(76, 76)              -- godt over 56px
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -14, 0.5, 0)
	b.BackgroundColor3 = COL_ARROW
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = glyph
	b.AutoButtonColor = true
	b.Visible = false                              -- skjult til gudemodus er PÅ
	b.Parent = uiRoot
	corner(b, 14)
	stroke(b, Color3.fromRGB(20, 24, 34), 1)
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 40
	tsc.MinTextSize = 20
	tsc.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = b
	return b
end

-- Fly-pilene på HØYRE side, rett over av/på-knappen. (Vises kun når gudemodus er PÅ.)
local upBtn = makeArrow("FlyOpp", "▲")
local downBtn = makeArrow("FlyNed", "▼")

--============================  RESPONSIVT OPPSETT  ===============--
-- Places the toggle and the two fly arrows for the current viewport. Roblox's jump button
-- owns the bottom-right corner, so the stack is built upwards from where that band starts
-- rather than from the middle of the screen: on a short phone screen the whole thing slides
-- up instead of ending underneath a control the player can never tap through.
local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	-- Den tegnbare høyden, ikke hele vinduet: se effectiveY over.
	local effY = effectiveY(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = layout.scale
	-- Grow the root by 1/scale so root * scale lands exactly on the viewport. Skip this and
	-- the buttons shrink into the top-left corner on a phone while looking fine on desktop.
	uiRoot.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local viewY = if effY > 0 then effY else Responsive.REF_Y
	local rootH = viewY / layout.scale
	local floorY = rootH - layout.controlPad / layout.scale - Responsive.MARGIN

	local btnH = tap(50)
	toggle.Size = UDim2.fromOffset(tap(160), btnH)
	toggleTsc.MaxTextSize = grow(17)
	-- Just below the middle by default, but never further down than the control band allows.
	local toggleBottom = math.min(rootH * 0.5 + 60 + btnH / 2, floorY)
	toggle.Position = UDim2.new(1, -14, 0, toggleBottom)

	local arrow = tap(if layout.compact then 56 else 76)
	for _, b in ipairs({ upBtn, downBtn }) do
		b.Size = UDim2.fromOffset(arrow, arrow)
		local tsc = b:FindFirstChildOfClass("UITextSizeConstraint")
		if tsc then
			tsc.MaxTextSize = grow(40)
		end
	end

	if layout.compact then
		-- Phone: the arrows sit side by side above the toggle. Stacked they would not fit
		-- between the shop buttons along the top and the touch controls at the bottom.
		local arrowsBottom = toggleBottom - btnH - 8
		upBtn.Position = UDim2.new(1, -14, 0, arrowsBottom)
		downBtn.Position = UDim2.new(1, -(14 + arrow + 8), 0, arrowsBottom)
	else
		-- Desktop: ▲ over ▼ over the toggle, exactly as before.
		local downBottom = toggleBottom - btnH - 12
		downBtn.Position = UDim2.new(1, -14, 0, downBottom)
		upBtn.Position = UDim2.new(1, -14, 0, downBottom - arrow - 8)
	end
end

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter den ut ved
-- enkelte respawn — og gudemodus respawner deg hvert nivå. Vi kobler lytteren på nytt når
-- kameraet byttes, og kobler den gamle FRA først, så vi ikke samler opp forbindelser. Dette
-- er den samme rebindingen som HUD-, kart-, rekord-, guide- og kringkastings-skriptene
-- bruker; før hadde denne halvdelen av spillet et kamera fanget ved lasting, og de to
-- halvdelene sto for hver sin oppfatning av nøyaktig det samme plattform-faktumet.
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

--==========================  NOCLIP + FLY  =======================--
-- Sett CanCollide tilbake til normalt. I en standard Roblox-figur skal
-- kroppsdelene ha CanCollide=true (så man står på gulvet), mens HumanoidRootPart
-- normalt er false. (Respawn hvert nivå nullstiller uansett alt trygt.)
local function restoreCollision()
	local char = character
	if not char then
		return
	end
	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") then
			part.CanCollide = (part.Name ~= "HumanoidRootPart")
		end
	end
end

-- Selve fly + noclip-steget. Kjører hver Heartbeat MENS gudemodus er på.
-- Nil-sjekker figur/humanoid/root hver eneste frame — feiler aldri om figuren
-- akkurat nå er borte (død/respawn).
local function flyStep()
	local char = character
	local hum = humanoid
	local rt = root
	if not char or not hum or not rt then
		return
	end
	if not rt.Parent or not hum.Parent then
		return
	end

	-- NOCLIP: slå av kollisjon på kroppsdelene (kollisjon er klient-side i Roblox,
	-- så dette lar spilleren gå/fly gjennom vegger LOKALT). GetChildren gir bare
	-- de direkte kroppsdelene + HumanoidRootPart — ikke tilbehør (som ikke
	-- kolliderer likevel), så vi treffer nøyaktig det vi vil.
	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end

	-- Loddrett: +1 opp / -1 ned, fra knapp ELLER tastatur. Begge = 0 (svever).
	local vertical = 0
	if btnUp or keyUp then
		vertical += 1
	end
	if btnDown or keyDown then
		vertical -= 1
	end

	-- Vannrett kommer fra styrepinnen (mobil) OG WASD (PC), kamera-relativt på
	-- XZ-planet — begge deler ligger allerede i humanoid.MoveDirection (0 eller
	-- enhetsvektor). Vi setter HELE farten hver frame, så tyngdekraften
	-- overstyres: uten input blir farten null → spilleren svever på stedet.
	local move = hum.MoveDirection
	rt.AssemblyLinearVelocity = (move * FLY_SPEED) + Vector3.new(0, vertical * FLY_SPEED, 0)
end

-- Start fly-løkka — men BARE hvis den ikke allerede kjører (aldri stable løkker).
local function startLoop()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(flyStep)
end

-- Stopp fly-løkka rent (så vi ikke lenger overstyrer farten → fysikk tar over).
local function stopLoop()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

-- Vis/skjul pileknappene. Når vi skjuler dem nullstiller vi knapp-holdet, så en
-- skjult knapp aldri kan bli "hengende inne".
local function setArrowsVisible(vis)
	upBtn.Visible = vis
	downBtn.Visible = vis
	if not vis then
		btnUp = false
		btnDown = false
	end
end

--==========================  AV/PÅ-LOGIKK  =======================--
local function applyGod(on)
	godOn = on
	if on then
		toggle.Text = "✈️ God mode ON"
		toggle.BackgroundColor3 = COL_ON
		setArrowsVisible(true)
		startLoop()
		fireGod(true)       -- serveren gir udødelighet
	else
		toggle.Text = "✈️ God mode OFF"
		toggle.BackgroundColor3 = COL_OFF
		setArrowsVisible(false)
		stopLoop()          -- slutt å overstyre farten
		restoreCollision()  -- gi kollisjon tilbake (kan stå/gå normalt igjen)
		fireGod(false)      -- serveren fjerner udødelighet
	end
end

toggle.Activated:Connect(function()
	applyGod(not godOn)
end)

--==========================  KNAPP-HOLD (TRYKK)  =================--
-- InputBegan/InputEnded på selve knappen gir ekte HOLD på både telefon (Touch) og
-- PC (mus). InputEnded fyrer også om fingeren glir av → knappen henger ikke fast.
local function bindHold(button, setTrue)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setTrue(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setTrue(false)
		end
	end)
end

bindHold(upBtn, function(v) btnUp = v end)
bindHold(downBtn, function(v) btnDown = v end)

--==========================  TASTATUR (PC)  ======================--
-- Mellomrom = opp, venstre Ctrl = ned. Vi setter bare hold når gudemodus er på og
-- input ikke er "spist" (f.eks. mens man skriver i chatten). InputEnded frigjør
-- ALLTID, så taster ikke kan bli hengende om gudemodus slås av mens de holdes.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not godOn then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		keyUp = true
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		keyDown = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		keyUp = false
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		keyDown = false
	end
end)

--==========================  FIGUR + RESPAWN  ====================--
-- Hent figur/humanoid/root på nytt hver gang spilleren spawner. Var gudemodus PÅ
-- (serveren respawner deg hvert nivå), rustter vi den opp igjen: vis knappene,
-- start løkka (guardet mot dobbel), og be serveren gi udødelighet til den NYE
-- figuren. WaitForChild med tak, og løkka nil-sjekker uansett.
local function bindCharacter(char)
	character = char
	humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)

	if godOn then
		setArrowsVisible(true)
		startLoop()
		fireGod(true)   -- ny figur/nivå → be om udødelighet på nytt
	end
end

LocalPlayer.CharacterAdded:Connect(function(char)
	bindCharacter(char)
end)

-- Er figuren allerede lastet (skriptet startet etter spawn)? Bind den også — i en
-- egen tråd så en eventuell WaitForChild ikke bremser oppstarten.
if LocalPlayer.Character then
	task.spawn(bindCharacter, LocalPlayer.Character)
end

--==========================  KOBLE TIL REMOTEN  ==================--
-- Serveren lager ReplicatedStorage/GodRemotes/SetGodMode. Vi venter litt på den
-- uten å blokkere resten. Kommer den sent MENS gudemodus alt er på, synkroniserer
-- vi tilstanden med en gang den er der. Mangler den helt, virker fly + noclip
-- fortsatt lokalt — bare uten server-udødeligheten (skriptet krasjer aldri).
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("GodRemotes", 30)
	if folder then
		setGod = folder:WaitForChild("SetGodMode", 15)
	end
	if not setGod then
		warn("[Gudemodus] Fant ikke GodRemotes/SetGodMode — udødelighet gis ikke før server-delen er inne.")
		return
	end
	if godOn then
		fireGod(true)   -- var alt på før remoten kom → synk serveren nå
	end
end)

--==============  FØRSTE OPPSETT + LYTTERE (ALLER SIST)  =========--
-- Rekkefølgen er med vilje: remoten kobles opp FØRST, så første oppsett, og lytteren på
-- inndata-enheten aller sist. Et LocalScript som reiser stopper på stedet, så det samme
-- kallet plassert over remote-oppkoblingen ville — den dagen det reiste — etterlatt
-- spilleren med et frosset panel og ingen måte å merke det på.
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

-- Hver trykk-mål-størrelse henger på layout.controlPad, som kommer fra
-- UserInputService.TouchEnabled. Endrer berøringen seg UTEN at pikselstørrelsen gjør det
-- (et nettbrett som kobler fra tastaturet, en telefon som får mus), fyrer ViewportSize
-- aldri, og hver kontroll beholder størrelsen fra forrige inndata-enhet — nøyaktig slik
-- rekord-knappen i rekord-panelet ble stående på 29x29. Layout er kosmetikk; tilstands-røret
-- er det ikke, så selve Connect ligger i pcall.
local touchOk, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not touchOk then
	warn("[Gudemodus] ingen TouchEnabled-lytter; oppsettet følger bare vinduet: " .. tostring(touchErr))
end
