--!strict
-- StateCache.luau — the last State payload the HUD received, for the other client scripts. Pure.
--
-- Roblox queues a RemoteEvent fired before any client listener is connected and hands the queue to the
-- FIRST connection. The server pushes the loaded profile at join, usually before a phone has started its
-- LocalScripts, so that push waits in the queue. A second listener on State (the wings) would race the HUD
-- for it. So Hud.client stays the ONLY listener, exactly as before the wings, and passes every payload it
-- gets to StateCache.set; src/client/Wings.client.luau reads StateCache.get every frame and never
-- connects to the remote. Client-side only: the server never requires this module.

local StateCache = {}

local latest: any = nil
local version = 0

function StateCache.set(st: any)
	if type(st) ~= "table" then
		return
	end
	latest = st
	version += 1
end

-- (payload or nil, version): the version moves on every push, so a reader can tell a new one.
function StateCache.get(): (any, number)
	return latest, version
end

return StateCache
