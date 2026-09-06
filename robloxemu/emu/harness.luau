--!nolint GlobalUsedAsLocal
-- harness.luau Ã¢â‚¬â€ assembles the fake Roblox environment and runs real game scripts in it.
--
-- The point of the whole emulator: `require("./Rng")` compiled clean, passed 119 unit tests,
-- and would still have made the anomaly server fail to load in Roblox. A headless boot catches
-- that in one second. So does "the HUD is 470 px tall on a 360 px screen".
--
-- ---------------------------------------------------------------------------------------
-- How a game script gets to run against fake globals
--
-- The luau CLI has no file IO and no `setfenv`, and it sandboxes every `require`d module
-- behind its own globals table Ã¢â‚¬â€ a global set here is NOT visible in a module required from
-- here. Two facts make this work anyway:
--
--   1. `loadstring` exists, and the chunk it returns is bound to the globals of the THREAD that
--      called it Ã¢â‚¬â€ not of the file the call is written in. Since the runner calls into this
--      file, both the global install and the game chunks bind to the runner's table, which is
--      what makes them see the same `game` / `Instance` / `task`. See `_installGlobals`; the
--      obvious `game = svc.game` here does NOT work, and cost an afternoon to pin down.
--   2. `robloxemu/wrap.py` bundles a game's sources into one requireable module of verbatim
--      long strings, which is how the source text reaches this file without file IO.
--
-- Chunks are named "@<real path>", so a stack trace points at the actual game file and the
-- actual line, not at the bundle.
--
-- ---------------------------------------------------------------------------------------
-- Known gaps, stated plainly rather than papered over
--
--  * `typeof` is inlined by the Luau compiler, so the global assigned here is ignored inside
--    game code: `typeof(aVector3)` answers "table", not "Vector3". Every `typeof` in our four
--    games compares against "string" / "number" / "table", where the builtin already agrees,
--    so this changes nothing today. It would matter the moment a game type-checks a datatype.
--  * All scripts run in ONE globals table, so a game script that writes a global leaks into
--    the next script of the same run. Roblox gives each script its own. Nothing in our games
--    writes globals; `errors()` will not tell you if that changes.
--  * Nothing renders. This harness proves that code loads, runs, and computes the numbers it
--    claims to; it cannot prove anything looks right.

local Datatypes = require("./datatypes")
local InstanceLib = require("./instance")
local ServicesLib = require("./services")
local Scheduler = require("./scheduler")

local Harness = {}
Harness.__index = Harness

-- One process, one live harness: the globals below are module-wide, so two harnesses would
-- fight over them. Guarded rather than left as a mystery.
local installed = false

-- Height of Roblox's topbar inset, in screen px. Must stay in step with what the GuiService shim
-- returns from GetGuiInset (emu/services.luau), or the geometry walk and the game code under test
-- would be reasoning about two different screens.
Harness.GUI_INSET_Y = 36

--=============================================================================== construction

export type Options = {
	bundle: any, -- the table returned by build/<game>.luau (from wrap.py)
	name: string?, -- for messages
	viewport: { number }?, -- { width, height }; defaults to the Camera's own 1280x720
	touch: boolean?, -- UserInputService.TouchEnabled
}

