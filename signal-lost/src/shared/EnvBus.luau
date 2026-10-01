--!strict
-- EnvBus.luau — the one-way line from the environment client (Env.client) to the HUD (Hud.client).
--
-- Both LocalScripts require this ModuleScript, and every script on one client gets the same table back,
-- so a plain list of handlers is a local bus: no Instance, nothing that replicates, nothing the server
-- ever sees. The HUD draws hazard warnings and the rest line where its own layout already fits them (and
-- where check_facilitynightmare_hud already measures them) instead of a second GUI guessing where the
-- HUD's panels are. Messages:
--   "hazard" { phase = "warn" | "zone" | "burst" | "hit" | "clear", name = string,
--              seconds = the telegraph (warn), inside = boolean (zone: the player left or re-entered the ring) }
--   "rest"   { resting = boolean, source = "bench" | "idle" | nil }
-- EnvBus.new() makes a private bus (tests); the module itself is the shared one.

type Handler = (string, any) -> ()

local function newBus(): any
	local handlers: { Handler } = {}
	local lastOf: { [string]: any } = {}
	local bus = {}
	function bus.on(fn: Handler): () -> ()
		table.insert(handlers, fn)
		return function()
			local i = table.find(handlers, fn)
			if i then table.remove(handlers, i) end
		end
	end
	function bus.fire(kind: string, data: any)
		lastOf[kind] = data
		for _, fn in table.clone(handlers) do
			pcall(fn, kind, data)
		end
	end
	function bus.last(kind: string): any
		return lastOf[kind]
	end
	return bus
end

local EnvBus = newBus()
EnvBus.new = newBus

return EnvBus
