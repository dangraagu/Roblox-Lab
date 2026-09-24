--!strict
-- FORK TOWER — Would You Rather Obby.
-- ALLE tunables bor her. Endre ett tall ETT sted; ingen magiske konstanter i logikken.
--
-- De rene modulene (Fork, Section, Build, Codes) leser IKKE denne globalt — cfg sendes inn
-- som argument, så de kan enhets-testes i luau-CLI uten Roblox. Server/klient krever den fra
-- ReplicatedStorage.

local Config = {}

-- ── Determinisme ────────────────────────────────────────────────────────────
-- Samme WorldSeed + samme `runSeed` (rebirth-teller) => samme SYNLIGE tårn for alle: skiltene på
-- dørene, og geometrien bak en dør man har gått gjennom.
--
-- IKKE den skjulte halvdelen. Hvilken dør som er fella, løgnlinja, tegnet innskripsjonen
-- navngir og begge traitene avgjøres av én 32-bits hemmelighet per etasje som SERVEREN trekker
-- tilfeldig, lagrer i profilen og aldri replikerer (Main.server.luau, mintSecret). Denne fila og
-- Fork.luau ligger i ReplicatedStorage, og `runSeed` er leaderstats.Rebirths + 1 — så alt som
-- avledes herfra kan klienten regne ut selv. Målt 2026-09-17: 30 av 30 feller forutsagt uten å
-- lese. Se REVIEW-4.md før du lar noe skjult avhenge av dette tallet igjen.
Config.WorldSeed = 20260909

-- ── Fysikk (Roblox-standard; brukt til å UTLEDE hvor langt et hopp rekker) ──
Config.Physics = {
	Gravity = 196.2, -- studs/s^2, Roblox default
}

Config.Jump = {
	BaseJump = 7.2, -- Humanoid.JumpHeight for en spiller UTEN traits
	MaxJumpHeight = 30, -- tak, så trait-stabling ikke skyter figuren i bane
}

Config.WalkSpeed = 16

-- ── Tårnet ──────────────────────────────────────────────────────────────────
-- Én etasje = én Fork (to dører) + én obby-seksjon. Etter Floors etasjer: toppen.
--
-- KLARERBARHETS-INVARIANTEN (asserted i Section.spec): hvert steg må klares av en spiller
-- med NULL traits. Derfor måles StepMax/GapMax mot Config.Jump.BaseJump alene, ikke mot
-- hoppet du har etter å ha samlet ti traits.
Config.Tower = {
	Floors = 10, -- 8-12 iflg. konseptet; 10 er v1

	TileSize = 9, -- kvadratisk plattform (studs)
	PlatformThickness = 1, -- serveren senterer delen PlatformThickness/2 UNDER gangflaten

	StepMin = 3.4, -- vertikal stigning pr plattform, etasje 1
	StepPerFloor = 0.2, -- vekst pr etasje
	StepMax = 5.4, -- HARDT tak. Må være <= Safety * BaseJump (= 5.76)

	GapMin = 2.0, -- horisontal kant-til-kant-avstand, etasje 1
	GapPerFloor = 0.25,
	GapMax = 6.5, -- HARDT tak. Må være <= Safety * Section.maxJumpRun(cfg)

	Safety = 0.8, -- marginen alle takene måles mot

	PlatformsMin = 5,
	PlatformsPerFloor = 0.5,
	PlatformsMax = 11,
	PenaltyExtraPlatforms = 4, -- fella gir en LENGRE seksjon, aldri et høyere steg

	HazardFromFloor = 2,
	HazardEveryNFloors = 3,
	HazardMax = 4,
	PenaltyExtraHazards = 2,

	HazardSize = 3, -- kube-kant (studs)
	HazardBite = 3, -- hvor mange studs den stikker INN over plattformtoppen
}

