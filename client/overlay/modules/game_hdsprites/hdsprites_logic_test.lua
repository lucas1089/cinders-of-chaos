-- run from the repo root: luajit client/overlay/modules/game_hdsprites/hdsprites_logic_test.lua (and lua5.3)
dofile('client/overlay/modules/game_hdsprites/hdsprites_logic.lua')
local L = HdSpritesLogic

assert(L.DIR == '/data/hd', 'the folder the overlay ships in')
assert(L.OPTION == 'hdMonsters', 'the option the settings dataset names')

-- on unless the value is false
assert(L.isOn(true) == true, 'true is on')
assert(L.isOn(nil) == true, 'no value is on')
assert(L.isOn(false) == false, 'false is off')
assert(L.isOn(0) == true, 'only false turns it off')

-- phones: off once
assert(L.mobileDefault(true, false) == true, 'a phone that has not taken it')
assert(L.mobileDefault(true, nil) == true, 'a phone with no flag')
assert(L.mobileDefault(true, true) == false, 'a phone that took it keeps the player choice')
assert(L.mobileDefault(false, false) == false, 'a desktop never')
assert(L.mobileDefault(nil, nil) == false, 'unknown is not a phone')

-- log line
assert(L.summary(0, true) == 'no HD overlay found', 'none')
assert(L.summary(nil, true) == 'no HD overlay found', 'nil')
assert(L.summary(12, true) == 'HD overlay: 12 sprites, on', 'on')
assert(L.summary(12, false) == 'HD overlay: 12 sprites, off', 'off')

print('hdsprites_logic_test: ok')
