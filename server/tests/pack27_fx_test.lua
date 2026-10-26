-- Run from the server/ folder: luajit tests/pack27_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pack farming spell effects (data/lib/chaos_pack27_fx.lua, pair 27 trial): the switch is one plain line, off; every
-- swap names a spell of spells_chaos.xml (by id and name) whose script sends the swapped name; every new name (swaps,
-- uses, loot beams) is in the client spec (art_import/pack27_fx.csv) and the ids file; off, nothing is swapped or sent
-- and the ids file is not loaded; on, the pair 27 names; _common.lua and the use call sites are wired.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/lib/chaos_pack27_fx.lua")
local C = ChaosPack27Fx

-- the switch: one plain line, on (pair 27 is live: windows-assets 51a26d26, effects 674-758 / missiles 154-160)
local src = readFile("data/lib/chaos_pack27_fx.lua") or ""
eq(src:match("\nC%.PAIR27_FX = (%a+)\n"), "true", "the switch is one plain line, on")
eq(C.PAIR27_FX, true, "the shipped switch is on")

-- the client spec
local spec = {}
for line in (readFile("../client/tools/sprites/art_import/pack27_fx.csv") or ""):gmatch("[^\n]+") do
	local kind, name = line:match("^(%a+),([%w_]+),")
	if kind == "effect" or kind == "missile" then
		spec[kind .. ":" .. name] = true
	end
end
local dirs = {"n", "ne", "e", "se", "s", "sw", "w", "nw"}

-- the spells: id and name as in spells_chaos.xml, the script sends the swapped names
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local helpers = (readFile("data/spells/chaos/_packtools.lua") or "") .. (readFile("data/spells/chaos/_blades.lua") or "")
	.. (readFile("data/spells/chaos/necromancer/bone_shrapnel.lua") or "")
local n = 0
for id, kinds in pairs(C.spells) do
	n = n + 1
	local name = C.names[id]
	ok(name ~= nil, "spell " .. id .. " has a name")
	local script = xml:match('spellid="' .. id .. '" name="' .. (name or "?") .. '"[^>]-script="([^"]+)"')
	ok(script ~= nil, "spells_chaos.xml has spell " .. id .. " named " .. tostring(name))
	local body = (script and readFile("data/spells/" .. script) or "") .. helpers
	for name1 in pairs(kinds.first or {}) do
		ok(kinds.fx ~= nil and kinds.fx[name1] ~= nil, id .. ": first " .. name1 .. " is an fx swap")
	end
	for kind, swaps in pairs(kinds) do
		ok(kind == "fx" or kind == "missile" or kind == "dir" or kind == "fxdir" or kind == "first", id .. ": kind " .. kind)
		for from, to in pairs(kind == "first" and {} or swaps) do
			ok(body:find('"' .. from .. '"', 1, true) ~= nil, tostring(name) .. " sends " .. from)
			if kind == "dir" or kind == "fxdir" then
				for _, d in ipairs(dirs) do
					ok(spec["effect:" .. to .. "_" .. d], to .. "_" .. d .. " in the client spec")
				end
			else
				ok(spec[(kind == "missile" and "missile:" or "effect:") .. to], to .. " in the client spec")
			end
			eq(C.pick(id, kind, from), to, "pick " .. id .. " " .. from)
		end
	end
end
eq(n, 42, "the spells with pair 27 effects")
for use, name in pairs(C.uses) do
	ok(spec["effect:" .. name], "use " .. use .. ": " .. name .. " in the client spec")
end
for _, key in ipairs({"wrath", "iron", "haste", "clarity"}) do
	ok(C.uses["vigil_" .. key] ~= nil, "vigil " .. key .. " has a use")
end
for from, name in pairs(C.portals) do
	ok(spec["effect:" .. name], "portal " .. from .. ": " .. name .. " in the client spec")
	ok((readFile("data/scripts/chaos/townportal_config.lua") or ""):find('"' .. from .. '"', 1, true) ~= nil,
		from .. " is a Town Portal effect")
end
ok(spec["effect:" .. C.telegraphName], "the boss telegraph in the client spec")
for ray, name in pairs(C.rays) do
	ok(spec["effect:" .. name], "ray " .. ray .. ": " .. name .. " in the client spec")
	ok((readFile("data/scripts/chaos/lootfilter_config.lua") or ""):find('"' .. ray .. '"', 1, true) ~= nil,
		ray .. " is a loot ray of lootfilter_config.lua")
end
eq(C.pick(194, "fx", "whirlwind"), nil, "no swap for another name")
eq(C.pick(999, "fx", "aura_burst_gold"), nil, "no swap for another spell")