-- ── Forken (kjernen: hvilken av to dører er fella?) ─────────────────────────
-- Hver dør bærer nøyaktig SignsPerDoor tegn. Ett tegn — `tellKind` — er sant denne
-- etasjen, og innskripsjonen på fork-platået navngir det. `ruleInverted` snur betydningen,
-- men SIER det: innskripsjonen leses fortsatt til et entydig svar. Derfor er ingen etasje
-- et myntkast.
Config.Fork = {
	Signs = { "flame", "frost", "crack", "eye" },
	SignNames = {
		flame = "FLAMMEN",
		frost = "RIMET",
		crack = "SPREKKEN",
		eye = "ØYET",
	},
	-- HVER GLYF MÅ FINNES I ROBLOX-FONTEN. `crack` var 🪨 (U+1FAA8, Emoji 13.0) og ble tegnet som
	-- en TOM RUTE i spillet: ett av fire tegn i vokabularet innskripsjonen navngir var uleselig på
	-- døra, på platået og i HUD-en. Målt i Studio 2026-09-10 (se STUDIO.md og
	-- studio-shots/05-glyph-block-test.png): U+1FA79 (Emoji 12.0) tegnes, U+1FA9F / U+1FAA8 /
	-- U+1FAB0 (Emoji 13.0) og U+1FAE0 (Emoji 14.0) tegnes ikke. find_mojibake.py ser ikke dette —
	-- bytene er korrekt UTF-8, det er fonten som mangler bildet.
	-- 🗿 (U+1F5FF) er målt tegnet, er grå som SignColors.crack, og er stein slik SPREKKEN er stein.
	-- check_forktower.luau har lista over hver glyf noen faktisk har sett tegnet i Studio.
	SignEmoji = {
		flame = "🔥",
		frost = "❄️",
		crack = "🗿",
		eye = "👁️",
	},
	SignsPerDoor = 2,
	SignColors = {
		flame = { 255, 130, 60 },
		frost = { 130, 220, 255 },
		crack = { 200, 195, 185 },
		eye = { 200, 120, 255 },
	},

	LiarFromFloor = 4, -- før denne etasjen lyver innskripsjonen aldri
	LiarChance = 0.3, -- ... og etterpå lyver den (åpenlyst) så ofte

	-- ── Å LESE KOSTER TID ────────────────────────────────────────────────────
	-- Innskripsjonen er det ENESTE som sier noe. En ulest dør viser bare at den er en dør: ingen
	-- trait, ingen stjerner, ingen tema-farge. Det er hele fiksen på den dominerte kjernesløyfa —
	-- stjernene sto skrevet på dørene, og det gjorde «ta den sterkeste, aldri les» til den beste
	-- måten å spille på (målt: 95.1 % av frøene).
	--
	-- Men gratis informasjon er ikke et valg. Å lese er derfor en HANDLING som tar tid: du holder
	-- inne LES på fork-platået, og serveren måler tiden selv (se onReadInscription i
	-- Main.server.luau — en klient som fyrer prompten direkte får ingen rabatt).
	--
	-- TALLET ER MÅLT, IKKE SMAKT. tests/readcost.measure.luau spiller 5000 ekte frø to veier:
	-- «les hver fork og ta den trygge døra» mot «gjett, aldri les». Fella koster bare TID
	-- (PenaltyExtraPlatforms lengre, aldri brattere), en gjetter går i fella halvparten av
	-- etasjene, og de to strategiene bruker like lang tid på ti etasjer nøyaktig når en lesning
	-- koster break-even-tallet den fila regner ut. Se REVIEW-3.md for målingen.
	ReadSeconds = 1.1,

	-- Hva en ulest dør og et ulest platå viser i stedet.
	UnreadDoor = "🚪 DØR",
	UnreadInscription = "🔒 INNSKRIPSJONEN ER ULEST",
	UnreadColor = { 74, 70, 96 },
	UnreadAccent = { 150, 145, 175 },
}

-- ── Rettferdighet: tallene testene måler mot ────────────────────────────────
-- Terskler for Fork.spec. Ikke pynt: de er den operative definisjonen av «fella er
-- uleselig uten innskripsjonen».
--
-- MERK at det IKKE finnes noe «maks like sider på rad» her. Første utkast hadde et tak på 3,
-- og taket LEKKER: har fella stått til venstre tre etasjer på rad, vet du at neste er høyre,
-- gratis, uten å lese noe. Fork.spec fanget det som skjev overgangstabell. Siden er nå en ren
-- rettferdig mynt — uavhengig fra etasje til etasje — og det er nettopp derfor innskripsjonen
-- er det ENESTE som løser en fork.
Config.Fairness = {
	SideBalanceTolerance = 0.03, -- |P(felle = venstre) - 0.5|
	SerialTolerance = 0.05, -- hvor mye en betinget P(neste|historikk) får avvike fra 0.5
	SignBalanceTolerance = 0.05, -- ingen tegn-oppstilling får peke på fella
	PowerBalanceTolerance = 0.15, -- felledøra skal ikke systematisk ha bedre/verre trait
	MaxHazardCoverage = 0.4, -- andel av en plattformtopp en hindring får dekke
	MinLandingStuds = 5, -- fri landingsstripe på hver plattform (studs)
}

