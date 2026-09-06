-- LightingClient — decides how bright the world is, per player.
--
-- Why this exists. A player on Reddit described the game as
--     "there is legit no map. its a black part that is scaled in the shape of a square"
-- and they were describing something real. In lobby mode the server applied the maze's darkness
-- once at startup and never changed it, so the hub got ClockTime 0 and black fog from 0 to 45
-- studs, and the first thing a new player ever saw was a grey slab lit by their own torch. The
-- constant LOBBY_FOG existed with the comment "the hub is bright" and was never used.
--
-- Lighting is a single global service, so the server could not have fixed this on its own: with
-- per-player instances two players are in different worlds at the same time and one server-side
-- write covers both. The client is the only place that knows which world THIS player is looking
-- at, so lighting is decided here, from the flags the server sends with every LevelInfo.
--
-- Three rules this file exists to keep, each of which was got wrong on the first attempt:
--
--   1. **Entering the maze snaps; leaving it tweens.** A 0.55 s fade INTO the maze hands the
--      player about 143 studs of sight for the first third of a second, against a settled 45 —
--      and the return door is free, so it could be farmed by walking in and out. Darkness is
--      the mechanic; it does not get to fade in.
--   2. **Nothing is applied before the first payload.** The server sets the correct starting
--      state for whichever mode it booted in. Applying a bright lobby here at load time would
--      daylight the maze on the CONFIG.UseLobby = false rollback path, where there is no lobby
--      and the player spawns straight into the maze.
--   3. **CONFIG.Darkness is honoured.** With it off the server hands out no torches, so blacking
--      the world out here would leave a pitch-black maze nobody can play.
--
-- The presets live in ReplicatedStorage.LightingPresets, shared with the server, because the two
-- hand-written copies this file started with had already drifted apart.
--
-- What this does NOT do is keep anyone honest. Lighting belongs to the client in Roblox; an
-- exploiter can set FogEnd themselves whether or not this script exists. Moving lighting here
-- costs no security that the game ever had.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Presets = require(ReplicatedStorage:WaitForChild("LightingPresets"))

-- Fog distance inside an instance. The server sends the real value with every payload; this is
-- the fallback for a server old enough not to.
local DEFAULT_INSTANCE_FOG = Presets.MAZE.FogEnd

local TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local activePreset, activeFog = nil, nil

local function apply(preset, fogEnd: number, instant: boolean)
	-- ClockTime is always set outright: tweening it plays a sunrise every time a player walks
	-- through a door, which reads as a bug rather than as a transition.
	Lighting.ClockTime = preset.ClockTime

	local goal = {
		Brightness = preset.Brightness,
		Ambient = color(preset.Ambient),
		OutdoorAmbient = color(preset.OutdoorAmbient),
		FogColor = color(preset.FogColor),
		FogStart = preset.FogStart,
		FogEnd = fogEnd,
	}
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	local atmosGoal = { Density = preset.AtmosphereDensity, Haze = preset.AtmosphereHaze }

	if instant then
		for key, value in goal do
			(Lighting :: any)[key] = value
		end
		if atmos then
			for key, value in atmosGoal do
				(atmos :: any)[key] = value
			end
		end
	else
		TweenService:Create(Lighting, TWEEN, goal):Play()
		if atmos then
			TweenService:Create(atmos, TWEEN, atmosGoal):Play()
		end
	end
end

local function applyState(preset, fogEnd: number, instant: boolean)
	activePreset, activeFog = preset, fogEnd
	apply(preset, fogEnd, instant)
end

-- The Atmosphere is built by the server (Fx.Presets.Maze) and replicates in its own time, so it
-- often does not exist yet when the first payload lands. Without this the hub keeps the maze's
-- Density 0.35 / Haze 1.4 murk while every other property is already bright. Nothing is applied
-- until a payload has told us which world we are in.
Lighting.ChildAdded:Connect(function(child)
	if child:IsA("Atmosphere") and activePreset ~= nil then
		apply(activePreset, activeFog, true)
	end
end)

local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
local levelInfo = hud and hud:WaitForChild("LevelInfo", 30)
if not levelInfo then
	-- Leave the server's own starting state alone. It is correct for whichever mode the game
	-- booted in, which is more than this script can say without a payload.
	warn("[Labyrint] LightingClient: LevelInfo never appeared; leaving the server's lighting as is.")
	return
end

local inMaze = false

levelInfo.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	-- A server old enough to send no `inLobby` is a server from before per-player instances, so
	-- treating a missing flag as the lobby is the safe read: it is the state everyone starts in.
	local nowInLobby = payload.inLobby
	if nowInLobby == nil then nowInLobby = true end

	-- CONFIG.Darkness off means no torches are handed out, so the maze must stay lit.
	local darkness = payload.darkness
	if darkness == nil then darkness = true end

	if not darkness then
		-- With the flag off the world is uniformly lit and there is no dark state to fade out
		-- of, so a transition would only ever be a flicker on the first payload. Snap.
		applyState(Presets.LIT, Presets.LIT.FogEnd, true)
		inMaze = false
		return
	end

	if nowInLobby then
		-- Coming out of the maze is the one transition that gets to fade.
		local instant = activePreset == nil
		if inMaze or activePreset == nil then
			inMaze = false
			applyState(Presets.LOBBY, Presets.LOBBY.FogEnd, instant)
		end
	else
		-- Snap. See rule 1 at the top of the file. Re-applied on every maze payload because the
		-- fog distance is per level on the shared-maze path, where it tightens as levels rise.
		inMaze = true
		applyState(Presets.MAZE, tonumber(payload.fog) or DEFAULT_INSTANCE_FOG, true)
	end
end)