function Harness.new(opts: Options)
	assert(type(opts) == "table", "Harness.new expects an options table")
	assert(type(opts.bundle) == "table", "Harness.new needs a `bundle` (see wrap.py)")
	assert(not installed, "a Harness is already installed in this process; run one game per CLI invocation")

	local sched = Scheduler.new()
	local inst = InstanceLib.new({ datatypes = Datatypes })
	local svc = ServicesLib.new({ datatypes = Datatypes, instance = inst, scheduler = sched })

	local self = setmetatable({
		name = opts.name or "game",
		bundle = opts.bundle,
		scheduler = sched,
		instance = inst,
		services = svc,
		game = svc.game,
		workspace = svc.workspace,
		Players = svc.Players,
		ReplicatedStorage = svc.ReplicatedStorage,
		Lighting = svc.Lighting,
		-- module key -> { holder = fake ModuleScript, value = any, state = "cold"|"running"|"done" }
		modules = {},
		ran = {}, -- keys already executed by :run()
	}, Harness)

	--------------------------------------------------------------------- the shared-module tree
	-- Every `src/shared/X.luau` becomes ReplicatedStorage.X, a ModuleScript whose value is
	-- produced the first time something requires it. Creating the holders up front (rather than
	-- evaluating up front) is what lets modules require each other in any order.
	for key, entry in opts.bundle do
		local sub, modName = string.match(key, "^([^/]+)/(.+)$")
		if sub == "shared" then
			local holder = inst.Instance.new("ModuleScript")
			holder.Name = modName
			holder.Parent = svc.ReplicatedStorage
			self.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end

	--------------------------------------------------------------------------- global install
	local g = sched:globals()

	-- Collected rather than printed, so a run can assert on what a game warned about.
	self.warnings = {}
	local warnings = self.warnings

	local values = {
		game = svc.game,
		workspace = svc.workspace,
		Instance = inst.Instance,
		Enum = Datatypes.Enum,

		Color3 = Datatypes.Color3,
		Vector3 = Datatypes.Vector3,
		Vector2 = Datatypes.Vector2,
		CFrame = Datatypes.CFrame,
		UDim = Datatypes.UDim,
		UDim2 = Datatypes.UDim2,
		NumberRange = Datatypes.NumberRange,
		NumberSequence = Datatypes.NumberSequence,
		NumberSequenceKeypoint = Datatypes.NumberSequenceKeypoint,
		ColorSequence = Datatypes.ColorSequence,
		ColorSequenceKeypoint = Datatypes.ColorSequenceKeypoint,
		TweenInfo = Datatypes.TweenInfo,
		Random = Datatypes.Random,

		task = g.task,
		wait = g.wait,
		delay = g.delay,
		spawn = g.spawn,

		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			local line = table.concat(parts, " ")
			table.insert(warnings, line)
			print("[warn] " .. line)
		end,

		tick = function()
			return sched:now()
		end,

		require = function(target)
			return self:_require(target)
		end,
	}

	self:_installGlobals(values)
	installed = true

	if opts.viewport then
		self:setViewport(opts.viewport[1], opts.viewport[2])
	end
	if opts.touch ~= nil then
		self:setTouch(opts.touch)
	end

	return self
end

--============================================================================ global install
-- Why this is not just `game = svc.game`.
--
-- The luau CLI gives every required module its own globals table, and `loadstring` binds a
-- chunk to the globals of the THREAD THAT CALLS IT. A plain assignment inside this file writes
-- into harness.luau's own table Ã¢â‚¬â€ but `Harness.new` and `Harness.run` are called from the
-- runner script, on the runner's thread, so the chunks compiled in `_exec` bind to the RUNNER's
-- globals. Assigning here and compiling there put the values in two different tables, and every
-- game script saw `game == nil`.
--
-- So the assignment itself is done by a chunk compiled right here, in the caller's thread: its
-- writes land in exactly the table the game chunks will later read from. The consequence to
-- remember is that `new` and `run` must be called on the SAME thread.
local GLOBAL_NAMES = {
	"game", "workspace", "Instance", "Enum",
	"Color3", "Vector3", "Vector2", "CFrame", "UDim", "UDim2",
	"NumberRange", "NumberSequence", "NumberSequenceKeypoint",
	"ColorSequence", "ColorSequenceKeypoint", "TweenInfo", "Random",
	"task", "wait", "delay", "spawn",
	"warn", "tick", "require",
}

function Harness._installGlobals(self, values)
	local lines = { "local t = ..." }
	for _, name in GLOBAL_NAMES do
		table.insert(lines, name .. " = t." .. name)
	end
	local chunk, err = loadstring(table.concat(lines, "\n"), "@robloxemu-globals")
	if not chunk then
		error("harness could not build its global installer: " .. tostring(err), 0)
	end
	chunk(values)

	-- `script` changes per run, so it needs its own setter bound to the same globals table.
	local setScript, err2 = loadstring("script = ...", "@robloxemu-script")
	if not setScript then
		error("harness could not build its script setter: " .. tostring(err2), 0)
	end
	self._setScript = setScript
	setScript(nil)
end

--=================================================================================== requiring

-- The bug this whole file exists to catch. In Roblox `require` takes an Instance; a bare string
-- resolves happily in the luau CLI and fails in game. Anything that is not one of our fake
-- ModuleScripts is refused by name, loudly.
function Harness._require(self, target)
	if type(target) == "string" then
		error(
			"require(\"" .. target .. "\") Ã¢â‚¬â€ Roblox `require` takes an Instance, not a string. "
				.. "This resolves in the luau CLI and FAILS in Roblox. Use "
				.. "require(ReplicatedStorage:WaitForChild(\"...\")).",
			3
		)
	end

	for _, mod in self.modules do
		if mod.holder == target then
			if mod.state == "done" then
				return mod.value
			end
			if mod.state == "running" then
				error("cyclic require of " .. mod.key, 3)
			end
			mod.state = "running"
			local value = self:_exec(mod.entry, mod.key)
			if value == nil then
				error("module " .. mod.key .. " returned nil; a ModuleScript must return a value", 3)
			end
			mod.value = value
			mod.state = "done"
			return value
		end
	end

	local shown = "nil"
	if target ~= nil then
		local ok, name = pcall(function()
			return tostring((target :: any).Name)
		end)
		shown = ok and name or tostring(target)
	end
	error("require() got something this harness has no module for: " .. shown, 3)