-- ── Traits: det du faktisk velger mellom ────────────────────────────────────
-- power = hvor mye den er verdt i Build-kortet. jump/speed = faktisk effekt på figuren.
-- theme styrer fargen og teksturen på seksjonen bak døra.
--
-- INGEN trait har negativ jump eller speed, og det er en KORREKTHETSREGEL, ikke en smakssak.
-- Section.spec beviser at hvert eneste steg klares av en spiller med BaseJump og WalkSpeed —
-- altså null traits. Ga en trait deg MINDRE enn det, ville beviset ikke lenger dekke spilleren
-- som tok den, og en etasje kunne bli uklarerbar for akkurat den builden. Serveren klemmer
-- dessuten oppover mot de samme gulvene, så selv en feilkonfigurert trait ikke kan senke deg —
-- og en trait med negativ verdi ville da vært en STILLE NO-OP, som er sin egen defekt.
-- Avveiningen i en «would you rather» ligger i fella bak døra, ikke i en straff på figuren.
Config.Traits = {
	{ id = "emberboots", label = "🔥 Glødestøvler", theme = "fire", power = 2, jump = 0.6, speed = 2, color = { 255, 110, 60 } },
	{ id = "cindercrown", label = "🔥 Askekrone", theme = "fire", power = 3, jump = 0, speed = 0, color = { 255, 160, 70 } },
	{ id = "frostgrapple", label = "❄️ Rimkrok", theme = "ice", power = 3, jump = 1.2, speed = 0, color = { 120, 220, 255 } },
	{ id = "glacierskin", label = "❄️ Breskinn", theme = "ice", power = 2, jump = 0, speed = 0, color = { 170, 230, 255 } },
	{ id = "windstep", label = "💨 Vindsteg", theme = "wind", power = 2, jump = 0.4, speed = 4, color = { 190, 255, 220 } },
	{ id = "blurcloak", label = "💨 Slørkappe", theme = "wind", power = 3, jump = 0, speed = 6, color = { 150, 240, 200 } },
	{ id = "bananacurse", label = "🍌 Bananforbannelse", theme = "troll", power = 1, jump = 0, speed = 0, color = { 250, 230, 90 } },
	{ id = "jestermark", label = "🃏 Gjøglermerket", theme = "troll", power = 4, jump = 0, speed = 3, color = { 240, 120, 200 } },
	{ id = "voidstep", label = "🌌 Tomromssteg", theme = "void", power = 4, jump = 1.6, speed = 0, color = { 150, 120, 255 } },
	{ id = "nullsigil", label = "🌌 Nullsegl", theme = "void", power = 5, jump = 0, speed = 0, color = { 110, 90, 210 } },
	{ id = "midastouch", label = "👑 Midasgrep", theme = "gold", power = 5, jump = 0, speed = 0, color = { 255, 210, 90 } },
	{ id = "gildedwings", label = "👑 Forgylte vinger", theme = "gold", power = 4, jump = 2.0, speed = 0, color = { 255, 235, 150 } },
}

-- Farge + materiale pr tema, brukt av seksjonsbyggeren på serveren.
Config.Themes = {
	fire = { color = { 200, 80, 40 }, accent = { 255, 150, 60 }, material = "Slate" },
	ice = { color = { 120, 180, 215 }, accent = { 200, 240, 255 }, material = "Ice" },
	wind = { color = { 150, 200, 175 }, accent = { 220, 255, 235 }, material = "SmoothPlastic" },
	troll = { color = { 190, 160, 60 }, accent = { 250, 230, 90 }, material = "Wood" },
	void = { color = { 60, 50, 95 }, accent = { 150, 120, 255 }, material = "Neon" },
	gold = { color = { 170, 140, 60 }, accent = { 255, 215, 100 }, material = "Metal" },
}

