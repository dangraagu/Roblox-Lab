--!strict
-- ClientBus.luau — how the two client scripts talk. Client-only in use; pure; no Roblox.
--
-- Hud.client owns every 2D control (so one layout decides where everything goes and hudcheck measures
-- it all); Lab.client owns the 3D world, the hazards and the Break rules. A ModuleScript required by two
-- LocalScripts on one client is ONE table, so this is a shared mailbox:
--   Lab -> Hud:  "hazard" { active, text, clear }, "rest" { resting, pending }, "card" { title, sub, celebrate }
--   Hud -> Lab:  "breakPressed", "overlay" { open, station }, and every "roomState", "profile" and
--                "notice" payload the server sent (Hud is the one script that listens to the remotes)
-- `last` keeps the newest payload per name, so a script that loads second still sees the current state.
-- It carries nothing the server did not already send this client; it never touches a remote.

local ClientBus = {}

local handlers: { [string]: { (any) -> () } } = {}
local lastPayload: { [string]: any } = {}

function ClientBus.on(name: string, fn: (any) -> ())
	local list = handlers[name]
	if list == nil then
		list = {}
		handlers[name] = list
	end
	table.insert(list, fn)
end

function ClientBus.fire(name: string, payload: any)
	lastPayload[name] = payload
	for _, fn in table.clone(handlers[name] or {}) do
		fn(payload)
	end
end

function ClientBus.last(name: string): any
	return lastPayload[name]
end

return ClientBus
