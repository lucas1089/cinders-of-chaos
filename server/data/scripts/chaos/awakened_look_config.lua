-- Awakened spell look (O711, client pair 76): the one table that says which kit effect an awakened spell sends. Plain table, loaded with
--     ChaosAwakenedLookConfig = dofile("data/scripts/chaos/awakened_look_config.lua")
-- Rules: docs/SPELL_UPGRADES.md 3.4, server/README.md "Awakened spell looks (O711)"; code: data/lib/chaos_awakened_look.lua, the kit:
-- data/lib/chaos_awakened_fx.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- ELEMENT. The kit has the eight elements of ChaosAwakenedFx.ELEMENTS. A cast takes the element it SHOWS: the element of an
	-- SHIFT / ASCEND Form of the spell when it has one (the Form's new element), else the spell's own element of awakened.csv (spelldata.lua).
	-- A spell whose element is none of the eight (a heal, a utility spell: awakened.csv has it empty) takes this kit.
	fallbackElement = "arcane",

	-- SHAPE. The area shape of the spell in awakened.csv (the shape column: the areaShape of the client spell list, the list
	-- tools/ci/check_rotation_kit.py reads) -> the kit shape. `self` is a spell cast on the caster: the ring round the caster.
	shape = {single = "single", circle = "circle", around = "around", line = "line", wave = "wave", self = "around"},
	-- a spell whose shape is not in the table above takes this one
	fallbackShape = "single",

	-- ANCHOR. The tile the kit effect is sent on, plus the send offset of the kit entry (dx, dy of chaos_awakened_fx_ids.lua):
	-- `target` is the tile of the cast's first send (the target, or the tile an area cast is aimed at), `caster` the caster's own tile.
	anchor = {single = "target", circle = "target", around = "caster", line = "caster", wave = "caster"},

	-- HEADING. A line or a wave of the kit is drawn running EAST (client/tools/sprites/gen_awakened_fx.py: the other headings come with
	-- a later build step). A cast of a line or wave spell that does not face east sends the kit shape named here, on the target.
	-- Empty a row once the pair draws every heading.
	eastOnly = {line = "single", wave = "single"},
}
