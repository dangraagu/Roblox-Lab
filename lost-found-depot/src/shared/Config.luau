--!strict
-- Config.luau — every tunable in Lost & Found Depot, in one block.
--
-- Each number has its reason in DESIGN.md §6 (and the model run behind it in design/model.luau).
-- Nothing here is secret: this file replicates to every client. The Back Room note and the code
-- table live in src/server/Secret.luau, which never leaves the server (DESIGN.md §8.2).
--
-- Pure data, requires nothing, so the luau CLI tests and Roblox load the same file.

local Config = {}

-- The date the spec was written. Any constant works: the per-session salt, not this, is what
-- makes a shift unpredictable (DESIGN.md §7.1).
Config.WorldSeed = 20260916

--============================================================================== rules (§3)

Config.Rules = {
	Letters = { "B", "E", "K", "T" },
	Conditions = 5,
	Routes = { "RED", "GREEN", "BLUE", "YELLOW", "PURPLE", "WHITE" },
	-- The six bins, by stable id. The id is server bookkeeping; players read `BinNames`.
	Bins = { "BAGS", "ELECTRONICS", "KEYS", "TOYS", "REPAIR", "CLAIMS" },
	BinNames = {
		BAGS = "BAGS & WEAR",
		ELECTRONICS = "ELECTRONICS",
		KEYS = "KEYS & WALLETS",
		TOYS = "TOYS",
		REPAIR = "REPAIR",
		CLAIMS = "CLAIMS",
	},
	LetterBin = { B = "BAGS", E = "ELECTRONICS", K = "KEYS", T = "TOYS" },
	-- The base manual: RED is claimed, condition 5 is broken.
	ClaimedRoute = "RED",
	BrokenCondition = 5,
	-- 0.25: the lowest value at which both torn clauses decide at least one item in more than 4
	-- shifts in 5 (torn-condition 88.5%, torn-letter 82.0%) [M 1].
	TornChance = 0.25,
	TornUnlockShift = 2,
	MemoUnlockShift = 3,
}

--============================================================================== catalog (§3.2)

-- 16 items, 4 per letter, each in 2 colour variants. `builder` names the Part recipe in the
-- server's BUILDERS table; Shift.missingBuilders reports any archetype without one at boot.
-- No rule reads the variant (§3.2), and nothing about an item's look depends on its tag.
Config.Catalog = {
	{ id = "backpack", name = "Backpack", letter = "B", builder = "backpack",
		colors = { { 60, 110, 190 }, { 200, 90, 60 } } },
	{ id = "sneaker", name = "Sneaker", letter = "B", builder = "sneaker",
		colors = { { 235, 235, 235 }, { 40, 40, 48 } } },
	{ id = "cap", name = "Baseball Cap", letter = "B", builder = "cap",
		colors = { { 190, 40, 50 }, { 40, 120, 70 } } },
	{ id = "scarf", name = "Scarf", letter = "B", builder = "scarf",
		colors = { { 150, 60, 160 }, { 230, 180, 60 } } },

	{ id = "phone", name = "Phone", letter = "E", builder = "phone",
		colors = { { 30, 30, 36 }, { 220, 220, 228 } } },
	{ id = "headphones", name = "Headphones", letter = "E", builder = "headphones",
		colors = { { 50, 50, 58 }, { 240, 120, 170 } } },
	{ id = "camera", name = "Camera", letter = "E", builder = "camera",
		colors = { { 45, 45, 50 }, { 170, 140, 100 } } },
	{ id = "laptop", name = "Laptop", letter = "E", builder = "laptop",
		colors = { { 170, 172, 180 }, { 40, 60, 90 } } },

	{ id = "keyring", name = "Keyring", letter = "K", builder = "keyring",
		colors = { { 210, 175, 60 }, { 180, 185, 195 } } },
	{ id = "wallet", name = "Wallet", letter = "K", builder = "wallet",
		colors = { { 110, 70, 40 }, { 30, 30, 34 } } },
	{ id = "padlock", name = "Padlock", letter = "K", builder = "padlock",
		colors = { { 200, 165, 70 }, { 150, 155, 165 } } },
	{ id = "badge", name = "ID Badge", letter = "K", builder = "badge",
		colors = { { 60, 140, 210 }, { 230, 120, 40 } } },

	{ id = "teddy", name = "Teddy Bear", letter = "T", builder = "teddy",
		colors = { { 160, 110, 60 }, { 235, 225, 210 } } },
	{ id = "toycar", name = "Toy Car", letter = "T", builder = "toycar",
		colors = { { 210, 50, 50 }, { 60, 160, 220 } } },
	{ id = "ball", name = "Beach Ball", letter = "T", builder = "ball",
		colors = { { 250, 200, 60 }, { 90, 200, 190 } } },
	{ id = "duck", name = "Rubber Duck", letter = "T", builder = "duck",
		colors = { { 250, 215, 40 }, { 240, 140, 180 } } },
}

