--!strict
-- Secret.luau — the depot's one secret and the code table. SERVER ONLY.
--
-- Rojo puts this file in ServerScriptService, which never replicates. That is the whole point of
-- it being here and not in src/shared (DESIGN.md §8.2):
--   * the Back Room note is the game's viral secret; anything in ReplicatedStorage can be
--     datamined by any client, so it would be on a wiki before anyone earned it;
--   * unreleased codes in a replicated table are datamined before their article goes up.
--
-- The note travels only in a `Scene` FireClient to the player who unlocked the room. The props
-- other players can see carry no text.

local Secret = {}

Secret.Note = {
	"THE BACK ROOM",
	"",
	"You cleared the backlog. Nobody has done that since this depot opened.",
	"",
	"Every item on those shelves was somebody's, and most of them went home.",
	"This key never did. It was the first thing ever handed in, the night the",
	"depot opened, and its tag was already torn clean off: no letter, no",
	"condition, no route.",
	"",
	"I kept it on this shelf for thirty-nine years and never found out what it opens.",
	"",
	"It is yours now, Keeper. Somewhere in this depot, a door is still locked.",
	"",
	"- R. Okafor, first Depot Keeper",
}

-- Code -> reward. Cash only; the launch code is exactly one level-1 upgrade (DESIGN.md §6.4).
Secret.Codes = {
	SORTED = { cash = 250 },
}

return Secret
