-- luajit helperconfig_test.lua && lua5.3 helperconfig_test.lua (from the repository root or this folder)
-- ChaosHelperConfig: hand-edited helper.json and config.otml nodes are clamped to the helper's ranges on load, wrong
-- types fall back to defaults, lists are capped; the helper's reader (ChaosHelperSave.read) applies it.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helpersave.lua')
dofile(dir .. 'helperconfig.lua')
local HS, HC = ChaosHelperSave, ChaosHelperConfig
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- value checks
eq(HC.int(50, 0, 100, 7), 50, 'in range'); eq(HC.int(1000, 0, 100, 7), 100, 'clamped high')
eq(HC.int(-5, 0, 100, 7), 0, 'clamped low'); eq(HC.int('42', 0, 100, 7), 42, 'numeric string')
eq(HC.int(12.9, 0, 100, 7), 12, 'whole number'); eq(HC.int('x', 0, 100, 7), 7, 'text: default')
eq(HC.int(nil, 0, 100, 7), 7, 'nil: default'); eq(HC.int({}, 0, 100, 7), 7, 'table: default')
eq(HC.int(true, 0, 100, 7), 7, 'boolean: default'); eq(HC.int(0 / 0, 0, 100, 7), 7, 'NaN: default')
eq(HC.int(math.huge, 0, 100, 7), 7, 'inf: default'); eq(HC.int('1e999', 0, 100, 7), 7, 'inf string: default')
eq(HC.bool(true, false), true, 'bool'); eq(HC.bool('true', false), false, 'string is not a bool')
eq(HC.bool(1, true), true, 'number: default'); eq(HC.oneOf('min', { 'sec', 'min' }, 'x'), 'min', 'oneOf')
eq(HC.oneOf('day', { 'sec', 'min' }, 'x'), 'x', 'oneOf default'); eq(HC.text(('a'):rep(200), 128, ''):len(), 128, 'text capped')
eq(HC.text(5, 128, 'd'), 'd', 'text type')

-- ---------------------------------------------------------------- helper.json
local function hand()
  return {
    spells = { { id = 'abc', percent = 250 }, { id = 3, percent = -40 }, 'garbage', { id = 4.7, percent = '55' } },
    potions = { { id = 266, percent = 900, priority = 9 }, { id = -1, percent = 'x', priority = 'mana' } },
    training = { { id = 5, percent = 101, enabled = 'yes' } },
    haste = { { id = 6, enabled = 1, safecast = true, onlyWalking = 'no' } },
    paralyzeCure = { { id = 7, enabled = true } },
    staminaFood = { id = 8, enabled = true, thresholdMinutes = 99999 },
    specialFoods = { hp = { { id = 9, enabled = true, percent = 0, priority = 0 }, {}, {}, {}, {}, {} }, mana = 'x' },
    friendhealing = { knight = { enabled = 'true', percent = 5000, priority = 77 }, druid = 'x', paladin = { percent = 0 } },
    gransiohealing = { { name = 'old format' } },
    masreshealing = { extended = 'yes', sorcerer = { enabled = true, percent = 50, priority = 3 } },
    namedSio = { enabled = true, name = 'Friend', percent = 100 },
    -- settings of options the compact helper window removed (base patch 0105): an old file still loads without them
    autoQuillSell = true, autoQuillSellBelowCap = true, autoQuillSellCapacity = -3,
    quiverRefill = { enabled = true, itemId = 3447, minValue = 50, refillValue = 100 },
    magicShield = { utamoEnabled = true, utamoHpPercent = 70, exanaEnabled = true, exanaHpPercent = 90 },
    botHud = { enabled = true, showCavebot = true, showWaypoints = true, showTimers = true },
    autoTargetMode = 99,
    currentLockedTargetId = 'x',
    shooterProfiles = {
      Default = { autoTargetMode = 0, rules = {
        { type = 'spell', spellId = 10, manaPercent = 300, creatures = 50, enabled = 'x' },
        { type = 'weird', spellId = 11 },
        { type = 'rune', itemId = 3155, creatures = 0, countLowerThan = 'x' } } },
      Old = { spells = { { id = 1, percent = 120, creatures = 0, priority = 99 } }, runes = { { id = 3155, creatures = 11 } } },
      [7] = { rules = {} },
    },
    equipProfiles = { Default = { enabled = true, rules = {
      { id = 1, itemId = 3081, cond1Resource = 'hp%', cond1Operator = '<=', cond1Value = 400, condLogic = 'xor',
        cond2Enabled = true, cond2Resource = 'mp', cond2Operator = '!=', cond2Value = 123456789, action = 'drop' } } } },
    timerConfig = { ruleCounter = -2, rules = {
      { key = 'r1', type = 'words', value = 'utani hur', cooldown = 0, unit = 'sec', enabled = true },
      { key = 'r2', type = 'item', itemId = 'x', value = 'x', cooldown = 2.5, unit = 'day' },
      { key = 'r3', type = 'script', value = 'os.exit()', cooldown = 1 },
      { key = 'r4', type = 'words', value = 'exura', cooldown = 1e12, unit = 'hr' } } },
    selectedShooterProfile = 5,
    targetMonsterList = { 'x' },
    unknownField = { kept = true },
  }
