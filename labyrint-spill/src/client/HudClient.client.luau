--[[==================================================================
	LABYRINT-SPILL  -  HUD + MEDALJE-OPPSUMMERING (klient)
	Laget for Marius & onkel :)

	Dette er et LOKALT skript (Rojo legger src/client i StarterPlayerScripts).
	Det gjør to jobber, og TEGNER ALT SELV — ingen bilder/lyder/assets, bare
	Frame / TextLabel / UICorner / UIStroke / UIGradient.

	  JOBB 1 — Fast HUD (alltid synlig, øverst i midten): hvilket nivå du er på,
	           nivåets rekord (🏆) og din egen beste tid. Oppdateres hver gang
	           serveren sender "LevelInfo".

	  JOBB 2 — Oppsummerings-kort (TrackMania-stil): når du kommer deg ut av et
	           nivå viser serveren "LevelComplete", og vi spretter opp et kort i
	           midten med medalje, tider og eventuelle rekord-jubel. Kortet
	           forsvinner av seg selv etter ~4,5 sek.

	Serveren er sjefen: den regner ut medaljer/rekorder og forteller oss fasit.
	Klienten bare TEGNER det. Alt er nil-sjekket — første gang man spiller finnes
	det verken rekord eller personlig beste, og da skal ingenting krasje.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Delt medalje-/tid-modul (ren data + fmtTime). Denne MÅ finnes; serveren
-- kloner src/shared inn i ReplicatedStorage før spillerne kobler seg på.
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))

-- Delt skjermstørrelse-modul: bestemmer hvor stort HUD-et får lov å være på
-- telefon/nettbrett/desktop. Ren data — se src/shared/Responsive.luau.
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))

--==========================  HJELPERE  ===========================--
-- {r,g,b} 0-255  ->  Color3. Tåler tull (mangler/feil form) og faller pent
-- tilbake til en grå farge i stedet for å krasje.
local function c3(rgb)
	if type(rgb) == "table" and type(rgb[1]) == "number"
		and type(rgb[2]) == "number" and type(rgb[3]) == "number" then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return Color3.fromRGB(180, 180, 180)
end

-- Trygg medalje-nøkkel: godta bare noe som faktisk finnes i Medals.display,
-- ellers bruk "none" (den grå "Fullført"-visningen).
local function medalKey(m)
	if type(m) == "string" and Medals.display[m] then
		return m
	end
	return "none"
end

-- Runde hjørner.
local function corner(inst, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r or 8)
	u.Parent = inst
	return u
end

