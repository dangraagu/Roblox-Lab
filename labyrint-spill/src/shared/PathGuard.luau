--!strict
-- PathGuard.luau — the server's PATH EVIDENCE for a clear. Pure logic: no Roblox API and no require, so it runs
-- under the luau CLI (tests/PathGuard.spec.luau) and in the game (the server passes everything in).
--
-- WHY (second review 2026-10-09, HIGH): movement is the client's. The walk guard's time floor
-- (Progression.minClearSeconds) only refuses an exit reached too SOON, so a script could stand at the spawn for that
-- long and then teleport onto the exit pad: an unbeatable record and a climbing board, for free.
--
-- WHAT: the server samples each runner's root position several times a second and keeps one VALIDATED position per
-- player. A sample moves the validated position only if a walker could have got there from it:
--   * the sample is in an open cell of the maze's fine grid, with EVERY planned secret door open (so the guard is
--     never stricter than the maze the player is really in);
--   * its COST fits the player's ALLOWANCE. The cost of a move is the larger of the straight-line distance and what
--     the cell route between the two cells must at least be: (steps - StepPad) * cellSize / 2. A walker can cross
--     two cell borders at once (rounding a wall corner), but the next border is then a whole cell away: a hairpin
--     round a wall end is two such corners cellSize apart, so no line crosses more than 2 + 2 * length / cellSize
--     borders. (cellSize / sqrt(2) a step, the diagonal staircase, is NOT a lower bound: the spec's hairpin mazes
--     broke it.) StepPad is that 2 with a cell to spare. The spec measures both terms against the shortest line
--     anyone can walk, on the game's own mazes, and they never exceed it.
--   * the ALLOWANCE is a bank of studs. It fills at MaxSpeed * SpeedSlack studs a second and is capped at
--     BankSeconds of that; every accepted move is paid from it. So standing still (at the spawn, or on the exit
--     pad after a teleport) buys BankSeconds of walking and not a stud more, while a lag gap pays for itself: the
--     bank fills during the seconds the server saw nothing, and the catch-up move is paid from it.
-- A sample that does not fit changes NOTHING: the validated position stays, the bank keeps filling to its cap, and
-- the player is tracked again as soon as a sample fits (the next tick after a hiccup; back near where the lag began
-- after a gap longer than the bank). The exit counts only when the validated cell is within ExitReach cells of it.
-- THE COST TO AN HONEST PLAYER, stated: after a gap longer than the bank (about 5 s of blind running at top speed)
-- the player is NOT found again by walking on, only by walking back to within a bank of where the gap began. So the
-- state remembers since when it has been lost (`lostFor`), and the server tells the player AT ONCE (after
-- LostNoticeSeconds), while the way back is still short, instead of at the exit.
--
-- The server must call `seed` every time IT moves a player (placed in a run, moved on to the next level): the
-- validated position is then where the server put them.
--
-- WHAT THIS DOES NOT DO (tests/PathGuard.spec.luau section 4 measures it): a script that moves along the real
-- route in hops the bank allows is accepted; so is one that simply walks. The guard makes a clear require the
-- route (through any planned secret door, opened or not, and through a wall whose way round is within one bank).
-- It does NOT hold such a script to walking speed: the step charge is a lower bound (half a cell a step), so on a
-- winding route a hopper is charged about half of what a walker walks, and measured it finishes in as little as
-- 0.41 of the fastest honest time. The server's time floor (Progression.minClearSeconds) is what holds it, at
-- about 0.6. A record is not script-proof.

local PathGuard = {}

-- One place for the numbers (the server adds MaxSpeed = the fastest walking speed, with the speed perk).
PathGuard.Config = {
	SampleSeconds = 0.25,   -- how often the server samples a runner
	SpeedSlack = 1.3,       -- the bank fills this much faster than anyone walks: jitter never empties it
	BankSeconds = 4,        -- the cap: waiting buys at most this; a lag gap up to about BankSeconds * SpeedSlack is tolerated
	StartBankSeconds = 1,   -- the bank a player starts a level with
	StepPad = 3,            -- cell steps that cost nothing in a move (see above; the geometry needs 2)
	ExitReach = 1,          -- the pad is touched from the exit cell or the passage next to it
	LostNoticeSeconds = 1.5, -- refused this long without a break: tell the player now (a hiccup heals in one tick)
}

export type Maze = {
	grid: any, gCols: number, gRows: number, cellSize: number,
	originX: number, originZ: number, exitFx: number, exitFy: number,
}
export type State = { fx: number, fy: number, x: number, z: number, t: number, bank: number, lostAt: number? }

-- A copy of `grid` (grid[y][x] == true is a wall) with the cells named in `doorKeys` ("x,y") open.
function PathGuard.openGrid(grid: any, gRows: number, doorKeys: { string }): any
	local open = {}
	for y = 0, gRows - 1 do open[y] = table.clone(grid[y]) end
	for _, k in doorKeys do
		local dx, dy = string.match(k, "^(%d+),(%d+)$")
		local row = dy and open[tonumber(dy) :: number]
		if row and row[tonumber(dx) :: number] ~= nil then row[tonumber(dx) :: number] = false end
	end
	return open
end

