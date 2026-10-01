-- Calm.luau — "fewer flashes": one switch for every client script of this game. CLIENT ONLY (the server never
-- requires it and never hears of it).
--
-- Two ways to turn our flashes off:
--   * Roblox's own Reduced Motion setting, GuiService.ReducedMotionEnabled, read through pcall every time it is
--     asked (so it switches live). The property's name is from the Roblox API as known here and is NOT verified in
--     Studio: an engine without it reads as "off" (EYECANDY.md, Studio list);
--   * the in-game ⚡ toggle in the safehouse (owner decision 2026-09-30, "take the recommended option"), for players
--     who never open Roblox's settings, and as the safety net if the property's name is wrong.
-- What "calm" turns off: lightning (no flash, bolt or grade boost; the rain and the windows stay), a knock's screen
-- flash and shake, the Blood Moon card's flash and FOV punch, the hazard warning's blinking (it holds steady), and the
-- HUD's own one-off effects (the flash and shake when CAUGHT, the flash when EVICTED, the FOV punch on EXTRACTED, the
-- shake when SPOTTED).
--
-- A ModuleScript is shared by every LocalScript of one client, so Haunt.client (which owns the toggle) and
-- Hud.client read the same switch. Nothing is saved or sent: the toggle lasts the session.

local Calm = {}

Calm.toggled = false -- the in-game ⚡ toggle: true = flashes off

function Calm.reducedMotion(): boolean
	local ok, on = pcall(function()
		return (game:GetService("GuiService") :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- true = no flashes, no shakes, no punches
function Calm.on(): boolean
	return Calm.toggled or Calm.reducedMotion()
end

return Calm
