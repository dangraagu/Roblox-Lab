--!strict
-- BoardConfig — the highscore board's settings (docs/complete-game-standard.md §3). Pure data, shared by the server
-- (MazeGame.server: the DataStore calls, caching, throttling) and the client (BoardClient: drawing the board).
-- Board.luau is +1 Jump's template, verbatim; it takes this table as its `cfg`.
--
-- The metric is `accepted`: the highest level a player has cleared IN SEQUENCE, without god mode, measured by the
-- server at the exit (MazeGame.server finishRun, behind the walk guard: Progression.minClearSeconds). Ties go to
-- whoever reached that level first.

return {
	Store = "LabyrintTopp_v3",   -- OrderedDataStore: key u_<userId>, value level * 2e9 + (2e9 - reachedAtUnix)
	LegacyStore = "LabyrintTopp_v2", -- the old board (key tostring(userId), raw level): its top entries are copied once per server start
	LegacyReachedAt = 1790812800, -- 2026-10-01 00:00 UTC: when a legacy entry was reached is unknown, but it was before this
	PublicRows = 10,             -- GetSortedAsync(false, 10)
	PublicCacheSeconds = 60,     -- the server asks the store for the top 10 at most once a minute
	FriendsRows = 10,
	FriendsCap = 200,            -- Players:GetFriendsAsync is never read further than this
	FriendsCacheSeconds = 300,   -- the friends list, per player
	ScoreCacheSeconds = 120,     -- a friend's best, per server (also "has not cleared a level")
	ReadsBurst = 40,             -- GetAsync on the board for friends: 40 at once ...
	ReadsPerSecond = 1,          -- ... then 1 a second (Roblox gives 60 + 10 per player a minute)
	BudgetReserve = 10,          -- always leave this many GetAsync in Roblox's budget
	MaxMetric = 4000000,         -- the value is exact in a double up to here (4e6 * 2e9 < 2^53)
	PromptDistance = 10,         -- studs; the spawn pad's centre is ~15 away, so the prompt shows when you walk over
	-- where the board stands in the lobby (the lobby floor is 70 x 70 around the origin; the spawn pad is at the origin)
	Position = { -15, 5, 2 },    -- centre; 10 tall, so it stands on the floor (top face y = 0)
	Size = { 14, 10, 1 },
	Text = {
		Title = "TOP MAZE RUNNERS",
		EmptyPublic = "No one on the board yet. Clear level 1 and be the first!",
		PublicFailed = "Couldn't load the board right now. It will try again in a minute.",
		FriendsFailed = "Couldn't load your Roblox friends right now. Try again in a minute.",
		NoFriends = "No Roblox friends yet. Friends you add show up here, ranked against you.",
		FriendsNoScores = "None of your %d friends has cleared a level yet. Invite one and race them through the maze!",
		FriendsChecking = "Checking your friends: %d of %d so far...",
		Loading = "Loading...",
		Prompt = "Public / Friends",
		Object = "Top Maze Runners",
	},
}