end

--==================================================================================== running

-- Compile and call one bundle entry. Errors keep the game file's own path and line number.
function Harness._exec(self, entry, key: string)
	assert(type(entry) == "table" and type(entry.source) == "string", "bundle entry " .. key .. " has no source")

	local chunk, compileErr = loadstring(entry.source, "@" .. entry.path)
	if not chunk then
		error("compile failed in " .. key .. ": " .. tostring(compileErr), 0)
	end

	local holder = self.modules[key] and self.modules[key].holder
	local previousScript = self._currentScript
	self._currentScript = holder or self:_scriptStub(key)
	self._setScript(self._currentScript)

	local ok, result = pcall(chunk)

	self._currentScript = previousScript
	self._setScript(previousScript)

	if not ok then
		error(tostring(result), 0)
	end
	return result
end

function Harness._scriptStub(self, key: string)
	local stub = self.instance.Instance.new("Script")
	stub.Name = string.match(key, "([^/]+)$") or key
	return stub
end

-- Run a non-module script (`server/Main.server`, `client/Hud.client`). Raises on failure with
-- the real file and line; returns whatever the script returned (usually nil).
function Harness.run(self, key: string)
	local entry = self.bundle[key]
	if entry == nil then
		local available = {}
		for k in self.bundle do
			table.insert(available, k)
		end
		table.sort(available)
		error("no bundle entry '" .. key .. "'. Have: " .. table.concat(available, ", "), 2)
	end
	table.insert(self.ran, key)
	return self:_exec(entry, key)
end

-- Same, but never raises: returns ok, err. Use when the point of the run IS to see whether it
-- loads (that is the whole `require("./Rng")` class of bug).
function Harness.tryRun(self, key: string): (boolean, string?)
	local ok, err = pcall(function()
		return self:run(key)
	end)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

--================================================================================ environment

function Harness.setViewport(self, width: number, height: number)
	local cam = self.workspace.CurrentCamera
	assert(cam ~= nil, "workspace has no CurrentCamera")
	cam.ViewportSize = Datatypes.Vector2.new(width, height)
	return cam
end

function Harness.setTouch(self, touch: boolean)
	local uis = self.game:GetService("UserInputService")
	uis.TouchEnabled = touch and true or false
	-- A phone has no keyboard; the common `TouchEnabled and not KeyboardEnabled` test relies on
	-- these two moving together.
	uis.KeyboardEnabled = not touch
	return uis
end

-- A player who has the PlayerGui a client script expects. `Players:simulateJoin` alone does not
-- create one, and every HUD begins with `player:WaitForChild("PlayerGui")`.
function Harness.join(self, name: string?, userId: number?)
	local plr = self.Players:simulateJoin(name, userId)
	if plr:FindFirstChild("PlayerGui") == nil then
		local pg = self.instance.Instance.new("PlayerGui")
		pg.Name = "PlayerGui"
		pg.Parent = plr
	end
	self.Players.LocalPlayer = plr
	return plr
end

function Harness.leave(self, plr)
	self.Players:simulateLeave(plr)
end

function Harness.advance(self, seconds: number)
	self.scheduler:advance(seconds)
	return self.scheduler:now()
end

function Harness.errors(self): { string }
	return self.scheduler.errors
end

function Harness.hadErrors(self): boolean
	return self.scheduler:hadErrors()
end


