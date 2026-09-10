--!strict
-- FORK TOWER — Would You Rather Obby.
-- ALLE tunables bor her. Endre ett tall ETT sted; ingen magiske konstanter i logikken.
--
-- De rene modulene (Fork, Section, Build, Codes) leser IKKE denne globalt — cfg sendes inn
-- som argument, så de kan enhets-testes i luau-CLI uten Roblox. Server/klient krever den fra
-- ReplicatedStorage.

local Config = {}

-- ── Determinisme ────────────────────────────────────────────────────────────
-- Samme WorldSeed => nøyaktig samme tårn for alle. En spillers `runSeed` (rebirth-teller)
-- blandes inn, så en rebirth gir et nytt valgtre uten å røre WorldSeed.
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
	SignEmoji = {
		flame = "🔥",
		frost = "❄️",
		crack = "🪨",
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

return Config
