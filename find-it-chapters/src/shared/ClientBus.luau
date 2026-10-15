--!strict
-- ClientBus.luau — how the client scripts talk. Client-only in use; pure; no Roblox. Copied verbatim in
-- behaviour from escape-room-lab/src/shared/ClientBus.luau; only this header names this game's scripts.
--
-- Hud.client owns every 2D control (so one layout decides where everything goes and hudcheck measures
-- it all); Room.client owns the 3D room, the taps on props, the bands, the hazards and the Pause rules.
-- A ModuleScript required by two LocalScripts on one client is ONE table, so this is a shared mailbox:
--   Room -> Hud: "select" { prop }, "hazard" { active, text, clear }, "rest" { resting, pending }, "toast", "found"
--   Hud -> Room: "pausePressed", "searchPressed", "chip" { item }, and every "room", "state", "result",
--                "hint", "profile" and "notice" payload the server sent (Hud is the one script on the remotes)
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
