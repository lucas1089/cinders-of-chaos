-- luajit helper_config_test.lua && lua5.3 helper_config_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_config.lua')
local C = ChaosHelperCfg
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- defaults
local d = C.defaults()
eq(#d.spells, 3, 'three heal rows')
eq(#d.potions, 3, 'three potion rows')
eq(#d.shooterProfiles.Default.spells, 5, 'five slots')
eq(d.autoTargetMode, 6, 'mode F by default')
eq(d.helperAutomaticFunctionsEnabled, true, 'automatic functions on')

-- sanitize: wrong types and ranges
eq(C.sanitize('x').selectedShooterProfile, 'Default', 'not a table')
local c = C.sanitize({ spells = { { id = 'abc', percent = 500 } }, autoTargetMode = 99, magicShooterEnabled = 'yes',
  shooterProfiles = { Mine = { spells = { { id = 5, percent = -3, creatures = 40, forceCast = 1 } } } },
  selectedShooterProfile = 'Gone', unknownField = { keep = 1 } })
eq(c.spells[1].id, 0, 'bad id')
eq(c.spells[1].percent, 100, 'percent clamped')
eq(c.autoTargetMode, 8, 'mode out of range is clamped')
eq(c.magicShooterEnabled, false, 'bool fallback')
eq(c.shooterProfiles.Mine.spells[1].percent, 0, 'slot percent clamped')
eq(c.shooterProfiles.Mine.spells[1].creatures, 8, 'creatures clamped')
eq(c.shooterProfiles.Mine.spells[1].forceCast, false, 'forceCast bool')
eq(#c.shooterProfiles.Mine.spells, 5, 'slots padded')
eq(c.selectedShooterProfile, 'Mine', 'selected profile repaired')
eq(c.unknownField.keep, 1, 'unknown fields round-trip')

-- migration: rules -> slots, once
local old = C.sanitize({ shooterProfiles = { Default = { rules = {
  { type = 'spell', spellId = 11, manaPercent = 40, creatures = 2, forceOnTarget = true, enabled = true },
  { type = 'rune', itemId = 3155, enabled = true },
  { type = 'spell', spellId = 12, manaPercent = 20, selfCast = true, enabled = false },
  { type = 'spell', spellId = 13, manaPercent = 10, enabled = true },
} } } })
local p = old.shooterProfiles.Default
eq(p.rules, nil, 'rules gone from the profile')
eq(p.spells[1].id, 11, 'first rule is slot 1')
eq(p.spells[1].percent, 40, 'mana percent kept')
eq(p.spells[1].forceCast, true, 'force kept')
eq(p.spells[2].id, 13, 'the rune and the disabled rule are skipped')
eq(p.legacyRules ~= nil, true, 'the old rules stay aside')
local again = C.sanitize(old)
eq(again.shooterProfiles.Default.spells[1].id, 11, 'second pass keeps the slots')

-- more than five rules
local many = {}
for i = 1, 8 do many[i] = { type = 'spell', spellId = 100 + i, enabled = true } end
local slots, dropped = C.rulesToSlots(many)
eq(#slots, 5, 'five slots')
eq(dropped, 3, 'three rules dropped')

-- slots <-> rules
local rules = C.slotsToRules({ { id = 7, percent = 30, creatures = 3, priority = 2 }, { id = 8, percent = 0, priority = 1 },
  { id = 0 } }, function(id) return { name = 'S' .. id, words = 'w' .. id } end)
eq(#rules, 2, 'empty slots give no rule')
eq(rules[1].spellId, 8, 'priority order')
eq(rules[2].creatures, 3, 'creatures')
eq(rules[2].name, 'S7', 'lookup name')

-- rotation view
local prof = C.newProfile()
local view = C.rotationView(prof)
view.rules = { { type = 'spell', spellId = 21, manaPercent = 50, enabled = true } }
eq(prof.spells[1].id, 21, 'writing rules sets the slots')
eq(view.rules[1].spellId, 21, 'reading rules gives rules')
view.chaosAutoRotation = true
eq(prof.chaosAutoRotation, true, 'the marker passes through')
eq(view.chaosAutoRotation, true, 'the marker reads back')

-- names
eq(C.nameProblem('', nil) ~= nil, true, 'empty name')
eq(C.nameProblem('abcdefghijklmnop', nil) ~= nil, true, 'long name')
eq(C.nameProblem('a/b', nil) ~= nil, true, 'bad character')
eq(C.nameProblem('Boss run', nil), nil, 'good name')
eq(C.nameProblem('Default', function(n) return n == 'Default' end) ~= nil, true, 'name in use')
local cfg = { shooterProfiles = { B = {}, A = {}, C = {} } }
eq(C.nextProfile(cfg, 'A'), 'B', 'next preset')
eq(C.nextProfile(cfg, 'C'), 'A', 'wraps')

-- hud
local h = C.sanitize({ botHud = { size = 'Huge', showEquipment = true } }).botHud
eq(h.size, 'Normal', 'bad hud size')
eq(h.showEquipment, nil, 'old hud section dropped')
eq(h.showHealing, true, 'new section default')

-- timers words
local tw = C.timerWords({ timerConfig = { rules = {
  { type = 'words', value = 'Utani Hur', enabled = true }, { type = 'words', value = 'utani hur' },
  { type = 'item', value = '5' }, { type = 'words', value = 'x', enabled = false } } } })
eq(#tw, 1, 'one distinct words rule')
eq(tw[1], 'utani hur', 'lower-cased')
local m = {}
eq(C.timersMigrated(m), false, 'not migrated')
C.markTimersMigrated(m)
eq(C.timersMigrated(m), true, 'migrated')

if fails > 0 then os.exit(1) end
print('helper_config_test: ok')