-- ── Build Reveal (kortet på toppen) ─────────────────────────────────────────
Config.Build = {
	SynergyMin = 3, -- så mange traits av samme tema gir synergi
	SynergyBonus = 4, -- poeng pr synergi-tema
	EmptyTitle = "Navnløs Klatrer",
	Adjectives = {
		fire = "Glødende", ice = "Frostbitt", wind = "Hvirvlende",
		troll = "Forbannet", void = "Tomroms", gold = "Forgylt",
	},
	Nouns = {
		fire = "Askevandrer", ice = "Rimvokter", wind = "Stormløper",
		troll = "Gjøgler", void = "Skyggegjenger", gold = "Kongsklatrer",
	},
	-- score >= threshold => denne sjeldenheten. Stigende; høyeste som slår til vinner.
	--
	-- Tersklene er MÅLT, ikke gjettet. Første sett (0/16/24/32/40) så rimelig ut og gjorde
	-- «Vanlig» til et dødt nivå: et ekte ti-etasjers run scorer 19-57 uansett hvordan du
	-- spiller, så ingen som kom til toppen kunne noensinne få det laveste kortet. Build.spec
	-- spiller nå 400 ekte frø tre veier (alltid sterkest, alltid svakest, alltid venstre) og
	-- krever at HVERT nivå er oppnåelig. Kvintilene i den fordelingen er 31/35/40/45.
	Rarities = {
		{ name = "Vanlig", threshold = 0, color = { 190, 195, 210 } },
		{ name = "Uvanlig", threshold = 31, color = { 120, 220, 150 } },
		{ name = "Sjelden", threshold = 36, color = { 110, 190, 255 } },
		{ name = "Episk", threshold = 41, color = { 190, 130, 255 } },
		{ name = "Legendarisk", threshold = 47, color = { 255, 200, 90 } },
	},
}

-- ── Koder (engangs pr spiller) ──────────────────────────────────────────────
Config.Codes = {
	["FORK"] = { skips = 1 },
	["TROLL"] = { skips = 1 },
	["WOULDYOURATHER"] = { skips = 2 },
	["WELCOME"] = { skips = 1 },
}

-- Et "skip" lar deg hoppe over straffe-seksjonen én gang (du beholder traiten).
Config.Skips = {
	StartSkips = 1, -- en fersk spiller får ett gratis, så første felle ikke er en vegg
	MaxSkips = 9,
}

-- ── Gamepasses (ekte IDs når de finnes; AV til da) ──────────────────────────
Config.Passes = {
	Enabled = false,
	ExtraSkip = 0,
	GoldTrail = 0,
}

-- ── Verden (per-spiller bane, som grow-a-crystal sine plots) ────────────────
Config.World = {
	LaneSpacing = 220, -- studs mellom to spilleres tårn
	MaxLanes = 24, -- GULV. Serveren tar max(dette, Players.MaxPlayers) — se claimLane.

	-- KORRIDOREN. Hver seksjons utgang blir NESTE etasjes fork-origo, så tårnets X er en
	-- tilfeldig vandring over hele runet. Uten en grense i MODELLEN vandrer et tårn inn i
	-- naboens: målt til 364 studs drift på ti etasjer (mot et 220-studs spor) og 2942 studs
	-- på 500. Section.build klemmer hvert steg mot dette tallet, målt fra banens midtlinje,
	-- og Section.check håndhever det. Å øke LaneSpacing ville bare flyttet verdien der
	-- kollisjonen kommer tilbake.
	--
	-- Section.spec beviser CorridorHalfWidth + bredeste plate/2 <= LaneSpacing/2, altså at
	-- ingen del av et tårn kan nå inn i sporet ved siden av.
	CorridorHalfWidth = 60,

	-- En Roblox-figur er ~4 studs bred. Brukt til å plassere sjekkpunktet på en plattform
	-- KLAR av hindringen som står der: sjekkpunktet var plattformens senter, og hindringen
	-- står 1.50 studs fra det — altså inni figuren. Se Section.respawn.
	CharacterHalfWidth = 2,

	LobbyPadSize = { 26, 2, 22 },
	ForkPadSize = { 26, 2, 20 },
	DoorSize = { 6, 11, 1 },
	DoorSpread = 6.5, -- +/- x fra midten av fork-platået
	DoorDepth = 8, -- z fra midten av fork-platået
	FallGrace = 70, -- studs under sjekkpunktet før du hentes tilbake
	RespawnLift = 4,
}

