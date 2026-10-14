-- Store-bound items never drop on death: the pure rules (no engine calls), shared by death_keep.lua and
-- server/tests/death_keep_test.lua. server/README.md "Store pouches and the Everfull Ration" (Death).
--   ChaosDeathKeepCore.find(root, api)                  the kept items inside root: {{item, parent}}
--   ChaosDeathKeepCore.beforeDrop(item, corpse, api)    -> stays (true: item is kept itself, it stays in its slot), parked
-- api (death_keep.lua binds it to the engine; the test to a mock):
--   kept(item) -> bool         a store-bound item (store pouches, the Everfull Ration, the nemesis trophy, ...)
--   isContainer(item), items(container) -> list (a copy: the loop moves items out of it)
--   moveTo(item, dest) -> bool  no size limit, like the engine's item:moveTo
--   remove(item)
--   park(item) -> bool         out of the drop for good: the character's inbox, marked for the next login
-- The base death script (data/creaturescripts/scripts/droploot.lua, hook written by tools/patch_base_events.py step 15)
-- asks before each slot item drops. The engine has no corpse on a tile that cannot hold one (shallow water): the stock
-- script then removes every dropped item, so a kept item must leave the drop BEFORE it, never be fished out of a corpse.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosDeathKeepCore = ChaosDeathKeepCore or {}
local K = ChaosDeathKeepCore

K.SCAN_LIMIT = 4000 -- items looked at in one dropped slot (a backpack of backpacks)

-- the kept items inside `root` (not root itself), with the container holding each; nothing inside a kept item (it
-- leaves with it)
function K.find(root, api)
	local out, queue, i = {}, {root}, 1
	while queue[i] and i <= K.SCAN_LIMIT do
		local it = queue[i]
		i = i + 1
		if api.isContainer(it) then
			for _, inner in ipairs(api.items(it) or {}) do
				if api.kept(inner) then
					out[#out + 1] = {item = inner, parent = it}
				else
					queue[#queue + 1] = inner
				end
			end
		end
	end
	return out
end

-- the loot inside a kept container (never the kept items in it) goes to `dest`. orRemove: what cannot go there is
-- removed (the stock rule for a dropped item without a corpse); else it stays where it is.
local function emptyInto(item, dest, api, orRemove)
	if not api.isContainer(item) then
		return
	end
	for _, inner in ipairs(api.items(item) or {}) do
		if not api.kept(inner) then
			local moved = dest ~= nil and api.moveTo(inner, dest)
			if not moved and orRemove then
				api.remove(inner)
			end
		end
	end
end

-- called for each slot item the death script is about to drop. Returns stays, parked:
--   stays = true   the item itself is kept: it stays in its slot (the death script skips it); its loot drops like any
--                  loot (into the corpse, or gone without one), so a store container is no death-proof backpack
--   stays = false  the item drops; every kept item in it was parked first (its own loot left in the dropped container)
function K.beforeDrop(item, corpse, api)
	if api.kept(item) then
		emptyInto(item, corpse, api, true)
		return true, {}
	end
	local parked = {}
	for _, f in ipairs(K.find(item, api)) do
		emptyInto(f.item, f.parent, api, false)
		if api.park(f.item) then
			parked[#parked + 1] = f.item
		end
	end
	return false, parked
end

-- the login line for what came back: names = {"Loot Bag", ...}, where = "backpack" | "inbox" | "backpack and inbox"
function K.loginText(names, where)
	if not names or #names == 0 then
		return nil
	end
	return string.format("Kept through your death: your %s (%s).", table.concat(names, ", "), where or "inbox")
end
