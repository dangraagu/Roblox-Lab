-- LightingClient — decides how bright the world is, per player, on the client.
--
-- Why this exists. A player on Reddit described the game as
--     "there is legit no map. its a black part that is scaled in the shape of a square"
-- and they were describing something real. In lobby mode the server applied the maze's
-- darkness preset once at startup and never changed it: ClockTime 0, Ambient (15,15,20),
-- black fog from 0 to 45 studs, plus the Maze atmosphere at Density 0.35 / Haze 1.4. The
-- lobby got the same treatment as the maze, so the first thing a new player ever saw was a
-- grey slab lit by their own torch and nothing else. The constant LOBBY_FOG = 90 existed with
-- the comment "the hub is bright" but was never actually used anywhere.
--
-- Lighting is a single global service, so the server could not have fixed this properly on
-- its own: with per-player instances, two players are in different places at the same time
-- and one server-side write covers both. The client is the only place that knows which world
-- THIS player is looking at, so lighting is decided here, from the `inLobby` flag the server
-- already sends with every LevelInfo.
--
-- The maze preset is a deliberate copy of what the server used to apply. Darkness is the
-- game's core mechanic and this change must not make the maze any easier to see through.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Fog distance in the instances. The server sends this with LevelInfo; this is the fallback
-- for an older server that does not.
local DEFAULT_INSTANCE_FOG = 45

local LOBBY = {
	ClockTime = 14.2,
	Brightness = 2.4,
	Ambient = Color3.fromRGB(96, 100, 118),
	OutdoorAmbient = Color3.fromRGB(128, 134, 152),
	FogColor = Color3.fromRGB(150, 158, 178),
	FogStart = 140,
	FogEnd = 520,
	AtmosphereDensity = 0.12,
	AtmosphereHaze = 0.6,
}

local MAZE = {
	ClockTime = 0,
	Brightness = 1,
	Ambient = Color3.fromRGB(15, 15, 20),
	OutdoorAmbient = Color3.fromRGB(20, 20, 28),
	FogColor = Color3.fromRGB(8, 8, 12),
	FogStart = 0,
	FogEnd = DEFAULT_INSTANCE_FOG,
	AtmosphereDensity = 0.35,
	AtmosphereHaze = 1.4,
}

local TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function atmosphere(): Atmosphere?
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	return a
end

-- ClockTime is set outright rather than tweened: tweening it plays a two-second sunrise every
-- time a player walks through a door, which reads as a bug rather than as a transition.
local function apply(preset, fogEnd: number)
	Lighting.ClockTime = preset.ClockTime

	local goal = {
		Brightness = preset.Brightness,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		FogColor = preset.FogColor,
		FogStart = preset.FogStart,
		FogEnd = fogEnd,
	}
	TweenService:Create(Lighting, TWEEN, goal):Play()

	local a = atmosphere()
	if a then
		TweenService:Create(a, TWEEN, {
			Density = preset.AtmosphereDensity,
			Haze = preset.AtmosphereHaze,
		}):Play()
	end
end

-- Everyone spawns in the lobby, so that is the state to start in. If LevelInfo never arrives
-- the player is left with a hub they can see, which is the right way to fail.
local activePreset, activeFog = LOBBY, LOBBY.FogEnd
apply(activePreset, activeFog)

-- The Atmosphere is built by the server (Fx.Presets.Maze) and replicates in its own time, so
-- the first apply above usually runs before it exists. Without this the hub keeps the maze's
-- Density 0.35 / Haze 1.4 murk even though every other lighting property is already bright.
Lighting.ChildAdded:Connect(function(child)
	if child:IsA("Atmosphere") then
		apply(activePreset, activeFog)
	end
end)

local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
if not hud then
	warn("[Labyrint] LightingClient: HudRemotes never appeared; staying on the lobby preset.")
	return
end

local levelInfo = hud:WaitForChild("LevelInfo", 30)
if not levelInfo then
	warn("[Labyrint] LightingClient: LevelInfo never appeared; staying on the lobby preset.")
	return
end

local inLobby = true

levelInfo.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	-- An older server sends no `inLobby` at all. Falling back to "in the maze" would black out
	-- the hub again, which is the exact bug this file exists to fix, so treat a missing flag as
	-- the lobby.
	local nowInLobby = payload.inLobby
	if nowInLobby == nil then nowInLobby = true end

	local fog = tonumber(payload.fog) or DEFAULT_INSTANCE_FOG

	if nowInLobby then
		if not inLobby then
			inLobby = true
			activePreset, activeFog = LOBBY, LOBBY.FogEnd
			apply(activePreset, activeFog)
		end
	else
		-- Re-apply on every maze payload even when we were already in a maze: the fog distance
		-- is per level, so it can change without the lobby flag changing.
		inLobby = false
		activePreset, activeFog = MAZE, fog
		apply(activePreset, activeFog)
	end
end)
