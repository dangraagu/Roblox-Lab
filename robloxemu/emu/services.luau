--!nolint LocalShadow
-- services.luau — the objects behind `game:GetService(name)` for robloxemu.
--
-- Datatypes arrive by DEPENDENCY INJECTION (never require emu/datatypes.luau from here):
--
--     local ServicesLib = require("./services")
--     local svc = ServicesLib.new({ datatypes = <datatypes table>, instance = <instance api> })
--     local game, workspace = svc.game, svc.workspace
--
-- `instance` is optional — if the harness does not pass one, this module builds its own from
-- ./instance (our own file, so no cross-agent race).
--
-- The single most important thing in this file is UpdateAsync. Roblox semantics, encoded
-- exactly, because our session-lock bug class lives here:
--   * the transform receives the CURRENT stored value (a fresh deserialized copy),
--   * returning nil ABORTS the write and leaves the stored value untouched,
--   * the transform MAY BE INVOKED MORE THAN ONCE — `store.__retryCount = N` forces N extra
--     invocations so a test can prove the caller's flags (`wrote`, `applied`, ...) are reset
--     per attempt and that mutations from a discarded attempt never leak.
-- Failure injection: `store.__failNext = true` (one call) / `store.__failAll = true` (until
-- cleared) makes DataStore calls raise, which is how the "load failed -> canSave = false"
-- path gets tested.

local ServicesLib = {}