-- The guard's view of one built maze. `grid` should be an openGrid; origin = the maze's centre in the world.
function PathGuard.maze(grid: any, gCols: number, gRows: number, cellSize: number, originX: number, originZ: number,
	exitFx: number, exitFy: number): Maze
	return { grid = grid, gCols = gCols, gRows = gRows, cellSize = cellSize, originX = originX, originZ = originZ,
		exitFx = exitFx, exitFy = exitFy }
end

-- The fine cell of a world position (the inverse of MazeGen.gridToWorld). May be outside the grid.
function PathGuard.cellOf(maze: Maze, x: number, z: number): (number, number)
	return math.floor((x - maze.originX) / maze.cellSize + (maze.gCols - 1) / 2 + 0.5),
		math.floor((z - maze.originZ) / maze.cellSize + (maze.gRows - 1) / 2 + 0.5)
end

function PathGuard.isOpen(maze: Maze, fx: number, fy: number): boolean
	local row = maze.grid[fy]
	return row ~= nil and row[fx] == false
end

-- Cell steps from (ax, ay) to (bx, by) through open cells, or nil when there is no way within `limit` steps.
function PathGuard.steps(maze: Maze, ax: number, ay: number, bx: number, by: number, limit: number): number?
	if not PathGuard.isOpen(maze, ax, ay) or not PathGuard.isOpen(maze, bx, by) then return nil end
	if ax == bx and ay == by then return 0 end
	if math.abs(ax - bx) + math.abs(ay - by) > limit then return nil end
	local gCols = maze.gCols
	local grid = maze.grid
	local seen = { [ay * gCols + ax] = true }
	local qx, qy, qd = { ax }, { ay }, { 0 }
	local head = 1
	while head <= #qx do
		local x, y, d = qx[head], qy[head], qd[head]
		head += 1
		if d < limit then
			for i = 1, 4 do
				local nx = if i == 1 then x + 1 elseif i == 2 then x - 1 else x
				local ny = if i == 3 then y + 1 elseif i == 4 then y - 1 else y
				local row = grid[ny]
				if row ~= nil and row[nx] == false and not seen[ny * gCols + nx] then
					if nx == bx and ny == by then return d + 1 end
					seen[ny * gCols + nx] = true
					table.insert(qx, nx); table.insert(qy, ny); table.insert(qd, d + 1)
				end
			end
		end
	end
	return nil
end

-- What a move costs: `straight` studs in a straight line, `steps` cell steps apart through the maze. Never more
-- than the length of the shortest line a walker could take between the two points (see the header).
function PathGuard.cost(maze: Maze, straight: number, steps: number, cfg: any): number
	return math.max(straight, (steps - cfg.StepPad) * maze.cellSize / 2)
end

-- The server moved the player to (x, z) at time t: that is the validated position now.
function PathGuard.seed(maze: Maze, x: number, z: number, t: number, cfg: any): State
	local fx, fy = PathGuard.cellOf(maze, x, z)
	return { fx = fx, fy = fy, x = x, z = z, t = t, bank = cfg.MaxSpeed * cfg.SpeedSlack * cfg.StartBankSeconds }
end

-- One sample of the player's root position at time t. Returns true when it was accepted (the validated position
-- is now here), false and a reason otherwise. Never throws on a junk position; a refused sample only fills the bank.
function PathGuard.sample(state: State, maze: Maze, x: number, z: number, t: number, cfg: any): (boolean, string)
	local rate = cfg.MaxSpeed * cfg.SpeedSlack
	local cap = rate * cfg.BankSeconds
	local elapsed = t - state.t
	if elapsed > 0 then
		state.bank = math.min(cap, state.bank + rate * elapsed)
		state.t = t
	end
	local allowance = state.bank
	if x ~= x or z ~= z then return false, "offgrid" end
	local fx, fy = PathGuard.cellOf(maze, x, z)
	if not PathGuard.isOpen(maze, fx, fy) then return false, "offgrid" end
	local dx, dz = x - state.x, z - state.z
	local straight = math.sqrt(dx * dx + dz * dz)
	if not (straight <= allowance) then
		state.lostAt = state.lostAt or t
		return false, "far"
	end
	local perStep = maze.cellSize / 2
	local limit = math.floor(allowance / perStep) + cfg.StepPad
	local steps = PathGuard.steps(maze, state.fx, state.fy, fx, fy, limit)
	local cost = steps and PathGuard.cost(maze, straight, steps, cfg)
	if cost == nil or cost > allowance then
		state.lostAt = state.lostAt or t
		return false, "unreachable"
	end
	state.bank = allowance - cost
	state.fx, state.fy, state.x, state.z = fx, fy, x, z
	state.lostAt = nil
	return true, "ok"
end

-- For how many seconds, up to time t, has every sample in the maze been refused? 0 while the player is tracked.
-- (A position off the grid or in a wall neither starts nor ends it.)
function PathGuard.lostFor(state: State, t: number): number
	return if state.lostAt then math.max(0, t - state.lostAt) else 0
end

-- Is the validated position at the exit? (cell steps through the maze, never straight through a wall)
function PathGuard.atExit(state: State, maze: Maze, cfg: any): boolean
	return PathGuard.steps(maze, state.fx, state.fy, maze.exitFx, maze.exitFy, cfg.ExitReach) ~= nil
end

return PathGuard
