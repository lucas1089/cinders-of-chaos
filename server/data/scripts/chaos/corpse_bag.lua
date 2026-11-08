-- Loot bag instead of monster bodies, the engine part (server/README.md "Loot bag instead of corpses"). The rule is in
-- corpse_core.lua (ChaosCorpse, tests/corpse_bag_test.lua), the numbers and the switch in corpse_config.lua.
--
-- At every load (a start and a /reload) it gives the engine the bag and the kept corpse ids once:
-- Game.setMonsterLootBag(bagId, keepIds) (src-patch 0089). From then on Monster::getLookCorpse answers the bag for every
-- monster that has a corpse (a corpse of 0 stays nothing, a kept id stays), so the bag is made where the body was made:
-- loot, the corpse owner, decay and every onDeath / onDropLoot callback see an ordinary corpse container. `enabled =
-- false` in the config and a /reload gives the bodies back. Players are not touched (their corpse never goes through
-- this). An engine built without the patch has no Game.setMonsterLootBag: one line in the log, bodies as before.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCorpse or not ChaosCorpse.engineArgs then
	dofile("data/scripts/chaos/corpse_core.lua")
end
Chaos.corpseConfig = dofile("data/scripts/chaos/corpse_config.lua")
local cfg = Chaos.corpseConfig
local C = ChaosCorpse

-- the bag must be a container that counts as a corpse (items.xml corpseType, tools/patch_monster_corpses.py)
local function bagItemOk()
	local okType, itemType = pcall(ItemType, cfg.bagId)
	if not okType or not itemType or itemType:getId() == 0 then
		return false
	end
	local okC, isC = pcall(function() return itemType:isContainer() and itemType:isCorpse() end)
	return okC and isC and true or false
end

C.engine = false
if Game and Game.setMonsterLootBag then
	local problems = C.validate(cfg)
	for _, p in ipairs(problems) do
		print("[Chaos corpses] config: " .. p)
	end
	local itemOk = nil
	if cfg.enabled and #problems == 0 then
		itemOk = bagItemOk()
		if not itemOk then
			print("[Chaos corpses] item " .. tostring(cfg.bagId) .. " is no corpse container: bodies stay (tools/patch_monster_corpses.py)")
		end
	end
	local bag, keep = C.engineArgs(cfg, itemOk)
	local ok, err = pcall(Game.setMonsterLootBag, bag, keep)
	C.engine = ok and true or false
	C.active = C.engine and bag ~= 0
	if not ok then
		print("[Chaos corpses] Game.setMonsterLootBag: " .. tostring(err))
	end
else
	C.active = false
	if cfg.enabled then
		print("[Chaos corpses] this engine has no Game.setMonsterLootBag (src-patch 0089): monsters leave bodies")
	end
end
