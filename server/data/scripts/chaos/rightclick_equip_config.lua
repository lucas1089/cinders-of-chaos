-- Right-click equips: the numbers and lists (server/README.md "Right-click equips"; rightclick_equip_core.lua reads
-- them, tests/rightclick_equip_test.lua checks them). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and 5.3.
return {
	-- the base's action file: the multi-use weapons whose action is one of destroyScripts (break furniture with a use
	-- with) equip on a right-click; a multi-use item with any other action there (the machete, the crowbar, the
	-- scythe: tools that are also weapons) keeps its use with
	actionsFile = "data/actions/actions.xml",
	destroyScripts = {"other/destroy.lua"},
	-- server item ids that keep their use with although nothing above says so (a revscript Action on equipment)
	keepUseWith = {},
	-- the item ids scanned for the list (ItemType(id) of an unknown id has id 0)
	firstItemId = 100,
	lastItemId = 65000,
}
