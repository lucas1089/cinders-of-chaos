-- Magic effect names some base scripts use but this engine (protocol 10.98) does not register: nil made a
-- "sendMagicEffect" Lua error per cast (single_cloud_chain.lua:16, tester run 2026-10-23) or an effect parameter of 0.
-- Each one falls back to the nearest effect the client has. Loaded first by chaos_unique_items.lua (lib.lua), so before
-- every script, spell and monster file. Never overrides a name the engine registers. Lua 5.1 / LuaJIT and 5.3.
local FALLBACK = {
	CONST_ME_STORM = "CONST_ME_ENERGYAREA",
	CONST_ME_GREENSPARK = "CONST_ME_GREEN_RINGS",
	CONST_ME_ROOTS = "CONST_ME_SMALLPLANTS",
	CONST_ME_PIXIE_EXPLOSION = "CONST_ME_GIFT_WRAPS",
	CONST_ME_BLUE_GHOST = "CONST_ME_YALAHARIGHOST",
	CONST_ME_BLUE_ENERGY_SPARK = "CONST_ME_ENERGYHIT",
	CONST_ME_GREEN_ENERGY_SPARK = "CONST_ME_GREEN_RINGS",
	CONST_ME_WHITE_ENERGY_SPARK = "CONST_ME_HOLYDAMAGE",
	CONST_ME_YELLOW_ENERGY_SPARK = "CONST_ME_YELLOWENERGY",
}
for name, to in pairs(FALLBACK) do
	if _G[name] == nil then
		_G[name] = _G[to] or 0
	end
end
