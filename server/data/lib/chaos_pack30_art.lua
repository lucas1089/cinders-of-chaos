-- chaos_pack30_art.lua: the third-party pack art of the client pair 30 on the server side, behind one switch.
-- Loaded with  ChaosPack30Art = dofile("data/lib/chaos_pack30_art.lua")  (server/tools/install_pack30_items.py reads the
-- switch line). Plain Lua, no engine calls at load (server/tests/pack30_art_test.lua).
--
-- Pair switch (M.PAIR30, OFF until the owner switches it: the dat has the ids only after pair 30 is pushed to the
-- client). A client on pair 29 or older has none of the items 34443+ and none of the outfits 2237+ (it would draw
-- nothing, or stop on a look id past its last outfit). The items may be installed with the switch off
-- (server/tools/install_pack30_items.py, install_all step pack30items); nothing uses them then.
-- On: M.decorId(key, fallback) gives the pack item of that key, M.lookOf(name, current) the pack look of a monster.
--
-- What it holds: item server ids (data/lib/chaos_pack30_items.lua, generated), and monster name -> look rows once
-- the monsters are wired (M.monsters, filled with the picks of client/tools/sprites/monster_looks/pack30_picks.csv).

local M = {}

M.PAIR30 = false

local ok, items = pcall(dofile, "data/lib/chaos_pack30_items.lua")
M.items = ok and items or {first = 37443, items = {}, groups = {}}

-- monster name -> look once the switch is on (before: the stock look the file has now)
M.monsters = {
}

-- the server id of a pack item once the switch is on; the fallback (a stock item id) before, or for an unknown key
function M.decorId(key, fallback)
	local it = M.items.items[key]
	if M.PAIR30 and it then
		return it.id
	end
	return fallback
end

-- the look a monster should carry now
function M.lookOf(name, current)
	if M.PAIR30 and M.monsters[name] then
		return M.monsters[name]
	end
	return current
end

return M