--============================================================================== shift (§6.3)

Config.Shift = {
	Items = 30,
	TraySlots = 8, -- 2 rows x 4; the knee in [M 4]
	-- 330 s: the shortest 30-s step at which a first-timer clears stage 3 in >= 90% of shifts [M 6].
	Seconds = 330,
	-- 8 s: the smallest penalty at which a slow reader beats a guesser by >= 25% [M 5].
	MisfilePenalty = 8,
	PerfectMaxMisfiles = 3,
	IntermissionSeconds = 4,
	TimerPoll = 0.25,
	-- A picked slot refills from the cart this long after the pick, not in the same frame. Without
	-- the beat, two clicks on one item in one frame (a double tap) would carry that item AND the
	-- one the cart rolled into its place. Not in DESIGN.md §6; added at build time for §10.2's
	-- "same item picked twice" row. How it feels is a Studio question.
	RefillSeconds = 0.3,
	-- Career shift 1 only: one item whose tag matches its look, then one whose tag contradicts it.
	-- Each is { archetype id, tag, tray slot }. The answer is fixed and public (§7.2 step 4).
	Tutorial = {
		{ archetype = "teddy", variant = 1, letter = "T", cond = 2, route = "GREEN", slot = 6 },
		{ archetype = "phone", variant = 1, letter = "K", cond = 1, route = "BLUE", slot = 7 },
	},
}

--============================================================================== economy (§6.4)

Config.Economy = {
	PayFirstTry = 10,
	ComboCap = 10, -- first-try pay is PayFirstTry + min(combo, ComboCap), combo counting this sort
	PayResort = 5,
	PerfectBonus = 100,
	-- Both upgrade tracks share one ladder: level 1, 2, 3 cost 250, 800, 2000 [M 9].
	Prices = { 250, 800, 2000 },
	MaxLevel = 3,
	Carry = { 2, 3, 4, 5 }, -- by cartLevel 0..3
	WalkSpeed = { 16, 18, 20, 22 }, -- by shoesLevel 0..3
	BacklogSize = 500,
}

--============================================================================== the bay (§4, §6.2)

-- Bay-local studs: +Y up, floor top at y = 0, the pick point P at the origin, bins toward -Z, the
-- spawn toward +Z.
Config.Bay = {
	Count = 12,
	FirstX = 100,
	Pitch = 80,
	-- interior bounds
	MinX = -36,
	MaxX = 36,
	MinZ = -36,
	MaxZ = 20,
	WallHeight = 16,
	WallThickness = 1,

	-- the bin arc
	ArcRadius = 28,
	ArcFirstDegrees = 15,
	ArcStepDegrees = 30,
	BinSize = { 8, 4, 6 },
	BinPromptDistance = 6,
	BinLightBrightness = 1.2,
	BinLightRange = 10,

	-- the tray
	TrayCentre = { 0, 1.5, 6.5 },
	TraySize = { 16, 3, 6 },
	StepHeight = 1.5,
	SlotXs = { -6, -2, 2, 6 },
	FrontRowZ = 5,
	BackRowZ = 8,
	-- WHAT A TAP HITS. The item's own pieces are the tap target (a ClickDetector on the item Model),
	-- plus a low invisible tile on the tray surface under each slot, so a flat Phone or ID Badge is
	-- easy to hit and an empty slot still answers. The old fixed 3.5 x 3 x 2.5 invisible box stood
	-- above the other row's items: a tap on a visible back-row item from the bin side picked the
	-- front-row item in front of it, and the tutorial Phone took 1 tap in 40 from there. A box
	-- shaped to each item's bounds still lost 30% of pad-side taps to the air around round shapes
	-- (REVIEW-1 finding 6; robloxemu check_lostfounddepot_view.luau measures all three).
	-- The tile's height is measured, not picked: taps on visible FRONT-row items made from the pad
	-- side reach them 90.8% of the time with a 0.4-stud tile (the back row's tiles catch rays that
	-- skim the step), 98.5% at 0.2, 99.4% at 0.1 (3169 of 3187, re-measured on the final source), 100% at 0.05; every other view is 100% at all four.
	SlotTile = { 2, 0.1, 2 },
	-- Two clicks for ONE tap arriving this close together (a double tap, or the engine reporting a
	-- tap to both the item's and the tile's ClickDetector) are one pick, not a pick and a refusal.
	SamePickSeconds = 0.05,
	-- The tag floats this far above the surface its item rests on, whatever the item.
	TagAboveSurface = 3.9,
	ItemReach = 12,
	PutBackDistance = 8,
	TagMaxDistance = 40,

	-- the rest
	PadCentre = { 0, 0.5, 14 },
	PadSize = { 6, 1, 6 },
	LockerCentre = { 12, 3, 16 },
	LockerSize = { 4, 6, 2 },
	LockerPromptDistance = 6,
	DoorWidth = 8,
	DoorHeight = 10,
	DoorPromptDistance = 6,
	BackRoom = { MinX = -10, MaxX = 10, MinZ = -50, RoofY = 14 },
	-- Pressing E at the open door re-sends the note at most this often. The camera tween is 3 s, so
	-- a honest second press inside it has nothing new to show; a spammed one was a DataStore write
	-- and a 592-byte payload per press (REVIEW-1 R1-4).
	SceneCooldownSeconds = 3,

	-- 2 studs of forgiveness on every server-side reach check (§6.2).
	ReachSlack = 2,
	-- The engine places a root part at a SpawnLocation's top face + 2.51 (SPAWN-ORDER.md §2); the
	-- re-place uses +3 so it is never placed inside the pad.
	PlaceAbovePad = 3,
	CharacterWaitFrames = 300,
	-- No collidable fixture inside a bay may have a top face above this (§4.2).
	MaxStandableTop = 6,
	MaxPartsPerBay = 120,
}