--=========================================================== layout settling (screen px)
-- Nothing in this shim lays anything out, so `UIListLayout.AbsoluteContentSize` sits at zero
-- forever. That is not a harmless simplification: our HUDs compute a ScrollingFrame's
-- CanvasSize FROM that property, so with it pinned at zero the correct expression and a
-- broken one evaluate identically and a review had to find the bug by hand. Three files had
-- shipped a canvas that was short by exactly the UIScale factor, which hides completely on a
-- 1080p monitor and costs a phone player the bottom half of the shop.
--
-- So: resolve the geometry, then fill in what each layout's content actually measures. Writing
-- the property fires the game's own GetPropertyChangedSignal handler, which is what makes the
-- canvas maths run for real.
--
-- Values are SCREEN px, like Roblox's. The UIGridLayout arithmetic is an approximation Ã¢â‚¬â€ cells
-- per row from the parent's width, rows from the count Ã¢â‚¬â€ which is enough to catch a canvas that
-- is short by a scale factor, and not enough to trust for pixel work.
function Harness.settleLayouts(self, root, viewportW: number, viewportH: number)
	local rects = self:guiRects(root, viewportW, viewportH)
	local byObj = {}
	for _, r in rects do
		if r.obj ~= nil then
			byObj[r.obj] = r
		end
	end

	for _, r in rects do
		local parent = r.obj
		if parent == nil then continue end
		for _, child in parent:GetChildren() do
			local cls = child.ClassName
			if cls ~= "UIListLayout" and cls ~= "UIGridLayout" then continue end

			local kids = {}
			for _, k in parent:GetChildren() do
				local kr = byObj[k]
				if kr ~= nil then table.insert(kids, kr) end
			end
			if #kids == 0 then
				child.AbsoluteContentSize = Datatypes.Vector2.new(0, 0)
				continue
			end

			-- Roblox sizes the canvas itself when AutomaticCanvasSize covers an axis; the shim
			-- does not, so without this a ScrollingFrame that correctly uses it looks to a
			-- checker exactly like one with a canvas of zero. Applied after the content size is
			-- known, further down.
			local function autoCanvas(contentScreen: number)
				if parent.ClassName ~= "ScrollingFrame" then return end
				local mode = parent.AutomaticCanvasSize
				local name = if mode == nil then "None" else tostring(mode.Name or mode)
				if name ~= "Y" and name ~= "XY" then return end
				local scale = if r.scale > 0 then r.scale else 1
				parent.CanvasSize = Datatypes.UDim2.new(0, 0, 0, math.ceil(contentScreen / scale))
				-- Mark it. A checker that then reads this value back and compares it to the same
				-- content figure is grading the shim's arithmetic against itself and would pass
				-- whatever the game did Ã¢â‚¬â€ so the canvas check must SKIP these and say so.
				parent:SetAttribute("__emuAutoCanvas", true)
			end

			if cls == "UIListLayout" then
				local gap = 0
				local pad = child.Padding
				if pad ~= nil then
					local ok, off = pcall(function() return pad.Offset end)
					if ok and type(off) == "number" then gap = off * r.scale end
				end
				local total, widest = 0, 0
				for _, kr in kids do
					total += kr.sh
					if kr.sw > widest then widest = kr.sw end
				end
				total += gap * math.max(#kids - 1, 0)
				child.AbsoluteContentSize = Datatypes.Vector2.new(widest, total)
				autoCanvas(total)
			else
				local cellW = 100 * r.scale
				local cellH = 100 * r.scale
				local cell = child.CellSize
				if cell ~= nil then
					local ok, w = pcall(function() return cell.X.Offset end)
					local ok2, hgt = pcall(function() return cell.Y.Offset end)
					if ok and type(w) == "number" and w > 0 then cellW = w * r.scale end
					if ok2 and type(hgt) == "number" and hgt > 0 then cellH = hgt * r.scale end
				end
				local padX, padY = 0, 0
				local cp = child.CellPadding
				if cp ~= nil then
					local ok, w = pcall(function() return cp.X.Offset end)
					local ok2, hgt = pcall(function() return cp.Y.Offset end)
					if ok and type(w) == "number" then padX = w * r.scale end
					if ok2 and type(hgt) == "number" then padY = hgt * r.scale end
				end
				local perRow = math.max(1, math.floor((r.sw + padX) / math.max(cellW + padX, 1)))
				local rows = math.ceil(#kids / perRow)
				child.AbsoluteContentSize = Datatypes.Vector2.new(
					math.min(#kids, perRow) * (cellW + padX) - padX,
					rows * (cellH + padY) - padY
				)
				autoCanvas(rows * (cellH + padY) - padY)
			end
		end
	end
end

--=================================================================================== reporting

-- Walk a GuiObject tree and report every frame's resolved screen rectangle, so a test can
-- assert "nothing is off screen" and "nothing sits under the touch controls". Sizes here are
-- computed the way Roblox computes them (scale against the parent, plus offset), including any
-- UIScale found on an ancestor.
function Harness.guiRects(self, root, viewportW: number, viewportH: number): { any }
	local out = {}

	local function scaleOf(obj): number
		local s = 1
		local node = obj
		while node ~= nil do
			local child = node:FindFirstChildOfClass("UIScale")
			if child ~= nil then
				s *= (tonumber(child.Scale) or 1)
			end
			node = node.Parent
		end
		return s
	end

	local function resolve(obj, parentW: number, parentH: number, parentX: number, parentY: number, parentShown: boolean, depth: number)
		local size = obj.Size
		local pos = obj.Position
		if size == nil or pos == nil then
			return
		end

		local w = size.X.Scale * parentW + size.X.Offset
		local h = size.Y.Scale * parentH + size.Y.Offset

		-- Roblox grows a frame with AutomaticSize to fit its content; this shim does not lay
		-- anything out, so an auto-sized panel authored as `UDim2.new(0, w, 0, 0)` measured as
		-- ZERO PIXELS TALL and every rule here scored it as nothing. The maze leaderboard is
		-- exactly that shape, and on a phone Roblox will draw it up to 144 screen px of opaque
		-- panel the gate signed off as absent. Substitute the content extent, capped by any
		-- UISizeConstraint, so the checks see roughly what a player will.
		local auto = obj.AutomaticSize
		local autoName = if auto == nil then "None" else tostring(auto.Name or auto)
		if autoName == "Y" or autoName == "XY" then
			local content = 0
			for _, child in obj:GetChildren() do
				local cls = child.ClassName
				if cls == "UIListLayout" or cls == "UIGridLayout" then
					local acs = child.AbsoluteContentSize
					-- AbsoluteContentSize is screen px; h is design px in the parent's space.
					if acs ~= nil and acs.Y > content then
						content = acs.Y
					end
				end
			end
			if content > 0 then
				local s0 = scaleOf(obj)
				local designContent = content / (if s0 > 0 then s0 else 1)
				if designContent > h then
					h = designContent
				end
			end
			for _, child in obj:GetChildren() do
				if child.ClassName == "UISizeConstraint" then
					local maxS = child.MaxSize
					if maxS ~= nil and maxS.Y ~= nil and maxS.Y > 0 and h > maxS.Y then
						h = maxS.Y
					end
				end
			end
		end
		local x = parentX + pos.X.Scale * parentW + pos.X.Offset
		local y = parentY + pos.Y.Scale * parentH + pos.Y.Offset

		local anchor = obj.AnchorPoint
		if anchor ~= nil then
			x -= anchor.X * w
			y -= anchor.Y * h
		end

		-- Two coordinate spaces, because both matter and confusing them is how a HUD ends up
		-- covering a phone: x/y/w/h are DESIGN px (what the script set), sx/sy/sw/sh are what
		-- the player actually sees after every ancestor UIScale is applied. Assertions about
		-- "fits on screen" must use the screen values.
		local s = scaleOf(obj)
		-- Roblox hides a whole subtree when an ancestor is hidden, so a panel tucked behind a
		-- closed drawer must not be reported as on-screen furniture. `shown` is the AND down
		-- the chain; `visible` is this object's own flag.
		local shown = parentShown and (obj.Visible ~= false)
		table.insert(out, {
			name = obj.Name,
			class = obj.ClassName,
			visible = obj.Visible ~= false,
			shown = shown,
			-- 1 = a direct child of the ScreenGui (usually the scaling root), 2 = the panels
			-- themselves. Callers that measure "how much screen do the panels cover" must count
			-- one depth only, or a panel's own rows get added on top of the panel again.
			depth = depth,
			x = x,
			y = y,
			w = w,
			h = h,
			scale = s,
			obj = obj,
			sx = x * s,
			sy = y * s,
			sw = w * s,
			sh = h * s,
		})

		for _, child in obj:GetChildren() do
			if child.Size ~= nil and child.Position ~= nil then
				resolve(child, w, h, x, y, shown, depth + 1)
			end
		end
	end

	-- A ScreenGui with IgnoreGuiInset false Ã¢â‚¬â€ the Roblox default Ã¢â‚¬â€ does NOT span the viewport:
	-- Roblox shortens it by the topbar inset and pushes its origin down by the same amount. Every
	-- child therefore resolves against a smaller box than the raw viewport, and a panel budgeted
	-- from the full height overflows the real bottom by the inset, straight into the touch-control
	-- band. Resolving everything against the full viewport made that whole class of defect
	-- invisible here, so three of four games "proved" an inset fix the gate could not see.
	--
	-- The inset comes off the TOP only; the bottom edge is the physical bottom either way, which
	-- is why the off-screen and touch-band rules above still measure against the full viewport.
	local insetY = 0
	local ignore = root.IgnoreGuiInset
	if ignore ~= true then
		insetY = Harness.GUI_INSET_Y
	end

	for _, child in root:GetChildren() do
		if child.Size ~= nil and child.Position ~= nil then
			resolve(child, viewportW, viewportH - insetY, 0, insetY, true, 1)
		end
	end

	return out
end

return Harness