-- ── Takter: hva en klient får be om, hvor ofte ──────────────────────────────
-- En RemoteEvent er en knapp hvem som helst kan holde inne. Rebirth river ned og bygger opp
-- hele verdenen OG skriver til DataStore; uten en takt her tømmer én klient hele serverens
-- skrivebudsjett (60 + 10 pr spiller pr minutt) på under ett sekund, og da slutter ALLE ANDRE
-- å lagre — inkludert session-låsen, som er det som gjør en økt read-only.
Config.Limits = {
	RebirthCooldown = 3, -- sekunder mellom to rebirths fra samme spiller
	ArmSkipCooldown = 0.25, -- ArmSkip er billig, men den er fortsatt en knapp
	-- Minste tid mellom to DataStore-skriv for samme spiller. Avslutning, BindToClose og
	-- kodeinnløsning skriver alltid med én gang (force), for de MÅ lande; alt annet venter til
	-- autosave-loopen skyller.
	--
	-- Tallet er UTLEDET, ikke gjettet. Roblox gir SERVEREN 60 + 10*spillere UpdateAsync-kall i
	-- minuttet. Et gulv på S sekunder mellom to skriv fra samme spiller gir hver spiller høyst
	-- 60/S skriv i minuttet, altså 60N/S for N spillere — og 60N/S <= 60 + 10N holder for ENHVER
	-- N nøyaktig når 60/S <= 10, altså S >= 6. 6 er derfor det minste tallet som holder en full
	-- server innenfor budsjettet, med de flate 60 igjen som slakk til join, leave og BindToClose.
	-- Serveren advarer ved oppstart hvis noen senker det under 6.
	SaveMinInterval = 6,
	-- Hvor lenge en hindring er «brukt» etter at den sendte deg til sjekkpunktet. Touched
	-- fyrer mange ganger pr berøring; uten dette er hver berøring en Notice-melding til
	-- klienten og en ny teleport midt i den forrige.
	HazardCooldown = 1,
}

-- ── Lagring ─────────────────────────────────────────────────────────────────
Config.Save = {
	Enabled = true,
	Store = "ForkTower_v1",
	Leaderboard = "ForkTower_LB_v1", -- OrderedDataStore på beste build-score
	AutosaveSeconds = 20, -- fornyer også session-låsen; MÅ være < SessionLockSeconds
	SessionLockSeconds = 45,
}

