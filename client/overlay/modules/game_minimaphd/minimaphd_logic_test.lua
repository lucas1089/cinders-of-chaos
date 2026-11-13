-- run from the repo root: luajit client/overlay/modules/game_minimaphd/minimaphd_logic_test.lua (and lua5.3)
dofile('client/overlay/modules/game_minimaphd/minimaphd_logic.lua')
local L = MinimapHdLogic

assert(L.DIR == '/data/minimap_hd', 'the folder the atlas ships in')
assert(L.OPTION == 'hdMinimap', 'the option the settings dataset names')
assert(L.SHADER == 'chaos_minimap_hd', 'the name the engine draws with (Minimap::draw)')
assert(L.VERTEX == '/shaders/chaos_minimap_vertex' and L.FRAGMENT == '/shaders/chaos_minimap_hd', 'shader files')
assert(L.MIN_SCALE == 2, 'HD from 2 px per tile')

assert(L.isOn(true) == true and L.isOn(nil) == true and L.isOn(false) == false and L.isOn(0) == true, 'option as a switch')

assert(L.hasEngine(nil) == false, 'no minimap table')
assert(L.hasEngine({}) == false, 'an engine without the patch')
assert(L.hasEngine({ loadHdAtlas = function() end }) == false, 'half of the API is not enough')
assert(L.hasEngine({ loadHdAtlas = function() end, setHdEnabled = function() end }) == true, 'the patch API')

assert(L.mobileDefault(true, false) == true and L.mobileDefault(true, nil) == true, 'a phone that has not taken it')
assert(L.mobileDefault(true, true) == false, 'a phone that took it keeps the player choice')
assert(L.mobileDefault(false, false) == false and L.mobileDefault(nil, nil) == false, 'a desktop never')

assert(L.summary(0, true) == 'no HD minimap atlas found, the flat map stays', 'none')
assert(L.summary(nil, true) == 'no HD minimap atlas found, the flat map stays', 'nil')
assert(L.summary(16921, true) == 'HD minimap: 16921 swatches, on', 'on')
assert(L.summary(16921, false) == 'HD minimap: 16921 swatches, off', 'off')

print('minimaphd_logic_test: ok')