end

local c = HC.sanitizeHelper(hand())
eq(#c.spells, 3, 'spell rows: the non-table row dropped')
eq(c.spells[1].id, 0, 'spell id text -> 0'); eq(c.spells[1].percent, 100, 'spell percent 250 -> 100')
eq(c.spells[2].percent, 0, 'spell percent -40 -> 0 (the helper makes 0 its default)'); eq(c.spells[3].id, 4, 'spell id whole')
eq(c.spells[3].percent, 55, 'spell percent from a numeric string')
eq(c.potions[1].percent, 100, 'potion percent'); eq(c.potions[1].priority, 2, 'potion priority 0..2')
eq(c.potions[2].id, 0, 'negative potion id -> 0'); eq(c.potions[2].percent, 50, 'potion percent text -> 50')
eq(c.potions[2].priority, 0, 'potion priority text -> 0')
eq(c.training[1].percent, 100, 'training percent'); eq(c.training[1].enabled, false, 'training enabled text -> false')
eq(c.haste[1].enabled, false, 'haste enabled number -> false'); eq(c.haste[1].safecast, true, 'haste bool kept')
eq(c.haste[1].onlyWalking, false, 'haste onlyWalking text -> false')
eq(c.staminaFood.thresholdMinutes, HC.STAMINA_MAX, 'stamina minutes clamped')
eq(#c.specialFoods.hp, 4, 'special foods capped at 4 slots'); eq(c.specialFoods.hp[1].percent, 1, 'special food percent >= 1')
eq(c.specialFoods.hp[1].priority, 1, 'special food priority >= 1'); eq(c.specialFoods.hp[2].percent, 80, 'empty slot: default 80')
eq(c.specialFoods.hp[3].priority, 3, 'empty slot: priority = its slot'); eq(c.specialFoods.mana, nil, 'mana not a list: dropped')
eq(c.friendhealing.knight.percent, 100, 'friend heal percent'); eq(c.friendhealing.knight.priority, 5, 'friend heal priority 1..5')
eq(c.friendhealing.knight.enabled, false, 'friend heal enabled text -> false'); eq(c.friendhealing.druid, nil, 'bad vocation entry dropped')
eq(c.friendhealing.paladin.percent, 1, 'friend heal percent >= 1'); eq(c.friendhealing.paladin.priority, 4, 'missing priority: default')
eq(c.gransiohealing[1].name, 'old format', 'old list format left for the helper to reset')
eq(c.masreshealing.extended, false, 'masres extended text -> false'); eq(c.masreshealing.sorcerer.percent, 50, 'good value kept')
eq(c.namedSio.percent, 99, 'named sio 1..99')
eq(c.autoTargetMode, 8, 'target mode 1..8')
eq(c.paralyzeCure, nil, '0105: Cure Paralyze dropped'); eq(c.quiverRefill, nil, '0105: Quiver Refill dropped')
eq(c.autoQuillSell, nil, '0105: Auto Sell Loot dropped'); eq(c.autoQuillSellBelowCap, nil, '0105: its below-cap switch')
eq(c.autoQuillSellCapacity, nil, '0105: its capacity')
eq(c.magicShield.exanaEnabled, nil, '0105: Exana Vita dropped'); eq(c.magicShield.exanaHpPercent, nil, '0105: its threshold')
eq(c.magicShield.utamoEnabled, true, 'Ward of the Mind kept'); eq(c.magicShield.utamoHpPercent, 70, 'its threshold kept')
eq(c.botHud.showCavebot, nil, '0105: HUD cavebot row dropped'); eq(c.botHud.showWaypoints, nil, '0105: HUD waypoints dropped')
eq(c.botHud.showTimers, true, 'other HUD rows kept')
eq(HC.sanitizeHelper({ magicShield = 'x', botHud = 5 }).magicShield, 'x', 'a dropped field of a non-table: no error')
eq(c.currentLockedTargetId, 0, 'locked target text -> 0')
local d = c.shooterProfiles.Default
eq(d.autoTargetMode, 1, 'profile target mode'); eq(#d.rules, 2, 'unknown rule type dropped')
eq(d.rules[1].manaPercent, 100, 'shooter mana percent'); eq(d.rules[1].creatures, 10, 'shooter creatures 1..10')
eq(d.rules[1].enabled, true, 'shooter enabled text -> true (default)'); eq(d.rules[2].creatures, 1, 'shooter creatures >= 1')
eq(d.rules[2].countLowerThan, false, 'countLowerThan text -> false')
eq(c.shooterProfiles.Old.spells[1].percent, 100, 'old format spell percent'); eq(c.shooterProfiles.Old.spells[1].priority, 20, 'old priority')
eq(c.shooterProfiles.Old.runes[1].creatures, 10, 'old rune creatures'); eq(c.shooterProfiles[7], nil, 'a profile without a name dropped')
local r = c.equipProfiles.Default.rules[1]
eq(r.cond1Value, 100, 'equip percent condition 0..100'); eq(r.condLogic, 'and', 'equip logic default')
eq(r.cond2Value, HC.ABSOLUTE_MAX, 'equip absolute condition capped'); eq(r.cond2Operator, '>=', 'equip operator default')
eq(r.action, 'equip', 'equip action default')
local t = c.timerConfig
eq(#t.rules, 3, 'timer rule of an unknown type dropped'); eq(t.rules[1].cooldown, 1, 'timer cooldown 0 -> 1 (no loop)')
eq(t.rules[2].cooldown, 2, 'timer cooldown whole'); eq(t.rules[2].unit, 'min', 'timer unit default'); eq(t.rules[2].itemId, 0, 'item id')
eq(t.rules[3].cooldown, HC.COOLDOWN_MAX, 'timer cooldown capped'); eq(t.rules[3].value, 'exura', 'words kept')
eq(t.rules[2].enabled, true, 'timer enabled default'); eq(t.ruleCounter, 0, 'rule counter >= 0')
eq(c.selectedShooterProfile, nil, 'a non-text profile name: the helper falls back to Default')
eq(c.targetMonsterList, nil, 'a non-text monster list dropped'); eq(c.unknownField.kept, true, 'unknown fields left alone')

-- a well-formed file is unchanged
local okCfg = { spells = { { id = 1, percent = 80 } }, potions = { { id = 266, percent = 50, priority = 1 } },
  timerConfig = { ruleCounter = 3, rules = { { key = 'a', type = 'words', value = 'utani hur', cooldown = 5, unit = 'sec',
  forceDecrease = false, inPz = false, inNonPz = true, targetingMonster = false, enabled = true } } },
  staminaFood = { id = 0, enabled = false, thresholdMinutes = 30 } }
local same = HC.sanitizeHelper(okCfg)
eq(same.spells[1].percent, 80, 'good spell'); eq(same.timerConfig.rules[1].cooldown, 5, 'good cooldown')
eq(same.timerConfig.rules[1].inNonPz, true, 'good flag'); eq(same.timerConfig.ruleCounter, 3, 'good counter')
eq(same.staminaFood.thresholdMinutes, 30, 'good minutes')
eq(HC.sanitizeHelper('x'), 'x', 'not a table: left to the reader')

-- caps: rows and rules
local many = { spells = {}, timerConfig = { rules = {} } }
for i = 1, 500 do
  many.spells[i] = { id = i, percent = 50 }
  many.timerConfig.rules[i] = { type = 'words', value = 'w' .. i, cooldown = 1, unit = 'sec' }
end
HC.sanitizeHelper(many)
eq(#many.spells, HC.ROWS_MAX, 'rows capped'); eq(#many.timerConfig.rules, HC.RULES_MAX, 'rules capped')

-- ---------------------------------------------------------------- the reader applies it
do
  local files = {}
  local fs = { exists = function(p) return files[p] ~= nil end, read = function(p) return files[p] end,
               write = function(p, x) files[p] = x end, copy = function(a, b) files[b] = files[a] end,
               delete = function(p) files[p] = nil end }
  files['helper.json'] = 'x'
  local value, status = HS.read(fs, 'helper.json', function() return { autoTargetMode = 42, staminaFood = 'x' } end)
  eq(status, 'ok', 'read ok'); eq(value.autoTargetMode, 8, 'the reader clamps'); eq(value.staminaFood, nil, 'and fixes types')
  local saved = HS.clean
  HS.clean = function() error('broken cleaner') end
  value = HS.read(fs, 'helper.json', function() return { autoTargetMode = 42 } end)
  eq(value.autoTargetMode, 42, 'a failing cleaner never loses the file')
  HS.clean = saved
end

-- ---------------------------------------------------------------- config.otml nodes
local p = HC.spellPrefs({ autoUpdate = 'true', ignored = { [12] = true, ['13'] = true, x = true, [14] = 'no', [-1] = true, [2.5] = true } })
eq(p.autoUpdate, true, 'autoUpdate from text "true" (the settings file stores text)')
eq(p.ignored[12], true, 'ignored id'); eq(p.ignored[13], true, 'ignored id from a text key')
eq(p.ignored.x, nil, 'text key dropped'); eq(p.ignored[14], nil, 'not true: dropped'); eq(p.ignored[-1], nil, 'negative dropped')
eq(p.ignored[2], nil, 'fraction dropped')
eq(HC.spellPrefs('x').autoUpdate, false, 'bad entry: defaults'); eq(next(HC.spellPrefs(nil).ignored), nil, 'nil entry')
local big = { ignored = {} }
for i = 1, 2000 do big.ignored[i] = true end
local n = 0
for _ in pairs(HC.spellPrefs(big).ignored) do n = n + 1 end
eq(n, 500, 'ignored list capped')
local w = HC.autosetupWords({ timerWords = { 'utani hur', 5, '', { 'x' }, ('a'):rep(300) } })
eq(#w, 2, 'only non-empty words'); eq(#w[2], HC.TEXT_MAX, 'long word capped')
eq(#HC.autosetupWords({ timerWords = 'x' }), 0, 'not a list'); eq(#HC.autosetupWords(nil), 0, 'no entry')

print(('helperconfig_test: %d checks, %s'):format(checks, fails == 0 and 'OK' or (fails .. ' FAILED')))
if fails > 0 then os.exit(1) end