-- ── Miljøet: tårnet forandrer seg mens du klatrer (EYECANDY.md) ─────────────
-- Eierens brief (2026-09-17): rikere, aldri monotont, miljøet endrer seg med fremgangen, sjeldne
-- varslede farer, og en måte å hvile på som aldri blir en utnyttelse.
--
-- Fremgangen er ETASJER KLATRET (Climb.luau): (etasje - 1) + andelen av seksjonen du står i. Et band
-- NAVNGIS av etasjenummeret HUD-en viser («ETASJE n/10») og BLANDES av den kontinuerlige verdien, så
-- chip, tittelkort og himmel aldri er uenige. Ved en fork er fremgangen NØYAKTIG etasje - 1: verden
-- foran to uleste dører avhenger av etasjenummeret og ingenting annet (REVIEW-3/REVIEW-4).
--
-- Alt her er KOSMETIKK på klienten (src/client/Ambience.client.luau). Serveren leser ikke én linje av
-- dette. Farger er {r, g, b} — EnvBands blander tall, aldri Color3.
Config.Env = {
	-- ClockTime STIGER oppover tårnet (EnvConfig.spec): en søm blander lineært, så et band med tidligere
	-- klokkeslett enn det under ville kjørt sola baklengs gjennom sømmen. Over et HOPP (rebirth fra
	-- natten på toppen til fangehullet) tar klienten den korte veien rundt midnatt (Climb.nearestClock).
	HalfLife = 0.6, -- s: hver skrevet verdi glir, også når fremgangen HOPPER (rebirth, fall-redning)
	LightingHz = 10, -- Lighting skrives høyst så ofte, og bare når en verdi endret seg
	FloorBelowRoot = 3, -- føttene står ~3 studs under HumanoidRootPart

	-- Fork-platåene (og lobby- og topp-platået) er et FRISTED: farer løper, skytes og treffer aldri
	-- der. Å lese koster Config.Fork.ReadSeconds på serverens klokke, og prisen er målt mot å aldri
	-- lese (tests/readcost.measure.luau) — en fare som slo en leser ned ville lagt til en kostnad
	-- målingen aldri priset. Radius = spillerens radius (samme som ringen), tak = et hopp på platået.
	Sanctuary = { Radius = 1.5, Ceiling = 34 },

	-- Kulissene står i to «vegger» på hver side av banen, speilet om banens midtlinje, utenfor
	-- tårnets korridor (CorridorHalfWidth + halve toppen = 75) og godt innenfor naboens.
	WallOffset = 105, -- studs fra banens midtlinje til veggens midte
	WallDepth = 30, -- veggens tykkelse i x

	Bands = {
		{
			id = "dungeon", from = 0, fade = 0,
			name = "Fangehullet", emoji = "🕯️",
			lighting = { ClockTime = 0.5, Brightness = 1.2, ExposureCompensation = 0.35,
				Ambient = { 78, 60, 52 }, OutdoorAmbient = { 64, 50, 54 },
				FogColor = { 30, 24, 32 }, FogStart = 40, FogEnd = 300 },
			atmosphere = { Density = 0.56, Offset = 0.1, Color = { 62, 48, 50 }, Decay = { 24, 18, 22 }, Glare = 0, Haze = 2.2 },
			sky = { StarCount = 0, MoonAngularSize = 4, SunAngularSize = 21 },
			bloom = { Intensity = 1.6, Size = 36, Threshold = 0.8 },
			colorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.05, TintColor = { 255, 226, 200 } },
			sunRays = { Intensity = 0, Spread = 0.5 },
			pieces = { "dungeonWalls" },
			ambient = { { kind = "bat", count = 6 } },
			weather = { kind = "embers", rate = 6 },
			hazards = {},
		},
		{
			id = "garden", from = 2, fade = 0.8,
			name = "Den gjengrodde hagen", emoji = "🌿",
			lighting = { ClockTime = 8.6, Brightness = 2.4, ExposureCompensation = 0.15,
				Ambient = { 72, 88, 62 }, OutdoorAmbient = { 112, 132, 98 },
				FogColor = { 150, 190, 140 }, FogStart = 80, FogEnd = 700 },
			atmosphere = { Density = 0.34, Offset = 0.25, Color = { 190, 220, 170 }, Decay = { 110, 150, 100 }, Glare = 0.4, Haze = 1.6 },
			sky = { StarCount = 0, MoonAngularSize = 11, SunAngularSize = 21 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.28, TintColor = { 240, 255, 225 } },
			sunRays = { Intensity = 0.22, Spread = 0.8 },
			pieces = { "gardenWalls", "farBlooms" },
			ambient = { { kind = "butterfly", count = 8 }, { kind = "firefly", count = 8 } },
			weather = { kind = "pollen", rate = 8 },
			hazards = { "bee", "seedpod" },
		},
		{
			id = "clockwork", from = 4, fade = 0.8,
			name = "Urverket", emoji = "⚙️",
			lighting = { ClockTime = 16.4, Brightness = 2.2, ExposureCompensation = 0.1,
				Ambient = { 96, 72, 44 }, OutdoorAmbient = { 120, 96, 64 },
				FogColor = { 170, 130, 80 }, FogStart = 70, FogEnd = 600 },
			atmosphere = { Density = 0.4, Offset = 0.2, Color = { 220, 180, 120 }, Decay = { 140, 96, 50 }, Glare = 0.6, Haze = 2.0 },
			sky = { StarCount = 0, MoonAngularSize = 11, SunAngularSize = 24 },
			bloom = { Intensity = 1.3, Size = 32, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.16, Saturation = 0.12, TintColor = { 255, 236, 205 } },
			sunRays = { Intensity = 0.2, Spread = 0.9 },
			pieces = { "clockworkWalls", "clockFace" },
			ambient = { { kind = "clockmoth", count = 8 } },
			weather = { kind = "sparks", rate = 10 },
			hazards = { "cog", "clockbird" },
		},
		{
			id = "storm", from = 6, fade = 0.8,
			name = "Stormen", emoji = "⛈️",
			lighting = { ClockTime = 18.7, Brightness = 1.4, ExposureCompensation = 0.05,
				Ambient = { 60, 66, 90 }, OutdoorAmbient = { 70, 80, 110 },
				FogColor = { 70, 78, 100 }, FogStart = 40, FogEnd = 420 },
			atmosphere = { Density = 0.5, Offset = 0.15, Color = { 110, 120, 150 }, Decay = { 40, 44, 66 }, Glare = 0.1, Haze = 2.4 },
			sky = { StarCount = 0, MoonAngularSize = 11, SunAngularSize = 21 },
			bloom = { Intensity = 1.1, Size = 30, Threshold = 0.88 },
			colorCorrection = { Brightness = -0.02, Contrast = 0.22, Saturation = -0.1, TintColor = { 215, 225, 255 } },
			sunRays = { Intensity = 0.05, Spread = 0.5 },
			pieces = { "stormWalls", "stormDeck" },
			ambient = { { kind = "leaf", count = 10 } },
			weather = { kind = "rain", rate = 40 },
			lightning = { everyMin = 6, everyMax = 12 },
			hazards = { "spark", "debris" },
		},
		{
			id = "observatory", from = 8, fade = 0.8,
			name = "Observatoriet", emoji = "🔭",
			lighting = { ClockTime = 23.6, Brightness = 1.0, ExposureCompensation = 0.25,
				Ambient = { 70, 64, 110 }, OutdoorAmbient = { 80, 76, 130 },
				FogColor = { 30, 26, 60 }, FogStart = 200, FogEnd = 1500 },
			atmosphere = { Density = 0.08, Offset = 0, Color = { 120, 110, 200 }, Decay = { 40, 30, 90 }, Glare = 0, Haze = 0.4 },
			sky = { StarCount = 4000, MoonAngularSize = 26, SunAngularSize = 21 },
			bloom = { Intensity = 1.8, Size = 40, Threshold = 0.78 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.18, TintColor = { 225, 220, 255 } },
			sunRays = { Intensity = 0, Spread = 0.5 },
			pieces = { "observatoryWalls", "planets" },
			ambient = { { kind = "shootingStar", count = 3 } },
			weather = { kind = "stardust", rate = 8 },
			hazards = { "meteor", "comet" },
		},
		{
			id = "crown", from = 10, fade = 0.6,
			name = "Stjernekronen", emoji = "👑",
			lighting = { ClockTime = 23.95, Brightness = 1.1, ExposureCompensation = 0.3,
				Ambient = { 96, 84, 120 }, OutdoorAmbient = { 110, 96, 140 },
				FogColor = { 24, 20, 48 }, FogStart = 300, FogEnd = 2000 },
			atmosphere = { Density = 0.02, Offset = 0, Color = { 150, 130, 220 }, Decay = { 60, 40, 110 }, Glare = 0, Haze = 0 },
			sky = { StarCount = 5000, MoonAngularSize = 11, SunAngularSize = 21 },
			bloom = { Intensity = 2.0, Size = 44, Threshold = 0.74 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.14, Saturation = 0.25, TintColor = { 255, 238, 205 } },
			sunRays = { Intensity = 0, Spread = 0.5 },
			pieces = { "galaxy", "crownRing" },
			ambient = { { kind = "shootingStar", count = 5 } },
			weather = { kind = "stardust", rate = 10 },
			hazards = {},
		},
	},

	-- Levende ting på en ring rundt kameraet (EnvBands.ambientSpawn): studs relativt til kameraet.
	Critters = {
		bat = { rMin = 40, rMax = 110, yMin = -10, yMax = 40, speedMin = 14, speedMax = 22, flock = 2 },
		butterfly = { rMin = 25, rMax = 80, yMin = -15, yMax = 25, speedMin = 4, speedMax = 7, flock = 1 },
		firefly = { rMin = 20, rMax = 70, yMin = -20, yMax = 20, speedMin = 1.5, speedMax = 3, flock = 2 },
		clockmoth = { rMin = 30, rMax = 90, yMin = -10, yMax = 35, speedMin = 8, speedMax = 12, flock = 2 },
		leaf = { rMin = 25, rMax = 90, yMin = -20, yMax = 40, speedMin = 18, speedMax = 30, flock = 2 },
		shootingStar = { rMin = 220, rMax = 420, yMin = 80, yMax = 240, speedMin = 140, speedMax = 200, flock = 1 },
	},
}

