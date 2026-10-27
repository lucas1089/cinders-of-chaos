-- Server ids of the pair 50 items that need a script (server/tools/install_pair50_items.py --lua, from
-- server/data/items/pair50_items.csv). Generated; do not edit by hand. They exist after the "pair50items" install step
-- and need the matching client pair (client/tools/sprites/import_pair50.py).

ChaosPair50 = {
	-- ladders: using one moves the player one floor up (data/scripts/chaos/pair50_items.lua)
	ladders = {
		43977, -- Ladder 1 (client 39977)
		43978, -- Ladder 2 (client 39978)
		43979, -- Ladder 3 (client 39979)
		43980, -- Ladder 4 (client 39980)
		43981, -- Ladder 5 (client 39981)
		43982, -- Ladder 6 (client 39982)
		43983, -- Ladder 7 (client 39983)
		43984, -- Ladder 8 (client 39984)
		48391, -- Wooden ladder (client 44391)
		48392, -- Wooden ladder (client 44392)
	},
}
