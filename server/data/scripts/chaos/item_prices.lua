-- Item prices: the price table for every NPC sale (data/lib/chaos_item_prices.lua, ChaosItemPrices) and the Loot Buyer
-- NPCs (data/npc/Loot Buyer.xml, data/npc/scripts/loot_buyer.lua), one next to every temple, placed at startup.
-- Overview: server/README.md "Item prices". Numbers: item_prices_config.lua; prices: tools/gen_item_prices.py.
--
-- Other scripts call ChaosItemPrices.sellPrice(item) for what an NPC pays for one copy (rarity, item level and unique
-- included) or ChaosItemPrices.basePrice(id) for a plain copy; the Auto Seller's sell_prices.lua holds the same plain
-- prices.

if not ChaosItemPrices or not ChaosItemPrices.sellPrice then
	dofile("data/lib/chaos_item_prices.lua")
end

local ok, cfg = pcall(dofile, "data/scripts/chaos/item_prices_config.lua")
if not ok or type(cfg) ~= "table" then
	print("[Chaos item prices] item_prices_config.lua: " .. tostring(cfg))
	cfg = {enabled = false, npc = {name = "Loot Buyer", towns = "all", offsets = {}}}
end
ChaosItemPrices.config = cfg
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

local function log(text)
	print("[Chaos item prices] " .. text)
end

function ChaosItemPrices.placeNpcs()
	local towns = {}
	if cfg.npc.towns == "all" then
		towns = Game.getTowns and Game.getTowns() or {}
	else
		for _, id in ipairs(cfg.npc.towns) do
			towns[#towns + 1] = Town(id)
		end
	end
	local placed, missed = 0, {}
	for _, town in ipairs(towns) do
		local temple = town and town:getTemplePosition()
		local done = false
		if temple then
			-- npc_place.lua: the offsets first, then any reachable free tile, away from the other NPCs
			local okp, npc = pcall(ChaosNpcPlace.place, cfg.npc.name, temple, cfg.npc.offsets, cfg.npc.place)
			done = okp and npc ~= nil
			if not okp then
				log("placing at " .. town:getName() .. ": " .. tostring(npc))
			end
		end
		if done then
			placed = placed + 1
		else
			missed[#missed + 1] = town and town:getName() or "?"
		end
	end
	if #missed > 0 then
		log("no " .. cfg.npc.name .. " at " .. table.concat(missed, ", ") .. " (no free tile near the temple, or data/npc/" ..
			cfg.npc.name .. ".xml is missing: tools/install_item_prices.py)")
	end
	return placed
end

local startup = GlobalEvent("ChaosItemPricesStartup")
function startup.onStartup()
	local n = 0
	for _ in pairs(ChaosItemPrices.prices()) do
		n = n + 1
	end
	log(n .. " item prices loaded")
	if cfg.enabled then
		addEvent(function()
			log(ChaosItemPrices.placeNpcs() .. " " .. cfg.npc.name .. "(s) placed")
		end, cfg.npc.delayMs or 2600)
	end
	return true
end
startup:register()