Config.BreakRoom = {
	HalfSize = 20,
	WallHeight = 16,
}

--============================================================================== look (§13.2)

Config.Colors = {
	Route = {
		RED = { 255, 90, 90 },
		GREEN = { 80, 220, 110 },
		BLUE = { 110, 170, 255 },
		YELLOW = { 255, 215, 60 },
		PURPLE = { 200, 130, 255 },
		WHITE = { 245, 245, 245 },
	},
	TagBackground = { 34, 36, 42 },
	TagBorder = { 214, 186, 120 },
	TagText = { 245, 245, 245 },
	Torn = { 150, 150, 160 },
	BinSteel = { 118, 124, 134 },
	SignBoard = { 28, 30, 36 },
	SignText = { 245, 245, 245 },
	Floor = { 150, 146, 138 },
	Wall = { 196, 190, 176 },
	Tray = { 120, 92, 64 },
	Locker = { 70, 110, 150 },
	Door = { 86, 60, 40 },
	Brass = { 210, 170, 70 },
}

--============================================================================== persistence (§6.5)

Config.Save = {
	Enabled = true,
	Store = "LostFoundDepot_v1",
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
	-- A load or a leave-time release that raises is tried this many times, waiting 1 s, then 2 s,
	-- between attempts. One transient DataStore error used to drop a veteran into the tutorial with
	-- 0 cash for the whole session (REVIEW-1 R1-3).
	Attempts = 3,
	-- BindToClose waits at most this long for release saves already in flight (Roblox allows 30).
	CloseWaitSeconds = 25,
}

-- At most one State payload per this many seconds answers a burst of Select events; the first one
-- after a quiet moment is answered at once. 10,000 Selects in one frame used to send 9,999 full
-- State payloads, 14.4 MB (REVIEW-1 R1-5).
Config.Remotes = {
	SelectPushSeconds = 0.1,
	-- EVERY STATE-CHANGING IN-WORLD ACTION (pick, put back, deposit, buy) spends one token from a
	-- per-player bucket that holds ActionBurst and refills ActionsPerSecond. Each accepted action
	-- sends a State payload and can build Parts in the shared workspace; only Select was throttled,
	-- and 10,000 pick + put-back pairs in one frame were 20,000 payloads (17.9 MB) and 80,000
	-- Instance.new calls (REVIEW-1 pass 3, exploit finding 1). A player tapping five items in a
	-- frame and putting one back is 6; a brisk put-back-and-re-pick every quarter second is 4 per
	-- second, which never runs dry.
	ActionBurst = 10,
	ActionsPerSecond = 5,
	-- Refusals and info toasts: the same text again within NoticeRepeatSeconds is not re-sent (the
	-- toast on screen already says it), and at most NoticeBurst of them go out at once, refilling
	-- NoticesPerSecond. A deposit's "+11", a misfile and a Perfect Shift are never held back; the
	-- action bucket already bounds them. 10,000 Redeem "NOPE" events used to be 10,000 toasts.
	NoticeRepeatSeconds = 0.05,
	NoticeBurst = 6,
	NoticesPerSecond = 3,
}

Config.Codes = {
	RedeemCooldown = 2,
	MaxLength = 20,
}

return Config