-- ── Farer: SJELDNE, varslet, én om gangen (Hazards.luau, kopiert fra +1 Jump) ──
-- Klokka går bare mens du KLATRER en seksjon (ikke på et platå, ikke mens du hviler). En fare
-- starter på skjermen, sikter på deg mens varselet løper, LÅSER commit sekunder før den kommer, og
-- treffer bare hvis du står i den røde ringen (radius hitRadius + PlayerRadius). Et treff dytter deg
-- av plattformen; serverens fall-redning setter deg tilbake på sjekkpunktet. Ingenting tapes.
-- Sjeldenheten er MÅLT i tests/Pacing.spec.luau (EYECANDY.md §3).
Config.Hazards = {
	IntervalMin = 70, -- sekunder KLATRING mellom to farer (se Pacing.spec for minutter spilt)
	IntervalMax = 110,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	KnockLift = 10, -- studs/s oppover: stiger 0.25 studs, under det minste steget (3.4)
	KnockSeconds = 0.9, -- PlatformStand så dyttet faktisk bærer
	NearMissStuds = 8,
	SpreadDegrees = 35,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	AimJitter = 1.0,
	-- ring = 2 * (hitRadius + 1.5): 6.2-6.8 studs på en 9-studs plate; ut av ringen fra midten er
	-- høyst 3.4 studs, og 4.5 er halve plata.
	Kinds = {
		bee = { speed = 20, telegraph = 3.4, commit = 1.8, pass = 2.5, hitRadius = 1.6, knock = 30, pitch = 4, pitchSpread = 12 },
		seedpod = { speed = 24, telegraph = 3.2, commit = 1.7, pass = 2.5, hitRadius = 1.8, knock = 34, pitch = 25, pitchSpread = 10 },
		cog = { speed = 42, telegraph = 3.0, commit = 1.5, pass = 2, hitRadius = 1.9, knock = 44, pitch = 0, pitchSpread = 8 },
		clockbird = { speed = 30, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.7, knock = 36, pitch = 10, pitchSpread = 12 },
		spark = { speed = 24, telegraph = 3.4, commit = 1.8, pass = 2.5, hitRadius = 1.8, knock = 40, pitch = 0, pitchSpread = 18 },
		debris = { speed = 48, telegraph = 3.0, commit = 1.5, pass = 2, hitRadius = 1.9, knock = 46, pitch = 6, pitchSpread = 8 },
		meteor = { speed = 46, telegraph = 3.0, commit = 1.5, pass = 2, hitRadius = 1.9, knock = 44, pitch = 28, pitchSpread = 8 },
		comet = { speed = 60, telegraph = 3.0, commit = 1.5, pass = 2, hitRadius = 1.9, knock = 48, pitch = 10, pitchSpread = 8 },
	},
}