-- ---------------------------------------------------------------- JSON (pure, no deps)
-- Used by HttpService AND by the DataStore write path: Roblox stores JSON, so a
-- round-trip on every write faithfully reproduces the traps (integer keys come back as
-- STRING keys; functions/instances are rejected).
local JSON_ESCAPE = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function jsonQuote(s: string): string
	local out = string.gsub(s, '[%c"\\]', function(c)
		return JSON_ESCAPE[c] or string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. out .. '"'
end

local function jsonEncode(value): string
	local buf = {}
	local seen = {}
	local function enc(v)
		local t = type(v)
		if v == nil then
			table.insert(buf, "null")
		elseif t == "boolean" then
			table.insert(buf, tostring(v))
		elseif t == "number" then
			local num = v :: number
			if num ~= num or num == math.huge or num == -math.huge then
				error("JSONEncode: cannot encode non-finite number", 0)
			end
			if num % 1 == 0 and math.abs(num) < 2 ^ 53 then
				table.insert(buf, string.format("%d", num))
			else
				table.insert(buf, string.format("%.14g", num))
			end
		elseif t == "string" then
			table.insert(buf, jsonQuote(v :: string))
		elseif t == "table" then
			if seen[v] then
				error("JSONEncode: cannot encode a table with cycles", 0)
			end
			seen[v] = true
			local count, isArray = 0, true
			for k in v do
				count += 1
				if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then
					isArray = false
				end
			end
			if isArray and count ~= #v then
				isArray = false -- sparse: Roblox falls back to an object with string keys
			end
			if isArray then
				table.insert(buf, "[")
				for i = 1, count do
					if i > 1 then
						table.insert(buf, ",")
					end
					enc(v[i])
				end
				table.insert(buf, "]")
			else
				table.insert(buf, "{")
				local first = true
				for k, val in v do
					local kt = type(k)
					if kt ~= "string" and kt ~= "number" then
						error("JSONEncode: table keys must be strings or numbers, got " .. kt, 0)
					end
					if not first then
						table.insert(buf, ",")
					end
					first = false
					table.insert(buf, jsonQuote(tostring(k)))
					table.insert(buf, ":")
					enc(val)
				end
				table.insert(buf, "}")
			end
			seen[v] = nil
		else
			error("JSONEncode: cannot encode a value of type " .. t, 0)
		end
	end
	enc(value)
	return table.concat(buf)
end

local function jsonDecode(str: string)
	if type(str) ~= "string" then
		error("JSONDecode: expected a string, got " .. typeof(str), 0)
	end
	local pos = 1
	local n = #str
	local function fail(msg)
		error(string.format("JSONDecode: %s at position %d", msg, pos), 0)
	end
	local function skip()
		while pos <= n do
			local c = string.sub(str, pos, pos)
			if c == " " or c == "\t" or c == "\n" or c == "\r" then
				pos += 1
			else
				break
			end
		end
	end
	local function parseString(): string
		pos += 1 -- opening quote
		local buf = {}
		while true do
			if pos > n then
				fail("unterminated string")
			end
			local c = string.sub(str, pos, pos)
			if c == '"' then
				pos += 1
				break
			elseif c == "\\" then
				local e = string.sub(str, pos + 1, pos + 1)
				pos += 2
				if e == "n" then
					table.insert(buf, "\n")
				elseif e == "t" then
					table.insert(buf, "\t")
				elseif e == "r" then
					table.insert(buf, "\r")
				elseif e == "b" then
					table.insert(buf, "\b")
				elseif e == "f" then
					table.insert(buf, "\f")
				elseif e == "u" then
					local cp = tonumber(string.sub(str, pos, pos + 3), 16)
					pos += 4
					table.insert(buf, utf8.char(cp or 63))
				else
					table.insert(buf, e)
				end
			else
				table.insert(buf, c)
				pos += 1
			end
		end
		return table.concat(buf)
	end
	local parseValue
	local function parseArray()
		pos += 1
		local out = {}
		skip()
		if string.sub(str, pos, pos) == "]" then
			pos += 1
			return out
		end
		while true do
			table.insert(out, parseValue())
			skip()
			local c = string.sub(str, pos, pos)
			pos += 1
			if c == "]" then
				break
			elseif c ~= "," then
				fail("expected ',' or ']'")
			end
			skip()
		end
		return out
	end
	local function parseObject()
		pos += 1
		local out = {}
		skip()
		if string.sub(str, pos, pos) == "}" then
			pos += 1
			return out
		end
		while true do
			skip()
			if string.sub(str, pos, pos) ~= '"' then
				fail("expected an object key")
			end
			local key = parseString()
			skip()
			if string.sub(str, pos, pos) ~= ":" then
				fail("expected ':'")
			end
			pos += 1
			out[key] = parseValue()
			skip()
			local c = string.sub(str, pos, pos)
			pos += 1
			if c == "}" then
				break
			elseif c ~= "," then
				fail("expected ',' or '}'")
			end
		end
		return out
	end
	parseValue = function()
		skip()
		local c = string.sub(str, pos, pos)
		if c == "{" then
			return parseObject()
		elseif c == "[" then
			return parseArray()
		elseif c == '"' then
			return parseString()
		elseif string.sub(str, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(str, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(str, pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local s, e = string.find(str, "^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
		if not s then
			fail("unexpected character '" .. tostring(c) .. "'")
		end
		local num = tonumber(string.sub(str, s :: number, e :: number))
		if num == nil then
			fail("malformed number")
		end
		pos = (e :: number) + 1
		return num
	end
	local v = parseValue()
	skip()
	return v
end

ServicesLib.jsonEncode = jsonEncode
ServicesLib.jsonDecode = jsonDecode

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in v do
		out[k] = deepCopy(val)
	end
	return out
end

-- ---------------------------------------------------------------- DataStore
local DataStore = {}
DataStore.__index = DataStore

local OrderedDataStore = setmetatable({}, { __index = DataStore })
OrderedDataStore.__index = OrderedDataStore

local function newStore(name: string, scope: string?, ordered: boolean?)
	local store = {
		__name = name,
		__scope = scope or "global",
		__ordered = ordered == true,
		__data = {}, -- key -> stored value (already JSON-normalised)
		__calls = 0, -- diagnostics: how many API calls this store served
		-- FAILURE INJECTION
		__failNext = false, -- next call raises, then clears itself
		__failAll = false, -- every call raises until cleared
		__failMessage = nil, -- optional custom message
		-- RETRY INJECTION: extra UpdateAsync transform invocations (0 = Roblox's happy path)
		__retryCount = 0,
		-- JSON round-trip on write (Roblox does; set false to store raw Lua tables)
		__serialize = true,
	}
	return setmetatable(store, ordered and OrderedDataStore or DataStore)
end

function DataStore:__gate(what: string)
	self.__calls += 1
	if self.__failAll or self.__failNext then
		local msg = self.__failMessage
			or string.format("robloxemu: injected DataStore failure in %s (%s)", what, tostring(self.__name))
		self.__failNext = false
		error(msg, 0)
	end
end

local function assertKey(key)
	if type(key) ~= "string" then
		error("DataStore key must be a string, got " .. typeof(key), 0)
	end
	if #key == 0 or #key > 50 then
		error(string.format("DataStore key length must be between 1 and 50 (got %d)", #key), 0)
	end
end

-- Roblox persists JSON. Round-tripping on write reproduces its coercions (notably: integer
-- table keys come back as STRINGS) and rejects anything unserialisable, instead of letting a
-- Lua-only value survive in memory and explode in production.
function DataStore:__normalize(value)
	if value == nil then
		return nil
	end
	if not self.__serialize then
		return deepCopy(value)
	end
	local ok, encoded = pcall(jsonEncode, value)
	if not ok then
		error("103: Cannot store value in data store. " .. tostring(encoded), 0)
	end
	return jsonDecode(encoded)
end

function DataStore:GetAsync(key)
	self:__gate("GetAsync")
	assertKey(key)
	return deepCopy(self.__data[key])
end

function DataStore:SetAsync(key, value)
	self:__gate("SetAsync")
	assertKey(key)
	self.__data[key] = self:__normalize(value)
	return key
end

function DataStore:RemoveAsync(key)
	self:__gate("RemoveAsync")
	assertKey(key)
	local old = self.__data[key]
	self.__data[key] = nil
	return deepCopy(old)
end

function DataStore:IncrementAsync(key, delta)
	self:__gate("IncrementAsync")
	assertKey(key)
	local n = (tonumber(self.__data[key]) or 0) + (tonumber(delta) or 1)
	self.__data[key] = n
	return n
end

-- THE contract (SPEC.md hard rule 4).
--   * transform(current) -> new value, committed;
--   * transform(current) -> nil, the write is ABORTED and the stored value is untouched;
--   * transform MAY RUN MORE THAN ONCE (`__retryCount` extra runs). Every run gets a FRESH
--     copy of the stored value, so mutations made during a discarded run cannot survive —
--     which is exactly what makes a non-idempotent transform fail here instead of in prod.
--   * returns the committed value, or nil when aborted.
function DataStore:UpdateAsync(key, transform)
	self:__gate("UpdateAsync")
	assertKey(key)
	if type(transform) ~= "function" then
		error("UpdateAsync: transformFunction must be a function, got " .. typeof(transform), 0)
	end
	local extra = math.floor(tonumber(self.__retryCount) or 0)
	if extra < 0 then
		extra = 0
	end
	local committed = nil
	for _ = 1, 1 + extra do
		local current = deepCopy(self.__data[key])
		local returned = transform(current)
		committed = returned -- only the LAST invocation decides
	end
	if committed == nil then
		return nil -- aborted: stored value unchanged
	end
	local stored = self:__normalize(committed)
	self.__data[key] = stored
	return deepCopy(stored)
end

-- Ordered stores only take integers, and that constraint is worth enforcing: a float here
-- silently fails in Roblox and the leaderboard just never updates.
function OrderedDataStore:SetAsync(key, value)
	self:__gate("SetAsync")
	assertKey(key)
	local num = tonumber(value)
	if num == nil or num % 1 ~= 0 then
		error("OrderedDataStore values must be integers, got " .. tostring(value), 0)
	end
	self.__data[key] = num
	return key
end

local Pages = {}
Pages.__index = Pages

function Pages:GetCurrentPage()
	return deepCopy(self.__pages[self.__page] or {})
end

function Pages:AdvanceToNextPageAsync()
	if self.IsFinished then
		return
	end
	self.__page += 1
	self.IsFinished = self.__page >= #self.__pages
end

function OrderedDataStore:GetSortedAsync(ascending, pageSize, minValue, maxValue)
	self:__gate("GetSortedAsync")
	local size = math.max(1, math.floor(tonumber(pageSize) or 50))
	local entries = {}
	for k, v in self.__data do
		if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
			table.insert(entries, { key = k, value = v })
		end
	end
	table.sort(entries, function(a, b)
		if a.value == b.value then
			return a.key < b.key -- stable, deterministic tie-break
		end
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	local pages = {}
	local page = {}
	for _, e in entries do
		table.insert(page, e)
		if #page >= size then
			table.insert(pages, page)
			page = {}
		end
	end
	if #page > 0 or #pages == 0 then
		table.insert(pages, page)
	end
	return setmetatable({ __pages = pages, __page = 1, IsFinished = #pages <= 1 }, Pages)
end

-- ---------------------------------------------------------------- factory
function ServicesLib.new(deps)
	deps = deps or {}
	local dt = deps.datatypes or {}
	local inst = deps.instance or (require("./instance") :: any).new(deps)

	local Instance = inst.Instance
	local create = inst.create
	local defineClass = inst.defineClass
	local fireIfExists = inst.fireIfExists
	local stateOf = inst.stateOf
	local isA = inst.isA

	local function try(fn, ...)
		local ok, v = pcall(fn, ...)
		if ok then
			return v
		end
		return nil
	end

	-- ------------------------------------------------------------ Players
	defineClass("Players", {
		parent = "Instance",
		events = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
		defaults = { MaxPlayers = 12, LocalPlayer = nil, CharacterAutoLoads = true },
		init = function(self)
			rawset(self, "__nextUserId", 1000)
		end,
		methods = {
			GetPlayers = function(self)
				local out = {}
				for _, c in stateOf(self).children do
					if isA(c, "Player") then
						table.insert(out, c)
					end
				end
				return out
			end,
			GetPlayerFromCharacter = function(self, character)
				if character == nil then
					return nil
				end
				for _, c in stateOf(self).children do
					if isA(c, "Player") and stateOf(c).props.Character == character then
						return c
					end
				end
				return nil
			end,
			GetPlayerByUserId = function(self, userId)
				for _, c in stateOf(self).children do
					if isA(c, "Player") and stateOf(c).props.UserId == userId then
						return c
					end
				end
				return nil
			end,
			GetNameFromUserIdAsync = function(self, userId)
				for _, c in stateOf(self).children do
					if isA(c, "Player") and stateOf(c).props.UserId == userId then
						return stateOf(c).props.Name
					end
				end
				return "User_" .. tostring(userId)
			end,
			GetUserIdFromNameAsync = function(self, name)
				for _, c in stateOf(self).children do
					if isA(c, "Player") and stateOf(c).props.Name == name then
						return stateOf(c).props.UserId
					end
				end
				return 0
			end,

			-- TEST HOOK: a player joins. Parented to the Players service, so the real server's
			-- ghost-session guard (`plr.Parent ~= Players`) sees exactly what Roblox shows it.
			simulateJoin = function(self, name, userId)
				local nextId = rawget(self, "__nextUserId") or 1000
				if userId == nil then
					userId = nextId
				end
				rawset(self, "__nextUserId", math.max(nextId, userId) + 1)
				local plr = create("Player")
				plr.Name = name or ("Player" .. tostring(userId))
				plr.UserId = userId
				plr.Parent = self
				fireIfExists(self, "PlayerAdded", plr)
				return plr
			end,

			-- TEST HOOK: a player leaves. PlayerRemoving fires while the player is STILL
			-- parented to Players (Roblox order), then the player is unparented.
			simulateLeave = function(self, plr)
				if plr == nil then
					return
				end
				fireIfExists(self, "PlayerRemoving", plr)
				plr.Parent = nil
			end,

			-- TEST HOOK: give a player a minimal character (Humanoid + HumanoidRootPart) and
			-- fire CharacterAdded, so server code that teleports the root part has something
			-- real to move.
			simulateSpawn = function(self, plr, parent)
				local char = create("Model")
				char.Name = stateOf(plr).props.Name
				local hrp = create("Part")
				hrp.Name = "HumanoidRootPart"
				hrp.Parent = char
				local hum = create("Humanoid")
				hum.Parent = char
				char.PrimaryPart = hrp
				if parent ~= nil then
					char.Parent = parent
				end
				plr.Character = char
				fireIfExists(plr, "CharacterAdded", char)
				return char
			end,
		},
	})

	-- ------------------------------------------------------------ DataStoreService
	defineClass("DataStoreService", {
		parent = "Instance",
		init = function(self)
			rawset(self, "__stores", {})
		end,
		methods = {
			GetDataStore = function(self, name, scope)
				local stores = rawget(self, "__stores")
				local id = "d/" .. tostring(name) .. "/" .. tostring(scope or "global")
				local store = stores[id]
				if not store then
					store = newStore(name, scope, false)
					stores[id] = store
				end
				return store
			end,
			GetOrderedDataStore = function(self, name, scope)
				local stores = rawget(self, "__stores")
				local id = "o/" .. tostring(name) .. "/" .. tostring(scope or "global")
				local store = stores[id]
				if not store then
					store = newStore(name, scope, true)
					stores[id] = store
				end
				return store
			end,
			GetGlobalDataStore = function(self)
				return (self :: any):GetDataStore("__global")
			end,
			GetRequestBudgetForRequestType = function()
				return 1000
			end,
			-- TEST HOOK: forget every store (fresh world between harness runs).
			resetAll = function(self)
				rawset(self, "__stores", {})
			end,
		},
	})

	-- ------------------------------------------------------------ Lighting
	local lightingDefaults: { [string]: any } = {
		Brightness = 2,
		ClockTime = 14,
		GeographicLatitude = 41.7,
		ExposureCompensation = 0,
		FogStart = 0,
		FogEnd = 100000,
		GlobalShadows = true,
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0,
		ShadowSoftness = 0.2,
	}
	if dt.Color3 and dt.Color3.fromRGB then
		lightingDefaults.Ambient = try(dt.Color3.fromRGB, 0, 0, 0)
		lightingDefaults.OutdoorAmbient = try(dt.Color3.fromRGB, 128, 128, 128)
		lightingDefaults.FogColor = try(dt.Color3.fromRGB, 192, 192, 192)
	end
	if dt.Enum then
		lightingDefaults.Technology = try(function()
			return (dt.Enum :: any).Technology.Future
		end)
	end
	defineClass("Lighting", {
		parent = "Instance",
		defaults = lightingDefaults,
		methods = {
			GetMinutesAfterMidnight = function(self)
				return (tonumber(stateOf(self).props.ClockTime) or 0) * 60
			end,
			SetMinutesAfterMidnight = function(self, minutes)
				stateOf(self).props.ClockTime = (tonumber(minutes) or 0) / 60
			end,
		},
	})

	-- ------------------------------------------------------------ Workspace + Camera
	local cameraDefaults: { [string]: any } = { FieldOfView = 70, CameraType = "Custom" }
	if dt.CFrame and dt.CFrame.new then
		cameraDefaults.CFrame = try(dt.CFrame.new, 0, 0, 0)
		cameraDefaults.Focus = try(dt.CFrame.new, 0, 0, 0)
	end
	if dt.Vector2 and dt.Vector2.new then
		cameraDefaults.ViewportSize = try(dt.Vector2.new, 1280, 720)
	end
	defineClass("Camera", { parent = "Instance", defaults = cameraDefaults })

	defineClass("Workspace", {
		parent = "Model",
		defaults = { Gravity = 196.2, StreamingEnabled = false },
		init = function(self)
			local cam = create("Camera")
			cam.Name = "Camera"
			stateOf(self).props.CurrentCamera = cam
		end,
		methods = {
			-- Not implemented on purpose: no physics here. Raising surfaces the gap.
			Raycast = function()
				error("robloxemu: Workspace:Raycast() is not implemented (no physics)", 2)
			end,
		},
	})

	-- ------------------------------------------------------------ RunService
	defineClass("RunService", {
		parent = "Instance",
		events = {
			"Heartbeat",
			"RenderStepped",
			"Stepped",
			"PreRender",
			"PreSimulation",
			"PostSimulation",
			"PreAnimation",
		},
		init = function(self)
			rawset(self, "__isServer", true)
		end,
		methods = {
			IsServer = function(self)
				return rawget(self, "__isServer") ~= false
			end,
			IsClient = function(self)
				return rawget(self, "__isServer") == false
			end,
			IsStudio = function()
				return false
			end,
			IsRunning = function()
				return true
			end,
			IsEdit = function()
				return false
			end,
			IsRunMode = function()
				return false
			end,
			-- No render loop headlessly: binding is a no-op, so client code keeps running.
			BindToRenderStep = function() end,
			UnbindFromRenderStep = function() end,
			-- TEST HOOK: flip the context so client scripts can be exercised too.
			setIsServer = function(self, isServer)
				rawset(self, "__isServer", isServer ~= false)
			end,
		},
	})

	-- ------------------------------------------------------------ TweenService
	local completedState = try(function()
		return (dt.Enum :: any).PlaybackState.Completed
	end) or "Completed"
	local cancelledState = try(function()
		return (dt.Enum :: any).PlaybackState.Cancelled
	end) or "Cancelled"

	defineClass("Tween", {
		parent = "Instance",
		events = { "Completed" },
		methods = {
			-- Headless: apply the goal IMMEDIATELY and report Completed. Game logic that waits
			-- on .Completed keeps moving, and the scene dump sees the END state, which is the
			-- state a screenshot would show anyway.
			Play = function(self)
				local target = rawget(self, "__target")
				local props = rawget(self, "__props")
				if target ~= nil and type(props) == "table" then
					for k, v in props do
						target[k] = v
					end
				end
				rawset(self, "__played", (rawget(self, "__played") or 0) + 1)
				stateOf(self).props.PlaybackState = completedState
				fireIfExists(self, "Completed", completedState)
			end,
			Cancel = function(self)
				stateOf(self).props.PlaybackState = cancelledState
			end,
			Pause = function(self)
				stateOf(self).props.PlaybackState = "Paused"
			end,
		},
	})

	defineClass("TweenService", {
		parent = "Instance",
		init = function(self)
			rawset(self, "__created", {})
		end,
		methods = {
			Create = function(self, target, info, props)
				local tween = create("Tween")
				rawset(tween, "__target", target)
				rawset(tween, "__info", info)
				rawset(tween, "__props", props)
				rawset(tween, "__played", 0)
				table.insert(rawget(self, "__created"), tween)
				return tween
			end,
			GetValue = function(_self, alpha)
				return alpha -- linear: no easing curves headlessly
			end,
			-- TEST HOOK: every tween this service handed out.
			getCreated = function(self)
				return rawget(self, "__created")
			end,
		},
	})

	-- ------------------------------------------------------------ HttpService
	defineClass("HttpService", {
		parent = "Instance",
		defaults = { HttpEnabled = false },
		init = function(self)
			rawset(self, "__guid", 0)
		end,
		methods = {
			-- Unique per service instance (counter in the last field), and stable across runs
			-- so scene dumps stay diffable.
			GenerateGUID = function(self, braces)
				local n = (rawget(self, "__guid") or 0) + 1
				rawset(self, "__guid", n)
				local s = string.format(
					"%08X-%04X-4%03X-%04X-%012X",
					(n * 2654435761) % 4294967296,
					n % 65536,
					n % 4096,
					32768 + (n % 4096),
					n
				)
				if braces == false then
					return s
				end
				return "{" .. s .. "}"
			end,
			JSONEncode = function(_self, value)
				return jsonEncode(value)
			end,
			JSONDecode = function(_self, str)
				return jsonDecode(str)
			end,
			UrlEncode = function(_self, s)
				return (string.gsub(tostring(s), "[^%w%-%._~]", function(c)
					return string.format("%%%02X", string.byte(c))
				end))
			end,
			GetAsync = function()
				error("robloxemu: HttpService:GetAsync() is not implemented (no network)", 2)
			end,
			PostAsync = function()
				error("robloxemu: HttpService:PostAsync() is not implemented (no network)", 2)
			end,
			RequestAsync = function()
				error("robloxemu: HttpService:RequestAsync() is not implemented (no network)", 2)
			end,
		},
	})

	-- ------------------------------------------------------------ inert-but-useful stubs
	defineClass("TextService", {
		parent = "Instance",
		methods = {
			-- Returns the text unchanged, wrapped in the same shape Roblox hands back.
			FilterStringAsync = function(_self, text)
				local filtered = {
					GetNonChatStringForBroadcastAsync = function()
						return text
					end,
					GetChatForUserAsync = function()
						return text
					end,
					GetNonChatStringForUserAsync = function()
						return text
					end,
				}
				return filtered
			end,
			GetTextSize = function()
				return nil
			end,
		},
	})

	defineClass("Path", {
		parent = "Instance",
		events = { "Blocked", "Unblocked" },
		defaults = { Status = "NoPath" },
		methods = {
			ComputeAsync = function(self)
				stateOf(self).props.Status = "NoPath"
			end,
			GetWaypoints = function()
				return {}
			end,
		},
	})

	defineClass("PathfindingService", {
		parent = "Instance",
		methods = {
			CreatePath = function(_self, params)
				local path = create("Path")
				rawset(path, "__params", params)
				return path
			end,
		},
	})

	defineClass("MarketplaceService", {
		parent = "Instance",
		events = { "PromptGamePassPurchaseFinished", "PromptPurchaseFinished" },
		methods = {
			GetProductInfo = function(_self, assetId)
				return { Name = "Product" .. tostring(assetId), PriceInRobux = 0, AssetId = assetId }
			end,
			UserOwnsGamePassAsync = function()
				return false
			end,
			PlayerOwnsAsset = function()
				return false
			end,
			PromptPurchase = function() end,
			PromptGamePassPurchase = function() end,
			PromptProductPurchase = function() end,
		},
	})

	defineClass("BadgeService", {
		parent = "Instance",
		methods = {
			AwardBadge = function()
				return true
			end,
			UserHasBadgeAsync = function()
				return false
			end,
			GetBadgeInfoAsync = function(_self, badgeId)
				return { Name = "Badge" .. tostring(badgeId), IsEnabled = true }
			end,
		},
	})

	defineClass("UserInputService", {
		parent = "Instance",
		events = { "InputBegan", "InputEnded", "InputChanged", "TouchTap", "WindowFocused" },
		defaults = { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false },
		methods = {
			IsKeyDown = function()
				return false
			end,
			GetMouseLocation = function()
				return dt.Vector2 and try((dt.Vector2 :: any).new, 0, 0) or nil
			end,
		},
	})

	defineClass("GuiService", {
		parent = "Instance",
		events = { "MenuOpened", "MenuClosed" },
		defaults = { TopbarInset = nil },
		methods = {
			-- Roblox returns TWO Vector2s: the top-left inset (the topbar) and the bottom-right one.
			-- 36 px is the modern topbar height; a HUD that pins buttons to the top edge with
			-- IgnoreGuiInset on has to subtract it or they land under the Roblox menu button.
			GetGuiInset = function()
				local v2 = dt.Vector2
				if v2 == nil then
					return nil, nil
				end
				return try((v2 :: any).new, 0, 36), try((v2 :: any).new, 0, 0)
			end,
			IsTenFootInterface = function()
				return false
			end,
		},
	})

	defineClass("Debris", {
		parent = "Instance",
		methods = {
			-- No virtual clock here (that is emu/scheduler.luau); dropping the item on the
			-- floor is the safe headless behaviour.
			AddItem = function() end,
		},
	})

	defineClass("SoundService", { parent = "Instance" })
	defineClass("TextChatService", { parent = "Instance" })
	-- The maze game registers a "/bc" admin command server-side and connects to it on the
	-- client. Without the event declared, `cmd.Triggered:Connect(...)` reads nil and the whole
	-- broadcast client dies partway through loading.
	defineClass("TextChatCommand", {
		parent = "Instance",
		events = { "Triggered" },
		defaults = { PrimaryAlias = "", SecondaryAlias = "", Enabled = true, AutocompleteVisible = true },
	})
	defineClass("TextChannel", { parent = "Instance", events = { "MessageReceived" } })
	defineClass("ReplicatedStorage", { parent = "Instance" })
	defineClass("ServerScriptService", { parent = "Instance" })
	defineClass("ServerStorage", { parent = "Instance" })
	defineClass("StarterGui", { parent = "Instance" })
	defineClass("StarterPlayer", { parent = "Instance" })
	defineClass("Teams", { parent = "Instance" })

	-- ------------------------------------------------------------ registry
	local registry: { [string]: any } = {}

	local Players = create("Players")
	Players.Name = "Players"
	registry.Players = Players

	local ws = create("Workspace")
	ws.Name = "Workspace"
	registry.Workspace = ws

	local SIMPLE_CONTAINERS = {
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPlayer",
		"Teams",
		"SoundService",
		"TextChatService",
		"Lighting",
	}
	for _, name in SIMPLE_CONTAINERS do
		local obj = create(name)
		obj.Name = name
		registry[name] = obj
	end

	local SINGLETONS = {
		"DataStoreService",
		"RunService",
		"TweenService",
		"HttpService",
		"TextService",
		"PathfindingService",
		"MarketplaceService",
		"BadgeService",
		"UserInputService",
		"GuiService",
		"Debris",
	}
	for _, name in SINGLETONS do
		local obj = create(name)
		obj.Name = name
		registry[name] = obj
	end

	-- RemoteEvent:FireServer / RemoteFunction:InvokeServer need "who is the client".
	inst.config.getLocalPlayer = function()
		return stateOf(Players).props.LocalPlayer
	end

	local function getService(name)
		if type(name) ~= "string" then
			error("GetService expects a service name string, got " .. typeof(name), 2)
		end
		local svc = registry[name]
		if svc then
			return svc
		end
		-- Any service we did not model becomes an inert object that merely EXISTS: property
		-- access works, unknown method calls still raise, so the gap is visible.
		svc = create(name)
		svc.Name = name
		registry[name] = svc
		return svc
	end

	-- ------------------------------------------------------------ game (DataModel)
	local SERVICE_INDEX_NAMES = {
		Workspace = true,
		Players = true,
		Lighting = true,
		ReplicatedStorage = true,
		ServerScriptService = true,
		ServerStorage = true,
		StarterGui = true,
		StarterPlayer = true,
		SoundService = true,
		TextChatService = true,
		Teams = true,
		Debris = true,
	}

	defineClass("DataModel", {
		parent = "Instance",
		events = { "Close" },
		defaults = { PlaceId = 123669267191209, GameId = 10544008743, JobId = "robloxemu-headless" },
		init = function(self)
			rawset(self, "__bindToClose", {})
		end,
		methods = {
			GetService = function(self, name)
				return (rawget(self, "__getService") :: any)(name)
			end,
			FindService = function(self, name)
				return (rawget(self, "__registry") :: any)[name]
			end,
			BindToClose = function(self, fn)
				if type(fn) ~= "function" then
					error("BindToClose expects a function, got " .. typeof(fn), 2)
				end
				table.insert(rawget(self, "__bindToClose"), fn)
			end,
			IsLoaded = function()
				return true
			end,
			-- TEST HOOK: run every BindToClose callback, like a server shutdown would.
			runBindToClose = function(self)
				for _, fn in table.clone(rawget(self, "__bindToClose")) do
					fn()
				end
			end,
		},
		get = function(self, key)
			if SERVICE_INDEX_NAMES[key] then
				return (rawget(self, "__registry") :: any)[key]
			end
			return nil
		end,
	})

	local game = create("DataModel")
	game.Name = "Game"
	rawset(game, "__registry", registry)
	rawset(game, "__getService", getService)

	return {
		game = game,
		getService = getService,
		services = registry,
		-- the ones the harness reaches for by name
		Players = Players,
		Workspace = ws,
		workspace = ws,
		Lighting = registry.Lighting,
		ReplicatedStorage = registry.ReplicatedStorage,
		ServerScriptService = registry.ServerScriptService,
		DataStoreService = registry.DataStoreService,
		RunService = registry.RunService,
		TweenService = registry.TweenService,
		HttpService = registry.HttpService,
		-- plumbing
		instance = inst,
		Instance = Instance,
		jsonEncode = jsonEncode,
		jsonDecode = jsonDecode,
		newDataStore = newStore,
		runBindToClose = function()
			(game :: any):runBindToClose()
		end,
	}
end

return ServicesLib
