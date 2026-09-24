-- StateFeed.luau — ONE listener on a RemoteEvent, shared by every client script that needs it. Pure.
--
-- Why. Roblox queues a RemoteEvent fired at a client before any listener is connected and hands the whole
-- queue to the FIRST connection only. The server pushes the player's profile (State) at join, usually
-- before the LocalScripts have started, and the next push only comes with a plant, harvest, buy, geode or
-- code. Hud.client and Grotto.client both need that push, and Roblox does not define which LocalScript
-- starts first. With a connection each, the loser missed it: a returning player's HUD read "💎 0" and
-- "Codex 0/6" until their first click (adversarial review 2026-09-24, finding 1).
--
-- So each script asks for the feed and SUBSCRIBES; the feed is the only connection. Whichever script asks
-- first makes it, the queue goes to it, and a script that subscribes later is handed the latest payload
-- straight away (State is a full snapshot, so the latest is the whole truth). Every subscriber is called
-- through `spawn` (task.spawn in the game), each on its own thread, the way separate connections are: one
-- that errors or yields cannot hold up another.
--
-- Client only; the server never requires this. A ModuleScript runs once per client, so both LocalScripts
-- get the same `feeds` table. Dependencies are arguments (require("./X") is invalid in Roblox).
-- tests/StateFeed.spec.luau pins the rules; robloxemu/check_growacrystal_queue*.luau replay Roblox's queue
-- rule against the real scripts, in both start orders.
--
--   local feed = StateFeed.of(remotes:WaitForChild("State"), task.spawn)
--   feed:subscribe(function(state) ... end)

local StateFeed = {}

local Feed = {}
Feed.__index = Feed

-- keyed by the RemoteEvent instance (an Instance is the same reference every time it is read; a signal
-- object read off it need not be)
local feeds: { [any]: any } = {}

function StateFeed.of(remote: any, spawn: (...any) -> ...any): any
	local existing = feeds[remote]
	if existing then
		return existing
	end
	assert(type(spawn) == "function", "StateFeed.of needs a spawner (task.spawn)")
	local feed = setmetatable({ subs = {}, last = nil, spawn = spawn }, Feed)
	feeds[remote] = feed
	remote.OnClientEvent:Connect(function(...)
		local args = table.pack(...)
		feed.last = args
		-- a snapshot: a script that subscribes during this delivery gets this payload from subscribe, once
		for _, fn in table.clone(feed.subs) do
			feed.spawn(fn, table.unpack(args, 1, args.n))
		end
	end)
	return feed
end

-- fn gets every payload from now on, and the latest one right away if one has already arrived
function Feed:subscribe(fn: (...any) -> ())
	table.insert(self.subs, fn)
	local last = self.last
	if last ~= nil then
		self.spawn(fn, table.unpack(last, 1, last.n))
	end
end

return StateFeed