-- ── Hvile: en tilstand spilleren er i, ikke en frossen verden (Rest.luau, kopiert fra +1 Jump) ──
-- Fork Tower har ingen rundeklokke, ingen raid og ingen tidsbasert rangering (leaderboardet er beste
-- build-score). Lesingen er tidsbestemt av SERVEREN og hvile rører den ikke. Hvile pauser bare
-- klientens farer: klokka FRYSES (nullstilles aldri), og all bevegelse vekker deg.
Config.Rest = {
	IdleSeconds = 20, -- stå stille så lenge og farene lar deg være (AFK-trygt)
	PendingSeconds = 8, -- en hvile-forespørsel under en fare venter så lenge (> lengste flukt + 1)
	WakeGraceSeconds = 0.4,
	RequireGrounded = true,
	WakeOnMove = true, -- Rest.validate krever det: ingen fremgang mens du hviler
	BlockWhileThreat = true, -- Rest.validate krever det: hvile er aldri en panikknapp
}

-- ── Budsjetter (lokale, per klient; MÅLT i robloxemu/check_forktower_env.luau) ──
Config.Budget = {
	MaxLocalParts = 200,
	MaxEmitters = 3,
	MaxWeatherEmitters = 2,
	MaxEmitterRate = 50, -- partikler/s summert
	MaxBeams = 8,
	MaxTrails = 6,
	MaxLights = 3,
	MaxHazards = 1,
}

-- ── Tempo: antakelsene bak «minutter spilt» (tests/PlayModel.luau, tests/Pacing.spec.luau) ──
-- Ingen telemetri ennå, så et menneske er beskrevet her i stedet for gjemt i et tall.
--   lineUp: sekunder å sikte inn hvert hopp; miss: andel hopp som bommer; recover: sekunder etter
--   at fall-redningen har satt deg tilbake; fork: sekunder på et platå (gå dit, tenke, velge) UTEN
--   lesingen; summit: sekunder på toppen før rebirth.
Config.Pacing = {
	RescuePollSeconds = 0.4, -- serverens fall-redning spør så ofte (Main.server onCharacter)
	Profiles = {
		normal = { lineUp = 1.4, miss = 0.18, recover = 1.5, fork = 6, summit = 10 },
		fast = { lineUp = 0.8, miss = 0.08, recover = 1.0, fork = 3.5, summit = 5 },
		slow = { lineUp = 2.4, miss = 0.32, recover = 2.0, fork = 10, summit = 15 },
	},
}

return Config
