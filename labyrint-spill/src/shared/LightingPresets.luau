-- LightingPresets — the two lighting states, in one place, as plain data.
--
-- The server needs them (to set the world's starting state) and the client needs them (to
-- switch per player, since Lighting is global on the server and two players can be standing in
-- two different instances at once). They used to be hand-copied into both files, and the copies
-- drifted within a day: the maze copy picked up an `Ambient` value the live game never had,
-- which lifted exactly the surfaces the torch was supposed to be the only light for.
--
-- Colours are {r, g, b} 0-255, turned into Color3 where they are applied, so this module stays
-- free of Roblox API and can be tested from the luau CLI.
--
-- MAZE is not a design choice. It is the state the live server has been applying since the
-- lobby shipped, transcribed exactly; `tests/lightingpresets.spec.luau` pins it against those
-- historical values. Changing a number here changes how hard the game is to see through, so
-- treat it as a difficulty change, not as polish.

local LightingPresets = {}

LightingPresets.MAZE = {
	ClockTime = 0,
	Brightness = 1,
	-- (0,0,0) is the Roblox default and what the live game actually ran: the old server block
	-- set OutdoorAmbient and never touched Ambient. Ambient is a flat fill that fog does not
	-- attenuate, so any value above zero here is free sight in a game about not being able to
	-- see. It is written out rather than omitted because the lobby raises it and something has
	-- to put it back.
	Ambient = { 0, 0, 0 },
	OutdoorAmbient = { 20, 20, 28 },
	FogColor = { 8, 8, 12 },
	FogStart = 0,
	FogEnd = 45, -- INSTANCE_FOG; the server sends the real value per payload
	AtmosphereDensity = 0.35,
	AtmosphereHaze = 1.4,
}

LightingPresets.LOBBY = {
	ClockTime = 14.2,
	Brightness = 2.4,
	Ambient = { 96, 100, 118 },
	OutdoorAmbient = { 128, 134, 152 },
	FogColor = { 150, 158, 178 },
	FogStart = 140,
	FogEnd = 520,
	AtmosphereDensity = 0.12,
	AtmosphereHaze = 0.6,
}

-- Applied when the game is running with CONFIG.Darkness off. Without this the client would
-- black the world out while the server skips handing out torches, which is a maze nobody can
-- play — the flag is meant to give a fully lit game, not an unlit one.
LightingPresets.LIT = LightingPresets.LOBBY

return LightingPresets
