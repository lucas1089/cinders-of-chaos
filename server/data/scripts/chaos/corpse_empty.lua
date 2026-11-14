-- Empty loot bags vanish fast (O565, owner 2026-11-14 (pt-BR): "faca tambem eles desaparecem mais rapido quando estiverem
-- vazias"). The engine glue; the rule is in corpse_core.lua (ChaosCorpse.sweep, tests/corpse_bag_test.lua), the number is
-- corpse_config.lua `emptySeconds`; server/README.md "Loot bag instead of corpses".
--
-- A bag has the normal `seconds` of corpse_config.lua (items.xml duration, tools/patch_monster_corpses.py). When it holds
-- nothing any more (looted by hand, by quick loot, by auto loot, or a monster with no loot at all) its remaining time is cut
-- to `emptySeconds`: item:setAttribute(ITEM_ATTRIBUTE_DURATION, ms) moves a decaying item to its new time (decay.h). A
-- bag with items keeps its time; the time is never made longer.
--
-- How it finds them without a hook on every way an item can leave a container: EventCallback onDropLoot (the corpse is on its
-- tile, the loot layer and auto loot ran before, priority 9) remembers the PLACE of a new bag; one timer, only while a place is
-- remembered, looks at those tiles every second and cuts the time of each empty bag it finds there. State is in memory (a
-- restart forgets the places: bags that were lying keep their time). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCorpse or not ChaosCorpse.sweep then
	dofile("data/scripts/chaos/corpse_core.lua")
end
local C = ChaosCorpse
local cfg = Chaos.corpseConfig or dofile("data/scripts/chaos/corpse_config.lua")

local watch = C.newWatch()
local running = false

local function nowSec()
	return os.time()
end

-- the bags of the tile as {size, remaining, item} rows
local function probe(pos)
	local rows = {}
	local tile = Tile(pos.x, pos.y, pos.z)
	if not tile then
		return rows
	end
	for _, item in ipairs(tile:getItems() or {}) do
		if item:getId() == cfg.bagId then
			local size = item.getSize and item:getSize() or 0
			rows[#rows + 1] = {size = size, remaining = item:getAttribute(ITEM_ATTRIBUTE_DURATION) or 0, item = item}
		end
	end
	return rows
end

local function shorten(row, ms)
	row.item:setAttribute(ITEM_ATTRIBUTE_DURATION, ms)
	-- a bag that was not counting down yet starts now (a no-op for one that is)
	pcall(row.item.decay, row.item)
end

local tick
tick = function()
	local ok, err = pcall(C.sweep, cfg, watch, nowSec(), probe, shorten)
	if not ok then
		print("[Chaos corpses] empty bag sweep: " .. tostring(err))
	end
	if C.count(watch) > 0 then
		addEvent(tick, C.CHECK_MS)
	else
		running = false
	end
end

local function remember(corpse)
	if not C.emptyMs(cfg) or not corpse or corpse:getId() ~= cfg.bagId then
		return
	end
	if not C.watch(watch, corpse:getPosition(), nowSec()) then
		return
	end
	if not running then
		running = true
		addEvent(tick, C.CHECK_MS)
	end
end

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local ok, err = pcall(remember, corpse)
	if not ok then
		print("[Chaos corpses] empty bag watch: " .. tostring(err))
	end
end
drop:register(9) -- after the loot layer, autoloot (and globes, 8): their items are in or out of the bag already