-- off: nothing, and the ids file is not loaded
C.PAIR27_FX, C.loaded = false, nil
ChaosVfx, ChaosVfxMissile = {aura_burst_gold = {id = 1, dx = 0, dy = 0}}, {}
eq(C.swapFor(194, "fx", "aura_burst_gold"), nil, "off: no swap")
eq(ChaosVfx.palm_quake, nil, "off: ids not loaded")
eq(C.send({x = 1, y = 1, z = 7}, "rested"), false, "off: no use effect")
eq(C.ray("loot_ray_legendary"), nil, "off: the loot ray stays")

-- on: the ids file merges the names, the swaps come back
C.PAIR27_FX, C.loaded = true, nil
eq(C.swapFor(194, "fx", "aura_burst_gold"), "palm_quake", "on: Palm Shockwave")
eq(C.swapFor(136, "missile", "razor_disc"), "fan_knife", "on: Fan of Knives missile")
eq(C.swapFor(74, "dir", "heavy_cleave"), "iaido_dash", "on: Iaido Sweep directional")
eq(C.swapFor(170, "fxdir", "dome_blast_holy"), "shieldwave_bash", "on: Shield Wave turned from the caster")
local beam = C.ray("loot_ray_legendary")
ok(beam ~= nil and beam.id == ChaosVfx.loot_beam_gold.id, "on: the gold beam for a legendary ray")
local sent = {}
Vfx = function(pos, name) sent[#sent + 1] = name return ChaosVfx[name] ~= nil end
eq(C.send({x = 1, y = 1, z = 7}, "rested"), true, "on: a use is sent")
eq(sent[1], "buff_rested", "on: the rested buff")
eq(C.uses.level_up, nil, "the level up is the client's pair 36 effect (game_levelwings), not a pair 27 use")
local sw, first = C.swapFor(204, "fx", "meteor_strike")
eq(sw, "meteor_fall", "on: Falling Pyre meteor")
eq(first, true, "on: the meteor comes before the large effect")
sw, first = C.swapFor(194, "fx", "aura_burst_gold")
eq(first, false, "on: Palm Shockwave keeps the class effect first")
eq(C.portal("teleport_in"), "portal_in", "on: the Waygate opens with the pair 27 effect")
eq(C.portal("fire_ring"), nil, "on: other portal styles keep theirs")
ChaosBigFx = {circleOf = function(tiles) return tiles.centre, tiles.size end}
eq(C.telegraphCentre({centre = {x = 5, y = 5, z = 7}, size = 7}), nil, "on: no danger circle for a 7 x 7 telegraph")
Vfx = function(pos, name) sent[#sent + 1] = name return true end
eq(C.telegraph({centre = {x = 5, y = 5, z = 7}, size = 5}), true, "on: the danger circle for a 5 x 5 telegraph")
eq(sent[#sent], "boss_telegraph", "on: the boss telegraph effect")
ChaosBigFx = nil
Vfx = nil
eq(C.swapFor(73, "fx", "aura_burst_gold"), nil, "on: no swap for another name")
for key in pairs(spec) do
	local kind, name = key:match("^(%a+):(.+)$")
	local e = (kind == "missile" and ChaosVfxMissile or ChaosVfx)[name]
	ok(e ~= nil, name .. " in the ids file")
	if e and kind == "missile" then
		ok(e.id <= 255, name .. ": a missile id fits u8")
	end
end
C.PAIR27_FX, C.loaded = true, nil

-- _common.lua asks the module in fx, vfx, vfxDir, shoot and vshoot
local common = readFile("data/spells/chaos/_common.lua") or ""
for _, k in ipairs({'pack27%("fx", name%)', 'pack27%("missile", name%)', 'pack27%("dir", base%)',
		'pack27%("missile", vname%)'}) do
	ok(common:find(k) ~= nil, "_common.lua calls " .. k)
end

-- the use call sites
local sites = {
	["data/scripts/chaos/catchup.lua"] = {'"rested"', '"returning"', '"catchup"', '"low_stamina"'},
	["data/scripts/chaos/embercache.lua"] = {'"embercache"'},
	["data/scripts/chaos/candlemarks.lua"] = {'"candlemarks"'},
	["data/scripts/chaos/lootfilter.lua"] = {"ChaosPack27Fx.ray(effect)"},
	["data/spells/chaos/_vigils.lua"] = {'"vigil_" .. key'},
	["data/spells/chaos/ironsage/iron_palm.lua"] = {'P27.send, target:getPosition(), "stun"'},
	["data/scripts/chaos/townportal.lua"] = {"P27.portal(e)"},
	["data/scripts/chaos/boss_mechanics.lua"] = {"P27.telegraph, tel.tiles"},
}
for file, keys in pairs(sites) do
	local body = readFile(file) or ""
	for _, k in ipairs(keys) do
		ok(body:find(k, 1, true) ~= nil, file .. " sends " .. k)
	end
end
ok(common:find('pack27("fxdir", name)', 1, true) ~= nil, "_common.lua turns fxdir effects from the caster")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack27 fx test: OK")
