--!strict
-- ClientClock.luau — the client's copy of the server clock (DESIGN.md §2.1).
--
-- The server writes workspace ServerNow once a second. A client extrapolates from the last value it saw by
-- the local tick() difference, at most `maxAhead` seconds, so a stalled server never lets it run ahead.
-- `extrapolate` is pure; `attach` wires it to the workspace attribute (client scripts only).

local ClientClock = {}

function ClientClock.extrapolate(serverNow: number, receivedAt: number, nowTick: number, maxAhead: number): number
	return serverNow + math.clamp(nowTick - receivedAt, 0, maxAhead)
end

-- -> now(): the extrapolated server clock. Falls back to os.time() until the first broadcast arrives.
function ClientClock.attach(ws: Instance, maxAhead: number): () -> number
	local last: number? = nil
	local at = tick()
	local function seen()
		local v = ws:GetAttribute("ServerNow")
		if type(v) == "number" then
			last = v
			at = tick()
		end
	end
	seen()
	ws:GetAttributeChangedSignal("ServerNow"):Connect(seen)
	return function(): number
		if last == nil then
			seen()
		end
		if last == nil then return os.time() end
		return ClientClock.extrapolate(last :: number, at, tick(), maxAhead)
	end
end

return ClientClock