-- Kantlinje.
local function stroke(inst, color, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick or 1
	s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

-- Liten mørk-til-mørkere dybde-gradient (rent kosmetisk).
local function depthGradient(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = inst
	return g
end

-- Sentrert tekst-etikett (bruker AnchorPoint 0.5,0 så vi kan flyt-plassere den).
local function mkLabel(parent, w, h, ts, font, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.fromOffset(w, h)
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = ts
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

-- En "pille"/bjelke: samme som mkLabel, men med farget bakgrunn og runde hjørner.
-- Brukes til de fremhevede jubel-linjene ("Ny personlig rekord!" / "NY REKORD!").
local function mkBar(parent, w, h, ts, font, bg, fg)
	local l = mkLabel(parent, w, h, ts, font, fg)
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = bg
	corner(l, math.floor(h / 2))
	return l
end

--============================  SKJERM-GUI  =======================--
local playerGui = player:WaitForChild("PlayerGui")

-- Ikke lag to av samme HUD. Skriptet kjører normalt bare én gang (og GUI-en
-- overlever respawn via ResetOnSpawn=false), men om en gammel henger igjen så
-- fjerner vi den først så vi aldri stabler dupliserte HUD-er oppå hverandre.
local old = playerGui:FindFirstChild("MedaljeHud")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MedaljeHud"
gui.ResetOnSpawn = false          -- MÅ være av: serveren respawner deg hvert nivå
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 12             -- over tema-butikken (10)
gui.Parent = playerGui

--====================  ROT-RAMME MED UISCALE  ====================--
-- En UIScale gjør INGENTING når den henger rett på en ScreenGui, så vi trenger en
-- gjennomsiktig rot-ramme som eier skaleringen. Alt HUD-innhold henger under den
-- i stedet for rett på gui-en, slik at hele HUD-et krymper i takt på små skjermer.
--
-- Active = false er viktig i et hinderløype-spill: spilleren holder finger på
-- skjermen nesten hele tiden, og en gjennomsiktig ramme som "spiser" trykk ville
-- gjort det umulig å bevege seg. En Frame sluker bare input når Active er true.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- Gjeldende skjerm-oppsett. Settes ordentlig av applyLayout() nederst i fila.
local layout = Responsive.layout(0, 0, UserInputService.TouchEnabled)

--==================  JOBB 1: FAST HUD (topp-midten)  =============--
-- Gjennomsiktig "Level"-felt: bare flytende tekst med svart kant (lesbar over
-- selve spillet). Rekorden vises nå øverst-til-HØYRE (eget panel), ikke her.
local hudPanel = Instance.new("Frame")
hudPanel.Name = "NivaaPanel"
hudPanel.AnchorPoint = Vector2.new(0.5, 0)
hudPanel.Position = UDim2.new(0.5, 0, 0, 6)
hudPanel.Size = UDim2.new(0.82, 0, 0, 78)
hudPanel.BackgroundTransparency = 1        -- gjennomsiktig felt (ingen boks)
hudPanel.BorderSizePixel = 0
hudPanel.Active = false                    -- må aldri sluke trykk over spillefeltet
hudPanel.Parent = root
local hudSize = Instance.new("UISizeConstraint")
hudSize.MaxSize = Vector2.new(320, 78)
hudSize.MinSize = Vector2.new(240, 78)
hudSize.Parent = hudPanel

-- Stor: hvilket nivå.
local levelLabel = Instance.new("TextLabel")
levelLabel.Size = UDim2.new(1, -16, 0, 36)
levelLabel.Position = UDim2.fromOffset(8, 4)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextScaled = true
levelLabel.TextColor3 = Color3.new(1, 1, 1)
levelLabel.TextXAlignment = Enum.TextXAlignment.Center
levelLabel.Text = "Level …"
levelLabel.Parent = hudPanel
local levelTsc = Instance.new("UITextSizeConstraint")
levelTsc.MaxTextSize = 30
levelTsc.MinTextSize = 16
levelTsc.Parent = levelLabel
stroke(levelLabel, Color3.fromRGB(0, 0, 0), 2, 0)     -- svart kant = lesbar på gjennomsiktig

-- Mindre: din egen beste tid.
local bestLabel = Instance.new("TextLabel")
bestLabel.Size = UDim2.new(1, -16, 0, 18)
bestLabel.Position = UDim2.fromOffset(8, 42)
bestLabel.BackgroundTransparency = 1
bestLabel.Font = Enum.Font.GothamMedium
bestLabel.TextScaled = true
bestLabel.TextColor3 = Color3.fromRGB(215, 222, 235)
bestLabel.TextXAlignment = Enum.TextXAlignment.Center
bestLabel.TextTruncate = Enum.TextTruncate.AtEnd
bestLabel.Text = "Your best: —"
bestLabel.Parent = hudPanel
local bestTsc = Instance.new("UITextSizeConstraint")
bestTsc.MaxTextSize = 14
bestTsc.MinTextSize = 10
bestTsc.Parent = bestLabel
stroke(bestLabel, Color3.fromRGB(0, 0, 0), 1.5, 0.1)

-- Mindre: ditt sekvensielle "accepted"-nivå (og for gude-spillere: rent vs gud).
local acceptedLabel = Instance.new("TextLabel")
acceptedLabel.Size = UDim2.new(1, -16, 0, 18)
acceptedLabel.Position = UDim2.fromOffset(8, 60)
acceptedLabel.BackgroundTransparency = 1
acceptedLabel.Font = Enum.Font.GothamMedium
acceptedLabel.TextScaled = true
acceptedLabel.TextColor3 = Color3.fromRGB(170, 235, 180)
acceptedLabel.TextXAlignment = Enum.TextXAlignment.Center
acceptedLabel.TextTruncate = Enum.TextTruncate.AtEnd
acceptedLabel.Text = "Accepted: —"
acceptedLabel.Parent = hudPanel
local acceptedTsc = Instance.new("UITextSizeConstraint")
acceptedTsc.MaxTextSize = 14
acceptedTsc.MinTextSize = 10
acceptedTsc.Parent = acceptedLabel
stroke(acceptedLabel, Color3.fromRGB(0, 0, 0), 1.5, 0.1)

-- Oppdater HUD-en fra en LevelInfo-nyttelast (bare level + din beste her nå;
-- rekordene vises i topp-høyre-panelet). Alt nil-sjekket.
local function updateInfo(p)
	if type(p) ~= "table" then
		return
	end
	local lvl = tonumber(p.level)
	if p.inLobby then
		levelLabel.Text = "🏠 Lobby"
	else
		levelLabel.Text = "Level " .. (lvl and tostring(lvl) or "—")
	end
	if type(p.yourBest) == "number" then
		bestLabel.Text = "Your best: " .. Medals.fmtTime(p.yourBest)
	else
		bestLabel.Text = "Your best: —"
	end
	-- Accepted-nivå. Har vi bestWithGod (kun gude-spillere), vis rent vs gud-skille.
	local acc = tonumber(p.accepted)
	if type(p.bestWithGod) == "number" then
		acceptedLabel.Text = "Clean " .. (acc or 0) .. "  ·  God " .. math.floor(p.bestWithGod)
	else
		acceptedLabel.Text = "Accepted: " .. (acc and tostring(acc) or "—")
	end
end

--==================  JOBB 2: OPPSUMMERINGS-KORT  =================--
-- Vi bygger kortet ÉN gang (skjult), og fyller det på nytt for hvert nivå du
-- fullfører. Da slipper vi å lage/rydde GUI hele tiden, og fort-etter-fort-nivå
-- bare oppdaterer det samme kortet.
local CARD_W = 400
local PAD_TOP, GAP, PAD_BOTTOM = 18, 8, 16

local card = Instance.new("Frame")
card.Name = "OppsummeringsKort"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = UDim2.fromOffset(CARD_W, 360)  -- høyden settes dynamisk i populate()
card.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
card.BorderSizePixel = 0
card.Visible = false
card.ZIndex = 5
card.Active = false                        -- kortet er ren visning; ikke sluk trykk
card.Parent = root
corner(card, 16)
stroke(card, Color3.fromRGB(80, 88, 115), 1.5, 0)
depthGradient(card, Color3.fromRGB(44, 48, 66), Color3.fromRGB(24, 26, 38))

-- Ekstra nedskalering av SELVE kortet, oppå rot-skaleringen. Rot-rammen tar seg av
-- den generelle telefon-krympingen, men kortet vokser i høyden ut fra hvor mange
-- linjer som vises, og et høyt kort kan fortsatt bli for stort for et lavt vindu.
-- Denne UIScale-en fanger nettopp det tilfellet, og lar midtstillingen
-- (AnchorPoint 0.5,0.5) stå i fred.
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local SCREEN_MARGIN = 24
local function fitCard()
	-- Alt under rot-rammen måles i DESIGN-piksler, ikke skjerm-piksler: rot-rammen er
	-- 1/scale så stor som skjermen, og UIScale krymper den ned igjen. Derfor deler vi
	-- skjermstørrelsen på skalaen før vi sammenligner med kortets egne mål. Gjør man
	-- ikke det, skrumper kortet én gang for mye på telefon.
	local vp = gui.AbsoluteSize / layout.scale
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	local h = card.Size.Y.Offset -- gjeldende korthøyde (settes i populateCard)
	if h <= 0 then
		h = 360
	end
	local sw = (vp.X - SCREEN_MARGIN) / CARD_W
	local sh = (vp.Y - SCREEN_MARGIN) / h
	cardScale.Scale = math.clamp(math.min(sw, sh), 0.5, 1)
end

-- Stor medalje-"badge": en farget sirkel med en stjerne i.
local badge = Instance.new("Frame")
badge.Name = "Medalje"
badge.AnchorPoint = Vector2.new(0.5, 0)
badge.Size = UDim2.fromOffset(96, 96)
badge.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
badge.BorderSizePixel = 0
badge.ZIndex = 6
badge.Parent = card
local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(1, 0)  -- 1,0 på en firkant = sirkel
badgeCorner.Parent = badge
stroke(badge, Color3.fromRGB(255, 255, 255), 2, 0.4)

local badgeStar = Instance.new("TextLabel")
badgeStar.Size = UDim2.fromScale(1, 1)
badgeStar.BackgroundTransparency = 1
badgeStar.Font = Enum.Font.GothamBlack
badgeStar.TextSize = 46
badgeStar.Text = "★"
badgeStar.TextColor3 = Color3.fromRGB(255, 255, 255)
badgeStar.TextTransparency = 0.15
badgeStar.ZIndex = 7
badgeStar.Parent = badge

-- Medalje-navn (Diamant/Gull/Sølv/Bronse/Fullført), i medaljens farge.
local medalName = mkLabel(card, 360, 26, 22, Enum.Font.GothamBold, Color3.fromRGB(200, 200, 200))
medalName.ZIndex = 6

-- Tittel: "Nivå N fullført!"
local title = mkLabel(card, 360, 26, 20, Enum.Font.GothamBold, Color3.new(1, 1, 1))
title.ZIndex = 6

-- Din tid.
local timeLine = mkLabel(card, 360, 26, 18, Enum.Font.GothamSemibold, Color3.fromRGB(235, 238, 245))
timeLine.ZIndex = 6

-- Din beste.
local bestLine = mkLabel(card, 360, 22, 15, Enum.Font.GothamMedium, Color3.fromRGB(205, 212, 225))
bestLine.ZIndex = 6

-- Fremhevet "Ny personlig rekord!"-pille (vises bare ved ny PB).
local pbBar = mkBar(card, 320, 26, 14, Enum.Font.GothamBold,
	Color3.fromRGB(255, 205, 60), Color3.fromRGB(50, 36, 0))
pbBar.Text = "New personal best! ⭐"
pbBar.ZIndex = 6
pbBar.Visible = false

-- Nivåets rekord (tid — navn).
local recordLine = mkLabel(card, 360, 22, 14, Enum.Font.GothamMedium, Color3.fromRGB(240, 215, 150))
recordLine.ZIndex = 6

-- Stor gull-banner ved helt ny nivå-rekord.
local banner = mkBar(card, 320, 34, 20, Enum.Font.GothamBlack,
	Color3.fromRGB(255, 200, 40), Color3.fromRGB(60, 42, 0))
banner.Text = "NEW RECORD! 🏆"
banner.ZIndex = 6
banner.Visible = false
-- Litt gull-glans på banneret.
local bannerGrad = Instance.new("UIGradient")
bannerGrad.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(240, 180, 30))
bannerGrad.Rotation = 90
bannerGrad.Parent = banner

-- Rad med de fire medalje-måltidene (Diamant/Gull/Sølv/Bronse), hver i sin farge,
-- så spilleren ser hva som må slås. Bygges én gang; tidene fylles inn per nivå.
local threshRow = Instance.new("Frame")
threshRow.Name = "Maaltider"
threshRow.AnchorPoint = Vector2.new(0.5, 0)
threshRow.Size = UDim2.fromOffset(344, 46)
threshRow.BackgroundTransparency = 1
threshRow.ZIndex = 6
threshRow.Visible = false
threshRow.Parent = card

local PILL_W, PILL_GAP = 80, 8
local threshPills = {}
for i, id in ipairs(Medals.order) do
	local disp = Medals.display[id]
	local mcol = c3(disp and disp.color)

	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromOffset(PILL_W, 40)
	pill.Position = UDim2.fromOffset((i - 1) * (PILL_W + PILL_GAP), 3)
	pill.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
	pill.BorderSizePixel = 0
	pill.ZIndex = 6
	pill.Parent = threshRow
	corner(pill, 8)
	stroke(pill, mcol, 1, 0.15)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -6, 0, 14)
	nameLbl.Position = UDim2.fromOffset(3, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 11
	nameLbl.TextColor3 = mcol
	nameLbl.TextXAlignment = Enum.TextXAlignment.Center
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = (disp and disp.name) or "?"
	nameLbl.ZIndex = 7
	nameLbl.Parent = pill

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Size = UDim2.new(1, -6, 0, 16)
	timeLbl.Position = UDim2.fromOffset(3, 20)
	timeLbl.BackgroundTransparency = 1
	timeLbl.Font = Enum.Font.GothamSemibold
	timeLbl.TextSize = 13
	timeLbl.TextColor3 = Color3.fromRGB(235, 238, 245)
	timeLbl.TextXAlignment = Enum.TextXAlignment.Center
	timeLbl.Text = "-"
	timeLbl.ZIndex = 7
	timeLbl.Parent = pill

	threshPills[id] = { frame = pill, timeLabel = timeLbl }
end

-- Fyll kortet fra en LevelComplete-nyttelast, plasser bare de synlige linjene
-- (ingen stygge hull når en jubel-linje er skjult), og juster korthøyden.
local function populateCard(p)
	if type(p) ~= "table" then
		return false
	end

	-- Medalje (håndterer "none" og ukjent/manglende medalje -> grå "Fullført").
	local mkey = medalKey(p.medal)
	local disp = Medals.display[mkey] or Medals.display.none
	local col = c3(disp.color)
	badge.BackgroundColor3 = col
	medalName.Text = disp.name or "Finished"
	medalName.TextColor3 = col

	local lvl = tonumber(p.level)
	title.Text = "Level " .. (lvl and tostring(lvl) or "—") .. " complete!"

	-- fmtTime tåler nil ("-"); alle tider går gjennom den.
	timeLine.Text = "Your time: " .. Medals.fmtTime(p.time)
	bestLine.Text = "Your best: " .. Medals.fmtTime(p.yourBest)

	local showPB = (p.isNewPB == true)
	pbBar.Visible = showPB

	-- Rekord-linje (nil-sjekket på både tabell, tid og navn).
	local rec = p.record
	if type(rec) == "table" and type(rec.time) == "number" then
		local nm = (type(rec.name) == "string" and rec.name ~= "")
			and (" — " .. rec.name) or ""
		recordLine.Text = "🏆 Record: " .. Medals.fmtTime(rec.time) .. nm
	else
		recordLine.Text = "🏆 Record: —"
	end

	local showBanner = (p.isNewRecord == true)
	banner.Visible = showBanner

	-- Måltider: bare hvis vi faktisk fikk terskler.
	local thr = p.thresholds
	local showThr = (type(thr) == "table")
	threshRow.Visible = showThr
	if showThr then
		for _, id in ipairs(Medals.order) do
			local pill = threshPills[id]
			if pill then
				local v = thr[id]
				pill.timeLabel.Text = Medals.fmtTime(type(v) == "number" and v or nil)
			end
		end
	end

	-- Vertikal flyt: plasser fra toppen og hopp over det som er skjult.
	local y = PAD_TOP
	local function place(inst, h)
		inst.Position = UDim2.new(0.5, 0, 0, y)
		y = y + h + GAP
	end
	place(badge, 96)
	place(medalName, 26)
	place(title, 26)
	place(timeLine, 26)
	place(bestLine, 22)
	if showPB then place(pbBar, 26) end
	place(recordLine, 22)
	if showBanner then place(banner, 34) end
	if showThr then place(threshRow, 46) end

	y = y - GAP + PAD_BOTTOM
	card.Size = UDim2.fromOffset(CARD_W, y)
	fitCard() -- oppdater telefon-skaleringen mot den nye korthøyden
	return true
end

-- Auto-skjul med "token"-vakt: hver ny fullføring får et nytt token, så en
-- GAMMEL nedtellings-timer aldri rekker å skjule et NYTT kort. Kommer to nivåer
-- rett etter hverandre, blir kortet bare oppdatert og timeren nullstilt.
local dismissToken = 0
local SHOW_SECONDS = 4.5

local function showComplete(p)
	if not populateCard(p) then
		return
	end
	card.Visible = true

	dismissToken += 1
	local mine = dismissToken
	task.delay(SHOW_SECONDS, function()
		if mine == dismissToken then
			card.Visible = false
		end
	end)
end

--==================  DAGLIG-BELØNNING-TOAST  ====================--
-- Liten banner som spretter opp øverst når serveren gir dagens belønning. Bygges
-- én gang (skjult), fylles på nytt hver gang. All spiller-synlig tekst er engelsk.
-- STOR, animert daglig-belønning-popup MIDT på skjermen (godt synlig = spilleren
-- ser verdien og vil komme tilbake i morgen). Spretter inn, teaser for neste dag,
-- lukker seg selv. All spiller-synlig tekst er engelsk.
local RewardTween = game:GetService("TweenService")

local rewardCard = Instance.new("Frame")
rewardCard.Name = "DagligBelonning"
rewardCard.AnchorPoint = Vector2.new(0.5, 0.5)
rewardCard.Position = UDim2.fromScale(0.5, 0.42)
rewardCard.Size = UDim2.fromOffset(360, 250)
rewardCard.BackgroundColor3 = Color3.fromRGB(30, 26, 16)
rewardCard.BorderSizePixel = 0
rewardCard.Visible = false
rewardCard.ZIndex = 30
rewardCard.Active = false                  -- ren visning; skal ikke sluke trykk
rewardCard.Parent = root
corner(rewardCard, 18)
stroke(rewardCard, Color3.fromRGB(255, 210, 90), 3, 0)
depthGradient(rewardCard, Color3.fromRGB(58, 48, 22), Color3.fromRGB(24, 20, 12))
local rewardScale = Instance.new("UIScale"); rewardScale.Scale = 1; rewardScale.Parent = rewardCard
local rewardFit = Instance.new("UISizeConstraint")
rewardFit.MaxSize = Vector2.new(380, 260); rewardFit.MinSize = Vector2.new(300, 220)
rewardFit.Parent = rewardCard

local rewardTitle = mkLabel(rewardCard, 344, 34, 26, Enum.Font.GothamBold, Color3.fromRGB(255, 224, 130))
rewardTitle.Position = UDim2.new(0.5, 0, 0, 14); rewardTitle.Text = "🎁 DAILY REWARD"; rewardTitle.ZIndex = 31

local rewardStreak = mkLabel(rewardCard, 344, 28, 20, Enum.Font.GothamBold, Color3.fromRGB(255, 150, 80))
rewardStreak.Position = UDim2.new(0.5, 0, 0, 52); rewardStreak.Text = ""; rewardStreak.ZIndex = 31

local rewardBig = mkLabel(rewardCard, 344, 50, 40, Enum.Font.GothamBold, Color3.fromRGB(255, 236, 150))
rewardBig.Position = UDim2.new(0.5, 0, 0, 88); rewardBig.Text = ""; rewardBig.ZIndex = 31

local rewardGems = mkLabel(rewardCard, 344, 30, 20, Enum.Font.GothamBold, Color3.fromRGB(120, 220, 240))
rewardGems.Position = UDim2.new(0.5, 0, 0, 140); rewardGems.Text = ""; rewardGems.ZIndex = 31

local rewardTease = mkLabel(rewardCard, 330, 46, 14, Enum.Font.GothamSemibold, Color3.fromRGB(205, 198, 175))
rewardTease.Position = UDim2.new(0.5, 0, 1, -50); rewardTease.Text = ""; rewardTease.ZIndex = 31
rewardTease.TextWrapped = true; rewardTease.TextTruncate = Enum.TextTruncate.None

local rewardToken = 0
local function showReward(p)
	if type(p) ~= "table" then return end
	local coins = tonumber(p.coins) or 0
	local gems = tonumber(p.gems) or 0
	local streak = tonumber(p.streak) or 1

	rewardStreak.Text = "🔥 DAY " .. streak .. " STREAK"
	rewardBig.Text = "+" .. coins .. " COINS"
	if gems > 0 then
		rewardGems.Text = "+" .. gems .. " GEMS 💎  weekly bonus!"
		rewardGems.Visible = true
	else
		rewardGems.Visible = false
	end
	-- Teaser: hva i morgen gir + hvor langt til 7-dagers gullbonus (må matche serveren).
	local nextCoins = 150 * math.min(streak + 1, 7)
	local toBonus = (streak % 7 == 0) and 7 or (7 - (streak % 7))
	rewardTease.Text = "Come back tomorrow: +" .. nextCoins .. " coins!   Day 7 = 💎 bonus (" .. toBonus .. " to go)"

	rewardToken += 1
	local mine = rewardToken
	rewardCard.Visible = true
	rewardScale.Scale = 0.3
	RewardTween:Create(rewardScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(6, function()
		if mine == rewardToken and rewardCard.Parent then
			local out = RewardTween:Create(rewardScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.3 })
			out.Completed:Connect(function()
				if mine == rewardToken then rewardCard.Visible = false end
			end)
			out:Play()
		end
	end)
end

--====================  SKJERM-TILPASNING  =======================--
-- Én funksjon som kjøres ved oppstart og hver gang vinduet endrer størrelse
-- (rotering av telefon, endring av vindu, delt skjerm).
local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale

	-- Rot-rammen må vokse med 1/skala, slik at rot × skala lander nøyaktig på
	-- skjermkanten. Uten dette krymper hele HUD-et inn i øvre venstre hjørne på
	-- telefon — mens det ser helt riktig ut på desktop, der skalaen er 1 og feilen
	-- dermed er usynlig.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	-- Toppfeltet er allerede skala-basert med et tak (UISizeConstraint), så det
	-- trenger ingen egen justering. Kortene måles derimot i faste piksler.
	fitCard()
end

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter
-- den ut ved enkelte respawn. Derfor kobler vi lytteren på nytt hver gang kameraet
-- byttes, i stedet for å ta vare på det aller første.
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
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

--==================  KOBLE TIL SERVERENS REMOTES  ===============--
-- Serveren lager mappa "HudRemotes" med "LevelInfo" og "LevelComplete". Vi
-- venter litt på dem uten å blokkere resten. Mangler de, står HUD-en bare med
-- "—"-verdier — den krasjer aldri. Alle handlere er pakket i pcall så en rar
-- eller ufullstendig nyttelast heller ikke kan velte noe.
task.spawn(function()
	local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
	if not hud then
		warn("[HUD] Fant ikke HudRemotes — HUD-en står tom til server-delen er inne.")
		return
	end

	local levelInfo = hud:WaitForChild("LevelInfo", 15)
	if levelInfo then
		levelInfo.OnClientEvent:Connect(function(p)
			-- Håndterer også den aller første LevelInfo som kommer etter at
			-- GUI-en finnes (serveren sender den ved innlogging og hvert nivå).
			pcall(updateInfo, p)
		end)
	end

	local levelComplete = hud:WaitForChild("LevelComplete", 15)
	if levelComplete then
		levelComplete.OnClientEvent:Connect(function(p)
			pcall(showComplete, p)
		end)
	end

	local reward = hud:WaitForChild("Reward", 15)
	if reward then
		reward.OnClientEvent:Connect(function(p)
			pcall(showReward, p)
		end)
	end
end)
